-- The real host must keep its neighbour's placement stable as the clock ticks.
local root = REPO_ROOT or "."
local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end
local core = MENUBAR_CORE_ROOT or root
if not exists(core .. "/tests/wow_stub.lua") then
    print("SKIP Time host integration: restore Core in this repository or supply MENUBAR_CORE_ROOT.")
    return
end
local Stub = dofile(core .. "/tests/wow_stub.lua")
Stub.Install()
local Region = getmetatable(UIParent)
local originalWidth = Region.GetStringWidth
function Region:GetStringWidth()
    if self.kind ~= "FontString" then return originalWidth(self) end
    local units = 0
    for char in self:GetText():gmatch(".") do
        units = units + (char == "1" and 3 or char == "8" and 9 or char == ":" and 2 or 7)
    end
    return units * (self.fontSize or 12) / 12 * (self.font == "Fonts\\MORPHEUS.TTF" and 1.3 or 1)
end
local hour, minute = 11, 11
date = function() return { hour = hour, min = minute } end
for _, file in ipairs({ "Model.lua", "Identity.lua", "Fonts.lua", "Layout.lua", "Gauge.lua", "Skins.lua", "Core.lua", "UI.lua", "Settings.lua" }) do
    dofile(core .. "/src/menubar-core/" .. file)
end
dofile(root .. "/src/menubar-time/Time.lua")
Menubar:RegisterWidgetType({ id = "clock-neighbour", name = "Clock neighbour", defaults = {},
    defaultPlacement = { bar = "top", alignment = "right" },
    update = function(widget) widget:SetText("Neighbour") end,
})
Menubar:Start()
local clock, neighbour
for _, widget in pairs(Menubar.runtime) do
    if widget.instance.type == "time" then clock = widget
    elseif widget.instance.type == "clock-neighbour" then neighbour = widget end
end
assert(clock and neighbour)
neighbour.instance.order, clock.instance.order = 1, 2
Menubar:Layout()
local passed = 0
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function tick()
    Menubar.eventFrame.scripts.OnUpdate(Menubar.eventFrame, 1)
    assert(not clock.failed, tostring(clock.failed))
end
local function left(widget) return widget.frame.points[1][4] end

check("real host keeps the clock frame and adjacent widget fixed across time updates", function()
    local width, position, nextPosition = clock.width, left(clock), left(neighbour)
    assert(clock.customWidth and clock.clockMeasure)
    assert(not clock.clockMeasure:IsShown(), "Measuring text must never be rendered")
    assert(clock.label:GetStringWidth() < width - 8, "Initial narrow time leaves room for wider digits")
    for _, value in ipairs({ { 20, 8 }, { 23, 59 }, { 0, 0 }, { 11, 11 } }) do
        hour, minute = value[1], value[2]; tick()
        equal(clock.width, width); equal(clock.frame:GetWidth(), width)
        equal(left(clock), position); equal(left(neighbour), nextPosition)
        assert(clock.width >= clock.label:GetStringWidth() + 8)
    end
end)

check("profile rebuilds resize the fixed reservation using the actual new font", function()
    local originalWidget, measure, previousWidth = clock, clock.clockMeasure, clock.width
    local profile = Menubar:GetProfile()
    profile.font, profile.fontSize = "Fonts\\MORPHEUS.TTF", 22
    Menubar:Rebuild()
    equal(Menubar.runtime[clock.id], originalWidget)
    equal(clock.clockMeasure, measure)
    equal(select(1, measure:GetFont()), select(1, clock.label:GetFont()))
    equal(select(2, measure:GetFont()), select(2, clock.label:GetFont()))
    assert(clock.width > previousWidth)
    local width, nextPosition = clock.width, left(neighbour)
    hour, minute = 20, 8; tick()
    equal(clock.width, width); equal(left(neighbour), nextPosition)
    assert(clock.width >= clock.label:GetStringWidth() + 8)
end)

check("host refresh applies format changes once and keeps later AM-PM transitions fixed", function()
    clock.settings.format, clock.settings.showLabel = "12h", true
    hour, minute = 9, 59
    Menubar:RefreshWidget(clock.id); Menubar:Layout()
    equal(clock.text, "Player 9:59 AM")
    local width, nextPosition = clock.width, left(neighbour)
    for _, value in ipairs({ { 10, 0 }, { 11, 59 }, { 12, 0 }, { 0, 0 } }) do
        hour, minute = value[1], value[2]; tick()
        equal(clock.width, width); equal(left(neighbour), nextPosition)
        assert(clock.width >= clock.label:GetStringWidth() + 8)
    end
end)

check("a rejected measuring font stays healthy and the next native poll restores its fixed reservation", function()
    local measure, frames, attempts = clock.clockMeasure, #Stub.frames, 0
    local setFont = measure.SetFont
    measure.SetFont = function(self, ...)
        attempts = attempts + 1
        if attempts == 1 then return false end
        return setFont(self, ...)
    end
    Menubar:GetProfile().fontSize = 30
    Menubar:Rebuild()
    equal(clock.failed, nil); equal(clock.clockSizing, nil); equal(clock.customWidth, nil)
    equal(attempts, 1); equal(clock.clockMeasure, measure); equal(#Stub.frames, frames)
    assert(clock.width >= clock.label:GetStringWidth() + 8)
    assert(not clock.text:find("error", 1, true))
    hour, minute = 23, 58; tick() -- Native OnUpdate, with no manual recovery call.
    equal(attempts, 2); equal(clock.clockMeasure, measure); equal(#Stub.frames, frames)
    equal(clock.customWidth, clock.clockSizing.width)
    equal(select(2, measure:GetFont()), 30)
    assert(clock.width >= clock.label:GetStringWidth() + 8)
    local width, position = clock.width, left(neighbour)
    hour, minute = 0, 0; tick()
    equal(attempts, 2); equal(clock.width, width); equal(left(neighbour), position)
end)

print(passed .. " Time host integration tests passed")
