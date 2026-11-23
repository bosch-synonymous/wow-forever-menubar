-- Verify the real host's theme/font lifecycle and background-only opacity boundary.
local root = REPO_ROOT or "."
local muteLabel = "|A:voicechat-icon-speaker-mute:14:14|a Mute"
local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end
local core = MENUBAR_CORE_ROOT or root
if not exists(core .. "/tests/wow_stub.lua") then
    print("SKIP Volume theme integration: restore Core in this repository or supply MENUBAR_CORE_ROOT.")
    return
end
local Stub = dofile(core .. "/tests/wow_stub.lua")
Stub.Install()
local audio = { Sound_MasterVolume = "0.5", Sound_EnableAllSound = "1" }
local writes = 0
C_CVar = {
    GetCVar = function(name) return audio[name] end,
    SetCVar = function(name, value) writes = writes + 1; audio[name] = tostring(value); return true end,
}
for _, file in ipairs({ "Model.lua", "Identity.lua", "Fonts.lua", "Layout.lua", "Gauge.lua", "Skins.lua", "Core.lua", "UI.lua", "Settings.lua" }) do
    dofile(core .. "/src/menubar-core/" .. file)
end
dofile(root .. "/src/menubar-volume/Volume.lua")
Menubar:Start()
local volume
for _, widget in pairs(Menubar.runtime) do
    if widget.instance.type == "volume" then volume = widget end
end
assert(volume and not volume.failed, volume and tostring(volume.failed) or "Volume must load")
local passed = 0
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function colourMatches()
    local actual = volume.volumeIcon.vertexColor
    local expected = { volume.label:GetTextColor() }
    for index = 1, 4 do equal(actual[index], expected[index]) end
end

