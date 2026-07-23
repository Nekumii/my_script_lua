local V = require("skill_effect/waxwell/emperor/shadow_reliquary/variables")
local codex_recharge = require("skill_effect/waxwell/emperor/shadow_reliquary/codex_recharge")
local mapicons = require("skill_effect/waxwell/emperor/shadow_reliquary/mapicons")
local spell_utils = require("skill_effect/waxwell/_shared/codex_spell_utils")
local SpellIcon = require("skill_effect/waxwell/_shared/codex_spell_icon")
local ReticuleUtils = require("reticule/utils")
local debug = require("debug/init")
local ModCompat = require("mod_compatibility")

local CastSpellBookFromInventory = spell_utils.CastSpellBookFromInventory
local TriggerInstantSpellbookCast = CastSpellBookFromInventory
local StartAOETargeting = spell_utils.StartAOETargeting

-- =============================================================================
-- Private helpers
-- =============================================================================

local function PushSpellRefresh(owner)
    if owner ~= nil and TheWorld ~= nil then
        TheWorld:PushEvent("waxwell_emperor_spell_refresh", { owner = owner })
    end
end

local function ResolveSpellOwner(inst, doer, fallback)
    local owner = doer
    if (owner == nil or owner.components == nil) and inst ~= nil and inst.components ~= nil and inst.components.inventoryitem ~= nil then
        owner = inst.components.inventoryitem:GetGrandOwner()
    end
    return owner or fallback or ThePlayer
end

local function SpellCost(pct)
    if debug.ShouldIgnoreCodexUmbraDurability() then
        return 0
    end
    return pct * TUNING.LARGE_FUEL * -4
end

local function HasEnoughCodexFuel(inst, costpct)
    if debug.ShouldIgnoreCodexUmbraDurability() then
        return true
    end
    local fueled = inst ~= nil and inst.components ~= nil and inst.components.fueled or nil
    local cost = SpellCost(costpct)
    return fueled ~= nil
        and fueled.currentfuel ~= nil
        and cost ~= nil
        and fueled.currentfuel >= math.abs(cost) - .001
end

-- Flat cost, never touched by Dark Scholar / Measured Invocation by design.
local function GetShadowReliquarySanityCost(doer)
    return V.SHADOW_RELIQUARY_SANITY_COST
end

-- =============================================================================
-- Skill / base state
-- =============================================================================

local function IsShadowReliquarySkillActive(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_shadow_reliquary"))
            or inst:HasTag(V.SHADOW_RELIQUARY_ACTIVE_TAG)
        )
end

local function GetShadowReliquaryBase(owner)
    if owner == nil then
        return nil
    end

    local base = owner._waxwell_shadow_reliquary_base
    if base ~= nil and base:IsValid() then
        return base
    end

    if owner.userid ~= nil then
        for _, ent in pairs(Ents) do
            if ent ~= nil
                and ent:IsValid()
                and ent.prefab == "waxwell_shadow_reliquary_base"
                and ent._owner_userid == owner.userid then
                owner._waxwell_shadow_reliquary_base = ent
                if ent.RebindOwner ~= nil then
                    ent:RebindOwner(owner)
                else
                    ent.owner = owner
                end
                return ent
            end
        end
    end

    owner._waxwell_shadow_reliquary_base = nil
    return nil
end

-- nil | "active" | "unlocking" | "deactivating"
local function GetShadowReliquarySpellState(owner)
    if owner == nil then
        return nil
    end
    local base = GetShadowReliquaryBase(owner)
    if base == nil then
        return nil
    end
    if base._deactivating then
        return "deactivating"
    end
    if base._unlocking then
        return "unlocking"
    end
    return "active"
end

local function IsShadowReliquaryOnCooldown(doer)
    return spell_utils.IsSpellOnCooldown(doer, V.SHADOW_RELIQUARY_COOLDOWN_ID)
end

local function GetShadowReliquaryCooldownPercent(doer)
    return spell_utils.GetSpellCooldownPercent(doer, V.SHADOW_RELIQUARY_COOLDOWN_ID)
end

-- =============================================================================
-- Placement validation
-- =============================================================================

