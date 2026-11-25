-- Only Menubar requests these styles. Menu textures belong to Blizzard's
-- compositor for the lifetime of a description. Hover art lives on one private tip.
local Popup = {}
MenubarSkins.Popup = Popup

local darkText = { 0.08, 0.09, 0.11 }
local darkMuted = { 0.28, 0.29, 0.31 }
local white = { 0.97, 0.98, 1 }
local lightMuted = { 0.76, 0.78, 0.81 }
local disabledText = { 0.5, 0.5, 0.5 }
local gold = { 1, 0.82, 0.25 }
local palettes = {
    system7 = { body = { 1, 1, 1, 1 }, edge = { 0, 0, 0, 1 }, light = true,
        highlight = { 0, 0, 0, 1 } },
    macos8 = { body = { 0.87, 0.87, 0.87, 1 }, edge = { 0.30, 0.30, 0.30, 1 },
        shine = { 1, 1, 1, 1 }, shade = { 0.57, 0.57, 0.59, 1 },
        light = true, highlight = { 0.68, 0.70, 0.80, 1 } },
    macosx = { body = { 0.95, 0.96, 0.98, 0.97 }, edge = { 0.50, 0.54, 0.61, 1 },
        shine = { 1, 1, 1, 1 }, light = true, highlight = { 0.56, 0.77, 0.98, 1 } },
    warcraftBrown = { body = { 0.13, 0.081, 0.046, 0.97 }, edge = { 0.61, 0.46, 0.28, 1 },
        shine = { 0.82, 0.60, 0.34, 0.70 }, accent = gold, highlight = { 0.35, 0.26, 0.13, 1 } },
    warcraftBlack = { body = { 0.04, 0.04, 0.045, 0.97 }, edge = { 0.42, 0.40, 0.36, 1 },
        accent = white, highlight = { 0.25, 0.24, 0.22, 1 } },
    warcraftRed = { body = { 0.20, 0.035, 0.033, 0.97 }, edge = { 0.53, 0.40, 0.22, 1 },
        shine = { 0.88, 0.47, 0.29, 0.55 }, accent = gold, highlight = { 0.40, 0.11, 0.08, 1 } },
}

-- Widget menus and the Glass tooltip use these materials, separately from the bar.
local material = "Interface\\AddOns\\Menubar\\Media\\Popup\\"
local menuStyles = {
    system7 = { light = true, body = palettes.system7.body, edge = palettes.system7.edge,
        ink = palettes.system7.edge, focusedInk = palettes.system7.body, highlight = palettes.system7.highlight,
        inset = { left = 1, top = 2, right = 3, bottom = 4 }, rowHeight = 20, divider = { 0.55, 0.55, 0.55, 1 } },
    macos8 = { light = true, body = { 0.86, 0.85, 0.83, 1 }, edge = { 0.12, 0.11, 0.13, 1 },
        highlight = MenubarSkins.platinumSelection, inset = { left = 3, top = 2, right = 5, bottom = 4 },
        rowHeight = 20, divider = { 0.39, 0.38, 0.40, 1 } },
    macosx = { light = true, body = { 0.97, 0.97, 0.98, 0.95 }, edge = { 0.54, 0.58, 0.62, 1 },
        highlight = { 0.17, 0.39, 0.69, 1 }, inset = { left = 2, top = 4, right = 2, bottom = 7 },
        rowHeight = 20, divider = { 0.49, 0.54, 0.62, 0.60 } },
    macos27 = { light = true, body = { 252 / 255, 253 / 255, 1, 1 }, edge = { 0.48, 0.51, 0.55, 0.70 },
        ink = { 0.01, 0.015, 0.02 }, muted = { 0.08, 0.09, 0.10 }, disabled = { 0.40, 0.40, 0.42 },
        highlight = { 0.07, 0.38, 0.84, 1 },
        inset = { left = 9, top = 8, right = 9, bottom = 10 },
        rowHeight = 24, divider = { 0.20, 0.22, 0.27, 0.29 } },
}
palettes.macos27 = menuStyles.macos27
local childPadding = { width = 18, height = 0 }

local function menuPalette(profile)
    return profile and (menuStyles[profile.theme] or palettes[profile.theme])
end

local function menuInk(style)
    return style.ink or style.accent or (style.light and darkText or white)
end

