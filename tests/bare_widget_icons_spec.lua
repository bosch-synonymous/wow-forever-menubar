-- The glyph must be the only painted texture in the widget at rest.
-- Native HIGHLIGHT textures draw only while the mouse is over the widget.
local root = REPO_ROOT or "."
local sourceDirectory = dofile(root .. "/tests/source_paths.lua")
local Stub = dofile(root .. "/tests/wow_stub.lua")
Stub.Install()
C_CVar = { GetCVar = function(key) return key == "Sound_MasterVolume" and "0.5" or "1" end }
HasNewMail = function() return true end

for _, addon in ipairs({ "Menubar", "Menubar_Volume", "Menubar_Social", "Menubar_Mail" }) do
    local directory = sourceDirectory(root, addon)
    local namespace = {}
    for line in io.lines(directory .. "/" .. addon .. ".toc") do
        local file = line:match("^%s*(%S+%.lua)%s*$")
        if file then assert(loadfile(directory .. "/" .. file))(addon, namespace) end
    end
end
Menubar:Start()

local function belongsTo(region, ancestor)
    while region do
        if region == ancestor then return true end
        region = region:GetParent()
    end
end

local icons = { volume = "volumeIcon", social = "socialIcon", mail = "mailIcon" }
local profile = Menubar:GetProfile()
for theme in pairs(MenubarModel.Themes) do
    assert(MenubarModel.ApplyTheme(profile, theme))
    for _, opacity in ipairs({ 0, 1 }) do
        profile.opacity = opacity
        Menubar:Rebuild()
        local checked = {}
        for _, widget in pairs(Menubar.runtime) do
            local kind = widget.instance.type
            local field = icons[kind]
            if field then
                local glyph = assert(widget[field], theme .. " missing " .. kind .. " icon")
                assert(glyph:IsVisible() and glyph:GetEffectiveAlpha() == 1, theme .. " faded " .. kind)
                for _, texture in ipairs(Stub.textures) do
                    if texture ~= glyph and texture.drawLayer ~= "HIGHLIGHT" and texture:IsVisible() then
                        assert(not belongsTo(texture, widget.frame), theme .. " paints an extra " .. kind .. " texture")
                    end
                end
                checked[kind] = true
            end
        end
        for kind in pairs(icons) do assert(checked[kind], "Missing " .. kind .. " widget") end
    end
end
print("PASS bare Mail, Social and Volume icons on transparent and opaque bars in every theme")
