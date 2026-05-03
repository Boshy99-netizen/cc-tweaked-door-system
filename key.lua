-- ============================================
-- OWNER KEY v5.0
-- Uses modem API (not rednet) for compatibility
-- ============================================

local INTERVAL = 1

local playerName = settings.get("key_owner")
if not playerName then
    print("Enter your Minecraft name:")
    playerName = read()
    settings.set("key_owner", playerName)
    settings.save()
end

print("=== OWNER KEY ===")
print("Player: " .. playerName)
print("Type: OWNER")
print("")

local modem = peripheral.find("modem")
if not modem then
    print("ERROR: No wireless modem!")
    return
end

local modemName = peripheral.getName(modem)
modem.open(101)  -- Open reply channel

print("Modem: " .. modemName)
print("Sending on channel 100...")
print("")

while true do
    -- Use modem.transmit instead of rednet
    modem.transmit(100, 101, {
        type = "KEY_PING",
        keyType = "owner",
        player = playerName,
        timestamp = os.time()
    })
    
    term.setCursorPos(1, 8)
    term.clearLine()
    term.setTextColor(colors.yellow)
    term.write("[OWNER] Ping: " .. os.time())
    term.setTextColor(colors.white)
    
    sleep(INTERVAL)
end
