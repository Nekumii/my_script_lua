local domain_expansion = require("skill_effect/waxwell/emperor/domain_expansion/common")
local outside_target_block = require("skill_effect/waxwell/emperor/domain_expansion/outside_target_block")
local persist_utils = require("skill_effect/waxwell/_shared/persist_utils")
local common = require("skill_effect/waxwell/emperor/_shared/common")

local ForceImperialRegaliaDeactivate = common.ForceImperialRegaliaDeactivate

local M = {}

local _combat_replica_domain_registered = false

local function BlocksCrossDomainTarget(attacker, target)
    return outside_target_block.HasActiveFields()
        and target ~= nil
        and outside_target_block.IsCrossDomainTarget(attacker, target)
end

local function RegisterCombatReplicaDomainBlock(env)
    if _combat_replica_domain_registered or env.AddClassPostConstruct == nil then
        return
    end

    _combat_replica_domain_registered = true

    env.AddClassPostConstruct("components/combat_replica", function(self)
        local old_IsValidTarget = self.IsValidTarget

        function self:IsValidTarget(target)
            if not old_IsValidTarget(self, target) then
                return false
            end
            if BlocksCrossDomainTarget(self.inst, target) then
                return false
            end
            return true
        end
    end)
end

function M.Register(env)
    RegisterCombatReplicaDomainBlock(env)

    env.AddComponentPostInit("combat", function(self)
        if self == nil or self._waxwell_domain_outside_target_patched then
            return
        end

        self._waxwell_domain_outside_target_patched = true

        local old_IsValidTarget = self.IsValidTarget
        function self:IsValidTarget(target)
            if not old_IsValidTarget(self, target) then
                return false
            end
            if BlocksCrossDomainTarget(self.inst, target) then
                return false
            end
            return true
        end

        local old_SetTarget = self.SetTarget
        function self:SetTarget(target)
            if BlocksCrossDomainTarget(self.inst, target) then
                return
            end
            return old_SetTarget(self, target)
        end

        local old_ValidateTarget = self.ValidateTarget
        function self:ValidateTarget()
            if self.target ~= nil and BlocksCrossDomainTarget(self.inst, self.target) then
                self:DropTarget()
                return false
            end
            return old_ValidateTarget(self)
        end
    end)

    env.AddComponentPostInit("inventory", function(self)
        if self == nil or self._waxwell_domain_expansion_drop_patched then
            return
        end

        self._waxwell_domain_expansion_drop_patched = true
        local old_DropEverything = self.DropEverything
        function self:DropEverything(...)
            if self.inst ~= nil and self.inst.prefab == "waxwell"
                and domain_expansion ~= nil
                and domain_expansion.GetDomainExpansionSpellState ~= nil
                and domain_expansion.GetDomainExpansionSpellState(self.inst) ~= nil
                and domain_expansion.RequestDomainExpansionDeactivate ~= nil then
                domain_expansion.RequestDomainExpansionDeactivate(self.inst)
            end
            return old_DropEverything(self, ...)
        end
    end)

    env.AddPrefabPostInit("waxwell", function(inst)
        if not TheWorld.ismastersim then
            return
        end

        inst:ListenForEvent("death", function(player)
            if domain_expansion ~= nil
                and domain_expansion.GetDomainExpansionSpellState ~= nil
                and domain_expansion.GetDomainExpansionSpellState(player) ~= nil
                and domain_expansion.RequestDomainExpansionDeactivate ~= nil then
                domain_expansion.RequestDomainExpansionDeactivate(player)
            end
        end)

        if inst.components == nil or inst.components.petleash == nil then
            return
        end

        local old_OnSave = inst.OnSave
        inst.OnSave = function(player, data, ...)
            if domain_expansion ~= nil
                and domain_expansion.GetDomainExpansionSpellState ~= nil
                and domain_expansion.GetDomainExpansionSpellState(player) == "active" then
                ForceImperialRegaliaDeactivate(player, false, false)
            end

            local refs = nil
            if old_OnSave ~= nil then
                refs = old_OnSave(player, data, ...)
            end

            persist_utils.SaveValue(data, "_waxwell_domain_expansion_state", domain_expansion ~= nil and domain_expansion.GetDomainExpansionPersistData ~= nil
                and domain_expansion.GetDomainExpansionPersistData(player)
                or nil)

            return refs
        end

        local old_OnLoad = inst.OnLoad
        inst.OnLoad = function(player, data, ...)
            if old_OnLoad ~= nil then
                old_OnLoad(player, data, ...)
            end

            player:DoTaskInTime(0, function(owner)
                if data ~= nil and data._waxwell_domain_expansion_state ~= nil and domain_expansion ~= nil and domain_expansion.RestoreDomainExpansionPersistData ~= nil then
                    domain_expansion.RestoreDomainExpansionPersistData(owner, data._waxwell_domain_expansion_state)
                elseif domain_expansion ~= nil and domain_expansion.GetDomainExpansionSpellState ~= nil then
                    domain_expansion.GetDomainExpansionSpellState(owner)
                end
            end)
        end
    end)
end

return M
