require "behaviours/doaction"

local cast = require("skill_effect/waxwell/puppeteer/_shared/cast_common")
local expanded_dominion = require("skill_effect/waxwell/puppeteer/expanded_dominion/common")
local fragmented_mind = require("skill_effect/waxwell/puppeteer/fragmented_mind/common")
local tireless_servant = require("skill_effect/waxwell/puppeteer/tireless_servant/common")
local spell_utils = require("skill_effect/waxwell/_shared/codex_spell_utils")
local ReticuleUtils = require("reticule/utils")
local domain_expansion = require("skill_effect/waxwell/emperor/domain_expansion/common")
local V = require("skill_effect/waxwell/puppeteer/shadow_lanternbearer/variables")

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

local function IsShadowLanternbearerSkillActive(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_shadow_lanternbearer_1"))
            or inst:HasTag("shadow_lanternbearer_1_active")
        )
end

local function IsShadowLanternbearer2Active(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_shadow_lanternbearer_2"))
            or inst:HasTag("shadow_lanternbearer_2_active")
        )
end

local function GetLanternbearerPenalty(owner)
    local basepenalty = (TUNING.SHADOWWAXWELL_SANITY_PENALTY ~= nil and (
        TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_LANTERNBEARER
        or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_WORKER
        or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_PROTECTOR
    )) or .15

    if IsFragmentedMindActuallyActive(owner) then
        return FRAGMENTED_MIND_PENALTY or GetFragmentedMindPenalty(owner, "shadow_lanternbearer") or basepenalty
    end

    return basepenalty
end

local function GetExpectedLanternbearerPenaltyTotal(owner)
    local petleash = owner ~= nil and owner.components ~= nil and owner.components.petleash or nil
    local pets = petleash ~= nil and petleash:GetPets() or nil
    local total = 0

    if pets ~= nil then
        for pet in pairs(pets) do
            if pet ~= nil and pet:IsValid() and pet.prefab == "shadow_lanternbearer" and not IsFreeShadowServant(pet) then
                total = total + GetLanternbearerPenalty(owner)
            end
        end
    end

    return total
end

local function GetActualLanternbearerPenaltyTotal(sanity)
    local total = 0

    if sanity ~= nil and sanity.sanity_penalties ~= nil then
        for key, mod in pairs(sanity.sanity_penalties) do
            if type(key) == "table" and key.prefab == "shadow_lanternbearer" then
                total = total + (mod or 0)
            end
        end
    end

    return total
end

local function RefreshLanternbearerSanityPenalty(owner)
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
            and key.prefab == "shadow_lanternbearer"
            and (pets == nil or pets[key] == nil or not key:IsValid()) then
            sanity:RemoveSanityPenalty(key)
        end
    end

    if pets ~= nil then
        for pet in pairs(pets) do
            if pet ~= nil and pet:IsValid() and pet.prefab == "shadow_lanternbearer" then
                local penalty = IsFreeShadowServant(pet) and 0 or GetLanternbearerPenalty(owner)

                if penalty ~= nil then
                    sanity:AddSanityPenalty(pet, penalty)

                    local base_penalty = TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_LANTERNBEARER
                        or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_WORKER
                    if base_penalty ~= nil and penalty ~= base_penalty then
                        MarkFragmentedMindPenaltyReduction(pet)
                    end
                else
                    sanity:RemoveSanityPenalty(pet)
                end

                if pet._waxwell_lanternbearer_penalty_remove_owner == nil then
                    pet._waxwell_lanternbearer_penalty_remove_owner = owner
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

local function EnsureLanternbearerSanityPenalty(owner, pet)
    if owner == nil
        or pet == nil
        or pet.prefab ~= "shadow_lanternbearer"
        or owner.components == nil
        or owner.components.sanity == nil then
        RefreshLanternbearerSanityPenalty(owner)
        return
    end

    local penalty = IsFreeShadowServant(pet) and 0 or GetLanternbearerPenalty(owner)

    if penalty ~= nil then
        owner.components.sanity:AddSanityPenalty(pet, penalty)

        local base_penalty = TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_LANTERNBEARER
            or TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_WORKER
        if base_penalty ~= nil and penalty ~= base_penalty then
            MarkFragmentedMindPenaltyReduction(pet)
        end
    else
        owner.components.sanity:RemoveSanityPenalty(pet)
    end

    if pet._waxwell_lanternbearer_penalty_remove_owner == nil then
        pet._waxwell_lanternbearer_penalty_remove_owner = owner
        pet:ListenForEvent("onremove", function(inst)
            if owner:IsValid() and owner.components ~= nil and owner.components.sanity ~= nil then
                owner.components.sanity:RemoveSanityPenalty(inst)
            end
        end)
    end

    RefreshLanternbearerSanityPenalty(owner)
