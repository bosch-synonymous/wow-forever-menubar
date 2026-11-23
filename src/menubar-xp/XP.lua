-- Original XP provider. Restricted values are never compared or used in arithmetic.
local function readable(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function call(method, ...)
    if type(method) ~= "function" then return nil, false end
    local ok, value = pcall(method, ...)
    if not ok or not readable(value) then return nil, false end
    return value, true
end

local function nonnegativeInteger(value)
    return readable(value) and type(value) == "number" and value >= 0
        and value < math.huge and value == math.floor(value)
end

local restAtlases = {
    [1] = "UI-HUD-ExperienceBar-Fill-Rested",
    [2] = "UI-HUD-ExperienceBar-Fill-Experience",
}
-- Fallbacks for a client without these atlases/constants. Forever's native
-- atlases carry the standard XP colours and are the preferred presentation.
local fallbackColors = {
    [1] = { 0, 0.39, 0.88, 1 },
    [2] = { 0.58, 0, 0.55, 1 },
}
-- Native prediction art supplies the square gauge's light blue when available;
-- this original fallback also tints the rounded Warcraft gauge's white fill.
local restedBonusColor = { 0.35, 0.65, 1, 1 }

local function restColor(state)
    local fallback = fallbackColors[state] or { 0.5, 0.5, 0.5, 1 }
    local source = type(EXHAUSTION_COLORS) == "table" and EXHAUSTION_COLORS[state]
    if type(source) ~= "table" then return fallback end
    local result = {}
    for index, key in ipairs({ "r", "g", "b" }) do
        local value = source[key]
        if not readable(value) or type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
            return fallback
        end
        result[index] = value
    end
    result[4] = 1
    return result
end

local function snapshot()
    local level = call(UnitLevel, "player")
    local current = call(UnitXP, "player")
    local maximum = call(UnitXPMax, "player")
    local result = {}
    if nonnegativeInteger(level) and level > 0 then result.level = level end
    if nonnegativeInteger(current) and nonnegativeInteger(maximum) and current <= maximum then
        result.current, result.maximum = current, maximum
    end
    local rested, restedAvailable = call(GetXPExhaustion)
    if restedAvailable and rested == nil then rested = 0 end
    if restedAvailable and nonnegativeInteger(rested) then result.rested = rested end
    local resting, restingAvailable = call(IsResting)
    if restingAvailable and type(resting) == "boolean" then result.resting = resting end
    local restState = call(GetRestState)
    if readable(restState) and type(restState) == "number" and (restState == 1 or restState == 2) then
        result.restState = restState
    elseif type(GetRestState) ~= "function" and result.rested ~= nil then
        -- A public positive bonus pool identifies rested XP even away from an inn.
        -- Never substitute inn/location status or infer from a restricted API read.
        result.restState = result.rested > 0 and 1 or 2
    end
    return result
end

local function whole(value)
    return string.format("%.0f", value)
end

local function progress(data, display)
    if display == "none" then return nil end
    if data.current == nil then return "--" end
    if data.maximum == 0 then return nil end
    if display == "fraction" then
        return whole(data.current) .. "/" .. whole(data.maximum)
    elseif display == "remaining" then
        return whole(data.maximum - data.current) .. " to go"
    end
    return string.format("%.1f%%", data.current / data.maximum * 100)
end

local function nativeService()
    local service = Menubar.NativeStatusBars
    if not readable(service) or type(service) ~= "table" or type(service.Request) ~= "function"
        or type(service.Release) ~= "function" or type(service.GetMessage) ~= "function" then return nil end
    return service
end
local function requestNative(widget)
    local service = nativeService()
    if service then service:Request("experience", widget, widget.settings.hideBlizzardXPBar == true) end
end
local function releaseNative(widget)
    local service = nativeService()
    if service then service:Release("experience", widget) end
end
local function nativeMessage(widget)
    local service = nativeService()
    if service then return service:GetMessage("experience") end
    if widget.settings.hideBlizzardXPBar == true then return "Update Menubar to hide Blizzard's experience bar." end
end

local function render(widget)
    local data = snapshot()
    local pieces = {}
    if widget.settings.showLabel then pieces[#pieces + 1] = "XP" end
    if widget.settings.showLevel then
        pieces[#pieces + 1] = data.level and "Lv " .. whole(data.level) or "Lv --"
    end
    local value = progress(data, widget.settings.display)
    if value then pieces[#pieces + 1] = value end
    local gauge = widget.settings.presentation ~= "text"
    if #pieces == 0 and not gauge then
        pieces[#pieces + 1] = data.level and "Lv " .. whole(data.level) or "--"
    end
    if gauge and data.current == nil and widget.settings.display == "none" then pieces[#pieces + 1] = "--" end
    local label = table.concat(pieces, " ")
    if gauge then
        local width = widget.settings.gaugeWidth
        if not nonnegativeInteger(width) or width < 80 or width > 400 then width = 160 end
        local value, maximum = 0, 1
        if data.current ~= nil and data.maximum > 0 then value, maximum = data.current, data.maximum end
        local bonus
        if data.current ~= nil and data.current < data.maximum and data.rested ~= nil and data.rested > 0 then
            bonus = widget.xpRestedBonus
            if not bonus then
                bonus = { color = restedBonusColor, atlas = "UI-HUD-ExperienceBar-Fill-Prediction" }
                widget.xpRestedBonus = bonus
            end
            bonus.value = data.rested
        end
        widget:SetGauge(value, maximum, restColor(data.restState), label, width, restAtlases[data.restState], bonus)
    else
        widget:HideGauge()
        widget:SetText(label)
    end
    requestNative(widget)
end

local function update(widget)
    local ok, reason = pcall(render, widget)
    if not ok then
        -- Older API-v1 hosts lack reset; never leave suppression owned by a
        -- widget whose render failed. Keep the original rendering diagnostic.
        pcall(releaseNative, widget)
        error(reason, 0)
    end
end

local function tooltip(widget, tip)
    local data = snapshot()
    tip:AddLine("Experience")
    tip:AddLine("Every side-quest counts!", 1, 1, 1)
    tip:AddDoubleLine("Level", data.level and whole(data.level) or "Unavailable")
    if data.current == nil then
        tip:AddLine("Experience is unavailable.", 0.65, 0.65, 0.65, true)
    elseif data.maximum == 0 then
        tip:AddLine("No next-level progress reported.", 0.65, 0.65, 0.65, true)
    else
        tip:AddDoubleLine("Progress", whole(data.current) .. " / " .. whole(data.maximum) .. " (" .. progress(data, "percent") .. ")")
        tip:AddDoubleLine("To next level", whole(data.maximum - data.current))
    end
    tip:AddDoubleLine("Rested bonus XP", data.rested ~= nil and whole(data.rested) or "Unavailable")
    local state = data.restState == 1 and "Rested" or (data.restState == 2 and "Normal" or "Unavailable")
    local resting = data.resting == true and "resting" or (data.resting == false and "not resting" or "resting unknown")
    tip:AddDoubleLine("Rest status", state .. " / " .. resting)
    local note = nativeMessage(widget)
    if note then tip:AddLine(note, 0.65, 0.65, 0.65, true) end
end

Menubar:RegisterWidgetType({
    id = "xp",
    retainOnDisable = true,
    name = "XP",
    defaults = { presentation = "gauge", gaugeWidth = 160, gaugeStyle = "theme",
        display = "none", showLevel = true, showLabel = false, hideBlizzardXPBar = true},
    legacyDefaults = { display = "percent", gaugeStyle = "square", hideBlizzardXPBar = false },
    settings = {
        { key = "presentation", label = "Presentation", type = "select", options = {
            { value = "gauge", label = "Fillable gauge" }, { value = "text", label = "Text" },
        } },
        { key = "gaugeWidth", label = "Gauge width", type = "number", min = 80, max = 400, integer = true },
        { key = "gaugeStyle", label = "Gauge style", type = "select", options = {
            { value = "theme", label = "Theme default" },
            { value = "square", label = "Square" }, { value = "warcraft", label = "Warcraft" },
        } },
        {
            key = "display", label = "Experience display", type = "select",
            options = {
                { value = "none", label = "No numeric value" },
                { value = "percent", label = "Percentage" },
                { value = "fraction", label = "Current / required XP" },
                { value = "remaining", label = "XP remaining" },
            },
        },
        { key = "showLevel", label = "Show character level", type = "toggle" },
        { key = "showLabel", label = "Show XP label", type = "toggle" },
        { key = "hideBlizzardXPBar", label = "Hide Blizzard experience bar", type = "toggle" },
    },
    interval = 5,
    events = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD" },
    defaultPlacement = { bar = "top", alignment = "left", order = 3, sidebarOrder = 12 },
    update = update,
    tooltip = tooltip,
    reset = releaseNative,
    deactivate = releaseNative,
    destroy = releaseNative,
})
