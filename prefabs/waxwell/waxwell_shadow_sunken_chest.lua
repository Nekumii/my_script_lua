-- Shadow Reliquary chests (small / medium / large prefabs). Heavy-carry sunkenchest
-- clone; opens only via owning waxwell_shadow_reliquary_base smash sequence.
local V = require("skill_effect/waxwell/emperor/shadow_reliquary/variables")
local persist_utils = require("skill_effect/waxwell/_shared/persist_utils")
local reliquary_fling = require("skill_effect/waxwell/emperor/shadow_reliquary/fling")

local PHYSICS_RADIUS = .45

local shadow_reliquary_common

local function GetCommon()
    if shadow_reliquary_common == nil then
        shadow_reliquary_common = require("skill_effect/waxwell/emperor/shadow_reliquary/common")
    end
    return shadow_reliquary_common
end

local assets =
{
    Asset("ANIM", "anim/sunken_treasurechest.zip"),
    Asset("ANIM", "anim/swap_sunken_treasurechest.zip"),
}

local spawn_prefabs =
{
    "shadow_despawn",
    "sanity_raise",
    "globalmapicon",
    "globalmapiconnoproxy",
}

-- =============================================================================
-- Private helpers
-- =============================================================================

local function GetChestTierConfig(inst)
    local tier_key = inst._chest_tier or "medium"
    local cfg = V.SHADOW_RELIQUARY_CHEST_TIER_CONFIG[tier_key]
    return cfg or V.SHADOW_RELIQUARY_CHEST_TIER_CONFIG.medium, tier_key
end

local function ApplyVisualStyle(inst)
    local cfg = GetChestTierConfig(inst)
    local r = cfg.tint_r
    local g = cfg.tint_g
    local b = cfg.tint_b
    if r == nil then
        local tint = V.SHADOW_RELIQUARY_CHEST_TINT or .1
        r, g, b = tint, tint, tint
    end
    inst.AnimState:SetMultColour(r, g, b, 1)
    inst.AnimState:SetFinalOffset(V.SHADOW_RELIQUARY_STACKED_FINAL_OFFSET or 1)
end

local function ApplyChestTierVisual(inst, tier_key)
    local cfg = V.SHADOW_RELIQUARY_CHEST_TIER_CONFIG[tier_key]
        or V.SHADOW_RELIQUARY_CHEST_TIER_CONFIG.medium
    local scale = cfg.scale or 1
    inst.Transform:SetScale(scale, scale, scale)
    ApplyVisualStyle(inst)
end

local function CancelLifetimeTask(inst)
    if inst._lifetime_task ~= nil then
        inst._lifetime_task:Cancel()
        inst._lifetime_task = nil
    end
end

local function CancelSmashTask(inst)
    if inst._smash_task ~= nil then
        inst._smash_task:Cancel()
        inst._smash_task = nil
    end
end

local function DespawnUnclaimed(inst)
    if inst == nil or not inst:IsValid() or inst._unlocking then
        return
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    local fx = SpawnPrefab("shadow_despawn")
    if fx ~= nil then
        fx.Transform:SetPosition(x, y, z)
    end
    inst:Remove()
end

local function StartLifetimeTimer(inst, remaining)
    CancelLifetimeTask(inst)
    if remaining == nil then
        local cfg = GetChestTierConfig(inst)
        remaining = cfg.lifetime or V.SHADOW_RELIQUARY_CHEST_LIFETIME
    end
    remaining = math.max(0, remaining)
    inst._despawn_attime = GetTime() + remaining
    inst._lifetime_task = inst:DoTaskInTime(remaining, DespawnUnclaimed)
end

local function FlingLootItem(item, x, y, z)
    if item == nil then
        return
    end

    reliquary_fling.FlingEntity(
        item,
        x, y, z,
        V.SHADOW_RELIQUARY_LOOT_FLING_SPEED_MIN,
        V.SHADOW_RELIQUARY_LOOT_FLING_SPEED_MAX,
        V.SHADOW_RELIQUARY_LOOT_FLING_Y_MIN,
        V.SHADOW_RELIQUARY_LOOT_FLING_Y_MAX,
        V.SHADOW_RELIQUARY_LOOT_FLING_XZ_SPREAD
    )
