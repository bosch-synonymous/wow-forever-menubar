-- Original Menubar money provider. The host owns each instance's settings.
local function readMoney()
    if type(GetMoney) ~= "function" then
        return nil
    end
    local ok, amount = pcall(GetMoney)
    if not ok or (type(issecretvalue) == "function" and issecretvalue(amount)) then
        return nil
    end
    if type(amount) ~= "number" or amount < 0 or amount ~= amount
        or amount == math.huge or amount ~= math.floor(amount) then
        return nil
    end
    return amount
end

local function splitMoney(amount)
    return math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100
end

local function whole(value)
    -- %.0f preserves large integer totals without a platform-sized %d conversion.
    return string.format("%.0f", value)
end

-- These are the client atlases used by Blizzard's own money presentation.
local coinIcons = {
    gold = "|A:coin-gold:14:14:0:0|a",
    silver = "|A:coin-silver:14:14:0:0|a",
    copper = "|A:coin-copper:14:14:0:0|a",
}

local function formatMoney(amount, display)
    if amount == nil then
        return "--"
    end
    local gold, silver, copper = splitMoney(amount)
    if display == "gold" then
        return whole(gold) .. string.format(".%04d", amount % 10000) .. coinIcons.gold
    elseif display == "silver" then
        return whole(math.floor(amount / 100)) .. string.format(".%02d", copper) .. coinIcons.silver
    elseif display == "copper" then
        return whole(amount) .. coinIcons.copper
    end
    return whole(gold) .. coinIcons.gold .. " " .. whole(silver) .. coinIcons.silver .. " " .. whole(copper) .. coinIcons.copper
end

