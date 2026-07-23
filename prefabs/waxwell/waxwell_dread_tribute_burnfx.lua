local V = require("skill_effect/waxwell/sovereign/dread_tribute/variables")

local assets =
{
    Asset("ANIM", "anim/fire_large_character.zip"),
}

local function DarkColour(r, g, b)
    local m = V.BURN_FX_TINT.r
    return { r * m, g * m, b * m }
end

local firelevels =
{
    {
        anim = "loop_small",
        pre = "pre_small",
        pst = "post_small",
        pst_fast = "post_small_fast",
        anim_controlled_burn = "loop_small_controlled_burn",
        pre_controlled_burn = "pre_small_controlled_burn",
        pst_controlled_burn = "post_small_controlled_burn",
        sound = nil,
        radius = 0,
        intensity = 0,
        falloff = 1,
        colour = DarkColour(197 / 255, 197 / 255, 170 / 255),
        soundintensity = 0,
    },
    {
        anim = "loop_med",
        pre = "pre_med",
        pst = "post_med",
        pst_fast = "post_med_fast",
        anim_controlled_burn = "loop_med_controlled_burn",
        pre_controlled_burn = "pre_med_controlled_burn",
        pst_controlled_burn = "post_med_controlled_burn",
        sound = nil,
        radius = 0,
        intensity = 0,
        falloff = 1,
        colour = DarkColour(1, 1, 192 / 255),
        soundintensity = 0,
    },
    {
        anim = "loop_large",
        pre = "pre_large",
        pst = "post_large",
        pst_fast = "post_large_fast",
        anim_controlled_burn = "loop_large_controlled_burn",
        pre_controlled_burn = "pre_large_controlled_burn",
        pst_controlled_burn = "post_large_controlled_burn",
        sound = nil,
        radius = 0,
        intensity = 0,
        falloff = 1,
        colour = DarkColour(197 / 255, 197 / 255, 170 / 255),
        soundintensity = 0,
    },
}

local function DisableFireLight(inst)
    local firefx = inst.components ~= nil and inst.components.firefx or nil
    if firefx ~= nil and firefx.light ~= nil and firefx.light.Light ~= nil then
        firefx.light.Light:Enable(false)
    end
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("fire_large_character")
    inst.AnimState:SetBuild("fire_large_character")
    inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
    inst.AnimState:SetRayTestOnBB(true)
    inst.AnimState:SetFinalOffset(FINALOFFSET_MAX)
    inst.AnimState:SetMultColour(V.BURN_FX_TINT.r, V.BURN_FX_TINT.g, V.BURN_FX_TINT.b, V.BURN_FX_TINT.a)

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false

    inst:AddComponent("firefx")
    inst.components.firefx.levels = firelevels
    inst.components.firefx.playignitesound = false
    inst.components.firefx.extinguishsoundtest = function()
        return false
    end

    inst:DoTaskInTime(0, DisableFireLight)

    return inst
end

return Prefab("waxwell_dread_tribute_burnfx", fn, assets)
