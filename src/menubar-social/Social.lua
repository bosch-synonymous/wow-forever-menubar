-- Original Social provider. Blizzard retains its button's lifecycle and chat anchors.
local function public(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function object(value)
    return public(value) and (type(value) == "table" or type(value) == "userdata")
end

local function call(method, ...)
    if not public(method) or type(method) ~= "function" then return nil, false end
    local ok, value = pcall(method, ...)
    if not ok or not public(value) then return nil, false end
    return value, true
end

local function integer(value)
    return public(value) and type(value) == "number" and value >= 0
        and value < math.huge and value == math.floor(value)
end

local function alpha(value)
    return public(value) and type(value) == "number" and value == value and value >= 0 and value <= 1
end

local function whole(value) return string.format("%.0f", value) end

local function errorText(reason)
    if not public(reason) then return "details restricted" end
    local ok, text = pcall(tostring, reason)
    return ok and text or "details unavailable"
end

local function snapshot()
    local result = {}
    if type(BNGetNumFriends) == "function" then
        local ok, _, online = pcall(BNGetNumFriends)
        if ok and integer(online) then result.bnet = online end
    end
    if object(C_FriendList) then
        local legacy = call(C_FriendList.IsLegacyFriendSystemEnabled)
        if legacy == false then result.wow = 0
        elseif legacy == true then
            local online = call(C_FriendList.GetNumOnlineFriends)
            if integer(online) then result.wow = online end
        end
    end
    if result.bnet ~= nil and result.wow ~= nil then
        local total = result.bnet + result.wow
        if integer(total) then result.total = total end
    end
    return result
end

-- Counts cannot identify simultaneous logins/logouts. Keep only complete public
-- presence snapshots, scoped to this widget, and compare stable friend identities.
local function wowPresence()
    if not object(C_FriendList) then return nil end
    local legacy = call(C_FriendList.IsLegacyFriendSystemEnabled)
    if legacy == false then return {} end
    if legacy ~= true then return nil end
    local total = call(C_FriendList.GetNumFriends)
    if not integer(total) or total > 10000 then return nil end
    local result = {}
    for index = 1, total do
        local info = call(C_FriendList.GetFriendInfoByIndex, index)
        if not object(info) then return nil end
        local guid, connected = info.guid, info.connected
        if not public(guid) or type(guid) ~= "string" or guid == "" or not public(connected)
            or type(connected) ~= "boolean" or result[guid] ~= nil then return nil end
        result[guid] = connected
    end
    return result
end

local function bnetOnline(info, expectedID)
    if not object(info) then return nil end
    local id, game = info.bnetAccountID, info.gameAccountInfo
    if not integer(id) or id == 0 or (expectedID and id ~= expectedID) or not object(game) then return nil end
    local online = game.isOnline
    if public(online) and type(online) == "boolean" then return online, id end
end

local function bnetPresence()
    if call(BNConnected) ~= true or not object(C_BattleNet) then return nil end
    local total = call(BNGetNumFriends)
    if not integer(total) or total > 10000 then return nil end
    local result = {}
    for index = 1, total do
        local info = call(C_BattleNet.GetFriendAccountInfo, index)
        local online, id = bnetOnline(info)
        if online == nil or result[id] ~= nil then return nil end
        result[id] = online
    end
    return result
end

local function retainKnownPresence(previous, current)
    if previous and current then
        for id, online in pairs(previous) do
            if current[id] ~= nil then current[id] = online end
        end
    end
    return current
end

local function bnetMetadata(previous, index)
    if not public(index) then return nil end
    -- A nil index is the native contract's broad metadata invalidation.
    if index == nil then return retainKnownPresence(previous, bnetPresence()) end
    if not integer(index) or index == 0 or index > 10000 then return nil end
    if call(BNConnected) ~= true or not object(C_BattleNet) then return nil end
    local info = call(C_BattleNet.GetFriendAccountInfo, index)
    local online, id = bnetOnline(info)
    if online == nil then return nil end
    -- Known per-friend metadata must not consume the explicit online/offline
    -- transition. Rebuilding the whole roster for each such event is wasteful.
    if previous and previous[id] ~= nil then return previous end
    return retainKnownPresence(previous, bnetPresence())
end

local function presence(widget)
    local state = widget.socialPresence
    if not state or state.settings ~= widget.settings then
        state = { settings = widget.settings, wow = wowPresence(), bnet = bnetPresence() }
        widget.socialPresence = state
    end
    return state
end

local function jiggle(widget)
    local animate = widget.JiggleIcon
    if public(animate) and type(animate) == "function" then animate(widget, widget.socialIcon) end
end

local function event(widget, name, friendID, companion)
    if not public(name) or type(name) ~= "string" then return end
    local state = presence(widget)
    if name == "PLAYER_ENTERING_WORLD" then
        state.wow, state.bnet = wowPresence(), bnetPresence()
    elseif name == "LEGACY_FRIEND_SYSTEM_STATUS_UPDATED" then
        state.wow = wowPresence()
    elseif name == "FRIENDLIST_UPDATE" then
        local previous, current = state.wow, wowPresence()
        state.wow = current
        if previous and current then
            for guid, online in pairs(current) do
                if previous[guid] ~= nil and previous[guid] ~= online then jiggle(widget); break end
            end
        end
    elseif name == "BN_CONNECTED" or name == "BN_DISCONNECTED" then
        -- Connection/population changes are not an individual friend's transition.
        state.bnet = nil
    elseif name == "BN_FRIEND_LIST_SIZE_CHANGED" then
        -- Metadata/list events can precede a presence event. Seed new identities
        -- silently without consuming a known friend's explicit transition.
        state.bnet = retainKnownPresence(state.bnet, bnetPresence())
    elseif name == "BN_FRIEND_INFO_CHANGED" then
        -- This event carries a roster index, rather than an account ID.
        state.bnet = bnetMetadata(state.bnet, friendID)
    elseif name == "BN_FRIEND_ACCOUNT_ONLINE" or name == "BN_FRIEND_ACCOUNT_OFFLINE" then
        local previous, current = state.bnet, bnetPresence()
        local observed
        if current and integer(friendID) and friendID > 0 then observed = current[friendID] end
        state.bnet = retainKnownPresence(previous, current)
        if not previous or not current or not integer(friendID) or friendID == 0
            or not public(companion) or (companion ~= nil and type(companion) ~= "boolean") or companion == true then return end
        local expected = name == "BN_FRIEND_ACCOUNT_ONLINE"
        local live
        if object(C_BattleNet) then live = bnetOnline(call(C_BattleNet.GetAccountInfoByID, friendID), friendID) end
        if observed == expected and live == expected then
            state.bnet[friendID] = expected
            if previous[friendID] ~= nil and previous[friendID] ~= expected then jiggle(widget) end
        end
    end
end

local function nativeButton()
    if object(QuickJoinToastButton) then return QuickJoinToastButton end
end

local function action()
    if not public(C_GameRules) then return nil, nil, "Social permissions are unavailable." end
    local rules = object(C_GameRules) and C_GameRules.IsGameRuleActive
    local flags = object(Enum) and Enum.GameRule
    local disabled = object(flags) and flags.IngameFriendsListDisabled
    if C_GameRules ~= nil then
        if not public(rules) or type(rules) ~= "function" then return nil, nil, "Social permissions are unavailable." end
        if not integer(disabled) then return nil, nil, "Social permissions are unavailable." end
        local denied, available = call(rules, disabled)
        if not available or type(denied) ~= "boolean" then return nil, nil, "Social permissions are unavailable." end
        if denied then return nil, nil, "Social is disabled by the game." end
    end
    local button = nativeButton()
    if button then
        if not public(button.IsEnabled) then return nil, nil, "Social is currently unavailable." end
        if type(button.IsEnabled) == "function" then
            local enabled = call(button.IsEnabled, button)
            if enabled ~= true then return nil, nil, "Social is currently unavailable." end
        end
        if not public(button.OnClick) then return nil, nil, "Social controls are unavailable." end
        if type(button.OnClick) == "function" then return button.OnClick, button end
    end
    if public(ToggleFriendsFrame) and type(ToggleFriendsFrame) == "function" and integer(FRIEND_TAB_FRIENDS) then
        return ToggleFriendsFrame
    end
    return nil, nil, "Social controls are not available yet."
end

local function supportsDirectClick()
    return object(Menubar.CAPABILITIES) and public(Menubar.CAPABILITIES.directClick)
        and Menubar.CAPABILITIES.directClick == true
end

-- Each healthy widget owns a request; the last release restores borrowed state.
-- Alpha preserves native OnShow/OnHide semantics. Input is disabled before alpha
-- reaches zero, and restored only after the native surface is visible again.
local requests, masks = {}, {}
local monitor, monitorReady, armed, elapsed, busy, nativeMessage
local synchronize

local function write(button, method, value)
    if type(button[method]) ~= "function" then return false end
    if method == "EnableMouse" and call(button.CanChangeProtectedState, button) ~= true then return false end
    local ok, result = pcall(button[method], button, value)
    return ok and public(result) and result ~= false
end

local function restore(button, saved)
    local current = call(button.GetAlpha, button)
    if not alpha(current) then return false end
    -- A newer nonzero alpha belongs to the client or another addon.
    if current == 0 and saved.alpha ~= 0 then
        if not write(button, "SetAlpha", saved.alpha) or call(button.GetAlpha, button) ~= saved.alpha then return false end
    end
    local mouse = call(button.IsMouseEnabled, button)
    if type(mouse) ~= "boolean" then return false end
    if not mouse and saved.mouse then
        if not write(button, "EnableMouse", true) or call(button.IsMouseEnabled, button) ~= true then return false end
    end
    masks[button] = nil
    return true
end

local function mask(button)
    local current = call(button.GetAlpha, button)
    local mouse = call(button.IsMouseEnabled, button)
    if not alpha(current) or type(mouse) ~= "boolean" or type(button.SetAlpha) ~= "function" then return false end
    local saved = masks[button]
    if not saved then saved = { alpha = current, mouse = mouse }; masks[button] = saved end
    if current ~= 0 then saved.alpha = current end
    if mouse then saved.mouse = true end
    if mouse and not write(button, "EnableMouse", false) then return false end
    if call(button.IsMouseEnabled, button) ~= false then return false end
    if current ~= 0 and not write(button, "SetAlpha", 0) then return false end
    return call(button.GetAlpha, button) == 0
end

local function reconcile(ready)
    local method = action()
    local desired = ready and next(requests) and supportsDirectClick() and method and nativeButton() or nil
    -- Do not mutate borrowed UI during combat or an unreadable combat state.
    if call(InCombatLockdown) ~= false then
        nativeMessage = (desired or next(masks)) and "Chat button changes are waiting until combat ends." or nil
        return
    end
    local complete = true
    for button, saved in pairs(masks) do
        if button ~= desired and not restore(button, saved) then complete = false end
    end
    if desired and not mask(desired) then
        complete = false
        -- Failed input/alpha changes must not leave an invisible input surface.
        if masks[desired] then restore(desired, masks[desired]) end
    end
    nativeMessage = not complete and "The chat Social button could not be restored/hidden; it will retry."
        or (next(requests) and not desired and "The chat Social button is not available yet.") or nil
end

local function changed()
    if not busy and (next(requests) or next(masks)) then synchronize() end
end

local function armMonitor()
    if not monitor then monitor = CreateFrame("Frame") end
    if not monitorReady then
        monitor:SetScript("OnEvent", changed)
        monitor:SetScript("OnUpdate", function(_, delta)
            if not public(delta) or type(delta) ~= "number" or delta ~= delta or delta < 0 or delta == math.huge then return end
            elapsed = (elapsed or 0) + delta
            if elapsed >= 0.25 then elapsed = 0; changed() end
        end)
        monitorReady = true
    end
    if not armed then
        for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
            pcall(monitor.RegisterEvent, monitor, event)
        end
    end
    monitor:Show()
    armed = true
end

synchronize = function()
    if busy then return end
    -- Arrange the retry owner before borrowing any native state.
    busy = true
    local ready = true
    if (next(requests) or next(masks)) and not (monitorReady and armed) then ready = pcall(armMonitor) end
    -- Restoration remains possible even if retry setup itself was rejected.
    local ok = pcall(reconcile, ready)
    busy = false
    if not ready or not ok then nativeMessage = "Chat Social button changes failed; they will retry." end
    if not next(requests) and not next(masks) and monitor and armed then
        monitor:UnregisterAllEvents()
        monitor:Hide()
        armed, elapsed = false, 0
    end
end

local function release(widget)
    requests[widget] = nil
    if next(masks) or armed then synchronize() end
end

local function request(widget)
    local method = action()
    if widget.settings.hideChatButton ~= false and supportsDirectClick() and method then requests[widget] = true
    else requests[widget] = nil end
    if next(requests) or next(masks) or armed then synchronize() end
end

local function destroy(widget)
    widget.socialPresence = nil
    local stop = widget.StopIconJiggle
    if public(stop) and type(stop) == "function" then stop(widget) end
    release(widget)
    if widget.socialIcon then widget.socialIcon:Hide() end
    widget.customWidth = nil
    widget.label:ClearAllPoints()
    widget.label:SetPoint("CENTER", widget.content or widget.frame, "CENTER")
end

local function notificationAtlas()
    local button = nativeButton()
    local toast = button and button.displayedToast
    if object(toast) then
        if public(button.isLFGList) and button.isLFGList == true then return "quickjoin-button-group-up", true end
        return "quickjoin-button-quickjoin-up", true
    end
    return "quickjoin-button-friendslist-up", false
end

local function render(widget)
    local data = snapshot()
    local count = data.total and whole(data.total) or "--"
    local value = widget.settings.showCount ~= false and count or ""
    if widget.settings.showLabel then value = "Social" .. (value ~= "" and (" " .. value) or "") end
    local icon = widget.socialIcon
    if not icon then icon = widget.frame:CreateTexture(nil, "ARTWORK"); widget.socialIcon = icon end
    local iconHeight = widget.content and math.min(18, widget.content:GetHeight()) or 18
    if not widget.socialIconReady or widget.socialIconHeight ~= iconHeight then
        icon:SetSize(iconHeight, iconHeight)
        widget.socialIconHeight = iconHeight
    end
    if not widget.socialIconReady then
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", (widget.content or widget.frame), "LEFT", 3, 0)
        widget.socialIconReady = true
    end
    local atlas, notification = notificationAtlas()
    local glyph = "social"
    if notification then
        glyph = atlas == "quickjoin-button-group-up" and "social-group" or "social-alert"
    end
    local accepted = Menubar.ApplyThemeIcon and Menubar:ApplyThemeIcon(icon, glyph, widget.label)
    if not Menubar.ApplyThemeIcon and type(icon.SetAtlas) == "function" then
        local ok, result = pcall(icon.SetAtlas, icon, atlas)
        accepted = ok and public(result) and result ~= false
        if accepted and type(icon.GetAtlas) == "function" then
            local actual = call(icon.GetAtlas, icon)
            -- Native atlas readback may use canonical capitalization.
            accepted = type(actual) == "string" and actual:lower() == atlas:lower()
        end
    end
    if accepted then icon:Show()
    else icon:Hide(); if value == "" or not widget.settings.showLabel then value = "Social" .. (value ~= "" and (" " .. value) or "") end end
    widget:SetText("Social" .. (widget.settings.showCount ~= false and (" " .. count) or ""))
    widget.label:SetText(value)
    widget.label:ClearAllPoints()
    widget.label:SetPoint("LEFT", (widget.content or widget.frame), "LEFT", accepted and 24 or 4, 0)
    local width = (accepted and 25 or 8) + (value ~= "" and widget.label:GetStringWidth() or 0)
    if widget.customWidth ~= width then widget:SetWidth(width) end
    request(widget)
end

local function update(widget)
    local ok, reason = pcall(render, widget)
    if not ok then pcall(destroy, widget); error(reason, 0) end
    presence(widget)
end

local function click(widget)
    local method, button = action()
    widget.socialMessage = nil
    if not method then release(widget); return end
    local ok, reason
    if button then ok, reason = pcall(method, button, "LeftButton")
    else ok, reason = pcall(method, FRIEND_TAB_FRIENDS) end
    if not ok then pcall(release, widget); error(reason, 0) end
    widget.socialFailureReported = nil
end

local function contextMenu(widget, root)
    local open = function()
        -- Menu responders outlive Host:Call(contextMenu); isolate their action too.
        local ok, reason = pcall(click, widget)
        if not ok then
            pcall(destroy, widget)
            widget.socialMessage = "Social action failed: " .. errorText(reason)
            if widget.socialFailureReported ~= widget.socialMessage then
                widget.socialFailureReported = widget.socialMessage
                if type(Menubar.Print) == "function" then pcall(Menubar.Print, widget.socialMessage) end
            end
        end
    end
    -- New hosts invalidate responders on native menu release and widget
    -- lifetime changes. Older hosts retain their existing isolated action.
    if type(widget.MenuCallback) == "function" then open = widget:MenuCallback(open) end
    root:CreateButton("Open Social", open)
end

local function tooltip(widget, tip)
    local data = snapshot()
    tip:AddLine("Social")
    tip:AddLine("Better with company.", 1, 1, 1)
    tip:AddDoubleLine("Friends online", data.total and whole(data.total) or "Unavailable")
    tip:AddDoubleLine("Battle.net", data.bnet and whole(data.bnet) or "Unavailable")
    tip:AddDoubleLine("WoW friends", data.wow and whole(data.wow) or "Unavailable")
    local _, notification = notificationAtlas()
    if notification then tip:AddLine("A social notification is waiting.", 1, 0.82, 0, true) end
    local _, _, message = action()
    if message or widget.socialMessage then tip:AddLine(message or widget.socialMessage, 1, 0.4, 0.4, true) end
    if widget.settings.hideChatButton ~= false then
        if not supportsDirectClick() then tip:AddLine("Update Menubar core for direct access and chat button replacement.", 1, 0.82, 0, true)
        elseif nativeMessage then tip:AddLine(nativeMessage, 0.65, 0.65, 0.65, true) end
    end
end

Menubar:RegisterWidgetType({
    id = "social", name = "Social", clickHint = "Open Social",
    retainOnDisable = true,
    defaults = { showCount = true, showLabel = false, hideChatButton = true},
    defaultPlacement = { bar = "top", alignment = "right", order = 6, sidebarOrder = 6 },
    interval = 1,
    events = { "FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED",
        "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_CONNECTED", "BN_DISCONNECTED",
        "LEGACY_FRIEND_SYSTEM_STATUS_UPDATED", "SOCIAL_QUEUE_UPDATE", "PLAYER_ENTERING_WORLD" },
    settings = {
        { key = "showCount", label = "Show online friend count", type = "toggle" },
        { key = "showLabel", label = "Show Social label", type = "toggle" },
        { key = "hideChatButton", label = "Hide chat Social button", type = "toggle" },
    },
    update = update, event = event, click = click, tooltip = tooltip, contextMenu = contextMenu,
    reset = destroy, deactivate = destroy, destroy = destroy,
})
