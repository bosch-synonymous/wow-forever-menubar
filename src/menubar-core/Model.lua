-- Menubar's persisted state. This file deliberately has no game API dependencies.
local Model = {}
_G.MenubarModel = Model

Model.SCHEMA_VERSION = 1
-- Repair incomplete saved profiles using their original defaults. Factory
-- preferences can change without restyling an existing character on login.
local legacyProfileDefaults = {
    theme = "system7",
    placement = "top",
    coreMenuBar = "both",
    roundedCorners = true,
    height = 24,
    font = "Fonts\\ARIALN.TTF",
    fontSize = 12,
    fontFlags = "",
    fontStyle = "regular",
    textShadow = false,
    opacity = 1,
    background = { 0.86, 0.86, 0.86, 1 },
    textColor = { 0, 0, 0, 1 },
    topLine = { 1, 1, 1, 1 },
    bottomLine = { 0, 0, 0, 1 },
    topLineSize = 1,
    bottomLineSize = 1,
    texture = "solid",
    padding = 8,
    spacing = 12,
}

Model.DefaultProfile = {
    theme = "warcraftBrown",
    placement = "top",
    coreMenuBar = "both",
    roundedCorners = false,
    height = 24,
    font = "Fonts\\FRIZQT__.TTF",
    fontSize = 12,
    fontFlags = "",
    fontStyle = "regular",
    textShadow = true,
    opacity = 0.7,
    background = { 1, 1, 1, 1 },
    textColor = { 1, 0.82, 0, 1 },
    topLine = { 0.48, 0.36, 0.18, 1 },
    bottomLine = { 1, 1, 1, 1 },
    topLineSize = 1,
    bottomLineSize = 4,
    texture = "theme",
    padding = 8,
    spacing = 12,
}

Model.Themes = {
    system7 = {
        theme = "system7", background = { 1, 1, 1, 1 }, textColor = { 0, 0, 0, 1 },
        topLine = { 1, 1, 1, 1 }, bottomLine = { 0, 0, 0, 1 },
        topLineSize = 0, bottomLineSize = 1, texture = "solid",
        font = "Fonts\\FRIZQT__.TTF", fontStyle = "regular", textShadow = false, roundedCorners = true,
    },
    macos8 = {
        theme = "macos8", background = { 0.8, 0.8, 0.8, 1 }, textColor = { 0, 0, 0, 1 },
        topLine = { 1, 1, 1, 1 }, bottomLine = { 0.18, 0.18, 0.18, 1 },
        topLineSize = 1, bottomLineSize = 2, texture = "solid",
        font = "Fonts\\FRIZQT__.TTF", fontStyle = "regular", textShadow = false, roundedCorners = true,
    },
    macosx = {
        theme = "macosx", background = { 0.94, 0.95, 0.96, 1 }, textColor = { 0, 0, 0, 1 },
        topLine = { 1, 1, 1, 1 }, bottomLine = { 0.4, 0.42, 0.45, 1 },
        topLineSize = 1, bottomLineSize = 1, texture = "theme",
        font = "Fonts\\FRIZQT__.TTF", fontStyle = "regular", textShadow = false, roundedCorners = true,
    },
    warcraftBrown = {
        theme = "warcraftBrown", background = { 1, 1, 1, 1 }, textColor = { 1, 0.82, 0, 1 },
        topLine = { 0.48, 0.36, 0.18, 1 }, bottomLine = { 1, 1, 1, 1 },
        topLineSize = 1, bottomLineSize = 4, texture = "theme",
        font = "Fonts\\FRIZQT__.TTF", fontStyle = "regular", textShadow = true, roundedCorners = false,
    },
    warcraftBlack = {
        theme = "warcraftBlack", background = { 1, 1, 1, 1 }, textColor = { 1, 1, 1, 1 },
        topLine = { 0.26, 0.23, 0.18, 1 }, bottomLine = { 1, 1, 1, 1 },
        topLineSize = 1, bottomLineSize = 4, texture = "theme",
        font = "Fonts\\FRIZQT__.TTF", fontStyle = "regular", textShadow = true, roundedCorners = false,
    },
    warcraftRed = {
        theme = "warcraftRed", background = { 1, 1, 1, 1 }, textColor = { 1, 0.82, 0, 1 },
        topLine = { 0.38, 0.3, 0.18, 1 }, bottomLine = { 1, 1, 1, 1 },
        topLineSize = 1, bottomLineSize = 4, texture = "theme",
        font = "Fonts\\FRIZQT__.TTF", fontStyle = "regular", textShadow = true, roundedCorners = false,
    },
}

