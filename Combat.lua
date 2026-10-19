-- Facing + ordinary Tool activation + cooldown spacing. Server confirmations have a separate explicit feed.
local C={Name="Combat",Ready=true}
local function flat(v) return Vector3.new(v.X,0,v.Z) end
local function finite(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge end
function C.new(context)
    local clock=context.Clock or os.clock
    local o=context.Options
    local adapter=context.Adapter
    local self={Attempts=0,ConfirmedHits=0,Unconfirmed=0,ActivationErrors=0,NextAt=0,Pending={},Seen={},SeenOrder={},
        Phase="paused",Message="Бой остановлен",Sequence=0}
    function self:profile(tool)
        if adapter then return adapter:profile(tool,o) end
        return {Range=o.ConservativeRange,Interval=o.Interval,Verified=false,Source="Настройки профиля"}
    end
    function self:ready() return clock()>=self.NextAt end
    function self:_deactivate()
        if self.Tool then pcall(function() self.Tool:Deactivate() end); self.Tool=nil end
    end
    function self:_releaseFacing()
        if self.FacingHumanoid and self.FacingHumanoid.Parent then self.FacingHumanoid.AutoRotate=self.WasAutoRotate end
        self.FacingHumanoid,self.WasAutoRotate=nil,nil
    end
    function self:_expire()
        local now=clock()
        for id,record in pairs(self.Pending) do
            if now-record.Time>o.ConfirmationWindow then self.Pending[id]=nil; self.Unconfirmed=self.Unconfirmed+1 end
        end
    end
    function self:stop()
        self:_deactivate(); self:_releaseFacing(); self.Context=nil
        self.Phase,self.Message="paused","Бой остановлен"
        for id in pairs(self.Pending) do self.Pending[id]=nil; self.Unconfirmed=self.Unconfirmed+1 end
        -- Keep NextAt across Stop/Start so toggling cannot bypass the attack interval.
    end
    function self:Destroy() self:stop(); self.Destroyed=true end
    function self:confirm(payload)
        if self.Destroyed or not adapter or not adapter.HitFeedAvailable or not self.Context then return false end
        self:_expire()
        local id=payload.AttackId; local record=self.Pending[id]
        local event=payload.EventId
        if not record or (type(event)~="string" and type(event)~="number") then return false end
        if type(event)=="string" and (#event==0 or #event>128) then return false end
        if type(event)=="number" and not finite(event) then return false end
        local key=type(event)..":"..tostring(event)
        if self.Seen[key] or payload.AttackerUserId~=context.Player.UserId
            or payload.TargetUserId~=record.TargetUserId or record.Character~=context.Player.Character then return false end
        self.Seen[key]=true; table.insert(self.SeenOrder,key)
        if #self.SeenOrder>128 then self.Seen[table.remove(self.SeenOrder,1)]=nil end
        self.Pending[id]=nil; self.ConfirmedHits=self.ConfirmedHits+1
        if context.Log then context.Log("Подтверждено попадание по "..record.TargetName) end
        return true
    end
    function self:getMovementIntent(snapshot,pursuit)
        local p=self:profile(snapshot.Tool)
        local recovery=not self:ready()
        local narrow=pursuit._narrowCorridor and pursuit:_narrowCorridor()
        if recovery and not narrow and pursuit.Root and pursuit._geometry then
            local foot=pursuit:_geometry():project(pursuit.Root.Position,1,8)
            local size=foot and foot.Size
            narrow=size and math.min(size.X,size.Z)<4 or false
        end
        local desired=p.Range*.85
        if recovery and not narrow then desired=p.Range+o.RecoveryPadding end
        return {DesiredDistance=desired,HoldMin=math.max(.8,desired-.55),HoldMax=math.min(desired+.45,recovery and desired+.45 or p.Range),
            Narrow=narrow,Stance=recovery and "recover" or "attack",Message=recovery and "Выдерживаю интервал и сохраняю дистанцию" or "Подхожу для удара"}
    end
    function self:_face(root,humanoid,target,dt)
        local desired=flat(target-root.Position)
        if desired.Magnitude<.01 then return false end
        desired=desired.Unit
        if self.FacingHumanoid~=humanoid then
            self:_releaseFacing(); self.FacingHumanoid=humanoid; self.WasAutoRotate=humanoid.AutoRotate
        end
        humanoid.AutoRotate=false
        local current=flat(root.CFrame.LookVector)
        current=current.Magnitude>.01 and current.Unit or desired
        local atan=math.atan2 or math.atan
        local angle=(atan(desired.Z,desired.X)-atan(current.Z,current.X)+math.pi)%(2*math.pi)-math.pi
        local amount=math.min(math.abs(angle),o.TurnRate*math.max(0,math.min(dt,.1)))
        if angle<0 then amount=-amount end
        local c,s=math.cos(amount),math.sin(amount)
        local facing=Vector3.new(current.X*c-current.Z*s,0,current.X*s+current.Z*c)
        root.CFrame=CFrame.lookAt(root.Position,root.Position+facing)
        return facing:Dot(desired)>=math.cos(o.FacingTolerance)
    end
    function self:update(snapshot,plan,character,pursuit,observations)
        self.Context={Snapshot=snapshot,Plan=plan,Character=character,Pursuit=pursuit,Observations=observations}
        self:step(0)
    end
    function self:step(dt)
        self:_expire()
        if self.Tool and clock()>=self.ReleaseAt then self:_deactivate() end
        local c=self.Context
        if self.Destroyed or not c then return end
        local s,pursuit=c.Snapshot,c.Pursuit
        local char=c.Character
        local root=char and char:FindFirstChild("HumanoidRootPart")
        local h=char and char:FindFirstChildOfClass("Humanoid")
        local target=pursuit.Target; local tc=target and target.Character
        local tr=tc and tc:FindFirstChild("HumanoidRootPart")
        local th=tc and tc:FindFirstChildOfClass("Humanoid")
        local function idle(message)
            self:_deactivate(); self:_releaseFacing(); self.Phase,self.Message="waiting",message
        end
        if not o.Enabled or not pursuit.Running or not s.Alive or s.ArenaState~="arena" or not root or not h
            or h.Health<=0 or h.Sit or h.PlatformStand or (context.Player and context.Player.Character~=char)
            or not target or not tr or not th or th.Health<=0 or pursuit.TargetCharacter~=tc
            or not s.Tool or not s.EquippedTool or s.Tool.Parent~=char or char:FindFirstChildOfClass("Tool")~=s.Tool then
            idle("Ожидание готового персонажа, перчатки и цели"); return
        end
        local bounds=context.Arena or {LobbyMinY=300,LobbyMaxY=400}
        local function lobby(y) return y>=bounds.LobbyMinY and y<=bounds.LobbyMaxY end
        if lobby(root.Position.Y) or lobby(tr.Position.Y) or tc:FindFirstChildOfClass("ForceField") then idle("Цель недоступна или защищена"); return end
        local profile=self:profile(s.Tool); self.CurrentProfile=profile
        local distance=(tr.Position-root.Position).Magnitude
        if not finite(distance) or distance>profile.Range+o.FacePadding or math.abs(root.AssemblyLinearVelocity.Y)>12 then idle("Преследую цель"); return end
        if context.Knowledge and not context.Knowledge.get(s.GloveName).CanSlap then idle("Нужен отдельный контроллер перчатки"); return end
        -- Re-read visibility, range and footing at execution time, not just the older perception tick.
        local world=context.Workspace or game:GetService("Workspace")
        if world:Raycast(root.Position,tr.Position-root.Position,pursuit.Params) then idle("Между нами препятствие"); return end
        if not pursuit:_geometry():project(root.Position,1,8) then idle("Нет подтверждённой опоры"); return end
        local aligned=self:_face(root,h,tr.Position,dt or 0)
        if not aligned then self.Phase,self.Message="facing","Поворачиваюсь к цели"; return end
        if not self:ready() or s.Tool.Enabled==false then
            self.Phase,self.Message="cooldown",s.Tool.Enabled==false and "Инструмент пока не готов" or "Выдерживаю интервал удара"; return
        end
        if distance>profile.Range or pursuit.Phase~="position" then self.Phase,self.Message="approach","Подхожу на дистанцию удара"; return end
        local obs=c.Observations or {}
        if obs.Target and (obs.Target.CounterActive or obs.Target.ReverseActive or obs.Target.Invulnerable) then idle("У цели активная защита"); return end
        if c.Plan and c.Plan.Action~="slap" and c.Plan.Action~="space" then self.Phase,self.Message="waiting",c.Plan.Reason or "Ожидаю решения"; return end
        self.Sequence=self.Sequence+1; local id=self.Sequence
        self.Attempts=self.Attempts+1; self.NextAt=clock()+profile.Interval
        self.Pending[id]={Time=clock(),TargetUserId=target.UserId,TargetName=target.Name,Character=char}
        -- Bound the queue even for a very fast configured profile.
        local ids={}; for key in pairs(self.Pending) do table.insert(ids,key) end; table.sort(ids)
        while #ids>16 do self.Pending[table.remove(ids,1)]=nil; self.Unconfirmed=self.Unconfirmed+1 end
        self.Phase,self.Message="swing","Удар по "..target.Name
        local ok=pcall(function() s.Tool:Activate() end)
        if ok then self.Tool=s.Tool; self.ReleaseAt=clock()+o.ActivationSeconds
        else self.Pending[id]=nil; self.ActivationErrors=self.ActivationErrors+1; self.Message="Не удалось активировать инструмент" end
        if context.Log then context.Log("Попытка удара #"..id.." по "..target.Name) end
    end
    function self:snapshot()
        self:_expire()
        local pending=0; for _ in pairs(self.Pending) do pending=pending+1 end
        local feed=adapter and adapter.HitFeedAvailable or false
        self.HadHitFeed=self.HadHitFeed or feed
        return {AttackAttempts=self.Attempts,ConfirmedHits=self.HadHitFeed and self.ConfirmedHits or nil,
            HitFeedAvailable=feed,UnconfirmedAttacks=self.Unconfirmed,ActivationErrors=self.ActivationErrors,PendingAttacks=pending,
            Phase=self.Phase,Message=self.Message,Cooldown=math.max(0,self.NextAt-clock()),Profile=self.CurrentProfile}
    end
    return self
end
return C
