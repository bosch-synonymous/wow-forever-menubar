-- Run from the repository root: lua tests/time_spec.lua
local passed = 0
local function equal(actual, expected, message)
    assert(actual == expected,
        (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local provider
Menubar = {
    RegisterWidgetType = function(_, definition)
        assert(not provider, "provider must register exactly once")
        provider = definition
    end,
}

local localTime = { hour = 20, min = 3, sec = 7 }
local utcTime = { hour = 10, min = 33, sec = 7 }
local serverHour, serverMinute = 14, 8
local secret = setmetatable({}, {
    __lt = function() error("restricted clock value was compared") end,
    __le = function() error("restricted clock value was compared") end,
    __index = function() error("restricted calendar was indexed") end,
    __tostring = function() error("restricted clock value was formatted") end,
})
issecretvalue = function(value) return rawequal(value, secret) end
date = function(format)
    if format == "*t" then
        return localTime
    end
    assert(format == "!*t", "UTC must be requested explicitly")
    return utcTime
end
GetGameTime = function()
    return serverHour, serverMinute
end

dofile("src/menubar-time/Time.lua")

local function settings(overrides)
    local result = {}
    for key, value in pairs(provider.defaults) do
        result[key] = value
    end
    for key, value in pairs(overrides or {}) do
        result[key] = value
    end
    return result
end

-- Variable glyph widths (and one kerned pair) catch the moving-width bug that a
-- monospace test double would hide. Custom faces/sizes change the measurement.
local glyphWidths = { ["0"] = 8, ["1"] = 3, ["2"] = 7, ["3"] = 6, ["4"] = 8,
    ["5"] = 7, ["6"] = 8, ["7"] = 6, ["8"] = 9, ["9"] = 8,
    [":"] = 2, [" "] = 3, ["-"] = 6, A = 8, P = 7, M = 10 }
local function textWidth(text, path, size, flags)
    local total = 0
    for index = 1, #text do
        local letter = text:sub(index, index)
        total = total + ((path == "Placeholder.ttf" and letter == "-") and 20 or glyphWidths[letter] or 7)
    end
    if text:find("11", 1, true) then total = total + 0.75 end
    local face = path == "Wide.ttf" and 1.4 or 1
    if flags == "BOLD" then face = face * 1.12 end
    return total * (size or 12) / 12 * face
end
local function render(options, font, prepare)
    local widget = { settings = settings(options), measurementCount = 0, measuringRegions = 0 }
    local function fontString(measuring)
        local label = { path = "Default.ttf", size = 12, flags = "", text = "" }
        function label:GetFont() return self.path, self.size, self.flags end
        function label:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags; return true end
        function label:SetText(text) self.text = text end
        function label:GetText() return self.text end
        function label:GetStringWidth()
            if measuring then widget.measurementCount = widget.measurementCount + 1 end
            return textWidth(self.text, self.path, self.size, self.flags)
        end
        function label:Hide() self.hidden = true end
        function label:Show() self.hidden = false end
        function label:SetWordWrap() end
        function label:SetAllPoints() end
        return label
    end
    widget.label = fontString(false)
    if font then widget.label:SetFont(unpack(font)) end
    widget.frame = { CreateFontString = function()
        widget.measuringRegions = widget.measuringRegions + 1
        return fontString(true)
    end }
    function widget:SetWidth(width)
        self.customWidth, self.width = width, width
    end
    function widget:SetText(text)
        self.text = text
        self.label:SetText(text)
        self.width = self.customWidth or math.max(18, self.label:GetStringWidth() + 8)
    end
    if prepare then prepare(widget) end
    provider.update(widget)
    return widget.text, widget
end

local function test(name, callback)
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

test("registers an independent host provider with stable id", function()
    equal(provider.id, "time")
    equal(provider.interval, 1)
    equal(provider.defaultPlacement.alignment, "right")
    equal(provider.defaults.showSeconds, nil)
    for _, setting in ipairs(provider.settings) do assert(setting.key ~= "showSeconds") end
end)

test("default player clock uses computer local time", function()
    equal(render(), "20:03")
end)

test("UTC clock requests universal time and ignores saved seconds", function()
    equal(render({ zone = "utc", showSeconds = true }), "10:33")
end)

test("midnight and noon have correct twelve hour forms", function()
    local previous = localTime
    localTime = { hour = 0, min = 0, sec = 1 }
    equal(render({ format = "12h", showSeconds = true }), "12:00 AM")
    localTime = { hour = 12, min = 0, sec = 2 }
    equal(render({ format = "12h" }), "12:00 PM")
    localTime = { hour = 23, min = 59, sec = 59 }
    equal(render({ format = "12h" }), "11:59 PM")
    localTime = previous
end)

test("server clock never fabricates seconds", function()
    equal(render({ zone = "server", showSeconds = true }), "14:08")
    equal(render({ zone = "server", showSeconds = true, format = "12h" }), "2:08 PM")
end)

test("optional label distinguishes simultaneous clocks", function()
    equal(render({ zone = "utc", showLabel = true }), "UTC 10:33")
end)

test("clock instances keep separate choices", function()
    local _, first = render({ zone = "local" })
    local _, second = render({ zone = "utc", showSeconds = true })
    first.settings.format = "12h"
    provider.update(first)
    provider.update(second)
    equal(first.text, "8:03 PM")
    equal(second.text, "10:33")
    equal(provider.defaults.format, "24h")
end)

test("missing server API falls back to realm calendar time", function()
    local previous = GetGameTime
    GetGameTime = nil
    C_DateAndTime = { GetCurrentCalendarTime = function()
        return { hour = 6, minute = 9 }
    end }
    equal(render({ zone = "server", showSeconds = true }), "06:09")
    C_DateAndTime = nil
    GetGameTime = previous
end)

test("invalid game time falls back and unavailable data is explicit", function()
    local previousHour, previousMinute = serverHour, serverMinute
    serverHour, serverMinute = -1, 80
    C_DateAndTime = { GetCurrentCalendarTime = function()
        return { hour = 5, minute = 6 }
    end }
    equal(render({ zone = "server" }), "05:06")
    C_DateAndTime = nil
    equal(render({ zone = "server" }), "--:--")
    serverHour, serverMinute = previousHour, previousMinute
end)

test("missing local time stays visibly unavailable", function()
    local previous = date
    date = nil
    equal(render(), "--:--")
    date = previous
end)

test("throwing clock APIs are contained and a public server fallback remains available", function()
    local previousDate, previousGameTime = date, GetGameTime
    date = function() error("date temporarily unavailable") end
    equal(render(), "--:--")
    equal(render({ zone = "utc" }), "--:--")
    GetGameTime = function() error("server time temporarily unavailable") end
    C_DateAndTime = { GetCurrentCalendarTime = function() return { hour = 9, minute = 4 } end }
    equal(render({ zone = "server" }), "09:04")
    C_DateAndTime.GetCurrentCalendarTime = function() error("calendar temporarily unavailable") end
    equal(render({ zone = "server" }), "--:--")
    date, GetGameTime, C_DateAndTime = previousDate, previousGameTime, nil
    equal(render(), "20:03")
end)

test("restricted clock results are neither inspected nor inferred through another API", function()
    local previousDate, previousGameTime = date, GetGameTime
    date = function() return secret end
    equal(render(), "--:--")
    date = function() return { hour = secret, min = 3 } end
    equal(render(), "--:--")
    date = function() return { hour = 20, min = secret } end
    equal(render({ zone = "utc" }), "--:--")
    C_DateAndTime = { GetCurrentCalendarTime = function() return { hour = 9, minute = 4 } end }
    GetGameTime = function() return secret, 8 end
    equal(render({ zone = "server" }), "--:--")
    GetGameTime = function() return 14, secret end
    equal(render({ zone = "server" }), "--:--")
    GetGameTime = nil
    C_DateAndTime.GetCurrentCalendarTime = function() return secret end
    equal(render({ zone = "server" }), "--:--")
    C_DateAndTime.GetCurrentCalendarTime = function() return { hour = 6, minute = secret } end
    equal(render({ zone = "server" }), "--:--")
    date, GetGameTime, C_DateAndTime = previousDate, previousGameTime, nil
end)

test("malformed numeric clock parts never reach formatting", function()
    local previous = localTime
    for _, value in ipairs({ 0 / 0, math.huge, -math.huge, 2.5, "12" }) do
        localTime = { hour = value, min = 3 }
        equal(render(), "--:--")
        localTime = { hour = 20, min = value }
        equal(render(), "--:--")
    end
    localTime = previous
end)

test("invalid stored zone safely selects player time", function()
    equal(render({ zone = "removed", showLabel = true }), "Player 20:03")
end)

test("tooltip compares all three zones at minute precision", function()
    local _, widget = render({ zone = "server", showSeconds = true })
    local tip = { lines = {}, rows = {} }
    function tip:AddLine(text)
        self.lines[#self.lines + 1] = text
    end
    function tip:AddDoubleLine(label, text)
        self.rows[#self.rows + 1] = { label, text }
    end
    provider.tooltip(widget, tip)
    equal(tip.lines[1], "Time")
    equal(#tip.rows, 3)
    equal(tip.rows[1][2], "20:03")
    equal(tip.rows[2][2], "14:08")
    equal(tip.rows[3][2], "10:33")
    equal(tip.lines[2], "Adventure never sleeps")
    equal(tip.lines[3], nil)
end)

local function fits(widget)
    local path, size, flags = widget.label:GetFont()
    assert(widget.width >= textWidth(widget.text, path, size, flags) + 8,
        "Fixed clock width must fit its current text and host padding")
end

test("a proportional twenty-four hour clock reserves width before its first wider time", function()
    local previous = localTime
    localTime = { hour = 11, min = 11 }
    local _, widget = render()
    assert(widget.customWidth, "The provider must reserve a fixed width through the host")
    local reserved, measured = widget.width, widget.measurementCount
    local narrow = textWidth(widget.text, widget.label:GetFont())
    for hour = 0, 23 do
        for minute = 0, 59 do
            localTime = { hour = hour, min = minute }
            provider.update(widget)
            equal(widget.width, reserved)
            fits(widget)
        end
    end
    assert(textWidth("20:08", widget.label:GetFont()) > narrow, "Fixture must have unequal digit widths")
    equal(widget.measurementCount, measured, "Normal minute updates must reuse measured width")
    equal(widget.measuringRegions, 1, "Reuse one hidden measuring region")
    localTime = previous
end)

test("twelve hour clocks keep their width through single-digit hours noon and midnight", function()
    local previous = localTime
    localTime = { hour = 9, min = 59 }
    local _, widget = render({ format = "12h" })
    local reserved, measured = widget.width, widget.measurementCount
    for _, value in ipairs({ { 10, 0, "10:00 AM" }, { 11, 59, "11:59 AM" },
        { 12, 0, "12:00 PM" }, { 23, 59, "11:59 PM" }, { 0, 0, "12:00 AM" }, { 1, 1, "1:01 AM" } }) do
        localTime = { hour = value[1], min = value[2] }
        provider.update(widget)
        equal(widget.text, value[3]); equal(widget.width, reserved); fits(widget)
    end
    equal(widget.measurementCount, measured)
    localTime = previous
end)

test("clock width includes optional zone labels and follows explicit format choices", function()
    local _, widget = render({ showLabel = true })
    local playerWidth = widget.width
    fits(widget)
    widget.settings.zone = "utc"
    provider.update(widget)
    fits(widget)
    assert(widget.width < playerWidth, "Shorter selected labels should reclaim unused width")
    local utcWidth = widget.width
    widget.settings.format = "12h"
    provider.update(widget)
    fits(widget)
    assert(widget.width > utcWidth, "AM/PM format requires its own fixed width")
    widget.settings.showLabel = false
    provider.update(widget)
    fits(widget)
    assert(widget.width < playerWidth, "Removing the label should reclaim its space")
end)

test("an unavailable clock retains enough width for its placeholder and can recover", function()
    local previous = date
    local _, widget = render({ format = "12h", showLabel = true }, { "Placeholder.ttf", 12, "" })
    local reserved = widget.width
    date = nil
    provider.update(widget)
    equal(widget.text, "Player --:--"); equal(widget.width, reserved); fits(widget)
    date = previous
    provider.update(widget)
    equal(widget.width, reserved); fits(widget)
end)

test("changing font face size and style recalculates width and reuses its measuring region", function()
    local _, widget = render({ format = "12h" })
    local previousWidth, previousMeasurements = widget.width, widget.measurementCount
    for _, font in ipairs({ { "Wide.ttf", 12, "" }, { "Wide.ttf", 20, "" }, { "Wide.ttf", 20, "BOLD" } }) do
        widget.label:SetFont(unpack(font))
        provider.update(widget)
        assert(widget.width > previousWidth, "A wider font must receive more space")
        assert(widget.measurementCount > previousMeasurements, "Changed font must be measured")
        fits(widget)
        previousWidth, previousMeasurements = widget.width, widget.measurementCount
        for _ = 1, 10 do provider.update(widget) end
        equal(widget.width, previousWidth); equal(widget.measurementCount, previousMeasurements)
    end
    widget.label:SetFont("Default.ttf", 12, "")
    provider.update(widget)
    assert(widget.width < previousWidth, "Switching back must release the larger font's width")
    fits(widget)
    equal(widget.measuringRegions, 1)
end)

test("simultaneous clocks preserve independent reserved widths and saved settings", function()
    local _, first = render({ format = "12h", showLabel = true })
    local _, second = render({ zone = "utc", format = "24h" }, { "Wide.ttf", 20, "" })
    local secondWidth, secondMeasurements = second.width, second.measurementCount
    first.settings.showLabel, first.settings.format = false, "24h"
    first.label:SetFont("Default.ttf", 10, "")
    provider.update(first); provider.update(second)
    equal(second.width, secondWidth); equal(second.measurementCount, secondMeasurements)
    fits(first); fits(second)
    for key in pairs(first.settings) do
        assert(key == "zone" or key == "format" or key == "showLabel", "Do not persist measured UI state")
    end
end)

test("interrupted measuring setup retains its region and retries it before recovery", function()
    local widget, measure, failing, setupCalls = nil, nil, true, 0
    local ok, reason = pcall(function()
        render(nil, nil, function(current)
            widget = current
            local create = current.frame.CreateFontString
            current.frame.CreateFontString = function(...)
                local region = create(...)
                measure = region
                local configure = region.SetWordWrap
                function region:SetWordWrap(...)
                    setupCalls = setupCalls + 1
                    if failing then error("injected measuring setup failure") end
                    return configure(self, ...)
                end
                return region
            end
        end)
    end)
    assert(not ok and tostring(reason):find("injected measuring setup failure", 1, true))
    equal(widget.clockMeasure, measure)
    equal(widget.measuringRegions, 1)
    assert(measure.hidden, "An incomplete measuring region must remain hidden")
    for _ = 1, 10 do equal(pcall(provider.update, widget), false) end
    equal(widget.clockMeasure, measure); equal(widget.measuringRegions, 1)
    equal(setupCalls, 11)
    failing = false
    provider.update(widget)
    equal(widget.clockMeasure, measure); equal(widget.measuringRegions, 1)
    equal(setupCalls, 12); assert(measure.hidden); fits(widget)
    equal(widget.text, "20:03")
    local measurements = widget.measurementCount
    provider.update(widget)
    equal(setupCalls, 12); equal(widget.measurementCount, measurements)
end)

test("a silently rejected measuring font renders uncached text and recovers on the same region", function()
    local widget, measure, attempts = nil, nil, 0
    local text = render(nil, { "Wide.ttf", 12, "" }, function(current)
        widget = current
        local create = current.frame.CreateFontString
        current.frame.CreateFontString = function(...)
            measure = create(...)
            local setFont = measure.SetFont
            function measure:SetFont(...)
                attempts = attempts + 1
                if attempts == 1 then return false end
                return setFont(self, ...)
            end
            return measure
        end
    end)
    equal(text, "20:03"); fits(widget)
    equal(widget.clockMeasure, measure); equal(widget.measuringRegions, 1)
    equal(widget.clockSizing, nil); equal(widget.customWidth, nil); equal(widget.measurementCount, 0)
    assert(measure.hidden)
    provider.update(widget)
    equal(attempts, 2); equal(widget.clockMeasure, measure); equal(widget.measuringRegions, 1)
    equal(widget.clockSizing.path, "Wide.ttf"); equal(measure:GetFont(), "Wide.ttf")
    equal(widget.text, "20:03"); fits(widget)
    local measurements, width = widget.measurementCount, widget.width
    provider.update(widget)
    equal(attempts, 2); equal(widget.measurementCount, measurements); equal(widget.width, width)
end)

test("the direct time-zone picker preserves format and waits for a host selection before changing zone", function()
    local widget = { settings = { zone = "server", format = "12h", showLabel = true }, text = "Server 2:08 PM" }
    local calls = 0
    function widget:OpenChoiceMenu(key, title)
        equal(key, "zone"); equal(title, "Choose time zone")
        calls = calls + 1
        return true
    end
    equal(provider.click(widget), true)
    equal(calls, 1); equal(widget.settings.zone, "server"); equal(widget.settings.format, "12h"); equal(widget.settings.showLabel, true)
    for _, missing in ipairs({ false, "unsupported", secret }) do
        widget.OpenChoiceMenu = missing
        equal(provider.click(widget), false)
        equal(widget.settings.zone, "server"); equal(widget.text, "Server 2:08 PM")
    end
    widget.OpenChoiceMenu = nil; equal(provider.click(widget), false)
    equal(calls, 1)
end)

print(string.format("%d Time tests passed", passed))
