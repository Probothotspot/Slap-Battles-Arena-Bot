-- One public loading unit; individual module checks stay internal.
local BASE = "https://raw.githubusercontent.com/Probothotspot/Slap-Battles-Arena-Bot/main/"
local TIMEOUT = 20
local env = _G
if type(getgenv) == "function" then
    local ok, value = pcall(getgenv)
    if ok and type(value) == "table" then env = value end
end
local KEY = "SlapBattlesArenaBotLoader"
if type(env[KEY]) == "table" and type(env[KEY].Destroy) == "function" then
    pcall(function() env[KEY]:Destroy() end)
end
local player = game:GetService("Players").LocalPlayer
assert(player, "[ArenaBot] Loader requires a client player")
local parent = player:WaitForChild("PlayerGui",10)
assert(parent, "[ArenaBot] PlayerGui is unavailable")
local report = { State="loading", Completed=0, Errors=0, Warnings=0,
    Destroyed=false, Finished=false, Hidden=false, Connections={}, Silent=true }
env[KEY] = report
local function create(class, properties, owner)
    local object = Instance.new(class)
    for key,value in pairs(properties) do object[key]=value end
    object.Parent=owner
    return object
end
local gui = create("ScreenGui",{Name="ArenaBotLoadingGUI",ResetOnSpawn=false,
    IgnoreGuiInset=true,DisplayOrder=200,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},parent)
local strip = create("Frame",{Position=UDim2.fromOffset(0,0),Size=UDim2.new(1,0,0,30),
    BackgroundColor3=Color3.fromRGB(25,22,36),BackgroundTransparency=0.08,BorderSizePixel=0},gui)
local label = create("TextLabel",{Text="loading modules 0/1",Size=UDim2.new(1,-16,1,-3),
    Position=UDim2.fromOffset(8,0),BackgroundTransparency=1,Font=Enum.Font.GothamMedium,
    TextSize=14,TextColor3=Color3.fromRGB(238,233,250),TextWrapped=false,
    TextXAlignment=Enum.TextXAlignment.Center},strip)
local fill = create("Frame",{Position=UDim2.new(0,0,1,-3),Size=UDim2.new(0,0,0,3),
    BorderSizePixel=0,BackgroundColor3=Color3.fromRGB(151,105,235)},strip)
function report:Destroy()
    if self.Destroyed then return end
    self.Destroyed=true
    for _,connection in ipairs(self.Connections) do connection:Disconnect() end
    self.Connections={}
    gui:Destroy()
    if env[KEY]==self then env[KEY]=nil end
end
local function connect(signal,callback)
    local connection=signal:Connect(callback)
    table.insert(report.Connections,connection)
end
local function fail(detail)
    if report.Destroyed then return end
    gui.Enabled=true
    report.Hidden=false
    report.State,report.Finished,report.LastError="error",true,tostring(detail)
    report.Errors=report.Errors+1
    label.Text="error"
    label.TextColor3=Color3.fromRGB(255,146,156)
    fill.Size=UDim2.new(1,0,0,3)
    fill.BackgroundColor3=Color3.fromRGB(235,80,100)
end
connect(gui.Destroying,function() report:Destroy() end)
local function awaitResult(callback)
    local done,success,result=false,false,nil
    local worker=task.spawn(function() success,result=pcall(callback); done=true end)
    local started=os.clock()
    while not done and not report.Destroyed and os.clock()-started<TIMEOUT do task.wait(0.05) end
    if not done then
        if type(task.cancel)=="function" then pcall(task.cancel,worker) end
        error(report.Destroyed and "cancelled" or "module timeout",0)
    end
    if not success then error(tostring(result),0) end
    if report.Destroyed then error("cancelled",0) end
    return result
