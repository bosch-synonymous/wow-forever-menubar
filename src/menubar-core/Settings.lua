-- Native Blizzard panels and controls; bar themes apply to the menu bars.
local Host, Model, Fonts = Menubar, MenubarModel, MenubarFonts
local UI = Host.UI

local function public(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function number(value)
    return public(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function colorValue(value)
    if not public(value) or type(value) ~= "table" then return nil end
    local color = {}
    for index = 1, 4 do
        local component = value[index]
        if not public(component) then return nil end
        if index == 4 and component == nil then component = 1 end
        if not number(component) or component < 0 or component > 1 then return nil end
        color[index] = component
    end
    return color
end

local function selections(options)
    local valid = {}
    if not public(options) or type(options) ~= "table" then return valid end
    for _, option in ipairs(options) do
        if public(option) and type(option) == "table" then
            local label, value, group = option.label, option.value, option.group
            local primitive = public(value) and (type(value) == "string" or type(value) == "boolean" or number(value))
            if public(label) and type(label) == "string" and label ~= "" and primitive then
                valid[#valid + 1] = { label = label, value = value,
                    group = public(group) and type(group) == "string" and group or nil }
            end
        end
    end
    return valid
end

function UI:CloseColorPicker()
    local session = self.colorSession
    self.colorOwner, self.colorSession = nil, nil
    if not session then return end
    local picker = session.picker
    -- Another addon may have reused the shared picker while it was still shown.
    if type(picker.GetExtraInfo) == "function" then
        local ok, owner = pcall(picker.GetExtraInfo, picker)
        if not ok or owner ~= session then return end
    end
    picker:Hide()
end

local function text(parent, value, style)
    local label = parent:CreateFontString(nil, "OVERLAY", style or "GameFontHighlight")
    label:SetText(value or "")
    label:SetJustifyH("LEFT")
    return label
end

local function nativeButton(parent, caption, width, callback)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width or UI:GetControlWidth(), 24)
    control:SetText(caption or "")
    control.Label = control:GetFontString()
    control:SetScript("OnClick", callback)
    return control
end

local function arrow(parent, direction, callback)
    local control = CreateFrame("Button", nil, parent, "UIPanelSquareButton")
    SquareButton_SetIcon(control, direction == "up" and "UP" or "DOWN")
    control:SetScript("OnClick", callback)
    control:SetWidth(24)
    control:SetHeight(18)
    control.direction = direction
    return control
end

local function mark(control, caption, kind)
    control.caption, control.menubarControl = caption, kind
    control.fontField = nil
    return control
end

local function controlSession(ui, control)
    local generation, token, window = ui.settingsGeneration, control.menubarSession, ui.window
    local database, character, profile = Host.db, Host.characterKey, Host:GetProfile()
    local id, draft = ui.widgetID, ui.fontEditor
    local instance = id and Model.GetWidget(database, character, id)
    local settings = instance and instance.settings
    local definition = instance and Host.types[instance.type]
    return function()
        if ui.settingsGeneration ~= generation or control.menubarSession ~= token or ui.window ~= window
            or Host.db ~= database or Host.characterKey ~= character or ui.widgetID ~= id or ui.fontEditor ~= draft then return false end
        local shown, visible = control:IsShown(), window:IsVisible()
        if not public(shown) or shown ~= true or not public(visible) or visible ~= true or Host:GetProfile() ~= profile then return false end
        if id then
            local current = Model.GetWidget(database, character, id)
            return current ~= nil and current == instance and current.settings == settings and Host.types[current.type] == definition
        end
        return true
    end
end

local profilePopupKey = "MENUBAR_NEW_APPEARANCE_PROFILE"

local function ownedProfileDialog(session, dialog)
    return public(session) and type(session) == "table" and UI.profileDialogSession == session
        and public(dialog) and (type(dialog) == "table" or type(dialog) == "userdata")
        and public(dialog.which) and public(dialog.data) and session.dialog == dialog
        and dialog.which == profilePopupKey and dialog.data == session
end

local function currentProfileDialog(session, dialog)
    if not ownedProfileDialog(session, dialog)
        or not Host.ready or Host.db ~= session.database or Host.characterKey ~= session.characterKey
        or UI.window ~= session.window or UI.settingsGeneration ~= session.generation
        or UI.widgetID ~= nil or UI.fontEditor ~= nil then return false end
    local db = session.database
    if not public(db.characters) or type(db.characters) ~= "table" or db.characters ~= session.characters
        or db.characters[session.characterKey] ~= session.character
        or not public(db.profiles) or type(db.profiles) ~= "table" or db.profiles ~= session.profiles
        or db.profiles[session.sourceName] ~= session.source
        or not public(session.character.profile) or session.character.profile ~= session.sourceName then return false end
    local visible = session.window:IsVisible()
    return public(visible) and visible == true
end

function UI:CloseNewProfileDialog()
    local session = self.profileDialogSession
    self.profileDialogSession = nil
    if not session then return end
    -- Native popups are pooled. Dismiss only this key and exact data owner.
    if type(StaticPopup_Hide) == "function" then StaticPopup_Hide(profilePopupKey, session) end
end

local function profileName(dialog, session)
    local value = dialog:GetEditBox():GetText()
    if not public(value) or type(value) ~= "string" then return nil, "The profile name is unavailable." end
    local name = value:match("^%s*(.-)%s*$")
    if name == "" then return nil, "Enter a profile name." end
    if session.database.profiles[name] ~= nil then return nil, "That profile already exists." end
    return name
end

local function updateProfileDialog(dialog, session, showEmptyError)
    if not currentProfileDialog(session, dialog) then return end
    local name, message = profileName(dialog, session)
    dialog:GetButton1():SetEnabled(name ~= nil)
    local value = dialog:GetEditBox():GetText()
    local empty = public(value) and type(value) == "string" and not value:find("%S")
    local body = session.prompt
    if message and (showEmptyError or not empty) then body = body .. "\n\n|cffff4040" .. message .. "|r" end
    dialog:GetTextFontString():SetText(body)
    dialog:Resize()
end

local function forgetProfileDialog(_, session)
    if public(session) and UI.profileDialogSession == session then UI.profileDialogSession = nil end
end

local profilePopupDefinition = {
    text = "New appearance profile\n\nProfile name:", button1 = "Create", button2 = "Cancel",
    hasEditBox = true, maxLetters = 240, editBoxWidth = 240, timeout = 0,
    whileDead = true, hideOnEscape = true,
    OnShow = function(dialog, session)
        if not public(session) or type(session) ~= "table" or UI.profileDialogSession ~= session or dialog.data ~= session then return end
        session.dialog = dialog
        if not currentProfileDialog(session, dialog) then UI:CloseNewProfileDialog(); return end
        session.initializing = true
        dialog:GetEditBox():SetText("")
        session.initializing = nil
        updateProfileDialog(dialog, session, false)
        dialog:GetEditBox():SetFocus()
    end,
    OnAccept = function(dialog, session)
        if not currentProfileDialog(session, dialog) then
            if public(session) and UI.profileDialogSession == session then UI:CloseNewProfileDialog() end
            return true
        end
        local name = profileName(dialog, session)
        if not name then updateProfileDialog(dialog, session, true); return true end
        local created, message = Model.CreateProfile(session.database, name, session.sourceName)
        if not created then
            dialog:GetTextFontString():SetText(session.prompt .. "\n\n" .. message)
            dialog:Resize(); return true
        end
        Model.SetProfile(session.database, session.characterKey, name)
        -- Close before callbacks/redraw can reuse a shared popup frame. Returning
        -- true prevents the native caller hiding a new owner after we return.
        UI:CloseNewProfileDialog()
        Host:Rebuild(); UI:OpenSettings()
        return true
    end,
    OnCancel = forgetProfileDialog, OnHide = forgetProfileDialog,
    EditBoxOnTextChanged = function(edit, session)
        if not public(session) or type(session) ~= "table" or session.initializing then return end
        local dialog = session.dialog
        if currentProfileDialog(session, dialog) and dialog:GetEditBox() == edit then updateProfileDialog(dialog, session, true) end
    end,
    EditBoxOnEnterPressed = function(edit, session)
        local dialog = public(session) and type(session) == "table" and session.dialog
        if currentProfileDialog(session, dialog) and dialog:GetEditBox() == edit and dialog:GetButton1():IsEnabled() then
            StaticPopup_OnClick(dialog, 1)
        end
    end,
    EditBoxOnEscapePressed = function(edit, session)
        local dialog = public(session) and type(session) == "table" and session.dialog
        if ownedProfileDialog(session, dialog) and dialog:GetEditBox() == edit then UI:CloseNewProfileDialog() end
    end,
}

function UI:OpenNewProfileDialog()
    if not Host.ready or not self.window or self.widgetID ~= nil or self.fontEditor ~= nil or not self.window:IsVisible() then return end
    self:CloseNewProfileDialog()
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function"
        or type(StaticPopup_Hide) ~= "function" or type(StaticPopup_OnClick) ~= "function"
        or (StaticPopupDialogs[profilePopupKey] ~= nil and StaticPopupDialogs[profilePopupKey] ~= profilePopupDefinition) then
        self.window.status:SetText("Profile creation is currently unavailable."); return
    end
    StaticPopupDialogs[profilePopupKey] = profilePopupDefinition
    local character = Model.GetCharacter(Host.db, Host.characterKey)
    local session = { database = Host.db, characterKey = Host.characterKey, character = character,
        sourceName = character.profile, source = Host:GetProfile(), profiles = Host.db.profiles, characters = Host.db.characters,
        window = self.window, generation = self.settingsGeneration }
    session.prompt = "New appearance profile\n\nCreate a copy of \"" .. session.sourceName .. "\".\n\nProfile name:"
    self.profileDialogSession = session
    local ok, dialog = pcall(StaticPopup_Show, profilePopupKey, nil, nil, session)
    if not ok or not dialog then
        self:CloseNewProfileDialog()
        self.window.status:SetText("Could not open the new profile dialog.")
        if not ok and public(dialog) and type(dialog) == "string" then Host.Print(dialog) end
    end
end

local function bindNavigation(ui, control, callback)
    control.menubarSession = {}
    local active = controlSession(ui, control)
    control:SetScript("OnClick", function(...)
        if active() then callback(...) end
    end)
end

function UI:GetPageWidth()
    return self.window and self.window.pageWidth or 452
end

function UI:GetControlWidth()
    return math.min(260, math.max(150, math.floor(self:GetPageWidth() * 0.51)))
end

function UI:DismissSettingsControls()
    self.settingsGeneration = (self.settingsGeneration or 0) + 1
    self.contextToken = nil
    self:CloseBarMenu()
    local menu = self.settingsMenuSession
    self.settingsMenuSession = nil
    if menu and menu.root then menu.manager:CloseMenus() end
    self:CloseColorPicker()
    self:CloseNewProfileDialog()
    for _, control in ipairs(self.window and self.window.controls or {}) do
        if type(control.ClearMenuState) == "function" then control:ClearMenuState() end
        if control.ClearFocus then control:ClearFocus() end
        if control.edit and control.edit.ClearFocus then control.edit:ClearFocus() end
    end
end

-- Settings owns this canvas's parent, anchors, visibility and outer window.
-- Keep registration cheap: the controls are created only when the page is shown.
function UI:SettingsCanvas()
    if self.window then return self.window end
    local window = CreateFrame("Frame", "MenubarOptions", UIParent)
    self.window = window
    window:Hide()
    window.controls = {}
    window:SetScript("OnShow", function() self:RenderSettingsPage() end)
    window:SetScript("OnHide", function() self:DismissSettingsControls() end)
    window:SetScript("OnSizeChanged", function()
        if not window.content then return end
        local changed = self:UpdateWindowLayout()
        if changed then self:RenderSettingsPage() end
    end)
    window.OnRefresh = function() self:RenderSettingsPage() end
    return window
end

function UI:RegisterSettingsCategory()
    if self.settingsRegistered then return true end
    local window = self:SettingsCanvas()
    if not Host.ready or type(Settings) ~= "table" or type(Settings.RegisterCanvasLayoutCategory) ~= "function"
        or type(Settings.RegisterAddOnCategory) ~= "function" then return false end
    if not self.settingsCategory then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, window, "Menubar")
        if not ok or type(category) ~= "table" or type(category.GetID) ~= "function" then return false end
        self.settingsCategory = category
    end
    local ok = pcall(Settings.RegisterAddOnCategory, self.settingsCategory)
    if not ok then return false end
    self.settingsRegistered = true
    return true
