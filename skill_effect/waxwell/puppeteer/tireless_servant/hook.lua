local common = require("skill_effect/waxwell/puppeteer/_shared/common")

local IsFreeShadowServant = common.IsFreeShadowServant
local MarkFreeShadowServant = common.MarkFreeShadowServant
local HasFragmentedMindPenaltyReduction = common.HasFragmentedMindPenaltyReduction
local MarkFragmentedMindPenaltyReduction = common.MarkFragmentedMindPenaltyReduction
local HasTirelessServant1WorkerBuff = common.HasTirelessServant1WorkerBuff
local MarkTirelessServant1WorkerBuff = common.MarkTirelessServant1WorkerBuff
local LinkFreeShadowServantToMaster = common.LinkFreeShadowServantToMaster
local ApplyTirelessServant1ToWorker = common.ApplyTirelessServant1ToWorker
local StartFreeShadowServantTintWatcher = common.StartFreeShadowServantTintWatcher

local M = {}

function M.Register(env)
    env.AddPrefabPostInit("shadowworker", function(inst)
        StartFreeShadowServantTintWatcher(inst)

        if not TheWorld.ismastersim then
            return inst
        end

        local old_OnSave = inst.OnSave
        inst.OnSave = function(inst, data)
            local refs = nil
            if old_OnSave ~= nil then
                refs = old_OnSave(inst, data)
            end

            if data ~= nil and IsFreeShadowServant(inst) then
                data._waxwell_free_shadow_servant = true
            end

            if data ~= nil and HasFragmentedMindPenaltyReduction(inst) then
                data._waxwell_fragmented_mind_penalty = true
            end

            if data ~= nil and HasTirelessServant1WorkerBuff(inst) then
                data._waxwell_tireless_servant_1 = true
            end

            if data ~= nil and inst._waxwell_free_shadow_master ~= nil and inst._waxwell_free_shadow_master:IsValid() then
                data._waxwell_free_shadow_master = inst._waxwell_free_shadow_master.GUID
                refs = refs or {}
                table.insert(refs, data._waxwell_free_shadow_master)
            end

            return refs
        end

        local old_OnLoad = inst.OnLoad
        inst.OnLoad = function(inst, data)
            if old_OnLoad ~= nil then
                old_OnLoad(inst, data)
            end

            if data ~= nil and data._waxwell_free_shadow_servant then
                MarkFreeShadowServant(inst)
            end

            if data ~= nil and data._waxwell_fragmented_mind_penalty then
                MarkFragmentedMindPenaltyReduction(inst)
            end

            if data ~= nil and data._waxwell_tireless_servant_1 then
                MarkTirelessServant1WorkerBuff(inst)
            end

            inst._waxwell_free_shadow_master_guid = data ~= nil and data._waxwell_free_shadow_master or nil
        end

        local old_LoadPostPass = inst.LoadPostPass
        inst.LoadPostPass = function(inst, newents, data)
            if old_LoadPostPass ~= nil then
                old_LoadPostPass(inst, newents, data)
            end

            if inst._waxwell_free_shadow_master_guid ~= nil and newents ~= nil then
                local master = newents[inst._waxwell_free_shadow_master_guid]
                master = master ~= nil and master.entity or nil
                if master ~= nil and master:IsValid() then
                    LinkFreeShadowServantToMaster(inst, master)
                end
            end
        end

        inst:DoTaskInTime(0, ApplyTirelessServant1ToWorker)
    end)
end

return M
