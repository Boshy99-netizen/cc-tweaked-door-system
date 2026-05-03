-- ============================================
-- BASE DOOR CONTROL SYSTEM v9.0
-- Individual radius per door, persistent guests
-- ============================================

local OWNER_NAME = "Boshy99"

local DEFAULT_RADIUS = 5
local PING_TIMEOUT = 2
local KEY_CHANNEL = 100
local REPLY_CHANNEL = 101

-- ============================================
-- PERIPHERAL CONFIG
-- ============================================

local config = {
    statusMonitor = nil,
    controlMonitor = nil,
    relay1 = nil,
    relay2 = nil,
    modem1 = nil,
    modem2 = nil,
}

-- ============================================
-- STATE
-- ============================================

local state = {
    locked = false,
    radius1 = DEFAULT_RADIUS,  -- Radius for door 1
    radius2 = DEFAULT_RADIUS,  -- Radius for door 2
    door1Open = false,
    door2Open = false,
    manualOverride1 = false,
    manualOverride2 = false,
    allowedGuests = {},        -- Will be loaded from file
    activePings = {},
    lastPingTime = {},
}

-- Previous state for no-flicker
local prevStatusState = nil
local prevControlState = nil

-- Periodic broadcast counter (every Nth timer tick)
local broadcastTick = 0

-- ============================================
-- SAVE/LOAD PERSISTENT DATA
-- ============================================

function savePersistentData()
    -- Save guests
    local f = fs.open("guests.txt", "w")
    if f then
        for name, _ in pairs(state.allowedGuests) do
            f.writeLine(name)
        end
        f.close()
    end
    
    -- Save radii
    local r = fs.open("radii.txt", "w")
    if r then
        r.writeLine("radius1=" .. state.radius1)
        r.writeLine("radius2=" .. state.radius2)
        r.close()
    end
end

function loadPersistentData()
    -- Load guests
    if fs.exists("guests.txt") then
        local f = fs.open("guests.txt", "r")
        if f then
            while true do
                local line = f.readLine()
                if not line then break end
                if line ~= "" then
                    state.allowedGuests[line] = true
                end
            end
            f.close()
        end
    end
    
    -- Load radii
    if fs.exists("radii.txt") then
        local r = fs.open("radii.txt", "r")
        if r then
            while true do
                local line = r.readLine()
                if not line then break end
                local key, val = line:match("([^=]+)=(.*)")
                if key and val then
                    local num = tonumber(val)
                    if num then
                        if key == "radius1" then state.radius1 = num
                        elseif key == "radius2" then state.radius2 = num
                        end
                    end
                end
            end
            r.close()
        end
    end
end

-- ============================================
-- CONFIGURATION (peripherals only)
-- ============================================

