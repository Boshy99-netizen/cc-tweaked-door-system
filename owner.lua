-- ============================================
-- OWNER KEY v10.0 — ELECTRONIC PASS
-- Multi-page interface with remote control
-- ============================================

local INTERVAL = 1
local KEY_CHANNEL = 100
local REPLY_CHANNEL = 101

local playerName = settings.get("key_owner")
if not playerName then
    print("Enter your Minecraft name:")
    playerName = read()
    settings.set("key_owner", playerName)
    settings.save()
end

-- ============================================
-- SETUP MODEM
-- ============================================

local modem = peripheral.find("modem")
if not modem then
    print("ERROR: No wireless modem!")
    return
end

local modemName = peripheral.getName(modem)
modem.open(REPLY_CHANNEL)

-- ============================================
-- PAGES
-- ============================================

local currentPage = "main"  -- main, guests
local buttons = {}          -- shared between draw funcs and handleClick
local baseLocked = nil      -- nil = unknown, true/false from BASE_STATUS

-- ============================================
-- DRAW FUNCTIONS
-- ============================================

function clearScreen()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

function drawFrame()
    local w, h = term.getSize()
    term.setTextColor(colors.gray)
    
    -- Corners
    term.setCursorPos(1, 1)
    write("+")
    term.setCursorPos(w, 1)
    write("+")
    term.setCursorPos(1, h)
    write("+")
    term.setCursorPos(w, h)
    write("+")
    
    -- Borders
    for x = 2, w - 1 do
        term.setCursorPos(x, 1)
        write("=")
        term.setCursorPos(x, h)
        write("=")
    end
    for y = 2, h - 1 do
        term.setCursorPos(1, y)
        write("|")
        term.setCursorPos(w, y)
        write("|")
    end
end

