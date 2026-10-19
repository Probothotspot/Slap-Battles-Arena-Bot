local Main = {}

function Main.start(loadModule, manifest, diagnostics)
    local config = loadModule("config.lua")
    local Cleanup = loadModule("Cleanup.lua")
    local Logger = loadModule("Logger.lua")
    local Gui = loadModule("Gui.lua")
    local adapter = loadModule("SlapBattles.lua")
    local systems = {}
    -- Load and validate everything before replacing a previous session.
    for _, entry in ipairs(manifest.systems) do
        systems[entry.name] = loadModule(entry.path)
    end

    local env = type(getgenv) == "function" and getgenv() or _G
    local key = "SlapBattlesArenaBot"
    local previous = env[key]
    if type(previous) == "table" and type(previous.Destroy) == "function" then
        previous:Destroy()
    end

    local app = {
        Version = manifest.version,
        Config = config,
        Systems = systems,
        Adapter = adapter,
        Status = "scaffold",
        Destroyed = false,
    }
    local cleanup = Cleanup.new()
    local logger = Logger.new(config.Debug)

    function app:Destroy()
        if self.Destroyed then return end
        self.Destroyed = true
        self.Status = "stopped"
        cleanup:Destroy()
        if env[key] == self then env[key] = nil end
    end

    env[key] = app
    local ok, err = pcall(function()
        app.Gui = Gui.mount({
            App = app,
            Config = config,
            Cleanup = cleanup,
            Manifest = manifest,
        })
    end)
    if not ok then
        app:Destroy()
        error("Arena Bot GUI failed: " .. tostring(err))
    end
    -- Failed startup keeps the diagnostics visible; successful sessions own their report.
    if diagnostics then
        app.Diagnostics = diagnostics
        cleanup:add(function() diagnostics:Destroy() end)
    end
    local inventory = systems.Perception.new(config.Arena)
    app.GloveKnowledge = systems.GloveKnowledge
    app.CatalogStats = app.GloveKnowledge.stats()
    app.Status = "observing"

    function app:GetCombatPlan(observations)
        if self.Destroyed then
            return { Action = "wait", Reason = "Сессия завершена", Execute = false }
        end
        -- Always refresh to avoid decisions based on a stale death/glove snapshot.
        local player = game:GetService("Players").LocalPlayer
        self.Snapshot = inventory:snapshot(player)
        return systems.Decision.plan(self.GloveKnowledge, self.Snapshot, observations)
    end

    local function refresh()
        app.Plan = app:GetCombatPlan()
        app.Glove = app.Snapshot.GloveName and app.GloveKnowledge.get(app.Snapshot.GloveName)
        Gui.update(app.Gui, app)
    end
    local started, startError = pcall(function()
        refresh()
        local elapsed = 0
        local heartbeat
        heartbeat = game:GetService("RunService").Heartbeat:Connect(function(dt)
            elapsed = elapsed + dt
            if app.Destroyed or elapsed < config.PerceptionInterval then return end
            elapsed = 0
            local refreshed, refreshError = pcall(refresh)
            if not refreshed then
                heartbeat:Disconnect()
                app.Status, app.LastError = "error", tostring(refreshError)
                warn("[ArenaBot] Inventory observation failed: " .. app.LastError)
            end
        end)
        cleanup:add(heartbeat)
    end)
    if not started then
        app:Destroy()
        error("[ArenaBot] Glove initialization failed: " .. tostring(startError))
    end
    if not diagnostics or not diagnostics.Silent then
        logger:info("Glove knowledge " .. manifest.version .. " loaded. Action execution is not implemented.")
    end
    return app
end

return Main

