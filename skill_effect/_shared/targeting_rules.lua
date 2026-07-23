local warned_conflicts = {}

local function HasAnyTagSafe(ent, tags)
    return ent ~= nil and tags ~= nil and #tags > 0 and ent:HasAnyTag(tags)
end

local function HasOneOfTagsSafe(ent, tags)
    return ent ~= nil and tags ~= nil and #tags > 0 and ent:HasOneOfTags(tags)
end

local function HasAllTagsSafe(ent, tags)
    if ent == nil or tags == nil then
        return true
    end

    for _, tag in ipairs(tags) do
        if not ent:HasTag(tag) then
            return false
        end
    end

    return true
end

local function WarnListConflicts(name, whitelist_prefabs, blacklist_prefabs)
    if name == nil or whitelist_prefabs == nil or blacklist_prefabs == nil then
        return
    end

    for prefab in pairs(whitelist_prefabs) do
        if blacklist_prefabs[prefab] and not warned_conflicts[name .. ":" .. prefab] then
            warned_conflicts[name .. ":" .. prefab] = true
            print("[Skill Tree][TargetingRules] blacklist overrides whitelist for", name, prefab)
        end
    end
end

local function IsEntityAllowed(ent, rules)
    if ent == nil or rules == nil then
        return false
    end

    local prefab = ent.prefab or ""
    local blacklist_prefabs = rules.blacklist_prefabs
    local whitelist_prefabs = rules.whitelist_prefabs
    local blacklist_tags = rules.blacklist_tags or rules.no_tags or rules.cant_tags
    local must_tags = rules.must_tags
    local one_of_tags = rules.one_of_tags
    local extra_check = rules.extra_check

    WarnListConflicts(rules.name, whitelist_prefabs, blacklist_prefabs)

    if blacklist_prefabs ~= nil and blacklist_prefabs[prefab] then
        return false
    end

    if HasAnyTagSafe(ent, blacklist_tags) then
        return false
    end

    if whitelist_prefabs ~= nil and whitelist_prefabs[prefab] then
        return extra_check == nil or extra_check(ent)
    end

    if must_tags ~= nil and not HasAllTagsSafe(ent, must_tags) then
        return false
    end

    if one_of_tags ~= nil and not HasOneOfTagsSafe(ent, one_of_tags) then
        return false
    end

    return extra_check == nil or extra_check(ent)
end

return {
    IsEntityAllowed = IsEntityAllowed,
}
