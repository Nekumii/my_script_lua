local SANITY_RECOUP_RATIO = .30
local SANITY_RECOUP_DURATION = 4
local SANITY_RECOUP_TICK = 1

-- nil = no cap (single pool still merges hits into one drip).
-- Set a number later if pending restore should hard-cap.
local SANITY_RECOUP_MAX_PENDING = nil

return {
    SANITY_RECOUP_RATIO = SANITY_RECOUP_RATIO,
    SANITY_RECOUP_DURATION = SANITY_RECOUP_DURATION,
    SANITY_RECOUP_TICK = SANITY_RECOUP_TICK,
    SANITY_RECOUP_MAX_PENDING = SANITY_RECOUP_MAX_PENDING,
}
