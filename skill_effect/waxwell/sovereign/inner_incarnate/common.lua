local V = require("skill_effect/waxwell/sovereign/inner_incarnate/variables")
local mind_over_matter = require("skill_effect/waxwell/sovereign/mind_over_matter/common")
local shadow_level = require("skill_effect/waxwell/_shared/shadow_level")

local INNER_INCARNATE_TAG = "inner_incarnate_active"

local function IsInnerIncarnateActive(inst)
    if inst == nil then
        return false
    end

    if inst:HasTag(INNER_INCARNATE_TAG) then
        return true
    end

    local skilltreeupdater = inst.components ~= nil and inst.components.skilltreeupdater or nil
    return skilltreeupdater ~= nil
        and skilltreeupdater:IsActivated("waxwell_inner_incarnate")
end

local function GetInnerIncarnateDamageReductionMult(inst)
    if not IsInnerIncarnateActive(inst) then
        return 1
    end

    local level = shadow_level.GetPlayerShadowLevel(inst)
    local per_level = V.INNER_INCARNATE_DAMAGE_REDUCTION_PER_LEVEL or .005
    return math.max(0, 1 - level * per_level)
end

local function RefreshInnerIncarnateSanityRegen(inst)
    if inst == nil or not TheWorld.ismastersim or inst.components == nil or inst.components.sanity == nil then
        return
    end

    local sanity = inst.components.sanity
    local dapperness = TUNING.DAPPERNESS_LARGE

    if mind_over_matter.IsMindOverMatterActive(inst) then
        local mom_V = require("skill_effect/waxwell/sovereign/mind_over_matter/variables")
        dapperness = mom_V.MIND_OVER_MATTER_DAPPERNESS or (10 / 60)
    end

    if IsInnerIncarnateActive(inst) then
        local level = shadow_level.GetPlayerShadowLevel(inst)
        dapperness = dapperness + level * (V.INNER_INCARNATE_SANITY_REGEN_PER_LEVEL or (0.5 / 60))
    end

    sanity.dapperness = dapperness
end

local function RefreshInnerIncarnateCombatBonus(inst)
    if inst == nil or not TheWorld.ismastersim or inst.components == nil or inst.components.combat == nil then
        return
    end

    local combat = inst.components.combat
    if not IsInnerIncarnateActive(inst) then
        if combat._waxwell_inner_incarnate_bonusfn ~= nil then
            combat.bonusdamagefn = combat._waxwell_inner_incarnate_old_bonusfn
            combat._waxwell_inner_incarnate_bonusfn = nil
            combat._waxwell_inner_incarnate_old_bonusfn = nil
        end
        return
    end

    if combat._waxwell_inner_incarnate_bonusfn == nil then
        combat._waxwell_inner_incarnate_old_bonusfn = combat.bonusdamagefn
        combat._waxwell_inner_incarnate_bonusfn = function(attacker, target, damage, weapon)
            local bonus = 0
            if combat._waxwell_inner_incarnate_old_bonusfn ~= nil then
                bonus = combat._waxwell_inner_incarnate_old_bonusfn(attacker, target, damage, weapon) or 0
            end
            if attacker ~= nil
                and attacker:IsValid()
                and IsInnerIncarnateActive(attacker) then
                bonus = bonus + shadow_level.GetPlayerShadowLevel(attacker) * (V.INNER_INCARNATE_FLAT_DAMAGE_PER_LEVEL or 2)
            end
            return bonus
        end
        combat.bonusdamagefn = combat._waxwell_inner_incarnate_bonusfn
    end
end

local function OnInnerIncarnateStateChanged(inst)
    RefreshInnerIncarnateSanityRegen(inst)
    RefreshInnerIncarnateCombatBonus(inst)

    local expanded_hook = nil
    local ok, hook = pcall(require, "skill_effect/waxwell/puppeteer/expanded_dominion/hook")
    if ok then
        expanded_hook = hook
    end
    if expanded_hook ~= nil and expanded_hook.RefreshWaxwellShadowServantState ~= nil then
        expanded_hook.RefreshWaxwellShadowServantState(inst)
    end
end

local function ApplyInnerIncarnateToWaxwell(inst)
    if inst == nil or not TheWorld.ismastersim or inst._waxwell_inner_incarnate_patched then
        return
    end

    inst._waxwell_inner_incarnate_patched = true

    local health = inst.components.health
    if health ~= nil then
        local old_deltamodifierfn = health.deltamodifierfn
        health.deltamodifierfn = function(target, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
            if amount ~= nil
                and amount < 0
                and target ~= nil
                and IsInnerIncarnateActive(target) then
                amount = amount * GetInnerIncarnateDamageReductionMult(target)
            end

            if old_deltamodifierfn ~= nil then
                return old_deltamodifierfn(target, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
            end

            return amount
        end
    end

    OnInnerIncarnateStateChanged(inst)

    inst:ListenForEvent("onactivateskill_server", function()
        OnInnerIncarnateStateChanged(inst)
    end)
    inst:ListenForEvent("ondeactivateskill_server", function()
        OnInnerIncarnateStateChanged(inst)
    end)

    if inst.components.inventory ~= nil then
        inst:ListenForEvent("equip", function()
            RefreshInnerIncarnateSanityRegen(inst)
        end, inst.components.inventory)
        inst:ListenForEvent("unequip", function()
            RefreshInnerIncarnateSanityRegen(inst)
        end, inst.components.inventory)
    end
end

return {
    IsInnerIncarnateActive = IsInnerIncarnateActive,
    GetInnerIncarnateSummonSlotPenalty = function(inst)
        return IsInnerIncarnateActive(inst) and (V.INNER_INCARNATE_SUMMON_SLOT_PENALTY or 2) or 0
    end,
    RefreshInnerIncarnateSanityRegen = RefreshInnerIncarnateSanityRegen,
    ApplyInnerIncarnateToWaxwell = ApplyInnerIncarnateToWaxwell,
}
