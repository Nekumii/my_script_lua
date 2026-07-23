local spell_categories = require("skill_effect/waxwell/_shared/spell_categories")
local spell_utils = require("skill_effect/waxwell/_shared/codex_spell_utils")
local persist_utils = require("skill_effect/waxwell/_shared/persist_utils")
local shared = require("skill_effect/waxwell/umbra/_shared/cast_common")

local SpellCost = shared.SpellCost
local HasEnoughCodexFuel = shared.HasEnoughCodexFuel
local NotBlocked = shared.NotBlocked
local IsPassableGroundPoint = shared.IsPassableGroundPoint
local IsFriendlyOrSummonedTarget = shared.IsFriendlyOrSummonedTarget
local IsSpellOnCooldown = shared.IsSpellOnCooldown
local GetSpellCooldownPercent = shared.GetSpellCooldownPercent
local RestartSpellCooldown = shared.RestartSpellCooldown
local StartAOETargeting = shared.StartAOETargeting
local V = require("skill_effect/waxwell/umbra/dark_scholar/variables")

local function IsDarkScholarActive(inst)
    return inst ~= nil
        and inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_dark_scholar")
end

local function GetDarkScholarSanityCost(base_cost, doer)
    if base_cost == nil or base_cost <= 0 or not IsDarkScholarActive(doer) then
        return base_cost
    end

    local discount = V.DARK_SCHOLAR_SANITY_DISCOUNT

    return math.max(0, base_cost - discount)
end

local function GetDarkScholarSanityDelta(base_delta, doer)
    if base_delta == nil or base_delta >= 0 then
        return base_delta
    end

    return -GetDarkScholarSanityCost(math.abs(base_delta), doer)
end

local function WithAdjustedSanityDelta(sanity, expecteddelta, adjusteddelta, fn)
    if sanity == nil or fn == nil or expecteddelta == nil or adjusteddelta == nil or expecteddelta == adjusteddelta then
        return fn()
    end

    local old_DoDelta = sanity.DoDelta
    sanity.DoDelta = function(self, delta, ...)
        if delta == expecteddelta then
            delta = adjusteddelta
        end

        return old_DoDelta(self, delta, ...)
    end

    local ok, result, reason = xpcall(fn, debug.traceback)
    sanity.DoDelta = old_DoDelta

    if not ok then
        error(result)
    end

    return result, reason
end

return {
    IsDarkScholarActive = IsDarkScholarActive,
    GetDarkScholarSanityCost = GetDarkScholarSanityCost,
    GetDarkScholarSanityDelta = GetDarkScholarSanityDelta,
    WithAdjustedSanityDelta = WithAdjustedSanityDelta,
}