require "behaviours/chaseandattack"
require "behaviours/doaction"
require "behaviours/follow"
require "behaviours/faceentity"
require "behaviours/leash"
require "behaviours/standstill"
require "behaviours/wander"

local MIN_FOLLOW_DIST = 0
local TARGET_FOLLOW_DIST = 6
local MAX_FOLLOW_DIST = 14
local FOLLOW_TRIGGER_DIST = 10
local START_FACE_DIST = 4
local KEEP_FACE_DIST = 8
local KEEP_WORKING_DIST = 14
local POST_ACTION_IDLE_DELAY = 5
local LEADER_WANDER_MARGIN = 1
local LEADER_WANDER_MAX_DIST = 4
local LEADER_PATROL_WANDER_DIST = 4
local CENTER_PATROL_MIN_DIST = 5
local CENTER_PATROL_WANDER_DIST = 7
local CENTER_PATROL_MAX_DIST = 8
local PATROL_DELAY = 5
local PATROL_POINT_MIN_SEPARATION = 4.5

local SPIKE_TARGET_MUST_TAGS = { "_combat", "_health" }
local HasEnemyNearCenter
local SPIKE_TARGET_CANT_TAGS =
{
    "INLIMBO",
    "player",
    "playerghost",
    "companion",
    "shadow",
    "shadowminion",
    "stalkerminion",
    "shadowcreature",
    "fossil",
}

local FeastBuffEffects = require("skill_effect/waxwell/emperor/shadow_stalker/feast_buff_effects")
local Abilities = require("skill_effect/waxwell/emperor/shadow_stalker/abilities")

local ABILITY_PRIORITY =
{
    "fossilfeast",
    "mindcontrol",
    "shadowchannelers",
    "fossilsnare",
    "fossilspikes",
}

local ShadowStalkerBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
    self.abilityname = nil
    self.abilitydata = nil
end)

local function IsValidLeader(leader)
    return leader ~= nil
        and leader:IsValid()
        and not leader:HasTag("playerghost")
        and (leader.components.health == nil or not leader.components.health:IsDead())
end

local function GetLeader(inst)
    local leader = inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
    if not IsValidLeader(leader) then
        return nil
    end
    return leader
end

local function GetFaceLeaderFn(inst)
    local target = GetLeader(inst)
    return target ~= nil and target.entity:IsVisible() and inst:IsNear(target, START_FACE_DIST) and target or nil
end

local function KeepFaceLeaderFn(inst, target)
    return target.entity:IsVisible() and inst:IsNear(target, KEEP_FACE_DIST)
end

local function GetWorkCenter(inst)
    return inst.GetWorkCenter ~= nil and inst:GetWorkCenter() or nil
end

local function GetLeaderInWorkArea(inst)
    local leader = GetLeader(inst)
    return leader ~= nil and inst.IsInWorkArea ~= nil and inst:IsInWorkArea(leader) and leader or nil
end

local function GetDistanceSq(a, b)
    return a ~= nil and b ~= nil and a:GetDistanceSqToInst(b) or math.huge
end

local function WantsToFollowLeader(inst)
    local leader = GetLeaderInWorkArea(inst)
    return leader ~= nil and GetDistanceSq(inst, leader) > FOLLOW_TRIGGER_DIST * FOLLOW_TRIGGER_DIST
end

local function UpdateRecentActivity(inst)
    local now = GetTime()
    if inst.components.combat ~= nil and inst.components.combat:HasTarget() then
        inst._randomwander_lastcombat = now
    end

    if WantsToFollowLeader(inst) then
        inst._randomwander_lastfollow = now
    end
end

local function IsRandomWanderReady(inst)
    UpdateRecentActivity(inst)

    if inst.components.combat ~= nil and inst.components.combat:HasTarget() then
        return false
    end

    local now = GetTime()
    if (inst._randomwander_lastcombat or 0) + POST_ACTION_IDLE_DELAY > now then
        return false
    end

    if (inst._randomwander_lastfollow or 0) + POST_ACTION_IDLE_DELAY > now then
        return false
    end

    return true
end

