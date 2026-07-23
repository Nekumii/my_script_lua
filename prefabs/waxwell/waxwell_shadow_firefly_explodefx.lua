local assets =
{
    Asset("ANIM", "anim/deer_fire_charge.zip"),
}

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")

    inst.entity:SetCanSleep(false)
    inst.persists = false

    inst.AnimState:SetBank("deer_fire_charge")
    inst.AnimState:SetBuild("deer_fire_charge")
    inst.AnimState:SetMultColour(0, 0, 0, .6)
    inst.AnimState:PlayAnimation("blast")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.SoundEmitter:PlaySound("dontstarve/common/deathpoof")
    inst:ListenForEvent("animover", inst.Remove)
    inst:DoTaskInTime(2, inst.Remove)

    return inst
end

return Prefab("waxwell_shadow_firefly_explodefx", fn, assets)
