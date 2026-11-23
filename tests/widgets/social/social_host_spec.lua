local sourceDirectory = dofile((REPO_ROOT or ".") .. "/tests/source_paths.lua")
-- Real host lifecycle and native Social-button policy. Native C++ protections,
-- artwork and Social-window behavior still require an in-client check.
local root = REPO_ROOT or "."
local core = MENUBAR_CORE_ROOT or root
local file = io.open(core .. "/tests/wow_stub.lua", "rb")
if not file then print("SKIP Social host integration: restore Core in this clone or supply MENUBAR_CORE_ROOT."); return end
file:close()
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
        local name = line:match("^%s*(.-)%s*$")
        if name:match("%.lua$") then assert(loadfile(sourceDirectory(repository, addon) .. "/" .. name))(addon, namespace) end
    end
end
local function findItem(menu, text)
    for _, child in ipairs(menu.children or {}) do
        if child.text == text then return child end
        local result = findItem(child, text); if result then return result end
    end
end
local function fixture(options)
    options = options or {}
    local Stub = dofile(core .. "/tests/wow_stub.lua"); Stub.Install()
    local f = { Stub = Stub, combat = false, permission = true, clicks = 0, fallbackClicks = 0, shift = false,
        wowFriends = { { guid = "Player-1", connected = true }, { guid = "Player-2", connected = false } },
        bnFriends = { { bnetAccountID = 10, gameAccountInfo = { isOnline = true } },
            { bnetAccountID = 20, gameAccountInfo = { isOnline = false } } } }
    MenubarDB = nil
    f.secret = setmetatable({}, { __tostring = function() error("Restricted Social atlas formatted", 0) end })
    issecretvalue = function(value) return rawequal(value, f.secret) end
    InCombatLockdown = function() return f.combat end
    IsShiftKeyDown = function() return f.shift end
    BNGetNumFriends = function() return #f.bnFriends, 4 end
    BNConnected = function() return true end
    C_BattleNet = {
        GetFriendAccountInfo = function(index) return f.bnFriends[index] end,
        GetAccountInfoByID = function(id)
            for _, info in ipairs(f.bnFriends) do if info.bnetAccountID == id then return info end end
        end,
    }
    C_FriendList = {
        IsLegacyFriendSystemEnabled = function() return true end,
        GetNumOnlineFriends = function() return 3 end,
        GetNumFriends = function() return #f.wowFriends end,
        GetFriendInfoByIndex = function(index) return f.wowFriends[index] end,
    }
    Enum = { GameRule = { IngameFriendsListDisabled = 7 } }
    C_GameRules = { IsGameRuleActive = function() return f.rule == true end }
    FRIEND_TAB_FRIENDS = 1
    ToggleFriendsFrame = function(tab) equal(tab, 1); f.fallbackClicks = f.fallbackClicks + 1 end
    local nativeCreateFrame = CreateFrame
    CreateFrame = function(...)
        local frame = nativeCreateFrame(...)
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:IsMouseEnabled() return self.mouseEnabled == true end
        function frame:CanChangeProtectedState() return f.permission end
        if options.atlasReadback then
            local createTexture = frame.CreateTexture
            function frame:CreateTexture(...)
                local texture = createTexture(self, ...)
                local getAtlas = texture.GetAtlas
                function texture:GetAtlas()
                    local atlas = getAtlas(self)
                    return options.atlasReadback(atlas, f)
                end
                return texture
            end
        end
        return frame
    end
    local native = CreateFrame("Button", "QuickJoinToastButton", UIParent)
    f.native = native
    native:SetAlpha(0.8); native:EnableMouse(true); native:RegisterEvent("SOCIAL_QUEUE_UPDATE")
    native:SetScript("OnHide", function(self) self.nativeHideCalls = (self.nativeHideCalls or 0) + 1; self.queueCacheCleared = true end)
    native.FriendsButton = native:CreateTexture(); native.FriendsButton:SetAtlas("quickjoin-button-friendslist-up")
    native.QueueButton = native:CreateTexture(); native.QueueButton:SetAtlas("quickjoin-button-quickjoin-up")
    function native.FriendsButton:GetAtlas() return self.atlas end
    function native.QueueButton:GetAtlas() return self.atlas end
    native.OnClick = function(self, button)
        equal(self, native); equal(button, "LeftButton")
        f.clicks, f.lastToast = f.clicks + 1, self.displayedToast
        if f.clickFailure then error("native Social action failed", 0) end
    end
    f.nativeHandler, f.nativeOnHide, f.nativeParent = native.OnClick, native:GetScript("OnHide"), native:GetParent()
    loadAddon(core, "Menubar")
    if options.oldHost then Menubar.CAPABILITIES = nil end
    loadAddon(root, "Menubar_Social")
    Menubar:Start()
    f.host = Menubar
    for _, widget in pairs(Menubar.runtime) do if widget.instance.type == "social" then f.widget = widget; break end end
    assert(f.widget and not f.widget.failed, tostring(f.widget and f.widget.failed or "Social did not initialize"))
    function f:step()
        for _, frame in ipairs(Stub.frames) do if frame:IsVisible() and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 1) end end
        Stub.FireTickers()
    end
    function f:event(name, ...)
        for _, frame in ipairs(Stub.frames) do
            if frame.events and frame.events[name] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, name, ...) end
        end
    end
    function f:masked()
        equal(native:GetAlpha(), 0); equal(native:IsMouseEnabled(), false)
        equal(native:IsShown(), true); equal(native:GetParent(), self.nativeParent)
        equal(native.OnClick, self.nativeHandler); equal(native:GetScript("OnHide"), self.nativeOnHide)
        equal(native.events.SOCIAL_QUEUE_UPDATE, true); equal(native.nativeHideCalls, nil); equal(native.queueCacheCleared, nil)
    end
    function f:restored() equal(native:GetAlpha(), 0.8); equal(native:IsMouseEnabled(), true) end
    function f:setting(widget, key, value)
        self.host.UI:OpenWidget(widget.id)
        local caption
        for _, setting in ipairs(self.host.types.social.settings) do if setting.key == key then caption = setting.label end end
        assert(caption, "Social must expose setting " .. key)
        for _, control in ipairs(self.host.UI.window.controls) do
            if control.caption == caption then
                if control:GetChecked() ~= value then control:Click() end
                equal(widget.settings[key], value); self:step(); return
            end
        end
        error("Missing Social settings control " .. caption)
    end
    return f
