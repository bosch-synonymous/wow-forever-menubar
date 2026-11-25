-- Original skin composition using artwork already supplied by the WoW client.
local Skins = { platinumSelection = { 0.22, 0.18, 0.51, 1 } }
_G.MenubarSkins = Skins

local fallbackColors = {
    warcraftBrown = { 0.20, 0.12, 0.055, 1 },
    warcraftBlack = { 0.035, 0.035, 0.035, 1 },
    warcraftRed = { 0.36, 0.035, 0.025, 1 },
}
local buttonFile = "Interface\\Buttons\\UI-Panel-Button-Up"
local insetFile = "Interface\\FrameGeneral\\UI-Background-Marble"
local titleAtlas = "_UI-Frame-TitleTileBg"
local bottomAtlases = {
    left = "UI-Frame-BotCornerLeft", middle = "_UI-Frame-Bot", right = "UI-Frame-BotCornerRight",
}
local bottomDimensions = { left = { 14, 14 }, middle = { 256, 9 }, right = { 11, 11 } }
local pieceOrder = { "left", "middle", "right" }
local buttonCoordinates = {
    left = { 0, 0.09375, 0, 0.6875 },
    middle = { 0.09375, 0.53125, 0, 0.6875 },
    right = { 0.53125, 0.625, 0, 0.6875 },
}

