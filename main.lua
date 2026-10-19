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
        Gui.mount({
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
    logger:info("Scaffold " .. manifest.version .. " loaded. Combat is not implemented.")
    return app
end

return Main
