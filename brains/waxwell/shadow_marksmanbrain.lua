require "behaviours/wander"
require "behaviours/faceentity"
require "behaviours/chaseandattack"
require "behaviours/follow"
require "behaviours/leash"
require "behaviours/runaway"

local ShadowMarksmanBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

local START_FACE_DIST = 4
local KEEP_FACE_DIST = 8
local KEEP_DANCING_DIST = 2
local AVOID_EXPLOSIVE_DIST = 5
local WatchingMinigame_MinDist = 1
local WatchingMinigame_TargetDist = 3
local WatchingMinigame_MaxDist = 6
local MARKSMAN_TOO_CLOSE_DIST = 4.25
local MARKSMAN_SAFE_DIST = 6.25

local function GetLeader(inst)
    return inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
end

local function GetLeaderPos(inst)
    local leader = GetLeader(inst)
    return leader ~= nil and leader:GetPosition() or nil
end

local function GetFaceLeaderFn(inst)
    local leader = GetLeader(inst)
    return leader ~= nil and leader.entity:IsVisible() and inst:IsNear(leader, START_FACE_DIST) and leader or nil
end

local function KeepFaceLeaderFn(inst, target)
    return target ~= nil and target.entity:IsVisible() and inst:IsNear(target, KEEP_FACE_DIST)
end

local function WatchingMinigame(inst)
    local leader = GetLeader(inst)
    if leader ~= nil and leader.components.minigame_participator ~= nil then
        local participator = leader.components.minigame_participator
        local target = participator:GetMinigame() or participator:GetStation()
        if target ~= nil and target:IsValid() then
            return target
        end
    end
end

local function ShouldWatchMinigame(inst)
    local leader = GetLeader(inst)
    if leader ~= nil and leader.components.minigame_participator ~= nil then
        if inst.components.combat.target == nil or inst.components.combat.target.components.minigame_participator ~= nil then
            return true
        end
    end
    return false
end

local function DanceParty(inst)
    inst:PushEvent("dance")
end

local function ShouldDanceParty(inst)
    local leader = GetLeader(inst)
    return leader ~= nil and leader.sg ~= nil and leader.sg:HasStateTag("dancing")
end

local function ShouldAvoidExplosive(target)
    return target.components.explosive == nil
        or target.components.burnable == nil
        or target.components.burnable:IsBurning()
end

local function GetSpawn(inst)
    return inst.GetSpawnPoint ~= nil and inst:GetSpawnPoint() or nil
end

local function ShouldBackAwayFromTarget(target, inst)
    if target == nil
        or inst == nil
        or inst.components.combat == nil
        or not inst.components.combat:TargetIs(target)
        or not inst.components.combat:CanTarget(target) then
        return false
    end

    local spawn = GetSpawn(inst)
    if spawn ~= nil then
        local maxdist = math.max(0, TUNING.SHADOWWAXWELL_PROTECTOR_DEFEND_RADIUS - 1)
        if inst:GetDistanceSqToPoint(spawn) > maxdist * maxdist then
            return false
        end
    end

    return inst:GetDistanceSqToInst(target) < MARKSMAN_TOO_CLOSE_DIST * MARKSMAN_TOO_CLOSE_DIST
end

local function CreateWanderer(self, maxdist)
    return Wander(self.inst,
        function() return GetSpawn(self.inst) end,
        maxdist,
        nil, nil, nil, nil,
        {
            should_run = false,
            wander_dist = 4,
        }
    )
end

local function CreateIdleOblivion(self, delay, range)
    range = range * range
    return LoopNode{
        WaitNode(delay),
        ActionNode(function()
            local leader = GetLeader(self.inst)
            local spawnpt = GetSpawn(self.inst)
            if leader ~= nil and spawnpt ~= nil and leader:GetDistanceSqToPoint(spawnpt) >= range then
                self.inst:PushEvent("seekoblivion")
            end
        end),
    }
end

function ShadowMarksmanBrain:OnStart()
    local watch_game = WhileNode(function() return ShouldWatchMinigame(self.inst) end, "Watching Game",
        PriorityNode({
            Follow(self.inst, WatchingMinigame, WatchingMinigame_MinDist, WatchingMinigame_TargetDist, WatchingMinigame_MaxDist),
            RunAway(self.inst, "minigame_participator", 5, 7),
            FaceEntity(self.inst, WatchingMinigame, WatchingMinigame),
        }, 0.25))

    local dance_party = WhileNode(function() return ShouldDanceParty(self.inst) end, "Dance Party",
        PriorityNode({
            Leash(self.inst, GetLeaderPos, KEEP_DANCING_DIST, KEEP_DANCING_DIST),
            ActionNode(function() DanceParty(self.inst) end),
        }, 0.25))

    local avoid_explosions = RunAway(self.inst, { fn = ShouldAvoidExplosive, tags = { "explosive" }, notags = { "INLIMBO" } }, AVOID_EXPLOSIVE_DIST, AVOID_EXPLOSIVE_DIST)
    local back_away_from_target = RunAway(
        self.inst,
        {
            getfn = function(inst)
                return inst.components.combat ~= nil and inst.components.combat.target or nil
            end,
        },
        MARKSMAN_TOO_CLOSE_DIST,
        MARKSMAN_SAFE_DIST,
        ShouldBackAwayFromTarget,
        nil,
        nil,
        nil,
        GetSpawn
    )
    local face_leader = FaceEntity(self.inst, GetFaceLeaderFn, KeepFaceLeaderFn)

    local root = PriorityNode({
        dance_party,
        watch_game,
        avoid_explosions,
        back_away_from_target,
        ChaseAndAttack(self.inst),
        Leash(
            self.inst,
            GetSpawn,
            math.min(8, TUNING.SHADOWWAXWELL_PROTECTOR_DEFEND_RADIUS),
            math.min(4, TUNING.SHADOWWAXWELL_PROTECTOR_DEFEND_RADIUS)
        ),
        face_leader,
        ParallelNode{
            CreateWanderer(self, math.min(6, TUNING.SHADOWWAXWELL_PROTECTOR_DEFEND_RADIUS)),
            CreateIdleOblivion(self, TUNING.SHADOWWAXWELL_MINION_IDLE_DESPAWN_TIME, TUNING.SHADOWWAXWELL_PROTECTOR_DEFEND_RADIUS),
        },
    }, 0.25)

    self.bt = BT(self.inst, root)
end

function ShadowMarksmanBrain:OnInitializationComplete()
    if self.inst.SaveSpawnPoint ~= nil then
        self.inst:SaveSpawnPoint(true)
    end
end

return ShadowMarksmanBrain
