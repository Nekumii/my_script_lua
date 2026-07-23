local V = require("skill_effect/waxwell/puppeteer/fragmented_mind/variables")

local expanded_dominion_common = nil

local function GetExpandedDominionCommon()
    if expanded_dominion_common == nil then
        expanded_dominion_common = require("skill_effect/waxwell/puppeteer/expanded_dominion/common")
    end

    return expanded_dominion_common
end

local function IsFragmentedMindActive(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_fragmented_mind"))
            or inst:HasTag("fragmented_mind_active")
        )
end

local function HasFragmentedMindPenaltyReduction(inst)
    return inst ~= nil and (inst._waxwell_fragmented_mind_penalty or inst:HasTag(V.FRAGMENTED_MIND_PENALTY_TAG))
end

local function MarkFragmentedMindPenaltyReduction(inst)
    if inst == nil then
        return
    end

    inst._waxwell_fragmented_mind_penalty = true
    if not inst:HasTag(V.FRAGMENTED_MIND_PENALTY_TAG) then
        inst:AddTag(V.FRAGMENTED_MIND_PENALTY_TAG)
    end
end

local function GetFragmentedMindPenalty(owner, prefab)
    if prefab == nil then
        return nil
    end

    prefab = string.lower(prefab)
    local penaltykey =
        prefab == "shadow_marksman" and "SHADOW_MARKSMAN"
        or string.upper(prefab)

    local penalty = TUNING.SHADOWWAXWELL_SANITY_PENALTY[penaltykey]
    if penalty == nil and prefab == "shadow_marksman" then
        penalty = TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_MARKSMAN
            or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_PROTECTOR
    elseif penalty == nil and prefab == "shadow_lanternbearer" then
        penalty = TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_LANTERNBEARER
            or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_WORKER
    end
    if penalty == nil then
        return nil
    end

    if V.FRAGMENTED_MIND_PUPPETS[prefab] and IsFragmentedMindActive(owner) then
        return V.FRAGMENTED_MIND_REDUCED_PENALTIES[prefab] or penalty
    end

    return penalty
end

local function GetFragmentedMindSpellPuppet(inst)
    local spellbook = inst ~= nil and inst.components.spellbook or nil
    return spellbook ~= nil and V.FRAGMENTED_MIND_SPELLS[spellbook:GetSpellName()] or nil
end

local function CanCastFragmentedMindSpell(doer, sanity, prefab)
    local penalty = GetFragmentedMindPenalty(doer, prefab)
    local petleash = doer ~= nil and doer.components ~= nil and doer.components.petleash or nil
    return sanity ~= nil
        and penalty ~= nil
        and sanity:GetPenaltyPercent() + penalty <= TUNING.MAXIMUM_SANITY_PENALTY
        and (petleash == nil or not GetExpandedDominionCommon().IsShadowServantCapFull(petleash))
end

local function WithAdjustedPenaltyPercent(sanity, offset, fn)
    if sanity == nil or fn == nil or offset == nil or offset <= 0 then
        return fn()
    end

    local old_GetPenaltyPercent = sanity.GetPenaltyPercent
    sanity.GetPenaltyPercent = function(self, ...)
        return math.max(0, old_GetPenaltyPercent(self, ...) - offset)
    end

    local ok, result, reason = xpcall(fn, debug.traceback)
    sanity.GetPenaltyPercent = old_GetPenaltyPercent

    if not ok then
        error(result)
    end

    return result, reason
end

return {
    FRAGMENTED_MIND_PENALTY = V.FRAGMENTED_MIND_PENALTY,
    IsFragmentedMindActive = IsFragmentedMindActive,
    HasFragmentedMindPenaltyReduction = HasFragmentedMindPenaltyReduction,
    MarkFragmentedMindPenaltyReduction = MarkFragmentedMindPenaltyReduction,
    GetFragmentedMindPenalty = GetFragmentedMindPenalty,
    GetFragmentedMindSpellPuppet = GetFragmentedMindSpellPuppet,
    CanCastFragmentedMindSpell = CanCastFragmentedMindSpell,
    WithAdjustedPenaltyPercent = WithAdjustedPenaltyPercent,
}
