-- Original Location provider. Map selection is read without modifying the world map.
local function readable(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function call(method, ...)
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, ...)
    if ok and readable(value) then return value end
    return nil, true -- A failed or restricted read must not trigger another position lookup.
end

local function textFrom(method)
    local value = call(method)
    if type(value) == "string" and value ~= "" then return value end
end

local instanceLabels = {
    party = "Dungeon", raid = "Raid", scenario = "Scenario", pvp = "Battleground", arena = "Arena",
}

-- False is a confirmed outdoor location. A missing or restricted answer
-- cannot authorize the outdoor ownership lookup or an instance label.
local function currentInstance()
    if type(IsInInstance) ~= "function" then return nil end
    local ok, inside, kind = pcall(IsInInstance)
    if not ok or not readable(inside) or type(inside) ~= "boolean" then return nil end
    if not inside then return false end
    return readable(kind) and type(kind) == "string" and instanceLabels[kind] or "Instance"
end

local function currentZone(instance)
    local zone = textFrom(GetRealZoneText)
    if not zone and instance then zone = textFrom(GetInstanceInfo) end
    return zone
end

local function positiveID(value)
    return readable(value) and type(value) == "number" and value > 0 and value < math.huge
        and value == math.floor(value)
end

local function normalized(value)
    return readable(value) and type(value) == "number" and value >= 0 and value <= 1
end

local function playerPosition(mapID)
    local position, blocked = call(C_Map.GetPlayerMapPosition, mapID, "player")
    if position == nil then return nil, nil, blocked end
    local ok, x, y = pcall(function() return position:GetXY() end)
    if ok and normalized(x) and normalized(y) then return x, y end
    return nil, nil, true
end

local territories = {
    sanctuary = { label = "Sanctuary", color = "26748D" },
    friendly = { label = "Friendly", color = "287A36" },
    hostile = { label = "Enemy", color = "B02020" },
    contested = { label = "Contested", color = "806000" },
    combat = { label = "Combat zone", color = "A04D00" },
    arena = { label = "Free-for-all", color = "A02080" },
}
local unknownTerritory = { label = "Unknown", color = "606060" }

-- Custom images and the world behind transparent bars have no fixed colour.
-- For those, follow the player's chosen foreground as a contrast cue.
local function friendlyColor()
    local profile = Menubar.GetProfile and Menubar:GetProfile()
    if profile then
        local texture = profile.texture
        local background = profile.background
        local knownSurface = texture == "solid" or texture == "dither" or texture == "theme"
        if knownSurface and background and profile.opacity * background[4] > 0.2 then
            if texture == "theme" and MenubarSkins and MenubarSkins.IsWarcraft(profile.theme) then
                return "8BE99A" -- Warcraft artwork is dark; its profile swatch is a tint.
            end
            if 0.2126 * background[1] + 0.7152 * background[2] + 0.0722 * background[3] < 0.5 then
                return "8BE99A"
            end
        else
            local ink = profile.textColor
            if 0.2126 * ink[1] + 0.7152 * ink[2] + 0.0722 * ink[3] >= 0.5 then return "8BE99A" end
        end
    end
    return territories.friendly.color
end

local function readTerritory(method)
    if type(method) ~= "function" then return nil, "unavailable" end
    local result = { state = unknownTerritory }
    local ok, kind, subzonePvP, faction = pcall(method)
    if not ok then return nil, "unavailable" end
    if not readable(subzonePvP) then result.subzonePvPRestricted = true
    elseif type(subzonePvP) == "boolean" then result.subzonePvP = subzonePvP end
    if not readable(faction) then result.factionRestricted = true
    elseif type(faction) == "string" and faction ~= "" then result.faction = faction end
    if not readable(kind) then return result, "restricted" end
    if kind == nil or kind == "" then return result, "missing" end
    if type(kind) == "string" and territories[kind] then
        result.state = territories[kind]
        return result, "known"
    end
    return result, "unknown"
end

local function factionToken(value)
    if not readable(value) or type(value) ~= "string" then return nil end
    for _, token in ipairs({ "Horde", "Alliance" }) do
        local localized = _G["FACTION_" .. string.upper(token)]
        if value == token or (readable(localized) and type(localized) == "string" and value == localized) then
            return token
        end
    end
end

local function playerFaction()
    if type(UnitFactionGroup) ~= "function" then return nil end
    local ok, token, localized = pcall(UnitFactionGroup, "player")
    if ok and readable(token) and (token == "Horde" or token == "Alliance") then
        return token, readable(localized) and type(localized) == "string" and localized or nil
    end
end

