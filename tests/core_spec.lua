-- Host lifecycle tests with a deliberately small WoW frame/UI boundary.
-- Rendering and protected-frame behavior still require the actual client.
local passed = 0
local function check(name, test)
    local ok, reason = pcall(test)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1
    print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function count(tableValue)
    local result = 0
    for _ in pairs(tableValue) do result = result + 1 end
    return result
end

local function frame()
    return {
        shown = true, width = 1200, scripts = {}, events = {}, eventAttempts = {},
        RegisterEvent = function(self, event)
            self.eventAttempts[event] = (self.eventAttempts[event] or 0) + 1
            if self.events[event] then return false end
            self.events[event] = true
            return true
        end,
        IsEventRegistered = function(self, event) return self.events[event] == true end,
        SetScript = function(self, event, callback) self.scripts[event] = callback end,
        Hide = function(self) self.shown = false end,
        Show = function(self) self.shown = true end,
        SetShown = function(self, shown) self.shown = shown end,
        IsShown = function(self) return self.shown end,
        IsVisible = function(self) return self.shown and (not self.parent or self.parent:IsVisible()) end,
        GetWidth = function(self) return self.width end,
        SetWidth = function(self, width) self.width = width end,
        SetHeight = function() end,
        SetSize = function() end,
        SetParent = function(self, parent) self.parent = parent end,
        ClearAllPoints = function(self) self.point = nil end,
        SetPoint = function(self, ...) self.point = { ... } end,
    }
end

