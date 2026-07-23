-- Custom Fissure Eruption sinkhole — copied collapse timing from antlion_sinkhole,
-- no structure destroy, planar damage pulses, toggle end → ErodeAway → CD on remove.
local V = require("skill_effect/waxwell/emperor/fissure_eruption/variables")
local targeting_rules = require("skill_effect/_shared/targeting_rules")

local assets =
{
    Asset("ANIM", "anim/antlion_sinkhole.zip"),
}

local prefabs =
{
    "waxwell_fissure_eruption_dust_fx",
    "shadow_despawn",
}

local NUM_CRACKING_STAGES = V.FISSURE_ERUPTION_COLLAPSE_STAGES or 3
local COLLAPSE_STAGE_DURATION = V.FISSURE_ERUPTION_COLLAPSE_STAGE_DURATION or 1

local DAMAGE_EXCLUDE_TAGS = { "INLIMBO", "FX", "NOCLICK", "DECOR", "playerghost", "flying", "bird", "ghost", "structure", "wall" }

-- =============================================================================
-- Private helpers
-- =============================================================================

local function GetFissureCommon()
    return require("skill_effect/waxwell/emperor/fissure_eruption/common")
end

local function ApplyVisualStyle(inst)
    local scale = V.FISSURE_ERUPTION_VISUAL_SCALE or 2
    local tint = V.FISSURE_ERUPTION_TINT or .10
    inst.Transform:SetScale(scale, scale, scale)
    inst.AnimState:SetMultColour(tint, tint, tint, 1)
end

local function IsPVPEnabled()
    return TheNet ~= nil and TheNet:GetPVPEnabled()
end

-- unevenground slows every player in the radius (including caster) — never use it for FE.
local function DisableUnevenGround(inst)
    if inst.components.unevenground ~= nil then
        inst.components.unevenground:Disable()
    end
end

local function UpdateOverrideSymbols(inst, state)
    if state == nil then
        return
    end
    if state >= NUM_CRACKING_STAGES then
        inst.AnimState:ClearOverrideSymbol("cracks1")
    else
        inst.AnimState:OverrideSymbol("cracks1", "antlion_sinkhole", "cracks_pre"..tostring(state))
    end
    DisableUnevenGround(inst)
end

local function BelongsToOwner(ent, owner)
    if ent == nil or owner == nil then
        return false
    end
    if ent == owner then
        return true
    end
    if owner.components ~= nil then
        if owner.components.petleash ~= nil and owner.components.petleash:IsPet(ent) then
            return true
        end
        if owner.components.combat ~= nil and owner.components.combat:IsAlly(ent) then
            return true
        end
    end
    local follower = ent.components ~= nil and ent.components.follower or nil
    local leader = follower ~= nil and follower:GetLeader() or nil
    if leader == owner then
        return true
    end
    return false
end

-- Slow enemies always. Never slow caster / own summons / own allies.
-- Non-PvP: also never slow any player or other players' friends/summons.
-- PvP: slow other players and their summons/friends/allies.
local function ShouldSlowTarget(ent, owner, pvp_enabled, common)
    if ent == nil or not ent:IsValid() or ent.components == nil or ent.components.locomotor == nil then
        return false
    end
    if BelongsToOwner(ent, owner) then
        return false
    end
    if ent:HasTag("structure") or ent:HasTag("wall") then
        return false
    end

    local is_player_aligned = ent:HasTag("player")
        or (common.IsFriendlyOrSummonedTarget ~= nil and common.IsFriendlyOrSummonedTarget(ent))

    if not pvp_enabled then
        return not is_player_aligned
    end

    -- PvP: own side already excluded; slow other players / their aligned units / mobs.
    return true
end

local function SpawnDustFx(inst, dust_scale)
    local x, y, z = inst.Transform:GetWorldPosition()
    local radius = 1.6 * (V.FISSURE_ERUPTION_VISUAL_SCALE or 2)
    local theta = math.random() * TWOPI
    local num = 7
    local dtheta = TWOPI / num
    local center = SpawnPrefab("waxwell_fissure_eruption_dust_fx")
    if center ~= nil then
        center.Transform:SetPosition(x, y, z)
    end
    for i = 1, num do
        local dust = SpawnPrefab("waxwell_fissure_eruption_dust_fx")
        if dust ~= nil then
            local s = (dust_scale or .8)
            dust.Transform:SetPosition(
                x + math.cos(theta) * radius * (1 + math.random() * .1),
                0,
                z - math.sin(theta) * radius * (1 + math.random() * .1)
            )
            local flip = (i % 2 == 0) and -1 or 1
            local visual = (V.FISSURE_ERUPTION_VISUAL_SCALE or 2) * (s + math.random() * .2)
            dust.Transform:SetScale(flip * visual, visual, visual)
        end
        theta = theta + dtheta
    end
    if inst.SoundEmitter ~= nil then
        local stage = inst.collapsestage or 1
        inst.SoundEmitter:PlaySoundWithParams(
            "dontstarve/creatures/together/antlion/sfx/ground_break",
            { size = math.pow(stage / NUM_CRACKING_STAGES, 2) }
        )
    end
