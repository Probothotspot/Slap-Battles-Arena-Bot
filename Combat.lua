-- Generic Tool activation only. No guessed remote names or glove-specific abilities.
local C={Name="Combat",Ready=true}
function C.new(context)
    local clock=context.Clock or os.clock
    local o=context.Options
    local self={Attempts=0,NextAt=0}
    function self:ready() return clock()>=self.NextAt end
    function self:stop()
        if self.Tool then pcall(function() self.Tool:Deactivate() end); self.Tool=nil end
    end
    function self:update(snapshot,plan,character,pursuit,observations)
        self:stop()
        if not o.Enabled or not pursuit.Running or snapshot.ArenaState~="arena" or not snapshot.Alive
            or not snapshot.EquippedTool or not snapshot.Tool or snapshot.Tool.Enabled==false or snapshot.Tool.Parent~=character
            or plan.Action~="slap" or not self:ready() or not observations.Target.LineOfSight
            or observations.Target.Distance>o.ConservativeRange or observations.Target.Invulnerable then return end
        local h=pursuit.Humanoid
        if not h or h.Health<=0 or h.Sit or h.PlatformStand then return end
        -- Never attack from a route whose next step is unsafe; do not rotate/teleport the character.
        if pursuit.Phase~="position" then return end
        local root=character:FindFirstChild("HumanoidRootPart")
        if not root or math.abs((root.AssemblyLinearVelocity or Vector3.zero).Y)>12 then return end
        if pursuit._geometry and not pursuit:_geometry():project(root.Position,1,8) then return end
        self.NextAt=clock()+o.Interval
        local ok=pcall(function() snapshot.Tool:Activate() end)
        if ok then self.Tool=snapshot.Tool; self.Attempts=self.Attempts+1 end
    end
    return self
end
return C
