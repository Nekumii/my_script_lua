-- Visual-only falling fossil swords for Domain Expansion (no damage).
local V = require("skill_effect/waxwell/emperor/domain_expansion/variables")

local assets =
{
    Asset("ANIM", "anim/fossil_spike2.zip"),
}

local SHADOW_TINT_ALPHA = .75
local NUM_VARIATIONS = 7
local SHADOW_SIZE = { 1.2, .75 }

local function ApplyShadowTint(inst)
    inst.AnimState:SetMultColour(0, 0, 0, SHADOW_TINT_ALPHA)
end

local SHADOW_DELTA2 = -.2
local function UpdateShadow2(inst)
    if inst.shadowtask ~= nil then
        inst.shadowtask:Cancel()
        inst.shadowtask = nil
    end
    inst.shadowsize = inst.shadowsize + SHADOW_DELTA2
    local k = 1 - inst.shadowsize
    k = 1 - k * k
    if k <= .5 then
        k = .5
        if inst.shadowtask2 ~= nil then
            inst.shadowtask2:Cancel()
            inst.shadowtask2 = nil
        end
    end
    inst.DynamicShadow:SetSize(k * SHADOW_SIZE[1], k * SHADOW_SIZE[2])
end

local SHADOW_DELTA = .05
local function UpdateShadow(inst)
    inst.shadowsize = inst.shadowsize + SHADOW_DELTA
    if inst.shadowsize > 0 then
        inst.DynamicShadow:Enable(true)
        if inst.shadowsize >= 1 then
            inst.shadowsize = 1
            if inst.shadowtask ~= nil then
                inst.shadowtask:Cancel()
                inst.shadowtask = nil
            end
        end
    end
    local k = inst.shadowsize * inst.shadowsize
    inst.DynamicShadow:SetSize(k * SHADOW_SIZE[1], k * SHADOW_SIZE[2])
end

local LIGHT_DELTA = .03
local function UpdateLight(inst)
    inst.lightvalue = inst.lightvalue + LIGHT_DELTA
    if inst.lightvalue >= 1 then
        inst.lightvalue = 1
        if inst.lighttask ~= nil then
            inst.lighttask:Cancel()
            inst.lighttask = nil
        end
    end
    inst.AnimState:SetLightOverride(0)
end

local function CancelFxTasks(inst)
    if inst.shadowtask ~= nil then
        inst.shadowtask:Cancel()
        inst.shadowtask = nil
    end
    if inst.shadowtask2 ~= nil then
        inst.shadowtask2:Cancel()
        inst.shadowtask2 = nil
    end
    if inst.lighttask ~= nil then
        inst.lighttask:Cancel()
        inst.lighttask = nil
    end
    if inst._freeze_task ~= nil then
        inst._freeze_task:Cancel()
        inst._freeze_task = nil
    end
end

local function StartAppearFx(inst)
    inst.shadowsize = 0
    CancelFxTasks(inst)
    inst.shadowtask = inst:DoPeriodicTask(0, UpdateShadow)
    inst.shadowtask2 = inst:DoPeriodicTask(0, UpdateShadow2, 43 * FRAMES)
    inst.lightvalue = 0
    inst.lighttask = inst:DoPeriodicTask(0, UpdateLight)
end

local function FreezeImpactPose(inst)
    if inst == nil or not inst:IsValid() or inst._frozen or inst._finishing then
        return
    end

    inst._frozen = true
    local pct = V.DOMAIN_EXPANSION_SPIKE_FREEZE_PERCENT or .82
    inst.AnimState:SetPercent("impact", pct)
    if inst.AnimState.Pause ~= nil then
        inst.AnimState:Pause()
    end
end

local function StopImpactFxTasks(inst)
    if inst.lighttask ~= nil then
        inst.lighttask:Cancel()
        inst.lighttask = nil
    end
    inst.AnimState:SetLightOverride(0)

    if inst.shadowtask ~= nil then
        inst.shadowtask:Cancel()
        inst.shadowtask = nil
    end
    if inst.shadowtask2 ~= nil then
        inst.shadowtask2:Cancel()
        inst.shadowtask2 = nil
    end
    inst.DynamicShadow:Enable(false)
end

