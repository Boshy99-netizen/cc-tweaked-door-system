-- ============================================
-- BASE SERVER v12.0
-- Headless backend; all setup via owner tablet.
-- 1 modem = 1 door. Pad monitors live on this PC via wired network.
-- ============================================

local KEY_CHANNEL    = 100
local REPLY_CHANNEL  = 101
local PING_TIMEOUT   = 2
local PAD_IDLE_CLEAR = 8

-- ============================================ HASH ============================================
-- Same djb2+salt as owner.lua so hashes generated on either side compare.
local function hashPin(pin, salt)
    salt = salt or "base"
    local h = 5381
    local s = salt .. "|" .. pin .. "|" .. salt
    for i = 1, #s do
        h = ((h * 33) + string.byte(s, i)) % 0x100000000
    end
    for _ = 1, 1000 do
        h = ((h * 33) + (h % 257)) % 0x100000000
    end
    return string.format("%08x", h)
end

local OWNER_NAME = settings.get("base_owner") or ""

-- ============================================ STATE ============================================

local state = {
    locked         = false,
    doors          = {},   -- id -> door
    statusMonitor  = nil,  -- string or nil
    basePin        = nil,  -- hash string or nil; protects W (wipe) on dashboard
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
        basePin = state.basePin,
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
    state.basePin = d.basePin
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

-- Idempotency cache for owner commands: nonce -> {success, reason, expiry}
local nonceCache = {}
local NONCE_TTL = 15  -- seconds; long enough for 3 retries x 0.7s each

local function ackTo(modemName, nonce, ok, reason)
    if not modemName then return end
    local m = peripheral.wrap(modemName)
    if m and m.transmit then
        m.transmit(REPLY_CHANNEL, KEY_CHANNEL, {
            type = "OWNER_ACK", nonce = nonce, success = ok, reason = reason,
        })
    end
end

local function tickNonceCache()
    local now = os.clock()
    for n, e in pairs(nonceCache) do
        if e.expiry < now then nonceCache[n] = nil end
    end
end

local function handleOwnerCommand(message, sourceModem)
    local nonce = message.nonce

    -- Idempotency: if we've seen this nonce recently, just re-send the cached ack
    if nonce and nonceCache[nonce] then
        local cached = nonceCache[nonce]
        ackTo(sourceModem, nonce, cached.success, cached.reason)
        return
    end

    local function ack(s, r)
        ackTo(sourceModem, nonce, s, r)
        if nonce then
            nonceCache[nonce] = { success = s, reason = r, expiry = os.clock() + NONCE_TTL }
        end
    end

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

    elseif cmd == "set_base_pin" then
        -- data = { pinHash = "..." } or { pinHash = nil } to clear
        if type(data.pinHash) == "string" and data.pinHash ~= "" then
            state.basePin = data.pinHash
            saveState()
        elseif data.pinHash == nil or data.pinHash == "" then
            state.basePin = nil
            saveState()
        end

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

-- Compute layout for a given (effective) monitor size.
-- Returns nil if size too small to fit a usable keypad.
local function computePadLayout(w, h)
    -- Header (1) + display (1) + status (1) + spacing (3) + 4 button rows + 3 row gaps = need >= 8 for keypad zone
    -- Buttons: at minimum 3w x 1h each, plus 2 horizontal gaps -> >= 11 wide
    if w < 11 or h < 8 then return nil end

    -- Keypad zone starts at row 4, ends at h-1
    local zoneTop = 4
    local zoneBottom = h - 1
    local zoneH = zoneBottom - zoneTop + 1
    -- 4 button rows + 3 gaps between them; each row at least 1 high
    local btnH = math.max(1, math.floor((zoneH - 3) / 4))
    if btnH < 1 then return nil end
    local rowGap = (zoneH - 4 * btnH >= 3) and 1 or 0

    local btnW = math.max(3, math.floor((w - 4) / 3))
    local colGap = (w - 3 * btnW >= 4) and 1 or 0

    local startX = math.floor((w - (btnW * 3 + 2 * colGap)) / 2) + 1
    if startX < 2 then startX = 2 end

    local totalH = btnH * 4 + rowGap * 3
    local startY = zoneTop + math.max(0, math.floor((zoneH - totalH) / 2))

    local keys = {}
    for r = 1, 4 do
        for c = 1, 3 do
            local x1 = startX + (c - 1) * (btnW + colGap)
            local y1 = startY + (r - 1) * (btnH + rowGap)
            local x2 = x1 + btnW - 1
            local y2 = y1 + btnH - 1
            table.insert(keys, { ch = PAD_KEYS[r][c], x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
        end
    end

    return {
        keys = keys,
        displayY = 3,
        statusY = startY - 1,
    }
end

-- Try to find the best text scale that gives a usable layout.
-- Returns scale, layout, w, h. May return nil layout if monitor too small at any scale.
local SCALES = { 1, 0.5, 1.5, 2, 2.5, 3 }
local function findScaleAndLayout(mon)
    -- Try preferred order: 1, 0.5 (smaller text = more room), then bigger.
    for _, s in ipairs(SCALES) do
        pcall(mon.setTextScale, s)
        local w, h = mon.getSize()
        local L = computePadLayout(w, h)
        if L then return s, L, w, h end
    end
    -- Last attempt at smallest text
    pcall(mon.setTextScale, 0.5)
    local w, h = mon.getSize()
    return 0.5, nil, w, h
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
-- Cache the layout per monitor so touch handler can use the SAME layout used to render
local padLayoutCache = {}  -- monName -> {layout, scale, w, h}

local function drawPad(doorId, force)
    local d = state.doors[doorId]; if not d or not d.padMonitor then return end
    local mon = peripheral.wrap(d.padMonitor); if not mon then return end

    local input = rt.padInput[doorId] or { buffer = "", last = 0, status = "", statusUntil = 0 }
    local h = padHash(d, input)
    if not force and prevPadHash[doorId] == h then return end
    prevPadHash[doorId] = h

    local scale, L, w, mh = findScaleAndLayout(mon)
    padLayoutCache[d.padMonitor] = { layout = L, scale = scale, w = w, h = mh }

    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- Header
    mon.setBackgroundColor(colors.gray)
    mon.setTextColor(colors.white)
    for x = 1, w do mon.setCursorPos(x, 1); mon.write(" ") end
    local title = d.name
    if #title > w - 2 then title = title:sub(1, w - 2) end
    mon.setCursorPos(math.floor((w - #title) / 2) + 1, 1); mon.write(title)
    mon.setBackgroundColor(colors.black)

    if not L then
        -- Monitor too small for keypad: show name + state warning
        mon.setTextColor(colors.red)
        local msg = "Too small"
        if #msg > w then msg = msg:sub(1, w) end
        mon.setCursorPos(math.max(1, math.floor((w - #msg) / 2) + 1), math.max(2, math.floor(mh / 2)))
        mon.write(msg)
        return
    end

    -- Display field (password buffer)
    local masked = string.rep("*", #input.buffer)
    if masked == "" then masked = "(enter pwd)" end
    local maxLen = w - 4
    if #masked > maxLen then masked = masked:sub(-maxLen) end
    mon.setCursorPos(2, L.displayY)
    mon.setBackgroundColor(colors.gray)
    mon.setTextColor(colors.yellow)
    local pad = w - 3 - #masked
    if pad < 0 then pad = 0 end
    mon.write(" " .. masked .. string.rep(" ", pad) .. " ")
    mon.setBackgroundColor(colors.black)

    -- Status line above keypad
    if input.status and input.status ~= "" and L.statusY and L.statusY >= 2 then
        local color = colors.lightGray
        if input.status:sub(1, 2) == "OK" then color = colors.lime
        elseif input.status:sub(1, 4) == "WRONG" or input.status:sub(1, 4) == "FAIL" then color = colors.red end
        mon.setTextColor(color)
        local txt = input.status
        if #txt > w - 2 then txt = txt:sub(1, w - 2) end
        mon.setCursorPos(math.floor((w - #txt) / 2) + 1, L.statusY)
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

-- Use the cached layout the pad was rendered with (the touch coordinates come
-- from the same scale the monitor is currently at).
local function padHitTest(monName, mx, my)
    local cached = padLayoutCache[monName]
    if not cached or not cached.layout then return nil end
    for _, k in ipairs(cached.layout.keys) do
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

-- ============================================ BASE TERMINAL DASHBOARD ============================================
-- Renders to the base PC's own screen (term.*). Shows live state of all doors,
-- lock state, owner, peripherals. Bottom bar has key shortcuts.

local prevTermHash = nil

local function drawTermDashboard(force)
    -- Build a snapshot hash so we don't redraw if nothing changed
    local parts = { OWNER_NAME, tostring(state.locked), tostring(state.statusMonitor or "-"),
                    state.basePin and "pin:set" or "pin:none" }
    for _, id in ipairs(sortedDoorIds()) do
        local d = state.doors[id]
        table.insert(parts, id .. ":" .. d.name .. ":" ..
            tostring(rt.doorOpen[id] == true) .. ":" ..
            tostring(d.enabled) .. ":" ..
            (d.padMonitor or "-") .. ":" ..
            d.modem .. ":" .. d.relay)
    end
    local hash = table.concat(parts, "|")
    if not force and hash == prevTermHash then return end
    prevTermHash = hash

    term.setBackgroundColor(colors.black)
    term.clear()
    local w, h = term.getSize()

    -- Header bar
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    for x = 1, w do term.setCursorPos(x, 1); term.write(" ") end
    term.setCursorPos(2, 1); term.write("BASE v12")
    local right = state.locked and "LOCKED" or "OPEN"
    term.setTextColor(state.locked and colors.red or colors.lime)
    term.setCursorPos(w - #right, 1); term.write(right)
    term.setBackgroundColor(colors.black)

    -- Owner line
    term.setTextColor(colors.lightGray)
    term.setCursorPos(2, 3); term.write("Owner: ")
    term.setTextColor(colors.white)
    term.write(OWNER_NAME ~= "" and OWNER_NAME or "(unclaimed - use tablet)")

    term.setTextColor(colors.lightGray)
    term.setCursorPos(2, 4); term.write("Doors: ")
    term.setTextColor(colors.white); term.write(tostring(countTbl(state.doors)))

    term.setTextColor(colors.lightGray)
    term.setCursorPos(2, 5); term.write("Status mon: ")
    term.setTextColor(state.statusMonitor and colors.white or colors.gray)
    term.write(state.statusMonitor or "(none)")

    term.setTextColor(colors.lightGray)
    term.setCursorPos(2, 6); term.write("Wipe PIN: ")
    if state.basePin and state.basePin ~= "" then
        term.setTextColor(colors.lime); term.write("set")
    else
        term.setTextColor(colors.gray); term.write("(none - W will only ask YES)")
    end

    -- Door table
    term.setTextColor(colors.gray)
    term.setCursorPos(2, 8); term.write(string.rep("-", w - 2))
    term.setTextColor(colors.white)
    term.setCursorPos(2, 9); term.write("NAME")
    term.setCursorPos(15, 9); term.write("STATE")
    term.setCursorPos(23, 9); term.write("MODEM")
    term.setCursorPos(35, 9); term.write("PAD")
    term.setCursorPos(2, 10); term.setTextColor(colors.gray); term.write(string.rep("-", w - 2))

    local y = 11
    local ids = sortedDoorIds()
    if #ids == 0 then
        term.setTextColor(colors.gray)
        term.setCursorPos(2, y); term.write("(no doors yet - add via tablet)")
    else
        for _, id in ipairs(ids) do
            if y >= h - 2 then
                term.setTextColor(colors.gray)
                term.setCursorPos(2, y); term.write("...and " .. (#ids - (y - 11)) .. " more")
                break
            end
            local d = state.doors[id]
            local nm = d.name
            if #nm > 12 then nm = nm:sub(1, 11) .. "." end
            term.setTextColor(colors.white)
            term.setCursorPos(2, y); term.write(nm)

            local stateTxt, stateCol
            if not d.enabled then stateTxt, stateCol = "DISABLED", colors.gray
            elseif rt.doorOpen[id] then stateTxt, stateCol = "OPEN ", colors.lime
            else stateTxt, stateCol = "CLOSE", colors.red end
            term.setTextColor(stateCol)
            term.setCursorPos(15, y); term.write(stateTxt)

            local mn = d.modem
            if mn == "" then mn = "-" end
            if #mn > 11 then mn = mn:sub(1, 10) .. "." end
            term.setTextColor(d.modem == "" and colors.red or colors.lightGray)
            term.setCursorPos(23, y); term.write(mn)

            local pm = d.padMonitor or "-"
            if #pm > 12 then pm = pm:sub(1, 11) .. "." end
            term.setTextColor(d.padMonitor and colors.lightBlue or colors.gray)
            term.setCursorPos(35, y); term.write(pm)
            y = y + 1
        end
    end

    -- Footer with shortcuts
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    for x = 1, w do term.setCursorPos(x, h); term.write(" ") end
    term.setCursorPos(2, h)
    term.write("[P]eri [R]eboot [W]ipe state")
    term.setBackgroundColor(colors.black)
    term.setCursorPos(1, h - 1)
end

local function showPeriList()
    term.setBackgroundColor(colors.black); term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow); print("=== Peripherals on this base ===")
    term.setTextColor(colors.white); print("Relays:")
    for _, n in ipairs(listByType("redstone_relay")) do
        term.setTextColor(colors.lightGray); print("  " .. n)
    end
    term.setTextColor(colors.white); print("Modems:")
    for _, n in ipairs(listByType("modem")) do
        term.setTextColor(colors.lightGray); print("  " .. n)
    end
    term.setTextColor(colors.white); print("Monitors:")
    for _, n in ipairs(listByType("monitor")) do
        term.setTextColor(colors.lightGray); print("  " .. n)
    end
    term.setTextColor(colors.gray)
    print("")
    print("Press any key to return...")
    os.pullEvent("key")
    prevTermHash = nil  -- force redraw of dashboard
    drawTermDashboard(true)
end

local function confirmWipe()
    term.setBackgroundColor(colors.black); term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print("=== WIPE BASE STATE ===")
    term.setTextColor(colors.white)
    print("This deletes all doors, owner, settings.")
    print("")

    -- PIN check first if set
    if state.basePin and state.basePin ~= "" then
        term.setTextColor(colors.yellow)
        print("Enter base PIN:")
        term.setTextColor(colors.white)
        write("> ")
        local pin = read("*")
        if hashPin(pin, "base") ~= state.basePin then
            term.setTextColor(colors.red); print("Wrong PIN.")
            sleep(2)
            prevTermHash = nil
            drawTermDashboard(true)
            return
        end
    end

    print("Type YES (uppercase) to confirm:")
    write("> ")
    local line = read()
    if line == "YES" then
        fs.delete("base_state.dat")
        settings.unset("base_owner"); settings.save()
        term.setTextColor(colors.yellow)
        print("Wiped. Rebooting in 2s...")
        sleep(2)
        os.reboot()
    else
        prevTermHash = nil
        drawTermDashboard(true)
    end
end

local function dashboardLoop()
    drawTermDashboard(true)
    local refreshTimer = os.startTimer(0.5)
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "key" then
            local k = ev[2]
            if k == keys.p then showPeriList()
            elseif k == keys.r then os.reboot()
            elseif k == keys.w then confirmWipe()
            end
        elseif ev[1] == "term_resize" then
            prevTermHash = nil
            drawTermDashboard(true)
        elseif ev[1] == "timer" and ev[2] == refreshTimer then
            drawTermDashboard(false)
            refreshTimer = os.startTimer(0.5)
        end
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
                tickNonceCache()
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

parallel.waitForAny(networkLoop, dashboardLoop)
