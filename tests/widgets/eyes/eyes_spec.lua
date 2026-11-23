local passed, provider = 0, nil
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.00001,
        "expected approximately " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, callback)
    callback(); passed = passed + 1; print("PASS " .. name)
end
Menubar = { RegisterWidgetType = function(_, definition) provider = definition end }
local mouseX, mouseY, visible, looking = 500, 200, true, false
GetCursorPosition = function() return mouseX, mouseY end
IsCursorVisible = function() return visible end
IsMouselooking = function() return looking end
dofile("src/menubar-eyes/Eyes.lua")

local function widget(options, scale, height, deferCreate)
    local frame = { textures = {}, scale = scale or 1, height = height or 24,
        centerX = 100, centerY = 100, hooks = {} }
    function frame:GetCenter() return self.centerX, self.centerY end
    function frame:GetEffectiveScale() return self.scale end
    function frame:GetHeight() return self.height end
    function frame:HookScript(name, callback)
        self.hooks[name] = self.hooks[name] or {}
        self.hooks[name][#self.hooks[name] + 1] = callback
    end
    function frame:Hide()
        for _, callback in ipairs(self.hooks.OnHide or {}) do callback(self) end
    end
    function frame:CreateTexture(_, layer, _, level)
        equal(layer, "ARTWORK")
        local texture = { level = level }
        function texture:SetColorTexture(...) self.color = { ... } end
        function texture:SetTexture(path) self.asset = path end
        function texture:SetVertexColor(...) self.vertexColor = { ... } end
        function texture:SetAlpha(alpha) self.alpha = alpha end
        function texture:GetAlpha() return self.alpha == nil and 1 or self.alpha end
        function texture:SetBlendMode(mode) self.blendMode = mode end
        function texture:SetDrawLayer(drawLayer, drawLevel) self.layer, self.level = drawLayer, drawLevel end
        function texture:ClearAllPoints() self.point = nil end
        function texture:SetPoint(_, anchor, _, x, y)
            assert(type(x) == "number" and x == x and math.abs(x) < math.huge, "Texture x must be finite")
            assert(type(y) == "number" and y == y and math.abs(y) < math.huge, "Texture y must be finite")
            equal(anchor, frame); self.x, self.y = x, y
        end
        function texture:SetSize(width, textureHeight) self.width, self.height = width, textureHeight end
        function texture:Show() self.shown = true end
        function texture:Hide() self.shown = false end
        frame.textures[#frame.textures + 1] = texture
        return texture
    end
    local value = { frame = frame, settings = {} }
    for key, default in pairs(provider.defaults) do value.settings[key] = default end
    -- Most geometry checks deliberately exercise the optional standard renderer.
    value.settings.appearance, value.settings.iris = "standard", "black"
    for key, override in pairs(options or {}) do value.settings[key] = override end
    function value:SetText(text) self.text = text end
    function value:SetWidth(width)
        self.width, self.customWidth = width, width
        self.widthChanges = (self.widthChanges or 0) + 1
    end
    if not deferCreate then provider.create(value); provider.update(value) end
    return value
end

test("registers independent original graphical provider", function()
    equal(provider.id, "eyes"); near(provider.interval, 1 / 30)
    assert(provider.interval >= 0.02)
    equal(provider.defaults.appearance, "smooth"); equal(provider.defaults.iris, "blue")
end)

test("factory eyes use smooth blue artwork while retaining white sclera", function()
    local value = widget({ appearance = provider.defaults.appearance, iris = provider.defaults.iris })
    equal(#value.frame.textures, 6); equal(value.text, ""); equal(value.width, 40)
    equal(value.eyes[1].smooth.orb.vertexColor[1], 1)
    equal(value.eyes[1].smooth.orb.vertexColor[2], 1)
    equal(value.eyes[1].smooth.orb.vertexColor[3], 1)
    assert(value.eyes[1].smooth.iris.vertexColor[3] > value.eyes[1].smooth.iris.vertexColor[1])
end)
test("constructs solid geometric art without external assets", function()
    local value = widget()
    equal(#value.frame.textures, 24); equal(value.text, ""); equal(value.width, 40)
    for _, texture in ipairs(value.frame.textures) do assert(texture.shown); assert(texture.color) end
end)
test("far right cursor moves both pupils right inside their eyes", function()
    mouseX, mouseY = 10000, 100
    local value = widget()
    near(value.eyes[1].pupil.x, -5); near(value.eyes[2].pupil.x, 11)
    near(value.eyes[1].pupil.y, 0)
end)
test("far upward cursor moves pupils upward within bounded travel", function()
    mouseX, mouseY = 100, 10000
    local value = widget()
    assert(value.eyes[1].pupil.y > 3.9 and value.eyes[1].pupil.y <= 4)
    assert(value.eyes[2].pupil.y > 3.9 and value.eyes[2].pupil.y <= 4)
end)
test("coordinate scaling tracks the same physical direction", function()
    mouseX, mouseY = 10000, 200
    local value = widget(nil, 2)
    near(value.eyes[1].pupil.x, -5); near(value.eyes[1].pupil.y, 0)
end)
test("hidden cursor and camera turning produce neutral eyes", function()
    visible = false
    local value = widget()
    near(value.eyes[1].pupil.x, -8); near(value.eyes[2].pupil.x, 8)
    visible, looking = true, true
    provider.update(value); near(value.eyes[1].pupil.x, -8)
    looking = false
end)
test("cursor tracking can be disabled per instance", function()
    mouseX, mouseY = 10000, 100
    local first, second = widget({ followCursor = false }), widget()
    near(first.eyes[1].pupil.x, -8); near(second.eyes[1].pupil.x, -5)
    equal(provider.defaults.followCursor, true)
end)
test("missing cursor API and invalid coordinates remain neutral", function()
    local previous = GetCursorPosition
    GetCursorPosition = nil
    local value = widget()
    near(value.eyes[1].pupil.x, -8)
    GetCursorPosition = previous; mouseX = 0 / 0
    provider.update(value); near(value.eyes[1].pupil.x, -8)
    mouseX = math.huge
    provider.update(value); near(value.eyes[1].pupil.x, -8)
    mouseX = 10000
end)
test("eye size respects bar height and adapts after height changes", function()
    local value = widget({ size = 24 }, nil, 16)
    equal(value.width, 32)
    equal(value.eyes[1].pupil.height, 3.75)
    value.frame.height = 28; provider.update(value)
    equal(value.width, 56); equal(value.eyes[1].pupil.height, 7.5)
end)
test("obsolete size settings select a usable default", function()
    equal(widget({ size = "removed" }).width, 40)
    equal(widget({ size = 0 / 0 }).width, 40)
end)
test("repeated updates and create calls do not allocate more textures", function()
    local value = widget()
    for i = 1, 100 do provider.update(value) end
    provider.create(value)
    equal(#value.frame.textures, 24)
    equal(value.widthChanges, 1)
end)
test("recovered graphical updates clear the host's previous error label", function()
    local value = widget()
    value:SetText("[Eyes: error]")
    provider.update(value)
    equal(value.text, ""); equal(value.width, 40)
    equal(value.widthChanges, 1)
end)
test("creation can retry and reuse art after a partial allocation failure", function()
    local value = widget(nil, nil, nil, true)
    local original = value.frame.CreateTexture
    function value.frame:CreateTexture(...)
        if #self.textures == 5 then
            self.CreateTexture = original
            error("simulated native allocation failure")
        end
        return original(self, ...)
    end
    local ok = pcall(provider.create, value)
    equal(ok, false); equal(#value.frame.textures, 5)
    provider.create(value); provider.update(value)
    equal(#value.frame.textures, 24)
    for _, texture in ipairs(value.frame.textures) do equal(texture.shown, true) end
end)
test("destroy hides every owned texture and reuse restores them", function()
    local value = widget()
    provider.destroy(value)
    for _, texture in ipairs(value.frame.textures) do equal(texture.shown, false) end
    provider.create(value); provider.update(value)
    for _, texture in ipairs(value.frame.textures) do equal(texture.shown, true) end
    equal(#value.frame.textures, 24)
end)

test("natural iris presets recolour only the standard pupils and remain independent", function()
    local first, second = widget({ iris = "brown" }), widget({ iris = "blue" })
    near(first.eyes[1].pupil.color[1], 0.40)
    near(first.eyes[1].pupil.color[2], 0.23)
    near(second.eyes[1].pupil.color[3], 0.94)
    equal(first.eyes[1].white[1].color[1], 1)
    first.settings.iris = "hazel"; provider.update(first)
    near(first.eyes[1].pupil.color[1], 0.56)
    near(second.eyes[1].pupil.color[3], 0.94)
    equal(provider.defaults.iris, "blue")
end)

test("all six natural and four elven palettes remain selectable", function()
    local count = 0
    for _, setting in ipairs(provider.settings) do
        if setting.key == "iris" then
            count = #setting.options
            for _, choice in ipairs(setting.options) do
                local value = widget({ iris = choice.value })
                assert(value.eyes[1].pupil.shown)
                equal(#value.frame.textures, 24)
            end
        end
    end
    equal(count, 10)
end)

test("elven standard irises keep white sclera and visibly track the cursor", function()
    mouseX, mouseY = 10000, 100
    local value = widget({ iris = "solidGreen" })
    for _, texture in ipairs(value.eyes[1].white) do
        for channel = 1, 3 do equal(texture.color[channel], 1) end
    end
    near(value.eyes[1].pupil.color[1], 0.24)
    near(value.eyes[1].pupil.color[2], 1)
    near(value.eyes[1].spark.x, -6.8)
    near(value.eyes[1].pupil.x, -5.8)
    equal(value.eyes[1].pupil.width, 5)
    equal(value.eyes[1].spark.shown, true)
    mouseX = -10000; provider.update(value)
    near(value.eyes[1].pupil.x, -10.2)
    for _, texture in ipairs(value.eyes[1].white) do equal(texture.color[1], 1) end
end)

test("smooth eyes use only six original alpha textures on initial creation", function()
    local value = widget({ appearance = "smooth", iris = "blue" })
    equal(#value.frame.textures, 6)
    equal(value.width, 40)
    equal(#value.eyes[1].border, 0)
    assert(value.eyes[1].smooth.orb.asset:find("Menubar_Eyes\\Assets\\Orb.tga", 1, true))
    near(value.eyes[1].smooth.iris.vertexColor[3], 0.94)
    equal(value.eyes[1].smooth.orb.shown, true)
    equal(value.eyes[1].smooth.iris.shown, true)
    equal(value.eyes[1].smooth.glint.shown, true)
end)

test("smooth iris travel stays inside the shaded orb at extreme cursor positions", function()
    mouseX, mouseY = 10000, 100
    local value = widget({ appearance = "smooth" })
    near(value.eyes[1].smooth.iris.x, -5.2)
    mouseX, mouseY = 100, 10000
    provider.update(value)
    assert(value.eyes[1].smooth.iris.y > 3.2 and value.eyes[1].smooth.iris.y <= 3.3)
    assert(value.eyes[1].smooth.iris.y + value.eyes[1].smooth.iris.height / 2 < 7)
    visible = false
    provider.update(value)
    near(value.eyes[1].smooth.iris.x, -8)
    near(value.eyes[1].smooth.iris.y, 0)
    visible = true
end)

test("definition switches lazily allocate once and hide the inactive artwork", function()
    local value = widget()
    local firstPixel = value.eyes[1].pupil
    value.settings.appearance = "smooth"; provider.update(value)
    local firstSmooth = value.eyes[1].smooth.orb
    equal(#value.frame.textures, 30)
    equal(firstPixel.shown, false)
    equal(firstSmooth.shown, true)
    for _ = 1, 50 do
        value.settings.appearance = "standard"; provider.update(value)
        equal(firstSmooth.shown, false); equal(firstPixel.shown, true)
        value.settings.appearance = "smooth"; provider.update(value)
        equal(firstPixel.shown, false); equal(firstSmooth.shown, true)
    end
    equal(#value.frame.textures, 30)
    equal(value.eyes[1].pupil, firstPixel)
    equal(value.eyes[1].smooth.orb, firstSmooth)
    equal(value.widthChanges, 1)
end)

test("smooth elven presets keep shaded white sclera and track a uniform coloured iris", function()
    mouseX, mouseY = 10000, 100
    local value = widget({ appearance = "smooth", iris = "solidOrange" })
    local smooth = value.eyes[1].smooth
    for channel = 1, 3 do near(smooth.orb.vertexColor[channel], 1) end
    equal(smooth.iris.shown, true)
    assert(smooth.iris.asset:find("SolidIris.tga", 1, true))
    near(smooth.iris.vertexColor[1], 1)
    near(smooth.iris.vertexColor[2], 0.48)
    near(smooth.iris.x, -5.8)
    equal(smooth.iris.width, 6)
    equal(smooth.glint.shown, true)
    near(smooth.glint.vertexColor[4], 1)
    value.settings.iris = "grey"; provider.update(value)
    equal(smooth.orb.vertexColor[2], 1)
    equal(smooth.iris.shown, true)
    assert(smooth.iris.asset:find("Assets\\Iris.tga", 1, true))
    near(smooth.iris.vertexColor[1], 0.53)
    equal(#value.frame.textures, 6)
end)

test("both artwork sets clean up and only the selected definition returns on reuse", function()
    local value = widget()
    value.settings.appearance = "smooth"; provider.update(value)
    provider.destroy(value)
    for _, texture in ipairs(value.frame.textures) do equal(texture.shown, false) end
    provider.create(value); provider.update(value)
    for _, texture in ipairs(value.eyes[1].border) do equal(texture.shown, false) end
    equal(value.eyes[1].smooth.orb.shown, true)
    equal(value.eyes[1].smooth.iris.shown, true)
    equal(#value.frame.textures, 30)
end)

test("obsolete appearance and palette values safely use the original black eyes", function()
    local value = widget({ appearance = "old-style", iris = "not-a-colour" })
    equal(#value.frame.textures, 24)
    near(value.eyes[1].pupil.color[1], 0.05)
end)

test("shipped smooth geometry has transparent edges and shaded sphere pixels", function()
    local file = assert(io.open("src/menubar-eyes/Assets/Orb.tga", "rb"))
    local data = file:read("*a"); file:close()
    equal(#data, 18 + 64 * 64 * 4)
    equal(data:byte(3), 2); equal(data:byte(17), 32); equal(data:byte(18), 0x28)
    equal(data:byte(22), 0) -- upper-left corner alpha
    local function pixel(x, y) return data:byte(19 + (y * 64 + x) * 4) end
    assert(pixel(22, 22) > pixel(42, 42), "upper-left light should give the orb depth")
    assert(pixel(32, 32) > 220)
end)
test("every solid preset preserves white sclera across style and colour switches", function()
    for _, appearance in ipairs({ "standard", "smooth" }) do
        local value = widget({ appearance = appearance })
        local count = #value.frame.textures
        for _, iris in ipairs({ "solidBlue", "solidOrange", "solidRed", "solidGreen" }) do
            value.settings.iris = iris; provider.update(value)
            for _, eye in ipairs(value.eyes) do
                if appearance == "smooth" then
                    for channel = 1, 3 do equal(eye.smooth.orb.vertexColor[channel], 1) end
                    equal(eye.smooth.iris.shown, true)
                else
                    for _, texture in ipairs(eye.white) do
                        for channel = 1, 3 do equal(texture.color[channel], 1) end
                    end
                end
            end
            equal(#value.frame.textures, count)
        end
    end
end)

test("solid iris asset contains uniform colour and antialiased transparent edges", function()
    local file = assert(io.open("src/menubar-eyes/Assets/SolidIris.tga", "rb"))
    local data = file:read("*a"); file:close()
    equal(#data, 18 + 64 * 64 * 4)
    local function pixel(x, y) return data:byte(19 + (y * 64 + x) * 4) end
    equal(pixel(32, 32), 255)
    equal(pixel(22, 22), 255)
    equal(data:byte(22), 0)
end)

local function glowTextures(value, shownOnly)
    local result = {}
    for _, texture in ipairs(value.frame.textures) do
        if texture.blendMode == "BLEND" and (not shownOnly or texture.shown) then
            result[#result + 1] = texture
        end
    end
    return result
end

local function glowing(options)
    mouseX, mouseY, visible, looking = 10000, 100, true, false
    local settings = { iris = "solidBlue" }
    for key, value in pairs(options or {}) do settings[key] = value end
    local value = widget(settings)
    equal(#glowTextures(value, true), 0)
    mouseX = -10000
    provider.update(value, 0.05)
    assert(#glowTextures(value, true) > 0, "Moving an elven iris should leave a short visible afterimage")
    return value
end

local function maxGlowAlpha(value)
    local alpha = 0
    for _, texture in ipairs(glowTextures(value, true)) do alpha = math.max(alpha, texture:GetAlpha()) end
    return alpha
end

test("elven trails are selectable and natural eyes never allocate glow", function()
    equal(provider.defaults.glowTrails, true)
    local toggle
    for _, setting in ipairs(provider.settings) do
        if setting.key == "glowTrails" then toggle = setting end
    end
    assert(toggle and toggle.type == "toggle")
    mouseX, mouseY = 10000, 100
    local value = widget({ iris = "blue" })
    for _ = 1, 20 do
        mouseX = -mouseX
        provider.update(value, 0.05)
    end
    equal(#glowTextures(value), 0)
    equal(#value.frame.textures, 24)
end)

test("moving elven irises leave matching soft afterimages behind their current positions", function()
    for _, appearance in ipairs({ "standard", "smooth" }) do
        local value = glowing({ appearance = appearance })
        local shown = glowTextures(value, true)
        for _, texture in ipairs(shown) do
            assert(texture.asset:find("Menubar_Eyes\\Assets\\Glint.tga", 1, true))
            near(texture.vertexColor[1], 0.20); near(texture.vertexColor[2], 0.65); near(texture.vertexColor[3], 1)
            assert(texture:GetAlpha() > 0 and texture:GetAlpha() < 1, "Afterimages should not cover the current iris")
            assert(texture.width > 0 and texture.height > 0)
        end
        for _, eye in ipairs(value.eyes) do
            if appearance == "smooth" then
                for channel = 1, 3 do near(eye.smooth.orb.vertexColor[channel], 1) end
            else
                for _, whiteTexture in ipairs(eye.white) do
                    for channel = 1, 3 do near(whiteTexture.color[channel], 1) end
                end
            end
        end
        local current = appearance == "smooth" and value.eyes[1].smooth.iris or value.eyes[1].pupil
        local behind = false
        for _, texture in ipairs(shown) do
            if texture.x < 0 and texture.x > current.x then behind = true end
        end
        assert(behind, "A leftward move should retain a previous point to the right of the current left iris")
    end
end)

test("trails fade with elapsed time after movement stops and expire completely", function()
    local value = glowing()
    local initial = maxGlowAlpha(value)
    provider.update(value, 0.10)
    local faded = maxGlowAlpha(value)
    assert(faded > 0 and faded < initial)
    for _ = 1, 8 do provider.update(value, 0.04) end
    equal(#glowTextures(value, true), 0)
end)

test("trail fading depends on elapsed duration rather than number of updates", function()
    local slow = glowing()
    local fast = glowing()
    provider.update(slow, 0.10)
    for _ = 1, 10 do provider.update(fast, 0.01) end
    near(maxGlowAlpha(slow), maxGlowAlpha(fast))
    equal(#glowTextures(slow, true), #glowTextures(fast, true))
end)

test("continuous movement reuses a bounded pool without allocating on later ticks", function()
    local value = glowing()
    local count, pool = #value.frame.textures, glowTextures(value)
    assert(#pool > 0 and #pool <= 12)
    for index = 1, 200 do
        mouseX, mouseY = index % 2 == 0 and 10000 or -10000, index % 3 == 0 and 10000 or 100
        provider.update(value, 0.04)
        assert(#glowTextures(value, true) <= 12)
    end
    equal(#value.frame.textures, count)
    equal(#glowTextures(value), #pool)
    for index, texture in ipairs(pool) do equal(glowTextures(value)[index], texture) end
end)

test("disabling trails clears them immediately and re-enabling reuses their textures", function()
    local value = glowing()
    local count = #value.frame.textures
    value.settings.glowTrails = false; provider.update(value, 0.04)
    equal(#glowTextures(value, true), 0)
    mouseX = 10000
    provider.update(value, 0.04)
    equal(#glowTextures(value, true), 0)
    value.settings.glowTrails = true; provider.update(value, 0.04)
    equal(#glowTextures(value, true), 0)
    mouseX = -10000; provider.update(value, 0.05)
    assert(#glowTextures(value, true) > 0)
    equal(#value.frame.textures, count)
end)

test("pointer hiding camera turning and disabled tracking erase stale glow", function()
    for _, reason in ipairs({ "hidden", "looking", "tracking" }) do
        local value = glowing()
        if reason == "hidden" then visible = false
        elseif reason == "looking" then looking = true
        else value.settings.followCursor = false end
        provider.update(value, 0.04)
        equal(#glowTextures(value, true), 0)
        visible, looking, value.settings.followCursor = true, false, true
        provider.update(value, 0.04)
        equal(#glowTextures(value, true), 0)
    end
end)

test("colour definition size and layout changes clear old afterimages", function()
    for _, change in ipairs({ "colour", "definition", "size", "layout", "scale" }) do
        local value = glowing()
        if change == "colour" then value.settings.iris = "solidOrange"
        elseif change == "definition" then value.settings.appearance = "smooth"
        elseif change == "size" then value.settings.size = 12
        elseif change == "layout" then value.frame.centerX = 300
        else value.frame.scale = 1.5 end
        provider.update(value, 0.04)
        equal(#glowTextures(value, true), 0)
        mouseX = 10000; provider.update(value, 0.05)
        assert(#glowTextures(value, true) > 0)
        if change == "colour" then
            for _, texture in ipairs(glowTextures(value, true)) do
                near(texture.vertexColor[1], 1); near(texture.vertexColor[2], 0.48)
            end
        end
    end
end)

test("switching to natural eyes clears elf glow and instances keep independent colours", function()
    local blue = glowing()
    local green = glowing({ iris = "solidGreen" })
    blue.settings.iris = "brown"; provider.update(blue, 0.04)
    equal(#glowTextures(blue, true), 0)
    assert(#glowTextures(green, true) > 0)
    for _, texture in ipairs(glowTextures(green, true)) do near(texture.vertexColor[2], 1) end
    equal(provider.defaults.iris, "blue")
end)

test("long pauses and destruction clear history without a streak on reappearance", function()
    local value = glowing()
    mouseX = 10000; provider.update(value, 2)
    equal(#glowTextures(value, true), 0)
    mouseX = -10000; provider.update(value, 0.05)
    assert(#glowTextures(value, true) > 0)
    local count = #value.frame.textures
    provider.destroy(value)
    for _, texture in ipairs(value.frame.textures) do equal(texture.shown, false) end
    provider.create(value); provider.update(value, 0.04)
    equal(#glowTextures(value, true), 0)
    equal(#value.frame.textures, count)
end)

test("host hiding clears traces immediately and hooks only once across creation retries", function()
    local value = glowing()
    equal(#value.frame.hooks.OnHide, 1)
    provider.create(value); provider.create(value)
    equal(#value.frame.hooks.OnHide, 1)
    value.frame:Hide()
    equal(#glowTextures(value, true), 0)
    mouseX = 10000
    provider.update(value, 0.04)
    equal(#glowTextures(value, true), 0)
end)

test("manual refreshes reset animation history instead of creating a false streak", function()
    local value = glowing()
    mouseX = 10000
    provider.update(value)
    equal(#glowTextures(value, true), 0)
    provider.update(value, 0.05)
    equal(#glowTextures(value, true), 0)
end)
test("temporary cursor API failures look forward and recover on the next update", function()
    mouseX, mouseY, visible, looking = 10000, 100, true, false
    local value = widget()
    for _, name in ipairs({ "GetCursorPosition", "IsMouselooking", "IsCursorVisible" }) do
        local previous = _G[name]
        _G[name] = function() error("temporary input failure") end
        local ok, reason = pcall(provider.update, value, 0.05)
        _G[name] = previous
        assert(ok, reason)
        near(value.eyes[1].pupil.x, -8)
        near(value.eyes[2].pupil.x, 8)
        provider.update(value, 0.05)
        near(value.eyes[1].pupil.x, -5)
    end
end)

test("restricted or nonfinite input geometry never reaches texture anchors", function()
    mouseX, mouseY, visible, looking = 10000, 100, true, false
    local secret = setmetatable({}, { __lt = function() error("restricted comparison") end,
        __le = function() error("restricted comparison") end, __div = function() error("restricted arithmetic") end })
    local previousSecret = issecretvalue
    issecretvalue = function(value) return rawequal(value, secret) end
    local value = widget()
    local cases = {
        { name = "IsCursorVisible", read = function() return secret end },
        { name = "IsMouselooking", read = function() return secret end },
        { name = "GetCursorPosition", read = function() return secret, 100 end },
        { name = "GetCursorPosition", read = function() return 100, math.huge end },
    }
    for _, case in ipairs(cases) do
        local previous = _G[case.name]
        _G[case.name] = case.read
        local ok, reason = pcall(provider.update, value, 0.05)
        _G[case.name] = previous
        assert(ok, reason)
        near(value.eyes[1].pupil.x, -8)
    end
    for _, scale in ipairs({ 0 / 0, math.huge, 0, secret, 1e-320 }) do
        value.frame.scale = scale
        provider.update(value, 0.05)
        near(value.eyes[1].pupil.x, -8)
    end
    value.frame.scale = 1
    for _, center in ipairs({ 0 / 0, math.huge, secret }) do
        value.frame.centerX = center
        provider.update(value, 0.05)
        near(value.eyes[1].pupil.x, -8)
    end
    value.frame.centerX = 100
    provider.update(value, 0.05)
    near(value.eyes[1].pupil.x, -5)
    issecretvalue = previousSecret
end)

test("disabled tracking does not query cursor APIs", function()
    local previous, calls = GetCursorPosition, 0
    GetCursorPosition = function() calls = calls + 1; error("disabled tracking should not read input") end
    local ok, value = pcall(widget, { followCursor = false })
    GetCursorPosition = previous
    assert(ok, value)
    equal(calls, 0)
    near(value.eyes[1].pupil.x, -8)
end)

test("reset hides art and recovery restores graphical width after the host error label", function()
    local value = widget()
    local count, widthChanges = #value.frame.textures, value.widthChanges
    assert(type(provider.reset) == "function")
    provider.reset(value, "update")
    for _, texture in ipairs(value.frame.textures) do equal(texture.shown, false) end
    value.customWidth, value.width = nil, 18
    value:SetText("[Eyes: error]")
    provider.update(value)
    equal(value.text, "")
    equal(value.width, 40); equal(value.customWidth, 40)
    equal(value.widthChanges, widthChanges + 1)
    equal(#value.frame.textures, count)
    for _, texture in ipairs(value.frame.textures) do equal(texture.shown, true) end
    -- Reassert the width even if host presentation was cleared before provider reset completed.
    value.customWidth, value.width = nil, 18
    provider.update(value)
    equal(value.width, 40); equal(value.customWidth, 40)
end)

test("partially configured base art stays owned and retries without orphan regions", function()
    for _, appearance in ipairs({ "standard", "smooth" }) do
        local value = widget({ appearance = appearance }, nil, nil, true)
        local original, failed = value.frame.CreateTexture, false
        function value.frame:CreateTexture(...)
            local texture = original(self, ...)
            local method = appearance == "smooth" and "SetTexture" or "SetColorTexture"
            local configure = texture[method]
            texture[method] = function(region, ...)
                region[method] = configure
                if not failed then failed = true; error("temporary art configuration failure") end
                return configure(region, ...)
            end
            return texture
        end
        local ok = pcall(function() provider.create(value); provider.update(value) end)
        equal(ok, false)
        provider.destroy(value)
        for _, texture in ipairs(value.frame.textures) do equal(texture.shown, false) end
        provider.create(value); provider.update(value)
        equal(#value.frame.textures, appearance == "smooth" and 6 or 24)
        for _, texture in ipairs(value.frame.textures) do equal(texture.shown, true) end
    end
end)

test("a partially configured final trail slot is completed when its pool is reused", function()
    mouseX, mouseY, visible, looking = 10000, 100, true, false
    local value = widget({ iris = "solidBlue" })
    local original, extra, failed = value.frame.CreateTexture, 0, false
    function value.frame:CreateTexture(...)
        local texture = original(self, ...)
        extra = extra + 1
        if extra == 6 then
            local configure = texture.SetBlendMode
            texture.SetBlendMode = function(region, ...)
                region.SetBlendMode = configure
                if not failed then failed = true; error("temporary final trail configuration failure") end
                return configure(region, ...)
            end
        end
        return texture
    end
    mouseX = -10000
    equal(pcall(provider.update, value, 0.05), false)
    provider.reset(value, "update")
    for _, texture in ipairs(value.frame.textures) do equal(texture.shown, false) end
    provider.update(value)
    mouseX = 10000; provider.update(value, 0.05)
    equal(#value.frame.textures, 36)
    for _, eye in ipairs(value.eyes) do
        equal(#eye.trails, 6)
        for _, sample in ipairs(eye.trails) do equal(sample.texture.blendMode, "BLEND") end
    end
end)

print(string.format("%d Eyes tests passed", passed))
