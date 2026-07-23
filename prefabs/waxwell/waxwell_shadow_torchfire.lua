local MakeTorchFire = require("prefabs/torchfire_common")

local SMOKE_TEXTURE = "fx/smoke.tex"
local TEXTURE = "fx/torchfire.tex"
local SHADER = "shaders/vfx_particle.ksh"

local COLOUR_ENVELOPE_NAME_SMOKE = "waxwell_shadow_firesmokecolourenvelope"
local SCALE_ENVELOPE_NAME_SMOKE = "waxwell_shadow_firesmokescaleenvelope"
local COLOUR_ENVELOPE_NAME = "waxwell_shadow_firecolourenvelope"
local SCALE_ENVELOPE_NAME = "waxwell_shadow_firescaleenvelope"

local assets =
{
    Asset("IMAGE", TEXTURE),
    Asset("SHADER", SHADER),
}

local function IntColour(r, g, b, a)
    return { r / 255, g / 255, b / 255, a / 255 }
end

local function InitEnvelope()
    EnvelopeManager:AddColourEnvelope(
        COLOUR_ENVELOPE_NAME_SMOKE,
        {
            { 0,    IntColour(2, 2, 2, 0) },
            { .3,   IntColour(2, 2, 2, 100) },
            { .55,  IntColour(2, 2, 2, 28) },
            { 1,    IntColour(2, 2, 2, 0) },
        }
    )

    local smoke_max_scale = 1.25
    EnvelopeManager:AddVector2Envelope(
        SCALE_ENVELOPE_NAME_SMOKE,
        {
            { 0,    { smoke_max_scale * .4, smoke_max_scale * .4} },
            { .50,  { smoke_max_scale * .6, smoke_max_scale * .6} },
            { .65,  { smoke_max_scale * .9, smoke_max_scale * .9} },
            { 1,    { smoke_max_scale, smoke_max_scale} },
        }
    )

    EnvelopeManager:AddColourEnvelope(
        COLOUR_ENVELOPE_NAME,
        {
            { 0,    IntColour(9, 6, 3, 128) },
            { .49,  IntColour(9, 6, 3, 128) },
            { .5,   IntColour(13, 13, 0, 128) },
            { .51,  IntColour(13, 2, 3, 128) },
            { .75,  IntColour(13, 2, 3, 128) },
            { 1,    IntColour(13, 0, 1, 0) },
        }
    )

    local max_scale = 3
    EnvelopeManager:AddVector2Envelope(
        SCALE_ENVELOPE_NAME,
        {
            { 0,    { max_scale * .5, max_scale } },
            { 1,    { max_scale * .5 * .5, max_scale * .5 } },
        }
    )

    InitEnvelope = nil
    IntColour = nil
end

local FIRE_MAX_LIFETIME = .3
local SMOKE_MAX_LIFETIME = .7

local function emit_smoke_fn(effect, sphere_emitter)
    local vx, vy, vz = .01 * UnitRand(), .05, .01 * UnitRand()
    local lifetime = SMOKE_MAX_LIFETIME * (.9 + UnitRand() * .1)
    local px, py, pz = sphere_emitter()
    local uv_offset = math.random(0, 3) * .25

    effect:AddParticleUV(
        0,
        lifetime,
        px, py, pz,
        vx, vy, vz,
        uv_offset, 0
    )
end

local function emit_fire_fn(effect, sphere_emitter)
    local vx, vy, vz = .01 * UnitRand(), 0, .01 * UnitRand()
    local lifetime = FIRE_MAX_LIFETIME * (.9 + UnitRand() * .1)
    local px, py, pz = sphere_emitter()
    local uv_offset = math.random(0, 3) * .25

    effect:AddParticleUV(
        1,
        lifetime,
        px, py, pz,
        vx, vy, vz,
        uv_offset, 0
    )
end

local function common_postinit(inst)
    if TheNet:IsDedicated() then
        return
    elseif InitEnvelope ~= nil then
        InitEnvelope()
    end

    local effect = inst.entity:AddVFXEffect()
    effect:InitEmitters(2)

    effect:SetRenderResources(0, SMOKE_TEXTURE, SHADER)
    effect:SetMaxNumParticles(0, 64)
    effect:SetMaxLifetime(0, SMOKE_MAX_LIFETIME)
    effect:SetColourEnvelope(0, COLOUR_ENVELOPE_NAME_SMOKE)
    effect:SetScaleEnvelope(0, SCALE_ENVELOPE_NAME_SMOKE)
    effect:SetBlendMode(0, BLENDMODE.Premultiplied)
    effect:EnableBloomPass(0, true)
    effect:SetUVFrameSize(0, .25, 1)
    effect:SetSortOrder(0, 0)
    effect:SetSortOffset(0, 1)
    effect:SetRadius(0, 2)

    effect:SetRenderResources(1, TEXTURE, SHADER)
    effect:SetMaxNumParticles(1, 64)
    effect:SetMaxLifetime(1, FIRE_MAX_LIFETIME)
    effect:SetColourEnvelope(1, COLOUR_ENVELOPE_NAME)
    effect:SetScaleEnvelope(1, SCALE_ENVELOPE_NAME)
    effect:SetBlendMode(1, BLENDMODE.Additive)
    effect:EnableBloomPass(1, true)
    effect:SetUVFrameSize(1, .25, 1)
    effect:SetSortOrder(1, 0)
    effect:SetSortOffset(1, 2)

    local tick_time = TheSim:GetTickTime()

    local smoke_desired_pps = 80
    local smoke_particles_per_tick = smoke_desired_pps * tick_time
    local smoke_num_particles_to_emit = -50

    local fire_desired_pps = 40
    local fire_particles_per_tick = fire_desired_pps * tick_time
    local fire_num_particles_to_emit = 1

    local sphere_emitter = CreateSphereEmitter(.05)

    EmitterManager:AddEmitter(inst, nil, function()
        while smoke_num_particles_to_emit > 1 do
            emit_smoke_fn(effect, sphere_emitter)
            smoke_num_particles_to_emit = smoke_num_particles_to_emit - 1
        end
        smoke_num_particles_to_emit = smoke_num_particles_to_emit + smoke_particles_per_tick

        while fire_num_particles_to_emit > 1 do
            emit_fire_fn(effect, sphere_emitter)
            fire_num_particles_to_emit = fire_num_particles_to_emit - 1
        end
        fire_num_particles_to_emit = fire_num_particles_to_emit + fire_particles_per_tick
    end)
end

local function master_postinit(inst)
    inst.fx_offset = -110

    if inst._light ~= nil and inst._light.Light ~= nil then
        inst._light.Light:SetColour(.05, .05, .05)
        inst._light.Light:SetIntensity(.04)
    end
end

return MakeTorchFire("waxwell_shadow_torchfire", assets, nil, common_postinit, master_postinit)
