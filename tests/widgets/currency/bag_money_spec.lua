-- Native footer contracts modeled independently from the controller.
-- Positive reference dimensions are required by this fixture's rectangle model.
-- That models the zero-anchor failure hypothesis; it is not native-engine proof.
-- This tests geometry/lifetimes, not native rendering, protected frames or taint.
local root = REPO_ROOT or "."
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1
    print("PASS " .. name)
end

local function fixture(options)
    options = options or {}
    local f = { effects = {}, monitors = {}, restricted = {}, combat = false, anchors = 0 }
    local function node(name, height, shown, parent, borrowed)
        local value = { name = name, height = height or 0, width = 200, shown = shown ~= false,
            parent = parent, borrowed = borrowed ~= false, permission = true, mouse = true, hooks = {}, scripts = {} }
        local function effect(self, operation, argument)
            if self.borrowed then f.effects[#f.effects + 1] = { self, operation, argument } end
        end
        function value:RunScript(script, ...)
            if self.scripts[script] then self.scripts[script](self, ...) end
            for _, callback in ipairs(self.hooks[script] or {}) do callback(self, ...) end
        end
        function value:SetScript(script, callback) self.scripts[script] = callback end
        function value:HookScript(script, callback)
            self.hooks[script] = self.hooks[script] or {}
            self.hooks[script][#self.hooks[script] + 1] = callback
        end
        function value:GetName() return self.name end
        function value:GetParent() return self.parent end
        function value:CanChangeProtectedState() return self.permission end
        function value:IsShown() return self.shown end
        function value:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
        function value:nativeShow()
            effect(self, "show")
            local changed = not self.shown
            self.shown = true
            if changed then self:RunScript("OnShow") end
        end
        function value:nativeHide()
            effect(self, "hide")
            local changed = self.shown
            self.shown = false
            if changed then self:RunScript("OnHide") end
        end
        function value:Show()
            assert(not self.referenceAnchor, "Addon must leave the native MoneyFrame shown policy alone")
            self:nativeShow()
        end
        function value:Hide()
            assert(not self.referenceAnchor, "Addon must not hide the grid's MoneyFrame anchor")
            self:nativeHide()
        end
        function value:SetShown(shown) if shown then self:Show() else self:Hide() end end
        function value:GetHeight() return self.height end
        function value:GetWidth() return self.width end
        function value:IsRectValid() return not self.referenceAnchor or self.height > 0 end
        function value:GetRect()
            if not self:IsRectValid() then return nil end
            return self.left or 0, self.bottom or 0, self.width, self.height
        end
        function value:SetHeight(height)
            effect(self, "height", height)
            local changed = self.height ~= height
            self.height = height
            if self.anchorGeometry then self.anchorGeometry() end
            if changed then self:RunScript("OnSizeChanged", self.width, height) end
        end
        function value:SetSize(width, height)
            effect(self, "size", height)
            local changed = self.width ~= width or self.height ~= height
            self.width, self.height = width, height
            if changed then self:RunScript("OnSizeChanged", width, height) end
        end
        function value:GetAlpha() return 1 end
        function value:SetAlpha() error("Footer collapse must not change alpha") end
        function value:IsMouseEnabled() return self.mouse end
        function value:EnableMouse() error("Hiding individual money content must not rewrite input settings") end
        function value:CanReceiveMouse() return self.mouse and self:IsVisible() end
        function value:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
        function value:UnregisterEvent(event) if self.events then self.events[event] = nil end end
        function value:UnregisterAllEvents() self.events = {} end
        return value
    end
    f.node = node
    local function bag(name, moneyHeight, count, columns, padding)
        local value = node(name, 1, not options.closed)
        value.nativeMoneyHeight, value.columns, value.padding, value.tokenHeight = moneyHeight, columns, padding, 0
        value.MoneyFrame = node(name .. "MoneyFrame", moneyHeight, true, value)
        value.MoneyFrame.referenceAnchor, value.nativeMoneyShown = true, true
        value.MoneyFrame.Border = node(name .. "MoneyBorder", 17, true, value.MoneyFrame)
        value.MoneyFrame.GoldButton = node(name .. "GoldButton", 13, true, value.MoneyFrame)
        value.MoneyFrame.SilverButton = node(name .. "SilverButton", 13, true, value.MoneyFrame)
        value.MoneyFrame.CopperButton = node(name .. "CopperButton", 13, true, value.MoneyFrame)
        value.MoneyFrame.trialErrorButton = node(name .. "TrialError", 13, false, value.MoneyFrame)
        value.MoneyFrame.PrefixText = node(name .. "Prefix", 13, true, value.MoneyFrame)
        value.MoneyFrame.SuffixText = node(name .. "Suffix", 13, false, value.MoneyFrame)
        value.nativeChildShown = { Border = true, GoldButton = true, SilverButton = true,
            CopperButton = true, trialErrorButton = false, PrefixText = true, SuffixText = false }
        value.TokenTracker = node(name .. "TokenTracker", 0, false, value)
        value.Items, value.originalItems = {}, {}
        for index = 1, count do
            local item = { id = index, parent = value }
            function item:IsShown() return true end
            function item:IsVisible() return self.parent:IsVisible() end
            function item:IsRectValid() return self.rectValid == true end
            function item:GetRect()
                if not self:IsRectValid() then return nil end
                return self.left, self.bottom, 37, 37
            end
            value.Items[index], value.originalItems[index] = item, item
        end
        function value:GetRows() return math.ceil(#self.Items / self.columns) end
        function value:CalculateHeight()
            local rows = self:GetRows()
            return rows * 37 + (rows - 1) * 5 + self.padding + self.tokenHeight + self.MoneyFrame:GetHeight()
        end
        function value:UpdateFrameSize()
            self:SetSize(self.columns * 42 + 16, self:CalculateHeight())
            self.sizeUpdates = (self.sizeUpdates or 0) + 1
        end
        function value:AnchorItemGeometry()
            -- Native bottom-up grid begins above the money frame, which itself
            -- follows the independently retained token tracker.
            local moneyBottom = 8 + (self.tokenHeight > 0 and self.tokenHeight + 3 or 0)
            local firstBottom = moneyBottom + self.MoneyFrame:GetHeight() + 4
            for index, item in ipairs(self.Items) do
                item.rectValid = self.MoneyFrame:IsRectValid()
                if item.rectValid then
                    item.left = ((index - 1) % self.columns) * 42
                    item.bottom = firstBottom + math.floor((index - 1) / self.columns) * 42
                    item.top = item.bottom + 37
                else item.left, item.bottom, item.top = nil, nil, nil end
            end
        end
        function value:UpdateItemLayout()
            self:AnchorItemGeometry()
            self.layoutUpdates = (self.layoutUpdates or 0) + 1
        end
        value.MoneyFrame.anchorGeometry = function() value:AnchorItemGeometry() end
        function value:IsBackpack() return name == "ContainerFrame1" end
        function value:IsCombinedBagContainer() return name == "ContainerFrameCombinedBags" end
        value:UpdateFrameSize(); value:UpdateItemLayout()
        return value
    end
    f.backpack = bag("ContainerFrame1", 13, 16, 4, 78)
    f.combined = bag("ContainerFrameCombinedBags", 16, 48, 8, 75)
    f.bank = node("BankMoneyFrame", 13, true)
    f.merchant = node("MerchantMoneyFrame", 13, true)
    f.otherBag = bag("ContainerFrame2", 13, 16, 4, 48)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.GetMoney = function() return 123456 end
    if options.nativeRenderer then
        -- The native small-money renderer sizes its own contents to 13 units;
        -- the container separately owns its reserved row height (combined: 16).
        -- Width here is representative, not a model of WoW anchor resolution.
        env.MoneyFrame_Update = function(money)
            if type(money) == "string" then money = env[money] end
            money:SetSize(97, 13)
            for key, shown in pairs(money:GetParent().nativeChildShown) do
                if key ~= "Border" then money[key]:SetShown(shown) end
            end
        end
        env.MoneyFrame_UpdateMoney = function(money) env.MoneyFrame_Update(money) end
        env.hooksecurefunc = function(name, callback)
            local original = env[name]
            assert(type(original) == "function")
            env[name] = function(...)
                local result = original(...)
                callback(...)
                return result
            end
            f.nativeHooks = (f.nativeHooks or 0) + 1
        end
        for _, bag in ipairs({ f.backpack, f.combined, f.otherBag }) do env[bag.MoneyFrame:GetName()] = bag.MoneyFrame end
    end
    env.issecretvalue = function(value) return rawequal(value, f.restricted) end
    env.InCombatLockdown = function() return f.combat end
    env.ContainerFrame1 = not options.late and f.backpack or false
    env.ContainerFrameCombinedBags = not options.late and f.combined or false
    env.ContainerFrame2, env.BankMoneyFrame, env.MerchantMoneyFrame = f.otherBag, f.bank, f.merchant
    env.UpdateContainerFrameAnchors = function() f.anchors = f.anchors + 1 end
    env.Menubar = { RegisterWidgetType = function(_, definition) f.provider = definition end }
    env.CreateFrame = function(kind)
        equal(kind, "Frame")
        local monitor = node("monitor", 0, true, nil, false)
        f.monitors[#f.monitors + 1] = monitor
        return monitor
    end
    f.env = env
    function f:step(elapsed)
        for _, monitor in ipairs(self.monitors) do
            if monitor:IsVisible() then monitor:RunScript("OnUpdate", elapsed or 0.3) end
        end
    end
    function f:event(event, ...)
        for _, monitor in ipairs(self.monitors) do
            if monitor.events and monitor.events[event] then monitor:RunScript("OnEvent", event, ...) end
        end
    end
    function f:widget(hide)
        local settings = {}
        for key, value in pairs(self.provider.defaults) do settings[key] = value end
        if hide ~= nil then settings.hideBagMoney = hide end
        local widget = { settings = settings }
        function widget:SetText(text)
            if self.renderError then error(self.renderError, 0) end
            self.text = text
        end
        return widget
    end
    function f:update(widget) self.provider.update(widget) end
    function f:assertGrid(container)
        equal(#container.Items, #container.originalItems)
        for index, item in ipairs(container.Items) do
            equal(item, container.originalItems[index])
            assert(item:IsRectValid(), "Every item needs a resolved positive reference rectangle")
            local left, bottom, width, itemHeight = item:GetRect()
            assert(type(left) == "number" and type(bottom) == "number" and width > 0 and itemHeight > 0)
            assert(item.bottom >= 8 + container.tokenHeight, "Item intrudes into footer/token area")
            local topReserved = container.padding - 12 - (container.tokenHeight > 0 and 3 or 0)
            assert(item.top <= container:GetHeight() - topReserved, "Item intrudes into the title/search area")
        end
    end
    function f:assertCollapsed(container)
        equal(container.MoneyFrame:GetHeight(), 1)
        equal(container.MoneyFrame:IsShown(), container.nativeMoneyShown)
        assert(container.MoneyFrame:IsRectValid())
        equal(container:GetHeight(), container:CalculateHeight())
        for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
            equal(container.MoneyFrame[key]:IsShown(), false)
            equal(container.MoneyFrame[key]:CanReceiveMouse(), false)
        end
        for _, key in ipairs({ "Border", "trialErrorButton", "PrefixText", "SuffixText" }) do
            equal(container.MoneyFrame[key]:IsShown(), false)
        end
        self:assertGrid(container)
    end
    function f:assertRestored(container, shown)
        equal(container.MoneyFrame:GetHeight(), container.nativeMoneyHeight)
        equal(container.MoneyFrame:IsShown(), shown ~= false)
        for key, visible in pairs(container.nativeChildShown) do equal(container.MoneyFrame[key]:IsShown(), visible) end
        if container:IsVisible() then
            equal(container:GetHeight(), container:CalculateHeight())
            self:assertGrid(container)
        end
    end
    function f:nativeLayout(container, height)
        if height then container.nativeMoneyHeight = height end
        container.MoneyFrame:SetHeight(container.nativeMoneyHeight)
        container.MoneyFrame:nativeShow()
        for key, shown in pairs(container.nativeChildShown) do container.MoneyFrame[key]:SetShown(shown) end
        container:UpdateFrameSize(); container:UpdateItemLayout()
        self:step()
    end
    function f:tip(widget)
        local tip = { lines = {} }
        function tip:AddLine(text) self.lines[#self.lines + 1] = text end
        function tip:AddDoubleLine() end
        self.provider.tooltip(widget, tip)
        return table.concat(tip.lines, "\n")
    end
    function f:assertUnrelated()
        equal(self.bank:IsShown(), true); equal(self.bank:GetHeight(), 13)
        equal(self.merchant:IsShown(), true); equal(self.merchant:GetHeight(), 13)
        equal(self.otherBag.MoneyFrame:IsShown(), true)
        equal(self.otherBag.MoneyFrame:GetHeight(), 13)
    end
    f.effects = {}
    local chunk = assert(loadfile(root .. "/src/menubar-currency/Currency.lua"))
    setfenv(chunk, env)()
    return f
end

check("factory settings and an explicit saved opt-out both leave backpack money untouched", function()
    local f = fixture()
    equal(f.provider.defaults.hideBagMoney, false)
    local option
    for _, field in ipairs(f.provider.settings) do if field.key == "hideBagMoney" then option = field end end
    assert(option); equal(option.type, "toggle"); equal(option.label, "Hide backpack and player bank money")
    f:update(f:widget())
    f:update(f:widget(false))
    equal(#f.monitors, 0); equal(#f.effects, 0)
    f:assertRestored(f.backpack); f:assertRestored(f.combined); f:assertUnrelated()
end)

check("separate and combined money areas collapse without removing or clipping any item slots", function()
    local f, widget = fixture()
    widget = f:widget(true)
    local oldBackpack, oldCombined = f.backpack:GetHeight(), f.combined:GetHeight()
    f:update(widget); f:step()
    f:assertCollapsed(f.backpack); f:assertCollapsed(f.combined)
    equal(f.backpack:GetHeight(), oldBackpack - 12)
    equal(f.combined:GetHeight(), oldCombined - 15)
    assert(f.anchors > 0)
    f:assertUnrelated()
    widget.settings.hideBagMoney = false; f:update(widget); f:step()
    f:assertRestored(f.backpack); f:assertRestored(f.combined)
end)

check("a positive reference height recovers every item rectangle after a modeled zero-anchor failure", function()
    local f = fixture()
    local widget = f:widget(true); f:update(widget); f:step()
    local money, item = f.combined.MoneyFrame, f.combined.Items[1]
    money:SetHeight(0)
    equal(money:IsRectValid(), false)
    equal(item:IsShown(), true)
    equal(item:IsRectValid(), false)
    equal(item:GetRect(), nil)
    f:step(0.01)
    f:assertCollapsed(f.combined)
    equal(item:IsRectValid(), true)
    assert(type(item:GetRect()) == "number")
    widget.settings.hideBagMoney = false; f:update(widget); f:step()
    f:assertRestored(f.combined)
end)

check("resolved rounding at the collapsed height cannot replace the remembered native height", function()
    local f = fixture()
    local money = f.backpack.MoneyFrame
    function money:GetHeight(ignoreRect)
        if ignoreRect then return self.height end
        return self.height == 1 and 1.000001 or self.height
    end
    local widget = f:widget(true); f:update(widget); f:step()
    equal(money:GetHeight(true), 1)
    for _ = 1, 5 do f:step() end
    widget.settings.hideBagMoney = false; f:update(widget); f:step()
    equal(money:GetHeight(true), 13)
    f:assertRestored(f.backpack)
end)

check("native money restoration recomputes current denominations and restores the independent border", function()
    local f = fixture()
    local updates = 0
    f.env.MoneyFrame_UpdateMoney = function(money)
        updates = updates + 1
        local container = money:GetParent()
        container.nativeChildShown.GoldButton = false
        money.GoldButton:Hide()
        money.SilverButton:Show()
        money.CopperButton:Show()
        money.PrefixText:Show()
        money.SuffixText:Hide()
    end
    local widget = f:widget(true); f:update(widget); f:step()
    f:assertCollapsed(f.backpack)
    local before = updates
    widget.settings.hideBagMoney = false; f:update(widget); f:step()
    assert(updates > before, "Restoration must read current native denomination visibility")
    f:assertRestored(f.backpack); f:assertRestored(f.combined)
    equal(f.backpack.MoneyFrame.GoldButton:IsShown(), false)
    equal(f.backpack.MoneyFrame.Border:IsShown(), true)
end)

check("snapshot fallback preserves initially absent denominations without changing parent visibility", function()
    local f = fixture()
    f.backpack.nativeChildShown.GoldButton = false
    f.backpack.MoneyFrame.GoldButton:Hide()
    local widget = f:widget(true); f:update(widget); f:step()
    f:assertCollapsed(f.backpack)
    widget.settings.hideBagMoney = false; f:update(widget); f:step()
    f:assertRestored(f.backpack)
    equal(f.backpack.MoneyFrame:IsShown(), true)
    equal(f.backpack.MoneyFrame.GoldButton:IsShown(), false)
end)

check("generic money rendering cannot replace the container's reserved footer height", function()
    for _, customHeight in ipairs({ 16, 21 }) do
        local f = fixture({ nativeRenderer = true })
        local bag = f.combined
        if customHeight ~= 16 then f:nativeLayout(bag, customHeight) end
        local originalHeight = bag:GetHeight()
        local widget = f:widget(true); f:update(widget); f:step()
        for _ = 1, 3 do
            f:assertCollapsed(bag)
            -- Current money chooses visible denominations, even if it changed
            -- while hidden; geometry still belongs to the owning container.
            bag.nativeChildShown.GoldButton = false
            widget.settings.hideBagMoney = false; f:update(widget); f:step()
            f:assertRestored(f.backpack); f:assertRestored(bag)
            equal(bag:GetHeight(), originalHeight)
            widget.settings.hideBagMoney = true; f:update(widget); f:step()
        end
        bag:Hide()
        f.provider.destroy(widget); f:step()
        f:assertRestored(bag)
        f:nativeLayout(bag)
        bag:Show(); f:step()
        equal(bag:GetHeight(), originalHeight)
        f:assertGrid(bag)
    end
end)

check("a rejected row-height restoration keeps contents hidden and retries", function()
    local f = fixture({ nativeRenderer = true })
    local bag, widget = f.combined, f:widget(true)
    f:update(widget); f:step()
    local money, setHeight = bag.MoneyFrame, bag.MoneyFrame.SetHeight
    money.SetHeight = function(self, value)
        if value == bag.nativeMoneyHeight and self:GetHeight() == 13 then return false end
        return setHeight(self, value)
    end
    widget.settings.hideBagMoney = false; f:update(widget); f:step()
    f:assertCollapsed(bag)
    money.SetHeight = setHeight
    f:event("PLAYER_REGEN_ENABLED"); f:step()
    f:assertRestored(bag); f:assertGrid(bag)
end)

check("money updates while hidden cannot replace the row height or ignore a later container resize", function()
    for _, byName in ipairs({ false, true }) do
        local f = fixture({ nativeRenderer = true })
        local bag, widget = f.combined, f:widget(true)
        local money = bag.MoneyFrame
        f:update(widget); f:step()
        equal(f.nativeHooks, 1)
        for _ = 1, 3 do
            f.env.MoneyFrame_Update(byName and money:GetName() or money)
            equal(money:GetHeight(), 13)
            f:step(); f:assertCollapsed(bag)
        end
        -- Native OnShow also renders coins before our OnShow observer runs.
        f.env.MoneyFrame_UpdateMoney(money); money:RunScript("OnShow")
        -- A following horizontal anchor update emits OnSizeChanged too.
        money:SetSize(180, money:GetHeight())
        f:step()
        widget.settings.hideBagMoney = false; f:update(widget); f:step()
        f:assertRestored(bag)
        widget.settings.hideBagMoney = true; f:update(widget); f:step()
        f:nativeLayout(bag, 21)
        f.env.MoneyFrame_UpdateMoney(money); f:step()
        f.provider.destroy(widget); f:step(); f:assertRestored(bag)
        equal(money:GetHeight(), 21)
        equal(f.nativeHooks, 1)
        -- The permanent native post-hook relinquishes all work after release.
        local updates = bag.sizeUpdates
        f.env.MoneyFrame_UpdateMoney(money); f:step()
        equal(bag.sizeUpdates, updates); equal(money:GetHeight(), 13)
    end
end)

check("unavailable native money observation defers suppression without changing the row", function()
    local f = fixture({ nativeRenderer = true })
    local hook = f.env.hooksecurefunc
    f.env.hooksecurefunc = nil -- No registration was attempted; availability may recover.
    local widget = f:widget(true); f:update(widget); f:step()
    f:assertRestored(f.backpack); f:assertRestored(f.combined)
    f.env.hooksecurefunc = hook; f:step()
    f:assertCollapsed(f.combined)
    f.provider.destroy(widget); f:step(); f:assertRestored(f.combined)
end)

check("uncertain global money-render hooks never accumulate or borrow the native row", function()
    for _, failure in ipairs({ "refuse", "attach-throw" }) do
        local f = fixture({ nativeRenderer = true })
        local hook, attempts = f.env.hooksecurefunc, 0
        f.env.hooksecurefunc = function(...)
            attempts = attempts + 1
            if failure == "refuse" then return false end
            hook(...); error("registered before native failure", 0)
        end
        local widget = f:widget(true); f:update(widget); f:step()
        f:step(); f:assertRestored(f.backpack); f:assertRestored(f.combined)
        for _ = 1, 20 do f:step() end
        equal(attempts, 1); equal(f.nativeHooks or 0, failure == "attach-throw" and 1 or 0)
        equal(#f.monitors, 1); equal(#f.effects, 0)
        assert(f:tip(widget):find("Reload the UI", 1, true))
        f.env.hooksecurefunc = hook; f:step()
        equal(attempts, 1); f:assertRestored(f.backpack); f:assertRestored(f.combined)
        f.provider.destroy(widget); f:step()
        equal(f.monitors[1]:IsVisible(), false)
    end
end)

check("uncertain resize hooks stay bounded while healthy and replacement bags remain usable", function()
    for _, failure in ipairs({ "refuse", "attach-throw" }) do
        local f = fixture({ nativeRenderer = true })
        local money = f.combined.MoneyFrame
        local hook, attempts = money.HookScript, 0
        money.HookScript = function(self, script, callback)
            if script == "OnSizeChanged" then
                attempts = attempts + 1
                if failure == "refuse" then return false end
                hook(self, script, callback); error("script attached before native failure", 0)
            end
            return hook(self, script, callback)
        end
        local widget = f:widget(true); f:update(widget); f:step()
        f:assertRestored(f.combined); f:assertCollapsed(f.backpack)
        for _ = 1, 20 do f:step() end
        equal(attempts, 1); equal(#(money.hooks.OnSizeChanged or {}), failure == "attach-throw" and 1 or 0)
        equal(f.nativeHooks, 1) -- The already-ready renderer hook remains shared.
        assert(f:tip(widget):find("Reload the UI", 1, true))
        money.HookScript = hook; f:step(); f:assertRestored(f.combined)
        f.env.ContainerFrameCombinedBags = f.otherBag -- A later native object gets its own attempt.
        f:step(); f:assertCollapsed(f.otherBag); f:assertRestored(f.combined)
        assert(not f:tip(widget):find("Reload the UI", 1, true), "old failed bag must not taint its healthy replacement")
        f:nativeLayout(f.otherBag, 21)
        f.provider.destroy(widget); f:step()
        f:assertRestored(f.backpack); f:assertRestored(f.otherBag); f:assertRestored(f.combined)
        equal(f.nativeHooks, 1); equal(attempts, 1)
    end
end)

check("watched token rows retain their height and visibility while money is collapsed", function()
    local f = fixture()
    for _, bag in ipairs({ f.backpack, f.combined }) do
        bag.tokenHeight = 22; bag.TokenTracker:SetHeight(22); bag.TokenTracker:Show()
        bag:UpdateFrameSize(); bag:UpdateItemLayout()
    end
    local widget = f:widget(true); f:update(widget); f:step()
    for _, bag in ipairs({ f.backpack, f.combined }) do
        f:assertCollapsed(bag)
        equal(bag.TokenTracker:GetHeight(), 22); equal(bag.TokenTracker:IsShown(), true)
    end
    f.provider.destroy(widget); f:step()
    f:assertRestored(f.backpack); f:assertRestored(f.combined); f:assertUnrelated()
end)

check("multiple Currency instances retain the request until the final owner releases", function()
    local f = fixture()
    local one, two = f:widget(true), f:widget(true)
    f:update(one); f:update(two); f:update(one)
    f.provider.destroy(one); f:step()
    f:assertCollapsed(f.backpack); f:assertCollapsed(f.combined)
    two.settings.hideBagMoney = false; f:update(two); f:step()
    f:assertRestored(f.backpack); f:assertRestored(f.combined)
end)

check("native reopening and repeated layout never accumulate a bag-height subtraction", function()
    local f = fixture()
    local widget = f:widget(true); f:update(widget); f:step()
    local height = f.combined:GetHeight()
    for _ = 1, 8 do
        f.combined:Hide(); f:nativeLayout(f.combined); f.combined:Show(); f:step()
        f:assertCollapsed(f.combined); equal(f.combined:GetHeight(), height)
    end
    f.provider.destroy(widget); f:step(); f:assertRestored(f.combined)
end)

check("native grid and footer-size changes restore current layout rather than a stale bag height", function()
    local f = fixture()
    local widget = f:widget(true); f:update(widget); f:step()
    f.combined.columns = 6
    f.combined.tokenHeight = 19
    f:nativeLayout(f.combined, 21)
    f:assertCollapsed(f.combined)
    local collapsed = f.combined:GetHeight()
    widget.settings.hideBagMoney = false; f:update(widget); f:step()
    f:assertRestored(f.combined)
    equal(f.combined:GetHeight(), collapsed + 20)
    equal(f.combined:GetRows(), 8)
    equal(#f.combined.Items, 48)
end)

check("unopened bags wait for generation while an owned closed footer remains collapsed", function()
    local f = fixture({ closed = true })
    local widget = f:widget(true); f:update(widget); f:step()
    f:assertRestored(f.backpack); f:assertRestored(f.combined)
    f.backpack:Show(); f:step()
    f:assertCollapsed(f.backpack); f:assertRestored(f.combined)
    f.backpack:Hide(); f:step()
    equal(f.backpack.MoneyFrame:GetHeight(), 1)
    f.combined:Show(); f:step()
    f:assertCollapsed(f.combined)
    f.provider.destroy(widget); f:step()
    f:assertRestored(f.backpack); f:assertRestored(f.combined)
end)

check("late-created backpack UI is discovered and restored without affecting other money frames", function()
    local f = fixture({ late = true })
    local widget = f:widget(true); f:update(widget); f:step()
    f:assertRestored(f.backpack); f:assertRestored(f.combined)
    f.env.ContainerFrame1, f.env.ContainerFrameCombinedBags = f.backpack, f.combined
    f:event("ADDON_LOADED", "Blizzard_UIPanels_Game"); f:step()
    f:assertCollapsed(f.backpack); f:assertCollapsed(f.combined)
    f.provider.destroy(widget); f:step()
    f:assertRestored(f.backpack); f:assertRestored(f.combined); f:assertUnrelated()
end)

check("combat and unavailable combat-state readings defer every borrowed mutation", function()
    for _, blocked in ipairs({ true, {}, "unknown" }) do
        local f = fixture()
        f.combat = blocked
        local widget = f:widget(true)
        f:update(widget); f:step()
        equal(#f.effects, 0)
        f:assertRestored(f.backpack); f:assertRestored(f.combined)
        f.combat = false; f:event("PLAYER_REGEN_ENABLED"); f:step()
        f:assertCollapsed(f.backpack); f:assertCollapsed(f.combined)
        f.provider.destroy(widget); f:step()
        f:assertRestored(f.backpack); f:assertRestored(f.combined)
    end
end)

check("protected parent footer or mandatory content denies collapse before any native mutation", function()
    for _, which in ipairs({ "parent", "money", "GoldButton", "Border" }) do
        local f = fixture()
        local blocked = which == "parent" and f.backpack
            or (which == "money" and f.backpack.MoneyFrame or f.backpack.MoneyFrame[which])
        blocked.permission = false
        local widget = f:widget(true)
        f:update(widget); f:step()
        f:assertRestored(f.backpack)
        equal(f.backpack.MoneyFrame.GoldButton:CanReceiveMouse(), true)
        for _, effect in ipairs(f.effects) do
            assert(effect[1] ~= f.backpack and effect[1] ~= f.backpack.MoneyFrame,
                "Denied layout must not attempt a native mutation")
            assert(effect[1].parent ~= f.backpack.MoneyFrame, "Denied content must not be partially hidden")
        end
        blocked.permission = true; f:event("PLAYER_REGEN_ENABLED"); f:step()
        f:assertCollapsed(f.backpack)
        f.provider.destroy(widget); f:step(); f:assertRestored(f.backpack)
    end
end)

check("restoration deferred by combat keeps the footer hidden until native geometry can be restored", function()
    local f = fixture()
    local widget = f:widget(true); f:update(widget); f:step()
    f.combat = true
    widget.settings.hideBagMoney = false; f:update(widget); f:step()
    f:assertCollapsed(f.backpack); f:assertCollapsed(f.combined)
    f.combat = false; f:event("PLAYER_REGEN_ENABLED"); f:step()
    f:assertRestored(f.backpack); f:assertRestored(f.combined)
end)

check("render failure releases native layout and refresh can reacquire the same request", function()
    local f = fixture()
    local widget = f:widget(true); f:update(widget); f:step()
    widget.renderError = "simulated currency render failure"
    local ok, reason = pcall(f.provider.update, widget)
    equal(ok, false); assert(tostring(reason):find(widget.renderError, 1, true))
    f.provider.reset(widget, "update"); f:step()
    f:assertRestored(f.backpack); f:assertRestored(f.combined)
    widget.renderError = nil; f:update(widget); f:step()
    f:assertCollapsed(f.backpack); f:assertCollapsed(f.combined)
    f.provider.destroy(widget); f.provider.destroy(widget); f:step()
    f:assertRestored(f.backpack); f:assertRestored(f.combined)
end)

check("an originally hidden money display stays hidden after its height is restored", function()
    local f = fixture()
    f.backpack.nativeMoneyShown = false
    f.backpack.MoneyFrame:nativeHide()
    local widget = f:widget(true); f:update(widget); f:step()
    f:assertCollapsed(f.backpack)
    f.provider.destroy(widget); f:step()
    f:assertRestored(f.backpack, false)
end)

check("rejected or silent content Hide never shrinks a still-interactive money area", function()
    for _, silent in ipairs({ false, true }) do
        local f = fixture()
        local money, button = f.backpack.MoneyFrame, f.backpack.MoneyFrame.GoldButton
        local hide = button.Hide
        button.Hide = function() if silent then return nil else return false end end
        local widget = f:widget(true); f:update(widget); f:step()
        equal(money:GetHeight(), 13)
        equal(money:IsShown(), true)
        equal(money.GoldButton:CanReceiveMouse(), true)
        f:assertGrid(f.backpack)
        button.Hide = hide; f:step()
        f:assertCollapsed(f.backpack)
        f.provider.destroy(widget); f:step(); f:assertRestored(f.backpack)
    end
end)

check("a rejected footer resize cannot create a live invisible coin target", function()
    local f = fixture()
    local money = f.backpack.MoneyFrame
    local setHeight = money.SetHeight
    money.SetHeight = function(self, value) if value == 1 then return false end; return setHeight(self, value) end
    local widget = f:widget(true); f:update(widget); f:step()
    equal(money:GetHeight(), 13)
    equal(money.GoldButton:CanReceiveMouse(), false)
    f:assertGrid(f.backpack)
    money.SetHeight = setHeight; f:step(); f:assertCollapsed(f.backpack)
    widget.settings.hideBagMoney = false; f:update(widget); f:step(); f:assertRestored(f.backpack)
end)

check("a failed restoration layout cannot reveal money over the still-collapsed item grid", function()
    local f = fixture()
    local widget = f:widget(true); f:update(widget); f:step()
    local updateSize = f.backpack.UpdateFrameSize
    f.backpack.UpdateFrameSize = function() return false end
    widget.settings.hideBagMoney = false; f:update(widget); f:step()
    equal(f.backpack.MoneyFrame:IsShown(), true)
    equal(f.backpack.MoneyFrame:GetHeight(), 1)
    f:assertGrid(f.backpack)
    equal(f.backpack.MoneyFrame.GoldButton:CanReceiveMouse(), false)
    f.backpack.UpdateFrameSize = updateSize
    f:event("PLAYER_REGEN_ENABLED"); f:step()
    f:assertRestored(f.backpack)
end)

check("unavailable native bag visibility retains pending layout and restoration until it is public", function()
    for _, throws in ipairs({ false, true }) do
        local f = fixture()
        local bag, money = f.backpack, f.backpack.MoneyFrame
        local widget = f:widget(true); f:update(widget); f:step()
        local isShown = bag.IsShown
        local function unavailable()
            if throws then error("native visibility is unavailable") end
            return f.restricted
        end
        bag.IsShown = unavailable
        local updates = bag.sizeUpdates
        money:SetHeight(13); money:nativeShow(); money.GoldButton:Show(); f:step()
        equal(bag.sizeUpdates, updates)
        equal(money:GetHeight(), 1); equal(money:IsShown(), true)
        bag.IsShown = isShown
        f:step()
        assert(bag.sizeUpdates > updates, "Unresolved visibility must not discard the pending native reflow")
        f:assertCollapsed(bag)

        bag.IsShown = unavailable
        widget.settings.hideBagMoney = false; f:update(widget); f:step()
        equal(money:IsShown(), true)
        equal(money:GetHeight(), 1)
        equal(money.GoldButton:CanReceiveMouse(), false)
        bag.IsShown = isShown
        f:step()
        f:assertRestored(bag)
        f:assertRestored(f.combined)
    end
end)

check("inactive native hooks stop changing the bag and the monitor is reused", function()
    local f = fixture()
    local widget = f:widget(true); f:update(widget); f:step()
    equal(#f.monitors, 1)
    widget.settings.hideBagMoney = false; f:update(widget); f:step()
    f:nativeLayout(f.backpack, 18)
    f:assertRestored(f.backpack)
    widget.settings.hideBagMoney = true; f:update(widget); f:step()
    equal(#f.monitors, 1)
    f:assertCollapsed(f.backpack)
    f.provider.destroy(widget); f:step(); f:assertRestored(f.backpack)
end)

print(passed .. " backpack money layout tests passed")
