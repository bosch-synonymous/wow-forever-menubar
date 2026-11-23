-- Shared native-shaped status-bar fixture; no renderer, native taint or combat emulation.
local root = REPO_ROOT or "."
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function fixture(lateManager, options)
    options = options or {}
    local result = { effects = {}, monitors = {}, providers = {}, now = 0, restricted = {}, expectedReputationShown = false, watchedFactionID = 72, factionWrites = 0 }
    local function node(name, alpha, shown, mouse)
        local value = { name = name, alpha = alpha, shown = shown ~= false, scripts = {}, hooks = {} }
        function value:GetAlpha() return self.alpha end
        function value:SetAlpha(nextAlpha)
            self.alpha = nextAlpha
            result.effects[#result.effects + 1] = { self, "alpha", nextAlpha }
        end
        function value:IsShown() return self.shown end
        function value:IsVisible() return self.shown end
        function value:RunScript(script, ...)
            if self.scripts[script] then self.scripts[script](self, ...) end
            for _, hook in ipairs(self.hooks[script] or {}) do hook(self, ...) end
        end
        function value:Show()
            local previous = self.shown
            self.shown = true
            result.effects[#result.effects + 1] = { self, "show" }
            if not previous then self:RunScript("OnShow") end
        end
        function value:Hide()
            local previous = self.shown
            self.shown = false
            result.effects[#result.effects + 1] = { self, "hide" }
            if previous then self:RunScript("OnHide") end
        end
        function value:SetShown(nextShown) if nextShown then self:Show() else self:Hide() end end
        function value:SetScript(script, handler) self.scripts[script] = handler end
        function value:HookScript(script, handler)
            self.hooks[script] = self.hooks[script] or {}
            self.hooks[script][#self.hooks[script] + 1] = handler
        end
        if mouse ~= nil then
            value.mouse = mouse
            function value:CanChangeProtectedState() return true end
            function value:IsMouseEnabled() return self.mouse end
            function value:EnableMouse(enabled)
                self.mouse = enabled
                result.effects[#result.effects + 1] = { self, "mouse", enabled }
            end
        end
        return value
    end
    result.node = node
    result.xp = node("xp", 0.8, true, true)
    result.exhaustionTick = node("exhaustion tick", 0.6, true, true)
    result.xp.ExhaustionTick = result.exhaustionTick
    result.reputation = node("reputation", 0.9, false, true)
    result.chrome = node("shared frame", 0.7, true)
    result.firstDivider = node("divider", 0.4, true)
    result.pool = { active = { [result.firstDivider] = true } }
    function result.pool:EnumerateActive() return next, self.active end
    result.container = node("container", 1, true, true)
    result.container.bars = { [1] = result.xp, [2] = result.reputation }
    result.container.BarFrameTexture = result.chrome
    result.container.HorizontalDividersPool = result.pool
    result.manager = node("manager", 1, true, true)
    result.manager.barContainers = { result.container }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.StatusTrackingBarInfo = { BarsEnum = { Experience = 1, Reputation = 2 } }
    if not lateManager then env.StatusTrackingBarManager = result.manager end
    env.issecretvalue = function(value) return rawequal(value, result.restricted) end
    env.InCombatLockdown = function() return false end
    env.GetTime = function() return result.now end
    env.UnitLevel = function() return 20 end
    env.UnitXP = function() return 250 end
    env.UnitXPMax = function() return 1000 end
    env.GetXPExhaustion = function() return 300 end
    env.GetRestState = function() return 1 end
    env.IsResting = function() return false end
    env.EXHAUSTION_COLORS = nil
    env.C_Reputation = {
        GetWatchedFactionData = function() return { factionID = result.watchedFactionID, name = "Stormwind", reaction = 5,
            currentStanding = 4500, currentReactionThreshold = 3000, nextReactionThreshold = 9000 } end,
        GetFactionDataByID = function(id) return { factionID = id, name = "Other faction", reaction = 5,
            currentStanding = 4500, currentReactionThreshold = 3000, nextReactionThreshold = 9000 } end,
        IsMajorFaction = function() return false end,
        IsFactionParagonForCurrentPlayer = function() return false end,
        SetWatchedFactionByID = function() result.factionWrites = result.factionWrites + 1; error("widget must not change the native watched faction") end,
    }
    env.Menubar = { RegisterWidgetType = function(_, provider)
        result.providers[provider.id] = provider
        if provider.id == "xp" then result.provider = provider end
    end }
    env.CreateFrame = function(kind)
        equal(kind, "Frame")
        local frame = node("monitor", 1, true)
        frame.events = {}
        function frame:RegisterEvent(event) self.events[event] = true; return true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        result.monitors[#result.monitors + 1] = frame
        return frame
    end
    result.env = env
    function result:tick(elapsed)
        self.now = self.now + elapsed
        for _, frame in ipairs(self.monitors) do
            if frame:IsShown() then frame:RunScript("OnUpdate", elapsed) end
        end
    end
    function result:event(event, ...)
        for _, frame in ipairs(self.monitors) do
            if frame.events[event] then frame:RunScript("OnEvent", event, ...) end
        end
    end
    setfenv(assert(loadfile(root .. "/src/menubar-core/NativeStatusBars.lua")), env)()
    env.Menubar.NativeStatusBars = env.MenubarNativeStatusBars
    if options.xp ~= false then setfenv(assert(loadfile(root .. "/src/menubar-xp/XP.lua")), env)() end
    if options.reputation ~= false then setfenv(assert(loadfile(root .. "/src/menubar-reputation/Reputation.lua")), env)() end
    function result:widget(hide, kind)
        kind = kind or "xp"
        local provider = assert(self.providers[kind], "provider must be loaded")
        local settings = {}
        for key, value in pairs(provider.defaults) do settings[key] = value end
        local key = kind == "xp" and "hideBlizzardXPBar" or "hideBlizzardReputationBar"
        if hide ~= nil then settings[key] = hide end
        local widget = { settings = settings, definition = provider }
        function widget:SetGauge(...)
            if self.renderError then error(self.renderError, 0) end
            self.gauge = { ... }
        end
        function widget:SetText(text)
            if self.renderError then error(self.renderError, 0) end
            self.text = text
        end
        function widget:HideGauge() self.gauge = nil end
        return widget
    end
    function result:update(widget) widget.definition.update(widget) end
    function result:select(kind)
        self.expectedReputationShown = kind == "reputation"
        if self.expectedReputationShown then self.xp:Hide(); self.reputation:Show()
        else self.reputation:Hide(); self.xp:Show() end
    end
    function result:assertShell()
        equal(self.manager.alpha, 1); equal(self.manager.shown, true)
        equal(self.container.alpha, 1); equal(self.container.shown, true)
        equal(self.watchedFactionID, 72); equal(self.factionWrites, 0)
    end
    function result:assertNativeSelection()
        equal(self.manager.alpha, 1)
        equal(self.manager.shown, true)
        equal(self.container.alpha, 1)
        equal(self.container.shown, true)
        equal(self.reputation.alpha, 0.9)
        equal(self.reputation.mouse, true)
        equal(self.reputation.shown, self.expectedReputationShown)
    end
    function result:assertSuppressed()
        equal(self.xp.alpha, 0)
        equal(self.exhaustionTick.alpha, 0)
        equal(self.xp.mouse, false)
        equal(self.exhaustionTick.mouse, false)
        if self.xp:IsShown() then
            equal(self.chrome.alpha, 0)
            for divider in self.pool:EnumerateActive() do equal(divider.alpha, 0) end
        end
        self:assertNativeSelection()
    end
    function result:assertRestored()
        equal(self.xp.alpha, 0.8)
        equal(self.exhaustionTick.alpha, 0.6)
        equal(self.xp.mouse, true)
        equal(self.exhaustionTick.mouse, true)
        equal(self.chrome.alpha, 0.7)
        equal(self.firstDivider.alpha, 0.4)
        self:assertNativeSelection()
    end
    return result
end

return fixture
