local spell_categories = require("skill_effect/waxwell/_shared/spell_categories")
local cost_gate = require("skill_effect/waxwell/_shared/codex_cost_gate")

local M = {}

local resolvers = {}

local function GetSpellName(book)
    local spellbook = book ~= nil and book.components ~= nil and book.components.spellbook
        or book ~= nil and book.replica ~= nil and book.replica.spellbook
        or nil
    return spellbook ~= nil and spellbook.GetSpellName ~= nil and spellbook:GetSpellName() or nil
end

function M.RegisterCastCostResolver(match_fn, resolve_fn)
    table.insert(resolvers, {
        match = match_fn,
        resolve = resolve_fn,
    })
end

function M.ResolveCastCosts(book, doer)
    for _, entry in ipairs(resolvers) do
        if entry.match(book, doer) then
            return entry.resolve(book, doer)
        end
    end

    return nil
end

function M.GetResourceBlockReason(book, doer)
    local costs = M.ResolveCastCosts(book, doer)
    if costs == nil then
        return nil
    end

    return cost_gate.GetResourceBlockReason(book, doer, costs)
end

function M.CanAffordCurrentCodexCast(book, doer)
    return M.GetResourceBlockReason(book, doer) == nil
end

local function RegisterWaxwellCastCosts()
    if M._waxwell_cast_costs_registered then
        return
    end

    M._waxwell_cast_costs_registered = true

    local umbra_common = require("skill_effect/waxwell/umbra/_shared/common")
    local umbra_V = require("skill_effect/waxwell/umbra/_shared/variables")
    local emperor_common = require("skill_effect/waxwell/emperor/_shared/common")
    local emperor_V = require("skill_effect/waxwell/emperor/_shared/variables")
    local puppeteer_cast = require("skill_effect/waxwell/puppeteer/_shared/cast_common")
    local puppeteer_V = require("skill_effect/waxwell/puppeteer/_shared/variables")
    local fragmented_mind = require("skill_effect/waxwell/puppeteer/fragmented_mind/common")
    local umbral_rift = require("skill_effect/waxwell/umbra/umbral_rift/common")
    local eclipse_fall = require("skill_effect/waxwell/umbra/eclipse_fall/common")

    local function GetUmbraMagicSanityCost(book, doer)
        local resolved = umbra_common.ResolveUmbraAoeSanityCost(book, doer)
        if resolved ~= nil then
            return resolved
        end

        if spell_categories.IsMagicSpell(book) then
            return TUNING.SANITY_MED
        end

        return nil
    end

    local function GetUmbraSpellFuelPct(book, doer)
        if umbra_common.IsShadowTrapSpell(book) then
            return umbra_common.IsLingeringDread2Active(doer)
                and umbra_V.UMBRA_SKILL_2_DURABILITY_COST_PCT
                or TUNING.WAXWELLJOURNAL_SPELL_COST.SHADOW_TRAP
        end
        if umbra_common.IsShadowPillarsSpell(book) then
            return umbra_common.IsAbyssalBinding2Active(doer)
                and umbra_V.UMBRA_SKILL_2_DURABILITY_COST_PCT
                or TUNING.WAXWELLJOURNAL_SPELL_COST.SHADOW_PILLARS
        end

        return nil
    end

    local ur_V = require("skill_effect/waxwell/umbra/umbral_rift/variables")
    local ef_V = require("skill_effect/waxwell/umbra/eclipse_fall/variables")

    M.RegisterCastCostResolver(umbral_rift.IsUmbralRiftBook, function(book, doer)
        return {
            fuel_pct = ur_V.UMBRAL_RIFT_DURABILITY_COST_PCT
                + (umbral_rift.IsUmbralRift2Active(doer) and ur_V.UMBRAL_RIFT_LV2_EXTRA_DURABILITY_COST_PCT or 0),
            sanity = umbral_rift.GetUmbralRiftSanityCost(doer),
        }
    end)

    M.RegisterCastCostResolver(function(book)
        local spellname = GetSpellName(book)
        return spellname == (STRINGS.SPELLS[ef_V.ECLIPSE_FALL_SPELL] or STRINGS.SPELLS.ECLIPSE_FALL or "Eclipse Fall")
    end, function(book, doer)
        -- Eclipse Fall spends all current Sanity (handled in its spell fn), so only durability is gated here.
        return {
            fuel_pct = eclipse_fall.GetEclipseFallDurabilityCostPct(doer),
        }
    end)

    M.RegisterCastCostResolver(function(book)
        return umbra_common.IsShadowTrapSpell(book) or umbra_common.IsShadowPillarsSpell(book)
    end, function(book, doer)
        return {
            fuel_pct = GetUmbraSpellFuelPct(book, doer),
            sanity = GetUmbraMagicSanityCost(book, doer),
        }
    end)

    M.RegisterCastCostResolver(function(book)
        local spellname = GetSpellName(book)
        return spellname == (STRINGS.SPELLS[emperor_common.SHADOW_STALKER_SPELL] or STRINGS.SPELLS.SHADOW_STALKER)
    end, function(book, doer)
        if emperor_common.GetShadowStalkerSpellState(doer) == "active" then
            return nil
        end
        return {
            fuel_pct = emperor_V.SHADOW_STALKER_DURABILITY_COST_PCT,
        }
    end)

    local domain_expansion = require("skill_effect/waxwell/emperor/domain_expansion/common")

    M.RegisterCastCostResolver(function(book)
        local spellname = GetSpellName(book)
        return spellname == (STRINGS.SPELLS[emperor_V.DOMAIN_EXPANSION_SPELL] or STRINGS.SPELLS.DOMAIN_EXPANSION)
    end, function(book, doer)
        if domain_expansion.GetDomainExpansionSpellState(doer) == "active" then
            return nil
        end
        return {
            fuel_pct = emperor_V.DOMAIN_EXPANSION_DURABILITY_COST_PCT,
        }
    end)

    local fissure_eruption = require("skill_effect/waxwell/emperor/fissure_eruption/common")

    M.RegisterCastCostResolver(function(book)
        local spellname = GetSpellName(book)
        return spellname == (STRINGS.SPELLS[emperor_V.FISSURE_ERUPTION_SPELL] or "Fissure Eruption")
    end, function(book, doer)
        if fissure_eruption.GetFissureEruptionSpellState(doer) ~= nil then
            return nil
        end
        return {
            fuel_pct = emperor_V.FISSURE_ERUPTION_DURABILITY_COST_PCT,
            sanity = fissure_eruption.GetFissureEruptionSanityCost(doer),
        }
    end)

    local shadow_reliquary = require("skill_effect/waxwell/emperor/shadow_reliquary/common")

    M.RegisterCastCostResolver(function(book)
        local spellname = GetSpellName(book)
        return spellname == (STRINGS.SPELLS[emperor_V.SHADOW_RELIQUARY_SPELL] or "Shadow Reliquary")
    end, function(book, doer)
        if shadow_reliquary.GetShadowReliquarySpellState(doer) ~= nil then
            return nil
        end
        return {
            fuel_pct = emperor_V.SHADOW_RELIQUARY_DURABILITY_COST_PCT,
            sanity = shadow_reliquary.GetShadowReliquarySanityCost(doer),
        }
    end)

    M.RegisterCastCostResolver(function(book)
        local spellname = GetSpellName(book)
        return spellname == (STRINGS.SPELLS[puppeteer_V.SHADOW_LANTERNBEARER_SPELL] or STRINGS.SPELLS.SHADOW_LANTERNBEARER)
    end, function(book, doer)
        local pct = puppeteer_cast.GetShadowServantCodexCostPct("shadow_lanternbearer", doer)
            or puppeteer_V.SHADOW_LANTERNBEARER_DURABILITY_COST_PCT
        return { fuel_pct = pct }
    end)

    M.RegisterCastCostResolver(function(book)
        local spellname = GetSpellName(book)
        return spellname == (STRINGS.SPELLS[puppeteer_V.SHADOW_MARKSMAN_SPELL] or STRINGS.SPELLS.SHADOW_MARKSMAN)
    end, function(book, doer)
        local pct = puppeteer_cast.GetShadowServantCodexCostPct("shadow_marksman", doer)
            or puppeteer_V.SHADOW_MARKSMAN_DURABILITY_COST_PCT
        return { fuel_pct = pct }
    end)

    M.RegisterCastCostResolver(function(book)
        return fragmented_mind.GetFragmentedMindSpellPuppet(book) ~= nil
    end, function(book, doer)
        local prefab = fragmented_mind.GetFragmentedMindSpellPuppet(book)
        return {
            fuel_pct = puppeteer_cast.GetShadowServantCodexCostPct(prefab, doer),
        }
    end)
end

function M.EnsureRegistered()
    RegisterWaxwellCastCosts()
end

return M
