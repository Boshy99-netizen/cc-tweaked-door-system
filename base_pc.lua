-- ============================================
-- BASE SERVER v12.0
-- Headless backend; all setup via owner tablet.
-- 1 modem = 1 door. Pad monitors live on this PC via wired network.
-- ============================================

local KEY_CHANNEL    = 100
local REPLY_CHANNEL  = 101
local PING_TIMEOUT   = 2
local PAD_IDLE_CLEAR = 8

local OWNER_NAME = settings.get("base_owner") or ""

-- ============================================ STATE ============================================

local state = {
    locked         = false,
    doors          = {},   -- id -> door
    statusMonitor  = nil,  -- string or nil
}

local rt = {
    doorOpen       = {},   -- id -> bool
    manualOverride = {},   -- id -> bool
    activePings    = {},   -- player -> {time, doorIds}
    padInput       = {},   -- doorId -> {buffer, last, status, statusUntil}
    activeModems   = {},   -- list of modem names
    monitorOfDoor  = {},   -- monName -> doorId
    drawNeeded     = true, -- redraw status + all pads on next tick
}

local tpsLastReal, tpsCurrent = nil, 20.0

-- ============================================ UTILS ============================================

local function nameEq(a, b)
    return string.lower(tostring(a or "")) == string.lower(tostring(b or ""))
end

local function genDoorId()
    local i = 1
    while state.doors["door_" .. i] do i = i + 1 end
    return "door_" .. i
end

local function ensureDefaults(d)
    d.name         = d.name         or "Unnamed"
    d.relay        = d.relay        or ""
    d.relaySide    = d.relaySide    or "top"
    d.modem        = d.modem        or ""
    d.radius       = tonumber(d.radius) or 5
    d.normallyOn   = d.normallyOn   == true
    d.enabled      = d.enabled      ~= false
    d.allowedUsers = d.allowedUsers or {}
    d.passwords    = d.passwords    or {}
    d.padMonitor   = d.padMonitor   or nil
    return d
end

