local sourceDirectory = dofile((REPO_ROOT or ".") .. "/tests/source_paths.lua")
-- Real host/provider lifecycle regressions. Native behavior still needs the client.
local root = REPO_ROOT or "."
local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end
local function providerPath(id, addon, file)
    local providerRoot = _G["MENUBAR_" .. id:upper() .. "_ROOT"] or root
    local path = sourceDirectory(providerRoot, addon) .. "/" .. file
    if exists(path) then return path end
end
local eyesPath = providerPath("eyes", "Menubar_Eyes", "Eyes.lua")
local volumePath = providerPath("volume", "Menubar_Volume", "Volume.lua")
if not eyesPath or not volumePath then
    print("SKIP graphical reset integration: supply Eyes and Volume repository roots.")
    return
end

local Stub = dofile(root .. "/tests/wow_stub.lua")
Stub.Install()
local pointerX, pointerY = 1000, 100
GetCursorPosition = function() return pointerX, pointerY end
IsCursorVisible = function() return true end
IsMouselooking = function() return false end
local audio = { Sound_MasterVolume = "0.5", Sound_EnableAllSound = "1" }
local writes = 0
C_CVar = {
    GetCVar = function(name) return audio[name] end,
    SetCVar = function(name, value) writes = writes + 1; audio[name] = value; return true end,
}
for _, file in ipairs({ "Model.lua", "Identity.lua", "Fonts.lua", "Layout.lua", "Gauge.lua", "Skins.lua", "Core.lua", "UI.lua", "Settings.lua" }) do
    dofile(root .. "/src/menubar-core/" .. file)
end
dofile(eyesPath)
dofile(volumePath)
Menubar:Start()

local passed = 0
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1
    print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.0000001,
        "expected approximately " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function shiftLeftClick(frame)
    local previous = IsShiftKeyDown
    IsShiftKeyDown = function() return true end
    local ok, reason = pcall(frame.Click, frame, "LeftButton")
    IsShiftKeyDown = previous
    if not ok then error(reason, 0) end
end
local function widget(kind)
    for _, value in pairs(Menubar.runtime) do
        if value.instance.type == kind then return value end
    end
    error("Missing " .. kind .. " widget")
end
local function tick(elapsed)
    Menubar.eventFrame.scripts.OnUpdate(Menubar.eventFrame, elapsed)
