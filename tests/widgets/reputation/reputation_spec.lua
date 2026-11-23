local definition
local secret = setmetatable({}, {
    __index = function() error("secret value was indexed") end,
    __tostring = function() error("secret value was formatted") end,
    __sub = function() error("secret value was subtracted") end,
    __add = function() error("secret value was added") end,
    __lt = function() error("secret value was compared") end,
})
issecretvalue = function(value) return rawequal(value, secret) end
Menubar = { RegisterWidgetType = function(_, provider) definition = provider end }
dofile("src/menubar-reputation/Reputation.lua")

local passed = 0
local function check(name, test)
    local ok, reason = pcall(test)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1
    print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function copy(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end
local function faction(overrides)
    local result = { factionID = 72, name = "Stormwind", reaction = 5,
        currentStanding = 4500, currentReactionThreshold = 3000, nextReactionThreshold = 9000,
        isHeader = false, isHeaderWithRep = false }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end
local function fixture(data)
    data = data or faction()
    C_Reputation = {
        GetWatchedFactionData = function() return data end,
        GetFactionDataByID = function(id) if id == data.factionID then return data end end,
        GetNumFactions = function() return 1 end,
        GetFactionDataByIndex = function() return data end,
        IsMajorFaction = function() return false end,
        IsFactionParagonForCurrentPlayer = function() return false end,
    }
    C_MajorFactions, C_GossipInfo = nil, nil
    FACTION_BAR_COLORS = nil
    BLUE_FONT_COLOR = nil
    return data
end
local function widget(settings)
    local result = { settings = copy(definition.defaults) }
    result.settings.presentation = "text"
    -- Detailed text/square-mode checks are independent of the factory gauge.
    result.settings.showStanding, result.settings.progress, result.settings.gaugeStyle = true, "percent", "square"
    for key, value in pairs(settings or {}) do result.settings[key] = value end
    function result:SetText(value) self.text = value end
    function result:HideGauge() self.gauge = nil; self.hiddenGauge = true end
    function result:SetGauge(value, maximum, color, label, width)
        self.gauge = { value = value, maximum = maximum, color = color, label = label, width = width }
        self.text = label
    end
    definition.update(result)
    return result
end
local function tooltip(forWidget)
    local lines = {}
    local tip = {
        AddLine = function(_, value) lines[#lines + 1] = value end,
        AddDoubleLine = function(_, left, right) lines[#lines + 1] = left .. ": " .. right end,
    }
    definition.tooltip(forWidget, tip)
    return table.concat(lines, "\n")
end

check("factory reputation follows the watched faction with a name-only theme-default gauge", function()
    fixture()
    equal(definition.defaults.factionID, 0); equal(definition.defaults.gaugeStyle, "theme")
    equal(definition.defaults.progress, "none"); equal(definition.defaults.showStanding, false)
    local value = widget({ presentation = definition.defaults.presentation,
        gaugeStyle = definition.defaults.gaugeStyle, progress = definition.defaults.progress,
        showStanding = definition.defaults.showStanding })
    equal(value.text, "Stormwind"); equal(value.gauge.value, 1500); equal(value.gauge.maximum, 6000)
end)

check("watched faction progress uses the current standing bracket", function()
    fixture()
    local value = widget()
    equal(value.text, "Stormwind: Friendly 25%")
    equal(value.reputationState.progress, 1500)
    equal(value.reputationState.total, 6000)
    assert(tooltip(value):match("Remaining: 4500"))
end)

check("ordinary reputation hover keeps its standing and progress without a redundant progression label", function()
    fixture()
    local text = tooltip(widget())
    assert(text:find("Good names are earned.", 1, true))
    assert(text:find("Standing: Friendly", 1, true))
    assert(text:find("Progress: 1500/6000 (25%)", 1, true))
    assert(text:find("Remaining: 4500", 1, true))
    assert(not text:find("Progression: Reputation", 1, true))
end)

check("public large progress amounts retain their decimal value in text and tooltips", function()
    fixture(faction({ currentStanding = 4294967296, currentReactionThreshold = 0, nextReactionThreshold = 8589934592 }))
    local value = widget({ progress = "fraction" })
    equal(value.text, "Stormwind: Friendly 4294967296/8589934592")
    assert(tooltip(value):find("Remaining: 4294967296", 1, true))
end)

check("overflowing public reputation ranges stay visibly unavailable", function()
    for _, data in ipairs({
        faction({ currentStanding = 0, currentReactionThreshold = -1e308, nextReactionThreshold = 1e308 }),
        faction({ currentStanding = 1e308, currentReactionThreshold = -1e308, nextReactionThreshold = 0 }),
    }) do
        fixture(data)
        local value = widget({ presentation = "gauge" })
        equal(value.text, "Stormwind: Friendly --")
        equal(value.reputationState.progress, nil)
        equal(value.gauge.value, 0)
        equal(value.gauge.maximum, 1)
        assert(tooltip(value):find("Progress is unavailable", 1, true))
    end
end)

check("restricted colors are not inspected or replaced with an alternate component", function()
    fixture()
    FACTION_BAR_COLORS = { [5] = secret }
    local value = widget({ presentation = "gauge" })
    equal(value.gauge.color[1], 0.5)
    FACTION_BAR_COLORS[5] = { r = secret, g = 0.6, b = 0.2, [1] = 0.9 }
    value = widget({ presentation = "gauge" })
    equal(value.gauge.color[1], 0.5)
    FACTION_BAR_COLORS[5] = { 0.9, 0.6, 0.2 }
    value = widget({ presentation = "gauge" })
    equal(value.gauge.color[1], 0.9)
end)

check("a selected faction is queried by ID instead of its list position", function()
    fixture()
    C_Reputation.GetWatchedFactionData = function() error("must not read watched faction") end
    local queried
    C_Reputation.GetFactionDataByID = function(id) queried = id; return faction({ factionID = id, name = "Chosen" }) end
    local value = widget({ factionID = 530, progress = "both" })
    equal(queried, 530)
    equal(value.text, "Chosen: Friendly 1500/6000 (25%)")
end)

check("no watched faction gives an actionable empty state", function()
    fixture()
    C_Reputation.GetWatchedFactionData = function() return nil end
    local value = widget()
    equal(value.text, "Reputation: no watched faction")
    assert(tooltip(value):match("Choose one"))
    C_Reputation.GetWatchedFactionData = function() return { factionID = 0 } end
    equal(widget().text, "Reputation: no watched faction")
end)

check("unavailable selected IDs remain selected", function()
    fixture()
    local value = widget({ factionID = 12345 })
    equal(value.text, "Reputation: unavailable")
    equal(value.settings.factionID, 12345)
    assert(tooltip(value):match("selected faction is unavailable"))
end)

check("negative reputation thresholds still produce bracket-relative progress", function()
    fixture(faction({ reaction = 1, currentStanding = -12000,
        currentReactionThreshold = -42000, nextReactionThreshold = -6000 }))
    local value = widget({ progress = "fraction" })
    equal(value.text, "Stormwind: Hated 30000/36000")
end)

check("standard exalted standing does not divide by an empty next bracket", function()
    fixture(faction({ reaction = 8, currentStanding = 42999,
        currentReactionThreshold = 42000, nextReactionThreshold = 42000 }))
    local value = widget()
    equal(value.text, "Stormwind: Exalted Maximum")
    assert(value.reputationState.complete)
end)

check("progress clamps transient out-of-bracket values", function()
    fixture(faction({ currentStanding = 99999 }))
    equal(widget().text, "Stormwind: Friendly 100%")
    fixture(faction({ currentStanding = -99999 }))
    equal(widget().text, "Stormwind: Friendly 0%")
end)

check("compact labels can show only a fraction", function()
    fixture()
    equal(widget({ showName = false, showStanding = false, progress = "fraction" }).text, "1500/6000")
end)

check("secret reputation values are not compared formatted or used in arithmetic", function()
    for _, field in ipairs({ "currentStanding", "currentReactionThreshold", "nextReactionThreshold" }) do
        fixture(faction({ [field] = secret }))
        local value = widget()
        equal(value.text, "Stormwind: Friendly --")
        assert(tooltip(value):match("unavailable"))
    end
    fixture(faction({ factionID = secret, name = secret }))
    local value = widget()
    equal(value.text, "Reputation: unavailable")
    assert(tooltip(value):match("restricted"))
end)

check("malformed numeric data gives an unavailable state", function()
    fixture(faction({ currentStanding = 0 / 0 }))
    equal(widget().text, "Stormwind: Friendly --")
    fixture(faction({ nextReactionThreshold = math.huge }))
    equal(widget().text, "Stormwind: Friendly --")
    fixture(faction({ nextReactionThreshold = 1000 }))
    equal(widget().text, "Stormwind: Friendly --")
    equal(widget({ factionID = -1 }).text, "Reputation: unavailable")
end)

check("renown uses renown-specific progress and supports maximum renown", function()
    fixture()
    C_Reputation.IsMajorFaction = function() return true end
    C_MajorFactions = { GetMajorFactionData = function()
        return { renownLevel = 5, maxLevel = 20, renownReputationEarned = 1250,
            renownLevelThreshold = 2500, isUnlocked = true }
    end, HasMaximumRenown = function() return false end }
    equal(widget().text, "Stormwind: Renown 5 50%")
    C_MajorFactions.HasMaximumRenown = function() return true end
    equal(widget().text, "Stormwind: Renown 5 Maximum")
end)

check("missing renown details never fall back to misleading standard progress", function()
    fixture()
    C_Reputation.IsMajorFaction = function() return true end
    local value = widget()
    equal(value.text, "Stormwind: --")
    assert(tooltip(value):match("Renown details are unavailable"))
end)

check("friendship uses friendship brackets and recognizes maximum friendship", function()
    fixture()
    local friendship = { friendshipFactionID = 99, standing = 5000, maxRep = 10000,
        reaction = "Buddy", reactionThreshold = 4000, nextThreshold = 10000 }
    C_GossipInfo = { GetFriendshipReputation = function() return friendship end }
    equal(widget({ progress = "fraction" }).text, "Stormwind: Buddy 1000/6000")
    friendship.standing, friendship.nextThreshold = 10000, nil
    equal(widget().text, "Stormwind: Buddy Maximum")
end)

check("paragon factions explicitly report unsupported reward-cycle progress", function()
    fixture()
    C_Reputation.IsFactionParagonForCurrentPlayer = function() return true end
    local value = widget()
    equal(value.text, "Stormwind: Paragon --")
    assert(tooltip(value):match("not supported yet"))
end)

check("paragon eligibility alone does not hide a player's normal standing progress", function()
    fixture()
    C_Reputation.IsFactionParagon = function() return true end
    equal(widget().text, "Stormwind: Friendly 25%")
end)

check("category headers do not pretend to have faction progress", function()
    fixture(faction({ isHeader = true, isHeaderWithRep = false }))
    local value = widget()
    equal(value.text, "Stormwind: --")
    assert(tooltip(value):match("category"))
end)

check("dynamic choices deduplicate exposed factions without changing collapsed headers", function()
    fixture()
    local rows = {
        faction({ factionID = 1, name = "Category", isHeader = true }),
        faction({ factionID = 2, name = "Zeta" }),
        faction({ factionID = 3, name = "Alpha", isHeader = true, isHeaderWithRep = true }),
        faction({ factionID = 2, name = "Zeta" }),
        faction({ factionID = secret, name = secret }),
    }
    C_Reputation.GetNumFactions = function() return #rows end
    C_Reputation.GetFactionDataByIndex = function(index) return rows[index] end
    C_Reputation.ExpandFactionHeader = function() error("must not change player headers") end
    C_Reputation.CollapseFactionHeader = function() error("must not change player headers") end
    local options = definition.settings[1].options({ factionID = 12345 })
    equal(#options, 3)
    equal(options[1].value, 0)
    equal(options[2].label, "Alpha")
    equal(options[3].label, "Zeta")
end)

check("unavailable or failing APIs remain usable through a fallback state", function()
    C_Reputation = nil
    equal(widget().text, "Reputation: unavailable")
    equal(#definition.settings[1].options({}), 1)
    fixture()
    C_Reputation.GetWatchedFactionData = function() error("API not ready") end
    equal(widget().text, "Reputation: unavailable")
end)

check("restricted classification does not fall back to an unrelated progression type", function()
    fixture()
    C_Reputation.IsMajorFaction = function() return secret end
    local value = widget()
    equal(value.text, "Stormwind: --")
    assert(tooltip(value):match("restricted"))
    fixture()
    C_GossipInfo = { GetFriendshipReputation = function() return { friendshipFactionID = secret } end }
    value = widget()
    equal(value.text, "Stormwind: --")
    assert(tooltip(value):match("restricted"))
end)

check("independent instances preserve different selections and display preferences", function()
    fixture()
    C_Reputation.GetFactionDataByID = function(id)
        return faction({ factionID = id, name = id == 1 and "First" or "Second" })
    end
    local one = widget({ factionID = 1 })
    local two = widget({ factionID = 2, showStanding = false, progress = "fraction" })
    equal(one.text, "First: Friendly 25%")
    equal(two.text, "Second: 1500/6000")
    assert(one.reputationState ~= two.reputationState)
    equal(one.settings.factionID, 1)
end)

check("gauge is the default and settings offer only exposed faction choices", function()
    fixture()
    equal(definition.defaults.presentation, "gauge")
    equal(definition.defaults.gaugeWidth, 160)
    for _, setting in ipairs(definition.settings) do
        assert(not (setting.key == "factionID" and setting.type == "number"))
    end
    local options = definition.settings[1].options({ factionID = 12345 })
    equal(#options, 2)
    equal(options[1].label, "Follow game's watched faction")
    equal(options[2].label, "Stormwind")
    assert(not tooltip(widget()):find("Faction ID", 1, true))
end)

check("an unset widget follows the experience bar watched faction without changing either Blizzard selection", function()
    local watched = fixture()
    local setterCalls = 0
    C_Reputation.SetWatchedFactionByID = function() setterCalls = setterCalls + 1 end
    C_Reputation.SetWatchedFactionByIndex = function() setterCalls = setterCalls + 1 end
    C_Reputation.SetSelectedFaction = function() setterCalls = setterCalls + 1 end
    C_Reputation.GetSelectedFaction = function() error("window selection is unrelated to watched XP-bar faction") end
    C_Reputation.GetFactionDataByID = function(id) return faction({ factionID = id, name = "Independent" }) end
    local follow = widget({ presentation = "gauge" })
    follow.settings.factionID = nil
    definition.update(follow)
    equal(follow.reputationState.factionID, watched.factionID)
    local fixed = widget({ presentation = "gauge", factionID = 99 })
    equal(fixed.reputationState.name, "Independent")
    equal(watched.factionID, 72)
    watched.name = "Watched changed"
    definition.update(follow)
    equal(follow.reputationState.name, "Watched changed")
    equal(fixed.reputationState.name, "Independent")
    equal(setterCalls, 0)
end)

check("watched fallback reads exposed isWatched rows when the direct API is missing or empty", function()
    fixture()
    local watched = faction({ factionID = 99, name = "Tracked", isWatched = true })
    local rows = { faction({ factionID = 98, isWatched = secret }), watched }
    C_Reputation.GetNumFactions = function() return #rows end
    C_Reputation.GetFactionDataByIndex = function(index) return rows[index] end
    C_Reputation.GetWatchedFactionData = nil
    equal(widget().reputationState.name, "Tracked")
    C_Reputation.GetWatchedFactionData = function() return nil end
    equal(widget().reputationState.name, "Tracked")
    C_Reputation.GetWatchedFactionData = function() return { factionID = 0 } end
    equal(widget().reputationState.name, "Tracked")
    C_Reputation.GetWatchedFactionData = function() error("not ready") end
    equal(widget().reputationState.name, "Tracked")
end)

check("malformed direct watched data falls back to an exposed watched row without bypassing restrictions", function()
    fixture()
    local exposed = faction({ factionID = 99, name = "Actually tracked", isWatched = true })
    C_Reputation.GetFactionDataByIndex = function() return exposed end
    for _, malformed in ipairs({ { name = "Missing ID" }, { factionID = -1 }, { factionID = 0 },
        { factionID = "not an ID" }, { factionID = math.huge } }) do
        C_Reputation.GetWatchedFactionData = function() return malformed end
        equal(widget().reputationState.factionID, 99)
    end
    C_Reputation.GetWatchedFactionData = function() return { factionID = secret } end
    local value = widget()
    equal(value.reputationState.factionID, nil)
    equal(value.text, "Reputation: unavailable")
    assert(tooltip(value):match("restricted"))
end)

check("gauge fill and colour follow current bracket and standing changes", function()
    local data = fixture()
    FACTION_BAR_COLORS = {
        [5] = { GetRGB = function() return 0.1, 0.7, 0.2 end },
        [6] = { 0.2, 0.8, 0.3 },
    }
    local value = widget({ presentation = "gauge" })
    equal(value.gauge.value, 1500)
    equal(value.gauge.maximum, 6000)
    equal(value.gauge.width, 160)
    equal(value.gauge.color[2], 0.7)
    equal(value.gauge.color[4], 1)
    equal(value.gauge.label, "Stormwind: Friendly 25%")
    data.reaction, data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding = 6, 9000, 21000, 12000
    definition.update(value)
    equal(value.gauge.value, 3000)
    equal(value.gauge.maximum, 12000)
    equal(value.gauge.color[2], 0.8)
    equal(value.gauge.label, "Stormwind: Honored 25%")
end)

check("each standing reads its own live Blizzard colour instead of a hardcoded palette", function()
    for standing = 1, 8 do
        fixture(faction({ reaction = standing }))
        FACTION_BAR_COLORS = { [standing] = { r = standing / 10, g = 0.25, b = 0.5 } }
        local value = widget({ presentation = "gauge" })
        equal(value.gauge.color[1], standing / 10)
        equal(value.gauge.color[2], 0.25)
    end
end)

check("friendship stays green and renown uses the native blue colour", function()
    fixture(faction({ reaction = 2 }))
    FACTION_BAR_COLORS = { [2] = { 1, 0, 0 }, [5] = { 0.1, 0.9, 0.2 } }
    C_GossipInfo = { GetFriendshipReputation = function()
        return { friendshipFactionID = 99, standing = 5000, maxRep = 10000,
            reaction = "Buddy", reactionThreshold = 4000, nextThreshold = 10000 }
    end }
    equal(widget({ presentation = "gauge" }).gauge.color[2], 0.9)
    C_Reputation.IsMajorFaction = function() return true end
    C_MajorFactions = { GetMajorFactionData = function()
        return { renownLevel = 5, renownReputationEarned = 1250, renownLevelThreshold = 2500, isUnlocked = true }
    end }
    BLUE_FONT_COLOR = { GetRGB = function() return 0.2, 0.4, 0.95 end }
    local value = widget({ presentation = "gauge" })
    equal(value.gauge.color[3], 0.95)
    equal(value.gauge.value, 1250)
    equal(value.gauge.maximum, 2500)
end)

check("maximum reputation is a full gauge without division by an empty bracket", function()
    fixture(faction({ reaction = 8, currentStanding = 42999,
        currentReactionThreshold = 42000, nextReactionThreshold = 42000 }))
    local value = widget({ presentation = "gauge", showName = false })
    equal(value.gauge.value, 1)
    equal(value.gauge.maximum, 1)
    equal(value.gauge.label, "Exalted 100%")
end)

check("gauge overlays independently select standing, value, percentage or no text", function()
    fixture()
    local value = widget({ presentation = "gauge", showName = false, showStanding = false, progress = "none" })
    equal(value.gauge.label, "")
    equal(value.gauge.value, 1500)
    value.settings.progress = "fraction"
    definition.update(value)
    equal(value.gauge.label, "1500/6000")
    value.settings.showStanding, value.settings.progress = true, "percent"
    definition.update(value)
    equal(value.gauge.label, "Friendly 25%")
end)

check("name-only reputation has no trailing colon in text and either gauge style", function()
    for _, reaction in ipairs({ 5, 8 }) do
        for _, presentation in ipairs({ "text", "gauge" }) do
            for _, gaugeStyle in ipairs({ "square", "warcraft" }) do
                fixture(faction({ name = "Undercity", reaction = reaction }))
                local value = widget({ presentation = presentation, gaugeStyle = gaugeStyle,
                    showName = true, showStanding = false, progress = "none" })
                equal(value.text, "Undercity")
                if value.gauge then equal(value.gauge.label, "Undercity") end
            end
        end
    end
end)

check("the faction-name colon separates only visible following fields", function()
    for _, presentation in ipairs({ "text", "gauge" }) do
        fixture()
        local value = widget({ presentation = presentation, showName = true,
            showStanding = true, progress = "none" })
        equal(value.text, "Stormwind: Friendly")
        value.settings.showStanding, value.settings.progress = false, "percent"
        definition.update(value)
        equal(value.text, "Stormwind: 25%")
        value.settings.progress = "none"
        definition.update(value)
        equal(value.text, "Stormwind")
        value.settings.showName, value.settings.showStanding = false, true
        definition.update(value)
        equal(value.text, "Friendly")
        value.settings.showStanding, value.settings.progress = false, "fraction"
        definition.update(value)
        equal(value.text, "1500/6000")
    end
end)

check("unavailable progress retains its separator and explicit unknown marker", function()
    for _, presentation in ipairs({ "text", "gauge" }) do
        fixture(faction({ currentStanding = secret }))
        local value = widget({ presentation = presentation, showName = true,
            showStanding = false, progress = "none" })
        equal(value.text, "Stormwind: --")
        if value.gauge then equal(value.gauge.value, 0); equal(value.gauge.maximum, 1) end
    end
end)

check("unavailable gauge progress is empty with an explicit unknown marker", function()
    fixture(faction({ currentStanding = secret }))
    local value = widget({ presentation = "gauge", progress = "none" })
    equal(value.gauge.value, 0)
    equal(value.gauge.maximum, 1)
    assert(value.gauge.label:find("--", 1, true))
    assert(not value.gauge.label:find("0%%"))
    fixture()
    C_Reputation.GetWatchedFactionData = function() return nil end
    value = widget({ presentation = "gauge" })
    equal(value.gauge.label, "Reputation: no watched faction")
end)

check("gauge styles stay independent while reputation progress and colour are preserved", function()
    fixture()
    FACTION_BAR_COLORS = { [5] = { 0.1, 0.7, 0.2 } }
    local setting
    for _, candidate in ipairs(definition.settings) do
        if candidate.key == "gaugeStyle" then setting = candidate end
    end
    assert(setting, "gauge style picker is registered")
    equal(setting.label, "Gauge style")
    equal(setting.type, "select")
    equal(#setting.options, 3)
    equal(setting.options[1].value, "theme")
    equal(setting.options[1].label, "Theme default")
    equal(setting.options[2].value, "square")
    equal(setting.options[2].label, "Square")
    equal(setting.options[3].value, "warcraft")
    equal(setting.options[3].label, "Warcraft")
    local first = widget({ presentation = "gauge", gaugeStyle = "warcraft", progress = "fraction", gaugeWidth = 240 })
    local second = widget({ presentation = "gauge" })
    equal(first.settings.gaugeStyle, "warcraft")
    equal(second.settings.gaugeStyle, "square")
    local before = first.gauge
    first.settings.gaugeStyle = "square"
    definition.update(first)
    definition.update(second)
    equal(first.settings.gaugeStyle, "square")
    equal(second.settings.gaugeStyle, "square")
    equal(first.gauge.value, before.value)
    equal(first.gauge.maximum, before.maximum)
    equal(first.gauge.label, "Stormwind: Friendly 1500/6000")
    equal(first.gauge.width, 240)
    for channel = 1, 4 do equal(first.gauge.color[channel], before.color[channel]) end
    equal(second.gauge.label, "Stormwind: Friendly 25%")
    equal(second.gauge.width, 160)
    equal(definition.defaults.gaugeStyle, "theme")
end)

check("text mode clears an existing gauge and corrupt widths fall back safely", function()
    fixture()
    local value = widget({ presentation = "gauge", gaugeWidth = math.huge })
    equal(value.gauge.width, 160)
    value.settings.presentation = "text"
    definition.update(value)
    equal(value.gauge, nil)
    assert(value.hiddenGauge)
    equal(value.text, "Stormwind: Friendly 25%")
end)

check("opening the direct faction picker never changes either watched-faction preference", function()
    fixture()
    C_Reputation.SetWatchedFactionByID = function() error("Do not change Blizzard's watched reputation") end
    C_Reputation.SetWatchedFactionByIndex = C_Reputation.SetWatchedFactionByID
    local value = { settings = { factionID = 72, showName = true }, text = "Stormwind" }
    local calls = 0
    function value:OpenChoiceMenu(key, title)
        equal(key, "factionID"); equal(title, "Watch reputation")
        calls = calls + 1
        return true
    end
    equal(definition.click(value), true)
    equal(calls, 1); equal(value.settings.factionID, 72); equal(value.text, "Stormwind")
    for _, missing in ipairs({ false, "unsupported", secret }) do
        value.OpenChoiceMenu = missing
        equal(definition.click(value), false)
        equal(value.settings.factionID, 72); equal(value.settings.showName, true)
    end
    value.OpenChoiceMenu = nil; equal(definition.click(value), false)
    equal(calls, 1)
end)

print(string.format("%d reputation tests passed", passed))