local function GetLeaderWanderMaxDist(inst)
    local leader = GetLeaderInWorkArea(inst)
    local center = GetWorkCenter(inst)
    if leader == nil or center == nil then
        return inst._workradius or KEEP_WORKING_DIST
    end

    local lx, _, lz = leader.Transform:GetWorldPosition()
    local dx = lx - center.x
    local dz = lz - center.z
    local dist_from_center = math.sqrt(dx * dx + dz * dz)
    local radius = inst._workradius or KEEP_WORKING_DIST
    local available = math.max(1, radius - dist_from_center - LEADER_WANDER_MARGIN)
    return math.min(LEADER_WANDER_MAX_DIST, available)
end

local function ShouldLeaderPatrol(inst)
    local leader = GetLeaderInWorkArea(inst)
    return leader ~= nil
        and not WantsToFollowLeader(inst)
        and IsRandomWanderReady(inst)
        and not HasEnemyNearCenter(inst)
end

local function GetLeaderPatrolHome(inst)
    return GetWorkCenter(inst)
end

local function ShouldCenterPatrol(inst)
    return GetLeaderInWorkArea(inst) == nil
        and IsRandomWanderReady(inst)
        and GetWorkCenter(inst) ~= nil
        and not HasEnemyNearCenter(inst)
end

local function GetCenterPatrolMaxDist(inst)
    return math.min(
        CENTER_PATROL_MAX_DIST,
        math.max(CENTER_PATROL_MIN_DIST + 1, (inst._workradius or KEEP_WORKING_DIST) - 3)
    )
end

local SHADOW_STALKER_SKILL_DELAY_TIMER = "skill_delay_cd"
local SHADOW_STALKER_ABILITY_MISS_RETRY = 3

local function IsSkillDelayActive(inst)
    return inst.IsSkillDelayActive ~= nil and inst:IsSkillDelayActive()
        or inst.components.timer ~= nil and inst.components.timer:TimerExists(SHADOW_STALKER_SKILL_DELAY_TIMER)
end

local function ShouldSnare(self)
    if FeastBuffEffects.IsDuelistCrowdControlBlocked(self.inst) then
        return false
    end
    if not IsSkillDelayActive(self.inst)
        and not self.inst.components.timer:TimerExists("snare_cd") then
        local targets = self.inst:FindSnareTargets()
        if targets ~= nil then
            self.abilitydata = { targets = targets }
            return true
        end
        self.inst.components.timer:StartTimer("snare_cd", SHADOW_STALKER_ABILITY_MISS_RETRY)
    end
    return false
end

HasEnemyNearCenter = function(inst)
    local center = GetWorkCenter(inst)
    if center == nil then
        return false
    end

    local ents = TheSim:FindEntities(center.x, center.y, center.z, inst._workradius or KEEP_WORKING_DIST, SPIKE_TARGET_MUST_TAGS, SPIKE_TARGET_CANT_TAGS)
    for _, guy in ipairs(ents) do
        if inst:IsValidEnemy(guy) then
            return true
        end
    end

    return false
end

local function ShouldSpikes(self)
    if not IsSkillDelayActive(self.inst)
        and not self.inst.components.timer:TimerExists("spikes_cd") then
        local spiketargets = self.inst.FindSpikeTargets ~= nil and self.inst:FindSpikeTargets() or nil
        if spiketargets ~= nil and #spiketargets > 0 then
            return true
        end
        self.inst.components.timer:StartTimer("spikes_cd", SHADOW_STALKER_ABILITY_MISS_RETRY)
    end
    return false
end

local function ShouldSummonChannelers(self)
    local inst = self.inst
    return not IsSkillDelayActive(inst)
        and not inst.components.timer:TimerExists("channelers_cd")
        and not inst._feast_lantern_mc_ward
        and not (inst.components.timer ~= nil
            and inst.components.timer:TimerExists("shadow_stalker_channelers_duration"))
end

local function ShouldMindControl(self)
    local inst = self.inst
    if FeastBuffEffects.IsDuelistCrowdControlBlocked(inst) then
        FeastBuffEffects.ClearImmediateLanternMcChain(inst)
        return false
    end

    local wants_immediate = FeastBuffEffects.WantsImmediateLanternMcChain(inst)

    if wants_immediate
        and inst.sg ~= nil
        and not inst.sg:HasStateTag("feasting")
        and not inst:HasMindControlTarget() then
        FeastBuffEffects.ClearImmediateLanternMcChain(inst)
        wants_immediate = false
    end

    local skill_delay_ok = wants_immediate or not IsSkillDelayActive(inst)
    local mc_cd_ok = wants_immediate
        or not inst.components.timer:TimerExists("mindcontrol_cd")

    if skill_delay_ok and mc_cd_ok then
        if inst.sg ~= nil and inst.sg:HasStateTag("feasting") then
            return false
        end
        if inst:HasMindControlTarget() then
            return true
        end
        if not wants_immediate then
            inst.components.timer:StartTimer("mindcontrol_cd", SHADOW_STALKER_ABILITY_MISS_RETRY)
        end
    end
    return false
