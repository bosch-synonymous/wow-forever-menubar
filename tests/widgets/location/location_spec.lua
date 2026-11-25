local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local provider
Menubar = { RegisterWidgetType = function(_, definition) provider = definition end }
local zone, subzone = "Elwynn Forest", "Goldshire"
local mapID, x, y, kind, subzonePvP, faction = 37, 0.1234, 0.5678, "friendly", false, "Alliance"
local restricted = setmetatable({}, {
    __lt = function() error("restricted comparison") end,
    __le = function() error("restricted comparison") end,
    __tostring = function() error("restricted display") end,
})
issecretvalue = function(value) return rawequal(value, restricted) end
GetRealZoneText = function() return zone end
GetSubZoneText = function() return subzone end
C_Map = {
    GetBestMapForUnit = function(unit) equal(unit, "player"); return mapID end,
    GetPlayerMapPosition = function(id, unit)
        equal(id, mapID); equal(unit, "player")
        return { GetXY = function() return x, y end }
    end,
}
C_PvP = { GetZonePVPInfo = function() return kind, subzonePvP, faction end }
dofile("src/menubar-location/TerritoryData.lua")
dofile("src/menubar-location/Location.lua")

local function render(overrides)
    local options = {}
    for key, value in pairs(provider.defaults) do options[key] = value end
    for key, value in pairs(overrides or {}) do options[key] = value end
    local widget = { settings = options }
    function widget:SetText(text) self.text = text end
    provider.update(widget)
    return widget.text, widget
end
local function tipFor(widget)
    local tip = { lines = {}, rows = {} }
    function tip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tip:AddDoubleLine(key, value) self.rows[key] = value end
    provider.tooltip(widget, tip)
    return tip
end
local function baseline(tip)
    return table.concat(tip.lines, "\n"):find("Baseline territory", 1, true) ~= nil
end
local function test(name, callback)
    callback(); passed = passed + 1; print("PASS " .. name)
end

test("default zone coordinates and classification are visible", function()
    equal(provider.id, "location")
    equal(provider.interval, 0.5)
    equal(render(), "Elwynn Forest (12.3, 56.8) [|cff287A36Friendly|r]")
end)
test("Friendly uses a pale green on dark surfaces and honours custom backgrounds", function()
    local profile = { theme = "macos27", texture = "theme", background = { 0.055, 0.07, 0.09, 0.86 },
        opacity = 0.45, textColor = { 1, 1, 1, 1 } }
    Menubar.GetProfile = function() return profile end
    local previousSkins = MenubarSkins
    MenubarSkins = { IsWarcraft = function(theme) return theme == "warcraftBrown" end }
    local function expected(green)
        equal(render({ showCoordinates = false }), "Elwynn Forest [|cff" .. green .. "Friendly|r]")
    end
    expected("8BE99A")
    profile.theme, profile.background = "macosx", { 0.94, 0.95, 0.96, 1 }
    expected("287A36")
    profile.theme, profile.background = "warcraftBrown", { 1, 1, 1, 1 }
    expected("8BE99A")
    profile.texture = "solid" -- A white swatch is the surface itself here.
    expected("287A36")
    profile.background = { 0, 0, 0, 1 }
    expected("8BE99A")
    profile.texture = "Custom\\Background.tga"
    expected("8BE99A")
    profile.textColor = { 0, 0, 0, 1 }
    expected("287A36")
    profile.texture, profile.opacity = "solid", 0
    expected("287A36")
    profile.textColor = { 1, 1, 1, 1 }
    expected("8BE99A")
    kind = "hostile"
    equal(render({ showCoordinates = false }), "Elwynn Forest [|cffB02020Enemy|r]")
    kind = "friendly"
    Menubar.GetProfile, MenubarSkins = nil, previousSkins
end)

