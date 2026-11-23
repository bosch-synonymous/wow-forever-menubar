local sourceDirectory = dofile((REPO_ROOT or ".") .. "/tests/source_paths.lua")
-- Original native-warning ownership checks through the real addon TOCs.
-- Visibility/Edit Mode/input are modeled contracts, not native taint proof.
local root = REPO_ROOT or "."
local core = MENUBAR_CORE_ROOT or root
local probe = io.open(core .. "/tests/wow_stub.lua", "rb")
if not probe then print("SKIP native durability: supply the Menubar core root."); return end
probe:close()
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run); if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function loadAddon(repository, name)
    for line in io.lines(sourceDirectory(repository, name) .. "/" .. name .. ".toc") do
        local file = line:match("^%s*(.-)%s*$")
        if file:match("%.lua$") then assert(loadfile(sourceDirectory(repository, name) .. "/" .. file))(name, {}) end
    end
end
local function fixture(options)
    options = options or {}
    local Stub = dofile(core .. "/tests/wow_stub.lua"); Stub.Install()
    local f = { Stub = Stub, combat = false, edit = false, permission = true, warning = true, hooks = {}, frames = {} }
    f.secret = setmetatable({}, {
        __tostring = function() error("restricted value formatted", 0) end,
        __lt = function() error("restricted value compared", 0) end,
        __le = function() error("restricted value compared", 0) end,
    })
    issecretvalue = function(value) return rawequal(value, f.secret) end
    MenubarDB, DurabilityFrame = nil, nil
    InCombatLockdown = function() return f.combat end
    EditModeManagerFrame = { IsEditModeActive = function() return f.edit end }
    GetInventoryItemDurability = function(slot) if slot == 1 then return 50, 100 end end
    GetInventoryAlertStatus = function() return 0 end
    local create = CreateFrame
    CreateFrame = function(...)
        local frame = create(...)
        function frame:UnregisterAllEvents() self.events = {} end
        return frame
    end
    hooksecurefunc = function(owner, method, hook)
        local original = assert(owner[method])
        f.hooks[owner] = f.hooks[owner] or {}
        f.hooks[owner][method] = (f.hooks[owner][method] or 0) + 1
        owner[method] = function(...)
            local result = { original(...) }; hook(...); return unpack(result)
        end
    end
    function f:makeNative()
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -50, -200)
        frame:SetSize(60, 75); frame.alpha, frame.mouseEnabled, frame.isInEditMode = 0.75, true, false
        frame.alphaWrites, frame.mouseWrites, frame.nativeUpdates = 0, 0, 0
        frame.Selection = CreateFrame("Frame", nil, frame)
        frame.Selection.ignoreParentAlpha, frame.Selection.mouseEnabled = true, true
        frame.Selection:Hide()
        function frame:CanChangeProtectedState() return f.permission end
        function frame:GetAlpha() if self.alphaRead ~= nil then return self.alphaRead end; return self.alpha end
        function frame:IsMouseEnabled() if self.mouseRead ~= nil then return self.mouseRead end; return self.mouseEnabled end
        function frame:SetAlpha(value)
            assert(type(value) == "number" and value == value and value >= 0 and value <= 1)
            if not f.externalWrite then
                assert(f.combat == false and f.permission == true, "presentation writes require permission")
                self.alphaWrites = self.alphaWrites + 1
                if self.rejectAlpha then return false end
                if self.throwAlpha then error("native alpha rejected", 0) end
            end
            self.alpha = value
        end
        function frame:EnableMouse(enabled)
            assert(type(enabled) == "boolean")
            if not f.externalWrite then
                assert(f.combat == false and f.permission == true, "input writes require permission")
                self.mouseWrites = self.mouseWrites + 1
                if self.rejectMouse then return false end
            end
            self.mouseEnabled = enabled
        end
        local show, hide, setShown = frame.Show, frame.Hide, frame.SetShown
        function frame:Show() assert(f.native, "addon must not show the native warning frame"); return show(self) end
        function frame:Hide() assert(f.native, "addon must not hide the native warning frame"); return hide(self) end
        function frame:SetShown(value) assert(f.native, "addon must not set native warning visibility"); return setShown(self, value) end
        function frame:UpdateShownState()
            self.nativeUpdates = self.nativeUpdates + 1
            f.native = true
            self.shouldShow = f.warning
            self:SetShown(self.shouldShow or self.isInEditMode)
            f.native = false
        end
        frame:RegisterEvent("UPDATE_INVENTORY_ALERTS"); frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:SetScript("OnEvent", function(self) self:UpdateShownState() end)
        frame.savedPoints, frame.savedEvents, frame.savedSelectionMouse = frame.points, frame.events, frame.Selection.mouseEnabled
        frame.SetPoint = function() error("native anchors must remain unchanged", 0) end
        frame.ClearAllPoints = frame.SetPoint
        frame.SetParent = function() error("native warning must not be reparented", 0) end
        frame.UnregisterAllEvents = function() error("native alert events must remain registered", 0) end
        self.frames[#self.frames + 1] = frame
        return frame
    end
    if not options.lazy then DurabilityFrame = f:makeNative() end
    loadAddon(core, "Menubar"); loadAddon(root, "Menubar_Durability")
    if not options.factoryDefaults then
        local db = MenubarModel.Initialize(nil, "Tester - Test Realm")
        MenubarModel.AddWidget(db, "Tester - Test Realm", "durability", { hideDefaultWarnings = false, customThresholds = false })
        MenubarDB = db
    end
    Menubar:Start()
    f.host = Menubar
    for _, widget in pairs(Menubar.runtime) do if widget.instance.type == "durability" then f.widget = widget end end
    assert(f.widget and not f.widget.failed)
    function f:step(count)
        for _ = 1, count or 2 do
            for _, frame in ipairs(Stub.frames) do
                if frame:IsVisible() and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.3) end
            end
        end
    end
    function f:emit(event)
        for _, frame in ipairs(Stub.frames) do
            if frame.events and frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event) end
        end
    end
    function f:refresh(widget) self.host:RefreshWidget((widget or self.widget).id); assert(not (widget or self.widget).failed) end
    function f:request(value, widget)
        widget = widget or self.widget
        self.host.UI:OpenWidget(widget.id)
        local control
        for _, candidate in ipairs(self.host.UI.window.controls) do
            if candidate.caption == "Hide default durability warnings" then control = candidate; break end
        end
        assert(control, "the requested option must be a real native checkbox")
        if control:GetChecked() ~= value then control:Click() end
        equal(widget.settings.hideDefaultWarnings, value); assert(not widget.failed)
    end
    function f:external(frame, method, value)
        self.externalWrite = true; frame[method](frame, value); self.externalWrite = false
    end
    function f:original(frame, alphaValue, mouse)
        frame = frame or DurabilityFrame
        equal(frame:GetAlpha(), alphaValue == nil and 0.75 or alphaValue)
        equal(frame:IsMouseEnabled(), mouse == nil and true or mouse)
    end
    function f:masked(frame)
        frame = frame or DurabilityFrame
        equal(frame:GetAlpha(), 0); equal(frame:IsMouseEnabled(), false)
        equal(frame.points, frame.savedPoints); equal(frame.events, frame.savedEvents)
        equal(frame.Selection.mouseEnabled, frame.savedSelectionMouse)
    end
    function f:tip()
        local tip = { lines = {} }
        function tip:AddLine(text) self.lines[#self.lines + 1] = text end
        function tip:AddDoubleLine() end
        self.widget.definition.tooltip(self.widget, tip)
        return table.concat(tip.lines, "\n")
    end
    function f:controller()
        local found
        for _, frame in ipairs(Stub.frames) do
            if frame ~= self.host.eventFrame and frame.events and frame.events.PLAYER_REGEN_ENABLED and frame.scripts.OnUpdate then
                assert(not found, "one shared retry owner"); found = frame
            end
        end
        return found
    end
    return f
end

check("factory native hiding can be disabled independently from custom threshold settings", function()
    local f = fixture({ factoryDefaults = true }); f:masked()
    equal(f.widget.settings.hideDefaultWarnings, true); equal(f.widget.settings.customThresholds, true)
    f:request(false); f:original()
    f.widget.settings.customThresholds = true; f.widget.settings.warningPercent = 75; f:refresh(); f:original()
    f:request(true); f:masked(); equal(DurabilityFrame:IsShown(), true); equal(DurabilityFrame.shouldShow, nil)
    equal(f.widget.settings.customThresholds, true); equal(f.widget.settings.warningPercent, 75)
    f:emit("UPDATE_INVENTORY_ALERTS"); f:masked(); assert(DurabilityFrame.nativeUpdates > 0)
    equal(DurabilityFrame.shouldShow, true); equal(DurabilityFrame:IsEventRegistered("UPDATE_INVENTORY_ALERTS"), true)
    f:request(false); f:original()
end)

check("repeated rendering does not release borrowed warnings and twenty toggles reuse one retry frame", function()
    local f = fixture(); f:request(true); f:masked()
    local native, monitor = DurabilityFrame, assert(f:controller())
    local frames, alphaWrites, mouseWrites = #f.Stub.frames, native.alphaWrites, native.mouseWrites
    for _ = 1, 20 do f:refresh(); f:masked() end
    equal(native.alphaWrites, alphaWrites); equal(native.mouseWrites, mouseWrites)
    for _ = 1, 20 do f:request(false); f:original(); f:request(true); f:masked() end
    equal(#f.Stub.frames, frames); equal(f:controller(), monitor)
    for _, method in ipairs({ "SetAlpha", "EnableMouse", "UpdateShownState" }) do equal(f.hooks[native][method], 1) end
    f:request(false); equal(monitor:IsShown(), false); equal(next(monitor.events), nil)
end)

check("independent duplicates release only their own request on disable remove and settings reset", function()
    local f = fixture(); f:request(true)
    local instance = f.host:AddWidget("durability"); local second = f.host.runtime[instance.id]
    equal(second.settings.hideDefaultWarnings, true); f:request(true, second)
    f:request(false); f:masked()
    second.instance.enabled = false; f.host:Rebuild(); f:original()
    second.instance.enabled = true; f.host:Rebuild(); f:masked()
    f.host:RemoveWidget(second.id); f:original()
    f:request(true); f.host.UI:OpenWidget(f.widget.id)
    for _, control in ipairs(f.host.UI.window.controls) do if control.caption == "Reset this widget's settings" then control:Click(); break end end
    equal(f.widget.settings.hideDefaultWarnings, true); f:masked()
    f:request(false); f:original()
end)

check("Edit Mode and its independently interactive selection preview restore native presentation", function()
    local f = fixture(); f:request(true); f:masked()
    local frame = DurabilityFrame
    f.edit, frame.isInEditMode = true, true; frame.Selection:Show(); frame:UpdateShownState(); f:original()
    equal(frame.Selection:IsShown(), true); equal(frame.Selection.mouseEnabled, true)
    f.edit, frame.isInEditMode = false, false; frame.Selection:Hide(); frame:UpdateShownState(); f:masked()
    f.edit = true; frame:UpdateShownState(); f:original()
    f.edit = false; frame.Selection:Show(); frame:UpdateShownState(); f:original()
    frame.Selection:Hide(); frame:UpdateShownState(); f:masked()
end)

check("native alert visibility keeps running while suppression and later restoration leave shown state alone", function()
    local f = fixture(); f:request(true); f:masked()
    f.warning = false; f:emit("UPDATE_INVENTORY_ALERTS")
    equal(DurabilityFrame:IsShown(), false); equal(DurabilityFrame.shouldShow, false)
    f:request(false); f:original(); equal(DurabilityFrame:IsShown(), false)
    f.warning = true; f:emit("UPDATE_INVENTORY_ALERTS"); f:original(); equal(DurabilityFrame:IsShown(), true)
end)

check("new external alpha and input policies including zero and false survive the last release", function()
    for _, values in ipairs({ { 0.4, false }, { 0, true } }) do
        local f = fixture(); f:request(true)
        f:external(DurabilityFrame, "SetAlpha", values[1]); f:external(DurabilityFrame, "EnableMouse", values[2])
        f:masked(); f:request(false); f:original(nil, values[1], values[2])
    end
end)

check("combat and denied permission defer acquisition and the final restoration", function()
    local f = fixture(); f.combat = true; f:request(true); f:original()
    f.combat = false; f:emit("PLAYER_REGEN_ENABLED"); f:masked()
    f.combat = true; f:request(false); f:masked()
    f.combat, f.permission = false, false; f:emit("PLAYER_REGEN_ENABLED"); f:masked()
    f.permission = true; f:step(); f:original()
end)

check("late or replaced native warnings recover without loading addons or retaining the old borrowed frame", function()
    local f = fixture({ lazy = true }); f:request(true); assert(f:tip():find("not available yet", 1, true))
    DurabilityFrame = f:makeNative(); f:emit("ADDON_LOADED"); f:masked()
    local previous = DurabilityFrame; DurabilityFrame = f:makeNative(); f:step()
    f:original(previous); f:masked(); f:request(false); f:original()
end)

check("missing restricted or malformed native data degrades only the optional feature and can recover", function()
    for _, mode in ipairs({ "alpha", "mouse", "permission", "edit", "selection", "hooks" }) do
        local f = fixture(); local frame, repair = DurabilityFrame
        if mode == "alpha" then frame.alphaRead = f.secret; repair = function() frame.alphaRead = nil end
        elseif mode == "mouse" then frame.mouseRead = f.secret; repair = function() frame.mouseRead = nil end
        elseif mode == "permission" then f.permission = f.secret; repair = function() f.permission = true end
        elseif mode == "edit" then f.edit = f.secret; repair = function() f.edit = false end
        elseif mode == "selection" then
            local shown = frame.Selection.IsShown; frame.Selection.IsShown = function() return f.secret end
            repair = function() frame.Selection.IsShown = shown end
        else local hook = hooksecurefunc; hooksecurefunc = nil; repair = function() hooksecurefunc = hook end end
        f:request(true); equal(f.widget.failed, nil); equal(frame.alphaWrites, 0); equal(frame.mouseWrites, 0)
        assert(f:tip():find("unavailable", 1, true) or f:tip():find("could not", 1, true))
        repair(); f:step(); f:masked(); f:request(false); f:original()
    end
end)

check("rejected partial native changes roll back input and keep final restoration retryable", function()
    local f = fixture(); local frame = DurabilityFrame
    frame.throwAlpha = true; f:request(true); f:original(); equal(f.widget.failed, nil)
    frame.throwAlpha = false; f:step(); f:masked()
    frame.rejectAlpha = true; f:request(false); f:masked()
    frame.rejectAlpha = false; f:step(); f:original()
end)

check("uncertain permanent hooks decline that warning frame while a later native frame can recover", function()
    for _, failure in ipairs({ "before-attach", "attach-throw" }) do
        for _, target in ipairs({ "SetAlpha", "EnableMouse", "UpdateShownState" }) do
            local f = fixture(); local frame, hook, attempts = DurabilityFrame, hooksecurefunc, 0
            hooksecurefunc = function(owner, method, callback)
                if owner == frame and method == target then
                    attempts = attempts + 1
                    if failure == "attach-throw" then hook(owner, method, callback) end
                    error("uncertain permanent hook registration", 0)
                end
                return hook(owner, method, callback)
            end
            f:request(true); f:original(); equal(frame.alphaWrites, 0); equal(frame.mouseWrites, 0)
            local monitor, count = assert(f:controller()), #f.Stub.frames
            f:step(20)
            equal(attempts, 1)
            equal(f.hooks[frame] and f.hooks[frame][target] or 0, failure == "attach-throw" and 1 or 0)
            equal(#f.Stub.frames, count); equal(f:controller(), monitor); f:original()
            assert(f:tip():find("Reload the UI", 1, true))
            -- An exception before attachment is indistinguishable to the caller.
            -- Restoring the registration function cannot justify a second try.
            hooksecurefunc = hook; f:step(5); equal(attempts, 1); f:original()
            local previousHooks = f.hooks[frame]
            DurabilityFrame = f:makeNative(); f:step(); f:masked(); f:original(frame)
            assert(not f:tip():find("Reload the UI", 1, true), "old failed frame must not taint a healthy replacement")
            equal(f:controller(), monitor)
            for _, method in ipairs({ "SetAlpha", "EnableMouse", "UpdateShownState" }) do
                equal(f.hooks[DurabilityFrame][method], 1)
                if previousHooks and previousHooks[method] then equal(previousHooks[method], 1) end
            end
            f:request(false); f:original(); f:original(frame)
        end
    end
end)

check("an unreadable final restoration keeps ownership until public data returns", function()
    local f = fixture(); f:request(true); f:masked()
    local frame, monitor = DurabilityFrame, assert(f:controller())
    frame.alphaRead = f.secret; f:request(false)
    equal(frame.alpha, 0); equal(frame.mouseEnabled, false); equal(monitor:IsShown(), true)
    frame.alphaRead = nil; f:step(); f:original()
    equal(monitor:IsShown(), false); equal(next(monitor.events), nil)
end)

check("unreadable external setter readback yields to its later public policy without guessing old values", function()
    for _, values in ipairs({ { 0, false }, { 0.4, true } }) do
        local f = fixture(); f:request(true); f:masked()
        local frame, monitor = DurabilityFrame, assert(f:controller())
        local getAlpha, getMouse = frame.GetAlpha, frame.IsMouseEnabled
        local unreadable = true
        function frame:GetAlpha() if unreadable then return f.secret end; return getAlpha(self) end
        function frame:IsMouseEnabled() if unreadable then return f.secret end; return getMouse(self) end
        f:external(frame, "SetAlpha", values[1]); f:external(frame, "EnableMouse", values[2])
        local alphaWrites, mouseWrites = frame.alphaWrites, frame.mouseWrites
        f:request(false); equal(monitor:IsShown(), true)
        unreadable = false; f:step(); f:original(nil, values[1], values[2])
        equal(frame.alphaWrites, alphaWrites); equal(frame.mouseWrites, mouseWrites)
        equal(monitor:IsShown(), false)
        f:request(true); f:masked(); f:request(false); f:original(nil, values[1], values[2])
    end
end)

check("a widget rendering failure releases suppression before its ordinary error presentation", function()
    local f = fixture(); f:request(true); f:masked()
    local setText = f.widget.SetText; f.widget.SetText = function() error("original render failure", 0) end
    f.host:RefreshWidget(f.widget.id); equal(f.widget.failed, "original render failure"); f:original()
    f.widget.SetText = setText; f:refresh(); f:masked()
    f.host:RemoveWidget(f.widget.id); f:original()
end)

print(passed .. " native durability warning ownership tests passed")