end

function UI:ShowSettingsCategory()
    local generation = self.settingsGeneration
    local ok = self:RegisterSettingsCategory()
    if ok and type(Settings.OpenToCategory) == "function" then
        local readable, id = pcall(self.settingsCategory.GetID, self.settingsCategory)
        if readable and public(id) and (type(id) == "string" or number(id)) then
            -- The native function returns nil even when it succeeds.
            ok = pcall(Settings.OpenToCategory, id)
        else ok = false end
    else ok = false end
    if not ok then Host.Print("Could not open Menubar in Options > AddOns. Try again after the game UI has loaded."); return end
    if self.settingsGeneration == generation then self:RenderSettingsPage() end
end

function UI:UpdateWindowLayout()
    local window = self.window
    local width = window:GetWidth()
    if not number(width) or width <= 0 then width = 680 end
    local pageWidth = math.max(260, width - 220)
    local changed = window.pageWidth ~= pageWidth
    window.pageWidth = pageWidth
    window.content:SetWidth(pageWidth)
    return changed
end

function UI:Window()
    local window = self:SettingsCanvas()
    if window.content then self:UpdateWindowLayout(); return window end
    window.title = text(window, "Menubar", "GameFontNormalLarge")
    window.title:SetPoint("TOPLEFT", 16, -16)
    window.title:SetPoint("TOPRIGHT", -16, -16)
    local sidebar = CreateFrame("Frame", nil, window)
    sidebar:SetPoint("TOPLEFT", 8, -52)
    sidebar:SetPoint("BOTTOMLEFT", 8, 44)
    sidebar:SetWidth(164)
    window.sidebar = sidebar
    local sideScroll = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    sideScroll:SetPoint("TOPLEFT", 0, 0)
    sideScroll:SetPoint("BOTTOMRIGHT", -22, 0)
    local sideContent = CreateFrame("Frame", nil, sideScroll)
    sideContent:SetSize(142, 500)
    sideScroll:SetScrollChild(sideContent)
    window.sideContent, window.sideScroll = sideContent, sideScroll
    window.sidebarRows = {}
    window.add = nativeButton(window, "+", 28)
    window.add:SetPoint("BOTTOMLEFT", 12, 12)
    window.remove = nativeButton(window, "-", 28)
    window.remove:SetPoint("LEFT", window.add, "RIGHT", 5, 0)
    window.up = arrow(window, "up")
    window.up:SetPoint("LEFT", window.remove, "RIGHT", 9, 0)
    window.down = arrow(window, "down")
    window.down:SetPoint("LEFT", window.up, "RIGHT", 5, 0)

    local divider = window:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 180, -48)
    divider:SetPoint("BOTTOMLEFT", 180, 12)
    divider:SetWidth(1); divider:SetColorTexture(0.45, 0.36, 0.22, 0.5)
    local page = CreateFrame("Frame", nil, window)
    page:SetPoint("TOPLEFT", 196, -52)
    page:SetPoint("BOTTOMRIGHT", -8, 44)
    window.page = page
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -16, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(self:GetPageWidth(), 500)
    scroll:SetScrollChild(content)
    window.content, window.scroll = content, scroll
    window.status = text(window, "", "GameFontHighlightSmall")
    window.status:SetPoint("BOTTOMLEFT", 196, 12)
    window.status:SetPoint("BOTTOMRIGHT", -8, 12)
    window.status:SetWordWrap(true)
    self:UpdateWindowLayout()
    return window
