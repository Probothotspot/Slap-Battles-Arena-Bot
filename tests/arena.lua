-- Real planner/controller, synthetic 3-D collision world (not Roblox rendering or live server physics).
local saved={Vector3=Vector3,CFrame=CFrame,Enum=Enum,RaycastParams=RaycastParams,OverlapParams=OverlapParams}
local V,mt={},{}
function V.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},mt) end
mt.__add=function(a,b) return V.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
mt.__sub=function(a,b) return V.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
mt.__mul=function(a,n) return V.new(a.X*n,a.Y*n,a.Z*n) end
mt.__div=function(a,n) return a*(1/n) end
mt.__unm=function(a) return a*-1 end
mt.__index=function(a,k)
    if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
    if k=="Unit" then return a/a.Magnitude end
    if k=="Dot" then return function(x,b) return x.X*b.X+x.Y*b.Y+x.Z*b.Z end end
    if k=="Cross" then return function(x,b) return V.new(x.Y*b.Z-x.Z*b.Y,x.Z*b.X-x.X*b.Z,x.X*b.Y-x.Y*b.X) end end
end
V.zero=V.new(0,0,0); Vector3=V
local function frame(position,right,up,back)
    local cf={Position=position,RightVector=right or V.new(1,0,0),UpVector=up or V.new(0,1,0),BackVector=back or V.new(0,0,1)}
    cf.LookVector=cf.BackVector*-1
    function cf:PointToWorldSpace(p) return self.Position+self.RightVector*p.X+self.UpVector*p.Y+self.BackVector*p.Z end
    function cf:PointToObjectSpace(p) local d=p-self.Position; return V.new(d:Dot(self.RightVector),d:Dot(self.UpVector),d:Dot(self.BackVector)) end
    return cf
end
CFrame={new=function(p) return frame(p) end}
CFrame.lookAt=function(p,target,up)
    local look=(target-p).Unit; local normal=up or V.new(0,1,0)
    return frame(p,look:Cross(normal),normal,look*-1)
end
Enum={RaycastFilterType={Exclude="exclude"},Material={Water="water"},PathStatus={Success="success"},
    RenderPriority={Input={Value=100}}}
