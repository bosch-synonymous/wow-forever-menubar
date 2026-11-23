local sourceDirectory = dofile((REPO_ROOT or ".") .. "/tests/source_paths.lua")
-- Cross-addon behavior through the actual host and UI, using the shared native UI double.
-- Official provider sources live beside Core under this repository's src/ directory.
local root = REPO_ROOT or "."
local Stub = dofile(root .. "/tests/wow_stub.lua")
Stub.Install()
local currentXP, coordinateX, restState = 100, 0.25, 2
UnitLevel = function() return 10 end
UnitXP = function() return currentXP end
UnitXPMax = function() return 1000 end
GetXPExhaustion = function() return 250 end
IsResting = function() return false end
GetRestState = function() return restState, restState == 1 and "Rested" or "Normal", restState == 1 and 2 or 1 end
GetRealZoneText = function() return "Test Zone" end
GetSubZoneText = function() return "Test Hamlet" end
C_Map = {
    GetBestMapForUnit = function() return 1 end,
    GetPlayerMapPosition = function() return { GetXY = function() return coordinateX, 0.75 end } end,
}
C_PvP = { GetZonePVPInfo = function() return "friendly", false, "Alliance" end }
local factionStanding, watchedFactionID = 4500, 72
local function faction(id)
    id = id or watchedFactionID
    return { factionID = id, name = id == 72 and "Stormwind" or "Other faction", reaction = 5,
        currentStanding = factionStanding, currentReactionThreshold = 3000,
        nextReactionThreshold = 9000, isHeader = false, isHeaderWithRep = false, isWatched = id == watchedFactionID }
