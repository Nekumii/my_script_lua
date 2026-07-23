-- Umbral Rift point-1 mark. Persistent networked FX that marks the pending
-- warp source while the player selects point 2. Server-owned; the replicated
-- "waxwell_umbral_rift_mark" tag lets clients detect it (phase + placement check).

local assets =
{
    Asset("ANIM", "anim/reticuleaoe.zip"),
}

local MARK_TAG = "waxwell_umbral_rift_mark"
local BANK = "reticuleaoe"
local BUILD = "reticuleaoe"
local ANIM = "idle_target_1d2"
local COLOUR = { .3, .5, .2, 1 }
local SCALE = 1.5
local FADE_FRAMES = 6

local function DoFade(inst, from, to, ondone)
    if inst._fadetask ~= nil then
        inst._fadetask:Cancel()
        inst._fadetask = nil
    end

    local elapsed = 0
    local total = FADE_FRAMES * FRAMES
    inst._fadetask = inst:DoPeriodicTask(FRAMES, function()
        elapsed = elapsed + FRAMES
        local t = total > 0 and math.min(1, elapsed / total) or 1
        local a = Lerp(from, to, t)
        inst.AnimState:OverrideMultColour(COLOUR[1], COLOUR[2], COLOUR[3], a)
        if t >= 1 then
            if inst._fadetask ~= nil then
                inst._fadetask:Cancel()
                inst._fadetask = nil
            end
            if ondone ~= nil then
                ondone(inst)
            end
        end
    end)
end

local function KillFX(inst)
    if inst._killing then
        return
    end
    inst._killing = true
    DoFade(inst, COLOUR[4], 0, inst.Remove)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")
    inst:AddTag(MARK_TAG)

    inst.AnimState:SetBank(BANK)
    inst.AnimState:SetBuild(BUILD)
    inst.AnimState:PlayAnimation(ANIM, true)
    inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGroundFixed)
    inst.AnimState:SetLayer(LAYER_BACKGROUND)
    inst.AnimState:SetSortOrder(3)
    inst.AnimState:SetScale(SCALE, SCALE)
    inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
    -- ตั้ง alpha เต็มตั้งแต่แรก เพราะ OverrideMultColour ไม่ replicate ไปยัง client
    -- (client จะเห็น mark ทันที, host เล่น fade-in เพิ่มด้านล่าง)
    inst.AnimState:OverrideMultColour(COLOUR[1], COLOUR[2], COLOUR[3], COLOUR[4])

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false
    inst.KillFX = KillFX

    -- fade-in เฉพาะฝั่ง host (server) — cosmetic
    DoFade(inst, 0, COLOUR[4])

    return inst
end

return Prefab("umbral_rift_mark", fn, assets)