local function readable(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function finite(value, minimum)
    return readable(value) and type(value) == "number" and value == value
        and value >= minimum and value < math.huge
end

local function integer(value, minimum)
    return finite(value, minimum) and value == math.floor(value)
end

local function tokenAmount(value)
    if value == math.floor(value) then return whole(value) end
    return tostring(value)
end

local function currencyCall(name, ...)
    if not readable(C_CurrencyInfo) or type(C_CurrencyInfo) ~= "table" then return nil end
    local method = C_CurrencyInfo[name]
    if not readable(method) or type(method) ~= "function" then return nil end
    local ok, value = pcall(method, ...)
    if ok and readable(value) then return value end
end

local function currencyName(value)
    if readable(value) and type(value) == "string" and value ~= "" and #value <= 256 then return value end
end

local function selectedCurrency(settings)
    local id = settings.currencyID
    if not readable(id) then return nil end
    if id == nil then return 0 end -- Existing money-only instances keep their source.
    if integer(id, 0) then return id end
end

local function currencyState(id)
    local info = currencyCall("GetCurrencyInfo", id)
    if type(info) ~= "table" or not integer(info.currencyID, 1) or info.currencyID ~= id then return nil end
    return {
        name = currencyName(info.name),
        quantity = finite(info.quantity, 0) and info.quantity or nil,
        icon = integer(info.iconFileID, 1) and info.iconFileID or nil,
        maximum = finite(info.maxQuantity, 0) and info.maxQuantity > 0 and info.maxQuantity or nil,
    }
end

local function currencyOptions()
    local result, seen = { { value = 0, label = "Money" } }, {}
    local count = currencyCall("GetCurrencyListSize")
    if not integer(count, 0) or count > 10000 then return result end
    -- Only the player's currently exposed rows are selectable. Never expand
    -- native headers, change filters or alter the backpack's tracked tokens.
    for index = 1, count do
        local info = currencyCall("GetCurrencyListInfo", index)
        if type(info) == "table" and readable(info.isHeader) and info.isHeader == false
            and integer(info.currencyID, 1) and not seen[info.currencyID] then
            local name = currencyName(info.name)
            if name then
                seen[info.currencyID] = true
                result[#result + 1] = { value = info.currencyID, label = name }
            end
        end
    end
    return result
end

local function tokenText(state, showLabel)
    if not state then return "Currency --" end
    local icon = state.icon and string.format("|T%.0f:14:14:0:0|t", state.icon)
    local prefix = icon and (icon .. " ") or ""
    if showLabel or not icon then prefix = prefix .. (state.name or "Currency") .. " " end
    return prefix .. (state.quantity ~= nil and tokenAmount(state.quantity) or "--")
end

local function click(widget)
    if type(widget.OpenChoiceMenu) ~= "function" then
        widget.currencyMessage = "Update Menubar to choose a currency from this widget."
        return false
    end
    widget.currencyMessage = nil
    return widget:OpenChoiceMenu("currencyID", "Watch currency")
end

local function stopIcons(widget)
    if type(widget.StopIconJiggle) == "function" then widget:StopIconJiggle() end
end

local function hideFragments(widget)
    local visual = widget.currencyVisual
    if visual then
        for _, icon in pairs(visual.icons) do icon:Hide() end
        for _, text in ipairs(visual.texts) do text:Hide() end
    end
    if widget.label and type(widget.label.Show) == "function" then widget.label:Show() end
end

local function fontStyle(widget)
    local label = widget.label
    if not label then return nil end
    for _, method in ipairs({ "GetFont", "GetTextColor", "GetShadowColor", "GetShadowOffset" }) do
        if type(label[method]) ~= "function" then return nil end
    end
    local path, size, flags = label:GetFont()
    if not readable(path) or type(path) ~= "string" or path == "" or not finite(size, 0) or size == 0
        or not readable(flags) or type(flags) ~= "string" then return nil end
    local style = { path, size, flags }
    local color = { label:GetTextColor() }
    local shadow = { label:GetShadowColor() }
    local x, y = label:GetShadowOffset()
    for index = 1, 4 do
        if not finite(color[index], 0) or color[index] > 1
            or not finite(shadow[index], 0) or shadow[index] > 1 then return nil end
        style[#style + 1] = color[index]
        style[#style + 1] = shadow[index]
    end
    if not readable(x) or not readable(y) or type(x) ~= "number" or type(y) ~= "number"
        or x ~= x or y ~= y or x <= -math.huge or x >= math.huge or y <= -math.huge or y >= math.huge then return nil end
    style[#style + 1], style[#style + 2] = x, y
    return style
end

local function sameStyle(first, second)
    if first == nil or second == nil then return first == second end
    for index = 1, #first do if first[index] ~= second[index] then return false end end
    return true
end

local function samePresentation(first, second)
    return first and first.id == second.id and first.display == second.display
        and first.showLabel == second.showLabel and first.hideBagMoney == second.hideBagMoney
        and first.icon == second.icon and first.presented == second.presented and sameStyle(first.style, second.style)
end

local function partsForMoney(amount, display, showLabel)
    if amount == nil then return nil end
    local prefix = showLabel and "Money " or ""
    if display == "gold" or display == "silver" or display == "copper" then
        local text = formatMoney(amount, display)
        return { { text = prefix .. text:sub(1, #text - #coinIcons[display]) }, { icon = display, atlas = "coin-" .. display } }
    end
    local gold, silver, copper = splitMoney(amount)
    return { { text = prefix .. whole(gold) }, { icon = "gold", atlas = "coin-gold" },
        { text = " " .. whole(silver) }, { icon = "silver", atlas = "coin-silver" },
        { text = " " .. whole(copper) }, { icon = "copper", atlas = "coin-copper" } }
end

local function partsForToken(state, showLabel)
    if not state or not state.icon then return nil end
    local text = (showLabel and ((state.name or "Currency") .. " ") or "")
        .. (state.quantity ~= nil and tokenAmount(state.quantity) or "--")
    return { { icon = "token", texture = state.icon }, { text = " " .. text } }
end

local function renderFragments(widget, parts, style)
    if not parts or not style or not widget.frame or type(widget.frame.CreateTexture) ~= "function"
        or type(widget.frame.CreateFontString) ~= "function" or type(widget.SetWidth) ~= "function" then
        stopIcons(widget); hideFragments(widget); return false
    end
    local visual = widget.currencyVisual
    if not visual then visual = { icons = {}, texts = {} }; widget.currencyVisual = visual end
    local active, regions, widths, width, textIndex = {}, {}, {}, 0, 0
    for index, part in ipairs(parts) do
        local region, partWidth
        if part.icon then
            region = visual.icons[part.icon]
            if not region then
                region = widget.frame:CreateTexture(nil, "ARTWORK")
                visual.icons[part.icon] = region
                region:Hide()
            end
            if region.currencyAsset ~= (part.atlas or part.texture) then
                local method = part.atlas and "SetAtlas" or "SetTexture"
                local getter = part.atlas and "GetAtlas"
                    or (type(region.GetTextureFileID) == "function" and "GetTextureFileID" or "GetTexture")
                if type(region[method]) ~= "function" then stopIcons(widget); hideFragments(widget); return false end
                local ok, result
                if part.atlas then ok, result = pcall(region[method], region, part.atlas, false)
                else ok, result = pcall(region[method], region, part.texture) end
                local applied = ok and readable(result) and result ~= false
                if applied and type(region[getter]) == "function" then
                    local read, actual = pcall(region[getter], region)
                    -- The client canonicalizes atlas names (coin-gold becomes
                    -- Coin-Gold). A valid native texture must not fall back to
                    -- an inline text icon merely because its spelling differs.
                    applied = read and readable(actual) and (part.atlas
                        and type(actual) == "string" and actual:lower() == part.atlas:lower()
                        or not part.atlas and actual == part.texture)
                end
                if not applied then stopIcons(widget); hideFragments(widget); return false end
                region.currencyAsset = part.atlas or part.texture
            end
            local height = math.min(14, widget.content and widget.content:GetHeight() or 14)
            region:SetSize(height, height)
            active[part.icon], partWidth = true, height
        else
            textIndex = textIndex + 1
            region = visual.texts[textIndex]
            if not region then
                region = widget.frame:CreateFontString(nil, "OVERLAY")
                visual.texts[textIndex] = region
                region:Hide()
                region:SetWordWrap(false)
            end
            if not sameStyle(region.currencyStyle, style) then
                if region:SetFont(style[1], style[2], style[3]) ~= true then error("Currency font is unavailable", 0) end
                region:SetTextColor(style[4], style[6], style[8], style[10])
                region:SetShadowColor(style[5], style[7], style[9], style[11])
                region:SetShadowOffset(style[12], style[13])
                region.currencyStyle = style
            end
            region:SetText(part.text)
            partWidth = region:GetStringWidth()
            if not finite(partWidth, 0) then error("Currency text width is unavailable", 0) end
        end
        regions[index], widths[index], width = region, partWidth, width + partWidth
    end
    widget:SetWidth(math.max(18, width + 8))
    local x = (widget.width - width) / 2
    for index, region in ipairs(regions) do
        region:ClearAllPoints()
        region:SetPoint("LEFT", (widget.content or widget.frame), "LEFT", x, 0)
        region:Show()
        x = x + widths[index]
    end
    for key, icon in pairs(visual.icons) do if not active[key] then icon:Hide() end end
    for index = textIndex + 1, #visual.texts do visual.texts[index]:Hide() end
    widget.label:Hide()
    return true
end

local function object(value)
    return readable(value) and (type(value) == "table" or type(value) == "userdata")
end

local function query(frame, method, ...)
    if not object(frame) or type(frame[method]) ~= "function" then return nil, false end
    local ok, value = pcall(frame[method], frame, ...)
    if not ok or not readable(value) then return nil, false end
    return value, true
end

local function invoke(frame, method, ...)
    local value, ok = query(frame, method, ...)
    return ok and value ~= false
end

local function height(value)
    return readable(value) and type(value) == "number" and value == value and value >= 0 and value < math.huge
end

-- MoneyFrame is also the grid's anchor. Keep that native frame shown with a
-- positive rectangle; suppress its contents and reclaim the rest of the row.
local bagRequests, bagStates, bagHooks = {}, {}, {}
local bankStates, bankPolicies = {}, {}
local bankMessage
local bagMonitor, bagReady, bagArmed, bagElapsed, bagBusy, bagDeferred, bagMessage, moneyRenderHook
local synchronizeBags
local bagNames = { "ContainerFrame1", "ContainerFrameCombinedBags" }
local bagLayoutMethods = { "UpdateFrameSize", "UpdateItemLayout", "IsShown", "GetHeight", "SetHeight" }
local moneyLayoutMethods = { "GetHeight", "SetHeight", "IsShown" }
local collapsedMoneyHeight = 1
local moneyContentKeys = { "Border", "GoldButton", "SilverButton", "CopperButton", "trialErrorButton", "PrefixText", "SuffixText" }

local function canChange(frame)
    return query(frame, "CanChangeProtectedState") == true
end

local function outOfCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, combat = pcall(InCombatLockdown)
    return ok and readable(combat) and combat == false
end

local function hasBagLayout(bag, money)
    if type(UpdateContainerFrameAnchors) ~= "function" then return false end
    for _, method in ipairs(bagLayoutMethods) do
        if type(bag[method]) ~= "function" then return false end
    end
    for _, method in ipairs(moneyLayoutMethods) do
        if type(money[method]) ~= "function" then return false end
    end
    return true
end

local function collectMoneyContents(money, state)
    -- The first four regions belong to the verified native bag template.
    -- Optional warning/prefix/suffix regions must be suppressed when present.
    for index, key in ipairs(moneyContentKeys) do
        local region = money[key]
        if not object(region) then
            if index <= 4 or region ~= nil then return false end
        else
            if type(region.IsShown) ~= "function" or type(region.Hide) ~= "function"
                or type(region.Show) ~= "function" or not canChange(region) then return false end
            local shown = query(region, "IsShown")
            if type(shown) ~= "boolean" then return false end
            if not state.contents[region] then state.contents[region] = { shown = shown, key = key } end
            if shown then state.contents[region].shown = true end
        end
    end
    return true
end

local function hideMoneyContents(state)
    for region in pairs(state.contents) do
        local shown = query(region, "IsShown")
        if type(shown) ~= "boolean" then return false end
        if shown and not invoke(region, "Hide") then return false end
        if query(region, "IsShown") ~= false then return false end
    end
    return true
end

local function restoreMoneyContents(money, state)
    -- Native money updates choose which denominations/warnings are current.
    -- Saved shown flags are the fallback for an unavailable native renderer.
    if type(MoneyFrame_UpdateMoney) == "function" then
        local ok, result = pcall(MoneyFrame_UpdateMoney, money)
        if not ok or not readable(result) or result == false then return false end
        -- Coin rendering owns neither the bag border nor the trial warning.
        for region, saved in pairs(state.contents) do
            if saved.key == "trialErrorButton" and type(MoneyFrame_UpdateTrialErrorButton) == "function" then
                local warningOK = pcall(MoneyFrame_UpdateTrialErrorButton, money)
                if not warningOK or type(query(region, "IsShown")) ~= "boolean" then return false end
            elseif saved.key == "Border" or saved.key == "trialErrorButton" then
                local method = saved.shown and "Show" or "Hide"
                if not invoke(region, method) or query(region, "IsShown") ~= saved.shown then return false end
            end
        end
    else
        for region, saved in pairs(state.contents) do
            local method = saved.shown and "Show" or "Hide"
            if not invoke(region, method) or query(region, "IsShown") ~= saved.shown then return false end
        end
    end
    return true
end

local function reflowBag(state)
    local shown = query(state.bag, "IsShown")
    if shown == false then state.dirty = false; return true end
    if shown ~= true then return false end
    if not invoke(state.bag, "UpdateFrameSize") then return false end
    local moneyHeight = query(state.money, "GetHeight")
    if not height(moneyHeight) or moneyHeight <= 0 then return false end
    if type(state.money.IsRectValid) == "function" and query(state.money, "IsRectValid") ~= true then return false end
    if not invoke(state.bag, "UpdateItemLayout") then return false end
    if type(UpdateContainerFrameAnchors) ~= "function" then return false end
    local ok, result = pcall(UpdateContainerFrameAnchors)
    if not ok or not readable(result) or result == false then return false end
    state.dirty = false
    return true
end

local function collapseBag(money, state)
    local current, shown = query(money, "GetHeight", true), query(money, "IsShown")
    if not height(current) or type(shown) ~= "boolean" then return false end
    if current ~= collapsedMoneyHeight and current > 0 and not state.contentSized then state.height, state.dirty = current, true end
    if not collectMoneyContents(money, state) then return false end
    if not hideMoneyContents(state) then return false end
    if current ~= collapsedMoneyHeight then
        state.dirty = true
        if not invoke(money, "SetHeight", collapsedMoneyHeight) then return false end
    end
    if query(money, "GetHeight", true) ~= collapsedMoneyHeight then return false end
    return not state.dirty or reflowBag(state)
end

local function restoreBag(money, state)
    local current, shown = query(money, "GetHeight", true), query(money, "IsShown")
    if not height(current) or type(shown) ~= "boolean" then return false end
    local bagHeight = query(state.bag, "GetHeight")
    if not height(bagHeight) then return false end
    -- A new public native height is the latest layout, not our small anchor.
    if current ~= collapsedMoneyHeight and current > 0 and not state.contentSized then state.height = current end
    if not collectMoneyContents(money, state) then return false end
    local function rollback()
        hideMoneyContents(state)
        invoke(money, "SetHeight", collapsedMoneyHeight)
        if not reflowBag(state) then invoke(state.bag, "SetHeight", bagHeight) end
        state.dirty = true
        return false
    end
    -- Grow/reflow while the individual coin controls are still hidden.
    if not hideMoneyContents(state) then return false end
    if current ~= state.height then
        if not invoke(money, "SetHeight", state.height) or query(money, "GetHeight", true) ~= state.height then return rollback() end
    end
    if not reflowBag(state) then return rollback() end
    local preparedHeight = query(money, "GetHeight", true)
    if not height(preparedHeight) or preparedHeight <= 0 then return rollback() end
    if not restoreMoneyContents(money, state) then return rollback() end
    local finalHeight = query(money, "GetHeight", true)
    if not height(finalHeight) or finalHeight <= 0 then return rollback() end
    -- The generic coin renderer sizes its contents; the container owns the row.
    -- Keep the latest container height, including combined bags and custom
    -- layouts, rather than adopting the renderer's small-money-frame height.
    if finalHeight ~= preparedHeight then
        if not invoke(money, "SetHeight", preparedHeight)
            or query(money, "GetHeight", true) ~= preparedHeight
            or not reflowBag(state) then return rollback() end
    end
    state.height = preparedHeight
    bagStates[money] = nil
    return true
end

local function bagChanged(frame)
    if bagBusy or (not next(bagRequests) and not next(bagStates) and not next(bankStates)) then return end
    for money, state in pairs(bagStates) do
        if frame == money or frame == state.bag then state.dirty = true end
    end
    for _, state in pairs(bankStates) do state.dirty = true end
    -- Finish native Show/Size callbacks before recomputing their geometry:
    -- UpdateFrameSize still applies corner cropping after SetSize returns.
    bagDeferred = true
end

local function bagResized(frame, _, newHeight)
    local state = bagStates[frame]
    if state and height(newHeight) then
        -- Width-only layout notifications do not change who sized the row.
        if not bagBusy and newHeight ~= state.observedHeight then state.contentSized = nil end
        state.observedHeight = newHeight
    end
    bagChanged(frame)
end

local function observeMoneyRendering()
    if moneyRenderHook == "failed" then return false end
    if moneyRenderHook == true or type(MoneyFrame_Update) ~= "function" then return true end
    if type(hooksecurefunc) ~= "function" then return false end
    -- Do not repeat an uncertain permanent registration, including a native
    -- failure raised after the callback was already attached.
    moneyRenderHook = "failed"
    local ok, result = pcall(hooksecurefunc, "MoneyFrame_Update", function(frame)
        if bagBusy or not readable(frame) then return end
        if type(frame) == "string" then frame = _G[frame] end
        if not object(frame) then return end
        local state = bagStates[frame]
        if state then
            -- A coin refresh sizes contents, not the container's reserved row.
            -- A later independent resize clears this marker in bagResized.
            state.contentSized = true
            bagChanged(frame)
        end
    end)
    if not ok or not readable(result) or result == false then return false end
    moneyRenderHook = true
    return true
end

local function observeBag(frame, script)
    if not object(frame) or type(frame.HookScript) ~= "function" then return false end
    local scripts = bagHooks[frame]
    if not scripts then scripts = {}; bagHooks[frame] = scripts end
    if not scripts[script] then
        local callback = script == "OnSizeChanged" and bagResized or bagChanged
        scripts[script] = "failed"
        local ok, result = pcall(frame.HookScript, frame, script, callback)
        if ok and readable(result) and result ~= false then scripts[script] = true end
    end
    return scripts[script] == true
end

-- The player-bank footer has its own native visibility policy and is not an
-- item-grid anchor. Never apply the backpack's small-anchor layout to it.
local function bankContract(bank, panel, footer)
    return object(bank) and object(panel) and object(footer)
        and query(panel, "GetParent") == bank and query(footer, "GetParent") == panel
        and type(panel.GetActiveBankType) == "function" and type(panel.GenerateItemSlotsForSelectedTab) == "function"
        and type(footer.SetEnabled) == "function" and type(footer.Refresh) == "function"
        and object(footer.Border) and object(footer.MoneyDisplay)
        and object(footer.WithdrawButton) and object(footer.DepositButton)
end

local function bankPolicy(bank, panel, footer)
    local policy = bankPolicies[footer]
    if not policy then
        local shown = query(footer, "IsShown")
        if type(shown) ~= "boolean" then return nil end
        policy = { shown = shown }; bankPolicies[footer] = policy
    end
    if type(hooksecurefunc) ~= "function" then return nil end
    if policy.enabledHook == "failed" or policy.layoutHook == "failed" then return nil end
    if not policy.enabledHook then
        policy.enabledHook = "failed"
        local ok, result = pcall(hooksecurefunc, footer, "SetEnabled", function(_, enabled)
            if policy.writing then return end
            if readable(enabled) and type(enabled) == "boolean" then policy.shown = enabled
            else policy.shown = nil end
            bagChanged(footer)
        end)
        if not ok or not readable(result) or result == false then return nil end
        policy.enabledHook = true
    end
    if not policy.layoutHook then
        policy.layoutHook = "failed"
        local ok, result = pcall(hooksecurefunc, panel, "GenerateItemSlotsForSelectedTab", bagChanged)
        if not ok or not readable(result) or result == false then return nil end
        policy.layoutHook = true
    end
    for _, frame in ipairs({ bank, panel, footer }) do
        observeBag(frame, "OnShow"); observeBag(frame, "OnHide"); observeBag(frame, "OnSizeChanged")
    end
    return policy
end

local function bankPermission(state)
    return canChange(state.bank) and canChange(state.panel) and canChange(state.footer)
        and type(state.bank.SetHeight) == "function" and type(state.panel.SetHeight) == "function"
end

local function sameBankPoint(first, second)
    if not first or not second then return false end
    for index = 1, 5 do if first[index] ~= second[index] then return false end end
    return true
end

local function bankAnchorLayout(region)
    local count = query(region, "GetNumPoints")
    if not integer(count, 0) then return nil end
    if count ~= 2 then return nil, true end -- A readable foreign layout.
    if type(region.GetPoint) ~= "function" then return nil end
    local parent, parentRead = query(region, "GetParent")
    if not parentRead then return nil end
    if not object(parent) then return nil, true end
    local result = { parent = parent }
    for index = 1, 2 do
        local ok, point, relative, relativePoint, x, y = pcall(region.GetPoint, region, index)
        if not ok or not readable(point) or not object(relative) or not readable(relativePoint)
            or type(point) ~= "string" or type(relativePoint) ~= "string"
            or not readable(x) or not readable(y) or type(x) ~= "number" or type(y) ~= "number"
            or x ~= x or y ~= y or math.abs(x) == math.huge or math.abs(y) == math.huge then return nil end
        local key = point == "TOPLEFT" and "top" or (point == "BOTTOMRIGHT" and "bottom")
        if not key or result[key] then return nil, true end
        result[key] = { point, relative, relativePoint, x, y }
    end
    return result
end

-- GetPoint can canonicalize UI-unit offsets. Keep native write provenance
-- separate from requested coordinates; no arithmetic tolerance proves ownership.
local bankPointObservers = {}
local bankPointMutators = { "AdjustPointsOffset", "ClearPoint", "ClearAllPoints", "ClearPointsOffset",
    "SetAllPoints", "SetPoint", "SetPointsOffset", "SetParent" }

local function sameBankPointIdentity(first, second)
    return first and second and first[1] == second[1] and first[2] == second[2] and first[3] == second[3]
end

local function observeBankPoints(region)
    if type(hooksecurefunc) ~= "function" then return nil end
    if type(region.SetPoint) ~= "function" then return nil end
    local observer = bankPointObservers[region]
    if not observer then
        observer = { hooks = {} }; bankPointObservers[region] = observer
    end
    if observer.failed or observer.entry then return nil end
    for _, method in ipairs(bankPointMutators) do
        if type(region[method]) == "function" and not observer.hooks[method] then
            local operation = method
            local ok, result = pcall(hooksecurefunc, region, method, function(self, point, relative, relativePoint, x, y)
                local probe = observer.probe
                if not probe then
                    if observer.entry then observer.entry.foreign = true end
                    return
                end
                probe.calls = probe.calls + 1
                if operation ~= "SetPoint" or not object(self) or self ~= region or not readable(point) or not object(relative)
                    or not readable(relativePoint) or not readable(x) or not readable(y)
                    or not sameBankPoint({ point, relative, relativePoint, x, y }, probe.point) then
                    probe.foreign = true
                else probe.expected = true end
            end)
            -- A failed registration may already have attached its permanent hook.
            -- Decline this region rather than retrying and duplicating callbacks.
            if not ok or not readable(result) or result == false then observer.failed = true; return nil end
            observer.hooks[method] = true
        end
    end
    return observer
end

local function releaseBankFraming(state)
    for _, entry in ipairs(state.framing or {}) do
        if entry.observer.entry == entry then entry.observer.entry = nil end
    end
end

local function ownBankReadback(entry, current)
    if entry.foreign then return false end
    if current.parent ~= entry.parent or not sameBankPointIdentity(current.top, entry.top)
        or not sameBankPointIdentity(current.bottom, entry.original) then return false end
    if not sameBankPoint(current.top, entry.top) then
        if entry.pending then return nil end -- Our unresolved write is not proof of a foreign writer.
        return false
    end
    local pending = entry.pending
    if pending then
        local requested
        if sameBankPoint(current.bottom, pending.point) then requested = pending.point
        elseif sameBankPoint(current.bottom, pending.before) then requested = pending.beforeRequested
        elseif pending.witnessed then requested = pending.point
        else return nil end
        entry.applied, entry.requested, entry.pending = current.bottom, requested, nil
        return true
    end
    return sameBankPoint(current.bottom, entry.applied)
end

local function writeBankPoint(entry, point, before)
    local observer = entry.observer
    if entry.foreign or observer.entry ~= entry or observer.probe or not canChange(entry.region)
        or type(entry.region.SetPoint) ~= "function" then return false end
    -- Retain both possible owned results before a native write/read can fail.
    entry.pending = { before = before, beforeRequested = entry.requested, point = point }
    local probe = { point = point, calls = 0 }
    observer.probe = probe
    local accepted = invoke(entry.region, "SetPoint", unpack(point))
    observer.probe = nil
    if probe.calls == 1 and probe.expected and not probe.foreign then entry.pending.witnessed = true
    elseif probe.calls > 0 then entry.foreign = true end
    local current = bankAnchorLayout(entry.region)
    local owned = current and ownBankReadback(entry, current)
    if owned == false then entry.foreign = true end
    return accepted and owned == true and sameBankPoint(entry.requested, point)
end

local function restoreBankFraming(state)
    local complete = true
    for _, entry in ipairs(state.framing or {}) do
        if not entry.foreign then
            local current, foreign = bankAnchorLayout(entry.region)
            local owned = current and ownBankReadback(entry, current)
            if foreign or owned == false then entry.foreign = true
            elseif owned ~= true then complete = false
            elseif not sameBankPoint(entry.requested, entry.original)
                and not writeBankPoint(entry, entry.original, current.bottom) then complete = false end
        end
    end
    return complete
end

local function captureBankFraming(state)
    local regions = { state.panel.NineSlice, state.bank.Background }
    local parents = { state.panel, state.bank }
    local footerHeight, footerScale = query(state.footer, "GetHeight"), query(state.footer, "GetEffectiveScale")
    if not finite(footerHeight, 0) or footerHeight == 0 or not finite(footerScale, 0) or footerScale == 0 then return nil end
    local entries = {}
    for index = 1, 2 do
        local region, parent = regions[index], parents[index]
        if not object(region) then return nil end
        local observer = observeBankPoints(region)
        if not observer then return nil end
        local current = bankAnchorLayout(region)
        local scale, parentScale = query(region, "GetEffectiveScale"), query(parent, "GetEffectiveScale")
        if not current or current.parent ~= parent or current.top[2] ~= parent or current.bottom[2] ~= parent
            or current.top[3] ~= "TOPLEFT" or current.bottom[3] ~= "BOTTOMRIGHT"
            or not finite(scale, 0) or scale == 0 or scale ~= parentScale or scale ~= footerScale
            or type(region.SetPoint) ~= "function" then return nil end
        -- Rounded upward keeps the new inset inside the verified reserved row.
        -- Use small binary steps; accepted native readback is tracked separately.
        local targetY = math.ceil((current.bottom[5] - footerHeight) * 16) / 16
        if not finite(targetY, 0) or targetY >= current.bottom[5] then return nil end
        entries[index] = { region = region, parent = parent, top = current.top, original = current.bottom,
            observer = observer, applied = current.bottom, requested = current.bottom,
            target = { "BOTTOMRIGHT", parent, "BOTTOMRIGHT", current.bottom[4], targetY } }
    end
    for _, entry in ipairs(entries) do entry.observer.entry = entry end
    return entries
end

local function applyBankFraming(state)
    if state.framing and (state.framing[1].region ~= state.panel.NineSlice or state.framing[2].region ~= state.bank.Background) then
        if not restoreBankFraming(state) then return false end
        releaseBankFraming(state)
        state.framing = nil
    end
    if not state.framing then
        state.framing = captureBankFraming(state)
        if not state.framing then return false end
    end
    local pending = {}
    for _, entry in ipairs(state.framing) do
        if not entry.foreign then
            local current, foreign = bankAnchorLayout(entry.region)
            local owned = current and ownBankReadback(entry, current)
            if foreign or owned == false then entry.foreign = true
            elseif owned ~= true then return false
            else
                local scale, parentScale = query(entry.region, "GetEffectiveScale"), query(entry.parent, "GetEffectiveScale")
                if not finite(scale, 0) or scale == 0 or scale ~= parentScale then return false end
                if not sameBankPoint(entry.requested, entry.target) then
                    if not canChange(entry.region) then return false end
                    pending[#pending + 1] = { entry, current.bottom }
                end
            end
        end
    end
    for _, change in ipairs(pending) do
        if not writeBankPoint(change[1], change[1].target, change[2]) then
            restoreBankFraming(state)
            return false
        end
    end
    return true
end

local function visitBankPool(owner, method, callback)
    if not object(owner) or type(owner[method]) ~= "function" then return false end
    local ok, iterator, context, control = pcall(owner[method], owner)
    if not ok or not readable(iterator) or type(iterator) ~= "function"
        or not readable(context) or not readable(control) then return false end
    for _ = 1, 512 do
        local read, first, second = pcall(iterator, context, control)
        if not read or not readable(first) then return false end
        if first == nil then return true end
        control = first
        local frame = object(first) and first or second
        if not object(frame) or not callback(frame) then return false end
    end
    return false
end

local function bankRect(frame)
    if not object(frame) then return nil end
    local shown = query(frame, "IsVisible")
    if shown == false then return false end
    if shown ~= true or query(frame, "IsRectValid") ~= true or type(frame.GetRect) ~= "function" then return nil end
    local ok, left, bottom, width, tall = pcall(frame.GetRect, frame)
    local scale = query(frame, "GetEffectiveScale")
    if not ok or not readable(left) or not readable(bottom) or type(left) ~= "number" or type(bottom) ~= "number"
        or left ~= left or bottom ~= bottom or math.abs(left) == math.huge or math.abs(bottom) == math.huge
        or not finite(width, 0) or width == 0 or not finite(tall, 0) or tall == 0
        or not finite(scale, 0) or scale == 0 then return nil end
    local low, high = bottom * scale, (bottom + tall) * scale
    if not finite(high - low, 0) or high - low == 0 or math.abs(low) == math.huge or math.abs(high) == math.huge then return nil end
    return { bottom = low, top = high }
end

local function readBankRegions(bank)
    return { bank:GetRegions() }
end

local function bankDividerRect(bank)
    local count = query(bank, "GetNumRegions")
    if not finite(count, 1) or count % 1 ~= 0 or count > 128 or type(bank.GetRegions) ~= "function" then return nil end
    local ok, regions = pcall(readBankRegions, bank)
    if not ok or #regions ~= count then return nil end
    local divider
    for index = 1, count do
        local region = regions[index]
        if not object(region) or query(region, "GetParent") ~= bank then return nil end
        if type(region.IsForbidden) == "function" and query(region, "IsForbidden") ~= false then return nil end
        local kind = query(region, "GetObjectType")
        if not readable(kind) or type(kind) ~= "string" then return nil end
        if type(region.GetAtlas) == "function" then
            local atlas, known = query(region, "GetAtlas")
            if not known then return nil end
            if atlas == "bank-divider" then
                if divider then return nil end
                divider = region
            end
        elseif kind ~= "FontString" and kind ~= "Line" then return nil end
    end
    -- The retained decoration is a footer obstacle even when the balance is hidden.
    -- Unknown or hidden divider geometry cannot establish safe space to reclaim.
    return divider and bankRect(divider) or nil
end

local function bankReclaim(state)
    local scale, panelScale = query(state.bank, "GetEffectiveScale"), query(state.panel, "GetEffectiveScale")
    local footerScale, footerHeight = query(state.footer, "GetEffectiveScale"), query(state.footer, "GetHeight")
    if not finite(scale, 0) or scale == 0 or panelScale ~= scale
        or not finite(footerScale, 0) or footerScale == 0 or not finite(footerHeight, 0) or footerHeight == 0 then return 0, false end
    local gridBottom, toolbarTop
    local function grid(frame)
        local rect = bankRect(frame)
        if rect == nil then return false end
        if rect then gridBottom = math.min(gridBottom or rect.bottom, rect.bottom) end
        return true
    end
    local function toolbar(frame)
        observeBag(frame, "OnShow"); observeBag(frame, "OnHide"); observeBag(frame, "OnSizeChanged")
        local rect = bankRect(frame)
        if rect == nil then return false end
        if rect then toolbarTop = math.max(toolbarTop or rect.top, rect.top) end
        return true
    end
    if not visitBankPool(state.panel, "EnumerateValidItems", grid) then return 0, false end
    for _, frame in ipairs({ state.bank.BagText, state.bank.BagCost, state.panel.MoneyDisplay, state.panel.PurchaseButton }) do
        if not toolbar(frame) then return 0, false end
    end
    -- Missing named controls or pools cannot establish a safe free interval.
    if not object(state.bank.BagText) or not object(state.bank.BagCost)
        or not object(state.panel.MoneyDisplay) or not object(state.panel.PurchaseButton)
        or not visitBankPool(state.bank.itemButtonBagPool, "EnumerateActive", toolbar)
        or not gridBottom or not toolbarTop then return 0, false end
    local divider = bankDividerRect(state.bank)
    if not divider then return 0, false end
    toolbarTop = math.max(toolbarTop, divider.top)
    local gap = (gridBottom - toolbarTop) / scale + (state.delta or 0) - 4
    local limit = footerHeight * footerScale / scale
    if gap ~= gap or gap <= -math.huge or gap >= math.huge or not finite(limit, 0) then return 0, false end
    local delta = math.max(0, math.min(gap, limit))
    -- Keep the result inside the proven gap on a small exact binary unit.
    -- Native height storage can have less precision than Lua's arithmetic.
    local wholeDelta = math.floor(delta)
    return wholeDelta + math.floor((delta - wholeDelta) * 16) / 16, true
end

local function ownsBankHeight(state, key, value)
    local candidates = state[key .. "Candidates"]
    return value == state[key == "bank" and "appliedBank" or "appliedPanel"]
        or (candidates and candidates[value] == true)
end

local function captureBankHeights(state)
    local bankHeight, panelHeight = query(state.bank, "GetHeight", true), query(state.panel, "GetHeight", true)
    if not height(bankHeight) or bankHeight <= 0 or not height(panelHeight) or panelHeight <= 0 then return false end
    if state.bankCandidates or state.panelCandidates then
        if ownsBankHeight(state, "bank", bankHeight) and ownsBankHeight(state, "panel", panelHeight) then
            state.appliedBank, state.appliedPanel, state.delta = bankHeight, panelHeight, nil
            state.dirty = true
            return true
        end
    end
    if bankHeight ~= state.appliedBank or panelHeight ~= state.appliedPanel then
        -- Native generation sizes both frames. Wait through an incomplete pair.
        if bankHeight ~= panelHeight then return false end
        state.bankHeight, state.panelHeight, state.delta = bankHeight, panelHeight, 0
        state.appliedBank, state.appliedPanel = bankHeight, panelHeight
        state.bankCandidates, state.panelCandidates = nil, nil
        state.dirty = true
    end
    return true
end

local function sizeBank(state, delta)
    local targetBank, targetPanel = state.bankHeight - delta, state.panelHeight - delta
    if not height(targetBank) or targetBank <= 0 or not height(targetPanel) or targetPanel <= 0 then return false end
    local beforeBank, beforePanel = query(state.bank, "GetHeight", true), query(state.panel, "GetHeight", true)
    if not height(beforeBank) or beforeBank <= 0 or not height(beforePanel) or beforePanel <= 0 then return false end
    local ok = (beforeBank == targetBank or invoke(state.bank, "SetHeight", targetBank))
        and query(state.bank, "GetHeight", true) == targetBank
        and (beforePanel == targetPanel or invoke(state.panel, "SetHeight", targetPanel))
        and query(state.panel, "GetHeight", true) == targetPanel
    if ok then
        -- These targets were just read back successfully. An additional
        -- transient read must not erase the dimensions we still own.
        state.appliedBank, state.appliedPanel, state.delta = targetBank, targetPanel, delta
        state.bankCandidates, state.panelCandidates = nil, nil
        return true
    end
    local rollbackBank = invoke(state.bank, "SetHeight", beforeBank)
        and query(state.bank, "GetHeight", true) == beforeBank
    local rollbackPanel = invoke(state.panel, "SetHeight", beforePanel)
        and query(state.panel, "GetHeight", true) == beforePanel
    state.appliedBank, state.appliedPanel = beforeBank, beforePanel
    if rollbackBank and rollbackPanel then
        state.bankCandidates, state.panelCandidates = nil, nil
    else
        state.bankCandidates = { [beforeBank] = true, [targetBank] = true }
        state.panelCandidates = { [beforePanel] = true, [targetPanel] = true }
        state.delta = nil
    end
    return false
end

local function setBankFooter(state, shown)
    local current = query(state.footer, "IsShown")
    if type(current) ~= "boolean" then return false end
    if current == shown then return true end
    state.policy.writing = true
    local result, ok = query(state.footer, "SetEnabled", shown)
    state.policy.writing = nil
    return ok and result ~= false and query(state.footer, "IsShown") == shown
end

local function restoreBank(state)
    if type(state.policy.shown) ~= "boolean" or not bankPermission(state) then return false end
    local bankHeight, panelHeight = query(state.bank, "GetHeight", true), query(state.panel, "GetHeight", true)
    if not height(bankHeight) or bankHeight <= 0 or not height(panelHeight) or panelHeight <= 0 then return false end
    -- Relinquishing ownership must not wait for a native generation pair.
    -- Preserve each later external size and restore only our remaining sizes.
    if not ownsBankHeight(state, "bank", bankHeight) then state.bankHeight = bankHeight end
    if not ownsBankHeight(state, "panel", panelHeight) then state.panelHeight = panelHeight end
    if not sizeBank(state, 0) then return false end
    if not restoreBankFraming(state) then return false end
    if not setBankFooter(state, state.policy.shown) then return false end
    releaseBankFraming(state)
    bankStates[state.footer] = nil
    return true
end

local function failedBankObservation(bank, panel, footer)
    local policy = object(footer) and bankPolicies[footer]
    if policy and (policy.enabledHook == "failed" or policy.layoutHook == "failed") then return true end
    local inset = object(panel) and panel.NineSlice
    local background = object(bank) and bank.Background
    local insetObserver = object(inset) and bankPointObservers[inset]
    local backgroundObserver = object(background) and bankPointObservers[background]
    return (insetObserver and insetObserver.failed) or (backgroundObserver and backgroundObserver.failed) or false
end

local function reconcileBank()
    if not next(bagRequests) and not next(bankStates) then bankMessage = nil; return end
    if not outOfCombat() then bankMessage = "Player bank money changes are waiting until permitted."; return end
    local bank = _G.BankFrame
    local panel = object(bank) and bank.BankPanel
    local footer = object(panel) and panel.MoneyFrame
    local desired, complete
    complete = true
    if next(bagRequests) and bankContract(bank, panel, footer)
        and ((query(bank, "IsShown") == true and query(panel, "IsShown") == true) or bankStates[footer]) then
        local policy = bankPolicy(bank, panel, footer)
        local character = object(Enum) and object(Enum.BankType) and Enum.BankType.Character
        local kind = query(panel, "GetActiveBankType")
        if policy and integer(character, 0) and readable(kind) and kind == character
            and query(bank, "IsShown") == true and query(panel, "IsShown") == true and policy.shown == true then
            desired = footer
            local state = bankStates[footer]
            if not state then
                state = { bank = bank, panel = panel, footer = footer, policy = policy, dirty = true }
                if bankPermission(state) and captureBankHeights(state) then bankStates[footer] = state
                else complete = false end
            end
        elseif not policy or not readable(kind) or kind == nil then complete = false end
    end
    for money, state in pairs(bankStates) do
        if not bankPermission(state) then complete = false
        elseif money ~= desired then
            if not restoreBank(state) then complete = false end
        elseif not captureBankHeights(state) or not setBankFooter(state, false) then complete = false
        else
            if not applyBankFraming(state) then complete = false end
            if state.delta == nil and not sizeBank(state, 0) then complete = false
            elseif state.dirty or (state.retryIn and state.retryIn <= 0) then
                local delta, verified = bankReclaim(state)
                if sizeBank(state, delta) then
                    state.dirty, state.retryIn = false, not verified and 1 or nil
                else complete = false end
            end
        end
    end
    bankMessage = not complete and next(bagRequests) and failedBankObservation(bank, panel, footer)
        and "Player bank money hiding could not be enabled safely. Reload the UI to try again."
        or not complete and "Player bank money layout could not be fully updated; it will retry." or nil
end

local function reconcileBags()
    if not outOfCombat() then bagMessage = "Backpack money layout changes are waiting until permitted."; return end
    local desired, found, complete = {}, false, true
    if next(bagRequests) then
        for _, name in ipairs(bagNames) do
            local bag = _G[name]
            local money = object(bag) and bag.MoneyFrame
            if object(money) then
                found, desired[money] = true, bag
                if hasBagLayout(bag, money) and canChange(bag) and canChange(money) and observeMoneyRendering() then
                    observeBag(bag, "OnShow"); observeBag(bag, "OnSizeChanged")
                    observeBag(money, "OnShow")
                    if not observeBag(money, "OnSizeChanged") then complete = false
                    elseif not bagStates[money] then
                        local visible = query(bag, "IsShown")
                        if visible == true then
                            local current, shown = query(money, "GetHeight", true), query(money, "IsShown")
                            if height(current) and type(shown) == "boolean" then
                                if current > 0 then
                                    local state = { bag = bag, money = money, height = current, observedHeight = current, contents = {}, dirty = true }
                                    if collectMoneyContents(money, state) then bagStates[money] = state else complete = false end
                                else complete = false end
                            else complete = false end
                        elseif visible ~= false then complete = false end
                    end
                else complete = false end
            end
        end
    end
    for money, state in pairs(bagStates) do
        if not hasBagLayout(state.bag, money) or not canChange(money) or not canChange(state.bag) then complete = false
        elseif desired[money] == state.bag then
            if not collapseBag(money, state) then complete = false end
        elseif not restoreBag(money, state) then complete = false end
        for region in pairs(state.contents) do observeBag(region, "OnShow") end
    end
    local observerFailed = next(desired) and moneyRenderHook == "failed" or false
    for money in pairs(desired) do
        local scripts = bagHooks[money]
        if scripts and scripts.OnSizeChanged == "failed" then observerFailed = true end
    end
    bagMessage = not complete and observerFailed
        and "Backpack money hiding could not be enabled safely. Reload the UI to try again."
        or not complete and "Backpack money layout could not be fully updated; it will retry."
        or (next(bagRequests) and not found and "Blizzard's backpack money area is not available yet.") or nil
end

local function armBagMonitor()
    if not bagMonitor then
        if type(CreateFrame) ~= "function" then return end
        bagMonitor = CreateFrame("Frame")
    end
    if not bagReady then
        bagMonitor:SetScript("OnEvent", bagChanged)
        bagMonitor:SetScript("OnUpdate", function(_, elapsed)
            if not readable(elapsed) or type(elapsed) ~= "number" or elapsed ~= elapsed or elapsed < 0 or elapsed == math.huge then return end
            bagElapsed = (bagElapsed or 0) + elapsed
            if bagDeferred or bagElapsed >= 0.25 then
                for _, state in pairs(bankStates) do
                    if state.retryIn then state.retryIn = math.max(0, state.retryIn - bagElapsed) end
                end
                bagDeferred, bagElapsed = false, 0
                synchronizeBags()
            end
        end)
        bagReady = true
    end
    if not bagArmed then
        for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
            pcall(bagMonitor.RegisterEvent, bagMonitor, event)
        end
        bagArmed, bagElapsed = true, 0
        bagMonitor:Show()
    end
end

synchronizeBags = function()
    if bagBusy then return end
    bagBusy = true
    local ok, reason = pcall(reconcileBags)
    local bankOK, bankReason = pcall(reconcileBank)
    bagBusy = false
    if not ok then
        local textOK, text = false, nil
        if readable(reason) then textOK, text = pcall(tostring, reason) end
        bagMessage = "Backpack money control failed: " .. (textOK and text or "details unavailable") .. ". It will retry."
    end
    if not bankOK then
        local textOK, text = false, nil
        if readable(bankReason) then textOK, text = pcall(tostring, bankReason) end
        bankMessage = "Player bank money control failed: " .. (textOK and text or "details unavailable") .. ". It will retry."
    end
    if next(bagRequests) or next(bagStates) or next(bankStates) then armBagMonitor()
    elseif bagMonitor and bagArmed then
        bagMonitor:UnregisterAllEvents(); bagMonitor:Hide()
        bagArmed, bagDeferred, bagElapsed = false, false, 0
    end
end

local function releaseBagMoney(widget)
    if not bagRequests[widget] then return end
    bagRequests[widget] = nil
    synchronizeBags()
end

local function reset(widget)
    widget.customWidth, widget.currencyWatch, widget.currencySample = nil, nil, nil
    releaseBagMoney(widget)
    stopIcons(widget)
    hideFragments(widget)
end

local function create(widget)
    -- Hidden balances become the next silent baseline, rather than a backlog
    -- of notifications when this instance returns from overflow or a rebuild.
    if not widget.currencyHideHooked then
        widget.frame:HookScript("OnHide", function() widget.currencyWatch = nil end)
        widget.currencyHideHooked = true
    end
end

local function notifyChange(widget, before, after)
    if not after.presented then return end
    local icons = widget.currencyVisual.icons
    local changed = widget.currencyChanges
    if not changed then changed = {}; widget.currencyChanges = changed end
    for index = #changed, 1, -1 do changed[index] = nil end
    if after.id ~= 0 then
        changed[1] = icons.token
    elseif after.display ~= "coins" then
        changed[1] = icons[after.display]
    else
        local oldGold, oldSilver, oldCopper = splitMoney(before.value)
        local gold, silver, copper = splitMoney(after.value)
        -- Match the visible order from right to left, omitting unchanged units.
        if oldCopper ~= copper then changed[#changed + 1] = icons.copper end
        if oldSilver ~= silver then changed[#changed + 1] = icons.silver end
        if oldGold ~= gold then changed[#changed + 1] = icons.gold end
    end
    if type(widget.JiggleIcons) == "function" then widget:JiggleIcons(changed)
    elseif type(widget.JiggleIcon) == "function" then
        -- Older cores can still provide their existing independent animation.
        for _, icon in ipairs(changed) do widget:JiggleIcon(icon) end
    end
end

local function render(widget)
    local id = selectedCurrency(widget.settings)
    local display = widget.settings.display
    if not readable(display) or type(display) ~= "string"
        or (display ~= "gold" and display ~= "silver" and display ~= "copper") then display = "coins" end
    local showLabel = readable(widget.settings.showLabel) and not not widget.settings.showLabel
    local text, parts, value, icon
    if id == 0 then
        value = readMoney()
        text = formatMoney(value, display)
        if showLabel then text = "Money " .. text end
        parts = partsForMoney(value, display, showLabel)
    else
        local state = id and currencyState(id)
        text = tokenText(state, showLabel)
        parts = partsForToken(state, showLabel)
        if state then value, icon = state.quantity, state.icon end
    end
    widget:SetText(text)
    local style = fontStyle(widget)
    local sample = { id = id, display = display, showLabel = showLabel,
        hideBagMoney = widget.settings.hideBagMoney == true, icon = icon, value = value, style = style }
    sample.presented = renderFragments(widget, parts, style)
    if not sample.presented and widget.customWidth ~= nil then
        widget.customWidth = nil
        widget:SetText(text)
    end
    local baseline = widget.currencyWatch
    if not samePresentation(baseline, sample) or value == nil or baseline.value == nil then
        stopIcons(widget)
    elseif baseline.value ~= value then
        notifyChange(widget, baseline, sample)
    end
    -- Events cause an immediate read; a later polling read can also finish a
    -- change. Neither path infers amounts from shop, loot or mail UI messages.
    widget.currencyWatch, widget.currencySample = sample, sample
    if widget.settings.hideBagMoney == true then bagRequests[widget] = true else bagRequests[widget] = nil end
    if next(bagRequests) or next(bagStates) or next(bankStates) or bagArmed then synchronizeBags() end
end

local function update(widget)
    local ok, reason = pcall(render, widget)
    if not ok then
        pcall(reset, widget)
        pcall(releaseBagMoney, widget)
        error(reason, 0)
    end
end

local function event(widget, name)
    if name == "PLAYER_ENTERING_WORLD" then
        widget.currencyWatch = widget.currencySample
        stopIcons(widget)
    end
end

local function tooltip(widget, tip)
    tip:AddLine("Currency")
    tip:AddLine("For repairs, rides, and rainy days.", 1, 1, 1)
    if bagMessage then tip:AddLine(bagMessage, 0.65, 0.65, 0.65, true) end
    if bankMessage then tip:AddLine(bankMessage, 0.65, 0.65, 0.65, true) end
    if widget.currencyMessage then tip:AddLine(widget.currencyMessage, 0.65, 0.65, 0.65, true) end
    local id = selectedCurrency(widget.settings)
    if id ~= 0 then
        local state = id and currencyState(id)
        if not state then
            tip:AddLine("Selected currency is currently unavailable.", 0.65, 0.65, 0.65, true)
            return
        end
        tip:AddDoubleLine("Watching", state.name or "Unavailable")
        tip:AddDoubleLine("Amount", state.quantity ~= nil and tokenAmount(state.quantity) or "Unavailable")
        if state.maximum then tip:AddDoubleLine("Maximum", tokenAmount(state.maximum)) end
        return
    end
    local amount = readMoney()
    if amount == nil then
        tip:AddLine("Money is currently unavailable.", 0.65, 0.65, 0.65, true)
        return
    end
    local gold, silver, copper = splitMoney(amount)
    tip:AddDoubleLine("Gold", whole(gold))
    tip:AddDoubleLine("Silver", whole(silver))
    tip:AddDoubleLine("Copper", whole(copper))
end

Menubar:RegisterWidgetType({
    id = "currency",
    retainOnDisable = true,
    name = "Currency",
    clickHint = "Choose currency",
    defaults = {
        currencyID = 0,
        display = "coins",
        showLabel = false,
        hideBagMoney = false,
    },
    legacyDefaults = { hideBagMoney = false },
    settings = {
        { key = "currencyID", label = "Currency", type = "select", options = currencyOptions },
        {
            key = "display",
            label = "Money display",
            type = "select",
            options = {
                { value = "coins", label = "Gold, silver and copper" },
                { value = "gold", label = "Total gold (exact)" },
                { value = "silver", label = "Total silver (exact)" },
                { value = "copper", label = "Total copper" },
            },
        },
        { key = "showLabel", label = "Show currency name", type = "toggle" },
        { key = "hideBagMoney", label = "Hide backpack and player bank money", type = "toggle" },
    },
    interval = 5,
    events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD", "CURRENCY_DISPLAY_UPDATE" },
    defaultPlacement = { bar = "top", alignment = "right", order = 7, sidebarOrder = 10 },
    create = create,
    update = update,
    event = event,
    click = click,
    tooltip = tooltip,
    reset = reset,
    deactivate = reset,
    destroy = reset,
})
