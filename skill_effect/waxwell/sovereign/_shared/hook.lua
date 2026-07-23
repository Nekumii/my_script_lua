local common = require("skill_effect/waxwell/sovereign/_shared/common")

local ApplyShadowGluttonyToWaxwell = common.ApplyShadowGluttonyToWaxwell
local ApplyDreadTributeToWaxwell = common.ApplyDreadTributeToWaxwell
local ApplySanityRecoupToWaxwell = common.ApplySanityRecoupToWaxwell
local ApplyMindOverMatterToWaxwell = common.ApplyMindOverMatterToWaxwell
local ApplyInnerIncarnateToWaxwell = common.ApplyInnerIncarnateToWaxwell
local ApplyChaosInoculationToWaxwell = common.ApplyChaosInoculationToWaxwell
local GetNightmareDominionDamageMultiplier = common.GetNightmareDominionDamageMultiplier
local GetNightmareDominionDamageTakenMultiplier = common.GetNightmareDominionDamageTakenMultiplier

local royal_composure_hook = require("skill_effect/waxwell/sovereign/royal_composure/hook")
local shadow_gluttony_hook = require("skill_effect/waxwell/sovereign/shadow_gluttony/hook")
local shadow_conjury_hook = require("skill_effect/waxwell/sovereign/shadow_conjury/hook")
local nightmare_dominion_hook = require("skill_effect/waxwell/sovereign/nightmare_dominion/hook")

local M = {}

local function RegisterWaxwellCombatHooks(env)
    env.AddPrefabPostInit("waxwell", function(inst)
        if not TheWorld.ismastersim or inst._waxwell_sovereign_patched then
            return
        end

        inst._waxwell_sovereign_patched = true

        local combat = inst.components.combat
        if combat == nil then
            return
        end

        local old_customdamagemultfn = combat.customdamagemultfn
        combat.customdamagemultfn = function(attacker, target, weapon, multiplier, mount)
            local mult = old_customdamagemultfn ~= nil and old_customdamagemultfn(attacker, target, weapon, multiplier, mount) or 1
            return mult * GetNightmareDominionDamageMultiplier(attacker, target)
        end

        combat._waxwell_nightmare_dominion_damagetakenfn = combat._waxwell_nightmare_dominion_damagetakenfn or function(target, attacker, weapon)
            return GetNightmareDominionDamageTakenMultiplier(target, attacker)
        end
        combat:AddConditionExternalDamageTakenMultiplier(combat._waxwell_nightmare_dominion_damagetakenfn)

        ApplyDreadTributeToWaxwell(inst)
        -- Recoup uses attacked.original_damage (pre-armor); order vs MOM no longer matters.
        ApplySanityRecoupToWaxwell(inst)
        ApplyMindOverMatterToWaxwell(inst)
        ApplyInnerIncarnateToWaxwell(inst)
        ApplyChaosInoculationToWaxwell(inst)
        ApplyShadowGluttonyToWaxwell(inst)
    end)
end

function M.Register(env)
    royal_composure_hook.Register(env)
    shadow_gluttony_hook.Register(env)
    shadow_conjury_hook.Register(env)
    nightmare_dominion_hook.Register(env)
    RegisterWaxwellCombatHooks(env)
end

return M
