-- Native scalar/fallback contracts and bounded resource regressions. GC is
-- controlled only inside the isolated allocator test, never by the addon.
local root = REPO_ROOT or "."
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function entries(value) local count = 0; for _ in pairs(value) do count = count + 1 end; return count end
local function upvalue(callback, wanted, seen)
    seen = seen or {}; if seen[callback] then return end; seen[callback] = true
    for index = 1, math.huge do
        local name, value = debug.getupvalue(callback, index)
        if not name then return end
        if name == wanted then return value end
        if type(value) == "function" then local found = upvalue(value, wanted, seen); if found ~= nil then return found end end
    end
end
local function fixture()
    local f = { ids = { 1001, 1001, 2001 }, amount = 300, now = 0, scalarReads = 0,
        infoReads = 0, classReads = 0, countReads = 0, loadRequests = 0 }
    local secret = setmetatable({}, {
        __tostring = function() error("restricted value formatted", 0) end,
        __lt = function() error("restricted value compared", 0) end,
    }); f.secret = secret
    local env = setmetatable({}, { __index = _G }); env._G = env; f.env = env
    env.issecretvalue = function(value) return rawequal(value, secret) end
    env.Constants = { InventoryConstants = { NumBagSlots = 0 } }
    env.Enum = { ItemClass = { Projectile = 6 } }
    env.GetTime = function() return f.now end
    env.C_Container = {
        GetContainerNumSlots = function() return #f.ids end,
        GetContainerItemID = function(_, slot)
            f.scalarReads = f.scalarReads + 1
            if f.scalarError then error("scalar read unavailable", 0) end
            return f.ids[slot]
        end,
        GetContainerItemInfo = function(_, slot)
            f.infoReads = f.infoReads + 1
            if f.infoError then error("struct read unavailable", 0) end
            if f.infoResult then return f.infoResult end
            local id = f.ids[slot]; if id then return { itemID = id } end
        end,
    }
    env.C_Item = {
        GetItemInfoInstant = function(id)
            f.classReads = f.classReads + 1
            if not f.unresolved then return id, nil, nil, nil, 100000 + id, id == 1001 and 6 or 0 end
        end,
        GetItemInfo = function(id)
            if not f.unresolved then return id == 1001 and "Arrow" or "Bread", nil, nil, nil, nil, nil, nil, nil, nil, 100000 + id, nil, id == 1001 and 6 or 0 end
        end,
        GetItemIconByID = function(id) if not f.unresolved then return 100000 + id end end,
        GetItemCount = function(_, includeBank) equal(includeBank, false); f.countReads = f.countReads + 1; return f.amount end,
        RequestLoadItemDataByID = function() f.loadRequests = f.loadRequests + 1 end,
    }
    env.Menubar = { RegisterWidgetType = function(_, provider) f.provider = provider end }
    local chunk = assert(loadfile(root .. "/src/menubar-ammo/Ammo.lua")); setfenv(chunk, env); chunk()
    function f:widget(settings)
        local widget = { settings = { selectedID = 0, display = "count" } }
        for key, value in pairs(settings or {}) do widget.settings[key] = value end
        function widget:SetText(value) self.text = value end
        self.provider.update(widget); return widget
    end
    function f:tooltip(widget)
        local tip = { rows = {} }; function tip:AddLine() end
        function tip:AddDoubleLine(left, right) self.rows[left] = right end
        self.provider.tooltip(widget, tip); return tip
    end
    return f
end

check("scalar item IDs are preferred while counts remain authoritative and fresh", function()
    local f = fixture(); f.infoError = true
    local first = f:widget(); equal(first.text, "300")
    equal(f.scalarReads, 3); equal(f.infoReads, 0); equal(f.countReads, 1)
    local metadataReads = f.classReads
    f.amount = 19; local second = f:widget(); f.provider.update(first)
    equal(first.text, "19"); equal(second.text, "19")
    equal(f.classReads, metadataReads); equal(f.countReads, 3)
    f.amount = 0; equal(f:tooltip(first).rows["Arrow (selected)"], "0")
    equal(f.countReads, 4); equal(f.infoReads, 0)
end)

