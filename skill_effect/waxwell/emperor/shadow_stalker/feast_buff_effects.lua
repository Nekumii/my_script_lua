local FeastBuff = require("skill_effect/waxwell/emperor/shadow_stalker/feast_buff")
local FeastLanternMC = require("skill_effect/waxwell/emperor/shadow_stalker/feast_lantern_mc")
local LethalApparition = require("skill_effect/waxwell/puppeteer/lethal_apparition/common")
local TirelessServant = require("skill_effect/waxwell/puppeteer/tireless_servant/common")
local ShadowMarksman = require("skill_effect/waxwell/puppeteer/shadow_marksman/common")
local LethalVars = require("skill_effect/waxwell/puppeteer/lethal_apparition/variables")

local M = {}

local DUELIST_BASE_MULT = 1.20
local DUELIST_LA1_MULT = 1.40
local DUELIST_PLANAR_BASE = 25
local DUELIST_PLANAR_LA1 = 30
local DUELIST_PLANAR_DEFAULT = 20
local DUELIST_ABSORB_BASE = 0.05
local DUELIST_ABSORB_LA1 = 0.10
local DUELIST_ABSORB_LA2 = 0.15
local DUELIST_ABSORB_KEY = "shadow_stalker_feast_duelist"

local WORKER_SPEED_KEY = "shadow_stalker_feast_worker"

local WORKER_BASE_SPEED_MULT = 1.15
local WORKER_TS1_SPEED_MULT = 1.30
local WORKER_BASE_CD_REDUCTION = 4
local WORKER_TS1_CD_REDUCTION = 8
local WORKER_TS2_CD_RESET_CHANCE = 0.30
local WORKER_NORMAL_DAMAGE_DEFAULT = 80
local WORKER_PLANAR_DAMAGE_DEFAULT = 20
local WORKER_NORMAL_DAMAGE_BASE = 70
local WORKER_PLANAR_DAMAGE_BASE = 15
local WORKER_NORMAL_DAMAGE_TS1 = 60
local WORKER_PLANAR_DAMAGE_TS1 = 10

local MARKSMAN_SNARE_MAX_LV1 = 6
local MARKSMAN_SNARE_MAX_LV2 = 8
local MARKSMAN_SNARE_DURATION_LV1 = 10
local MARKSMAN_SNARE_DURATION_LV2 = 12

local SPIKE_DAMAGE = 24
local SPIKE_DAMAGE_MARKSMAN_LV1 = 30
local SPIKE_DAMAGE_MARKSMAN_LV2 = 36
local SPIKE_PLANAR_DAMAGE = 6
local SPIKE_PLANAR_MARKSMAN_LV1 = 8
local SPIKE_PLANAR_MARKSMAN_LV2 = 10
local SPIKE_SCALE_BASE = 1.5
local SPIKE_SCALE_MARKSMAN_LV1 = 1.75
local SPIKE_SCALE_MARKSMAN_LV2 = 2.0
local SPIKE_COUNT_BASE = 4
local SPIKE_COUNT_MARKSMAN_LV1 = 5
local SPIKE_COUNT_MARKSMAN_LV2 = 6

local SHADOW_STALKER_SKILL_DELAY_TIMER = "skill_delay_cd"

local function FindPlayerByUserID(userid)
    if userid == nil then
        return nil
    end

    for _, player in ipairs(AllPlayers) do
        if player ~= nil and player.userid == userid then
            return player
        end
    end

    return nil
end

local function GetSpellOwner(inst)
    if inst == nil then
        return nil
    end

    local owner = inst._shadow_stalker_spell_owner
    if owner ~= nil and owner:IsValid() then
        return owner
    end

    if inst._shadow_stalker_spell_owner_userid ~= nil then
        owner = FindPlayerByUserID(inst._shadow_stalker_spell_owner_userid)
        if owner ~= nil and owner:IsValid() then
            inst._shadow_stalker_spell_owner = owner
            return owner
        end
    end

    local follower = inst.components ~= nil and inst.components.follower or nil
    return follower ~= nil and follower:GetLeader() or nil
end

local function IsFeastDuelistNormalAttack(inst)
    if inst.sg == nil then
        return false
    end

    return inst.sg:HasStateTag("attack")
        and not inst.sg:HasStateTag("snare")
        and not inst.sg:HasStateTag("spikes")
end

local function GetDuelistDamageMultiplier(owner)
    if owner ~= nil and LethalApparition.IsLethalApparition1Active(owner) then
        return DUELIST_LA1_MULT
    end
    return DUELIST_BASE_MULT
