-- Explicit integration points; no guessed game RemoteEvents or inflated mesh-derived reach.
local A={Name="SlapBattles",Ready=true}
local function positive(n,maximum) return type(n)=="number" and n==n and n>0 and n<=maximum end
function A.new(context)
    local self={HitFeedAvailable=false,Player=context.Player}
    function self:profile(tool,options)
        local configured=(options.GloveProfiles or {})[tool and tool.Name or ""] or {}
        local range=configured.Range or options.ConservativeRange
        local interval=configured.Interval or options.Interval
        if not positive(range,40) then range=4.5 end
        if not positive(interval,30) then interval=.8 end
        local verified=configured.Verified==true and positive(configured.Range,40) and positive(configured.Interval,30)
        return {Range=range,Interval=interval,Verified=verified,
            Source=verified and "Проверенный профиль" or "Настройки: требуется проверка в игре"}
    end
    function self:unbindHitFeed()
        self.HitFeedAvailable=false
        if self.Connection then self.Connection:Disconnect(); self.Connection=nil end
    end
    -- decode must be written against a verified, server-originated confirmation schema.
    -- Result: {AttackId, AttackerUserId, TargetUserId, EventId}; a counter or Touched is not a hit feed.
    function self:bindHitFeed(signal,decode,callback)
        assert(signal and type(decode)=="function" and type(callback)=="function","Hit feed requires signal and decoder")
        self:unbindHitFeed()
        self.Connection=signal:Connect(function(...)
            if not self.HitFeedAvailable then return end
            local ok,payload=pcall(decode,...)
            if ok and type(payload)=="table" and payload.AttackerUserId==self.Player.UserId then callback(payload) end
        end)
        self.HitFeedAvailable=true
    end
    function self:Destroy() self:unbindHitFeed() end
    return self
end
return A
