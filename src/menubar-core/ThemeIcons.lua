-- Original artwork from tools/generate_theme_icons.py. The same texture region
-- can stay anchored (and animated) while themes and notification states change.
local sheet = "Interface\\AddOns\\Menubar\\Media\\ThemeIcons\\status.tga"
local rows = { system7 = 0, macos8 = 1, macosx = 2, macos27 = 3 }
local columns = {
    ["volume-muted"] = 0, ["volume-low"] = 1, ["volume-medium"] = 2, ["volume-high"] = 3,
    mail = 4, social = 5, ["social-alert"] = 6, ["social-group"] = 7,
}

-- Returns a texture path followed by SetTexCoord's left, right, top, bottom.
-- An unknown role or a theme without an override uses the widget's own icon.
local function themeIcon(theme, role)
    local col = columns[role]
    local row = rows[theme]
    -- Aqua and Glass share a bell silhouette; each profile supplies its ink.
    if theme == "macosx" and col and col >= columns.social then row = rows.macos27 end
    -- The game supplies these as button atlases. Use our cream envelope and brass
    -- bells for Warcraft so the glyph is the only artwork on the bar.
    if not row and col and col >= columns.mail and MenubarSkins.IsWarcraft(theme) then row = rows.system7 end
    if col and row then
        return sheet, col / 8, (col + 1) / 8, row / 4, (row + 1) / 4
    end
end

function Menubar:GetThemeIcon(role)
    if self.ready then return themeIcon(self:GetProfile().theme, role) end
end

-- Pass an addon-owned Texture and the widget label. Harmony and Platinum carry their own
-- pixel palette, while the monochrome families take the label's colour.
-- A false return leaves the caller free to apply its normal texture or atlas.
function Menubar:ApplyThemeIcon(texture, role, label)
    local theme = self.ready and self:GetProfile().theme
    local path, left, right, top, bottom = themeIcon(theme, role)
    if path then
        if not texture.menubarThemeIcon and texture:SetTexture(path) == false then return false end
        texture.menubarThemeIcon = true
        texture:SetTexCoord(left, right, top, bottom)
        local red, green, blue, alpha = label:GetTextColor()
        if theme == "system7" or theme == "macos8" or MenubarSkins.IsWarcraft(theme) then
            red, green, blue = 1, 1, 1
        end
        texture:SetVertexColor(red, green, blue, alpha)
        return true
    end
    if texture.menubarThemeIcon then
        texture.menubarThemeIcon = nil
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetVertexColor(1, 1, 1, 1)
    end
    return false
end