end

local function GetDuelistPlanarDamage(owner)
    if owner ~= nil and LethalApparition.IsLethalApparition1Active(owner) then
        return DUELIST_PLANAR_LA1
    end
    return DUELIST_PLANAR_BASE
end

local function GetDuelistAbsorb(owner)
    if owner ~= nil and LethalApparition.IsLethalApparition2Active(owner) then
        return DUELIST_ABSORB_LA2
    end
    if owner ~= nil and LethalApparition.IsLethalApparition1Active(owner) then
        return DUELIST_ABSORB_LA1
    end
    return DUELIST_ABSORB_BASE
end

local function RemoveDuelistAbsorb(inst)
    if inst.components ~= nil
        and inst.components.health ~= nil
        and inst.components.health.externalabsorbmodifiers ~= nil then
        inst.components.health.externalabsorbmodifiers:RemoveModifier(inst, DUELIST_ABSORB_KEY)
    end
end

local function ApplyDuelistAbsorb(inst, owner)
    RemoveDuelistAbsorb(inst)
    if inst.components ~= nil
        and inst.components.health ~= nil
        and inst.components.health.externalabsorbmodifiers ~= nil then
        inst.components.health.externalabsorbmodifiers:SetModifier(inst, GetDuelistAbsorb(owner), DUELIST_ABSORB_KEY)
    end
end

local function SetDuelistPlanarBase(inst, amount)
    if inst.components ~= nil and inst.components.planardamage ~= nil then
        inst.components.planardamage:SetBaseDamage(amount)
    end
end

local function RemoveDuelistCombatPatch(inst)
    local combat = inst.components ~= nil and inst.components.combat or nil
    if combat == nil then
        return
    end

    if inst._feast_duelist_onattackother ~= nil then
        inst:RemoveEventCallback("onattackother", inst._feast_duelist_onattackother)
        inst._feast_duelist_onattackother = nil
    end
    if inst._feast_duelist_onhitother ~= nil then
        inst:RemoveEventCallback("onhitother", inst._feast_duelist_onhitother)
        inst._feast_duelist_onhitother = nil
    end

    if combat._shadow_stalker_feast_duelist_patched then
        combat.customdamagemultfn = inst._feast_duelist_old_customdamagemultfn
        combat.customspdamagemultfn = inst._feast_duelist_old_customspdamagemultfn
        inst._feast_duelist_old_customdamagemultfn = nil
        inst._feast_duelist_old_customspdamagemultfn = nil
        combat._shadow_stalker_feast_duelist_patched = nil
    end

    SetDuelistPlanarBase(inst, DUELIST_PLANAR_DEFAULT)
    RemoveDuelistAbsorb(inst)
    inst._feast_duelist_damage_mult = nil
    inst._feast_duelist_crit_enabled = nil
    inst._feast_duelist_planar_base = nil
    inst._feast_duelist_planar_crit_pending = nil
    inst._shadow_stalker_feast_duelist_nextcrit = nil
end

local function ApplyDuelistCombatPatch(inst, owner)
    local combat = inst.components ~= nil and inst.components.combat or nil
    if combat == nil or combat._shadow_stalker_feast_duelist_patched then
        return
    end

    inst._feast_duelist_damage_mult = GetDuelistDamageMultiplier(owner)
    inst._feast_duelist_crit_enabled = owner ~= nil and LethalApparition.IsLethalApparition2Active(owner)
    inst._feast_duelist_planar_base = GetDuelistPlanarDamage(owner)
    SetDuelistPlanarBase(inst, inst._feast_duelist_planar_base)

    combat._shadow_stalker_feast_duelist_patched = true
    inst._feast_duelist_old_customdamagemultfn = combat.customdamagemultfn
    inst._feast_duelist_old_customspdamagemultfn = combat.customspdamagemultfn

    inst._feast_duelist_onattackother = function()
        if not IsFeastDuelistNormalAttack(inst) or not inst._feast_duelist_crit_enabled then
            return
        end

        inst._shadow_stalker_feast_duelist_nextcrit = math.random() < LethalVars.LETHAL_APPARITION_2_CRIT_CHANCE or nil
    end
    inst:ListenForEvent("onattackother", inst._feast_duelist_onattackother)

    inst._feast_duelist_onhitother = function()
        inst._shadow_stalker_feast_duelist_nextcrit = nil
        inst._feast_duelist_planar_crit_pending = nil
    end
    inst:ListenForEvent("onhitother", inst._feast_duelist_onhitother)

    combat.customdamagemultfn = function(attacker, target, weapon, multiplier, mount)
        local mult = inst._feast_duelist_old_customdamagemultfn ~= nil
            and inst._feast_duelist_old_customdamagemultfn(attacker, target, weapon, multiplier, mount)
            or multiplier

        if attacker ~= inst or not IsFeastDuelistNormalAttack(inst) then
            return mult
        end

        mult = mult * (inst._feast_duelist_damage_mult or DUELIST_BASE_MULT)

        local crit = inst._feast_duelist_crit_enabled and inst._shadow_stalker_feast_duelist_nextcrit
        inst._shadow_stalker_feast_duelist_nextcrit = nil
        if crit then
            inst._feast_duelist_planar_crit_pending = true
            mult = mult * LethalVars.LETHAL_APPARITION_2_CRIT_MULT
        end

        return mult
    end

    combat.customspdamagemultfn = function(attacker, target, weapon, multiplier, mount)
        local mult = inst._feast_duelist_old_customspdamagemultfn ~= nil
            and inst._feast_duelist_old_customspdamagemultfn(attacker, target, weapon, multiplier, mount)
            or 1

        if attacker ~= inst or not IsFeastDuelistNormalAttack(inst) then
            return mult
        end

        if inst._feast_duelist_planar_crit_pending then
            inst._feast_duelist_planar_crit_pending = nil
            return mult * LethalVars.LETHAL_APPARITION_2_CRIT_MULT
        end

        return mult
    end
