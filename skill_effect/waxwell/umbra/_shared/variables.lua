local dark_scholar = require("skill_effect/waxwell/umbra/dark_scholar/variables")
local measured_invocation = require("skill_effect/waxwell/umbra/measured_invocation/variables")
local umbral_rift = require("skill_effect/waxwell/umbra/umbral_rift/variables")
local eclipse_fall = require("skill_effect/waxwell/umbra/eclipse_fall/variables")
local lingering_dread = require("skill_effect/waxwell/umbra/lingering_dread/variables")
local abyssal_binding = require("skill_effect/waxwell/umbra/abyssal_binding/variables")

local M = {
    DARK_SCHOLAR_BASE_SANITY_COST = -TUNING.SANITY_MED,
    UMBRA_SKILL_2_SANITY_COST = -20,
    UMBRA_SKILL_2_DURABILITY_COST_PCT = .10,
    SHADOW_TRAP_COOLDOWN_ID = "shadow_trap",
    SHADOW_PILLARS_COOLDOWN_ID = "shadow_pillars",
    UMBRA_BASE_SPELL_COOLDOWN_TIME = 10,
}
for _, src in ipairs({
    dark_scholar,
    measured_invocation,
    umbral_rift,
    eclipse_fall,
    lingering_dread,
    abyssal_binding,
}) do
    for k, v in pairs(src) do
        M[k] = v
    end
end

return M
