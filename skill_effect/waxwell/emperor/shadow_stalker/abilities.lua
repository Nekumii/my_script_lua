local ReticuleUtils = require("reticule/utils")
local V = require("skill_effect/waxwell/emperor/shadow_stalker/variables")

local WORK_RADIUS = ReticuleUtils.GetWorkRadius(V.SHADOW_STALKER_RETICULE_SCALE, ReticuleUtils.ANIM_LARGE) or 14

return {
    WORK_RADIUS = WORK_RADIUS,

    MINDCONTROL_CD = 30,
    CHANNELERS_CD = 30,
    SNARE_CD = 20,
    SPIKES_CD = 20,
    FEAST_CD = 60,

    SKILL_DELAY = 5,
    ABILITY_MISS_RETRY = 3,

    SNARE_MAX_TARGETS = 4,
    SNARE_DURATION = 8,

    FEAST_SC_LOW_HEALTH_PERCENT = 0.6,
    FEAST_SC_HEAL_PERCENT = 0.40,
    FEAST_SUMMON_HEAL_PERCENT = 0.20,
    FEAST_EAT_RANGE = 2.4,
    FEAST_RETRY_CD = 2,
    FEAST_SPEEDMULT = 1.5,

    MC_REPOSITION_SPEEDMULT = 1.2,
    MC_REPOSITION_ARRIVE_DIST = 1.5,

    CHANNELERS_DURATION = 10,
    CHANNELERS_HITS = 20,
    CHANNELERS_ABSORB = 0.7,
    CHANNELERS_REFLECT = 0.3,

    NORMAL_DAMAGE = 80,
    PLANAR_DAMAGE = 20,
    VS_LUNAR_BONUS = 1.1,
    PLANAR_DEFENSE = 10,
    VS_SHADOW_RESIST = 0.9,
}
