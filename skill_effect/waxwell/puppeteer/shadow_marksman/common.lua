require "behaviours/doaction"

local cast = require("skill_effect/waxwell/puppeteer/_shared/cast_common")
local expanded_dominion = require("skill_effect/waxwell/puppeteer/expanded_dominion/common")
local fragmented_mind = require("skill_effect/waxwell/puppeteer/fragmented_mind/common")
local tireless_servant = require("skill_effect/waxwell/puppeteer/tireless_servant/common")
local spell_utils = require("skill_effect/waxwell/_shared/codex_spell_utils")
local ReticuleUtils = require("reticule/utils")
local domain_expansion = require("skill_effect/waxwell/emperor/domain_expansion/common")
local V = require("skill_effect/waxwell/puppeteer/shadow_marksman/variables")

local SpellCost = cast.SpellCost
local HasCodexUmbraFuelForPct = cast.HasCodexUmbraFuelForPct
local WithTemporaryPetLeashIsFull = expanded_dominion.WithTemporaryPetLeashIsFull
local IsShadowServantCapFull = expanded_dominion.IsShadowServantCapFull
local CanAddShadowServant = expanded_dominion.CanAddShadowServant
local FRAGMENTED_MIND_PENALTY = fragmented_mind.FRAGMENTED_MIND_PENALTY
local GetFragmentedMindPenalty = fragmented_mind.GetFragmentedMindPenalty
local MarkFragmentedMindPenaltyReduction = fragmented_mind.MarkFragmentedMindPenaltyReduction
local IsFreeShadowServant = tireless_servant.IsFreeShadowServant
local StartAOETargeting = spell_utils.StartAOETargeting

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

local function IsShadowMarksmanSkillActive(inst)
    return V.SHADOW_MARKSMAN_ENABLED
        and inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_shadow_marksman_1"))
            or inst:HasTag("shadow_marksman_1_active")
        )
end

local function IsShadowMarksman2Active(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_shadow_marksman_2"))
            or inst:HasTag("shadow_marksman_2_active")
        )
end

local function MarkShadowMarksman1(inst)
    if inst ~= nil and not inst:HasTag(V.SHADOW_MARKSMAN_LV1_TAG) then
        inst._waxwell_marksman_lv1 = true
        inst:AddTag(V.SHADOW_MARKSMAN_LV1_TAG)
    end
end

local function MarkShadowMarksman2(inst)
    if inst ~= nil and not inst:HasTag(V.SHADOW_MARKSMAN_LV2_TAG) then
        inst._waxwell_marksman_lv2 = true
        inst:AddTag(V.SHADOW_MARKSMAN_LV2_TAG)
    end
end

local function GetMarksmanPenalty(owner)
    local basepenalty = (TUNING.SHADOWWAXWELL_SANITY_PENALTY ~= nil and (
        TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_MARKSMAN
        or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_PROTECTOR
        or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_WORKER
        or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOWWORKER
    )) or .15

    if IsFragmentedMindActuallyActive(owner) then
        return FRAGMENTED_MIND_PENALTY or GetFragmentedMindPenalty(owner, "shadow_marksman") or basepenalty
    end

    return basepenalty
end

local function GetExpectedMarksmanPenaltyTotal(owner)
    local petleash = owner ~= nil and owner.components ~= nil and owner.components.petleash or nil
    local pets = petleash ~= nil and petleash:GetPets() or nil
    local total = 0

    if pets ~= nil then
        for pet in pairs(pets) do
            if pet ~= nil and pet:IsValid() and pet.prefab == "shadow_marksman" and not IsFreeShadowServant(pet) then
                total = total + GetMarksmanPenalty(owner)
            end
        end
    end

    return total
end

local function GetActualMarksmanPenaltyTotal(sanity)
    local total = 0

    if sanity ~= nil and sanity.sanity_penalties ~= nil then
        for key, mod in pairs(sanity.sanity_penalties) do
            if type(key) == "table" and key.prefab == "shadow_marksman" then
                total = total + (mod or 0)
            end
        end
    end

    return total
end

