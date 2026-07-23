local assets =
{
    Asset("ANIM", "anim/stalker/stalker_basic.zip"),
    Asset("ANIM", "anim/stalker/stalker_action.zip"),
    Asset("ANIM", "anim/stalker/stalker_shadow_build.zip"),
    Asset("ANIM", "anim/stalker/stalker_cave_build.zip"),
    Asset("ANIM", "anim/stalker/fossil_stalker.zip"),
    Asset("ANIM", "anim/stalker/stalker_shield.zip"),
}

local prefabs =
{
    "shadow_despawn",
    "shadow_stalker_fossilspike",
    "shadow_stalker_fossilspike2",
    "blinkfocus_marker",
}

local brain = require("brains/waxwell/shadow_stalkerbrain")
require("stategraphs/waxwell/SGshadow_stalker")
local targeting_rules = require("skill_effect/_shared/targeting_rules")
local SHADOW_STALKER_ACTIVE_TAG = "shadow_stalker_spell_active"

local emperor_common = require("skill_effect/waxwell/emperor/_shared/common")
local RestartSpellCooldown = emperor_common.RestartSpellCooldown
local PushEmperorSpellRefresh = emperor_common.PushEmperorSpellRefresh
local FeastBuff = require("skill_effect/waxwell/emperor/shadow_stalker/feast_buff")
local FeastBuffEffects = require("skill_effect/waxwell/emperor/shadow_stalker/feast_buff_effects")
local ShadowStalkerSpikes = require("skill_effect/waxwell/emperor/shadow_stalker/spikes")
local Abilities = require("skill_effect/waxwell/emperor/shadow_stalker/abilities")
local ShadowCreatureTargets = require("skill_effect/waxwell/sovereign/_shared/shadow_creature_targets")

local WORK_RADIUS = Abilities.WORK_RADIUS
local TARGET_LOCK_TIME = 1.5
local LEADER_HIT_MEMORY = 4
local SHADOW_TINT_ALPHA = .75
local SHADOW_STALKER_MINDCONTROL_CD = Abilities.MINDCONTROL_CD
local SHADOW_STALKER_SNARE_CD = Abilities.SNARE_CD
local SHADOW_STALKER_SPIKES_CD = Abilities.SPIKES_CD
local SHADOW_STALKER_CHANNELERS_CD = Abilities.CHANNELERS_CD
local SHADOW_STALKER_SKILL_DELAY = Abilities.SKILL_DELAY
local SHADOW_STALKER_SKILL_DELAY_TIMER = "skill_delay_cd"
local SHADOW_STALKER_ABILITY_MISS_RETRY = Abilities.ABILITY_MISS_RETRY
local SHADOW_STALKER_CHANNELERS_DURATION = Abilities.CHANNELERS_DURATION
local SHADOW_STALKER_CHANNELERS_HITS = Abilities.CHANNELERS_HITS
local SHADOW_STALKER_CHANNELERS_ABSORB = Abilities.CHANNELERS_ABSORB
local SHADOW_STALKER_CHANNELERS_REFLECT = Abilities.CHANNELERS_REFLECT
local SHADOW_STALKER_NORMAL_DAMAGE = Abilities.NORMAL_DAMAGE
local SHADOW_STALKER_PLANAR_DAMAGE = Abilities.PLANAR_DAMAGE
local SHADOW_STALKER_VS_LUNAR_BONUS = Abilities.VS_LUNAR_BONUS
local SHADOW_STALKER_PLANAR_DEFENSE = Abilities.PLANAR_DEFENSE
local SHADOW_STALKER_VS_SHADOW_RESIST = Abilities.VS_SHADOW_RESIST
local SHADOW_STALKER_CHANNELERS_DURATION_TIMER = "shadow_stalker_channelers_duration"
local SHADOW_STALKER_CHANNELERS_ABSORB_KEY = "shadow_stalker_channelers"
local SHADOW_STALKER_LANTERN_MC_WARD_ABSORB_KEY = "shadow_stalker_lantern_mc_ward"
local SHADOW_STALKER_FEAST_CD = Abilities.FEAST_CD
local SHADOW_STALKER_FEAST_SC_HEAL_PERCENT = Abilities.FEAST_SC_HEAL_PERCENT
local SHADOW_STALKER_FEAST_SUMMON_HEAL_PERCENT = Abilities.FEAST_SUMMON_HEAL_PERCENT
local SHADOW_STALKER_FEAST_SC_LOW_HEALTH_PERCENT = Abilities.FEAST_SC_LOW_HEALTH_PERCENT
local SHADOW_STALKER_FEAST_EAT_RANGE = Abilities.FEAST_EAT_RANGE
local SHADOW_STALKER_FEAST_RETRY_CD = Abilities.FEAST_RETRY_CD
local SHADOW_STALKER_FEAST_SPEEDMULT_KEY = "shadow_stalker_feast"
local SHADOW_STALKER_FEAST_SPEEDMULT = Abilities.FEAST_SPEEDMULT
local SHADOW_STALKER_MC_REPOSITION_SPEEDMULT_KEY = "shadow_stalker_mc_reposition"
local SHADOW_STALKER_MC_REPOSITION_SPEEDMULT = Abilities.MC_REPOSITION_SPEEDMULT
local SHADOW_STALKER_MC_REPOSITION_ARRIVE_DIST = Abilities.MC_REPOSITION_ARRIVE_DIST
local SHADOW_STALKER_SNARE_MAX_TARGETS = Abilities.SNARE_MAX_TARGETS
local SHADOW_STALKER_SNARE_DURATION = Abilities.SNARE_DURATION
local SHADOW_STALKER_LIFETIME_TIMER = "shadow_stalker_lifetime"
local SHADOW_STALKER_LIFETIME = TUNING.SEG_TIME * 8

local function SaveSpawnPoint(inst, dont_overwrite)
    local knownlocations = inst.components.knownlocations
    local entitytracker = inst.components.entitytracker
    if knownlocations == nil or entitytracker == nil then
        return
    end

    if not dont_overwrite
        or (knownlocations:GetLocation("spawn") == nil and knownlocations:GetLocation("spawnplatform") == nil) then
        local x, y, z = inst.Transform:GetWorldPosition()
        local platform = TheWorld.Map:GetPlatformAtPoint(x, z)
        if platform ~= nil then
            x, y, z = platform.entity:WorldToLocalSpace(x, 0, z)
            knownlocations:ForgetLocation("spawn")
            knownlocations:RememberLocation("spawnplatform", Vector3(x, 0, z))
            entitytracker:TrackEntity("spawnplatform", platform)
        else
            entitytracker:ForgetEntity("spawnplatform")
            knownlocations:ForgetLocation("spawnplatform")
            knownlocations:RememberLocation("spawn", Vector3(x, 0, z))
        end
    end
end

local RETARGET_MUST_TAGS = { "_combat", "_health" }
local RETARGET_CANT_TAGS =
{
    "INLIMBO",
    "player",
    "playerghost",
    "companion",
    "shadowminion",
    "stalkerminion",
    "shadow",
    "shadowcreature",
    "shadowchesspiece",
    "notarget",
    "invisible",
    "noattack",
}

local AOE_TARGET_CANT_TAGS = { "INLIMBO", "notarget", "invisible", "noattack", "flight", "playerghost", "shadow", "shadowchesspiece", "shadowcreature" }

