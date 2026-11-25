-- Exercise the two native skin entry points with real host dispatch. The shared
-- stub models menus separately from their rendering; supply the compositor calls here.
local root = REPO_ROOT or "."
local Stub = dofile(root .. "/tests/wow_stub.lua")
Stub.Install()
for line in io.lines(root .. "/src/menubar-core/Menubar.toc") do
    local file = line:match("^%s*(%S+%.lua)%s*$")
    if file then dofile(root .. "/src/menubar-core/" .. file) end
end

local native = MenuVariants.GetDefaultContextMenuMixin()
local originalGenerate = function() error("unexpected global style mutation") end
native.Generate = originalGenerate
native.GetChildExtentPadding = function() return { width = 0, height = 0 } end
-- The native texture renderer interprets these pixel margins. Verify the
-- material/layout requested from it and the compositor's per-row ownership.
local Region = getmetatable(UIParent)
function Region:SetTextureSliceMargins(...) self.slice = { ... } end
function Region:SetTextureSliceMode(mode) self.sliceMode = mode end
Enum = Enum or {}
Enum.UITextureSliceMode = { Tiled = 1 }
local create = CreateFrame
local ownedCount = 0
function GameTooltip:NumLines() return #self.lines end
CreateFrame = function(kind, name, parent, template)
    if kind ~= "GameTooltip" then return create(kind, name, parent, template) end
    assert(template == "GameTooltipTemplate")
    local frame = create(kind, name, parent)
    if kind == "GameTooltip" then
        ownedCount = ownedCount + 1
        frame.NineSlice = create("Frame", nil, frame)
        frame.SetOwner, frame.GetOwner, frame.NumLines = GameTooltip.SetOwner, GameTooltip.GetOwner, GameTooltip.NumLines
        local function setLine(side, text, red, green, blue)
            local key = name .. "Text" .. side .. frame:NumLines()
            local template = frame:NumLines() == 1 and "GameFontNormalLarge" or "GameFontHighlightSmall"
            local line = _G[key] or frame:CreateFontString(key, "ARTWORK", template)
            line:SetText(text)
            line:SetTextColor(red or 1, green or 0.82, blue or 0)
        end
        frame.AddLine = function(self, text, red, green, blue)
            GameTooltip.AddLine(self, text)
            setLine("Left", text, red, green, blue)
        end
        frame.AddDoubleLine = function(self, left, right, lr, lg, lb, rr, rg, rb)
            GameTooltip.AddDoubleLine(self, left, right)
            setLine("Left", left, lr, lg, lb)
            setLine("Right", right, rr, rg, rb)
        end
        frame:SetScript("OnHide", function(self) self.NineSlice:Show() end)
    end
    return frame
end
Menubar:RegisterWidgetType({
    id = "popup", name = "Popup", defaults = {},
    update = function(widget) widget:SetText("Popup") end,
    tooltip = function(_, tip)
        tip:AddLine("Title")
        tip:AddLine("Faint hint", 0.6, 0.6, 0.6)
        tip:AddLine("Warning", 1, 0.3, 0.2)
    end,
})
local masterVolume = "0.5"
C_CVar = {
    GetCVar = function(key) return key == "Sound_MasterVolume" and masterVolume or "1" end,
    SetCVar = function(key, value) if key == "Sound_MasterVolume" then masterVolume = tostring(value) end; return true end,
}
GetRealZoneText = function() return "The Barrens" end
GetSubZoneText = function() return "The Crossroads" end
C_Texture = { GetAtlasInfo = function() return { width = 16, height = 16 } end }
dofile(root .. "/src/menubar-location/TerritoryData.lua")
dofile(root .. "/src/menubar-location/Location.lua")
dofile(root .. "/src/menubar-time/Time.lua")
dofile(root .. "/src/menubar-volume/Volume.lua")
Menubar:Start()
local widget, volume, location, clock
for _, active in pairs(Menubar.runtime) do
    if active.instance.type == "popup" then widget = active end
    if active.instance.type == "location" then location = active end
    if active.instance.type == "time" then clock = active end
    if active.instance.type == "volume" then volume = active end
end
assert(widget and volume and location and clock and not (volume.failed or location.failed or clock.failed))
local foreign = create("Frame")
GameTooltip:SetOwner(foreign)
GameTooltip:AddLine("An unrelated item")
GameTooltip:Show()

