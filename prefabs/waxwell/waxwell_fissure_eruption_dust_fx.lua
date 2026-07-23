local V = require("skill_effect/waxwell/emperor/fissure_eruption/variables")

local assets =
{
    Asset("ANIM", "anim/sinkhole_spawn_fx.zip"),
}

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    local scale = (V.FISSURE_ERUPTION_VISUAL_SCALE or 2) * (.8 + math.random() * .2)
    local tint = V.FISSURE_ERUPTION_TINT or .10
    local flip = math.random() < .5 and -1 or 1

    inst.AnimState:SetBank("sinkhole_spawn_fx")
    inst.AnimState:SetBuild("sinkhole_spawn_fx")
    inst.AnimState:PlayAnimation("idle"..tostring(math.random(3)))
    inst.AnimState:SetMultColour(tint, tint, tint, 1)
    inst.Transform:SetScale(flip * scale, scale, scale)

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")
    inst:AddTag("NOBLOCK")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false
    inst:ListenForEvent("animover", inst.Remove)
    inst:DoTaskInTime(2, inst.Remove)

    return inst
end

return Prefab("waxwell_fissure_eruption_dust_fx", fn, assets)
