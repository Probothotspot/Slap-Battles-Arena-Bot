-- Bootstrap for a client environment exposing loadstring and game:HttpGet.
local BASE = "https://raw.githubusercontent.com/Probothotspot/Slap-Battles-Arena-Bot/main/"
assert(type(loadstring) == "function", "Arena Bot: loadstring is unavailable")

local cache = {}
local loading = {}
local function loadModule(path)
    assert(type(path) == "string" and not path:find("..", 1, true), "Invalid module path")
    if cache[path] ~= nil then return cache[path] end
    assert(not loading[path], "Circular dependency: " .. path)
    loading[path] = true
    local ok, result = pcall(function()
        local source = game:HttpGet(BASE .. path)
        local chunk, err = loadstring(source, "@ArenaBot/" .. path)
        assert(chunk, err)
        local value = chunk()
        assert(type(value) == "table", path .. " must return a table")
        return value
    end)
    loading[path] = nil
    assert(ok, "Arena Bot could not load " .. path .. ": " .. tostring(result))
    cache[path] = result
    return result
end

local manifest = loadModule("manifest.lua")
assert(manifest.schemaVersion == 1, "Unsupported manifest schema")
local main = loadModule(manifest.entry)
return main.start(loadModule, manifest)
