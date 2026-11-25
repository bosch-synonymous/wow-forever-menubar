-- Checks alpha ownership and inheritance, not GPU compositing or client rendering.
local root = REPO_ROOT or "."
local Stub = dofile(root .. "/tests/wow_stub.lua")
Stub.Install()
C_Texture = { GetAtlasInfo = function() return { width = 64, height = 32 } end }
local Region = getmetatable(UIParent)
local nativeCreateTexture, textureCount = Region.CreateTexture, 0
function Region:CreateTexture(...)
    textureCount = textureCount + 1
    return nativeCreateTexture(self, ...)
end
for _, file in ipairs({ "Model.lua", "Identity.lua", "Fonts.lua", "Layout.lua", "Gauge.lua", "Skins.lua", "Core.lua", "UI.lua", "Settings.lua" }) do
    dofile(root .. "/src/menubar-core/" .. file)
end
Menubar:RegisterWidgetType({ id = "opacity-text", name = "Text", defaults = {},
    defaultPlacement = { bar = "top", alignment = "left" },
    create = function(widget)
        widget.icon = widget.frame:CreateTexture(nil, "OVERLAY")
        widget.icon:SetColorTexture(1, 1, 1, 1)
    end,
    update = function(widget) widget:SetText("Readable text") end,
})
Menubar:RegisterWidgetType({ id = "opacity-gauge", name = "Gauge", defaults = {},
    defaultPlacement = { bar = "bottom", alignment = "right" },
    update = function(widget) widget:SetGauge(37, 100, { 0.2, 0.7, 0.3, 1 }, "37%", 160) end,
})
Menubar:Start()

local passed = 0
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function equal(actual, expected)
    assert(math.abs(actual - expected) < 0.0000001, "expected " .. expected .. ", got " .. tostring(actual))
end
local function shiftLeftClick(frame)
    local previous = IsShiftKeyDown
    IsShiftKeyDown = function() return true end
    local ok, reason = pcall(frame.Click, frame, "LeftButton")
    IsShiftKeyDown = previous
    if not ok then error(reason, 0) end
end
local function runtime(kind)
    for _, widget in pairs(Menubar.runtime) do if widget.instance.type == kind then return widget end end
    error("Missing widget: " .. kind)
