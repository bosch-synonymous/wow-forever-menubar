-- Original Ammo provider. Item metadata is cached; inventory counts are always fresh.
local metadata, requested, cacheOrder = {}, {}, {}
local cacheLimit, nextCacheSlot = 1024, 1

local function cachedMetadata(id)
    local info = metadata[id]
    if not info then
        local previous = cacheOrder[nextCacheSlot]
        if previous then metadata[previous], requested[previous] = nil, nil end
        cacheOrder[nextCacheSlot] = id
        nextCacheSlot = nextCacheSlot % cacheLimit + 1
        info = {}
        metadata[id] = info
    end
    return info
end

local function readable(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function integer(value, minimum)
    return readable(value) and type(value) == "number" and value >= minimum
        and value < math.huge and value == math.floor(value)
end

local function call(method, ...)
    if not readable(method) or type(method) ~= "function" then return nil, false end
    local ok, value = pcall(method, ...)
    if not ok or not readable(value) then return nil, false end
    return value, true
end

local function whole(value)
    return string.format("%.0f", value)
end

local function projectileClass()
    local value = Enum and Enum.ItemClass and Enum.ItemClass.Projectile
    return integer(value, 0) and value or 6
end

local function describe(id, projectilesOnly)
    local info = cachedMetadata(id)
    if info.classID == nil and C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        local ok, itemID, itemType, itemSubtype, equipLoc, icon, classID = pcall(C_Item.GetItemInfoInstant, id)
        if ok then
            if integer(classID, 0) then info.classID = classID end
            if integer(icon, 1) then info.icon = icon end
        end
    end
    local relevant = info.classID == nil or info.classID == projectileClass()
    if relevant and (info.classID == nil or info.name == nil or info.icon == nil)
        and C_Item and type(C_Item.GetItemInfo) == "function" then
        local ok, name, link, quality, level, minLevel, itemType, itemSubtype, stackCount, equipLoc, icon, sellPrice, classID = pcall(C_Item.GetItemInfo, id)
        if ok then
            if readable(name) and type(name) == "string" and name ~= "" then info.name = name end
            if integer(icon, 1) then info.icon = icon end
            if integer(classID, 0) then info.classID = classID end
        end
    end
    relevant = info.classID == nil or info.classID == projectileClass()
    if relevant and info.icon == nil and C_Item then
        local icon = call(C_Item.GetItemIconByID, id)
        if integer(icon, 1) then info.icon = icon end
    end
    if relevant and (info.classID == nil or info.name == nil)
        and C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
        local now = call(GetTime)
        if type(now) ~= "number" or now ~= now or now < 0 or now >= math.huge then now = nil end
        local previous = requested[id]
        -- Explicit loads may fail or never complete. Allow another request after
        -- ten seconds, shared across instances; polling alone must not flood loads.
        if previous == nil or (now and (previous == true or now < previous or now - previous >= 10)) then
            requested[id] = now or true
            call(C_Item.RequestLoadItemDataByID, id)
        end
    end
    -- Inventory scans never display non-projectiles. Keep their classification
    -- cached without allocating a fresh display record on every full bag scan.
    if projectilesOnly and info.classID ~= nil and not relevant then return nil, true end
    return {
        id = id,
        icon = info.icon,
        name = info.name or "Ammunition (loading)",
        loading = info.name == nil or info.classID == nil,
        classified = info.classID ~= nil,
        projectile = info.classID == projectileClass(),
    }
end

local function count(id)
    local amount = call(C_Item and C_Item.GetItemCount, id, false)
    if integer(amount, 0) then return amount end
end

local function scan()
    local result = { items = {}, byID = {}, incomplete = false, unavailable = false }
    local lastBag = Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots
    if not integer(lastBag, 0) then lastBag = NUM_BAG_SLOTS end
    if not integer(lastBag, 0) or not C_Container then result.unavailable = true; return result end
    local idReader = C_Container.GetContainerItemID
    local scalar = readable(idReader) and type(idReader) == "function"
    local fallback = readable(idReader) and idReader == nil
    if not scalar and not fallback then result.unavailable = true; return result end
    local seen = {}
    for bag = 0, lastBag do
        local slots = call(C_Container.GetContainerNumSlots, bag)
        if not integer(slots, 0) then
            result.unavailable = true
        else
            for slot = 1, slots do
                local id, available
                if scalar then
                    id, available = call(idReader, bag, slot)
                else
                    local container
                    container, available = call(C_Container.GetContainerItemInfo, bag, slot)
                    if available and container ~= nil then
                        if type(container) == "table" then
                            id = container.itemID
                            if not readable(id) then id = nil end
                            if id == nil then result.incomplete = true end
                        else result.incomplete = true end
                    end
                end
                if not available then
                    result.unavailable = true
                elseif id ~= nil then
                    if not integer(id, 1) then
                        result.incomplete = true
                    elseif not seen[id] then
                        seen[id] = true
                        local item, excluded = describe(id, true)
                        if not excluded then
                            if not item.classified then result.incomplete = true end
                            if item.projectile then
                                item.count = count(item.id)
                                result.items[#result.items + 1] = item
                                result.byID[item.id] = item
                                if item.loading then result.incomplete = true end
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(result.items, function(a, b) return a.id < b.id end)
    return result
end

local function focus(settings, inventory)
    -- Preserve a former manual choice only if it is currently carried, then retire
    -- that preference. All subsequent choices come from the inventory picker.
    if settings.manualID ~= nil and settings.legacySelectionMigrated ~= true then
        if integer(settings.manualID, 1) and inventory.byID[settings.manualID] then
            settings.selectedID = settings.manualID
            settings.legacySelectionMigrated = true
        elseif not integer(settings.manualID, 1) or (not inventory.unavailable and not inventory.incomplete) then
            settings.legacySelectionMigrated = true
        end
    end
    local id = settings.selectedID
    if id == nil then id = 0 end
    if not integer(id, 0) then return nil, "Selected ammunition is unavailable" end
    if id == 0 then
        if inventory.items[1] then return inventory.items[1] end
        if inventory.unavailable then return nil, "Ammo unavailable" end
        if inventory.incomplete then return nil, "Ammo data loading" end
        return nil, "No carried ammo"
    end
    if inventory.byID[id] then return inventory.byID[id] end
    local item = describe(id)
    if not item.classified then return nil, "Ammo data loading" end
    if not item.projectile then return nil, "Selected item is not projectile ammo" end
    item.count = count(id)
    return item
end

local function options(settings)
    local inventory = scan()
    local choices = { { value = 0, label = "Auto: first carried projectile type" } }
    for _, item in ipairs(inventory.items) do
        choices[#choices + 1] = { value = item.id, label = item.name }
    end
    return choices
end

local function update(widget)
    local item, message = focus(widget.settings, scan())
    if not item then widget:SetText(message); return end
    local amount = item.count ~= nil and whole(item.count) or "--"
    local display = widget.settings.display
    local height = whole(math.min(14, widget.content and widget.content:GetHeight() or 14))
    local icon = item.icon and ("|T" .. whole(item.icon) .. ":" .. height .. ":" .. height .. ":0:0|t") or nil
    if display == "count" then widget:SetText(amount)
    elseif display == "name" then widget:SetText(item.name .. ": " .. amount)
    elseif display == "iconName" then widget:SetText((icon and icon .. " " or "") .. item.name .. ": " .. amount)
    elseif icon then widget:SetText(icon .. " " .. amount)
    else widget:SetText(item.name .. ": " .. amount) end
end

local function click(widget)
    local open = widget.OpenChoiceMenu
    if not readable(open) or type(open) ~= "function" then return false end
    return open(widget, "selectedID", "Watch ammunition")
end

local function tooltip(widget, tip)
    local inventory = scan()
    local selected, message = focus(widget.settings, inventory)
    tip:AddLine("Ammunition")
    tip:AddLine("A few more shots for the road.", 1, 1, 1)
    if selected then
        tip:AddDoubleLine(selected.name .. " (selected)", selected.count ~= nil and whole(selected.count) or "Unavailable")
    else
        tip:AddLine(message, 0.65, 0.65, 0.65, true)
    end
    for _, item in ipairs(inventory.items) do
        if not selected or item.id ~= selected.id then
            tip:AddDoubleLine(item.name, item.count ~= nil and whole(item.count) or "Unavailable")
        end
    end
    if inventory.unavailable then
        tip:AddLine("Bag data unavailable; this list may be incomplete.", 0.65, 0.65, 0.65, true)
    elseif inventory.incomplete then
        tip:AddLine("Item details loading; this list may be incomplete.", 0.65, 0.65, 0.65, true)
    end
end

Menubar:RegisterWidgetType({
    id = "ammo",
    retainOnDisable = true,
    name = "Ammo",
    clickHint = "Choose ammunition",
    defaults = { selectedID = 0, display = "icon"},
    settings = {
        { key = "selectedID", label = "Carried ammunition", type = "select", options = options },
        { key = "display", label = "Ammunition display", type = "select", options = {
            { value = "icon", label = "Icon and quantity" },
            { value = "name", label = "Name and quantity" },
            { value = "iconName", label = "Icon, name and quantity" },
            { value = "count", label = "Quantity only" },
        } },
    },
    interval = 2,
    events = { "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "PLAYER_ENTERING_WORLD", "ITEM_DATA_LOAD_RESULT" },
    defaultPlacement = { bar = "top", alignment = "right", order = 4, sidebarOrder = 4 },
    update = update,
    click = click,
    tooltip = tooltip,
})
