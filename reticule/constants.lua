local M = {}

-- 1 = idle_small, 2 = idle_1d2_12
M.ANIM_SMALL = 1
M.ANIM_LARGE = 2

M.ANIM = {
	[M.ANIM_SMALL] = "idle_small",
	[M.ANIM_LARGE] = "idle_1d2_12",
}

-- Calibrated work radius per AnimState scale unit.
M.RANGE_PER_SCALE = {
	[M.ANIM_SMALL] = 1.25,
	[M.ANIM_LARGE] = 8,
}

M.PREFAB = {
	[M.ANIM_SMALL] = {
		reticule = "reticule_skilltree_small",
		ping = "reticule_skilltree_small_ping",
	},
	[M.ANIM_LARGE] = {
		reticule = "reticule_skilltree_large",
		ping = "reticule_skilltree_large_ping",
	},
}

M.PING_SCALE_UP = {
	[M.ANIM_SMALL] = 1.08333,
	[M.ANIM_LARGE] = 1.08333,
}

M.PING_DURATION = .5
M.PING_PAD_DURATION = .1
M.PING_FLASH_TIME = .3

M.DEBUG_SCALE_MIN = .1
M.DEBUG_SCALE_MAX = 10
M.DEBUG_TAG = "skilltree_debug_reticule"

M.DEBUG_ANIM_KEY = {
	s = M.ANIM_SMALL,
	l = M.ANIM_LARGE,
}

return M
