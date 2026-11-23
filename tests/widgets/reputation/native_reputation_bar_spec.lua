-- Reputation-only and cross-provider ownership through the shared native fixture.
local root = REPO_ROOT or "."
local fixture = dofile(root .. "/tests/native_status_bar_fixture.lua")
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function repSuppressed(f)
    equal(f.reputation.alpha, 0); equal(f.reputation.mouse, false)
    equal(f.chrome.alpha, 0); equal(f.firstDivider.alpha, 0); f:assertShell()
end
local function repRestored(f)
    equal(f.reputation.alpha, 0.9); equal(f.reputation.mouse, true)
    equal(f.chrome.alpha, 0.7); equal(f.firstDivider.alpha, 0.4); f:assertShell()
end

check("Reputation controls native presentation without the XP addon and exposes a reversible checkbox", function()
    local f = fixture(false, { xp = false }); f:select("reputation")
    assert(f.providers.xp == nil)
    local definition = f.providers.reputation
    equal(definition.defaults.hideBlizzardReputationBar, true)
    equal(definition.legacyDefaults.hideBlizzardReputationBar, false)
    local found
    for _, setting in ipairs(definition.settings) do
        if setting.key == "hideBlizzardReputationBar" then found = setting end
    end
    assert(found); equal(found.type, "toggle"); equal(found.label, "Hide Blizzard reputation bar")
    local widget = f:widget(true, "reputation"); f:update(widget); repSuppressed(f)
    equal(f.xp.alpha, 0.8); equal(f.xp.mouse, true); equal(f.exhaustionTick.alpha, 0.6)
    widget.settings.hideBlizzardReputationBar = false; f:update(widget); repRestored(f)
    equal(f.reputation.shown, true); equal(f.xp.shown, false)
end)

check("duplicate Reputation owners survive reset removal and renderer failure independently", function()
    local f = fixture(); f:select("reputation")
    local first, second = f:widget(true, "reputation"), f:widget(true, "reputation")
    f:update(first); f:update(second); repSuppressed(f)
    first.renderError = "reputation render failed"
    local ok, reason = pcall(first.definition.update, first)
    equal(ok, false); assert(tostring(reason):find(first.renderError, 1, true)); repSuppressed(f)
    first.definition.reset(first, "update"); first.definition.deactivate(first); repSuppressed(f)
    second.definition.destroy(second); repRestored(f)
    first.renderError = nil; f:update(first); repSuppressed(f)
    first.definition.destroy(first); first.definition.destroy(first); repRestored(f)
end)