RaycastParams={new=function() return {} end}; OverlapParams={new=function() return {} end}
local S=dofile("SurfaceRoutes.lua"); local A=dofile("ArenaNavigation.lua"); local C=dofile("Combat.lua")
local config=dofile("config.lua"); local checks=0
local function eq(a,b,why) checks=checks+1; assert(a==b,(why or "Mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
local function part(pos,size,cf)
    return {Parent=true,CanCollide=true,Size=size,Position=pos,CFrame=cf or frame(pos),
        IsA=function(_,class) return class=="BasePart" end}
end
local function plank(a,b,width)
    local right=(b-a).Unit; local back=V.new(-right.Z,0,right.X).Unit
    local up=back:Cross(right); local mid=(a+b)/2-up*.5
    return part(mid,V.new((b-a).Magnitude,1,width or 2),frame(mid,right,up,back))
end
local function collisionWorld(parts)
    local w={Queries=0,Parts=parts,Wall=false}
    function w:Raycast(origin,dir)
        self.Queries=self.Queries+1
        if self.VisibilityWall and math.abs(dir.Y)<.01 then return {Instance=self.VisibilityWall} end
        local nearest,tmin
        for _,p in ipairs(self.Parts) do
            if p.Parent and p.CanCollide then
                local normal=p.CFrame.UpVector; local den=dir:Dot(normal)
                if math.abs(den)>.00001 then
                    local top=p.CFrame:PointToWorldSpace(V.new(0,p.Size.Y/2,0))
                    local t=(top-origin):Dot(normal)/den
                    if t>=0 and t<=1 then
                        local pos=origin+dir*t; local localP=p.CFrame:PointToObjectSpace(pos)
                        if math.abs(localP.X)<=p.Size.X/2+.0001 and math.abs(localP.Z)<=p.Size.Z/2+.0001 and (not tmin or t<tmin) then
                            nearest={Position=pos,Normal=normal,Instance=p,Material="solid"}; tmin=t
                        end
                    end
                end
            end
        end
        return nearest
    end
    function w:Blockcast(cf,size,dir)
        self.Queries=self.Queries+1
        if self.Wall then return {Instance=self.Wall} end
        if self.LocalWall then
            for i=0,4 do
                local q=cf.Position+dir*(i/4)
                if math.abs(q.X-10)<1.1 and math.abs(q.Z)<3 then return {Instance=self.LocalWall} end
            end
        end
        -- Floors: test swept body against solid boxes, with actual part orientation.
        for _,p in ipairs(self.Parts) do
            if p.Parent and p.CanCollide then
                for i=0,4 do
                    local center=cf.Position+dir*(i/4)
                    for _,height in ipairs({-size.Y/2+.05,0,size.Y/2}) do
                        local q=p.CFrame:PointToObjectSpace(center+V.new(0,height,0))
                        if math.abs(q.X)<p.Size.X/2 and math.abs(q.Z)<p.Size.Z/2 and math.abs(q.Y)<p.Size.Y/2-.02 then return {Instance=p} end
                    end
                end
            end
        end
    end
    function w:GetPartBoundsInRadius() self.Queries=self.Queries+1; local r={}; for _,p in ipairs(self.Parts) do r[#r+1]=p end; return r end
    return w
end
local function geometry(world,checkpoint)
    return S.new({Workspace=world,Options=config.Pursuit,Params={},Checkpoint=checkpoint})
end
-- Multi-goal A* selects measured route cost, can reopen a node whose queued score improved.
local nodes={}; for i,p in ipairs({V.new(0,0,0),V.new(2,0,0),V.new(0,0,3),V.new(4,0,0),V.new(0,0,5)}) do nodes[i]={Position=p} end
local adjacency={{2,3},{4},{5},{},{}}
local path,cost=S.search(nodes,1,{4,5},function(i) return adjacency[i] end,
    function(a,b) return (nodes[a].Position-nodes[b].Position).Magnitude end,function() end,30)
eq(path[#path],nodes[4],"Choose cheaper of multiple destinations"); eq(cost,4)
local short=S.search(nodes,1,{4},function(i) return adjacency[i] end,function() return false end,function() end,30)
eq(short,nil,"Disconnected graph never invents an edge")
local _,_,expanded=S.search(nodes,1,{4},function(i) return adjacency[i] end,function() return 1 end,function() end,1)
eq(expanded,1,"Expansion limit")

local left=part(V.new(-10,-.5,0),V.new(20,1,20))
local right=part(V.new(32,3.5,0),V.new(20,1,20))
local bridges={plank(V.new(-2,0,8),V.new(3,0,16)),plank(V.new(3,0,16),V.new(19,4,16)),plank(V.new(19,4,16),V.new(25,4,8))}
local parts={left,right}; for _,p in ipairs(bridges) do parts[#parts+1]=p end
local world=collisionWorld(parts); local geom=geometry(world)
eq(geom:segment(V.new(-10,0,0),V.new(32,4,0)),false,"Never walk across open void")
eq(geom:segment(V.new(3,0,16),V.new(19,4,16)),true,"Climb a supported sloping plank")
local calls=0
local co=coroutine.create(function()
    local g=geometry(world,function() calls=calls+1; if calls%64==0 then coroutine.yield() end end)
    local goals={g:project(V.new(32,4,0),1,3)}
    return g:build(parts,V.new(-10,0,0),goals)
end)
local route,graphCost,info,slices
slices=0
repeat
    local ok,a,b,c=coroutine.resume(co); assert(ok,a); slices=slices+1
    if coroutine.status(co)=="dead" then route,graphCost,info=a,b,c end
until coroutine.status(co)=="dead" or slices>10000
eq(route~=nil,true,"Find connected island route through three angled/sloping planks")
eq(route[#route].Position.X>25,true)
eq(info.Nodes<=config.Pursuit.MaxNodes,true,"Node cap")
eq(slices>1,true,"Work is split across slices")
local crossedBridge=false
for _,n in ipairs(route) do if n.Position.Z>12 then crossedBridge=true end end
eq(crossedBridge,true,"Route uses the off-axis bridge instead of cutting across void")
eq(geom:validate(route),true,"Every output segment remains supported")
world.Wall=part(V.new(0,0,0),V.new(1,1,1))
eq(geom:validate(route),false,"New wall invalidates old route")
world.Wall=false; bridges[2].Parent=nil
eq(geom:validate(route),false,"Removed plank invalidates old route")
bridges[2].Parent=true
local gapWorld=collisionWorld({left,right}); local g=geometry(gapWorld)
local disconnected=g:build({left,right},V.new(-10,0,0),{g:project(V.new(32,4,0),1,3)})
eq(disconnected,nil,"Unconnected islands produce no walking route")

local function rig()
    local r={Now=0,Queue={},Binds={},Moves=0,Requests=0,DestroyedPaths=0}
    r.World=collisionWorld({part(V.new(0,-.5,0),V.new(100,1,100))})
    local function player(name,x)
        local root={Parent=true,Position=V.new(x,3,0),AssemblyLinearVelocity=V.zero,CollisionGroup="Default",IsA=function() return true end}
        root.CFrame=CFrame.lookAt(root.Position,root.Position+V.new(1,0,0))
        local h={Parent=true,AutoRotate=true,Health=100,Move=function(_,d) r.Direction=d; r.Moves=r.Moves+1; if d.Magnitude==0 then r.ZeroMoves=(r.ZeroMoves or 0)+1 end end,EquipTool=function() end}
        local tool={Name="Default",Enabled=true,Activate=function() r.Activations=(r.Activations or 0)+1 end,Deactivate=function() end}
        local char={}
        function char:FindFirstChild(n) if n=="HumanoidRootPart" then return root end end
        function char:FindFirstChildOfClass(n) if n=="Humanoid" then return h elseif n=="Tool" then return tool end end
        tool.Parent=char
        return {Name=name,UserId=name=="self" and 1 or 2,Character=char},root,h,tool
    end
    r.Player,r.Root,r.Humanoid,r.Tool=player("self",0)
    r.Enemy,r.EnemyRoot,r.EnemyHumanoid=player("opponent",20)
    local players={GetPlayers=function() return {r.Player,r.Enemy} end}
    local run={BindToRenderStep=function(_,n,_,cb) r.Binds[n]=cb end,UnbindFromRenderStep=function(_,n) r.Binds[n]=nil end}
    local pfs={CreatePath=function()
        r.Requests=r.Requests+1
        local path={Status=r.EnginePoints and "success" or "no_path",ComputeAsync=function() end,GetWaypoints=function() return r.EnginePoints or {} end,
            Blocked={Connect=function(_,cb) r.Blocked=cb; return {Disconnect=function() r.Blocked=nil end} end},
            Destroy=function() r.DestroyedPaths=r.DestroyedPaths+1 end}
        return path
    end}
    r.Nav=A.new({Workspace=r.World,Players=players,RunService=run,PathfindingService=pfs,Player=r.Player,
        Options=config.Pursuit,Arena=config.Arena,SurfaceRoutes=S,Knowledge=dofile("GloveKnowledge.lua"),
        Clock=function() return r.Now end,Spawn=function(cb) table.insert(r.Queue,cb) end})
    r.Snapshot={Alive=true,ArenaState="arena",Tool=r.Tool,GloveName="Default",EquippedTool=true}
    function r:update() self.Nav:update(self.Snapshot,self.Now) end
    function r:step() self.Nav:step() end
    function r:render() local cb=self.Binds.ArenaBotPursuit; if cb then cb() end end
    return r
end
local r=rig(); r:update()
eq(r.Nav.Running,true)
for _=1,100 do r:step(); if r.Nav.Route then break end end
eq(r.Nav.RouteSource,"прямой проверенный","Open ground uses cheapest validated direct route")
eq(r.Requests,0,"Do not ComputeAsync on an open floor")
eq(r.Nav.PeakSliceWork<=config.Pursuit.WorkPerFrame,true,"Bound cooperative work per frame")
r:render(); eq(r.Direction.X>0,true,"Follow route")
local visible=r.Nav:getRoute(); eq(#visible>=2,true,"Expose the actual active route for preview")
r.EnemyRoot.Position=V.new(20,350,0); r.Now=.2; r:render()
eq(r.Direction.Magnitude,0,"Stop steering at a target that returned to lobby")
r.Now=.7; r:update(); eq(r.Nav.Target,nil,"Lobby player cannot remain a combat target")
r.Nav:Destroy(); eq(next(r.Binds),nil,"Destroy unbinds render")

r=rig(); r:update(); r:step(); local old=r.Nav.Generation
r.Nav:stop(); for _=1,100 do r:step() end
r:render(); eq(r.Nav.Route,nil,"Stop during cooperative search cancels the result")
eq(r.Nav.Generation>old,true); eq(next(r.Binds),nil)
r=rig(); r.World.Wall=true; r:update()
for _=1,100 do r:step(); if #r.Queue>0 then break end end
eq(#r.Queue,1,"One queued engine request")
local requests=r.Requests
r.Now=20; r:update(); r:step(); r:update(); r:step()
eq(#r.Queue,1,"Timed out ComputeAsync is not replaced by overlapping requests")
r.Nav:stop(); r.Queue[1]()
eq(r.Nav.Route,nil,"Late engine result after Stop cannot restart movement")
eq(r.DestroyedPaths,1,"Release a stale native path object")

r=rig(); r:update(); for _=1,100 do r:step(); if r.Nav.Route then break end end
r.Nav:stop(); r.Now=1; r:update(); for _=1,100 do r:step(); if r.Nav.Route then break end end
r.EnemyRoot.Position=V.new(40,3,0); r.Now=2; r:update()
eq(r.Nav.Job,nil,"Target motion keeps a useful long route instead of rebuilding it")
r:render(); r.Root.Position=V.new(10,3,0); r.Now=3; r:render(); r:update()
eq(r.Nav.Job~=nil,true,"Refresh moving-target endpoint only near the end of the corridor")
eq(r.Nav.Route~=nil,true,"Keep a validated route while its replacement computes")
r=rig(); r:update(); for _=1,100 do r:step(); if r.Nav.Route then break end end
r.World.Wall=true; r.Now=.2; r:render()
eq(r.Nav.Route,nil,"New impassable wall stops steering before replanning")
eq(r.Direction.Magnitude,0)
r=rig(); r:update(); for _=1,100 do r:step(); if r.Nav.Route then break end end
r.World.Parts[1].Parent=nil; r.Now=.2; r:render()
eq(r.Direction.Magnitude,0,"Lost floor releases walking immediately")
r=rig(); r.EnemyRoot.Position=V.new(4,3,0); r:update()
eq(r.Nav.Phase,"position","Hold spacing instead of walking onto target")
local combat=C.new({Options=config.Attack,Clock=function() return r.Now end,Workspace=r.World,Player=r.Player,Arena=config.Arena})
local observations={Target={Distance=4,LineOfSight=true,Invulnerable=false}}
combat:update(r.Snapshot,{Action="slap"},r.Player.Character,r.Nav,observations)
eq(combat.Attempts,1,"Activate ordinary Tool only in a checked attack position")
combat:update(r.Snapshot,{Action="slap"},r.Player.Character,r.Nav,observations)
eq(combat.Attempts,1,"Throttle tool activation")
r.Now=2; observations.Target.Invulnerable=true
combat:update(r.Snapshot,{Action="slap"},r.Player.Character,r.Nav,observations)
eq(combat.Attempts,1,"Do not activate against a protected player")
observations.Target.Invulnerable=false; r.Nav:stop(); r.Now=3
combat:update(r.Snapshot,{Action="slap"},r.Player.Character,r.Nav,observations)
eq(combat.Attempts,1,"Paused controller never attacks")
-- Native path results are separately surface-validated and cancelled with their Blocked listener.
r=rig(); r.World.LocalWall=true
r.EnginePoints={{Position=V.new(0,0,0)},{Position=V.new(0,0,8)},{Position=V.new(16,0,8)},{Position=V.new(16,0,0)}}
r:update()
for tick=1,150 do
    r:step()
    if #r.Queue>0 and not r.DidEngine then r.Queue[1](); r.DidEngine=true end
    if r.Nav.RouteSource=="Roblox path" then break end
end
eq(r.Nav.RouteSource,"Roblox path","Validate and use a native detour around a wall")
eq(r.Nav.Path~=nil,true,"Keep native path ownership for Blocked events")
r.Blocked(0); eq(r.Nav.Route~=nil,true,"Ignore a blockage behind the current native waypoint")
r.Blocked(2); eq(r.Nav.Route,nil,"A native blockage ahead triggers replanning")
eq(r.DestroyedPaths,1,"Release the invalid native path")
r.Nav:Destroy()

-- Integrate actual steering across the bridge graph, including height changes and cornering.
r=rig(); r.World.Parts=parts; r.Root.Position=V.new(-10,3,0); r.EnemyRoot.Position=V.new(32,7,0)
local fell=false; local arrived=false; local processed=0
for tick=1,1500 do
    r.Now=tick/60
    if tick%12==1 then r:update() end
    r:step()
    while processed<#r.Queue do processed=processed+1; r.Queue[processed]() end
    r:render()
    if r.Direction and r.Direction.Magnitude>0 then
        local nextPosition=r.Root.Position+r.Direction*(10/60)
        local support=r.World:Raycast(nextPosition+V.new(0,2,0),V.new(0,-10,0))
        if not support then fell=true; break end
        r.Root.Position=support.Position+V.new(0,3,0)
    end
    if r.Nav.Phase=="position" and (r.Root.Position-r.EnemyRoot.Position).Magnitude<5 then arrived=true; break end
end
eq(fell,false,"Integrated steering never steps into the island gap")
eq(arrived,true,"Actual steering reaches the opposite island using angled and sloped boards")
r.Nav:Destroy()

-- At 16 studs/s and 30 updates/s, bridge progress must stay forward on a fixed route.
r=rig(); r.World.Parts=parts; r.Root.Position=V.new(-10,3,0); r.EnemyRoot.Position=V.new(32,7,0)
local bridgeBacksteps=0; local bridgeFrames=0; local processedFast=0; local fellFast=false; local fixedRoute; local routeChanges=0
for tick=1,1200 do
    r.Now=tick/30
    if tick%6==1 then r:update() end
    r:step()
    while processedFast<#r.Queue do processedFast=processedFast+1; r.Queue[processedFast]() end
    r:render()
    if r.Nav.Route and r.Nav:_narrowCorridor() and r.Direction and r.Direction.Magnitude>0 then
        bridgeFrames=bridgeFrames+1
        fixedRoute=fixedRoute or r.Nav.Route
        if r.Nav.Route~=fixedRoute then routeChanges=routeChanges+1 end
        local edge=r.Nav.Route[r.Nav.Index].Position-r.Nav.Route[r.Nav.Index-1].Position
        if r.Direction:Dot(V.new(edge.X,0,edge.Z))<-.01 then bridgeBacksteps=bridgeBacksteps+1 end
    end
    if r.Direction and r.Direction.Magnitude>0 then
        local nextPosition=r.Root.Position+r.Direction*(16/30)
        local support=r.World:Raycast(nextPosition+V.new(0,2,0),V.new(0,-10,0))
        if not support then fellFast=true; break end
        r.Root.Position=support.Position+V.new(0,3,0)
    end
    if r.Nav.Phase=="position" then break end
end
eq(routeChanges,0,"Keep one chosen route throughout the unchanged bridge")
eq(bridgeFrames>10,true,"Exercise full-speed crossing, not only route generation")
eq(bridgeBacksteps,0,"No backward steering toward passed plank waypoints at full walk speed")
eq(fellFast,false,"Faster following retains gap protection")
eq(r.Nav.Phase,"position","Full-speed crossing still reaches the opposite island")
r.Nav:Destroy()

-- Smooth traversal regressions: passed points, stable bridges, cheap invariant checks and no stop pulse.
r=rig(); r:update(); for _=1,120 do r:step(); if r.Nav.Route then break end end
local floor=r.World.Parts[1]
local function node(x) return {Position=V.new(x,0,0),Part=floor,Pose=floor.CFrame,Size=floor.Size,
    Supports={{Part=floor,Pose=floor.CFrame,Size=floor.Size}}} end
r.Nav.Route={node(0),node(1),node(8),node(16)}; r.Nav.Index=2
r.Root.Position=V.new(1.8,3,0); r.Now=.2; r:render()
eq(r.Nav.Index>=3,true,"Skip an overshot waypoint instead of returning to it")
eq(r.Direction.X>0,true,"No backward step after a slightly missed waypoint")
r.Root.Position=V.new(3,3,0); r.Now=.4
local beforeQueries=r.World.Queries; local beforeZeros=r.ZeroMoves or 0
r:render()
eq(r.World.Queries-beforeQueries<=4,true,"Unchanged edge needs only ground/change probes and one volume sweep")
eq(r.ZeroMoves or 0,beforeZeros,"Safety check does not emit a stop command")
-- A new route based on an origin less than AttachDistance behind us must still skip its old prefix.
r.Nav.RefreshAllowed=true; r.Nav.RouteCost=nil
local incoming={node(0),node(1),node(8),node(18)}
local attached=coroutine.create(function() r.Nav:_accept(incoming,18,"test refresh",r.Nav.Generation) end)
repeat r.Nav.SliceOps=0; r.Nav.SliceStart=r.Now; local ok,err=coroutine.resume(attached); assert(ok,err) until coroutine.status(attached)=="dead"
eq(r.ZeroMoves or 0,beforeZeros,"Accepting a refreshed path never pulses Humanoid:Move(0)")
r.Now=.6; r:render(); eq(r.Direction.X>0,true,"Attach refreshed route ahead even after moving less than the old five-stud threshold")
local acceptedRoute=r.Nav.Route
r.Nav.EngineBusy=true; r.Nav.EngineGeneration=r.Nav.Generation; r.Now=50; r:step()
eq(r.Nav.Route,acceptedRoute,"A lingering alternative computation cannot time out an accepted valid route")
r.Nav.EngineBusy=false; r.Nav:Destroy()

r=rig(); r.World.Parts=parts; r.Root.Position=V.new(3,3,16); r.EnemyRoot.Position=V.new(32,7,0)
r:update()
-- Use a previously proved segment on the sloping plank to isolate route-retention behavior.
local g=geometry(r.World)
local start=g:project(V.new(3,0,16),1,3); local goal=g:project(V.new(19,4,16),1,3)
local safe,proofs=g:segment(start.Position,goal.Position); assert(safe)
goal.Supports=proofs; goal.Narrow=true
r.Nav.Route={start,goal}; r.Nav.Index=2; r.Nav.Job=nil; r.Nav.PlanTarget=r.EnemyRoot.Position
r.Nav.RefreshAllowed=false; r.Nav.Direction=V.new(1,0,0)
local retained=r.Nav.Route; local plans=r.Nav.Plans
for i=1,12 do
    r.Now=i; r.EnemyRoot.Position=V.new(32+i,7,0); r:update()
    eq(r.Nav.Route,retained,"Moving opponent cannot replace a still-valid bridge crossing")
end
eq(r.Nav.Plans,plans,"No repeated full path searches on an unchanged plank")
local alternative=coroutine.create(function() r.Nav:_accept({start,goal},1,"late alternative",r.Nav.Generation) end)
local ok,err=coroutine.resume(alternative); assert(ok,err)
eq(r.Nav.Route,retained,"Late alternative planner cannot reset the chosen crossing")
local originalSize=bridges[2].Size
bridges[2].Size=V.new(2,1,2); r.Now=13; r:render()
eq(r.Nav.Route,nil,"Changed board size invalidates its cached proof")
bridges[2].Size=originalSize
r.Nav:Destroy()

-- Combat integration: turn without translation, throttle, recover on checked ground and correlated confirmations.
local Adapter=dofile("SlapBattles.lua")
local function battle()
    local b=rig(); b.EnemyRoot.Position=V.new(4,3,0); b:update()
    b.Adapter=Adapter.new({Player=b.Player})
    b.Combat=C.new({Options=config.Attack,Clock=function() return b.Now end,Workspace=b.World,
        Player=b.Player,Arena=config.Arena,Adapter=b.Adapter,Knowledge=dofile("GloveKnowledge.lua")})
    b.Observations={Target={Distance=4,LineOfSight=true,Invulnerable=false}}
    function b:prepare() self.Combat:update(self.Snapshot,{Action="slap"},self.Player.Character,self.Nav,self.Observations) end
    return b
end
r=battle(); r.Root.CFrame=CFrame.lookAt(r.Root.Position,r.Root.Position+V.new(-1,0,0))
local originalPosition=r.Root.Position
r:prepare(); eq(r.Combat.Attempts,0,"Never attack while facing away")
for _=1,8 do r.Now=r.Now+1/60; r.Combat:step(1/60) end
eq(r.Combat.Attempts,0,"Wait for sufficient facing angle")
for _=1,24 do r.Now=r.Now+1/60; r.Combat:step(1/60) end
eq(r.Combat.Attempts,1,"Attack once after turning toward the target")
eq((r.Root.CFrame.Position-originalPosition).Magnitude<.00001,true,"Facing never translates the root")
eq(r.Root.CFrame.LookVector:Dot(V.new(1,0,0))>=math.cos(config.Attack.FacingTolerance),true)
eq(r.Humanoid.AutoRotate,false,"Own facing only while in combat")
local intent=r.Combat:getMovementIntent(r.Snapshot,r.Nav)
eq(intent.Stance,"recover"); eq(intent.DesiredDistance>config.Attack.ConservativeRange,true,"Recover at a safer standoff distance")
local oldNarrow=r.Nav._narrowCorridor; r.Nav._narrowCorridor=function() return true end
local narrowIntent=r.Combat:getMovementIntent(r.Snapshot,r.Nav)
eq(narrowIntent.DesiredDistance<config.Attack.ConservativeRange,true,"Do not demand a backward step on a narrow crossing")
r.Nav._narrowCorridor=oldNarrow
local deadline=r.Combat.NextAt
r.Combat:stop(); eq(r.Humanoid.AutoRotate,true,"Stop restores the previous AutoRotate value")
r:prepare(); eq(r.Combat.NextAt,deadline,"Stop/Start cannot reset an outstanding cooldown")
eq(r.Combat.Attempts,1)
r.Now=2; r.Tool.Enabled=false; r.Combat:step(.1); eq(r.Combat.Attempts,1,"Tool.Enabled gates real readiness")
r.Tool.Enabled=true; r.EnemyRoot.Position=V.new(10,3,0); r.Combat:step(.1)
eq(r.Combat.Attempts,1,"Execution rereads the live range instead of stale observation distance")
r.EnemyRoot.Position=V.new(4,3,0); r.World.VisibilityWall=true; r.Combat:step(.1)
eq(r.Combat.Attempts,1,"Execution rereads live line of sight")
r.World.VisibilityWall=false; r.Humanoid.PlatformStand=true; r.Combat:step(.1)
eq(r.Combat.Attempts,1,"Ragdoll blocks attacks and facing")
r.Humanoid.PlatformStand=false; r.Combat:Destroy(); r.Adapter:Destroy(); r.Nav:Destroy()

r=battle(); r:prepare(); eq(r.Combat.Attempts,1)
r.Nav.Combat=r.Combat; r.Now=.2; r:update()
for _=1,100 do r:step(); if r.Nav.Route then break end end
r:render(); eq(r.Direction.X<0,true,"Post-swing navigation finds a supported short retreat")
r.Root.Position=V.new(-1.7,3,0); r.Now=2; r:update()
local recoveryRoute=r.Nav.Route
for _=1,100 do r:step(); r:render(); if r.Nav.Route and r.Nav.Route~=recoveryRoute then break end end
r:render(); eq(r.Direction.X>0,true,"Resume pursuit after cooldown ends")
r.Combat:Destroy(); r.Adapter:Destroy(); r.Nav:Destroy()

r=battle(); r:prepare(); r.World.Parts=parts; r.Root.Position=V.new(10,4.75,16)
r.Nav.Route=nil -- Holding attack position has already released the walking route.
local bridgeIntent=r.Combat:getMovementIntent(r.Snapshot,r.Nav)
eq(bridgeIntent.Narrow,true,"Detect narrow footing even after clearing the route to hold attack position")
eq(bridgeIntent.DesiredDistance<config.Attack.ConservativeRange,true,"Recovery cannot demand a blind retreat off a board")
r.Combat:Destroy(); r.Adapter:Destroy(); r.Nav:Destroy()
r=battle(); r.Tool.Activate=function() error("tool rejected") end
r:prepare(); eq(r.Combat.Attempts,1,"An activation request is an attempt even if the Tool throws")
eq(r.Combat.ActivationErrors,1,"Activation exceptions have a separate counter")
eq(r.Combat:snapshot().PendingAttacks,0,"Failed activation cannot await a hit acknowledgement")
r.Combat:Destroy(); r.Adapter:Destroy(); r.Nav:Destroy()
r=battle(); r.Humanoid.AutoRotate=false; r:prepare(); r.Combat:stop()
eq(r.Humanoid.AutoRotate,false,"Restore an originally disabled AutoRotate without enabling it")
r.Combat:Destroy(); r.Adapter:Destroy(); r.Nav:Destroy()

local function feed()
    local f={Connections={}}
    function f:Connect(cb)
        local c={Connected=true,Callback=cb}; function c:Disconnect() self.Connected=false end
        table.insert(self.Connections,c); return c
    end
    function f:Fire(payload) for _,c in ipairs(self.Connections) do if c.Connected then c.Callback(payload) end end end
    return f
end
r=battle(); r:prepare()
eq(r.Combat:snapshot().ConfirmedHits,nil,"No fabricated confirmations without a game feed")
local events=feed()
r.Adapter:bindHitFeed(events,function(p) return p end,function(p) r.Combat:confirm(p) end)
eq(r.Combat:snapshot().ConfirmedHits,0,"A bound feed enables a separate confirmed counter")
local id=r.Combat.Sequence
local function ack(attack,event,target,attacker) return {AttackId=attack,EventId=event,TargetUserId=target or 2,AttackerUserId=attacker or 1} end
events:Fire(ack(id,"wrong attacker",2,3)); events:Fire(ack(id,"wrong target",3)); events:Fire(ack(999,"unknown attempt"))
eq(r.Combat.ConfirmedHits,0,"Reject confirmations for other attackers, targets and unknown attempts")
events:Fire(ack(id,"hit-1")); eq(r.Combat.ConfirmedHits,1,"Count a correlated confirmation once")
events:Fire(ack(id,"hit-1")); eq(r.Combat.ConfirmedHits,1,"Deduplicate repeated server event delivery")
r.Now=2; r.Combat:step(.1); local nextId=r.Combat.Sequence
events:Fire(ack(nextId,"hit-1")); eq(r.Combat.ConfirmedHits,1,"A replayed event ID cannot confirm a different swing")
r.Now=5; events:Fire(ack(nextId,"too-late")); eq(r.Combat.ConfirmedHits,1,"Expired attempts cannot be confirmed")
eq(r.Combat.Unconfirmed>0,true,"Expiry is tracked as unconfirmed, not as a proven miss")
r.Adapter:bindHitFeed(feed(),function() error("decoder failure") end,function(p) r.Combat:confirm(p) end)
eq(events.Connections[1].Connected,false,"Replacing an adapter disconnects its old signal")
r.Combat:stop(); events:Fire(ack(nextId,"after-stop")); eq(r.Combat.ConfirmedHits,1,"Paused session ignores late acknowledgements")
r.Combat:Destroy(); r.Adapter:Destroy(); eq(r.Adapter.HitFeedAvailable,false,"Cleanup clears hit-feed availability")
r.Nav:Destroy()

-- Preview uses a bounded object pool, floor projection, animation, immediate toggle and cleanup.
saved.Instance,saved.Color3=Instance,Color3
local objects={}
Instance={new=function(class)
    local object={ClassName=class}
    function object:Destroy() self.Destroyed=true end
    table.insert(objects,object); return object
end}
Color3={fromRGB=function(...) return {...} end}; Enum.Material.Neon="neon"
CFrame.lookAt=function(p,_,up) return frame(p,nil,up) end
local heartbeat={}
function heartbeat:Connect(cb)
    self.Callback=cb
    local connection={Connected=true}
    function connection:Disconnect() self.Connected=false end
    self.Connection=connection; return connection
end
local previewWorld=collisionWorld({part(V.new(0,-.5,0),V.new(200,1,100))})
local preview=dofile("PathPreview.lua").new({Workspace=previewWorld,RunService={Heartbeat=heartbeat},
    Players={GetPlayers=function() return {} end},Options=config.PathPreview})
eq(#preview.Pool,config.PathPreview.MaxSteps,"Fixed-size footprint pool")
preview:setEnabled(true); preview:update({V.new(-10,0,0),V.new(10,0,0)})
eq(preview.Pool[1].Visible,true,"Show footprints on current route")
heartbeat.Callback(.1)
eq(preview.Pool[1].Part.Transparency<1,true,"Animate footprint appearance")
eq(preview.Pool[1].Part.CanQuery,false,"Footprints never contaminate pathfinding queries")
eq(preview.Pool[1].Part.CanCollide,false)
eq(math.abs(preview.Pool[1].Point.Y)<.001,true,"Footprints project onto floor")
local before=#objects
for _=1,30 do preview:setEnabled(false); preview:setEnabled(true); preview:update({V.new(-10,0,0),V.new(90,0,0)}) end
eq(#objects,before,"Repeated route updates/toggles do not allocate more instances")
preview:setEnabled(false)
eq(preview.Pool[1].Part.Transparency,1,"Toggle hides footsteps immediately")
preview:setEnabled(true); previewWorld.Parts[1].Parent=nil
preview:update({V.new(-10,0,0),V.new(10,0,0)})
eq(preview.Pool[1].Visible,false,"Do not display supported-looking steps over a missing floor")
preview:Destroy(); eq(heartbeat.Connection.Connected,false,"Preview animation disconnects on close")
eq(preview.Folder.Destroyed,true)
Instance,Color3=saved.Instance,saved.Color3

Vector3,CFrame,Enum,RaycastParams,OverlapParams=saved.Vector3,saved.CFrame,saved.Enum,saved.RaycastParams,saved.OverlapParams
print("PASS: "..checks.." surface graph, pursuit and activation checks; bridge graph "..info.Nodes.." nodes / "..slices.." slices")
return checks
