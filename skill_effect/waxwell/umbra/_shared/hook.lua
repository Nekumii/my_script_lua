local common = require("skill_effect/waxwell/umbra/_shared/common")
local codex_umbra_spell_index = require("skill_effect/waxwell/_shared/codex_spell_index")
local base_spell_cooldown = require("skill_effect/waxwell/umbra/_shared/base_spell_cooldown")

local umbral_rift_hook = require("skill_effect/waxwell/umbra/umbral_rift/hook")
local lingering_dread_hook = require("skill_effect/waxwell/umbra/lingering_dread/hook")
local abyssal_binding_hook = require("skill_effect/waxwell/umbra/abyssal_binding/hook")

local IsMeasuredInvocationActive = common.IsMeasuredInvocationActive
local IsShadowPillarsSpell = common.IsShadowPillarsSpell
local IsShadowTrapSpell = common.IsShadowTrapSpell
local BuildUmbraSpellList = common.BuildUmbraSpellList
local UMBRAL_RIFT_SPELL = common.UMBRAL_RIFT_SPELL
local ECLIPSE_FALL_SPELL = common.ECLIPSE_FALL_SPELL
local WithAdjustedLingeringDreadShadowTrapSpawn = common.WithAdjustedLingeringDreadShadowTrapSpawn
local WithMeasuredInvocationCodexDurabilityChance = common.WithMeasuredInvocationCodexDurabilityChance
local WithAdjustedUmbraAoeCastCosts = common.WithAdjustedUmbraAoeCastCosts

local FISSURE_ERUPTION_SPELL = require("skill_effect/waxwell/emperor/fissure_eruption/variables").FISSURE_ERUPTION_SPELL

local M = {}

local function IsMeasuredInvocationSpell(book)
    local spellbook = book ~= nil and book.components ~= nil and book.components.spellbook or nil
    local spellname = spellbook ~= nil and spellbook:GetSpellName() or nil
    return spellname == STRINGS.SPELLS.SHADOW_TRAP
        or spellname == STRINGS.SPELLS.SHADOW_PILLARS
        or spellname == STRINGS.SPELLS[UMBRAL_RIFT_SPELL]
        or spellname == (STRINGS.SPELLS[ECLIPSE_FALL_SPELL] or "Eclipse Fall")
        or spellname == (STRINGS.SPELLS[FISSURE_ERUPTION_SPELL] or "Fissure Eruption")
end

local function RegisterJournalHooks(env)
    local AddPrefabPostInit = env.AddPrefabPostInit

    codex_umbra_spell_index.EnsureSpellLabel(UMBRAL_RIFT_SPELL, "Umbral Rift")
    codex_umbra_spell_index.EnsureSpellLabel(ECLIPSE_FALL_SPELL, "Eclipse Fall")

    AddPrefabPostInit("waxwelljournal", function(inst)
        local spellbook = inst.components.spellbook
        codex_umbra_spell_index.RegisterJournalSpellBuilder(inst, spellbook, "umbra", BuildUmbraSpellList)

        local aoespell = inst.components.aoespell
        if aoespell ~= nil and not aoespell._dark_scholar_patched then
            aoespell._dark_scholar_patched = true

            local old_SetSpellFn = aoespell.SetSpellFn
            function aoespell:SetSpellFn(fn)
                local originalfn = fn

                if originalfn ~= nil then
                    fn = function(book, doer, pos)
                        local isshadowtrap = IsShadowTrapSpell(book)
                        local isshadowpillars = IsShadowPillarsSpell(book)

                        local cd_reason = base_spell_cooldown.GetCastBlockReason(isshadowtrap, isshadowpillars, doer)
                        if cd_reason ~= nil then
                            return false, cd_reason
                        end

                        local castfn = function()
                            if isshadowtrap or isshadowpillars then
                                return WithAdjustedUmbraAoeCastCosts(book, doer, function()
                                    return originalfn(book, doer, pos)
                                end)
                            end

                            return originalfn(book, doer, pos)
                        end

                        if IsMeasuredInvocationSpell(book) and IsMeasuredInvocationActive(doer) then
                            local old_castfn = castfn
                            castfn = function()
                                return WithMeasuredInvocationCodexDurabilityChance(book, old_castfn)
                            end
                        end

                        local function RunAndTrackCooldown(run)
                            local ok, reason = run()
                            if ok then
                                base_spell_cooldown.OnCastSuccess(isshadowtrap, isshadowpillars, doer)
                            end
                            return ok, reason
                        end

                        if isshadowtrap then
                            return RunAndTrackCooldown(function()
                                return WithAdjustedLingeringDreadShadowTrapSpawn(doer, castfn)
                            end)
                        end

                        return RunAndTrackCooldown(castfn)
                    end
                end

                return old_SetSpellFn(self, fn)
            end
        end
    end)
end

function M.Register(env)
    umbral_rift_hook.Register(env)
    lingering_dread_hook.Register(env)
    abyssal_binding_hook.Register(env)
    RegisterJournalHooks(env)
end

return M
