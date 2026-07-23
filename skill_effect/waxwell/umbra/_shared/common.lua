local cast = require("skill_effect/waxwell/umbra/_shared/cast_common")
local dark_scholar = require("skill_effect/waxwell/umbra/dark_scholar/common")
local measured_invocation = require("skill_effect/waxwell/umbra/measured_invocation/common")
local lingering_dread = require("skill_effect/waxwell/umbra/lingering_dread/common")
local abyssal_binding = require("skill_effect/waxwell/umbra/abyssal_binding/common")
local umbral_rift = require("skill_effect/waxwell/umbra/umbral_rift/common")
local eclipse_fall = require("skill_effect/waxwell/umbra/eclipse_fall/common")
local V = require("skill_effect/waxwell/umbra/_shared/variables")
local base_spell_cooldown = require("skill_effect/waxwell/umbra/_shared/base_spell_cooldown")
local codex_spell_sort = require("skill_effect/waxwell/_shared/codex_spell_sort")

local function BuildUmbraSpellList(baseitems, user)
    local items = {}
    if baseitems ~= nil then
        for _, item in ipairs(baseitems) do
            table.insert(items, item)
        end
    end

    local hasumbralrift = false
    local haseclipsefall = false
    local umbralriftlabel = STRINGS.SPELLS[V.UMBRAL_RIFT_SPELL]
    local eclipsefalllabel = STRINGS.SPELLS[eclipse_fall.ECLIPSE_FALL_SPELL] or "Eclipse Fall"

    for _, item in ipairs(items) do
        if item ~= nil and item.label == umbralriftlabel then
            hasumbralrift = true
        elseif item ~= nil and item.label == eclipsefalllabel then
            haseclipsefall = true
        end
        if hasumbralrift and haseclipsefall then
            break
        end
    end

    if umbral_rift.IsUmbralRiftSkillActive(user) and not hasumbralrift then
        table.insert(items, umbral_rift.GetUmbralRiftSpellData())
    end
    if eclipse_fall.IsEclipseFallSkillActive(user) and not haseclipsefall then
        table.insert(items, eclipse_fall.GetEclipseFallSpellData())
    end

    return base_spell_cooldown.DecorateSpellItems(codex_spell_sort.SortSpellList(items))
end

local M = {
    BuildUmbraSpellList = BuildUmbraSpellList,
}
for _, src in ipairs({
    cast,
    dark_scholar,
    measured_invocation,
    lingering_dread,
    abyssal_binding,
    umbral_rift,
    eclipse_fall,
}) do
    for k, v in pairs(src) do
        M[k] = v
    end
end

M.UMBRA_SKILL_2_DURABILITY_COST_PCT = V.UMBRA_SKILL_2_DURABILITY_COST_PCT

return M
