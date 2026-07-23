local V = require("skill_effect/waxwell/emperor/_shared/variables")
local umbra_rift_V = require("skill_effect/waxwell/umbra/umbral_rift/variables")
local eclipse_fall_V = require("skill_effect/waxwell/umbra/eclipse_fall/variables")
local domain_expansion = require("skill_effect/waxwell/emperor/domain_expansion/common")
local fissure_eruption = require("skill_effect/waxwell/emperor/fissure_eruption/common")
local shadow_reliquary = require("skill_effect/waxwell/emperor/shadow_reliquary/common")
local spell_shared = require("skill_effect/waxwell/emperor/_shared/spell_shared")
local codex_spell_sort = require("skill_effect/waxwell/_shared/codex_spell_sort")
local regalia = require("skill_effect/waxwell/emperor/domain_expansion/regalia_outfit")(spell_shared)
local shadow_stalker = require("skill_effect/waxwell/emperor/shadow_stalker/common")(spell_shared)

local DOMAIN_EXPANSION_LABEL = STRINGS.SPELLS[V.DOMAIN_EXPANSION_SPELL] or "Domain Expansion"
local SHADOW_STALKER_LABEL = STRINGS.SPELLS[V.SHADOW_STALKER_SPELL] or "Shadow Stalker"
local FISSURE_ERUPTION_LABEL = STRINGS.SPELLS[V.FISSURE_ERUPTION_SPELL] or "Fissure Eruption"
local SHADOW_RELIQUARY_LABEL = STRINGS.SPELLS[V.SHADOW_RELIQUARY_SPELL] or "Shadow Reliquary"

local UMBRAL_RIFT_LABEL = STRINGS.SPELLS[umbra_rift_V.UMBRAL_RIFT_SPELL] or "Umbral Rift"
local ECLIPSE_FALL_LABEL = STRINGS.SPELLS[eclipse_fall_V.ECLIPSE_FALL_SPELL] or "Eclipse Fall"

local GetSpellItemKey = codex_spell_sort.GetSpellItemKey
local SortSpellList = codex_spell_sort.SortSpellList

local SUMMON_SPELL_KEYS =
{
    [STRINGS.SPELLS.SHADOW_WORKER] = true,
    [STRINGS.SPELLS.SHADOW_PROTECTOR] = true,
    [STRINGS.SPELLS.SHADOW_LANTERNBEARER or "Shadow Lanternbearer"] = true,
    [STRINGS.SPELLS.SHADOW_MARKSMAN or "Shadow Marksman"] = true,
    [V.SHADOW_STALKER_SPELL] = true,
    [SHADOW_STALKER_LABEL] = true,
    [V.DOMAIN_EXPANSION_SPELL] = true,
    [DOMAIN_EXPANSION_LABEL] = true,
}

local function IsSummonSpellItem(item)
    return SUMMON_SPELL_KEYS[GetSpellItemKey(item)] == true
end

local function GetBlockedSpellOverlay(item, owner)
    local key = GetSpellItemKey(item)
    local domainstate = domain_expansion ~= nil
        and domain_expansion.GetDomainExpansionSpellState ~= nil
        and domain_expansion.GetDomainExpansionSpellState(owner)
        or nil

    if domainstate ~= nil then
        if key == V.DOMAIN_EXPANSION_SPELL or key == DOMAIN_EXPANSION_LABEL then
            return nil, nil
        end
        -- Umbral Rift stays usable while DE is active (warp out / trap play).
        if key == umbra_rift_V.UMBRAL_RIFT_SPELL or key == UMBRAL_RIFT_LABEL then
            return nil, nil
        end
        -- Fissure Eruption: if already open before DE, allow toggle-off; block open/reopen.
        if key == V.FISSURE_ERUPTION_SPELL or key == FISSURE_ERUPTION_LABEL then
            local fissurestate = fissure_eruption ~= nil
                and fissure_eruption.GetFissureEruptionSpellState ~= nil
                and fissure_eruption.GetFissureEruptionSpellState(owner)
                or nil
            if fissurestate == "active" then
                return nil, nil
            end
        end
        return V.DOMAIN_EXPANSION_ACTIVE_OVERLAY_PERCENT, { .52, .16, .16, .50 }
    end

    return nil, nil
end

