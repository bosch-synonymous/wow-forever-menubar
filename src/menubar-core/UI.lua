-- Original Menubar presentation. Blizzard's menu system handles context-menu input.
local Host, Model = Menubar, MenubarModel
local UI = {}
local context
Host.UI = UI

local function public(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

-- A quick launch, slower return and small rebound move only the owned icon.
-- Hop into the play area so a screen-edge bar does not hide the feedback.
-- Repeated notifications during a burst are coalesced.
local jiggleOffsets = { 10, -10, 2.5, -2.5 }
local jiggleDurations = { 0.10, 0.26, 0.05, 0.12 }
local jiggleSmoothing = { "OUT", "IN", "OUT", "IN" }
local jiggleInterval = 0.265 -- Half of one complete hop, without changing its motion.
local function clearJiggleQueue(widget, queue)
    if widget.iconJiggleQueue == queue then widget.iconJiggleQueue = nil end
    if queue then
        queue.active, queue.cadenceToken, queue.pending, queue.present = nil, nil, nil, nil
        queue.database, queue.character, queue.instance, queue.settings, queue.definition = nil, nil, nil, nil, nil
    end
end

local function stopIconJiggle(widget)
    -- Native Stop may run scripts immediately. Invalidate queued work first.
    clearJiggleQueue(widget, widget.iconJiggleQueue)
    local stopped = true
    local cadence = widget.iconJiggleCadence
    if cadence and cadence.group then
        if not pcall(cadence.group.Stop, cadence.group) then stopped = false end
    end
    for _, motion in ipairs(widget.iconJiggles or {}) do
        if motion.group then
            -- Each stop is isolated so one cosmetic failure cannot prevent
            -- cleanup of the other icons or obscure the original error.
            local ok = pcall(motion.group.Stop, motion.group)
            if not ok then stopped = false end
        end
    end
    return stopped
end

local function validJiggleIcon(widget, icon)
    if widget.failed or Host.runtime[widget.id] ~= widget or widget.instance.enabled == false
        or not widget.frame:IsVisible() then return false end
    if not public(icon) or (type(icon) ~= "table" and type(icon) ~= "userdata")
        or type(icon.IsVisible) ~= "function" or not icon:IsVisible()
        or type(icon.GetObjectType) ~= "function" or type(icon.GetParent) ~= "function"
        or type(icon.CreateAnimationGroup) ~= "function" then return false end
    local kind, parent = icon:GetObjectType(), icon:GetParent()
    if not public(kind) or kind ~= "Texture" or not public(parent) or parent ~= widget.frame then return false end
    return true
end

local function jiggleMotion(widget, icon)
    local motions = widget.iconJiggles
    if not motions then motions = {}; widget.iconJiggles = motions end
    local motion
    for _, candidate in ipairs(motions) do if candidate.icon == icon then motion = candidate; break end end
    if not motion then
        -- Money has three coins and one reusable token icon. Keep the pool
        -- bounded even if a provider repeatedly passes newly allocated regions.
        if #motions >= 4 then return nil end
        motion = { icon = icon, steps = {} }
        motions[#motions + 1] = motion
        widget.iconJiggle = widget.iconJiggle or motion
    end
    if not motion.group then motion.group = icon:CreateAnimationGroup() end
    local direction = Host:EffectiveBar(widget.instance) == "top" and -1 or 1
    if not motion.ready or motion.direction ~= direction then
        motion.ready = false
        local group = motion.group
        group:SetLooping("NONE")
        for index, offset in ipairs(jiggleOffsets) do
            local step = motion.steps[index]
            if not step then step = group:CreateAnimation("Translation"); motion.steps[index] = step end
            step:SetOrder(index)
            step:SetDuration(jiggleDurations[index])
            step:SetOffset(0, offset * direction)
            step:SetSmoothing(jiggleSmoothing[index])
        end
        motion.direction, motion.ready = direction, true
    end
    return motion
end

local function jiggleCadence(widget)
    local cadence = widget.iconJiggleCadence
    if not cadence then cadence = {}; widget.iconJiggleCadence = cadence end
    if not cadence.group then cadence.group = widget.frame:CreateAnimationGroup() end
    if not cadence.ready then
        cadence.group:SetLooping("NONE")
        if not cadence.step then cadence.step = cadence.group:CreateAnimation() end
        cadence.step:SetOrder(1)
        cadence.step:SetDuration(jiggleInterval)
        cadence.ready = true
    end
    return cadence
end

local function jiggleIcon(widget, icon)
    if not validJiggleIcon(widget, icon) then return false end
    local motion = jiggleMotion(widget, icon)
    if not motion then return false end
    if widget.iconJiggleQueue and not stopIconJiggle(widget) then return false end
    if not motion.group:IsPlaying() then motion.group:Play() end
    return true
end

local function currentJiggleQueue(widget, queue)
    return widget.iconJiggleQueue == queue and Host.runtime[widget.id] == widget and not widget.failed
        and widget.instance == queue.instance and widget.settings == queue.settings and widget.definition == queue.definition
        and Host.db == queue.database and Host.characterKey == queue.character
        and widget.instance.enabled ~= false and widget.frame:IsVisible()
end

local protectedJiggleAdvance
local function advanceJiggleQueue(widget, queue)
    if not currentJiggleQueue(widget, queue) then
        if widget.iconJiggleQueue == queue then stopIconJiggle(widget) end
        return false
    end
    if queue.cadenceToken then return true end
    while #queue.pending > 0 do
        local motion = table.remove(queue.pending, 1)
        if validJiggleIcon(widget, motion.icon) then
            local token = {}
            queue.active[motion] = token
            motion.group:SetScript("OnFinished", function()
                if widget.iconJiggleQueue ~= queue or queue.active[motion] ~= token then return end
                queue.active[motion], queue.present[motion] = nil, nil
                protectedJiggleAdvance(widget, queue)
            end)
            motion.group:Play()
            if widget.iconJiggleQueue ~= queue then return false end
            local cadenceToken = {}
            queue.cadenceToken = cadenceToken
            queue.cadence.group:SetScript("OnFinished", function()
                if widget.iconJiggleQueue ~= queue or queue.cadenceToken ~= cadenceToken then return end
                queue.cadenceToken = nil
                protectedJiggleAdvance(widget, queue)
            end)
            -- Reserve the gap even when the pending list is momentarily empty:
            -- an early burst joins this cooldown instead of launching at once.
            queue.cadence.group:Restart()
            return true
        end
        queue.present[motion] = nil
    end
    if not next(queue.active) then clearJiggleQueue(widget, queue) end
    return true
end

protectedJiggleAdvance = function(widget, queue)
    local ok, result = pcall(advanceJiggleQueue, widget, queue)
    if not ok then
        if widget.iconJiggleQueue == queue then stopIconJiggle(widget) end
        local detail = "details unavailable"
        if public(result) then
            local readable, value = pcall(tostring, result)
            if readable then detail = value end
        end
        local message = "Icon animation could not continue: " .. detail
        if widget.iconJiggleQueueFailure ~= message then
            widget.iconJiggleQueueFailure = message
            if type(Host.Print) == "function" then pcall(Host.Print, message) end
        end
        return false
    end
    if result then widget.iconJiggleQueueFailure = nil end
    return result
end

local function jiggleIcons(widget, icons)
    if not public(icons) or type(icons) ~= "table" then return false end
    local count = 0
    for key in pairs(icons) do
        count = count + 1
        if count > 4 or not public(key) or type(key) ~= "number" or key < 1 or key > 4 or key ~= math.floor(key) then return false end
    end
    if count == 0 then return false end
    local prepared, seen = {}, {}
    for index = 1, count do
        local icon = rawget(icons, index)
        if not validJiggleIcon(widget, icon) then return false end
        if not seen[icon] then
            seen[icon] = true
            prepared[#prepared + 1] = icon
        end
    end
    -- Prepare all native resources in the caller's guarded update/event
    -- boundary, after copying and validating its reusable ordered array.
    for index, icon in ipairs(prepared) do
        local motion = jiggleMotion(widget, icon)
        if not motion or type(motion.group.SetScript) ~= "function" then return false end
        prepared[index] = motion
    end
    local cadence = jiggleCadence(widget)
    local queue = widget.iconJiggleQueue
    if queue and not currentJiggleQueue(widget, queue) then
        if not stopIconJiggle(widget) then return false end
        queue = nil
    end
    if not queue then
        -- Switching from the independent helper must not overlap an old motion.
        for _, motion in ipairs(widget.iconJiggles) do
            if motion.group:IsPlaying() then
                if not stopIconJiggle(widget) then return false end
                break
            end
        end
        queue = { database = Host.db, character = Host.characterKey, instance = widget.instance,
            settings = widget.settings, definition = widget.definition, cadence = cadence,
            pending = {}, present = {}, active = {} }
        widget.iconJiggleQueue = queue
    end
    for _, motion in ipairs(prepared) do
        if not queue.present[motion] then
            queue.pending[#queue.pending + 1], queue.present[motion] = motion, true
        end
    end
    return protectedJiggleAdvance(widget, queue)
end

local function shiftDown()
    if type(IsShiftKeyDown) ~= "function" then return false end
    local ok, down = pcall(IsShiftKeyDown)
    return ok and public(down) and down == true
end

local function mouseGlyph(button)
    if not public(C_Texture) or type(C_Texture) ~= "table" then return nil end
    local method = C_Texture.GetAtlasInfo
    if not public(method) or type(method) ~= "function" then return nil end
    local atlas = "newplayertutorial-icon-mouse-" .. button .. "button"
    local ok, info = pcall(method, atlas)
    if not ok or not public(info) or type(info) ~= "table" then return nil end
    local width, height = rawget(info, "width"), rawget(info, "height")
    if not public(width) or not public(height) or type(width) ~= "number" or type(height) ~= "number"
        or not (width > 0 and width < math.huge and height > 0 and height < math.huge) then return nil end
    return "|A:" .. atlas .. ":16:16:0:0|a"
end

local function leftGesture(glyph, shifted)
    if shifted then return glyph and ("Shift + " .. glyph) or "Shift-left-click" end
    return glyph or "Left-click"
end

local function interactionHints(tip, definition, failed)
    local left, right = mouseGlyph("left"), mouseGlyph("right")
    local actions = {}
    if definition and not failed then
        if type(definition.click) == "function" then
            actions[#actions + 1] = leftGesture(left) .. ": " .. (definition.clickHint or "activate")
        end
        if type(definition.mouseWheel) == "function" then
            actions[#actions + 1] = "Wheel: " .. (definition.wheelHint or "adjust")
        end
    end
    actions[#actions + 1] = leftGesture(left, true) .. ": menu"
    actions[#actions + 1] = (right or "Right-click") .. ": settings"
    tip:AddLine(table.concat(actions, "   "), 0.65, 0.65, 0.65, true)
end

local function controlTooltip(frame, barName, title, description, action)
    frame:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, barName == "bottom" and "ANCHOR_TOP" or "ANCHOR_BOTTOM")
        GameTooltip:AddLine(title)
        GameTooltip:AddLine(description, 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(leftGesture(mouseGlyph("left")) .. ": " .. action
            .. "   " .. (mouseGlyph("right") or "Right-click") .. ": settings", 0.65, 0.65, 0.65, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(owner)
        if GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
    end)
end

local function font(label, size)
    local profile = Host:GetProfile()
    local path = MenubarFonts and MenubarFonts.Resolve(profile, Host.db.customFonts) or profile.font
    local ok, result = pcall(label.SetFont, label, path, size or profile.fontSize, "")
    if not ok or result == false then label:SetFont(Model.DefaultProfile.font, size or profile.fontSize, "") end
    label:SetTextColor(unpack(profile.textColor))
    label:SetShadowColor(0, 0, 0, profile.textShadow and 1 or 0)
    label:SetShadowOffset(profile.textShadow and 1 or 0, profile.textShadow and -1 or 0)
end

local function contentGeometry(profile)
    local top, bottom = profile.topLineSize or 1, profile.bottomLineSize or 1
    return math.max(4, profile.height - top - bottom), (bottom - top) / 2
end

function UI:ResetWidgetPresentation(widget)
    stopIconJiggle(widget)
    MenubarGauge.Reset(widget)
    widget.customWidth = nil
    widget.label:ClearAllPoints()
    widget.label:SetPoint("CENTER", widget.content or widget.frame, "CENTER", 0, 0)
    widget.label:Show()
    font(widget.label)
end

function UI:Context(owner, generate) return context(owner, generate) end

local function fill(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetColorTexture(unpack(color))
    return texture
end

local function box(parent, color)
    local background = fill(parent, "BACKGROUND", color or { 0.86, 0.86, 0.86, 1 })
    background:SetAllPoints()
    parent.menubarBorder = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local line = fill(parent, "BORDER", { 0, 0, 0, 1 })
        parent.menubarBorder[#parent.menubarBorder + 1] = line
        if side == "TOP" or side == "BOTTOM" then
            line:SetHeight(1); line:SetPoint(side .. "LEFT"); line:SetPoint(side .. "RIGHT")
        else
            line:SetWidth(1); line:SetPoint("TOP" .. side); line:SetPoint("BOTTOM" .. side)
        end
    end
    return background
end

local function label(parent, text, size)
    local textRegion = parent:CreateFontString(nil, "OVERLAY")
    font(textRegion, size)
    textRegion:SetText(text)
    textRegion:SetJustifyH("LEFT")
    return textRegion
end

local function button(parent, text, width, callback, bare)
    local control = CreateFrame("Button", nil, parent)
    control:SetSize(width or 240, 24)
    control.menubarBare = bare == true
    if not control.menubarBare then control.background = box(control) end
    control.Label = label(control, text, 12)
    local inset = (width or 240) <= 32 and 2 or 8
    control.Label:SetPoint("LEFT", inset, 0)
    control.Label:SetPoint("RIGHT", -inset, 0)
    if not control.menubarBare then
        local highlight = fill(control, "HIGHLIGHT", { 0, 0, 0, 0.12 })
        highlight:SetAllPoints()
    end
    control:SetScript("OnClick", callback)
    return control
end

-- Original window-and-menubar glyph, drawn once from six owned rectangles.
local menuIconShape = {
    { -7, 6, 14, 3 }, { -7, 3, 1, 9 }, { 6, 3, 1, 9 },
    { -7, -5, 14, 1 }, { -4, 0, 8, 1 }, { -4, -2, 5, 1 },
}

local function finite(value)
    return public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function frameRect(frame)
    if not public(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata")
        or type(frame.GetRect) ~= "function" or type(frame.GetEffectiveScale) ~= "function" then return end
    local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
    local read, scale = pcall(frame.GetEffectiveScale, frame)
    if not ok or not read or not finite(left) or not finite(bottom) or not finite(width) or width <= 0
        or not finite(height) or height <= 0 or not finite(scale) or scale <= 0 then return end
    local right, top = (left + width) * scale, (bottom + height) * scale
    left, bottom = left * scale, bottom * scale
    if not finite(left) or not finite(bottom) or not finite(right) or not finite(top) then return end
    return { left = left, bottom = bottom, right = right, top = top, scale = scale }
end

local function ownerBar(owner)
    local current = owner
    for _ = 1, 16 do
        for _, name in ipairs({ "top", "bottom" }) do
            if current and current == Host.bars[name] then return current, name end
        end
        if not public(current) or (type(current) ~= "table" and type(current) ~= "userdata")
            or type(current.GetParent) ~= "function" then return end
        local ok, parent = pcall(current.GetParent, current)
        if not ok or not public(parent) or parent == current then return end
        current = parent
    end
end

local function menuGeometry(owner, bar, name, inset)
    local screen, source, barRect = frameRect(UIParent), frameRect(owner), frameRect(bar)
    if not screen or not source or not barRect then return end
    local upper, lower = screen.top, screen.bottom
    for _, edge in ipairs({ "top", "bottom" }) do
        local other = Host.bars[edge]
        if other and other:IsVisible() then
            local rect = frameRect(other)
            if not rect then return end
            if edge == "top" then upper = math.min(upper, rect.bottom) else lower = math.max(lower, rect.top) end
        end
    end
    -- Native context variants have different artwork outside their frame.
    -- Insets below are content padding, not that external border/shadow.
    local art = { left = 3, right = 3, top = 3, bottom = 4 }
    if inset.top == 14 and inset.bottom == 14 then art.top = 1
    elseif inset.top == 8 and inset.bottom == 15 then art.left, art.right, art.bottom = 10, 10, 3
    elseif inset.top ~= 10 or inset.bottom ~= 10 then
        -- Conservative bounds for the remaining verified shared menu variant.
        art = { left = 17, right = 17, top = 12, bottom = 22 }
    end
    local parent = type(GetAppropriateTopLevelParent) == "function" and GetAppropriateTopLevelParent() or UIParent
    local scale = parent and type(parent.GetScale) == "function" and parent:GetScale()
    if not finite(scale) or scale <= 0 then return end
    local gap = screen.scale -- One UIParent unit beyond the visible artwork.
    local limit = (upper - lower - 2 * gap) / scale - art.top - art.bottom - inset.top - inset.bottom
    if not finite(limit) or limit < 1 then return end
    local x = (source.left - barRect.left) / barRect.scale
    local width, height = (source.right - source.left) / barRect.scale, (barRect.top - barRect.bottom) / barRect.scale
    if not finite(x) or not finite(width) or width <= 0 or not finite(height) or height <= 0 then return end
    UI.menuAnchors = UI.menuAnchors or {}
    local anchorFrame = UI.menuAnchors[name]
    if not anchorFrame then
        anchorFrame = CreateFrame("Frame", nil, bar)
        UI.menuAnchors[name] = anchorFrame
        anchorFrame:EnableMouse(false)
    end
    anchorFrame:ClearAllPoints()
    anchorFrame:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
    anchorFrame:SetSize(width, height)
    anchorFrame:Show()
    local side = (source.left + source.right) / 2 > (screen.left + screen.right) / 2 and "RIGHT" or "LEFT"
    local down = name == "top"
    local offset = down and -(art.top + gap / scale) or art.bottom + gap / scale
    local anchor = AnchorUtil.CreateAnchor((down and "TOP" or "BOTTOM") .. side, anchorFrame,
        (down and "BOTTOM" or "TOP") .. side, 0, offset)
    return { anchor = anchor, limit = math.min(400, limit), screen = screen, upper = upper, lower = lower,
        art = art, gap = gap }
end

function UI:CloseBarMenu()
    local session = self.barMenuSession
    if session and session.root and session.manager and type(session.manager.CloseMenus) == "function" then
        session.manager:CloseMenus()
    end
    self.barMenuSession = nil
end

local function anchoredMenu(owner, bar, name, generate, token)
    if not Menu or type(Menu.GetManager) ~= "function" or type(Menu.PopulateDescription) ~= "function"
        or type(MenuUtil.CreateRootMenuDescription) ~= "function" or not AnchorUtil or type(AnchorUtil.CreateAnchor) ~= "function"
        or not MenuVariants or type(MenuVariants.GetDefaultContextMenuMixin) ~= "function" then return end
    local mixin = owner.menuMixin or MenuVariants.GetDefaultContextMenuMixin()
    if not public(mixin) or type(mixin) ~= "table" or type(mixin.GetInset) ~= "function" then return end
    local ok, inset = pcall(mixin.GetInset, mixin)
    if not ok or not public(inset) or type(inset) ~= "table" or not finite(inset.top) or inset.top < 0
        or not finite(inset.bottom) or inset.bottom < 0 then return end
    local geometry = menuGeometry(owner, bar, name, inset)
    if not geometry then return end
    local manager = Menu.GetManager()
    if not manager or type(manager.OpenMenu) ~= "function" then return end
    local description = MenuUtil.CreateRootMenuDescription(mixin)
    Menu.PopulateDescription(function(_, root) generate(root, token) end, owner, description)
    local visited = 0
    local function constrain(root, depth)
        visited = visited + 1
        if depth > 32 or visited > 32768 then return false end
        local children = false
        for _, child in root:EnumerateElementDescriptions() do
            children = true
            if not constrain(child, depth + 1) then return false end
        end
        -- All existing bar-provider scroll caps are 400. Apply the same cap to
        -- every populated submenu, reduced when the free screen area is smaller.
        if children then root:SetScrollMode(geometry.limit) end
        return true
    end
    if not constrain(description, 0) then return end
    local session = { manager = manager, clamps = {}, owner = owner, token = token }
    description:AddMenuAcquiredCallback(function(frame)
        if not session.root then session.root = frame end
        local scale = frame:GetEffectiveScale()
        if not finite(scale) or scale <= 0 then return end
        local saved = { frame:GetClampRectInsets() }
        for index = 1, 4 do if not finite(saved[index]) then return end end
        session.clamps[frame] = saved
        local art = geometry.art
        frame:SetClampRectInsets(math.min(saved[1], -art.left), math.max(saved[2], art.right),
            math.max(saved[3], (geometry.screen.top - geometry.upper + geometry.gap) / scale + art.top),
            math.min(saved[4], -(geometry.lower - geometry.screen.bottom + geometry.gap) / scale - art.bottom))
    end)
    description:AddMenuReleasedCallback(function(frame)
        local saved = session.clamps[frame]
        if saved then frame:SetClampRectInsets(unpack(saved)); session.clamps[frame] = nil end
        if session.root == frame then
            session.root = nil
            if UI.barMenuSession == session then UI.barMenuSession = nil end
            if UI.contextToken == token then UI.contextToken = nil end
        end
    end)
    UI.barMenuSession = session
    local menu = manager:OpenMenu(owner, description, geometry.anchor)
    if not menu then if UI.barMenuSession == session then UI.barMenuSession = nil end; return end
    if type(PlaySound) == "function" and SOUNDKIT and finite(SOUNDKIT.IG_MAINMENU_OPEN) then PlaySound(SOUNDKIT.IG_MAINMENU_OPEN) end
    return true
end

context = function(owner, generate)
    local token = {}
    UI.contextToken = token
    if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then
        UI.contextToken = nil
        Host.Print("Context menus are unavailable. Use /menubar for settings.")
        return
    end
    GameTooltip:Hide()
    local bar, name = ownerBar(owner)
    if bar then
        if not anchoredMenu(owner, bar, name, generate, token) then
            if UI.contextToken == token then UI.contextToken = nil end
            Host.Print("This bar menu cannot be positioned safely. Use /menubar for settings.")
            return
        end
    else
        local session = {}
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:AddMenuAcquiredCallback(function(frame) session.root = session.root or frame end)
            root:AddMenuReleasedCallback(function(frame)
                if session.root == frame then
                    session.root = nil
                    if UI.contextToken == token then UI.contextToken = nil end
                end
            end)
            generate(root, token)
        end)
    end
    return token
end

local function menuScope(token)
    local database, character, profile = Host.db, Host.characterKey, Host:GetProfile()
    return function()
        return token ~= nil and UI.contextToken == token and Host.ready
            and Host.db == database and Host.characterKey == character and Host:GetProfile() == profile
    end
end

local function menuAction(current, callback)
    return function(...)
        if not current() then return end
        -- A completed action cannot be replayed from the same description.
        UI.contextToken = nil
        return callback(...)
    end
end

local function sortedTypes()
    local definitions = {}
    for _, definition in pairs(Host.types) do definitions[#definitions + 1] = definition end
    table.sort(definitions, function(a, b) return a.name < b.name end)
    return definitions
end

function UI:AddWidgetMenu(root, barName, isCurrent)
    local scope = menuScope(self.contextToken)
    local function current() return scope() and (not isCurrent or isCurrent()) end
    local definitions = sortedTypes()
    if #definitions == 0 then root:CreateTitle("Install a Menubar widget addon to add content."); return end
    for _, definition in ipairs(definitions) do
        local typeID = definition.id
        root:CreateButton(definition.name, menuAction(function()
            return current() and Host.types[typeID] == definition
        end, function()
            local instance = Host:AddWidget(typeID, barName)
            if instance then self:OpenWidget(instance.id) end
        end))
    end
end

function UI:WidgetMenu(owner, instance, root, contextToken)
    local definition = Host.types[instance.type]
    local widget, settings, typeID = Host.runtime[instance.id], instance.settings, instance.type
    local database, character = Host.db, Host.characterKey
    local function generate(menu, token)
        local scope = menuScope(token)
        local function current()
            return scope() and widget ~= nil and Host.runtime[instance.id] == widget
                and Model.GetWidget(database, character, instance.id) == instance
                and instance.type == typeID and instance.enabled ~= false and instance.settings == settings
                and widget.instance == instance and widget.settings == settings
                and Host.types[typeID] == definition and widget.definition == definition
        end
        if not current() then return end
        menu:CreateTitle((definition and definition.name or instance.type) .. " (" .. instance.id .. ")")
        if widget and definition and definition.contextMenu then
            Host:Call(widget, "contextMenu", menu)
            menu:CreateDivider()
        end
        menu:CreateButton("Configure...", menuAction(current, function() self:OpenWidget(instance.id) end))
        menu:CreateButton("Move earlier", menuAction(current, function() Host:ReorderWidget(instance, -1) end))
        menu:CreateButton("Move later", menuAction(current, function() Host:ReorderWidget(instance, 1) end))
        local alignmentMenu = menu:CreateButton("Alignment")
        for _, alignment in ipairs({ "left", "center", "right" }) do
            local value = alignment
            alignmentMenu:CreateRadio(value == "center" and "Centre" or value:gsub("^%l", string.upper),
                function() return current() and instance.alignment == value end, menuAction(current, function()
                    Model.MoveWidget(Host.db, Host.characterKey, instance.id, Host:EffectiveBar(instance), value)
                    Host:Rebuild()
                end))
        end
        if Host:GetProfile().placement == "both" then
            local bars = menu:CreateButton("Bar")
            for _, barName in ipairs({ "top", "bottom" }) do
                local value = barName
                bars:CreateRadio(value == "top" and "Top" or "Bottom", function() return current() and instance.bar == value end,
                    menuAction(current, function()
                        Model.MoveWidget(Host.db, Host.characterKey, instance.id, value, instance.alignment)
                        Host:Rebuild()
                    end))
            end
        end
        if definition then
            menu:CreateButton("Duplicate", menuAction(current, function()
                Model.AddWidget(Host.db, Host.characterKey, instance.type, instance.settings,
                    { bar = Host:EffectiveBar(instance), alignment = instance.alignment })
                Host:Rebuild()
            end))
        end
        menu:CreateDivider()
        menu:CreateButton("Remove from bar", menuAction(current, function()
            Host:RemoveWidget(instance.id)
            if self.widgetID == instance.id then self:OpenSettings() end
        end))
    end
    if root then generate(root, contextToken or self.contextToken) else context(owner, generate) end
end

local function barMenuIsOpen(owner)
    local session = UI.barMenuSession
    return session ~= nil and session.root ~= nil and session.owner == owner
        and session.token ~= nil and UI.contextToken == session.token
end

local function installCoreMenuOpener(owner)
    local native = owner.HandlesGlobalMouseEvent
    owner.HandlesGlobalMouseEvent = function(frame, mouseButton, event)
        -- Native global mouse-down otherwise dismisses the menu before our
        -- button-up click can toggle it. Only its current exact owner defers it.
        if mouseButton == "LeftButton" and event == "GLOBAL_MOUSE_DOWN" and barMenuIsOpen(frame) then return true end
        if public(native) and type(native) == "function" then return native(frame, mouseButton, event) end
        return false
    end
end

function UI:BarMenu(owner, barName)
    if barMenuIsOpen(owner) then self:CloseBarMenu(); return end
    context(owner, function(root, token)
        local current = menuScope(token)
        root:CreateTitle("Menubar")
        root:CreateButton("Settings", menuAction(current, function() self:OpenSettings() end))
        local add = root:CreateButton("Add widget")
        self:AddWidgetMenu(add, barName, current)
        local placement = root:CreateButton("Show bars")
        for _, option in ipairs({ { "top", "Top" }, { "bottom", "Bottom" }, { "both", "Both" } }) do
            local value = option[1]
            placement:CreateRadio(option[2], function() return current() and Host:GetProfile().placement == value end,
                menuAction(current, function() Host:GetProfile().placement = value; Host:Rebuild() end))
        end
    end)
end

function UI:UpdateBars()
    local profile = Host:GetProfile()
    local contentHeight, contentOffset = contentGeometry(profile)
    local controlHeight = math.min(math.max(12, profile.height - 4), contentHeight)
    local aqua = profile.theme == "macosx" and profile.texture == "theme"
    for _, name in ipairs({ "top", "bottom" }) do
        local bar = Host.bars[name]
        if not bar then
            bar = CreateFrame("Button", nil, UIParent)
            Host.bars[name] = bar
            bar:SetFrameStrata("MEDIUM")
            bar:SetFrameLevel(20)
            bar.surface = CreateFrame("Frame", nil, bar)
            bar.surface:SetFrameLevel(bar:GetFrameLevel() - 1)
            bar.surface:SetAllPoints()
            bar.surface:EnableMouse(false)
            bar.background = bar.surface:CreateTexture(nil, "BACKGROUND")
            bar.background:SetAllPoints()
            bar.topLine = fill(bar, "BORDER", profile.topLine)
            bar.topLine:SetPoint("TOPLEFT"); bar.topLine:SetPoint("TOPRIGHT")
            bar.bottomLine = fill(bar, "BORDER", profile.bottomLine)
            bar.bottomLine:SetPoint("BOTTOMLEFT"); bar.bottomLine:SetPoint("BOTTOMRIGHT")
            bar.menu = button(bar, "", 24, function(_, mouseButton)
                if mouseButton == "RightButton" then self:OpenSettings() else self:BarMenu(bar.menu, name) end
            end, true)
            bar.menu.Label:Hide()
            bar.menu.icon = {}
            for index, part in ipairs(menuIconShape) do
                local region = fill(bar.menu, "OVERLAY", { 1, 1, 1, 1 })
                bar.menu.icon[index] = region
                region:SetPoint("TOPLEFT", bar.menu, "CENTER", part[1], part[2])
                region:SetSize(part[3], part[4])
            end
            controlTooltip(bar.menu, name, "Menubar", "Make yourself at home.", "menu")
            bar.menu:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            installCoreMenuOpener(bar.menu)
            bar.menu:SetFrameLevel(22)
            bar.overflow = button(bar, ">>", 24, function(_, mouseButton)
                if mouseButton == "RightButton" then self:OpenSettings(); return end
                context(bar.overflow, function(root, token)
                    root:CreateTitle("More widgets")
                    if #(bar.hiddenWidgets or {}) > 12 then root:SetScrollMode(400) end
                    for _, item in ipairs(bar.hiddenWidgets or {}) do
                        local widget = Host.runtime[item.id]
                        if widget then
                            Host:RefreshWidget(widget.id)
                            local caption = widget.text
                            if not caption or not caption:find("%S") then
                                caption = widget.definition and widget.definition.name or widget.instance.type
                            end
                            local submenu = root:CreateButton(caption)
                            self:WidgetMenu(bar.overflow, widget.instance, submenu, token)
                        end
                    end
                end)
            end)
            controlTooltip(bar.overflow, name, "More widgets", "The rest of your bar, close at hand.", "widgets")
            bar.overflow:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            bar.empty = label(bar, "Add a widget from the menu", 12)
            bar.empty:SetPoint("CENTER")
            bar.dither = {}
            bar.shadingBands = {}
            bar.corners = {}
            for row = 0, 7 do
                for _, side in ipairs({ "LEFT", "RIGHT" }) do
                    local corner = fill(bar, "OVERLAY", { 0, 0, 0, 1 })
                    local width = math.ceil(8 - math.sqrt(64 - (7.5 - row) ^ 2))
                    corner:SetSize(width, 1)
                    local edge = name == "top" and "TOP" or "BOTTOM"
                    corner:SetPoint(edge .. side, 0, name == "top" and -row or row)
                    bar.corners[#bar.corners + 1] = corner
                end
            end
        end
        bar:ClearAllPoints()
        bar:SetPoint(name == "top" and "TOPLEFT" or "BOTTOMLEFT", UIParent)
        bar:SetPoint(name == "top" and "TOPRIGHT" or "BOTTOMRIGHT", UIParent)
        bar:SetHeight(profile.height)
        -- Only the background surface inherits this setting. Framing and content
        -- remain on the opaque host, including at zero background opacity.
        bar:SetAlpha(1)
        bar.surface:SetAlpha(profile.opacity)
        bar:SetShown(profile.placement == name or profile.placement == "both")
        bar.background:SetTexture(nil)
        if profile.texture == "theme" and MenubarSkins.IsWarcraft(profile.theme) then
            bar.background:SetColorTexture(unpack(MenubarSkins.GetFallbackColor(profile.theme)))
            bar.background:SetVertexColor(unpack(profile.background))
        elseif profile.texture == "theme" then
            bar.background:SetColorTexture(unpack(profile.background))
            bar.background:SetVertexColor(1, 1, 1, 1)
        elseif profile.texture ~= "solid" and profile.texture ~= "dither" then
            bar.background:SetTexture(profile.texture)
            bar.background:SetVertexColor(unpack(profile.background))
            bar.background:SetHorizTile(true)
            bar.background:SetVertTile(true)
        else
            bar.background:SetColorTexture(unpack(profile.background))
            bar.background:SetVertexColor(1, 1, 1, 1)
        end
        for _, line in ipairs(bar.dither) do line:Hide() end
        for _, band in ipairs(bar.shadingBands) do band:Hide() end
        if profile.theme == "macos8" or aqua then
            -- Original Mac-inspired surfaces share a retained, height-bounded pool.
            -- Aqua paints one layer per row so swatch alpha and bar opacity apply once.
            for row = 0, profile.height - 1 do
                local band = bar.shadingBands[row + 1]
                if not band then
                    band = bar.surface:CreateTexture(nil, "BACKGROUND", nil, 1)
                    bar.shadingBands[row + 1] = band
                end
                local position = row / math.max(1, profile.height - 1)
                if aqua then
                    local highlight = 0.5 * (1 - position) ^ 2
                    local shade = (1 - 0.06 * position ^ 2) * (row % 3 == 2 and 0.975 or 1)
                    local background = profile.background
                    band:SetColorTexture((background[1] + (1 - background[1]) * highlight) * shade,
                        (background[2] + (1 - background[2]) * highlight) * shade,
                        (background[3] + (1 - background[3]) * highlight) * shade, background[4])
                elseif position < 0.5 then
                    band:SetColorTexture(1, 1, 1, (0.5 - position) * 0.42 * profile.background[4])
                else band:SetColorTexture(0, 0, 0, (position - 0.5) * 0.26 * profile.background[4]) end
                band:ClearAllPoints()
                band:SetPoint("TOPLEFT", 0, -row); band:SetPoint("TOPRIGHT", 0, -row)
                band:SetHeight(1); band:Show()
            end
        end
        if profile.texture == "dither" then
            -- An original fine horizontal pattern, drawn with game primitives.
            for i = 1, math.floor(profile.height / 3) do
                local line = bar.dither[i] or fill(bar.surface, "ARTWORK", { 0, 0, 0, 0.055 })
                bar.dither[i] = line
                line:SetColorTexture(0, 0, 0, 0.055 * profile.background[4])
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", 0, -i * 3)
                line:SetPoint("TOPRIGHT", 0, -i * 3)
                line:SetHeight(1)
                line:Show()
            end
        end
        bar.topLine:SetColorTexture(unpack(profile.topLine))
        bar.bottomLine:SetColorTexture(unpack(profile.bottomLine))
        bar.topLine:SetHeight(math.max(1, profile.topLineSize))
        bar.bottomLine:SetHeight(math.max(1, profile.bottomLineSize))
        bar.topLine:SetShown(profile.topLineSize > 0)
        bar.bottomLine:SetShown(profile.bottomLineSize > 0)
        bar.menu:ClearAllPoints(); bar.menu:SetPoint("LEFT", bar, "LEFT", profile.padding, contentOffset)
        bar.overflow:ClearAllPoints(); bar.overflow:SetPoint("RIGHT", bar, "RIGHT", -profile.padding, contentOffset)
        bar.empty:ClearAllPoints(); bar.empty:SetPoint("CENTER", bar, "CENTER", 0, contentOffset)
        bar.menu:SetHeight(controlHeight)
        bar.menu:SetShown(Host:HasCoreMenu(name))
        for _, corner in ipairs(bar.corners) do corner:SetShown(profile.roundedCorners) end
        bar.overflow:SetHeight(controlHeight)
        font(bar.menu.Label, 12); font(bar.overflow.Label, 12); font(bar.empty)
        if not MenubarSkins.IsWarcraft(profile.theme) then
            bar.menu.Label:SetTextColor(0, 0, 0, 1)
            bar.overflow.Label:SetTextColor(0, 0, 0, 1)
        end
        MenubarSkins.Apply(bar, profile)
        if aqua then bar.background:Hide() end -- Shading rows replace the flat fallback surface.
        local r, g, b, a = bar.menu.Label:GetTextColor()
        for _, region in ipairs(bar.menu.icon) do region:SetColorTexture(r, g, b, a) end
    end
end

function UI:CreateWidget(instance, previous)
    local definition = Host.types[instance.type]
    local widget = previous
    if widget and widget.definition ~= definition then
        Host:Call(widget, "destroy")
        widget.frame:Hide()
        widget = nil
    end
    local fresh = widget == nil
    if fresh then
        local frame = CreateFrame("Button", nil, Host.bars[Host:EffectiveBar(instance)])
        frame:SetFrameLevel(23)
        frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local textRegion = label(frame, "")
        textRegion:SetPoint("CENTER")
        local highlight = fill(frame, "HIGHLIGHT", { 0, 0, 0, 0.1 }); highlight:SetAllPoints()
        widget = { id = instance.id, frame = frame, label = textRegion, elapsed = 0, width = 24, _menubarEpoch = {} }
        function widget:SetText(text)
            assert(public(text), "Menubar: restricted widget text")
            self.text = tostring(text or "")
            self.label:SetText(self.text)
            local width = (not self.failed and self.customWidth) or math.max(18, self.label:GetStringWidth() + 8)
            if width ~= self.width then self.width = width; self.frame:SetWidth(width); Host.dirty = true end
        end
        function widget:SetWidth(width)
            assert(public(width) and type(width) == "number" and width > 0 and width < 10000, "Menubar: invalid widget width")
            self.customWidth = width
            if width ~= self.width then self.width = width; self.frame:SetWidth(width); Host.dirty = true end
        end
        function widget:Refresh()
            if Host.runtime[self.id] == self then return Host:RefreshWidget(self.id) end
        end
        function widget:GuardCallback(handler) return Host:GuardCallback(self, handler, false) end
        function widget:MenuCallback(handler) return Host:GuardCallback(self, handler, true) end
        function widget:OpenChoiceMenu(key, title) return Host.UI:OpenChoiceMenu(self, key, title) end
        widget.JiggleIcon, widget.JiggleIcons, widget.StopIconJiggle = jiggleIcon, jiggleIcons, stopIconJiggle
        frame:SetScript("OnHide", function() stopIconJiggle(widget) end)
        MenubarGauge.Attach(widget, function(value) font(value.label) end)
    end
    -- Keep the public full-height interaction frame unchanged. Visual content
    -- has a separate body anchor so unequal border rules move every provider
    -- together without shifting its clicks, tooltip owner or popup anchors.
    local content = widget.content
    if not content then
        content = CreateFrame("Frame", nil, widget.frame)
        widget.content = content
        content:EnableMouse(false)
        content:SetFrameLevel(widget.frame:GetFrameLevel())
        widget.label:ClearAllPoints()
        widget.label:SetPoint("CENTER", content, "CENTER", 0, 0)
    end
    widget.instance, widget.definition = instance, definition
    widget.settings = instance.settings
    widget.frame:SetParent(Host.bars[Host:EffectiveBar(instance)])
    local profile = Host:GetProfile()
    widget.frame:SetHeight(profile.height)
    local contentHeight, contentOffset = contentGeometry(profile)
    content:ClearAllPoints()
    content:SetPoint("LEFT", widget.frame, "LEFT", 0, contentOffset)
    content:SetPoint("RIGHT", widget.frame, "RIGHT", 0, contentOffset)
    content:SetHeight(contentHeight)
    widget.gaugeTopLineSize = Host:GetProfile().topLineSize
    widget.gaugeBottomLineSize = Host:GetProfile().bottomLineSize
    widget.gaugeTheme = Host:GetProfile().theme
    font(widget.label)
    widget:SetText(widget.text or "")
    widget.frame:SetScript("OnClick", function(frame, mouseButton)
        if mouseButton == "RightButton" then self:OpenWidget(instance.id)
        elseif mouseButton == "LeftButton" then
            if shiftDown() then self:WidgetMenu(frame, instance)
            elseif definition and type(definition.click) == "function" then Host:Call(widget, "click", mouseButton) end
        end
    end)
    widget.frame:EnableMouseWheel(definition and type(definition.mouseWheel) == "function" or false)
    widget.frame:SetScript("OnMouseWheel", function(_, delta) Host:Call(widget, "mouseWheel", delta) end)
    widget.frame:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, Host:EffectiveBar(instance) == "bottom" and "ANCHOR_TOP" or "ANCHOR_BOTTOM")
        if widget.failed then
            GameTooltip:AddLine("Widget error")
            GameTooltip:AddLine(widget.failed, 1, 0.5, 0.5, true)
        elseif not definition then
            GameTooltip:AddLine(instance.type .. " is unavailable")
            GameTooltip:AddLine("Enable its addon and restart the game. Your settings are kept.", 1, 1, 1, true)
        else Host:Call(widget, "tooltip", GameTooltip) end
        GameTooltip:AddLine(" ")
        interactionHints(GameTooltip, definition, widget.failed)
        GameTooltip:Show()
    end)
    widget.frame:SetScript("OnLeave", function(frame)
        if GameTooltip:GetOwner() == frame then GameTooltip:Hide() end
    end)
    Host.runtime[instance.id] = widget
    if not definition then widget:SetText("[" .. instance.type .. " unavailable]")
    elseif fresh then Host:Call(widget, "create") end
    widget.frame:SetWidth(widget.width)
end
