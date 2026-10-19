-- Cooperative surface graph. Bounds are only sampling hints: every node/edge is ray-tested.
local S = { Name = "SurfaceRoutes", Ready = true }
local function flat(v) return Vector3.new(v.X,0,v.Z) end
local function dist(a,b) return (a-b).Magnitude end
local function push(heap,item)
    local i=#heap+1
    while i>1 do local p=math.floor(i/2); if heap[p].f<=item.f then break end; heap[i]=heap[p]; i=p end
    heap[i]=item
end
local function pop(heap)
    local first,last=heap[1],table.remove(heap)
    if #heap>0 then
        local i=1
        while i*2<=#heap do
            local j=i*2; if j<#heap and heap[j+1].f<heap[j].f then j=j+1 end
            if last.f<=heap[j].f then break end; heap[i]=heap[j]; i=j
        end
        heap[i]=last
    end
    return first
end
-- Dijkstra/A* with admissible Euclidean heuristic, lazy validated edges, multiple goals.
function S.search(nodes,start,goals,neighbors,edge,checkpoint,maxExpanded)
    local goalSet={}; for _,id in ipairs(goals) do goalSet[id]=true end
    if #goals==0 then return nil end
    local function h(id)
        local n=math.huge
        for _,g in ipairs(goals) do n=math.min(n,dist(nodes[id].Position,nodes[g].Position)) end
        return n
    end
    local heap,gscore,parent,closed={}, {[start]=0}, {}, {}
    push(heap,{id=start,f=h(start),g=0})
    local expanded=0
    while #heap>0 and expanded<maxExpanded do
        checkpoint()
        local current=pop(heap); local id=current.id
        if not closed[id] and current.g==gscore[id] then
            if goalSet[id] then
                local ids={id}; while parent[id] do id=parent[id]; table.insert(ids,1,id) end
                local route={}; for _,v in ipairs(ids) do table.insert(route,nodes[v]) end
                return route,current.g,expanded
            end
            closed[id]=true; expanded=expanded+1
            for _,nextId in ipairs(neighbors(id)) do
                checkpoint()
                if not closed[nextId] then
                    local cost=edge(id,nextId)
                    if cost then
                        local g=current.g+cost
                        if not gscore[nextId] or g<gscore[nextId] then
                            gscore[nextId],parent[nextId]=g,id
                            push(heap,{id=nextId,g=g,f=g+h(nextId)})
                        end
                    end
                end
            end
        end
    end
    return nil,nil,expanded
end

