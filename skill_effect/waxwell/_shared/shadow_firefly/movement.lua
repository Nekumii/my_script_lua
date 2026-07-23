local Profiles = require("skill_effect/waxwell/_shared/shadow_firefly/profiles")

local M = {}

local HUNT_PERIOD = 0.25
local STOP_DIST = 0

local WANDER_DIR_MIN = 0.75
local WANDER_DIR_MAX = 2.25
local WANDER_SPEED_MIN_MULT = 0.75
local WANDER_SPEED_MAX_MULT = 1
local WANDER_PAUSE_CHANCE = 0.12
local WANDER_SWIRL_STRENGTH = 0.22

local HUNT_MUST_TAGS = { "_combat", "_health" }
local HUNT_CANT_TAGS = { "INLIMBO", "playerghost", "companion", "player", "waxwell_shadow_firefly" }
local HUNT_ONEOF_TAGS = { "monster", "prey", "insect", "hostile", "character", "animal" }

local function IsValidHuntTarget(fly, ent)
    if ent == nil
        or not ent:IsValid()
        or ent == fly
        or ent.components == nil
        or ent.components.combat == nil
        or ent.components.health == nil
        or ent.components.health:IsDead() then
        return false
    end

    if ent:HasTag("player")
        or ent:HasTag("companion")
        or ent:HasTag("shadow_lanternbearer")
        or ent:HasTag("waxwell_shadow_firefly") then
        return false
    end

    local host = fly._shadow_firefly_host
    if host ~= nil and ent == host then
        return false
    end

    local attacker = fly._shadow_firefly_attacker
    if attacker ~= nil and ent == attacker then
        return false
    end

    return true
end

local function FindHuntTarget(fly)
    local fx, fy, fz = fly.Transform:GetWorldPosition()
    local radius = Profiles.GetLanternbearerSearchRadius(fly._shadow_firefly_host)
    local ents = TheSim:FindEntities(fx, fy, fz, radius, HUNT_MUST_TAGS, HUNT_CANT_TAGS, HUNT_ONEOF_TAGS)

    local best = nil
    local bestsq = nil

    for _, ent in ipairs(ents) do
        if IsValidHuntTarget(fly, ent) then
            local ex, _, ez = ent.Transform:GetWorldPosition()
            local dx, dz = ex - fx, ez - fz
            local dsq = dx * dx + dz * dz
            if bestsq == nil or dsq < bestsq then
                best = ent
                bestsq = dsq
            end
        end
    end

    return best
end

local function StopMoving(fly)
    if fly.Physics ~= nil then
        fly.Physics:Stop()
    end
    fly._shadow_firefly_move_dx = 0
    fly._shadow_firefly_move_dz = 0
    fly._shadow_firefly_move_speed = 0
end

local function SetMovementIntent(fly, dir_x, dir_z, speed)
    fly._shadow_firefly_move_dx = dir_x
    fly._shadow_firefly_move_dz = dir_z
    fly._shadow_firefly_move_speed = speed or 0
end

local function ApplyStoredMovement(fly)
    if fly == nil or not fly:IsValid() or fly._shadow_firefly_dying or fly._shadow_firefly_fading then
        return
    end

    local speed = fly._shadow_firefly_move_speed or 0
    local dir_x = fly._shadow_firefly_move_dx or 0
    local dir_z = fly._shadow_firefly_move_dz or 0

    if speed <= 0 then
        if fly.Physics ~= nil then
            fly.Physics:Stop()
        end
        return
    end

    local len = math.sqrt(dir_x * dir_x + dir_z * dir_z)
    if len <= 0 then
        if fly.Physics ~= nil then
            fly.Physics:Stop()
        end
        return
    end

    dir_x = dir_x / len
    dir_z = dir_z / len

    local step = speed * FRAMES
    local x, y, z = fly.Transform:GetWorldPosition()
    fly.Transform:SetPosition(x + dir_x * step, y, z + dir_z * step)

    fly.Transform:SetRotation(math.atan2(-dir_z, dir_x) / DEGREES)
end

local function ClearWanderState(fly)
    fly._shadow_firefly_wander_until = nil
    fly._shadow_firefly_wander_pause_until = nil
end

local function PickNewWanderDir(fly)
    local angle = math.random() * TWOPI
    fly._shadow_firefly_wander_dx = math.cos(angle)
    fly._shadow_firefly_wander_dz = math.sin(angle)
    fly._shadow_firefly_wander_until = GetTime() + WANDER_DIR_MIN + math.random() * (WANDER_DIR_MAX - WANDER_DIR_MIN)
    fly._shadow_firefly_wander_speed = Profiles.LANTERNBEARER_WALK_SPEED
        * (WANDER_SPEED_MIN_MULT + math.random() * (WANDER_SPEED_MAX_MULT - WANDER_SPEED_MIN_MULT))
    fly._shadow_firefly_wander_pause_until = nil

    if math.random() < WANDER_PAUSE_CHANCE then
        fly._shadow_firefly_wander_pause_until = GetTime() + 0.25 + math.random() * 0.5
    end
end

