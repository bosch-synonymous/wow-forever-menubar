local sourceDirectory = dofile((REPO_ROOT or ".") .. "/tests/source_paths.lua")
-- Factory preferences are deliberately generic: no player/account IDs or saved
-- instance IDs. Exercise the real loader/model boundary, not declaration tables alone.
local root = REPO_ROOT or "."
local expected = {
    profile = {
        fontSize = 12,
        opacity = 0.9,
        popupOpacity = 0.9,
        popupText = { font = "theme", fontStyle = "regular", fontSize = 14, useCustomColor = false },
        roundedCorners = false,
        spacing = 12,
        background = { 1, 1, 1, 1 },
        theme = "warcraftBrown",
        texture = "theme",
        bottomLineSize = 4,
        fontStyle = "regular",
        topLine = { 0.48, 0.36, 0.18, 1 },
        font = "Fonts\\FRIZQT__.TTF",
        coreMenuBar = "both",
        bottomLine = { 1, 1, 1, 1 },
        topLineSize = 1,
        fontFlags = "",
        placement = "top",
        height = 24,
        padding = 8,
        textShadow = true,
        textColor = { 1, 0.82, 0, 1 },
    },
    widgets = {
        {
            enabled = true,
            type = "performance",
            settings = {
                display = "fps",
                memoryInKB = false,
                usageMetric = "memory",
                diagnostics = false,
            },
            order = 1,
            alignment = "right",
            bar = "top",
            sidebarOrder = 1,
        },
        {
            enabled = true,
            type = "network",
            settings = {
                showLabel = false,
                showThroughput = false,
                latency = "world",
            },
            order = 2,
            alignment = "right",
            bar = "top",
            sidebarOrder = 2,
        },
        {
            enabled = true,
            type = "mail",
            settings = {},
            order = 3,
            alignment = "right",
            bar = "top",
            sidebarOrder = 3,
        },
        {
            enabled = true,
            type = "ammo",
            settings = {
                display = "icon",
                selectedID = 0,
            },
            order = 4,
            alignment = "right",
            bar = "top",
            sidebarOrder = 4,
        },
        {
            enabled = true,
            type = "durability",
            settings = {
                hideDefaultWarnings = true,
                customThresholds = true,
                warningPercent = 20,
                criticalPercent = 0,
            },
            order = 5,
            alignment = "right",
            bar = "top",
            sidebarOrder = 5,
        },
        {
            enabled = true,
            type = "social",
            settings = {
                showLabel = false,
                hideChatButton = true,
                showCount = true,
            },
            order = 6,
            alignment = "right",
            bar = "top",
            sidebarOrder = 6,
        },
        {
            enabled = true,
            type = "eyes",
            settings = {
                appearance = "smooth",
                followCursor = true,
                glowTrails = true,
                iris = "blue",
                size = 16,
            },
            order = 1,
            alignment = "center",
            bar = "top",
            sidebarOrder = 7,
        },
        {
            enabled = true,
            type = "location",
            settings = {
                name = "zone",
                decimals = 1,
                colorStatus = true,
                showCoordinates = true,
                showStatus = true,
            },
            order = 1,
            alignment = "left",
            bar = "top",
            sidebarOrder = 8,
        },
        {
            enabled = true,
            type = "reputation",
            settings = {
                hideBlizzardReputationBar = true,
                showName = true,
                progress = "none",
                showStanding = false,
                gaugeWidth = 160,
                gaugeStyle = "theme",
                presentation = "gauge",
                factionID = 0,
            },
            order = 2,
            alignment = "left",
            bar = "top",
            sidebarOrder = 9,
        },
        {
            enabled = true,
            type = "currency",
            settings = {
                display = "coins",
                showLabel = false,
                hideBagMoney = false,
                currencyID = 0,
            },
            order = 7,
            alignment = "right",
            bar = "top",
            sidebarOrder = 10,
        },
        {
            enabled = true,
            type = "volume",
            settings = {
                orientation = "horizontal",
                wheelStep = 5,
                showPercent = true,
            },
            order = 8,
            alignment = "right",
            bar = "top",
            sidebarOrder = 11,
        },
        {
            enabled = true,
            type = "xp",
            settings = {
                hideBlizzardXPBar = true,
                showLabel = false,
                display = "none",
                gaugeWidth = 160,
                gaugeStyle = "theme",
                presentation = "gauge",
                showLevel = true,
            },
            order = 3,
            alignment = "left",
            bar = "top",
            sidebarOrder = 12,
        },
        {
            enabled = true,
            type = "time",
            settings = {
                format = "24h",
                showLabel = false,
                zone = "local",
            },
            order = 9,
            alignment = "right",
            bar = "top",
            sidebarOrder = 13,
        },
    },
}

