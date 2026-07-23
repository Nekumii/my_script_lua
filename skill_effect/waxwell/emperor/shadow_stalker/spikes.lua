local FeastBuffEffects = require("skill_effect/waxwell/emperor/shadow_stalker/feast_buff_effects")

local M = {}

M.MOVE_SPEED = 8
M.ARRIVE_DIST = 0.2

M.BASE_HEAD_Y = 2.0
M.BASE_FORM_RADIUS = 0.5
M.BASE_SPIKE_SCALE = 1.5

local RETARGET_MUST_TAGS = { "_combat", "_health" }
local RETARGET_CANT_TAGS =
{
    "INLIMBO",
    "notarget",
    "invisible",
    "noattack",
    "flight",
    "playerghost",
    "shadow",
    "shadowchesspiece",
    "shadowcreature",
}

local function GetWorkRadius(inst)
    return inst._workradius or 14
end

local function GetWorkCenter(inst)
    if inst.GetWorkCenter ~= nil then
        return inst:GetWorkCenter()
    end
    local x, _, z = inst.Transform:GetWorldPosition()
    return Vector3(x, 0, z)
end

local function IsTargetAlive(target)
    return target ~= nil
        and target:IsValid()
        and not target:IsInLimbo()
        and target.components.health ~= nil
        and not target.components.health:IsDead()
end

function M.GetFormationOffsetXZ(index, total, form_r)
    if total <= 1 then
        return 0, 0
    elseif total == 2 then
        return (index == 1 and -form_r or form_r), 0
    end

    -- 3+ = polygon (Marksman 6 spikes = hexagon)
    local angle = (index - 1) / total * TWOPI - PI * 0.5
    return math.cos(angle) * form_r, math.sin(angle) * form_r
end

function M.GetTargetLayout(_target)
    return M.BASE_HEAD_Y, M.BASE_FORM_RADIUS
end

-- Fixed float height for base scale; larger SetScale sinks Y so tip still hits ground.
-- Never raises for big targets.
function M.GetFloatY(spike)
    local scale = (spike ~= nil and spike._ss_spike_scale) or M.BASE_SPIKE_SCALE
    if scale <= 0 then
        scale = M.BASE_SPIKE_SCALE
    end
    return M.BASE_HEAD_Y * (M.BASE_SPIKE_SCALE / scale)
end

function M.GetDesiredWorldPosition(stalker, spike)
    local float_y = M.GetFloatY(spike)
    local target = spike._ss_target
    if IsTargetAlive(target) then
        local _, form_r = M.GetTargetLayout(target)
        local x, _, z = target.Transform:GetWorldPosition()
        local ox, oz = M.GetFormationOffsetXZ(
            spike._ss_formation_index or 1,
            spike._ss_formation_total or 1,
            form_r
        )
        return x + ox, float_y, z + oz
    end

    if spike._ss_idle_x ~= nil then
        return spike._ss_idle_x, float_y, spike._ss_idle_z
    end

    local px, _, pz = spike.Transform:GetWorldPosition()
    return px, float_y, pz
end

local function PruneSpikeList(spikes)
    local i = 1
    while i <= #spikes do
        local spike = spikes[i]
        if spike == nil or not spike:IsValid() then
            table.remove(spikes, i)
        else
            i = i + 1
        end
    end
end

local function GetTargetGroup(stalker, target)
    if stalker._ss_spike_groups == nil then
        stalker._ss_spike_groups = {}
    end

    local key = target.GUID
    local group = stalker._ss_spike_groups[key]
    if group == nil then
        group = { target = target, spikes = {} }
        stalker._ss_spike_groups[key] = group
    elseif group.target ~= target then
        group.target = target
    end

    return group
end

local function RemoveSpikeFromGroups(stalker, spike)
    if stalker._ss_spike_groups == nil then
        return
    end

    for key, group in pairs(stalker._ss_spike_groups) do
        for i = #group.spikes, 1, -1 do
            if group.spikes[i] == spike then
                table.remove(group.spikes, i)
            end
        end
        if #group.spikes <= 0 then
            stalker._ss_spike_groups[key] = nil
        end
    end
end

function M.RecomputeFormation(group)
    PruneSpikeList(group.spikes)
    local total = #group.spikes
    for i, spike in ipairs(group.spikes) do
        spike._ss_formation_index = i
        spike._ss_formation_total = total
    end
end

function M.CountSpikesOnTarget(stalker, target)
    if stalker._ss_spike_groups == nil or target == nil then
        return 0
    end

    local group = stalker._ss_spike_groups[target.GUID]
    if group == nil then
        return 0
    end

    PruneSpikeList(group.spikes)
    M.RecomputeFormation(group)
    return #group.spikes
end