end
C_Reputation = {
    GetWatchedFactionData = faction,
    GetFactionDataByID = function(id) if id == 72 or id == 99 then return faction(id) end end,
    GetNumFactions = function() return 2 end,
    GetFactionDataByIndex = function(index) if index <= 2 then return faction(index == 1 and 72 or 99) end end,
    IsMajorFaction = function() return false end,
    IsFactionParagonForCurrentPlayer = function() return false end,
    SetWatchedFactionByID = function() error("Widget focus must not change Blizzard's watched bar") end,
    SetWatchedFactionByIndex = function() error("Widget focus must not change Blizzard's watched bar") end,
    SetSelectedFaction = function() error("Widget focus must not change Blizzard's Reputation window selection") end,
}
local ammoCount = 300
Constants = { InventoryConstants = { NumBagSlots = 1 } }
Enum = { ItemClass = { Projectile = 6 } }
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
    GetContainerItemInfo = function(bag, slot) if bag == 0 and slot == 1 then return { itemID = 1001 } end end,
}
C_Item = {
    GetItemInfo = function(id)
        if id == 1001 then return "Sharp Arrow", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 6 end
    end,
    GetItemInfoInstant = function(id) if id == 1001 then return id, nil, nil, nil, nil, 6 end end,
    GetItemCount = function(id, includeBank)
        assert(includeBank == false, "Ammo must count carried inventory rather than bank inventory")
        return id == 1001 and ammoCount or 0
    end,
    GetItemIconByID = function(id) if id == 1001 then return 4242 end end,
}
local cvars, audioWrites = { Sound_MasterVolume = "0.5", Sound_EnableAllSound = "1" }, {}
C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value)
        audioWrites[#audioWrites + 1] = { name, value }
        cvars[name] = tostring(value)
        return true
    end,
}
local Region = getmetatable(UIParent)
local nativeCreateTexture = Region.CreateTexture
local textures = {}
function Region:CreateTexture(...)
    local texture = nativeCreateTexture(self, ...)
    textures[#textures + 1] = texture
    return texture
end

local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end
local function providerPath(id, addonName, fileName)
    local override = _G["MENUBAR_" .. string.upper(id) .. "_ROOT"]
    local candidates = {}
    if override then candidates[#candidates + 1] = override end
    candidates[#candidates + 1] = root
    for _, candidate in ipairs(candidates) do
        local path = sourceDirectory(candidate, addonName) .. "/" .. fileName
        if exists(path) then return path end
    end
    return nil
end

dofile(root .. "/src/menubar-core/Model.lua")
dofile(root .. "/src/menubar-core/Identity.lua")
dofile(root .. "/src/menubar-core/Layout.lua")
dofile(root .. "/src/menubar-core/Gauge.lua")
dofile(root .. "/src/menubar-core/Skins.lua")
dofile(root .. "/src/menubar-core/Fonts.lua")
dofile(root .. "/src/menubar-core/Core.lua")
dofile(root .. "/src/menubar-core/UI.lua")
dofile(root .. "/src/menubar-core/Settings.lua")
local sources = {
    { "time", "Menubar_Time", "Time.lua" },
    { "currency", "Menubar_Currency", "Currency.lua" },
    { "eyes", "Menubar_Eyes", "Eyes.lua" },
    { "network", "Menubar_Network", "Network.lua" },
    { "xp", "Menubar_XP", "XP.lua" },
    { "location", "Menubar_Location", "Location.lua" },
    { "reputation", "Menubar_Reputation", "Reputation.lua" },
    { "ammo", "Menubar_Ammo", "Ammo.lua" },
    { "volume", "Menubar_Volume", "Volume.lua" },
}
local sourcePaths = {}
for _, source in ipairs(sources) do
    local path = providerPath(unpack(source))
    if not path then
        print("SKIP cross-addon provider integration: missing menubar-" .. source[1]
            .. "; restore the official widget sources under src/ or pass explicit roots to the runner.")
        return
    end
    sourcePaths[#sourcePaths + 1] = path
end
local territoryData = providerPath("location", "Menubar_Location", "TerritoryData.lua")
if territoryData then dofile(territoryData) end
for _, path in ipairs(sourcePaths) do dofile(path) end
local callbacks = {}
for _, source in ipairs(sources) do
    local id = source[1]
    callbacks[id] = { create = 0, update = 0, deactivate = 0, destroy = 0 }
    for _, callback in ipairs({ "create", "update", "deactivate", "destroy" }) do
        local original = Menubar.types[id][callback]
        if original then
            local callbackName = callback
            Menubar.types[id][callbackName] = function(...)
                callbacks[id][callbackName] = callbacks[id][callbackName] + 1
                return original(...)
            end
        end
    end
end
Menubar:Start()

-- Keep explicit presentation fixtures for the standard-eye and square/numeric
-- paths below; the separate production-defaults spec covers factory choices.
for _, value in pairs(Menubar.runtime) do
    if value.instance.type == "eyes" then value.settings.appearance, value.settings.iris = "standard", "black"
    elseif value.instance.type == "network" then value.settings.showLabel = true
    elseif value.instance.type == "xp" then value.settings.display, value.settings.gaugeStyle = "percent", "square"
    elseif value.instance.type == "reputation" then
        value.settings.progress, value.settings.gaugeStyle, value.settings.showStanding = "percent", "square", true
    end
end
Menubar:RefreshAll()

local passed = 0
local function check(name, callback)
    local ok, reason = pcall(callback)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function shiftLeftClick(frame)
    local previous = IsShiftKeyDown
    IsShiftKeyDown = function() return true end
    local ok, reason = pcall(frame.Click, frame, "LeftButton")
    IsShiftKeyDown = previous
    if not ok then error(reason, 0) end
end
local function widget(kind)
    for _, value in pairs(Menubar.runtime) do
        if value.instance.type == kind then return value end
    end
    error("Missing runtime for " .. kind)
end
local function tick(elapsed)
    Menubar.eventFrame.scripts.OnUpdate(Menubar.eventFrame, elapsed)
end
local function eyesShown(value, shown)
    for _, eye in ipairs(value.eyes) do
        for _, texture in ipairs(eye.border) do equal(texture:IsShown(), shown) end
        for _, texture in ipairs(eye.white) do equal(texture:IsShown(), shown) end
        equal(eye.pupil:IsShown(), shown); equal(eye.spark:IsShown(), shown)
    end
end

check("all independent addon definitions load and render together", function()
    equal(#MenubarModel.ListWidgets(Menubar.db, Menubar.characterKey), #sources)
    equal(widget("time").text, "12:34")
    equal(widget("currency").text, "12|A:coin-gold:14:14:0:0|a 34|A:coin-silver:14:14:0:0|a 56|A:coin-copper:14:14:0:0|a")
    equal(widget("network").text, "World 68 ms")
    equal(widget("xp").text, "Lv 10 10.0%")
    equal(widget("reputation").text, "Stormwind: Friendly 25%")
    equal(widget("reputation").gauge:GetValue(), 1500)
    equal(select(2, widget("reputation").gauge:GetMinMaxValues()), 6000)
    equal(widget("xp").gauge:GetValue(), 100)
    equal(select(2, widget("xp").gauge:GetMinMaxValues()), 1000)
    equal(widget("ammo").text, "|T4242:14:14:0:0|t 300")
    assert(widget("volume").volumeIcon.texture:find("volume%-medium%.tga"))
    assert(widget("volume").text:find("50%%$"))
    assert(widget("location").text:find("Test Zone (25.0, 75.0)", 1, true))
    equal(widget("eyes").text, ""); equal(widget("eyes").width, 40)
    for _, value in pairs(Menubar.runtime) do assert(not value.failed); assert(value.frame:IsShown()) end
    eyesShown(widget("eyes"), true)
end)

check("dynamic faction and ammunition lists configure the selected provider through host UI", function()
    local function choose(kind, current, choice)
        local value = widget(kind)
        Menubar.UI:OpenWidget(value.id)
        local found
        for _, control in ipairs(Menubar.UI.window.controls) do
            if control.Label and control.Label:GetText() == current then found = control; break end
        end
        assert(found, "Missing dynamic selection: " .. current)
        found:OpenMenu()
        Stub.MenuItem(Stub.menus[#Stub.menus], choice).callback()
    end
    choose("reputation", "Follow game's watched faction", "Stormwind")
    equal(widget("reputation").settings.factionID, 72)
    choose("ammo", "Auto: first carried projectile type", "Sharp Arrow")
    equal(widget("ammo").settings.selectedID, 1001)
    for _, control in ipairs(Menubar.UI.window.controls) do
        assert(control.caption ~= "Manual item ID (0 uses selection)")
    end
end)

local function chooseSetting(value, caption, choice)
    Menubar.UI:OpenWidget(value.id)
    local found
    for _, control in ipairs(Menubar.UI.window.controls) do
        if control.caption == caption and control.menubarControl == "select" then found = control; break end
    end
    assert(found, "Missing provider setting: " .. caption)
    found:OpenMenu()
    Stub.MenuItem(Stub.menus[#Stub.menus], choice).callback()
end

check("saved reputation and XP instances without a gauge style retain square defaults", function()
    for _, kind in ipairs({ "reputation", "xp" }) do widget(kind).settings.gaugeStyle = nil end
    Menubar:Rebuild()
    for _, kind in ipairs({ "reputation", "xp" }) do
        local value = widget(kind)
        equal(value.settings.gaugeStyle, "square")
        equal(value.gaugeStyleUsed, "square")
        assert(not value.failed and value.gaugeActive)
    end
    equal(widget("reputation").gauge:GetValue(), 1500)
    equal(widget("xp").gauge:GetValue(), 100)
end)

check("native provider settings select independent gauge styles without changing progress or fill", function()
    for _, kind in ipairs({ "reputation", "xp" }) do
        local first = widget(kind)
        local original, label = first.gauge, first.gaugeLabel
        local progress, maximum = first.gauge:GetValue(), select(2, first.gauge:GetMinMaxValues())
        local atlas = first.gauge:GetStatusBarTexture().atlas
        local red, green, blue = first.gauge:GetStatusBarColor()
        chooseSetting(first, "Gauge style", "Warcraft")
        equal(first.settings.gaugeStyle, "warcraft")
        equal(first.gaugeStyleUsed, "warcraft")
        equal(first.gauge, original); equal(first.gaugeLabel, label)
        equal(first.gauge:GetValue(), progress)
        equal(select(2, first.gauge:GetMinMaxValues()), maximum)
        equal(first.gauge:GetStatusBarTexture().atlas, atlas)
        local nextRed, nextGreen, nextBlue = first.gauge:GetStatusBarColor()
        equal(nextRed, red); equal(nextGreen, green); equal(nextBlue, blue)
        local instance = Menubar:AddWidget(kind, "top", "left")
        local second = Menubar.runtime[instance.id]
        equal(second.settings.gaugeStyle, "theme")
        equal(second.gaugeStyleUsed, "warcraft")
        assert(second.settings ~= first.settings and second.gauge ~= first.gauge)
        chooseSetting(second, "Gauge style", "Warcraft")
        chooseSetting(second, "Gauge style", "Square")
        Menubar:Rebuild()
        equal(first.settings.gaugeStyle, "warcraft")
        equal(second.settings.gaugeStyle, "square")
        equal(first.gaugeStyleUsed, "warcraft")
        equal(second.gaugeStyleUsed, "square")
        equal(first.instance.settings.gaugeStyle, "warcraft")
        Menubar:RemoveWidget(second.id)
        chooseSetting(first, "Gauge style", "Square")
    end
end)

check("Theme default picker follows real appearance and profile changes without rewriting widget choices", function()
    local profile = Menubar:GetProfile()
    local savedProfile = MenubarModel.DeepCopy(profile)
    local character = MenubarModel.GetCharacter(Menubar.db, Menubar.characterKey)
    local originalName = character.profile
    local snapshots = {}
    for _, kind in ipairs({ "xp", "reputation" }) do
        local value = widget(kind)
        snapshots[kind] = { value = value, style = value.settings.gaugeStyle, gauge = value.gauge, label = value.gaugeLabel,
            progress = value.gauge:GetValue(), maximum = select(2, value.gauge:GetMinMaxValues()),
            text = value.gaugeLabel:GetText(), bonus = value.xpRestedBonus }
        chooseSetting(value, "Gauge style", "Theme default")
        equal(value.settings.gaugeStyle, "theme")
    end
    local function chooseAppearance(caption, choice)
        Menubar.UI:OpenSettings()
        local found
        for _, control in ipairs(Menubar.UI.window.controls) do
            if control.caption == caption and control.menubarControl == "select" then found = control; break end
        end
        assert(found, "Missing appearance control: " .. caption)
        found:OpenMenu(); Stub.MenuItem(Stub.menus[#Stub.menus], choice).callback()
    end
    local function checkStyle(style)
        for kind, before in pairs(snapshots) do
            local value = widget(kind)
            equal(value, before.value); equal(value.gauge, before.gauge); equal(value.gaugeLabel, before.label)
            equal(value.gaugeStyleUsed, style); equal(value.settings.gaugeStyle, "theme")
            equal(value.instance.settings.gaugeStyle, "theme")
            equal(value.gauge:GetValue(), before.progress); equal(select(2, value.gauge:GetMinMaxValues()), before.maximum)
            equal(value.gaugeLabel:GetText(), before.text); equal(value.xpRestedBonus, before.bonus)
        end
    end
    chooseAppearance("Bar style", "Mac OS 7.6 (Harmony)"); checkStyle("square")
    chooseAppearance("Bar style", "Warcraft Brown"); checkStyle("warcraft")
    local mac = assert(MenubarModel.CreateProfile(Menubar.db, "Gauge theme Macs"))
    MenubarModel.ApplyTheme(mac, "macos8")
    chooseAppearance("Appearance profile", "Gauge theme Macs"); checkStyle("square")
    chooseAppearance("Appearance profile", originalName); checkStyle("warcraft")
    Menubar.db.profiles["Gauge theme Macs"] = nil
    for key in pairs(profile) do profile[key] = nil end
    for key, value in pairs(savedProfile) do profile[key] = value end
    for _, before in pairs(snapshots) do before.value.settings.gaugeStyle = before.style end
    Menubar:Rebuild()
end)
check("each provider reaches hover configuration and arrangement through actual UI", function()
    for _, source in ipairs(sources) do
        local value = widget(source[1])
        value.frame.scripts.OnEnter(value.frame)
        equal(GameTooltip:GetOwner(), value.frame); assert(#GameTooltip.lines >= 3)
        value.frame.scripts.OnClick(value.frame, "RightButton")
        equal(Menubar.UI.widgetID, value.id)
        shiftLeftClick(value.frame)
        assert(Stub.MenuItem(Stub.menus[#Stub.menus], "Move earlier"))
    end
end)

check("appearance resizing retains graphical runtime and recalculates constrained width", function()
    local value = widget("eyes")
    local frame, firstTexture, textureCount = value.frame, value.eyes[1].pupil, #textures
    value.settings.size = 24
    Menubar:GetProfile().height = 16
    Menubar:Rebuild()
    equal(widget("eyes"), value); equal(value.frame, frame)
    equal(value.content:GetHeight(), 11)
    equal(value.width, 30); equal(value.customWidth, 30); equal(value.frame:GetWidth(), 30)
    equal(value.eyes[1].pupil:GetHeight(), 3.4375)
    Menubar:GetProfile().height = 28
    Menubar:Rebuild()
    equal(value.content:GetHeight(), 23)
    equal(value.width, 54); equal(value.eyes[1].pupil:GetHeight(), 7.1875)
    equal(value.eyes[1].pupil, firstTexture); equal(#textures, textureCount)
    equal(callbacks.eyes.create, 1); equal(callbacks.eyes.destroy, 0)
end)

check("moving eyes between bars retains frame art and per-instance settings", function()
    local value = widget("eyes")
    local originalFrame, originalSettings = value.frame, value.settings
    Menubar:GetProfile().placement = "both"
    MenubarModel.MoveWidget(Menubar.db, Menubar.characterKey, value.id, "bottom", "center")
    Menubar:Rebuild()
    equal(widget("eyes").frame, originalFrame); equal(widget("eyes").settings, originalSettings)
    equal(value.frame:GetParent(), Menubar.bars.bottom)
    equal(value.frame.points[1][4] + value.width / 2, UIParent:GetWidth() / 2)
    equal(callbacks.eyes.create, 1); equal(callbacks.eyes.destroy, 0)
end)

check("normal graphical ticks change pupils without requesting host layout", function()
    Menubar.dirty = false
    local previousLayout = Menubar.Layout
    local layouts = 0
    Menubar.Layout = function(self, ...) layouts = layouts + 1; return previousLayout(self, ...) end
    tick(0.04)
    equal(layouts, 0)
    Menubar.Layout = previousLayout
end)

check("multiple graphical instances have independent art size and tracking choices", function()
    local first = widget("eyes")
    local instance = Menubar:AddWidget("eyes", "bottom", "left")
    local second = Menubar.runtime[instance.id]
    second.settings.appearance, second.settings.iris = "standard", "black"
    second.settings.followCursor = false
    second.settings.size = 12
    Menubar:RefreshWidget(second.id)
    equal(first.settings.size, 24); equal(first.width, 54); equal(second.width, 32)
    assert(first.eyes[1].pupil ~= second.eyes[1].pupil)
    assert(first.settings ~= second.settings)
    equal(second.eyes[1].pupil.points[1][4], -6)
    Menubar:RemoveWidget(second.id)
    eyesShown(second, false)
end)

check("disabling suspends the retained graphical view and reenabling restores saved choices", function()
    local original = widget("eyes")
    local instance, settings = original.instance, original.settings
    local destroysBefore = callbacks.eyes.destroy
    local deactivatesBefore, createsBefore = callbacks.eyes.deactivate, callbacks.eyes.create
    instance.enabled = false
    Menubar:Rebuild()
    equal(Menubar.runtime[instance.id], nil); assert(not original.frame:IsShown())
    eyesShown(original, false); equal(callbacks.eyes.destroy, destroysBefore)
    equal(callbacks.eyes.deactivate, deactivatesBefore + 1)
    instance.enabled = true
    Menubar:Rebuild()
    local restored = Menubar.runtime[instance.id]
    assert(restored and not restored.failed); equal(restored.settings, settings)
    equal(restored, original); equal(callbacks.eyes.create, createsBefore)
    equal(restored.width, 54); eyesShown(restored, true)
end)

check("currency events and network timers update their own displays alongside eyes", function()
    GetMoney = function() return 20001 end
    local networkBefore = callbacks.network.update
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "PLAYER_MONEY")
    equal(widget("currency").text, "2|A:coin-gold:14:14:0:0|a 0|A:coin-silver:14:14:0:0|a 1|A:coin-copper:14:14:0:0|a")
    equal(callbacks.network.update, networkBefore)
    GetNetStats = function() return 5, 2, 31, 95 end
    tick(1)
    equal(widget("network").text, "World 95 ms")
    assert(not widget("eyes").failed)
end)

check("XP events and location movement update alongside independent clock and money", function()
    currentXP = 200
    local currencyBefore = callbacks.currency.update
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "PLAYER_XP_UPDATE", "player")
    equal(widget("xp").text, "Lv 10 20.0%")
    equal(widget("xp").gauge:GetValue(), 200)
    equal(callbacks.currency.update, currencyBefore)
    coordinateX = 0.5
    tick(0.5)
    assert(widget("location").text:find("50.0, 75.0", 1, true))
    assert(not widget("eyes").failed and not widget("time").failed)
end)

check("rested status updates the native XP fill art without changing progress", function()
    local value = widget("xp")
    equal(value.gauge:GetStatusBarTexture().atlas, "UI-HUD-ExperienceBar-Fill-Experience")
    restState = 1
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "UPDATE_EXHAUSTION")
    equal(value.gauge:GetStatusBarTexture().atlas, "UI-HUD-ExperienceBar-Fill-Rested")
    equal(value.gauge:GetValue(), 200)
    restState = 2
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "UPDATE_EXHAUSTION")
    equal(value.gauge:GetStatusBarTexture().atlas, "UI-HUD-ExperienceBar-Fill-Experience")
end)

check("the actual XP provider renders and clears a clipped rested segment without adding it to reputation", function()
    local xp, reputation = widget("xp"), widget("reputation")
    local oldPool, oldStyle, oldPresentation, oldCurrent = GetXPExhaustion, xp.settings.gaugeStyle, xp.settings.presentation, currentXP
    local reputationValue = reputation.gauge:GetValue()
    local pool = 500
    GetXPExhaustion = function() return pool end
    currentXP = 750
    for _, style in ipairs({ "square", "warcraft" }) do
        xp.settings.gaugeStyle = style
        Menubar:RefreshWidget(xp.id)
        assert(not xp.failed)
        local prediction = style == "square" and xp.gaugeBonus or xp.gaugeWarcraftBonus
        local extent = style == "square" and (xp.width - 4) or xp.gaugeWarcraft.FillArea:GetWidth()
        assert(prediction and prediction:IsVisible())
        assert(math.abs(prediction:GetWidth() - extent * 0.25) < 0.00001)
        equal(xp.gauge:GetValue(), 750); equal(xp.gaugeLabel:GetText(), "Lv 10 75.0%")
        pool = 0
        Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "UPDATE_EXHAUSTION")
        assert(not prediction:IsShown()); equal(xp.gauge:GetValue(), 750)
        pool = 500
        Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "UPDATE_EXHAUSTION")
        assert(prediction:IsVisible())
        xp.settings.presentation = "text"; Menubar:RefreshWidget(xp.id)
        assert(not prediction:IsShown())
        xp.settings.presentation = "gauge"
        Menubar:RefreshWidget(reputation.id)
        equal(reputation.gauge:GetValue(), reputationValue)
        equal(reputation.gaugeBonus, nil); equal(reputation.gaugeWarcraftBonus, nil)
    end
    GetXPExhaustion, currentXP = oldPool, oldCurrent
    xp.settings.gaugeStyle, xp.settings.presentation = oldStyle, oldPresentation
    Menubar:RefreshWidget(xp.id)
end)

check("reported Barrens ownership refreshes as friendly or enemy without changing explicit PvP status", function()
    local value = widget("location")
    local oldZone, oldSubzone, oldPvP = GetRealZoneText, GetSubZoneText, C_PvP.GetZonePVPInfo
    local oldPlayerFaction, oldLegacy, oldColour = UnitFactionGroup, GetZonePVPInfo, value.settings.colorStatus
    GetRealZoneText = function() return "The Barrens" end
    GetSubZoneText = function() return "The Crossroads" end
    GetZonePVPInfo = nil
    C_PvP.GetZonePVPInfo = function() return nil, false, "Horde" end
    UnitFactionGroup = function() return "Horde", "Horde" end
    value.settings.colorStatus = false
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "ZONE_CHANGED_NEW_AREA")
    assert(not value.failed)
    assert(value.text:find("The Barrens", 1, true) and value.text:find("[Friendly]", 1, true))
    local rows = {}
    value.definition.tooltip(value, { AddLine = function() end,
        AddDoubleLine = function(_, key, text) rows[key] = text end })
    equal(rows.Territory, "Friendly"); equal(rows["Territory faction"], "Horde")
    UnitFactionGroup = function() return "Alliance", "Alliance" end
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "ZONE_CHANGED")
    assert(value.text:find("[Enemy]", 1, true))
    C_PvP.GetZonePVPInfo = function() return "contested", false, "Horde" end
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "ZONE_CHANGED")
    assert(value.text:find("[Contested]", 1, true))
    GetRealZoneText, GetSubZoneText, C_PvP.GetZonePVPInfo = oldZone, oldSubzone, oldPvP
    UnitFactionGroup, GetZonePVPInfo, value.settings.colorStatus = oldPlayerFaction, oldLegacy, oldColour
    Menubar:RefreshWidget(value.id)
end)

check("owned map fallback follows capabilities after loader acceptance", function()
    local value = widget("location")
    local oldMap, oldZone, oldSubzone, oldBuild = C_Map, GetRealZoneText, GetSubZoneText, GetBuildInfo
    local oldPvP, oldLegacy, oldFaction = C_PvP.GetZonePVPInfo, GetZonePVPInfo, UnitFactionGroup
    local oldInstance, oldFFA, oldColour = IsInInstance, UnitIsPVPFreeForAll, value.settings.colorStatus
    C_Map = {
        GetBestMapForUnit = function() return 1413 end,
        GetMapInfo = function() return { mapID = 1413, name = "The Barrens", mapType = 3 } end,
        GetAreaInfo = function(id) equal(id, 17); return "The Barrens" end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.637, 0.389 end } end,
    }
    GetRealZoneText = function() return "The Barrens" end
    GetSubZoneText = function() return "Ratchet" end
    local patchBuild = "71037"
    local metadataQueries = 0
    GetBuildInfo = function()
        metadataQueries = metadataQueries + 1
        return "1.60.2", patchBuild, "Nov 20 2026", 16002
    end
    C_PvP.GetZonePVPInfo = function() end
    GetZonePVPInfo = nil
    UnitFactionGroup = function() return "Horde", "Horde" end
    IsInInstance = function() return false, "none" end
    UnitIsPVPFreeForAll = function() return false end
    value.settings.colorStatus = false
    for _, build in ipairs({ "71037", "99999" }) do
        patchBuild = build
        Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "ZONE_CHANGED_NEW_AREA")
        assert(not value.failed)
        equal(value.text, "The Barrens (63.7, 38.9) [Friendly]")
    end
    local rows, notes = {}, {}
    value.definition.tooltip(value, { AddLine = function(_, text) notes[#notes + 1] = text end,
        AddDoubleLine = function(_, key, text) rows[key] = text end })
    equal(rows["Territory faction"], "Horde")
    assert(not table.concat(notes, " "):find("live PvP status unavailable", 1, true))
    equal(MenubarLocationDiagnostics().source, "clientData")
    equal(metadataQueries, 0)
    IsInInstance = function() return true, "party" end
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "ZONE_CHANGED_NEW_AREA")
    assert(value.text:find("[Unknown]", 1, true))
    IsInInstance = function() return false, "none" end
    C_PvP.GetZonePVPInfo = function() return "sanctuary", false end
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "ZONE_CHANGED_NEW_AREA")
    assert(value.text:find("[Sanctuary]", 1, true))
    C_Map, GetRealZoneText, GetSubZoneText, GetBuildInfo = oldMap, oldZone, oldSubzone, oldBuild
    C_PvP.GetZonePVPInfo, GetZonePVPInfo, UnitFactionGroup = oldPvP, oldLegacy, oldFaction
    IsInInstance, UnitIsPVPFreeForAll, value.settings.colorStatus = oldInstance, oldFFA, oldColour
    Menubar:RefreshWidget(value.id)
end)

check("reputation event updates watched progress without changing other widgets", function()
    local currencyBefore, networkBefore = callbacks.currency.update, callbacks.network.update
    factionStanding = 6000
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "FACTION_STANDING_CHANGED", 72)
    equal(widget("reputation").text, "Stormwind: Friendly 50%")
    equal(widget("reputation").gauge:GetValue(), 3000)
    equal(callbacks.currency.update, currencyBefore); equal(callbacks.network.update, networkBefore)
end)

check("name-only reputation stays unpunctuated in text and both gauge styles", function()
    local value = widget("reputation")
    local previous = {}
    for _, key in ipairs({ "presentation", "gaugeStyle", "showName", "showStanding", "progress" }) do
        previous[key] = value.settings[key]
    end
    value.settings.showName, value.settings.showStanding, value.settings.progress = true, false, "none"
    for _, presentation in ipairs({ "gauge", "text" }) do
        for _, style in ipairs({ "square", "warcraft" }) do
            value.settings.presentation, value.settings.gaugeStyle = presentation, style
            Menubar:RefreshWidget(value.id)
            assert(not value.failed)
            equal(value.text, "Stormwind")
            if presentation == "gauge" then equal(value.gaugeLabel:GetText(), "Stormwind")
            else equal(value.label:GetText(), "Stormwind") end
        end
    end
    for key, setting in pairs(previous) do value.settings[key] = setting end
    Menubar:RefreshWidget(value.id)
end)

check("an unset reputation widget can read the exposed watched-row fallback", function()
    local value, direct = widget("reputation"), C_Reputation.GetWatchedFactionData
    local previousSelection = value.settings.factionID
    value.settings.factionID = nil
    watchedFactionID = 99
    C_Reputation.GetWatchedFactionData = function() return nil end
    Menubar:RefreshWidget(value.id)
    equal(value.reputationState.factionID, 99)
    equal(value.text, "Other faction: Friendly 50%")
    equal(watchedFactionID, 99)
    C_Reputation.GetWatchedFactionData, watchedFactionID = direct, 72
    value.settings.factionID = previousSelection
    Menubar:RefreshWidget(value.id)
end)

check("watched faction changes leave a fixed choice intact and refresh watched selection", function()
    local value = widget("reputation")
    watchedFactionID = 99
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "UPDATE_FACTION")
    equal(value.text, "Stormwind: Friendly 50%")
    value.settings.factionID = 0
    Menubar:RefreshWidget(value.id)
    equal(value.text, "Other faction: Friendly 50%")
    watchedFactionID = 72
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "UPDATE_FACTION")
    equal(value.text, "Stormwind: Friendly 50%")
end)

check("bag changes refresh focused ammunition without touching independent widgets", function()
    ammoCount = 275
    local currencyBefore, reputationBefore = callbacks.currency.update, callbacks.reputation.update
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "BAG_UPDATE_DELAYED")
    equal(widget("ammo").text, "|T4242:14:14:0:0|t 275")
    equal(callbacks.currency.update, currencyBefore); equal(callbacks.reputation.update, reputationBefore)
end)

