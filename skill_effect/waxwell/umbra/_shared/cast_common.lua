local spell_categories = require("skill_effect/waxwell/_shared/spell_categories")
local spell_utils = require("skill_effect/waxwell/_shared/codex_spell_utils")
local debug = require("debug/init")
local V = require("skill_effect/waxwell/umbra/_shared/variables")

local lingering_dread_common = nil
local abyssal_binding_common = nil
local dark_scholar_common = nil

local function GetLingeringDreadCommon()
    if lingering_dread_common == nil then
        lingering_dread_common = require("skill_effect/waxwell/umbra/lingering_dread/common")
    end
    return lingering_dread_common
end

local function GetAbyssalBindingCommon()
    if abyssal_binding_common == nil then
        abyssal_binding_common = require("skill_effect/waxwell/umbra/abyssal_binding/common")
    end
    return abyssal_binding_common
end

local function GetDarkScholarCommon()
    if dark_scholar_common == nil then
        dark_scholar_common = require("skill_effect/waxwell/umbra/dark_scholar/common")
    end
    return dark_scholar_common
end

local function IsDarkScholarSpell(inst)
    return spell_categories.IsMagicSpell(inst)
end

local function IsShadowTrapSpell(inst)
    local spellbook = inst ~= nil and inst.components ~= nil and inst.components.spellbook or nil
    return spellbook ~= nil and spellbook:GetSpellName() == STRINGS.SPELLS.SHADOW_TRAP
end

local function IsShadowPillarsSpell(inst)
    local spellbook = inst ~= nil and inst.components ~= nil and inst.components.spellbook or nil
    return spellbook ~= nil and spellbook:GetSpellName() == STRINGS.SPELLS.SHADOW_PILLARS
end

local function SpellCost(pct)
    if debug.ShouldIgnoreCodexUmbraDurability() then
        return 0
    end
    return pct * TUNING.LARGE_FUEL * -4
end

local function HasEnoughCodexFuel(inst, costpct)
    if debug.ShouldIgnoreCodexUmbraDurability() then
        return true
    end
    local fueled = inst ~= nil and inst.components ~= nil and inst.components.fueled or nil
    local cost = SpellCost(costpct)
    return fueled ~= nil
        and fueled.currentfuel ~= nil
        and cost ~= nil
        and fueled.currentfuel >= math.abs(cost) - .001
end

local IsSpellOnCooldown = spell_utils.IsSpellOnCooldown
local GetSpellCooldownPercent = spell_utils.GetSpellCooldownPercent
local RestartSpellCooldown = spell_utils.RestartSpellCooldown
local StartAOETargeting = spell_utils.StartAOETargeting

local function NotBlocked(pt)
    return pt ~= nil and not TheWorld.Map:IsGroundTargetBlocked(pt)
end

local function IsPassableGroundPoint(pt)
    return pt ~= nil
        and TheWorld.Map:IsAboveGroundAtPoint(pt.x, 0, pt.z)
        and not TheWorld.Map:IsOceanAtPoint(pt.x, 0, pt.z, false)
        and TheWorld.Map:IsPassableAtPoint(pt.x, 0, pt.z, true)
        and NotBlocked(pt)
end
local function IsFriendlyOrSummonedTarget(ent)
    if ent == nil then
        return true
    end

    if ent:HasTag("player")
        or ent:HasTag("companion")
        or ent:HasTag("playerpet")
        or ent:HasTag("shadowminion")
        or ent:HasTag("stalkerminion")
        or ent:HasTag("chester")
        or ent:HasTag("hutch")
        or ent:HasTag("glommer")
        or ent:HasTag("abigail")
        or ent:HasTag("structure")
        or ent:HasTag("wall") then
        return true
    end

    local follower = ent.components ~= nil and ent.components.follower or nil
    local leader = follower ~= nil and follower:GetLeader() or nil
    if leader ~= nil and (leader:HasTag("player") or leader:HasTag("companion") or leader:HasTag("shadowmagic")) then
        return true
    end

    return false
end
local function GetCodexUmbraFuelCost(pct)
    return pct ~= nil and pct * TUNING.LARGE_FUEL * -4 or nil
end

local function WithAdjustedCodexUmbraCastCosts(fueled, expectedfueldelta, adjustedfueldelta, sanity, expectedsanitydelta, adjustedsanitydelta, fn)
    if fn == nil then
        return
    end

    local old_FueledDoDelta = fueled ~= nil and fueled.DoDelta or nil
    if old_FueledDoDelta ~= nil and expectedfueldelta ~= nil and adjustedfueldelta ~= nil then
        fueled.DoDelta = function(self, delta, ...)
            if delta ~= nil and math.abs(delta - expectedfueldelta) < .001 then
                delta = adjustedfueldelta
            end

            return old_FueledDoDelta(self, delta, ...)
        end
    end

    local old_SanityDoDelta = sanity ~= nil and sanity.DoDelta or nil
    if old_SanityDoDelta ~= nil and expectedsanitydelta ~= nil and adjustedsanitydelta ~= nil then
        sanity.DoDelta = function(self, delta, ...)
            if delta == expectedsanitydelta then
                delta = adjustedsanitydelta
            end

            return old_SanityDoDelta(self, delta, ...)
        end
    end

    local ok, result, reason = xpcall(fn, debug.traceback)

    if old_FueledDoDelta ~= nil then
        fueled.DoDelta = old_FueledDoDelta
    end
    if old_SanityDoDelta ~= nil then
        sanity.DoDelta = old_SanityDoDelta
    end

    if not ok then
        error(result)
    end

    return result, reason
