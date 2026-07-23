local cast = require("skill_effect/waxwell/puppeteer/_shared/cast_common")
local fragmented_mind = require("skill_effect/waxwell/puppeteer/fragmented_mind/common")
local expanded_dominion = require("skill_effect/waxwell/puppeteer/expanded_dominion/common")
local tireless_servant = require("skill_effect/waxwell/puppeteer/tireless_servant/common")
local lethal_apparition = require("skill_effect/waxwell/puppeteer/lethal_apparition/common")
local shadow_lanternbearer = require("skill_effect/waxwell/puppeteer/shadow_lanternbearer/common")
local shadow_marksman = require("skill_effect/waxwell/puppeteer/shadow_marksman/common")
local V = require("skill_effect/waxwell/puppeteer/_shared/variables")

local function BuildPuppeteerSpellList(baseitems, user)
    local items = {}
    local inserted_lanternbearer = false
    local inserted_marksman = false

    if baseitems ~= nil then
        for _, item in ipairs(baseitems) do
            table.insert(items, item)
            if not inserted_lanternbearer and shadow_lanternbearer.IsShadowLanternbearerSkillActive(user) and item.label == STRINGS.SPELLS.SHADOW_WORKER then
                table.insert(items, shadow_lanternbearer.GetShadowLanternbearerSpellData())
                inserted_lanternbearer = true
            end
            if not inserted_marksman and shadow_marksman.IsShadowMarksmanSkillActive(user) and item.label == STRINGS.SPELLS.SHADOW_PROTECTOR then
                table.insert(items, shadow_marksman.GetShadowMarksmanSpellData())
                inserted_marksman = true
            end
        end
    end

    if shadow_lanternbearer.IsShadowLanternbearerSkillActive(user) and not inserted_lanternbearer then
        table.insert(items, 1, shadow_lanternbearer.GetShadowLanternbearerSpellData())
    end

    if shadow_marksman.IsShadowMarksmanSkillActive(user) and not inserted_marksman then
        table.insert(items, shadow_marksman.GetShadowMarksmanSpellData())
    end

    return items
end

local M = {
    BuildPuppeteerSpellList = BuildPuppeteerSpellList,
    SHADOW_LANTERNBEARER_SPELL = V.SHADOW_LANTERNBEARER_SPELL,
    SHADOW_MARKSMAN_SPELL = V.SHADOW_MARKSMAN_SPELL,
}
for _, src in ipairs({
    cast,
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
