local sourceDirectory = dofile((REPO_ROOT or ".") .. "/tests/source_paths.lua")
-- Actual provider actions through Core's click routing and native menu adapter.
-- Native rendering, input and protected actions still require the game client.
local root = REPO_ROOT or "."
local sources = {
    { "location", "Menubar_Location", "Location.lua" },
    { "reputation", "Menubar_Reputation", "Reputation.lua" },
    { "ammo", "Menubar_Ammo", "Ammo.lua" },
    { "currency", "Menubar_Currency", "Currency.lua" },
    { "time", "Menubar_Time", "Time.lua" },
    { "volume", "Menubar_Volume", "Volume.lua" },
}
local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end
local paths = {}
for _, source in ipairs(sources) do
    local override = _G["MENUBAR_" .. source[1]:upper() .. "_ROOT"]
    local providerRoot = override or root
    local path = sourceDirectory(providerRoot, source[2]) .. "/" .. source[3]
    if not exists(path) then
        if override then error("Required quick-action integration provider is missing: " .. path, 0) end
        print("SKIP quick-action integration: supply Location, Reputation, Ammo, Currency, Time and Volume roots.")
        return
    end
    paths[#paths + 1] = path
end

local Stub = dofile(root .. "/tests/wow_stub.lua")
Stub.Install()
local shifted = false
IsShiftKeyDown = function() return shifted end

local mapToggles, mapVisible, mapReads = 0, false, 0
OpenWorldMap = function() error("Location must use the native toggle rather than the open-only action") end
ToggleWorldMap = function(...)
    assert(select("#", ...) == 0, "Toggling the map must not force a map selection")
    mapToggles, mapVisible = mapToggles + 1, not mapVisible
end
GetRealZoneText = function() return "Test Territory" end
GetSubZoneText = function() return "Test Camp" end
C_Map = {
    GetBestMapForUnit = function() mapReads = mapReads + 1; return 1 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.25, 0.75 end } end,
}
C_PvP = { GetZonePVPInfo = function() return "friendly", false, "Horde" end }

local watchedFaction, reputationWrites = 72, 0
local factionNames = { [72] = "Stormwind", [99] = "Darkspear Trolls" }
local function faction(id)
    if not factionNames[id] then return end
    return { factionID = id, name = factionNames[id], reaction = 5, currentStanding = 4500,
        currentReactionThreshold = 3000, nextReactionThreshold = 9000,
        isHeader = false, isHeaderWithRep = false, isWatched = id == watchedFaction }
end
local function forbiddenFactionWrite()
    reputationWrites = reputationWrites + 1
    error("A widget selection must not change Blizzard's watched faction or selection")
end
C_Reputation = {
    GetWatchedFactionData = function() return faction(watchedFaction) end,
    GetFactionDataByID = faction,
    GetNumFactions = function() return 2 end,
    GetFactionDataByIndex = function(index) return faction(index == 1 and 72 or 99) end,
    IsMajorFaction = function() return false end,
    IsFactionParagonForCurrentPlayer = function() return false end,
    SetWatchedFactionByID = forbiddenFactionWrite,
    SetWatchedFactionByIndex = forbiddenFactionWrite,
    SetSelectedFaction = forbiddenFactionWrite,
}

local carried = { 1001, 1002, 1004 }
local items = {
    [1001] = { name = "Sharp Arrow", icon = 2001, class = 6, count = 120 },
    [1002] = { name = "Heavy Shot", icon = 2002, class = 6, count = 80 },
    [1003] = { name = "Bank Arrow", icon = 2003, class = 6, count = 900 },
    [1004] = { name = "Bread", icon = 2004, class = 0, count = 5 },
}
Constants = { InventoryConstants = { NumBagSlots = 1 } }
Enum = { ItemClass = { Projectile = 6 } }
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and #carried or 0 end,
    GetContainerItemID = function(bag, slot) if bag == 0 then return carried[slot] end end,
}
C_Item = {
    GetItemInfoInstant = function(id)
        local item = items[id]
        if item then return id, nil, nil, nil, item.icon, item.class end
    end,
    GetItemInfo = function(id)
        local item = items[id]
        if item then return item.name, nil, nil, nil, nil, nil, nil, nil, nil, item.icon, nil, item.class end
    end,
    GetItemCount = function(id, includeBank)
        assert(includeBank == false, "Ammo must count only carried inventory")
        return items[id] and items[id].count or 0
    end,
}