end

local function RemoveWorkerSpeed(inst)
    if inst.components ~= nil and inst.components.locomotor ~= nil then
        inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, WORKER_SPEED_KEY)
    end
end

local function GetWorkerSpeedMultiplier(owner)
    if owner ~= nil and TirelessServant.IsTirelessServant1Active(owner) then
        return WORKER_TS1_SPEED_MULT
    end
    return WORKER_BASE_SPEED_MULT
end

local function GetWorkerCooldownReduction(owner)
    if owner ~= nil and TirelessServant.IsTirelessServant1Active(owner) then
        return WORKER_TS1_CD_REDUCTION
    end
    return WORKER_BASE_CD_REDUCTION
end

local function GetWorkerNormalAttackDamage(owner)
    if owner ~= nil and TirelessServant.IsTirelessServant1Active(owner) then
        return WORKER_NORMAL_DAMAGE_TS1, WORKER_PLANAR_DAMAGE_TS1
    end
    return WORKER_NORMAL_DAMAGE_BASE, WORKER_PLANAR_DAMAGE_BASE
end

local function RemoveWorkerCombatPatch(inst)
    local combat = inst.components ~= nil and inst.components.combat or nil
    if combat == nil then
        return
    end

    if inst._feast_worker_onattackother ~= nil then
        inst:RemoveEventCallback("onattackother", inst._feast_worker_onattackother)
        inst._feast_worker_onattackother = nil
    end
    if inst._feast_worker_onhitother ~= nil then
        inst:RemoveEventCallback("onhitother", inst._feast_worker_onhitother)
        inst._feast_worker_onhitother = nil
    end

    if combat._shadow_stalker_feast_worker_patched then
        combat.customdamagemultfn = inst._feast_worker_old_customdamagemultfn
        inst._feast_worker_old_customdamagemultfn = nil
        combat._shadow_stalker_feast_worker_patched = nil
    end

    if inst.components.planardamage ~= nil then
        inst.components.planardamage:SetBaseDamage(WORKER_PLANAR_DAMAGE_DEFAULT)
    end

    inst._feast_worker_damage_mult = nil
    inst._feast_worker_planar = nil
    inst._feast_worker_planar_active = nil
end

