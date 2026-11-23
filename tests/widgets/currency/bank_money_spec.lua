local sourceDirectory = dofile((REPO_ROOT or ".") .. "/tests/source_paths.lua")
-- Independent native-shaped Character-bank fixture through real addon TOCs.
-- Geometry models verified anchors/scales; this is not renderer/taint proof.
local root = REPO_ROOT or "."
local core = MENUBAR_CORE_ROOT or root
local file = io.open(core .. "/tests/wow_stub.lua", "rb")
if not file then print("SKIP bank-money integration: restore Core in this clone or supply MENUBAR_CORE_ROOT."); return end
file:close()
local passed = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected, message)
    assert(math.abs(actual - expected) < 0.000001, (message or "unexpected measurement") .. ": expected " .. expected .. ", got " .. actual)
end
local function check(name, run)
    local ok, reason = pcall(run)
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

local function fixture(options)
    options = options or {}
    local Stub = dofile(core .. "/tests/wow_stub.lua"); Stub.Install()
    local f = { Stub = Stub, combat = false, hooks = {}, nativeWrites = false, banks = {}, rectReads = 0, itemEnumerations = 0, nilRead = {} }
    f.secret = setmetatable({}, {
        __index = function() error("restricted value indexed", 0) end,
        __lt = function() error("restricted value compared", 0) end,
        __le = function() error("restricted value compared", 0) end,
        __tostring = function() error("restricted value formatted", 0) end,
    })
    issecretvalue = function(value) return rawequal(value, f.secret) end
    InCombatLockdown = function() return f.combat end
    MenubarDB, BankFrame, ContainerFrame1, ContainerFrameCombinedBags, C_CurrencyInfo = nil, nil, nil, nil, nil
    Enum = { BankType = { Character = 0, Account = 2 } }
    C_Bank = {
        DoesBankTypeSupportMoneyTransfer = function(bankType) return bankType == Enum.BankType.Account end,
        CanWithdrawMoney = function() return true end,
        CanDepositMoney = function() return true end,
    }
    UpdateContainerFrameAnchors, MoneyFrame_UpdateMoney = nil, nil
    hooksecurefunc = function(owner, method, hook)
        assert(type(owner) == "table" and type(method) == "string" and type(hook) == "function")
        local original = assert(owner[method], "post-hook needs a concrete native method")
        f.hooks[owner] = f.hooks[owner] or {}
        f.hooks[owner][method] = (f.hooks[owner][method] or 0) + 1
        owner[method] = function(...)
            local result = { original(...) }; hook(...); return unpack(result)
        end
    end
    local nativeCreateFrame = CreateFrame
    CreateFrame = function(...)
        local frame = nativeCreateFrame(...)
        function frame:UnregisterAllEvents() self.events = {} end
        return frame
    end
    UIParent:SetScale(options.uiScale or 1)
    local function protectAnchors(frame)
        frame.savedPoints = frame.points
        frame.SetPoint = function() error("bank adapter must not move retained anchors", 0) end
        frame.ClearAllPoints = function() error("bank adapter must not clear retained anchors", 0) end
        frame.SetParent = function() error("bank adapter must not reparent native controls", 0) end
    end
    local function bankPart(frame)
        frame.permission = true
        function frame:CanChangeProtectedState() return self.permission end
        local nativeHeight, nativeGetHeight = frame.SetHeight, frame.GetHeight
        function frame:SetHeight(value)
            assert(not rawequal(value, f.secret) and type(value) == "number" and value == value
                and value > 0 and value < math.huge, "no invalid or restricted native dimension writes")
            if not f.nativeWrites then
                assert(f.combat == false and self.permission == true, "addon sizing needs current public permission")
                self.heightWrites = (self.heightWrites or 0) + 1
                local action = self.heightWriteSequence and table.remove(self.heightWriteSequence, 1)
                if action == "reject" then return false end
                if self.rejectHeight then return false end
                if self.throwHeight then error("bank resize rejected", 0) end
            end
            if options.heightQuantum then value = math.floor(value / options.heightQuantum + 0.5) * options.heightQuantum end
            nativeHeight(self, value)
            if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, self:GetWidth(), value) end
        end
        function frame:GetHeight()
            if self.heightSequence and #self.heightSequence > 0 then
                local value = table.remove(self.heightSequence, 1)
                if value == f.nilRead then return nil end
                return value
            end
            if self.heightValue ~= nil then return self.heightValue end
            return nativeGetHeight(self)
        end
        local nativeScale = frame.GetEffectiveScale
        function frame:GetEffectiveScale()
            if self.scaleValue ~= nil then return self.scaleValue end
            return nativeScale(self)
        end
    end
    function f:bank(config)
        config = config or {}
        local bank = CreateFrame("Frame", nil, UIParent)
        bank:SetWidth(380); bank:SetScale(config.scale or options.bankScale or 1)
        bank:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -30)
        bank.top, bank.nativeHeight, bank.kind = 900, 460, Enum.BankType.Character
        bankPart(bank)
        local panel = CreateFrame("Frame", nil, bank); bank.BankPanel = panel
        panel:SetPoint("LEFT", bank, "LEFT", 0, 0); panel:SetWidth(380); bankPart(panel)
        local function framing(region, parent)
            region.permission, region.anchorWrites = true, 0
            region.points = { { "TOPLEFT", parent, "TOPLEFT", 0, -20 }, { "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 30 } }
            region.savedTop, region.savedBottom = region.points[1], region.points[2]
            function region:CanChangeProtectedState() return self.permission end
            function region:GetNumPoints() return self.pointCountValue or #self.points end
            function region:GetPoint(index)
                if self.pointReadSequence and #self.pointReadSequence > 0 then
                    local action = table.remove(self.pointReadSequence, 1)
                    if action == "missing" then return end
                    if action == "restricted" then return "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, f.secret end
                    if action == "throw" then error("anchor read unavailable", 0) end
                end
                if self.pointReadFailure == "missing" then return end
                if self.pointReadFailure == "restricted" then return f.secret end
                return unpack(self.points[index] or {})
            end
            function region:SetPoint(point, relative, relativePoint, x, y)
                assert(type(point) == "string" and type(relativePoint) == "string" and type(x) == "number"
                    and type(y) == "number" and x == x and y == y and math.abs(x) < math.huge and math.abs(y) < math.huge)
                local action
                if not f.nativeWrites then
                    assert(f.combat == false and self.permission == true, "framing writes need public permission")
                    equal(point, "BOTTOMRIGHT", "only the reserved lower edge may move")
                    self.anchorWrites = self.anchorWrites + 1
                    action = self.anchorWriteSequence and table.remove(self.anchorWriteSequence, 1)
                    if action == "reject" or self.rejectPoint then return false end
                    if action == "throw" then error("anchor write rejected", 0) end
                end
                if options.pointQuantum then y = math.floor(y / options.pointQuantum + 0.5) * options.pointQuantum end
                if options.pointReadback then x, y = options.pointReadback(x, y, self) end
                local replaced
                for index, current in ipairs(self.points) do
                    if current[1] == point then self.points[index] = { point, relative, relativePoint, x, y }; replaced = true; break end
                end
                if not replaced then self.points[#self.points + 1] = { point, relative, relativePoint, x, y } end
                if action == "apply-throw" then error("native write applied before failure", 0) end
            end
            function region:AdjustPointsOffset(x, y)
                assert(f.nativeWrites, "framing must not adjust the other native anchors")
                for _, point in ipairs(self.points) do point[4], point[5] = point[4] + x, point[5] + y end
            end
            function region:ClearPoint(name)
                assert(f.nativeWrites, "framing must preserve the other native anchors")
                for index = #self.points, 1, -1 do if self.points[index][1] == name then table.remove(self.points, index) end end
            end
            function region:ClearAllPoints()
                assert(f.nativeWrites, "framing must preserve the other native anchors"); self.points = {}
            end
            function region:ClearPointsOffset() assert(f.nativeWrites, "framing must preserve native offsets") end
            function region:SetPointsOffset() assert(f.nativeWrites, "framing must preserve native offsets") end
            function region:SetAllPoints(relative)
                assert(f.nativeWrites, "framing must preserve the other native anchors")
                self.points = { { "TOPLEFT", relative, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", relative, "BOTTOMRIGHT", 0, 0 } }
            end
            function region:SetParent(relative)
                assert(f.nativeWrites, "framing must not be reparented"); self.parent = relative
            end
            return region
        end
        panel.NineSlice = framing(CreateFrame("Frame", nil, panel), panel)
        bank.Background = framing(bank:CreateTexture(nil, "BACKGROUND"), bank)
        panel.EdgeShadows = CreateFrame("Frame", nil, panel)
        panel.EdgeShadows:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        panel.EdgeShadows:SetPoint("BOTTOMRIGHT", panel.NineSlice, "BOTTOMRIGHT", 0, 0)
        protectAnchors(panel.EdgeShadows)
        panel.items, bank.bagButtons = {}, {}
        bank.itemButtonBagPool = { EnumerateActive = function() return ipairs(bank.bagButtons) end }
        function panel:EnumerateValidItems() f.itemEnumerations = f.itemEnumerations + 1; return ipairs(self.items) end
        function panel:GetActiveBankType() return bank.kind end
        local function geometry(frame, kind, bottom, width, tall)
            frame.geometryKind, frame.bottomOffset = kind, bottom
            frame:SetSize(width, tall)
            function frame:IsRectValid() if self.rectValid ~= nil then return self.rectValid end; return true end
            function frame:GetRect()
                f.rectReads = f.rectReads + 1
                if self.rectError then error("bank rect unavailable", 0) end
                if self.rectValue ~= nil then return self.rectValue, 0, 37, 37 end
                local bankScale, ownScale = bank:GetEffectiveScale(), self:GetEffectiveScale()
                local low
                if self.geometryKind == "item" then low = bank.top - 63 - self.row * 47 - 37
                else low = bank.top - bank.height + self.bottomOffset end
                return 100 * bankScale / ownScale, low * bankScale / ownScale,
                    self:GetWidth(), self:GetHeight()
            end
            protectAnchors(frame)
        end
        local function lower(parent, offset, width, tall)
            local control = CreateFrame("Frame", nil, parent)
            control:SetPoint("BOTTOMLEFT", bank, "BOTTOMLEFT", 0, offset)
            geometry(control, "lower", offset, width, tall)
            control.tint, control.savedTint = { 0.2, 0.4, 0.6 }, nil
            control.savedTint = control.tint
            return control
        end
        bank.BagText = lower(bank, (config.lowerTop or 107) - 40, 120, 40)
        bank.BagCost = lower(bank, 45, 40, 13)
        panel.MoneyDisplay = lower(panel, 45, 100, 13); panel.MoneyDisplay:Hide()
        panel.PurchaseButton = lower(panel, 45, 80, 20); panel.PurchaseButton:Hide()
        -- Native direct, unnamed Texture: BOTTOM y220, scale .48, observed height32.
        -- Explicit alternate heights below exercise layouts with genuine reclaimable room.
        local divider = bank:CreateTexture(nil, "ARTWORK"); bank.divider = divider
        local dividerTop = config.dividerTop or options.dividerTop or ((220 + 32) * 0.48)
        divider:SetAtlas("bank-divider"); divider:SetScale(0.48)
        divider:SetPoint("BOTTOM", bank, "BOTTOM", 0, dividerTop / 0.48 - 32)
        geometry(divider, "lower", dividerTop - 32 * 0.48, 864, 32)
        bank.regions = { bank.Background, divider }
        function bank:GetNumRegions() return self.regionCountValue or #self.regions end
        function bank:GetRegions()
            self.regionReads = (self.regionReads or 0) + 1
            if self.regionError then error("bank regions unavailable", 0) end
            return unpack(self.regions)
        end
        local footer = CreateFrame("Frame", nil, panel); panel.MoneyFrame = footer
        footer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, 3); footer:SetSize(394, options.footerHeight or 25)
        bankPart(footer)
        for _, name in ipairs({ "Border", "MoneyDisplay", "WithdrawButton", "DepositButton" }) do
            footer[name] = CreateFrame(name:find("Button", 1, true) and "Button" or "Frame", nil, footer)
        end
        -- Verified BankPanelMoneyFrameTemplate geometry. The balance border is
        -- deliberately178px, not a full-panel footer (Mainline XML170–207).
        footer.Border:SetSize(178, 19); footer.Border:SetPoint("LEFT", footer, "LEFT", 0, 0)
        footer.MoneyDisplay:SetSize(128, 13)
        footer.MoneyDisplay:SetPoint("RIGHT", footer.Border, "RIGHT", 0, 0)
        footer.WithdrawButton:SetSize(105, 21)
        footer.WithdrawButton:SetPoint("LEFT", footer.Border, "RIGHT", 5, 1)
        footer.DepositButton:SetSize(105, 21)
        footer.DepositButton:SetPoint("LEFT", footer.WithdrawButton, "RIGHT", 1, 0)
        for _, name in ipairs({ "Border", "MoneyDisplay", "WithdrawButton", "DepositButton" }) do
            protectAnchors(footer[name])
        end
        function footer.MoneyDisplay:Refresh()
            self.moneyType = bank.kind == Enum.BankType.Account and "ACCOUNT" or "PLAYER"
            -- The generic SmallMoneyFrame renderer chooses content width and
            -- height13. Width128 is representative; no coin-width claim needed.
            self:SetSize(128, 13)
            self.refreshes = (self.refreshes or 0) + 1
        end
        function footer.WithdrawButton:Refresh()
            local supported = C_Bank.DoesBankTypeSupportMoneyTransfer(bank.kind)
            self:SetShown(supported)
            self:SetEnabled(supported and C_Bank.CanWithdrawMoney(bank.kind))
        end
        function footer.DepositButton:Refresh()
            local supported = C_Bank.DoesBankTypeSupportMoneyTransfer(bank.kind)
            self:SetShown(supported)
            self:SetEnabled(supported and C_Bank.CanDepositMoney(bank.kind))
        end
        function footer:RefreshContents()
            self.WithdrawButton:Refresh(); self.DepositButton:Refresh(); self.MoneyDisplay:Refresh()
            self.nativeTransferShown = self.WithdrawButton:IsShown() and self.DepositButton:IsShown()
        end
        function footer:UpdateMoneyDisplayAnchoring()
            local buttons = self.WithdrawButton:IsShown() and self.DepositButton:IsShown()
            self:SetWidth(buttons and 394 or 180)
        end
        footer.enabled = nil -- Native footer has no enabled property or getter.
        footer.IsEnabled = function() error("native bank footer has no enabled getter", 0) end
        function footer:Refresh()
            self.refreshes = (self.refreshes or 0) + 1
            if not self:IsShown() then return end
            self:RefreshContents(); self:UpdateMoneyDisplayAnchoring()
        end
        function footer:SetEnabled(enabled) self:SetShown(enabled); self:Refresh() end
        footer:SetScript("OnShow", function(owner) owner:Refresh() end)
        local nativeShow, nativeHide = footer.Show, footer.Hide
        function footer:Show()
            if not f.nativeWrites then assert(f.combat == false and self.permission == true, "footer restore needs permission") end
            if self.rejectShow and not f.nativeWrites then return false end
            return nativeShow(self)
        end
        function footer:Hide()
            if not f.nativeWrites then assert(f.combat == false and self.permission == true, "footer hide needs permission") end
            if self.rejectHide and not f.nativeWrites then return false end
            return nativeHide(self)
        end
        function panel:SetMoneyFrameEnabled(enabled) self.MoneyFrame:SetEnabled(enabled) end
        function panel:GenerateItemSlotsForSelectedTab(slots)
            slots = slots or self.slotCount or 48; self.slotCount = slots
            f.nativeWrites = true
            bank.nativeHeight = 460 + math.max(0, (math.ceil(slots / 8) - 6) * 47)
            bank:SetHeight(bank.nativeHeight); self:SetHeight(bank.nativeHeight)
            self.items = {}
            for index = 1, slots do
                local item = CreateFrame("Button", nil, self)
                item.slot, item.row = index, math.floor((index - 1) / 8)
                item:SetPoint("TOPLEFT", self, "TOPLEFT", 30 + ((index - 1) % 8) * 47, -63 - item.row * 47)
                geometry(item, "item", 0, 37, 37)
                self.items[index] = item
            end
            f.nativeWrites = false
        end
        function bank:Refresh(slots, enabled)
            panel:GenerateItemSlotsForSelectedTab(slots)
            f.nativeWrites = true; panel:SetMoneyFrameEnabled(enabled ~= false); f.nativeWrites = false
        end
        function bank:AddBagButton(top)
            local button = CreateFrame("Button", nil, self); button:SetScale(0.75)
            button:SetPoint("LEFT", self, "BOTTOMLEFT", 200, top - 37 * 0.75 / 2)
            geometry(button, "lower", top - 37 * 0.75, 37, 37)
            self.bagButtons[#self.bagButtons + 1] = button
            return button
        end
        bank:Refresh(config.slots or 48, config.enabled)
        if config.hidden then bank:Hide() end
        protectAnchors(bank); protectAnchors(panel); protectAnchors(footer)
        self.banks[#self.banks + 1] = bank
        return bank
    end
    if not options.lazy then BankFrame = f:bank(options) end
    loadAddon(core, "Menubar"); loadAddon(root, "Menubar_Currency")
    -- Controller transition cases begin with an explicit existing opt-out.
    local db = MenubarModel.Initialize(nil, "Tester - Test Realm")
    MenubarModel.AddWidget(db, "Tester - Test Realm", "currency", { hideBagMoney = false })
    MenubarDB = db; Menubar:Start()
    f.host = Menubar
    for _, widget in pairs(Menubar.runtime) do if widget.instance.type == "currency" then f.widget = widget; break end end
    assert(f.widget and not f.widget.failed, "Currency must initialize through its TOC")
    function f:step(count)
        for _ = 1, count or 2 do
            for _, frame in ipairs(Stub.frames) do
                if frame:IsVisible() and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.3) end
            end
        end
    end
    function f:event(name, ...)
        for _, frame in ipairs(Stub.frames) do
            if frame.events and frame.events[name] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, name, ...) end
        end
    end
    function f:tip()
        local tip = { lines = {} }
        function tip:AddLine(text) self.lines[#self.lines + 1] = text end
        function tip:AddDoubleLine() end
        self.widget.definition.tooltip(self.widget, tip)
        return table.concat(tip.lines, "\n")
    end
    function f:request(enabled, widget, defer)
        widget = widget or self.widget
        self.host.UI:OpenWidget(widget.id)
        local caption
        for _, setting in ipairs(widget.definition.settings) do if setting.key == "hideBagMoney" then caption = setting.label end end
        local checkbox
        for _, control in ipairs(self.host.UI.window.controls) do if control.caption == caption then checkbox = control; break end end
        assert(checkbox, "hideBagMoney must remain an ordinary native setting")
        if checkbox:GetChecked() ~= enabled then checkbox:Click() end
        equal(widget.settings.hideBagMoney, enabled); assert(not widget.failed, widget.failed)
        if not defer then self:step() end
    end
    function f:unchanged(bank)
        bank = bank or BankFrame; local panel, footer = bank.BankPanel, bank.BankPanel.MoneyFrame
        equal(footer:GetHeight(), 25); equal(footer:GetParent(), panel)
        for _, name in ipairs({ "Border", "MoneyDisplay", "WithdrawButton", "DepositButton" }) do
            equal(footer[name]:GetParent(), footer)
            local expectedShown = true
            if name == "WithdrawButton" or name == "DepositButton" then
                expectedShown = footer.nativeTransferShown ~= false
            end
            equal(footer[name]:IsShown(), expectedShown)
            equal(footer[name].points, footer[name].savedPoints)
        end
        equal(panel:GetParent(), bank); equal(bank:GetParent(), UIParent)
        for _, frame in ipairs({ bank, panel, footer, bank.BagText, bank.BagCost, panel.MoneyDisplay, panel.PurchaseButton }) do
            equal(frame.points, frame.savedPoints, "retained anchor table")
        end
        for _, control in ipairs({ bank.BagText, bank.BagCost, panel.MoneyDisplay, panel.PurchaseButton }) do
            equal(control.tint, control.savedTint, "sibling artwork/tint")
        end
        equal(bank.BagText:IsShown(), true); equal(bank.BagCost:IsShown(), true)
        equal(panel.MoneyDisplay:IsShown(), false); equal(panel.PurchaseButton:IsShown(), false)
        equal(#panel.items, panel.slotCount)
        for index, item in ipairs(panel.items) do
            equal(item.slot, index); equal(item.points, item.savedPoints)
            equal(item:IsShown(), true); equal(item:IsRectValid(), true)
            local _, low, width, tall = item:GetRect()
            assert(type(low) == "number" and width > 0 and tall > 0, "items retain valid positive rectangles")
        end
        for _, button in ipairs(bank.bagButtons) do equal(button:GetScale(), 0.75); equal(button.points, button.savedPoints) end
        equal(bank.divider.points, bank.divider.savedPoints, "retained divider anchors")
        equal(bank.divider:GetScale(), 0.48); equal(bank.divider:GetAtlas(), "bank-divider")
    end
    function f:hidden(delta, bank)
        bank = bank or BankFrame
        equal(bank.BankPanel.MoneyFrame:IsShown(), false)
        near(bank:GetHeight(), bank.nativeHeight - delta)
        near(bank.BankPanel:GetHeight(), bank.nativeHeight - delta)
    end
    function f:restored(bank, shown)
        bank = bank or BankFrame
        near(bank:GetHeight(), bank.nativeHeight); near(bank.BankPanel:GetHeight(), bank.nativeHeight)
        equal(bank.BankPanel.MoneyFrame:IsShown(), shown ~= false)
    end
    function f:framing(y, bank)
        bank = bank or BankFrame
        for _, region in ipairs({ bank.BankPanel.NineSlice, bank.Background }) do
            local point, parent, relative, x, offset = region:GetPoint(2)
            equal(point, "BOTTOMRIGHT"); equal(parent, region:GetParent()); equal(relative, "BOTTOMRIGHT")
            equal(x, 0); near(offset, y)
            equal(region.points[1], region.savedTop, "top and sides remain native")
        end
        equal(bank.BankPanel.EdgeShadows.points, bank.BankPanel.EdgeShadows.savedPoints)
        equal(bank.BankPanel.EdgeShadows.points[2][2], bank.BankPanel.NineSlice)
    end
    return f
end

-- Keep the earlier positive-reclaim/ownership fault tests meaningful. These
-- deliberately roomy layouts are not the observed native y220 divider layout.
local function roomyFixture(options)
    options = options or {}; options.dividerTop = options.dividerTop or 90
    return fixture(options)
end

check("the observed 507-height native bank retains its arrow divider when the money bar is hidden", function()
    local f = fixture({ slots = 54, bankScale = 0.711111, lowerTop = 107.0000001, heightQuantum = 1 / 16 })
    local bank, panel = BankFrame, BankFrame.BankPanel
    equal(bank:GetHeight(), 507); equal(panel:GetHeight(), 507)
    local _, itemBottom = panel.items[54]:GetRect()
    local _, dividerBottom, _, dividerHeight = bank.divider:GetRect()
    near(itemBottom * panel.items[54]:GetEffectiveScale()
        - (dividerBottom + dividerHeight) * bank.divider:GetEffectiveScale(), 4.04 * bank:GetEffectiveScale())
    f:request(true); f:hidden(0); f:framing(5); f:unchanged()
    equal(bank.heightWrites or 0, 0); equal(panel.heightWrites or 0, 0)
    local regions, reads, enumerations = bank.regionReads, f.rectReads, f.itemEnumerations
    f:step(20)
    equal(bank.regionReads, regions); equal(f.rectReads, reads); equal(f.itemEnumerations, enumerations)
    equal(bank.heightWrites or 0, 0); equal(panel.heightWrites or 0, 0)
    bank:Refresh(88, true); f:step(); f:hidden(0)
    bank:Refresh(54, true); f:step(); f:hidden(0)
    f:request(false); f:restored(); f:framing(30)
end)

check("native divider measurement composes with parent scaling and still allows genuinely spare space", function()
    for _, scales in ipairs({ { 1, 1 }, { 1.25, 0.8 }, { 0.8, 0.711111 } }) do
        local f = fixture({ uiScale = scales[1], bankScale = scales[2], slots = 54 })
        BankFrame:AddBagButton(115)
        f:request(true); f:hidden(0); f:unchanged()
        BankFrame:Refresh(8, true); f:step(); f:hidden(25)
        local bank, panel = BankFrame, BankFrame.BankPanel
        local _, low = panel.items[8]:GetRect()
        local _, bottom, _, tall = bank.divider:GetRect()
        assert(low * panel.items[8]:GetEffectiveScale()
            - (bottom + tall) * bank.divider:GetEffectiveScale() >= 4 * bank:GetEffectiveScale())
        f:request(false); f:restored()
    end
end)

check("unresolved divider identity or geometry restores prior owned shrink while keeping money hidden", function()
    for _, kind in ipairs({ "missing", "duplicate", "hidden", "secret-region", "secret-count", "oversized-count",
        "throw-regions", "missing-regions", "wrong-parent", "forbidden", "unknown-forbidden", "secret-atlas", "throw-atlas",
        "unknown-type", "secret-type", "missing-atlas", "secret-rect", "throw-rect", "invalid-rect", "secret-scale" }) do
        local f = roomyFixture({ slots = 54, lowerTop = 107.0000001, heightQuantum = 1 / 16 })
        local bank, divider = BankFrame, BankFrame.divider
        f:request(true); f:hidden(13.9375)
        equal(bank:GetHeight(), 493.0625, "the traced old resize remains covered in a proven-room fixture")
        if kind == "missing" then table.remove(bank.regions, 2)
        elseif kind == "duplicate" then
            local duplicate = bank:CreateTexture(nil, "ARTWORK"); duplicate:SetAtlas("bank-divider")
            bank.regions[#bank.regions + 1] = duplicate
        elseif kind == "hidden" then divider:Hide()
        elseif kind == "secret-region" then bank.regions[1] = f.secret
        elseif kind == "secret-count" then bank.regionCountValue = f.secret
        elseif kind == "oversized-count" then bank.regionCountValue = 129
        elseif kind == "throw-regions" then bank.regionError = true
        elseif kind == "missing-regions" then bank.GetRegions = false
        elseif kind == "wrong-parent" then divider.parent = bank.BankPanel
        elseif kind == "forbidden" then divider.IsForbidden = function() return true end
        elseif kind == "unknown-forbidden" then divider.IsForbidden = function() return f.secret end
        elseif kind == "secret-atlas" then divider.GetAtlas = function() return f.secret end
        elseif kind == "throw-atlas" then divider.GetAtlas = function() error("unavailable") end
        elseif kind == "unknown-type" then divider.GetObjectType = function() return nil end
        elseif kind == "secret-type" then divider.GetObjectType = function() return f.secret end
        elseif kind == "missing-atlas" then divider.GetAtlas = false
        elseif kind == "secret-rect" then divider.rectValue = f.secret
        elseif kind == "throw-rect" then divider.rectError = true
        elseif kind == "invalid-rect" then divider.rectValid = false
        else divider.GetEffectiveScale = function() return f.secret end end
        -- Existing display invalidation remeasures without replacing the
        -- currently owned reduced root/panel heights first.
        f:event("UI_SCALE_CHANGED")
        f:step(); f:hidden(0); f:framing(5)
        equal(f.widget.failed, nil, kind)
        f:request(false); f:restored(); f:framing(30)
    end
end)

check("known direct font and line regions do not conceal the unique divider", function()
    local f = fixture()
    local label = BankFrame:CreateFontString(nil, "ARTWORK"); label.GetAtlas = false
    local line = BankFrame:CreateTexture(nil, "ARTWORK")
    line.GetObjectType = function() return "Line" end; line.GetAtlas = false
    table.insert(BankFrame.regions, 1, label); table.insert(BankFrame.regions, 2, line)
    f:request(true); f:hidden(0); f:request(false); f:restored()
end)

check("the existing money toggle hides only the Character-bank balance footer and reclaims the proven gap", function()
    local f = roomyFixture(); f:restored(); f:unchanged()
    f:request(true); f:hidden(14); f:unchanged(); f:framing(5)
    f:request(false); f:restored(); f:unchanged(); f:framing(30)
end)

check("repeated reconciliation and completed native page generation never accumulate shrink", function()
    local f = roomyFixture(); f:request(true)
    for _ = 1, 8 do f:step(); f.host:RefreshWidget(f.widget.id); f:hidden(14) end
    BankFrame:Refresh(88, true); f:step(); equal(BankFrame.nativeHeight, 695); f:hidden(14); f:unchanged()
    BankFrame:Refresh(48, true); f:step(); f:hidden(14)
    f:request(false); f:restored(); f:unchanged()
end)

check("safe reclaim is capped by the footer and correctly compares scaled active bag controls", function()
    local capped = roomyFixture({ lowerTop = 80 }); capped:request(true); capped:hidden(25); capped:unchanged()
    local scaled = roomyFixture({ uiScale = 1.25, bankScale = 0.8 })
    BankFrame:AddBagButton(115)
    scaled:request(true); scaled:hidden(6); scaled:unchanged()
    local item = BankFrame.BankPanel.items[#BankFrame.BankPanel.items]
    local _, itemBottom = item:GetRect(); itemBottom = itemBottom * item:GetEffectiveScale()
    local button = BankFrame.bagButtons[1]; local _, buttonBottom, _, buttonHeight = button:GetRect()
    local buttonTop = (buttonBottom + buttonHeight) * button:GetEffectiveScale()
    near(itemBottom - buttonTop, 4 * BankFrame:GetEffectiveScale(), "retained controls keep a visible margin")
end)

check("overlapping, missing, restricted or invalid geometry hides the footer without speculative shrinking", function()
    for _, kind in ipairs({ "overlap", "tiny-gap", "invalid-item", "restricted-item", "throw-item", "missing-control", "restricted-control", "missing-pool", "restricted-scale", "different-scale", "empty-items" }) do
        local f = roomyFixture(); local bank, panel = BankFrame, BankFrame.BankPanel
        if kind == "overlap" then bank.BagText.bottomOffset = 100
        elseif kind == "tiny-gap" then bank.BagText.bottomOffset = 82
        elseif kind == "invalid-item" then panel.items[1].rectValid = false
        elseif kind == "restricted-item" then panel.items[1].rectValue = f.secret
        elseif kind == "throw-item" then panel.items[1].rectError = true
        elseif kind == "missing-control" then bank.BagText = nil
        elseif kind == "restricted-control" then bank.BagCost = f.secret
        elseif kind == "missing-pool" then bank.itemButtonBagPool = nil
        elseif kind == "restricted-scale" then bank.scaleValue = f.secret
        elseif kind == "different-scale" then panel:SetScale(0.9)
        else panel.items = {} end
        f:request(true); f:hidden(0)
        f:request(false); f:restored()
    end
end)

check("Character scope and latest native enabled policy survive account switches and purchase prompts", function()
    local f = roomyFixture(); f:request(true); f:hidden(14); f:framing(5)
    BankFrame.kind = Enum.BankType.Account; BankFrame:Refresh(48, true); f:step(); f:restored(); f:framing(30)
    BankFrame.kind = Enum.BankType.Character; BankFrame:Refresh(48, true); f:step(); f:hidden(14); f:framing(5)
    local footer = BankFrame.BankPanel.MoneyFrame
    footer:SetEnabled(false); f:step(); f:restored(nil, false); f:framing(30)
    f:request(false); f:restored(nil, false)
    footer:SetEnabled(true); f:request(true); f:hidden(14)
    f:request(false); f:restored(); f:unchanged()
end)

check("unknown or restricted active bank types never qualify as the Character bank", function()
    for _, kind in ipairs({ "missing", "restricted", "unknown" }) do
        local f = roomyFixture()
        BankFrame.kind = kind == "restricted" and f.secret or (kind == "unknown" and 99 or nil)
        f:request(true); f:restored()
        BankFrame.kind = Enum.BankType.Character; BankFrame:Refresh(48, true); f:step(); f:hidden(14)
    end
end)

check("the last live Currency request restores while duplicates, disable and removal stay independent", function()
    local f = roomyFixture(); f:request(true)
    local instance = f.host:AddWidget("currency"); local second = f.host.runtime[instance.id]
    f:request(true, second); f:request(false); f:hidden(14); f:framing(5)
    second.instance.enabled = false; f.host:Rebuild(); f:step(); f:restored(); f:framing(30)
    second.instance.enabled = true; f.host:Rebuild(); f:step(); f:hidden(14); f:framing(5)
    f.host:RemoveWidget(second.id); f:step(); f:restored(); f:framing(30)
    f:request(true); f.host:RemoveWidget(f.widget.id); f:step(); f:restored()
end)

check("combat and denied protected-state permission defer suppression and last-request restoration", function()
    local f = roomyFixture(); f.combat = true; f:request(true); f:restored()
    f.combat = false; f:event("PLAYER_REGEN_ENABLED"); f:step(); f:hidden(14)
    f.combat = true; f:request(false); f:hidden(14)
    f.combat = false; BankFrame.BankPanel.permission = false
    f:event("PLAYER_REGEN_ENABLED"); f:step(); f:hidden(14)
    BankFrame.BankPanel.permission = true; f:step(); f:restored()
    BankFrame.BankPanel.MoneyFrame.permission = f.secret; f:request(true); f:restored()
    BankFrame.BankPanel.MoneyFrame.permission = true; f:step(); f:hidden(14)
end)

check("lazy discovery and replacement frames restore previous ownership without loading or moving UI", function()
    local f = roomyFixture({ lazy = true }); f:request(true)
    BankFrame = f:bank(); f:event("BANKFRAME_OPENED"); f:step(); f:hidden(14)
    local previous = BankFrame
    BankFrame = f:bank({ slots = 88 }); f:step()
    f:restored(previous); f:hidden(14); f:unchanged(previous); f:unchanged()
    BankFrame:Hide(); f:step(); f:restored()
    BankFrame:Show(); f:step(); f:hidden(14)
end)

check("failed writes retain a recoverable layout and latest native heights are restored after recovery", function()
    local rejected = roomyFixture(); BankFrame.BankPanel.MoneyFrame.rejectHide = true
    rejected:request(true); rejected:restored(); equal(rejected.widget.failed, nil)
    BankFrame.BankPanel.MoneyFrame.rejectHide = false; rejected:step(); rejected:hidden(14)
    local f = roomyFixture(); BankFrame.BankPanel.rejectHeight = true
    f:request(true); equal(f.widget.failed, nil)
    near(BankFrame:GetHeight(), 460); near(BankFrame.BankPanel:GetHeight(), 460)
    BankFrame.BankPanel.rejectHeight = false; f:step(); f:hidden(14)
    BankFrame:Refresh(88, true); f:step(); f:hidden(14)
    BankFrame.BankPanel.MoneyFrame.rejectShow = true
    f:request(false); equal(BankFrame.BankPanel.MoneyFrame:IsShown(), false)
    BankFrame.BankPanel.MoneyFrame.rejectShow = false; f:step(); f:restored(); f:unchanged()
end)

check("widget render failure releases the bank request and fresh successful rendering can recover", function()
    local f = roomyFixture(); f:request(true); f:hidden(14)
    local setText = f.widget.SetText
    f.widget.SetText = function() error("Currency rendering rejected", 0) end
    f.host:RefreshWidget(f.widget.id); f:step()
    equal(f.widget.failed, "Currency rendering rejected"); f:restored()
    f.widget.SetText = setText; f.host:RefreshWidget(f.widget.id); f:step()
    equal(f.widget.failed, nil); f:hidden(14)
end)

check("an unreadable second native-height read never reaches a resize or rollback setter", function()
    for _, kind in ipairs({ "missing", "restricted", "nan", "zero", "overflow" }) do
        local f = roomyFixture(); f:request(true); f:hidden(14)
        local value
        if kind == "missing" then value = f.nilRead
        elseif kind == "restricted" then value = f.secret
        elseif kind == "nan" then value = 0 / 0
        elseif kind == "zero" then value = 0
        else value = math.huge end
        local bank, panel = BankFrame, BankFrame.BankPanel
        local bankWrites, panelWrites = bank.heightWrites, panel.heightWrites
        bank.heightSequence = { bank.height, value }
        f:request(false, nil, true)
        equal(bank.heightWrites, bankWrites, kind); equal(panel.heightWrites, panelWrites, kind)
        equal(f.widget.failed, nil, kind)
        f:step(); f:restored()
    end
end)

check("native partial height pairs wait for a complete page and restore the newest baseline", function()
    local f = roomyFixture(); f:request(true); f:hidden(14)
    f.nativeWrites = true; BankFrame:SetHeight(695); f.nativeWrites = false
    f:step(); equal(BankFrame:GetHeight(), 695); equal(BankFrame.BankPanel:GetHeight(), 446)
    BankFrame:Refresh(88, true); f:step(); f:hidden(14)
    f:request(false); f:restored(); equal(BankFrame:GetHeight(), 695)
end)

check("an initially native-disabled footer retains that policy until a normal native enable", function()
    local f = roomyFixture({ enabled = false }); f:request(true); f:restored(nil, false)
    f:request(false); f:restored(nil, false)
    f:request(true); BankFrame:Refresh(48, true); f:step(); f:hidden(14)
    f:request(false); f:restored()
end)

check("a native lock arriving during combat remains the latest policy when restoration is permitted", function()
    local f = roomyFixture(); f:request(true); f:hidden(14)
    f.combat, f.nativeWrites = true, true
    BankFrame.BankPanel:SetMoneyFrameEnabled(false)
    f.nativeWrites = false; f:step(); f:hidden(14)
    f.combat = false; f:event("PLAYER_REGEN_ENABLED"); f:step(); f:restored(nil, false)
    f:request(false); f:restored(nil, false)
end)

check("uncertain bank policy hooks stay bounded and do not block a later native bank", function()
    for _, target in ipairs({ "SetEnabled", "GenerateItemSlotsForSelectedTab" }) do
        for _, failure in ipairs({ "refuse", "attach-throw" }) do
            local f = roomyFixture(); local bank = BankFrame
            local owner = target == "SetEnabled" and bank.BankPanel.MoneyFrame or bank.BankPanel
            local hook, attempts = hooksecurefunc, 0
            hooksecurefunc = function(object, method, callback)
                if object == owner and method == target then
                    attempts = attempts + 1
                    if failure == "refuse" then return false end
                    hook(object, method, callback); error("bank observer attached before failure", 0)
                end
                return hook(object, method, callback)
            end
            f:request(true); f:restored(); f:framing(30); f:step(20)
            equal(attempts, 1)
            equal(f.hooks[owner] and f.hooks[owner][target] or 0, failure == "attach-throw" and 1 or 0)
            equal(bank.heightWrites or 0, 0); equal(bank.BankPanel.heightWrites or 0, 0)
            assert(f:tip():find("Reload the UI", 1, true))
            if target == "GenerateItemSlotsForSelectedTab" then equal(f.hooks[bank.BankPanel.MoneyFrame].SetEnabled, 1) end
            hooksecurefunc = hook; f:step(5); f:restored(); f:framing(30)
            BankFrame = f:bank(); f:step(); f:hidden(14); f:framing(5); f:restored(bank)
            assert(not f:tip():find("Reload the UI", 1, true), "old failed bank must not taint its healthy replacement")
            f:request(false); f:restored(); f:framing(30); f:restored(bank)
            equal(attempts, 1)
        end
    end
end)

check("missing native hook support leaves the footer alone and can recover without changing settings", function()
    local f = roomyFixture(); local nativeHook = hooksecurefunc
    hooksecurefunc = nil; f:request(true); f:restored()
    hooksecurefunc = nativeHook; f:step(); f:hidden(14)
    equal(f.widget.settings.hideBagMoney, true); equal(f.widget.failed, nil)
end)

check("settled bank geometry is reused during periodic updates and refreshed after native generation", function()
    local f = roomyFixture({ slots = 88 }); f:request(true); f:hidden(14); f:step()
    local reads, enumerations = f.rectReads, f.itemEnumerations
    f:step(20)
    equal(f.rectReads, reads, "steady rectangle reads"); equal(f.itemEnumerations, enumerations, "steady item enumeration")
    BankFrame:Refresh(48, true); f:step(); f:hidden(14)
    assert(f.rectReads > reads and f.itemEnumerations > enumerations, "completed native generation invalidates geometry")
    reads, enumerations = f.rectReads, f.itemEnumerations
    f:step(20); equal(f.rectReads, reads); equal(f.itemEnumerations, enumerations)
end)

check("releasing an unequal foreign resize restores only still-owned dimensions and finishes footer cleanup", function()
    for _, kind in ipairs({ "bank", "panel", "both" }) do
        local f = roomyFixture(); f:request(true); f:hidden(14)
        local bank, panel = BankFrame, BankFrame.BankPanel
        local controllers = {}
        for _, frame in ipairs(f.Stub.frames) do
            -- Core also retries pending character identity on combat exit.
            if frame ~= f.host.eventFrame and frame.events and frame.events.PLAYER_REGEN_ENABLED and frame.scripts.OnUpdate then
                controllers[#controllers + 1] = frame
            end
        end
        equal(#controllers, 1, "one shared native money controller")
        f.nativeWrites = true
        if kind ~= "panel" then bank:SetHeight(500) end
        if kind ~= "bank" then panel:SetHeight(510) end
        local nativeShown = kind ~= "panel"
        panel:SetMoneyFrameEnabled(nativeShown)
        f.nativeWrites = false
        f:request(false)
        equal(bank:GetHeight(), kind == "panel" and 460 or 500, kind)
        equal(panel:GetHeight(), kind == "bank" and 460 or 510, kind)
        equal(panel.MoneyFrame:IsShown(), nativeShown, kind)
        for _, controller in ipairs(controllers) do
            equal(controller:IsShown(), false, "released controller stops polling")
            equal(next(controller.events), nil, "released controller stops listening")
        end
        local bankWrites, panelWrites, refreshes = bank.heightWrites, panel.heightWrites, panel.MoneyFrame.refreshes
        f:step(20)
        equal(bank.heightWrites, bankWrites); equal(panel.heightWrites, panelWrites)
        equal(panel.MoneyFrame.refreshes, refreshes)
    end
end)

check("a transient read after an accepted resize never promotes the owned reduced height to a native baseline", function()
    for _, component in ipairs({ "bank", "panel" }) do
        for _, kind in ipairs({ "missing", "restricted" }) do
            local f = roomyFixture(); local frame = component == "bank" and BankFrame or BankFrame.BankPanel
            local transient = kind == "missing" and f.nilRead or f.secret
            frame.heightSequence = { 460, 460, 460, 446, transient }
            f:request(true, nil, true)
            equal(BankFrame.height, 446); equal(BankFrame.BankPanel.height, 446)
            f:step(3); f:request(false); f:restored()
            equal(f.widget.failed, nil)
        end
    end
end)

check("a rejected paired resize and unreadable rollback retain ownership until a safe full restoration", function()
    for _, kind in ipairs({ "missing", "restricted" }) do
        local f = roomyFixture(); local bank, panel = BankFrame, BankFrame.BankPanel
        local transient = kind == "missing" and f.nilRead or f.secret
        bank.heightWriteSequence = { "accept", "reject" }
        panel.heightWriteSequence = { "reject", "accept" }
        bank.heightSequence = { 460, 460, 460, 446, transient }
        panel.heightSequence = { 460, 460, 460, transient }
        f:request(true, nil, true)
        equal(bank.height, 446); equal(panel.height, 460)
        f:request(false, nil, true); f:step(3); f:restored()
        equal(f.widget.failed, nil)
        local bankWrites, panelWrites = bank.heightWrites, panel.heightWrites
        f:step(20); equal(bank.heightWrites, bankWrites); equal(panel.heightWrites, panelWrites)
    end
end)

check("limited native height precision accepts conservative reclaim once without resize retries", function()
    local f = roomyFixture({ lowerTop = 107.0000001, heightQuantum = 1 / 16 })
    f:request(true); f:hidden(13.9375); f:unchanged()
    local bank, panel = BankFrame, BankFrame.BankPanel
    equal(bank:GetHeight(), 446.0625); equal(panel:GetHeight(), 446.0625)
    local bankWrites, panelWrites, enumerations = bank.heightWrites, panel.heightWrites, f.itemEnumerations
    f:step(20)
    equal(bank.heightWrites, bankWrites); equal(panel.heightWrites, panelWrites)
    equal(f.itemEnumerations, enumerations)
    f:request(false); f:restored()
end)

check("the observed native footer precision removes reserved framing without repeated anchor writes", function()
    local f = roomyFixture({ footerHeight = 24.999988555908, pointQuantum = 1 / 16 })
    f:request(true); f:hidden(14); f:framing(5.0625)
    local inset, background = BankFrame.BankPanel.NineSlice, BankFrame.Background
    equal(background.kind, "Texture", "the outer background is a Region, not a Frame")
    local writes = inset.anchorWrites + background.anchorWrites
    f:step(20); equal(inset.anchorWrites + background.anchorWrites, writes)
    BankFrame:Refresh(88, true); f:step(); f:hidden(14); f:framing(5.0625)
    equal(inset.anchorWrites + background.anchorWrites, writes)
    f:request(false); f:restored(); f:framing(30)
end)

check("missing restricted scaled or denied framing stays unchanged and recovers on the same native regions", function()
    for _, mode in ipairs({ "missing", "restricted", "scale", "permission", "getter" }) do
        local f = roomyFixture(); local bank, panel = BankFrame, BankFrame.BankPanel
        local inset, background = panel.NineSlice, bank.Background
        local repair
        if mode == "missing" then
            bank.Background = nil; repair = function() bank.Background = background end
        elseif mode == "restricted" then
            background.pointReadFailure = "restricted"; repair = function() background.pointReadFailure = nil end
        elseif mode == "scale" then
            background:SetScale(0.75); repair = function() background:SetScale(1) end
        elseif mode == "permission" then
            background.permission = false; repair = function() background.permission = true end
        else
            local getPoint = background.GetPoint; background.GetPoint = false
            repair = function() background.GetPoint = getPoint end
        end
        f:request(true); f:hidden(14)
        equal(inset.anchorWrites, 0, mode); equal(background.anchorWrites, 0, mode)
        equal(inset.points[2][5], 30); equal(background.points[2][5], 30)
        repair(); f:step(); f:framing(5)
        f:request(false); f:restored(); f:framing(30)
    end
end)

check("combat and denied Region permission defer the last framing restoration", function()
    local f = roomyFixture(); f:request(true); f:framing(5)
    local inset, background = BankFrame.BankPanel.NineSlice, BankFrame.Background
    f.combat = true; f:request(false); f:framing(5)
    f.combat = false; background.permission = false
    f:event("PLAYER_REGEN_ENABLED"); f:step()
    equal(inset.points[2][5], 30); equal(background.points[2][5], 5)
    equal(BankFrame.BankPanel.MoneyFrame:IsShown(), false)
    background.permission = true; f:step(); f:restored(); f:framing(30)
    local writes = inset.anchorWrites + background.anchorWrites
    f:step(20); equal(inset.anchorWrites + background.anchorWrites, writes)
end)

check("foreign bottom top or parent changes relinquish only that framing region's complete layout", function()
    for _, mode in ipairs({ "bottom", "top", "parent" }) do
        local f = roomyFixture(); f:request(true); f:framing(5)
        local inset, background = BankFrame.BankPanel.NineSlice, BankFrame.Background
        f.nativeWrites = true
        if mode == "bottom" then background:SetPoint("BOTTOMRIGHT", BankFrame, "BOTTOMRIGHT", 2, 12)
        elseif mode == "top" then background:SetPoint("TOPLEFT", BankFrame, "TOPLEFT", 3, -19)
        else background.parent = UIParent end
        f.nativeWrites = false
        local top, bottom, parent = background.points[1], background.points[2], background:GetParent()
        local writes = background.anchorWrites
        f:step(); f:request(false); f:restored()
        equal(background.points[1], top, mode); equal(background.points[2], bottom, mode)
        equal(background:GetParent(), parent, mode); equal(background.anchorWrites, writes, mode)
        equal(inset.points[2][5], 30)
        f:step(20); equal(background.anchorWrites, writes)
    end
end)

check("a rejected framing write rolls back the pair and later retries without accumulating offsets", function()
    local f = roomyFixture(); local inset, background = BankFrame.BankPanel.NineSlice, BankFrame.Background
    background.anchorWriteSequence = { "reject" }
    f:request(true, nil, true); f:hidden(14); f:framing(30)
    f:step(); f:framing(5)
    inset.anchorWriteSequence = { "reject" }
    f:request(false, nil, true)
    equal(inset.points[2][5], 5); equal(background.points[2][5], 30)
    equal(BankFrame.BankPanel.MoneyFrame:IsShown(), false)
    f:step(); f:restored(); f:framing(30)
end)

check("applied points survive unreadable write readback and rollback until explicit restoration", function()
    for _, kind in ipairs({ "missing", "restricted" }) do
        local f = roomyFixture(); local inset, background = BankFrame.BankPanel.NineSlice, BankFrame.Background
        local setPoint, first = inset.SetPoint, true
        function inset:SetPoint(...)
            local result = setPoint(self, ...)
            if first then self.pointReadSequence = { kind, kind }; first = false end
            return result
        end
        f:request(true, nil, true)
        equal(inset.points[2][5], 5); equal(background.points[2][5], 30)
        f:request(false); f:restored(); f:framing(30)
        local writes = inset.anchorWrites + background.anchorWrites
        f:step(20); equal(inset.anchorWrites + background.anchorWrites, writes)
    end
end)

check("unreadable anchor tuples defer restoration without losing the original reserved offsets", function()
    for _, kind in ipairs({ "missing", "restricted" }) do
        local f = roomyFixture(); f:request(true); f:framing(5)
        local inset, background = BankFrame.BankPanel.NineSlice, BankFrame.Background
        inset.pointReadFailure = kind
        f:request(false)
        equal(inset.points[2][5], 5); equal(background.points[2][5], 30)
        equal(BankFrame.BankPanel.MoneyFrame:IsShown(), false)
        inset.pointReadFailure = nil; f:step(); f:restored(); f:framing(30)
        local writes = inset.anchorWrites + background.anchorWrites
        f:step(20); equal(inset.anchorWrites + background.anchorWrites, writes)
    end
end)

check("restoration retains the stock short Character balance box and native Account transfer layout", function()
    local f = roomyFixture()
    local bank, panel = BankFrame, BankFrame.BankPanel
    local footer = panel.MoneyFrame
    local function shape(width, moneyType, transfers)
        equal(footer:GetWidth(), width); equal(footer:GetHeight(), 25)
        equal(footer.Border:GetWidth(), 178); equal(footer.Border:GetHeight(), 19)
        equal(footer.MoneyDisplay.moneyType, moneyType); equal(footer.MoneyDisplay:GetHeight(), 13)
        equal(footer.WithdrawButton:IsShown(), transfers); equal(footer.DepositButton:IsShown(), transfers)
        equal(footer.WithdrawButton:IsEnabled(), transfers); equal(footer.DepositButton:IsEnabled(), transfers)
        near(footer.Border:GetLeft(), footer:GetLeft())
        near(footer.MoneyDisplay:GetRight(), footer.Border:GetRight())
        near(footer:GetRight(), panel:GetRight() - 3)
        assert(footer.Border:GetWidth() < panel:GetWidth(), "Native balance border does not span the bank")
    end
    shape(180, "PLAYER", false)
    local baseline = { footer.Border:GetRect() }
    for _ = 1, 3 do
        f:request(true); f:hidden(14); f:framing(5)
        f:request(false); f:restored(); f:framing(30); shape(180, "PLAYER", false)
        local current = { footer.Border:GetRect() }
        for index = 1, 4 do near(current[index], baseline[index]) end
    end
    bank.kind = Enum.BankType.Account; bank:Refresh(48, true); f:step()
    shape(394, "ACCOUNT", true)
    f:request(true); f:restored(); shape(394, "ACCOUNT", true)
    bank.kind = Enum.BankType.Character; bank:Refresh(48, true); f:step(); f:hidden(14)
    f:request(false); f:restored(); shape(180, "PLAYER", false)
end)

-- Actual client capture: both heights stayed507; the %.9f diagnostic printed
--5.062500477 for NineSlice and Background after SetPoint(5.0625). The model
-- below uses the adjacent binary32 value, not additional measured digits.
-- No row-height fix is implied by this anchor-only regression.
check("observed native anchor readback restores both regions and settles without repeated writes", function()
    local canonical = 5.062500476837158
    local f = fixture({ slots = 54, bankScale = 0.711111, footerHeight = 24.999988555908,
        pointReadback = function(x, y) return x, y == 5.0625 and canonical or y end })
    local bank, panel = BankFrame, BankFrame.BankPanel
    local inset, background = panel.NineSlice, bank.Background
    for _ = 1, 3 do
        f:request(true); f:hidden(0)
        equal(inset.points[2][5], canonical); equal(background.points[2][5], canonical)
        local writes = inset.anchorWrites + background.anchorWrites
        f:step(20); equal(inset.anchorWrites + background.anchorWrites, writes, "canonical target is already applied")
        f:request(false); f:restored(); f:framing(30)
        writes = inset.anchorWrites + background.anchorWrites
        f:step(20); equal(inset.anchorWrites + background.anchorWrites, writes, "restoration stops writing")
    end
    equal(bank.heightWrites or 0, 0); equal(panel.heightWrites or 0, 0)
end)

check("canonical anchor readback survives temporarily unreadable write and rollback reads", function()
    for _, kind in ipairs({ "missing", "restricted" }) do
        local f = roomyFixture({ footerHeight = 24.999988555908,
            pointReadback = function(x, y) return x, y == 5.0625 and 5.062500476837158 or y end })
        local inset = BankFrame.BankPanel.NineSlice
        local setPoint, first = inset.SetPoint, true
        function inset:SetPoint(...)
            local result = setPoint(self, ...)
            if first then self.pointReadSequence = { kind, kind }; first = false end
            return result
        end
        f:request(true, nil, true)
        f:request(false); f:restored(); f:framing(30)
    end
end)

check("synchronous foreign anchor writers retain their layout even when they repeat our requested values", function()
    local methods = { "SetPoint", "AdjustPointsOffset", "ClearPoint", "ClearAllPoints", "ClearPointsOffset", "SetAllPoints", "SetPointsOffset", "SetParent" }
    for _, which in ipairs({ "inset", "background" }) do
        for _, method in ipairs(methods) do
            local f = roomyFixture()
            local bank, panel = BankFrame, BankFrame.BankPanel
            local region = which == "inset" and panel.NineSlice or bank.Background
            local fired
            hooksecurefunc(region, "SetPoint", function(self, point, relative, relativePoint, x, y)
                if fired then return end
                fired = true; f.nativeWrites = true
                if method == "SetPoint" then self:SetPoint(point, relative, relativePoint, x, y)
                elseif method == "AdjustPointsOffset" then self:AdjustPointsOffset(0, 0)
                elseif method == "ClearPoint" then self:ClearPoint("CENTER")
                elseif method == "ClearAllPoints" then self:ClearAllPoints()
                elseif method == "ClearPointsOffset" then self:ClearPointsOffset()
                elseif method == "SetAllPoints" then self:SetAllPoints(relative)
                elseif method == "SetPointsOffset" then self:SetPointsOffset(0, 0)
                else self:SetParent(UIParent) end
                f.nativeWrites = false
            end)
            f:request(true)
            local points, parent, writes = region.points, region:GetParent(), region.anchorWrites
            assert(fired, "foreign post-hook ran")
            f:request(false); f:restored(); f:step(20)
            equal(region.points, points, which .. ":" .. method)
            equal(region:GetParent(), parent, which .. ":" .. method)
            equal(region.anchorWrites, writes, "foreign framing must not be restored")
        end
    end
end)

check("missing optional point mutators do not block SetPoint ownership or require new hooks on every activation", function()
    for _, which in ipairs({ "inset", "background" }) do
        local f = roomyFixture(); local panel = BankFrame.BankPanel
        local region = which == "inset" and panel.NineSlice or BankFrame.Background
        for _, name in ipairs({ "AdjustPointsOffset", "ClearPoint", "ClearAllPoints", "ClearPointsOffset", "SetAllPoints", "SetPointsOffset", "SetParent" }) do region[name] = false end
        for _ = 1, 3 do f:request(true); f:framing(5); f:request(false); f:restored(); f:framing(30) end
        equal(f.hooks[region].SetPoint, 1, "one permanent observer")
        local writes = region.anchorWrites
        f.nativeWrites = true; region:SetPoint("BOTTOMRIGHT", region:GetParent(), "BOTTOMRIGHT", 0, 17); f.nativeWrites = false
        f:step(20); equal(region.anchorWrites, writes); equal(region.points[2][5], 17, "released observer stays inactive")
    end
end)

check("failed or ambiguous observer registration never mutates framing or installs duplicate permanent callbacks", function()
    for _, which in ipairs({ "inset", "background" }) do
        for _, failure in ipairs({ "refuse", "attach-throw" }) do
            local f = roomyFixture(); local region = which == "inset" and BankFrame.BankPanel.NineSlice or BankFrame.Background
            local hook, attempts = hooksecurefunc, 0
            hooksecurefunc = function(owner, method, callback)
                if owner == region and method == "SetPoint" then
                    attempts = attempts + 1
                    if failure == "refuse" then return false end
                    hook(owner, method, callback); error("registration failed after attaching", 0)
                end
                return hook(owner, method, callback)
            end
            f:request(true); f:hidden(14); f:framing(30); f:step(20)
            equal(attempts, 1, failure)
            equal(BankFrame.BankPanel.NineSlice.anchorWrites, 0); equal(BankFrame.Background.anchorWrites, 0)
            f:request(false); f:restored(); f:framing(30)
        end
    end
end)

check("a successful no-op SetPoint is rejected without replacing the original baseline and can recover", function()
    local f = roomyFixture(); local region = BankFrame.Background
    local setPoint, blocked = region.SetPoint, true
    function region:SetPoint(...) if blocked then return end; return setPoint(self, ...) end
    f:request(true, nil, true); f:hidden(14); f:framing(30)
    blocked = false; f:step(); f:framing(5)
    f:request(false); f:restored(); f:framing(30)
end)

check("an unwitnessed applied canonical write stays unresolved until a confirmed native writer takes ownership", function()
    for _, which in ipairs({ "inset", "background" }) do
        local f = roomyFixture({ footerHeight = 24.999988555908,
            pointReadback = function(x, y) return x, y == 5.0625 and 5.062500476837158 or y end })
        local region = which == "inset" and BankFrame.BankPanel.NineSlice or BankFrame.Background
        local setPoint, first = region.SetPoint, true
        function region:SetPoint(...)
            local result = setPoint(self, ...)
            if first then first = false; error("native write applied before post-hook", 0) end
            return result
        end
        f:request(true, nil, true); equal(region.points[2][5], 5.062500476837158)
        f:request(false); equal(BankFrame.BankPanel.MoneyFrame:IsShown(), false, "unresolved restore must not report success")
        local writes = region.anchorWrites; f:step(20); equal(region.anchorWrites, writes, "uncertainty does not cause repeated writes")
        f.nativeWrites = true; region:SetPoint("BOTTOMRIGHT", region:GetParent(), "BOTTOMRIGHT", 0, 30); f.nativeWrites = false
        f:step(); f:restored(); f:framing(30)
    end
end)

check("scaled canonical readbacks retain original requests and settle at multiple UI scales", function()
    -- Controlled normal-range single-precision storage model, not an assertion
    -- about the client's implementation. Its public readback need not equal input.
    local function single(value)
        if value == 0 then return 0 end
        local sign = value < 0 and -1 or 1
        local mantissa, exponent = math.frexp(math.abs(value))
        return sign * math.ldexp(math.floor(mantissa * 16777216 + 0.5), exponent - 24)
    end
    for _, scale in ipairs({ 0.711111, 0.8, 1.1, 1.25 }) do
        local f = fixture({ slots = 54, bankScale = scale, footerHeight = 24.999988555908,
            pointReadback = function(x, y, region)
                local effective = region:GetEffectiveScale()
                return single(x * effective) / effective, single(y * effective) / effective
            end })
        local regions = { BankFrame.BankPanel.NineSlice, BankFrame.Background }
        for _, region in ipairs(regions) do
            local setPoint = region.SetPoint
            function region:SetPoint(point, relative, relativePoint, x, y)
                self.lastRequestedY = y
                return setPoint(self, point, relative, relativePoint, x, y)
            end
        end
        for _ = 1, 2 do
            local originals = { regions[1].points[2][5], regions[2].points[2][5] }
            f:request(true); f:hidden(0)
            local writes = regions[1].anchorWrites + regions[2].anchorWrites
            f:step(20); equal(regions[1].anchorWrites + regions[2].anchorWrites, writes)
            f:request(false); f:restored()
            for index, region in ipairs(regions) do
                equal(region.lastRequestedY, originals[index], "restore the captured original request")
                local expected = single(originals[index] * region:GetEffectiveScale()) / region:GetEffectiveScale()
                equal(region.points[2][5], expected)
            end
            writes = regions[1].anchorWrites + regions[2].anchorWrites
            f:step(20); equal(regions[1].anchorWrites + regions[2].anchorWrites, writes)
        end
    end
end)

print(passed .. " Character-bank money tests passed")