end
local function surfaces(skin)
    local result = {}
    if skin then
        if skin.body and skin.body:IsShown() then result[#result + 1] = skin.body end
        for _, item in pairs(skin.red or {}) do if item:IsShown() then result[#result + 1] = item end end
    end
    return result
end
local function paintAlpha(texture)
    return texture:GetEffectiveAlpha() * (texture.color and texture.color[4] or 1)
        * (texture.vertexColor and texture.vertexColor[4] or 1)
end
local function assertContentOpaque()
    for _, bar in pairs(Menubar.bars) do
        equal(bar:GetEffectiveAlpha(), 1)
        equal(bar.topLine:GetEffectiveAlpha(), 1); equal(bar.bottomLine:GetEffectiveAlpha(), 1)
        for _, corner in ipairs(bar.corners) do equal(corner:GetEffectiveAlpha(), 1) end
        equal(bar.menu:GetEffectiveAlpha(), 1); equal(bar.menu.Label:GetEffectiveAlpha(), 1)
        equal(bar.overflow:GetEffectiveAlpha(), 1); equal(bar.overflow.Label:GetEffectiveAlpha(), 1)
        for _, control in ipairs({ bar.menu, bar.overflow }) do
            for _, texture in ipairs(surfaces(control.warcraftSkin)) do equal(paintAlpha(texture), 1) end
        end
        for _, texture in pairs(bar.warcraftSkin and bar.warcraftSkin.bottom or {}) do
            equal(texture:GetEffectiveAlpha(), 1)
        end
    end
    for _, widget in pairs(Menubar.runtime) do
        equal(widget.frame:GetEffectiveAlpha(), 1); equal(widget.label:GetEffectiveAlpha(), 1)
        if widget.icon then equal(widget.icon:GetEffectiveAlpha(), 1) end
        if widget.gauge then
            equal(widget.gauge:GetEffectiveAlpha(), 1); equal(widget.gaugeLabel:GetEffectiveAlpha(), 1)
        end
    end
end
local styles = { "system7", "macos8", "macosx", "macos27", "warcraftBrown", "warcraftBlack", "warcraftRed" }

check("all styles and bar placements fade only the background at zero fractional and full opacity", function()
    local profile = Menubar:GetProfile()
    for _, style in ipairs(styles) do
        MenubarModel.ApplyTheme(profile, style)
        for _, placement in ipairs({ "top", "bottom", "both" }) do
            profile.placement = placement
            for _, opacity in ipairs({ 0, 0.37, 1 }) do
                profile.opacity = opacity; Menubar:Rebuild()
                for _, bar in pairs(Menubar.bars) do
                    assert(bar.surface:GetParent() == bar)
                    assert(bar.surface:GetFrameLevel() < bar:GetFrameLevel())
                    assert(bar.surface.mouseEnabled == false)
                    equal(bar.surface:GetEffectiveAlpha(), opacity)
                    assert(bar.background:GetParent() == bar.surface)
                    equal(bar.background:GetEffectiveAlpha(), opacity)
                    for _, list in ipairs({ bar.dither, bar.shadingBands }) do
                        for _, texture in ipairs(list) do
                            assert(texture:GetParent() == bar.surface)
                            equal(texture:GetEffectiveAlpha(), opacity)
                        end
                    end
                    for _, texture in ipairs(surfaces(bar.warcraftSkin)) do
                        assert(texture:GetParent() == bar.surface)
                        equal(texture:GetEffectiveAlpha(), opacity)
                    end
                    if MenubarSkins.IsWarcraft(style) or style == "macosx" or style == "macos27" then
                        assert(not bar.background:IsShown(), "The selected style must replace the backup surface")
                    end
                end
                assertContentOpaque()
            end
        end
    end
end)

check("background swatch alpha combines with opacity without fading frame colours or control artwork", function()
    local profile = Menubar:GetProfile()
    for _, style in ipairs(styles) do
        MenubarModel.ApplyTheme(profile, style)
        profile.placement, profile.opacity = "both", 0.37
        profile.background[4], profile.bottomLine[4], profile.textColor[4] = 0.6, 0.45, 0.8
        Menubar:Rebuild()
        for _, bar in pairs(Menubar.bars) do
            if bar.background:IsShown() then equal(paintAlpha(bar.background), 0.37 * 0.6) end
            for _, texture in ipairs(surfaces(bar.warcraftSkin)) do equal(paintAlpha(texture), 0.37 * 0.6) end
            if style == "macosx" or style == "macos27" then
                for _, band in ipairs(bar.shadingBands) do if band:IsShown() then equal(paintAlpha(band), 0.37 * 0.6) end end
            end
            if bar.bottomLine:IsShown() then equal(paintAlpha(bar.bottomLine), 0.45) end
            for _, texture in pairs(bar.warcraftSkin and bar.warcraftSkin.bottom or {}) do
                if texture:IsShown() then equal(paintAlpha(texture), 0.45) end
            end
        end
        equal(runtime("opacity-text").label.textColor[4], 0.8)
        equal(runtime("opacity-gauge").gaugeLabel.textColor[4], 1)
        assertContentOpaque()
    end
end)

check("a transparent background colour also hides shading and patterns without fading controls", function()
    local profile = Menubar:GetProfile()
    for _, style in ipairs(styles) do
        MenubarModel.ApplyTheme(profile, style)
        profile.background[4], profile.opacity = 0, 1
        if not MenubarSkins.IsWarcraft(style) then profile.texture = "dither" end
        Menubar:Rebuild()
        for _, bar in pairs(Menubar.bars) do
            if bar.background:IsShown() then equal(paintAlpha(bar.background), 0) end
            for _, list in ipairs({ bar.shadingBands, bar.dither, surfaces(bar.warcraftSkin) }) do
                for _, texture in ipairs(list) do if texture:IsShown() then equal(paintAlpha(texture), 0) end end
            end
        end
        assertContentOpaque()
    end
end)

check("solid patterned and custom background overrides keep the same opacity scope", function()
    local profile = Menubar:GetProfile()
    for _, style in ipairs(styles) do
        MenubarModel.ApplyTheme(profile, style)
        profile.opacity = 0.37
        for _, pattern in ipairs({ "solid", "dither", "Interface\\AddOns\\Custom\\Background.tga" }) do
            profile.texture = pattern; Menubar:Rebuild()
            for _, bar in pairs(Menubar.bars) do
                assert(bar.background:IsShown())
                equal(bar.background:GetEffectiveAlpha(), 0.37)
                assert(bar.background:GetParent() == bar.surface)
                equal(#surfaces(bar.warcraftSkin), 0)
            end
            assertContentOpaque()
        end
    end
end)

check("missing native artwork uses one fading fallback body while framing and controls stay independent", function()
    local oldSetTexture, oldAtlasInfo = Region.SetTexture, C_Texture.GetAtlasInfo
    function Region:SetTexture(value)
        if value ~= nil then return false end
        return oldSetTexture(self, value)
    end
    C_Texture.GetAtlasInfo = function() return nil end
    local profile = Menubar:GetProfile()
    for _, style in ipairs({ "warcraftBrown", "warcraftBlack", "warcraftRed" }) do
        MenubarModel.ApplyTheme(profile, style)
        profile.opacity = 0.37; Menubar:Rebuild()
        for _, bar in pairs(Menubar.bars) do
            assert(not bar.background:IsShown())
            assert(not bar.warcraftSkin.nativeBody and bar.warcraftSkin.body:IsShown())
            equal(paintAlpha(bar.warcraftSkin.body), 0.37)
            assert(bar.bottomLine:IsShown()); equal(paintAlpha(bar.bottomLine), 1)
        end
        assertContentOpaque()
    end
    Region.SetTexture, C_Texture.GetAtlasInfo = oldSetTexture, oldAtlasInfo
end)

check("transparent backgrounds leave widget and core mouse actions usable", function()
    local profile = Menubar:GetProfile()
    MenubarModel.ApplyTheme(profile, "warcraftBlack")
    profile.opacity, profile.placement = 0, "both"; Menubar:Rebuild()
    local widget = runtime("opacity-text")
    widget.frame:Click("RightButton")
    assert(Menubar.UI.window:IsShown() and Menubar.UI.widgetID == widget.id)
    shiftLeftClick(widget.frame)
    assert(Stub.MenuItem(Stub.menus[#Stub.menus], "Configure..."))
    Menubar.bars.top.menu:Click("RightButton")
    assert(Menubar.UI.window:IsShown() and Menubar.UI.widgetID == nil)
    assertContentOpaque()
end)

check("opacity changes reuse background containers and preserve saved values", function()
    local profile = Menubar:GetProfile()
    local function cycle()
        for _, style in ipairs(styles) do
            MenubarModel.ApplyTheme(profile, style)
            for _, opacity in ipairs({ 0, 0.37, 1 }) do profile.opacity = opacity; Menubar:Rebuild() end
        end
    end
    cycle()
    local top, bottom = Menubar.bars.top.surface, Menubar.bars.bottom.surface
    local framesBefore, texturesBefore = #Stub.frames, textureCount
    for _ = 1, 10 do cycle() end
    assert(Menubar.bars.top.surface == top and Menubar.bars.bottom.surface == bottom)
    equal(#Stub.frames, framesBefore); equal(textureCount, texturesBefore)
    profile.opacity = 0.37
    MenubarModel.Initialize(Menubar.db, Menubar.characterKey)
    Menubar:Rebuild(); equal(profile.opacity, 0.37)
    equal(top:GetEffectiveAlpha(), 0.37); equal(bottom:GetEffectiveAlpha(), 0.37)
end)

check("Aqua gloss and pinstripes fade with their surface while framing and widgets stay opaque", function()
    local profile = Menubar:GetProfile()
    assert(MenubarModel.ApplyTheme(profile, "macosx"))
    profile.placement = "both"
    for _, opacity in ipairs({ 0, 0.37, 1 }) do
        profile.opacity = opacity; Menubar:Rebuild()
        for _, bar in pairs(Menubar.bars) do
            equal(bar.surface:GetAlpha(), opacity)
            local painted = 0
            for _, band in ipairs(bar.shadingBands) do
                if band:IsShown() then
                    painted = painted + 1
                    assert(band:GetParent() == bar.surface)
                    equal(band:GetAlpha(), 1)
                    equal(band:GetEffectiveAlpha(), opacity)
                    equal(paintAlpha(band), opacity * profile.background[4])
                end
            end
            assert(painted > 0, "Aqua style texture must draw its original gloss and stripe rows")
            assert(bar.topLine:IsShown() and bar.bottomLine:IsShown())
        end
        assertContentOpaque()
    end
    profile.background[4] = 0; Menubar:Rebuild()
    for _, bar in pairs(Menubar.bars) do
        for _, band in ipairs(bar.shadingBands) do if band:IsShown() then equal(paintAlpha(band), 0) end end
    end
    assertContentOpaque()
end)

print(passed .. " background opacity tests passed")
