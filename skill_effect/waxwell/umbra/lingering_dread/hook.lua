local common = require("skill_effect/waxwell/umbra/_shared/common")
local persist_utils = require("skill_effect/waxwell/_shared/persist_utils")

local IsShadowSneakCursed = common.IsShadowSneakCursed
local GetShadowSneakCurseDamageTakenMult = common.GetShadowSneakCurseDamageTakenMult
local HasLingeringDread1Trap = common.HasLingeringDread1Trap
local HasLingeringDread2Trap = common.HasLingeringDread2Trap
local MarkLingeringDread1Trap = common.MarkLingeringDread1Trap
local MarkLingeringDread2Trap = common.MarkLingeringDread2Trap
local TriggerLingeringDreadShadowTrap = common.TriggerLingeringDreadShadowTrap

local SHADOW_TRAP_PERSIST_SPECS = {
    { key = "_waxwell_lingering_dread_1_trap", has = HasLingeringDread1Trap, mark = MarkLingeringDread1Trap },
    { key = "_waxwell_lingering_dread_2_trap", has = HasLingeringDread2Trap, mark = MarkLingeringDread2Trap },
}

local M = {}

function M.Register(env)
    local AddPrefabPostInit = env.AddPrefabPostInit
    local AddComponentPostInit = env.AddComponentPostInit

    AddComponentPostInit("combat", function(self)
        if self._waxwell_shadow_sneak_curse_patched then
            return
        end

        self._waxwell_shadow_sneak_curse_patched = true
        self._waxwell_shadow_sneak_curse_damagetakenfn = function(inst, attacker, weapon)
            return IsShadowSneakCursed(inst) and GetShadowSneakCurseDamageTakenMult(inst) or 1
        end
        self:AddConditionExternalDamageTakenMultiplier(self._waxwell_shadow_sneak_curse_damagetakenfn)
    end)

    AddPrefabPostInit("shadow_trap", function(inst)
        if not TheWorld.ismastersim or inst._waxwell_lingering_dread_patched then
            return
        end

        inst._waxwell_lingering_dread_patched = true
        inst.TriggerTrap = TriggerLingeringDreadShadowTrap

        local old_OnSave = inst.OnSave
        inst.OnSave = function(shadow_trap, data, ...)
            if old_OnSave ~= nil then
                old_OnSave(shadow_trap, data, ...)
            end

            persist_utils.SaveMarkedFlags(data, shadow_trap, SHADOW_TRAP_PERSIST_SPECS)
        end

        local old_OnLoad = inst.OnLoad
        inst.OnLoad = function(shadow_trap, data, ...)
            if old_OnLoad ~= nil then
                old_OnLoad(shadow_trap, data, ...)
            end

            persist_utils.RestoreMarkedFlags(data, shadow_trap, SHADOW_TRAP_PERSIST_SPECS)
        end
    end)
end

return M
