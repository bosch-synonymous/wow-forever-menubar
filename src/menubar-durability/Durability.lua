-- Original equipped-durability provider. Blizzard artwork is referenced in the client.
local texturePath = "Interface\\Durability\\UI-Durability-Icons"
local repairAtlas = "SpellIcon-256x256-Repair"
-- Facts from Forever's durability XML: inventory slot, label, native alert index,
-- and texture crop. Native alert indices are not inventory slot IDs.
local slots = {
    { id = 1, name = "Head", uv = { 0, 0.140625, 0, 0.171875 } },
    { id = 3, name = "Shoulders", uv = { 0.140625, 0.515625, 0, 0.171875 } },
    { id = 5, name = "Chest", uv = { 0.515625, 0.6640625, 0, 0.171875 } },
    { id = 6, name = "Waist", uv = { 0.328125, 0.46875, 0.171875, 0.203125 } },
    { id = 7, name = "Legs", uv = { 0.46875, 0.6875, 0.171875, 0.3203125 } },
    { id = 8, name = "Feet", uv = { 0.6875, 1, 0.171875, 0.4140625 } },
    { id = 9, name = "Wrists", uv = { 0.6640625, 1, 0, 0.171875 } },
    { id = 10, name = "Hands", uv = { 0, 0.328125, 0.171875, 0.3046875 } },
    { id = 16, name = "Main hand", uv = { 0, 0.140625, 0.3203125, 0.6640625 } },
    { id = 17, name = "Off hand", uv = { 0.1875, 0.375, 0.3203125, 0.5546875 } },
    { id = 18, name = "Ranged", uv = { 0.1875, 0.3984375, 0.5546875, 0.84375 } },
}
local colors = { { 1, 0.82, 0.18 }, { 0.93, 0.07, 0.07 } }

