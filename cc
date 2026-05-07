-- ========================================
-- ae2.lua — Create AE2 Controller v3.2
-- ========================================

local VAULT = peripheral.wrap("create:item_vault_0")
local CRAFTER = peripheral.wrap("create:mechanical_crafter_0")
local OUTPUT = peripheral.wrap("right")
local MONITOR = peripheral.find("monitor")

local CONFIG_FILE = "ae2_slots.txt"
local RECIPES_FILE = "ae2_recipes.txt"

-- Гарантированная инициализация
local SLOTS = {input = {}, output = {}}
local RECIPES = {}

-- === ФАЙЛЫ ===
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

-- === ИНИЦИАЛИЗАЦИЯ ===
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

-- === КАЛИБРОВКА ===
function calibrate()
    print("=== КАЛИБРОВКА ===")
    print("Убедись: крафтер ПУСТ, есть палки в Vault, подключено вращение")
    print("Нажми Enter...")
    read()
    
    if not CRAFTER then print("❌ Нет крафтера!"); return false end
    
    local total = CRAFTER.size()
    print("Слотов: " .. total)
    
    -- Чистим
    for i = 1, total do
        if CRAFTER.getItemDetail(i) then
            VAULT.pullItems(peripheral.getName(CRAFTER), i)
        end
    end
    
    SLOTS = {input = {}, output = {}}
    
    -- Тест
    if VAULT.pushItems(peripheral.getName(CRAFTER), "minecraft:stick", 1) == 0 then
        print("❌ Нет палок в Vault!")
        return false
    end
    
    -- Ищем палку
    for i = 1, total do
        local item = CRAFTER.getItemDetail(i)
        if item and item.name == "minecraft:stick" then
            table.insert(SLOTS.input, i)
            print("  Вход: " .. i)
            VAULT.pullItems(peripheral.getName(CRAFTER), i)
        end
    end
    
    -- Остальные — выход
    for i = 1, total do
        local found = false
        for _, v in ipairs(SLOTS.input) do if v == i then found = true end end
        if not found then table.insert(SLOTS.output, i) end
    end
    
    print("Вход: " .. #SLOTS.input .. ", Выход: " .. #SLOTS.output)
    saveData(CONFIG_FILE, SLOTS)
    print("✅ Сохранено!")
    return true
end

-- === ОБУЧЕНИЕ ===
function learn()
    if #SLOTS.input == 0 then print("❌ Сначала calibrate()!"); return end
    
    print("Положи предметы в крафтер, дождись крафта, нажми Enter")
    read()
    
    local slots = {}
    local has = false
    
    for _, s in ipairs(SLOTS.input) do
        local item = CRAFTER.getItemDetail(s)
        if item then
            slots[tostring(s)] = item.name
            has = true
            print("  Слот " .. s .. ": " .. item.name)
        end
    end
    
    if not has then print("❌ Пусто!"); return end
    
    -- Результат
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
        print("Введи результат вручную:")
        result = read()
        if result == "" then return end
    end
    
    print("Результат: " .. result)
    print("Название рецепта:")
    local name = read()
    if name == "" then return end
    
    RECIPES[name] = {slots = slots, result = result}
    saveData(RECIPES_FILE, RECIPES)
    print("✅ " .. name)
    store()
end

-- === КРАФТ ===
function vaultItems()
    local t = {}
    if not VAULT then return t end
    for i = 1, VAULT.size() do
        local item = VAULT.getItemDetail(i)
        if item then t[item.name] = (t[item.name] or 0) + item.count end
    end
    return t
end

function needs(recipe)
    local t = {}
    for _, item in pairs(recipe.slots) do
        t[item] = (t[item] or 0) + 1
    end
    return t
end

function check(req)
    local have = vaultItems()
    for item, count in pairs(req) do
        if (have[item] or 0) < count then
            return false, item .. ": " .. (have[item] or 0) .. "/" .. count
        end
    end
    return true
end

function clear()
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

function loadR(recipe)
    for slotStr, item in pairs(recipe.slots) do
        local slot = tonumber(slotStr)
        if VAULT.pushItems(peripheral.getName(CRAFTER), item, 1, slot) == 0 then
            print("❌ Нет " .. item)
            return false
        end
    end
    return true
end

function store()
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

function busy()
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
    if not recipe then print("❌ Нет рецепта: " .. name); return false end
    
    print("=== " .. name .. " ===")
    
    local ok, msg = check(needs(recipe))
    if not ok then print("❌ " .. msg); return false end
    
    clear()
    sleep(0.5)
    
    print("📦 Загрузка...")
    if not loadR(recipe) then return false end
    
    print("⚙️ Ждём...")
    local t = 0
    while t < 30 do
        sleep(1)
        t = t + 1
        if busy() then print("✅ Готово за " .. t .. "с"); break end
    end
    
    sleep(1)
    local n = store()
    print(n > 0 and ("✅ " .. n .. " шт") or "⚠️ Ничего!")
    clear()
    return n > 0
end

-- === ИНТЕРФЕЙС ===
function ui()
    if not MONITOR then return end
    MONITOR.clear()
    MONITOR.setCursorPos(1,1)
    MONITOR.write("Create AE2")
    MONITOR.setCursorPos(1,2)
    if #SLOTS.input == 0 then
        MONITOR.write("calibrate!")
    elseif busy() then
        MONITOR.write("работаю...")
    else
        MONITOR.write("готов")
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

-- === КОМАНДЫ ===
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
        print("✅ Удалён")
    else
        print("❌ Нет такого")
    end
end

-- === АВТО ===
local Q = {}
function q(name)
    if not RECIPES[name] then print("❌ Нет рецепта"); return end
    table.insert(Q, name)
    print("📋 " .. name .. " (всего: " .. #Q .. ")")
end

function auto()
    while true do
        if #Q > 0 and not busy() then
            craft(table.remove(Q, 1))
        end
        ui()
        sleep(2)
    end
end

-- === ЗАПУСК ===
print("=== Create AE2 ===")
initSlots()
initRecipes()

print("Вход: " .. #SLOTS.input .. ", Выход: " .. #SLOTS.output)
local n = 0; for _ in pairs(RECIPES) do n = n + 1 end
print("Рецептов: " .. n)

if #SLOTS.input == 0 then
    print("\n⚠️ Первый запуск! Введи: calibrate()")
end

print("\nКоманды: calibrate() learn() craft('name') list() showRecipes() q('name') auto() del('name')")
