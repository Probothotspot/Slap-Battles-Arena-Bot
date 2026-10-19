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
    function cf:PointToWorldSpace(p) return self.Position+self.RightVector*p.X+self.UpVector*p.Y+self.BackVector*p.Z end
    function cf:PointToObjectSpace(p) local d=p-self.Position; return V.new(d:Dot(self.RightVector),d:Dot(self.UpVector),d:Dot(self.BackVector)) end
    return cf
end
CFrame={new=function(p) return frame(p) end}
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
        local h={Parent=true,Health=100,Move=function(_,d) r.Direction=d; r.Moves=r.Moves+1 end,EquipTool=function() end}
        local tool={Name="Default",Enabled=true,Activate=function() r.Activations=(r.Activations or 0)+1 end,Deactivate=function() end}
        local char={}
        function char:FindFirstChild(n) if n=="HumanoidRootPart" then return root end end
        function char:FindFirstChildOfClass(n) if n=="Humanoid" then return h elseif n=="Tool" then return tool end end
        tool.Parent=char
        return {Name=name,Character=char},root,h,tool
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
eq(r.Nav.Job~=nil,true,"Moving target queues an endpoint refresh without cancelling the usable route")
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
local combat=C.new({Options=config.Attack,Clock=function() return r.Now end})
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
