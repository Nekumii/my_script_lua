local V = require("skill_effect/waxwell/emperor/_shared/variables")
local common = require("skill_effect/waxwell/emperor/_shared/common")
local codex_umbra_spell_index = require("skill_effect/waxwell/_shared/codex_spell_index")
local domain_expansion = require("skill_effect/waxwell/emperor/domain_expansion/common")

local shadow_stalker_hook = require("skill_effect/waxwell/emperor/shadow_stalker/hook")
local domain_expansion_hook = require("skill_effect/waxwell/emperor/domain_expansion/hook")
local shadow_reliquary_codex = require("skill_effect/waxwell/emperor/shadow_reliquary/codex_recharge")

local SHADOW_STALKER_SPELL = common.SHADOW_STALKER_SPELL
local BuildEmperorSpellList = common.BuildEmperorSpellList
local GetShadowStalkerSpellState = common.GetShadowStalkerSpellState
local GetImperialRegaliaSpellState = common.GetImperialRegaliaSpellState
local GetImperialRegaliaDrainPerSecond = common.GetImperialRegaliaDrainPerSecond

local M = {}

local function RegisterJournalHooks(env)
    local AddPrefabPostInit = env.AddPrefabPostInit

    codex_umbra_spell_index.EnsureSpellLabel(SHADOW_STALKER_SPELL, "Shadow Stalker")
    codex_umbra_spell_index.EnsureSpellLabel(V.DOMAIN_EXPANSION_SPELL, "Domain Expansion")
    codex_umbra_spell_index.EnsureSpellLabel(V.FISSURE_ERUPTION_SPELL, "Fissure Eruption")
    codex_umbra_spell_index.EnsureSpellLabel(V.SHADOW_RELIQUARY_SPELL, "Shadow Reliquary")
    TUNING.SHADOWWAXWELL_SANITY_PENALTY = TUNING.SHADOWWAXWELL_SANITY_PENALTY or {}
    TUNING.SHADOWWAXWELL_SANITY_PENALTY.SHADOW_STALKER = .75

    AddPrefabPostInit("waxwelljournal", function(inst)
        local spellbook = inst.components.spellbook
        if spellbook == nil then
            return
        end

        codex_umbra_spell_index.RegisterJournalSpellBuilder(inst, spellbook, "emperor", BuildEmperorSpellList)
        codex_umbra_spell_index.RegisterJournalRefreshStateProvider(inst, spellbook, "emperor", function(owner)
            local stalkerstate = GetShadowStalkerSpellState(owner)
            local regaliastate = GetImperialRegaliaSpellState(owner)
            local regaliadrain = GetImperialRegaliaDrainPerSecond ~= nil and GetImperialRegaliaDrainPerSecond(owner) or 0
            local domainstate = domain_expansion ~= nil and domain_expansion.GetDomainExpansionSpellState ~= nil and domain_expansion.GetDomainExpansionSpellState(owner) or nil
            local fissurestate = common.GetFissureEruptionSpellState ~= nil and common.GetFissureEruptionSpellState(owner) or nil
            local reliquarystate = common.GetShadowReliquarySpellState ~= nil and common.GetShadowReliquarySpellState(owner) or nil
            return table.concat({
                tostring(stalkerstate or "nil"),
                tostring(regaliastate or "nil"),
                tostring(regaliadrain or 0),
                tostring(domainstate or "nil"),
                tostring(fissurestate or "nil"),
                tostring(reliquarystate or "nil"),
            }, "|")
        end)

        -- Listen for direct spawn notification from stalker stategraph
        inst:ListenForEvent("waxwell_shadow_stalker_spawned", function(inst_journal, data)
            if inst_journal.components ~= nil and inst_journal.components.spellbook ~= nil then
                local owner = data.owner
                if owner == nil then
                    owner = ThePlayer
                end
                codex_umbra_spell_index.RefreshSpellbook(inst_journal.components.spellbook, owner)
            end
        end)
    end)
end

local function RegisterWaxwellPetLeashHooks(env)
    env.AddPrefabPostInit("waxwell", function(inst)
        if not TheWorld.ismastersim or inst.components == nil or inst.components.petleash == nil then
            return
        end

        inst.components.petleash:SetMaxPetsForPrefab("shadow_stalker", 1)
    end)
end

local function RegisterShadowSunkenChestHover(env)
    if env == nil or env.AddComponentAction == nil then
        return
    end

    -- Vanilla inspectable omits LOOKAT while moving (Alt force-inspect still works).
    -- Always offer Examine on LMB for SSC so hover is: Examine Name + RMB Carry.
    env.AddComponentAction("SCENE", "inspectable", function(inst, doer, actions, right)
        if right
            or inst == nil
            or doer == nil
            or not inst:HasTag("waxwell_shadow_sunken_chest") then
            return
        end
        if doer.CanExamine ~= nil and not doer:CanExamine() then
            return
        end
        table.insert(actions, ACTIONS.LOOKAT)
    end)
end

function M.Register(env)
    shadow_stalker_hook.Register(env)
    domain_expansion_hook.Register(env)
    RegisterJournalHooks(env)
    shadow_reliquary_codex.RegisterJournalHooks(env)
    RegisterWaxwellPetLeashHooks(env)
    RegisterShadowSunkenChestHover(env)
end

return M