test("zone subzone and combined names are selectable", function()
    equal(render({ name = "subzone", showCoordinates = false, showStatus = false }), "Goldshire")
    equal(render({ name = "both", showCoordinates = false, showStatus = false }), "Elwynn Forest: Goldshire")
    subzone = zone
    equal(render({ name = "both", showCoordinates = false, showStatus = false }), "Elwynn Forest")
    subzone = "Goldshire"
end)
test("missing subzone falls back without an empty name", function()
    subzone = ""
    equal(render({ name = "subzone", showCoordinates = false, showStatus = false }), "Elwynn Forest")
    subzone = "Goldshire"
end)
test("precision and uncolored status use saved instance settings", function()
    equal(render({ decimals = 2, colorStatus = false }), "Elwynn Forest (12.34, 56.78) [Friendly]")
    equal(render({ decimals = 0, showStatus = false }), "Elwynn Forest (12, 57)")
end)
test("all known territory types have readable labels", function()
    local cases = {
        sanctuary = "Sanctuary", friendly = "Friendly", hostile = "Enemy",
        contested = "Contested", combat = "Combat zone", arena = "Free-for-all",
    }
    for value, label in pairs(cases) do
        kind = value
        local shown, widget = render({ showCoordinates = false, colorStatus = false })
        equal(shown, "Elwynn Forest [" .. label .. "]")
        equal(tipFor(widget).rows.Territory, label)
    end
    kind = "friendly"
end)
test("unknown classifications remain on the bar but their tooltip row is omitted", function()
    for _, value in ipairs({ false, "future-category", restricted, 123 }) do
        kind = value or nil
        local shown, widget = render({ showCoordinates = false, colorStatus = false })
        equal(shown, "Elwynn Forest [Unknown]")
        local tip = tipFor(widget)
        equal(tip.rows.Territory, nil)
        equal(tip.rows["Territory faction"], "Alliance")
        equal(tip.rows.Zone, "Elwynn Forest")
    end
    kind = "friendly"
end)
test("an unavailable world map does not invent coordinates", function()
    mapID = nil
    equal(render({ showStatus = false }), "Elwynn Forest (--, --)")
    local _, widget = render()
    equal(tipFor(widget).rows.Coordinates, "Unavailable")
    mapID = 37
end)
test("malformed map identifiers never reach native position lookups", function()
    local previous = C_Map.GetPlayerMapPosition
    local lookups = 0
    C_Map.GetPlayerMapPosition = function() lookups = lookups + 1; error("invalid map ID reached native lookup") end
    for _, value in ipairs({ 0 / 0, math.huge, -math.huge, 1.5, 0, -1, "37" }) do
        mapID = value
        equal(render({ showStatus = false }), "Elwynn Forest (--, --)")
    end
    equal(lookups, 0)
    mapID, C_Map.GetPlayerMapPosition = 37, previous
end)
test("valid map corners remain real coordinates", function()
    x, y = 0, 0
    equal(render({ showStatus = false }), "Elwynn Forest (0.0, 0.0)")
    x, y = 1, 1
    equal(render({ showStatus = false }), "Elwynn Forest (100.0, 100.0)")
    x, y = 0.1234, 0.5678
end)
test("out of bounds and restricted coordinates remain unavailable", function()
    x = 1.1
    equal(render({ showStatus = false }), "Elwynn Forest (--, --)")
    x = restricted
    equal(render({ showStatus = false }), "Elwynn Forest (--, --)")
    x = 0.1234
    mapID = restricted
    equal(render({ showStatus = false }), "Elwynn Forest (--, --)")
    mapID = 37
end)
test("restricted names and classification are not displayed or compared", function()
    local previousZone, previousSubzone, previousKind = zone, subzone, kind
    zone, subzone, kind = restricted, restricted, restricted
    equal(render({ showCoordinates = false, colorStatus = false }), "Unknown zone [Unknown]")
    zone, subzone, kind = previousZone, previousSubzone, previousKind
end)
test("missing APIs remain usable with explicit unknown data", function()
    local previousMap, previousPvP = C_Map, C_PvP
    C_Map, C_PvP = nil, nil
    local shown, widget = render({ colorStatus = false })
    equal(shown, "Elwynn Forest (--, --) [Unknown]")
    equal(tipFor(widget).rows.Territory, nil)
    C_Map, C_PvP = previousMap, previousPvP
end)
test("restricted API calls do not break other information", function()
    local previous = C_Map.GetPlayerMapPosition
    C_Map.GetPlayerMapPosition = function() error("restricted call") end
    equal(render({ showStatus = false }), "Elwynn Forest (--, --)")
    C_Map.GetPlayerMapPosition = previous
end)
test("tooltip includes zone subzone coordinates and territory details", function()
    local _, widget = render()
    local tip = tipFor(widget)
    equal(tip.rows.Zone, "Elwynn Forest")
    equal(tip.rows.Subzone, "Goldshire")
    equal(tip.rows.Coordinates, "12.3, 56.8")
    equal(tip.rows.Territory, "Friendly")
    equal(tip.rows["Territory faction"], "Alliance")
    equal(tip.rows["PvP subzone"], nil)
end)
test("tooltip omits empty or duplicate subzones and routine safety prose", function()
    local previous = subzone
    for _, value in ipairs({ "", zone }) do
        subzone = value
        local _, widget = render()
        local tip = tipFor(widget)
        equal(tip.rows.Subzone, nil)
        equal(tip.rows.Zone, zone)
        assert(not table.concat(tip.lines, "\n"):find("guarantee of safety", 1, true))
    end
    subzone = previous
end)
test("independent instances keep location display choices", function()
    local _, first = render({ name = "subzone", showCoordinates = false, showStatus = false })
    local _, second = render({ decimals = 2, showStatus = false })
    first.settings.name = "both"
    provider.update(first); provider.update(second)
    equal(first.text, "Elwynn Forest: Goldshire")
    equal(second.text, "Elwynn Forest (12.34, 56.78)")
    equal(provider.defaults.name, "zone")
end)

local function territoryCase(callback)
    local saved = { C_PvP, GetZonePVPInfo, UnitFactionGroup, FACTION_HORDE, FACTION_ALLIANCE,
        zone, subzone, kind, subzonePvP, faction }
    zone, subzone, kind, subzonePvP, faction = "The Barrens", "The Crossroads", nil, false, "Horde"
    C_PvP = { GetZonePVPInfo = function() return kind, subzonePvP, faction end }
    GetZonePVPInfo, FACTION_HORDE, FACTION_ALLIANCE = nil, nil, nil
    UnitFactionGroup = function(unit) equal(unit, "player"); return "Horde", "Horde" end
    local ok, reason = pcall(callback)
    C_PvP, GetZonePVPInfo, UnitFactionGroup, FACTION_HORDE, FACTION_ALLIANCE = unpack(saved, 1, 5)
    zone, subzone, kind, subzonePvP, faction = unpack(saved, 6, 10)
    if not ok then error(reason, 0) end
end

test("missing classification uses reported Horde ownership relative to the player", function()
    territoryCase(function()
        local shown, widget = render({ showCoordinates = false, colorStatus = false })
        equal(shown, "The Barrens [Friendly]")
        local tip = tipFor(widget)
        equal(tip.rows.Territory, "Friendly")
        equal(tip.rows["Territory faction"], "Horde")
        equal(tip.rows["PvP subzone"], nil)
        equal(render({ showCoordinates = false }), "The Barrens [|cff287A36Friendly|r]")
        UnitFactionGroup = function() return "Alliance", "Alliance" end
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Enemy]")
        faction = "Alliance"
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Friendly]")
    end)
end)

test("missing territory types support comparable localized faction names", function()
    territoryCase(function()
        kind = ""
        FACTION_HORDE, FACTION_ALLIANCE = "La Horde", "L'Alliance"
        UnitFactionGroup = function() return "Horde", "La Horde" end
        faction = "La Horde"
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Friendly]")
        faction = "L'Alliance"
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Enemy]")
        FACTION_HORDE, FACTION_ALLIANCE = nil, nil
        faction = "La Horde"
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Friendly]")
    end)
end)