local function public(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

function Skins.IsWarcraft(theme)
    return fallbackColors[theme] ~= nil
end

function Skins.GetFallbackColor(theme)
    local color = fallbackColors[theme]
    return color and { color[1], color[2], color[3], color[4] } or nil
end

local function texture(parent, layer, level)
    local result = parent:CreateTexture(nil, layer, nil, level)
    result:Hide()
    return result
end

local function parts(parent, skin, key, layer, level)
    if not skin[key] then
        local result = {}
        for _, name in ipairs(pieceOrder) do result[name] = texture(parent, layer, level) end
        skin[key] = result
    end
    return skin[key]
end

local function hideParts(value)
    if value then for _, name in ipairs(pieceOrder) do value[name]:Hide() end end
end

local function hide(skin)
    if not skin then return end
    if skin.body then skin.body:Hide() end
    hideParts(skin.red)
    hideParts(skin.bottom)
    skin.active, skin.nativeBody, skin.nativeBottom = false, false, false
end

local function reset(value)
    value:SetTexture(nil)
    value:SetTexCoord(0, 1, 0, 1)
    value:SetHorizTile(false)
    value:SetVertTile(false)
    value:SetVertexColor(1, 1, 1, 1)
end

local function atlasInfo(name)
    if C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
        local ok, info = pcall(C_Texture.GetAtlasInfo, name)
        if not ok or not info then return false end
        return info
    end
    return true -- Known client assets can still be attempted without metadata enumeration.
end

local function setAtlas(value, name)
    if type(value.SetAtlas) ~= "function" or not atlasInfo(name) then return false end
    reset(value)
    local ok, result = pcall(value.SetAtlas, value, name, false)
    if not ok or result == false then return false end
    if type(value.GetAtlas) == "function" then
        local readOK, actual = pcall(value.GetAtlas, value)
        -- The native getter may canonicalize an accepted atlas name's casing.
        if not readOK or not public(actual) or type(actual) ~= "string" or actual:lower() ~= name:lower() then return false end
    end
    return true -- SetAtlas normally returns nil on success.
end

local function setFile(value, path)
    reset(value)
    local ok, result = pcall(value.SetTexture, value, path)
    return ok and result ~= false
end

local function tint(value, color)
    value:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

local function fallback(value, theme, color)
    local base = fallbackColors[theme]
    reset(value)
    value:SetColorTexture(base[1] * color[1], base[2] * color[2], base[3] * color[3],
        base[4] * (color[4] or 1))
end

local function redSurface(parent, skin, color)
    local pieces = parts(parent, skin, "red", "BACKGROUND", 1)
    local width, height = parent:GetWidth(), parent:GetHeight()
    -- Preserve the native 12:22 cap aspect until a very narrow control needs clamping.
    local cap = math.max(0, math.min(12 * height / 22, (width - 2) / 2))
    local native = true
    for _, name in ipairs(pieceOrder) do
        local value = pieces[name]
        native = setFile(value, buttonFile) and native
        value:SetTexCoord(unpack(buttonCoordinates[name]))
        tint(value, color)
        value:ClearAllPoints()
    end
    pieces.left:SetWidth(cap)
    pieces.left:SetPoint("TOPLEFT"); pieces.left:SetPoint("BOTTOMLEFT")
    pieces.right:SetWidth(cap)
    pieces.right:SetPoint("TOPRIGHT"); pieces.right:SetPoint("BOTTOMRIGHT")
    pieces.middle:SetPoint("TOPLEFT", pieces.left, "TOPRIGHT")
    pieces.middle:SetPoint("BOTTOMRIGHT", pieces.right, "BOTTOMLEFT")
    if native then
        for _, name in ipairs(pieceOrder) do pieces[name]:Show() end
    else hideParts(pieces) end
    return native
end

local function body(parent, skin, theme, color)
    skin.body = skin.body or texture(parent, "BACKGROUND", 1)
    skin.body:SetAllPoints()
    local native = false
    if theme == "warcraftRed" then native = redSurface(parent, skin, color)
    elseif theme == "warcraftBrown" then
        native = setAtlas(skin.body, titleAtlas)
        if native then skin.body:SetHorizTile(true) end
    elseif theme == "warcraftBlack" then
        native = setFile(skin.body, insetFile)
        if native then skin.body:SetHorizTile(true); skin.body:SetVertTile(true) end
    end
    if native and theme ~= "warcraftRed" then tint(skin.body, color); skin.body:Show()
    elseif not native then fallback(skin.body, theme, color); skin.body:Show() end
    skin.nativeBody = native
end

local function bottom(parent, skin, size, color)
    if size <= 0 then return false end
    local native = true
    for _, name in ipairs(pieceOrder) do if not atlasInfo(bottomAtlases[name]) then native = false end end
    if not native then return false end
    local pieces = parts(parent, skin, "bottom", "ARTWORK", 1)
    for _, name in ipairs(pieceOrder) do
        if not setAtlas(pieces[name], bottomAtlases[name]) then native = false end
    end
    if not native then hideParts(pieces); return false end
    for _, name in ipairs({ "left", "right" }) do
        local info = atlasInfo(bottomAtlases[name])
        local dimensions = bottomDimensions[name]
        local nativeWidth = type(info) == "table" and info.width or dimensions[1]
        local nativeHeight = type(info) == "table" and info.height or dimensions[2]
        if type(nativeWidth) ~= "number" or not (nativeWidth > 0 and nativeWidth < math.huge) then nativeWidth = dimensions[1] end
        if type(nativeHeight) ~= "number" or not (nativeHeight > 0 and nativeHeight < math.huge) then nativeHeight = dimensions[2] end
        local width = math.min(size * nativeWidth / nativeHeight, math.max(0, parent:GetWidth() / 2 - 1))
        pieces[name]:ClearAllPoints()
        pieces[name]:SetSize(width, size)
        pieces[name]:SetPoint(name == "left" and "BOTTOMLEFT" or "BOTTOMRIGHT")
    end
    pieces.middle:ClearAllPoints()
    pieces.middle:SetHeight(size)
    pieces.middle:SetPoint("BOTTOMLEFT", pieces.left, "BOTTOMRIGHT")
    pieces.middle:SetPoint("BOTTOMRIGHT", pieces.right, "BOTTOMLEFT")
    pieces.middle:SetHorizTile(true)
    for _, name in ipairs(pieceOrder) do tint(pieces[name], color); pieces[name]:Show() end
    return true
end

local function borders(control, shown)
    for _, line in ipairs(control.menubarBorder or {}) do line:SetShown(shown) end
end

local function chrome(control, profile, active)
    if not control then return end
    hide(control.warcraftSkin)
    if control.menubarBare or profile.theme == "macos27" then
        if control.background then control.background:Hide() end
        borders(control, false)
        return
    end
    if not active then
        if control.background then
            control.background:SetColorTexture(0.86, 0.86, 0.86, 1)
            control.background:SetVertexColor(1, 1, 1, 1)
            control.background:Show()
        end
        borders(control, true)
        return
    end
    local skin = control.warcraftSkin or {}
    control.warcraftSkin = skin
    skin.active, skin.theme = true, profile.theme
    local chromeColor = { profile.background[1], profile.background[2], profile.background[3], 1 }
    body(control, skin, profile.theme, chromeColor)
    if control.background then control.background:Hide() end
    borders(control, not skin.nativeBody)
end

function Skins.Apply(bar, profile)
    local active = Skins.IsWarcraft(profile.theme)
    hide(bar.warcraftSkin)
    if bar.background then bar.background:Show() end
    if bar.bottomLine then bar.bottomLine:SetShown(profile.bottomLineSize > 0) end
    chrome(bar.menu, profile, active)
    chrome(bar.overflow, profile, active)
    if not active then return false end
    local skin = bar.warcraftSkin or {}
    bar.warcraftSkin = skin
    skin.active, skin.theme = true, profile.theme
    if profile.texture == "theme" then
        body(bar.surface or bar, skin, profile.theme, profile.background)
        -- The native or fallback skin is the body, rather than an extra opaque
        -- layer over the flat backup (which would compound transparency).
        if bar.background then bar.background:Hide() end
    end
    skin.nativeBottom = bottom(bar, skin, profile.bottomLineSize, profile.bottomLine)
    if skin.nativeBottom and bar.bottomLine then bar.bottomLine:Hide() end
    return true
end

return Skins
