-- Native-shaped profile creation through the actual settings action and model.
-- Native placement, IME/Unicode letter limits and rendering require the client.
local root = REPO_ROOT or "."
local popupKey = "MENUBAR_NEW_APPEARANCE_PROFILE"
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function same(actual, expected)
    if type(actual) ~= "table" or type(expected) ~= "table" then equal(actual, expected); return end
    for key, value in pairs(actual) do assert(expected[key] ~= nil); same(value, expected[key]) end
    for key in pairs(expected) do assert(actual[key] ~= nil) end
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function fixture()
    local Stub = dofile(root .. "/tests/wow_stub.lua"); Stub.Install(); MenubarDB = nil
    local f = { Stub = Stub }
    f.secret = setmetatable({}, { __index = function() error("restricted profile data indexed", 0) end,
        __tostring = function() error("restricted profile data formatted", 0) end })
    issecretvalue = function(value) return rawequal(value, f.secret) end
    local namespace = {}
    for line in io.lines(root .. "/src/menubar-core/Menubar.toc") do
        local file = line:match("^%s*(.-)%s*$")
        if file:match("%.lua$") then assert(loadfile(root .. "/src/menubar-core/" .. file))("Menubar", namespace) end
    end
    Menubar:RegisterWidgetType({ id = "profile-probe", name = "Profile probe", defaults = { value = "Saved" },
        defaultPlacement = { bar = "top", alignment = "left" },
        update = function(widget) widget:SetText(widget.settings.value) end,
        settings = { { key = "value", label = "Probe value", type = "text" } },
    })
    local db, character, profile = MenubarModel.Initialize(nil, "Tester - Test Realm")
    profile.fontSize, profile.height = 17, 29
    db.futureField = { preserved = true }
    local instance = MenubarModel.AddWidget(db, "Tester - Test Realm", "profile-probe",
        { value = "Saved", futureField = { preserved = true } }, { bar = "top", alignment = "left" })
    local other = MenubarModel.GetCharacter(db, "Other character")
    MenubarDB = db; Menubar:Start(); assert(Menubar.ready)
    f.host, f.db, f.character, f.source, f.instance, f.other = Menubar, db, character, profile, instance, other
    function f:action()
        for _, control in ipairs(self.host.UI.window.controls) do
            assert(control.caption ~= "Create a copy named", "The old inline creation field must be absent")
            if control.caption == "New profile..." then return control end
        end
        error("Missing New profile... action", 0)
    end
    function f:clickNew()
        self.host.UI:OpenSettings(); self:action():Click()
        return StaticPopup_FindVisible(popupKey)
    end
    function f:openNew()
        local dialog = self:clickNew(); assert(dialog, "The native naming popup must open")
        return dialog
    end
    return f
end

check("Create and Enter copy and select appearance without replacing character widgets", function()
    for _, input in ipairs({ "button", "enter" }) do
        local f = fixture(); local widget = f.host.runtime[f.instance.id]
        local settings, sourceColour = f.instance.settings, f.source.background
        local before = MenubarModel.DeepCopy(f.db)
        local dialog = f:openNew(); local session = dialog.data
        equal(f.host.UI.profileDialogSession, session); equal(session.dialog, dialog)
        equal(dialog:GetEditBox():GetText(), ""); equal(dialog:GetButton1():IsEnabled(), false)
        assert(dialog:GetEditBox():HasFocus()); equal(dialog:GetEditBox().maxLetters, 240)
        assert(dialog:GetTextFontString():GetText():find('"Default"', 1, true))
        same(f.db, before)
        dialog:GetEditBox():SetText("  Night  "); equal(dialog:GetButton1():IsEnabled(), true)
        same(f.db, before)
        local definition = StaticPopupDialogs[popupKey]
        if input == "button" then dialog:GetButton1():Click()
        else
            local calls = f.Stub.popupClicks
            dialog:GetEditBox().scripts.OnEnterPressed(dialog:GetEditBox())
            equal(f.Stub.popupClicks, calls + 1)
        end
        equal(f.character.profile, "Night"); equal(f.other.profile, "Default")
        equal(StaticPopup_FindVisible(popupKey), nil); equal(f.host.UI.profileDialogSession, nil)
        local copy = f.db.profiles.Night
        assert(copy ~= f.source and copy.background ~= sourceColour)
        equal(copy.fontSize, 17); equal(copy.height, 29)
        equal(f.character.widgets[1], f.instance); equal(f.instance.settings, settings)
        equal(f.host.runtime[f.instance.id], widget); equal(settings.futureField.preserved, true)
        equal(f.db.futureField.preserved, true)
        copy.background[1] = 0.1; equal(f.source.background, sourceColour)
        assert(sourceColour[1] ~= 0.1)
        before = MenubarModel.DeepCopy(f.db)
        definition.OnAccept(dialog, session); same(f.db, before)
    end
end)

