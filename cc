-- ========================================
-- ae2.lua — Create AE2 Kontroller
-- Create 6.0+ | CC:Tweaked 1.117.1
-- ========================================

local VAULT = peripheral.wrap("create:item_vault_0")
local CRAFTER = peripheral.wrap("create:mechanical_crafter_0")
local OUTPUT = peripheral.wrap("right")
local MONITOR = peripheral.find("monitor")

local KONFIG_FILE = "ae2_slots.txt"
local RECEPTS_FILE = "ae2_recepts.txt"

local SLOTS = {input = {}, output = {}}
local RECEPTS = {}
local OCHERED = {}
local STATUS = "Ozhidaniye"

-- === FAYLY ===
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
    local data = loadData(KONFIG_FILE)
    if data and data.input and data.output 
       and type(data.input) == "table" and type(data.output) == "table" then
        SLOTS = data
        return true
    end
    SLOTS = {input = {}, output = {}}
    return false
end

function initRecepts()
    local data = loadData(RECEPTS_FILE)
    if data and type(data) == "table" then
        RECEPTS = data
        return true
    end
    RECEPTS = {}
    return false
end

-- === KALIBROVKA ===
function kalibrovka()
    STATUS = "Kalibrovka..."
    drawUI()
    
    print("=== KALIBROVKA ===")
    print("Pustoy kraftr, 1 palochka v vault, vrashcheniye podklyucheno")
    print("Nazhmi Enter...")
    read()
    
    if not CRAFTER then 
        STATUS = "OSHIbka: Net kraftra!"
        print(STATUS)
        return false 
    end
    
    local total = CRAFTER.size()
    print("Slotov: " .. total)
    
    -- Chistim kraftr
    for i = 1, total do
        local item = CRAFTER.getItemDetail(i)
        if item then
            CRAFTER.pushItems(peripheral.getName(VAULT), i)
        end
    end
    
    SLOTS = {input = {}, output = {}}
    
    -- Test: ishem palochku v vault
    local stickSlot = nil
    for i = 1, VAULT.size() do
        local item = VAULT.getItemDetail(i)
        if item and item.name == "minecraft:stick" then
            stickSlot = i
            break
        end
    end
    
    if not stickSlot then
        STATUS = "OSHIbka: Net palochek v vault!"
        print(STATUS)
        return false
    end
    
    -- Kladom v kraftr (arg #2 = slot istochnika v vault, arg #4 = slot naznacheniya v kraftr)
    local moved = VAULT.pushItems(peripheral.getName(CRAFTER), stickSlot, 1, 1)
    
    if moved == 0 then
        STATUS = "OSHIbka: Ne udalos polozhit!"
        print(STATUS)
        return false
    end
    
    -- Ishem palochku v kraftr
    for i = 1, total do
        local item = CRAFTER.getItemDetail(i)
        if item and item.name == "minecraft:stick" then
            table.insert(SLOTS.input, i)
            print("  Vkhodnoy slot: " .. i)
            CRAFTER.pushItems(peripheral.getName(VAULT), i)
        end
    end
    
    -- Ostalnye — vykhodnye
    for i = 1, total do
        local found = false
        for _, v in ipairs(SLOTS.input) do if v == i then found = true end end
        if not found then table.insert(SLOTS.output, i) end
    end
    
    print("Vkhodnye: " .. #SLOTS.input .. ", Vykhodnye: " .. #SLOTS.output)
    saveData(KONFIG_FILE, SLOTS)
    
    STATUS = "OK: Kalibrovka zavershena!"
    print(STATUS)
    return true
end

-- === OBUCHENIYE ===
function obucheniye()
    if #SLOTS.input == 0 then 
        STATUS = "OSHIbka: Snachala kalibrovka!"
        print(STATUS)
        return 
    end
    
    STATUS = "Obucheniye..."
    drawUI()
    
    print("Polozhi predmety V RUKU v kraftr, dozhdisya krafta, nazhmi Enter")
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
        STATUS = "OSHIbka: Kraftr pust!"
        print(STATUS)
        return 
    end
    
    -- Ishem rezultat
    local rezultat = nil
    for _, s in ipairs(SLOTS.output) do
        local item = CRAFTER.getItemDetail(s)
        if item then rezultat = item.name; break end
    end
    
    if not rezultat and OUTPUT then
        for s = 1, OUTPUT.size() do
            local item = OUTPUT.getItemDetail(s)
            if item then rezultat = item.name; break end
        end
    end
    
    if not rezultat then
        print("Vvedi rezultat v ruchnuyu:")
        rezultat = read()
        if rezultat == "" then 
            STATUS = "Otmeneno"
            return 
        end
    end
    
    print("Rezultat: " .. rezultat)
    print("Nazvaniye recepts:")
    local name = read()
    if name == "" then 
        STATUS = "Otmeneno"
        return 
    end
    
    RECEPTS[name] = {slots = slots, rezultat = rezultat}
    saveData(RECEPTS_FILE, RECEPTS)
    
    STATUS = "OK: Recept '" .. name .. "' sohranen!"
    print(STATUS)
    zabratRezultat()
end

-- === KRAFT ===
function vaultItems()
    local t = {}
    if not VAULT then return t end
    for i = 1, VAULT.size() do
        local item = VAULT.getItemDetail(i)
        if item then t[item.name] = (t[item.name] or 0) + item.count end
    end
    return t
end

function receptNeeds(recept)
    local t = {}
    for _, item in pairs(recept.slots) do
        t[item] = (t[item] or 0) + 1
    end
    return t
end

function proverkaResursov(req)
    local have = vaultItems()
    for item, count in pairs(req) do
        if (have[item] or 0) < count then
            return false, item .. ": " .. (have[item] or 0) .. "/" .. count
        end
    end
    return true
end

function chistkaKraftra()
    for _, s in ipairs(SLOTS.input) do
        if CRAFTER.getItemDetail(s) then
            CRAFTER.pushItems(peripheral.getName(VAULT), s)
        end
    end
    for _, s in ipairs(SLOTS.output) do
        if CRAFTER.getItemDetail(s) then
            CRAFTER.pushItems(peripheral.getName(VAULT), s)
        end
    end
end

function zagruzitRecept(recept)
    for slotStr, item in pairs(recept.slots) do
        local slot = tonumber(slotStr)
        -- Ishem predmet v vault
        local found = false
        for vSlot = 1, VAULT.size() do
            local vItem = VAULT.getItemDetail(vSlot)
            if vItem and vItem.name == item then
                local moved = VAULT.pushItems(peripheral.getName(CRAFTER), vSlot, 1, slot)
                if moved > 0 then
                    found = true
                    break
                end
            end
        end
        if not found then
            print("OSHIbka: Net " .. item)
            return false
        end
    end
    return true
end

function zabratRezultat()
    local n = 0
    for _, s in ipairs(SLOTS.output) do
        local item = CRAFTER.getItemDetail(s)
        if item then n = n + CRAFTER.pushItems(peripheral.getName(VAULT), s) end
    end
    if OUTPUT then
        for s = 1, OUTPUT.size() do
            local item = OUTPUT.getItemDetail(s)
            if item then n = n + OUTPUT.pushItems(peripheral.getName(VAULT), s) end
        end
    end
    return n
end

function zanyat()
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

function kraft(name)
    local recept = RECEPTS[name]
    if not recept then 
        STATUS = "OSHIbka: Net recepts '" .. name .. "'"
        print(STATUS)
        return false 
    end
    
    STATUS = "Kraft: " .. name .. "..."
    drawUI()
    print("=== KRAFT: " .. name .. " ===")
    
    local ok, msg = proverkaResursov(receptNeeds(recept))
    if not ok then 
        STATUS = "OSHIbka: " .. msg
        print(STATUS)
        return false 
    end
    
    chistkaKraftra()
    sleep(0.5)
    
    print("Zagruzka...")
    if not zagruzitRecept(recept) then 
        STATUS = "OSHIbka: Zagruzka neudachna!"
        return false 
    end
    
    print("Ozhidaniye...")
    local t = 0
    while t < 30 do
        sleep(1)
        t = t + 1
        if zanyat() then 
            print("OK: Gotovo za " .. t .. "s")
            break 
        end
    end
    
    sleep(1)
    local n = zabratRezultat()
    if n > 0 then
        STATUS = "OK: Polucheno " .. n .. "x " .. recept.rezultat
        print(STATUS)
    else
        STATUS = "VNIMANIYe: Nichego!"
        print(STATUS)
    end
    
    chistkaKraftra()
    return n > 0
end

-- === OCHERED ===
function vOchered(name)
    if not RECEPTS[name] then 
        STATUS = "OSHIbka: Net recepts '" .. name .. "'"
        print(STATUS)
        return 
    end
    table.insert(OCHERED, name)
    STATUS = "V ocheredi: " .. name .. " (" .. #OCHERED .. " vsego)"
    print(STATUS)
end

function obrabotkaOcheredi()
    if #OCHERED > 0 and not zanyat() then
        local next = table.remove(OCHERED, 1)
        kraft(next)
    end
end

function avtoRezhim()
    STATUS = "Avto rezhim"
    drawUI()
    while true do
        obrabotkaOcheredi()
        drawUI()
        sleep(2)
    end
end

-- === UI (MONITOR) ===
local KNOPKI = {}

function drawKnopka(x, y, w, h, text, color, id)
    local oldColor = MONITOR.getBackgroundColor()
    MONITOR.setBackgroundColor(color or colors.gray)
    for by = y, y + h - 1 do
        MONITOR.setCursorPos(x, by)
        for bx = x, x + w - 1 do
            MONITOR.write(" ")
        end
    end
    
    MONITOR.setCursorPos(x + math.floor((w - #text) / 2), y + math.floor((h - 1) / 2))
    MONITOR.setTextColor(colors.white)
    MONITOR.write(text)
    
    MONITOR.setBackgroundColor(oldColor)
    
    table.insert(KNOPKI, {
        x = x, y = y, w = w, h = h, 
        id = id or text
    })
end

function drawUI()
    if not MONITOR then return end
    
    KNOPKI = {}
    
    MONITOR.setBackgroundColor(colors.black)
    MONITOR.clear()
    
    -- Zagolovok
    MONITOR.setTextColor(colors.cyan)
    MONITOR.setCursorPos(1, 1)
    MONITOR.write("=== CREATE AE2 ===")
    
    -- Status
    MONITOR.setTextColor(colors.yellow)
    MONITOR.setCursorPos(1, 2)
    MONITOR.write("Status: " .. STATUS)
    
    -- Info
    MONITOR.setTextColor(colors.lightGray)
    MONITOR.setCursorPos(1, 3)
    local rc = 0; for _ in pairs(RECEPTS) do rc = rc + 1 end
    MONITOR.write("Sloty: V" .. #SLOTS.input .. " Vy" .. #SLOTS.output .. " | Recepty: " .. rc)
    
    -- Ochered
    MONITOR.setTextColor(colors.pink)
    MONITOR.setCursorPos(1, 4)
    MONITOR.write("Ochered: " .. #OCHERED)
    
    -- Glavnye knopki
    drawKnopka(1, 6, 8, 3, "KALIB", colors.blue, "kalibrovka")
    drawKnopka(10, 6, 8, 3, "OBUCH", colors.green, "obucheniye")
    drawKnopka(19, 6, 8, 3, "AVTO", colors.orange, "avto")
    drawKnopka(28, 6, 8, 3, "CHIST", colors.red, "chistka")
    
    -- Recepty
    MONITOR.setTextColor(colors.white)
    MONITOR.setCursorPos(1, 10)
    MONITOR.write("=== RECEPTY ===")
    
    local y = 12
    local x = 1
    for name, recept in pairs(RECEPTS) do
        if y > 18 then break end
        
        local short = recept.rezultat:gsub(".*:", "")
        local label = name .. ">" .. short
        
        drawKnopka(x, y, 18, 2, label, colors.purple, "kraft:" .. name)
        
        x = x + 19
        if x > 30 then
            x = 1
            y = y + 3
        end
    end
    
    -- Podskazka
    MONITOR.setTextColor(colors.gray)
    MONITOR.setCursorPos(1, 19)
    MONITOR.write("Nazhmi knopku dlya upravleniya")
end

function obrabotkaKnopki(x, y)
    for _, btn in ipairs(KNOPKI) do
        if x >= btn.x and x < btn.x + btn.w 
           and y >= btn.y and y < btn.y + btn.h then
            return btn.id
        end
    end
    return nil
end

function runKomanda(cmd)
    if cmd == "kalibrovka" then
        kalibrovka()
    elseif cmd == "obucheniye" then
        obucheniye()
    elseif cmd == "avto" then
        parallel.waitForAny(
            function()
                while true do
                    obrabotkaOcheredi()
                    drawUI()
                    sleep(2)
                end
            end,
            function()
                while true do
                    local event, side, x, y = os.pullEvent("monitor_touch")
                    local clicked = obrabotkaKnopki(x, y)
                    if clicked == "chistka" then
                        STATUS = "Avto ostanovlen"
                        break
                    end
                end
            end
        )
    elseif cmd == "chistka" then
        chistkaKraftra()
        zabratRezultat()
        OCHERED = {}
        STATUS = "Ochishcheno"
    elseif cmd:sub(1, 6) == "kraft:" then
        local name = cmd:sub(7)
        vOchered(name)
        obrabotkaOcheredi()
    end
    drawUI()
end

-- === KOMANDY (terminal) ===
function spisok()
    for name, count in pairs(vaultItems()) do
        print(name .. ": " .. count)
    end
end

function pokazatRecepty()
    for name, r in pairs(RECEPTS) do
        print(name .. " -> " .. r.rezultat)
    end
end

function udalit(name)
    if RECEPTS[name] then
        RECEPTS[name] = nil
        saveData(RECEPTS_FILE, RECEPTS)
        STATUS = "Udaleno: " .. name
        print(STATUS)
    else
        STATUS = "Ne naydeno: " .. name
        print(STATUS)
    end
end

-- === GLAVNAYA ===
function main()
    print("=== Create AE2 ===")
    initSlots()
    initRecepts()
    
    print("Vkhodnye: " .. #SLOTS.input .. ", Vykhodnye: " .. #SLOTS.output)
    local n = 0; for _ in pairs(RECEPTS) do n = n + 1 end
    print("Receptov: " .. n)
    
    if #SLOTS.input == 0 then
        print("\nPervyy zapusk! Nazhmi KALIB na monitore ili vvedi 'kalibrovka'")
    end
    
    drawUI()
    
    parallel.waitForAny(
        function()
            while true do
                local event, side, x, y = os.pullEvent("monitor_touch")
                local cmd = obrabotkaKnopki(x, y)
                if cmd then
                    print("Nazhato: " .. cmd)
                    runKomanda(cmd)
                end
            end
        end,
        function()
            while true do
                write("> ")
                local input = read()
                local args = {}
                for word in input:gmatch("%S+") do table.insert(args, word) end
                
                if #args == 0 then
                    -- pusto
                elseif args[1] == "kalibrovka" then
                    kalibrovka()
                elseif args[1] == "obucheniye" then
                    obucheniye()
                elseif args[1] == "kraft" and args[2] then
                    kraft(args[2])
                elseif args[1] == "spisok" then
                    spisok()
                elseif args[1] == "recepty" then
                    pokazatRecepty()
                elseif args[1] == "q" and args[2] then
                    vOchered(args[2])
                elseif args[1] == "avto" then
                    avtoRezhim()
                elseif args[1] == "udalit" and args[2] then
                    udalit(args[2])
                elseif args[1] == "vykhod" then
                    break
                else
                    print("Neizvestno: " .. args[1])
                end
                
                drawUI()
            end
        end
    )
end

main()
