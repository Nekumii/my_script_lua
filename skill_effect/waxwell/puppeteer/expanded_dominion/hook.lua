local fragmented_mind_hook = require("skill_effect/waxwell/puppeteer/fragmented_mind/hook")
local common = require("skill_effect/waxwell/puppeteer/_shared/common")
local expanded_dominion_common = require("skill_effect/waxwell/puppeteer/expanded_dominion/common")

local RefreshAllShadowServantSanityPenalties = fragmented_mind_hook.RefreshAllShadowServantSanityPenalties
local RefreshLanternbearerSanityPenalty = common.RefreshLanternbearerSanityPenalty
local RefreshMarksmanSanityPenalty = common.RefreshMarksmanSanityPenalty

local M = {}

local function SyncExpandedDominionPetSlots(owner)
    local petleash = owner ~= nil and owner.components ~= nil and owner.components.petleash or nil
    if petleash == nil then
        return
    end

    local targetmax = expanded_dominion_common.GetExpandedDominionMaxPets(petleash)
    if petleash:GetMaxPets() ~= targetmax then
        petleash:SetMaxPets(targetmax)
    end
end

local function RefreshWaxwellShadowServantState(owner)
    if owner == nil or owner.components == nil then
        return
    end

    SyncExpandedDominionPetSlots(owner)
    RefreshAllShadowServantSanityPenalties(owner)
    RefreshMarksmanSanityPenalty(owner)
    RefreshLanternbearerSanityPenalty(owner)
end

M.RefreshWaxwellShadowServantState = RefreshWaxwellShadowServantState

local SKILLS_REFRESH_SHADOW_SERVANTS =
{
    waxwell_expanded_dominion = true,
    waxwell_fragmented_mind = true,
    waxwell_inner_incarnate = true,
}

local function MaybeRefreshShadowServantState(inst, skill)
    if inst ~= nil
        and inst.prefab == "waxwell"
        and (skill == nil or SKILLS_REFRESH_SHADOW_SERVANTS[skill]) then
        inst:DoTaskInTime(0, RefreshWaxwellShadowServantState)
    end
end

function M.Register(env)
    env.AddPrefabPostInit("waxwell", function(inst)
        if not TheWorld.ismastersim or inst._waxwell_expanded_dominion_events then
            return
        end

        inst._waxwell_expanded_dominion_events = true

        inst:ListenForEvent("onactivateskill_server", function(_, data)
            MaybeRefreshShadowServantState(inst, data ~= nil and data.skill or nil)
        end)
        inst:ListenForEvent("ondeactivateskill_server", function(_, data)
            MaybeRefreshShadowServantState(inst, data ~= nil and data.skill or nil)
        end)
        inst:ListenForEvent("onsetskillselection_server", function()
            MaybeRefreshShadowServantState(inst, nil)
        end)
    end)
end

return M
