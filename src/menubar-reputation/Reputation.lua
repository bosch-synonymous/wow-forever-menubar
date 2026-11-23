-- Original reputation provider. Never changes Blizzard's watched faction or headers.
local function public(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function numeric(value)
    if not public(value) or type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function text(value)
    if public(value) and type(value) == "string" and value ~= "" then return value end
end

local function query(namespace, name, ...)
    if type(namespace) ~= "table" or type(namespace[name]) ~= "function" then return nil, "unavailable" end
    local ok, result = pcall(namespace[name], ...)
    if not ok then return nil, "unavailable" end
    if not public(result) then return nil, "restricted" end
    return result
end

local function positiveID(value)
    value = numeric(value)
    return value and value > 0 and value == math.floor(value) and value or nil
end

local function fraction(state, standing, lower, upper)
    standing, lower, upper = numeric(standing), numeric(lower), numeric(upper)
    if not standing or not lower or not upper or upper <= lower then
        state.reason = "Progress is unavailable for this faction."
        return state
    end
    -- Public finite inputs can still produce an overflowing difference. Keep
    -- malformed ranges out of both arithmetic formatting and native gauges.
    local total, progress = numeric(upper - lower), numeric(standing - lower)
    if not total or not progress then
        state.reason = "Progress is unavailable for this faction."
        return state
    end
    state.total = total
    state.progress = math.max(0, math.min(total, progress))
    return state
end

local standingNames = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local function standingLabel(reaction)
    reaction = numeric(reaction)
    if not reaction or reaction ~= math.floor(reaction) or not standingNames[reaction] then return "Reputation" end
    return text(_G["FACTION_STANDING_LABEL" .. reaction]) or standingNames[reaction]
end

local function exposedWatchedFaction()
    local count = numeric(query(C_Reputation, "GetNumFactions"))
    if not count or count < 0 or count > 10000 then return nil end
    for index = 1, math.floor(count) do
        local data = query(C_Reputation, "GetFactionDataByIndex", index)
        if type(data) == "table" and public(data.isWatched) and data.isWatched == true
            and positiveID(data.factionID) then return data end
    end
end

local function watchedFaction()
    local data, failure = query(C_Reputation, "GetWatchedFactionData")
    -- The watched XP-bar choice is independent of the faction selected in the
    -- Reputation window. Only read it; never change either Blizzard selection.
    if failure == "restricted" then return nil, failure end
    if type(data) == "table" then
        if not public(data.factionID) then return nil, "restricted" end
        if positiveID(data.factionID) then return data end
    end
    local exposed = exposedWatchedFaction()
    if exposed then return exposed end
    return nil, failure
end

local function readState(settings)
    local selected = settings.factionID == nil and 0 or numeric(settings.factionID)
    if not selected or selected < 0 or selected ~= math.floor(selected) then
        return { reason = "Choose an exposed faction, or follow the game's watched faction." }
    end
    if type(C_Reputation) ~= "table" then return { reason = "The reputation API is unavailable." } end
    local data, failure
    if selected == 0 then
        data, failure = watchedFaction()
        if failure then return { reason = "Watched-faction data is " .. failure .. "." } end
        if type(data) ~= "table" then return { empty = true, reason = "No watched faction. Choose one in Reputation or select a faction here." } end
    else
        data = query(C_Reputation, "GetFactionDataByID", selected)
        if type(data) ~= "table" then return { reason = "The selected faction is unavailable. Choose an exposed faction or follow the watched faction." } end
    end
    if selected == 0 and numeric(data.factionID) == 0 then
        return { empty = true, reason = "No watched faction. Choose one in Reputation or select a faction here." }
    end
    local id = positiveID(data.factionID)
    local reaction = numeric(data.reaction)
    local state = { name = text(data.name) or "Reputation", factionID = id,
        reaction = reaction and reaction == math.floor(reaction) and reaction or nil }
    if not id then state.reason = "Faction data is unavailable."; return state end
    if not public(data.isHeader) or not public(data.isHeaderWithRep) then
        state.reason = "Faction data is restricted."; return state
    end
    if data.isHeader and not data.isHeaderWithRep then
        state.reason = "This entry is a category, not a reputation."; return state
    end

    local major, classificationFailure = query(C_Reputation, "IsMajorFaction", id)
    if classificationFailure == "restricted" then
        state.reason = "Faction progression data is restricted."; return state
    end
    if major == true then
        state.kind = "Renown"
        local renown = query(C_MajorFactions, "GetMajorFactionData", id)
        if type(renown) ~= "table" then state.reason = "Renown details are unavailable."; return state end
        local level, maximum = numeric(renown.renownLevel), numeric(renown.maxLevel)
        if not level then state.reason = "Renown details are unavailable."; return state end
        state.standing = "Renown " .. math.floor(level)
        if not public(renown.isUnlocked) then
            state.reason = "Renown details are restricted."; return state
        end
        if renown.isUnlocked == false then
            state.reason = "This renown faction is locked."; return state
        end
        local capped = query(C_MajorFactions, "HasMaximumRenown", id)
        if capped == true or (maximum and maximum > 0 and level >= maximum) then
            state.complete = true; return state
        end
        return fraction(state, renown.renownReputationEarned, 0, renown.renownLevelThreshold)
    end

    local friend, friendshipFailure = query(C_GossipInfo, "GetFriendshipReputation", id)
    if friendshipFailure == "restricted" or (type(friend) == "table" and not public(friend.friendshipFactionID)) then
        state.reason = "Friendship data is restricted."; return state
    end
    if type(friend) == "table" and positiveID(friend.friendshipFactionID) then
        state.kind = "Friendship"
        state.standing = text(friend.reaction) or "Friendship"
        local standing, maximum = numeric(friend.standing), numeric(friend.maxRep)
        if standing and maximum and maximum > 0 and standing >= maximum then
            state.complete = true; return state
        end
        return fraction(state, friend.standing, friend.reactionThreshold, friend.nextThreshold)
    end

    local paragon, paragonFailure = query(C_Reputation, "IsFactionParagonForCurrentPlayer", id)
    if paragonFailure == "restricted" then state.reason = "Faction progression data is restricted."; return state end
    if paragon == true then
        state.kind, state.standing = "Paragon", "Paragon"
        state.reason = "Paragon reward-cycle progress is not supported yet."
        return state
    end
    state.kind, state.standing = "Reputation", standingLabel(data.reaction)
    if numeric(data.reaction) == 8 then state.complete = true; return state end
    return fraction(state, data.currentStanding, data.currentReactionThreshold, data.nextReactionThreshold)
end

local function progressText(state, style)
    if state.complete then return "Maximum" end
    if not state.progress or not state.total then return "--" end
    local percentage = string.format("%.0f%%", state.progress / state.total * 100)
    local amount = string.format("%.0f/%.0f", state.progress, state.total)
    if style == "fraction" then return amount end
    if style == "both" then return amount .. " (" .. percentage .. ")" end
    return percentage
end

local function factionOptions()
    local options = { { value = 0, label = "Follow game's watched faction" } }
    local found, factions = {}, {}
    local count = numeric(query(C_Reputation, "GetNumFactions"))
    if count and count >= 0 and count <= 10000 then
        for index = 1, math.floor(count) do
            local data = query(C_Reputation, "GetFactionDataByIndex", index)
            if type(data) == "table" then
                local id, name = positiveID(data.factionID), text(data.name)
                if id and name and public(data.isHeader) and public(data.isHeaderWithRep)
                    and (not data.isHeader or data.isHeaderWithRep) and not found[id] then
                    factions[#factions + 1] = { value = id, label = name }
                    found[id] = true
                end
            end
        end
    end
    table.sort(factions, function(a, b)
        if a.label == b.label then return a.value < b.value end
        return a.label < b.label
    end)
    for _, option in ipairs(factions) do options[#options + 1] = option end
    return options
end

local function fillColor(state)
    local color
    if state.kind == "Renown" then color = BLUE_FONT_COLOR
    elseif type(FACTION_BAR_COLORS) == "table" then
        color = FACTION_BAR_COLORS[state.kind == "Friendship" and 5 or state.reaction]
    end
    if not public(color) or type(color) ~= "table" then return { 0.5, 0.5, 0.5, 1 } end
    local r, g, b
    if type(color.GetRGB) == "function" then
        local ok, red, green, blue = pcall(color.GetRGB, color)
        if ok then r, g, b = numeric(red), numeric(green), numeric(blue) end
    else
        local function component(name, index)
            local value = color[name]
            if not public(value) then return nil end
            if value == nil then value = color[index] end
            return numeric(value)
        end
        r, g, b = component("r", 1), component("g", 2), component("b", 3)
    end
    if not r or not g or not b or r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 then
        return { 0.5, 0.5, 0.5, 1 }
    end
    return { r, g, b, 1 }
end

local function overlayText(state, settings, gauge)
    if not state.name then return state.empty and "Reputation: no watched faction" or "Reputation: unavailable" end
    local parts = {}
    if settings.showName ~= false then parts[#parts + 1] = state.name end
    if settings.showStanding ~= false and state.standing then parts[#parts + 1] = state.standing end
    local style = settings.progress
    if not state.complete and state.progress == nil then parts[#parts + 1] = "--"
    elseif style ~= "none" then
        local value = gauge and state.complete and style ~= "fraction" and style ~= "value" and "100%"
            or progressText(state, style == "value" and "fraction" or style)
        parts[#parts + 1] = value
    end
    if settings.showName ~= false and #parts > 1 then parts[1] = parts[1] .. ":" end
    return table.concat(parts, " ")
end

local function nativeService()
    local service = Menubar.NativeStatusBars
    if not public(service) or type(service) ~= "table" or type(service.Request) ~= "function"
        or type(service.Release) ~= "function" or type(service.GetMessage) ~= "function" then return nil end
    return service
end
local function requestNative(widget)
    local service = nativeService()
    if service then service:Request("reputation", widget, widget.settings.hideBlizzardReputationBar == true) end
end
local function releaseNative(widget)
    local service = nativeService()
    if service then service:Release("reputation", widget) end
end
local function nativeMessage(widget)
    local service = nativeService()
    if service then return service:GetMessage("reputation") end
    if widget.settings.hideBlizzardReputationBar == true then return "Update Menubar to hide Blizzard's reputation bar." end
end

local function render(widget)
    local state = readState(widget.settings)
    widget.reputationState = state
    local gauge = widget.settings.presentation ~= "text"
    if gauge then
        local value, maximum = 0, 1
        if state.complete then value = 1
        elseif state.progress ~= nil and state.total ~= nil then value, maximum = state.progress, state.total end
        local width = numeric(widget.settings.gaugeWidth)
        if not width or width < 80 or width > 400 then width = 160 end
        widget:SetGauge(value, maximum, fillColor(state), overlayText(state, widget.settings, true), width)
    else
        widget:HideGauge()
        widget:SetText(overlayText(state, widget.settings, false))
    end
    requestNative(widget)
end

local function update(widget)
    local ok, reason = pcall(render, widget)
    if not ok then
        pcall(releaseNative, widget)
        error(reason, 0)
    end
end

local function click(widget)
    local open = widget.OpenChoiceMenu
    if not public(open) or type(open) ~= "function" then return false end
    return open(widget, "factionID", "Watch reputation")
end

local function tooltip(widget, tip)
    local state = readState(widget.settings)
    tip:AddLine(state.name or "Reputation")
    tip:AddLine("Good names are earned.", 1, 1, 1)
    if state.standing then tip:AddDoubleLine("Standing", state.standing) end
    if state.kind and state.kind ~= "Reputation" and state.kind ~= "Renown" and state.kind ~= state.standing then
        tip:AddDoubleLine("Progression", state.kind)
    end
    if state.complete then tip:AddLine("Maximum standing reached.")
    elseif state.progress and state.total then
        tip:AddDoubleLine("Progress", progressText(state, "both"))
        tip:AddDoubleLine("Remaining", string.format("%.0f", state.total - state.progress))
    end
    if state.reason then tip:AddLine(state.reason, 0.65, 0.65, 0.65, true) end
    local note = nativeMessage(widget)
    if note then tip:AddLine(note, 0.65, 0.65, 0.65, true) end
end

Menubar:RegisterWidgetType({
    id = "reputation", name = "Reputation", clickHint = "Choose faction",
    retainOnDisable = true,
    defaults = { factionID = 0, presentation = "gauge", gaugeWidth = 160, gaugeStyle = "theme",
        showName = true, showStanding = false, progress = "none", hideBlizzardReputationBar = true},
    legacyDefaults = { gaugeStyle = "square", progress = "percent", showStanding = true, hideBlizzardReputationBar = false },
    defaultPlacement = { bar = "top", alignment = "left", order = 2, sidebarOrder = 9 },
    interval = 2,
    events = { "FACTION_STANDING_CHANGED", "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "MAJOR_FACTION_UNLOCKED" },
    settings = {
        { key = "factionID", label = "Faction", type = "select", options = factionOptions },
        { key = "presentation", label = "Reputation display", type = "select", options = {
            { value = "gauge", label = "Gauge" }, { value = "text", label = "Text" },
        } },
        { key = "gaugeWidth", label = "Gauge width", type = "number", min = 80, max = 400, integer = true },
        { key = "gaugeStyle", label = "Gauge style", type = "select", options = {
            { value = "theme", label = "Theme default" },
            { value = "square", label = "Square" }, { value = "warcraft", label = "Warcraft" },
        } },
        { key = "hideBlizzardReputationBar", label = "Hide Blizzard reputation bar", type = "toggle" },
        { key = "showName", label = "Show faction name", type = "toggle" },
        { key = "showStanding", label = "Show reputation level", type = "toggle" },
        { key = "progress", label = "Progress value", type = "select", options = {
            { value = "none", label = "Hidden" },
            { value = "percent", label = "Percentage" },
            { value = "fraction", label = "Current / required" },
            { value = "both", label = "Value and percentage" },
        } },
    },
    update = update,
    click = click,
    tooltip = tooltip,
    reset = releaseNative,
    deactivate = releaseNative,
    destroy = releaseNative,
})