end

local function GetUmbraSkill2FuelCostPct(book, doer)
    if IsShadowTrapSpell(book) and GetLingeringDreadCommon().IsLingeringDread2Active(doer) then
        return TUNING.WAXWELLJOURNAL_SPELL_COST.SHADOW_TRAP
    end
    if IsShadowPillarsSpell(book) and GetAbyssalBindingCommon().IsAbyssalBinding2Active(doer) then
        return TUNING.WAXWELLJOURNAL_SPELL_COST.SHADOW_PILLARS
    end
    return nil
end

local function ResolveUmbraAoeSanityCost(book, doer)
    if not IsShadowTrapSpell(book) and not IsShadowPillarsSpell(book) then
        return nil
    end

    local cost = TUNING.SANITY_MED
    if IsShadowTrapSpell(book) and GetLingeringDreadCommon().IsLingeringDread2Active(doer) then
        cost = math.abs(V.UMBRA_SKILL_2_SANITY_COST)
    elseif IsShadowPillarsSpell(book) and GetAbyssalBindingCommon().IsAbyssalBinding2Active(doer) then
        cost = math.abs(V.UMBRA_SKILL_2_SANITY_COST)
    end

    return GetDarkScholarCommon().GetDarkScholarSanityCost(cost, doer)
end

local function WithAdjustedUmbraAoeCastCosts(book, doer, fn)
    if fn == nil then
        return
    end

    local skill2fuelpct = GetUmbraSkill2FuelCostPct(book, doer)
    local finalsanitycost = ResolveUmbraAoeSanityCost(book, doer)
    if finalsanitycost == nil then
        return fn()
    end

    local needsfueladjust = skill2fuelpct ~= nil
    local needssanityadjust = finalsanitycost ~= TUNING.SANITY_MED
    if not needsfueladjust and not needssanityadjust then
        return fn()
    end

    local fueled = book ~= nil and book.components ~= nil and book.components.fueled or nil
    local sanity = doer ~= nil and doer.components ~= nil and doer.components.sanity or nil
    if fueled == nil or sanity == nil then
        return fn()
    end

    return WithAdjustedCodexUmbraCastCosts(
        fueled,
        needsfueladjust and GetCodexUmbraFuelCost(skill2fuelpct) or nil,
        needsfueladjust and GetCodexUmbraFuelCost(V.UMBRA_SKILL_2_DURABILITY_COST_PCT) or nil,
        sanity,
        needssanityadjust and V.DARK_SCHOLAR_BASE_SANITY_COST or nil,
        needssanityadjust and -finalsanitycost or nil,
        fn
    )
end

local function WithAdjustedUmbraSkill2CastCosts(book, doer, spellcostpct, fn)
    if fn == nil then
        return
    end

    local fueled = book ~= nil and book.components ~= nil and book.components.fueled or nil
    local sanity = doer ~= nil and doer.components ~= nil and doer.components.sanity or nil
    if fueled == nil or sanity == nil then
        return fn()
    end

    return WithAdjustedCodexUmbraCastCosts(
        fueled,
        GetCodexUmbraFuelCost(spellcostpct),
        GetCodexUmbraFuelCost(V.UMBRA_SKILL_2_DURABILITY_COST_PCT),
        sanity,
        V.DARK_SCHOLAR_BASE_SANITY_COST,
        V.UMBRA_SKILL_2_SANITY_COST,
        fn
    )
end

local IsSpellOnCooldown = spell_utils.IsSpellOnCooldown
local GetSpellCooldownPercent = spell_utils.GetSpellCooldownPercent
local RestartSpellCooldown = spell_utils.RestartSpellCooldown
local StartAOETargeting = spell_utils.StartAOETargeting

return {
    IsDarkScholarSpell = IsDarkScholarSpell,
    IsShadowTrapSpell = IsShadowTrapSpell,
    IsShadowPillarsSpell = IsShadowPillarsSpell,
    SpellCost = SpellCost,
    HasEnoughCodexFuel = HasEnoughCodexFuel,
    NotBlocked = NotBlocked,
    IsPassableGroundPoint = IsPassableGroundPoint,
    IsFriendlyOrSummonedTarget = IsFriendlyOrSummonedTarget,
    IsSpellOnCooldown = IsSpellOnCooldown,
    GetSpellCooldownPercent = GetSpellCooldownPercent,
    RestartSpellCooldown = RestartSpellCooldown,
    StartAOETargeting = StartAOETargeting,
    GetCodexUmbraFuelCost = GetCodexUmbraFuelCost,
    GetUmbraSkill2FuelCostPct = GetUmbraSkill2FuelCostPct,
    ResolveUmbraAoeSanityCost = ResolveUmbraAoeSanityCost,
    WithAdjustedCodexUmbraCastCosts = WithAdjustedCodexUmbraCastCosts,
    WithAdjustedUmbraAoeCastCosts = WithAdjustedUmbraAoeCastCosts,
    WithAdjustedUmbraSkill2CastCosts = WithAdjustedUmbraSkill2CastCosts,
}