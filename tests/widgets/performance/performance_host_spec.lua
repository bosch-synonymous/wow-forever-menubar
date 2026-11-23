local sourceDirectory = dofile((REPO_ROOT or ".") .. "/tests/source_paths.lua")
-- Actual host lifecycle and layout; native rendering/profiler behavior still
-- needs an in-client check. No third-party addon implementation is used here.
local root = REPO_ROOT or "."
local core = MENUBAR_CORE_ROOT or root
local file = io.open(core .. "/tests/wow_stub.lua", "rb")
if not file then print("SKIP Performance host integration: restore Core in this clone or supply MENUBAR_CORE_ROOT."); return end
file:close()
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function loadAddon(repository, addon)
    local namespace = {}
    for line in io.lines(sourceDirectory(repository, addon) .. "/" .. addon .. ".toc") do
        local name = line:match("^%s*(.-)%s*$")
        if name:match("%.lua$") then assert(loadfile(sourceDirectory(repository, addon) .. "/" .. name))(addon, namespace) end
    end
end
local function fixture(options)
    options = options or {}
    local Stub = dofile(core .. "/tests/wow_stub.lua"); Stub.Install()
    local f = { Stub = Stub, fps = 99, now = 100, recent = 0.1, metricReads = 0, profilerChecks = 0,
        memoryScans = 0, memory = 64, shift = false, profilerEnabled = true }
    MenubarDB = nil
    f.secret = setmetatable({}, { __tostring = function() error("Restricted FPS formatted", 0) end })
    issecretvalue = function(value) return rawequal(value, f.secret) end
    IsShiftKeyDown = function() return f.shift end
    GetTime = function() return f.now end
    GetFramerate = function() return f.fps end
    local Region = getmetatable(UIParent)
    local nativeSetTexture, nativeCreateTexture = Region.SetTexture, Region.CreateTexture
    function Region:SetTexture(path, ...)
        if type(path) == "string" and path:find("Menubar_Performance\\Media\\performance.tga", 1, true) then
            if options.iconFailure == "false" then return false end
            if options.iconFailure == "nil" then return nil end
            if options.iconFailure == "throw" then error("Performance icon setup failed", 0) end
        end
        return nativeSetTexture(self, path, ...)
    end
    function Region:CreateTexture(name, layer, template, level)
        if options.iconFailure == "creation" and layer == "ARTWORK" and level == 1
            and Menubar and Menubar.bars and self:GetParent() == Menubar.bars.top then
            error("Performance icon allocation failed", 0)
        end
        return nativeCreateTexture(self, name, layer, template, level)
    end
    local originalWidth = Region.GetStringWidth
    function Region:GetStringWidth()
        if self.kind ~= "FontString" then return originalWidth(self) end
        local units = 0
        for char in self:GetText():gmatch(".") do units = units + (char == "1" and 3 or char == "8" and 9 or char == "." and 2 or char == " " and 3 or 7) end
        return units * (self.fontSize or 12) / 12 * (self.font == "Fonts\\MORPHEUS.TTF" and 1.4 or 1)
    end
    local names = { "Menubar", "Menubar_Performance", "Menubar_Time", "ForTheHoard", "ShutUpThrall", "OtherAddon" }
    C_AddOns = {
        GetNumAddOns = function() return #names end,
        GetAddOnInfo = function(index) return names[index], "Native tuple title", "Notes", true end,
        IsAddOnLoaded = function() return true, true end,
    }
    UpdateAddOnMemoryUsage = function() f.memoryScans = f.memoryScans + 1 end
    GetAddOnMemoryUsage = function() return f.memory end
    Enum = { AddOnProfilerMetric = { SessionAverageTime = 0, RecentAverageTime = 1, PeakTime = 4,
        CountTimeOver5Ms = 6, CountTimeOver10Ms = 7 } }
    C_AddOnProfiler = {
        IsEnabled = function() f.profilerChecks = f.profilerChecks + 1; return f.profilerEnabled end,
        GetAddOnMetric = function(_, metric)
            f.metricReads = f.metricReads + 1
            if metric == 1 then return f.recent end
            if metric == 0 then return 0.2 end
            if metric == 4 then return 4 end
            return 2
        end,
        ResetMetrics = function() error("Never reset native profiler counters", 0) end,
    }
    SetCVar = function() error("Do not enable profiling through CVars", 0) end
    ResetCPUUsage = function() error("Do not reset native profiling", 0) end
    loadAddon(core, "Menubar")
    if MENUBAR_TIME_ROOT then loadAddon(MENUBAR_TIME_ROOT, "Menubar_Time")
    else Menubar:RegisterWidgetType({ id = "time", name = "Time fixture", defaults = {},
        defaultPlacement = { bar = "top", alignment = "right" }, update = function(widget) widget:SetText("12:34") end }) end
    loadAddon(root, "Menubar_Performance")
    -- Existing opt-outs must retain pure FPS and independent CPU-mode coverage.
    local db = MenubarModel.Initialize(nil, "Tester - Test Realm")
    MenubarModel.AddWidget(db, "Tester - Test Realm", "performance", { diagnostics = false, usageMetric = "cpu" })
    MenubarDB = db
    Menubar:Start(); f.host = Menubar
    function f:find(kind)
        for _, widget in pairs(self.host.runtime) do if widget.instance.type == kind then return widget end end
    end
    f.widget, f.clock = assert(f:find("performance")), assert(f:find("time"))
    f.widget.instance.order, f.clock.instance.order = 1, 2; f.host:Layout()
    if options.iconFailure ~= "throw" and options.iconFailure ~= "creation" then assert(not f.widget.failed, tostring(f.widget.failed)) end
    function f:tick(delta)
        self.now = self.now + (delta or 0.5)
        self.host.eventFrame.scripts.OnUpdate(self.host.eventFrame, delta or 0.5)
        assert(not self.widget.failed, tostring(self.widget.failed))
    end
    function f:position(widget) return widget.frame.points[1][4] end
    function f:fits()
        local icon = self.widget.performanceIcon
        local space = icon and icon:IsShown() and 18 or 0
        assert(self.widget.width >= self.widget.label:GetStringWidth() + 8 + space)
    end
    function f:pickUsage(widget, option)
        self.host.UI:OpenWidget(widget.id)
        for _, control in ipairs(self.host.UI.window.controls) do
            if control.caption == "Addon usage" then
                equal(control.template, "WowStyle1DropdownTemplate")
                control:OpenMenu()
                self.Stub.MenuItem(self.Stub.menus[#self.Stub.menus], option).callback()
                return
            end
        end
        error("Missing native Addon usage selector")
    end
    function f:memoryUnits(widget, alwaysKB)
        self.host.UI:OpenWidget(widget.id)
        for _, control in ipairs(self.host.UI.window.controls) do
            if control.caption == "Always use kB for memory" then
                equal(control.template, "UICheckButtonTemplate")
                if control:GetChecked() ~= alwaysKB then control:Click() end
                equal(widget.settings.memoryInKB, alwaysKB)
                assert(not widget.failed, tostring(widget.failed))
                return
            end
        end
        error("Missing native memory-unit checkbox")
    end
    return f
end

check("FPS ticks keep the real clock and Performance layout fixed without native addon scans", function()
    local f = fixture(); local widget = f.widget
    local width, position, clockPosition = widget.width, f:position(widget), f:position(f.clock)
    for _, value in ipairs({ 100, 11, 888, 10000, 0, f.secret, 60 }) do
        f.fps = value; f:tick()
        equal(widget.width, width); equal(f:position(widget), position); equal(f:position(f.clock), clockPosition); f:fits()
    end
    equal(f.memoryScans, 0); equal(f.metricReads, 0); equal(f.profilerChecks, 0)
end)

check("font, format and CPU suffix changes resize once and retain stable adjacent placement", function()
    local f = fixture(); local widget = f.widget; local original = widget.performanceMeasure
    f.host:GetProfile().font, f.host:GetProfile().fontSize = "Fonts\\MORPHEUS.TTF", 20
    widget.settings.display, widget.settings.diagnostics = "both", true
    f.host:Rebuild(); f:tick()
    equal(widget.performanceMeasure, original); assert(f.metricReads > 0)
    local width, clockPosition = widget.width, f:position(f.clock)
    for _, recent in ipairs({ 0, 2.5, 10000 }) do
        f.recent = recent; f:tick(1.1)
        equal(widget.width, width); equal(f:position(f.clock), clockPosition); f:fits()
    end
    f.profilerEnabled = false; f:tick(1.1)
    assert(widget.text:find("Addons %-%- ms")); equal(widget.width, width); equal(f:position(f.clock), clockPosition)
    equal(f.memoryScans, 0)
end)

check("plain left-click is quiet while Shift-left and right-click retain native menus and settings", function()
    local f = fixture(); local widget = f.widget; local menus = #f.Stub.menus
    widget.frame:Click("LeftButton"); equal(#f.Stub.menus, menus)
    f.shift = true; widget.frame:Click("LeftButton")
    equal(#f.Stub.menus, menus + 1); assert(f.Stub.MenuItem(f.Stub.menus[#f.Stub.menus], "Configure..."))
    widget.frame:Click("RightButton"); equal(f.host.UI.widgetID, widget.id)
    local foundDisplay, foundDiagnostics, foundUsage = false, false, false
    for _, control in ipairs(f.host.UI.window.controls) do
        if control.caption == "Display" then foundDisplay = true end
        if control.caption == "Monitor our addons" then foundDiagnostics = true end
        if control.caption == "Addon usage" then foundUsage = true end
    end
    assert(foundDisplay and foundDiagnostics and foundUsage)
    widget.frame.scripts.OnEnter(widget.frame)
    equal(GameTooltip:GetOwner(), widget.frame)
    equal(GameTooltip.lines[#GameTooltip.lines][1], "Shift-left-click: menu   Right-click: settings")
end)

check("duplicate and alternate-character settings remain independent", function()
    local f = fixture(); local first = f.widget
    first.settings.display, first.settings.diagnostics = "both", true
    f.host:RefreshWidget(first.id)
    f:pickUsage(first, "Memory")
    f:memoryUnits(first, true)
    local instance = f.host:AddWidget("performance"); local second = f.host.runtime[instance.id]
    assert(second.settings ~= first.settings)
    equal(second.settings.display, "fps"); equal(second.settings.diagnostics, false)
    equal(second.settings.usageMetric, "memory"); equal(first.settings.usageMetric, "memory")
    f:pickUsage(second, "CPU time"); equal(first.settings.usageMetric, "memory")
    equal(second.settings.memoryInKB, false); equal(first.settings.memoryInKB, true)
    second.settings.display = "frameTime"; equal(first.settings.display, "both")
    local originalCharacter = f.host.characterKey
    f.host.characterKey = "Other player - Test Realm"; f.host:EnsureDefaults(); f.host:Rebuild()
    local other = assert(f:find("performance"))
    equal(other.settings.display, "fps"); equal(other.settings.diagnostics, false)
    equal(other.settings.usageMetric, "memory")
    equal(other.settings.memoryInKB, false)
    other.settings.display = "frameTime"
    f.host.characterKey = originalCharacter; f.host:Rebuild()
    equal(f.host.runtime[first.id].settings.display, "both"); equal(f.host.runtime[first.id].settings.diagnostics, true)
    equal(f.host.runtime[first.id].settings.usageMetric, "memory")
    equal(f.host.runtime[first.id].settings.memoryInKB, true)
    equal(f.host.runtime[second.id].settings.display, "frameTime")
    equal(f.host.runtime[second.id].settings.usageMetric, "cpu")
    equal(f.host.runtime[second.id].settings.memoryInKB, false)
end)

check("host render errors reset layout state and reuse the retained measurement region on recovery", function()
    local f = fixture(); local widget = f.widget; local measure = widget.performanceMeasure
    local setText = widget.SetText
    widget.SetText = function() error("Performance render failed", 0) end
    f.host:RefreshWidget(widget.id)
    equal(widget.failed, "Performance render failed"); equal(widget.customWidth, nil)
    equal(measure:IsShown(), false)
    widget.SetText = setText; f.host:RefreshWidget(widget.id); f.host:Layout()
    equal(widget.failed, nil); equal(widget.performanceMeasure, measure); f:fits()
end)

check("overflowed widgets resume their current FPS and stable layout when space returns", function()
    local f = fixture(); local widget = f.widget; local measure = widget.performanceMeasure
    local width = widget.width
    UIParent:SetWidth(44); f.host:Rebuild(); equal(widget.frame:IsShown(), false)
    f.fps = 144; f:tick()
    UIParent:SetWidth(1280); f.host:Rebuild()
    equal(widget.frame:IsShown(), true); equal(widget.text, "144 FPS")
    equal(widget.width, width); equal(widget.performanceMeasure, measure); f:fits()
end)

check("the native Addon usage picker switches metrics without resetting FPS options or sampling the other mode", function()
    local f = fixture(); local widget = f.widget; local clockZone = f.clock.settings.zone
    widget.settings.display, widget.settings.diagnostics, widget.settings.usageMetric = "both", true, nil
    f.host:Rebuild()
    equal(widget.settings.usageMetric, "cpu") -- Sparse existing settings preserve the former metric.
    assert(widget.text:find("Addons 0.50 ms", 1, true)); equal(f.memoryScans, 0)
    local reads, checks = f.metricReads, f.profilerChecks
    f:pickUsage(widget, "Memory")
    equal(widget.settings.usageMetric, "memory"); equal(widget.settings.display, "both")
    equal(widget.text, "99 FPS / ~10.1 ms | Addons 320.0 kB")
    equal(f.memoryScans, 1); equal(f.metricReads, reads); equal(f.profilerChecks, checks)
    widget.frame.scripts.OnEnter(widget.frame)
    equal(f.metricReads, reads); equal(f.profilerChecks, checks)
    f.fps = 120; f:tick(16)
    equal(widget.text, "120 FPS / ~8.3 ms | Addons 320.0 kB")
    equal(f.memoryScans, 2); equal(f.metricReads, reads); equal(f.profilerChecks, checks)
    f:pickUsage(widget, "CPU time")
    equal(widget.settings.usageMetric, "cpu"); equal(widget.settings.display, "both")
    equal(widget.text, "120 FPS / ~8.3 ms | Addons 0.50 ms")
    assert(f.metricReads > reads); equal(f.memoryScans, 2); equal(f.clock.settings.zone, clockZone)
end)

check("memory reservations remain stable through value changes, unavailable data and overflow", function()
    local f = fixture(); local widget = f.widget; local measure = widget.performanceMeasure
    widget.settings.display, widget.settings.diagnostics = "both", true
    f:pickUsage(widget, "Memory"); f.host:Layout()
    local width, clockPosition = widget.width, f:position(f.clock)
    for _, memory in ipairs({ 0, 888, 100000000, f.secret }) do
        f.memory = memory; f:tick(15.1)
        equal(widget.width, width); equal(f:position(f.clock), clockPosition); f:fits()
    end
    UIParent:SetWidth(44); f.host:Rebuild(); equal(widget.frame:IsShown(), false)
    f.memory = 144; f:tick(15.1)
    UIParent:SetWidth(1280); f.host:Rebuild()
    equal(widget.frame:IsShown(), true); equal(widget.width, width)
    equal(widget.text, "99 FPS / ~10.1 ms | Addons 720.0 kB")
    equal(widget.performanceMeasure, measure); equal(f.metricReads, 0); equal(f.profilerChecks, 0); f:fits()
end)

check("native metric selection changes the global tooltip as well as project detail rows", function()
    local f = fixture(); local widget = f.widget
    local function value(caption)
        for _, line in ipairs(GameTooltip.lines) do if line[1] == caption then return line[2] end end
    end
    local function contains(needle)
        for _, line in ipairs(GameTooltip.lines) do
            for _, text in ipairs(line) do if type(text) == "string" and text:find(needle, 1, true) then return true end end
        end
        return false
    end
    widget.frame.scripts.OnEnter(widget.frame)
    equal(value("Approx. addon CPU / tick"), "0.60 ms")
    equal(value("Addon Lua memory"), nil)
    assert(not contains("kB")); assert(contains("Largest addons by recent CPU"))
    equal(f.memoryScans, 0)
    f:pickUsage(widget, "Memory"); widget.frame.scripts.OnEnter(widget.frame)
    equal(value("Addon Lua memory"), "384.0 kB")
    equal(value("Approx. addon CPU / tick"), nil)
    local reads = f.metricReads
    f:pickUsage(widget, "CPU time"); widget.frame.scripts.OnEnter(widget.frame)
    equal(value("Approx. addon CPU / tick"), "0.60 ms")
    equal(value("Addon Lua memory"), nil); assert(not contains("kB"))
    equal(f.memoryScans, 1); equal(f.metricReads, reads)
end)

check("the native memory checkbox updates all memory sections while duplicate instances keep their own units", function()
    local f = fixture(); local first = f.widget
    f.memory = 2048
    first.settings.display, first.settings.diagnostics = "both", true
    f:pickUsage(first, "Memory")
    equal(first.settings.memoryInKB, false)
    equal(first.text, "99 FPS / ~10.1 ms | Addons 10.0 MB")
    local function value(caption)
        for _, line in ipairs(GameTooltip.lines) do if line[1] == caption then return line[2] end end
    end
    first.frame.scripts.OnEnter(first.frame)
    equal(value("Addon Lua memory"), "12.0 MB")
    f:memoryUnits(first, true)
    equal(first.text, "99 FPS / ~10.1 ms | Addons 10240.0 kB")
    first.frame.scripts.OnEnter(first.frame)
    equal(value("Addon Lua memory"), "12288.0 kB")
    equal(value("Our addons Lua memory"), "10240.0 kB")
    equal(value("Menubar"), "2048.0 kB")
    local instance = f.host:AddWidget("performance"); local second = f.host.runtime[instance.id]
    second.settings.diagnostics, second.settings.usageMetric = true, "memory"
    f.host:RefreshWidget(second.id)
    equal(second.settings.memoryInKB, false)
    equal(second.text, "99 FPS | Addons 10.0 MB")
    equal(first.settings.memoryInKB, true)
    f:memoryUnits(first, false)
    equal(first.text, "99 FPS / ~10.1 ms | Addons 10.0 MB")
    equal(second.settings.memoryInKB, false); equal(second.text, "99 FPS | Addons 10.0 MB")
    equal(f.memoryScans, 1); equal(f.metricReads, 0); equal(f.profilerChecks, 0)
end)

check("switching memory units reuses the measuring region and keeps neighbouring widgets steady between changes", function()
    local f = fixture(); local widget = f.widget
    f.memory = 2048; widget.settings.display, widget.settings.diagnostics = "both", true
    f:pickUsage(widget, "Memory"); f.host:Layout()
    local measure, autoWidth = widget.performanceMeasure, widget.width
    local scans = f.memoryScans
    f:memoryUnits(widget, true); f.host:Layout()
    local forcedWidth, clockPosition = widget.width, f:position(f.clock)
    assert(forcedWidth > autoWidth); equal(f.memoryScans, scans)
    for _, memory in ipairs({ 0, 0.1, 1024, 1e12, f.secret }) do
        f.memory = memory; f:tick(15.1)
        equal(widget.width, forcedWidth); equal(f:position(f.clock), clockPosition); f:fits()
    end
    scans = f.memoryScans
    f:memoryUnits(widget, false); f.host:Layout()
    equal(widget.width, autoWidth); equal(widget.performanceMeasure, measure)
    equal(f.memoryScans, scans); equal(f.metricReads, 0); equal(f.profilerChecks, 0); f:fits()
end)

check("the original icon stays distinct in all five themes with a transparent bar and minimum height", function()
    local f = fixture(); local widget = f.widget
    local icon, outline = assert(widget.performanceIcon), assert(widget.performanceIconOutline)
    local profile = f.host:GetProfile()
    local themes = { "system7", "macos8", "warcraftBrown", "warcraftBlack", "warcraftRed" }
    for _, theme in ipairs(themes) do
        MenubarModel.ApplyTheme(profile, theme); profile.opacity, profile.height = 0, 16
        f.host:Rebuild(); f:fits()
        assert(icon:IsVisible() and outline:IsVisible())
        equal(icon:GetParent(), widget.frame); equal(outline:GetParent(), widget.frame)
        local iconHeight = math.min(14, widget.content:GetHeight())
        equal(icon:GetWidth(), iconHeight); equal(icon:GetHeight(), iconHeight)
        equal(outline:GetWidth(), iconHeight); equal(outline:GetHeight(), iconHeight)
        for _, region in ipairs({ icon, outline }) do
            equal(region.points[1][2], widget.content)
            assert(region:GetTop() <= widget.content:GetTop() + 0.00001)
            assert(region:GetBottom() >= widget.content:GetBottom() - 0.00001)
            assert(region:GetTop() <= widget.frame:GetTop() + 0.00001)
            assert(region:GetBottom() >= widget.frame:GetBottom() - 0.00001)
        end
        equal(widget.label.points[1][2], widget.content)
        equal(icon.points[1][4], 4); equal(widget.label.points[1][1], "LEFT"); equal(widget.label.points[1][4], 22)
        equal(icon.drawLayer, "ARTWORK"); assert(outline.drawLevel < icon.drawLevel)
        local red, green, blue, alpha = widget.label:GetTextColor()
        equal(icon.vertexColor[1], red); equal(icon.vertexColor[2], green)
        equal(icon.vertexColor[3], blue); equal(icon.vertexColor[4], alpha)
        local opposite = red * 0.2126 + green * 0.7152 + blue * 0.0722 >= 0.5 and 0 or 1
        for index = 1, 3 do equal(outline.vertexColor[index], opposite) end
        equal(outline.vertexColor[4], alpha); equal(f.host.bars.top.surface:GetAlpha(), 0)
        equal(widget.frame:GetAlpha(), 1); equal(icon:GetAlpha(), 1)
        equal(widget.width, widget.performanceSizing.width + 18)
        equal(widget.text, "99 FPS")
    end
    local frames, textures = #f.Stub.frames, #f.Stub.textures
    for _ = 1, 3 do for _, theme in ipairs(themes) do MenubarModel.ApplyTheme(profile, theme); f.host:Rebuild() end end
    equal(widget.performanceIcon, icon); equal(widget.performanceIconOutline, outline)
    equal(#f.Stub.frames, frames); equal(#f.Stub.textures, textures)
    equal(f.memoryScans, 0); equal(f.metricReads, 0)
end)

check("steady ticks retain the text reservation without repeating icon setup or tint writes", function()
    local f = fixture(); local widget = f.widget
    local writes, width, measure = 0, widget.width, widget.performanceMeasure
    for _, icon in ipairs({ widget.performanceIcon, widget.performanceIconOutline }) do
        for _, method in ipairs({ "SetTexture", "SetPoint", "SetVertexColor", "SetSize" }) do
            local original = icon[method]
            icon[method] = function(self, ...) writes = writes + 1; return original(self, ...) end
        end
    end
    for _, fps in ipairs({ 11, 888, 60, 9999 }) do f.fps = fps; f:tick(); equal(widget.width, width); f:fits() end
    equal(writes, 0); equal(widget.performanceMeasure, measure)
    equal(widget.width, widget.performanceSizing.width + 18)
end)

check("duplicates own separate icons and disable enable removal reuse their presentation safely", function()
    local f = fixture(); local first = f.widget
    local instance = f.host:AddWidget("performance"); local second = f.host.runtime[instance.id]
    assert(first.performanceIcon ~= second.performanceIcon and first.performanceIconOutline ~= second.performanceIconOutline)
    second.settings.display = "frameTime"; f.host:RefreshWidget(second.id)
    local icon, outline, measure = first.performanceIcon, first.performanceIconOutline, first.performanceMeasure
    local frames, textures = #f.Stub.frames, #f.Stub.textures
    for _ = 1, 10 do
        first.instance.enabled = false; f.host:Rebuild()
        assert(not icon:IsShown() and not outline:IsShown()); equal(first.customWidth, nil)
        equal(first.label.points[1][1], "CENTER"); assert(second.performanceIcon:IsShown())
        first.instance.enabled = true; f.host:Rebuild()
        equal(f.host.runtime[first.id], first); assert(icon:IsVisible() and outline:IsVisible())
        equal(first.label.points[1][1], "LEFT"); equal(first.width, first.performanceSizing.width + 18)
    end
    equal(first.performanceMeasure, measure); equal(#f.Stub.frames, frames); equal(#f.Stub.textures, textures)
    equal(first.text, "99 FPS"); equal(second.text, "~10.1 ms")
    f.host:RemoveWidget(first.id)
    assert(not icon:IsShown() and not outline:IsShown()); equal(first.label.points[1][1], "CENTER")
    assert(second.performanceIcon:IsShown()); equal(f.host.runtime[second.id], second)
end)

check("a rejected or unconfirmed icon texture keeps plain text without empty space and retries on the next tick", function()
    for _, failure in ipairs({ "false", "nil" }) do
        local options = { iconFailure = failure }
        local f = fixture(options); local widget = f.widget
        local icon, outline, measure = widget.performanceIcon, widget.performanceIconOutline, widget.performanceMeasure
        local textures = #f.Stub.textures
        equal(widget.failed, nil); equal(widget.text, "99 FPS")
        assert(not icon:IsShown() and not outline:IsShown()); equal(widget.label.points[1][1], "CENTER")
        equal(widget.width, widget.performanceSizing.width)
        options.iconFailure = nil; f:tick()
        equal(widget.performanceIcon, icon); equal(widget.performanceIconOutline, outline); equal(widget.performanceMeasure, measure)
        equal(#f.Stub.textures, textures); assert(icon:IsShown() and outline:IsShown())
        equal(widget.width, widget.performanceSizing.width + 18); f:fits()
    end
end)

check("partial icon allocation and unexpected setup failures keep readable errors and recover owned regions", function()
    for _, failure in ipairs({ "creation", "throw" }) do
        local options = { iconFailure = failure }
        local f = fixture(options); local widget = f.widget
        local outline, icon = assert(widget.performanceIconOutline), widget.performanceIcon
        assert(widget.failed and widget.text:find("error", 1, true))
        equal(widget.customWidth, nil); assert(not outline:IsShown())
        if icon then assert(not icon:IsShown()) end
        equal(widget.label.points[1][1], "CENTER")
        local textures = #f.Stub.textures
        options.iconFailure = nil; f.host:RefreshWidget(widget.id); f.host:Layout()
        equal(widget.failed, nil); equal(widget.performanceIconOutline, outline)
        if icon then equal(widget.performanceIcon, icon) end
        equal(#f.Stub.textures, textures + (icon and 0 or 1))
        equal(widget.text, "99 FPS"); assert(widget.performanceIcon:IsShown() and outline:IsShown()); f:fits()
    end
end)

check("a partial tint failure cannot leave stale icon colours when the theme is rolled back", function()
    local f = fixture(); local widget = f.widget
    local profile = f.host:GetProfile()
    -- Warm both native styles so the remaining allocation check concerns recovery.
    MenubarModel.ApplyTheme(profile, "system7"); f.host:Rebuild()
    MenubarModel.ApplyTheme(profile, "warcraftBrown"); f.host:Rebuild()
    local icon, outline, measure = widget.performanceIcon, widget.performanceIconOutline, widget.performanceMeasure
    local frames, textures = #f.Stub.frames, #f.Stub.textures
    local original = outline.SetVertexColor
    outline.SetVertexColor = function() error("Performance outline tint failed", 0) end
    MenubarModel.ApplyTheme(profile, "system7"); f.host:Rebuild()
    equal(widget.failed, "Performance outline tint failed")
    for index = 1, 3 do equal(icon.vertexColor[index], 0) end -- Body was already changed.
    assert(not icon:IsShown() and not outline:IsShown())
    equal(widget.customWidth, nil); equal(widget.label.points[1][1], "CENTER")
    outline.SetVertexColor = original
    MenubarModel.ApplyTheme(profile, "warcraftBrown"); f.host:Rebuild()
    f.host:RefreshWidget(widget.id); f.host:Layout()
    equal(widget.failed, nil); equal(widget.text, "99 FPS")
    equal(widget.performanceIcon, icon); equal(widget.performanceIconOutline, outline); equal(widget.performanceMeasure, measure)
    local red, green, blue, alpha = widget.label:GetTextColor()
    equal(icon.vertexColor[1], red); equal(icon.vertexColor[2], green)
    equal(icon.vertexColor[3], blue); equal(icon.vertexColor[4], alpha)
    for index = 1, 3 do equal(outline.vertexColor[index], 0) end
    assert(icon:IsVisible() and outline:IsVisible()); f:fits()
    equal(#f.Stub.frames, frames); equal(#f.Stub.textures, textures)
end)

print(passed .. " Performance host integration tests passed")