end

local function RefreshLanternbearerSanityPenaltyForPet(pet, owner)
    if owner ~= nil and owner:IsValid() then
        RefreshLanternbearerSanityPenalty(owner)
    end
end

local function NotBlocked(pt)
    return pt ~= nil and not TheWorld.Map:IsGroundTargetBlocked(pt)
end

local function IsValidLanternTarget(player)
    return player ~= nil
        and player:IsValid()
        and player:HasTag("player")
        and not player:HasTag("playerghost")
        and player.entity:IsVisible()
end

local function FindLanternbearerForPlayer(player)
    if player == nil then
        return nil
    end

    local x, y, z = player.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(x, y, z, 30, { "shadow_lanternbearer" }, { "INLIMBO" })
    for _, ent in ipairs(ents) do
        if ent ~= nil
            and ent:IsValid()
            and ent._bound_target_userid ~= nil
            and ent._bound_target_userid == player.userid then
            return ent
        end
    end
end

local function FindNearestLanternTarget(pos)
    local bestfreeplayer = nil
    local bestfreedistsq = nil
    local hadplayerinrange = false
    local radius_sq = V.SHADOW_LANTERNBEARER_TARGET_WORK_RADIUS * V.SHADOW_LANTERNBEARER_TARGET_WORK_RADIUS

    for _, player in ipairs(AllPlayers) do
        if IsValidLanternTarget(player) then
            local distsq = player:GetDistanceSqToPoint(pos)
            if distsq <= radius_sq then
                hadplayerinrange = true
                if FindLanternbearerForPlayer(player) == nil then
                    if bestfreedistsq == nil or distsq < bestfreedistsq then
                        bestfreeplayer = player
                        bestfreedistsq = distsq
                    end
                end
            end
        end
    end

    return bestfreeplayer, hadplayerinrange
end

local function GetLanternbearerSpellName()
    return STRINGS.SPELLS[V.SHADOW_LANTERNBEARER_SPELL] or STRINGS.SPELLS.SHADOW_LANTERNBEARER
end

local function IsLanternbearerSpellBook(book)
    local spellbook = book ~= nil and book.components ~= nil and book.components.spellbook or nil
    local spellname = spellbook ~= nil and spellbook:GetSpellName() or nil
    local expected = GetLanternbearerSpellName()
    return expected ~= nil and spellname == expected
end

local function GetLanternTargetFailReason(pos)
    local target, hadplayerinrange = FindNearestLanternTarget(pos)
    if target == nil and hadplayerinrange then
        return "NO_LANTERN_NEEDED"
    elseif target == nil then
        return "NO_LANTERN_TARGET"
    end
end

local function GetLanternbearerCastFailLine(failreason)
    if failreason == nil then
        return nil
    end

    local castaoe = STRINGS.CHARACTERS ~= nil
        and STRINGS.CHARACTERS.WAXWELL ~= nil
        and STRINGS.CHARACTERS.WAXWELL.ACTIONFAIL ~= nil
        and STRINGS.CHARACTERS.WAXWELL.ACTIONFAIL.CASTAOE
        or nil

    return castaoe ~= nil and castaoe[failreason] or nil
end

local function SayLanternbearerCastFail(doer, failreason)
    local line = GetLanternbearerCastFailLine(failreason)
    if line == nil or doer == nil then
        return
    end

    local talker = doer.components ~= nil and doer.components.talker or nil
    if talker ~= nil
        and not (doer.components.health ~= nil and doer.components.health:IsDead()) then
        talker:Say(line)
    end
end

