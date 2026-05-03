-- ============================================
-- BASE DOOR CONTROL SYSTEM v5.0
-- CC:Tweaked 1.117.1 - uses modem_message for distance
-- No GPS, no chat commands
-- ============================================

local OWNER_NAME = "Boshy99"  -- CHANGE THIS!

local DEFAULT_RADIUS = 5
local PING_TIMEOUT = 2

-- ============================================
-- PERIPHERAL CONFIG
-- ============================================

local config = {
    statusMonitor = nil,
    controlMonitor = nil,
    relay1 = nil,
    relay2 = nil,
    modem1 = nil,      -- Under door 1
    modem2 = nil,      -- Under door 2
    mainModem = nil,   -- Main wireless modem
    mainModemSide = nil, -- Side name of main modem
}

local state = {
    locked = false,
    radius = DEFAULT_RADIUS,
    door1Open = false,
    door2Open = false,
    manualOverride = false,
    allowedGuests = {},
    activePings = {},
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
    for i, p in ipairs({table.unpack(monitors), table.unpack(relays), table.unpack(modems)}) do
        print(i .. ". " .. p.name .. " (" .. p.type .. ")")
    end
    print("")
    
    -- Status Monitor
    print("=== STATUS MONITOR (outside) ===")
    for i, p in ipairs(monitors) do print("  " .. i .. ". " .. p.name) end
    print("Select number:")
    local choice = read()
    if choice ~= "" then
        local idx = tonumber(choice)
        if idx and monitors[idx] then config.statusMonitor = monitors[idx].obj end
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
        local idx = tonumber(choice)
        if idx and remMon[idx] then config.controlMonitor = remMon[idx].obj end
    end
    sleep(0.3)
    
    -- Relay 1
    term.clear()
    print("=== RELAY 1 (Door 1) ===")
    for i, p in ipairs(relays) do print("  " .. i .. ". " .. p.name) end
    print("Select number:")
    choice = read()
    if choice ~= "" then
        local idx = tonumber(choice)
        if idx and relays[idx] then config.relay1 = relays[idx].obj end
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
        local idx = tonumber(choice)
        if idx and remRel[idx] then config.relay2 = remRel[idx].obj end
    end
    sleep(0.3)
    
    -- Main Modem (for receiving keys)
    term.clear()
    print("=== MAIN MODEM (receives keys) ===")
    for i, p in ipairs(modems) do
        print("  " .. i .. ". " .. p.name)
    end
    print("Select number:")
    choice = read()
    if choice ~= "" then
        local idx = tonumber(choice)
        if idx and modems[idx] then
            config.mainModem = modems[idx].obj
            config.mainModemSide = modems[idx].name
        end
    end
    sleep(0.3)
    
    -- Open main modem for listening
    if config.mainModem then
        -- Open modem on specific channel
        config.mainModem.open(100)  -- Channel for door keys
        print("Opened channel 100 on " .. config.mainModemSide)
    end
    
    saveConfig()
    
    term.clear()
    print("=== CONFIG COMPLETE ===")
    print("Status:  " .. (config.statusMonitor and peripheral.getName(config.statusMonitor) or "NONE"))
    print("Control: " .. (config.controlMonitor and peripheral.getName(config.controlMonitor) or "NONE"))
    print("Relay 1: " .. (config.relay1 and peripheral.getName(config.relay1) or "NONE"))
    print("Relay 2: " .. (config.relay2 and peripheral.getName(config.relay2) or "NONE"))
    print("Main Modem: " .. (config.mainModemSide or "NONE"))
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
            elseif key == "mainModem" then
                config.mainModemSide = val
                config.mainModem = peripheral.wrap(val)
            end
        end
    end
    f.close()
    
    -- Open channel on main modem
    if config.mainModem then
        config.mainModem.open(100)
    end
    
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

function openDoors()
    setDoor(1, true)
    setDoor(2, true)
end

function closeDoors()
    if not state.manualOverride then
        setDoor(1, false)
        setDoor(2, false)
    end
end

-- ============================================
-- STATUS MONITOR
-- ============================================

function drawStatusMonitor()
    local mon = config.statusMonitor
    if not mon then return end
    
    mon.setTextScale(1.5)
    mon.setBackgroundColor(colors.black)
    mon.clear()
    
    local w, h = mon.getSize()
    local cx = math.floor(w / 2)
    
    mon.setTextColor(colors.white)
    mon.setCursorPos(cx - 4, 2)
    mon.write("== BASE ==")
    
    mon.setCursorPos(cx - 6, 4)
    if state.locked then
        mon.setTextColor(colors.red)
        mon.write("LOCKED")
    else
        mon.setTextColor(colors.lime)
        mon.write("OPEN")
    end
    
    mon.setCursorPos(cx - 6, 6)
    if state.door1Open or state.door2Open then
        mon.setTextColor(colors.yellow)
        mon.write("DOORS OPEN")
    else
        mon.setTextColor(colors.gray)
        mon.write("DOORS CLOSED")
    end
    
    mon.setTextColor(colors.lightGray)
    mon.setCursorPos(cx - 7, 8)
    mon.write("Radius: " .. state.radius)
    
    local count = 0
    for _ in pairs(state.activePings) do count = count + 1 end
    mon.setCursorPos(cx - 8, 10)
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
    
    drawBtn(mon, 12, 4, state.manualOverride and "CLOSE" or "OPEN",
            state.manualOverride and colors.yellow or colors.blue,
            colors.black,
            "toggle_manual")
    
    mon.setTextColor(colors.white)
    mon.setCursorPos(2, 6)
    mon.write("Radius:")
    drawBtn(mon, 10, 6, "-", colors.gray, colors.white, "radius_down")
    mon.setTextColor(colors.yellow)
    mon.setCursorPos(14, 6)
    mon.write(string.format("%2d", state.radius))
    drawBtn(mon, 18, 6, "+", colors.gray, colors.white, "radius_up")
    
    local guestCount = 0
    for _ in pairs(state.allowedGuests) do guestCount = guestCount + 1 end
    
    mon.setTextColor(colors.cyan)
    mon.setCursorPos(2, 8)
    mon.write("Guests: " .. guestCount)
    drawBtn(mon, 18, 8, "+ ADD", colors.green, colors.white, "add_guest")
    
    local y = 10
    local guests = {}
    for name, _ in pairs(state.allowedGuests) do table.insert(guests, name) end
    
    for i = 1, math.min(#guests, 8) do
        mon.setTextColor(colors.yellow)
        mon.setCursorPos(2, y)
        mon.write(guests[i])
        drawBtn(mon, 18, y, "[X]", colors.red, colors.white, "remove_" .. guests[i])
        y = y + 1
    end
    
    mon.setTextColor(colors.gray)
    mon.setCursorPos(2, 19)
    mon.write("Active: " .. countPings())
    
    drawBtn(mon, 2, 20, "[ RECONFIG ]", colors.purple, colors.white, "reconfig")
    
    if inputMode == "add_guest" then
        mon.setBackgroundColor(colors.black)
        for i = 9, 15 do
            mon.setCursorPos(2, i)
            mon.write(string.rep(" ", 24))
        end
        mon.setTextColor(colors.white)
        mon.setCursorPos(2, 10)
        mon.write("=== ADD GUEST ===")
        mon.setCursorPos(2, 12)
        mon.write("Type on PC keyboard:")
        mon.setCursorPos(2, 15)
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
        if my < 9 or my > 15 then
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
            state.manualOverride = false
            closeDoors()
        end
    elseif action == "toggle_manual" then
        state.manualOverride = not state.manualOverride
        if state.manualOverride then openDoors() else closeDoors() end
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
-- KEY PROCESSING - USING modem_message FOR DISTANCE!
-- ============================================

function processPing(message, distance)
    if type(message) ~= "table" then return end
    if message.type ~= "KEY_PING" then return end
    
    local player = message.player
    local keyType = message.keyType or "guest"
    
    -- CRITICAL FIX: distance is now a REAL NUMBER from modem_message!
    local dist = tonumber(distance)
    if not dist then
        print("DEBUG: distance invalid: " .. tostring(distance))
        return
    end
    
    print("DEBUG: " .. player .. " at " .. dist .. " blocks")
    
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
    
    -- Distance check - NOW WORKING!
    if dist <= state.radius then
        local now = os.clock()
        state.activePings[player] = {
            time = now,
            distance = dist,
            keyType = keyType
        }
        state.lastPingTime[player] = now
        
        if not state.door1Open then
            openDoors()
        end
    end
end

-- ============================================
-- MAIN LOOP
-- ============================================

function mainLoop()
    print("=== Door System v5.0 ===")
    print("CC:Tweaked 1.117.1")
    print("Owner: " .. OWNER_NAME)
    print("Radius: " .. state.radius)
    print("")
    
    if config.statusMonitor then print("Status:  " .. peripheral.getName(config.statusMonitor)) end
    if config.controlMonitor then print("Control: " .. peripheral.getName(config.controlMonitor)) end
    if config.relay1 then print("Relay 1: " .. peripheral.getName(config.relay1)) end
    if config.relay2 then print("Relay 2: " .. peripheral.getName(config.relay2)) end
    print("Main Modem: " .. (config.mainModemSide or "NONE"))
    print("")
    print("Using modem_message for distance")
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
                    local anyone = false
                    
                    for player, data in pairs(state.activePings) do
                        if now - data.time < PING_TIMEOUT then
                            anyone = true
                        else
                            state.activePings[player] = nil
                        end
                    end
                    
                    if not anyone and not state.manualOverride then
                        closeDoors()
                    end
                    
                    drawStatusMonitor()
                    drawControlMonitor()
                    
                elseif event[1] == "modem_message" then
                    -- THIS IS THE FIX!
                    -- modem_message gives us distance!
                    -- event[1] = "modem_message"
                    -- event[2] = side (string)
                    -- event[3] = channel (number)
                    -- event[4] = replyChannel (number)
                    -- event[5] = message (table)
                    -- event[6] = distance (number!)
                    
                    local side = event[2]
                    local channel = event[3]
                    local replyChannel = event[4]
                    local message = event[5]
                    local distance = event[6]  -- ← REAL DISTANCE!
                    
                    -- Only process messages on our channel from main modem
                    if side == config.mainModemSide and channel == 100 then
                        processPing(message, distance)
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