function S.new(context)
    local world,o,params=context.Workspace,context.Options,context.Params
    local step=context.Checkpoint or function() end
    local self={}
    function self:ray(origin,direction) step(); return world:Raycast(origin,direction,params) end
    function self:project(point,up,down)
        local hit=self:ray(point+Vector3.new(0,up or 3,0),Vector3.new(0,-(down or 8),0))
        if not hit or hit.Normal.Y<o.MinNormalY or hit.Material==Enum.Material.Water then return nil end
        return {Position=hit.Position,Part=hit.Instance,Pose=hit.Instance:IsA("BasePart") and hit.Instance.CFrame or nil,
            Size=hit.Instance:IsA("BasePart") and hit.Instance.Size or nil}
    end
    function self:segment(a,b)
        local delta=b-a; local horizontal=flat(delta).Magnitude
        if horizontal>o.MaxSegment then return false end
        if math.abs(delta.Y)>o.StepHeight+horizontal*o.MaxSlope then return false end
        local count=math.max(1,math.ceil(horizontal/o.ProbeSpacing))
        local last
        local proofs,seen={},{}
        local function remember(node)
            if node and not seen[node.Part] then
                seen[node.Part]=true
                table.insert(proofs,{Part=node.Part,Pose=node.Pose,Size=node.Size})
            end
        end
        for i=0,count do
            local point=a+delta*(i/count)
            local node=self:project(point,o.StepHeight+.25,2*o.StepHeight+.5)
            if not node or math.abs(node.Position.Y-point.Y)>o.StepHeight then return false end
            remember(node)
            if last and math.abs(node.Position.Y-last.Y)>o.StepHeight+horizontal/count*o.MaxSlope then return false end
            -- Footprint samples tolerate narrow planks but reject a centerline on a knife edge.
            local side=horizontal>.01 and Vector3.new(-delta.Z,0,delta.X).Unit*o.FootRadius or Vector3.new(o.FootRadius,0,0)
            for _,offset in ipairs({side,side*-1}) do
                local support=self:project(node.Position+offset,.75,1.5)
                if not support or math.abs(support.Position.Y-node.Position.Y)>.7 then return false end
                remember(support)
            end
            -- Volume clearance, elevated above the surface. Detect a Fort wall without knowing its name.
            if last then
                local lift=Vector3.new(0,o.BodyHeight/2+o.StepHeight,0)
                step()
                if world:Blockcast(CFrame.new(last+lift),Vector3.new(o.BodyRadius*2,o.BodyHeight,o.BodyRadius*2),
                    node.Position-last,context.BodyParams or params) then return false end
            end
            last=node.Position
        end
        return true,proofs
    end
    function self:validate(route)
        for i=2,#route do
            local ok,proofs=self:segment(route[i-1].Position,route[i].Position)
            if not ok then return false end
            route[i].Supports=proofs
        end
        return #route>1
    end
    function self:build(parts,origin,goals)
        local nodes,buckets,dedup={}, {}, {}
        local radius=o.LinkRadius
        local function key(p) return math.floor(p.X/radius)..":"..math.floor(p.Y/radius)..":"..math.floor(p.Z/radius) end
        local function add(node)
            if not node or #nodes>=o.MaxNodes then return end
            local p=node.Position
            local tag=math.floor(p.X*2)..":"..math.floor(p.Y*2)..":"..math.floor(p.Z*2)
            if dedup[tag] then return dedup[tag] end
            local id=#nodes+1; node.Id=id; nodes[id]=node; dedup[tag]=id
            local k=key(p); buckets[k]=buckets[k] or {}; table.insert(buckets[k],id)
            return id
        end
        local start=add(self:project(origin,3,10)); if not start then return nil end
        local goalIds={}; for _,g in ipairs(goals) do local id=add(g); if id then table.insert(goalIds,id) end end
        -- Narrow parts first; cap the entire graph and each broad surface separately.
        table.sort(parts,function(a,b) return math.min(a.Size.X,a.Size.Z)<math.min(b.Size.X,b.Size.Z) end)
        for _,part in ipairs(parts) do
            step()
            if #nodes>=o.MaxNodes then break end
            if part.Parent and part.CanCollide and part.CFrame.UpVector.Y>=o.MinNormalY then
                local sx,sz=math.max(0,part.Size.X/2-o.FootRadius),math.max(0,part.Size.Z/2-o.FootRadius)
                local nx,nz=math.min(o.MaxAxisSamples,math.max(1,math.ceil(sx*2/o.GridSpacing))),
                    math.min(o.MaxAxisSamples,math.max(1,math.ceil(sz*2/o.GridSpacing)))
                if part.Size.X<4 then nx,sx=0,0 end
                if part.Size.Z<4 then nz,sz=0,0 end
                for x=0,nx do for z=0,nz do
                    step()
                    local p=part.CFrame:PointToWorldSpace(Vector3.new(-sx+2*sx*x/math.max(1,nx),part.Size.Y/2,-sz+2*sz*z/math.max(1,nz)))
                    if flat(p-origin).Magnitude<=o.ScanRadius and math.abs(p.Y-origin.Y)<=o.ScanHeight then
                        local node=self:project(p,.8,1.6)
                        if node and node.Part==part and math.abs(node.Position.Y-p.Y)<.75 then
                            node.Narrow=math.min(part.Size.X,part.Size.Z)<4; add(node)
                        end
                    end
                end end
            end
        end
        local function neighbors(id)
            local p=nodes[id].Position; local bx,by,bz=math.floor(p.X/radius),math.floor(p.Y/radius),math.floor(p.Z/radius)
            local found={}
            for x=-1,1 do for y=-1,1 do for z=-1,1 do
                for _,other in ipairs(buckets[(bx+x)..":"..(by+y)..":"..(bz+z)] or {}) do
                    step()
                    if other~=id then
                        local d=dist(p,nodes[other].Position)
                        if d<=radius then table.insert(found,{id=other,d=d}) end
                    end
                end
            end end end
            table.sort(found,function(a,b) return a.d<b.d end)
            local result={}; for i=1,math.min(o.MaxNeighbors,#found) do result[i]=found[i].id end
            return result
        end
        local cache,proofCache={},{}
        local function edge(a,b)
            local k=a..":"..b
            if cache[k]==nil then
                local na,nb=nodes[a],nodes[b]
                local safe,proofs=self:segment(na.Position,nb.Position)
                cache[k]=safe and dist(na.Position,nb.Position)*(nb.Narrow and 1.12 or 1)+math.max(0,nb.Position.Y-na.Position.Y)*.2 or false
                proofCache[k]=proofs
            end
            return cache[k]
        end
        local route,cost,expanded=S.search(nodes,start,goalIds,neighbors,edge,step,o.MaxExpanded)
        if route then
            for i=2,#route do route[i].Supports=proofCache[route[i-1].Id..":"..route[i].Id] end
        end
        return route,cost,{Nodes=#nodes,Expanded=expanded}
    end
    return self
end
return S