check("a successful nil scalar result is a known empty slot and never uses the struct fallback", function()
    local f = fixture(); f.ids = { false }
    f.env.C_Container.GetContainerItemID = function() f.scalarReads = f.scalarReads + 1; return nil end
    equal(f:widget().text, "No carried ammo"); equal(f.infoReads, 0); equal(f.classReads, 0)
end)

check("failed or restricted scalar reads cannot fall back or masquerade as empty inventory", function()
    for _, state in ipairs({ "error", "restricted" }) do
        local f = fixture()
        if state == "error" then f.scalarError = true else f.ids = { f.secret } end
        equal(f:widget().text, "Ammo unavailable"); equal(f.infoReads, 0)
        equal(f:widget({ selectedID = 1001 }).text, "300"); equal(f.infoReads, 0)
    end
end)

check("invalid scalar IDs remain incomplete rather than silently selecting other ammunition", function()
    for _, value in ipairs({ 0, -1, 1.5, "1001" }) do
        local f = fixture(); f.ids = { value }
        equal(f:widget().text, "Ammo data loading"); equal(f.infoReads, 0)
    end
end)

check("only an absent scalar method permits the struct compatibility path", function()
    local f = fixture(); f.env.C_Container.GetContainerItemID = nil
    equal(f:widget().text, "300"); equal(f.infoReads, 3); equal(f.scalarReads, 0)
    f.infoResult = {}; equal(f:widget().text, "Ammo data loading")
    f.infoResult = { itemID = f.secret }; equal(f:widget().text, "Ammo data loading")
    f.infoResult, f.infoError = nil, true; equal(f:widget().text, "Ammo unavailable")
    for _, state in ipairs({ "malformed", "restricted" }) do
        local other = fixture(); other.env.C_Container.GetContainerItemID = state == "malformed" and "not callable" or other.secret
        equal(other:widget().text, "Ammo unavailable"); equal(other.infoReads, 0)
    end
end)

check("cached non-projectile inventories avoid rebuilding per-item display records", function()
    local f = fixture(); f.ids = {}
    for index = 1, 100 do f.ids[index] = 2000 + index end
    local widget = f:widget(); local metadataReads = f.classReads
    collectgarbage("collect"); collectgarbage("collect")
    local before = collectgarbage("count"); collectgarbage("stop")
    local ok, reason = pcall(function() for _ = 1, 100 do f.provider.update(widget) end end)
    local growth = collectgarbage("count") - before
    collectgarbage("restart"); collectgarbage("collect")
    assert(ok, reason)
    assert(growth < 1500, "Stable scalar scans allocated excessive transient Lua memory")
    equal(f.classReads, metadataReads); equal(f.infoReads, 0)
    equal(widget.text, "No carried ammo")
end)

check("historical item metadata is bounded and evicted selections can still be resolved and counted", function()
    local f = fixture(); f.ids = { 200001 }; local widget = f:widget()
    for id = 200002, 203000 do f.ids[1] = id; f.provider.update(widget) end
    local metadata = assert(upvalue(f.provider.update, "metadata"))
    assert(entries(metadata) <= 1024, "Historical item metadata must be bounded")
    local reads = f.classReads
    f.ids[1] = 200001; f.provider.update(widget); assert(f.classReads > reads, "An evicted item should be safely described again")
    f.amount = 17; widget.settings.selectedID = 1001; f.provider.update(widget)
    equal(widget.text, "17")
    equal(#f.provider.settings[1].options(widget.settings), 1, "A saved non-carried selection must not become a possessed picker option")
end)

check("pending-load state is bounded while retained IDs keep shared ten-second request backoff", function()
    local f = fixture(); f.unresolved = true; f.ids = { 300001 }; local widget = f:widget()
    for id = 300002, 302500 do f.ids[1] = id; f.provider.update(widget) end
    assert(entries(assert(upvalue(f.provider.update, "metadata"))) <= 1024)
    assert(entries(assert(upvalue(f.provider.update, "requested"))) <= 1024)
    local requests = f.loadRequests
    f.now = 9.99; f:widget(); equal(f.loadRequests, requests)
    f.now = 10; f.provider.update(widget); equal(f.loadRequests, requests + 1)
    f.unresolved = false; f.provider.update(widget); equal(widget.text, "No carried ammo")
end)

print(passed .. " Ammo resource tests passed")
