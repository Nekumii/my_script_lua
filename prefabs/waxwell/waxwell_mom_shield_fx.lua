local assets =
{
    Asset("ANIM", "anim/stalker_shield.zip"),
}

-- Visual-only stalker shield (no repel / damage from vanilla stalker_shield).
local PLAYER_SCALE = 1.05

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")

    local n = math.random(1, 3)
    inst.AnimState:SetBank("stalker_shield")
    inst.AnimState:SetBuild("stalker_shield")
    inst.AnimState:PlayAnimation("idle"..tostring(n))
    inst.AnimState:SetFinalOffset(2)
    if math.random() < .5 then
        inst.AnimState:SetScale(-PLAYER_SCALE, PLAYER_SCALE, PLAYER_SCALE)
    else
        inst.AnimState:SetScale(PLAYER_SCALE, PLAYER_SCALE, PLAYER_SCALE)
    end

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/shield")
    inst.persists = false
    inst:ListenForEvent("animover", inst.Remove)
    inst:DoTaskInTime(inst.AnimState:GetCurrentAnimationLength() + FRAMES, inst.Remove)

    return inst
end

return Prefab("waxwell_mom_shield_fx", fn, assets)
