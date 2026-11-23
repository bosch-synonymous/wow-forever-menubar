-- Original Menubar provider; never opens sockets or measures other applications.
local function validNumber(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    if type(value) == "number" and value == value and value >= 0 and value < math.huge then
        return value
    end
end

local function readStats()
    if type(GetNetStats) ~= "function" then return {} end
    local ok, incoming, outgoing, home, world = pcall(GetNetStats)
    if not ok then return {} end
    return {
        incoming = validNumber(incoming), outgoing = validNumber(outgoing),
        home = validNumber(home), world = validNumber(world),
    }
end

local function latency(value)
    return value and string.format("%.0f ms", value) or "-- ms"
end

local function traffic(value)
    -- Preserve the game's reported value; do not infer decimal/binary conversions.
    return value and string.format("%.1f", value) or "--"
end

local media = "Interface\\AddOns\\Menubar_Network\\Media\\"

local function reset(widget)
    -- Keep owned regions for recovery and retained instances, but leave ordinary
    -- host text readable when native setup fails or this widget is deactivated.
    if widget.networkIcon then pcall(widget.networkIcon.Hide, widget.networkIcon) end
    if widget.networkOutline then pcall(widget.networkOutline.Hide, widget.networkOutline) end
    widget.networkR, widget.networkG, widget.networkB, widget.networkA = nil, nil, nil, nil
    widget.customWidth = nil
    if widget.label then
        pcall(widget.label.ClearAllPoints, widget.label)
        pcall(widget.label.SetPoint, widget.label, "CENTER", widget.content or widget.frame, "CENTER")
    end
end

local function prepareIcon(widget, key, readyKey, layer, filename)
    local region = widget[key]
    if not region then
        region = widget.frame:CreateTexture(nil, layer)
        widget[key] = region -- Retain it before any native setup can fail.
    end
    if not widget[readyKey] then
        region:Hide()
        region:ClearAllPoints()
        region:SetPoint("LEFT", (widget.content or widget.frame), "LEFT", 4, 0)
        local accepted = region:SetTexture(media .. filename)
        if type(issecretvalue) == "function" and issecretvalue(accepted) then return false end
        if accepted ~= true then return false end
        widget[readyKey] = true
    end
    return true
end

local function update(widget)
    local stats = readStats()
    local selected = widget.settings.latency == "home" and "home" or "world"
    local text = latency(stats[selected])
    if widget.settings.showLabel then
        text = (selected == "home" and "Home " or "World ") .. text
    end
    if widget.settings.showThroughput then
        text = text .. "  In " .. traffic(stats.incoming) .. " / Out " .. traffic(stats.outgoing) .. " KB/s"
    end
    -- Lightweight API-v1/headless hosts can still use the original text output.
    if not widget.frame or not widget.label or type(widget.SetWidth) ~= "function"
        or type(widget.frame.CreateTexture) ~= "function" then
        reset(widget)
        widget:SetText(text)
        return
    end
    if not prepareIcon(widget, "networkOutline", "networkOutlineReady", "ARTWORK", "network-outline.tga")
        or not prepareIcon(widget, "networkIcon", "networkIconReady", "OVERLAY", "network.tga") then
        reset(widget)
        widget:SetText(text)
        return
    end
    local iconHeight = widget.content and math.min(14, widget.content:GetHeight()) or 14
    if widget.networkIconHeight ~= iconHeight then
        widget.networkOutline:SetSize(iconHeight, iconHeight)
        widget.networkIcon:SetSize(iconHeight, iconHeight)
        widget.networkIconHeight = iconHeight
    end
    local r, g, b, a = widget.label:GetTextColor()
    if not validNumber(r) or not validNumber(g) or not validNumber(b) or not validNumber(a)
        or r > 1 or g > 1 or b > 1 or a > 1 then r, g, b, a = 1, 1, 1, 1 end
    if widget.networkR ~= r or widget.networkG ~= g or widget.networkB ~= b or widget.networkA ~= a then
        local edge = (0.2126 * r + 0.7152 * g + 0.0722 * b) >= 0.5 and 0 or 1
        widget.networkIcon:SetVertexColor(r, g, b, a)
        widget.networkOutline:SetVertexColor(edge, edge, edge, a)
        widget.networkR, widget.networkG, widget.networkB, widget.networkA = r, g, b, a
    end
    widget:SetText(text) -- Semantic text remains plain for overflow and tooltips.
    local measured = validNumber(widget.label:GetStringWidth())
    if not measured then error("Network text width is unavailable", 0) end
    local width = math.max(18, math.min(9999, measured + 26))
    if widget.customWidth ~= width then widget:SetWidth(width) end
    local point, relative, relativePoint, x, y = widget.label:GetPoint(1)
    if point ~= "LEFT" or relative ~= (widget.content or widget.frame) or relativePoint ~= "LEFT" or x ~= 22 or y ~= 0 then
        widget.label:ClearAllPoints()
        widget.label:SetPoint("LEFT", (widget.content or widget.frame), "LEFT", 22, 0)
    end
    widget.networkOutline:Show()
    widget.networkIcon:Show()
end

local function tooltip(_, tip)
    local stats = readStats()
    tip:AddLine("Network")
    tip:AddLine("Your connection to Azeroth.", 1, 1, 1)
    tip:AddDoubleLine("Home latency", latency(stats.home))
    tip:AddDoubleLine("World latency", latency(stats.world))
    tip:AddDoubleLine("Incoming game traffic", traffic(stats.incoming) .. " KB/s")
    tip:AddDoubleLine("Outgoing game traffic", traffic(stats.outgoing) .. " KB/s")
    tip:AddLine("Game traffic only; KB/s units are experimental on Forever.",
        0.65, 0.65, 0.65, true)
end

Menubar:RegisterWidgetType({
    id = "network",
    retainOnDisable = true,
    name = "Network",
    defaults = { latency = "world", showLabel = false, showThroughput = false},
    legacyDefaults = { showLabel = true },
    settings = {
        {
            key = "latency", label = "Latency connection", type = "select",
            options = {
                { value = "world", label = "World" },
                { value = "home", label = "Home" },
            },
        },
        { key = "showLabel", label = "Show connection label", type = "toggle" },
        { key = "showThroughput", label = "Show game traffic (experimental)", type = "toggle" },
    },
    interval = 1,
    defaultPlacement = { bar = "top", alignment = "right", order = 2, sidebarOrder = 2 },
    update = update,
    tooltip = tooltip,
    reset = reset,
    deactivate = reset,
    destroy = reset,
})
