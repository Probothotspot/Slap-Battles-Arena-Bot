-- Returns proposals only. Navigation/Combat must validate and execute separately.
local Decision = { Name = "Decision", Ready = true }

function Decision.plan(knowledge, snapshot, observations)
    local context = {}
    for key, value in pairs(observations or {}) do context[key] = value end
    -- Callers cannot override the locally observed life/arena/tool state.
    context.Alive = snapshot.Alive
    context.ArenaState = snapshot.ArenaState
    context.AmbiguousTools = snapshot.AmbiguousTools
    context.Equipped = snapshot.EquippedTool
    context.HasTool = (snapshot.ToolCount or 0) > 0
    return knowledge.plan(snapshot.GloveName, context)
end

return Decision