-- Named entities that block placement even when they lack a shared tag
-- (mirrors fissure_eruption/common.lua's BLOCKER_PREFABS, but SR only needs
-- to protect a single point + small clearance around the winch, not a disc).
local BLOCKER_PREFABS =
{
    cave_entrance = true,
    cave_entrance_open = true,
    cave_entrance_ruins = true,
    oasislake = true,
    grotto_pool_big = true,
    grotto_pool_small = true,
    wormhole = true,
    wormhole_limited = true,
    antlion_sinkhole = true,
    eyeofterror_sinkhole = true,
    multiplayer_portal = true,
    waxwell_fissure_eruption_sinkhole = true,
    waxwell_shadow_reliquary_base = true,
}

local TROPICAL_BLOCKER_PREFABS =
{
    tidalpool = true,
    tidalpoolnew = true,
    quagmire_pond_salt = true,
    lavapondbig = true,
    lavapondbig1 = true,
    tigersharkpool = true,
    lake = true,
}

-- Trees / rocks / structures / ponds / lava are all caught via shared tags.
local BLOCKER_ONEOF_TAGS = { "structure", "tree", "boulder", "pond", "lava" }
local BLOCKER_CANT_TAGS = { "INLIMBO", "FX", "DECOR", "playerghost" }

local function ResolvePoint(pos)
    if pos == nil then
        return nil
    end
    local x, y, z = pos.x, pos.y, pos.z
    if x == nil and pos.Get ~= nil then
        x, y, z = pos:Get()
    end
    if x == nil or z == nil then
        return nil
    end
    return Vector3(x, y or 0, z)
end

local function IsShadowReliquaryLandPoint(pt)
    if pt == nil or TheWorld == nil or TheWorld.Map == nil then
        return false
    end
    local map = TheWorld.Map
    local x, z = pt.x, pt.z
    if map.IsLandTileAtPoint ~= nil and not map:IsLandTileAtPoint(x, 0, z) then
        return false
    end
    if map:IsOceanAtPoint(x, 0, z, false) then
        return false
    end
    if not map:IsPassableAtPoint(x, 0, z, false, true) then
        return false
    end
    if map.IsGroundTargetBlocked ~= nil and map:IsGroundTargetBlocked(pt) then
        return false
    end
    return true
end

local function IsBlockerEntity(ent, center, radius)
    if ent == nil or not ent:IsValid() then
        return false
    end
    local prefab = ent.prefab
    local ispointblocker = prefab ~= nil
        and (BLOCKER_PREFABS[prefab] or (ModCompat.IsTropicalCompatEnabled() and TROPICAL_BLOCKER_PREFABS[prefab]))
    if not ispointblocker
        and not ent:HasTag("structure")
        and not ent:HasTag("tree")
        and not ent:HasTag("boulder")
        and not ent:HasTag("pond")
        and not ent:HasTag("lava") then
        return false
    end
    local pad = ent.Physics ~= nil and ent:GetPhysicsRadius(0) or 0
    return ent:GetDistanceSqToPoint(center.x, 0, center.z) <= (radius + pad) * (radius + pad)
end

local function HasPlacementBlockers(pt, radius)
    if pt == nil then
        return true
    end
    local search = radius + (V.SHADOW_RELIQUARY_BLOCKER_PAD or 1.5)
    local ents = TheSim:FindEntities(pt.x, 0, pt.z, search, nil, BLOCKER_CANT_TAGS, BLOCKER_ONEOF_TAGS)
    for _, ent in ipairs(ents) do
        if IsBlockerEntity(ent, pt, radius) then
            return true
        end
    end
    -- Prefab-only blockers (caves, wormholes, oasislake, ...) may lack these tags.
    local ents2 = TheSim:FindEntities(pt.x, 0, pt.z, search, nil, BLOCKER_CANT_TAGS)
    for _, ent in ipairs(ents2) do
        if IsBlockerEntity(ent, pt, radius) then
            return true
        end
    end
    return false
end

local function IsShadowReliquaryWithinCastRange(doer, pt)
    if doer == nil or not doer:IsValid() or doer.Transform == nil or pt == nil then
        return false
    end
    local x, _, z = doer.Transform:GetWorldPosition()
    return ReticuleUtils.IsPointWithinCastRange(x, z, pt, V.SHADOW_RELIQUARY_CAST_RANGE)
end