function Popup.DefaultTextColor(profile)
    return menuInk(menuPalette(profile))
end

local function selectedFace(text)
    if text.font ~= "theme" then return MenubarFonts.Resolve(text, Menubar.db.customFonts) end
end

-- Blizzard's menu compositor forbids SetFont on its FontStrings. Give each
-- native font object one private counterpart, reused across all sizes and faces.
local derivedFonts, nativeFonts = {}, {}
local fontCount = 0
local function applyFont(label, face, size, fallback)
    local bound = label:GetFontObject()
    if type(bound) == "string" then bound = _G[bound] end
    local native = nativeFonts[bound]
    if not face and size == 0 then
        if native then
            label:SetFontObject(native)
            return select(2, native:GetFont())
        end
        return
    end

    native = native or bound or fallback or GameFontHighlight
    local path, nativeSize, flags = native:GetFont()
    if not path or not nativeSize then return end
    face, size, flags = face or path, size > 0 and size or nativeSize, flags or ""
    local derived = derivedFonts[native]
    if not derived then
        fontCount = fontCount + 1
        derived = CreateFont("MenubarPopupFont" .. fontCount)
        if derived.CopyFontObject then derived:CopyFontObject(native) end
        derivedFonts[native], nativeFonts[derived] = derived, native
    end
    if derived.menubarFace ~= face or derived.menubarSize ~= size or derived.menubarFlags ~= flags then
        if not MenubarFonts.TrySetFont(derived, face, size, flags)
            and not MenubarFonts.TrySetFont(derived, path, size, flags) then
            label:SetFontObject(native)
            return nativeSize
        end
        derived.menubarFace, derived.menubarSize, derived.menubarFlags = face, size, flags
    end
    label:SetFontObject(derived)
    return size
end

local function paint(texture, colour)
    texture:SetColorTexture(unpack(colour))
end

local function horizontal(frame, attach, colour, side, left, right, y, height)
    local line = attach(frame)
    line:SetDrawLayer("BORDER")
    line:SetHeight(height)
    line:SetPoint(side .. "LEFT", frame, side .. "LEFT", left, y)
    line:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", -right, y)
    paint(line, colour)
    return line
end

local function vertical(frame, attach, colour, side, top, bottom, x, width)
    local line = attach(frame)
    line:SetDrawLayer("BORDER")
    line:SetWidth(width)
    line:SetPoint("TOP" .. side, frame, "TOP" .. side, x, -top)
    line:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, x, bottom)
    paint(line, colour)
end

local function outline(frame, attach, light, shade, left, top, right, bottom)
    horizontal(frame, attach, light, "TOP", left, right, -top, 1)
    horizontal(frame, attach, shade, "BOTTOM", left, right, bottom, 1)
    vertical(frame, attach, light, "LEFT", top + 1, bottom + 1, left, 1)
    vertical(frame, attach, shade, "RIGHT", top + 1, bottom + 1, -right, 1)
end

local function panelMaterial(texture, frame, style, part)
    local family = style == menuStyles.macosx and "aqua" or "glass"
    if texture:SetTexture(material .. family .. "-" .. part .. ".tga") == false then return false end
    texture:SetAllPoints(frame)
    if style == menuStyles.macosx then
        texture:SetTextureSliceMargins(2, 2, 2, 6)
        if texture.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
            texture:SetTextureSliceMode(Enum.UITextureSliceMode.Tiled)
        end
    else
        texture:SetTextureSliceMargins(17, 17, 17, 17)
    end
    return true
end

