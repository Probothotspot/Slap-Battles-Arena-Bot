-- Bootstrap UI is local to this file and does not depend on remote modules.
local BASE = "https://raw.githubusercontent.com/Probothotspot/Slap-Battles-Arena-Bot/main/"
local TOTAL, TIMEOUT = 17, 20
local env = _G
if type(getgenv) == "function" then
    local ok, value = pcall(getgenv)
    if ok and type(value) == "table" then env = value end
end
local KEY = "SlapBattlesArenaBotLoader"
if type(env[KEY]) == "table" and type(env[KEY].Destroy) == "function" then
    pcall(function() env[KEY]:Destroy() end)
end
local player = game:GetService("Players").LocalPlayer
assert(player, "[ArenaBot] Loader requires a client player")
local parent = player:WaitForChild("PlayerGui", 10)
assert(parent, "[ArenaBot] PlayerGui is unavailable")
local inputService = game:GetService("UserInputService")
local report = { Completed = 0, Errors = 0, Warnings = 0, Finished = false,
    Destroyed = false, Connections = {}, Records = {}, RuntimeErrors = 0 }
env[KEY] = report
local colors = { ok = Color3.fromRGB(143,225,171), warning = Color3.fromRGB(255,205,115),
    error = Color3.fromRGB(255,135,145), skipped = Color3.fromRGB(160,160,180),
    running = Color3.fromRGB(205,185,255) }
local names = { ok = "ГОТОВО", warning = "ВНИМАНИЕ", error = "ОШИБКА",
    skipped = "ПРОПУЩЕНО", running = "ЗАГРУЗКА" }
local function create(class, properties, owner)
    local object = Instance.new(class)
    for key, value in pairs(properties) do object[key] = value end
    object.Parent = owner
    return object
