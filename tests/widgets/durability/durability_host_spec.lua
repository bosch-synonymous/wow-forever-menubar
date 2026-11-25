-- Integration through the real host. The stub does not reproduce native WoW UI.
local root = REPO_ROOT or "."
local core = MENUBAR_CORE_ROOT or root
local file = io.open(core .. "/tests/wow_stub.lua", "rb")
if not file then
    print("SKIP Durability host integration: restore Core in this clone or supply MENUBAR_CORE_ROOT.")
    return
end
file:close()
local Stub = dofile(core .. "/tests/wow_stub.lua")
Stub.Install()
local yellow, red = "|cffffd12e", "|cffed1212"
local repairHammer = "Interface\\AddOns\\Menubar_Durability\\Media\\repair-hammer.tga"
local monoHammer = repairHammer:gsub("hammer%.tga$", "hammer-mono.tga")
local lightThemes = { system7 = true, macos8 = true, macosx = true }
local ochre, darkRed = "|cff775000", "|cff981f26"
local gear, alerts = { [1] = { 50, 100 }, [5] = { 100, 100 } }, {}
GetInventoryItemDurability = function(id)
    local pair = gear[id]; if pair then return pair[1], pair[2] end
end
GetInventoryAlertStatus = function(index) return alerts[index] or 0 end
for _, name in ipairs({ "Model.lua", "Identity.lua", "Fonts.lua", "Layout.lua", "Gauge.lua", "Skins.lua", "Core.lua", "UI.lua", "Settings.lua" }) do
    dofile(core .. "/src/menubar-core/" .. name)
end
dofile(root .. "/src/menubar-durability/Durability.lua")
Menubar:Start()
local widget
for _, value in pairs(Menubar.runtime) do if value.instance.type == "durability" then widget = value end end
assert(widget and not widget.failed, "Durability must load in the real host")
local passed = 0
local function check(name, run)
    local ok, reason = pcall(run)
    assert(ok, name .. ": " .. tostring(reason))
    passed = passed + 1; print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function refresh(event)
    Menubar.eventFrame.scripts.OnEvent(Menubar.eventFrame, event or "UPDATE_INVENTORY_DURABILITY")
    Menubar:Layout()
    assert(not widget.failed, tostring(widget.failed))
end

check("native events switch between average and multiple slot alerts with real host widths", function()
    equal(widget.label:GetText(), "75%")
    local summary = assert(widget.durabilitySummaryIcon)
    assert(summary:IsVisible())
    equal(summary:GetTexture(), repairHammer)
    local normalWidth = widget.width
    alerts[1], alerts[3] = 1, 2; gear[1], gear[5] = { 10, 100 }, { 0, 100 }
    refresh("UPDATE_INVENTORY_ALERTS")
    equal(widget.label:GetText(), yellow .. "Head 10%|r  " .. red .. "Chest 0%|r")
    equal(widget.label.fontFlags, "OUTLINE")
    assert(widget.width > normalWidth)
    equal(widget.text, "Durability: Head 10%, Chest 0%")
    assert(summary:IsVisible()); equal(widget.durabilitySummaryIcon, summary)
end)

check("theme rebuilds switch hammer art and warning inks on the same texture", function()
    local icon = widget.durabilitySummaryIcon
    for _, theme in ipairs({ "system7", "macos8", "macosx", "macos27", "warcraftBrown", "warcraftBlack", "warcraftRed" }) do
        assert(MenubarModel.ApplyTheme(Menubar:GetProfile(), theme))
        Menubar:GetProfile().fontSize = 17
        Menubar:GetProfile().opacity = 0.9
        Menubar:Rebuild()
        equal(Menubar.runtime[widget.id], widget)
        equal(widget.durabilitySummaryIcon, icon)
        equal(widget.label.fontSize, 17)
        local light = lightThemes[theme]
        equal(widget.label.fontFlags, light and "" or "OUTLINE")
        equal(widget.label.font, Menubar:GetProfile().font)
        equal(widget.label:GetText(), (light and ochre or yellow) .. "Head 10%|r  "
            .. (light and darkRed or red) .. "Chest 0%|r")
        local monochrome = theme == "macosx" or theme == "macos27"
        equal(icon:GetTexture(), monochrome and monoHammer or repairHammer)
        for component = 1, 3 do
            equal(icon.vertexColor[component], monochrome and Menubar:GetProfile().textColor[component] or 1)
        end
        equal(icon:GetEffectiveAlpha(), 1)
        equal(Menubar.bars.top.surface:GetAlpha(), 0.9)
    end
end)

