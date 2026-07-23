local assets =
{
    Asset("ANIM", "anim/burntground.zip"),
}

local HOLD_TIME = 1.2
local FADE_TIME = 1.8
local UPDATE_INTERVAL = FRAMES

local function Clamp(value, minvalue, maxvalue)
    return value < minvalue and minvalue or (value > maxvalue and maxvalue or value)
end

local function UpdateFade(inst)
    local elapsed = GetTime() - (inst._spawn_time or GetTime())
    local alpha

    if elapsed <= HOLD_TIME then
        alpha = 1
    else
        alpha = 1 - Clamp((elapsed - HOLD_TIME) / FADE_TIME, 0, 1)
    end

    inst.AnimState:OverrideMultColour(0, 0, 0, alpha)

    if alpha <= 0 then
        inst:Remove()
    end
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    inst.AnimState:SetBuild("burntground")
    inst.AnimState:SetBank("burntground")
    inst.AnimState:PlayAnimation("idle")
    inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    inst.AnimState:SetLayer(LAYER_GROUND)
    inst.AnimState:SetSortOrder(3)
    inst.AnimState:OverrideMultColour(0, 0, 0, 1)

    inst:AddTag("NOCLICK")
    inst:AddTag("FX")

    inst.entity:SetPristine()

    inst._spawn_time = GetTime()
    UpdateFade(inst)
    inst:DoPeriodicTask(UPDATE_INTERVAL, UpdateFade)

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false

    return inst
end

return Prefab("eclipse_burntground", fn, assets)
