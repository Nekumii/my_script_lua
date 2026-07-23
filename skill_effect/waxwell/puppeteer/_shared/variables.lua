local fragmented_mind = require("skill_effect/waxwell/puppeteer/fragmented_mind/variables")
local expanded_dominion = require("skill_effect/waxwell/puppeteer/expanded_dominion/variables")
local tireless_servant = require("skill_effect/waxwell/puppeteer/tireless_servant/variables")
local lethal_apparition = require("skill_effect/waxwell/puppeteer/lethal_apparition/variables")
local shadow_lanternbearer = require("skill_effect/waxwell/puppeteer/shadow_lanternbearer/variables")
local shadow_marksman = require("skill_effect/waxwell/puppeteer/shadow_marksman/variables")

local M = {}
for _, src in ipairs({
    fragmented_mind,
    expanded_dominion,
    tireless_servant,
    lethal_apparition,
    shadow_lanternbearer,
    shadow_marksman,
}) do
    for k, v in pairs(src) do
        M[k] = v
    end
end

return M