function runConfiguration()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== DOOR SYSTEM SETUP ===")
    print("Configure peripherals. Radii and guests are saved separately.")
    print("")
    
    local monitors = {}
    local relays = {}
    local modems = {}
    
    for _, name in ipairs(peripheral.getNames()) do
        local pType = peripheral.getType(name)
        local p = {name = name, type = pType, obj = peripheral.wrap(name)}
        
        if pType == "monitor" then table.insert(monitors, p)
        elseif pType == "redstone_relay" then table.insert(relays, p)
        elseif pType == "modem" then table.insert(modems, p)
        end
    end
    
    print("=== ALL PERIPHERALS ===")
    local idx = 1
    for _, p in ipairs(monitors) do
        print(idx .. ". " .. p.name .. " (" .. p.type .. ")")
        idx = idx + 1
    end
    for _, p in ipairs(relays) do
        print(idx .. ". " .. p.name .. " (" .. p.type .. ")")
        idx = idx + 1
    end
    for _, p in ipairs(modems) do
        print(idx .. ". " .. p.name .. " (" .. p.type .. ")")
        idx = idx + 1
    end
    print("")
    
    -- Status Monitor
    print("=== STATUS MONITOR (outside) ===")
    for i, p in ipairs(monitors) do print("  " .. i .. ". " .. p.name) end
    print("Select number:")
    local choice = read()
    if choice ~= "" then
        local n = tonumber(choice)
        if n and monitors[n] then config.statusMonitor = monitors[n].obj end
    end
    sleep(0.3)
    
    -- Control Monitor
    term.clear()
    print("=== CONTROL MONITOR (inside) ===")
    local remMon = {}
    for _, p in ipairs(monitors) do
        if p.obj ~= config.statusMonitor then
            table.insert(remMon, p)
            print("  " .. #remMon .. ". " .. p.name)
        end
    end
    print("Select number:")
    choice = read()
    if choice ~= "" then
        local n = tonumber(choice)
        if n and remMon[n] then config.controlMonitor = remMon[n].obj end
    end
    sleep(0.3)
    
    -- Relay 1
    term.clear()
    print("=== RELAY 1 (Door 1) ===")
    for i, p in ipairs(relays) do print("  " .. i .. ". " .. p.name) end
    print("Select number:")
    choice = read()
    if choice ~= "" then
        local n = tonumber(choice)
        if n and relays[n] then config.relay1 = relays[n].obj end
    end
    sleep(0.3)
    
    -- Relay 2
    term.clear()
    print("=== RELAY 2 (Door 2) ===")
    local remRel = {}
    for _, p in ipairs(relays) do
        if p.obj ~= config.relay1 then
            table.insert(remRel, p)
            print("  " .. #remRel .. ". " .. p.name)
        end
    end
    print("Select number:")
    choice = read()
    if choice ~= "" then
        local n = tonumber(choice)
        if n and remRel[n] then config.relay2 = remRel[n].obj end
    end
    sleep(0.3)
    
    -- Modem 1
    term.clear()
    print("=== MODEM 1 (Under Door 1) ===")
    for i, p in ipairs(modems) do
        print("  " .. i .. ". " .. p.name)
    end
    print("Select number:")
    choice = read()
    if choice ~= "" then
        local n = tonumber(choice)
        if n and modems[n] then
            config.modem1 = modems[n].name
            modems[n].obj.open(KEY_CHANNEL)
        end
    end
    sleep(0.3)
    
    -- Modem 2
    term.clear()
    print("=== MODEM 2 (Under Door 2) ===")
    local remMod = {}
    for _, p in ipairs(modems) do
        if p.name ~= config.modem1 then
            table.insert(remMod, p)
            print("  " .. #remMod .. ". " .. p.name)
        end
    end
    print("Select number:")
    choice = read()
    if choice ~= "" then
        local n = tonumber(choice)
        if n and remMod[n] then
            config.modem2 = remMod[n].name
            remMod[n].obj.open(KEY_CHANNEL)
        end
    end
    sleep(0.3)
    
    saveConfig()
    
    term.clear()
    print("=== CONFIGURATION COMPLETE ===")
    print("Status Monitor:  " .. (config.statusMonitor and peripheral.getName(config.statusMonitor) or "NONE"))
    print("Control Monitor: " .. (config.controlMonitor and peripheral.getName(config.controlMonitor) or "NONE"))
    print("Relay 1:         " .. (config.relay1 and peripheral.getName(config.relay1) or "NONE"))
    print("Relay 2:         " .. (config.relay2 and peripheral.getName(config.relay2) or "NONE"))
    print("Modem Door 1:    " .. (config.modem1 or "NONE"))
    print("Modem Door 2:    " .. (config.modem2 or "NONE"))
    print("")
    print("Press Enter to start...")
    read()
end

function saveConfig()
    local f = fs.open("door_config.txt", "w")
    if f then
        f.writeLine("statusMonitor=" .. (config.statusMonitor and peripheral.getName(config.statusMonitor) or ""))
        f.writeLine("controlMonitor=" .. (config.controlMonitor and peripheral.getName(config.controlMonitor) or ""))
        f.writeLine("relay1=" .. (config.relay1 and peripheral.getName(config.relay1) or ""))
        f.writeLine("relay2=" .. (config.relay2 and peripheral.getName(config.relay2) or ""))
        f.writeLine("modem1=" .. (config.modem1 or ""))
        f.writeLine("modem2=" .. (config.modem2 or ""))
        f.close()
    end
end

function loadConfig()
    if not fs.exists("door_config.txt") then return false end
    
    local f = fs.open("door_config.txt", "r")
    if not f then return false end
    
    while true do
        local line = f.readLine()
        if not line then break end
        local key, val = line:match("([^=]+)=(.*)")
        if key and val ~= "" then
            if key == "statusMonitor" then config.statusMonitor = peripheral.wrap(val)
            elseif key == "controlMonitor" then config.controlMonitor = peripheral.wrap(val)
            elseif key == "relay1" then config.relay1 = peripheral.wrap(val)
            elseif key == "relay2" then config.relay2 = peripheral.wrap(val)
            elseif key == "modem1" then
                config.modem1 = val
                local m = peripheral.wrap(val)
                if m then m.open(KEY_CHANNEL) end
            elseif key == "modem2" then
                config.modem2 = val
                local m = peripheral.wrap(val)
                if m then m.open(KEY_CHANNEL) end
            end
        end
    end
    f.close()
    
    return true
end

-- ============================================
-- DOOR CONTROL
-- ============================================

function setDoor(doorNum, isOpen)
    local relay = (doorNum == 1) and config.relay1 or config.relay2
    if not relay then return end
    
    pcall(function()
        relay.setOutput("top", isOpen)
    end)
    
    if doorNum == 1 then state.door1Open = isOpen
    else state.door2Open = isOpen end
end

-- ============================================
-- STATUS MONITOR (OUTSIDE) - NO FLICKER
-- ============================================

function getStatusStateString()
    return tostring(state.locked)
end

function drawStatusMonitor()
    local mon = config.statusMonitor
    if not mon then return end
    
    local currentState = getStatusStateString()
    if currentState == prevStatusState then
        return
    end
    prevStatusState = currentState
    
    mon.setTextScale(1.5)
    mon.setBackgroundColor(colors.black)
    mon.clear()
    
    local w, h = mon.getSize()
    
    -- Draw beautiful frame
    mon.setTextColor(colors.gray)
    
    -- Corners
    mon.setCursorPos(1, 1)
    mon.write("+")
    mon.setCursorPos(w, 1)
    mon.write("+")
    mon.setCursorPos(1, h)
    mon.write("+")
    mon.setCursorPos(w, h)
    mon.write("+")
    
    -- Horizontal borders
    for x = 2, w - 1 do
        mon.setCursorPos(x, 1)
        mon.write("=")
        mon.setCursorPos(x, h)
        mon.write("=")
    end
    
    -- Vertical borders
    for y = 2, h - 1 do
        mon.setCursorPos(1, y)
        mon.write("|")
        mon.setCursorPos(w, y)
        mon.write("|")
    end
    
    -- Calculate center positions
    local line1 = "==Base " .. OWNER_NAME .. "=="
    local line2 = "Base Status"
    local line3 = state.locked and "LOCKED" or "OPEN"
    
    local x1 = math.floor((w - #line1) / 2) + 1
    local x2 = math.floor((w - #line2) / 2) + 1
    local x3 = math.floor((w - #line3) / 2) + 1
    
    -- Line 1
    mon.setTextColor(colors.white)
    mon.setCursorPos(x1, 3)
    mon.write(line1)
    
    -- Line 2
    mon.setTextColor(colors.lightGray)
    mon.setCursorPos(x2, 5)
    mon.write(line2)
    
    -- Line 3
    mon.setCursorPos(x3, 7)
    if state.locked then
        mon.setTextColor(colors.red)
    else
        mon.setTextColor(colors.lime)
    end
    mon.write(line3)
end

-- ============================================
-- CONTROL MONITOR (INSIDE) - NO FLICKER
-- ============================================

local buttons = {}
local inputMode = nil
local inputBuffer = ""

function getControlStateString()
    local guests = {}
    for name, _ in pairs(state.allowedGuests) do table.insert(guests, name) end
    table.sort(guests)
    return tostring(state.locked) .. "|" .. tostring(state.door1Open) .. "|" .. tostring(state.door2Open) .. "|" .. state.radius1 .. "|" .. state.radius2 .. "|" .. table.concat(guests, ",") .. "|" .. tostring(inputMode) .. "|" .. inputBuffer
end

function drawControlMonitor()
    local mon = config.controlMonitor
    if not mon then return end
    
    local currentState = getControlStateString()
    if currentState == prevControlState then
        return
    end
    prevControlState = currentState
    
    buttons = {}
    mon.setTextScale(0.8)
    mon.setBackgroundColor(colors.black)
    mon.clear()
    
    local w, h = mon.getSize()
    
    -- Header
    mon.setBackgroundColor(colors.gray)
    mon.setTextColor(colors.white)
    for x = 1, w do
        mon.setCursorPos(x, 1)
        mon.write(" ")
    end
    mon.setCursorPos(2, 1)
    mon.write("  BASE CONTROL SYSTEM  ")
    mon.setBackgroundColor(colors.black)
    
    -- Owner info
    mon.setTextColor(colors.lightGray)
    mon.setCursorPos(2, 3)
    mon.write("Owner: " .. OWNER_NAME)
    
    -- Lock button
    if state.locked then
        drawBtn(mon, 2, 5, " [ UNLOCK BASE ] ", colors.red, colors.white, "toggle_lock")
    else
        drawBtn(mon, 2, 5, " [  LOCK BASE  ] ", colors.lime, colors.black, "toggle_lock")
    end
    
    -- Door 1 controls
    mon.setTextColor(colors.white)
    mon.setCursorPos(2, 8)
    mon.write("DOOR 1:")
    if state.door1Open then
        drawBtn(mon, 12, 8, "[CLOSE]", colors.yellow, colors.black, "toggle_door1")
    else
        drawBtn(mon, 12, 8, "[OPEN] ", colors.green, colors.white, "toggle_door1")
    end
    
    -- Door 1 radius
    mon.setTextColor(colors.lightGray)
    mon.setCursorPos(2, 9)
    mon.write("Radius1:")
    drawBtn(mon, 11, 9, "-", colors.gray, colors.white, "radius1_down")
    mon.setTextColor(colors.yellow)
    mon.setCursorPos(14, 9)
    mon.write(string.format("%2d", state.radius1))
    drawBtn(mon, 18, 9, "+", colors.gray, colors.white, "radius1_up")
    
    -- Door 2 controls
    mon.setTextColor(colors.white)
    mon.setCursorPos(2, 11)
    mon.write("DOOR 2:")
    if state.door2Open then
        drawBtn(mon, 12, 11, "[CLOSE]", colors.yellow, colors.black, "toggle_door2")
    else
        drawBtn(mon, 12, 11, "[OPEN] ", colors.green, colors.white, "toggle_door2")
    end
    
    -- Door 2 radius
    mon.setTextColor(colors.lightGray)
    mon.setCursorPos(2, 12)
    mon.write("Radius2:")
    drawBtn(mon, 11, 12, "-", colors.gray, colors.white, "radius2_down")
    mon.setTextColor(colors.yellow)
    mon.setCursorPos(14, 12)
    mon.write(string.format("%2d", state.radius2))
    drawBtn(mon, 18, 12, "+", colors.gray, colors.white, "radius2_up")
    
    -- Guest header
    mon.setBackgroundColor(colors.gray)
    mon.setTextColor(colors.white)
    for x = 1, w do
        mon.setCursorPos(x, 14)
        mon.write(" ")
    end
    local guestCount = 0
    for _ in pairs(state.allowedGuests) do guestCount = guestCount + 1 end
    mon.setCursorPos(2, 14)
    mon.write(" GUESTS: " .. guestCount .. " ")
    drawBtn(mon, 20, 14, " +ADD ", colors.green, colors.white, "add_guest")
    mon.setBackgroundColor(colors.black)
    
    -- Guest list
    local y = 16
    local guests = {}
    for name, _ in pairs(state.allowedGuests) do table.insert(guests, name) end
    table.sort(guests)
    
    for i = 1, math.min(#guests, 5) do
        mon.setTextColor(colors.yellow)
        mon.setCursorPos(2, y)
        mon.write(guests[i])
        drawBtn(mon, 20, y, "[DEL]", colors.red, colors.white, "remove_" .. guests[i])
        y = y + 1
    end
    
    -- Footer
    mon.setTextColor(colors.gray)
    mon.setCursorPos(2, 22)
    mon.write("Active: " .. countPings())
    
    drawBtn(mon, 2, 23, "[ RECONFIGURE ]", colors.purple, colors.white, "reconfig")
    
    -- Input overlay
    if inputMode == "add_guest" then
        for by = 10, 18 do
            for bx = 4, 22 do
                mon.setBackgroundColor(colors.black)
                mon.setCursorPos(bx, by)
                mon.write(" ")
            end
        end
        mon.setBackgroundColor(colors.gray)
        for bx = 4, 22 do
            mon.setCursorPos(bx, 10)
            mon.write(" ")
            mon.setCursorPos(bx, 18)
            mon.write(" ")
        end
        for by = 10, 18 do
            mon.setCursorPos(4, by)
            mon.write(" ")
            mon.setCursorPos(22, by)
            mon.write(" ")
        end
        mon.setBackgroundColor(colors.black)
        
        mon.setTextColor(colors.white)
        mon.setCursorPos(6, 12)
        mon.write("ADD NEW GUEST")
        mon.setCursorPos(6, 14)
        mon.write("Type name:")
        mon.setCursorPos(6, 16)
        mon.setTextColor(colors.yellow)
        mon.write("> " .. inputBuffer .. "_")
    end
end

function drawBtn(mon, x, y, text, bg, fg, action)
    mon.setBackgroundColor(bg)
    mon.setTextColor(fg)
    mon.setCursorPos(x, y)
    mon.write(text)
    mon.setBackgroundColor(colors.black)
    buttons[action] = {x1 = x, y1 = y, x2 = x + #text - 1, y2 = y}
end

function countPings()
    local c = 0
    for _ in pairs(state.activePings) do c = c + 1 end
    return c
end

function handleTouch(mx, my)
    if inputMode == "add_guest" then
        if mx < 4 or mx > 22 or my < 10 or my > 18 then
            inputMode = nil
            inputBuffer = ""
            prevControlState = nil
            drawControlMonitor()
        end
        return
    end
    
    for action, area in pairs(buttons) do
        if mx >= area.x1 and mx <= area.x2 and my >= area.y1 and my <= area.y2 then
            execAction(action)
            return
        end
    end
end

function execAction(action)
    if action == "toggle_lock" then
        state.locked = not state.locked
        -- Lock only changes permission state, doesn't slam doors shut.
    elseif action == "toggle_door1" then
        state.manualOverride1 = not state.manualOverride1
        setDoor(1, not state.door1Open)
    elseif action == "toggle_door2" then
        state.manualOverride2 = not state.manualOverride2
        setDoor(2, not state.door2Open)
    elseif action == "radius1_down" then
        if state.radius1 > 1 then state.radius1 = state.radius1 - 1 end
        savePersistentData()
    elseif action == "radius1_up" then
        if state.radius1 < 64 then state.radius1 = state.radius1 + 1 end
        savePersistentData()
    elseif action == "radius2_down" then
        if state.radius2 > 1 then state.radius2 = state.radius2 - 1 end
        savePersistentData()
    elseif action == "radius2_up" then
        if state.radius2 < 64 then state.radius2 = state.radius2 + 1 end
        savePersistentData()
    elseif action == "add_guest" then
        inputMode = "add_guest"
        inputBuffer = ""
        prevControlState = nil
        drawControlMonitor()
        return
    elseif action:sub(1, 7) == "remove_" then
        local name = action:sub(8)
        state.allowedGuests[name] = nil
        savePersistentData()
    elseif action == "reconfig" then
        fs.delete("door_config.txt")
        fs.delete("guests.txt")
        fs.delete("radii.txt")
        os.reboot()
    end
    
    prevControlState = nil
    prevStatusState = nil
    drawControlMonitor()
    drawStatusMonitor()
end

function handleKeyboardInput()
    while true do
        local event = {os.pullEvent("key")}
        if inputMode == "add_guest" then
            local key = event[2]
            
            if key == keys.enter then
                if inputBuffer ~= "" then
                    state.allowedGuests[inputBuffer] = true
                    savePersistentData()
                end
                inputMode = nil
                inputBuffer = ""
                prevControlState = nil
                drawControlMonitor()
                drawStatusMonitor()
            elseif key == keys.backspace then
                if #inputBuffer > 0 then
                    inputBuffer = inputBuffer:sub(1, -2)
                    prevControlState = nil
                    drawControlMonitor()
                end
            elseif key >= keys.a and key <= keys.z then
                local char = string.char(key - keys.a + string.byte("a"))
                inputBuffer = inputBuffer .. char
                prevControlState = nil
                drawControlMonitor()
            elseif key >= keys.zero and key <= keys.nine then
                local char = string.char(key - keys.zero + string.byte("0"))
                inputBuffer = inputBuffer .. char
                prevControlState = nil
                drawControlMonitor()
            elseif key == keys.space then
                inputBuffer = inputBuffer .. " "
                prevControlState = nil
                drawControlMonitor()
            elseif key == keys.minus or key == keys.underscore then
                inputBuffer = inputBuffer .. "_"
                prevControlState = nil
                drawControlMonitor()
            end
        end
    end
end

-- ============================================
-- REPLIES TO KEYS
-- ============================================

function sendBaseStatus(modemSide)
    local payload = {
        type = "BASE_STATUS",
        locked = state.locked,
        door1Open = state.door1Open,
        door2Open = state.door2Open,
    }
    local function send(name)
        if not name then return end
        local m = peripheral.wrap(name)
        if m and m.transmit then
            m.transmit(REPLY_CHANNEL, KEY_CHANNEL, payload)
        end
    end
    if modemSide then
        send(modemSide)
    else
        send(config.modem1)
        send(config.modem2)
    end
end

function sendGuestList(modemSide)
    local guests = {}
    for name, _ in pairs(state.allowedGuests) do table.insert(guests, name) end
    table.sort(guests)
    local m = peripheral.wrap(modemSide)
    if m and m.transmit then
        m.transmit(REPLY_CHANNEL, KEY_CHANNEL, {
            type = "GUEST_LIST",
            guests = guests,
        })
    end
end

function handleOwnerCommand(message)
    if message.player ~= OWNER_NAME then return end
    local cmd = message.command
    local data = message.data

    if cmd == "open_door" then
        if data == 1 then setDoor(1, true); state.manualOverride1 = true
        elseif data == 2 then setDoor(2, true); state.manualOverride2 = true end
    elseif cmd == "close_door" then
        if data == 1 then setDoor(1, false); state.manualOverride1 = false
        elseif data == 2 then setDoor(2, false); state.manualOverride2 = false end
    elseif cmd == "open_all" then
        setDoor(1, true); setDoor(2, true)
        state.manualOverride1 = true; state.manualOverride2 = true
    elseif cmd == "close_all" then
        setDoor(1, false); setDoor(2, false)
        state.manualOverride1 = false; state.manualOverride2 = false
    elseif cmd == "toggle_lock" then
        state.locked = not state.locked
        -- Note: don't physically close doors here.
        -- Lock just changes the permission check for future pings.
        -- Doors held by non-owner pings will close on PING_TIMEOUT (~2s) naturally.
    elseif cmd == "add_guest" then
        if type(data) == "string" and data ~= "" then
            state.allowedGuests[data] = true
            savePersistentData()
        end
    elseif cmd == "remove_guest" then
        if type(data) == "string" then
            state.allowedGuests[data] = nil
            savePersistentData()
        end
    end
end

-- ============================================
-- KEY PROCESSING - PER DOOR WITH INDIVIDUAL RADIUS
-- ============================================

function processPing(message, distance, modemSide)
    if type(message) ~= "table" then return end
    if message.type ~= "KEY_PING" then return end
    
    local player = message.player
    local keyType = message.keyType or "guest"
    
    if type(distance) ~= "number" then
        print("[REJECT] " .. tostring(player) .. " (" .. keyType .. ") - no distance (wired modem?)")
        return
    end
    
    local targetDoor = nil
    local targetRadius = nil
    
    if modemSide == config.modem1 then
        targetDoor = 1
        targetRadius = state.radius1
    elseif modemSide == config.modem2 then
        targetDoor = 2
        targetRadius = state.radius2
    else
        return
    end
    
    -- Check lock (only owner can open when locked)
    if state.locked then
        if player ~= OWNER_NAME or keyType ~= "owner" then
            print("[REJECT] " .. tostring(player) .. " (" .. keyType .. ") - base is LOCKED")
            return
        end
    end
    
    -- Check permissions
    if keyType == "owner" then
        if player ~= OWNER_NAME then
            print("[REJECT] " .. tostring(player) .. " - claims owner but name != " .. OWNER_NAME)
            return
        end
    elseif keyType == "team" then
        -- Team/Clan: must be in guest list (treated as trusted)
        if player ~= OWNER_NAME and not state.allowedGuests[player] then
            print("[REJECT] " .. tostring(player) .. " (team) - NOT in guest list. Add via owner key.")
            return
        end
        -- Team opens BOTH doors when near ANY modem
        targetDoor = "both"
    else
        -- Regular guest: must be in list
        if player ~= OWNER_NAME and not state.allowedGuests[player] then
            print("[REJECT] " .. tostring(player) .. " (guest) - NOT in guest list. Add via owner key.")
            return
        end
    end
    
    if distance <= targetRadius then
        local now = os.clock()
        
        state.activePings[player] = {
            time = now,
            distance = distance,
            keyType = keyType,
            door = targetDoor
        }
        state.lastPingTime[player] = now
        
        -- Open door(s)
        if targetDoor == 1 then
            setDoor(1, true)
        elseif targetDoor == 2 then
            setDoor(2, true)
        elseif targetDoor == "both" then
            setDoor(1, true)
            setDoor(2, true)
        end
        print("[OPEN] " .. tostring(player) .. " (" .. keyType .. ") door=" .. tostring(targetDoor) .. " d=" .. string.format("%.1f", distance))
    else
        print("[REJECT] " .. tostring(player) .. " (" .. keyType .. ") - too far d=" .. string.format("%.1f", distance) .. " > radius=" .. targetRadius)
    end
end

-- ============================================
-- MAIN LOOP
-- ============================================

function mainLoop()
    print("=== Door System v9.0 ===")
    print("Owner: " .. OWNER_NAME)
    print("Radius1: " .. state.radius1 .. " | Radius2: " .. state.radius2)
    print("Guests: " .. countGuests())
    print("")
    
    if config.statusMonitor then print("Status:  " .. peripheral.getName(config.statusMonitor)) end
    if config.controlMonitor then print("Control: " .. peripheral.getName(config.controlMonitor)) end
    if config.relay1 then print("Relay 1: " .. peripheral.getName(config.relay1)) end
    if config.relay2 then print("Relay 2: " .. peripheral.getName(config.relay2)) end
    print("Modem Door 1: " .. (config.modem1 or "NONE"))
    print("Modem Door 2: " .. (config.modem2 or "NONE"))
    print("")
    
    prevStatusState = nil
    prevControlState = nil
    drawStatusMonitor()
    drawControlMonitor()
    
    parallel.waitForAny(
        function()
            while true do
                local timerId = os.startTimer(0.5)
                local event = {os.pullEvent()}
                
                if event[1] == "timer" then
                    local now = os.clock()
                    local door1Active = false
                    local door2Active = false
                    
                    for player, data in pairs(state.activePings) do
                        if now - data.time < PING_TIMEOUT then
                            if data.door == 1 then
                                door1Active = true
                            elseif data.door == 2 then
                                door2Active = true
                            elseif data.door == "both" then
                                door1Active = true
                                door2Active = true
                            end
                        else
                            state.activePings[player] = nil
                        end
                    end
                    
                    local door1Changed = false
                    local door2Changed = false
                    
                    if not door1Active and not state.manualOverride1 and state.door1Open then
                        setDoor(1, false)
                        door1Changed = true
                    end
                    if not door2Active and not state.manualOverride2 and state.door2Open then
                        setDoor(2, false)
                        door2Changed = true
                    end
                    
                    if door1Changed or door2Changed then
                        prevStatusState = nil
                        prevControlState = nil
                        drawStatusMonitor()
                        drawControlMonitor()
                    end
                    
                    -- Periodic broadcast every ~2s so keys can show base state
                    broadcastTick = broadcastTick + 1
                    if broadcastTick >= 4 then
                        broadcastTick = 0
                        sendBaseStatus()
                    end
                    
                elseif event[1] == "modem_message" then
                    local side = event[2]
                    local channel = event[3]
                    local replyChannel = event[4]
                    local message = event[5]
                    local distance = event[6]
                    
                    -- DEBUG: print every incoming msg
                    print("[RX] side=" .. tostring(side) .. " ch=" .. tostring(channel) .. " d=" .. tostring(distance) .. " type=" .. (type(message) == "table" and tostring(message.type) or type(message)) .. " from=" .. (type(message) == "table" and tostring(message.player) or "?"))
                    
                    if channel == KEY_CHANNEL and type(message) == "table" then
                        if message.type == "KEY_PING" then
                            if side == config.modem1 or side == config.modem2 then
                                processPing(message, distance, side)
                                if message.keyType == "owner" and message.player == OWNER_NAME then
                                    sendBaseStatus(side)
                                end
                                prevStatusState = nil
                                prevControlState = nil
                                drawStatusMonitor()
                                drawControlMonitor()
                            end
                        elseif message.type == "OWNER_COMMAND" then
                            handleOwnerCommand(message)
                            sendBaseStatus(side)
                            prevStatusState = nil
                            prevControlState = nil
                            drawStatusMonitor()
                            drawControlMonitor()
                        elseif message.type == "REQUEST_GUESTS" then
                            sendGuestList(side)
                        end
                    end
                    
                elseif event[1] == "monitor_touch" then
                    local monName = event[2]
                    local mx = event[3]
                    local my = event[4]
                    
                    if config.controlMonitor and monName == peripheral.getName(config.controlMonitor) then
                        handleTouch(mx, my)
                    end
                end
            end
        end,
        function()
            handleKeyboardInput()
        end
    )
end

function countGuests()
    local c = 0
    for _ in pairs(state.allowedGuests) do c = c + 1 end
    return c
end

-- ============================================
-- STARTUP
-- ============================================

-- Load persistent data first
loadPersistentData()

local hasConfig = loadConfig()

if not hasConfig then
    runConfiguration()
else
    print("Config loaded. Delete door_config.txt to reconfigure.")
    print("Guests: " .. countGuests())
    print("Radius1: " .. state.radius1 .. ", Radius2: " .. state.radius2)
    print("")
end

mainLoop()
