-- Character settings use the player's opaque GUID when available. Display names
-- and realm labels are only migration hints, never substitutes for a hidden GUID.
local Identity = {}
_G.MenubarIdentity = Identity

local function public(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function name(value)
    return public(value) and type(value) == "string" and value:match("%S") and value or nil
end

local function read(method, ...)
    if type(method) ~= "function" then return nil, "absent" end
    local ok, value = pcall(method, ...)
    if not ok then return nil, "unavailable" end
    if not public(value) then return nil, "restricted" end
    if value ~= nil and type(value) ~= "string" then return nil, "invalid" end
    return name(value), "readable", type(value) == "string" and value or nil
end

function Identity.Read(saved)
    local guid, guidStatus = read(UnitGUID, "player")
    if guidStatus ~= "absent" and not guid then
        return nil, "Character identity is unavailable; existing settings have been preserved."
    end
    local first = read(UnitName, "player")
    local full = read(GetUnitName, "player", false) or first
    if not full then return nil, "Character name is not ready; existing settings have been preserved." end
    local realm, realmStatus, rawRealm = read(GetRealmName)
    local key = guid and ("guid:" .. guid) or (realm and (full .. " - " .. realm))
    if not key then
        return nil, "Character identity is not ready; existing settings have been preserved."
    end

    local characters = type(saved) == "table" and type(saved.characters) == "table" and saved.characters or {}
    local candidates, seen = {}, {}
    local function add(candidate)
        if candidate and candidate ~= key and not seen[candidate] and type(characters[candidate]) == "table" then
            candidates[#candidates + 1], seen[candidate] = candidate, true
        end
    end
    if realmStatus == "readable" then
        -- Reproduce the old key exactly, including a real empty string. The
        -- old code treated nil as 'Realm', but an empty realm remained empty.
        local legacyRealm = rawRealm or "Realm"
        if first then add(first .. " - " .. legacyRealm) end
        add(full .. " - " .. legacyRealm)
    end
    -- When a realm label disappears, one matching legacy record is safe to
    -- copy. Several candidates require an explicit choice; never combine them.
    if #candidates == 0 then
        local matches = {}
        for candidate, character in pairs(characters) do
            if type(candidate) == "string" and type(character) == "table"
                and (candidate:sub(1, #full + 3) == full .. " - "
                    or (first and candidate:sub(1, #first + 3) == first .. " - ")) then
                matches[#matches + 1] = candidate
            end
        end
        if #matches == 1 then add(matches[1])
        elseif #matches > 1 and type(characters[key]) ~= "table" then
            table.sort(matches)
            return nil, "Several saved layouts match this character. Existing settings are preserved; /menubar recover lets you choose one.",
                { key = key, legacyKeys = matches }
        end
    end
    return { key = key, legacyKeys = candidates }
end

return Identity
