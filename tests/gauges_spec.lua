-- Renderer behavior through the real host and this clone's official providers.
local root = REPO_ROOT or "."
local Stub = dofile(root .. "/tests/wow_stub.lua")
Stub.Install()
for _, file in ipairs({ "Model.lua", "Identity.lua", "Fonts.lua", "Layout.lua", "Gauge.lua", "Skins.lua", "Core.lua", "UI.lua", "Settings.lua" }) do
    dofile(root .. "/src/menubar-core/" .. file)
end

local current, maximum, shade, overlay, width, atlas = 25, 100, { 0.2, 0.7, 0.3, 1 }, "25%", 160, nil
local bonus
Menubar:RegisterWidgetType({
    id = "gauge-fixture", name = "Gauge fixture", defaults = { presentation = "gauge" },
    defaultPlacement = { bar = "top", alignment = "left" },
    update = function(widget)
        if widget.settings.presentation == "text" then widget:HideGauge(); widget:SetText("brief")
        else widget:SetGauge(current, maximum, shade, overlay, width, atlas, bonus) end
    end,
})
-- Pin the renderer's border geometry instead of relying on factory styling.
MenubarDB = { profiles = { Default = { theme = "system7", topLineSize = 1, bottomLineSize = 1 } } }
Menubar:Start()
local widget = Menubar.runtime.w1
local passed = 0
local function check(name, callback)
    local ok, reason = pcall(callback)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function refresh() Menubar:RefreshWidget(widget.id) end
local function near(actual, expected)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.000001,
        "expected approximately " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function pointOffset(region, anchor)
    for _, point in ipairs(region.points) do if point[1] == anchor then return point[4] end end
    error("Missing " .. anchor .. " anchor", 0)
end
local function nativeGauge(value)
    for _, frame in ipairs(Stub.frames) do
        if frame.template == "ColoredProgressBarTemplate" then
            local parent = frame:GetParent()
            while parent do
                if parent == value.frame then return frame end
                parent = parent:GetParent()
            end
        end
    end
