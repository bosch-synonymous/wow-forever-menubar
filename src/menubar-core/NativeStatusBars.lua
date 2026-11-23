-- Shared presentation ownership for Blizzard's XP and reputation bars.
-- Native selection, visibility, layout and container fades remain Blizzard's.
local Native = {}
_G.MenubarNativeStatusBars = Native

local function readable(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end
local function object(value)
    return readable(value) and (type(value) == "table" or type(value) == "userdata")
end
local function plain(value) return readable(value) and type(value) == "table" end
local function call(method, ...)
    if type(method) ~= "function" then return nil, false end
    local ok, value = pcall(method, ...)
    if not ok or not readable(value) then return nil, false end
    return value, true
end
local function integer(value)
    return readable(value) and type(value) == "number" and value >= 0
        and value < math.huge and value == math.floor(value)
end
local function alpha(value)
    return readable(value) and type(value) == "number" and value == value and value >= 0 and value <= 1
end

local kinds = {
    { id = "experience", enum = "Experience", child = "ExhaustionTick", requests = {},
        missing = "Blizzard's experience bar is not available yet." },
    { id = "reputation", enum = "Reputation", requests = {},
        missing = "Blizzard's reputation bar is not available yet." },
}
local byKind = { experience = kinds[1], reputation = kinds[2] }
local masks, hooks, desired, groups, containers = {}, setmetatable({}, { __mode = "k" }), {}, {}, {}
local monitor, ready, armed, elapsed, pending, busy, message, failure
local synchronize

local function requested()
    return next(kinds[1].requests) ~= nil or next(kinds[2].requests) ~= nil
end
local function report(reason)
    local ok, text = false, nil
    if readable(reason) then ok, text = pcall(tostring, reason) end
    failure = "Blizzard status-bar control failed: " .. (ok and readable(text) and type(text) == "string" and text or "details unavailable") .. ". It will retry."
end
local function write(target, method, value)
    if type(target[method]) ~= "function" then return false end
    if method == "EnableMouse" and call(target.CanChangeProtectedState, target) ~= true then return false end
    local ok, result = pcall(target[method], target, value)
    return ok and readable(result) and result ~= false
end
local function remember(target)
    local current = call(target.GetAlpha, target)
    if not alpha(current) or type(target.SetAlpha) ~= "function" then return nil end
    local saved = masks[target]
    if not saved then saved = { alpha = current }; masks[target] = saved end
    if current ~= 0 then saved.alpha = current end
    return saved, current
end
local function prepareInput(target, parent)
    local saved = remember(target)
    local enabled = call(target.IsMouseEnabled, target)
    if not saved or type(enabled) ~= "boolean" then return false end
    saved.parent = parent
    if saved.mouse == nil or enabled then saved.mouse = enabled end
    if enabled and not write(target, "EnableMouse", false) then return false end
    return call(target.IsMouseEnabled, target) == false
end
local function mask(target)
    local saved, current = remember(target)
    if not saved then return false end
    if current == 0 then return true end
    return write(target, "SetAlpha", 0) and call(target.GetAlpha, target) == 0
end
local function restore(target, saved)
    if saved.parent and masks[saved.parent] then return false end
    local current = call(target.GetAlpha, target)
    local ok = alpha(current)
    if current == 0 and saved.alpha ~= 0 then
        ok = write(target, "SetAlpha", saved.alpha) and call(target.GetAlpha, target) == saved.alpha
    end
    if not ok then return false end
    if saved.mouse ~= nil then
        local enabled = call(target.IsMouseEnabled, target)
        if type(enabled) ~= "boolean" then ok = false
        elseif not enabled and saved.mouse then
            ok = write(target, "EnableMouse", true) and call(target.IsMouseEnabled, target) == true
        end
    end
    if ok then masks[target] = nil end
    return ok
end
local function changed()
    if not requested() and not next(masks) then return end
    if busy then pending = true else synchronize() end
end
local function resized()
    if requested() then pending = true end
end
local function observe(target, script, handler)
    if not object(target) or type(target.HookScript) ~= "function" then return end
    local scripts = hooks[target]
    if not scripts then scripts = {}; hooks[target] = scripts end
    if not scripts[script] then
        local ok, result = pcall(target.HookScript, target, script, handler)
        -- Retain an attempted permanent registration even if it threw after
        -- attachment; polling is the fallback, not duplicate native callbacks.
        scripts[script] = true
        if not ok or not readable(result) or result == false then pending = true end
    end
end
local function arm()
    if not monitor then
        if type(CreateFrame) ~= "function" then return end
        monitor = CreateFrame("Frame")
    end
    if not ready then
        monitor:SetScript("OnEvent", changed)
        monitor:SetScript("OnUpdate", function(_, delta)
            if not readable(delta) or type(delta) ~= "number" or delta ~= delta or delta < 0 or delta == math.huge then return end
            elapsed = (elapsed or 0) + delta
            if pending or elapsed >= 0.25 then pending, elapsed = false, 0; changed() end
        end)
        ready = true
    end
    if not armed then
        for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
            pcall(monitor.RegisterEvent, monitor, event)
        end
        armed, elapsed = true, 0
        monitor:Show()
    end
end
local function collectTarget(container, bars, kind, index, count)
    local bar = bars[index]
    if not object(bar) then return count, false end
    local tick = kind.child and bar[kind.child] or nil
    if not readable(tick) or (tick ~= nil and not object(tick)) then return count, false end
    count = count + 1
    local group = groups[count]
    if not group then group = {}; groups[count] = group end
    group.bar, group.tick = bar, tick
    desired[bar] = true
    if tick then desired[tick] = true end
    return count, true
end
local function suppress(group)
    local ok = prepareInput(group.bar)
    if ok and group.tick then ok = prepareInput(group.tick, group.bar) end
    if ok then ok = mask(group.bar) end
    if ok and group.tick then ok = mask(group.tick) end
    return ok
end
local function collectDividers(pool)
    for divider in pool:EnumerateActive() do if object(divider) then desired[divider] = false end end
end
local function collectChrome(container)
    local bars = container.bars
    if not plain(bars) then return false end
    local maskedShown, otherShown = false, false
    for _, bar in pairs(bars) do
        if object(bar) then
            local shown = call(bar.IsShown, bar)
            if shown == true then
                if desired[bar] == true then maskedShown = true else otherShown = true end
            elseif shown ~= false then otherShown = true end
        else otherShown = true end
    end
    -- Show/Hide callbacks can run before shownBarIndex is updated. Inspect
    -- actual public visibility, preserving chrome for any unmasked/unknown bar.
    if maskedShown and not otherShown then
        if object(container.BarFrameTexture) then desired[container.BarFrameTexture] = false end
        local pool = container.HorizontalDividersPool
        if object(pool) and type(pool.EnumerateActive) == "function" then collectDividers(pool) end
    end
    return true
end
local function clearWork()
    for target in pairs(desired) do desired[target] = nil end
    for _, group in ipairs(groups) do group.bar, group.tick = nil, nil end
    for index = #containers, 1, -1 do containers[index] = nil end
end
local function reconcile()
    failure = nil
    local count, complete = 0, true
    for _, kind in ipairs(kinds) do kind.found = false end
    if requested() then
        local manager, info = StatusTrackingBarManager, StatusTrackingBarInfo
        local available = object(manager) and manager.barContainers
        local enums = plain(info) and info.BarsEnum
        if plain(available) and plain(enums) then
            for _, container in ipairs(available) do
                local bars = object(container) and container.bars
                if plain(bars) then
                    containers[#containers + 1] = container
                    observe(container, "OnSizeChanged", resized)
                    for _, bar in pairs(bars) do
                        if object(bar) then observe(bar, "OnShow", changed); observe(bar, "OnHide", changed) end
                    end
                    for _, kind in ipairs(kinds) do
                        local index = enums[kind.enum]
                        if next(kind.requests) and integer(index) then
                            local ok, nextCount, found = pcall(collectTarget, container, bars, kind, index, count)
                            if ok then count = nextCount; kind.found = kind.found or found
                            else complete = false; report(nextCount) end
                        end
                    end
                end
            end
        end
    end
    for index = 1, count do
        local group = groups[index]
        local ok, hidden = pcall(suppress, group)
        if not ok or not hidden then
            complete, desired[group.bar] = false, nil
            if group.tick then desired[group.tick] = nil end
            if not ok then report(hidden) end
        end
    end
    -- Union shared chrome only after every target's input/alpha result is known.
    for _, container in ipairs(containers) do
        local ok, collected = pcall(collectChrome, container)
        if not ok or not collected then complete = false; if not ok then report(collected) end end
    end
    for target, saved in pairs(masks) do
        if not saved.parent and desired[target] == nil then
            local ok, restored = pcall(restore, target, saved)
            if not ok or not restored then complete = false; if not ok then report(restored) end end
        end
    end
    for target, saved in pairs(masks) do
        if saved.parent and desired[target] == nil then
            local ok, restored = pcall(restore, target, saved)
            if not ok or not restored then complete = false; if not ok then report(restored) end end
        end
    end
    for target, interactive in pairs(desired) do
        if not interactive then
            local ok, hidden = pcall(mask, target)
            if not ok or not hidden then complete = false; if not ok then report(hidden) end end
        end
    end
    message = not complete and "Blizzard's status bars could not be fully restored/hidden; they will retry." or nil
end
synchronize = function()
    if busy then pending = true; return end
    busy = true
    local ok, reason = pcall(reconcile)
    clearWork()
    busy = false
    if not ok then report(reason) end
    if requested() or next(masks) then
        local armedOK, armedReason = pcall(arm)
        if not armedOK then report(armedReason) end
    elseif monitor and armed then
        monitor:UnregisterAllEvents(); monitor:Hide()
        armed, pending, elapsed = false, false, 0
    end
end
function Native:Request(kind, owner, hide)
    local definition = readable(kind) and type(kind) == "string" and byKind[kind]
    if not definition or not object(owner) or not readable(hide) or type(hide) ~= "boolean" then return false end
    if hide then definition.requests[owner] = true else definition.requests[owner] = nil end
    if hide or next(masks) or armed then synchronize() end
    return true
end
function Native:Release(kind, owner)
    local definition = readable(kind) and type(kind) == "string" and byKind[kind]
    if not definition or not object(owner) or not definition.requests[owner] then return end
    definition.requests[owner] = nil
    synchronize()
end
function Native:GetMessage(kind)
    local definition = readable(kind) and type(kind) == "string" and byKind[kind]
    if not definition then return nil end
    if failure then return failure end
    if message then return message end
    if next(definition.requests) and not definition.found then return definition.missing end
end
