-- Original outside-author contracts through the real Core TOC/public context.
-- Native event delivery and drawing are fixtures, not client execution.
local root = REPO_ROOT or "."
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function fixture(saved)
    local Stub = dofile(root .. "/tests/wow_stub.lua"); Stub.Install(); MenubarDB = saved
    for line in io.lines(root .. "/src/menubar-core/Menubar.toc") do
        local file = line:match("^%s*(.-)%s*$")
        if file:match("%.lua$") then assert(loadfile(root .. "/src/menubar-core/" .. file))("Menubar", {}) end
    end
    local f = { Stub = Stub, host = Menubar }
    function f:tick(elapsed) self.host.eventFrame:GetScript("OnUpdate")(self.host.eventFrame, elapsed or 0) end
    function f:event(name, ...) self.host.eventFrame:GetScript("OnEvent")(self.host.eventFrame, name, ...) end
    function f:settings(widget) self.host.UI:OpenWidget(widget.id) end
    function f:control(caption)
        for _, control in ipairs(self.host.UI.window.controls) do if control.caption == caption then return control end end
        error("Missing native setting " .. caption)
    end
    function f:enabled(widget, enabled)
        self:settings(widget)
        local toggle = self:control("Enabled")
        if toggle:GetChecked() ~= enabled then toggle:Click() end
    end
    return f
end

check("an outside provider registers before login or later without private host dependencies", function()
    for _, late in ipairs({ false, true }) do
        local f = fixture(); local creates, updates, held = 0, 0
        if late then f.host:Start() end
        Menubar:RegisterWidgetType({ id = "outside-greeting", name = "Outside greeting", interval = false,
            defaults = { caption = "Welcome" },
            settings = { { key = "caption", label = "Greeting", type = "text" } },
            create = function(widget) creates = creates + 1; held = widget end,
            update = function(widget) updates = updates + 1; widget:SetText(widget.settings.caption) end,
            tooltip = function(_, tip) tip:AddLine("An original outside provider") end })
        if not late then equal(creates, 0); f:event("PLAYER_LOGIN") end
        equal(creates, 1); equal(updates, 1); equal(held.label:GetText(), "Welcome")
        equal(held.GetSettings, nil, "The fixture must not invent an accessor")
        f:settings(held); local edit = f:control("Greeting")
        edit:SetText("Hello"); edit:GetScript("OnEnterPressed")(edit)
        equal(held.settings.caption, "Hello"); equal(held.label:GetText(), "Hello")
    end
end)

check("invalid persisted defaults are rejected before any registration or saved-state mutation", function()
    local f = fixture(); local cycle = {}; cycle.self = cycle
    local indirect, inner = {}, {}; indirect.inner = inner; inner.outer = indirect
    local restricted = {}; issecretvalue = function(value) return rawequal(value, restricted) end
    local invalid = { cycle, indirect, { bad = function() end }, { bad = coroutine.create(function() end) },
        { bad = math.huge }, { bad = 0 / 0 }, { [{}] = true }, setmetatable({}, {}), { bad = restricted } }
    for _, defaults in ipairs(invalid) do
        local ok, reason = pcall(Menubar.RegisterWidgetType, Menubar,
            { id = "outside-invalid", name = "Invalid", defaults = defaults })
        equal(ok, false); assert(type(reason) == "string")
        equal(f.host.types["outside-invalid"], nil); equal(MenubarDB, nil)
    end
    local shared = { value = 2 }; local held
    Menubar:RegisterWidgetType({ id = "outside-valid", name = "Valid", defaults = { one = shared, two = shared },
        update = function(widget) held = widget; widget:SetText(widget.settings.one.value) end })
    f.host:Start(); equal(held.settings.one.value, 2); equal(held.failed, nil)
end)