check("XP and Reputation release either order without restoring the remaining owner's chrome", function()
    for _, firstKind in ipairs({ "xp", "reputation" }) do
        local f = fixture(); f:select(firstKind == "xp" and "reputation" or "experience")
        local widgets = { xp = f:widget(true), reputation = f:widget(true, "reputation") }
        f:update(widgets.xp); f:update(widgets.reputation)
        equal(f.xp.alpha, 0); equal(f.reputation.alpha, 0); equal(f.chrome.alpha, 0)
        widgets[firstKind].definition.destroy(widgets[firstKind])
        local remaining = firstKind == "xp" and "reputation" or "xp"
        equal(remaining == "xp" and f.xp.alpha or f.reputation.alpha, 0)
        equal(f.chrome.alpha, 0); equal(f.firstDivider.alpha, 0)
        widgets[remaining].definition.destroy(widgets[remaining])
        equal(f.xp.alpha, 0.8); equal(f.reputation.alpha, 0.9); equal(f.chrome.alpha, 0.7)
        equal(f.xp.mouse, true); equal(f.reputation.mouse, true); equal(#f.monitors, 1); f:assertShell()
    end
end)

check("native Show Hide transitions restore untargeted chrome before shownBarIndex catches up", function()
    local f = fixture(); local widget = f:widget(true, "reputation")
    f.container.shownBarIndex = 1
    f:update(widget); equal(f.chrome.alpha, 0.7)
    f.xp:Hide(); f.reputation:Show() -- Native callbacks precede the index assignment.
    equal(f.container.shownBarIndex, 1); equal(f.chrome.alpha, 0)
    f.container.shownBarIndex = 2
    f.reputation:Hide(); f.xp:Show()
    equal(f.container.shownBarIndex, 2); equal(f.chrome.alpha, 0.7)
    equal(f.xp.alpha, 0.8); equal(f.reputation.alpha, 0)
    widget.definition.destroy(widget); repRestored(f)
end)

check("an unmasked or unreadable shown bar conservatively retains shared chrome", function()
    for _, state in ipairs({ "shown", "missing", "restricted" }) do
        local f = fixture(); f.reputation:Show() -- Deliberate two-shown transition state.
        if state == "missing" then f.reputation.IsShown = function() return nil end
        elseif state == "restricted" then f.reputation.IsShown = function() return f.restricted end end
        local widget = f:widget(true); f:update(widget)
        equal(f.xp.alpha, 0); equal(f.xp.mouse, false)
        equal(f.chrome.alpha, 0.7); equal(f.firstDivider.alpha, 0.4)
        equal(f.reputation.alpha, 0.9); equal(f.reputation.mouse, true)
        widget.definition.destroy(widget); equal(f.xp.alpha, 0.8); f:assertShell()
    end
end)

check("a failed target input mask neither unmasks another target nor conceals its required chrome", function()
    local f = fixture(); f.reputation:Show()
    local first, second = f:widget(true), f:widget(true, "reputation")
    local enable = f.reputation.EnableMouse
    f.reputation.EnableMouse = function() return false end
    f:update(first); f:update(second)
    equal(f.xp.alpha, 0); equal(f.reputation.alpha, 0.9); equal(f.reputation.mouse, true)
    equal(f.chrome.alpha, 0.7)
    f.reputation.EnableMouse = enable; f:tick(0.3)
    equal(f.xp.alpha, 0); equal(f.reputation.alpha, 0); equal(f.chrome.alpha, 0)
    first.definition.destroy(first)
    equal(f.xp.alpha, 0.8); equal(f.reputation.alpha, 0); equal(f.chrome.alpha, 0.7)
    second.definition.destroy(second); repRestored(f)
end)

check("Reputation discovery stays pending until its enum and manager are available", function()
    local f = fixture(true, { xp = false }); f:select("reputation")
    local widget = f:widget(true, "reputation"); f:update(widget)
    equal(f.reputation.alpha, 0.9)
    assert(f.env.Menubar.NativeStatusBars:GetMessage("reputation"))
    f.env.StatusTrackingBarManager = f.manager
    f.env.StatusTrackingBarInfo.BarsEnum.Reputation = nil
    f:event("ADDON_LOADED"); equal(f.reputation.alpha, 0.9)
    f.env.StatusTrackingBarInfo.BarsEnum.Reputation = 2
    f:event("ADDON_LOADED"); repSuppressed(f)
    widget.definition.destroy(widget); repRestored(f)
end)

check("Reputation permission and pending alpha restoration never leave an invisible input surface", function()
    local f = fixture(false, { xp = false }); f:select("reputation")
    local widget = f:widget(true, "reputation")
    f.reputation.CanChangeProtectedState = function() return f.restricted end
    f:update(widget); repRestored(f)
    f.reputation.CanChangeProtectedState = function() return true end
    f:event("PLAYER_REGEN_ENABLED"); repSuppressed(f)
    local setAlpha = f.reputation.SetAlpha
    f.reputation.SetAlpha = function(self, value) if value == 0.9 then return false end; return setAlpha(self, value) end
    widget.settings.hideBlizzardReputationBar = false; f:update(widget)
    equal(f.reputation.alpha, 0); equal(f.reputation.mouse, false)
    f.reputation.SetAlpha = setAlpha; f:tick(0.3); repRestored(f)
    equal(f.monitors[1]:IsShown(), false)
end)

check("missing shared service keeps old API-v1 hosts rendering and offers an update-Core hint", function()
    for _, kind in ipairs({ "xp", "reputation" }) do
        local f = fixture(); f.env.Menubar.NativeStatusBars = nil
        local widget = f:widget(true, kind)
        local effects = #f.effects; f:update(widget)
        assert(widget.gauge); equal(#f.effects, effects); equal(#f.monitors, 0)
        local lines = {}
        widget.definition.tooltip(widget, {
            AddLine = function(_, line) lines[#lines + 1] = line end,
            AddDoubleLine = function() end,
        })
        assert(table.concat(lines, "\n"):find("Update Menubar", 1, true))
        widget.definition.destroy(widget); f:assertShell()
    end
end)

check("choosing the widget faction never changes the native watched faction", function()
    local f = fixture(false, { xp = false }); f:select("reputation")
    local widget = f:widget(true, "reputation"); widget.settings.factionID = 99
    f:update(widget); equal(widget.reputationState.factionID, 99)
    equal(f.watchedFactionID, 72); equal(f.factionWrites, 0); repSuppressed(f)
    widget.definition.destroy(widget); repRestored(f)
end)

print(passed .. " native Reputation/shared status-bar tests passed")
