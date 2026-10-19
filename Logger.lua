local Logger = {}
Logger.__index = Logger

function Logger.new(debugEnabled)
    return setmetatable({ debugEnabled = debugEnabled }, Logger)
end

function Logger:info(message)
    print("[ArenaBot] " .. tostring(message))
end

function Logger:debug(message)
    if self.debugEnabled then self:info(message) end
end

return Logger
