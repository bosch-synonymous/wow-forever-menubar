local root = REPO_ROOT or "."
local yellow, red = "|cffffd12e", "|cffed1212"
local repairHammer = "Interface\\AddOns\\Menubar_Durability\\Media\\repair-hammer.tga"
local passed = 0
local function check(name, run)
    local ok, reason = pcall(run)
    assert(ok, name .. ": " .. tostring(reason))
    passed = passed + 1; print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function fixture()
    local f = { gear = {}, alerts = {}, reads = {}, alertReads = {}, textures = {}, fonts = {} }
    local env = setmetatable({}, { __index = _G })
    local secret = setmetatable({}, { __lt = function() error("secret compared") end,
        __le = function() error("secret compared") end, __tostring = function() error("secret formatted") end })
    f.secret = secret
    env.issecretvalue = function(value) return rawequal(value, secret) end
    env.GetInventoryItemDurability = function(id)
        f.reads[#f.reads + 1] = id
        if f.readError == id then error("native durability unavailable") end
        local pair = f.gear[id]
        if pair then return pair[1], pair[2] end
    end
    env.GetInventoryAlertStatus = function(index)
        f.alertReads[#f.alertReads + 1] = index
        if f.alertError == index then error("native alert unavailable") end
        return f.alerts[index] or 0
    end
    env.Menubar = { RegisterWidgetType = function(_, definition) f.provider = definition end }
    local chunk = assert(loadfile(root .. "/src/menubar-durability/Durability.lua"))
    setfenv(chunk, env); chunk()
    f.env = env
    local function region()
        local value = { shown = true, points = {}, text = "" }
        function value:SetText(text) self.text = text end
        function value:GetText() return self.text end
        function value:GetStringWidth()
            local visible = self.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            return #visible * (self.size or 12) / 2
        end
        function value:GetFont() return self.path or "Default.ttf", self.size or 12, self.flags or "" end
        function value:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags; return true end
        function value:GetTextColor() return unpack(self.color or { 0, 0, 0, 1 }) end
        function value:SetTextColor(...) self.color = { ... } end
        function value:SetShadowColor(...) self.shadow = { ... } end
        function value:SetShadowOffset(...) self.shadowOffset = { ... } end
        function value:SetWordWrap() end
        function value:SetTexture(path)
            if f.textureError then error("temporary hammer error") end
            if f.textureUnavailable then return false end
            self.texture = path; return true
        end
        function value:GetTexture() return self.texture end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetSize(width, height) self.width, self.height = width, height end
        function value:ClearAllPoints() self.points = {} end
        function value:SetPoint(...) self.points[#self.points + 1] = { ... } end
        function value:Show() self.shown = true end
        function value:Hide() self.shown = false end
        return value
    end
    function f:widget(settings, defer)
        local widget = { settings = {}, label = region(), frame = {} }
        for key, value in pairs(self.provider.defaults) do widget.settings[key] = value end
        -- Native-alert averaging checks explicitly select the alternative policy.
        widget.settings.customThresholds, widget.settings.hideDefaultWarnings = false, false
        for key, value in pairs(settings or {}) do widget.settings[key] = value end
        function widget.frame:CreateTexture()
            local result = region(); f.textures[#f.textures + 1] = result; return result
        end
        function widget.frame:CreateFontString()
            local result = region(); f.fonts[#f.fonts + 1] = result; return result
        end
        function widget:SetText(text) self.text = text; self.label:SetText(text) end
        function widget:SetWidth(width) self.width, self.customWidth = width, width end
        if not defer then self.provider.update(widget) end
        return widget
    end
    function f:tooltip(widget)
        local tip = { lines = {} }
        function tip:AddLine(text) self.lines[#self.lines + 1] = text end
        function tip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. ": " .. right end
        self.provider.tooltip(widget, tip)
        return table.concat(tip.lines, "\n")
    end
    return f
end

check("durability averages per-item percentages and excludes absent/non-durable slots", function()
    local f = fixture(); f.gear = { [1] = { 1, 2 }, [5] = { 100, 100 } }
    equal(f.provider.defaults.customThresholds, true); equal(f.provider.defaults.hideDefaultWarnings, true)
    local widget = f:widget()
    equal(widget.label.text, "75%") -- Weighted raw points would be 101/102 instead.
    equal(#f.reads, 11); equal(#f.alertReads, 11)
    equal(f.reads[9], 16); equal(f.alertReads[9], 9)
    equal(#f.textures, 1)
    equal(widget.durabilitySummaryIcon.texture, repairHammer)
    equal(widget.label.flags, "OUTLINE")
    local tooltip = f:tooltip(widget)
    assert(tooltip:find("Average remaining: 75%", 1, true))
    assert(tooltip:find("each item counts equally", 1, true))
    assert(not tooltip:find("Shoulder:", 1, true), "Empty and non-durable slots should not clutter the item list")
end)

check("native alerts use their own slot index and status rather than guessed thresholds", function()
    local f = fixture(); f.gear = { [1] = { 70, 100 }, [5] = { 0, 100 }, [16] = { 90, 100 } }
    f.alerts = { [1] = 1, [3] = 2, [9] = 1 }
    local widget = f:widget()
    equal(widget.label.text, yellow .. "Head 70%|r  " .. red .. "Chest 0%|r  " .. yellow .. "Main hand 90%|r")
    equal(widget.text, "Durability: Head 70%, Chest 0%, Main hand 90%")
    equal(#f.textures, 1); equal(#f.fonts, 0)
    equal(f.textures[1].texture, repairHammer)
    equal(widget.label.flags, "OUTLINE")
end)

check("custom alerts are inclusive, independent, and bound red to yellow", function()
    local f = fixture(); f.gear = { [1] = { 20, 100 }, [5] = { 5, 100 }, [16] = { 21, 100 } }
    f.alerts[9] = 2
    local widget = f:widget({ customThresholds = true, warningPercent = 20, criticalPercent = 5 })
    equal(#f.alertReads, 0)
    equal(widget.label.text, yellow .. "Head 20%|r  " .. red .. "Chest 5%|r")
    widget.settings.criticalPercent = 90
    f.provider.update(widget)
    equal(widget.label.text, red .. "Head 20%|r  " .. red .. "Chest 5%|r")
    assert(f:tooltip(widget):find("Red threshold is capped at yellow", 1, true))
end)

check("broken zero counts in the average and a fully empty set is N/A", function()
    local f = fixture(); f.gear[1] = { 0, 100 }
    equal(f:widget().label.text, "0%")
    f.gear = {}; equal(f:widget().label.text, "N/A")
end)

check("missing throwing malformed and restricted reads remain unknown rather than zero", function()
    for _, pair in ipairs({ { -1, 100 }, { 101, 100 }, { 1, 0 }, { 1, math.huge }, { 0/0, 100 }, { 1 }, { "1", 100 }, { 1.5, 100 } }) do
        local f = fixture(); f.gear[1] = pair
        equal(f:widget().label.text, "--")
    end
    local f = fixture(); f.gear = { [1] = { f.secret, 100 }, [5] = { 100, 100 } }
    equal(f:widget().label.text, "--")
    f.gear[1] = { 1, f.secret }; equal(f:widget().label.text, "--")
    f.gear = {}; f.readError = 1; equal(f:widget().label.text, "--")
    f.readError = nil; f.env.GetInventoryItemDurability = false
    equal(f:widget().label.text, "--")
    f.env.GetInventoryItemDurability = f.secret
    equal(f:widget().label.text, "--")
end)

check("unknown native alerts are visibly distinct while public durability remains readable", function()
    local f = fixture(); f.gear[1] = { 100, 100 }; f.alerts[1] = f.secret
    local widget = f:widget()
    equal(widget.label.text, "100% ?")
    assert(f:tooltip(widget):find("WoW alert status unavailable", 1, true))
    f.alerts[1] = 1; f.alertError = 2
    f.provider.update(widget); equal(widget.label.text, yellow .. "Head 100%|r ?")
    f.alertError = nil; f.alerts[1] = 0
    f.provider.update(widget); equal(widget.label.text, "100%")
end)

check("a wrist warning names the damaged slot beside a single hammer", function()
    local f = fixture(); f.gear[9] = { 20, 100 }; f.alerts[7] = 1
    local widget = f:widget()
    equal(widget.label.text, yellow .. "Wrists 20%|r"); equal(widget.label.flags, "OUTLINE")
    equal(#f.textures, 1); equal(f.textures[1].texture, repairHammer)
    assert(f:tooltip(widget):find("Wrists: 20%", 1, true))
end)

check("a native alert remains visible when its exact durability is unavailable", function()
    local f = fixture(); f.gear[1] = { f.secret, 100 }; f.alerts[1] = 2
    local widget = f:widget()
    equal(widget.label.text, red .. "Head --|r --")
    assert(f:tooltip(widget):find("Average remaining: Unavailable", 1, true))
    f.gear = { [5] = { 100, 100 } }
    f.provider.update(widget)
    equal(widget.label.text, red .. "Head --|r --")
    local tip = f:tooltip(widget)
    assert(tip:find("Average remaining: Unavailable", 1, true))
    assert(tip:find("Head: Unavailable", 1, true))
end)

check("all eleven slot alerts share a single label and hammer across repeated updates", function()
    local f = fixture()
    for _, id in ipairs({ 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }) do f.gear[id] = { 1, 100 } end
    for index = 1, 11 do f.alerts[index] = 1 end
    local widget = f:widget()
    equal(#f.textures, 1); equal(#f.fonts, 0)
    equal(select(2, widget.label.text:gsub("|r", "")), 11)
    for attempt = 1, 30 do f.provider.update(widget) end
    equal(#f.textures, 1); equal(#f.fonts, 0)
    f.provider.reset(widget); f.provider.reset(widget)
    equal(widget.customWidth, nil); equal(widget.label.points[1][1], "CENTER")
    assert(not widget.durabilitySummaryIcon.shown)
    f.alerts = {}; f.provider.update(widget)
    equal(widget.label.text, "1%"); equal(widget.label.points[1][1], "LEFT")
    assert(widget.durabilitySummaryIcon.shown)
    equal(#f.textures, 1)
end)

check("repair summary preserves values and reuses its neutral icon through alert and unknown states", function()
    local f = fixture(); f.gear = { [1] = { 50, 100 }, [5] = { 100, 100 } }
    local widget = f:widget()
    local icon = assert(widget.durabilitySummaryIcon)
    equal(icon.texture, repairHammer)
    equal(icon.width, 16); equal(icon.height, 16)
    equal(icon.points[1][1], "LEFT"); equal(icon.points[1][4], 4)
    equal(widget.label.points[1][1], "LEFT"); equal(widget.label.points[1][4], 23)
    equal(widget.width, widget.label:GetStringWidth() + 27)
    for _ = 1, 30 do f.provider.update(widget) end
    equal(#f.textures, 1); equal(#f.fonts, 0)
    f.gear = { [1] = { 0, 100 } }; f.provider.update(widget)
    equal(widget.label.text, "0%"); assert(icon.shown)
    f.gear = { [1] = { f.secret, 100 } }; f.provider.update(widget)
    equal(widget.label.text, "--"); assert(icon.shown)
    f.gear = {}; f.provider.update(widget)
    equal(widget.label.text, "N/A"); assert(icon.shown)
    f.gear = { [1] = { 10, 100 } }; f.alerts[1] = 1; f.provider.update(widget)
    equal(widget.label.text, yellow .. "Head 10%|r"); assert(icon.shown)
    f.alerts = {}; f.provider.update(widget)
    equal(widget.durabilitySummaryIcon, icon); assert(icon.shown)
    equal(widget.label.text, "10%"); equal(#f.textures, 1); equal(#f.fonts, 0)
    f.provider.reset(widget); f.provider.reset(widget)
    assert(not icon.shown); equal(widget.label.points[1][1], "CENTER")
    equal(widget.customWidth, nil)
end)

check("a rejected or throwing texture keeps the reading and recovers without reallocating", function()
    for _, failure in ipairs({ "textureUnavailable", "textureError" }) do
        local f = fixture()
        f[failure] = true; f.gear[9] = { 20, 100 }
        local widget = f:widget()
        equal(widget.label.text, "20%")
        equal(widget.label.points[1][1], "CENTER")
        assert(not widget.durabilitySummaryIcon.shown)
        f.alerts[7] = 1
        f.provider.update(widget)
        equal(widget.label.text, yellow .. "Wrists 20%|r")
        equal(widget.width, widget.label:GetStringWidth() + 8)
        assert(not widget.durabilitySummaryIcon.shown)
        f[failure] = false
        f.provider.update(widget)
        equal(#f.textures, 1); equal(#f.fonts, 0)
        equal(f.textures[1].texture, repairHammer); assert(f.textures[1].shown)
    end
end)

check("text-only hosts can still read the slot and warning percentage", function()
    local f = fixture(); f.gear[9] = { 20, 100 }; f.alerts[7] = 1
    local widget = f:widget(nil, true)
    widget.frame.CreateTexture = nil
    f.provider.update(widget)
    equal(widget.label.text, yellow .. "Wrists 20%|r")
    equal(widget.label.points[1][1], "CENTER")
    equal(widget.width, widget.label:GetStringWidth() + 8)
end)

print(passed .. " Durability tests passed")