local function IsShadowReliquaryChestSpawnPointValid(pt)
    pt = ResolvePoint(pt)
    if pt == nil then
        return false
    end
    if not IsShadowReliquaryLandPoint(pt) then
        return false
    end
    -- Same clearance as placing the winch: no ponds, lava, trees, rocks,
    -- structures, caves, wormholes, or other named blockers under the chest.
    if HasPlacementBlockers(pt, V.SHADOW_RELIQUARY_PLACEMENT_CLEARANCE or 1.25) then
        return false
    end
    local min_sep = V.SHADOW_RELIQUARY_CHEST_SPAWN_MIN_SEP or 1
    local min_sep_sq = min_sep * min_sep
    for _, chest in ipairs(TheSim:FindEntities(pt.x, 0, pt.z, min_sep, { "waxwell_shadow_sunken_chest" })) do
        if chest ~= nil and chest:IsValid() then
            local cx, _, cz = chest.Transform:GetWorldPosition()
            local dx, dz = pt.x - cx, pt.z - cz
            if dx * dx + dz * dz < min_sep_sq then
                return false
            end
        end
    end
    return true
end

local function IsShadowReliquaryPlacementValid(pt, doer, check_cast_range)
    pt = ResolvePoint(pt)
    if pt == nil then
        return false
    end
    if check_cast_range ~= false and not IsShadowReliquaryWithinCastRange(doer, pt) then
        return false
    end
    return IsShadowReliquaryChestSpawnPointValid(pt)
end

-- Shared shadow pillar intro FX (sanity_raise + pre sound) at an entity's position.
local function PlayShadowReliquaryGroundIntro(inst)
    if inst == nil or not inst:IsValid() then
        return
    end
    if inst.SoundEmitter ~= nil then
        inst.SoundEmitter:PlaySound("maxwell_rework/shadow_pillar/pre")
    end
    local x, y, z = inst.Transform:GetWorldPosition()
    local fx = SpawnPrefab("sanity_raise")
    if fx ~= nil then
        fx.Transform:SetPosition(x, y, z)
    end
end

-- Hide, play shadow intro, then reveal after the pillar FX reaches the ground.
local function RevealAfterShadowIntro(inst, onreveal)
    if inst == nil or not inst:IsValid() then
        return
    end
    inst:Hide()
    PlayShadowReliquaryGroundIntro(inst)
    inst:DoTaskInTime(V.SHADOW_RELIQUARY_SHADOW_INTRO_DELAY or (15 * FRAMES), function()
        if inst ~= nil and inst:IsValid() then
            inst:Show()
            if onreveal ~= nil then
                onreveal(inst)
            end
        end
    end)
end

-- =============================================================================
-- Tiered chest spawn (distance rings from base)
-- =============================================================================

local function DistSqFromBase(pt, base_x, base_z)
    local dx, dz = pt.x - base_x, pt.z - base_z
    return dx * dx + dz * dz
end

local function MatchesChestTierSpawnPoint(pt, tier_key, base_x, base_z, opts)
    local tier = V.SHADOW_RELIQUARY_CHEST_TIER_CONFIG[tier_key]
    if tier == nil or pt == nil then
        return false
    end

    local allow_beyond_max = opts ~= nil and opts.allow_beyond_max == true
    local dist_sq = DistSqFromBase(pt, base_x, base_z)
    local min_dist = tier.min_dist or 0
    if dist_sq < min_dist * min_dist then
        return false
    end

    local max_dist = tier.max_dist
    if not allow_beyond_max and max_dist ~= nil and dist_sq > max_dist * max_dist then
        return false
    end
    return true
end

local function GetChestTierConfig(tier_key)
    return V.SHADOW_RELIQUARY_CHEST_TIER_CONFIG[tier_key]
        or V.SHADOW_RELIQUARY_CHEST_TIER_CONFIG.medium
end

local function GetTierPreferredMaxDist(tier)
    if tier.max_dist ~= nil then
        return tier.max_dist
    end
    local band = V.SHADOW_RELIQUARY_CHEST_LARGE_SPAWN_PREFERRED_BAND or 200
    return (tier.min_dist or 0) + band
end

local function GetTierExpandLimit(tier)
    if tier.max_dist ~= nil then
        return GetTierPreferredMaxDist(tier) + (V.SHADOW_RELIQUARY_CHEST_SPAWN_MAX_BEYOND or 250)
    end
    return V.SHADOW_RELIQUARY_CHEST_SPAWN_ABSOLUTE_MAX or 1500
end

local function SamplePolarSpawnPoint(base_x, base_z, dist)
    local theta = math.random() * TWOPI
    return { x = base_x + math.cos(theta) * dist, z = base_z + math.sin(theta) * dist }
end

