-- ========================================
-- test3.lua — Test: Barrel pull from Vault
-- ========================================

local VAULT = nil
local BARREL = nil

for _, name in ipairs(peripheral.getNames()) do
    if name:find("item_vault") then VAULT = name
    elseif name:find("barrel") then BARREL = name end
end

print("Vault:  " .. (VAULT or "NONE"))
print("Barrel: " .. (BARREL or "NONE"))

if not VAULT or not BARREL then print("Missing!"); return end

local vl = peripheral.wrap(VAULT)
local br = peripheral.wrap(BARREL)

-- Find stick in vault
local slot = nil
for i = 1, vl.size() do
    local item = vl.getItemDetail(i)
    if item and item.name == "minecraft:stick" then slot = i; break end
end

if not slot then print("No stick!"); return end

print("Stick in vault slot " .. slot)

-- Clear barrel
for i = 1, br.size() do
    if br.getItemDetail(i) then br.pushItems(VAULT, i) end
end

-- Test: Barrel pulls from Vault
print("\nTest: br.pullItems(VAULT, " .. slot .. ", 1)")
local moved = br.pullItems(VAULT, slot, 1)
print("Result: " .. moved)

if moved > 0 then
    print("SUCCESS with pullItems!")
    -- Check barrel
    for i = 1, br.size() do
        local item = br.getItemDetail(i)
        if item then print("Barrel slot " .. i .. ": " .. item.name) end
    end
    -- Return
    br.pushItems(VAULT, 1)
else
    print("pullItems also FAILED")
    print("\nPossible reasons:")
    print("1. Vault and Barrel are on DIFFERENT modem networks")
    print("2. No empty slots in barrel")
    print("3. CC:Tweaked 1.117.1 bug with Create vaults")
    
    -- Check if barrel has space
    print("\nBarrel empty slots:")
    for i = 1, br.size() do
        if not br.getItemDetail(i) then print("  Slot " .. i .. " empty") end
    end
end
