-- Public API v1. Providers register behavior; the host owns persistence and interaction.

local Model, Layout = MenubarModel, MenubarLayout

local Menubar = { NativeStatusBars = MenubarNativeStatusBars, API_VERSION = 1, VERSION = "0.11.30", CAPABILITIES = {
    directClick = true, guardedCallbacks = true, retainedContexts = true, eventOnly = true,
}, types = {}, runtime = {}, dormant = {}, bars = {} }

_G.Menubar = Menubar

local registrations, registeredEvents = {}, {}

local function public(value)

    return type(issecretvalue) ~= "function" or not issecretvalue(value)

end

local function finite(value)

    return public(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge

end

local function nonempty(value)

    return public(value) and type(value) == "string" and value:match("%S") ~= nil

end

local function errorText(value)

    if not public(value) then return "Error details are restricted." end

    local ok, result = pcall(tostring, value)

    return ok and result or "Error details are unavailable."

end

local function say(message)

    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then

        pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, "|cffccccccMenubar:|r " .. message)

    end

end

Menubar.Print = say

local function eventMembership(frame, event)
    if type(frame.IsEventRegistered) ~= "function" then return nil end
    local ok, registered = pcall(frame.IsEventRegistered, frame, event)
    return ok and public(registered) and registered == true
end

local function registerEvent(event)
    if registeredEvents[event] ~= nil then return registeredEvents[event] end
    local frame = Menubar.eventFrame
    local registered = eventMembership(frame, event)
    if registered ~= true then
        local ok, result = pcall(frame.RegisterEvent, frame, event)
        registered = eventMembership(frame, event)
        -- Read actual membership when available. Older APIs may return nothing
        -- on success; use that contract only when membership readback is absent.
        if registered == nil then registered = ok and public(result) and result ~= false end
    end
    registeredEvents[event] = registered == true
    return registeredEvents[event]
end


local function mergeDefaults(target, defaults, seen)
    if not defaults then return end
    seen = seen or {}
    local targets = seen[defaults]
    if targets and targets[target] then return end
    if not targets then targets = {}; seen[defaults] = targets end
    targets[target] = true
    for key, value in pairs(defaults) do
        if target[key] == nil then target[key] = Model.DeepCopy(value)
        elseif type(value) == "table" and type(target[key]) == "table" then
            mergeDefaults(target[key], value, seen)
        end
    end
end

local function persistentDefaults(value, ancestors, depth, budget)
    assert(public(value), "Menubar: defaults cannot contain restricted values")
    local kind = type(value)
    if kind ~= "table" then
        assert(kind == "nil" or kind == "string" or kind == "boolean" or (kind == "number" and finite(value)),
            "Menubar: defaults must contain only serializable settings values")
        return
    end
    ancestors, depth, budget = ancestors or {}, depth or 0, budget or { count = 0 }
    assert(not ancestors[value], "Menubar: defaults cannot contain cycles")
    assert(depth < 64, "Menubar: defaults are nested too deeply")
    assert(getmetatable(value) == nil, "Menubar: defaults must be plain settings tables")
    ancestors[value] = true
    for key, item in pairs(value) do
        budget.count = budget.count + 1
        assert(budget.count <= 10000, "Menubar: defaults contain too many settings")
        assert(public(key) and (type(key) == "string" or type(key) == "boolean" or finite(key)),
            "Menubar: defaults contain an invalid settings key")
        persistentDefaults(item, ancestors, depth + 1, budget)
    end
    ancestors[value] = nil
end

local function validateLegacyDefaults(legacy, defaults)
    if not legacy then return end
    for key, value in pairs(legacy) do
        assert(type(defaults) == "table" and defaults[key] ~= nil,
            "Menubar: legacy defaults must reference declared default keys")
        if type(value) == "table" then validateLegacyDefaults(value, defaults[key]) end
    end
end

local function pack(...) return { n = select("#", ...), ... } end

local function phase(host, run, ...)
    host.workDepth = (host.workDepth or 0) + 1
    local ok, message = pcall(run, ...)
    host.workDepth = host.workDepth - 1
    if not ok then error(message, 0) end
    host:FlushWork()
end

function Menubar:IsCurrentWidget(widget)
    return self.ready and self.runtime[widget.id] == widget and not widget._menubarDestroyed
        and widget.instance.enabled ~= false and widget.settings == widget.instance.settings
        and widget.definition == self.types[widget.instance.type]
        and Model.GetWidget(self.db, self.characterKey, widget.id) == widget.instance