end
local function squareEdges(value)
    local edges = {}
    for _, texture in ipairs(Stub.textures) do
        local color = texture.color
        if texture:GetParent() == value.gauge and texture.drawLayer == "OVERLAY"
            and color and color[1] == 0 and color[2] == 0 and color[3] == 0 then
            edges[#edges + 1] = texture
        end
    end
    assert(#edges == 4, "Expected the existing square gauge's four border rules")
    return edges
end
local function nativeArt()
    return { GetAtlasInfo = function(name)
        if name == "common-stat-bar-BG" or name == "common-stat-bar-white" or name == "common-stat-bar-Mask" then
            return { width = 67, height = 29 }
        elseif name == "native-xp-test" then return { width = 100, height = 10 } end
    end }
end

check("the host uses an inset native StatusBar with a separate overlay above its fill", function()
    assert(not widget.failed and widget.gaugeActive)
    equal(widget.gauge.kind, "StatusBar")
    equal(widget.gauge:GetParent(), widget.frame)
    equal(widget.gauge:GetHeight(), widget.frame:GetHeight() - 6)
    equal(widget.width, 160)
    equal(widget.gauge.points[1][4], 2)
    equal(widget.gauge.points[2][4], -2)
    assert(widget.gauge:GetFrameLevel() > widget.frame:GetFrameLevel())
    equal(widget.gaugeLabel:GetParent(), widget.gauge)
    assert(not widget.label:IsShown())
    equal(widget.gauge:GetValue(), 25)
    equal(select(2, widget.gauge:GetMinMaxValues()), 100)
end)

check("overlay text keeps the game's gauge font white with a black outline and shadow", function()
    local label = widget.gaugeLabel
    equal(label.fontObject, TextStatusBarText)
    equal(label.fontFlags, "OUTLINE")
    for index = 1, 4 do equal(label.textColor[index], 1) end
    equal(label.shadowColor[1], 0); equal(label.shadowColor[4], 1)
    equal(label.shadowOffset[1], 1); equal(label.shadowOffset[2], -1)
    equal(label:GetText(), "25%")
    local profile = Menubar:GetProfile()
    profile.font, profile.fontSize, profile.textColor = "Custom\\Menu.ttf", 28, { 0, 0, 0, 1 }
    Menubar:Rebuild()
    equal(widget.gaugeLabel, label)
    equal(label.font, "Fonts\\FRIZQT__.TTF")
    equal(label.fontSize, 12)
    equal(label.fontFlags, "OUTLINE")
    equal(label.textColor[1], 1)
end)

check("valid transient overflows clamp to gauge bounds and independent RGB colours apply", function()
    current, shade = 150, { 0.8, 0.25, 0.1, 0.7 }
    refresh()
    equal(widget.gauge:GetValue(), 100)
    equal(widget.gauge.statusBarColor[1], 0.8)
    equal(widget.gauge.statusBarColor[4], 0.7)
    current = -50
    refresh()
    equal(widget.gauge:GetValue(), 0)
    current, shade = 25, { 0.2, 0.7, 0.3, 1 }
end)

check("native XP fill atlases are preserved without applying a second colour tint", function()
    C_Texture = { GetAtlasInfo = function(name) return name == "native-xp-test" and { width = 100, height = 10 } or nil end }
    atlas = "native-xp-test"
    refresh()
    assert(widget.gaugeAtlasApplied)
    equal(widget.gauge:GetStatusBarTexture().atlas, atlas)
    equal(widget.gauge.statusBarColor[1], 1)
    equal(widget.gauge.statusBarColor[2], 1)
    atlas = "not-a-real-atlas"
    refresh()
    assert(not widget.gaugeAtlasApplied)
    equal(widget.gauge:GetStatusBarTexture().texture, "Interface\\TargetingFrame\\UI-StatusBar")
    equal(widget.gauge:GetStatusBarTexture().atlas, nil)
    equal(widget.gauge.statusBarColor[2], 0.7)
    atlas, C_Texture = nil, nil
end)

check("canonical atlas casing preserves the earned fill instead of tinting its fallback", function()
    local texture = widget.gauge:GetStatusBarTexture()
    local getAtlas, previous = texture.GetAtlas, C_Texture
    C_Texture = { GetAtlasInfo = function() return { width = 100, height = 10 } end }
    texture.GetAtlas = function(value) return value.atlas and value.atlas:upper() end
    atlas = "native-xp-test"; refresh()
    assert(not widget.failed and widget.gaugeAtlasApplied)
    equal(texture.atlas, atlas)
    for index = 1, 3 do equal(widget.gauge.statusBarColor[index], 1) end
    texture.GetAtlas, C_Texture, atlas = getAtlas, previous, nil; refresh()
end)

check("missing malformed restricted and different atlas readbacks retain the earned fill fallback", function()
    local texture = widget.gauge:GetStatusBarTexture()
    local getAtlas, previous, secretCheck = texture.GetAtlas, C_Texture, issecretvalue
    local secret = setmetatable({}, { __tostring = function() error("restricted atlas formatted", 0) end })
    issecretvalue = function(value) return rawequal(value, secret) end
    C_Texture = { GetAtlasInfo = function() return { width = 100, height = 10 } end }
    for _, result in ipairs({ {}, { value = false }, { value = 27 }, { value = {} },
        { value = secret }, { value = "NATIVE-XP-OTHER" } }) do
        texture.GetAtlas = function() return result.value end
        atlas = "native-xp-test"; refresh()
        assert(not widget.failed and not widget.gaugeAtlasApplied)
        equal(texture.texture, "Interface\\TargetingFrame\\UI-StatusBar")
        equal(widget.gauge.statusBarColor[2], shade[2])
        atlas = nil; refresh()
    end
    texture.GetAtlas, C_Texture, issecretvalue = getAtlas, previous, secretCheck
end)

check("size and profile rebuilds reuse the same status bar and overlay", function()
    local original, label, count = widget.gauge, widget.gaugeLabel, #Stub.frames
    width, Menubar:GetProfile().height = 208, 32
    Menubar:Rebuild()
    equal(widget.gauge, original); equal(widget.gaugeLabel, label)
    equal(widget.gauge:GetHeight(), 26)
    equal(widget.width, 208)
    equal(widget.gaugeLabel:GetWidth(), 196)
    for _ = 1, 20 do Menubar:Rebuild() end
    equal(#Stub.frames, count)
end)

check("switching to ordinary text restores the current profile font and measured width", function()
    local original, label = widget.gauge, widget.gaugeLabel
    widget.settings.presentation = "text"
    refresh()
    assert(not widget.gaugeActive and not original:IsShown())
    assert(widget.label:IsShown())
    equal(widget.customWidth, nil)
    equal(widget.label.font, "Custom\\Menu.ttf")
    equal(widget.label.fontSize, 28)
    equal(widget.label.fontFlags, "")
    equal(widget.label.textColor[1], 0)
    equal(widget.width, widget.label:GetStringWidth() + 8)
    widget.settings.presentation = "gauge"
    refresh()
    equal(widget.gauge, original); equal(widget.gaugeLabel, label)
    equal(widget.customWidth, 208)
    equal(widget.width, 208)
    assert(not widget.label:IsShown())
end)

check("invalid gauge data is isolated and replaced with a readable ordinary error label", function()
    maximum = 0
    refresh()
    assert(widget.failed)
    assert(not widget.gaugeActive and not widget.gauge:IsShown())
    assert(widget.label:IsShown())
    equal(widget.customWidth, nil)
    assert(widget.text:find("error", 1, true))
    assert(widget.width >= widget.label:GetStringWidth() + 8)
    maximum = 100
    refresh()
    assert(not widget.failed and widget.gaugeActive)
    equal(widget.gaugeLabel:GetText(), "25%")
    equal(widget.width, 208)
end)

check("secret or malformed colours never reach native bar arithmetic or drawing", function()
    local hidden = setmetatable({}, { __lt = function() error("restricted comparison") end })
    issecretvalue = function(value) return rawequal(value, hidden) end
    shade = { hidden, 0.2, 0.3, 1 }
    refresh()
    assert(widget.failed and not widget.gaugeActive)
    shade = { 0.1, 0.2, 0.3, 1 }
    refresh()
    assert(not widget.failed and widget.gaugeActive)
    issecretvalue = nil
end)

check("thick and unequal bar rules resize and offset the gauge without allocating another frame", function()
    local profile = Menubar:GetProfile()
    local original, label, count = widget.gauge, widget.gaugeLabel, #Stub.frames
    profile.topLineSize, profile.bottomLineSize, profile.height = 6, 1, 24
    Menubar:Rebuild()
    equal(widget.gauge:GetHeight(), 13)
    equal(widget.content:GetHeight(), 17)
    equal(widget.content.points[1][5], -2.5)
    equal(widget.gaugeOffset, 0)
    equal(widget.gauge.points[1][2], widget.content)
    equal(widget.gauge.points[1][5], 0)
    equal(widget.gauge.points[2][5], 0)
    profile.topLineSize, profile.bottomLineSize, profile.height = 6, 6, 16
    Menubar:Rebuild()
    equal(widget.gauge:GetHeight(), 4)
    equal(widget.gaugeOffset, 0)
    equal(widget.gauge.points[1][5], 0)
    equal(widget.gauge, original); equal(widget.gaugeLabel, label)
    equal(#Stub.frames, count)
end)

check("missing or unrecognized saved gauge styles retain the existing square renderer", function()
    local profile = Menubar:GetProfile()
    profile.height, profile.topLineSize, profile.bottomLineSize = 28, 1, 1
    C_Texture = nativeArt()
    for _, style in ipairs({ false, "future-unknown-style" }) do
        widget.settings.gaugeStyle = style or nil
        Menubar:Rebuild()
        assert(not widget.failed and widget.gaugeActive)
        equal(widget.gaugeStyleUsed, "square")
        assert(not nativeGauge(widget) or not nativeGauge(widget):IsVisible())
        for _, edge in ipairs(squareEdges(widget)) do assert(edge:IsVisible()) end
        equal(widget.gauge:GetValue(), 25)
    end
    widget.settings.gaugeStyle = nil
end)

check("Warcraft framing uses the native rounded mask while square rules are hidden", function()
    widget.settings.gaugeStyle = "warcraft"
    refresh()
    local native = assert(nativeGauge(widget), "Warcraft style must create the native progress-bar template")
    assert(not widget.failed and native:IsVisible())
    equal(widget.gaugeStyleUsed, "warcraft")
    assert(not native.Text:IsShown(), "Use the host's outlined overlay rather than a second native label")
    equal(native.Mask.atlas, "common-stat-bar-Mask")
    assert(native.Fill.masks[native.Mask], "Rounded frame requires the native fill mask")
    equal(native.Fill.atlas, "common-stat-bar-white")
    for index = 1, 4 do equal(native.Fill.vertexColor[index], shade[index]) end
    equal(native.fillPercent, 0.25)
    assert(native.Fill:IsShown())
    for _, edge in ipairs(squareEdges(widget)) do assert(not edge:IsVisible()) end
    equal(widget.gaugeLabel:GetText(), "25%")
    equal(widget.gaugeLabel.fontFlags, "OUTLINE")
    equal(widget.gaugeLabel:GetEffectiveAlpha(), 1)
end)

check("the Warcraft frame scales within the bar rules while its overlay stays unscaled", function()
    local native = assert(nativeGauge(widget))
    local profile = Menubar:GetProfile()
    local available = widget.frame:GetHeight() - profile.topLineSize - profile.bottomLineSize
    equal(native:GetHeight(), 29)
    assert(math.abs(native:GetHeight() * native:GetScale() - available) < 0.000001)
    assert(math.abs(native:GetWidth() * native:GetScale() - (widget.width - 4)) < 0.000001)
    assert(native:GetFrameLevel() < widget.gauge:GetFrameLevel())
    equal(widget.gaugeLabel:GetEffectiveScale(), widget.frame:GetEffectiveScale())
    equal(native.mouseEnabled, false)
    equal(native.FillArea.mouseEnabled, false)
end)

check("rounded fill hides at zero and clamps at its full masked width", function()
    local native = assert(nativeGauge(widget))
    current = -5; refresh()
    equal(native.fillPercent, 0)
    assert(not native.Fill:IsShown(), "A zero-width native atlas must not draw its full fill")
    current = 500; refresh()
    equal(native.fillPercent, 1)
    equal(native.Fill:GetWidth(), native.FillArea:GetWidth())
    assert(native.Fill:IsShown())
    current = 25; refresh()
    equal(native.fillPercent, 0.25)
end)

check("style changes and normal ticks reuse all gauge frames, textures and masks", function()
    local gauge, label, native = widget.gauge, widget.gaugeLabel, assert(nativeGauge(widget))
    local frames, textures, masks = #Stub.frames, #Stub.textures, #Stub.masks
    for _ = 1, 20 do
        widget.settings.gaugeStyle = "square"; refresh()
        assert(not native:IsVisible())
        for _, edge in ipairs(squareEdges(widget)) do assert(edge:IsVisible()) end
        widget.settings.gaugeStyle = "warcraft"; refresh()
        assert(native:IsVisible())
        for _, edge in ipairs(squareEdges(widget)) do assert(not edge:IsVisible()) end
        Menubar.eventFrame.scripts.OnUpdate(Menubar.eventFrame, 1)
    end
    equal(widget.gauge, gauge); equal(widget.gaugeLabel, label); equal(nativeGauge(widget), native)
    equal(#Stub.frames, frames); equal(#Stub.textures, textures); equal(#Stub.masks, masks)
end)

check("text presentation hides Warcraft framing and recovers the chosen style", function()
    local native = assert(nativeGauge(widget))
    local previous = widget.gauge:GetScript("OnShow")
    widget.gauge:SetScript("OnShow", function(bar) bar:GetStatusBarTexture():Show() end)
    widget.settings.presentation = "text"; refresh()
    assert(not native:IsVisible() and widget.label:IsVisible())
    equal(widget.label.font, "Custom\\Menu.ttf")
    widget.settings.presentation = "gauge"; refresh()
    assert(native:IsVisible() and not widget.label:IsShown())
    assert(not widget.gauge:GetStatusBarTexture():IsShown(), "A native OnShow refresh must not reveal square fill")
    equal(widget.settings.gaugeStyle, "warcraft")
    widget.gauge:SetScript("OnShow", previous)
end)

check("Warcraft gauge opacity stays independent of the menubar background", function()
    local profile = Menubar:GetProfile()
    profile.opacity = 0
    Menubar:Rebuild()
    local native = assert(nativeGauge(widget))
    assert(native:IsVisible() and native.Fill:IsVisible())
    equal(native:GetEffectiveAlpha(), 1)
    equal(native.Fill:GetEffectiveAlpha(), 1)
    equal(widget.gaugeLabel:GetEffectiveAlpha(), 1)
    equal(Menubar.bars.top.surface:GetAlpha(), 0)
    profile.opacity = 1
end)

check("compact heights and thick rules keep gauge content within its available body", function()
    local profile = Menubar:GetProfile()
    profile.height, profile.topLineSize, profile.bottomLineSize = 16, 6, 6
    Menubar:Rebuild()
    local native = nativeGauge(widget)
    assert(not widget.failed and widget.gaugeActive and widget.gaugeLabel:IsVisible())
    equal(widget.gaugeHeight, 4)
    equal(widget.gaugeLabel.fontSize, 12)
    equal(widget.gaugeLabel:GetEffectiveScale(), widget.frame:GetEffectiveScale())
    if native and native:IsVisible() then
        assert(native:GetHeight() * native:GetScale() <= widget.gaugeHeight,
            "A compact native frame must not extend into the bar's thick rules")
    else
        for _, edge in ipairs(squareEdges(widget)) do assert(edge:IsVisible()) end
    end
    profile.height, profile.topLineSize, profile.bottomLineSize = 28, 1, 1
    Menubar:Rebuild()
    assert(nativeGauge(widget):IsVisible())
end)

check("missing native frame art falls back to a readable square gauge for that instance", function()
    local previous = C_Texture
    C_Texture = { GetAtlasInfo = function() return nil end }
    local instance = Menubar:AddWidget("gauge-fixture", "top", "left")
    local missing = Menubar.runtime[instance.id]
    missing.settings.gaugeStyle = "warcraft"
    Menubar:RefreshWidget(missing.id)
    assert(not missing.failed and missing.gaugeActive and missing.gaugeLabel:IsVisible())
    equal(missing.gaugeStyleUsed, "square")
    assert(not nativeGauge(missing) or not nativeGauge(missing):IsVisible())
    for _, edge in ipairs(squareEdges(missing)) do assert(edge:IsVisible()) end
    equal(missing.gauge:GetValue(), 25)
    equal(missing.gaugeLabel:GetText(), "25%")
    equal(missing.settings.gaugeStyle, "warcraft")
    equal(widget.settings.gaugeStyle, "warcraft")
    C_Texture = previous
    Menubar:RefreshWidget(missing.id)
    equal(missing.gaugeStyleUsed, "warcraft")
    assert(nativeGauge(missing):IsVisible(), "A failed art preflight must recover when art becomes available")
    Menubar:RemoveWidget(missing.id)
end)

check("a missing native mixin uses square framing and can recover without losing settings", function()
    local previous = ColoredProgressBarMixin
    ColoredProgressBarMixin = nil
    local instance = Menubar:AddWidget("gauge-fixture", "top", "left")
    local missing = Menubar.runtime[instance.id]
    missing.settings.gaugeStyle = "warcraft"
    Menubar:RefreshWidget(missing.id)
    assert(not missing.failed and missing.gaugeActive)
    equal(missing.gaugeStyleUsed, "square")
    for _, edge in ipairs(squareEdges(missing)) do assert(edge:IsVisible()) end
    ColoredProgressBarMixin = previous
    Menubar:RefreshWidget(missing.id)
    equal(missing.gaugeStyleUsed, "warcraft")
    assert(nativeGauge(missing):IsVisible())
    Menubar:RemoveWidget(missing.id)
end)

check("a failed native template is cached per instance without repeated allocation or errors", function()
    local previous, attempts = CreateFrame, 0
    CreateFrame = function(kind, name, parent, template)
        if template == "ColoredProgressBarTemplate" then
            attempts = attempts + 1
            error("native template unavailable")
        end
        return previous(kind, name, parent, template)
    end
    local instance = Menubar:AddWidget("gauge-fixture", "top", "left")
    local failed = Menubar.runtime[instance.id]
    failed.settings.gaugeStyle = "warcraft"
    Menubar:RefreshWidget(failed.id)
    assert(not failed.failed and failed.gaugeActive and failed.gaugeLabel:IsVisible())
    equal(failed.gaugeStyleUsed, "square")
    equal(attempts, 1)
    local frames, textures, masks = #Stub.frames, #Stub.textures, #Stub.masks
    for _ = 1, 10 do Menubar:RefreshWidget(failed.id) end
    equal(attempts, 1)
    equal(#Stub.frames, frames); equal(#Stub.textures, textures); equal(#Stub.masks, masks)
    for _, edge in ipairs(squareEdges(failed)) do assert(edge:IsVisible()) end
    assert(not failed.gaugeWarcraftAnchor:IsVisible())
    equal(failed.settings.gaugeStyle, "warcraft")
    assert(nativeGauge(widget):IsVisible(), "One unavailable native template must not hide another widget")
    CreateFrame = previous
    Menubar:RemoveWidget(failed.id)
end)

check("a failed partial gauge retains its native objects for a bounded retry", function()
    local previous, interrupted = CreateFrame, false
    CreateFrame = function(kind, name, parent, template)
        local frame = previous(kind, name, parent, template)
        if kind == "StatusBar" then
            local createTexture, count = frame.CreateTexture, 0
            frame.CreateTexture = function(bar, ...)
                count = count + 1
                if count == 3 and not interrupted then interrupted = true; error("texture allocation interrupted") end
                return createTexture(bar, ...)
            end
        end
        return frame
    end
    local instance = Menubar:AddWidget("gauge-fixture", "top", "left")
    CreateFrame = previous
    local partial = Menubar.runtime[instance.id]
    assert(interrupted and partial.failed)
    local bar, background, edge = partial.gauge, partial.gaugeBackground, partial.gaugeEdges[1]
    assert(bar and not bar:IsVisible() and not partial.gaugeReady)
    assert(partial.label:IsVisible(), "A failed partial gauge must leave ordinary error text visible")
    local frames, textures = #Stub.frames, #Stub.textures
    Menubar:RefreshWidget(partial.id)
    assert(not partial.failed and partial.gaugeReady and partial.gaugeActive and bar:IsVisible())
    equal(partial.gauge, bar); equal(partial.gaugeBackground, background); equal(partial.gaugeEdges[1], edge)
    equal(#Stub.frames, frames); equal(#Stub.textures, textures + 3)
    Menubar:RefreshWidget(partial.id)
    equal(#Stub.frames, frames); equal(#Stub.textures, textures + 3)
    Menubar:RemoveWidget(partial.id)
end)

check("reset restores ordinary label presentation and releases gauge width without rewriting text", function()
    local original = widget.text
    widget.label:ClearAllPoints(); widget.label:SetPoint("RIGHT", -20, 0)
    widget.label:SetTextColor(0.9, 0.2, 0.1, 1)
    Menubar.UI:ResetWidgetPresentation(widget)
    assert(not widget.gaugeActive and not widget.gauge:IsVisible() and not nativeGauge(widget):IsVisible())
    equal(widget.customWidth, nil)
    assert(widget.label:IsVisible())
    equal(widget.label.points[1][1], "CENTER")
    equal(widget.label.points[1][2], widget.content)
    equal(widget.label.font, Menubar:GetProfile().font)
    for index = 1, 4 do equal(widget.label.textColor[index], Menubar:GetProfile().textColor[index]) end
    equal(widget.text, original)
    refresh()
    assert(widget.gaugeActive and widget.gauge:IsVisible() and not widget.label:IsShown())
end)

check("an interrupted native gauge setup is hidden and resumed on the same allocated frame", function()
    local previous, interrupted = CreateFrame, false
    local instance = Menubar:AddWidget("gauge-fixture", "top", "left")
    local partial = Menubar.runtime[instance.id]
    CreateFrame = function(kind, name, parent, template)
        local frame = previous(kind, name, parent, template)
        if template == "ColoredProgressBarTemplate" then
            local setLevel = frame.SetFrameLevel
            frame.SetFrameLevel = function(value, ...)
                if not interrupted then interrupted = true; error("native frame setup interrupted") end
                return setLevel(value, ...)
            end
        end
        return frame
    end
    partial.settings.gaugeStyle = "warcraft"
    Menubar:RefreshWidget(partial.id)
    CreateFrame = previous
    assert(interrupted and partial.failed and not partial.gaugeWarcraftReady)
    local native, frames = partial.gaugeWarcraft, #Stub.frames
    assert(native and not native:IsVisible() and not partial.gauge:IsVisible())
    Menubar:RefreshWidget(partial.id)
    assert(not partial.failed and partial.gaugeWarcraftReady and native:IsVisible())
    equal(partial.gaugeWarcraft, native); equal(#Stub.frames, frames)
    equal(native.mouseEnabled, false); equal(native.FillArea.mouseEnabled, false)
    Menubar:RemoveWidget(partial.id)
end)

check("a silent atlas no-op preserves the fallback texture and provider colour", function()
    local texture = widget.gauge:GetStatusBarTexture()
    local setAtlas, getAtlas, oldArt = texture.SetAtlas, texture.GetAtlas, C_Texture
    texture.SetAtlas = function() return nil end
    texture.GetAtlas = function(value) return value.atlas end
    C_Texture, atlas = nativeArt(), "native-xp-test"
    refresh()
    assert(not widget.gaugeAtlasApplied)
    equal(texture.texture, "Interface\\TargetingFrame\\UI-StatusBar")
    equal(widget.gauge.statusBarColor[2], shade[2])
    texture.SetAtlas, texture.GetAtlas, C_Texture, atlas = setAtlas, getAtlas, oldArt, nil
    refresh()
end)

check("rested prediction extends after earned XP in both styles without altering earned progress or labels", function()
    current, maximum, bonus = 25, 100, { value = 30, color = { 0.3, 0.65, 1, 1 } }
    widget.settings.gaugeStyle = "square"; refresh()
    local square = assert(widget.gaugeBonus)
    assert(not widget.failed and square:IsVisible())
    equal(square:GetParent(), widget.gauge)
    near(pointOffset(square, "TOPLEFT"), (widget.width - 4) * 0.25)
    near(square:GetWidth(), (widget.width - 4) * 0.3)
    equal(square.drawLayer, "ARTWORK"); equal(square.drawLevel, -1)
    equal(widget.gauge:GetValue(), 25); equal(widget.gaugeLabel:GetText(), "25%")
    widget.settings.gaugeStyle = "warcraft"; refresh()
    local native, prediction = assert(nativeGauge(widget)), assert(widget.gaugeWarcraftBonus)
    assert(prediction:IsVisible() and not square:IsVisible())
    equal(prediction:GetParent(), native)
    near(pointOffset(prediction, "LEFT"), native.FillArea:GetWidth() * 0.25)
    near(prediction:GetWidth(), native.FillArea:GetWidth() * 0.3)
    equal(prediction:GetHeight(), native.Fill:GetHeight())
    assert(prediction.masks[native.Mask], "The rested prediction must share the rounded native mask")
    equal(prediction.drawLayer, "BORDER"); equal(prediction.drawLevel, -1)
    near(prediction.texCoords[1], 0.25); near(prediction.texCoords[2], 0.55)
    equal(prediction.texCoords[3], 1); equal(prediction.texCoords[4], 0)
    for index = 1, 4 do equal(prediction.vertexColor[index], bonus.color[index]) end
    equal(native.fillPercent, 0.25)
    equal(widget.gauge:GetValue(), 25); equal(widget.gaugeLabel.fontFlags, "OUTLINE")
end)

check("native rested geometry follows a later fill-area resize without another provider update", function()
    bonus = { value = 30, color = { 0.3, 0.65, 1, 1 } }
    widget.settings.gaugeStyle = "warcraft"; refresh()
    local native, prediction = nativeGauge(widget), widget.gaugeWarcraftBonus
    local handler = assert(native.FillArea:GetScript("OnSizeChanged"), "Native anchored geometry needs a resize refresh")
    native:SetWidth(native:GetWidth() + 40)
    handler(native.FillArea)
    near(pointOffset(prediction, "LEFT"), native.FillArea:GetWidth() * 0.25)
    near(prediction:GetWidth(), native.FillArea:GetWidth() * 0.3)
    local getWidth = native.FillArea.GetWidth
    native.FillArea.GetWidth = function() return 0 end
    refresh()
    assert(not prediction:IsShown(), "Unresolved anchored width must not paint a full-size prediction")
    native.FillArea.GetWidth = getWidth
    handler(native.FillArea)
    assert(prediction:IsVisible())
    near(prediction:GetWidth(), native.FillArea:GetWidth() * 0.3)
    local frames, textures = #Stub.frames, #Stub.textures
    for _ = 1, 20 do refresh() end
    equal(native.FillArea:GetScript("OnSizeChanged"), handler)
    equal(#Stub.frames, frames); equal(#Stub.textures, textures)
    bonus = nil; refresh()
    handler(native.FillArea)
    assert(not prediction:IsShown(), "An anchored resize must not reveal a cleared prediction")
end)

check("a native rested-prediction atlas keeps its own colour and unavailable art restores the lighter fallback", function()
    local previous, predictionAtlas = C_Texture, "UI-HUD-ExperienceBar-Fill-Prediction"
    local art = nativeArt()
    C_Texture = { GetAtlasInfo = function(name)
        if name == predictionAtlas then return { width = 100, height = 10 } end
        return art.GetAtlasInfo(name)
    end }
    bonus = { value = 30, color = { 0.3, 0.65, 1, 1 }, atlas = predictionAtlas }
    widget.settings.gaugeStyle = "square"; refresh()
    local prediction = assert(widget.gaugeBonus)
    equal(prediction.atlas, predictionAtlas)
    near(prediction.texCoords[1], 0.25); near(prediction.texCoords[2], 0.55)
    equal(prediction.texCoords[3], 0); equal(prediction.texCoords[4], 1)
    for index = 1, 4 do equal(prediction.vertexColor[index], 1) end
    C_Texture = { GetAtlasInfo = function() return nil end }
    bonus.atlas = "missing-prediction-atlas"; refresh()
    equal(prediction.atlas, nil)
    equal(prediction.texture, "Interface\\TargetingFrame\\UI-StatusBar")
    for index = 1, 4 do equal(prediction.vertexColor[index], bonus.color[index]) end
    C_Texture, bonus = previous, nil; refresh()
end)

check("canonical atlas casing preserves the rested fill's native colour", function()
    local previous, predictionAtlas = C_Texture, "UI-HUD-ExperienceBar-Fill-Prediction"
    C_Texture = { GetAtlasInfo = function() return { width = 100, height = 10 } end }
    local prediction = assert(widget.gaugeBonus)
    local getAtlas = prediction.GetAtlas
    prediction.GetAtlas = function(value) return value.atlas and value.atlas:lower() end
    bonus = { value = 30, color = { 0.3, 0.65, 1, 1 }, atlas = predictionAtlas }
    widget.settings.gaugeStyle = "square"; refresh()
    assert(not widget.failed and widget.gaugeBonusAtlasApplied)
    equal(prediction.atlas, predictionAtlas)
    for index = 1, 4 do equal(prediction.vertexColor[index], 1) end
    prediction.GetAtlas, C_Texture, bonus = getAtlas, previous, nil; refresh()
end)

check("rested predictions clip at the level boundary and avoid overflowing large finite XP pools", function()
    for _, style in ipairs({ "square", "warcraft" }) do
        widget.settings.gaugeStyle = style
        current, maximum, bonus = 80, 100, { value = 1000, color = { 0.3, 0.65, 1, 1 } }
        refresh()
        local prediction = style == "square" and widget.gaugeBonus or widget.gaugeWarcraftBonus
        local extent = style == "square" and (widget.width - 4) or nativeGauge(widget).FillArea:GetWidth()
        near(prediction:GetWidth(), extent * 0.2)
        equal(widget.gauge:GetValue(), 80)
        current, maximum, bonus.value = 9e307, 1e308, 1e308
        refresh()
        assert(not widget.failed and prediction:IsVisible())
        near(prediction:GetWidth(), extent * 0.1)
        current, maximum = 100, 100; refresh(); assert(not prediction:IsShown())
        current = -1; bonus.value = 30; refresh()
        assert(not widget.failed and prediction:IsVisible())
        near(prediction:GetWidth(), extent * 0.3)
        equal(widget.gauge:GetValue(), 0)
    end
    current, maximum, bonus = 25, 100, nil; refresh()
end)

check("absent and exhausted rested pools hide both predictions and text or reset clears stale art", function()
    bonus = { value = 30, color = { 0.3, 0.65, 1, 1 } }
    for _, style in ipairs({ "square", "warcraft" }) do
        widget.settings.gaugeStyle = style; refresh()
        local prediction = style == "square" and widget.gaugeBonus or widget.gaugeWarcraftBonus
        assert(prediction:IsVisible())
        bonus.value = 0; refresh()
        assert(not widget.gaugeBonus:IsShown() and not widget.gaugeWarcraftBonus:IsShown())
        bonus.value = 30; refresh(); assert(prediction:IsVisible())
        local saved = bonus; bonus = nil; refresh()
        assert(not widget.gaugeBonus:IsShown() and not widget.gaugeWarcraftBonus:IsShown())
        bonus = saved; refresh()
        widget.settings.presentation = "text"; refresh()
        local native = nativeGauge(widget)
        if native and native.FillArea:GetScript("OnSizeChanged") then native.FillArea:GetScript("OnSizeChanged")(native.FillArea) end
        assert(not widget.gaugeBonus:IsShown() and not widget.gaugeWarcraftBonus:IsShown())
        widget.settings.presentation = "gauge"; refresh(); assert(prediction:IsVisible())
        Menubar.UI:ResetWidgetPresentation(widget)
        if native and native.FillArea:GetScript("OnSizeChanged") then native.FillArea:GetScript("OnSizeChanged")(native.FillArea) end
        assert(not widget.gaugeBonus:IsShown() and not widget.gaugeWarcraftBonus:IsShown())
        refresh(); assert(prediction:IsVisible())
    end
    bonus = nil; refresh()
end)

check("style flips resize the existing rested art and compact Warcraft fallback leaves no stale native prediction", function()
    bonus = { value = 30, color = { 0.3, 0.65, 1, 1 } }
    widget.settings.gaugeStyle = "square"; refresh()
    widget.settings.gaugeStyle = "warcraft"; refresh()
    local square, native = widget.gaugeBonus, widget.gaugeWarcraftBonus
    local frames, textures, masks = #Stub.frames, #Stub.textures, #Stub.masks
    for _ = 1, 30 do
        widget.settings.gaugeStyle = "square"; refresh()
        assert(square:IsVisible() and not native:IsShown())
        widget.settings.gaugeStyle = "warcraft"; refresh()
        assert(native:IsVisible() and not square:IsShown())
    end
    equal(widget.gaugeBonus, square); equal(widget.gaugeWarcraftBonus, native)
    equal(#Stub.frames, frames); equal(#Stub.textures, textures); equal(#Stub.masks, masks)
    local profile = Menubar:GetProfile()
    profile.height, profile.topLineSize, profile.bottomLineSize = 16, 6, 6
    Menubar:Rebuild()
    equal(widget.gaugeStyleUsed, "square")
    assert(square:IsVisible() and not native:IsShown())
    near(square:GetWidth(), (widget.width - 4) * 0.3)
    profile.height, profile.topLineSize, profile.bottomLineSize = 28, 1, 1
    Menubar:Rebuild()
    equal(widget.gaugeStyleUsed, "warcraft")
    assert(native:IsVisible() and not square:IsShown())
    bonus = nil; refresh()
end)

check("restricted or malformed rested presentation is rejected before native state changes", function()
    local secret = setmetatable({}, {
        __index = function() error("restricted bonus indexed", 0) end,
        __lt = function() error("restricted bonus compared", 0) end,
        __tostring = function() error("restricted bonus formatted", 0) end,
    })
    issecretvalue = function(value) return rawequal(value, secret) end
    local color = { 0.3, 0.65, 1, 1 }
    local invalid = { secret, false, "pool", { value = secret, color = color }, { value = -1, color = color },
        { value = math.huge, color = color }, { value = 0 / 0, color = color }, { value = 30, color = secret },
        { value = 30, color = { secret, 0.65, 1, 1 } }, { value = 30, color = color, atlas = secret } }
    local frames, textures = #Stub.frames, #Stub.textures
    for _, candidate in ipairs(invalid) do
        assert(not pcall(widget.SetGauge, widget, 70, 100, shade, "changed", width, nil, candidate))
        equal(widget.gauge:GetValue(), 25); equal(widget.gaugeLabel:GetText(), "25%")
        equal(#Stub.frames, frames); equal(#Stub.textures, textures)
    end
    issecretvalue = nil
    refresh(); assert(not widget.failed)
end)

check("an interrupted rested texture setup retains ownership and resumes without reallocating", function()
    local previous, interrupted = CreateFrame, false
    bonus = { value = 30, color = { 0.3, 0.65, 1, 1 } }
    CreateFrame = function(kind, name, parent, template)
        local frame = previous(kind, name, parent, template)
        if kind == "StatusBar" then
            local createTexture = frame.CreateTexture
            frame.CreateTexture = function(bar, textureName, layer, subLayer, level)
                local texture = createTexture(bar, textureName, layer, subLayer, level)
                if layer == "ARTWORK" and level == -1 then
                    local setPoint = texture.SetPoint
                    texture.SetPoint = function(value, ...)
                        if not interrupted then interrupted = true; error("rested texture setup interrupted", 0) end
                        return setPoint(value, ...)
                    end
                end
                return texture
            end
        end
        return frame
    end
    local instance = Menubar:AddWidget("gauge-fixture", "top", "left")
    CreateFrame = previous
    local partial = Menubar.runtime[instance.id]
    assert(interrupted and partial.failed)
    local prediction = assert(partial.gaugeBonus)
    assert(not prediction:IsShown() and not partial.gauge:IsVisible() and partial.label:IsVisible())
    local frames, textures = #Stub.frames, #Stub.textures
    Menubar:RefreshWidget(partial.id)
    assert(not partial.failed and prediction:IsVisible())
    equal(partial.gaugeBonus, prediction)
    equal(#Stub.frames, frames); equal(#Stub.textures, textures)
    Menubar:RemoveWidget(partial.id)
    assert(not prediction:IsVisible())
    bonus = nil; refresh()
end)

check("an interrupted native rested mask setup retries the owned texture and installs one resize hook", function()
    bonus = { value = 30, color = { 0.3, 0.65, 1, 1 } }
    local instance = Menubar:AddWidget("gauge-fixture", "top", "left")
    local partial = Menubar.runtime[instance.id]
    local previous, interrupted = CreateFrame, false
    CreateFrame = function(kind, name, parent, template)
        local frame = previous(kind, name, parent, template)
        if template == "ColoredProgressBarTemplate" then
            local createTexture = frame.CreateTexture
            frame.CreateTexture = function(owner, textureName, layer, subLayer, level)
                local texture = createTexture(owner, textureName, layer, subLayer, level)
                if layer == "BORDER" and level == -1 then
                    local attach = texture.AddMaskTexture
                    texture.AddMaskTexture = function(value, mask)
                        if not interrupted then interrupted = true; error("rested mask attachment interrupted", 0) end
                        return attach(value, mask)
                    end
                end
                return texture
            end
        end
        return frame
    end
    partial.settings.gaugeStyle = "warcraft"
    Menubar:RefreshWidget(partial.id)
    CreateFrame = previous
    assert(interrupted and partial.failed and not partial.gaugeWarcraftBonusReady)
    local native, prediction = assert(partial.gaugeWarcraft), assert(partial.gaugeWarcraftBonus)
    assert(not prediction:IsVisible() and not partial.gauge:IsVisible() and partial.label:IsVisible())
    local frames, textures, masks = #Stub.frames, #Stub.textures, #Stub.masks
    Menubar:RefreshWidget(partial.id)
    assert(not partial.failed and partial.gaugeWarcraftBonusReady and prediction:IsVisible())
    equal(partial.gaugeWarcraftBonus, prediction)
    assert(prediction.masks[native.Mask])
    local handler = assert(native.FillArea:GetScript("OnSizeChanged"))
    for _ = 1, 20 do Menubar:RefreshWidget(partial.id) end
    equal(native.FillArea:GetScript("OnSizeChanged"), handler)
    equal(#Stub.frames, frames); equal(#Stub.textures, textures); equal(#Stub.masks, masks)
    Menubar:RemoveWidget(partial.id)
    handler(native.FillArea)
    assert(not prediction:IsVisible())
    bonus = nil; refresh()
end)

check("theme-default framing follows all six themes while reusing gauge art and preserving progress", function()
    local profile = Menubar:GetProfile()
    local oldTheme, oldStyle, oldBonus, oldAtlas = profile.theme, widget.settings.gaugeStyle, bonus, atlas
    local oldHeight, oldTop, oldBottom = profile.height, profile.topLineSize, profile.bottomLineSize
    profile.height, profile.topLineSize, profile.bottomLineSize = 28, 1, 1
    widget.settings.gaugeStyle, widget.settings.presentation = "theme", "gauge"
    current, maximum, shade, overlay, atlas = 25, 100, { 0.2, 0.7, 0.3, 1 }, "25%", nil
    bonus = { value = 30, color = { 0.3, 0.65, 1, 1 } }
    local themes = { { "system7", "square" }, { "macos8", "square" }, { "macosx", "square" },
        { "warcraftBrown", "warcraft" }, { "warcraftBlack", "warcraft" }, { "warcraftRed", "warcraft" } }
    for _, choice in ipairs(themes) do
        assert(MenubarModel.Themes[choice[1]], "The gauge matrix must use registered themes")
        profile.theme = choice[1]; Menubar:Rebuild()
    end
    local bar, label, native, squareBonus, nativeBonus = widget.gauge, widget.gaugeLabel,
        widget.gaugeWarcraft, widget.gaugeBonus, widget.gaugeWarcraftBonus
    local function resources()
        local counts = {}
        for index, objects in ipairs({ Stub.frames, Stub.textures, Stub.masks }) do
            counts[index] = 0
            for _, object in ipairs(objects) do
                local parent = object:GetParent()
                while parent do
                    if parent == widget.frame then counts[index] = counts[index] + 1; break end
                    parent = parent:GetParent()
                end
            end
        end
        return counts
    end
    local counts = resources()
    for _ = 1, 3 do
        for _, choice in ipairs(themes) do
            profile.theme = choice[1]; Menubar:Rebuild()
            equal(widget.gaugeStyleUsed, choice[2]); equal(widget.gaugeTheme, choice[1])
            equal(widget.settings.gaugeStyle, "theme"); equal(widget.instance.settings.gaugeStyle, "theme")
            equal(widget.gauge, bar); equal(widget.gaugeLabel, label); equal(widget.gaugeWarcraft, native)
            equal(widget.gaugeBonus, squareBonus); equal(widget.gaugeWarcraftBonus, nativeBonus)
            equal(widget.gauge:GetValue(), 25); equal(select(2, widget.gauge:GetMinMaxValues()), 100)
            equal(widget.gaugeLabel:GetText(), "25%")
            local red, green, blue = widget.gauge:GetStatusBarColor()
            equal(red, shade[1]); equal(green, shade[2]); equal(blue, shade[3]); equal(bonus.value, 30)
            local prediction = choice[2] == "warcraft" and nativeBonus or squareBonus
            assert(prediction:IsVisible(), "rested prediction follows the effective renderer")
            local after = resources()
            for index = 1, 3 do equal(after[index], counts[index]) end
        end
    end
    profile.theme, profile.height, profile.topLineSize, profile.bottomLineSize = oldTheme, oldHeight, oldTop, oldBottom
    widget.settings.gaugeStyle, bonus, atlas = oldStyle, oldBonus, oldAtlas; Menubar:Rebuild()
end)

check("explicit gauge overrides win on every theme while unsupported theme context falls back safely", function()
    local profile = Menubar:GetProfile()
    local oldTheme, oldStyle = profile.theme, widget.settings.gaugeStyle
    local oldHeight, oldTop, oldBottom = profile.height, profile.topLineSize, profile.bottomLineSize
    profile.height, profile.topLineSize, profile.bottomLineSize = 28, 1, 1
    for _, style in ipairs({ "square", "warcraft" }) do
        widget.settings.gaugeStyle = style
        for _, theme in ipairs({ "system7", "macos8", "macosx", "warcraftBrown", "warcraftBlack", "warcraftRed" }) do
            profile.theme = theme; Menubar:Rebuild()
            equal(widget.gaugeStyleUsed, style); equal(widget.settings.gaugeStyle, style)
        end
    end
    widget.settings.gaugeStyle = "theme"
    local secret, oldSecret = {}, issecretvalue
    issecretvalue = function(value) return rawequal(value, secret) or (type(oldSecret) == "function" and oldSecret(value)) end
    for _, context in ipairs({ false, "unknown-theme", 123, secret }) do
        widget.gaugeTheme = context or nil; refresh()
        equal(widget.gaugeStyleUsed, "square"); equal(widget.settings.gaugeStyle, "theme")
    end
    issecretvalue = oldSecret
    profile.theme, profile.height, profile.topLineSize, profile.bottomLineSize = oldTheme, oldHeight, oldTop, oldBottom
    widget.settings.gaugeStyle = oldStyle; Menubar:Rebuild()
end)

check("theme-default framing retains its setting through compact and unavailable-native-art fallbacks", function()
    local profile = Menubar:GetProfile()
    local oldTheme, oldStyle, oldArt = profile.theme, widget.settings.gaugeStyle, C_Texture
    local oldHeight, oldTop, oldBottom = profile.height, profile.topLineSize, profile.bottomLineSize
    profile.theme, profile.height, profile.topLineSize, profile.bottomLineSize = "warcraftBrown", 16, 6, 6
    widget.settings.gaugeStyle = "theme"; Menubar:Rebuild()
    equal(widget.gaugeStyleUsed, "square"); equal(widget.settings.gaugeStyle, "theme")
    profile.height, profile.topLineSize, profile.bottomLineSize = 28, 1, 1; Menubar:Rebuild()
    equal(widget.gaugeStyleUsed, "warcraft"); equal(widget.settings.gaugeStyle, "theme")
    C_Texture = { GetAtlasInfo = function() return nil end }
    local instance = Menubar:AddWidget("gauge-fixture", "top", "left")
    local missing = Menubar.runtime[instance.id]; missing.settings.gaugeStyle = "theme"
    Menubar:RefreshWidget(missing.id)
    equal(missing.gaugeStyleUsed, "square"); equal(missing.settings.gaugeStyle, "theme")
    local gauge, label = missing.gauge, missing.gaugeLabel
    C_Texture = nativeArt(); Menubar:RefreshWidget(missing.id)
    equal(missing.gaugeStyleUsed, "warcraft"); equal(missing.settings.gaugeStyle, "theme")
    equal(missing.gauge, gauge); equal(missing.gaugeLabel, label); Menubar:RemoveWidget(missing.id)
    C_Texture = oldArt
    profile.theme, profile.height, profile.topLineSize, profile.bottomLineSize = oldTheme, oldHeight, oldTop, oldBottom
    widget.settings.gaugeStyle = oldStyle; Menubar:Rebuild()
end)
local function centerY(region)
    local _, bottom, _, height = region:GetRect()
    return bottom + height / 2
end

check("visual bodies align both gauge renderers and ordinary text across all six themes", function()
    local profile = Menubar:GetProfile()
    local originalProfile = MenubarModel.DeepCopy(profile)
    local originalStyle, originalPresentation = widget.settings.gaugeStyle, widget.settings.presentation
    local frame, content, gauge, label = widget.frame, widget.content, widget.gauge, widget.label
    for _, theme in ipairs({ "system7", "macos8", "macosx", "warcraftBrown", "warcraftBlack", "warcraftRed" }) do
        assert(MenubarModel.ApplyTheme(profile, theme))
        profile.height, profile.placement, profile.coreMenuBar = 28, "both", "both"
        for _, style in ipairs({ "square", "warcraft" }) do
            widget.settings.gaugeStyle, widget.settings.presentation = style, "gauge"
            Menubar:Rebuild()
            local bodyCenter = centerY(frame) + (profile.bottomLineSize - profile.topLineSize) / 2
            equal(widget.frame, frame); equal(widget.content, content); equal(widget.gauge, gauge)
            equal(frame:GetHeight(), profile.height)
            equal(frame.points[1][5], 0)
            equal(content:GetWidth(), frame:GetWidth())
            equal(content:GetHeight(), profile.height - profile.topLineSize - profile.bottomLineSize)
            equal(content.mouseEnabled, false)
            equal(content:GetParent(), frame)
            near(centerY(content), bodyCenter)
            near(centerY(gauge), bodyCenter)
            equal(widget.gaugeOffset, 0)
            if widget.gaugeStyleUsed == "warcraft" then near(centerY(widget.gaugeWarcraftAnchor), bodyCenter) end
            equal(gauge:GetValue(), current)
            equal(gauge:GetAlpha(), 1)
            equal(content:GetAlpha(), 1)
            for _, bar in pairs(Menubar.bars) do
                near(centerY(bar.menu), centerY(bar) + (profile.bottomLineSize - profile.topLineSize) / 2)
                near(centerY(bar.overflow), centerY(bar.menu)); near(centerY(bar.empty), centerY(bar.menu))
            end
        end
        widget.settings.presentation = "text"; refresh()
        equal(widget.label, label); equal(label.points[1][2], content)
        near(centerY(label), centerY(content))
    end
    for key in pairs(profile) do profile[key] = nil end
    for key, value in pairs(originalProfile) do profile[key] = value end
    widget.settings.gaugeStyle, widget.settings.presentation = originalStyle, originalPresentation
    Menubar:Rebuild()
end)

check("compact body geometry keeps input frames full height and menu controls inside either bar", function()
    local profile = Menubar:GetProfile()
    local original = MenubarModel.DeepCopy(profile)
    local content, frame, gauge = widget.content, widget.frame, widget.gauge
    for _, placement in ipairs({ "top", "bottom", "both" }) do
        profile.placement, profile.coreMenuBar = placement, "both"
        for _, borders in ipairs({ { 6, 6 }, { 6, 0 }, { 0, 6 }, { 0, 0 } }) do
            profile.height, profile.topLineSize, profile.bottomLineSize = 16, borders[1], borders[2]
            Menubar:Rebuild()
            local height, offset = math.max(4, 16 - borders[1] - borders[2]), (borders[2] - borders[1]) / 2
            equal(widget.content, content); equal(widget.frame, frame); equal(widget.gauge, gauge)
            equal(frame:GetHeight(), 16); equal(frame.points[1][5], 0)
            equal(content:GetHeight(), height); near(centerY(content), centerY(frame) + offset)
            equal(content.points[1][2], frame); equal(content.points[2][2], frame)
            assert(type(frame:GetScript("OnClick")) == "function")
            equal(gauge:GetHeight(), math.max(4, height - math.min(4, height - 4)))
            near(centerY(gauge), centerY(content))
            for _, bar in pairs(Menubar.bars) do
                for _, control in ipairs({ bar.menu, bar.overflow }) do
                    equal(control:GetHeight(), math.min(12, height))
                    near(centerY(control), centerY(bar) + offset)
                    assert(control:GetTop() <= bar:GetTop() and control:GetBottom() >= bar:GetBottom())
                end
                near(centerY(bar.empty), centerY(bar) + offset)
            end
        end
    end
    local count = #Stub.frames
    for _ = 1, 10 do Menubar:Rebuild() end
    equal(#Stub.frames, count); equal(widget.content, content)
    for key in pairs(profile) do profile[key] = nil end
    for key, value in pairs(original) do profile[key] = value end
    Menubar:Rebuild()
end)

check("standalone gauge users retain the original full-frame border inset contract", function()
    local frame = CreateFrame("Button", nil, UIParent); frame:SetSize(160, 24)
    local standalone = { frame = frame, label = frame:CreateFontString(nil, "OVERLAY"), settings = {},
        gaugeTopLineSize = 6, gaugeBottomLineSize = 1,
        SetWidth = function(self, value) self.width, self.customWidth = value, value; self.frame:SetWidth(value) end,
        SetText = function(self, value) self.text = value; self.label:SetText(value) end,
    }
    MenubarGauge.Attach(standalone)
    standalone:SetGauge(25, 100, { 0.2, 0.7, 0.3, 1 }, "25%", 160)
    equal(standalone.content, nil)
    equal(standalone.gauge:GetHeight(), 13)
    equal(standalone.gauge.points[1][2], frame); equal(standalone.gaugeOffset, -2.5)
    standalone:HideGauge()
    equal(standalone.label.points[1][2], frame)
end)
print(passed .. " gauge renderer tests passed")