local expectedByType = {}
for _, widget in ipairs(expected.widgets) do
    assert(not expectedByType[widget.type], "Expected widget types must be unique")
    expectedByType[widget.type] = widget
end

local providers = { "ammo", "currency", "durability", "eyes", "location", "mail", "network",
    "performance", "reputation", "social", "time", "volume", "xp" }
local repositories, addons = {}, {}
local function exists(path)
    local file = io.open(path, "rb")
    if not file then return false end
    file:close(); return true
end
for _, id in ipairs(providers) do
    addons[id] = "Menubar_" .. (id == "xp" and "XP" or id:sub(1, 1):upper() .. id:sub(2))
    repositories[id] = _G["MENUBAR_" .. id:upper() .. "_ROOT"] or root
    if not exists(sourceDirectory(repositories[id], addons[id]) .. "/" .. addons[id] .. ".toc") then
        print("SKIP production-default integration: supply all thirteen provider roots; missing " .. id)
        return
    end
end
local passed = 0
local function equal(actual, wanted, context)
    assert(actual == wanted, (context or "unexpected value") .. ": expected " .. tostring(wanted) .. ", got " .. tostring(actual))
end
local function same(actual, wanted, context)
    if type(wanted) ~= "table" then equal(actual, wanted, context); return end
    assert(type(actual) == "table", context or "expected table")
    for key, value in pairs(wanted) do same(actual[key], value, (context or "value") .. "." .. tostring(key)) end
    for key in pairs(actual) do assert(wanted[key] ~= nil, (context or "value") .. ": unexpected key " .. tostring(key)) end
end
local function contains(actual, wanted, context)
    for key, value in pairs(wanted) do same(actual[key], value, (context or "value") .. "." .. key) end
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function loadAddon(repository, addon)
    local namespace = {}
    for line in io.lines(sourceDirectory(repository, addon) .. "/" .. addon .. ".toc") do
        local name = line:match("^%s*(.-)%s*$")
        if name:match("%.lua$") then assert(loadfile(sourceDirectory(repository, addon) .. "/" .. name))(addon, namespace) end
    end
end
local characterKey = "guid:Player-Defaults-Fixture"
local function fixture(saved)
    local Stub = dofile(root .. "/tests/wow_stub.lua"); Stub.Install()
    MenubarDB = nil
    UnitGUID = function() return "Player-Defaults-Fixture" end
    UnitName = function() return "Fixture" end
    GetUnitName = function() return "Fixture" end
    UIParent:SetSize(8192, 1080)
    loadAddon(root, "Menubar")
    if type(saved) == "function" then saved = saved(MenubarModel) end
    MenubarDB = saved
    for _, id in ipairs(providers) do loadAddon(repositories[id], addons[id]) end
    Menubar:Start(); assert(Menubar.ready, "The actual host must initialize")
    local f = { Stub = Stub, host = Menubar, db = Menubar.db }
    f.character = MenubarModel.GetCharacter(f.db, characterKey)
    f.profile = f.host:GetProfile()
    function f:control(caption)
        for _, control in ipairs(self.host.UI.window.controls or {}) do if control.caption == caption then return control end end
        error("Missing settings control: " .. caption, 0)
    end
    return f
end
local function widgetsByType(character)
    local result = {}
    for _, instance in ipairs(character.widgets) do assert(not result[instance.type]); result[instance.type] = instance end
    return result
