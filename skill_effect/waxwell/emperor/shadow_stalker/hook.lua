local M = {}

local _combat_replica_targeting_registered = false

function M.Register(env)
    if env == nil then
        return
    end

    if env.AddPrefabPostInit ~= nil then
        env.AddPrefabPostInit("shadow_stalker", function(inst)
            require("skill_effect/waxwell/emperor/shadow_stalker/feast_buff_ui").ScheduleAttach(inst)
        end)
    end

    if _combat_replica_targeting_registered or env.AddClassPostConstruct == nil then
        return
    end

    _combat_replica_targeting_registered = true

    local AddClassPostConstruct = env.AddClassPostConstruct
    AddClassPostConstruct("components/combat_replica", function(self)
        local _CanBeAttacked = self.CanBeAttacked

        function self:CanBeAttacked(attacker)
            if self.inst ~= nil and self.inst:HasTag("shadow_stalker") and attacker ~= nil and attacker.isplayer then
                local follower = self.inst.replica.follower
                local leader = follower ~= nil and follower:GetLeader() or nil
                return attacker == leader
            end

            if self.inst ~= nil and self.inst:HasTag("shadow_lanternbearer") and attacker ~= nil and attacker.isplayer then
                local follower = self.inst.replica.follower
                local leader = follower ~= nil and follower:GetLeader() or nil
                local targetuserid = self.inst._bound_target_userid_net ~= nil and self.inst._bound_target_userid_net:value() or nil
                return attacker == leader or (targetuserid ~= nil and targetuserid ~= "" and attacker.userid == targetuserid)
            end

            return _CanBeAttacked(self, attacker)
        end
    end)
end

return M
