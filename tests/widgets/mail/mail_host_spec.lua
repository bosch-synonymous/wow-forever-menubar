local sourceDirectory = dofile((REPO_ROOT or ".") .. "/tests/source_paths.lua")
-- Real Menubar lifecycle and layout, with its shared native UI double.
local root = REPO_ROOT or "."
local core = MENUBAR_CORE_ROOT or root
local file = io.open(core .. "/tests/wow_stub.lua", "rb")
assert(file, "Mail host integration requires Menubar core; pass its root to the test runner")
file:close()
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, callback)
    local ok, reason = pcall(callback)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function loadAddon(repository, addon)
    local namespace = {}
    for line in io.lines(sourceDirectory(repository, addon) .. "/" .. addon .. ".toc") do
        local name = line:match("^%s*(.-)%s*$")
        if name:match("%.lua$") then assert(loadfile(sourceDirectory(repository, addon) .. "/" .. name))(addon, namespace) end
    end
end
local function fixture(presence, options)
    options = options or {}
    local Stub = dofile(core .. "/tests/wow_stub.lua"); Stub.Install()
    local f = { Stub = Stub, frames = {}, presence = true, rows = {}, loaded = 0, total = 0, shift = false }
    if presence ~= nil then f.presence = presence end
    MenubarDB = nil
    local nativeCreate = CreateFrame
    CreateFrame = function(...)
        local frame = nativeCreate(...); f.frames[#f.frames + 1] = frame
        if options.atlasReadback then
            local createTexture = frame.CreateTexture
            function frame:CreateTexture(...)
                local texture = createTexture(self, ...)
                local getAtlas = texture.GetAtlas
                function texture:GetAtlas()
                    local atlas = getAtlas(self)
                    return options.atlasReadback(atlas, f)
                end
                return texture
            end
        end
        return frame
    end
    f.secret = setmetatable({}, { __tostring = function() error("Restricted mail formatted", 0) end })
    issecretvalue = function(value) return rawequal(value, f.secret) end
    IsShiftKeyDown = function() return f.shift end
    HasNewMail = function() return f.presence end
    GetInboxNumItems = function() return f.loaded, f.total end
    GetInboxHeaderInfo = function(index)
        local row = f.rows[index]
        if row then return nil, 134332, nil, nil, 0, 0, 30, row.stacks, row.read end
    end
    HasInboxItem = function() return false end
    GetInboxItem = function() error("Empty attachment slots must not be read", 0) end
    CheckInbox = function() error("Widget must never refresh mailbox state", 0) end
    GetInboxText = function() error("Widget must never mark messages read", 0) end
    TakeInboxItem = function() error("Widget must never collect attachments", 0) end
    loadAddon(core, "Menubar")
    if options.atlasReadback then Menubar.ApplyThemeIcon = nil end -- Exercise older hosts with native artwork.
    Menubar:RegisterWidgetType({ id = "time", name = "Clock fixture", defaults = {},
        defaultPlacement = { bar = "top", alignment = "right" }, update = function(widget) widget:SetText("12:34") end })
    loadAddon(root, "Menubar_Mail")
    Menubar:Start(); f.host = Menubar
    function f:find(kind)
        for _, widget in pairs(self.host.runtime) do if widget.instance.type == kind then return widget end end
    end
    f.widget, f.clock = assert(f:find("mail")), assert(f:find("time"))
    f.widget.instance.order, f.clock.instance.order = 1, 2; f.host:Layout()
    function f:tick()
        self.host.eventFrame.scripts.OnUpdate(self.host.eventFrame, 1.1)
        for _, widget in pairs(self.host.runtime) do assert(not widget.failed, tostring(widget.failed)) end
    end
    function f:emit(event, hostFirst)
        local eventFrame = self.host.eventFrame
        if hostFirst and eventFrame.events[event] then eventFrame.scripts.OnEvent(eventFrame, event) end
        for _, frame in ipairs(self.frames) do
            if frame ~= eventFrame and frame.events and frame.events[event] and frame.scripts.OnEvent then
                frame.scripts.OnEvent(frame, event)
            end
        end
        if not hostFirst and eventFrame.events[event] then eventFrame.scripts.OnEvent(eventFrame, event) end
    end
    function f:observerCount()
        local count = 0
        for _, frame in ipairs(self.frames) do
            if frame ~= self.host.eventFrame and frame.events and frame.events.MAIL_SHOW then count = count + 1 end
        end
        return count
    end
    function f:text(widget) return (widget or self.widget).text:match("|a (.*)$") end
    function f:position(widget) return widget.frame.points[1][4] end
    return f
end

check("real host updates mail events and keeps its adjacent clock stable", function()
    local f = fixture(); equal(f:text(), "1+")
    local width, clockPosition = f.widget.width, f:position(f.clock)
    f.rows, f.loaded, f.total = { {}, { read = true } }, 2, 2
    f:emit("MAIL_SHOW"); equal(f:text(), "--")
    f:emit("MAIL_INBOX_UPDATE"); equal(f:text(), "1")
    f.rows[2].read = false; f:emit("MAIL_INBOX_UPDATE"); equal(f:text(), "2")
    f:emit("MAIL_CLOSED"); equal(f:text(), "1+")
    f.presence = false; f:emit("UPDATE_PENDING_MAIL"); equal(f:text(), "0")
    f.presence = f.secret; f:tick(); equal(f:text(), "--")
    equal(f.widget.width, width); equal(f:position(f.clock), clockPosition)
end)

check("host-first event delivery recovers within the one-second polling interval", function()
    local f = fixture(); f.rows, f.loaded, f.total = { {} }, 1, 1
    f:emit("MAIL_SHOW", true); f:tick(); equal(f:text(), "--")
    f:emit("MAIL_INBOX_UPDATE", true); f:tick(); equal(f:text(), "1")
    f:emit("MAIL_CLOSED", true); f:tick(); equal(f:text(), "1+")
end)

check("zero active Mail instances retain mailbox lifecycle with one addon observer", function()
    local f = fixture(); f.host:RemoveWidget(f.widget.id)
    equal(f:find("mail"), nil); equal(f:observerCount(), 1)
    f.rows, f.loaded, f.total = { {}, {} }, 2, 2
    f:emit("MAIL_SHOW"); f:emit("MAIL_INBOX_UPDATE")
    local instance = f.host:AddWidget("mail"); f.widget = f.host.runtime[instance.id]
    equal(f:text(), "2"); equal(f:observerCount(), 1)
    local other = f.host:AddWidget("mail"); equal(f:text(f.host.runtime[other.id]), "2")
    for _ = 1, 30 do f.host:Rebuild() end
    equal(f:observerCount(), 1)
    f:emit("MAIL_CLOSED"); equal(f:text(), "1+"); equal(f:text(f.host.runtime[other.id]), "1+")
end)

check("host render recovery and font rebuilds reuse owned measuring regions", function()
    local f = fixture(); local widget = f.widget; local measure = assert(widget.mailMeasure)
    local setText = widget.SetText
    widget.SetText = function() error("Mail rendering failed", 0) end
    f.host:RefreshWidget(widget.id); equal(widget.failed, "Mail rendering failed"); equal(widget.customWidth, nil)
    widget.SetText = setText; f.host:RefreshWidget(widget.id)
    equal(widget.failed, nil); equal(widget.mailMeasure, measure); equal(f:text(), "1+")
    f.host:GetProfile().fontSize = 22; f.host:Rebuild()
    equal(widget.mailMeasure, measure); assert(widget.width >= widget.label:GetStringWidth() + 8)
    equal(f:observerCount(), 1)
end)

check("plain clicking is quiet and native Menubar interactions remain available", function()
    local f = fixture(); local widget = f.widget; local menus = #f.Stub.menus
    widget.frame:Click("LeftButton"); equal(#f.Stub.menus, menus)
    f.shift = true; widget.frame:Click("LeftButton")
    equal(#f.Stub.menus, menus + 1); assert(f.Stub.MenuItem(f.Stub.menus[#f.Stub.menus], "Configure..."))
    widget.frame:Click("RightButton"); equal(f.host.UI.widgetID, widget.id)
    widget.frame.scripts.OnEnter(widget.frame); equal(GameTooltip:GetOwner(), widget.frame)
    equal(GameTooltip.lines[1][1], "Mail")
    equal(GameTooltip.lines[#GameTooltip.lines][1], "Shift-left-click: menu   Right-click: settings")
end)

check("a rejected glyph falls back to text without a button plate", function()
    local f = fixture(false)
    local icon = f.widget.mailIcon
    local apply = f.host.ApplyThemeIcon
    f.host.ApplyThemeIcon = function() return false end
    f.host:RefreshWidget(f.widget.id)
    equal(icon:IsShown(), false); equal(icon:GetAtlas(), nil)
    equal(f.widget.label:GetText(), "0")
    f.host.ApplyThemeIcon = apply
    f.host:RefreshWidget(f.widget.id)
    equal(icon:IsShown(), true); equal(f.widget.mailIcon, icon)
end)

check("mail arrivals animate the owned envelope while the count and neighboring clock stay anchored", function()
    local f = fixture(false); local widget = f.widget; local icon = assert(widget.mailIcon)
    local width, clockPosition = widget.width, f:position(f.clock)
    equal(icon.texCoords[1], 4 / 8); equal(widget.label.text, "0")
    equal(icon:GetWidth(), icon:GetHeight()); equal(widget.iconJiggle, nil)
    f.presence = true; f:tick(); f:tick(); equal(widget.iconJiggle, nil)
    f:emit("UPDATE_PENDING_MAIL")
    local motion = assert(widget.iconJiggle); equal(motion.icon, icon); equal(motion.group.parent, icon)
    equal(motion.group.plays, 1); equal(widget.label.text, "1+")
    local labelX = widget.label.points[1][4]
    f:emit("UPDATE_PENDING_MAIL"); f.host:RefreshWidget(widget.id); f.host:Rebuild(); f:tick()
    equal(motion.group.plays, 1); equal(widget.mailIcon, icon)
    equal(widget.width, width); equal(f:position(f.clock), clockPosition); equal(widget.label.points[1][4], labelX)
    motion.group:Finish(); f.presence = false; f:emit("UPDATE_PENDING_MAIL")
    f.presence = true; f:emit("UPDATE_PENDING_MAIL"); equal(motion.group.plays, 2)
    equal(f:observerCount(), 1)
end)

check("Mail keeps one animated envelope across Mac and Warcraft artwork changes", function()
    local f = fixture(false)
    local icon = f.widget.mailIcon
    local width = f.widget.width
    for index, theme in ipairs({ "system7", "macos8", "macosx", "macos27" }) do
        assert(MenubarModel.ApplyTheme(f.host:GetProfile(), theme))
        f.host:Rebuild()
        equal(f.widget.mailIcon, icon)
        equal(f.widget.width, width)
        equal(icon.texCoords[1], 4 / 8)
        equal(icon.texCoords[3], (index - 1) / 4)
        equal(icon:IsShown(), true)
    end
    f.presence = true; f:emit("UPDATE_PENDING_MAIL")
    equal(assert(f.widget.iconJiggle).icon, icon)
    assert(MenubarModel.ApplyTheme(f.host:GetProfile(), "warcraftBrown"))
    f.host:Rebuild()
    equal(icon.texCoords[1], 4 / 8); equal(icon.texCoords[3], 0)
    equal(icon.vertexColor[1], 1)
end)

check("new complete inbox sessions are quiet before observable complete growth in either event order", function()
    for _, hostFirst in ipairs({ false, true }) do
        local f = fixture(false); local widget = f.widget
        f.rows, f.loaded, f.total = { {} }, 1, 1
        f:emit("MAIL_SHOW", hostFirst); f:emit("MAIL_INBOX_UPDATE", hostFirst); f:tick()
        equal(widget.iconJiggle, nil)
        f.rows[2], f.loaded, f.total = {}, 2, 2
        f:tick(); f:tick(); equal(widget.iconJiggle, nil)
        f:emit("MAIL_INBOX_UPDATE", hostFirst)
        local motion = assert(widget.iconJiggle); equal(motion.group.plays, 1); motion.group:Finish()
        f.total = 3; f:emit("MAIL_INBOX_UPDATE", hostFirst)
        f.rows[3], f.loaded = {}, 3; f:emit("MAIL_INBOX_UPDATE", hostFirst)
        equal(motion.group.plays, 1)
        f:emit("MAIL_CLOSED", hostFirst); f:emit("MAIL_SHOW", hostFirst)
        f.rows[4], f.loaded, f.total = {}, 4, 4
        f:emit("MAIL_INBOX_UPDATE", hostFirst); f:tick(); equal(motion.group.plays, 1)
    end
end)

check("hidden removed and failed Mail instances stop motion and recovery cannot replay an arrival", function()
    local f = fixture(false); local widget = f.widget
    f.presence = true; f:emit("UPDATE_PENDING_MAIL"); local group = assert(widget.iconJiggle).group
    widget.frame:Hide(); equal(group.playing, false)
    f.presence = false; f:emit("UPDATE_PENDING_MAIL")
    f.presence = true; f:emit("UPDATE_PENDING_MAIL"); equal(group.plays, 1)
    f.host:Layout(); equal(group.plays, 1)
    f.presence = false; f:emit("UPDATE_PENDING_MAIL")
    f.presence = true; f:emit("UPDATE_PENDING_MAIL"); equal(group.plays, 2)
    local setText = widget.SetText; widget.SetText = function() error("Mail display failed", 0) end
    f.host:RefreshWidget(widget.id); equal(widget.failed, "Mail display failed")
    equal(group.playing, false); equal(widget.mailIcon:IsShown(), false)
    widget.SetText = setText; f.host:RefreshWidget(widget.id)
    equal(widget.failed, nil); equal(widget.mailIcon:IsShown(), true); equal(group.plays, 2)
    f:emit("UPDATE_PENDING_MAIL"); equal(group.plays, 2)
    f.presence = false; f:emit("UPDATE_PENDING_MAIL")
    f.presence = true; f:emit("UPDATE_PENDING_MAIL"); equal(group.plays, 3)
    f.host:RemoveWidget(widget.id); equal(group.playing, false); equal(widget.mailIcon:IsShown(), false)
    equal(f:observerCount(), 1)
end)

check("duplicate and re-enabled Mail widgets keep independent bounded envelope motion", function()
    local f = fixture(false); local instance = f.host:AddWidget("mail"); local other = f.host.runtime[instance.id]
    f.presence = true; f:emit("UPDATE_PENDING_MAIL")
    local first, second = assert(f.widget.iconJiggle), assert(other.iconJiggle)
    assert(first.icon ~= second.icon); equal(first.group.plays, 1); equal(second.group.plays, 1)
    local allocations = #f.Stub.animations
    for _ = 1, 20 do f:emit("UPDATE_PENDING_MAIL"); f.host:Rebuild() end
    equal(#f.Stub.animations, allocations); equal(first.group.plays, 1); equal(second.group.plays, 1)
    f.host:RemoveWidget(other.id)
    local replacement = f.host:AddWidget("mail"); local fresh = f.host.runtime[replacement.id]
    equal(fresh.iconJiggle, nil); f:emit("UPDATE_PENDING_MAIL"); equal(fresh.iconJiggle, nil)
    equal(f:observerCount(), 1)
end)

check("canonical atlas capitalization keeps the owned envelope visible and new mail animates it", function()
    local f = fixture(false, { atlasReadback = function(atlas) return atlas and atlas:upper() end })
    local widget, icon = f.widget, f.widget.mailIcon
    equal(icon:GetAtlas(), "UI-HUD-MINIMAP-MAIL-ICON")
    equal(widget.mailIconReady, true); equal(icon:IsVisible(), true); equal(widget.label:GetText(), "0")
    equal(widget.iconJiggle, nil)
    local width, position = widget.width, f:position(f.clock)
    f.presence = true; f:emit("UPDATE_PENDING_MAIL")
    local motion = assert(widget.iconJiggle)
    equal(motion.icon, icon); equal(motion.group.parent, icon); equal(motion.group.plays, 1)
    equal(motion.group:IsPlaying(), true); equal(icon:IsVisible(), true)
    equal(widget.label:GetText(), "1+"); equal(widget.width, width); equal(f:position(f.clock), position)
    motion.group:Finish(); f:emit("UPDATE_PENDING_MAIL"); f:tick()
    equal(motion.group.plays, 1); equal(#f.Stub.animations, 1)
end)

check("different missing and restricted atlas readbacks retain Mail fallback and recover without replay", function()
    for _, mode in ipairs({ "different", "missing", "restricted" }) do
        local fallback = true
        local f = fixture(false, { atlasReadback = function(atlas, state)
            if not fallback then return atlas and atlas:upper() end
            if mode == "different" then return "another-mail-icon" end
            if mode == "restricted" then return state.secret end
        end })
        local widget, icon = f.widget, f.widget.mailIcon
        equal(widget.failed, nil); equal(widget.mailIconReady, false); equal(icon:IsShown(), false)
        assert(widget.label:GetText():find("|A:", 1, true), "Inline envelope remains readable")
        f.presence = true; f:emit("UPDATE_PENDING_MAIL"); equal(widget.iconJiggle, nil)
        fallback = false; f.host:RefreshWidget(widget.id)
        equal(widget.mailIcon, icon); equal(widget.mailIconReady, true); equal(icon:IsVisible(), true)
        f:emit("UPDATE_PENDING_MAIL"); equal(widget.iconJiggle, nil)
        f.presence = false; f:emit("UPDATE_PENDING_MAIL")
        f.presence = true; f:emit("UPDATE_PENDING_MAIL")
        equal(widget.iconJiggle.icon, icon); equal(widget.iconJiggle.group.plays, 1)
        equal(widget.failed, nil)
    end
end)

print(passed .. " Mail actual-host tests passed")
