local V = require("skill_effect/waxwell/emperor/fissure_eruption/variables")
local spell_utils = require("skill_effect/waxwell/_shared/codex_spell_utils")
local SpellIcon = require("skill_effect/waxwell/_shared/codex_spell_icon")
local ReticuleUtils = require("reticule/utils")
local debug = require("debug/init")
local ModCompat = require("mod_compatibility")
local dark_scholar = require("skill_effect/waxwell/umbra/dark_scholar/common")

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

local function GetFissureEruptionSanityCost(doer)
    return dark_scholar.GetDarkScholarSanityCost(V.FISSURE_ERUPTION_SANITY_COST, doer)
end

local function IsFriendlyOrSummonedTarget(ent)
    if ent == nil then
        return true
    end
    if ent:HasTag("player")
        or ent:HasTag("companion")
        or ent:HasTag("playerpet")
        or ent:HasTag("shadowminion")
        or ent:HasTag("stalkerminion")
        or ent:HasTag("chester")
        or ent:HasTag("hutch")
        or ent:HasTag("glommer")
        or ent:HasTag("abigail")
        or ent:HasTag("structure")
        or ent:HasTag("wall") then
        return true
    end

    local follower = ent.components ~= nil and ent.components.follower or nil
    local leader = follower ~= nil and follower:GetLeader() or nil
    if leader ~= nil and (leader:HasTag("player") or leader:HasTag("companion") or leader:HasTag("shadowmagic")) then
        return true
    end

    return false
end

-- =============================================================================
-- Skill / sinkhole state
-- =============================================================================

local function IsFissureEruptionSkillActive(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_fissure_eruption"))
            or inst:HasTag(V.FISSURE_ERUPTION_ACTIVE_TAG)
        )
end

local function GetFissureSinkhole(owner)
    if owner == nil then
        return nil
    end

    local field = owner._waxwell_fissure_eruption_sinkhole
    if field ~= nil and field:IsValid() then
        return field
    end

    if owner.userid ~= nil then
        for _, ent in pairs(Ents) do
            if ent ~= nil
                and ent:IsValid()
                and ent.prefab == "waxwell_fissure_eruption_sinkhole"
                and ent._owner_userid == owner.userid then
                owner._waxwell_fissure_eruption_sinkhole = ent
                if ent.RebindOwner ~= nil then
                    ent:RebindOwner(owner)
                else
                    ent.owner = owner
                end
                return ent
            end
        end
    end

    owner._waxwell_fissure_eruption_sinkhole = nil
    return nil
end

local function GetFissureEruptionSpellState(owner)
    if owner == nil then
        return nil
    end
    local field = GetFissureSinkhole(owner)
    if field == nil then
        return nil
    end
    if field._ending then
        return "deactivating"
    end
    return "active"
end

local function IsFissureEruptionOnCooldown(doer)
    return spell_utils.IsSpellOnCooldown(doer, V.FISSURE_ERUPTION_COOLDOWN_ID)
end

local function GetFissureEruptionCooldownPercent(doer)
    return spell_utils.GetSpellCooldownPercent(doer, V.FISSURE_ERUPTION_COOLDOWN_ID)
end

local function GetFissureEruptionActiveDurationPercent(owner)
    if GetFissureEruptionSpellState(owner) ~= "active" then
        return nil
    end

    local field = GetFissureSinkhole(owner)
    return SpellIcon.GetEntityTimerRemainingPercent(field, V.FISSURE_ERUPTION_LIFETIME_TIMER)
end

-- =============================================================================
-- Placement validation
-- =============================================================================

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

local BLOCKER_ONEOF_TAGS = { "pond", "lava" }
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

local function IsCenterLandPoint(pt)
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