local function mapMatches(info, mapID, mapType)
    return type(info) == "table" and readable(info.mapID) and info.mapID == mapID
        and readable(info.mapType) and info.mapType == mapType
        and readable(info.name) and type(info.name) == "string"
end

local function zoneAtPosition(continentID, data)
    if type(C_Map.GetMapInfoAtPosition) ~= "function" then return nil end
    local x, y = playerPosition(continentID)
    if x == nil then return nil end
    local info = call(C_Map.GetMapInfoAtPosition, continentID, x, y)
    if type(info) ~= "table" or not positiveID(info.mapID) or not mapMatches(info, info.mapID, 3)
        or not readable(info.parentMapID) or info.parentMapID ~= continentID
        or not data.maps[info.mapID] then return nil end
    local canonical = call(C_Map.GetMapInfo, info.mapID)
    if not mapMatches(canonical, info.mapID, 3) or canonical.name ~= info.name
        or not readable(canonical.parentMapID) or canonical.parentMapID ~= continentID then return nil end
    return canonical
end

local function clientOwnership(instance)
    local data = _G.MenubarLocationTerritories
    if type(data) ~= "table" then return nil, "data-unavailable" end
    if type(C_Map) ~= "table" then return nil, "map-api-unavailable" end
    if instance ~= false then return nil, instance and "instance" or "instance-unavailable" end
    if type(UnitIsPVPFreeForAll) == "function" then
        local ok, freeForAll = pcall(UnitIsPVPFreeForAll, "player")
        if not ok or not readable(freeForAll) then return nil, "free-for-all-unavailable" end
        if freeForAll == true or freeForAll == 1 then return nil, "free-for-all" end
        if freeForAll ~= nil and freeForAll ~= false then return nil, "free-for-all-unavailable" end
    end
    -- WoW owns declared-client loading policy. Validate the APIs and area identities used here.
    local mapID = call(C_Map.GetBestMapForUnit, "player")
    if not positiveID(mapID) then return nil, "map-unavailable" end
    local entry = data.maps[mapID]
    local info = call(C_Map.GetMapInfo, mapID)
    local spatial = false
    if not entry then
        if not mapMatches(info, mapID, 2) then return nil, "unverified-map" end
        -- Some outdoor caves report only a continent. Ask the client which
        -- verified surrounding zone contains the player's current position.
        info = zoneAtPosition(mapID, data)
        if not info then return nil, "spatial-map-unavailable" end
        mapID, spatial = info.mapID, true
        entry = data.maps[mapID]
    end
    if not mapMatches(info, mapID, 3) then return nil, "map-identity" end
    local name = call(C_Map.GetAreaInfo, entry.areaID)
    -- Direct maps need the exact current zone name. A spatially resolved zone
    -- can instead surround a differently named cave, with its identity checked above.
    if type(name) ~= "string" or name == "" or info.name ~= name then return nil, "area-name" end
    if not spatial and textFrom(GetRealZoneText) ~= name then return nil, "zone-name" end
    if entry.owner == "Horde" or entry.owner == "Alliance" then return entry.owner end
    return nil, "unverified-owner"
end

local function territory(instance)
    local modern = type(C_PvP) == "table" and C_PvP.GetZonePVPInfo or nil
    local result, status = readTerritory(modern)
    if status == "known" or status == "unknown" or status == "restricted" then return result end
    -- Some clients expose useful zone information only through the legacy entry point.
    -- Never replace an explicit or restricted classification with another source.
    if type(GetZonePVPInfo) == "function" and GetZonePVPInfo ~= modern then
        local fallback, fallbackStatus = readTerritory(GetZonePVPInfo)
        if fallbackStatus == "known" or fallbackStatus == "unknown" or fallbackStatus == "restricted" then
            return fallback
        end
        if not result then result = fallback
        elseif fallback then
            if not result.faction then result.faction = fallback.faction end
            if result.subzonePvP == nil or fallback.subzonePvP == true then result.subzonePvP = fallback.subzonePvP end
            result.subzonePvPRestricted = result.subzonePvPRestricted or fallback.subzonePvPRestricted
            result.factionRestricted = result.factionRestricted or fallback.factionRestricted
        end
    end
    result = result or { state = unknownTerritory }
    if result.faction and result.subzonePvP ~= true and not result.subzonePvPRestricted then
        local player, localizedPlayer = playerFaction()
        if player then
            local owner = factionToken(result.faction)
            if not owner and localizedPlayer and localizedPlayer ~= "" and result.faction == localizedPlayer then owner = player end
            if owner then result.state = owner == player and territories.friendly or territories.hostile end
        end
    end
    if not result.faction and not result.factionRestricted and result.subzonePvP ~= true and not result.subzonePvPRestricted then
        local player = playerFaction()
        if player then
            local owner, reason = clientOwnership(instance)
            result.fallbackReason = reason
            if owner then
                result.state = owner == player and territories.friendly or territories.hostile
                local localized = _G["FACTION_" .. string.upper(owner)]
                result.faction = readable(localized) and type(localized) == "string" and localized ~= "" and localized or owner
                result.source = "clientData"
            end
        else
            result.fallbackReason = "player-faction-unavailable"
        end
    end
    return result
