local INTERVAL = 1
local KEY_CHANNEL = 100

local playerName = settings.get("key_owner")
if not playerName then
    print("Enter your Minecraft name:")
    playerName = read()
    settings.set("key_owner", playerName)
    settings.save()
end

print("=== OWNER KEY ===")
print("Player: " .. playerName)

local modem = peripheral.find("modem")
if not modem then
    print("ERROR: No wireless modem!")
    return
end

local modemName = peripheral.getName(modem)
modem.open(KEY_CHANNEL + 1)

while true do
    modem.transmit(KEY_CHANNEL, KEY_CHANNEL + 1, {
        type = "KEY_PING",
        keyType = "owner",
        player = playerName,
        timestamp = os.time()
    })
    
    term.setCursorPos(1, 4)
    term.clearLine()
    term.setTextColor(colors.yellow)
    term.write("[OWNER] " .. os.time())
    term.setTextColor(colors.white)
    
    sleep(INTERVAL)
end
