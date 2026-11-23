-- The real TOC declares one native shortcut; widgets share its original artwork.
-- Rendering and the native compartment's population still require the client.
local root = REPO_ROOT or "."
local passed = 0
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function metadata(path)
    local values = {}
    for line in io.lines(path) do
        local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
        if key then assert(values[key] == nil, "Duplicate metadata: " .. key); values[key] = value end
    end
    return values
end
local function fixture()
    local Stub = dofile(root .. "/tests/wow_stub.lua"); Stub.Install(); MenubarDB = nil
    for line in io.lines(root .. "/src/menubar-core/Menubar.toc") do
        local file = line:match("^%s*(.-)%s*$")
        if file:match("%.lua$") then assert(loadfile(root .. "/src/menubar-core/" .. file))("Menubar", {}) end
    end
    return Stub, Menubar
end

check("the main AddOns icon names a shipped texture and one native settings callback", function()
    local fields = metadata(root .. "/src/menubar-core/Menubar.toc")
    local relative = assert(fields.IconTexture):match("^Interface\\AddOns\\Menubar\\(.+)$")
    assert(relative and not relative:find("%.%."))
    local file = assert(io.open(root .. "/src/menubar-core/" .. relative:gsub("\\", "/"), "rb"))
    local header = file:read(18); file:close()
    assert(header and #header == 18 and header:byte(3) == 2 and header:byte(17) == 32, "Expected original RGBA TGA")
    assert(fields.AddonCompartmentFunc == "Menubar_OnAddonCompartmentClick")
end)

check("the compartment callback respects startup state and opens the existing settings route", function()
    local _, host = fixture()
    local opens = 0
    host.UI.OpenSettings = function() opens = opens + 1 end
    Menubar_OnAddonCompartmentClick("Menubar", "LeftButton")
    assert(opens == 0 and MenubarDB == nil and not host.ready)
    host:Start()
    Menubar_OnAddonCompartmentClick("Menubar", "LeftButton")
    assert(opens == 1 and host.ready)
    Menubar_OnAddonCompartmentClick("Menubar", "RightButton")
    assert(opens == 2)
end)

print(passed .. " AddOns icon tests passed")
