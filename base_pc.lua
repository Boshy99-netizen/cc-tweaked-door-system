-- ============================================
-- BASE DOOR CONTROL SYSTEM v7.0
-- 2 modems only (1 per door), individual control
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
    modem1 = nil,      -- Under door 1
    modem2 = nil,      -- Under door 2
}

local state = {
    locked = false,
    radius = DEFAULT_RADIUS,
    door1Open = false,
    door2Open = false,
    manualOverride1 = false,
    manualOverride2 = false,
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
    
    -- Modem 1 (under Door 1)
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
    
    -- Modem 2 (under Door 2)
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
-- STATUS MONITOR (OUTSIDE) - SIMPLIFIED
-- ============================================

function drawStatusMonitor()
    local mon = config.statusMonitor
    if not mon then return end
    
    mon.setTextScale(1.0)
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
    
    -- Line 3: OPEN or LOCKED (big, centered)
    mon.setCursorPos(cx - 4, 6)
    if state.locked then
        mon.setTextColor(colors.red)
        mon.write("LOCKED")
    else
        mon.setTextColor(colors.lime)
        mon.write("OPEN")
    end
end

-- ============================================
-- CONTROL MONITOR (INSIDE) - BEAUTIFUL
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
    
    -- Header with border
    mon.setBackgroundColor(colors.gray)
    mon.setTextColor(colors.white)
    for x = 1, 26 do
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
    
    -- Lock status
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
    
    -- Door 2 controls
    mon.setTextColor(colors.white)
    mon.setCursorPos(2, 10)
    mon.write("DOOR 2:")
    if state.door2Open then
        drawBtn(mon, 12, 10, "[CLOSE]", colors.yellow, colors.black, "toggle_door2")
    else
        drawBtn(mon, 12, 10, "[OPEN] ", colors.green, colors.white, "toggle_door2")
    end
    
    -- Radius control
    mon.setTextColor(colors.white)
    mon.setCursorPos(2, 13)
    mon.write("Radius:")
    drawBtn(mon, 10, 13, " - ", colors.gray, colors.white, "radius_down")
    mon.setTextColor(colors.yellow)
    mon.setCursorPos(15, 13)
    mon.write(string.format("%2d", state.radius))
    drawBtn(mon, 19, 13, " + ", colors.gray, colors.white, "radius_up")
    
    -- Guest list header
    mon.setBackgroundColor(colors.gray)
    mon.setTextColor(colors.white)
    for x = 1, 26 do
        mon.setCursorPos(x, 15)
        mon.write(" ")
    end
    local guestCount = 0
    for _ in pairs(state.allowedGuests) do guestCount = guestCount + 1 end
    mon.setCursorPos(2, 15)
    mon.write(" GUESTS: " .. guestCount .. " ")
    drawBtn(mon, 20, 15, " +ADD ", colors.green, colors.white, "add_guest")
    mon.setBackgroundColor(colors.black)
    
    -- Guest list
    local y = 17
    local guests = {}
    for name, _ in pairs(state.allowedGuests) do table.insert(guests, name) end
    
    for i = 1, math.min(#guests, 5) do
        mon.setTextColor(colors.yellow)
        mon.setCursorPos(2, y)
        mon.write(guests[i])
        drawBtn(mon, 20, y, "[DEL]", colors.red, colors.white, "remove_" .. guests[i])
        y = y + 1
    end
    
    -- Footer
    mon.setTextColor(colors.gray)
    mon.setCursorPos(2, 23)
    mon.write("Active: " .. countPings())
    
    drawBtn(mon, 2, 24, "[ RECONFIGURE ]", colors.purple, colors.white, "reconfig")
    
    -- Input overlay
    if inputMode == "add_guest" then
        -- Draw box
        mon.setBackgroundColor(colors.black)
        for by = 10, 18 do
            for bx = 4, 22 do
                mon.setCursorPos(bx, by)
                mon.write(" ")
            end
        end
        -- Border
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
        -- Click outside box cancels
        if mx < 4 or mx > 22 or my < 10 or my > 18 then
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
    elseif action == "toggle_door1" then
        state.manualOverride1 = not state.manualOverride1
        setDoor(1, not state.door1Open)
    elseif action == "toggle_door2" then
        state.manualOverride2 = not state.manualOverride2
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
            -- FIX: Support uppercase letters!
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
            elseif key == keys.minus or key == keys.underscore then
                inputBuffer = inputBuffer .. "_"
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
    
    -- Determine which door based on which modem received
    local targetDoor = nil
    
    if modemSide == config.modem1 then
        targetDoor = 1
    elseif modemSide == config.modem2 then
        targetDoor = 2
    else
        return  -- Unknown modem
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
            keyType = keyType,
            door = targetDoor
        }
        state.lastPingTime[player] = now
        
        -- Open only the specific door
        if targetDoor == 1 then
            setDoor(1, true)
        elseif targetDoor == 2 then
            setDoor(2, true)
        end
    end
end

-- ============================================
-- MAIN LOOP
-- ============================================

function mainLoop()
    print("=== Door System v7.0 ===")
    print("Owner: " .. OWNER_NAME)
    print("Radius: " .. state.radius)
    print("")
    
    if config.statusMonitor then print("Status:  " .. peripheral.getName(config.statusMonitor)) end
    if config.controlMonitor then print("Control: " .. peripheral.getName(config.controlMonitor)) end
    if config.relay1 then print("Relay 1: " .. peripheral.getName(config.relay1)) end
    if config.relay2 then print("Relay 2: " .. peripheral.getName(config.relay2)) end
    print("Modem Door 1: " .. (config.modem1 or "NONE"))
    print("Modem Door 2: " .. (config.modem2 or "NONE"))
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
                            if data.door == 1 then door1Active = true end
                            if data.door == 2 then door2Active = true end
                        else
                            state.activePings[player] = nil
                        end
                    end
                    
                    -- Auto-close doors if no active pings
                    if not door1Active and not state.manualOverride1 then
                        setDoor(1, false)
                    end
                    if not door2Active and not state.manualOverride2 then
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
                    
                    -- Only process from our door modems on our channel
                    if channel == KEY_CHANNEL then
                        if side == config.modem1 or side == config.modem2 then
                            processPing(message, distance, side)
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
