local sourceDirectory = dofile((REPO_ROOT or ".") .. "/tests/source_paths.lua")
-- Real first-party TOCs and lifecycle. This counts native-shaped allocations;
-- it does not emulate WoW's allocator, renderer, combat restrictions or taint.
local root = REPO_ROOT or "."
local providers = { "ammo", "currency", "durability", "eyes", "location", "mail", "network",
    "performance", "reputation", "social", "time", "volume", "xp" }
local addons, repositories = {}, {}
local function exists(path)
    local file = io.open(path, "rb"); if not file then return false end
    file:close(); return true
end
for _, id in ipairs(providers) do
    local name = id == "xp" and "XP" or id:sub(1, 1):upper() .. id:sub(2)
    addons[id] = "Menubar_" .. name
    repositories[id] = _G["MENUBAR_" .. id:upper() .. "_ROOT"] or root
    if not exists(sourceDirectory(repositories[id], addons[id]) .. "/" .. addons[id] .. ".toc") then
        print("SKIP first-party retention integration: supply all thirteen provider repositories; missing " .. id)
        return
    end
end
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function loadAddon(repository, addon)
    local namespace = {}
    for line in io.lines(sourceDirectory(repository, addon) .. "/" .. addon .. ".toc") do
        local file = line:match("^%s*(.-)%s*$")
        if file:match("%.lua$") then assert(loadfile(sourceDirectory(repository, addon) .. "/" .. file))(addon, namespace) end
    end
end