check("draft validation is live and Accept rechecks a name which became a duplicate", function()
    local f = fixture(); local dialog = f:openNew(); local before = MenubarModel.DeepCopy(f.db)
    for _, name in ipairs({ "", " \t ", "Default", "  Default  " }) do
        dialog:GetEditBox():SetText(name); equal(dialog:GetButton1():IsEnabled(), false)
        StaticPopup_OnClick(dialog, 1)
        assert(dialog:IsShown()); same(f.db, before)
    end
    dialog:GetEditBox():SetText("Available"); equal(dialog:GetButton1():IsEnabled(), true)
    local external = assert(MenubarModel.CreateProfile(f.db, "Available", "Default"))
    external.fontSize = 33; before = MenubarModel.DeepCopy(f.db)
    StaticPopup_OnClick(dialog, 1)
    assert(dialog:IsShown()); equal(dialog:GetButton1():IsEnabled(), false)
    assert(dialog:GetTextFontString():GetText():find("already exists", 1, true))
    same(f.db, before); equal(f.db.profiles.Available, external)
    dialog:GetEditBox():SetText("Different"); dialog:GetButton1():Click()
    equal(f.character.profile, "Different"); equal(f.db.profiles.Available.fontSize, 33)
end)

check("Cancel editbox Escape and native Escape leave saved state untouched", function()
    for _, input in ipairs({ "cancel", "edit escape", "native escape" }) do
        local f = fixture(); local before = MenubarModel.DeepCopy(f.db); local dialog = f:openNew()
        dialog:GetEditBox():SetText("Do not save")
        if input == "cancel" then dialog:GetButton2():Click()
        elseif input == "edit escape" then dialog:GetEditBox().scripts.OnEscapePressed(dialog:GetEditBox())
        else StaticPopup_EscapePressed() end
        equal(dialog:IsShown(), false); equal(dialog:GetEditBox():GetText(), "")
        equal(f.host.UI.profileDialogSession, nil); same(f.db, before)
    end
    for _, expired in ipairs({ "profile", "generation" }) do
        local f = fixture(); local dialog = f:openNew(); dialog:GetEditBox():SetText("Expired")
        if expired == "profile" then
            assert(MenubarModel.CreateProfile(f.db, "External", "Default"))
            assert(MenubarModel.SetProfile(f.db, f.host.characterKey, "External"))
        else f.host.UI.settingsGeneration = f.host.UI.settingsGeneration + 1 end
        local before = MenubarModel.DeepCopy(f.db)
        dialog:GetEditBox().scripts.OnEscapePressed(dialog:GetEditBox())
        equal(dialog:IsShown(), false); equal(f.host.UI.profileDialogSession, nil)
        same(f.db, before)
    end
end)

check("restricted draft text and stale settings model or pooled-action ownership cannot create profiles", function()
    for _, kind in ipairs({ "restricted text", "malformed text", "settings hidden", "widget page", "font page",
        "profile", "database", "character", "source replaced", "profiles map", "characters map" }) do
        local f = fixture(); local dialog = f:openNew(); local session = dialog.data
        local action, definition = f:action(), StaticPopupDialogs[popupKey]
        local staleAction = action.scripts.OnClick
        dialog:GetEditBox():SetText("Ignored")
        if kind == "restricted text" or kind == "malformed text" then
            dialog:GetEditBox().GetText = function() return kind == "restricted text" and f.secret or 42 end
            definition.EditBoxOnTextChanged(dialog:GetEditBox(), session)
            equal(dialog:GetButton1():IsEnabled(), false)
        elseif kind == "settings hidden" then SettingsPanel:Hide()
        elseif kind == "widget page" then f.host.UI:OpenWidget(f.instance.id)
        elseif kind == "font page" then f.host.UI:OpenFontEditor()
        elseif kind == "profile" then
            assert(MenubarModel.CreateProfile(f.db, "Other", "Default"))
            assert(MenubarModel.SetProfile(f.db, f.host.characterKey, "Other"))
        elseif kind == "database" then f.host.db = MenubarModel.Initialize(nil, f.host.characterKey)
        elseif kind == "character" then f.host.characterKey = "Other character"
        elseif kind == "source replaced" then f.db.profiles.Default = MenubarModel.DeepCopy(f.source)
        elseif kind == "profiles map" then f.db.profiles = { Default = f.source }
        else f.db.characters = { [f.host.characterKey] = f.character, ["Other character"] = f.other } end
        local before, activeBefore = MenubarModel.DeepCopy(f.db), MenubarModel.DeepCopy(f.host.db)
        definition.OnAccept(dialog, session)
        definition.EditBoxOnEnterPressed(dialog:GetEditBox(), session)
        same(f.db, before); same(f.host.db, activeBefore)
        if kind == "widget page" or kind == "font page" or kind == "settings hidden" then
            local shows = f.Stub.popupShows; staleAction(action); equal(f.Stub.popupShows, shows)
        end
    end
end)

