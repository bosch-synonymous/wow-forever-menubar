-- Original fixtures for public currency contracts; native list state is never changed.
local root = REPO_ROOT or "."
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run)
    assert(ok, name .. ": " .. tostring(reason))
    passed = passed + 1; print("PASS " .. name)
end
local function fixture()
    local f = { money = 123456, moneyReads = 0, infoReads = 0, listReads = 0, mutations = 0,
        rows = {}, tokens = {} }
    local secret = setmetatable({}, { __tostring = function() error("restricted value formatted", 0) end,
        __lt = function() error("restricted value compared", 0) end, __le = function() error("restricted value compared", 0) end })
    f.secret = secret
    local env = setmetatable({}, { __index = _G }); env._G = env; f.env = env
    env.issecretvalue = function(value) return rawequal(value, secret) end
    env.GetMoney = function() f.moneyReads = f.moneyReads + 1; return f.money end
    env.C_CurrencyInfo = {
        GetCurrencyListSize = function() if f.count ~= nil then return f.count end; return #f.rows end,
        GetCurrencyListInfo = function(index) f.listReads = f.listReads + 1; return f.rows[index] end,
        GetCurrencyInfo = function(id)
            f.infoReads = f.infoReads + 1
            if f.infoError then error("currency temporarily unavailable", 0) end
            return f.tokens[id]
        end,
    }
    local function forbidden() f.mutations = f.mutations + 1; error("Do not change Blizzard currency state", 0) end
    for _, name in ipairs({ "ExpandCurrencyList", "SetCurrencyFilter", "SetCurrencyUnused", "SetCurrencyBackpack" }) do
        env.C_CurrencyInfo[name] = forbidden
    end
    env.Menubar = { RegisterWidgetType = function(_, definition) f.provider = definition end }
    local chunk = assert(loadfile(root .. "/src/menubar-currency/Currency.lua")); setfenv(chunk, env); chunk()
    function f:widget(settings)
        local widget = { settings = {} }
        for key, value in pairs(self.provider.defaults) do widget.settings[key] = value end
        for key, value in pairs(settings or {}) do widget.settings[key] = value end
        function widget:SetText(value) self.text = value end
        self.provider.update(widget); return widget
    end
    function f:options()
        for _, setting in ipairs(self.provider.settings) do
            if setting.key == "currencyID" then return setting.options() end
        end
        error("Missing currency selector")
    end
    function f:tooltip(widget)
        local tip = { lines = {}, rows = {} }
        function tip:AddLine(value) self.lines[#self.lines + 1] = value end
        function tip:AddDoubleLine(key, value) self.rows[key] = value end
        self.provider.tooltip(widget, tip); return tip
    end
    function f:token(id, name, quantity, icon, maximum)
        local info = { currencyID = id, name = name, isHeader = false, quantity = quantity, iconFileID = icon, maxQuantity = maximum }
        self.tokens[id] = info; return info
    end
    return f
end

check("existing money-only instances retain their source and do not scan currencies", function()
    local f = fixture(); local widget = f:widget()
    assert(widget.text:find("coin-gold", 1, true)); equal(f.infoReads, 0); equal(f.listReads, 0)
    widget.settings.currencyID = nil; f.provider.update(widget)
    assert(widget.text:find("coin-gold", 1, true)); equal(widget.settings.currencyID, nil)
    equal(f.provider.defaults.currencyID, 0)
end)

check("the picker exposes Money and readable non-header native currencies once without changing native state", function()
    local f = fixture()
    f.rows = {
        { isHeader = true, name = "Tokens" }, f:token(11, "Marks", 9, 101, 100),
        f:token(12, "Badges", 0, 102), f.tokens[11],
        { isHeader = false, currencyID = f.secret, name = "Hidden" },
        { isHeader = false, currencyID = 13, name = f.secret },
        { isHeader = f.secret, currencyID = 14, name = "Restricted type" },
        { isHeader = false, currencyID = 15.5, name = "Malformed" },
    }
    local options = f:options()
    equal(#options, 3); equal(options[1].value, 0); equal(options[1].label, "Money")
    equal(options[2].value, 11); equal(options[2].label, "Marks")
    equal(options[3].value, 12); equal(f.listReads, 8); equal(f.mutations, 0)
end)

check("missing malformed or restricted list capability stays bounded and still offers Money", function()
    for _, count in ipairs({ -1, 1.5, 0 / 0, math.huge, 10001, "2" }) do
        local f = fixture(); f.count = count
        equal(#f:options(), 1); equal(f.listReads, 0)
    end
    local f = fixture(); f.count = f.secret; equal(#f:options(), 1); equal(f.listReads, 0)
    f.env.C_CurrencyInfo = nil; equal(#f:options(), 1)
    f.env.C_CurrencyInfo = f.secret; equal(#f:options(), 1)
end)

check("selected native currency uses its icon and a fresh quantity including a real zero", function()
    local f = fixture(); local data = f:token(11, "Marks", 9, 101, 100)
    local widget = f:widget({ currencyID = 11 })
    equal(widget.text, "|T101:14:14:0:0|t 9"); equal(f.moneyReads, 0)
    data.quantity = 0; f.provider.update(widget)
    equal(widget.text, "|T101:14:14:0:0|t 0")
    widget.settings.showLabel = true; f.provider.update(widget)
    equal(widget.text, "|T101:14:14:0:0|t Marks 0")
    local tip = f:tooltip(widget)
    equal(tip.rows.Watching, "Marks"); equal(tip.rows.Amount, "0"); equal(tip.rows.Maximum, "100")
    equal(f.moneyReads, 0); equal(f.mutations, 0)
end)

check("missing icons keep the selected currency identifiable and missing amounts never become zero", function()
    local f = fixture(); local data = f:token(11, "Marks", f.secret, nil, 0)
    local widget = f:widget({ currencyID = 11 })
    equal(widget.text, "Marks --"); equal(f:tooltip(widget).rows.Amount, "Unavailable")
    equal(f:tooltip(widget).rows.Maximum, nil)
    data.quantity, data.iconFileID = 12, f.secret
    f.provider.update(widget); equal(widget.text, "Marks 12")
    data.name, data.iconFileID, data.quantity = f.secret, 101, -1
    f.provider.update(widget); equal(widget.text, "|T101:14:14:0:0|t --")
    data.quantity, data.maxQuantity = 1.5, 2.5
    f.provider.update(widget); equal(widget.text, "|T101:14:14:0:0|t 1.5")
    equal(f:tooltip(widget).rows.Maximum, "2.5")
end)

check("an unlisted saved currency remains watched and unavailable reads do not switch it to Money", function()
    local f = fixture(); f:token(11, "Marks", 13, 101)
    local widget = f:widget({ currencyID = 11 })
    equal(#f:options(), 1); equal(widget.text, "|T101:14:14:0:0|t 13")
    f.infoError = true; f.provider.update(widget)
    equal(widget.text, "Currency --"); equal(widget.settings.currencyID, 11)
    equal(f.moneyReads, 0)
    assert(table.concat(f:tooltip(widget).lines, " "):find("Selected currency is currently unavailable.", 1, true))
    f.infoError = false; f.provider.update(widget); equal(widget.text, "|T101:14:14:0:0|t 13")
end)

check("restricted malformed or mismatched currency records cannot leak into another watch", function()
    local f = fixture(); local widget = f:widget({ currencyID = 11 })
    for _, info in ipairs({ f.secret, {}, { currencyID = 12, name = "Other currency", quantity = 9 },
        { currencyID = f.secret, name = "Restricted", quantity = 9 } }) do
        f.tokens[11] = info; f.provider.update(widget)
        equal(widget.text, "Currency --"); equal(widget.settings.currencyID, 11)
    end
    for _, id in ipairs({ -1, 1.5, "11", f.secret }) do
        widget.settings.currencyID = id; local before = f.infoReads
        f.provider.update(widget); equal(widget.text, "Currency --"); equal(f.infoReads, before)
        assert(rawequal(widget.settings.currencyID, id))
    end
    equal(f.moneyReads, 0); equal(f.mutations, 0)
end)

check("duplicate instances keep different selected currencies and legacy money formatting", function()
    local f = fixture(); f:token(11, "Marks", 13, 101); f:token(12, "Badges", 7, 102)
    local first = f:widget({ currencyID = 11 }); local second = f:widget({ currencyID = 12 })
    local money = f:widget({ display = "copper" })
    equal(first.text, "|T101:14:14:0:0|t 13"); equal(second.text, "|T102:14:14:0:0|t 7")
    equal(money.text, "123456|A:coin-copper:14:14:0:0|a")
    first.settings.currencyID = 0; f.provider.update(first)
    equal(second.settings.currencyID, 12); equal(f.provider.defaults.currencyID, 0)
end)

check("ordinary click delegates only the currency selector and an older host fails safely", function()
    local f = fixture(); local widget = f:widget()
    equal(f.provider.clickHint, "Choose currency")
    equal(f.provider.click(widget), false)
    assert(widget.currencyMessage:find("Update Menubar", 1, true))
    local calls = 0
    function widget:OpenChoiceMenu(key, title)
        equal(key, "currencyID"); equal(title, "Watch currency"); calls = calls + 1; return true
    end
    equal(f.provider.click(widget), true); equal(calls, 1); equal(widget.currencyMessage, nil)
    equal(widget.settings.currencyID, 0)
end)

print(passed .. " Currency token tests passed")
