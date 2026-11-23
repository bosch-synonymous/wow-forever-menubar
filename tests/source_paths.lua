-- Source aliases are development layout; these keys are installed TOC identities.
return function(repository, addon)
    local mapped = type(MENUBAR_SOURCE_DIRS) == "table" and MENUBAR_SOURCE_DIRS[addon]
    if type(mapped) == "string" then return mapped end
    -- Support direct Lua test execution from this repository without the runner.
    local alias
    if addon == "Menubar" then alias = "menubar-core"
    elseif type(addon) == "string" and addon:sub(1, 8) == "Menubar_" then
        alias = "menubar-" .. addon:sub(9):lower()
    else error("Unknown source addon identity: " .. tostring(addon), 0) end
    return repository .. "/src/" .. alias
end
