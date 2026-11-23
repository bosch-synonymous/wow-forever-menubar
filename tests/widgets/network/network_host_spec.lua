-- Real-host layout/lifetime checks. The small shared double does not certify
-- native texture rendering, contrast or client draw order.
local root = REPO_ROOT or "."
local core = MENUBAR_CORE_ROOT or root
local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end
if not exists(core .. "/tests/wow_stub.lua") then
    print("SKIP Network host integration: restore Core in this repository or supply MENUBAR_CORE_ROOT.")
    return
end
local passed = 0
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.00001,
        "expected approximately " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function fixture(beforeUpdate)
    local f = { reads = 0, world = 81, home = 42 }
    local Stub = dofile(core .. "/tests/wow_stub.lua")
    Stub.Install()
    MenubarDB = nil
    GetNetStats = function()
        f.reads = f.reads + 1
        if f.unavailable then error("statistics unavailable", 0) end
        return 1.25, 0.75, f.home, f.world
    end
    for _, file in ipairs({ "Model.lua", "Identity.lua", "Fonts.lua", "Layout.lua", "Gauge.lua", "Skins.lua", "Core.lua", "UI.lua", "Settings.lua" }) do
        dofile(core .. "/src/menubar-core/" .. file)
    end
    dofile(root .. "/src/menubar-network/Network.lua")
    if beforeUpdate then Menubar.types.network.create = function(widget) beforeUpdate(widget, f) end end
    Menubar:Start()
    for _, widget in pairs(Menubar.runtime) do if widget.instance.type == "network" then f.widget = widget end end
    assert(f.widget)
    f.host, f.stub = Menubar, Stub
    function f:refresh() self.host:RefreshWidget(self.widget.id); self.host:Layout() end
    function f:tick()
        self.host.eventFrame.scripts.OnUpdate(self.host.eventFrame, 1)
    end
    function f:healthy() equal(self.widget.failed, nil) end
    return f
end
local function visibleIcon(widget)
    assert(widget.networkIcon and widget.networkOutline)
    assert(widget.networkIcon:IsVisible() and widget.networkOutline:IsVisible())
    equal(widget.networkIcon:GetTexture(), "Interface\\AddOns\\Menubar_Network\\Media\\network.tga")
    equal(widget.networkOutline:GetTexture(), "Interface\\AddOns\\Menubar_Network\\Media\\network-outline.tga")
    equal(widget.networkIcon:GetParent(), widget.frame); equal(widget.networkOutline:GetParent(), widget.frame)
end

check("all five theme colours preserve distinct Network layers at zero background opacity and a sixteen-pixel bar", function()
    for _, filename in ipairs({ "network.tga", "network-outline.tga" }) do
        local file = assert(io.open(root .. "/src/menubar-network/Media/" .. filename, "rb"))
        local header = file:read(18); file:close()
        equal(header:byte(3), 2); equal(header:byte(13) + 256 * header:byte(14), 64)
        equal(header:byte(15) + 256 * header:byte(16), 64)
        equal(header:byte(17), 32); equal(header:byte(18), 40)
    end
    local f = fixture(); local widget = f.widget
    local body, outline = widget.networkIcon, widget.networkOutline
    for _, theme in ipairs({ "system7", "macos8", "warcraftBrown", "warcraftBlack", "warcraftRed" }) do
        local profile = f.host:GetProfile()
        assert(MenubarModel.ApplyTheme(profile, theme))
        profile.height, profile.opacity = 16, 0
        f.host:Rebuild(); f:healthy(); visibleIcon(widget)
        equal(widget.networkIcon, body); equal(widget.networkOutline, outline)
        equal(widget.text, "81 ms"); equal(widget.label:GetText(), "81 ms")
        equal(widget.frame:GetHeight(), 16)
        local iconHeight = math.min(14, widget.content:GetHeight())
        for _, region in ipairs({ body, outline }) do
            equal(region:GetWidth(), iconHeight); equal(region:GetHeight(), iconHeight)
            equal(select(2, region:GetPoint(1)), widget.content)
            assert(region:GetTop() <= widget.content:GetTop() + 0.00001)
            assert(region:GetBottom() >= widget.content:GetBottom() - 0.00001)
            assert(region:GetTop() <= widget.frame:GetTop() + 0.00001)
            assert(region:GetBottom() >= widget.frame:GetBottom() - 0.00001)
            equal(region:GetEffectiveAlpha(), 1); equal(region.vertexColor[4], 1)
        end
        local r, g, b = widget.label:GetTextColor()
        equal(body.vertexColor[1], r); equal(body.vertexColor[2], g); equal(body.vertexColor[3], b)
        local expectedEdge = (0.2126 * r + 0.7152 * g + 0.0722 * b) >= 0.5 and 0 or 1
        equal(outline.vertexColor[1], expectedEdge)
        equal(outline.vertexColor[2], expectedEdge); equal(outline.vertexColor[3], expectedEdge)
        near(widget.width, widget.label:GetStringWidth() + 26)
        local point, relative, relativePoint, x, y = widget.label:GetPoint(1)
        equal(point, "LEFT"); equal(relative, widget.content); equal(relativePoint, "LEFT")
        equal(x, 22); equal(y, 0)
        near(body:GetLeft() - widget.frame:GetLeft(), 4)
    end
end)

