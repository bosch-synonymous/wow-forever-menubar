-- Exercise the real label, coordinate poll and adjacent widget layout with proportional digits.
local root = REPO_ROOT or "."
local sourceDirectory = dofile(root .. "/tests/source_paths.lua")
local Stub = dofile(root .. "/tests/wow_stub.lua")
Stub.Install()

local alternateFont = "Fonts\\MORPHEUS.TTF"
local region = getmetatable(UIParent)
local standardWidth = region.GetStringWidth
local locationLabel, labelReads = nil, 0
function region:GetStringWidth()
    local width = standardWidth(self)
    local plain = self:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if self == locationLabel then labelReads = labelReads + 1 end
    local wideDigit = self.font == alternateFont and "7" or "0"
    for digit in plain:gmatch("%d") do
        local extra = digit == wideDigit and (self.font == alternateFont and 9 or 4) or digit == "1" and -3 or 0
        width = width + extra * (self.fontSize or 12) / 12
    end
    if self.font == alternateFont then
        local _, mixedPairs = plain:gsub("87", "")
        width = width + mixedPairs * 16 * (self.fontSize or 12) / 12
    end
    return width
end

local x, y = 0.0111, 0.0911
local zone, status, inside = "The Barrens", "friendly", false
GetRealZoneText = function() return zone end
IsInInstance = function() return inside, inside and "party" or "none" end
C_PvP = { GetZonePVPInfo = function() return status end }
C_Map = {
    GetBestMapForUnit = function() return 42 end,
    GetPlayerMapPosition = function()
        if x then return { GetXY = function() return x, y end } end
    end,
}
for _, addon in ipairs({ "Menubar", "Menubar_Location" }) do
    local dir = sourceDirectory(root, addon)
    for line in io.lines(dir .. "/" .. addon .. ".toc") do
        local file = line:match("^%s*([^#]-%.lua)%s*$")
        if file then dofile(dir .. "/" .. file) end
    end
end
Menubar:RegisterWidgetType({ id = "neighbour", name = "Neighbour", defaults = {},
    defaultPlacement = { bar = "top", alignment = "left", order = 2 },
    update = function(widget) widget:SetText("Next") end,
})
Menubar:Start()
local location, neighbour
for _, widget in pairs(Menubar.runtime) do
    if widget.instance.type == "location" then location = widget end
    if widget.instance.type == "neighbour" then neighbour = widget end
end
assert(location and neighbour)
locationLabel = location.label
local function tick()
    Menubar.eventFrame.scripts.OnUpdate(Menubar.eventFrame, 0.5)
    assert(not location.failed, tostring(location.failed))
end
local function nextPosition() return neighbour.frame:GetLeft() end
assert(nextPosition() >= location.frame:GetRight(), "test neighbour must follow Location")

local function stableCoordinates(precision)
    location.settings.decimals = precision
    x, y = 0.0111, 0.0911
    tick()
    local width, nextX = location.frame:GetWidth(), nextPosition()
    local point = location.label:GetPoint()
    assert(point and point:find("LEFT", 1, true), "variable coordinate text should have a fixed left edge")
    local prefixX = location.label:GetLeft()
    local format = "(%." .. precision .. "f, %." .. precision .. "f)"
    for _, value in ipairs({ 0, 0.101, 0.1111, 0.7777, 0.8787, 0.99999, 1, 0.0111 }) do
        x, y = value, value
        local before = labelReads
        tick()
        assert(labelReads == before, "ordinary coordinate movement remeasured the visible label")
        assert(location.label:GetLeft() == prefixX, "changing coordinates moved the zone prefix")
        assert(location.label:GetText():find(format:format(x * 100, y * 100), 1, true), "coordinates must still update")
        assert(location.frame:GetWidth() == width, "changing digits resized the Location widget")
        assert(nextPosition() == nextX, "changing digits displaced the adjacent widget")
        assert(width >= location.label:GetStringWidth() + 8, "one of the visible coordinates clips")
    end
    return width
end

local whole = stableCoordinates(0)
local tenths = stableCoordinates(1)
local hundredths = stableCoordinates(2)
assert(whole < tenths and tenths < hundredths, "reservation should follow the selected precision")
local profile = Menubar:GetProfile()
profile.font = alternateFont
Menubar:Rebuild()
local differentFace = stableCoordinates(2)
assert(differentFace > hundredths, "reservation did not account for wider digits in the new face")
profile.fontSize = 18
Menubar:Rebuild()
local large = stableCoordinates(2)
assert(large > differentFace, "rebuild did not apply the larger font")

zone = "Westfall"
tick()
local shorterZone = location.width
assert(shorterZone < large, "Location retained width from the previous zone")
status = "contested"
tick()
assert(location.width > shorterZone, "territory changes should resize the label")
x, y = nil, nil
tick()
assert(location.label:GetText():find("(--, --)", 1, true))
inside = true
tick()
assert(not location.label:GetText():find("(", 1, true))
assert(location.width == location.label:GetStringWidth() + 8, "absent instance coordinates left a blank reservation")
inside, x, y = false, 0.5, 0.5
location.settings.showCoordinates = false
tick()
assert(location.width == location.label:GetStringWidth() + 8, "hidden coordinates still reserve space")
print("PASS Location keeps adjacent widgets still for proportional coordinates and resizes with the font and content")
