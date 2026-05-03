-- ============================================
-- GUEST/CLAN KEY v10.0 — ELECTRONIC PASS
-- Select type: Guest (1 door) or Team/Clan (both doors)
-- ============================================

local INTERVAL = 1
local KEY_CHANNEL = 100
local REPLY_CHANNEL = 101

-- ============================================
-- SETUP
-- ============================================

local playerName = settings.get("key_owner")
if not playerName then
    print("Enter your Minecraft name:")
    playerName = read()
    settings.set("key_owner", playerName)
    settings.save()
end

-- Select key type (Guest or Team)
local keyType = settings.get("key_type")
if not keyType then
    term.clear()
    term.setCursorPos(1, 1)
    print("=== SELECT PASS TYPE ===")
    print("")
    print("1. GUEST — Opens one door only")
    print("   (closest door to you)")
    print("")
    print("2. TEAM / CLAN — Opens both doors")
    print("   (full access like owner)")
    print("")
    print("Select 1 or 2:")
    
    while true do
        local choice = read()
        if choice == "1" then
            keyType = "guest"
            settings.set("key_type", keyType)
            settings.save()
            break
        elseif choice == "2" then
            keyType = "team"
            settings.set("key_type", keyType)
            settings.save()
            break
        else
            print("Invalid! Enter 1 or 2:")
        end
    end
end

-- ============================================
-- MODEM SETUP
-- ============================================

local modem = peripheral.find("modem")
if not modem then
    print("ERROR: No wireless modem!")
    return
end

local modemName = peripheral.getName(modem)
modem.open(REPLY_CHANNEL)

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

-- ============================================
-- MAIN PAGE — ELECTRONIC PASS
-- ============================================

function drawPass()
    clearScreen()
    drawFrame()
    
    local typeText = (keyType == "team") and "  TEAM PASS  " or "  GUEST PASS  "
    drawHeader(typeText)
    
    local w, h = term.getSize()
    local cx = math.floor(w / 2)
    
    -- Pass icon (different for guest vs team)
    if keyType == "team" then
        -- Crown icon for team
        term.setTextColor(colors.yellow)
        term.setCursorPos(cx - 3, 4)
        write("  .-.  ")
        term.setCursorPos(cx - 3, 5)
        write(" /   \\ ")
        term.setCursorPos(cx - 3, 6)
        write("(  |  )")
        term.setCursorPos(cx - 3, 7)
        write(" \\___/ ")
    else
        -- Card icon for guest
        term.setTextColor(colors.lightBlue)
        term.setCursorPos(cx - 3, 4)
        write(" +---+ ")
        term.setCursorPos(cx - 3, 5)
        write(" |   | ")
        term.setCursorPos(cx - 3, 6)
        write(" | o | ")
        term.setCursorPos(cx - 3, 7)
        write(" +---+ ")
    end
    
    -- Player name
    term.setTextColor(colors.white)
    term.setCursorPos(cx - math.floor(#playerName / 2), 9)
    write(playerName)
    
    -- Access level
    if keyType == "team" then
        term.setTextColor(colors.yellow)
        term.setCursorPos(cx - 3, 11)
        write("[TEAM]")
        term.setTextColor(colors.lightGray)
        term.setCursorPos(cx - 6, 13)
        write("Full Access")
    else
        term.setTextColor(colors.lightBlue)
        term.setCursorPos(cx - 3, 11)
        write("[GUEST]")
        term.setTextColor(colors.lightGray)
        term.setCursorPos(cx - 6, 13)
        write("Single Door")
    end
    
    -- Status
    term.setTextColor(colors.gray)
    term.setCursorPos(3, 15)
    write("Status: Active")
    
    -- Signal
    term.setTextColor(colors.lime)
    term.setCursorPos(3, 17)
    write("Signal: Transmitting")
    
    -- Time
    term.setTextColor(colors.lightGray)
    local timeStr = textutils.formatTime(os.time(), false)
    term.setCursorPos(cx - math.floor(#timeStr / 2), 19)
    write(timeStr)
    
    -- Instructions
    term.setTextColor(colors.gray)
    term.setCursorPos(3, h - 2)
    write("Hold to approach door")
end

-- ============================================
-- MAIN LOOP
-- ============================================

function mainLoop()
    clearScreen()
    print("=== GUEST KEY v10.0 ===")
    print("Electronic Pass System")
    print("Player: " .. playerName)
    print("Type: " .. ((keyType == "team") and "TEAM (Full Access)" or "GUEST (Single Door)"))
    print("")
    print("Loading...")
    sleep(1)
    
    drawPass()
    
    while true do
        local event = {os.pullEvent()}
        
        if event[1] == "timer" then
            -- Send ping with type
            modem.transmit(KEY_CHANNEL, REPLY_CHANNEL, {
                type = "KEY_PING",
                keyType = keyType,  -- "guest" or "team"
                player = playerName,
                timestamp = os.time()
            })
            
            -- Update time
            term.setTextColor(colors.lightGray)
            local timeStr = textutils.formatTime(os.time(), false)
            local w = term.getSize()
            local cx = math.floor(w / 2)
            term.setCursorPos(cx - math.floor(#timeStr / 2), 19)
            write(timeStr)
            
            -- Blink signal indicator
            term.setTextColor(colors.lime)
            term.setCursorPos(11, 17)
            write("*")
            sleep(0.1)
            term.setCursorPos(11, 17)
            write(" ")
            
        elseif event[1] == "key" then
            local key = event[2]
            -- Press 'R' to reset type
            if key == keys.r then
                settings.set("key_type", nil)
                settings.save()
                print("Type reset! Reboot...")
                sleep(1)
                os.reboot()
            end
        end
    end
end

mainLoop()