end

local function ClearEnemySlows(inst)
    if inst._slowed_ents == nil then
        return
    end
    for ent in pairs(inst._slowed_ents) do
        if ent ~= nil and ent:IsValid() and ent.components ~= nil and ent.components.locomotor ~= nil then
            ent.components.locomotor:RemoveExternalSpeedMultiplier(ent, V.FISSURE_ERUPTION_SLOW_KEY)
        end
    end
    inst._slowed_ents = {}
end

local function UpdateEnemySlows(inst)
    if inst == nil or not inst:IsValid() or inst._ending or not inst._active then
        return
    end

    DisableUnevenGround(inst)

    local radius = inst.radius or V.FISSURE_ERUPTION_WORK_RADIUS
    local x, _, z = inst.Transform:GetWorldPosition()
    local common = GetFissureCommon()
    local pvp_enabled = IsPVPEnabled()
    local owner = inst.owner
    local seen = {}
    local ents = TheSim:FindEntities(x, 0, z, radius, { "locomotor" }, { "INLIMBO", "FX", "playerghost", "flying" })
    for _, ent in ipairs(ents) do
        if ShouldSlowTarget(ent, owner, pvp_enabled, common) then
            if ent.components.carefulwalker ~= nil then
                ent:PushEvent("unevengrounddetected", {
                    inst = inst,
                    radius = radius,
                    period = V.FISSURE_ERUPTION_SLOW_PERIOD or .35,
                })
            else
                seen[ent] = true
                if inst._slowed_ents[ent] == nil then
                    ent.components.locomotor:SetExternalSpeedMultiplier(ent, V.FISSURE_ERUPTION_SLOW_KEY, V.FISSURE_ERUPTION_SLOW_MULT)
                    inst._slowed_ents[ent] = true
                end
            end
        end
    end

    local to_clear
    for ent in pairs(inst._slowed_ents) do
        if seen[ent] ~= true then
            to_clear = to_clear or {}
            table.insert(to_clear, ent)
        end
    end
    if to_clear ~= nil then
        for _, ent in ipairs(to_clear) do
            if ent ~= nil and ent:IsValid() and ent.components ~= nil and ent.components.locomotor ~= nil then
                ent.components.locomotor:RemoveExternalSpeedMultiplier(ent, V.FISSURE_ERUPTION_SLOW_KEY)
            end
            inst._slowed_ents[ent] = nil
        end
    end
end

local ScheduleShadowBurst

local function GetShadowBurstDelay()
    local min_delay = V.FISSURE_ERUPTION_SHADOW_FX_DELAY_MIN or .75
    local max_delay = V.FISSURE_ERUPTION_SHADOW_FX_DELAY_MAX or min_delay
    return min_delay + math.random() * math.max(0, max_delay - min_delay)
end

local function IsFarEnoughFromBurst(pos, positions)
    local spacing = V.FISSURE_ERUPTION_SHADOW_FX_MIN_SPACING or 2.75
    local spacing_sq = spacing * spacing
    for _, other in ipairs(positions) do
        local dx = pos.x - other.x
        local dz = pos.z - other.z
        if dx * dx + dz * dz < spacing_sq then
            return false
        end
    end
    return true
end

local function GetRandomShadowBurstPosition(x, z, radius, positions)
    for _ = 1, 32 do
        local theta = math.random() * TWOPI
        local r = math.sqrt(math.random()) * radius
        local pos = Vector3(x + math.cos(theta) * r, 0, z - math.sin(theta) * r)
        if IsFarEnoughFromBurst(pos, positions) then
            return pos
        end
    end
    return nil
end

local function SpawnShadowBurst(inst)
    if inst == nil or not inst:IsValid() or inst._ending then
        return
    end
    local radius = (inst.radius or V.FISSURE_ERUPTION_WORK_RADIUS) - (V.FISSURE_ERUPTION_SHADOW_FX_EDGE_PADDING or 1.35)
    if radius <= 0 then
        return
    end
    local x, _, z = inst.Transform:GetWorldPosition()
    local min_count = V.FISSURE_ERUPTION_SHADOW_FX_COUNT_MIN or 1
    local max_count = V.FISSURE_ERUPTION_SHADOW_FX_COUNT_MAX or min_count
    local count = math.random(min_count, math.max(min_count, max_count))
    local positions = {}
    for _ = 1, count do
        local pos = GetRandomShadowBurstPosition(x, z, radius, positions)
        if pos ~= nil then
            table.insert(positions, pos)
            local fx = SpawnPrefab("shadow_despawn")
            if fx ~= nil then
                fx.Transform:SetPosition(pos.x, 0, pos.z)
            end
        end
    end
    ScheduleShadowBurst(inst)
