local mod_config = require("mod_config")
local spell_utils = require("skill_effect/waxwell/_shared/codex_spell_utils")
local V = require("skill_effect/waxwell/umbra/_shared/variables")

local SHADOW_TRAP_LABEL = STRINGS.SPELLS.SHADOW_TRAP
local SHADOW_PILLARS_LABEL = STRINGS.SPELLS.SHADOW_PILLARS

local M = {}

function M.IsFixEnabled()
    return mod_config.IsWaxwellUmbraBaseSpellCooldownFixEnabled()
end

function M.GetCooldownTime()
    return V.UMBRA_BASE_SPELL_COOLDOWN_TIME
end

function M.IsShadowTrapOnCooldown(doer)
    return spell_utils.IsSpellOnCooldown(doer, V.SHADOW_TRAP_COOLDOWN_ID)
end

function M.IsShadowPillarsOnCooldown(doer)
    return spell_utils.IsSpellOnCooldown(doer, V.SHADOW_PILLARS_COOLDOWN_ID)
end

function M.GetShadowTrapCooldownPercent(doer)
    return spell_utils.GetSpellCooldownPercent(doer, V.SHADOW_TRAP_COOLDOWN_ID)
end

function M.GetShadowPillarsCooldownPercent(doer)
    return spell_utils.GetSpellCooldownPercent(doer, V.SHADOW_PILLARS_COOLDOWN_ID)
end

function M.StartShadowTrapCooldown(doer)
    spell_utils.RestartSpellCooldown(doer, V.SHADOW_TRAP_COOLDOWN_ID, V.UMBRA_BASE_SPELL_COOLDOWN_TIME)
end

function M.StartShadowPillarsCooldown(doer)
    spell_utils.RestartSpellCooldown(doer, V.SHADOW_PILLARS_COOLDOWN_ID, V.UMBRA_BASE_SPELL_COOLDOWN_TIME)
end

function M.GetCastBlockReason(is_shadow_trap, is_shadow_pillars, doer)
    if not M.IsFixEnabled() or doer == nil then
        return nil
    end

    if is_shadow_trap and M.IsShadowTrapOnCooldown(doer) then
        return "SPELL_ON_COOLDOWN"
    end
    if is_shadow_pillars and M.IsShadowPillarsOnCooldown(doer) then
        return "SPELL_ON_COOLDOWN"
    end

    return nil
end

function M.OnCastSuccess(is_shadow_trap, is_shadow_pillars, doer)
    if not M.IsFixEnabled() or doer == nil then
        return
    end

    if is_shadow_trap then
        M.StartShadowTrapCooldown(doer)
    elseif is_shadow_pillars then
        M.StartShadowPillarsCooldown(doer)
    end
end

local COOLDOWN_OVERLAY_COLOR = { .12, .28, .42, .50 }
local COOLDOWN_OVERLAY_SCALE = 1.42

function M.DecorateSpellItems(items)
    if items == nil or not M.IsFixEnabled() then
        return items
    end

    for _, item in ipairs(items) do
        if item ~= nil and item.label == SHADOW_TRAP_LABEL then
            item.checkcooldown = function(user)
                return M.GetShadowTrapCooldownPercent(user)
            end
            item.cooldowncolor = COOLDOWN_OVERLAY_COLOR
            item.cooldownscale = COOLDOWN_OVERLAY_SCALE
        elseif item ~= nil and item.label == SHADOW_PILLARS_LABEL then
            item.checkcooldown = function(user)
                return M.GetShadowPillarsCooldownPercent(user)
            end
            item.cooldowncolor = COOLDOWN_OVERLAY_COLOR
            item.cooldownscale = COOLDOWN_OVERLAY_SCALE
        end
    end

    return items
end

return M
