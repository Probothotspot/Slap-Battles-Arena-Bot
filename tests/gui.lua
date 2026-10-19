-- Execute the real GUI and Main against a small event-driven Roblox model.
local saved={Instance=Instance,Enum=Enum,UDim2=UDim2,UDim=UDim,Color3=Color3,
    ColorSequence=ColorSequence,ColorSequenceKeypoint=ColorSequenceKeypoint,
    TweenInfo=TweenInfo,game=game,typeof=typeof,warn=warn,session=_G.SlapBattlesArenaBot}
local signals,tweens={},{}
local viewport={X=1000,Y=850}
local function signal()
    local s={listeners={}}
    function s:Connect(callback)
        local c={kind="RBXScriptConnection",Connected=true,callback=callback}
        function c:Disconnect() self.Connected=false end
        table.insert(self.listeners,c); return c
    end
    function s:Fire(...)
        local copy={}; for _,c in ipairs(self.listeners) do table.insert(copy,c) end
        for _,c in ipairs(copy) do if c.Connected then c.callback(...) end end
    end
    table.insert(signals,s); return s
end
local function aliveConnections()
    local n=0
    for _,s in ipairs(signals) do for _,c in ipairs(s.listeners) do if c.Connected then n=n+1 end end end
    return n
end
UDim2={new=function(xs,xo,ys,yo) return {X={Scale=xs,Offset=xo},Y={Scale=ys,Offset=yo}} end}
function UDim2.fromOffset(x,y) return UDim2.new(0,x,0,y) end
function UDim2.fromScale(x,y) return UDim2.new(x,0,y,0) end
UDim={new=function(s,o) return {Scale=s,Offset=o} end}
Color3={fromRGB=function(r,g,b) return {r,g,b} end}
ColorSequence={new=function(v) return v end}
ColorSequenceKeypoint={new=function(t,c) return {t,c} end}
TweenInfo={new=function(...) return {...} end}
Enum={Font={Gotham="Gotham",GothamBold="GothamBold"},TextXAlignment={Left="Left"},
    TextYAlignment={Center="Center",Top="Top"},ZIndexBehavior={Sibling="Sibling"},
    AutomaticSize={Y="Y"},ScrollingDirection={Y="Y"},SortOrder={LayoutOrder="LayoutOrder"},
    EasingStyle={Linear="Linear",Quad="Quad"},EasingDirection={InOut="InOut",Out="Out"},
    UserInputType={MouseButton1="MouseButton1",Touch="Touch",MouseMovement="MouseMovement"}}
local methods,mt={},{}
Instance={new=function(class)
    return setmetatable({_class=class,_children={},_signals={},_properties={Name=class,Visible=true,ZIndex=1}},mt)
end}
mt.__index=function(self,k)
    if methods[k] then return methods[k] end
    if k=="AbsoluteSize" then
        if self._class=="ScreenGui" or self._class=="PlayerGui" then return viewport end
        local parent=self._properties.Parent
        local area=parent and parent.AbsoluteSize or {X=1000,Y=850}
        local size=self._properties.Size
        return size and {X=area.X*size.X.Scale+size.X.Offset,Y=area.Y*size.Y.Scale+size.Y.Offset} or area
    end
    if k=="Activated" or k=="InputBegan" or k=="InputChanged" or k=="InputEnded"
        or k=="WindowFocusReleased" or k=="Destroying" or k=="ChildAdded"
        or k=="CharacterAdded" or k=="Died" then
        if not self._signals[k] then self._signals[k]=signal() end
        return self._signals[k]
    end
    return self._properties[k]
end
mt.__newindex=function(self,k,v)
    if k=="Parent" then
        local old=self._properties.Parent
        if old then for i,c in ipairs(old._children) do if c==self then table.remove(old._children,i); break end end end
        if v then table.insert(v._children,self) end
    end
    self._properties[k]=v
    if self._signals[k] then self._signals[k]:Fire() end