local function GetBaseAbilityCooldown(ability)
    if ability == "mindcontrol" then
        return SHADOW_STALKER_MINDCONTROL_CD
    elseif ability == "snare" then
        return SHADOW_STALKER_SNARE_CD
    elseif ability == "spikes" then
        return SHADOW_STALKER_SPIKES_CD
    elseif ability == "channelers" then
        return SHADOW_STALKER_CHANNELERS_CD
    elseif ability == "feast" then
        return SHADOW_STALKER_FEAST_CD
    end
    return 0
end

local function GetAbilityCooldown(inst, ability)
    return FeastBuffEffects.GetModifiedAbilityCooldown(inst, ability, GetBaseAbilityCooldown(ability))
end

local function ApplyAbilityCooldown(inst, ability)
    if inst.components.timer == nil or ability == nil then
        return
    end

    local cooldown = GetAbilityCooldown(inst, ability)
    if cooldown > 0 then
        inst.components.timer:StopTimer(ability.."_cd")
        inst.components.timer:StartTimer(ability.."_cd", cooldown)
    end

    inst.components.timer:StopTimer(SHADOW_STALKER_SKILL_DELAY_TIMER)
    inst.components.timer:StartTimer(SHADOW_STALKER_SKILL_DELAY_TIMER, SHADOW_STALKER_SKILL_DELAY)
    FeastBuffEffects.OnAbilityCooldownApplied(inst, ability)
end

local ResetAbilityCooldown = ApplyAbilityCooldown

local function IsSkillDelayActive(inst)
    return inst.components.timer ~= nil
        and inst.components.timer:TimerExists(SHADOW_STALKER_SKILL_DELAY_TIMER)
end

local function HasPlayerLeader(target)
    if target.components.follower == nil then
        return false
    end

    local leader = target.components.follower:GetLeader()
    if leader ~= nil and leader.components.inventoryitem ~= nil then
        leader = leader.components.inventoryitem:GetGrandOwner()
    end

    return leader ~= nil and leader:HasTag("player")
end

local function IsShadowNonCombatTarget(target)
    if target == nil then
        return false
    end

    return target:HasTag("shadow")
        or target:HasTag("shadowminion")
        or target:HasTag("shadowcreature")
        or target:HasTag("shadowchesspiece")
        or target:HasTag("stalkerminion")
        or (target.prefab ~= nil and string.find(target.prefab, "shadowwaxwell", 1, true) ~= nil)
end

local function IsProtectedNonTarget(target)
    if target == nil then
        return true
    end

    return target:HasTag("player")
        or target:HasTag("playerghost")
        or target:HasTag("companion")
        or IsShadowNonCombatTarget(target)
        or HasPlayerLeader(target)
        or (target.prefab ~= nil and string.find(target.prefab, "chester", 1, true) ~= nil)
        or (target.prefab ~= nil and string.find(target.prefab, "glommer", 1, true) ~= nil)
end

local function CanAreaHitTarget(target, attacker)
    return targeting_rules.IsEntityAllowed(target,
    {
        name = "shadow_stalker_aoe",
        blacklist_tags = AOE_TARGET_CANT_TAGS,
        extra_check = function(ent)
            return ent ~= attacker
                and ent.components.health ~= nil
                and not ent.components.health:IsDead()
                and not IsProtectedNonTarget(ent)
        end,
    })
end

local function GetPlayerOwner(source)
    if source == nil then
        return nil
    end

    if source.isplayer then
        return source
    end

    if source.components.inventoryitem ~= nil then
        local owner = source.components.inventoryitem:GetGrandOwner()
        if owner ~= nil and owner.isplayer then
            return owner
        end
    end

    if source.components.follower ~= nil then
        local leader = source.components.follower:GetLeader()
        if leader ~= nil and leader.isplayer then
            return leader
        end
    end

    if source.owner ~= nil and source.owner.isplayer then
        return source.owner
    end

    if source.attacker ~= nil and source.attacker.isplayer then
        return source.attacker
    end

    return nil
end

local function IsLeaderDamageSource(inst, source)
    local leader = inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
    local owner = GetPlayerOwner(source)
    return leader ~= nil and owner == leader
end

local function HasSamePlayerLeader(inst, target)
    if inst == nil or target == nil or target.components.follower == nil then
        return false
    end

    local myleader = inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
    local targetleader = target.components.follower:GetLeader()
    if targetleader ~= nil and targetleader.components.inventoryitem ~= nil then
        targetleader = targetleader.components.inventoryitem:GetGrandOwner()
    end
    return myleader ~= nil and myleader == targetleader
end

local function ShouldIgnoreFriendlyAttacker(inst, attacker)
    return attacker ~= nil and (
        attacker:HasTag("shadowminion")
        or attacker:HasTag("companion")
        or HasSamePlayerLeader(inst, attacker)
    )
end

local function IsPlayerDamageSource(source)
    return GetPlayerOwner(source) ~= nil
end

