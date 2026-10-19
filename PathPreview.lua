-- A fixed pool of local-only, non-queryable footprints. Geometry stays outside route calculations.
local P={Name="PathPreview",Ready=true}
function P.new(context)
    local world=context.Workspace or game:GetService("Workspace")
    local run=context.RunService or game:GetService("RunService")
    local o=context.Options
    local players=context.Players or game:GetService("Players")
    local self={Enabled=false,Pool={},Time=0,Destroyed=false}
    local folder=Instance.new("Folder"); folder.Name="ArenaBotPathPreview"; folder.Parent=world
    self.Folder=folder
    for i=1,o.MaxSteps do
        local part=Instance.new("Part"); part.Name="Step"..i
        part.Anchored=true; part.CanCollide=false; part.CanTouch=false; part.CanQuery=false
        part.CastShadow=false; part.Material=Enum.Material.Neon; part.Color=Color3.fromRGB(184,112,255)
        part.Size=Vector3.new(.25,.035,.55); part.Transparency=1; part.Parent=folder
        self.Pool[i]={Part=part,Age=0,Visible=false}
    end
    function self:setEnabled(value)
        self.Enabled=value==true
        if not self.Enabled then for _,slot in ipairs(self.Pool) do slot.Visible=false; slot.Part.Transparency=1 end end
    end
    function self:update(points)
        if self.Destroyed then return end
        if not self.Enabled then return end
        local placements={}; local travel=0; local nextAt=o.Spacing*.5
        for i=2,#points do
            local a,b=points[i-1],points[i]; local delta=b-a; local length=delta.Magnitude
            if length>.001 then
                while nextAt<=travel+length and #placements<o.MaxSteps do
                    local t=(nextAt-travel)/length
                    table.insert(placements,{Point=a+delta*t,Forward=delta.Unit})
                    nextAt=nextAt+o.Spacing
                end
                travel=travel+length
            end
            if #placements>=o.MaxSteps then break end
        end
        local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude
        local exclude={folder}; for _,player in ipairs(players:GetPlayers()) do
            if player.Character then table.insert(exclude,player.Character) end
        end
        params.FilterDescendantsInstances=exclude; params.RespectCanCollide=true
        for i,slot in ipairs(self.Pool) do
            local p=placements[i]
            local hit=p and world:Raycast(p.Point+Vector3.new(0,2,0),Vector3.new(0,-4,0),params)
            if p and hit and hit.Normal.Y>.5 then
                p.Point,p.Normal=hit.Position,hit.Normal
                if not slot.Visible or not slot.Point or (slot.Point-p.Point).Magnitude>.8 then slot.Age=0 end
                slot.Visible,slot.Point,slot.Forward,slot.Normal=true,p.Point,p.Forward,p.Normal
            else slot.Visible=false; slot.Part.Transparency=1 end
        end
    end
    function self:Destroy()
        if self.Destroyed then return end; self.Destroyed=true
        self.Connection:Disconnect(); folder:Destroy()
    end
    self.Connection=run.Heartbeat:Connect(function(dt)
        if not self.Enabled then return end
        self.Time=self.Time+dt
        for i,slot in ipairs(self.Pool) do
            if slot.Visible then
                slot.Age=math.min(1,slot.Age+dt*5)
                local side=Vector3.new(-slot.Forward.Z,0,slot.Forward.X)
                side=side.Magnitude>.01 and side.Unit or Vector3.new(1,0,0)
                local point=slot.Point+Vector3.new(0,.08,0)+side*(i%2==0 and .1 or -.1)
                local rise=(1-slot.Age)*.35
                local p=point+Vector3.new(0,rise,0)
                local forward=slot.Forward-slot.Normal*slot.Forward:Dot(slot.Normal)
                if forward.Magnitude<.01 then forward=Vector3.new(1,0,0) end
                slot.Part.CFrame=CFrame.lookAt(p,p+forward,slot.Normal)
                slot.Part.Size=Vector3.new(.25,.035,.55)*(.6+.4*slot.Age)
                slot.Part.Transparency=1-slot.Age*(.7+.12*math.sin(self.Time*4-i*.4))
            end
        end
    end)
    return self
end
return P
