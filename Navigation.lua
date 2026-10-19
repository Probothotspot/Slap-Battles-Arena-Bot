-- Live lobby portal route with local obstacle/player avoidance and replanning.
local Navigation = { Name = "Navigation", Ready = true }
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function distance(a, b) return flat(a - b).Magnitude end

function Navigation.portalPoints(portal, position, clearance)
    local thinX = portal.Size.X <= portal.Size.Z
    local normal = flat(thinX and portal.CFrame.RightVector or portal.CFrame.LookVector)
    assert(normal.Magnitude > 0.01, "Portal has no horizontal entry axis")
    normal = normal.Unit
    local side = flat(position - portal.Position):Dot(normal) >= 0 and 1 or -1
    local half = (thinX and portal.Size.X or portal.Size.Z) / 2
    local center = Vector3.new(portal.Position.X, position.Y, portal.Position.Z)
    local offset = normal * side * (half + clearance)
    return center + offset, center - offset
end

function Navigation.new(context)
    local world = context.Workspace or game:GetService("Workspace")
    local runService = context.RunService or game:GetService("RunService")
    local pathfinding = context.PathfindingService or game:GetService("PathfindingService")
    local player, options, bounds = context.Player, context.Options, context.Arena
    local spawn, clock = context.Spawn or task.spawn, context.Clock or os.clock
    local bindName = "ArenaBotLobbyPortal"
    local self = { Phase = "waiting", Message = "Ожидание персонажа", Attempts = 0,
        Generation = 0, Destroyed = false, Moving = false, Bound = false,
        TotalAttempts = 0, TotalFailures = 0 }

    function self:_halt()
        if self.Bound then runService:UnbindFromRenderStep(bindName); self.Bound = false end
        if self.Moving and self.Humanoid and self.Humanoid.Parent then
            pcall(function() self.Humanoid:Move(Vector3.zero, false) end)
        end
        self.Moving, self.Target, self.LocalTarget = false, nil, nil
        if self.BlockedConnection then self.BlockedConnection:Disconnect(); self.BlockedConnection = nil end
        if self.NativePath then self.NativePath:Destroy(); self.NativePath=nil end
    end

    function self:stop(message)
        self.Generation = self.Generation + 1
        self:_halt()
        self.Phase, self.Message = "waiting", message or "Движение остановлено"
    end

    function self:Destroy()
        if self.Destroyed then return end
        self:stop("Движение завершено")
        self.Destroyed = true
    end

    function self:getStatus()
        return { Phase = self.Phase, Message = self.Message, Attempts = self.Attempts,
            TotalAttempts = self.TotalAttempts, TotalFailures = self.TotalFailures }
    end

    function self:getRoute()
        if not self.Target or not self.Root or not self.Bound then return {} end
        local points={self.Root.Position}
        if self.LocalTarget then table.insert(points,self.LocalTarget) end
        if self.Phase=="approach" then
            for i=self.Index,#self.Route do table.insert(points,self.Route[i].Position) end
            table.insert(points,self.Crossing)
        else table.insert(points,self.Target) end
        local result={}
        for _,p in ipairs(points) do
            local hit=world:Raycast(p+Vector3.new(0,2,0),Vector3.new(0,-options.GroundProbe,0),self:_params())
            if hit and hit.Position then table.insert(result,hit.Position) else break end
        end
        return result
    end
    function self:_portal()
        local object = world
        for _, name in ipairs(options.Path) do object = object and object:FindFirstChild(name) end
        return object and object:IsA("BasePart") and object or nil
    end

    function self:_params()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { self.Character, self.Portal }
        params.RespectCanCollide = true
        return params
    end

    function self:_ground(point, params)
        local hit = world:Raycast(point + Vector3.new(0, 2, 0), Vector3.new(0, -options.GroundProbe, 0), params)
        if hit and hit.Instance then
            local model=hit.Instance:FindFirstAncestorOfClass("Model")
            if model and model:FindFirstChildOfClass("Humanoid") then return false end
        end
        return hit ~= nil and hit.Normal.Y >= 0.5
    end

    function self:_straightSafe(from, goal)
        local delta, params = flat(goal - from), self:_params()
        if delta.Magnitude>45 then return false end
        if world:Raycast(from, delta, params) then return false end
        local count = math.max(1, math.ceil(delta.Magnitude / 2))
        for i = 0, count do
            if not self:_ground(from + delta * (i / count), params) then return false end
        end
        return true
    end

    function self:_fail(message, now)
        self.TotalFailures = self.TotalFailures + 1
        self.Generation = self.Generation + 1
        self:_halt()
        self.Message = message
        if self.Attempts >= options.MaxAttempts then
            self.Phase, self.RetryAt = "cooldown", now + options.FailureCooldown
        else self.Phase, self.RetryAt = "retry", now + options.RetryDelay end
    end

    function self:_localClear(direction,length)
        local params=self:_params()
        local side=Vector3.new(-direction.Z,0,direction.X)
        for _,offset in ipairs({Vector3.zero,side*.9,side*-.9}) do
            if world:Raycast(self.Root.Position+offset,direction*length,params) then return false end
        end
        for i=1,3 do
            if not self:_ground(self.Root.Position+direction*(length*i/3),params) then return false end
        end
        return true
    end
    function self:_render()
        -- Recheck height every frame to avoid steering toward a stale lobby target.
        if self.Destroyed or player.Character ~= self.Character or not self.Root.Parent
            or not self.Humanoid.Parent or self.Humanoid.Health <= 0 then
            self:stop("Ожидание персонажа"); return
        end
        local y = self.Root.Position.Y
        if y ~= y or y < bounds.LobbyMinY or y > bounds.LobbyMaxY then
            self:stop("Переход: движение остановлено"); return
        end
        if self.Humanoid.Sit or self.Humanoid.PlatformStand then
            self:stop("Персонаж временно не может идти"); return
        end
        if self.Target then
            local delta = flat(self.Target - self.Root.Position)
            local direction=delta.Magnitude>.15 and delta.Unit or Vector3.zero
            local now=clock()
            if not self.AvoidAt or now>=self.AvoidAt then
                self.AvoidAt=now+.08; self.Steering=direction; self.LocalTarget=nil
                local length=math.min(2.5,delta.Magnitude)
                if length>.15 and not self:_localClear(direction,length) then
                    local found=false
                    for _,angle in ipairs({math.pi/3,-math.pi/3}) do
                        local c,s=math.cos(angle),math.sin(angle)
                        local candidate=Vector3.new(direction.X*c-direction.Z*s,0,direction.X*s+direction.Z*c)
                        if self:_localClear(candidate,length) then
                            self.Steering=candidate; self.LocalTarget=self.Root.Position+candidate*length; found=true; break
                        end
                    end
                    if not found then
                        self:_fail("Проход перекрыт — ищу новый путь",now)
                        self.RetryAt=now+.25; return
                    end
                end
            end
            self.Humanoid:Move(self.Steering or direction, false)
            self.Moving = true
        end
    end

    function self:_route(points, now)
        self.Route, self.Index = points, 1
        self.BestDistance, self.LastProgress = math.huge, now
        self.LastCommand, self.Phase, self.Message = nil, "approach", "Иду к красному порталу"
    end

    function self:_start(now)
        if self.EngineBusy then self.Message="Ожидаю завершения прошлого поиска"; return end
        self.TotalAttempts = self.TotalAttempts + 1
        self.Attempts = self.Attempts + 1
        self.Generation = self.Generation + 1
        local generation = self.Generation
        local ok, approach, crossing = pcall(Navigation.portalPoints, self.Portal, self.Root.Position, options.Clearance)
        if not ok then self:_fail("Не удалось определить вход в портал", now); return end
        self.Approach, self.Crossing, self.PortalCFrame = approach, crossing, self.Portal.CFrame
        if self:_straightSafe(self.Root.Position, approach) then
            self:_route({ { Position = approach } }, now); return
        end
        self.Phase, self.Message, self.PathStarted = "path", "Строю путь к порталу", now
        local origin = self.Root.Position
        self.EngineBusy=true
        spawn(function()
            local path
            local computed, waypoints = pcall(function()
                path = pathfinding:CreatePath({ AgentRadius = 2, AgentHeight = 5,
                    AgentCanJump = true, WaypointSpacing = 3 })
                path:ComputeAsync(origin, approach)
                if path.Status ~= Enum.PathStatus.Success then return nil end
                return path:GetWaypoints()
            end)
            self.EngineBusy=false
            if self.Destroyed or self.Generation ~= generation or player.Character ~= self.Character then
                if path then path:Destroy() end; return
            end
            if not computed or type(waypoints) ~= "table" or #waypoints == 0 then
                if path then path:Destroy() end
                self:_fail("Путь к порталу недоступен — повторю подход", clock()); return
            end
            self.NativePath=path
            self:_route(waypoints, clock())
            self.BlockedConnection = path.Blocked:Connect(function(index)
                if not self.Destroyed and self.Generation == generation and index >= self.Index then
                    self:_fail("Путь перекрыт — перестраиваю", clock())
                end
            end)
        end)
    end

    function self:update(snapshot, now)
        if self.Destroyed then return end
        now = now or clock()
        local character = player.Character
        if character ~= self.Character then
            self:stop(); self.Character, self.Attempts = character, 0
        end
        if not options.Enabled or snapshot.ArenaState ~= "lobby" or not snapshot.Alive then
            self:stop(not options.Enabled and "Вход в портал выключен"
                or (snapshot.ArenaState == "arena" and "Арена: вход подтверждён" or "Ожидание персонажа"))
            self.Phase = snapshot.ArenaState == "arena" and "arena" or "waiting"
            self.Attempts = 0; return
        end
        self.Root = character and character:FindFirstChild("HumanoidRootPart")
        self.Humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not self.Root or not self.Root:IsA("BasePart") or not self.Humanoid or self.Humanoid.Health <= 0 then
            self:stop("Ожидание персонажа"); return
        end
        if self.Humanoid.Sit or self.Humanoid.PlatformStand then
            self:stop("Персонаж временно не может идти"); return
        end
        local portal = self:_portal()
        if not portal then self:stop("Ожидание Workspace.Lobby.Teleport1"); return end
        if portal ~= self.Portal then self:stop(); self.Portal, self.Attempts = portal, 0 end
        if self.PortalCFrame and portal.CFrame ~= self.PortalCFrame
            and (self.Phase == "approach" or self.Phase == "enter" or self.Phase == "path") then
            self:_fail("Портал переместился — обновляю путь", now)
        end
        if self.Phase == "cooldown" or self.Phase == "retry" then
            if now < self.RetryAt then return end
            if self.Phase == "cooldown" then self.Attempts = 0 end
            self.Phase = "waiting"
        end
        if self.Phase == "waiting" or self.Phase == "arena" then self:_start(now) end
        if self.Phase == "path" then
            if now - self.PathStarted >= options.PathTimeout then self:_fail("Построение пути заняло слишком долго", now) end
            return
        end
        if self.Phase == "verify" then
            if now >= self.VerifyUntil then self:_fail("Переход не подтверждён — повторю вход", now) end
            return
        end
        if self.Phase == "approach" then
            local waypoint = self.Route[self.Index]
            while waypoint and distance(self.Root.Position, waypoint.Position) <= options.WaypointReach
                and math.abs(self.Root.Position.Y - waypoint.Position.Y) <= 4 do
                if waypoint.Action == Enum.PathWaypointAction.Jump then self.Humanoid.Jump = true end
                self.Index = self.Index + 1
                self.BestDistance, self.LastProgress, self.LastCommand = math.huge, now, nil
                waypoint = self.Route[self.Index]
            end
            if waypoint then
                self.Target = waypoint.Position
                if self.LastCommand ~= self.Index then
                    self.LastCommand = self.Index
                    if waypoint.Action == Enum.PathWaypointAction.Jump then self.Humanoid.Jump = true end
                end
            else
                if self.BlockedConnection then self.BlockedConnection:Disconnect(); self.BlockedConnection = nil end
                if self.NativePath then self.NativePath:Destroy(); self.NativePath=nil end
                self.Phase, self.Message, self.EnterStarted = "enter", "Захожу в красный портал", now
                self.Target, self.BestDistance, self.LastProgress = self.Crossing, math.huge, now
            end
        end
        if self.Phase ~= "approach" and self.Phase ~= "enter" then return end
        if self.Phase == "enter" and (distance(self.Root.Position, self.Crossing) <= options.WaypointReach
            or now - self.EnterStarted >= options.EnterTimeout) then
            self:_halt()
            self.Phase, self.Message, self.VerifyUntil = "verify", "Проверяю переход на арену", now + options.VerifyTimeout
            return
        end
        local delta = flat(self.Target - self.Root.Position)
        local d = delta.Magnitude
        if d + 0.3 < self.BestDistance then self.BestDistance, self.LastProgress = d, now end
        if now - self.LastProgress >= options.StuckTimeout then
            if self.Phase == "enter" then
                self:_halt()
                self.Phase, self.Message, self.VerifyUntil = "verify", "Ожидаю срабатывания портала", now + options.VerifyTimeout
            else self:_fail("Застрял по пути к порталу — повторю подход", now) end
            return
        end
        if d > 0.15 and not self:_ground(self.Root.Position + delta.Unit * math.min(1.5, d), self:_params()) then
            self:_fail("Перед персонажем нет опоры — ищу другой путь", now); return
        end
        if not self.Bound then
            self.Bound = true
            runService:BindToRenderStep(bindName, Enum.RenderPriority.Input.Value + 1, function() self:_render() end)
        end
    end

    return self
end

return Navigation