local function FailLanternbearerCast(doer, failreason)
    SayLanternbearerCastFail(doer, failreason)
    return false, failreason
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

local function TrySpawnLanternbearer(doer, pos)
    local petleash = doer.components.petleash
    if petleash == nil then
        return false
    end

    local target, hadplayerinrange = FindNearestLanternTarget(pos)
    if target == nil then
        return false, hadplayerinrange and "NO_LANTERN_NEEDED" or "NO_LANTERN_TARGET"
    end

    if FindLanternbearerForPlayer(target) ~= nil then
        return false, "HASPET"
    end

    local spawnpts = FindSpawnPoints(doer, pos, 1, 1)
    if #spawnpts <= 0 then
        return false
    end

    for _, pt in ipairs(spawnpts) do
        local pet = WithTemporaryPetLeashIsFull(petleash, IsShadowServantCapFull, function()
            return petleash:SpawnPetAt(pt.x, 0, pt.z, "shadow_lanternbearer")
        end)

        if pet ~= nil then
            if pet.SetWaxwellOwner ~= nil then
                pet:SetWaxwellOwner(doer)
            end
            if pet.SetTargetPlayer ~= nil and not pet:SetTargetPlayer(target) then
                return false
            end
            if IsShadowLanternbearer2Active(doer) and pet.MarkShadowLanternbearer2 ~= nil then
                pet:MarkShadowLanternbearer2()
            end
            EnsureLanternbearerSanityPenalty(doer, pet)
            pet:DoTaskInTime(0, RefreshLanternbearerSanityPenaltyForPet, doer)
            pet:DoTaskInTime(0.1, RefreshLanternbearerSanityPenaltyForPet, doer)
            if pet.SaveSpawnPoint ~= nil then
                pet:SaveSpawnPoint()
            end
            return true
        end
    end

    return false
end

local function CheckLanternbearerMaxSanity(doer, sanity)
    local penalty = GetLanternbearerPenalty(doer)

    return sanity ~= nil
        and penalty ~= nil
        and sanity:GetPenaltyPercent() + penalty <= TUNING.MAXIMUM_SANITY_PENALTY
end

local function ShouldRepeatCastLanternbearer(inst, doer)
    if doer == nil then
        return false
    end

    local sanity = doer.replica ~= nil and doer.replica.sanity
        or doer.components ~= nil and doer.components.sanity
        or nil
    if not CheckLanternbearerMaxSanity(doer, sanity) then
        return false
    end

    local petleash = doer.components ~= nil and doer.components.petleash or nil
    if petleash ~= nil and not CanAddShadowServant(petleash, "shadow_lanternbearer") then
        return false
    end

    local pc = doer.components ~= nil and doer.components.playercontroller or nil
    local pos = pc ~= nil and pc.reticule ~= nil and pc.reticule.targetpos or nil
    if pos ~= nil and GetLanternTargetFailReason(pos) ~= nil then
        return false
    end

    return true
end

local function LanternbearerSpellFn(inst, doer, pos)
    local sanity = doer ~= nil and doer.components ~= nil and doer.components.sanity or nil
    local petleash = doer ~= nil and doer.components ~= nil and doer.components.petleash or nil
    local penalty = GetLanternbearerPenalty(doer)
    local penaltypct = sanity ~= nil and sanity:GetPenaltyPercent() or nil
    local canadd = petleash ~= nil and CanAddShadowServant(petleash, "shadow_lanternbearer") or nil
    local target, hadplayerinrange = FindNearestLanternTarget(pos)

    if inst.components.fueled:IsEmpty() then
        return false, "NO_FUEL"
    elseif not HasCodexUmbraFuelForPct(inst, V.SHADOW_LANTERNBEARER_DURABILITY_COST_PCT) then
        return false, "NO_FUEL"
    elseif domain_expansion ~= nil and domain_expansion.IsDomainExpansionSummonLockActive ~= nil and domain_expansion.IsDomainExpansionSummonLockActive(doer) then
        return false, "HASPET"
    elseif target == nil and hadplayerinrange then
        return FailLanternbearerCast(doer, "NO_LANTERN_NEEDED")
    elseif target == nil then
        return FailLanternbearerCast(doer, "NO_LANTERN_TARGET")
    elseif not (sanity ~= nil
        and penalty ~= nil
        and penaltypct + penalty <= TUNING.MAXIMUM_SANITY_PENALTY
        and (petleash == nil or not IsShadowServantCapFull(petleash))
        and (petleash == nil or canadd)) then
        return false, "HASPET"
    end

    local success, reason = TrySpawnLanternbearer(doer, pos)
    if success then
        inst.components.fueled:DoDelta(SpellCost(V.SHADOW_LANTERNBEARER_DURABILITY_COST_PCT), doer)
        return true
    end

    if reason == "NO_LANTERN_NEEDED" or reason == "NO_LANTERN_TARGET" then
        return FailLanternbearerCast(doer, reason)
    end

    return false, reason
