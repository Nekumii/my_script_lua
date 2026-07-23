local lantern_V = require("skill_effect/waxwell/puppeteer/shadow_lanternbearer/variables")
local marksman_V = require("skill_effect/waxwell/puppeteer/shadow_marksman/variables")
local rift_V = require("skill_effect/waxwell/umbra/umbral_rift/variables")
local eclipse_V = require("skill_effect/waxwell/umbra/eclipse_fall/variables")
local emperor_V = require("skill_effect/waxwell/emperor/_shared/variables")

local LANTERNBEARER_LABEL = STRINGS.SPELLS[lantern_V.SHADOW_LANTERNBEARER_SPELL] or "Shadow Lanternbearer"
local MARKSMAN_LABEL = STRINGS.SPELLS[marksman_V.SHADOW_MARKSMAN_SPELL] or "Shadow Marksman"
local UMBRAL_RIFT_LABEL = STRINGS.SPELLS[rift_V.UMBRAL_RIFT_SPELL] or "Umbral Rift"
local ECLIPSE_FALL_LABEL = STRINGS.SPELLS[eclipse_V.ECLIPSE_FALL_SPELL] or "Eclipse Fall"
local SHADOW_STALKER_LABEL = STRINGS.SPELLS[emperor_V.SHADOW_STALKER_SPELL] or "Shadow Stalker"
local DOMAIN_EXPANSION_LABEL = STRINGS.SPELLS[emperor_V.DOMAIN_EXPANSION_SPELL] or "Domain Expansion"
local FISSURE_ERUPTION_LABEL = STRINGS.SPELLS[emperor_V.FISSURE_ERUPTION_SPELL] or "Fissure Eruption"
local SHADOW_RELIQUARY_LABEL = STRINGS.SPELLS[emperor_V.SHADOW_RELIQUARY_SPELL] or "Shadow Reliquary"

-- Codex Umbra wheel order (left-to-right on spell wheel).
local SPELL_SORT_ORDER =
{
    [STRINGS.SPELLS.SHADOW_WORKER] = 1,
    [STRINGS.SPELLS.SHADOW_PROTECTOR] = 2,
    [lantern_V.SHADOW_LANTERNBEARER_SPELL] = 3,
    [LANTERNBEARER_LABEL] = 3,
    [marksman_V.SHADOW_MARKSMAN_SPELL] = 4,
    [MARKSMAN_LABEL] = 4,
    [STRINGS.SPELLS.SHADOW_TRAP] = 5,
    [STRINGS.SPELLS.SHADOW_PILLARS] = 6,
    [rift_V.UMBRAL_RIFT_SPELL] = 7,
    [UMBRAL_RIFT_LABEL] = 7,
    [eclipse_V.ECLIPSE_FALL_SPELL] = 8,
    [ECLIPSE_FALL_LABEL] = 8,
    [emperor_V.SHADOW_STALKER_SPELL] = 9,
    [SHADOW_STALKER_LABEL] = 9,
    [emperor_V.DOMAIN_EXPANSION_SPELL] = 10,
    [DOMAIN_EXPANSION_LABEL] = 10,
    [emperor_V.FISSURE_ERUPTION_SPELL] = 11,
    [FISSURE_ERUPTION_LABEL] = 11,
    [emperor_V.SHADOW_RELIQUARY_SPELL] = 12,
    [SHADOW_RELIQUARY_LABEL] = 12,
}

local function GetSpellItemKey(item)
    return item ~= nil and (item.spell_id or item.label) or nil
end

local function SortSpellList(items)
    if items == nil then
        return items
    end

    for index, item in ipairs(items) do
        item._waxwell_spell_sort_index = index
    end

    table.sort(items, function(a, b)
        local ordera = SPELL_SORT_ORDER[GetSpellItemKey(a)] or math.huge
        local orderb = SPELL_SORT_ORDER[GetSpellItemKey(b)] or math.huge
        if ordera == orderb then
            return (a ~= nil and a._waxwell_spell_sort_index or math.huge) < (b ~= nil and b._waxwell_spell_sort_index or math.huge)
        end
        return ordera < orderb
    end)

    for _, item in ipairs(items) do
        item._waxwell_spell_sort_index = nil
    end

    return items
end

return {
    GetSpellItemKey = GetSpellItemKey,
    SortSpellList = SortSpellList,
    SPELL_SORT_ORDER = SPELL_SORT_ORDER,
}