end

function Menubar:FlushWork()
    if not self.ready or (self.workDepth or 0) > 0 or self.flushingWork then return end
    if not self.pendingRebuild and not (self.pendingRefresh and next(self.pendingRefresh)) and not self.dirty then return end
    self.flushingWork = true
    local ok, message = pcall(function()
        -- One structural pass and one finite refresh snapshot per drain. Work
        -- requested by that pass is coalesced until the next native pulse.
        if self.pendingRebuild then
            self.pendingRebuild = nil
            self:RebuildNow()
        end
        local requests = self.pendingRefresh or {}
        self.pendingRefresh = {}
        for widget in pairs(requests) do
            if self:IsCurrentWidget(widget) and not widget.failed then self:RefreshNow(widget) end
        end
        if self.dirty then self:Layout() end
    end)
    self.flushingWork = nil
    if not ok then error(message, 0) end
end

local function array(values, label)

    assert(type(values) == "table", "Menubar: " .. label .. " must be an array")

    local count, maximum = 0, 0

    for index in pairs(values) do

        assert(finite(index) and index >= 1 and index == math.floor(index), "Menubar: " .. label .. " must be an array")

        count, maximum = count + 1, math.max(maximum, index)

    end

    assert(count == maximum, "Menubar: " .. label .. " must be a dense array")

end

local function validateSettings(settings)

    array(settings, "settings")

    local keys = {}

    for _, field in ipairs(settings) do

        assert(type(field) == "table" and nonempty(field.key) and nonempty(field.label), "Menubar: setting key and label are required")

        assert(not keys[field.key], "Menubar: duplicate setting key " .. field.key)

        keys[field.key] = field

        assert(field.type == "select" or field.type == "toggle" or field.type == "text" or field.type == "number" or field.type == "color",

            "Menubar: invalid setting type")

        if field.type == "number" then

            assert(field.min == nil or finite(field.min), "Menubar: invalid setting minimum")

            assert(field.max == nil or finite(field.max), "Menubar: invalid setting maximum")

            local minimum, maximum = field.min or 0, field.max or 1000000

            assert(minimum <= maximum, "Menubar: setting bounds are reversed")

            assert(field.integer == nil or type(field.integer) == "boolean", "Menubar: invalid integer setting flag")

            assert(not field.integer or math.ceil(minimum) <= math.floor(maximum),

                "Menubar: integer setting bounds contain no integer")

        elseif field.type == "select" then

            assert(type(field.options) == "table" or type(field.options) == "function", "Menubar: select options are required")

            if type(field.options) == "table" then

                array(field.options, "select options")

                for _, option in ipairs(field.options) do

                    assert(type(option) == "table" and nonempty(option.label) and public(option.value), "Menubar: invalid select option")

                    local kind = type(option.value)

                    assert(kind == "string" or kind == "boolean" or (kind == "number" and finite(option.value)), "Menubar: invalid select value")

                    assert(option.group == nil or nonempty(option.group), "Menubar: invalid select group")

                end

            end

        end

    end

    -- Numeric controls may depend on a toggle declared anywhere in this list.
    for _, field in ipairs(settings) do
        assert(public(field.enabledBy), "Menubar: enabledBy must be public")
        if field.enabledBy ~= nil then
            assert(field.type == "number" and nonempty(field.enabledBy), "Menubar: enabledBy requires a numeric setting and toggle key")
            assert(keys[field.enabledBy] and keys[field.enabledBy].type == "toggle", "Menubar: enabledBy must reference a toggle setting")
        end
    end

end

