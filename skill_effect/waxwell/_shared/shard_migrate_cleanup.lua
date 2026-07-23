-- =============================================================================
-- Shard migrate cleanup (Method 1 baseline)
-- =============================================================================
-- When a player leaves this shard via cave/portal migrate, end every active
-- codex spell using the same deactivate paths as manual cancel / death.
-- Arrival OnLoad strips cross-shard persist so spells are not restored.

local codex_spell_index = require("skill_effect/waxwell/_shared/codex_spell_index")

local M = {}

local _registered = false
local _expanded_dominion_hook

local function GetExpandedDominionHook()
    if _expanded_dominion_hook == nil then
        local ok, hook = pcall(require, "skill_effect/waxwell/puppeteer/expanded_dominion/hook")
        _expanded_dominion_hook = ok and hook or false
    end

    return _expanded_dominion_hook or nil
end

local function RefreshShadowServantSanity(player)
    if player == nil or not player:IsValid() then
        return
    end

    local hook = GetExpandedDominionHook()
    if hook ~= nil and hook.RefreshWaxwellShadowServantState ~= nil then
        hook.RefreshWaxwellShadowServantState(player)
    end
end

local function PushJournalRefresh(player)
    if player == nil or player.components == nil or player.components.inventory == nil then
        return
    end

    local book = player.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if book ~= nil
        and book:IsValid()
        and book.prefab == "waxwelljournal"
        and book.components ~= nil
        and book.components.spellbook ~= nil then
        codex_spell_index.RefreshSpellbook(book.components.spellbook, player)
    end
end

local function CancelAOETargeting(player)
    if player == nil or player.components == nil then
        return
    end

    local pc = player.components.playercontroller
    if pc ~= nil and pc:IsAOETargeting() then
        pc:CancelAOETargeting()
    end
end

local function ClearPendingDomainState(player)
    if player == nil then
        return
    end

    player._waxwell_domain_expansion_pending_state = nil
    player._waxwell_domain_expansion_pending_position = nil
    player._waxwell_domain_expansion_field = nil
    player._waxwell_domain_expansion_field_cache = nil
    player._waxwell_domain_expansion_state_cache = nil
end

function M.ClearArrivalShardState(player)
    if player == nil or not player:IsValid() then
        return
    end

    ClearPendingDomainState(player)
    PushJournalRefresh(player)
end

function M.EndAllActiveSpells(player, reason)
    if player == nil or not player:IsValid() or not TheWorld.ismastersim then
        return
    end

    reason = reason or "shard_migrate"

    CancelAOETargeting(player)

    local umbral_rift = require("skill_effect/waxwell/umbra/umbral_rift/common")
    if umbral_rift ~= nil and umbral_rift.CancelUmbralRiftSkill ~= nil then
        umbral_rift.CancelUmbralRiftSkill(player)
    end

    local domain_expansion = require("skill_effect/waxwell/emperor/domain_expansion/common")
    if domain_expansion ~= nil and domain_expansion.RequestDomainExpansionDeactivate ~= nil then
        domain_expansion.RequestDomainExpansionDeactivate(player)
    end

    local emperor_common = require("skill_effect/waxwell/emperor/_shared/common")
    if emperor_common ~= nil then
        if emperor_common.GetShadowStalkerSpellState ~= nil
            and emperor_common.GetShadowStalkerSpellState(player) ~= nil
            and emperor_common.RequestShadowStalkerDeactivate ~= nil then
            emperor_common.RequestShadowStalkerDeactivate(player)
        end
    end

    local fissure_eruption = require("skill_effect/waxwell/emperor/fissure_eruption/common")
    if fissure_eruption ~= nil
        and fissure_eruption.GetFissureEruptionSpellState ~= nil
        and fissure_eruption.GetFissureEruptionSpellState(player) ~= nil
        and fissure_eruption.RequestFissureEruptionDeactivate ~= nil then
        fissure_eruption.RequestFissureEruptionDeactivate(player)
    end

    local shadow_reliquary = require("skill_effect/waxwell/emperor/shadow_reliquary/common")
    if shadow_reliquary ~= nil
        and shadow_reliquary.GetShadowReliquarySpellState ~= nil
        and shadow_reliquary.GetShadowReliquarySpellState(player) ~= nil
        and shadow_reliquary.RequestShadowReliquaryDeactivate ~= nil then
        shadow_reliquary.RequestShadowReliquaryDeactivate(player)
    end

    ClearPendingDomainState(player)
    PushJournalRefresh(player)
    RefreshShadowServantSanity(player)

    player:PushEvent("waxwell_shard_migrate_spells_ended", { reason = reason })
end

local function OnPlayerDespawnAndMigrate(world, data)
    if data == nil or data.player == nil then
        return
    end

    M.EndAllActiveSpells(data.player, "shard_migrate")
end

local function RegisterWaxwellArrivalGuard(env)
    env.AddPrefabPostInit("waxwell", function(inst)
        if not TheWorld.ismastersim then
            return
        end

        local old_OnLoad = inst.OnLoad
        inst.OnLoad = function(player, data, ...)
            if data ~= nil and data.migration ~= nil then
                data._waxwell_domain_expansion_state = nil
                data._waxwell_imperial_regalia_state = nil
            end

            if old_OnLoad ~= nil then
                old_OnLoad(player, data, ...)
            end

            if data ~= nil and data.migration ~= nil then
                player:DoTaskInTime(0, function(owner)
                    if owner ~= nil and owner:IsValid() then
                        M.ClearArrivalShardState(owner)
                    end
                end)
            end
        end
    end)
end

local function RegisterWorldMigrateListener(env)
    env.AddPrefabPostInit("world", function(inst)
        if not TheWorld.ismastersim then
            return
        end

        inst:ListenForEvent("ms_playerdespawnandmigrate", OnPlayerDespawnAndMigrate)
    end)
end

function M.Register(env)
    if _registered then
        return
    end
    _registered = true

    RegisterWorldMigrateListener(env)
    RegisterWaxwellArrivalGuard(env)
end

return M