local function public(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function number(value)
    return public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function integer(value, minimum)
    return number(value) and value >= minimum and value == math.floor(value)
end

local function percentage(ratio)
    -- Floor keeps a positive value below 100 from displaying as fully repaired.
    return tostring(math.floor(ratio * 100 + 0.0000001)) .. "%"
end

local function thresholds(settings)
    local warning, critical = settings.warningPercent, settings.criticalPercent
    if not number(warning) or warning < 0 or warning > 100 then warning = 20 end
    if not number(critical) or critical < 0 or critical > 100 then critical = 0 end
    return warning, math.min(warning, critical)
end

local function read(settings)
    local state = { items = {}, alerts = {}, incomplete = false, alertsUnknown = false }
    local total = 0
    local custom = public(settings.customThresholds) and settings.customThresholds == true
    local warning, critical = thresholds(settings)
    local canRead = public(GetInventoryItemDurability) and type(GetInventoryItemDurability) == "function"
    local canAlert = public(GetInventoryAlertStatus) and type(GetInventoryAlertStatus) == "function"
    for index, slot in ipairs(slots) do
        local item = { slot = slot, alert = 0 }
        state.items[index] = item
        local ok, current, maximum
        if canRead then ok, current, maximum = pcall(GetInventoryItemDurability, slot.id) end
        if not ok or not public(current) or not public(maximum) then
            state.incomplete = true
            item.unknown = true
        elseif current == nil and maximum == nil then
            item.absent = true -- Empty and non-durable slots have no durability pair.
        elseif integer(current, 0) and integer(maximum, 1) and current <= maximum then
            item.ratio = current / maximum
            total = total + item.ratio
            state.count = (state.count or 0) + 1
        else
            state.incomplete = true
            item.unknown = true
        end
        if custom then
            if item.ratio then
                if item.ratio <= critical / 100 then item.alert = 2
                elseif item.ratio <= warning / 100 then item.alert = 1 end
            end
        else
            local alertOK, alert
            if canAlert then alertOK, alert = pcall(GetInventoryAlertStatus, index) end
            if alertOK and integer(alert, 0) and alert <= 2 then
                item.alert = alert
            else
                state.alertsUnknown = true
            end
        end
        if item.alert > 0 then
            if item.ratio == nil then
                -- A native alert proves this slot needs attention even when its
                -- durability pair has not arrived; do not exclude it as empty.
                item.absent, item.unknown, state.incomplete = false, true, true
            end
            state.alerts[#state.alerts + 1] = item
        end
    end
    if not state.incomplete and state.count then state.average = total / state.count end
    return state
end

-- Borrow only presentation/input. Native alert events, shown state and managed
-- layout stay Blizzard-owned, including its independently interactive Edit Mode
-- selection child. One retry owner serves all requesting widget instances.
local nativeRequests, nativeMasks, nativeHooks = {}, {}, {}
local nativeMonitor, nativeReady, nativeArmed, nativeElapsed, nativeBusy, nativeWriting, nativeMessage
local synchronizeNative

local function nativeObject(value)
    return public(value) and (type(value) == "table" or type(value) == "userdata")
end

local function nativeCall(owner, method, ...)
    if not nativeObject(owner) or not public(owner[method]) or type(owner[method]) ~= "function" then return nil, false end
    local ok, value = pcall(owner[method], owner, ...)
    if ok and public(value) then return value, true end
    return nil, false
end

local function alpha(value) return number(value) and value >= 0 and value <= 1 end

local function nativeAllowed(frame)
    if not public(InCombatLockdown) or type(InCombatLockdown) ~= "function" then return false end
    local ok, combat = pcall(InCombatLockdown)
    return ok and public(combat) and combat == false and nativeCall(frame, "CanChangeProtectedState") == true
end

local function nativeWrite(frame, method, value)
    if not nativeAllowed(frame) or not public(frame[method]) or type(frame[method]) ~= "function" then return false end
    nativeWriting = frame
    local ok, result = pcall(frame[method], frame, value)
    nativeWriting = nil
    return ok and public(result) and result ~= false
end

local function restoreNative(frame, saved)
    local current, mouse = nativeCall(frame, "GetAlpha"), nativeCall(frame, "IsMouseEnabled")
    if not alpha(current) or type(mouse) ~= "boolean" then return false end
    if current == 0 and saved.alpha ~= nil and saved.alpha ~= 0 then
        if not nativeWrite(frame, "SetAlpha", saved.alpha) or nativeCall(frame, "GetAlpha") ~= saved.alpha then return false end
    end
    if mouse == false and saved.mouse == true then
        if not nativeWrite(frame, "EnableMouse", true) or nativeCall(frame, "IsMouseEnabled") ~= true then return false end
    end
    nativeMasks[frame] = nil
    return true
end

local function preview(frame)
    if not public(frame.isInEditMode) then return nil end
    if frame.isInEditMode == true then return true end
    if frame.isInEditMode ~= nil and frame.isInEditMode ~= false then return nil end
    local selection = frame.Selection
    if not nativeObject(selection) then return nil end
    local shown = nativeCall(selection, "IsShown")
    if type(shown) ~= "boolean" then return nil end
    if shown then return true end
    if not public(EditModeManagerFrame) then return nil end
    if EditModeManagerFrame ~= nil then
        if not nativeObject(EditModeManagerFrame) then return nil end
        local active, read = nativeCall(EditModeManagerFrame, "IsEditModeActive")
        if not read then return nil end
        if active == true then return true end
        if active ~= nil and active ~= false then return nil end
        if type(EditModeManagerFrame.IsEditModeActive) ~= "function" then return nil end
    end
    return false
end

local function nativeChanged()
    if not nativeBusy and (next(nativeRequests) or next(nativeMasks)) then synchronizeNative() end
end

local function observeNative(frame)
    if not public(hooksecurefunc) or type(hooksecurefunc) ~= "function" then return false end
    local hooks = nativeHooks[frame]
    if not hooks then hooks = {}; nativeHooks[frame] = hooks end
    for _, method in ipairs({ "SetAlpha", "EnableMouse", "UpdateShownState" }) do
        if hooks[method] == "failed" then return false end
        if not hooks[method] then
            if not public(frame[method]) or type(frame[method]) ~= "function" then return false end
            local name = method
            -- A native registration can attach its permanent callback before
            -- failing. Retain that uncertainty rather than attaching it again.
            hooks[name] = "failed"
            local ok, result = pcall(hooksecurefunc, frame, name, function()
                if nativeWriting == frame then return end
                local saved = nativeMasks[frame]
                if saved and name == "SetAlpha" then
                    local value = nativeCall(frame, "GetAlpha")
                    saved.alpha = alpha(value) and value or nil
                elseif saved and name == "EnableMouse" then
                    local value = nativeCall(frame, "IsMouseEnabled")
                    if type(value) == "boolean" then saved.mouse = value else saved.mouse = nil end
                end
                nativeChanged()
            end)
            if not ok or not public(result) or result == false then return false end
            hooks[name] = true
        end
    end
    return true
end

local function maskNative(frame)
    local current, mouse = nativeCall(frame, "GetAlpha"), nativeCall(frame, "IsMouseEnabled")
    if not alpha(current) or type(mouse) ~= "boolean" or not nativeAllowed(frame) or not observeNative(frame) then return false end
    local saved = nativeMasks[frame]
    if not saved then saved = { alpha = current, mouse = mouse }; nativeMasks[frame] = saved end
    if current ~= 0 then saved.alpha = current end
    if mouse then saved.mouse = true end
    if mouse and not nativeWrite(frame, "EnableMouse", false) then return false end
    if nativeCall(frame, "IsMouseEnabled") ~= false then return false end
    if current ~= 0 and not nativeWrite(frame, "SetAlpha", 0) then return false end
    return nativeCall(frame, "GetAlpha") == 0
end

local function armNative()
    if not nativeMonitor then nativeMonitor = CreateFrame("Frame") end
    if not nativeObject(nativeMonitor) then return false end
    if not nativeReady then
        nativeMonitor:SetScript("OnEvent", nativeChanged)
        nativeMonitor:SetScript("OnUpdate", function(_, elapsed)
            if not number(elapsed) or elapsed < 0 then return end
            nativeElapsed = (nativeElapsed or 0) + elapsed
            if nativeElapsed >= 0.25 then nativeElapsed = 0; nativeChanged() end
        end)
        nativeReady = true
    end
    if not nativeArmed then
        for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
            pcall(nativeMonitor.RegisterEvent, nativeMonitor, event)
        end
        nativeMonitor:Show()
        nativeArmed = true
    end
    return true
end

local function reconcileNative(ready)
    local frame = public(DurabilityFrame) and DurabilityFrame or nil
    local editing
    if nativeObject(frame) then editing = preview(frame) end
    local desired = ready and next(nativeRequests) and nativeObject(frame) and editing == false and frame or nil
    local complete = true
    for object, saved in pairs(nativeMasks) do
        if object ~= desired and not restoreNative(object, saved) then complete = false end
    end
    if desired and not maskNative(desired) then
        complete = false
        if nativeMasks[desired] then restoreNative(desired, nativeMasks[desired]) end
    end
    local observerFailed = false
    local hooks = desired and nativeHooks[desired]
    if hooks then
        for _, status in pairs(hooks) do
            if status == "failed" then observerFailed = true end
        end
    end
    nativeMessage = observerFailed and "Default durability warning control could not be enabled safely. Reload the UI to try again."
        or not complete and "Default durability warnings could not be hidden or restored; they will retry."
        or (next(nativeRequests) and not nativeObject(frame) and "Default durability warnings are not available yet.")
        or (next(nativeRequests) and editing == nil and "Default durability warning preview state is unavailable; it will retry.") or nil
end

synchronizeNative = function()
    if nativeBusy then return end
    nativeBusy = true
    local ready = true
    if next(nativeRequests) or next(nativeMasks) then
        local ok, result = pcall(armNative); ready = ok and result == true
    end
    local ok = pcall(reconcileNative, ready)
    nativeBusy = false
    if not ok or not ready then nativeMessage = "Default durability warning control is unavailable; it will retry." end
    if not next(nativeRequests) and not next(nativeMasks) and nativeMonitor and nativeArmed then
        pcall(nativeMonitor.Hide, nativeMonitor)
        pcall(nativeMonitor.UnregisterAllEvents, nativeMonitor)
        nativeArmed, nativeElapsed = false, 0
    end
end

local function releaseNative(widget)
    nativeRequests[widget] = nil
    if next(nativeMasks) or nativeArmed then synchronizeNative() end
end

local function requestNative(widget)
    if public(widget.settings.hideDefaultWarnings) and widget.settings.hideDefaultWarnings == true then nativeRequests[widget] = true
    else nativeRequests[widget] = nil end
    if next(nativeRequests) or next(nativeMasks) or nativeArmed then synchronizeNative() end
end

local function hideRegions(widget)
    if widget.durabilitySummaryIcon then widget.durabilitySummaryIcon:Hide() end
    for _, region in ipairs(widget.durabilityRegions or {}) do
        if region.icon then region.icon:Hide() end
        if region.label then region.label:Hide() end
    end
end

local function repairArtAvailable()
    if not public(C_Texture) then return false end
    if C_Texture == nil then return true end
    if type(C_Texture) ~= "table" then return false end
    local lookup = C_Texture.GetAtlasInfo
    if not public(lookup) then return false end
    if lookup == nil then return true end
    if type(lookup) ~= "function" then return false end
    local ok, info = pcall(lookup, repairAtlas)
    if not ok or not public(info) or type(info) ~= "table" then return false end
    local width, height = rawget(info, "width"), rawget(info, "height")
    return number(width) and width > 0 and number(height) and height > 0
end

local function summaryIcon(widget)
    if not repairArtAvailable() then return nil end
    local icon = widget.durabilitySummaryIcon
    if not icon then
        icon = widget.frame:CreateTexture(nil, "ARTWORK")
        widget.durabilitySummaryIcon = icon
    end
    icon:Hide()
    if type(icon.SetAtlas) ~= "function" then return nil end
    -- SetAtlas has no native return value; nil is success, not a missing icon.
    local accepted = icon:SetAtlas(repairAtlas, false)
    assert(public(accepted) and accepted ~= false, "Durability repair icon could not be applied")
    if type(icon.GetAtlas) == "function" then
        local actual = icon:GetAtlas()
        -- The native getter may canonicalize an accepted atlas name's casing.
        assert(public(actual) and type(actual) == "string" and actual:lower() == repairAtlas:lower(),
            "Durability repair icon could not be applied")
    end
    local height = math.min(16, widget.content and widget.content:GetHeight() or 16)
    icon:SetSize(height, height)
    icon:SetVertexColor(1, 1, 1, 1)
    icon:ClearAllPoints()
    icon:SetPoint("LEFT", (widget.content or widget.frame), "LEFT", 4, 0)
    return icon
end

local function resetPresentation(widget)
    hideRegions(widget)
    widget.customWidth = nil
    widget.label:ClearAllPoints()
    widget.label:SetPoint("CENTER", widget.content or widget.frame, "CENTER")
    widget.label:Show()
end

local function reset(widget)
    releaseNative(widget)
    resetPresentation(widget)
end

local function region(widget, index)
    widget.durabilityRegions = widget.durabilityRegions or {}
    local value = widget.durabilityRegions[index]
    if not value then value = {}; widget.durabilityRegions[index] = value end
    if not value.icon then value.icon = widget.frame:CreateTexture(nil, "ARTWORK") end
    if not value.label then value.label = widget.frame:CreateFontString(nil, "OVERLAY") end
    return value
end

local function styleLabel(widget, label)
    local path, size, flags = widget.label:GetFont()
    assert(label:SetFont(path, size, flags) == true, "Durability font could not be applied")
    label:SetWordWrap(false)
    if type(widget.label.GetShadowColor) == "function" then
        label:SetShadowColor(widget.label:GetShadowColor())
        label:SetShadowOffset(widget.label:GetShadowOffset())
    else
        label:SetShadowColor(0, 0, 0, 0)
        label:SetShadowOffset(0, 0)
    end
end

local function offhandUV()
    if not public(C_PaperDollInfo) or type(C_PaperDollInfo) ~= "table" then return nil end
    local method = C_PaperDollInfo.OffhandHasWeapon
    if not public(method) or type(method) ~= "function" then return nil end
    local ok, weapon = pcall(method)
    if ok and public(weapon) and weapon == true then return slots[9].uv end
end

local function render(widget)
    local state = read(widget.settings)
    resetPresentation(widget)
    if #state.alerts == 0 then
        widget.customWidth = nil
        local text = state.average and percentage(state.average) or (state.incomplete and "--" or "N/A")
        if state.alertsUnknown then text = text .. " ?" end
        widget:SetText("Durability " .. text)
        widget.label:SetText(text)
        local icon = summaryIcon(widget)
        if icon then
            widget.label:ClearAllPoints()
            widget.label:SetPoint("LEFT", (widget.content or widget.frame), "LEFT", 23, 0)
            widget:SetWidth(widget.label:GetStringWidth() + 27)
            icon:Show()
        else
            -- Missing optional artwork must not hide a readable percentage.
            widget:SetWidth(math.max(18, widget.label:GetStringWidth() + 8))
        end
        return
    end
    local position, summary = 4, {}
    for index, item in ipairs(state.alerts) do
        local value = region(widget, index)
        local uv = item.slot.id == 17 and offhandUV() or nil
        uv = uv or item.slot.uv
        local w, h = uv[2] - uv[1], uv[4] - uv[3]
        local height = math.min(16, widget.content and widget.content:GetHeight() or 16)
        local scale = height / math.max(w, h)
        assert(value.icon:SetTexture(texturePath) == true, "Durability icon could not be applied")
        value.icon:SetTexCoord(unpack(uv))
        value.icon:SetSize(w * scale, h * scale)
        value.icon:ClearAllPoints()
        value.icon:SetPoint("CENTER", (widget.content or widget.frame), "LEFT", position + 8, 0)
        local color = colors[item.alert]
        value.icon:SetVertexColor(color[1], color[2], color[3], 1)
        value.icon:Show()
        styleLabel(widget, value.label)
        local text = item.ratio and percentage(item.ratio) or "--"
        value.label:SetText(text)
        value.label:SetTextColor(color[1], color[2], color[3], 1)
        value.label:ClearAllPoints()
        value.label:SetPoint("LEFT", (widget.content or widget.frame), "LEFT", position + 19, 0)
        value.label:Show()
        position = position + 19 + value.label:GetStringWidth() + 7
        summary[#summary + 1] = item.slot.name .. " " .. text
    end
    widget:SetText("Durability: " .. table.concat(summary, ", "))
    local suffix = (state.incomplete and "--" or "") .. (state.alertsUnknown and " ?" or "")
    widget.label:SetText(suffix)
    if suffix ~= "" then
        widget.label:ClearAllPoints()
        widget.label:SetPoint("LEFT", (widget.content or widget.frame), "LEFT", position, 0)
        position = position + widget.label:GetStringWidth() + 4
    end
    widget:SetWidth(position - 3)
end

local function update(widget)
    -- Rendering failures remain diagnosable through the host; owned regions must
    -- first yield to its ordinary centered error label.
    local ok, reason = pcall(render, widget)
    if not ok then pcall(releaseNative, widget); pcall(resetPresentation, widget); error(reason, 0) end
    requestNative(widget)
end

local function tooltip(widget, tip)
    local state = read(widget.settings)
    tip:AddLine("Durability")
    tip:AddLine("Look after your gear.", 1, 1, 1)
    local average = state.average and percentage(state.average) or (state.incomplete and "Unavailable" or "No durable gear")
    tip:AddDoubleLine("Average remaining", average)
    tip:AddLine("Average of equipped durable items; each item counts equally.", 0.65, 0.65, 0.65, true)
    for _, item in ipairs(state.items) do
        if not item.absent then
            local color = colors[item.alert] or { 1, 1, 1 }
            tip:AddDoubleLine(item.slot.name, item.ratio and percentage(item.ratio) or "Unavailable", 1, 1, 1, color[1], color[2], color[3])
        end
    end
    if public(widget.settings.customThresholds) and widget.settings.customThresholds == true then
        local warning, critical = thresholds(widget.settings)
        tip:AddLine("Alerts: yellow <= " .. warning .. "%; red <= " .. critical .. "%.", 0.65, 0.65, 0.65, true)
        if number(widget.settings.criticalPercent) and number(widget.settings.warningPercent)
            and widget.settings.criticalPercent > widget.settings.warningPercent then
            tip:AddLine("Red threshold is capped at yellow.", 1, 0.82, 0.18, true)
        end
    else
        tip:AddLine("Alerts use WoW's yellow/red inventory status.", 0.65, 0.65, 0.65, true)
    end
    if state.incomplete then tip:AddLine("Some gear data is unavailable.", 1, 0.82, 0.18, true) end
    if state.alertsUnknown then tip:AddLine("WoW alert status unavailable; ? marks unknown alerts.", 1, 0.82, 0.18, true) end
    if nativeMessage then tip:AddLine(nativeMessage, 0.65, 0.65, 0.65, true) end
end

Menubar:RegisterWidgetType({
    id = "durability", name = "Durability",
    retainOnDisable = true,
    defaults = { customThresholds = true, warningPercent = 20, criticalPercent = 0, hideDefaultWarnings = true},
    legacyDefaults = { customThresholds = false, hideDefaultWarnings = false },
    defaultPlacement = { bar = "top", alignment = "right", order = 5, sidebarOrder = 5 },
    interval = 10,
    events = { "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "UPDATE_INVENTORY_DURABILITY", "UPDATE_INVENTORY_ALERTS" },
    settings = {
        { key = "hideDefaultWarnings", label = "Hide default durability warnings", type = "toggle" },
        { key = "customThresholds", label = "Use custom warning thresholds", type = "toggle" },
        { key = "warningPercent", label = "Custom yellow threshold (%)", type = "number", min = 0, max = 100, integer = true, enabledBy = "customThresholds" },
        { key = "criticalPercent", label = "Custom red threshold (%)", type = "number", min = 0, max = 100, integer = true, enabledBy = "customThresholds" },
    },
    update = update, reset = reset, deactivate = reset, destroy = reset, tooltip = tooltip,
})
