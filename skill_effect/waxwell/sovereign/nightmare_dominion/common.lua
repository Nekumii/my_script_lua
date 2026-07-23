local V = require("skill_effect/waxwell/sovereign/nightmare_dominion/variables")
local ShadowTargets = require("skill_effect/waxwell/sovereign/_shared/shadow_creature_targets")

local function IsNightmareDominionActive(inst)
    return inst ~= nil
        and inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_nightmare_dominion")
end

local function IsNightmareDominionTarget(inst)
    return ShadowTargets.IsNightmareShadowCreatureTarget(inst)
end

local function GetNightmareDominionDamageMultiplier(inst, target)
    if inst == nil or not IsNightmareDominionActive(inst) or not IsNightmareDominionTarget(target) then
        return 1
    end

    return 1 + V.NIGHTMARE_DOMINION_DAMAGE_BONUS
end

local function GetNightmareDominionDamageTakenMultiplier(inst, attacker)
    if inst == nil or not IsNightmareDominionActive(inst) or not IsNightmareDominionTarget(attacker) then
        return 1
    end

    return math.max(0, 1 - V.NIGHTMARE_DOMINION_DAMAGE_REDUCTION)
end

local function GetNightmareDominionDarknessDamageMultiplier(inst)
    if inst == nil or not IsNightmareDominionActive(inst) then
        return 1
    end

    return math.max(0, 1 - V.NIGHTMARE_DOMINION_DAMAGE_REDUCTION)
end

return {
    IsNightmareDominionActive = IsNightmareDominionActive,
    IsNightmareDominionTarget = IsNightmareDominionTarget,
    GetNightmareDominionDamageMultiplier = GetNightmareDominionDamageMultiplier,
    GetNightmareDominionDamageTakenMultiplier = GetNightmareDominionDamageTakenMultiplier,
    GetNightmareDominionDarknessDamageMultiplier = GetNightmareDominionDarknessDamageMultiplier,
}
