local sourceDirectory = dofile((REPO_ROOT or ".") .. "/tests/source_paths.lua")
-- Original real-host tests for owned currency fragments and event-consumed changes.
local root = REPO_ROOT or "."
local core = assert(MENUBAR_CORE_ROOT, "Currency jiggle tests require Menubar core")
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
    for line in io.lines(sourceDirectory(repository, addon) .. "/" .. addon .. ".toc") do
        local file = line:match("^%s*(.-)%s*$")
        if file:match("%.lua$") then assert(loadfile(sourceDirectory(repository, addon) .. "/" .. file))(addon, {}) end
    end
end
local function fixture(money, options)
    options = options or {}
    local Stub = dofile(core .. "/tests/wow_stub.lua"); Stub.Install()
    local createNativeFrame = CreateFrame
    CreateFrame = function(...)
        local frame = createNativeFrame(...)
        function frame:UnregisterAllEvents() self.events = {} end
        return frame
    end
    local f = { Stub = Stub, money = money or 123456, tokens = {}, rows = {}, shift = false }
    if options.canonicalAtlases or options.resolvedTokenPaths or options.legacyTextureReadback then
        local createFrame = CreateFrame
        CreateFrame = function(...)
            local frame = createFrame(...); local createTexture = frame.CreateTexture
            function frame:CreateTexture(...)
                local texture = createTexture(self, ...)
                if options.canonicalAtlases then
                    local getAtlas = texture.GetAtlas
                    function texture:GetAtlas()
                        local value = getAtlas(self)
                        if type(value) == "string" and value:match("^coin%-") then
                            return (value:gsub("(%a)([%w]*)", function(first, rest) return first:upper() .. rest end))
                        end
                        return value
                    end
                end
                if options.resolvedTokenPaths then
                    assert(type(texture.GetTextureFileID) == "function", "The native FileID getter contract is required")
                    local getTexture = texture.GetTexture
                    function texture:GetTexture()
                        local value = getTexture(self)
                        return type(value) == "number" and "Interface\\Icons\\ResolvedToken" or value
                    end
                end
                if options.legacyTextureReadback then texture.GetTextureFileID = false end
                return texture
            end
            return frame
        end
    end
    f.secret = setmetatable({}, { __tostring = function() error("Restricted currency formatted", 0) end })
    issecretvalue = function(value) return rawequal(value, f.secret) end
    IsShiftKeyDown = function() return f.shift end
    MenubarDB = nil
    GetMoney = function() if f.moneyError then error("Money unavailable", 0) end; return f.money end
    C_CurrencyInfo = {
        GetCurrencyListSize = function() return #f.rows end,
        GetCurrencyListInfo = function(index) return f.rows[index] end,
        GetCurrencyInfo = function(id) if f.tokenError then error("Token unavailable", 0) end; return f.tokens[id] end,
    }
    for _, name in ipairs({ "ExpandCurrencyList", "SetCurrencyBackpack", "SetCurrencyFilter", "SetCurrencyUnused" }) do
        C_CurrencyInfo[name] = function() error("Currency selection must not mutate native state", 0) end
    end
    loadAddon(core, "Menubar")
    Menubar:RegisterWidgetType({ id = "time", name = "Clock fixture", defaults = {},
        defaultPlacement = { bar = "top", alignment = "right" }, update = function(widget) widget:SetText("12:34") end })
    loadAddon(root, "Menubar_Currency"); Menubar:Start(); f.host = Menubar
    for _, widget in pairs(f.host.runtime) do
        if widget.instance.type == "currency" then f.widget = widget end
        if widget.instance.type == "time" then f.clock = widget end
    end
    assert(f.widget and not f.widget.failed, tostring(f.widget and f.widget.failed))
    function f:refresh(widget)
        self.host:RefreshWidget((widget or self.widget).id)
        assert(not (widget or self.widget).failed, tostring((widget or self.widget).failed))
    end
    function f:emit(event, ...)
        self.host.eventFrame.scripts.OnEvent(self.host.eventFrame, event, ...)
        for _, widget in pairs(self.host.runtime) do assert(not widget.failed, tostring(widget.failed)) end
    end
    function f:poll()
        self.host.eventFrame.scripts.OnUpdate(self.host.eventFrame, 5.1)
        for _, widget in pairs(self.host.runtime) do assert(not widget.failed, tostring(widget.failed)) end
    end
    function f:motion(key, widget)
        widget = widget or self.widget
        for _, motion in ipairs(widget.iconJiggles or {}) do
            if motion.icon == widget.currencyVisual.icons[key] then return motion.group end
        end
    end
    function f:plays(key, widget)
        local group = self:motion(key, widget); return group and group.plays or 0
    end
    function f:playing(key, widget)
        local group = self:motion(key, widget); return group and group:IsPlaying() or false
    end
    function f:finish(widget)
        widget = widget or self.widget
        for _ = 1, 12 do
            local progressed = false
            -- Force completion only for this owner's native groups. Timeline
            -- assertions below instead advance the common animation clock.
            for _, group in ipairs(self.Stub.animations) do
                if group.parent == widget.frame and group:IsPlaying() then group:Finish(); progressed = true end
            end
            for _, motion in ipairs(widget.iconJiggles or {}) do
                if motion.group:IsPlaying() then motion.group:Finish(); progressed = true end
            end
            if not progressed then return end
        end
        error("Currency feedback did not finish in a bounded number of native completions")
    end
    function f:sequence(keys, widget)
        widget = widget or self.widget
        local start = self.Stub.animationTime
        for index, key in ipairs(keys) do
            if index > 1 then self.Stub.AdvanceAnimations(0.265) end
            local group = assert(self:motion(key, widget), "Expected a native group for " .. key)
            assert(math.abs(group.starts[#group.starts] - start - (index - 1) * 0.265) < 1e-8)
            assert(math.abs(group:GetDuration() - 0.53) < 1e-8)
            for _, candidate in ipairs({ "copper", "silver", "gold", "token" }) do
                equal(self:playing(candidate, widget), candidate == key or (index > 1 and candidate == keys[index - 1]))
            end
        end
        self.Stub.AdvanceAnimations(0.53)
        for _, motion in ipairs(widget.iconJiggles or {}) do equal(motion.group:IsPlaying(), false) end
    end
    function f:token(id, quantity, icon, name)
        local data = { currencyID = id, isHeader = false, name = name or "Marks", quantity = quantity, iconFileID = icon or 101 }
        self.tokens[id] = data; self.rows[#self.rows + 1] = data; return data
    end
    function f:select(id, display)
        self.widget.settings.currencyID = id
        if display then self.widget.settings.display = display end
        self:refresh()
    end
    return f
end

check("native fragments preserve coin order exact values size and resolved font appearance", function()
    local f = fixture(); local widget = f.widget; local visual = assert(widget.currencyVisual)
    equal(widget.label:IsShown(), false); equal(#visual.texts, 3)
    equal(visual.texts[1]:GetText(), "12"); equal(visual.texts[2]:GetText(), " 34"); equal(visual.texts[3]:GetText(), " 56")
    for _, key in ipairs({ "gold", "silver", "copper" }) do
        equal(visual.icons[key]:GetAtlas(), "coin-" .. key); equal(visual.icons[key]:GetWidth(), 14)
        equal(visual.icons[key]:GetHeight(), 14); equal(visual.icons[key]:GetParent(), widget.frame)
    end
    assert(visual.icons.gold.points[1][4] < visual.texts[2].points[1][4])
    local profile = f.host:GetProfile(); profile.fontSize = 19; profile.textColor = { 0.2, 0.4, 0.6, 0.8 }; f.host:Rebuild()
    widget.label:SetFont("Custom.ttf", 17, "OUTLINE")
    widget.label:SetShadowColor(0.1, 0.2, 0.3, 0.4); widget.label:SetShadowOffset(1, -2); f:refresh()
    local text = visual.texts[1]
    local path, size, flags = text:GetFont(); equal(path, "Custom.ttf"); equal(size, 17); equal(flags, "OUTLINE")
    local r, g, b, a = text:GetTextColor(); equal(r, 0.2); equal(g, 0.4); equal(b, 0.6); equal(a, 0.8)
    r, g, b, a = text:GetShadowColor(); equal(r, 0.1); equal(g, 0.2); equal(b, 0.3); equal(a, 0.4)
    local x, y = text:GetShadowOffset(); equal(x, 1); equal(y, -2); equal(widget.iconJiggles, nil)
    local setFont, writes = text.SetFont, 0
    text.SetFont = function(...) writes = writes + 1; return setFont(...) end
    f:refresh(); f:refresh(); equal(writes, 0)
    widget.label:SetFont("Custom.ttf", 18, "OUTLINE"); f:refresh(); equal(writes, 1)
end)

check("canonical mixed-case native atlas readbacks retain all owned coin textures and sequential feedback", function()
    local f = fixture(129999, { canonicalAtlases = true }); local visual = assert(f.widget.currencyVisual)
    equal(f.widget.label:IsShown(), false)
    for _, pair in ipairs({ { "gold", "Coin-Gold" }, { "silver", "Coin-Silver" }, { "copper", "Coin-Copper" } }) do
        local icon = assert(visual.icons[pair[1]], "Each denomination must use its owned native texture")
        equal(icon:GetAtlas(), pair[2]); equal(icon:IsVisible(), true)
    end
    f.money = 130000; f:emit("PLAYER_MONEY"); f:sequence({ "copper", "silver", "gold" })
    equal(f:plays("copper"), 1); equal(f:plays("silver"), 1); equal(f:plays("gold"), 1)
end)

check("numeric token identity uses native FileID readback while older numeric GetTexture remains compatible", function()
    for _, options in ipairs({ { resolvedTokenPaths = true }, { legacyTextureReadback = true } }) do
        local f = fixture(123456, options); local data = f:token(11, 1, 101)
        f:select(11); equal(f.widget.label:IsShown(), false)
        assert(f.widget.currencyVisual.icons.token:IsVisible())
        data.quantity = 2; f:emit("CURRENCY_DISPLAY_UPDATE"); f:sequence({ "token" }); equal(f:plays("token"), 1)
    end
end)

check("changed denominations launch half a hop apart from copper to gold and refreshes stay quiet", function()
    local f = fixture(123456)
    f.money = 123457; f:poll(); f:poll()
    equal(f:plays("copper"), 1); f:emit("PLAYER_MONEY"); f:sequence({ "copper" })
    equal(f:plays("gold"), 0); equal(f:plays("silver"), 0); equal(f:plays("copper"), 1)
    f.money = 123400; f:emit("PLAYER_MONEY"); f:sequence({ "copper" }); equal(f:plays("copper"), 2)
    f.money = 123399; f:emit("PLAYER_MONEY"); f:sequence({ "copper", "silver" })
    equal(f:plays("gold"), 0); equal(f:plays("silver"), 1); equal(f:plays("copper"), 3)
    f.money = 129999; f:refresh(); f:emit("PLAYER_MONEY"); f:sequence({ "silver" })
    local gold, silver, copper = f:plays("gold"), f:plays("silver"), f:plays("copper")
    f.money = 130000; f:emit("PLAYER_MONEY"); f:sequence({ "copper", "silver", "gold" })
    equal(f:plays("gold"), gold + 1); equal(f:plays("silver"), silver + 1); equal(f:plays("copper"), copper + 1)
    f:emit("PLAYER_MONEY"); f:refresh(); f:poll(); f.host:Rebuild()
    equal(f:plays("gold"), gold + 1); equal(f:plays("silver"), silver + 1); equal(f:plays("copper"), copper + 1)
end)

check("each exact-total mode retains all fractional money and animates its single denomination", function()
    for _, key in ipairs({ "gold", "silver", "copper" }) do
        local f = fixture(); f:select(0, key); equal(f.widget.iconJiggles, nil)
        local text = f.widget.currencyVisual.texts[1]:GetText()
        equal(text, key == "gold" and "12.3456" or key == "silver" and "1234.56" or "123456")
        f.money = 123455; f:poll(); f:emit("PLAYER_MONEY"); f:sequence({ key }); equal(f:plays(key), 1)
        for _, other in ipairs({ "gold", "silver", "copper" }) do
            equal(f.widget.currencyVisual.icons[other]:IsShown(), other == key)
        end
    end
end)

check("selected token quantity changes animate only its icon and preserve selection and label behavior", function()
    local f = fixture(); local data = f:token(11, 9); f:select(11)
    local widget, visual = f.widget, f.widget.currencyVisual
    equal(visual.icons.token:GetTexture(), 101); equal(visual.texts[1]:GetText(), " 9")
    equal(visual.icons.gold:IsShown(), false); equal(visual.texts[2]:IsShown(), false)
    data.quantity = 0; f:poll(); equal(f:plays("token"), 1)
    f:emit("CURRENCY_DISPLAY_UPDATE", nil, nil, nil); f:sequence({ "token" }); equal(f:plays("token"), 1)
    data.quantity = 1.5; f:emit("CURRENCY_DISPLAY_UPDATE", 999, f.secret); f:sequence({ "token" })
    equal(f:plays("token"), 2); equal(visual.texts[1]:GetText(), " 1.5")
    widget.settings.showLabel = true; f:refresh(); f:emit("CURRENCY_DISPLAY_UPDATE")
    equal(visual.texts[1]:GetText(), " Marks 1.5"); equal(f:plays("token"), 2); equal(widget.settings.currencyID, 11)
    widget.frame:Click("LeftButton")
    assert(f.Stub.MenuItem(f.Stub.menus[#f.Stub.menus], "Money"), "Left-click currency picker remains available")
end)

check("format source label bag setting and entering-world changes silently reseed pending notifications", function()
    local f = fixture(); local data = f:token(11, 4)
    f.money = 123457; f:select(0, "gold"); f:emit("PLAYER_MONEY"); equal(f.widget.iconJiggles, nil)
    f.money = 123458; f.widget.settings.showLabel = true; f:refresh(); f:emit("PLAYER_MONEY")
    equal(f.widget.iconJiggles, nil); equal(f.widget.currencyVisual.texts[1]:GetText(), "Money 12.3458")
    f:select(11); f:emit("CURRENCY_DISPLAY_UPDATE"); equal(f.widget.iconJiggles, nil)
    data.quantity = 5; f.widget.settings.hideBagMoney = not f.widget.settings.hideBagMoney; f:refresh(); f:emit("CURRENCY_DISPLAY_UPDATE")
    equal(f.widget.iconJiggles, nil)
    data.quantity = 6; f:emit("PLAYER_ENTERING_WORLD"); f:emit("CURRENCY_DISPLAY_UPDATE")
    equal(f:playing("token"), false); local plays = f:plays("token")
    data.quantity = 7; f:emit("CURRENCY_DISPLAY_UPDATE"); f:sequence({ "token" }); equal(f:plays("token"), plays + 1)
end)

check("missing restricted and recovered readings never invent zeroes or replay changes", function()
    local f = fixture(); f.money = f.secret; f:emit("PLAYER_MONEY"); equal(f.widget.text, "--")
    equal(f.widget.label:IsShown(), true); equal(f.widget.currencyVisual.icons.gold:IsShown(), false)
    f.money = 8; f:poll(); f:emit("PLAYER_MONEY"); equal(f.widget.iconJiggles, nil)
    f.moneyError = true; f:emit("PLAYER_MONEY"); f.moneyError = false; f.money = 9
    f:emit("PLAYER_MONEY"); equal(f.widget.iconJiggles, nil)
    local data = f:token(11, 1); f:select(11); data.quantity = f.secret; f:emit("CURRENCY_DISPLAY_UPDATE")
    assert(f.widget.text:find("--", 1, true)); data.quantity = 2; f:emit("CURRENCY_DISPLAY_UPDATE")
    equal(f.widget.iconJiggles, nil)
    data.iconFileID = nil; data.quantity = 3; f:emit("CURRENCY_DISPLAY_UPDATE")
    equal(f.widget.text, "Marks 3"); equal(f.widget.label:IsShown(), true)
    data.iconFileID = 101; f:emit("CURRENCY_DISPLAY_UPDATE"); equal(f.widget.iconJiggles, nil)
end)

check("unavailable render capabilities retain inline fallback and recover using the same owned regions", function()
    local f = fixture(); local widget = f.widget; local visual = widget.currencyVisual; local icon = visual.icons.gold
    local getter = widget.label.GetTextColor
    widget.label.GetTextColor = function() return f.secret, 1, 1, 1 end
    f:refresh(); equal(widget.label:IsShown(), true); equal(widget.label:GetText(), widget.text); equal(icon:IsShown(), false)
    widget.label.GetTextColor = getter; f:refresh(); equal(widget.label:IsShown(), false); equal(visual.icons.gold, icon)
    local atlas = icon.SetAtlas; icon.currencyAsset = nil; icon.SetAtlas = function() return false end
    f:refresh(); equal(widget.label:IsShown(), true); equal(icon:IsShown(), false)
    icon.SetAtlas = atlas; f:refresh(); equal(widget.label:IsShown(), false); equal(widget.currencyVisual, visual)
    local getAtlas = icon.GetAtlas
    for _, value in ipairs({ "Coin-Silver", f.secret, false }) do
        icon.currencyAsset = nil; icon.GetAtlas = function() return value end
        f:refresh(); equal(widget.label:IsShown(), true); equal(icon:IsShown(), false)
    end
    icon.currencyAsset = nil; icon.GetAtlas = function() return nil end
    f:refresh(); equal(widget.label:IsShown(), true); equal(icon:IsShown(), false)
    icon.GetAtlas = getAtlas; f:refresh(); equal(widget.label:IsShown(), false); equal(visual.icons.gold, icon)
    local create = widget.frame.CreateTexture; widget.frame.CreateTexture = false
    f:refresh(); equal(widget.label:IsShown(), true); widget.frame.CreateTexture = create; f:refresh()
    equal(widget.currencyVisual, visual); equal(visual.icons.gold, icon); equal(widget.iconJiggles, nil)
    widget.JiggleIcon, widget.JiggleIcons, widget.StopIconJiggle = nil, nil, nil
    f.money = f.money + 1; f:emit("PLAYER_MONEY"); equal(widget.iconJiggles, nil)
end)

check("hiding removal and render recovery stop every icon without notification replay", function()
    local f = fixture(129999); f.money = 130000; f:emit("PLAYER_MONEY")
    equal(f:playing("copper"), true); equal(f:playing("silver"), false); equal(f:playing("gold"), false)
    f.widget.frame:Hide()
    for _, key in ipairs({ "gold", "silver", "copper" }) do equal(f:playing(key), false) end
    f:finish() -- A canceled sequence must not resume from a late completion.
    f.money = 140101; f:emit("PLAYER_MONEY"); f.host:Layout()
    equal(f:plays("gold"), 0); equal(f:plays("silver"), 0); equal(f:plays("copper"), 1)
    local region = f.widget.currencyVisual.texts[1]; local setText = region.SetText
    region.SetText = function() error("Currency fragment failed", 0) end
    f.host:RefreshWidget(f.widget.id); equal(f.widget.failed, "Currency fragment failed")
    equal(f.widget.label:IsShown(), true)
    for _, icon in pairs(f.widget.currencyVisual.icons) do equal(icon:IsShown(), false) end
    region.SetText = setText; f:refresh(); f:emit("PLAYER_MONEY"); equal(f:plays("gold"), 0)
    f.money = 150202; f:emit("PLAYER_MONEY"); equal(f:playing("copper"), true)
    local widget = f.widget; f.host:RemoveWidget(widget.id)
    for _, motion in ipairs(widget.iconJiggles) do equal(motion.group.playing, false) end
    f:finish(widget)
    equal(f:plays("gold", widget), 0); equal(f:plays("silver", widget), 0)
    for _, icon in pairs(widget.currencyVisual.icons) do equal(icon:IsShown(), false) end
end)

check("duplicate instances retain separate notification baselines and at most four reusable icon groups", function()
    local f = fixture(); f:token(11, 1)
    local instance = f.host:AddWidget("currency"); local other = f.host.runtime[instance.id]
    other.settings.display = "gold"; f:refresh(other)
    f.money = 129999; f:emit("PLAYER_MONEY"); f:finish(); f:finish(other)
    f.money = 130000; f:emit("PLAYER_MONEY"); f:finish(); f:finish(other)
    f:select(11); f.tokens[11].quantity = 2; f:emit("CURRENCY_DISPLAY_UPDATE"); f:finish()
    equal(#f.widget.iconJiggles, 4); equal(#other.iconJiggles, 1)
    local visual, groups = f.widget.currencyVisual, #f.Stub.animations
    for _ = 1, 15 do f:select(0, "coins"); f:select(11); f.host:Rebuild(); f:emit("CURRENCY_DISPLAY_UPDATE") end
    equal(f.widget.currencyVisual, visual); equal(#f.Stub.animations, groups); equal(#f.widget.iconJiggles, 4)
    local fresh = f.host:AddWidget("currency"); equal(f.host.runtime[fresh.id].iconJiggles, nil)
end)

check("sales purchases loot and money collected from mail notify through the authoritative player balance", function()
    local cases = {
        { "sale", 123456, 123457, { "copper" } },
        { "purchase", 123456, 123356, { "silver" } },
        { "loot", 129999, 130000, { "copper", "silver", "gold" } },
        { "mail", 123400, 124000, { "silver" } },
    }
    for _, case in ipairs(cases) do
        local f = fixture(case[2])
        for _, name in ipairs({ "BuyMerchantItem", "SellCursorItem", "LootSlot", "TakeInboxMoney", "CheckInbox" }) do
            _G[name] = function() error("Feedback must never perform a transaction: " .. name, 0) end
        end
        f.money = case[3]; f:emit("PLAYER_MONEY")
        assert(f.widget.text ~= "--", case[1] .. " keeps a readable balance")
        f:sequence(case[4])
        local changed = {}; for _, key in ipairs(case[4]) do changed[key] = true end
        for _, key in ipairs({ "copper", "silver", "gold" }) do equal(f:plays(key), changed[key] and 1 or 0) end
        f:emit("PLAYER_MONEY"); f:poll()
        for _, key in ipairs({ "copper", "silver", "gold" }) do equal(f:plays(key), changed[key] and 1 or 0) end
    end
end)

check("a late readable balance or an earlier generic refresh notifies once without depending on event ordering", function()
    local f = fixture(123456)
    f:emit("PLAYER_MONEY"); equal(f.widget.iconJiggles, nil)
    f.money = 123457; f:poll(); equal(f:playing("copper"), true)
    f:emit("PLAYER_MONEY"); f:sequence({ "copper" }); equal(f:plays("copper"), 1)
    f.money = 123458; f:emit("CURRENCY_DISPLAY_UPDATE", nil, nil, nil)
    equal(f:playing("copper"), true); f:emit("PLAYER_MONEY"); f:sequence({ "copper" })
    equal(f:plays("copper"), 2)
    f.money = 123459; f:poll(); f:sequence({ "copper" })
    equal(f:plays("copper"), 3); f:poll(); equal(f:plays("copper"), 3)
end)

check("unrelated money or token payloads never animate unchanged focused currency or supply its amount", function()
    local f = fixture(); local watched = f:token(11, 9); local other = f:token(12, 20)
    f:select(11)
    f.money = 130000; f:emit("PLAYER_MONEY"); equal(f.widget.iconJiggles, nil)
    other.quantity = 21; f:emit("CURRENCY_DISPLAY_UPDATE", 12, 99999, f.secret)
    equal(f.widget.iconJiggles, nil); equal(f.widget.currencyVisual.texts[1]:GetText(), " 9")
    watched.quantity = 10; f:emit("CURRENCY_DISPLAY_UPDATE", nil, f.secret, f.secret)
    f:sequence({ "token" }); equal(f:plays("token"), 1)
    equal(f.widget.currencyVisual.texts[1]:GetText(), " 10")
    f:emit("CURRENCY_DISPLAY_UPDATE", 11, 9000, 8990); f:poll(); equal(f:plays("token"), 1)
end)

check("bursts remain bounded while duplicate instances finish or cancel independently", function()
    local f = fixture(129999)
    local instance = f.host:AddWidget("currency"); local other = f.host.runtime[instance.id]
    f.money = 130000; f:emit("PLAYER_MONEY")
    equal(f:playing("copper"), true); equal(f:playing("copper", other), true)
    local groups = #f.Stub.animations
    for index = 1, 50 do
        f.money = 130000 + index; f:emit("PLAYER_MONEY"); f:emit("PLAYER_MONEY")
        for _, widget in ipairs({ f.widget, other }) do
            local active = 0
            for _, motion in ipairs(widget.iconJiggles or {}) do if motion.group:IsPlaying() then active = active + 1 end end
            equal(active, 1); assert(#widget.iconJiggles <= 4)
        end
    end
    equal(#f.Stub.animations, groups)
    f:finish(); equal(f:playing("copper", other), true)
    local silver, gold = f:plays("silver", other), f:plays("gold", other)
    f.host:RemoveWidget(other.id); f:finish(other)
    equal(f:plays("silver", other), silver); equal(f:plays("gold", other), gold)
    for _, motion in ipairs(other.iconJiggles or {}) do equal(motion.group:IsPlaying(), false) end
    local copper = f:plays("copper"); f:poll(); f:emit("PLAYER_MONEY"); equal(f:plays("copper"), copper)
end)

check("real currency updates stagger right to left and late bursts reuse the existing cadence", function()
    local f = fixture(129999); local widget = f.widget
    f.money = 130000; f:emit("PLAYER_MONEY")
    local width, position = widget.width, f.clock.frame.points[1][4]
    local copper, silver, gold = f:motion("copper"), f:motion("silver"), f:motion("gold")
    equal(copper.starts[1], 0); equal(silver.plays, 0); equal(gold.plays, 0)
    f.Stub.AdvanceAnimations(0.1); f.money = 130001; f:emit("PLAYER_MONEY")
    f.Stub.AdvanceAnimations(0.165)
    assert(math.abs(silver.starts[1] - 0.265) < 1e-8)
    equal(copper:IsPlaying(), true); equal(silver:IsPlaying(), true)
    f.Stub.AdvanceAnimations(0.265); assert(math.abs(gold.starts[1] - 0.53) < 1e-8)
    f.money = 130002; f:emit("PLAYER_MONEY"); equal(copper.plays, 1)
    f.Stub.AdvanceAnimations(0.265); equal(copper.plays, 2)
    assert(math.abs(copper.starts[2] - 0.795) < 1e-8)
    f.Stub.AdvanceAnimations(2)
    equal(silver.plays, 1); equal(gold.plays, 1); equal(#f.Stub.animations, 4)
    equal(widget.width, width); equal(f.clock.frame.points[1][4], position)
end)

check("changing currency source or money format cancels the remaining old sequence without replay", function()
    for _, source in ipairs({ "token", "gold" }) do
        local f = fixture(129999); local token = f:token(11, 1)
        f.money = 130000; f:emit("PLAYER_MONEY"); equal(f:playing("copper"), true)
        local copper = assert(f:motion("copper"))
        f:select(source == "token" and 11 or 0, source == "gold" and "gold" or nil)
        for _, motion in ipairs(f.widget.iconJiggles or {}) do equal(motion.group:IsPlaying(), false) end
        copper:Finish(); equal(f:plays("silver"), 0); equal(f:plays("gold"), 0)
        if source == "token" then
            token.quantity = 2; f:emit("CURRENCY_DISPLAY_UPDATE"); f:sequence({ "token" }); equal(f:plays("token"), 1)
        else
            f.money = 130001; f:emit("PLAYER_MONEY"); f:sequence({ "gold" }); equal(f:plays("gold"), 1)
        end
        equal(f:plays("silver"), 0)
    end
end)

print(passed .. " Currency icon jiggle integration tests passed")