-- If native nine-slicing or either file is unavailable, build a rounded
-- silhouette from flat bands. A hollow rim keeps the world visible at 0%.
local glassCurve = { { 2, 2, 8 }, { 4, 3, 5 }, { 7, 3, 3 } }
local function glassFallback(frame, attach, face, style)
    face:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -10)
    face:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 10)
    paint(face, style.body)
    vertical(frame, attach, style.edge, "LEFT", 10, 10, 2, 1)
    vertical(frame, attach, style.edge, "RIGHT", 10, 10, -2, 1)
    local bands = {}
    for _, side in ipairs({ "TOP", "BOTTOM" }) do
        local sign = side == "TOP" and -1 or 1
        horizontal(frame, attach, style.edge, side, 12, 12, sign, 1)
        local previous = 12
        for _, band in ipairs(glassCurve) do
            local offset, height, outer = unpack(band)
            local y = sign * offset
            local fill = horizontal(frame, attach, style.body, side, previous, previous, y, height)
            fill:SetDrawLayer("BACKGROUND", -2)
            bands[#bands + 1] = fill
            for _, edge in ipairs({ "LEFT", "RIGHT" }) do
                local corner = side .. edge
                local rim = attach(frame)
                rim:SetDrawLayer("BORDER")
                rim:SetSize(previous - outer, height)
                rim:SetPoint(corner, frame, corner, edge == "LEFT" and outer or -outer, y)
                paint(rim, style.edge)
            end
            previous = outer
        end
    end
    return face, bands
end

local function setFaceOpacity(face, bands, opacity)
    face:SetAlpha(opacity)
    if bands then
        for _, band in ipairs(bands) do band:SetAlpha(opacity) end
    end
end

local function surface(frame, style, attach)
    local face = attach(frame)
    face:SetDrawLayer("BACKGROUND", -2)
    if (style == menuStyles.macosx or style == menuStyles.macos27) and face.SetTextureSliceMargins
        and panelMaterial(face, frame, style, "panel") then
        local rim = attach(frame)
        rim:SetDrawLayer("BORDER")
        if panelMaterial(rim, frame, style, "frame") then return face end
        rim:Hide()
        face:ClearAllPoints()
        face:SetTextureSliceMargins(0, 0, 0, 0)
    end

    if style == menuStyles.macos27 then return glassFallback(frame, attach, face, style) end

    -- Only the face owns the profile opacity. Rectangular borders, bevels and
    -- shadows must leave the middle hollow even with a fully transparent face.
    local classic = style == palettes.system7 or style == menuStyles.system7 or style == menuStyles.macos8
    local near = style.shade and 2 or 1
    local far = classic and 3 or near
    face:SetPoint("TOPLEFT", frame, "TOPLEFT", near, -near)
    face:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -far, far)
    paint(face, style.body)

    local shadow = classic and 2 or 0
    outline(frame, attach, style.edge, style.edge, 0, 0, shadow, shadow)
    if classic then
        vertical(frame, attach, style.edge, "RIGHT", shadow, 0, 0, shadow)
        horizontal(frame, attach, style.edge, "BOTTOM", shadow, shadow, 0, shadow)
    elseif style.shade then
        outline(frame, attach, style.shine, style.shade, 1, 1, 1, 1)
    elseif style.shine then
        horizontal(frame, attach, style.shine, "TOP", 1, 1, -1, 1)
    end
    return face
end

local function shadowStrength(style, profile)
    if style.light then return 0 end
    return math.min(1, 3 * (1 - profile.popupOpacity))
end

local function shadow(label, strength)
    -- Reset both properties when a pooled label moves onto a light surface.
    local offset = strength > 0 and 1 or 0
    label:SetShadowColor(0, 0, 0, strength)
    label:SetShadowOffset(offset, -offset)
end

local function ink(label, colour, strength)
    label:SetTextColor(colour[1], colour[2], colour[3], 1)
    shadow(label, strength)
end

function Popup.Label(label, muted)
    local profile = Menubar:GetProfile()
    local style = menuPalette(profile)
    if not style then return end
    local colour = style.light and (muted and (style.muted or darkMuted) or style.ink or darkText)
        or (muted and lightMuted or white)
    local text = profile.popupText
    applyFont(label, selectedFace(text), text.fontSize)
    ink(label, not muted and text.useCustomColor and text.textColor or colour, shadowStrength(style, profile))
end

-- Mac menus use a check for the active choice and an unadorned
-- chevron for a submenu. Retain the client's own buttons and choice semantics.
local function selectionGlyph(texture, column)
    texture:SetTexture(material .. "marks.tga")
    texture:SetTexCoord(column / 2, (column + 1) / 2, 0, 1)
    texture:SetSize(14, 14)
end

