-- Engine-independent tests for geometry, walking, retries and async cancellation.
local previous = { Vector3 = Vector3, Enum = Enum, RaycastParams = RaycastParams }
local V, mt = {}, {}
function V.new(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, mt) end
mt.__add = function(a, b) return V.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
mt.__sub = function(a, b) return V.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
mt.__mul = function(a, n) return V.new(a.X*n, a.Y*n, a.Z*n) end
mt.__index = function(a, k)
    if k == "Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
    if k == "Unit" then return a * (1 / a.Magnitude) end
    if k == "Dot" then return function(x, b) return x.X*b.X+x.Y*b.Y+x.Z*b.Z end end
end
V.zero = V.new(0,0,0)
Vector3, RaycastParams = V, { new = function() return {} end }
Enum = { RaycastFilterType = { Exclude = "exclude" }, PathStatus = { Success = "success" },
    PathWaypointAction = { Jump = "jump" }, RenderPriority = { Input = { Value = 100 } } }
local N = dofile("Navigation.lua")
local config = dofile("config.lua")
local checks = 0
local function eq(a,b,why)
    checks=checks+1; assert(a==b,(why or "Mismatch")..": "..tostring(a).." ~= "..tostring(b))
end
local function rig()
    local r = { now = 0, queued = {}, floor = true, wall = false, binds = {}, moves = 0 }
    r.root = { Position = V.new(-1320,329.9,3.99), Parent = true,
        IsA = function(_,class) return class=="BasePart" end }
    r.humanoid = { Parent = true, Health = 100, Move = function(_,dir) r.direction=dir; r.moves=r.moves+1 end }
    r.character = { FindFirstChild = function(_,name) if name=="HumanoidRootPart" then return r.root end end,
        FindFirstChildOfClass = function(_,class) if class=="Humanoid" then return r.humanoid end end }
    r.player = { Character = r.character }
    r.portal = { Position = V.new(-1310.16,329.9,3.99), Size = V.new(.87,14.07,8.57),
        CFrame = { RightVector = V.new(1,0,0), LookVector = V.new(0,0,-1) },
        IsA = function(_,class) return class=="BasePart" end }
    local lobby = { FindFirstChild = function(_,name) if name=="Teleport1" then return r.portal end end }
    local world = { FindFirstChild = function(_,name) if name=="Lobby" then return lobby end end,
        Raycast = function(_,_,direction)
            if direction.Y < 0 then return r.floor and { Normal = V.new(0,1,0) } or nil end
            return r.wall and {} or nil
        end }
    local run = { BindToRenderStep = function(_,name,_,callback) r.binds[name] = callback end,
        UnbindFromRenderStep = function(_,name) r.binds[name] = nil end }
    local path = { Status = "success", ComputeAsync = function() end,
        GetWaypoints = function() return r.pathPoints or { { Position = r.nav.Approach } } end,
        Blocked = { Connect = function(_,callback)
            r.blocked=callback
            return { Disconnect=function() r.blocked=nil end }
        end } }
    local options = {}
    for k,v in pairs(config.Portal) do options[k]=v end
    r.options=options
    r.nav=N.new({ Player=r.player, Workspace=world, RunService=run,
        PathfindingService={CreatePath=function() return path end}, Options=options,
        Arena=config.Arena, Spawn=function(callback) table.insert(r.queued,callback) end,
        Clock=function() return r.now end })
    function r:update(now,state)
        self.now=now
        local y=self.root.Position.Y
        self.nav:update({ Alive=self.humanoid.Health>0,
            ArenaState=state or (y>=300 and y<=400 and "lobby" or "arena") },now)
    end
    function r:render()
        local callback=self.binds.ArenaBotLobbyPortal
        if callback then callback() end
    end
    return r
end

