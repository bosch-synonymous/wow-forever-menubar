-- Shared original progress presentation. Providers own the data and select native colours/art.
local Gauge = {}
_G.MenubarGauge = Gauge
local plainTexture = "Interface\\TargetingFrame\\UI-StatusBar"
local nativeHeight = 29
local nativeAtlases = { "common-stat-bar-BG", "common-stat-bar-white", "common-stat-bar-Mask" }

local function public(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function publicNumber(value)
    if not public(value) then return false end
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function validateColor(color)
    assert(public(color) and type(color) == "table", "Menubar: invalid gauge colour")
    for index = 1, 4 do
        local component = color[index]
        assert(public(component), "Menubar: restricted gauge colour")
        if index == 4 and component == nil then component = 1 end
        assert(publicNumber(component) and component >= 0 and component <= 1, "Menubar: invalid gauge colour")
    end
end

local function applyAtlas(texture, atlas)
    if type(atlas) ~= "string" or type(texture.SetAtlas) ~= "function" then return false end
    if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
        if not ok or not public(info) or not info then return false end
    end
    local ok, result = pcall(texture.SetAtlas, texture, atlas, false)
    if not ok or not public(result) or result == false then return false end
    if type(texture.GetAtlas) == "function" then
        local readOK, actual = pcall(texture.GetAtlas, texture)
        -- The native getter may canonicalize an accepted atlas name's casing.
        return readOK and public(actual) and type(actual) == "string" and actual:lower() == atlas:lower()
    end
    return true
end

local function hideBonus(widget)
    if widget.gaugeBonus then widget.gaugeBonus:Hide() end
    if widget.gaugeWarcraftBonus then
        widget.gaugeWarcraftBonus.menubarBonusActive = false
        widget.gaugeWarcraftBonus:Hide()
    end
end

local function create(widget)
    -- Own each native object as soon as it exists, so a failed allocation can be
    -- hidden and retried without abandoning frames that WoW cannot delete.
    local bar = widget.gauge
    if not bar then
        bar = CreateFrame("StatusBar", nil, widget.frame)
        widget.gauge = bar
    end
    bar:Hide()
    bar:SetFrameLevel(widget.frame:GetFrameLevel() + 1)
    bar:ClearAllPoints()
    local content = widget.content or widget.frame
    bar:SetPoint("LEFT", content, "LEFT", 2, 0)
    bar:SetPoint("RIGHT", content, "RIGHT", -2, 0)
    bar:SetStatusBarTexture(plainTexture)
    local background = widget.gaugeBackground
    if not background then background = bar:CreateTexture(nil, "BACKGROUND"); widget.gaugeBackground = background end
    background:SetAllPoints(); background:SetColorTexture(0.06, 0.06, 0.06, 0.9)
    widget.gaugeEdges = widget.gaugeEdges or {}
    for index, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local line = widget.gaugeEdges[index]
        if not line then line = bar:CreateTexture(nil, "OVERLAY"); widget.gaugeEdges[index] = line end
        line:SetColorTexture(0, 0, 0, 1)
        line:ClearAllPoints()
        if edge == "TOP" or edge == "BOTTOM" then
            line:SetHeight(1); line:SetPoint(edge .. "LEFT"); line:SetPoint(edge .. "RIGHT")
        else
            line:SetWidth(1); line:SetPoint("TOP" .. edge); line:SetPoint("BOTTOM" .. edge)
        end
    end
    local label = widget.gaugeLabel
    if not label then label = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText"); widget.gaugeLabel = label end
    label:ClearAllPoints()
    label:SetPoint("CENTER")
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    widget.gaugeReady = true
end

function Gauge.Reset(widget)
    widget.gaugeActive = false
    hideBonus(widget)
    if widget.gauge then widget.gauge:Hide() end
    if widget.gaugeWarcraft then widget.gaugeWarcraft:Hide() end
    if widget.gaugeWarcraftAnchor then widget.gaugeWarcraftAnchor:Hide() end
end

local function layoutNativeBonus(area)
    local texture = area.menubarBonus
    if not texture or not texture.menubarBonusActive then return end
    local width = area:GetWidth()
    assert(publicNumber(width) and width >= 0, "Menubar: invalid native gauge width")
    texture:ClearAllPoints()
    texture:SetPoint("LEFT", area, "LEFT", width * texture.menubarBonusStart, 0)
    texture:SetWidth(width * texture.menubarBonusSpan)
    texture:SetHeight(area:GetParent().Fill:GetHeight())
    -- Match the native white fill's crop and vertical orientation.
    texture:SetTexCoord(texture.menubarBonusStart, texture.menubarBonusStart + texture.menubarBonusSpan, 1, 0)
    texture:SetShown(width > 0)
end

local function resizeNativeBonus(area)
    -- A host rebuild can render before showing the widget. Explicit rendering
    -- lays it out regardless; later visual-only resize work needs visibility.
    if area:IsVisible() then layoutNativeBonus(area) end
end

local function applyBonus(widget, value, maximum, bonus, width)
    hideBonus(widget)
    if not bonus then return end
    -- Clamp before adding/dividing: a finite rested pool can be larger than
    -- this level, and adding two otherwise finite values can overflow.
    local amount = math.min(bonus.value, maximum - value)
    if amount <= 0 then return end
    local start, span = value / maximum, amount / maximum
    local color, texture = bonus.color
    if widget.gaugeStyleUsed == "warcraft" then
        local native = widget.gaugeWarcraft
        texture = widget.gaugeWarcraftBonus
        if not texture then
            texture = native:CreateTexture(nil, "BORDER", nil, -1)
            widget.gaugeWarcraftBonus = texture
        end
        texture:Hide()
        if not widget.gaugeWarcraftBonusReady then
            texture:SetDrawLayer("BORDER", -1)
            texture:SetTexture(plainTexture)
            if not applyAtlas(texture, "common-stat-bar-white") then texture:SetTexture(plainTexture) end
            texture:AddMaskTexture(native.Mask)
            native.FillArea.menubarBonus = texture
            if not widget.gaugeWarcraftBonusHooked then
                native.FillArea:HookScript("OnSizeChanged", resizeNativeBonus)
                widget.gaugeWarcraftBonusHooked = true
            end
            widget.gaugeWarcraftBonusReady = true
        end
        texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
        texture.menubarBonusStart, texture.menubarBonusSpan, texture.menubarBonusActive = start, span, true
        -- The hook also handles the native FillArea resolving its initial size
        -- after template creation, without another allocation or sampler.
        layoutNativeBonus(native.FillArea)
    else
        texture = widget.gaugeBonus
        if not texture then
            texture = widget.gauge:CreateTexture(nil, "ARTWORK", nil, -1)
            widget.gaugeBonus = texture
        end
        texture:Hide()
        texture:SetDrawLayer("ARTWORK", -1)
        if widget.gaugeBonusAtlas ~= bonus.atlas or widget.gaugeBonusAtlasApplied == nil then
            texture:SetTexture(plainTexture)
            widget.gaugeBonusAtlas, widget.gaugeBonusAtlasApplied = bonus.atlas, applyAtlas(texture, bonus.atlas)
            if not widget.gaugeBonusAtlasApplied then texture:SetTexture(plainTexture) end
        end
        if widget.gaugeBonusAtlasApplied then texture:SetVertexColor(1, 1, 1, color[4] or 1)
        else texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", widget.gauge, "TOPLEFT", (width - 4) * start, 0)
        texture:SetPoint("BOTTOMLEFT", widget.gauge, "BOTTOMLEFT", (width - 4) * start, 0)
        texture:SetWidth((width - 4) * span)
        texture:SetTexCoord(start, start + span, 0, 1)
        texture:Show()
    end
end

local function nativeGauge(widget)
    if widget.gaugeWarcraftReady then return widget.gaugeWarcraft end
    if widget.gaugeWarcraftUnavailable then return nil end
    if type(ColoredProgressBarMixin) ~= "table" or type(ColoredProgressBarMixin.SetFillPercent) ~= "function" then
        return nil
    end
    if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
        for _, atlas in ipairs(nativeAtlases) do
            local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
            if not ok or not info then return nil end
        end
    end
    -- Use the client's reputation-bar template and its rounded fill mask. No art is bundled.
    local anchor = widget.gaugeWarcraftAnchor
    if not anchor then
        anchor = CreateFrame("Frame", nil, widget.frame)
        widget.gaugeWarcraftAnchor = anchor
        anchor:Hide()
    end
    anchor:SetFrameLevel(widget.gauge:GetFrameLevel() - 1)
    anchor:EnableMouse(false)
    local frame = widget.gaugeWarcraft
    if not frame then
        local ok
        ok, frame = pcall(CreateFrame, "Frame", nil, anchor, "ColoredProgressBarTemplate")
        if not ok or not frame or not frame.Fill or not frame.Mask or type(frame.SetFillPercent) ~= "function" then
            if ok and frame then frame:Hide() end
            widget.gaugeWarcraftUnavailable = true
            return nil
        end
        widget.gaugeWarcraft = frame
    end
    frame:Hide()
    frame:SetFrameLevel(widget.gauge:GetFrameLevel() - 1)
    frame:EnableMouse(false)
    if frame.FillArea then frame.FillArea:EnableMouse(false) end
    if frame.Text then frame.Text:Hide() end
    frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    frame:Hide()
    widget.gaugeWarcraftReady = true
    return frame
end

local function wantsWarcraft(widget)
    local style = widget.settings.gaugeStyle
    if not public(style) then return false end
    if style ~= "theme" then return style == "warcraft" end
    local theme, skins = widget.gaugeTheme, MenubarSkins
    if not public(theme) or type(theme) ~= "string" or not public(skins) or type(skins) ~= "table"
        or type(skins.IsWarcraft) ~= "function" then return false end
    return skins.IsWarcraft(theme)
end

local function applyStyle(widget, value, maximum, color, width, height, offset)
    local native
    if wantsWarcraft(widget) and height >= 12 then native = nativeGauge(widget) end
    if native then
        -- Scale the original 29px frame uniformly; keep the overlay on the unscaled StatusBar.
        local anchor, scale = widget.gaugeWarcraftAnchor, height / nativeHeight
        anchor:ClearAllPoints()
        local content = widget.content or widget.frame
        anchor:SetPoint("LEFT", content, "LEFT", 2, offset)
        anchor:SetPoint("RIGHT", content, "RIGHT", -2, offset)
        anchor:SetHeight(height)
        native:SetScale(scale)
        native:SetSize((width - 4) / scale, nativeHeight)
        native:SetFillPercent(value / maximum)
        native.Fill:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
        anchor:Show()
        native:Show()
        widget.gauge:GetStatusBarTexture():Hide()
        widget.gaugeBackground:Hide()
        for _, edge in ipairs(widget.gaugeEdges) do edge:Hide() end
        widget.gaugeStyleUsed = "warcraft"
    else
        if widget.gaugeWarcraft then widget.gaugeWarcraft:Hide() end
        if widget.gaugeWarcraftAnchor then widget.gaugeWarcraftAnchor:Hide() end
        widget.gauge:GetStatusBarTexture():Show()
        widget.gaugeBackground:Show()
        for _, edge in ipairs(widget.gaugeEdges) do edge:Show() end
        widget.gaugeStyleUsed = "square"
    end
end

function Gauge.Attach(widget, restoreTextStyle)
    function widget:SetGauge(value, maximum, color, overlay, width, atlas, bonus)
        assert(publicNumber(value) and publicNumber(maximum) and maximum > 0, "Menubar: invalid gauge progress")
        assert(public(width) and public(color) and public(overlay) and public(atlas) and public(bonus), "Menubar: restricted gauge presentation")
        width = width or 160
        assert(publicNumber(width) and width >= 48 and width <= 1000, "Menubar: invalid gauge width")
        color = color or { 0.5, 0.5, 0.5, 1 }
        validateColor(color)
        if bonus ~= nil then
            assert(public(bonus) and type(bonus) == "table", "Menubar: invalid gauge bonus")
            assert(publicNumber(bonus.value) and bonus.value >= 0, "Menubar: invalid gauge bonus value")
            validateColor(bonus.color)
            assert(public(bonus.atlas) and (bonus.atlas == nil or type(bonus.atlas) == "string"), "Menubar: invalid gauge bonus atlas")
        end
        if not self.gaugeReady then create(self) end
        local bar = self.gauge
        self.gaugeActive = true
        local content = self.content or self.frame
        local frameHeight = content:GetHeight()
        local top, bottom = 0, 0
        if not self.content then top, bottom = self.gaugeTopLineSize or 1, self.gaugeBottomLineSize or 1 end
        local gap = math.min(2, math.max(0, (frameHeight - top - bottom - 4) / 2))
        local height = math.max(4, frameHeight - top - bottom - gap * 2)
        local offset = (bottom - top) / 2
        if height ~= self.gaugeHeight or offset ~= self.gaugeOffset or self.gaugeAnchorParent ~= content then
            bar:ClearAllPoints()
            bar:SetPoint("LEFT", content, "LEFT", 2, offset)
            bar:SetPoint("RIGHT", content, "RIGHT", -2, offset)
            bar:SetHeight(height)
            self.gaugeHeight, self.gaugeOffset, self.gaugeAnchorParent = height, offset, content
        end
        if self.customWidth ~= width then self:SetWidth(width) end

        if self.gaugeAtlas ~= atlas or self.gaugeAtlasApplied == nil then
            bar:SetStatusBarTexture(plainTexture)
            self.gaugeAtlas, self.gaugeAtlasApplied = atlas, false
            local texture = bar:GetStatusBarTexture()
            if texture then
                self.gaugeAtlasApplied = applyAtlas(texture, atlas)
                if not self.gaugeAtlasApplied then bar:SetStatusBarTexture(plainTexture) end
            end
        end
        if self.gaugeAtlasApplied then bar:SetStatusBarColor(1, 1, 1, color[4] or 1)
        else bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1) end
        bar:SetMinMaxValues(0, maximum)
        local clamped = math.max(0, math.min(maximum, value))
        bar:SetValue(clamped)

        local fontPath, fontHeight = self.gaugeLabel:GetFont()
        self.gaugeLabel:SetFont(fontPath or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", fontHeight or 12, "OUTLINE")
        self.gaugeLabel:SetTextColor(1, 1, 1, 1)
        self.gaugeLabel:SetShadowColor(0, 0, 0, 1)
        self.gaugeLabel:SetShadowOffset(1, -1)
        self.gaugeLabel:SetWidth(width - 12)
        self.gaugeLabel:SetText(tostring(overlay or ""))
        self:SetText(overlay or "")
        self.label:Hide()
        bar:Show()
        applyStyle(self, clamped, maximum, color, width, frameHeight - top - bottom, offset)
        applyBonus(self, clamped, maximum, bonus, width)
    end

    function widget:HideGauge()
        local wasActive = self.gaugeActive
        Gauge.Reset(self)
        if not wasActive then return end
        self.customWidth = nil
        self.label:ClearAllPoints()
        self.label:SetPoint("CENTER", self.content or self.frame, "CENTER", 0, 0)
        self.label:Show()
        if restoreTextStyle then restoreTextStyle(self) end
        self:SetText(self.text or "")
    end
end

return Gauge
