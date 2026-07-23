local easing = require("easing")

local SHADOW_TINT = { .08, .08, .08, 1 }
local SHADOW_SPARK_TINT = { .08, .08, .08, 1 }

local function ApplyShadowTint(animstate)
    if animstate ~= nil then
        animstate:SetMultColour(unpack(SHADOW_TINT))
        animstate:SetAddColour(0, 0, 0, 0)
        animstate:SetLightOverride(0)
    end
end

local aoe_assets =
{
    Asset("ANIM", "anim/slingshotammo.zip"),
}

local shatter_assets =
{
    Asset("ANIM", "anim/frozen_shatter.zip"),
}

local spark_assets =
{
    Asset("ANIM", "anim/elec_hit_fx.zip"),
    Asset("ANIM", "anim/elec_immune_fx.zip"),
}

local function RefreshDiscColor(inst)
    local a =
        inst.delta > 0 and
        easing.outQuad(inst.alpha, 0, 1, 1) or
        easing.inQuad(inst.alpha, 0, 1, 1)

    inst.AnimState:SetMultColour(SHADOW_TINT[1], SHADOW_TINT[2], SHADOW_TINT[3], a)
end

local function OnUpdateDisc(inst)
    if inst.delta > 0 then
        if inst.alpha < 1 then
            inst.alpha = math.min(1, inst.alpha + inst.delta)
            RefreshDiscColor(inst)
            if inst.alpha >= 1 then
                inst.delta = -0.1
            end
        end
    elseif inst.alpha > 0 then
        inst.alpha = math.max(0, inst.alpha + inst.delta)
        RefreshDiscColor(inst)
        if inst.alpha <= 0 then
            inst:Hide()
        end
    end
end

local function CreateDarkDisc()
    local inst = CreateEntity()

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")
    inst.persists = false

    inst.entity:AddTransform()
    inst.entity:AddAnimState()

    inst.AnimState:SetBank("slingshotammo")
    inst.AnimState:SetBuild("slingshotammo")
    inst.AnimState:PlayAnimation("target_fx_ring")
    inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    inst.AnimState:SetLayer(LAYER_WORLD_BACKGROUND)
    inst.AnimState:SetSortOrder(3)

    inst:AddComponent("updatelooper")
    inst.components.updatelooper:AddOnUpdateFn(OnUpdateDisc)

    inst.alpha = 0.75
    inst.delta = 0.25
    RefreshDiscColor(inst)

    return inst
end

local function ShadowMarksmanAOEFn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")

    inst.AnimState:SetBank("slingshotammo")
    inst.AnimState:SetBuild("slingshotammo")
    inst.AnimState:PlayAnimation("target_fx_pst")
    inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    inst.AnimState:SetLayer(LAYER_WORLD_BACKGROUND)
    inst.AnimState:SetSortOrder(3)
    inst.AnimState:SetFinalOffset(1)
    ApplyShadowTint(inst.AnimState)

    if not TheNet:IsDedicated() then
        local disc = CreateDarkDisc()
        disc.entity:SetParent(inst.entity)
    end

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:ListenForEvent("animover", inst.Remove)
    inst.persists = false

    return inst
end

local shatterlevels =
{
    { anim = "tiny" },
    { anim = "small" },
    { anim = "medium" },
    { anim = "large" },
    { anim = "huge" },
}

local function PlayShadowShatterAnim(proxy)
    local inst = CreateEntity()

    inst:AddTag("FX")
    inst.entity:SetCanSleep(false)
    inst.persists = false

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()

    local parent = proxy.entity:GetParent()
    if parent ~= nil then
        inst.entity:SetParent(parent.entity)
    end

    inst.Transform:SetFromProxy(proxy.GUID)

    inst.AnimState:SetBank("frozen_shatter")
    inst.AnimState:SetBuild("frozen_shatter")
    inst.AnimState:SetFinalOffset(3)
    ApplyShadowTint(inst.AnimState)

    inst.SoundEmitter:PlaySound("dontstarve/common/break_iceblock")

    inst:AddComponent("shatterfx")
    inst.components.shatterfx.levels = shatterlevels
    inst.components.shatterfx:SetLevel(proxy._level:value())

    inst:ListenForEvent("animover", inst.Remove)
end

local function OnShadowLevelDirty(inst)
    if inst._complete or inst._level:value() <= 0 then
        return
    end

    inst:DoTaskInTime(0, PlayShadowShatterAnim)
    inst._complete = true