local function TryPolarSpawnCandidates(base_x, base_z, tier_key, dist_min, dist_max, attempts, allow_beyond_max)
    if dist_max < dist_min then
        dist_max = dist_min
    end

    for _ = 1, attempts do
        local dist = dist_min + math.random() * (dist_max - dist_min)
        local pt = SamplePolarSpawnPoint(base_x, base_z, dist)
        if IsShadowReliquaryChestSpawnPointValid(pt)
            and MatchesChestTierSpawnPoint(pt, tier_key, base_x, base_z, { allow_beyond_max = allow_beyond_max }) then
            return pt
        end
    end

    return nil
end

local function TryRandomLandSpawnCandidates(base_x, base_z, tier_key, dist_min, dist_max, attempts, allow_beyond_max)
    local map = TheWorld ~= nil and TheWorld.Map or nil
    if map == nil or map.FindRandomPointOnLand == nil then
        return nil
    end

    for _ = 1, attempts do
        local pt = map:FindRandomPointOnLand(1)
        if pt ~= nil then
            local dist_sq = DistSqFromBase(pt, base_x, base_z)
            if dist_sq >= dist_min * dist_min and dist_sq <= dist_max * dist_max
                and IsShadowReliquaryChestSpawnPointValid(pt)
                and MatchesChestTierSpawnPoint(pt, tier_key, base_x, base_z, { allow_beyond_max = allow_beyond_max }) then
                return pt
            end
        end
    end

    return nil
end

local function FindChestSpawnPointForTier(base_x, base_z, tier_key)
    local tier = GetChestTierConfig(tier_key)
    if tier == nil then
        return nil
    end

    local min_dist = tier.min_dist or 0
    local pref_max = GetTierPreferredMaxDist(tier)
    local expand_limit = GetTierExpandLimit(tier)
    local preferred_attempts = V.SHADOW_RELIQUARY_CHEST_SPAWN_PREFERRED_ATTEMPTS
        or V.SHADOW_RELIQUARY_CHEST_SPAWN_ATTEMPTS
        or 64
    local ring_attempts = V.SHADOW_RELIQUARY_CHEST_SPAWN_RING_ATTEMPTS or 16
    local ring_step = V.SHADOW_RELIQUARY_CHEST_SPAWN_EXPAND_STEP or 25
    local polar_attempts = math.floor(preferred_attempts * .5)
    local land_attempts = preferred_attempts - polar_attempts

    local pt = TryPolarSpawnCandidates(
        base_x, base_z, tier_key,
        min_dist, pref_max, polar_attempts, false)
    if pt == nil then
        pt = TryRandomLandSpawnCandidates(
            base_x, base_z, tier_key,
            min_dist, pref_max, land_attempts, false)
    end
    if pt ~= nil then
        return pt
    end

    local ring_inner = pref_max
    while ring_inner < expand_limit do
        local ring_outer = math.min(ring_inner + ring_step, expand_limit)
        pt = TryPolarSpawnCandidates(
            base_x, base_z, tier_key,
            ring_inner, ring_outer, ring_attempts, true)
        if pt == nil then
            pt = TryRandomLandSpawnCandidates(
                base_x, base_z, tier_key,
                ring_inner, ring_outer, ring_attempts, true)
        end
        if pt ~= nil then
            return pt
        end
        ring_inner = ring_outer
    end

    return nil
end

local function GetChestPrefabForTier(tier_key)
    local cfg = GetChestTierConfig(tier_key)
    return cfg.prefab or ("waxwell_shadow_sunken_chest_" .. (tier_key or "medium"))
end

local function IsShadowReliquaryChest(chest)
    return chest ~= nil and chest:IsValid() and chest:HasTag("waxwell_shadow_sunken_chest")
end

local SSC_RIFT_BUSY_TAG = "waxwell_ssc_rift_busy"

local function IsShadowReliquaryChestRiftTransfer(chest)
    return chest ~= nil
        and chest:IsValid()
        and (chest._umbral_rift_transferring or chest:HasTag(SSC_RIFT_BUSY_TAG))
end

local function CancelChestReliquarySuckTask(chest)
    if chest ~= nil and chest._reliquary_suck_task ~= nil then
        chest._reliquary_suck_task:Cancel()
        chest._reliquary_suck_task = nil
    end
end