check("normal polling changes data without repeating static texture placement or tint work", function()
    local f = fixture(); local widget = f.widget
    local calls = { texture = 0, point = 0, color = 0, size = 0 }
    for _, region in ipairs({ widget.networkIcon, widget.networkOutline, widget.label }) do
        for method, key in pairs({ SetTexture = "texture", SetPoint = "point", SetVertexColor = "color", SetSize = "size" }) do
            local original = region[method]
            region[method] = function(self, ...)
                calls[key] = calls[key] + 1
                return original(self, ...)
            end
        end
    end
    local frames, textures, reads = #f.stub.frames, #f.stub.textures, f.reads
    for value = 82, 91 do f.world = value; f:tick(); f:healthy() end
    equal(f.reads - reads, 10); equal(widget.text, "91 ms")
    equal(calls.texture, 0); equal(calls.point, 0); equal(calls.color, 0); equal(calls.size, 0)
    equal(#f.stub.frames, frames); equal(#f.stub.textures, textures)
    widget.settings.latency, widget.settings.showLabel, widget.settings.showThroughput = "home", true, true
    f:refresh(); equal(widget.text, "Home 42 ms  In 1.2 / Out 0.8 KB/s")
    near(widget.width, widget.label:GetStringWidth() + 26)
    f.unavailable = true; f:tick(); f:healthy()
    equal(widget.text, "Home -- ms  In -- / Out -- KB/s"); visibleIcon(widget)
    f.unavailable = false; f:tick(); equal(widget.text, "Home 42 ms  In 1.2 / Out 0.8 KB/s")
    equal(calls.texture, 0); equal(calls.point, 0); equal(calls.color, 0); equal(calls.size, 0)
    -- The host may explicitly clear presentation after another callback fails.
    f.host.UI:ResetWidgetPresentation(widget); f:refresh()
    equal(select(1, widget.label:GetPoint(1)), "LEFT"); equal(calls.point, 2)
end)

check("duplicate icons remain independent and retained disable reset and removal release their presentation", function()
    local f = fixture(); local widget = f.widget
    local body, outline = widget.networkIcon, widget.networkOutline
    local instance = f.host:AddWidget("network"); local second = f.host.runtime[instance.id]
    assert(second.networkIcon ~= body and second.networkOutline ~= outline)
    local frames, textures = #f.stub.frames, #f.stub.textures
    for _ = 1, 5 do
        widget.instance.enabled = false; f.host:Rebuild()
        equal(f.host.dormant[widget.id], widget)
        equal(body:IsShown(), false); equal(outline:IsShown(), false)
        equal(widget.customWidth, nil); equal(select(1, widget.label:GetPoint(1)), "CENTER")
        visibleIcon(second)
        widget.instance.enabled = true; f.host:Rebuild(); f:healthy()
        equal(f.host.runtime[widget.id], widget); equal(widget.networkIcon, body); visibleIcon(widget)
    end
    equal(#f.stub.frames, frames); equal(#f.stub.textures, textures)
    f.host:Call(widget, "reset")
    equal(body:IsShown(), false); equal(outline:IsShown(), false); equal(widget.customWidth, nil)
    equal(select(1, widget.label:GetPoint(1)), "CENTER")
    f:refresh(); visibleIcon(widget); equal(widget.networkIcon, body)
    f.host:RemoveWidget(widget.id)
    equal(f.host.runtime[widget.id], nil); equal(body:IsShown(), false); equal(outline:IsShown(), false)
    equal(widget.customWidth, nil); visibleIcon(second)
end)

check("a known rejected asset falls back to ordinary text and the next poll reuses both owned regions", function()
    local f = fixture(function(widget, context)
        context.reject = true
        local create = widget.frame.CreateTexture
        widget.frame.CreateTexture = function(owner, ...)
            local region = create(owner, ...)
            local setTexture = region.SetTexture
            region.SetTexture = function(self, path)
                if context.reject and path:find("Media\\network.tga", 1, true) then return false end
                return setTexture(self, path)
            end
            return region
        end
    end)
    local widget = f.widget; f:healthy()
    local body, outline, frames, textures = widget.networkIcon, widget.networkOutline, #f.stub.frames, #f.stub.textures
    assert(body and outline); equal(body:IsShown(), false); equal(outline:IsShown(), false)
    equal(widget.text, "81 ms"); equal(widget.customWidth, nil)
    near(widget.width, widget.label:GetStringWidth() + 8)
    equal(select(1, widget.label:GetPoint(1)), "CENTER")
    f.reject = false; f:tick(); f:healthy(); visibleIcon(widget)
    equal(widget.networkIcon, body); equal(widget.networkOutline, outline)
    equal(#f.stub.frames, frames); equal(#f.stub.textures, textures)
    near(widget.width, widget.label:GetStringWidth() + 26)
end)

check("partially configured native regions stay owned and a host recovery keeps the error readable without leaking textures", function()
    local f = fixture(function(widget, context)
        context.fail = true
        local create = widget.frame.CreateTexture
        widget.frame.CreateTexture = function(owner, ...)
            local region = create(owner, ...)
            local setPoint = region.SetPoint
            region.SetPoint = function(self, ...)
                if context.fail then error("native Network placement unavailable", 0) end
                return setPoint(self, ...)
            end
            return region
        end
    end)
    local widget = f.widget; local outline = assert(widget.networkOutline)
    assert(widget.failed and widget.failed:find("native Network placement unavailable", 1, true))
    equal(outline:IsShown(), false); equal(widget.networkIcon, nil); equal(widget.customWidth, nil)
    equal(select(1, widget.label:GetPoint(1)), "CENTER")
    assert(widget.label:GetText():find("error", 1, true)); assert(widget.width >= widget.label:GetStringWidth() + 8)
    local frames, textures = #f.stub.frames, #f.stub.textures
    f.fail = false; f:refresh(); f:healthy(); visibleIcon(widget)
    equal(widget.networkOutline, outline); equal(#f.stub.frames, frames); equal(#f.stub.textures, textures + 1)
    textures = #f.stub.textures
    for _ = 1, 5 do f:refresh(); f.host:Rebuild() end
    equal(#f.stub.frames, frames); equal(#f.stub.textures, textures)
end)

check("unreadable tint values never enter colour arithmetic and unusually wide text stays within the host bound", function()
    local f = fixture(); local widget = f.widget
    local color, width = widget.label.GetTextColor, widget.label.GetStringWidth
    local secret = {}; local originalSecret = issecretvalue
    issecretvalue = function(value) return value == secret or (originalSecret and originalSecret(value)) end
    widget.label.GetTextColor = function() return secret, 0, 0, 1 end
    f:refresh(); f:healthy()
    for index = 1, 4 do equal(widget.networkIcon.vertexColor[index], 1) end
    for index = 1, 3 do equal(widget.networkOutline.vertexColor[index], 0) end
    widget.label.GetTextColor = function() end
    f:refresh(); f:healthy()
    widget.label.GetTextColor = color; issecretvalue = originalSecret
    widget.label.GetStringWidth = function() return 20000 end
    f:refresh(); f:healthy(); equal(widget.width, 9999)
    widget.label.GetStringWidth = width
    f:refresh(); f:healthy(); near(widget.width, widget.label:GetStringWidth() + 26)
end)

check("a partially written tint cannot survive failure cleanup when the original theme is restored", function()
    local f = fixture(); local widget = f.widget
    local body, outline = widget.networkIcon, widget.networkOutline
    local profile = f.host:GetProfile()
    assert(MenubarModel.ApplyTheme(profile, "warcraftBrown")); f.host:Rebuild(); f:healthy()
    equal(body.vertexColor[1], 1)
    local setColor, fail = outline.SetVertexColor, true
    outline.SetVertexColor = function(self, ...)
        if fail then error("native Network outline tint unavailable", 0) end
        return setColor(self, ...)
    end
    local frames, textures = #f.stub.frames, #f.stub.textures
    assert(MenubarModel.ApplyTheme(profile, "system7")); f.host:Rebuild()
    assert(widget.failed and widget.failed:find("native Network outline tint unavailable", 1, true))
    equal(body.vertexColor[1], 0) -- The first setter succeeded before the second failed.
    equal(body:IsShown(), false); equal(outline:IsShown(), false)
    fail = false
    assert(MenubarModel.ApplyTheme(profile, "warcraftBrown")); f.host:Rebuild(); f:healthy(); visibleIcon(widget)
    local r, g, b, a = widget.label:GetTextColor()
    equal(body.vertexColor[1], r); equal(body.vertexColor[2], g)
    equal(body.vertexColor[3], b); equal(body.vertexColor[4], a)
    equal(outline.vertexColor[1], 0); equal(outline.vertexColor[4], a)
    equal(widget.networkIcon, body); equal(widget.networkOutline, outline)
    equal(#f.stub.frames, frames); equal(#f.stub.textures, textures)
end)

print(passed .. " Network host integration tests passed")
