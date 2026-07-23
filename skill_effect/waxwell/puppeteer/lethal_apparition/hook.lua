local common = require("skill_effect/waxwell/puppeteer/_shared/common")

local IsLethalApparition1ShadowDuelist = common.IsLethalApparition1ShadowDuelist
local MarkLethalApparition1ShadowDuelist = common.MarkLethalApparition1ShadowDuelist
local IsLethalApparition2ShadowDuelist = common.IsLethalApparition2ShadowDuelist
local MarkLethalApparition2ShadowDuelist = common.MarkLethalApparition2ShadowDuelist
local HasFragmentedMindPenaltyReduction = common.HasFragmentedMindPenaltyReduction
local MarkFragmentedMindPenaltyReduction = common.MarkFragmentedMindPenaltyReduction
local ApplyLethalApparition1ToProtector = common.ApplyLethalApparition1ToProtector
local ApplyLethalApparition2ToProtector = common.ApplyLethalApparition2ToProtector

local M = {}

function M.Register(env)
    env.AddPrefabPostInit("shadowprotector", function(inst)
        if not TheWorld.ismastersim then
            return inst
        end

        local old_OnSave = inst.OnSave
        inst.OnSave = function(inst, data)
            local refs = nil
            if old_OnSave ~= nil then
                refs = old_OnSave(inst, data)
            end

            if data ~= nil and IsLethalApparition1ShadowDuelist(inst) then
                data._waxwell_lethal_apparition_1 = true
            end

            if data ~= nil and IsLethalApparition2ShadowDuelist(inst) then
                data._waxwell_lethal_apparition_2 = true
            end

            if data ~= nil and HasFragmentedMindPenaltyReduction(inst) then
                data._waxwell_fragmented_mind_penalty = true
            end

            return refs
        end

        local old_OnLoad = inst.OnLoad
        inst.OnLoad = function(inst, data)
            if old_OnLoad ~= nil then
                old_OnLoad(inst, data)
            end

            if data ~= nil and data._waxwell_lethal_apparition_1 then
                MarkLethalApparition1ShadowDuelist(inst)
            end

            if data ~= nil and data._waxwell_lethal_apparition_2 then
                MarkLethalApparition2ShadowDuelist(inst)
            end

            if data ~= nil and data._waxwell_fragmented_mind_penalty then
                MarkFragmentedMindPenaltyReduction(inst)
            end
        end

        inst:DoTaskInTime(0, ApplyLethalApparition1ToProtector)
        inst:DoTaskInTime(0, ApplyLethalApparition2ToProtector)
    end)
end

return M
