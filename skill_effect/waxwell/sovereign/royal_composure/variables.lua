local ROYAL_COMPOSURE_NEGATIVE_RATE_MULT = .50
local LIGHT_SANITY_DRAINS =
{
    [SANITY_MODE_INSANITY] =
    {
        DAY = TUNING.SANITY_DAY_GAIN,
        NIGHT_LIGHT = TUNING.SANITY_NIGHT_LIGHT,
        NIGHT_DIM = TUNING.SANITY_NIGHT_MID,
        NIGHT_DARK = TUNING.SANITY_NIGHT_DARK,
    },
    [SANITY_MODE_LUNACY] =
    {
        DAY = TUNING.SANITY_LUNACY_DAY_GAIN,
        NIGHT_LIGHT = TUNING.SANITY_LUNACY_NIGHT_LIGHT,
        NIGHT_DIM = TUNING.SANITY_LUNACY_NIGHT_MID,
        NIGHT_DARK = TUNING.SANITY_LUNACY_NIGHT_DARK,
    },
}
local SANITYRECALC_MUST_TAGS = { "sanityaura" }
local SANITYRECALC_CANT_TAGS = { "FX", "NOCLICK", "DECOR", "INLIMBO" }

local ROYAL_COMPOSURE_BONUS_FUEL_CHANCE = .50
local ROYAL_COMPOSURE_BONUS_DROP_PREFAB = "nightmarefuel"

-- Non-shadow_creature_targets kills that should still roll bonus fuel when they
-- actually drop nightmarefuel (insane/nightmare transforms, chess, stalker).
local ROYAL_COMPOSURE_FUEL_DROP_EXTRA_TARGETS =
{
    rabbit = true,          -- beardling (insane form keeps prefab "rabbit")
    crab = true,            -- insane crab form (mod-provided; harmless if absent)
    monkey = true,          -- nightmare monkey (keeps prefab "monkey")
    knight_nightmare = true,
    bishop_nightmare = true,
    rook_nightmare = true,
    stalker = true,
    stalker_atrium = true,
}

return {
    ROYAL_COMPOSURE_NEGATIVE_RATE_MULT = ROYAL_COMPOSURE_NEGATIVE_RATE_MULT,
    LIGHT_SANITY_DRAINS = LIGHT_SANITY_DRAINS,
    SANITYRECALC_MUST_TAGS = SANITYRECALC_MUST_TAGS,
    SANITYRECALC_CANT_TAGS = SANITYRECALC_CANT_TAGS,
    ROYAL_COMPOSURE_BONUS_FUEL_CHANCE = ROYAL_COMPOSURE_BONUS_FUEL_CHANCE,
    ROYAL_COMPOSURE_BONUS_DROP_PREFAB = ROYAL_COMPOSURE_BONUS_DROP_PREFAB,
    ROYAL_COMPOSURE_FUEL_DROP_EXTRA_TARGETS = ROYAL_COMPOSURE_FUEL_DROP_EXTRA_TARGETS,
}
