local Cleanup = {}
Cleanup.__index = Cleanup

function Cleanup.new()
    return setmetatable({ items = {}, destroyed = false }, Cleanup)
end

local function release(item)
    local kind = typeof(item)
    if kind == "RBXScriptConnection" then
        item:Disconnect()
    elseif kind == "Instance" then
        item:Destroy()
    elseif type(item) == "function" then
        item()
    end
end

function Cleanup:add(item)
    if self.destroyed then
        release(item)
    else
        table.insert(self.items, item)
    end
    return item
end

function Cleanup:Destroy()
    if self.destroyed then return end
    self.destroyed = true
    for i = #self.items, 1, -1 do
        local ok, err = pcall(release, self.items[i])
        if not ok then warn("[ArenaBot cleanup] " .. tostring(err)) end
    end
    self.items = {}
end

return Cleanup
