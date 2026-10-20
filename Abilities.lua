-- Detect locally advertised abilities and send a normal E/button input. No
-- RemoteEvent discovery, guessed remote arguments or claimed server successes.
local M={Name="Abilities",Ready=true}
local function attr(item,key)
    if item and item.GetAttribute then return item:GetAttribute(key) end
end
local function visible(item)
    local p=item
    while p do
        if p:IsA("GuiObject") and not p.Visible then return false end
        if p:IsA("ScreenGui") and not p.Enabled then return false end
        p=p.Parent
    end
    return true
end
function M.new(context)
    local o,player=context.Options,context.Player
    local world=context.Workspace
    local clock=context.Clock or os.clock
    local self={Attempts=0,Errors=0,Bindings={},Deadlines={},Message="Способность: ожидание",NextScan=0}
    function self:_release()
        if self.Held and self.Input then
            local held=self.Held; self.Held=nil
            local ok=pcall(function()
                if held.Button then self.Input:SendMouseButtonEvent(held.X,held.Y,0,false,game,0)
                else self.Input:SendKeyEvent(false,held.Key,false,game) end
            end)
            if not ok then self.Message="Не удалось отпустить ввод способности"; self.Errors=self.Errors+1 end
        end
    end
    function self:stop() self:_release(); self.Context=nil; self.Message="Способности остановлены" end
    function self:bind(name,spec)
        assert(type(name)=="string" and type(spec)=="table" and type(spec.Activate)=="function"
            and type(spec.Ready)=="function" and type(spec.Cooldown)=="number" and spec.Cooldown>=.5
            and spec.Cooldown<math.huge,"Ability binding needs Activate, Ready and a finite Cooldown >= 0.5")
        self.Bindings[name]=spec
    end
    function self:_detect(tool)
        if self.Tool==tool and self.ToolName==tool.Name and clock()<self.NextScan then return self.Spec end
        self.Tool,self.ToolName=tool,tool.Name; self.NextScan=clock()+(o.ScanInterval or 1)
        local bound=self.Bindings[tool.Name]
        if bound then self.Spec=bound; return bound end
        if attr(tool,"HasAbility")==false then self.Spec=nil; return nil end
        local button,ui
        local gui=player:FindFirstChildOfClass("PlayerGui")
        if gui and gui.GetDescendants then
            for i,item in ipairs(gui:GetDescendants()) do
                if i>(o.MaxGuiScan or 600) then break end
                local name=string.lower(item.Name)
                if (name:find("ability",1,true) or name=="e") and item:IsA("GuiObject") and visible(item) then
                    local parent=item; local abilityContainer=false
                    while parent and parent~=gui do
                        if parent.Name=="SlapBattlesArenaBotGUI" then abilityContainer=false; break end
                        if string.lower(parent.Name):find("ability",1,true) then abilityContainer=true end
                        parent=parent.Parent
                    end
                    if abilityContainer then
                        ui=item
                        if item:IsA("GuiButton") then button=item; break end
                    end
                end
            end
        end
        local advertised=attr(tool,"HasAbility")==true or type(attr(tool,"AbilityName"))=="string" or ui~=nil
        if not advertised then self.Spec=nil; return nil end
        local info=context.Knowledge.get(tool.Name)
        local cooldown=attr(tool,"AbilityCooldown")
        if type(cooldown)~="number" or cooldown~=cooldown or cooldown<.5 or cooldown>300 then cooldown=o.FallbackInterval or 3 end
        self.Spec={Role=info.AbilityRole or "utility",Cooldown=cooldown,Button=button,UI=ui,Input=true,
            Source=ui and "интерфейс игры" or "атрибуты инструмента"}
        return self.Spec
    end
    function self:_input(spec)
        if self.Unsupported then return false end
        if not self.Input then
            local ok,value=pcall(function() return context.Input or game:GetService("VirtualInputManager") end)
            if not ok then self.Unsupported=true; return false end
            self.Input=value
        end
        local ok=pcall(function()
            if spec.Button then
                if not visible(spec.Button) or not spec.Button.Active then error("ability button unavailable") end
                local pos,size=spec.Button.AbsolutePosition,spec.Button.AbsoluteSize
                local x,y=pos.X+size.X/2,pos.Y+size.Y/2
                self.Held={Button=true,X=x,Y=y}
                self.Input:SendMouseButtonEvent(x,y,0,true,game,0)
            else
                local key=Enum.KeyCode.E
                self.Held={Key=key}; self.Input:SendKeyEvent(true,key,false,game)
            end
        end)
        if not ok then self:_release(); self.Unsupported=true; return false end
        self.ReleaseAt=clock()+(o.PressSeconds or .05)
        return true
    end
    function self:update(snapshot,pursuit,observations)
        self.Context={Snapshot=snapshot,Pursuit=pursuit,Observations=observations or {}}
    end
    function self:step()
        if self.Held and clock()>=(self.ReleaseAt or 0) then self:_release() end
        local c=self.Context
        if self.Destroyed or not o.Enabled or not c then return end
        local s,p=c.Snapshot,c.Pursuit; local char=player.Character
        local h=char and char:FindFirstChildOfClass("Humanoid")
        local root=char and char:FindFirstChild("HumanoidRootPart")
        local tool=s.Tool; local target=p.Target; local tc=target and target.Character
        local tr=tc and tc:FindFirstChild("HumanoidRootPart")
        local th=tc and tc:FindFirstChildOfClass("Humanoid")
        if not s.Alive or s.ArenaState~="arena" or not p.Running or p.Character~=char or not h or h.Health<=0
            or h.Sit or h.PlatformStand or not root or not tool or tool.Parent~=char or not s.EquippedTool
            or not tr or not th or th.Health<=0 or p.TargetCharacter~=tc then self:_release(); return end
        local b=context.Arena
        if (root.Position.Y>=b.LobbyMinY and root.Position.Y<=b.LobbyMaxY)
            or (tr.Position.Y>=b.LobbyMinY and tr.Position.Y<=b.LobbyMaxY) then self:_release(); return end
        local spec=self:_detect(tool)
        self.Available=spec~=nil
        if not spec then self.Message="Способность не обнаружена"; return end
        if self.Unsupported and spec.Input then self.Message="Ввод способности недоступен в этой среде"; return end
        if self.Held then return end
        local remaining=(self.Deadlines[tool.Name] or 0)-clock()
        if remaining>0 then self.Message=string.format("Способность: ожидание %.1f с",remaining); return end
        if tool.Enabled==false or attr(tool,"AbilityReady")==false then return end
        local cd=attr(tool,"AbilityCooldownRemaining")
        if type(cd)=="number" and cd>0 then return end
        if spec.UI and not visible(spec.UI) then self.Message="Кнопка способности скрыта"; return end
        if spec.Button and not spec.Button.Active then self.Message="Кнопка способности пока не готова"; return end
        if spec.UI then
            local remaining=attr(spec.UI,"CooldownRemaining")
            if type(remaining)=="number" and remaining>0 then return end
            if spec.UI:IsA("TextButton") or spec.UI:IsA("TextLabel") then
                local timer=tostring(spec.UI.Text or ""):gsub("с","s"):gsub(",",".")
                local value=timer:match("^%s*(%d+%.?%d*)%s*[sS]?%s*$")
                if tonumber(value) and tonumber(value)>0 then self.Message="Способность: игровой таймер"; return end
            end
        end
        local obs=c.Observations; local targetObs=obs.Target or {}
        if tc:FindFirstChildOfClass("ForceField") or targetObs.Invulnerable or targetObs.CounterActive or targetObs.ReverseActive then return end
        local delta=tr.Position-root.Position
        if delta.Magnitude>(spec.Range or o.TargetRange or 24)
            or (world or game:GetService("Workspace")):Raycast(root.Position,delta,p.Params) then return end
        if spec.Role=="reposition" and obs.LandingSafe~=true then self.Message="Способность: нет проверенной точки перемещения"; return end
        if spec.Role=="recover" and (obs.Falling~=true or obs.RecoverySafe~=true) then self.Message="Восстановление сохранено до падения"; return end
        if spec.Role=="defend" then
            local toward=tr.AssemblyLinearVelocity or Vector3.zero
            if delta.Magnitude>o.ThreatDistance or toward:Dot(root.Position-tr.Position)<=0 then
                self.Message="Защита сохранена до сближения противника"; return
            end
        elseif delta.Magnitude>.1 and root.CFrame.LookVector:Dot(delta.Unit)<math.cos(math.rad(25)) then return end
        if not p:_geometry():project(root.Position,1,8) then return end
        if context.UserInput and context.UserInput:GetFocusedTextBox() then return end
        if spec.Ready then
            local ok,ready=pcall(spec.Ready,tool,target,obs)
            if not ok or ready~=true then return end
        end
        self.Deadlines[tool.Name]=clock()+spec.Cooldown
        self.Attempts=self.Attempts+1
        local ok,result
        if spec.Activate then ok,result=pcall(spec.Activate,tool,target,obs)
        else ok,result=pcall(function() return self:_input(spec) end) end
        if not ok or result==false then self.Errors=self.Errors+1; self.Message="Не удалось активировать способность"
        else self.Message="Попытка способности: "..tool.Name end
        if context.Log then context.Log(self.Message) end
    end
    function self:snapshot() return {Available=self.Available,Attempts=self.Attempts,Errors=self.Errors,Message=self.Message} end
    function self:Destroy() self:stop(); self.Destroyed=true; self.Spec=nil; self.Tool=nil end
    return self
end
return M
