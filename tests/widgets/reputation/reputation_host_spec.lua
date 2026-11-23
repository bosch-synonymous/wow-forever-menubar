-- Native Reputation ownership through actual Core/provider TOCs and settings.
local root = REPO_ROOT or "."
local build = dofile(root .. "/tests/native_status_bar_host_fixture.lua")
local function fixture() return build("reputation") end
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(name, run)
    local ok, reason = pcall(run)
    if not ok then error(name .. ": " .. tostring(reason), 0) end
    passed = passed + 1; print("PASS " .. name)
end
check("real Reputation settings hide and restore native bars without the XP addon", function()
    local host, widget, request, _, concealed, restored = fixture()
    assert(host.types.xp == nil); equal(host.types.reputation.defaults.hideBlizzardReputationBar, true)
    concealed(); request(widget, false); restored(); request(widget, true); concealed()
    request(widget, false); restored(); equal(widget.gauge:GetValue(), 1500)
    equal(widget.gaugeLabel:GetText(), "Stormwind")
end)
check("real Reputation duplicates retain requests through disable enable and removal", function()
    local host, first, request, _, concealed, restored = fixture()
    local created = host:AddWidget("reputation"); local second = host.runtime[created.id]
    concealed(); request(first, false); concealed()
    second.instance.enabled = false; host:Rebuild(); restored()
    second.instance.enabled = true; host:Rebuild(); concealed()
    request(first, true); host:RemoveWidget(second.id); concealed()
    host:RemoveWidget(first.id); restored()
end)
check("Reputation appearance rebuild and overflow preserve enabled suppression", function()
    local host, widget, request, step, concealed, restored = fixture()
    host:GetProfile().placement = "both"; host:Rebuild(); equal(host.runtime[widget.id], widget); concealed()
    UIParent:SetWidth(80); host:Rebuild(); equal(widget.frame:IsShown(), false); step(0.3); concealed()
    UIParent:SetWidth(1280); host:Rebuild(); request(widget, false); restored()
end)
check("real Reputation render failure restores native UI and a refresh can recover", function()
    local host, widget, _, _, concealed, restored = fixture()
    concealed(); local setGauge = widget.SetGauge
    widget.SetGauge = function() error("simulated reputation rendering failure", 0) end
    host:RefreshWidget(widget.id); equal(widget.failed, "simulated reputation rendering failure"); restored()
    widget.SetGauge = setGauge; host:RefreshWidget(widget.id); equal(widget.failed, nil); concealed()
    host:RemoveWidget(widget.id); restored()
end)
check("real Reputation faction focus remains independent from the game's watched faction", function()
    local host, widget, request, _, concealed, restored, target, _, _, watched = fixture()
    widget.settings.factionID = 99; host:RefreshWidget(widget.id)
    equal(widget.reputationState.factionID, 99); equal(watched.id, 72); equal(watched.writes, 0)
    equal(target.shownBarIndex, 2); concealed(); request(widget, false); restored()
end)
print(passed .. " Reputation host integration tests passed")
