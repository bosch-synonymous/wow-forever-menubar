-- Original layout logic. Coordinates and widths are in UI units, not physical pixels.
local Layout = {}
_G.MenubarLayout = Layout

function Layout.Compute(items, width, padding, spacing, menuWidth, overflowWidth)
    padding, spacing, menuWidth = padding or 8, spacing or 12, menuWidth or 24
    overflowWidth = overflowWidth or 24
    local groups = { left = {}, center = {}, right = {} }
    for _, item in ipairs(items) do
        local alignment = groups[item.alignment] and item.alignment or "left"
        groups[alignment][#groups[alignment] + 1] = item
    end
    local hidden = {}
    local function groupWidth(group)
        local result = 0
        for i, item in ipairs(group) do
            result = result + math.max(1, item.width) + (i > 1 and spacing or 0)
        end
        return result
    end
    local function measure()
        return groupWidth(groups.left), groupWidth(groups.center), groupWidth(groups.right)
    end
    local function fits(left, center, right)
        local first = padding + (menuWidth > 0 and menuWidth + spacing or 0)
        local last = width - padding - (#hidden > 0 and overflowWidth + spacing or 0)
        if center > 0 then
            local centerStart = (width - center) / 2
            local centerEnd = centerStart + center
            return centerStart >= first and centerEnd <= last
                and (left == 0 or first + left + spacing <= centerStart)
                and (right == 0 or last - right - spacing >= centerEnd)
        end
        return first + left + (left > 0 and right > 0 and spacing or 0) <= last - right
    end
    local left, center, right = measure()
    while not fits(left, center, right) do
        local largest = "left"
        if center > left then largest = "center" end
        if right > (largest == "left" and left or center) then largest = "right" end
        local group = groups[largest]
        if #group == 0 then break end
        hidden[#hidden + 1] = table.remove(group)
        left, center, right = measure()
    end
    local positions = {}
    local starts = {
        left = padding + (menuWidth > 0 and menuWidth + spacing or 0),
        center = (width - center) / 2,
        right = width - padding - (#hidden > 0 and overflowWidth + spacing or 0) - right,
    }
    for _, alignment in ipairs({ "left", "center", "right" }) do
        local x = starts[alignment]
        for _, item in ipairs(groups[alignment]) do
            positions[item.id] = x
            x = x + item.width + spacing
        end
    end
    return positions, hidden
end