local r=rig()
local a,b=N.portalPoints(r.portal,r.root.Position,3)
eq(a.X<r.portal.Position.X,true,"Approach from current side")
eq(b.X>r.portal.Position.X,true,"Goal is beyond portal")
eq(a.Y,r.root.Position.Y,"Preserve character height")
local a2,b2=N.portalPoints(r.portal,V.new(-1300,329.9,3.99),3)
eq(a2.X>r.portal.Position.X,true,"Opposite side approach")
eq(b2.X<r.portal.Position.X,true,"Opposite side crossing")
r.portal.CFrame={RightVector=V.new(0,0,1),LookVector=V.new(-1,0,0)}
local rotated=N.portalPoints(r.portal,V.new(-1310.16,329.9,20),3)
eq(rotated.Z>r.portal.Position.Z,true,"Use portal rotation")
r=rig(); r:update(0); r:render()
eq(r.nav.Phase,"approach")
eq(r.nav.Attempts,1)
eq(r.direction.X>0,true,"Walk toward portal")
eq(r.direction.Y,0,"Never teleport or force vertical motion")
r.root.Position=r.nav.Approach; r:update(.2)
eq(r.nav.Phase,"enter")
r:render(); eq(r.direction.X>0,true,"Cross portal plane")
r.root.Position=V.new(0,50,0); r:render()
eq(r.nav.Bound,false,"Stop immediately when Y becomes arena")
eq(r.direction.Magnitude,0,"No stale steering on arena")
r:update(.4); eq(r.nav.Phase,"arena")
eq(r.nav.Attempts,0)
eq(r.nav:getStatus().Message,"Арена: вход подтверждён")
r.root.Position=V.new(-1320,329.9,3.99); r:update(.6)
eq(r.nav.Phase,"approach","Restart when returned to lobby")
r.nav:Destroy(); eq(r.nav.Bound,false)
r:update(.8); eq(r.nav.Destroyed,true)

r=rig(); r:update(0); r:render(); r.humanoid.Health=0; r:render()
eq(r.nav.Bound,false,"Death stops movement")
eq(r.direction.Magnitude,0)
r:update(.2,"waiting"); eq(r.nav.Attempts,0)
local oldCharacter=r.character
r.character={FindFirstChild=oldCharacter.FindFirstChild,FindFirstChildOfClass=oldCharacter.FindFirstChildOfClass}
r.player.Character=r.character; r.humanoid.Health=100; r:update(.4)
eq(r.nav.Phase,"approach","New character can enter again")
r.nav:Destroy()

r=rig(); r.portal=nil; r:update(0)
eq(r.nav.Bound,false,"Missing portal does not move")
eq(r.nav.Message,"Ожидание Workspace.Lobby.Teleport1")
r=rig(); r.options.Enabled=false; r:update(0)
eq(r.nav.Bound,false,"Disabled navigation stays still")
r=rig(); r:update(0); r:render(); r.options.Enabled=false; r:update(.2)
eq(r.nav.Bound,false,"Disabling stops existing movement")

r=rig(); r:update(0); r:render(); r:update(3.2)
eq(r.nav.Phase,"retry","Stuck approach retries")
eq(r.nav.Bound,false)
r:update(3.3); eq(r.nav.Attempts,1,"Retry waits")
r:update(5); eq(r.nav.Attempts,2)
r:update(8.2); eq(r.nav.Phase,"retry")
r:update(10); r:update(13.2)
eq(r.nav.Phase,"cooldown","Repeated failures have bounded retries")
r:update(14); eq(r.nav.Attempts,3)
r:update(22); eq(r.nav.Attempts,1,"Retry after cooldown")
r.nav:Destroy()

r=rig(); r:update(0); r.root.Position=r.nav.Approach; r:update(.2)
r:render(); r:update(3.4)
eq(r.nav.Phase,"verify","Collidable portal: wait for actual transition")
eq(r.nav.Bound,false)
r:update(5.6); eq(r.nav.Phase,"retry","Touch without teleport is not success")
r.nav:Destroy()

r=rig(); r.floor=false; r:update(0)
eq(r.nav.Phase,"path","Unsafe direct approach requests a path")
eq(r.nav.Bound,false)
local delayed=r.queued[1]
r.nav:Destroy(); delayed()
eq(r.nav.Phase,"waiting","Late result cannot revive destroyed controller")
eq(r.nav.Bound,false)
r=rig(); r.wall=true; r:update(0); r.queued[1]()
eq(r.nav.Phase,"approach","Use computed path")
r:update(.2); r:render(); r.blocked(r.nav.Index)
eq(r.nav.Phase,"retry","Blocked path is invalidated")
eq(r.nav.Bound,false)
r=rig(); r.wall=true; r:update(0); local late=r.queued[1]
r:update(5.2); eq(r.nav.Phase,"retry","Path timeout")
late(); eq(r.nav.Phase,"retry","Timed-out result ignored")
r=rig(); r.wall=true; r:update(0); local pausedResult=r.queued[1]
r.nav:stop("paused"); pausedResult()
eq(r.nav.Phase,"waiting","Late path result cannot resume a stopped bot")
eq(r.nav.Bound,false)
r=rig(); r.wall=true; r:update(0)
r.pathPoints={{Position=r.root.Position,Action="jump"},{Position=r.nav.Approach}}
r.queued[1](); r:update(.2)
eq(r.humanoid.Jump,true,"Reached jump waypoint still triggers jump")
r.nav:Destroy()

Vector3,Enum,RaycastParams=previous.Vector3,previous.Enum,previous.RaycastParams
print("PASS: "..checks.." portal navigation checks")
return checks
