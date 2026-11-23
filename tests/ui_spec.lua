local root = REPO_ROOT or "."
local Stub = dofile(root .. "/tests/wow_stub.lua")
Stub.Install()
for _, file in ipairs({ "Model.lua", "Identity.lua", "Fonts.lua", "Layout.lua", "Gauge.lua", "Skins.lua", "Core.lua", "UI.lua", "Settings.lua" }) do
    dofile(root .. "/src/menubar-core/" .. file)
end
if MENUBAR_TIME_ROOT then dofile(MENUBAR_TIME_ROOT .. "/src/menubar-time/Time.lua") end
if not Menubar.types.time then
    Menubar:RegisterWidgetType({ id = "time", name = "Time", defaults = { zone = "local" },
        defaultPlacement = { bar = "top", alignment = "right" },
        update = function(widget) widget:SetText(widget.settings.zone == "utc" and "03:34" or "12:34") end,
        settings = { { key = "zone", label = "Time zone", type = "select", options = {
            { value = "local", label = "Player" }, { value = "utc", label = "UTC" },
        } } },
    })
end
local passed = 0
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function character() return MenubarModel.GetCharacter(Menubar.db, Menubar.characterKey) end
local function control(caption, kind)
    for _, value in ipairs(Menubar.UI.window.controls) do
        if value.caption == caption and (not kind or value.menubarControl == kind) then return value end
    end
    error("Missing control: " .. caption)
end
local function click(value, button)
    if value.intrinsic == "DropdownButton" then value:OpenMenu()
    else value:Click(button or "LeftButton") end