test("a present legacy zone API supplies classifications missing from the modern entry point", function()
    territoryCase(function()
        local legacyCalls = 0
        C_PvP.GetZonePVPInfo = function() return nil end
        GetZonePVPInfo = function() legacyCalls = legacyCalls + 1; return "friendly", false, "Horde" end
        local shown, widget = render({ showCoordinates = false, colorStatus = false })
        equal(shown, "The Barrens [Friendly]")
        equal(tipFor(widget).rows["Territory faction"], "Horde")
        equal(legacyCalls, 2)
        C_PvP = nil
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Friendly]")
        C_PvP = { GetZonePVPInfo = function() error("API unavailable") end }
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Friendly]")
        GetZonePVPInfo = function() return "hostile", false, "Alliance" end
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Enemy]")
    end)
end)

test("partial zone results merge missing ownership without losing affirmative PvP flags", function()
    territoryCase(function()
        faction = nil
        GetZonePVPInfo = function() return nil, false, "Horde" end
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Friendly]")
        local _, widget = render()
        equal(tipFor(widget).rows["Territory faction"], "Horde")
        GetZonePVPInfo = function() return nil, true, "Horde" end
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
        local _, pvp = render()
        equal(tipFor(pvp).rows["PvP subzone"], "Yes")
        subzonePvP = true
        GetZonePVPInfo = function() return nil, false, "Horde" end
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
        local _, modernPvP = render()
        equal(tipFor(modernPvP).rows["PvP subzone"], "Yes")
    end)
end)

test("restricted PvP flags never become an inferred friendly or enemy classification", function()
    territoryCase(function()
        subzonePvP = restricted
        GetZonePVPInfo = function() return nil, false, "Horde" end
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
        local _, primaryRestricted = render()
        equal(tipFor(primaryRestricted).rows["PvP subzone"], nil)
        subzonePvP = false
        GetZonePVPInfo = function() return nil, restricted, "Horde" end
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
        local _, legacyRestricted = render()
        equal(tipFor(legacyRestricted).rows["PvP subzone"], nil)
    end)
end)

test("explicit modern territory categories take priority over ownership or legacy data", function()
    territoryCase(function()
        GetZonePVPInfo = function() error("An explicit modern category must not query legacy data") end
        for _, sample in ipairs({ { "contested", "Contested" }, { "sanctuary", "Sanctuary" },
            { "arena", "Free-for-all" }, { "hostile", "Enemy" }, { "future-category", "Unknown" } }) do
            kind = sample[1]
            equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [" .. sample[2] .. "]")
        end
        kind = restricted
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
        kind = 123
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
    end)
end)

test("missing or unrecognized ownership does not invent friendly territory", function()
    territoryCase(function()
        for _, owner in ipairs({ false, "", "Neutral", "Unrecognized faction", restricted }) do
            faction = owner or nil
            equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
        end
        faction = "Horde"
        for _, player in ipairs({ false, "Neutral", "Unrecognized faction", restricted }) do
            UnitFactionGroup = function() return player or nil, "Unrecognized faction" end
            equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
        end
        UnitFactionGroup = nil
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
        UnitFactionGroup = function() error("Unavailable faction") end
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
    end)
end)

test("an unclassified PvP subzone does not inherit its surrounding faction's friendly status", function()
    territoryCase(function()
        subzonePvP = true
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
        local _, widget = render()
        local tip = tipFor(widget)
        equal(tip.rows.Territory, nil)
        equal(tip.rows["Territory faction"], "Horde")
        equal(tip.rows["PvP subzone"], "Yes")
        kind = "arena"
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Free-for-all]")
    end)
end)

test("legacy aliases and restricted fallback values remain safe without duplicated reads", function()
    territoryCase(function()
        local calls = 0
        local absent = function() calls = calls + 1; return nil end
        C_PvP.GetZonePVPInfo, GetZonePVPInfo = absent, absent
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
        equal(calls, 1)
        GetZonePVPInfo = function() return restricted, restricted, restricted end
        local _, widget = render({ showCoordinates = false, colorStatus = false })
        equal(widget.text, "The Barrens [Unknown]")
        equal(tipFor(widget).rows["Territory faction"], nil)
        GetZonePVPInfo = function() error("Unavailable compatibility API") end
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
    end)
end)

-- Reproduce the user's real return shape: the modern API returns no values and
-- the old global API does not exist. The map/area information is independent.
local function staticTerritoryCase(callback)
    local globals = { "C_Map", "C_PvP", "GetZonePVPInfo", "UnitFactionGroup", "GetBuildInfo", "IsInInstance",
        "UnitIsPVPFreeForAll", "FACTION_HORDE", "FACTION_ALLIANCE", "SetMapToCurrentZone", "SetMapZoom",
        "SetCVar", "C_CVar", "GetInstanceInfo", "C_Minimap" }
    local saved, oldZone, oldSubzone = {}, zone, subzone
    for _, name in ipairs(globals) do saved[name] = _G[name] end
    local state = { mapID = 1413, infoMapID = 1413, mapType = 3, mapName = "The Barrens", areaName = "The Barrens",
        version = "1.60.1", build = "71037", interface = 16001, inInstance = false, freeForAll = false,
        player = "Horde", localizedPlayer = "Horde", lookups = 0, writes = 0, metadataReads = 0 }
    local function forbiddenWrite() state.writes = state.writes + 1; error("Location must not alter map selection or CVars") end
    zone, subzone = "The Barrens", "The Crossroads"
    GetZonePVPInfo, FACTION_HORDE, FACTION_ALLIANCE = nil, nil, nil
    C_PvP = { GetZonePVPInfo = function() end }
    GetBuildInfo = function()
        state.metadataReads = state.metadataReads + 1
        return state.version, state.build, "Nov 19 2026", state.interface
    end
    IsInInstance = function() return state.inInstance, state.inInstance and "party" or "none" end
    UnitIsPVPFreeForAll = function(unit) equal(unit, "player"); return state.freeForAll end
    UnitFactionGroup = function(unit) equal(unit, "player"); return state.player, state.localizedPlayer end
    C_Map = {
        GetBestMapForUnit = function(unit) equal(unit, "player"); return state.mapID end,
        GetMapInfo = function(id)
            equal(id, state.mapID)
            return { mapID = state.infoMapID, mapType = state.mapType, name = state.mapName, parentMapID = 1414, flags = 0 }
        end,
        GetAreaInfo = function(id)
            assert(id == 17 or id == 12, "Fixture expects a canonical Barrens or Elwynn area lookup")
            state.lookups = state.lookups + 1
            return state.areaName
        end,
        GetPlayerMapPosition = function(id, unit)
            equal(id, state.mapID); equal(unit, "player")
            return { GetXY = function() return 0.524, 0.294 end }
        end,
        SetMapByID = forbiddenWrite,
    }
    SetMapToCurrentZone, SetMapZoom, SetCVar = forbiddenWrite, forbiddenWrite, forbiddenWrite
    C_CVar = { SetCVar = forbiddenWrite }
    local ok, reason = pcall(callback, state)
    zone, subzone = oldZone, oldSubzone
    for _, name in ipairs(globals) do _G[name] = saved[name] end
    if not ok then error(reason, 0) end
    equal(state.writes, 0)
