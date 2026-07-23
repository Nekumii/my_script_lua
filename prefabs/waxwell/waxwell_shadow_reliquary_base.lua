-- Visual-only winch base for the Shadow Reliquary skill. Drives boat_winch anims
-- manually (no winch/activatable/hammer components) — periodically pulls owned
-- sunken chests and the owner's Codex Umbra within suck radius, then unlocks
-- chests or recharges the journal. See AI Memory/skill_effect_emperor.txt.
local V = require("skill_effect/waxwell/emperor/shadow_reliquary/variables")
local persist_utils = require("skill_effect/waxwell/_shared/persist_utils")
local codex_recharge = require("skill_effect/waxwell/emperor/shadow_reliquary/codex_recharge")
local reliquary_fling = require("skill_effect/waxwell/emperor/shadow_reliquary/fling")

local assets =
{
    Asset("ANIM", "anim/boat_winch.zip"),
}

local prefabs =
{
    "sanity_raise",
    "shadow_despawn",
    "waxwell_shadow_sunken_chest_small",
    "waxwell_shadow_sunken_chest_medium",
    "waxwell_shadow_sunken_chest_large",
    "waxwell_shadow_sunken_chest",
    "globalmapicon",
    "globalmapiconnoproxy",
}

local WINCH_SOUNDS =
{
    drop_ground_pre = "hookline_2/common/boat_winch/drop_ground_pre",
    drop_ground_pst = "hookline_2/common/boat_winch/drop_ground_pst",
}

-- =============================================================================
-- Private helpers
-- =============================================================================

local shadow_reliquary_common

local function GetCommon()
    if shadow_reliquary_common == nil then
        shadow_reliquary_common = require("skill_effect/waxwell/emperor/shadow_reliquary/common")
    end
    return shadow_reliquary_common
end

local function ApplyVisualStyle(inst)
    local scale = V.SHADOW_RELIQUARY_VISUAL_SCALE or 1
    local tint = V.SHADOW_RELIQUARY_TINT or .2
    inst.Transform:SetScale(scale, scale, scale)
    inst.AnimState:SetMultColour(tint, tint, tint, 1)
    inst.AnimState:SetFinalOffset(V.SHADOW_RELIQUARY_WINCH_FINAL_OFFSET or 2)
end

local function NotifyRefresh(inst)
    local common = GetCommon()
    if common.PushSpellRefresh ~= nil then
        common.PushSpellRefresh(inst.owner)
    end
end

local function PlaySpawnIntro(inst)
    local common = GetCommon()
    if common.RevealAfterShadowIntro ~= nil then
        common.RevealAfterShadowIntro(inst)
    else
        if inst.SoundEmitter ~= nil then
            inst.SoundEmitter:PlaySound("maxwell_rework/shadow_pillar/pre")
        end
        local x, y, z = inst.Transform:GetWorldPosition()
        local fx = SpawnPrefab("sanity_raise")
        if fx ~= nil then
            fx.Transform:SetPosition(x, y, z)
        end
    end
end

-- Tiered land search from the base: distance rings only (see SHADOW_RELIQUARY_CHEST_TIER_CONFIG).
local CHEST_SPAWN_TIERS = V.SHADOW_RELIQUARY_CHEST_TIER_ORDER or { "small", "medium", "large" }

-- =============================================================================
-- Chest spawn scheduling (per-tier timers; small fires immediately on activate)
-- =============================================================================

local ScheduleNextChestSpawn

local function CancelSpawnTaskForTier(inst, tier)
    inst._spawn_tasks = inst._spawn_tasks or {}
    if inst._spawn_tasks[tier] ~= nil then
        inst._spawn_tasks[tier]:Cancel()
        inst._spawn_tasks[tier] = nil
    end
end

local function CancelSpawnTask(inst)
    for _, tier in ipairs(CHEST_SPAWN_TIERS) do
        CancelSpawnTaskForTier(inst, tier)
    end
end

local function SpawnChestForTier(inst, tier)
    if inst._deactivating then
        return false
    end

    local bx, _, bz = inst.Transform:GetWorldPosition()
    local common = GetCommon()
    local pos = common.FindChestSpawnPointForTier ~= nil
        and common.FindChestSpawnPointForTier(bx, bz, tier)
        or nil
    if pos == nil then
        return false
    end

    if common.SpawnShadowReliquaryChest ~= nil then
        local chest = common.SpawnShadowReliquaryChest(inst.owner, pos.x, pos.z, inst._owner_userid, tier)
        return chest ~= nil
    end
    return false
