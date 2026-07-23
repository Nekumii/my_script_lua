local royal_composure = require("skill_effect/waxwell/sovereign/royal_composure/common")
local shadow_gluttony = require("skill_effect/waxwell/sovereign/shadow_gluttony/common")
local nightmare_dominion = require("skill_effect/waxwell/sovereign/nightmare_dominion/common")
local inner_incarnate = require("skill_effect/waxwell/sovereign/inner_incarnate/common")
local dread_tribute = require("skill_effect/waxwell/sovereign/dread_tribute/common")
local sanity_recoup = require("skill_effect/waxwell/sovereign/sanity_recoup/common")
local mind_over_matter = require("skill_effect/waxwell/sovereign/mind_over_matter/common")
local chaos_inoculation = require("skill_effect/waxwell/sovereign/chaos_inoculation/common")

local M = {}
for _, src in ipairs({
    royal_composure,
    shadow_gluttony,
    nightmare_dominion,
    inner_incarnate,
    dread_tribute,
    sanity_recoup,
    mind_over_matter,
    chaos_inoculation,
}) do
    for k, v in pairs(src) do
        M[k] = v
    end
end

return M
