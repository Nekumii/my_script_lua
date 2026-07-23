local Lifecycle = require("skill_effect/waxwell/_shared/shadow_firefly/lifecycle")

local assets =
{
    Asset("ANIM", "anim/fireflies.zip"),
}

local prefabs =
{
    "shadow_despawn",
    "waxwell_shadow_firefly_explodefx",
}

local INTENSITY = .5
local LIGHT_RADIUS = 1.5
local SHADOW_FIREFLY_TINT_ALPHA = .9

local function ApplyShadowFireflyTint(inst)
    if inst.AnimState ~= nil then
        inst.AnimState:SetMultColour(0, 0, 0, SHADOW_FIREFLY_TINT_ALPHA)
    end
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddLight()
    inst.entity:AddNetwork()

    inst.Light:SetFalloff(1)
    inst.Light:SetIntensity(INTENSITY)
    inst.Light:SetRadius(LIGHT_RADIUS)
    inst.Light:SetColour(180 / 255, 195 / 255, 150 / 255)
    inst.Light:Enable(true)
    inst.Light:EnableClientModulation(true)

    inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
    inst.AnimState:SetBank("fireflies")
    inst.AnimState:SetBuild("fireflies")
    inst.AnimState:SetRayTestOnBB(true)
    inst.AnimState:PlayAnimation("swarm_loop", true)
    ApplyShadowFireflyTint(inst)

    inst.entity:SetCanSleep(false)

    inst:AddTag("waxwell_shadow_firefly")
    inst:AddTag("flying")
    inst:AddTag("NOBLOCK")
    inst:AddTag("NOCLICK")
    inst:AddTag("noplayertarget")
    inst:AddTag("scarytoprey")
    inst:AddTag("shadow")

    inst.FadeOutAndRemove = Lifecycle.FadeOutAndRemove
    inst.ForceDespawn = Lifecycle.ForceDespawn

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        inst:DoPeriodicTask(1, ApplyShadowFireflyTint)
        return inst
    end

    inst:AddComponent("health")
    inst.components.health:SetMaxHealth(1)
    inst.components.health.nofadeout = true
    inst.components.health.redirect = function(inst, amount)
        if amount ~= nil and amount < 0 and not inst._shadow_firefly_fading then
            inst._shadow_firefly_killed_by_combat = true
        end
    end

    inst:AddComponent("combat")
    inst.components.combat.hiteffectsymbol = "fireflies"
    inst.components.combat:SetDefaultDamage(0)
    inst.components.combat:SetRange(0)
    inst.components.combat:SetAttackPeriod(10)

    inst:DoPeriodicTask(1, ApplyShadowFireflyTint)

    return inst
end

return Prefab("waxwell_shadow_firefly", fn, assets, prefabs)
