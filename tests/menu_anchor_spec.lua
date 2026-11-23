local sourceDirectory = dofile((REPO_ROOT or ".") .. "/tests/source_paths.lua")
-- Native menu entry points and bar geometry through the real host. The small
-- SetPoint/scale model checks requested bounds, not C++ rendering or input.
local root = REPO_ROOT or "."
local passed = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function exists(path)
    local file = io.open(path, "rb"); if not file then return false end
    file:close(); return true
end
local function loadAddon(repository, addon)
    for line in io.lines(sourceDirectory(repository, addon) .. "/" .. addon .. ".toc") do
        local name = line:match("^%s*(.-)%s*$")
        if name:match("%.lua$") then assert(loadfile(sourceDirectory(repository, addon) .. "/" .. name))(addon, {}) end
    end
end
local volumeRoot = MENUBAR_VOLUME_ROOT or root
local hasVolume = exists(volumeRoot .. "/src/menubar-volume/Menubar_Volume.toc")

local function fixture(options)
    options = options or {}
    local Stub = dofile(root .. "/tests/wow_stub.lua"); Stub.Install()
    local f = { Stub = Stub, shift = false, contextCalls = 0, contextDepth = 0, opened = {}, anchors = {}, callbacks = {}, styles = {},
        choices = { { value = "a", label = "A" }, { value = "b", label = "B" } }, audioWrites = 0,
        audio = { Sound_MasterVolume = "0.4", Sound_EnableAllSound = "1" },
        art = options.art or { left = 3, right = 3, top = 3, bottom = 4 } }
    MenubarDB, issecretvalue = nil, nil
    IsShiftKeyDown = function() return f.shift end
    C_CVar = {
        GetCVar = function(name) return f.audio[name] end,
        SetCVar = function(name, value) f.audioWrites = f.audioWrites + 1; f.audio[name] = tostring(value); return true end,
    }
    UIParent:SetSize(options.width or 1280, options.height or 720)
    UIParent:SetScale(options.scale or 1)
    if options.insets then
        local style = { GetInset = function() return options.insets end }
        MenuVariants.GetDefaultContextMenuMixin = function() return style end
    end
    local Region = getmetatable(UIParent)
    local function factor(point, low, high)
        if point:find(low, 1, true) then return 0 end
        if point:find(high, 1, true) then return 1 end
        return 0.5
    end
    function Region:GetRect()
        local width, height = self:GetWidth(), self:GetHeight()
        if self == UIParent then return 0, 0, width, height end
        local point = self.points[1]
        if not point then return 0, 0, width, height end
        local relative, relativePoint, x, y
        if type(point[2]) == "table" then
            relative = point[2]
            if type(point[3]) == "string" then relativePoint, x, y = point[3], point[4] or 0, point[5] or 0
            else relativePoint, x, y = point[1], point[3] or 0, point[4] or 0 end
        else relative, relativePoint, x, y = self:GetParent() or UIParent, point[1], point[2] or 0, point[3] or 0 end
        local left, bottom, wide, tall = relative:GetRect()
        local ratio = relative:GetEffectiveScale() / self:GetEffectiveScale()
        return (left + factor(relativePoint, "LEFT", "RIGHT") * wide) * ratio + x - factor(point[1], "LEFT", "RIGHT") * width,
            (bottom + factor(relativePoint, "BOTTOM", "TOP") * tall) * ratio + y - factor(point[1], "BOTTOM", "TOP") * height,
            width, height
    end
    function Region:IsRectValid() return true end
    function Region:GetLeft() local left = self:GetRect(); return left end
    function Region:GetRight() local left, _, width = self:GetRect(); return left + width end
    function Region:GetBottom() local _, bottom = self:GetRect(); return bottom end
    function Region:GetTop() local _, bottom, _, height = self:GetRect(); return bottom + height end
    function Region:GetCenter() local left, bottom, width, height = self:GetRect(); return left + width / 2, bottom + height / 2 end

    -- Record public native arguments without relying on private stub fields.
    local createAnchor = assert(AnchorUtil and AnchorUtil.CreateAnchor)
    AnchorUtil.CreateAnchor = function(point, relativeTo, relativePoint, x, y)
        local anchor = createAnchor(point, relativeTo, relativePoint, x, y)
        f.anchors[anchor] = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x or 0, y = y or 0 }
        return anchor
    end
    local createDescription = assert(MenuUtil.CreateRootMenuDescription)
    MenuUtil.CreateRootMenuDescription = function(style)
        local description = createDescription(style)
        local addCallback = assert(description.AddMenuAcquiredCallback)
        f.callbacks[description], f.styles[description] = {}, style
        description.AddMenuAcquiredCallback = function(self, callback)
            f.callbacks[description][#f.callbacks[description] + 1] = callback
            return addCallback(self, callback)
        end
        return description
    end
    local context = MenuUtil.CreateContextMenu
    MenuUtil.CreateContextMenu = function(...)
        f.contextCalls, f.contextDepth = f.contextCalls + 1, f.contextDepth + 1
        local menu = context(...)
        f.contextDepth = f.contextDepth - 1
        return menu
    end
    local manager = assert(Menu and Menu.GetManager and Menu.GetManager())
    local open = assert(manager.OpenMenu)
    manager.OpenMenu = function(self, owner, description, anchor)
        local record = { owner = owner, description = description, anchor = anchor, cursor = f.contextDepth > 0 }
        f.opened[#f.opened + 1] = record
        record.menu = open(self, owner, description, anchor)
        return record.menu
    end

    loadAddon(root, "Menubar"); f.host = Menubar
    f.host:RegisterWidgetType({ id = "anchor-choice", name = "Anchor choice", defaults = { choice = "a" },
        defaultPlacement = { bar = "top", alignment = "left" },
        settings = { { key = "choice", label = "Choice", type = "select", options = function() return f.choices end } },
        update = function(widget) widget:SetText("Choice") end,
        click = function(widget) widget:OpenChoiceMenu("choice", "Choose") end,
        contextMenu = function(_, description) description:CreateButton("Widget action", function() f.actions = (f.actions or 0) + 1 end) end,
    })
    if options.volume and hasVolume then loadAddon(volumeRoot, "Menubar_Volume") end
    f.host:Start()
    for _, widget in pairs(f.host.runtime) do
        if widget.instance.type == "anchor-choice" then f.widget = widget
        elseif widget.instance.type == "volume" then f.volume = widget end
    end
    f.host:GetProfile().placement = options.placement or "top"
    f.host:GetProfile().coreMenuBar = "both"
    f.host:Rebuild()
    function f:click(owner, shift)
        local before = #self.opened
        self.shift = shift == true; owner:Click("LeftButton"); self.shift = false
        assert(not self.widget.failed, tostring(self.widget.failed))
        assert(#self.opened > before, "A bar menu must use the anchored native manager path")
        local record = self.opened[#self.opened]
        equal(record.owner, owner, "native menu lifetime keeps its actual owner")
        equal(record.cursor, false, "bar menus must not use the cursor context-menu entry point")
        assert(self.anchors[record.anchor], "A bar menu needs an explicit native anchor")
        return record
    end
    function f:side(record, side)
        local anchor = assert(self.anchors[record.anchor])
        local reference = assert(anchor.relativeTo)
        local _, bottom, _, height = reference:GetRect()
        local referenceScale = reference:GetEffectiveScale()
        local target = (bottom + factor(anchor.relativePoint, "BOTTOM", "TOP") * height) * referenceScale
            + anchor.y * UIParent:GetEffectiveScale()
        local bar = self.host.bars[side]
        if side == "top" then
            assert(anchor.point:find("TOP", 1, true), "Top-bar menus must grow downwards")
            assert(target <= bar:GetBottom() * bar:GetEffectiveScale(), "The menu starts below the actual bar edge")
        else
            assert(anchor.point:find("BOTTOM", 1, true), "Bottom-bar menus must grow upwards")
            assert(target >= bar:GetTop() * bar:GetEffectiveScale(), "The menu starts above the actual bar edge")
        end
        return anchor
    end
    function f:acquire(record, scale)
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetScale((scale or UIParent:GetEffectiveScale()) / UIParent:GetEffectiveScale())
        function frame:SetClampRectInsets(left, right, top, bottom) self.clamp = { left, right, top, bottom } end
        local callbacks = assert(self.callbacks[record.description])
        assert(#callbacks > 0, "The native acquired-menu callback must constrain the entire menu tree")
        for _, callback in ipairs(callbacks) do callback(frame) end
        local clamp = assert(frame.clamp, "Native acquired menus need a safe clamp region")
        equal(clamp[1], -self.art.left); equal(clamp[2], self.art.right)
        if self.host.bars.top:IsShown() then assert(clamp[3] * frame:GetEffectiveScale() >= self.host.bars.top:GetHeight() * self.host.bars.top:GetEffectiveScale()) end
        if self.host.bars.bottom:IsShown() then assert(-clamp[4] * frame:GetEffectiveScale() >= self.host.bars.bottom:GetHeight() * self.host.bars.bottom:GetEffectiveScale()) end
        return frame, clamp
    end
    function f:bounds(record, width, contentHeight, description, initialBottom)
        description = description or record.description
        local frame, clamp = self:acquire(record)
        local scale = frame:GetEffectiveScale()
        local insets = assert(self.styles[record.description]:GetInset())
        local cap = description.scrollHeight or contentHeight
        assert(type(cap) == "number" and cap > 0, "The native content-height budget must be positive")
        local height = math.min(contentHeight, cap) + insets.top + insets.bottom
        local anchor = assert(self.anchors[record.anchor])
        local reference = anchor.relativeTo
        local left, bottom, wide, tall = reference:GetRect()
        local referenceScale = reference:GetEffectiveScale()
        local targetX = (left + factor(anchor.relativePoint, "LEFT", "RIGHT") * wide) * referenceScale + anchor.x * scale
        local targetY = (bottom + factor(anchor.relativePoint, "BOTTOM", "TOP") * tall) * referenceScale + anchor.y * scale
        left = targetX - factor(anchor.point, "LEFT", "RIGHT") * width * scale
        bottom = initialBottom or (targetY - factor(anchor.point, "BOTTOM", "TOP") * height * scale)
        local screenScale = UIParent:GetEffectiveScale()
        local screenWidth, screenHeight = UIParent:GetWidth() * screenScale, UIParent:GetHeight() * screenScale
        local minimumY, maximumY = -clamp[4] * scale, screenHeight - clamp[3] * scale
        assert(height * scale <= maximumY - minimumY + 0.00001, "Insets plus capped content must fit the native clamp region")
        -- Native's clamp envelope has these signed inset semantics. This small
        -- final-bounds model deliberately does not emulate native flip/layout.
        left = math.max(-clamp[1] * scale, math.min(left, screenWidth - clamp[2] * scale - width * scale))
        bottom = math.max(minimumY, math.min(bottom, maximumY - height * scale))
        local outerLeft, outerRight = left - self.art.left * scale, left + (width + self.art.right) * scale
        assert(outerLeft >= -0.00001 and outerRight <= screenWidth + 0.00001)
        -- These native-style artwork outsets are separate from content insets.
        local outerBottom, outerTop = bottom - self.art.bottom * scale, bottom + (height + self.art.top) * scale
        if self.host.bars.top:IsShown() then
            assert(outerTop <= self.host.bars.top:GetBottom() * self.host.bars.top:GetEffectiveScale() + 0.00001,
                "The menu's outer artwork must stay below the top bar")
        end
        if self.host.bars.bottom:IsShown() then
            assert(outerBottom >= self.host.bars.bottom:GetTop() * self.host.bars.bottom:GetEffectiveScale() - 0.00001,
                "The menu's outer artwork must stay above the bottom bar")
        end
        return { left = outerLeft, right = outerRight, bottom = outerBottom, top = outerTop }
    end
    return f
end

check("quick selectors use their effective top or bottom bar and retain Shift-click placement", function()
    for _, placement in ipairs({ "top", "bottom", "both" }) do
        local f = fixture({ placement = placement })
        for _, savedBar in ipairs({ "top", "bottom" }) do
            f.widget.instance.bar = savedBar; f.host:Rebuild()
            local effective = placement == "both" and savedBar or placement
            f:side(f:click(f.widget.frame), effective)
            local shiftMenu = f:click(f.widget.frame, true)
            f:side(shiftMenu, effective)
            assert(f.Stub.MenuItem(shiftMenu.description, "Move earlier"))
        end
    end
end)

check("core and overflow menus stay outside each bar while empty-space clicks open nothing", function()
    local f = fixture({ placement = "both" })
    for _, side in ipairs({ "top", "bottom" }) do
        local bar = f.host.bars[side]
        f:side(f:click(bar.menu), side)
        local before = #f.opened
        bar:Click("LeftButton"); bar:Click("RightButton")
        equal(#f.opened, before)
        bar.hiddenWidgets = { { id = f.widget.id } }; bar.overflow:Show()
        local menu = f:click(bar.overflow)
        f:side(menu, side)
        assert(#menu.description.children > 0)
    end
end)

check("acquired root menus and submenus exclude both bars at differing menu scales", function()
    local f = fixture({ placement = "both", scale = 1.25 })
    local record = f:click(f.host.bars.top.menu)
    f:side(record, "top")
    f:acquire(record, 1.25)
    -- The verified native callback is shared by every menu in the tree and is
    -- invoked once with that pooled menu's proxy after scale is established.
    f:acquire(record, 0.75)
    assert(f.Stub.MenuItem(record.description, "Add widget"))
end)

check("left and right edge owners keep short menus inside the screen at different UI scales", function()
    for _, scale in ipairs({ 0.75, 1.25 }) do
        local f = fixture({ placement = "both", width = 800, height = 600, scale = scale })
        for _, side in ipairs({ "top", "bottom" }) do
            for _, alignment in ipairs({ "left", "right" }) do
                MenubarModel.MoveWidget(f.host.db, f.host.characterKey, f.widget.id, side, alignment)
                f.host:Rebuild()
                local record = f:click(f.widget.frame)
                local anchor = f:side(record, side)
                assert(anchor.point:find(alignment:upper(), 1, true), "The menu should align with its owner's available horizontal edge")
                f:bounds(record, 280, 48)
            end
        end
    end
end)

check("tall root and nested menus use inset-aware budgets without crossing either visible bar", function()
    local f = fixture({ placement = "both", width = 640, height = 240 })
    f.host.UI:Context(f.widget.frame, function(description)
        description:SetScrollMode(400)
        local nested = description:CreateButton("Nested choices"); nested:SetScrollMode(400)
        for index = 1, 80 do
            description:CreateButton("Choice " .. index, function() end)
            nested:CreateButton("Subchoice " .. index, function() end)
        end
    end)
    local record = assert(f.opened[#f.opened])
    local nested = f.Stub.MenuItem(record.description, "Nested choices")
    assert(record.description.scrollHeight < 400 and nested.scrollHeight < 400)
    f:side(record, "top"); f:bounds(record, 240, 2000)
    f:bounds(record, 240, 2000, nested, UIParent:GetHeight())
    f.host:GetProfile().placement = "bottom"; f.host:Rebuild()
    for index = 3, 30 do f.choices[index] = { value = tostring(index), label = "Choice " .. index } end
    record = f:click(f.widget.frame); f:side(record, "bottom"); f:bounds(record, 240, 2000)
    local large = fixture({ height = 1200 })
    for index = 3, 30 do large.choices[index] = { value = tostring(index), label = "Choice " .. index } end
    local capped = large:click(large.widget.frame)
    equal(capped.description.scrollHeight, 400, "A smaller provider scroll limit must be retained")
end)

check("native menu variants keep their full artwork inside the screen and outside both bars", function()
    local variants = {
        { insets = { left = 16, right = 16, top = 10, bottom = 10 }, art = { left = 3, right = 3, top = 3, bottom = 4 } },
        { insets = { left = 14, right = 14, top = 14, bottom = 14 }, art = { left = 3, right = 3, top = 1, bottom = 4 } },
        { insets = { left = 8, right = 8, top = 8, bottom = 15 }, art = { left = 10, right = 10, top = 3, bottom = 3 } },
        { insets = { left = 3, right = 3, top = 6, bottom = 7 }, art = { left = 17, right = 17, top = 12, bottom = 22 } },
    }
    for _, variant in ipairs(variants) do
        variant.placement, variant.width, variant.height = "both", 640, 240
        local f = fixture(variant)
        for index = 3, 30 do f.choices[index] = { value = tostring(index), label = "Choice " .. index } end
        for _, side in ipairs({ "top", "bottom" }) do
            MenubarModel.MoveWidget(f.host.db, f.host.characterKey, f.widget.id, side, "right")
            f.host:Rebuild()
            local record = f:click(f.widget.frame)
            f:side(record, side); f:bounds(record, 240, 2000)
        end
    end
end)

check("settings selectors use native dropdowns and invalidate older bar choices", function()
    local f = fixture(); local settings = f.widget.settings
    local older = f:click(f.widget.frame)
    local choose = f.Stub.MenuItem(older.description, "B").callback
    f.host.UI:OpenWidget(f.widget.id)
    local control
    for _, candidate in ipairs(f.host.UI.window.controls) do if candidate.caption == "Choice" then control = candidate; break end end
    assert(control, "The ordinary native settings selector must remain available")
    local before = f.contextCalls; control:OpenMenu()
    equal(f.contextCalls, before)
    assert(control:IsMenuOpen(), "The native dropdown must open its own menu")
    choose(); equal(settings.choice, "a")
    local latest = f:click(f.widget.frame)
    f.Stub.MenuItem(latest.description, "B").callback(); equal(settings.choice, "b")
    f.Stub.MenuItem(latest.description, "A").callback(); equal(settings.choice, "b")
end)

check("release and rebuild restore pooled native clamps while bar anchors remain bounded and reusable", function()
    local f = fixture({ placement = "both" }); local manager = Menu.GetManager()
    local function unclamped(frame)
        local values = { frame:GetClampRectInsets() }
        for index = 1, 4 do equal(values[index], 0, "released native clamp inset") end
    end
    local first = f:click(f.widget.frame); local native = first.menu
    local oldChoose = f.Stub.MenuItem(first.description, "B").callback
    f.host:Rebuild(); equal(f.host.UI.barMenuSession, nil); equal(native:IsShown(), false); unclamped(native)
    oldChoose(); equal(f.widget.settings.choice, "a")
    f.widget.instance.bar = "bottom"; f.host:Rebuild()
    equal(f:click(f.widget.frame).menu, native)
    manager:CloseMenus(); equal(f.host.UI.barMenuSession, nil); unclamped(native)
    MenuUtil.CreateContextMenu(UIParent, function(_, description) description:CreateButton("Other menu", function() end) end)
    equal(f.opened[#f.opened].menu, native); equal(f.opened[#f.opened].cursor, true); unclamped(native)
    f.host.UI:OpenWidget(f.widget.id)
    local control
    for _, candidate in ipairs(f.host.UI.window.controls) do if candidate.caption == "Choice" then control = candidate; break end end
    assert(control); control:OpenMenu(); unclamped(native); manager:CloseMenus()
    local topAnchor, bottomAnchor = f.host.UI.menuAnchors.top, f.host.UI.menuAnchors.bottom
    assert(topAnchor and bottomAnchor and topAnchor ~= bottomAnchor)
    local frames = #f.Stub.frames
    for _ = 1, 8 do
        for _, side in ipairs({ "top", "bottom" }) do
            f.widget.instance.bar = side; f.host:Rebuild()
            equal(f:click(f.widget.frame).menu, native)
            manager:CloseMenus(); unclamped(native)
        end
    end
    equal(#f.Stub.frames, frames, "repeated bar menus reuse both anchors and the native menu pool")
    equal(f.host.UI.menuAnchors.top, topAnchor); equal(f.host.UI.menuAnchors.bottom, bottomAnchor)
    local count = 0; for _ in pairs(f.host.UI.menuAnchors) do count = count + 1 end
    equal(count, 2)
end)

if hasVolume then
    check("Volume uses the same outside-bar anchor while retaining visible vertical controls and audio", function()
        for _, side in ipairs({ "top", "bottom" }) do
            local f = fixture({ placement = side, volume = true })
            local record = f:click(f.volume.frame)
            f:side(record, side)
            local description
            for _, child in ipairs(record.description.children) do if child.kind == "Frame" then description = child; break end end
            assert(description, "The native Volume controls must be retained")
            local frame = CreateFrame("Frame", nil, UIParent); local before = #f.Stub.frames
            for _, initialize in ipairs(description.initializers) do initialize(frame, description, record.description) end
            local slider
            for index = before + 1, #f.Stub.frames do if f.Stub.frames[index].kind == "Slider" then slider = f.Stub.frames[index]; break end end
            assert(slider and slider:IsVisible()); equal(slider.orientation, "VERTICAL")
            equal(f.audioWrites, 0); equal(f.audio.Sound_MasterVolume, "0.4")
            f.Stub.DragSlider(slider, 20); equal(tonumber(f.audio.Sound_MasterVolume), 0.8)
        end
    end)
else print("SKIP real Volume anchor integration: restore Menubar_Volume under this clone's src/ directory.") end

print(passed .. " bar-menu anchor tests passed")