end

local function ShouldCombatFeast(self)
    if IsSkillDelayActive(self.inst)
        or self.inst.components.timer:TimerExists("feast_cd") then
        return false
    end

    local target = self.inst:FindFeastTarget()
    if target ~= nil then
        self.abilitydata = { target = target }
        return true
    end

    return false
end

local function AbilityNeedsCombatTarget(ability)
    return ability == "fossilsnare"
        or ability == "fossilspikes"
        or ability == "shadowchannelers"
end

local function TryAbility(self, ability)
    if ability == "fossilfeast" then
        return ShouldCombatFeast(self) and "fossilfeast" or nil
    elseif ability == "mindcontrol" then
        return ShouldMindControl(self) and "mindcontrol" or nil
    elseif ability == "shadowchannelers" then
        return ShouldSummonChannelers(self) and "shadowchannelers" or nil
    elseif ability == "fossilsnare" then
        return ShouldSnare(self) and "fossilsnare" or nil
    elseif ability == "fossilspikes" then
        return ShouldSpikes(self) and "fossilspikes" or nil
    end
    return nil
end

local function ShouldUseAbility(self)
    self.abilityname = nil
    self.abilitydata = nil

    for _, ability in ipairs(ABILITY_PRIORITY) do
        if not AbilityNeedsCombatTarget(ability)
            or self.inst.components.combat:HasTarget() then
            local chosen = TryAbility(self, ability)
            if chosen ~= nil then
                self.abilityname = chosen
                return true
            end
        end
    end

    return false
end

function ShadowStalkerBrain:OnStart()
    local face_leader = FaceEntity(self.inst, GetFaceLeaderFn, KeepFaceLeaderFn)
    local follow_leader = Follow(self.inst, GetLeaderInWorkArea, MIN_FOLLOW_DIST, TARGET_FOLLOW_DIST, MAX_FOLLOW_DIST)
    local leader_patrol = WhileNode(
        function() return ShouldLeaderPatrol(self.inst) end,
        "LeaderPatrol",
        Wander(
            self.inst,
            GetLeaderPatrolHome,
            GetLeaderWanderMaxDist,
            {
                minwalktime = 1.5,
                randwalktime = .5,
                minwaittime = PATROL_DELAY,
                randwaittime = 0,
            },
            nil,
            nil,
            nil,
            {
                wander_dist = LEADER_PATROL_WANDER_DIST,
                ignore_walls = true,
            }
        )
    )
    local center_patrol = WhileNode(
        function() return ShouldCenterPatrol(self.inst) end,
        "CenterPatrol",
        Wander(
            self.inst,
            GetWorkCenter,
            GetCenterPatrolMaxDist,
            {
                minwalktime = 1.5,
                randwalktime = .5,
                minwaittime = PATROL_DELAY,
                randwaittime = 0,
            },
            nil,
            nil,
            nil,
            {
                wander_dist = CENTER_PATROL_WANDER_DIST,
                ignore_walls = true,
            }
        )
    )

    local root = PriorityNode(
    {
        Leash(self.inst, GetWorkCenter, self.inst._workradius or KEEP_WORKING_DIST, math.max(2, (self.inst._workradius or KEEP_WORKING_DIST) - 3)),
        WhileNode(function() return ShouldUseAbility(self) end, "Ability",
            ActionNode(function()
                self.inst:PushEvent(self.abilityname, self.abilitydata)
                self.abilityname = nil
                self.abilitydata = nil
            end)),
        ChaseAndAttack(self.inst),
        follow_leader,
        leader_patrol,
        center_patrol,
        face_leader,
        StandStill(self.inst),
    }, .25)

    self.bt = BT(self.inst, root)
end

return ShadowStalkerBrain
