local passed, provider = 0, nil
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, callback)
    callback(); passed = passed + 1; print("PASS " .. name)
end
Menubar = { RegisterWidgetType = function(_, definition) provider = definition end }
local incoming, outgoing, home, world = 1.25, 0.75, 42, 81
local function stats() return incoming, outgoing, home, world end
GetNetStats = stats
dofile("src/menubar-network/Network.lua")
local function widget(options)
    local value = { settings = {} }
    for key, default in pairs(provider.defaults) do value.settings[key] = default end
    for key, override in pairs(options or {}) do value.settings[key] = override end
    function value:SetText(text) self.text = text end
    provider.update(value)
    return value
end

test("registers network provider with a modest update interval", function()
    equal(provider.id, "network"); equal(provider.interval, 1)
    equal(provider.defaults.showThroughput, false)
    equal(provider.defaults.showLabel, false); equal(provider.legacyDefaults.showLabel, true)
end)
test("world latency is selected without a connection label by default", function()
    equal(widget().text, "81 ms")
end)
test("home latency can be selected independently", function()
    equal(widget({ latency = "home", showLabel = true }).text, "Home 42 ms")
end)
test("connection label can be enabled", function()
    equal(widget({ showLabel = true }).text, "World 81 ms")
end)
test("throughput keeps inbound and outbound direction and reported scale", function()
    equal(widget({ showThroughput = true, showLabel = true }).text, "World 81 ms  In 1.2 / Out 0.8 KB/s")
end)
test("zero traffic and zero latency remain valid measurements", function()
    incoming, outgoing, home, world = 0, 0, 0, 0
    equal(widget({ showThroughput = true, showLabel = true }).text, "World 0 ms  In 0.0 / Out 0.0 KB/s")
    incoming, outgoing, home, world = 1.25, 0.75, 42, 81
end)
test("missing API explicitly displays unavailable latency and rates", function()
    GetNetStats = nil
    equal(widget({ showThroughput = true, showLabel = true }).text, "World -- ms  In -- / Out -- KB/s")
    GetNetStats = stats
end)
test("invalid and nonfinite measurements are unavailable", function()
    incoming, outgoing, home, world = -1, math.huge, "unknown", 0 / 0
    equal(widget({ showThroughput = true, showLabel = true }).text, "World -- ms  In -- / Out -- KB/s")
    equal(widget({ latency = "home", showLabel = true }).text, "Home -- ms")
    incoming, outgoing, home, world = 1.25, 0.75, 42, 81
end)
test("secret values are rejected before arithmetic", function()
    local secret = {}
    issecretvalue = function(value) return value == secret end
    world = secret
    equal(widget().text, "-- ms")
    world, issecretvalue = 81, nil
end)
test("each instance keeps its own choices", function()
    local first, second = widget({ latency = "home", showLabel = true }), widget({ showLabel = false })
    first.settings.showThroughput = true
    provider.update(first); provider.update(second)
    equal(first.text, "Home 42 ms  In 1.2 / Out 0.8 KB/s")
    equal(second.text, "81 ms")
    equal(provider.defaults.showThroughput, false)
end)
test("tooltip shows both connections and directions", function()
    local tip = { rows = {}, lines = {} }
    function tip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tip:AddDoubleLine(label, text) self.rows[#self.rows + 1] = { label, text } end
    provider.tooltip(widget(), tip)
    equal(tip.lines[1], "Network"); equal(#tip.rows, 4)
    equal(tip.rows[1][2], "42 ms"); equal(tip.rows[2][2], "81 ms")
    equal(tip.rows[3][2], "1.2 KB/s"); equal(tip.rows[4][2], "0.8 KB/s")
    assert(tip.lines[#tip.lines]:find("Game traffic only", 1, true))
    assert(tip.lines[#tip.lines]:find("KB/s units are experimental", 1, true))
    equal(#tip.lines, 3)
end)
test("obsolete stored connection safely defaults to world", function()
    equal(widget({ latency = "removed", showLabel = true }).text, "World 81 ms")
end)
test("temporary network API failures remain unavailable and recover without a settings refresh", function()
    local previous = GetNetStats
    GetNetStats = function() error("temporary network statistics failure") end
    local value = widget({ showThroughput = true, showLabel = true })
    equal(value.text, "World -- ms  In -- / Out -- KB/s")
    local tip = { rows = {}, lines = {} }
    function tip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tip:AddDoubleLine(label, text) self.rows[#self.rows + 1] = { label, text } end
    provider.tooltip(value, tip)
    equal(tip.rows[1][2], "-- ms"); equal(tip.rows[3][2], "-- KB/s")
    GetNetStats = previous
    provider.update(value)
    equal(value.text, "World 81 ms  In 1.2 / Out 0.8 KB/s")
end)

print(string.format("%d Network tests passed", passed))
