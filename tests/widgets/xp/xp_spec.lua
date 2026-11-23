local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local provider
Menubar = { RegisterWidgetType = function(_, definition) provider = definition end }
local level, current, maximum, rested, resting, restState = 20, 250, 1000, 300, true, 1
local restricted = setmetatable({}, {
    __lt = function() error("restricted comparison") end,
    __le = function() error("restricted comparison") end,
    __tostring = function() error("restricted display") end,
})
issecretvalue = function(value) return rawequal(value, restricted) end
UnitLevel = function(unit) equal(unit, "player"); return level end
UnitXP = function(unit) equal(unit, "player"); return current end
UnitXPMax = function(unit) equal(unit, "player"); return maximum end
GetXPExhaustion = function() return rested end
IsResting = function() return resting end
GetRestState = function() return restState end
dofile("src/menubar-xp/XP.lua")

local function render(overrides)
    local options = {}
    for key, value in pairs(provider.defaults) do options[key] = value end
    -- Numeric/square rendering remains an explicitly selectable alternative.
    options.display, options.gaugeStyle = "percent", "square"
    for key, value in pairs(overrides or {}) do options[key] = value end
    local widget = { settings = options }
    function widget:SetText(text) self.text = text end
    function widget:SetGauge(value, maximum, color, text, width, atlas, bonus)
        self.gauge = { value = value, maximum = maximum, color = color, text = text, width = width, atlas = atlas, bonus = bonus }
        self.text = text
    end
    function widget:HideGauge() self.gauge = nil; self.hideCalls = (self.hideCalls or 0) + 1 end
    provider.update(widget)
    return widget.text, widget
end
local function tooltip(widget)
    local tip = { lines = {}, rows = {} }
    function tip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tip:AddDoubleLine(key, value) self.rows[key] = value end
    provider.tooltip(widget, tip)
    return tip
end
local function hasLine(tip, expected)
    for _, line in ipairs(tip.lines) do if line == expected then return true end end
    return false
end
local function test(name, callback)
    callback(); passed = passed + 1; print("PASS " .. name)
end