local function syncMenuRow(row, description)
    local style = row.menubarMenuStyle
    local enabled = not description or not description.IsEnabled or description:IsEnabled()
    if style.light and not enabled then row.highlight:Hide() end
    local focused = row.highlight:IsShown()
    local colour = not enabled and (style.disabled or (style.light and darkMuted or disabledText))
        or focused and (style.focusedInk or (style.light and white or menuInk(style))) or menuInk(style)
    ink(row.fontString, enabled and not focused and row.menubarCustomInk or colour,
        shadowStrength(style, Menubar:GetProfile()))
    if style.light then
        if row.arrow then row.arrow:SetVertexColor(unpack(colour)) end
        if row.leftTexture1 then row.leftTexture1:SetVertexColor(unpack(colour)) end
    end
end

-- Descriptions are initialized again during scrolling and menu refresh. Share
-- handlers and retain the native mouse and keyboard navigation on each lease.
local function menuRowEnter(row, description)
    row.menubarNativeEnter(row, description)
    syncMenuRow(row, description)
end

local function menuRowLeave(row, description)
    row.menubarNativeLeave(row, description)
    syncMenuRow(row, description)
end

local function styleMacRow(frame, item, style)
    if frame.divider then
        local line = frame.divider
        line:ClearAllPoints()
        line:SetPoint("LEFT", frame, "LEFT", 6, 0)
        line:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
        line:SetHeight(1)
        paint(line, style.divider)
        return 1, 7
    end
    local label, highlight = frame.fontString, frame.highlight
    if not label then return end -- A provider-owned control (e.g. Volume's slider).
    local mark, arrow = frame.leftTexture1, frame.arrow
    if mark then
        selectionGlyph(mark, 0)
        mark:ClearAllPoints()
        mark:SetPoint("LEFT", frame, "LEFT", 4, 0)
        label:ClearAllPoints()
        label:SetPoint("LEFT", mark, "RIGHT", 2, 0)
        mark:SetAlpha(item and item.IsSelected and item:IsSelected() and 1 or 0)
        if frame.leftTexture2 then frame.leftTexture2:Hide() end
    else
        label:ClearAllPoints()
        label:SetPoint("LEFT", frame, "LEFT", 8, 0)
    end
    if arrow then
        selectionGlyph(arrow, 1)
        arrow:ClearAllPoints()
        arrow:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    end
    if not highlight then return end
    if style == menuStyles.macos27 and highlight.SetTextureSliceMargins then
        highlight:ClearAllPoints()
        highlight:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -1)
        highlight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 1)
        highlight:SetTexture(material .. "glass-selection.tga")
        highlight:SetTextureSliceMargins(6, 6, 6, 6)
    elseif style == menuStyles.macosx then
        highlight:SetTexture(material .. "aqua-selection.tga", "REPEAT", "REPEAT")
        highlight:SetVertTile(true)
        highlight:SetHorizTile(true)
    end
end

local function attachMenu(frame) return frame:AttachTexture() end

-- Blizzard shares a menu mixin with all submenus of one description.
-- Pass a private copy when the client's supported style methods are present.
function Popup.Menu(native)
    local profile = Menubar:GetProfile()
    local style = menuPalette(profile)
    if not style or type(native.Generate) ~= "function" or type(native.GetChildExtentPadding) ~= "function" then
        return native
    end
    local text = profile.popupText
    local face = selectedFace(text)
    local customInk = text.useCustomColor and text.textColor
    local mixin = {}
    for key, value in pairs(native) do mixin[key] = value end
    mixin.Generate = function(frame)
        local face, bands = surface(frame, style, attachMenu)
        setFaceOpacity(face, bands, Menubar:GetProfile().popupOpacity)
    end
    if style.inset then
        mixin.GetInset = function() return style.inset end
        mixin.GetChildExtentPadding = function() return childPadding end
    end
    local function styleElement(frame, description)
        if frame.highlight then
            frame.highlight:SetBlendMode("BLEND")
            paint(frame.highlight, style.highlight)
        end
        if style.rowHeight then
            local width, height = styleMacRow(frame, description, style)
            if width then return width, height end
        end
        local label = frame.fontString
        if not label then return end
        local size = applyFont(label, face, text.fontSize)
        if size then
            -- Blizzard measured the label in its original font before this initializer.
            label:SetHeight(math.max(style.rowHeight or 20, math.ceil(size) + 6))
            local caption = label:GetText()
            if not issecretvalue or not issecretvalue(caption) then
                if label.SetTextToFit then label:SetTextToFit(caption or "")
                else label:SetWidth(math.ceil(label:GetStringWidth())) end
            end
        elseif style.rowHeight then
            label:SetHeight(style.rowHeight)
        end
        if not frame.highlight then
            ink(label, customInk or menuInk(style), shadowStrength(style, profile))
            return
        end
        frame.menubarMenuStyle, frame.menubarCustomInk = style, customInk
        if frame.OnEnter and frame.OnLeave and frame.OnEnter ~= menuRowEnter then
            frame.menubarNativeEnter, frame.menubarNativeLeave = frame.OnEnter, frame.OnLeave
            frame.OnEnter, frame.OnLeave = menuRowEnter, menuRowLeave
        end
        syncMenuRow(frame, description)
    end
    return mixin, styleElement
