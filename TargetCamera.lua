-- Own orientation only, after the standard camera controller. Preserve zoom and
-- collision handling; release immediately on pause, death, lost target or cutscene.
local M={Name="TargetCamera",Ready=true}
function M.new(context)
    local world=context.Workspace
    local run=context.RunService or game:GetService("RunService")
    local player,o=context.Player,context.Options
    local self={Active=false,Message="Камера свободна"}
    local key="ArenaBotTargetCamera"
    function self:stop()
        if self.Bound then run:UnbindFromRenderStep(key); self.Bound=false end
        self.Active=false; self.Pursuit=nil; self.Message="Камера свободна"
    end
    function self:step(dt)
        local p=self.Pursuit
        local character=player.Character
        local h=character and character:FindFirstChildOfClass("Humanoid")
        local target=p and p.Target; local tc=target and target.Character
        local th=tc and tc:FindFirstChildOfClass("Humanoid")
        local tr=tc and tc:FindFirstChild("HumanoidRootPart")
        if self.Destroyed or not o.Enabled or not p or not p.Running or p.Character~=character
            or not h or h.Health<=0 or not tr or not th or th.Health<=0 or p.TargetCharacter~=tc then self:stop(); return end
        local camera=(world or game:GetService("Workspace")).CurrentCamera
        if not camera or camera.CameraType==Enum.CameraType.Scriptable then self.Active=false; return end
        local targetPosition=tr.Position+Vector3.new(0,o.AimHeight or 1,0)
        local velocity=tr.AssemblyLinearVelocity or Vector3.zero
        if velocity.Magnitude<100 then targetPosition=targetPosition+velocity*(o.PredictionSeconds or .08) end
        local pos=camera.CFrame.Position
        if (targetPosition-pos).Magnitude<.1 then return end
        local look=CFrame.lookAt(pos,targetPosition)
        local alpha=1-math.exp(-(o.Responsiveness or 12)*math.max(0,math.min(dt or 0,.1)))
        camera.CFrame=camera.CFrame:Lerp(look,alpha)
        self.Active=true; self.Message="Камера: "..target.Name
    end
    function self:update(snapshot,pursuit)
        if self.Destroyed or not o.Enabled or not snapshot.Alive or snapshot.ArenaState~="arena"
            or not pursuit.Running or not pursuit.Target then self:stop(); return end
        self.Pursuit=pursuit
        if not self.Bound then
            self.Bound=true
            run:BindToRenderStep(key,Enum.RenderPriority.Camera.Value+1,function(dt) self:step(dt) end)
        end
    end
    function self:Destroy() self:stop(); self.Destroyed=true end
    return self
end
return M