end

-- Read-only support snapshot. Diagnostic reasons stay outside the normal widget presentation.
_G.MenubarLocationDiagnostics = function() return territory(currentInstance()) end

local function mapTypeForID(mapID)
    local info = call(C_Map.GetMapInfo, mapID)
    if type(info) == "table" and readable(info.mapID) and info.mapID == mapID and readable(info.mapType) then
        return info.mapType
    end
end

local function isExteriorMap(mapID)
    -- A portal transition can briefly leave the continent or surrounding outdoor zone as the best map.
    local kind = mapTypeForID(mapID)
    if kind == 0 or kind == 1 or kind == 2 then return true end -- Cosmic, world or continent.
    local data = _G.MenubarLocationTerritories
    return kind == 3 and type(data) == "table" and type(data.maps) == "table" and data.maps[mapID] ~= nil
end

local function coordinates(instance)
    if type(C_Map) ~= "table" or type(C_Map.GetPlayerMapPosition) ~= "function" then return nil end
    local mapID, blocked = call(C_Map.GetBestMapForUnit, "player")
    if blocked or (mapID ~= nil and not positiveID(mapID)) then return nil end
    local x, y
    if mapID and not (instance and isExteriorMap(mapID)) then
        x, y, blocked = playerPosition(mapID)
    end
    if x == nil and instance and not blocked and type(C_Minimap) == "table" then
        -- The minimap can already be on a dungeon floor while the world map has no player position.
        local floorID = call(C_Minimap.GetUiMapID)
        if positiveID(floorID) and floorID ~= mapID and mapTypeForID(floorID) == 4 then
            x, y = playerPosition(floorID)
        end
    end
    if x ~= nil then return { x = x * 100, y = y * 100 } end
end

local coordinateFormats = { [0] = "%.0f, %.0f", "%.1f, %.1f", "%.2f, %.2f" }

local function precision(settings)
    return coordinateFormats[settings.decimals] and settings.decimals or 1
end

local function formatCoordinates(point, decimals)
    if not point then return "--, --" end
    return string.format(coordinateFormats[decimals], point.x, point.y)
end

local function textWidth(label, text)
    label:SetText(text)
    return label:GetStringWidth()
end

local function widestDigits(label, before, after, format, last)
    local widest, width = "", -1
    for i = 0, last do
        local digits = string.format(format, i)
        local measured = textWidth(label, before .. digits .. after)
        if measured > width then widest, width = digits, measured end
    end
    return widest
end

local function widestCoordinate(label, before, after, decimals)
    -- The decimal point separates the two digit runs. Measure each with its
    -- neighbours to include kerning, then compare the rounded endpoint and fallback.
    local digits = widestDigits(label, before, decimals == 0 and after or ".", "%d", 99)
    if decimals > 0 then
        local fraction = widestDigits(label, ".", after, "%0" .. decimals .. "d", 10 ^ decimals - 1)
        digits = digits .. "." .. fraction
    end
    local endpoint = string.format("%." .. decimals .. "f", 100)
    local width = textWidth(label, before .. digits .. after)
    local endpointWidth = textWidth(label, before .. endpoint .. after)
    if endpointWidth > width then digits, width = endpoint, endpointWidth end
    if textWidth(label, before .. "--" .. after) > width then return "--" end
    return digits
end

