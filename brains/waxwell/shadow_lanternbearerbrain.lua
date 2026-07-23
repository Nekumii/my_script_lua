require "behaviours/follow"
require "behaviours/faceentity"

local ShadowLanternbearerBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

local MIN_FOLLOW_DIST = 0
local TARGET_FOLLOW_DIST = 3.25
local MAX_FOLLOW_DIST = 7
local START_FACE_DIST = 4
local KEEP_FACE_DIST = 8

local function GetTargetPlayer(inst)
    return inst.GetTargetPlayer ~= nil and inst:GetTargetPlayer() or nil
end

local function GetFaceTargetFn(inst)
    local player = GetTargetPlayer(inst)
    return player ~= nil and player.entity:IsVisible() and inst:IsNear(player, START_FACE_DIST) and player or nil
end

local function KeepFaceTargetFn(inst, target)
    return target ~= nil and target.entity:IsVisible() and inst:IsNear(target, KEEP_FACE_DIST)
end

function ShadowLanternbearerBrain:OnStart()
    local root = PriorityNode({
        Follow(self.inst, GetTargetPlayer, MIN_FOLLOW_DIST, TARGET_FOLLOW_DIST, MAX_FOLLOW_DIST),
        FaceEntity(self.inst, GetFaceTargetFn, KeepFaceTargetFn),
    }, 0.25)

    self.bt = BT(self.inst, root)
end

return ShadowLanternbearerBrain
