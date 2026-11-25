-- Font catalogue for game-visible assets. No operating-system font files are read.
local Fonts = {}
_G.MenubarFonts = Fonts

local builtins = {
    { value = "Fonts\\ARIALN.TTF", label = "Arial Narrow" },
    { value = "Fonts\\FRIZQT__.TTF", label = "Friz Quadrata" },
    { value = "Fonts\\MORPHEUS.TTF", label = "Morpheus" },
    { value = "Fonts\\SKURRI.TTF", label = "Skurri" },
}
local registrations = {}
local styleOrder = {
    { value = "regular", label = "Regular" },
    { value = "bold", label = "Bold" },
    { value = "italic", label = "Italic" },
    { value = "bolditalic", label = "Bold italic" },
}

local function clean(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    return value ~= "" and value or nil
end

local function key(path)
    return path:lower():gsub("/", "\\")
end

-- Some clients return no result from SetFont. The font probe and our own
-- popup fonts can confirm that the requested asset actually took effect.
function Fonts.TrySetFont(object, path, size, flags)
    local ok, result = pcall(object.SetFont, object, path, size, flags)
    if not ok or result == false then return false end
    if result == true then return true end
    local applied, height = object:GetFont()
    return type(applied) == "string" and key(applied) == key(path)
        and type(height) == "number" and math.abs(height - size) < 0.1
end

local function entry(name, regular, faces)
    name, regular = clean(name), clean(regular)
    if not name then return nil, "Enter a font name." end
    if not regular then return nil, "Enter the regular font's game asset path." end
    if faces ~= nil and type(faces) ~= "table" then return nil, "Font faces must be a table." end
    local result = { name = name, regular = regular }
    for _, style in ipairs({ "bold", "italic", "bolditalic" }) do
        local value = faces and faces[style]
        if value ~= nil then
            value = clean(value)
            if not value then return nil, "Enter a valid asset path for " .. style .. "." end
            result[style] = value
        end
    end
    return result
end

local function customEntry(value)
    if type(value) ~= "table" then return nil end
    return entry(value.name, value.regular, value)
end

local function find(path, customFonts)
    path = clean(path)
    if not path then return nil end
    local wanted = key(path)
    if type(customFonts) == "table" then
        for _, value in pairs(customFonts) do
            local selected = customEntry(value)
            if selected and key(selected.regular) == wanted then return selected end
        end
    end
    return registrations[wanted]
end

function Fonts.Register(name, regular, faces)
    local selected, message = entry(name, regular, faces)
    if not selected then return nil, message end
    registrations[key(selected.regular)] = selected
    return selected
end

function Fonts.AddCustom(db, name, regular, faces)
    if type(db) ~= "table" then return nil, "Font storage is unavailable." end
    local selected, message = entry(name, regular, faces)
    if not selected then return nil, message end
    db.customFonts = type(db.customFonts) == "table" and db.customFonts or {}
    -- One entry per regular face, even if the same path is registered with different case.
    for path in pairs(db.customFonts) do
        if type(path) == "string" and key(path) == key(selected.regular) then db.customFonts[path] = nil end
    end
    db.customFonts[selected.regular] = selected
    return selected
end

function Fonts.Options(customFonts, currentFile, otherFile)
    local options, known, candidates = {}, {}, {}
    local function add(path, name, group)
        path, name = clean(path), clean(name)
        if not path or not name or known[key(path)] then return end
        known[key(path)] = true
        local option = { value = path, label = name, group = group }
        options[#options + 1] = option
    end
    for _, builtin in ipairs(builtins) do add(builtin.value, builtin.label, "Built-in fonts") end
    -- Saved choices override transient registrations for names and actual face files.
    if type(customFonts) == "table" then
        for _, value in pairs(customFonts) do
            local selected = customEntry(value)
            if selected then candidates[key(selected.regular)] = selected end
        end
    end
    for path, value in pairs(registrations) do if not candidates[path] then candidates[path] = value end end
    if type(GetFonts) == "function" then
        local ok, names = pcall(GetFonts)
        if ok and type(names) == "table" then
            local ordered = {}
            for _, name in pairs(names) do
                if clean(name) and not name:match("^MenubarPopupFont%d+$") then ordered[#ordered + 1] = name end
            end
            table.sort(ordered)
            for _, name in ipairs(ordered) do
                local object = _G[name]
                local success, path = pcall(function() return object:GetFont() end)
                path = success and clean(path) or nil
                if path and not candidates[key(path)] then candidates[key(path)] = { name = name, regular = path } end
            end
        end
    end
    local function includeCurrent(path)
        path = clean(path)
        if path and not known[key(path)] and not candidates[key(path)] then
            candidates[key(path)] = { name = path .. " (current)", regular = path }
        end
    end
    includeCurrent(currentFile)
    includeCurrent(otherFile)
    local sorted = {}
    for _, selected in pairs(candidates) do sorted[#sorted + 1] = selected end
    table.sort(sorted, function(a, b)
        local first, second = a.name:lower(), b.name:lower()
        if first ~= second then return first < second end
        if a.name ~= b.name then return a.name < b.name end
        return a.regular < b.regular
    end)
    for _, selected in ipairs(sorted) do add(selected.regular, selected.name, "Game and custom fonts") end
    return options
end

function Fonts.Styles(path, customFonts)
    local selected = find(path, customFonts)
    local result = {}
    for _, style in ipairs(styleOrder) do
        if style.value == "regular" or (selected and selected[style.value]) then
            result[#result + 1] = { value = style.value, label = style.label }
        end
    end
    return result
end

function Fonts.Resolve(profile, customFonts)
    profile = type(profile) == "table" and profile or {}
    local path = clean(profile.font) or builtins[1].value
    local selected = find(path, customFonts)
    local style = profile.fontStyle
    if style ~= "bold" and style ~= "italic" and style ~= "bolditalic" then style = "regular" end
    return (selected and selected[style]) or path
end

return Fonts
