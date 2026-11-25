-- Preset application and native-skin lifecycle through the real core UI.
local root = REPO_ROOT or "."
local Stub = dofile(root .. "/tests/wow_stub.lua")
Stub.Install()
C_Texture = { GetAtlasInfo = function() return { width = 64, height = 32 } end }
local textureCount = 0
local Region = getmetatable(UIParent)
local nativeCreateTexture = Region.CreateTexture
function Region:CreateTexture(...)
    textureCount = textureCount + 1
    return nativeCreateTexture(self, ...)
end
for _, file in ipairs({ "Model.lua", "Identity.lua", "Fonts.lua", "Layout.lua", "Gauge.lua", "Skins.lua", "Core.lua", "UI.lua", "Settings.lua" }) do
    dofile(root .. "/src/menubar-core/" .. file)
end
local Model = MenubarModel
local passed = 0
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local styles = {
    { id = "warcraftBrown", label = "Warcraft Brown", opacity = 0.9, panelSize = 14 },
    { id = "warcraftBlack", label = "Warcraft Black", opacity = 0.7, panelSize = 0 },
    { id = "warcraftRed", label = "Warcraft Red", opacity = 0.7, panelSize = 0 },
}

check("Warcraft presets replace typography and colour without changing layout or character choices", function()
    for _, style in ipairs(styles) do
        local db, character, profile = Model.Initialize({ profiles = { Default = { theme = "system7" } } }, "A")
        local instance = Model.AddWidget(db, "A", "time", { zone = "utc" }, { bar = "bottom", alignment = "center" })
        profile.placement, profile.coreMenuBar = "both", "bottom"
        profile.height, profile.padding, profile.spacing = 40, 17, 22
        profile.font, profile.fontStyle, profile.fontSize = "Custom\\Font.ttf", "italic", 18
        profile.opacity, profile.roundedCorners = 0.4, true
        assert(Model.ApplyTheme(profile, style.id))
        equal(profile.theme, style.id)
        equal(profile.font, "Fonts\\FRIZQT__.TTF")
        equal(profile.fontStyle, "regular"); equal(profile.fontFlags, "")
        equal(profile.textShadow, true)
        equal(profile.texture, "theme"); equal(profile.roundedCorners, false)
        equal(profile.fontSize, 12); equal(profile.height, 40)
        equal(profile.placement, "both"); equal(profile.coreMenuBar, "bottom")
        equal(profile.padding, 17); equal(profile.spacing, 22)
        equal(profile.opacity, style.opacity); equal(profile.popupOpacity, 0.9)
        equal(profile.popupText.fontSize, style.panelSize); equal(profile.popupText.font, "theme")
        equal(character.widgets[1], instance)
        equal(instance.bar, "bottom"); equal(instance.alignment, "center"); equal(instance.settings.zone, "utc")
        equal(profile.textColor[1], 1)
        if style.id == "warcraftBlack" then
            equal(profile.textColor[2], 1); equal(profile.textColor[3], 1)
        else
            assert(profile.textColor[2] > 0.5 and profile.textColor[2] < 1)
            equal(profile.textColor[3], 0)
        end
    end
end)

check("saved Warcraft profiles retain user overrides instead of reapplying preset defaults on login", function()
    for _, style in ipairs(styles) do
        local db, _, profile = Model.Initialize(nil, "A")
        assert(Model.ApplyTheme(profile, style.id))
        profile.font, profile.fontStyle, profile.textShadow = "Custom\\Font.ttf", "bold", false
        profile.textColor = { 0.7, 0.8, 0.9, 1 }
        profile.texture = "Interface\\AddOns\\Custom\\Background.tga"
        profile.bottomLineSize = 3
        profile.opacity, profile.popupOpacity, profile.popupText.fontSize = 0.7, 0.58, 0
        Model.Initialize(db, "A")
        equal(profile.theme, style.id)
        equal(profile.font, "Custom\\Font.ttf"); equal(profile.fontStyle, "bold")
        equal(profile.textShadow, false); equal(profile.textColor[2], 0.8)
        equal(profile.texture, "Interface\\AddOns\\Custom\\Background.tga")
        equal(profile.bottomLineSize, 3)
        equal(profile.opacity, 0.7); equal(profile.popupOpacity, 0.58); equal(profile.popupText.fontSize, 0)
    end
end)

