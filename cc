-- ========================================
-- ae2.lua — Create AE2 Controller
-- ========================================

local VAULT = peripheral.wrap("create:item_vault_0")
local CRAFTER = peripheral.wrap("create:mechanical_crafter_0")
local OUTPUT = peripheral.wrap("right")
local MONITOR = peripheral.find("monitor")

local CONFIG_FILE = "ae2_slots.txt"
local RECIPES_FILE = "ae2_recipes.txt"

local SLOTS = {input = {}, output = {}}
local RECIPES = {}
local QUEUE = {}

-- === FILES ===
function loadData(filename)
    if fs.exists(filename) then
        local f = fs.open(filename, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        if type(data) == "table" then return data end
    end
    return nil
end

function saveData(filename, data)
    local f = fs.open(filename, "w")
    f.write(textutils.serialize(data))
    f.close()
end

-- === INIT ===
function initSlots()
    local data = loadData(CONFIG_FILE)
    if data and data.input and data.output 
       and type(data.input) == "table" and type(data.output) == "table" then
        SLOTS = data
        return true
    end
    SLOTS = {input = {}, output = {}}
    return false
end

function initRecipes()
    local data = loadData(RECIPES_FILE)
    if data and type(data) == "table" then
        RECIPES = data
        return true
    end
    RECIPES = {}
    return false
end

-- === CALIBRATE ===
function calibrate()
    print("=== CALIBRATE ===")
    print("Empty crafter, 1 stick in vault, rotation connected")
    print("Press Enter...")
    read()
    
    if not CRAFTER then print("ERR: No crafter!"); return false end
    
    local total = CRAFTER.size()
    print("Slots: " .. total)
    
    for i = 1, total do
        if CRAFTER.getItemDetail(i) then
            VAULT.pullItems(peripheral.getName(CRAFTER), i)
        end
    end
    
    SLOTS = {input = {}, output = {}}
    
    if VAULT.pushItems(peripheral.getName(CRAFTER), "minecraft:stick", 1) == 0 then
        print("ERR: No sticks in vault!")
        return false
    end
    
    for i = 1, total do
        local item = CRAFTER.getItemDetail(i)
        if item and item.name == "minecraft:stick" then
            table.insert(SLOTS.input, i)
            print("  Input: " .. i)
            VAULT.pullItems(peripheral.getName(CRAFTER), i)
        end
    end
    
    for i = 1, total do
        local found = false
        for _, v in ipairs(SLOTS.input) do if v == i then found = true end end
        if not found then table.insert(SLOTS.output, i) end
    end
    
    print("Input: " .. #SLOTS.input .. ", Output: " .. #SLOTS.output)
    saveData(CONFIG_FILE, SLOTS)
    print("OK: Saved!")
    return true
end

-- === LEARN ===
function learn()
    if #SLOTS.input == 0 then print("ERR: Run calibrate() first!"); return end
    
    print("Put items in crafter, wait for craft, press Enter")
    read()
    
    local slots = {}
    local has = false
    
    for _, s in ipairs(SLOTS.input) do
        local item = CRAFTER.getItemDetail(s)
        if item then
            slots[tostring(s)] = item.name
            has = true
            print("  Slot " .. s .. ": " .. item.name)
        end
    end
    
    if not has then print("ERR: Empty!"); return end
    
    local result = nil
    for _, s in ipairs(SLOTS.output) do
        local item = CRAFTER.getItemDetail(s)
        if item then result = item.name; break end
    end
    
    if not result and OUTPUT then
        for s = 1, OUTPUT.size() do
            local item = OUTPUT.getItemDetail(s)
            if item then result = item.name; break end
        end
    end
    
    if not result then
        print("Enter result item manually:")
        result = read()
        if result == "" then return end
    end
    
    print("Result: " .. result)
    print("Recipe name:")
    local name = read()
    if name == "" then return end
    
    RECIPES[name] = {slots = slots, result = result}
    saveData(RECIPES_FILE, RECIPES)
    print("OK: " .. name)
    store()
end

-- === CRAFT ===
function vaultItems()
    local t = {}
    if not VAULT then return t end
    for i = 1, VAULT.size() do
        local item = VAULT.getItemDetail(i)
        if item then t[item.name] = (t[item.name] or 0) + item.count end
    end
    return t
end

function recipeNeeds(recipe)
    local t = {}
    for _, item in pairs(recipe.slots) do
        t[item] = (t[item] or 0) + 1
    end
    return t
end

function checkResources(req)
    local have = vaultItems()
    for item, count in pairs(req) do
        if (have[item] or 0) < count then
            return false, item .. ": " .. (have[item] or 0) .. "/" .. count
        end
    end
    return true
end

function clearCrafter()
    for _, s in ipairs(SLOTS.input) do
        if CRAFTER.getItemDetail(s) then
            VAULT.pullItems(peripheral.getName(CRAFTER), s)
        end
    end
    for _, s in ipairs(SLOTS.output) do
        if CRAFTER.getItemDetail(s) then
            VAULT.pullItems(peripheral.getName(CRAFTER), s)
        end
    end
end

function loadRecipe(recipe)
    for slotStr, item in pairs(recipe.slots) do
        local slot = tonumber(slotStr)
        if VAULT.pushItems(peripheral.getName(CRAFTER), item, 1, slot) == 0 then
            print("ERR: Missing " .. item)
            return false
        end
    end
    return true
end

function storeOutput()
    local n = 0
    for _, s in ipairs(SLOTS.output) do
        local item = CRAFTER.getItemDetail(s)
        if item then n = n + VAULT.pullItems(peripheral.getName(CRAFTER), s) end
    end
    if OUTPUT then
        for s = 1, OUTPUT.size() do
            local item = OUTPUT.getItemDetail(s)
            if item then n = n + VAULT.pullItems(peripheral.getName(OUTPUT), s) end
        end
    end
    return n
end

function isBusy()
    for _, s in ipairs(SLOTS.output) do
        if CRAFTER.getItemDetail(s) then return true end
    end
    if OUTPUT then
        for s = 1, OUTPUT.size() do
            if OUTPUT.getItemDetail(s) then return true end
        end
    end
    return false
end

function craft(name)
    local recipe = RECIPES[name]
    if not recipe then print("ERR: No recipe: " .. name); return false end
    
    print("=== CRAFT: " .. name .. " ===")
    
    local ok, msg = checkResources(recipeNeeds(recipe))
    if not ok then print("ERR: " .. msg); return false end
    
    clearCrafter()
    sleep(0.5)
    
    print("Loading...")
    if not loadRecipe(recipe) then return false end
    
    print("Waiting...")
    local t = 0
    while t < 30 do
        sleep(1)
        t = t + 1
        if isBusy() then print("OK: Done in " .. t .. "s"); break end
    end
    
    sleep(1)
    local n = storeOutput()
    print(n > 0 and ("OK: Got " .. n) or "WARN: Nothing!")
    clearCrafter()
    return n > 0
end

-- === UI ===
function drawUI()
    if not MONITOR then return end
    MONITOR.clear()
    MONITOR.setCursorPos(1,1)
    MONITOR.write("Create AE2")
    MONITOR.setCursorPos(1,2)
    if #SLOTS.input == 0 then
        MONITOR.write("Run calibrate!")
    elseif isBusy() then
        MONITOR.write("Working...")
    else
        MONITOR.write("Ready")
    end
    local y = 4
    for name, r in pairs(RECIPES) do
        MONITOR.setCursorPos(1, y)
        local short = r.result:gsub(".*:", "")
        MONITOR.write(name .. " -> " .. short)
        y = y + 1
        if y > 18 then break end
    end
end

-- === COMMANDS ===
function list()
    for name, count in pairs(vaultItems()) do
        print(name .. ": " .. count)
    end
end

function showRecipes()
    for name, r in pairs(RECIPES) do
        print(name .. " -> " .. r.result)
    end
end

function del(name)
    if RECIPES[name] then
        RECIPES[name] = nil
        saveData(RECIPES_FILE, RECIPES)
        print("OK: Deleted")
    else
        print("ERR: Not found")
    end
end

function q(name)
    if not RECIPES[name] then print("ERR: No recipe"); return end
    table.insert(QUEUE, name)
    print("Queued: " .. name .. " (total: " .. #QUEUE .. ")")
end

function auto()
    while true do
        if #QUEUE > 0 and not isBusy() then
            craft(table.remove(QUEUE, 1))
        end
        drawUI()
        sleep(2)
    end
end

-- === MAIN ===
function main()
    print("=== Create AE2 ===")
    initSlots()
    initRecipes()
    
    print("Input: " .. #SLOTS.input .. ", Output: " .. #SLOTS.output)
    local n = 0; for _ in pairs(RECIPES) do n = n + 1 end
    print("Recipes: " .. n)
    
    if #SLOTS.input == 0 then
        print("\nFirst run! Type: calibrate")
    end
    
    print("\nCommands: calibrate | learn | craft [name] | list | recipes | q [name] | auto | del [name]")
    
    -- Command loop
    while true do
        write("> ")
        local cmd = read()
        local args = {}
        for word in cmd:gmatch("%S+") do table.insert(args, word) end
        
        if #args == 0 then
            -- empty
        elseif args[1] == "calibrate" then
            calibrate()
        elseif args[1] == "learn" then
            learn()
        elseif args[1] == "craft" and args[2] then
            craft(args[2])
        elseif args[1] == "list" then
            list()
        elseif args[1] == "recipes" then
            showRecipes()
        elseif args[1] == "q" and args[2] then
            q(args[2])
        elseif args[1] == "auto" then
            auto()
        elseif args[1] == "del" and args[2] then
            del(args[2])
        elseif args[1] == "exit" then
            break
        else
            print("Unknown: " .. args[1])
        end
        
        drawUI()
    end
end

main()