function Menubar:RegisterWidgetType(definition)

    assert(public(definition) and type(definition) == "table", "Menubar: widget definition must be a table")
    persistentDefaults(definition.defaults)
    assert(public(definition.legacyDefaults) and (definition.legacyDefaults == nil or type(definition.legacyDefaults) == "table"),
        "Menubar: legacy defaults must be a table")
    persistentDefaults(definition.legacyDefaults)
    validateLegacyDefaults(definition.legacyDefaults, definition.defaults)
    -- Providers retain their own declarations. The host owns this validated
    -- snapshot, including nested settings/options/defaults, legacy defaults and placement.
    definition = Model.DeepCopy(definition)

    assert(nonempty(definition.id) and definition.id:match("^[%w_%-]+$"), "Menubar: invalid widget type id")

    assert(nonempty(definition.name), "Menubar: widget name is required")

    assert(not self.types[definition.id], "Menubar: duplicate widget type " .. definition.id)

    assert(definition.clickHint == nil or nonempty(definition.clickHint), "Menubar: click hint must be a nonempty string")

    assert(definition.wheelHint == nil or nonempty(definition.wheelHint), "Menubar: wheel hint must be a nonempty string")

    for _, callback in ipairs({ "create", "update", "event", "tooltip", "contextMenu", "mouseWheel", "click", "reset", "destroy", "activate", "deactivate" }) do

        assert(definition[callback] == nil or type(definition[callback]) == "function", "Menubar: " .. callback .. " must be a function")

    end

    assert(public(definition.interval) and (definition.interval == nil or definition.interval == false or (finite(definition.interval) and definition.interval >= 0.02)),

        "Menubar: interval must be false or at least 0.02 seconds")

    assert(definition.defaults == nil or type(definition.defaults) == "table", "Menubar: defaults must be a table")

    assert(definition.defaultPlacement == nil or definition.defaultPlacement == false or type(definition.defaultPlacement) == "table",

        "Menubar: invalid default placement")

    assert(public(definition.retainOnDisable) and (definition.retainOnDisable == nil or type(definition.retainOnDisable) == "boolean"),
        "Menubar: retainOnDisable must be a boolean")
    assert((definition.activate == nil and definition.deactivate == nil) or definition.retainOnDisable == true,
        "Menubar: activate/deactivate require retainOnDisable")
    if type(definition.defaultPlacement) == "table" then
        local placement = definition.defaultPlacement
        assert(placement.bar == nil or placement.bar == "top" or placement.bar == "bottom", "Menubar: invalid default bar")
        assert(placement.alignment == nil or placement.alignment == "left" or placement.alignment == "center"
            or placement.alignment == "right", "Menubar: invalid default alignment")
        assert(placement.order == nil or (finite(placement.order) and placement.order >= 1
            and placement.order == math.floor(placement.order)), "Menubar: invalid default order")
        assert(public(placement.sidebarOrder) and (placement.sidebarOrder == nil or (finite(placement.sidebarOrder)
            and placement.sidebarOrder >= 1 and placement.sidebarOrder == math.floor(placement.sidebarOrder))),
            "Menubar: invalid default sidebar order")
    end
    if definition.settings ~= nil then validateSettings(definition.settings) end

    local events = {}

    if definition.events ~= nil then

        array(definition.events, "events")

        for _, event in ipairs(definition.events) do

            assert(nonempty(event), "Menubar: event names must be nonempty strings")

            events[event] = true

        end

    end

    self.types[definition.id] = definition

    registrations[definition.id] = { events = events, interval = definition.interval == nil and 1 or definition.interval }

    for event in pairs(events) do

        if registeredEvents[event] == nil and not registerEvent(event) then
            say("Event " .. event .. " is unavailable; only widgets with a numeric interval can use polling.")
        end

    end

    if self.ready then self.pendingDefaults = true; self:Rebuild() end

end

function Menubar:GetProfile()

    return Model.GetProfile(self.db, self.characterKey)

end

function Menubar:RegisterFont(name, regular, faces)

    return MenubarFonts.Register(name, regular, faces)

end

function Menubar:HasCoreMenu(bar)

    local profile = self:GetProfile()

    return profile.placement ~= "both" or profile.coreMenuBar == "both" or profile.coreMenuBar == bar

end

function Menubar:SidebarInstances()

    return Model.GetCharacter(self.db, self.characterKey).widgets

end