local function OnImpact(inst)
    inst:RemoveEventCallback("animover", OnImpact)
    if inst._finishing and not inst._frozen then
        -- Finishing while still falling: play impact once, then remove.
        inst.AnimState:PlayAnimation("impact")
        ApplyShadowTint(inst)
        StopImpactFxTasks(inst)
        if inst.basefx == nil then
            inst.basefx = SpawnPrefab("shadow_stalker_fossilspike2_base")
            if inst.basefx ~= nil then
                inst.basefx.entity:SetParent(inst.entity)
            end
        end
        if inst.SoundEmitter ~= nil then
            inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/fossil_spike")
        end
        inst:ListenForEvent("animover", inst.Remove)
        return
    end

    inst.AnimState:PlayAnimation("impact")
    ApplyShadowTint(inst)
    StopImpactFxTasks(inst)

    inst.basefx = SpawnPrefab("shadow_stalker_fossilspike2_base")
    if inst.basefx ~= nil then
        inst.basefx.entity:SetParent(inst.entity)
    end

    if inst.SoundEmitter ~= nil then
        inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/fossil_spike")
    end

    if inst._finishing then
        inst:ListenForEvent("animover", inst.Remove)
        return
    end

    local len = inst.AnimState:GetCurrentAnimationLength()
    local pct = V.DOMAIN_EXPANSION_SPIKE_FREEZE_PERCENT or .82
    inst._freeze_task = inst:DoTaskInTime(math.max(0, len * pct), FreezeImpactPose)
end

local function OnAppearOver(inst)
    inst:RemoveEventCallback("animover", OnAppearOver)
    OnImpact(inst)
end

local function BeginFall(inst, variation)
    variation = variation or math.random(NUM_VARIATIONS)
    if variation > 1 then
        inst.AnimState:OverrideSymbol("bone1", "fossil_spike2", "bone"..tostring(variation))
    end

    inst.AnimState:PlayAnimation("appear")
    ApplyShadowTint(inst)
    StartAppearFx(inst)
    inst:ListenForEvent("animover", OnAppearOver)

    if inst.SoundEmitter ~= nil then
        inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/out", nil, 0.35)
    end
end

local function FinishAndRemove(inst)
    if inst == nil or not inst:IsValid() or inst._finishing then
        return
    end

    inst._finishing = true
    CancelFxTasks(inst)

    if inst._frozen then
        -- Resume planted pose from freeze point and let impact finish.
        if inst.AnimState.Resume ~= nil then
            inst.AnimState:Resume()
        end
        local pct = V.DOMAIN_EXPANSION_SPIKE_FREEZE_PERCENT or .82
        inst.AnimState:PlayAnimation("impact")
        ApplyShadowTint(inst)
        local frames = inst.AnimState:GetCurrentAnimationNumFrames()
        if frames ~= nil and frames > 1 then
            inst.AnimState:SetFrame(math.max(0, math.floor(frames * pct) - 1))
        end
        inst:ListenForEvent("animover", inst.Remove)
        return
    end

    if inst.AnimState:IsCurrentAnimation("appear") then
        -- Already listening for appear → impact → remove via OnImpact finishing branch.
        return
    end

    if inst.AnimState:IsCurrentAnimation("impact") then
        if inst.AnimState.Resume ~= nil then
            inst.AnimState:Resume()
        end
        inst:ListenForEvent("animover", inst.Remove)
        return
    end

    -- Not started / empty: remove immediately.
    inst:Remove()
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddDynamicShadow()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("fossil_spike2")
    inst.AnimState:SetBuild("fossil_spike2")
    inst.AnimState:PlayAnimation("empty")
    inst.AnimState:SetFinalOffset(1)
    inst.AnimState:SetLightOverride(0)
    ApplyShadowTint(inst)

    inst.DynamicShadow:Enable(false)

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")
    inst:AddTag("NOBLOCK")
    inst:AddTag("notarget")
    inst:AddTag("domain_expansion_spike")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false
    inst._frozen = false
    inst._finishing = false
    inst.BeginFall = BeginFall
    inst.FinishAndRemove = FinishAndRemove

    inst:ListenForEvent("onremove", CancelFxTasks)

    return inst
end

return Prefab("domain_expansion_spike_fx", fn, assets)