function drawHeader(title)
    local w = term.getSize()
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    for x = 2, w - 1 do
        term.setCursorPos(x, 2)
        write(" ")
    end
    local x = math.floor((w - #title) / 2) + 1
    term.setCursorPos(x, 2)
    write(title)
    term.setBackgroundColor(colors.black)
end

function drawButton(x, y, text, bg, fg)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    term.setCursorPos(x, y)
    write(text)
    term.setBackgroundColor(colors.black)
    return {x1 = x, y1 = y, x2 = x + #text - 1, y2 = y}
end

-- ============================================
-- MAIN PAGE — ELECTRONIC PASS
-- ============================================

function drawMainPage()
    clearScreen()
    drawFrame()
    drawHeader("  ELECTRONIC PASS  ")
    
    local w, h = term.getSize()
    local cx = math.floor(w / 2)
    
    -- Pass icon (simple diamond shape)
    term.setTextColor(colors.yellow)
    term.setCursorPos(cx - 2, 4)
    write("  /\\  ")
    term.setCursorPos(cx - 2, 5)
    write(" <  > ")
    term.setCursorPos(cx - 2, 6)
    write("  \\/  ")
    
    -- Owner name
    term.setTextColor(colors.white)
    term.setCursorPos(cx - math.floor(#playerName / 2), 8)
    write(playerName)
    
    -- Status line
    term.setTextColor(colors.lime)
    term.setCursorPos(cx - 3, 9)
    write("[OWNER]")
    
    -- Current time
    term.setTextColor(colors.lightGray)
    local timeStr = textutils.formatTime(os.time(), false)
    term.setCursorPos(cx - math.floor(#timeStr / 2), 11)
    write(timeStr)
    
    -- Base status line
    term.setTextColor(colors.gray)
    term.setCursorPos(3, 13)
    write("Base: ")
    if baseLocked == nil then
        term.setTextColor(colors.gray)
        write("Waiting...")
    elseif baseLocked then
        term.setTextColor(colors.red)
        write("LOCKED  ")
    else
        term.setTextColor(colors.lime)
        write("OPEN    ")
    end
    
    -- Action buttons (vertical aligned list)
    buttons = {}
    buttons.guests = drawButton(4, 15, "[  GUESTS   ]", colors.yellow, colors.black)
    if baseLocked then
        buttons.toggle_lock = drawButton(4, 16, "[  UNLOCK   ]", colors.red,  colors.white)
    else
        buttons.toggle_lock = drawButton(4, 16, "[ LOCK BASE ]", colors.purple, colors.white)
    end
    
    -- Ping indicator
    term.setTextColor(colors.gray)
    term.setCursorPos(3, h - 1)
    write("Signal: OK")
end

-- ============================================
-- GUESTS PAGE — MANAGE GUESTS
-- ============================================

local guestInput = ""
local guestInputMode = false

function drawGuestsPage()
    clearScreen()
    drawFrame()
    drawHeader("  GUEST MANAGEMENT  ")
    
    buttons = {}
    
    -- Guest list (we'll receive this from base)
    term.setTextColor(colors.yellow)
    term.setCursorPos(4, 5)
    write("Loading guests...")
    
    -- Add guest button
    buttons.add_guest = drawButton(4, 16, " [ ADD GUEST ] ", colors.green, colors.white)
    
    -- Back button
    buttons.back = drawButton(4, 18, " [ BACK ] ", colors.gray, colors.white)
    
    -- Request guest list from base
    modem.transmit(KEY_CHANNEL, REPLY_CHANNEL, {
        type = "REQUEST_GUESTS",
        player = playerName,
        keyType = "owner"
    })
end

function drawGuestInput()
    term.setBackgroundColor(colors.black)
    for y = 8, 14 do
        for x = 4, 22 do
            term.setCursorPos(x, y)
            write(" ")
        end
    end
    
    -- Box border
    term.setTextColor(colors.gray)
    for x = 4, 22 do
        term.setCursorPos(x, 8)
        write("-")
        term.setCursorPos(x, 14)
        write("-")
    end
    for y = 8, 14 do
        term.setCursorPos(4, y)
        write("|")
        term.setCursorPos(22, y)
        write("|")
    end
    term.setCursorPos(4, 8)
    write("+")
    term.setCursorPos(22, 8)
    write("+")
    term.setCursorPos(4, 14)
    write("+")
    term.setCursorPos(22, 14)
    write("+")
    
    term.setTextColor(colors.white)
    term.setCursorPos(6, 10)
    write("ENTER GUEST NAME:")
    term.setTextColor(colors.yellow)
    term.setCursorPos(6, 12)
    write("> " .. guestInput .. "_")
end

-- ============================================
-- INPUT HANDLING
-- ============================================

function handleClick(x, y)
    for name, area in pairs(buttons) do
        if x >= area.x1 and x <= area.x2 and y >= area.y1 and y <= area.y2 then
            return name
        end
    end
    return nil
end

function sendCommand(cmd, data)
    modem.transmit(KEY_CHANNEL, REPLY_CHANNEL, {
        type = "OWNER_COMMAND",
        player = playerName,
        command = cmd,
        data = data
    })
end

-- ============================================
-- MAIN LOOP
-- ============================================

function mainLoop()
    clearScreen()
    print("=== OWNER KEY v10.0 ===")
    print("Electronic Pass System")
    print("Player: " .. playerName)
    print("")
    print("Loading interface...")
    sleep(1)
    
    drawMainPage()
    
    local timerId = os.startTimer(INTERVAL)
    
    while true do
        local event = {os.pullEventRaw()}
        
        if event[1] == "timer" and event[2] == timerId then
            -- Send regular ping
            modem.transmit(KEY_CHANNEL, REPLY_CHANNEL, {
                type = "KEY_PING",
                keyType = "owner",
                player = playerName,
                timestamp = os.time()
            })
            
            -- Update time on main page
            if currentPage == "main" then
                term.setTextColor(colors.lightGray)
                local timeStr = textutils.formatTime(os.time(), false)
                local w = term.getSize()
                local cx = math.floor(w / 2)
                term.setCursorPos(cx - math.floor(#timeStr / 2), 11)
                write(timeStr)
            end
            
            timerId = os.startTimer(INTERVAL)
            
        elseif event[1] == "modem_message" then
            local side = event[2]
            local channel = event[3]
            local replyChannel = event[4]
            local message = event[5]
            local distance = event[6]
            
            if type(message) == "table" then
                if message.type == "BASE_STATUS" then
                    -- Save state and refresh main page only on change
                    local changed = (baseLocked ~= message.locked)
                    baseLocked = message.locked
                    if currentPage == "main" and changed then
                        drawMainPage()
                    end
                elseif message.type == "GUEST_LIST" and currentPage == "guests" then
                    -- Update guest list
                    clearScreen()
                    drawFrame()
                    drawHeader("  GUEST MANAGEMENT  ")
                    
                    buttons = {}
                    buttons.add_guest = drawButton(4, 16, " [ ADD GUEST ] ", colors.green, colors.white)
                    buttons.back = drawButton(4, 18, " [ BACK ] ", colors.gray, colors.white)
                    
                    term.setTextColor(colors.yellow)
                    local y = 5
                    if message.guests and #message.guests > 0 then
                        for i, guest in ipairs(message.guests) do
                            if y <= 14 then
                                term.setCursorPos(4, y)
                                write(guest)
                                buttons["remove_" .. guest] = drawButton(18, y, "[X]", colors.red, colors.white)
                                y = y + 1
                            end
                        end
                    else
                        term.setCursorPos(4, 5)
                        write("No guests")
                    end
                end
            end
            
        elseif event[1] == "mouse_click" or event[1] == "monitor_touch" then
            local x, y = event[3], event[4]
            local clicked = handleClick(x, y)
            
            if clicked then
                if currentPage == "main" then
                    if clicked == "guests" then
                        currentPage = "guests"
                        drawGuestsPage()
                    elseif clicked == "toggle_lock" then
                        sendCommand("toggle_lock")
                        -- Optimistic UI flip so user sees immediate response.
                        -- The next BASE_STATUS broadcast (~2s) will confirm or revert.
                        if baseLocked == nil then baseLocked = false end
                        baseLocked = not baseLocked
                        drawMainPage()
                    end
                    
                elseif currentPage == "guests" then
                    if clicked == "add_guest" then
                        guestInputMode = true
                        guestInput = ""
                        drawGuestInput()
                    elseif clicked == "back" then
                        currentPage = "main"
                        drawMainPage()
                    elseif clicked:sub(1, 7) == "remove_" then
                        local name = clicked:sub(8)
                        sendCommand("remove_guest", name)
                        sleep(0.5)
                        drawGuestsPage()
                    end
                end
            end
            
        elseif event[1] == "key" and guestInputMode then
            local key = event[2]
            
            if key == keys.enter then
                if guestInput ~= "" then
                    sendCommand("add_guest", guestInput)
                end
                guestInputMode = false
                guestInput = ""
                drawGuestsPage()
            elseif key == keys.backspace then
                if #guestInput > 0 then
                    guestInput = guestInput:sub(1, -2)
                    drawGuestInput()
                end
            elseif key == keys.escape then
                guestInputMode = false
                guestInput = ""
                drawGuestsPage()
            elseif key >= keys.a and key <= keys.z then
                local char = string.char(key - keys.a + string.byte("a"))
                guestInput = guestInput .. char
                drawGuestInput()
            elseif key >= keys.zero and key <= keys.nine then
                local char = string.char(key - keys.zero + string.byte("0"))
                guestInput = guestInput .. char
                drawGuestInput()
            elseif key == keys.space then
                guestInput = guestInput .. " "
                drawGuestInput()
            end
        end
    end
end

-- Start
mainLoop()
