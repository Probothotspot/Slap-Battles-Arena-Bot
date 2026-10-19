-- Observed session metrics. Slap counter growth is not proof of landed attacks.
local Stats = { Name = "SessionStats", Ready = true }
local function valid(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

function Stats.new(clock)
    clock = clock or os.clock
    local created = clock()
    local self = { Running = false, CreatedAt = created, ActiveSeconds = 0,
        SlapsEarned = 0, Deaths = 0, ArenaEntries = 0, PortalAttempts = 0,
        PortalFailures = 0, GloveChanges = 0, Logs = {}, Revision = 0 }

    function self:log(message, now)
        table.insert(self.Logs, { Time = math.max(0, (now or clock()) - created), Text = message })
        if #self.Logs > 30 then table.remove(self.Logs, 1) end
        self.Revision = self.Revision + 1
    end

    function self:setRunning(running, now)
        now = now or clock()
        running = running == true
        if running == self.Running then return end
        if self.Running then self.ActiveSeconds = self.ActiveSeconds + math.max(0, now - self.StartedAt) end
        self.Running, self.StartedAt = running, running and now or nil
        self:log(running and "Бот запущен" or "Бот остановлен", now)
    end

    function self:life(character, humanoid)
        if self.Character == character and self.Humanoid == humanoid then return end
        self.Character, self.Humanoid = character, humanoid
        self.DeathRecorded, self.LastZone, self.LastGlove = false, nil, nil
        self.SawAlive = humanoid ~= nil and humanoid.Health > 0
    end

    function self:death(character, now)
        if character ~= self.Character or self.DeathRecorded or not self.SawAlive then return end
        self.DeathRecorded = true
        if self.Running then self.Deaths = self.Deaths + 1; self:log("Персонаж погиб", now) end
    end

    function self:slaps(value, source, now)
        if not valid(value) or source == nil then
            self.CurrentSlaps, self.CounterSource, self.CounterHigh = nil, nil, nil
            return
        end
        self.CurrentSlaps = value
        if self.CounterSource ~= source then
            self.CounterSource, self.CounterHigh = source, value
            return
        end
        -- Keep the high-water mark when the same replicated counter drops/rebounds.
        local increase = math.max(0, value - self.CounterHigh)
        self.CounterHigh = math.max(self.CounterHigh, value)
        if self.Running and increase > 0 then
            self.SlapsEarned = self.SlapsEarned + increase
            self:log("Счётчик слаппов: +" .. tostring(increase), now)
        end
    end

    function self:observe(snapshot, navigation, now)
        now = now or clock()
        if snapshot.Alive then self.SawAlive = true
        elseif self.Humanoid and self.Humanoid.Health <= 0 then self:death(self.Character, now) end
        local zone = snapshot.ArenaState
        if zone == "lobby" or zone == "arena" then
            if self.Running and self.LastZone == "lobby" and zone == "arena" then
                self.ArenaEntries = self.ArenaEntries + 1
                self:log("Выход на арену подтверждён по Y", now)
            end
            self.LastZone = zone
        end
        local glove = snapshot.GloveName
        if glove and glove ~= self.LastGlove then
            if self.Running then
                if self.LastGlove then self.GloveChanges = self.GloveChanges + 1 end
                self:log("Перчатка: " .. glove, now)
            end
            self.LastGlove = glove
        end
        navigation = navigation or {}
        local attempts, failures = navigation.TotalAttempts or 0, navigation.TotalFailures or 0
        local addedAttempts = math.max(0, attempts - (self.LastAttempts or 0))
        local addedFailures = math.max(0, failures - (self.LastFailures or 0))
        if self.Running then
            self.PortalAttempts = self.PortalAttempts + addedAttempts
            self.PortalFailures = self.PortalFailures + addedFailures
            if addedAttempts > 0 then self:log("Начат подход к красному порталу", now) end
            if addedFailures > 0 then self:log(navigation.Message or "Вход не подтверждён, повторная попытка", now) end
        end
        self.LastAttempts, self.LastFailures = attempts, failures
    end

    function self:snapshot(now)
        now = now or clock()
        local active = self.ActiveSeconds + (self.Running and math.max(0, now - self.StartedAt) or 0)
        return {
            ActiveSeconds = active, SessionSeconds = math.max(0, now - created),
            SlapsEarned = self.SlapsEarned, TotalSlaps = self.CurrentSlaps,
            SlapsAvailable = self.CurrentSlaps ~= nil,
            SlapsPerHour = active >= 1 and self.SlapsEarned * 3600 / active or 0,
            Deaths = self.Deaths, ArenaEntries = self.ArenaEntries,
            PortalAttempts = self.PortalAttempts, PortalFailures = self.PortalFailures,
            GloveChanges = self.GloveChanges, Logs = self.Logs, Revision = self.Revision,
        }
    end
    return self
end

return Stats
