-- ========================================
-- test.lua — Test: Barrel → Crafter
-- ========================================

-- Find devices
local CRAFTER = nil
local BARREL = nil

for _, name in ipairs(peripheral.getNames()) do
    if name:find("mechanical_crafter") then
        CRAFTER = name
    elseif name:find("barrel") or name:find("chest") then
        BARREL = name
    end
end

print("=== DEVICES ===")
print("Crafter: " .. (CRAFTER or "NONE"))
print("Barrel:  " .. (BARREL or "NONE"))

if not CRAFTER or not BARREL then
    print("Missing devices!")
    return
end

local cr = peripheral.wrap(CRAFTER)
local br = peripheral.wrap(BARREL)

-- Show barrel contents
print("\n=== BARREL CONTENTS ===")
for i = 1, br.size() do
    local item = br.getItemDetail(i)
    if item then
        print("Slot " .. i .. ": " .. item.name .. " x" .. item.count)
    end
end

-- Find stick in barrel
print("\nLooking for stick...")
local slot = nil
for i = 1, br.size() do
    local item = br.getItemDetail(i)
    if item and item.name == "minecraft:stick" then
        slot = i
        print("Found in slot " .. i)
        break
    end
end

if not slot then
    print("No sticks in barrel!")
    print("Put 1 stick in barrel and run again")
    return
end

-- Try to move to crafter
print("\nTrying: Barrel → Crafter...")
print("from: " .. BARREL .. " slot " .. slot)
print("to:   " .. CRAFTER .. " slot 1")

local moved = br.pushItems(CRAFTER, slot, 1, 1)
print("\nResult: " .. moved .. " items moved")

if moved > 0 then
    print("SUCCESS! Works!")
    
    -- Check crafter
    print("\nChecking crafter:")
    for i = 1, cr.size() do
        local item = cr.getItemDetail(i)
        if item then
            print("  Slot " .. i .. ": " .. item.name)
        end
    end
    
    -- Take back
    print("\nTaking back...")
    cr.pushItems(BARREL, 1)
    print("Done")
else
    print("FAILED")
    print("\nCheck:")
    print("1. Is barrel next to crafter?")
    print("2. Is there a Funnel/Hopper between them?")
    print("3. Are all connected to modem network?")
end
