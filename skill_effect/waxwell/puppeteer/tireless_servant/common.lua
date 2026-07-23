local V = require("skill_effect/waxwell/puppeteer/tireless_servant/variables")
local expanded_dominion = require("skill_effect/waxwell/puppeteer/expanded_dominion/common")

local WithTemporaryPetLeashIsFull = expanded_dominion.WithTemporaryPetLeashIsFull

local function IsTirelessServant1Active(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_tireless_servant_1"))
            or inst:HasTag("tireless_servant_1_active")
        )
end

local function IsTirelessServant2Active(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_tireless_servant_2"))
            or inst:HasTag("tireless_servant_2_active")
        )
end

local function IsFreeShadowServant(inst)
    return inst ~= nil and (inst._waxwell_free_shadow_servant or inst:HasTag(V.FREE_SHADOW_SERVANT_TAG))
end

local function MarkFreeShadowServant(inst)
    if inst == nil then
        return
    end

    inst._waxwell_free_shadow_servant = true
    if not inst:HasTag(V.FREE_SHADOW_SERVANT_TAG) then
        inst:AddTag(V.FREE_SHADOW_SERVANT_TAG)
    end

    if inst.AnimState ~= nil then
        inst.AnimState:SetMultColour(V.SHADOW_MINION_BASE_TINT, V.SHADOW_MINION_BASE_TINT, V.SHADOW_MINION_BASE_TINT, V.SHADOW_MINION_BASE_ALPHA)
        inst.AnimState:SetAddColour(V.FREE_SHADOW_SERVANT_ADD_TINT, V.FREE_SHADOW_SERVANT_ADD_TINT, V.FREE_SHADOW_SERVANT_ADD_TINT, 0)
        inst._waxwell_free_shadow_servant_tinted = true
    end
end

local function ClearFreeShadowServantMasterLink(inst)
    if inst == nil then
        return
    end

    local master = inst._waxwell_free_shadow_master
    if master ~= nil and master:IsValid() then
        if inst._waxwell_free_shadow_master_remove_fn ~= nil then
            master:RemoveEventCallback("onremove", inst._waxwell_free_shadow_master_remove_fn)
        end
        if inst._waxwell_free_shadow_master_death_fn ~= nil then
            master:RemoveEventCallback("death", inst._waxwell_free_shadow_master_death_fn)
        end
    end

    inst._waxwell_free_shadow_master = nil
    inst._waxwell_free_shadow_master_guid = nil
    inst._waxwell_free_shadow_master_remove_fn = nil
    inst._waxwell_free_shadow_master_death_fn = nil
end

local function RemoveLinkedFreeShadowServant(inst)
    if inst == nil or not inst:IsValid() then
        return
    end

    inst._waxwell_free_shadow_removed_by_master = true
    if inst.PushEvent ~= nil then
        inst:PushEvent("seekoblivion")
    end
    if inst:IsValid() then
        inst:DoTaskInTime(0, function(shadow)
            if shadow ~= nil and shadow:IsValid() then
                shadow:Remove()
            end
        end)
    end
end

local function LinkFreeShadowServantToMaster(inst, master)
    if inst == nil then
        return nil
    end

    ClearFreeShadowServantMasterLink(inst)

    if master == nil or not master:IsValid() then
        RemoveLinkedFreeShadowServant(inst)
        return nil
    end

    inst._waxwell_free_shadow_master = master
    inst._waxwell_free_shadow_master_guid = master.GUID
    inst._waxwell_free_shadow_master_remove_fn = function()
        RemoveLinkedFreeShadowServant(inst)
    end
    inst._waxwell_free_shadow_master_death_fn = inst._waxwell_free_shadow_master_remove_fn

    master:ListenForEvent("onremove", inst._waxwell_free_shadow_master_remove_fn)
    master:ListenForEvent("death", inst._waxwell_free_shadow_master_death_fn)

    if not inst._waxwell_free_shadow_link_cleanup_patched then
        inst._waxwell_free_shadow_link_cleanup_patched = true
        inst:ListenForEvent("onremove", function(shadow)
            ClearFreeShadowServantMasterLink(shadow)
        end)
    end

    return master
