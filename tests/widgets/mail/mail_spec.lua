-- Original provider tests; the fixtures model verified Blizzard tuple positions.
local root = REPO_ROOT or "."
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, callback)
    local ok, reason = pcall(callback)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function fixture()
    local f = { frames = {}, rows = {}, loaded = 0, total = 0, presence = true,
        presenceReads = 0, headerReads = 0, itemReads = 0, measurements = 0, measureCreations = 0,
        iconCreations = 0, jiggles = 0, stops = 0 }
    local function forbidden() error("Restricted value was used", 0) end
    f.secret = setmetatable({}, { __tostring = forbidden, __eq = forbidden, __lt = forbidden,
        __le = forbidden, __add = forbidden, __sub = forbidden, __mul = forbidden, __div = forbidden })
    local env = setmetatable({}, { __index = _G }); f.env = env
    env.issecretvalue = function(value) return rawequal(value, f.secret) end
    env.CreateFrame = function()
        local frame = { events = {}, scripts = {} }; f.frames[#f.frames + 1] = frame
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:SetScript(name, callback) self.scripts[name] = callback end
        function frame:Hide() self.hidden = true end
        return frame
    end
    env.HasNewMail = function()
        f.presenceReads = f.presenceReads + 1
        if f.presenceError then error("native pending-mail error", 0) end
        return f.presence
    end
    env.GetInboxNumItems = function()
        if f.inboxError then error("native inbox error", 0) end
        return f.loaded, f.total
    end
    env.GetInboxHeaderInfo = function(index)
        f.headerReads = f.headerReads + 1
        if f.headerError then error("native header error", 0) end
        local row = f.rows[index]
        if not row or row.missing then return end
        return nil, row.icon or "Interface\\MailFrame\\Mail-Icon", nil, nil, 0, 0, 30, row.stacks, row.read
    end
    env.HasInboxItem = function(index, slot)
        local row = f.rows[index]
        if row.itemFlag ~= nil then return row.itemFlag end
        return row.items and row.items[slot] ~= nil or false
    end
    env.GetInboxItem = function(index, slot)
        f.itemReads = f.itemReads + 1
        if f.itemError then error("native attachment error", 0) end
        return "Item", 123, 456, f.rows[index].items[slot], 1, true, false
    end
    for _, name in ipairs({ "CheckInbox", "GetInboxText", "TakeInboxItem", "TakeInboxMoney", "SendMail", "DeleteInboxItem", "ReturnInboxItem" }) do
        env[name] = function() error("Mail observer must never mutate the mailbox: " .. name, 0) end
    end
    env.Menubar = { RegisterWidgetType = function(_, definition) f.provider = definition end }
    local chunk = assert(loadfile(root .. "/src/menubar-mail/Mail.lua")); setfenv(chunk, env); chunk()
    function f:emit(event)
        for _, frame in ipairs(self.frames) do
            if frame.events[event] then frame.scripts.OnEvent(frame, event) end
        end
    end
    function f:open()
        self:emit("MAIL_SHOW"); self:emit("MAIL_INBOX_UPDATE")
    end
    local function measureText(text, size)
        local units = 0
        local plain = text:gsub("|A(.-)|a", function(body)
            units = units + (tonumber(body:match("^[^:]+:[^:]+:([^:]+)")) or 16)
            return ""
        end)
        for character in plain:gmatch(".") do
            units = units + (character == "8" and 10 or character == "1" and 2 or character == " " and 3 or 6) * size / 12
        end
        return units
    end
    function f:widget()
        local widget = { settings = {}, font = "Font", size = 12, flags = "" }
        widget.label = { GetFont = function() return widget.font, widget.size, widget.flags end }
        function widget.label:ClearAllPoints() self.points = {} end
        function widget.label:SetPoint(...) self.points[#self.points + 1] = { ... } end
        function widget.label:SetJustifyH(value) self.justify = value end
        function widget.label:SetText(value) self.text = value end
        widget.frame = { CreateFontString = function()
            f.measureCreations = f.measureCreations + 1
            local region = {}
            function region:Hide() self.hidden = true end
            function region:SetWordWrap() end
            function region:SetFont(_, size)
                if f.fontFailure == "false" then return false end
                if f.fontFailure == "nil" then return nil end
                self.size = size; return true
            end
            function region:SetText(text) self.text = text end
            function region:GetStringWidth()
                f.measurements = f.measurements + 1
                return measureText(self.text, self.size)
            end
            return region
        end }
        if not f.noTexture then
            function widget.frame:CreateTexture()
                f.iconCreations = f.iconCreations + 1
                local region = {}
                function region:Hide() self.hidden = true end
                function region:Show() self.hidden = false end
                function region:ClearAllPoints() self.points = {} end
                function region:SetPoint(...) self.points[#self.points + 1] = { ... } end
                function region:SetSize(width, height) self.width, self.height = width, height end
                function region:SetAtlas(atlas)
                    if f.atlasError then error("native atlas error", 0) end
                    if f.atlasFailure then return false end
                    self.atlas = f.atlasMismatch and "unrelated-atlas" or atlas
                    return true
                end
                function region:GetAtlas() return self.atlas end
                return region
            end
        end
        function widget:SetWidth(width) self.width, self.customWidth = width, width end
        function widget:SetText(text) self.text = text; self.label:SetText(text) end
        function widget:JiggleIcon(icon) equal(icon, self.mailIcon); f.jiggles = f.jiggles + 1 end
        function widget:StopIconJiggle() f.stops = f.stops + 1 end
        function widget:fits() assert(self.width >= measureText(self.text, self.size) + 8) end
        f.provider.update(widget)
        return widget
    end
    function f:event(widget, event, hostFirst)
        if not hostFirst then self:emit(event) end
        self.provider.update(widget)
        self.provider.event(widget, event)
        if hostFirst then self:emit(event) end
    end
    function f:text(widget)
        self.provider.update(widget)
        return widget.text:match("|a (.*)$")
    end
    function f:tooltip(widget)
        local tip = { lines = {} }
        function tip:AddLine(...) self.lines[#self.lines + 1] = { ... } end
        function tip:AddDoubleLine(...) self.lines[#self.lines + 1] = { ... } end
        self.provider.tooltip(widget, tip)
        return tip
    end
    return f
end
local function row(tip, title)
    for _, line in ipairs(tip.lines) do if line[1] == title then return line[2] end end
end

check("native envelope and remote presence never claim an exact unread total", function()
    local f = fixture(); local widget = f:widget()
    assert(widget.text:find("|A:ui-hud-minimap-mail-icon:", 1, true)); equal(f:text(widget), "1+")
    local tip = f:tooltip(widget)
    equal(row(tip, "New mail"), "1+")
    equal(row(tip, "Unread messages"), nil)
    equal(row(tip, "Attachment stacks"), nil)
    equal(row(tip, "Attached items (units)"), nil)
    equal(#tip.lines, 4)
    assert(tip.lines[4][1]:find("1+ means mail is waiting", 1, true))
    f.presence = 1; equal(f:text(widget), "1+")
    f.presence = false; equal(f:text(widget), "0")
    f.presence = nil; equal(f:text(widget), "0")
    equal(f.headerReads, 0); equal(f.itemReads, 0)
    equal(row(f:tooltip(widget), "Attachment stacks"), nil)
end)

check("missing, throwing, malformed and restricted presence stays unknown and recovers", function()
    local f = fixture(); local widget = f:widget()
    for _, value in ipairs({ f.secret, "1", 0, -1, math.huge }) do
        f.presence = value; equal(f:text(widget), "--")
    end
    f.presenceError = true; equal(f:text(widget), "--")
    f.presenceError, f.env.HasNewMail = false, false; equal(f:text(widget), "--")
    f.env.HasNewMail = function() return false end; equal(f:text(widget), "0")
end)

check("mailbox loading and closure cannot expose cached exact counts", function()
    local f = fixture(); f.rows = { { read = false }, { read = true } }; f.loaded, f.total = 2, 2
    local widget = f:widget(); f:emit("MAIL_SHOW")
    equal(f:text(widget), "--"); equal(f.headerReads, 0)
    f:emit("MAIL_INBOX_UPDATE"); equal(f:text(widget), "1")
    f:emit("MAIL_CLOSED"); equal(f:text(widget), "1+")
    f:emit("MAIL_INBOX_UPDATE"); equal(f:text(widget), "1+")
    f:emit("MAIL_SHOW"); equal(f:text(widget), "--")
end)

check("loaded mail uses native nil unread flags and separates stack and unit counts", function()
    local f = fixture(); f.rows = {
        { stacks = 2, items = { [1] = 5, [7] = 3 } },
        { read = false }, { read = true, stacks = 1, items = { [16] = 20 } }, { read = 1 },
    }; f.loaded, f.total = 4, 4; f:open()
    local widget = f:widget(); equal(f:text(widget), "2")
    local tip = f:tooltip(widget)
    equal(row(tip, "Unread messages"), "2")
    equal(row(tip, "Inbox (loaded / total)"), "4 / 4")
    equal(row(tip, "Attachment stacks"), "3"); equal(row(tip, "Attached items (units)"), "28")
    equal(f.itemReads, 3); equal(f.presenceReads, 0)
end)

check("partial inboxes show lower bounds and complete empty inboxes retain zero", function()
    local f = fixture(); f.rows = { {}, {} }; f.loaded, f.total = 2, 200; f:open()
    local widget = f:widget(); equal(f:text(widget), "2+")
    local tip = f:tooltip(widget)
    equal(row(tip, "Unread messages"), "2+")
    equal(row(tip, "Attachment stacks"), "0+")
    assert(tip.lines[#tip.lines][1]:find("+ marks a minimum", 1, true))
    f.loaded = 0; equal(f:text(widget), "0+")
    f.total = 0; equal(f:text(widget), "0")
    equal(row(f:tooltip(widget), "Attached items (units)"), "0")
end)

check("invalid inbox containers and bounds never enter an unbounded header scan", function()
    local f = fixture(); f:open(); local widget = f:widget()
    for _, value in ipairs({ f.secret, -1, 0.5, math.huge, 0 / 0, 1001 }) do
        f.loaded, f.total = value, value; equal(f:text(widget), "--")
    end
    f.loaded, f.total = 2, 1; equal(f:text(widget), "--")
    f.inboxError = true; equal(f:text(widget), "--")
    f.inboxError, f.env.GetInboxNumItems = false, false; equal(f:text(widget), "--")
    equal(f.headerReads, 0); equal(f.presenceReads, 0)
end)

check("missing or restricted headers remain unknown rather than falling back to presence", function()
    local f = fixture(); f.loaded, f.total = 1, 1; f:open(); local widget = f:widget()
    equal(f:text(widget), "--")
    for _, record in ipairs({ { missing = true }, { read = f.secret }, { read = "false" }, { icon = f.secret } }) do
        f.rows = { record }; equal(f:text(widget), "--")
    end
    f.rows = { {} }; f.headerError = true; equal(f:text(widget), "--")
    f.headerError = false; equal(f:text(widget), "1"); equal(f.presenceReads, 0)
end)

check("restricted attachment headers do not reconstruct counts through attachment APIs", function()
    local f = fixture(); f.rows = { { stacks = f.secret, items = { [1] = 4 } } }; f.loaded, f.total = 1, 1; f:open()
    local widget = f:widget(); equal(f:text(widget), "1")
    local tip = f:tooltip(widget)
    equal(row(tip, "Attachment stacks"), "--"); equal(row(tip, "Attached items (units)"), "--")
    equal(f.itemReads, 0)
end)

check("attachment loading, restrictions, mutation and failures preserve independent unread counts", function()
    local f = fixture(); f.rows = { { stacks = 1, items = { [9] = 4 } } }; f.loaded, f.total = 1, 1; f:open()
    local widget = f:widget()
    for _, quantity in ipairs({ f.secret, 0, -1, 1.5, math.huge }) do
        f.rows[1].items[9] = quantity; equal(row(f:tooltip(widget), "Attached items (units)"), "--")
        equal(f:text(widget), "1")
    end
    f.rows[1].items[9], f.rows[1].itemFlag = 4, f.secret
    equal(row(f:tooltip(widget), "Attached items (units)"), "--")
    f.rows[1].itemFlag, f.itemError = nil, true
    equal(row(f:tooltip(widget), "Attached items (units)"), "--")
    f.itemError, f.rows[1].stacks = false, 2
    equal(row(f:tooltip(widget), "Attached items (units)"), "--")
    f.rows[1].stacks = 1; equal(row(f:tooltip(widget), "Attached items (units)"), "4")
end)

check("mail events while no widget exists and duplicate instances use one bounded observer", function()
    local f = fixture(); f.rows = { {} }; f.loaded, f.total = 1, 1; f:open()
    local first, second = f:widget(), f:widget(); equal(f:text(first), "1"); equal(f:text(second), "1")
    equal(#f.frames, 1); f:emit("MAIL_CLOSED")
    equal(f:text(first), "1+"); equal(f:text(second), "1+"); equal(#f.frames, 1)
end)

check("proportional fonts reserve every bounded count and reuse the measuring region", function()
    local f = fixture(); f:open(); local widget = f:widget(); local width, measurements = widget.width, f.measurements
    for _, value in ipairs({ 0, 1, 11, 888, 999, 1000 }) do
        f.loaded, f.total = value, value; f.rows = {}
        for index = 1, value do f.rows[index] = {} end
        f:text(widget); equal(widget.width, width); widget:fits()
    end
    equal(f:text(widget), "999+"); equal(row(f:tooltip(widget), "Unread messages"), "1000")
    equal(f.measurements, measurements); equal(f.measureCreations, 1)
    widget.font, widget.size = "Other font", 20; f:text(widget); widget:fits()
    assert(widget.width > width); equal(f.measureCreations, 1)
    widget.customWidth = nil; f:text(widget); widget:fits(); equal(f.measureCreations, 1)
end)

check("a native font failure never caches an unverified width and retries with its retained region", function()
    local f = fixture(); local widget = f:widget(); local measure = widget.mailMeasure
    local originalSizing = widget.mailSizing
    widget.font = "Different font"
    for _, failure in ipairs({ "false", "nil" }) do
        f.fontFailure = failure
        local ok, reason = pcall(f.provider.update, widget)
        equal(ok, false); equal(reason, "Mail font measurement is unavailable")
        equal(widget.mailSizing, originalSizing); equal(widget.mailMeasure, measure)
    end
    f.fontFailure = nil; f.provider.update(widget)
    equal(widget.mailSizing.path, "Different font"); equal(widget.mailMeasure, measure)
    equal(f.measureCreations, 1); widget:fits()
end)

check("the owned envelope preserves aspect ratio and stable sizing while only the number occupies its label", function()
    local f = fixture(); local widget = f:widget(); local icon, width = widget.mailIcon, widget.width
    assert(icon and not icon.hidden); equal(icon.atlas, "ui-hud-minimap-mail-icon")
    equal(icon.width / icon.height, 4 / 3); equal(widget.label.text, "1+")
    assert(widget.text:find("|A:ui-hud-minimap-mail-icon:", 1, true))
    f.presence = false; f:text(widget); equal(widget.label.text, "0"); equal(widget.width, width)
    widget.size = 20; f:text(widget)
    equal(widget.mailIcon, icon); equal(f.iconCreations, 1); equal(f.measureCreations, 1)
    equal(icon.width / icon.height, 4 / 3); widget:fits(); equal(f.jiggles, 0)
end)

check("unavailable native envelope capabilities retain inline display and retry the owned texture", function()
    local f = fixture(); f.atlasFailure = true; local widget = f:widget(); local icon = widget.mailIcon
    assert(icon.hidden); equal(widget.mailIconReady, false); equal(widget.label.text, widget.text)
    f.atlasFailure, f.atlasMismatch = false, true; f:text(widget)
    equal(widget.mailIconReady, false); equal(widget.label.text, widget.text)
    f.atlasMismatch, f.atlasError = false, true; f:text(widget); equal(widget.label.text, widget.text)
    f.atlasError = false; f:text(widget); equal(widget.mailIcon, icon); equal(f.iconCreations, 1)
    equal(widget.mailIconReady, true); equal(widget.label.text, "1+")
    f = fixture(); f.noTexture = true; widget = f:widget()
    equal(widget.mailIcon, nil); equal(widget.label.text, widget.text)
end)

check("pending-mail invalidations jiggle only a known remote absence becoming presence", function()
    local f = fixture(); f.presence = false; local widget = f:widget()
    f:event(widget, "UPDATE_PENDING_MAIL"); equal(f.jiggles, 0)
    f.presence = true; f:event(widget, "UPDATE_PENDING_MAIL"); equal(f.jiggles, 1)
    f:event(widget, "UPDATE_PENDING_MAIL"); equal(f.jiggles, 1)
    f.presence = false; f:event(widget, "UPDATE_PENDING_MAIL")
    f.presence = f.secret; f:event(widget, "UPDATE_PENDING_MAIL")
    f.presence = true; f:event(widget, "UPDATE_PENDING_MAIL"); equal(f.jiggles, 1)
    f.presence = false; f:text(widget)
    f.presence = true; f:text(widget); equal(f.jiggles, 1)
    f:event(widget, "UPDATE_PENDING_MAIL"); equal(f.jiggles, 2)
    local enabled = f:widget(); f:event(enabled, "UPDATE_PENDING_MAIL"); equal(f.jiggles, 2)
end)

check("complete same-session inbox growth is observed after seeding while unread changes and loading are quiet", function()
    local f = fixture(); local widget = f:widget()
    f.rows, f.loaded, f.total = { {} }, 1, 1
    f:event(widget, "MAIL_SHOW"); f:event(widget, "MAIL_INBOX_UPDATE"); equal(f.jiggles, 0)
    f.rows[2], f.loaded, f.total = {}, 2, 2
    f:text(widget); f:text(widget); equal(f.jiggles, 0)
    f:event(widget, "MAIL_INBOX_UPDATE"); equal(f.jiggles, 1)
    f.rows[1].read = true; f:event(widget, "MAIL_INBOX_UPDATE")
    f.rows[1].read = false; f:event(widget, "MAIL_INBOX_UPDATE"); equal(f.jiggles, 1)
    f.rows[3], f.loaded, f.total = {}, 2, 3
    f:event(widget, "MAIL_INBOX_UPDATE"); equal(f.jiggles, 1)
    f.loaded = 3; f:event(widget, "MAIL_INBOX_UPDATE"); equal(f.jiggles, 1)
    f.headerError = true; f:event(widget, "MAIL_INBOX_UPDATE")
    f.headerError = false; f.rows[4], f.loaded, f.total = {}, 4, 4
    f:event(widget, "MAIL_INBOX_UPDATE"); equal(f.jiggles, 1)
    f:event(widget, "MAIL_CLOSED"); f:event(widget, "MAIL_SHOW")
    f.rows[5], f.loaded, f.total = {}, 5, 5
    f:event(widget, "MAIL_INBOX_UPDATE"); equal(f.jiggles, 1)
end)

check("host-first lifecycle ordering seeds a new inbox session and resumes after loading without alerts", function()
    local f = fixture(); f.rows, f.loaded, f.total = { {} }, 1, 1; local widget = f:widget()
    f:event(widget, "MAIL_SHOW", true); f:text(widget)
    f:event(widget, "MAIL_INBOX_UPDATE", true); f:text(widget); equal(f.jiggles, 0)
    f.rows[2], f.loaded, f.total = {}, 2, 2
    f:event(widget, "MAIL_INBOX_UPDATE", true); equal(f.jiggles, 1)
    f:event(widget, "MAIL_CLOSED", true); f:text(widget)
    f:event(widget, "MAIL_SHOW", true); f:event(widget, "MAIL_INBOX_UPDATE", true)
    f:text(widget); equal(f.jiggles, 1); equal(#f.frames, 1)
end)

check("duplicate and recovering instances seed independently and missing old-host motion helpers are optional", function()
    local f = fixture(); f.presence = false; local first, second = f:widget(), f:widget()
    f.presence = true
    f:event(first, "UPDATE_PENDING_MAIL"); f:event(second, "UPDATE_PENDING_MAIL"); equal(f.jiggles, 2)
    f.provider.reset(first); assert(first.mailIcon.hidden); equal(first.mailWatch, nil)
    f:text(first); f:event(first, "UPDATE_PENDING_MAIL"); equal(f.jiggles, 2)
    f.provider.destroy(first); equal(first.mailWatch, nil); assert(first.mailIcon.hidden)
    second.JiggleIcon, second.StopIconJiggle = nil, nil
    f.presence = false; f:event(second, "UPDATE_PENDING_MAIL")
    f.presence = true; f:event(second, "UPDATE_PENDING_MAIL"); equal(f.jiggles, 2)
    f.provider.reset(second); equal(#f.frames, 1)
end)

print(passed .. " Mail public-contract tests passed")