end

local function DoScheduledSpawnForTier(inst, tier)
    inst._spawn_tasks = inst._spawn_tasks or {}
    inst._spawn_tasks[tier] = nil
    SpawnChestForTier(inst, tier)
    local cfg = V.SHADOW_RELIQUARY_CHEST_TIER_CONFIG[tier]
    ScheduleNextChestSpawn(inst, tier, cfg ~= nil and cfg.spawn_period or V.SHADOW_RELIQUARY_CHEST_SPAWN_PERIOD)
end

ScheduleNextChestSpawn = function(inst, tier, delay)
    CancelSpawnTaskForTier(inst, tier)
    if inst._deactivating then
        return
    end
    delay = math.max(0, delay or 0)
    inst._next_spawn_attime = inst._next_spawn_attime or {}
    inst._next_spawn_attime[tier] = GetTime() + delay
    inst._spawn_tasks = inst._spawn_tasks or {}
    inst._spawn_tasks[tier] = inst:DoTaskInTime(delay, function()
        DoScheduledSpawnForTier(inst, tier)
    end)
end

local function StartAllChestSpawnTimers(inst)
    for _, tier in ipairs(CHEST_SPAWN_TIERS) do
        local cfg = V.SHADOW_RELIQUARY_CHEST_TIER_CONFIG[tier]
        if cfg ~= nil then
            ScheduleNextChestSpawn(inst, tier, cfg.spawn_period)
        end
    end
end

local function ResumeChestSpawnTimers(inst, remaining_by_tier)
    for _, tier in ipairs(CHEST_SPAWN_TIERS) do
        local remaining = remaining_by_tier ~= nil and remaining_by_tier[tier] or nil
        if remaining == nil then
            local cfg = V.SHADOW_RELIQUARY_CHEST_TIER_CONFIG[tier]
            remaining = cfg ~= nil and cfg.spawn_period or 0
        end
        ScheduleNextChestSpawn(inst, tier, remaining)
    end
end

local function EnsureBaseMapIcons(inst)
    local common = GetCommon()
    if common.EnsureShadowReliquaryMapIcons ~= nil then
        common.EnsureShadowReliquaryMapIcons(inst, inst._owner_userid, "ssc_map_winch.png")
    end
end

local function ClearBaseMapIcons(inst)
    local common = GetCommon()
    if common.ClearShadowReliquaryMapIcons ~= nil then
        common.ClearShadowReliquaryMapIcons(inst)
    end
end

-- =============================================================================
-- Unlock sequence (raised -> drop_ground_* -> raised)
-- Serial: one chest at a time; _unlocking stays true until winch fully raised.
-- =============================================================================

local StartUnlock
local StartCodexRecharge
local ScanForWork

local function CancelScanTask(inst)
    if inst._scan_task ~= nil then
        inst._scan_task:Cancel()
        inst._scan_task = nil
    end
end

-- True only when this base and the chest share a real owner userid. nil==nil
-- must never unlock (would let orphan chests / other Maxwells cross-unlock).
local function IsChestOnGround(chest)
    if chest == nil or not chest:IsValid() or chest:IsInLimbo() then
        return false
    end
    local inv = chest.components ~= nil and chest.components.inventoryitem or nil
    return inv == nil or not inv:IsHeld()
end

local function OwnsChest(inst, chest)
    local uid = inst._owner_userid
    return uid ~= nil
        and chest ~= nil
        and chest:IsValid()
        and chest._owner_userid == uid
        and not chest._unlocking
        and not chest._smashing
        and not chest:HasTag("waxwell_ssc_rift_busy")
        and IsChestOnGround(chest)
end

local function CancelChestSuckTask(chest)
    if chest ~= nil and chest._reliquary_suck_task ~= nil then
        chest._reliquary_suck_task:Cancel()
        chest._reliquary_suck_task = nil
    end
end

