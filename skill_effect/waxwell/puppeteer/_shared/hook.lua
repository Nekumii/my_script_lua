local common = require("skill_effect/waxwell/puppeteer/_shared/common")
local codex_umbra_spell_index = require("skill_effect/waxwell/_shared/codex_spell_index")

local fragmented_mind_hook = require("skill_effect/waxwell/puppeteer/fragmented_mind/hook")
local expanded_dominion_hook = require("skill_effect/waxwell/puppeteer/expanded_dominion/hook")
local tireless_servant_hook = require("skill_effect/waxwell/puppeteer/tireless_servant/hook")
local lethal_apparition_hook = require("skill_effect/waxwell/puppeteer/lethal_apparition/hook")
local shadow_lanternbearer_hook = require("skill_effect/waxwell/puppeteer/shadow_lanternbearer/hook")
local shadow_marksman_hook = require("skill_effect/waxwell/puppeteer/shadow_marksman/hook")

local BuildPuppeteerSpellList = common.BuildPuppeteerSpellList
local SHADOW_LANTERNBEARER_SPELL = common.SHADOW_LANTERNBEARER_SPELL
local SHADOW_MARKSMAN_SPELL = common.SHADOW_MARKSMAN_SPELL
local GetExpectedMarksmanPenaltyTotal = common.GetExpectedMarksmanPenaltyTotal
local GetActualMarksmanPenaltyTotal = common.GetActualMarksmanPenaltyTotal
local GetExpectedLanternbearerPenaltyTotal = common.GetExpectedLanternbearerPenaltyTotal
local GetActualLanternbearerPenaltyTotal = common.GetActualLanternbearerPenaltyTotal
local IsFreeShadowServant = common.IsFreeShadowServant
local MarkFreeShadowServant = common.MarkFreeShadowServant
local IsTirelessServant1Active = common.IsTirelessServant1Active
local IsLethalApparition1Active = common.IsLethalApparition1Active
local IsLethalApparition2Active = common.IsLethalApparition2Active
local IsLethalApparition1ShadowDuelist = common.IsLethalApparition1ShadowDuelist
local IsLethalApparition2ShadowDuelist = common.IsLethalApparition2ShadowDuelist
local ApplyTirelessServant1ToWorker = common.ApplyTirelessServant1ToWorker
local ApplyLethalApparition1ToProtector = common.ApplyLethalApparition1ToProtector
local ApplyLethalApparition2ToProtector = common.ApplyLethalApparition2ToProtector
local EnsureMarksmanSanityPenalty = common.EnsureMarksmanSanityPenalty
local RefreshMarksmanSanityPenalty = common.RefreshMarksmanSanityPenalty
local RefreshMarksmanSanityPenaltyForPet = common.RefreshMarksmanSanityPenaltyForPet
local EnsureLanternbearerSanityPenalty = common.EnsureLanternbearerSanityPenalty
local RefreshLanternbearerSanityPenalty = common.RefreshLanternbearerSanityPenalty
local RefreshLanternbearerSanityPenaltyForPet = common.RefreshLanternbearerSanityPenaltyForPet
local RefreshWaxwellShadowServantState = expanded_dominion_hook.RefreshWaxwellShadowServantState

local M = {}

local function RegisterSanityRecalculatePatch(env)
    env.AddComponentPostInit("sanity", function(self)
        if self._waxwell_puppeteer_recalculate_penalty_patched then
            return
        end

        self._waxwell_puppeteer_recalculate_penalty_patched = true
        local old_RecalculatePenalty = self.RecalculatePenalty

        function self:RecalculatePenalty(...)
            old_RecalculatePenalty(self, ...)

            if self.inst == nil or self.inst.prefab ~= "waxwell" then
                return
            end

            local expected = GetExpectedMarksmanPenaltyTotal(self.inst)
            local actual = GetActualMarksmanPenaltyTotal(self)
            local lantern_expected = GetExpectedLanternbearerPenaltyTotal(self.inst)
            local lantern_actual = GetActualLanternbearerPenaltyTotal(self)
            local delta = (expected - actual) + (lantern_expected - lantern_actual)
            if math.abs(delta) > .0001 then
                self.penalty = math.min(math.max(0, self.penalty + delta), 1 - (5 / self.max))
                self:DoDelta(0)
            end
        end
    end)
end

