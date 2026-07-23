local Profiles = require("skill_effect/waxwell/_shared/shadow_firefly/profiles")
local Lifecycle = require("skill_effect/waxwell/_shared/shadow_firefly/lifecycle")

local M = {}

local function PruneTrackList(track_list)
    if track_list == nil then
        return
    end

    for i = #track_list, 1, -1 do
        local fly = track_list[i]
        if fly == nil or not fly:IsValid() then
            table.remove(track_list, i)
        end
    end
end

local function TrackFirefly(track_list, fly)
    if track_list == nil or fly == nil then
        return
    end

    PruneTrackList(track_list)
    table.insert(track_list, fly)

    fly:ListenForEvent("onremove", function()
        PruneTrackList(track_list)
        for i = #track_list, 1, -1 do
            if track_list[i] == fly then
                table.remove(track_list, i)
                break
            end
        end
    end)
end

function M.GetExistingPositions(track_list)
    local positions = {}
    if track_list == nil then
        return positions
    end

    PruneTrackList(track_list)
    for _, fly in ipairs(track_list) do
        if fly ~= nil and fly:IsValid() then
            local x, _, z = fly.Transform:GetWorldPosition()
            table.insert(positions, { x = x, z = z })
        end
    end

    return positions
end

local function IsSpawnPointClear(positions, x, z)
    local min_sep = Profiles.FIREFLY_MIN_SEP
    local min_sepsq = min_sep * min_sep
    for _, pos in ipairs(positions) do
        local dx, dz = x - pos.x, z - pos.z
        if dx * dx + dz * dz < min_sepsq then
            return false
        end
    end
    return true
end

function M.FindFeastMcSpawnPoint(host, positions, slot_index, slot_total)
    if host == nil or not host:IsValid() then
        return nil, nil
    end

    local center = host.GetWorkCenter ~= nil and host:GetWorkCenter() or nil
    if center == nil then
        local x, _, z = host.Transform:GetWorldPosition()
        center = Vector3(x, 0, z)
    end

    local radius = (host._workradius or 14) * 0.9
    local map = TheWorld.Map
    slot_total = math.max(slot_total or 1, 1)
    slot_index = math.clamp(slot_index or 1, 1, slot_total)

    for attempt = 1, 28 do
        local angle
        local dist
        if attempt <= 12 then
            local sector_width = TWOPI / slot_total
            local sector_start = (slot_index - 1) * sector_width
            angle = sector_start + math.random() * sector_width
            dist = radius * (0.45 + math.random() * 0.55)
        else
            angle = math.random() * TWOPI
            dist = math.sqrt(math.random()) * radius
        end

        local x = center.x + math.cos(angle) * dist
        local z = center.z + math.sin(angle) * dist
        if map:IsPassableAtPoint(x, 0, z)
            and not map:IsPointNearHole(Vector3(x, 0, z))
            and IsSpawnPointClear(positions, x, z) then
            return x, z
        end
    end

    return nil, nil
end

function M.SpawnShadowFirefly(opts)
    if not TheWorld.ismastersim or opts == nil then
        return nil
    end

    local profile = Profiles.GetProfile(opts.profile)
    if profile == nil then
        return nil
    end

    local fly = SpawnPrefab(Profiles.FIREFLY_PREFAB)
    if fly == nil then
        return nil
    end

    local pos = opts.pos
    if pos ~= nil then
        fly.Transform:SetPosition(pos.x, pos.y or 0, pos.z)
    end

    Lifecycle.Configure(fly, opts)

    if opts.track_list ~= nil then
        TrackFirefly(opts.track_list, fly)
    end

    return fly
end

function M.ClearFireflies(track_list, use_fade)
    if track_list == nil then
        return
    end

    for _, fly in ipairs(track_list) do
        if fly ~= nil and fly:IsValid() then
            if use_fade and fly.FadeOutAndRemove ~= nil then
                fly:FadeOutAndRemove()
            elseif fly.ForceDespawn ~= nil then
                fly:ForceDespawn()
            elseif fly.components ~= nil and fly.components.health ~= nil then
                fly.components.health:Kill()
            else
                fly:Remove()
            end
        end
    end

    for i = #track_list, 1, -1 do
        track_list[i] = nil
    end
end

return M