check("registration snapshots nested declarations while preserving intentional callback functions", function()
    local f = fixture({ profiles = { Default = { placement = "both" } } })
    local held, updates, events = nil, 0, 0
    local update = function(widget) held = widget; updates = updates + 1; widget:SetText(widget.settings.caption) end
    local declaration = { id = "outside-snapshot", name = "Original", interval = 1,
        defaults = { caption = "Original", nested = { value = 7 } }, events = { "PLAYER_MONEY" },
        defaultPlacement = { bar = "bottom", alignment = "left" }, update = update,
        event = function(_, name, value, tail) equal(name, "PLAYER_MONEY"); equal(value, false); equal(tail, 0); events = events + 1 end,
        settings = { { key = "caption", label = "Caption", type = "select", options = { { value = "Original", label = "Original choice" } } } } }
    Menubar:RegisterWidgetType(declaration)
    declaration.id, declaration.name, declaration.interval, declaration.events[1] = "mutated", "Mutated", 100, "PLAYER_XP_UPDATE"
    declaration.defaults.caption, declaration.defaults.nested.value = "Mutated", 99
    declaration.defaultPlacement.bar, declaration.settings[1].options[1].label = "top", "Mutated choice"
    f.host:Start(); equal(held.label:GetText(), "Original"); equal(held.settings.nested.value, 7)
    equal(held.instance.bar, "bottom"); equal(held.definition.update, update)
    f:settings(held); local dropdown = f:control("Caption"); dropdown:OpenMenu()
    assert(f.Stub.MenuItem(f.Stub.menus[#f.Stub.menus], "Original choice"))
    local before = updates; f:event("PLAYER_MONEY", false, 0)
    equal(updates, before + 1); equal(events, 1)
    f:event("PLAYER_XP_UPDATE"); equal(events, 1)
    f:tick(1.1); equal(updates, before + 2)
end)

check("registration during create defers structure without orphaning another provider's frame", function()
    local f = fixture(); local registered, creates, destroys, contexts = false, 0, 0, {}
    Menubar:RegisterWidgetType({ id = "outside-a", name = "A", defaults = {},
        create = function()
            if registered then return end
            registered = true
            Menubar:RegisterWidgetType({ id = "outside-c", name = "C", update = function(widget) widget:SetText("C") end })
        end, update = function(widget) widget:SetText("A") end })
    Menubar:RegisterWidgetType({ id = "outside-b", name = "B", defaults = {},
        create = function(widget) creates = creates + 1; contexts[#contexts + 1] = widget end,
        destroy = function() destroys = destroys + 1 end,
        update = function(widget) widget:SetText("B") end })
    f.host:Start(); f:tick(0)
    equal(creates, 1); equal(destroys, 0); equal(#contexts, 1); equal(contexts[1].frame:IsVisible(), true)
    local found = 0; for _ in pairs(f.host.runtime) do found = found + 1 end; equal(found, 3)
    f.host:RemoveWidget(contexts[1].id); equal(destroys, 1); equal(contexts[1].frame:IsVisible(), false)
end)

check("self refresh is coalesced and structural requests cannot recurse through an update", function()
    local f = fixture(); local depth, maximum, updates, held = 0, 0, 0
    Menubar:RegisterWidgetType({ id = "outside-reentrant", name = "Reentrant", interval = false,
        defaults = { rebuild = false }, update = function(widget)
            held, depth, updates = widget, depth + 1, updates + 1; maximum = math.max(maximum, depth)
            widget:Refresh()
            if widget.settings.rebuild then Menubar:Rebuild() end
            widget:SetText("Ready"); depth = depth - 1
        end })
    f.host:Start(); equal(updates, 1); equal(maximum, 1)
    held.settings.rebuild = true; held:Refresh(); equal(maximum, 1); assert(updates <= 3)
    local before = updates; f:tick(0); equal(maximum, 1); assert(updates <= before + 2)
    held.settings.rebuild = false; f:tick(0)
end)

check("identical event failures deduplicate across unrelated update success and recover per callback", function()
    local f = fixture(); local fail = "failure one"
    Menubar:RegisterWidgetType({ id = "outside-error", name = "Error", events = { "PLAYER_MONEY" },
        update = function(widget) widget:SetText("Ready") end,
        event = function() if fail then error(fail, 0) end end })
    f.host:Start(); local before = #f.Stub.messages
    for _ = 1, 3 do f:event("PLAYER_MONEY") end
    equal(#f.Stub.messages, before + 1)
    fail = "failure two"; f:event("PLAYER_MONEY"); equal(#f.Stub.messages, before + 2)
    fail = false; f:event("PLAYER_MONEY")
    fail = "failure two"; f:event("PLAYER_MONEY"); equal(#f.Stub.messages, before + 3)
end)

check("retained contexts activate before updates and invalidate old callbacks across disable and re-enable", function()
    local f = fixture(); local creates, activates, deactivates, destroys, actions, held, old = 0, 0, 0, 0, 0
    Menubar:RegisterWidgetType({ id = "outside-retained", name = "Retained", retainOnDisable = true, interval = false,
        defaults = {}, create = function(widget) held = widget; creates = creates + 1 end,
        activate = function(widget) activates = activates + 1; widget.outsideActive = true end,
        deactivate = function(widget) deactivates = deactivates + 1; widget.outsideActive = false end,
        destroy = function() destroys = destroys + 1 end,
        update = function(widget) assert(widget.outsideActive); widget:SetText("Ready") end })
    f.host:Start(); equal(creates, 1); equal(activates, 1)
    old = held:GuardCallback(function() actions = actions + 1 end); old(); equal(actions, 1)
    f:enabled(held, false); equal(deactivates, 1); equal(destroys, 0); old(); equal(actions, 1)
    f:enabled(held, true); equal(f.host.runtime[held.id], held); equal(creates, 1); equal(activates, 2)
    old(); equal(actions, 1)
    held:GuardCallback(function() actions = actions + 1 end)(); equal(actions, 2)
    f.host:Rebuild(); equal(activates, 2); equal(deactivates, 1)
    f.host:RemoveWidget(held.id); equal(deactivates, 2); equal(destroys, 1); old(); equal(actions, 2)
end)

check("failed activation retries activation before update and failed cleanup preserves the original diagnostic", function()
    local f = fixture(); local held, updates, activates, deactivates, destroys = nil, 0, 0, 0, 0
    Menubar:RegisterWidgetType({ id = "outside-activation", name = "Activation", retainOnDisable = true,
        defaults = { ready = false, failUpdate = false }, create = function(widget) held = widget end,
        activate = function(widget) activates = activates + 1; assert(widget.settings.ready, "activation not ready") end,
        update = function(widget) updates = updates + 1; if widget.settings.failUpdate then error("original update error", 0) end; widget:SetText("Ready") end,
        deactivate = function() deactivates = deactivates + 1; error("cleanup error", 0) end,
        destroy = function() destroys = destroys + 1 end })
    f.host:Start(); equal(updates, 0); equal(held.failedCallback, "activate")
    held.settings.ready = true; held:Refresh(); equal(activates, 2); equal(updates, 1); equal(held.failed, nil)
    held.settings.failUpdate = true; held:Refresh(); equal(held.failed, "original update error")
    held.instance.enabled = false; f.host:Rebuild()
    equal(deactivates, 1); equal(held.failed, "original update error"); equal(held.failedCallback, "update")
    f.host:RemoveWidget(held.id); equal(destroys, 1)
end)

check("legacy providers keep destroy-on-disable behavior and dormant removal performs terminal cleanup", function()
    local f = fixture(); local creates, destroys, held = 0, 0
    Menubar:RegisterWidgetType({ id = "outside-legacy", name = "Legacy", create = function(widget) held = widget; creates = creates + 1 end,
        update = function(widget) widget:SetText("Ready") end, destroy = function() destroys = destroys + 1 end })
    f.host:Start(); local old = held
    f:enabled(old, false); equal(destroys, 1)
    f:enabled(old, true); equal(creates, 2); assert(held ~= old)
    local updates = held.text; old:Refresh(); equal(held.text, updates)
    f.host:RemoveWidget(held.id); equal(destroys, 2)
end)

check("guarded native callbacks preserve nil returns and isolate failures without resetting other episodes", function()
    local f = fixture(); local held, fail, calls = nil, false, 0
    Menubar:RegisterWidgetType({ id = "outside-callback", name = "Callback", update = function(widget) held = widget; widget:SetText("Ready") end })
    f.host:Start()
    local callback = held:GuardCallback(function(value, last)
        calls = calls + 1
        if fail then error("outside callback error", 0) end
        return nil, value, last, nil
    end)
    local values = { callback("value", false) }; equal(select("#", callback("value", false)), 4)
    equal(values[1], nil); equal(values[2], "value"); equal(values[3], false); equal(values[4], nil)
    local before = #f.Stub.messages
    fail = true; equal(pcall(callback), true); equal(held.failedCallback, "callback"); equal(#f.Stub.messages, before + 1)
    held:Refresh(); callback(); equal(#f.Stub.messages, before + 1)
    held:Refresh(); fail = false; callback(); fail = true; callback(); equal(#f.Stub.messages, before + 2)
    local previous = calls; f.host:RemoveWidget(held.id); callback(); equal(calls, previous)
end)

check("menu callbacks obey native menu dismissal and replacement and reject old settings identities", function()
    local f = fixture(); local held, actions, stale = nil, 0
    Menubar:RegisterWidgetType({ id = "outside-menu", name = "Menu", defaults = { value = 0 },
        update = function(widget) held = widget; widget:SetText(widget.settings.value) end,
        contextMenu = function(widget, menu)
            stale = widget:MenuCallback(function() actions = actions + 1; widget.settings.value = widget.settings.value + 1; widget:Refresh() end)
            menu:CreateButton("Outside increment", stale)
        end })
    f.host:Start(); equal(pcall(held.MenuCallback, held, function() end), false)
    IsShiftKeyDown = function() return true end; held.frame:Click("LeftButton")
    equal(pcall(held.MenuCallback, held, function() end), false, "An open menu alone is not a generation scope")
    local old = stale; old(); equal(actions, 1); equal(held.label:GetText(), "1")
    Menu.GetManager():CloseMenus(); old(); equal(actions, 1)
    held.frame:Click("LeftButton"); local second = stale
    MenuUtil.CreateContextMenu(UIParent, function(_, menu) menu:CreateButton("Foreign action", function() end) end)
    second(); equal(actions, 1)
    held.frame:Click("LeftButton"); local current = stale
    held.instance.settings = { value = 20 }; f.host:Rebuild(); current(); equal(actions, 1)
    equal(held.settings.value, 20)
end)

check("replacing retained settings reactivates current handlers while old callbacks stay invalid", function()
    local f = fixture(); local held, current, activates, deactivates = nil, nil, 0, 0
    Menubar:RegisterWidgetType({ id = "outside-rebind", name = "Rebind", retainOnDisable = true,
        defaults = { count = 0 }, create = function(widget) held = widget end,
        activate = function(widget)
            activates = activates + 1
            current = widget:GuardCallback(function() widget.settings.count = widget.settings.count + 1; widget:Refresh() end)
        end,
        deactivate = function() deactivates = deactivates + 1 end,
        update = function(widget) widget:SetText(widget.settings.count) end })
    f.host:Start(); local old = current; old(); equal(held.settings.count, 1)
    f:settings(held); f:control("Reset this widget's settings"):Click()
    equal(activates, 2); equal(deactivates, 1); equal(held.settings.count, 0)
    old(); equal(held.settings.count, 0)
    current(); equal(held.settings.count, 1); equal(held.label:GetText(), "1")
end)

check("restricted boolean scheduling and retention declarations are rejected before registration", function()
    local f = fixture()
    for _, field in ipairs({ "interval", "retainOnDisable" }) do
        local value = true
        if field == "interval" then value = false end
        issecretvalue = function(candidate) return rawequal(candidate, value) end
        local declaration = { id = "outside-restricted", name = "Restricted", defaults = {} }
        declaration[field] = value
        equal(pcall(Menubar.RegisterWidgetType, Menubar, declaration), false)
        equal(f.host.types[declaration.id], nil)
    end
    issecretvalue = nil
    equal(pcall(Menubar.RegisterWidgetType, Menubar,
        { id = "outside-events", name = "Events", events = false }), false)
end)

check("event-only providers do not poll but retain initial event explicit and visible-resume refreshes", function()
    local f = fixture(); local updates, held = 0
    Menubar:RegisterWidgetType({ id = "outside-event-only", name = "Event only", interval = false, events = { "PLAYER_MONEY" },
        update = function(widget, elapsed) held = widget; updates = updates + 1; equal(elapsed, nil); widget:SetText("Ready") end })
    f.host:Start(); equal(updates, 1)
    f:tick(100); f:tick(100); equal(updates, 1)
    f:event("PLAYER_MONEY"); equal(updates, 2); held:Refresh(); equal(updates, 3)
    f.host.bars.top:Hide(); f:tick(100); equal(updates, 3)
    f.host.bars.top:Show(); f:tick(0.01); equal(updates, 4); f:tick(100); equal(updates, 4)
end)

print(passed .. " outside-author integration checks passed")