check("real host failure rendering centers a readable error and recovers without new textures", function()
    local icon = widget.durabilitySummaryIcon
    local textures = #Stub.textures
    local label = widget.label
    local original = label.SetText
    label.SetText = function(self, text)
        if text:find("|c", 1, true) then
            self.SetText = original
            error("simulated durability text failure")
        end
        return original(self, text)
    end
    Menubar:RefreshWidget(widget.id); Menubar:Layout()
    assert(widget.failed and widget.failed:find("simulated durability text failure", 1, true))
    equal(widget.customWidth, nil)
    equal(widget.label.points[1][1], "CENTER")
    assert(not icon:IsShown())
    assert(widget.label:GetText():find("error", 1, true))
    assert(widget.width >= widget.label:GetStringWidth() + 8)
    Menubar:RefreshWidget(widget.id); Menubar:Layout()
    assert(not widget.failed)
    equal(widget.durabilitySummaryIcon, icon); equal(#Stub.textures, textures)
    assert(icon:IsVisible())
end)

check("native repair and custom threshold changes release warning layout without stale regions", function()
    alerts = {}; gear = { [1] = { 100, 100 } }
    refresh()
    equal(widget.label:GetText(), "100%")
    equal(widget.label.points[1][1], "LEFT")
    assert(widget.durabilitySummaryIcon:IsVisible())
    widget.settings.customThresholds, widget.settings.warningPercent, widget.settings.criticalPercent = true, 100, 0
    refresh("PLAYER_EQUIPMENT_CHANGED")
    assert(widget.durabilitySummaryIcon:IsVisible())
    equal(widget.label:GetText(), yellow .. "Head 100%|r")
    widget.definition.destroy(widget); widget.definition.destroy(widget)
    equal(widget.customWidth, nil)
    assert(not widget.durabilitySummaryIcon:IsShown())
end)

check("transparent bars retain text and icon alpha and use the theme foreground for contrast", function()
    alerts = {}; gear = { [1] = { 100, 100 } }
    widget.settings.customThresholds = false
    refresh()
    local summary = assert(widget.durabilitySummaryIcon)
    for theme in pairs(MenubarModel.Themes) do
        local profile = Menubar:GetProfile()
        assert(MenubarModel.ApplyTheme(profile, theme))
        profile.opacity, profile.textColor[4] = 0, 0.65
        Menubar:Rebuild()
        equal(widget.durabilitySummaryIcon, summary)
        assert(summary:IsVisible()); equal(summary:GetEffectiveAlpha(), 1)
        equal(widget.label:GetText(), "100%")
        local light = lightThemes[theme]
        equal(widget.label.fontFlags, light and "" or "OUTLINE"); equal(widget.label.font, profile.font)
        for component = 1, 3 do equal(widget.label.textColor[component], light and 0 or 1) end
        equal(summary.vertexColor[4], 0.65)
        equal(widget.label.textColor[4], 0.65)
        equal(Menubar.bars.top.surface:GetAlpha(), 0)
    end
end)

check("custom Aqua foreground tints the hammer and unknown surfaces use the chosen ink as a contrast cue", function()
    local profile = Menubar:GetProfile()
    assert(MenubarModel.ApplyTheme(profile, "macosx"))
    local ink = { 0.12, 0.20, 0.32, 0.8 }
    profile.textColor, profile.opacity = ink, 1
    Menubar:Rebuild()
    for component = 1, 4 do
        equal(widget.label.textColor[component], ink[component])
        equal(widget.durabilitySummaryIcon.vertexColor[component], ink[component])
    end
    profile.texture = "solid"
    profile.background = { 0.08, 0.10, 0.12, 1 }
    Menubar:Rebuild()
    equal(widget.label.fontFlags, "OUTLINE")
    equal(widget.label.textColor[1], 1)
    profile.texture = "MyTexture"
    Menubar:Rebuild()
    equal(widget.label.fontFlags, "")
    profile.textColor = { 0.9, 0.9, 0.9, 0.8 }
    Menubar:Rebuild()
    equal(widget.label.fontFlags, "OUTLINE")
    equal(widget.durabilitySummaryIcon.vertexColor[1], 0.9)
end)

local function settingControl(caption)
    for _, control in ipairs(Menubar.UI.window.controls) do if control.caption == caption then return control end end
    error("Missing native control: " .. caption)
end
local function settingLabel(caption)
    for _, row in ipairs(Menubar.UI.window.controls) do
        if row.Label and row.Label:GetText() == caption then return row.Label end
    end
    error("Missing setting label: " .. caption)
end
local yellowCaption, redCaption = "Custom yellow threshold (%)", "Custom red threshold (%)"
local function thresholdsEditable(expected)
    for _, caption in ipairs({ yellowCaption, redCaption }) do
        local control = settingControl(caption)
        equal(control.edit:IsEnabled(), expected)
        equal(control:GetAlpha(), 1, "native arrows own their disabled appearance")
        local r, g, b = control.edit:GetTextColor()
        local shade = expected and 1 or 0.5
        equal(r, shade); equal(g, shade); equal(b, shade)
        equal(settingLabel(caption):GetFontObject(), expected and GameFontNormal or GameFontDisable)
        if not expected then
            equal(control.up:IsEnabled(), false); equal(control.down:IsEnabled(), false)
            equal(control.edit:HasFocus(), false)
        end
    end
end
local function enterNumber(caption, value)
    local control = settingControl(caption)
    control.edit:SetText(tostring(value)); control.edit:GetScript("OnEnterPressed")(control.edit)
end
local function invokeRetained(control, value)
    control.edit:SetText(tostring(value)); control.edit:GetScript("OnEnterPressed")(control.edit)
    control.up:GetScript("OnClick")(control.up); control.down:GetScript("OnClick")(control.down)
end
local thresholdWidget

check("custom threshold numbers reject disabled input and enable immediately with native bound-aware arrows", function()
    local instance = Menubar:AddWidget("durability"); thresholdWidget = Menubar.runtime[instance.id]
    thresholdWidget.settings.customThresholds = false; Menubar:RefreshWidget(thresholdWidget.id)
    Menubar.UI:OpenWidget(thresholdWidget.id)
    equal(thresholdWidget.settings.customThresholds, false)
    equal(thresholdWidget.settings.warningPercent, 20); equal(thresholdWidget.settings.criticalPercent, 0)
    thresholdsEditable(false)
    invokeRetained(settingControl(yellowCaption), 80); invokeRetained(settingControl(redCaption), 70)
    equal(thresholdWidget.settings.warningPercent, 20); equal(thresholdWidget.settings.criticalPercent, 0)

    settingControl("Use custom warning thresholds"):Click(); thresholdsEditable(true)
    equal(thresholdWidget.settings.customThresholds, true)
    local yellow, red = settingControl(yellowCaption), settingControl(redCaption)
    equal(yellow.up:IsEnabled(), true); equal(yellow.down:IsEnabled(), true)
    equal(red.up:IsEnabled(), true); equal(red.down:IsEnabled(), false)
    yellow.up:Click(); equal(thresholdWidget.settings.warningPercent, 21)
    settingControl(yellowCaption).down:Click(); equal(thresholdWidget.settings.warningPercent, 20)
    enterNumber(yellowCaption, 100)
    yellow = settingControl(yellowCaption)
    equal(yellow.up:IsEnabled(), false); equal(yellow.down:IsEnabled(), true)
    enterNumber(redCaption, 100)
    red = settingControl(redCaption)
    equal(red.up:IsEnabled(), false); equal(red.down:IsEnabled(), true)
    enterNumber(redCaption, 0)
    red = settingControl(redCaption)
    equal(red.up:IsEnabled(), true); equal(red.down:IsEnabled(), false)
    enterNumber(yellowCaption, 42); enterNumber(redCaption, 9)

    yellow = settingControl(yellowCaption)
    local oldEnter, oldUp, oldDown = yellow.edit:GetScript("OnEnterPressed"), yellow.up:GetScript("OnClick"), yellow.down:GetScript("OnClick")
    yellow.edit:SetFocus(); equal(yellow.edit:HasFocus(), true)
    settingControl("Use custom warning thresholds"):Click(); thresholdsEditable(false)
    yellow.edit:SetText("99"); oldEnter(yellow.edit); oldUp(yellow.up); oldDown(yellow.down)
    invokeRetained(settingControl(yellowCaption), 80); invokeRetained(settingControl(redCaption), 70)
    equal(thresholdWidget.settings.customThresholds, false)
    equal(thresholdWidget.settings.warningPercent, 42); equal(thresholdWidget.settings.criticalPercent, 9)
    settingControl("Use custom warning thresholds"):Click(); thresholdsEditable(true)
    equal(settingControl(yellowCaption).edit:GetText(), "42"); equal(settingControl(redCaption).edit:GetText(), "9")
end)

check("threshold enablement is per-instance and pooled Appearance numbers shed disabled styling and stale callbacks", function()
    local instance = Menubar:AddWidget("durability"); local second = Menubar.runtime[instance.id]
    second.settings.customThresholds = false; Menubar:RefreshWidget(second.id)
    Menubar.UI:OpenWidget(second.id); thresholdsEditable(false)
    equal(second.settings.warningPercent, 20); equal(second.settings.criticalPercent, 0)
    equal(thresholdWidget.settings.customThresholds, true)
    settingControl("Use custom warning thresholds"):Click(); enterNumber(yellowCaption, 22)
    equal(second.settings.warningPercent, 22); equal(thresholdWidget.settings.warningPercent, 42)
    Menubar.UI:OpenWidget(thresholdWidget.id); thresholdsEditable(true)
    equal(settingControl(yellowCaption).edit:GetText(), "42"); equal(settingControl(redCaption).edit:GetText(), "9")
    Menubar.UI:OpenWidget(second.id); settingControl("Use custom warning thresholds"):Click(); thresholdsEditable(false)
    local yellow, red = settingControl(yellowCaption), settingControl(redCaption)
    local oldEnter, oldUp, oldDown = yellow.edit:GetScript("OnEnterPressed"), yellow.up:GetScript("OnClick"), yellow.down:GetScript("OnClick")
    local profile = Menubar:GetProfile()
    local height, padding, fontSize = profile.height, profile.padding, profile.fontSize
    Menubar.UI:OpenSettings()
    local appearanceHeight = settingControl("Height (UI units)")
    assert(appearanceHeight == yellow or appearanceHeight == red, "The test must exercise a reused number control")
    for _, caption in ipairs({ "Height (UI units)", "Edge padding", "Widget spacing", "Font size", "Top line thickness", "Bottom line thickness" }) do
        local control = settingControl(caption)
        equal(control.edit:IsEnabled(), true); equal(control:GetAlpha(), 1)
        local r, g, b = control.edit:GetTextColor(); equal(r, 1); equal(g, 1); equal(b, 1)
        equal(settingLabel(caption):GetFontObject(), GameFontNormal)
    end
    yellow.edit:SetText("88"); oldEnter(yellow.edit); oldUp(yellow.up); oldDown(yellow.down)
    equal(profile.height, height); equal(profile.padding, padding); equal(profile.fontSize, fontSize)
    equal(second.settings.warningPercent, 22); equal(second.settings.criticalPercent, 0)
    equal(second.settings.customThresholds, false); equal(thresholdWidget.settings.customThresholds, true)
    equal(thresholdWidget.settings.warningPercent, 42); equal(thresholdWidget.settings.criticalPercent, 9)
    Menubar.UI:OpenWidget(second.id); thresholdsEditable(false)
    equal(settingControl(yellowCaption).edit:GetText(), "22")
end)

print(passed .. " Durability host integration tests passed")