local function BuildEmperorSpellList(baseitems, user)
    local items = {}
    if baseitems ~= nil then
        for _, item in ipairs(baseitems) do
            table.insert(items, item)
        end
    end

    local hasstalker = false
    local hasdomain = false
    local hasfissure = false
    local hasreliquary = false

    for _, item in ipairs(items) do
        local key = GetSpellItemKey(item)
        if key == V.SHADOW_STALKER_SPELL or key == SHADOW_STALKER_LABEL then
            hasstalker = true
        elseif key == V.DOMAIN_EXPANSION_SPELL or key == DOMAIN_EXPANSION_LABEL then
            hasdomain = true
        elseif key == V.FISSURE_ERUPTION_SPELL or key == FISSURE_ERUPTION_LABEL then
            hasfissure = true
        elseif key == V.SHADOW_RELIQUARY_SPELL or key == SHADOW_RELIQUARY_LABEL then
            hasreliquary = true
        end
    end

    if shadow_stalker.IsShadowStalkerSkillActive(user) and not hasstalker then
        table.insert(items, shadow_stalker.GetShadowStalkerSpellData(user))
    end

    if domain_expansion ~= nil and domain_expansion.IsDomainExpansionSkillActive ~= nil and domain_expansion.IsDomainExpansionSkillActive(user) and not hasdomain then
        table.insert(items, domain_expansion.GetDomainExpansionSpellData(user))
    end

    if fissure_eruption ~= nil
        and fissure_eruption.IsFissureEruptionSkillActive ~= nil
        and fissure_eruption.IsFissureEruptionSkillActive(user)
        and not hasfissure then
        table.insert(items, fissure_eruption.GetFissureEruptionSpellData(user))
    end

    if shadow_reliquary ~= nil
        and shadow_reliquary.IsShadowReliquarySkillActive ~= nil
        and shadow_reliquary.IsShadowReliquarySkillActive(user)
        and not hasreliquary then
        table.insert(items, shadow_reliquary.GetShadowReliquarySpellData(user))
    end

    for index, item in ipairs(items) do
        if item ~= nil then
            items[index] = item
        end
    end

    return SortSpellList(items)
end

local M = {
    SHADOW_STALKER_SPELL = V.SHADOW_STALKER_SPELL,
    SHADOW_STALKER_COOLDOWN_ID = V.SHADOW_STALKER_COOLDOWN_ID,
    SHADOW_STALKER_COOLDOWN_TIME = V.SHADOW_STALKER_COOLDOWN_TIME,
    SHADOW_STALKER_ACTIVE_TAG = V.SHADOW_STALKER_ACTIVE_TAG,
    BuildEmperorSpellList = BuildEmperorSpellList,
    GetBlockedSpellOverlay = GetBlockedSpellOverlay,
    IsSummonSpellItem = IsSummonSpellItem,
    IsShadowStalkerSkillActive = shadow_stalker.IsShadowStalkerSkillActive,
    IsImperialRegaliaBuffActive = regalia.IsImperialRegaliaBuffActive,
    GetImperialRegaliaSpellState = regalia.GetImperialRegaliaSpellState,
    GetImperialRegaliaDrainPerSecond = regalia.GetImperialRegaliaDrainPerSecond,
    RequestImperialRegaliaDeactivate = regalia.RequestImperialRegaliaDeactivate,
    ForceImperialRegaliaDeactivate = regalia.ForceImperialRegaliaDeactivate,
    FinalizeImperialRegaliaActivate = regalia.FinalizeImperialRegaliaActivate,
    SuspendImperialRegaliaOutfit = regalia.SuspendImperialRegaliaOutfit,
    ResumeImperialRegaliaOutfit = regalia.ResumeImperialRegaliaOutfit,
    FindActiveShadowStalker = shadow_stalker.FindActiveShadowStalker,
    GetShadowStalkerSpellState = shadow_stalker.GetShadowStalkerSpellState,
    RequestShadowStalkerDeactivate = shadow_stalker.RequestShadowStalkerDeactivate,
    IsFissureEruptionSkillActive = fissure_eruption.IsFissureEruptionSkillActive,
    GetFissureEruptionSpellState = fissure_eruption.GetFissureEruptionSpellState,
    IsShadowReliquarySkillActive = shadow_reliquary.IsShadowReliquarySkillActive,
    GetShadowReliquarySpellState = shadow_reliquary.GetShadowReliquarySpellState,
    RestartSpellCooldown = spell_shared.RestartSpellCooldown,
    PushEmperorSpellRefresh = spell_shared.PushEmperorSpellRefresh,
}

return M
