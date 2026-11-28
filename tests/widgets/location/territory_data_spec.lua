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

check("the generated data contains canonical territorial zones and cities", function()
    local owned, contested = 0, 0
    for mapID, record in pairs(data.maps) do
        assert(type(mapID) == "number" and mapID > 0 and mapID == math.floor(mapID))
        assert(type(record.areaID) == "number" and record.areaID > 0 and record.areaID == math.floor(record.areaID))
        assert(record.worldMapID == 0 or record.worldMapID == 1)
        if record.owner then
            assert(record.owner == "Horde" or record.owner == "Alliance")
            equal(record.classification, nil)
            owned = owned + 1
        else
            equal(record.classification, "contested")
            contested = contested + 1
        end
    end
    equal(owned, 17)
    equal(contested, 32)
    equal(data.maps[1414], nil) -- Continent.
    equal(data.maps[1579], nil) -- No canonical outdoor zone assignment.
end)

check("contested areas use their outdoor map and area identities on both continents", function()
    for _, expected in ipairs({ {1431, 10, 0}, {1434, 33, 0}, {1440, 331, 1}, {2548, 16591, 0}, {2652, 16651, 1} }) do
        local record = assert(data.maps[expected[1]])
        equal(record.areaID, expected[2])
        equal(record.worldMapID, expected[3])
        equal(record.classification, "contested")
        equal(record.owner, nil)
    end
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