local function ApplyWorkerCombatPatch(inst, owner)
    local combat = inst.components ~= nil and inst.components.combat or nil
    if combat == nil or combat._shadow_stalker_feast_worker_patched then
        return
    end

    local normal_dmg, planar_dmg = GetWorkerNormalAttackDamage(owner)
    inst._feast_worker_damage_mult = normal_dmg / WORKER_NORMAL_DAMAGE_DEFAULT
    inst._feast_worker_planar = planar_dmg

    combat._shadow_stalker_feast_worker_patched = true
    inst._feast_worker_old_customdamagemultfn = combat.customdamagemultfn

    inst._feast_worker_onattackother = function(attacker)
        if not IsFeastDuelistNormalAttack(inst) then
            return
        end
        if attacker.components.planardamage ~= nil then
            attacker.components.planardamage:SetBaseDamage(attacker._feast_worker_planar or WORKER_PLANAR_DAMAGE_BASE)
            attacker._feast_worker_planar_active = true
        end
    end
    inst:ListenForEvent("onattackother", inst._feast_worker_onattackother)

    inst._feast_worker_onhitother = function(attacker)
        if attacker._feast_worker_planar_active and attacker.components.planardamage ~= nil then
            attacker.components.planardamage:SetBaseDamage(WORKER_PLANAR_DAMAGE_DEFAULT)
            attacker._feast_worker_planar_active = nil
        end
    end
    inst:ListenForEvent("onhitother", inst._feast_worker_onhitother)

    combat.customdamagemultfn = function(attacker, target, weapon, multiplier, mount)
        local mult = inst._feast_worker_old_customdamagemultfn ~= nil
            and inst._feast_worker_old_customdamagemultfn(attacker, target, weapon, multiplier, mount)
            or multiplier

        if attacker ~= inst or not IsFeastDuelistNormalAttack(inst) then
            return mult
        end

        return mult * (inst._feast_worker_damage_mult or 1)
    end
end

local function HasWorkerBuff(inst)
    return FeastBuff.GetFeastBuffType(inst) == FeastBuff.TYPES.WORKER
end

local function HasTirelessServant2(owner)
    return owner ~= nil and TirelessServant.IsTirelessServant2Active(owner)
end

function M.RemoveAll(inst)
    if inst == nil then
        return
    end

    require("skill_effect/waxwell/emperor/shadow_stalker/spikes").ClearAll(inst)
    FeastLanternMC.ClearAll(inst)
    RemoveDuelistCombatPatch(inst)
    RemoveWorkerCombatPatch(inst)
    RemoveWorkerSpeed(inst)
    inst._feast_lantern_mc_chain_immediate = nil
end

local function ApplyDuelist(inst, owner)
    ApplyDuelistCombatPatch(inst, owner)
    ApplyDuelistAbsorb(inst, owner)
end

function M.HasDuelistBuff(inst)
    return FeastBuff.GetFeastBuffType(inst) == FeastBuff.TYPES.DUELIST
end

-- While Duelist is active, MC + snare are disabled (attack + spike + channelers style).
function M.IsDuelistCrowdControlBlocked(inst)
    return M.HasDuelistBuff(inst)
end

local function ApplyWorker(inst, owner)
    if inst.components ~= nil and inst.components.locomotor ~= nil then
        inst.components.locomotor:SetExternalSpeedMultiplier(inst, WORKER_SPEED_KEY, GetWorkerSpeedMultiplier(owner))
    end
    ApplyWorkerCombatPatch(inst, owner)
end

local function ApplyLantern(inst)
    if inst.components.timer ~= nil then
        inst.components.timer:StopTimer("mindcontrol_cd")
    end

    if inst.HasMindControlTarget ~= nil and inst:HasMindControlTarget() then
        inst._feast_lantern_mc_chain_immediate = true
        inst:DoTaskInTime(0, function()
            if not inst:IsValid() or not M.HasLanternMcUpgrade(inst) then
                return
            end

            if inst.components.timer ~= nil then
                inst.components.timer:StopTimer(SHADOW_STALKER_SKILL_DELAY_TIMER)
                inst.components.timer:StopTimer("mindcontrol_cd")
            end
        end)
    end
end

function M.Apply(inst, bufftype)
    if inst == nil or not TheWorld.ismastersim then
        return
    end

    M.RemoveAll(inst)

    local owner = GetSpellOwner(inst)
    if bufftype == FeastBuff.TYPES.DUELIST then
        ApplyDuelist(inst, owner)
    elseif bufftype == FeastBuff.TYPES.WORKER then
        ApplyWorker(inst, owner)
    elseif bufftype == FeastBuff.TYPES.LANTERN then
        ApplyLantern(inst)
    end
end

function M.GetModifiedAbilityCooldown(inst, ability, base)
    if inst == nil or base == nil or base <= 0 or ability == "feast" or not HasWorkerBuff(inst) then
        return base
    end

    local owner = GetSpellOwner(inst)
    local reduction = GetWorkerCooldownReduction(owner)
    return math.max(0, base - reduction)
end

function M.OnAbilityCooldownApplied(inst, ability)
    if inst == nil
        or not TheWorld.ismastersim
        or ability == nil
        or ability == "feast"
        or inst.components.timer == nil
        or not HasWorkerBuff(inst) then
        return
    end

    local owner = GetSpellOwner(inst)
    if not HasTirelessServant2(owner) or math.random() >= WORKER_TS2_CD_RESET_CHANCE then
        return
    end

    inst.components.timer:StopTimer(ability.."_cd")