local tokenRows = {
    { name = "Tokens", isHeader = true },
    { name = "Festival Ticket", currencyID = 42, isHeader = false },
    { name = "Honor", currencyID = 77, isHeader = false },
}
local tokenData = {
    [42] = { currencyID = 42, name = "Festival Ticket", quantity = 7, iconFileID = 3042, maxQuantity = 100 },
    [77] = { currencyID = 77, name = "Honor", quantity = 12, iconFileID = 3077 },
    [88] = { currencyID = 88, name = "Hidden Token", quantity = 99, iconFileID = 3088 },
}
local currencyWrites = 0
local function forbiddenCurrencyWrite()
    currencyWrites = currencyWrites + 1
    error("Choosing widget currency must not change Blizzard's tracking or exposed list")
end
C_CurrencyInfo = {
    GetCurrencyListSize = function() return #tokenRows end,
    GetCurrencyListInfo = function(index) return tokenRows[index] end,
    GetCurrencyInfo = function(id) return tokenData[id] end,
    SetCurrencyBackpack = forbiddenCurrencyWrite,
    ExpandCurrencyList = forbiddenCurrencyWrite,
    SetCurrencyUnused = forbiddenCurrencyWrite,
}
local audio, audioWrites = { Sound_MasterVolume = "0.5", Sound_EnableAllSound = "1" }, 0
C_CVar = {
    GetCVar = function(name) return audio[name] end,
    SetCVar = function(name, value)
        audioWrites = audioWrites + 1
        audio[name] = tostring(value)
        return true
    end,
}

for _, file in ipairs({ "Model.lua", "Identity.lua", "Layout.lua", "Gauge.lua", "Skins.lua", "Fonts.lua", "Core.lua", "UI.lua", "Settings.lua" }) do
    dofile(root .. "/src/menubar-core/" .. file)
end
for _, path in ipairs(paths) do dofile(path) end
Menubar:Start()

local passed = 0
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1
    print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function widget(kind, except)
    for _, value in pairs(Menubar.runtime) do
        if value.instance.type == kind and value ~= except then return value end
    end
    error("Missing runtime for " .. kind)
end
local function click(value, button, shift)
    shifted = shift == true
    value.frame:Click(button or "LeftButton")
    shifted = false
    assert(not value.failed, value.failed)
