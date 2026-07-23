local assets =
{
    Asset("ANIM", "anim/shadow_pillar.zip"),
}

local prefabs =
{
    "sanity_raise",
    "sanity_lower",
    "shadow_pillar_base_fx",
}

local NUM_VARIATIONS = 6
local V = require("skill_effect/waxwell/emperor/domain_expansion/variables")

local function DoSplash(inst)
    if TheWorld.Map:IsOceanAtPoint(inst.Transform:GetWorldPosition()) then
        SpawnPrefab("ocean_splash_med"..tostring(math.random(2))).Transform:SetPosition(inst.Transform:GetWorldPosition())
    end
end

local function EnsureBaseFx(inst)
    if inst.base ~= nil and inst.base:IsValid() then
        return
    end

    inst.base = SpawnPrefab("shadow_pillar_base_fx")
    if inst.base ~= nil then
        inst.base.entity:SetParent(inst.entity)
        inst.base.Transform:SetRotation(math.random() * 360)
    end
end

local function EnableBlocking(inst)
    -- Visual-only pillars: soft radial barrier handles blocking smoothly.
end

local function DisableBlocking(inst)
    inst._blocking = false
end

local function StopWarning(inst)
    if not inst._warning then
        return
    end

    inst._warning = false
    if inst.SoundEmitter ~= nil then
        inst.SoundEmitter:KillSound("rumble")
    end

    if not inst._lowering and inst.variation ~= nil then
        inst.AnimState:PlayAnimation("idle"..tostring(inst.variation), true)
        local frames = inst.AnimState:GetCurrentAnimationNumFrames()
        if frames ~= nil and frames > 1 then
            inst.AnimState:SetFrame(math.random(frames) - 1)
        end
    end
end

local function StartWarning(inst)
    if inst._warning or inst._lowering or not inst._raised then
        return
    end

    inst._warning = true
    inst.AnimState:PlayAnimation("shake"..tostring(inst.variation), true)
    if inst.SoundEmitter ~= nil then
        inst.SoundEmitter:PlaySound("maxwell_rework/shadow_pillar/rumble", "rumble")
    end
end

local function SetWarning(inst, active)
    if active then
        StartWarning(inst)
    else
        StopWarning(inst)
    end
end

local function DoRaise(inst)
    inst._delayraisetask = nil
    if inst._lowering then
        return
    end

    inst.variation = math.random(NUM_VARIATIONS)
    if math.random() < .5 then
        inst.flipped = true
        inst.AnimState:SetScale(-1, 1, 1)
    end

    inst.AnimState:SetMultColour(1, 1, 1, 1)
    inst.AnimState:PlayAnimation("pre"..tostring(inst.variation))
    inst.AnimState:PushAnimation("idle"..tostring(inst.variation), true)
    DoSplash(inst)
    EnableBlocking(inst)
    inst._raised = true
    inst._raising = false
end

local function PreRaise(inst)
    inst._delayraisetask = inst:DoTaskInTime(7 * FRAMES, DoRaise)
    EnsureBaseFx(inst)
end

local function BeginRaise(inst, delay)
    if inst._raising or inst._raised or inst._lowering then
        return
    end

    inst._raising = true
    delay = math.max(0, delay or 0)

    inst:DoTaskInTime(delay, function()
        if inst == nil or not inst:IsValid() or inst._lowering then
            return
        end

        if inst.SoundEmitter ~= nil then
            inst.SoundEmitter:PlaySound("maxwell_rework/shadow_pillar/pre")
        end
        SpawnPrefab("sanity_raise").Transform:SetPosition(inst.Transform:GetWorldPosition())
        inst._delayraisetask = inst:DoTaskInTime(8 * FRAMES, PreRaise)
    end)
end

local function DoLower(inst)
    if inst._lowering then
        return
    end

    inst._lowering = true
    StopWarning(inst)
    DisableBlocking(inst)

    if inst._delayraisetask ~= nil then
        inst._delayraisetask:Cancel()
        inst._delayraisetask = nil
    end

    if not inst._raised then
        if inst.base ~= nil and inst.base:IsValid() and inst.base.KillFX ~= nil then
            inst.base:KillFX()
        end
        inst:Remove()
        return
    end

    local variation = inst.variation or 1
    if inst.SoundEmitter ~= nil then
        inst.SoundEmitter:PlaySound("dontstarve/sanity/shadowrock_down")
    end
    SpawnPrefab("sanity_lower").Transform:SetPosition(inst.Transform:GetWorldPosition())

    inst.AnimState:PlayAnimation("pst"..tostring(variation))
    if inst.base ~= nil and inst.base:IsValid() then
        inst.base:DoTaskInTime(2 * FRAMES, inst.base.KillFX)
    end
    inst:DoTaskInTime(10 * FRAMES, DoSplash)
    inst:ListenForEvent("animover", inst.Remove)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("shadow_pillar")
    inst.AnimState:SetBuild("shadow_pillar")
    inst.AnimState:SetSymbolMultColour("shad_spot2", 1, 1, 1, .75)
    inst.AnimState:SetSymbolMultColour("shadow2", 1, 1, 1, .75)
    inst.AnimState:PlayAnimation("idle1")
    inst.AnimState:SetMultColour(1, 1, 1, 0)

    -- Visual-only soft barrier posts. Do NOT tag FX/NOBLOCK/allow_casting —
    -- Umbral Rift deployradius must treat pillars as blockers (no rift on posts).
    inst:AddTag("NOCLICK")
    inst:AddTag("domain_expansion_barrier")

    inst.persists = false
    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst._blocking = false
    inst._raised = false
    inst._raising = false
    inst._lowering = false
    inst._warning = false
    inst.variation = nil
    inst.base = nil

    inst.BeginRaise = BeginRaise
    inst.KillFX = DoLower
    inst.SetWarning = SetWarning

    return inst
end

return Prefab("domain_expansion_barrier_pillar", fn, assets, prefabs)