local function CancelRiftTasksOnChest(chest)
    if chest == nil then
        return
    end
    if chest._umbral_rift_static_emerge_task ~= nil then
        chest._umbral_rift_static_emerge_task:Cancel()
        chest._umbral_rift_static_emerge_task = nil
    end
    if chest._umbral_rift_transfer_task ~= nil then
        chest._umbral_rift_transfer_task:Cancel()
        chest._umbral_rift_transfer_task = nil
    end
end

local function MoveEntityToPoint(ent, x, z)
    if ent == nil or not ent:IsValid() then
        return
    end
    if ent.Physics ~= nil then
        ent.Physics:Stop()
        ent.Physics:Teleport(x, 0, z)
    else
        ent.Transform:SetPosition(x, 0, z)
    end
end

local function MoveChestToPoint(chest, x, z)
    MoveEntityToPoint(chest, x, z)
end

local function SmoothSuckToBase(inst, target, oncomplete)
    if inst == nil or not inst:IsValid() or target == nil or not target:IsValid() then
        return
    end

    local bx, _, bz = inst.Transform:GetWorldPosition()
    local cx, _, cz = target.Transform:GetWorldPosition()
    local dx, dz = bx - cx, bz - cz
    if dx * dx + dz * dz < .01 then
        MoveEntityToPoint(target, bx, bz)
        if oncomplete ~= nil then
            oncomplete()
        end
        return
    end

    codex_recharge.CancelCodexSuckTask(target)
    CancelChestSuckTask(target)
    CancelRiftTasksOnChest(target)
    codex_recharge.CancelRiftTasksOnCodex(target)

    local suck_time = V.SHADOW_RELIQUARY_SUCK_TIME or (10 * FRAMES)
    local startx, startz = cx, cz
    local elapsed = 0

    target._reliquary_suck_task = target:DoPeriodicTask(FRAMES, function(item)
        if item == nil or not item:IsValid() or inst == nil or not inst:IsValid() then
            if item ~= nil then
                CancelChestSuckTask(item)
                codex_recharge.CancelCodexSuckTask(item)
            end
            return
        end

        elapsed = elapsed + FRAMES
        local t = math.min(1, suck_time > 0 and (elapsed / suck_time) or 1)
        local nx = Lerp(startx, bx, t)
        local nz = Lerp(startz, bz, t)
        MoveEntityToPoint(item, nx, nz)

        if t >= 1 then
            CancelChestSuckTask(item)
            codex_recharge.CancelCodexSuckTask(item)
            if oncomplete ~= nil then
                oncomplete()
            end
        end
    end)
end

local function SmoothSuckChestToBase(inst, chest, oncomplete)
    SmoothSuckToBase(inst, chest, oncomplete)
end

local function FinishUnlock(inst)
    inst.AnimState:PlayAnimation("drop_ground_pst")
    if inst.SoundEmitter ~= nil then
        inst.SoundEmitter:PlaySound(WINCH_SOUNDS.drop_ground_pst)
    end

    local function OnRaised()
        inst:RemoveEventCallback("animover", OnRaised)
        if inst == nil or not inst:IsValid() then
            return
        end
        inst.AnimState:PlayAnimation("idle", true)
        -- Full winch cycle done (lower + smash + raise). Only now free the
        -- unlock slot so the next owned chest in range can begin.
        inst._unlocking = false
        inst._docked_codex = nil
        NotifyRefresh(inst)
        ScanForWork(inst)
    end
    inst:ListenForEvent("animover", OnRaised)
end

local function BeginLowering(inst, onlowered)
    inst.AnimState:PlayAnimation("drop_ground_pre")
    if inst.SoundEmitter ~= nil then
        inst.SoundEmitter:PlaySound(WINCH_SOUNDS.drop_ground_pre)
    end

    local function OnLowered()
        inst:RemoveEventCallback("animover", OnLowered)
        if inst == nil or not inst:IsValid() then
            return
        end
        inst.AnimState:PlayAnimation("drop_ground_loop", true)

        if onlowered ~= nil then
            onlowered()
        else
            FinishUnlock(inst)
        end
    end
    inst:ListenForEvent("animover", OnLowered)
end

