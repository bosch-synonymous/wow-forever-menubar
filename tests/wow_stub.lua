-- A deliberately small UI test double, not a WoW emulator. Client checks remain required.
local Stub = { frames = {}, textures = {}, masks = {}, menus = {}, messages = {}, tickers = {} }
local Region = {}
Region.__index = Region

local function region(kind, parent, name)
    return setmetatable({ kind = kind, parent = parent, name = name, scripts = {}, points = {},
        shown = true, text = "", enabled = true }, Region)
end

local function sizeChanged(frame, method)
    -- Some existing native-facing fixtures wrap an individual setter and own
    -- its event dispatch. Do not deliver that same native event twice.
    local owned = rawget(frame, method)
    if (not owned or owned == Region[method]) and frame.scripts.OnSizeChanged then
        frame.scripts.OnSizeChanged(frame, frame:GetWidth(), frame:GetHeight())
    end
end
function Region:SetSize(width, height)
    local changed = self.width ~= width or self.height ~= height
    self.width, self.height = width, height
    if changed then sizeChanged(self, "SetSize") end
end
function Region:SetWidth(width)
    local changed = self.width ~= width
    self.width = width
    if changed then sizeChanged(self, "SetWidth") end
end
function Region:SetHeight(height)
    local changed = self.height ~= height
    self.height = height
    if changed then sizeChanged(self, "SetHeight") end
end
function Region:GetWidth() return (self.allPoints and self.allPoints:GetWidth()) or self.width or (self.parent and self.parent:GetWidth()) or 1280 end
function Region:GetHeight() return (self.allPoints and self.allPoints:GetHeight()) or self.height or (self.parent and self.parent:GetHeight()) or 720 end
function Region:SetScale(value) self.scale = value end
function Region:GetScale() return self.scale or 1 end
function Region:GetEffectiveScale()
    return self:GetScale() * (self.parent and self.parent:GetEffectiveScale() or 1)
end
function Region:GetName() return self.name end
function Region:GetCenter() return self:GetWidth() / 2, self:GetHeight() / 2 end
function Region:GetRect()
    local width, height = self:GetWidth(), self:GetHeight()
    if self == UIParent then return 0, 0, width, height end
    local point = self.points[1]
    local relative, relativePoint, x, y = self.parent or UIParent, "CENTER", 0, 0
    local ownPoint = "CENTER"
    if point then
        ownPoint, relativePoint = point[1], point[1]
        if type(point[2]) == "table" then
            relative, relativePoint, x, y = point[2], point[3] or ownPoint, point[4] or 0, point[5] or 0
        else x, y = point[2] or 0, point[3] or 0 end
    end
    local function fraction(value, low, high)
        if value:find(low, 1, true) then return 0 end
        if value:find(high, 1, true) then return 1 end
        return 0.5
    end
    local left, bottom, wide, tall = relative:GetRect()
    local ratio = relative:GetEffectiveScale() / self:GetEffectiveScale()
    return (left + wide * fraction(relativePoint, "LEFT", "RIGHT")) * ratio + x - width * fraction(ownPoint, "LEFT", "RIGHT"),
        (bottom + tall * fraction(relativePoint, "BOTTOM", "TOP")) * ratio + y - height * fraction(ownPoint, "BOTTOM", "TOP"), width, height
end
function Region:GetLeft() local left = self:GetRect(); return left end
function Region:GetRight() local left, _, width = self:GetRect(); return left + width end
function Region:GetBottom() local _, bottom = self:GetRect(); return bottom end
function Region:GetTop() local _, bottom, _, height = self:GetRect(); return bottom + height end
function Region:SetClampRectInsets(...) self.clampRectInsets = { ... } end
function Region:GetClampRectInsets() return unpack(self.clampRectInsets or { 0, 0, 0, 0 }) end
function Region:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Region:GetPoint(index) return unpack(self.points[index or 1] or {}) end
function Region:ClearAllPoints() self.points, self.allPoints = {}, nil end
function Region:SetAllPoints(other) self.allPoints = other or self.parent end
function Region:SetFrameStrata(value) self.strata = value end
function Region:GetFrameStrata() return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM" end
function Region:SetFrameLevel(value) self.level = value end
function Region:GetFrameLevel() return self.level or 1 end
function Region:SetAlpha(value) self.alpha = value end
function Region:GetAlpha() return self.alpha == nil and 1 or self.alpha end
function Region:GetEffectiveAlpha()
    return self:GetAlpha() * (self.parent and self.parent:GetEffectiveAlpha() or 1)
end
function Region:SetParent(parent) self.parent = parent end
function Region:GetParent() return self.parent end
function Region:GetObjectType() return self.kind end
function Region:SetScript(name, handler) self.scripts[name] = handler end
function Region:GetScript(name) return self.scripts[name] end
function Region:HookScript(name, handler)
    local previous = self.scripts[name]
    self.scripts[name] = function(...)
        if previous then previous(...) end
        handler(...)
    end
end
function Region:RegisterEvent(event)
    self.events = self.events or {}
    if self.events[event] then return false end
    self.events[event] = true
    return true
end
function Region:IsEventRegistered(event) return self.events ~= nil and self.events[event] == true end
function Region:RegisterForClicks(...) self.clicks = { ... } end
function Region:RegisterForDrag() end
function Region:EnableMouse(enabled) self.mouseEnabled = enabled ~= false end
function Region:EnableMouseWheel(enabled) self.mouseWheelEnabled = enabled ~= false end
function Region:SetEnabled(enabled) self.enabled = enabled ~= false end
function Region:IsEnabled() return self.enabled end
function Region:Enable() self:SetEnabled(true) end
function Region:Disable() self:SetEnabled(false) end
function Region:SetChecked(checked) self.checked = not not checked end
function Region:GetChecked() return self.checked or false end
function Region:Click(mouseButton)
    if not self.enabled then return end
    if self.kind == "CheckButton" then self:SetChecked(not self:GetChecked()) end
    if self.scripts.OnClick then self.scripts.OnClick(self, mouseButton or "LeftButton") end
