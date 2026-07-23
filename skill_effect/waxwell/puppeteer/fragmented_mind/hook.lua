local common = require("skill_effect/waxwell/puppeteer/_shared/common")
local emperor_common = require("skill_effect/waxwell/emperor/_shared/common")
local domain_expansion = require("skill_effect/waxwell/emperor/domain_expansion/common")

local GetFragmentedMindPenalty = common.GetFragmentedMindPenalty
local GetFragmentedMindSpellPuppet = common.GetFragmentedMindSpellPuppet
local CanCastFragmentedMindSpell = common.CanCastFragmentedMindSpell
local HasFragmentedMindPenaltyReduction = common.HasFragmentedMindPenaltyReduction
local MarkFragmentedMindPenaltyReduction = common.MarkFragmentedMindPenaltyReduction
local IsFreeShadowServant = common.IsFreeShadowServant
local IsShadowServantCapFull = common.IsShadowServantCapFull
local CanAddShadowServant = common.CanAddShadowServant
local HasCodexUmbraFuelForPct = common.HasCodexUmbraFuelForPct
local GetShadowServantCodexCostPct = common.GetShadowServantCodexCostPct
local WithAdjustedPenaltyPercent = common.WithAdjustedPenaltyPercent
local WithAdjustedTirelessServant2CastCosts = common.WithAdjustedTirelessServant2CastCosts
local WithAdjustedLethalApparition2CastCosts = common.WithAdjustedLethalApparition2CastCosts
local WithTemporaryPetLeashIsFull = common.WithTemporaryPetLeashIsFull
local IsTirelessServant2Active = common.IsTirelessServant2Active
local IsLethalApparition2Active = common.IsLethalApparition2Active
local TrySpawnTirelessServant2Worker = common.TrySpawnTirelessServant2Worker

local M = {}

local function IsFragmentedMindActuallyActive(owner)
    if owner == nil then
        return false
    end

    local skilltreeupdater = owner.components ~= nil and owner.components.skilltreeupdater or nil
    if skilltreeupdater ~= nil then
        if skilltreeupdater:IsActivated("waxwell_fragmented_mind") then
            return true
        end

        local activatedskills = skilltreeupdater.GetActivatedSkills ~= nil and skilltreeupdater:GetActivatedSkills() or nil
        if activatedskills ~= nil and activatedskills["waxwell_fragmented_mind"] then
            return true
        end
    end

    return owner:HasTag("fragmented_mind_active")
end

local function GetBaseShadowServantPenalty(prefab)
    if prefab == nil or TUNING.SHADOWWAXWELL_SANITY_PENALTY == nil then
        return nil
    end

    prefab = string.lower(prefab)

    if prefab == "shadowworker" then
        return TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_WORKER
            or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOWWORKER
    elseif prefab == "shadowprotector" then
        return TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_PROTECTOR
    elseif prefab == "shadow_lanternbearer" then
        return TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_LANTERNBEARER
            or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_WORKER
    elseif prefab == "shadow_marksman" then
        return TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_MARKSMAN
            or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_PROTECTOR
    elseif prefab == "shadow_stalker" then
        return TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_STALKER
    end

    return nil
end

local function GetDesiredShadowServantPenalty(owner, pet)
    if owner == nil or pet == nil or pet.prefab == nil then
        return nil
    end

    if IsFreeShadowServant(pet) then
        return 0
    end

    return GetFragmentedMindPenalty(owner, pet.prefab)
end

local function EnsureShadowServantPenaltyRemoveHook(owner, pet)
    if owner == nil or pet == nil or pet._waxwell_shadow_penalty_remove_owner ~= nil then
        return
    end

    pet._waxwell_shadow_penalty_remove_owner = owner
    pet:ListenForEvent("onremove", function(inst)
        if owner:IsValid() and owner.components ~= nil and owner.components.sanity ~= nil then
            owner.components.sanity:RemoveSanityPenalty(inst)
        end
    end)
end

function M.RefreshAllShadowServantSanityPenalties(owner)
    if owner == nil
        or owner.components == nil
        or owner.components.sanity == nil
        or owner.components.petleash == nil then
        return
    end

    local petleash = owner.components.petleash
    local pets = petleash:GetPets()
    local sanity = owner.components.sanity

    for key in pairs(sanity.sanity_penalties) do
        if type(key) == "table"
            and key.prefab ~= nil
            and GetBaseShadowServantPenalty(key.prefab) ~= nil
            and (pets == nil or pets[key] == nil or not key:IsValid()) then
            sanity:RemoveSanityPenalty(key)
        end
    end

    if pets ~= nil then
        for pet in pairs(pets) do
            if pet ~= nil and pet:IsValid() then
                local penalty = GetDesiredShadowServantPenalty(owner, pet)
                if penalty ~= nil then
                    sanity:AddSanityPenalty(pet, penalty)
                    if IsFragmentedMindActuallyActive(owner) and penalty < (GetBaseShadowServantPenalty(pet.prefab) or penalty) then
                        MarkFragmentedMindPenaltyReduction(pet)
                    end
                    EnsureShadowServantPenaltyRemoveHook(owner, pet)
                end
            end
        end
    end

    sanity:RecalculatePenalty()
