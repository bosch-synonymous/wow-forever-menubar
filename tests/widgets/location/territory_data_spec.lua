local root = REPO_ROOT or "."
dofile(root .. "/src/menubar-location/TerritoryData.lua")
local data = assert(MenubarLocationTerritories, "The ownership data must load before the provider")
local passed = 0
local function check(name, callback)
    callback(); passed = passed + 1; print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

check("client ownership data separates its version family from independently verified snapshots", function()
    equal(data.version, "1.60.1")
    equal(data.interface, 16001)
    equal(data.verifiedBuilds["70938"], true)
    equal(data.verifiedBuilds["70959"], true)
    equal(data.verifiedBuilds["71037"], true)
    equal(data.verifiedBuilds["99999"], nil)
end)

check("the generated data contains only canonical owned world zones and cities", function()
    local count = 0
    for mapID, record in pairs(data.maps) do
        assert(type(mapID) == "number" and mapID > 0 and mapID == math.floor(mapID))
        assert(type(record.areaID) == "number" and record.areaID > 0 and record.areaID == math.floor(record.areaID))
        assert(record.worldMapID == 0 or record.worldMapID == 1)
        assert(record.owner == "Horde" or record.owner == "Alliance")
        count = count + 1
    end
    equal(count, 17)
    equal(data.maps[1414], nil) -- Kalimdor is a continent, not an owned zone.
    equal(data.maps[1416], nil) -- Alterac Mountains is not an owned territory.
    equal(data.maps[1579], nil) -- No canonical owned zone/city assignment.
end)

check("the source joins preserve the canonical Barrens and capital identities", function()
    equal(data.maps[1413].areaID, 17)
    equal(data.maps[1413].worldMapID, 1)
    equal(data.maps[1413].owner, "Horde")
    equal(data.maps[1429].areaID, 12)
    equal(data.maps[1429].owner, "Alliance")
    equal(data.maps[1454].areaID, 1637)
    equal(data.maps[1454].owner, "Horde")
    equal(data.maps[1453].areaID, 1519)
    equal(data.maps[1453].owner, "Alliance")
end)

print(passed .. " territory data tests passed")
