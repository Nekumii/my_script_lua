local brain = require("brains/waxwell/shadow_marksmanbrain")
require("stategraphs/waxwell/SGshadow_marksman")

local assets =
{
    Asset("ANIM", "anim/slingshot.zip"),
}

local prefabs =
{
    "shadow_despawn",
    "shadow_glob_fx",
    "statue_transition_2",
    "slingshotammo_rock_proj",
    "slingshotammo_stinger_proj",
    "slingshotammo_moonglass_proj",
    "slingshotammo_marble_proj",
    "slingshotammo_thulecite_proj",
    "slingshotammo_freeze_proj",
    "slingshotammo_scrapfeather_proj",
    "slingshotammo_honey_proj",
    "slingshotammo_gelblob_proj",
    "shadow_marksman_aoe_fx",
    "shadow_marksman_shatter",
    "shadow_marksman_electrichitsparks",
    "shadow_marksman_electrichitsparks_electricimmune",
    "shadow_marksman_honey_trail",
    "ocean_splash_med1",
    "ocean_splash_med2",
    "ocean_splash_small1",
    "ocean_splash_small2",
}

local SHADOW_MARKSMAN_DURATION = TUNING.SEG_TIME * 6

local function SaveSpawnPoint(inst, dont_overwrite)
    if not dont_overwrite or
        (
            inst.components.knownlocations:GetLocation("spawn") == nil and
            inst.components.knownlocations:GetLocation("spawnplatform") == nil
        )
    then
        local x, y, z = inst.Transform:GetWorldPosition()
        local platform = TheWorld.Map:GetPlatformAtPoint(x, z)
        if platform ~= nil then
            x, y, z = platform.entity:WorldToLocalSpace(x, 0, z)
            inst.components.knownlocations:ForgetLocation("spawn")
            inst.components.knownlocations:RememberLocation("spawnplatform", Vector3(x, 0, z))
            inst.components.entitytracker:TrackEntity("spawnplatform", platform)
        else
            inst.components.entitytracker:ForgetEntity("spawnplatform")
            inst.components.knownlocations:ForgetLocation("spawnplatform")
            inst.components.knownlocations:RememberLocation("spawn", Vector3(x, 0, z))
        end
    end
end

local function GetSpawnPoint(inst)
    local pt = inst.components.knownlocations:GetLocation("spawn")
    if pt ~= nil then
        return pt
    end

    pt = inst.components.knownlocations:GetLocation("spawnplatform")
    if pt ~= nil then
        local platform = inst.components.entitytracker:GetEntity("spawnplatform")
        if platform ~= nil then
            local x, y, z = platform.entity:LocalToWorldSpace(pt:Get())
            return Vector3(x, 0, z)
        end
    end
end

local function MakeSpawnPointTracker(inst)
    inst:AddComponent("knownlocations")
    inst:AddComponent("entitytracker")
    inst.SaveSpawnPoint = SaveSpawnPoint
    inst.GetSpawnPoint = GetSpawnPoint
end

local function OnAttacked(inst, data)
    if data.attacker ~= nil then
        if data.attacker.components.petleash ~= nil and data.attacker.components.petleash:IsPet(inst) then
            data.attacker.components.petleash:DespawnPet(inst)
        elseif data.attacker.components.combat ~= nil then
            inst.components.combat:SuggestTarget(data.attacker)
        end
    end
end

local function DoRemove(inst)
    if inst.components.inventory ~= nil then
        inst.components.inventory:DropEverything(true)
    end
    inst:Remove()
end

local function OnSeekOblivion(inst)
    if inst:IsAsleep() then
        DoRemove(inst)
        return
    end

    inst.components.timer:StopTimer("obliviate")
    if inst.components.health == nil then
        inst.sg:GoToState("quickdespawn")
    elseif inst.components.health:IsInvincible() then
        inst.components.timer:StartTimer("obliviate", .5)
    else
        inst:SetBrain(nil)
        inst.components.health:Kill()
    end
end

