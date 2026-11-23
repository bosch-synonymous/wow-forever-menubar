-- Native XP presentation ownership through public frame contracts.
-- This does not emulate protected frames, native status-bar layout or taint.
local root = REPO_ROOT or "."
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1
    print("PASS " .. name)
end

local fixture = dofile(root .. "/tests/native_status_bar_fixture.lua")

check("native XP visibility remains untouched for an explicit saved opt-out", function()
    local f = fixture()
    equal(f.provider.defaults.hideBlizzardXPBar, true)
    local option
    for _, setting in ipairs(f.provider.settings) do
        if setting.key == "hideBlizzardXPBar" then option = setting end
    end
    assert(option)
    equal(option.type, "toggle")
    equal(option.label, "Hide Blizzard experience bar")
    f:update(f:widget(false))
    equal(#f.monitors, 0)
    equal(#f.effects, 0)
    f:assertRestored()
end)

check("enabling masks only native XP presentation and disabling restores it", function()
    local f = fixture()
    local widget = f:widget(true)
    f:update(widget)
    f:assertSuppressed()
    equal(f.xp.shown, true)
    equal(f.exhaustionTick.shown, true)
    widget.settings.hideBlizzardXPBar = false
    f:update(widget)
    f:assertRestored()
    equal(f.xp.shown, true)
    equal(f.exhaustionTick.shown, true)
end)

check("duplicate widgets retain suppression until the final request is released", function()
    local f = fixture()
    local first, second, ordinary = f:widget(true), f:widget(true), f:widget(false)
    f:update(first); f:update(second); f:update(ordinary)
    for _ = 1, 4 do f:update(first); f:update(second) end
    f:assertSuppressed()
    f.provider.destroy(first)
    f:assertSuppressed()
    f.provider.destroy(first) -- Cleanup is idempotent, not a decrementing counter.
    f:assertSuppressed()
    second.settings.hideBlizzardXPBar = false
    f:update(second)
    f:assertRestored()
    f.provider.destroy(second); f.provider.destroy(ordinary)
    f:assertRestored()
end)

check("native reputation switching restores shared chrome without changing native selection", function()
    local f = fixture()
    local widget = f:widget(true)
    f:update(widget)
    f:select("reputation")
    f:tick(0.3)
    equal(f.xp.shown, false)
    equal(f.chrome.alpha, 0.7)
    equal(f.firstDivider.alpha, 0.4)
    f:assertNativeSelection()
    f:select("experience")
    f:tick(0.3)
    f:assertSuppressed()
    f:select("reputation")
    widget.settings.hideBlizzardXPBar = false
    f:update(widget)
    equal(f.xp.shown, false) -- Releasing ownership must not force native XP visible.
    f:assertRestored()
end)

check("native divider replacement is masked and all owned alpha is restored", function()
    local f = fixture()
    local widget = f:widget(true)
    f:update(widget)
    local replacement = f.node("replacement divider", 0.35, true)
    f.pool.active = { [replacement] = true }
    f.container:RunScript("OnSizeChanged", 900, 20)
    f:tick(0.3)
    equal(replacement.alpha, 0)
    widget.settings.hideBlizzardXPBar = false
    f:update(widget)
    equal(replacement.alpha, 0.35)
    f:assertRestored()
end)

check("an initially unavailable native manager is discovered while the request stays active", function()
    local f = fixture(true)
    local widget = f:widget(true)
    f:update(widget)
    equal(f.xp.alpha, 0.8)
    f.env.StatusTrackingBarManager = f.manager
    f:event("ADDON_LOADED", "Blizzard_StatusTrackingBarManager")
    f:tick(0.3)
    f:assertSuppressed()
    f.provider.destroy(widget)
    f:assertRestored()
end)

check("existing false mouse state and zero alpha are preserved on release", function()
    local f = fixture()
    f.xp.mouse, f.exhaustionTick.mouse = false, false
    f.xp.alpha, f.exhaustionTick.alpha, f.chrome.alpha, f.firstDivider.alpha = 0, 0, 0, 0
    local widget = f:widget(true)
    f:update(widget)
    widget.settings.hideBlizzardXPBar = false
    f:update(widget)
    equal(f.xp.mouse, false); equal(f.exhaustionTick.mouse, false)
    equal(f.xp.alpha, 0); equal(f.exhaustionTick.alpha, 0)
    equal(f.chrome.alpha, 0); equal(f.firstDivider.alpha, 0)
    f:assertNativeSelection()
end)

check("later native alpha changes become the restoration baseline", function()
    local f = fixture()
    local widget = f:widget(true)
    f:update(widget)
    f.xp:SetAlpha(0.45)
    f.exhaustionTick:SetAlpha(0.25)
    f.chrome:SetAlpha(0.55)
    f.firstDivider:SetAlpha(0.15)
    f:tick(0.3)
    f:assertSuppressed()
    widget.settings.hideBlizzardXPBar = false
    f:update(widget)
    equal(f.xp.alpha, 0.45); equal(f.exhaustionTick.alpha, 0.25)
    equal(f.chrome.alpha, 0.55); equal(f.firstDivider.alpha, 0.15)
    equal(f.xp.mouse, true); equal(f.exhaustionTick.mouse, true)
end)

check("host error reset releases the failed requester and a successful refresh reacquires it", function()
    local f = fixture()
    local widget = f:widget(true)
    f:update(widget)
    widget.renderError = "simulated XP rendering failure"
    local ok, reason = pcall(f.provider.update, widget)
    equal(ok, false)
    assert(tostring(reason):find(widget.renderError, 1, true))
    f.provider.reset(widget, "update")
    f:assertRestored()
    f.provider.reset(widget, "update")
    f:assertRestored()
    widget.renderError = nil
    f:update(widget)
    f:assertSuppressed()
    f.provider.destroy(widget)
    f:assertRestored()
end)

check("a reset requester cannot release another healthy widget's request", function()
    local f = fixture()
    local first, second = f:widget(true), f:widget(true)
    f:update(first); f:update(second)
    f.provider.reset(first, "tooltip")
    f:assertSuppressed()
    f.provider.destroy(second)
    f:assertRestored()
end)

check("protected input changes wait for verified public permission without attempting the setter", function()
    for _, permission in ipairs({ "false", "restricted", "throw", "missing" }) do
        local f = fixture()
        local widget = f:widget(true)
        local attempts, enableMouse = 0, f.xp.EnableMouse
        f.xp.EnableMouse = function(self, enabled)
            attempts = attempts + 1
            return enableMouse(self, enabled)
        end
        if permission == "false" then f.xp.CanChangeProtectedState = function() return false end
        elseif permission == "restricted" then f.xp.CanChangeProtectedState = function() return f.restricted end
        elseif permission == "throw" then f.xp.CanChangeProtectedState = function() error("permission is unavailable") end
        else f.xp.CanChangeProtectedState = nil end
        f:update(widget)
        equal(attempts, 0)
        f:assertRestored()
        f.xp.CanChangeProtectedState = function() return true end
        f:event("PLAYER_REGEN_ENABLED")
        f:assertSuppressed()
        equal(attempts, 1)
        f.provider.destroy(widget)
        f:assertRestored()
    end
end)

check("failed mouse checks or writes never conceal an interactive native XP bar", function()
    for _, failure in ipairs({ "read", "write", "throw" }) do
        local f = fixture()
        local widget = f:widget(true)
        local readMouse, enableMouse = f.xp.IsMouseEnabled, f.xp.EnableMouse
        if failure == "read" then f.xp.IsMouseEnabled = function() return nil end
        elseif failure == "write" then f.xp.EnableMouse = function() return false end
        else f.xp.EnableMouse = function() error("temporarily unavailable input control") end end
        f:update(widget)
        equal(f.xp.mouse, true)
        equal(f.xp.alpha, 0.8)
        f.xp.IsMouseEnabled, f.xp.EnableMouse = readMouse, enableMouse
        f:tick(0.3)
        f:assertSuppressed()
        f.provider.destroy(widget)
        f:assertRestored()
    end
end)

check("an already masked XP bar becomes visible if newly enabled input cannot be suppressed", function()
    local f = fixture()
    local widget = f:widget(true)
    f:update(widget)
    local enableMouse = f.xp.EnableMouse
    f.xp.mouse = true -- A native update or another addon enabled input again.
    f.xp.EnableMouse = function() return false end
    f:tick(0.3)
    equal(f.xp.mouse, true)
    equal(f.xp.alpha, 0.8)
    f.xp.EnableMouse = enableMouse
    f:tick(0.3)
    f:assertSuppressed()
    f.provider.destroy(widget)
    f:assertRestored()
end)

check("pending alpha restoration keeps input suppressed and retries after the option is off", function()
    local f = fixture()
    local widget = f:widget(true)
    f:update(widget)
    local setAlpha = f.xp.SetAlpha
    f.xp.SetAlpha = function(self, value)
        if value == 0.8 then return false end
        return setAlpha(self, value)
    end
    widget.settings.hideBlizzardXPBar = false
    f:update(widget)
    equal(f.xp.alpha, 0)
    equal(f.xp.mouse, false)
    equal(f.exhaustionTick.mouse, false)
    equal(f.exhaustionTick.alpha, 0)
    f.xp.SetAlpha = setAlpha
    f:tick(0.3)
    f:assertRestored()
    equal(f.monitors[1]:IsShown(), false)
end)

check("inactive hooks stop imposing presentation and one monitor is reused", function()
    local f = fixture()
    local widget = f:widget(true)
    f:update(widget)
    local monitors = #f.monitors
    equal(monitors, 1)
    widget.settings.hideBlizzardXPBar = false
    f:update(widget)
    f.xp:SetAlpha(0.9)
    f.xp:Hide(); f.xp:Show()
    f:tick(1)
    equal(f.xp.alpha, 0.9)
    widget.settings.hideBlizzardXPBar = true
    f:update(widget)
    equal(#f.monitors, monitors)
    f:assertSuppressed()
    f.provider.destroy(widget)
    equal(f.xp.alpha, 0.9)
end)

check("steady native polling reuses work storage without allocating frames or repeating hooks", function()
    local f = fixture()
    local widget = f:widget(true)
    f:update(widget)
    local monitor = f.monitors[1]
    local update = monitor.scripts.OnUpdate
    for _ = 1, 32 do update(monitor, 0.25) end
    local effects = #f.effects
    -- Only this isolated test stops/collects Lua GC. Calling the monitor directly
    -- avoids allocating fixture script-dispatch records inside the measurement.
    collectgarbage("collect")
    local before = collectgarbage("count")
    collectgarbage("stop")
    local ok, reason = pcall(function()
        for _ = 1, 2048 do update(monitor, 0.25) end
    end)
    local allocated = collectgarbage("count") - before
    collectgarbage("restart")
    collectgarbage("collect")
    if not ok then error(reason, 0) end
    assert(allocated < 32, "Steady polling allocated " .. allocated .. " KB of temporary Lua storage")
    equal(#f.monitors, 1)
    equal(f.monitors[1], monitor)
    equal(#f.xp.hooks.OnShow, 1)
    equal(#f.xp.hooks.OnHide, 1)
    equal(#f.container.hooks.OnSizeChanged, 1)
    equal(#f.effects, effects)
    f:assertSuppressed()
    f.provider.destroy(widget)
    f:assertRestored()
end)

check("reused native groups discard removed ticks and disappearing containers", function()
    local f = fixture()
    local widget = f:widget(true)
    f:update(widget)
    f.xp.ExhaustionTick = nil
    f.exhaustionTick:SetAlpha(0.3)
    f:tick(0.3)
    -- The removed child is no longer actively masked. Its input restoration
    -- still waits for its borrowed parent, preserving the existing safety rule.
    equal(f.exhaustionTick.alpha, 0.3)
    equal(f.exhaustionTick.mouse, false)
    equal(f.xp.alpha, 0)
    f.exhaustionTick:SetAlpha(0)
    f.xp.ExhaustionTick = f.exhaustionTick
    f:tick(0.3)
    f:assertSuppressed()
    f.manager.barContainers = {}
    f:tick(0.3)
    f:assertRestored()
    f.manager.barContainers = { f.container }
    f:tick(0.3)
    f:assertSuppressed()
    equal(#f.monitors, 1)
    equal(#f.xp.hooks.OnShow, 1)
    equal(#f.container.hooks.OnSizeChanged, 1)
    f.provider.destroy(widget)
    f:assertRestored()
end)

check("replaced native dividers are released from reusable workspace after restoration", function()
    local f = fixture()
    local widget = f:widget(true)
    f:update(widget)
    local previous = f.firstDivider
    local weak = setmetatable({ previous }, { __mode = "v" })
    local replacement = f.node("replacement divider", 0.35, true)
    f.pool.active = { [replacement] = true }
    f:tick(0.3)
    equal(previous.alpha, 0.4)
    equal(replacement.alpha, 0)
    f.firstDivider, previous = nil, nil
    f.effects = {} -- Fixture effect logs deliberately retain their target nodes.
    collectgarbage("collect")
    collectgarbage("collect")
    equal(weak[1], nil)
    f.provider.destroy(widget)
    equal(replacement.alpha, 0.35)
    f:assertNativeSelection()
end)

check("partial native discovery failures clear borrowed workspace references before retry", function()
    local f = fixture()
    local widget = f:widget(true)
    f:update(widget)
    local transient = f.node("partially discovered XP bar", 0.5, true, true)
    setmetatable(transient, { __index = function(_, key)
        if key == "ExhaustionTick" then error("native XP child is temporarily unreadable", 0) end
    end })
    local weak = setmetatable({ transient }, { __mode = "v" })
    f.container.bars[1] = transient
    f:tick(0.3)
    f.container.bars[1], transient = f.xp, nil
    f.effects = {}
    collectgarbage("collect")
    collectgarbage("collect")
    equal(weak[1], nil)
    f:tick(0.3)
    f:assertSuppressed()
    equal(#f.monitors, 1)
    f.provider.destroy(widget)
    f:assertRestored()
end)

print(passed .. " native XP presentation tests passed")