local function countTbl(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

local function sortedDoorIds()
    local ids = {}
    for id, _ in pairs(state.doors) do table.insert(ids, id) end
    table.sort(ids, function(a, b) return (state.doors[a].name or a) < (state.doors[b].name or b) end)
    return ids
end

local function rebuildMonitorMap()
    rt.monitorOfDoor = {}
    for id, d in pairs(state.doors) do
        if d.padMonitor and d.padMonitor ~= "" then
            rt.monitorOfDoor[d.padMonitor] = id
        end
    end
end

-- ============================================ PERSISTENCE ============================================

local function saveState()
    local payload = {
        owner = OWNER_NAME, locked = state.locked,
        doors = state.doors, statusMonitor = state.statusMonitor,
    }
    local ok, txt = pcall(textutils.serialize, payload)
    if not ok then return end
    local f = fs.open("base_state.dat", "w")
    if f then f.write(txt); f.close() end
end

local function loadState()
    if not fs.exists("base_state.dat") then return false end
    local f = fs.open("base_state.dat", "r"); if not f then return false end
    local txt = f.readAll(); f.close()
    local ok, d = pcall(textutils.unserialize, txt)
    if not ok or type(d) ~= "table" then return false end
    state.locked = d.locked == true
    state.doors = d.doors or {}
    state.statusMonitor = d.statusMonitor
    if d.owner and d.owner ~= "" then
        OWNER_NAME = d.owner
        settings.set("base_owner", OWNER_NAME); settings.save()
    end
    for _, dr in pairs(state.doors) do ensureDefaults(dr) end
    rebuildMonitorMap()
    return true
end

-- ============================================ PERIPHERALS ============================================

local function listByType(t)
    local r = {}
    for _, n in ipairs(peripheral.getNames()) do
        if peripheral.getType(n) == t then table.insert(r, n) end
    end
    table.sort(r); return r
end

local function openAllModems()
    rt.activeModems = {}
    for _, n in ipairs(listByType("modem")) do
        local m = peripheral.wrap(n)
        if m and m.open then
            pcall(m.open, KEY_CHANNEL)
            table.insert(rt.activeModems, n)
        end
    end
end

-- ============================================ DOOR ACTUATION ============================================

local function applyDoor(d, isOpen)
    if not d.relay or d.relay == "" then return end
    local r = peripheral.wrap(d.relay)
    if not r or not r.setOutput then return end
    local out = isOpen
    if d.normallyOn then out = not out end
    pcall(r.setOutput, d.relaySide or "top", out)
end

local function setDoorState(id, open)
    local d = state.doors[id]; if not d then return end
    rt.doorOpen[id] = open
    applyDoor(d, open)
    rt.drawNeeded = true
end

-- ============================================ ACCESS ============================================

local function userLevel(door, player)
    if nameEq(player, OWNER_NAME) then return "owner" end
    for n, lvl in pairs(door.allowedUsers) do
        if nameEq(n, player) then return lvl end
    end
    return nil
end

local function canOpen(door, player, keyType)
    if not door.enabled then return false end
    local lvl = userLevel(door, player)
    if not lvl then return false end
    if lvl == "owner" then return true end
    if keyType == "owner" then return false end
    if keyType == "team"  then return lvl == "team" end
    if state.locked then return false end
    return lvl == "guest" or lvl == "team"
end

-- ============================================ KEY PING ============================================

local function processPing(msg, distance, modemSide)
    if type(msg) ~= "table" or msg.type ~= "KEY_PING" then return end
    if type(distance) ~= "number" then return end
    local player  = msg.player
    local keyType = msg.keyType or "guest"
    if keyType == "owner" and not nameEq(player, OWNER_NAME) then return end

    local now = os.clock()
    for id, d in pairs(state.doors) do
        if d.modem == modemSide and distance <= d.radius then
            if canOpen(d, player, keyType) then
                local entry = rt.activePings[player] or { time = now, doorIds = {} }
                entry.time = now
                entry.doorIds[id] = true
                rt.activePings[player] = entry
                if not rt.doorOpen[id] then setDoorState(id, true) end
            end
        end
    end
end

-- ============================================ ACK + COMMANDS ============================================

local function ackTo(modemName, nonce, ok, reason)
    if not modemName then return end
    local m = peripheral.wrap(modemName)
    if m and m.transmit then
        m.transmit(REPLY_CHANNEL, KEY_CHANNEL, {
            type = "OWNER_ACK", nonce = nonce, success = ok, reason = reason,
        })
    end
end

local function handleOwnerCommand(message, sourceModem)
    local function ack(s, r) ackTo(sourceModem, message.nonce, s, r) end

    -- Bootstrap: first claim wins when no owner is set
    if OWNER_NAME == "" then
        if message.command == "claim_owner" and type(message.player) == "string" and message.player ~= "" then
            OWNER_NAME = message.player
            settings.set("base_owner", OWNER_NAME); settings.save()
            saveState()
            print("[OWNER] base claimed by " .. OWNER_NAME)
            ack(true, "claimed"); return
        else
            ack(false, "no owner; send claim_owner"); return
        end
    end

    if not nameEq(message.player, OWNER_NAME) then
        ack(false, "name mismatch"); return
    end

    local cmd  = message.command
    local data = message.data or {}
    print("[CMD] " .. tostring(cmd))

    if cmd == "claim_owner" then
        ack(false, "already owned by " .. OWNER_NAME); return

    elseif cmd == "set_owner" then
        if type(data.name) == "string" and data.name ~= "" then
            OWNER_NAME = data.name
            settings.set("base_owner", OWNER_NAME); settings.save()
            saveState()
        else ack(false, "no name"); return end

    elseif cmd == "set_status_monitor" then
        state.statusMonitor = (data.monitor ~= "" and data.monitor) or nil
        rt.drawNeeded = true
        saveState()

    elseif cmd == "toggle_lock" then
        state.locked = not state.locked
        rt.drawNeeded = true
        saveState()

    elseif cmd == "set_lock" then
        state.locked = data.locked == true
        rt.drawNeeded = true
        saveState()

    elseif cmd == "door_add" then
        local id = genDoorId()
        local d = ensureDefaults({
            id = id,
            name       = (data.name and data.name ~= "") and data.name or ("Door " .. id),
            relay      = data.relay or "",
            relaySide  = data.relaySide or "top",
            modem      = data.modem or "",
            radius     = tonumber(data.radius) or 5,
            normallyOn = data.normallyOn == true,
            enabled    = data.enabled ~= false,
        })
        state.doors[id] = d
        applyDoor(d, false)
        saveState()
        ack(true, id); return

    elseif cmd == "door_remove" then
        local id = data.id; if not id or not state.doors[id] then ack(false, "no door"); return end
        applyDoor(state.doors[id], false)
        local pad = state.doors[id].padMonitor
        state.doors[id] = nil
        rt.doorOpen[id] = nil; rt.manualOverride[id] = nil; rt.padInput[id] = nil
        rebuildMonitorMap()
        if pad then
            local m = peripheral.wrap(pad)
            if m and m.clear then pcall(function() m.setBackgroundColor(colors.black); m.clear() end) end
        end
        saveState()

    elseif cmd == "door_update" then
        local id = data.id; local d = id and state.doors[id]
        if not d then ack(false, "no door"); return end
        local relayChanged = false
        for _, k in ipairs({"name","relay","relaySide","modem","radius","normallyOn","enabled"}) do
            if data[k] ~= nil then
                if (k == "relay" or k == "relaySide" or k == "normallyOn") and d[k] ~= data[k] then
                    relayChanged = true
                end
                d[k] = data[k]
            end
        end
        d.radius = tonumber(d.radius) or 5
        ensureDefaults(d)
        if relayChanged then applyDoor(d, rt.doorOpen[id] == true) end
        rt.drawNeeded = true
        saveState()

    elseif cmd == "door_set_pad" then
        local id = data.id; local d = id and state.doors[id]
        if not d then ack(false, "no door"); return end
        local newPad = (data.monitor ~= "" and data.monitor) or nil
        if d.padMonitor and d.padMonitor ~= newPad then
            local m = peripheral.wrap(d.padMonitor)
            if m and m.clear then pcall(function() m.setBackgroundColor(colors.black); m.clear() end) end
        end
        d.padMonitor = newPad
        rt.padInput[id] = nil
        rebuildMonitorMap()
        rt.drawNeeded = true
        saveState()

    elseif cmd == "door_user_set" then
        local id = data.id; local d = id and state.doors[id]
        if not d then ack(false, "no door"); return end
        local user, level = data.user, data.level
        if not user or user == "" then ack(false, "no user"); return end
        for k, _ in pairs(d.allowedUsers) do
            if nameEq(k, user) then d.allowedUsers[k] = nil end
        end
        if level == "guest" or level == "team" then
            d.allowedUsers[user] = level
        end
        saveState()

    elseif cmd == "door_pwd_add" then
        local id = data.id; local d = id and state.doors[id]
        if not d then ack(false, "no door"); return end
        local pw = data.password
        if not pw or pw == "" then ack(false, "empty pwd"); return end
        for _, p in ipairs(d.passwords) do
            if p == pw then ack(false, "exists"); return end
        end
        table.insert(d.passwords, pw)
        saveState()

    elseif cmd == "door_pwd_remove" then
        local id = data.id; local d = id and state.doors[id]
        if not d then ack(false, "no door"); return end
        local pw = data.password
        for i, p in ipairs(d.passwords) do
            if p == pw then table.remove(d.passwords, i); saveState(); ack(true, nil); return end
        end
        ack(false, "not found"); return

    else
        ack(false, "unknown: " .. tostring(cmd)); return
    end

    ack(true, nil)
end

-- ============================================ PASSWORD PAD UI ============================================
-- Renders a numeric keypad on each door's padMonitor (if assigned).
-- Layout assumes a 2x2 monitor (~29x19) at scale 1, but works for any size >= 18x12.

local PAD_KEYS = {
    {"1","2","3"},
    {"4","5","6"},
    {"7","8","9"},
    {"C","0","OK"},
}

-- Build button rectangles for a given monitor size; returns layout {keys=[{ch,x1,y1,x2,y2}], display={x,y,w}}
local function padLayout(w, h)
    local btnW = math.max(4, math.floor((w - 4) / 3))
    local btnH = math.max(2, math.floor((h - 6) / 5))
    local startX = math.floor((w - (btnW * 3 + 2)) / 2) + 1
    local startY = h - (btnH * 4 + 3)
    if startY < 5 then startY = 5 end
    local keys = {}
    for r = 1, 4 do
        for c = 1, 3 do
            local x1 = startX + (c - 1) * (btnW + 1)
            local y1 = startY + (r - 1) * (btnH + 1) - 1
            local x2 = x1 + btnW - 1
            local y2 = y1 + btnH - 1
            table.insert(keys, { ch = PAD_KEYS[r][c], x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
        end
    end
    return { keys = keys, displayY = startY - 3 }
end

local function fillRect(mon, x1, y1, x2, y2, bg)
    mon.setBackgroundColor(bg)
    for y = y1, y2 do
        mon.setCursorPos(x1, y)
        mon.write(string.rep(" ", x2 - x1 + 1))
    end
end

local function padHash(door, input)
    local s = (input and input.buffer or "") .. "|"
    s = s .. (input and input.status or "") .. "|"
    s = s .. tostring(state.locked) .. "|" .. tostring(door.enabled) .. "|" .. door.name
    return s
end

local prevPadHash = {}

local function drawPad(doorId, force)
    local d = state.doors[doorId]; if not d or not d.padMonitor then return end
    local mon = peripheral.wrap(d.padMonitor); if not mon then return end

    local input = rt.padInput[doorId] or { buffer = "", last = 0, status = "", statusUntil = 0 }
    local h = padHash(d, input)
    if not force and prevPadHash[doorId] == h then return end
    prevPadHash[doorId] = h

    pcall(mon.setTextScale, 1)
    mon.setBackgroundColor(colors.black)
    mon.clear()
    local w, mh = mon.getSize()

    -- Header
    mon.setBackgroundColor(colors.gray)
    mon.setTextColor(colors.white)
    for x = 1, w do mon.setCursorPos(x, 1); mon.write(" ") end
    local title = d.name
    if #title > w - 2 then title = title:sub(1, w - 2) end
    mon.setCursorPos(math.floor((w - #title) / 2) + 1, 1); mon.write(title)
    mon.setBackgroundColor(colors.black)

    local L = padLayout(w, mh)

    -- Display field
    local masked = string.rep("*", #input.buffer)
    if masked == "" then masked = "(enter password)" end
    local maxLen = w - 4
    if #masked > maxLen then masked = masked:sub(-maxLen) end
    mon.setCursorPos(2, L.displayY)
    mon.setBackgroundColor(colors.gray)
    mon.setTextColor(colors.yellow)
    mon.write(" " .. masked .. string.rep(" ", w - 3 - #masked) .. " ")
    mon.setBackgroundColor(colors.black)

    -- Status line (right above keypad)
    if input.status and input.status ~= "" then
        local color = colors.lightGray
        if input.status:sub(1, 2) == "OK" then color = colors.lime
        elseif input.status:sub(1, 4) == "WRONG" or input.status:sub(1, 4) == "FAIL" then color = colors.red end
        mon.setTextColor(color)
        local txt = input.status
        if #txt > w - 2 then txt = txt:sub(1, w - 2) end
        mon.setCursorPos(math.floor((w - #txt) / 2) + 1, L.displayY + 1)
        mon.write(txt)
    end

    -- Buttons
    for _, k in ipairs(L.keys) do
        local bg, fg = colors.lightGray, colors.black
        if k.ch == "OK" then bg, fg = colors.green, colors.white
        elseif k.ch == "C" then bg, fg = colors.red, colors.white end
        fillRect(mon, k.x1, k.y1, k.x2, k.y2, bg)
        local cy = math.floor((k.y1 + k.y2) / 2)
        local cx = math.floor((k.x1 + k.x2) / 2) - math.floor(#k.ch / 2) + 1
        mon.setCursorPos(cx, cy)
        mon.setBackgroundColor(bg); mon.setTextColor(fg)
        mon.write(k.ch)
    end
    mon.setBackgroundColor(colors.black)
end

local function drawAllPads(force)
    for id, _ in pairs(state.doors) do
        if state.doors[id].padMonitor then drawPad(id, force) end
    end
end

-- Returns clicked key char or nil
local function padHitTest(monName, mx, my)
    local mon = peripheral.wrap(monName); if not mon then return nil end
    local w, h = mon.getSize()
    local L = padLayout(w, h)
    for _, k in ipairs(L.keys) do
        if mx >= k.x1 and mx <= k.x2 and my >= k.y1 and my <= k.y2 then
            return k.ch
        end
    end
    return nil
end

local function handlePadTouch(monName, x, y)
    local doorId = rt.monitorOfDoor[monName]; if not doorId then return end
    local d = state.doors[doorId]; if not d then return end
    local key = padHitTest(monName, x, y); if not key then return end

    local inp = rt.padInput[doorId] or { buffer = "", last = 0, status = "", statusUntil = 0 }
    inp.last = os.clock()

    if key == "C" then
        inp.buffer = ""; inp.status = ""
    elseif key == "OK" then
        local pw = inp.buffer
        inp.buffer = ""
        local matched = false
        if d.enabled then
            for _, p in ipairs(d.passwords) do
                if p == pw then matched = true; break end
            end
        end
        if matched then
            inp.status = "OK"
            inp.statusUntil = os.clock() + 2
            -- Open via activePings so the standard auto-close timer applies
            local entry = rt.activePings["__pad_" .. doorId] or { time = os.clock(), doorIds = {} }
            entry.time = os.clock()
            entry.doorIds[doorId] = true
            rt.activePings["__pad_" .. doorId] = entry
            if not rt.doorOpen[doorId] then setDoorState(doorId, true) end
            print("[PAD] " .. d.name .. " OK")
        else
            inp.status = d.enabled and "WRONG" or "FAIL: disabled"
            inp.statusUntil = os.clock() + 2
            print("[PAD] " .. d.name .. " wrong password")
        end
    else
        if #inp.buffer < 16 then inp.buffer = inp.buffer .. key end
        inp.status = ""
    end

    rt.padInput[doorId] = inp
    drawPad(doorId, true)
end

local function tickPads()
    local now = os.clock()
    for id, inp in pairs(rt.padInput) do
        local stale = false
        if inp.buffer ~= "" and (now - inp.last) > PAD_IDLE_CLEAR then
            inp.buffer = ""; stale = true
        end
        if inp.status and inp.status ~= "" and inp.statusUntil and now > inp.statusUntil then
            inp.status = ""; stale = true
        end
        if stale then drawPad(id, true) end
    end
end

-- ============================================ STATUS MONITOR ============================================

local prevStatusHash = nil
local function drawStatus()
    local mn = state.statusMonitor; if not mn then return end
    local mon = peripheral.wrap(mn); if not mon then return end
    local h = tostring(state.locked) .. "|" .. OWNER_NAME
    if h == prevStatusHash then return end
    prevStatusHash = h

    pcall(mon.setTextScale, 1.5)
    mon.setBackgroundColor(colors.black); mon.clear()
    local w, mh = mon.getSize()
    -- Frame
    mon.setTextColor(colors.gray)
    mon.setCursorPos(1, 1); mon.write("+"); mon.setCursorPos(w, 1); mon.write("+")
    mon.setCursorPos(1, mh); mon.write("+"); mon.setCursorPos(w, mh); mon.write("+")
    for x = 2, w - 1 do mon.setCursorPos(x, 1); mon.write("="); mon.setCursorPos(x, mh); mon.write("=") end
    for y = 2, mh - 1 do mon.setCursorPos(1, y); mon.write("|"); mon.setCursorPos(w, y); mon.write("|") end

    local title = (OWNER_NAME ~= "" and ("Base " .. OWNER_NAME)) or "Base"
    mon.setTextColor(colors.white)
    mon.setCursorPos(math.floor((w - #title) / 2) + 1, 3); mon.write(title)
    mon.setTextColor(colors.lightGray)
    local sub = "Base Status"
    mon.setCursorPos(math.floor((w - #sub) / 2) + 1, 5); mon.write(sub)
    local lbl = state.locked and "LOCKED" or "OPEN"
    mon.setTextColor(state.locked and colors.red or colors.lime)
    mon.setCursorPos(math.floor((w - #lbl) / 2) + 1, 7); mon.write(lbl)
end

-- ============================================ BROADCASTS ============================================

local function buildDoorsSummary()
    local r = {}
    for _, id in ipairs(sortedDoorIds()) do
        local d = state.doors[id]
        table.insert(r, {
            id = id, name = d.name,
            open     = rt.doorOpen[id] == true,
            override = rt.manualOverride[id] == true,
            enabled  = d.enabled,
        })
    end
    return r
end

local function buildDoorsFull(includePasswords)
    local r = {}
    for _, id in ipairs(sortedDoorIds()) do
        local d = state.doors[id]
        local users = {}
        for n, lvl in pairs(d.allowedUsers) do
            table.insert(users, { name = n, level = lvl })
        end
        table.sort(users, function(a, b) return a.name < b.name end)
        local entry = {
            id = id, name = d.name,
            relay = d.relay, relaySide = d.relaySide,
            modem = d.modem, radius = d.radius,
            normallyOn = d.normallyOn, enabled = d.enabled,
            padMonitor = d.padMonitor,
            users = users, passwordCount = #d.passwords,
            open = rt.doorOpen[id] == true,
            override = rt.manualOverride[id] == true,
        }
        if includePasswords then
            entry.passwords = {}
            for i, p in ipairs(d.passwords) do entry.passwords[i] = p end
        end
        table.insert(r, entry)
    end
    return r
end

local function transmitTo(modemName, payload)
    if not modemName then return end
    local m = peripheral.wrap(modemName)
    if m and m.transmit then m.transmit(REPLY_CHANNEL, KEY_CHANNEL, payload) end
end

local function broadcastBaseStatus(modemSide)
    local payload = {
        type = "BASE_STATUS",
        locked = state.locked, owner = OWNER_NAME,
        tps = tpsCurrent, gameTime = os.time(), gameDay = os.day(),
        doors = buildDoorsSummary(),
    }
    if modemSide then transmitTo(modemSide, payload)
    else for _, n in ipairs(rt.activeModems) do transmitTo(n, payload) end end
end

local function sendDoorsFull(modemName, includePasswords)
    transmitTo(modemName, { type = "DOORS_FULL", doors = buildDoorsFull(includePasswords) })
end

local function sendPeripherals(modemName)
    transmitTo(modemName, {
        type     = "PERIPHERAL_LIST",
        relays   = listByType("redstone_relay"),
        modems   = listByType("modem"),
        monitors = listByType("monitor"),
        statusMonitor = state.statusMonitor,
    })
end

-- ============================================ AUTO-CLOSE LOOP ============================================

local function tickAutoClose()
    local now = os.clock()
    -- Track which doors have any active ping
    local active = {}
    for player, data in pairs(rt.activePings) do
        if now - data.time < PING_TIMEOUT then
            for id, _ in pairs(data.doorIds) do active[id] = true end
        else
            rt.activePings[player] = nil
        end
    end
    local changed = false
    for id, _ in pairs(state.doors) do
        if not active[id] and not rt.manualOverride[id] and rt.doorOpen[id] then
            setDoorState(id, false); changed = true
        end
    end
    if changed then rt.drawNeeded = true end
end

-- ============================================ KEYBOARD CONSOLE ============================================

local function consoleHelp()
    print("Commands:")
    print("  doors      list doors")
    print("  peri       list peripherals")
    print("  owner      show owner")
    print("  reset-all  delete state, restart")
    print("  reboot     reboot")
end

local function consoleLoop()
    print("=== BASE SERVER v12 ===")
    if OWNER_NAME == "" then
        print("[!] No owner. Run owner.lua on a tablet to claim this base.")
    else
        print("Owner: " .. OWNER_NAME)
    end
    print("Doors: " .. countTbl(state.doors) .. ". Type 'help' for commands.")
    while true do
        write("> ")
        local line = read()
        if line == "help" then consoleHelp()
        elseif line == "doors" then
            for _, id in ipairs(sortedDoorIds()) do
                local d = state.doors[id]
                print(("%s | %s | relay=%s/%s modem=%s r=%d open=%s pad=%s"):format(
                    id, d.name, d.relay, d.relaySide, d.modem, d.radius,
                    tostring(rt.doorOpen[id] == true), tostring(d.padMonitor or "-")))
            end
        elseif line == "peri" then
            print("Relays:");   for _, n in ipairs(listByType("redstone_relay")) do print("  " .. n) end
            print("Modems:");   for _, n in ipairs(listByType("modem")) do print("  " .. n) end
            print("Monitors:"); for _, n in ipairs(listByType("monitor")) do print("  " .. n) end
        elseif line == "owner" then print("Owner: " .. (OWNER_NAME ~= "" and OWNER_NAME or "(unset)"))
        elseif line == "reset-all" then
            print("Type 'YES' to wipe state:"); local c = read()
            if c == "YES" then
                fs.delete("base_state.dat")
                settings.unset("base_owner"); settings.save()
                print("Wiped. Rebooting..."); sleep(1); os.reboot()
            end
        elseif line == "reboot" then os.reboot()
        elseif line and line ~= "" then print("Unknown. Type 'help'.") end
    end
end

-- ============================================ MAIN NETWORK LOOP ============================================

local function networkLoop()
    rt.drawNeeded = true
    drawStatus(); drawAllPads(true)
    local statusTimer = os.startTimer(0.5)
    local broadcastTimer = os.startTimer(2)
    local padTickTimer = os.startTimer(1)

    while true do
        local event = { os.pullEvent() }
        local ev = event[1]

        if ev == "timer" then
            local id = event[2]
            -- TPS measurement (any timer fire counts; smoothed)
            local nowReal = os.epoch("utc")
            if tpsLastReal and id == statusTimer then
                local delta = nowReal - tpsLastReal
                if delta > 0 then
                    local instant = math.min(20, 500 / delta * 20)
                    tpsCurrent = tpsCurrent * 0.7 + instant * 0.3
                end
            end
            if id == statusTimer then
                tpsLastReal = nowReal
                tickAutoClose()
                tickPads()
                if rt.drawNeeded then
                    drawStatus(); drawAllPads(false)
                    rt.drawNeeded = false
                end
                statusTimer = os.startTimer(0.5)
            elseif id == broadcastTimer then
                broadcastBaseStatus()
                broadcastTimer = os.startTimer(2)
            elseif id == padTickTimer then
                tickPads()
                padTickTimer = os.startTimer(1)
            end

        elseif ev == "modem_message" then
            local side, ch, _, message, distance = event[2], event[3], event[4], event[5], event[6]
            if ch == KEY_CHANNEL and type(message) == "table" then
                local mt = message.type
                if mt == "KEY_PING" then
                    processPing(message, distance, side)
                    if message.keyType == "owner" and nameEq(message.player, OWNER_NAME) then
                        broadcastBaseStatus(side)
                    end

                elseif mt == "OWNER_COMMAND" then
                    handleOwnerCommand(message, side)
                    broadcastBaseStatus(side)

                elseif mt == "REQUEST_DOORS" then
                    if nameEq(message.player, OWNER_NAME) then
                        sendDoorsFull(side, true)
                    else
                        sendDoorsFull(side, false)
                    end

                elseif mt == "REQUEST_PERIPHERALS" then
                    if nameEq(message.player, OWNER_NAME) then sendPeripherals(side) end

                elseif mt == "PING_REQUEST" then
                    transmitTo(side, {
                        type = "PING_REPLY", nonce = message.nonce,
                        tps = tpsCurrent, gameTime = os.time(), gameDay = os.day(),
                    })
                end
            end

        elseif ev == "monitor_touch" then
            local monName, x, y = event[2], event[3], event[4]
            if rt.monitorOfDoor[monName] then
                handlePadTouch(monName, x, y)
            end

        elseif ev == "peripheral" then
            local n = event[2]
            if n then
                local t = peripheral.getType(n)
                if t == "modem" then openAllModems()
                elseif t == "monitor" and rt.monitorOfDoor[n] then
                    drawPad(rt.monitorOfDoor[n], true)
                end
            end
        elseif ev == "peripheral_detach" then
            -- nothing to do; will retry on reconnect
        end
    end
end

-- ============================================ STARTUP ============================================

loadState()
openAllModems()

parallel.waitForAny(networkLoop, consoleLoop)
