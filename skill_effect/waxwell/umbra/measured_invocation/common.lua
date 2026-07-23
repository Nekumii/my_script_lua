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
local V = require("skill_effect/waxwell/umbra/measured_invocation/variables")

local function IsMeasuredInvocationActive(inst)
    return inst ~= nil
        and inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_measured_invocation")
end
local function WithMeasuredInvocationCodexDurabilityChance(book, fn, savechance)
    if fn == nil then
        return
    end

    local fueled = book ~= nil and book.components ~= nil and book.components.fueled or nil
    if fueled == nil then
        return fn()
    end

    local old_DoDelta = fueled.DoDelta
    local rolled = false
    fueled.DoDelta = function(self, delta, ...)
        if delta ~= nil and delta < 0 and not rolled then
            rolled = true
            if math.random() < (savechance or V.MEASURED_INVOCATION_DURABILITY_SAVE_CHANCE) then
                delta = 0
            end
        end

        return old_DoDelta(self, delta, ...)
    end

    local ok, result, reason = xpcall(fn, debug.traceback)
    fueled.DoDelta = old_DoDelta

    if not ok then
        error(result)
    end

    return result, reason
end

return {
    IsMeasuredInvocationActive = IsMeasuredInvocationActive,
    WithMeasuredInvocationCodexDurabilityChance = WithMeasuredInvocationCodexDurabilityChance,
}