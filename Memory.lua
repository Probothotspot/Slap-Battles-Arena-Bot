-- Bounded contextual bandit. Learn safe movement preferences from observations.
-- Disappearing targets and increased slap counters are never kills.
local M={Name="Memory",Ready=true}
local actions={"balanced","left","right","cautious"}
local labels={balanced="обычная",left="обход слева",right="обход справа",cautious="дальняя дистанция"}
local policies={balanced={Scale=1,Side=0},left={Scale=.95,Side=-1},right={Scale=.95,Side=1},cautious={Scale=1.08,Side=0}}
local function number(n,lo,hi) return type(n)=="number" and n==n and n>=lo and n<=hi end
local function valid(data)
    if type(data)~="table" or data.Schema~=1 or type(data.Contexts)~="table" or type(data.History)~="table" or #data.History>30 then return false end
    for _,field in ipairs({"Outcomes","Deaths","Hits","Kills","Unknown","Episodes","Sequence"}) do
        if not number(data[field],0,1e12) then return false end
    end
    local count=0
    for key,state in pairs(data.Contexts) do
        count=count+1
        if count>128 or type(key)~="string" or #key>220 or type(state)~="table" or not number(state.Last,0,1e12) then return false end
        for _,name in ipairs(actions) do
            local a=state[name]
            if type(a)~="table" or not number(a.N,0,1000000) or not number(a.Q,-4,4) then return false end
        end
    end
    for _,entry in ipairs(data.History) do
        if type(entry)~="table" or type(entry.Context)~="string" or #entry.Context>220
            or not policies[entry.Action] or not number(entry.Reward,-4,4)
            or (entry.Kind~="Deaths" and entry.Kind~="Hits" and entry.Kind~="Kills" and entry.Kind~="Damage" and entry.Kind~="Blocked") then return false end
    end
    return true