end
local function open(value)
    local before = #Stub.menus
    click(value)
    equal(#Stub.menus, before + 1)
    return Stub.menus[#Stub.menus]
end
local function find(menu, label)
    for _, child in ipairs(menu.children) do if child.text == label then return child end end
end
local function choose(value, label)
    local menu = open(value)
    local choice = Stub.MenuItem(menu, label)
    assert(type(choice.selected) == "function", "A quick choice must use the native radio contract")
    choice.callback()
    assert(not value.failed, value.failed)
    return menu
end
local function saved(value, key)
    return MenubarModel.GetWidget(Menubar.db, Menubar.characterKey, value.id).settings[key]
end

check("ordinary Location left-click toggles open closed and open without menus or map-selection reads", function()
    local location, before = widget("location"), #Stub.menus
    local reads, settings, previous = mapReads, location.settings, {}
    for key, value in pairs(settings) do previous[key] = value end
    equal(location.definition.clickHint, "Toggle map")
    click(location)
    equal(mapToggles, 1); equal(mapVisible, true)
    click(location)
    equal(mapToggles, 2); equal(mapVisible, false)
    click(location)
    equal(mapToggles, 3); equal(mapVisible, true)
    equal(#Stub.menus, before)
    equal(mapReads, reads); equal(location.settings, settings)
    for key, value in pairs(previous) do equal(settings[key], value) end
    for key, value in pairs(settings) do equal(previous[key], value) end
end)

check("all six providers keep right-click settings and Shift-left arrangement menus", function()
    local before = mapToggles
    for _, source in ipairs(sources) do
        local value = widget(source[1])
        local menus = #Stub.menus
        click(value, "RightButton")
        equal(Menubar.UI.widgetID, value.id)
        assert(Menubar.UI.window:IsShown())
        equal(#Stub.menus, menus)
        Menubar.UI.window:Hide()
        click(value, "LeftButton", true)
        local menu = Stub.menus[#Stub.menus]
        equal(#Stub.menus, menus + 1)
        assert(Stub.MenuItem(menu, "Move earlier"))
        assert(Stub.MenuItem(menu, "Configure..."))
    end
    equal(mapToggles, before)
    equal(reputationWrites, 0); equal(currencyWrites, 0); equal(audioWrites, 0)
end)

check("the real Reputation picker changes only this widget and leaves Blizzard's watched bar alone", function()
    local value = widget("reputation")
    local prior = value.settings.factionID
    local menu = open(value)
    equal(value.settings.factionID, prior)
    local choice = Stub.MenuItem(menu, "Darkspear Trolls")
    choice.callback()
    equal(saved(value, "factionID"), 99)
    assert(value.text:find("Darkspear Trolls", 1, true), "New faction should render immediately")
    equal(watchedFaction, 72); equal(reputationWrites, 0)
    choose(value, "Follow game's watched faction")
    equal(saved(value, "factionID"), 0)
    assert(value.text:find("Stormwind", 1, true))
end)

check("the real Ammo picker exposes carried projectiles and duplicate choices stay independent", function()
    local first = widget("ammo")
    local menu = choose(first, "Heavy Shot")
    assert(not find(menu, "Bank Arrow") and not find(menu, "Bread"))
    equal(saved(first, "selectedID"), 1002)
    assert(first.text:find("2002", 1, true) and first.text:find("80", 1, true))
    click(first, "LeftButton", true)
    Stub.MenuItem(Stub.menus[#Stub.menus], "Duplicate").callback()
    local second = widget("ammo", first)
    assert(first.settings ~= second.settings)
    equal(saved(second, "selectedID"), 1002)
    choose(second, "Sharp Arrow")
    equal(saved(second, "selectedID"), 1001)
    equal(saved(first, "selectedID"), 1002)
    local stale = Stub.MenuItem(open(second), "Heavy Shot")
    carried = { 1001, 1004 }
    stale.callback()
    equal(saved(second, "selectedID"), 1001)
    carried = { 1001, 1002, 1004 }
end)

check("the real Time picker saves UTC and redraws immediately without changing clock format", function()
    local value = widget("time")
    local format, label = value.settings.format, value.settings.showLabel
    equal(value.text, "12:34")
    choose(value, "UTC")
    equal(saved(value, "zone"), "utc")
    equal(value.settings.format, format); equal(value.settings.showLabel, label)
    equal(value.text, "03:34")
end)

check("the real Currency picker chooses Money or exposed token IDs without native tracking writes", function()
    local value = widget("currency")
    local money = value.text
    local menu = choose(value, "Festival Ticket")
    assert(not find(menu, "Hidden Token") and not find(menu, "Tokens"))
    equal(saved(value, "currencyID"), 42)
    assert(value.text:find("3042", 1, true) and value.text:find("7", 1, true))
    choose(value, "Honor")
    equal(saved(value, "currencyID"), 77)
    assert(value.text:find("3077", 1, true) and value.text:find("12", 1, true))
    choose(value, "Money")
    equal(saved(value, "currencyID"), 0); equal(value.text, money)
    equal(currencyWrites, 0)
end)

check("ordinary Volume left-click creates usable native vertical controls", function()
    local value = widget("volume")
    local menu, element = open(value)
    for _, child in ipairs(menu.children) do if child.kind == "Frame" then element = child; break end end
    assert(element, "Volume action must create a managed menu frame")
    local native = CreateFrame("Frame", nil, UIParent)
    local first = #Stub.frames
    for _, initialize in ipairs(element.initializers) do initialize(native, element, menu) end
    local slider
    for index = first + 1, #Stub.frames do
        if Stub.frames[index].kind == "Slider" then slider = Stub.frames[index]; break end
    end
    assert(slider and slider.orientation == "VERTICAL")
    equal(audioWrites, 0)
    Stub.DragSlider(slider, 20)
    equal(tonumber(audio.Sound_MasterVolume), 0.8)
    slider.scripts.OnMouseWheel(slider, -1)
    equal(tonumber(audio.Sound_MasterVolume), 0.75)
    Stub.MenuItem(menu, "|A:voicechat-icon-speaker-mute:14:14|a Mute").callback()
    equal(tonumber(audio.Sound_EnableAllSound), 0)
    assert(not value.failed)
end)

check("provider hover hints advertise each ordinary action alongside the common gestures", function()
    for _, source in ipairs(sources) do
        local value = widget(source[1])
        value.frame.scripts.OnEnter(value.frame)
        local hints = GameTooltip.lines[#GameTooltip.lines][1]
        assert(hints:find(value.definition.clickHint, 1, true))
        assert(hints:find("Shift", 1, true) and hints:find("settings", 1, true))
        value.frame.scripts.OnLeave(value.frame)
    end
end)

print(passed .. " quick-action integration tests passed")
