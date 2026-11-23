local sourceDirectory = dofile((REPO_ROOT or ".") .. "/tests/source_paths.lua")
-- Real Currency host/settings lifecycle with native bag geometry modeled from
-- Blizzard's MoneyFrame-height contract. This does not emulate taint or combat.
-- The local rectangle model requires a positive reference-frame dimension;
-- this represents the zero-anchor hypothesis, not proof of native C++ behavior.
local root = REPO_ROOT or "."
local core = MENUBAR_CORE_ROOT or root
local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end
if not exists(core .. "/tests/wow_stub.lua") then
    print("SKIP Currency host integration: restore Core in this clone or supply MENUBAR_CORE_ROOT.")
    return
end

local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function loadAddon(repository, addon)
    local namespace = {}
    for line in io.lines(sourceDirectory(repository, addon) .. "/" .. addon .. ".toc") do
        local file = line:match("^%s*(.-)%s*$")
        if file:match("%.lua$") then
            assert(loadfile(sourceDirectory(repository, addon) .. "/" .. file))(addon, namespace)
        end
    end
end

local function fixture(factoryDefaults)
    local Stub = dofile(core .. "/tests/wow_stub.lua")
    Stub.Install()
    local nativeCreateFrame = CreateFrame
    CreateFrame = function(...)
        local frame = nativeCreateFrame(...)
        function frame:UnregisterAllEvents() self.events = {} end
        return frame
    end
    MenubarDB = nil
    GetMoney = function() return 123456 end
    MoneyFrame_UpdateMoney = nil -- Exercise the controller's snapshot fallback here.
    local combat, anchorUpdates = false, 0
    InCombatLockdown = function() return combat end
    UpdateContainerFrameAnchors = function() anchorUpdates = anchorUpdates + 1 end
    local function allowed() return not combat end
    local function bag(name, nativeMoneyHeight, slots, columns)
        local container = CreateFrame("Frame", name, UIParent)
        container.CanChangeProtectedState = allowed
        container.items, container.paddingHeight, container.gridHeight = {}, 60, math.ceil(slots / columns) * 20
        container.nativeMoneyHeight, container.tokenHeight = nativeMoneyHeight, 18
        container.nativeShow, container.nativeHide = container.Show, container.Hide
        container.Hide = function() error("Addon must not hide a backpack container") end
        container.SetParent = function() error("Addon must not reparent a backpack container") end
        for index = 1, slots do
            local item = CreateFrame("Button", nil, container)
            item.CanChangeProtectedState = allowed
            item.slot, item.mouseEnabled = index, true
            container.items[index] = item
        end
        function container:EnumerateValidItems() return ipairs(self.items) end
        function container:GetBagID() return 0 end
        function container:IsCombinedBagContainer() return name == "ContainerFrameCombinedBags" end
        function container:IsBackpack() return name == "ContainerFrame1" end
        function container:CalculateHeight()
            return self.gridHeight + self.paddingHeight + self.tokenHeight + self.MoneyFrame:GetHeight()
        end
        function container:UpdateFrameSize()
            assert(not combat, "Bag resize must wait for combat to end")
            self.resizeCalls = (self.resizeCalls or 0) + 1
            self:SetSize(columns * 20 + 16, self:CalculateHeight())
        end
        function container:UpdateItemLayout()
            assert(not combat, "Item layout must wait for combat to end")
            self.layoutCalls = (self.layoutCalls or 0) + 1
            self.firstItemY = 8 + self.tokenHeight + 3 + self.MoneyFrame:GetHeight() + 4
            for index, item in ipairs(self.items) do
                item:ClearAllPoints()
                item:SetPoint("BOTTOMRIGHT", self.MoneyFrame, "TOPRIGHT", -((index - 1) % columns) * 20,
                    4 + math.floor((index - 1) / columns) * 20)
            end
        end
        local money = CreateFrame("Frame", name == "ContainerFrame1" and "ContainerFrame1MoneyFrame" or nil, container)
        container.MoneyFrame = money
        money.CanChangeProtectedState = allowed
        money:SetHeight(nativeMoneyHeight)
        money:SetAlpha(0.85)
        money.nativeShow, money.nativeHide = money.Show, money.Hide
        money.Show = function() error("Addon must preserve the grid anchor's native shown policy") end
        money.Hide = function() error("Addon must not hide the grid's native MoneyFrame anchor") end
        money.SetParent = function() error("Addon must not reparent backpack money") end
        money.SetAlpha = function() error("Bag-space removal must not use alpha masking") end
        local setHeight, setSize = money.SetHeight, money.SetSize
        function money:SetHeight(height)
            assert(not combat, "Money geometry must wait for combat to end")
            local previous = self:GetHeight()
            setHeight(self, height)
            if previous ~= height and self.scripts.OnSizeChanged then
                self.scripts.OnSizeChanged(self, self:GetWidth(), height)
            end
        end
        function money:SetSize(width, height)
            self.width = width; self:SetHeight(height)
        end
        function money:IsMouseEnabled() return self.mouseEnabled == true end
        function money:IsRectValid() return self:GetHeight() > 0 end
        function money:GetRect()
            if not self:IsRectValid() then return nil end
            return 0, 8 + container.tokenHeight + 3, container:GetWidth() - 16, self:GetHeight()
        end
        money.Border = CreateFrame("Frame", nil, money)
        money.Border.CanChangeProtectedState = allowed
        for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
            local button = CreateFrame("Button", nil, money)
            button.mouseEnabled, button.CanChangeProtectedState = true, allowed
            function button:IsMouseEnabled() return self.mouseEnabled end
            button.EnableMouse = function() error("Hiding coin content must not rewrite its input setting") end
            money[key] = button
        end
        for _, key in ipairs({ "trialErrorButton", "PrefixText", "SuffixText" }) do
            local child = CreateFrame("Frame", nil, money)
            child.CanChangeProtectedState = allowed
            if key ~= "PrefixText" then child:Hide() end
            money[key] = child
        end
        for _, item in ipairs(container.items) do
            function item:IsRectValid() return money:IsRectValid() and #self.points > 0 end
            function item:GetRect()
                if not self:IsRectValid() then return nil end
                local anchor = self.points[1]
                return anchor[4], 8 + container.tokenHeight + 3 + money:GetHeight() + anchor[5], 20, 20
            end
        end
        money:SetScript("OnShow", function(self) self:SetHeight(container.nativeMoneyHeight) end)
        money:SetScript("OnHide", function(self) self.nativeHideCalls = (self.nativeHideCalls or 0) + 1 end)
        function container:UpdateMoneyFrame() self.MoneyFrame:SetHeight(self.nativeMoneyHeight) end
        function container:UpdateCurrencyFrames()
            self.MoneyFrame.nativeShow(self.MoneyFrame)
            self.MoneyFrame.Border:Show()
            for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton", "PrefixText" }) do self.MoneyFrame[key]:Show() end
        end
        container:SetScript("OnShow", function(self)
            self:UpdateMoneyFrame(); self:UpdateCurrencyFrames()
            self:UpdateFrameSize(); self:UpdateItemLayout()
        end)
        container:UpdateFrameSize(); container:UpdateItemLayout()
        container.originalHeight, container.originalItemY = container:GetHeight(), container.firstItemY
        return container
    end
    local backpack = bag("ContainerFrame1", 13, 20, 4)
    local combined = bag("ContainerFrameCombinedBags", 16, 60, 10)
    combined.nativeHide(combined)
    ContainerFrame1, ContainerFrameCombinedBags = backpack, combined
    local token = CreateFrame("Frame", "BackpackTokenFrame", backpack)
    token:SetHeight(18); token:SetAlpha(0.7)
    local merchant = CreateFrame("Frame", "MerchantMoneyFrame", UIParent)
    merchant:SetHeight(13); merchant:SetAlpha(0.6)
    local bank = CreateFrame("Frame", "BankMoneyFrame", UIParent)
    bank:SetHeight(13); bank:SetAlpha(0.4)
    BankFrame = { MoneyFrame = bank }
    ContainerFrameSettingsManager = {
        MoneyFrameOwner = backpack, TokenTrackerOwner = backpack, TokenTracker = token,
        IsUsingCombinedBags = function() return combined:IsShown() end,
    }
    loadAddon(core, "Menubar")
    loadAddon(root, "Menubar_Currency")
    if not factoryDefaults then
        local db = MenubarModel.Initialize(nil, "Tester - Test Realm")
        MenubarModel.AddWidget(db, "Tester - Test Realm", "currency", { hideBagMoney = false })
        MenubarDB = db
    end
    Menubar:Start()
    local host, widget = Menubar, select(2, next(Menubar.runtime))
    assert(widget and widget.instance.type == "currency" and not widget.failed, "Currency must initialize")
    local f = { host = host, widget = widget, backpack = backpack, combined = combined, token = token,
        merchant = merchant, bank = bank, Stub = Stub }
    function f:step(elapsed)
        for _, frame in ipairs(Stub.frames) do
            if frame:IsVisible() and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, elapsed or 0.3) end
        end
    end
    function f:event(name)
        for _, frame in ipairs(Stub.frames) do
            if frame.events and frame.events[name] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, name) end
        end
    end
    function f:request(value, enabled)
        host.UI:OpenWidget(value.id)
        local checkbox
        for _, control in ipairs(host.UI.window.controls) do
            if control.caption == "Hide backpack and player bank money" then checkbox = control; break end
        end
        assert(checkbox, "Currency's native money setting must be exposed")
        equal(checkbox:GetChecked(), value.settings.hideBagMoney == true)
        if checkbox:GetChecked() ~= enabled then checkbox:Click() end
        equal(value.settings.hideBagMoney, enabled)
        assert(not value.failed, tostring(value.failed))
        self:step()
    end
    function f:unchangedOthers()
        equal(token:GetHeight(), 18); equal(token:GetAlpha(), 0.7); equal(token:IsShown(), true)
        equal(merchant:GetHeight(), 13); equal(merchant:GetAlpha(), 0.6); equal(merchant:IsShown(), true)
        equal(bank:GetHeight(), 13); equal(bank:GetAlpha(), 0.4); equal(bank:IsShown(), true)
        equal(#backpack.items, 20); equal(#combined.items, 60)
        for _, container in ipairs({ backpack, combined }) do
            for index, item in ipairs(container.items) do equal(item.slot, index); equal(item.mouseEnabled, true) end
            equal(container.MoneyFrame:GetAlpha(), 0.85)
        end
    end
    function f:collapsed(container)
        container = container or backpack
        equal(container.MoneyFrame:IsShown(), true)
        equal(container.MoneyFrame:GetHeight(), 1)
        assert(container.MoneyFrame:IsRectValid())
        equal(container:GetHeight(), container.originalHeight - container.nativeMoneyHeight + 1)
        equal(container.firstItemY, container.originalItemY - container.nativeMoneyHeight + 1)
        for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
            equal(container.MoneyFrame[key]:IsVisible(), false)
            equal(container.MoneyFrame[key]:IsMouseEnabled(), true)
        end
        for _, key in ipairs({ "Border", "trialErrorButton", "PrefixText", "SuffixText" }) do equal(container.MoneyFrame[key]:IsShown(), false) end
        for _, item in ipairs(container.items) do
            assert(item:IsRectValid(), "Every retained item needs a resolved anchor rectangle")
            local left, bottom, width, itemHeight = item:GetRect()
            assert(type(left) == "number" and bottom > 0 and width > 0 and itemHeight > 0)
            assert(bottom + itemHeight <= container:GetHeight() - 35, "Item overlaps title/search controls")
        end
        self:unchangedOthers()
    end
    function f:restored(container)
        container = container or backpack
        equal(container.MoneyFrame:IsShown(), true)
        equal(container.MoneyFrame:GetHeight(), container.nativeMoneyHeight)
        equal(container.MoneyFrame.Border:IsShown(), true)
        equal(container.MoneyFrame.PrefixText:IsShown(), true)
        equal(container.MoneyFrame.SuffixText:IsShown(), false)
        equal(container.MoneyFrame.trialErrorButton:IsShown(), false)
        for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do equal(container.MoneyFrame[key]:IsShown(), true) end
        if container:IsShown() then
            equal(container:GetHeight(), container.originalHeight)
            equal(container.firstItemY, container.originalItemY)
        end
        self:unchangedOthers()
    end
    function f:switch(container)
        backpack.nativeHide(backpack); combined.nativeHide(combined)
        ContainerFrameSettingsManager.MoneyFrameOwner = container
        ContainerFrameSettingsManager.TokenTrackerOwner = container
        container.nativeShow(container)
        self:step()
    end
    function f:setCombat(value) combat = value end
    return f
end

check("Currency factory settings preserve backpack money and opting in reclaims its space", function()
    local f = fixture(true)
    equal(f.host.types.currency.defaults.hideBagMoney, false)
    f:restored()
    f:request(f.widget, true); f:collapsed()
    -- The unused combined bag has not been mutated merely because it exists.
    equal(f.combined.MoneyFrame:GetHeight(), 16)
    equal(f.combined.MoneyFrame:IsShown(), true)
    f:request(f.widget, false); f:restored()
    assert(f.widget.text:find("coin%-gold"), "The Currency widget must still display money")
end)

check("duplicate Currency requesters survive disable and removal until the final release", function()
    local f = fixture()
    local instance = f.host:AddWidget("currency")
    local second = f.host.runtime[instance.id]
    f:request(f.widget, true); f:request(second, true)
    f:request(f.widget, false); f:collapsed()
    second.instance.enabled = false; f.host:Rebuild(); f:step(); f:restored()
    second.instance.enabled = true; f.host:Rebuild(); f:step(); f:collapsed()
    f:request(f.widget, true)
    f.host:RemoveWidget(second.id); f:step(); f:collapsed()
    f.host:RemoveWidget(f.widget.id); f:step(); f:restored()
end)

check("Currency appearance rebuild and overflow retain a bag-collapse request", function()
    local f = fixture()
    f:request(f.widget, true)
    local original = f.widget
    f.host:GetProfile().placement = "both"
    f.host:Rebuild(); f:step()
    equal(f.host.runtime[original.id], original); f:collapsed()
    UIParent:SetWidth(80); f.host:Rebuild(); f:step()
    equal(original.frame:IsShown(), false); f:collapsed()
    UIParent:SetWidth(1280); f.host:Rebuild()
    f:request(original, false); f:restored()
end)

check("a Currency render failure restores the native money area and refresh can recover", function()
    local f = fixture()
    f:request(f.widget, true)
    local setText = f.widget.SetText
    f.widget.SetText = function() error("simulated Currency rendering failure", 0) end
    f.host:RefreshWidget(f.widget.id); f:step()
    equal(f.widget.failed, "simulated Currency rendering failure")
    f:restored()
    f.widget.SetText = setText
    f.host:RefreshWidget(f.widget.id); f:step(); f:collapsed()
    f.host:RemoveWidget(f.widget.id); f:step(); f:restored()
end)

check("switching backpack modes collapses both money rows without changing slots or tokens", function()
    local f = fixture()
    f:request(f.widget, true); f:collapsed(f.backpack)
    f:switch(f.combined); f:collapsed(f.combined)
    equal(f.backpack.MoneyFrame:GetHeight(), 1)
    f:switch(f.backpack); f:collapsed(f.backpack)
    f:request(f.widget, false)
    f:restored(f.backpack); f:restored(f.combined)
    -- Closed containers defer their grid until Blizzard opens them again.
    f:switch(f.combined); f:restored(f.combined)
end)

check("combat-time Currency requests defer geometry changes until permitted", function()
    local f = fixture()
    f:setCombat(true)
    f:request(f.widget, true); f:restored()
    f:setCombat(false); f:event("PLAYER_REGEN_ENABLED"); f:step(); f:collapsed()
    f:setCombat(true)
    f:request(f.widget, false); f:collapsed()
    f:setCombat(false); f:event("PLAYER_REGEN_ENABLED"); f:step(); f:restored()
end)

print(passed .. " Currency host integration tests passed")