function M.AssignSpikeTarget(stalker, spike, target)
    RemoveSpikeFromGroups(stalker, spike)
    spike._ss_target = target

    if IsTargetAlive(target) then
        local group = GetTargetGroup(stalker, target)
        local found = false
        for _, existing in ipairs(group.spikes) do
            if existing == spike then
                found = true
                break
            end
        end
        if not found then
            table.insert(group.spikes, spike)
        end
        M.RecomputeFormation(group)
    end
end

local function SetIdleSpreadPosition(stalker, spike, slot_index, total_slots)
    local center = GetWorkCenter(stalker)
    local radius = GetWorkRadius(stalker) * 0.75
    total_slots = math.max(total_slots or 1, 1)
    slot_index = math.clamp(slot_index or 1, 1, total_slots)
    local angle = (slot_index - 1) / total_slots * TWOPI + (slot_index - 0.5) * 0.12
    spike._ss_idle_x = center.x + math.cos(angle) * radius
    spike._ss_idle_y = nil
    spike._ss_idle_z = center.z + math.sin(angle) * radius
end

function M.FindTargets(inst, is_valid_enemy_fn)
    if inst == nil or not inst:IsValid() then
        return {}
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(x, y, z, GetWorkRadius(inst), RETARGET_MUST_TAGS, RETARGET_CANT_TAGS)
    local targets = {}

    for _, guy in ipairs(ents) do
        if is_valid_enemy_fn(inst, guy) then
            table.insert(targets, guy)
        end
    end

    table.sort(targets, function(a, b)
        return a:GetDistanceSqToInst(inst) < b:GetDistanceSqToInst(inst)
    end)

    return targets
end

local function FindRetarget(stalker, spike, is_valid_enemy_fn)
    local x, _, z = spike.Transform:GetWorldPosition()
    local targets = M.FindTargets(stalker, is_valid_enemy_fn)

    local best, best_dist
    for _, target in ipairs(targets) do
        local tx, _, tz = target.Transform:GetWorldPosition()
        local dx, dz = tx - x, tz - z
        local dist = dx * dx + dz * dz
        if best == nil or dist < best_dist then
            best = target
            best_dist = dist
        end
    end

    return best
end