local function environmentaldamageredirect(inst, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
    if afflicter == nil then
        return true
    end

    return IsPlayerDamageSource(afflicter) or afflicter:HasTag("quakedebris")
end

local function EnsureWorkCenter(inst)
    if inst._workcenter == nil then
        local x, y, z = inst.Transform:GetWorldPosition()
        inst._workcenter = Vector3(x, y, z)
    end
    return inst._workcenter
end

local function GetWorkPosition(inst)
    local center = EnsureWorkCenter(inst)
    return center.x, center.y, center.z
end

local function IsPointInWorkArea(inst, x, z, padding)
    local center = EnsureWorkCenter(inst)
    local radius = (inst._workradius or WORK_RADIUS) + (padding or 0)
    local dx = x - center.x
    local dz = z - center.z
    return dx * dx + dz * dz <= radius * radius
end

local function IsPointInWorkAreaProxy(inst, x, z, padding)
    return IsPointInWorkArea(inst, x, z, padding)
end

local function IsInWorkArea(inst, target, padding)
    if target == nil then
        return false
    end
    local x, _, z = target.Transform:GetWorldPosition()
    return IsPointInWorkArea(inst, x, z, padding)
end

local PASSIVE_ANIMAL_PREFABS =
{
    bee = true,
    butterfly = true,
    rabbit = true,
    mole = true,
    molehill = true,
    catcoon = true,
    crow = true,
    robin = true,
    robin_winter = true,
    puffin = true,
    canary = true,
    penguin = true,
    pengull = true,
    perd = true,
    lightflier = true,
    glowfly = true,
    fruitfly = true,
    gnat = true,
    grassgator = true,
    moonpig = true,
    koalefant_summer = true,
    koalefant_winter = true,
    rabbitkinghorn = true,
    tallbird = false,
    beequeen = false,
    killerbee = false,
    frog = false,
    mosquito = false,
    bat = false,
    molebat = false,
    slurtle = false,
    snurtle = false,
}

local function IsPlayerRelatedTarget(inst, target)
    if target == nil or target.components.combat == nil then
        return false
    end

    local combat_target = target.components.combat.target
    if combat_target == nil then
        return false
    end

    local leader = inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
    return combat_target == inst
        or combat_target == leader
        or combat_target:HasTag("player")
        or HasPlayerLeader(combat_target)
end

local function IsPassiveAnimal(target)
    if target == nil then
        return false
    end

    if PASSIVE_ANIMAL_PREFABS[target.prefab] ~= nil then
        return PASSIVE_ANIMAL_PREFABS[target.prefab]
    end

    return (target:HasTag("bird")
        or target:HasTag("smallcreature")
        or target:HasTag("prey")
        or (target:HasTag("animal") and not target:HasTag("hostile") and not target:HasTag("monster")))
end

local function IsNaturallyHostileTarget(target)
    return target ~= nil and (
        target:HasTag("monster")
        or target:HasTag("hostile")
        or target:HasTag("scarytoprey")
    )
end

local function IsValidEnemy(inst, target)
    return targeting_rules.IsEntityAllowed(target,
    {
        name = "shadow_stalker_enemy",
        must_tags = RETARGET_MUST_TAGS,
        blacklist_tags = RETARGET_CANT_TAGS,
        extra_check = function(ent)
            return ent ~= inst
                and ent.entity:IsVisible()
                and ent.components.health ~= nil
                and not ent.components.health:IsDead()
                and ent.components.combat ~= nil
                and not IsProtectedNonTarget(ent)
                and (
                    IsNaturallyHostileTarget(ent)
                    or IsPlayerRelatedTarget(inst, ent)
                    or (not IsPassiveAnimal(ent) and ent.components.combat.target == inst)
                )
                and inst.components.combat:CanTarget(ent)
                and IsInWorkArea(inst, ent, ent:GetPhysicsRadius(0))
        end,
    })
end

local function RefreshTargetLock(inst, target)
    if target ~= nil then
        inst._targetlock_target = target
        inst._targetlock_time = GetTime() + TARGET_LOCK_TIME
    end
end

local function ApplyShadowTintToAnimTarget(target)
    if target ~= nil and target.AnimState ~= nil then
        target.AnimState:SetMultColour(0, 0, 0, SHADOW_TINT_ALPHA)
    end
end

local function ApplyShadowTintToSpikeEffects(spike)
    if spike == nil then
        return
    end

    ApplyShadowTintToAnimTarget(spike)
    if spike.AnimState ~= nil then
        spike.AnimState:SetLightOverride(0)
    end

    if spike.basefx ~= nil then
        ApplyShadowTintToAnimTarget(spike.basefx)
    end
end

local function DeactivateShadowWard(inst)
    if inst.components.health ~= nil and inst.components.health.externalabsorbmodifiers ~= nil then
        inst.components.health.externalabsorbmodifiers:RemoveModifier(inst, SHADOW_STALKER_CHANNELERS_ABSORB_KEY)
    end
    if inst.components.timer ~= nil then
        inst.components.timer:StopTimer(SHADOW_STALKER_CHANNELERS_DURATION_TIMER)
    end

    if inst._feast_lantern_mc_ward then
        inst.hasshield = true
        inst._shadowward_hitsleft = nil
        return
    end

    inst.hasshield = false
    inst._shadowward_hitsleft = nil
end

local function ClearFeastSpeed(inst)
    if inst.components.locomotor ~= nil then
        inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, SHADOW_STALKER_FEAST_SPEEDMULT_KEY)
    end
end

local function ApplyFeastSpeed(inst)
    if inst.components.locomotor ~= nil then
        inst.components.locomotor:SetExternalSpeedMultiplier(inst, SHADOW_STALKER_FEAST_SPEEDMULT_KEY, SHADOW_STALKER_FEAST_SPEEDMULT)
    end
end

local function ApplyMindControlRepositionSpeed(inst)
    if inst.components.locomotor ~= nil then
        inst.components.locomotor:SetExternalSpeedMultiplier(inst, SHADOW_STALKER_MC_REPOSITION_SPEEDMULT_KEY, SHADOW_STALKER_MC_REPOSITION_SPEEDMULT)
    end
end

local function ClearMindControlRepositionSpeed(inst)
    if inst.components.locomotor ~= nil then
        inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, SHADOW_STALKER_MC_REPOSITION_SPEEDMULT_KEY)
    end
end

local function IsAtWorkCenter(inst, padding)
    local center = EnsureWorkCenter(inst)
    local x, _, z = inst.Transform:GetWorldPosition()
    local dx = x - center.x
    local dz = z - center.z
    local radius = (padding or SHADOW_STALKER_MC_REPOSITION_ARRIVE_DIST)
    return dx * dx + dz * dz <= radius * radius
end

local function GetMindControlRange(inst)
    return inst._workradius or WORK_RADIUS
end

local function ActivateShadowWard(inst)
    ResetAbilityCooldown(inst, "channelers")
    inst.hasshield = true
    inst._shadowward_hitsleft = SHADOW_STALKER_CHANNELERS_HITS
    if inst.components.health ~= nil and inst.components.health.externalabsorbmodifiers ~= nil then
        inst.components.health.externalabsorbmodifiers:SetModifier(inst, SHADOW_STALKER_CHANNELERS_ABSORB, SHADOW_STALKER_CHANNELERS_ABSORB_KEY)
    end
    inst.components.timer:StopTimer(SHADOW_STALKER_CHANNELERS_DURATION_TIMER)
    inst.components.timer:StartTimer(SHADOW_STALKER_CHANNELERS_DURATION_TIMER, SHADOW_STALKER_CHANNELERS_DURATION)
end

local function ReflectShadowWardDamage(inst, attacker, data)
    if attacker == nil or attacker.components.health == nil or attacker.components.health:IsDead() then
        return
    end

    local ward_active = inst._feast_lantern_mc_ward
        or (inst.components.timer ~= nil
            and inst.components.timer:TimerExists(SHADOW_STALKER_CHANNELERS_DURATION_TIMER))
    if not ward_active then
        return
    end

    local reflected = math.max(data.damageresolved or data.damage or 0, 0) * SHADOW_STALKER_CHANNELERS_REFLECT
    if reflected > 0 and attacker.components.combat ~= nil and attacker.components.combat:CanTarget(inst) then
        attacker.components.combat:GetAttacked(inst, reflected)
    end
end

local function ConsumeShadowWardHit(inst)
    if inst._feast_lantern_mc_ward then
        return
    end

    if not inst.hasshield then
        return
    end

    inst._shadowward_hitsleft = math.max((inst._shadowward_hitsleft or SHADOW_STALKER_CHANNELERS_HITS) - 1, 0)
    if inst._shadowward_hitsleft <= 0 then
        DeactivateShadowWard(inst)
    end
end

local function ActivateLanternFeastWard(inst)
    if inst._feast_lantern_mc_ward then
        return
    end

    inst._feast_lantern_mc_ward = true
    inst.hasshield = true
    inst._shadowward_hitsleft = nil
    if inst.components.health ~= nil and inst.components.health.externalabsorbmodifiers ~= nil then
        inst.components.health.externalabsorbmodifiers:SetModifier(
            inst,
            SHADOW_STALKER_CHANNELERS_ABSORB,
            SHADOW_STALKER_LANTERN_MC_WARD_ABSORB_KEY
        )
    end
end

local function DeactivateLanternFeastWard(inst)
    inst._feast_lantern_mc_ward = false
    if inst.components.health ~= nil and inst.components.health.externalabsorbmodifiers ~= nil then
        inst.components.health.externalabsorbmodifiers:RemoveModifier(inst, SHADOW_STALKER_LANTERN_MC_WARD_ABSORB_KEY)
    end

    if inst.components.timer ~= nil
        and inst.components.timer:TimerExists(SHADOW_STALKER_CHANNELERS_DURATION_TIMER) then
        inst.hasshield = true
        inst._shadowward_hitsleft = SHADOW_STALKER_CHANNELERS_HITS
        return
    end

    inst.hasshield = false
    inst._shadowward_hitsleft = nil
