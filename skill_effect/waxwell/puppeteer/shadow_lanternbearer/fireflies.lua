local Profiles = require("skill_effect/waxwell/_shared/shadow_firefly/profiles")
local Spawn = require("skill_effect/waxwell/_shared/shadow_firefly/spawn")
local SpawnGate = require("skill_effect/waxwell/puppeteer/shadow_lanternbearer/spawn_gate")

local M = {}

local function FindWaxwellOwner(lantern)
    if lantern == nil then
        return nil
    end

    local owner = lantern._waxwell_owner
    if owner ~= nil and owner:IsValid() then
        return owner
    end

    if lantern._waxwell_owner_userid ~= nil then
        for _, player in ipairs(AllPlayers) do
            if player ~= nil and player.userid == lantern._waxwell_owner_userid then
                lantern._waxwell_owner = player
                return player
            end
        end
    end

    return nil
end

local function TrySpawnFireflyBurst(lantern)
    if lantern == nil or not lantern:IsValid() then
        return
    end

    if not SpawnGate.CanSpawnFireflies(lantern) then
        return
    end

    if lantern.sg ~= nil and (lantern.sg:HasStateTag("busy") or lantern.sg:HasStateTag("phasing")) then
        return
    end

    local x, y, z = lantern.Transform:GetWorldPosition()
    lantern._lanternbearer_fireflies = lantern._lanternbearer_fireflies or {}

    local spawn_count = Profiles.LANTERNBEARER_SPAWN_COUNT or 3
    local burst_offset = Profiles.LANTERNBEARER_BURST_OFFSET or .35
    local base_angle = math.random() * TWOPI
    local attacker = FindWaxwellOwner(lantern)

    for i = 1, spawn_count do
        local angle = base_angle + (i - 1) * TWOPI / spawn_count
        local dir_x = math.cos(angle)
        local dir_z = math.sin(angle)

        Spawn.SpawnShadowFirefly({
            profile = Profiles.PROFILE_LANTERNBEARER_LV2,
            host = lantern,
            pos = Vector3(x + dir_x * burst_offset, y, z + dir_z * burst_offset),
            attacker = attacker,
            track_list = lantern._lanternbearer_fireflies,
            burst_dir = { x = dir_x, z = dir_z },
            burst_duration = Profiles.LANTERNBEARER_BURST_DURATION,
        })
    end
end

function M.GetActiveLanternFireflies(lantern)
    if lantern == nil or lantern._lanternbearer_fireflies == nil then
        return {}
    end

    local active = {}
    for _, fly in ipairs(lantern._lanternbearer_fireflies) do
        if fly ~= nil and fly:IsValid() then
            table.insert(active, fly)
        end
    end
    return active
end

function M.BeginLanternFireflies(lantern)
    if lantern == nil or not TheWorld.ismastersim then
        return
    end

    if lantern._lanternbearer_firefly_spawn_task ~= nil then
        return
    end

    lantern._lanternbearer_fireflies = lantern._lanternbearer_fireflies or {}
    SpawnGate.Begin(lantern)
    lantern._lanternbearer_firefly_spawn_task = lantern:DoPeriodicTask(
        Profiles.LANTERNBEARER_SPAWN_INTERVAL,
        TrySpawnFireflyBurst
    )
end

function M.EndLanternFireflies(lantern)
    if lantern == nil then
        return
    end

    SpawnGate.End(lantern)

    if lantern._lanternbearer_firefly_spawn_task ~= nil then
        lantern._lanternbearer_firefly_spawn_task:Cancel()
        lantern._lanternbearer_firefly_spawn_task = nil
    end

    if lantern._lanternbearer_fireflies ~= nil then
        Spawn.ClearFireflies(lantern._lanternbearer_fireflies, true)
        lantern._lanternbearer_fireflies = {}
    end
end

return M
