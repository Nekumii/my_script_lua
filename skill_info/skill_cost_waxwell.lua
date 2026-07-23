local skill_cost_display = require("skill_info/skill_cost_display")

local fragmented_mind_V = require("skill_effect/waxwell/puppeteer/fragmented_mind/variables")
local tireless_V = require("skill_effect/waxwell/puppeteer/tireless_servant/variables")
local lethal_V = require("skill_effect/waxwell/puppeteer/lethal_apparition/variables")
local lantern_V = require("skill_effect/waxwell/puppeteer/shadow_lanternbearer/variables")
local marksman_V = require("skill_effect/waxwell/puppeteer/shadow_marksman/variables")
local umbra_V = require("skill_effect/waxwell/umbra/_shared/variables")
local stalker_V = require("skill_effect/waxwell/emperor/shadow_stalker/variables")
local domain_V = require("skill_effect/waxwell/emperor/domain_expansion/variables")
local fissure_V = require("skill_effect/waxwell/emperor/fissure_eruption/variables")
local reliquary_V = require("skill_effect/waxwell/emperor/shadow_reliquary/variables")
local dread_V = require("skill_effect/waxwell/sovereign/dread_tribute/variables")

local M = {}

local function Pct(value)
    return math.floor((value or 0) * 100 + 0.5)
end

local function AbsSanity(value)
    return math.floor(math.abs(value or 0) + 0.5)
end

local SUMMON_PENALTY_PCT = Pct(fragmented_mind_V.FRAGMENTED_MIND_BASE_PENALTY)
local UMBRA_SANITY_T1 = AbsSanity(umbra_V.DARK_SCHOLAR_BASE_SANITY_COST)
local UMBRA_SANITY_T2 = AbsSanity(umbra_V.UMBRA_SKILL_2_SANITY_COST)

local COSTS =
{
    waxwell_tireless_servant_1 = {
        durability_pct = Pct(tireless_V.TIRELESS_SERVANT_2_BASE_DURABILITY_COST_PCT),
        sanity_penalty_pct = SUMMON_PENALTY_PCT,
    },
    waxwell_tireless_servant_2 = {
        durability_pct = Pct(tireless_V.TIRELESS_SERVANT_2_DURABILITY_COST_PCT),
        sanity_penalty_pct = SUMMON_PENALTY_PCT,
    },
    waxwell_lethal_apparition_1 = {
        durability_pct = Pct(lethal_V.LETHAL_APPARITION_2_BASE_DURABILITY_COST_PCT),
        sanity_penalty_pct = SUMMON_PENALTY_PCT,
    },
    waxwell_lethal_apparition_2 = {
        durability_pct = Pct(lethal_V.LETHAL_APPARITION_2_DURABILITY_COST_PCT),
        sanity_penalty_pct = SUMMON_PENALTY_PCT,
    },
    waxwell_shadow_lanternbearer_1 = {
        durability_pct = Pct(lantern_V.SHADOW_LANTERNBEARER_2_BASE_DURABILITY_COST_PCT),
        sanity_penalty_pct = SUMMON_PENALTY_PCT,
    },
    waxwell_shadow_lanternbearer_2 = {
        durability_pct = Pct(lantern_V.SHADOW_LANTERNBEARER_2_DURABILITY_COST_PCT),
        sanity_penalty_pct = SUMMON_PENALTY_PCT,
    },
    waxwell_shadow_marksman_1 = {
        durability_pct = Pct(marksman_V.SHADOW_MARKSMAN_2_BASE_DURABILITY_COST_PCT),
        sanity_penalty_pct = SUMMON_PENALTY_PCT,
    },
    waxwell_shadow_marksman_2 = {
        durability_pct = Pct(marksman_V.SHADOW_MARKSMAN_2_DURABILITY_COST_PCT),
        sanity_penalty_pct = SUMMON_PENALTY_PCT,
    },

    waxwell_lingering_dread_1 = {
        durability_pct = Pct(umbra_V.UMBRAL_RIFT_DURABILITY_COST_PCT),
        sanity_flat = UMBRA_SANITY_T1,
    },
    waxwell_lingering_dread_2 = {
        durability_pct = Pct(umbra_V.UMBRA_SKILL_2_DURABILITY_COST_PCT),
        sanity_flat = UMBRA_SANITY_T2,
    },
    waxwell_abyssal_binding_1 = {
        durability_pct = Pct(umbra_V.UMBRAL_RIFT_DURABILITY_COST_PCT),
        sanity_flat = UMBRA_SANITY_T1,
    },
    waxwell_abyssal_binding_2 = {
        durability_pct = Pct(umbra_V.UMBRA_SKILL_2_DURABILITY_COST_PCT),
        sanity_flat = UMBRA_SANITY_T2,
    },
    waxwell_umbral_rift_1 = {
        durability_pct = Pct(umbra_V.UMBRAL_RIFT_DURABILITY_COST_PCT),
        sanity_flat = UMBRA_SANITY_T1,
    },
    waxwell_umbral_rift_2 = {
        durability_pct = Pct(umbra_V.UMBRA_SKILL_2_DURABILITY_COST_PCT),
        sanity_flat = UMBRA_SANITY_T2,
    },
    waxwell_eclipse_fall_1 = {
        durability_pct = Pct(umbra_V.ECLIPSE_FALL_DURABILITY_COST_PCT),
        sanity_all = true,
    },
    waxwell_eclipse_fall_2 = {
        durability_pct = Pct(umbra_V.ECLIPSE_FALL_DURABILITY_COST_PCT + umbra_V.ECLIPSE_FALL_LV2_EXTRA_DURABILITY_COST_PCT),
        sanity_all = true,
    },

    waxwell_shadow_stalker = {
        durability_pct = Pct(stalker_V.SHADOW_STALKER_DURABILITY_COST_PCT),
        sanity_penalty_pct = 75,
    },
    waxwell_domain_expansion = {
        durability_pct = Pct(domain_V.DOMAIN_EXPANSION_DURABILITY_COST_PCT),
        sanity_cast_min = domain_V.DOMAIN_EXPANSION_SANITY_CAST_MIN,
    },
    waxwell_fissure_eruption = {
        durability_pct = Pct(fissure_V.FISSURE_ERUPTION_DURABILITY_COST_PCT),
        sanity_flat = fissure_V.FISSURE_ERUPTION_SANITY_COST,
    },
    waxwell_shadow_reliquary = {
        durability_pct = Pct(reliquary_V.SHADOW_RELIQUARY_DURABILITY_COST_PCT),
        sanity_flat = reliquary_V.SHADOW_RELIQUARY_SANITY_COST,
    },

    waxwell_dread_tribute_1 = {
        sanity_discount = {
            base = dread_V.DREAD_TRIBUTE_1_SANITY_COST,
            rehit = 1,
        },
    },
    waxwell_dread_tribute_2 = {
        sanity_discount = {
            base = dread_V.DREAD_TRIBUTE_1_SANITY_COST,
            rehit = 1,
        },
    },
}

local function GetWaxwellCost(skill_id)
    return COSTS[skill_id]
end

function M.Register()
    skill_cost_display.RegisterCharacter("waxwell", GetWaxwellCost)
end

return M