-- Abort an in-progress winch unlock if the chest is pulled into an Umbral Rift.
local function AbortShadowReliquaryUnlockForChest(chest)
    if chest == nil or not chest:IsValid() or chest._owner_userid == nil then
        return
    end

    CancelChestReliquarySuckTask(chest)
    if chest._unlocking or chest._smashing or chest:HasTag("waxwell_ssc_busy") then
        chest._unlocking = false
        chest._smashing = false
        chest:RemoveTag("waxwell_ssc_busy")
        if chest.components ~= nil and chest.components.inventoryitem ~= nil then
            chest.components.inventoryitem.canbepickedup = true
        end
    end

    local x, _, z = chest.Transform:GetWorldPosition()
    local search = math.max((V.SHADOW_RELIQUARY_SUCK_RADIUS or 3) * 4, 16)
    for _, base in ipairs(TheSim:FindEntities(x, 0, z, search, { "waxwell_shadow_reliquary_base" })) do
        if base ~= nil
            and base:IsValid()
            and base._unlocking
            and base._owner_userid == chest._owner_userid then
            base._unlocking = false
            if base.AnimState ~= nil then
                base.AnimState:PlayAnimation("idle", true)
            end
            if base.SoundEmitter ~= nil then
                base.SoundEmitter:KillAllSounds()
            end
        end
    end
end

local function SetShadowReliquaryChestRiftTransfer(chest, transferring)
    if not IsShadowReliquaryChest(chest) then
        return
    end

    if transferring then
        AbortShadowReliquaryUnlockForChest(chest)
        chest._umbral_rift_transferring = true
        chest:AddTag(SSC_RIFT_BUSY_TAG)
    else
        chest._umbral_rift_transferring = nil
        chest:RemoveTag(SSC_RIFT_BUSY_TAG)
    end
end

-- Shared spawn path for scheduled world waves and debug skill_chest_spawn():
-- create the chest, bind owner userid, intro FX, reveal after shadow lands.
local function SpawnShadowReliquaryChest(owner, x, z, owner_userid, tier_key)
    if TheWorld == nil or not TheWorld.ismastersim then
        return nil
    end
    if x == nil or z == nil then
        return nil
    end

    tier_key = tier_key or "medium"
    local tier = GetChestTierConfig(tier_key)

    local chest = SpawnPrefab(GetChestPrefabForTier(tier_key))
    if chest == nil then
        return nil
    end

    chest.Transform:SetPosition(x, 0, z)
    if chest.ApplyChestTier ~= nil then
        chest:ApplyChestTier(tier_key)
    end

    local userid = owner_userid or (owner ~= nil and owner.userid or nil)
    if chest.SetOwner ~= nil then
        chest:SetOwner(owner, userid)
    end
    if chest.RevealAfterShadowIntro ~= nil then
        chest:RevealAfterShadowIntro(function(c)
            if c.StartLifetimeTimer ~= nil then
                c:StartLifetimeTimer(tier.lifetime)
            end
        end)
    end
    return chest
end

-- If a chest exits an Umbral Rift portal inside a base's suck radius, skip the
-- rift push and start the normal unlock sequence on the owning base instead.
-- radius_override: optional larger radius (e.g. body-drop near the winch edge).
local function IsShadowReliquaryChestOnGround(chest)
    if chest == nil or not chest:IsValid() or chest:IsInLimbo() then
        return false
    end
    local inv = chest.components ~= nil and chest.components.inventoryitem or nil
    return inv == nil or not inv:IsHeld()
end

local function MoveChestToPoint(chest, x, z)
    if chest == nil or not chest:IsValid() then
        return
    end
    if chest.Physics ~= nil then
        chest.Physics:Stop()
        chest.Physics:Teleport(x, 0, z)
    else
        chest.Transform:SetPosition(x, 0, z)
    end
end

