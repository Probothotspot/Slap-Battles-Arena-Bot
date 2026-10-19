-- Data and pure decision policies. Loading this file never moves or attacks.
-- Catalog presence is not proof of ownership, ability readiness, or live balance.
local Knowledge = {
    Name = "GloveKnowledge", Ready = true, SchemaVersion = 1,
    ReviewedAt = "2026-10-19", CatalogComplete = false,
    LiveTested = false,
    Sources = {
        catalog = "https://roblox-slap-battles.fandom.com/wiki/Gloves",
        regular = "https://roblox-slap-battles.fandom.com/wiki/Reverse",
        badge = "https://roblox-slap-battles.fandom.com/wiki/Grab",
        snapshot = "https://robloxden.com/game-codes/slap-battles/guides/slap-battles-all-gloves",
        staff = "https://roblox-slap-battles.fandom.com/wiki/Staff_Members",
        royale = "https://roblox-slap-battles.fandom.com/wiki/Slap_Royale",
        oneshot = "https://roblox-slap-battles.fandom.com/wiki/Category:One-Shot_Gloves",
        counter = "https://roblox-slap-battles.fandom.com/wiki/Category:Countering_Ability",
        projectile = "https://roblox-slap-battles.fandom.com/wiki/Category:Projectile_Ability",
        recovery = "https://roblox-slap-battles.fandom.com/wiki/Category:Recovery_Ability",
        extended = "https://roblox-slap-battles.fandom.com/wiki/Extended",
        rock = "https://roblox-slap-battles.fandom.com/wiki/Diamond",
        custom = "https://roblox-slap-battles.fandom.com/wiki/CUSTOM",
        flash = "https://roblox-slap-battles.fandom.com/wiki/Flash",
        streak = "https://roblox-slap-battles.fandom.com/wiki/Killstreak",
        spectator = "https://roblox-slap-battles.fandom.com/wiki/Spectator",
        stilts = "https://roblox-slap-battles.fandom.com/wiki/Stilts",
        slapstick = "https://roblox-slap-battles.fandom.com/wiki/Slapstick",
        ink = "https://roblox-slap-battles.fandom.com/wiki/Ink",
    },
}

-- Shared tactics are authored heuristics, not measured glove statistics.
-- No invented cooldowns, reach values, RemoteEvent names or key bindings.
local policies = {
    basic = { Hint = "Сближаться по безопасному пути, бить в измеренной дистанции, выходить из размена." },
    reach = { Hint = "Держать противника на внешней границе измеренной дальности удара; не заходить вплотную." },
    oneshot = { Hint = "Искать одиночную цель и первый удар; не размениваться с другими опасными перчатками." },
    counter = { Ability = "defend", Hint = "Беречь контратаку до подтверждённой угрозы; не тратить её без атаки противника." },
    rock = { Ability = "defend", Hint = "При угрозе защищаться; выходить из камня только после проверки окружения." },
    projectile = { Ability = "ranged", Hint = "Сохранять дистанцию, выбирать видимую цель и проверять траекторию перед выстрелом." },
    recovery = { Ability = "recover", Hint = "Беречь восстановление для опасности падения; проверять точку возвращения." },
    flash = { Ability = "reposition", Hint = "Телепортироваться только при проверенном месте приземления; избегать прыжка в пустоту." },
    streak = { Hint = "Сохранять серию: выбирать одиночные цели, отходить от толпы и края; фазу читать отдельно." },
    no_slap = { CanSlap = false, Hint = "Обычный удар недоступен; нужен отдельный контроллер механики этой перчатки." },
    spectator = { CanSlap = false, Hint = "Режим наблюдателя: не выбирать боевые действия." },
    charged_reach = { CanSlap = false, Hint = "Измерять дистанцию, заряжать и отпускать удлинение; нужен отдельный контроллер." },
}
local catalog, aliases = {}, {}
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

function Knowledge.normalize(name)
    if type(name) ~= "string" then return "" end
    return (name:gsub("’", "'"):gsub("%s+", " "):match("^%s*(.-)%s*$")):lower()
end

local function key(name, mode)
    return (mode or "arena") .. ":" .. Knowledge.normalize(name)
end

