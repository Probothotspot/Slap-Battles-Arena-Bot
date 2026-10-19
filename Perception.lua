-- Inventory observation is ready. Opponents/geometry remain separate work.
local Perception = { Name = "Perception", Ready = true }

local function tools(container)
    local result = {}
    if container then
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") then table.insert(result, item) end
        end
    end
    table.sort(result, function(a, b) return a.Name < b.Name end)
    return result
end

function Perception.new(bounds)
    bounds = bounds or {}
    local minY = bounds.LobbyMinY or 300
    local maxY = bounds.LobbyMaxY or 400
    assert(type(minY) == "number" and type(maxY) == "number"
        and minY <= maxY and minY > -math.huge and maxY < math.huge,
        "Invalid lobby height bounds")
    local tracker = { LobbyMinY = minY, LobbyMaxY = maxY }
    function tracker:snapshot(player, now)
        now = now or os.clock()
        local character = player.Character
        local backpack = player:FindFirstChildOfClass("Backpack")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root and not root:IsA("BasePart") then root = nil end
        local y = root and root.Position.Y or nil
        local validHeight = type(y) == "number" and y == y
            and y > -math.huge and y < math.huge
        local equipped, inventory = tools(character), tools(backpack)
        local alive = humanoid ~= nil and humanoid.Health > 0
        local state = "waiting"
        if alive and validHeight then
            state = y >= self.LobbyMinY and y <= self.LobbyMaxY and "lobby" or "arena"
        end
        local selected
        if #equipped == 1 then selected = equipped[1]
        elseif #equipped == 0 and #inventory == 1 then selected = inventory[1] end
        local names, equippedNames = {}, {}
        for _, item in ipairs(inventory) do table.insert(names, item.Name) end
        for _, item in ipairs(equipped) do table.insert(equippedNames, item.Name) end
        return {
            Alive = alive, ArenaState = state, Tool = selected,
            HeightY = validHeight and y or nil, ToolCount = #equipped + #inventory,
            EquippedTool = selected ~= nil and #equipped == 1,
            GloveName = selected and selected.Name or nil,
            AmbiguousTools = #equipped > 1 or (#equipped == 0 and #inventory > 1),
            Inventory = names, Equipped = equippedNames,
            -- User-specified zone rule; inventory only controls combat readiness.
            StateEvidence = "height_y", ObservedAt = now,
        }
    end
    return tracker
end

return Perception

