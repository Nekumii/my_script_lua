local ModCompat = require("mod_compatibility")

local BASE_NIGHTMARE_SHADOW_CREATURE_TARGETS =
{
    crawlinghorror = true,
    crawlingnightmare = true,
    terrorbeak = true,
    nightmarebeak = true,
    oceanhorror = true,
}

local function IsSwimminghorrorTargetEnabled()
    return ModCompat.IsTropicalCompatEnabled()
end

local function IsUncompromisingShadowTargetEnabled()
    return ModCompat.IsEnabled(ModCompat.MODS.UNCOMPROMISING)
end

-- Uncompromising: low-sanity spawner + random night events (creepingfear excluded — boss-tier spawn).
local UNCOMPROMISING_NIGHTMARE_SHADOW_CREATURE_TARGETS =
{
    dreadeye = true,
    mindweaver = true,
    nervoustick = true,
    nervoustickden = true,
    nightcrawler = true,
    fuelseeker = true,
}

local MOD_GATED_NIGHTMARE_SHADOW_CREATURE_TARGETS =
{
    swimminghorror = IsSwimminghorrorTargetEnabled,
}

local function IsNightmareShadowCreatureTarget(inst)
    if inst == nil or inst.prefab == nil then
        return false
    end

    if BASE_NIGHTMARE_SHADOW_CREATURE_TARGETS[inst.prefab] then
        return true
    end

    if UNCOMPROMISING_NIGHTMARE_SHADOW_CREATURE_TARGETS[inst.prefab] and IsUncompromisingShadowTargetEnabled() then
        return true
    end

    local isenabled = MOD_GATED_NIGHTMARE_SHADOW_CREATURE_TARGETS[inst.prefab]
    return isenabled ~= nil and isenabled()
end

return {
    BASE_NIGHTMARE_SHADOW_CREATURE_TARGETS = BASE_NIGHTMARE_SHADOW_CREATURE_TARGETS,
    UNCOMPROMISING_NIGHTMARE_SHADOW_CREATURE_TARGETS = UNCOMPROMISING_NIGHTMARE_SHADOW_CREATURE_TARGETS,
    MOD_GATED_NIGHTMARE_SHADOW_CREATURE_TARGETS = MOD_GATED_NIGHTMARE_SHADOW_CREATURE_TARGETS,
    IsNightmareShadowCreatureTarget = IsNightmareShadowCreatureTarget,
}
