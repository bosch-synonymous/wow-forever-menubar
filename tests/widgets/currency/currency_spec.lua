-- Run from the repository root: lua tests/currency_spec.lua
local passed = 0
local function equal(actual, expected, message)
    assert(actual == expected,
        (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function coins(text)
    return (text:gsub("(%d)g", "%1|A:coin-gold:14:14:0:0|a")
        :gsub("(%d)s", "%1|A:coin-silver:14:14:0:0|a")
        :gsub("(%d)c", "%1|A:coin-copper:14:14:0:0|a"))
end

local provider
Menubar = {
    RegisterWidgetType = function(_, definition)
        assert(not provider, "provider must register exactly once")
        provider = definition
    end,
}
local money = 123456
GetMoney = function()
    return money
end
dofile("src/menubar-currency/Currency.lua")

local function render(overrides)
    local options = {}
    for key, value in pairs(provider.defaults) do
        options[key] = value
    end
    for key, value in pairs(overrides or {}) do
        options[key] = value
    end
    local widget = { settings = options }
    function widget:SetText(text)
        self.text = text
    end
    provider.update(widget)
    return widget.text, widget
end

local function test(name, callback)
    callback()
    passed = passed + 1
    print("PASS " .. name)
end

test("registers money updates and entering-world refresh", function()
    equal(provider.id, "currency")
    equal(provider.events[1], "PLAYER_MONEY")
    equal(provider.events[2], "PLAYER_ENTERING_WORLD")
    equal(provider.interval, 5)
end)

test("default coin display keeps every denomination", function()
    equal(render(), coins("12g 34s 56c"))
end)

test("gold conversion preserves every copper", function()
    equal(render({ display = "gold" }), coins("12.3456g"))
    money = 1
    equal(render({ display = "gold" }), coins("0.0001g"))
    money = 123456
end)

test("silver and copper totals preserve value", function()
    equal(render({ display = "silver" }), coins("1234.56s"))
    equal(render({ display = "copper" }), coins("123456c"))
end)

test("zero money is distinct from an unavailable source", function()
    money = 0
    equal(render(), coins("0g 0s 0c"))
    equal(render({ display = "gold" }), coins("0.0000g"))
    equal(render({ display = "silver" }), coins("0.00s"))
    equal(render({ display = "copper" }), coins("0c"))
    money = 123456
end)

test("denomination boundaries do not lose or duplicate coins", function()
    local cases = {
        { 99, coins("0g 0s 99c") },
        { 100, coins("0g 1s 0c") },
        { 9999, coins("0g 99s 99c") },
        { 10000, coins("1g 0s 0c") },
    }
    for _, case in ipairs(cases) do
        money = case[1]
        equal(render(), case[2])
    end
    money = 123456
end)

test("large totals avoid integer overflow and scientific notation", function()
    money = 2147483648
    equal(render(), coins("214748g 36s 48c"))
    equal(render({ display = "gold" }), coins("214748.3648g"))
    equal(render({ display = "copper" }), coins("2147483648c"))
    money = 123456
end)

test("updated money is read rather than accumulated", function()
    local _, widget = render()
    money = 10000
    provider.update(widget)
    equal(widget.text, coins("1g 0s 0c"))
    money = 123456
end)

test("instances can show different denominations independently", function()
    local _, first = render({ display = "gold" })
    local _, second = render({ display = "copper", showLabel = true })
    first.settings.display = "coins"
    provider.update(first)
    provider.update(second)
    equal(first.text, coins("12g 34s 56c"))
    equal(second.text, coins("Money 123456c"))
    equal(provider.defaults.display, "coins")
end)

test("invalid stored display falls back to the full breakdown", function()
    equal(render({ display = "obsolete" }), coins("12g 34s 56c"))
end)

test("unavailable and invalid sources never claim zero wealth", function()
    local previous = GetMoney
    GetMoney = nil
    equal(render(), "--")
    GetMoney = previous
    for _, value in ipairs({ -1, 1.5, math.huge, "123" }) do
        money = value
        equal(render({ showLabel = true }), "Money --")
    end
    money = nil
    equal(render(), "--")
    money = 123456
end)

test("temporarily restricted reads are unavailable and recover on the next refresh", function()
    local previous = GetMoney
    GetMoney = function() error("temporarily restricted") end
    equal(render(), "--")
    GetMoney = previous
    issecretvalue = function(value) return value == 123456 end
    equal(render(), "--")
    issecretvalue = nil
    equal(render(), coins("12g 34s 56c"))
end)

test("tooltip gives a complete coin breakdown without a duplicate raw-copper total", function()
    local _, widget = render({ display = "gold" })
    local tip = { lines = {}, rows = {} }
    function tip:AddLine(text)
        self.lines[#self.lines + 1] = text
    end
    function tip:AddDoubleLine(label, text)
        self.rows[#self.rows + 1] = { label, text }
    end
    provider.tooltip(widget, tip)
    equal(tip.lines[1], "Currency")
    equal(#tip.rows, 3)
    equal(tip.rows[1][2], "12")
    equal(tip.rows[2][2], "34")
    equal(tip.rows[3][2], "56")
    for _, row in ipairs(tip.rows) do assert(row[1] ~= "Total copper") end
end)

test("tooltip distinguishes unavailable data", function()
    money = nil
    local _, widget = render()
    local tip = { lines = {} }
    function tip:AddLine(text)
        self.lines[#self.lines + 1] = text
    end
    function tip:AddDoubleLine()
        error("unavailable money must not produce coin totals")
    end
    provider.tooltip(widget, tip)
    equal(tip.lines[#tip.lines], "Money is currently unavailable.")
    money = 123456
end)

print(string.format("%d Currency tests passed", passed))
