local root = REPO_ROOT or "."
local Identity = dofile(root .. "/src/menubar-core/Identity.lua")
local passed = 0
local function equal(actual, expected) assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
local function check(label, run)
    local ok, reason = pcall(run); if not ok then error(label .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. label)
end
local function fixture()
    issecretvalue = nil
    UnitGUID = function() return "Player-123-ABC" end
    UnitName = function() return "First", "Surname" end
    GetUnitName = function() return "First Surname" end
    GetRealmName = function() return "Original Realm" end
end

check("opaque player GUID makes character keys independent of display names and realm labels", function()
    fixture(); local first = assert(Identity.Read(nil)); equal(first.key, "guid:Player-123-ABC")
    GetRealmName = function() return "Changed Realm" end
    GetUnitName = function() return "Changed Name" end
    equal(assert(Identity.Read(nil)).key, first.key)
    GetRealmName = function() return "" end; equal(assert(Identity.Read(nil)).key, first.key)
    GetRealmName = nil; equal(assert(Identity.Read(nil)).key, first.key)
end)
check("characters sharing a first name remain distinct without a realm label", function()
    fixture(); GetRealmName = function() return "" end
    local first = assert(Identity.Read(nil)).key
    UnitGUID = function() return "Player-123-DEF" end
    GetUnitName = function() return "First Other" end
    assert(assert(Identity.Read(nil)).key ~= first)
end)
check("legacy exact realm keys are preferred over other characters or realm histories", function()
    fixture(); local old = { characters = { ["First - Original Realm"] = {}, ["First - Other Realm"] = {}, ["Other - Original Realm"] = {} } }
    local selected = assert(Identity.Read(old)); equal(selected.legacyKeys[1], "First - Original Realm")
    equal(#selected.legacyKeys, 1); equal(selected.key, "guid:Player-123-ABC")
end)
check("one legacy layout survives missing realm metadata without renaming or mutating it", function()
    fixture(); GetRealmName = function() return "" end
    local old = { characters = { ["First - Original Realm"] = { marker = 9 } } }
    local selected = assert(Identity.Read(old)); equal(selected.legacyKeys[1], "First - Original Realm")
    equal(old.characters["First - Original Realm"].marker, 9); equal(old.characters[selected.key], nil)
end)
check("the observed empty-realm first-name key migrates precisely despite other realm history", function()
    fixture(); GetRealmName = function() return "" end
    UnitName = function() return "Testplayer", "Surname" end
    GetUnitName = function() return "Testplayer Surname" end
    UnitGUID = function() return "Player-123-ABC" end
    local current, previous = { marker = "current" }, { marker = "previous" }
    local old = { characters = { ["Testplayer - "] = current, ["Testplayer - Old Realm"] = previous,
        ["Testplayer Surname - "] = { marker = "alternate full-name layout" } } }
    local selected = assert(Identity.Read(old))
    equal(selected.key, "guid:Player-123-ABC"); equal(#selected.legacyKeys, 2)
    equal(selected.legacyKeys[1], "Testplayer - "); equal(old.characters["Testplayer - "], current)
    local Model = dofile(root .. "/src/menubar-core/Model.lua")
    local _, character = Model.Initialize(old, selected.key, selected.legacyKeys)
    equal(character.marker, "current")
end)
check("ambiguous legacy layouts are preserved and never silently combined", function()
    fixture(); GetRealmName = nil
    local a, b = { marker = 1 }, { marker = 2 }
    local old = { characters = { ["First - A"] = a, ["First - B"] = b } }
    local selected, reason = Identity.Read(old); equal(selected, nil); assert(reason:find("Several", 1, true))
    equal(old.characters["First - A"], a); equal(old.characters["First - B"], b)
    old.characters["guid:Player-123-ABC"] = { marker = 3 }
    equal(assert(Identity.Read(old)).key, "guid:Player-123-ABC")
end)
check("legacy clients with no GUID API retain a real name and realm key", function()
    fixture(); UnitGUID, GetUnitName = nil, nil
    equal(assert(Identity.Read(nil)).key, "First - Original Realm")
    GetRealmName = function() return "" end
    local selected = Identity.Read(nil); equal(selected, nil)
end)
check("unknown or restricted identity never becomes a fake Player or Realm key", function()
    fixture(); UnitName, GetUnitName = nil, nil
    equal(Identity.Read(nil), nil)
    fixture(); UnitGUID = function() error("not ready", 0) end; equal(Identity.Read(nil), nil)
    fixture(); local secret = setmetatable({}, { __tostring = function() error("restricted identity formatted", 0) end })
    issecretvalue = function(value) return rawequal(value, secret) end
    UnitGUID = function() return secret end; equal(Identity.Read(nil), nil)
end)
check("malformed saved roots do not change identity resolution or cause mutation", function()
    fixture()
    for _, old in ipairs({ false, "bad", { characters = false }, { characters = { [9] = {}, ["First - Original Realm"] = false } } }) do
        local selected = assert(Identity.Read(old)); equal(selected.key, "guid:Player-123-ABC"); equal(#selected.legacyKeys, 0)
    end
end)
print(passed .. " character identity checks passed")
