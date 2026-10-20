-- Local preferences only. Optional executor APIs must never prevent GUI startup.
local M={Name="Settings",Ready=true}
local function finite(n,lo,hi) return type(n)=="number" and n==n and n>=lo and n<=hi end
local function checks(n) return finite(n,10,2000) and n==math.floor(n) end
local function profile(p)
    return type(p)=="table" and finite(p.Range,1,40) and finite(p.Interval,.15,30)
end
local function service(name)
    local ok,v=pcall(function() return game:GetService(name) end)
    return ok and v or nil
end
function M.new(context)
    local config=context.Config
    local g=context.Globals or {}
    local input=context.Input or service("UserInputService")
    local http=context.HttpService or service("HttpService")
    local self={Executor="Unknown",Device="Unknown",Profiles={},PathVisible=false,LearningEnabled=true,CameraLock=true,Dirty=false,
        Message="Сохранение недоступно: нет файлового API",StorageAvailable=false}
    for _,fn in ipairs({g.identifyexecutor or false,g.getexecutorname or false}) do
        if type(fn)=="function" then
            local ok,name=pcall(fn)
            if ok and type(name)=="string" then
                name=name:gsub("[%c]"," "):match("^%s*(.-)%s*$")
                if #name>0 then self.Executor=name:sub(1,32); break end
            end
        end
    end
    -- Platform wins over executor branding and touchscreen availability (touch laptops).
    local ok,platform=pcall(function() return tostring(input:GetPlatform()):lower() end)
    if ok then
        if platform:find("android",1,true) or platform:find("ios",1,true) then self.Device="Mobile"
        elseif platform:find("windows",1,true) or platform:find("osx",1,true)
            or platform:find("linux",1,true) or platform:find("uwp",1,true) then self.Device="PC" end
    end
    if self.Device=="Unknown" then
        pcall(function()
            if input.TouchEnabled and not input.KeyboardEnabled then self.Device="Mobile"
            elseif input.KeyboardEnabled and input.MouseEnabled then self.Device="PC" end
        end)
    end
    self.DefaultChecks=self.Device=="PC" and config.Performance.PCChecks or config.Performance.MobileChecks
    function self:applyBudget(n)
        if not checks(n) then return false end
        self.SearchChecks=n
        local o=config.Pursuit
        o.WorkPerFrame=n
        o.BudgetSeconds=math.min(.006,.0005+n*.000005)
        o.GoalCandidates=math.max(8,math.min(64,math.floor(n/8)))
        o.MaxExpanded=math.min(6000,800+n*4)
        return true
    end
    self:applyBudget(self.DefaultChecks)
    local id=tonumber(context.UserId)
    id=finite(id,1,1e15) and math.floor(id) or 0
    self.Path="ArenaBot_Settings_v1_"..string.format("%.0f",id)..".json"
    self.BackupPath=self.Path..".bak"
    self.StorageAvailable=type(g.readfile)=="function" and type(g.writefile)=="function"
        and http~=nil and type(http.JSONEncode)=="function" and type(http.JSONDecode)=="function"
    local function decode(raw)
        if type(raw)~="string" or #raw>65536 then return nil end
        local good,data=pcall(function() return http:JSONDecode(raw) end)
        if not good or type(data)~="table" or data.Schema~=1 or not checks(data.SearchChecks)
            or type(data.PathVisible)~="boolean" or type(data.Profiles)~="table"
            or (data.CameraLock~=nil and type(data.CameraLock)~="boolean") then return nil end
        local count=0
        for name,p in pairs(data.Profiles) do
            count=count+1
            if count>128 or type(name)~="string" or #name>100 or not profile(p) then return nil end
        end
        return data
    end
    local function read(path)
        if type(g.isfile)=="function" then
            local exists,yes=pcall(g.isfile,path)
            if exists and not yes then return nil,"missing" end
        end
        local good,raw=pcall(g.readfile,path)
        if not good then return nil,"unreadable" end
        return raw,"read"
    end
    if self.StorageAvailable then
        local raw,state=read(self.Path)
        local data=decode(raw)
        local recovered=false
        if not data then
            local backup=read(self.BackupPath)
            data=decode(backup)
            if data then raw=backup; recovered=true end
        end
        if data then
            self:applyBudget(data.SearchChecks)
            self.PathVisible=data.PathVisible
            self.LearningEnabled=data.LearningEnabled~=false
            self.CameraLock=data.CameraLock~=false
            config.Camera.CharacterLock=self.CameraLock
            for name,p in pairs(data.Profiles) do
                self.Profiles[name]={Range=p.Range,Interval=p.Interval}
                local target=config.Attack.GloveProfiles[name] or {}
                target.Range,target.Interval,target.Verified=p.Range,p.Interval,false
                config.Attack.GloveProfiles[name]=target
            end
            self.LastGood=raw
            self.Message=recovered and "Настройки восстановлены из резервной копии" or "Настройки загружены"
        else
            self.Message=state=="missing" and "Новые настройки; сохранятся после изменения"
                or "Настройки не прочитаны; используются стандартные"
        end
    end
    function self:save()
        if not self.Dirty then return true end
        if not self.StorageAvailable then self.Message="Сохранение недоступно: нет файлового API"; return false end
        local good,raw=pcall(function()
            return http:JSONEncode({Schema=1,SearchChecks=self.SearchChecks,PathVisible=self.PathVisible,
                LearningEnabled=self.LearningEnabled,CameraLock=self.CameraLock,Profiles=self.Profiles})
        end)
        if not good or not decode(raw) then self.Message="Ошибка подготовки настроек"; return false end
        -- Preserve a previously validated copy before replacing the primary file.
        if self.LastGood then
            local backed=pcall(g.writefile,self.BackupPath,self.LastGood)
            if not backed then self.Message="Ошибка записи резервной копии"; return false end
        end
        local wrote=pcall(g.writefile,self.Path,raw)
        local verified=wrote and read(self.Path)
        if verified~=raw then self.Message="Ошибка сохранения: запись не подтверждена"; return false end
        self.LastGood=raw; self.Dirty=false; self.Message="Настройки сохранены на устройстве"
        return true
    end
    function self:setChecks(n)
        if not self:applyBudget(n) then return false end
        self.Dirty=true; self:save(); return true
    end
    function self:setPathVisible(value)
        self.PathVisible=value==true; self.Dirty=true; self:save()
    end
    function self:setLearning(value)
        self.LearningEnabled=value==true; self.Dirty=true; self:save()
    end
    function self:setCameraLock(value)
        self.CameraLock=value==true; config.Camera.CharacterLock=self.CameraLock
        self.Dirty=true; self:save()
    end
    function self:openStore(suffix,validate,limit)
        assert(suffix:match("^[%w%-]+$"),"Invalid store name")
        local store={Available=self.StorageAvailable,Message="Память: сохранение недоступно"}
        local path=self.Path:gsub("%.json$","_"..suffix..".json")
        local function parse(raw)
            if type(raw)~="string" or #raw>(limit or 262144) then return nil end
            local yes,data=pcall(function() return http:JSONDecode(raw) end)
            return yes and validate(data) and data or nil
        end
        function store:load()
            if not self.Available then return nil end
            local raw,state=read(path); local data=parse(raw)
            if not data then
                local backup=read(path..".bak"); data=parse(backup)
                if data then raw=backup; self.Message="Память восстановлена из копии" end
            else self.Message="Память загружена" end
            if data then self.LastGood=raw
            else self.Message=state=="missing" and "Память: новый файл" or "Память не прочитана; новый опыт" end
            return data
        end
        function store:save(data)
            if not self.Available then return false end
            local yes,raw=pcall(function() return http:JSONEncode(data) end)
            if not yes or not parse(raw) then self.Message="Ошибка подготовки памяти"; return false end
            if self.LastGood and not pcall(g.writefile,path..".bak",self.LastGood) then
                self.Message="Ошибка резервной копии памяти"; return false
            end
            local wrote=pcall(g.writefile,path,raw)
            if not wrote or read(path)~=raw then self.Message="Память не сохранена: ошибка записи"; return false end
            self.LastGood=raw; self.Message="Память сохранена на устройстве"; return true
        end
        return store
    end
    function self:setProfile(name,range,interval)
        if type(name)~="string" or #name>100 or not profile({Range=range,Interval=interval}) then return false end
        if not self.Profiles[name] then
            local count=0; for _ in pairs(self.Profiles) do count=count+1 end
            if count>=128 then return false end
        end
        self.Profiles[name]={Range=range,Interval=interval}; self.Dirty=true; self:save(); return true
    end
    return self
end
return M