end
local function assertInitialLayout(f, character)
    equal(#character.widgets, #expected.widgets, "number of initial widgets")
    for index, wanted in ipairs(expected.widgets) do
        local instance = assert(character.widgets[index])
        equal(instance.type, wanted.type, "sidebar position " .. index)
        equal(instance.enabled, wanted.enabled, wanted.type .. " enabled")
        equal(instance.bar, wanted.bar, wanted.type .. " bar")
        equal(instance.alignment, wanted.alignment, wanted.type .. " alignment")
        equal(instance.order, wanted.order, wanted.type .. " group order")
        contains(instance.settings, wanted.settings, wanted.type .. " production settings")
        same(instance.settings, f.host.types[wanted.type].defaults, wanted.type .. " complete defaults")
        assert(instance.settings ~= f.host.types[wanted.type].defaults, "Instance settings must be independent")
        equal(character.initializedTypes[wanted.type], true)
    end
    local wantedGroups = { left = { "location", "reputation", "xp" }, center = { "eyes" },
        right = { "performance", "network", "mail", "ammo", "durability", "social", "currency", "volume", "time" } }
    for alignment, wanted in pairs(wantedGroups) do
        local actual = MenubarModel.ListWidgets(f.db, f.host.characterKey, "top", alignment)
        equal(#actual, #wanted)
        for index, id in ipairs(wanted) do equal(actual[index].type, id, alignment .. " visual position " .. index) end
    end
end

check("a fresh database loads the complete appearance and ordered settings for all thirteen providers", function()
    local f = fixture()
    contains(f.profile, expected.profile, "fresh appearance")
    assertInitialLayout(f, f.character)
    equal(widgetsByType(f.character).reputation.settings.factionID, 0, "Reputation follows the game's watched faction")
    assert(f.profile ~= MenubarModel.DefaultProfile and f.profile.background ~= MenubarModel.DefaultProfile.background)
    for _, widget in pairs(f.host.runtime) do assert(not widget.failed, widget.instance.type .. ": " .. tostring(widget.failed)) end
end)

check("fresh character settings are independent while appearance keeps its intended account scope", function()
    local f = fixture()
    local first = widgetsByType(f.character)
    local otherKey = "guid:Player-Defaults-Other"
    f.host.characterKey = otherKey
    local other = MenubarModel.GetCharacter(f.db, otherKey)
    f.host:EnsureDefaults(); f.host:Rebuild()
    equal(f.host:GetProfile(), f.profile, "Characters use the existing shared Default appearance")
    assertInitialLayout(f, other)
    for _, instance in ipairs(other.widgets) do assert(instance.settings ~= first[instance.type].settings) end
    local second = widgetsByType(other)
    second.ammo.settings.display = "name"
    equal(first.ammo.settings.display, "icon"); equal(f.host.types.ammo.defaults.display, "icon")
    local _, _, independentProfile = MenubarModel.Initialize(nil, "guid:Player-Defaults-Independent")
    assert(independentProfile ~= f.profile and independentProfile.background ~= f.profile.background)
    f.profile.background[1] = 0.13
    equal(independentProfile.background[1], expected.profile.background[1])
    equal(MenubarModel.DefaultProfile.background[1], expected.profile.background[1])
end)

check("saved reputation instances keep native-bar preferences while only the missing legacy field is backfilled", function()
    local wanted, schema
    local f = fixture(function(Model)
        local db, character, profile = Model.Initialize(nil, characterKey)
        profile.placement = "both"
        for _, id in ipairs(providers) do character.initializedTypes[id] = true end
        for index, placement in ipairs({
            { bar = "bottom", alignment = "left" },
            { bar = "top", alignment = "right" },
            { bar = "bottom", alignment = "center" },
        }) do
            local settings = Model.DeepCopy(expectedByType.reputation.settings)
            settings.factionID = 70 + index
            settings.futureReputationSetting = { marker = "saved-" .. index, value = false }
            settings.hideBlizzardReputationBar = index == 3
            if index == 1 then settings.hideBlizzardReputationBar = nil end
            local instance = Model.AddWidget(db, characterKey, "reputation", settings, placement)
            instance.enabled = index ~= 2
        end
        schema, wanted = db.schemaVersion, Model.DeepCopy(db)
        -- This one new saved value preserves the old implicit behavior. The
        -- explicit false/true cases and all unrelated saved fields must survive.
        wanted.characters[characterKey].widgets[1].settings.hideBlizzardReputationBar = false
        return db
    end)
    local function assertPreferences(current, phase)
        equal(current.db.schemaVersion, schema, phase .. " schema")
        equal(#current.character.widgets, 3, phase .. " instance count")
        for index, expectedInstance in ipairs(wanted.characters[characterKey].widgets) do
            local instance = assert(MenubarModel.GetWidget(current.db, characterKey, expectedInstance.id))
            equal(instance.settings.hideBlizzardReputationBar, index == 3, phase .. " preference " .. index)
            equal(instance.settings.factionID, expectedInstance.settings.factionID, phase .. " faction " .. index)
            same(instance.settings.futureReputationSetting, expectedInstance.settings.futureReputationSetting,
                phase .. " unknown field " .. index)
            equal(instance.bar, expectedInstance.bar, phase .. " bar " .. index)
            equal(instance.alignment, expectedInstance.alignment, phase .. " alignment " .. index)
            equal(instance.order, expectedInstance.order, phase .. " order " .. index)
            equal(instance.enabled, expectedInstance.enabled, phase .. " enabled " .. index)
        end
        same(current.db, wanted, phase .. " preserves everything except the missing field")
    end
    assertPreferences(f, "initial saved load")
    f.host:Rebuild()
    assertPreferences(f, "repeated rebuild")
    local reloaded = fixture(MenubarModel.DeepCopy(f.db))
    assertPreferences(reloaded, "reload-equivalent saved load")
end)

check("saved appearance widgets removals and unavailable providers survive the new factory choices and reload", function()
    local snapshot
    local f = fixture(function(Model)
        local db, character, profile = Model.Initialize(nil, characterKey)
        Model.ApplyTheme(profile, "system7")
        profile.opacity, profile.height, profile.placement, profile.coreMenuBar = 0.37, 31, "both", "bottom"
        profile.futureAppearance = { retained = true }
        db.futureRoot = { retained = true }
        for _, id in ipairs(providers) do character.initializedTypes[id] = true end
        Model.AddWidget(db, characterKey, "ammo", { selectedID = 12345, display = "name", futureSetting = false },
            { bar = "bottom", alignment = "left" })
        local xp = Model.AddWidget(db, characterKey, "xp", Model.DeepCopy(expectedByType.xp.settings),
            { bar = "bottom", alignment = "right" })
        xp.enabled, xp.settings.hideBlizzardXPBar = false, false
        for _, choice in ipairs({ { "performance", "diagnostics" }, { "network", "showLabel" }, { "currency", "hideBagMoney" } }) do
            local settings = Model.DeepCopy(expectedByType[choice[1]].settings)
            settings[choice[2]] = true -- Explicit previous preferences survive this factory refresh.
            Model.AddWidget(db, characterKey, choice[1], settings, { bar = "bottom", alignment = "center" })
        end
        Model.AddWidget(db, characterKey, "unavailable-example", { marker = 0, futureSetting = true },
            { bar = "top", alignment = "center" })
        snapshot = Model.DeepCopy(db)
        return db
    end)
    same(f.db, snapshot, "saved configuration")
    local original = f.db.profiles.Default
    f.host:EnsureDefaults(); f.host:Rebuild()
    same(f.db, snapshot, "repeated default seeding")
    equal(f.db.profiles.Default, original)
    equal(#f.character.widgets, #snapshot.characters[characterKey].widgets, "Deliberately removed defaults must not respawn")
    local reloaded = fixture(MenubarModel.DeepCopy(f.db))
    same(reloaded.db, snapshot, "reloaded configuration")
    local newKey = "guid:Player-Defaults-NewSavedAccount"
    reloaded.host.characterKey = newKey
    local newCharacter = MenubarModel.GetCharacter(reloaded.db, newKey)
    reloaded.host:EnsureDefaults(); reloaded.host:Rebuild()
    equal(reloaded.host:GetProfile(), reloaded.db.profiles.Default)
    equal(reloaded.host:GetProfile().theme, "system7")
    equal(reloaded.host:GetProfile().opacity, 0.37)
    equal(#newCharacter.widgets, #expected.widgets)
end)

check("explicit resets use factory preferences without replacing widget placement or character layout", function()
    local f = fixture()
    local instance = widgetsByType(f.character).durability
    MenubarModel.MoveWidget(f.db, characterKey, instance.id, "bottom", "center")
    instance.enabled = false
    instance.settings.hideDefaultWarnings, instance.settings.customThresholds = false, false
    instance.settings.warningPercent = 77
    local id, bar, alignment, order = instance.id, instance.bar, instance.alignment, instance.order
    f.host:Rebuild(); f.host.UI:OpenWidget(id)
    f:control("Reset this widget's settings"):Click()
    same(instance.settings, expectedByType.durability.settings, "reset durability settings")
    equal(instance.id, id); equal(instance.bar, bar); equal(instance.alignment, alignment); equal(instance.order, order)
    equal(instance.enabled, false)
    for _, choice in ipairs({ { "performance", "diagnostics" }, { "network", "showLabel" }, { "currency", "hideBagMoney" } }) do
        local changed = widgetsByType(f.character)[choice[1]]
        changed.settings[choice[2]] = true
        f.host.UI:OpenWidget(changed.id)
        f:control("Reset this widget's settings"):Click()
        same(changed.settings, expectedByType[choice[1]].settings, "reset " .. choice[1] .. " settings")
    end
    MenubarModel.ApplyTheme(f.profile, "macos27")
    f.profile.fontSize, f.profile.popupText.fontSize, f.profile.popupOpacity = 19, 23, 0.42
    MenubarModel.ApplyTheme(f.profile, "system7")
    f.profile.placement, f.profile.coreMenuBar, f.profile.opacity = "both", "bottom", 0.2
    local before = MenubarModel.DeepCopy(f.character.widgets)
    f.host:Rebuild(); f.host.UI:OpenSettings()
    f:control("Restore to defaults"):Click()
    local wanted = MenubarModel.DeepCopy(expected.profile)
    wanted.placement, wanted.coreMenuBar = "both", "bottom"
    contains(f.profile, wanted, "restored appearance")
    same(f.character.widgets, before, "appearance reset preserves character widgets")
    assert(MenubarModel.ApplyTheme(f.profile, "macos27"))
    equal(f.profile.fontSize, 12); equal(f.profile.popupText.fontSize, 0); equal(f.profile.popupOpacity, 0.9)
    equal(f.profile.opacity, 0.45)
    assert(MenubarModel.ApplyTheme(f.profile, "system7"))
    equal(f.profile.opacity, 0.7)
end)

print(passed .. " production-default integration tests passed")