local function RefreshMarksmanSanityPenalty(owner)
    if owner == nil
        or owner.components == nil
        or owner.components.sanity == nil
        or owner.components.petleash == nil then
        return
    end

    local pets = owner.components.petleash:GetPets()
    local sanity = owner.components.sanity

    for key in pairs(sanity.sanity_penalties) do
        if type(key) == "table"
            and key.prefab == "shadow_marksman"
            and (pets == nil or pets[key] == nil or not key:IsValid()) then
            sanity:RemoveSanityPenalty(key)
        end
    end

    if pets ~= nil then
        for pet in pairs(pets) do
            if pet ~= nil and pet:IsValid() and pet.prefab == "shadow_marksman" then
                local penalty = IsFreeShadowServant(pet) and 0
                    or GetMarksmanPenalty(owner)

                if penalty ~= nil then
                    sanity:AddSanityPenalty(pet, penalty)

                    local base_penalty = TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_MARKSMAN
                        or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_PROTECTOR
                    if base_penalty ~= nil and penalty ~= base_penalty then
                        MarkFragmentedMindPenaltyReduction(pet)
                    end
                else
                    sanity:RemoveSanityPenalty(pet)
                end

                if pet._waxwell_marksman_penalty_remove_owner == nil then
                    pet._waxwell_marksman_penalty_remove_owner = owner
                    pet:ListenForEvent("onremove", function(inst)
                        if owner:IsValid() and owner.components ~= nil and owner.components.sanity ~= nil then
                            owner.components.sanity:RemoveSanityPenalty(inst)
                        end
                    end)
                end
            end
        end
    end
end

local function EnsureMarksmanSanityPenalty(owner, pet)
    if owner == nil
        or pet == nil
        or pet.prefab ~= "shadow_marksman"
        or owner.components == nil
        or owner.components.sanity == nil then
        RefreshMarksmanSanityPenalty(owner)
        return
    end

    local penalty = IsFreeShadowServant(pet) and 0
        or GetMarksmanPenalty(owner)

    if penalty ~= nil then
        owner.components.sanity:AddSanityPenalty(pet, penalty)

        local base_penalty = TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_MARKSMAN
            or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_PROTECTOR
        if base_penalty ~= nil and penalty ~= base_penalty then
            MarkFragmentedMindPenaltyReduction(pet)
        end
    else
        owner.components.sanity:RemoveSanityPenalty(pet)
    end

    if pet._waxwell_marksman_penalty_remove_owner == nil then
        pet._waxwell_marksman_penalty_remove_owner = owner
        pet:ListenForEvent("onremove", function(inst)
            if owner:IsValid() and owner.components ~= nil and owner.components.sanity ~= nil then
                owner.components.sanity:RemoveSanityPenalty(inst)
            end
        end)
    end

    RefreshMarksmanSanityPenalty(owner)
end

local function RefreshMarksmanSanityPenaltyForPet(pet, owner)
    if owner ~= nil and owner:IsValid() then
        RefreshMarksmanSanityPenalty(owner)
    end
end

local function NotBlocked(pt)
    return pt ~= nil and not TheWorld.Map:IsGroundTargetBlocked(pt)
end

local function FindSpawnPoints(doer, pos, num, radius)
    local ret = {}
    local theta, delta, attempts
    if num > 1 then
        delta = TWOPI / num
        attempts = 3
        theta = doer:GetAngleToPoint(pos) * DEGREES
        if num == 2 then
            theta = theta + PI * (math.random() < .5 and .5 or -.5)
        else
            theta = theta + PI
            if math.random() < .5 then
                delta = -delta
            end
        end
    else
        theta = 0
        delta = 0
        attempts = 1
        radius = 0
    end

    for i = 1, num do
        local offset = FindWalkableOffset(pos, theta, radius, attempts, false, false, NotBlocked, true, true)
        if (type(offset) == "table" or type(offset) == "userdata") and offset.x ~= nil and offset.z ~= nil then
            table.insert(ret, Vector3(pos.x + offset.x, 0, pos.z + offset.z))
        end
        theta = theta + delta
    end

    return ret
end