local themes = { "system7", "macos8", "macosx", "macos27", "warcraftBrown", "warcraftBlack", "warcraftRed" }
local popupMedia = "Interface\\AddOns\\Menubar\\Media\\Popup\\"
local function findTexture(frame, path)
    for _, texture in ipairs(Stub.textures) do
        if texture:GetParent() == frame and texture:IsShown() and texture:GetTexture() == path then return texture end
    end
end
for _, theme in ipairs(themes) do
    assert(MenubarModel.ApplyTheme(Menubar:GetProfile(), theme))
    widget.frame.scripts.OnEnter(widget.frame)
    local tip = MenubarWidgetTooltip
    assert(tip:GetOwner() == widget.frame and tip:IsShown() and not tip.NineSlice:IsShown())
    if theme == "system7" or theme == "macos27" then
        assert(MenubarWidgetTooltipTextLeft2:GetTextColor() < 0.4)
        local red, green, blue = MenubarWidgetTooltipTextLeft3:GetTextColor()
        assert(red < 0.55 and red > green and green > blue)
    end
    Menubar.UI:Context(widget.frame, function(menu)
        local submenu = menu:CreateButton("Actions")
        submenu:CreateButton("Leaf", function() end)
    end)
    assert(not tip:IsShown())
    local description = Stub.menus[#Stub.menus]
    assert(description.mixin.Generate ~= originalGenerate)
    local surface = create("Frame")
    description.mixin.Generate(surface)
    local row = create("Button")
    row.fontString = row:AttachFontString()
    row.highlight = row:AttachTexture()
    Stub.MenuItem(description, "Actions").initializer(row)
    assert(row.highlight.blendMode == "BLEND")
    if theme == "system7" then
        local enabled, enters, leaves = true, 0, 0
        local state = { IsEnabled = function() return enabled end }
        row.arrow = row:AttachTexture()
        row.OnEnter = function(button) enters = enters + 1; button.highlight:Show() end
        row.OnLeave = function(button) leaves = leaves + 1; button.highlight:Hide() end
        row.highlight:Show() -- Native menu can open with a row already focused.
        Stub.MenuItem(description, "Actions").initializer(row, state)
        assert(row.highlight.color[1] == 0 and row.fontString:GetTextColor() == 1)
        row:OnLeave(state)
        assert(row.fontString:GetTextColor() == 0 and row.arrow.vertexColor[1] == 0)
        row:OnEnter(state)
        assert(row.fontString:GetTextColor() == 1 and row.arrow.vertexColor[1] == 1)
        enabled = false
        row.fontString:SetTextColor(0.5, 0.5, 0.5, 1)
        row:OnEnter(state)
        assert(not row.highlight:IsShown() and row.fontString:GetTextColor() > 0.20
            and row.fontString:GetTextColor() < 0.55)
        local inset = description.mixin:GetInset()
        assert(inset.left == 1 and inset.right == 3)
        local divider = create("Frame")
        divider.divider = divider:AttachTexture()
        Stub.MenuItem(description, "Actions").initializer(divider, state)
        assert(divider.divider:GetHeight() == 1 and divider.divider.color[1] == 0.55)
        assert(enters == 2 and leaves == 1)
        row.OnEnter, row.OnLeave = nil, nil
    end
    if theme == "macos27" or theme == "macosx" or theme == "macos8" then
        local glass, aqua = theme == "macos27", theme == "macosx"
        if glass or aqua then
            local prefix = "Interface\\AddOns\\Menubar\\Media\\Popup\\"
            local family = glass and "glass" or "aqua"
            local panel = assert(findTexture(surface, prefix .. family .. "-panel.tga"))
            local rim = assert(findTexture(surface, prefix .. family .. "-frame.tga"))
            assert(table.concat(rim.slice, ",") == table.concat(panel.slice, ","))
            assert(table.concat(panel.slice, ",") == (glass and "17,17,17,17" or "2,2,2,6"))
            if aqua then assert(panel.sliceMode == Enum.UITextureSliceMode.Tiled) end
            assert(row.highlight:GetTexture() == prefix .. (glass and "glass-selection.tga" or "aqua-selection.tga"))
            if glass then
                assert(table.concat(row.highlight.slice, ",") == "6,6,6,6")
            else
                assert(row.highlight.vertTile)
            end
        else
            assert(table.concat(row.highlight.color, ",") == table.concat(MenubarSkins.platinumSelection, ","))
        end
        local enabled, selected = true, true
        local item = { IsEnabled = function() return enabled end, IsSelected = function() return selected end }
        row.leftTexture1, row.leftTexture2, row.arrow = row:AttachTexture(), row:AttachTexture(), row:AttachTexture()
        row.OnEnter = function(button) button.highlight:Show() end
        row.OnLeave = function(button) button.highlight:Hide() end
        row.highlight:Hide()
        local initialize = Stub.MenuItem(description, "Actions").initializer
        initialize(row, item)
        assert(row.fontString:GetHeight() == (glass and 24 or 20))
        assert(row.leftTexture1:GetAlpha() == 1 and not row.leftTexture2:IsShown())
        assert(row.leftTexture1.texCoords[1] == 0 and row.arrow.texCoords[1] == 0.5)
        row:OnEnter(item)
        assert(row.fontString:GetTextColor() > 0.95 and row.arrow.vertexColor[1] > 0.95)
        row:OnLeave(item)
        assert(row.fontString:GetTextColor() < 0.15 and row.leftTexture1.vertexColor[1] < 0.15)
        enabled = false
        row:OnEnter(item)
        assert(not row.highlight:IsShown())
        selected = false
        local fresh = create("Button")
        fresh.fontString, fresh.highlight, fresh.leftTexture1 = fresh:AttachFontString(), fresh:AttachTexture(), fresh:AttachTexture()
        initialize(fresh, item)
        assert(fresh.leftTexture1:GetAlpha() == 0)
        local divider = create("Frame")
        divider.divider = divider:AttachTexture()
        local _, height = initialize(divider, item)
        assert(height == 7 and divider.divider:GetHeight() == 1)
        local volumeLabel = fresh:AttachFontString()
        Menubar.UI:StylePopupLabel(volumeLabel)
        assert(volumeLabel:GetTextColor() < 0.15)
        if glass then
            Menubar.UI:StylePopupLabel(volumeLabel, true)
            assert(volumeLabel:GetTextColor() == 0.08 and fresh.fontString:GetTextColor() == 0.40)
        end
        row.OnEnter, row.OnLeave = nil, nil
    end
    Stub.MenuItem(Stub.MenuItem(description, "Actions"), "Leaf").initializer(row)
    assert(native.Generate == originalGenerate)
end
assert(ownedCount == 1)
-- Sample inside a 160 x 64 popup. The stub's GetRect handles only the first
-- anchor, so resolve the opposing corner anchors used by popup materials here.
local width, height = 160, 64
local function extent(texture, horizontal)
    local dimension = horizontal and width or height
    if texture.allPoints then return 0, dimension end
    local low, high = horizontal and "LEFT" or "TOP", horizontal and "RIGHT" or "BOTTOM"
    local first, last
    for _, point in ipairs(texture.points) do
        assert(point[1] == point[3] and point[2] == texture:GetParent())
        local offset = horizontal and (point[4] or 0) or -(point[5] or 0)
        if point[1]:find(low, 1, true) then first = offset end
        if point[1]:find(high, 1, true) then last = dimension + offset end
    end
    local size = (horizontal and texture.width) or (not horizontal and texture.height)
    return first or (last - size), last or (first + size)
end

-- A nine-sliced face and its rim share a rectangle. Read the actual TGA
-- pixels so a full-panel shadow or rim with an opaque centre fails this test.
local bitmaps = {}
local function pixelAlpha(path, texture, x, y, w, h)
    local data = bitmaps[path]
    if not data then
        local file = assert(io.open(root .. "/src/menubar-core/Media/Popup/" .. path:sub(#popupMedia + 1), "rb"))
        data = file:read("*a"); file:close(); bitmaps[path] = data
        assert(data:byte(3) == 2 and data:byte(17) == 32 and data:byte(18) == 40)
    end
    local cols, rows = data:byte(13) + 256 * data:byte(14), data:byte(15) + 256 * data:byte(16)
    local function texel(offset, extent, pixels, near, far)
        if offset < near then return math.floor(offset) end
        if offset >= extent - far then return math.floor(pixels - extent + offset) end
        local span = pixels - near - far
        if texture.sliceMode == Enum.UITextureSliceMode.Tiled then return near + math.floor(offset - near) % span end
        return near + math.floor((offset - near) / (extent - near - far) * span)
    end
    local s = texture.slice
    local col = texel(x, w, cols, s[1], s[3])
    local row = texel(y, h, rows, s[2], s[4])
    return data:byte(18 + (row * cols + col) * 4 + 4) / 255
end

local function composite(frame, x, y)
    local clear = 1
    for _, texture in ipairs(Stub.textures) do
        if texture:GetParent() == frame and texture:IsShown() then
            local l, r = extent(texture, true)
            local t, b = extent(texture, false)
            if x >= l and x < r and y >= t and y < b then
                local path = texture:GetTexture()
                local material = path and pixelAlpha(path, texture, x - l, y - t, r - l, b - t)
                    or (texture.color and texture.color[4] or 1)
                clear = clear * (1 - material * texture:GetEffectiveAlpha() * (texture.vertexColor and texture.vertexColor[4] or 1))
            end
        end
    end
    return 1 - clear
end

local function near(value, expected)
    assert(math.abs(value - expected) < 0.00001, ("expected %.4f, got %.4f"):format(expected, value))
end

-- Light Mac surfaces use flat ink even at low face opacity. Warcraft's
-- translucent surfaces use a dark shadow. In both cases the glyph stays opaque.
local function checkInk(label, opacity, lightPanel)
    local _, _, _, alpha = label:GetTextColor()
    near((alpha or 1) * label:GetEffectiveAlpha(), 1)
    local x, y = label:GetShadowOffset()
    local r, g, b, a = label:GetShadowColor()
    if lightPanel or opacity == 1 then
        assert(x == 0 and y == 0 and a == 0, "flat text should clear any pooled shadow")
    else
        assert((x ~= 0 or y ~= 0) and a > 0 and r == 0 and g == 0 and b == 0,
            "translucent Warcraft panels should keep a black text shadow")
    end
end

local function sample(frame, glass)
    return { centre = composite(frame, 80.5, 32.5), edge = composite(frame, glass and 2.5 or 0.5, 32.5),
        shadow = composite(frame, 80.5, 63.5) }
end
local function checkOpacity(theme, fallback)
    local profile = Menubar:GetProfile()
    if fallback then
        MenubarModel.ApplyTheme(profile, "warcraftBlack")
        MenubarSkins.Popup.Tooltip() -- Reacquire the material with this capability set.
    end
    assert(MenubarModel.ApplyTheme(profile, theme))
    local glass = theme == "macos27"
    profile.opacity, profile.popupOpacity = 0.63, 1
    clock.frame:Click("LeftButton")
    local description = Stub.menus[#Stub.menus]
    assert(description.title == "Choose time zone")
    local choice = assert(Stub.MenuItem(description, "Player"))
    local light = not MenubarSkins.IsWarcraft(theme)
    local row = create("Button")
    row.fontString, row.highlight = row:AttachFontString(), row:AttachTexture()
    row.leftTexture1, row.arrow = row:AttachTexture(), row:AttachTexture()
    row.OnEnter = function(button) button.highlight:Show() end
    row.OnLeave = function(button) button.highlight:Hide() end
    local fullMenu, fullTip, previous
    for _, opacity in ipairs({ 1, 0, 0.37, 0.45, 0.7, 1 }) do
        -- Reuse the mixin as a submenu would. Reopen the same private tooltip
        -- without invalidating it or applying another theme.
        profile.popupOpacity = opacity
        local surface = create("Frame")
        surface:SetSize(width, height)
        description.mixin.Generate(surface)
        local tip = MenubarSkins.Popup.Tooltip()
        tip:SetSize(width, height)
        local menuSample, tipSample = sample(surface, glass), sample(tip, glass)
        if opacity == 1 then
            fullMenu, fullTip, previous = menuSample, tipSample, tip
            assert(fullMenu.centre > 0.7 and fullTip.centre > 0.7)
            assert(fullMenu.edge + fullMenu.shadow > 0 and fullTip.edge + fullTip.shadow > 0)
        end
        assert(tip == previous and tip:GetEffectiveAlpha() == 1 and surface:GetEffectiveAlpha() == 1)
        for k, result in ipairs({ menuSample, tipSample }) do
            local full = k == 1 and fullMenu or fullTip
            near(result.centre, full.centre * opacity)
            near(result.edge, full.edge)
            near(result.shadow, full.shadow)
        end
        if glass then
            -- Sample inside the curves and outside all four corners at game scale.
            for _, panel in ipairs({ surface, tip }) do
                for _, corner in ipairs({ {2.5, 2.5}, {157.5, 2.5}, {2.5, 61.5}, {157.5, 61.5} }) do
                    assert(composite(panel, corner[1], corner[2]) < 0.035)
                end
                near(composite(panel, 80.5, 32.5), opacity)
                near(composite(panel, 80.5, 6.5), opacity)
            end
            if not fallback then
                assert(findTexture(tip, popupMedia .. "glass-frame.tga"))
                assert(findTexture(tip, popupMedia .. "glass-panel.tga"))
                local data = bitmaps[popupMedia .. "glass-panel.tga"]
                local blue, green, red, alpha = data:byte(19 + (32 * 64 + 32) * 4, 22 + (32 * 64 + 32) * 4)
                assert(red == 252 and green == 253 and blue == 255 and alpha == 255)
            end
            location.frame.scripts.OnEnter(location.frame)
            assert(MenubarWidgetTooltipTextLeft1:GetText() == "Location")
            assert(MenubarWidgetTooltipTextLeft3:GetText() == "Zone")
            assert(MenubarWidgetTooltipTextRight3:GetText() == "The Barrens")
            near(MenubarWidgetTooltipTextLeft3:GetTextColor(), 0.01)
            near(MenubarWidgetTooltipTextRight3:GetTextColor(), 0.01)
            checkInk(MenubarWidgetTooltipTextLeft3, opacity, light)
            checkInk(MenubarWidgetTooltipTextRight3, opacity, light)
            local hint = _G["MenubarWidgetTooltipTextLeft" .. tip:NumLines()]
            local red, green, blue = hint:GetTextColor()
            assert(red == 0.08 and green == 0.09 and blue == 0.10)
            assert(hint:GetText():find("|A:newplayertutorial%-icon%-mouse"))
            checkInk(hint, opacity, light)
        end
        local heading = create("Frame", nil, surface)
        heading.fontString = heading:AttachFontString()
        choice.initializer(heading, choice) -- native title-shaped row has no highlight
        checkInk(heading.fontString, opacity, light)
        row:SetParent(surface)
        row:Show(); row.highlight:Hide()
        local enabled = true
        local state = { IsSelected = function() return true end, IsEnabled = function() return enabled end }
        choice.initializer(row, state)
        checkInk(row.fontString, opacity, light)
        if light then
            local normal = row.fontString:GetTextColor()
            assert(normal < 0.15)
            row:OnEnter(state)
            assert(row.highlight:IsShown() and row.fontString:GetTextColor() > 0.95)
            checkInk(row.fontString, opacity, light)
            row:OnLeave(state)
            near(row.fontString:GetTextColor(), normal)
            checkInk(row.fontString, opacity, light)
            enabled = false
            row:OnEnter(state)
            assert(not row.highlight:IsShown() and row.fontString:GetTextColor() > normal + 0.15)
            checkInk(row.fontString, opacity, light)
            enabled = true
            row:OnLeave(state)
            near(row.fontString:GetTextColor(), normal)
            checkInk(row.fontString, opacity, light)
        end
        for _, foreground in ipairs({ row.fontString, row.highlight, row.leftTexture1, row.arrow }) do
            near(foreground:GetEffectiveAlpha(), 1)
        end
        widget.frame.scripts.OnEnter(widget.frame)
        checkInk(MenubarWidgetTooltipTextLeft1, opacity, light)
        checkInk(MenubarWidgetTooltipTextLeft3, opacity, light) -- provider warning colour
        assert(tip:IsShown() and not tip.NineSlice:IsShown())
        if fallback then
            assert(not findTexture(surface, popupMedia .. "aqua-panel.tga"))
            assert(not findTexture(surface, popupMedia .. "glass-panel.tga"))
        end
    end
end
for _, theme in ipairs(themes) do checkOpacity(theme) end

-- Vary each control independently while reusing the same tooltip and dropdown row.
do
    local profile = Menubar:GetProfile()
    assert(MenubarModel.ApplyTheme(profile, "macos27"))
    local previousTip
    local row = create("Button")
    row.fontString, row.highlight = row:AttachFontString(), row:AttachTexture()
    row.leftTexture1 = row:AttachTexture()
    row.highlight:Hide()
    for _, settings in ipairs({ { 0.45, 0.9 }, { 0.45, 0 }, { 1, 0 }, { 0, 1 }, { 0, 0.72 } }) do
        local barAlpha, expected = settings[1], settings[2]
        profile.opacity, profile.popupOpacity = barAlpha, expected
        Menubar:Rebuild()
        clock.frame:Click("LeftButton")
        local menu = Stub.menus[#Stub.menus]
        local panel = create("Frame")
        panel:SetSize(width, height)
        menu.mixin.Generate(panel)
        near(composite(panel, 80.5, 32.5), expected)
        row:SetParent(panel)
        for _, text in ipairs({ "Player", "Server" }) do
            local choice = Stub.MenuItem(menu, text)
            choice.initializer(row, choice)
            near(row.leftTexture1:GetEffectiveAlpha(), text == "Player" and 1 or 0)
            checkInk(row.fontString, expected, true)
        end
        location.frame.scripts.OnEnter(location.frame)
        local tip = MenubarWidgetTooltip
        assert(not previousTip or tip == previousTip)
        previousTip = tip
        tip:SetSize(width, height)
        near(composite(tip, 80.5, 32.5), expected)
        checkInk(MenubarWidgetTooltipTextRight3, expected, true)
        near(Menubar.bars.top.surface:GetEffectiveAlpha(), barAlpha)
    end
end

local slice = Region.SetTextureSliceMargins
Region.SetTextureSliceMargins = nil
checkOpacity("macosx", true); checkOpacity("macos27", true)
Region.SetTextureSliceMargins = slice

-- The client replaces any existing file material when SetColorTexture runs.
local setTexture, setColor = Region.SetTexture, Region.SetColorTexture
function Region:SetColorTexture(...)
    self.texture = nil
    return setColor(self, ...)
end
for theme, family in pairs({ macosx = "aqua", macos27 = "glass" }) do
    for _, part in ipairs({ "panel", "frame" }) do
        Region.SetTexture = function(self, path, ...)
            if path == popupMedia .. family .. "-" .. part .. ".tga" then return false end
            return setTexture(self, path, ...)
        end
        checkOpacity(theme, true)
    end
end
Region.SetTexture, Region.SetColorTexture = setTexture, setColor

-- Reuse Glass textures as solid tooltip strokes; stale nine-slice margins,
-- reduced face-band alpha and unhidden corner fragments would change this skin.
local profile = Menubar:GetProfile()
MenubarModel.ApplyTheme(profile, "macos27")
profile.popupOpacity = 0
MenubarSkins.Popup.Tooltip()
MenubarModel.ApplyTheme(profile, "warcraftBrown")
profile.popupOpacity = 1
local restored = MenubarSkins.Popup.Tooltip()
for _, region in ipairs(Stub.textures) do
    if region:GetParent() == restored and region:IsShown() then
        assert(region:GetTexture() == nil and region:GetAlpha() == 1)
        assert(not region.slice or table.concat(region.slice, ",") == "0,0,0,0")
    end
end
-- Switch live themes at the reported opacity. The client recycles FontStrings
-- across menus, and both columns of the private tooltip persist across hovers.
local pooled = create("Button")
pooled.fontString, pooled.highlight = pooled:AttachFontString(), pooled:AttachTexture()
for _, theme in ipairs({ "warcraftBrown", "macos27", "warcraftRed", "system7", "macos8", "macosx" }) do
    assert(MenubarModel.ApplyTheme(profile, theme))
    profile.popupOpacity = 0.45
    clock.frame:Click("LeftButton")
    local player = Stub.MenuItem(Stub.menus[#Stub.menus], "Player")
    player.initializer(pooled, player)
    location.frame.scripts.OnEnter(location.frame)
    local light = not MenubarSkins.IsWarcraft(theme)
    checkInk(pooled.fontString, 0.45, light)
    checkInk(MenubarWidgetTooltipTextLeft3, 0.45, light)
    checkInk(MenubarWidgetTooltipTextRight3, 0.45, light)
end
-- A native slider is a child of the themed menu. At zero face alpha its
-- track, thumb and wheel handler must still work through that parent.
local function volumeControls()
    volume.frame:Click("LeftButton")
    local menu = Stub.menus[#Stub.menus]
    local surface = create("Frame")
    surface:SetSize(width, height)
    menu.mixin.Generate(surface)
    local element = create("Frame", nil, surface)
    local labels = {}
    function element:AttachFontString(...)
        local label = Region.AttachFontString(self, ...)
        labels[#labels + 1] = label
        return label
    end
    local first = #Stub.frames + 1
    for _, child in ipairs(menu.children) do
        if child.kind == "Frame" then
            for _, initialize in ipairs(child.initializers) do initialize(element, child, menu) end
        end
    end
    local slider
    for i = first, #Stub.frames do if Stub.frames[i].kind == "Slider" then slider = Stub.frames[i] end end
    assert(slider and slider:GetParent() == element and slider:IsVisible() and slider.mouseWheelEnabled)
    return slider, labels, surface
end
local function checkVolume(theme, opacity)
    assert(MenubarModel.ApplyTheme(profile, theme))
    profile.opacity, profile.popupOpacity = 0.62, opacity
    local slider, labels, surface = volumeControls()
    if theme == "macos27" then near(composite(surface, 80.5, 32.5), opacity) end
    near(slider:GetEffectiveAlpha(), 1)
    assert(#labels == 3) -- current volume and slider endpoints
    for _, label in ipairs(labels) do
        checkInk(label, opacity, true)
        if theme == "macos27" then
            local endpoint = label:GetText() == "0%" or label:GetText() == "100%"
            near(label:GetTextColor(), endpoint and 0.08 or 0.01)
        end
    end
    local thumb, track = slider:GetThumbTexture()
    for _, texture in ipairs(Stub.textures) do
        if texture:GetParent() == slider and texture:GetAtlas() == "_Minimal_SliderBar_Middle" then track = texture end
    end
    assert(track and track:IsVisible() and thumb:IsVisible())
    near(thumb:GetEffectiveAlpha(), 1); near(track:GetEffectiveAlpha(), 1)
    local old = tonumber(masterVolume)
    slider.scripts.OnMouseWheel(slider, 1)
    assert(tonumber(masterVolume) > old)
end
for _, opacity in ipairs({ 0, 0.37, 0.45, 1 }) do
    checkVolume("macosx", opacity)
    checkVolume("macos27", opacity)
end

-- The same row, tooltip and provider labels can move between font overrides and native templates.
do
    local regular, italic = "Custom\\Panel.ttf", "Custom\\PanelItalic.ttf"
    assert(MenubarFonts.AddCustom(Menubar.db, "Panel", regular, { italic = italic }))
    local custom = { 0.31, 0.19, 0.47, 1 }
    local function checkFont(label, face, size)
        local actualFace, actualSize = label:GetFont()
        assert(actualFace == face and actualSize == size,
            ("expected %s at %s, got %s at %s"):format(face, size, tostring(actualFace), tostring(actualSize)))
    end
    local function checkColour(label, wanted)
        local colour = { label:GetTextColor() }
        for k = 1, 4 do near(colour[k], wanted[k]) end
    end
    assert(MenubarModel.ApplyTheme(profile, "macos27"))
    local text = profile.popupText
    local row = create("Button")
    row.fontString, row.highlight = row:AttachFontString(), row:AttachTexture()
    row.fontString:SetFontObject(GameFontNormalSmall)
    row.fontString:SetText("Player")
    row.OnEnter = function(button) button.highlight:Show() end
    row.OnLeave = function(button) button.highlight:Hide() end
    row.highlight:Hide()
    local function menuChoice()
        clock.frame:Click("LeftButton")
        return assert(Stub.MenuItem(Stub.menus[#Stub.menus], "Player"))
    end

    local barFace, barSize = clock.label:GetFont()
    text.fontSize = 24
    local player = menuChoice()
    local enabled = true
    local item = { IsEnabled = function() return enabled end }
    player.initializer(row, item)
    checkFont(row.fontString, GameFontNormalSmall:GetFont(), 24)
    assert(row.fontString:GetHeight() >= row.fontString:GetStringHeight())
    text.font, text.fontStyle, text.fontSize = regular, "italic", 0
    player = menuChoice()
    player.initializer(row, item)
    checkFont(row.fontString, italic, select(2, GameFontNormalSmall:GetFont()))
    text.fontSize, text.useCustomColor, text.textColor = 24, true, custom
    player = menuChoice()
    player.initializer(row, item)
    checkFont(row.fontString, italic, 24); checkColour(row.fontString, custom)
    row:OnEnter(item); assert(row.fontString:GetTextColor() > 0.95)
    row:OnLeave(item); checkColour(row.fontString, custom)
    enabled = false
    row:OnEnter(item); near(row.fontString:GetTextColor(), 0.40)
    enabled = true

    location.frame.scripts.OnEnter(location.frame)
    for _, label in ipairs({ MenubarWidgetTooltipTextLeft3, MenubarWidgetTooltipTextRight3 }) do
        checkFont(label, italic, 24); checkColour(label, custom)
    end
    widget.frame.scripts.OnEnter(widget.frame)
    checkFont(MenubarWidgetTooltipTextLeft3, italic, 24) -- coloured provider warning
    local r, g, b = MenubarWidgetTooltipTextLeft3:GetTextColor()
    assert(r > g and g > b)
    near(MenubarWidgetTooltipTextLeft2:GetTextColor(), 0.08) -- theme hint
    checkFont(clock.label, barFace, barSize)

    -- Large percentage labels must physically fit in both native Volume menus.
    local originalShift = IsShiftKeyDown
    masterVolume = "1"
    volume.settings.orientation = "horizontal"
    for _, shifted in ipairs({ false, true }) do
        IsShiftKeyDown = function() return shifted end
        local slider, labels = volumeControls()
        assert(slider.orientation == (shifted and "HORIZONTAL" or "VERTICAL"))
        local body = slider:GetParent()
        assert(#labels == 3)
        for _, label in ipairs(labels) do
            checkFont(label, italic, 24)
            assert(label:GetStringWidth() <= label:GetWidth() and label:GetStringHeight() <= label:GetHeight(),
                "Volume text clips inside its label")
            assert(label:GetLeft() >= body:GetLeft() and label:GetRight() <= body:GetRight()
                and label:GetTop() <= body:GetTop() and label:GetBottom() >= body:GetBottom(),
                "Volume text must fit inside its menu")
        end
        checkColour(labels[1], custom)
        near(labels[2]:GetTextColor(), 0.08)
    end
    IsShiftKeyDown = originalShift

    text.font, text.fontSize, text.fontStyle, text.useCustomColor = "theme", 0, "regular", false
    player = menuChoice()
    player.initializer(row, item)
    checkFont(row.fontString, GameFontNormalSmall:GetFont())
    near(row.fontString:GetTextColor(), 0.01)
    location.frame.scripts.OnEnter(location.frame)
    checkFont(MenubarWidgetTooltipTextLeft1, GameFontNormalLarge:GetFont())
    checkFont(MenubarWidgetTooltipTextRight3, GameFontHighlightSmall:GetFont())
    near(MenubarWidgetTooltipTextRight3:GetTextColor(), 0.01)

    assert(MenubarModel.ApplyTheme(profile, "warcraftBrown"))
    text = profile.popupText
    text.font, text.fontStyle, text.fontSize = regular, "italic", 0
    text.useCustomColor, text.textColor = true, custom
    player = menuChoice()
    player.initializer(row, item)
    checkColour(row.fontString, custom)
    row:OnEnter(item); checkColour(row.fontString, { 1, 0.82, 0.25, 1 })
    enabled = false
    row:OnEnter(item)
    local red, green, blue = row.fontString:GetTextColor()
    assert(red == green and green == blue and red > 0 and red < 1)
    enabled = true
    row:OnLeave(item)

    -- The native compositor may assign the same FontString to a title on this acquisition.
    row.fontString:SetFontObject(GameFontNormalLarge)
    player.initializer(row, item)
    checkFont(row.fontString, italic, select(2, GameFontNormalLarge:GetFont()))
    -- A rejected face can return false, or nil without changing GetFont().
    local nativeSetFont = Region.SetFont
    Region.SetFont = function(font, path, ...)
        if path == "not-installed.ttf" then return nil end
        return nativeSetFont(font, path, ...)
    end
    for _, missing in ipairs({ "missing.ttf", "not-installed.ttf" }) do
        text.font, text.fontSize = missing, 20
        player = menuChoice()
        player.initializer(row, item)
        checkFont(row.fontString, GameFontNormalLarge:GetFont(), 20)
    end
    Region.SetFont = nativeSetFont
    text.font, text.fontSize, text.useCustomColor = "theme", 0, false
    player = menuChoice()
    player.initializer(row, item)
    checkFont(row.fontString, GameFontNormalLarge:GetFont())
end

widget.frame.scripts.OnEnter(widget.frame)
Menubar:Rebuild()
assert(not MenubarWidgetTooltip:IsShown())
assert(GameTooltip:IsShown() and GameTooltip:GetOwner() == foreign and GameTooltip.lines[1][1] == "An unrelated item")
profile.popupOpacity = 0
Menubar.UI:Context(UIParent, function(menu) menu:CreateButton("Settings action") end)
assert(Stub.menus[#Stub.menus].mixin == native)
Menubar.UI:OpenWidget(clock.id)
local settingsDropdown
for _, control in ipairs(Menubar.UI.window.controls) do
    if control.caption == "Time zone" then settingsDropdown = control; break end
end
assert(settingsDropdown)
settingsDropdown:OpenMenu()
local settingsMenu = settingsDropdown:GetMenuDescription()
assert(settingsDropdown:IsMenuOpen() and settingsMenu.mixin == MenuVariants.GetDefaultMenuMixin())
assert(not Stub.MenuItem(settingsMenu, "Player").initializer)
local unsupported = { GetInset = native.GetInset }
assert(MenubarSkins.Popup.Menu(unsupported) == unsupported)
local lines = GameTooltip.NumLines
GameTooltip.NumLines = nil
assert(MenubarSkins.Popup.Tooltip() == GameTooltip and GameTooltip:GetOwner() == foreign)
GameTooltip.NumLines = lines
print("PASS seven scoped popup skins, opacity compositing, tooltip reuse, volume slider, native fallbacks and UI isolation")