end
local function pick(caption, option)
    click(control(caption, "select"))
    Stub.MenuItem(Stub.menus[#Stub.menus], option).callback()
end
local function enter(caption, value)
    local field = control(caption)
    local edit = field.menubarControl == "number" and field.edit or field
    edit:SetText(value); edit.scripts.OnEnterPressed(edit)
end
-- These UI checks deliberately exercise the classic theme; factory preferences
-- are verified independently through a fresh startup with every provider.
local classicProfile = MenubarModel.DeepCopy(MenubarModel.DefaultProfile)
assert(MenubarModel.ApplyTheme(classicProfile, "system7")); classicProfile.opacity = 1
MenubarDB = { profiles = { Default = classicProfile } }
Menubar:Start()

check("host starts with a full-width top bar, minute clock and rounded black corners", function()
    assert(Menubar.bars.top:IsShown() and not Menubar.bars.bottom:IsShown())
    equal(Menubar.bars.top:GetWidth(), UIParent:GetWidth())
    equal(Menubar.runtime.w1.text, "12:34")
    equal(#Menubar.bars.top.corners, 16)
    equal(Menubar.bars.top.corners[1].color[1], 0)
    assert(Menubar.bars.top.corners[1]:IsShown())
end)

check("declared left actions keep Shift-left menus and right-click settings", function()
    local shift, previousShift = false, IsShiftKeyDown
    IsShiftKeyDown = function() return shift end
    local widget = Menubar.runtime.w1
    widget.frame.scripts.OnEnter(widget.frame)
    equal(GameTooltip:GetOwner(), widget.frame)
    local hint = "Shift-left-click: menu   Right-click: settings"
    if widget.definition.click then hint = "Left-click: " .. widget.definition.clickHint .. "   " .. hint end
    equal(GameTooltip.lines[#GameTooltip.lines][1], hint)
    widget.frame.scripts.OnLeave(widget.frame)
    local menus = #Stub.menus
    click(widget.frame)
    equal(#Stub.menus, menus + (widget.definition.click and 1 or 0)); equal(Menubar.UI.widgetID, nil)
    menus = #Stub.menus
    click(widget.frame, "MiddleButton"); equal(#Stub.menus, menus)
    shift = true
    click(widget.frame)
    equal(#Stub.menus, menus + 1)
    assert(Stub.MenuItem(Stub.menus[#Stub.menus], "Move earlier"))
    shift = false
    click(widget.frame, "RightButton")
    equal(Menubar.UI.widgetID, "w1")
    equal(Menubar.UI.window.template, nil)
    equal(Menubar.UI.window:GetParent(), SettingsPanel.Container.SettingsCanvas)
    equal(control("Time zone").template, "WowStyle1DropdownTemplate")
    assert(Menubar.UI.window:IsShown())
    shift = true
    click(widget.frame, "RightButton")
    equal(Menubar.UI.widgetID, "w1"); equal(#Stub.menus, menus + 1)
    IsShiftKeyDown = previousShift
end)

check("core is pinned at the top and cannot be removed, duplicated or reordered", function()
    Menubar.UI:OpenSettings()
    local window = Menubar.UI.window
    assert(window.sidebarRows[1].core)
    assert(not window.remove:IsEnabled() and not window.up:IsEnabled() and not window.down:IsEnabled())
    click(window.remove); click(window.up); click(window.down)
    equal(#character().widgets, 1)
    for _, value in ipairs(window.controls) do assert(value.caption ~= "Duplicate this widget") end
end)

check("independent clocks configure and duplicate through the sidebar page", function()
    Menubar.UI:OpenWidget("w1")
    pick("Time zone", "UTC")
    equal(Menubar.runtime.w1.text, "03:34")
    click(control("Duplicate this widget"))
    equal(#character().widgets, 2)
    equal(Menubar.UI.widgetID, "w2")
    pick("Time zone", "Player")
    equal(character().widgets[1].settings.zone, "utc")
    equal(character().widgets[2].settings.zone, "local")
    assert(character().widgets[1].settings ~= character().widgets[2].settings)
end)

check("sidebar plus, minus and arrows manage widgets while preserving the core entry", function()
    local window = Menubar.UI.window
    click(window.add)
    Stub.MenuItem(Stub.menus[#Stub.menus], "Time").callback()
    equal(Menubar.UI.widgetID, "w3")
    equal(#character().widgets, 3)
    assert(window.up:IsEnabled() and not window.down:IsEnabled())
    click(window.up)
    equal(character().widgets[2].id, "w3")
    assert(window.sidebarRows[1].core)
    equal(Menubar.runtime.w3.instance.order, 2)
    click(window.remove)
    equal(#character().widgets, 2)
    equal(Menubar.UI.widgetID, nil)
    assert(not window.remove:IsEnabled())
end)

check("ordinary core clicks open menus on top, bottom or both without wasting hidden-menu space", function()
    local previousShift = IsShiftKeyDown
    IsShiftKeyDown = function() return false end
    local function coreMenu(barName)
        local bar = Menubar.bars[barName]
        assert(bar:IsShown() and bar.menu:IsShown())
        local before = #Stub.menus
        click(bar.menu)
        equal(#Stub.menus, before + 1)
        local menu = Stub.menus[#Stub.menus]
        equal(menu.title, "Menubar")
        assert(Stub.MenuItem(menu, "Settings"))
        assert(Stub.MenuItem(menu, "Add widget")); assert(Stub.MenuItem(menu, "Show bars"))
    end
    coreMenu("top")
    click(Menubar.bars.top)
    equal(Stub.menus[#Stub.menus].title, "Menubar")
    click(Menubar.bars.top.menu, "RightButton")
    equal(Menubar.UI.widgetID, nil)
    pick("Bars", "Both")
    pick("Core menu on", "Bottom bar")
    assert(not Menubar.bars.top.menu:IsShown() and Menubar.bars.bottom.menu:IsShown())
    coreMenu("bottom")
    MenubarModel.MoveWidget(Menubar.db, Menubar.characterKey, "w1", "top", "left")
    Menubar:Rebuild()
    equal(Menubar.runtime.w1.frame.points[1][4], Menubar:GetProfile().padding)
    pick("Core menu on", "Top bar")
    assert(Menubar.bars.top.menu:IsShown() and not Menubar.bars.bottom.menu:IsShown())
    coreMenu("top")
    pick("Core menu on", "Both bars")
    assert(Menubar.bars.top.menu:IsShown() and Menubar.bars.bottom.menu:IsShown())
    coreMenu("top"); coreMenu("bottom")
    pick("Bars", "Bottom")
    assert(not Menubar.bars.top:IsShown() and Menubar.bars.bottom.menu:IsShown())
    coreMenu("bottom")
    equal(#character().widgets, 2)
    IsShiftKeyDown = previousShift
end)

check("integer steppers enforce limits and typed numbers remain validated", function()
    equal(control("Font size").up.template, "UIPanelSquareButton")
    equal(control("Font size").down.template, "UIPanelSquareButton")
    equal(control("Font size").up.icon.squareButtonDirection, "UP")
    equal(control("Font size").down.icon.squareButtonDirection, "DOWN")
    local before = Menubar:GetProfile().fontSize
    click(control("Font size").up)
    equal(Menubar:GetProfile().fontSize, before + 1)
    click(control("Font size").down)
    equal(Menubar:GetProfile().fontSize, before)
    enter("Font size", "0")
    equal(Menubar:GetProfile().fontSize, before)
    assert(Menubar.UI.window.status:GetText():find("8 to 48", 1, true))
    enter("Height (UI units)", "32")
    equal(Menubar.bars.bottom:GetHeight(), 32)
end)

check("background opacity uses a live native slider while keeping the bar and controls opaque", function()
    local original = control("Background opacity", "slider")
    equal(original.slider.template, "MinimalSliderTemplate")
    Stub.DragSlider(original.slider, 37)
    equal(Menubar:GetProfile().opacity, 0.37)
    equal(Menubar.bars.bottom:GetAlpha(), 1)
    equal(Menubar.bars.bottom.surface:GetAlpha(), 0.37)
    equal(Menubar.bars.bottom.menu:GetEffectiveAlpha(), 1)
    equal(control("Background opacity"), original)
end)

check("native colour picker previews RGB and alpha and cancellation restores the original", function()
    local original = MenubarModel.DeepCopy(Menubar:GetProfile().background)
    click(control("Background colour", "color"))
    assert(ColorPickerFrame:IsShown())
    ColorPickerFrame:SetColorRGB(0.1, 0.2, 0.3)
    ColorPickerFrame:SetColorAlpha(0.4)
    equal(Menubar:GetProfile().background[1], 0.1)
    equal(Menubar:GetProfile().background[4], 0.4)
    ColorPickerFrame:Cancel()
    for i = 1, 4 do equal(Menubar:GetProfile().background[i], original[i]) end
end)

check("claiming a visible foreign colour picker initializes our alpha without setup writes", function()
    local profile = Menubar:GetProfile()
    profile.background = { 0.18, 0.27, 0.36, 0.81 }
    Menubar.UI:OpenSettings()
    local original, nativeRebuild, rebuilds = profile.background, Menubar.Rebuild, 0
    ColorPickerFrame:SetupColorPickerAndShow({ r = 1, g = 1, b = 1,
        hasOpacity = true, opacity = 0.23, extraInfo = "foreign session" })
    equal(ColorPickerFrame:GetColorAlpha(), 0.23)
    Menubar.Rebuild = function(self, ...)
        rebuilds = rebuilds + 1; return nativeRebuild(self, ...)
    end
    click(control("Background colour", "color"))
    Menubar.Rebuild = nativeRebuild
    equal(rebuilds, 0, "Native setup callbacks must not rebuild or persist preview values")
    equal(profile.background, original)
    equal(ColorPickerFrame:GetColorAlpha(), 0.81)
    assert(ColorPickerFrame:GetExtraInfo() ~= "foreign session")
    ColorPickerFrame:SetColorRGB(0.6, 0.7, 0.8)
    equal(profile.background[1], 0.6); equal(profile.background[4], 0.81)
    ColorPickerFrame:Cancel()
    for index = 1, 4 do equal(profile.background[index], original[index]) end
end)

check("reopening a colour picker cancels to the latest accepted colour", function()
    click(control("Background colour", "color"))
    ColorPickerFrame:SetColorRGB(0.23, 0.34, 0.45)
    ColorPickerFrame:SetColorAlpha(0.56)
    ColorPickerFrame:Hide() -- The native Okay button applies callbacks before hiding.
    equal(Menubar.UI.colorOwner, nil)
    click(control("Background colour", "color"))
    equal(ColorPickerFrame.info.r, 0.23)
    equal(ColorPickerFrame.info.opacity, 0.56)
    ColorPickerFrame:SetColorRGB(0.8, 0.7, 0.6)
    ColorPickerFrame:Cancel()
    equal(Menubar:GetProfile().background[1], 0.23)
    equal(Menubar:GetProfile().background[4], 0.56)
end)

check("pooled colour controls ignore callbacks from a dismissed page", function()
    click(control("Background colour", "color"))
    local stale = ColorPickerFrame.info
    Menubar.UI:OpenWidget("w1")
    assert(not ColorPickerFrame:IsShown())
    Menubar.UI:OpenSettings()
    local original = MenubarModel.DeepCopy(Menubar:GetProfile().background)
    ColorPickerFrame.red, ColorPickerFrame.alpha = 0.91, 0.12
    stale.swatchFunc(); stale.opacityFunc(); stale.cancelFunc()
    for index = 1, 4 do equal(Menubar:GetProfile().background[index], original[index]) end
end)

check("closing Menubar leaves a shared colour picker claimed by another addon open", function()
    function ColorPickerFrame:GetExtraInfo() return self.info and self.info.extraInfo end
    click(control("Background colour", "color"))
    ColorPickerFrame:SetupColorPickerAndShow({ r = 1, g = 1, b = 1, opacity = 1, extraInfo = "another addon" })
    Menubar.UI.window:Hide()
    assert(ColorPickerFrame:IsShown())
    equal(Menubar.UI.colorOwner, nil)
    ColorPickerFrame:Hide()
    Menubar.UI:OpenSettings()
end)

check("bar font and colour changes leave Blizzard settings fonts and colours intact", function()
    local profile = Menubar:GetProfile()
    profile.textColor = { 1, 1, 1, 1 }
    profile.font = "Custom\\Readable.ttf"
    profile.fontSize = 40
    Menubar:Rebuild(); Menubar.UI:OpenSettings()
    equal(Menubar.runtime.w1.label.font, profile.font)
    equal(Menubar.runtime.w1.label.fontSize, 40)
    equal(Menubar.UI.window.title.fontObject, GameFontNormalLarge)
    equal(control("Font").Label.fontObject, GameFontHighlight)
    local expected = { GameFontHighlight:GetTextColor() }
    for index = 1, 4 do equal(control("Font").Label.textColor[index], expected[index]) end
    equal(Menubar.bars.bottom.menu.Label.fontSize, 12)
end)

check("custom fonts register from form contents and use actual bold and italic files", function()
    click(control("Register custom font..."))
    control("Font name"):SetText("My custom family")
    control("Regular font file"):SetText("Custom\\Regular.ttf")
    control("Bold font file (optional)"):SetText("missing.ttf")
    click(control("Register and select font"))
    assert(Menubar.UI.window.status:GetText():find("Could not load", 1, true))
    assert(not Menubar.db.customFonts["Custom\\Regular.ttf"])
    control("Bold font file (optional)"):SetText("Custom\\Bold.ttf")
    control("Italic font file (optional)"):SetText("Custom\\Italic.ttf")
    click(control("Register and select font"))
    equal(Menubar:GetProfile().font, "Custom\\Regular.ttf")
    pick("Font style", "Bold")
    equal(Menubar.runtime.w1.label.font, "Custom\\Bold.ttf")
    equal(Menubar.runtime.w1.label.fontFlags, "")
    pick("Font style", "Italic")
    equal(Menubar.runtime.w1.label.font, "Custom\\Italic.ttf")
    local options = MenubarFonts.Options(Menubar.db.customFonts, Menubar:GetProfile().font)
    equal(options[1].group, "Built-in fonts")
    equal(options[4].group, "Built-in fonts")
    assert(#options >= 5)
end)

check("Platinum style applies matching typography and reuses shading while preserving size opacity and layout", function()
    local profile = Menubar:GetProfile()
    local oldSize = profile.fontSize
    local oldOpacity, oldHeight, oldPlacement = profile.opacity, profile.height, profile.placement
    local firstWidget, firstSettings = character().widgets[1], character().widgets[1].settings
    pick("Bar style", "Mac OS 8 (Platinum)")
    equal(profile.theme, "macos8")
    equal(profile.font, "Fonts\\FRIZQT__.TTF"); equal(profile.fontStyle, "regular"); equal(profile.fontSize, oldSize)
    equal(profile.textShadow, false)
    equal(profile.opacity, oldOpacity); equal(profile.height, oldHeight); equal(profile.placement, oldPlacement)
    equal(character().widgets[1], firstWidget); equal(character().widgets[1].settings, firstSettings)
    local bar = Menubar.bars.bottom
    equal(#bar.shadingBands, profile.height)
    local firstBand, count = bar.shadingBands[1], #bar.shadingBands
    assert(firstBand:IsShown())
    assert(firstBand.color[1] > bar.shadingBands[count].color[1])
    pick("Bar style", "Mac OS 7.6 (Harmony)")
    for _, band in ipairs(bar.shadingBands) do assert(not band:IsShown()) end
    pick("Bar style", "Mac OS 8 (Platinum)")
    equal(bar.shadingBands[1], firstBand); equal(#bar.shadingBands, count)
    equal(profile.font, "Fonts\\FRIZQT__.TTF"); equal(profile.opacity, oldOpacity)
    pick("Bar style", "Mac OS 7.6 (Harmony)")
end)

check("top and bottom rules change thickness and visibility independently", function()
    enter("Top line thickness", "0")
    enter("Bottom line thickness", "4")
    local profile, bar = Menubar:GetProfile(), Menubar.bars.bottom
    equal(profile.topLineSize, 0); equal(profile.bottomLineSize, 4)
    assert(not bar.topLine:IsShown() and bar.bottomLine:IsShown())
    equal(bar.bottomLine:GetHeight(), 4)
    enter("Top line thickness", "2")
    enter("Bottom line thickness", "0")
    equal(profile.topLineSize, 2); equal(profile.bottomLineSize, 0)
    assert(bar.topLine:IsShown() and not bar.bottomLine:IsShown())
    equal(bar.topLine:GetHeight(), 2)
end)

check("rounded corners can be disabled independently of bar placement", function()
    click(control("Rounded outer corners", "toggle"))
    assert(not Menubar:GetProfile().roundedCorners)
    for _, bar in pairs(Menubar.bars) do for _, corner in ipairs(bar.corners) do assert(not corner:IsShown()) end end
    click(control("Rounded outer corners", "toggle"))
    assert(Menubar:GetProfile().roundedCorners)
end)

check("overflow widgets retain accessible menus and settings at narrow widths", function()
    UIParent:SetWidth(80); Menubar:Layout()
    local bar = Menubar.bars.bottom
    assert(bar.overflow:IsShown() and #bar.hiddenWidgets > 0)
    local before = #Stub.menus
    click(bar.overflow)
    equal(#Stub.menus, before + 1)
    local menu = Stub.menus[#Stub.menus]
    equal(#menu.children, #bar.hiddenWidgets)
    Stub.MenuItem(menu.children[1], "Configure...").callback()
    assert(Menubar.UI.widgetID)
    click(bar.overflow, "RightButton")
    equal(Menubar.UI.widgetID, nil)
    UIParent:SetWidth(1280); Menubar:Layout()
end)

check("graphical overflow widgets have a useful provider name instead of a blank entry", function()
    Menubar:RegisterWidgetType({ id = "graphical-menu-fixture", name = "Graphical fixture", defaults = {},
        update = function(widget) widget:SetWidth(48); widget:SetText("") end })
    local instance = Menubar:AddWidget("graphical-menu-fixture", "bottom", "left")
    UIParent:SetWidth(80); Menubar:Layout()
    click(Menubar.bars.bottom.overflow)
    local item = Stub.MenuItem(Stub.menus[#Stub.menus], "Graphical fixture")
    Stub.MenuItem(item, "Configure...").callback()
    equal(Menubar.UI.widgetID, instance.id)
    UIParent:SetWidth(1280); Menubar:RemoveWidget(instance.id)
end)

check("stable widget widths avoid redundant native resizing and layout invalidation", function()
    local widget = Menubar.runtime.w1
    local nativeWidth, calls = widget.frame.SetWidth, 0
    widget.frame.SetWidth = function(frame, value) calls = calls + 1; return nativeWidth(frame, value) end
    widget:SetWidth(73)
    calls, Menubar.dirty = 0, false
    for _ = 1, 10 do widget:SetWidth(73); widget:SetText("12:34") end
    equal(calls, 0); equal(Menubar.dirty, false)
    widget.frame.SetWidth = nativeWidth
    widget.customWidth = nil; Menubar:RefreshWidget(widget.id)
end)

check("native settings controls are reused across repeated redraws", function()
    Menubar.UI:OpenSettings()
    local before = #Stub.frames
    for _ = 1, 20 do Menubar.UI:OpenSettings() end
    equal(#Stub.frames, before)
    equal(Menubar.UI.window.sidebarRows[1].Label:GetText(), "Menubar")
    Menubar.UI.window:Hide()
    equal(Menubar.UI.widgetID, nil)
end)

check("appearance copies remain independent while character widgets stay intact", function()
    Menubar.UI:OpenSettings()
    local previous, count = Menubar:GetProfile(), #character().widgets
    local previousFont = previous.font
    click(control("New profile..."))
    local dialog = assert(StaticPopup_FindVisible("MENUBAR_NEW_APPEARANCE_PROFILE"))
    dialog:GetEditBox():SetText("  Alternate  ")
    StaticPopup_OnClick(dialog, 1)
    equal(character().profile, "Alternate")
    equal(#character().widgets, count)
    local copied = Menubar:GetProfile()
    assert(copied ~= previous and copied.background ~= previous.background)
    click(control("Restore to defaults"))
    equal(copied.font, MenubarModel.DefaultProfile.font)
    equal(copied.placement, "bottom")
    equal(previous.font, previousFont)
end)

check("unavailable saved selections never expose numeric internal identifiers", function()
    Menubar.UI:ClearWindow("Unavailable choice")
    local selected = Menubar.UI:Select("Target", 1234567, {
        { value = 0, label = "Automatic" }, { value = 42, label = "Possessed or exposed choice" },
    }, function() end)
    equal(selected.Label:GetText(), "Not currently listed")
    assert(not selected.Label:GetText():find("1234567", 1, true))
    click(selected)
    equal(#Stub.menus[#Stub.menus].children, 2)
    Menubar.UI:OpenSettings()
end)

check("malformed dynamic choices are filtered while false selections and unavailable values are retained", function()
    local restricted, previous = {}, issecretvalue
    issecretvalue = function(value) return value == restricted end
    local available = { false, 123, {}, { value = false, label = "Disabled" }, { value = 1, label = {} },
        { value = math.huge, label = "Infinite" }, { value = {}, label = "Object" },
        { value = "valid", label = "Valid", group = 123 }, { value = "secret", label = restricted } }
    Menubar:RegisterWidgetType({ id = "choice-fixture", name = "Choice fixture", defaults = { target = "unlisted" },
        update = function(widget) widget:SetText("choices") end,
        settings = { { key = "target", label = "Dynamic target", type = "select", options = function()
            return available
        end } } })
    local instance = Menubar:AddWidget("choice-fixture", "bottom", "left")
    Menubar.UI:OpenWidget(instance.id)
    equal(control("Dynamic target").Label:GetText(), "Not currently listed")
    equal(instance.settings.target, "unlisted")
    click(control("Dynamic target"))
    equal(#Stub.menus[#Stub.menus].children, 2)
    Stub.MenuItem(Stub.menus[#Stub.menus], "Disabled").callback()
    equal(instance.settings.target, false)
    equal(control("Dynamic target").Label:GetText(), "Disabled")
    local dropdown = control("Dynamic target")
    click(dropdown)
    local stale = Stub.MenuItem(Stub.menus[#Stub.menus], "Valid").callback
    available = { { value = false, label = "Disabled" } }
    stale(); equal(instance.settings.target, false)
    click(dropdown)
    equal(#Stub.menus[#Stub.menus].children, 1)
    assert(Stub.MenuItem(Stub.menus[#Stub.menus], "Disabled"))
    issecretvalue = previous
    Menubar:RemoveWidget(instance.id); Menubar.UI:OpenSettings()
end)

check("corrupt numeric widget settings remain editable without silently overwriting saved values", function()
    Menubar:RegisterWidgetType({ id = "number-fixture", name = "Number fixture", defaults = { amount = 42 },
        update = function(widget) widget:SetText("number") end,
        settings = { { key = "amount", label = "Amount", type = "number", min = 10, max = 50, integer = true } } })
    local instance = Menubar:AddWidget("number-fixture", "bottom", "left")
    for _, value in ipairs({ "broken", "25", false, math.huge, -math.huge, 0 / 0 }) do
        instance.settings.amount = value
        Menubar.UI:OpenWidget(instance.id)
        equal(control("Amount").edit:GetText(), "42")
        if type(value) == "number" and value ~= value then assert(instance.settings.amount ~= instance.settings.amount)
        else equal(instance.settings.amount, value) end
    end
    click(control("Amount").up)
    equal(instance.settings.amount, 43)
    enter("Amount", "inf")
    equal(instance.settings.amount, 43)
    Menubar:RemoveWidget(instance.id); Menubar.UI:OpenSettings()
end)

check("integer commits validate the rounded value against fractional bounds", function()
    Menubar.UI:ClearWindow("Bounded integer")
    local saved = 2
    local field = Menubar.UI:Number("Integer", saved, 1.5, 5.5, function(value) saved = value end, true)
    field.edit:SetText("1.8"); field.edit.scripts.OnEnterPressed(field.edit)
    equal(saved, 2)
    field.edit:SetText("4.9"); field.edit.scripts.OnEnterPressed(field.edit)
    equal(saved, 4)
    Menubar.UI:OpenSettings()
end)

check("public presentation methods reject restricted values before formatting or native calls", function()
    local formatted, restricted, previous = false, {}, issecretvalue
    setmetatable(restricted, { __tostring = function() formatted = true; return "restricted" end })
    issecretvalue = function(value) return value == restricted end
    local widget = Menubar.runtime.w1
    local oldText, oldWidth = widget.text, widget.width
    assert(not pcall(widget.SetText, widget, restricted))
    assert(not pcall(widget.SetWidth, widget, restricted))
    equal(formatted, false); equal(widget.text, oldText); equal(widget.width, oldWidth)
    issecretvalue = previous
end)

check("provider color settings retain their existing native picker contract", function()
    Menubar:RegisterWidgetType({ id = "color-fixture", name = "Color fixture", defaultPlacement = false,
        defaults = { tint = { 0.2, 0.3, 0.4, 0.5 } },
        settings = { { key = "tint", label = "Widget tint", type = "color" } },
        update = function(widget) widget:SetText("color") end })
    local instance = Menubar:AddWidget("color-fixture")
    Menubar.UI:OpenWidget(instance.id)
    click(control("Widget tint", "color"))
    ColorPickerFrame:SetColorRGB(0.6, 0.7, 0.8)
    ColorPickerFrame:SetColorAlpha(0.9)
    equal(instance.settings.tint[1], 0.6)
    equal(instance.settings.tint[4], 0.9)
    ColorPickerFrame:Cancel()
    equal(instance.settings.tint[1], 0.2)
    equal(instance.settings.tint[4], 0.5)
    equal(Menubar.types["color-fixture"].defaults.tint[1], 0.2)
    Menubar:RemoveWidget(instance.id); Menubar.UI:OpenSettings()
end)

check("direct-action widgets retain Shift-left arrangement and right-click settings", function()
    local actions, contextMenus, providerActions, shift = 0, 0, 0, false
    local previousShift = IsShiftKeyDown
    IsShiftKeyDown = function() return shift end
    Menubar:RegisterWidgetType({ id = "direct-fixture", name = "Direct fixture", defaultPlacement = false,
        clickHint = "open Social",
        click = function(_, button) equal(button, "LeftButton"); actions = actions + 1 end,
        contextMenu = function(_, menu)
            contextMenus = contextMenus + 1
            menu:CreateButton("Provider action", function() providerActions = providerActions + 1 end)
        end,
        update = function(widget) widget:SetText("Social") end })
    local instance = Menubar:AddWidget("direct-fixture")
    local widget = Menubar.runtime[instance.id]
    widget.frame.scripts.OnEnter(widget.frame)
    local help = GameTooltip.lines[#GameTooltip.lines][1]
    assert(help:find("Left-click: open Social", 1, true))
    assert(help:find("Shift-left-click: menu", 1, true))
    local menus = #Stub.menus
    click(widget.frame)
    equal(actions, 1); equal(contextMenus, 0); equal(#Stub.menus, menus)
    shift = true
    click(widget.frame)
    equal(actions, 1); equal(contextMenus, 1); equal(#Stub.menus, menus + 1)
    assert(Stub.MenuItem(Stub.menus[#Stub.menus], "Move earlier"))
    Stub.MenuItem(Stub.menus[#Stub.menus], "Provider action").callback()
    equal(providerActions, 1)
    click(widget.frame, "RightButton")
    equal(Menubar.UI.widgetID, instance.id)
    equal(actions, 1); equal(contextMenus, 1); equal(#Stub.menus, menus + 1)
    Menubar:RemoveWidget(instance.id); Menubar.UI:OpenSettings()
    IsShiftKeyDown = previousShift
end)

check("modifier API failures cannot escape or disable a direct widget action", function()
    local actions, restricted = 0, {}
    local previousShift, previousSecret = IsShiftKeyDown, issecretvalue
    Menubar:RegisterWidgetType({ id = "modifier-fixture", name = "Modifier fixture", defaultPlacement = false,
        click = function() actions = actions + 1 end,
        update = function(widget) widget:SetText("Action") end })
    local instance = Menubar:AddWidget("modifier-fixture")
    local widget = Menubar.runtime[instance.id]
    local variants = {
        function() return false end,
        function() error("modifier is temporarily unavailable") end,
        function() return "true" end,
        function() return restricted end,
    }
    issecretvalue = function(value) return rawequal(value, restricted) end
    for _, handler in ipairs(variants) do IsShiftKeyDown = handler; click(widget.frame) end
    IsShiftKeyDown = nil; click(widget.frame)
    IsShiftKeyDown = true; click(widget.frame)
    equal(actions, 6); equal(widget.failed, nil)
    widget.frame.scripts.OnEnter(widget.frame)
    assert(GameTooltip.lines[#GameTooltip.lines][1]:find("Left-click: activate", 1, true))
    Menubar:RemoveWidget(instance.id); Menubar.UI:OpenSettings()
    IsShiftKeyDown, issecretvalue = previousShift, previousSecret
end)

check("direct-click failures restore host presentation and leave configuration reachable", function()
    local actions, resets, fail, shift = 0, 0, true, false
    local previousShift = IsShiftKeyDown
    IsShiftKeyDown = function() return shift end
    Menubar:RegisterWidgetType({ id = "direct-error-fixture", name = "Direct error", defaultPlacement = false,
        click = function()
            actions = actions + 1
            if fail then error("simulated direct action failure", 0) end
        end,
        reset = function(_, callback) equal(callback, "click"); resets = resets + 1 end,
        update = function(widget) widget:SetText("Action") end })
    local instance = Menubar:AddWidget("direct-error-fixture")
    local widget = Menubar.runtime[instance.id]
    click(widget.frame)
    equal(widget.failed, "simulated direct action failure")
    equal(widget.failedCallback, "click"); equal(resets, 1)
    assert(widget.text:find("error", 1, true)); assert(widget.label:IsShown())
    click(widget.frame); equal(actions, 1)
    shift = true
    click(widget.frame)
    assert(Stub.MenuItem(Stub.menus[#Stub.menus], "Configure..."))
    click(widget.frame, "RightButton")
    equal(Menubar.UI.widgetID, instance.id)
    fail, shift = false, false
    Menubar:RefreshWidget(instance.id)
    click(widget.frame)
    equal(widget.failed, nil); equal(actions, 2); equal(resets, 1)
    Menubar:RemoveWidget(instance.id); Menubar.UI:OpenSettings()
    IsShiftKeyDown = previousShift
end)

check("unavailable widget providers keep plain left-click quiet and expose Shift-left menus and accurate help", function()
    local shift, previousShift = false, IsShiftKeyDown
    IsShiftKeyDown = function() return shift end
    local instance = MenubarModel.AddWidget(Menubar.db, Menubar.characterKey, "missing-action-fixture")
    Menubar:Rebuild()
    local widget = Menubar.runtime[instance.id]
    local menus = #Stub.menus
    click(widget.frame)
    equal(#Stub.menus, menus)
    shift = true
    click(widget.frame)
    equal(#Stub.menus, menus + 1)
    assert(Stub.MenuItem(Stub.menus[#Stub.menus], "Configure..."))
    widget.frame.scripts.OnEnter(widget.frame)
    equal(GameTooltip.lines[#GameTooltip.lines][1], "Shift-left-click: menu   Right-click: settings")
    click(widget.frame, "RightButton")
    equal(Menubar.UI.widgetID, instance.id); equal(#Stub.menus, menus + 1)
    Menubar:RemoveWidget(instance.id); Menubar.UI:OpenSettings()
    IsShiftKeyDown = previousShift
end)

check("corrupt profile names cannot break the native appearance picker", function()
    Menubar.db = MenubarModel.Initialize({ profiles = { [1] = {}, [" "] = {} } }, Menubar.characterKey)
    Menubar:EnsureDefaults(); Menubar:Rebuild(); Menubar.UI:OpenSettings()
    equal(Menubar.db.profiles[1], nil)
    assert(Menubar.db.profiles.Default)
end)
check("native mouse glyphs retain the Shift gesture and advertise only implemented widget actions", function()
    local previous = C_Texture
    C_Texture = { GetAtlasInfo = function(name)
        assert(name == "newplayertutorial-icon-mouse-leftbutton" or name == "newplayertutorial-icon-mouse-rightbutton")
        return { width = 32, height = 32 }
    end }
    local actions = 0
    Menubar:RegisterWidgetType({ id = "glyph-fixture", name = "Glyph fixture", defaultPlacement = false,
        clickHint = "Open Social", wheelHint = "Volume",
        click = function() actions = actions + 1 end,
        mouseWheel = function() actions = actions + 1 end,
        update = function(widget) widget:SetText("glyph") end })
    local instance = Menubar:AddWidget("glyph-fixture")
    local widget = Menubar.runtime[instance.id]
    local frames, textures = #Stub.frames, #Stub.textures
    for _ = 1, 20 do widget.frame.scripts.OnEnter(widget.frame) end
    local hint = GameTooltip.lines[#GameTooltip.lines][1]
    local left = "|A:newplayertutorial-icon-mouse-leftbutton:16:16:0:0|a"
    local right = "|A:newplayertutorial-icon-mouse-rightbutton:16:16:0:0|a"
    assert(hint:find(left .. ": Open Social", 1, true))
    assert(hint:find("Shift + " .. left .. ": menu", 1, true))
    assert(hint:find(right .. ": settings", 1, true))
    assert(hint:find("Wheel: Volume", 1, true))
    assert(not hint:find("Left-click", 1, true) and not hint:find("Right-click", 1, true))
    equal(actions, 0); equal(#Stub.frames, frames); equal(#Stub.textures, textures)
    widget.failed = "temporarily unavailable"
    widget.frame.scripts.OnEnter(widget.frame)
    hint = GameTooltip.lines[#GameTooltip.lines][1]
    assert(not hint:find("Open Social", 1, true) and not hint:find("Wheel", 1, true))
    assert(hint:find("Shift + " .. left .. ": menu", 1, true))
    Menubar:RemoveWidget(instance.id); C_Texture = previous
end)

check("unavailable or restricted native glyph metadata falls back to readable mouse gestures", function()
    local previousTexture, previousSecret = C_Texture, issecretvalue
    local restricted = setmetatable({}, { __index = function() error("restricted icon metadata indexed", 0) end })
    issecretvalue = function(value) return rawequal(value, restricted) end
    Menubar:RegisterWidgetType({ id = "glyph-fallback-fixture", name = "Fallback fixture", defaultPlacement = false })
    local instance = Menubar:AddWidget("glyph-fallback-fixture")
    local widget = Menubar.runtime[instance.id]
    local variants = {
        false, restricted, {}, { GetAtlasInfo = restricted },
        { GetAtlasInfo = function() error("atlas lookup unavailable", 0) end },
        { GetAtlasInfo = function() return restricted end },
        { GetAtlasInfo = function() return true end },
        { GetAtlasInfo = function() return nil end },
        { GetAtlasInfo = function() return {} end },
        { GetAtlasInfo = function() return { width = restricted, height = 32 } end },
        { GetAtlasInfo = function() return { width = 32, height = 0 } end },
        { GetAtlasInfo = function() return { width = 0 / 0, height = 32 } end },
        { GetAtlasInfo = function() return { width = 32, height = math.huge } end },
    }
    for _, variant in ipairs(variants) do
        C_Texture = variant or nil
        widget.frame.scripts.OnEnter(widget.frame)
        equal(GameTooltip.lines[#GameTooltip.lines][1], "Shift-left-click: menu   Right-click: settings")
        equal(widget.failed, nil)
    end
    C_Texture = { GetAtlasInfo = function(name)
        if name == "newplayertutorial-icon-mouse-rightbutton" then return { width = 32, height = 32 } end
    end }
    widget.frame.scripts.OnEnter(widget.frame)
    local hint = GameTooltip.lines[#GameTooltip.lines][1]
    assert(hint:find("Shift-left-click: menu", 1, true))
    assert(hint:find("|A:newplayertutorial-icon-mouse-rightbutton:16:16:0:0|a: settings", 1, true))
    Menubar:RemoveWidget(instance.id)
    C_Texture, issecretvalue = previousTexture, previousSecret
end)

check("core and overflow hover hints preserve ordinary left-click and tooltip ownership", function()
    local previous = C_Texture
    C_Texture = { GetAtlasInfo = function() return { width = 32, height = 32 } end }
    for _, name in ipairs({ "top", "bottom" }) do
        for _, control in ipairs({ Menubar.bars[name].menu, Menubar.bars[name].overflow }) do
            control.scripts.OnEnter(control)
            equal(GameTooltip:GetOwner(), control)
            equal(GameTooltip.anchor, name == "bottom" and "ANCHOR_TOP" or "ANCHOR_BOTTOM")
            local hint = GameTooltip.lines[#GameTooltip.lines][1]
            assert(hint:find("|A:newplayertutorial-icon-mouse-leftbutton:16:16:0:0|a", 1, true))
            assert(not hint:find("Shift", 1, true))
            control.scripts.OnLeave(control); assert(not GameTooltip:IsShown())
            GameTooltip:SetOwner(UIParent); GameTooltip:Show()
            control.scripts.OnLeave(control); assert(GameTooltip:IsShown())
            GameTooltip:Hide()
        end
    end
    C_Texture = previous
end)

check("native dropdowns refresh choices and reject closed or previous menu sessions", function()
    Menubar.UI:OpenSettings(); Menubar.UI:ClearWindow("Dropdown sessions")
    local options, selected, writes = { { value = "a", label = "A" }, { value = "b", label = "B" } }, "a", 0
    local dropdown = Menubar.UI:Select("Changing choices", selected, function() return options end, function(value)
        selected, writes = value, writes + 1
    end)
    local function openChoice()
        dropdown:OpenMenu()
        return Stub.MenuItem(Stub.menus[#Stub.menus], "B").callback
    end
    local old = openChoice()
    table.remove(options, 2); old(); equal(selected, "a"); equal(writes, 0)
    options[2] = { value = "b", label = "B" }; old(); equal(writes, 0)
    local closed = openChoice(); dropdown:CloseMenu(); closed(); equal(writes, 0)
    local current = openChoice(); old(); closed(); equal(writes, 0)
    current(); equal(selected, "b"); equal(writes, 1)
    current(); equal(writes, 1)
    Menubar.UI:OpenSettings()
end)

print(passed .. " UI integration tests passed")