local function IsDiscSurroundedByLand(pt, radius)
    if pt == nil or TheWorld == nil or TheWorld.Map == nil then
        return false
    end
    local map = TheWorld.Map
    if map.IsSurroundedByLand ~= nil then
        return map:IsSurroundedByLand(pt.x, 0, pt.z, radius)
    end
    -- Fallback ring sample
    local samples = 16
    for i = 0, samples - 1 do
        local theta = i * TWOPI / samples
        local sx = pt.x + math.cos(theta) * radius
        local sz = pt.z + math.sin(theta) * radius
        if map:IsOceanAtPoint(sx, 0, sz, false) or not map:IsPassableAtPoint(sx, 0, sz, false, true) then
            return false
        end
    end
    return true
end

local function IsBlockerEntity(ent, center, radius)
    if ent == nil or not ent:IsValid() then
        return false
    end
    local prefab = ent.prefab
    if prefab ~= nil and (BLOCKER_PREFABS[prefab] or (ModCompat.IsTropicalCompatEnabled() and TROPICAL_BLOCKER_PREFABS[prefab])) then
        local pad = ent.Physics ~= nil and ent:GetPhysicsRadius(0) or 0
        return ent:GetDistanceSqToPoint(center.x, 0, center.z) <= (radius + pad) * (radius + pad)
    end
    if ent:HasTag("pond") or ent:HasTag("lava") then
        local pad = ent.Physics ~= nil and ent:GetPhysicsRadius(0) or 0
        return ent:GetDistanceSqToPoint(center.x, 0, center.z) <= (radius + pad) * (radius + pad)
    end
    return false
end

local function HasPlacementBlockers(pt, radius)
    if pt == nil then
        return true
    end
    local search = radius + (V.FISSURE_ERUPTION_BLOCKER_PAD or 2.5)
    local ents = TheSim:FindEntities(pt.x, 0, pt.z, search, nil, BLOCKER_CANT_TAGS, BLOCKER_ONEOF_TAGS)
    for _, ent in ipairs(ents) do
        if IsBlockerEntity(ent, pt, radius) then
            return true
        end
    end
    -- Prefab-only blockers (caves etc.) may lack pond/lava tags
    local ents2 = TheSim:FindEntities(pt.x, 0, pt.z, search, nil, BLOCKER_CANT_TAGS)
    for _, ent in ipairs(ents2) do
        if IsBlockerEntity(ent, pt, radius) then
            return true
        end
    end
    return false
end

local function IsFissureEruptionWithinCastRange(doer, pt)
    if doer == nil or not doer:IsValid() or doer.Transform == nil or pt == nil then
        return false
    end
    local x, _, z = doer.Transform:GetWorldPosition()
    return ReticuleUtils.IsPointWithinCastRange(x, z, pt, V.FISSURE_ERUPTION_CAST_RANGE)
end

local function IsFissureEruptionPlacementValid(pt, doer, check_cast_range)
    pt = ResolvePoint(pt)
    if pt == nil then
        return false
    end
    if check_cast_range ~= false and not IsFissureEruptionWithinCastRange(doer, pt) then
        return false
    end
    if not IsCenterLandPoint(pt) then
        return false
    end
    if not IsDiscSurroundedByLand(pt, V.FISSURE_ERUPTION_WORK_RADIUS) then
        return false
    end
    if HasPlacementBlockers(pt, V.FISSURE_ERUPTION_WORK_RADIUS) then
        return false
    end
    return true
end

local function FissureEruptionReticuleValidFn(inst, reticule, pos)
    local pt = ResolvePoint(pos)
    if pt == nil then
        return false
    end
    local doer = ThePlayer
    local check_cast_range = ReticuleUtils.IsReticuleRangeLockEnabled()
    return IsFissureEruptionPlacementValid(pt, doer, check_cast_range)
end

-- =============================================================================
-- Cast / toggle
-- =============================================================================