-- Push a chest that belongs to a different Maxwell away from this winch.
local function BounceChestFromWinch(base, chest)
    if base == nil
        or not base:IsValid()
        or chest == nil
        or not chest:IsValid()
        or not IsShadowReliquaryChest(chest)
        or chest._unlocking
        or chest._smashing
        or IsShadowReliquaryChestRiftTransfer(chest)
        or not IsShadowReliquaryChestOnGround(chest) then
        return false
    end

    local chest_uid = chest._owner_userid
    local base_uid = base._owner_userid
    if chest_uid == nil or base_uid == nil or chest_uid == base_uid then
        return false
    end

    local now = GetTime()
    local cooldown = V.SHADOW_RELIQUARY_CHEST_BOUNCE_COOLDOWN or 1
    if chest._reliquary_bounce_attime ~= nil and now - chest._reliquary_bounce_attime < cooldown then
        return true
    end
    chest._reliquary_bounce_attime = now

    local bx, _, bz = base.Transform:GetWorldPosition()
    local cx, _, cz = chest.Transform:GetWorldPosition()
    local dx, dz = cx - bx, cz - bz
    local len_sq = dx * dx + dz * dz
    if len_sq < .0001 then
        local theta = math.random() * TWOPI
        dx, dz = math.cos(theta), math.sin(theta)
        len_sq = 1
    end
    local len = math.sqrt(len_sq)
    dx, dz = dx / len, dz / len

    local radius = V.SHADOW_RELIQUARY_SUCK_RADIUS or 3
    local pad = V.SHADOW_RELIQUARY_CHEST_BOUNCE_PAD or 2
    local tx = bx + dx * (radius + pad)
    local tz = bz + dz * (radius + pad)
    MoveChestToPoint(chest, tx, tz)

    local speed = V.SHADOW_RELIQUARY_CHEST_BOUNCE_SPEED or 4
    if chest.Physics ~= nil then
        chest.Physics:SetVel(dx * speed, 0, dz * speed)
    end

    return true
end

local function TryAbsorbShadowReliquaryChest(chest, x, z, radius_override)
    if TheWorld == nil or not TheWorld.ismastersim then
        return false
    end
    if chest == nil or not IsShadowReliquaryChest(chest) then
        return false
    end
    if chest._unlocking or chest._smashing or IsShadowReliquaryChestRiftTransfer(chest) then
        return false
    end
    if not IsShadowReliquaryChestOnGround(chest) then
        return false
    end

    local uid = chest._owner_userid
    if uid == nil then
        return false
    end

    local radius = radius_override or V.SHADOW_RELIQUARY_SUCK_RADIUS
    local bases = TheSim:FindEntities(x, 0, z, radius, { "waxwell_shadow_reliquary_base" })
    local bounced = false
    for _, base in ipairs(bases) do
        if base ~= nil and base:IsValid() and not base._deactivating then
            if base._owner_userid ~= uid then
                if BounceChestFromWinch(base, chest) then
                    bounced = true
                end
            elseif not base._unlocking and base.TryUnlockChest ~= nil then
                base:TryUnlockChest(chest)
                return true
            end
        end
    end

    return bounced
end

local function ShadowReliquaryReticuleValidFn(inst, reticule, pos)
    local pt = ResolvePoint(pos)
    if pt == nil then
        return false
    end
    local doer = ThePlayer
    local check_cast_range = ReticuleUtils.IsReticuleRangeLockEnabled()
    return IsShadowReliquaryPlacementValid(pt, doer, check_cast_range)
end

-- =============================================================================
-- Cast / toggle
-- =============================================================================

local function GetShadowReliquaryCastBlockReason(inst, doer, pos)
    if inst == nil or inst.components == nil or inst.components.fueled == nil then
        return "MISSING_FUELED"
    elseif inst.components.fueled:IsEmpty() then
        return "NO_FUEL_EMPTY"
    elseif not HasEnoughCodexFuel(inst, V.SHADOW_RELIQUARY_DURABILITY_COST_PCT) then
        return "NO_FUEL_COST"
    elseif not IsShadowReliquarySkillActive(doer) then
        return "SKILL_INACTIVE"
    elseif IsShadowReliquaryOnCooldown(doer) then
        return "SPELL_ON_COOLDOWN"
    end

    local sanity_cost = GetShadowReliquarySanityCost(doer)
    if sanity_cost ~= nil and sanity_cost > 0 then
        local cost_gate = require("skill_effect/waxwell/_shared/codex_cost_gate")
        if not cost_gate.HasEnoughSanity(doer, sanity_cost) then
            return "NO_SANITY"
        end
    end

    if pos ~= nil then
        local check_cast_range = ReticuleUtils.IsReticuleRangeLockEnabled()
        if not IsShadowReliquaryPlacementValid(pos, doer, check_cast_range) then
            return "NO_TARGETS"
        end
    end

    return nil
end

local function RequestShadowReliquaryDeactivate(owner)
    local base = GetShadowReliquaryBase(owner)
    if base ~= nil and base.RequestDeactivate ~= nil then
        base:RequestDeactivate("manual")
        return true
    end
    return false
end