end

local function RegisterSanityAddPenaltyPatch(env)
    env.AddComponentPostInit("sanity", function(self)
        if self._waxwell_fragmented_mind_add_penalty_patched then
            return
        end

        self._waxwell_fragmented_mind_add_penalty_patched = true
        local old_AddSanityPenalty = self.AddSanityPenalty

        function self:AddSanityPenalty(key, mod)
            if self.inst ~= nil and self.inst.prefab == "waxwell" and key ~= nil and key.prefab ~= nil then
                if IsFreeShadowServant(key) then
                    mod = 0
                elseif HasFragmentedMindPenaltyReduction(key) then
                    local penalty = GetFragmentedMindPenalty(self.inst, key.prefab)
                    if penalty ~= nil then
                        mod = penalty
                    end
                else
                    local petleash = self.inst.components ~= nil and self.inst.components.petleash or nil
                    if not (petleash ~= nil and petleash._waxwell_loading_pets) then
                        local penalty = GetFragmentedMindPenalty(self.inst, key.prefab)
                        if penalty ~= nil then
                            mod = penalty
                            local base_penalty = TUNING.SHADOWWAXWELL_SANITY_PENALTY[string.upper(key.prefab)]
                            if base_penalty ~= nil and penalty ~= base_penalty then
                                MarkFragmentedMindPenaltyReduction(key)
                            end
                        end
                    end
                end
            end

            return old_AddSanityPenalty(self, key, mod)
        end
    end)
end

local function RegisterJournalSpellPatches(env)
    env.AddPrefabPostInit("waxwelljournal", function(inst)
        local aoetargeting = inst.components.aoetargeting
        if aoetargeting ~= nil and not aoetargeting._fragmented_mind_patched then
            aoetargeting._fragmented_mind_patched = true

            local old_SetShouldRepeatCastFn = aoetargeting.SetShouldRepeatCastFn
            function aoetargeting:SetShouldRepeatCastFn(fn)
                local originalfn = fn

                if originalfn ~= nil then
                    fn = function(book, doer)
                        local prefab = GetFragmentedMindSpellPuppet(book)
                        if prefab ~= nil then
                            local sanity = doer ~= nil and doer.replica ~= nil and doer.replica.sanity or nil
                            return CanCastFragmentedMindSpell(doer, sanity, prefab)
                        end

                        return originalfn(book, doer)
                    end
                end

                return old_SetShouldRepeatCastFn(self, fn)
            end
        end

        local aoespell = inst.components.aoespell
        if aoespell ~= nil and not aoespell._fragmented_mind_patched then
            aoespell._fragmented_mind_patched = true

            local old_SetSpellFn = aoespell.SetSpellFn
            function aoespell:SetSpellFn(fn)
                local originalfn = fn

                if originalfn ~= nil then
                    fn = function(book, doer, pos)
                        local prefab = GetFragmentedMindSpellPuppet(book)
                        local petleash = doer ~= nil and doer.components ~= nil and doer.components.petleash or nil
                        if prefab ~= nil and domain_expansion ~= nil and domain_expansion.IsDomainExpansionSummonLockActive ~= nil and domain_expansion.IsDomainExpansionSummonLockActive(doer) then
                            return false, "HASPET"
                        elseif prefab ~= nil and petleash ~= nil and IsShadowServantCapFull(petleash) then
                            return false, "HASPET"
                        end

                        local function castfn()
                            local execfn = function()
                                if prefab ~= nil and doer ~= nil and doer.components ~= nil and doer.components.sanity ~= nil then
                                    local base_penalty = TUNING.SHADOWWAXWELL_SANITY_PENALTY[string.upper(prefab)]
                                    local penalty = GetFragmentedMindPenalty(doer, prefab)
                                    local offset = base_penalty ~= nil and penalty ~= nil and (base_penalty - penalty) or 0

                                    return WithAdjustedPenaltyPercent(doer.components.sanity, offset, function()
                                        return originalfn(book, doer, pos)
                                    end)
                                end

                                return originalfn(book, doer, pos)
                            end

                            if prefab == "shadowworker" and IsTirelessServant2Active(doer) then
                                return WithAdjustedTirelessServant2CastCosts(book, execfn)
                            end
                            if prefab == "shadowprotector" and IsLethalApparition2Active(doer) then
                                return WithAdjustedLethalApparition2CastCosts(book, execfn)
                            end

                            return execfn()
                        end

                        local result, reason = (prefab ~= nil and petleash ~= nil)
                            and WithTemporaryPetLeashIsFull(petleash, IsShadowServantCapFull, castfn)
                            or castfn()

                        if result and prefab == "shadowworker" and IsTirelessServant2Active(doer) then
                            local masterpet = petleash ~= nil and petleash._waxwell_last_primary_shadowworker or nil
                            if masterpet ~= nil and masterpet:IsValid() then
                                TrySpawnTirelessServant2Worker(doer, pos, masterpet)
                            end
                        end

                        return result, reason
                    end
                end

                return old_SetSpellFn(self, fn)
            end
        end
    end)
end

function M.Register(env)
    RegisterSanityAddPenaltyPatch(env)
    RegisterJournalSpellPatches(env)
end

return M
