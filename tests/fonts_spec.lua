local root = REPO_ROOT or "."
local Fonts = dofile(root .. "/src/menubar-core/Fonts.lua")
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, run) run(); passed = passed + 1; print("PASS " .. name) end
local function option(options, value)
    for _, choice in ipairs(options) do if choice.value == value then return choice end end
end

test("built-in fonts stay first when no game enumeration is available", function()
    GetFonts = nil
    local options = Fonts.Options()
    equal(#options, 4)
    equal(options[1].value, "Fonts\\ARIALN.TTF")
    equal(options[2].label, "Friz Quadrata")
    equal(options[4].group, "Built-in fonts")
end)

test("registered and named game fonts share a sorted deduplicated second group", function()
    assert(Fonts.Register("Zeta", "Interface\\AddOns\\Example\\Zeta.ttf"))
    assert(Fonts.Register("Alpha", "Interface\\AddOns\\Example\\Alpha.ttf"))
    _G.TestGameFont = { GetFont = function() return "Fonts\\GAMEFONT.TTF", 12, "" end }
    _G.TestBuiltinAlias = { GetFont = function() return "fonts/arialn.ttf", 20, "OUTLINE" end }
    _G.TestDuplicate = { GetFont = function() return "Interface\\AddOns\\Example\\Alpha.ttf" end }
    GetFonts = function() return { "TestGameFont", "TestBuiltinAlias", "TestDuplicate", "TestGameFont" } end
    local options = Fonts.Options()
    equal(#options, 7)
    equal(options[5].label, "Alpha")
    equal(options[6].label, "TestGameFont")
    equal(options[7].label, "Zeta")
    equal(options[5].group, "Game and custom fonts")
end)

test("unavailable and malformed game font objects cannot break the picker", function()
    _G.TestBroken = { GetFont = function() error("not initialized") end }
    _G.TestNumeric = { GetFont = function() return 12345 end }
    _G.TestMissingMethod = {}
    GetFonts = function() return { false, 32, "TestBroken", "TestNumeric", "TestMissingMethod", "NoSuchFont" } end
    equal(#Fonts.Options(), 6)
    GetFonts = function() error("unavailable") end
    equal(#Fonts.Options(), 6)
    GetFonts = function() return "malformed" end
    equal(#Fonts.Options(), 6)
end)

test("unknown currently selected paths remain selectable", function()
    GetFonts = nil
    local selected = "Interface\\AddOns\\MissingFont\\Regular.ttf"
    local options = Fonts.Options(nil, selected)
    equal(option(options, selected).value, selected)
    equal(option(options, selected).group, "Game and custom fonts")
end)

test("custom persistence validates before mutating and trims names and files", function()
    local db = {}
    local result = assert(Fonts.AddCustom(db, "  Custom Family ", " Interface\\AddOns\\Fonts\\Regular.ttf ", {
        bold = " Interface\\AddOns\\Fonts\\Bold.ttf ", italic = "Interface\\AddOns\\Fonts\\Italic.ttf",
    }))
    equal(result.name, "Custom Family")
    equal(db.customFonts[result.regular].bold, "Interface\\AddOns\\Fonts\\Bold.ttf")
    local before = db.customFonts
    assert(not Fonts.AddCustom(db, "", "Regular.ttf"))
    assert(not Fonts.AddCustom(db, "Bad Face", "Regular.ttf", { bold = " " }))
    equal(db.customFonts, before)
    equal(db.customFonts["Regular.ttf"], nil)
    assert(not Fonts.AddCustom(nil, "No storage", "Regular.ttf"))
end)

test("real bold and italic files resolve without invented rendering flags", function()
    local db = {}
    assert(Fonts.AddCustom(db, "Complete", "Regular.ttf", {
        bold = "Bold.ttf", italic = "Italic.ttf", bolditalic = "BoldItalic.ttf",
    }))
    equal(Fonts.Resolve({ font = "Regular.ttf", fontStyle = "bold" }, db.customFonts), "Bold.ttf")
    equal(Fonts.Resolve({ font = "Regular.ttf", fontStyle = "italic" }, db.customFonts), "Italic.ttf")
    equal(Fonts.Resolve({ font = "Regular.ttf", fontStyle = "bolditalic" }, db.customFonts), "BoldItalic.ttf")
    equal(Fonts.Resolve({ font = "Regular.ttf", fontStyle = "regular" }, db.customFonts), "Regular.ttf")
    local styles = Fonts.Styles("regular.TTF", db.customFonts)
    equal(#styles, 4)
    equal(styles[4].value, "bolditalic")
end)

test("missing or invalid style selections use the regular face", function()
    assert(Fonts.Register("One face", "Single.ttf"))
    equal(Fonts.Resolve({ font = "Single.ttf", fontStyle = "bold" }), "Single.ttf")
    equal(Fonts.Resolve({ font = "Single.ttf", fontStyle = "OUTLINE" }), "Single.ttf")
    equal(Fonts.Resolve({ font = "Single.ttf", fontStyle = "name" }), "Single.ttf")
    equal(#Fonts.Styles("Single.ttf"), 1)
    equal(Fonts.Resolve(nil), "Fonts\\ARIALN.TTF")
end)

test("saved custom families override transient registrations and duplicate file aliases", function()
    assert(Fonts.Register("Transient", "Shared.ttf", { bold = "TransientBold.ttf" }))
    local db = {}
    assert(Fonts.AddCustom(db, "Saved", "Shared.ttf", { bold = "SavedBold.ttf" }))
    equal(option(Fonts.Options(db.customFonts), "Shared.ttf").label, "Saved")
    equal(Fonts.Resolve({ font = "SHARED.TTF", fontStyle = "bold" }, db.customFonts), "SavedBold.ttf")
    assert(Fonts.AddCustom(db, "Updated", "shared.TTF", { italic = "SavedItalic.ttf" }))
    local count = 0
    for _ in pairs(db.customFonts) do count = count + 1 end
    equal(count, 1)
    equal(Fonts.Resolve({ font = "Shared.ttf", fontStyle = "italic" }, db.customFonts), "SavedItalic.ttf")
end)

test("malformed saved font entries are ignored without changing their storage", function()
    local custom = { bad = false, broken = { name = 4 }, okay = { name = "Valid", regular = "Valid.ttf" } }
    assert(option(Fonts.Options(custom), "Valid.ttf"))
    equal(Fonts.Resolve({ font = "bad", fontStyle = "bold" }, custom), "bad")
    equal(custom.bad, false)
    equal(custom.broken.name, 4)
end)

print(passed .. " font catalogue tests passed")
