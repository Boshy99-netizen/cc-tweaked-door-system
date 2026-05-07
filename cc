-- ========================================
-- ae2.lua — Create AE2 Controller
-- Create 6.0+ | CC:Tweaked 1.117.1
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
local STATUS = "Idle"
local LAST_MSG = ""

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
    STATUS = "Calibrating..."
    drawUI()
    
    print("=== CALIBRATE ===")
    print("Empty crafter, 1 stick in vault, rotation connected")
    print("Press Enter...")
    read()
    
    if not CRAFTER then 
        STATUS = "ERR: No crafter!"
        print(STATUS)
        return false 
    end
    
    local total = CRAFTER.size()
    print("Slots: " .. total)
    
    for i = 1, total do
        if CRAFTER.getItemDetail(i) then
            VAULT.pullItems(peripheral.getName(CRAFTER), i)
        end
    end
    
    SLOTS = {input = {}, output = {}}
    
    if VAULT.pushItems(peripheral.getName(CRAFTER), "minecraft:stick", 1) == 0 then
        STATUS = "ERR: No sticks!"
        print(STATUS)
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
    
    STATUS = "OK: Calibrated!"
    print(STATUS)
    return true
end

-- === LEARN ===
function learn()
    if #SLOTS.input == 0 then 
        STATUS = "ERR: Calibrate first!"
        print(STATUS)
        return 
    end
    
    STATUS = "Learning..."
    drawUI()
    
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
    
    if not has then 
        STATUS = "ERR: Empty crafter!"
        print(STATUS)
        return 
    end
    
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
        if result == "" then 
            STATUS = "Cancelled"
            return 
        end
    end
    
    print("Result: " .. result)
    print("Recipe name:")
    local name = read()
    if name == "" then 
        STATUS = "Cancelled"
        return 
    end
    
    RECIPES[name] = {slots = slots, result = result}
    saveData(RECIPES_FILE, RECIPES)
    
    STATUS = "OK: Recipe '" .. name .. "' saved!"
    print(STATUS)
    storeOutput()
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
    if not recipe then 
        STATUS = "ERR: No recipe '" .. name .. "'"
        print(STATUS)
        return false 
    end
    
    STATUS = "Crafting: " .. name .. "..."
    drawUI()
    print("=== CRAFT: " .. name .. " ===")
    
    local ok, msg = checkResources(recipeNeeds(recipe))
    if not ok then 
        STATUS = "ERR: " .. msg
        print(STATUS)
        return false 
    end
    
    clearCrafter()
    sleep(0.5)
    
    print("Loading...")
    if not loadRecipe(recipe) then 
        STATUS = "ERR: Load failed!"
        return false 
    end
    
    print("Waiting...")
    local t = 0
    while t < 30 do
        sleep(1)
        t = t + 1
        if isBusy() then 
            print("OK: Done in " .. t .. "s")
            break 
        end
    end
    
    sleep(1)
    local n = storeOutput()
    if n > 0 then
        STATUS = "OK: Got " .. n .. "x " .. recipe.result
        print(STATUS)
    else
        STATUS = "WARN: Nothing!"
        print(STATUS)
    end
    
    clearCrafter()
    return n > 0
end

-- === QUEUE ===
function queue(name)
    if not RECIPES[name] then 
        STATUS = "ERR: No recipe '" .. name .. "'"
        print(STATUS)
        return 
    end
    table.insert(QUEUE, name)
    STATUS = "Queued: " .. name .. " (" .. #QUEUE .. " total)"
    print(STATUS)
end

function processQueue()
    if #QUEUE > 0 and not isBusy() then
        local next = table.remove(QUEUE, 1)
        craft(next)
    end
end

function autoMode()
    STATUS = "Auto Mode"
    drawUI()
    while true do
        processQueue()
        drawUI()
        sleep(2)
    end
end

-- === UI ===
local BUTTONS = {}
local RECIPE_BUTTONS = {}

