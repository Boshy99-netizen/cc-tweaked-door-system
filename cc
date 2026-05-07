-- ========================================
-- test2.lua — Test: Vault → Barrel
-- ========================================

-- Find devices
local VAULT = nil
local BARREL = nil

for _, name in ipairs(peripheral.getNames()) do
    if name:find("item_vault") then
        VAULT = name
    elseif name:find("barrel") or name:find("chest") then
        BARREL = name
    end
end

print("=== DEVICES ===")
print("Vault:  " .. (VAULT or "NONE"))
print("Barrel: " .. (BARREL or "NONE"))

if not VAULT or not BARREL then
    print("Missing devices!")
    return
end

local vl = peripheral.wrap(VAULT)
local br = peripheral.wrap(BARREL)

-- Show vault contents
print("\n=== VAULT CONTENTS ===")
for i = 1, vl.size() do
    local item = vl.getItemDetail(i)
    if item then
        print("Slot " .. i .. ": " .. item.name .. " x" .. item.count)
    end
end

-- Find stick in vault
print("\nLooking for stick...")
local slot = nil
for i = 1, vl.size() do
    local item = vl.getItemDetail(i)
    if item and item.name == "minecraft:stick" then
        slot = i
        print("Found in slot " .. i)
        break
    end
end

if not slot then
    print("No sticks in vault!")
    return
end

-- Clear barrel first
print("\nClearing barrel...")
for i = 1, br.size() do
    if br.getItemDetail(i) then
        br.pushItems(VAULT, i)
    end
end

-- Try Vault → Barrel
print("\nTrying: Vault → Barrel...")
print("from: " .. VAULT .. " slot " .. slot)
print("to:   " .. BARREL .. " slot 1")

local moved = vl.pushItems(BARREL, slot, 1, 1)
print("\nResult: " .. moved .. " items moved")

if moved > 0 then
    print("SUCCESS!")
    
    -- Check barrel
    print("\nChecking barrel:")
    for i = 1, br.size() do
        local item = br.getItemDetail(i)
        if item then
            print("  Slot " .. i .. ": " .. item.name)
        end
    end
    
    -- Take back
    print("\nTaking back to vault...")
    br.pushItems(VAULT, 1)
    print("Done")
else
    print("FAILED")
end
