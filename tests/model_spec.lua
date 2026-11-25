-- Run from the repository root: lua tests/model_spec.lua
local Model = dofile("src/menubar-core/Model.lua")
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

check("fresh state has a shared profile and separate character layouts", function()
    local db, first, appearance = Model.Initialize(nil, "Realm:First")
    equal(db.schemaVersion, 1)
    equal(appearance.theme, "warcraftBrown")
    equal(appearance.placement, "top")
    equal(appearance.coreMenuBar, "both")
    equal(appearance.roundedCorners, false)
    equal(appearance.font, "Fonts\\FRIZQT__.TTF")
    equal(appearance.fontStyle, "regular")
    equal(appearance.fontFlags, "")
    equal(appearance.textShadow, true)
    equal(appearance.opacity, 0.90)
    equal(appearance.popupOpacity, 0.90)
    equal(appearance.texture, "theme")
    equal(appearance.topLineSize, 1)
    equal(appearance.bottomLineSize, 4)
    assert(type(db.customFonts) == "table")
    equal(first.profile, "Default")
    local second = Model.GetCharacter(db, "Realm:Second")
    equal(Model.GetProfile(db, "Realm:Second"), appearance)
    assert(first.widgets ~= second.widgets)
    assert(first.initializedTypes ~= second.initializedTypes)
end)

check("factory profiles are copied independently while saved appearance keeps legacy repairs", function()
    local first, _, profile = Model.Initialize(nil, "A")
    local second = Model.Initialize(nil, "B")
    local original = Model.DefaultProfile.background[1]
    profile.background[1] = 0.2
    equal(second.profiles.Default.background[1], original)
    equal(Model.DefaultProfile.background[1], original)
    local copy = assert(Model.CreateProfile(first, "Factory"))
    equal(copy.theme, "warcraftBrown"); equal(copy.opacity, 0.90)
    equal(copy.popupOpacity, 0.90); equal(copy.popupText.fontSize, 14)
    equal(copy.background[1], original)
    assert(copy.background ~= Model.DefaultProfile.background)

    local saved = { profiles = { Default = { custom = "preserved" } } }
    local _, _, legacy = Model.Initialize(saved, "A")
    equal(legacy.theme, "system7"); equal(legacy.font, "Fonts\\ARIALN.TTF")
    equal(legacy.opacity, 1); equal(legacy.texture, "solid")
    equal(legacy.popupOpacity, 1)
    equal(legacy.background[1], 0.86); equal(legacy.textColor[1], 0)
    equal(legacy.roundedCorners, true); equal(legacy.textShadow, false)
    equal(legacy.bottomLineSize, 1); equal(legacy.custom, "preserved")
end)

check("every saved profile keeps its popup opacity across migration and subsequent reloads", function()
    local saved = { profiles = {
        Default = { theme = "macos27", opacity = 0.45 },
        Linked = { opacity = 0.62, fullOpacityPopups = false },
        Opaque = { opacity = 0.25, fullOpacityPopups = true },
        Explicit = { opacity = 0.45, popupOpacity = 0, fullOpacityPopups = true },
        Bounded = { opacity = 0.12, popupOpacity = 2 },
        Low = { opacity = 0.88, popupOpacity = -0.3 },
        Corrupt = { opacity = 0.5, popupOpacity = 0 / 0 },
    } }
    local db = Model.Initialize(saved, "A")
    local expected = { Default = 0.45, Linked = 0.62, Opaque = 1,
        Explicit = 0, Bounded = 1, Low = 0, Corrupt = 0.5 }
    for name, alpha in pairs(expected) do
        equal(db.profiles[name].popupOpacity, alpha)
        equal(db.profiles[name].fullOpacityPopups, nil)
    end
    db.profiles.Default.opacity = 0.8
    db.profiles.Opaque.popupOpacity = 0.67
    Model.Initialize(db, "A")
    equal(db.profiles.Default.popupOpacity, 0.45)
    equal(db.profiles.Opaque.popupOpacity, 0.67)
    equal(db.profiles.Opaque.opacity, 0.25)
end)