function drawButton(x, y, w, h, text, color, id)
    -- Background
    local oldColor = MONITOR.getBackgroundColor()
    MONITOR.setBackgroundColor(color or colors.gray)
    for by = y, y + h - 1 do
        MONITOR.setCursorPos(x, by)
        for bx = x, x + w - 1 do
            MONITOR.write(" ")
        end
    end
    
    -- Text centered
    MONITOR.setCursorPos(x + math.floor((w - #text) / 2), y + math.floor((h - 1) / 2))
    MONITOR.setTextColor(colors.white)
    MONITOR.write(text)
    
    MONITOR.setBackgroundColor(oldColor)
    
    -- Store button data
    table.insert(BUTTONS, {
        x = x, y = y, w = w, h = h, 
        id = id or text
    })
end

function drawUI()
    if not MONITOR then return end
    
    BUTTONS = {}
    RECIPE_BUTTONS = {}
    
    MONITOR.setBackgroundColor(colors.black)
    MONITOR.clear()
    
    -- Title
    MONITOR.setTextColor(colors.cyan)
    MONITOR.setCursorPos(1, 1)
    MONITOR.write("=== CREATE AE2 ===")
    
    -- Status line
    MONITOR.setTextColor(colors.yellow)
    MONITOR.setCursorPos(1, 2)
    MONITOR.write("Status: " .. STATUS)
    
    -- Info line
    MONITOR.setTextColor(colors.lightGray)
    MONITOR.setCursorPos(1, 3)
    MONITOR.write("Slots: I" .. #SLOTS.input .. " O" .. #SLOTS.output .. " | Recipes: " .. 0)
    local rc = 0; for _ in pairs(RECIPES) do rc = rc + 1 end
    MONITOR.setCursorPos(1, 3)
    MONITOR.write("Slots: I" .. #SLOTS.input .. " O" .. #SLOTS.output .. " | Recipes: " .. rc)
    
    -- Queue info
    MONITOR.setTextColor(colors.pink)
    MONITOR.setCursorPos(1, 4)
    MONITOR.write("Queue: " .. #QUEUE)
    
    -- Main buttons row 1
    drawButton(1, 6, 8, 3, "CALIB", colors.blue, "calibrate")
    drawButton(10, 6, 8, 3, "LEARN", colors.green, "learn")
    drawButton(19, 6, 8, 3, "AUTO", colors.orange, "auto")
    drawButton(28, 6, 8, 3, "CLEAR", colors.red, "clear")
    
    -- Recipe buttons (rows below)
    MONITOR.setTextColor(colors.white)
    MONITOR.setCursorPos(1, 10)
    MONITOR.write("=== RECIPES ===")
    
    local y = 12
    local x = 1
    for name, recipe in pairs(RECIPES) do
        if y > 18 then break end
        
        local short = recipe.result:gsub(".*:", "")
        local label = name .. ">" .. short
        
        drawButton(x, y, 18, 2, label, colors.purple, "craft:" .. name)
        
        x = x + 19
        if x > 30 then
            x = 1
            y = y + 3
        end
    end
    
    -- Help text at bottom
    MONITOR.setTextColor(colors.gray)
    MONITOR.setCursorPos(1, 19)
    MONITOR.write("Click buttons to control")
end

function handleClick(x, y)
    for _, btn in ipairs(BUTTONS) do
        if x >= btn.x and x < btn.x + btn.w 
           and y >= btn.y and y < btn.y + btn.h then
            return btn.id
        end
    end
    return nil
end

function runCommand(cmd)
    if cmd == "calibrate" then
        calibrate()
    elseif cmd == "learn" then
        learn()
    elseif cmd == "auto" then
        -- Start auto in parallel
        parallel.waitForAny(
            function()
                while true do
                    processQueue()
                    drawUI()
                    sleep(2)
                end
            end,
            function()
                -- Wait for any click to stop auto (or just run)
                while true do
                    local event, side, x, y = os.pullEvent("monitor_touch")
                    local clicked = handleClick(x, y)
                    if clicked == "clear" then
                        STATUS = "Auto stopped"
                        break
                    end
                end
            end
        )
    elseif cmd == "clear" then
        clearCrafter()
        storeOutput()
        QUEUE = {}
        STATUS = "Cleared"
    elseif cmd:sub(1, 6) == "craft:" then
        local name = cmd:sub(7)
        queue(name)
        processQueue()
    end
    drawUI()
end

-- === COMMANDS (terminal) ===
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
        STATUS = "Deleted: " .. name
        print(STATUS)
    else
        STATUS = "Not found: " .. name
        print(STATUS)
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
        print("\nFirst run! Click CALIB on monitor or type 'calibrate'")
    end
    
    drawUI()
    
    -- Parallel: monitor clicks + terminal input
    parallel.waitForAny(
        function()
            -- Monitor click handler
            while true do
                local event, side, x, y = os.pullEvent("monitor_touch")
                local cmd = handleClick(x, y)
                if cmd then
                    print("Clicked: " .. cmd)
                    runCommand(cmd)
                end
            end
        end,
        function()
            -- Terminal input handler
            while true do
                write("> ")
                local input = read()
                local args = {}
                for word in input:gmatch("%S+") do table.insert(args, word) end
                
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
                    queue(args[2])
                elseif args[1] == "auto" then
                    autoMode()
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
    )
end

main()
