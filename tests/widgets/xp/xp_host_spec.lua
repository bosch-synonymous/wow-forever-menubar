local sourceDirectory = dofile((REPO_ROOT or ".") .. "/tests/source_paths.lua")
-- XP visibility through the real host/settings lifecycle. This models the
-- verified native frame contract, not native taint, animation or combat rules.
local root = REPO_ROOT or "."
local core = MENUBAR_CORE_ROOT or root
local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end
if not exists(core .. "/tests/wow_stub.lua") then
    print("SKIP XP host integration: restore Core in this repository or supply MENUBAR_CORE_ROOT.")
    return
end

local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local passed = 0
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end

local function loadAddon(repository, addon)
    local namespace = {}
    for line in io.lines(sourceDirectory(repository, addon) .. "/" .. addon .. ".toc") do
        local file = line:match("^%s*(.-)%s*$")
        if file:match("%.lua$") then
            assert(loadfile(sourceDirectory(repository, addon) .. "/" .. file))(addon, namespace)
        end
    end
end

local fixture = dofile(root .. "/tests/native_status_bar_host_fixture.lua")

check("real XP factory settings replace native bars and the opt-out restores them reversibly", function()
    local host, widget, request, _, concealed, restored = fixture()
    equal(host.types.xp.defaults.hideBlizzardXPBar, true)
    concealed()
    request(widget, false)
    restored()
    request(widget, true); concealed(); request(widget, false); restored()
    equal(widget.gauge:GetValue(), 250)
    equal(widget.gaugeLabel:GetText(), "Lv 20")
end)

check("two real XP requesters keep concealment until the final request is disabled", function()
    local host, first, request, _, concealed, restored = fixture()
    local created = host:AddWidget("xp")
    local second = host.runtime[created.id]
    request(first, true); request(second, true)
    concealed()
    request(first, false)
    concealed()
    second.instance.enabled = false
    host:Rebuild()
    equal(host.runtime[second.id], nil)
    restored()
    second.instance.enabled = true
    host:Rebuild()
    concealed()
    request(first, true)
    host:RemoveWidget(second.id)
    concealed()
    host:RemoveWidget(first.id)
    restored()
end)

check("appearance rebuild and overflow preserve an enabled XP request", function()
    local host, widget, request, step, concealed, restored = fixture()
    request(widget, true)
    local profile = host:GetProfile()
    profile.placement, profile.fontSize = "both", 18
    host:Rebuild()
    equal(host.runtime[widget.id], widget)
    concealed()
    UIParent:SetWidth(80)
    host:Rebuild()
    equal(widget.frame:IsShown(), false)
    step(0.3)
    concealed()
    UIParent:SetWidth(1280)
    host:Rebuild()
    request(widget, false)
    restored()
end)

check("a real XP rendering failure releases suppression and explicit refresh can recover it", function()
    local host, widget, request, _, concealed, restored = fixture()
    request(widget, true)
    concealed()
    local setGauge = widget.SetGauge
    widget.SetGauge = function() error("simulated native gauge failure", 0) end
    host:RefreshWidget(widget.id)
    equal(widget.failed, "simulated native gauge failure")
    equal(widget.failedCallback, "update")
    assert(widget.text:find("error", 1, true))
    restored()
    widget.SetGauge = setGauge
    host:RefreshWidget(widget.id)
    equal(widget.failed, nil)
    equal(widget.settings.hideBlizzardXPBar, true)
    concealed()
    host:RemoveWidget(widget.id)
    restored()
end)

check("native XP-to-reputation transitions restore shared chrome without changing selection", function()
    local host, widget, request, step, concealed, restored, primary = fixture()
    request(widget, true)
    concealed()
    primary.bars[1].nativeHide(primary.bars[1])
    primary.shownBarIndex = 2
    primary.bars[2].nativeShow(primary.bars[2])
    step(0.3)
    equal(primary.BarFrameTexture:GetAlpha(), 0.63)
    equal(primary.divider:GetAlpha(), 0.42)
    equal(primary.bars[2]:GetAlpha(), 0.9)
    equal(primary.shownBarIndex, 2)
    primary.bars[2].nativeHide(primary.bars[2])
    primary.shownBarIndex = 1
    primary.bars[1].nativeShow(primary.bars[1])
    step(0.3)
    concealed()
    equal(primary.shownBarIndex, 1)
    host:RemoveWidget(widget.id)
    restored()
end)

print(passed .. " XP host integration tests passed")
