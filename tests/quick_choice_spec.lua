-- Shared native quick-selector behavior through the actual host and persisted instances.
local root = REPO_ROOT or "."
local Stub = dofile(root .. "/tests/wow_stub.lua")
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, callback)
    local ok, why = pcall(callback)
    if not ok then error(name .. ": " .. tostring(why), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function fixture()
    Stub.Install(); MenubarDB = nil
    local f = { options = { { value = "a", label = "A" }, { value = "b", label = "B" } }, updates = 0, reads = 0 }
    f.secret = setmetatable({}, { __tostring = function() error("restricted value formatted", 0) end })
    issecretvalue = function(value) return rawequal(value, f.secret) end
    for line in io.lines(root .. "/src/menubar-core/Menubar.toc") do
        local file = line:match("^%s*(.-)%s*$")
        if file:match("%.lua$") then assert(loadfile(root .. "/src/menubar-core/" .. file))() end
    end
    f.host = Menubar
    f.host:RegisterWidgetType({ id = "quick-choice", name = "Quick choice", defaults = { selection = "a" },
        defaultPlacement = { bar = "top", alignment = "left" },
        settings = { { key = "selection", label = "Selection", type = "select", options = function()
            f.reads = f.reads + 1
            if f.throw then error("temporary choice source failure", 0) end
            return f.options
        end } },
        clickHint = "Choose", click = function(widget) widget:OpenChoiceMenu("selection", "Watch something") end,
        update = function(widget) f.updates = f.updates + 1; widget.lastChoice = widget.settings.selection; widget:SetText("Choice") end,
    })
    f.host:Start()
    local _, widget = next(f.host.runtime); f.widget = widget
    function f:open(target)
        target = target or self.widget
        target.frame:Click("LeftButton")
        assert(not target.failed, tostring(target.failed))
        return Stub.menus[#Stub.menus]
    end
    return f
end

check("quick choices open without settings writes and update only the selected instance immediately", function()
    local f = fixture(); local first = f.widget
    local duplicate = f.host:AddWidget("quick-choice"); local second = f.host.runtime[duplicate.id]
    local before = f.updates; local menu = f:open()
    equal(menu.title, "Watch something"); equal(first.settings.selection, "a"); equal(f.updates, before)
    equal(Stub.MenuItem(menu, "A").selected(), true)
    equal(Stub.MenuItem(menu, "B").selected(), false)
    equal(f.host.UI.widgetID, nil)
    local choose = Stub.MenuItem(menu, "B").callback
    choose()
    equal(first.settings.selection, "b"); equal(first.instance.settings.selection, "b")
    equal(first.lastChoice, "b"); equal(second.settings.selection, "a"); equal(f.updates, before + 1)
    first.settings.selection = "a"; choose(); equal(first.settings.selection, "a")
end)

check("older quick-menu callbacks cannot write after their owner or UI session changes", function()
    for _, change in ipairs({ "other-menu", "removed", "disabled", "rebuild", "settings-window", "character", "settings-table", "database", "definition" }) do
        local f = fixture(); local widget = f.widget; local settings = widget.settings
        local choose = Stub.MenuItem(f:open(), "B").callback
        if change == "other-menu" then f.host.UI:Context(UIParent, function() end)
        elseif change == "removed" then f.host:RemoveWidget(widget.id)
        elseif change == "disabled" then widget.instance.enabled = false; f.host:Rebuild()
        elseif change == "rebuild" then f.host:Rebuild()
        elseif change == "settings-window" then f.host.UI:OpenWidget(widget.id)
        elseif change == "character" then f.host.characterKey = "Another character"
        elseif change == "settings-table" then widget.settings = {}
        elseif change == "database" then f.host.db = {}
        else widget.definition = {} end
        choose(); equal(settings.selection, "a")
    end
end)

check("quick choices re-read current membership and reject stale inventory without replay", function()
    local f = fixture(); local widget = f.widget
    local choose = Stub.MenuItem(f:open(), "B").callback
    f.options = { { value = "a", label = "A" } }
    choose(); equal(widget.settings.selection, "a")
    f.options = { { value = "b", label = "B" } }
    choose(); equal(widget.settings.selection, "a")
    Stub.MenuItem(f:open(), "B").callback(); equal(widget.settings.selection, "b")
    assert(f.reads >= 4)
end)

check("unlisted saved choices and valid zero or false values remain distinct from malformed options", function()
    local f = fixture(); local widget = f.widget
    widget.settings.selection = "unlisted"
    f.options = {
        { value = f.secret, label = "Restricted" }, { value = math.huge, label = "Overflow" },
        { value = "hidden", label = f.secret }, { value = false, label = "Off", group = f.secret },
        { value = 0, label = "Automatic" }, { value = "b", label = "B" },
    }
    local menu = f:open(); equal(widget.settings.selection, "unlisted")
    equal(#menu.children, 3); equal(Stub.MenuItem(menu, "Off").selected(), false)
    Stub.MenuItem(menu, "Off").callback(); equal(widget.settings.selection, false)
    menu = f:open(); equal(Stub.MenuItem(menu, "Off").selected(), true)
    Stub.MenuItem(menu, "Automatic").callback(); equal(widget.settings.selection, 0)
end)

check("unavailable or empty choice sources leave focus intact and report a usable menu", function()
    local f = fixture(); local settings = f.widget.settings
    f.throw = true; local menu = f:open()
    equal(menu.title, "Choices are currently unavailable."); equal(settings.selection, "a")
    assert(table.concat(Stub.messages, " "):find("temporary choice source failure", 1, true))
    f.throw = false; f.options = {}; menu = f:open()
    equal(menu.title, "No choices available."); equal(settings.selection, "a")
    MenuUtil = nil
    equal(f.widget:OpenChoiceMenu("selection"), false); equal(settings.selection, "a")
    equal(f.widget.failed, nil)
end)

check("quick selectors reject invalid keys and keep an already-open settings page synchronized", function()
    local f = fixture(); local widget = f.widget
    assert(not pcall(widget.OpenChoiceMenu, widget, f.secret))
    assert(not pcall(widget.OpenChoiceMenu, widget, "selection", f.secret))
    equal(widget:OpenChoiceMenu("missing"), false)
    f.host.UI:OpenWidget(widget.id)
    Stub.MenuItem(f:open(), "B").callback()
    equal(f.host.UI.widgetID, widget.id)
    local found
    for _, control in ipairs(f.host.UI.window.controls) do
        if control.caption == "Selection" then found = control:GetText() end
    end
    equal(found, "B"); equal(widget.settings.selection, "b")
end)

print(passed .. " quick-choice host tests passed")
