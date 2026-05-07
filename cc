-- ========================================
-- Create AE2 Controller v3.1 (FIX)
-- Create 6.0+ | CC:Tweaked 1.117.1
-- ========================================

-- === НАСТРОЙКА ПЕРИФЕРИИ ===
local VAULT = peripheral.wrap("create:item_vault_0")           -- Хранилище
local CRAFTER = peripheral.wrap("create:mechanical_crafter_0") -- 5x5 крафтер
local OUTPUT = peripheral.wrap("right")                        -- Бочка выхода (или nil)

local MONITOR = peripheral.find("monitor")

-- === КОНФИГ ===
local CONFIG_FILE = "ae2_config.txt"
local RECIPES_FILE = "ae2_recipes.txt"

-- Структура: {input = {1,2,3...}, output = {26,27...}}
local SLOTS = {
    input = {},
    output = {}
}

-- Рецепты
local RECIPES = {}

-- ========================================
-- УТИЛИТЫ ФАЙЛОВ
-- ========================================

function loadTable(filename)
    if fs.exists(filename) then
        local f = fs.open(filename, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        return data
    end
    return nil
end

function saveTable(filename, data)
    local f = fs.open(filename, "w")
    f.write(textutils.serialize(data))
    f.close()
end

-- ========================================
-- КАЛИБРОВКА СЛОТОВ
-- ========================================

function calibrate()
    print("=== КАЛИБРОВКА СЛОТОВ ===")
    print("Убедись, что крафтер ПУСТ и подключён к вращению!")
    print("Нажми Enter для начала...")
    read()
    
    if not CRAFTER then
        print("❌ Крафтер не подключен!")
        return false
    end
    
    -- Размер
    local totalSlots = CRAFTER.size()
    print("Всего слотов: " .. totalSlots)
    
    -- Очищаем всё
    for slot = 1, totalSlots do
        local item = CRAFTER.getItemDetail(slot)
        if item then
            VAULT.pullItems(peripheral.getName(CRAFTER), slot)
        end
    end
    
    -- Сбрасываем структуру
    SLOTS = {input = {}, output = {}}
    
    print("Тестирование входных слотов...")
    
    -- Берём тестовый предмет
    local testItem = "minecraft:stick"
    local moved = VAULT.pushItems(peripheral.getName(CRAFTER), testItem, 1)
    
    if moved == 0 then
        print("❌ Нет палок в Vault! Положи хотя бы 1.")
        return false
    end
    
    -- Ищем куда попало
    for slot = 1, totalSlots do
        local item = CRAFTER.getItemDetail(slot)
        if item and item.name == testItem then
            table.insert(SLOTS.input, slot)
            print("  Входной слот: " .. slot)
            -- Забираем обратно
            VAULT.pullItems(peripheral.getName(CRAFTER), slot)
        end
    end
    
    -- Остальные — выходные
    for slot = 1, totalSlots do
        local isInput = false
        for _, inp in ipairs(SLOTS.input) do
            if inp == slot then isInput = true; break end
        end
        if not isInput then
            table.insert(SLOTS.output, slot)
        end
    end
    
    print("Входных: " .. #SLOTS.input)
    print("Выходных: " .. #SLOTS.output)
    
    saveTable(CONFIG_FILE, SLOTS)
    print("✅ Калибровка сохранена!")
    return true
end

function loadConfig()
    local data = loadTable(CONFIG_FILE)
    
    -- Проверяем, что данные корректные
    if data and type(data) == "table" and data.input and data.output 
       and type(data.input) == "table" and type(data.output) == "table"
       and #data.input > 0 then
        SLOTS = data
        return true
    end
    
    -- Инициализируем пустую структуру
    SLOTS = {input = {}, output = {}}
    return false
end

-- ========================================
-- ОБУЧЕНИЕ РЕЦЕПТАМ
-- ========================================

function learnRecipe()
    print("=== ОБУЧЕНИЕ РЕЦЕПТА ===")
    
    if #SLOTS.input == 0 then
        print("❌ Сначала выполни calibrate()!")
        return
    end
    
    print("1. Положи предметы ВРУЧНУЮ в крафтер")
    print("2. Дождись завершения крафта")
    print("3. Нажми Enter")
    read()
    
    -- Сканируем входные слоты
    local recipeSlots = {}
    local hasItems = false
    
    for _, slot in ipairs(SLOTS.input) do
        local item = CRAFTER.getItemDetail(slot)
        if item then
            recipeSlots[tostring(slot)] = item.name  -- ключ как строка для сериализации
            hasItems = true
            print("  Слот " .. slot .. ": " .. item.name)
        end
    end
    
    if not hasItems then
        print("❌ Входные слоты пусты!")
        return
    end
    
    -- Ищем результат
    local resultItem = nil
    local resultSlots = {}
    
    -- В выходных слотах крафтера
    for _, slot in ipairs(SLOTS.output) do
        local item = CRAFTER.getItemDetail(slot)
        if item then
            resultItem = item.name
            table.insert(resultSlots, slot)
        end
    end
    
    -- В бочке выхода
    if OUTPUT and not resultItem then
        for slot = 1, OUTPUT.size() do
            local item = OUTPUT.getItemDetail(slot)
            if item then
                resultItem = item.name
                table.insert(resultSlots, "out:" .. slot)
            end
        end
    end
    
    if not resultItem then
        print("⚠️ Результат не найден!")
        print("Введи название результата вручную (или Enter для отмены):")
        resultItem = read()
        if resultItem == "" then return end
    end
    
    print("Результат: " .. resultItem)
    print("Введи название рецепта:")
    local recipeName = read()
    if recipeName == "" then print("❌ Отмена"); return end
    
    RECIPES[recipeName] = {
        slots = recipeSlots,
        result = resultItem,
        result_slots = resultSlots
    }
    
    saveTable(RECIPES_FILE, RECIPES)
    print("✅ Сохранён: " .. recipeName)
    
    storeOutput()
end

-- ========================================
-- ВЫПОЛНЕНИЕ РЕЦЕПТА
-- ========================================

function vaultItems()
    local items = {}
    if not VAULT then return items end
    for slot = 1, VAULT.size() do
        local item = VAULT.getItemDetail(slot)
        if item then
            items[item.name] = (items[item.name] or 0) + item.count
        end
    end
    return items
end

function vaultHas(required)
    local have = vaultItems()
    for item, count in pairs(required) do
        if (have[item] or 0) < count then
            return false, item .. ": нужно " .. count .. ", есть " .. (have[item] or 0)
        end
    end
    return true
end

function recipeNeeds(recipe)
    local needs = {}
    for slot, item in pairs(recipe.slots) do
        needs[item] = (needs[item] or 0) + 1
    end
    return needs
end

function clearCrafter()
    for _, slot in ipairs(SLOTS.input) do
        local item = CRAFTER.getItemDetail(slot)
        if item then
            VAULT.pullItems(peripheral.getName(CRAFTER), slot)
        end
    end
    for _, slot in ipairs(SLOTS.output) do
        local item = CRAFTER.getItemDetail(slot)
        if item then
            VAULT.pullItems(peripheral.getName(CRAFTER), slot)
        end
    end
end

function loadRecipe(recipe)
    for slotStr, itemName in pairs(recipe.slots) do
        local slot = tonumber(slotStr)
        local moved = VAULT.pushItems(peripheral.getName(CRAFTER), itemName, 1, slot)
        if moved == 0 then
            print("❌ Не удалось: " .. itemName .. " в слот " .. slot)
            return false
        end
    end
    return true
end

function storeOutput()
    local total = 0
    
    for _, slot in ipairs(SLOTS.output) do
        local item = CRAFTER.getItemDetail(slot)
        if item then
            total = total + VAULT.pullItems(peripheral.getName(CRAFTER), slot)
        end
    end
    
    if OUTPUT then
        for slot = 1, OUTPUT.size() do
            local item = OUTPUT.getItemDetail(slot)
            if item then
                total = total + VAULT.pullItems(peripheral.getName(OUTPUT), slot)
            end
        end
    end
    
    return total
end

function isCrafting()
    for _, slot in ipairs(SLOTS.output) do
        if CRAFTER.getItemDetail(slot) then return true end
    end
    if OUTPUT then
        for slot = 1, OUTPUT.size() do
            if OUTPUT.getItemDetail(slot) then return true end
        end
    end
    return false
end

function craft(recipeName)
    local recipe = RECIPES[recipeName]
    if not recipe then
        print("❌ Рецепт не найден: " .. recipeName)
        return false
    end
    
    print("=== Крафт: " .. recipeName .. " ===")
    
    local needs = recipeNeeds(recipe)
    local ok, msg = vaultHas(needs)
    if not ok then
        print("❌ Недостаточно ресурсов: " .. msg)
        return false
    end
    
    clearCrafter()
    sleep(0.5)
    
    print("📦 Загрузка...")
    if not loadRecipe(recipe) then return false end
    
    print("⚙️ Ожидание...")
    local waitTime = 0
    while waitTime < 30 do
        sleep(1)
        waitTime = waitTime + 1
        if isCrafting() then
            print("✅ Готово за " .. waitTime .. " сек")
            break
        end
    end
    
    sleep(1)
    local resultCount = storeOutput()
    print(resultCount > 0 and ("✅ Получено: " .. resultCount) or "⚠️ Результат не найден!")
    
    clearCrafter()
    return resultCount > 0
end

-- ========================================
-- ИНТЕРФЕЙС
-- ========================================

function drawUI()
    if not MONITOR then return end
    MONITOR.clear()
    MONITOR.setCursorPos(1, 1)
    MONITOR.write("=== Create AE2 ===")
    
    MONITOR.setCursorPos(1, 2)
    if #SLOTS.input == 0 then
        MONITOR.write("❌ Нужна калибровка!")
    elseif isCrafting() then
        MONITOR.write("⚙️ Крафтинг...")
    else
        MONITOR.write("✅ Готов")
    end
    
    MONITOR.setCursorPos(1, 4)
    MONITOR.write("Рецепты:")
    local y = 5
    for name, recipe in pairs(RECIPES) do
        MONITOR.setCursorPos(1, y)
        local short = recipe.result:gsub("minecraft:", ""):gsub("create:", "")
        MONITOR.write("  " .. name .. " -> " .. short)
        y = y + 1
        if y > 18 then break end
    end
end

-- ========================================
-- КОМАНДЫ
-- ========================================

function list()
    print("=== Vault ===")
    for name, count in pairs(vaultItems()) do
        print("  " .. name .. ": " .. count)
    end
end

function recipes()
    print("=== Рецепты ===")
    for name, recipe in pairs(RECIPES) do
        print("  " .. name .. " -> " .. recipe.result)
    end
end

function deleteRecipe(name)
    if RECIPES[name] then
        RECIPES[name] = nil
        saveTable(RECIPES_FILE, RECIPES)
        print("✅ Удалён: " .. name)
    else
        print("❌ Не найден")
    end
end

-- ========================================
-- АВТОРЕЖИМ
-- ========================================

local QUEUE = {}

function queue(name)
    if not RECIPES[name] then
        print("❌ Рецепт не существует")
        return
    end
    table.insert(QUEUE, name)
    print("📋 Добавлено: " .. name .. " (в очереди: " .. #QUEUE .. ")")
end

function autoMode()
    print("=== Авторежим ===")
    while true do
        if #QUEUE > 0 and not isCrafting() then
            craft(table.remove(QUEUE, 1))
        end
        drawUI()
        sleep(2)
    end
end

-- ========================================
-- ЗАПУСК
-- ========================================

function init()
    print("=== Create AE2 Controller v3.1 ===")
    
    -- Загружаем конфиг с проверкой
    local hasConfig = loadConfig()
    if hasConfig then
        print("✅ Конфиг: " .. #SLOTS.input .. " входных, " .. #SLOTS.output .. " выходных")
    else
        print("⚠️ Нет конфигурации! Введи calibrate()")
    end
    
    -- Загружаем рецепты
    local data = loadTable(RECIPES_FILE)
    if data and type(data) == "table" then
        RECIPES = data
    else
        RECIPES = {}
    end
    
    local count = 0
    for _ in pairs(RECIPES) do count = count + 1 end
    print("✅ Рецептов: " .. count)
    
    print("\nКоманды:")
    print("  calibrate()      — первая настройка")
    print("  learnRecipe()    — обучить рецепт")
    print("  craft('name')      — выполнить")
    print("  recipes()          — список")
    print("  list()             — инвентарь")
    print("  queue('name')      — в очередь")
    print("  autoMode()         — автовыполнение")
    print("  deleteRecipe('n')  — удалить")
end

init()
