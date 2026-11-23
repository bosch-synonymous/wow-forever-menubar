-- Ordinary menus use the same owner/session lifetime as quick selectors.
local root = REPO_ROOT or "."
local passed = 0
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function same(actual, expected)
    if type(actual) ~= "table" or type(expected) ~= "table" then equal(actual, expected); return end
    for key, value in pairs(actual) do assert(expected[key] ~= nil); same(value, expected[key]) end
    for key in pairs(expected) do assert(actual[key] ~= nil) end
end
local function fixture(options)
    options = options or {}
    local Stub = dofile(root .. "/tests/wow_stub.lua"); Stub.Install(); MenubarDB = nil
    local nativeCalls, descriptions = {}, 0
    local createRoot = MenuUtil.CreateRootMenuDescription
    MenuUtil.CreateRootMenuDescription = function(...)
        descriptions = descriptions + 1; return createRoot(...)
    end
    if options.nativeMouseHandler then
        local createFrame = CreateFrame
        CreateFrame = function(...)
            local frame = createFrame(...)
            function frame:HandlesGlobalMouseEvent(buttonName, event)
                nativeCalls[#nativeCalls + 1] = { owner = self, button = buttonName, event = event }
                return options.nativeResult == true
            end
            return frame
        end
    end
    for line in io.lines(root .. "/src/menubar-core/Menubar.toc") do
        local file = line:match("^%s*(.-)%s*$")
        if file:match("%.lua$") then assert(loadfile(root .. "/src/menubar-core/" .. file))() end
    end
    Menubar:RegisterWidgetType({ id = "menu-probe", name = "Menu probe", defaults = {},
        defaultPlacement = { bar = "top", alignment = "left" },
        update = function(widget) widget:SetText("Probe"); widget:SetWidth(1400) end })
    Menubar:Start()
    local _, widget = next(Menubar.runtime)
    local f = { Stub = Stub, host = Menubar, widget = widget, nativeCalls = nativeCalls }
    function f:descriptionCount() return descriptions end
    function f:mouseDown(owner, buttonName, event)
        event = event or "GLOBAL_MOUSE_DOWN"
        local handled = type(owner.HandlesGlobalMouseEvent) == "function"
            and owner:HandlesGlobalMouseEvent(buttonName, event) == true
        if event == "GLOBAL_MOUSE_DOWN" and not handled then Menu.GetManager():CloseMenus() end
        return handled
    end
    function f:pointerClick(owner, buttonName)
        self:mouseDown(owner, buttonName, "GLOBAL_MOUSE_DOWN")
        owner:Click(buttonName)
    end
    function f:widgetMenu()
        self.host.UI:WidgetMenu(UIParent, self.widget.instance)
        return self.Stub.menus[#self.Stub.menus]
    end
    function f:barMenu()
        self.host.UI:BarMenu(UIParent, "top")
        return self.Stub.menus[#self.Stub.menus]
    end
    return f
end
local function responders(menu, result)
    result = result or {}
    for _, child in ipairs(menu.children or {}) do
        if child.callback then result[#result + 1] = child end
        responders(child, result)
    end
    return result
end
local function change(f, kind)
    local host, widget = f.host, f.widget
    if kind == "closed" then Menu.GetManager():CloseMenus()
    elseif kind == "other menu" then host.UI:Context(UIParent, function(menu) menu:CreateTitle("New menu") end)
    elseif kind == "removed" then host:RemoveWidget(widget.id)
    elseif kind == "disabled" then widget.instance.enabled = false; host:Rebuild()
    elseif kind == "rebuild" then host:Rebuild()
    elseif kind == "character" then host.characterKey = "Another character"
    elseif kind == "database" then host.db = MenubarModel.Initialize(nil, host.characterKey)
    elseif kind == "profile" then
        assert(MenubarModel.CreateProfile(host.db, "Another profile"))
        MenubarModel.SetProfile(host.db, host.characterKey, "Another profile")
    elseif kind == "settings" then widget.instance.settings = {}
    elseif kind == "definition" then host.types[widget.instance.type] = {}
    elseif kind == "runtime" then host.runtime[widget.id] = nil end
end

check("every ordinary widget responder rejects changed owners and stale sessions", function()
    for _, kind in ipairs({ "closed", "other menu", "removed", "disabled", "rebuild", "character",
        "database", "profile", "settings", "definition", "runtime" }) do
        local f = fixture(); f.host:GetProfile().placement = "both"; f.host:Rebuild()
        local actions = responders(f:widgetMenu())
        change(f, kind)
        local database, opened = MenubarModel.DeepCopy(f.host.db), 0
        f.host.UI.OpenWidget = function() opened = opened + 1 end
        for _, action in ipairs(actions) do
            if action.selected then equal(action.selected(), false) end
            action.callback()
        end
        same(f.host.db, database); equal(opened, 0)
    end
end)

check("Core menu placement and add actions reject changed sessions database character and profile", function()
    for _, kind in ipairs({ "closed", "other menu", "rebuild", "character", "database", "profile" }) do
        local f = fixture(); local actions = responders(f:barMenu())
        change(f, kind)
        local database, opened = MenubarModel.DeepCopy(f.host.db), 0
        f.host.UI.OpenSettings = function() opened = opened + 1 end
        f.host.UI.OpenWidget = function() opened = opened + 1 end
        for _, action in ipairs(actions) do action.callback() end
        same(f.host.db, database); equal(opened, 0)
    end
end)

check("current widget actions retain their behavior and a completed action cannot replay", function()
    local f = fixture(); local duplicate = f.Stub.MenuItem(f:widgetMenu(), "Duplicate").callback
    duplicate(); equal(#f.host:SidebarInstances(), 2)
    duplicate(); equal(#f.host:SidebarInstances(), 2)
    local menu = f:widgetMenu(); local align = f.Stub.MenuItem(menu, "Alignment")
    f.Stub.MenuItem(align, "Right").callback(); equal(f.widget.instance.alignment, "right")
    f.Stub.MenuItem(f:widgetMenu(), "Remove from bar").callback()
    equal(MenubarModel.GetWidget(f.host.db, f.host.characterKey, f.widget.id), nil)
end)

check("a failed widget can still open its configuration from its current menu", function()
    local f = fixture(); f.widget.failed = "Expected fixture error"
    f.Stub.MenuItem(f:widgetMenu(), "Configure...").callback()
    equal(f.host.UI.widgetID, f.widget.id)
    assert(f.host.UI.window:IsVisible())
end)

check("current Core menu can change placement and add a widget once", function()
    local f = fixture(); local submenu = f.Stub.MenuItem(f:barMenu(), "Show bars")
    f.Stub.MenuItem(submenu, "Both").callback(); equal(f.host:GetProfile().placement, "both")
    local add = f.Stub.MenuItem(f:barMenu(), "Add widget")
    local choose = f.Stub.MenuItem(add, "Menu probe").callback
    choose(); equal(#f.host:SidebarInstances(), 2)
    choose(); equal(#f.host:SidebarInstances(), 2)
end)

check("overflow widget responders reject a removed hidden instance", function()
    local f = fixture(); f.host:AddWidget("menu-probe")
    local bar = f.host.bars.top; assert(#bar.hiddenWidgets > 0)
    local hiddenID = bar.hiddenWidgets[1].id
    bar.overflow:Click()
    local overflow = f.Stub.menus[#f.Stub.menus]
    local duplicate = f.Stub.MenuItem(overflow.children[1], "Duplicate").callback
    f.host:RemoveWidget(hiddenID)
    local before = #f.host:SidebarInstances(); duplicate()
    equal(#f.host:SidebarInstances(), before)
end)

check("native root release invalidates cursor and bar tokens without invalidating a replacement menu", function()
    for _, anchored in ipairs({ false, true }) do
        local f = fixture(); local owner = anchored and f.widget.frame or UIParent
        local token = f.host.UI:Context(owner, function(menu) menu:CreateTitle("Old menu") end)
        local old = f.Stub.menus[#f.Stub.menus]; local frame = old.menuFrame
        equal(f.host.UI.contextToken, token)
        Menu.GetManager():CloseMenus(); equal(f.host.UI.contextToken, nil)
        local replacement = f.host.UI:Context(owner, function(menu) menu:CreateTitle("Replacement") end)
        for _, release in ipairs(old.released) do release(frame) end
        equal(f.host.UI.contextToken, replacement)
        Menu.GetManager():CloseMenus(); equal(f.host.UI.contextToken, nil)
    end
end)

check("blank bar clicks stay inert while the main control toggles without rebuilding its closing menu", function()
    local f = fixture({ nativeMouseHandler = true }); local bar = f.host.bars.top
    local before = f:descriptionCount()
    f:pointerClick(bar, "LeftButton"); f:pointerClick(bar, "RightButton")
    equal(f:descriptionCount(), before); equal(Menu.GetManager():GetOpenMenu(), nil)
    assert(not f.host.UI.window or not f.host.UI.window:IsVisible())
    local calls = #f.nativeCalls
    f:pointerClick(bar.menu, "LeftButton")
    equal(f:descriptionCount(), before + 1)
    local first = f.Stub.menus[#f.Stub.menus]; local frame = first.menuFrame
    local stale = f.Stub.MenuItem(f.Stub.MenuItem(first, "Show bars"), "Both").callback
    local clamp = { frame:GetClampRectInsets() }
    assert(clamp[1] ~= 0 or clamp[2] ~= 0 or clamp[3] ~= 0 or clamp[4] ~= 0)
    f:pointerClick(bar.menu, "LeftButton")
    equal(f:descriptionCount(), before + 1)
    equal(Menu.GetManager():GetOpenMenu(), nil); equal(f.host.UI.contextToken, nil)
    same({ frame:GetClampRectInsets() }, { 0, 0, 0, 0 })
    local database = MenubarModel.DeepCopy(f.host.db); stale(); same(f.host.db, database)
    f:pointerClick(bar.menu, "LeftButton")
    equal(f:descriptionCount(), before + 2)
    assert(Menu.GetManager():GetOpenMenu()); assert(f.Stub.menus[#f.Stub.menus] ~= first)
    stale(); same(f.host.db, database)
    -- Only the second, exact-owner mouse-down bypasses the inherited handler.
    equal(#f.nativeCalls, calls + 2)
end)

check("Core global mouse handling delegates other owners menus buttons events and native return values", function()
    local options = { nativeMouseHandler = true }
    local f = fixture(options); local bar = f.host.bars.top
    f:pointerClick(bar.menu, "LeftButton")
    local calls = #f.nativeCalls
    equal(f:mouseDown(bar, "LeftButton"), false)
    equal(#f.nativeCalls, calls + 1); equal(f.nativeCalls[#f.nativeCalls].owner, bar)
    equal(Menu.GetManager():GetOpenMenu(), nil)
    local before = f:descriptionCount(); bar:Click("LeftButton")
    equal(f:descriptionCount(), before); equal(Menu.GetManager():GetOpenMenu(), nil)
    bar.menu:Click("LeftButton"); local active = Menu.GetManager():GetOpenMenu(); assert(active)
    equal(f:mouseDown(bar.menu, "LeftButton", "GLOBAL_MOUSE_UP"), false)
    equal(Menu.GetManager():GetOpenMenu(), active)
    equal(f.nativeCalls[#f.nativeCalls].event, "GLOBAL_MOUSE_UP")
    equal(f:mouseDown(bar.menu, "RightButton"), false)
    equal(f.nativeCalls[#f.nativeCalls].button, "RightButton")
    equal(Menu.GetManager():GetOpenMenu(), nil)
    bar.menu:Click("RightButton"); assert(f.host.UI.window:IsVisible())
    f.host.UI.window:Hide()
    f.host.UI:Context(UIParent, function(menu) menu:CreateTitle("Another owner's menu") end)
    calls = #f.nativeCalls
    equal(f:mouseDown(bar.menu, "LeftButton"), false)
    equal(#f.nativeCalls, calls + 1); equal(Menu.GetManager():GetOpenMenu(), nil)
    f:pointerClick(bar.menu, "LeftButton")
    equal(f:mouseDown(UIParent, "LeftButton"), false); equal(Menu.GetManager():GetOpenMenu(), nil)
    options.nativeResult = true; calls = #f.nativeCalls
    equal(f:mouseDown(bar.menu, "RightButton", "GLOBAL_MOUSE_UP"), true)
    equal(#f.nativeCalls, calls + 1)
    equal(f.nativeCalls[#f.nativeCalls].owner, bar.menu)
end)

check("programmatic Core clicks toggle and a stale token cannot intercept the next native mouse-down", function()
    local f = fixture({ nativeMouseHandler = true }); local owner = f.host.bars.top.menu
    local before = f:descriptionCount()
    owner:Click("LeftButton"); owner:Click("LeftButton"); owner:Click("LeftButton")
    equal(f:descriptionCount(), before + 2); assert(Menu.GetManager():GetOpenMenu())
    f.host.UI.contextToken = {} -- The root still exists, but no longer owns this session.
    local calls = #f.nativeCalls
    equal(f:mouseDown(owner, "LeftButton"), false)
    equal(#f.nativeCalls, calls + 1); equal(Menu.GetManager():GetOpenMenu(), nil)
    owner:Click("LeftButton"); equal(f:descriptionCount(), before + 3)
    assert(Menu.GetManager():GetOpenMenu())
end)

print(passed .. " ordinary-menu lifecycle tests passed")