end

local function HasTirelessServant1WorkerBuff(inst)
    return inst ~= nil and (inst._waxwell_tireless_servant_1 or inst:HasTag(V.TIRELESS_SERVANT_1_TAG))
end

local function MarkTirelessServant1WorkerBuff(inst)
    if inst == nil then
        return
    end

    inst._waxwell_tireless_servant_1 = true
    if not inst:HasTag(V.TIRELESS_SERVANT_1_TAG) then
        inst:AddTag(V.TIRELESS_SERVANT_1_TAG)
    end
end

local function CountFreeShadowServants(petleash)
    local pets = petleash ~= nil and petleash:GetPets() or nil
    local count = 0

    if pets ~= nil then
        for pet in pairs(pets) do
            if IsFreeShadowServant(pet) then
                count = count + 1
            end
        end
    end

    return count
end

local function HasLegacyTirelessServant1Buff(inst)
    local timer = inst.components.timer
    local obliviate = timer ~= nil and timer.timers ~= nil and timer.timers.obliviate or nil
    return obliviate ~= nil and (obliviate.initial_time or 0) > (TUNING.SHADOWWAXWELL_WORKER_DURATION + 1)
end

local function ApplyTirelessServant1ToWorker(inst, force_enhance)
    if not (inst:IsValid() and inst.components.locomotor ~= nil and inst.components.follower ~= nil) then
        return
    end

    local enhanced = HasTirelessServant1WorkerBuff(inst)
    local legacy_enhanced = not enhanced and HasLegacyTirelessServant1Buff(inst)
    if not enhanced and not legacy_enhanced and not force_enhance then
        return
    end

    inst.components.locomotor.runspeed = V.TIRELESS_SERVANT_1_SPEED

    if legacy_enhanced then
        MarkTirelessServant1WorkerBuff(inst)
        return
    end

    if enhanced or not force_enhance then
        return
    end

    MarkTirelessServant1WorkerBuff(inst)

    local timer = inst.components.timer
    if timer == nil or not timer:TimerExists("obliviate") then
        return
    end

    local base_duration = timer.timers.obliviate.initial_time or TUNING.SHADOWWAXWELL_WORKER_DURATION
    local duration_bonus = base_duration * V.TIRELESS_SERVANT_1_DURATION_BONUS_PCT
    local paused = timer:IsPaused("obliviate")
    local timeleft = timer:GetTimeLeft("obliviate") + duration_bonus
    local initial_time = base_duration + duration_bonus

    timer:StopTimer("obliviate")
    timer:StartTimer("obliviate", timeleft, paused, initial_time)
end

local function RefreshFreeShadowServantTint(inst)
    if not inst:IsValid() then
        if inst._waxwell_free_shadow_servant_tinttask ~= nil then
            inst._waxwell_free_shadow_servant_tinttask:Cancel()
            inst._waxwell_free_shadow_servant_tinttask = nil
        end
        return
    end

    if IsFreeShadowServant(inst) and inst.AnimState ~= nil then
        inst.AnimState:SetMultColour(V.SHADOW_MINION_BASE_TINT, V.SHADOW_MINION_BASE_TINT, V.SHADOW_MINION_BASE_TINT, V.SHADOW_MINION_BASE_ALPHA)
        inst.AnimState:SetAddColour(V.FREE_SHADOW_SERVANT_ADD_TINT, V.FREE_SHADOW_SERVANT_ADD_TINT, V.FREE_SHADOW_SERVANT_ADD_TINT, 0)
        inst._waxwell_free_shadow_servant_tinted = true
    end

    if inst._waxwell_free_shadow_servant_tinted or (inst._waxwell_free_shadow_servant_tintretries or 0) <= 0 then
        if inst._waxwell_free_shadow_servant_tinttask ~= nil then
            inst._waxwell_free_shadow_servant_tinttask:Cancel()
            inst._waxwell_free_shadow_servant_tinttask = nil
        end
        return
    end

    inst._waxwell_free_shadow_servant_tintretries = (inst._waxwell_free_shadow_servant_tintretries or V.FREE_SHADOW_SERVANT_TINT_RETRIES) - 1