end

test("verified Barrens ownership works with an empty modern query and no legacy function", function()
    staticTerritoryCase(function(state)
        for _, build in ipairs({ "70938", "70959" }) do
            state.build = build
            local shown, widget = render({ colorStatus = false })
            equal(shown, "The Barrens (52.4, 29.4) [Friendly]")
            local tip = tipFor(widget)
            equal(tip.rows.Territory, "Friendly")
            equal(tip.rows["Territory faction"], "Horde")
            equal(baseline(tip), false)
            equal(MenubarLocationDiagnostics().source, "clientData")
            equal(tip.rows["PvP subzone"], nil)
            state.player, state.localizedPlayer = "Alliance", "Alliance"
            equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Enemy]")
            state.player, state.localizedPlayer = "Horde", "Horde"
        end
    end)
end)

test("a binary patch does not disable unchanged ownership in the same client family", function()
    staticTerritoryCase(function(state)
        subzone = "Ratchet"
        for _, build in ipairs({ "71037", "99999" }) do
            state.build = build
            local shown, widget = render({ showCoordinates = false, colorStatus = false })
            equal(shown, "The Barrens [Friendly]")
            equal(baseline(tipFor(widget)), false)
            equal(render({ name = "both", showCoordinates = false, colorStatus = false }),
                "The Barrens: Ratchet [Friendly]")
            state.player, state.localizedPlayer = "Alliance", "Alliance"
            equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Enemy]")
            state.player, state.localizedPlayer = "Horde", "Horde"
        end
        equal(state.writes, 0)
    end)
end)

test("unused binary-build metadata is neither inspected nor formatted", function()
    staticTerritoryCase(function(state)
        local malformed = setmetatable({}, { __tostring = function() error("unused build formatted") end })
        for _, build in ipairs({ restricted, malformed }) do
            state.build = build
            local shown, widget = render({ showCoordinates = false, colorStatus = false })
            equal(shown, "The Barrens [Friendly]")
            equal(baseline(tipFor(widget)), false)
        end
    end)
end)

test("verified world territory data uses map and localized area identity rather than English zone matching", function()
    staticTerritoryCase(function(state)
        zone, subzone, state.mapName, state.areaName = "Das Brachland", "Das Wegekreuz", "Das Brachland", "Das Brachland"
        equal(render({ showCoordinates = false, colorStatus = false }), "Das Brachland [Friendly]")
        zone, subzone, state.mapName, state.areaName = "Elwynn Forest", "Goldshire", "Elwynn Forest", "Elwynn Forest"
        state.mapID, state.infoMapID = 1429, 1429
        equal(render({ showCoordinates = false, colorStatus = false }), "Elwynn Forest [Enemy]")
        state.player, state.localizedPlayer = "Alliance", "Alliance"
        equal(render({ showCoordinates = false, colorStatus = false }), "Elwynn Forest [Friendly]")
    end)
end)

test("explicit live and unrecognized territory types never consult the static ownership fallback", function()
    staticTerritoryCase(function(state)
        for _, sample in ipairs({ { "friendly", "Friendly" }, { "hostile", "Enemy" }, { "sanctuary", "Sanctuary" },
            { "contested", "Contested" }, { "arena", "Free-for-all" }, { "combat", "Combat zone" },
            { "future-category", "Unknown" }, { restricted, "Unknown" } }) do
            C_PvP.GetZonePVPInfo = function() return sample[1] end
            local shown, widget = render({ showCoordinates = false, colorStatus = false })
            equal(shown, "The Barrens [" .. sample[2] .. "]")
            equal(tipFor(widget).rows.Territory, sample[2] ~= "Unknown" and sample[2] or nil)
            equal(baseline(tipFor(widget)), false)
        end
        equal(state.lookups, 0)
    end)
end)

test("a reported owner or a restricted owner is never replaced by static ownership", function()
    staticTerritoryCase(function(state)
        for _, owner in ipairs({ "Neutral", "Unrecognized faction", restricted }) do
            C_PvP.GetZonePVPInfo = function() return nil, false, owner end
            equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
        end
        C_PvP.GetZonePVPInfo = function() return nil, false, "Alliance" end
        local shown, widget = render({ showCoordinates = false, colorStatus = false })
        equal(shown, "The Barrens [Enemy]")
        equal(tipFor(widget).rows["Territory faction"], "Alliance")
        equal(baseline(tipFor(widget)), false)
        equal(state.lookups, 0)
    end)
end)

test("static ownership never classifies active or restricted PvP subzones", function()
    for _, flag in ipairs({ true, restricted }) do
        staticTerritoryCase(function(state)
            C_PvP.GetZonePVPInfo = function() return nil, flag end
            equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
            equal(state.lookups, 0)
        end)
    end
end)

