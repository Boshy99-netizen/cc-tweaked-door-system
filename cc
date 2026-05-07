-- ========================================
-- test2.lua — Test: Vault → Barrel (Debug)
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

print("\nVault size: " .. vl.size())
print("Barrel size: " .. br.size())

-- Show vault contents
print("\n=== VAULT CONTENTS ===")
for i = 1, vl.size() do
    local item = vl.getItemDetail(i)
    if item then
        print("Slot " .. i .. ": " .. item.name .. " x" .. item.count)
    end
end

-- Show barrel contents before
print("\n=== BARREL BEFORE ===")
for i = 1, br.size() do
    local item = br.getItemDetail(i)
    if item then
        print("Slot " .. i .. ": " .. item.name .. " x" .. item.count)
    else
        print("Slot " .. i .. ": empty")
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

-- Test 1: pushItems with specific target slot
print("\n=== TEST 1: Vault→Barrel slot 1 ===")
local moved1 = vl.pushItems(BARREL, slot, 1, 1)
print("Moved: " .. moved1)

-- Test 2: pushItems without target slot (any slot)
if moved1 == 0 then
    print("\n=== TEST 2: Vault→Barrel any slot ===")
    local moved2 = vl.pushItems(BARREL, slot, 1)
    print("Moved: " .. moved2)
    
    -- Test 3: pullItems from vault side
    if moved2 == 0 then
        print("\n=== TEST 3: Barrel pull from Vault ===")
        local moved3 = br.pullItems(VAULT, slot, 1)
        print("Moved: " .. moved3)
    end
end

-- Show barrel contents after
print("\n=== BARREL AFTER ===")
for i = 1, br.size() do
    local item = br.getItemDetail(i)
    if item then
        print("Slot " .. i .. ": " .. item.name .. " x" .. item.count)
    else
        print("Slot " .. i .. ": empty")
    end
end

-- Cleanup: return to vault if anything moved
print("\nCleanup...")
for i = 1, br.size() do
    if br.getItemDetail(i) then
        br.pushItems(VAULT, i)
    end
end
print("Done")
