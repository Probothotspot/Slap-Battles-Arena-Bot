-- Facing + ordinary Tool activation + cooldown spacing. Server confirmations have a separate explicit feed.
local C={Name="Combat",Ready=true}
local function flat(v) return Vector3.new(v.X,0,v.Z) end
local function finite(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge end
function C.new(context)
    local clock=context.Clock or os.clock
    local o=context.Options
    local adapter=context.Adapter
    local self={Attempts=0,ConfirmedHits=0,Unconfirmed=0,ActivationErrors=0,NextAt=0,Pending={},Seen={},SeenOrder={},
        Phase="paused",Message="Бой остановлен",Sequence=0,ContactChecks=0,ContactAttacks=0}
    function self:_hitParts(tool)
        local now=clock()
        if self.PartsTool==tool and now<(self.PartsUntil or 0) then return self.HitParts end
        local chosen,fallback={},{}
        if tool and tool.GetDescendants then
            for _,part in ipairs(tool:GetDescendants()) do
                if part:IsA("BasePart") then
                    local named=false; local ancestor=part
                    while ancestor and ancestor~=tool do
                        local name=string.lower(ancestor.Name)
                        if name:find("glove",1,true) or name:find("hand",1,true) or name:find("hitbox",1,true)
                            or name:find("slap",1,true) then named=true; break end
                        ancestor=ancestor.Parent
                    end
                    local list=named and chosen or fallback
                    if #list<(o.MaxHitParts or 8) then list[#list+1]=part end
                end
            end
        end
        self.HitParts=#chosen>0 and chosen or fallback
        self.PartsTool,self.PartsUntil=tool,now+(o.HitPartRefresh or .5)
        self.ContactState=nil; self.ContactTool=nil
        return self.HitParts
    end
    function self:_contact(tool,target,root)
        local world=context.Workspace or game:GetService("Workspace")
        local parts=self:_hitParts(tool)
        if #parts==0 or not world.GetPartsInPart then return false,false end
        -- Screen-space pixels can overlap through walls or at different depths.
        -- Query real collision geometry, limited to the current target's body parts.
        local now=clock()
        if self.ContactTool==tool and self.ContactTarget==target and now<(self.ContactUntil or 0) then
            return self.ContactState,self.ContactAvailable
        end
        local filter=OverlapParams.new(); filter.FilterType=Enum.RaycastFilterType.Include
        filter.FilterDescendantsInstances={target}; filter.RespectCanCollide=false; filter.MaxParts=0
        filter.CollisionGroup=root.CollisionGroup
        local touching,available=false,false
        for _,part in ipairs(parts) do
            if part.Parent and part:IsDescendantOf(tool) and part.Size.Magnitude<80 then
                self.ContactChecks=self.ContactChecks+1
                local ok,hits=pcall(function() return world:GetPartsInPart(part,filter) end)
                if ok then
                    available=true
                    for _,hit in ipairs(hits) do
                        -- Accessories and the opponent's Tool do not constitute body contact.
                        if hit:IsA("BasePart") and hit.Parent==target then touching=true; break end
                    end
                end
            end
            if touching then break end
        end
        self.ContactTool,self.ContactTarget,self.ContactUntil=tool,target,now+(o.ContactCheckInterval or 1/60)
        self.ContactState,self.ContactAvailable=touching,available
        return touching,available
    end
    function self:_measuredDistance(tool,root,targetRoot,profile)
        if not profile.PreferContact or not root then return profile.Range*(profile.StandOff or .85) end
        local reach=0
        for _,part in ipairs(self:_hitParts(tool)) do
            if part.Parent and part:IsDescendantOf(tool) then
                -- Horizontal support of an oriented box along the facing direction.
                local look=flat(root.CFrame.LookVector).Unit
                local cf,size=part.CFrame,part.Size
                local extent=(math.abs(cf.RightVector:Dot(look))*size.X+math.abs(cf.UpVector:Dot(look))*size.Y
                    +math.abs(cf.LookVector:Dot(look))*size.Z)/2
                reach=math.max(reach,flat(part.Position-root.Position):Dot(look)+extent)
            end
        end
        local targetRadius=targetRoot and targetRoot.Size and math.min(targetRoot.Size.X,targetRoot.Size.Z)/2 or 1
        if reach>1 then return math.max(1,math.min(profile.Range,reach+targetRadius-.3)) end
        return profile.Range*(profile.StandOff or .85)
    end
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
        self.PartsTool=nil; self.HitParts=nil; self.ContactState=nil; self.ContactTool=nil
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
        if not narrow and pursuit.Root and pursuit._geometry then
            local foot=pursuit:_geometry():project(pursuit.Root.Position,1,8)
            local size=foot and foot.Size
            narrow=size and math.min(size.X,size.Z)<4 or false
        end
        local tc=pursuit.Target and pursuit.Target.Character
        local tr=tc and tc:FindFirstChild("HumanoidRootPart")
        local desired=self:_measuredDistance(snapshot.Tool,pursuit.Root,tr,p)
        if recovery and not narrow then desired=p.Range+o.RecoveryPadding end
        local flanking=false
        local behind=tr and tr.CFrame and flat(tr.CFrame.LookVector)*-1
        if o.FlankEnabled and not recovery and not narrow and behind and behind.Magnitude>.01 and pursuit.Root then
            local offset=flat(pursuit.Root.Position-tr.Position)
            flanking=offset.Magnitude>.01 and offset.Magnitude<=desired+(o.FlankEngagePadding or 7)
                and offset.Unit:Dot(behind.Unit)<math.cos(o.BehindAngle or math.rad(60))
        end
        return {DesiredDistance=desired,HoldMin=math.max(.8,desired-.55),HoldMax=math.min(desired+.45,recovery and desired+.45 or p.Range),
            Narrow=narrow,Flanking=flanking,Behind=behind,Stance=recovery and "recover" or "attack",
            Message=recovery and "Выдерживаю интервал и сохраняю дистанцию" or (flanking and "Захожу за спину" or "Подхожу для удара")}
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
        if not finite(distance) or distance>math.max(profile.Range+o.FacePadding,profile.PreferContact and 40 or 0)
            or math.abs(root.AssemblyLinearVelocity.Y)>12 then idle("Преследую цель"); return end
        if context.Knowledge and not context.Knowledge.get(s.GloveName).CanSlap then idle("Нужен отдельный контроллер перчатки"); return end
        -- Re-read visibility, range and footing at execution time, not just the older perception tick.
        local world=context.Workspace or game:GetService("Workspace")
        if world:Raycast(root.Position,tr.Position-root.Position,pursuit.Params) then idle("Между нами препятствие"); return end
        local aligned=self:_face(root,h,tr.Position,dt or 0)
        if not self:ready() or s.Tool.Enabled==false then
            self.Phase,self.Message="cooldown",s.Tool.Enabled==false and "Инструмент пока не готов" or "Выдерживаю интервал удара"; return
        end
        local contact,available=self:_contact(s.Tool,tc,root)
        if not aligned and not contact then self.Phase,self.Message="facing","Поворачиваюсь к цели"; return end
        if not contact and (distance>profile.Range or (profile.PreferContact and available)) then
            self.Phase,self.Message="approach","Подвожу перчатку к цели"; return
        end
        if not pursuit:_geometry():project(root.Position,1,8) then idle("Нет подтверждённой опоры"); return end
        local obs=c.Observations or {}
        if obs.Target and (obs.Target.CounterActive or obs.Target.ReverseActive or obs.Target.Invulnerable) then idle("У цели активная защита"); return end
        if c.Plan and c.Plan.Action~="slap" and c.Plan.Action~="space" and c.Plan.Action~="approach" then
            self.Phase,self.Message="waiting",c.Plan.Reason or "Ожидаю решения"; return
        end
        self.Sequence=self.Sequence+1; local id=self.Sequence
        self.Attempts=self.Attempts+1; self.NextAt=clock()+profile.Interval
        if contact then self.ContactAttacks=self.ContactAttacks+1 end
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
            ContactChecks=self.ContactChecks,ContactAttacks=self.ContactAttacks,
            Phase=self.Phase,Message=self.Message,Cooldown=math.max(0,self.NextAt-clock()),Profile=self.CurrentProfile}
    end
    return self
end
return C
