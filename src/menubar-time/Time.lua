-- Original Menubar clock provider. All saved settings belong to the host.
local function public(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function validPart(value, upperBound)
    return public(value) and type(value) == "number" and value >= 0 and value < upperBound
        and value == math.floor(value)
end

local function clockParts(hour, minute)
    if not validPart(hour, 24) or not validPart(minute, 60) then
        return nil
    end
    return {
        hour = hour,
        minute = minute,
    }
end

local function readClock(zone)
    if zone == "server" then
        if type(GetGameTime) == "function" then
            local ok, hour, minute = pcall(GetGameTime)
            if ok then
                -- Do not try a second API to infer a clock whose values are restricted.
                if not public(hour) or not public(minute) then return nil end
                local parts = clockParts(hour, minute)
                if parts then return parts end
            end
        end
        if C_DateAndTime and type(C_DateAndTime.GetCurrentCalendarTime) == "function" then
            local ok, calendar = pcall(C_DateAndTime.GetCurrentCalendarTime)
            if ok and public(calendar) and type(calendar) == "table" then
                return clockParts(calendar.hour, calendar.minute)
            end
        end
        return nil
    end

    if type(date) ~= "function" then
        return nil
    end
    local ok, calendar = pcall(date, zone == "utc" and "!*t" or "*t")
    if ok and public(calendar) and type(calendar) == "table" then
        return clockParts(calendar.hour, calendar.min)
    end
    return nil
end

local function formatClock(parts, settings)
    if not parts then
        return "--:--"
    end

    local hour = parts.hour
    local suffix = ""
    if settings.format == "12h" then
        suffix = hour >= 12 and " PM" or " AM"
        hour = hour % 12
        if hour == 0 then
            hour = 12
        end
    end

    local text
    if settings.format == "12h" then
        text = string.format("%d:%02d", hour, parts.minute)
    else
        text = string.format("%02d:%02d", hour, parts.minute)
    end
    return text .. suffix
end

local zoneLabels = {
    ["local"] = "Player",
    server = "Server",
    utc = "UTC",
}

local function reserveWidth(widget, prefix)
    local path, size, flags = widget.label:GetFont()
    flags = flags or ""
    local format = widget.settings.format == "12h" and "12h" or "24h"
    local cached = widget.clockSizing
    if not cached or cached.path ~= path or cached.size ~= size or cached.flags ~= flags
        or cached.format ~= format or cached.prefix ~= prefix then
        local measure = widget.clockMeasure
        if not measure then
            measure = widget.frame:CreateFontString(nil, "OVERLAY")
            widget.clockMeasure = measure
        end
        measure:Hide()
        measure:SetWordWrap(false)
        if measure:SetFont(path, size, flags) ~= true then
            -- A known native rejection must not cache measurements from the
            -- previous face or quarantine the clock. Render its current text
            -- normally and retry this owned region on the next scheduled tick.
            widget.clockSizing, widget.customWidth = nil, nil
            return
        end
        measure:SetText(prefix .. "--:--")
        local widest = measure:GetStringWidth()
        -- Measure complete strings: custom fonts can have unequal digits and kerning.
        -- This runs only when the font or display format changes, never on each tick.
        local parts = {}
        for hour = 0, 23 do
            parts.hour = hour
            for minute = 0, 59 do
                parts.minute = minute
                measure:SetText(prefix .. formatClock(parts, widget.settings))
                widest = math.max(widest, measure:GetStringWidth())
            end
        end
        cached = { path = path, size = size, flags = flags, format = format,
            prefix = prefix, width = math.max(18, math.ceil(widest) + 8) }
        widget.clockSizing = cached
    end
    if widget.customWidth ~= cached.width then widget:SetWidth(cached.width) end
end

local function update(widget)
    local settings = widget.settings
    local zone = zoneLabels[settings.zone] and settings.zone or "local"
    local prefix = settings.showLabel and (zoneLabels[zone] .. " ") or ""
    reserveWidth(widget, prefix)
    widget:SetText(prefix .. formatClock(readClock(zone), settings))
end

local function click(widget)
    local open = widget.OpenChoiceMenu
    if not public(open) or type(open) ~= "function" then return false end
    return open(widget, "zone", "Choose time zone")
end

local function tooltip(widget, tip)
    local settings = widget.settings
    tip:AddLine("Time")
    tip:AddLine("Adventure never sleeps", 1, 1, 1)
    for _, zone in ipairs({ "local", "server", "utc" }) do
        tip:AddDoubleLine(zoneLabels[zone], formatClock(readClock(zone), settings))
    end
end

Menubar:RegisterWidgetType({
    id = "time",
    retainOnDisable = true,
    name = "Time",
    clickHint = "Choose time zone",
    defaults = {
        zone = "local",
        format = "24h",
        showLabel = false,
    },
    settings = {
        {
            key = "zone",
            label = "Time zone",
            type = "select",
            options = {
                { value = "local", label = "Player" },
                { value = "server", label = "Server" },
                { value = "utc", label = "UTC" },
            },
        },
        {
            key = "format",
            label = "Clock format",
            type = "select",
            options = {
                { value = "24h", label = "24 hour" },
                { value = "12h", label = "12 hour" },
            },
        },
        { key = "showLabel", label = "Show time zone label", type = "toggle" },
    },
    interval = 1,
    defaultPlacement = { bar = "top", alignment = "right", order = 9, sidebarOrder = 13 },
    update = update,
    click = click,
    tooltip = tooltip,
})