end

function UI:RenderSidebar()
    local window = self:Window()
    bindNavigation(self, window.add, function(owner)
        self:Context(owner, function(root, token)
            local session = { manager = Menu.GetManager() }
            self.settingsMenuSession = session
            root:AddMenuAcquiredCallback(function(frame) session.root = session.root or frame end)
            root:AddMenuReleasedCallback(function(frame)
                if session.root == frame then
                    session.root = nil
                    if self.settingsMenuSession == session then self.settingsMenuSession = nil end
                end
            end)
            self:AddWidgetMenu(root, nil, function()
                return self.contextToken == token and window:IsVisible()
            end)
        end)
    end)
    bindNavigation(self, window.remove, function()
        if self.widgetID then Host:RemoveWidget(self.widgetID); self:OpenSettings() end
    end)
    bindNavigation(self, window.up, function() self:MoveSelected(-1) end)
    bindNavigation(self, window.down, function() self:MoveSelected(1) end)
    local widgets, entries, counts = Host:SidebarInstances(), { { label = "Menubar", core = true } }, {}
    for _, instance in ipairs(widgets) do counts[instance.type] = (counts[instance.type] or 0) + 1 end
    local seen = {}
    for _, instance in ipairs(widgets) do
        seen[instance.type] = (seen[instance.type] or 0) + 1
        local definition = Host.types[instance.type]
        local name = definition and definition.name or instance.type .. " (unavailable)"
        if counts[instance.type] > 1 then name = name .. " " .. seen[instance.type] end
        if instance.enabled == false then name = name .. " (disabled)" end
        entries[#entries + 1] = { label = name, id = instance.id }
    end
    local selectedIndex
    for index, entry in ipairs(entries) do
        local row = window.sidebarRows[index]
        if not row then
            row = CreateFrame("Button", nil, window.sideContent)
            row:SetSize(142, 28)
            row.Label = text(row, "", "GameFontHighlight")
            row.Label:SetPoint("LEFT", 8, 0)
            row.Label:SetPoint("RIGHT", -6, 0)
            local highlight = row:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints(); highlight:SetColorTexture(1, 1, 1, 0.1)
            row.selected = row:CreateTexture(nil, "BACKGROUND")
            row.selected:SetAllPoints(); row.selected:SetColorTexture(1, 0.82, 0, 0.18)
            window.sidebarRows[index] = row
        end
        local id = entry.id
        row.entryID, row.core = id, entry.core
        row.Label:SetText(entry.label)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(index - 1) * 30)
        row.selected:SetShown(id == self.widgetID)
        bindNavigation(self, row, function()
            self.fontEditor = nil
            if id then self:OpenWidget(id) else self:OpenSettings() end
        end)
        row:Show()
        if id == self.widgetID then selectedIndex = index end
    end
    for index = #entries + 1, #window.sidebarRows do window.sidebarRows[index]:Hide() end
    window.sideContent:SetHeight(math.max(500, #entries * 30))
    window.remove:SetEnabled(self.widgetID ~= nil)
    window.up:SetEnabled(self.widgetID ~= nil and selectedIndex ~= nil and selectedIndex > 2)
    window.down:SetEnabled(self.widgetID ~= nil and selectedIndex ~= nil and selectedIndex < #entries)
end

function UI:MoveSelected(delta)
    if not self.widgetID then return end
    Host:ReorderSidebar(self.widgetID, delta)
    self:Redraw()
end

function UI:ClearWindow(title)
    local window = self:Window()
    local pageKey = self.fontEditor or self.widgetID or "appearance"
    local scroll = window.pageKey == pageKey and window.scroll:GetVerticalScroll() or 0
    window.pageKey, window.restoreScroll = pageKey, number(scroll) and math.max(0, scroll) or 0
    self:DismissSettingsControls()
    self.pools = self.pools or {}
    for _, control in ipairs(window.controls) do
        control:Hide()
        local kind = control.menubarKind
        self.pools[kind] = self.pools[kind] or {}
        self.pools[kind][#self.pools[kind] + 1] = control
    end
    window.controls, self.y = {}, -4
    window.title:SetText(title)
    window.status:SetText("")
    self:RenderSidebar()
    return window
end

function UI:Acquire(kind, create)
    local pool = self.pools and self.pools[kind]
    local control = pool and table.remove(pool) or create()
    control.menubarSession, control.menubarMenuToken = {}, nil
    if type(control.ClearMenuState) == "function" then control:ClearMenuState() end
    control.menubarKind = kind
    control:ClearAllPoints()
    control:Show()
    self.window.controls[#self.window.controls + 1] = control
    return control
end

function UI:Note(value)
    local control = self:Acquire("note", function()
        local frame = CreateFrame("Frame", nil, self.window.content)
        frame.Label = text(frame, "", "GameFontHighlightSmall")
        frame.Label:SetPoint("TOPLEFT")
        frame.Label:SetWordWrap(true)
        return frame
    end)
    local width = self:GetPageWidth()
    control.Label:SetWidth(math.max(40, width - 8))
    control.Label:SetText(value)
    local height = math.max(28, control.Label:GetStringHeight() + 12)
    control:SetSize(width, height)
    control:SetPoint("TOPLEFT", 0, self.y)
    self.y = self.y - height
end

function UI:Row(caption, height)
    local row = self:Acquire("row", function()
        local frame = CreateFrame("Frame", nil, self.window.content)
        frame.Label = text(frame, "", "GameFontNormal")
        frame.Label:SetPoint("LEFT", 0, 0)
        frame.Label:SetWordWrap(true)
        return frame
    end)
    local width = self:GetPageWidth()
    row.Label:SetWidth(math.max(40, width - self:GetControlWidth() - 16))
    row.Label:SetFontObject(GameFontNormal)
    row.Label:SetText(caption)
    row.Label:Show()
    height = math.max(height or 30, row.Label:GetStringHeight() + 10)
    row:SetSize(width, height)
    row:SetPoint("TOPLEFT", 0, self.y)
    self.y = self.y - height - 6
    return row
end

function UI:OpenChoiceMenu(widget, key, title)
    assert(public(key) and type(key) == "string", "Menubar: invalid quick-choice key")
    assert(public(title) and (title == nil or (type(title) == "string" and title ~= "")), "Menubar: invalid quick-choice title")
    local instance, settings, definition = widget.instance, widget.settings, widget.definition
    local db, character = Host.db, Host.characterKey
    local field
    if definition then
        for _, candidate in ipairs(definition.settings or {}) do
            if candidate.key == key and candidate.type == "select" then field = candidate; break end
        end
    end
    if not field then return false end
    local function current(token)
        return (not token or self.contextToken == token) and Host.db == db and Host.characterKey == character
            and Host.runtime[widget.id] == widget and not widget.failed and widget.definition == definition
            and widget.instance == instance and widget.settings == settings and instance.settings == settings
            and instance.enabled ~= false and Model.GetWidget(db, character, widget.id) == instance
    end
    local function choices()
        local options = field.options or {}
        if type(options) == "function" then
            local ok, result = pcall(options, settings)
            if not ok then
                local detail = public(result) and type(result) == "string" and result or "Error details unavailable."
                Host.Print("Cannot read " .. field.label .. " choices: " .. detail)
                return nil
            end
            options = result
        end
        return selections(options)
    end
    if not current() then return false end
    local opened = self:Context(widget.frame, function(root, token)
        if not current(token) then return end
        root:CreateTitle(title or field.label)
        local options = choices()
        if not options then root:CreateTitle("Choices are currently unavailable."); return end
        if #options == 0 then root:CreateTitle("No choices available."); return end
        if #options > 12 then root:SetScrollMode(400) end
        local group
        for _, option in ipairs(options) do
            local value = option.value
            if option.group and group ~= option.group then root:CreateTitle(option.group); group = option.group end
            root:CreateRadio(option.label, function()
                return current(token) and public(settings[key]) and settings[key] == value
            end, function()
                if not current(token) then return end
                -- Inventory and exposed factions/currencies may change while
                -- the menu is open. Recheck membership before saving a choice.
                local available = choices()
                if not current(token) then return end
                self.contextToken = nil
                if not available then return end
                for _, choice in ipairs(available) do
                    if choice.value == value then
                        settings[key] = value
                        Host:RefreshWidget(widget.id)
                        if self.window and self.window:IsVisible() and self.widgetID == widget.id then self:Redraw() end
                        return
                    end
                end
            end)
        end
    end)
    return opened ~= nil
end

function UI:Select(caption, current, options, apply)
    if not public(current) then current = nil end
    local row = self:Row(caption)
    local control = self:Acquire("dropdown", function()
        local dropdown = CreateFrame("DropdownButton", nil, self.window.content, "WowStyle1DropdownTemplate")
        dropdown.Label = dropdown.Text
        return dropdown
    end)
    mark(control, caption, "select")
    control:SetSize(self:GetControlWidth(), 26)
    control:SetPoint("RIGHT", row, "RIGHT")
    local active = controlSession(self, control)
    local function choices()
        local source = options
        if not public(source) then return {} end
        if type(source) == "function" then
            local ok, value = pcall(source)
            source = ok and value or nil
        end
        return selections(source)
    end
    local available = choices()
    local fallback = #available == 0 and "No choices available" or "Not currently listed"
    for _, option in ipairs(available) do if option.value == current then fallback = option.label; break end end
    control:SetDefaultText(fallback)
    control:SetupMenu(function(_, root)
        if not active() then return end
        local token = {}
        control.menubarMenuToken = token
        local listed = choices()
        if #listed == 0 then root:CreateTitle("No choices available"); return end
        if #listed > 12 then root:SetScrollMode(400) end
        local group
        for _, option in ipairs(listed) do
            local value = option.value
            if option.group and group ~= option.group then root:CreateTitle(option.group); group = option.group end
            root:CreateRadio(option.label, function() return active() and current == value end, function()
                if not active() or control.menubarMenuToken ~= token or not control:IsMenuOpen() then return end
                local fresh = choices()
                if not active() or control.menubarMenuToken ~= token or not control:IsMenuOpen() then return end
                control.menubarMenuToken = nil
                for _, choice in ipairs(fresh) do
                    if choice.value == value then apply(value); self:Redraw(); return end
                end
            end)
        end
    end)
    return control
end

function UI:Toggle(caption, current, apply)
    local row = self:Row("")
    row.Label:Hide()
    local control = self:Acquire("toggle", function()
        local checkbox = CreateFrame("CheckButton", nil, self.window.content, "UICheckButtonTemplate")
        checkbox.menubarNativeClick = checkbox:GetScript("OnClick")
        return checkbox
    end)
    mark(control, caption, "toggle")
    control:SetSize(26, 26)
    control:SetPoint("LEFT", row, "LEFT", 0, 0)
    control:SetChecked(public(current) and current == true)
    control.Text:SetText(caption)
    control.Text:SetWidth(math.max(40, self:GetPageWidth() - 34))
    control.Text:SetJustifyH("LEFT")
    control.Text:SetJustifyV("MIDDLE")
    control.Text:SetWordWrap(true)
    local height = math.max(row:GetHeight(), control.Text:GetStringHeight() + 10)
    self.y = self.y - (height - row:GetHeight()); row:SetHeight(height)
    local active = controlSession(self, control)
    control:SetScript("OnClick", function(frame, ...)
        if not active() then return end
        -- Retain any template click behavior, with a fresh bound
        -- handler so retained callbacks cannot operate on a reused checkbox.
        if control.menubarNativeClick then control.menubarNativeClick(frame, ...) end
        local value = frame:GetChecked()
        if public(value) and type(value) == "boolean" then apply(value); self:Redraw() end
    end)
    return control
end

function UI:Text(caption, current, apply)
    if not public(current) then current = "" end
    local row = self:Row(caption)
    local control = self:Acquire("edit", function()
        local edit = CreateFrame("EditBox", nil, self.window.content, "InputBoxTemplate")
        edit:SetAutoFocus(false); edit:SetMaxLetters(240)
        return edit
    end)
    mark(control, caption, "text")
    control:SetSize(math.max(40, self:GetControlWidth() - 6), 24)
    control:SetPoint("RIGHT", row, "RIGHT")
    control:SetTextInsets(6, 8, 0, 0)
    control:SetText(tostring(current or ""))
    local active = controlSession(self, control)
    control:SetScript("OnEscapePressed", function(edit)
        if not active() then return end
        edit:SetText(tostring(current or "")); edit:ClearFocus()
    end)
    control:SetScript("OnEnterPressed", function(edit)
        if not active() then return end
        local value = edit:GetText()
        if not public(value) or type(value) ~= "string" then return end
        local ok, message = apply(value)
        edit:ClearFocus()
        if ok == false then
            self.window.status:SetText(public(message) and type(message) == "string" and message or "Invalid value.")
        else self:Redraw() end
    end)
    return control
end

function UI:Number(caption, current, minimum, maximum, apply, integer, canEdit)
    if integer then minimum, maximum = math.ceil(minimum), math.floor(maximum) end
    if not number(current) then current = minimum end
    current = math.max(minimum, math.min(maximum, current))
    if integer then current = math.max(math.ceil(minimum), math.floor(current)) end
    local row = self:Row(caption, 40)
    local control = self:Acquire("number", function()
        local frame = CreateFrame("Frame", nil, self.window.content)
        frame.edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        frame.edit:SetAutoFocus(false); frame.edit:SetMaxLetters(24)
        frame.edit:SetPoint("LEFT", 6, 0); frame.edit:SetHeight(24)
        frame.edit:SetJustifyH("RIGHT")
        frame.up = arrow(frame, "up")
        frame.down = arrow(frame, "down")
        frame.up:SetSize(24, 18); frame.down:SetSize(24, 18)
        frame.up:SetPoint("TOPRIGHT"); frame.down:SetPoint("BOTTOMRIGHT")
        return frame
    end)
    mark(control, caption, "number")
    local width = self:GetControlWidth()
    control:SetSize(width, 38)
    control.edit:SetWidth(math.max(40, width - 42))
    control.edit:SetTextInsets(6, 8, 0, 0)
    control:SetPoint("RIGHT", row, "RIGHT")
    control.edit:SetText(tostring(current or 0))
    local enabled = not canEdit or canEdit()
    control.edit:SetEnabled(enabled)
    if not enabled then control.edit:ClearFocus() end
    local shade = enabled and 1 or 0.5
    control.edit:SetTextColor(shade, shade, shade)
    row.Label:SetFontObject(enabled and GameFontNormal or GameFontDisable)
    local active = controlSession(self, control)
    local function editable() return active() and (not canEdit or canEdit()) end
    local function commit(value)
        if not editable() then return false end
        if integer and number(value) then value = math.floor(value) end
        if not number(value) or value < minimum or value > maximum then
            self.window.status:SetText("Enter a number from " .. minimum .. " to " .. maximum .. ".")
            control.edit:SetText(tostring(current)); return false
        end
        apply(value); self:Redraw(); return true
    end
    control.edit:SetScript("OnEnterPressed", function(edit)
        if not editable() then return end
        local value = edit:GetText()
        if not public(value) or type(value) ~= "string" then return end
        edit:ClearFocus(); commit(tonumber(value))
    end)
    control.edit:SetScript("OnEscapePressed", function(edit)
        if not active() then return end
        edit:SetText(tostring(current)); edit:ClearFocus()
    end)
    local step = integer and 1 or 0.1
    control.up:SetEnabled(enabled and current < maximum)
    control.down:SetEnabled(enabled and current > minimum)
    control.up:SetScript("OnClick", function() commit(math.min(maximum, current + step)) end)
    control.down:SetScript("OnClick", function() commit(math.max(minimum, current - step)) end)
    return control
end

function UI:Slider(caption, current, minimum, maximum, step, apply, format)
    local row = self:Row(caption, 36)
    local control = self:Acquire("slider", function()
        local frame = CreateFrame("Frame", nil, self.window.content)
        frame.slider = CreateFrame("Slider", nil, frame, "MinimalSliderTemplate")
        frame.slider:SetHeight(19)
        frame.slider:SetPoint("LEFT")
        frame.value = text(frame, "", "GameFontHighlightSmall")
        frame.value:SetPoint("RIGHT")
        frame.value:SetWidth(50)
        frame.value:SetJustifyH("RIGHT")
        return frame
    end)
    mark(control, caption, "slider")
    local width = self:GetControlWidth()
    control:SetSize(width, 26); control:SetPoint("RIGHT", row, "RIGHT")
    control.slider:SetWidth(math.max(40, width - 60))
    if not number(current) then current = minimum end
    current = math.max(minimum, math.min(maximum, current))
    local active = controlSession(self, control)
    local function display(value) control.value:SetText(format and format(value) or tostring(value)) end
    control.slider:SetScript("OnValueChanged", nil)
    control.slider:SetMinMaxValues(minimum, maximum)
    control.slider:SetValueStep(step); control.slider:SetObeyStepOnDrag(true)
    control.slider:SetValue(current); display(current)
    control.slider:SetScript("OnValueChanged", function(_, value)
        if not active() or not number(value) then return end
        value = math.max(minimum, math.min(maximum, value))
        display(value); apply(value)
    end)
    return control
end

function UI:Color(caption, current, apply)
    current = colorValue(current) or { 1, 1, 1, 1 }
    local row = self:Row(caption)
    local control = self:Acquire("color", function()
        local frame = nativeButton(self.window.content, "Choose colour...")
        frame.swatch = frame:CreateTexture(nil, "OVERLAY")
        frame.swatch:SetSize(16, 16); frame.swatch:SetPoint("LEFT", 9, 0)
        return frame
    end)
    mark(control, caption, "color")
    control:SetSize(self:GetControlWidth(), 24); control:SetPoint("RIGHT", row, "RIGHT")
    control.swatch:SetColorTexture(unpack(current))
    local currentControl = controlSession(self, control)
    control:SetScript("OnClick", function()
        if not currentControl() then return end
        if not ColorPickerFrame then
            if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_ColorPickerFrame") end
        end
        if not ColorPickerFrame or type(ColorPickerFrame.SetupColorPickerAndShow) ~= "function" then
            self.window.status:SetText("The game's colour picker is unavailable."); return
        end
        self:CloseColorPicker()
        local picker = ColorPickerFrame
        -- This click explicitly claims a new picker session. Native opacity
        -- initializes in OnShow, so a visible session must be restarted here.
        -- Ordinary page dismissal still leaves a foreign-owned picker alone.
        picker:Hide()
        if not currentControl() then return end
        if self.colorPickerHooked ~= picker then
            picker:HookScript("OnHide", function()
                if self.colorSession and self.colorSession.picker == picker then
                    self.colorOwner, self.colorSession = nil, nil
                end
            end)
            self.colorPickerHooked = picker
        end
        local original = Model.DeepCopy(current)
        local session = { picker = picker }
        local initializing = true
        local function active()
            if initializing or not currentControl() or self.colorSession ~= session then return false end
            if type(picker.GetExtraInfo) == "function" then
                local ok, owner = pcall(picker.GetExtraInfo, picker)
                return ok and owner == session
            end
            return true
        end
        local function changed()
            if not active() then return end
            local r, g, b = picker:GetColorRGB()
            local color = colorValue({ r, g, b, picker:GetColorAlpha() })
            if not color then return end
            current = color
            apply(color); control.swatch:SetColorTexture(unpack(color))
        end
        self.colorOwner, self.colorSession = control, session
        picker:SetupColorPickerAndShow({ r = current[1], g = current[2], b = current[3],
            hasOpacity = true, opacity = current[4], swatchFunc = changed, opacityFunc = changed,
            extraInfo = session,
            cancelFunc = function()
                if not active() then return end
                self.colorOwner, self.colorSession = nil, nil
                current = Model.DeepCopy(original)
                apply(current); control.swatch:SetColorTexture(unpack(current))
            end,
        })
        initializing = false
    end)
    return control
end

function UI:Action(caption, apply)
    local control = self:Acquire("button", function() return nativeButton(self.window.content, "") end)
    mark(control, caption, "action")
    control:SetText(caption)
    local width = self:GetControlWidth()
    local labelWidth = control.Label:GetStringWidth()
    if number(labelWidth) then width = math.max(width, labelWidth + 24) end
    control:SetSize(math.min(self:GetPageWidth(), width), 24)
    local active = controlSession(self, control)
    control:SetPoint("TOPLEFT", 0, self.y)
    control:SetScript("OnClick", function(...) if active() then return apply(...) end end)
    self.y = self.y - 34
    return control
end

function UI:Finish()
    local window = self.window
    local height = math.max(500, -self.y + 10)
    window.content:SetHeight(height)
    local offset, viewport = window.restoreScroll or 0, window.scroll:GetHeight()
    if number(viewport) and viewport > 0 then offset = math.min(offset, math.max(0, height - viewport)) end
    window.scroll:SetVerticalScroll(offset)
end

function UI:Redraw()
    self:RenderSettingsPage()
end

function UI:RenderSettingsPage()
    local window = self.window
    if not Host.ready or not window or not window:IsVisible() or self.renderingSettings then return end
    self.renderingSettings = true
    local ok, message = pcall(function()
        if self.fontEditor then self:OpenFontEditor()
        elseif self.widgetID then self:OpenWidget(self.widgetID) else self:OpenSettings() end
    end)
    self.renderingSettings = nil
    if not ok then error(message, 0) end
end

function UI:Section(caption)
    local section = self:Acquire("section", function()
        local frame = CreateFrame("Frame", nil, self.window.content)
        frame.Label = text(frame, "", "GameFontHighlightLarge")
        frame.Label:SetPoint("TOPLEFT", 0, -9)
        frame.line = frame:CreateTexture(nil, "ARTWORK")
        frame.line:SetPoint("BOTTOMLEFT", 0, 4)
        frame.line:SetPoint("BOTTOMRIGHT", 0, 4)
        frame.line:SetHeight(1); frame.line:SetColorTexture(0.45, 0.36, 0.22, 0.5)
        return frame
    end)
    section:SetSize(self:GetPageWidth(), 42)
    section.Label:SetText(caption)
    section:SetPoint("TOPLEFT", 0, self.y)
    self.y = self.y - 46
end

function UI:OpenFontEditor()
    self.widgetID = nil
    self.fontEditor = self.fontEditor or { name = "", regular = "", bold = "", italic = "", bolditalic = "" }
    if not self.renderingSettings then self:ShowSettingsCategory(); return end
    local draft = self.fontEditor
    self:ClearWindow("Menubar - Register custom font")
    self:Note("Use game-accessible font files. Bold and italic require matching face files; the addon does not simulate them with outlines.")
    for _, field in ipairs({ { "name", "Font name" }, { "regular", "Regular font file" }, { "bold", "Bold font file (optional)" },
        { "italic", "Italic font file (optional)" }, { "bolditalic", "Bold italic file (optional)" } }) do
        local key = field[1]
        local control = self:Text(field[2], draft[key], function(value) draft[key] = value; return true end)
        control.fontField = key
    end
    self:Action("Register and select font", function()
        for _, control in ipairs(self.window.controls) do
            if control.fontField then draft[control.fontField] = control:GetText() end
        end
        local faces = {}
        local probe = self.fontProbe
        if not probe then probe = self.window.content:CreateFontString(nil, "OVERLAY"); self.fontProbe = probe end
        for _, key in ipairs({ "regular", "bold", "italic", "bolditalic" }) do
            local path = draft[key]:match("^%s*(.-)%s*$")
            if path ~= "" then
                local ok, result = pcall(probe.SetFont, probe, path, Host:GetProfile().fontSize, "")
                if not ok or result == false then self.window.status:SetText("Could not load the " .. key .. " font file."); return end
                if key == "regular" then draft.regular = path else faces[key] = path end
            end
        end
        local entry, message = Fonts.AddCustom(Host.db, draft.name, draft.regular, faces)
        if not entry then self.window.status:SetText(message); return end
        Host:GetProfile().font, Host:GetProfile().fontStyle = entry.regular, "regular"
        Host:Rebuild(); self.fontEditor = nil; self:OpenSettings()
    end)
    self:Action("Back to appearance", function() self.fontEditor = nil; self:OpenSettings() end)
    self:Note("Windows/macOS font catalogues are not exposed to addons. Files must be installed in a game-accessible location, then registered here or by another addon.")
    self:Finish()
end

function UI:OpenSettings()
    self.widgetID, self.fontEditor = nil, nil
    if not self.renderingSettings then self:ShowSettingsCategory(); return end
    self:ClearWindow("Menubar - Appearance")
    local profile = Host:GetProfile()
    local character = Model.GetCharacter(Host.db, Host.characterKey)
    local function change(key, value) profile[key] = value; Host:Rebuild() end
    self:Note("Appearance profiles are shared. Widgets, order and settings belong to each character.")
    self:Section("Profiles")
    local profiles = {}
    for name in pairs(Host.db.profiles) do profiles[#profiles + 1] = { value = name, label = name } end
    table.sort(profiles, function(a, b) return a.value < b.value end)
    self:Select("Appearance profile", character.profile, profiles, function(value)
        Model.SetProfile(Host.db, Host.characterKey, value); Host:Rebuild()
    end)
    self:Action("New profile...", function() self:OpenNewProfileDialog() end)
    self:Section("Bar layout")
    self:Select("Bar style", profile.theme, { { value = "system7", label = "Mac OS 7.6 (Harmony)" },
        { value = "macos8", label = "Mac OS 8 (Platinum)" },
        { value = "macosx", label = "Mac OS X (Aqua)" },
        { value = "warcraftBrown", label = "Warcraft Brown" },
        { value = "warcraftBlack", label = "Warcraft Black" },
        { value = "warcraftRed", label = "Warcraft Red" } }, function(value)
            Model.ApplyTheme(profile, value); Host:Rebuild()
        end)
    self:Select("Bars", profile.placement, { { value = "top", label = "Top" }, { value = "bottom", label = "Bottom" },
        { value = "both", label = "Both" } }, function(value) change("placement", value) end)
    if profile.placement == "both" then
        self:Select("Core menu on", profile.coreMenuBar, { { value = "top", label = "Top bar" },
            { value = "bottom", label = "Bottom bar" }, { value = "both", label = "Both bars" } },
            function(value) change("coreMenuBar", value) end)
    end
    self:Toggle("Rounded outer corners", profile.roundedCorners, function(value) change("roundedCorners", value) end)
    self:Number("Height (UI units)", profile.height, 16, 96, function(value) change("height", value) end, true)
    self:Slider("Background opacity", profile.opacity * 100, 0, 100, 1,
        function(value) change("opacity", value / 100) end, function(value) return string.format("%.0f%%", value) end)
    self:Number("Edge padding", profile.padding, 0, 64, function(value) change("padding", value) end, true)
    self:Number("Widget spacing", profile.spacing, 0, 64, function(value) change("spacing", value) end, true)
    self:Section("Text")
    self:Select("Font", profile.font, Fonts.Options(Host.db.customFonts, profile.font), function(value)
        profile.fontStyle = "regular"; change("font", value)
    end)
    self:Select("Font style", profile.fontStyle, Fonts.Styles(profile.font, Host.db.customFonts),
        function(value) change("fontStyle", value) end)
    self:Number("Font size", profile.fontSize, 8, 48, function(value) change("fontSize", value) end, true)
    self:Toggle("Text shadow", profile.textShadow, function(value) change("textShadow", value) end)
    self:Action("Register custom font...", function() self:OpenFontEditor() end)
    self:Color("Text colour", profile.textColor, function(value) change("textColor", value) end)
    self:Section("Background and borders")
    local patterns = { { value = "solid", label = "Solid" }, { value = "dither", label = "Fine lines" } }
    if MenubarSkins.IsWarcraft(profile.theme) or profile.theme == "macosx" then
        table.insert(patterns, 1, { value = "theme", label = "Style texture" })
    end
    self:Select("Background pattern", profile.texture, patterns, function(value) change("texture", value) end)
    self:Text("Custom texture file", (profile.texture == "solid" or profile.texture == "dither" or profile.texture == "theme") and "" or profile.texture,
        function(value) change("texture", value:match("%S") and value or "solid"); return true end)
    for _, entry in ipairs({ { "background", "Background colour" },
        { "topLine", "Top line colour" }, { "bottomLine", "Bottom line colour" } }) do
        local key = entry[1]
        self:Color(entry[2], profile[key], function(value) change(key, value) end)
    end
    self:Number("Top line thickness", profile.topLineSize, 0, 6, function(value) change("topLineSize", value) end, true)
    self:Number("Bottom line thickness", profile.bottomLineSize, 0, 6, function(value) change("bottomLineSize", value) end, true)
    self:Section("Reset appearance")
    self:Action("Restore to defaults", function()
        local placement, menu = profile.placement, profile.coreMenuBar
        for key, value in pairs(Model.DefaultProfile) do profile[key] = Model.DeepCopy(value) end
        profile.placement, profile.coreMenuBar = placement, menu
        Host:Rebuild(); self:OpenSettings()
    end)
    self:Finish()
end

function UI:OpenWidget(id)
    local instance = Model.GetWidget(Host.db, Host.characterKey, id)
    if not instance then self:OpenSettings(); return end
    self.widgetID, self.fontEditor = id, nil
    if not self.renderingSettings then self:ShowSettingsCategory(); return end
    local definition = Host.types[instance.type]
    self:ClearWindow("Menubar - " .. (definition and definition.name or instance.type))
    local function setting(key, value) instance.settings[key] = value; Host:RefreshWidget(id) end
    self:Section("Placement")
    self:Toggle("Enabled", instance.enabled ~= false, function(value) instance.enabled = value; Host:Rebuild() end)
    self:Select("Alignment", instance.alignment, { { value = "left", label = "Left" },
        { value = "center", label = "Centre" }, { value = "right", label = "Right" } }, function(value)
            Model.MoveWidget(Host.db, Host.characterKey, id, Host:EffectiveBar(instance), value); Host:Rebuild()
        end)
    if Host:GetProfile().placement == "both" then
        self:Select("Bar", instance.bar, { { value = "top", label = "Top" }, { value = "bottom", label = "Bottom" } },
            function(value) Model.MoveWidget(Host.db, Host.characterKey, id, value, instance.alignment); Host:Rebuild() end)
    end
    if definition then
        if #(definition.settings or {}) > 0 then self:Section(definition.name .. " options") end
        for _, field in ipairs(definition.settings or {}) do
            local key = field.key
            local current = instance.settings[key]
            if current == nil then current = definition.defaults and definition.defaults[key] end
            if field.type == "select" then
                local source = field.options
                local function options()
                    if type(source) == "function" then return source(instance.settings) end
                    return source or {}
                end
                self:Select(field.label, current, options, function(value) setting(key, value) end)
            elseif field.type == "toggle" then self:Toggle(field.label, current, function(value) setting(key, value) end)
            elseif field.type == "number" then
                if not number(current) then current = definition.defaults and definition.defaults[key] end
                local function canEdit()
                    if field.enabledBy == nil then return true end
                    local value = instance.settings[field.enabledBy]
                    if not public(value) then return false end
                    if value == nil then value = definition.defaults and definition.defaults[field.enabledBy] end
                    return public(value) and value == true
                end
                self:Number(field.label, current, field.min or 0, field.max or 1000000,
                    function(value) setting(key, value) end, field.integer, canEdit)
            elseif field.type == "text" then
                self:Text(field.label, current, function(value) setting(key, value); return true end)
            elseif field.type == "color" then
                current = colorValue(current) or (definition.defaults and definition.defaults[key])
                self:Color(field.label, current, function(value) setting(key, value) end)
            end
        end
        self:Section("Manage widget")
        self:Action("Duplicate this widget", function()
            local created = Model.AddWidget(Host.db, Host.characterKey, instance.type, instance.settings,
                { bar = Host:EffectiveBar(instance), alignment = instance.alignment })
            Host:Rebuild(); self:OpenWidget(created.id)
        end)
        self:Action("Reset this widget's settings", function()
            instance.settings = Model.DeepCopy(definition.defaults or {})
            Host:Rebuild(); self:OpenWidget(id)
        end)
    else self:Note("Enable this widget's addon and reload. Its settings have been retained.") end
    self:Finish()
end