check("returning to a Macintosh preset clears Warcraft shadows and restores its typography", function()
    local profile = Model.DeepCopy(Model.DefaultProfile)
    for _, style in ipairs(styles) do
        assert(Model.ApplyTheme(profile, style.id))
        for _, target in ipairs({ "system7", "macos8", "macosx" }) do
            assert(Model.ApplyTheme(profile, target))
            equal(profile.font, "Fonts\\FRIZQT__.TTF"); equal(profile.fontStyle, "regular")
            equal(profile.textShadow, false); equal(profile.roundedCorners, true)
            equal(profile.textColor[1], 0); equal(profile.textColor[2], 0); equal(profile.textColor[3], 0)
            assert(Model.ApplyTheme(profile, style.id))
        end
    end
end)

check("preset tables remain immutable and legacy profiles gain a safe shadow setting", function()
    local first, second = Model.DeepCopy(Model.DefaultProfile), Model.DeepCopy(Model.DefaultProfile)
    assert(Model.ApplyTheme(first, "warcraftBrown")); assert(Model.ApplyTheme(second, "warcraftBrown"))
    local original = second.bottomLine[1]
    first.bottomLine[1] = 0.13
    equal(second.bottomLine[1], original)
    equal(Model.Themes.warcraftBrown.bottomLine[1], original)
    local _, _, old = Model.Initialize({ profiles = { Default = { font = "Custom\\Old.ttf" } } }, "A")
    equal(old.textShadow, false); equal(old.font, "Custom\\Old.ttf")
    local _, _, malformed = Model.Initialize({ profiles = { Default = { textShadow = "yes" } } }, "A")
    equal(malformed.textShadow, false)
end)

Menubar:RegisterWidgetType({
    id = "theme-clock", name = "Theme clock", defaults = {},
    defaultPlacement = { bar = "top", alignment = "left" },
    update = function(widget) widget:SetText("Azeroth 12:34") end,
})
Menubar:RegisterWidgetType({
    id = "theme-gauge", name = "Theme gauge", defaults = {},
    defaultPlacement = { bar = "bottom", alignment = "right" },
    update = function(widget) widget:SetGauge(25, 100, { 0.2, 0.6, 0.3, 1 }, "25%", 160) end,
})
Menubar:Start()
local function runtime(kind)
    for _, value in pairs(Menubar.runtime) do if value.instance.type == kind then return value end end
    error("Missing runtime: " .. kind)
end
local function control(caption)
    for _, value in ipairs(Menubar.UI.window.controls) do if value.caption == caption then return value end end
    error("Missing control: " .. caption)
