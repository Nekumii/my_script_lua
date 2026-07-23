local shadow_stalker = require("skill_effect/waxwell/emperor/shadow_stalker/variables")
local domain_expansion = require("skill_effect/waxwell/emperor/domain_expansion/variables")
local fissure_eruption = require("skill_effect/waxwell/emperor/fissure_eruption/variables")
local shadow_reliquary = require("skill_effect/waxwell/emperor/shadow_reliquary/variables")

local M = {}
for _, src in ipairs({
    shadow_stalker,
    domain_expansion,
    fissure_eruption,
    shadow_reliquary,
}) do
    for k, v in pairs(src) do
        M[k] = v
    end
end

return M
