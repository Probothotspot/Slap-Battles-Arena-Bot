local Gui = {}
local views = setmetatable({}, { __mode = "k" })
local function create(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties) do object[key] = value end
    object.Parent = parent
    return object
end
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local function round(object, radius)
    create("UICorner", { CornerRadius = UDim.new(0, radius or 12) }, object)
end
local function text(parent, name, value, x, y, width, height, size, color, bold)
    return create("TextLabel", { Name = name, Text = value, Position = UDim2.fromOffset(x,y),
        Size = UDim2.new(width, width == 1 and -2*x or 0, 0, height),
        BackgroundTransparency = 1, Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextSize = size, TextColor3 = color or rgb(239,230,255),
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
        TextWrapped = true }, parent)
end
local function button(parent, name, value, position, size)
    local object = create("TextButton", { Name = name, Text = value, Position = position, Size = size,
        BackgroundColor3 = rgb(65,41,103), BorderSizePixel = 0, AutoButtonColor = true,
        TextColor3 = rgb(250,245,255), Font = Enum.Font.GothamBold, TextSize = 15 }, parent)
    round(object,10)
    return object
end
local function gradient(object, colors, rotation)
    local keys = {}
    for i,color in ipairs(colors) do keys[i] = ColorSequenceKeypoint.new((i-1)/(#colors-1),color) end
    return create("UIGradient", { Color = ColorSequence.new(keys), Rotation = rotation or 0 }, object)
end
local function clockText(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return string.format("%02d:%02d:%02d", math.floor(seconds/3600), math.floor(seconds/60)%60, seconds%60)
end
local function number(value)
    if value == nil then return "—" end
    local s = string.format("%.0f", value)
    return s:reverse():gsub("(%d%d%d)","%1 "):reverse():gsub("^ ","")
end

function Gui.mount(context)
    local app, cleanup = context.App, context.Cleanup
    local input = game:GetService("UserInputService")
    local tweenService = game:GetService("TweenService")
    local width, height = context.Config.UI.Width, context.Config.UI.Height
    local gui = create("ScreenGui", { Name = "SlapBattlesArenaBotGUI", ResetOnSpawn = false,
        DisplayOrder = 100, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, nil)
    cleanup:add(gui)
    local root = create("Frame", { Name = "SafeArea", Size = UDim2.fromScale(1,1), BackgroundTransparency = 1 }, gui)
    local frame = create("Frame", { Name = "BotWindow", Size = UDim2.fromOffset(width,height),
        Position = UDim2.new(.5,-width/2,.5,-height/2), BackgroundColor3 = rgb(255,255,255),
        BorderSizePixel = 0, ClipsDescendants = true, Active = true }, root)
    round(frame,18)
    local borderGradient = gradient(frame,{rgb(154,93,255),rgb(230,166,255),rgb(106,61,209)},35)
    local inner = create("Frame", { Name = "Surface", Position = UDim2.fromOffset(2,2),
        Size = UDim2.new(1,-4,1,-4), BackgroundColor3 = rgb(255,255,255), BorderSizePixel = 0 }, frame)
    round(inner,16)
    local surfaceGradient = gradient(inner,{rgb(23,14,40),rgb(48,26,75),rgb(25,16,47)},20)
    local scale = create("UIScale", { Scale = 1 }, frame)
    local collapse = button(frame,"Collapse","−",UDim2.fromOffset(14,14),UDim2.fromOffset(32,32))
    local title = text(frame,"Title","ARENA BOT",56,9,0,24,18,nil,true)
    title.Size = UDim2.new(1,-110,0,24)
    title.Active = true
    local subtitle = text(frame,"Subtitle","PAUSED  /  v"..context.Manifest.version,56,32,0,17,10,rgb(186,160,218))
    subtitle.Size = UDim2.new(1,-110,0,17)
    local close = button(frame,"Close","×",UDim2.new(1,-46,0,14),UDim2.fromOffset(32,32))
    close.TextSize = 23
    local body = create("Frame", { Name = "Body", Position = UDim2.fromOffset(18,64),
        Size = UDim2.new(1,-36,1,-108), BackgroundTransparency = 1 }, frame)
    local credit=text(frame,"AuthorCredit","By: Probothotspot",18,0,1,18,10,rgb(255,255,255))
    credit.Position=UDim2.new(0,18,1,-29)
    credit.TextXAlignment=Enum.TextXAlignment.Center; credit.ZIndex=3
    local creditGradient=gradient(credit,{rgb(145,145,145),rgb(255,255,255),rgb(175,175,175),rgb(255,255,255)},0)
    local hero = create("Frame", { Name = "StatusCard", Size = UDim2.new(1,0,0,74),
        BackgroundColor3 = rgb(66,40,101), BackgroundTransparency = .15, BorderSizePixel = 0 }, body)
    round(hero,12)
    local status = text(hero,"Status","Готов к запуску",14,9,1,25,18,nil,true)
    local location = text(hero,"Location","Ожидание персонажа",14,39,1,23,12,rgb(207,184,233))
    local run = button(body,"RunToggle","Старт бота",UDim2.fromOffset(0,88),UDim2.new(1,0,0,44))
    run.BackgroundColor3 = rgb(255,255,255)
    local runGradient = gradient(run,{rgb(113,57,217),rgb(173,91,245),rgb(123,66,224)})
    run.Text=""
    local runLabel=text(run,"RunLabel","Старт бота",0,0,1,44,15,nil,true)
    runLabel.TextXAlignment=Enum.TextXAlignment.Center
    run.ZIndex=2; runLabel.ZIndex=3
    local showPath=button(body,"ShowPath","Показать путь: выкл",UDim2.fromOffset(0,138),UDim2.new(1,0,0,30))
    showPath.TextSize=12
    local tabBar = create("Frame", { Name = "Tabs", Position = UDim2.fromOffset(0,180),
        Size = UDim2.new(1,0,0,34), BackgroundTransparency = 1 }, body)
    local pages, tabs = {}, {}
    local labels = { "Обзор", "Статистика", "Журнал" }
    for i,name in ipairs({ "Overview", "Statistics", "Journal" }) do
        tabs[name] = button(tabBar,name.."Tab",labels[i],UDim2.new((i-1)/3,(i-1)*3,0,0),UDim2.new(1/3,-6,1,0))
        tabs[name].TextSize = 12
        pages[name] = create("ScrollingFrame", { Name = name, Position = UDim2.fromOffset(0,224),
            Size = UDim2.new(1,0,1,-224), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, ScrollBarImageColor3 = rgb(167,112,241),
            Active = true,
            CanvasSize = UDim2.fromOffset(0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y, Visible = name == "Overview" }, body)
    end
    local function detail(name,label,y,h)
        local card = create("Frame", { Name = name.."Card", Position = UDim2.fromOffset(0,y),
            Size = UDim2.new(1,-6,0,h), BackgroundColor3 = rgb(43,28,65), BorderSizePixel = 0 },pages.Overview)
        round(card,12)
        text(card,name.."Label",label,12,7,1,18,10,rgb(172,145,204),true)
        return text(card,name,"—",12,28,1,h-35,13)
    end
    local action = detail("Action","ТЕКУЩАЯ ЗАДАЧА",0,82)
    local glove = detail("Glove","ПЕРЧАТКА",92,65)
    local tactic = detail("Tactic","ТАКТИКА",167,100)
    local notice = text(pages.Overview,"Notice","",4,278,1,96,11,rgb(173,150,198))
    notice.TextYAlignment = Enum.TextYAlignment.Top
    local combatInfo=text(pages.Overview,"CombatInfo","",4,382,1,70,11,rgb(214,207,224))
    combatInfo.TextYAlignment=Enum.TextYAlignment.Top
    text(pages.Overview,"RangeLabel","Дистанция",4,462,0,20,11).Size=UDim2.fromOffset(190,20)
    text(pages.Overview,"IntervalLabel","Интервал, с",224,462,0,20,11).Size=UDim2.fromOffset(190,20)
    local function tuningBox(name,x,value)
        local box=create("TextBox",{Name=name,Text=value,Position=UDim2.fromOffset(x,484),Size=UDim2.fromOffset(190,30),
            BackgroundColor3=rgb(50,34,70),TextColor3=rgb(250,245,255),Font=Enum.Font.Gotham,
            TextSize=13,ClearTextOnFocus=false,BorderSizePixel=0},pages.Overview)
        round(box,8); return box
    end
    local rangeBox=tuningBox("AttackRange",4,tostring(context.Config.Attack.ConservativeRange))
    local intervalBox=tuningBox("AttackInterval",224,tostring(context.Config.Attack.Interval))
    local apply=button(pages.Overview,"ApplyCombat","Применить настройки боя",UDim2.fromOffset(4,524),UDim2.new(1,-10,0,30))
    apply.TextSize=12
    local tuningNote=text(pages.Overview,"TuningNote","Параметры выбранной перчатки. Проверяй их в игре.",4,560,1,36,10,rgb(178,161,196))
    local statValues = {}
    local statLabels = {
        {"SlapsEarned","ЗАРАБОТАНО СЛАППОВ"},{"Deaths","СМЕРТЕЙ"},
        {"ActiveSeconds","АКТИВНОЕ ВРЕМЯ"},{"SlapsPerHour","СЛАППОВ / ЧАС"},
        {"ArenaEntries","ВЫХОДОВ НА АРЕНУ"},{"PortalAttempts","ПОПЫТОК ВХОДА"},
        {"PortalFailures","НЕУДАЧНЫХ ВХОДОВ"},{"GloveChanges","СМЕН ПЕРЧАТКИ"},
        {"AttackAttempts","ПОПЫТОК УДАРА"},{"ConfirmedHits","ПОДТВЕРЖДЁННЫХ ПОПАДАНИЙ"},
        {"UnconfirmedAttacks","БЕЗ ПОДТВЕРЖДЕНИЯ"},{"ActivationErrors","ОШИБОК АКТИВАЦИИ"},
    }
    for i,entry in ipairs(statLabels) do
        local col,row = (i-1)%2,math.floor((i-1)/2)
        local card = create("Frame", { Name = entry[1].."Card", Position = UDim2.new(col*.5,col*4,0,row*88),
            Size = UDim2.new(.5,-8,0,78), BackgroundColor3 = rgb(48,29,73), BorderSizePixel = 0 },pages.Statistics)
        round(card,12)
        statValues[entry[1]] = text(card,entry[1],"0",12,9,1,31,entry[1]=="ActiveSeconds" and 20 or 26,rgb(231,201,255),true)
        text(card,entry[1].."Label",entry[2],12,44,1,25,9,rgb(188,157,217),true)
    end
    local statNote = text(pages.Statistics,"StatsNote","",4,528,1,110,11,rgb(183,157,209))
    statNote.TextYAlignment = Enum.TextYAlignment.Top
    create("UIListLayout", { Padding = UDim.new(0,8), SortOrder = Enum.SortOrder.LayoutOrder },pages.Journal)
    local view = { Frame=frame, Body=body, Scale=scale, Collapse=collapse, Run=runLabel, PathButton=showPath, Notice=notice,
        Subtitle=subtitle, Status=status, Location=location, Action=action, Glove=glove,
        Tactic=tactic, StatValues=statValues, StatNote=statNote, CombatInfo=combatInfo, Credit=credit, RangeBox=rangeBox, IntervalBox=intervalBox, TuningNote=tuningNote, Pages=pages, Tabs=tabs,
        Selected="Overview", Collapsed=false, LogRevision=-1, LastRunning=nil, Placed=false }
    views[gui] = view
    local animated = {}
    local function animate(object,seconds,goals)
        local tween = tweenService:Create(object,TweenInfo.new(seconds,Enum.EasingStyle.Linear,Enum.EasingDirection.InOut,-1),goals)
        table.insert(animated,tween); tween:Play()
    end
    animate(borderGradient,16,{Rotation=395})
    animate(surfaceGradient,28,{Rotation=380})
    animate(runGradient,12,{Rotation=360})
    animate(creditGradient,5,{Rotation=360})
    local function fit()
        local size = root.AbsoluteSize
        if size.X<=0 or size.Y<=0 then return end
        scale.Scale = math.min(1,(size.X-24)/width,(size.Y-24)/height)
        scale.Scale = math.max(.1,scale.Scale)
        local w,h=width*scale.Scale,(view.Collapsed and 60 or height)*scale.Scale
        local x,y=frame.Position.X.Offset,frame.Position.Y.Offset
        if not view.Placed then x,y=(size.X-w)/2,(size.Y-h)/2; view.Placed=true end
        frame.Position=UDim2.fromOffset(math.max(0,math.min(x,size.X-w)),math.max(0,math.min(y,size.Y-h)))
    end
    cleanup:add(root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit))
    cleanup:add(collapse.Activated:Connect(function()
        view.Collapsed=not view.Collapsed
        collapse.Text=view.Collapsed and "+" or "−"
        body.Visible=not view.Collapsed
        credit.Visible=not view.Collapsed
        if view.SizeTween then view.SizeTween:Cancel() end
        view.SizeTween=tweenService:Create(frame,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
            { Size=UDim2.fromOffset(width,view.Collapsed and 60 or height) })
        view.SizeTween:Play(); fit()
    end))
    cleanup:add(run.Activated:Connect(function()
        if app.Running then app:Stop() else app:Start() end
    end))
    cleanup:add(apply.Activated:Connect(function()
        local r=tonumber((rangeBox.Text:gsub(",","."))); local cd=tonumber((intervalBox.Text:gsub(",",".")))
        if not app:SetCombatTuning(r,cd) then tuningNote.Text="Дистанция: 1–40; интервал: 0.15–30 с." end
    end))
    cleanup:add(showPath.Activated:Connect(function() app:SetPathVisible(not app.PathVisible) end))
    cleanup:add(close.Activated:Connect(function() app:Destroy() end))
    for name,control in pairs(tabs) do
        local selected=name
        cleanup:add(control.Activated:Connect(function()
            view.Selected=selected
            for key,page in pairs(pages) do
                page.Visible=key==selected
                tabs[key].BackgroundColor3=key==selected and rgb(116,65,186) or rgb(52,33,78)
            end
        end))
    end
    tabs.Overview.BackgroundColor3=rgb(116,65,186)
    local activeInput,start,origin
    cleanup:add(title.InputBegan:Connect(function(event)
        if activeInput then return end
        if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then
            activeInput,start,origin=event,event.Position,frame.Position
        end
    end))
    cleanup:add(input.InputChanged:Connect(function(event)
        if not activeInput then return end
        if activeInput.UserInputType==Enum.UserInputType.Touch then
            if event~=activeInput then return end
        elseif event.UserInputType~=Enum.UserInputType.MouseMovement then return end
        local delta=event.Position-start
        frame.Position=UDim2.fromOffset(origin.X.Offset+delta.X,origin.Y.Offset+delta.Y); fit()
    end))
    cleanup:add(input.InputEnded:Connect(function(event) if event==activeInput then activeInput=nil end end))
    cleanup:add(input.WindowFocusReleased:Connect(function() activeInput=nil end))
    cleanup:add(gui.Destroying:Connect(function() app:Destroy() end))
    cleanup:add(function()
        for _,tween in ipairs(animated) do tween:Cancel() end
        if view.SizeTween then view.SizeTween:Cancel() end
        views[gui]=nil
    end)
    gui.Parent=game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    fit()
    Gui.update(gui,app)
    return gui
end

function Gui.update(gui,app)
    local v=views[gui]
    if not v then return end
    local s,stats=app.Snapshot or {},app.StatsView or {}
    local combat=app.CombatView or {}
    local zones={lobby="Лобби",arena="Арена",waiting="Загрузка персонажа"}
    v.Status.Text=app.Status=="error" and "Ошибка сессии" or (app.Running and "Бот работает" or "Бот на паузе")
    v.Subtitle.Text=(app.Running and "RUNNING" or "PAUSED").."  /  v"..app.Version.."  /  "..clockText(stats.SessionSeconds)
    v.Location.Text=(zones[s.ArenaState] or "Ожидание")..(s.HeightY and string.format("  ·  Y %.1f",s.HeightY) or "")
    v.Run.Text=app.Status=="error" and "Перезапусти загрузчик" or (app.Running and "Остановить бота" or "Старт бота")
    if v.LastRunning~=app.Running then
        v.LastRunning=app.Running
        v.Status.TextColor3=app.Running and rgb(210,174,255) or rgb(242,230,255)
    end
    v.Action.Text=app.LastError or (not app.Running and "Нажми «Старт бота», чтобы начать." or
        (s.ArenaState=="lobby" and app.NavigationStatus and app.NavigationStatus.Message) or
        (s.ArenaState=="arena" and app.ArenaStatus and app.ArenaStatus.Message) or
        (app.Plan and app.Plan.Reason) or "Ожидание персонажа")
    v.PathButton.Text="Показать путь: "..(app.PathVisible and "вкл" or "выкл")
    local nav=app.ArenaStatus or {}
    v.Notice.Text="Цель: "..(nav.Target or "—").." · Путь: "..(nav.RouteSource or "—").."\nПоисков: "..(nav.Plans or 0).." · Узлов: "..(nav.GraphNodes or 0).."\nАктиваций инструмента: "..(combat.AttackAttempts or app.AttackAttempts or 0).." · ожидают ответа: "..(combat.PendingAttacks or 0)
    local profile=combat.Profile
    v.CombatInfo.Text=(combat.Message or "Бой остановлен").."\n"..
        (profile and string.format("Дистанция %.1f · Интервал %.2f с · Таймер %.1f с",profile.Range,profile.Interval,combat.Cooldown or 0) or "Профиль появится после выбора перчатки").."\n"..
        (combat.HitFeedAvailable and "Подтверждения попаданий подключены" or "Попадания: источник подтверждений не подключён")
    if s.GloveName~=v.TuningGlove then
        v.TuningGlove=s.GloveName
        local configured=app.Config.Attack.GloveProfiles[s.GloveName or "Default"] or {}
        v.RangeBox.Text=tostring(configured.Range or app.Config.Attack.ConservativeRange)
        v.IntervalBox.Text=tostring(configured.Interval or app.Config.Attack.Interval)
    end
    v.Glove.Text=s.GloveName or (s.AmbiguousTools and "Выбери инструмент в руках" or "Перчатки пока нет")
    v.Tactic.Text=app.Glove and app.Glove.Hint or "Тактика появится после получения перчатки."
    for key,label in pairs(v.StatValues) do
        if key=="AttackAttempts" or key=="UnconfirmedAttacks" or key=="ActivationErrors" then label.Text=number(combat[key] or 0)
        elseif key=="ConfirmedHits" then label.Text=number(combat[key])
        elseif key=="ActiveSeconds" then label.Text=clockText(stats[key])
        elseif key=="SlapsEarned" then label.Text=stats.SlapsAvailable and "+"..number(stats[key] or 0) or "—"
        elseif key=="SlapsPerHour" then label.Text=stats.SlapsAvailable and number(stats[key] or 0) or "—"
        else label.Text=number(stats[key] or 0) end
    end
    v.StatNote.Text="Всего слаппов: "..number(stats.TotalSlaps).."\n"..
        (stats.SlapsAvailable and "Слаппы — прирост игрового счётчика во время работы бота." or "Игровой счётчик Slaps недоступен. Ожидаю данные.").."\n"..
        (combat.HitFeedAvailable and "Попадания учитываются по подключённому подтверждающему событию." or "Подтверждения попаданий не подключены; отсутствие ответа не означает промах.")
    if v.LogRevision~=(stats.Revision or 0) then
        v.LogRevision=stats.Revision or 0
        for _,child in ipairs(v.Pages.Journal:GetChildren()) do if child:IsA("TextLabel") then child:Destroy() end end
        local logs=stats.Logs or {}
        if #logs==0 then
            text(v.Pages.Journal,"EmptyLog","Здесь появятся действия после запуска бота.",8,0,1,48,12,rgb(192,167,218))
        else
            for i=#logs,1,-1 do
                local label=text(v.Pages.Journal,"Log",clockText(logs[i].Time).."   "..logs[i].Text,8,0,1,48,12,rgb(216,195,240))
                label.LayoutOrder=#logs-i+1
                label.TextYAlignment=Enum.TextYAlignment.Top
            end
        end
    end
end

return Gui