end

local function StartFreeShadowServantTintWatcher(inst)
    if inst == nil or inst.AnimState == nil or inst._waxwell_free_shadow_servant_tinted or inst._waxwell_free_shadow_servant_tinttask ~= nil then
        return
    end

    inst._waxwell_free_shadow_servant_tintretries = V.FREE_SHADOW_SERVANT_TINT_RETRIES
    inst._waxwell_free_shadow_servant_tinttask = inst:DoPeriodicTask(FRAMES, RefreshFreeShadowServantTint)
    RefreshFreeShadowServantTint(inst)
end

local function CanSpawnTirelessServant2Worker(pt)
    return not TheWorld.Map:IsGroundTargetBlocked(pt)
end

local function GetTirelessServant2SpawnPoint(doer, pos)
    if doer == nil or pos == nil then
        return nil
    end

    local theta = doer:GetAngleToPoint(pos) * DEGREES + PI * (math.random() < .5 and .5 or -.5)
    local offset = FindWalkableOffset(pos, theta, 1, 3, false, false, CanSpawnTirelessServant2Worker, true, true)
    if (type(offset) == "table" or type(offset) == "userdata") and offset.x ~= nil and offset.z ~= nil then
        return Vector3(pos.x + offset.x, 0, pos.z + offset.z)
    end

    if TheWorld.Map:IsPassableAtPoint(pos.x, 0, pos.z, true) and CanSpawnTirelessServant2Worker(pos) then
        return pos
    end

    return nil
end

local function TrySpawnTirelessServant2Worker(owner, pos, master)
    if math.random() >= V.TIRELESS_SERVANT_2_FREE_SPAWN_CHANCE then
        return nil
    end

    local petleash = owner ~= nil and owner.components ~= nil and owner.components.petleash or nil
    local spawnpt = GetTirelessServant2SpawnPoint(owner, pos)
    if petleash == nil or spawnpt == nil then
        return nil
    end

    petleash._waxwell_pending_free_shadow_servants = (petleash._waxwell_pending_free_shadow_servants or 0) + 1

    local pet = WithTemporaryPetLeashIsFull(petleash, function()
        return false
    end, function()
        return petleash:SpawnPetAt(spawnpt.x, 0, spawnpt.z, "shadowworker")
    end)

    if pet == nil then
        local pending = (petleash._waxwell_pending_free_shadow_servants or 1) - 1
        petleash._waxwell_pending_free_shadow_servants = pending > 0 and pending or nil
        return nil
    end

    if pet.SaveSpawnPoint ~= nil then
        pet:SaveSpawnPoint()
    end

    LinkFreeShadowServantToMaster(pet, master)

    return pet
end

return {
    IsTirelessServant1Active = IsTirelessServant1Active,
    IsTirelessServant2Active = IsTirelessServant2Active,
    IsFreeShadowServant = IsFreeShadowServant,
    MarkFreeShadowServant = MarkFreeShadowServant,
    ClearFreeShadowServantMasterLink = ClearFreeShadowServantMasterLink,
    LinkFreeShadowServantToMaster = LinkFreeShadowServantToMaster,
    HasTirelessServant1WorkerBuff = HasTirelessServant1WorkerBuff,
    MarkTirelessServant1WorkerBuff = MarkTirelessServant1WorkerBuff,
    CountFreeShadowServants = CountFreeShadowServants,
    ApplyTirelessServant1ToWorker = ApplyTirelessServant1ToWorker,
    StartFreeShadowServantTintWatcher = StartFreeShadowServantTintWatcher,
    TrySpawnTirelessServant2Worker = TrySpawnTirelessServant2Worker,
}
