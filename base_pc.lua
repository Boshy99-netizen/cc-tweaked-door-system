-- ============================================
-- BASE DOOR CONTROL SYSTEM v6.0
-- Individual door control per modem
-- ============================================

local OWNER_NAME = "Boshy99"

local DEFAULT_RADIUS = 5
local PING_TIMEOUT = 2
local KEY_CHANNEL = 100

-- ============================================
-- PERIPHERAL CONFIG
-- ============================================

local config = {
    statusMonitor = nil,
    controlMonitor = nil,
    relay1 = nil,
    relay2 = nil,
    modem1 = nil,      -- Under door 1 (opens door 1 only)
    modem2 = nil,      -- Under door 2 (opens door 2 only)
    mainModem = nil,   -- On PC, receives keys
    mainModemSide = nil,
}

local state = {
    locked = false,
    radius = DEFAULT_RADIUS,
    door1Open = false,
    door2Open = false,
    manualOverride = false,
    allowedGuests = {},
    activePings = {},     -- [playerName] = {time, distance, doorNum}
    lastPingTime = {},
}

-- ============================================
-- CONFIGURATION
-- ============================================

function runConfiguration()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== DOOR SYSTEM SETUP ===")
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
    
    -- Modem 1 (under Door 1 - opens door 1)
    term.clear()
    print("=== MODEM 1 (Under Door 1 - opens Door 1) ===")
    for i, p in ipairs(modems) do
        print("  " .. i .. ". " .. p.name)
    end
    print("Select number:")
    choice = read()
    if choice ~= "" then
        local n = tonumber(choice)
        if n and modems[n] then config.modem1 = modems[n].name end
    end
    sleep(0.3)
    
    -- Modem 2 (under Door 2 - opens door 2)
    term.clear()
    print("=== MODEM 2 (Under Door 2 - opens Door 2) ===")
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
        if n and remMod[n] then config.modem2 = remMod[n].name end
    end
    sleep(0.3)
    
    -- Main Modem (on PC, receives keys only)
    term.clear()
    print("=== MAIN MODEM (on PC, receives keys) ===")
    print("Select the modem ON the PC (usually 'top', 'left', etc.)")
    local remMod2 = {}
    for _, p in ipairs(modems) do
        if p.name ~= config.modem1 and p.name ~= config.modem2 then
            table.insert(remMod2, p)
            print("  " .. #remMod2 .. ". " .. p.name)
        end
    end
    print("Select number:")
    choice = read()
    if choice ~= "" then
        local n = tonumber(choice)
        if n and remMod2[n] then
            config.mainModem = remMod2[n].obj
            config.mainModemSide = remMod2[n].name
        end
    end
    sleep(0.3)
    
    -- Open main modem on key channel
    if config.mainModem then
        config.mainModem.open(KEY_CHANNEL)
        print("Opened channel " .. KEY_CHANNEL .. " on " .. config.mainModemSide)
    end
    
    -- Also open door modems to listen for pings (they forward to main modem via cable)
    -- Actually, in CC:Tweaked, all modems on the network receive messages
    -- So we need to listen on ALL modems for modem_message events
    
    saveConfig()
    
    term.clear()
    print("=== CONFIGURATION COMPLETE ===")
    print("Status Monitor:  " .. (config.statusMonitor and peripheral.getName(config.statusMonitor) or "NONE"))
    print("Control Monitor: " .. (config.controlMonitor and peripheral.getName(config.controlMonitor) or "NONE"))
    print("Relay 1:         " .. (config.relay1 and peripheral.getName(config.relay1) or "NONE"))
    print("Relay 2:         " .. (config.relay2 and peripheral.getName(config.relay2) or "NONE"))
    print("Modem Door 1:    " .. (config.modem1 or "NONE") .. " -> opens Door 1")
    print("Modem Door 2:    " .. (config.modem2 or "NONE") .. " -> opens Door 2")
    print("Main Modem:      " .. (config.mainModemSide or "NONE") .. " -> receives keys")
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
        f.writeLine("mainModem=" .. (config.mainModemSide or ""))
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
            elseif key == "modem1" then config.modem1 = val
            elseif key == "modem2" then config.modem2 = val
            elseif key == "mainModem" then
                config.mainModemSide = val
                config.mainModem = peripheral.wrap(val)
            end
        end
    end
    f.close()
    
    if config.mainModem then
        config.mainModem.open(KEY_CHANNEL)
    end
    
    return true
end

-- ============================================
-- DOOR CONTROL - INDIVIDUAL
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
-- STATUS MONITOR - NEW FORMAT
-- ============================================

function drawStatusMonitor()
    local mon = config.statusMonitor
    if not mon then return end
    
    mon.setTextScale(1.2)
    mon.setBackgroundColor(colors.black)
    mon.clear()
    
    local w, h = mon.getSize()
    local cx = math.floor(w / 2)
    
    -- Line 1: ==Base Boshy99==
    mon.setTextColor(colors.white)
    mon.setCursorPos(cx - 8, 2)
    mon.write("==Base " .. OWNER_NAME .. "==")
    
    -- Line 2: Base Status
    mon.setTextColor(colors.lightGray)
    mon.setCursorPos(cx - 5, 4)
    mon.write("Base Status")
    
    -- Line 3: OPEN or LOCKED
    mon.setCursorPos(cx - 4, 6)
    if state.locked then
        mon.setTextColor(colors.red)
        mon.write("LOCKED")
    else
        mon.setTextColor(colors.lime)
        mon.write("OPEN")
    end
    
    -- Door status
    mon.setTextColor(colors.gray)
    mon.setCursorPos(2, 8)
    mon.write("Door 1: " .. (state.door1Open and "OPEN" or "CLOSED"))
    mon.setCursorPos(2, 9)
    mon.write("Door 2: " .. (state.door2Open and "OPEN" or "CLOSED"))
    
    -- Active players
    local count = 0
    for _ in pairs(state.activePings) do count = count + 1 end
    mon.setCursorPos(2, 11)
    mon.write("Nearby: " .. count)
end

-- ============================================
-- CONTROL MONITOR
-- ============================================

local buttons = {}
local inputMode = nil
local inputBuffer = ""

function drawControlMonitor()
    local mon = config.controlMonitor
    if not mon then return end
    
    buttons = {}
    mon.setTextScale(0.8)
    mon.setBackgroundColor(colors.black)
    mon.clear()
    
    mon.setTextColor(colors.cyan)
    mon.setCursorPos(2, 1)
    mon.write("=== BASE CONTROL ===")
    
    mon.setTextColor(colors.gray)
    mon.setCursorPos(2, 2)
    mon.write("Owner: " .. OWNER_NAME)
    
    drawBtn(mon, 2, 4, state.locked and "UNLOCK" or "LOCK",
            state.locked and colors.red or colors.lime,
            state.locked and colors.white or colors.black,
            "toggle_lock")
    
    drawBtn(mon, 12, 4, "OPEN ALL", colors.blue, colors.white, "open_all")
    drawBtn(mon, 2, 5, "CLOSE ALL", colors.gray, colors.white, "close_all")
    
    mon.setTextColor(colors.white)
    mon.setCursorPos(2, 7)
    mon.write("Radius:")
    drawBtn(mon, 10, 7, "-", colors.gray, colors.white, "radius_down")
    mon.setTextColor(colors.yellow)
    mon.setCursorPos(14, 7)
    mon.write(string.format("%2d", state.radius))
    drawBtn(mon, 18, 7, "+", colors.gray, colors.white, "radius_up")
    
    -- Door 1 manual
    drawBtn(mon, 2, 9, state.door1Open and "D1 CLOSE" or "D1 OPEN",
            state.door1Open and colors.yellow or colors.green,
            colors.black,
            "toggle_door1")
    
    -- Door 2 manual
    drawBtn(mon, 12, 9, state.door2Open and "D2 CLOSE" or "D2 OPEN",
            state.door2Open and colors.yellow or colors.green,
            colors.black,
            "toggle_door2")
    
    local guestCount = 0
    for _ in pairs(state.allowedGuests) do guestCount = guestCount + 1 end
    
    mon.setTextColor(colors.cyan)
    mon.setCursorPos(2, 11)
    mon.write("Guests: " .. guestCount)
    drawBtn(mon, 18, 11, "+ ADD", colors.green, colors.white, "add_guest")
    
    local y = 13
    local guests = {}
    for name, _ in pairs(state.allowedGuests) do table.insert(guests, name) end
    
    for i = 1, math.min(#guests, 6) do
        mon.setTextColor(colors.yellow)
        mon.setCursorPos(2, y)
        mon.write(guests[i])
        drawBtn(mon, 18, y, "[X]", colors.red, colors.white, "remove_" .. guests[i])
        y = y + 1
    end
    
    mon.setTextColor(colors.gray)
    mon.setCursorPos(2, 20)
    mon.write("Active: " .. countPings())
    
    drawBtn(mon, 2, 21, "[ RECONFIG ]", colors.purple, colors.white, "reconfig")
    
    if inputMode == "add_guest" then
        mon.setBackgroundColor(colors.black)
        for i = 11, 17 do
            mon.setCursorPos(2, i)
            mon.write(string.rep(" ", 24))
        end
        mon.setTextColor(colors.white)
        mon.setCursorPos(2, 12)
        mon.write("=== ADD GUEST ===")
        mon.setCursorPos(2, 14)
        mon.write("Type on PC keyboard:")
        mon.setCursorPos(2, 16)
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
        if my < 11 or my > 17 then
            inputMode = nil
            inputBuffer = ""
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
        if state.locked then
            setDoor(1, false)
            setDoor(2, false)
        end
    elseif action == "open_all" then
        state.manualOverride = true
        setDoor(1, true)
        setDoor(2, true)
    elseif action == "close_all" then
        state.manualOverride = false
        setDoor(1, false)
        setDoor(2, false)
    elseif action == "toggle_door1" then
        setDoor(1, not state.door1Open)
    elseif action == "toggle_door2" then
        setDoor(2, not state.door2Open)
    elseif action == "radius_down" then
        if state.radius > 1 then state.radius = state.radius - 1 end
    elseif action == "radius_up" then
        if state.radius < 64 then state.radius = state.radius + 1 end
    elseif action == "add_guest" then
        inputMode = "add_guest"
        inputBuffer = ""
        drawControlMonitor()
        return
    elseif action:sub(1, 7) == "remove_" then
        local name = action:sub(8)
        state.allowedGuests[name] = nil
    elseif action == "reconfig" then
        fs.delete("door_config.txt")
        os.reboot()
    end
    
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
                end
                inputMode = nil
                inputBuffer = ""
                drawControlMonitor()
                drawStatusMonitor()
            elseif key == keys.backspace then
                if #inputBuffer > 0 then
                    inputBuffer = inputBuffer:sub(1, -2)
                    drawControlMonitor()
                end
            elseif key >= keys.a and key <= keys.z then
                local char = string.char(key - keys.a + string.byte("a"))
                inputBuffer = inputBuffer .. char
                drawControlMonitor()
            elseif key >= keys.zero and key <= keys.nine then
                local char = string.char(key - keys.zero + string.byte("0"))
                inputBuffer = inputBuffer .. char
                drawControlMonitor()
            elseif key == keys.space then
                inputBuffer = inputBuffer .. " "
                drawControlMonitor()
            end
        end
    end
end

-- ============================================
-- KEY PROCESSING - PER DOOR
-- ============================================

function processPing(message, distance, modemSide)
    if type(message) ~= "table" then return end
    if message.type ~= "KEY_PING" then return end
    
    local player = message.player
    local keyType = message.keyType or "guest"
    
    if type(distance) ~= "number" then
        return
    end
    
    -- Determine which door based on which modem received the signal
    local targetDoor = nil
    
    if modemSide == config.modem1 then
        targetDoor = 1  -- Door 1
    elseif modemSide == config.modem2 then
        targetDoor = 2  -- Door 2
    elseif modemSide == config.mainModemSide then
        -- Main modem receives all signals, but we need to know which door modem is closer
        -- For now, if received on main modem, open both (or use closest door logic)
        targetDoor = "both"
    else
        -- Unknown modem, ignore
        return
    end
    
    print("DEBUG: " .. player .. " at " .. distance .. " blocks via " .. modemSide .. " -> Door " .. tostring(targetDoor))
    
    -- Check lock
    if state.locked then
        if player ~= OWNER_NAME or keyType ~= "owner" then
            return
        end
    end
    
    -- Check permissions
    if keyType == "owner" then
        if player ~= OWNER_NAME then return end
    else
        if player ~= OWNER_NAME and not state.allowedGuests[player] then
            return
        end
    end
    
    if distance <= state.radius then
        local now = os.clock()
        
        -- Store ping with target door
        state.activePings[player] = {
            time = now,
            distance = distance,
            keyType = keyType,
            door = targetDoor,
            modem = modemSide
        }
        state.lastPingTime[player] = now
        
        -- Open specific door(s)
        if targetDoor == 1 then
            setDoor(1, true)
        elseif targetDoor == 2 then
            setDoor(2, true)
        elseif targetDoor == "both" then
            -- If on main modem, we can't tell which door, so check both modems
            -- Actually, in CC:Tweaked all modems on network receive the message
            -- So we should get separate events for each modem!
            setDoor(1, true)
            setDoor(2, true)
        end
    end
end

-- ============================================
-- MAIN LOOP
-- ============================================

function mainLoop()
    print("=== Door System v6.0 ===")
    print("CC:Tweaked 1.117.1")
    print("Owner: " .. OWNER_NAME)
    print("Radius: " .. state.radius)
    print("")
    
    if config.statusMonitor then print("Status:  " .. peripheral.getName(config.statusMonitor)) end
    if config.controlMonitor then print("Control: " .. peripheral.getName(config.controlMonitor)) end
    if config.relay1 then print("Relay 1: " .. peripheral.getName(config.relay1)) end
    if config.relay2 then print("Relay 2: " .. peripheral.getName(config.relay2)) end
    print("Modem Door 1: " .. (config.modem1 or "NONE"))
    print("Modem Door 2: " .. (config.modem2 or "NONE"))
    print("Main Modem:   " .. (config.mainModemSide or "NONE"))
    print("")
    print("Individual door control per modem")
    print("Channel: " .. KEY_CHANNEL)
    print("")
    
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
                            if data.door == 1 or data.door == "both" then
                                door1Active = true
                            end
                            if data.door == 2 or data.door == "both" then
                                door2Active = true
                            end
                        else
                            state.activePings[player] = nil
                        end
                    end
                    
                    -- Close doors if no active pings for that door
                    if not door1Active and not state.manualOverride then
                        setDoor(1, false)
                    end
                    if not door2Active and not state.manualOverride then
                        setDoor(2, false)
                    end
                    
                    drawStatusMonitor()
                    drawControlMonitor()
                    
                elseif event[1] == "modem_message" then
                    local side = event[2]
                    local channel = event[3]
                    local replyChannel = event[4]
                    local message = event[5]
                    local distance = event[6]
                    
                    -- Process from ANY modem on our channel
                    if channel == KEY_CHANNEL then
                        processPing(message, distance, side)
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

-- ============================================
-- STARTUP
-- ============================================

local hasConfig = loadConfig()

if not hasConfig then
    runConfiguration()
else
    print("Config loaded. Delete door_config.txt to reconfigure.")
    print("")
end

mainLoop()