check("panel typography preserves native defaults and stores independent shared-profile choices", function()
    local db, _, profile = Model.Initialize({ profiles = { Default = { fontSize = 19 } } }, "A")
    local panel = profile.popupText
    equal(panel.font, "theme"); equal(panel.fontSize, 0)
    equal(panel.fontStyle, "regular"); equal(panel.useCustomColor, false)
    equal(profile.fontSize, 19)
    panel.font, panel.fontStyle, panel.fontSize = "Fonts\\Custom.ttf", "italic", 21
    panel.useCustomColor, panel.textColor = true, { 0.14, 0.27, 0.51, 0.1 }
    local copy = assert(Model.CreateProfile(db, "Reader", "Default"))
    assert(copy.popupText ~= panel and copy.popupText.textColor ~= panel.textColor)
    copy.popupText.textColor[1] = 0.72
    assert(Model.ApplyTheme(profile, "macos27"))
    equal(profile.popupText.font, "theme"); equal(profile.popupText.fontSize, 0)
    Model.Initialize(db, "A")
    assert(Model.ApplyTheme(profile, "system7"))
    equal(profile.popupText.font, "Fonts\\Custom.ttf")
    equal(profile.popupText.fontSize, 21); equal(profile.popupText.fontStyle, "italic")
    equal(profile.popupText.textColor[1], 0.14); equal(profile.popupText.textColor[4], 1)
    equal(copy.popupText.textColor[1], 0.72)
    equal(Model.NormalizeProfile({ popupText = "invalid" }).popupText.font, "theme")
end)

check("bar and popup preferences return independently after theme switches, copying and reload", function()
    local db, _, brown = Model.Initialize(nil, "A")
    brown.font, brown.fontStyle, brown.fontSize = "Custom\\Bar.ttf", "bold", 14
    brown.textShadow, brown.textColor = false, { 0.22, 0.36, 0.56, 0.75 }
    brown.opacity, brown.popupOpacity = 0.32, 0.84
    brown.popupText = { font = "Custom\\Panel.ttf", fontStyle = "italic", fontSize = 16,
        useCustomColor = true, textColor = { 0.48, 0.41, 0.37, 1 } }
    assert(Model.ApplyTheme(brown, "macos27"))
    equal(brown.fontSize, 12); equal(brown.opacity, 0.45); equal(brown.popupOpacity, 0.90)
    equal(brown.popupText.fontSize, 0); equal(brown.popupText.useCustomColor, false)
    brown.opacity, brown.popupOpacity, brown.fontSize = 0, 1, 19
    brown.textColor = { 0.79, 0.88, 0.99, 1 }
    brown.popupText.fontSize = 21

    local copy = assert(Model.CreateProfile(db, "Night", "Default"))
    assert(Model.ApplyTheme(copy, "warcraftBrown"))
    equal(copy.font, "Custom\\Bar.ttf"); equal(copy.fontStyle, "bold"); equal(copy.fontSize, 14)
    equal(copy.textShadow, false); equal(copy.textColor[4], 0.75)
    equal(copy.opacity, 0.32); equal(copy.popupOpacity, 0.84)
    equal(copy.popupText.font, "Custom\\Panel.ttf"); equal(copy.popupText.fontStyle, "italic")
    equal(copy.popupText.fontSize, 16); equal(copy.popupText.useCustomColor, true)
    equal(copy.popupText.textColor[1], 0.48)
    copy.popupText.textColor[1], copy.textColor[1] = 0.08, 0.09

    local reloaded = Model.Initialize(Model.DeepCopy(db), "A")
    local original = reloaded.profiles.Default
    equal(original.theme, "macos27"); equal(original.fontSize, 19); equal(original.popupText.fontSize, 21)
    equal(original.opacity, 0); equal(original.popupOpacity, 1)
    assert(Model.ApplyTheme(original, "warcraftBrown"))
    equal(original.popupText.textColor[1], 0.48); equal(original.textColor[1], 0.22)
    equal(original.popupText.fontSize, 16); equal(original.opacity, 0.32)
    assert(Model.ApplyTheme(original, "macos27"))
    equal(original.textColor[2], 0.88); equal(original.popupText.fontSize, 21)
    equal(original.fontSize, 19); equal(original.opacity, 0); equal(original.popupOpacity, 1)
    equal(reloaded.profiles.Night.popupText.textColor[1], 0.08)
    equal(Model.Themes.warcraftBrown.textColor[1], 1)
end)

