dofile("src/menubar-core/Layout.lua")
local Layout = MenubarLayout
local passed = 0
local function check(name, test)
    local ok, reason = pcall(test)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1
    print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

check("center alignment is centered on the whole screen", function()
    local items = {
        { id = "left", width = 100, alignment = "left" },
        { id = "center1", width = 40, alignment = "center" },
        { id = "center2", width = 60, alignment = "center" },
        { id = "right", width = 200, alignment = "right" },
    }
    local positions, hidden = Layout.Compute(items, 1000, 8, 12, 24)
    equal(positions.left, 44)
    equal(positions.center1, (1000 - 112) / 2)
    equal(positions.center2, positions.center1 + 52)
    equal(positions.right, 792)
    equal(#hidden, 0)
end)

check("right alignment preserves visible item order", function()
    local positions = Layout.Compute({
        { id = "one", width = 30, alignment = "right" },
        { id = "two", width = 70, alignment = "right" },
    }, 500, 8, 12, 24)
    equal(positions.one, 380)
    equal(positions.two, 422)
end)

check("overflow reserves its own button and retains hidden item references", function()
    local items = {
        { id = "one", width = 100, alignment = "left" },
        { id = "two", width = 100, alignment = "left" },
        { id = "three", width = 100, alignment = "left" },
    }
    local positions, hidden = Layout.Compute(items, 280, 8, 12, 24)
    equal(positions.one, 44)
    equal(positions.two, nil)
    equal(positions.three, nil)
    equal(#hidden, 2)
    equal(hidden[1], items[3])
    equal(hidden[2], items[2])
    equal(#items, 3)
    equal(items[1].width, 100)
end)

check("an oversized centered widget goes to overflow without shifting its neighbors", function()
    local positions, hidden = Layout.Compute({
        { id = "left", width = 40, alignment = "left" },
        { id = "center", width = 1000, alignment = "center" },
        { id = "right", width = 40, alignment = "right" },
    }, 400, 8, 12, 24)
    equal(positions.left, 44)
    equal(positions.center, nil)
    equal(positions.right, 316)
    equal(#hidden, 1)
    equal(hidden[1].id, "center")
end)

check("very narrow screens retain every widget through overflow", function()
    local items = {
        { id = "left", width = 40, alignment = "left" },
        { id = "center", width = 30, alignment = "center" },
        { id = "right", width = 50, alignment = "right" },
    }
    local positions, hidden = Layout.Compute(items, 40, 8, 12, 24)
    equal(next(positions), nil)
    equal(#hidden, #items)
end)

check("empty bars produce no overflow", function()
    local positions, hidden = Layout.Compute({}, 1000)
    equal(next(positions), nil)
    equal(#hidden, 0)
end)

check("hiding the core menu releases its width and spacing rather than leaving a blank gap", function()
    local items = {
        { id = "left", width = 100, alignment = "left" },
        { id = "right", width = 100, alignment = "right" },
    }
    local positions, hidden = Layout.Compute(items, 232, 8, 12, 0)
    equal(positions.left, 8)
    equal(positions.right, 124)
    equal(#hidden, 0)
    local _, withMenuHidden = Layout.Compute(items, 232, 8, 12, 24)
    assert(#withMenuHidden > 0)
end)

check("overflow retains its own full button width on a bar without the core menu", function()
    local items = {
        { id = "one", width = 100, alignment = "left" },
        { id = "two", width = 100, alignment = "left" },
        { id = "three", width = 100, alignment = "left" },
    }
    local positions, hidden = Layout.Compute(items, 280, 8, 12, 0)
    equal(positions.one, 8)
    equal(positions.two, 120)
    equal(positions.three, nil)
    equal(#hidden, 1)
    assert(positions.two + items[2].width <= 280 - 8 - 24 - 12)
end)

check("mixed layouts never overlap widgets or controls across viewport sizes", function()
    local alignments = { "left", "center", "right" }
    local scenarios = 0
    for _, menuWidth in ipairs({ 0, 24 }) do
    for width = 80, 1200, 40 do
        for _, padding in ipairs({ 0, 8, 24 }) do
            for _, spacing in ipairs({ 0, 4, 12 }) do
                for count = 1, 12 do
                    local items = {}
                    for index = 1, count do
                        items[index] = {
                            id = "w" .. index,
                            width = 7 + ((index * 37 + count * 19) % 130),
                            alignment = alignments[1 + ((index + count) % 3)],
                        }
                    end
                    local positions, hidden = Layout.Compute(items, width, padding, spacing, menuWidth)
                    local accounted, visible = {}, {}
                    for _, item in ipairs(hidden) do
                        assert(not accounted[item.id], "duplicate hidden widget")
                        accounted[item.id] = true
                    end
                    local centerFirst, centerLast
                    for _, item in ipairs(items) do
                        local x = positions[item.id]
                        if x then
                            assert(not accounted[item.id], "widget both hidden and visible")
                            accounted[item.id] = true
                            assert(x >= padding + (menuWidth > 0 and menuWidth + spacing or 0), "widget overlaps settings control")
                            assert(x + item.width <= width - padding - (#hidden > 0 and 24 + spacing or 0),
                                "widget overlaps overflow control")
                            visible[#visible + 1] = { x = x, width = item.width }
                            if item.alignment == "center" then
                                centerFirst = math.min(centerFirst or x, x)
                                centerLast = math.max(centerLast or (x + item.width), x + item.width)
                            end
                        end
                    end
                    for _, item in ipairs(items) do assert(accounted[item.id], "widget became inaccessible") end
                    table.sort(visible, function(a, b) return a.x < b.x end)
                    for index = 2, #visible do
                        assert(visible[index - 1].x + visible[index - 1].width + spacing <= visible[index].x,
                            "visible widgets overlap")
                    end
                    if centerFirst then equal((centerFirst + centerLast) / 2, width / 2) end
                    scenarios = scenarios + 1
                end
            end
        end
    end
    end
    print("Verified " .. scenarios .. " layout scenarios")
end)

print(string.format("%d layout tests passed", passed))