end
local function eyeTextures(value)
    local result = {}
    for _, eye in ipairs(value.eyes) do
        for _, texture in ipairs(eye.border) do result[#result + 1] = texture end
        for _, texture in ipairs(eye.white) do result[#result + 1] = texture end
        if eye.pupil then result[#result + 1] = eye.pupil end
        if eye.spark then result[#result + 1] = eye.spark end
        for _, texture in pairs(eye.smooth or {}) do result[#result + 1] = texture end
        for _, sample in ipairs(eye.trails or {}) do result[#result + 1] = sample.texture end
    end
    return result
end
local function errorPresentation(value)
    assert(value.failed and value.text:find("error", 1, true))
    equal(value.customWidth, nil)
    equal(#value.label.points, 1)
    equal(value.label.points[1][1], "CENTER")
    assert(value.label:IsShown())
    assert(value.frame:GetWidth() >= value.label:GetStringWidth() + 8)
    equal(value.label.fontSize, Menubar:GetProfile().fontSize)
    equal(value.label.fontFlags, "")
end

check("actual host reset hides Eyes artwork and recovers its original width without replacement textures", function()
    local value = widget("eyes")
    -- Warm both presentations so reset must release every kind of artwork,
    -- independently of which presentation the factory starts with.
    value.settings.iris, value.settings.appearance = "black", "standard"
    Menubar:RefreshWidget(value.id); Menubar:Layout()
    value.settings.iris, value.settings.appearance = "solidBlue", "smooth"
    Menubar:RefreshWidget(value.id); Menubar:Layout()
    tick(0.04)
    pointerX = -1000
    tick(0.05)
    equal(#eyeTextures(value), 42)
    local textures, frames, width = #Stub.textures, #Stub.frames, value.width
    local definition, resets, failedCallback = value.definition, 0, nil
    local reset = definition.reset
    definition.reset = function(current, callback)
        resets, failedCallback = resets + 1, callback
        return reset(current, callback)
    end
    local iris = value.eyes[1].smooth.iris
    local setPoint = iris.SetPoint
    iris.SetPoint = function(self, ...)
        self.SetPoint = setPoint
        error("simulated iris anchor failure", 0)
    end
    tick(0.04)
    equal(resets, 1)
    equal(failedCallback, "update")
    equal(value.failed, "simulated iris anchor failure")
    errorPresentation(value)
    for _, texture in ipairs(eyeTextures(value)) do assert(not texture:IsShown()) end
    tick(0.1)
    equal(resets, 1)
    Menubar:RefreshWidget(value.id); Menubar:Layout()
    equal(value.failed, nil)
    equal(value.failedCallback, nil)
    equal(value.text, "")
    equal(value.width, width)
    equal(value.customWidth, width)
    assert(value.eyes[1].smooth.orb:IsVisible() and iris:IsVisible())
    equal(#Stub.textures, textures)
    equal(#Stub.frames, frames)
    definition.reset = reset
end)

check("a Volume menu failure uses host reset outside the local redraw boundary and refresh reuses its icon", function()
    local value = widget("volume")
    local definition, icon, width = value.definition, value.volumeIcon, value.width
    local textures, frames = #Stub.textures, #Stub.frames
    local reset, contextMenu = definition.reset, definition.contextMenu
    local resets, callback = 0, nil
    definition.reset = function(current, failedCallback)
        resets, callback = resets + 1, failedCallback
        return reset(current, failedCallback)
    end
    definition.contextMenu = function() error("simulated volume menu failure", 0) end
    shiftLeftClick(value.frame)
    -- A first bar menu lazily creates one bar anchor and the native pooled
    -- menu frame. Neither allocation belongs to the provider's icon recovery.
    local anchor = assert(Menubar.UI.menuAnchors[Menubar:EffectiveBar(value.instance)])
    local nativeMenu = assert(Stub.menus[#Stub.menus].menuFrame)
    assert(#Stub.frames <= frames + 2, "Only the bar anchor and native menu pool may initialize")
    for index = frames + 1, #Stub.frames do
        assert(Stub.frames[index] == anchor or Stub.frames[index] == nativeMenu,
            "Unexpected frame allocation during provider failure recovery")
    end
    frames = #Stub.frames
    equal(resets, 1)
    equal(callback, "contextMenu")
    equal(value.failed, "simulated volume menu failure")
    assert(not icon:IsShown())
    errorPresentation(value)
    definition.contextMenu = contextMenu
    Menubar:RefreshWidget(value.id); Menubar:Layout()
    equal(value.failed, nil)
    equal(value.volumeIcon, icon)
    equal(value.width, width)
    equal(value.customWidth, width)
    equal(value.label.points[1][1], "LEFT")
    equal(value.label:GetText(), "50%")
    assert(icon:IsVisible())
    equal(#Stub.textures, textures)
    equal(#Stub.frames, frames)
    equal(writes, 0)
    definition.reset = reset
end)

check("actual host presentation cleanup hides a failed gauge and reuses it on explicit recovery", function()
    local fail, resets = false, 0
    Menubar:RegisterWidgetType({
        id = "reset-gauge", name = "Reset gauge", defaultPlacement = false,
        defaults = { gaugeStyle = "warcraft" },
        update = function(value)
            value:SetGauge(25, 100, { 0, 0.5, 1, 1 }, "Progress", 160)
            if fail then error("simulated gauge provider failure", 0) end
        end,
        reset = function(_, callback) equal(callback, "update"); resets = resets + 1 end,
    })
    local instance = Menubar:AddWidget("reset-gauge", "top", "left")
    local value = Menubar.runtime[instance.id]
    local gauge, native = value.gauge, value.gaugeWarcraft
    assert(value.gaugeActive and gauge:IsVisible() and native:IsVisible())
    local textures, frames = #Stub.textures, #Stub.frames
    fail = true
    Menubar:RefreshWidget(value.id); Menubar:Layout()
    equal(resets, 1)
    equal(value.gaugeActive, false)
    assert(not gauge:IsShown() and not native:IsShown() and not value.gaugeWarcraftAnchor:IsShown())
    errorPresentation(value)
    fail = false
    Menubar:RefreshWidget(value.id); Menubar:Layout()
    equal(value.failed, nil)
    equal(value.gauge, gauge)
    equal(value.gaugeWarcraft, native)
    equal(value.customWidth, 160)
    equal(value.width, 160)
    assert(value.gaugeActive and gauge:IsVisible() and native:IsVisible())
    equal(value.gaugeLabel:GetText(), "Progress")
    equal(#Stub.textures, textures)
    equal(#Stub.frames, frames)
    Menubar:RemoveWidget(value.id)
end)

check("irregular actual-host timer deliveries give Eyes only elapsed time since its preceding update", function()
    local instance = Menubar:AddWidget("eyes", "top", "left")
    local value = Menubar.runtime[instance.id]
    local definition, deliveries = value.definition, {}
    local update = definition.update
    definition.update = function(current, elapsed)
        if current == value and elapsed then deliveries[#deliveries + 1] = elapsed end
        return update(current, elapsed)
    end
    local total, pending, reported = 0, 0, 0
    for _, elapsed in ipairs({ 0.021, 0.027, 0.011, 0.042, 0.013, 0.037, 0.019, 0.031 }) do
        total, pending = total + elapsed, pending + elapsed
        local before = #deliveries
        tick(elapsed)
        assert(not value.failed, tostring(value.failed))
        if #deliveries > before then
            equal(#deliveries, before + 1)
            near(deliveries[#deliveries], pending)
            reported, pending = reported + deliveries[#deliveries], 0
        end
    end
    assert(#deliveries >= 4)
    assert(reported <= total + 0.0000001, "Scheduling carry must not age Eyes trails twice")
    near(reported + pending, total)
    definition.update = update
    Menubar:RemoveWidget(value.id)
end)

local alignmentProviders = {
    { "mail", "Menubar_Mail", "Mail.lua" },
    { "social", "Menubar_Social", "Social.lua" },
    { "currency", "Menubar_Currency", "Currency.lua" },
    { "network", "Menubar_Network", "Network.lua" },
    { "performance", "Menubar_Performance", "Performance.lua" },
    { "durability", "Menubar_Durability", "Durability.lua" },
}
local completeAlignmentFixture = true
for _, provider in ipairs(alignmentProviders) do
    provider.path = providerPath(provider[1], provider[2], provider[3])
    if not provider.path then completeAlignmentFixture = false end
end
if completeAlignmentFixture then
    local durabilityRemaining = 85
    GetInventoryItemDurability = function(slot) if slot == 5 then return durabilityRemaining, 100 end end
    GetInventoryAlertStatus = function() return 0 end
    for _, provider in ipairs(alignmentProviders) do dofile(provider.path) end
    Menubar:Rebuild()

    local function anchoredTo(region, content)
        assert(region and region:IsVisible(), "Expected visible provider artwork")
        assert(#region.points > 0, "Provider artwork has no anchor")
        for _, point in ipairs(region.points) do
            equal(point[2], content)
            equal(point[5] or 0, 0)
        end
    end
    local function visualCenter(region)
        local _, bottom, _, height = region:GetRect()
        return bottom + height / 2
    end

    check("real provider artwork shares the framed content centre on either bar in every theme", function()
        local kinds = { "eyes", "volume", "mail", "social", "currency", "network", "performance", "durability" }
        local retained = {}
        for _, kind in ipairs(kinds) do
            local value = widget(kind)
            value.settings.followCursor = false
            if kind == "eyes" then value.settings.appearance, value.settings.iris, value.settings.size = "smooth", "blue", 16 end
            if kind == "currency" then value.settings.display = "coins" end
            retained[kind] = value
        end
        local profile = Menubar:GetProfile()
        for _, theme in ipairs({ "system7", "macos8", "macosx", "macos27", "warcraftBrown", "warcraftBlack", "warcraftRed" }) do
            assert(MenubarModel.ApplyTheme(profile, theme))
            profile.placement = "both"
            for _, name in ipairs({ "top", "bottom" }) do
                for _, kind in ipairs(kinds) do retained[kind].instance.bar = name end
                Menubar:Rebuild()
                local bar = Menubar.bars[name]
                local expectedCenter = visualCenter(bar) + (profile.bottomLineSize - profile.topLineSize) / 2
                for _, kind in ipairs(kinds) do
                    local value = widget(kind)
                    equal(value, retained[kind])
                    assert(not value.failed, tostring(value.failed))
                    equal(value.frame:GetHeight(), profile.height)
                    equal(value.frame:GetParent(), bar)
                    equal(value.content:GetHeight(), profile.height - profile.topLineSize - profile.bottomLineSize)
                    near(visualCenter(value.content), expectedCenter)
                    if kind ~= "currency" and kind ~= "eyes" then
                        anchoredTo(value.label, value.content)
                        near(visualCenter(value.label), expectedCenter)
                    end
                end
                local mail = widget("mail")
                equal(#mail.label.points, 2) -- Both edges must reference the same vertical centre.
                for _, pair in ipairs({
                    { "mail", "mailIcon" }, { "social", "socialIcon" },
                    { "volume", "volumeIcon" }, { "network", "networkIcon" },
                    { "performance", "performanceIcon" }, { "durability", "durabilitySummaryIcon" },
                }) do
                    local value = widget(pair[1])
                    anchoredTo(value[pair[2]], value.content)
                    near(visualCenter(value[pair[2]]), expectedCenter)
                end
                -- Outlines exist only on presets that use them. Their placement
                -- still follows the same content rectangle as the icon itself.
                local function checkOutline(value, region, expected)
                    equal(region and region:IsVisible() or false, expected)
                    if expected then
                        anchoredTo(region, value.content)
                        near(visualCenter(region), expectedCenter)
                    end
                end
                local network, performance = widget("network"), widget("performance")
                checkOutline(network, network.networkOutline, MenubarSkins.IsWarcraft(theme))
                checkOutline(performance, performance.performanceIconOutline, theme ~= "macos8" and theme ~= "macosx")
                local currency = widget("currency")
                for _, key in ipairs({ "gold", "silver", "copper" }) do
                    anchoredTo(currency.currencyVisual.icons[key], currency.content)
                    near(visualCenter(currency.currencyVisual.icons[key]), expectedCenter)
                end
                for _, text in ipairs(currency.currencyVisual.texts) do
                    if text:IsShown() then anchoredTo(text, currency.content); near(visualCenter(text), expectedCenter) end
                end
                local eyes = widget("eyes")
                for _, eye in ipairs(eyes.eyes) do
                    equal(eye.smooth.orb:GetHeight(), 16)
                    anchoredTo(eye.smooth.orb, eyes.content)
                    anchoredTo(eye.smooth.iris, eyes.content)
                    near(visualCenter(eye.smooth.orb), expectedCenter)
                    near(visualCenter(eye.smooth.iris), expectedCenter)
                end
                shiftLeftClick(mail.frame)
                local anchor = assert(Menubar.UI.menuAnchors[name])
                equal(anchor.points[1][2], bar)
                equal(anchor.points[1][3], "TOPLEFT")
                equal(anchor.points[1][5], 0)
                equal(anchor:GetHeight(), profile.height)
                Menubar.UI:CloseBarMenu()
            end
        end
    end)

    check("Durability warnings keep the hammer and slot percentages on the shared centre", function()
        local value = widget("durability")
        durabilityRemaining = 10
        Menubar:RefreshWidget(value.id)
        assert(not value.failed, tostring(value.failed))
        local icon = assert(value.durabilitySummaryIcon)
        assert(icon:IsShown())
        assert(value.label:GetText():find("10%", 1, true))
        anchoredTo(icon, value.content)
        anchoredTo(value.label, value.content)
        near(visualCenter(icon), visualCenter(value.content))
        near(visualCenter(value.label), visualCenter(value.content))
        durabilityRemaining = 85
        Menubar:RefreshWidget(value.id)
    end)

    check("compact framed bars keep every graphical icon inside the available body", function()
        local profile = Menubar:GetProfile()
        local function inside(region, content)
            assert(region and region:IsVisible(), "Expected visible compact artwork")
            assert(region:GetTop() <= content:GetTop() + 0.000001, "Artwork extends above its content area")
            assert(region:GetBottom() >= content:GetBottom() - 0.000001, "Artwork extends below its content area")
        end
        for _, geometry in ipairs({ {16, 1, 4}, {16, 0, 6}, {16, 6, 0}, {16, 6, 6}, {24, 1, 4} }) do
            profile.height, profile.topLineSize, profile.bottomLineSize = unpack(geometry)
            Menubar:Rebuild()
            for _, pair in ipairs({
                { "mail", "mailIcon" }, { "social", "socialIcon" }, { "volume", "volumeIcon" },
                { "network", "networkIcon" }, { "network", "networkOutline" },
                { "performance", "performanceIcon" }, { "performance", "performanceIconOutline" },
            }) do
                local value = widget(pair[1]); assert(not value.failed, tostring(value.failed))
                inside(value[pair[2]], value.content)
            end
            local currency = widget("currency")
            for _, icon in pairs(currency.currencyVisual.icons) do
                if icon:IsShown() then inside(icon, currency.content) end
            end
            local eyes = widget("eyes")
            for _, eye in ipairs(eyes.eyes) do inside(eye.smooth.orb, eyes.content) end
            local durability = widget("durability")
            for _, remaining in ipairs({85, 10}) do
                durabilityRemaining = remaining
                Menubar:RefreshWidget(durability.id)
                assert(not durability.failed, tostring(durability.failed))
                local icon = durability.durabilitySummaryIcon
                inside(icon, durability.content)
            end
            durabilityRemaining = 85
            Menubar:RefreshWidget(durability.id)
        end
    end)

    check("Eyes uses its visual content centre when aiming at the pointer", function()
        local value = widget("eyes")
        local oldContentCenter, oldFrameCenter = value.content.GetCenter, value.frame.GetCenter
        value.content.GetCenter = function() return 1000, 700 end
        value.frame.GetCenter = function() return 2000, 1400 end
        pointerX, pointerY = 1000, 700
        value.settings.followCursor, value.settings.appearance, value.settings.iris = true, "smooth", "blue"
        Menubar:RefreshWidget(value.id)
        assert(not value.failed, tostring(value.failed))
        for index, eye in ipairs(value.eyes) do
            local orb, iris = eye.smooth.orb, eye.smooth.iris
            equal(iris.points[1][2], value.content)
            near(iris.points[1][5], 0)
            -- At the midpoint, both eyes converge horizontally without looking up or down.
            local horizontal = iris.points[1][4] - orb.points[1][4]
            assert(index == 1 and horizontal > 0 or index == 2 and horizontal < 0)
        end
        value.content.GetCenter, value.frame.GetCenter = oldContentCenter, oldFrameCenter
    end)
else
    print("SKIP complete provider alignment integration: supply the bundled provider roots.")
end

print(passed .. " graphical host integration tests passed")
