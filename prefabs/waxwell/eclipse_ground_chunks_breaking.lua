local assets =
{
    Asset("ANIM", "anim/ground_chunks_breaking.zip"),
}

local function PlayChunksAnim(proxy)
    local inst = CreateEntity()

    inst:AddTag("FX")
    inst.entity:SetCanSleep(false)
    inst.persists = false

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()

    inst.Transform:SetFromProxy(proxy.GUID)

    inst.AnimState:SetBank("ground_breaking")
    inst.AnimState:SetBuild("ground_chunks_breaking")
    inst.AnimState:PlayAnimation("idle")
    inst.AnimState:SetFinalOffset(3)
    inst.AnimState:OverrideMultColour(0, 0, 0, 1)

    inst.SoundEmitter:PlaySound("dontstarve/common/stone_drop")

    inst:ListenForEvent("animover", inst.Remove)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddNetwork()

    inst:AddTag("FX")

    if not TheNet:IsDedicated() then
        inst:DoTaskInTime(0, PlayChunksAnim)
    end

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false
    inst:DoTaskInTime(1, inst.Remove)

    return inst
end

return Prefab("eclipse_ground_chunks_breaking", fn, assets)
