local root = REPO_ROOT or "."
local passed = 0
local function check(name, run)
    local ok, reason = pcall(run)
    assert(ok, name .. ": " .. tostring(reason))
    passed = passed + 1; print("PASS " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected) assert(math.abs(actual - expected) < 0.000001) end

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
    env.C_PaperDollInfo = { OffhandHasWeapon = function() return f.offhandWeapon end }
    env.Menubar = { RegisterWidgetType = function(_, definition) f.provider = definition end }
    local chunk = assert(loadfile(root .. "/src/menubar-durability/Durability.lua"))
    setfenv(chunk, env); chunk()
    f.env = env
    local function region()
        local value = { shown = true, points = {}, text = "" }
        function value:SetText(text) self.text = text end
        function value:GetText() return self.text end
        function value:GetStringWidth() return #self.text * (self.size or 12) / 2 end
        function value:GetFont() return "Default.ttf", self.size or 12, "" end
        function value:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags; return true end
        function value:SetTextColor(...) self.color = { ... } end
        function value:SetShadowColor(...) self.shadow = { ... } end
        function value:SetShadowOffset(...) self.shadowOffset = { ... } end
        function value:SetWordWrap() end
        function value:SetTexture(path)
            if f.textureUnavailable then return nil end
            self.texture = path; return true
        end
        function value:SetAtlas(atlas, useAtlasSize)
            equal(atlas, "SpellIcon-256x256-Repair")
            equal(useAtlasSize, false)
            if f.atlasError then error("repair atlas application interrupted", 0) end
            if not f.atlasNoOp then self.atlas = atlas end
            -- Native SetAtlas has no return value; acceptance is read back.
        end
        function value:GetAtlas()
            if f.atlasReadback then return f.atlasReadback(self) end
            return self.atlas
        end
        function value:SetTexCoord(...) self.uv = { ... } end
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
            if f.fontAllocationError then f.fontAllocationError = false; error("font allocation failed") end
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
    equal(widget.durabilitySummaryIcon.atlas, "SpellIcon-256x256-Repair")
    local tooltip = f:tooltip(widget)
    assert(tooltip:find("Average remaining: 75%", 1, true))
    assert(tooltip:find("each item counts equally", 1, true))
    assert(not tooltip:find("Shoulder:", 1, true), "Empty and non-durable slots should not clutter the item list")
end)