test("client version labels do not disable valid current map ownership", function()
    local cases = {
        function(state) state.version = "1.15.8" end,
        function(state) state.version, state.interface = "1.60.2", 16002 end,
        function(state) state.version = nil end,
        function(state) state.version = restricted end,
        function(state) state.interface = 11508 end,
        function(state) state.interface = nil end,
        function(state) state.interface = restricted end,
        function() GetBuildInfo = nil end,
        function(state) GetBuildInfo = function()
            state.metadataReads = state.metadataReads + 1
            error("Client metadata is unavailable")
        end end,
    }
    for _, change in ipairs(cases) do
        staticTerritoryCase(function(state)
            change(state)
            local shown, widget = render({ showCoordinates = false, colorStatus = false })
            equal(shown, "The Barrens [Friendly]")
            equal(baseline(tipFor(widget)), false)
            equal(state.metadataReads, 0)
        end)
    end
end)

test("unavailable instance state cannot justify static ownership", function()
    for _, change in ipairs({ function(state) state.inInstance = restricted end,
        function() IsInInstance = nil end,
        function() IsInInstance = function() error("Instance state unavailable") end end }) do
        staticTerritoryCase(function(state)
            change(state)
            equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
        end)
    end
end)

test("unverified maps and mismatching map or area names do not borrow a nearby owned zone", function()
    local cases = {
        function(state) state.mapID, state.infoMapID = 9999, 9999 end,
        function(state) state.mapID = restricted end,
        function(state) state.infoMapID = 1429 end,
        function(state) state.infoMapID = restricted end,
        function(state) state.mapType = 4 end,
        function(state) state.mapType = restricted end,
        function(state) state.mapName = "Other map" end,
        function(state) state.mapName = restricted end,
        function(state) state.areaName = "Other area" end,
        function(state) state.areaName = restricted end,
        function() zone = "Other zone" end,
        function() C_Map.GetMapInfo = function() return nil end end,
        function() C_Map.GetAreaInfo = nil end,
        function() C_Map.GetAreaInfo = function() error("Area lookup unavailable") end end,
    }
    for _, change in ipairs(cases) do
        staticTerritoryCase(function(state)
            change(state)
            local shown = render({ showCoordinates = false, colorStatus = false })
            assert(shown:find("[Unknown]", 1, true), shown)
        end)
    end
    staticTerritoryCase(function(state)
        state.infoMapID = 1429
        local diagnostics = MenubarLocationDiagnostics()
        equal(diagnostics.state.label, "Unknown")
        equal(diagnostics.fallbackReason, "map-identity")
    end)
end)

test("free-for-all status or an unreadable free-for-all check prevents static friendly labels", function()
    for _, change in ipairs({ function(state) state.freeForAll = true end,
        function(state) state.freeForAll = restricted end,
        function() UnitIsPVPFreeForAll = function() error("Free-for-all state unavailable") end end }) do
        staticTerritoryCase(function(state)
            change(state)
            equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
        end)
    end
    staticTerritoryCase(function()
        UnitIsPVPFreeForAll = nil
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Friendly]")
    end)
end)

test("unknown or restricted player faction never receives a static friendly label", function()
    for _, change in ipairs({ function(state) state.player = "Neutral" end,
        function(state) state.player = restricted end,
        function() UnitFactionGroup = nil end,
        function() UnitFactionGroup = function() error("Player faction unavailable") end end }) do
        staticTerritoryCase(function(state)
            change(state)
            equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Unknown]")
            equal(state.lookups, 0)
        end)
    end
end)

test("ownership fallback keeps display choices separate and stores no data in saved settings", function()
    staticTerritoryCase(function(state)
        local _, first = render({ showCoordinates = false, colorStatus = false })
        local _, second = render({ name = "subzone", showCoordinates = false, showStatus = false })
        for _ = 1, 10 do provider.update(first); provider.update(second) end
        equal(first.text, "The Barrens [Friendly]")
        equal(second.text, "The Crossroads")
        local allowed = { name = true, showCoordinates = true, decimals = true, showStatus = true, colorStatus = true }
        for key in pairs(first.settings) do assert(allowed[key], "Do not persist client data or derived territory state") end
        equal(state.writes, 0)
    end)
end)

test("left-click toggles the native map without selecting an area or changing location settings", function()
    local previousOpen, previousToggle, previousMapRead = OpenWorldMap, ToggleWorldMap, C_Map.GetBestMapForUnit
    local calls, visible = 0, false
    OpenWorldMap = function() error("Location must use the native toggle rather than the open-only action") end
    ToggleWorldMap = function(...)
        equal(select("#", ...), 0)
        calls, visible = calls + 1, not visible
    end
    C_Map.GetBestMapForUnit = function() error("Toggling the native map must not query an area to select") end
    local settings = { name = "zone", showCoordinates = false, decimals = 2 }
    local widget = { settings = settings, text = "Elwynn Forest" }
    equal(provider.clickHint, "Toggle map")
    equal(provider.click(widget), true); equal(visible, true)
    equal(provider.click(widget), true); equal(visible, false)
    equal(provider.click(widget), true); equal(visible, true); equal(calls, 3)
    equal(widget.text, "Elwynn Forest"); equal(widget.settings, settings)
    equal(widget.settings.name, "zone"); equal(widget.settings.showCoordinates, false); equal(widget.settings.decimals, 2)
    local keys = 0; for _ in pairs(widget.settings) do keys = keys + 1 end; equal(keys, 3)
    OpenWorldMap, ToggleWorldMap, C_Map.GetBestMapForUnit = previousOpen, previousToggle, previousMapRead
end)