end
function M.new(context)
    local settings=context.Settings
    local clock=context.Clock or os.clock
    local store=settings:openStore("memory-v1",valid,262144)
    local self={Store=store,Dirty=false,Pending={},Seen={},SeenOrder={},NextSave=clock()+15,LastFailures=0}
    self.Data=store:load() or {Schema=1,Contexts={},History={},Outcomes=0,Deaths=0,Hits=0,Kills=0,Unknown=0,Episodes=0,Sequence=0}
    function self:save(force)
        if not self.Dirty or (not force and clock()<self.NextSave) then return end
        self.NextSave=clock()+15
        if store:save(self.Data) then self.Dirty=false end
    end
    function self:finish()
        local e=self.Episode
        if e then
            self.Data.Episodes=self.Data.Episodes+1
            if e.Events==0 then self.Data.Unknown=self.Data.Unknown+1 end
            self.Dirty=true
        end
        self.Episode=nil
    end
    function self:stop()
        self:finish(); self.Pending={}; self:save(true)
    end
    function self:_state(key)
        local state=self.Data.Contexts[key]
        if not state then
            local count,oldest,age=0,nil,math.huge
            for k,s in pairs(self.Data.Contexts) do count=count+1; if s.Last<age then oldest,age=k,s.Last end end
            if count>=128 then self.Data.Contexts[oldest]=nil end
            state={Last=0}
            for _,name in ipairs(actions) do state[name]={N=0,Q=0} end
            self.Data.Contexts[key]=state
        end
        self.Data.Sequence=math.min(1e12,self.Data.Sequence+1); state.Last=self.Data.Sequence
        self.Dirty=true; return state
    end
    function self:policy(snapshot,pursuit,narrow)
        if not settings.LearningEnabled then return policies.balanced end
        local target=pursuit.Target; local tc=target and target.Character
        if not snapshot.Alive or not tc then return policies.balanced end
        local opposing=tc:FindFirstChildOfClass("Tool")
        local own=tostring(snapshot.GloveName or "Default"):sub(1,90)
        local other=tostring(opposing and opposing.Name or "Unknown"):sub(1,90)
        local e=self.Episode
        -- Keep one choice for this encounter, rather than jittering every tick.
        if not e or e.Character~=pursuit.Character or e.TargetCharacter~=tc or e.Own~=own or e.Other~=other
            or e.Narrow~=(narrow==true) or clock()-e.Started>=30 then
            self:finish()
            local key=own.." | "..other.." | "..(narrow and "narrow" or "open")
            local state=self:_state(key)
            local total=0; for _,name in ipairs(actions) do total=total+state[name].N end
            local best,bestScore="balanced",-math.huge
            for _,name in ipairs(actions) do
                local a=state[name]
                local score=a.N==0 and 1000 or a.Q+.55*math.sqrt(math.log(total+1)/a.N)
                if score>bestScore then best,bestScore=name,score end
            end
            local h=pursuit.Humanoid
            e={Key=key,Action=best,Character=pursuit.Character,TargetCharacter=tc,TargetUserId=target.UserId,
                Own=own,Other=other,Narrow=narrow==true,Started=clock(),Events=0,Health=h and h.Health,Dead=false}
            self.Episode=e
        end
        return policies[e.Action]
    end
    function self:_reward(e,value,kind)
        if not e or not settings.LearningEnabled then return end
        local state=self:_state(e.Key); local a=state[e.Action]
        value=math.max(-4,math.min(4,value))
        a.N=math.min(1000000,a.N+1)
        a.Q=a.Q+(value-a.Q)*math.max(.08,1/a.N)
        e.Events=e.Events+1; self.Data.Outcomes=self.Data.Outcomes+1
        if kind=="Hits" or kind=="Kills" or kind=="Deaths" then self.Data[kind]=self.Data[kind]+1 end
        local history=self.Data.History
        history[#history+1]={Context=e.Key,Action=e.Action,Kind=kind,Reward=value}
        if #history>30 then table.remove(history,1) end
        self.Dirty=true
    end
    function self:death(character)
        local e=self.Episode
        if not e or e.Character~=character or e.Dead then return end
        e.Dead=true; self:_reward(e,-3,"Deaths"); self:finish(); self:save(true)
    end
    function self:observe(snapshot,pursuit)
        local e=self.Episode
        if e then
            local h=e.Character and e.Character:FindFirstChildOfClass("Humanoid")
            if h and h.Health<=0 then self:death(e.Character)
            elseif not snapshot.Alive or pursuit.Character~=e.Character or not pursuit.Target
                or pursuit.Target.Character~=e.TargetCharacter then self:finish()
            elseif h then
                if e.Health and h.Health<e.Health then self:_reward(e,-math.min(1,(e.Health-h.Health)/math.max(h.MaxHealth or 100,1)),"Damage") end
                e.Health=h.Health
                local failures=pursuit.Failures or 0
                if failures>self.LastFailures then self:_reward(e,-.4,"Blocked") end
            end
        end
        self.LastFailures=pursuit.Failures or 0
        for id,record in pairs(self.Pending) do if clock()-record.Time>10 then self.Pending[id]=nil end end
        self:save(false)
    end
    function self:attack(id,record)
        local e=self.Episode
        if not e or e.TargetUserId~=record.TargetUserId or e.Character~=record.Character then return end
        self.Pending[id]={Episode=e,Time=clock(),TargetUserId=record.TargetUserId,Character=record.Character}
        local count,oldest,time=0,nil,math.huge
        for k,r in pairs(self.Pending) do count=count+1; if r.Time<time then oldest,time=k,r.Time end end
        if count>64 then self.Pending[oldest]=nil end
    end
    function self:hit(id)
        local r=self.Pending[id]
        if not r or r.Hit or clock()-r.Time>10 then return false end
        r.Hit=true; self:_reward(r.Episode,1,"Hits"); return true
    end
    function self:confirmKill(payload)
        if type(payload)~="table" or payload.AttackerUserId~=context.UserId then return false end
        local r=self.Pending[payload.AttackId]; local event=payload.EventId
        if not r or r.Kill or clock()-r.Time>10 or payload.TargetUserId~=r.TargetUserId
            or (context.Player and context.Player.Character~=r.Character)
            or (type(event)~="string" and type(event)~="number") then return false end
        if type(event)=="string" and (#event==0 or #event>128) then return false end
        if type(event)=="number" and not number(event,-1e15,1e15) then return false end
        local key=type(event)..":"..tostring(event)
        if self.Seen[key] then return false end
        self.Seen[key]=true; self.SeenOrder[#self.SeenOrder+1]=key
        if #self.SeenOrder>128 then self.Seen[table.remove(self.SeenOrder,1)]=nil end
        r.Kill=true; self:_reward(r.Episode,4,"Kills"); self:save(true); return true
    end
    function self:snapshot()
        local count=0; for _ in pairs(self.Data.Contexts) do count=count+1 end
        return {Contexts=count,Outcomes=self.Data.Outcomes,Deaths=self.Data.Deaths,Hits=self.Data.Hits,Kills=self.Data.Kills,
            Unknown=self.Data.Unknown,Action=self.Episode and labels[self.Episode.Action] or "ожидание",Message=store.Message}
    end
    function self:Destroy() self:stop() end
    return self
end
return M
