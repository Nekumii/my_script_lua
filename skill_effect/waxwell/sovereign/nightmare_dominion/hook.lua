local common = require("skill_effect/waxwell/sovereign/nightmare_dominion/common")

local GetNightmareDominionDarknessDamageMultiplier = common.GetNightmareDominionDarknessDamageMultiplier

local M = {}

function M.Register(env)
    env.AddComponentPostInit("grue", function(self)
        if self._waxwell_nightmare_dominion_patched then
            return
        end

        self._waxwell_nightmare_dominion_patched = true

        local old_Attack = self.Attack
        function self:Attack(...)
            local args = { ... }
            local mult = GetNightmareDominionDarknessDamageMultiplier(self.inst)
            if mult == 1 or self.inst == nil or self.inst.components == nil or self.inst.components.combat == nil then
                return old_Attack(self, unpack(args))
            end

            local combat = self.inst.components.combat
            local old_GetAttacked = combat.GetAttacked
            combat.GetAttacked = function(combatself, attacker, damage, weapon, stimuli, spdamage, ...)
                if attacker == nil and weapon == nil and stimuli == "darkness" and damage ~= nil then
                    damage = damage * mult
                end
                return old_GetAttacked(combatself, attacker, damage, weapon, stimuli, spdamage, ...)
            end

            local ok, result = xpcall(function()
                return old_Attack(self, unpack(args))
            end, debug.traceback)

            combat.GetAttacked = old_GetAttacked

            if not ok then
                error(result)
            end

            return result
        end
    end)
end

return M