end
local function pickStyle(label)
    Menubar.UI:OpenSettings()
    control("Bar style"):OpenMenu()
    Stub.MenuItem(Stub.menus[#Stub.menus], label).callback()
end
local function textures(skin)
    local result = {}
    if not skin then return result end
    if skin.body then result[#result + 1] = skin.body end
    for _, key in ipairs({ "red", "bottom" }) do
        for _, name in ipairs({ "left", "middle", "right" }) do
            if skin[key] and skin[key][name] then result[#result + 1] = skin[key][name] end
        end
    end
    return result
end
local function anySurface(skin)
    if skin.body and skin.body:IsShown() then return true end
    for _, value in pairs(skin.red or {}) do if value:IsShown() then return true end end
    return false
end

check("all Warcraft styles are selectable and apply readable font treatments to widgets and chrome", function()
    Menubar:GetProfile().placement = "both"
    for _, style in ipairs(styles) do
        pickStyle(style.label)
        local profile, widget = Menubar:GetProfile(), runtime("theme-clock")
        equal(profile.theme, style.id)
        equal(widget.label.font, "Fonts\\FRIZQT__.TTF")
        equal(widget.label.fontFlags, "")
        equal(widget.label.shadowColor[4], 1)
        equal(widget.label.shadowOffset[1], 1); equal(widget.label.shadowOffset[2], -1)
        for index = 1, 4 do equal(widget.label.textColor[index], profile.textColor[index]) end
        for _, bar in pairs(Menubar.bars) do
            assert(bar.warcraftSkin and anySurface(bar.warcraftSkin))
            assert(bar.overflow.warcraftSkin and anySurface(bar.overflow.warcraftSkin))
            for index = 1, 4 do equal(bar.menu.Label.textColor[index], profile.textColor[index]) end
            for _, corner in ipairs(bar.corners) do assert(not corner:IsShown()) end
        end
        equal(Menubar.UI.window.title.fontObject, GameFontNormalLarge)
        equal(control("Font").Label.fontObject, GameFontHighlight)
    end
end)

check("Macintosh font presets apply Friz while ordinary rebuilds preserve a chosen font", function()
    for _, style in ipairs({ { id = "system7", label = "Mac OS 7.6 (Harmony)" },
        { id = "macos8", label = "Mac OS 8.1 (Platinum)" },
        { id = "macosx", label = "Mac OS X (Aqua)" },
        { id = "macos27", label = "macOS 27 (Liquid Glass)" } }) do
        pickStyle(style.label)
        local profile, widget = Menubar:GetProfile(), runtime("theme-clock")
        equal(profile.theme, style.id)
        equal(profile.font, "Fonts\\FRIZQT__.TTF")
        equal(widget.label.font, "Fonts\\FRIZQT__.TTF")
        profile.font = "Fonts\\MORPHEUS.TTF"
        Menubar:Rebuild()
        equal(profile.theme, style.id)
        equal(profile.font, "Fonts\\MORPHEUS.TTF")
        equal(widget.label.font, "Fonts\\MORPHEUS.TTF")
        pickStyle("Warcraft Brown")
        equal(widget.label.font, "Fonts\\FRIZQT__.TTF")
        pickStyle(style.label)
        equal(profile.font, "Fonts\\MORPHEUS.TTF")
        equal(widget.label.font, "Fonts\\MORPHEUS.TTF")
        profile.font = "Fonts\\FRIZQT__.TTF"
        Menubar:Rebuild()
    end
end)

check("native framing respects the configured bottom edge and existing gauge clearance", function()
    pickStyle("Warcraft Brown")
    local profile, bar, widget = Menubar:GetProfile(), Menubar.bars.bottom, runtime("theme-gauge")
    for _, value in pairs(bar.warcraftSkin.bottom) do
        assert(value:IsShown()); equal(value:GetHeight(), profile.bottomLineSize)
    end
    equal(widget.gauge:GetHeight(), profile.height - profile.topLineSize - profile.bottomLineSize - 4)
    equal(widget.content.points[1][5], (profile.bottomLineSize - profile.topLineSize) / 2)
    equal(widget.gauge.points[1][2], widget.content)
    equal(widget.gauge.points[1][5], 0)
    profile.bottomLineSize = 0; Menubar:Rebuild()
    for _, value in pairs(bar.warcraftSkin.bottom) do assert(not value:IsShown()) end
    equal(widget.gaugeBottomLineSize, 0)
end)

check("theme font choices never replace the native white outlined progress overlay", function()
    local widget = runtime("theme-gauge")
    local original = widget.gaugeLabel
    for _, style in ipairs(styles) do
        pickStyle(style.label)
        equal(widget.gaugeLabel, original)
        equal(original.fontObject, TextStatusBarText)
        equal(original.fontFlags, "OUTLINE")
        for index = 1, 4 do equal(original.textColor[index], 1) end
        equal(original.shadowColor[4], 1)
    end
end)

check("custom background overrides keep Warcraft framing and controls while releasing the preset surface", function()
    pickStyle("Warcraft Brown")
    local profile, bar = Menubar:GetProfile(), Menubar.bars.bottom
    profile.texture = "Interface\\AddOns\\Custom\\Background.tga"
    Menubar:Rebuild()
    assert(not anySurface(bar.warcraftSkin))
    equal(bar.background.texture, profile.texture)
    assert(bar.warcraftSkin.nativeBottom)
    for _, value in pairs(bar.warcraftSkin.bottom) do assert(value:IsShown()) end
    assert(anySurface(bar.overflow.warcraftSkin))
end)

check("unavailable client artwork produces readable fallback surfaces and rules without widget errors", function()
    local nativeSetTexture, nativeGetAtlasInfo = Region.SetTexture, C_Texture.GetAtlasInfo
    function Region:SetTexture(value)
        if value ~= nil then return false end
        return nativeSetTexture(self, value)
    end
    C_Texture.GetAtlasInfo = function() return nil end
    for _, style in ipairs(styles) do
        pickStyle(style.label)
        local bar = Menubar.bars.bottom
        assert(not bar.warcraftSkin.nativeBody and not bar.warcraftSkin.nativeBottom)
        assert(bar.warcraftSkin.body:IsShown())
        assert(bar.warcraftSkin.body.color and bar.warcraftSkin.body.color[4] > 0)
        assert(bar.bottomLine:IsShown())
        for _, widget in pairs(Menubar.runtime) do assert(not widget.failed) end
    end
    Region.SetTexture, C_Texture.GetAtlasInfo = nativeSetTexture, nativeGetAtlasInfo
end)

check("canonical atlas casing keeps native title artwork and window framing", function()
    local getAtlas = Region.GetAtlas
    function Region:GetAtlas() return self.atlas and self.atlas:lower() end
    for _, style in ipairs({ "Warcraft Brown", "Warcraft Black" }) do
        pickStyle(style)
        for _, bar in pairs(Menubar.bars) do
            assert(bar.warcraftSkin.nativeBody and bar.warcraftSkin.nativeBottom)
            for _, value in pairs(bar.warcraftSkin.bottom) do assert(value:IsShown()) end
        end
    end
    Region.GetAtlas = getAtlas
end)

check("missing malformed restricted and different atlas readbacks retain readable skin fallbacks", function()
    local getAtlas, secretCheck = Region.GetAtlas, issecretvalue
    local secret = setmetatable({}, { __tostring = function() error("restricted atlas formatted", 0) end })
    issecretvalue = function(value) return rawequal(value, secret) end
    for _, result in ipairs({ {}, { value = false }, { value = 27 }, { value = {} },
        { value = secret }, { value = "ANOTHER-NATIVE-ATLAS" } }) do
        function Region:GetAtlas() return result.value end
        pickStyle("Warcraft Brown")
        for _, bar in pairs(Menubar.bars) do
            assert(not bar.warcraftSkin.nativeBody and not bar.warcraftSkin.nativeBottom)
            assert(bar.warcraftSkin.body:IsShown() and bar.warcraftSkin.body.color)
            assert(bar.bottomLine:IsShown())
        end
        for _, widget in pairs(Menubar.runtime) do assert(not widget.failed) end
    end
    Region.GetAtlas, issecretvalue = getAtlas, secretCheck
end)

check("malformed atlas dimensions use known finite frame proportions", function()
    local original = C_Texture.GetAtlasInfo
    C_Texture.GetAtlasInfo = function() return { width = math.huge, height = 0 / 0 } end
    pickStyle("Warcraft Brown")
    local bar = Menubar.bars.bottom
    local left, right = bar.warcraftSkin.bottom.left, bar.warcraftSkin.bottom.right
    equal(left:GetWidth(), Menubar:GetProfile().bottomLineSize)
    equal(right:GetWidth(), Menubar:GetProfile().bottomLineSize)
    assert(bar.warcraftSkin.nativeBottom)
    C_Texture.GetAtlasInfo = original
end)

check("switching back hides native surfaces and clears text shadows instead of leaking theme state", function()
    pickStyle("Warcraft Red")
    local bar = Menubar.bars.bottom
    pickStyle("Mac OS 8.1 (Platinum)")
    for _, owner in ipairs({ bar, bar.menu, bar.overflow }) do
        for _, value in ipairs(textures(owner.warcraftSkin)) do assert(not value:IsShown()) end
    end
    local label = runtime("theme-clock").label
    equal(label.font, "Fonts\\FRIZQT__.TTF")
    equal(label.shadowColor[4], 0)
    equal(label.shadowOffset[1], 0); equal(label.shadowOffset[2], 0)
    equal(bar.menu.Label.textColor[1], 0)
    assert(bar.bottomLine:IsShown())
    pickStyle("Mac OS 7.6 (Harmony)")
    for _, band in ipairs(bar.shadingBands) do assert(not band:IsShown()) end
    for _, corner in ipairs(bar.corners) do assert(corner:IsShown()) end
    local profile = Menubar:GetProfile()
    equal(profile.theme, "system7"); equal(profile.texture, "solid")
    for _, owner in pairs(Menubar.bars) do
        assert(owner.background:IsShown()); equal(owner.background.texture, nil)
        for index = 1, 4 do equal(owner.background.color[index], 1) end
        assert(not owner.topLine:IsShown()); assert(owner.bottomLine:IsShown())
        equal(owner.bottomLine:GetHeight(), 1)
        for index = 1, 3 do equal(owner.bottomLine.color[index], 0) end
        for _, line in ipairs(owner.dither) do assert(not line:IsShown()) end
        for _, band in ipairs(owner.shadingBands) do assert(not band:IsShown()) end
    end
    local _, _, reloaded = Model.Initialize(Model.DeepCopy(Menubar.db), Menubar.characterKey)
    equal(reloaded.theme, "system7"); equal(reloaded.background[1], 1)
    equal(reloaded.topLineSize, 0); equal(reloaded.bottomLineSize, 1)
end)

check("repeated style changes reuse textures and frames after the first complete cycle", function()
    local cycle = { "Warcraft Brown", "Warcraft Black", "Warcraft Red", "Mac OS 8.1 (Platinum)", "Mac OS X (Aqua)", "Mac OS 7.6 (Harmony)" }
    for _, style in ipairs(cycle) do pickStyle(style) end
    local bar = Menubar.bars.bottom
    local body, bottom = bar.warcraftSkin.body, bar.warcraftSkin.bottom.middle
    local texturesBefore, framesBefore = textureCount, #Stub.frames
    for _ = 1, 10 do for _, style in ipairs(cycle) do pickStyle(style) end end
    equal(textureCount, texturesBefore); equal(#Stub.frames, framesBefore)
    equal(bar.warcraftSkin.body, body); equal(bar.warcraftSkin.bottom.middle, bottom)
end)

check("the bare menu glyph follows theme contrast without backgrounds borders or reallocating", function()
    local profile = Menubar:GetProfile()
    profile.placement, profile.coreMenuBar, profile.opacity = "both", "both", 0
    local icons = {}
    for _, theme in ipairs({ "system7", "macos8", "macosx", "macos27", "warcraftBrown", "warcraftBlack", "warcraftRed" }) do
        assert(Model.ApplyTheme(profile, theme)); Menubar:Rebuild()
        for name, bar in pairs(Menubar.bars) do
            assert(bar.menu:IsShown()); assert(not bar.menu.Label:IsShown())
            equal(bar.menu:GetWidth(), 24)
            assert(not bar.menu.background or not bar.menu.background:IsShown())
            for _, edge in ipairs(bar.menu.menubarBorder or {}) do assert(not edge:IsShown()) end
            for _, surface in ipairs(textures(bar.menu.warcraftSkin)) do assert(not surface:IsShown()) end
            equal(bar.menu.Label:GetText(), "")
            local icon = assert(bar.menu.icon)
            if icons[name] then equal(icon, icons[name]) else icons[name] = icon end
            assert(#icon > 0)
            local color = { bar.menu.Label:GetTextColor() }
            for _, part in ipairs(icon) do
                assert(part:IsVisible()); equal(part:GetParent(), bar.menu)
                equal(part:GetEffectiveAlpha(), 1)
                equal(part.drawLayer, "OVERLAY")
                for index = 1, 4 do equal(part.color[index], color[index]) end
            end
        end
    end
    profile.textColor = { 0.3, 0.6, 0.9, 0.75 }; Menubar:Rebuild()
    for _, bar in pairs(Menubar.bars) do
        for _, part in ipairs(bar.menu.icon) do
            for index = 1, 4 do equal(part.color[index], profile.textColor[index]) end
        end
    end
    local before = textureCount
    for _ = 1, 20 do Menubar:Rebuild() end
    equal(textureCount, before)
end)

check("Mac OS X is selectable with dark Friz text while preserving user sizing opacity and layout", function()
    local profile = Menubar:GetProfile()
    pickStyle("Mac OS X (Aqua)")
    profile.fontSize, profile.opacity, profile.height = 18, 0.37, 32
    profile.placement, profile.coreMenuBar = "both", "bottom"
    pickStyle("Warcraft Red"); pickStyle("Mac OS X (Aqua)")
    equal(profile.theme, "macosx"); equal(profile.texture, "theme")
    equal(profile.background[1], 0.94); equal(profile.background[2], 0.95); equal(profile.background[3], 0.96)
    equal(profile.font, "Fonts\\FRIZQT__.TTF"); equal(profile.fontStyle, "regular")
    equal(profile.textShadow, false); equal(profile.roundedCorners, true)
    equal(profile.topLineSize, 1); equal(profile.bottomLineSize, 1)
    equal(profile.fontSize, 18); equal(profile.opacity, 0.37); equal(profile.height, 32)
    equal(profile.placement, "both"); equal(profile.coreMenuBar, "bottom")
    local label = runtime("theme-clock").label
    equal(label.font, "Fonts\\FRIZQT__.TTF"); equal(label.fontSize, 18)
    equal(label.shadowColor[4], 0)
    for index = 1, 3 do equal(label.textColor[index], 0) end
    for _, bar in pairs(Menubar.bars) do
        assert(not anySurface(bar.warcraftSkin))
        for _, owner in ipairs({ bar, bar.menu, bar.overflow }) do
            for _, region in ipairs(textures(owner.warcraftSkin)) do assert(not region:IsShown()) end
        end
        for _, corner in ipairs(bar.corners) do assert(corner:IsShown()) end
    end
    profile.fontSize, profile.height = 12, 24
    Menubar:Rebuild()
end)

check("Aqua shading reuses a bounded pool across heights and other themes without stale rows", function()
    local profile = Menubar:GetProfile()
    profile.placement, profile.height = "both", 96
    assert(Model.ApplyTheme(profile, "macosx")); Menubar:Rebuild()
    local original = {}
    for name, bar in pairs(Menubar.bars) do
        equal(#bar.shadingBands, 96)
        original[name] = { unpack(bar.shadingBands) }
    end
    local texturesBefore, framesBefore = textureCount, #Stub.frames
    for _ = 1, 3 do
        for _, height in ipairs({ 16, 24, 96 }) do
            for _, theme in ipairs({ "macosx", "macos8", "system7", "warcraftBrown" }) do
                assert(Model.ApplyTheme(profile, theme)); profile.height = height; Menubar:Rebuild()
                for name, bar in pairs(Menubar.bars) do
                    equal(#bar.shadingBands, 96)
                    local active, lastBottom = 0, nil
                    for index, band in ipairs(bar.shadingBands) do
                        equal(band, original[name][index])
                        equal(band:GetParent(), bar.surface)
                        if band:IsShown() then
                            active = active + 1
                            assert(index <= height, "Rows outside the current height must be hidden")
                            assert(band:GetTop() <= bar:GetTop() + 0.000001)
                            assert(band:GetBottom() >= bar:GetBottom() - 0.000001)
                            if theme == "macosx" and lastBottom then equal(band:GetTop(), lastBottom) end
                            lastBottom = band:GetBottom()
                        end
                    end
                    equal(active, theme == "macosx" and height or theme == "macos8" and 2 or 0)
                end
                equal(textureCount, texturesBefore); equal(#Stub.frames, framesBefore)
            end
        end
    end
    profile.height = 24; pickStyle("Mac OS X (Aqua)")
end)

check("Aqua style texture can be restored after solid fine-line and custom overrides", function()
    local profile = Menubar:GetProfile()
    local function pattern(option)
        Menubar.UI:OpenSettings(); control("Background pattern"):OpenMenu()
        Stub.MenuItem(Stub.menus[#Stub.menus], option).callback()
    end
    local function assertShading(shown)
        for _, bar in pairs(Menubar.bars) do
            assert(#bar.shadingBands > 0)
            for index, band in ipairs(bar.shadingBands) do equal(band:IsShown(), shown and index <= profile.height) end
        end
    end
    pickStyle("Mac OS X (Aqua)"); assertShading(true)
    for _, choice in ipairs({ { "Solid", "solid" }, { "Fine lines", "dither" } }) do
        pattern(choice[1]); equal(profile.texture, choice[2]); assertShading(false)
        if choice[2] == "dither" then
            for _, bar in pairs(Menubar.bars) do assert(bar.dither[1]:IsShown()) end
        end
        pattern("Style texture"); equal(profile.texture, "theme"); assertShading(true)
        for _, bar in pairs(Menubar.bars) do
            for _, line in ipairs(bar.dither) do assert(not line:IsShown()) end
        end
    end
    Menubar.UI:OpenSettings()
    local field = control("Custom texture file")
    field:SetText("Interface\\AddOns\\Custom\\Background.tga")
    field:GetScript("OnEnterPressed")(field)
    assertShading(false)
    for _, bar in pairs(Menubar.bars) do
        equal(bar.background.texture, "Interface\\AddOns\\Custom\\Background.tga")
        assert(bar.background:IsShown())
    end
    pattern("Style texture"); assertShading(true)
    for _, bar in pairs(Menubar.bars) do equal(bar.background.texture, nil) end
end)

check("Liquid Glass is translucent with readable chrome on both bars and restores cleanly", function()
    local profile = Menubar:GetProfile()
    pickStyle("Mac OS 7.6 (Harmony)")
    profile.opacity, profile.popupOpacity, profile.placement = 0.75, 0.84, "both"
    pickStyle("macOS 27 (Liquid Glass)")
    equal(profile.theme, "macos27"); equal(profile.opacity, 0.45); equal(profile.popupOpacity, 0.90)
    equal(profile.font, "Fonts\\FRIZQT__.TTF")
    assert(profile.background[4] > 0 and profile.background[4] < 1)
    for _, bar in pairs(Menubar.bars) do
        assert(not bar.background:IsShown()); assert(not bar.overflow.background:IsShown())
        equal(bar.surface:GetAlpha(), 0.45)
        assert(not bar.topLine:IsShown() and not bar.bottomLine:IsShown())
        equal(bar.menu.icon[1].color[1], 1); equal(bar.overflow.Label.textColor[1], 1)
        local last = math.huge
        for index = 1, profile.height do
            local band = bar.shadingBands[index]
            assert(band:IsShown()); assert(band.color[1] < last)
            equal(band.color[4], profile.background[4])
            last = band.color[1]
        end
    end
    profile.opacity, profile.popupOpacity = 0.31, 0.72
    Model.NormalizeProfile(profile)
    equal(profile.opacity, 0.31)
    pickStyle("Mac OS 7.6 (Harmony)")
    equal(profile.opacity, 0.75); equal(profile.opacityBeforeGlass, nil); equal(profile.popupOpacity, 0.84)
    for _, bar in pairs(Menubar.bars) do
        assert(bar.background:IsShown()); assert(bar.overflow.background:IsShown())
        for _, band in ipairs(bar.shadingBands) do assert(not band:IsShown()) end
        equal(bar.menu.icon[1].color[1], 0)
    end
end)

print(passed .. " bar theme tests passed")