end
function Region:MouseDown(mouseButton)
    if self.enabled and self.scripts.OnMouseDown then self.scripts.OnMouseDown(self, mouseButton or "LeftButton") end
end
function Region:MouseUp(mouseButton)
    if self.enabled and self.scripts.OnMouseUp then self.scripts.OnMouseUp(self, mouseButton or "LeftButton") end
end
function Region:SetMovable() end
function Region:SetClampedToScreen() end
function Region:StartMoving() end
function Region:StopMovingOrSizing() end
function Region:SetAutoFocus(value) self.autoFocus = value end
function Region:SetTextInsets(...) self.textInsets = { ... } end
function Region:SetMaxLetters(value) self.maxLetters = value end
function Region:SetJustifyH(value) self.justifyH = value end
function Region:SetJustifyV(value) self.justifyV = value end
function Region:SetWordWrap(value) self.wordWrap = value end
function Region:SetShadowColor(...) self.shadowColor = { ... } end
function Region:SetShadowOffset(...) self.shadowOffset = { ... } end
function Region:GetShadowColor() return unpack(self.shadowColor or { 0, 0, 0, 0 }) end
function Region:GetShadowOffset() return unpack(self.shadowOffset or { 0, 0 }) end
function Region:SetNumeric(value) self.numeric = value end
function Region:SetMultiLine(value) self.multiline = value end
function Region:SetFocus() self.focus = true end
function Region:HasFocus() return self.focus or false end
function Region:HighlightText(start, finish) self.highlightRange = { start, finish } end
function Region:ClearFocus() self.focus = false end
function Region:SetVerticalScroll(value) self.scroll = value end
function Region:GetVerticalScroll() return self.scroll or 0 end
function Region:SetScrollChild(child) self.scrollChild = child end
function Region:SetHorizTile(value) self.horizTile = value end
function Region:SetVertTile(value) self.vertTile = value end
function Region:SetVertexColor(...) self.vertexColor = { ... } end
function Region:SetColorTexture(...) self.color = { ... } end
function Region:SetTexture(value) self.texture, self.atlas = value, nil; return true end
function Region:GetTexture() return self.texture end
function Region:GetTextureFileID() if type(self.texture) == "number" then return self.texture end end
function Region:SetTexCoord(...) self.texCoords = { ... } end
function Region:SetRotation(value) self.rotation = value end
function Region:CreateAnimationGroup()
    local group = { parent = self, steps = {}, scripts = {}, plays = 0, stops = 0, playing = false, starts = {} }
    Stub.animations[#Stub.animations + 1] = group
    function group:CreateAnimation(kind)
        local step = { kind = kind or "Animation" }
        self.steps[#self.steps + 1] = step
        function step:SetOrder(value) self.order = value end
        function step:SetDuration(value) self.duration = value end
        function step:SetDegrees(value) self.degrees = value end
        function step:SetOffset(x, y) self.offset = { x, y } end
        function step:SetOrigin(...) self.origin = { ... } end
        function step:SetSmoothing(value) self.smoothing = value end
        return step
    end
    function group:SetLooping(value) self.looping = value end
    function group:SetScript(name, callback) self.scripts[name] = callback end
    function group:GetScript(name) return self.scripts[name] end
    function group:IsPlaying() return self.playing end
    function group:GetDuration()
        local orders, duration = {}, 0
        for _, step in ipairs(self.steps) do
            local order = step.order or 1
            orders[order] = math.max(orders[order] or 0, step.duration or 0)
        end
        for _, value in pairs(orders) do duration = duration + value end
        return duration
    end
    function group:Play()
        self.plays, self.playing = self.plays + 1, true
        self.starts[#self.starts + 1] = Stub.animationTime
        self.endsAt = Stub.animationTime + self:GetDuration()
    end
    function group:Stop()
        local wasPlaying = self.playing
        self.stops, self.playing, self.endsAt = self.stops + 1, false, nil
        if wasPlaying and self.scripts.OnStop then self.scripts.OnStop(self) end
    end
    function group:Restart() self:Stop(); self:Play() end
    function group:Finish()
        local wasPlaying = self.playing
        self.playing, self.endsAt = false, nil
        if wasPlaying and self.scripts.OnFinished then self.scripts.OnFinished(self) end
    end
    return group
end
function Region:SetAtlas(value, useAtlasSize)
    self.atlas, self.texture, self.useAtlasSize = value, nil, useAtlasSize
    if useAtlasSize and value == "Minimal_SliderBar_Button" then
        -- Representative fixture dimensions, not a claim about client art.
        self:SetSize(16, 16)
    end
    return true
end
function Region:GetAtlas() return self.atlas end
function Region:SetBlendMode(value) self.blendMode = value end
function Region:SetDrawLayer(layer, level) self.drawLayer, self.drawLevel = layer, level end
function Region:AddMaskTexture(mask)
    self.masks = self.masks or {}
    self.masks[mask] = true
end
function Region:RemoveMaskTexture(mask)
    if self.masks then self.masks[mask] = nil end
end
function Region:SetFont(path, size, flags)
    if path == "missing.ttf" then return false end
    self.font, self.fontSize, self.fontFlags = path, size, flags
    return true
end
function Region:GetFont() return self.font, self.fontSize, self.fontFlags end
function Region:SetFontObject(value)
    if type(value) == "string" then value = _G[value] end
    assert(type(value) == "table" and type(value.GetFont) == "function", "Expected a native font object")
    self.fontObject = value
    self:SetFont(value:GetFont())
    if value.textColor then self:SetTextColor(unpack(value.textColor)) end
end
function Region:GetFontObject() return self.fontObject end
function Region:SetNormalFontObject(value)
    self.normalFontObject = type(value) == "string" and _G[value] or value
    if self.Text then self.Text:SetFontObject(self.normalFontObject) end
end
function Region:GetNormalFontObject() return self.normalFontObject end
function Region:SetHighlightFontObject(value) self.highlightFontObject = value end
function Region:SetDisabledFontObject(value) self.disabledFontObject = value end
function Region:GetFontString() return self.Text or self.Label end
function Region:SetTextColor(...) self.textColor = { ... } end
function Region:SetText(value)
    self.textValue = tostring(value)
    if type(self.text) ~= "table" then self.text = self.textValue end
    if self.Text then self.Text:SetText(self.textValue) end
end
function Region:GetText() return self.textValue or (type(self.text) == "string" and self.text) or "" end
function Region:GetStringWidth()
    local text = self:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local iconWidth = 0
    local function measureIcon(body)
        local height, width = body:match("^[^:]+:([%d%.%-]+):([%d%.%-]+)")
        height, width = tonumber(height), tonumber(width)
        iconWidth = iconWidth + ((width and width > 0 and width) or (height and height > 0 and height) or (self.fontSize or 12))
        return ""
    end
    local plain = text:gsub("|T(.-)|t", measureIcon):gsub("|A(.-)|a", measureIcon)
    return #plain * (self.fontSize or 12) / 2 + iconWidth
end
function Region:GetStringHeight() return math.max(1, math.ceil(#self:GetText() / 75)) * (self.fontSize or 12) end
function Region:GetTextColor() return unpack(self.textColor or { 1, 1, 1, 1 }) end
function Region:SetMinMaxValues(minimum, maximum)
    assert(type(minimum) == "number" and type(maximum) == "number" and maximum >= minimum)
    self.minimum, self.maximum = minimum, maximum
end
function Region:GetMinMaxValues() return self.minimum or 0, self.maximum or 1 end
function Region:SetValueStep(value) self.valueStep = value end
function Region:GetValueStep() return self.valueStep or 0 end
function Region:SetObeyStepOnDrag(value) self.obeyStepOnDrag = value end
function Region:GetObeyStepOnDrag() return self.obeyStepOnDrag end
function Region:SetOrientation(value) self.orientation = value end
function Region:GetOrientation() return self.orientation or "HORIZONTAL" end
local function setSliderValue(slider, value, userInput)
    assert(type(value) == "number", "A slider value must be numeric")
    local minimum, maximum = slider:GetMinMaxValues()
    value = math.max(minimum, math.min(maximum, value))
    if userInput and slider.obeyStepOnDrag and slider.valueStep and slider.valueStep > 0 then
        value = minimum + math.floor((value - minimum) / slider.valueStep + 0.5) * slider.valueStep
        value = math.max(minimum, math.min(maximum, value))
    end
    if slider.value == value then return end
    slider.value = value
    if slider.scripts.OnValueChanged then slider.scripts.OnValueChanged(slider, value, userInput) end
end
function Region:SetValue(value) setSliderValue(self, value, false) end
function Region:GetValue() return self.value or 0 end
local function setTexture(regionValue, field, value)
    if type(value) == "table" then regionValue[field] = value
    else
        local texture = regionValue[field] or region("Texture", regionValue)
        texture:SetTexture(value)
        regionValue[field] = texture
    end
end
function Region:SetNormalTexture(value) setTexture(self, "NormalTexture", value) end
function Region:GetNormalTexture() return self.NormalTexture end
function Region:SetPushedTexture(value) setTexture(self, "PushedTexture", value) end
function Region:GetPushedTexture() return self.PushedTexture end
function Region:SetHighlightTexture(value) setTexture(self, "HighlightTexture", value) end
function Region:GetHighlightTexture() return self.HighlightTexture end
function Region:SetDisabledTexture(value) setTexture(self, "DisabledTexture", value) end
function Region:GetDisabledTexture() return self.DisabledTexture end
function Region:SetCheckedTexture(value) setTexture(self, "CheckedTexture", value) end
function Region:SetDisabledCheckedTexture(value) setTexture(self, "DisabledCheckedTexture", value) end
function Region:SetThumbTexture(value) setTexture(self, "Thumb", value) end
function Region:GetThumbTexture() return self.Thumb end
function Region:SetStatusBarTexture(value)
    setTexture(self, "StatusBarTexture", value)
end
function Region:GetStatusBarTexture() return self.StatusBarTexture end
function Region:SetStatusBarColor(...) self.statusBarColor = { ... } end
function Region:GetStatusBarColor() return unpack(self.statusBarColor or { 1, 1, 1, 1 }) end
function Region:IsShown() return self.shown end
function Region:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Region:Show()
    local wasShown = self.shown
    self.shown = true
    if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Region:Hide()
    local wasShown = self.shown
    self.shown = false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Region:SetShown(value) if value then self:Show() else self:Hide() end end
function Region:CreateTexture(name, layer, _, level)
    local texture = region("Texture", self, name)
    texture.drawLayer, texture.drawLevel = layer, level
    Stub.textures[#Stub.textures + 1] = texture
    if name then _G[name] = texture end
    return texture
end
function Region:CreateMaskTexture(name, layer, _, level)
    local mask = region("MaskTexture", self, name)
    mask.drawLayer, mask.drawLevel = layer, level
    Stub.masks[#Stub.masks + 1] = mask
    if name then _G[name] = mask end
    return mask
end
function Region:CreateFontString(name, layer, fontObject)
    local textRegion = region("FontString", self, name)
    textRegion.drawLayer = layer
    if fontObject then textRegion:SetFontObject(fontObject) end
    if name then _G[name] = textRegion end
    return textRegion
end
-- These methods are supplied by Blizzard's menu compositor on element frames.
function Region:AttachFrame(kind, template)
    local frame = CreateFrame(kind, nil, self, template)
    frame:Show()
    -- Native Compositor acquires/shows before configuring a type's first
    -- metatable. That first configuration hides the region again.
    if not Stub.attachmentMetatables[kind] then
        Stub.attachmentMetatables[kind] = true
        frame:Hide()
    end
    return frame
end
function Region:AttachTexture(...) return self:CreateTexture(...) end
function Region:AttachFontString(...)
    local text = self:CreateFontString(...)
    -- Native compositor defaults; callers own the eventual text rectangle.
    text:SetSize(150, 1); text.maxLines = 1
    text:SetJustifyH("LEFT"); text:SetJustifyV("MIDDLE")
    return text
end
function Region:NewTicker(interval, callback) return C_Timer.NewTicker(interval, callback) end

local function dropdownTemplate(frame)
    frame.intrinsic = "DropdownButton"
    frame:SetSize(120, 25)
    frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.Arrow = frame:CreateTexture(nil, "OVERLAY")
    frame.Background = frame:CreateTexture(nil, "BACKGROUND")
    function frame:SetDefaultText(value) self.defaultText = value; self:Update() end
    function frame:GetDefaultText() return self.defaultText end
    function frame:SetSelectionText(callback) self.selectionFunc = callback end
    function frame:SetSelectionTranslator(callback) self.selectionTranslator = callback end
    function frame:OverrideText(value) self.disableSelectionText = true; self:SetText(value) end
    function frame:SignalUpdate()
        if self.disableSelectionText then return end
        local selected = {}
        local function visit(description)
            for _, child in ipairs(description.children) do
                if child.selected and not child.selectionIgnored and child.selected(child.data) then selected[#selected + 1] = child end
                visit(child)
            end
        end
        if self.menuDescription then visit(self.menuDescription) end
        local value = self.selectionFunc and self.selectionFunc(selected)
        if value == nil and #selected > 0 then
            local labels = {}
            for _, child in ipairs(selected) do labels[#labels + 1] = self.selectionTranslator and self.selectionTranslator(child) or child.text end
            value = table.concat(labels, ", ")
        end
        self:SetText(value or self.defaultText or "")
    end
    frame.Update = frame.SignalUpdate
    function frame:SetupMenu(generate)
        assert(type(generate) == "function")
        self.menuGenerator = generate
        if self:IsShown() then self:GenerateMenu() end
    end
    function frame:GenerateMenu()
        if not self.menuGenerator then return end
        local description = MenuUtil.CreateRootMenuDescription(self.menuMixin or MenuVariants.GetDefaultMenuMixin())
        description.dropdown = self
        Menu.PopulateDescription(self.menuGenerator, self, description)
        self.menuDescription = description
        self:SignalUpdate()
    end
    function frame:GetMenuDescription() return self.menuDescription end
    function frame:IsMenuOpen() return self.menu ~= nil end
    function frame:CloseMenu()
        if self.menu then Menu.GetManager():CloseMenu(self.menu); self.menu = nil end
        self:SignalUpdate()
    end
    function frame:ClearMenuState()
        self.menuDescription, self.menuGenerator = nil, nil
        self:CloseMenu()
    end
    function frame:OpenMenu()
        if not self:IsEnabled() or self:IsMenuOpen() then return end
        self:GenerateMenu()
        if not self.menuDescription then return end
        local anchor = self.menuAnchor or AnchorUtil.CreateAnchor("TOPLEFT", self, "BOTTOMLEFT", 0, 0)
        local menu = Menu.GetManager():OpenMenu(self, self.menuDescription, anchor)
        self.menu = menu
        if menu then menu:SetClosedCallback(function() self.menu = nil; self:SignalUpdate() end) end
        return menu
    end
    function frame:SetMenuOpen(open) if open then self:OpenMenu() else self:CloseMenu() end end
    function frame:SetMenuAnchor(anchor) self.menuAnchor = anchor end
    function frame:EnableRegenerateOnResponse() self.shouldRegenerateOnResponse = true end
    function frame:SetTooltip(callback) self.tooltipFunc = callback end
    -- Native intrinsic input opens on mouse-down; Button:Click is not a substitute.
    frame:SetScript("OnMouseDown", function(self)
        if type(IsShiftKeyDown) ~= "function" or not IsShiftKeyDown() then self:SetMenuOpen(not self:IsMenuOpen()) end
    end)
    frame:SetScript("OnShow", function(self) self:GenerateMenu() end)
end

local function applyTemplate(frame, template)
    if template == "DefaultPanelTemplate" then
        frame.TitleContainer = region("Frame", frame)
        frame.TitleContainer.TitleText = frame.TitleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.CloseButton = region("Button", frame)
        frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)
    elseif template == "UIPanelCloseButton" then
        frame:SetSize(32, 32)
        frame:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        frame:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        frame:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        frame:SetScript("OnClick", function() if frame.parent then frame.parent:Hide() end end)
    elseif template == "UIPanelButtonTemplate" then
        frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame:SetNormalFontObject(GameFontNormal)
        frame:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
        frame:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
        frame:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
        frame:SetDisabledTexture("Interface\\Buttons\\UI-Panel-Button-Disabled")
    elseif template == "InputBoxTemplate" then
        frame:SetFontObject(GameFontHighlight)
        frame.Left, frame.Middle, frame.Right = frame:CreateTexture(), frame:CreateTexture(), frame:CreateTexture()
    elseif template == "UICheckButtonTemplate" or template == "InterfaceOptionsCheckButtonTemplate" then
        frame:SetSize(32, 32)
        if template == "InterfaceOptionsCheckButtonTemplate" then frame:SetSize(26, 26) end
        frame.Text = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        frame.text = frame.Text -- native legacy alias from UICheckButtonFontString_SetParentKeyAlias
        frame:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        frame:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        frame:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    elseif template == "WowStyle1DropdownTemplate" then
        assert(frame.kind == "DropdownButton", "The native dropdown template requires its intrinsic frame type")
        dropdownTemplate(frame)
    elseif template == "UIPanelSquareButton" then
        frame:SetSize(26, 26)
        frame.icon = frame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetSize(12, 12)
        frame.icon:SetTexture("Interface\\Buttons\\SquareButtonTextures")
        frame:SetNormalTexture("Interface\\Buttons\\SquareButtonTextures")
        frame:SetPushedTexture("Interface\\Buttons\\SquareButtonTextures")
        frame:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    elseif template == "MinimalSliderTemplate" then
        frame:SetSize(200, 19)
        frame.orientation, frame.obeyStepOnDrag, frame.value = "HORIZONTAL", true, 0
        frame.Left, frame.Right, frame.Middle = frame:CreateTexture(), frame:CreateTexture(), frame:CreateTexture()
        frame:SetThumbTexture("Minimal_SliderBar_Button")
    elseif template == "InsetFrameTemplate" then
        frame.NineSlice = region("Frame", frame)
    elseif template == "UIPanelScrollFrameTemplate" then
        frame.ScrollBar = region("Slider", frame)
    elseif template == "ColoredProgressBarTemplate" then
        -- The native template's public regions and fill behavior, not its rendering.
        frame:SetSize(67, 29)
        frame.FillArea = CreateFrame("Frame", nil, frame)
        function frame.FillArea:GetWidth() return math.max(0, self.parent:GetWidth() - 12) end
        local background = frame:CreateTexture(nil, "BACKGROUND")
        background:SetAtlas("common-stat-bar-BG")
        background:SetAllPoints()
        frame.Fill = frame:CreateTexture(nil, "BORDER")
        frame.Fill:SetAtlas("common-stat-bar-white")
        frame.Fill:SetHeight(15)
        frame.Fill:SetPoint("LEFT", frame.FillArea, "LEFT", 0, 0)
        frame.Mask = frame:CreateMaskTexture(nil, "ARTWORK")
        frame.Mask:SetAtlas("common-stat-bar-Mask")
        frame.Mask:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.Mask:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        frame.Fill:AddMaskTexture(frame.Mask)
        frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        for name, method in pairs(ColoredProgressBarMixin) do frame[name] = method end
        frame:SetFillPercent(0)
    elseif template == "BackdropTemplate" then
        -- Rendering is not emulated; the presence of this template is recorded.
    else error("Unsupported native UI test template: " .. template, 0) end
end

function Stub.Install()
    Stub.animationTime = 0
    _G.GetAppropriateTopLevelParent = function() return UIParent end
    Stub.attachmentMetatables = { Frame = true, Button = true, CheckButton = true, StatusBar = true, EditBox = true }
    Stub.animations = {}
    Stub.frames, Stub.textures, Stub.masks, Stub.menus, Stub.messages, Stub.tickers = {}, {}, {}, {}, {}, {}, {}
    _G.UIParent = region("Frame")
    UIParent:SetSize(1280, 720)
    local fontNames = {}
    _G.CreateFont = function(name)
        local object = region("Font", nil, name)
        object:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        object:SetTextColor(1, 1, 1, 1)
        _G[name] = object; fontNames[#fontNames + 1] = name
        return object
    end
    for _, name in ipairs({ "GameFontNormal", "GameFontHighlight", "GameFontDisable", "GameFontNormalSmall",
        "GameFontHighlightSmall", "GameFontDisableSmall", "GameFontNormalLarge", "GameFontHighlightLarge", "ChatFontNormal", "TextStatusBarText" }) do
        local object = CreateFont(name)
        if name:find("Normal", 1, true) then object:SetTextColor(1, 0.82, 0, 1) end
        if name:find("Small", 1, true) then object.fontSize = 10 end
        if name:find("Large", 1, true) then object.fontSize = 16 end
    end
    TextStatusBarText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    TextStatusBarText:SetTextColor(1, 1, 1, 1)
    TextStatusBarText:SetShadowColor(0, 0, 0, 1)
    TextStatusBarText:SetShadowOffset(1, -1)
    local function color(red, green, blue)
        return { r = red, g = green, b = blue, GetRGB = function(self) return self.r, self.g, self.b end }
    end
    _G.FACTION_BAR_COLORS = {
        color(0.8, 0.1, 0.1), color(0.8, 0.1, 0.1), color(0.9, 0.4, 0.1), color(0.9, 0.8, 0.1),
        color(0.1, 0.7, 0.2), color(0.1, 0.75, 0.25), color(0.1, 0.8, 0.3), color(0.1, 0.85, 0.35),
    }
    _G.BLUE_FONT_COLOR = color(0.2, 0.4, 1)
    _G.GetRestState = function() return 2, "Normal", 1 end
    _G.ColoredProgressBarMixin = {
        SetFillPercent = function(self, percent)
            self.fillPercent = math.max(0, math.min(1, percent))
            local width = self.fillPercent * self.FillArea:GetWidth()
            self.Fill:SetShown(width > 0)
            self.Fill:SetWidth(width)
            self.Fill:SetTexCoord(0, self.fillPercent, 1, 0)
        end,
    }
    _G.GetFonts = function()
        local result = {}
        for index, name in ipairs(fontNames) do result[index] = name end
        return result
    end
    _G.CreateFrame = function(kind, name, parent, template)
        local frame = region(kind, parent, name)
        frame.template = template
        Stub.frames[#Stub.frames + 1] = frame
        if name then _G[name] = frame end
        if template then
            for selected in template:gmatch("[^,%s]+") do applyTemplate(frame, selected) end
        end
        return frame
    end
    _G.GameTooltip = region("Tooltip")
    function GameTooltip:SetOwner(owner, anchor) self.owner, self.anchor, self.lines = owner, anchor, {} end
    function GameTooltip:GetOwner() return self.owner end
    function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = { text } end
    function GameTooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = { left, right } end
    _G.UnitName = function() return "Tester" end
    _G.GetRealmName = function() return "Test Realm" end
    _G.GetBuildInfo = function() return "1.60.1", "70938", "Nov 12 2026", 16001 end
    _G.date = function(pattern)
        return { hour = pattern:sub(1, 1) == "!" and 3 or 12, min = 34, sec = 56 }
    end
    _G.GetGameTime = function() return 18, 45 end
    _G.GetMoney = function() return 123456 end
    _G.GetCursorPosition = function() return 640, 360 end
    _G.IsCursorVisible = function() return true end
    _G.IsMouselooking = function() return false end
    _G.GetNetStats = function() return 1.25, 0.75, 42, 68 end
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) Stub.messages[#Stub.messages + 1] = message end }
    _G.SlashCmdList, _G.UISpecialFrames = {}, {}
    _G.C_Timer = { NewTicker = function(interval, callback)
        local ticker = { interval = interval, callback = callback, cancelled = false }
        function ticker:Cancel() self.cancelled = true end
        function ticker:IsCancelled() return self.cancelled end
        Stub.tickers[#Stub.tickers + 1] = ticker
        return ticker
    end }
    _G.ColorPickerFrame = region("Frame")
    ColorPickerFrame:Hide()
    function ColorPickerFrame:SetupColorPickerAndShow(info)
        self.info, self.previousValues = info, { r = info.r, g = info.g, b = info.b, a = info.opacity }
        -- Native Setup applies RGB before Show. Its OnShow applies opacity;
        -- replacing a shown picker does not independently reset that alpha.
        self:SetColorRGB(info.r, info.g, info.b)
        self:Show()
    end
    ColorPickerFrame:SetScript("OnShow", function(self)
        if self.info.hasOpacity then self:SetColorAlpha(self.info.opacity) end
    end)
    function ColorPickerFrame:GetExtraInfo() return self.info and self.info.extraInfo end
    function ColorPickerFrame:GetColorRGB() return self.red, self.green, self.blue end
    function ColorPickerFrame:GetColorAlpha() return self.alpha end
    function ColorPickerFrame:SetColorRGB(red, green, blue)
        self.red, self.green, self.blue = red, green, blue
        if self.info and self.info.swatchFunc then self.info.swatchFunc() end
    end
    function ColorPickerFrame:SetColorAlpha(alpha)
        self.alpha = alpha
        if self.info and self.info.opacityFunc then self.info.opacityFunc() end
    end
    function ColorPickerFrame:Cancel()
        if self.info and self.info.cancelFunc then self.info.cancelFunc(self.previousValues) end
        self:Hide()
    end
    local Description = {}
    Description.__index = Description
    function Description:EnumerateElementDescriptions() return ipairs(self.children) end
    function Description:AddMenuAcquiredCallback(callback)
        local root = self.root or self
        root.acquired = root.acquired or {}; root.acquired[#root.acquired + 1] = callback
    end
    function Description:AddMenuReleasedCallback(callback)
        local root = self.root or self
        root.released = root.released or {}; root.released[#root.released + 1] = callback
    end
    function Description:CreateTitle(text) self.title = text end
    function Description:CreateDivider() end
    function Description:SetScrollMode(height) self.scrollHeight = height end
    function Description:CreateButton(text, callback, data)
        local root = self.root or self
        local child = setmetatable({ text = text, callback = callback, data = data, children = {}, root = root }, Description)
        if root.dropdown and callback then
            child.callback = function(...)
                local result
                if select("#", ...) == 0 then result = callback(data) else result = callback(...) end
                local dropdown = root.dropdown
                if dropdown.menuDescription == root then
                    if dropdown.shouldRegenerateOnResponse then dropdown:GenerateMenu() else dropdown:SignalUpdate() end
                    local active = Menu.GetManager().active
                    if not child.checkbox and active and active.description == root then dropdown:CloseMenu() end
                end
                return result
            end
        end
        self.children[#self.children + 1] = child
        return child
    end
    function Description:CreateRadio(text, selected, callback, data)
        local child = self:CreateButton(text, callback, data); child.selected = selected; child.radio = true; return child
    end
    function Description:CreateCheckbox(text, selected, callback, data)
        local child = self:CreateButton(text, callback, data); child.selected = selected; child.checkbox = true; return child
    end
    function Description:SetSelectionIgnored() self.selectionIgnored = true end
    function Description:IsSelected() return self.selected and self.selected(self.data) or false end
    function Description:IsRadio() return self.radio == true end
    function Description:SetMinimumWidth(value) self.minimumWidth = value end
    function Description:GetMinimumWidth() return self.minimumWidth or 0 end
    function Description:CreateFrame()
        local child = setmetatable({ kind = "Frame", children = {}, initializers = {}, root = self.root or self }, Description)
        self.children[#self.children + 1] = child
        return child
    end
    function Description:AddInitializer(callback)
        self.initializers = self.initializers or {}
        self.initializers[#self.initializers + 1] = callback
        self.initializer = callback
    end
    local style = { GetInset = function() return { left = 10, right = 10, top = 10, bottom = 10 } end }
    _G.MenuVariants = { GetDefaultContextMenuMixin = function() return style end, GetDefaultMenuMixin = function() return style end }
    _G.AnchorUtil = { CreateAnchor = function(point, relativeTo, relativePoint, x, y)
        local anchor = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x or 0, y = y or 0 }
        function anchor:GetRelativeTo() return self.relativeTo end
        function anchor:SetPoint(frame, clear)
            if clear then frame:ClearAllPoints() end
            frame:SetPoint(self.point, self.relativeTo, self.relativePoint, self.x, self.y)
        end
        return anchor
    end }
    local manager = {}
    function manager:CloseMenus()
        local active = self.active
        self.active = nil
        if active then
            for _, callback in ipairs(active.description.released or {}) do callback(active.frame, "CloseAll") end
            active.frame:Hide()
            if active.closed then active.closed(active.frame, "CloseAll") end
        end
    end
    function manager:CloseMenu(frame) if self.active and self.active.frame == frame then self:CloseMenus() end end
    function manager:GetOpenMenu() return self.active and self.active.frame end
    function manager:OpenMenu(owner, description, anchor)
        self:CloseMenus()
        if not self.frame then self.frame = CreateFrame("Frame", nil, UIParent) end
        local frame = self.frame
        frame:ClearAllPoints()
        frame:Show()
        description.owner, description.anchor, description.menuFrame = owner, anchor, frame
        local active = { description = description, frame = frame }
        self.active = active
        function frame:SetClosedCallback(callback) active.closed = callback end
        function frame:Close() manager:CloseMenu(self) end
        for _, callback in ipairs(description.acquired or {}) do callback(frame) end
        if anchor then anchor:SetPoint(frame, true) end
        Stub.menus[#Stub.menus + 1] = description
        return frame
    end
    _G.Menu = { GetManager = function() return manager end,
        PopulateDescription = function(generate, owner, description, ...) return generate(owner, description, ...) end }
    _G.MenuUtil = {
        CreateRootMenuDescription = function(mixin) return setmetatable({ children = {}, mixin = mixin }, Description) end,
        CreateContextMenu = function(owner, generate)
            local description = MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultContextMenuMixin())
            Menu.PopulateDescription(generate, owner, description)
            return manager:OpenMenu(owner, description)
        end,
        GetElementText = function(description) return description.text end,
    }
    _G.SquareButton_SetIcon = function(button, direction)
        assert(button.icon and ({ UP = true, DOWN = true, LEFT = true, RIGHT = true, DELETE = true })[direction])
        -- Observe the native helper call, without emulating its UV artwork.
        button.icon.squareButtonDirection = direction
    end

    -- Canvas registration and native ownership, not the complete Settings UI.
    Stub.settingsCategories, Stub.settingsOpens = {}, {}
    local panel = CreateFrame("Frame", "SettingsPanel", UIParent)
    panel:SetSize(920, 724)
    panel:Hide()
    panel.Container = CreateFrame("Frame", nil, panel)
    -- Representative content dimensions; native responsive rendering is not emulated.
    panel.Container:SetSize(640, 590)
    panel.Container.SettingsCanvas = CreateFrame("Frame", nil, panel.Container)
    panel.Container.SettingsCanvas:SetAllPoints(panel.Container)
    panel.Container.SettingsList = CreateFrame("Frame", nil, panel.Container)
    panel.Container.SettingsList:SetAllPoints(panel.Container)
    local function refreshCanvases()
        for _, category in ipairs(Stub.settingsCategories) do
            if category.registered and category.frame.OnRefresh then category.frame:OnRefresh() end
        end
    end
    function panel:GetSettingsCanvas() return self.Container.SettingsCanvas end
    function panel:GetSettingsList() return self.Container.SettingsList end
    function panel:GetCurrentCategory() return self.currentCategory end
    function panel:Show()
        local wasShown = self:IsShown()
        Region.Show(self)
        if not wasShown then
            local canvas = self.currentCategory and self.currentCategory.frame
            if canvas and canvas:IsVisible() and canvas.scripts.OnShow then canvas.scripts.OnShow(canvas) end
            -- Native SettingsPanel.OnShow refreshes hidden canvases too.
            refreshCanvases()
        end
    end
    function panel:Hide()
        local canvas = self.currentCategory and self.currentCategory.frame
        local visible = canvas and canvas:IsVisible()
        Region.Hide(self)
        if visible and canvas.scripts.OnHide then canvas.scripts.OnHide(canvas) end
    end
    function panel:Close()
        for _, category in ipairs(Stub.settingsCategories) do
            if category.registered and category.frame.OnCommit then category.frame:OnCommit() end
        end
        self:Hide()
    end
    function panel:OpenToCategory(id)
        local selected
        for _, category in ipairs(Stub.settingsCategories) do if category.registered and category:GetID() == id then selected = category end end
        self:Show()
        if not selected then return false end
        local previous = self.currentCategory
        if previous and previous ~= selected then
            previous.frame:SetParent(nil)
            previous.frame:ClearAllPoints()
            previous.frame:Hide()
        end
        self.currentCategory = selected
        local canvas = selected.frame
        canvas:SetParent(self.Container.SettingsCanvas)
        canvas:ClearAllPoints()
        canvas:SetAllPoints(self.Container.SettingsCanvas)
        canvas:Show()
        if canvas.OnRefresh then canvas:OnRefresh() end
        self.Container.SettingsCanvas:Show()
        self.Container.SettingsList:Hide()
        return true
    end
    _G.Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
            assert(canvas and type(name) == "string")
            local category = { frame = canvas, name = name, ID = #Stub.settingsCategories + 1 }
            function category:GetID() return self.ID end
            function category:GetName() return self.name end
            local layout = { frame = canvas, anchors = {} }
            function layout:GetFrame() return self.frame end
            function layout:AddAnchorPoint(point, x, y) self.anchors[#self.anchors + 1] = { point, x, y } end
            category.layout = layout
            Stub.settingsCategories[#Stub.settingsCategories + 1] = category
            return category, layout
        end,
        RegisterAddOnCategory = function(category) category.registered = true end,
        OpenToCategory = function(id, scrollTo)
            Stub.settingsOpens[#Stub.settingsOpens + 1] = { id = id, scrollTo = scrollTo }
            panel:OpenToCategory(id)
            -- The public native wrapper deliberately returns no value.
        end,
    }

    -- One reusable native-shaped popup slot. This deliberately models pooled
    -- ownership and callback order, not StaticPopup's layout/queue machinery.
    _G.StaticPopupDialogs = {}
    Stub.popupFrames, Stub.popupShows, Stub.popupClicks = {}, 0, 0
    local popup
    local function popupEditEvent(edit, name)
        local dialog = edit:GetParent()
        local info = StaticPopupDialogs[dialog.which]
        if info and info[name] then return info[name](edit, dialog.data) end
    end
    local function popupSlot()
        if popup then return popup end
        popup = CreateFrame("Frame", nil, UIParent)
        popup.shown = false
        local edit = CreateFrame("EditBox", nil, popup)
        local first, second = CreateFrame("Button", nil, popup), CreateFrame("Button", nil, popup)
        local body = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        function popup:GetEditBox() return edit end
        function popup:GetButton1() return first end
        function popup:GetButton2() return second end
        function popup:GetTextFontString() return body end
        function popup:Resize() self.resizeCount = (self.resizeCount or 0) + 1 end
        function edit:SetText(value)
            Region.SetText(self, value)
            popupEditEvent(self, "EditBoxOnTextChanged")
        end
        function edit:ClearText() self:SetText("") end
        edit:SetScript("OnTextChanged", function(self) return popupEditEvent(self, "EditBoxOnTextChanged") end)
        edit:SetScript("OnEnterPressed", function(self) return popupEditEvent(self, "EditBoxOnEnterPressed") end)
        edit:SetScript("OnEscapePressed", function(self) return popupEditEvent(self, "EditBoxOnEscapePressed") end)
        first:SetScript("OnClick", function() StaticPopup_OnClick(popup, 1) end)
        second:SetScript("OnClick", function() StaticPopup_OnClick(popup, 2) end)
        popup:SetScript("OnShow", function(self)
            local info = StaticPopupDialogs[self.which]
            if info and info.OnShow then info.OnShow(self, self.data) end
        end)
        popup:SetScript("OnHide", function(self)
            local info = StaticPopupDialogs[self.which]
            if info and info.OnHide then info.OnHide(self, self.data) end
            edit:ClearText(); edit:ClearFocus()
        end)
        Stub.popupFrames[1] = popup
        return popup
    end
    _G.StaticPopup_FindVisible = function(which, data)
        local info = StaticPopupDialogs[which]
        if info and popup and popup:IsShown() and popup.which == which
            and (not info.multiple or popup.data == data) then return popup end
    end
    _G.StaticPopup_Show = function(which, _, _, data)
        local info = StaticPopupDialogs[which]
        if not info then return nil end
        local dialog = popupSlot()
        if dialog:IsShown() then
            if dialog.which ~= which or (info.multiple and dialog.data ~= data) then
                if info.OnCancel then info.OnCancel(nil, data) end
                return nil
            end
            local cancelOnReuse = not info.noCancelOnReuse
            dialog:Hide()
            if cancelOnReuse then
                -- Native reuse resolves cancellation after OnHide/text clear;
                -- a reentrant hide callback can change the slot's owner/data.
                local previous = StaticPopupDialogs[dialog.which]
                if previous and previous.OnCancel then previous.OnCancel(dialog, dialog.data, "override") end
            end
        end
        dialog.which, dialog.dialogInfo, dialog.data = which, info, data
        dialog.hideOnEscape = info.hideOnEscape
        dialog:GetTextFontString():SetText(info.text or "")
        dialog:GetButton1():SetText(info.button1 or ""); dialog:GetButton1():SetEnabled(true)
        dialog:GetButton2():SetText(info.button2 or ""); dialog:GetButton2():SetEnabled(true)
        dialog:GetEditBox():SetShown(info.hasEditBox == true)
        dialog:GetEditBox():SetMaxLetters(info.maxLetters)
        dialog:GetEditBox():SetWidth(info.editBoxWidth or 240)
        Stub.popupShows = Stub.popupShows + 1
        -- Fields/data are assigned before this synchronous native OnShow.
        dialog:Show(); dialog:Resize()
        return dialog
    end
    _G.StaticPopup_Hide = function(which, data)
        if popup and popup:IsShown() and popup.which == which and (not data or popup.data == data) then popup:Hide() end
    end
    _G.StaticPopup_OnClick = function(dialog, index)
        if not dialog:IsShown() then return end
        local which, info = dialog.which, StaticPopupDialogs[dialog.which]
        if not info then return end
        Stub.popupClicks = Stub.popupClicks + 1
        local callback = index == 1 and (info.OnAccept or info.OnButton1) or info.OnCancel
        local keep
        if callback then
            if index == 1 then keep = callback(dialog, dialog.data, dialog.data2)
            else keep = callback(dialog, dialog.data, "clicked") end
        end
        if not keep and dialog.which == which then dialog:Hide() end
    end
    _G.StaticPopup_EscapePressed = function()
        if popup and popup:IsShown() and popup.hideOnEscape then
            local info = StaticPopupDialogs[popup.which]
            if info.OnEscape then info.OnEscape(popup, popup.data, "clicked")
            elseif info.OnCancel and not info.noCancelOnEscape then info.OnCancel(popup, popup.data, "clicked") end
            popup:Hide(); return 1
        end
    end
end

function Stub.DragSlider(slider, value) setSliderValue(slider, value, true) end
function Stub.FireTickers()
    for _, ticker in ipairs(Stub.tickers) do if not ticker.cancelled then ticker.callback(ticker) end end
end

-- Event-time scheduling only: no native interpolation/rendering is emulated.
-- Process all completions at an instant before moving the clock onward; a
-- callback may start another finite group during that same engine boundary.
function Stub.AdvanceAnimations(seconds)
    assert(type(seconds) == "number" and seconds >= 0 and seconds < math.huge)
    local target, events = Stub.animationTime + seconds, 0
    while true do
        local earliest
        for _, group in ipairs(Stub.animations) do
            if group.playing and group.endsAt and group.endsAt <= target + 1e-9
                and (not earliest or group.endsAt < earliest) then earliest = group.endsAt end
        end
        if not earliest then break end
        Stub.animationTime = earliest
        local ready = {}
        for _, group in ipairs(Stub.animations) do
            if group.playing and group.endsAt and group.endsAt <= earliest + 1e-9 then ready[#ready + 1] = group end
        end
        for _, group in ipairs(ready) do
            if group.playing and group.endsAt and group.endsAt <= earliest + 1e-9 then group:Finish() end
        end
        events = events + #ready; assert(events < 1000, "Unbounded fixture animation scheduling")
    end
    Stub.animationTime = target
end

function Stub.MenuItem(menu, text)
    for _, child in ipairs(menu.children) do if child.text == text then return child end end
    error("Missing menu item: " .. text)
end

return Stub
