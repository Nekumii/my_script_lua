local common = require("skill_effect/waxwell/umbra/_shared/common")
local persist_utils = require("skill_effect/waxwell/_shared/persist_utils")
local V = require("skill_effect/waxwell/umbra/abyssal_binding/variables")

local IsAbyssalBinding1Active = common.IsAbyssalBinding1Active
local IsAbyssalBinding2Active = common.IsAbyssalBinding2Active
local GetShadowPillarsCasterFromSpawnStack = common.GetShadowPillarsCasterFromSpawnStack
local HasAbyssalBinding1ShadowPillar = common.HasAbyssalBinding1ShadowPillar
local HasAbyssalBinding1ShadowPillarTarget = common.HasAbyssalBinding1ShadowPillarTarget
local HasAbyssalBinding2ShadowPillar = common.HasAbyssalBinding2ShadowPillar
local MarkAbyssalBinding1ShadowPillar = common.MarkAbyssalBinding1ShadowPillar
local MarkAbyssalBinding1ShadowPillarTarget = common.MarkAbyssalBinding1ShadowPillarTarget
local MarkAbyssalBinding2ShadowPillar = common.MarkAbyssalBinding2ShadowPillar
local ResumeAbyssalBinding2ShadowPillarImpact = common.ResumeAbyssalBinding2ShadowPillarImpact
local PatchAbyssalBinding1Lifetime = common.PatchAbyssalBinding1Lifetime
local PatchAbyssalBinding2ShadowPillarImpact = common.PatchAbyssalBinding2ShadowPillarImpact

local SHADOW_PILLAR_PERSIST_SPECS = {
    { key = "_waxwell_abyssal_binding_1_shadow_pillar", has = HasAbyssalBinding1ShadowPillar, mark = MarkAbyssalBinding1ShadowPillar },
    { key = "_waxwell_abyssal_binding_2_shadow_pillar", has = HasAbyssalBinding2ShadowPillar, mark = MarkAbyssalBinding2ShadowPillar },
}

local SHADOW_PILLAR_TARGET_PERSIST_SPECS = {
    { key = "_waxwell_abyssal_binding_1_shadow_pillar_target", has = HasAbyssalBinding1ShadowPillarTarget, mark = MarkAbyssalBinding1ShadowPillarTarget },
}

local M = {}

function M.Register(env)
    local AddPrefabPostInit = env.AddPrefabPostInit

    AddPrefabPostInit("shadow_pillar", function(inst)
        if not TheWorld.ismastersim or inst._waxwell_abyssal_binding_shadow_pillar_patched then
            return
        end

        inst._waxwell_abyssal_binding_shadow_pillar_patched = true
        local spawncaster = GetShadowPillarsCasterFromSpawnStack()
        if IsAbyssalBinding1Active(spawncaster) then
            MarkAbyssalBinding1ShadowPillar(inst)
            inst._waxwell_abyssal_binding_1_duration_mult = V.ABYSSAL_BINDING_1_DURATION_MULT
        end
        if IsAbyssalBinding2Active(spawncaster) then
            MarkAbyssalBinding2ShadowPillar(inst)
            inst._waxwell_abyssal_binding_2_caster = spawncaster
            inst._waxwell_abyssal_binding_2_damage = V.ABYSSAL_BINDING_2_DAMAGE
        end

        PatchAbyssalBinding1Lifetime(inst, HasAbyssalBinding1ShadowPillar)
        PatchAbyssalBinding2ShadowPillarImpact(inst)

        local old_OnSave = inst.OnSave
        inst.OnSave = function(shadow_pillar, data, ...)
            if old_OnSave ~= nil then
                old_OnSave(shadow_pillar, data, ...)
            end

            persist_utils.SaveMarkedFlags(data, shadow_pillar, SHADOW_PILLAR_PERSIST_SPECS)
            persist_utils.SaveValue(data, "_waxwell_abyssal_binding_1_duration_mult", shadow_pillar._waxwell_abyssal_binding_1_duration_mult)
            persist_utils.SaveValue(data, "_waxwell_abyssal_binding_2_damage", shadow_pillar._waxwell_abyssal_binding_2_damage)
            persist_utils.SaveFlag(data, "_waxwell_abyssal_binding_2_shadow_pillar_hit", shadow_pillar._waxwell_abyssal_binding_2_shadow_pillar_hit)
        end

        local old_OnLoad = inst.OnLoad
        inst.OnLoad = function(shadow_pillar, data, ...)
            if old_OnLoad ~= nil then
                old_OnLoad(shadow_pillar, data, ...)
            end

            persist_utils.RestoreMarkedFlags(data, shadow_pillar, SHADOW_PILLAR_PERSIST_SPECS)
            if data ~= nil and data._waxwell_abyssal_binding_1_duration_mult ~= nil then
                shadow_pillar._waxwell_abyssal_binding_1_duration_mult = data._waxwell_abyssal_binding_1_duration_mult
            end
            if data ~= nil and data._waxwell_abyssal_binding_2_damage ~= nil then
                shadow_pillar._waxwell_abyssal_binding_2_damage = data._waxwell_abyssal_binding_2_damage
            end
            if data ~= nil and data._waxwell_abyssal_binding_2_shadow_pillar_hit then
                shadow_pillar._waxwell_abyssal_binding_2_shadow_pillar_hit = true
            end
            if HasAbyssalBinding2ShadowPillar(shadow_pillar)
                and not shadow_pillar._waxwell_abyssal_binding_2_shadow_pillar_hit
                and shadow_pillar.components.timer ~= nil
                and shadow_pillar.components.timer:TimerExists("lifetime") then
                ResumeAbyssalBinding2ShadowPillarImpact(shadow_pillar)
            end
        end
    end)

    AddPrefabPostInit("shadow_pillar_target", function(inst)
        if not TheWorld.ismastersim or inst._waxwell_abyssal_binding_shadow_pillar_target_patched then
            return
        end

        inst._waxwell_abyssal_binding_shadow_pillar_target_patched = true
        local spawncaster = GetShadowPillarsCasterFromSpawnStack()
        if IsAbyssalBinding1Active(spawncaster) then
            MarkAbyssalBinding1ShadowPillarTarget(inst)
            inst._waxwell_abyssal_binding_1_duration_mult = V.ABYSSAL_BINDING_1_DURATION_MULT
        end

        PatchAbyssalBinding1Lifetime(inst, HasAbyssalBinding1ShadowPillarTarget)

        local old_OnSave = inst.OnSave
        inst.OnSave = function(shadow_pillar_target, data, ...)
            if old_OnSave ~= nil then
                old_OnSave(shadow_pillar_target, data, ...)
            end

            persist_utils.SaveMarkedFlags(data, shadow_pillar_target, SHADOW_PILLAR_TARGET_PERSIST_SPECS)
            persist_utils.SaveValue(data, "_waxwell_abyssal_binding_1_duration_mult", shadow_pillar_target._waxwell_abyssal_binding_1_duration_mult)
        end

        local old_OnLoad = inst.OnLoad
        inst.OnLoad = function(shadow_pillar_target, data, ...)
            if old_OnLoad ~= nil then
                old_OnLoad(shadow_pillar_target, data, ...)
            end

            persist_utils.RestoreMarkedFlags(data, shadow_pillar_target, SHADOW_PILLAR_TARGET_PERSIST_SPECS)
            if data ~= nil and data._waxwell_abyssal_binding_1_duration_mult ~= nil then
                shadow_pillar_target._waxwell_abyssal_binding_1_duration_mult = data._waxwell_abyssal_binding_1_duration_mult
            end
        end
    end)
end

return M