local function ReleaseCodexBesideBase(inst, journal)
    if journal == nil or not journal:IsValid() then
        return
    end

    codex_recharge.EnsureCodexFlingReady(journal)

    local bx, by, bz = inst.Transform:GetWorldPosition()
    reliquary_fling.FlingEntity(
        journal,
        bx, by, bz,
        V.SHADOW_RELIQUARY_CODEX_RELEASE_SPEED_MIN,
        V.SHADOW_RELIQUARY_CODEX_RELEASE_SPEED_MAX,
        V.SHADOW_RELIQUARY_CODEX_RELEASE_Y_MIN,
        V.SHADOW_RELIQUARY_CODEX_RELEASE_Y_MAX,
        0
    )
end

local function FinishCodexRecharge(inst, journal)
    if journal ~= nil and journal:IsValid() then
        codex_recharge.UndockCodexVisual(journal)
        ReleaseCodexBesideBase(inst, journal)
    end
    inst._docked_codex = nil
    FinishUnlock(inst)
end

StartUnlock = function(inst, chest)
    -- Serial unlock: refuse while another sequence is mid-anim, and refuse
    -- chests that belong to a different Maxwell (or have no owner userid).
    if inst._unlocking or inst._deactivating or not OwnsChest(inst, chest) then
        return
    end

    inst._unlocking = true
    if chest.MarkUnlocking ~= nil then
        chest:MarkUnlocking()
    end

    NotifyRefresh(inst)
    SmoothSuckChestToBase(inst, chest, function()
        if inst ~= nil and inst:IsValid() and chest ~= nil and chest:IsValid() then
            BeginLowering(inst, function()
                if chest ~= nil and chest:IsValid() and chest.BeginSmash ~= nil then
                    chest:BeginSmash(function()
                        if inst ~= nil and inst:IsValid() then
                            FinishUnlock(inst)
                        end
                    end)
                elseif inst ~= nil and inst:IsValid() then
                    FinishUnlock(inst)
                end
            end)
        elseif inst ~= nil and inst:IsValid() then
            inst._unlocking = false
            NotifyRefresh(inst)
            ScanForWork(inst)
        end
    end)
end

StartCodexRecharge = function(inst, journal)
    if inst._unlocking or inst._deactivating or not codex_recharge.IsEligibleCodex(inst, journal) then
        return
    end

    inst._unlocking = true
    inst._docked_codex = journal
    codex_recharge.MarkCodexUnlocking(journal)
    NotifyRefresh(inst)

    SmoothSuckToBase(inst, journal, function()
        if inst ~= nil and inst:IsValid() and journal ~= nil and journal:IsValid() then
            BeginLowering(inst, function()
                codex_recharge.BeginCodexRepair(inst, journal, function(complete)
                    if inst ~= nil and inst:IsValid() then
                        if complete then
                            FinishCodexRecharge(inst, journal)
                        else
                            inst._unlocking = false
                            inst._docked_codex = nil
                            codex_recharge.UndockCodexVisual(journal, true)
                            ReleaseCodexBesideBase(inst, journal)
                            NotifyRefresh(inst)
                            if inst.AnimState ~= nil then
                                inst.AnimState:PlayAnimation("idle", true)
                            end
                            ScanForWork(inst)
                        end
                    end
                end)
            end)
        elseif inst ~= nil and inst:IsValid() then
            inst._unlocking = false
            inst._docked_codex = nil
            NotifyRefresh(inst)
            ScanForWork(inst)
        end
    end)
end

local function TouchEnteredRadius(inst, ent, in_radius)
    inst._entered_radius_at = inst._entered_radius_at or {}
    if in_radius then
        if inst._entered_radius_at[ent] == nil then
            inst._entered_radius_at[ent] = GetTime()
        end
    else
        inst._entered_radius_at[ent] = nil
    end
end

local function PruneEnteredRadius(inst, seen)
    if inst._entered_radius_at == nil then
        return
    end
    for ent in pairs(inst._entered_radius_at) do
        if seen[ent] == nil or ent == nil or not ent:IsValid() then
            inst._entered_radius_at[ent] = nil
        end
    end
end