local function seed(names, category, mode, source)
    for name in names:gmatch("[^|\n]+") do
        name = name:match("^%s*(.-)%s*$")
        local id = key(name, mode)
        assert(not catalog[id], "Duplicate glove: " .. id)
        catalog[id] = {
            Name = name, Mode = mode or "arena", Category = category,
            Policy = "basic", Known = true, Strategy = "generic",
            Source = source, LiveTested = false,
        }
    end
end

-- Names only. The maintained wiki navigation and June 2026 index are snapshots;
-- neither proves that this is the complete roster of the current server.
seed([[
spin|Stick|Default but Bad|Default|Diamond|ZZZZZZZ|Extended|Dual|Brick|Snow|Pull|Flash|Stilts|Spring|Pinwheel|Swapper|Screwdriver|Bull|Dice|Ghost|Thanos|Stun|L.O.L.B.O.M.B|Za Hando|Fort|Magnet|Pusher|Anchor|Space|Boomerang|Speedrun|Mail|T H I C K|Golden|Squid|MR|Hive|Reaper|Baby|Replica|Mace|Defense|Offense|Killstreak|Pineslapple|Reverse|Shukuchi|Duelist|woah|Ice|Gummy|Adios|Blocked|Divert|Engineer|Rocky|Coil|Conveyor|Balloony|Phantom|Leafblower|el gato|Wormhole|Shackle|Flick|STOP|Equalizer|Track|Stalker|Prop|Cherry|Shield|Clover|5 More|Booster|Chainsaw|Ping Pong|Thumbtack|Trifecta|Baller|Architect|Home Run|Friction|Whirlwind|Disc|BONK|Grenadier|Excavator|Retribution|Nightmare|Pylon|Thor|Slime|Pocket|Grapple|Command|Cloud|Stalagmite|Gravity|Helix|Parry|Glue|Jebaited|Meteor|Oven|Guardian Angel|Sun|Ferryman|Blackhole|Walrus|Blink|Tableflip|Slapstick|Beatdown|Jockey|Chicken|Slicer|Sbeve|Golem|Doomsday|Grab|UFO|Demolition|Beachball|Shotgun|Error|64|Roguelike|Barrel|Lawnmower|Virus|Smiler|Butcher|Infinity|Aggro|Medusa|Seal|Soul|R/C|Mushroom|Scuba|Pyromania|Automaton|Roaring|God's Hand|The Flex
]], "slaps", "arena", "regular")
seed([[
MEGAROCK|Plague|Hallow Jack|[REDACTED]|bus|Mitten|Phase|Warp|Bomb|Bubble|Jet|Shard|potato|CULT|bob|buddies|Moon|Jupiter|Spy|Detonator|Rage|Trap|Orbit|Hybrid|Slapple|Disarm|Dominance|Link|Chain|Rattlebones|Charge|Tycoon|Confusion|Glitch|Snowball|Elude|RNG|fish|🗿|Obby|Voodoo|Goofy|Leash|Flamarang|Kinetic|Berserk|Sparky|Boogie|Recall|Quake|Psycho|Kraken|Counter|Hammer|rob|Rhythm|Rojo|Hitman|Retro|Null|Lure|Tinkerer|Necromancer|Alchemist|Druid|Jester|Scythe|Santa|Iceskate|Blasphemy|Pan|Admin|Joust|Firework|Run|Glovel|Divebomb|Lamp|Knockoff|Frostbite|Plank|Spoonful|the schlob|Siphon|Wrench|Hunter|Relude|Avatar|Water|Fan|Boxer|MATERIALIZE|Bind|Poltergeist|Clock|Untitled Tag Glove|Pillow|Angler|Jerry|Snowroller|Draw4|Mouse|Hexa|Metaverse|Swordfighter|Tank|Eggler|Slender|Swashbuckler|Silly|Slasher|Car Keys|Suction|Reflect|Dave|mortis|Bounty|Debug|Paint|Plate|Lag|Harvester|Riftshot|Conker|Wheelchair|Elf|Shopkeeper|Collector|Glaxe|Piñata|Penguin|Undead|Groundbreaker|Shellbert|Lasso|Lotus|Elastic|G-X|Doorkeeper|Camera
]], "badge", "arena", "badge")
seed("OVERKILL|Spectator|CUSTOM|Ultra Instinct|Titan|Killerfish", "paid", "arena", "snapshot")
seed("Acrobat", "special", "arena", "snapshot")
seed([[
barzil|edgelord|sus|Clone()|minecraft|Train|BOBBLE|TABLE|gum|Nimbus|manspider|Frost God|KING SBEVE|IMAGINARY GLOVE|Extendeded|TERRY|boogiewoogie|Slayer|So Retro|OneMillionBricks|Minos|Dummy|WALL|Sisyphus|Mihawk|BTools|Chicxulub|Fire slasher|Larry (glove)|Kenneth|Default but good|Super stilts
]], "staff", "arena", "staff")
seed([[
Pack-A-Punch|Vigorous|Aerialist|Tank|Pow|Faculty|Revenge|Juggernaut|Void|Aquarius|Mimic|Thundercaller|Missile-Launcher|Glacier|KABOOM|Witch|Vampire|Cannoneer
]], "royale", "royale", "royale")
seed("Zombie|Lantern|Ink|Flashlight|Evolg", "subgame", "subgame", "snapshot")