test("missing map actions preserve the location and expose a recoverable tooltip note", function()
    local previous, previousOpen = ToggleWorldMap, OpenWorldMap
    OpenWorldMap = function() error("A missing toggle must not silently become an open-only action") end
    local widget = { settings = {}, text = "Elwynn Forest" }
    for _, missing in ipairs({ false, "unsupported", restricted }) do
        ToggleWorldMap = missing
        equal(provider.click(widget), false)
        equal(widget.text, "Elwynn Forest")
        assert(table.concat(tipFor(widget).lines, "\n"):find("World map is unavailable.", 1, true))
    end
    ToggleWorldMap = nil; equal(provider.click(widget), false)
    ToggleWorldMap = function() end
    equal(provider.click(widget), true); equal(widget.locationMessage, nil)
    assert(not table.concat(tipFor(widget).lines, "\n"):find("World map is unavailable.", 1, true))
    ToggleWorldMap, OpenWorldMap = previous, previousOpen
end)

test("unexpected native map failures remain observable without rewriting location preferences", function()
    local previous = ToggleWorldMap
    ToggleWorldMap = function() error("native map action failed", 0) end
    local widget = { settings = { showCoordinates = false }, text = "Elwynn Forest" }
    local ok, reason = pcall(provider.click, widget)
    equal(ok, false); assert(tostring(reason):find("native map action failed", 1, true))
    equal(widget.settings.showCoordinates, false); equal(widget.text, "Elwynn Forest")
    ToggleWorldMap = previous
end)

-- Client-observed cave contract: BestMap is the continent, while the native
-- spatial query returns the containing zone. The player-facing cave name stays.
local function continentTerritoryCase(callback)
    staticTerritoryCase(function(state)
        zone, subzone = "The Wailing Caverns", "Wailing Caverns"
        state.mapID, state.x, state.y = 1414, 0.521, 0.550
        state.origin = { mapID = 1414, mapType = 2, name = "Kalimdor", parentMapID = 947 }
        state.resolved = { mapID = 1413, mapType = 3, name = "The Barrens", parentMapID = 1414 }
        state.canonical = { mapID = 1413, mapType = 3, name = "The Barrens", parentMapID = 1414 }
        state.spatialReads, state.positionReads = 0, 0
        C_Map.GetMapInfo = function(id)
            if id == 1414 then return state.origin end
            if id == 1413 then return state.canonical end
        end
        C_Map.GetPlayerMapPosition = function(id, unit)
            equal(id, state.mapID); equal(unit, "player")
            state.positionReads = state.positionReads + 1
            return { GetXY = function() return state.x, state.y end }
        end
        C_Map.GetMapInfoAtPosition = function(id, pointX, pointY, ...)
            equal(id, 1414); equal(pointX, state.x); equal(pointY, state.y)
            equal(select("#", ...), 0) -- Keep the native default zone-position policy.
            state.spatialReads = state.spatialReads + 1
            return state.resolved
        end
        callback(state)
    end)
end

test("a client-resolved continent position classifies the Wailing Caverns without renaming it", function()
    continentTerritoryCase(function(state)
        local shown, widget = render({ colorStatus = false })
        equal(shown, "The Wailing Caverns (52.1, 55.0) [Friendly]")
        local tip = tipFor(widget)
        equal(tip.rows.Zone, "The Wailing Caverns"); equal(tip.rows.Subzone, "Wailing Caverns")
        equal(tip.rows.Coordinates, "52.1, 55.0")
        equal(tip.rows.Territory, "Friendly"); equal(tip.rows["Territory faction"], "Horde")
        equal(MenubarLocationDiagnostics().source, "clientData")
        state.player, state.localizedPlayer = "Alliance", "Alliance"
        equal(render({ showCoordinates = false, colorStatus = false }), "The Wailing Caverns [Enemy]")
        assert(state.spatialReads >= 2)
        equal(state.metadataReads, 0); equal(state.writes, 0)
    end)
end)

test("spatial ownership rejects unavailable or invalid player coordinates before resolving a zone", function()
    local cases = {
        function() C_Map.GetPlayerMapPosition = nil end,
        function() C_Map.GetPlayerMapPosition = function() error("position unavailable") end end,
        function() C_Map.GetPlayerMapPosition = function() return restricted end end,
        function() C_Map.GetPlayerMapPosition = function() return {} end end,
        function() C_Map.GetPlayerMapPosition = function() return { GetXY = function() error("vector unavailable") end } end end,
        function(state) state.x = restricted end,
        function(state) state.y = restricted end,
        function(state) state.x = -0.01 end,
        function(state) state.y = 1.01 end,
        function(state) state.x = 0 / 0 end,
        function(state) state.y = math.huge end,
    }
    for _, change in ipairs(cases) do
        continentTerritoryCase(function(state)
            change(state)
            equal(render({ showCoordinates = false, colorStatus = false }), "The Wailing Caverns [Unknown]")
            equal(state.spatialReads, 0)
        end)
    end
end)

test("spatial ownership requires a genuine continent and a verified child zone in that continent", function()
    local cases = {
        function(state) state.origin.mapID = 1415 end,
        function(state) state.origin.mapID = restricted end,
        function(state) state.origin.mapType = 0 end,
        function(state) state.origin.mapType = 3 end,
        function(state) state.origin.mapType = restricted end,
        function() C_Map.GetMapInfoAtPosition = nil end,
        function() C_Map.GetMapInfoAtPosition = function() error("spatial query unavailable") end end,
        function() C_Map.GetMapInfoAtPosition = function() return restricted end end,
        function() C_Map.GetMapInfoAtPosition = function() return {} end end,
        function(state) state.resolved.mapID = 9999 end,
        function(state) state.resolved.mapID = restricted end,
        function(state) state.resolved.mapType = 2 end,
        function(state) state.resolved.mapType = 4 end,
        function(state) state.resolved.mapType = restricted end,
        function(state) state.resolved.parentMapID = 1415 end,
        function(state) state.resolved.parentMapID = restricted end,
        function(state) state.resolved.name = restricted end,
        function(state) state.resolved.name = "Another zone" end,
        function(state) state.canonical = nil end,
        function(state) state.canonical.mapID = 1412 end,
        function(state) state.canonical.mapID = restricted end,
        function(state) state.canonical.mapType = 4 end,
        function(state) state.canonical.mapType = restricted end,
        function(state) state.canonical.parentMapID = 1415 end,
        function(state) state.canonical.parentMapID = restricted end,
        function(state) state.canonical.name = "Another zone" end,
        function(state) state.canonical.name = restricted end,
        function(state) state.areaName = "Another area" end,
        function(state) state.areaName = restricted end,
    }
    for _, change in ipairs(cases) do
        continentTerritoryCase(function(state)
            change(state)
            local shown, widget = render({ showCoordinates = false, colorStatus = false })
            equal(shown, "The Wailing Caverns [Unknown]")
            equal(tipFor(widget).rows.Territory, nil)
        end)
    end
end)