end
function methods:GetChildren() local r={}; for _,c in ipairs(self._children) do table.insert(r,c) end; return r end
function methods:IsA(class)
    return self._class==class or (class=="BasePart" and self._class=="Part")
end
function methods:FindFirstChild(name,recursive)
    for _,c in ipairs(self._children) do
        if c.Name==name then return c end
        if recursive then local found=c:FindFirstChild(name,true); if found then return found end end
    end
end
function methods:FindFirstChildOfClass(class)
    for _,c in ipairs(self._children) do if c:IsA(class) then return c end end
end
function methods:WaitForChild(name) return assert(self:FindFirstChild(name),name) end
function methods:GetPropertyChangedSignal(name)
    self._signals[name]=self._signals[name] or signal(); return self._signals[name]
end
function methods:Destroy()
    if self._properties.Destroyed then return end
    self._properties.Destroyed=true
    self.Destroying:Fire()
    for _,child in ipairs(self:GetChildren()) do child:Destroy() end
    self.Parent=nil
end
typeof=function(object) return type(object)=="table" and (object.kind or (object._class and "Instance")) or type(object) end
warn=function() end
local player=Instance.new("Player")
local playerGui=Instance.new("PlayerGui"); playerGui.Parent=player
local character=Instance.new("Model"); player.Character=character
local humanoid=Instance.new("Humanoid"); humanoid.Health=100; humanoid.Parent=character
local root=Instance.new("Part"); root.Name="HumanoidRootPart"; root.Position={Y=350}; root.Parent=character
local backpack=Instance.new("Backpack"); backpack.Parent=player
local board=Instance.new("Folder"); board.Name="leaderstats"; board.Parent=player
local slaps=Instance.new("IntValue"); slaps.Name="Slaps"; slaps.Value=100; slaps.Parent=board
local input=Instance.new("UserInputService")
local heartbeat=signal()
local services={Players={LocalPlayer=player},UserInputService=input,RunService={Heartbeat=heartbeat},TweenService={}}
function services.TweenService:Create(object,_,goals)
    local tween={Cancelled=false}
    function tween:Play() for k,v in pairs(goals) do object[k]=v end end
    function tween:Cancel() self.Cancelled=true end
    table.insert(tweens,tween); return tween
end
game={GetService=function(_,name) return assert(services[name],name) end}
local nav
local Nav={Name="Navigation",Ready=true,new=function()
    nav={Updates=0,Stops=0,TotalAttempts=0,TotalFailures=0,Phase="waiting",Message="Ожидание"}
    function nav:update()
        self.Updates=self.Updates+1
        if self.Phase=="waiting" then self.TotalAttempts=self.TotalAttempts+1 end
        self.Phase="approach"; self.Message="Иду к красному порталу"
    end
    function nav:stop(message) self.Stops=self.Stops+1; self.Phase="waiting"; self.Message=message end
    function nav:getStatus() return self end
    function nav:getRoute() return {} end
    function nav:Destroy() self.Destroyed=true; self:stop("closed") end
    return nav
end}
local modules={}
local function loadModule(path)
    if path=="Navigation.lua" then return Nav end
    if path=="ArenaNavigation.lua" then return {new=function() return {
        Running=false,update=function() end,step=function() end,stop=function() end,Destroy=function() end,
        getRoute=function() return {} end,getStatus=function() return {} end} end} end
    if path=="PathPreview.lua" then return {new=function() return {
        setEnabled=function() end,update=function() end,Destroy=function() end} end} end
    modules[path]=modules[path] or dofile(path); return modules[path]
end
_G.SlapBattlesArenaBot=nil
local app=loadModule("main.lua").start(loadModule,dofile("manifest.lua"),{Silent=true,Destroy=function() end})
local checks=0
local function eq(a,b,message)
    checks=checks+1; assert(a==b,(message or "Mismatch")..": "..tostring(a).." ~= "..tostring(b))