local function assign(names, policy, source)
    for name in names:gmatch("[^|]+") do
        local entry = assert(catalog[key(name)], "Unlisted glove: " .. name)
        entry.Policy, entry.Strategy, entry.MechanicSource = policy, "heuristic", source
    end
end
assign("Extended", "reach", "extended")
assign("OVERKILL|Error|The Flex|sus", "oneshot", "oneshot")
assign("Reverse|Counter|Parry|Jebaited", "counter", "counter")
assign("Diamond|MEGAROCK", "rock", "rock")
assign("CUSTOM", "rock", "custom")
assign("Shard|Slicer|Tableflip", "projectile", "projectile")
assign("fish|Recall", "recovery", "recovery")
assign("Flash", "flash", "flash")
assign("Killstreak", "streak", "streak")
assign("Spectator", "spectator", "spectator")
assign("Stilts|Mace", "no_slap", "stilts")
assign("Slapstick", "charged_reach", "slapstick")
catalog[key("Ink", "subgame")].Policy = "no_slap"
catalog[key("Flashlight", "subgame")].Policy = "no_slap"

local function alias(name, canonical, mode)
    local id = key(canonical, mode)
    assert(catalog[id], "Alias target missing")
    aliases[key(name, mode)] = id
end
alias("THICK", "T H I C K")
alias("Moai", "🗿")
alias("Pinata", "Piñata")
alias("Redacted", "[REDACTED]")
alias("Missile Launcher", "Missile-Launcher", "royale")

function Knowledge.get(name, mode)
    local id = key(name, mode)
    local entry = catalog[aliases[id] or id]
    local result = entry and copy(entry) or {
        Name = type(name) == "string" and name or "Unknown",
        Mode = mode or "arena", Category = "unknown", Policy = "basic",
        Known = false, Strategy = "generic", LiveTested = false,
    }
    local policy = policies[result.Policy]
    result.Hint, result.AbilityRole = policy.Hint, policy.Ability
    result.CanSlap = policy.CanSlap ~= false
    return result
end

function Knowledge.list(mode)
    local result = {}
    for _, entry in pairs(catalog) do
        if not mode or entry.Mode == mode then
            table.insert(result, Knowledge.get(entry.Name, entry.Mode))
        end
    end
    table.sort(result, function(a, b)
        return a.Mode .. ":" .. a.Name < b.Mode .. ":" .. b.Name
    end)
    return result
end

function Knowledge.stats()
    local result = { Total = 0, Specialized = 0, Generic = 0, ByMode = {} }
    for _, entry in pairs(catalog) do
        result.Total = result.Total + 1
        result.ByMode[entry.Mode] = (result.ByMode[entry.Mode] or 0) + 1
        if entry.Policy == "basic" then result.Generic = result.Generic + 1
        else result.Specialized = result.Specialized + 1 end
    end
    return result
end