end

function M.GetSnareMaxTargets(inst, base)
    if FeastBuff.GetFeastBuffType(inst) ~= FeastBuff.TYPES.MARKSMAN then
        return base
    end

    local owner = GetSpellOwner(inst)
    if owner ~= nil and ShadowMarksman.IsShadowMarksman2Active(owner) then
        return MARKSMAN_SNARE_MAX_LV2
    end
    if owner ~= nil and ShadowMarksman.IsShadowMarksmanSkillActive(owner) then
        return MARKSMAN_SNARE_MAX_LV1
    end

    return base
end

function M.GetSnareDuration(inst, base)
    if FeastBuff.GetFeastBuffType(inst) ~= FeastBuff.TYPES.MARKSMAN then
        return base
    end

    local owner = GetSpellOwner(inst)
    if owner ~= nil and ShadowMarksman.IsShadowMarksman2Active(owner) then
        return MARKSMAN_SNARE_DURATION_LV2
    end
    if owner ~= nil and ShadowMarksman.IsShadowMarksmanSkillActive(owner) then
        return MARKSMAN_SNARE_DURATION_LV1
    end

    return base
end

local function HasMarksmanBuff(inst)
    return FeastBuff.GetFeastBuffType(inst) == FeastBuff.TYPES.MARKSMAN
end

function M.GetSpikeDamage(inst)
    if not HasMarksmanBuff(inst) then
        return SPIKE_DAMAGE
    end

    local owner = GetSpellOwner(inst)
    if owner ~= nil and ShadowMarksman.IsShadowMarksman2Active(owner) then
        return SPIKE_DAMAGE_MARKSMAN_LV2
    end
    if owner ~= nil and ShadowMarksman.IsShadowMarksmanSkillActive(owner) then
        return SPIKE_DAMAGE_MARKSMAN_LV1
    end

    return SPIKE_DAMAGE
end

function M.GetSpikePlanarDamage(inst)
    if not HasMarksmanBuff(inst) then
        return SPIKE_PLANAR_DAMAGE
    end

    local owner = GetSpellOwner(inst)
    if owner ~= nil and ShadowMarksman.IsShadowMarksman2Active(owner) then
        return SPIKE_PLANAR_MARKSMAN_LV2
    end
    if owner ~= nil and ShadowMarksman.IsShadowMarksmanSkillActive(owner) then
        return SPIKE_PLANAR_MARKSMAN_LV1
    end

    return SPIKE_PLANAR_DAMAGE
end

function M.GetSpikeScale(inst)
    if not HasMarksmanBuff(inst) then
        return SPIKE_SCALE_BASE
    end

    local owner = GetSpellOwner(inst)
    if owner ~= nil and ShadowMarksman.IsShadowMarksman2Active(owner) then
        return SPIKE_SCALE_MARKSMAN_LV2
    end
    if owner ~= nil and ShadowMarksman.IsShadowMarksmanSkillActive(owner) then
        return SPIKE_SCALE_MARKSMAN_LV1
    end

    return SPIKE_SCALE_BASE
end

function M.GetSpikesPerCast(inst)
    if not HasMarksmanBuff(inst) then
        return SPIKE_COUNT_BASE
    end

    local owner = GetSpellOwner(inst)
    if owner ~= nil and ShadowMarksman.IsShadowMarksman2Active(owner) then
        return SPIKE_COUNT_MARKSMAN_LV2
    end
    if owner ~= nil and ShadowMarksman.IsShadowMarksmanSkillActive(owner) then
        return SPIKE_COUNT_MARKSMAN_LV1
    end

    return SPIKE_COUNT_BASE
end

function M.HasLanternMcUpgrade(inst)
    return inst ~= nil and FeastBuff.GetFeastBuffType(inst) == FeastBuff.TYPES.LANTERN
end

function M.WantsImmediateLanternMcChain(inst)
    return inst ~= nil and inst._feast_lantern_mc_chain_immediate == true
end

function M.ClearImmediateLanternMcChain(inst)
    if inst ~= nil then
        inst._feast_lantern_mc_chain_immediate = nil
    end
end

-- Back-compat aliases for older call sites.
M.WantsImmediateLanternMcUpgrade = M.WantsImmediateLanternMcChain
M.ClearImmediateLanternMcUpgrade = M.ClearImmediateLanternMcChain

return M
