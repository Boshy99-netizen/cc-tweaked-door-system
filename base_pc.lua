-- ============================================
-- BASE DOOR CONTROL SYSTEM v5.2
-- CC:Tweaked 1.117.1 - With modem selection
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
    modem1 = nil,      -- Wireless modem under door 1
    modem2 = nil,      -- Wireless modem under door 2
    mainModem = nil,   -- Main wireless modem on PC for receiving keys
}

local state = {
    locked = false,
    radius = DEFAULT_RADIUS,
    door1Open = false,
    door2Open = false,
    manualOverride = false,
    allowedGuests = {},
    activePings = {},
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
    print("=== RELAY 1 (Door 1 / Left) ===")
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
    print("=== RELAY 2 (Door 2 / Right) ===")
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
    
    -- Modem 1 (under Door 1)
    term.clear()
    print("=== MODEM 1 (Wireless under Door 1) ===")
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
    
    -- Modem 2 (under Door 2)
    term.clear()
    print("=== MODEM 2 (Wireless under Door 2) ===")
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
    
    -- Main Modem (receives keys from pocket PCs)
    term.clear()
    print("=== MAIN MODEM (receives keys) ===")
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
        if n and remMod2[n] then config.mainModem = remMod2[n].name end
    end
    sleep(0.3)
    
    -- Open all modems for rednet
    for _, p in ipairs(modems) do
        rednet.open(p.name)
        print("Opened modem: " .. p.name)
    end
    
    saveConfig()
    
    term.clear()
    print("=== CONFIGURATION COMPLETE ===")
    print("Status Monitor:  " .. (config.statusMonitor and peripheral.getName(config.statusMonitor) or "NONE"))
    print("Control Monitor: " .. (config.controlMonitor and peripheral.getName(config.controlMonitor) or "NONE"))
    print("Relay 1:         " .. (config.relay1 and peripheral.getName(config.relay1) or "NONE"))
    print("Relay 2:         " .. (config.relay2 and peripheral.getName(config.relay2) or "NONE"))
    print("Modem Door 1:    " .. (config.modem1 or "NONE"))
    print("Modem Door 2:    " .. (config.modem2 or "NONE"))
    print("Main Modem:      " .. (config.mainModem or "NONE"))
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
        f.writeLine("mainModem=" .. (config.mainModem or ""))
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
            elseif key == "mainModem" then config.mainModem = val
            end
        end
    end
    f.close()
    
    -- Open all modems
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            rednet.open(name)
        end
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
-- KEY PROCESSING
-- ============================================

function processPing(sender, message, distance)
    if type(message) ~= "table" then return end
    if message.type ~= "KEY_PING" then return end
    
    local player = message.player
    local keyType = message.keyType or "guest"
    
    if type(distance) ~= "number" then
        return
    end
    
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
        state.activePings[player] = {
            time = now,
            distance = distance,
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
    print("=== Door System v5.2 ===")
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
    print("Main Modem:   " .. (config.mainModem or "NONE"))
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
                    
                elseif event[1] == "rednet_message" then
                    local sender = event[2]
                    local message = event[3]
                    local distance = event[4]
                    
                    processPing(sender, message, distance)
                    
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
