local assets =
{
    Asset("ANIM", "anim/slingshotammo.zip"),
}

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("slingshotammo")
    inst.AnimState:SetBuild("slingshotammo")
    inst.AnimState:PlayAnimation("used")
    inst.AnimState:SetMultColour(0.08, 0.08, 0.08, 1)
    inst.AnimState:SetAddColour(0, 0, 0, 0)
    inst.AnimState:SetLightOverride(0)
    inst.AnimState:SetFinalOffset(3)

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")
    inst.persists = false

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.SoundEmitter:PlaySound("dontstarve/characters/walter/slingshot/rock")
    inst:ListenForEvent("animover", inst.Remove)

    return inst
end

return Prefab("shadow_marksman_hitfx", fn, assets)
