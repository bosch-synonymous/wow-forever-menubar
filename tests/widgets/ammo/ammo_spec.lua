local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local provider
Menubar = { RegisterWidgetType = function(_, definition) provider = definition end }
Constants = { InventoryConstants = { NumBagSlots = 1 } }
Enum = { ItemClass = { Projectile = 6 } }
local bags = { [0] = { 1001, 1001, 999 }, [1] = { 1002 } }
local items = {
    [1001] = { name = "Sharp Arrow", classID = 6 },
    [1002] = { name = "Heavy Bullet", classID = 6 },
    [999] = { name = "Bread", classID = 0 },
}
local amounts = { [1001] = 300, [1002] = 80 }
local countCalls, requests = {}, {}
local restricted = setmetatable({}, {
    __lt = function() error("restricted comparison") end,
    __le = function() error("restricted comparison") end,
    __tostring = function() error("restricted display") end,
})
issecretvalue = function(value) return rawequal(value, restricted) end
C_Container = {
    GetContainerNumSlots = function(bag) return #(bags[bag] or {}) end,
    GetContainerItemInfo = function(bag, slot)
        local id = bags[bag] and bags[bag][slot]
        if id then return { itemID = id, stackCount = 999 } end
    end,
}
C_Item = {
    GetItemIconByID = function(id) return ({ [1001] = 132382, [1002] = 132384, [3001] = 132383, [3002] = 132385 })[id] end,
    GetItemInfo = function(id)
        local item = items[id]
        if item and not item.uncached then
            return item.name, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, item.classID
        end
    end,
    GetItemInfoInstant = function(id)
        local item = items[id]
        if item then return id, nil, nil, nil, nil, item.classID end
    end,
    GetItemCount = function(id, includeBank)
        equal(includeBank, false)
        countCalls[id] = (countCalls[id] or 0) + 1
        return amounts[id] or 0
    end,
    RequestLoadItemDataByID = function(id) requests[id] = (requests[id] or 0) + 1 end,
}
dofile("src/menubar-ammo/Ammo.lua")

local function settings(overrides)
    local options = {}
    for key, value in pairs(provider.defaults) do options[key] = value end
    for key, value in pairs(overrides or {}) do options[key] = value end
    return options
end
local function render(overrides)
    local widget = { settings = settings(overrides) }
    function widget:SetText(text) self.text = text end
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
local function choices(overrides) return provider.settings[1].options(settings(overrides)) end
local function test(name, callback)
    callback(); passed = passed + 1; print("PASS " .. name)
end