function M.BuildCastAssignments(inst, is_valid_enemy_fn)
    local targets = M.FindTargets(inst, is_valid_enemy_fn)
    local assignments = {}
    local per_cast = FeastBuffEffects.GetSpikesPerCast(inst)

    if #targets <= 0 then
        return assignments
    end

    -- 1 spike per target first; leftovers spread idle; no per-target cap
    local targeted = math.min(per_cast, #targets)
    for i = 1, targeted do
        table.insert(assignments, { target = targets[i] })
    end

    local idle_total = per_cast - targeted
    for slot = 1, idle_total do
        table.insert(assignments, { target = nil, idle_slot = slot, idle_total = idle_total })
    end

    return assignments
end

function M.RegisterSpike(stalker, spike, assignment)
    stalker._ss_active_spikes = stalker._ss_active_spikes or {}
    table.insert(stalker._ss_active_spikes, spike)

    spike._ss_stalker = stalker

    if assignment ~= nil and IsTargetAlive(assignment.target) then
        M.AssignSpikeTarget(stalker, spike, assignment.target)
    elseif assignment ~= nil and assignment.idle_slot ~= nil then
        spike._ss_target = nil
        SetIdleSpreadPosition(stalker, spike, assignment.idle_slot, assignment.idle_total or 1)
    end

    if spike._ss_onremove_fn == nil then
        spike._ss_onremove_fn = function()
            M.UnregisterSpike(stalker, spike)
        end
        spike:ListenForEvent("onremove", spike._ss_onremove_fn)
    end
end

function M.UnregisterSpike(stalker, spike)
    if stalker._ss_active_spikes ~= nil then
        for i = #stalker._ss_active_spikes, 1, -1 do
            if stalker._ss_active_spikes[i] == spike then
                table.remove(stalker._ss_active_spikes, i)
            end
        end
    end

    local target = spike._ss_target
    RemoveSpikeFromGroups(stalker, spike)
    if target ~= nil and stalker._ss_spike_groups ~= nil then
        local group = stalker._ss_spike_groups[target.GUID]
        if group ~= nil then
            M.RecomputeFormation(group)
        end
    end
end

function M.UpdateSpike(stalker, spike, is_valid_enemy_fn)
    if spike._ss_telegraph_phase == "done" then
        return
    end

    if not IsTargetAlive(spike._ss_target) then
        local old = spike._ss_target
        RemoveSpikeFromGroups(stalker, spike)
        spike._ss_target = nil

        local new_target = FindRetarget(stalker, spike, is_valid_enemy_fn)
        if new_target ~= nil then
            M.AssignSpikeTarget(stalker, spike, new_target)
        elseif old ~= nil then
            local px, py, pz = spike.Transform:GetWorldPosition()
            spike._ss_idle_x, spike._ss_idle_y, spike._ss_idle_z = px, py, pz
        end
    end

    if IsTargetAlive(spike._ss_target) then
        local group = stalker._ss_spike_groups ~= nil and stalker._ss_spike_groups[spike._ss_target.GUID] or nil
        if group ~= nil then
            M.RecomputeFormation(group)
        end
    end
end

function M.SpawnOneTelegraphSpike(stalker, assignment, variation, restrict_fn, apply_tint_fn)
    local spike = SpawnPrefab("shadow_stalker_fossilspike2")
    if spike == nil then
        return nil
    end

    local scale = FeastBuffEffects.GetSpikeScale(stalker)
    spike._ss_spike_scale = scale
    spike.AnimState:SetScale(scale, scale)
    spike._damage_radius_padding_mult = scale

    if spike.components.combat ~= nil then
        spike.components.combat:SetDefaultDamage(FeastBuffEffects.GetSpikeDamage(stalker))
    end
    if spike.components.planardamage ~= nil then
        spike.components.planardamage:SetBaseDamage(FeastBuffEffects.GetSpikePlanarDamage(stalker))
    end

    if restrict_fn ~= nil then
        restrict_fn(spike, stalker)
    end
    if apply_tint_fn ~= nil then
        apply_tint_fn(spike)
    end

    M.RegisterSpike(stalker, spike, assignment)

    local sx, sy, sz = M.GetDesiredWorldPosition(stalker, spike)
    spike.Transform:SetPosition(sx, sy, sz)

    if spike.BeginShadowStalkerTelegraph ~= nil then
        spike:BeginShadowStalkerTelegraph({
            stalker = stalker,
            variation = variation,
            scale = scale,
            is_valid_enemy_fn = stalker._ss_spike_is_valid_enemy_fn,
        })
    end

    return spike
end

function M.SpawnCast(stalker, is_valid_enemy_fn, restrict_fn, apply_tint_fn)
    if stalker == nil or not TheWorld.ismastersim then
        return false
    end

    stalker._ss_spike_is_valid_enemy_fn = is_valid_enemy_fn
    local assignments = M.BuildCastAssignments(stalker, is_valid_enemy_fn)
    if #assignments <= 0 then
        return false
    end

    local vars = { 1, 2, 3, 4, 5, 6, 7 }
    local used = {}
    local queued = {}

    for _, assignment in ipairs(assignments) do
        local variation = table.remove(vars, math.random(#vars))
        table.insert(used, variation)
        if #used > 3 then
            table.insert(queued, table.remove(used, 1))
        end
        if #vars <= 0 then
            local swap = vars
            vars = queued
            queued = swap
        end

        M.SpawnOneTelegraphSpike(stalker, assignment, variation, restrict_fn, apply_tint_fn)
    end

    if stalker._ss_spike_update_task == nil then
        stalker._ss_spike_update_task = stalker:DoPeriodicTask(0, function()
            M.UpdateAll(stalker)
        end)
    end

    return true
end

function M.UpdateAll(stalker)
    if stalker._ss_active_spikes == nil then
        return
    end

    PruneSpikeList(stalker._ss_active_spikes)
    if #stalker._ss_active_spikes <= 0 then
        if stalker._ss_spike_update_task ~= nil then
            stalker._ss_spike_update_task:Cancel()
            stalker._ss_spike_update_task = nil
        end
        return
    end

    local is_valid_enemy_fn = stalker._ss_spike_is_valid_enemy_fn
    for _, spike in ipairs(stalker._ss_active_spikes) do
        if spike:IsValid() and spike.UpdateShadowStalkerTelegraph ~= nil then
            M.UpdateSpike(stalker, spike, is_valid_enemy_fn)
            spike:UpdateShadowStalkerTelegraph()
        end
    end
end

function M.ClearAll(stalker)
    if stalker == nil then
        return
    end

    if stalker._ss_spike_update_task ~= nil then
        stalker._ss_spike_update_task:Cancel()
        stalker._ss_spike_update_task = nil
    end

    local spikes = stalker._ss_active_spikes
    stalker._ss_active_spikes = nil
    stalker._ss_spike_groups = nil

    if spikes ~= nil then
        for _, spike in ipairs(spikes) do
            if spike ~= nil and spike:IsValid() then
                if spike.CancelShadowStalkerTelegraph ~= nil then
                    spike:CancelShadowStalkerTelegraph()
                end
                spike:Remove()
            end
        end
    end
end

return M