function Menubar:ReorderSidebar(id, delta)

    local widgets = self:SidebarInstances()

    for i, instance in ipairs(widgets) do

        if instance.id == id then

            local target = math.max(1, math.min(#widgets, i + delta))

            widgets[i], widgets[target] = widgets[target], widgets[i]

            break

        end

    end

    local order = {}

    for _, instance in ipairs(widgets) do

        local key = instance.bar .. ":" .. instance.alignment

        order[key] = (order[key] or 0) + 1

        instance.order = order[key]

    end

    self:Rebuild()

end

function Menubar:EnsureDefaults()

    local character = Model.GetCharacter(self.db, self.characterKey)

    local ids = {}

    for id in pairs(self.types) do ids[#ids + 1] = id end

    table.sort(ids, function(a, b)
        local first, second = self.types[a].defaultPlacement, self.types[b].defaultPlacement
        local firstOrder = type(first) == "table" and first.sidebarOrder or math.huge
        local secondOrder = type(second) == "table" and second.sidebarOrder or math.huge
        if firstOrder == secondOrder then return a < b end
        return firstOrder < secondOrder
    end)

    for _, id in ipairs(ids) do

        if not character.initializedTypes[id] then

            local exists = false

            for _, instance in ipairs(character.widgets) do

                if instance.type == id then exists = true; break end

            end

            local definition = self.types[id]

            if not exists and definition.defaultPlacement ~= false then

                local placement = Model.DeepCopy(definition.defaultPlacement or {})

                if self:GetProfile().placement ~= "both" then placement.bar = self:GetProfile().placement end

                Model.AddWidget(self.db, self.characterKey, id, definition.defaults or {}, placement)

            end

            character.initializedTypes[id] = true

        end

    end

end


local function finishInvoke(self, widget, callback, previous, previousFailure, previousFailedCallback, ok, ...)
    widget._menubarCallback = previous
    widget.reportedFailures = widget.reportedFailures or {}
    if not ok then
        local failure = errorText((...))
        if callback ~= "destroy" then
            widget.failed, widget.failedCallback = failure, callback
            if widget.definition.reset then pcall(widget.definition.reset, widget, callback) end
            if self.UI and self.UI.ResetWidgetPresentation then
                pcall(self.UI.ResetWidgetPresentation, self.UI, widget)
            elseif widget.HideGauge then pcall(widget.HideGauge, widget) end
            pcall(widget.SetText, widget, "[" .. (widget.definition.name or widget.instance.type) .. ": error]")
            if callback == "deactivate" and previousFailure then
                widget.failed, widget.failedCallback = previousFailure, previousFailedCallback
            end
        end
        if widget.reportedFailures[callback] ~= failure then
            say("Widget " .. widget.instance.type .. " (" .. widget.id .. ") failed in " .. callback .. ": " .. failure)
            widget.reportedFailures[callback] = failure
        end
    else
        -- Recovery of an unrelated update must not reset an event/callback
        -- failure episode. Each callback clears only its own diagnostic.
        widget.reportedFailures[callback] = nil
    end
    self.workDepth = self.workDepth - 1
    self:FlushWork()
    return ok, ...
end

function Menubar:Invoke(widget, callback, handler, ...)
    self.workDepth = (self.workDepth or 0) + 1
    local previous, previousFailure, previousFailedCallback = widget._menubarCallback, widget.failed, widget.failedCallback
    widget._menubarCallback = callback
    -- Forward the complete protected-call tuple, including trailing nils,
    -- without allocating a result table for every provider update.
    return finishInvoke(self, widget, callback, previous, previousFailure, previousFailedCallback, pcall(handler, widget, ...))
end

function Menubar:Call(widget, callback, ...)
    local handler = widget.definition and widget.definition[callback]
    if not handler or (widget.failed and callback ~= "destroy" and callback ~= "deactivate") then return true end
    return self:Invoke(widget, callback, handler, ...)
end

function Menubar:GuardCallback(widget, handler, menu)
    assert(type(handler) == "function", "Menubar: guarded callback must be a function")
    local database, character, instance, settings, definition, epoch = self.db, self.characterKey,
        widget.instance, widget.settings, widget.definition, widget._menubarEpoch
    local token = menu and self.UI and self.UI.contextToken
    assert(not menu or (token and widget._menubarCallback == "contextMenu"),
        "Menubar: MenuCallback must be created while generating its menu")
    return function(...)
        if self.db ~= database or self.characterKey ~= character or widget.instance ~= instance
            or widget.settings ~= settings or instance.settings ~= settings or widget.definition ~= definition
            or widget._menubarEpoch ~= epoch or widget.failed or not self:IsCurrentWidget(widget)
            or (menu and (not self.UI or self.UI.contextToken ~= token)) then return end
        local result = pack(self:Invoke(widget, menu and "menuCallback" or "callback", function(_, ...)
            return handler(...)
        end, ...))
        if result[1] then return unpack(result, 2, result.n) end
    end
end

function Menubar:AddWidget(typeID, bar, alignment)

    local definition = self.types[typeID]

    if not definition then return end

    local preferred = type(definition.defaultPlacement) == "table" and definition.defaultPlacement or {}
    local active = self:GetProfile().placement
    local defaultBar = active == "both" and (preferred.bar or "top") or active

    local instance = Model.AddWidget(self.db, self.characterKey, typeID, definition.defaults or {},

        { bar = bar or defaultBar, alignment = alignment or preferred.alignment or "right" })

    self:Rebuild()

    return instance

end

function Menubar:RemoveWidget(id)

    Model.RemoveWidget(self.db, self.characterKey, id)

    self:Rebuild()

end

function Menubar:EffectiveBar(instance)

    local placement = self:GetProfile().placement

    return placement == "both" and instance.bar or placement

end

function Menubar:DisplayInstances(bar, alignment)

    local list = {}

    for _, instance in ipairs(Model.ListWidgets(self.db, self.characterKey)) do

        if self:EffectiveBar(instance) == bar and (not alignment or instance.alignment == alignment) then

            list[#list + 1] = instance

        end

    end

    table.sort(list, function(a, b)

        if a.order == b.order then return a.id < b.id end

        return a.order < b.order

    end)

    return list

end

function Menubar:ReorderWidget(instance, delta)

    local bar = self:EffectiveBar(instance)

    local siblings = self:DisplayInstances(bar, instance.alignment)

    for i, sibling in ipairs(siblings) do

        if sibling.id == instance.id then

            local target = math.max(1, math.min(#siblings, i + delta))

            siblings[i], siblings[target] = siblings[target], siblings[i]

            break

        end

    end

    for i, sibling in ipairs(siblings) do sibling.order, sibling.bar = i, bar end

    local widgets, index = self:SidebarInstances(), 1

    for i, candidate in ipairs(widgets) do

        if self:EffectiveBar(candidate) == bar and candidate.alignment == instance.alignment then

            widgets[i], index = siblings[index], index + 1

        end

    end

    self:Rebuild()

end


function Menubar:RefreshNow(widget)
    if not self:IsCurrentWidget(widget) then return end
    if self.pendingRefresh then self.pendingRefresh[widget] = nil end
    local retryCreate = widget.failedCallback == "create"
    widget.failed, widget.failedCallback = nil, nil
    widget.sinceUpdate = 0
    if retryCreate then self:Call(widget, "create") end
    if widget.definition and widget.definition.retainOnDisable and not widget._menubarActive and not widget.failed then
        local ok = self:Call(widget, "activate")
        if ok then widget._menubarActive = true end
    end
    self:Call(widget, "update")
end

function Menubar:RefreshWidget(id)
    local widget = self.runtime[id]
    if not widget or widget._menubarCallback == "update" then return end
    if (self.workDepth or 0) > 0 or self.flushingWork then
        self.pendingRefresh = self.pendingRefresh or {}
        self.pendingRefresh[widget] = true
        return
    end
    phase(self, function() self:RefreshNow(widget) end)
end

function Menubar:RefreshAll()
    if (self.workDepth or 0) > 0 or self.flushingWork then
        self.pendingRefresh = self.pendingRefresh or {}
        for _, widget in pairs(self.runtime) do
            if widget._menubarCallback ~= "update" then self.pendingRefresh[widget] = true end
        end
        return
    end
    phase(self, function()
        for _, widget in pairs(self.runtime) do self:RefreshNow(widget) end
    end)
end

function Menubar:DeactivateWidget(widget)
    widget._menubarEpoch = {}
    if widget._menubarActive then
        widget._menubarActive = nil
        self:Call(widget, "deactivate")
    end
end

function Menubar:DestroyWidget(widget)
    if widget._menubarDestroyed then return end
    self:DeactivateWidget(widget)
    widget._menubarDestroyed = true
    widget._menubarEpoch = {}
    self:Call(widget, "destroy")
    widget.frame:Hide()
    for _, script in ipairs({ "OnEnter", "OnLeave", "OnClick", "OnMouseWheel" }) do widget.frame:SetScript(script, nil) end
end

function Menubar:RebuildNow()
    phase(self, function()
        if self.UI.CloseBarMenu then self.UI:CloseBarMenu() end
        self.UI.contextToken = nil
        if self.pendingDefaults then self.pendingDefaults = nil; self:EnsureDefaults() end
        if GameTooltip and GameTooltip:GetOwner() then
            for _, widget in pairs(self.runtime) do
                if GameTooltip:GetOwner() == widget.frame then GameTooltip:Hide(); break end
            end
        end
        local previous = self.runtime
        for _, widget in pairs(previous) do widget.frame:Hide() end
        self.runtime = {}
        self.UI:UpdateBars()
        for id, widget in pairs(self.dormant) do
            if Model.GetWidget(self.db, self.characterKey, id) ~= widget.instance
                or self.types[widget.instance.type] ~= widget.definition then
                self.dormant[id] = nil; self:DestroyWidget(widget)
            end
        end
        for _, instance in ipairs(Model.ListWidgets(self.db, self.characterKey)) do
            local definition = self.types[instance.type]
            if definition then
                -- Missing saved fields keep their prior behavior. Fresh instances
                -- and explicit resets already contain the complete factory values.
                mergeDefaults(instance.settings, definition.legacyDefaults)
                mergeDefaults(instance.settings, definition.defaults)
            end
            if instance.enabled ~= false then
                local old = previous[instance.id] or self.dormant[instance.id]
                if old and (old.instance ~= instance or old.definition ~= definition) then self:DestroyWidget(old); old = nil end
                if old and definition and definition.retainOnDisable and old.settings ~= instance.settings then
                    self:DeactivateWidget(old)
                end
                if self.dormant[instance.id] then
                    if old then old._menubarEpoch = {} end
                    self.dormant[instance.id] = nil
                end
                self.UI:CreateWidget(instance, old)
                previous[instance.id] = nil
            end
        end
        for id, widget in pairs(previous) do
            local instance = Model.GetWidget(self.db, self.characterKey, id)
            if instance == widget.instance and instance.enabled == false and widget.definition
                and widget.definition.retainOnDisable and self.types[instance.type] == widget.definition then
                self:DeactivateWidget(widget)
                self.dormant[id] = widget
            else self:DestroyWidget(widget) end
        end
        for _, widget in pairs(self.runtime) do self:RefreshNow(widget) end
        self:Layout()
    end)
end

function Menubar:Rebuild()
    if not self.ready or not self.UI then return end
    self.pendingRebuild = true
    self:FlushWork()
end

function Menubar:Layout()

    if not self.ready then return end

    local profile = self:GetProfile()

    for name, bar in pairs(self.bars) do

        if bar:IsShown() then

            local items = {}

            for _, instance in ipairs(self:DisplayInstances(name)) do

                local widget = self.runtime[instance.id]

                if widget then

                    items[#items + 1] = { id = widget.id, width = widget.width, alignment = instance.alignment }

                end

            end

            local positions, hidden = Layout.Compute(items, bar:GetWidth(), profile.padding, profile.spacing,

                self:HasCoreMenu(name) and 24 or 0)

            bar.hiddenWidgets = hidden

            bar.overflow:SetShown(#hidden > 0)

            bar.empty:SetShown(#items == 0)

            for _, item in ipairs(items) do

                local widget = self.runtime[item.id]

                widget.frame:ClearAllPoints()

                if positions[item.id] then

                    widget.frame:SetPoint("LEFT", bar, "LEFT", positions[item.id], 0)

                    widget.frame:Show()

                else widget.frame:Hide() end

            end

        end

    end

    self.dirty = false

end

local function legacyCandidate(recovery, key)
    for _, candidate in ipairs(recovery and recovery.legacyKeys or {}) do
        if candidate == key then return true end
    end
    return false
end

function Menubar:Start()
    if self.ready then return end
    local identity, message, recovery = MenubarIdentity.Read(MenubarDB)
    self.identityRecovery = recovery
    local choice = self.identityChoice
    if not identity and recovery and choice and choice.database == MenubarDB
        and choice.key == recovery.key and legacyCandidate(recovery, choice.legacy) then
        identity = { key = recovery.key, legacyKeys = { choice.legacy } }
    end
    if not identity then
        if self.startupMessage ~= message then say(message); self.startupMessage = message end
        return
    end
    local db, character, profile, reason = Model.Initialize(MenubarDB, identity.key, identity.legacyKeys)
    if not db then
        reason = reason or "Could not load settings."
        if self.startupMessage ~= reason then say(reason); self.startupMessage = reason end
        return
    end
    MenubarDB, self.db, self.characterKey = db, db, identity.key
    self.startupMessage, self.identityChoice, self.identityRecovery = nil, nil, nil
    self.ready = true
    self:EnsureDefaults()
    self:Rebuild()
    if self.UI and self.UI.RegisterSettingsCategory then self.UI:RegisterSettingsCategory() end
end

function Menubar:OpenIdentityRecovery()
    if self.ready then say("This character's layout is already loaded."); return end
    local identity, message, recovery = MenubarIdentity.Read(MenubarDB)
    if identity then self:Start(); return end
    if not recovery then say(message); return end
    local database, ui = MenubarDB, self.UI
    ui:Context(UIParent, function(root, token)
        root:CreateTitle("Recover Menubar layout")
        if #recovery.legacyKeys > 12 then root:SetScrollMode(400) end
        for _, candidate in ipairs(recovery.legacyKeys) do
            local key = candidate
            root:CreateButton(key, function()
                if self.ready or MenubarDB ~= database or self.UI ~= ui or ui.contextToken ~= token then return end
                local current, _, pending = MenubarIdentity.Read(MenubarDB)
                if current or not pending or pending.key ~= recovery.key or not legacyCandidate(pending, key) then return end
                ui.contextToken = nil
                self.identityChoice = { key = pending.key, legacy = key, database = database }
                self:Start()
            end)
        end
    end)
end

local eventFrame = CreateFrame("Frame")

Menubar.eventFrame = eventFrame

for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
    "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
    if not registerEvent(event) then say("Core event " .. event .. " could not be registered.") end
end


local function dispatchEvent(event, ...)
    -- Structural changes are deferred, keeping this runtime table stable
    -- throughout the phase. Native payloads remain on this call's stack.
    for _, widget in pairs(Menubar.runtime) do
        local registration = widget.definition and registrations[widget.definition.id]
        if registration and registration.events[event] and Menubar:IsCurrentWidget(widget) then
            Menubar:RefreshNow(widget)
            if Menubar:IsCurrentWidget(widget) then Menubar:Call(widget, "event", event, ...) end
        end
    end
end

local function updateTimers(elapsed)
    for _, widget in pairs(Menubar.runtime) do
        local registration = widget.definition and registrations[widget.definition.id]
        if Menubar:IsCurrentWidget(widget) then
            if not widget.frame:IsVisible() then
                widget.elapsed, widget.sinceUpdate, widget.suspended = 0, 0, true
            elseif registration and not widget.failed then
                if widget.suspended then
                    widget.suspended = nil
                    Menubar:RefreshNow(widget)
                elseif registration.interval then
                    widget.elapsed = widget.elapsed + elapsed
                    widget.sinceUpdate = (widget.sinceUpdate or 0) + elapsed
                    if widget.elapsed >= registration.interval then
                        local updateElapsed = widget.sinceUpdate
                        widget.elapsed, widget.sinceUpdate = widget.elapsed % registration.interval, 0
                        Menubar:Call(widget, "update", updateElapsed)
                    end
                end
            end
        end
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" or (not Menubar.ready and (event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED")) then Menubar:Start()
    elseif Menubar.ready and (event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED") then
        Menubar:Rebuild()
    elseif Menubar.ready then phase(Menubar, dispatchEvent, event, ...) end
end)

eventFrame:SetScript("OnUpdate", function(_, elapsed)
    if not Menubar.ready or not finite(elapsed) or elapsed < 0 then return end
    Menubar:FlushWork()
    phase(Menubar, updateTimers, elapsed)
end)

SLASH_MENUBAR1, SLASH_MENUBAR2 = "/menubar", "/mbar"

SlashCmdList.MENUBAR = function(message)
    if message and message:match("^%s*recover%s*$") then Menubar:OpenIdentityRecovery(); return end
    if not Menubar.ready then
        if Menubar.identityRecovery then Menubar:OpenIdentityRecovery()
        else say(Menubar.startupMessage or "Settings are unavailable; check the load error above.") end
        return
    end

    if message and message:match("^%s*status%s*$") then

        local count = 0

        for _ in pairs(Menubar.runtime) do count = count + 1 end

        say("v" .. Menubar.VERSION .. ", profile " .. Model.GetCharacter(Menubar.db, Menubar.characterKey).profile

            .. ", " .. count .. " widget(s). Client " .. tostring(GetBuildInfo()))

    else Menubar.UI:OpenSettings() end

end

-- Blizzard resolves this TOC callback when an AddOn Compartment entry is clicked.
-- Reuse the command's startup/recovery checks and the native settings route.
function Menubar_OnAddonCompartmentClick()
    SlashCmdList.MENUBAR("")
end