-- Context is supplied by perception/controllers. Unknown facts stay nil.
-- AbilityBound/AbilityReady and measured ranges must be supplied by an adapter;
-- a request is NOT execution and never assumes the ability succeeded.
function Knowledge.plan(name, context)
    local c = context or {}
    local glove = Knowledge.get(name, c.Mode)
    local function result(action, reason, extra)
        local value = { Action = action, Reason = reason, Glove = glove.Name,
            Policy = glove.Policy, Hint = glove.Hint, Known = glove.Known,
            Strategy = glove.Strategy, Execute = false }
        for k, v in pairs(extra or {}) do value[k] = v end
        return value
    end
    local function ability(role)
        return c.AbilityBound == true and c.AbilityReady == true
            and c.AbilityRole == role
    end
    if c.Alive ~= true then return result("wait", "Персонаж не готов или погиб") end
    if c.ArenaState ~= "arena" then return result("wait", "Ожидание входа на арену") end
    if c.HasTool == false then return result("wait", "Арена: ожидание перчатки") end
    if c.AmbiguousTools then return result("inspect", "Несколько инструментов: требуется выбор активного") end
    if glove.Policy == "spectator" then return result("observe", glove.Hint) end
    if c.Equipped == false then return result("equip", "Экипировать выбранный инструмент перед боем") end
    if c.Falling == true then
        if glove.AbilityRole == "recover" and ability("recover") and c.RecoverySafe == true then
            return result("ability", "Восстановление после падения", { AbilityRole = "recover" })
        end
        return result("recover", "Нужно восстановление; подходящий контроллер не подтверждён")
    end
    if c.Ragdolled == true then return result("wait", "Ожидание выхода из ragdoll") end
    if c.NearEdge == true then return result("retreat", "Приоритет — отойти от края", { NeedsGroundCheck = true }) end
    if c.Threatened == true and glove.AbilityRole == "defend" and ability("defend") then
        return result("ability", "Подтверждённая угроза: защитная способность", { AbilityRole = "defend" })
    end
    local target = c.Target
    if type(target) ~= "table" or target.Alive ~= true then
        return result("search", "Нет подтверждённой живой цели")
    end
    if target.Invulnerable == true or target.CounterActive == true or target.ReverseActive == true then
        return result("bait", "Не бить в активную защиту противника")
    end
    local enemy = Knowledge.get(target.Glove, c.Mode)
    if enemy.Policy == "spectator" then return result("search", "Наблюдатель не является боевой целью") end
    if enemy.Policy == "oneshot" and c.Threatened == true then
        return result("dodge", "Избегать размена с перчаткой мгновенного убийства", { NeedsGroundCheck = true })
    end
    if c.Crowded == true and glove.Policy == "streak" then
        return result("retreat", "Сохранить серию: не входить в толпу", { NeedsGroundCheck = true })
    end
    if target.LineOfSight ~= true then return result("reposition", "Нет проверенной видимости цели", { NeedsGroundCheck = true }) end
    local distance = target.Distance
    if type(distance) ~= "number" or distance ~= distance or distance < 0 or distance == math.huge then
        return result("inspect", "Не измерена дистанция до цели")
    end
    if not glove.CanSlap then return result("controller", glove.Hint) end
    if glove.AbilityRole == "ranged" and ability("ranged") and c.ProjectilePathClear == true
        and type(c.AbilityRange) == "number" and distance <= c.AbilityRange then
        return result("ability", "Видимая цель в подтверждённой дальности", { AbilityRole = "ranged" })
    end
    if glove.AbilityRole == "reposition" and ability("reposition")
        and c.LandingSafe == true and c.WantsReposition == true then
        return result("ability", "Место телепортации проверено", { AbilityRole = "reposition" })
    end
    if type(c.SlapRange) ~= "number" or c.SlapRange <= 0 or c.SlapRange ~= c.SlapRange
        or c.SlapRange == math.huge then
        return result("measure", "Нужна проверенная дальность удара этой перчатки")
    end
    if distance <= c.SlapRange then
        if c.SlapReady == true then return result("slap", "Цель в дальности, удар готов") end
        return result("space", "Сохранять дистанцию до готовности удара", { NeedsGroundCheck = true })
    end
    return result("approach", glove.Policy == "reach" and "Подойти только к границе дальности" or "Подойти по проверенному пути",
        { DesiredDistance = c.SlapRange * 0.9, NeedsGroundCheck = true })
end

return Knowledge
