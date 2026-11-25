-- Original Menubar mail provider. Blizzard's envelope is referenced at runtime.
local function public(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function count(value)
    return public(value) and type(value) == "number" and value == value
        and value >= 0 and value < math.huge and value == math.floor(value)
end

local function flag(value)
    if not public(value) then return nil end
    if value == nil or value == false then return false end
    if value == true or value == 1 then return true end
end

-- One observer belongs to the addon, rather than to an individual widget. It
-- retains mailbox lifecycle events while all Mail instances are disabled.
local mailboxOpen, inboxReady = false, false
local observer = CreateFrame("Frame")
observer:Hide()
for _, event in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE" }) do
    pcall(observer.RegisterEvent, observer, event)
end
observer:SetScript("OnEvent", function(_, event)
    if not public(event) then return end
    if event == "MAIL_SHOW" then
        mailboxOpen, inboxReady = true, false
    elseif event == "MAIL_CLOSED" then
        mailboxOpen, inboxReady = false, false
    elseif event == "MAIL_INBOX_UPDATE" and mailboxOpen then
        inboxReady = true
    end
end)

local function readPresence()
    if type(HasNewMail) ~= "function" then return {} end
    local ok, value = pcall(HasNewMail)
    if not ok then return {} end
    local present = flag(value)
    if present == nil then return {} end
    return { presence = present }
end

local function readInbox()
    if not inboxReady then return { loading = true } end
    if type(GetInboxNumItems) ~= "function" or type(GetInboxHeaderInfo) ~= "function" then return {} end
    local ok, loaded, total = pcall(GetInboxNumItems)
    if not ok or not count(loaded) or not count(total) or loaded > total or loaded > 1000 then return {} end
    local result = { unread = 0, stacks = 0, loaded = loaded, total = total, partial = loaded < total }
    for index = 1, loaded do
        local read, _, stationery, _, _, _, _, _, attachments, wasRead = pcall(GetInboxHeaderInfo, index)
        -- A nil read flag is a legitimate unread message. Require a readable
        -- stationery asset to distinguish it from an absent/loading header.
        if not read or not public(stationery) then return {} end
        if not ((type(stationery) == "string" and stationery ~= "")
            or (count(stationery) and stationery > 0)) then return {} end
        local alreadyRead = flag(wasRead)
        if alreadyRead == nil then return {} end
        if not alreadyRead then result.unread = result.unread + 1 end
        if public(attachments) and attachments == nil then attachments = 0 end
        if not count(attachments) or attachments > 16 then
            result.stacks = nil
        elseif result.stacks ~= nil then
            result.stacks = result.stacks + attachments
        end
    end
    return result
end

local function snapshot()
    if mailboxOpen then return readInbox() end
    return readPresence()
end

local function number(value)
    return string.format("%.0f", value)
end

local function displayed(state, capped)
    if state.unread ~= nil then
        if capped and state.unread > 999 then return "999+" end
        return number(state.unread) .. (state.partial and "+" or "")
    end
    if state.presence == true then return "1+" end
    if state.presence == false then return "0" end
    return "--"
end

local function presentation(widget)
    local path, size, flags = widget.label:GetFont()
    flags = flags or ""
    local height = math.max(12, math.min(24, (size or 12) * 1.1))
    local icon = string.format("|A:ui-hud-minimap-mail-icon:%.1f:%.1f|a ", height, height * 4 / 3)
    local sizing = widget.mailSizing
    if not sizing or sizing.path ~= path or sizing.size ~= size or sizing.flags ~= flags then
        local measure = widget.mailMeasure
        if not measure then
            measure = widget.frame:CreateFontString(nil, "OVERLAY")
            widget.mailMeasure = measure
            measure:Hide()
            measure:SetWordWrap(false)
        end
        if measure:SetFont(path, size, flags) ~= true then
            error("Mail font measurement is unavailable", 0)
        end
        local widest = 0
        measure:SetText(icon .. "--")
        widest = measure:GetStringWidth()
        -- Complete strings account for unequal digit widths and kerning.
        -- This bounded work runs only when the label's font changes.
        for value = 0, 999 do
            for _, suffix in ipairs({ "", "+" }) do
                measure:SetText(icon .. number(value) .. suffix)
                widest = math.max(widest, measure:GetStringWidth())
            end
        end
        measure:SetText(" ")
        sizing = { path = path, size = size, flags = flags, width = math.ceil(widest) + 8,
            height = height, gap = measure:GetStringWidth() }
        widget.mailSizing = sizing
    end
    if widget.customWidth ~= sizing.width then widget:SetWidth(sizing.width) end
    return icon
end

local function centerLabel(widget)
    widget.label:ClearAllPoints()
    widget.label:SetPoint("CENTER", widget.content or widget.frame, "CENTER")
end

local function stopIcon(widget)
    if type(widget.StopIconJiggle) == "function" then widget:StopIconJiggle() end
end

local function envelope(widget, text)
    local icon = widget.mailIcon
    if not icon and type(widget.frame.CreateTexture) == "function" then
        icon = widget.frame:CreateTexture(nil, "ARTWORK")
        widget.mailIcon = icon -- Retain ownership before native configuration.
        if icon then icon:Hide() end
    end
    local themed = icon and Menubar.ApplyThemeIcon and Menubar:ApplyThemeIcon(icon, "mail", widget.label)
    if Menubar.ApplyThemeIcon then
        widget.mailIconReady = themed == true
    elseif icon and not widget.mailIconReady and type(icon.SetAtlas) == "function" then
        local ok, applied = pcall(icon.SetAtlas, icon, "ui-hud-minimap-mail-icon", false)
        local ready = ok and public(applied) and applied ~= false
        if ready and type(icon.GetAtlas) == "function" then
            local read, actual = pcall(icon.GetAtlas, icon)
            -- Native atlas readback may use canonical capitalization.
            ready = read and public(actual) and type(actual) == "string"
                and actual:lower() == "ui-hud-minimap-mail-icon"
        end
        widget.mailIconReady = ready
    end
    if not icon or not widget.mailIconReady then
        if icon then icon:Hide() end
        stopIcon(widget)
        centerLabel(widget)
        if Menubar.ApplyThemeIcon then widget.label:SetText(text) end
        return
    end
    local sizing = widget.mailSizing
    local height = math.min(sizing.height, widget.content and widget.content:GetHeight() or sizing.height)
    local width = height * 4 / 3
    if themed then
        height = math.min(width, 16, widget.content and widget.content:GetHeight() or 16)
        width = height -- The original glyphs are square; only Blizzard's envelope is widescreen.
    end
    icon:SetSize(width, height)
    icon:ClearAllPoints()
    icon:SetPoint("LEFT", (widget.content or widget.frame), "LEFT", 4, 0)
    icon:Show()
    widget.label:ClearAllPoints()
    widget.label:SetPoint("LEFT", (widget.content or widget.frame), "LEFT", 4 + sizing.height * 4 / 3 + sizing.gap, 0)
    widget.label:SetPoint("RIGHT", widget.content or widget.frame, "RIGHT", -4, 0)
    widget.label:SetJustifyH("CENTER")
    widget.label:SetText(text)
end

local function update(widget)
    local state = snapshot()
    local current = { open = mailboxOpen, presence = state.presence,
        total = state.unread ~= nil and not state.partial and state.total or nil }
    local baseline = widget.mailWatch
    -- Rendering may see a change before its native event arrives. Keep a
    -- known rise unconsumed, while unavailable/loading/recovery is silent.
    if not baseline or baseline.open ~= current.open then
        widget.mailWatch = current
    elseif not current.open then
        if current.presence ~= true or baseline.presence == nil then widget.mailWatch = current end
    elseif current.total == nil or baseline.total == nil or current.total <= baseline.total then
        widget.mailWatch = current
    end
    widget.mailState = current
    local text = displayed(state, true)
    widget:SetText(presentation(widget) .. text)
    envelope(widget, text)
end

local function event(widget, name)
    local before, current = widget.mailWatch, widget.mailState
    local arrived = false
    if name == "MAIL_SHOW" then
        widget.mailWatch = { open = true } -- The first complete inbox is a baseline.
    elseif name == "MAIL_CLOSED" then
        widget.mailWatch = { open = false, presence = readPresence().presence }
    elseif name == "UPDATE_PENDING_MAIL" and before and current
        and not before.open and not current.open then
        arrived = before.presence == false and current.presence == true
        widget.mailWatch = current
    elseif name == "MAIL_INBOX_UPDATE" and before and current and before.open and current.open then
        arrived = before.total ~= nil and current.total ~= nil and current.total > before.total
        widget.mailWatch = current
    end
    if arrived and widget.mailIconReady and type(widget.JiggleIcon) == "function" then
        widget:JiggleIcon(widget.mailIcon)
    end
end

local function reset(widget)
    stopIcon(widget)
    if widget.mailIcon then widget.mailIcon:Hide() end
    centerLabel(widget)
    widget.mailState, widget.mailWatch = nil, nil
end

local function itemUnits(state)
    if state.stacks == nil then return nil end
    if state.stacks == 0 then return 0 end
    if type(HasInboxItem) ~= "function" or type(GetInboxItem) ~= "function" then return nil end
    local stacks, units = 0, 0
    for index = 1, state.loaded do
        for slot = 1, 16 do
            local ok, value = pcall(HasInboxItem, index, slot)
            if not ok then return nil end
            local occupied = flag(value)
            if occupied == nil then return nil end
            if occupied then
                local read, _, _, _, quantity = pcall(GetInboxItem, index, slot)
                if not read or not count(quantity) or quantity == 0 then return nil end
                stacks, units = stacks + 1, units + quantity
                if not count(units) then return nil end
            end
        end
    end
    -- Mail can change between calls; do not label an inconsistent scan exact.
    if stacks ~= state.stacks then return nil end
    return units
end

local function tooltip(_, tip)
    local state = snapshot()
    tip:AddLine("Mail")
    tip:AddLine("Not rain nor heat nor gloom of night...", 1, 1, 1)
    tip:AddDoubleLine(mailboxOpen and "Unread messages" or "New mail", displayed(state, false))
    if state.unread ~= nil then
        tip:AddDoubleLine("Inbox (loaded / total)", number(state.loaded) .. " / " .. number(state.total))
        local suffix = state.partial and "+" or ""
        tip:AddDoubleLine("Attachment stacks", state.stacks ~= nil and (number(state.stacks) .. suffix) or "--")
        local units = itemUnits(state)
        tip:AddDoubleLine("Attached items (units)", units ~= nil and (number(units) .. suffix) or "--")
        tip:AddLine("Attachments include all loaded mail.", 0.65, 0.65, 0.65, true)
        if state.partial then
            tip:AddLine("Partial inbox: + marks a minimum.", 0.65, 0.65, 0.65, true)
        end
    elseif mailboxOpen then
        tip:AddLine(state.loading and "Loading the inbox..." or "Mailbox counts are unavailable.",
            0.65, 0.65, 0.65, true)
    else
        tip:AddLine(state.presence == true and "1+ means mail is waiting; visit a mailbox for exact counts."
            or "Visit a mailbox for unread and attachment counts.", 0.65, 0.65, 0.65, true)
    end
end

Menubar:RegisterWidgetType({
    id = "mail",
    retainOnDisable = true,
    name = "Mail",
    defaults = {},
    events = { "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "UPDATE_PENDING_MAIL" },
    interval = 1,
    defaultPlacement = { bar = "top", alignment = "right", order = 3, sidebarOrder = 3 },
    update = update,
    event = event,
    tooltip = tooltip,
    reset = reset,
    deactivate = reset,
    destroy = reset,
})
