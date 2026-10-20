-- Arena pursuit: one engine request in flight, cooperative surface A*, live stopping checks.
local A={Name="ArenaNavigation",Ready=true}
local function flat(v) return Vector3.new(v.X,0,v.Z) end
local function distance(a,b) return flat(a-b).Magnitude end
local function finite(v) return v and v.X==v.X and v.Y==v.Y and v.Z==v.Z and v.Magnitude<1e7 end
local function playerRig(player,bounds)
    local c=player.Character; local root=c and c:FindFirstChild("HumanoidRootPart")
    local h=c and c:FindFirstChildOfClass("Humanoid")
    if not root or not root:IsA("BasePart") or not h or h.Health<=0 or not finite(root.Position) then return nil end
    local y=root.Position.Y
    if y>=bounds.LobbyMinY and y<=bounds.LobbyMaxY then return nil end
    return c,root,h
end
function A.new(context)
    local world=context.Workspace or game:GetService("Workspace")
    local players=context.Players or game:GetService("Players")
    local run=context.RunService or game:GetService("RunService")
    local pfs=context.PathfindingService or game:GetService("PathfindingService")
    local clock,spawn=context.Clock or os.clock,context.Spawn or task.spawn
    local o,bounds,player,S=context.Options,context.Arena,context.Player,context.SurfaceRoutes
    local self={Generation=0,Running=false,Destroyed=false,Phase="waiting",Message="Ожидание арены",
        NextPlan=0,NextSelect=0,Plans=0,Failures=0,GraphNodes=0,Expanded=0,
        LastSliceWork=0,PeakSliceWork=0,RouteSource="—",TargetName="—",Direction=Vector3.zero,GraphCache={}}
    local bindName="ArenaBotPursuit"
    function self:_release()
        self.Direction=Vector3.zero; self.LocalTarget=nil
        if (self.Running or self.Bound) and self.Humanoid and self.Humanoid.Parent then self.Humanoid:Move(Vector3.zero,false) end
    end
    function self:_clearPath(release)
        self.Route=nil; self.Index=1; self.RouteCost=nil; self.SupportScan=2
        self.RefreshAllowed=false; self.GroundOffset=nil
        if self.Blocked then self.Blocked:Disconnect(); self.Blocked=nil end
        if self.Path then self.Path:Destroy(); self.Path=nil end
        if release~=false then self:_release() end
    end
    function self:_dropPending()
        if self.PendingPath and self.PendingPath~=self.Path then self.PendingPath:Destroy() end
        if self.EngineCandidate and self.EngineCandidate.Path then self.EngineCandidate.Path:Destroy() end
        self.PendingPath=nil
    end
    function self:stop(message)
        self.Generation=self.Generation+1; self.Running=false
        self:_dropPending()
        self.Job=nil; self.EngineCandidate=nil; self.ValidationJob=nil; self.Cache=nil; self.GraphCache={}
        self.Target=nil; self.TargetCharacter=nil; self.TargetName="—"
        self:_clearPath()
        if self.Bound then run:UnbindFromRenderStep(bindName); self.Bound=false end
        self.Phase,self.Message="waiting",message or "Движение остановлено"
        self.NextPlan=0; self.PlanTarget=nil; self.PlanStarted=nil; self.AttemptFinished=true
    end
    function self:Destroy() if not self.Destroyed then self:stop(); self.Destroyed=true end end
    function self:getRoute()
        if not self.Running or not self.Route or not self.Root then return {} end
        local ground=self:_geometry():project(self.Root.Position,1,8)
        if not ground then return {} end
        local points={ground.Position}
        if self.LocalTarget then table.insert(points,self.LocalTarget) end
        for i=self.Index,#self.Route do table.insert(points,self.Route[i].Position) end
        return points
    end
    function self:getStatus()
        return {Phase=self.Phase,Message=self.Message,Target=self.TargetName,RouteSource=self.RouteSource,
            Plans=self.Plans,Failures=self.Failures,GraphNodes=self.GraphNodes,Expanded=self.Expanded,
            SliceWork=self.LastSliceWork,PeakSliceWork=self.PeakSliceWork,
            PlanSeconds=self.LastPlanSeconds,PlanSlices=self.LastPlanSlices,GoalCandidates=self.GoalCandidates,
            GraphCacheHit=self.GraphCacheHit,EdgeCacheHits=self.EdgeCacheHits,EdgeChecks=self.EdgeChecks,
            Waypoints=self.Route and #self.Route or 0,Waypoint=self.Index or 0,Planning=self.Job~=nil or self.EngineBusy}
    end
    function self:_params()
        local exclude={}
        for _,p in ipairs(players:GetPlayers()) do if p.Character then table.insert(exclude,p.Character) end end
        local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances=exclude; params.RespectCanCollide=true
        params.CollisionGroup=self.Root.CollisionGroup
        return params,exclude
    end
    function self:_geometry(checkpoint,params,bodyParams)
        return S.new({Workspace=world,Options=o,Params=params or self.Params,BodyParams=bodyParams,Checkpoint=checkpoint,
            GraphCache=self.GraphCache,Clock=clock})
    end
    function self:_checkpoint()
        if self.SliceOps>=o.WorkPerFrame or clock()-self.SliceStart>=o.BudgetSeconds then coroutine.yield() end
        self.SliceOps=self.SliceOps+1
    end
    function self:_targetValid(p)
        local c,r,h=playerRig(p,bounds)
        if not c or h.PlatformStand or h.Sit or c:FindFirstChildOfClass("ForceField") then return nil end
        if distance(self.Root.Position,r.Position)>o.TargetRadius then return nil end
        if context.Knowledge then
            local tool=c:FindFirstChildOfClass("Tool")
            if tool and context.Knowledge.get(tool.Name).Policy=="spectator" then return nil end
        end
        return c,r,h
    end
    function self:_supportsValid(proofs)
        if not proofs then return false end
        for _,proof in ipairs(proofs) do
            local part=proof.Part
            if not part or not part.Parent or not part.CanCollide
                or (proof.Pose and part.CFrame~=proof.Pose) or (proof.Size and part.Size~=proof.Size) then return false end
        end
        return true
    end
    function self:_narrowCorridor()
        if not self.Route then return false end
        for i=self.Index,math.min(#self.Route,self.Index+1) do
            local node=self.Route[i]
            if node.Narrow then return true end
            for _,proof in ipairs(node.Supports or {}) do
                if proof.Size and math.min(proof.Size.X,proof.Size.Z)<4 then return true end
            end
        end
        return false
    end
    function self:_canRefresh()
        if not self.Route then return true end
        if self:_narrowCorridor() then return false end
        local remaining=0; local p=self.Root.Position
        for i=self.Index,#self.Route do
            remaining=remaining+distance(p,self.Route[i].Position); p=self.Route[i].Position
            if remaining>o.EndpointRefreshDistance then return false end
        end
        return true
    end
    function self:_advance(ground,now)
        if not self.Route then return end
        local point=self.Route[self.Index]
        while point do
            local previous=self.Route[self.Index-1]
            local reached=distance(ground,point.Position)<=o.WaypointReach
            if not reached and previous then
                local edge=flat(point.Position-previous.Position); local length=edge.Magnitude
                if length>.01 then
                    local along=flat(ground-previous.Position):Dot(edge.Unit)
                    local cross=flat(ground-previous.Position-edge.Unit*along).Magnitude
                    reached=along>=length and cross<=o.PassedPointCorridor and distance(ground,point.Position)<=o.LookAhead+o.WaypointReach
                end
            end
            if not reached or math.abs(ground.Y-point.Position.Y)>=1.5 then break end
            self.Index=self.Index+1; self.BestDistance,self.LastProgress=math.huge,now
            self.CheckedAt=nil; point=self.Route[self.Index]
        end
    end
    function self:_select(now)
        if self.Route and self.Target and self.Target.Character==self.TargetCharacter
            and self:_narrowCorridor() and self:_targetValid(self.Target) then return end
        if now<self.NextSelect and self.Target and self.Target.Character==self.TargetCharacter and self:_targetValid(self.Target) then return end
        self.NextSelect=now+o.SelectInterval
        local best,bestScore=nil,math.huge
        for _,p in ipairs(players:GetPlayers()) do
            if p~=player then
                local _,r=self:_targetValid(p)
                if r and now>=(self.Unreachable and self.Unreachable[p] or 0) then
                    local score=distance(self.Root.Position,r.Position)+math.abs(self.Root.Position.Y-r.Position.Y)*1.5
                    -- Keep a useful route instead of oscillating between similar players.
                    if p==self.Target then score=score*o.TargetHysteresis end
                    if score<bestScore then best,bestScore=p,score end
                end
            end
        end
        if best~=self.Target or (best and best.Character~=self.TargetCharacter) then
            self.Generation=self.Generation+1; self:_dropPending(); self.Job=nil; self.ValidationJob=nil; self.EngineCandidate=nil
            self:_clearPath(); self.NextPlan=now
            self.Target=best; self.TargetCharacter=best and best.Character
            self.TargetName=best and best.Name or "—"
        end
    end
    function self:_accept(route,cost,source,generation,path)
        if self.Destroyed or not self.Running or generation~=self.Generation or not self.Target
            or self.Target.Character~=self.TargetCharacter then if path then path:Destroy() end; return end
        if not route or #route<2 then if path then path:Destroy() end; return end
        -- Keep the chosen crossing, including when a second planner returns a slightly cheaper alternative.
        if self.Route and not self.RefreshAllowed then if path then path:Destroy() end; return end
        local geom=self:_geometry(function() self:_checkpoint() end)
        local ground=geom:project(self.Root.Position,1,8)
        local candidates={}
        if ground then
            for i=2,#route do
                self:_checkpoint()
                local a,b=route[i-1].Position,route[i].Position
                local edge=b-a; local length=edge.Magnitude
                if length>.01 then
                    local t=math.max(0,math.min(1,(ground.Position-a):Dot(edge)/(length*length)))
                    local projection=a+edge*t
                    local d=(ground.Position-projection).Magnitude
                    if d<=o.AttachDistance then table.insert(candidates,{Index=i,Point=projection,Distance=d}) end
                end
            end
        end
        table.sort(candidates,function(a,b) return a.Distance<b.Distance end)
        local attached
        for _,candidate in ipairs(candidates) do
            local node=geom:project(candidate.Point,1,3)
            if node then
                local safe,proofs=geom:segment(ground.Position,node.Position)
                if safe then
                    node.Supports=proofs; node.EngineIndex=route[candidate.Index].EngineIndex
                    -- Projection skips the old prefix even if the bot moved less than AttachDistance.
                    attached={ground}
                    if (node.Position-ground.Position).Magnitude>.05 then table.insert(attached,node) end
                    for i=candidate.Index,#route do table.insert(attached,route[i]) end
                    break
                end
            end
        end
        if not attached then if path then path:Destroy() end; return end
        route=attached
        if self.Route and self.RouteCost and cost>=self.RouteCost*.95 then if path then path:Destroy() end; return end
        self:_clearPath(false) -- Swapping a route must not issue a zero movement command.
        self.Route,self.RouteCost,self.Index,self.Path=route,cost,2,path
        self.RouteSource,self.LastProgress,self.BestDistance=source,clock(),math.huge
        self.CheckedAt=nil
        self.Job=nil -- The accepted route is settled; stop evaluating alternative graph routes.
        self.LastPlanSeconds=self.PlanStarted and clock()-self.PlanStarted or 0
        self.LastPlanSlices=self.PlanSlices or 0
        self.PlanStarted=nil; self.AttemptFinished=true
        self.Phase,self.Message="pursuit","Иду к "..self.TargetName.." · "..source
        if path then
            self.Blocked=path.Blocked:Connect(function(index)
                local current=self.Route and self.Route[self.Index]
                if self.Running and self.Path==path and index>=(current and current.EngineIndex or self.Index) then self:_invalidate("Путь перекрыт") end
            end)
        end
    end
    function self:_invalidate(message)
        self.Generation=self.Generation+1; self:_dropPending(); self.Job=nil; self.ValidationJob=nil; self.EngineCandidate=nil
        self.Cache=nil; self.GraphCache={}; self.PlanTarget=nil; self.PlanStarted=nil; self.AttemptFinished=true
        self:_clearPath(); self.NextPlan=clock()+o.MinReplanInterval
        self.Phase,self.Message="replan",message.." — ищу обход"
    end
    function self:_goals(geometry,targetRoot)
        local v=flat(targetRoot.AssemblyLinearVelocity or Vector3.zero)
        local lead=v*o.PredictionSeconds
        if lead.Magnitude>o.MaxPrediction then lead=lead.Unit*o.MaxPrediction end
        local predicted=targetRoot.Position+lead
        -- A led position over empty space is discarded, never used as a blind destination.
        local ground=geometry:project(predicted,2,10) or geometry:project(targetRoot.Position,2,10)
        if not ground then return {} end
        local dir=flat(self.Root.Position-ground.Position)
        dir=dir.Magnitude>.01 and dir.Unit or Vector3.new(1,0,0)
        local result={}
        local intent=self.CombatIntent
        local preferred
        if intent and intent.Flanking and intent.Behind then
            local behind=intent.Behind.Unit
            local atan=math.atan2 or math.atan
            local angle=(atan(behind.Z,behind.X)-atan(dir.Z,dir.X)+math.pi)%(2*math.pi)-math.pi
            if math.abs(math.abs(angle)-math.pi)<.05 then
                self.FlankSide=self.FlankSide or ((player.UserId or 0)%2==0 and 1 or -1)
                angle=math.abs(angle)*self.FlankSide
            end
            local turn=math.min(math.abs(angle),o.FlankStep or math.rad(45))*(angle<0 and -1 or 1)
            local c,s=math.cos(turn),math.sin(turn)
            preferred=Vector3.new(dir.X*c-dir.Z*s,0,dir.X*s+dir.Z*c)
        end
        local count=math.max(5,math.min(48,o.GoalCandidates or 24))
        for i=0,count-1 do
            local angle=i*2*math.pi/count
            local c,s=math.cos(angle),math.sin(angle)
            local offset=Vector3.new(dir.X*c-dir.Z*s,0,dir.X*s+dir.Z*c)*(self.CombatIntent and self.CombatIntent.DesiredDistance or o.DesiredDistance)
            local goal=geometry:project(ground.Position+offset,2,5)
            if goal and math.abs(goal.Position.Y-ground.Position.Y)<3 then
                goal.GoalPenalty=preferred and (1-offset.Unit:Dot(preferred))*(intent.DesiredDistance or o.DesiredDistance)*(o.FlankWeight or 4) or 0
                table.insert(result,goal)
            end
        end
        table.sort(result,function(a,b) return distance(self.Root.Position,a.Position)<distance(self.Root.Position,b.Position) end)
        self.GoalCandidates=#result
        return result
    end
    function self:_request(now,targetRoot)
        if self.Job or self.ValidationJob or self.EngineCandidate or now<self.NextPlan then return end
        self.NextPlan=now+o.MinReplanInterval; self.Plans=self.Plans+1
        self.Generation=self.Generation+1; local generation=self.Generation
        self.PlanTarget=targetRoot.Position; self.PlanStarted=now; self.PlanSlices=0; self.RouteCost=nil; self.AttemptFinished=false
        self.GraphCacheHit=false; self.EdgeCacheHits=0; self.EdgeChecks=0
        self.RefreshAllowed=self.Route~=nil
        self.PlanStance=self.CombatIntent and self.CombatIntent.Stance
        self.PlanFacing=targetRoot.CFrame and flat(targetRoot.CFrame.LookVector)
        self.PlanFlanking=self.CombatIntent and self.CombatIntent.Flanking
        local origin=self.Root.Position; local params,exclude=self:_params(); self.Params=params
        local function checkpoint() self:_checkpoint() end
        self.Job=coroutine.create(function()
            local geom=self:_geometry(checkpoint,params)
            local start=geom:project(origin,2,10); if not start then return end
            local goals=self:_goals(geom,targetRoot); if #goals==0 then return end
            local function score(g) return (g.Position-start.Position).Magnitude+(g.GoalPenalty or 0) end
            table.sort(goals,function(a,b) return score(a)<score(b) end)
            local best,bestCost
            for _,goal in ipairs(goals) do
                local lower=score(goal)
                if bestCost and lower>=bestCost then break end
                local safe,proofs=geom:segment(start.Position,goal.Position)
                if safe then
                    goal.Supports=proofs
                    local cost=lower
                    if not bestCost or cost<bestCost then best,bestCost={start,goal},cost end
                end
            end
            if best then self:_accept(best,bestCost,"прямой проверенный",generation); return end
            -- Engine planning yields outside this coroutine; at most one ComputeAsync in flight.
            if not self.EngineBusy then
            self.EngineBusy=true; self.EngineStarted=clock(); self.EngineGeneration=generation
            spawn(function()
                local path
                local ok,points=pcall(function()
                    path=pfs:CreatePath({AgentRadius=math.ceil(o.BodyRadius),AgentHeight=math.ceil(o.BodyHeight+1),
                        AgentCanJump=false,AgentCanClimb=false,WaypointSpacing=3})
                    path:ComputeAsync(origin,goals[1].Position)
                    if path.Status==Enum.PathStatus.Success then return path:GetWaypoints() end
                end)
                self.EngineBusy=false
                if self.Destroyed or not self.Running or generation~=self.Generation then if path then path:Destroy() end; return end
                if self.Route and not self.RefreshAllowed then if path then path:Destroy() end; return end
                if ok and points and #points>1 then
                    self.EngineCandidate={Points=points,Path=path,Generation=generation,Start=start}
                elseif path then path:Destroy() end
            end)
            end
            local parts
            local cache=self.Cache
            if cache and clock()-cache.Time<o.CacheSeconds and distance(cache.Origin,origin)<o.CacheDistance then
                parts=cache.Parts
            else
                local overlap=OverlapParams.new(); overlap.FilterType=Enum.RaycastFilterType.Exclude
                overlap.FilterDescendantsInstances=exclude; overlap.MaxParts=o.MaxParts; overlap.RespectCanCollide=true
                overlap.CollisionGroup=self.Root.CollisionGroup
                checkpoint(); parts=world:GetPartBoundsInRadius(origin,o.ScanRadius,overlap)
                self.Cache={Parts=parts,Origin=origin,Time=clock()}
            end
            local route,cost,info=geom:build(parts,start.Position,goals)
            if info then
                self.GraphNodes,self.Expanded=info.Nodes,info.Expanded
                self.GraphCacheHit,self.EdgeCacheHits,self.EdgeChecks=info.CacheHit,info.EdgeCacheHits,info.EdgeChecks
            end
            if route then self:_accept(route,cost,"поверхности A*",generation) end
        end)
        if not self.Route then self.Phase,self.Message="planning","Ищу безопасный путь к "..self.TargetName end
    end
    function self:_work(now)
        if self.Phase=="position" and not self.Job and not self.ValidationJob and not self.EngineCandidate then return end
        if self.PlanStarted and now-self.PlanStarted>o.PlanTimeout and (self.Job or self.ValidationJob or (self.EngineBusy and self.EngineGeneration==self.Generation)) then
            self.Failures=self.Failures+1; self:_invalidate("Истекло время поиска"); return
        end
        self.SliceOps,self.SliceStart=0,clock()
        if self.EngineCandidate then
            local candidate=self.EngineCandidate; self.EngineCandidate=nil
            self.ValidationJob=coroutine.create(function()
                local geom=self:_geometry(function() self:_checkpoint() end)
                local route={candidate.Start}; local cost=0
                for i,point in ipairs(candidate.Points) do
                    local node=geom:project(point.Position,3,8)
                    if not node then candidate.Path:Destroy(); return end
                    node.EngineIndex=i
                    if (node.Position-route[#route].Position).Magnitude>.1 then
                        cost=cost+(node.Position-route[#route].Position).Magnitude; table.insert(route,node)
                    end
                end
                if geom:validate(route) then self:_accept(route,cost,"Roblox path",candidate.Generation,candidate.Path)
                else candidate.Path:Destroy() end
            end)
            -- Keep ownership even if validation is cancelled.
            self.PendingPath=candidate.Path
        end
        local job=self.ValidationJob or self.Job
        if job then
            self.PlanSlices=(self.PlanSlices or 0)+1
            local ok,err=coroutine.resume(job)
            if not ok then
                self.Failures=self.Failures+1; self.LastError=tostring(err)
                self:_invalidate("Ошибка расчёта маршрута")
            elseif coroutine.status(job)=="dead" then
                if job==self.ValidationJob then self.ValidationJob=nil; self.PendingPath=nil else self.Job=nil end
            end
        end
        self.LastSliceWork=self.SliceOps; self.PeakSliceWork=math.max(self.PeakSliceWork,self.SliceOps)
        if self.PlanStarted and not self.AttemptFinished and not self.Job and not self.ValidationJob and (not self.EngineBusy or self.EngineGeneration~=self.Generation) and not self.EngineCandidate and not self.Route then
            self.AttemptFinished=true
            if self.Target then
                self.Unreachable=self.Unreachable or {}; self.Unreachable[self.Target]=now+o.UnreachableCooldown
            end
            self.Message="Безопасный путь не найден — проверяю другие цели"; self.NextSelect=0
            self.NextPlan=math.max(self.NextPlan,now+o.RetryDelay)
        end
    end
    function self:_stepClear(geom,start,look,point,body)
        local edgeStart=self.Route[math.max(1,self.Index-1)].Position
        local edge=flat(point.Position-edgeStart)
        local t=edge.Magnitude>.01 and flat(start-edgeStart):Dot(edge)/(edge.Magnitude*edge.Magnitude) or 0
        local cross=distance(start,edgeStart+edge*t)
        if not point.Supports or cross>o.CachedCorridor then return geom:segment(start,look) end
        if not self:_supportsValid(point.Supports) then return false end
        -- This edge was already validated. Recheck changed geometry and the next footfall,
        -- rather than re-proving all footprint samples and rebuilding the route.
        local delta=look-start
        for _,t in ipairs({.5,1}) do
            local expected=start+delta*t
            local node=geom:project(expected,o.StepHeight+.25,2*o.StepHeight+.5)
            if not node or math.abs(node.Position.Y-expected.Y)>o.StepHeight then return false end
        end
        local lift=Vector3.new(0,o.BodyHeight/2+o.StepHeight,0)
        return not world:Blockcast(CFrame.new(start+lift),Vector3.new(o.BodyRadius*2,o.BodyHeight,o.BodyRadius*2),delta,body)
    end
    function self:_safety(now)
        if not self.Route then self:_release(); return end
        local root,h=self.Root,self.Humanoid
        local body=RaycastParams.new(); body.FilterType=Enum.RaycastFilterType.Exclude
        body.FilterDescendantsInstances={self.Character}; body.RespectCanCollide=true; body.CollisionGroup=self.Root.CollisionGroup
        local geom=self:_geometry(nil,nil,body)
        local start=geom:project(root.Position,1,8)
        if not start or math.abs((root.AssemblyLinearVelocity or Vector3.zero).Y)>o.MaxVerticalSpeed then self:_release(); return end
        self.GroundOffset=root.Position.Y-start.Position.Y
        self:_advance(start.Position,now)
        local point=self.Route[self.Index]
        if not point then self.AttemptFinished=not (self.Job or self.ValidationJob or self.EngineCandidate); self:_clearPath(); self.Phase,self.Message="position","Держу дистанцию от "..self.TargetName; return end
        if point.Part and (not point.Part.Parent or not point.Part.CanCollide or point.Pose~=point.Part.CFrame) then
            self:_invalidate("Опора изменилась"); return
        end
        -- Round-robin stamp checks catch a removed/moved/resized board further along the path.
        for _=1,3 do
            local scan=math.max(self.Index,self.SupportScan or self.Index)
            if scan>#self.Route then scan=self.Index end
            local proofs=self.Route[scan].Supports
            if proofs and not self:_supportsValid(proofs) then self:_invalidate("Опора маршрута изменилась"); return end
            self.SupportScan=scan+1
        end
        local delta=point.Position-start.Position; local d=flat(delta).Magnitude
        local look=start.Position+delta*(math.min(o.LookAhead,d)/math.max(d,.001))
        self.LocalTarget=nil
        if not self:_stepClear(geom,start.Position,look,point,body) then
            local found=false
            local direction=flat(delta).Unit
            for _,angle in ipairs({math.pi/3,-math.pi/3}) do
                local c,s=math.cos(angle),math.sin(angle)
                local alternate=Vector3.new(direction.X*c-direction.Z*s,0,direction.X*s+direction.Z*c)
                local node=geom:project(start.Position+alternate*o.LookAhead,2,5)
                if node and geom:segment(start.Position,node.Position) then
                    delta=node.Position-start.Position; self.LocalTarget=node.Position; found=true; break
                end
            end
            if not found then self:_invalidate("Впереди препятствие или край"); return end
        end
        if d+.15<self.BestDistance then self.BestDistance,self.LastProgress=d,now end
        if now-self.LastProgress>o.StuckSeconds then self.Failures=self.Failures+1; self:_invalidate("Нет продвижения"); return end
        self.Direction=d>.1 and flat(delta).Unit or Vector3.zero
        self.CheckedAt=now
    end
    function self:_render()
        local now=clock()
        if self.Destroyed or not self.Running or player.Character~=self.Character then self:stop(); return end
        local _,root,h=playerRig(player,bounds)
        if root~=self.Root or not h or h.Sit or h.PlatformStand then self:_release(); return end
        if not self.Target or not self:_targetValid(self.Target) or self.Target.Character~=self.TargetCharacter then self:_release(); return end
        -- Brake between perception ticks as soon as the live target enters the
        -- desired band; do not follow a stale approach waypoint into their torso.
        local tr=self.TargetCharacter:FindFirstChild("HumanoidRootPart")
        local intent=self.CombatIntent
        if intent and tr and math.abs(root.Position.Y-tr.Position.Y)<3 then
            local gap=distance(root.Position,tr.Position)
            if gap<=intent.HoldMax and not world:Raycast(root.Position,tr.Position-root.Position,self.Params) then
                if (gap>=intent.HoldMin and not intent.Flanking) or (gap<intent.HoldMin and self.Direction.Magnitude>0 and self.Direction:Dot(flat(tr.Position-root.Position))>0) then
                    self:_release(); return
                end
            end
        end
        if self.Route and self.GroundOffset then
            self:_advance(root.Position-Vector3.new(0,self.GroundOffset,0),now)
        end
        if not self.CheckedAt or now-self.CheckedAt>o.CheckInterval then
            self.CheckedAt=now
            local ok,err=pcall(function() self:_safety(now) end)
            if not ok then self.LastError=tostring(err); self:_invalidate("Не удалось проверить опору"); return end
        end
        if not self.Route or now-(self.CheckedAt or 0)>o.CheckInterval*2 then self.Direction=Vector3.zero end
        if self.Route and not self.LocalTarget and self.Route[self.Index] then
            local delta=flat(self.Route[self.Index].Position-root.Position)
            if self.Direction.Magnitude>0 then self.Direction=delta.Magnitude>.01 and delta.Unit or Vector3.zero end
        end
        h:Move(self.Direction,false)
    end
    function self:update(snapshot,now)
        if self.Destroyed then return end
        now=now or clock()
        if not o.Enabled or not snapshot.Alive or snapshot.ArenaState~="arena" then self:stop(); return end
        local character,root,h=playerRig(player,bounds)
        if not character or h.Sit or h.PlatformStand then self:stop("Ожидание управления персонажем"); return end
        if self.Character~=character then self:stop(); self.Character=character end
        self.Root,self.Humanoid,self.Running=root,h,true
        self.Params=self:_params()
        if not self.Bound then
            self.Bound=true; run:BindToRenderStep(bindName,Enum.RenderPriority.Input.Value+1,function() self:_render() end)
        end
        if not snapshot.Tool or snapshot.AmbiguousTools then self:stop("Арена: выбери перчатку"); return end
        local profile=context.Knowledge and context.Knowledge.get(snapshot.GloveName)
        if profile and not profile.CanSlap then self:stop("Этой перчатке нужен отдельный контроллер"); return end
        if not snapshot.EquippedTool then h:EquipTool(snapshot.Tool) end
        self:_select(now)
        if not self.Target then self:_release(); self.Phase,self.Message="search","Ищу живого игрока на арене"; return end
        local _,targetRoot=self:_targetValid(self.Target)
        if not targetRoot then self:_release(); return end
        -- Finish the bounded current search even while the target moves. Cancelling it on
        -- every position update would starve bridge searches; the next request refreshes its endpoint.
        if self.PlanTarget and distance(self.PlanTarget,targetRoot.Position)>o.StaleTargetDistance then
            self.Message="Цель движется — обновляю точку подхода"
        end
        self.CombatIntent=self.Combat and self.Combat:getMovementIntent(snapshot,self) or nil
        local intent=self.CombatIntent
        local holdMin,holdMax=intent and intent.HoldMin or o.HoldMin,intent and intent.HoldMax or o.HoldMax
        local d=distance(root.Position,targetRoot.Position)
        if not (intent and intent.Flanking) and d>=holdMin and d<=holdMax and math.abs(root.Position.Y-targetRoot.Position.Y)<3
            and not world:Raycast(root.Position,targetRoot.Position-root.Position,self.Params) then
            self.Generation=self.Generation+1; self:_dropPending(); self.Job=nil; self.ValidationJob=nil; self.EngineCandidate=nil
            self.AttemptFinished=true; self:_clearPath(); self.Message=intent and intent.Message or "Держу дистанцию от "..self.TargetName; self.Phase="position"
        else
            local moved=not self.PlanTarget or distance(self.PlanTarget,targetRoot.Position)>o.TargetReplanDistance
                or (intent and self.PlanStance~=intent.Stance)
                or (intent and self.PlanFlanking~=intent.Flanking)
                or (intent and intent.Flanking and self.PlanFacing and targetRoot.CFrame
                    and flat(targetRoot.CFrame.LookVector):Dot(self.PlanFacing)<math.cos(o.FlankRefreshAngle or .6))
            if not self.Route or (moved and self:_canRefresh()) then self:_request(now,targetRoot) end
        end
    end
    function self:step()
        if not self.Destroyed and self.Running then self:_work(clock()) end
    end
    return self
end
return A
