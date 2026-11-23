-- Original public-contract fixtures. They verify native API inputs and output
-- semantics without claiming to emulate the client's profiler or UI renderer.
local root = REPO_ROOT or "."
local passed = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function row(tip, caption)
    for _, value in ipairs(tip.lines) do if value[1] == caption then return value[2] end end
end
local function tipText(tip)
    local values = {}
    for _, value in ipairs(tip.lines) do values[#values + 1] = table.concat(value, " | ") end
    return table.concat(values, "\n")
end
local function textWidth(text, path, size, flags)
    local total = 0
    for letter in text:gmatch(".") do
        local width = ({ ["1"] = 3, ["8"] = 9, ["9"] = 8, ["0"] = 8, [" "] = 3, ["."] = 2, ["/"] = 4 })[letter] or 7
        if path == "UnavailableWide.ttf" and letter == "-" then width = 20 end
        total = total + width
    end
    return total * (size or 12) / 12 * (path == "Wide.ttf" and 1.4 or 1) * (flags == "BOLD" and 1.12 or 1)
end
local function fixture()
    local f = { fps = 60, now = 100, fpsReads = 0, memoryScans = 0, memoryReads = 0,
        addonEnumerations = 0, metricReads = {}, forbidden = 0, measurements = 0, fontCreations = 0, profilerChecks = 0,
        profilingEnabled = true, addons = {}, metrics = {} }
    local secret = setmetatable({}, {
        __index = function() error("restricted value was indexed", 0) end,
        __lt = function() error("restricted value was compared", 0) end,
        __le = function() error("restricted value was compared", 0) end,
        __tostring = function() error("restricted value was formatted", 0) end,
    })
    f.secret = secret
    local env = setmetatable({}, { __index = _G }); env._G = env; f.env = env
    env.issecretvalue = function(value) return rawequal(value, secret) end
    env.GetFramerate = function() f.fpsReads = f.fpsReads + 1; if f.fpsError then error("framerate temporarily unavailable", 0) end; return f.fps end
    env.GetTime = function() if f.clockError then error("clock unavailable", 0) end; return f.now end
    local function forbidden()
        f.forbidden = f.forbidden + 1; error("Performance must not change native profiling, counters, CVars or garbage collection", 0)
    end
    env.SetCVar, env.collectgarbage = forbidden, forbidden
    env.C_CVar = { SetCVar = forbidden }
    env.ResetCPUUsage, env.UpdateAddOnCPUUsage, env.GetAddOnCPUUsage = forbidden, forbidden, forbidden
    env.Enum = { AddOnProfilerMetric = { SessionAverageTime = 0, RecentAverageTime = 1, PeakTime = 4,
        CountTimeOver5Ms = 6, CountTimeOver10Ms = 7 } }
    local names = { "Menubar", "Menubar_Performance", "Menubar_Time", "ForTheHoard", "ShutUpThrall",
        "OtherHeavy", "OtherSecond", "OtherThird", "OtherFourth", "Dormant", "Loading" }
    local memory = { 128, 64, 32, 16, 8, 1024, 512, 256, 192, 9999, 8888 }
    for index, name in ipairs(names) do
        f.addons[index] = { name = name, memory = memory[index], loadedOrLoading = index ~= 10, loaded = index < 10 }
        f.metrics[name] = { [0] = index <= 5 and (index / 10 + 0.1) or 0.5,
            [1] = index <= 5 and index / 10 or 0.25, [4] = index + 2, [6] = index, [7] = index - 1 }
    end
    local function addon(value)
        if type(value) == "number" then return f.addons[value] end
        for _, entry in ipairs(f.addons) do if entry.name == value then return entry end end
    end
    env.C_AddOns = {
        GetNumAddOns = function() f.addonEnumerations = f.addonEnumerations + 1; return f.addonCount or #f.addons end,
        GetAddOnInfo = function(index)
            if f.catalogueError then error("addon catalogue unavailable", 0) end
            local entry = addon(index)
            return entry and entry.name, "Addon title", "Notes", true
        end,
        IsAddOnLoaded = function(name)
            local entry = assert(addon(name), "Expected an installed addon name")
            return entry.loadedOrLoading, entry.loaded
        end,
    }
    env.UpdateAddOnMemoryUsage = function(...)
        equal(select("#", ...), 0); f.memoryScans = f.memoryScans + 1
        if f.memoryError then error("native memory update unavailable", 0) end
    end
    env.GetAddOnMemoryUsage = function(name)
        f.memoryReads = f.memoryReads + 1
        local entry = assert(addon(name), "Memory reads require a native addon name or index")
        assert(entry.loaded == true, "Loading or disabled addons must not be treated as loaded")
        return entry.memory
    end
    env.C_AddOnProfiler = {
        IsEnabled = function() f.profilerChecks = f.profilerChecks + 1; if f.profilerError then error("profiler unavailable", 0) end; return f.profilingEnabled end,
        GetAddOnMetric = function(name, metric)
            assert(type(name) == "string", "Profiler's first argument is the addon name")
            assert(type(metric) == "number" and (metric == 0 or metric == 1 or metric == 4 or metric == 6 or metric == 7), "Profiler requires a validated native metric enum")
            f.metricReads[#f.metricReads + 1] = { name = name, metric = metric }
            if f.metricError then error("native metric unavailable", 0) end
            return assert(f.metrics[name], "Unknown profiler addon")[metric]
        end,
        ResetMetrics = forbidden,
    }
    env.Menubar = { RegisterWidgetType = function(_, definition) assert(not f.provider); f.provider = definition end }
    local namespace = {}
    for line in io.lines(root .. "/src/menubar-performance/Menubar_Performance.toc") do
        local name = line:match("^%s*(.-)%s*$")
        if name:match("%.lua$") then
            local chunk = assert(loadfile(root .. "/src/menubar-performance/" .. name))
            setfenv(chunk, env); chunk("Menubar_Performance", namespace)
        end
    end
    assert(f.provider, "Performance must register with its host")
    local function fontString(measuring)
        local label = { text = "", path = "Default.ttf", size = 12, flags = "", shown = true }
        function label:GetFont() return self.path, self.size, self.flags end
        function label:SetFont(path, size, flags)
            if measuring and f.measureFontFailure then return false end
            self.path, self.size, self.flags = path, size, flags; return true
        end
        function label:SetText(text) self.text = text end
        function label:GetText() return self.text end
        function label:GetStringWidth()
            if measuring then
                f.measurements = f.measurements + 1
                if f.measureWidthFailure then error("measure width unavailable", 0) end
            end
            return textWidth(self.text, self.path, self.size, self.flags)
        end
        function label:SetWordWrap() if measuring and f.measureSetupFailure then error("measure setup unavailable", 0) end end
        function label:SetAllPoints() end
        function label:ClearAllPoints() end
        function label:SetPoint() end
        function label:Hide() self.shown = false end
        function label:Show() self.shown = true end
        function label:IsShown() return self.shown end
        return label
    end
    function f:widget(settings, defer)
        local widget = { settings = {}, width = 18, label = fontString(false) }
        for key, value in pairs(self.provider.defaults) do widget.settings[key] = value end
        -- FPS/CPU behavior checks retain their explicit non-memory configuration.
        widget.settings.diagnostics, widget.settings.usageMetric = false, "cpu"
        for key, value in pairs(settings or {}) do widget.settings[key] = value end
        widget.frame = { CreateFontString = function()
            f.fontCreations = f.fontCreations + 1
            if f.measureCreationFailure then error("measure allocation unavailable", 0) end
            return fontString(true)
        end }
        function widget:SetWidth(width)
            assert(type(width) == "number" and width > 0 and width < 10000)
            self.width, self.customWidth = width, width
        end
        function widget:SetText(text)
            if self.renderFailure then error("performance render unavailable", 0) end
            self.text = text; self.label:SetText(text)
            if not self.customWidth then self.width = math.max(18, self.label:GetStringWidth() + 8) end
        end
        function widget:Refresh() f.provider.update(self) end
        if self.provider.create then self.provider.create(widget) end
        if not defer then self.provider.update(widget) end
        return widget
    end
    function f:tooltip(widget)
        local tip = { lines = {} }
        function tip:AddLine(text) self.lines[#self.lines + 1] = { text } end
        function tip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = { left, right } end
        self.provider.tooltip(widget, tip); return tip
    end
    function f:fits(widget)
        assert(widget.width >= widget.label:GetStringWidth() + 8, "Current display exceeds its reserved width")
    end
    return f
end

check("factory Performance shows FPS without diagnostics until explicitly enabled", function()
    local f = fixture()
    equal(f.provider.id, "performance"); equal(f.provider.name, "Performance")
    equal(f.provider.defaults.display, "fps"); equal(f.provider.defaults.diagnostics, false)
    equal(f.provider.defaults.usageMetric, "memory")
    equal(f.provider.defaults.memoryInKB, false)
    local memorySetting
    for _, setting in ipairs(f.provider.settings) do if setting.key == "memoryInKB" then memorySetting = setting end end
    assert(memorySetting and memorySetting.type == "toggle")
    equal(memorySetting.label, "Always use kB for memory")
    equal(f.provider.interval, 0.5); equal(f.provider.defaultPlacement.alignment, "right")
    equal(f.provider.click, nil)
    local widget = f:widget({ diagnostics = f.provider.defaults.diagnostics, usageMetric = f.provider.defaults.usageMetric })
    equal(widget.text, "60 FPS")
    equal(f.memoryScans, 0); equal(#f.metricReads, 0); equal(f.profilerChecks, 0)
    widget.settings.diagnostics = true; widget:Refresh()
    assert(widget.text:find("Addons ", 1, true)); assert(widget.text:find("kB", 1, true))
    equal(f.memoryScans, 1); equal(#f.metricReads, 0); equal(f.profilerChecks, 0)
end)

check("FPS and estimated frame duration are explicit independent display choices", function()
    local f = fixture(); f.fps = 120
    equal(f:widget().text, "120 FPS")
    equal(f:widget({ display = "frameTime" }).text, "~8.3 ms")
    equal(f:widget({ display = "both" }).text, "120 FPS / ~8.3 ms")
    equal(f.forbidden, 0)
end)

check("zero FPS is real data while its derived frame duration remains unavailable", function()
    local f = fixture(); f.fps = 0
    equal(f:widget().text, "0 FPS")
    equal(f:widget({ display = "frameTime" }).text, "-- ms")
    equal(f:widget({ display = "both" }).text, "0 FPS / -- ms")
end)

check("unavailable and restricted framerates recover locally without fabricated zero", function()
    for _, value in ipairs({ "60", false, -1, math.huge, 0 / 0 }) do
        local f = fixture(); f.fps = value
        equal(f:widget().text, "-- FPS")
    end
    local f = fixture(); f.fps = f.secret
    local widget = f:widget({ display = "both" }); equal(widget.text, "-- FPS / -- ms")
    f.fps, f.fpsError = 60, true; f.provider.update(widget); equal(widget.text, "-- FPS / -- ms")
    f.fpsError = false; f.provider.update(widget); equal(widget.text, "60 FPS / ~16.7 ms")
    f.env.GetFramerate = nil; f.provider.update(widget); equal(widget.text, "-- FPS / -- ms")
end)

check("display caps preserve meaning and still fit the measured reservation", function()
    local f = fixture(); f.fps = 10000
    local fps = f:widget(); equal(fps.text, "9999+ FPS"); f:fits(fps)
    f.fps = 0.01
    local duration = f:widget({ display = "frameTime" }); equal(duration.text, ">9999 ms"); f:fits(duration)
end)

check("FPS fluctuations across digit boundaries never move a widget's reservation", function()
    local f = fixture(); f.fps = 11
    local widget = f:widget({ display = "both" }); local width, measurements = widget.width, f.measurements
    for _, value in ipairs({ 99, 100, 888, 10000, 0, 0.01, 60 }) do
        f.fps = value; f.provider.update(widget); equal(widget.width, width); f:fits(widget)
    end
    f.fps = f.secret; f.provider.update(widget); equal(widget.width, width); f:fits(widget)
    equal(f.measurements, measurements); equal(f.fontCreations, 1)
end)

check("the applied font and display selection invalidate sizing without creating new regions", function()
    local f = fixture(); local widget = f:widget()
    local firstWidth, firstMeasure = widget.width, widget.performanceMeasure
    widget.label:SetFont("Wide.ttf", 20, "BOLD"); f.provider.update(widget)
    assert(widget.width > firstWidth); f:fits(widget)
    local wider = widget.width
    widget.settings.display = "both"; f.provider.update(widget)
    assert(widget.width > wider); f:fits(widget)
    widget.label:SetFont("Default.ttf", 12, ""); widget.settings.display = "fps"; f.provider.update(widget)
    equal(widget.width, firstWidth); equal(widget.performanceMeasure, firstMeasure); equal(f.fontCreations, 1)
    equal(widget.performanceMeasure:IsShown(), false)
end)

check("unavailable text is measured using the actual face rather than guessed digit widths", function()
    local f = fixture(); local widget = f:widget({}, true)
    widget.label:SetFont("UnavailableWide.ttf", 12, ""); f.provider.update(widget)
    local width = widget.width
    f.fps = f.secret; f.provider.update(widget)
    equal(widget.width, width); f:fits(widget)
end)

check("sizing retains partial resources for retry and reset releases only transient layout state", function()
    local f = fixture(); f.measureSetupFailure = true
    local widget = f:widget({}, true)
    equal(pcall(f.provider.update, widget), false)
    local measure = assert(widget.performanceMeasure, "A created measuring region must be retained even when setup fails")
    equal(f.fontCreations, 1)
    f.provider.reset(widget, "update") -- The real host resets a failing callback.
    f.measureSetupFailure = false; f.provider.update(widget); f:fits(widget)
    equal(widget.performanceMeasure, measure); equal(f.fontCreations, 1)
    f.provider.reset(widget, "update")
    equal(widget.customWidth, nil); equal(measure:IsShown(), false)
    f.provider.update(widget); f:fits(widget); equal(widget.performanceMeasure, measure)
    equal(f.fontCreations, 1)
end)

check("default FPS updates never enumerate addons or read memory and CPU metrics", function()
    local f = fixture(); local widget = f:widget()
    for _ = 1, 30 do f.now = f.now + 0.5; f.provider.update(widget) end
    equal(f.memoryScans, 0); equal(f.memoryReads, 0); equal(f.addonEnumerations, 0)
    equal(f.profilerChecks, 0); equal(#f.metricReads, 0); equal(f.forbidden, 0)
end)

check("memory tooltip uses native kB, only fully loaded addons, and the largest five", function()
    local f = fixture(); local widget = f:widget({ usageMetric = "memory" }); local tip = f:tooltip(widget)
    equal(row(tip, "Addon Lua memory"), "2.2 MB")
    local top, reading = {}, false
    for _, value in ipairs(tip.lines) do
        if value[1] == "Largest addons by Lua memory" then reading = true
        elseif reading and value[2] then top[#top + 1] = value[1]
        elseif reading then break end
    end
    equal(table.concat(top, ","), "OtherHeavy,OtherSecond,OtherThird,OtherFourth,Menubar")
    equal(f.memoryScans, 1); equal(f.memoryReads, 9)
    equal(f.profilerChecks, 0); equal(#f.metricReads, 0)
    assert(tipText(tip):find("15 seconds", 1, true))
end)

check("duplicate hover snapshots share the expensive memory refresh for fifteen seconds", function()
    local f = fixture(); local first, second = f:widget({ usageMetric = "memory" }), f:widget({ usageMetric = "memory" })
    f:tooltip(first); f:tooltip(second); equal(f.memoryScans, 1)
    f.now = f.now + 14.9; f:tooltip(second); equal(f.memoryScans, 1)
    f.now = f.now + 0.2; f:tooltip(first); equal(f.memoryScans, 2)
    equal(f.memoryReads, 18); equal(f.forbidden, 0)
end)

check("unknown memory or native loaded state never turns an incomplete total into zero", function()
    for _, kind in ipairs({ "memory", "firstLoadedFlag", "secondLoadedFlag", "refresh" }) do
        local f = fixture()
        if kind == "memory" then f.addons[1].memory = f.secret
        elseif kind == "firstLoadedFlag" then f.addons[1].loadedOrLoading = f.secret
        elseif kind == "secondLoadedFlag" then f.addons[1].loaded = f.secret
        else f.memoryError = true end
        local widget = f:widget({ usageMetric = "memory" }); local tip = f:tooltip(widget)
        equal(row(tip, "Addon Lua memory"), "Unavailable", kind)
        assert(tipText(tip):find("complete total cannot be shown", 1, true))
        f.addons[1].memory, f.addons[1].loadedOrLoading, f.addons[1].loaded, f.memoryError = 128, true, true, false
        f.now = f.now + 15.1; equal(row(f:tooltip(widget), "Addon Lua memory"), "2.2 MB")
    end
end)

check("missing addon-memory or catalogue APIs are reported as unavailable rather than fabricated totals", function()
    for _, kind in ipairs({ "memoryRead", "memoryUpdate", "catalogue", "loaded", "catalogueError" }) do
        local f = fixture()
        if kind == "memoryRead" then f.env.GetAddOnMemoryUsage = nil
        elseif kind == "memoryUpdate" then f.env.UpdateAddOnMemoryUsage = nil
        elseif kind == "catalogue" then f.env.C_AddOns = nil
        elseif kind == "loaded" then f.env.C_AddOns.IsAddOnLoaded = nil
        else f.catalogueError = true end
        equal(row(f:tooltip(f:widget({ usageMetric = "memory" })), "Addon Lua memory"), "Unavailable", kind)
    end
end)

check("diagnostics append only the summed project recent CPU and preserve native metric semantics", function()
    local f = fixture(); local widget = f:widget({ diagnostics = true })
    equal(widget.text, "60 FPS | Addons 1.50 ms")
    equal(f.memoryScans, 0); equal(f.memoryReads, 0)
    local seenNames, seenMetrics = {}, {}
    for _, read in ipairs(f.metricReads) do seenNames[read.name] = true; seenMetrics[read.metric] = true end
    for _, name in ipairs({ "Menubar", "Menubar_Performance", "Menubar_Time", "ForTheHoard", "ShutUpThrall" }) do assert(seenNames[name], name) end
    equal(seenNames.OtherHeavy, nil); equal(seenNames.Dormant, nil); equal(seenNames.Loading, nil)
    for _, metric in ipairs({ 0, 1, 4, 6, 7 }) do assert(seenMetrics[metric], "Each verified native metric must be queried, including enum zero") end
    local tip = f:tooltip(widget)
    equal(row(tip, "Approx. recent CPU / tick"), "1.50 ms")
    equal(row(tip, "Approx. session CPU / tick"), "2.00 ms")
    assert(tipText(tip):find("last 60 ticks", 1, true)); assert(tipText(tip):find("peaks are never summed", 1, true))
    local peaks = 0
    for _, value in ipairs(tip.lines) do
        if value[1] == "  Peak / ticks >5 / >10 ms" then
            peaks = peaks + 1
            assert(not value[2]:find("25.00 ms", 1, true), "Per-addon peaks must never be added into a concurrent peak")
        end
    end
    equal(peaks, 5); equal(f.forbidden, 0)
end)

check("CPU snapshots are shared across duplicate widgets for one second without refreshing memory", function()
    local f = fixture(); local first = f:widget({ diagnostics = true })
    local reads, checks = #f.metricReads, f.profilerChecks
    local second = f:widget({ diagnostics = true })
    equal(#f.metricReads, reads); equal(f.profilerChecks, checks)
    f.now = f.now + 0.5; f.provider.update(first); equal(#f.metricReads, reads)
    f.now = f.now + 0.6; f.provider.update(second); equal(#f.metricReads, reads * 2)
    equal(f.memoryScans, 0); equal(f.memoryReads, 0)
    first.settings.diagnostics = false; second.settings.diagnostics = false
    f.now = f.now + 2; f.provider.update(first); f.provider.update(second)
    equal(#f.metricReads, reads * 2); equal(f.profilerChecks, checks * 2)
end)

check("disabled or unreadable native profiling is never enabled and never reads CPU metrics", function()
    for _, state in ipairs({ "disabled", "restricted", "error", "missing" }) do
        local f = fixture()
        if state == "disabled" then f.profilingEnabled = false
        elseif state == "restricted" then f.profilingEnabled = f.secret
        elseif state == "error" then f.profilerError = true
        else f.env.C_AddOnProfiler = nil end
        local widget = f:widget({ diagnostics = true })
        equal(widget.text, "60 FPS | Addons -- ms", state)
        local tip = f:tooltip(widget)
        equal(row(tip, "Approx. recent CPU / tick"), "-- ms")
        assert(tipText(tip):find("CPU profiling is unavailable or disabled", 1, true))
        equal(#f.metricReads, 0); equal(f.forbidden, 0)
    end
end)

check("restricted metrics and unknown own loaded state keep aggregate CPU unavailable", function()
    for _, kind in ipairs({ "metric", "error", "loaded" }) do
        local f = fixture()
        if kind == "metric" then f.metrics.Menubar[1] = f.secret
        elseif kind == "error" then f.metricError = true
        else f.addons[1].loaded = f.secret end
        local widget = f:widget({ diagnostics = true })
        equal(widget.text, "60 FPS | Addons -- ms", kind)
        f.metrics.Menubar[1], f.metricError, f.addons[1].loaded = 0.1, false, true
        f.now = f.now + 1.1; f.provider.update(widget); equal(widget.text, "60 FPS | Addons 1.50 ms")
    end
end)

check("unknown enum values are rejected before native calls and count metrics require whole numbers", function()
    local f = fixture(); f.env.Enum.AddOnProfilerMetric.RecentAverageTime = f.secret
    local widget = f:widget({ diagnostics = true }); equal(widget.text, "60 FPS | Addons -- ms")
    for _, read in ipairs(f.metricReads) do assert(read.metric ~= 1, "Restricted enum must never be passed to the profiler") end
    f.env.Enum.AddOnProfilerMetric.RecentAverageTime = 1; f.metrics.Menubar[6] = 1.5
    f.now = f.now + 1.1; f.provider.update(widget)
    local tip = f:tooltip(widget); local index
    for position, value in ipairs(tip.lines) do
        if value[1] == "Menubar" and value[2] and value[2]:find("recent", 1, true) then index = position; break end
    end
    assert(index); equal(tip.lines[index + 1][2], "3.00 ms / -- / 0")
end)

check("CPU field reservation includes unavailable and capped values without moving neighbours", function()
    local f = fixture(); local widget = f:widget({ diagnostics = true, display = "both" })
    local width, measurements = widget.width, f.measurements
    for _, value in ipairs({ 0, 123, 10000, f.secret }) do
        for _, name in ipairs({ "Menubar", "Menubar_Performance", "Menubar_Time", "ForTheHoard", "ShutUpThrall" }) do f.metrics[name][1] = value end
        f.now = f.now + 1.1; f.provider.update(widget); equal(widget.width, width); f:fits(widget)
    end
    equal(f.measurements, measurements); equal(f.fontCreations, 1)
end)

check("unreadable or reversed clocks never reuse stale measurement snapshots", function()
    local f = fixture(); local widget = f:widget({ diagnostics = true })
    f:tooltip(widget); local reads = #f.metricReads
    f.now = 99; f.provider.update(widget); f:tooltip(widget); equal(#f.metricReads, reads * 2)
    f.now = f.secret; f.provider.update(widget); equal(widget.text, "60 FPS | Addons -- ms")
    equal(row(f:tooltip(widget), "Approx. addon CPU / tick"), "-- ms")
    equal(f.memoryScans, 0)
    widget.settings.usageMetric = "memory"
    equal(row(f:tooltip(widget), "Addon Lua memory"), "Unavailable")
end)

check("memory monitoring shows only loaded project Lua memory and never queries the CPU profiler", function()
    local f = fixture(); local widget = f:widget({ diagnostics = true, usageMetric = "memory" })
    equal(widget.text, "60 FPS | Addons 248.0 kB")
    equal(f.memoryScans, 1); equal(f.profilerChecks, 0); equal(#f.metricReads, 0)
    local tip = f:tooltip(widget)
    equal(row(tip, "Addon Lua memory"), "2.2 MB")
    equal(row(tip, "Our addons Lua memory"), "248.0 kB")
    equal(row(tip, "Approx. recent CPU / tick"), nil)
    equal(row(tip, "  Peak / ticks >5 / >10 ms"), nil)
    equal(row(tip, "ForTheHoard"), "16.0 kB")
    equal(row(tip, "ShutUpThrall"), "8.0 kB")
    equal(f.profilerChecks, 0); equal(#f.metricReads, 0); equal(f.forbidden, 0)
end)

check("memory mode works without CPU profiling support or permission", function()
    for _, mode in ipairs({ "missing", "disabled", "restricted" }) do
        local f = fixture()
        if mode == "missing" then f.env.C_AddOnProfiler = nil
        elseif mode == "disabled" then f.profilingEnabled = false
        else f.profilingEnabled = f.secret end
        local widget = f:widget({ diagnostics = true, usageMetric = "memory" })
        equal(widget.text, "60 FPS | Addons 248.0 kB")
        equal(row(f:tooltip(widget), "Our addons Lua memory"), "248.0 kB")
        equal(f.profilerChecks, 0); equal(#f.metricReads, 0); equal(f.forbidden, 0)
    end
end)

check("unrelated unknown memory or loaded state invalidates the global total but preserves our memory total", function()
    for _, field in ipairs({ "memory", "loaded" }) do
        local f = fixture(); f.addons[6][field] = f.secret
        local widget = f:widget({ diagnostics = true, usageMetric = "memory" })
        equal(widget.text, "60 FPS | Addons 248.0 kB", field)
        local tip = f:tooltip(widget)
        equal(row(tip, "Addon Lua memory"), "Unavailable")
        equal(row(tip, "Our addons Lua memory"), "248.0 kB")
    end
end)

check("our unknown memory stays unavailable while a readable zero remains real data", function()
    for _, field in ipairs({ "memory", "loaded" }) do
        local f = fixture(); f.addons[1][field] = f.secret
        local widget = f:widget({ diagnostics = true, usageMetric = "memory" })
        equal(widget.text, "60 FPS | Addons -- kB", field)
        equal(row(f:tooltip(widget), "Our addons Lua memory"), "Unavailable")
    end
    local f = fixture()
    for index = 1, 5 do f.addons[index].memory = 0 end
    local widget = f:widget({ diagnostics = true, usageMetric = "memory" })
    equal(widget.text, "60 FPS | Addons 0.0 B")
    equal(row(f:tooltip(widget), "Our addons Lua memory"), "0.0 B")
end)

check("mixed hover modes keep their independent CPU and memory refresh cadences", function()
    local f = fixture(); local memory = f:widget({ diagnostics = true, usageMetric = "memory" })
    equal(f.memoryScans, 1)
    local cpu = f:widget({ diagnostics = true, usageMetric = "cpu" })
    equal(f.memoryScans, 1); local cpuReads, checks = #f.metricReads, f.profilerChecks
    f:tooltip(memory); f:tooltip(cpu); equal(f.memoryScans, 1)
    equal(#f.metricReads, cpuReads + 4); equal(f.profilerChecks, checks)
    cpuReads = #f.metricReads
    f.now = f.now + 14.9; f.provider.update(memory); equal(f.memoryScans, 1)
    equal(#f.metricReads, cpuReads); equal(f.profilerChecks, checks)
    f.now = f.now + 0.2; f.provider.update(memory); equal(f.memoryScans, 2)
    f:tooltip(memory); f.provider.update(cpu); equal(f.memoryScans, 2)
    assert(#f.metricReads > cpuReads); equal(f.forbidden, 0)
end)

check("a memory selection with monitoring off does not add bar sampling or change FPS choices", function()
    local f = fixture(); local widget = f:widget({ diagnostics = false, usageMetric = "memory", display = "frameTime" })
    equal(widget.text, "~16.7 ms")
    for _ = 1, 10 do f.now = f.now + 1; f.provider.update(widget) end
    equal(f.memoryScans, 0); equal(f.profilerChecks, 0); equal(#f.metricReads, 0)
    f:tooltip(widget); equal(f.memoryScans, 1); equal(f.profilerChecks, 0)
end)

check("missing, restricted or invalid metric choices safely use CPU without overwriting settings", function()
    for _, kind in ipairs({ "missing", "restricted", "invalid", "number" }) do
        local f = fixture(); local widget = f:widget({ diagnostics = true, display = "frameTime" }, true)
        local value
        if kind == "restricted" then value = f.secret
        elseif kind == "invalid" then value = "disk"
        elseif kind == "number" then value = 1 end
        widget.settings.usageMetric = value
        f.provider.update(widget)
        equal(widget.text, "~16.7 ms | Addons 1.50 ms", kind)
        assert(rawequal(widget.settings.usageMetric, value), "Fallback must not rewrite the saved choice")
        equal(widget.settings.display, "frameTime"); equal(f.memoryScans, 0)
    end
end)

check("memory units, unknown values and caps share a stable reservation that reuses the measuring region", function()
    local f = fixture(); local widget = f:widget({ diagnostics = true, display = "both" })
    local measure = widget.performanceMeasure
    widget.settings.usageMetric = "memory"; f.provider.update(widget)
    local width, measurements = widget.width, f.measurements
    for _, value in ipairs({ 0, 888, 100000000, f.secret }) do
        for index = 1, 5 do f.addons[index].memory = value end
        f.now = f.now + 15.1; f.provider.update(widget)
        equal(widget.width, width); f:fits(widget)
        if value == 100000000 then assert(widget.text:find("Addons 476.8 GB", 1, true)) end
    end
    equal(widget.performanceMeasure, measure); equal(f.fontCreations, 1); equal(f.measurements, measurements)
    widget.settings.usageMetric = "cpu"; f.provider.update(widget)
    assert(widget.text:find("Addons 1.50 ms", 1, true)); f:fits(widget)
    equal(widget.performanceMeasure, measure); equal(f.fontCreations, 1)
end)

check("CPU selection ranks all loaded addons by recent CPU even when project monitoring is off", function()
    local f = fixture()
    f.metrics.OtherSecond[1], f.metrics.OtherThird[1], f.metrics.OtherFourth[1] = 3, 2, 1
    local widget = f:widget({ usageMetric = "cpu", diagnostics = false })
    equal(#f.metricReads, 0)
    local tip = f:tooltip(widget)
    equal(row(tip, "Approx. addon CPU / tick"), "7.75 ms")
    local top, reading = {}, false
    for _, value in ipairs(tip.lines) do
        if value[1] == "Largest addons by recent CPU" then reading = true
        elseif reading and value[2] then
            top[#top + 1] = value[1]
            assert(value[2]:find("ms", 1, true))
        elseif reading then break end
    end
    equal(table.concat(top, ","), "OtherSecond,OtherThird,OtherFourth,ShutUpThrall,ForTheHoard")
    equal(row(tip, "Our addons"), nil)
    assert(not tipText(tip):find("kB", 1, true))
    assert(not tipText(tip):find("Lua memory", 1, true))
    assert(tipText(tip):find("last 60 ticks", 1, true))
    equal(f.memoryScans, 0); equal(f.memoryReads, 0); equal(f.forbidden, 0)
    for _, read in ipairs(f.metricReads) do
        assert(read.name ~= "Dormant" and read.name ~= "Loading")
        if read.name:find("Other", 1, true) then equal(read.metric, 1) end
    end
end)

check("CPU hover expands one shared sample without repeating project reads or widening future bar ticks", function()
    local f = fixture(); local first = f:widget({ diagnostics = true })
    equal(#f.metricReads, 25)
    local tip = f:tooltip(first); equal(#f.metricReads, 29)
    equal(row(tip, "Approx. recent CPU / tick"), "1.50 ms")
    equal(row(tip, "Approx. addon CPU / tick"), "2.50 ms")
    assert(not tipText(tip):find("kB", 1, true))
    local second = f:widget({ diagnostics = true })
    for _ = 1, 20 do f:tooltip(first); f:tooltip(second); f.provider.update(first) end
    equal(#f.metricReads, 29); equal(f.profilerChecks, 1)
    f.now = f.now + 1.1; f.provider.update(first)
    equal(#f.metricReads, 54); equal(f.profilerChecks, 2)
    for index = 30, 54 do assert(not f.metricReads[index].name:find("Other", 1, true)) end
    f:tooltip(second); equal(#f.metricReads, 58); equal(f.profilerChecks, 2)
    equal(f.memoryScans, 0); equal(f.memoryReads, 0)
end)

check("unknown unrelated CPU or loaded state invalidates only the global aggregate and can recover", function()
    for _, kind in ipairs({ "restricted", "invalid", "throwing", "loaded" }) do
        local f = fixture()
        local nativeRead = f.env.C_AddOnProfiler.GetAddOnMetric
        if kind == "restricted" then f.metrics.OtherHeavy[1] = f.secret
        elseif kind == "invalid" then f.metrics.OtherHeavy[1] = -1
        elseif kind == "loaded" then f.addons[6].loaded = f.secret
        else f.env.C_AddOnProfiler.GetAddOnMetric = function(name, metric)
            if name == "OtherHeavy" then error("one addon metric is unavailable", 0) end
            return nativeRead(name, metric)
        end end
        local widget = f:widget({ diagnostics = true })
        equal(widget.text, "60 FPS | Addons 1.50 ms", kind)
        local tip = f:tooltip(widget)
        equal(row(tip, "Approx. addon CPU / tick"), "-- ms", kind)
        equal(row(tip, "Approx. recent CPU / tick"), "1.50 ms", kind)
        assert(tipText(tip):find("Largest readable addons by recent CPU", 1, true))
        equal(row(tip, "OtherHeavy"), nil)
        f.metrics.OtherHeavy[1], f.addons[6].loaded = 0.25, true
        f.env.C_AddOnProfiler.GetAddOnMetric = nativeRead
        f.now = f.now + 1.1
        equal(row(f:tooltip(widget), "Approx. addon CPU / tick"), "2.50 ms", kind)
        equal(f.memoryScans, 0); equal(f.forbidden, 0)
    end
end)

check("CPU zeroes remain measurable and equal top-five readings have deterministic name ordering", function()
    local f = fixture()
    for _, values in pairs(f.metrics) do values[1] = 0 end
    local widget = f:widget({ diagnostics = true })
    equal(widget.text, "60 FPS | Addons 0.00 ms")
    local tip = f:tooltip(widget)
    equal(row(tip, "Approx. addon CPU / tick"), "0.00 ms")
    equal(row(tip, "Approx. recent CPU / tick"), "0.00 ms")
    local names, reading = {}, false
    for _, value in ipairs(tip.lines) do
        if value[1] == "Largest addons by recent CPU" then reading = true
        elseif reading and value[2] then names[#names + 1] = value[1]
        elseif reading then break end
    end
    equal(table.concat(names, ","), "ForTheHoard,Menubar,Menubar_Performance,Menubar_Time,OtherFourth")
    f.metrics.OtherHeavy[1], f.metrics.OtherSecond[1] = 1e308, 1e308
    f.now = f.now + 1.1; tip = f:tooltip(widget)
    equal(row(tip, "Approx. addon CPU / tick"), "-- ms")
    equal(row(tip, "Approx. recent CPU / tick"), "0.00 ms")
    equal(row(tip, "OtherHeavy"), ">9999 ms")
end)

check("CPU mode with profiling disabled stays CPU-only instead of silently reading memory", function()
    local f = fixture(); f.profilingEnabled = false
    local widget = f:widget({ usageMetric = "cpu", diagnostics = false })
    local tip = f:tooltip(widget)
    equal(row(tip, "Approx. addon CPU / tick"), "-- ms")
    assert(tipText(tip):find("CPU profiling is unavailable or disabled", 1, true))
    assert(not tipText(tip):find("kB", 1, true))
    equal(f.memoryScans, 0); equal(f.memoryReads, 0); equal(#f.metricReads, 0); equal(f.forbidden, 0)
    f.profilingEnabled = true; f.now = f.now + 1.1
    equal(row(f:tooltip(widget), "Approx. addon CPU / tick"), "2.50 ms")
end)

check("metric switching changes the entire tooltip without resetting the other sampler", function()
    local f = fixture(); local widget = f:widget({ diagnostics = true, usageMetric = "memory" })
    local memoryTip = f:tooltip(widget)
    equal(row(memoryTip, "Addon Lua memory"), "2.2 MB")
    equal(#f.metricReads, 0)
    widget.settings.usageMetric = "cpu"; f.provider.update(widget)
    local cpuTip = f:tooltip(widget); local cpuReads = #f.metricReads
    assert(not tipText(cpuTip):find("kB", 1, true)); equal(f.memoryScans, 1)
    widget.settings.usageMetric = "memory"; f.provider.update(widget); memoryTip = f:tooltip(widget)
    equal(row(memoryTip, "Addon Lua memory"), "2.2 MB")
    equal(row(memoryTip, "Approx. addon CPU / tick"), nil)
    equal(#f.metricReads, cpuReads); equal(f.memoryScans, 1)
    widget.settings.usageMetric = "cpu"; f.provider.update(widget); f:tooltip(widget)
    equal(#f.metricReads, cpuReads); equal(f.memoryScans, 1); equal(f.forbidden, 0)
end)

check("automatic and forced units format every memory section independently from one raw snapshot", function()
    local f = fixture()
    local values = { 128, 0.5, 2048, 16, 8, 65536, 512, 256, 192 }
    for index, value in ipairs(values) do f.addons[index].memory = value end
    local automatic = f:widget({ diagnostics = true, usageMetric = "memory" })
    local forced = f:widget({ diagnostics = true, usageMetric = "memory", memoryInKB = true })
    equal(automatic.text, "60 FPS | Addons 2.1 MB")
    equal(forced.text, "60 FPS | Addons 2200.5 kB")
    local autoTip, forcedTip = f:tooltip(automatic), f:tooltip(forced)
    equal(row(autoTip, "Addon Lua memory"), "67.1 MB")
    equal(row(forcedTip, "Addon Lua memory"), "68696.5 kB")
    equal(row(autoTip, "Our addons Lua memory"), "2.1 MB")
    equal(row(forcedTip, "Our addons Lua memory"), "2200.5 kB")
    local expected = {
        { "OtherHeavy", "64.0 MB", "65536.0 kB" }, { "Menubar_Time", "2.0 MB", "2048.0 kB" },
        { "OtherSecond", "512.0 kB", "512.0 kB" }, { "OtherThird", "256.0 kB", "256.0 kB" },
        { "OtherFourth", "192.0 kB", "192.0 kB" }, { "Menubar", "128.0 kB", "128.0 kB" },
        { "Menubar_Performance", "512.0 B", "0.5 kB" }, { "ForTheHoard", "16.0 kB", "16.0 kB" },
        { "ShutUpThrall", "8.0 kB", "8.0 kB" },
    }
    for _, value in ipairs(expected) do
        equal(row(autoTip, value[1]), value[2]); equal(row(forcedTip, value[1]), value[3])
    end
    local function largest(tip)
        local names, reading = {}, false
        for _, value in ipairs(tip.lines) do
            if value[1] == "Largest addons by Lua memory" then reading = true
            elseif reading and value[2] then names[#names + 1] = value[1]
            elseif reading then break end
        end
        return table.concat(names, ",")
    end
    equal(largest(autoTip), "OtherHeavy,Menubar_Time,OtherSecond,OtherThird,OtherFourth")
    equal(largest(forcedTip), largest(autoTip))
    equal(f.memoryScans, 1); equal(f.memoryReads, 9); equal(#f.metricReads, 0); equal(f.forbidden, 0)
end)

check("memory units promote rounded boundaries and retain bounded one-decimal caps", function()
    local cases = {
        { 0, "0.0 B", "0.0 kB" }, { 0.5, "512.0 B", "0.5 kB" },
        { 0.99994, "1023.9 B", "1.0 kB" }, { 0.99996, "1.0 kB", "1.0 kB" },
        { 1, "1.0 kB", "1.0 kB" }, { 1023.94, "1023.9 kB", "1023.9 kB" },
        { 1023.96, "1.0 MB", "1024.0 kB" }, { 1024, "1.0 MB", "1024.0 kB" },
        { 1048576, "1.0 GB", "1048576.0 kB" }, { 1073741824, "1.0 TB", "99999999.9+ kB" },
        { 99999999.94, "95.4 GB", "99999999.9 kB" }, { 99999999.96, "95.4 GB", "99999999.9+ kB" },
        { 9999.96 * 1073741824, "9999.9+ TB", "99999999.9+ kB" },
        { 1e308, "9999.9+ TB", "99999999.9+ kB" },
    }
    for _, value in ipairs(cases) do
        local f = fixture()
        for _, addon in ipairs(f.addons) do addon.memory = 0 end
        f.addons[1].memory = value[1]
        local automatic = f:widget({ diagnostics = true, usageMetric = "memory" })
        local forced = f:widget({ diagnostics = true, usageMetric = "memory", memoryInKB = true })
        equal(automatic.text, "60 FPS | Addons " .. value[2])
        equal(forced.text, "60 FPS | Addons " .. value[3])
        equal(row(f:tooltip(automatic), "Menubar"), value[2])
        equal(row(f:tooltip(forced), "Menubar"), value[3])
        f:fits(automatic); f:fits(forced); equal(f.memoryScans, 1)
    end
end)

check("invalid memory stays unavailable in both unit modes without formatting restricted values", function()
    for _, kind in ipairs({ "restricted", "string", "false", "negative", "nan", "infinite" }) do
        local f = fixture(); local value
        if kind == "restricted" then value = f.secret
        elseif kind == "string" then value = "64"
        elseif kind == "false" then value = false
        elseif kind == "negative" then value = -1
        elseif kind == "nan" then value = 0 / 0
        else value = math.huge end
        f.addons[1].memory = value
        for _, forced in ipairs({ false, true }) do
            local widget = f:widget({ diagnostics = true, usageMetric = "memory", memoryInKB = forced })
            equal(widget.text, "60 FPS | Addons -- kB", kind)
            local tip = f:tooltip(widget)
            equal(row(tip, "Addon Lua memory"), "Unavailable", kind)
            equal(row(tip, "Our addons Lua memory"), "Unavailable", kind)
            equal(row(tip, "Menubar"), "Unavailable", kind)
            f:fits(widget)
        end
        equal(f.memoryScans, 1); equal(f.forbidden, 0)
    end
end)

check("only a public true memory-unit preference forces kB without rewriting malformed saved settings", function()
    for _, kind in ipairs({ "missing", "restricted", "string", "number" }) do
        local f = fixture()
        for _, addon in ipairs(f.addons) do addon.memory = 0 end
        f.addons[1].memory = 0.5
        local value
        if kind == "restricted" then value = f.secret
        elseif kind == "string" then value = "true"
        elseif kind == "number" then value = 1 end
        local widget = f:widget({ diagnostics = true, usageMetric = "memory" }, true)
        widget.settings.memoryInKB = value; f.provider.update(widget)
        equal(widget.text, "60 FPS | Addons 512.0 B", kind)
        assert(rawequal(widget.settings.memoryInKB, value), "Display fallback must preserve saved settings")
    end
end)

check("format changes reuse the fifteen-second memory snapshot and leave CPU timing and FPS untouched", function()
    local f = fixture(); local widget = f:widget({ diagnostics = true, usageMetric = "memory", display = "both" })
    local memoryReads, scans = f.memoryReads, f.memoryScans
    f.addons[1].memory = 1024; f.now = f.now + 14.9
    widget.settings.memoryInKB = true; f.provider.update(widget); f:tooltip(widget)
    equal(widget.text, "60 FPS / ~16.7 ms | Addons 248.0 kB")
    widget.settings.memoryInKB = false; f.provider.update(widget)
    equal(f.memoryReads, memoryReads); equal(f.memoryScans, scans)
    f.now = f.now + 0.2; f.provider.update(widget)
    equal(widget.text, "60 FPS / ~16.7 ms | Addons 1.1 MB")
    equal(f.memoryScans, scans + 1); equal(f.memoryReads, memoryReads + 9)
    local cpu = f:widget({ diagnostics = true, memoryInKB = true, display = "both" })
    local cpuText, cpuReads, checks = cpu.text, #f.metricReads, f.profilerChecks
    cpu.settings.memoryInKB = false; f.provider.update(cpu); f:tooltip(cpu)
    equal(cpu.text, cpuText); assert(cpu.text:find("Addons 1.50 ms", 1, true))
    equal(#f.metricReads, cpuReads + 4); equal(f.profilerChecks, checks)
    equal(f.memoryScans, scans + 1); equal(f.forbidden, 0)
end)

check("auto and forced memory width reservations change once per preference and retain the measuring region", function()
    local f = fixture()
    for _, addon in ipairs(f.addons) do addon.memory = 0 end
    local widget = f:widget({ diagnostics = true, usageMetric = "memory", display = "both" })
    local measure, autoWidth, measurements = widget.performanceMeasure, widget.width, f.measurements
    for _, value in ipairs({ 0.5, 1, 1024, 1048576, 1073741824, 1e308, f.secret }) do
        f.addons[1].memory = value; f.now = f.now + 15.1; f.provider.update(widget)
        equal(widget.width, autoWidth); f:fits(widget)
    end
    equal(f.measurements, measurements)
    local scans = f.memoryScans
    widget.settings.memoryInKB = true; f.provider.update(widget)
    local forcedWidth, forcedMeasurements = widget.width, f.measurements
    assert(forcedWidth > autoWidth and forcedMeasurements > measurements)
    equal(f.memoryScans, scans)
    for _, value in ipairs({ 0, 0.5, 2048, 99999999.94, 99999999.96, f.secret }) do
        f.addons[1].memory = value; f.now = f.now + 15.1; f.provider.update(widget)
        equal(widget.width, forcedWidth); f:fits(widget)
    end
    equal(f.measurements, forcedMeasurements)
    widget.settings.memoryInKB = false; f.provider.update(widget)
    equal(widget.width, autoWidth); assert(f.measurements > forcedMeasurements)
    equal(widget.performanceMeasure, measure); equal(f.fontCreations, 1)
end)

print(passed .. " Performance public-contract tests passed")
