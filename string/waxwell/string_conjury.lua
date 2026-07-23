local V = require("skill_effect/waxwell/sovereign/shadow_conjury/variables")

STRINGS.NAMES = STRINGS.NAMES or {}

local M = {}

function M.Register()
    for base, displayname in pairs(V.SHADOW_DISPLAY_NAMES) do
        STRINGS.NAMES[string.upper("waxwell_shadow_" .. base)] = displayname
    end
end

return M