local function reserveCoordinateWidth(widget, name, suffix, decimals)
    local label = widget.label
    if not label or not widget.SetWidth then return end
    local face, size, flags = label:GetFont()
    local scale = widget.frame:GetEffectiveScale()
    local cache = widget.locationSizing
    if not cache or cache.face ~= face or cache.size ~= size or cache.flags ~= flags
        or cache.scale ~= scale or cache.decimals ~= decimals then
        -- Use the rendered label itself. The update restores its display text
        -- before drawing, and movement then needs no further font measurements.
        local x = widestCoordinate(label, "(", ",", decimals)
        local y = widestCoordinate(label, " ", ")", decimals)
        cache = { face = face, size = size, flags = flags, scale = scale, decimals = decimals,
            sample = " (" .. x .. ", " .. y .. ")" }
        widget.locationSizing = cache
    end
    local shadowX = label:GetShadowOffset()
    if cache.name ~= name or cache.suffix ~= suffix or cache.shadowX ~= shadowX then
        cache.name, cache.suffix, cache.shadowX = name, suffix, shadowX
        cache.width = math.max(18, math.ceil(textWidth(label, name .. cache.sample .. suffix)) + 8)
    end
    if widget.customWidth ~= cache.width then
        label:ClearAllPoints()
        label:SetPoint("LEFT", widget.content or widget.frame, "LEFT", 4, 0)
        widget:SetWidth(cache.width)
    end
end

local function zoneName(zone, subzone, choice)
    if choice == "subzone" then return subzone or zone or "Unknown zone" end
    if choice == "both" and zone and subzone and zone ~= subzone then return zone .. ": " .. subzone end
    return zone or subzone or "Unknown zone"
end

local function update(widget)
    local settings = widget.settings
    local instance = currentInstance()
    local name = zoneName(currentZone(instance), textFrom(GetSubZoneText), settings.name)
    local suffix = ""
    if settings.showStatus then
        local state = territory(instance).state
        local status = state.label
        if instance and state == unknownTerritory then
            status = instance
        elseif settings.colorStatus then
            local color = state == territories.friendly and friendlyColor() or state.color
            status = "|cff" .. color .. status .. "|r"
        end
        suffix = " [" .. status .. "]"
    end
    if settings.showCoordinates then
        local point = coordinates(instance)
        if point or not instance then
            local decimals = precision(settings)
            reserveCoordinateWidth(widget, name, suffix, decimals)
            widget:SetText(name .. " (" .. formatCoordinates(point, decimals) .. ")" .. suffix)
            return
        end
    end
    widget.customWidth = nil
    widget:SetText(name .. suffix)
end

local function click(widget)
    widget.locationMessage = nil
    if not readable(ToggleWorldMap) or type(ToggleWorldMap) ~= "function" then
        widget.locationMessage = "World map is unavailable."
        return false
    end
    -- Let the native action own visibility, map selection and game rules.
    ToggleWorldMap()
    return true
end

local function tooltip(widget, tip)
    local instance = currentInstance()
    local zone, subzone = currentZone(instance), textFrom(GetSubZoneText)
    local point, status = coordinates(instance), territory(instance)
    tip:AddLine("Location")
    tip:AddLine("Find your bearings.", 1, 1, 1)
    tip:AddDoubleLine("Zone", zone or "Unavailable")
    if subzone and subzone ~= zone then tip:AddDoubleLine("Subzone", subzone) end
    if instance then tip:AddDoubleLine("Instance type", instance) end
    if point or not instance then
        tip:AddDoubleLine("Coordinates", point and formatCoordinates(point, precision(widget.settings)) or "Unavailable")
    end
    if status.state ~= unknownTerritory then tip:AddDoubleLine("Territory", status.state.label) end
    if status.faction then tip:AddDoubleLine("Territory faction", status.faction) end
    if status.subzonePvP == true and not status.subzonePvPRestricted then
        tip:AddDoubleLine("PvP subzone", "Yes")
    end
    if widget.locationMessage then tip:AddLine(widget.locationMessage, 0.65, 0.65, 0.65, true) end
end

Menubar:RegisterWidgetType({
    id = "location",
    retainOnDisable = true,
    name = "Location",
    clickHint = "Toggle map",
    defaults = { name = "zone", showCoordinates = true, decimals = 1, showStatus = true, colorStatus = true},
    settings = {
        {
            key = "name", label = "Location name", type = "select",
            options = {
                { value = "zone", label = "Zone" },
                { value = "subzone", label = "Subzone (zone when unavailable)" },
                { value = "both", label = "Zone and subzone" },
            },
        },
        { key = "showCoordinates", label = "Show coordinates", type = "toggle" },
        {
            key = "decimals", label = "Coordinate precision", type = "select",
            options = {
                { value = 0, label = "Whole numbers" },
                { value = 1, label = "One decimal place" },
                { value = 2, label = "Two decimal places" },
            },
        },
        { key = "showStatus", label = "Show territory classification", type = "toggle" },
        { key = "colorStatus", label = "Colour territory classification", type = "toggle" },
    },
    interval = 0.5,
    events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" },
    defaultPlacement = { bar = "top", alignment = "left", order = 1, sidebarOrder = 8 },
    update = update,
    click = click,
    tooltip = tooltip,
})