end
local cache,loading={},{}
local function loadModule(path)
    assert(type(path)=="string" and path:match("^[%w_/%.-]+$") and not path:find("..",1,true),"invalid module path")
    if cache[path]~=nil then return cache[path] end
    assert(not loading[path],"circular module dependency: "..path)
    loading[path]=true
    local phase="download"
    local ok,value=pcall(function()
        return awaitResult(function()
            local source=game:HttpGet(BASE..path)
            assert(type(source)=="string" and #source>0,"empty response")
            phase="compile"
            local chunk,err=loadstring(source,"@ArenaBot/"..path)
            assert(chunk,err)
            phase="initialize"
            local module=chunk()
            assert(type(module)=="table","module must return a table")
            return module
        end)
    end)
    loading[path]=nil
    if not ok then error(path.." • "..phase..": "..tostring(value),0) end
    cache[path]=value
    if value.Ready==false then report.Warnings=report.Warnings+1 end
    return value
end
local function requireFunction(module,name,path)
    assert(type(module[name])=="function",path..": missing "..name)
end
local app
-- Draw the strip before starting downloads. All modules count as one loading unit.
task.wait()
local ok,err=pcall(function()
    assert(not report.Destroyed,"cancelled")
    assert(type(loadstring)=="function","loadstring unavailable")
    assert(type(task.spawn)=="function","task.spawn unavailable")
    local manifest=loadModule("manifest.lua")
    assert(manifest.schemaVersion==1 and manifest.entry=="main.lua","invalid manifest")
    assert(type(manifest.version)=="string" and type(manifest.systems)=="table","invalid manifest fields")
    local main=loadModule(manifest.entry)
    local config=loadModule("config.lua")
    local cleanup=loadModule("Cleanup.lua")
    local logger=loadModule("Logger.lua")
    local ui=loadModule("Gui.lua")
    loadModule("SlapBattles.lua")
    requireFunction(main,"start","main.lua")
    for _,name in ipairs({"new","add","Destroy"}) do requireFunction(cleanup,name,"Cleanup.lua") end
    requireFunction(logger,"new","Logger.lua")
    requireFunction(logger,"info","Logger.lua")
    requireFunction(ui,"mount","Gui.lua")
    assert(type(config.UI)=="table" and type(config.UI.Width)=="number" and config.UI.Width>=200
        and type(config.UI.Height)=="number" and config.UI.Height>=200,"invalid UI configuration")
    local seen={}
    for _,entry in ipairs(manifest.systems) do
        assert(type(entry)=="table" and type(entry.name)=="string" and not seen[entry.name],"invalid system entry")
        seen[entry.name]=true
        local module=loadModule(entry.path)
        assert(module.Name==entry.name and type(module.Ready)=="boolean",entry.path..": invalid system interface")
    end
    local previous=env.SlapBattlesArenaBot
    local started,value=pcall(function()
        return awaitResult(function()
            local result=main.start(loadModule,manifest,report)
            assert(type(result)=="table" and type(result.Destroy)=="function" and not result.Destroyed,"invalid application")
            assert(typeof(result.Gui)=="Instance" and result.Gui:IsA("ScreenGui")
                and result.Gui.Parent~=nil and result.Gui.Enabled~=false,"application GUI is not visible")
            return result
        end)
    end)
    if not started then
        local partial=env.SlapBattlesArenaBot
        if partial~=previous and type(partial)=="table" and type(partial.Destroy)=="function" then
            pcall(function() partial:Destroy() end)
        end
        error(value,0)
    end
    app=value
end)
if report.Destroyed then
    if app then app:Destroy() end
    return nil
end
if not ok then fail(err); return nil,report end
report.State,report.Completed,report.Finished="ready",1,true
label.Text="loading modules 1/1"
fill.Size=UDim2.new(1,0,0,3)
-- Only the word "error" is exposed. Details remain in the internal report.
pcall(function()
    connect(game:GetService("LogService").MessageOut,function(message,kind)
        if report.Destroyed or report.State=="error" or kind~=Enum.MessageType.MessageError then return end
        if message:find("ArenaBot/",1,true) or message:find("[ArenaBot]",1,true) then fail(message) end
    end)
end)
-- The primary GUI has been mounted; allow one frame before hiding the strip.
task.wait()
if report.Destroyed then return nil end
if report.State=="ready" then
    gui.Enabled=false
    report.Hidden=true
end
return app,report
