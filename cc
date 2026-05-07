-- ========================================
-- test5.lua — Test: Vault → Crafter direct
-- ========================================

local VAULT = nil
local CRAFTER = nil

for _, name in ipairs(peripheral.getNames()) do
    if name:find("item_vault") then VAULT = name
    elseif name:find("mechanical_crafter") then CRAFTER = name end
end

print("Vault:   " .. (VAULT or "NONE"))
print("Crafter: " .. (CRAFTER or "NONE"))

if not VAULT or not CRAFTER then print("Missing!"); return end

local vl = peripheral.wrap(VAULT)
local cr = peripheral.wrap(CRAFTER)

-- Clear crafter first
print("\nClearing crafter...")
for i = 1, cr.size() do
    if cr.getItemDetail(i) then
        cr.pushItems(VAULT, i)
    end
end

-- Find stick in vault
local slot = nil
for i = 1, vl.size() do
    local item = vl.getItemDetail(i)
    if item and item.name == "minecraft:stick" then slot = i; break end
end

if not slot then print("No stick in vault!"); return end

print("Stick in vault slot " .. slot)

-- Test: Vault → Crafter direct
print("\nTrying: Vault → Crafter direct...")
print("from: " .. VAULT .. " slot " .. slot)
print("to:   " .. CRAFTER .. " slot 1")

local moved = vl.pushItems(CRAFTER, slot, 1, 1)
print("\nResult: " .. moved .. " items moved")

if moved > 0 then
    print("SUCCESS! Direct works!")
    
    -- Check crafter
    print("\nCrafter contents:")
    for i = 1, cr.size() do
        local item = cr.getItemDetail(i)
        if item then print("  Slot " .. i .. ": " .. item.name) end
    end
    
    -- Take back
    print("\nTaking back to vault...")
    cr.pushItems(VAULT, 1)
    print("Done")
else
    print("FAILED direct!")
    print("\nDirect Vault→Crafter does NOT work.")
    print("Must use: Vault → Barrel → Funnel → Crafter")
end