end

local function GetLanternbearerCastBlockReason(book, doer, pos)
    if not IsLanternbearerSpellBook(book) or pos == nil then
        return nil
    end

    return GetLanternTargetFailReason(pos)
end

local function PlayLanternbearerCastBlockedFeedback(pc, doer, failreason)
    TheFocalPoint.SoundEmitter:PlaySound("dontstarve/HUD/click_negative", nil, .4)
    if pc ~= nil and pc.reticule ~= nil and pc.reticule.Blip ~= nil then
        pc.reticule:Blip()
    end

    SayLanternbearerCastFail(doer or (pc ~= nil and pc.inst or nil), failreason)
end

local function GetShadowLanternbearerSpellData()
    return {
        label = STRINGS.SPELLS[V.SHADOW_LANTERNBEARER_SPELL],
        onselect = function(inst)
            inst.components.spellbook:SetSpellName(STRINGS.SPELLS[V.SHADOW_LANTERNBEARER_SPELL])
            inst.components.spellbook:SetSpellAction(nil)
            inst.components.aoetargeting:SetAlwaysValid(false)
            inst.components.aoetargeting:SetAllowWater(false)
            inst.components.aoetargeting:SetShouldRepeatCastFn(ShouldRepeatCastLanternbearer)
            ReticuleUtils.ApplySpellReticule(inst, inst.components.aoetargeting, V.SHADOW_LANTERNBEARER_RETICULE_SCALE, ReticuleUtils.ANIM_LARGE, {
                cast_range = ReticuleUtils.GetVanillaSummonCastRange(),
            })
            inst.components.aoetargeting:SetDeployRadius(0)
            if TheWorld.ismastersim then
                inst.components.aoetargeting:SetTargetFX("reticuleaoesummontarget_1d2")
                inst.components.aoespell:SetSpellFn(LanternbearerSpellFn)
                inst.components.spellbook:SetSpellFn(nil)
            end
        end,
        execute = StartAOETargeting,
        atlas = "images/waxwell/waxwell_codex_icon.xml",
        normal = "codex_umbra_shadow_lanternbearer.tex",
        widget_scale = V.SHADOW_LANTERNBEARER_ICON_SCALE,
        hit_radius = V.SHADOW_LANTERNBEARER_ICON_RADIUS,
    }
end

return {
    SHADOW_LANTERNBEARER_SPELL = V.SHADOW_LANTERNBEARER_SPELL,
    GetLanternbearerCastBlockReason = GetLanternbearerCastBlockReason,
    PlayLanternbearerCastBlockedFeedback = PlayLanternbearerCastBlockedFeedback,
    IsShadowLanternbearerSkillActive = IsShadowLanternbearerSkillActive,
    IsShadowLanternbearer2Active = IsShadowLanternbearer2Active,
    GetExpectedLanternbearerPenaltyTotal = GetExpectedLanternbearerPenaltyTotal,
    GetActualLanternbearerPenaltyTotal = GetActualLanternbearerPenaltyTotal,
    RefreshLanternbearerSanityPenalty = RefreshLanternbearerSanityPenalty,
    EnsureLanternbearerSanityPenalty = EnsureLanternbearerSanityPenalty,
    RefreshLanternbearerSanityPenaltyForPet = RefreshLanternbearerSanityPenaltyForPet,
    GetShadowLanternbearerSpellData = GetShadowLanternbearerSpellData,
}