local function visibleControls(slider)
    assert(slider:IsShown() and slider:IsVisible(), "The native slider must be shown after its first attachment")
    assert(slider.mouseEnabled and slider.mouseWheelEnabled, "The visible slider must accept dragging and wheel input")
    assert(slider:GetWidth() > 0 and slider:GetHeight() > 0, "The slider needs a positive input rectangle")
    local parent = slider:GetParent()
    equal(slider:GetFrameStrata(), parent:GetFrameStrata())
    assert(slider:GetFrameLevel() > parent:GetFrameLevel(), "The slider must draw above its menu element")
    equal(slider:GetAlpha(), 1); equal(slider:IsEnabled(), true)
    equal(slider.points[1][2], parent)
    assert(parent:GetWidth() >= slider:GetWidth() and parent:GetHeight() >= slider:GetHeight())
    local thumb, track = assert(slider:GetThumbTexture())
    for _, texture in ipairs(Stub.textures) do
        if texture:GetParent() == slider and texture ~= thumb then track = texture; break end
    end
    assert(track and track:IsVisible() and thumb:IsVisible(), "Both slider art regions must be visible through their parent")
    equal(track:GetAtlas(), "_Minimal_SliderBar_Middle")
    equal(thumb:GetAtlas(), "Minimal_SliderBar_Button"); equal(thumb.useAtlasSize, true)
    assert(track.width > 0 and track.height > 0 and thumb.width > 0 and thumb.height > 0,
        "Track geometry and the atlas-sized thumb need their own positive dimensions")
    local rotation = track.rotation or 0
    local visualWidth = math.abs(math.cos(rotation)) * track.width + math.abs(math.sin(rotation)) * track.height
    local visualHeight = math.abs(math.sin(rotation)) * track.width + math.abs(math.cos(rotation)) * track.height
    assert(visualWidth <= slider:GetWidth() + 0.00001 and visualHeight <= slider:GetHeight() + 0.00001,
        "The visible rotated track must fit the slider's interactive rectangle")
    local left, bottom, width, height = parent:GetRect()
    local labels = parent.testLabels or {}
    equal(#labels, 3)
    local rectangles = {}
    for _, label in ipairs(labels) do
        local x, y, wide, tall = label:GetRect()
        assert(x >= left and x + wide <= left + width and y >= bottom and y + tall <= bottom + height,
            "Every label must fit inside its reserved menu body")
        assert(label:GetStringWidth() <= wide, "Current and endpoint percentages must fit their text columns")
        equal(label.justifyH, "CENTER"); equal(label.wordWrap, false)
        rectangles[#rectangles + 1] = { x, y, wide, tall }
    end
    for first = 1, #rectangles do
        for second = first + 1, #rectangles do
            local a, b = rectangles[first], rectangles[second]
            assert(a[1] + a[3] <= b[1] or b[1] + b[3] <= a[1]
                or a[2] + a[4] <= b[2] or b[2] + b[4] <= a[2], "Percentage labels must not overlap")
        end
    end
end

check("native volume icon follows every core theme across all four speaker states", function()
    local originalWidget, originalIcon = volume, volume.volumeIcon
    local profile = Menubar:GetProfile()
    for _, theme in ipairs({ "system7", "macos8", "warcraftBrown", "warcraftBlack", "warcraftRed" }) do
        assert(MenubarModel.ApplyTheme(profile, theme))
        Menubar:Rebuild()
        equal(Menubar.runtime[volume.id], originalWidget)
        equal(volume.volumeIcon, originalIcon)
        for _, state in ipairs({ { "0", "muted" }, { "0.2", "low" }, { "0.5", "medium" }, { "0.9", "high" } }) do
            audio.Sound_MasterVolume = state[1]
            Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, "CVAR_UPDATE", "Sound_MasterVolume", state[1])
            assert(not volume.failed, tostring(volume.failed))
            assert(volume.volumeIcon.texture:find("volume%-" .. state[2] .. "%.tga"))
            colourMatches()
            equal(volume.label.font, profile.font)
            equal(volume.label.fontSize, profile.fontSize)
        end
    end
    equal(writes, 0)
end)

check("custom text RGBA and icon-only layout remain independent of background opacity", function()
    local profile = Menubar:GetProfile()
    profile.textColor, profile.opacity = { 0.23, 0.67, 0.91, 0.65 }, 0
    Menubar:Rebuild()
    local icon = volume.volumeIcon
    colourMatches()
    equal(icon:GetParent(), volume.frame)
    equal(icon:GetEffectiveAlpha(), 1)
    equal(icon.vertexColor[4], 0.65)
    equal(Menubar.bars.top.surface:GetAlpha(), 0)
    local before = volume.width
    volume.settings.showPercent = false
    Menubar:RefreshWidget(volume.id); Menubar:Layout()
    assert(volume.width < before, "Hiding the percentage should reclaim its reserved space")
    equal(volume.width, 24)
    equal(volume.label:GetText(), "")
    equal(volume.text, "Volume")
    assert(icon:IsVisible())
    colourMatches()
    volume.settings.showPercent = true
    Menubar:RefreshWidget(volume.id); Menubar:Layout()
    equal(volume.volumeIcon, icon)
    assert(volume.label:GetText():find("%%$"))
    assert(volume.text:find("Volume ", 1, true))
    assert(volume.width >= icon:GetWidth() + volume.label:GetStringWidth() + 8)
    colourMatches()
    equal(writes, 0)
end)

check("a failed icon redraw restores the host error layout and can recover with the same texture", function()
    local icon, textures = volume.volumeIcon, #Stub.textures
    local originalTint = icon.SetVertexColor
    icon.SetVertexColor = function(self, ...)
        self.SetVertexColor = originalTint
        error("simulated icon tint failure")
    end
    Menubar:RefreshWidget(volume.id); Menubar:Layout()
    assert(volume.failed and volume.failed:find("simulated icon tint failure", 1, true))
    equal(volume.failedCallback, "update")
    assert(not icon:IsShown(), "Failed graphical content must not overlap the ordinary error label")
    equal(volume.customWidth, nil)
    equal(#volume.label.points, 1)
    equal(volume.label.points[1][1], "CENTER")
    assert(volume.label:GetText():find("error", 1, true))
    assert(volume.frame:GetWidth() >= volume.label:GetStringWidth() + 8,
        "The centered host error label must fit within its measured frame")
    Menubar:RefreshWidget(volume.id); Menubar:Layout()
    assert(not volume.failed and not volume.failedCallback)
    equal(volume.volumeIcon, icon)
    assert(icon:IsVisible())
    equal(volume.label.points[1][1], "LEFT")
    assert(volume.label:GetText():find("%%$"))
    colourMatches()
    equal(#Stub.textures, textures)
    equal(writes, 0)
end)

check("plain left-click opens native vertical controls while Shift-left retains configured orientation", function()
    local previousShift = IsShiftKeyDown
    local shifted = false
    IsShiftKeyDown = function() return shifted end
    volume.settings.orientation = "horizontal"
    audio.Sound_MasterVolume, audio.Sound_EnableAllSound = "0.5", "1"
    Menubar:RefreshWidget(volume.id)
    local before = writes
    equal(Stub.attachmentMetatables.Slider, nil)
    local function controls()
        volume.frame:Click("LeftButton")
        local menu = Stub.menus[#Stub.menus]
        local description
        for _, child in ipairs(menu.children) do if child.kind == "Frame" then description = child; break end end
        assert(description, "The native volume menu must contain a managed slider frame")
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetFrameStrata("FULLSCREEN_DIALOG"); frame:SetFrameLevel(544)
        frame.testLabels = {}
        local attach = frame.AttachFontString
        frame.AttachFontString = function(self, ...)
            local label = attach(self, ...); self.testLabels[#self.testLabels + 1] = label; return label
        end
        local first = #Stub.frames
        local bodyWidth, bodyHeight
        for _, initialize in ipairs(description.initializers) do bodyWidth, bodyHeight = initialize(frame, description, menu) end
        assert(type(bodyWidth) == "number" and type(bodyHeight) == "number", "Native menu layout needs an explicit size override")
        equal(bodyWidth, frame:GetWidth()); equal(bodyHeight, frame:GetHeight())
        local slider
        for index = first + 1, #Stub.frames do if Stub.frames[index].kind == "Slider" then slider = Stub.frames[index]; break end end
        return menu, assert(slider)
    end
    local menu, slider = controls()
    equal(Stub.attachmentMetatables.Slider, true)
    visibleControls(slider)
    equal(writes, before)
    equal(slider.orientation, "VERTICAL"); equal(slider:GetValue(), 50)
    equal(volume.settings.orientation, "horizontal")
    Stub.DragSlider(slider, 20)
    equal(tonumber(audio.Sound_MasterVolume), 0.8)
    slider.scripts.OnMouseWheel(slider, -1)
    equal(tonumber(audio.Sound_MasterVolume), 0.75)
    equal(slider:GetValue(), 25)
    local mute = Stub.MenuItem(menu, muteLabel)
    mute.callback()
    equal(tonumber(audio.Sound_EnableAllSound), 0)
    equal(tonumber(audio.Sound_MasterVolume), 0.75)
    slider:GetParent():Hide(); equal(slider:IsVisible(), false)
    shifted = true
    local fullMenu, horizontal = controls()
    equal(horizontal.orientation, "HORIZONTAL")
    visibleControls(horizontal)
    assert(Stub.MenuItem(fullMenu, "Move earlier"))
    before = writes
    slider.scripts.OnMouseWheel(slider, 1); mute.callback()
    equal(writes, before)
    Stub.DragSlider(horizontal, 60); equal(tonumber(audio.Sound_MasterVolume), 0.6)
    horizontal.scripts.OnMouseWheel(horizontal, 1); equal(tonumber(audio.Sound_MasterVolume), 0.65)
    Stub.MenuItem(fullMenu, muteLabel).callback(); equal(tonumber(audio.Sound_EnableAllSound), 1)
    volume.frame:Click("RightButton")
    equal(Menubar.UI.widgetID, volume.id)
    IsShiftKeyDown = previousShift
end)

check("resetting Volume settings preserves existing game volume and mute CVars without writes", function()
    for _, state in ipairs({ { "0.237500", "0.000" }, { "0.684375000", "1.000" } }) do
        audio.Sound_MasterVolume, audio.Sound_EnableAllSound = state[1], state[2]
        local before = writes
        local defaults = volume.definition.defaults
        volume.settings.showPercent = not defaults.showPercent
        volume.settings.orientation = defaults.orientation == "vertical" and "horizontal" or "vertical"
        local changedSettings = volume.settings
        Menubar:RefreshWidget(volume.id)
        Menubar.UI:OpenWidget(volume.id)
        local reset
        for _, control in ipairs(Menubar.UI.window.controls or {}) do
            if control.caption == "Reset this widget's settings" then reset = control; break end
        end
        assert(reset, "The actual widget Settings page must expose its reset action")
        reset:Click()
        assert(not volume.failed, tostring(volume.failed))
        equal(Menubar.runtime[volume.id], volume)
        assert(volume.settings ~= changedSettings, "Settings reset must replace the changed preference table")
        for _, key in ipairs({ "showPercent", "orientation", "wheelStep" }) do
            equal(volume.settings[key], defaults[key])
        end
        equal(audio.Sound_MasterVolume, state[1])
        equal(audio.Sound_EnableAllSound, state[2])
        equal(writes - before, 0)
    end
end)

check("removed native volume controls cannot write CVars through retained callbacks", function()
    local previousShift = IsShiftKeyDown
    IsShiftKeyDown = function() return false end
    volume.frame:Click("LeftButton")
    local menu = Stub.menus[#Stub.menus]
    local description
    for _, child in ipairs(menu.children) do if child.kind == "Frame" then description = child; break end end
    local frame = CreateFrame("Frame", nil, UIParent)
    local first = #Stub.frames
    for _, initialize in ipairs(description.initializers) do initialize(frame, description, menu) end
    local slider
    for index = first + 1, #Stub.frames do if Stub.frames[index].kind == "Slider" then slider = Stub.frames[index]; break end end
    local mute = Stub.MenuItem(menu, muteLabel)
    local before = writes
    Menubar:RemoveWidget(volume.id)
    slider.scripts.OnValueChanged(slider, 0)
    slider.scripts.OnMouseWheel(slider, 1)
    mute.callback()
    equal(writes, before)
    IsShiftKeyDown = previousShift
end)

print(passed .. " Volume theme integration tests passed")
