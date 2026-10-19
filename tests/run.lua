-- Run from the repository root with Lua 5.3+ or: texlua tests/run.lua
local K = dofile("GloveKnowledge.lua")
local P = dofile("Perception.lua")
local D = dofile("Decision.lua")
local checks = 0
local function eq(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, (message or "Mismatch") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function clone(value)
    local result = {}
    for k, v in pairs(value) do result[k] = type(v) == "table" and clone(v) or v end
    return result
end
local context = {
    Alive = true, ArenaState = "arena", Equipped = true,
    SlapRange = 5, SlapReady = true,
    Target = { Alive = true, Distance = 4, LineOfSight = true },
}
local function plan(name, changes)
    local c = clone(context)
    for k, v in pairs(changes or {}) do c[k] = v end
    return K.plan(name, c)
end
local stats = K.stats()
assert(stats.Total > 330 and stats.Specialized > 20)
for _, entry in ipairs(K.list()) do
    eq(type(entry.Hint), "string", "Every glove has a policy")
    assert(K.Sources[entry.Source], "Missing catalog provenance")
    local c = clone(context)
    c.Mode = entry.Mode
    local result = K.plan(entry.Name, c)
    eq(type(result.Action), "string", entry.Name)
    eq(result.Execute, false, "Knowledge never executes actions")
end
eq(K.get("  God's   Hand ").Name, "God's Hand")
eq(K.get("God’s Hand").Name, "God's Hand")
eq(K.get("Pinata").Name, "Piñata")
eq(K.get("Moai").Name, "🗿")
eq(K.get("Missile Launcher", "royale").Known, true)
eq(K.get("Tank").Category, "badge")
eq(K.get("Tank", "royale").Category, "royale")
eq(K.get("Vampire").Known, false, "Royale data cannot leak into arena")
eq(K.get("Brand New Glove").Known, false)
eq(plan("Brand New Glove").Action, "slap", "Unknown glove uses base policy")
local copy = K.get("Flash")
copy.Policy = "broken"
eq(K.get("Flash").Policy, "flash", "Callers cannot corrupt the catalog")
eq(plan("Default", { Alive = false }).Action, "wait")
eq(plan("Default", { ArenaState = "lobby" }).Action, "wait")
eq(plan("Default", { ArenaState = "waiting" }).Action, "wait")
eq(plan("Default", { AmbiguousTools = true }).Action, "inspect")
eq(plan("Default", { Equipped = false }).Action, "equip")
eq(plan("Default", { NearEdge = true }).Action, "retreat")
eq(plan("Default", { Ragdolled = true }).Action, "wait")
eq(plan("Default", { SlapRange = false }).Action, "measure")
eq(plan("Default", { SlapRange = math.huge }).Action, "measure")
eq(plan("Default", { SlapReady = false }).Action, "space")
eq(plan("Spectator").Action, "observe")
eq(plan("Mace").Action, "controller")
eq(plan("Stilts").Action, "controller")
eq(plan("Slapstick").Action, "controller")
for _, flag in ipairs({ "Invulnerable", "CounterActive", "ReverseActive" }) do
    local target = clone(context.Target)
    target[flag] = true
    eq(plan("Default", { Target = target }).Action, "bait")
end
eq(plan("Killstreak", { Crowded = true }).Action, "retreat")
eq(plan("Flash", { AbilityBound = true, AbilityReady = true,
    AbilityRole = "reposition", WantsReposition = true }).Action, "slap", "No unsafe teleport")
eq(plan("Flash", { AbilityBound = true, AbilityReady = true,
    AbilityRole = "reposition", WantsReposition = true, LandingSafe = true }).Action, "ability")
eq(plan("Counter", { Threatened = true, AbilityReady = true, AbilityRole = "defend" }).Action,
    "slap", "No guessed ability binding")
eq(plan("Counter", { Threatened = true, AbilityReady = true,
    AbilityBound = true, AbilityRole = "defend" }).Action, "ability")
eq(plan("fish", { Falling = true }).Action, "recover")
eq(plan("fish", { Falling = true, Ragdolled = true, AbilityBound = true,
    AbilityReady = true, AbilityRole = "recover", RecoverySafe = true }).Action, "ability")
eq(plan("Slicer", { AbilityBound = true, AbilityReady = true, AbilityRole = "ranged",
    AbilityRange = 30, ProjectilePathClear = true }).Action, "ability")
eq(plan("Slicer", { AbilityBound = true, AbilityReady = false, AbilityRole = "ranged",
    AbilityRange = 30, ProjectilePathClear = true }).Action, "slap")
eq(plan("Extended", { Target = { Alive = true, Distance = 10, LineOfSight = true } }).Action, "approach")
eq(plan("Default", { Target = { Alive = true, Distance = 0/0, LineOfSight = true } }).Action, "inspect")
eq(plan("Default", { Target = { Alive = true, Distance = 4, LineOfSight = false } }).Action, "reposition")
eq(plan("Default", { Threatened = true,
    Target = { Alive = true, Distance = 4, LineOfSight = true, Glove = "Error" } }).Action, "dodge")

-- Minimal engine mocks: height boundaries, equip/reparent, respawn and death.
local function container(children)
    return { GetChildren = function() return children end }
end
local function tool(name)
    return { Name = name, IsA = function(_, class) return class == "Tool" end }
end
local packItems, characterItems = {}, {}
local backpack = container(packItems)
local humanoid = { Health = 100 }
local root = { Position = { Y = 350 }, IsA = function(_, class) return class == "BasePart" end }
local character = container(characterItems)
character.FindFirstChild = function(_, name) if name == "HumanoidRootPart" then return root end end
character.FindFirstChildOfClass = function(_, class) if class == "Humanoid" then return humanoid end end
local player = { Character = character }
player.FindFirstChildOfClass = function(_, class) if class == "Backpack" then return backpack end end
local tracker = P.new(dofile("config.lua").Arena)
eq(tracker:snapshot(player, 0).ArenaState, "lobby")
for _, case in ipairs({ { 300, "lobby" }, { 400, "lobby" }, { 299.99, "arena" },
    { 400.01, "arena" }, { -50, "arena" }, { 350, "lobby" } }) do
    root.Position.Y = case[1]
    eq(tracker:snapshot(player, 0).ArenaState, case[2], "Height boundary")
end
packItems[1] = tool("Flash")
eq(tracker:snapshot(player, 0).ArenaState, "lobby", "Tool cannot override lobby height")
packItems[1] = nil
root.Position.Y = 50
local emptyArena = tracker:snapshot(player, 0)
eq(emptyArena.ArenaState, "arena", "No glove does not imply lobby")
eq(D.plan(K, emptyArena, context).Action, "wait", "Wait for glove on arena")
eq(D.plan(K, emptyArena, { HasTool = true }).Action, "wait", "Cannot override observed empty inventory")
packItems[1] = tool("Flash")
local s = tracker:snapshot(player, 1.1)
eq(s.ArenaState, "arena")
eq(s.GloveName, "Flash")
eq(s.EquippedTool, false)
eq(D.plan(K, s, context).Action, "equip")
characterItems[1], packItems[1] = packItems[1], nil
s = tracker:snapshot(player, 1.2)
eq(s.GloveName, "Flash")
eq(s.EquippedTool, true)
eq(s.ArenaState, "arena")
characterItems[1] = nil
eq(tracker:snapshot(player, 2).ArenaState, "arena", "Tool loss does not change location")
packItems[1] = tool("New glove")
eq(tracker:snapshot(player, 2.2).GloveName, "New glove")
packItems[2] = tool("Default")
s = tracker:snapshot(player, 2.3)
eq(s.AmbiguousTools, true)
eq(D.plan(K, s, context).Action, "inspect")
characterItems[1], packItems[1] = packItems[1], nil
s = tracker:snapshot(player, 2.4)
eq(s.AmbiguousTools, false)
eq(s.GloveName, "New glove", "Equipped glove takes precedence")
humanoid.Health = 0
s = tracker:snapshot(player, 3)
eq(s.ArenaState, "waiting")
eq(D.plan(K, s, context).Action, "wait", "Cannot override observed death")
packItems, characterItems = {}, {}
backpack = container(packItems)
character = container(characterItems)
character.FindFirstChild = function() return root end
humanoid = { Health = 100 }
character.FindFirstChildOfClass = function() return humanoid end
player.Character = character
root.Position.Y = 350
eq(tracker:snapshot(player, 4).ArenaState, "lobby", "Respawn height determines location")
backpack = nil
eq(tracker:snapshot(player, 5).ArenaState, "lobby", "Missing inventory does not change location")
local savedRoot = root
root = nil
eq(tracker:snapshot(player, 6).ArenaState, "waiting", "Wait for root")
root = savedRoot
root.Position.Y = 0/0
eq(tracker:snapshot(player, 7).ArenaState, "waiting", "Invalid Y")
root.Position.Y = math.huge
eq(tracker:snapshot(player, 8).ArenaState, "waiting", "Infinite Y")
root.Position.Y = 50
eq(tracker:snapshot(player, 9).ArenaState, "arena", "Returns after root becomes valid")
eq(pcall(P.new, { LobbyMinY = 400, LobbyMaxY = 300 }), false, "Invalid bounds rejected")

local manifest = dofile("manifest.lua")
checks = checks + dofile("tests/navigation.lua")
checks = checks + dofile("tests/stats.lua")
checks = checks + dofile("tests/gui.lua")
for _, entry in ipairs(manifest.systems) do
    local module = dofile(entry.path)
    eq(module.Name, entry.name)
    eq(type(module.Ready), "boolean")
end
for _, path in ipairs({"main.lua", "Gui.lua", "loader.lua", "SlapBattles.lua",
    "config.lua", "Cleanup.lua", "Logger.lua"}) do
    assert(loadfile(path), "Invalid syntax: " .. path)
end
print(string.format("PASS: %d checks; %d entries, %d specialized, %d generic; arena=%d, royale=%d, subgame=%d",
    checks, stats.Total, stats.Specialized, stats.Generic,
    stats.ByMode.arena, stats.ByMode.royale, stats.ByMode.subgame))