local function GetFissureEruptionCastBlockReason(inst, doer, pos)
    if inst == nil or inst.components == nil or inst.components.fueled == nil then
        return "MISSING_FUELED"
    elseif inst.components.fueled:IsEmpty() then
        return "NO_FUEL_EMPTY"
    elseif not HasEnoughCodexFuel(inst, V.FISSURE_ERUPTION_DURABILITY_COST_PCT) then
        return "NO_FUEL_COST"
    elseif not IsFissureEruptionSkillActive(doer) then
        return "SKILL_INACTIVE"
    elseif IsFissureEruptionOnCooldown(doer) then
        return "SPELL_ON_COOLDOWN"
    end

    local sanity_cost = GetFissureEruptionSanityCost(doer)
    if sanity_cost ~= nil and sanity_cost > 0 then
        local cost_gate = require("skill_effect/waxwell/_shared/codex_cost_gate")
        if not cost_gate.HasEnoughSanity(doer, sanity_cost) then
            return "NO_SANITY"
        end
    end

    if pos ~= nil then
        local check_cast_range = ReticuleUtils.IsReticuleRangeLockEnabled()
        if not IsFissureEruptionPlacementValid(pos, doer, check_cast_range) then
            return "NO_TARGETS"
        end
    end

    return nil
end

local function RequestFissureEruptionDeactivate(owner)
    local field = GetFissureSinkhole(owner)
    if field ~= nil and field.RequestDeactivate ~= nil then
        field:RequestDeactivate("manual")
        return true
    end
    return false
end

local function OnFissureEruptionEnded(owner)
    if owner ~= nil and owner:IsValid() then
        owner._waxwell_fissure_eruption_sinkhole = nil
        local cd = debug.GetSkillTestCooldown ~= nil
            and debug.GetSkillTestCooldown(V.FISSURE_ERUPTION_COOLDOWN_TIME)
            or V.FISSURE_ERUPTION_COOLDOWN_TIME
        spell_utils.RestartSpellCooldown(owner, V.FISSURE_ERUPTION_COOLDOWN_ID, cd)
        PushSpellRefresh(owner)
    end
end

local function BeginFissureEruption(owner, pos)
    if owner == nil or not owner:IsValid() or pos == nil then
        return false
    end

    local field = SpawnPrefab("waxwell_fissure_eruption_sinkhole")
    if field == nil then
        return false
    end

    owner._waxwell_fissure_eruption_sinkhole = field
    field:Activate(owner, pos, V.FISSURE_ERUPTION_WORK_RADIUS)
    PushSpellRefresh(owner)
    return true
end

local function FissureEruptionCancelSpellFn(inst, doer)
    local owner = ResolveSpellOwner(inst, doer)
    if owner == nil then
        return false
    end
    local state = GetFissureEruptionSpellState(owner)
    if state == "active" then
        return RequestFissureEruptionDeactivate(owner)
    end
    return false
end

local function FissureEruptionSpellFn(inst, doer, pos)
    local owner = ResolveSpellOwner(inst, doer)
    if owner == nil then
        return false
    end

    local state = GetFissureEruptionSpellState(owner)
    if state == "active" then
        return RequestFissureEruptionDeactivate(owner)
    elseif state ~= nil then
        return false
    end

    local blockreason = GetFissureEruptionCastBlockReason(inst, owner, pos)
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
    if target == nil or not IsFissureEruptionPlacementValid(target, owner, check_cast_range) then
        return false, "NO_TARGETS"
    end

    if inst.components ~= nil and inst.components.fueled ~= nil then
        inst.components.fueled:DoDelta(SpellCost(V.FISSURE_ERUPTION_DURABILITY_COST_PCT), owner)
    end
    local sanity_cost = GetFissureEruptionSanityCost(owner)
    if sanity_cost > 0 and owner.components ~= nil and owner.components.sanity ~= nil then
        owner.components.sanity:DoDelta(-sanity_cost)
    end

    if not BeginFissureEruption(owner, target) then
        return false
    end

    return true
end

local function ShouldRepeatCastFissureEruption()
    return false
end