local function RegisterJournalHooks(env)
    local AddPrefabPostInit = env.AddPrefabPostInit

    codex_umbra_spell_index.EnsureSpellLabel(SHADOW_LANTERNBEARER_SPELL, "Shadow Lanternbearer")
    codex_umbra_spell_index.EnsureSpellLabel(SHADOW_MARKSMAN_SPELL, "Shadow Marksman")
    TUNING.SHADOWWAXWELL_SANITY_PENALTY = TUNING.SHADOWWAXWELL_SANITY_PENALTY or {}
    TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_LANTERNBEARER = TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_LANTERNBEARER or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_WORKER
    TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_MARKSMAN = TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_MARKSMAN or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_PROTECTOR

    AddPrefabPostInit("waxwelljournal", function(inst)
        local spellbook = inst.components.spellbook
        codex_umbra_spell_index.RegisterJournalSpellBuilder(inst, spellbook, "puppeteer", BuildPuppeteerSpellList)
    end)
end

local function RegisterWaxwellPetLeashHooks(env)
    env.AddPrefabPostInit("waxwell", function(inst)
        if not TheWorld.ismastersim or inst.components == nil or inst.components.petleash == nil then
            return inst
        end

        local petleash = inst.components.petleash
        if petleash._tireless_servant_patched then
            return inst
        end

        petleash._tireless_servant_patched = true

        local old_OnLoad = petleash.OnLoad
        petleash.OnLoad = function(self, data)
            self._waxwell_loading_pets = true

            local ok, result = xpcall(function()
                return old_OnLoad(self, data)
            end, debug.traceback)

            self._waxwell_loading_pets = nil

            self.inst:DoTaskInTime(0, RefreshWaxwellShadowServantState)
            self.inst:DoTaskInTime(.1, RefreshWaxwellShadowServantState)
            self.inst:DoTaskInTime(.5, RefreshWaxwellShadowServantState)

            if not ok then
                error(result)
            end

            return result
        end

        local old_onspawnfn = petleash.onspawnfn
        petleash:SetOnSpawnFn(function(owner, pet)
            if pet ~= nil and pet.prefab == "shadowworker" then
                local pending = petleash._waxwell_pending_free_shadow_servants or 0
                if pending > 0 then
                    petleash._waxwell_pending_free_shadow_servants = pending > 1 and (pending - 1) or nil
                    MarkFreeShadowServant(pet)
                elseif IsFreeShadowServant(pet) then
                    MarkFreeShadowServant(pet)
                else
                    petleash._waxwell_last_primary_shadowworker = pet
                end
            end

            if old_onspawnfn ~= nil then
                old_onspawnfn(owner, pet)
            end

            if pet ~= nil and pet.prefab == "shadow_marksman" then
                EnsureMarksmanSanityPenalty(owner, pet)
                pet:DoTaskInTime(0, RefreshMarksmanSanityPenaltyForPet, owner)
                pet:DoTaskInTime(0.1, RefreshMarksmanSanityPenaltyForPet, owner)
                pet:ListenForEvent("onremove", function()
                    RefreshMarksmanSanityPenalty(owner)
                end)
            end

            if pet ~= nil and pet.prefab == "shadow_lanternbearer" then
                EnsureLanternbearerSanityPenalty(owner, pet)
                pet:DoTaskInTime(0, RefreshLanternbearerSanityPenaltyForPet, owner)
                pet:DoTaskInTime(0.1, RefreshLanternbearerSanityPenaltyForPet, owner)
                pet:ListenForEvent("onremove", function()
                    RefreshLanternbearerSanityPenalty(owner)
                end)
            end

            if pet ~= nil and pet.prefab == "shadowworker" and not petleash._waxwell_loading_pets and IsTirelessServant1Active(owner) then
                ApplyTirelessServant1ToWorker(pet, true)
            elseif pet ~= nil and pet.prefab == "shadowprotector" and not petleash._waxwell_loading_pets then
                if IsLethalApparition1Active(owner) then
                    pet:DoTaskInTime(0, ApplyLethalApparition1ToProtector, true)
                elseif IsLethalApparition1ShadowDuelist(pet) then
                    pet:DoTaskInTime(0, ApplyLethalApparition1ToProtector)
                end

                if IsLethalApparition2Active(owner) then
                    pet:DoTaskInTime(0, ApplyLethalApparition2ToProtector, true)
                elseif IsLethalApparition2ShadowDuelist(pet) then
                    pet:DoTaskInTime(0, ApplyLethalApparition2ToProtector)
                end
            end
        end)

        inst:DoTaskInTime(0, RefreshWaxwellShadowServantState)
        inst:DoTaskInTime(.1, RefreshWaxwellShadowServantState)
        inst:DoTaskInTime(.5, RefreshWaxwellShadowServantState)
    end)
end

function M.Register(env)
    expanded_dominion_hook.Register(env)
    fragmented_mind_hook.Register(env)
    tireless_servant_hook.Register(env)
    lethal_apparition_hook.Register(env)
    shadow_lanternbearer_hook.Register(env)
    shadow_marksman_hook.Register(env)
    RegisterSanityRecalculatePatch(env)
    RegisterJournalHooks(env)
    RegisterWaxwellPetLeashHooks(env)
end

return M