check("a style can supply distinct first-use bar and popup defaults without sharing writable colours", function()
    local _, _, profile = Model.Initialize(nil, "A")
    local style = Model.DeepCopy(Model.Themes.macosx)
    style.theme, style.fontSize, style.opacity, style.popupOpacity = "testAppearance", 14, 0.52, 0.93
    style.popupText = { font = "Test.ttf", fontStyle = "italic", fontSize = 18,
        useCustomColor = true, textColor = { 0.1, 0.2, 0.3, 1 } }
    Model.Themes.testAppearance = style
    assert(Model.ApplyTheme(profile, "testAppearance"))
    equal(profile.fontSize, 14); equal(profile.opacity, 0.52); equal(profile.popupOpacity, 0.93)
    equal(profile.popupText.font, "Test.ttf"); equal(profile.popupText.fontStyle, "italic")
    equal(profile.popupText.fontSize, 18); equal(profile.popupText.textColor[2], 0.2)
    profile.popupText.textColor[2] = 0.6
    equal(style.popupText.textColor[2], 0.2)
    assert(Model.ApplyTheme(profile, "warcraftBrown"))
    assert(Model.ApplyTheme(profile, "testAppearance"))
    equal(profile.popupText.textColor[2], 0.6)
    Model.Themes.testAppearance = nil
end)

check("an upgraded Glass profile consumes its previous bar opacity once on first exit", function()
    local _, _, profile = Model.Initialize({ profiles = { Default = {
        theme = "macos27", fontSize = 15, opacity = 0.39, opacityBeforeGlass = 0.28,
        popupOpacity = 0.81, popupText = { fontSize = 14 },
    } } }, "A")
    equal(profile.opacity, 0.39); equal(profile.popupOpacity, 0.81); equal(profile.popupText.fontSize, 14)
    assert(Model.ApplyTheme(profile, "macosx"))
    equal(profile.opacity, 0.28); equal(profile.popupOpacity, 0.90)
    equal(profile.opacityBeforeGlass, nil)
    assert(Model.ApplyTheme(profile, "macos27"))
    equal(profile.opacity, 0.39); equal(profile.fontSize, 15); equal(profile.popupText.fontSize, 14)
    assert(Model.ApplyTheme(profile, "system7"))
    equal(profile.opacity, 0.7); equal(profile.popupText.fontSize, 0)
end)