end

local function BeginShadowStalkerSpellDeactivate(inst)
    if inst._shadow_stalker_spell_ended_notified then
        return
    end

    inst._shadow_stalker_spell_ended_notified = true
    inst._shadow_stalker_spell_deactivating = true
    inst._shadow_stalker_spell_active = false
    if inst:HasTag(SHADOW_STALKER_ACTIVE_TAG) then
        inst:RemoveTag(SHADOW_STALKER_ACTIVE_TAG)
    end

    local owner = inst._shadow_stalker_spell_owner
    if (owner == nil or not owner:IsValid()) and inst._shadow_stalker_spell_owner_userid ~= nil then
        for _, player in ipairs(AllPlayers) do
            if player ~= nil and player:IsValid() and player.userid == inst._shadow_stalker_spell_owner_userid then
                owner = player
                inst._shadow_stalker_spell_owner = player
                break
            end
        end
    end

    if owner ~= nil then
        PushEmperorSpellRefresh(owner)
    end
end

local function GetPriorityTargetFromSelf(inst)
    local attacker = inst._recentattacker
    return attacker ~= nil and attacker:IsValid() and IsValidEnemy(inst, attacker) and attacker or nil
end

local function GetPriorityTargetFromLeader(inst)
    local leader = inst.components.follower:GetLeader()
    if leader ~= nil and leader.components.combat ~= nil then
        local attacker = leader.components.combat.lastattacker
        if attacker ~= nil
            and leader.components.combat:GetLastAttackedTime() + LEADER_HIT_MEMORY > GetTime()
            and IsValidEnemy(inst, attacker) then
            return attacker
        end
    end
    return nil
end

local function FindNearestToLeader(inst)
    local leader = inst.components.follower:GetLeader()
    if leader == nil then
        return nil
    end

    local lx, ly, lz = leader.Transform:GetWorldPosition()
    return FindEntity(
        leader,
        inst._workradius or WORK_RADIUS,
        function(guy)
            return IsValidEnemy(inst, guy)
        end,
        RETARGET_MUST_TAGS,
        RETARGET_CANT_TAGS
    )
end

local function FindAnyTargetInWorkArea(inst)
    local center = EnsureWorkCenter(inst)
    local ents = TheSim:FindEntities(center.x, center.y, center.z, inst._workradius or WORK_RADIUS, RETARGET_MUST_TAGS, RETARGET_CANT_TAGS)
    for _, guy in ipairs(ents) do
        if IsValidEnemy(inst, guy) then
            return guy
        end
    end
    return nil
end

local function retargetfn(inst)
    local target = GetPriorityTargetFromSelf(inst)
        or GetPriorityTargetFromLeader(inst)
        or FindNearestToLeader(inst)
        or FindAnyTargetInWorkArea(inst)

    if target ~= nil then
        RefreshTargetLock(inst, target)
    end

    return target
end

local function keeptargetfn(inst, target)
    return target ~= nil
        and (
            (inst._targetlock_target == target and (inst._targetlock_time or 0) > GetTime())
            or inst.components.follower:IsNearLeader(14)
            or target:IsNear(inst, TUNING.STALKER_KEEP_AGGRO_DIST)
        )
        and inst.components.combat:CanTarget(target)
        and target.components.minigame_participator == nil
        and IsInWorkArea(inst, target, target:GetPhysicsRadius(0))
end

local function IsPlayerDeadOrGhost(player)
    return player == nil
        or not player:IsValid()
        or player:HasTag("playerghost")
        or (player.components.health ~= nil and player.components.health:IsDead())
end

local function IsDespawning(inst)
    if inst._force_despawn or inst._shadow_stalker_despawn_pending then
        return true
    end
    if inst.sg ~= nil then
        local state = inst.sg.currentstate
        if state ~= nil and (state.name == "despawn" or state.name == "quickdespawn" or inst.sg:HasStateTag("dead")) then
            return true
        end
    end
    return false
end

local function StopShadowStalkerAI(inst)
    if inst.brain ~= nil then
        inst.brain:Stop()
    end
    if inst.components.locomotor ~= nil then
        inst.components.locomotor:Stop()
    end
    if inst.components.combat ~= nil then
        inst.components.combat:SetTarget(nil)
        inst.components.combat:DropTarget()
    end
end

local function ForceDespawn(inst)
    if inst == nil or not inst:IsValid() or IsDespawning(inst) then
        return
    end

    inst._shadow_stalker_despawn_pending = true
    StopShadowStalkerAI(inst)

    if inst._shadow_stalker_spell_active or inst._shadow_stalker_spell_spawning then
        BeginShadowStalkerSpellDeactivate(inst)
    end
    if TheWorld.ismastersim and inst._shadow_stalker_spell_owner ~= nil then
        RestartSpellCooldown(inst._shadow_stalker_spell_owner, emperor_common.SHADOW_STALKER_COOLDOWN_ID, emperor_common.SHADOW_STALKER_COOLDOWN_TIME)
        PushEmperorSpellRefresh(inst._shadow_stalker_spell_owner)
    end
    inst._force_despawn = true
    if inst.sg ~= nil then
        inst.sg:GoToState("despawn")
    else
        inst:Remove()
    end
end

local function RequestSpellDeactivate(inst)
    if inst == nil or not inst:IsValid() then
        return
    end

    if inst._shadow_stalker_spell_spawning or inst._shadow_stalker_spell_deactivating then
        return
    end

    BeginShadowStalkerSpellDeactivate(inst)
    inst._force_despawn = true
    if inst.sg ~= nil then
        inst.sg:GoToState("despawn")
    else
        inst:Remove()
    end
end

local function ShouldLeaderDespawn(inst, attacker)
    local leader = inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
    return leader ~= nil and leader.prefab == "waxwell" and attacker == leader
end

local function onattacked(inst, data)
    if data.attacker == nil then
        return
    end

    if ShouldIgnoreFriendlyAttacker(inst, data.attacker) then
        return
    end

    if ShouldLeaderDespawn(inst, data.attacker) then
        ForceDespawn(inst)
        return
    end

    if data.attacker.components.petleash ~= nil and data.attacker.components.petleash:IsPet(inst) then
        ForceDespawn(inst)
        return
    end

    if data.attacker.components.combat ~= nil and not data.attacker:HasTag("player") then
        inst._recentattacker = data.attacker
        inst._recentattackertime = GetTime()
        RefreshTargetLock(inst, data.attacker)
        inst.components.combat:SuggestTarget(data.attacker)
    end

    ReflectShadowWardDamage(inst, data.attacker, data)
    if (data.damageresolved or data.damage or 0) > 0 then
        ConsumeShadowWardHit(inst)
    end
end

local function onblocked(inst, data)
    if data.attacker ~= nil and ShouldIgnoreFriendlyAttacker(inst, data.attacker) then
        return
    end
    if data.attacker ~= nil and ShouldLeaderDespawn(inst, data.attacker) then
        ForceDespawn(inst)
    end
end