end

local function ShadowMarksmanShatterFn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddNetwork()

    inst.Transform:SetTwoFaced()
    inst:AddTag("FX")

    inst._level = net_tinybyte(inst.GUID, "_level", "leveldirty")

    if not TheNet:IsDedicated() then
        inst._complete = false
        inst:ListenForEvent("leveldirty", OnShadowLevelDirty)
    end

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("shatterfx")
    function inst.components.shatterfx:SetLevel(level)
        inst._level:set(level)
    end

    inst.persists = false
    inst:DoTaskInTime(1, inst.Remove)

    return inst
end

local function OnSparkUpdate(inst, dt)
    inst.Light:SetIntensity(inst.i)
    inst.i = inst.i - dt * 2
    if inst.i <= 0 then
        if inst.killfx then
            inst:Remove()
        else
            inst.task:Cancel()
            inst.task = nil
        end
    end
end

local function OnSparkAnimOver(inst)
    if inst.task == nil then
        inst:Remove()
    else
        inst:RemoveEventCallback("animover", OnSparkAnimOver)
        inst.killfx = true
    end
end

local function StartShadowSparkFX(proxy, animindex, build, sound)
    local inst = CreateEntity()

    inst:AddTag("FX")
    inst.entity:SetCanSleep(false)
    inst.persists = false

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    if not TheNet:IsDedicated() then
        inst.entity:AddSoundEmitter()
    end
    inst.entity:AddLight()

    local parent = proxy.entity:GetParent()
    if parent ~= nil then
        inst.entity:SetParent(parent.entity)
    end
    inst.Transform:SetFromProxy(proxy.GUID)

    inst.AnimState:SetBank(build)
    inst.AnimState:SetBuild(build)
    inst.AnimState:PlayAnimation("sparks_"..tostring(animindex))
    inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
    inst.AnimState:SetMultColour(unpack(SHADOW_SPARK_TINT))
    inst.AnimState:SetAddColour(0, 0, 0, 0)
    inst.AnimState:SetLightOverride(.2)

    inst.Light:Enable(true)
    inst.Light:SetRadius(1.5)
    inst.Light:SetFalloff(1)
    inst.Light:SetIntensity(.6)
    inst.Light:SetColour(.1, .1, .1)

    local dt = 1 / 20
    inst.i = .6
    if inst.SoundEmitter ~= nil and sound ~= nil then
        inst.SoundEmitter:PlaySound(sound)
    end
    inst.task = inst:DoPeriodicTask(dt, OnSparkUpdate, nil, dt)

    inst:ListenForEvent("animover", OnSparkAnimOver)
end

local function MakeShadowSparks(name, build, sound)
    local function OnRandDirty(inst)
        if inst._complete or inst._rand:value() <= 0 then
            return
        end

        inst:DoTaskInTime(0, StartShadowSparkFX, inst._rand:value(), build, sound)
        inst._complete = true
    end

    local function fn()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddNetwork()

        inst:AddTag("FX")

        inst.Transform:SetScale(2, 2, 2)

        inst._rand = net_tinybyte(inst.GUID, "_rand", "randdirty")
        inst._complete = false
        inst:ListenForEvent("randdirty", OnRandDirty)

        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst.persists = false
        inst:DoTaskInTime(1, inst.Remove)
        inst._rand:set(math.random(3))

        inst.AlignToTarget = function(proxy, target, attacker)
            local x, y, z = target.Transform:GetWorldPosition()
            local x1, y1, z1 = attacker.Transform:GetWorldPosition()
            local dx, dz = x1 - x, z1 - z
            local len = math.sqrt(dx * dx + dz * dz)
            local r = len ~= 0 and (target:GetPhysicsRadius(0) + .2) / len or 0
            proxy.Transform:SetPosition(x + dx * r, y + 1, z + dz * r)
        end

        return inst
    end

    return Prefab(name, fn, spark_assets)
end

return Prefab("shadow_marksman_aoe_fx", ShadowMarksmanAOEFn, aoe_assets),
    Prefab("shadow_marksman_shatter", ShadowMarksmanShatterFn, shatter_assets),
    MakeShadowSparks("shadow_marksman_electrichitsparks", "elec_hit_fx"),
    MakeShadowSparks("shadow_marksman_electrichitsparks_electricimmune", "elec_immune_fx", "dontstarve/common/together/electricity/electrocute_immune")
