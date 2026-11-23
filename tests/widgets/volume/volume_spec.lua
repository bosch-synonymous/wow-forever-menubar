local root = REPO_ROOT or "."
local muteLabel = "|A:voicechat-icon-speaker-mute:14:14|a Mute"
local provider
Menubar = { RegisterWidgetType = function(_, definition) provider = definition end }
local values, writes, reject, ignore, readError, attachmentTypes, exposeValueCallback
local function reset()
    values = { Sound_MasterVolume = "0.5", Sound_EnableAllSound = "1" }
    writes, reject, ignore, readError = {}, false, false, false
    exposeValueCallback = false
    attachmentTypes = { Frame = true, Button = true, CheckButton = true, StatusBar = true, EditBox = true }
    issecretvalue, GetCVar, SetCVar = nil, nil, nil
    Menubar.UI, Menubar.runtime, Menubar.db = nil, nil, nil
    C_CVar = {
        GetCVar = function(name) if readError then error("restricted read") end; return values[name] end,
        SetCVar = function(name, value)
            writes[#writes + 1] = { name, value }
            if reject then return false end
            if not ignore then values[name] = value end
            return true
        end,
    }
end
reset()
dofile(root .. "/src/menubar-volume/Volume.lua")

local tests = 0
local function test(name, run)
    reset()
    local ok, message = pcall(run)
    assert(ok, name .. ": " .. tostring(message))
    tests = tests + 1
    print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function widget(settings, color, deferUpdate)
    local instance = { settings = {} }
    for key, value in pairs(provider.defaults) do instance.settings[key] = value end
    for key, value in pairs(settings or {}) do instance.settings[key] = value end
    instance.label = { textColor = color or { 0, 0, 0, 1 }, points = {}, text = "" }
    function instance.label:GetTextColor() return unpack(self.textColor) end
    function instance.label:SetText(text) self.text = text end
    function instance.label:GetStringWidth() return #self.text * 6 end
    function instance.label:ClearAllPoints() self.points = {} end
    function instance.label:SetPoint(...) self.points[#self.points + 1] = { ... } end
    instance.frame = { textures = {} }
    function instance.frame:CreateTexture()
        local texture = { points = {} }
        function texture:SetTexture(path) self.texture = path end
        function texture:SetVertexColor(...) self.vertexColor = { ... } end
        function texture:SetSize(width, height) self.width, self.height = width, height end
        function texture:ClearAllPoints() self.points = {} end
        function texture:SetPoint(...) self.points[#self.points + 1] = { ... } end
        function texture:Show() self.shown = true end
        function texture:Hide() self.shown = false end
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function instance:SetText(text) self.text = text; self.label:SetText(text) end
    function instance:SetWidth(width)
        self.customWidth, self.width = width, width
        self.widthChanges = (self.widthChanges or 0) + 1
    end
    function instance:Refresh() self.refreshes = (self.refreshes or 0) + 1; provider.update(self) end
    if not deferUpdate then provider.update(instance) end
    return instance
end

local function matchesTextColor(instance)
    local icon = assert(instance.volumeIcon, "Speaker icon must be a tintable native texture")
    assert(icon.shown, "Current speaker state must remain visible")
    for index = 1, 4 do equal(icon.vertexColor[index], instance.label.textColor[index]) end
end

local Region = {}
Region.__index = Region
local function region(kind, parent)
    return setmetatable({ kind = kind, parent = parent, shown = true, children = {}, scripts = {}, points = {} }, Region)
end
function Region:SetSize(width, height) self.width, self.height = width, height end
function Region:GetWidth() return self.width or 0 end
function Region:GetHeight() return self.height or 0 end
function Region:GetParent() return self.parent end
function Region:Show()
    local wasShown = self.shown
    self.shown = true
    if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
    -- Adversarial initialization probe; native exposure need not fire this.
    if exposeValueCallback and self.kind == "Slider" and self.scripts.OnValueChanged then
        self.exposureCallbacks = (self.exposureCallbacks or 0) + 1
        self.scripts.OnValueChanged(self, self.value)
    end
end
function Region:Hide() self.shown = false end
function Region:IsShown() return self.shown end
function Region:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Region:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Region:SetFrameStrata(value) self.strata = value end
function Region:GetFrameStrata() return self.strata or "MEDIUM" end
function Region:SetFrameLevel(value) self.level = value end
function Region:GetFrameLevel() return self.level or 1 end
function Region:SetAlpha(value) self.alpha = value end
function Region:GetAlpha() return self.alpha or 1 end
function Region:SetEnabled(value) self.enabled = value end
function Region:IsEnabled() return self.enabled ~= false end
function Region:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
function Region:SetValueStep(step) self.step = step end
function Region:SetObeyStepOnDrag(value) self.obeyStep = value end
function Region:SetOrientation(value) self.orientation = value end
function Region:EnableMouse(value) self.mouseEnabled = value end
function Region:EnableMouseWheel(value) self.wheelEnabled = value end
function Region:SetAtlas(name, useSize)
    self.atlas, self.useAtlasSize = name, useSize
    -- Representative fixture dimensions, not asserted native atlas constants.
    if name == "Minimal_SliderBar_Button" and useSize then self:SetSize(16, 16) end
    -- The native setter has no return value.
end
function Region:GetAtlas() return self.atlas end
function Region:SetRotation(angle) self.rotation = angle end
function Region:SetDrawLayer(layer) self.layer = layer end
function Region:SetThumbTexture(texture) self.thumb = texture end
function Region:SetFontObject(font) self.font = font end
function Region:SetJustifyH(value) self.justifyH = value end
function Region:SetJustifyV(value) self.justifyV = value end
function Region:SetWordWrap(value) self.wordWrap = value end
function Region:SetText(text) self.text = text end
function Region:SetScript(name, callback) self.scripts[name] = callback end
function Region:SetValue(value)
    value = math.min(self.maximum, math.max(self.minimum, value))
    local changed = self.value ~= value
    self.value = value
    if changed and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function Region:AttachFrame(kind)
    local child = region(kind, self)
    -- Actual client diagnostic: the native Slider is reset below its menu.
    child:SetFrameStrata("MEDIUM"); child:SetFrameLevel(21)
    -- Also exercise stale pooled control state independently of that observation.
    child:SetAlpha(0.25); child:SetEnabled(false)
    child:Show()
    -- Native AcquireFrame shows before the first type's metatable setup hides
    -- its probe. Slider is initially absent from the compositor's warm types.
    if not attachmentTypes[kind] then
        attachmentTypes[kind] = true
        child:Hide()
        child.hiddenDuringAttach = true
    end
    self.children[#self.children + 1] = child
    return child
end
function Region:AttachTexture()
    local child = region("Texture", self); self.children[#self.children + 1] = child
    child:Show(); return child
end
function Region:AttachFontString()
    local child = region("FontString", self); self.children[#self.children + 1] = child
    child:SetSize(150, 1); child.maxLines = 1
    child:SetJustifyH("LEFT"); child:SetJustifyV("MIDDLE")
    child:Show(); return child
end
function Region:NewTicker(interval, callback) self.tick, self.tickInterval = callback, interval end

local function menu(instance, direct)
    local result = { titles = {}, frames = {}, checks = {} }
    function result:CreateTitle(title) self.titles[#self.titles + 1] = title end
    function result:CreateFrame()
        local description = {}
        function description:AddInitializer(callback) self.initialize = callback end
        self.frames[#self.frames + 1] = description
        return description
    end
    function result:CreateCheckbox(label, selected, callback)
        self.checks[#self.checks + 1] = { label = label, selected = selected, callback = callback }
    end
    if direct then
        Menubar.UI = Menubar.UI or {}
        Menubar.UI.Context = function(ui, owner, generate)
            equal(owner, instance.frame)
            result.owner = owner
            ui.contextToken = {}
            generate(result, ui.contextToken)
        end
        provider.click(instance)
    else
        if Menubar.UI then Menubar.UI.contextToken = {} end
        provider.contextMenu(instance, result)
    end
    if result.frames[1] then
        result.frame = region("Frame")
        result.frame:SetFrameStrata("FULLSCREEN_DIALOG"); result.frame:SetFrameLevel(544)
        result.bodyWidth, result.bodyHeight = result.frames[1].initialize(result.frame)
        if result.bodyWidth and result.bodyHeight then result.frame:SetSize(result.bodyWidth, result.bodyHeight) end
        for _, child in ipairs(result.frame.children) do
            if child.kind == "Slider" then result.slider = child end
        end
    end
    return result
end

local function visibleControls(result)
    local slider = assert(result.slider, "The managed menu needs a real slider")
    assert(slider:IsShown() and slider:IsVisible(), "The configured slider must be shown after cold attachment")
    assert(slider.mouseEnabled and slider.wheelEnabled, "The visible slider must accept drag and wheel input")
    equal(slider:GetFrameStrata(), result.frame:GetFrameStrata())
    assert(slider:GetFrameLevel() > result.frame:GetFrameLevel(), "Slider art must draw above the popup background")
    equal(slider:GetAlpha(), 1); equal(slider:IsEnabled(), true)
    assert(slider:GetWidth() > 0 and slider:GetHeight() > 0, "The slider needs a positive input rectangle")
    equal(slider:GetParent(), result.frame)
    equal(slider.points[1][2], result.frame)
    assert(result.frame:GetWidth() >= slider:GetWidth() and result.frame:GetHeight() >= slider:GetHeight())
    assert(result.bodyWidth and result.bodyHeight, "The native menu needs an explicit size override")
    equal(result.bodyWidth, result.frame:GetWidth()); equal(result.bodyHeight, result.frame:GetHeight())
    local thumb, track = assert(slider.thumb)
    for _, child in ipairs(slider.children) do if child.kind == "Texture" and child ~= thumb then track = child; break end end
    assert(track and track:IsVisible() and thumb:IsVisible(), "Track and thumb must be visible through their slider parent")
    equal(track:GetParent(), slider); equal(thumb:GetParent(), slider)
    equal(track:GetAtlas(), "_Minimal_SliderBar_Middle")
    equal(thumb:GetAtlas(), "Minimal_SliderBar_Button"); equal(thumb.useAtlasSize, true)
    assert(track:GetWidth() > 0 and track:GetHeight() > 0 and thumb:GetWidth() > 0 and thumb:GetHeight() > 0)
    local rotation = track.rotation or 0
    local visualWidth = math.abs(math.cos(rotation)) * track:GetWidth() + math.abs(math.sin(rotation)) * track:GetHeight()
    local visualHeight = math.abs(math.sin(rotation)) * track:GetWidth() + math.abs(math.cos(rotation)) * track:GetHeight()
    assert(visualWidth <= slider:GetWidth() + 0.00001 and visualHeight <= slider:GetHeight() + 0.00001,
        "The rotated track must fit the slider's interactive rectangle")
end

test("registers public audio settings and defaults to an icon plus percentage", function()
    equal(provider.id, "volume")
    equal(provider.defaults.showPercent, true)
    equal(provider.events[1], "CVAR_UPDATE")
    local instance = widget()
    assert(instance.volumeIcon.texture:find("volume%-medium%.tga"))
    assert(instance.text:find("50%%$"))
    equal(#writes, 0)
end)

test("speaker state follows mute low medium and high volume", function()
    local instance = widget()
    for _, sample in ipairs({ { 0, "muted" }, { 0.2, "low" }, { 0.5, "medium" }, { 0.9, "high" } }) do
        values.Sound_MasterVolume = tostring(sample[1])
        provider.update(instance)
        assert(instance.volumeIcon.texture:find("volume%-" .. sample[2] .. "%.tga"))
    end
    values.Sound_MasterVolume, values.Sound_EnableAllSound = "0.75", "0"
    provider.update(instance)
    assert(instance.volumeIcon.texture:find("volume%-muted%.tga"))
    assert(instance.text:find("75%%$"))
end)

test("percentage can be hidden without changing the master preference", function()
    local instance = widget({ showPercent = false })
    equal(instance.text, "Volume")
    equal(instance.label.text, "")
    equal(instance.width, 24)
    equal(values.Sound_MasterVolume, "0.5")
    equal(#writes, 0)
end)

test("all speaker states use the current text colour on light dark and custom profiles", function()
    local instance = widget()
    for _, color in ipairs({ { 0, 0, 0, 1 }, { 1, 1, 1, 1 }, { 1, 0.82, 0, 1 }, { 0.2, 0.6, 0.9, 0.7 } }) do
        instance.label.textColor = color
        for _, state in ipairs({ { 0, "muted" }, { 0.2, "low" }, { 0.5, "medium" }, { 0.9, "high" } }) do
            values.Sound_MasterVolume = tostring(state[1])
            provider.update(instance)
            assert(instance.volumeIcon.texture:find("volume%-" .. state[2] .. "%.tga"))
            matchesTextColor(instance)
        end
    end
    equal(#writes, 0)
end)

test("refreshing an existing icon follows a new text colour even when percentage is hidden", function()
    local instance = widget({ showPercent = false }, { 0, 0, 0, 1 })
    matchesTextColor(instance)
    instance.label.textColor = { 1, 1, 1, 1 }
    provider.update(instance)
    matchesTextColor(instance)
    equal(instance.text, "Volume")
    equal(instance.label.text, "")
    instance.label.textColor = { 0.25, 0.75, 0.5, 0.8 }
    instance.settings.showPercent = true
    provider.update(instance)
    matchesTextColor(instance)
    assert(instance.text:find("50%%$"))
    equal(values.Sound_MasterVolume, "0.5")
    equal(#writes, 0)
end)

test("theme updates reuse one icon and keep its visible text separate from overflow metadata", function()
    local instance = widget()
    local icon, widths = instance.volumeIcon, instance.widthChanges
    equal(instance.text, "Volume 50%")
    equal(instance.label.text, "50%")
    for index = 1, 20 do
        instance.label.textColor = index % 2 == 0 and { 1, 1, 1, 1 } or { 1, 0.82, 0, 1 }
        provider.update(instance)
        equal(instance.volumeIcon, icon); matchesTextColor(instance)
    end
    equal(#instance.frame.textures, 1)
    equal(instance.widthChanges, widths)
    provider.destroy(instance)
    equal(icon.shown, false)
    provider.update(instance)
    equal(instance.volumeIcon, icon); equal(icon.shown, true)
    equal(#instance.frame.textures, 1)
    equal(#writes, 0)
end)

test("mouse wheel adjusts master with bounded integer steps", function()
    local instance = widget()
    provider.mouseWheel(instance, 1)
    equal(tonumber(values.Sound_MasterVolume), 0.55)
    provider.mouseWheel(instance, -1)
    equal(tonumber(values.Sound_MasterVolume), 0.5)
    values.Sound_MasterVolume = "0.99"
    provider.mouseWheel(instance, 1)
    equal(tonumber(values.Sound_MasterVolume), 1)
    values.Sound_MasterVolume = "0.01"
    provider.mouseWheel(instance, -1)
    equal(tonumber(values.Sound_MasterVolume), 0)
    equal(#writes, 4)
end)

test("separate instances keep wheel and display choices while controlling shared audio", function()
    local first = widget({ wheelStep = 10 })
    local second = widget({ showPercent = false, wheelStep = 1 })
    provider.mouseWheel(first, 1)
    provider.mouseWheel(second, -1)
    equal(tonumber(values.Sound_MasterVolume), 0.59)
    equal(first.settings.wheelStep, 10)
    equal(second.settings.wheelStep, 1)
    provider.update(first)
    assert(first.text:find("59%%$"))
    equal(second.text, "Volume")
end)

test("invalid wheel preferences use a safe default and zero wheel does nothing", function()
    local instance = widget({ wheelStep = 200 })
    provider.mouseWheel(instance, 0)
    equal(#writes, 0)
    provider.mouseWheel(instance, 1)
    equal(tonumber(values.Sound_MasterVolume), 0.55)
end)

test("missing malformed or restricted reads stay unavailable without writes", function()
    local instance = widget()
    for _, value in ipairs({ "bad", -0.1, 2, math.huge, 0 / 0 }) do
        values.Sound_MasterVolume = value
        provider.update(instance)
        assert(instance.text:find(" %-%-$"))
        provider.mouseWheel(instance, 1)
    end
    values.Sound_MasterVolume = 0.5
    issecretvalue = function(value) return value == 0.5 end
    provider.update(instance)
    assert(instance.text:find(" %-%-$"))
    provider.mouseWheel(instance, 1)
    issecretvalue = nil
    C_CVar = nil
    provider.update(instance)
    assert(instance.text:find(" %-%-$"))
    equal(#writes, 0)
end)

test("temporarily failing reads can recover on the next refresh", function()
    local instance = widget()
    readError = true
    provider.update(instance)
    assert(instance.text:find(" %-%-$"))
    readError = false
    provider.update(instance)
    assert(instance.text:find("50%%$"))
end)

test("rejected or ignored writes are reported without inventing a new volume", function()
    local instance = widget()
    reject = true
    provider.mouseWheel(instance, 1)
    equal(values.Sound_MasterVolume, "0.5")
    assert(instance.volumeMessage)
    reject, ignore = false, true
    provider.mouseWheel(instance, 1)
    equal(values.Sound_MasterVolume, "0.5")
    assert(instance.volumeMessage)
    ignore = false
    provider.mouseWheel(instance, 1)
    equal(tonumber(values.Sound_MasterVolume), 0.55)
    equal(instance.volumeMessage, nil)
end)

test("horizontal context slider initializes without changing volume and adjusts live", function()
    local instance = widget()
    local result = menu(instance)
    equal(result.slider.orientation, "HORIZONTAL")
    equal(result.slider.value, 50)
    equal(result.slider.step, 1)
    equal(result.frame.tickInterval, 0.25)
    equal(#writes, 0)
    result.slider:SetValue(73)
    equal(tonumber(values.Sound_MasterVolume), 0.73)
    assert(instance.text:find("73%%$"))
    equal(result.slider.thumb.atlas, "Minimal_SliderBar_Button")
end)

test("vertical context slider reverses native values so louder is upward", function()
    values.Sound_MasterVolume = "0.75"
    local result = menu(widget({ orientation = "vertical" }))
    equal(result.slider.orientation, "VERTICAL")
    equal(result.slider.value, 25)
    assert(result.slider.height > result.slider.width)
    result.slider:SetValue(0)
    equal(tonumber(values.Sound_MasterVolume), 1)
    result.slider:SetValue(100)
    equal(tonumber(values.Sound_MasterVolume), 0)
end)

test("plain left click opens vertical drag wheel and mute controls without changing orientation or audio on open", function()
    local instance = widget({ orientation = "horizontal" })
    local opened = menu(instance, true)
    equal(provider.clickHint, "Volume controls")
    equal(opened.owner, instance.frame)
    equal(opened.slider.orientation, "VERTICAL")
    equal(opened.slider.value, 50)
    assert(opened.slider.height > opened.slider.width and opened.slider.wheelEnabled)
    equal(instance.settings.orientation, "horizontal")
    equal(#writes, 0)
    opened.slider:SetValue(20)
    equal(tonumber(values.Sound_MasterVolume), 0.8)
    opened.slider.scripts.OnMouseWheel(opened.slider, -1)
    equal(tonumber(values.Sound_MasterVolume), 0.75)
    equal(opened.slider.value, 25)
    opened.checks[1].callback()
    equal(tonumber(values.Sound_EnableAllSound), 0)
    equal(tonumber(values.Sound_MasterVolume), 0.75)
    opened.checks[1].callback()
    equal(tonumber(values.Sound_EnableAllSound), 1)
    equal(menu(instance).slider.orientation, "HORIZONTAL")
    equal(instance.settings.orientation, "horizontal")
end)

test("cold and warm menu attachments show the slider track and thumb in both orientations", function()
    exposeValueCallback = true
    local instance = widget({ orientation = "horizontal" })
    local first = menu(instance, true)
    equal(first.slider.hiddenDuringAttach, true)
    equal(first.slider.exposureCallbacks, 1)
    visibleControls(first)
    first.frame:Hide(); equal(first.slider:IsVisible(), false)
    local horizontal = menu(instance)
    equal(horizontal.slider.hiddenDuringAttach, nil)
    equal(horizontal.slider.orientation, "HORIZONTAL"); visibleControls(horizontal)
    horizontal.frame:Hide()
    instance.settings.orientation = "vertical"
    local vertical = menu(instance)
    equal(vertical.slider.hiddenDuringAttach, nil)
    equal(vertical.slider.orientation, "VERTICAL"); visibleControls(vertical)
    equal(#writes, 0)
    first.slider.scripts.OnValueChanged(first.slider, 0)
    first.slider.scripts.OnMouseWheel(first.slider, 1); first.checks[1].callback()
    equal(#writes, 0)
    vertical.slider:SetValue(20); equal(tonumber(values.Sound_MasterVolume), 0.8)
    vertical.slider.scripts.OnMouseWheel(vertical.slider, -1); equal(tonumber(values.Sound_MasterVolume), 0.75)
    vertical.checks[1].callback(); equal(tonumber(values.Sound_EnableAllSound), 0)
end)

test("compact controls follow native menu depth changes without writing volume", function()
    local instance = widget()
    local opened = menu(instance, true)
    visibleControls(opened)
    equal(opened.titles[1], "Volume")
    equal(opened.checks[1].label, muteLabel)
    assert(opened.frame:GetWidth() < 100 and opened.frame:GetHeight() < 190,
        "The vertical control should leave less empty popup space")
    local percent
    for _, child in ipairs(opened.frame.children) do
        if child.kind == "FontString" and child.text == "50%" then percent = child end
    end
    assert(percent, "The current value should use a compact percentage label")
    equal(percent.points[1][1], "LEFT"); equal(percent.points[1][2], opened.slider)
    equal(percent.points[1][3], "RIGHT")
    for _, label in ipairs(opened.frame.children) do
        if label.kind == "FontString" then
            assert(label:GetWidth() < opened.frame:GetWidth() and label:GetHeight() >= 12,
                "Managed labels must override the native 150-wide, one-unit-high defaults")
            equal(label.justifyH, "CENTER"); equal(label.justifyV, "MIDDLE"); equal(label.wordWrap, false)
        end
    end
    local before = #writes
    -- Native menu opening raises the parent after element initialization.
    opened.frame:SetFrameLevel(1044)
    opened.slider.scripts.OnShow(opened.slider)
    equal(opened.slider:GetFrameLevel(), 1045)
    opened.frame:SetFrameLevel(1544); opened.frame:SetFrameStrata("TOOLTIP")
    opened.frame.tick()
    equal(opened.slider:GetFrameLevel(), 1545)
    equal(opened.slider:GetFrameStrata(), "TOOLTIP")
    equal(#writes, before)
end)

test("reopening a volume menu invalidates old slider wheel mute and ticker callbacks", function()
    local instance = widget()
    local old = menu(instance, true)
    local current = menu(instance, true)
    local previousValue = old.slider.value
    old.slider.scripts.OnValueChanged(old.slider, 0)
    old.slider.scripts.OnMouseWheel(old.slider, 1)
    old.checks[1].callback()
    values.Sound_MasterVolume = "0.6"
    old.frame.tick()
    local staleFrame = region("Frame")
    old.frames[1].initialize(staleFrame)
    equal(#staleFrame.children, 0)
    equal(old.slider.value, previousValue)
    equal(old.checks[1].selected(), false)
    equal(#writes, 0)
    current.frame.tick()
    equal(current.slider.value, 40)
    current.slider.scripts.OnMouseWheel(current.slider, 1)
    equal(tonumber(values.Sound_MasterVolume), 0.65)
    equal(#writes, 1)
end)

test("removed replaced failed reset and switched-database owners cannot write through old controls", function()
    for _, state in ipairs({ "removed", "replaced", "settings", "instance", "database", "failed", "reset" }) do
        local instance = widget(); instance.id = "volume-owner"
        instance.instance = { settings = instance.settings }
        Menubar.runtime, Menubar.db = { [instance.id] = instance }, {}
        local opened = menu(instance, true)
        if state == "removed" then Menubar.runtime[instance.id] = nil
        elseif state == "replaced" then Menubar.runtime[instance.id] = {}
        elseif state == "settings" then instance.settings = {}
        elseif state == "instance" then instance.instance = {}
        elseif state == "database" then Menubar.db = {}
        elseif state == "failed" then instance.failed = "render failed"
        else provider.reset(instance) end
        opened.slider.scripts.OnValueChanged(opened.slider, 0)
        opened.slider.scripts.OnMouseWheel(opened.slider, 1)
        opened.checks[1].callback()
        opened.frame.tick()
        equal(#writes, 0)
        equal(values.Sound_MasterVolume, "0.5")
        equal(values.Sound_EnableAllSound, "1")
        Menubar.runtime, Menubar.db = nil, nil
    end
end)

test("unavailable direct menu hosts leave audio and preferences intact and recover when a host is available", function()
    local instance = widget({ orientation = "horizontal" })
    provider.click(instance)
    assert(instance.volumeMessage:find("Update Menubar", 1, true))
    equal(instance.settings.orientation, "horizontal")
    equal(#writes, 0)
    local opened = menu(instance, true)
    equal(opened.slider.orientation, "VERTICAL")
    equal(instance.volumeMessage, nil)
    equal(#writes, 0)
end)

test("another widget menu and a host rebuild invalidate old audio callbacks", function()
    local instance = widget()
    for _, state in ipairs({ "other menu", "rebuild" }) do
        local opened = menu(instance, true)
        if state == "rebuild" then Menubar.UI.contextToken = nil else Menubar.UI.contextToken = {} end
        opened.slider.scripts.OnValueChanged(opened.slider, 0)
        opened.slider.scripts.OnMouseWheel(opened.slider, 1)
        opened.checks[1].callback()
        opened.frame.tick()
        equal(#writes, 0)
        equal(values.Sound_MasterVolume, "0.5")
    end
end)

test("open menu follows external volume changes without write feedback", function()
    local result = menu(widget())
    values.Sound_MasterVolume = "0.8"
    result.frame.tick()
    equal(result.slider.value, 80)
    equal(#writes, 0)
    result.slider.scripts.OnMouseWheel(result.slider, -1)
    equal(tonumber(values.Sound_MasterVolume), 0.75)
    equal(result.slider.value, 75)
end)

test("mute control preserves the master setting and ordinary wheel respects mute", function()
    local instance = widget()
    local result = menu(instance)
    equal(result.checks[1].selected(), false)
    result.checks[1].callback()
    equal(tonumber(values.Sound_EnableAllSound), 0)
    equal(tonumber(values.Sound_MasterVolume), 0.5)
    provider.mouseWheel(instance, 1)
    equal(tonumber(values.Sound_MasterVolume), 0.55)
    equal(tonumber(values.Sound_EnableAllSound), 0)
    result.checks[1].callback()
    equal(tonumber(values.Sound_EnableAllSound), 1)
    equal(tonumber(values.Sound_MasterVolume), 0.55)
end)

test("missing enable state does not falsely report a mute or offer a mute control", function()
    values.Sound_EnableAllSound = nil
    local instance = widget()
    assert(instance.volumeIcon.texture:find("volume%-medium%.tga"))
    equal(#menu(instance).checks, 0)
    local tip = { rows = {} }
    function tip:AddLine() end
    function tip:AddDoubleLine(left, right) self.rows[left] = right end
    provider.tooltip(instance, tip)
    equal(tip.rows["Game sound"], "Unavailable")
end)

test("unavailable volume retains common context flow without an interactive slider", function()
    values.Sound_MasterVolume = nil
    local result = menu(widget())
    equal(#result.frames, 0)
    equal(result.titles[2], "Volume is currently unavailable.")
end)

test("tooltip distinguishes master setting mute and rejected changes", function()
    local instance = widget()
    values.Sound_EnableAllSound = "0"
    reject = true
    provider.mouseWheel(instance, 1)
    local tip = { lines = {}, rows = {} }
    function tip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tip:AddDoubleLine(left, right) self.rows[left] = right end
    provider.tooltip(instance, tip)
    equal(tip.rows.Master, "50%")
    equal(tip.rows["Game sound"], "Muted")
    equal(tip.lines[#tip.lines], instance.volumeMessage)
    for _, line in ipairs(tip.lines) do assert(not line:find("Mouse wheel", 1, true), "The shared footer owns wheel instructions") end
    equal(provider.wheelHint, "Volume")
end)

test("runtime icons are original complete 32-bit transparent TGA files", function()
    for _, name in ipairs({ "muted", "low", "medium", "high" }) do
        local file = assert(io.open(root .. "/src/menubar-volume/Media/volume-" .. name .. ".tga", "rb"))
        local data = file:read("*a"); file:close()
        equal(#data, 18 + 32 * 32 * 4)
        equal(data:byte(3), 2)
        equal(data:byte(17), 32)
        equal(data:byte(18), 40)
    end
end)

test("neutral speaker assets preserve their antialiased silhouettes while accepting any tint", function()
    local signatures = {
        muted = { 35830, 18327972 }, low = { 29166, 14839382 },
        medium = { 38124, 19520426 }, high = { 48454, 24962422 },
    }
    for name, expected in pairs(signatures) do
        local file = assert(io.open(root .. "/src/menubar-volume/Media/volume-" .. name .. ".tga", "rb"))
        local data = file:read("*a"); file:close()
        local alphaSum, weightedAlpha = 0, 0
        for pixel = 0, 1023 do
            local offset = 19 + pixel * 4
            local blue, green, red, alpha = data:byte(offset, offset + 3)
            if alpha > 0 then
                equal(red, 255); equal(green, 255); equal(blue, 255)
            end
            alphaSum = alphaSum + alpha
            weightedAlpha = weightedAlpha + (pixel + 1) * alpha
        end
        equal(alphaSum, expected[1]); equal(weightedAlpha, expected[2])
    end
end)

test("malformed sound-enabled values remain unknown and never offer a mute write", function()
    local secret = {}
    issecretvalue = function(value) return rawequal(value, secret) end
    for _, enabled in ipairs({ "2", "-1", "0.5", "invalid", math.huge, secret }) do
        values.Sound_EnableAllSound = enabled
        local instance = widget()
        assert(instance.volumeIcon.texture:find("volume%-medium%.tga"))
        equal(#menu(instance).checks, 0)
        local tip = { rows = {} }
        function tip:AddLine() end
        function tip:AddDoubleLine(key, value) self.rows[key] = value end
        provider.tooltip(instance, tip)
        equal(tip.rows["Game sound"], "Unavailable")
    end
    equal(#writes, 0)
end)

test("callable legacy CVar APIs support absent or incomplete modern namespaces", function()
    local legacyReads = 0
    GetCVar = function(name) legacyReads = legacyReads + 1; return values[name] end
    SetCVar = function(name, value) writes[#writes + 1] = { name, value }; values[name] = value; return true end
    for _, namespace in ipairs({ false, "unavailable", {}, { GetCVar = false, SetCVar = {} } }) do
        C_CVar = namespace or nil
        values.Sound_MasterVolume, writes = "0.5", {}
        local instance = widget()
        equal(instance.label.text, "50%")
        provider.mouseWheel(instance, 1)
        equal(tonumber(values.Sound_MasterVolume), 0.55)
        equal(#writes, 1)
    end
    assert(legacyReads > 0)
    -- A present modern getter returning restricted data remains authoritative.
    local secret = {}
    issecretvalue = function(value) return rawequal(value, secret) end
    C_CVar = { GetCVar = function() return secret end }
    GetCVar = function() error("Do not bypass a restricted modern read") end
    equal(widget().label.text, "--")
end)

test("an open mute checkbox refuses writes after its enable state becomes unavailable", function()
    local instance = widget()
    local result = menu(instance)
    equal(#result.checks, 1)
    values.Sound_EnableAllSound = nil
    result.checks[1].callback()
    equal(#writes, 0)
    assert(instance.volumeMessage:find("unavailable", 1, true))
    local secret = {}
    issecretvalue = function(value) return rawequal(value, secret) end
    values.Sound_EnableAllSound = secret
    result.checks[1].callback()
    equal(#writes, 0)
    values.Sound_EnableAllSound, issecretvalue = "1", nil
    result.checks[1].callback()
    equal(#writes, 1)
    equal(values.Sound_EnableAllSound, "0")
end)

test("vertical slider validates values before reversing their arithmetic", function()
    local instance = widget({ orientation = "vertical" })
    local result = menu(instance)
    local secret = setmetatable({}, { __sub = function() error("restricted subtraction") end })
    issecretvalue = function(value) return rawequal(value, secret) end
    for _, value in ipairs({ secret, 0 / 0, math.huge, "unavailable", false }) do
        result.slider.scripts.OnValueChanged(result.slider, value)
    end
    result.slider.scripts.OnValueChanged(result.slider, nil)
    equal(#writes, 0)
    equal(values.Sound_MasterVolume, "0.5")
    result.slider.scripts.OnValueChanged(result.slider, 60)
    equal(#writes, 1)
    equal(tonumber(values.Sound_MasterVolume), 0.4)
    assert(type(provider.reset) == "function")
    provider.reset(instance, "update")
    equal(instance.volumeIcon.shown, false)
    provider.update(instance)
    equal(instance.volumeIcon.shown, true)
    equal(instance.customWidth, instance.width)
end)

test("partially configured icon stays owned and finishes setup without reallocating", function()
    local instance = widget(nil, nil, true)
    local allocate = instance.frame.CreateTexture
    instance.frame.CreateTexture = function(frame)
        local texture = allocate(frame)
        local position = texture.SetPoint
        texture.SetPoint = function(self, ...)
            self.SetPoint = position
            position(self, ...)
            error("temporary icon position failure")
        end
        return texture
    end
    local ok = pcall(provider.update, instance)
    equal(ok, false)
    local texture = assert(instance.volumeIcon)
    equal(texture.shown, false)
    equal(instance.volumeIconReady, nil)
    provider.update(instance)
    equal(instance.volumeIcon, texture)
    equal(#instance.frame.textures, 1)
    equal(texture.width, 16)
    equal(texture.height, 16)
    equal(#texture.points, 1)
    equal(texture.points[1][1], "LEFT")
    equal(texture.points[1][4], 4)
    equal(instance.volumeIconReady, true)
    equal(texture.shown, true)
end)

test("an open volume slider refuses writes while master state becomes unreadable", function()
    local instance = widget()
    local opened = menu(instance)
    readError = true
    opened.slider.scripts.OnValueChanged(opened.slider, 60)
    equal(#writes, 0)
    equal(instance.volumeMessage, "Game audio controls are unavailable.")
    readError = false
    local secret = {}
    issecretvalue = function(value) return rawequal(value, secret) end
    values.Sound_MasterVolume = secret
    opened.slider.scripts.OnValueChanged(opened.slider, 70)
    equal(#writes, 0)
    values.Sound_MasterVolume = "0.5"
    opened.slider.scripts.OnValueChanged(opened.slider, 60)
    equal(#writes, 1)
    equal(values.Sound_MasterVolume, "0.6")
    equal(instance.volumeMessage, nil)
end)

print(tests .. " Volume tests passed")
