-- ========================================
-- test4.lua — Test: Vault → Barrel (leave in barrel)
-- ========================================

local VAULT = nil
local BARREL = nil
local CRAFTER = nil

for _, name in ipairs(peripheral.getNames()) do
    if name:find("item_vault") then VAULT = name
    elseif name:find("barrel") then BARREL = name
    elseif name:find("mechanical_crafter") then CRAFTER = name end
end

print("Vault:   " .. (VAULT or "NONE"))
print("Barrel:  " .. (BARREL or "NONE"))
print("Crafter: " .. (CRAFTER or "NONE"))

if not VAULT or not BARREL then print("Missing!"); return end

local vl = peripheral.wrap(VAULT)
local br = peripheral.wrap(BARREL)
local cr = CRAFTER and peripheral.wrap(CRAFTER) or nil

-- Find stick in vault
local slot = nil
for i = 1, vl.size() do
    local item = vl.getItemDetail(i)
    if item and item.name == "minecraft:stick" then slot = i; break end
end

if not slot then print("No stick in vault!"); return end

print("\nStick in vault slot " .. slot)

-- Clear barrel
print("Clearing barrel...")
for i = 1, br.size() do
    if br.getItemDetail(i) then br.pushItems(VAULT, i) end
end

-- Move Vault → Barrel (leave it there!)
print("\nMoving Vault → Barrel...")
print("Wait 3 seconds...")
local moved = vl.pushItems(BARREL, slot, 1, 1)
print("Moved: " .. moved)

if moved > 0 then
    print("\nSUCCESS! Stick is now in barrel.")
    print("Check if it went to crafter automatically...")
    
    -- Wait for funnel/hopper to move it
    sleep(3)
    
    -- Check barrel
    print("\nBarrel contents:")
    local inBarrel = false
    for i = 1, br.size() do
        local item = br.getItemDetail(i)
        if item then 
            print("  Slot " .. i .. ": " .. item.name)
            inBarrel = true
        end
    end
    
    -- Check crafter
    if cr then
        print("\nCrafter contents:")
        local inCrafter = false
        for i = 1, cr.size() do
            local item = cr.getItemDetail(i)
            if item then 
                print("  Slot " .. i .. ": " .. item.name)
                inCrafter = true
            end
        end
        
        if inCrafter then
            print("\n>> Funnel/Hopper moved it to crafter automatically!")
        elseif inBarrel then
            print("\n>> Still in barrel. No funnel/hopper?")
        else
            print("\n>> Vanished? Check output barrel!")
        end
    else
        print("\nNo crafter connected. Stick stays in barrel.")
    end
    
    print("\nTest complete. Stick is in barrel.")
    print("Run 'test' program to move barrel → crafter")
else
    print("FAILED to move to barrel")
end