ScanForWork = function(inst)
    if inst._unlocking or inst._deactivating or inst._owner_userid == nil then
        return
    end

    local x, _, z = inst.Transform:GetWorldPosition()
    local radius = V.SHADOW_RELIQUARY_SUCK_RADIUS or 3
    local seen = {}
    local candidates = {}

    local chests = TheSim:FindEntities(x, 0, z, radius, { "waxwell_shadow_sunken_chest" })
    local common = GetCommon()
    for _, ent in ipairs(chests) do
        seen[ent] = true
        if ent._owner_userid ~= nil
            and ent._owner_userid ~= inst._owner_userid
            and IsChestOnGround(ent)
            and common.BounceChestFromWinch ~= nil then
            common.BounceChestFromWinch(inst, ent)
        end
        local eligible = OwnsChest(inst, ent)
        TouchEnteredRadius(inst, ent, eligible)
        if eligible then
            table.insert(candidates, { ent = ent, kind = 1 })
        end
    end

    local codex_prefab = V.SHADOW_RELIQUARY_CODEX_PREFAB or "waxwelljournal"
    local ents = TheSim:FindEntities(x, 0, z, radius)
    for _, ent in ipairs(ents) do
        if ent.prefab == codex_prefab then
            seen[ent] = true
            local eligible = codex_recharge.IsEligibleCodex(inst, ent)
            TouchEnteredRadius(inst, ent, eligible)
            if eligible then
                table.insert(candidates, { ent = ent, kind = 2 })
            end
        end
    end

    PruneEnteredRadius(inst, seen)

    if #candidates == 0 then
        return
    end

    table.sort(candidates, function(a, b)
        local ta = inst._entered_radius_at[a.ent] or math.huge
        local tb = inst._entered_radius_at[b.ent] or math.huge
        if ta ~= tb then
            return ta < tb
        end
        return a.kind < b.kind
    end)

    local best = candidates[1]
    if best.kind == 1 then
        StartUnlock(inst, best.ent)
    else
        StartCodexRecharge(inst, best.ent)
    end
end

local function StartScanTask(inst)
    CancelScanTask(inst)
    inst._scan_task = inst:DoPeriodicTask(V.SHADOW_RELIQUARY_SCAN_PERIOD, ScanForWork)
end

-- =============================================================================
-- Deactivate / cleanup
-- =============================================================================

local function KillOwnedChests(inst)
    if inst._owner_userid == nil then
        return
    end
    for _, ent in pairs(Ents) do
        if ent ~= nil
            and ent:IsValid()
            and ent:HasTag("waxwell_shadow_sunken_chest")
            and ent._owner_userid == inst._owner_userid then
            local ex, ey, ez = ent.Transform:GetWorldPosition()
            local fx = SpawnPrefab("shadow_despawn")
            if fx ~= nil then
                fx.Transform:SetPosition(ex, ey, ez)
            end
            ent:Remove()
        end
    end
end

local function NotifyOwnerEnded(inst)
    if inst._cd_notified then
        return
    end
    inst._cd_notified = true
    local common = GetCommon()
    if common.OnShadowReliquaryEnded ~= nil then
        common.OnShadowReliquaryEnded(inst.owner)
    end
end

local function ReleaseDockedCodex(inst)
    local journal = inst._docked_codex
    if journal == nil or not journal:IsValid() then
        return
    end
    codex_recharge.StopRepairTask(journal)
    codex_recharge.UndockCodexVisual(journal, true)
    ReleaseCodexBesideBase(inst, journal)
    inst._docked_codex = nil
end

local function RequestDeactivate(inst, reason)
    if inst._deactivating then
        return
    end

    inst._deactivating = true
    inst._unlocking = false
    ReleaseDockedCodex(inst)
    ClearBaseMapIcons(inst)
    CancelSpawnTask(inst)
    CancelScanTask(inst)
    KillOwnedChests(inst)

    local x, y, z = inst.Transform:GetWorldPosition()
    local fx = SpawnPrefab("shadow_despawn")
    if fx ~= nil then
        fx.Transform:SetPosition(x, y, z)
    end

    inst.persists = false
    NotifyRefresh(inst)

    inst:DoTaskInTime(V.SHADOW_RELIQUARY_DEACTIVATE_DELAY or 1, function()
        if inst ~= nil and inst:IsValid() then
            inst:Remove()
        end
    end)
end

-- =============================================================================
-- Public API on instance
-- =============================================================================

local function Activate(inst, owner)
    inst.owner = owner
    inst._owner_userid = owner ~= nil and owner.userid or nil
    inst.persists = true

    local common = GetCommon()
    if common.RevealAfterShadowIntro ~= nil then
        common.RevealAfterShadowIntro(inst, function(base)
            if base._deactivating then
                return
            end
            EnsureBaseMapIcons(base)
            StartScanTask(base)
            StartAllChestSpawnTimers(base)
        end)
    else
        PlaySpawnIntro(inst)
        EnsureBaseMapIcons(inst)
        StartScanTask(inst)
        StartAllChestSpawnTimers(inst)
    end
