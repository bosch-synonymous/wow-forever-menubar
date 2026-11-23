-- Real startup and recovery navigation; private reader tests cover pure input cases.
local root = REPO_ROOT or "."
local passed = 0
local function equal(actual, expected) assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
local function check(label, run)
    local ok, reason = pcall(run); if not ok then error(label .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. label)
end
local function layout(label)
    return { profile = "Custom", marker = label, widgets = {
        { id = "w7", type = "example", settings = { label = label, nested = { chosen = true } }, alignment = "left", bar = "top" },
    } }
end
local function fixture(saved, options)
    options = options or {}
    local Stub = dofile(root .. "/tests/wow_stub.lua"); Stub.Install()
    local f = { Stub = Stub, guid = options.pending and nil or "Player-123-ABC", surname = "Surname", realm = options.realm }
    -- An explicit branch matters: nil is the pending state, not a falsey ternary fallback.
    if options.pending then f.guid = nil end
    UnitGUID = function() return f.guid end
    UnitName = function() return "Testplayer", f.surname end
    GetUnitName = function() return "Testplayer " .. f.surname end
    GetRealmName = function() return f.realm or "" end
    MenubarDB = saved
    for line in io.lines(root .. "/src/menubar-core/Menubar.toc") do
        local file = line:match("^%s*(.-)%s*$")
        if file:match("%.lua$") then assert(loadfile(root .. "/src/menubar-core/" .. file))("Menubar", {}) end
    end
    f.host = Menubar
    Menubar:RegisterWidgetType({ id = "example", name = "Example", defaults = { label = "New" },
        update = function(widget) widget:SetText(widget.settings.label) end })
    function f:emit(event) self.host.eventFrame:GetScript("OnEvent")(self.host.eventFrame, event) end
    function f:login() self:emit("PLAYER_LOGIN") end
    function f:choice(label)
        SlashCmdList.MENUBAR("recover")
        return assert(self.Stub.MenuItem(self.Stub.menus[#self.Stub.menus], label)).callback
    end
    return f
end
check("observed first-name empty-realm settings migrate at actual login without resetting widgets", function()
    local previous, alternative = layout("Current"), layout("Alternate")
    local saved = { profiles = { Custom = { height = 31 } }, characters = {
        ["Testplayer - "] = previous, ["Testplayer Surname - "] = alternative,
    } }
    local f = fixture(saved); f:login(); assert(f.host.ready)
    equal(f.host.characterKey, "guid:Player-123-ABC"); equal(f.host.runtime.w7.text, "Current")
    equal(f.host:GetProfile().height, 31)
    equal(saved.characters["Testplayer - "], previous); equal(saved.characters["Testplayer Surname - "], alternative)
    local current = saved.characters[f.host.characterKey]
    assert(current ~= previous and current.widgets[1].settings ~= previous.widgets[1].settings)
    current.widgets[1].settings.nested.chosen = false
    equal(previous.widgets[1].settings.nested.chosen, true)
    current.widgets[1].settings.label = "Updated"
    local again = fixture(saved, { realm = "Changed Realm" }); again:login()
    equal(again.host.runtime.w7.text, "Updated")
end)
check("pending identity preserves saved state and starts when world or combat-exit metadata becomes readable", function()
    local f = fixture(nil, { pending = true }); f:login()
    equal(f.host.ready, nil); equal(MenubarDB, nil)
    local messages = #f.Stub.messages; f:emit("PLAYER_ENTERING_WORLD"); equal(#f.Stub.messages, messages)
    equal(MenubarDB, nil)
    f.guid = "Player-123-ABC"; f:emit("PLAYER_REGEN_ENABLED")
    assert(f.host.ready and f.host.db); equal(f.host.characterKey, "guid:Player-123-ABC")
end)
check("ambiguous histories offer a native recovery choice that copies only the selected layout", function()
    local alpha, beta = layout("Alpha"), layout("Beta")
    local saved = { profiles = { Custom = {} }, characters = { ["Testplayer - A"] = alpha, ["Testplayer - B"] = beta } }
    local f = fixture(saved); f:login(); equal(f.host.ready, nil)
    equal(saved.characters["guid:Player-123-ABC"], nil)
    local choose = f:choice("Testplayer - B"); choose()
    assert(f.host.ready); equal(f.host.runtime.w7.text, "Beta")
    equal(saved.characters["Testplayer - A"], alpha); equal(saved.characters["Testplayer - B"], beta)
    choose(); equal(f.host.runtime.w7.text, "Beta")
end)
check("closed recovery menus and changed databases cannot apply retained layout choices", function()
    local function saved()
        return { profiles = { Custom = {} }, characters = { ["Testplayer - A"] = layout("Alpha"), ["Testplayer - B"] = layout("Beta") } }
    end
    local data = saved(); local f = fixture(data); f:login()
    local choose = f:choice("Testplayer - A"); Menu.GetManager():CloseMenus(); choose()
    equal(f.host.ready, nil); equal(data.characters["guid:Player-123-ABC"], nil)
    choose = f:choice("Testplayer - B"); MenubarDB = saved(); choose()
    equal(f.host.ready, nil); equal(data.characters["guid:Player-123-ABC"], nil)
    equal(MenubarDB.characters["guid:Player-123-ABC"], nil)
end)
check("future saved schemas remain untouched and do not retry or overwrite settings", function()
    local previous = layout("Future")
    local saved = { schemaVersion = 999, characters = { ["Testplayer - "] = previous } }
    local f = fixture(saved); f:login(); local messages = #f.Stub.messages
    f:emit("PLAYER_ENTERING_WORLD"); equal(#f.Stub.messages, messages)
    equal(f.host.ready, nil); equal(f.host.db, nil); equal(saved.schemaVersion, 999)
    equal(saved.characters["Testplayer - "], previous); equal(saved.characters["guid:Player-123-ABC"], nil)
end)
print(passed .. " character startup and recovery checks passed")