local function EnsureOwnerDeathListener(inst, owner)
    if owner == nil or not owner:IsValid() or inst._shadow_stalker_owner_death_listener == owner then
        return
    end

    if inst._shadow_stalker_owner_death_listener ~= nil and inst._shadow_stalker_owner_death_listener:IsValid() then
        inst:RemoveEventCallback("death", inst._shadow_stalker_on_owner_death, inst._shadow_stalker_owner_death_listener)
        inst:RemoveEventCallback("makeplayerghost", inst._shadow_stalker_on_owner_death, inst._shadow_stalker_owner_death_listener)
    end

    inst._shadow_stalker_owner_death_listener = owner
    inst._shadow_stalker_on_owner_death = function()
        ForceDespawn(inst)
    end
    inst:ListenForEvent("death", inst._shadow_stalker_on_owner_death, owner)
    inst:ListenForEvent("makeplayerghost", inst._shadow_stalker_on_owner_death, owner)
end

local function WatchLeaderState(inst)
    if inst.components.health == nil or inst.components.health:IsDead() or IsDespawning(inst) then
        return
    end

    local leader = inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
    local owner = inst._shadow_stalker_spell_owner

    if (owner == nil or not owner:IsValid()) and inst._shadow_stalker_spell_owner_userid ~= nil then
        for _, player in ipairs(AllPlayers) do
            if player ~= nil and player:IsValid() and player.userid == inst._shadow_stalker_spell_owner_userid then
                owner = player
                inst._shadow_stalker_spell_owner = player
                break
            end
        end
    end

    local trackedleader = owner or leader
    if trackedleader ~= nil and trackedleader:HasTag("player") then
        EnsureOwnerDeathListener(inst, trackedleader)
    end

    if trackedleader == nil and (inst._shadow_stalker_spell_active or inst._shadow_stalker_spell_spawning or inst._shadow_stalker_spell_deactivating) then
        ForceDespawn(inst)
        return
    end

    if IsPlayerDeadOrGhost(trackedleader) then
        ForceDespawn(inst)
    end
end

local function StartAbility(inst, ability)
    ApplyAbilityCooldown(inst, ability)
end

local function RestrictSpawnedSpikeDamage(spike, owner)
    if spike == nil or spike.components.combat == nil then
        return
    end

    local oldIsValidTarget = spike.components.combat.IsValidTarget
    spike.components.combat.playerdamagepercent = 0
    spike.components.combat.IsValidTarget = function(combat, target)
        return targeting_rules.IsEntityAllowed(target,
        {
            name = "shadow_stalker_spawned_spike",
            blacklist_tags = AOE_TARGET_CANT_TAGS,
            extra_check = function(ent)
                return ent ~= owner
                    and not IsProtectedNonTarget(ent)
                    and not ent:HasTag("stalkerminion")
                    and oldIsValidTarget(combat, ent)
            end,
        })
    end
end

local SNARE_OVERLAP_MIN = 1
local SNARE_OVERLAP_MAX = 3
local SNAREOVERLAP_TAGS = { "fossilspike", "groundspike" }
local SNARE_MAX_TARGETS = SHADOW_STALKER_SNARE_MAX_TARGETS
local SNARE_TAGS = { "_combat", "locomotor", "_health" }
local SNARE_NO_TAGS =
{
    "flying",
    "ghost",
    "playerghost",
    "tallbird",
    "fossil",
    "shadow",
    "shadowminion",
    "stalkerminion",
    "shadowcreature",
    "INLIMBO",
    "epic",
    "smallcreature",
    "player",
    "companion",
}

local function NoSnareOverlap(x, z, r)
    return #TheSim:FindEntities(x, 0, z, r or SNARE_OVERLAP_MIN, SNAREOVERLAP_TAGS) <= 0
end

local function IsValidSnareTarget(inst, target)
    return targeting_rules.IsEntityAllowed(target,
    {
        name = "shadow_stalker_snare",
        must_tags = SNARE_TAGS,
        blacklist_tags = SNARE_NO_TAGS,
        extra_check = function(ent)
            return ent.components.health ~= nil
                and not ent.components.health:IsDead()
                and ent.components.combat ~= nil
                and ent.components.locomotor ~= nil
                and not IsProtectedNonTarget(ent)
                and not ent:HasTag("largecreature")
                and not ent:HasTag("epic")
                and not ent:HasTag("smallepic")
                and inst.components.combat:CanTarget(ent)
                and inst:IsNear(ent, TUNING.STALKER_SNARE_RANGE)
                and IsInWorkArea(inst, ent, ent:GetPhysicsRadius(0))
        end,
    })
end

local function AddUniqueTarget(list, seen, target, validator)
    if target ~= nil and not seen[target] and validator(target) then
        seen[target] = true
        table.insert(list, target)
    end
end