check("volume widget wheel changes the shared master setting and refreshes its native icon", function()
    local value = widget("volume")
    assert(value.frame.scripts.OnMouseWheel, "The host must wire provider mouse-wheel input")
    value.frame.scripts.OnMouseWheel(value.frame, 1)
    equal(tonumber(cvars.Sound_MasterVolume), 0.55)
    assert(value.text:find("55%%$"))
    value.frame.scripts.OnMouseWheel(value.frame, -1)
    equal(tonumber(cvars.Sound_MasterVolume), 0.5)
    local currencyBefore = callbacks.currency.update
    cvars.Sound_MasterVolume = "0.82"
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "CVAR_UPDATE", "Sound_MasterVolume", "0.82")
    assert(value.volumeIcon.texture:find("volume%-high%.tga"))
    assert(value.text:find("82%%$"))
    equal(callbacks.currency.update, currencyBefore)
end)

local function volumeSlider(orientation)
    local value = widget("volume")
    value.settings.orientation = orientation
    shiftLeftClick(value.frame)
    local menu = Stub.menus[#Stub.menus]
    local description
    for _, child in ipairs(menu.children) do
        if child.kind == "Frame" and child.initializers and #child.initializers > 0 then description = child; break end
    end
    assert(description, "Volume context menu must contain a native slider frame")
    local frame = CreateFrame("Frame", nil, UIParent)
    local count = #Stub.frames
    for _, initialize in ipairs(description.initializers) do initialize(frame, description, menu) end
    local slider
    for index = count + 1, #Stub.frames do if Stub.frames[index].kind == "Slider" then slider = Stub.frames[index]; break end end
    assert(slider, "Volume menu initializer must attach a native Slider")
    return value, frame, slider, menu
end

check("Shift-left-click volume context builds a native horizontal slider without an initial write", function()
    local count = #audioWrites
    local value, frame, slider = volumeSlider("horizontal")
    equal(#audioWrites, count)
    equal(slider.orientation, "HORIZONTAL")
    equal(slider:GetValue(), 82)
    slider:SetValue(65)
    equal(tonumber(cvars.Sound_MasterVolume), 0.65)
    assert(value.text:find("65%%$"))
    assert(Stub.MenuItem(Stub.menus[#Stub.menus], "Move earlier"))
end)

check("vertical volume context maps upward motion to greater master volume", function()
    local value, frame, slider, menu = volumeSlider("vertical")
    equal(slider.orientation, "VERTICAL")
    equal(slider:GetValue(), 35)
    slider:SetValue(0)
    equal(tonumber(cvars.Sound_MasterVolume), 1)
    slider:SetValue(100)
    equal(tonumber(cvars.Sound_MasterVolume), 0)
    local mute = Stub.MenuItem(menu, "|A:voicechat-icon-speaker-mute:14:14|a Mute")
    mute.callback()
    equal(tonumber(cvars.Sound_EnableAllSound), 0)
    equal(tonumber(cvars.Sound_MasterVolume), 0)
    assert(value.volumeIcon.texture:find("volume%-muted%.tga"))
    mute.callback()
    equal(tonumber(cvars.Sound_EnableAllSound), 1)
end)

check("provider errors remain isolated and graphical recovery clears the error label", function()
    local value = widget("eyes")
    local definition, previousUpdate = value.definition, value.definition.update
    definition.update = function() error("simulated graphical failure") end
    Menubar:RefreshWidget(value.id)
    assert(value.failed); assert(value.text:find("error", 1, true))
    assert(value.width >= value.label:GetStringWidth() + 8, "graphical error text must remain readable")
    local networkBefore = callbacks.network.update
    tick(1)
    assert(callbacks.network.update > networkBefore)
    assert(not widget("network").failed and not widget("time").failed)
    definition.update = previousUpdate
    Menubar:RefreshWidget(value.id)
    equal(value.failed, nil); equal(value.text, "")
    equal(value.width, 54); equal(value.customWidth, 54); equal(value.frame:GetWidth(), 54)
    eyesShown(value, true)
end)

check("failed graphical widgets still invoke cleanup on removal", function()
    local value = widget("eyes")
    local definition, previousUpdate = value.definition, value.definition.update
    definition.update = function() error("simulated removal failure") end
    Menubar:RefreshWidget(value.id)
    local destroyed = callbacks.eyes.destroy
    Menubar:RemoveWidget(value.id)
    equal(callbacks.eyes.destroy, destroyed + 1)
    eyesShown(value, false)
    definition.update = previousUpdate
end)

print(string.format("%d cross-addon provider integration tests passed", passed))
