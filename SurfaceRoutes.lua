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
        -- A solid rectangular Part has no holes. Prove an entire supported span with
        -- two endpoint casts and one body sweep instead of resampling its interior.
        -- Meshes, unions, terrain, seams and edges retain the sampled fallback.
        local first=self:project(a,o.StepHeight+.25,2*o.StepHeight+.5)
        local finish=self:project(b,o.StepHeight+.25,2*o.StepHeight+.5)
        local part=first and first.Part
        if part and finish and finish.Part==part and part:IsA("Part")
            and part.Shape==Enum.PartType.Block and part.CFrame.UpVector.Y>=o.MinNormalY then
            local function inside(node,expected)
                local p=part.CFrame:PointToObjectSpace(node.Position)
                return math.abs(node.Position.Y-expected.Y)<=o.StepHeight
                    and math.abs(p.Y-part.Size.Y/2)<.05
                    and math.abs(p.X)<=part.Size.X/2-o.FootRadius
                    and math.abs(p.Z)<=part.Size.Z/2-o.FootRadius
            end
            if inside(first,a) and inside(finish,b) then
                local lift=Vector3.new(0,o.BodyHeight/2+o.StepHeight,0)
                step()
                if not world:Blockcast(CFrame.new(first.Position+lift),Vector3.new(o.BodyRadius*2,o.BodyHeight,o.BodyRadius*2),
                    finish.Position-first.Position,context.BodyParams or params) then
                    return true,{{Part=part,Pose=part.CFrame,Size=part.Size}}
                end
                return false
            end
        end
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
        local shared=context.GraphCache
        local cached=shared and shared.Graph
        local reusable=cached and cached.Options==o and cached.Group==params.CollisionGroup
            and #cached.Parts==#parts and (context.Clock or os.clock)()-cached.Time<(o.GraphCacheSeconds or 4)
        if reusable then
            local seen={}
            for _,part in ipairs(parts) do seen[part]=true end
            for _,stamp in ipairs(cached.Parts) do
                step()
                local part=stamp.Part
                if not seen[part] or not part.Parent or part.CanCollide~=stamp.Collidable
                    or part.CFrame~=stamp.Pose or part.Size~=stamp.Size or part.CollisionGroup~=stamp.Group
                    or part.Material~=stamp.Material or part.CanQuery~=stamp.Queryable
                    or (part:IsA("Part") and part.Shape~=stamp.Shape) then reusable=false; break end
            end
        end
        if reusable then
            for _,node in ipairs(cached.Nodes) do step(); add(node) end
        else
        -- Narrow parts first; cap the entire graph and each broad surface separately.
        local ordered={}; for _,part in ipairs(parts) do ordered[#ordered+1]=part end
        table.sort(ordered,function(a,b) return math.min(a.Size.X,a.Size.Z)<math.min(b.Size.X,b.Size.Z) end)
        for _,part in ipairs(ordered) do
            step()
            if #nodes>=o.MaxNodes-#goals-1 then break end
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
                            node.Narrow=math.min(part.Size.X,part.Size.Z)<4
                            if #nodes<o.MaxNodes-#goals-1 then add(node) end
                        end
                    end
                end end
            end
        end
        end
        local staticCount=#nodes
        if shared and not reusable then
            local stamps,base={},{}
            for _,part in ipairs(parts) do
                stamps[#stamps+1]={Part=part,Pose=part.CFrame,Size=part.Size,Collidable=part.CanCollide,Group=part.CollisionGroup,
                    Material=part.Material,Queryable=part.CanQuery,Shape=part:IsA("Part") and part.Shape or nil}
            end
            for i,node in ipairs(nodes) do base[i]=node end
            cached={Nodes=base,Parts=stamps,Options=o,Group=params.CollisionGroup,Time=(context.Clock or os.clock)(),Edges={},Proofs={}}
            shared.Graph=cached
        end
        local start=add(self:project(origin,3,10)); if not start then return nil end
        local goalIds={}; for _,g in ipairs(goals) do local id=add(g); if id then table.insert(goalIds,id) end end
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
        local edgeHits,edgeChecks=0,0
        local function edge(a,b)
            local k=a..":"..b
            if cache[k]==nil then
                local persistent=cached and a<=staticCount and b<=staticCount
                if persistent and cached.Edges[k]~=nil then
                    cache[k],proofCache[k]=cached.Edges[k],cached.Proofs[k]; edgeHits=edgeHits+1
                    return cache[k]
                end
                local na,nb=nodes[a],nodes[b]
                local safe,proofs=self:segment(na.Position,nb.Position)
                edgeChecks=edgeChecks+1
                cache[k]=safe and dist(na.Position,nb.Position)*(nb.Narrow and 1.12 or 1)+math.max(0,nb.Position.Y-na.Position.Y)*.2 or false
                proofCache[k]=proofs
                if persistent then cached.Edges[k],cached.Proofs[k]=cache[k],proofs end
            end
            return cache[k]
        end
        local route,cost,expanded=S.search(nodes,start,goalIds,neighbors,edge,step,o.MaxExpanded)
        if route then
            local copy={}
            for i,node in ipairs(route) do
                local n={}; for k,v in pairs(node) do n[k]=v end
                if i>1 then n.Supports=proofCache[route[i-1].Id..":"..node.Id] end
                copy[i]=n
            end
            route=copy
        end
        return route,cost,{Nodes=#nodes,Expanded=expanded,CacheHit=reusable==true,EdgeCacheHits=edgeHits,EdgeChecks=edgeChecks,Goals=#goalIds}
    end
    return self
end
return S