local function FindSnareTargets(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local targets = {}
    local seen = {}

    AddUniqueTarget(targets, seen, inst.components.combat.target, function(guy) return IsValidSnareTarget(inst, guy) end)
    AddUniqueTarget(targets, seen, GetPriorityTargetFromSelf(inst), function(guy) return IsValidSnareTarget(inst, guy) end)
    AddUniqueTarget(targets, seen, GetPriorityTargetFromLeader(inst), function(guy) return IsValidSnareTarget(inst, guy) end)

    local anchor = inst.components.follower ~= nil and inst.components.follower:GetLeader() or inst
    if anchor == nil or not IsInWorkArea(inst, anchor) then
        anchor = inst
    end
    local ax, ay, az = anchor.Transform:GetWorldPosition()

    local ents = TheSim:FindEntities(x, y, z, TUNING.STALKER_SNARE_RANGE, SNARE_TAGS, SNARE_NO_TAGS)
    table.sort(ents, function(a, b)
        return a:GetDistanceSqToPoint(ax, ay, az) < b:GetDistanceSqToPoint(ax, ay, az)
    end)

    for _, guy in ipairs(ents) do
        AddUniqueTarget(targets, seen, guy, function(target) return IsValidSnareTarget(inst, target) end)
        if #targets >= FeastBuffEffects.GetSnareMaxTargets(inst, SNARE_MAX_TARGETS) then
            break
        end
    end

    return #targets > 0 and targets or nil
end

local function SpawnSnare(inst, x, z, r, num, target)
    local vars = { 1, 2, 3, 4, 5, 6, 7 }
    local used = {}
    local queued = {}
    local count = 0
    local dtheta = TWOPI / num
    local delaytoggle = 0
    local map = TheWorld.Map
    for theta = math.random() * dtheta, TWOPI, dtheta do
        local x1 = x + r * math.cos(theta)
        local z1 = z + r * math.sin(theta)
        if map:IsPassableAtPoint(x1, 0, z1) and not map:IsPointNearHole(Vector3(x1, 0, z1)) then
            local spike = SpawnPrefab("shadow_stalker_fossilspike")
            spike.Transform:SetPosition(x1, 0, z1)
            spike:SetSnareData(inst, x, z, r)
            RestrictSpawnedSpikeDamage(spike, inst)

            local delay = delaytoggle == 0 and 0 or .2 + delaytoggle * math.random() * .2
            delaytoggle = delaytoggle == 1 and -1 or 1
            local duration = FeastBuffEffects.GetSnareDuration(inst, SHADOW_STALKER_SNARE_DURATION)

            local variation = table.remove(vars, math.random(#vars))
            table.insert(used, variation)
            if #used > 3 then
                table.insert(queued, table.remove(used, 1))
            end
            if #vars <= 0 then
                local swap = vars
                vars = queued
                queued = swap
            end

            spike:RestartSpike(delay, duration, variation)
            count = count + 1
        end
    end

    if count <= 0 then
        return false
    end

    local duration = FeastBuffEffects.GetSnareDuration(inst, SHADOW_STALKER_SNARE_DURATION) + 1
    local blinkfocus = SpawnPrefab("blinkfocus_marker")
    blinkfocus.Transform:SetPosition(x, 0, z)
    blinkfocus:MakeTemporary(duration)
    blinkfocus:SetMaxRange(r + 4)

    if target:IsValid() then
        target:PushEvent("snared", { attacker = inst })
    end

    return true
end

local function SpawnSnares(inst, targets)
    ResetAbilityCooldown(inst, "snare")

    local count = 0
    local nextpass = {}
    for _, v in ipairs(targets) do
        if v:IsValid()
            and v:IsNear(inst, TUNING.STALKER_SNARE_MAX_RANGE)
            and IsInWorkArea(inst, v, v:GetPhysicsRadius(0)) then
            local x, y, z = v.Transform:GetWorldPosition()
            local islarge = v:HasTag("largecreature")
            local r = v:GetPhysicsRadius(0) + (islarge and 1.5 or .5)
            local num = islarge and 12 or 6
            if NoSnareOverlap(x, z, r + SNARE_OVERLAP_MAX) then
                if SpawnSnare(inst, x, z, r, num, v) then
                    count = count + 1
                    if count >= TUNING.STALKER_MAX_SNARES then
                        return
                    end
                end
            else
                table.insert(nextpass, { x = x, z = z, r = r, n = num, inst = v })
            end
        end
    end

    if #nextpass > 0 then
        for range = SNARE_OVERLAP_MAX - 1, SNARE_OVERLAP_MIN, -1 do
            local i = 1
            while i <= #nextpass do
                local v = nextpass[i]
                if NoSnareOverlap(v.x, v.z, v.r + range) then
                    if SpawnSnare(inst, v.x, v.z, v.r, v.n, v.inst) then
                        count = count + 1
                        if count >= TUNING.STALKER_MAX_SNARES or #nextpass <= 1 then
                            return
                        end
                    end
                    table.remove(nextpass, i)
                else
                    i = i + 1
                end
            end
        end
    end
end

local function SpawnChannelers(inst)
    ActivateShadowWard(inst)
end

local function DespawnChannelers(inst)
    DeactivateShadowWard(inst)
end

local function OnRemoveShadowStalker(inst)
    DespawnChannelers(inst)
    ShadowStalkerSpikes.ClearAll(inst)
    if inst.ClearFeastLanternEffects ~= nil then
        inst:ClearFeastLanternEffects()
    end
end

local FEAST_TARGET_CANT_TAGS = { "INLIMBO", "NOCLICK", "player", "playerghost", "chester", "glommer" }

local function IsPlayerShadowFeastTarget(ent)
    if ent == nil then
        return false
    end

    if ent:HasTag("shadowminion") then
        return true
    end

    local prefab = ent.prefab
    if prefab ~= nil and string.find(prefab, "shadowwaxwell", 1, true) ~= nil then
        return true
    end

    local follower = ent.components ~= nil and ent.components.follower or nil
    local leader = follower ~= nil and follower:GetLeader() or nil
    if leader ~= nil and leader.components.inventoryitem ~= nil then
        leader = leader.components.inventoryitem:GetGrandOwner()
    end

    return leader ~= nil and leader:HasTag("player")
end

local function IsFeastTarget(inst, target)
    return targeting_rules.IsEntityAllowed(target,
    {
        name = "shadow_stalker_feast",
        must_tags = { "_health" },
        blacklist_tags = FEAST_TARGET_CANT_TAGS,
        extra_check = function(ent)
            if ent == inst
                or not ent:IsValid()
                or not ent.entity:IsVisible()
                or ent.components.health == nil
                or ent.components.health:IsDead()
                or ent.components.health:IsInvincible()
                or not IsInWorkArea(inst, ent, ent:GetPhysicsRadius(0)) then
                return false
            end

            if IsPlayerShadowFeastTarget(ent) then
                return true
            end

            return ShadowCreatureTargets.IsNightmareShadowCreatureTarget(ent)
        end,
    })
end

local FEAST_TARGET_RADIUS_PADDING = .3

local function CollectFeastTargets(inst)
    local center = EnsureWorkCenter(inst)
    local radius = (inst._workradius or WORK_RADIUS) + FEAST_TARGET_RADIUS_PADDING
    local ents = TheSim:FindEntities(center.x, center.y, center.z, radius, { "_health" }, FEAST_TARGET_CANT_TAGS)
    local summons = {}
    local creatures = {}

    for _, target in ipairs(ents) do
        if IsFeastTarget(inst, target) then
            if IsPlayerShadowFeastTarget(target) then
                table.insert(summons, target)
            else
                table.insert(creatures, target)
            end
        end
    end

    return summons, creatures
end

local function SelectNearestFeastTarget(inst, list)
    if list == nil or #list <= 0 then
        return nil
    end

    table.sort(list, function(a, b)
        return a:GetDistanceSqToInst(inst) < b:GetDistanceSqToInst(inst)
    end)

    return list[1]
end

local function FindMinions(inst, proximity)
    local x, y, z = inst.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(x, y, z, FEAST_TARGET_RADIUS_PADDING + inst:GetPhysicsRadius(0) + (proximity or .5), { "_health" }, FEAST_TARGET_CANT_TAGS)
    local targets = {}
    for _, target in ipairs(ents) do
        if IsFeastTarget(inst, target) then
            table.insert(targets, target)
        end
    end
    table.sort(targets, function(a, b)
        return a:GetDistanceSqToInst(inst) < b:GetDistanceSqToInst(inst)
    end)
    return targets
end

local function EatMinions(inst, target)
    target = target ~= nil and IsFeastTarget(inst, target) and target or FindMinions(inst, SHADOW_STALKER_FEAST_EAT_RANGE)[1]
    if target == nil then
        return 0
    end

    if target.PushEvent ~= nil then
        target:PushEvent("stalkerconsumed")
    end
    if target.components.health ~= nil and not target.components.health:IsDead() then
        target.components.health:Kill()
    end

    if not inst.components.health:IsDead() then
        local is_summon = IsPlayerShadowFeastTarget(target)
        local heal = is_summon
            and SHADOW_STALKER_FEAST_SUMMON_HEAL_PERCENT
            or SHADOW_STALKER_FEAST_SC_HEAL_PERCENT
        inst.components.health:SetPercent(math.min(1, inst.components.health:GetPercent() + heal))

        if is_summon then
            local bufftype = FeastBuff.GetTypeFromTarget(target)
            if bufftype ~= nil then
                FeastBuff.SetFeastBuffType(inst, bufftype)
            end
        end
    end

    ResetAbilityCooldown(inst, "feast")
    inst.components.timer:StopTimer("feast_retry_cd")
    inst._feasttarget = nil
    return 1
end

local function PlayFlameSound(inst)
    if inst.SoundEmitter ~= nil then
        inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/flame")
    end
end

local function FindFeastTarget(inst)
    local summons, creatures = CollectFeastTargets(inst)
    local summon = SelectNearestFeastTarget(inst, summons)
    if summon ~= nil then
        return summon
    end

    if inst.components.health == nil
        or inst.components.health:GetPercent() >= SHADOW_STALKER_FEAST_SC_LOW_HEALTH_PERCENT then
        return nil
    end

    return SelectNearestFeastTarget(inst, creatures)
end

local function CancelFeast(inst)
    inst._feasttarget = nil
    ClearFeastSpeed(inst)
    if inst.components.timer ~= nil then
        inst.components.timer:StopTimer("feast_cd")
        inst.components.timer:StopTimer("feast_retry_cd")
        inst.components.timer:StopTimer(SHADOW_STALKER_SKILL_DELAY_TIMER)
        inst.components.timer:StartTimer(SHADOW_STALKER_SKILL_DELAY_TIMER, SHADOW_STALKER_SKILL_DELAY)
    end
end

local function IsFeastAttemptReady(inst)
    if inst.components.timer == nil then
        return true
    end
    return not inst.components.timer:TimerExists("feast_cd")
        and not inst.components.timer:TimerExists(SHADOW_STALKER_SKILL_DELAY_TIMER)
end

local function WatchFeastOpportunity(inst)
    if inst.components.health == nil or inst.components.health:IsDead() then
        return
    end

    if not IsFeastAttemptReady(inst) then
        return
    end

    if inst.sg ~= nil and (inst.sg:HasStateTag("busy") or inst.sg:HasStateTag("feasting")) then
        return
    end

    local target = FindFeastTarget(inst)
    if target ~= nil then
        inst:PushEvent("fossilfeast", { target = target })
    end
end

local function FindSpikeTargets(inst)
    return ShadowStalkerSpikes.FindTargets(inst, IsValidEnemy)
end

local function SpawnSpikes(inst)
    ResetAbilityCooldown(inst, "spikes")

    if ShadowStalkerSpikes.SpawnCast(inst, IsValidEnemy, RestrictSpawnedSpikeDamage, ApplyShadowTintToSpikeEffects) then
        PlayFlameSound(inst)
    end
end

local MINDCONTROL_TAGS = { "_combat", "_health" }
local MINDCONTROL_NO_TAGS =
{
    "INLIMBO",
    "player",
    "playerghost",
    "companion",
    "shadow",
    "shadowminion",
    "stalkerminion",
    "shadowcreature",
    "prey",
    "smallcreature",
}

local function IsValidMindControlTarget(inst, guy)
    return targeting_rules.IsEntityAllowed(guy,
    {
        name = "shadow_stalker_mindcontrol",
        must_tags = MINDCONTROL_TAGS,
        blacklist_tags = MINDCONTROL_NO_TAGS,
        extra_check = function(ent)
            return ent.entity:IsVisible()
                and ent.components.health ~= nil
                and not ent.components.health:IsDead()
                and ent.components.combat ~= nil
                and not IsProtectedNonTarget(ent)
                and (ent:HasTag("monster") or ent:HasTag("hostile") or ent:HasTag("scarytoprey"))
                and ent.components.combat:CanTarget(inst)
                and IsInWorkArea(inst, ent, ent:GetPhysicsRadius(0))
        end,
    })
end

local function HasMindControlTarget(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local range = GetMindControlRange(inst)
    local ents = TheSim:FindEntities(x, y, z, range, MINDCONTROL_TAGS, MINDCONTROL_NO_TAGS)
    for _, guy in ipairs(ents) do
        if IsValidMindControlTarget(inst, guy) then
            return true
        end
    end
    return false
end

local function MindControl(inst)
    ResetAbilityCooldown(inst, "mindcontrol")

    local count = 0
    local x, y, z = inst.Transform:GetWorldPosition()
    local range = GetMindControlRange(inst)
    local ents = TheSim:FindEntities(x, y, z, range, MINDCONTROL_TAGS, MINDCONTROL_NO_TAGS)
    for _, guy in ipairs(ents) do
        if IsValidMindControlTarget(inst, guy) then
            count = count + 1
            guy.components.combat:SetTarget(inst)
            guy.components.combat:SuggestTarget(inst)
        end
    end

    return count
end

local function OnNewTarget(inst, data)
    if data.target ~= nil then
        inst:SetEngaged(true)
    end
end

local function SetEngaged(inst, engaged)
    if inst.engaged ~= engaged then
        inst.engaged = engaged
        inst.components.timer:StopTimer("snare_cd")
        inst.components.timer:StopTimer("spikes_cd")
        inst.components.timer:StopTimer("channelers_cd")
        inst.components.timer:StopTimer("mindcontrol_cd")
        inst.components.timer:StopTimer("feast_cd")
        inst.components.timer:StopTimer(SHADOW_STALKER_SKILL_DELAY_TIMER)
        if engaged then
            inst:RemoveEventCallback("newcombattarget", OnNewTarget)
        else
            inst:ListenForEvent("newcombattarget", OnNewTarget)
        end
    end
end

local function ontimerdone(inst, data)
    if data ~= nil and data.name == SHADOW_STALKER_CHANNELERS_DURATION_TIMER then
        DeactivateShadowWard(inst)
    elseif data ~= nil and data.name == SHADOW_STALKER_LIFETIME_TIMER then
        if inst:IsValid()
            and inst.sg ~= nil
            and inst.components.health ~= nil
            and not inst.components.health:IsDead()
            and not inst.sg:HasStateTag("dead") then
            inst.sg:GoToState("despawn")
        end
    end
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()
    inst.entity:AddDynamicShadow()
    inst.entity:AddSoundEmitter()

    inst._feast_buff_net = net_tinybyte(inst.GUID, "shadow_stalker._feast_buff", "shadow_stalker_feastbuffdirty")
    inst._feast_buff_net:set_local(0)
    inst._shadow_stalker_spell_owner_userid_net = net_string(inst.GUID, "shadow_stalker._spell_owner_userid", "shadow_stalker_spellownerdirty")

    MakeGiantCharacterPhysics(inst, 1000, .75)

    inst.Transform:SetFourFaced()
    inst.DynamicShadow:SetSize(4, 2)

    inst.AnimState:SetBank("stalker")
    inst.AnimState:SetBuild("stalker_shadow_build")
    inst.AnimState:AddOverrideBuild("stalker_cave_build")
    inst.AnimState:PlayAnimation("idle", true)
    inst.AnimState:SetMultColour(0, 0, 0, SHADOW_TINT_ALPHA)

    inst:AddTag("shadow_stalker")
    inst:AddTag("scarytoprey")
    inst:AddTag("shadowminion")
    inst:AddTag("companion")
    inst:AddTag("NOBLOCK")
    inst:AddTag("noauradamage")
    inst:AddTag("largecreature")
    inst.controller_priority_override_is_ally = true

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        require("skill_effect/waxwell/emperor/shadow_stalker/feast_buff_ui").ScheduleAttach(inst)
        return inst
    end

    inst._workradius = WORK_RADIUS
    inst.IsInWorkArea = IsInWorkArea
    inst.IsPointInWorkArea = IsPointInWorkAreaProxy
    inst.GetWorkCenter = EnsureWorkCenter
    inst.IsValidEnemy = IsValidEnemy
    inst:DoTaskInTime(0, EnsureWorkCenter)

    inst:AddComponent("locomotor")
    inst.components.locomotor.walkspeed = TUNING.STALKER_SPEED
    inst.components.locomotor.runspeed = TUNING.STALKER_SPEED
    inst.components.locomotor:SetTriggersCreep(false)
    inst.components.locomotor.pathcaps = { ignorecreep = true }
    inst.components.locomotor:SetSlowMultiplier(.6)

    inst:AddComponent("health")
    inst.components.health:SetMaxHealth(3000)
    inst.components.health.nofadeout = true
    inst.components.health.redirect = environmentaldamageredirect

    inst:AddComponent("combat")
    inst.components.combat.hiteffectsymbol = "torso"
    inst.components.combat:SetDefaultDamage(SHADOW_STALKER_NORMAL_DAMAGE)
    inst.components.combat:SetAttackPeriod(TUNING.STALKER_ATTACK_PERIOD)
    inst.components.combat.playerdamagepercent = .5
    inst.components.combat:SetRange(TUNING.STALKER_ATTACK_RANGE, TUNING.STALKER_HIT_RANGE)
    inst.components.combat:SetAreaDamage(TUNING.STALKER_AOE_RANGE, TUNING.STALKER_AOE_SCALE, CanAreaHitTarget)
    inst.components.combat:SetRetargetFunction(2, retargetfn)
    inst.components.combat:SetKeepTargetFunction(keeptargetfn)

    inst:AddComponent("damagetypebonus")
    inst.components.damagetypebonus:AddBonus("lunar_aligned", inst, SHADOW_STALKER_VS_LUNAR_BONUS, "shadow_stalker_vs_lunar")

    inst:AddComponent("damagetyperesist")
    inst.components.damagetyperesist:AddResist("shadow_aligned", inst, SHADOW_STALKER_VS_SHADOW_RESIST, "shadow_stalker_vs_shadow")
    inst.components.damagetyperesist:AddResist("shadowcreature", inst, SHADOW_STALKER_VS_SHADOW_RESIST, "shadow_stalker_vs_shadow")

    inst:AddComponent("planardamage")
    inst.components.planardamage:SetBaseDamage(SHADOW_STALKER_PLANAR_DAMAGE)

    inst:AddComponent("planardefense")
    inst.components.planardefense:SetBaseDefense(SHADOW_STALKER_PLANAR_DEFENSE)

    inst:AddComponent("follower")
    inst.components.follower:KeepLeaderOnAttacked()
    inst.components.follower:DisableLeashing()
    inst.components.follower.keepleaderduringminigame = true

    inst:AddComponent("knownlocations")
    inst:AddComponent("entitytracker")
    inst.SaveSpawnPoint = SaveSpawnPoint

    inst:AddComponent("timer")
    inst.components.timer:StartTimer(SHADOW_STALKER_LIFETIME_TIMER, SHADOW_STALKER_LIFETIME)

    -- Keep compatibility with Maxwell's vanilla shadow-pet hooks without
    -- letting player skin data override the stalker's custom visuals.
    inst.components.skinner = inst.components.skinner or
    {
        SetupNonPlayerData = function() end,
        CopySkinsFromPlayer = function() end,
    }
    inst.components.skinner:SetupNonPlayerData()

    inst.hasshield = false
    inst._shadowward_hitsleft = nil
    inst.reversespikes = false
    inst.RequestSpellDeactivate = RequestSpellDeactivate
    inst.EnsureOwnerDeathListener = EnsureOwnerDeathListener

    inst.StartAbility = StartAbility
    inst.IsSkillDelayActive = IsSkillDelayActive
    inst.FindSnareTargets = FindSnareTargets
    inst.FindSpikeTargets = FindSpikeTargets
    inst.SpawnSnares = SpawnSnares
    inst.SpawnChannelers = SpawnChannelers
    inst.FindMinions = FindMinions
    inst.FindFeastTarget = FindFeastTarget
    inst.EatMinions = EatMinions
    inst.CancelFeast = CancelFeast
    inst.ApplyFeastSpeed = ApplyFeastSpeed
    inst.ClearFeastSpeed = ClearFeastSpeed
    inst.ApplyMindControlRepositionSpeed = ApplyMindControlRepositionSpeed
    inst.ClearMindControlRepositionSpeed = ClearMindControlRepositionSpeed
    inst.IsAtWorkCenter = IsAtWorkCenter
    inst.GetMindControlRange = GetMindControlRange
    inst.SpawnSpikes = SpawnSpikes
    inst.HasMindControlTarget = HasMindControlTarget
    inst.MindControl = MindControl
    inst.SetEngaged = SetEngaged
    inst.ActivateLanternFeastWard = ActivateLanternFeastWard
    inst.DeactivateLanternFeastWard = DeactivateLanternFeastWard
    inst.BeginShadowStalkerSpellDeactivate = BeginShadowStalkerSpellDeactivate
    inst.ClearFeastLanternEffects = function(feast_inst)
        require("skill_effect/waxwell/emperor/shadow_stalker/feast_lantern_mc").ClearAll(feast_inst)
    end
    inst.SetFeastBuffType = FeastBuff.SetFeastBuffType
    inst.ClearFeastBuff = FeastBuff.ClearFeastBuff
    inst.GetFeastBuffType = FeastBuff.GetFeastBuffType
    inst.BattleChatter = function() end

    inst:SetEngaged(false)

    inst:SetStateGraph("waxwell/SGshadow_stalker")
    inst:SetBrain(brain)
    inst:DoTaskInTime(0, function(inst)
        if not inst._loaded_from_save
            and inst.sg ~= nil
            and inst.sg.currentstate ~= nil
            and inst.sg.currentstate.name == "idle"
            and not inst.components.health:IsDead() then
            inst.sg:GoToState("spawn")
        end
    end)

    inst.OnSave = function(inst, data)
        if data ~= nil and inst._shadow_stalker_spell_active and not inst._shadow_stalker_spell_deactivating then
            data._shadow_stalker_spell_active = true
        end
        if data ~= nil and inst._shadow_stalker_spell_owner_userid ~= nil then
            data._shadow_stalker_spell_owner_userid = inst._shadow_stalker_spell_owner_userid
        end
        if data ~= nil and inst._feast_buff_type ~= nil then
            data._feast_buff_type = inst._feast_buff_type
        end
    end

    inst.OnLoad = function(inst, data)
        inst._loaded_from_save = true
        if data ~= nil and data._shadow_stalker_spell_active then
            inst._shadow_stalker_spell_active = true
            if not inst:HasTag(SHADOW_STALKER_ACTIVE_TAG) then
                inst:AddTag(SHADOW_STALKER_ACTIVE_TAG)
            end
        end
        if data ~= nil and data._shadow_stalker_spell_owner_userid ~= nil then
            inst._shadow_stalker_spell_owner_userid = data._shadow_stalker_spell_owner_userid
            if inst._shadow_stalker_spell_owner_userid_net ~= nil then
                inst._shadow_stalker_spell_owner_userid_net:set(inst._shadow_stalker_spell_owner_userid)
            end
        end
        if data ~= nil and data._feast_buff_type ~= nil then
            inst:DoTaskInTime(0, function()
                if inst:IsValid() then
                    FeastBuff.SetFeastBuffType(inst, data._feast_buff_type)
                end
            end)
        end
    end

    inst:ListenForEvent("attacked", onattacked)
    inst:ListenForEvent("blocked", onblocked)
    inst:ListenForEvent("timerdone", ontimerdone)
    inst:DoPeriodicTask(0.25, WatchLeaderState)
    inst:DoPeriodicTask(0.5, WatchFeastOpportunity)

    inst.OnRemoveEntity = OnRemoveShadowStalker

    if ThePlayer ~= nil then
        require("skill_effect/waxwell/emperor/shadow_stalker/feast_buff_ui").ScheduleAttach(inst)
    end

    return inst
end

return Prefab("shadow_stalker", fn, assets, prefabs)