local function OnTimerDone(inst, data)
    if data ~= nil and data.name == "obliviate" then
        OnSeekOblivion(inst)
    end
end

local function OnEntitySleep(inst)
    if inst._obliviatetask == nil then
        inst._obliviatetask = inst:DoTaskInTime(TUNING.SHADOWWAXWELL_MINION_IDLE_DESPAWN_TIME, DoRemove)
    end
end

local function OnEntityWake(inst)
    if inst._obliviatetask ~= nil then
        inst._obliviatetask:Cancel()
        inst._obliviatetask = nil
    end
end

local function MakeOblivionSeeker(inst, duration)
    inst:ListenForEvent("timerdone", OnTimerDone)
    inst:AddComponent("timer")
    inst.components.timer:StartTimer("obliviate", duration)
    inst.OnEntitySleep = OnEntitySleep
    inst.OnEntityWake = OnEntityWake
end

local function DropAggro(inst)
    local leader = inst.components.follower:GetLeader()
    if leader ~= nil and
        (
            (leader.components.health ~= nil and leader.components.health:IsDead()) or
            (leader.sg ~= nil and leader.sg:HasStateTag("hiding")) or
            not inst:IsNear(leader, TUNING.SHADOWWAXWELL_PROTECTOR_TRANSFER_AGGRO_RANGE) or
            not leader.entity:IsVisible() or
            leader:HasTag("playerghost")
        )
    then
        leader = nil
    end

    inst:PushEvent("transfercombattarget", leader)
end

local function OnDancingPlayerData(inst, data)
    if data == nil then
        return
    end

    local player = data.inst
    if player == nil or player ~= inst.components.follower:GetLeader() then
        return
    end

    inst._brain_dancedata = data.dancedata
end

local RETARGET_MUST_TAGS = { "_combat", "_health" }
local RETARGET_CANT_TAGS = { "INLIMBO", "companion" }
local RETARGET_MUSTONEOF_TAGS = { "monster", "prey", "insect", "hostile", "character", "animal" }

local function HasFriendlyLeader(inst, target)
    local leader = inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
    if leader ~= nil then
        local target_leader = target.components.follower ~= nil and target.components.follower:GetLeader() or nil

        if target_leader ~= nil and target_leader.components.inventoryitem ~= nil then
            target_leader = target_leader.components.inventoryitem:GetGrandOwner()
            if target_leader == nil then
                return true
            end
        end

        local pvp_enabled = TheNet:GetPVPEnabled()
        return leader == target
            or (
                target_leader ~= nil and
                (
                    target_leader == leader or
                    (target_leader:HasTag("player") and not pvp_enabled)
                )
            )
            or (
                target.components.domesticatable ~= nil and
                target.components.domesticatable:IsDomesticated() and
                not pvp_enabled
            )
            or (
                target.components.saltlicker ~= nil and
                target.components.saltlicker.salted and
                not pvp_enabled
            )
    end

    return false
end

local function IsFrozenTarget(target)
    return target ~= nil
        and target.components ~= nil
        and target.components.freezable ~= nil
        and target.components.freezable:IsFrozen()
end

local function marksman_retargetfn(inst)
    local spawn = inst:GetSpawnPoint()
    if spawn == nil then
        return nil
    end

    local ents = TheSim:FindEntities(spawn.x, spawn.y, spawn.z, TUNING.SHADOWWAXWELL_PROTECTOR_DEFEND_RADIUS, RETARGET_MUST_TAGS, RETARGET_CANT_TAGS, RETARGET_MUSTONEOF_TAGS)
    for _, ent in ipairs(ents) do
        if ent ~= inst
            and ent.entity:IsVisible()
            and inst.components.combat:CanTarget(ent)
            and ent.components.minigame_participator == nil
            and not HasFriendlyLeader(inst, ent)
            and not IsFrozenTarget(ent)
        then
            return ent
        end
    end

    return nil
end

local function marksman_keeptargetfn(inst, target)
    return inst.components.combat:CanTarget(target)
        and not IsFrozenTarget(target)
        and target.components.minigame_participator == nil
        and (not target:HasTag("player") or TheNet:GetPVPEnabled())