function Model.ApplyTheme(profile, id)
    local theme = Model.Themes[id]
    if not theme then return nil, "Unknown bar style" end
    for key, value in pairs(theme) do profile[key] = Model.DeepCopy(value) end
    return true
end

local validBars = { top = true, bottom = true }
local validPlacements = { top = true, bottom = true, both = true }
local validAlignments = { left = true, center = true, right = true }
function Model.DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[Model.DeepCopy(key, seen)] = Model.DeepCopy(item, seen)
    end
    return result
end

local function number(value, fallback, minimum, maximum, integer)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        value = fallback
    end
    value = math.max(minimum, math.min(maximum, value))
    return integer and math.floor(value) or value
end

local function nonemptyString(value)
    return type(value) == "string" and value:match("%S") ~= nil
end

local function color(value, fallback)
    if type(value) ~= "table" then value = {} end
    for index = 1, 4 do
        value[index] = number(value[index], fallback[index], 0, 1)
    end
    return value
end

function Model.NormalizeProfile(profile)
    profile = type(profile) == "table" and profile or {}
    local defaults = legacyProfileDefaults
    profile.theme = Model.Themes[profile.theme] and profile.theme or "system7"
    profile.placement = validPlacements[profile.placement] and profile.placement or defaults.placement
    profile.height = number(profile.height, defaults.height, 16, 96, true)
    profile.font = nonemptyString(profile.font) and profile.font or defaults.font
    profile.fontSize = number(profile.fontSize, defaults.fontSize, 8, 48, true)
    -- Outline flags are no longer an appearance option. Weight/slant use real font faces.
    profile.fontFlags = ""
    local styles = { regular = true, bold = true, italic = true, bolditalic = true }
    profile.fontStyle = styles[profile.fontStyle] and profile.fontStyle or "regular"
    profile.textShadow = profile.textShadow == true
    profile.coreMenuBar = validPlacements[profile.coreMenuBar] and profile.coreMenuBar or "both"
    profile.roundedCorners = profile.roundedCorners ~= false
    profile.opacity = number(profile.opacity, defaults.opacity, 0, 1)
    profile.background = color(profile.background, defaults.background)
    profile.textColor = color(profile.textColor, defaults.textColor)
    profile.topLine = color(profile.topLine, defaults.topLine)
    profile.bottomLine = color(profile.bottomLine, defaults.bottomLine)
    local legacyLineSize = number(profile.lineSize, 1, 0, 6, true)
    profile.topLineSize = number(profile.topLineSize, legacyLineSize, 0, 6, true)
    profile.bottomLineSize = number(profile.bottomLineSize, legacyLineSize, 0, 6, true)
    profile.texture = nonemptyString(profile.texture) and profile.texture or defaults.texture
    profile.padding = number(profile.padding, defaults.padding, 0, 64, true)
    profile.spacing = number(profile.spacing, defaults.spacing, 0, 64, true)
    return profile
end

local function widgetLess(a, b)
    if a.bar ~= b.bar then return a.bar == "top" end
    if a.alignment ~= b.alignment then
        local ranks = { left = 1, center = 2, right = 3 }
        return ranks[a.alignment] < ranks[b.alignment]
    end
    if a.order ~= b.order then return a.order < b.order end
    return a.id < b.id
end