check("a new character keeps an existing shared appearance and custom profiles", function()
    local db, character, profile = Model.Initialize(nil, "A")
    profile.theme, profile.opacity = "macos8", 0.35
    profile.popupOpacity = 0.81
    profile.textColor = { 0.2, 0.3, 0.4, 1 }
    local custom = assert(Model.CreateProfile(db, "Night", "Default"))
    equal(custom.popupOpacity, 0.81)
    custom.popupOpacity = 0.29
    custom.font, custom.textShadow = "Custom\\Regular.ttf", false
    assert(Model.SetProfile(db, "A", "Night"))
    local instance = Model.AddWidget(db, "A", "time", { zone = "utc" }, { bar = "bottom", alignment = "center" })
    instance.enabled = false
    local widgets, settings, colors = character.widgets, instance.settings, profile.textColor
    local _, newCharacter, newProfile = Model.Initialize(db, "B")
    equal(newCharacter.profile, "Default"); equal(newProfile, profile)
    equal(profile.theme, "macos8"); equal(profile.opacity, 0.35)
    equal(profile.textColor, colors); equal(profile.textColor[2], 0.3)
    equal(db.profiles.Night, custom); equal(character.profile, "Night")
    equal(profile.popupOpacity, 0.81); equal(custom.popupOpacity, 0.29)
    equal(custom.font, "Custom\\Regular.ttf"); equal(custom.textShadow, false)
    equal(character.widgets[1], instance); equal(instance.settings, settings)
    equal(instance.enabled, false); equal(instance.bar, "bottom"); equal(instance.alignment, "center")
    equal(instance.settings.zone, "utc")
    assert(newCharacter.widgets ~= widgets and #newCharacter.widgets == 0)
end)

check("widget instances have stable IDs and deeply independent settings", function()
    local db = Model.Initialize(nil, "A")
    local defaults = { zone = "utc", nested = { value = 1 } }
    local one = Model.AddWidget(db, "A", "time", defaults)
    local two = Model.AddWidget(db, "A", "time", defaults)
    assert(one.id ~= two.id)
    one.settings.nested.value = 9
    equal(two.settings.nested.value, 1)
    equal(defaults.nested.value, 1)
    local savedID = two.id
    db = Model.Initialize(db, "A")
    equal(Model.GetWidget(db, "A", savedID).settings.zone, "utc")
    equal(Model.GetCharacter(db, "A").initializedTypes.time, true)
end)

check("removing all instances does not request default creation again", function()
    local db = Model.Initialize(nil, "A")
    local widget = Model.AddWidget(db, "A", "time")
    assert(Model.RemoveWidget(db, "A", widget.id))
    db = Model.Initialize(db, "A")
    equal(#Model.ListWidgets(db, "A"), 0)
    equal(Model.GetCharacter(db, "A").initializedTypes.time, true)
end)

check("reordering is bounded and moving renumbers both alignment groups", function()
    local db = Model.Initialize(nil, "A")
    local one = Model.AddWidget(db, "A", "time")
    local two = Model.AddWidget(db, "A", "time")
    local three = Model.AddWidget(db, "A", "time")
    assert(Model.ReorderWidget(db, "A", three.id, -1))
    local list = Model.ListWidgets(db, "A", "top", "right")
    equal(list[1], one)
    equal(list[2], three)
    equal(list[3], two)
    assert(Model.ReorderWidget(db, "A", one.id, -99))
    equal(one.order, 1)
    assert(Model.MoveWidget(db, "A", three.id, "bottom", "center", 1))
    equal(two.order, 2)
    equal(three.order, 1)
    equal(#Model.ListWidgets(db, "A", "bottom", "center"), 1)
    local four = Model.AddWidget(db, "A", "money", {}, { bar = "bottom", alignment = "center", order = 1 })
    equal(four.order, 1)
    equal(three.order, 2)
    assert(Model.RemoveWidget(db, "A", four.id))
    equal(three.order, 1)
end)

check("profile copies share no nested values and do not move character widgets", function()
    local db = Model.Initialize(nil, "A")
    local widget = Model.AddWidget(db, "A", "time")
    local sourceBackground = db.profiles.Default.background[1]
    local copy = assert(Model.CreateProfile(db, "  Night  ", "Default"))
    copy.background[1] = 0.2
    copy.placement = "both"
    equal(db.profiles.Default.background[1], sourceBackground)
    assert(Model.SetProfile(db, "A", "Night"))
    equal(Model.GetProfile(db, "A"), copy)
    equal(Model.GetWidget(db, "A", widget.id), widget)
    equal(Model.GetProfile(db, "B"), db.profiles.Default)
    assert(not Model.CreateProfile(db, "Night"))
    assert(not Model.CreateProfile(db, "Missing source", "missing"))
    assert(not Model.SetProfile(db, "A", "missing"))
    equal(Model.GetProfile(db, "A"), copy)
end)

check("load repairs invalid fields and sparse widgets without losing unavailable types", function()
    local saved = {
        profiles = { Default = { height = 1000, opacity = -1, fontSize = 0 / 0,
            background = { -1, 2, 0.25 }, placement = "somewhere", customField = "preserved" } },
        characters = { A = { profile = "missing", widgets = {
            [1] = { id = "w1", type = "disabled-addon", settings = { token = 5 }, bar = "bottom", enabled = false },
            [3] = { id = "w1", type = "time", order = 7 },
            [5] = { type = "other-addon", alignment = "left", order = math.huge },
        } } },
    }
    local db, character, profile = Model.Initialize(saved, "A")
    equal(profile.height, 96)
    equal(profile.opacity, 0)
    equal(profile.fontSize, 12)
    equal(profile.background[1], 0)
    equal(profile.background[2], 1)
    equal(profile.background[4], 1)
    equal(profile.customField, "preserved")
    equal(character.profile, "Default")
    equal(#character.widgets, 3)
    equal(Model.GetWidget(db, "A", "w1").settings.token, 5)
    equal(Model.GetWidget(db, "A", "w1").enabled, false)
    equal(#Model.ListWidgets(db, "A"), 3)
    equal(character.initializedTypes["disabled-addon"], true)
    equal(character.initializedTypes.time, true)
    local seen = {}
    for _, widget in ipairs(character.widgets) do assert(not seen[widget.id]); seen[widget.id] = true end
    local widget = Model.AddWidget(db, "A", "new-addon")
    assert(not seen[widget.id])
end)

check("invalid operations preserve the existing layout", function()
    local db = Model.Initialize(nil, "A")
    local widget = Model.AddWidget(db, "A", "time")
    assert(not Model.MoveWidget(db, "A", widget.id, "floating", "left"))
    equal(widget.bar, "top")
    equal(widget.alignment, "right")
    assert(not Model.RemoveWidget(db, "A", "missing"))
    assert(not Model.AddWidget(db, "A", ""))
    equal(#Model.ListWidgets(db, "A"), 1)
end)

check("oversized saved IDs do not corrupt allocation of new instance IDs", function()
    local db = Model.Initialize({ characters = { A = { widgets = {
        { id = "w99999999999999999999999999", type = "time" },
    } } } }, "A")
    local first = Model.AddWidget(db, "A", "time")
    local second = Model.AddWidget(db, "A", "time")
    equal(first.id, "w1")
    equal(second.id, "w2")
end)

check("newer saved schemas are rejected without mutating the saved table", function()
    local saved = { schemaVersion = 42, profiles = "future format" }
    local db, _, _, reason = Model.Initialize(saved, "A")
    equal(db, nil)
    assert(reason:match("newer"))
    equal(saved.schemaVersion, 42)
    equal(saved.profiles, "future format")
end)

check("old saved appearance gains menu and corner preferences while retiring outline flags", function()
    local saved = { profiles = { Default = {
        font = "Interface\\AddOns\\MyFonts\\Custom.ttf", fontFlags = "THICKOUTLINE,MONOCHROME",
        placement = "both", fontSize = 18,
    } } }
    local db, _, profile = Model.Initialize(saved, "A")
    equal(profile.placement, "both")
    equal(profile.fontSize, 18)
    equal(profile.font, "Interface\\AddOns\\MyFonts\\Custom.ttf")
    equal(profile.fontFlags, "")
    equal(profile.fontStyle, "regular")
    equal(profile.coreMenuBar, "both")
    equal(profile.roundedCorners, true)
    assert(type(db.customFonts) == "table")
end)

check("menu placement real face style and explicit square corners persist per profile", function()
    for _, placement in ipairs({ "top", "bottom", "both" }) do
        local saved = { profiles = { Default = { coreMenuBar = placement,
            fontStyle = "bolditalic", roundedCorners = false } } }
        local _, _, profile = Model.Initialize(saved, "A")
        equal(profile.coreMenuBar, placement)
        equal(profile.fontStyle, "bolditalic")
        equal(profile.roundedCorners, false)
    end
    local _, _, repaired = Model.Initialize({ profiles = { Default = {
        coreMenuBar = "somewhere", fontStyle = "outline", fontFlags = "OUTLINE",
    } }, customFonts = "invalid" }, "A")
    equal(repaired.coreMenuBar, "both")
    equal(repaired.fontStyle, "regular")
    equal(repaired.fontFlags, "")
end)

check("custom font face records remain shared and are retained across profile changes", function()
    local saved = { customFonts = { ["Interface\\Fonts\\Regular.ttf"] = {
        name = "Example", regular = "Interface\\Fonts\\Regular.ttf", bold = "Interface\\Fonts\\Bold.ttf",
        italic = "Interface\\Fonts\\Italic.ttf", bolditalic = "Interface\\Fonts\\BoldItalic.ttf",
    } } }
    local db = Model.Initialize(saved, "A")
    local fonts = db.customFonts
    local profile = assert(Model.CreateProfile(db, "Other", "Default"))
    profile.fontStyle = "bold"
    assert(Model.SetProfile(db, "A", "Other"))
    Model.Initialize(db, "B")
    equal(db.customFonts, fonts)
    equal(fonts["Interface\\Fonts\\Regular.ttf"].bolditalic, "Interface\\Fonts\\BoldItalic.ttf")
    equal(Model.GetProfile(db, "A").fontStyle, "bold")
    equal(Model.GetProfile(db, "B").fontStyle, "regular")
end)

check("legacy rule thickness migrates independently without overwriting explicit new choices", function()
    local _, _, legacy = Model.Initialize({ profiles = { Default = { lineSize = 3 } } }, "A")
    equal(legacy.topLineSize, 3)
    equal(legacy.bottomLineSize, 3)
    local _, _, mixed = Model.Initialize({ profiles = { Default = {
        lineSize = 4, topLineSize = 0,
    } } }, "A")
    equal(mixed.topLineSize, 0)
    equal(mixed.bottomLineSize, 4)
    local _, _, explicit = Model.Initialize({ profiles = { Default = {
        lineSize = 6, topLineSize = 2, bottomLineSize = 0,
    } } }, "A")
    equal(explicit.topLineSize, 2)
    equal(explicit.bottomLineSize, 0)
end)

check("separate rule sizes are bounded and chosen Platinum style survives reload", function()
    local db, _, profile = Model.Initialize({ profiles = { Default = {
        theme = "macos8", topLineSize = 50, bottomLineSize = -4,
    } } }, "A")
    equal(profile.theme, "macos8")
    equal(profile.topLineSize, 6)
    equal(profile.bottomLineSize, 0)
    Model.Initialize(db, "A")
    equal(profile.theme, "macos8")
    equal(profile.topLineSize, 6)
    equal(profile.bottomLineSize, 0)
    local _, _, unknown = Model.Initialize({ profiles = { Default = { theme = "unknown" } } }, "A")
    equal(unknown.theme, "system7")
end)

check("a new bar style uses its own type and opacity while preserving layout and widget settings", function()
    local db, character, profile = Model.Initialize(nil, "A")
    local widget = Model.AddWidget(db, "A", "time", { zone = "utc" }, { bar = "bottom", alignment = "center" })
    profile.placement, profile.coreMenuBar = "both", "bottom"
    profile.height, profile.padding, profile.spacing = 42, 17, 25
    profile.font, profile.fontStyle, profile.fontSize = "Custom\\Regular.ttf", "italic", 20
    profile.opacity, profile.roundedCorners = 0.35, false
    assert(Model.ApplyTheme(profile, "macos8"))
    equal(profile.theme, "macos8")
    equal(profile.placement, "both"); equal(profile.coreMenuBar, "bottom")
    equal(profile.height, 42); equal(profile.padding, 17); equal(profile.spacing, 25)
    equal(profile.font, "Fonts\\FRIZQT__.TTF"); equal(profile.fontStyle, "regular"); equal(profile.fontSize, 12)
    equal(profile.opacity, 0.7); equal(profile.roundedCorners, true)
    equal(character.widgets[1], widget)
    equal(widget.bar, "bottom"); equal(widget.alignment, "center"); equal(widget.settings.zone, "utc")
    equal(profile.bottomLineSize, 1)
    assert(Model.ApplyTheme(profile, "system7"))
    equal(profile.bottomLineSize, 1)
    equal(profile.font, "Fonts\\FRIZQT__.TTF")
    equal(profile.fontStyle, "regular"); equal(profile.opacity, 0.7)
    equal(profile.textShadow, false)
end)

check("theme values copy independently and an invalid theme leaves appearance intact", function()
    local first, second = Model.DeepCopy(Model.DefaultProfile), Model.DeepCopy(Model.DefaultProfile)
    assert(Model.ApplyTheme(first, "macos8"))
    assert(Model.ApplyTheme(second, "macos8"))
    first.background[1] = 0.1
    equal(second.background[1], 0.87)
    equal(Model.Themes.macos8.background[1], 0.87)
    local previousBackground = first.background
    assert(not Model.ApplyTheme(first, "missing"))
    equal(first.theme, "macos8")
    equal(first.background, previousBackground)
end)

check("ID repair reserves later maximum IDs and wraps without stealing saved instances", function()
    local db, character = Model.Initialize({ characters = { A = { nextWidgetID = 2147483647, widgets = {
        { type = "time" }, { id = "w2147483647", type = "time", settings = { marker = true } },
        { id = "w1", type = "time" }, { id = "w1", type = "time" },
    } } } }, "A")
    equal(character.widgets[1].id, "w2")
    equal(character.widgets[2].id, "w2147483647")
    equal(character.widgets[3].id, "w1")
    equal(character.widgets[4].id, "w3")
    equal(Model.GetWidget(db, "A", "w2147483647").settings.marker, true)
    character.nextWidgetID = 2147483647
    equal(Model.AddWidget(db, "A", "time").id, "w4")
    Model.Initialize(db, "A")
    equal(Model.GetWidget(db, "A", "w2147483647").settings.marker, true)
end)

check("allocation at the final ID wraps to a free integer on the next add", function()
    local db, character = Model.Initialize(nil, "A")
    character.nextWidgetID = 2147483647
    equal(Model.AddWidget(db, "A", "time").id, "w2147483647")
    equal(Model.AddWidget(db, "A", "time").id, "w1")
    equal(character.nextWidgetID, 2)
end)

check("unrecognized saved roots and schema versions are rejected before any mutation", function()
    for _, saved in ipairs({ false, "unrecognized", 9 }) do
        local db, _, _, reason = Model.Initialize(saved, "A")
        equal(db, nil)
        assert(reason:match("preserved"))
    end
    for _, version in ipairs({ "1", false, 0 / 0, math.huge, -1, 0.5 }) do
        local saved = { schemaVersion = version, profiles = "leave intact" }
        local db, _, _, reason = Model.Initialize(saved, "A")
        equal(db, nil)
        assert(reason:match("preserved"))
        equal(saved.profiles, "leave intact")
        assert(saved.characters == nil)
        if type(version) ~= "number" or version == version then equal(saved.schemaVersion, version) end
    end
    equal(Model.Initialize({ schemaVersion = 0 }, "A").schemaVersion, 1)
end)

check("legacy character migration copies full layouts without deleting or sharing their mutable state", function()
    local oldKey, newKey = "First - Old Realm", "guid:Player-123-ABC"
    local db, legacy = Model.Initialize(nil, oldKey)
    local instance = Model.AddWidget(db, oldKey, "example", { chosen = 9, nested = { colour = "blue" } })
    legacy.future = { untouched = true }
    local oldWidget = legacy.widgets[1]
    local loaded, current = Model.Initialize(db, newKey, { "missing", oldKey })
    equal(loaded, db); equal(db.characters[oldKey], legacy)
    assert(current ~= legacy and current.widgets[1] ~= oldWidget)
    equal(current.widgets[1].id, instance.id); equal(current.widgets[1].settings.chosen, 9)
    current.widgets[1].settings.nested.colour = "green"
    equal(oldWidget.settings.nested.colour, "blue"); equal(current.future.untouched, true)
    current.widgets[1].settings.chosen = 11
    equal(Model.Initialize(db, newKey, { oldKey }).characters[newKey].widgets[1].settings.chosen, 11)
end)
check("legacy character hints cannot mutate a future saved schema", function()
    local original = { widgets = { { id = "w1", settings = { chosen = 9 } } } }
    local saved = { schemaVersion = 999, characters = { ["First - Realm"] = original } }
    local db = Model.Initialize(saved, "guid:Player-123-ABC", { "First - Realm" })
    equal(db, nil); equal(saved.characters["guid:Player-123-ABC"], nil)
    equal(saved.characters["First - Realm"], original); equal(saved.schemaVersion, 999)
end)

check("reapplying the current style refreshes its skin and retains its saved text and opacity through reload", function()
    local db, character, profile = Model.Initialize(nil, "A")
    profile.theme, profile.background, profile.texture = "system7", { 0.86, 0.86, 0.86, 1 }, "dither"
    profile.topLineSize, profile.bottomLineSize = 3, 2
    profile.textColor, profile.textShadow = { 0.18, 0.27, 0.42, 1 }, true
    profile.font, profile.fontStyle, profile.fontSize = "Fonts\\MORPHEUS.TTF", "regular", 18
    profile.height, profile.opacity, profile.placement, profile.coreMenuBar = 32, 0.37, "both", "bottom"
    profile.padding, profile.spacing = 17, 22
    local instance = Model.AddWidget(db, "A", "time", { zone = "utc" }, { bar = "bottom", alignment = "center" })
    instance.enabled = false
    Model.Initialize(db, "A")
    equal(profile.background[1], 0.86); equal(profile.texture, "dither")
    equal(profile.font, "Fonts\\MORPHEUS.TTF"); equal(profile.topLineSize, 3); equal(profile.bottomLineSize, 2)
    assert(Model.ApplyTheme(profile, "system7"))
    equal(profile.theme, "system7"); equal(profile.texture, "solid")
    for index = 1, 4 do equal(profile.background[index], 1) end
    for index, component in ipairs({ 0.18, 0.27, 0.42 }) do
        equal(profile.textColor[index], component); equal(profile.bottomLine[index], 0)
    end
    equal(profile.bottomLine[4], 1); equal(profile.topLineSize, 0); equal(profile.bottomLineSize, 1)
    equal(profile.font, "Fonts\\MORPHEUS.TTF"); equal(profile.fontStyle, "regular")
    equal(profile.textShadow, true); equal(profile.roundedCorners, true)
    equal(profile.height, 32); equal(profile.fontSize, 18); equal(profile.opacity, 0.37)
    equal(profile.placement, "both"); equal(profile.coreMenuBar, "bottom")
    equal(profile.padding, 17); equal(profile.spacing, 22)
    equal(character.widgets[1], instance); equal(instance.enabled, false)
    equal(instance.bar, "bottom"); equal(instance.alignment, "center"); equal(instance.settings.zone, "utc")
    local _, reloadedCharacter, reloaded = Model.Initialize(Model.DeepCopy(db), "A")
    equal(reloaded.theme, "system7"); equal(reloaded.texture, "solid"); equal(reloaded.background[1], 1)
    equal(reloaded.topLineSize, 0); equal(reloaded.bottomLineSize, 1)
    equal(reloaded.font, "Fonts\\MORPHEUS.TTF"); equal(reloaded.fontSize, 18); equal(reloaded.opacity, 0.37)
    equal(reloadedCharacter.widgets[1].settings.zone, "utc"); equal(reloadedCharacter.widgets[1].enabled, false)
end)

print(string.format("%d model tests passed", passed))