end

ScheduleShadowBurst = function(inst)
    if inst ~= nil and inst:IsValid() and not inst._ending then
        inst._shadow_task = inst:DoTaskInTime(GetShadowBurstDelay(), SpawnShadowBurst)
    end
end

local function DealStageDamage(inst)
    local stage = inst.collapsestage or 1
    local dmg = V.FISSURE_ERUPTION_DAMAGE[stage]
    if dmg == nil then
        return
    end

    local radius = inst.radius or V.FISSURE_ERUPTION_WORK_RADIUS
    local x, _, z = inst.Transform:GetWorldPosition()
    local common = GetFissureCommon()
    local attacker = (inst.owner ~= nil and inst.owner:IsValid()) and inst.owner or inst
    local ents = TheSim:FindEntities(x, 0, z, radius, { "_combat" }, DAMAGE_EXCLUDE_TAGS)

    for _, ent in ipairs(ents) do
        if targeting_rules.IsEntityAllowed(ent, {
            name = "fissure_eruption_pulse",
            must_tags = { "_combat" },
            blacklist_tags = DAMAGE_EXCLUDE_TAGS,
            extra_check = function(target)
                return target:IsValid()
                    and target.components ~= nil
                    and target.components.combat ~= nil
                    and target.components.health ~= nil
                    and not target.components.health:IsDead()
                    and not (common.IsFriendlyOrSummonedTarget ~= nil and common.IsFriendlyOrSummonedTarget(target))
                    and target.components.combat:CanBeAttacked(attacker)
            end,
        }) then
            -- Stage 1 mirrors vanilla: skip locomotor on first pulse? Plan says all 3 pulses hit enemies.
            -- Spec: damage 3 times with increasing dmg — hit all combatants each pulse.
            ent.components.combat:GetAttacked(attacker, dmg.normal, nil, nil, { planar = dmg.planar })
        end
    end
end

local function DoNextCollapse(inst)
    if inst == nil or not inst:IsValid() or inst._ending then
        return
    end

    inst.collapsestage = (inst.collapsestage or 0) + 1
    local isfinal = inst.collapsestage >= NUM_CRACKING_STAGES

    if isfinal then
        if inst.collapsetask ~= nil then
            inst.collapsetask:Cancel()
            inst.collapsetask = nil
        end
        inst:RemoveTag("scarytoprey")
        ShakeAllCameras(CAMERASHAKE.FULL, COLLAPSE_STAGE_DURATION, .03, .15, inst, (inst.radius or 10) * 2)
        UpdateOverrideSymbols(inst, inst.collapsestage)
        SpawnDustFx(inst, .8)
        DealStageDamage(inst)
        DisableUnevenGround(inst)
        return
    end

    ShakeAllCameras(CAMERASHAKE.FULL, COLLAPSE_STAGE_DURATION, .015, .15, inst, (inst.radius or 10) * 1.5)
    UpdateOverrideSymbols(inst, inst.collapsestage)
    SpawnDustFx(inst, .8)
    DealStageDamage(inst)
end

local function StartCollapse(inst)
    inst.collapsestage = 0
    inst:AddTag("scarytoprey")
    if inst.collapsetask ~= nil then
        inst.collapsetask:Cancel()
    end
    inst.collapsetask = inst:DoPeriodicTask(COLLAPSE_STAGE_DURATION, DoNextCollapse)
    DoNextCollapse(inst)
end

local function NotifyOwnerEnded(inst)
    if inst._cd_notified then
        return
    end
    inst._cd_notified = true
    local owner = inst.owner
    local common = GetFissureCommon()
    if common.OnFissureEruptionEnded ~= nil then
        common.OnFissureEruptionEnded(owner)
    end
end

local DetachOwnerListeners
local BeginEnd

DetachOwnerListeners = function(inst)
    local owner = inst.owner
    if owner == nil then
        return
    end
    if inst._owner_onremove ~= nil then
        inst:RemoveEventCallback("onremove", inst._owner_onremove, owner)
        inst._owner_onremove = nil
    end
    if inst._owner_death ~= nil then
        inst:RemoveEventCallback("death", inst._owner_death, owner)
        inst._owner_death = nil
    end
end