local function fixture(legacy)
    local Stub = dofile(root .. "/tests/wow_stub.lua"); Stub.Install()
    local f = { Stub = Stub, creates = {} }
    MenubarDB = nil
    UnitGUID = function() return "Player-Retention-123" end
    UnitName = function() return "Tester", "Surname" end
    GetUnitName = function() return "Tester Surname" end
    InCombatLockdown = function() return false end
    C_GameRules, BankFrame, C_Map, C_PvP, C_Item, C_Container, C_CurrencyInfo, C_Reputation = nil, nil, nil, nil, nil, nil, nil, nil
    GetFramerate = function() return 60 end
    UnitLevel = function() return 20 end
    UnitXP = function() return 250 end
    UnitXPMax = function() return 1000 end
    GetXPExhaustion = function() return 300 end
    IsResting = function() return true end
    GetRestState = function() return 1 end
    GetZoneText = function() return "Durotar" end
    GetSubZoneText = function() return "Valley" end
    UnitFactionGroup = function() return "Horde", "Horde" end
    HasNewMail = function() return false end
    BNGetNumFriends = function() return 0, 0 end
    BNConnected = function() return true end
    C_FriendList = { IsLegacyFriendSystemEnabled = function() return false end }
    C_BattleNet = {}
    FRIEND_TAB_FRIENDS = 1
    C_CVar = { GetCVar = function(name) return name == "Sound_MasterVolume" and "0.4" or "1" end }
    UIParent:SetSize(8192, 1080)
    local nativeCreateFrame = CreateFrame
    CreateFrame = function(...)
        local frame = nativeCreateFrame(...)
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:CanChangeProtectedState() return true end
        function frame:IsProtected() return false end
        function frame:IsMouseEnabled() return self.mouseEnabled == true end
        return frame
    end

    -- The verified bank/bag controller keeps this footer as a positive grid
    -- anchor, hides its coin children, and asks native layout to reclaim space.
    local bag = CreateFrame("Frame", "ContainerFrame1", UIParent)
    f.bag = bag
    bag.MoneyFrame = CreateFrame("Frame", "ContainerFrame1MoneyFrame", bag)
    bag.MoneyFrame:SetHeight(25)
    for _, key in ipairs({ "Border", "GoldButton", "SilverButton", "CopperButton" }) do
        bag.MoneyFrame[key] = CreateFrame("Button", nil, bag.MoneyFrame)
    end
    function bag:UpdateFrameSize() self:SetSize(180, 70 + self.MoneyFrame:GetHeight()) end
    function bag:UpdateItemLayout() self.itemBottom = self.MoneyFrame:GetHeight() + 4 end
    bag:UpdateFrameSize(); bag:UpdateItemLayout()
    ContainerFrameCombinedBags, MoneyFrame_UpdateMoney = nil, nil
    UpdateContainerFrameAnchors = function() end

    local manager = CreateFrame("Frame", "StatusTrackingBarManager", UIParent)
    local container = CreateFrame("Frame", nil, manager)
    local xp = CreateFrame("Frame", nil, container)
    xp:SetAlpha(0.75); xp:EnableMouse(true)
    xp.ExhaustionTick = CreateFrame("Frame", nil, xp)
    xp.ExhaustionTick:SetAlpha(0.81); xp.ExhaustionTick:EnableMouse(true)
    container.BarFrameTexture = container:CreateTexture(nil, "OVERLAY")
    container.BarFrameTexture:SetAlpha(0.63)
    container.HorizontalDividersPool = { EnumerateActive = function() return next, {} end }
    container.bars, manager.barContainers = { [1] = xp }, { container }
    StatusTrackingBarInfo = { BarsEnum = { Experience = 1 } }
    EditModeManagerFrame = nil
    f.xp = xp

    local social = CreateFrame("Button", "QuickJoinToastButton", UIParent)
    social:SetAlpha(0.8); social:EnableMouse(true)
    social.OnClick = function() end
    f.social = social
    loadAddon(root, "Menubar")
    f.host = Menubar
    if legacy then
        local database, character = MenubarModel.Initialize(nil, "Tester - Test Realm")
        for _, id in ipairs(providers) do character.initializedTypes[id] = true end
        local saved = MenubarModel.AddWidget(database, "Tester - Test Realm", "time", { zone = "utc" })
        character.originalMarker = "preserved legacy layout"
        f.legacy, f.legacyWidget, MenubarDB = character, saved, database
    end
    local register = f.host.RegisterWidgetType
    f.host.RegisterWidgetType = function(self, declaration)
        local id, create = declaration.id, declaration.create
        if create then
            declaration.create = function(widget, ...)
                f.creates[id] = (f.creates[id] or 0) + 1
                return create(widget, ...)
            end
        end
        return register(self, declaration)
    end
    for _, id in ipairs(providers) do loadAddon(repositories[id], addons[id]) end
    f.host:Start(); assert(f.host.ready)
    f.widgets = {}
    for _, widget in pairs(f.host.runtime) do
        assert(not widget.failed, widget.instance.type .. ": " .. tostring(widget.failed))
        f.widgets[widget.instance.type] = widget
    end
    function f:enable(widget, enabled)
        widget.instance.enabled = enabled; self.host:Rebuild()
        if enabled then equal(self.host.runtime[widget.id], widget); assert(not widget.failed)
        else equal(self.host.runtime[widget.id], nil); assert(not widget.frame:IsShown()) end
    end
    function f:refresh(widget) self.host:RefreshWidget(widget.id); assert(not widget.failed, tostring(widget.failed)) end
    function f:duplicate(widget)
        local instance = MenubarModel.AddWidget(self.host.db, self.host.characterKey, widget.instance.type,
            widget.settings, { bar = widget.instance.bar, alignment = widget.instance.alignment })
        self.host:Rebuild()
        return assert(self.host.runtime[instance.id])
    end
    if not legacy then
        f.widgets.currency.settings.hideBagMoney = true; f:refresh(f.widgets.currency)
        f.widgets.xp.settings.hideBlizzardXPBar = true; f:refresh(f.widgets.xp)
        -- Warm native Settings controls too; later counts concern only lifetime
        -- reuse, not the canvas's intentionally lazy first allocation.
        f.host.UI:OpenSettings(); SettingsPanel:Hide()
    end
    return f
