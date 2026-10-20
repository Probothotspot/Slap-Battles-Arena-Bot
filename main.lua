local Main = {}

function Main.start(loadModule, manifest, diagnostics)
    local config = loadModule("config.lua")
    local Cleanup = loadModule("Cleanup.lua")
    local Logger = loadModule("Logger.lua")
    local Gui = loadModule("Gui.lua")
    local Adapter = loadModule("SlapBattles.lua")
    local systems = {}
    for _, entry in ipairs(manifest.systems) do systems[entry.name] = loadModule(entry.path) end
    local env = type(getgenv) == "function" and getgenv() or _G
    local key = "SlapBattlesArenaBot"
    local previous = env[key]
    if type(previous) == "table" and type(previous.Destroy) == "function" then previous:Destroy() end

    local player = game:GetService("Players").LocalPlayer
    local adapter = Adapter.new({Player=player})
    local cleanup = Cleanup.new()
    local logger = Logger.new(config.Debug)
    local inventory = systems.Perception.new(config.Arena)
    local stats = systems.SessionStats.new()
    local navigation = systems.Navigation.new({ Player = player, Options = config.Portal, Arena = config.Arena })
    local pursuit = systems.ArenaNavigation.new({ Player=player, Options=config.Pursuit, Arena=config.Arena,
        SurfaceRoutes=systems.SurfaceRoutes, Knowledge=systems.GloveKnowledge })
    local preview = systems.PathPreview.new({Options=config.PathPreview})
    local combat = systems.Combat.new({Options=config.Attack,Adapter=adapter,Player=player,Arena=config.Arena,
        Knowledge=systems.GloveKnowledge,Log=function(message) stats:log(message) end})
    pursuit.Combat=combat
    local app = { Version = manifest.version, Config = config, Systems = systems,
        Adapter = adapter, Status = "paused", Destroyed = false, Running = false,
        Navigation = navigation, Pursuit=pursuit, Preview=preview, Combat=combat, PathVisible=false, AttackAttempts=0, Stats = stats, GloveKnowledge = systems.GloveKnowledge }
    app.CatalogStats = app.GloveKnowledge.stats()
    cleanup:add(function() navigation:Destroy(); pursuit:Destroy(); preview:Destroy(); combat:Destroy(); adapter:Destroy() end)

    local counter, counterConnection, lifeCharacter, lifeHumanoid, diedConnection, childConnection
    local function readSlaps()
        local folder = player:FindFirstChild("leaderstats")
        local found = folder and (folder:FindFirstChild("Slaps") or folder:FindFirstChild("slaps") or folder:FindFirstChild("SLAPS"))
        if found and not (found:IsA("IntValue") or found:IsA("NumberValue")) then found = nil end
        if counter ~= found then
            if counterConnection then counterConnection:Disconnect(); counterConnection = nil end
            counter = found
            if counter then
                local source = counter
                counterConnection = counter:GetPropertyChangedSignal("Value"):Connect(function()
                    if not app.Destroyed and counter == source then stats:slaps(source.Value, source) end
                end)
            end
        end
        stats:slaps(counter and counter.Value or nil, counter)
    end
    local function bindHumanoid(character)
        if character ~= player.Character or app.Destroyed then return end
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if lifeCharacter == character and lifeHumanoid == humanoid then return end
        if diedConnection then diedConnection:Disconnect(); diedConnection = nil end
        lifeCharacter, lifeHumanoid = character, humanoid
        stats:life(character, humanoid)
        if humanoid then
            diedConnection = humanoid.Died:Connect(function()
                if not app.Destroyed then stats:death(character) end
            end)
        end
    end
    local function bindCharacter(character)
        if childConnection then childConnection:Disconnect(); childConnection = nil end
        bindHumanoid(character)
        if character then
            childConnection = character.ChildAdded:Connect(function(child)
                if child:IsA("Humanoid") then bindHumanoid(character) end
            end)
        end
    end
    cleanup:add(player.CharacterAdded:Connect(bindCharacter))
    cleanup:add(function()
        if diedConnection then diedConnection:Disconnect() end
        if childConnection then childConnection:Disconnect() end
        if counterConnection then counterConnection:Disconnect() end
    end)
    bindCharacter(player.Character)

    local function sample()
        bindHumanoid(player.Character)
        app.Snapshot = inventory:snapshot(player)
        app.Plan = systems.Decision.plan(app.GloveKnowledge, app.Snapshot)
        app.Glove = app.Snapshot.GloveName and app.GloveKnowledge.get(app.Snapshot.GloveName)
        readSlaps()
        stats:observe(app.Snapshot, navigation:getStatus())
        app.StatsView = stats:snapshot()
    end
    local lastTarget,lastRoute,lastFailures
    local function refresh()
        sample()
        combat.CurrentProfile=app.Snapshot.Tool and combat:profile(app.Snapshot.Tool) or nil
        if app.Running then
            navigation:update(app.Snapshot)
            pursuit:update(app.Snapshot)
            local target=pursuit.Target
            local targetCharacter=target and target.Character
            local targetRoot=targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
            local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot and root and pursuit.Running and app.Snapshot.ArenaState=="arena" then
                local tool=targetCharacter:FindFirstChildOfClass("Tool")
                local profile=combat:profile(app.Snapshot.Tool)
                local observations={SlapRange=profile.Range,SlapReady=combat:ready() and app.Snapshot.Tool.Enabled~=false,
                    Target={Alive=true,Distance=(root.Position-targetRoot.Position).Magnitude,
                        LineOfSight=not game:GetService("Workspace"):Raycast(root.Position,targetRoot.Position-root.Position,pursuit.Params),
                        Glove=tool and tool.Name,
                        Invulnerable=targetCharacter:FindFirstChildOfClass("ForceField")~=nil},
                    Ragdolled=pursuit.Humanoid.PlatformStand}
                app.Plan=systems.Decision.plan(app.GloveKnowledge,app.Snapshot,observations)
                combat:update(app.Snapshot,app.Plan,player.Character,pursuit,observations)
            else combat:stop() end
            app.AttackAttempts=combat.Attempts
            stats:observe(app.Snapshot, navigation:getStatus())
        end
        app.CombatView=combat:snapshot()
        app.ArenaStatus=pursuit:getStatus()
        if app.Running and app.Snapshot.ArenaState=="arena" then
            local n=app.ArenaStatus
            if n.Target and n.Target~="—" and n.Target~=lastTarget then stats:log("Цель: "..n.Target) end
            if n.RouteSource and n.RouteSource~="—" and n.RouteSource~=lastRoute then stats:log("Маршрут: "..n.RouteSource) end
            if n.Failures and n.Failures>(lastFailures or 0) then stats:log(n.Message) end
            lastTarget,lastRoute,lastFailures=n.Target,n.RouteSource,n.Failures
        end
        app.NavigationStatus, app.StatsView = navigation:getStatus(), stats:snapshot()
        if app.Gui then Gui.update(app.Gui, app) end
    end
    local function fail(err)
        navigation:stop("Ошибка: движение остановлено"); pursuit:stop(); combat:stop(); preview:update({})
        stats:setRunning(false)
        app.Running, app.Status, app.LastError = false, "error", tostring(err)
        app.StatsView = stats:snapshot()
        if app.Gui then pcall(Gui.update, app.Gui, app) end
        warn("[ArenaBot] Session failed: " .. tostring(err))
    end
    function app:Start()
        if self.Destroyed or self.Running or self.Status == "error" then return false end
        local ok, err = pcall(function()
            sample() -- Exclude gains accrued while paused from the active-run baseline.
            stats:setRunning(true)
            self.Running, self.Status = true, "running"
            refresh()
        end)
        if not ok then fail(err) end
        return ok
    end
    function app:Stop()
        if self.Destroyed then return end
        if self.Running then pcall(sample) end
        navigation:stop("Бот остановлен"); pursuit:stop(); combat:stop(); preview:update({})
        stats:setRunning(false)
        self.Running = false
        if self.Status ~= "error" then self.Status = "paused" end
        self.CombatView=combat:snapshot()
        self.ArenaStatus=pursuit:getStatus()
        self.NavigationStatus, self.StatsView = navigation:getStatus(), stats:snapshot()
        if self.Gui then pcall(Gui.update, self.Gui, self) end
    end
    function app:SetCombatTuning(range,interval)
        if self.Destroyed then return false end
        if type(range)~="number" or range~=range or range<1 or range>40
            or type(interval)~="number" or interval~=interval or interval<.15 or interval>30 then return false end
        local tool=self.Snapshot and self.Snapshot.Tool
        local name=tool and tool.Name or "Default"
        local profile=config.Attack.GloveProfiles[name] or {}
        profile.Range,profile.Interval,profile.Verified=range,interval,false
        config.Attack.GloveProfiles[name]=profile
        stats:log("Настройки боя: "..name..", дистанция "..range..", интервал "..interval.." с")
        refresh(); return true
    end
    function app:BindHitConfirmation(signal,decode)
        if self.Destroyed then return false end
        adapter:bindHitFeed(signal,decode,function(payload) combat:confirm(payload) end)
        self.CombatView=combat:snapshot()
        stats:log("Подключён адаптер подтверждений попаданий")
        if self.Gui then Gui.update(self.Gui,self) end
        return true
    end
    function app:SetPathVisible(value)
        if self.Destroyed then return end
        self.PathVisible=value==true; preview:setEnabled(self.PathVisible)
        if self.Gui then Gui.update(self.Gui,self) end
    end
    function app:Destroy()
        if self.Destroyed then return end
        self:Stop()
        self.Destroyed, self.Status = true, "stopped"
        cleanup:Destroy()
        if env[key] == self then env[key] = nil end
    end
    function app:GetCombatPlan(observations)
        if self.Destroyed or not self.Running then
            return { Action = "wait", Reason = "Бот остановлен", Execute = false }
        end
        self.Snapshot = inventory:snapshot(player)
        return systems.Decision.plan(self.GloveKnowledge, self.Snapshot, observations)
    end

    env[key] = app
    local ok, err = pcall(function()
        sample()
        app.Gui = Gui.mount({ App = app, Config = config, Cleanup = cleanup, Manifest = manifest })
        if diagnostics then
            app.Diagnostics = diagnostics
            cleanup:add(function() diagnostics:Destroy() end)
        end
        refresh()
        local elapsed,previewElapsed = 0,0
        cleanup:add(game:GetService("RunService").Heartbeat:Connect(function(dt)
            if app.Destroyed or app.Status == "error" then return end
            if app.Running then
                local good,problem=pcall(function()
                    combat:step(dt)
                    pursuit:step()
                    previewElapsed=previewElapsed+dt
                    if app.PathVisible and previewElapsed>=config.PathPreview.Interval then
                        previewElapsed=0
                        local nav=app.Snapshot.ArenaState=="lobby" and navigation or pursuit
                        preview:update(nav:getRoute())
                    end
                end)
                if not good then fail(problem); return end
            end
            elapsed = elapsed + dt
            if elapsed < config.PerceptionInterval then return end
            elapsed = 0
            local good, problem = pcall(refresh)
            if not good then fail(problem) end
        end))
        if config.AutoStart then app:Start() end
    end)
    if not ok then app:Destroy(); error("[ArenaBot] Session initialization failed: " .. tostring(err)) end
    if not diagnostics or not diagnostics.Silent then logger:info("Session " .. manifest.version .. " loaded. Press Start.") end
    return app
end

return Main