end

local function DropPlaceholderLoot(inst)
    local cfg = GetChestTierConfig(inst)
    local loot = cfg.loot
    if loot == nil or #loot == 0 then
        loot = V.SHADOW_RELIQUARY_PLACEHOLDER_LOOT
    end
    if loot == nil or #loot == 0 then
        return
    end

    local mincount = cfg.loot_min or V.SHADOW_RELIQUARY_LOOT_MIN_COUNT or 3
    local maxcount = math.max(mincount, cfg.loot_max or V.SHADOW_RELIQUARY_LOOT_MAX_COUNT or mincount)
    local count = math.random(mincount, maxcount)
    local x, y, z = inst.Transform:GetWorldPosition()

    for _ = 1, count do
        local prefab = loot[math.random(#loot)]
        FlingLootItem(SpawnPrefab(prefab), x, y, z)
    end
end

local function OnEquip(inst, owner)
    local cfg = GetChestTierConfig(inst)
    local r = cfg.tint_r or V.SHADOW_RELIQUARY_CHEST_TINT or .1
    local g = cfg.tint_g or r
    local b = cfg.tint_b or r
    owner.AnimState:OverrideSymbol("swap_body", "swap_sunken_treasurechest", "swap_body")
    owner.AnimState:SetSymbolMultColour("swap_body", r, g, b, 1)
end

local function OnUnequip(inst, owner)
    owner.AnimState:SetSymbolMultColour("swap_body", 1, 1, 1, 1)
    owner.AnimState:ClearOverrideSymbol("swap_body")
end

local function TryAbsorbAfterDrop(inst)
    if inst == nil or not inst:IsValid() or inst._unlocking or inst._smashing then
        return
    end
    local inv = inst.components.inventoryitem
    if inv ~= nil and inv:IsHeld() then
        return
    end
    local common = GetCommon()
    if common.TryAbsorbShadowReliquaryChest == nil then
        return
    end
    local x, _, z = inst.Transform:GetWorldPosition()
    local radius = (V.SHADOW_RELIQUARY_SUCK_RADIUS or 3) + (V.SHADOW_RELIQUARY_DROP_ABSORB_PAD or 1)
    common.TryAbsorbShadowReliquaryChest(inst, x, z, radius)
end

local function OnDropped(inst)
    TryAbsorbAfterDrop(inst)
    inst:DoTaskInTime(.35, TryAbsorbAfterDrop)
end

local function GetStatus(inst)
    return "LOCKED"
end

local function EnablePickup(inst)
    if inst.components.inventoryitem ~= nil and not inst._unlocking and not inst._smashing then
        inst.components.inventoryitem.canbepickedup = true
    end
end

-- =============================================================================
-- Smash sequence
-- =============================================================================

local function PlayHitPulse(inst)
    inst.AnimState:PlayAnimation("hit")
    inst.AnimState:PushAnimation("closed", false)
    if inst.SoundEmitter ~= nil then
        inst.SoundEmitter:PlaySound("dontstarve/wilson/chest_close")
    end
end

local function BreakOpen(inst, oncomplete)
    if inst.SoundEmitter ~= nil then
        inst.SoundEmitter:PlaySound("dontstarve/wilson/chest_open")
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    local fx = SpawnPrefab("shadow_despawn")
    if fx ~= nil then
        fx.Transform:SetPosition(x, y, z)
    end

    DropPlaceholderLoot(inst)
    inst:Remove()

    if oncomplete ~= nil then
        oncomplete()
    end
end

local function DoSmashPulse(inst, elapsed, oncomplete)
    if inst == nil or not inst:IsValid() then
        return
    end

    PlayHitPulse(inst)

    local duration = V.SHADOW_RELIQUARY_SMASH_DURATION or 4
    local startinterval = V.SHADOW_RELIQUARY_SMASH_START_INTERVAL or .55
    local endinterval = V.SHADOW_RELIQUARY_SMASH_END_INTERVAL or .12
    local progress = math.min(1, elapsed / duration)
    local nextinterval = Lerp(startinterval, endinterval, progress)
    local nextelapsed = elapsed + nextinterval

    inst._smash_task = inst:DoTaskInTime(nextinterval, function()
        if inst == nil or not inst:IsValid() then
            return
        end
        if nextelapsed >= duration then
            BreakOpen(inst, oncomplete)
        else
            DoSmashPulse(inst, nextelapsed, oncomplete)
        end
    end)
end

local function BeginSmash(inst, oncomplete)
    if inst._smashing then
        return
    end

    inst._smashing = true
    inst._unlocking = true
    inst:AddTag("waxwell_ssc_busy")
    if inst.components.inventoryitem ~= nil then
        inst.components.inventoryitem.canbepickedup = false
    end
    CancelLifetimeTask(inst)
    DoSmashPulse(inst, 0, oncomplete)
end

-- =============================================================================
-- Owner-private / shared map icons (see shadow_reliquary/mapicons.lua)
-- =============================================================================

local mapicons = require("skill_effect/waxwell/emperor/shadow_reliquary/mapicons")

local function GetChestMapIconName(inst)
    local cfg = GetChestTierConfig(inst)
    return cfg.mapicon or "ssc_map_chest_medium.png"
end

local function ClearOwnerMapIcons(inst)
    mapicons.ClearMapIcons(inst)
end

local function EnsureOwnerMapIcons(inst)
    mapicons.EnsureMapIcons(inst, inst._owner_userid, GetChestMapIconName(inst))
end

-- =============================================================================
-- Public API on instance
-- =============================================================================

local function ApplyChestTier(inst, tier_key)
    tier_key = tier_key or inst._chest_tier or "medium"
    if V.SHADOW_RELIQUARY_CHEST_TIER_CONFIG[tier_key] == nil then
        tier_key = "medium"
    end
    inst._chest_tier = tier_key
    ApplyChestTierVisual(inst, tier_key)
    if inst.components.equippable ~= nil then
        local cfg = V.SHADOW_RELIQUARY_CHEST_TIER_CONFIG[tier_key]
        inst.components.equippable.walkspeedmult = V.HeavyCarryWalkSpeedMult(cfg.carry_penalty)
    end
    EnsureOwnerMapIcons(inst)
end

local function SetOwner(inst, owner, owner_userid)
    inst.owner = owner
    inst._owner_userid = owner_userid or (owner ~= nil and owner.userid or nil)
    EnsureOwnerMapIcons(inst)
end

local function MarkUnlocking(inst)
    inst._unlocking = true
    inst:AddTag("waxwell_ssc_busy")
    if inst.components.inventoryitem ~= nil then
        inst.components.inventoryitem.canbepickedup = false
    end
    CancelLifetimeTask(inst)
end

local function RevealAfterShadowIntro(inst, onreveal)
    local common = GetCommon()
    local function onrevealed(chest)
        EnablePickup(chest)
        if onreveal ~= nil then
            onreveal(chest)
        end
    end
    if common.RevealAfterShadowIntro ~= nil then
        common.RevealAfterShadowIntro(inst, onrevealed)
    else
        inst:Show()
        onrevealed(inst)
    end
end

-- =============================================================================
-- Persist
-- =============================================================================

local function OnSave(inst, data)
    data._owner_userid = inst._owner_userid
    data._chest_tier = inst._chest_tier
    if inst._despawn_attime ~= nil then
        persist_utils.SaveRemainingTime(data, "_despawn_remaining", inst._despawn_attime)
    end
end

local function OnLoad(inst, data)
    if data == nil then
        return
    end

    inst._owner_userid = data._owner_userid
    if data._chest_tier ~= nil then
        inst._chest_tier = data._chest_tier
    end
    ApplyChestTier(inst, inst._chest_tier)
    inst._unlocking = false
    inst._smashing = false
    inst:RemoveTag("waxwell_ssc_busy")
    EnablePickup(inst)

    local remaining = persist_utils.GetSavedRemainingTime(data, "_despawn_remaining")
    StartLifetimeTimer(inst, remaining > 0 and remaining or nil)
end

-- =============================================================================
-- Prefab factory
-- =============================================================================

local function OnRemove(inst)
    CancelLifetimeTask(inst)
    CancelSmashTask(inst)
    ClearOwnerMapIcons(inst)
end

local function MakeChestFn(fixed_tier)
    return function()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddMiniMapEntity()
        inst.entity:AddNetwork()

        MakeHeavyObstaclePhysics(inst, PHYSICS_RADIUS)
        inst:SetPhysicsRadiusOverride(PHYSICS_RADIUS)

        inst.AnimState:SetBank("sunken_treasurechest")
        inst.AnimState:SetBuild("sunken_treasurechest")
        inst.AnimState:PlayAnimation("closed")

        inst.highlightoverride = { .55, .55, .55 }

        inst.MiniMapEntity:SetIcon("sunkenchest.png")
        inst.MiniMapEntity:SetCanUseCache(false)
        inst.MiniMapEntity:SetEnabled(false)

        inst:AddTag("heavy")
        inst:AddTag("waxwell_shadow_sunken_chest")
        inst:AddTag("__inventoryitem")
        inst:AddTag("__equippable")

        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:RemoveTag("__inventoryitem")
        inst:RemoveTag("__equippable")

        inst.persists = true
        inst.owner = nil
        inst._owner_userid = nil
        inst._chest_tier = fixed_tier
        inst._unlocking = false
        inst._smashing = false
        inst._lifetime_task = nil
        inst._smash_task = nil
        inst._despawn_attime = nil
    inst._mapicon_far = nil
    inst._mapicon_near = nil
    inst._mapicon_wait_player = nil

        inst:AddComponent("inspectable")
        inst.components.inspectable.getstatus = GetStatus

        inst:AddComponent("heavyobstaclephysics")
        inst.components.heavyobstaclephysics:SetRadius(PHYSICS_RADIUS)

        inst:AddComponent("inventoryitem")
        inst.components.inventoryitem.cangoincontainer = false
        inst.components.inventoryitem.canbepickedup = true
        inst.components.inventoryitem.imagename = "sunkenchest"
        inst.components.inventoryitem:SetOnDroppedFn(OnDropped)

        inst:AddComponent("equippable")
        inst.components.equippable.equipslot = EQUIPSLOTS.BODY
        inst.components.equippable:SetOnEquip(OnEquip)
        inst.components.equippable:SetOnUnequip(OnUnequip)

        inst:AddComponent("symbolswapdata")
        inst.components.symbolswapdata:SetData("swap_sunken_treasurechest", "swap_body")

        ApplyChestTier(inst, fixed_tier)

        inst.SetOwner = SetOwner
        inst.ApplyChestTier = ApplyChestTier
        inst.MarkUnlocking = MarkUnlocking
        inst.BeginSmash = BeginSmash
        inst.StartLifetimeTimer = StartLifetimeTimer
        inst.RevealAfterShadowIntro = RevealAfterShadowIntro

        inst.OnSave = OnSave
        inst.OnLoad = OnLoad
        inst:ListenForEvent("onremove", OnRemove)

        return inst
    end
end

return Prefab("waxwell_shadow_sunken_chest_small", MakeChestFn("small"), assets, spawn_prefabs),
    Prefab("waxwell_shadow_sunken_chest_medium", MakeChestFn("medium"), assets, spawn_prefabs),
    Prefab("waxwell_shadow_sunken_chest_large", MakeChestFn("large"), assets, spawn_prefabs),
    Prefab("waxwell_shadow_sunken_chest", MakeChestFn("medium"), assets, spawn_prefabs)