check("native alerts use their own slot index and status rather than guessed thresholds", function()
    local f = fixture(); f.gear = { [1] = { 70, 100 }, [5] = { 0, 100 }, [16] = { 90, 100 } }
    f.alerts = { [1] = 1, [3] = 2, [9] = 1 }
    local widget = f:widget()
    equal(#widget.durabilityRegions, 3)
    equal(widget.durabilityRegions[1].label.text, "70%")
    equal(widget.durabilityRegions[2].label.text, "0%")
    equal(widget.durabilityRegions[3].label.text, "90%")
    local red = widget.durabilityRegions[2].icon.color
    near(red[1], 0.93); near(red[2], 0.07); near(red[3], 0.07)
    assert(widget.text:find("Chest 0%", 1, true))
    local weapon = widget.durabilityRegions[3].icon
    near(weapon.uv[3], 0.3203125); assert(weapon.height > weapon.width)
end)

check("custom alerts are inclusive, independent, and bound red to yellow", function()
    local f = fixture(); f.gear = { [1] = { 20, 100 }, [5] = { 5, 100 }, [16] = { 21, 100 } }
    f.alerts[9] = 2
    local widget = f:widget({ customThresholds = true, warningPercent = 20, criticalPercent = 5 })
    equal(#widget.durabilityRegions, 2); equal(#f.alertReads, 0)
    equal(widget.durabilityRegions[1].icon.color[2], 0.82)
    equal(widget.durabilityRegions[2].icon.color[2], 0.07)
    widget.settings.criticalPercent = 90
    f.provider.update(widget)
    equal(widget.durabilityRegions[1].icon.color[2], 0.07)
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
    f.provider.update(widget); equal(widget.label.text, " ?")
    f.alertError = nil; f.alerts[1] = 0
    f.provider.update(widget); equal(widget.label.text, "100%")
end)

check("offhand weapon uses the client's weapon silhouette rather than its shield", function()
    local f = fixture(); f.gear[17] = { 10, 100 }; f.alerts[10] = 1
    local widget = f:widget()
    near(widget.durabilityRegions[1].icon.uv[1], 0.1875)
    f.offhandWeapon = true; f.provider.update(widget)
    near(widget.durabilityRegions[1].icon.uv[1], 0)
    f.offhandWeapon = f.secret; f.provider.update(widget)
    near(widget.durabilityRegions[1].icon.uv[1], 0.1875)
end)

check("a native alert remains visible when its exact durability is unavailable", function()
    local f = fixture(); f.gear[1] = { f.secret, 100 }; f.alerts[1] = 2
    local widget = f:widget()
    equal(widget.durabilityRegions[1].label.text, "--")
    equal(widget.durabilityRegions[1].icon.color[2], 0.07)
    equal(widget.label.text, "--")
    assert(f:tooltip(widget):find("Average remaining: Unavailable", 1, true))
    f.gear = { [5] = { 100, 100 } }
    f.provider.update(widget)
    equal(widget.label.text, "--")
    local tip = f:tooltip(widget)
    assert(tip:find("Average remaining: Unavailable", 1, true))
    assert(tip:find("Head: Unavailable", 1, true))
end)

check("all eleven slots reuse bounded regions and reset restores normal host presentation", function()
    local f = fixture()
    for _, id in ipairs({ 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }) do f.gear[id] = { 1, 100 } end
    for index = 1, 11 do f.alerts[index] = 1 end
    local widget = f:widget()
    equal(#f.textures, 11); equal(#f.fonts, 11)
    for attempt = 1, 30 do f.provider.update(widget) end
    equal(#f.textures, 11); equal(#f.fonts, 11)
    f.provider.reset(widget); f.provider.reset(widget)
    equal(widget.customWidth, nil); equal(widget.label.points[1][1], "CENTER")
    for _, value in ipairs(widget.durabilityRegions) do assert(not value.icon.shown and not value.label.shown) end
    f.alerts = {}; f.provider.update(widget)
    equal(widget.label.text, "1%"); equal(widget.label.points[1][1], "LEFT")
    assert(widget.durabilitySummaryIcon.shown)
    equal(#f.textures, 12)
end)

check("partially allocated graphics are retained and rendering failures clean up before retry", function()
    local f = fixture(); f.gear[1] = { 10, 100 }; f.alerts[1] = 1
    local widget = f:widget(nil, true); f.fontAllocationError = true
    local ok, reason = pcall(f.provider.update, widget)
    assert(not ok and tostring(reason):find("font allocation failed", 1, true))
    equal(#f.textures, 1); assert(not f.textures[1].shown)
    equal(widget.customWidth, nil)
    f.provider.update(widget)
    equal(#f.textures, 1); equal(#f.fonts, 1); assert(f.textures[1].shown)
end)

check("repair summary preserves values and reuses its neutral icon through alert and unknown states", function()
    local f = fixture(); f.gear = { [1] = { 50, 100 }, [5] = { 100, 100 } }
    local widget = f:widget()
    local icon = assert(widget.durabilitySummaryIcon)
    equal(icon.atlas, "SpellIcon-256x256-Repair")
    equal(icon.width, 16); equal(icon.height, 16)
    equal(icon.points[1][1], "LEFT"); equal(icon.points[1][4], 4)
    equal(widget.label.points[1][1], "LEFT"); equal(widget.label.points[1][4], 23)
    equal(widget.width, widget.label:GetStringWidth() + 27)
    for index = 1, 4 do equal(icon.color[index], 1) end
    for _ = 1, 30 do f.provider.update(widget) end
    equal(#f.textures, 1); equal(#f.fonts, 0)
    f.gear = { [1] = { 0, 100 } }; f.provider.update(widget)
    equal(widget.label.text, "0%"); assert(icon.shown)
    f.gear = { [1] = { f.secret, 100 } }; f.provider.update(widget)
    equal(widget.label.text, "--"); assert(icon.shown)
    f.gear = {}; f.provider.update(widget)
    equal(widget.label.text, "N/A"); assert(icon.shown)
    f.gear = { [1] = { 10, 100 } }; f.alerts[1] = 1; f.provider.update(widget)
    assert(not icon.shown and widget.durabilityRegions[1].icon.shown)
    f.alerts = {}; f.provider.update(widget)
    equal(widget.durabilitySummaryIcon, icon); assert(icon.shown)
    equal(widget.label.text, "10%"); equal(#f.textures, 2); equal(#f.fonts, 1)
    f.provider.reset(widget); f.provider.reset(widget)
    assert(not icon.shown); equal(widget.label.points[1][1], "CENTER")
    equal(widget.customWidth, nil)
end)

check("canonical repair atlas casing preserves a visible icon and percentage", function()
    local f = fixture(); f.gear[1] = { 75, 100 }
    f.atlasReadback = function(icon) return icon.atlas and icon.atlas:upper() end
    local widget = f:widget()
    local icon = assert(widget.durabilitySummaryIcon)
    assert(icon.shown); equal(widget.label.text, "75%")
    equal(icon.atlas, "SpellIcon-256x256-Repair")
    for _ = 1, 10 do f.provider.update(widget) end
    equal(widget.durabilitySummaryIcon, icon); equal(#f.textures, 1)
end)

check("missing malformed restricted and different repair atlas readbacks fail safely and recover", function()
    for _, kind in ipairs({ "missing", "false", "number", "table", "restricted", "different" }) do
        local f = fixture(); f.gear[1] = { 75, 100 }
        local results = { ["false"] = false, number = 27, table = {}, restricted = f.secret,
            different = "SpellIcon-256x256-Other" }
        f.atlasReadback = function() return results[kind] end
        local widget = f:widget(nil, true)
        local ok, reason = pcall(f.provider.update, widget)
        assert(not ok and reason:find("repair icon could not be applied", 1, true))
        local icon = assert(widget.durabilitySummaryIcon)
        assert(not icon.shown); equal(widget.customWidth, nil)
        f.atlasReadback = nil; f.provider.update(widget)
        assert(icon.shown); equal(widget.label.text, "75%")
        equal(widget.durabilitySummaryIcon, icon); equal(#f.textures, 1)
    end
end)

check("unsupported repair art falls back to a centered percentage and can recover on the owned icon", function()
    local f = fixture(); f.gear[1] = { 75, 100 }
    f.env.C_Texture = { GetAtlasInfo = function() return nil end }
    local widget = f:widget()
    equal(widget.label.text, "75%"); equal(#f.textures, 0)
    equal(widget.label.points[1][1], "CENTER")
    equal(widget.width, widget.label:GetStringWidth() + 8)
    local unknown = {
        function() return {} end,
        function() return f.secret end,
        function() return { width = 0, height = 256 } end,
        function() return { width = f.secret, height = 256 } end,
        function() error("atlas lookup unavailable", 0) end,
    }
    for _, lookup in ipairs(unknown) do
        f.env.C_Texture.GetAtlasInfo = lookup
        f.provider.update(widget)
        equal(widget.label.text, "75%"); equal(#f.textures, 0)
    end
    f.env.C_Texture.GetAtlasInfo = function(name)
        equal(name, "SpellIcon-256x256-Repair")
        return { width = 256, height = 256 }
    end
    f.provider.update(widget)
    local icon = assert(widget.durabilitySummaryIcon)
    assert(icon.shown); equal(#f.textures, 1)
    f.env.C_Texture.GetAtlasInfo = function() return nil end
    f.provider.update(widget)
    assert(not icon.shown); equal(widget.label.points[1][1], "CENTER")
    f.env.C_Texture = nil; f.provider.update(widget)
    equal(widget.durabilitySummaryIcon, icon); assert(icon.shown)
    equal(#f.textures, 1)
end)

check("interrupted or silent repair atlas setup is hidden and retries the same owned texture", function()
    for _, mode in ipairs({ "throws", "no-op" }) do
        local f = fixture(); f.gear[1] = { 75, 100 }
        f.atlasError, f.atlasNoOp = mode == "throws", mode == "no-op"
        local widget = f:widget(nil, true)
        local ok, reason = pcall(f.provider.update, widget)
        assert(not ok and type(reason) == "string")
        local icon = assert(widget.durabilitySummaryIcon)
        assert(not icon.shown)
        equal(widget.customWidth, nil); equal(widget.label.points[1][1], "CENTER")
        f.atlasError, f.atlasNoOp = false, false
        f.provider.update(widget)
        equal(widget.durabilitySummaryIcon, icon); assert(icon.shown)
        equal(#f.textures, 1); equal(icon.atlas, "SpellIcon-256x256-Repair")
        equal(widget.label.text, "75%")
    end
end)

check("nil texture application fails honestly and cleanup preserves the original diagnostic", function()
    local f = fixture(); f.gear[1] = { 10, 100 }; f.alerts[1] = 1
    local widget = f:widget(nil, true); f.textureUnavailable = true
    local ok, reason = pcall(f.provider.update, widget)
    assert(not ok and tostring(reason):find("Durability icon could not be applied", 1, true))
    f.textureUnavailable = false; f.provider.update(widget)
    local icon = widget.durabilityRegions[1].icon
    icon.SetVertexColor = function() error("original tint failure") end
    local hides = 0
    icon.Hide = function()
        hides = hides + 1
        if hides > 1 then error("secondary cleanup failure") end
    end
    ok, reason = pcall(f.provider.update, widget)
    assert(not ok and tostring(reason):find("original tint failure", 1, true))
end)

print(passed .. " Durability tests passed")
