local common = require("skill_effect/waxwell/puppeteer/_shared/common")

local HasFragmentedMindPenaltyReduction = common.HasFragmentedMindPenaltyReduction
local MarkFragmentedMindPenaltyReduction = common.MarkFragmentedMindPenaltyReduction

local M = {}

function M.Register(env)
    env.AddPrefabPostInit("shadow_lanternbearer", function(inst)
        if not TheWorld.ismastersim then
            return inst
        end

        local old_OnSave = inst.OnSave
        inst.OnSave = function(inst, data)
            local refs = nil
            if old_OnSave ~= nil then
                refs = old_OnSave(inst, data)
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

            if data ~= nil and data._waxwell_fragmented_mind_penalty then
                MarkFragmentedMindPenaltyReduction(inst)
            end
        end
    end)
end

return M