end

local function ForceSpawnChestTier(inst, tier)
    return SpawnChestForTier(inst, tier)
end

local function RebindOwner(inst, owner)
    inst.owner = owner
    if owner ~= nil then
        owner._waxwell_shadow_reliquary_base = inst
        inst._owner_userid = owner.userid
        EnsureBaseMapIcons(inst)
    end
end

local function IsUnlocking(inst)
    return inst._unlocking == true
end

-- =============================================================================
-- Persist
-- =============================================================================

local function OnSave(inst, data)
    data._owner_userid = inst._owner_userid
    if inst._next_spawn_attime ~= nil then
        for _, tier in ipairs(CHEST_SPAWN_TIERS) do
            local endtime = inst._next_spawn_attime[tier]
            if endtime ~= nil then
                persist_utils.SaveRemainingTime(data, "_next_spawn_remaining_" .. tier, endtime)
            end
        end
    end
end

local function OnLoad(inst, data)
    if data == nil then
        return
    end

    inst._owner_userid = data._owner_userid
    inst.persists = true

    EnsureBaseMapIcons(inst)
    inst:DoTaskInTime(0, function()
        if inst ~= nil and inst:IsValid() and not inst._deactivating then
            StartScanTask(inst)
        end
    end)
    local remaining_by_tier = {}
    for _, tier in ipairs(CHEST_SPAWN_TIERS) do
        remaining_by_tier[tier] = persist_utils.GetSavedRemainingTime(data, "_next_spawn_remaining_" .. tier)
    end
    -- Pre-tier saves: single timer mapped to small wave.
    if data._next_spawn_remaining ~= nil then
        local legacy = persist_utils.GetSavedRemainingTime(data, "_next_spawn_remaining")
        if legacy > 0 and (remaining_by_tier.small or 0) <= 0 then
            remaining_by_tier.small = legacy
        end
    end
    ResumeChestSpawnTimers(inst, remaining_by_tier)
end

-- =============================================================================
-- Prefab
-- =============================================================================

local function OnRemove(inst)
    CancelSpawnTask(inst)
    CancelScanTask(inst)
    ClearBaseMapIcons(inst)

    local owner = inst.owner
    if owner ~= nil and owner._waxwell_shadow_reliquary_base == inst then
        owner._waxwell_shadow_reliquary_base = nil
    end

    NotifyOwnerEnded(inst)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddMiniMapEntity()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("boat_winch")
    inst.AnimState:SetBuild("boat_winch")
    inst.AnimState:PlayAnimation("idle", true)

    ApplyVisualStyle(inst)

    -- Custom winch icon in waxwell_minimap_icon atlas (see modmain AddMinimapAtlas).
    inst.MiniMapEntity:SetIcon("ssc_map_winch.png")
    inst.MiniMapEntity:SetEnabled(false)

    inst:AddTag("NOCLICK")
    inst:AddTag("NOBLOCK")
    inst:AddTag("waxwell_shadow_reliquary_base")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = true
    inst.owner = nil
    inst._owner_userid = nil
    inst._unlocking = false
    inst._deactivating = false
    inst._spawn_tasks = {}
    inst._scan_task = nil
    inst._next_spawn_attime = {}
    inst._entered_radius_at = {}
    inst._docked_codex = nil
    inst._cd_notified = false

    inst.Activate = Activate
    inst.RequestDeactivate = RequestDeactivate
    inst.RebindOwner = RebindOwner
    inst.IsUnlocking = IsUnlocking
    inst.TryUnlockChest = function(inst, chest)
        StartUnlock(inst, chest)
    end
    inst.TryRechargeCodex = function(inst, journal)
        StartCodexRecharge(inst, journal)
    end
    inst.ForceSpawnChestTier = function(base, tier)
        return ForceSpawnChestTier(base, tier)
    end

    inst.OnSave = OnSave
    inst.OnLoad = OnLoad
    inst:ListenForEvent("onremove", OnRemove)

    return inst
end

return Prefab("waxwell_shadow_reliquary_base", fn, assets, prefabs)