local function TrySpawnMarksman(doer, pos)
    local petleash = doer.components.petleash
    if petleash == nil then
        return false
    end

    local spawnpts = FindSpawnPoints(doer, pos, 1, 1)
    if #spawnpts <= 0 then
        return false
    end

    for _, pt in ipairs(spawnpts) do
        local pet = WithTemporaryPetLeashIsFull(petleash, IsShadowServantCapFull, function()
            return petleash:SpawnPetAt(pt.x, 0, pt.z, "shadow_marksman")
        end)
        if pet ~= nil then
            if IsShadowMarksman2Active(doer) then
                MarkShadowMarksman2(pet)
            elseif IsShadowMarksmanSkillActive(doer) then
                MarkShadowMarksman1(pet)
            end
            EnsureMarksmanSanityPenalty(doer, pet)
            pet:DoTaskInTime(0, RefreshMarksmanSanityPenaltyForPet, doer)
            pet:DoTaskInTime(0.1, RefreshMarksmanSanityPenaltyForPet, doer)
            if pet.SaveSpawnPoint ~= nil then
                pet:SaveSpawnPoint()
            end
            return true
        end
    end

    return false
end

local function CheckMarksmanMaxSanity(doer, sanity)
    local penalty = GetMarksmanPenalty(doer)

    return sanity ~= nil
        and penalty ~= nil
        and sanity:GetPenaltyPercent() + penalty <= TUNING.MAXIMUM_SANITY_PENALTY
end

local function ShouldRepeatCastMarksman(inst, doer)
    if doer == nil then
        return false
    end

    local sanity = doer.replica ~= nil and doer.replica.sanity
        or doer.components ~= nil and doer.components.sanity
        or nil
    if not CheckMarksmanMaxSanity(doer, sanity) then
        return false
    end

    local petleash = doer.components ~= nil and doer.components.petleash or nil
    return petleash == nil or CanAddShadowServant(petleash, "shadow_marksman")
end

local function MarksmanSpellFn(inst, doer, pos)
    local sanity = doer ~= nil and doer.components ~= nil and doer.components.sanity or nil
    local petleash = doer ~= nil and doer.components ~= nil and doer.components.petleash or nil
    local penalty = GetMarksmanPenalty(doer)
    local penaltypct = sanity ~= nil and sanity:GetPenaltyPercent() or nil
    local canadd = petleash ~= nil and CanAddShadowServant(petleash, "shadow_marksman") or nil

    if inst.components.fueled:IsEmpty() then
        return false, "NO_FUEL"
    elseif not HasCodexUmbraFuelForPct(inst, V.SHADOW_MARKSMAN_DURABILITY_COST_PCT) then
        return false, "NO_FUEL"
    elseif domain_expansion ~= nil and domain_expansion.IsDomainExpansionSummonLockActive ~= nil and domain_expansion.IsDomainExpansionSummonLockActive(doer) then
        return false, "HASPET"
    elseif not (sanity ~= nil
        and penalty ~= nil
        and penaltypct + penalty <= TUNING.MAXIMUM_SANITY_PENALTY
        and (petleash == nil or not IsShadowServantCapFull(petleash))
        and (petleash == nil or canadd)) then
        return false, "HASPET"
    elseif TrySpawnMarksman(doer, pos) then
        inst.components.fueled:DoDelta(SpellCost(V.SHADOW_MARKSMAN_DURABILITY_COST_PCT), doer)
        return true
    end

    return false
end