test("factory theme-default gauge shows level without a numeric overlay and replaces native XP", function()
    equal(provider.id, "xp")
    local text, widget = render({ display = provider.defaults.display, gaugeStyle = provider.defaults.gaugeStyle })
    equal(text, "Lv 20")
    equal(provider.defaults.presentation, "gauge")
    equal(provider.defaults.gaugeStyle, "theme"); equal(provider.defaults.hideBlizzardXPBar, true)
    equal(widget.gauge.value, 250)
    equal(widget.gauge.maximum, 1000)
    equal(widget.gauge.width, 160)
    equal(provider.events[1], "PLAYER_XP_UPDATE")
end)
test("gauge styles stay independent while XP progress and rested appearance are preserved", function()
    local setting
    for _, candidate in ipairs(provider.settings) do
        if candidate.key == "gaugeStyle" then setting = candidate end
    end
    assert(setting, "gauge style picker is registered")
    equal(setting.label, "Gauge style")
    equal(setting.type, "select")
    equal(#setting.options, 3)
    equal(setting.options[1].value, "theme")
    equal(setting.options[1].label, "Theme default")
    equal(setting.options[2].value, "square")
    equal(setting.options[2].label, "Square")
    equal(setting.options[3].value, "warcraft")
    equal(setting.options[3].label, "Warcraft")
    local _, first = render({ gaugeStyle = "warcraft", display = "fraction", gaugeWidth = 240 })
    local _, second = render()
    equal(first.settings.gaugeStyle, "warcraft")
    equal(second.settings.gaugeStyle, "square")
    local before = first.gauge
    first.settings.gaugeStyle = "square"
    provider.update(first)
    provider.update(second)
    equal(first.settings.gaugeStyle, "square")
    equal(second.settings.gaugeStyle, "square")
    equal(first.gauge.value, before.value)
    equal(first.gauge.maximum, before.maximum)
    equal(first.gauge.text, "Lv 20 250/1000")
    equal(first.gauge.width, 240)
    equal(first.gauge.atlas, "UI-HUD-ExperienceBar-Fill-Rested")
    for channel = 1, 4 do equal(first.gauge.color[channel], before.color[channel]) end
    equal(second.gauge.text, "Lv 20 25.0%")
    equal(second.gauge.width, 160)
    equal(provider.defaults.gaugeStyle, "theme")
end)

test("fraction and remaining displays are exact", function()
    equal(render({ display = "fraction" }), "Lv 20 250/1000")
    equal(render({ display = "remaining", showLevel = false, showLabel = true }), "XP 750 to go")
end)
test("tooltip includes progress remaining and rested status", function()
    local _, widget = render()
    local tip = tooltip(widget)
    equal(tip.rows.Level, "20")
    equal(tip.rows.Progress, "250 / 1000 (25.0%)")
    equal(tip.rows.Complete, nil)
    equal(tip.rows["To next level"], "750")
    equal(tip.rows["Rested bonus XP"], "300")
    equal(tip.rows["Rest status"], "Rested / resting")
    equal(tip.rows.Resting, nil)
    equal(tip.rows["XP bonus state"], nil)
end)
test("no rested pool means zero while the independent rest state and location stay clear", function()
    rested, resting = nil, false
    local _, widget = render()
    local tip = tooltip(widget)
    equal(tip.rows["Rested bonus XP"], "0")
    equal(tip.rows["Rest status"], "Rested / not resting")
    rested, resting = 300, true
end)
test("zero requirement avoids division and does not assume a level cap", function()
    current, maximum = 0, 0
    equal(render(), "Lv 20")
    equal(render({ showLevel = false }), "")
    local _, widget = render()
    equal(widget.gauge.value, 0)
    equal(widget.gauge.maximum, 1)
    assert(hasLine(tooltip(widget), "No next-level progress reported."))
    current, maximum = 250, 1000
end)
test("zero progress and completed levels display correctly", function()
    current = 0; equal(render(), "Lv 20 0.0%")
    current = 1000; equal(render(), "Lv 20 100.0%")
    current = 250
end)
test("level transitions do not fabricate percentages from inconsistent data", function()
    current = 2000
    equal(render(), "Lv 20 --")
    current = 250
end)
test("secret XP is refused before formatting or comparisons", function()
    current = restricted
    equal(render(), "Lv 20 --")
    local _, widget = render()
    assert(hasLine(tooltip(widget), "Experience is unavailable."))
    current = 250
end)
test("restricted auxiliary fields remain unavailable without losing XP", function()
    rested, resting = restricted, restricted
    equal(render(), "Lv 20 25.0%")
    local _, widget = render()
    local tip = tooltip(widget)
    equal(tip.rows["Rested bonus XP"], "Unavailable")
    equal(tip.rows["Rest status"], "Rested / resting unknown")
    rested, resting = 300, true
end)
test("restricted API errors produce an unavailable display", function()
    local previous = UnitXP
    UnitXP = function() error("client restricted this call") end
    equal(render(), "Lv 20 --")
    UnitXP = previous
end)
test("optional missing APIs and older clients without secret helper work", function()
    local previousRested, previousResting, previousSecret = GetXPExhaustion, IsResting, issecretvalue
    GetXPExhaustion, IsResting, issecretvalue = nil, nil, nil
    equal(render(), "Lv 20 25.0%")
    local _, widget = render()
    equal(tooltip(widget).rows["Rest status"], "Rested / resting unknown")
    GetXPExhaustion, IsResting, issecretvalue = previousRested, previousResting, previousSecret
end)
test("instances preserve their own display options", function()
    local _, first = render({ display = "fraction" })
    local _, second = render({ showLevel = false })
    first.settings.showLabel = true
    provider.update(first); provider.update(second)
    equal(first.text, "XP Lv 20 250/1000")
    equal(second.text, "25.0%")
    equal(provider.defaults.showLabel, false)
end)

test("native rested XP atlas is blue away from an inn", function()
    rested, resting, restState = 300, false, 1
    local _, widget = render()
    equal(widget.gauge.atlas, "UI-HUD-ExperienceBar-Fill-Rested")
    equal(tooltip(widget).rows["Rest status"], "Rested / not resting")
    -- GetRestState is authoritative even when the client has no bonus-pool value.
    rested = nil
    local _, noPool = render()
    equal(noPool.gauge.atlas, "UI-HUD-ExperienceBar-Fill-Rested")
    rested, resting = 300, true
end)

test("inn location never turns an un-rested XP bar blue", function()
    rested, resting, restState = nil, true, 2
    local _, widget = render()
    equal(widget.gauge.atlas, "UI-HUD-ExperienceBar-Fill-Experience")
    equal(tooltip(widget).rows["Rest status"], "Normal / resting")
    rested, restState = 300, 1
end)

test("public client colour constants supply atlas-unavailable fallback colours", function()
    EXHAUSTION_COLORS = { [1] = { r = 0.1, g = 0.2, b = 0.9 }, [2] = { r = 0.6, g = 0.1, b = 0.7 } }
    local _, widget = render()
    equal(widget.gauge.color[1], 0.1)
    equal(widget.gauge.color[4], 1)
    restState = 2
    local _, normal = render()
    equal(normal.gauge.color[1], 0.6)
    restState, EXHAUSTION_COLORS = 1, nil
end)

test("restricted rest state never guesses colour from resting location or bonus pool", function()
    restState = restricted
    local _, widget = render()
    equal(widget.gauge.atlas, nil)
    equal(widget.gauge.color[1], 0.5)
    equal(tooltip(widget).rows["Rest status"], "Unavailable / resting")
    restState = 1
end)

test("legacy API fallback uses only a readable bonus pool", function()
    local previous = GetRestState
    GetRestState = nil
    rested = 50
    local _, widget = render()
    equal(widget.gauge.atlas, "UI-HUD-ExperienceBar-Fill-Rested")
    rested = nil
    local _, normal = render()
    equal(normal.gauge.atlas, "UI-HUD-ExperienceBar-Fill-Experience")
    rested = restricted
    local _, unknown = render()
    equal(unknown.gauge.atlas, nil)
    rested, GetRestState = 300, previous
end)

test("text presentation clears the gauge before using ordinary host text", function()
    local _, widget = render()
    assert(widget.gauge)
    widget.settings.presentation = "text"
    provider.update(widget)
    equal(widget.gauge, nil)
    equal(widget.hideCalls, 1)
    equal(widget.text, "Lv 20 25.0%")
end)

test("overlay values can be hidden independently of character level", function()
    local _, levelOnly = render({ display = "none" })
    equal(levelOnly.text, "Lv 20")
    local _, empty = render({ display = "none", showLevel = false })
    equal(empty.text, "")
    equal(empty.gauge.value, 250)
    current = restricted
    local _, unavailable = render({ display = "none", showLevel = false })
    equal(unavailable.text, "--")
    equal(unavailable.gauge.value, 0)
    equal(unavailable.gauge.maximum, 1)
    current = 250
end)

test("gauge dimensions reject corrupt values and remain per instance", function()
    local _, first = render({ gaugeWidth = 240 })
    local _, second = render({ gaugeWidth = -1 })
    equal(first.gauge.width, 240)
    equal(second.gauge.width, 160)
    equal(provider.defaults.gaugeWidth, 160)
end)

test("malformed colour constants and missing rest APIs cannot leak invalid components", function()
    EXHAUSTION_COLORS = { [1] = { r = restricted, g = 0.2, b = 0.9 } }
    local _, widget = render()
    equal(widget.gauge.color[1], 0)
    equal(widget.gauge.color[3], 0.88)
    local previous = GetRestState
    GetRestState = function() error("restricted") end
    local _, unknown = render()
    equal(unknown.gauge.atlas, nil)
    equal(unknown.gauge.color[1], 0.5)
    GetRestState, EXHAUSTION_COLORS = previous, nil
end)

test("positive rested XP is forwarded as a separate lighter preview without advancing earned progress", function()
    local _, widget = render()
    equal(widget.gauge.value, 250)
    equal(widget.gauge.maximum, 1000)
    equal(widget.gauge.bonus.value, 300)
    equal(widget.gauge.bonus.atlas, "UI-HUD-ExperienceBar-Fill-Prediction")
    equal(widget.gauge.atlas, "UI-HUD-ExperienceBar-Fill-Rested")
    local color = widget.gauge.bonus.color
    assert(color[1] > widget.gauge.color[1] and color[2] > widget.gauge.color[2])
    equal(color[4], 1)
    rested = 2000
    provider.update(widget)
    equal(widget.gauge.bonus.value, 2000, "The core owns current-level clipping of a readable bonus pool")
    equal(widget.gauge.value, 250)
    rested = 300
end)

test("each XP instance reuses its own rested descriptor across updates and gauge styles", function()
    local _, first = render()
    local _, second = render({ gaugeStyle = "warcraft" })
    local descriptor, color = first.gauge.bonus, first.gauge.bonus.color
    assert(descriptor ~= second.gauge.bonus)
    for index = 1, 64 do
        rested = 300 - index
        first.settings.gaugeStyle = index % 2 == 0 and "square" or "warcraft"
        provider.update(first)
        equal(first.gauge.bonus, descriptor)
        equal(first.gauge.bonus.color, color)
        equal(first.gauge.bonus.value, rested)
    end
    equal(second.gauge.bonus.value, 300)
    rested = 300
end)

test("zero missing restricted and malformed rested pools clear the preview without guessing", function()
    local _, widget = render()
    local previous = GetXPExhaustion
    local function clear(value)
        rested = value; provider.update(widget); equal(widget.gauge.bonus, nil)
        equal(widget.gauge.value, 250)
    end
    clear(0); clear(nil); clear(restricted); clear(-1); clear(1.5); clear(math.huge); clear(0 / 0)
    GetXPExhaustion = nil; provider.update(widget); equal(widget.gauge.bonus, nil)
    GetXPExhaustion = function() error("rested pool temporarily unavailable", 0) end
    provider.update(widget); equal(widget.gauge.bonus, nil)
    GetXPExhaustion, rested = previous, 300
    provider.update(widget); equal(widget.gauge.bonus.value, 300)
end)

test("unknown completed and zero-requirement XP do not retain a rested preview", function()
    local _, widget = render()
    current = restricted; provider.update(widget); equal(widget.gauge.bonus, nil)
    current = 2000; provider.update(widget); equal(widget.gauge.bonus, nil)
    current = 1000; provider.update(widget); equal(widget.gauge.bonus, nil)
    current, maximum = 0, 0; provider.update(widget); equal(widget.gauge.bonus, nil)
    current, maximum = 250, 1000; provider.update(widget); equal(widget.gauge.bonus.value, 300)
end)

test("a readable bonus pool remains separate from rest-state and resting-location colour decisions", function()
    restState, resting, rested = restricted, false, 150
    local _, unknownState = render()
    equal(unknownState.gauge.bonus.value, 150)
    equal(unknownState.gauge.atlas, nil)
    restState, resting, rested = 2, true, 0
    local _, innOnly = render()
    equal(innOnly.gauge.bonus, nil)
    equal(innOnly.gauge.atlas, "UI-HUD-ExperienceBar-Fill-Experience")
    restState, resting, rested = 1, true, 300
end)

test("text mode removes the rested gauge and returning to gauge mode uses the latest pool", function()
    local _, widget = render()
    local descriptor = widget.gauge.bonus
    widget.settings.presentation = "text"; provider.update(widget)
    equal(widget.gauge, nil)
    rested = 50; widget.settings.presentation = "gauge"; provider.update(widget)
    equal(widget.gauge.bonus, descriptor)
    equal(widget.gauge.bonus.value, 50)
    equal(widget.gauge.value, 250)
    rested = 300
end)
print(string.format("%d XP tests passed", passed))
