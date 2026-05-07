-- ========================================
-- Create AE2 Controller v3
-- Create 6.0+ | CC:Tweaked 1.117.1
-- ========================================

-- === НАСТРОЙКА ПЕРИФЕРИИ ===
local VAULT = peripheral.wrap("create:item_vault_0")           -- Хранилище
local CRAFTER = peripheral.wrap("create:mechanical_crafter_0") -- 5x5 крафтер
local OUTPUT = peripheral.wrap("right")                        -- Бочка выхода (или nil если результат в крафтере)

local MONITOR = peripheral.find("monitor")

-- === КОНФИГ ===
local CONFIG_FILE = "ae2_config.txt"
local RECIPES_FILE = "ae2_recipes.txt"

-- Структура: {input_slots = {1,2,3...}, output_slots = {26,27...}} — определяется при калибровке
local SLOTS = {
    input = {},   -- 25 входных слотов (5x5)
    output = {}   -- выходные слоты
}

-- Рецепты: {name = {slots = {[slot]=item, ...}, result = "item", result_slots = {}}}
local RECIPES = {}

-- ========================================
-- УТИЛИТЫ ФАЙЛОВ
-- ========================================

function loadTable(filename)
    if fs.exists(filename) then
        local f = fs.open(filename, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        return data or {}
    end
    return {}
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
    
    -- Определяем размер
    local totalSlots = CRAFTER.size()
    print("Всего слотов: " .. totalSlots)
    
    -- Очищаем всё
    for slot = 1, totalSlots do
        local item = CRAFTER.getItemDetail(slot)
        if item then
            VAULT.pullItems(peripheral.getName(CRAFTER), slot)
        end
    end
    
    SLOTS.input = {}
    SLOTS.output = {}
    
    -- Метод 1: Проверяем, в какие слоты можно положить (входные)
    -- Кладём тестовый предмет в каждый слот и смотрим, где он остаётся
    print("Тестирование входных слотов...")
    
    -- Берём 1 палку из Vault для теста
    local testItem = "minecraft:stick"
    local moved = VAULT.pushItems(peripheral.getName(CRAFTER), testItem, 1)
    
    if moved == 0 then
        print("❌ Нет палок в Vault! Положи хотя бы 1 палку.")
        return false
    end
    
    -- Ищем, куда палка попала
    for slot = 1, totalSlots do
        local item = CRAFTER.getItemDetail(slot)
        if item and item.name == testItem then
            table.insert(SLOTS.input, slot)
            print("  Входной слот: " .. slot)
            -- Забираем обратно
            VAULT.pullItems(peripheral.getName(CRAFTER), slot)
        end
    end
    
    -- Остальные слоты — выходные (если есть)
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
    
    -- Сохраняем
    saveTable(CONFIG_FILE, SLOTS)
    print("✅ Калибровка сохранена!")
    
    return true
end

function loadConfig()
    SLOTS = loadTable(CONFIG_FILE)
    if #SLOTS.input > 0 then
        print("✅ Конфиг загружен: " .. #SLOTS.input .. " входных, " .. #SLOTS.output .. " выходных")
        return true
    end
    return false
end

-- ========================================
-- ОБУЧЕНИЕ РЕЦЕПТАМ (РУЧНОЙ ВВОД)
-- ========================================

function learnRecipe()
    print("=== ОБУЧЕНИЕ РЕЦЕПТА ===")
    
    if #SLOTS.input == 0 then
        print("❌ Сначала выполни калибровку!")
        return
    end
    
    print("1. Положи предметы ВРУЧНУЮ в крафтер (входные слоты)")
    print("2. Дождись завершения крафта (или нажми Enter если уже готово)")
    print("3. Введи название рецепта:")
    
    read() -- ждём Enter
    
    -- Сканируем входные слоты
    local recipeSlots = {}
    local hasItems = false
    
    for _, slot in ipairs(SLOTS.input) do
        local item = CRAFTER.getItemDetail(slot)
        if item then
            recipeSlots[slot] = item.name
            hasItems = true
            print("  Слот " .. slot .. ": " .. item.name)
        end
    end
    
    if not hasItems then
        print("❌ Входные слоты пусты!")
        return
    end
    
    -- Ищем результат в выходных слотах или бочке
    local resultItem = nil
    local resultSlots = {}
    
    -- Сначала проверяем выходные слоты крафтера
    for _, slot in ipairs(SLOTS.output) do
        local item = CRAFTER.getItemDetail(slot)
        if item then
            resultItem = item.name
            table.insert(resultSlots, slot)
        end
    end
    
    -- Если есть бочка, проверяем и её
    if OUTPUT then
        for slot = 1, OUTPUT.size() do
            local item = OUTPUT.getItemDetail(slot)
            if item then
                resultItem = item.name
                table.insert(resultSlots, "output:" .. slot)
            end
        end
    end
    
    if not resultItem then
        print("⚠️ Результат не найден! Убедись, что крафт завершён.")
        print("Введи название результата вручную (или Enter для отмены):")
        resultItem = read()
        if resultItem == "" then return end
    end
    
    print("Результат: " .. resultItem)
    print("Введи название рецепта:")
    local recipeName = read()
    
    if recipeName == "" then
        print("❌ Название не может быть пустым")
        return
    end
    
    -- Сохраняем рецепт
    RECIPES[recipeName] = {
        slots = recipeSlots,        -- {[slot] = item_name}
        result = resultItem,
        result_slots = resultSlots
    }
    
    saveTable(RECIPES_FILE, RECIPES)
    print("✅ Рецепт сохранён: " .. recipeName)
    
    -- Забираем результат в Vault
    storeOutput()
end

-- ========================================
-- ВЫПОЛНЕНИЕ РЕЦЕПТА (АВТОКРАФТ)
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

-- Подсчёт нужного количества каждого ингредиента из шаблона слотов
function recipeNeeds(recipe)
    local needs = {}
    for slot, item in pairs(recipe.slots) do
        needs[item] = (needs[item] or 0) + 1
    end
    return needs
end

function clearCrafter()
    -- Забираем всё из входных слотов в Vault
    for _, slot in ipairs(SLOTS.input) do
        local item = CRAFTER.getItemDetail(slot)
        if item then
            VAULT.pullItems(peripheral.getName(CRAFTER), slot)
        end
    end
    
    -- Забираем всё из выходных слотов
    for _, slot in ipairs(SLOTS.output) do
        local item = CRAFTER.getItemDetail(slot)
        if item then
            VAULT.pullItems(peripheral.getName(CRAFTER), slot)
        end
    end
end

function loadRecipe(recipe)
    -- Загружаем предметы в нужные слоты
    for slot, itemName in pairs(recipe.slots) do
        -- Ищем предмет в Vault и кладём в конкретный слот крафтера
        local moved = VAULT.pushItems(peripheral.getName(CRAFTER), itemName, 1, slot)
        if moved == 0 then
            print("❌ Не удалось положить " .. itemName .. " в слот " .. slot)
            return false
        end
    end
    return true
end

function storeOutput()
    local total = 0
    
    -- Забираем из выходных слотов крафтера
    for _, slot in ipairs(SLOTS.output) do
        local item = CRAFTER.getItemDetail(slot)
        if item then
            local moved = VAULT.pullItems(peripheral.getName(CRAFTER), slot)
            total = total + moved
        end
    end
    
    -- Забираем из бочки выхода
    if OUTPUT then
        for slot = 1, OUTPUT.size() do
            local item = OUTPUT.getItemDetail(slot)
            if item then
                local moved = VAULT.pullItems(peripheral.getName(OUTPUT), slot)
                total = total + moved
            end
        end
    end
    
    return total
end

function isCrafting()
    -- Проверяем, есть ли предметы во входных слотах (значит процесс идёт или завершён)
    -- Или проверяем выходные слоты на результат
    for _, slot in ipairs(SLOTS.output) do
        local item = CRAFTER.getItemDetail(slot)
        if item then return true end
    end
    
    -- Если в бочке есть предметы — тоже считаем что крафт завершён
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
    
    -- Проверяем ресурсы
    local needs = recipeNeeds(recipe)
    local ok, msg = vaultHas(needs)
    if not ok then
        print("❌ Недостаточно ресурсов: " .. msg)
        return false
    end
    
    -- Очищаем крафтер
    clearCrafter()
    sleep(0.5)
    
    -- Загружаем ингредиенты
    print("📦 Загрузка ингредиентов...")
    if not loadRecipe(recipe) then
        return false
    end
    
    -- Ждём завершения крафта
    print("⚙️ Ожидание крафта...")
    local waitTime = 0
    local maxWait = 30  -- максимум 30 секунд
    
    while waitTime < maxWait do
        sleep(1)
        waitTime = waitTime + 1
        
        -- Проверяем, появился ли результат
        if isCrafting() then
            print("✅ Крафт завершён за " .. waitTime .. " сек")
            break
        end
    end
    
    if waitTime >= maxWait then
        print("⚠️ Таймаут ожидания!")
    end
    
    -- Забираем результат
    sleep(1) -- пауза на выпадение
    local resultCount = storeOutput()
    
    if resultCount > 0 then
        print("✅ Получено: " .. resultCount .. " предметов")
    else
        print("⚠️ Результат не найден!")
    end
    
    -- Очищаем остатки ингредиентов (если что-то осталось)
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
    
    -- Статус
    MONITOR.setCursorPos(1, 2)
    if #SLOTS.input == 0 then
        MONITOR.write("❌ Нужна калибровка!")
    elseif isCrafting() then
        MONITOR.write("⚙️ Крафтинг...")
    else
        MONITOR.write("✅ Готов")
    end
    
    -- Рецепты
    MONITOR.setCursorPos(1, 4)
    MONITOR.write("Рецепты:")
    local y = 5
    for name, recipe in pairs(RECIPES) do
        MONITOR.setCursorPos(1, y)
        local shortResult = recipe.result:gsub("minecraft:", ""):gsub("create:", "")
        MONITOR.write("  " .. name .. " → " .. shortResult)
        y = y + 1
        if y > 18 then break end
    end
end

-- ========================================
-- КОМАНДЫ
-- ========================================

function list()
    print("=== Vault ===")
    local items = vaultItems()
    for name, count in pairs(items) do
        print("  " .. name .. ": " .. count)
    end
end

function recipes()
    print("=== Рецепты ===")
    for name, recipe in pairs(RECIPES) do
        print("  " .. name .. " → " .. recipe.result)
        print("    Слоты: " .. textutils.serialize(recipe.slots))
    end
end

function deleteRecipe(name)
    if RECIPES[name] then
        RECIPES[name] = nil
        saveTable(RECIPES_FILE, RECIPES)
        print("✅ Удалён: " .. name)
    else
        print("❌ Не найден: " .. name)
    end
end

-- ========================================
-- АВТОРЕЖИМ
-- ========================================

local QUEUE = {}

function queue(name)
    if not RECIPES[name] then
        print("❌ Рецепт не существует: " .. name)
        return
    end
    table.insert(QUEUE, name)
    print("📋 Добавлено: " .. name .. " (в очереди: " .. #QUEUE .. ")")
end

function autoMode()
    print("=== Авторежим ===")
    while true do
        if #QUEUE > 0 and not isCrafting() then
            local next = table.remove(QUEUE, 1)
            print("▶️ Выполняю: " .. next)
            craft(next)
        end
        drawUI()
        sleep(2)
    end
end

-- ========================================
-- ЗАПУСК
-- ========================================

function init()
    print("=== Create AE2 Controller v3 ===")
    
    -- Загружаем конфиг
    if not loadConfig() then
        print("⚠️ Нет конфигурации слотов!")
        print("Введи 'calibrate()' для первой настройки")
    end
    
    -- Загружаем рецепты
    RECIPES = loadTable(RECIPES_FILE)
    print("✅ Рецептов загружено: " .. 0)
    local count = 0
    for _ in pairs(RECIPES) do count = count + 1 end
    print("  Всего: " .. count)
    
    print("\nКоманды:")
    print("  calibrate()     — калибровка слотов (первый запуск!)")
    print("  learnRecipe()   — обучить новый рецепт")
    print("  craft('name')   — выполнить рецепт")
    print("  recipes()       — список рецептов")
    print("  list()          — инвентарь Vault")
    print("  queue('name')   — добавить в очередь")
    print("  autoMode()      — автовыполнение очереди")
    print("  deleteRecipe('name') — удалить рецепт")
end

-- Запускаем инициализацию
init()
