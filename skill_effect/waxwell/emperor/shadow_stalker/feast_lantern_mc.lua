local FeastBuff = require("skill_effect/waxwell/emperor/shadow_stalker/feast_buff")
local ShadowLanternbearer = require("skill_effect/waxwell/puppeteer/shadow_lanternbearer/common")
local Profiles = require("skill_effect/waxwell/_shared/shadow_firefly/profiles")
local Spawn = require("skill_effect/waxwell/_shared/shadow_firefly/spawn")

local M = {}

local MC_SPAWN_DURATION = Profiles.FEAST_MC_SPAWN_DURATION

local function FindPlayerByUserID(userid)
    if userid == nil then
        return nil
    end

    for _, player in ipairs(AllPlayers) do
        if player ~= nil and player.userid == userid then
            return player
        end
    end

    return nil
end

local function GetSpellOwner(inst)
    if inst == nil then
        return nil
    end

    local owner = inst._shadow_stalker_spell_owner
    if owner ~= nil and owner:IsValid() then
        return owner
    end

    if inst._shadow_stalker_spell_owner_userid ~= nil then
        owner = FindPlayerByUserID(inst._shadow_stalker_spell_owner_userid)
        if owner ~= nil and owner:IsValid() then
            inst._shadow_stalker_spell_owner = owner
            return owner
        end
    end

    local follower = inst.components ~= nil and inst.components.follower or nil
    return follower ~= nil and follower:GetLeader() or nil
end

local function GetFireflyCount(owner)
    if owner ~= nil and ShadowLanternbearer.IsShadowLanternbearer2Active(owner) then
        return Profiles.FEAST_MC_COUNT_LV2
    end
    return Profiles.FEAST_MC_COUNT_LV1
end

local function CancelPendingFireflySpawns(inst)
    if inst._feast_lantern_firefly_tasks ~= nil then
        for _, task in ipairs(inst._feast_lantern_firefly_tasks) do
            if task ~= nil then
                task:Cancel()
            end
        end
        inst._feast_lantern_firefly_tasks = nil
    end
end

local function DestroyTrackedFireflies(inst, use_fade)
    CancelPendingFireflySpawns(inst)

    if inst._feast_lantern_fireflies == nil then
        inst._feast_lantern_fireflies = {}
        return
    end

    Spawn.ClearFireflies(inst._feast_lantern_fireflies, use_fade)
end

local function DespawnExistingFireflies(inst)
    DestroyTrackedFireflies(inst, false)
end

local function SpawnOneFirefly(inst, slot_index, slot_total)
    if not TheWorld.ismastersim or inst == nil or not inst:IsValid() then
        return
    end

    if FeastBuff.GetFeastBuffType(inst) ~= FeastBuff.TYPES.LANTERN then
        return
    end

    inst._feast_lantern_fireflies = inst._feast_lantern_fireflies or {}
    local positions = Spawn.GetExistingPositions(inst._feast_lantern_fireflies)
    local x, z = Spawn.FindFeastMcSpawnPoint(inst, positions, slot_index, slot_total)
    if x == nil then
        return
    end

    Spawn.SpawnShadowFirefly({
        profile = Profiles.PROFILE_FEAST_MC,
        host = inst,
        pos = Vector3(x, 0, z),
        track_list = inst._feast_lantern_fireflies,
    })
end

function M.ClearFireflies(inst)
    if inst == nil then
        return
    end

    DestroyTrackedFireflies(inst, false)
end

function M.IsLanternMcSessionActive(inst)
    return inst ~= nil and (inst._feast_lantern_mc_session or inst._feast_lantern_mc_ward)
end

function M.EndLanternFeastMindControl(inst)
    if inst == nil or not TheWorld.ismastersim then
        return
    end

    if not M.IsLanternMcSessionActive(inst) then
        CancelPendingFireflySpawns(inst)
        return
    end

    inst._feast_lantern_mc_session = nil
    CancelPendingFireflySpawns(inst)

    if inst.DeactivateLanternFeastWard ~= nil then
        inst:DeactivateLanternFeastWard()
    end

    M.ClearFireflies(inst)
end

function M.BeginLanternFeastMindControl(inst)
    if inst == nil or not TheWorld.ismastersim or inst._feast_lantern_mc_session then
        return
    end

    if FeastBuff.GetFeastBuffType(inst) ~= FeastBuff.TYPES.LANTERN then
        return
    end

    inst._feast_lantern_mc_session = true
    inst._feast_lantern_fireflies = inst._feast_lantern_fireflies or {}

    DespawnExistingFireflies(inst)

    local owner = GetSpellOwner(inst)
    local cap = GetFireflyCount(owner)
    inst._feast_lantern_firefly_tasks = {}

    if owner ~= nil
        and ShadowLanternbearer.IsShadowLanternbearer2Active(owner)
        and inst.ActivateLanternFeastWard ~= nil then
        inst:ActivateLanternFeastWard()
    end

    for i = 1, cap do
        local slot_index = i
        local task = inst:DoTaskInTime((i / cap) * MC_SPAWN_DURATION, function()
            if inst:IsValid()
                and inst._feast_lantern_mc_session
                and FeastBuff.GetFeastBuffType(inst) == FeastBuff.TYPES.LANTERN then
                SpawnOneFirefly(inst, slot_index, cap)
            end
        end)
        table.insert(inst._feast_lantern_firefly_tasks, task)
    end
end

function M.ClearAll(inst)
    M.EndLanternFeastMindControl(inst)
    M.ClearFireflies(inst)
end

function M.OnLanternBuffRemoved(inst)
    M.ClearAll(inst)
end

return M
