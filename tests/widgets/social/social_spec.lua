-- Independent public-contract tests. These original fixtures model API results,
-- frame ownership and restoration; they do not emulate native taint or rendering.
local root = REPO_ROOT or "."
local passed = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end

local function fixture(options)
    options = options or {}
    local f = { frames = {}, mutations = {}, clicks = {}, fallbackClicks = {}, combat = false,
        permission = true, onlineBN = 4, onlineWoW = 3, legacy = true, connected = true,
        wowFriends = { { guid = "Player-1", connected = true }, { guid = "Player-2", connected = false } },
        bnFriends = { { bnetAccountID = 10, gameAccountInfo = { isOnline = true } },
            { bnetAccountID = 20, gameAccountInfo = { isOnline = false } } } }
    local secret = setmetatable({}, {
        __index = function() error("Restricted data was indexed", 0) end,
        __lt = function() error("Restricted data was compared", 0) end,
        __le = function() error("Restricted data was compared", 0) end,
        __tostring = function() error("Restricted data was formatted", 0) end,
    })
    f.secret = secret
    local env = setmetatable({}, { __index = _G }); env._G = env
    f.env = env
    env.issecretvalue = function(value) return rawequal(value, secret) end
    local Region = {}; Region.__index = Region
    local function region(kind, parent)
        return setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, points = {},
            alpha = 1, enabled = true, mouseEnabled = true, textures = {}, text = "", width = 20, height = 20 }, Region)
    end
    function Region:SetScript(name, callback)
        if self.kind == "Frame" and f.monitorScriptFailure and name == "OnUpdate" then error("monitor setup failed", 0) end
        self.scripts[name] = callback
    end
    function Region:GetScript(name) return self.scripts[name] end
    function Region:HookScript(name, callback)
        local previous = self.scripts[name]
        self.scripts[name] = function(...) if previous then previous(...) end; callback(...) end
    end
    function Region:RegisterEvent(name) self.events = self.events or {}; self.events[name] = true end
    function Region:UnregisterEvent(name) if self.events then self.events[name] = nil end end
    function Region:UnregisterAllEvents() self.events = {} end
    function Region:SetSize(width, height) self.width, self.height = width, height end
    function Region:SetWidth(width) self.width = width end
    function Region:SetHeight(height) self.height = height end
    function Region:GetWidth() return self.width end
    function Region:GetHeight() return self.height end
    function Region:ClearAllPoints() self.points = {} end
    function Region:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function Region:SetAllPoints() end
    function Region:GetParent() return self.parent end
    function Region:SetParent(parent) self.parent = parent end
    function Region:GetAlpha() if self.alphaReadError then error("native alpha unavailable", 0) end; return self.alpha end
    function Region:SetAlpha(value)
        if self == f.native then
            assert(not f.combat, "Native alpha mutation must defer during combat")
            f.mutations[#f.mutations + 1] = { "alpha", value }
            if self.alphaWriteError then error("native alpha rejected", 0) end
        end
        self.alpha = value
    end
    function Region:IsMouseEnabled() if self.mouseReadError then error("native mouse state unavailable", 0) end; return self.mouseEnabled end
    function Region:EnableMouse(value)
        if self == f.native then
            assert(not f.combat and f.permission == true, "Native input mutation requires public permission")
            f.mutations[#f.mutations + 1] = { "mouse", value }
            if self.mouseWriteError then error("native input rejected", 0) end
        end
        self.mouseEnabled = value
    end
    function Region:IsEnabled() if self.enabledReadError then error("native enabled state unavailable", 0) end; return self.enabled end
    function Region:CanChangeProtectedState() if f.permissionError then error("native permission unavailable", 0) end; return f.permission end
    function Region:IsShown() return self.shown end
    function Region:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function Region:Show()
        if self.kind == "Frame" and f.monitorShowFailure then error("monitor show failed", 0) end
        local before = self.shown; self.shown = true; if not before and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function Region:Hide() local before = self.shown; self.shown = false; if before and self.scripts.OnHide then self.scripts.OnHide(self) end end
    function Region:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function Region:SetTexture(value) self.texture, self.atlas = value, nil; return not f.iconFailure end
    function Region:SetAtlas(value) if f.iconThrow then error("native atlas unavailable", 0) end; self.atlas, self.texture = value, nil; return not f.iconFailure end
    function Region:GetAtlas() return self.atlas end
    function Region:SetTexCoord(...) self.texCoords = { ... } end
    function Region:SetVertexColor(...) self.color = { ... } end
    function Region:SetText(text) self.text = text end
    function Region:GetText() return self.text end
    function Region:GetStringWidth() return #self.text * 6 end
    function Region:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function Region:GetTextColor() return 1, 0.82, 0, 1 end
    function Region:CreateTexture() local texture = region("Texture", self); self.textures[#self.textures + 1] = texture; return texture end
    function Region:CreateFontString() return region("FontString", self) end
    env.UIParent = region("Frame")
    env.CreateFrame = function(kind, _, parent)
        if f.monitorAllocationFailure and #f.frames > 0 then error("monitor allocation failed", 0) end
        local frame = region(kind, parent); f.frames[#f.frames + 1] = frame; return frame
    end
    env.InCombatLockdown = function() if f.combatReadError then error("combat unreadable", 0) end; return f.combat end
    env.BNGetNumFriends = function() if f.bnError then error("BN count unavailable", 0) end; return f.bnTotal or #f.bnFriends, f.onlineBN end
    env.BNConnected = function() return f.connected end
    env.C_BattleNet = {
        GetFriendAccountInfo = function(index)
            f.bnReads = (f.bnReads or 0) + 1
            if not f.bnUnavailable then return f.bnFriends[index] end
        end,
        GetAccountInfoByID = function(id)
            if f.bnByIDUnavailable then return end
            for _, info in ipairs(f.bnFriends) do if rawequal(info.bnetAccountID, id) then return info end end
        end,
    }
    env.C_FriendList = {
        IsLegacyFriendSystemEnabled = function() return f.legacy end,
        GetNumOnlineFriends = function() if f.wowError then error("WoW count unavailable", 0) end; return f.onlineWoW end,
        GetNumFriends = function() if f.wowError then error("WoW list unavailable", 0) end; return f.wowTotal or #f.wowFriends end,
        GetFriendInfoByIndex = function(index)
            f.wowReads = (f.wowReads or 0) + 1
            if not f.wowUnavailable then return f.wowFriends[index] end
        end,
    }
    env.C_GameRules = { IsGameRuleActive = function() if f.ruleError then error("rule unavailable", 0) end; return f.rule or false end }
    env.Enum = { GameRule = { IngameFriendsListDisabled = 7 } }
    env.FRIEND_TAB_FRIENDS = 1
    env.ToggleFriendsFrame = function(tab) f.fallbackClicks[#f.fallbackClicks + 1] = tab end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) f.message = text end }
    env.Menubar = { CAPABILITIES = { directClick = true },
        RegisterWidgetType = function(_, provider) assert(not f.provider); f.provider = provider end }
    if not options.noNative then
        local native = env.CreateFrame("Button", "QuickJoinToastButton", env.UIParent)
        f.native, env.QuickJoinToastButton = native, native
        native.alpha, native.mouseEnabled = 0.8, true
        native.FriendsButton = native:CreateTexture(); native.FriendsButton:SetAtlas("quickjoin-button-friendslist-up")
        native.QueueButton = native:CreateTexture(); native.QueueButton:SetAtlas("quickjoin-button-quickjoin-up")
        native:RegisterEvent("SOCIAL_QUEUE_UPDATE")
        native:SetScript("OnHide", function() error("Native Hide would unregister queues and clear cached data", 0) end)
        native.SetParent = function() error("Native chat button must retain its parent", 0) end
        native.OnClick = function(self, button)
            equal(self, native); equal(button, "LeftButton")
            f.clicks[#f.clicks + 1] = self.displayedToast or "friends"
            if f.clickError then error(f.clickErrorReason or "native social click failed", 0) end
        end
    end
    local chunk = assert(loadfile(root .. "/src/menubar-social/Social.lua"))
    setfenv(chunk, env); chunk("Menubar_Social", {})
    assert(f.provider, "Social must register with the host")
    function f:widget(settings, defer)
        local widget = { settings = {}, frame = region("Frame", env.UIParent) }
        for key, value in pairs(self.provider.defaults) do widget.settings[key] = value end
        for key, value in pairs(settings or {}) do widget.settings[key] = value end
        widget.label = region("FontString", widget.frame)
        function widget:SetText(text) if self.failText then error("proxy render failed", 0) end; self.text = text; self.label:SetText(text) end
        function widget:SetWidth(width) self.width = width end
        function widget:Refresh() f.provider.update(self) end
        function widget:JiggleIcon(texture) self.jiggles = (self.jiggles or 0) + 1; self.jiggledTexture = texture end
        function widget:StopIconJiggle() self.stops = (self.stops or 0) + 1 end
        if self.provider.create then self.provider.create(widget) end
        if not defer then self.provider.update(widget) end
        return widget
    end
    function f:step()
        for _, frame in ipairs(self.frames) do if frame:IsShown() and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 1) end end
    end
    function f:event(name)
        for _, frame in ipairs(self.frames) do if frame.events and frame.events[name] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, name) end end
    end
    function f:notify(widget, name, ...)
        self.provider.update(widget)
        self.provider.event(widget, name, ...)
    end
    function f:masked()
        equal(self.native:GetAlpha(), 0); equal(self.native:IsMouseEnabled(), false)
        equal(self.native:IsShown(), true); equal(self.native:GetParent(), env.UIParent)
        equal(self.native.events.SOCIAL_QUEUE_UPDATE, true)
    end
    function f:restored() equal(self.native:GetAlpha(), 0.8); equal(self.native:IsMouseEnabled(), true) end
    function f:menu(widget)
        local menu = { children = {} }
        function menu:CreateButton(text, callback) local child = { text = text, callback = callback }; self.children[#self.children + 1] = child; return child end
        function menu:CreateDivider() end
        function menu:CreateTitle() end
        self.provider.contextMenu(widget, menu)
        for _, child in ipairs(menu.children) do if child.text == "Open Social" then return child end end
        error("Missing Open Social action")
    end
    return f
end


check("registers an independent Social provider with direct-click and native visibility settings", function()
    local f = fixture()
    equal(f.provider.id, "social")
    equal(f.provider.defaults.showCount, true); equal(f.provider.defaults.showLabel, false)
    equal(f.provider.defaults.hideChatButton, true)
    equal(f.provider.defaultPlacement.alignment, "right")
    equal(f.provider.defaultPlacement.order, 6)
    equal(f.provider.defaultPlacement.sidebarOrder, 6)
    assert(type(f.provider.click) == "function" and type(f.provider.clickHint) == "string")
    assert(type(f.provider.reset) == "function" and type(f.provider.destroy) == "function")
end)

check("native online counts use BN online return and only the active legacy friend list", function()
    local f = fixture(); local widget = f:widget()
    equal(widget.label:GetText(), "7")
    f.legacy = false; f.provider.update(widget); equal(widget.label:GetText(), "4")
    f.legacy = true; f.onlineBN, f.onlineWoW = 0, 0
    f.provider.update(widget); equal(widget.label:GetText(), "0")
    f.provider.destroy(widget); f:restored()
end)

check("count display and label choices remain independent for simultaneous widgets", function()
    local f = fixture()
    local first = f:widget({ showCount = false, showLabel = true, hideChatButton = false })
    local second = f:widget({ showCount = true, showLabel = true, hideChatButton = false })
    equal(first.label:GetText(), "Social"); equal(second.label:GetText(), "Social 7")
    first.settings.showLabel = false; f.provider.update(first)
    equal(first.label:GetText(), ""); equal(second.label:GetText(), "Social 7")
    assert(first.width > 0 and second.width > first.width)
end)

check("unavailable, invalid and restricted friend counts are explicit unknowns", function()
    for _, value in ipairs({ "3", -1, 1.5, math.huge, 0 / 0 }) do
        local f = fixture(); f.onlineBN = value
        local widget = f:widget({ hideChatButton = false })
        equal(widget.label:GetText(), "--")
    end
    for _, field in ipairs({ "onlineBN", "onlineWoW", "legacy" }) do
        local f = fixture(); f[field] = f.secret
        local widget = f:widget({ hideChatButton = false }); equal(widget.label:GetText(), "--")
    end
    for _, field in ipairs({ "bnError", "wowError" }) do
        local f = fixture(); f[field] = true
        equal(f:widget({ hideChatButton = false }).label:GetText(), "--")
    end
end)

check("default proxy masks native rendering and input without hiding or moving the native button", function()
    local f = fixture(); local native = f.native
    local onClick, onHide, setAlpha, enableMouse = native.OnClick, native:GetScript("OnHide"), native.SetAlpha, native.EnableMouse
    local widget = f:widget(); f:masked()
    equal(f.mutations[1][1], "mouse"); equal(f.mutations[1][2], false)
    equal(f.mutations[2][1], "alpha"); equal(f.mutations[2][2], 0)
    equal(native.OnClick, onClick); equal(native:GetScript("OnHide"), onHide)
    equal(native.SetAlpha, setAlpha); equal(native.EnableMouse, enableMouse)
    f.provider.destroy(widget); f:restored()
    local total = #f.mutations
    equal(f.mutations[total - 1][1], "alpha"); equal(f.mutations[total][1], "mouse")
end)

check("direct click invokes the original native handler with its actual queue context", function()
    local f = fixture(); local widget = f:widget()
    f.provider.click(widget, "LeftButton"); equal(#f.clicks, 1); equal(f.clicks[1], "friends")
    f.native.displayedToast = { guid = "original-social-queue" }
    f.provider.update(widget); f.provider.click(widget, "LeftButton")
    equal(f.clicks[2], f.native.displayedToast); equal(#f.fallbackClicks, 0)
    local icon = widget.frame.textures[1]
    equal(icon.atlas, "quickjoin-button-quickjoin-up")
    equal(widget.label:GetText(), "7")
end)

check("a native button hidden by an input-mode transition still supplies its original action", function()
    local f = fixture(); f.native.shown = false
    local widget = f:widget({ hideChatButton = false })
    f.provider.click(widget, "LeftButton"); equal(#f.clicks, 1)
    equal(f.native:IsShown(), false)
end)

check("explicit disabled state and unreadable native permissions cannot be bypassed by fallback", function()
    for _, state in ipairs({ "disabled", "restricted", "error", "rule", "restrictedRule", "ruleError" }) do
        local f = fixture()
        if state == "disabled" then f.native.enabled = false
        elseif state == "restricted" then f.native.enabled = f.secret
        elseif state == "error" then f.native.enabledReadError = true
        elseif state == "rule" then f.rule = true
        elseif state == "restrictedRule" then f.rule = f.secret
        else f.ruleError = true end
        local widget = f:widget()
        f.provider.click(widget, "LeftButton")
        equal(#f.clicks, 0); equal(#f.fallbackClicks, 0); f:restored()
    end
end)

check("clients without a native handler use the existing friends-panel toggle", function()
    local f = fixture(); f.native.OnClick = nil
    local widget = f:widget(); f.provider.click(widget, "LeftButton")
    equal(#f.clicks, 0); equal(f.fallbackClicks[1], 1)
    local absent = fixture({ noNative = true }); local fallback = absent:widget()
    absent.provider.click(fallback, "LeftButton"); equal(absent.fallbackClicks[1], 1)
end)

check("native action errors restore chat access, propagate, and never open another window", function()
    local f = fixture(); local widget = f:widget(); f:masked(); f.clickError = true
    local ok, reason = pcall(f.provider.click, widget, "LeftButton")
    equal(ok, false); assert(tostring(reason):find("native social click failed", 1, true))
    equal(#f.clicks, 1); equal(#f.fallbackClicks, 0); f:restored()
end)

check("delayed context action errors are contained and release native button ownership", function()
    local f = fixture(); local widget = f:widget(); local action = f:menu(widget)
    f.clickError = true
    local ok = pcall(action.callback)
    equal(ok, true); equal(#f.fallbackClicks, 0); f:restored()
end)

check("delayed failures retain the original diagnostic and report once until a successful action", function()
    local f = fixture(); local reports = {}
    f.env.Menubar.Print = function(message) reports[#reports + 1] = message end
    local widget = f:widget(); local action = f:menu(widget)
    f.clickError = true; action.callback()
    equal(widget.socialMessage, "Social action failed: native social click failed")
    equal(reports[1], widget.socialMessage); equal(#reports, 1); f:restored()
    action.callback(); equal(#reports, 1)
    equal(widget.socialMessage, "Social action failed: native social click failed")
    f.clickError = false; action.callback(); equal(widget.socialMessage, nil)
    f.clickError = true; action.callback(); equal(#reports, 2)
    equal(reports[2], "Social action failed: native social click failed"); f:restored()
end)

check("a throwing diagnostic reporter cannot escape a delayed action or cause repeated reports", function()
    local f = fixture(); local reports = 0
    f.env.Menubar.Print = function() reports = reports + 1; error("diagnostic reporter unavailable", 0) end
    local widget = f:widget(); local action = f:menu(widget); f.clickError = true
    equal(pcall(action.callback), true); equal(reports, 1); f:restored()
    equal(pcall(action.callback), true); equal(reports, 1)
    f.clickError = false; equal(pcall(action.callback), true)
    f.clickError = true; equal(pcall(action.callback), true); equal(reports, 2); f:restored()
end)

check("restricted delayed-action errors produce safe diagnostics without formatting their value", function()
    local f = fixture(); local reports = {}
    f.env.Menubar.Print = function(message) reports[#reports + 1] = message end
    local widget = f:widget(); local action = f:menu(widget)
    f.clickError, f.clickErrorReason = true, f.secret
    equal(pcall(action.callback), true); equal(#reports, 1)
    assert(type(widget.socialMessage) == "string" and widget.socialMessage:find("Social action failed:", 1, true))
    equal(reports[1], widget.socialMessage); f:restored()
end)

check("multiple healthy instances retain native masking until the last request releases", function()
    local f = fixture(); local first, second = f:widget(), f:widget()
    f:masked(); f.provider.destroy(first); f:masked()
    second.settings.hideChatButton = false; f.provider.update(second); f:restored()
    second.settings.hideChatButton = true; f.provider.update(second); f:masked()
    f.provider.destroy(second); f:restored()
    f:step(); f:restored()
end)

check("reset releases only the failed instance while another healthy proxy remains", function()
    local f = fixture(); local first, second = f:widget(), f:widget()
    f.provider.reset(first, "update"); f:masked()
    f.provider.reset(second, "click"); f:restored()
    f.provider.update(first); f:masked(); f.provider.destroy(first); f:restored()
end)

check("an original mouse-disabled state is restored exactly", function()
    local f = fixture(); f.native.mouseEnabled = false
    local widget = f:widget(); f:masked()
    f.provider.destroy(widget)
    equal(f.native:GetAlpha(), 0.8); equal(f.native:IsMouseEnabled(), false)
end)

check("combat defers both initial suppression and final restoration until allowed", function()
    local f = fixture(); f.combat = true
    local widget = f:widget(); f:restored(); equal(#f.mutations, 0)
    f.combat = false; f:event("PLAYER_REGEN_ENABLED"); f:step(); f:masked()
    f.combat = true; f.provider.destroy(widget); f:masked()
    f.combat = false; f:event("PLAYER_REGEN_ENABLED"); f:step(); f:restored()
end)

check("protected-state rejection, restricted permission and thrown reads defer all native writes", function()
    for _, state in ipairs({ "denied", "restricted", "error" }) do
        local f = fixture()
        if state == "denied" then f.permission = false
        elseif state == "restricted" then f.permission = f.secret
        else f.permissionError = true end
        local widget = f:widget(); f:restored(); equal(#f.mutations, 0)
        f.permission, f.permissionError = true, false
        f:step(); f:masked(); f.provider.destroy(widget); f:restored()
    end
end)

check("unreadable original frame state never produces a partial native disguise", function()
    for _, field in ipairs({ "alphaReadError", "mouseReadError" }) do
        local f = fixture(); f.native[field] = true
        local widget = f:widget(); equal(#f.mutations, 0)
        f.native[field] = false; f:restored()
        f:step(); f:masked(); f.provider.destroy(widget); f:restored()
    end
end)

check("a rejected input write leaves the original native button visible", function()
    local f = fixture(); f.native.mouseWriteError = true
    local widget = f:widget()
    equal(f.native:GetAlpha(), 0.8); equal(f.native:IsMouseEnabled(), true)
    f.native.mouseWriteError = false; f:step(); f:masked()
    f.provider.destroy(widget); f:restored()
end)

check("native alpha or input changes are reasserted while the original button stays alive", function()
    local f = fixture(); local widget = f:widget(); f:masked()
    f.native.alpha, f.native.mouseEnabled = 1, true
    f:step(); f:masked()
    f.provider.destroy(widget); equal(f.native:GetAlpha(), 1); equal(f.native:IsMouseEnabled(), true)
end)

check("a missing icon retains a usable text fallback while failed text restores the native control", function()
    local f = fixture(); f.iconFailure = true
    local widget = f:widget({}, true)
    f.provider.update(widget); equal(widget.label:GetText(), "Social 7"); equal(widget.text, "Social 7"); f:masked()
    f.iconFailure = false; f.provider.update(widget); f:masked()
    widget.failText = true
    local ok = pcall(f.provider.update, widget); equal(ok, false)
    f.provider.reset(widget, "update"); f:restored()
end)

check("restricted queue metadata is not inspected or formatted and retains safe friend display", function()
    local f = fixture(); f.native.displayedToast = f.secret
    local widget = f:widget({ hideChatButton = false })
    equal(widget.label:GetText(), "7")
    equal(widget.frame.textures[1].atlas, "quickjoin-button-friendslist-up")
end)

check("native-state secrets are rejected before comparing or mutating borrowed UI", function()
    for _, field in ipairs({ "alpha", "mouseEnabled" }) do
        local f = fixture(); f.native[field] = f.secret
        local widget = f:widget(); equal(#f.mutations, 0)
        f.native.alpha, f.native.mouseEnabled = 0.8, true
        f:step(); f:masked(); f.provider.destroy(widget); f:restored()
    end
end)

check("a rejected alpha write rolls back input while leaving the original native control visible", function()
    local f = fixture(); f.native.alphaWriteError = true
    local widget = f:widget(); f:restored()
    equal(f.mutations[1][1], "mouse"); equal(f.mutations[1][2], false)
    equal(f.mutations[#f.mutations][1], "mouse"); equal(f.mutations[#f.mutations][2], true)
    f.native.alphaWriteError = false; f:step(); f:masked()
    f.provider.destroy(widget); f:restored()
end)

check("restoration retries protected input without restoring an invisible hit region", function()
    local f = fixture(); local widget = f:widget(); f:masked()
    f.permission = false; f.provider.destroy(widget)
    equal(f.native:GetAlpha(), 0.8); equal(f.native:IsMouseEnabled(), false)
    f.permission = true; f:step(); f:restored()
end)

check("old hosts or unavailable Social actions leave the chat button visible", function()
    for _, state in ipairs({ "oldHost", "missingAction", "unknownRule" }) do
        local f = fixture()
        if state == "oldHost" then f.env.Menubar.CAPABILITIES = nil
        elseif state == "missingAction" then f.native.OnClick, f.env.ToggleFriendsFrame = nil, nil
        else f.env.C_GameRules.IsGameRuleActive = function() return nil end end
        local widget = f:widget(); f:restored(); equal(#f.mutations, 0)
        if state ~= "oldHost" then f.provider.click(widget, "LeftButton"); equal(#f.clicks, 0); equal(#f.fallbackClicks, 0) end
    end
end)

check("one shared monitor exists only while a requester or pending restoration needs it", function()
    local f = fixture()
    local idle = f:widget({ hideChatButton = false }); equal(#f.frames, 1)
    local first, second = f:widget(), f:widget(); equal(#f.frames, 2)
    local monitor = f.frames[2]; assert(monitor.scripts.OnUpdate and monitor:IsShown())
    equal(monitor.events.PLAYER_REGEN_ENABLED, true)
    for _ = 1, 20 do f.provider.update(first); f.provider.update(second) end
    equal(#f.frames, 2)
    f.provider.destroy(first); f.provider.destroy(second); f.provider.destroy(idle)
    equal(monitor:IsShown(), false); equal(next(monitor.events), nil)
    idle.settings.hideChatButton = true; f.provider.update(idle)
    equal(#f.frames, 2); equal(monitor:IsShown(), true); f:masked()
    f.provider.destroy(idle); equal(monitor:IsShown(), false); f:restored()
end)

check("the original button is restored when a replacement native button becomes available", function()
    local f = fixture(); local widget = f:widget(); local old = f.native
    local replacement = f.env.CreateFrame("Button", nil, f.env.UIParent)
    replacement.alpha, replacement.mouseEnabled = 0.6, true
    replacement.OnClick = function(self, button) equal(self, replacement); equal(button, "LeftButton"); f.replacementClicks = (f.replacementClicks or 0) + 1 end
    f.env.QuickJoinToastButton = replacement
    f:step()
    equal(old:GetAlpha(), 0.8); equal(old:IsMouseEnabled(), true)
    equal(replacement:GetAlpha(), 0); equal(replacement:IsMouseEnabled(), false)
    f.provider.click(widget, "LeftButton"); equal(f.replacementClicks, 1)
    f.provider.destroy(widget)
    equal(replacement:GetAlpha(), 0.6); equal(replacement:IsMouseEnabled(), true)
end)

check("group notifications use their native atlas and tooltip while keeping online-friend counts", function()
    local f = fixture(); f.native.displayedToast = { guid = "group-notification" }; f.native.isLFGList = true
    local widget = f:widget({ hideChatButton = false })
    equal(widget.socialIcon.atlas, "quickjoin-button-group-up"); equal(widget.label:GetText(), "7")
    local tip = { lines = {} }
    function tip:AddLine(text) self.lines[#self.lines + 1] = { text } end
    function tip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = { left, right } end
    f.provider.tooltip(widget, tip)
    local fields, notification = {}, false
    for _, line in ipairs(tip.lines) do
        if line[2] then fields[line[1]] = line[2] end
        if line[1]:find("notification", 1, true) then notification = true end
        assert(not line[1]:find("Click to open", 1, true), "The shared footer owns click instructions")
    end
    equal(fields["Friends online"], "7"); equal(fields["Battle.net"], "4"); equal(fields["WoW friends"], "3")
    assert(notification)
    f.native.isLFGList = false
    f.provider.update(widget); equal(widget.socialIcon.atlas, "quickjoin-button-quickjoin-up")
    f.native.isLFGList = f.secret
    f.provider.update(widget); equal(widget.socialIcon.atlas, "quickjoin-button-quickjoin-up")
end)

check("monitor allocation and setup must succeed before any native state is borrowed", function()
    for _, field in ipairs({ "monitorAllocationFailure", "monitorScriptFailure", "monitorShowFailure" }) do
        local f = fixture(); f[field] = true
        local widget = f:widget({}, true)
        local ok = pcall(f.provider.update, widget)
        equal(ok, true, field .. " must retain a usable proxy while native suppression is deferred")
        equal(#f.mutations, 0); f:restored()
        f[field] = false; f.provider.update(widget); f:masked()
        equal(#f.frames, 2)
        f.provider.destroy(widget); f:restored()
        equal(f.frames[2]:IsShown(), false, field .. " monitor must stop after final release")
    end
end)

check("a partially available game-rule contract cannot bypass unknown Social permission", function()
    for _, state in ipairs({ "missingCallback", "secretCallback", "missingEnum", "secretRules", "secretEnum" }) do
        local f = fixture()
        if state == "missingCallback" then f.env.C_GameRules.IsGameRuleActive = nil
        elseif state == "secretCallback" then f.env.C_GameRules.IsGameRuleActive = f.secret
        elseif state == "missingEnum" then f.env.Enum = nil
        elseif state == "secretRules" then f.env.C_GameRules = f.secret
        else f.env.Enum = f.secret end
        local widget = f:widget(); f.provider.click(widget, "LeftButton")
        equal(#f.clicks, 0, state); equal(#f.fallbackClicks, 0, state)
        equal(#f.mutations, 0, state); f:restored()
    end
    -- A genuinely older client with no game-rule API retains its native action.
    local old = fixture(); old.env.C_GameRules, old.env.Enum = nil, nil
    local widget = old:widget(); old.provider.click(widget, "LeftButton")
    equal(#old.clicks, 1); old:masked()
end)

check("tooltip permissions reflect recovery after a denied click without keeping stale denial text", function()
    local f = fixture(); f.rule = true
    local widget = f:widget(); f.provider.click(widget, "LeftButton"); equal(#f.clicks, 0)
    local function text()
        local tip = { lines = {} }
        function tip:AddLine(value) self.lines[#self.lines + 1] = value end
        function tip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. ": " .. right end
        f.provider.tooltip(widget, tip); return table.concat(tip.lines, "\n")
    end
    assert(text():find("Social is disabled by the game.", 1, true))
    f.rule = false; f.provider.update(widget)
    assert(not text():find("disabled", 1, true), "A recovered permission must remove the previous denial")
    f.provider.click(widget, "LeftButton"); equal(#f.clicks, 1); f:masked()
end)

check("WoW presence uses known GUID transitions even when simultaneous changes leave the count unchanged", function()
    local f = fixture(); local widget = f:widget()
    local icon, label, point = widget.socialIcon, widget.label:GetText(), widget.label.points[1][4]
    equal(widget.jiggles, nil)
    f:notify(widget, "FRIENDLIST_UPDATE"); equal(widget.jiggles, nil)
    f.wowFriends[1].connected, f.wowFriends[2].connected = false, true
    f:notify(widget, "FRIENDLIST_UPDATE")
    equal(widget.jiggles, 1); equal(widget.jiggledTexture, icon)
    equal(widget.label:GetText(), label); equal(widget.label.points[1][4], point)
    f.wowFriends[1], f.wowFriends[2] = f.wowFriends[2], f.wowFriends[1]
    f:notify(widget, "FRIENDLIST_UPDATE"); equal(widget.jiggles, 1)
    f.wowFriends[#f.wowFriends + 1] = { guid = "Player-3", connected = true }
    f:notify(widget, "FRIENDLIST_UPDATE"); equal(widget.jiggles, 1)
    table.remove(f.wowFriends, 1)
    f:notify(widget, "FRIENDLIST_UPDATE"); equal(widget.jiggles, 1)
end)

check("Battle.net explicit account events survive metadata ordering and simultaneous equal-count transitions", function()
    local f = fixture(); local widget = f:widget()
    f.bnFriends[1].gameAccountInfo.isOnline, f.bnFriends[2].gameAccountInfo.isOnline = false, true
    f:notify(widget, "BN_FRIEND_INFO_CHANGED", 2)
    f:notify(widget, "BN_FRIEND_ACCOUNT_ONLINE", 20, false)
    equal(widget.jiggles, 1)
    f:notify(widget, "BN_FRIEND_ACCOUNT_OFFLINE", 10, false)
    equal(widget.jiggles, 2)
    f:notify(widget, "BN_FRIEND_ACCOUNT_OFFLINE", 10, false)
    equal(widget.jiggles, 2)
    f:notify(widget, "BN_FRIEND_ACCOUNT_ONLINE", 2, false) -- List index is not an account ID.
    equal(widget.jiggles, 2)
    f.bnFriends[1].gameAccountInfo.isOnline = true
    f:notify(widget, "BN_FRIEND_ACCOUNT_ONLINE", 10, true)
    equal(widget.jiggles, 2)
    f:notify(widget, "BN_FRIEND_ACCOUNT_ONLINE", 10, false)
    equal(widget.jiggles, 3)
end)

check("initial population, added or removed friends, world changes and reconnections stay quiet", function()
    local f = fixture(); local widget = f:widget()
    f.bnFriends[3] = { bnetAccountID = 30, gameAccountInfo = { isOnline = true } }
    f:notify(widget, "BN_FRIEND_LIST_SIZE_CHANGED", 30)
    f:notify(widget, "BN_FRIEND_ACCOUNT_ONLINE", 30, false)
    table.remove(f.bnFriends, 1)
    f:notify(widget, "BN_FRIEND_LIST_SIZE_CHANGED", 10)
    f:notify(widget, "BN_FRIEND_ACCOUNT_OFFLINE", 10, false)
    equal(widget.jiggles, nil)
    f.connected = false; f:notify(widget, "BN_DISCONNECTED", false, false)
    f.bnFriends[1].gameAccountInfo.isOnline = true
    f.connected = true; f:notify(widget, "BN_CONNECTED", false)
    f:notify(widget, "BN_FRIEND_ACCOUNT_ONLINE", 20, false)
    equal(widget.jiggles, nil)
    f.bnFriends[1].gameAccountInfo.isOnline = false
    f:notify(widget, "PLAYER_ENTERING_WORLD", false, false)
    f:notify(widget, "BN_FRIEND_ACCOUNT_OFFLINE", 20, false)
    f.wowFriends[1].connected = false
    f:notify(widget, "LEGACY_FRIEND_SYSTEM_STATUS_UPDATED")
    f:notify(widget, "FRIENDLIST_UPDATE")
    equal(widget.jiggles, nil)
end)

check("unavailable or restricted WoW identities never become fabricated presence changes", function()
    for _, kind in ipairs({ "missing", "restricted-info", "restricted-guid", "restricted-state", "missing-guid", "duplicate", "oversize", "throw" }) do
        local f = fixture(); local widget = f:widget(); local first = f.wowFriends[1]
        if kind == "missing" then f.wowUnavailable = true
        elseif kind == "restricted-info" then f.wowFriends[1] = f.secret
        elseif kind == "restricted-guid" then first.guid = f.secret
        elseif kind == "restricted-state" then first.connected = f.secret
        elseif kind == "missing-guid" then first.guid = nil
        elseif kind == "duplicate" then f.wowFriends[2].guid = first.guid
        elseif kind == "oversize" then f.wowTotal = 10001
        else f.wowError = true end
        f:notify(widget, "FRIENDLIST_UPDATE"); equal(widget.jiggles, nil, kind)
        f.wowUnavailable, f.wowError, f.wowTotal = false, false, nil
        f.wowFriends = { { guid = "Player-1", connected = false }, { guid = "Player-2", connected = true } }
        f:notify(widget, "FRIENDLIST_UPDATE"); equal(widget.jiggles, nil, kind)
        f.wowFriends[1].connected = true
        f:notify(widget, "FRIENDLIST_UPDATE"); equal(widget.jiggles, 1, kind)
    end
end)

check("Battle.net rejects restricted, missing or mismatched data instead of trusting an event alone", function()
    for _, kind in ipairs({ "missing", "restricted-info", "restricted-id", "restricted-game", "restricted-state", "missing-state", "disconnected", "restricted-connection", "missing-live", "bad-event", "companion", "wrong-state" }) do
        local f = fixture(); local widget = f:widget()
        f.bnFriends[2].gameAccountInfo.isOnline = true
        local id, companion = 20, false
        if kind == "missing" then f.bnUnavailable = true
        elseif kind == "restricted-info" then f.bnFriends[2] = f.secret
        elseif kind == "restricted-id" then f.bnFriends[2].bnetAccountID = f.secret
        elseif kind == "restricted-game" then f.bnFriends[2].gameAccountInfo = f.secret
        elseif kind == "restricted-state" then f.bnFriends[2].gameAccountInfo.isOnline = f.secret
        elseif kind == "missing-state" then f.bnFriends[2].gameAccountInfo.isOnline = nil
        elseif kind == "disconnected" then f.connected = false
        elseif kind == "restricted-connection" then f.connected = f.secret
        elseif kind == "missing-live" then f.bnByIDUnavailable = true
        elseif kind == "bad-event" then id = f.secret
        elseif kind == "companion" then companion = f.secret
        else f.bnFriends[2].gameAccountInfo.isOnline = false end
        f:notify(widget, "BN_FRIEND_ACCOUNT_ONLINE", id, companion)
        equal(widget.jiggles, nil, kind)
    end
end)

check("notification baselines are per instance, reset safely and remain optional on older cores", function()
    local f = fixture(); local first, second = f:widget(), f:widget()
    assert(first.socialPresence ~= second.socialPresence)
    assert(first.socialPresence.wow ~= second.socialPresence.wow)
    f.wowFriends[1].connected = false
    f:notify(first, "FRIENDLIST_UPDATE"); equal(first.jiggles, 1); equal(second.jiggles, nil)
    f:notify(second, "FRIENDLIST_UPDATE"); equal(second.jiggles, 1)
    f.provider.reset(first); equal(first.socialPresence, nil); equal(first.stops, 1)
    f:notify(first, "FRIENDLIST_UPDATE"); equal(first.jiggles, 1)
    local old = f:widget(); old.JiggleIcon, old.StopIconJiggle = nil, nil
    f.wowFriends[1].connected = true
    f:notify(old, "FRIENDLIST_UPDATE"); f.provider.destroy(old)
    equal(old.socialPresence, nil)
end)

check("steady aggregate-count polling does not enumerate contact lists or consume transitions", function()
    local f = fixture(); local widget = f:widget()
    local wowReads, bnReads = f.wowReads, f.bnReads
    f.wowFriends[1].connected = false; f.bnFriends[2].gameAccountInfo.isOnline = true
    for _ = 1, 20 do f.provider.update(widget) end
    equal(f.wowReads, wowReads); equal(f.bnReads, bnReads); equal(widget.jiggles, nil)
    f:notify(widget, "FRIENDLIST_UPDATE"); equal(widget.jiggles, 1)
    f:notify(widget, "BN_FRIEND_ACCOUNT_ONLINE", 20, false); equal(widget.jiggles, 2)
end)

check("known indexed metadata reads one account and preserves pending true and false transitions", function()
    local f = fixture(); f.bnFriends = {}
    for index = 1, 100 do
        f.bnFriends[index] = { bnetAccountID = index + 1000,
            gameAccountInfo = { isOnline = index % 2 == 1 } }
    end
    local widget = f:widget(); local reads = f.bnReads
    f.bnFriends[1].gameAccountInfo.isOnline, f.bnFriends[2].gameAccountInfo.isOnline = false, true
    for index = 1, 100 do f:notify(widget, "BN_FRIEND_INFO_CHANGED", index) end
    equal(f.bnReads - reads, 100, "A per-friend metadata burst must not rescan the roster")
    equal(widget.socialPresence.bnet[1001], true); equal(widget.socialPresence.bnet[1002], false)
    equal(widget.jiggles, nil)
    f:notify(widget, "BN_FRIEND_ACCOUNT_ONLINE", 1002, false); equal(widget.jiggles, 1)
    f:notify(widget, "BN_FRIEND_ACCOUNT_OFFLINE", 1001, false); equal(widget.jiggles, 2)
    f:notify(widget, "BN_FRIEND_ACCOUNT_OFFLINE", 1001, false); equal(widget.jiggles, 2)
end)

check("metadata broad invalidation seeds quietly while invalid indexed results never trigger a fallback scan", function()
    local f = fixture(); local widget = f:widget(); local reads = f.bnReads
    f:notify(widget, "BN_FRIEND_INFO_CHANGED")
    equal(f.bnReads - reads, #f.bnFriends); equal(widget.jiggles, nil)
    widget.socialPresence.bnet = nil; reads = f.bnReads
    f:notify(widget, "BN_FRIEND_INFO_CHANGED", 2)
    assert(f.bnReads - reads >= #f.bnFriends and f.bnReads - reads <= #f.bnFriends + 1)
    equal(widget.socialPresence.bnet[20], false); equal(widget.jiggles, nil)
    f.bnFriends[3] = { bnetAccountID = 30, gameAccountInfo = { isOnline = true } }; reads = f.bnReads
    f:notify(widget, "BN_FRIEND_INFO_CHANGED", 3)
    assert(f.bnReads - reads >= #f.bnFriends and f.bnReads - reads <= #f.bnFriends + 1)
    equal(widget.socialPresence.bnet[30], true); equal(widget.jiggles, nil)
    f:notify(widget, "BN_FRIEND_ACCOUNT_ONLINE", 30, false); equal(widget.jiggles, nil)
    table.remove(f.bnFriends, 1)
    f:notify(widget, "BN_FRIEND_LIST_SIZE_CHANGED", 10)
    equal(widget.socialPresence.bnet[10], nil); equal(widget.jiggles, nil)

    for _, kind in ipairs({ "zero", "negative", "fraction", "infinite", "nan", "oversize", "string", "restricted" }) do
        local current = fixture(); local owner = current:widget(); local index = 2
        if kind == "zero" then index = 0
        elseif kind == "negative" then index = -1
        elseif kind == "fraction" then index = 1.5
        elseif kind == "infinite" then index = math.huge
        elseif kind == "nan" then index = 0 / 0
        elseif kind == "oversize" then index = 10001
        elseif kind == "string" then index = "2"
        else index = current.secret end
        reads = current.bnReads
        current:notify(owner, "BN_FRIEND_INFO_CHANGED", index)
        equal(current.bnReads, reads, kind); equal(owner.socialPresence.bnet, nil, kind)
        equal(owner.jiggles, nil, kind)
        current:notify(owner, "BN_FRIEND_INFO_CHANGED", 2)
        equal(owner.socialPresence.bnet[20], false); equal(owner.jiggles, nil)
        current.bnFriends[2].gameAccountInfo.isOnline = true
        current:notify(owner, "BN_FRIEND_ACCOUNT_ONLINE", 20, false); equal(owner.jiggles, 1, kind)
    end

    for _, kind in ipairs({ "missing", "restricted-info", "restricted-id", "restricted-game", "restricted-state", "malformed-state", "throw" }) do
        local current = fixture(); local owner = current:widget(); local info = current.bnFriends[2]
        local getter = current.env.C_BattleNet.GetFriendAccountInfo
        if kind == "missing" then current.bnUnavailable = true
        elseif kind == "restricted-info" then current.bnFriends[2] = current.secret
        elseif kind == "restricted-id" then info.bnetAccountID = current.secret
        elseif kind == "restricted-game" then info.gameAccountInfo = current.secret
        elseif kind == "restricted-state" then info.gameAccountInfo.isOnline = current.secret
        elseif kind == "malformed-state" then info.gameAccountInfo.isOnline = "online"
        else current.env.C_BattleNet.GetFriendAccountInfo = function()
            current.bnReads = current.bnReads + 1; error("indexed account unavailable", 0)
        end end
        reads = current.bnReads
        current:notify(owner, "BN_FRIEND_INFO_CHANGED", 2)
        equal(current.bnReads - reads, 1, kind); equal(owner.socialPresence.bnet, nil, kind)
        equal(owner.jiggles, nil, kind)
        current.bnUnavailable = false; current.env.C_BattleNet.GetFriendAccountInfo = getter
        current.bnFriends[2] = { bnetAccountID = 20, gameAccountInfo = { isOnline = false } }
        current:notify(owner, "BN_FRIEND_INFO_CHANGED", 2)
        equal(owner.socialPresence.bnet[20], false); equal(owner.jiggles, nil)
        current.bnFriends[2].gameAccountInfo.isOnline = true
        current:notify(owner, "BN_FRIEND_ACCOUNT_ONLINE", 20, false); equal(owner.jiggles, 1, kind)
    end
end)

print(passed .. " Social public-contract tests passed")
