-- Original provider. Diagnostics observe existing native measurements only.
local function public(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function object(value)
    return public(value) and (type(value) == "table" or type(value) == "userdata")
end

local function number(value)
    if public(value) and type(value) == "number" and value == value and value >= 0 and value < math.huge then return value end
end

local function integer(value)
    return number(value) and value == math.floor(value)
end

local function call(method, ...)
    if not public(method) or type(method) ~= "function" then return nil end
    local ok, value = pcall(method, ...)
    if ok and public(value) then return value end
end

local function text(value)
    return public(value) and type(value) == "string" and value ~= "" and #value <= 256
end

local function ours(name)
    local lower = name:lower()
    return lower == "menubar" or lower:match("^menubar_") or lower == "forthehoard" or lower == "shutupthrall"
end

local function fpsText(value)
    if not number(value) then return "-- FPS" end
    if value > 9999 then return "9999+ FPS" end
    return string.format("%.0f FPS", value)
end

local function frameText(value, estimated)
    if not number(value) or value == 0 then return "-- ms" end
    -- Test the bound before division: a tiny positive FPS can overflow 1000/FPS.
    if value < 1000 / 9999 then return ">9999 ms" end
    return (estimated and "~" or "") .. string.format("%.1f ms", 1000 / value)
end

local function milliseconds(value)
    if not number(value) then return "-- ms" end
    if value > 9999 then return ">9999 ms" end
    return string.format("%.2f ms", value)
end

local memoryUnits = { "B", "kB", "MB", "GB", "TB" }
local function memoryInKB(settings)
    return public(settings.memoryInKB) and settings.memoryInKB == true
end

local function memoryText(value, forceKB)
    if not number(value) then return "Unavailable" end
    if forceKB then
        if value >= 99999999.95 then return "99999999.9+ kB" end
        return string.format("%.1f kB", value)
    end
    local unit = 2 -- Native addon memory readings are in kB.
    if value < 1 then value, unit = value * 1024, 1 end
    -- Promote from the original value before one-decimal rounding would
    -- produce 1024.0 in the smaller unit.
    while value >= 1023.95 and unit < #memoryUnits do
        value, unit = value / 1024, unit + 1
    end
    if value >= 9999.95 then return "9999.9+ TB" end
    return string.format("%.1f %s", value, memoryUnits[unit])
end

local function countText(value)
    if not integer(value) then return "--" end
    return value > 999999 and "999999+" or string.format("%.0f", value)
end

local function displayMode(settings)
    local value = settings.display
    if public(value) and (value == "frameTime" or value == "both") then return value end
    return "fps"
end

local function diagnostics(settings)
    return public(settings.diagnostics) and settings.diagnostics == true
end

local function usageMetric(settings)
    if public(settings.usageMetric) and settings.usageMetric == "memory" then return "memory" end
    return "cpu"
end

local function memoryUsage(value, forceKB)
    return number(value) and memoryText(value, forceKB) or "-- kB"
end

-- One shared cache: one-second CPU and memory sampled at most every
-- 15 seconds, matching Blizzard's throttle for its expensive memory refresh.
-- Memory refreshes are requested by tooltips and visible memory-mode widgets.
-- Names are enumerated again only when the installed count changes or a prior
-- catalogue was incomplete. Loaded state remains live at each sample.
local shared = {}
local function clock()
    local now = number(call(GetTime))
    if not now then return nil end
    if shared.clock and now < shared.clock then shared = {} end
    shared.clock = now
    return now
end

local function fresh(now, sample, ttl)
    return sample and now >= sample.time and now - sample.time < (ttl or 1)
end

local function catalogue()
    if not object(C_AddOns) then return nil end
    local count = call(C_AddOns.GetNumAddOns)
    if not integer(count) or count > 10000 then return nil end
    local cached = shared.catalogue
    if cached and cached.count == count and cached.complete then return cached end
    local result = { count = count, names = {}, complete = true }
    local seen = {}
    for index = 1, count do
        -- Forever GetAddOnInfo returns a tuple; the first return is the name.
        local name = call(C_AddOns.GetAddOnInfo, index)
        if text(name) and not seen[name] then
            seen[name] = true; result.names[#result.names + 1] = name
        else result.complete = false end
    end
    shared.catalogue = result
    return result
end

local function loaded(name)
    if not object(C_AddOns) or not public(C_AddOns.IsAddOnLoaded) or type(C_AddOns.IsAddOnLoaded) ~= "function" then return nil end
    local ok, loadingOrLoaded, fullyLoaded = pcall(C_AddOns.IsAddOnLoaded, name)
    if not ok or not public(loadingOrLoaded) or not public(fullyLoaded)
        or type(loadingOrLoaded) ~= "boolean" or type(fullyLoaded) ~= "boolean"
        or (fullyLoaded and not loadingOrLoaded) then return nil end
    return fullyLoaded
end

local function active(names, onlyOurs)
    local result, complete, projectComplete = {}, names.complete, names.complete
    for _, name in ipairs(names.names) do
        if not onlyOurs or ours(name) then
            local state = loaded(name)
            if state == true then result[#result + 1] = name
            elseif state == nil then
                complete = false
                if ours(name) then projectComplete = false end
            end
        end
    end
    table.sort(result)
    return result, complete, projectComplete
end

local function memorySnapshot(now)
    if not now then return { names = {}, values = {}, top = {}, complete = false, projectComplete = false } end
    if fresh(now, shared.memory, 15) then return shared.memory end
    local result = { time = now, names = {}, values = {}, top = {}, complete = false, projectComplete = false }
    local names = catalogue()
    if names then
        result.names, result.complete, result.projectComplete = active(names, false)
        if public(UpdateAddOnMemoryUsage) and type(UpdateAddOnMemoryUsage) == "function"
            and public(GetAddOnMemoryUsage) and type(GetAddOnMemoryUsage) == "function" then
            local refreshed = pcall(UpdateAddOnMemoryUsage)
            if refreshed then
                local total, projectTotal = 0, 0
                for _, name in ipairs(result.names) do
                    local value = number(call(GetAddOnMemoryUsage, name))
                    result.values[name] = value
                    if value then
                        result.top[#result.top + 1] = { name = name, value = value }
                        local sum = number(total + value)
                        if sum then total = sum else result.complete = false end
                        if ours(name) then
                            local projectSum = number(projectTotal + value)
                            if projectSum then projectTotal = projectSum else result.projectComplete = false end
                        end
                    else
                        result.complete = false
                        if ours(name) then result.projectComplete = false end
                    end
                end
                if result.complete then result.total = total end
                if result.projectComplete then result.projectTotal = projectTotal end
            else result.complete, result.projectComplete = false, false end
        else result.complete, result.projectComplete = false, false end
    end
    table.sort(result.top, function(left, right)
        return left.value == right.value and left.name < right.name or left.value > right.value
    end)
    shared.memory = result
    return result
end

local metricNames = { recent = "RecentAverageTime", session = "SessionAverageTime", peak = "PeakTime",
    over5 = "CountTimeOver5Ms", over10 = "CountTimeOver10Ms" }

local function cpuMetric(name, key)
    local enums = object(Enum) and Enum.AddOnProfilerMetric
    local metric = object(enums) and enums[metricNames[key]]
    if not integer(metric) or metric > 1000 or not object(C_AddOnProfiler) then return nil end
    local value = number(call(C_AddOnProfiler.GetAddOnMetric, name, metric))
    if (key == "over5" or key == "over10") and not integer(value) then return nil end
    return value
end

local function expandCPU(result)
    -- The expensive scope expansion belongs to hover, never ordinary bar ticks.
    -- Keep the project's original sample time and readings, including unknowns.
    result.allSampled, result.allComplete, result.allNames, result.top = true, false, {}, {}
    local names = result.catalogue
    if not names and result.enabled ~= true then names = catalogue() end
    if not names then return end
    local complete
    result.allNames, complete = active(names, false)
    if result.enabled ~= true then return end
    local total = 0
    for _, name in ipairs(result.allNames) do
        local value
        if ours(name) then
            local values = result.values[name]
            value = values and values.recent
        else value = cpuMetric(name, "recent") end
        if value then
            result.top[#result.top + 1] = { name = name, value = value }
            local sum = number(total + value)
            if sum then total = sum else complete = false end
        else complete = false end
    end
    table.sort(result.top, function(left, right)
        return left.value == right.value and left.name < right.name or left.value > right.value
    end)
    result.allComplete = complete
    if complete then result.allRecent = total end
end

local function cpuSnapshot(now, includeAll)
    if not now then return { names = {}, values = {}, allNames = {}, top = {}, allComplete = false } end
    local result = shared.cpu
    if not fresh(now, result) then
        result = { time = now, names = {}, values = {} }
        if object(C_AddOnProfiler) then result.enabled = call(C_AddOnProfiler.IsEnabled) end
        if result.enabled == true then
            local names = catalogue()
            result.catalogue = names
            if names then
                local complete
                result.names, complete = active(names, true)
                local recent, session, recentComplete, sessionComplete = 0, 0, complete, complete
                for _, name in ipairs(result.names) do
                    local values = {}
                    result.values[name] = values
                    for key in pairs(metricNames) do values[key] = cpuMetric(name, key) end
                    if values.recent then
                        local sum = number(recent + values.recent)
                        if sum then recent = sum else recentComplete = false end
                    else recentComplete = false end
                    if values.session then
                        local sum = number(session + values.session)
                        if sum then session = sum else sessionComplete = false end
                    else sessionComplete = false end
                end
                if recentComplete then result.recent = recent end
                if sessionComplete then result.session = session end
            end
        end
        shared.cpu = result
    end
    if includeAll and not result.allSampled then expandCPU(result) end
    return result
end

local function display(fps, mode)
    if mode == "frameTime" then return frameText(fps, true) end
    if mode == "both" then return fpsText(fps) .. " / " .. frameText(fps, true) end
    return fpsText(fps)
end

local function boundedWidth(value)
    if number(value) then return math.min(9999, math.max(18, math.ceil(value) + 8)) end
end

local media = "Interface\\AddOns\\Menubar_Performance\\Media\\"
local function hideIcon(widget)
    for _, key in ipairs({ "performanceIcon", "performanceIconOutline" }) do
        local icon = widget[key]
        if object(icon) and type(icon.Hide) == "function" then pcall(icon.Hide, icon) end
    end
    widget.performanceIconShown, widget.performanceIconTint = nil, nil
    if widget.performanceIconAnchored then
        widget.performanceIconAnchored = nil
        widget.label:ClearAllPoints()
        widget.label:SetPoint("CENTER", widget.content or widget.frame, "CENTER")
    end
end

local function colorComponent(value)
    return number(value) and value <= 1
end

local function renderIcon(widget)
    local frame, label = widget.frame, widget.label
    local content = widget.content or frame
    -- Older/headless hosts retain the original text-only presentation.
    if not object(frame) or type(frame.CreateTexture) ~= "function" or not object(label)
        or type(label.GetTextColor) ~= "function" or type(label.ClearAllPoints) ~= "function"
        or type(label.SetPoint) ~= "function" then hideIcon(widget); return 0 end
    local red, green, blue, alpha = label:GetTextColor()
    if not colorComponent(red) or not colorComponent(green) or not colorComponent(blue) or not colorComponent(alpha) then
        hideIcon(widget); return 0
    end
    local outline = widget.performanceIconOutline
    if not outline then
        outline = frame:CreateTexture(nil, "ARTWORK", nil, 0)
        widget.performanceIconOutline = outline
        outline:Hide()
    end
    local icon = widget.performanceIcon
    if not icon then
        icon = frame:CreateTexture(nil, "ARTWORK", nil, 1)
        widget.performanceIcon = icon
        icon:Hide()
    end
    local iconHeight = widget.content and math.min(14, content:GetHeight()) or 14
    if not widget.performanceIconReady or widget.performanceIconHeight ~= iconHeight then
        outline:SetSize(iconHeight, iconHeight); icon:SetSize(iconHeight, iconHeight)
        widget.performanceIconHeight = iconHeight
    end
    if not widget.performanceIconReady then
        outline:ClearAllPoints(); outline:SetPoint("LEFT", content, "LEFT", 4, 0)
        icon:ClearAllPoints(); icon:SetPoint("LEFT", content, "LEFT", 4, 0)
        local edge = outline:SetTexture(media .. "performance-outline.tga")
        local body = icon:SetTexture(media .. "performance.tga")
        if not public(edge) or edge ~= true or not public(body) or body ~= true then hideIcon(widget); return 0 end
        widget.performanceIconReady = true
    end
    local tint = widget.performanceIconTint
    if not tint or tint[1] ~= red or tint[2] ~= green or tint[3] ~= blue or tint[4] ~= alpha then
        local opposite = red * 0.2126 + green * 0.7152 + blue * 0.0722 >= 0.5 and 0 or 1
        icon:SetVertexColor(red, green, blue, alpha)
        outline:SetVertexColor(opposite, opposite, opposite, alpha)
        widget.performanceIconTint = { red, green, blue, alpha }
    end
    if not widget.performanceIconAnchored then
        label:ClearAllPoints(); label:SetPoint("LEFT", content, "LEFT", 22, 0)
        widget.performanceIconAnchored = true
    end
    if not widget.performanceIconShown then
        outline:Show(); icon:Show(); widget.performanceIconShown = true
    end
    return 18
end

local function reserveWidth(widget, mode, diagnostic, metric, forceKB, iconSpace)
    local path, size, flags
    if type(widget.label.GetFont) == "function" then
        local ok
        ok, path, size, flags = pcall(widget.label.GetFont, widget.label)
        if not ok or not text(path) or not number(size) or size == 0 or size > 256
            or not public(flags) or (flags ~= nil and (type(flags) ~= "string" or #flags > 64)) then path, size, flags = nil, nil, nil end
    end
    flags = flags or ""
    local cached = widget.performanceSizing
    if not cached or cached.path ~= path or cached.size ~= size or cached.flags ~= flags
        or cached.mode ~= mode or cached.diagnostics ~= diagnostic or cached.metric ~= metric or cached.memoryInKB ~= forceKB then
        cached = { path = path, size = size, flags = flags, mode = mode, diagnostics = diagnostic, metric = metric,
            memoryInKB = forceKB,
            width = (mode == "both" and 180 or 90) + (diagnostic and (metric == "memory" and 220 or 160) or 0) }
        widget.performanceSizing = cached
        if path then
            local measure = widget.performanceMeasure
            if not measure then
                measure = widget.frame:CreateFontString(nil, "OVERLAY")
                widget.performanceMeasure = measure
            end
            measure:Hide()
            measure:SetWordWrap(false)
            local accepted = measure:SetFont(path, size, flags)
            if public(accepted) and accepted ~= false then
                local fallbackWidth, validMeasurement = cached.width, false
                cached.measured = true
                cached.width = 18
                local function sample(candidate)
                    measure:SetText(candidate)
                    local width = boundedWidth(measure:GetStringWidth())
                    if width then validMeasurement = true; cached.width = math.max(cached.width, width) end
                end
                for digit = 0, 9 do
                    local character = tostring(digit)
                    local fps = string.rep(character, 4) .. " FPS"
                    local frame = "~" .. string.rep(character, 4) .. "." .. character .. " ms"
                    local candidate = mode == "both" and (fps .. " / " .. frame) or mode == "frameTime" and frame or fps
                    if diagnostic and metric == "memory" then
                        if forceKB then sample(candidate .. " | Addons " .. string.rep(character, 8) .. "." .. character .. " kB")
                        else
                            for _, unit in ipairs(memoryUnits) do
                                sample(candidate .. " | Addons " .. string.rep(character, 4) .. "." .. character .. " " .. unit)
                            end
                        end
                    elseif diagnostic then
                        sample(candidate .. " | Addons " .. string.rep(character, 4) .. "." .. string.rep(character, 2) .. " ms")
                    else sample(candidate) end
                end
                local unavailable = metric == "memory" and "-- kB" or "-- ms"
                sample(display(nil, mode) .. (diagnostic and (" | Addons " .. unavailable) or ""))
                local cap = mode == "both" and "9999+ FPS / >9999 ms" or mode == "frameTime" and ">9999 ms" or "9999+ FPS"
                local usageCap = metric == "memory" and (forceKB and "99999999.9+ kB" or "9999.9+ TB") or ">9999 ms"
                sample(cap .. (diagnostic and (" | Addons " .. usageCap) or ""))
                if not validMeasurement then cached.measured, cached.width = false, fallbackWidth end
            end
        end
    end
    local width = math.min(9999, cached.width + iconSpace)
    if widget.customWidth ~= width then widget:SetWidth(width) end
    return cached
end

local function update(widget)
    local mode, diagnostic, metric = displayMode(widget.settings), diagnostics(widget.settings), usageMetric(widget.settings)
    local forceKB = metric == "memory" and memoryInKB(widget.settings) or false
    local value = display(number(call(GetFramerate)), mode)
    if diagnostic then
        local usage = metric == "memory" and memoryUsage(memorySnapshot(clock()).projectTotal, forceKB)
            or milliseconds(cpuSnapshot(clock()).recent)
        value = value .. " | Addons " .. usage
    end
    local iconSpace = renderIcon(widget)
    local cached = reserveWidth(widget, mode, diagnostic, metric, forceKB, iconSpace)
    widget:SetText(value)
    if cached.lastText ~= value then
        -- The displayed string catches unusual kerning without touching the
        -- hidden measuring region again. An outlier grows, never shrinks, it.
        local width = boundedWidth(call(widget.label.GetStringWidth, widget.label))
        if width and width > cached.width then cached.width = width; widget:SetWidth(math.min(9999, width + iconSpace)) end
        cached.lastText = value
    end
end

local function tooltip(widget, tip)
    local fps, now = number(call(GetFramerate)), clock()
    tip:AddLine("Performance")
    tip:AddLine("Keeping an eye on the numbers.", 1, 1, 1)
    tip:AddDoubleLine("Frame rate", fpsText(fps))
    tip:AddDoubleLine("Estimated frame time", frameText(fps, false))
    if usageMetric(widget.settings) == "memory" then
        local forceKB = memoryInKB(widget.settings)
        local memory = memorySnapshot(now)
        tip:AddDoubleLine("Addon Lua memory", memoryText(memory.total, forceKB))
        tip:AddLine(memory.complete and "Largest addons by Lua memory" or "Largest readable addons by Lua memory")
        for index = 1, math.min(5, #memory.top) do
            local addon = memory.top[index]
            tip:AddDoubleLine(addon.name, memoryText(addon.value, forceKB))
        end
        if not memory.complete then tip:AddLine("Some memory readings are unavailable; a complete total cannot be shown.", 0.65, 0.65, 0.65, true) end
        tip:AddLine("Lua memory; snapshots are up to 15 seconds old.", 0.65, 0.65, 0.65, true)
        if not diagnostics(widget.settings) then return end
        tip:AddLine("Our addons")
        tip:AddLine("Menubar and its widgets, ForTheHoard and ShutUpThrall.", 0.65, 0.65, 0.65, true)
        tip:AddDoubleLine("Our addons Lua memory", memoryText(memory.projectTotal, forceKB))
        for _, name in ipairs(memory.names) do
            if ours(name) then tip:AddDoubleLine(name, memoryText(memory.values[name], forceKB)) end
        end
        if not memory.projectComplete then
            tip:AddLine("Some readings for our addons are unavailable; their total is unknown.", 0.65, 0.65, 0.65, true)
        end
        return
    end
    local cpu = cpuSnapshot(now, true)
    tip:AddDoubleLine("Approx. addon CPU / tick", milliseconds(cpu.allRecent))
    tip:AddLine(cpu.allComplete and "Largest addons by recent CPU" or "Largest readable addons by recent CPU")
    for index = 1, math.min(5, #cpu.top) do
        local addon = cpu.top[index]
        tip:AddDoubleLine(addon.name, milliseconds(addon.value))
    end
    if not cpu.allComplete and cpu.enabled == true then tip:AddLine("Some CPU readings are unavailable; a complete total cannot be shown.", 0.65, 0.65, 0.65, true) end
    if cpu.enabled ~= true then tip:AddLine("CPU profiling is unavailable or disabled.", 0.65, 0.65, 0.65, true) end
    tip:AddLine("Recent CPU: average over the last 60 ticks; snapshots cached for 1 second. Totals are approximate.", 0.65, 0.65, 0.65, true)
    if not diagnostics(widget.settings) then return end
    tip:AddLine("Our addons")
    tip:AddLine("Menubar and its widgets, ForTheHoard and ShutUpThrall.", 0.65, 0.65, 0.65, true)
    tip:AddDoubleLine("Approx. recent CPU / tick", milliseconds(cpu.recent))
    tip:AddDoubleLine("Approx. session CPU / tick", milliseconds(cpu.session))
    for _, name in ipairs(cpu.allNames) do
        if ours(name) then
            local values = cpu.values[name] or {}
            tip:AddDoubleLine(name, "recent " .. milliseconds(values.recent) .. " | session " .. milliseconds(values.session))
            tip:AddDoubleLine("  Peak / ticks >5 / >10 ms", milliseconds(values.peak) .. " / " .. countText(values.over5) .. " / " .. countText(values.over10))
        end
    end
    tip:AddLine("Session averages and peaks are since client startup; peaks are never summed.", 0.65, 0.65, 0.65, true)
end

local function destroy(widget)
    widget.performanceSizing, widget.customWidth = nil, nil
    hideIcon(widget)
    local measure = widget.performanceMeasure
    if object(measure) and type(measure.Hide) == "function" then pcall(measure.Hide, measure) end
end

Menubar:RegisterWidgetType({
    id = "performance", name = "Performance",
    retainOnDisable = true,
    defaults = { display = "fps", diagnostics = false, usageMetric = "memory", memoryInKB = false},
    legacyDefaults = { diagnostics = false, usageMetric = "cpu" },
    settings = {
        { key = "display", label = "Display", type = "select", options = {
            { value = "fps", label = "Frame rate" },
            { value = "frameTime", label = "Estimated frame time" },
            { value = "both", label = "Frame rate and estimated frame time" },
        } },
        { key = "diagnostics", label = "Monitor our addons", type = "toggle" },
        { key = "usageMetric", label = "Addon usage", type = "select", options = {
            { value = "cpu", label = "CPU time" },
            { value = "memory", label = "Memory" },
        } },
        { key = "memoryInKB", label = "Always use kB for memory", type = "toggle" },
    },
    interval = 0.5,
    defaultPlacement = { bar = "top", alignment = "right", order = 1, sidebarOrder = 1 },
    update = update, tooltip = tooltip, reset = destroy, deactivate = destroy, destroy = destroy,
})
