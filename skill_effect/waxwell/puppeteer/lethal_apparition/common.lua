local V = require("skill_effect/waxwell/puppeteer/lethal_apparition/variables")

local function IsLethalApparition1Active(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_lethal_apparition_1"))
            or inst:HasTag("lethal_apparition_1_active")
        )
end

local function IsLethalApparition2Active(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_lethal_apparition_2"))
            or inst:HasTag("lethal_apparition_2_active")
        )
end

local function IsLethalApparition1ShadowDuelist(inst)
    return inst ~= nil and (inst._waxwell_lethal_apparition_1 or inst:HasTag(V.LETHAL_APPARITION_1_TAG))
end

local function MarkLethalApparition1ShadowDuelist(inst)
    if inst == nil then
        return
    end

    inst._waxwell_lethal_apparition_1 = true
    if not inst:HasTag(V.LETHAL_APPARITION_1_TAG) then
        inst:AddTag(V.LETHAL_APPARITION_1_TAG)
    end
end

local function IsLethalApparition2ShadowDuelist(inst)
    return inst ~= nil and (inst._waxwell_lethal_apparition_2 or inst:HasTag(V.LETHAL_APPARITION_2_TAG))
end

local function MarkLethalApparition2ShadowDuelist(inst)
    if inst == nil then
        return
    end

    inst._waxwell_lethal_apparition_2 = true
    if not inst:HasTag(V.LETHAL_APPARITION_2_TAG) then
        inst:AddTag(V.LETHAL_APPARITION_2_TAG)
    end
end

local function ApplyLethalApparition1ToProtector(inst, force_enhance)
    if not (inst:IsValid() and inst.components.health ~= nil and inst.components.follower ~= nil) then
        return
    end

    local enhanced = IsLethalApparition1ShadowDuelist(inst)
    if not enhanced and not force_enhance then
        return
    end

    local timer = inst.components.timer
    local obliviate = timer ~= nil and timer.timers ~= nil and timer.timers.obliviate or nil
    local has_duration_bonus = obliviate ~= nil
        and (obliviate.initial_time or 0) > (TUNING.SHADOWWAXWELL_PROTECTOR_DURATION + 1)
    local health = inst.components.health
    local currenthealth = health.currenthealth
    if force_enhance and not enhanced then
        MarkLethalApparition1ShadowDuelist(inst)
        currenthealth = V.LETHAL_APPARITION_1_HEALTH
    end

    health.save_maxhealth = true
    if health.maxhealth ~= V.LETHAL_APPARITION_1_HEALTH then
        health:SetMaxHealth(V.LETHAL_APPARITION_1_HEALTH)
    end

    if currenthealth ~= nil then
        health:SetCurrentHealth(math.min(currenthealth, V.LETHAL_APPARITION_1_HEALTH))
    end

    health:ForceUpdateHUD(true)

    if timer == nil or not timer:TimerExists("obliviate") or has_duration_bonus then
        return
    end

    local base_duration = obliviate.initial_time or TUNING.SHADOWWAXWELL_PROTECTOR_DURATION
    local duration_bonus = base_duration * V.LETHAL_APPARITION_1_DURATION_BONUS_PCT
    local paused = timer:IsPaused("obliviate")
    local timeleft = timer:GetTimeLeft("obliviate") + duration_bonus
    local initial_time = base_duration + duration_bonus

    timer:StopTimer("obliviate")
    timer:StartTimer("obliviate", timeleft, paused, initial_time)
end

local function ApplyLethalApparition2ToProtector(inst, force_enhance)
    if not (inst:IsValid() and inst.components.combat ~= nil and inst.components.follower ~= nil) then
        return
    end

    local enhanced = IsLethalApparition2ShadowDuelist(inst)
    if not enhanced and not force_enhance then
        return
    end

    if force_enhance and not enhanced then
        MarkLethalApparition2ShadowDuelist(inst)
    end

    local combat = inst.components.combat
    if combat._waxwell_lethal_apparition_2_patched then
        return
    end

    combat._waxwell_lethal_apparition_2_patched = true
    inst:ListenForEvent("onattackother", function(attacker)
        attacker._waxwell_lethal_apparition_2_pending_crit = nil
        local crit = IsLethalApparition2ShadowDuelist(attacker)
            and math.random() < V.LETHAL_APPARITION_2_CRIT_CHANCE
            or nil
        attacker._waxwell_lethal_apparition_2_nextcrit = crit or nil
    end)

    inst:ListenForEvent("onhitother", function(attacker, data)
        attacker._waxwell_lethal_apparition_2_pending_crit = nil
    end)

    local old_customdamagemultfn = combat.customdamagemultfn
    combat.customdamagemultfn = function(attacker, target, weapon, multiplier, mount)
        local mult = old_customdamagemultfn ~= nil and old_customdamagemultfn(attacker, target, weapon, multiplier, mount) or 1
        local crit = attacker ~= nil and attacker:IsValid() and attacker._waxwell_lethal_apparition_2_nextcrit
        if attacker ~= nil then
            attacker._waxwell_lethal_apparition_2_nextcrit = nil
            attacker._waxwell_lethal_apparition_2_pending_crit = crit and true or nil
        end
        if crit then
            mult = mult * V.LETHAL_APPARITION_2_CRIT_MULT
        end
        return mult
    end
end

return {
    IsLethalApparition1Active = IsLethalApparition1Active,
    IsLethalApparition2Active = IsLethalApparition2Active,
    IsLethalApparition1ShadowDuelist = IsLethalApparition1ShadowDuelist,
    MarkLethalApparition1ShadowDuelist = MarkLethalApparition1ShadowDuelist,
    IsLethalApparition2ShadowDuelist = IsLethalApparition2ShadowDuelist,
    MarkLethalApparition2ShadowDuelist = MarkLethalApparition2ShadowDuelist,
    ApplyLethalApparition1ToProtector = ApplyLethalApparition1ToProtector,
    ApplyLethalApparition2ToProtector = ApplyLethalApparition2ToProtector,
}
