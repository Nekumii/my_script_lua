local V = require("skill_effect/waxwell/puppeteer/expanded_dominion/variables")

local tireless_servant_common = nil

local function GetTirelessServantCommon()
    if tireless_servant_common == nil then
        tireless_servant_common = require("skill_effect/waxwell/puppeteer/tireless_servant/common")
    end

    return tireless_servant_common
end

local function IsExpandedDominionActive(inst)
    if inst == nil then
        return false
    end

    if inst:HasTag("expanded_dominion_active") then
        return true
    end

    local skilltreeupdater = inst.components ~= nil and inst.components.skilltreeupdater or nil
    if skilltreeupdater ~= nil then
        if skilltreeupdater:IsActivated("waxwell_expanded_dominion") then
            return true
        end

        local activatedskills = skilltreeupdater.GetActivatedSkills ~= nil and skilltreeupdater:GetActivatedSkills() or nil
        if activatedskills ~= nil and activatedskills["waxwell_expanded_dominion"] then
            return true
        end
    end

    return false
end

local function GetWaxwellShadowServantBaseSlots(petleash)
    if petleash ~= nil then
        petleash._waxwell_base_maxpets = V.WAXWELL_SHADOW_SERVANT_BASE_SLOTS
    end

    return V.WAXWELL_SHADOW_SERVANT_BASE_SLOTS
end

local function GetShadowServantSlotCost(prefab)
    if prefab == nil then
        return 0
    end

    return V.SHADOW_SERVANT_SLOT_COSTS[string.lower(prefab)] or 0
end

local function GetUsedShadowServantSlots(petleash)
    local pets = petleash ~= nil and petleash:GetPets() or nil
    local used = 0
    local IsFreeShadowServant = GetTirelessServantCommon().IsFreeShadowServant

    if pets ~= nil then
        for pet in pairs(pets) do
            if pet ~= nil and pet:IsValid() and not IsFreeShadowServant(pet) then
                used = used + GetShadowServantSlotCost(pet.prefab)
            end
        end
    end

    return used
end

local function GetInnerIncarnateSummonSlotPenalty(owner)
    local ok, inner_incarnate = pcall(require, "skill_effect/waxwell/sovereign/inner_incarnate/common")
    if ok and inner_incarnate ~= nil and inner_incarnate.GetInnerIncarnateSummonSlotPenalty ~= nil then
        return inner_incarnate.GetInnerIncarnateSummonSlotPenalty(owner) or 0
    end

    return 0
end

local function GetExpandedDominionMaxPets(petleash)
    if petleash == nil then
        return 0
    end

    local maxpets = GetWaxwellShadowServantBaseSlots(petleash)
    if IsExpandedDominionActive(petleash.inst) then
        maxpets = maxpets + V.EXPANDED_DOMINION_MAX_PET_BONUS
    end

    return math.max(0, maxpets - GetInnerIncarnateSummonSlotPenalty(petleash.inst))
end

local function IsShadowServantCapFull(petleash)
    return petleash ~= nil and GetUsedShadowServantSlots(petleash) >= GetExpandedDominionMaxPets(petleash)
end

local function CanAddShadowServant(petleash, prefab)
    if petleash == nil then
        return false
    end

    local slotcost = GetShadowServantSlotCost(prefab)
    if slotcost <= 0 then
        return false
    end

    return GetUsedShadowServantSlots(petleash) + slotcost <= GetExpandedDominionMaxPets(petleash)
end

local function WithTemporaryPetLeashIsFull(petleash, isfullfn, fn)
    if petleash == nil or fn == nil then
        return fn()
    end

    local old_IsFull = petleash.IsFull
    petleash.IsFull = function(self, ...)
        return isfullfn(self, ...)
    end

    local ok, result, reason = xpcall(fn, debug.traceback)
    petleash.IsFull = old_IsFull

    if not ok then
        error(result)
    end

    return result, reason
end

return {
    IsExpandedDominionActive = IsExpandedDominionActive,
    GetWaxwellShadowServantBaseSlots = GetWaxwellShadowServantBaseSlots,
    GetShadowServantSlotCost = GetShadowServantSlotCost,
    GetUsedShadowServantSlots = GetUsedShadowServantSlots,
    GetExpandedDominionMaxPets = GetExpandedDominionMaxPets,
    IsShadowServantCapFull = IsShadowServantCapFull,
    CanAddShadowServant = CanAddShadowServant,
    WithTemporaryPetLeashIsFull = WithTemporaryPetLeashIsFull,
}
