-- Original Location provider. Map selection is read without modifying the world map.
local function readable(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function call(method, ...)
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, ...)
    if ok and readable(value) then return value end
end

local function textFrom(method)
    local value = call(method)
    if type(value) == "string" and value ~= "" then return value end
end

local function positiveID(value)
    return readable(value) and type(value) == "number" and value > 0 and value < math.huge
        and value == math.floor(value)
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

local function clientOwnership()
    local data = _G.MenubarLocationTerritories
    if type(data) ~= "table" then return nil, "data-unavailable" end
    if type(C_Map) ~= "table" then return nil, "map-api-unavailable" end
    local inInstance = call(IsInInstance)
    if inInstance ~= false then return nil, inInstance == true and "instance" or "instance-unavailable" end
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
    if not entry then return nil, "unverified-map" end
    local info = call(C_Map.GetMapInfo, mapID)
    if type(info) ~= "table" or not readable(info.mapID) or info.mapID ~= mapID
        or not readable(info.mapType) or info.mapType ~= 3 or not readable(info.name)
        or type(info.name) ~= "string" then return nil, "map-identity" end
    local name = call(C_Map.GetAreaInfo, entry.areaID)
    -- Confirm the exact current area in the client's language; do not apply stale map data.
    if type(name) ~= "string" or name == "" or info.name ~= name then return nil, "area-name" end
    if textFrom(GetRealZoneText) ~= name then return nil, "zone-name" end
    if entry.owner == "Horde" or entry.owner == "Alliance" then return entry.owner end
    return nil, "unverified-owner"
end

local function territory()
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
            local owner, reason = clientOwnership()
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
_G.MenubarLocationDiagnostics = territory

local function normalized(value)
    return readable(value) and type(value) == "number" and value >= 0 and value <= 1
end

local function coordinates()
    if not C_Map then return nil end
    local mapID = call(C_Map.GetBestMapForUnit, "player")
    if not positiveID(mapID) then return nil end
    local position = call(C_Map.GetPlayerMapPosition, mapID, "player")
    if not position then return nil end
    local ok, x, y = pcall(function() return position:GetXY() end)
    if ok and normalized(x) and normalized(y) then return { x = x * 100, y = y * 100 } end
end

local function formatCoordinates(point, settings)
    if not point then return "--, --" end
    local decimals = settings.decimals
    if decimals ~= 0 and decimals ~= 2 then decimals = 1 end
    local format = "%0." .. decimals .. "f, %0." .. decimals .. "f"
    return string.format(format, point.x, point.y)
end

local function zoneName(zone, subzone, choice)
    if choice == "subzone" then return subzone or zone or "Unknown zone" end
    if choice == "both" and zone and subzone and zone ~= subzone then return zone .. ": " .. subzone end
    return zone or subzone or "Unknown zone"
end

local function update(widget)
    local settings = widget.settings
    local zone, subzone = textFrom(GetRealZoneText), textFrom(GetSubZoneText)
    local text = zoneName(zone, subzone, settings.name)
    if settings.showCoordinates then text = text .. " (" .. formatCoordinates(coordinates(), settings) .. ")" end
    if settings.showStatus then
        local state = territory().state
        local status = state.label
        if settings.colorStatus then status = "|cff" .. state.color .. status .. "|r" end
        text = text .. " [" .. status .. "]"
    end
    widget:SetText(text)
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
    local zone, subzone = textFrom(GetRealZoneText), textFrom(GetSubZoneText)
    local point, status = coordinates(), territory()
    tip:AddLine("Location")
    tip:AddLine("Find your bearings.", 1, 1, 1)
    tip:AddDoubleLine("Zone", zone or "Unavailable")
    if subzone and subzone ~= zone then tip:AddDoubleLine("Subzone", subzone) end
    tip:AddDoubleLine("Coordinates", point and formatCoordinates(point, widget.settings) or "Unavailable")
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