local function UpdateBurst(fly)
    local burst_until = fly._shadow_firefly_burst_until
    if burst_until == nil or GetTime() >= burst_until then
        fly._shadow_firefly_burst_until = nil
        return false
    end

    local dir_x = fly._shadow_firefly_burst_dx or 1
    local dir_z = fly._shadow_firefly_burst_dz or 0
    SetMovementIntent(fly, dir_x, dir_z, Profiles.LANTERNBEARER_WALK_SPEED)
    return true
end

local function MoveTowardTarget(fly, target)
    if target == nil or not target:IsValid() then
        StopMoving(fly)
        return
    end

    ClearWanderState(fly)

    local tx, ty, tz = target.Transform:GetWorldPosition()
    local fx, fy, fz = fly.Transform:GetWorldPosition()
    local dx, dz = tx - fx, tz - fz
    local distsq = dx * dx + dz * dz

    if distsq <= STOP_DIST * STOP_DIST then
        StopMoving(fly)
        if fly.Physics ~= nil then
            fly.Physics:Teleport(tx, ty, tz)
        else
            fly.Transform:SetPosition(tx, fy, tz)
        end
        return
    end

    local speed = Profiles.LANTERNBEARER_WALK_SPEED
    SetMovementIntent(fly, dx, dz, speed)
end

local function UpdateWander(fly)
    local t = GetTime()

    if fly._shadow_firefly_wander_until == nil or t >= fly._shadow_firefly_wander_until then
        PickNewWanderDir(fly)
    end

    if fly._shadow_firefly_wander_pause_until ~= nil and t < fly._shadow_firefly_wander_pause_until then
        StopMoving(fly)
        return
    end

    local dx = fly._shadow_firefly_wander_dx or 1
    local dz = fly._shadow_firefly_wander_dz or 0
    local speed = fly._shadow_firefly_wander_speed or (Profiles.LANTERNBEARER_WALK_SPEED * WANDER_SPEED_MIN_MULT)
    local phase = (fly._shadow_firefly_wander_phase or 0) + t * 3.5
    local swirl = math.sin(phase) * WANDER_SWIRL_STRENGTH

    local perp_x = -dz
    local perp_z = dx
    local dir_x = dx + perp_x * swirl
    local dir_z = dz + perp_z * swirl
    local len = math.sqrt(dir_x * dir_x + dir_z * dir_z)

    if len > 0 then
        dir_x = dir_x / len
        dir_z = dir_z / len
    end

    SetMovementIntent(fly, dir_x, dir_z, speed)
end

local function UpdateHunt(fly)
    if fly == nil or not fly:IsValid() or fly._shadow_firefly_dying or fly._shadow_firefly_fading then
        return
    end

    if UpdateBurst(fly) then
        return
    end

    local target = FindHuntTarget(fly)
    if target ~= nil then
        MoveTowardTarget(fly, target)
    else
        UpdateWander(fly)
    end
end

function M.BeginBurstScatter(fly, dir_x, dir_z, duration)
    if fly == nil or not fly:IsValid() then
        return
    end

    local len = math.sqrt(dir_x * dir_x + dir_z * dir_z)
    if len > 0 then
        dir_x = dir_x / len
        dir_z = dir_z / len
    else
        local angle = math.random() * TWOPI
        dir_x = math.cos(angle)
        dir_z = math.sin(angle)
    end

    fly._shadow_firefly_burst_dx = dir_x
    fly._shadow_firefly_burst_dz = dir_z
    fly._shadow_firefly_burst_until = GetTime() + (duration or Profiles.LANTERNBEARER_BURST_DURATION or .65)
    SetMovementIntent(fly, dir_x, dir_z, Profiles.LANTERNBEARER_WALK_SPEED)
end

function M.Setup(inst)
    if inst == nil or not inst:IsValid() then
        return
    end

    inst._shadow_firefly_wander_phase = math.random() * TWOPI
    ClearWanderState(inst)
    PickNewWanderDir(inst)
    UpdateWander(inst)

    if inst._shadow_firefly_move_task ~= nil then
        inst._shadow_firefly_move_task:Cancel()
    end
    inst._shadow_firefly_move_task = inst:DoPeriodicTask(FRAMES, ApplyStoredMovement)

    if inst._shadow_firefly_hunt_task ~= nil then
        inst._shadow_firefly_hunt_task:Cancel()
    end
    inst._shadow_firefly_hunt_task = inst:DoPeriodicTask(HUNT_PERIOD, UpdateHunt)
end

function M.Stop(inst)
    if inst == nil then
        return
    end

    if inst._shadow_firefly_move_task ~= nil then
        inst._shadow_firefly_move_task:Cancel()
        inst._shadow_firefly_move_task = nil
    end

    if inst._shadow_firefly_hunt_task ~= nil then
        inst._shadow_firefly_hunt_task:Cancel()
        inst._shadow_firefly_hunt_task = nil
    end

    ClearWanderState(inst)
    StopMoving(inst)
    inst._shadow_firefly_burst_until = nil
    inst._shadow_firefly_burst_dx = nil
    inst._shadow_firefly_burst_dz = nil
end

return M
