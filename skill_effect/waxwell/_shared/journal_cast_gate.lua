local cast_costs = require("skill_effect/waxwell/_shared/codex_cast_costs")
local cost_gate = require("skill_effect/waxwell/_shared/codex_cost_gate")

local M = {}

local function WrapCastFn(fn)
    if fn == nil then
        return fn
    end

    return function(book, doer, pos)
        local blockreason = cast_costs.GetResourceBlockReason(book, doer)
        if blockreason ~= nil then
            local fail, reason = cost_gate.MapResourceBlockToFail(blockreason)
            if fail ~= nil then
                return fail, reason
            end
        end

        return fn(book, doer, pos)
    end
end

local function PatchCastFnSetter(inst, component, patch_key)
    if component == nil or component[patch_key] then
        return
    end

    component[patch_key] = true

    local old_SetSpellFn = component.SetSpellFn
    function component:SetSpellFn(fn)
        return old_SetSpellFn(self, WrapCastFn(fn))
    end
end

local function RegisterJournalHooks(env)
    cast_costs.EnsureRegistered()

    env.AddPrefabPostInit("waxwelljournal", function(inst)
        PatchCastFnSetter(inst, inst.components ~= nil and inst.components.aoespell or nil, "_codex_cast_gate_aoespell_patched")
        PatchCastFnSetter(inst, inst.components ~= nil and inst.components.spellbook or nil, "_codex_cast_gate_spellbook_patched")
    end)
end

function M.Register(env)
    RegisterJournalHooks(env)
end

function M.CanAffordCurrentCodexCast(book, doer)
    cast_costs.EnsureRegistered()
    return cast_costs.CanAffordCurrentCodexCast(book, doer)
end

function M.GetCurrentCodexCastBlockReason(book, doer)
    cast_costs.EnsureRegistered()
    return cast_costs.GetResourceBlockReason(book, doer)
end

function M.PlayClientCastBlockedFeedback(pc, book, doer)
    doer = doer or (pc ~= nil and pc.inst or nil)
    book = book or (pc ~= nil and pc.reticule ~= nil and pc.reticule.inst or nil)
    local blockreason = book ~= nil and doer ~= nil and cast_costs.GetResourceBlockReason(book, doer) or nil
    cost_gate.PlayClientCastBlockedFeedback(pc, blockreason, doer)
end

return M