local function GetFissureEruptionSpellData(user)
    local LABEL = STRINGS.SPELLS[V.FISSURE_ERUPTION_SPELL] or "Fissure Eruption"

    local function GetCurrentState(inst)
        return GetFissureEruptionSpellState(ResolveSpellOwner(inst, user))
    end

    local item = {
        spell_id = V.FISSURE_ERUPTION_SPELL,
        label = LABEL,
        onselect = function(inst)
            local player = ThePlayer
            if player ~= nil then
                local ok, ur = pcall(require, "skill_effect/waxwell/umbra/umbral_rift/common")
                if ok and ur ~= nil and ur.CancelUmbralRiftSkill ~= nil then
                    ur.CancelUmbralRiftSkill(player)
                end
            end

            local currentstate = GetCurrentState(inst)
            local isactive = currentstate == "active"

            inst.components.spellbook:SetSpellName(LABEL)
            inst.components.aoetargeting:SetAlwaysValid(false)
            inst.components.aoetargeting:SetAllowWater(false)
            inst.components.aoetargeting:SetDeployRadius(0)
            inst.components.aoetargeting:SetShouldRepeatCastFn(ShouldRepeatCastFissureEruption)

            if isactive then
                inst.components.spellbook:SetSpellAction(ACTIONS.CAST_SPELLBOOK)
                inst.components.spellbook:SetSpellFn(FissureEruptionCancelSpellFn)
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
                    V.FISSURE_ERUPTION_RETICULE_SCALE,
                    V.FISSURE_ERUPTION_RETICULE_ANIM,
                    {
                        cast_range = V.FISSURE_ERUPTION_CAST_RANGE,
                        validfn = FissureEruptionReticuleValidFn,
                    }
                )
                inst.components.aoetargeting:SetDeployRadius(0)
                if TheWorld.ismastersim then
                    inst.components.aoetargeting:SetTargetFX(nil)
                    inst.components.aoespell:SetSpellFn(FissureEruptionSpellFn)
                end
            end
        end,
        execute = function(inst)
            local currentstate = GetCurrentState(inst)
            if currentstate == "deactivating" then
                return true
            end
            if currentstate == "active" then
                TriggerInstantSpellbookCast(inst, ACTIONS.CAST_SPELLBOOK)
                return
            end
            StartAOETargeting(inst)
        end,
        atlas = "images/waxwell/waxwell_codex_icon.xml",
        normal = "codex_umbra_fissure_eruption.tex",
        widget_scale = V.FISSURE_ERUPTION_ICON_SCALE,
        hit_radius = V.FISSURE_ERUPTION_ICON_RADIUS,
    }

    return SpellIcon.BindToggleSpellItem(
        item,
        function(u)
            return GetFissureEruptionSpellState(u)
        end,
        function(u)
            return GetFissureEruptionCooldownPercent(u)
        end,
        function(u)
            return GetFissureEruptionActiveDurationPercent(u)
        end
    )
end

return {
    FISSURE_ERUPTION_SPELL = V.FISSURE_ERUPTION_SPELL,
    FISSURE_ERUPTION_COOLDOWN_ID = V.FISSURE_ERUPTION_COOLDOWN_ID,
    FISSURE_ERUPTION_COOLDOWN_TIME = V.FISSURE_ERUPTION_COOLDOWN_TIME,
    FISSURE_ERUPTION_DURABILITY_COST_PCT = V.FISSURE_ERUPTION_DURABILITY_COST_PCT,
    IsFissureEruptionSkillActive = IsFissureEruptionSkillActive,
    GetFissureEruptionSpellState = GetFissureEruptionSpellState,
    GetFissureEruptionSpellData = GetFissureEruptionSpellData,
    GetFissureEruptionSanityCost = GetFissureEruptionSanityCost,
    RequestFissureEruptionDeactivate = RequestFissureEruptionDeactivate,
    OnFissureEruptionEnded = OnFissureEruptionEnded,
    IsFissureEruptionPlacementValid = IsFissureEruptionPlacementValid,
    IsFriendlyOrSummonedTarget = IsFriendlyOrSummonedTarget,
    PushSpellRefresh = PushSpellRefresh,
}