test("native instance and live PvP restrictions precede the spatial ownership fallback", function()
    local cases = {
        { change = function(state) state.inInstance = true end, label = "Dungeon" },
        { change = function(state) state.inInstance = restricted end, label = "Unknown" },
        { change = function(state) state.freeForAll = true end, label = "Unknown" },
        { change = function(state) state.freeForAll = restricted end, label = "Unknown" },
        { change = function() C_PvP.GetZonePVPInfo = function() return "sanctuary" end end, label = "Sanctuary" },
        { change = function() C_PvP.GetZonePVPInfo = function() return "future-category" end end, label = "Unknown" },
        { change = function() C_PvP.GetZonePVPInfo = function() return restricted end end, label = "Unknown" },
        { change = function() C_PvP.GetZonePVPInfo = function() return nil, true end end, label = "Unknown" },
        { change = function() C_PvP.GetZonePVPInfo = function() return nil, restricted end end, label = "Unknown" },
        { change = function() C_PvP.GetZonePVPInfo = function() return nil, false, restricted end end, label = "Unknown" },
    }
    for _, sample in ipairs(cases) do
        continentTerritoryCase(function(state)
            sample.change(state)
            equal(render({ showCoordinates = false, colorStatus = false }), "The Wailing Caverns [" .. sample.label .. "]")
            equal(state.spatialReads, 0)
        end)
    end
end)

test("verified direct zone maps never use the spatial API or bypass their exact zone-name check", function()
    staticTerritoryCase(function()
        local queries = 0
        C_Map.GetMapInfoAtPosition = function() queries = queries + 1; error("direct zone must not use spatial lookup") end
        C_Map.GetPlayerMapPosition = function() error("ownership of a direct zone needs no coordinate read") end
        equal(render({ showCoordinates = false, colorStatus = false }), "The Barrens [Friendly]")
        zone = "The Wailing Caverns"
        equal(render({ showCoordinates = false, colorStatus = false }), "The Wailing Caverns [Unknown]")
        equal(queries, 0)
    end)
end)

test("continent ownership follows current native results on each poll without sticky territory state", function()
    continentTerritoryCase(function(state)
        local _, widget = render({ showCoordinates = false, colorStatus = false })
        equal(widget.text, "The Wailing Caverns [Friendly]")
        local start = state.spatialReads
        state.resolved.mapID = 9999; provider.update(widget)
        equal(widget.text, "The Wailing Caverns [Unknown]")
        state.resolved.mapID = 1413; provider.update(widget)
        equal(widget.text, "The Wailing Caverns [Friendly]")
        equal(state.spatialReads, start + 2)
        state.inInstance = true; provider.update(widget)
        equal(widget.text, "The Wailing Caverns [Dungeon]")
        equal(state.spatialReads, start + 2)
        state.inInstance = false; provider.update(widget)
        equal(widget.text, "The Wailing Caverns [Friendly]")
        state.mapID, zone = 1413, "The Barrens"; provider.update(widget)
        equal(widget.text, "The Barrens [Friendly]")
        equal(state.spatialReads, start + 3)
        equal(state.writes, 0)
    end)
end)

test("crossing the Wailing Caverns portal drops outdoor data and restores it on exit", function()
    continentTerritoryCase(function(state)
        local _, widget = render({ colorStatus = false })
        equal(widget.text, "The Wailing Caverns (52.1, 55.0) [Friendly]")
        local outdoorReads = state.spatialReads
        state.inInstance = true
        zone, subzone = "Wailing Caverns", ""
        for _, oldMap in ipairs({ 1414, 1413, 947 }) do
            state.mapID = oldMap
            if oldMap == 947 then
                C_Map.GetMapInfo = function() return { mapID = 947, mapType = 1, name = "Azeroth" } end
            end
            provider.update(widget)
            equal(widget.text, "Wailing Caverns [Dungeon]")
            local rows = tipFor(widget).rows
            equal(rows.Zone, "Wailing Caverns"); equal(rows["Instance type"], "Dungeon")
            equal(rows.Coordinates, nil); equal(rows.Territory, nil); equal(rows["Territory faction"], nil)
        end
        state.mapID = nil
        provider.update(widget)
        equal(widget.text, "Wailing Caverns [Dungeon]")
        equal(tipFor(widget).rows.Coordinates, nil)
        equal(state.spatialReads, outdoorReads)

        state.inInstance, state.mapID = false, 1413
        zone, subzone = "The Barrens", "Lushwater Oasis"
        C_Map.GetMapInfo = function() return state.canonical end
        provider.update(widget)
        equal(widget.text, "The Barrens (52.1, 55.0) [Friendly]")
        local rows = tipFor(widget).rows
        equal(rows["Instance type"], nil); equal(rows["Territory faction"], "Horde")
    end)
end)