end
local gui = create("ScreenGui", { Name = "ArenaBotLoadingGUI", ResetOnSpawn = false,
    DisplayOrder = 200, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, parent)
local window = create("Frame", { AnchorPoint = Vector2.new(0.5,0.5),
    Position = UDim2.fromScale(0.5,0.5), Size = UDim2.fromScale(0.92,0.78),
    BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(26,23,38) }, gui)
create("UISizeConstraint", { MinSize = Vector2.new(260,300), MaxSize = Vector2.new(480,560) }, window)
create("UICorner", { CornerRadius = UDim.new(0,14) }, window)
local function text(owner, value, position, size, fontSize)
    return create("TextLabel", { Text = value, Position = position, Size = size,
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = fontSize or 14,
        TextColor3 = Color3.fromRGB(225,220,240), TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left }, owner)
end
local title = text(window,"ARENA BOT • ЗАГРУЗКА",UDim2.fromOffset(14,0),UDim2.new(1,-66,0,44),16)
title.Font, title.Active = Enum.Font.GothamBold, true
local close = create("TextButton", { Text = "X", Position = UDim2.new(1,-42,0,8),
    Size = UDim2.fromOffset(30,28), BackgroundColor3 = Color3.fromRGB(100,65,160),
    TextColor3 = Color3.new(1,1,1), BorderSizePixel = 0 }, window)
create("UICorner", { CornerRadius = UDim.new(0,8) }, close)
local counter = text(window,"0 / 17",UDim2.fromOffset(14,47),UDim2.new(1,-28,0,35),27)
counter.Font = Enum.Font.GothamBold
local current = text(window,"Подготовка…",UDim2.fromOffset(14,84),UDim2.new(1,-28,0,34),13)
local track = create("Frame", { Position = UDim2.fromOffset(14,124), Size = UDim2.new(1,-28,0,8),
    BackgroundColor3 = Color3.fromRGB(55,46,72), BorderSizePixel = 0 }, window)
local bar = create("Frame", { Size = UDim2.fromScale(0,1), BorderSizePixel = 0,
    BackgroundColor3 = colors.running }, track)
local scroll = create("ScrollingFrame", { Position = UDim2.fromOffset(14,145),
    Size = UDim2.new(1,-28,1,-209), BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 4, CanvasSize = UDim2.fromOffset(0,0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y }, window)
create("UIListLayout", { Padding = UDim.new(0,9), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
local footer = text(window,"17 этапов • закрытие во время загрузки отменяет запуск",
    UDim2.new(0,14,1,-56),UDim2.new(1,-28,0,48),12)
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(report.Connections, connection)
    return connection
end
function report:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    for _, connection in ipairs(self.Connections) do connection:Disconnect() end
    self.Connections = {}
    gui:Destroy()
    if env[KEY] == self then env[KEY] = nil end
end
local function refresh()
    if report.Destroyed then return end
    counter.Text = string.format("%d / %d",report.Completed,TOTAL)
    bar.Size = UDim2.fromScale(report.Completed/TOTAL,1)
    bar.BackgroundColor3 = report.Errors > 0 and colors.error
        or (report.Warnings > 0 and colors.warning or colors.ok)
    footer.Text = string.format("Проверено: %d/%d • ошибок: %d • предупреждений: %d",
        report.Completed,TOTAL,report.Errors,report.Warnings)
end
local function addRow(label)
    if report.Destroyed then return end
    local record = { Label = label, Kind = "running" }
    table.insert(report.Records,record)
    record.Widget = text(scroll,"ЗАГРУЗКА • "..label,UDim2.fromOffset(0,0),UDim2.new(1,-12,0,0),12)
    record.Widget.AutomaticSize = Enum.AutomaticSize.Y
    record.Widget.TextYAlignment = Enum.TextYAlignment.Top
    record.Widget.LayoutOrder = #report.Records
    record.Widget.TextColor3 = colors.running
    return record
end
local function setRow(record, kind, detail)
    if report.Destroyed or not record then return end
    record.Kind, record.Detail = kind, detail
    record.Widget.Text = names[kind].." • "..record.Label
        ..(detail and detail ~= "" and ("\n"..tostring(detail)) or "")
    record.Widget.TextColor3 = colors[kind]
end
local dragInput, dragStart, dragOrigin
connect(title.InputBegan,function(input)
    if dragInput then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragInput,dragStart,dragOrigin = input,input.Position,window.Position
    end
end)
connect(inputService.InputChanged,function(input)
    if not dragInput then return end
    if dragInput.UserInputType == Enum.UserInputType.Touch then
        if input ~= dragInput then return end
    elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local delta = input.Position-dragStart
    window.Position = UDim2.new(dragOrigin.X.Scale,dragOrigin.X.Offset+delta.X,
        dragOrigin.Y.Scale,dragOrigin.Y.Offset+delta.Y)
end)
connect(inputService.InputEnded,function(input) if input == dragInput then dragInput = nil end end)
connect(inputService.WindowFocusReleased,function() dragInput = nil end)
connect(close.Activated,function() report:Destroy() end)
connect(gui.Destroying,function() report:Destroy() end)
local function step(label, callback)
    if report.Destroyed then return end
    current.Text = label
    local record = addRow(label)
    local ok,kind,detail = pcall(callback)
    if not ok then kind,detail = "error",kind end
    kind = kind or "ok"
    if kind == "error" then report.Errors = report.Errors+1 end
    if kind == "warning" then report.Warnings = report.Warnings+1 end
    report.Completed = report.Completed+1
    setRow(record,kind,detail)
    refresh()
end
local function awaitResult(callback)
    local done,success,result = false,false,nil
    local worker = task.spawn(function() success,result = pcall(callback); done = true end)
    local started = os.clock()
    while not done and not report.Destroyed and os.clock()-started < TIMEOUT do task.wait(0.05) end
    if not done then
        if type(task.cancel) == "function" then pcall(task.cancel,worker) end
        error(report.Destroyed and "Загрузка отменена" or ("Тайм-аут: "..TIMEOUT.." с"),0)
    end
    if not success then error(tostring(result),0) end
    return result
end
local cache,failures,loading = {},{},{}
local runtimeOK = false
local function loadModule(path)
    assert(runtimeOK,"Среда запуска не прошла проверку")
    assert(type(path) == "string" and not path:find("..",1,true),"Некорректный путь")
    if cache[path] ~= nil then return cache[path] end
    if failures[path] then error(failures[path],0) end
    assert(not loading[path],"Циклическая зависимость: "..path)
    loading[path] = true
    local phase = "скачивание"
    local ok,value = pcall(function()
        return awaitResult(function()
            local source = game:HttpGet(BASE..path)
            assert(type(source) == "string" and #source > 0,"Получен пустой ответ")
            phase = "компиляция"
            local chunk,err = loadstring(source,"@ArenaBot/"..path)
            assert(chunk,err)
            phase = "выполнение модуля"
            local exported = chunk()
            assert(type(exported) == "table","Модуль должен возвращать таблицу")
            return exported
        end)
    end)
    loading[path] = nil
    if not ok then
        failures[path] = path.." • "..phase..": "..tostring(value)
        error(failures[path],0)
    end
    cache[path] = value
    return value
end
local function moduleStep(path)
    step(path,function()
        if not runtimeOK then return "skipped","Недоступна среда исполнения" end
        local module = loadModule(path)
        if module.Ready == false then return "warning","Файл загружен, но реализация пока является заготовкой." end
        return "ok","Скачан, скомпилирован и возвращает таблицу."
    end)
end
-- Allow the initial 0/17 to render before work starts.
task.wait()
step("Проверка среды",function()
    assert(type(loadstring) == "function","loadstring недоступен")
    assert(type(task.spawn) == "function","task.spawn недоступен")
    runtimeOK = true
end)
moduleStep("manifest.lua")
local manifestOK = false
local systemNames = { "Perception","Decision","Navigation","Combat","Recovery","Memory" }
step("Проверка manifest.lua",function()
    local manifest = cache["manifest.lua"]
    if not manifest then return "skipped","Манифест не загружен" end
    assert(manifest.schemaVersion == 1,"Неподдерживаемая схема манифеста")
    assert(manifest.entry == "main.lua","Некорректная точка входа")
    assert(type(manifest.version) == "string","Отсутствует версия")
    assert(type(manifest.systems) == "table" and #manifest.systems == 6,"Ожидаются 6 систем и 17 этапов")
    for index,name in ipairs(systemNames) do
        local item = manifest.systems[index]
        assert(type(item) == "table" and item.name == name and item.path == name..".lua",
            "Некорректная запись системы: "..name)
    end
    manifestOK = true
end)
for _,path in ipairs({ "main.lua","config.lua","Cleanup.lua","Logger.lua","Gui.lua","SlapBattles.lua" }) do moduleStep(path) end
for _,name in ipairs(systemNames) do moduleStep(name..".lua") end
local contractsOK = false
step("Проверка интерфейсов модулей",function()
    if next(failures) or not runtimeOK then return "skipped","Сначала исправь ошибки загрузки файлов" end
    local problems = {}
    local function requireFunction(path,name)
        if not cache[path] or type(cache[path][name]) ~= "function" then
            table.insert(problems,path..": отсутствует функция "..name)
        end
    end
    requireFunction("main.lua","start")
    requireFunction("Cleanup.lua","new")
    requireFunction("Cleanup.lua","add")
    requireFunction("Cleanup.lua","Destroy")
    requireFunction("Logger.lua","new")
    requireFunction("Logger.lua","info")
    requireFunction("Gui.lua","mount")
    local config = cache["config.lua"]
    if not config or type(config.UI) ~= "table" or type(config.UI.Width) ~= "number"
        or config.UI.Width < 200 or type(config.UI.Height) ~= "number" or config.UI.Height < 200 then
        table.insert(problems,"config.lua: некорректные размеры UI")
    end
    for _,name in ipairs(systemNames) do
        local module = cache[name..".lua"]
        if not module or module.Name ~= name or type(module.Ready) ~= "boolean" then
            table.insert(problems,name..".lua: нужны Name и булево Ready")
        end
    end
    assert(#problems == 0,table.concat(problems,"\n"))
    contractsOK = true
end)
local app
step("Запуск приложения и GUI",function()
    if not manifestOK or not contractsOK or report.Errors > 0 then
        return "skipped","Приложение не запущено из-за ошибок предыдущих этапов"
    end
    local previous = env.SlapBattlesArenaBot
    local ok,value = pcall(function()
        return awaitResult(function()
            local result = cache["main.lua"].start(loadModule,cache["manifest.lua"],report)
            assert(type(result) == "table" and type(result.Destroy) == "function",
                "main.start должен вернуть приложение с методом Destroy")
            assert(not result.Destroyed,"Приложение уже остановлено")
            return result
        end)
    end)
    if not ok then
        local partial = env.SlapBattlesArenaBot
        if partial ~= previous and type(partial) == "table" and type(partial.Destroy) == "function" then
            pcall(function() partial:Destroy() end)
        end
        error(value,0)
    end
    if report.Destroyed then
        value:Destroy()
        return "skipped", "Загрузка отменена пользователем"
    end
    app = value
    return "ok","Окно приложения создано. Работоспособность боя проверяется отдельно."
end)
if report.Destroyed then return nil end
report.Finished = true
if report.Errors > 0 then current.Text = "Загрузка завершена с ошибками. Подробности ниже."
elseif report.Warnings > 0 then current.Text = "Каркас запущен. Есть не реализованные модули."
else current.Text = "Приложение запущено. Проверки пройдены." end
-- Diagnostic only: logs may omit or truncate errors; this cannot prove gameplay correctness.
if app then
    local seen,count = {},0
    local monitorOK = pcall(function()
        connect(game:GetService("LogService").MessageOut,function(message,kind)
            if report.Destroyed or kind ~= Enum.MessageType.MessageError then return end
            if not message:find("ArenaBot/",1,true) and not message:find("[ArenaBot]",1,true) then return end
            if seen[message] or count >= 50 then return end
            seen[message],count = true,count+1
            report.Errors,report.RuntimeErrors = report.Errors+1,report.RuntimeErrors+1
            setRow(addRow("Ошибка после запуска"),"error",message)
            current.Text = "Обнаружена ошибка приложения. Подробности ниже."
            refresh()
        end)
    end)
    if not monitorOK then
        report.Warnings = report.Warnings+1
        setRow(addRow("Наблюдение после запуска"),"warning","LogService недоступен в этой среде.")
    end
end
refresh()
return app,report
