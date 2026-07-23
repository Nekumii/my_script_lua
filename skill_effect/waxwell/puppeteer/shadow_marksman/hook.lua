local common = require("skill_effect/waxwell/puppeteer/_shared/common")

local HasFragmentedMindPenaltyReduction = common.HasFragmentedMindPenaltyReduction
local MarkFragmentedMindPenaltyReduction = common.MarkFragmentedMindPenaltyReduction
local MarkShadowMarksman1 = common.MarkShadowMarksman1
local MarkShadowMarksman2 = common.MarkShadowMarksman2
local TryTintShadowMarksmanFX = common.TryTintShadowMarksmanFX
local StartShadowMarksmanFXRetint = common.StartShadowMarksmanFXRetint

local M = {}

function M.Register(env)
    env.AddPrefabPostInit("shadow_marksman", function(inst)
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

            if data ~= nil and inst._waxwell_marksman_lv1 then
                data._waxwell_marksman_lv1 = true
            end

            if data ~= nil and inst._waxwell_marksman_lv2 then
                data._waxwell_marksman_lv2 = true
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

            if data ~= nil and data._waxwell_marksman_lv1 then
                MarkShadowMarksman1(inst)
            end

            if data ~= nil and data._waxwell_marksman_lv2 then
                MarkShadowMarksman2(inst)
            end
        end
    end)

    local darkfxprefabs =
    {
        "slingshot_aoe_fx",
        "slingshotammo_slow_debuff_fx",
        "electrichitsparks",
        "electrichitsparks_electricimmune",
        "shatter",
        "honey_trail",
        "slingshotammo_hitfx_honey",
        "slingshotammo_hitfx_freeze",
        "slingshotammo_hitfx_marble",
        "slingshotammo_hitfx_thulecite",
        "slingshotammo_hitfx_stinger",
        "slingshotammo_hitfx_moonglass",
        "slingshotammo_hitfx_scrapfeather",
        "slingshotammo_hitfx_gelblob",
        "slingshotammo_hitfx_rock",
    }

    for _, prefab in ipairs(darkfxprefabs) do
        env.AddPrefabPostInit(prefab, function(inst)
            if prefab == "honey_trail" and TheWorld.ismastersim and inst.SetVariation ~= nil and not inst._shadow_marksman_honey_wrapped then
                inst._shadow_marksman_honey_wrapped = true
                local old_SetVariation = inst.SetVariation
                inst.SetVariation = function(honey, ...)
                    local ret = old_SetVariation(honey, ...)
                    TryTintShadowMarksmanFX(honey)
                    honey:DoTaskInTime(0, TryTintShadowMarksmanFX)
                    honey:DoTaskInTime(.1, TryTintShadowMarksmanFX)
                    honey:DoTaskInTime(.25, TryTintShadowMarksmanFX)
                    StartShadowMarksmanFXRetint(honey, 4)
                    return ret
                end
            end

            TryTintShadowMarksmanFX(inst)
            inst:DoTaskInTime(0, TryTintShadowMarksmanFX)
            inst:DoTaskInTime(.1, TryTintShadowMarksmanFX)
            inst:DoTaskInTime(.25, TryTintShadowMarksmanFX)
            if prefab == "honey_trail" then
                StartShadowMarksmanFXRetint(inst, 4)
            end
        end)
    end
end

return M