local function group(character, bar, alignment, exceptID)
    local result = {}
    for _, widget in ipairs(character.widgets) do
        if widget.bar == bar and widget.alignment == alignment and widget.id ~= exceptID then
            result[#result + 1] = widget
        end
    end
    table.sort(result, widgetLess)
    return result
end

local function renumber(widgets)
    for index, widget in ipairs(widgets) do widget.order = index end
end

local maximumWidgetID = 2147483647
local function allocateID(character, reserved)
    local sequence = character.nextWidgetID
    local id = "w" .. sequence
    while reserved[id] do
        sequence = sequence == maximumWidgetID and 1 or sequence + 1
        id = "w" .. sequence
    end
    character.nextWidgetID = sequence == maximumWidgetID and 1 or sequence + 1
    reserved[id] = true
    return id
end

local function normalizeCharacter(character)
    character = type(character) == "table" and character or {}
    character.profile = nonemptyString(character.profile) and character.profile or "Default"
    character.initializedTypes = type(character.initializedTypes) == "table" and character.initializedTypes or {}
    character.nextWidgetID = number(character.nextWidgetID, 1, 1, 2147483647, true)
    local source = type(character.widgets) == "table" and character.widgets or {}
    local indices, widgets, usedIDs, reserved = {}, {}, {}, {}
    for index, widget in pairs(source) do
        if type(index) == "number" and index >= 1 and index % 1 == 0 and type(widget) == "table" then
            indices[#indices + 1] = index
        end
    end
    table.sort(indices)
    -- Repairing a missing ID must not steal a later instance's existing ID.
    for _, index in ipairs(indices) do
        local id = source[index].id
        if nonemptyString(id) then
            reserved[id] = true
            local sequence = tonumber(id:match("^w(%d+)$"))
            if sequence and sequence < maximumWidgetID then
                character.nextWidgetID = math.max(character.nextWidgetID, sequence + 1)
            end
        end
    end
    for _, index in ipairs(indices) do
        local widget = source[index]
        if not nonemptyString(widget.id) or usedIDs[widget.id] then
            widget.id = allocateID(character, reserved)
        end
        usedIDs[widget.id] = true
        widget.type = nonemptyString(widget.type) and widget.type or "unknown"
        widget.settings = type(widget.settings) == "table" and widget.settings or {}
        widget.bar = validBars[widget.bar] and widget.bar or "top"
        widget.alignment = validAlignments[widget.alignment] and widget.alignment or "right"
        widget.order = number(widget.order, index, 1, 2147483647, true)
        widget.enabled = widget.enabled ~= false
        character.initializedTypes[widget.type] = true
        widgets[#widgets + 1] = widget
    end
    character.widgets = widgets
    for bar in pairs(validBars) do
        for alignment in pairs(validAlignments) do renumber(group(character, bar, alignment)) end
    end
    return character
end

function Model.Initialize(savedDB, characterKey, legacyKeys)
    assert(nonemptyString(characterKey), "A character key is required")
    if savedDB ~= nil and type(savedDB) ~= "table" then
        return nil, nil, nil, "Saved settings have an unrecognized format; they have been preserved"
    end
    local db = savedDB or {}
    local version = db.schemaVersion
    if version ~= nil and (type(version) ~= "number" or version ~= version or version < 0 or version == math.huge or version % 1 ~= 0) then
        return nil, nil, nil, "Saved settings have an unrecognized schema version; they have been preserved"
    end
    if version and version > Model.SCHEMA_VERSION then
        return nil, nil, nil, "Saved settings were written by a newer Menubar version"
    end
    db.schemaVersion = Model.SCHEMA_VERSION
    db.customFonts = type(db.customFonts) == "table" and db.customFonts or {}
    db.profiles = type(db.profiles) == "table" and db.profiles or {}
    if db.profiles.Default == nil then
        db.profiles.Default = Model.DeepCopy(Model.DefaultProfile)
    end
    for name, profile in pairs(db.profiles) do
        if nonemptyString(name) then db.profiles[name] = Model.NormalizeProfile(profile)
        else db.profiles[name] = nil end
    end
    db.profiles.Default = Model.NormalizeProfile(db.profiles.Default)
    db.characters = type(db.characters) == "table" and db.characters or {}
    for key, character in pairs(db.characters) do
        character = normalizeCharacter(character)
        if not db.profiles[character.profile] then character.profile = "Default" end
        db.characters[key] = character
    end
    if not db.characters[characterKey] and type(legacyKeys) == "table" then
        for _, legacyKey in ipairs(legacyKeys) do
            if type(legacyKey) == "string" and type(db.characters[legacyKey]) == "table" then
                -- Preserve the original record for recovery or an older client.
                -- Copying also separates characters once distinguished by GUID.
                db.characters[characterKey] = Model.DeepCopy(db.characters[legacyKey])
                break
            end
        end
    end
    local character = Model.GetCharacter(db, characterKey)
    return db, character, db.profiles[character.profile]
end

function Model.GetCharacter(db, characterKey)
    assert(nonemptyString(characterKey), "A character key is required")
    local character = db.characters[characterKey]
    if not character then
        character = normalizeCharacter({})
        db.characters[characterKey] = character
    end
    return character
end

function Model.GetProfile(db, characterKey)
    return db.profiles[Model.GetCharacter(db, characterKey).profile]
end

function Model.CreateProfile(db, name, copyFromName)
    if not nonemptyString(name) then return nil, "Enter a profile name" end
    name = name:match("^%s*(.-)%s*$")
    if db.profiles[name] then return nil, "That profile already exists" end
    if copyFromName and not db.profiles[copyFromName] then return nil, "The source profile does not exist" end
    local source = copyFromName and db.profiles[copyFromName] or Model.DefaultProfile
    local profile = Model.NormalizeProfile(Model.DeepCopy(source))
    db.profiles[name] = profile
    return profile
end

function Model.SetProfile(db, characterKey, name)
    if not db.profiles[name] then return nil, "That profile does not exist" end
    Model.GetCharacter(db, characterKey).profile = name
    return true
end

function Model.ListWidgets(db, characterKey, bar, alignment)
    local result = {}
    for _, widget in ipairs(Model.GetCharacter(db, characterKey).widgets) do
        if (not bar or widget.bar == bar) and (not alignment or widget.alignment == alignment) then
            result[#result + 1] = widget
        end
    end
    table.sort(result, widgetLess)
    -- Include disabled and unavailable providers so management UI can retain them.
    return result
end

function Model.GetWidget(db, characterKey, id)
    for _, widget in ipairs(Model.GetCharacter(db, characterKey).widgets) do
        if widget.id == id then return widget end
    end
end

function Model.AddWidget(db, characterKey, typeID, settings, placement)
    if not nonemptyString(typeID) then return nil, "A widget type is required" end
    local character = Model.GetCharacter(db, characterKey)
    placement = type(placement) == "table" and placement or {}
    local bar = validBars[placement.bar] and placement.bar or "top"
    local alignment = validAlignments[placement.alignment] and placement.alignment or "right"
    local reserved = {}
    for _, existing in ipairs(character.widgets) do reserved[existing.id] = true end
    local id = allocateID(character, reserved)
    local widget = {
        id = id,
        type = typeID,
        settings = type(settings) == "table" and Model.DeepCopy(settings) or {},
        bar = bar,
        alignment = alignment,
        order = #group(character, bar, alignment) + 1,
        enabled = true,
    }
    character.widgets[#character.widgets + 1] = widget
    character.initializedTypes[typeID] = true
    if placement.order then Model.MoveWidget(db, characterKey, id, bar, alignment, placement.order) end
    return widget
end

function Model.RemoveWidget(db, characterKey, id)
    local character = Model.GetCharacter(db, characterKey)
    for index, widget in ipairs(character.widgets) do
        if widget.id == id then
            table.remove(character.widgets, index)
            renumber(group(character, widget.bar, widget.alignment))
            return true
        end
    end
    return nil, "That widget does not exist"
end

function Model.MoveWidget(db, characterKey, id, bar, alignment, index)
    if not validBars[bar] or not validAlignments[alignment] then return nil, "Invalid widget placement" end
    local character = Model.GetCharacter(db, characterKey)
    local widget = Model.GetWidget(db, characterKey, id)
    if not widget then return nil, "That widget does not exist" end
    local previousBar, previousAlignment = widget.bar, widget.alignment
    local destination = group(character, bar, alignment, id)
    index = number(index, #destination + 1, 1, #destination + 1, true)
    widget.bar, widget.alignment = bar, alignment
    table.insert(destination, index, widget)
    renumber(destination)
    if previousBar ~= bar or previousAlignment ~= alignment then
        renumber(group(character, previousBar, previousAlignment))
    end
    return true
end

function Model.ReorderWidget(db, characterKey, id, delta)
    local widget = Model.GetWidget(db, characterKey, id)
    if not widget then return nil, "That widget does not exist" end
    local widgets = group(Model.GetCharacter(db, characterKey), widget.bar, widget.alignment)
    delta = number(delta, 0, -#widgets, #widgets, true)
    return Model.MoveWidget(db, characterKey, id, widget.bar, widget.alignment,
        math.max(1, math.min(#widgets, widget.order + delta)))
end

return Model