check("a reused popup rejects old callbacks and exact dismissal preserves another popup owner", function()
    local f = fixture(); local old = f:openNew(); local oldSession = old.data
    local definition = StaticPopupDialogs[popupKey]
    old:GetButton2():Click()
    local current = f:openNew(); local session = current.data
    equal(current, old); assert(session ~= oldSession)
    current:GetEditBox():SetText("Current")
    -- Native FindVisible ignores data for a single-instance definition.
    equal(StaticPopup_FindVisible(popupKey, oldSession), current)
    StaticPopup_Hide(popupKey, oldSession); assert(current:IsShown())
    local before = MenubarModel.DeepCopy(f.db)
    definition.OnAccept(current, oldSession); definition.OnHide(current, oldSession)
    definition.OnCancel(current, oldSession); definition.EditBoxOnTextChanged(current:GetEditBox(), oldSession)
    definition.EditBoxOnEscapePressed(current:GetEditBox(), oldSession)
    equal(f.host.UI.profileDialogSession, session); same(f.db, before)
    current:GetButton2():Click()
    StaticPopupDialogs.FOREIGN_PROFILE_TEST = { text = "Foreign popup", button1 = "Okay", timeout = 0 }
    local foreignData = {}; local foreign = StaticPopup_Show("FOREIGN_PROFILE_TEST", nil, nil, foreignData)
    equal(foreign, current)
    definition.OnAccept(foreign, oldSession); definition.OnHide(foreign, oldSession)
    definition.EditBoxOnEscapePressed(foreign:GetEditBox(), oldSession)
    f.host.UI:DismissSettingsControls()
    assert(foreign:IsShown()); equal(foreign.data, foreignData)
    equal(foreign:GetTextFontString():GetText(), "Foreign popup"); same(f.db, before)
end)

check("accept closes before redraw and does not auto-hide a newer session in the same native slot", function()
    local f = fixture(); local dialog = f:openNew(); dialog:GetEditBox():SetText("First")
    local openSettings = f.host.UI.OpenSettings
    local replacement
    f.host.UI.OpenSettings = function(ui, ...)
        local rendering = ui.renderingSettings
        local result = openSettings(ui, ...)
        if not rendering then
            ui:OpenNewProfileDialog(); replacement = StaticPopup_FindVisible(popupKey)
        end
        return result
    end
    StaticPopup_OnClick(dialog, 1)
    equal(f.character.profile, "First"); equal(replacement, dialog)
    assert(replacement:IsShown()); equal(f.host.UI.profileDialogSession, replacement.data)
    equal(replacement.data.sourceName, "First")
    equal(replacement:GetEditBox():GetText(), ""); equal(replacement:GetButton1():IsEnabled(), false)
end)

check("repeated cancellation reuses native resources and unavailable native popups recover without writes", function()
    local f = fixture(); local dialog = f:openNew(); dialog:GetButton2():Click()
    local frames, textures, definition = #f.Stub.frames, #f.Stub.textures, StaticPopupDialogs[popupKey]
    for _ = 1, 25 do
        local nextDialog = f:openNew(); equal(nextDialog, dialog)
        nextDialog:GetEditBox():SetText("Discarded"); nextDialog:GetButton2():Click()
    end
    equal(#f.Stub.frames, frames); equal(#f.Stub.textures, textures)
    equal(#f.Stub.popupFrames, 1); equal(StaticPopupDialogs[popupKey], definition)
    local before = MenubarModel.DeepCopy(f.db)
    local show = StaticPopup_Show
    StaticPopup_Show = nil; equal(f:clickNew(), nil); same(f.db, before)
    StaticPopup_Show = function() error("native popup unavailable", 0) end
    equal(f:clickNew(), nil); same(f.db, before)
    StaticPopup_Show = show
    StaticPopupDialogs.FULL_PROFILE_TEST = { text = "Occupied slot", button1 = "Okay", timeout = 0 }
    local foreign = StaticPopup_Show("FULL_PROFILE_TEST")
    equal(f:clickNew(), nil); assert(foreign:IsShown()); same(f.db, before)
    foreign:Hide(); assert(f:openNew()); assert(f.host.ready)
end)

print(passed .. " native profile-dialog tests passed")
