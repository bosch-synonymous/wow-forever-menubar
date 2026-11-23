-- Original native-boundary tests; animation rendering still needs the game.
local root = REPO_ROOT or "."
local Stub = dofile(root .. "/tests/wow_stub.lua")
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, test)
    local ok, why = pcall(test)
    if not ok then error(name .. ": " .. tostring(why), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function fixture()
    Stub.Install(); MenubarDB = nil
    for line in io.lines(root .. "/src/menubar-core/Menubar.toc") do
        local file = line:match("^%s*(.-)%s*$")
        if file:match("%.lua$") then assert(loadfile(root .. "/src/menubar-core/" .. file))() end
    end
    local f = { updates = 0, events = 0, log = {} }
    Menubar:RegisterWidgetType({ id = "notice", name = "Notice", defaults = {}, events = { "NOTICE_TEST" },
        update = function(widget)
            f.updates = f.updates + 1; f.log[#f.log + 1] = "update"
            if f.updateError then error("render failure", 0) end
            if not widget.icon then
                widget.icon = widget.frame:CreateTexture(nil, "ARTWORK")
                widget.icon:SetSize(16, 16); widget.icon:SetPoint("CENTER", widget.frame, "CENTER")
            end
            widget.icon:Show(); widget:SetText("Notice 1")
        end,
        event = function(widget, event, ...)
            f.events = f.events + 1; f.log[#f.log + 1] = event; f.payload = { ... }
            widget:JiggleIcon(widget.icon)
        end,
    })
    Menubar:Start(); f.host = Menubar
    local _, widget = next(Menubar.runtime); f.widget = widget
    function f:emit(...) self.host.eventFrame.scripts.OnEvent(self.host.eventFrame, ...) end
    return f
end

check("registered event callbacks receive original payload after refresh and never during polling", function()
    local f = fixture(); local payload = {}
    equal(f.events, 0)
    f:emit("NOTICE_TEST", payload, false, 0)
    equal(f.events, 1); equal(f.payload[1], payload); equal(f.payload[2], false); equal(f.payload[3], 0)
    equal(f.log[#f.log - 1], "update"); equal(f.log[#f.log], "NOTICE_TEST")
    f:emit("OTHER_TEST"); equal(f.events, 1)
    f.host:RefreshAll(); f.host.eventFrame.scripts.OnUpdate(f.host.eventFrame, 1.1)
    equal(f.events, 1)
    local before = f.host.types.bad
    local ok = pcall(f.host.RegisterWidgetType, f.host, { id = "bad", name = "Bad", event = true })
    equal(ok, false); equal(f.host.types.bad, before)
end)

check("a pronounced native hop launches faster than it returns without moving the widget", function()
    local f = fixture(); local widget = f.widget
    local width, labelText, point = widget.width, widget.label:GetText(), widget.frame.points[1][4]
    f:emit("NOTICE_TEST")
    local motion = widget.iconJiggle; local group = motion.group
    equal(group.parent, widget.icon); equal(group.looping, "NONE"); equal(#group.steps, 4)
    local duration, offset = 0, 0
    for index, step in ipairs(group.steps) do
        equal(step.kind, "Translation"); equal(step.order, index); equal(step.offset[1], 0)
        assert(step.duration > 0); duration = duration + step.duration; offset = offset + step.offset[2]
    end
    assert(duration < 1); equal(offset, 0)
    local launch, fall, rebound, settle = unpack(group.steps)
    assert(launch.offset[2] ~= 0, "The hop must move the icon")
    assert(launch.duration * 2 < fall.duration, "The launch should be substantially quicker than the return")
    equal(launch.smoothing, "OUT"); equal(fall.smoothing, "IN")
    equal(launch.offset[2] + fall.offset[2], 0)
    assert(math.abs(rebound.offset[2]) < math.abs(launch.offset[2]) and rebound.duration < settle.duration)
    equal(rebound.offset[2] + settle.offset[2], 0)
    for _ = 1, 20 do f:emit("NOTICE_TEST") end
    equal(#Stub.animations, 1); equal(group.plays, 1)
    equal(widget.width, width); equal(widget.label:GetText(), labelText); equal(widget.frame.points[1][4], point)
    group:Finish(); f:emit("NOTICE_TEST"); equal(group.plays, 2); equal(#group.steps, 4)
end)

check("retained icon hops face the play area after moving between either bar", function()
    local f = fixture(); local widget = f.widget
    f:emit("NOTICE_TEST")
    local group = widget.iconJiggle.group
    assert(group.steps[1].offset[2] < 0, "The top bar should launch downward into the screen")
    local tickers, iconPoint = #Stub.tickers, widget.icon.points[1]
    assert(iconPoint ~= nil)
    for _, placement in ipairs({ "bottom", "top", "both", "both" }) do
        f.host:GetProfile().placement = placement
        widget.instance.bar = placement == "both" and (widget.instance.bar == "top" and "bottom" or "top") or placement
        f.host:Rebuild(); equal(group:IsPlaying(), false)
        f:emit("NOTICE_TEST")
        equal(f.host.runtime[widget.id], widget); equal(widget.iconJiggle.group, group)
        equal(#Stub.animations, 1); equal(#group.steps, 4)
        local direction = f.host:EffectiveBar(widget.instance) == "top" and -1 or 1
        assert(group.steps[1].offset[2] * direction > 0)
        equal(group.steps[1].offset[2] + group.steps[2].offset[2], 0)
        equal(widget.icon.points[1], iconPoint); equal(#Stub.tickers, tickers)
    end
end)

check("hidden removed disabled and failed widgets cannot keep or start a jiggle", function()
    local f = fixture(); local widget = f.widget
    f:emit("NOTICE_TEST"); local group = widget.iconJiggle.group
    widget.frame:Hide(); equal(group:IsPlaying(), false)
    equal(widget:JiggleIcon(widget.icon), false); equal(group.plays, 1)
    widget.frame:Show(); widget.icon:Hide()
    equal(widget:JiggleIcon(widget.icon), false); equal(group.plays, 1)
    widget.icon:Show(); widget.instance.enabled = false
    equal(widget:JiggleIcon(widget.icon), false)
    widget.instance.enabled = true; f:emit("NOTICE_TEST"); equal(group:IsPlaying(), true)
    f.updateError = true; f:emit("NOTICE_TEST")
    assert(widget.failed); equal(group:IsPlaying(), false)
    equal(widget:JiggleIcon(widget.icon), false)
    f.updateError = false; f.host:RefreshWidget(widget.id); f:emit("NOTICE_TEST")
    equal(group:IsPlaying(), true)
    widget.instance.enabled = false; f.host:Rebuild()
    equal(group:IsPlaying(), false); equal(widget:JiggleIcon(widget.icon), false)
end)

check("rebuilding reuses motion resources without replaying and missing animation support stays usable", function()
    local f = fixture(); local widget = f.widget
    f:emit("NOTICE_TEST"); local group = widget.iconJiggle.group
    for _ = 1, 10 do f.host:Rebuild() end
    equal(#Stub.animations, 1); equal(group:IsPlaying(), false); equal(group.plays, 1)
    f:emit("NOTICE_TEST"); equal(group.plays, 2)
    local other = widget.frame:CreateTexture(); other.CreateAnimationGroup = false
    equal(widget:JiggleIcon(other), false)
    local secret = {}; issecretvalue = function(value) return rawequal(value, secret) end
    equal(widget:JiggleIcon(secret), false)
    equal(widget:JiggleIcon(nil), false)
end)

check("the helper refuses frames labels and textures owned by another widget", function()
    local f = fixture(); local widget = f.widget
    equal(widget:JiggleIcon(widget.frame), false)
    equal(widget:JiggleIcon(widget.label), false)
    local other = CreateFrame("Frame", nil, UIParent)
    equal(widget:JiggleIcon(other:CreateTexture()), false)
    equal(#Stub.animations, 0)
    f:emit("NOTICE_TEST"); equal(#Stub.animations, 1)
end)

check("native Stop failures cannot abort rebuilding or obscure a provider error", function()
    local f = fixture(); local widget = f.widget
    f:emit("NOTICE_TEST"); local group = widget.iconJiggle.group
    local stop = group.Stop
    group.Stop = function() error("native stop failed", 0) end
    equal(widget:StopIconJiggle(), false)
    f.host:Rebuild(); equal(widget.failed, nil)
    f.updateError = true; f:emit("NOTICE_TEST")
    equal(widget.failed, "render failure")
    equal(widget.label:GetText(), "[Notice: error]")
    equal(widget.customWidth, nil)
    assert(not Stub.messages[#Stub.messages]:find("native stop failed", 1, true))
    group.Stop = stop; f.updateError = false
    f.host:RefreshWidget(widget.id); f.host:Rebuild()
    equal(widget.failed, nil); equal(group:IsPlaying(), false); equal(#Stub.animations, 1)
end)

check("partially configured native motion is retained and completes on explicit recovery", function()
    local f = fixture(); local widget = f.widget
    local native = widget.icon.CreateAnimationGroup
    local fail = true
    function widget.icon:CreateAnimationGroup()
        local group = native(self)
        local create = group.CreateAnimation
        function group:CreateAnimation(kind)
            local step = create(self, kind)
            if #self.steps == 2 then
                local set = step.SetOffset
                function step:SetOffset(...)
                    if fail then fail = false; error("native translation offset failure", 0) end
                    return set(self, ...)
                end
            end
            return step
        end
        return group
    end
    f:emit("NOTICE_TEST"); assert(widget.failed:find("native translation offset failure", 1, true))
    local group = widget.iconJiggle.group
    equal(#Stub.animations, 1); equal(#group.steps, 2); equal(group:IsPlaying(), false)
    f.host:RefreshWidget(widget.id); f:emit("NOTICE_TEST")
    equal(widget.failed, nil); equal(widget.iconJiggle.group, group)
    equal(#Stub.animations, 1); equal(#group.steps, 4); equal(group.plays, 1)
end)

check("multiple owned coin icons animate independently within a bounded reusable pool", function()
    local f = fixture(); local widget = f.widget
    local icons = { widget.icon }
    for index = 2, 5 do icons[index] = widget.frame:CreateTexture(nil, "ARTWORK") end
    equal(widget:JiggleIcon(icons[1]), true)
    equal(widget:JiggleIcon(icons[3]), true)
    local first, third = widget.iconJiggles[1].group, widget.iconJiggles[2].group
    equal(first.parent, icons[1]); equal(third.parent, icons[3]); equal(#Stub.animations, 2)
    first:Finish(); equal(third:IsPlaying(), true)
    equal(widget:JiggleIcon(icons[1]), true); equal(first.plays, 2); equal(third.plays, 1)
    equal(widget:JiggleIcon(icons[2]), true); equal(widget:JiggleIcon(icons[4]), true)
    equal(widget:JiggleIcon(icons[5]), false)
    for _ = 1, 20 do
        for index = 1, 4 do widget:JiggleIcon(icons[index]) end
    end
    equal(#Stub.animations, 4); equal(#widget.iconJiggles, 4)
    widget.frame:Hide()
    for _, group in ipairs(Stub.animations) do equal(group:IsPlaying(), false); equal(#group.steps, 4) end
    widget.frame:Show(); widget:JiggleIcon(icons[2]); equal(#Stub.animations, 4)
end)

check("a failed native Stop on one icon does not prevent stopping its siblings", function()
    local f = fixture(); local widget = f.widget
    widget:JiggleIcon(widget.icon)
    local second = widget.frame:CreateTexture(nil, "ARTWORK"); widget:JiggleIcon(second)
    local first, other = widget.iconJiggles[1].group, widget.iconJiggles[2].group
    local stop = first.Stop; first.Stop = function() error("one icon stop rejected", 0) end
    equal(widget:StopIconJiggle(), false); equal(other:IsPlaying(), false)
    first.Stop = stop; equal(widget:StopIconJiggle(), true); equal(first:IsPlaying(), false)
    equal(#Stub.animations, 2)
end)

local function ownedIcons(widget, count)
    local icons = { widget.icon }
    for index = 2, count do
        icons[index] = widget.frame:CreateTexture(nil, "ARTWORK")
        icons[index]:SetSize(16, 16)
    end
    return icons
end
local function motionFor(widget, icon)
    for _, motion in ipairs(widget.iconJiggles or {}) do if motion.icon == icon then return motion.group end end
end
local function playing(widget)
    local count = 0
    for _, motion in ipairs(widget.iconJiggles or {}) do if motion.group:IsPlaying() then count = count + 1 end end
    return count
end
local function cadenceFor(widget)
    for _, group in ipairs(Stub.animations) do
        if group.parent == widget.frame and #group.steps == 1 and group.steps[1].kind == "Animation" then return group end
    end
end
local function near(actual, expected) assert(math.abs(actual - expected) < 1e-8) end

check("ordered hops copy input and launch every half hop while prior icons keep moving", function()
    local f = fixture(); local widget = f.widget; local icons = ownedIcons(widget, 3)
    local ordered = { icons[3], icons[2], icons[1] }
    local width, text, point, tickers = widget.width, widget.label:GetText(), widget.frame.points[1], #Stub.tickers
    equal(widget:JiggleIcons(ordered), true)
    local right, middle, left = motionFor(widget, icons[3]), motionFor(widget, icons[2]), motionFor(widget, icons[1])
    equal(#Stub.animations, 4); equal(playing(widget), 1)
    local cadence = assert(cadenceFor(widget)); near(cadence:GetDuration(), 0.265)
    equal(right.plays, 1); equal(middle.plays, 0); equal(left.plays, 0)
    ordered[1], ordered[2], ordered[3] = icons[1], nil, nil
    Stub.AdvanceAnimations(0.264); equal(middle.plays, 0)
    Stub.AdvanceAnimations(0.001); equal(playing(widget), 2); equal(middle.plays, 1); equal(left.plays, 0)
    near(right.starts[1], 0); near(middle.starts[1], 0.265)
    Stub.AdvanceAnimations(0.265); equal(playing(widget), 2); equal(left.plays, 1); near(left.starts[1], 0.53)
    for _, group in ipairs({ right, middle, left }) do near(group:GetDuration(), 0.53) end
    Stub.AdvanceAnimations(0.53); equal(playing(widget), 0); equal(widget.iconJiggleQueue, nil)
    equal(widget.width, width); equal(widget.label:GetText(), text); equal(widget.frame.points[1], point)
    equal(#Stub.tickers, tickers)
    widget:JiggleIcon(icons[1]); left:Finish()
    equal(left.plays, 2); equal(middle.plays, 1); equal(right.plays, 1)
end)

check("ordered bursts coalesce active and pending icons within the four-identity resource bound", function()
    local f = fixture(); local widget = f.widget; local icons = ownedIcons(widget, 5)
    widget:JiggleIcons({ icons[1], icons[2], icons[3] })
    for _ = 1, 30 do equal(widget:JiggleIcons({ icons[1], icons[2], icons[3], icons[3] }), true) end
    equal(widget:JiggleIcons({ icons[3], icons[4] }), true)
    equal(widget:JiggleIcons({ icons[5] }), false)
    equal(#Stub.animations, 5); equal(#widget.iconJiggles, 4)
    Stub.AdvanceAnimations(2)
    equal(playing(widget), 0); equal(widget.iconJiggleQueue, nil)
    for index = 1, 4 do equal(motionFor(widget, icons[index]).plays, 1) end
end)

check("early appended bursts join the existing cooldown and finished icons can rejoin its tail", function()
    local f = fixture(); local widget = f.widget; local icons = ownedIcons(widget, 3)
    widget:JiggleIcons({ icons[1] }); local first = motionFor(widget, icons[1])
    Stub.AdvanceAnimations(0.1)
    widget:JiggleIcons({ icons[1], icons[2], icons[3] })
    local second, third = motionFor(widget, icons[2]), motionFor(widget, icons[3])
    equal(second.plays, 0)
    Stub.AdvanceAnimations(0.165); near(second.starts[1], 0.265)
    Stub.AdvanceAnimations(0.275); near(third.starts[1], 0.53)
    widget:JiggleIcons({ icons[1], icons[2], icons[3] })
    equal(first.plays, 1); equal(second.plays, 1); equal(third.plays, 1)
    Stub.AdvanceAnimations(0.255); equal(first.plays, 2); near(first.starts[2], 0.795)
    Stub.AdvanceAnimations(1); equal(playing(widget), 0); equal(widget.iconJiggleQueue, nil)
    equal(#Stub.animations, 4)
end)

check("same-instant cadence and hop completions are safe in either native callback order", function()
    for _, clockFirst in ipairs({ false, true }) do
        local f = fixture(); local widget = f.widget; local icons = ownedIcons(widget, 3)
        widget:JiggleIcons(icons); Stub.AdvanceAnimations(0.265)
        local first, third, cadence = motionFor(widget, icons[1]), motionFor(widget, icons[3]), cadenceFor(widget)
        Stub.animationTime = 0.53
        if clockFirst then cadence:Finish(); first:Finish() else first:Finish(); cadence:Finish() end
        equal(third.plays, 1); near(third.starts[1], 0.53); equal(playing(widget), 2)
        Stub.AdvanceAnimations(1); equal(playing(widget), 0); equal(widget.iconJiggleQueue, nil)
    end
end)

check("queued completions cannot continue after owner identity visibility or settings change", function()
    for _, change in ipairs({ "hide", "stop", "rebuild", "disable", "remove", "settings", "instance", "database", "character", "definition", "failure" }) do
        local f = fixture(); local widget = f.widget; local icons = ownedIcons(widget, 3)
        widget:JiggleIcons(icons)
        local first, nextGroup = motionFor(widget, icons[1]), motionFor(widget, icons[2])
        local finished = first:GetScript("OnFinished")
        local cadence = cadenceFor(widget); local elapsed = cadence:GetScript("OnFinished")
        if change == "hide" then widget.frame:Hide()
        elseif change == "stop" then widget:StopIconJiggle()
        elseif change == "rebuild" then f.host:Rebuild()
        elseif change == "disable" then widget.instance.enabled = false
        elseif change == "remove" then f.host:RemoveWidget(widget.id)
        elseif change == "settings" then widget.settings = {}
        elseif change == "instance" then widget.instance = { enabled = true }
        elseif change == "database" then f.host.db = {}
        elseif change == "character" then f.host.characterKey = "Another character"
        elseif change == "definition" then widget.definition = {}
        else widget.failed = "render failed" end
        cadence:Finish(); elapsed(cadence); first:Finish(); finished(first)
        equal(nextGroup.plays, 0); equal(playing(widget), 0); equal(widget.iconJiggleQueue, nil)
    end
end)

check("queue cancellation precedes native Stop scripts and old completions cannot advance a new sequence", function()
    local f = fixture(); local widget = f.widget; local icons = ownedIcons(widget, 2)
    widget:JiggleIcons(icons)
    local first, second = motionFor(widget, icons[1]), motionFor(widget, icons[2])
    local stale = first:GetScript("OnFinished")
    local cadence = cadenceFor(widget); local oldPhase = cadence:GetScript("OnFinished")
    local stopCadence = cadence.Stop
    cadence.Stop = function(self) oldPhase(self); return stopCadence(self) end
    local stop = first.Stop
    first.Stop = function(self) stale(self); return stop(self) end
    equal(widget:StopIconJiggle(), true); equal(second.plays, 0)
    first.Stop, cadence.Stop = stop, stopCadence
    widget:JiggleIcons(icons); stale(first); oldPhase(cadence)
    equal(playing(widget), 1); equal(first.plays, 2); equal(second.plays, 0)
    Stub.AdvanceAnimations(0.265); equal(second.plays, 1); equal(playing(widget), 2)
    local phase = cadence:GetScript("OnFinished"); oldPhase(cadence); equal(cadence:GetScript("OnFinished"), phase)
    Stub.AdvanceAnimations(1); equal(playing(widget), 0)
end)

check("an older phase callback cannot advance a later cooldown in the same sequence", function()
    local f = fixture(); local widget = f.widget; local icons = ownedIcons(widget, 3)
    widget:JiggleIcons(icons)
    local cadence = cadenceFor(widget); local stale = cadence:GetScript("OnFinished")
    Stub.AdvanceAnimations(0.265); stale(cadence)
    equal(motionFor(widget, icons[3]).plays, 0)
    Stub.AdvanceAnimations(0.265); equal(motionFor(widget, icons[3]).plays, 1)
end)

check("queued native failures cancel safely and a later request can reuse the retained groups", function()
    local f = fixture(); local widget = f.widget; local icons = ownedIcons(widget, 3)
    widget:JiggleIcons(icons)
    local first, second, third = motionFor(widget, icons[1]), motionFor(widget, icons[2]), motionFor(widget, icons[3])
    local nativePlay = second.Play
    local secret = setmetatable({}, { __tostring = function() error("restricted failure formatted", 0) end })
    issecretvalue = function(value) return rawequal(value, secret) end
    second.Play = function() error(secret, 0) end
    local ok = pcall(Stub.AdvanceAnimations, 0.265)
    equal(ok, true); equal(widget.failed, nil); equal(playing(widget), 0); equal(widget.iconJiggleQueue, nil)
    equal(second.plays, 0); equal(third.plays, 0)
    assert(Stub.messages[#Stub.messages]:find("details unavailable", 1, true))
    second.Play = nativePlay
    widget:JiggleIcons({ icons[2], icons[3] }); Stub.AdvanceAnimations(1)
    equal(second.plays, 1); equal(third.plays, 1); equal(#Stub.animations, 4)
    equal(widget.iconJiggleQueue, nil)
end)

check("queued preparation retains partial motion without starting earlier icons prematurely", function()
    local f = fixture(); local widget = f.widget; local icons = ownedIcons(widget, 3)
    local create, fail = icons[2].CreateAnimationGroup, true
    icons[2].CreateAnimationGroup = function(self)
        local group = create(self); local native = group.CreateAnimation
        function group:CreateAnimation(kind)
            local step = native(self, kind); local offset = step.SetOffset
            function step:SetOffset(...)
                if fail then fail = false; error("queued preparation rejected", 0) end
                return offset(self, ...)
            end
            return step
        end
        return group
    end
    local ok, message = pcall(widget.JiggleIcons, widget, icons)
    equal(ok, false); assert(tostring(message):find("queued preparation rejected", 1, true))
    equal(#Stub.animations, 2); equal(playing(widget), 0); equal(motionFor(widget, icons[1]).plays, 0)
    equal(widget:JiggleIcons(icons), true); equal(#Stub.animations, 4)
    Stub.AdvanceAnimations(2)
    equal(playing(widget), 0); equal(widget.iconJiggleQueue, nil)
end)

check("partial cadence setup is owned and retried before starting any icon", function()
    local f = fixture(); local widget = f.widget; local icons = ownedIcons(widget, 2)
    local create, fail = widget.frame.CreateAnimationGroup, true
    widget.frame.CreateAnimationGroup = function(self)
        local group = create(self); local native = group.CreateAnimation
        function group:CreateAnimation(...)
            local step = native(self, ...); local duration = step.SetDuration
            function step:SetDuration(...)
                if fail then fail = false; error("cadence setup failed", 0) end
                return duration(self, ...)
            end
            return step
        end
        return group
    end
    equal(pcall(widget.JiggleIcons, widget, icons), false)
    equal(playing(widget), 0); equal(#Stub.animations, 3)
    widget:JiggleIcons(icons); Stub.AdvanceAnimations(1)
    equal(#Stub.animations, 3); equal(playing(widget), 0); equal(widget.iconJiggleQueue, nil)
end)

check("a failed cadence restart stops overlapping hops and pending work can recover", function()
    local f = fixture(); local widget = f.widget; local icons = ownedIcons(widget, 3)
    widget:JiggleIcons(icons)
    local cadence = cadenceFor(widget); local restart = cadence.Restart
    cadence.Restart = function() error("cadence restart failed", 0) end
    Stub.AdvanceAnimations(0.265)
    equal(playing(widget), 0); equal(widget.iconJiggleQueue, nil); equal(motionFor(widget, icons[3]).plays, 0)
    cadence.Restart = restart
    widget:JiggleIcons(icons); Stub.AdvanceAnimations(2)
    equal(playing(widget), 0); equal(#Stub.animations, 4)
end)

check("a cadence Stop failure cannot revive pending work or prevent stopping overlapping icons", function()
    local f = fixture(); local widget = f.widget; local icons = ownedIcons(widget, 3)
    widget:JiggleIcons(icons); Stub.AdvanceAnimations(0.265)
    local cadence = cadenceFor(widget); local stale = cadence:GetScript("OnFinished"); local stop = cadence.Stop
    cadence.Stop = function(self) stale(self); error("cadence stop failed", 0) end
    equal(widget:StopIconJiggle(), false)
    equal(playing(widget), 0); equal(widget.iconJiggleQueue, nil)
    Stub.AdvanceAnimations(1); stale(cadence); equal(motionFor(widget, icons[3]).plays, 0)
    cadence.Stop = stop; equal(widget:StopIconJiggle(), true)
    widget:JiggleIcons(icons); Stub.AdvanceAnimations(2)
    equal(playing(widget), 0); equal(#Stub.animations, 4)
end)

check("ordered requests reject invalid arrays and skip an icon hidden while waiting", function()
    local f = fixture(); local widget = f.widget; local icons = ownedIcons(widget, 3)
    local foreign = CreateFrame("Frame", nil, UIParent):CreateTexture()
    local secret = {}; issecretvalue = function(value) return rawequal(value, secret) end
    for _, value in ipairs({ false, {}, secret, { widget.label }, { foreign }, { icons[1], foreign },
        { [1] = icons[1], [3] = icons[3] }, { icons[1], icons[1], icons[1], icons[1], icons[1] } }) do
        equal(widget:JiggleIcons(value), false)
    end
    equal(#Stub.animations, 0)
    widget:JiggleIcons(icons); icons[2]:Hide()
    Stub.AdvanceAnimations(0.265)
    equal(motionFor(widget, icons[2]).plays, 0); equal(motionFor(widget, icons[3]).plays, 1); equal(playing(widget), 2)
    Stub.AdvanceAnimations(1); equal(playing(widget), 0)
end)

check("switching independent and ordered APIs cancels only the current widget's queued work", function()
    local f = fixture(); local widget = f.widget; local icons = ownedIcons(widget, 3)
    widget:JiggleIcon(icons[1]); widget:JiggleIcon(icons[2]); equal(playing(widget), 2)
    widget:JiggleIcons({ icons[3], icons[1] }); equal(playing(widget), 1)
    local queued = motionFor(widget, icons[3]); local finished = queued:GetScript("OnFinished")
    widget:JiggleIcon(icons[2]); equal(playing(widget), 1)
    finished(queued); equal(playing(widget), 1); equal(motionFor(widget, icons[1]).plays, 1)
    local instance = f.host:AddWidget("notice"); local other = f.host.runtime[instance.id]
    other:JiggleIcons({ other.icon }); equal(playing(other), 1)
    widget:StopIconJiggle(); equal(playing(other), 1)
    Stub.AdvanceAnimations(1); equal(playing(other), 0)
end)

print(passed .. " icon jiggle tests passed")