test("available dungeon coordinates and live territory take priority over fallbacks", function()
    staticTerritoryCase(function(state)
        state.inInstance = true
        zone, subzone = "Wailing Caverns", "Pit of Fangs"
        -- An illustrative dungeon floor; behavior must not depend on its ID.
        state.mapID, state.infoMapID, state.mapType, state.mapName = 67890, 67890, 4, zone
        C_PvP.GetZonePVPInfo = function() return "sanctuary" end
        local _, widget = render({ name = "both", colorStatus = false })
        equal(widget.text, "Wailing Caverns: Pit of Fangs (52.4, 29.4) [Sanctuary]")
        local rows = tipFor(widget).rows
        equal(rows["Instance type"], "Dungeon"); equal(rows.Territory, "Sanctuary")
        equal(rows.Coordinates, "52.4, 29.4")
        C_Map.GetMapInfo = nil
        equal(render({ showStatus = false }), "Wailing Caverns (52.4, 29.4)")
        widget.settings.showCoordinates, widget.settings.showStatus = false, false
        provider.update(widget)
        equal(widget.text, "Wailing Caverns: Pit of Fangs")
        C_Map.GetPlayerMapPosition = function() return { GetXY = function() return restricted, 0.2 end } end
        equal(tipFor(widget).rows.Coordinates, nil)
    end)
end)

-- Compare the best player map and the minimap's current floor independently.
-- Synthetic floor IDs avoid assuming that all clients expose the same dungeon maps.
local function dungeonMinimapCase(callback)
    staticTerritoryCase(function(state)
        zone, subzone = "Wailing Caverns", ""
        local best, floor = 67890, 67891
        state.inInstance, state.mapID = true, best
        state.minimapID, state.minimapReads, state.floorPositionReads = floor, 0, 0
        state.floorInfo = { mapID = floor, mapType = 4, name = zone }
        C_Minimap = { GetUiMapID = function()
            state.minimapReads = state.minimapReads + 1
            return state.minimapID
        end }
        C_Map.GetMapInfo = function(id)
            if id == floor then return state.floorInfo end
            return { mapID = id, mapType = 4, name = zone }
        end
        C_Map.GetPlayerMapPosition = function(id, unit)
            equal(unit, "player")
            if id == floor then
                state.floorPositionReads = state.floorPositionReads + 1
                return { GetXY = function() return 0.25, 0.75 end }
            end
            equal(id, best)
            if state.primary then return state.primary() end
        end
        callback(state, best, floor)
    end)
end

test("a public dungeon floor on the minimap fills missing player-map coordinates", function()
    dungeonMinimapCase(function(state, best)
        local _, widget = render({ colorStatus = false })
        equal(widget.text, "Wailing Caverns (25.0, 75.0) [Dungeon]")
        equal(tipFor(widget).rows.Coordinates, "25.0, 75.0")
        state.mapID = nil
        provider.update(widget)
        equal(widget.text, "Wailing Caverns (25.0, 75.0) [Dungeon]")

        state.mapID = best
        state.primary = function() return { GetXY = function() return 0.6, 0.4 end } end
        local reads = state.minimapReads
        provider.update(widget)
        equal(widget.text, "Wailing Caverns (60.0, 40.0) [Dungeon]")
        equal(state.minimapReads, reads)
        state.inInstance, state.mapID, zone = false, nil, "The Barrens"
        provider.update(widget)
        equal(widget.text, "The Barrens (--, --) [Unknown]")
        equal(state.minimapReads, reads)
    end)
end)

test("minimap fallback requires a distinct identified Dungeon map", function()
    local cases = {
        function(state, best) state.minimapID = best end,
        function(state) state.minimapID = restricted end,
        function(state) state.floorInfo = nil end,
        function(state) state.floorInfo = restricted end,
        function(state) state.floorInfo.mapID = 27 end,
        function(state) state.floorInfo.mapID = restricted end,
        function(state) state.floorInfo.mapType = 3 end,
        function(state) state.floorInfo.mapType = restricted end,
        function() C_Minimap = nil end,
        function() C_Minimap.GetUiMapID = function() error("no floor map") end end,
    }
    for _, change in ipairs(cases) do
        dungeonMinimapCase(function(state, best)
            change(state, best)
            local shown, widget = render({ colorStatus = false })
            equal(shown, "Wailing Caverns [Dungeon]")
            equal(tipFor(widget).rows.Coordinates, nil)
            equal(state.floorPositionReads, 0)
        end)
    end
end)

test("a restricted or failing primary map read never triggers the alternate coordinate lookup", function()
    local cases = {
        function(state) state.mapID = restricted end,
        function() C_Map.GetBestMapForUnit = function() error("restricted best map") end end,
        function(state) state.primary = function() return restricted end end,
        function(state) state.primary = function() error("restricted position") end end,
        function(state) state.primary = function() return { GetXY = function() return restricted, 0.2 end } end end,
        function(state) state.primary = function() return { GetXY = function() error("restricted vector") end } end end,
    }
    for _, change in ipairs(cases) do
        dungeonMinimapCase(function(state)
            change(state)
            local shown, widget = render({ colorStatus = false })
            equal(shown, "Wailing Caverns [Dungeon]")
            equal(tipFor(widget).rows.Coordinates, nil)
            equal(state.minimapReads, 0); equal(state.floorPositionReads, 0)
        end)
    end
end)

test("instance type and localized name respect public client values", function()
    staticTerritoryCase(function(state)
        state.mapID, zone, subzone = nil, restricted, ""
        GetInstanceInfo = function() return "Les cavernes des Lamentations" end
        for _, sample in ipairs({ { "raid", "Raid" }, { "future-type", "Instance" },
            { restricted, "Instance" }, { nil, "Instance" } }) do
            IsInInstance = function() return true, sample[1] end
            local shown, widget = render({ colorStatus = false })
            equal(shown, "Les cavernes des Lamentations [" .. sample[2] .. "]")
            local rows = tipFor(widget).rows
            equal(rows.Zone, "Les cavernes des Lamentations")
            equal(rows["Instance type"], sample[2]); equal(rows.Coordinates, nil)
        end
        zone = "Name from the zone API"
        IsInInstance = function() return true, "party" end
        equal(render({ colorStatus = false }), "Name from the zone API [Dungeon]")
        IsInInstance = function() return restricted, "party" end
        equal(render({ colorStatus = false }), "Name from the zone API (--, --) [Unknown]")
    end)
end)

print(string.format("%d Location tests passed", passed))
