-- Own-project interoperability: actual For the Hoard Core/Movement/Colors and
-- actual Currency provider. The fixture's zero-height anchor is deliberately
-- invalid to expose the prior test gap; this is not proof of WoW rect behavior.
local root = REPO_ROOT or "."
local hoard = MENUBAR_HOARD_ROOT or root .. "/../for-the-hoard"
local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end
for _, file in ipairs({ "Core.lua", "Movement.lua", "Colors.lua" }) do
    if not exists(hoard .. "/src/ForTheHoard/" .. file) then
        print("SKIP For the Hoard integration: supply MENUBAR_HOARD_ROOT or the sibling checkout.")
        return
    end
end

local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.00001,
        "expected approximately " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end

local function fixture(order)
    local f = { frames = {}, anchorUpdates = 0 }
    local env = setmetatable({}, { __index = _G })
    env._G, env.SlashCmdList = env, {}
    env.ForTheHoardDB, env.ForTheHoardCharacterDB = nil, nil
    env.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
    env.issecretvalue = function() return false end
    env.canaccessvalue = function() return true end
    env.InCombatLockdown = function() return false end
    env.C_RestrictedActions = { CheckAllowProtectedFunctions = function() return true end }
    env.C_Container = { GetContainerItemInfo = function() return { isFiltered = false } end }
    env.GameTooltip, env.GamepadBagBar, env.ContainerFrameContainer = nil, nil, nil
    env.GetMoney = function() return 123456 end
    env.GetCursorPosition = function() return 500, 400 end
    local fractions = { TOPLEFT = { 0, 1 }, TOPRIGHT = { 1, 1 }, BOTTOMLEFT = { 0, 0 },
        BOTTOMRIGHT = { 1, 0 }, LEFT = { 0, 0.5 }, RIGHT = { 1, 0.5 },
        TOP = { 0.5, 1 }, BOTTOM = { 0.5, 0 }, CENTER = { 0.5, 0.5 } }
    local methods = {}
    function methods:GetObjectType() return self.kind end
    function methods:GetParent() return self.parent end
    function methods:SetParent(parent) self.parent = parent end
    function methods:GetName() return self.name end
    function methods:IsForbidden() return false end
    function methods:CanChangeProtectedState() return true end
    function methods:GetWidth() return self.width end
    function methods:GetHeight() return self.height end
    function methods:GetSize() return self.width, self.height end
    function methods:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
    function methods:GetFrameLevel() return self.level end
    function methods:SetFrameLevel(level) self.level = level end
    function methods:IsToplevel() return self.topLevel end
    function methods:SetToplevel(value) assert(type(value) == "boolean"); self.topLevel = value end
    function methods:GetFlattensRenderLayers() return self.flatten end
    function methods:SetFlattensRenderLayers(value) assert(type(value) == "boolean"); self.flatten = value end
    -- This fixture only exercises local grouping flags, not native overlap or
    -- inherited flattening. Its UIParent has no render-grouping state.
    function methods:GetEffectivelyFlattensRenderLayers() return self.flatten end
    function methods:Raise() self.raises = (self.raises or 0) + 1 end
    function methods:SetScript(script, callback) self.scripts[script] = callback end
    function methods:HookScript(script, callback)
        local hooks = self.hooks[script] or {}; self.hooks[script] = hooks
        hooks[#hooks + 1] = callback
        return true
    end
    function methods:Fire(script, ...)
        if self.scripts[script] then self.scripts[script](self, ...) end
        for _, callback in ipairs(self.hooks[script] or {}) do callback(self, ...) end
    end
    function methods:SetSize(width, height)
        local changed = self.width ~= width or self.height ~= height
        self.width, self.height = width, height
        if changed then self:Fire("OnSizeChanged", width, height) end
    end
    function methods:SetHeight(value) self:SetSize(self.width, value) end
    function methods:SetWidth(value) self:SetSize(value, self.height) end
    function methods:SetAlpha(value) self.alpha = value end
    function methods:GetAlpha() return self.alpha end
    function methods:EnableMouse(value) self.mouse = value end
    function methods:IsMouseEnabled() return self.mouse end
    function methods:RegisterForDrag(value) self.dragButton = value end
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:UnregisterAllEvents() self.events = {} end
    function methods:IsShown() return self.shown end
    function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function methods:Show()
        if not self.shown then self.shown = true; self:Fire("OnShow") end
    end
    function methods:Hide()
        if self.shown then self.shown = false; self:Fire("OnHide") end
    end
    function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function methods:ClearAllPoints() self.points = {} end
    function methods:SetPoint(point, relative, relativePoint, x, y)
        relative = relative or self.parent
        self.points[#self.points + 1] = { point, relative, relativePoint or point, x or 0, y or 0 }
    end
    function methods:GetPoint(index) return unpack(self.points[index or 1] or {}) end
    function methods:GetRect()
        -- Conservative regression model: a zero-sized anchor has no useful
        -- rectangle, so its anchored items cannot get valid decoration bounds.
        if self.width <= 0 or self.height <= 0 then return nil end
        if self == env.UIParent then return 0, 0, self.width, self.height end
        local point = self.points[1]
        if not point then
            if not self.parent then return 0, 0, self.width, self.height end
            local left, bottom = self.parent:GetRect()
            if not left then return nil end
            return left, bottom, self.width, self.height
        end
        local target = point[2]
        if not target then return nil end
        local left, bottom, width, height = target:GetRect()
        if not left then return nil end
        local own, relative = fractions[point[1]], fractions[point[3]]
        return left + width * relative[1] + point[4] - self.width * own[1],
            bottom + height * relative[2] + point[5] - self.height * own[2], self.width, self.height
    end
    function methods:IsRectValid() return self:GetRect() ~= nil end
    function methods:GetLeft() return self:GetRect() end
    function methods:GetTop() local _, bottom, _, height = self:GetRect(); return bottom and bottom + height end
    function methods:SetColorTexture(...) self.color = { ... } end
    function methods:GetBagID() return self.bagID end
    function methods:GetID() return self.slot end
    function methods:IsExtended() return false end
    function methods:Initialize(container, bagID, slot) self.parent, self.bagID, self.slot = container, bagID, slot end
    function methods:SetMatchesSearch(value) self.matchesSearch = value end
    function methods:UpdateItems() end
    function methods:UpdateItemSlots() end
    local function node(kind, name, parent)
        local result = setmetatable({ kind = kind, name = name, parent = parent, width = 100, height = 20,
            scale = 1, alpha = 1, mouse = false, shown = true, level = 10, topLevel = false, flatten = false,
            scripts = {}, hooks = {}, events = {}, points = {} }, { __index = methods })
        if name then env[name] = result end
        if kind ~= "Texture" then f.frames[#f.frames + 1] = result end
        return result
    end
    function methods:CreateTexture(name) return node("Texture", name, self) end
    env.CreateFrame = function(kind, name, parent) return node(kind, name, parent) end
    env.UIParent = node("Frame", "UIParent")
    env.UIParent:SetSize(1200, 900)
    local bag = node("Frame", "ContainerFrameCombinedBags", env.UIParent)
    bag.columns, bag.nativeMoneyHeight, bag.paddingHeight, bag.tokenHeight = 10, 16, 78, 18
    bag.Items = {}
    local money = node("Frame", nil, bag)
    bag.MoneyFrame = money
    money:SetSize(420, bag.nativeMoneyHeight)
    money:SetPoint("BOTTOMRIGHT", bag, "BOTTOMRIGHT", -8, 8 + bag.tokenHeight + 3)
    for _, key in ipairs({ "Border", "GoldButton", "SilverButton", "CopperButton", "trialErrorButton" }) do
        local child = node(key == "Border" and "Texture" or "Button", nil, money)
        child.mouse = key ~= "Border"
        if key == "trialErrorButton" then child:Hide() end
        money[key] = child
    end
    for index = 1, 30 do
        local item = node("Button", nil, bag)
        item:SetSize(37, 37)
        item.bagID, item.slot, item.mouse = math.floor((index - 1) / 10), (index - 1) % 10 + 1, true
        bag.Items[index] = item
    end
    function bag:CalculateHeight()
        local rows = math.ceil(#self.Items / self.columns)
        return rows * 37 + (rows - 1) * 5 + self.paddingHeight + self.tokenHeight + self.MoneyFrame:GetHeight()
    end
    function bag:UpdateFrameSize() self:SetSize(436, self:CalculateHeight()) end
    function bag:UpdateItemLayout()
        for index, item in ipairs(self.Items) do
            item:ClearAllPoints()
            item:SetPoint("BOTTOMRIGHT", self.MoneyFrame, "TOPRIGHT", -((index - 1) % self.columns) * 42,
                4 + math.floor((index - 1) / self.columns) * 42)
        end
    end
    function bag:EnumerateValidItems() return ipairs(self.Items) end
    function bag:IsBackpack() return false end
    function bag:IsCombinedBagContainer() return true end
    function bag:UpdateMoneyFrame() self.MoneyFrame:SetHeight(self.nativeMoneyHeight) end
    function bag:UpdateCurrencyFrames() self.MoneyFrame:Show() end
    env.MoneyFrame_UpdateMoney = function(frame)
        equal(frame, money)
        f.moneyUpdates = (f.moneyUpdates or 0) + 1
        frame:SetHeight(bag.nativeMoneyHeight)
        for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do frame[key]:Show() end
    end
    env.UpdateContainerFrameAnchors = function()
        f.anchorUpdates = f.anchorUpdates + 1
        bag:ClearAllPoints(); bag:SetPoint("BOTTOMRIGHT", env.UIParent, "BOTTOMRIGHT", -10, 85)
    end
    env.hooksecurefunc = function(target, method, callback)
        if type(target) == "string" then callback, method, target = method, target, env end
        local original = target[method]
        assert(type(original) == "function", "Native hook target must exist")
        target[method] = function(...)
            local values = { original(...) }
            callback(...)
            return unpack(values)
        end
    end
    bag:UpdateFrameSize(); bag:UpdateItemLayout(); env.UpdateContainerFrameAnchors()
    local provider
    env.Menubar = { RegisterWidgetType = function(_, definition) provider = definition end }
    local function loadSource(path, ...)
        local chunk = assert(loadfile(path)); setfenv(chunk, env); return chunk(...)
    end
    local function loadHoard()
        local addon = {}
        for _, file in ipairs({ "Core.lua", "Colors.lua", "Movement.lua" }) do
            loadSource(hoard .. "/src/ForTheHoard/" .. file, "ForTheHoard", addon)
        end
        addon:OnEvent("ADDON_LOADED", "ForTheHoard")
        assert(addon.savedReady)
        -- These scenarios test slot tints independently of product defaults.
        addon.db.appearance.mode = "tint"
        addon.char.position = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 120, y = -80 }
        addon:OnEvent("PLAYER_LOGIN")
        f.hoard = addon
    end
    local function loadCurrency()
        loadSource(root .. "/src/menubar-currency/Currency.lua")
        local settings = {}; for key, value in pairs(provider.defaults) do settings[key] = value end
        settings.hideBagMoney = false -- Explicit opt-out before each tested ownership transition.
        f.widget = { settings = settings, SetText = function(self, text) self.text = text end }
        f.provider = provider
        provider.update(f.widget)
    end
    function f:flush()
        for pass = 1, 4 do
            local count = #self.frames
            for index = 1, count do
                local frame = self.frames[index]
                if frame:IsVisible() and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.3) end
            end
        end
    end
    function f:request(value)
        self.widget.settings.hideBagMoney = value
        provider.update(self.widget)
        self:flush()
    end
    if order == "hoard-first" then
        loadHoard(); loadCurrency()
    else
        loadCurrency(); f:request(true); loadHoard()
    end
    f.env, f.bag, f.money = env, bag, money
    f.originalHeight = bag.paddingHeight + bag.tokenHeight + 3 * 37 + 2 * 5 + bag.nativeMoneyHeight
    f:flush()
    function f:assertPosition()
        near(bag:GetLeft(), 120); near(bag:GetTop(), 820)
        equal(bag:GetPoint(), "TOPLEFT")
        equal(self.hoard.char.position.x, 120); equal(self.hoard.char.position.y, -80)
    end
    function f:assertSlots()
        equal(#bag.Items, 30)
        local left, bottom, width, height = bag:GetRect()
        for index, item in ipairs(bag.Items) do
            equal(item:GetParent(), bag)
            equal(item.bagID, math.floor((index - 1) / 10))
            equal(item.slot, (index - 1) % 10 + 1)
            assert(item:IsVisible() and item:IsRectValid(), "Every native item needs a valid visible rectangle")
            local x, y, w, h = item:GetRect()
            assert(x >= left and x + w <= left + width and y >= bottom and y + h <= bottom + height - 60,
                "All native items must fit below the title/search region")
        end
    end
    function f:assertDecorations()
        self.hoard.Colors:Refresh()
        assert(not next(self.hoard.reports or {}), "For the Hoard must not report an interoperability failure")
        for _, item in ipairs(bag.Items) do
            local state = self.hoard.Colors.slots[item]
            assert(state and state.fill and state.fill:IsVisible(), "Actual slot tints must remain visible")
        end
    end
    return f
end

for _, order in ipairs({ "hoard-first", "currency-first" }) do
    check("For the Hoard positioning and slot colors survive Currency collapse: " .. order, function()
        local f = fixture(order)
        if order == "hoard-first" then
            equal(f.widget.settings.hideBagMoney, false)
            equal(f.money:IsShown(), true); equal(f.money:GetHeight(), 16)
            near(f.bag:GetHeight(), f.originalHeight)
            f:assertPosition(); f:assertSlots(); f:assertDecorations()
        end
        f:request(true)
        f:assertPosition(); f:assertSlots(); f:assertDecorations()
        equal(f.money:IsShown(), true)
        near(f.money:GetHeight(), 1)
        near(f.bag:GetHeight(), f.originalHeight - f.bag.nativeMoneyHeight + 1)
        for _, key in ipairs({ "Border", "GoldButton", "SilverButton", "CopperButton", "trialErrorButton" }) do
            equal(f.money[key]:IsVisible(), false)
        end
        f:assertPosition(); f:assertSlots(); f:assertDecorations()
        f.env.UpdateContainerFrameAnchors(); f:flush()
        f:assertPosition(); f:assertSlots(); f:assertDecorations()
        f:request(false)
        assert((f.moneyUpdates or 0) > 0, "Restoration must use the available native denomination updater")
        equal(f.money:IsShown(), true); equal(f.money:GetHeight(), f.bag.nativeMoneyHeight)
        near(f.bag:GetHeight(), f.originalHeight)
        for _, key in ipairs({ "Border", "GoldButton", "SilverButton", "CopperButton" }) do equal(f.money[key]:IsVisible(), true) end
        equal(f.money.trialErrorButton:IsShown(), false)
        f:assertPosition(); f:assertSlots(); f:assertDecorations()
    end)
end

check("native money refresh and group outlines coexist with the saved combined-bag position", function()
    local f = fixture("hoard-first")
    f:request(true)
    f.bag:UpdateMoneyFrame(); f.bag:UpdateCurrencyFrames()
    for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton", "Border" }) do f.money[key]:Show() end
    f.bag:UpdateFrameSize(); f.bag:UpdateItemLayout(); f.env.UpdateContainerFrameAnchors()
    f:flush()
    equal(f.money:IsShown(), true); near(f.money:GetHeight(), 1)
    f:assertPosition(); f:assertSlots(); f:assertDecorations()
    f.hoard.db.appearance.mode, f.hoard.db.appearance.outline = "outline", "groups"
    f.hoard.Colors:Refresh()
    local groups = f.hoard.Colors.containers[f.bag].groups
    equal(#groups, 3)
    for _, group in ipairs(groups) do assert(group:IsVisible(), "Actual grouped outlines stay visible") end
    f.provider.destroy(f.widget); f:flush()
    equal(f.money:GetHeight(), 16); near(f.bag:GetHeight(), f.originalHeight)
    f:assertPosition(); f:assertSlots()
end)

print(passed .. " For the Hoard interoperability tests passed")
