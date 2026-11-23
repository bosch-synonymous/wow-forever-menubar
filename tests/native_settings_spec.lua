-- Independent native-category lifecycle checks through the actual Core TOC.
-- Native rendering/input and Settings-panel scale still require the client.
local root = REPO_ROOT or "."
local passed = 0
local function equal(actual, expected, context)
    assert(actual == expected, (context or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function loadCore()
    local namespace = {}
    for line in io.lines(root .. "/src/menubar-core/Menubar.toc") do
        local file = line:match("^%s*(.-)%s*$")
        if file:match("%.lua$") then assert(loadfile(root .. "/src/menubar-core/" .. file))("Menubar", namespace) end
    end
end
local function fixture(options)
    options = options or {}
    local Stub = dofile(root .. "/tests/wow_stub.lua"); Stub.Install()
    local f = { Stub = Stub, canvasCalls = {}, registrations = {}, addonCalls = {}, opens = {}, updates = 0,
        failCanvas = options.failCanvas, failAddon = options.failAddon, failOpen = options.failOpen }
    assert(Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory and Settings.OpenToCategory,
        "Native Settings contracts must be present in the shared UI fixture")
    local registerCanvas, registerAddon, openCategory = Settings.RegisterCanvasLayoutCategory, Settings.RegisterAddOnCategory, Settings.OpenToCategory
    Settings.RegisterCanvasLayoutCategory = function(canvas, name, ...)
        f.canvasCalls[#f.canvasCalls + 1] = { canvas = canvas, name = name }
        if f.failCanvas then error("native canvas registration unavailable", 0) end
        local category, layout = registerCanvas(canvas, name, ...)
        f.registrations[#f.registrations + 1] = { canvas = canvas, category = category, layout = layout, name = name }
        return category, layout
    end
    Settings.RegisterAddOnCategory = function(category, ...)
        f.addonCalls[#f.addonCalls + 1] = category
        if f.failAddon then error("native AddOns registration unavailable", 0) end
        return registerAddon(category, ...)
    end
    Settings.OpenToCategory = function(id, ...)
        f.opens[#f.opens + 1] = id
        if f.failOpen then error("native category opening unavailable", 0) end
        return openCategory(id, ...)
    end
    MenubarDB = nil
    loadCore()
    Menubar:RegisterWidgetType({ id = "probe", name = "Native test widget",
        defaults = { choice = "first", toggle = true, amount = 3, label = "Default", tint = { 1, 1, 1, 1 } },
        defaultPlacement = { bar = "top", alignment = "right" },
        update = function(widget)
            f.updates = f.updates + 1
            widget:SetText(widget.settings.label .. ":" .. widget.settings.choice .. ":" .. widget.settings.amount)
        end,
        settings = {
            { key = "choice", label = "Probe choice", type = "select", options = {
                { value = "first", label = "First choice" }, { value = "second", label = "Second choice" },
            } },
            { key = "toggle", label = "Probe toggle", type = "toggle" },
            { key = "amount", label = "Probe amount", type = "number", min = 0, max = 20, integer = true },
            { key = "label", label = "Probe label", type = "text" },
            { key = "tint", label = "Probe colour", type = "color" },
        },
    })
    local db, character, profile = MenubarModel.Initialize(nil, "Tester - Test Realm")
    profile.height, profile.fontSize, profile.opacity = 31, 15, 0.61
    db.futureField = { untouched = true }
    local instance = MenubarModel.AddWidget(db, "Tester - Test Realm", "probe",
        { choice = "second", toggle = false, amount = 7, label = "Saved", tint = { 0.1, 0.2, 0.3, 0.4 }, futureField = 91 })
    MenubarDB, f.db, f.character, f.profile, f.instance = db, db, character, profile, instance
    f.savedSettings, f.marker = instance.settings, db.futureField
    f.host = Menubar
    f.host.eventFrame.scripts.OnEvent(f.host.eventFrame, "PLAYER_LOGIN")
    assert(f.host.ready and f.host.runtime[instance.id], "Native settings must not prevent the bar from starting")
    f.canvas = f.host.UI.window
    function f:control(caption)
        for _, control in ipairs(self.host.UI.window.controls or {}) do if control.caption == caption then return control end end
        error("Missing native settings control: " .. caption, 0)
    end
    function f:widget(id) return assert(self.host.runtime[id or self.instance.id]) end
    function f:openWidget(id) self.host.UI:OpenWidget(id or self.instance.id); self.canvas = self.host.UI.window end
    function f:openCore() self.host.UI:OpenSettings(); self.canvas = self.host.UI.window end
    function f:choice(caption, label)
        local dropdown = self:control(caption)
        assert(type(dropdown.OpenMenu) == "function", "Select controls must use the native dropdown API")
        dropdown:OpenMenu()
        return assert(self.Stub.MenuItem(self.Stub.menus[#self.Stub.menus], label), "Missing dropdown choice: " .. label)
    end
    function f:enter(caption, value)
        local control = self:control(caption); local edit = control.edit or control
        edit:SetText(value); assert(edit.scripts.OnEnterPressed)(edit)
    end
    function f:categoryID() return assert(self.registrations[1]).category:GetID() end
    return f
end

check("login registers one lazy native AddOns category and creates no independent dialog", function()
    local f = fixture(); equal(#f.registrations, 1); equal(#f.addonCalls, 1); equal(#f.opens, 0)
    equal(f.registrations[1].name, "Menubar"); equal(f.addonCalls[1], f.registrations[1].category)
    equal(f.canvas, f.registrations[1].canvas); equal(f.canvas:IsShown(), false)
    assert(f.canvas.template ~= "DefaultPanelTemplate", "The native canvas must not carry another window frame")
    equal(f.canvas.close, nil); equal(f.canvas:GetScript("OnDragStart"), nil)
    equal(#(f.canvas.controls or {}), 0)
    for _, name in ipairs(UISpecialFrames) do assert(name ~= f.canvas:GetName(), "The canvas must not register an independent Escape window") end
    f.host:Start(); f.host.eventFrame.scripts.OnEvent(f.host.eventFrame, "PLAYER_LOGIN"); f.host:Rebuild()
    equal(#f.registrations, 1); equal(#f.addonCalls, 1); equal(#f.opens, 0)
end)

check("widget and core right-clicks and slash commands open the same category with the right page", function()
    local f = fixture(); local id = f:categoryID()
    f:widget().frame:Click("RightButton")
    equal(f.opens[#f.opens], id); equal(f.host.UI.widgetID, f.instance.id); assert(f.canvas:IsVisible())
    equal(f.canvas:GetParent(), SettingsPanel.Container.SettingsCanvas)
    equal(f:control("Probe amount").edit:GetText(), "7")
    f.host.bars.top.menu:Click("RightButton")
    equal(f.opens[#f.opens], id); equal(f.host.UI.widgetID, nil); assert(f:control("Font size"))
    f:openWidget(); SlashCmdList.MENUBAR("")
    equal(f.opens[#f.opens], id); equal(f.host.UI.widgetID, nil)
    equal(#f.registrations, 1); equal(#f.addonCalls, 1)
end)

check("hidden native refresh never opens Settings and external selection renders current model values", function()
    local f = fixture(); local canvas = f.canvas
    assert(type(canvas.OnRefresh) == "function", "The canvas exposes the native refresh method")
    canvas:OnRefresh(); equal(#f.opens, 0); equal(canvas:IsShown(), false); equal(#(canvas.controls or {}), 0)
    f:openCore(); canvas:Hide()
    f.profile.fontSize = 22
    local opens = #f.opens
    canvas:OnRefresh(); equal(#f.opens, opens); equal(canvas:IsShown(), false)
    Settings.OpenToCategory(f:categoryID())
    equal(#f.opens, opens + 1); equal(f:control("Font size").edit:GetText(), "22")
    canvas:OnRefresh(); equal(#f.opens, opens + 1); equal(#f.registrations, 1)
end)

check("native canvas edits apply immediately while preserving existing data and object identity", function()
    local f = fixture(); f:openWidget(); local updates = f.updates
    f:choice("Probe choice", "First choice").callback()
    equal(f.instance.settings.choice, "first"); assert(f:widget().text:find(":first:", 1, true)); assert(f.updates > updates)
    f:control("Probe toggle"):Click(); equal(f.instance.settings.toggle, true)
    f:control("Probe amount").up:Click(); equal(f.instance.settings.amount, 8)
    f:enter("Probe label", "Edited"); equal(f.instance.settings.label, "Edited")
    f:openCore(); f:enter("Font size", "18")
    equal(f.profile.fontSize, 18); equal(f:widget().label.fontSize, 18)
    equal(MenubarDB, f.db); equal(f.host.db, f.db); equal(f.db.futureField, f.marker)
    equal(f.instance.settings, f.savedSettings); equal(f.instance.settings.futureField, 91)
    equal(f.profile.height, 31); equal(f.profile.opacity, 0.61)
    equal(#f.character.widgets, 1)
end)

check("shared settings captions and edit padding remain consistent across pooled pages", function()
    local f = fixture()
    local function controlsFit()
        equal(f.canvas.status:GetText(), "", "no generic save or Enter footer")
        for _, control in ipairs(f.canvas.controls) do
            if control.menubarControl == "toggle" then
                equal(control.Text.justifyH, "LEFT", "checkbox caption alignment")
                equal(control.Text.justifyV, "MIDDLE", "checkbox caption vertical alignment")
            elseif control.menubarControl == "number" or control.menubarControl == "text" then
                local edit = control.edit or control
                local insets = assert(edit.textInsets, "edit text needs its own internal padding")
                assert(insets[1] > 0 and insets[2] >= 8, "text must clear the native input-box caps")
            end
        end
    end
    f:openCore(); controlsFit()
    f:openWidget(); controlsFit()
    -- Rebinding a pooled control must reset any stale presentation state.
    f:control("Probe toggle").Text:SetJustifyH("CENTER")
    f:control("Probe amount").edit:SetTextInsets(0, 0, 0, 0)
    f.host.UI:Redraw(); controlsFit()
    f:enter("Probe amount", "invalid")
    assert(f.canvas.status:GetText():find("0 to 20", 1, true), "validation feedback must remain available")
    f:openCore(); controlsFit()
    f.host.UI:OpenFontEditor(); controlsFit()
end)

check("providers without custom fields retain placement and management without an empty options heading", function()
    local f = fixture()
    for index = 1, 2 do
        local definition = { id = "empty-options-" .. index, name = "Mail", defaults = {}, defaultPlacement = false,
            update = function(widget) widget:SetText("Mail") end }
        if index == 2 then definition.settings = {} end
        f.host:RegisterWidgetType(definition)
        local instance = f.host:AddWidget(definition.id)
        f:openWidget(instance.id)
        local sections = {}
        for _, control in ipairs(f.canvas.controls) do
            if control.menubarKind == "section" then sections[control.Label:GetText()] = true end
        end
        equal(sections["Mail options"], nil)
        assert(sections.Placement and sections["Manage widget"], "common settings sections remain")
        assert(f:control("Enabled") and f:control("Alignment"))
        assert(f:control("Duplicate this widget") and f:control("Reset this widget's settings"))
        equal(f.canvas.status:GetText(), "")
    end
end)

check("category dismissal invalidates pooled inputs and native dropdown callbacks before control reuse", function()
    local f = fixture(); f:openWidget()
    local toggle, amount, edit = f:control("Probe toggle"), f:control("Probe amount"), f:control("Probe label")
    local staleToggle, staleAmount, staleEdit = toggle.scripts.OnClick, amount.up.scripts.OnClick, edit.scripts.OnEnterPressed
    local staleChoice = f:choice("Probe choice", "First choice").callback
    f.canvas:Hide()
    edit:SetText("Stale"); toggle:SetChecked(true)
    staleEdit(edit); staleAmount(amount.up); staleToggle(toggle); staleChoice()
    equal(f.instance.settings.label, "Saved"); equal(f.instance.settings.amount, 7)
    equal(f.instance.settings.toggle, false); equal(f.instance.settings.choice, "second"); equal(f.canvas:IsShown(), false)
    local other = f.host:AddWidget("probe"); f:openWidget(other.id)
    edit:SetText("Wrong instance"); toggle:SetChecked(true)
    staleEdit(edit); staleAmount(amount.up); staleToggle(toggle); staleChoice()
    equal(other.settings.label, "Default"); equal(other.settings.amount, 3)
    equal(f.instance.settings.label, "Saved"); equal(f.instance.settings.amount, 7)
    equal(f.instance.settings.toggle, false); equal(f.instance.settings.choice, "second")
end)

check("category hide closes only its owned colour picker and popup sessions", function()
    local f = fixture(); f:openCore(); f:control("Background colour"):Click()
    assert(ColorPickerFrame:IsShown()); local stale = ColorPickerFrame.info
    local red = f.profile.background[1]
    f.host.UI:WidgetMenu(f:widget().frame, f.instance)
    assert(f.host.UI.barMenuSession and f.host.UI.barMenuSession.root:IsShown())
    local popup = f.host.UI.barMenuSession.root
    f.canvas:Hide(); equal(ColorPickerFrame:IsShown(), false); equal(popup:IsShown(), false)
    ColorPickerFrame.red = 0.91; stale.swatchFunc(); stale.cancelFunc(stale)
    equal(f.profile.background[1], red)
    f:openCore(); f:control("Background colour"):Click()
    function ColorPickerFrame:GetExtraInfo() return self.info and self.info.extraInfo end
    ColorPickerFrame:SetupColorPickerAndShow({ r = 1, g = 1, b = 1, opacity = 1, extraInfo = "another addon" })
    f.canvas:Hide(); equal(ColorPickerFrame:IsShown(), true, "Another addon's shared picker remains owned by that addon")
end)

check("closing the native Options ancestor dismisses controls without reopening or applying queued input", function()
    local f = fixture(); f:openWidget()
    local toggle = f:control("Probe toggle"); local staleToggle = toggle.scripts.OnClick
    local staleDuplicate = f:control("Duplicate this widget").scripts.OnClick
    f:control("Probe colour"):Click(); assert(ColorPickerFrame:IsShown())
    local staleColour = ColorPickerFrame.info.swatchFunc
    local dropdown = f:control("Probe choice"); dropdown:OpenMenu(); assert(dropdown:IsMenuOpen())
    local opens = #f.opens
    SettingsPanel:Hide()
    equal(f.canvas:IsVisible(), false); equal(ColorPickerFrame:IsShown(), false); equal(dropdown:IsMenuOpen(), false)
    toggle:SetChecked(true); staleToggle(toggle); staleDuplicate()
    ColorPickerFrame.red = 0.93; staleColour()
    equal(f.instance.settings.toggle, false); equal(#f.character.widgets, 1); equal(f.instance.settings.tint[1], 0.1)
    equal(#f.opens, opens); equal(SettingsPanel:IsShown(), false)
    assert(f:widget():OpenChoiceMenu("choice", "Choose probe"))
    assert(f.Stub.MenuItem(f.Stub.menus[#f.Stub.menus], "First choice")).callback()
    equal(f.instance.settings.choice, "first"); assert(f:widget().text:find(":first:", 1, true))
    equal(#f.opens, opens); equal(SettingsPanel:IsShown(), false); equal(f.canvas:IsVisible(), false)
    f:openWidget(); assert(f.canvas:IsVisible()); equal(f.host.UI.widgetID, f.instance.id)
end)

check("independent duplicates and native sidebar add remove reorder remain usable with core pinned", function()
    local f = fixture(); f:openWidget(); f:control("Duplicate this widget"):Click()
    local copyID = f.host.UI.widgetID; assert(copyID ~= f.instance.id)
    local copy = MenubarModel.GetWidget(f.db, f.host.characterKey, copyID)
    assert(copy.settings ~= f.instance.settings)
    f:enter("Probe label", "Copy"); equal(copy.settings.label, "Copy"); equal(f.instance.settings.label, "Saved")
    local canvas = f.canvas
    assert(canvas.sidebarRows[1].core); assert(canvas.up:IsEnabled()); canvas.up:Click()
    equal(f.character.widgets[1].id, copyID); assert(canvas.sidebarRows[1].core)
    canvas.add:Click(); assert(f.Stub.MenuItem(f.Stub.menus[#f.Stub.menus], "Native test widget")).callback()
    equal(#f.character.widgets, 3); local added = f.host.UI.widgetID
    assert(added ~= copyID and added ~= f.instance.id); canvas.remove:Click(); equal(#f.character.widgets, 2)
    f:openCore(); equal(canvas.remove:IsEnabled(), false); equal(canvas.up:IsEnabled(), false); equal(canvas.down:IsEnabled(), false)
    canvas.remove:Click(); canvas.up:Click(); canvas.down:Click(); equal(#f.character.widgets, 2)
end)

check("settings add-menu callbacks cannot add widgets after category dismissal", function()
    local f = fixture(); f:openCore(); f.canvas.add:Click()
    local description = f.Stub.menus[#f.Stub.menus]
    local stale = assert(f.Stub.MenuItem(description, "Native test widget")).callback
    local popup = assert(description.menuFrame); assert(popup:IsShown())
    local widgets, opens = #f.character.widgets, #f.opens
    f.canvas:Hide(); equal(popup:IsShown(), false); stale()
    equal(#f.character.widgets, widgets); equal(#f.opens, opens); equal(f.canvas:IsShown(), false)
    f:openCore(); f.canvas.add:Click()
    MenuUtil.CreateContextMenu(UIParent, function(_, menu) menu:CreateButton("Another addon's action", function() end) end)
    local foreign = assert(f.Stub.menus[#f.Stub.menus].menuFrame)
    f.canvas:Hide(); equal(foreign:IsShown(), true, "Dismissal must not close a replacement menu owned elsewhere")
end)

check("provider option resolvers refresh before native menu opening and before committing a choice", function()
    local f = fixture()
    local all = { { value = "first", label = "First choice" }, { value = "second", label = "Second choice" } }
    local onlySecond = { { value = "second", label = "Second choice" } }
    local available, reads = all, 0
    f.host.types.probe.settings[1].options = function(settings)
        equal(settings, f.instance.settings); reads = reads + 1; return available
    end
    f:openWidget(); local renderedReads = reads; available = onlySecond
    local dropdown = f:control("Probe choice"); dropdown:OpenMenu()
    equal(pcall(f.Stub.MenuItem, f.Stub.menus[#f.Stub.menus], "First choice"), false)
    assert(reads > renderedReads); equal(f.instance.settings.choice, "second")
    dropdown:CloseMenu(); available = all
    local stale = f:choice("Probe choice", "First choice").callback
    available = onlySecond; local openedReads = reads; stale()
    assert(reads > openedReads); equal(f.instance.settings.choice, "second")
    dropdown = f:control("Probe choice"); dropdown:CloseMenu(); dropdown:OpenMenu()
    equal(pcall(f.Stub.MenuItem, f.Stub.menus[#f.Stub.menus], "First choice"), false)
    equal(f.instance.settings.choice, "second")
end)

check("same-page redraw and native viewport resize preserve scroll while page navigation starts at the top", function()
    local f = fixture(); f:openCore(); local canvas = f.canvas
    canvas.scroll:SetVerticalScroll(200)
    f:control("Rounded outer corners"):Click(); equal(canvas.scroll:GetVerticalScroll(), 200)
    f:control("Font size").up:Click(); equal(canvas.scroll:GetVerticalScroll(), 200)
    local opens = #f.opens
    SettingsPanel.Container:SetSize(820, 650)
    canvas:GetScript("OnSizeChanged")(canvas, canvas:GetWidth(), canvas:GetHeight())
    equal(canvas.scroll:GetVerticalScroll(), 200); equal(#f.opens, opens)
    f:openWidget(); equal(canvas.scroll:GetVerticalScroll(), 0)
    f:openCore(); equal(canvas.scroll:GetVerticalScroll(), 0)
end)

check("sidebar and footer callbacks cannot act after dismissal or after their selected instance changes", function()
    local f = fixture(); local second, third = f.host:AddWidget("probe"), f.host:AddWidget("probe")
    f:openWidget(second.id); local canvas = f.canvas
    local handlers = {
        { canvas.add, canvas.add:GetScript("OnClick") }, { canvas.remove, canvas.remove:GetScript("OnClick") },
        { canvas.up, canvas.up:GetScript("OnClick") }, { canvas.down, canvas.down:GetScript("OnClick") },
        { canvas.sidebarRows[2], canvas.sidebarRows[2]:GetScript("OnClick") },
    }
    local function unchanged()
        equal(#f.character.widgets, 3)
        equal(f.character.widgets[1].id, f.instance.id); equal(f.character.widgets[2].id, second.id); equal(f.character.widgets[3].id, third.id)
    end
    local opens, menus = #f.opens, #f.Stub.menus
    canvas:Hide()
    for _, value in ipairs(handlers) do assert(value[2])(value[1]) end
    unchanged(); equal(#f.opens, opens); equal(#f.Stub.menus, menus); equal(canvas:IsShown(), false)
    f:openWidget(third.id); opens, menus = #f.opens, #f.Stub.menus
    for _, value in ipairs(handlers) do value[2](value[1]) end
    unchanged(); equal(f.host.UI.widgetID, third.id); equal(#f.opens, opens); equal(#f.Stub.menus, menus)
    f.host:Rebuild(); canvas.remove:Click()
    equal(#f.character.widgets, 2); equal(MenubarModel.GetWidget(f.db, f.host.characterKey, third.id), nil)
end)

check("responsive native canvas content remains bounded and reuses frames over rebuilds and navigation", function()
    local f = fixture(); f:openCore(); f:openWidget(); f:openCore()
    local canvas = f.canvas
    local function resize(width, height)
        -- Settings owns the canvas anchors. Model a native viewport resize,
        -- then deliver the resulting canvas size notification.
        SettingsPanel.Container:SetSize(width, height)
        local resized = canvas:GetScript("OnSizeChanged"); assert(resized, "Canvas resize must update its layout")
        resized(canvas, canvas:GetWidth(), canvas:GetHeight())
    end
    resize(740, 560); local narrow = canvas.content:GetWidth()
    assert(narrow > 0 and narrow < 740); assert(canvas.sideContent:GetWidth() > 0)
    resize(1080, 720); local wide = canvas.content:GetWidth(); assert(wide > narrow and wide < 1080)
    local frames, textures = #f.Stub.frames, #f.Stub.textures
    for index = 1, 20 do
        f:openWidget(); f:openCore(); f.host:Rebuild()
        resize(index % 2 == 0 and 1080 or 740, index % 2 == 0 and 720 or 560)
        canvas:Hide(); Settings.OpenToCategory(f:categoryID())
    end
    equal(#f.Stub.frames, frames); equal(#f.Stub.textures, textures)
    equal(#f.registrations, 1); equal(#f.addonCalls, 1); equal(f.host.UI.window, canvas)
    equal(f.instance.settings, f.savedSettings)
end)

check("registration and opening failures retain partial ownership and recover without a separate dialog", function()
    local f = fixture({ failCanvas = true }); local canvas = f.canvas
    equal(#f.registrations, 0); assert(f.host.ready); assert(f.host.bars.top:IsShown())
    local messages = #f.Stub.messages; f:openCore()
    equal(#f.Stub.messages, messages + 1); equal(canvas:IsShown(), false)
    f.failCanvas = false; f:openCore(); equal(#f.registrations, 1); equal(f.host.UI.window, canvas)
    f = fixture({ failAddon = true }); canvas = f.canvas
    equal(#f.registrations, 1); f.failAddon = false; f:openWidget()
    equal(#f.registrations, 1); equal(#f.addonCalls, 2); equal(f.host.UI.window, canvas)
    f = fixture({ failOpen = true }); canvas = f.canvas
    messages = #f.Stub.messages; f:openCore(); equal(#f.Stub.messages, messages + 1)
    equal(canvas:IsShown(), false); f.failOpen = false; f:openWidget()
    equal(f.canvas, canvas); equal(#f.registrations, 1); equal(f.host.UI.widgetID, f.instance.id)
    f = fixture(); canvas = f.canvas
    local open = Settings.OpenToCategory; Settings.OpenToCategory = nil
    messages = #f.Stub.messages; f:openCore(); equal(#f.Stub.messages, messages + 1)
    equal(canvas:IsShown(), false); Settings.OpenToCategory = open; f:openCore()
    equal(f.canvas, canvas); equal(#f.registrations, 1)
end)

print(passed .. " native Settings integration tests passed")