end

check("Social's real host routes left directly, right to settings and Shift-left to arrangement", function()
    local f = fixture(); local widget = f.widget; f:masked()
    equal(widget.label:GetText(), "7")
    local menus = #f.Stub.menus
    widget.frame:Click("LeftButton")
    equal(f.clicks, 1); equal(#f.Stub.menus, menus); equal(f.host.UI.widgetID, nil)
    widget.frame:Click("RightButton"); equal(f.host.UI.widgetID, widget.id); equal(f.clicks, 1)
    f.shift = true; widget.frame:Click("LeftButton")
    equal(f.clicks, 1); equal(#f.Stub.menus, menus + 1)
    local menu = f.Stub.menus[#f.Stub.menus]
    assert(findItem(menu, "Move earlier")); assert(findItem(menu, "Configure..."))
    assert(findItem(menu, "Open Social")); findItem(menu, "Open Social").callback(); equal(f.clicks, 2)
    widget.frame.scripts.OnEnter(widget.frame)
    equal(GameTooltip:GetOwner(), widget.frame)
    local hint = GameTooltip.lines[#GameTooltip.lines][1]
    assert(hint:find("Left-click:", 1, true) and hint:find("Shift-left-click: menu", 1, true))
end)

check("Social menu actions ignore released removed and suspended widget lifetimes", function()
    for _, kind in ipairs({ "closed", "other menu", "removed", "disabled", "reenabled" }) do
        local f = fixture(); local widget = f.widget
        f.shift = true; widget.frame:Click("LeftButton")
        local stale = assert(findItem(f.Stub.menus[#f.Stub.menus], "Open Social")).callback
        if kind == "closed" then Menu.GetManager():CloseMenus()
        elseif kind == "other menu" then f.host.UI:Context(UIParent, function(menu) menu:CreateTitle("Another menu") end)
        elseif kind == "removed" then f.host:RemoveWidget(widget.id)
        else
            widget.instance.enabled = false; f.host:Rebuild()
            if kind == "reenabled" then widget.instance.enabled = true; f.host:Rebuild() end
        end
        stale(); equal(f.clicks, 0); equal(f.fallbackClicks, 0)
        if kind ~= "removed" and kind ~= "disabled" then
            f.host.UI:WidgetMenu(widget.frame, widget.instance)
            findItem(f.Stub.menus[#f.Stub.menus], "Open Social").callback()
            equal(f.clicks, 1)
        end
    end
end)

check("settings release and reacquire the native button while preserving widget display", function()
    local f = fixture(); f:masked()
    f:setting(f.widget, "hideChatButton", false); f:restored()
    f:setting(f.widget, "showLabel", true); assert(f.widget.label:GetText():find("Social", 1, true))
    f:setting(f.widget, "showCount", false); equal(f.widget.label:GetText(), "Social")
    f:setting(f.widget, "hideChatButton", true); f:masked()
end)

check("duplicate instances hold ownership through independent settings, disable and removal", function()
    local f = fixture()
    local instance = f.host:AddWidget("social"); local second = f.host.runtime[instance.id]
    f:setting(f.widget, "hideChatButton", false); f:masked()
    second.instance.enabled = false; f.host:Rebuild(); f:step(); f:restored()
    second.instance.enabled = true; f.host:Rebuild(); f:step(); f:masked()
    f.host:RemoveWidget(second.id); f:step(); f:restored()
    f:setting(f.widget, "hideChatButton", true); f:masked()
    f.host:RemoveWidget(f.widget.id); f:step(); f:restored()
end)

check("theme changes, both-bar placement and overflow retain an accessible native action", function()
    local f = fixture(); local original = f.widget
    for _, theme in ipairs({ "warcraftBrown", "warcraftBlack", "warcraftRed", "system7" }) do
        MenubarModel.ApplyTheme(f.host:GetProfile(), theme)
        f.host:GetProfile().placement = "both"; f.host:Rebuild(); f:step()
        equal(f.host.runtime[original.id], original); equal(original.failed, nil); f:masked()
    end
    UIParent:SetWidth(44); f.host:Rebuild(); f:step()
    equal(original.frame:IsShown(), false); f:masked()
    local bar = f.host.bars[f.host:EffectiveBar(original.instance)]
    assert(bar.overflow:IsShown()); bar.overflow:Click("LeftButton")
    local action = assert(findItem(f.Stub.menus[#f.Stub.menus], "Open Social"), "Overflow must retain Social action")
    action.callback(); equal(f.clicks, 1)
    UIParent:SetWidth(1280); f.host:Rebuild(); f.host:RemoveWidget(original.id); f:step(); f:restored()
end)

check("render failures restore native chat access and successful refresh can recover", function()
    local f = fixture(); local widget = f.widget; f:masked()
    local setText = widget.SetText
    widget.SetText = function() error("Social display failed", 0) end
    f.host:RefreshWidget(widget.id); f:step()
    equal(widget.failed, "Social display failed"); f:restored()
    widget.SetText = setText; f.host:RefreshWidget(widget.id); f:step()
    equal(widget.failed, nil); f:masked()
end)

check("native click errors invoke host reset and retain settings for recovery", function()
    local f = fixture(); f.clickFailure = true
    f.widget.frame:Click("LeftButton")
    equal(f.widget.failed, "native Social action failed"); equal(f.widget.failedCallback, "click")
    equal(f.fallbackClicks, 0); f:restored()
    f.widget.frame:Click("RightButton"); equal(f.host.UI.widgetID, f.widget.id)
    f.clickFailure = false; f.host:RefreshWidget(f.widget.id); f:step(); f:masked()
    f.widget.frame:Click("LeftButton"); equal(f.clicks, 2)
end)

check("combat and denied protected-state permission defer suppression and restoration", function()
    local f = fixture(); f:masked()
    f.combat = true; f:setting(f.widget, "hideChatButton", false); f:masked()
    f.combat = false; f.permission = false; f:event("PLAYER_REGEN_ENABLED"); f:step()
    -- Visibility can be restored safely while protected input is still deferred.
    equal(f.native:GetAlpha(), 0.8); equal(f.native:IsMouseEnabled(), false)
    f.permission = true; f:step(); f:restored()
    f.combat = true; f:setting(f.widget, "hideChatButton", true); f:restored()
    f.combat = false; f:event("PLAYER_REGEN_ENABLED"); f:step(); f:masked()
end)

check("native game-rule denial restores the chat copy and blocks direct Social activation", function()
    local f = fixture(); f:masked()
    f.rule = true; f.host:RefreshWidget(f.widget.id); f:step(); f:restored()
    f.widget.frame:Click("LeftButton"); equal(f.clicks, 0); equal(f.fallbackClicks, 0)
    f.rule = false; f.host:RefreshWidget(f.widget.id); f:step(); f:masked()
end)

check("older API-v1 hosts retain their native Social button and expose context activation", function()
    local f = fixture({ oldHost = true }); f:restored()
    f.host.UI:WidgetMenu(f.widget.frame, f.widget.instance)
    local action = assert(findItem(f.Stub.menus[#f.Stub.menus], "Open Social"))
    action.callback(); equal(f.clicks, 1); f:restored()
end)

check("friend transitions animate only Social's icon through the actual host event boundary", function()
    local f = fixture(); local widget = f.widget
    local label, icon = widget.label:GetText(), widget.socialIcon
    local anchor = widget.label.points[1][4]
    equal(#f.Stub.animations, 0)
    f:step(); f.host:RefreshWidget(widget.id)
    equal(#f.Stub.animations, 0)
    f.wowFriends[1].connected, f.wowFriends[2].connected = false, true
    f:event("FRIENDLIST_UPDATE")
    local motion = assert(widget.iconJiggle)
    equal(motion.icon, icon); equal(motion.group.parent, icon)
    equal(motion.group.plays, 1); equal(motion.group.playing, true)
    equal(widget.label:GetText(), label); equal(widget.label.points[1][4], anchor)
    f.bnFriends[2].gameAccountInfo.isOnline = true
    f:event("BN_FRIEND_INFO_CHANGED", 2)
    f:event("BN_FRIEND_ACCOUNT_ONLINE", 20, false)
    equal(motion.group.plays, 1) -- Bursts coalesce while an animation is playing.
    motion.group:Finish()
    f.bnFriends[1].gameAccountInfo.isOnline = false
    f:event("BN_FRIEND_ACCOUNT_OFFLINE", 10, false)
    equal(motion.group.plays, 2); equal(#f.Stub.animations, 1)
    equal(widget.failed, nil); f:masked()
end)

check("hidden icons and widgets stay quiet and hiding or removal stops the owned animation", function()
    local f = fixture(); local widget = f.widget
    local setAtlas = widget.socialIcon.SetAtlas
    widget.socialIcon.SetAtlas = function() return false end
    f.wowFriends[1].connected = false; f:event("FRIENDLIST_UPDATE")
    equal(widget.socialIcon:IsShown(), false); equal(widget.iconJiggle, nil)
    widget.socialIcon.SetAtlas = setAtlas
    f.host:RefreshWidget(widget.id)
    f.wowFriends[1].connected = true; f:event("FRIENDLIST_UPDATE")
    local group = widget.iconJiggle.group; equal(group.playing, true)
    widget.frame:Hide(); equal(group.playing, false)
    f.wowFriends[1].connected = false; f:event("FRIENDLIST_UPDATE")
    equal(group.plays, 1)
    widget.frame:Show(); f.host:RefreshWidget(widget.id); equal(group.plays, 1)
    f.wowFriends[1].connected = true; f:event("FRIENDLIST_UPDATE"); equal(group.plays, 2)
    f.host:RemoveWidget(widget.id)
    equal(group.playing, false); equal(widget.socialPresence, nil); f:restored()
end)

check("duplicate Social widgets own independent baselines and animation resources", function()
    local f = fixture(); local first = f.widget
    local added = f.host:AddWidget("social"); local second = f.host.runtime[added.id]
    assert(first.socialPresence ~= second.socialPresence)
    f.wowFriends[1].connected = false; f:event("FRIENDLIST_UPDATE")
    local firstGroup, secondGroup = first.iconJiggle.group, second.iconJiggle.group
    assert(firstGroup ~= secondGroup)
    equal(firstGroup.parent, first.socialIcon); equal(secondGroup.parent, second.socialIcon)
    f.host:RemoveWidget(first.id); equal(firstGroup.playing, false); f:masked()
    secondGroup:Finish(); f.wowFriends[1].connected = true; f:event("FRIENDLIST_UPDATE")
    equal(secondGroup.plays, 2); equal(second.failed, nil)
end)

check("notification callback failures reset only the failing widget and release its native-button request", function()
    local f = fixture(); local first = f.widget
    local added = f.host:AddWidget("social"); local second = f.host.runtime[added.id]
    first.JiggleIcon = function() error("Social animation rejected", 0) end
    f.wowFriends[1].connected = false; f:event("FRIENDLIST_UPDATE")
    equal(first.failed, "Social animation rejected"); equal(first.failedCallback, "event")
    equal(first.socialPresence, nil); equal(second.failed, nil)
    equal(second.iconJiggle.group.plays, 1); f:masked()
    f.host:RemoveWidget(first.id); f:masked()
    f.host:RemoveWidget(second.id); f:restored()
end)

check("canonical atlas capitalization preserves Social icons and WoW and Battle.net transition motion", function()
    local f = fixture({ atlasReadback = function(atlas) return atlas and atlas:upper() end })
    local widget, icon = f.widget, f.widget.socialIcon
    equal(icon:GetAtlas(), "QUICKJOIN-BUTTON-FRIENDSLIST-UP"); equal(icon:IsVisible(), true)
    equal(widget.label:GetText(), "7"); equal(widget.iconJiggle, nil); f:masked()
    local width, label = widget.width, widget.label:GetText()
    f.wowFriends[1].connected = false; f:event("FRIENDLIST_UPDATE")
    local motion = assert(widget.iconJiggle)
    equal(motion.icon, icon); equal(motion.group.parent, icon); equal(motion.group.plays, 1)
    equal(motion.group:IsPlaying(), true); equal(icon:IsVisible(), true)
    motion.group:Finish()
    f.bnFriends[2].gameAccountInfo.isOnline = true; f:event("BN_FRIEND_ACCOUNT_ONLINE", 20, false)
    equal(motion.group.plays, 2); motion.group:Finish()
    f.bnFriends[1].gameAccountInfo.isOnline = false; f:event("BN_FRIEND_ACCOUNT_OFFLINE", 10, false)
    equal(motion.group.plays, 3); motion.group:Finish()
    for _, toast in ipairs({ { isLFGList = false, atlas = "QUICKJOIN-BUTTON-QUICKJOIN-UP" },
        { isLFGList = true, atlas = "QUICKJOIN-BUTTON-GROUP-UP" } }) do
        f.native.displayedToast, f.native.isLFGList = {}, toast.isLFGList
        f:event("SOCIAL_QUEUE_UPDATE")
        equal(icon:GetAtlas(), toast.atlas); equal(icon:IsVisible(), true)
        equal(motion.group.plays, 3)
    end
    equal(widget.width, width); equal(widget.label:GetText(), label); equal(#f.Stub.animations, 1)
    equal(widget.failed, nil); f:masked()
end)

check("different missing and restricted Social atlas readbacks retain text fallback and suppress motion", function()
    for _, mode in ipairs({ "different", "missing", "restricted" }) do
        local fallback = true
        local f = fixture({ atlasReadback = function(atlas, state)
            if not fallback then return atlas and atlas:upper() end
            if mode == "different" then return "another-social-icon" end
            if mode == "restricted" then return state.secret end
        end })
        local widget, icon = f.widget, f.widget.socialIcon
        equal(widget.failed, nil); equal(icon:IsShown(), false); equal(widget.iconJiggle, nil)
        equal(widget.label:GetText(), "Social 7"); f:masked()
        f.wowFriends[1].connected = false; f:event("FRIENDLIST_UPDATE")
        equal(widget.iconJiggle, nil)
        fallback = false; f.host:RefreshWidget(widget.id)
        equal(widget.socialIcon, icon); equal(icon:IsVisible(), true); equal(widget.label:GetText(), "7")
        equal(widget.iconJiggle, nil)
        f.wowFriends[1].connected = true; f:event("FRIENDLIST_UPDATE")
        equal(widget.iconJiggle.icon, icon); equal(widget.iconJiggle.group.plays, 1)
        equal(widget.failed, nil); f:masked()
    end
end)

print(passed .. " Social host integration tests passed")
