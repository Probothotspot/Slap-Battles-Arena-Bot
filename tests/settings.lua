-- Optional APIs, corrupted files, backup recovery and persistent tactical feedback.
local Settings=dofile("Settings.lua")
local Memory=dofile("Memory.lua")
local n=0
local function eq(a,b,why) n=n+1; assert(a==b,(why or "Mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
local function clone(t)
    if type(t)~="table" then return t end
    local out={}; for k,v in pairs(t) do out[k]=clone(v) end; return out
end
-- Model the engine's JSON roundtrip with opaque strings, not executable file data.
local encoded,serial={},0
local http={}
function http:JSONEncode(data) serial=serial+1; local raw="json:"..serial; encoded[raw]=clone(data); return raw end
function http:JSONDecode(raw) return clone(assert(encoded[raw],"Malformed JSON")) end
local files,writes={},0
local g={identifyexecutor=function() return "Delta","version" end,
    readfile=function(path) return assert(files[path],"Missing") end,
    writefile=function(path,raw) files[path]=raw; writes=writes+1 end,
    isfile=function(path) return files[path]~=nil end}
local function create(platform,globals,input)
    input=input or {GetPlatform=function() return platform end,TouchEnabled=false,KeyboardEnabled=true,MouseEnabled=true}
    return Settings.new({Config=dofile("config.lua"),Globals=globals or g,Input=input,HttpService=http,UserId=17})
end
local phone=create("Enum.Platform.Android")
local pc=create("Enum.Platform.Windows")
eq(phone.Executor,"Delta"); eq(phone.Device,"Mobile"); eq(pc.Device,"PC")
eq(phone.SearchChecks,100); eq(pc.SearchChecks,400)
local config=dofile("config.lua")
local desktop=Settings.new({Config=config,Globals={},Input={GetPlatform=function() return "Windows" end,TouchEnabled=true},HttpService=http})
eq(desktop.Device,"PC","Touch laptop remains a PC")
eq(config.Pursuit.WorkPerFrame,400); eq(config.Pursuit.GoalCandidates,50); eq(config.Pursuit.MaxExpanded,2400)
eq(desktop:setChecks(2000),true); eq(config.Pursuit.GoalCandidates,64); eq(config.Pursuit.BudgetSeconds,.006)
for _,bad in ipairs({0,-1,9,2001,math.huge,0/0,1.2,"100"}) do eq(desktop:setChecks(bad),false,"Reject invalid budget") end
eq(config.Pursuit.WorkPerFrame,2000,"Invalid input never mutates active options")
local denied=create("Android",{identifyexecutor=function() error("denied") end,getexecutorname=function() return "Fallback\nName" end})
eq(denied.Executor,"Fallback Name"); eq(denied.StorageAvailable,false)
eq(denied:setChecks(120),true,"Settings still work without file APIs")
eq(denied:save(),false)
local restricted=create(nil,{}, {GetPlatform=function() error("security") end,TouchEnabled=true,KeyboardEnabled=false})
eq(restricted.Device,"Mobile","Restricted platform API uses input fallback")
phone:setChecks(128); phone:setPathVisible(true); phone:setProfile("Extended",11,.9); phone:setLearning(false)
local reloaded=create("Android")
eq(reloaded.SearchChecks,128); eq(reloaded.PathVisible,true); eq(reloaded.LearningEnabled,false)
eq(reloaded.Profiles.Extended.Range,11); eq(reloaded.Profiles.Extended.Interval,.9)
files[phone.Path]="broken"
local backup=create("Android")
eq(backup.SearchChecks,128,"Corrupt primary recovers validated backup")
eq(backup.Message,"Настройки восстановлены из резервной копии")
files[phone.Path]=http:JSONEncode({Schema=99,SearchChecks=100,Profiles={},PathVisible=false})
files[phone.BackupPath]=nil
eq(create("Android").SearchChecks,100,"Unknown schema uses defaults")
local broken={readfile=g.readfile,isfile=g.isfile,writefile=function() error("disk full") end}
local full=create("Android",broken)
eq(full:setChecks(140),true); eq(full.Dirty,true); eq(full.Message,"Ошибка сохранения: запись не подтверждена")
local lost=create("Android",{readfile=g.readfile,isfile=g.isfile,writefile=function() end})
lost:setChecks(150); eq(lost.Dirty,true,"Silent write failure is detected by readback")
files={}; writes=0
local settings=create("Android"); local now=0
local function newMemory() return Memory.new({Settings=settings,Clock=function() return now end,UserId=17}) end
local m=newMemory()
local humanoid={Health=100,MaxHealth=100}
local character={FindFirstChildOfClass=function(_,class) if class=="Humanoid" then return humanoid end end}
local other={FindFirstChildOfClass=function(_,class) if class=="Tool" then return {Name="Default"} end end}
local target={UserId=18,Character=other}
local pursuit={Character=character,Humanoid=humanoid,Target=target,Failures=0}
local snapshot={Alive=true,GloveName="Extended"}
local p=m:policy(snapshot,pursuit,false)
eq(p.Scale,1); eq(m:snapshot().Contexts,1)
local e=m.Episode
eq(m:policy(snapshot,pursuit,false),p,"Same encounter keeps its action")
m:attack(1,{TargetUserId=18,Character=character})
eq(m:hit(1),true); eq(m:hit(1),false,"Duplicate hit cannot reward twice")
eq(m.Data.Hits,1)
eq(m:confirmKill({AttackId=1,TargetUserId=18,AttackerUserId=19,EventId="k1"}),false)
eq(m:confirmKill({AttackId=1,TargetUserId=19,AttackerUserId=17,EventId="k1"}),false)
eq(m:confirmKill({AttackId=1,TargetUserId=18,AttackerUserId=17,EventId="k1"}),true)
eq(m:confirmKill({AttackId=1,TargetUserId=18,AttackerUserId=17,EventId="k1"}),false)
eq(m.Data.Kills,1); eq(m.Data.Outcomes,2)
humanoid.Health=80; m:observe(snapshot,pursuit)
eq(m.Data.Outcomes,3,"Observed health loss contributes a negative signal")
m:observe(snapshot,pursuit); eq(m.Data.Outcomes,3,"Same damage not counted twice")
humanoid.Health=100; m:observe(snapshot,pursuit); eq(m.Data.Outcomes,3,"Healing is not a reward")
humanoid.Health=0; m:death(character); m:death(character)
eq(m.Data.Deaths,1); eq(m.Data.Outcomes,4); eq(m.Episode,nil)
local savedMemory=newMemory()
eq(savedMemory.Data.Kills,1); eq(savedMemory.Data.Deaths,1); eq(savedMemory.Data.Hits,1)
humanoid.Health=100
local choice=savedMemory:policy(snapshot,pursuit,false)
eq(choice.Side,-1,"Stored tried action makes the next unused tactic eligible")
local episode=savedMemory.Episode
savedMemory:finish(); eq(savedMemory.Data.Unknown,1,"Ending without a confirmed outcome is unknown")
eq(savedMemory.Data.Contexts[episode.Key].left.N,0,"Unknown ending does not teach a fake success")
savedMemory:policy(snapshot,pursuit,false)
pursuit.Target=nil; savedMemory:observe(snapshot,pursuit)
eq(savedMemory.Data.Kills,1,"Disappearing target does not become another kill")
pursuit.Target=target
savedMemory:policy(snapshot,pursuit,false)
savedMemory:attack(2,{TargetUserId=18,Character=character}); now=11
eq(savedMemory:confirmKill({AttackId=2,TargetUserId=18,AttackerUserId=17,EventId="late"}),false,"Stale kill attribution rejected")
savedMemory:stop(); local priorWrites=writes
now=30; savedMemory:observe(snapshot,pursuit)
eq(writes,priorWrites,"Idle observation does not write files every frame")
settings:setLearning(false)
eq(savedMemory:policy(snapshot,pursuit,false).Scale,1)
eq(savedMemory.Episode,nil,"Disabled learning starts no encounters")
settings:setLearning(true)
for i=1,140 do
    snapshot.GloveName="Fixture"..i
    savedMemory:policy(snapshot,pursuit,false); savedMemory:death(character)
end
eq(savedMemory:snapshot().Contexts,128,"Context table remains bounded")
eq(#savedMemory.Data.History,30,"Event log remains bounded")
savedMemory:save(true)
eq(newMemory():snapshot().Contexts,128,"Bounded table remains reloadable")
print("PASS: "..n.." settings, persistence and learning checks")
return n