local function GetShadowMarksmanSpellData()
    return {
        label = STRINGS.SPELLS[V.SHADOW_MARKSMAN_SPELL],
        onselect = function(inst)
            inst.components.spellbook:SetSpellName(STRINGS.SPELLS[V.SHADOW_MARKSMAN_SPELL])
            inst.components.spellbook:SetSpellAction(nil)
            inst.components.aoetargeting:SetAlwaysValid(false)
            inst.components.aoetargeting:SetAllowWater(false)
            inst.components.aoetargeting:SetDeployRadius(0)
            inst.components.aoetargeting:SetShouldRepeatCastFn(ShouldRepeatCastMarksman)
            inst.components.aoetargeting.reticule.reticuleprefab = "reticuleaoe_1d2_12"
            inst.components.aoetargeting.reticule.pingprefab = "reticuleaoeping_1d2_12"
            inst.components.aoetargeting.reticule.validfn = nil
            ReticuleUtils.ConfigureSpellCastRange(inst, inst.components.aoetargeting, ReticuleUtils.GetVanillaSummonCastRange())
            if TheWorld.ismastersim then
                inst.components.aoetargeting:SetTargetFX("reticuleaoesummontarget_1d2")
                inst.components.aoespell:SetSpellFn(MarksmanSpellFn)
                inst.components.spellbook:SetSpellFn(nil)
            end
        end,
        execute = StartAOETargeting,
        atlas = "images/waxwell/waxwell_codex_icon.xml",
        normal = "codex_umbra_shadow_marksman.tex",
        widget_scale = V.SHADOW_MARKSMAN_ICON_SCALE,
        hit_radius = V.SHADOW_MARKSMAN_ICON_RADIUS,
    }
end

local function SetShadowMarksmanFXTint(inst)
    if inst ~= nil and inst.AnimState ~= nil then
        inst.AnimState:SetMultColour(unpack(V.SHADOW_MARKSMAN_TINT))
        inst.AnimState:SetAddColour(0, 0, 0, 0)
        inst.AnimState:SetLightOverride(0)
    end

    if inst ~= nil and inst.Light ~= nil then
        inst.Light:SetColour(.1, .1, .1)
    end
end

local function IsNearShadowMarksmanFXTarget(inst)
    if inst == nil or not inst:IsValid() then
        return false
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(x, y, z, 10, { V.SHADOW_MARKSMAN_DARK_FX_TAG }, { "INLIMBO" })
    for _, ent in ipairs(ents) do
        if ent ~= nil and ent:IsValid() and ent._shadow_marksman_dark_fx_until ~= nil and ent._shadow_marksman_dark_fx_until > GetTime() then
            return true
        end
    end

    return false
end

local function TryTintShadowMarksmanFX(inst)
    if IsNearShadowMarksmanFXTarget(inst) then
        if inst.SetColorType ~= nil then
            inst:SetColorType("shadow")
        end
        SetShadowMarksmanFXTint(inst)
    end
end

local function StartShadowMarksmanFXRetint(inst, duration)
    if inst == nil or not inst:IsValid() then
        return
    end

    duration = duration or 2
    local endtime = GetTime() + duration

    if inst._shadow_marksman_fx_retint_task ~= nil then
        inst._shadow_marksman_fx_retint_task:Cancel()
    end

    inst._shadow_marksman_fx_retint_task = inst:DoPeriodicTask(0, function(fx)
        if not fx:IsValid() or GetTime() >= endtime then
            if fx._shadow_marksman_fx_retint_task ~= nil then
                fx._shadow_marksman_fx_retint_task:Cancel()
                fx._shadow_marksman_fx_retint_task = nil
            end
            return
        end

        TryTintShadowMarksmanFX(fx)
    end)
end

return {
    SHADOW_MARKSMAN_SPELL = V.SHADOW_MARKSMAN_SPELL,
    IsShadowMarksmanSkillActive = IsShadowMarksmanSkillActive,
    IsShadowMarksman2Active = IsShadowMarksman2Active,
    MarkShadowMarksman1 = MarkShadowMarksman1,
    MarkShadowMarksman2 = MarkShadowMarksman2,
    GetExpectedMarksmanPenaltyTotal = GetExpectedMarksmanPenaltyTotal,
    GetActualMarksmanPenaltyTotal = GetActualMarksmanPenaltyTotal,
    RefreshMarksmanSanityPenalty = RefreshMarksmanSanityPenalty,
    EnsureMarksmanSanityPenalty = EnsureMarksmanSanityPenalty,
    RefreshMarksmanSanityPenaltyForPet = RefreshMarksmanSanityPenaltyForPet,
    GetShadowMarksmanSpellData = GetShadowMarksmanSpellData,
    TryTintShadowMarksmanFX = TryTintShadowMarksmanFX,
    StartShadowMarksmanFXRetint = StartShadowMarksmanFXRetint,
}
