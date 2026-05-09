-- ============================================
-- GUEST/CLAN KEY v11.0 — ELECTRONIC PASS
-- Choose type: Guest (1 door) or Team/Clan (both doors, ignores LOCK)
-- + Modem auto-recovery
-- ============================================

local INTERVAL      = 1
local KEY_CHANNEL   = 100
local REPLY_CHANNEL = 101

-- ============================================
-- INIT
-- ============================================

local playerName = settings.get("key_owner")
if not playerName then
    print("Enter your Minecraft name:")
    playerName = read()
    settings.set("key_owner", playerName)
    settings.save()
end

local keyType = settings.get("key_type")
if not keyType then
    term.clear(); term.setCursorPos(1, 1)
    print("=== SELECT PASS TYPE ===")
    print("")
    print("1. GUEST  -- opens one door only")
    print("            (the closest door)")
    print("")
    print("2. TEAM   -- opens both doors,")
    print("            works while base is")
    print("            LOCKED (full access)")
    print("")
    print("Select 1 or 2:")

    while true do
        local choice = read()
        if choice == "1" then
            keyType = "guest"
            settings.set("key_type", keyType); settings.save(); break
        elseif choice == "2" then
            keyType = "team"
            settings.set("key_type", keyType); settings.save(); break
        else
            print("Invalid! Enter 1 or 2:")
        end
    end
end

-- ============================================
-- MODEM (with auto-recovery)
-- This is the fix for "key sometimes needs reload to open doors":
-- if the modem peripheral handle goes stale (chunk unload, dim change,
-- pocket re-equip), we re-resolve it instead of silently dropping pings.
-- ============================================

local modem = nil
local modemName = nil

local function resolveModem()
    modem = peripheral.find("modem")
    if modem then
        modemName = peripheral.getName(modem)
        pcall(modem.open, REPLY_CHANNEL)
    else
        modemName = nil
    end
end

local function safeTransmit(ch, replyCh, payload)
    if not modem then resolveModem() end
    if not modem then return false end
    local ok = pcall(modem.transmit, ch, replyCh, payload)
    if not ok then
        modem = nil
        modemName = nil
        resolveModem()
        if modem then
            pcall(modem.transmit, ch, replyCh, payload)
        end
    end
    return ok
end

resolveModem()
if not modem then
    print("ERROR: No wireless modem!")
    return
end

-- ============================================
-- BASE STATE (received via BASE_STATUS)
-- ============================================

local baseLocked = nil
local lastBaseAt = nil

-- ============================================
-- DRAW
-- ============================================

local function clearScreen()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

local function drawFrame()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.gray)
    term.setCursorPos(1, 1); term.write("+")
    term.setCursorPos(w, 1); term.write("+")
    term.setCursorPos(1, h); term.write("+")
    term.setCursorPos(w, h); term.write("+")
    for x = 2, w - 1 do
        term.setCursorPos(x, 1); term.write("=")
        term.setCursorPos(x, h); term.write("=")
    end
    for y = 2, h - 1 do
        term.setCursorPos(1, y); term.write("|")
        term.setCursorPos(w, y); term.write("|")
    end
end

local function drawHeader(title, bg)
    bg = bg or colors.gray
    local w = term.getSize()
    term.setBackgroundColor(bg)
    term.setTextColor(colors.white)
    for x = 2, w - 1 do
        term.setCursorPos(x, 2); term.write(" ")
    end
    term.setCursorPos(math.floor((w - #title) / 2) + 1, 2)
    term.write(title)
    term.setBackgroundColor(colors.black)
end

local function centerWrite(y, text, color)
    local w = term.getSize()
    if color then term.setTextColor(color) end
    term.setCursorPos(math.floor((w - #text) / 2) + 1, y)
    term.write(text)
end

-- ============================================
-- PASS PAGE
-- ============================================

local function drawPass()
    clearScreen()
    drawFrame()

    local w, h = term.getSize()
    local title = (keyType == "team") and "  TEAM PASS  " or "  GUEST PASS  "
    drawHeader(title, (keyType == "team") and colors.purple or colors.blue)

    if keyType == "team" then
        -- Crown icon
        term.setTextColor(colors.yellow)
        centerWrite(4, "  .---.  ", colors.yellow)
        centerWrite(5, " /\\ | /\\ ")
        centerWrite(6, "(  \\|/  )")
        centerWrite(7, " '-----' ")
    else
        -- Card icon
        term.setTextColor(colors.lightBlue)
        centerWrite(4, " +-----+ ", colors.lightBlue)
        centerWrite(5, " |     | ")
        centerWrite(6, " |  o  | ")
        centerWrite(7, " +-----+ ")
    end

    centerWrite(9, playerName, colors.white)

    if keyType == "team" then
        centerWrite(10, "[ TEAM ]", colors.yellow)
    else
        centerWrite(10, "[ GUEST ]", colors.lightBlue)
    end

    -- Base status (informational)
    term.setTextColor(colors.gray)
    term.setCursorPos(3, 13); term.write("Base: ")
    if baseLocked == nil then
        term.setTextColor(colors.gray);  term.write("...")
    elseif baseLocked then
        term.setTextColor(colors.red);   term.write("LOCKED")
        if keyType == "guest" then
            term.setTextColor(colors.gray)
            term.setCursorPos(3, 14); term.write("(guests denied)")
        end
    else
        term.setTextColor(colors.lime);  term.write("OPEN  ")
    end

    -- Real time at the bottom
    term.setTextColor(colors.lightGray)
    local timeStr = textutils.formatTime(os.time("local"), true)
    centerWrite(h - 1, timeStr, colors.lightGray)
end

local function refreshTimeBar()
    local w, h = term.getSize()
    -- Clear time row
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    for x = 2, w - 1 do
        term.setCursorPos(x, h - 1); term.write(" ")
    end
    local timeStr = textutils.formatTime(os.time("local"), true)
    term.setCursorPos(math.floor((w - #timeStr) / 2) + 1, h - 1)
    term.write(timeStr)
end

-- ============================================
-- MAIN LOOP
-- ============================================

local function mainLoop()
    clearScreen()
    print("=== KEY v11.0 ===")
    print("Player: " .. playerName)
    print("Type: " .. ((keyType == "team") and "TEAM" or "GUEST"))
    print("")
    print("Loading...")
    sleep(0.5)

    drawPass()

    local timerId = os.startTimer(INTERVAL)

    while true do
        local event = { os.pullEventRaw() }
        local ev = event[1]

        if ev == "timer" and event[2] == timerId then
            -- Send KEY_PING
            safeTransmit(KEY_CHANNEL, REPLY_CHANNEL, {
                type      = "KEY_PING",
                keyType   = keyType,
                player    = playerName,
                timestamp = os.time(),
            })
            -- Soft refresh of the time line
            refreshTimeBar()
            timerId = os.startTimer(INTERVAL)

        elseif ev == "modem_message" then
            local message = event[5]
            if type(message) == "table" and message.type == "BASE_STATUS" then
                local prev = baseLocked
                baseLocked = message.locked
                lastBaseAt = os.epoch("utc")
                if prev ~= baseLocked then
                    drawPass()
                end
            end

        elseif ev == "peripheral" then
            if event[2] then
                local ok, pType = pcall(peripheral.getType, event[2])
                if ok and pType == "modem" then
                    resolveModem()
                end
            end

        elseif ev == "peripheral_detach" then
            if event[2] == modemName then
                modem = nil
                modemName = nil
                resolveModem()
            end
        end
    end
end

mainLoop()