end

local function nodebrisdmg(inst, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
    return afflicter ~= nil and afflicter:HasTag("quakedebris")
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst:SetPhysicsRadiusOverride(.5)
    MakeGhostPhysics(inst, 1, inst.physicsradiusoverride)

    inst.Transform:SetFourFaced(inst)

    inst.AnimState:SetBank("wilson")
    inst.AnimState:SetBuild("waxwell")
    inst.AnimState:OverrideSymbol("fx_wipe", "wilson_fx", "fx_wipe")
    inst.AnimState:PlayAnimation("minion_spawn")
    inst.AnimState:SetMultColour(0, 0, 0, .5)
    inst.AnimState:UsePointFiltering(true)
    inst.AnimState:AddOverrideBuild("waxwell_minion_spawn")
    inst.AnimState:AddOverrideBuild("waxwell_minion_appear")
    inst.AnimState:OverrideSymbol("swap_object", "slingshot", "swap_slingshot")
    inst.AnimState:OverrideSymbol("swap_band_btm", "slingshot", "swap_band_btm")
    inst.AnimState:Hide("ARM_normal")
    inst.AnimState:Show("ARM_carry")
    inst.AnimState:Hide("HAT")
    inst.AnimState:Hide("HAIR_HAT")

    inst:AddTag("scarytoprey")
    inst:AddTag("shadowminion")
    inst:AddTag("shadowmarksman")
    inst:AddTag("NOBLOCK")

    inst:SetPrefabNameOverride("shadowwaxwell")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("skinner")
    inst.components.skinner:SetupNonPlayerData()

    inst:AddComponent("locomotor")
    inst.components.locomotor.runspeed = TUNING.SHADOWWAXWELL_PROTECTOR_SPEED
    inst.components.locomotor:SetTriggersCreep(false)
    inst.components.locomotor.pathcaps = { ignorecreep = true }
    inst.components.locomotor:SetSlowMultiplier(.6)

    inst:AddComponent("health")
    inst.components.health:SetMaxHealth(30)
    inst.components.health:SetMaxDamageTakenPerHit(TUNING.SHADOWWAXWELL_PROTECTOR_HEALTH_CLAMP_TAKEN)
    inst.components.health.nofadeout = true
    inst.components.health.redirect = nodebrisdmg

    inst:AddComponent("combat")
    inst.components.combat.hiteffectsymbol = "torso"
    inst.components.combat:SetDefaultDamage(TUNING.SLINGSHOT_AMMO_DAMAGE_ROCKS)
    inst.components.combat:SetAttackPeriod(TUNING.SHADOWWAXWELL_PROTECTOR_ATTACK_PERIOD)
    inst.components.combat:SetRetargetFunction(1, marksman_retargetfn)
    inst.components.combat:SetKeepTargetFunction(marksman_keeptargetfn)
    inst.components.combat:SetRange(TUNING.SLINGSHOT_DISTANCE, TUNING.SLINGSHOT_DISTANCE_MAX)

    inst:AddComponent("follower")
    inst.components.follower:KeepLeaderOnAttacked()
    inst.components.follower.keepdeadleader = true
    inst.components.follower.keepleaderduringminigame = true
    inst.components.follower.noleashing = true

    MakeSpawnPointTracker(inst)
    MakeOblivionSeeker(inst, SHADOW_MARKSMAN_DURATION + math.random())

    inst.DropAggro = DropAggro
    inst:SetBrain(brain)
    inst:SetStateGraph("waxwell/SGshadow_marksman")

    inst:ListenForEvent("attacked", OnAttacked)
    inst:ListenForEvent("seekoblivion", OnSeekOblivion)
    inst:ListenForEvent("death", DropAggro)
    inst:ListenForEvent("dancingplayerdata", function(world, data) OnDancingPlayerData(inst, data) end, TheWorld)

    return inst
end

return Prefab("shadow_marksman", fn, assets, prefabs)