local function OnShadowReliquaryEnded(owner)
    if owner ~= nil and owner:IsValid() then
        owner._waxwell_shadow_reliquary_base = nil
        spell_utils.RestartSpellCooldown(owner, V.SHADOW_RELIQUARY_COOLDOWN_ID, V.SHADOW_RELIQUARY_COOLDOWN_TIME)
        PushSpellRefresh(owner)
    end
end

local function BeginShadowReliquary(owner, pos)
    if owner == nil or not owner:IsValid() or pos == nil then
        return false
    end

    local base = SpawnPrefab("waxwell_shadow_reliquary_base")
    if base == nil then
        return false
    end

    base.Transform:SetPosition(pos.x, 0, pos.z)
    owner._waxwell_shadow_reliquary_base = base
    base:Activate(owner)
    PushSpellRefresh(owner)
    return true
end

local function ShadowReliquaryCancelSpellFn(inst, doer)
    local owner = ResolveSpellOwner(inst, doer)
    if owner == nil then
        return false
    end
    local state = GetShadowReliquarySpellState(owner)
    if state == "active" then
        return RequestShadowReliquaryDeactivate(owner)
    end
    return false
end

local function ShadowReliquarySpellFn(inst, doer, pos)
    local owner = ResolveSpellOwner(inst, doer)
    if owner == nil then
        return false
    end

    local state = GetShadowReliquarySpellState(owner)
    if state == "active" then
        return RequestShadowReliquaryDeactivate(owner)
    elseif state ~= nil then
        return false
    end

    local blockreason = GetShadowReliquaryCastBlockReason(inst, owner, pos)
    if blockreason == "NO_FUEL_EMPTY" or blockreason == "NO_FUEL_COST" then
        return false, "NO_FUEL"
    elseif blockreason == "NO_SANITY" then
        return false, "NO_SANITY"
    elseif blockreason == "SPELL_ON_COOLDOWN" then
        return false, "SPELL_ON_COOLDOWN"
    elseif blockreason == "NO_TARGETS" then
        return false, "NO_TARGETS"
    elseif blockreason ~= nil then
        return false
    end

    local target = ResolvePoint(pos)
    local check_cast_range = ReticuleUtils.IsReticuleRangeLockEnabled()
    if target == nil or not IsShadowReliquaryPlacementValid(target, owner, check_cast_range) then
        return false, "NO_TARGETS"
    end

    if inst.components ~= nil and inst.components.fueled ~= nil then
        inst.components.fueled:DoDelta(SpellCost(V.SHADOW_RELIQUARY_DURABILITY_COST_PCT), owner)
    end
    local sanity_cost = GetShadowReliquarySanityCost(owner)
    if sanity_cost > 0 and owner.components ~= nil and owner.components.sanity ~= nil then
        owner.components.sanity:DoDelta(-sanity_cost)
    end

    if not BeginShadowReliquary(owner, target) then
        return false
    end

    return true
end

local function ShouldRepeatCastShadowReliquary()
    return false
end