end

local f = fixture()
for _, id in ipairs(providers) do
    check("retains the " .. id .. " view through twenty disable and enable cycles", function()
        local widget = assert(f.widgets[id]); equal(widget.definition.retainOnDisable, true)
        local frame, label, settings = widget.frame, widget.label, widget.settings
        local frames, textures, masks, creates = #f.Stub.frames, #f.Stub.textures, #f.Stub.masks, f.creates[id] or 0
        for _ = 1, 20 do f:enable(widget, false); f:enable(widget, true) end
        equal(widget.frame, frame); equal(widget.label, label); equal(widget.settings, settings)
        equal(#f.Stub.frames, frames); equal(#f.Stub.textures, textures); equal(#f.Stub.masks, masks)
        equal(f.creates[id] or 0, creates)
    end)
end

check("disabled Currency releases bag space and duplicates retain independent settings and requests", function()
    local current = fixture(); local first = current.widgets.currency; local second = current:duplicate(first)
    assert(first.settings ~= second.settings)
    second.settings.display = "gold"; current:refresh(second)
    equal(first.settings.display, "coins")
    equal(current.bag.MoneyFrame:GetHeight(), 1); assert(not current.bag.MoneyFrame.GoldButton:IsShown())
    current:enable(first, false); equal(current.bag.MoneyFrame:GetHeight(), 1)
    current:enable(second, false)
    equal(current.bag.MoneyFrame:GetHeight(), 25); equal(current.bag:GetHeight(), 95)
    assert(current.bag.MoneyFrame.GoldButton:IsShown())
    current:enable(first, true); equal(current.bag.MoneyFrame:GetHeight(), 1)
    equal(current.bag:GetHeight(), 71); equal(second.settings.display, "gold")
end)

check("disabled XP restores native visibility and input after the last independent request", function()
    local current = fixture(); local first = current.widgets.xp; local second = current:duplicate(first)
    equal(current.xp:GetAlpha(), 0); equal(current.xp:IsMouseEnabled(), false)
    current:enable(first, false); equal(current.xp:GetAlpha(), 0)
    current:enable(second, false)
    equal(current.xp:GetAlpha(), 0.75); equal(current.xp:IsMouseEnabled(), true)
    equal(current.xp.ExhaustionTick:GetAlpha(), 0.81)
    current:enable(first, true); equal(current.xp:GetAlpha(), 0)
end)

check("disabled Social restores the native chat button after the last independent request", function()
    local current = fixture(); local first = current.widgets.social; local second = current:duplicate(first)
    equal(current.social:GetAlpha(), 0); equal(current.social:IsMouseEnabled(), false)
    current:enable(first, false); equal(current.social:GetAlpha(), 0)
    current:enable(second, false)
    equal(current.social:GetAlpha(), 0.8); equal(current.social:IsMouseEnabled(), true)
    current:enable(first, true); equal(current.social:GetAlpha(), 0)
end)

check("retained first-party views respect GUID migration without modifying the legacy record", function()
    local current = fixture(true); local host = current.host; local widget = assert(current.widgets.time)
    equal(host.characterKey, "guid:Player-Retention-123")
    equal(host.db.characters["Tester - Test Realm"], current.legacy)
    local character = host.db.characters[host.characterKey]
    assert(character ~= current.legacy and widget.instance ~= current.legacyWidget)
    equal(character.originalMarker, "preserved legacy layout"); equal(widget.settings.zone, "utc")
    widget.settings.zone = "local"; current:refresh(widget)
    local frame = widget.frame
    for _ = 1, 20 do current:enable(widget, false); current:enable(widget, true) end
    equal(widget.frame, frame); equal(widget.settings.zone, "local")
    equal(current.legacyWidget.settings.zone, "utc")
    equal(current.legacy.originalMarker, "preserved legacy layout")
end)

print(passed .. " first-party retention tests passed")
