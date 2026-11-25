-- Original game-audio provider. Only public game CVars are read or changed.
local media = "Interface\\AddOns\\Menubar_Volume\\Media\\volume-"

local function public(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function number(value)
    if not public(value) or (type(value) ~= "number" and type(value) ~= "string") then return nil end
    local result = tonumber(value)
    if result and result == result and result > -math.huge and result < math.huge then return result end
end

local function cvarMethod(name, legacy)
    local modern = type(C_CVar) == "table" and C_CVar[name]
    if type(modern) == "function" then return modern end
    return type(legacy) == "function" and legacy or nil
end

local function getCVar(name)
    local method = cvarMethod("GetCVar", GetCVar)
    if not method then return nil end
    local ok, value = pcall(method, name)
    if ok and public(value) then return value end
end

local function readState()
    local volume = number(getCVar("Sound_MasterVolume"))
    if volume and (volume < 0 or volume > 1) then volume = nil end
    local enabled = number(getCVar("Sound_EnableAllSound"))
    if enabled == 0 then return volume, false end
    if enabled == 1 then return volume, true end
    return volume, nil
end

local function percentage(volume)
    return volume and math.floor(volume * 100 + 0.5) or nil
end

local function icon(volume, enabled)
    if not volume or volume == 0 or enabled == false then return "muted" end
    if volume <= 1 / 3 then return "low" end
    if volume <= 2 / 3 then return "medium" end
    return "high"
end

local function render(widget)
    local volume, enabled = readState()
    local value = ""
    if widget.settings.showPercent ~= false then
        local percent = percentage(volume)
        value = percent and (percent .. "%") or "--"
    end
    local speaker = widget.volumeIcon
    if not speaker then
        speaker = widget.frame:CreateTexture(nil, "ARTWORK")
        widget.volumeIcon = speaker
    end
    local iconHeight = widget.content and math.min(16, widget.content:GetHeight()) or 16
    if not widget.volumeIconReady or widget.volumeIconHeight ~= iconHeight then
        speaker:SetSize(iconHeight, iconHeight)
        widget.volumeIconHeight = iconHeight
    end
    if not widget.volumeIconReady then
        speaker:ClearAllPoints()
        speaker:SetPoint("LEFT", (widget.content or widget.frame), "LEFT", 4, 0)
        widget.volumeIconReady = true
    end
    local state = icon(volume, enabled)
    if not (Menubar.ApplyThemeIcon and Menubar:ApplyThemeIcon(speaker, "volume-" .. state, widget.label)) then
        speaker:SetTexture(media .. state .. ".tga")
        speaker:SetVertexColor(widget.label:GetTextColor())
    end
    speaker:Show()
    -- Keep the host's font and shadow, and reserve the icon alongside the percentage.
    widget.label:SetText(value)
    local width = 24 + (value ~= "" and (4 + widget.label:GetStringWidth()) or 0)
    if widget.customWidth ~= width then widget:SetWidth(width) end
    -- Overflow menus need a readable name even when this instance displays only its icon.
    widget:SetText(value ~= "" and ("Volume " .. value) or "Volume")
    widget.label:SetText(value)
    widget.label:ClearAllPoints()
    widget.label:SetPoint("LEFT", (widget.content or widget.frame), "LEFT", 24, 0)
end

local function destroy(widget)
    widget.volumeMenuToken = nil
    if widget.volumeIcon then widget.volumeIcon:Hide() end
    widget.customWidth = nil
    widget.label:ClearAllPoints()
    widget.label:SetPoint("CENTER", widget.content or widget.frame, "CENTER")
end

local function update(widget)
    local ok, reason = pcall(render, widget)
    if not ok then
        -- Restore ordinary host layout before it replaces failed content with an error label.
        destroy(widget)
        error(reason, 0)
    end
end

local function refresh(widget)
    if type(widget.Refresh) == "function" then widget:Refresh() else update(widget) end
end

local function writeCVar(widget, name, value)
    local method = cvarMethod("SetCVar", SetCVar)
    if not method then widget.volumeMessage = "Game audio controls are unavailable."; return false end
    local ok, result = pcall(method, name, tostring(value))
    if not ok or result == false then
        widget.volumeMessage = "The game did not accept that audio change."
        return false
    end
    local actual = number(getCVar(name))
    if not actual or math.abs(actual - value) > 0.0001 then
        widget.volumeMessage = "The game did not accept that audio change."
        return false
    end
    widget.volumeMessage = nil
    return true
end

local function setVolume(widget, percent)
    percent = number(percent)
    if not percent then return false end
    if readState() == nil then
        widget.volumeMessage = "Game audio controls are unavailable."
        refresh(widget)
        return false
    end
    percent = math.max(0, math.min(100, math.floor(percent + 0.5)))
    local ok = writeCVar(widget, "Sound_MasterVolume", percent / 100)
    refresh(widget)
    return ok
end

local function mouseWheel(widget, delta)
    delta = number(delta)
    local volume = readState()
    if not delta or delta == 0 or not volume then return end
    local step = number(widget.settings.wheelStep)
    if not step or step < 1 or step > 20 then step = 5 end
    local direction = delta > 0 and 1 or -1
    setVolume(widget, percentage(volume) + direction * math.floor(step))
end

local function currentOwner(widget, settings, instance, database)
    if widget.settings ~= settings or widget.instance ~= instance or Menubar.db ~= database or widget.failed then return false end
    local runtime = Menubar.runtime
    return type(runtime) ~= "table" or runtime[widget.id] == widget
end

local function percentageLabel(frame, ui, muted, text)
    local label = frame:AttachFontString()
    label:SetFontObject(muted and "GameFontDisableSmall" or "GameFontHighlightSmall")
    if ui and type(ui.StylePopupLabel) == "function" then ui:StylePopupLabel(label, muted) end
    -- Blizzard attaches these as 150-wide, one-line regions. Measure the
    -- chosen font at its natural size before assigning a rectangle.
    label:SetSize(0, 0)
    label:SetJustifyH("CENTER"); label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    label:SetText(text)
    return label
end

local function contextMenu(widget, root, forceVertical)
    local settings, instance, database = widget.settings, widget.instance, Menubar.db
    if not currentOwner(widget, settings, instance, database) then return end
    local ui = public(Menubar.UI) and type(Menubar.UI) == "table" and Menubar.UI or nil
    local hostToken = ui and ui.contextToken
    if not public(hostToken) or (hostToken ~= nil and type(hostToken) ~= "table") then return end
    local token = {}
    widget.volumeMenuToken = token
    local function active()
        return widget.volumeMenuToken == token and currentOwner(widget, settings, instance, database)
            and (hostToken == nil or (Menubar.UI == ui and ui.contextToken == hostToken))
    end
    root:CreateTitle("Volume")
    local volume, enabled = readState()
    if not volume then
        root:CreateTitle("Volume is currently unavailable.")
        return
    end
    local vertical = forceVertical == true or (public(widget.settings.orientation) and widget.settings.orientation == "vertical")
    local element = root:CreateFrame()
    element:AddInitializer(function(frame)
        if not active() then return end
        local valueLabel = percentageLabel(frame, ui, false, "100%")
        local low = percentageLabel(frame, ui, true, "0%")
        local high = percentageLabel(frame, ui, true, "100%")
        local valueWidth = valueLabel:GetStringWidth()
        -- A proportional font can make a two-digit percentage wider than 100%.
        for digit = 1, 9 do
            valueLabel:SetText((digit * 11) .. "%")
            valueWidth = math.max(valueWidth, valueLabel:GetStringWidth())
        end
        valueWidth = math.max(36, math.ceil(valueWidth) + 4)
        local valueHeight = math.max(14, math.ceil(valueLabel:GetStringHeight()) + 2)
        local endWidth = math.max(32, math.ceil(math.max(low:GetStringWidth(), high:GetStringWidth())) + 4)
        local endHeight = math.max(12, math.ceil(math.max(low:GetStringHeight(), high:GetStringHeight())))
        valueLabel:SetSize(valueWidth, valueHeight)
        low:SetSize(endWidth, endHeight); high:SetSize(endWidth, endHeight)

        local length, width, height, sliderX, sliderY
        if vertical then
            length = 104
            sliderX = math.ceil(endWidth / 2) + 4
            sliderY = math.max(24, endHeight + 8)
            width = sliderX + 16 + valueWidth + 4
            height = length + 2 * sliderY
        else
            length = math.max(200, 2 * endWidth + 8)
            width = math.max(length + 30, valueWidth + 8)
            height = 26 + endHeight + valueHeight
        end
        frame:SetSize(width, height)
        local slider = frame:AttachFrame("Slider")
        -- The compositor resets attached frames to native defaults. A Slider
        -- must draw above this menu element, not back at its default UI depth.
        local function placeSlider()
            local strata, level = frame:GetFrameStrata(), frame:GetFrameLevel() + 1
            if slider:GetFrameStrata() ~= strata then slider:SetFrameStrata(strata) end
            if slider:GetFrameLevel() ~= level then slider:SetFrameLevel(level) end
        end
        placeSlider()
        slider:SetAlpha(1)
        slider:SetEnabled(true)
        slider:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        slider:SetSize(vertical and 20 or length, vertical and length or 20)
        if vertical then slider:SetPoint("TOPLEFT", frame, "TOPLEFT", sliderX - 10, -sliderY)
        else slider:SetPoint("TOP", frame, "TOP", 0, -2) end
        slider:SetMinMaxValues(0, 100)
        slider:SetValueStep(1)
        slider:SetObeyStepOnDrag(true)
        slider:EnableMouse(true)
        slider:EnableMouseWheel(true)

        local track = slider:AttachTexture()
        track:SetAtlas("_Minimal_SliderBar_Middle")
        track:SetPoint("CENTER")
        track:SetSize(length, 8)
        track:SetRotation(vertical and math.pi / 2 or 0)
        track:SetDrawLayer("BACKGROUND")
        local thumb = slider:AttachTexture()
        thumb:SetAtlas("Minimal_SliderBar_Button", true)
        slider:SetThumbTexture(thumb)

        if vertical then
            valueLabel:SetPoint("LEFT", slider, "RIGHT", 6, 0)
            high:SetPoint("BOTTOM", slider, "TOP", 0, 6)
            low:SetPoint("TOP", slider, "BOTTOM", 0, -6)
        else
            valueLabel:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
            low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
            high:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
        end

        local syncing = true
        local function sync()
            if not active() then return end
            -- Native menu opening can raise the parent after initialization.
            -- Follow that live depth without fixing the child's frame level.
            placeSlider()
            local current = percentage(readState())
            syncing = true
            if current then
                -- Native vertical sliders grow downwards. Reverse the value so louder is up.
                slider:SetValue(vertical and 100 - current or current)
                valueLabel:SetText(current .. "%")
            else valueLabel:SetText("--") end
            syncing = false
        end
        sync()
        slider:SetScript("OnValueChanged", function(_, value)
            if syncing or not active() then return end
            value = number(value)
            if not value then return end
            setVolume(widget, vertical and 100 - value or value)
            sync()
        end)
        slider:SetScript("OnMouseWheel", function(_, delta)
            if not active() then return end
            mouseWheel(widget, delta); sync()
        end)
        slider:SetScript("OnShow", function() if active() then placeSlider() end end)
        frame:NewTicker(0.25, sync)
        -- The menu compositor may hide the first Slider while configuring its
        -- previously unseen native metatable. Show it after setup is complete.
        syncing = true
        slider:Show()
        syncing = false
        -- The native menu otherwise remeasures every attachment and replaces
        -- the element's size; keep the intended body and padding explicit.
        return width, height
    end)
    if enabled ~= nil then
        root:CreateCheckbox("|A:voicechat-icon-speaker-mute:14:14|a Mute", function()
            if not active() then return false end
            local _, soundEnabled = readState()
            return soundEnabled == false
        end, function()
            if not active() then return end
            local _, soundEnabled = readState()
            if soundEnabled == nil then
                widget.volumeMessage = "Game audio controls are unavailable."
                refresh(widget)
                return
            end
            writeCVar(widget, "Sound_EnableAllSound", soundEnabled == false and 1 or 0)
            refresh(widget)
        end)
    end
end

local function click(widget)
    if not currentOwner(widget, widget.settings, widget.instance, Menubar.db) then return end
    local ui = Menubar.UI
    if not public(ui) or type(ui) ~= "table" or not public(ui.Context) or type(ui.Context) ~= "function" then
        widget.volumeMessage = "Update Menubar to use the volume controls."
        refresh(widget)
        return
    end
    if widget.volumeMessage == "Update Menubar to use the volume controls." then widget.volumeMessage = nil end
    ui:Context(widget.frame, function(root) contextMenu(widget, root, true) end)
end

local function tooltip(widget, tip)
    local volume, enabled = readState()
    local percent = percentage(volume)
    tip:AddLine("Volume")
    tip:AddLine("Set the tone for your adventure.", 1, 1, 1)
    tip:AddDoubleLine("Master", percent and (percent .. "%") or "Unavailable")
    tip:AddDoubleLine("Game sound", enabled == nil and "Unavailable" or (enabled and "Enabled" or "Muted"))
    if enabled == false then tip:AddLine("Enable game sound in the volume menu to hear changes.", 1, 0.82, 0, true) end
    if widget.volumeMessage then tip:AddLine(widget.volumeMessage, 1, 0.4, 0.4, true) end
end

Menubar:RegisterWidgetType({
    id = "volume", name = "Volume", wheelHint = "Volume", clickHint = "Volume controls",
    retainOnDisable = true,
    defaults = { showPercent = true, orientation = "horizontal", wheelStep = 5},
    defaultPlacement = { bar = "top", alignment = "right", order = 8, sidebarOrder = 11 },
    interval = 0.25,
    events = { "CVAR_UPDATE" },
    settings = {
        { key = "showPercent", label = "Show master volume percentage", type = "toggle" },
        { key = "orientation", label = "Context menu slider", type = "select", options = {
            { value = "horizontal", label = "Horizontal" }, { value = "vertical", label = "Vertical" },
        } },
        { key = "wheelStep", label = "Mouse wheel step (%)", type = "number", min = 1, max = 20, integer = true },
    },
    update = update, reset = destroy, deactivate = destroy, destroy = destroy, tooltip = tooltip, contextMenu = contextMenu, mouseWheel = mouseWheel, click = click,
})
