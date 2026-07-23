STRINGS.SPELLS = STRINGS.SPELLS or {}

local FRAGMENTED_MIND_BASE_PENALTY = .15
local FRAGMENTED_MIND_PENALTY = .10
local FRAGMENTED_MIND_PENALTY_TAG = "fragmented_mind_shadow_penalty_reduced"
local FRAGMENTED_MIND_PUPPETS =
{
    shadowworker = true,
    shadowprotector = true,
    shadow_lanternbearer = true,
    shadow_marksman = true,
    shadow_stalker = true,
}
local FRAGMENTED_MIND_REDUCED_PENALTIES =
{
    shadowworker = .10,
    shadowprotector = .10,
    shadow_lanternbearer = .10,
    shadow_marksman = .10,
    shadow_stalker = .70,
}
local FRAGMENTED_MIND_SPELLS =
{
    [STRINGS.SPELLS.SHADOW_WORKER] = "shadowworker",
    [STRINGS.SPELLS.SHADOW_PROTECTOR] = "shadowprotector",
}

return {
    FRAGMENTED_MIND_BASE_PENALTY = FRAGMENTED_MIND_BASE_PENALTY,
    FRAGMENTED_MIND_PENALTY = FRAGMENTED_MIND_PENALTY,
    FRAGMENTED_MIND_PENALTY_TAG = FRAGMENTED_MIND_PENALTY_TAG,
    FRAGMENTED_MIND_PUPPETS = FRAGMENTED_MIND_PUPPETS,
    FRAGMENTED_MIND_REDUCED_PENALTIES = FRAGMENTED_MIND_REDUCED_PENALTIES,
    FRAGMENTED_MIND_SPELLS = FRAGMENTED_MIND_SPELLS,
}