BeginEnd = function(inst, reason)
    if inst == nil or not inst:IsValid() or inst._ending then
        return
    end

    inst._ending = true
    inst._active = false
    inst._end_reason = reason

    if inst.collapsetask ~= nil then
        inst.collapsetask:Cancel()
        inst.collapsetask = nil
    end
    if inst._slow_task ~= nil then
        inst._slow_task:Cancel()
        inst._slow_task = nil
    end
    if inst._shadow_task ~= nil then
        inst._shadow_task:Cancel()
        inst._shadow_task = nil
    end
    if inst._lifetime_task ~= nil then
        inst._lifetime_task:Cancel()
        inst._lifetime_task = nil
    end
    if inst.components.timer ~= nil and inst.components.timer:TimerExists(V.FISSURE_ERUPTION_LIFETIME_TIMER) then
        inst.components.timer:StopTimer(V.FISSURE_ERUPTION_LIFETIME_TIMER)
    end

    ClearEnemySlows(inst)

    DisableUnevenGround(inst)

    DetachOwnerListeners(inst)

    -- Keep owner cache until onremove so wheel shows "deactivating" while eroding.
    if GetFissureCommon().PushSpellRefresh ~= nil then
        GetFissureCommon().PushSpellRefresh(inst.owner)
    end

    inst.persists = false
    ErodeAway(inst)
end

local function AttachOwnerListeners(inst, owner)
    DetachOwnerListeners(inst)
    if owner == nil then
        return
    end
    inst._owner_onremove = function()
        BeginEnd(inst, "owner_removed")
    end
    inst._owner_death = function()
        BeginEnd(inst, "owner_death")
    end
    inst:ListenForEvent("onremove", inst._owner_onremove, owner)
    inst:ListenForEvent("death", inst._owner_death, owner)
end

-- =============================================================================
-- Public API on instance
-- =============================================================================

local function Activate(inst, owner, pos, radius)
    inst.owner = owner
    inst._owner_userid = owner ~= nil and owner.userid or nil
    inst.radius = radius or V.FISSURE_ERUPTION_WORK_RADIUS
    inst._active = true
    inst._ending = false
    inst._cd_notified = false
    inst._slowed_ents = {}

    if pos ~= nil then
        inst.Transform:SetPosition(pos.x, 0, pos.z)
    end

    if inst.components.unevenground ~= nil then
        inst.components.unevenground.radius = inst.radius
    end
    DisableUnevenGround(inst)

    AttachOwnerListeners(inst, owner)
    StartCollapse(inst)

    inst._slow_task = inst:DoPeriodicTask(V.FISSURE_ERUPTION_SLOW_PERIOD or .35, UpdateEnemySlows)
    ScheduleShadowBurst(inst)
    local duration = V.FISSURE_ERUPTION_DURATION or 20
    if inst.components.timer ~= nil then
        inst.components.timer:StartTimer(V.FISSURE_ERUPTION_LIFETIME_TIMER, duration)
    end
    inst._lifetime_task = inst:DoTaskInTime(duration, function()
        BeginEnd(inst, "expired")
    end)
end

local function RequestDeactivate(inst, reason)
    BeginEnd(inst, reason or "manual")
end

local function RebindOwner(inst, owner)
    inst.owner = owner
    if owner ~= nil then
        owner._waxwell_fissure_eruption_sinkhole = inst
        inst._owner_userid = owner.userid
        AttachOwnerListeners(inst, owner)
    end
end

-- =============================================================================
-- Prefab
-- =============================================================================

local function OnRemove(inst)
    ClearEnemySlows(inst)
    DetachOwnerListeners(inst)
    local owner = inst.owner
    if owner ~= nil and owner._waxwell_fissure_eruption_sinkhole == inst then
        owner._waxwell_fissure_eruption_sinkhole = nil
    end
    NotifyOwnerEnded(inst)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("sinkhole")
    inst.AnimState:SetBuild("antlion_sinkhole")
    inst.AnimState:PlayAnimation("idle")
    inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    inst.AnimState:SetLayer(LAYER_BACKGROUND)
    inst.AnimState:SetSortOrder(2)

    ApplyVisualStyle(inst)
    inst.Transform:SetEightFaced()

    inst:AddTag("NOCLICK")
    inst:AddTag("fissure_eruption_sinkhole")
    -- Do not add antlion_sinkhole_blocker — would block unrelated systems broadly.

    inst:AddComponent("timer")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false
    inst.radius = V.FISSURE_ERUPTION_WORK_RADIUS
    inst._active = false
    inst._ending = false
    inst.owner = nil
    inst._owner_userid = nil
    inst._slowed_ents = {}
    inst.collapsestage = 0

    inst:AddComponent("unevenground")
    inst.components.unevenground.radius = V.FISSURE_ERUPTION_WORK_RADIUS
    inst.components.unevenground:Disable()

    inst.Activate = Activate
    inst.RequestDeactivate = RequestDeactivate
    inst.RebindOwner = RebindOwner

    inst:ListenForEvent("onremove", OnRemove)

    return inst
end

return Prefab("waxwell_fissure_eruption_sinkhole", fn, assets, prefabs)