test("auto uses stable first projectile and authoritative aggregate count", function()
    countCalls = {}
    equal(provider.id, "ammo")
    equal(render(), "|T132382:14:14:0:0|t 300")
    equal(countCalls[1001], 1)
    equal(provider.events[1], "BAG_UPDATE_DELAYED")
    equal(provider.events[2], "GET_ITEM_INFO_RECEIVED")
end)
test("dropdown lists carried projectile types once and excludes other classes", function()
    local list = choices()
    equal(#list, 3)
    equal(list[1].value, 0)
    equal(list[2].value, 1001)
    equal(list[3].value, 1002)
end)
test("legacy carried manual focus migrates once then the picker controls selection", function()
    equal(render({ selectedID = 1002 }), "|T132384:14:14:0:0|t 80")
    local _, widget = render({ selectedID = 1001, manualID = 1002, display = "count" })
    equal(widget.text, "80")
    equal(widget.settings.selectedID, 1002)
    equal(widget.settings.legacySelectionMigrated, true)
    widget.settings.selectedID = 1001
    provider.update(widget)
    equal(widget.text, "300")
    equal(widget.settings.manualID, 1002)
end)
test("tooltip lists all carried projectile quantities across multiple stacks", function()
    local _, widget = render()
    local tip = tooltip(widget)
    equal(tip.rows["Sharp Arrow (selected)"], "300")
    equal(tip.rows["Sharp Arrow"], nil)
    equal(tip.rows.Focused, nil)
    equal(tip.rows["Heavy Bullet"], "80")
    equal(tip.rows.Bread, nil)
end)
test("depleted saved focus shows reliable zero without adding an unpossessed picker entry", function()
    local previousBag, previousAmount = bags[0], amounts[1001]
    bags[0], amounts[1001] = { 999 }, 0
    equal(render({ selectedID = 1001 }), "|T132382:14:14:0:0|t 0")
    local list = choices({ selectedID = 1001 })
    equal(#list, 2)
    equal(list[#list].value, 1002)
    equal(list[#list].label, "Heavy Bullet")
    bags[0], amounts[1001] = previousBag, previousAmount
end)
test("classes with no carried projectiles receive a clear empty state", function()
    local previous = bags
    bags = { [0] = { 999 }, [1] = {} }
    equal(render(), "No carried ammo")
    bags = previous
end)
test("unknown item cache never masquerades as no ammunition", function()
    local previous = bags
    bags = { [0] = { 3001 } }
    equal(render(), "Ammo data loading")
    equal(requests[3001], 1)
    equal(render(), "Ammo data loading")
    equal(requests[3001], 1)
    items[3001] = { name = "New Arrow", classID = 6 }
    amounts[3001] = 25
    equal(render(), "|T132383:14:14:0:0|t 25")
    bags = previous
end)
test("instant classification preserves known projectile while name loads", function()
    local previous = bags
    bags = { [0] = { 3002 } }
    items[3002] = { classID = 6, uncached = true }
    amounts[3002] = 40
    equal(render(), "|T132385:14:14:0:0|t 40")
    local list = choices({ selectedID = 3002 })
    equal(list[2].value, 3002)
    items[3002] = { name = "Fresh Bullet", classID = 6 }
    equal(render(), "|T132385:14:14:0:0|t 40")
    bags = previous
end)
test("partial metadata warning accompanies known ammo in the tooltip", function()
    local previous = bags
    bags = { [0] = { 1001, 3003 } }
    local _, widget = render()
    local tip = tooltip(widget)
    equal(tip.rows["Sharp Arrow (selected)"], "300")
    equal(tip.lines[#tip.lines], "Item details loading; this list may be incomplete.")
    bags = previous
end)
test("stale or nonprojectile legacy manual preferences do not override the carried selection", function()
    equal(render({ selectedID = 1002, manualID = 999 }), "|T132384:14:14:0:0|t 80")
    equal(render({ selectedID = 999 }), "Selected item is not projectile ammo")
end)
test("invalid saved IDs do not silently switch focus", function()
    equal(render({ selectedID = 1002, manualID = -1 }), "|T132384:14:14:0:0|t 80")
    equal(render({ selectedID = 1.5 }), "Selected ammunition is unavailable")
end)
test("restricted counts stay unavailable without comparison or formatting", function()
    amounts[1001] = restricted
    equal(render(), "|T132382:14:14:0:0|t --")
    local _, widget = render()
    equal(tooltip(widget).rows["Sharp Arrow (selected)"], "Unavailable")
    amounts[1001] = 300
end)
test("restricted bag IDs leave an incomplete scan rather than false zero", function()
    local previous = bags
    bags = { [0] = { restricted } }
    equal(render(), "Ammo data loading")
    bags = previous
end)
test("unavailable count API does not fabricate stack-derived totals", function()
    local previous = C_Item.GetItemCount
    C_Item.GetItemCount = nil
    equal(render(), "|T132382:14:14:0:0|t --")
    C_Item.GetItemCount = previous
end)
test("unavailable bags are explicit while a saved known selection can still be counted", function()
    local previous = C_Container
    C_Container = nil
    equal(render(), "Ammo unavailable")
    equal(render({ selectedID = 1001 }), "|T132382:14:14:0:0|t 300")
    C_Container = previous
end)
test("runtime bag-count fallback includes carried bags only", function()
    local previous = Constants
    Constants, NUM_BAG_SLOTS = nil, 1
    equal(render({ selectedID = 1002 }), "|T132384:14:14:0:0|t 80")
    Constants, NUM_BAG_SLOTS = previous, nil
end)
test("API count errors degrade to unavailable", function()
    local previous = C_Item.GetItemCount
    C_Item.GetItemCount = function() error("restricted API") end
    equal(render(), "|T132382:14:14:0:0|t --")
    C_Item.GetItemCount = previous
end)
test("instances retain separate ammo selection and presentation", function()
    local _, first = render({ selectedID = 1001 })
    local _, second = render({ selectedID = 1002, display = "count" })
    first.settings.selectedID = 1002
    provider.update(first); provider.update(second)
    equal(first.text, "|T132384:14:14:0:0|t 80")
    equal(second.text, "80")
    equal(provider.defaults.manualID, nil)
end)
test("name and combined displays remain available independently of icon defaults", function()
    equal(render({ display = "name" }), "Sharp Arrow: 300")
    equal(render({ display = "iconName" }), "|T132382:14:14:0:0|t Sharp Arrow: 300")
    equal(render({ display = "count" }), "300")
    equal(render({ showName = true }), "|T132382:14:14:0:0|t 300")
    equal(render({ showName = false }), "|T132382:14:14:0:0|t 300")
end)
test("missing icon data falls back to a name and upgrades when the icon arrives", function()
    items[4001] = { name = "Uncached Icon Arrow", classID = 6 }
    amounts[4001] = 17
    equal(render({ selectedID = 4001 }), "Uncached Icon Arrow: 17")
    local previous = C_Item.GetItemIconByID
    C_Item.GetItemIconByID = function(id) return id == 4001 and 987654 or previous(id) end
    equal(render({ selectedID = 4001 }), "|T987654:14:14:0:0|t 17")
    C_Item.GetItemIconByID = previous
end)
test("cached item metadata can supply the icon when the icon API is unavailable", function()
    items[4002] = { name = "Cached Icon Bullet", classID = 6 }
    amounts[4002] = 23
    local previousInfo, previousIcon = C_Item.GetItemInfo, C_Item.GetItemIconByID
    C_Item.GetItemIconByID = nil
    C_Item.GetItemInfo = function(id)
        if id == 4002 then return "Cached Icon Bullet", nil, nil, nil, nil, nil, nil, nil, nil, 135791, nil, 6 end
        return previousInfo(id)
    end
    equal(render({ selectedID = 4002 }), "|T135791:14:14:0:0|t 23")
    C_Item.GetItemInfo, C_Item.GetItemIconByID = previousInfo, previousIcon
end)
test("restricted icon data is never formatted or compared", function()
    items[4003] = { name = "Restricted Icon Arrow", classID = 6 }
    amounts[4003] = 7
    local previous = C_Item.GetItemIconByID
    C_Item.GetItemIconByID = function(id) return id == 4003 and restricted or previous(id) end
    equal(render({ selectedID = 4003 }), "Restricted Icon Arrow: 7")
    C_Item.GetItemIconByID = previous
end)
test("settings expose possessed choices and presentation without numeric ID controls", function()
    for _, field in ipairs(provider.settings) do
        assert(field.key ~= "manualID")
        assert(field.type ~= "number")
    end
    local list = choices({ selectedID = 444444 })
    for _, choice in ipairs(list) do assert(choice.value ~= 444444) end
end)

test("legacy manual migration waits for carried inventory metadata", function()
    local previous = bags
    bags = { [0] = { 5001 } }
    local _, widget = render({ manualID = 5001, display = "count" })
    equal(widget.text, "Ammo data loading")
    assert(widget.settings.legacySelectionMigrated ~= true)
    items[5001] = { name = "Arriving Arrow", classID = 6 }
    amounts[5001] = 19
    provider.update(widget)
    equal(widget.text, "19")
    equal(widget.settings.selectedID, 5001)
    equal(widget.settings.legacySelectionMigrated, true)
    bags = previous
end)

test("complete immutable metadata is reused while carried amounts remain fresh", function()
    local previousInfo, previousInstant, previousIcon = C_Item.GetItemInfo, C_Item.GetItemInfoInstant, C_Item.GetItemIconByID
    local metadataReads = 0
    C_Item.GetItemInfo = function(...) metadataReads = metadataReads + 1; return previousInfo(...) end
    C_Item.GetItemInfoInstant = function(...) metadataReads = metadataReads + 1; return previousInstant(...) end
    C_Item.GetItemIconByID = function(...) metadataReads = metadataReads + 1; return previousIcon(...) end
    local _, first = render({ selectedID = 1001 })
    local _, second = render({ selectedID = 1001, display = "count" })
    equal(metadataReads, 0, "Previously completed item metadata should not be queried again")
    amounts[1001] = 271
    provider.update(first); provider.update(second)
    equal(first.text, "|T132382:14:14:0:0|t 271")
    equal(second.text, "271")
    equal(tooltip(first).rows["Sharp Arrow (selected)"], "271")
    equal(metadataReads, 0)
    amounts[1001] = 300
    C_Item.GetItemInfo, C_Item.GetItemInfoInstant, C_Item.GetItemIconByID = previousInfo, previousInstant, previousIcon
end)

test("nonprojectile bags need no full metadata icon or explicit load request", function()
    local previousBags = bags
    local previousInfo, previousIcon = C_Item.GetItemInfo, C_Item.GetItemIconByID
    bags = { [0] = { 6001 } }
    items[6001] = { classID = 0, uncached = true }
    local reads = 0
    C_Item.GetItemInfo = function() reads = reads + 1; error("nonprojectile name lookup is unnecessary") end
    C_Item.GetItemIconByID = function() reads = reads + 1; error("nonprojectile icon lookup is unnecessary") end
    equal(render(), "No carried ammo")
    equal(reads, 0)
    equal(requests[6001], nil)
    bags, C_Item.GetItemInfo, C_Item.GetItemIconByID = previousBags, previousInfo, previousIcon
end)

test("unresolved metadata retries explicit loads on a shared bounded cadence", function()
    local previousBags, previousTime = bags, GetTime
    local now = 0
    GetTime = function() return now end
    bags = { [0] = { 6002 } }
    equal(render(), "Ammo data loading")
    equal(requests[6002], 1)
    now = 9.99
    equal(render(), "Ammo data loading")
    equal(requests[6002], 1)
    now = 10
    equal(render(), "Ammo data loading")
    equal(requests[6002], 2)
    equal(render(), "Ammo data loading")
    equal(requests[6002], 2)
    items[6002], amounts[6002] = { name = "Recovered Arrow", classID = 6 }, 26
    equal(render({ display = "name" }), "Recovered Arrow: 26")
    now = 30
    equal(render({ display = "name" }), "Recovered Arrow: 26")
    equal(requests[6002], 2)
    bags, GetTime = previousBags, previousTime
end)

test("failed explicit loads share the retry limit and recover without a request burst", function()
    local previousBags, previousTime, previousRequest = bags, GetTime, C_Item.RequestLoadItemDataByID
    local now, attempts, failing = 100, 0, true
    GetTime = function() return now end
    bags = { [0] = { 6003 } }
    items[6003] = { classID = 6, uncached = true }
    C_Item.RequestLoadItemDataByID = function(id)
        equal(id, 6003)
        attempts = attempts + 1
        if failing then error("injected native load failure") end
    end
    local _, first = render({ display = "count" })
    local _, second = render({ display = "name" })
    for _ = 1, 100 do provider.update(first); provider.update(second) end
    equal(attempts, 1)
    now = 109.99; provider.update(first); equal(attempts, 1)
    now = 110; provider.update(second); equal(attempts, 2)
    failing = false
    now = 119.99; provider.update(first); equal(attempts, 2)
    now = 120; provider.update(second); equal(attempts, 3)
    provider.update(first); equal(attempts, 3)
    items[6003], amounts[6003] = { name = "Recovered Bullet", classID = 6 }, 41
    provider.update(first); provider.update(second)
    equal(first.text, "41"); equal(second.text, "Recovered Bullet: 41")
    now = 140; provider.update(first); equal(attempts, 3)
    bags, GetTime, C_Item.RequestLoadItemDataByID = previousBags, previousTime, previousRequest
end)

test("a failed load without a clock stays bounded until the clock recovers", function()
    local previousBags, previousTime, previousRequest = bags, GetTime, C_Item.RequestLoadItemDataByID
    local now, attempts = nil, 0
    GetTime = function() return now end
    bags = { [0] = { 6004 } }
    C_Item.RequestLoadItemDataByID = function()
        attempts = attempts + 1
        error("injected native load failure")
    end
    for _ = 1, 20 do render() end
    equal(attempts, 1)
    now = 20; render(); equal(attempts, 2)
    now = 29.99; render(); equal(attempts, 2)
    now = 30; render(); equal(attempts, 3)
    bags, GetTime, C_Item.RequestLoadItemDataByID = previousBags, previousTime, previousRequest
end)

test("the direct picker leaves ammunition focus untouched until its host applies a choice", function()
    local widget = { settings = { selectedID = 1001, display = "icon" }, text = "300" }
    local calls = 0
    function widget:OpenChoiceMenu(key, title)
        equal(key, "selectedID"); equal(title, "Watch ammunition")
        calls = calls + 1
        return true
    end
    equal(provider.click(widget), true)
    equal(calls, 1); equal(widget.settings.selectedID, 1001); equal(widget.settings.display, "icon"); equal(widget.text, "300")
    for _, missing in ipairs({ false, "unsupported", restricted }) do
        widget.OpenChoiceMenu = missing
        equal(provider.click(widget), false)
        equal(widget.settings.selectedID, 1001); equal(widget.text, "300")
    end
    widget.OpenChoiceMenu = nil; equal(provider.click(widget), false)
    equal(calls, 1)
end)

print(string.format("%d Ammo tests passed", passed))
