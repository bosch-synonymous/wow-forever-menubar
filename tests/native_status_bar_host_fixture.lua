-- Shared actual-host/native-shaped status-bar fixture.
local root = REPO_ROOT or "."
local core = MENUBAR_CORE_ROOT or root
local sourceDirectory = dofile(root .. "/tests/source_paths.lua")
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function loadAddon(repository, addon)
    for line in io.lines(sourceDirectory(repository, addon) .. "/" .. addon .. ".toc") do
        local file = line:match("^%s*(.-)%s*$")
        if file:match("%.lua$") then assert(loadfile(sourceDirectory(repository, addon) .. "/" .. file))(addon, {}) end
    end
end

local function fixture(kind)
    kind = kind or "xp"
    local isXP = kind == "xp"
    local settingKey = isXP and "hideBlizzardXPBar" or "hideBlizzardReputationBar"
    local Stub = dofile(core .. "/tests/wow_stub.lua")
    Stub.Install()
    local createFrame = CreateFrame
    CreateFrame = function(...)
        local frame = createFrame(...)
        function frame:UnregisterAllEvents() self.events = {} end
        return frame
    end
    MenubarDB = nil
    UnitLevel = function() return 20 end
    UnitXP = function() return 250 end
    UnitXPMax = function() return 1000 end
    GetXPExhaustion = function() return 300 end
    IsResting = function() return true end
    GetRestState = function() return 1 end
    InCombatLockdown = function() return false end
    StatusTrackingBarInfo = { BarsEnum = { Experience = 1, Reputation = 2 } }
    local watched = { id = 72, writes = 0 }
    C_Reputation = {
        GetWatchedFactionData = function() return { factionID = watched.id, name = "Stormwind", reaction = 5,
            currentStanding = 4500, currentReactionThreshold = 3000, nextReactionThreshold = 9000 } end,
        GetFactionDataByID = function(id) return { factionID = id, name = "Other faction", reaction = 5,
            currentStanding = 4500, currentReactionThreshold = 3000, nextReactionThreshold = 9000 } end,
        IsMajorFaction = function() return false end,
        IsFactionParagonForCurrentPlayer = function() return false end,
        SetWatchedFactionByID = function() watched.writes = watched.writes + 1; error("native watched faction must remain unchanged") end,
    }

    local borrowed = {}
    local function nativeFrame(parent, alpha, mouse)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetAlpha(alpha)
        frame:EnableMouse(mouse)
        function frame:IsMouseEnabled() return self.mouseEnabled end
        function frame:IsProtected() return false end
        function frame:CanChangeProtectedState() return true end
        frame.nativeShow, frame.nativeHide = frame.Show, frame.Hide
        -- No addon action should drive native managed visibility or parenting.
        frame.Hide = function() error("Addon must not Hide a borrowed native frame") end
        frame.SetParent = function() error("Addon must not reparent a borrowed native frame") end
        borrowed[#borrowed + 1] = { frame = frame, alpha = alpha, mouse = mouse }
        return frame
    end
    local manager = nativeFrame(UIParent, 0.83, false)
    StatusTrackingBarManager = manager
    local function container(alpha, active)
        local value = nativeFrame(manager, alpha, false)
        value.BarFrameTexture = value:CreateTexture(nil, "OVERLAY")
        value.BarFrameTexture:SetAlpha(0.63)
        value.divider = nativeFrame(value, 0.42, false)
        value.HorizontalDividersPool = {
            EnumerateActive = function() return next, { [value.divider] = true } end,
        }
        local xp = nativeFrame(value, 0.75, true)
        xp.ExhaustionTick = nativeFrame(xp, 0.81, true)
        local reputation = nativeFrame(value, 0.9, true)
        value.bars = { [1] = xp, [2] = reputation }
        value.shownBarIndex = active
        function value:GetShownBar() return self.bars[self.shownBarIndex] end
        if active == 1 then reputation.nativeHide(reputation) else xp.nativeHide(xp) end
        return value
    end
    local primary, secondary = container(0.72, 1), container(0.61, 2)
    manager.barContainers = { primary, secondary }
    local editMode = CreateFrame("Frame", nil, UIParent)
    editMode:Hide()
    function editMode:IsEditModeActive() return false end
    EditModeManagerFrame = editMode
    loadAddon(core, "Menubar")
    loadAddon(root, isXP and "Menubar_XP" or "Menubar_Reputation")
    Menubar:Start()
    local host = Menubar
    local _, initial = next(host.runtime)
    assert(initial and initial.instance.type == kind and not initial.failed, kind .. " should initialize")
    local function control(widgetID)
        local label
        for _, field in ipairs(host.types[kind].settings) do
            if field.key == settingKey then label = field.label; break end
        end
        assert(label, "XP native visibility setting is registered")
        host.UI:OpenWidget(widgetID)
        for _, candidate in ipairs(host.UI.window.controls) do
            if candidate.caption == label then return candidate end
        end
        error("Missing native XP setting control")
    end
    local function request(widget, enabled)
        local checkbox = control(widget.id)
        equal(checkbox:GetChecked(), widget.settings[settingKey] == true)
        if checkbox:GetChecked() ~= enabled then checkbox:Click() end
        equal(widget.settings[settingKey], enabled)
        assert(not widget.failed, tostring(widget.failed))
    end
    local function step(elapsed)
        for _, frame in ipairs(Stub.frames) do
            if frame:IsVisible() and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, elapsed) end
        end
    end
    local target, other = isXP and primary or secondary, isXP and secondary or primary
    local index, otherIndex = isXP and 1 or 2, isXP and 2 or 1
    local originalAlpha, otherAlpha = isXP and 0.75 or 0.9, isXP and 0.9 or 0.75
    local function shell()
        equal(manager:GetAlpha(), 0.83); equal(primary:GetAlpha(), 0.72); equal(secondary:GetAlpha(), 0.61)
        equal(other.bars[otherIndex]:GetAlpha(), otherAlpha); equal(other.bars[otherIndex]:IsMouseEnabled(), true)
        equal(other.BarFrameTexture:GetAlpha(), 0.63); equal(other.divider:GetAlpha(), 0.42)
        equal(watched.id, 72); equal(watched.writes, 0)
    end
    local function restored()
        shell(); equal(target.bars[index]:GetAlpha(), originalAlpha); equal(target.bars[index]:IsMouseEnabled(), true)
        if isXP then equal(target.bars[index].ExhaustionTick:IsMouseEnabled(), true) end
        equal(target.BarFrameTexture:GetAlpha(), 0.63); equal(target.divider:GetAlpha(), 0.42)
    end
    local function concealed()
        shell(); equal(target.bars[index]:GetAlpha(), 0); equal(target.bars[index]:IsMouseEnabled(), false)
        if isXP then equal(target.bars[index].ExhaustionTick:IsMouseEnabled(), false) end
        equal(target.BarFrameTexture:GetAlpha(), 0); equal(target.divider:GetAlpha(), 0)
    end
    return host, initial, request, step, concealed, restored, target, other, borrowed, watched
end

return fixture