end
local function find(name) return assert(app.Gui:FindFirstChild(name,true),"Missing GUI element: "..name) end
local function click(name) find(name).Activated:Fire() end
eq(app.Running,false,"Start paused")
eq(nav.Updates,0,"No movement before Start")
eq(find("RunLabel").Text,"Старт бота")
eq(find("Overview").Visible,true)
eq(find("RunToggle").Text,"","Gradient is on the background, not on the caption")
eq(find("RunLabel").ZIndex>find("RunToggle").ZIndex,true,"Caption is above gradient")
click("ShowPath"); eq(app.PathVisible,true); eq(find("ShowPath").Text,"Показать путь: вкл")
click("ShowPath"); eq(app.PathVisible,false)
click("RunToggle"); eq(app.Running,true)
eq(nav.Updates,1)
eq(find("RunLabel").Text,"Остановить бота")
slaps.Value=103; heartbeat:Fire(.2)
eq(app.Stats.SlapsEarned,3,"Real counter growth observed")
local updates=nav.Updates
click("Collapse"); eq(find("Body").Visible,false,"Collapse really hides content")
eq(find("BotWindow").Size.Y.Offset,60,"Collapse really shrinks window")
eq(find("Collapse").Text,"+")
eq(app.Running,true,"Collapse does not stop bot")
click("Collapse"); eq(find("Body").Visible,true)
eq(find("BotWindow").Size.Y.Offset,590)
eq(find("Collapse").Text,"−")
click("StatisticsTab"); eq(find("Statistics").Visible,true)
eq(find("Overview").Visible,false)
click("JournalTab"); eq(find("Journal").Visible,true)
eq(find("Statistics").Visible,false)
viewport={X=320,Y=400}
find("SafeArea"):GetPropertyChangedSignal("AbsoluteSize"):Fire()
eq(find("UIScale").Scale<.7,true,"Scale down for phone viewport")
eq(find("UIScale").Scale>0,true)
eq(find("BotWindow").Position.X.Offset>=0,true,"Window stays on-screen")
click("RunToggle"); eq(app.Running,false)
eq(find("RunLabel").Text,"Старт бота")
heartbeat:Fire(.2); eq(nav.Updates,updates,"Heartbeat cannot resume paused bot")
slaps.Value=110; eq(app.Stats.SlapsEarned,3,"Paused earnings excluded")
click("RunToggle"); slaps.Value=112; eq(app.Stats.SlapsEarned,5)
humanoid.Health=0; humanoid.Died:Fire(); heartbeat:Fire(.2)
eq(app.Stats.Deaths,1,"Died event and polling never double count")
local connectionCount=aliveConnections()
for i=1,12 do click("RunToggle"); click("RunToggle") end
eq(aliveConnections(),connectionCount,"Repeated Start/Stop never leaks event connections")
local beforeTweenCount=#tweens
for i=1,8 do heartbeat:Fire(.2) end
eq(#tweens,beforeTweenCount,"Updates do not create gradient tweens")
click("Close")
eq(app.Destroyed,true,"X ends session")
eq(nav.Destroyed,true,"X destroys navigation")
eq(app.Running,false)
eq(aliveConnections(),0,"All connections cleaned up")
for _,tween in ipairs(tweens) do eq(tween.Cancelled,true,"All animation resources cancelled") end
Instance,Enum,UDim2,UDim,Color3=saved.Instance,saved.Enum,saved.UDim2,saved.UDim,saved.Color3
ColorSequence,ColorSequenceKeypoint,TweenInfo=saved.ColorSequence,saved.ColorSequenceKeypoint,saved.TweenInfo
game,typeof,warn=saved.game,saved.typeof,saved.warn
_G.SlapBattlesArenaBot=saved.session
print("PASS: "..checks.." GUI and Start/Stop checks")
return checks