local function GetShadowReliquarySpellData(user)
    local LABEL = STRINGS.SPELLS[V.SHADOW_RELIQUARY_SPELL] or "Shadow Reliquary"

    local function GetCurrentState(inst)
        return GetShadowReliquarySpellState(ResolveSpellOwner(inst, user))
    end

    local item = {
        spell_id = V.SHADOW_RELIQUARY_SPELL,
        label = LABEL,
        onselect = function(inst)
            local currentstate = GetCurrentState(inst)
            local isactive = currentstate == "active"

            inst.components.spellbook:SetSpellName(LABEL)
            inst.components.aoetargeting:SetAlwaysValid(false)
            inst.components.aoetargeting:SetAllowWater(false)
            inst.components.aoetargeting:SetDeployRadius(0)
            inst.components.aoetargeting:SetShouldRepeatCastFn(ShouldRepeatCastShadowReliquary)

            if isactive then
                inst.components.spellbook:SetSpellAction(ACTIONS.CAST_SPELLBOOK)
                inst.components.spellbook:SetSpellFn(ShadowReliquaryCancelSpellFn)
                if TheWorld.ismastersim then
                    inst.components.aoetargeting:SetTargetFX(nil)
                    inst.components.aoespell:SetSpellFn(nil)
                end
            else
                inst.components.spellbook:SetSpellAction(nil)
                inst.components.spellbook:SetSpellFn(nil)
                ReticuleUtils.ApplySpellReticule(
                    inst,
                    inst.components.aoetargeting,
                    V.SHADOW_RELIQUARY_RETICULE_SCALE,
                    V.SHADOW_RELIQUARY_RETICULE_ANIM,
                    {
                        cast_range = V.SHADOW_RELIQUARY_CAST_RANGE,
                        validfn = ShadowReliquaryReticuleValidFn,
                    }
                )
                inst.components.aoetargeting:SetDeployRadius(0)
                if TheWorld.ismastersim then
                    inst.components.aoetargeting:SetTargetFX(nil)
                    inst.components.aoespell:SetSpellFn(ShadowReliquarySpellFn)
                end
            end
        end,
        execute = function(inst)
            local currentstate = GetCurrentState(inst)
            if currentstate == "deactivating" or currentstate == "unlocking" then
                return true
            end
            if currentstate == "active" then
                TriggerInstantSpellbookCast(inst, ACTIONS.CAST_SPELLBOOK)
                return
            end
            StartAOETargeting(inst)
        end,
        atlas = "images/waxwell/waxwell_codex_icon.xml",
        normal = "codex_umbra_shadow_reliquary.tex",
        widget_scale = V.SHADOW_RELIQUARY_ICON_SCALE,
        hit_radius = V.SHADOW_RELIQUARY_ICON_RADIUS,
    }

    return SpellIcon.BindToggleSpellItem(
        item,
        function(u)
            return GetShadowReliquarySpellState(u)
        end,
        function(u)
            return GetShadowReliquaryCooldownPercent(u)
        end
    )
end

return {
    SHADOW_RELIQUARY_SPELL = V.SHADOW_RELIQUARY_SPELL,
    SHADOW_RELIQUARY_COOLDOWN_ID = V.SHADOW_RELIQUARY_COOLDOWN_ID,
    SHADOW_RELIQUARY_COOLDOWN_TIME = V.SHADOW_RELIQUARY_COOLDOWN_TIME,
    SHADOW_RELIQUARY_DURABILITY_COST_PCT = V.SHADOW_RELIQUARY_DURABILITY_COST_PCT,
    IsShadowReliquarySkillActive = IsShadowReliquarySkillActive,
    GetShadowReliquaryBase = GetShadowReliquaryBase,
    GetShadowReliquarySpellState = GetShadowReliquarySpellState,
    GetShadowReliquarySpellData = GetShadowReliquarySpellData,
    GetShadowReliquarySanityCost = GetShadowReliquarySanityCost,
    RequestShadowReliquaryDeactivate = RequestShadowReliquaryDeactivate,
    OnShadowReliquaryEnded = OnShadowReliquaryEnded,
    IsShadowReliquaryPlacementValid = IsShadowReliquaryPlacementValid,
    IsShadowReliquaryChestSpawnPointValid = IsShadowReliquaryChestSpawnPointValid,
    FindChestSpawnPointForTier = FindChestSpawnPointForTier,
    GetChestTierConfig = GetChestTierConfig,
    GetChestPrefabForTier = GetChestPrefabForTier,
    IsShadowReliquaryChest = IsShadowReliquaryChest,
    IsShadowReliquaryChestRiftTransfer = IsShadowReliquaryChestRiftTransfer,
    SetShadowReliquaryChestRiftTransfer = SetShadowReliquaryChestRiftTransfer,
    SpawnShadowReliquaryChest = SpawnShadowReliquaryChest,
    PlayShadowReliquaryGroundIntro = PlayShadowReliquaryGroundIntro,
    RevealAfterShadowIntro = RevealAfterShadowIntro,
    TryAbsorbShadowReliquaryChest = TryAbsorbShadowReliquaryChest,
    BounceChestFromWinch = BounceChestFromWinch,
    EnsureShadowReliquaryMapIcons = mapicons.EnsureMapIcons,
    ClearShadowReliquaryMapIcons = mapicons.ClearMapIcons,
    IsShadowReliquaryCodexRiftTransfer = codex_recharge.IsShadowReliquaryCodexRiftTransfer,
    SetShadowReliquaryCodexRiftTransfer = codex_recharge.SetShadowReliquaryCodexRiftTransfer,
    TryAbsorbShadowReliquaryCodex = codex_recharge.TryAbsorbShadowReliquaryCodex,
    RegisterCodexRechargeJournalHooks = codex_recharge.RegisterJournalHooks,
    PushSpellRefresh = PushSpellRefresh,
}