end

local tip
local tooltipTextures = {}
local function paintTooltip(style)
    local index = 0
    local function attach(frame)
        index = index + 1
        local texture = tooltipTextures[index]
        if texture then
            -- The same slot can be a sliced face, a shadow or a short solid
            -- corner band on the next theme. Reset the state those roles set.
            texture:ClearAllPoints()
            texture:SetSize(0, 0)
            texture:SetTexture(nil)
            texture:SetAlpha(1)
            if texture.SetTextureSliceMargins then texture:SetTextureSliceMargins(0, 0, 0, 0) end
        else
            texture = frame:CreateTexture(nil, "BACKGROUND")
            tooltipTextures[index] = texture
        end
        texture:Show()
        return texture
    end
    tip.menubarFace, tip.menubarFaceBands = surface(tip, style, attach)
    for unused = index + 1, #tooltipTextures do tooltipTextures[unused]:Hide() end
    if tip.NineSlice then tip.NineSlice:Hide() end
end

function Popup.Tooltip()
    local profile = Menubar:GetProfile()
    local style = profile and palettes[profile.theme]
    if not style or not GameTooltip or type(GameTooltip.NumLines) ~= "function" then return GameTooltip end
    if tip == nil then
        local ok, owned = pcall(CreateFrame, "GameTooltip", "MenubarWidgetTooltip", UIParent, "GameTooltipTemplate")
        tip = ok and owned or false
    end
    if not tip then return GameTooltip end
    if tip.menubarStyle ~= style then
        paintTooltip(style)
        tip.menubarStyle = style
    end
    setFaceOpacity(tip.menubarFace, tip.menubarFaceBands, profile.popupOpacity)
    return tip
end

local function styleTooltipLine(label, style, first, strength, face, text)
    if not label then return end
    local red, green, blue = label:GetTextColor()
    if issecretvalue and (issecretvalue(red) or issecretvalue(green) or issecretvalue(blue)) then return end
    -- Binding a font object can also replace the colour supplied by AddLine.
    applyFont(label, face, text.fontSize, first and GameTooltipHeaderText or GameTooltipText)
    local neutral = math.abs(red - green) < 0.03 and math.abs(green - blue) < 0.03
    local standardGold = red > 0.97 and green > 0.78 and green < 0.85 and blue < 0.05
    if first or standardGold or neutral then
        local muted = neutral and red < 0.85 and not first
        local colour = style.light and (muted and (style.muted or darkMuted) or style.ink or darkText)
            or (first or standardGold) and (style.accent or white) or muted and lightMuted or white
        ink(label, not muted and text.useCustomColor and text.textColor or colour, strength)
    else
        -- Retain status hues on both surfaces and the existing darker ink
        -- treatment against pale panels.
        local scale = style.light and 0.48 or 1
        label:SetTextColor(red * scale, green * scale, blue * scale, 1)
        shadow(label, strength)
    end
end

function Popup.Show(tooltip)
    if tooltip ~= tip then tooltip:Show(); return end
    local profile, style = Menubar:GetProfile(), tip.menubarStyle
    local text = profile.popupText
    local face, strength = selectedFace(text), shadowStrength(style, profile)
    for row = 1, tip:NumLines() do
        styleTooltipLine(_G["MenubarWidgetTooltipTextLeft" .. row], style, row == 1, strength, face, text)
        styleTooltipLine(_G["MenubarWidgetTooltipTextRight" .. row], style, row == 1, strength, face, text)
    end
    -- The client measures the tooltip on Show, after its line fonts are final.
    tip:Show()
    if tip.NineSlice then tip.NineSlice:Hide() end
end

return Popup