local function fixture(saved, definitions, deferStart, rejectedEvent)
    _G.issecretvalue = nil
    _G.MenubarDB = saved
    _G.SlashCmdList = {}
    local messages = {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
    _G.CreateFrame = function()
        local result = frame()
        if rejectedEvent then
            result.RegisterEvent = function(self, event)
                if event == rejectedEvent then error("unsupported event") end
                self.events[event] = true
            end
        end
        return result
    end
    _G.UnitName = function() return "Tester" end
    _G.GetRealmName = function() return "Realm" end
    _G.GetBuildInfo = function() return "1.60.1", "70938", "Nov 12 2026", 16001 end
    _G.GameTooltip = { GetOwner = function() return nil end }
    dofile("src/menubar-core/Model.lua")
    dofile("src/menubar-core/Identity.lua")
    dofile("src/menubar-core/Layout.lua")
    dofile("src/menubar-core/Core.lua")
    local host = Menubar
    host.UI = {}
    function host.UI:UpdateBars()
        local placement = host:GetProfile().placement
        for _, name in ipairs({ "top", "bottom" }) do
            if not host.bars[name] then
                local bar = frame()
                bar.overflow, bar.empty = frame(), frame()
                host.bars[name] = bar
            end
            host.bars[name]:SetShown(placement == "both" or placement == name)
        end
    end
    function host.UI:CreateWidget(instance, previous)
        local definition = host.types[instance.type]
        if previous and previous.definition ~= definition then
            host:Call(previous, "destroy")
            previous = nil
        end
        local fresh = not previous
        local widget = previous or {
            id = instance.id,
            instance = instance,
            definition = definition,
            settings = instance.settings,
            frame = frame(),
            width = 40,
            elapsed = 0,
        }
        function widget:SetText(text)
            self.text = text
            host.dirty = true
        end
        function widget:SetWidth(width)
            self.width = width
            host.dirty = true
        end
        function widget:Refresh() if host.runtime[self.id] == self then host:RefreshWidget(self.id) end end
        widget.instance, widget.definition, widget.settings = instance, definition, instance.settings
        widget.frame:SetParent(host.bars[host:EffectiveBar(instance)])
        host.runtime[instance.id] = widget
        if fresh then host:Call(widget, "create") end
        return widget
    end
    function host.UI:StyleWidget() end
    function host.UI:UpdateWidget() end
    function host.UI:OpenSettings() self.settingsOpened = true end
    for _, definition in ipairs(definitions or {}) do host:RegisterWidgetType(definition) end
    if not deferStart then host:Start() end
    local function event(name, ...)
        host.eventFrame.scripts.OnEvent(host.eventFrame, name, ...)
    end
    local function tick(elapsed)
        host.eventFrame.scripts.OnUpdate(host.eventFrame, elapsed)
    end
    return host, messages, event, tick
end

local function clockDefinition(overrides)
    local definition = {
        id = "time", name = "Time", interval = 1,
        defaults = { zone = "local", nested = { value = 1 } },
        defaultPlacement = { bar = "top", alignment = "right" },
        update = function(widget) widget:SetText(widget.settings.zone) end,
    }
    for key, value in pairs(overrides or {}) do definition[key] = value end
    return definition
end

check("login creates a provider default once and honors active bottom placement", function()
    local host = fixture({ profiles = { Default = { placement = "bottom" } } }, { clockDefinition() }, true)
    equal(host.ready, nil)
    host.eventFrame.scripts.OnEvent(host.eventFrame, "PLAYER_LOGIN")
    equal(host.ready, true)
    local instances = MenubarModel.ListWidgets(host.db, host.characterKey)
    equal(#instances, 1)
    equal(instances[1].type, "time")
    equal(instances[1].bar, "bottom")
    equal(host.runtime[instances[1].id].text, "local")
    host:Start()
    host:EnsureDefaults()
    equal(#MenubarModel.ListWidgets(host.db, host.characterKey), 1)
end)

check("appearance rebuilds retain provider context without rerunning create", function()
    local creates, destroys = 0, 0
    local host = fixture(nil, { clockDefinition({
        create = function() creates = creates + 1 end,
        destroy = function() destroys = destroys + 1 end,
    }) })
    local id, original = next(host.runtime)
    host:GetProfile().placement = "both"
    host:Rebuild()
    equal(host.runtime[id], original)
    equal(creates, 1)
    equal(destroys, 0)
    host:RemoveWidget(id)
    equal(destroys, 1)
    equal(count(host.runtime), 0)
end)

check("deleted defaults stay deleted across reload and late registration", function()
    local host = fixture(nil, { clockDefinition() })
    local id = next(host.runtime)
    host:RemoveWidget(id)
    local saved = host.db
    host:RegisterWidgetType({ id = "other", name = "Other", defaultPlacement = false })
    equal(#MenubarModel.ListWidgets(host.db, host.characterKey), 0)
    host = fixture(saved, { clockDefinition() })
    equal(count(host.runtime), 0)
    equal(#MenubarModel.ListWidgets(host.db, host.characterKey), 0)
end)

check("unavailable providers retain instances and recover when the addon registers", function()
    local saved = { characters = { ["Tester - Realm"] = { widgets = {
        { id = "w7", type = "missing", settings = { selected = 23 }, bar = "bottom", alignment = "left" },
    } } } }
    local host = fixture(saved)
    local instance = MenubarModel.GetWidget(host.db, host.characterKey, "w7")
    equal(instance.settings.selected, 23)
    equal(instance.bar, "bottom")
    equal(instance.alignment, "left")
    assert(host.runtime.w7, "unavailable provider should remain manageable")
    host:RegisterWidgetType({ id = "missing", name = "Recovered",
        update = function(widget) widget:SetText("selected " .. widget.settings.selected) end })
    equal(#MenubarModel.ListWidgets(host.db, host.characterKey), 1)
    equal(host.runtime.w7.definition.id, "missing")
    equal(host.runtime.w7.text, "selected 23")
end)

check("saved selections survive new defaults and duplicate instances stay independent", function()
    local saved = { characters = { ["Tester - Realm"] = { widgets = {
        { id = "w1", type = "time", settings = { zone = "utc", nested = { chosen = true } } },
    } } } }
    local host = fixture(saved, { clockDefinition() })
    local one = host.runtime.w1
    equal(one.settings.zone, "utc")
    equal(one.settings.nested.chosen, true)
    equal(one.settings.nested.value, 1)
    local instance = host:AddWidget("time", "bottom", "center")
    local two = host.runtime[instance.id]
    two.settings.nested.value = 99
    two.settings.zone = "server"
    host:RefreshWidget(instance.id)
    equal(two.text, "server")
    equal(one.settings.nested.value, 1)
    equal(one.text, "utc")
    equal(host.types.time.defaults.nested.value, 1)
end)

check("changed factory defaults preserve omitted legacy settings even while disabled", function()
    local definition = clockDefinition({
        defaults = { zone = "server", show = true, flag = false, count = 10, nested = { value = 9, added = 2 }, newOption = "new" },
        legacyDefaults = { zone = "local", show = false, flag = true, count = 0, nested = { value = 1 } },
    })
    local saved = { characters = { ["Tester - Realm"] = { widgets = {
        { id = "w1", type = "time", settings = { zone = "utc", nested = { chosen = true }, unknown = 0 } },
        { id = "w2", type = "time", enabled = false, settings = {} },
    } } } }
    local host = fixture(saved, { definition }, true)
    definition.legacyDefaults.show = true
    definition.legacyDefaults.nested.value = 88
    host:Start()
    local one = MenubarModel.GetWidget(host.db, host.characterKey, "w1")
    local two = MenubarModel.GetWidget(host.db, host.characterKey, "w2")
    equal(one.settings.zone, "utc"); equal(one.settings.unknown, 0)
    equal(one.settings.show, false); equal(one.settings.count, 0)
    equal(one.settings.flag, true)
    equal(one.settings.nested.chosen, true); equal(one.settings.nested.value, 1)
    equal(one.settings.nested.added, 2); equal(one.settings.newOption, "new")
    equal(two.settings.zone, "local"); equal(two.settings.show, false)
    equal(two.settings.count, 0); equal(two.settings.nested.value, 1)
    equal(host.runtime.w2, nil)
    two.enabled = true; host:Rebuild()
    equal(host.runtime.w2.settings.show, false)
    local fresh = host:AddWidget("time")
    equal(fresh.settings.zone, "server"); equal(fresh.settings.show, true)
    equal(fresh.settings.flag, false)
    equal(fresh.settings.count, 10); equal(fresh.settings.nested.value, 9)
    fresh.settings.nested.value = 77
    equal(one.settings.nested.value, 1); equal(two.settings.nested.value, 1)
    equal(host.types.time.defaults.nested.value, 9)
end)

check("collapsed bars can be reordered consistently and expand without losing settings", function()
    local saved = { profiles = { Default = { placement = "both" } },
        characters = { ["Tester - Realm"] = { widgets = {
            { id = "w1", type = "time", bar = "top", alignment = "right", settings = { zone = "local" } },
            { id = "w2", type = "time", bar = "bottom", alignment = "right", settings = { zone = "utc" } },
        } } } }
    local host = fixture(saved, { clockDefinition() })
    equal(#host:DisplayInstances("top", "right"), 1)
    equal(#host:DisplayInstances("bottom", "right"), 1)
    host:GetProfile().placement = "top"
    host:Rebuild()
    local collapsed = host:DisplayInstances("top", "right")
    equal(#collapsed, 2)
    host:ReorderWidget(collapsed[2], -1)
    collapsed = host:DisplayInstances("top", "right")
    equal(collapsed[1].id, "w2")
    equal(collapsed[2].id, "w1")
    host:GetProfile().placement = "both"
    host:Rebuild()
    equal(host.runtime.w1.settings.zone, "local")
    equal(host.runtime.w2.settings.zone, "utc")
    equal(host.runtime.w1.frame:IsShown(), true)
    equal(host.runtime.w2.frame:IsShown(), true)
end)

check("provider failures are isolated and cleanup still runs for failed widgets", function()
    local healthyUpdates, failedDestroys = 0, 0
    local host, messages, _, tick = fixture(nil, {
        { id = "broken", name = "Broken", interval = 0.1,
            update = function() error("intentional test failure") end,
            destroy = function() failedDestroys = failedDestroys + 1 end },
        { id = "healthy", name = "Healthy", interval = 0.1,
            update = function(widget) healthyUpdates = healthyUpdates + 1; widget:SetText("working") end },
    })
    local brokenID, healthy
    for id, widget in pairs(host.runtime) do
        if widget.instance.type == "broken" then brokenID = id else healthy = widget end
    end
    assert(host.runtime[brokenID].failed)
    equal(healthy.text, "working")
    local previousUpdates, previousMessages = healthyUpdates, #messages
    tick(0.2)
    assert(healthyUpdates > previousUpdates)
    equal(#messages, previousMessages)
    host:RemoveWidget(brokenID)
    equal(failedDestroys, 1)
    equal(healthy.text, "working")
end)

check("provider events refresh only subscribed widgets and timers throttle updates", function()
    local firstUpdates, secondUpdates = 0, 0
    local host, _, event, tick = fixture(nil, {
        { id = "first", name = "First", interval = 1, events = { "PLAYER_MONEY" },
            update = function(widget) firstUpdates = firstUpdates + 1; widget:SetText("first") end },
        { id = "second", name = "Second", interval = 1,
            update = function(widget) secondUpdates = secondUpdates + 1; widget:SetText("second") end },
    })
    local firstBefore, secondBefore = firstUpdates, secondUpdates
    event("PLAYER_MONEY")
    equal(firstUpdates, firstBefore + 1)
    equal(secondUpdates, secondBefore)
    tick(0.25)
    equal(firstUpdates, firstBefore + 1)
    equal(secondUpdates, secondBefore)
    tick(0.75)
    equal(firstUpdates, firstBefore + 2)
    equal(secondUpdates, secondBefore + 1)
    assert(host.eventFrame.events.PLAYER_MONEY)
end)

check("a failed create is retried before update when configuration is repaired", function()
    local attempts, updates, destroys = 0, 0, 0
    local host = fixture(nil, {
        { id = "initialization", name = "Initialization", defaults = { ready = false },
            create = function(widget)
                attempts = attempts + 1
                assert(widget.settings.ready, "test provider is not configured yet")
                widget.initialized = true
            end,
            update = function(widget)
                assert(widget.initialized, "update must follow a successful create")
                updates = updates + 1
                widget:SetText("ready")
            end,
            destroy = function() destroys = destroys + 1 end,
        },
    })
    local id, widget = next(host.runtime)
    assert(widget.failed)
    equal(widget.failedCallback, "create")
    equal(updates, 0)
    local attemptsBefore = attempts
    widget.settings.ready = true
    host:RefreshWidget(id)
    equal(attempts, attemptsBefore + 1)
    equal(updates, 1)
    equal(widget.failed, nil)
    equal(widget.text, "ready")
    host:RemoveWidget(id)
    equal(destroys, 1)
end)

check("invocations preserve nil-filled return tuples, nested ownership and original error objects", function()
    local host = fixture(nil, { clockDefinition() })
    local _, widget = next(host.runtime)
    local function capture(...) return { n = select("#", ...), ... } end
    local values = capture(host:Invoke(widget, "outer", function(owner, ...)
        equal(owner, widget); equal(owner._menubarCallback, "outer")
        local nested = capture(host:Invoke(owner, "inner", function(inner)
            equal(inner._menubarCallback, "inner")
        end))
        equal(nested.n, 1); equal(nested[1], true)
        equal(owner._menubarCallback, "outer")
        return nil, ...
    end, "first", nil, "last", nil))
    equal(values.n, 6); equal(values[1], true); equal(values[2], nil)
    equal(values[3], "first"); equal(values[4], nil); equal(values[5], "last"); equal(values[6], nil)
    equal(widget._menubarCallback, nil); equal(host.workDepth, 0)
    local reason = {}
    local failure = capture(host:Invoke(widget, "failure", function() error(reason, 0) end))
    equal(failure.n, 2); equal(failure[1], false); equal(failure[2], reason)
    equal(widget._menubarCallback, nil); equal(host.workDepth, 0)
end)

check("event phases forward nil gaps and trailing nils without changing event ownership", function()
    local received, eventName
    local host, _, event = fixture(nil, {
        clockDefinition({ events = { "PLAYER_MONEY" }, event = function(widget, name, ...)
            equal(widget._menubarCallback, "event")
            eventName, received = name, { n = select("#", ...), ... }
        end }),
    })
    event("PLAYER_MONEY", "first", nil, "last", nil)
    equal(eventName, "PLAYER_MONEY"); equal(received.n, 4)
    equal(received[1], "first"); equal(received[2], nil); equal(received[3], "last"); equal(received[4], nil)
    equal(host.workDepth, 0)
    event("PLAYER_MONEY"); equal(received.n, 0); equal(host.workDepth, 0)
end)

check("future saved schemas stay untouched and the addon does not start", function()
    local saved = { schemaVersion = 999, profiles = "future representation" }
    local host, messages = fixture(saved, { clockDefinition() })
    equal(host.ready, nil)
    equal(host.db, nil)
    equal(MenubarDB, saved)
    equal(saved.profiles, "future representation")
    equal(count(host.runtime), 0)
    assert(messages[1]:match("newer"))
end)

check("registration rejects invalid contracts before retaining a provider", function()
    local host = fixture(nil)
    local invalid = {
        { interval = math.huge }, { interval = 0 / 0 }, { interval = 0.01 },
        { reset = true }, { update = "callback" }, { defaults = false },
        { legacyDefaults = false }, { legacyDefaults = { missing = 1 } },
        { legacyDefaults = { nested = { missing = 1 } } },
        { legacyDefaults = { zone = function() end } },
        { legacyDefaults = { nested = { value = math.huge } } },
        { click = true }, { clickHint = false }, { clickHint = "" }, { clickHint = " " },
        { wheelHint = false }, { wheelHint = "" }, { wheelHint = " " },
        { events = { [2] = "PLAYER_MONEY" } }, { events = { false } },
        { defaultPlacement = { sidebarOrder = 0 } }, { defaultPlacement = { sidebarOrder = -1 } },
        { defaultPlacement = { sidebarOrder = 1.5 } }, { defaultPlacement = { sidebarOrder = math.huge } },
        { defaultPlacement = { sidebarOrder = "first" } }, { defaultPlacement = { sidebarOrder = false } },
        { settings = { { key = "n", label = "N", type = "number", min = 2, max = 1 } } },
        { settings = { { key = "n", label = "N", type = "number", min = 2000000 } } },
        { settings = { { key = "n", label = "N", type = "number", max = -1 } } },
        { settings = { { key = "n", label = "N", type = "number", max = -0.2, integer = true } } },
        { settings = { { key = "n", label = "N", type = "number", min = 0.2, max = 0.8, integer = true } } },
        { settings = { { key = "n", label = "N", type = "number", max = math.huge } } },
        { settings = { { key = "s", label = "S", type = "select", options = { { label = "bad", value = {} } } } } },
        { settings = { { key = "same", label = "A", type = "text" }, { key = "same", label = "B", type = "text" } } },
        { settings = { { key = "n", label = "N", type = "number", enabledBy = "missing" } } },
        { settings = { { key = "n", label = "N", type = "number", enabledBy = false } } },
        { settings = { { key = "n", label = "N", type = "number", enabledBy = " " } } },
        { settings = { { key = "n", label = "N", type = "number", enabledBy = "n" } } },
        { settings = { { key = "n", label = "N", type = "number", enabledBy = "text" },
            { key = "text", label = "Text", type = "text" } } },
        { settings = { { key = "text", label = "Text", type = "text", enabledBy = "toggle" },
            { key = "toggle", label = "Toggle", type = "toggle" } } },
    }
    for _, overrides in ipairs(invalid) do
        local ok = pcall(host.RegisterWidgetType, host, clockDefinition(overrides))
        equal(ok, false)
        equal(host.types.time, nil)
        equal(count(host.runtime), 0)
    end
    host:RegisterWidgetType(clockDefinition({ settings = {
        { key = "on", label = "On", type = "select", options = { { label = "Off", value = false } } },
    } }))
    assert(host.types.time)
end)

check("numeric dependencies allow forward toggle references in an owned declaration snapshot", function()
    local host = fixture(nil)
    local fields = {
        { key = "amount", label = "Amount", type = "number", enabledBy = "custom" },
        { key = "custom", label = "Custom", type = "toggle" },
    }
    host:RegisterWidgetType(clockDefinition({ settings = fields }))
    fields[1].enabledBy = "changed"
    equal(host.types.time.settings[1].enabledBy, "custom")
end)

check("default sidebar rank and per-group position remain independent with unranked and opt-out providers", function()
    local host = fixture(nil, {
        { id = "z-first", name = "First", defaultPlacement = { bar = "top", alignment = "right", sidebarOrder = 1, order = 2 } },
        { id = "a-second", name = "Second", defaultPlacement = { bar = "top", alignment = "right", sidebarOrder = 2, order = 1 } },
        { id = "b-unranked", name = "Unranked", defaultPlacement = { bar = "top", alignment = "right" } },
        { id = "c-manual", name = "Manual", defaultPlacement = false },
    })
    local sidebar, visual = host:SidebarInstances(), host:DisplayInstances("top", "right")
    equal(#sidebar, 3); equal(sidebar[1].type, "z-first"); equal(sidebar[2].type, "a-second"); equal(sidebar[3].type, "b-unranked")
    equal(visual[1].type, "a-second"); equal(visual[2].type, "z-first"); equal(visual[3].type, "b-unranked")
    local manual = host:AddWidget("c-manual")
    equal(manual.bar, "top"); equal(manual.alignment, "right")
end)

check("manual additions resolve declared defaults and explicit overrides without inserting ahead of existing siblings", function()
    local host = fixture({ profiles = { Default = { placement = "both" } } }, {
        { id = "preferred", name = "Preferred", defaultPlacement = { bar = "bottom", alignment = "left", order = 1, sidebarOrder = 1 } },
    })
    local original = host:SidebarInstances()[1]
    local added = host:AddWidget("preferred")
    equal(added.bar, "bottom"); equal(added.alignment, "left"); equal(added.order, 2); equal(original.order, 1)
    local override = host:AddWidget("preferred", "top", "right")
    equal(override.bar, "top"); equal(override.alignment, "right")
    local barOnly = host:AddWidget("preferred", "top")
    equal(barOnly.bar, "top"); equal(barOnly.alignment, "left")
    host:GetProfile().placement = "top"
    local active = host:AddWidget("preferred")
    equal(active.bar, "top"); equal(active.alignment, "left"); equal(active.order, 2)
    equal(host:SidebarInstances()[1], original)
end)

check("unsupported optional events warn once and leave provider polling operational", function()
    local updates = 0
    local definition = function(id)
        return { id = id, name = id, interval = 0.1, events = { "UNSUPPORTED_EVENT", "PLAYER_MONEY" },
            update = function(widget) updates = updates + 1; widget:SetText("ready") end }
    end
    local host, messages, event, tick = fixture(nil, { definition("one"), definition("two") }, false, "UNSUPPORTED_EVENT")
    local warnings = 0
    for _, message in ipairs(messages) do if message:match("UNSUPPORTED_EVENT") then warnings = warnings + 1 end end
    equal(warnings, 1)
    local previous = updates
    tick(0.2)
    equal(updates, previous + 2)
    event("PLAYER_MONEY")
    equal(updates, previous + 4)
    assert(host.eventFrame.events.PLAYER_MONEY)
end)

check("bootstrap and event-only providers share one native registration without a false warning", function()
    local updates, deliveries = 0, 0
    local function definition(id)
        return { id = id, name = id, interval = false,
            events = { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_MONEY" },
            update = function(widget) updates = updates + 1; widget:SetText("Ready") end,
            event = function(_, name, initial, reload)
                if name == "PLAYER_ENTERING_WORLD" then equal(initial, false); equal(reload, true) end
                deliveries = deliveries + 1
            end }
    end
    local host, messages, event, tick = fixture(nil, { definition("one"), definition("two") }, true)
    equal(#messages, 0)
    for _, name in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
        "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "PLAYER_MONEY" }) do
        equal(host.eventFrame.eventAttempts[name], 1)
        equal(host.eventFrame:IsEventRegistered(name), true)
    end
    event("PLAYER_LOGIN"); equal(updates, 2)
    equal(#messages, 0)
    event("PLAYER_ENTERING_WORLD", false, true); equal(updates, 4); equal(deliveries, 2)
    event("PLAYER_REGEN_ENABLED"); equal(updates, 6); equal(deliveries, 4)
    tick(100); equal(updates, 6)
    equal(#messages, 0)
end)

check("event membership is authoritative and unsupported events still warn once", function()
    local host, messages, event = fixture(nil)
    local initialMessages = #messages
    local frame, native = host.eventFrame, host.eventFrame.RegisterEvent
    local updates = 0
    frame:RegisterEvent("ALREADY_REGISTERED")
    function frame:RegisterEvent(name)
        if name == "FALSE_WITH_MEMBERSHIP" then native(self, name); return false end
        if name == "FALSE_WITHOUT_MEMBERSHIP" then return false end
        if name == "TRUE_WITHOUT_MEMBERSHIP" then return true end
        if name == "THROW_WITHOUT_MEMBERSHIP" then error("unsupported event", 0) end
        return native(self, name)
    end
    for _, id in ipairs({ "one", "two" }) do
        host:RegisterWidgetType({ id = id, name = id, interval = false,
            events = { "ALREADY_REGISTERED", "FALSE_WITH_MEMBERSHIP", "FALSE_WITHOUT_MEMBERSHIP",
                "TRUE_WITHOUT_MEMBERSHIP", "THROW_WITHOUT_MEMBERSHIP" },
            update = function(widget) updates = updates + 1; widget:SetText("Ready") end })
    end
    equal(frame.eventAttempts.ALREADY_REGISTERED, 1)
    equal(#messages, initialMessages + 3)
    for _, name in ipairs({ "FALSE_WITHOUT_MEMBERSHIP", "TRUE_WITHOUT_MEMBERSHIP", "THROW_WITHOUT_MEMBERSHIP" }) do
        local warnings = 0
        for _, message in ipairs(messages) do if message:find(name, 1, true) then warnings = warnings + 1 end end
        equal(warnings, 1)
    end
    local previous = updates
    event("ALREADY_REGISTERED"); event("FALSE_WITH_MEMBERSHIP")
    equal(updates, previous + 4)
end)

check("legacy void event registration works when membership readback is absent", function()
    local host, messages, event = fixture(nil)
    local initialMessages = #messages
    local frame, updates = host.eventFrame, 0
    frame.IsEventRegistered = nil
    function frame:RegisterEvent(name) self.events[name] = true end
    host:RegisterWidgetType({ id = "legacy-events", name = "Legacy", interval = false, events = { "LEGACY_EVENT" },
        update = function(widget) updates = updates + 1; widget:SetText("Ready") end })
    equal(#messages, initialMessages); equal(frame.events.LEGACY_EVENT, true)
    local previous = updates; event("LEGACY_EVENT"); equal(updates, previous + 1)
end)

check("unreadable membership cannot be replaced by an optimistic registration return", function()
    for _, mode in ipairs({ "restricted", "throwing" }) do
        local host, messages = fixture(nil)
        local initialMessages, frame = #messages, host.eventFrame
        local secret = {}
        issecretvalue = function(value) return rawequal(value, secret) end
        function frame:IsEventRegistered()
            if mode == "throwing" then error("readback unavailable", 0) end
            return secret
        end
        local ok = pcall(host.RegisterWidgetType, host, { id = mode, name = mode, interval = false,
            events = { "UNREADABLE_EVENT" }, update = function(widget) widget:SetText("Ready") end })
        equal(ok, true); equal(#messages, initialMessages + 1)
        assert(messages[#messages]:find("UNREADABLE_EVENT", 1, true))
    end
    issecretvalue = nil
end)

check("reset and presentation failures preserve the original provider error", function()
    local resets, presentations, ready = 0, 0, true
    local host = fixture(nil, { clockDefinition({
        update = function(widget) if not ready then error("original provider failure", 0) end; widget:SetText("ready") end,
        reset = function(_, callback) resets = resets + 1; equal(callback, "update"); error("reset failure", 0) end,
    }) })
    function host.UI:ResetWidgetPresentation() presentations = presentations + 1; error("presentation failure", 0) end
    local id, widget = next(host.runtime)
    widget.SetText = function() error("error label failure", 0) end
    ready = false
    host:RefreshWidget(id)
    equal(resets, 1); equal(presentations, 1)
    equal(widget.failed, "original provider failure")
    equal(widget.failedCallback, "update")
    host:Call(widget, "tooltip")
    equal(resets, 1)
end)

check("identical event failures report once until a successful recovery", function()
    local ready = true
    local host, messages, event = fixture(nil, { clockDefinition({ events = { "PLAYER_MONEY" },
        update = function(widget) if not ready then error("same failure", 0) end; widget:SetText("ready") end,
    }) })
    local before = #messages
    ready = false
    event("PLAYER_MONEY"); event("PLAYER_MONEY"); event("PLAYER_MONEY")
    equal(#messages, before + 1)
    ready = true
    event("PLAYER_MONEY")
    local _, widget = next(host.runtime)
    equal(widget.failed, nil)
    ready = false
    event("PLAYER_MONEY")
    equal(#messages, before + 2)
end)

check("restricted and unprintable callback errors stay inside the host boundary", function()
    local ready, failure = true, nil
    local host = fixture(nil, { clockDefinition({ update = function(widget)
        if not ready then error(failure, 0) end
        widget:SetText("ready")
    end }) })
    local id, widget = next(host.runtime)
    ready, failure = false, setmetatable({}, { __tostring = function() error("cannot stringify") end })
    host:RefreshWidget(id)
    equal(widget.failed, "Error details are unavailable.")
    local restricted = {}
    _G.issecretvalue = function(value) return rawequal(value, restricted) end
    failure = restricted
    host:RefreshWidget(id)
    equal(widget.failed, "Error details are restricted.")
    _G.issecretvalue = nil
end)

check("timer elapsed excludes carried scheduling time and manual refresh discards pending time", function()
    local values = {}
    local host, _, _, tick = fixture(nil, { clockDefinition({ interval = 0.1, update = function(_, elapsed)
        if elapsed then values[#values + 1] = elapsed end
    end }) })
    tick(0.06); tick(0.06); tick(0.09); tick(0.1)
    equal(#values, 3)
    assert(math.abs(values[1] - 0.12) < 0.000001)
    assert(math.abs(values[2] - 0.09) < 0.000001)
    assert(math.abs(values[3] - 0.1) < 0.000001)
    tick(0.05)
    host:RefreshWidget(next(host.runtime))
    tick(0.06)
    assert(math.abs(values[4] - 0.06) < 0.000001)
end)

check("parent-hidden widgets suspend timers and refresh once on becoming visible", function()
    local updates = 0
    local host, _, _, tick = fixture(nil, { clockDefinition({ interval = 0.1,
        update = function() updates = updates + 1 end }) })
    local _, widget = next(host.runtime)
    local previous = updates
    host.bars.top:Hide()
    equal(widget.frame:IsShown(), true)
    equal(widget.frame:IsVisible(), false)
    tick(10)
    equal(updates, previous)
    host.bars.top:Show()
    tick(0.01)
    equal(updates, previous + 1)
    tick(0.01)
    equal(updates, previous + 1)
    tick(0.1)
    equal(updates, previous + 2)
    tick(-1); tick(math.huge); tick(0 / 0)
    equal(updates, previous + 2)
end)

check("unknown saved formats leave the saved root intact and do not start", function()
    for _, saved in ipairs({ false, "unrecognized", { schemaVersion = "future", profiles = "untouched" } }) do
        local host, messages = fixture(saved)
        equal(host.ready, nil)
        equal(MenubarDB, saved)
        assert(messages[1]:match("preserved"))
    end
end)

check("optional direct clicks validate and use the same failure and reset boundary", function()
    local clicks, resets, fail = 0, 0, true
    local host = fixture(nil, { clockDefinition({ clickHint = "open Social",
        click = function(widget, button)
            equal(button, "LeftButton")
            equal(widget.settings.zone, "local")
            clicks = clicks + 1
            if fail then error("direct action failed", 0) end
        end,
        reset = function(_, callback) equal(callback, "click"); resets = resets + 1 end,
    }) })
    local id, widget = next(host.runtime)
    equal(host.types.time.clickHint, "open Social")
    equal(host:Call(widget, "click", "LeftButton"), false)
    equal(widget.failed, "direct action failed")
    equal(widget.failedCallback, "click")
    equal(resets, 1)
    host:Call(widget, "click", "LeftButton")
    equal(clicks, 1)
    fail = false
    host:RefreshWidget(id)
    equal(widget.failed, nil)
    equal(host:Call(widget, "click", "LeftButton"), true)
    equal(clicks, 2); equal(resets, 1)
end)

check("restricted direct-click hints are rejected before registration", function()
    local host = fixture(nil)
    local restricted = {}
    _G.issecretvalue = function(value) return rawequal(value, restricted) end
    equal(pcall(host.RegisterWidgetType, host, clockDefinition({ clickHint = restricted })), false)
    equal(pcall(host.RegisterWidgetType, host, clockDefinition({ wheelHint = restricted })), false)
    equal(host.types.time, nil)
    _G.issecretvalue = nil
end)

print(string.format("%d core tests passed", passed))
