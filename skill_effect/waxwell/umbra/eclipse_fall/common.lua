local spell_categories = require("skill_effect/waxwell/_shared/spell_categories")
local spell_utils = require("skill_effect/waxwell/_shared/codex_spell_utils")
local shared = require("skill_effect/waxwell/umbra/_shared/cast_common")
local dark_scholar = require("skill_effect/waxwell/umbra/dark_scholar/common")
local ReticuleUtils = require("reticule/utils")
local V = require("skill_effect/waxwell/umbra/eclipse_fall/variables")

local SpellCost = shared.SpellCost
local IsFriendlyOrSummonedTarget = shared.IsFriendlyOrSummonedTarget
local IsSpellOnCooldown = shared.IsSpellOnCooldown
local GetSpellCooldownPercent = shared.GetSpellCooldownPercent
local RestartSpellCooldown = shared.RestartSpellCooldown
local StartAOETargeting = shared.StartAOETargeting
local IsDarkScholarActive = dark_scholar.IsDarkScholarActive

local METEOR_RADIUS = TUNING.METEOR_RADIUS or 3.5
local LARGE_IMPACT_RADIUS = V.ECLIPSE_FALL_VANILLA_LARGE_SIZE * METEOR_RADIUS * V.ECLIPSE_FALL_LARGE_SIZE_MULT
local RANDOM_CAST_RADIUS = V.ECLIPSE_FALL_RETICULE_WORK_RADIUS

local LaunchEclipseFallIceSpikes

--//////////////////// Skill state
local function IsEclipseFall1Active(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_eclipse_fall_1"))
            or inst:HasTag("eclipse_fall_1_active")
        )
end

local function IsEclipseFall2Active(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_eclipse_fall_2"))
            or inst:HasTag("eclipse_fall_2_active")
        )
end

local function IsEclipseFallSkillActive(inst)
    return IsEclipseFall1Active(inst) or IsEclipseFall2Active(inst)
end

local function GetEclipseFallDurabilityCostPct(inst)
    return V.ECLIPSE_FALL_DURABILITY_COST_PCT
        + (IsEclipseFall2Active(inst) and V.ECLIPSE_FALL_LV2_EXTRA_DURABILITY_COST_PCT or 0)
end

local function IsEclipseFallOnCooldown(doer)
    return IsSpellOnCooldown(doer, V.ECLIPSE_FALL_COOLDOWN_ID)
end

local function GetEclipseFallCooldownPercent(doer)
    return GetSpellCooldownPercent(doer, V.ECLIPSE_FALL_COOLDOWN_ID)
end

--//////////////////// Damage scaling
local function GetEclipseFallSpentSanity(doer)
    local sanity = doer ~= nil and doer.components ~= nil and doer.components.sanity or nil
    return sanity ~= nil and math.max(0, sanity.current or 0) or 0
end

local function GetEclipseFallSanityCost(doer)
    local spent_sanity = GetEclipseFallSpentSanity(doer)
    if spent_sanity <= 0 then
        return 0
    end

    if IsDarkScholarActive(doer) then
        return spent_sanity - math.floor(spent_sanity * V.ECLIPSE_FALL_DARK_SCHOLAR_SANITY_DISCOUNT)
    end

    return spent_sanity
end

local function GetEclipseFallDamagePerSanity(doer)
    return V.ECLIPSE_FALL_DAMAGE_PER_SANITY
end

local function GetEclipseFallSanityMult(doer, spent_sanity)
    return 1 + math.max(0, spent_sanity or 0) * GetEclipseFallDamagePerSanity(doer)
end

local function ResolveEclipseFallDamage(doer, base_damage, sanity_mult)
    return math.ceil((base_damage or 0) * (sanity_mult or 1))
end

local function ApplyEclipseMeteorVisualScale(meteor, visual_scale)
    if meteor == nil or visual_scale == nil then
        return
    end

    meteor.Transform:SetScale(visual_scale, visual_scale, visual_scale)
    if meteor.warnshadow ~= nil and meteor.warnshadow:IsValid() then
        -- warnshadow is parented to meteor — local scale must stay 1 to avoid double scaling.
        meteor.warnshadow.Transform:SetScale(1, 1, 1)
    end
end

--//////////////////// Meteor spawn / impact
local function ApplyEclipseMeteorTint(meteor)
    if meteor == nil then
        return
    end

    local tint = V.ECLIPSE_FALL_METEOR_TINT_MULT
    if meteor.AnimState ~= nil then
        meteor.AnimState:SetMultColour(tint, tint, tint, 1)
    end

    if meteor.warnshadow ~= nil and meteor.warnshadow:IsValid() and meteor.warnshadow.AnimState ~= nil then
        meteor.warnshadow.AnimState:SetMultColour(tint, tint, tint, 1)
    end
end

local function SpawnShortLivedBurntGround(x, z, scale)
    local scorch = SpawnPrefab("eclipse_burntground")
    if scorch ~= nil then
        scorch.Transform:SetPosition(x, 0, z)
        scorch.Transform:SetScale(scale, scale, scale)
    end
end

local function DoEclipseMeteorImpact(meteor, attacker, damage, radius, scorch_scale, shake_size, opts)
    if meteor == nil or not meteor:IsValid() then
        return
    end

    opts = opts or {}

    local x, _, z = meteor.Transform:GetWorldPosition()

    if meteor.warnshadow ~= nil and meteor.warnshadow:IsValid() then
        meteor.warnshadow:Remove()
        meteor.warnshadow = nil
    end

    if meteor.SoundEmitter ~= nil then
        meteor.SoundEmitter:PlaySound("dontstarve/common/meteor_impact", nil, V.ECLIPSE_FALL_SOUND_VOLUME)
    end

    ShakeAllCameras(CAMERASHAKE.FULL, .7 * shake_size, .02 * shake_size, .5 * shake_size, meteor, 40 * shake_size)

    local chunks = SpawnPrefab("eclipse_ground_chunks_breaking")
    if chunks ~= nil then
        chunks.Transform:SetPosition(x, 0, z)
    end

    if meteor:IsOnValidGround() then
        SpawnShortLivedBurntGround(x, z, scorch_scale)
    else
        local splash = SpawnPrefab("splash_ocean")
        if splash ~= nil then
            splash.Transform:SetPosition(x, 0, z)
        end
    end

    if TheWorld.ismastersim then
        local damage_source = attacker ~= nil and attacker:IsValid() and attacker or meteor
        local ents = TheSim:FindEntities(x, 0, z, radius, { "_combat" }, V.IMPACT_EXCLUDE_TAGS)
        local targeting_rules = require("skill_effect/_shared/targeting_rules")
        for _, ent in ipairs(ents) do
            if targeting_rules.IsEntityAllowed(ent, {
                name = "eclipse_fall_impact",
                must_tags = { "_combat" },
                blacklist_tags = V.IMPACT_EXCLUDE_TAGS,
                extra_check = function(target)
                    return target:IsValid()
                        and target.components ~= nil
                        and target.components.combat ~= nil
                        and target.components.health ~= nil
                        and not target.components.health:IsDead()
                        and not IsFriendlyOrSummonedTarget(target)
                end,
            }) then
                if ent.components ~= nil and ent.components.combat ~= nil then
                    ent.components.combat:GetAttacked(damage_source, damage)
                end
            end
        end
    end

    if opts.spawn_lv2_spikes and attacker ~= nil and attacker:IsValid() then
        local impact_pos = Vector3(x, 0, z)
        LaunchEclipseFallIceSpikes(attacker, impact_pos)
    end

    meteor:Remove()
end

local function TriggerEclipseMeteorStrike(meteor, attacker, damage, radius, scorch_scale, shake_size, opts)
    if meteor == nil or not meteor:IsValid() then
        return
    end

    meteor.striketask = nil
    meteor.AnimState:PlayAnimation("crash")
    meteor:DoTaskInTime(V.ECLIPSE_FALL_STRIKE_ANIM_DELAY, function(inst)
        DoEclipseMeteorImpact(inst, attacker, damage, radius, scorch_scale, shake_size, opts)
    end)
    meteor:ListenForEvent("animover", meteor.Remove)
    meteor:DoTaskInTime(3, meteor.Remove)
end

-- size_key: "small" or "large"
local function SpawnEclipseMeteor(attacker, targetpos, size_key, damage, opts)
    opts = opts or {}
    if targetpos == nil then
        return nil
    end

    local meteor = SpawnPrefab("shadowmeteor")
    if meteor == nil then
        return nil
    end

    if meteor.autosizetask ~= nil then
        meteor.autosizetask:Cancel()
        meteor.autosizetask = nil
    end

    if meteor.SetSize ~= nil then
        meteor:SetSize(size_key == "large" and "large" or "small")
    end

    -- SetSize schedules the vanilla strike (spawns loot / vanilla damage); drop it and use ours.
    if meteor.striketask ~= nil then
        meteor.striketask:Cancel()
        meteor.striketask = nil
    end

    local base_size = meteor.size or (size_key == "large" and V.ECLIPSE_FALL_VANILLA_LARGE_SIZE or .7)
    local visual_scale = base_size
    local radius
    local scorch_scale
    local shake_size

    if size_key == "large" then
        visual_scale = base_size * V.ECLIPSE_FALL_LARGE_SIZE_MULT
        radius = LARGE_IMPACT_RADIUS
        scorch_scale = base_size * V.ECLIPSE_FALL_SCORCH_VANILLA_MULT * V.ECLIPSE_FALL_LARGE_SIZE_MULT * V.ECLIPSE_FALL_LARGE_SCORCH_MULT
        shake_size = base_size * V.ECLIPSE_FALL_LARGE_SHAKE_MULT
        ApplyEclipseMeteorVisualScale(meteor, visual_scale)
    else
        visual_scale = base_size * V.ECLIPSE_FALL_SMALL_SIZE_MULT
        radius = base_size * METEOR_RADIUS * V.ECLIPSE_FALL_SMALL_SIZE_MULT
        scorch_scale = base_size * V.ECLIPSE_FALL_SCORCH_VANILLA_MULT * V.ECLIPSE_FALL_SMALL_SIZE_MULT
        shake_size = base_size
        ApplyEclipseMeteorVisualScale(meteor, visual_scale)
    end

    local strike_opts = opts.strike_opts

    ApplyEclipseMeteorTint(meteor)
    meteor.Transform:SetPosition(targetpos.x, 0, targetpos.z)
    meteor.striketask = meteor:DoTaskInTime(V.ECLIPSE_FALL_WARN_TIME, function(inst)
        TriggerEclipseMeteorStrike(inst, attacker, damage, radius, scorch_scale, shake_size, strike_opts)
    end)

    return meteor
end

--//////////////////// Lv2 ice spikes (8 directions × 5 tiers)
local function DoEclipseFallSpikeImpact(attacker, pos)
    if not TheWorld.ismastersim or pos == nil then
        return
    end

    local damage_source = attacker ~= nil and attacker:IsValid() and attacker or nil
    if damage_source == nil then
        return
    end

    local radius = V.ECLIPSE_FALL_SPIKE_IMPACT_RADIUS
    local ents = TheSim:FindEntities(pos.x, 0, pos.z, radius, { "_combat" }, V.IMPACT_EXCLUDE_TAGS)
    local targeting_rules = require("skill_effect/_shared/targeting_rules")
    for _, ent in ipairs(ents) do
        if targeting_rules.IsEntityAllowed(ent, {
            name = "eclipse_fall_spike_impact",
            must_tags = { "_combat" },
            blacklist_tags = V.IMPACT_EXCLUDE_TAGS,
            extra_check = function(target)
                return target:IsValid()
                    and target.components ~= nil
                    and target.components.combat ~= nil
                    and target.components.health ~= nil
                    and not target.components.health:IsDead()
                    and not IsFriendlyOrSummonedTarget(target)
            end,
        }) then
            if ent.components ~= nil and ent.components.combat ~= nil then
                ent.components.combat:GetAttacked(damage_source, V.ECLIPSE_FALL_SPIKE_DAMAGE)
            end
        end
    end
end

local function SpawnEclipseFallIceSpike(attacker, pos, angle, play_sound)
    if pos == nil then
        return
    end

    local fx = SpawnPrefab("deerclops_icespike_fx")
    if fx == nil then
        return
    end

    fx.Transform:SetPosition(pos.x, 0, pos.z)
    fx.Transform:SetRotation(angle * RADIANS)
    if fx.AnimState ~= nil then
        local tint = V.ECLIPSE_FALL_SPIKE_TINT_MULT
        fx.AnimState:SetMultColour(tint, tint, tint, 1)
    end
    if fx.RestartFX ~= nil then
        fx:RestartFX(false, math.random(4))
    end

    if play_sound and fx.SoundEmitter ~= nil then
        fx.SoundEmitter:PlaySound(
            "dontstarve/creatures/deerclops/attack",
            nil,
            V.ECLIPSE_FALL_SPIKE_SOUND_VOLUME
        )
    end

    DoEclipseFallSpikeImpact(attacker, pos)
end

local function BuildEclipseFallSpikePattern(center)
    local pattern = {}
    local startangle = math.random() * TWOPI
    local halfspread = V.ECLIPSE_FALL_SPIKE_ANGLE_SPREAD * .5

    for dir = 1, V.ECLIPSE_FALL_SPIKE_DIRECTION_COUNT do
        local baseangle = startangle + ((dir - 1) / V.ECLIPSE_FALL_SPIKE_DIRECTION_COUNT) * TWOPI
        for tier = 1, V.ECLIPSE_FALL_SPIKE_TIER_COUNT do
            local angle = baseangle + (math.random() * 2 - 1) * halfspread
            local distance = V.ECLIPSE_FALL_SPIKE_TIER_DISTANCES[tier] or V.ECLIPSE_FALL_SPIKE_TIER_DISTANCES[#V.ECLIPSE_FALL_SPIKE_TIER_DISTANCES]
            local delay = V.ECLIPSE_FALL_SPIKE_TIER_DELAYS[tier] or 0
            table.insert(pattern, {
                delay = delay,
                pos = Vector3(
                    center.x + math.cos(angle) * distance,
                    0,
                    center.z + math.sin(angle) * distance
                ),
                angle = angle,
                play_sound = tier == 1,
            })
        end
    end

    return pattern
end

LaunchEclipseFallIceSpikes = function(attacker, center)
    if attacker == nil or not attacker:IsValid() or center == nil or not TheWorld.ismastersim then
        return
    end

    local pattern = BuildEclipseFallSpikePattern(center)
    for _, entry in ipairs(pattern) do
        attacker:DoTaskInTime(entry.delay, function(inst)
            if inst ~= nil and inst:IsValid() then
                SpawnEclipseFallIceSpike(inst, entry.pos, entry.angle, entry.play_sound)
            end
        end)
    end
end

--//////////////////// Launch pattern
local function GetRandomPointInCircle(center, radius)
    local angle = math.random() * TWOPI
    local dist = math.sqrt(math.random()) * radius
    return Vector3(center.x + math.cos(angle) * dist, 0, center.z + math.sin(angle) * dist)
end

local function LaunchEclipseFall(attacker, center, sanity_mult)
    if attacker == nil or center == nil then
        return
    end

    local small_damage = ResolveEclipseFallDamage(attacker, V.ECLIPSE_FALL_DAMAGE_SMALL, sanity_mult)
    local count = V.ECLIPSE_FALL_SMALL_COUNT
    local step = V.ECLIPSE_FALL_SMALL_DURATION / count

    for i = 1, count do
        attacker:DoTaskInTime((i - 1) * step, function(inst)
            local pos = GetRandomPointInCircle(center, RANDOM_CAST_RADIUS)
            SpawnEclipseMeteor(inst, pos, "small", small_damage)
        end)
    end

    if IsEclipseFall2Active(attacker) then
        local large_damage = ResolveEclipseFallDamage(attacker, V.ECLIPSE_FALL_DAMAGE_LARGE, sanity_mult)
        attacker:DoTaskInTime(V.ECLIPSE_FALL_LARGE_WARNING_DELAY, function(inst)
            SpawnEclipseMeteor(inst, center, "large", large_damage, {
                strike_opts = { spawn_lv2_spikes = true },
            })
        end)
    end
end

--//////////////////// Cast
local function GetEclipseFallCastBlockReason(inst, doer, pos)
    local cast_costs = require("skill_effect/waxwell/_shared/codex_cast_costs")
    local cost_gate = require("skill_effect/waxwell/_shared/codex_cost_gate")

    cast_costs.EnsureRegistered()
    local resource_block = cost_gate.GetResourceBlockReason(inst, doer, cast_costs.ResolveCastCosts(inst, doer))
    if resource_block ~= nil then
        return resource_block
    elseif not IsEclipseFallSkillActive(doer) then
        return "SKILL_INACTIVE"
    elseif IsEclipseFallOnCooldown(doer) then
        return "SPELL_ON_COOLDOWN"
    elseif pos == nil then
        return "NO_TARGETS"
    end

    return nil
end

local function ShouldRepeatCastEclipseFall(inst, doer)
    return false
end

local function EclipseFallSpellFn(inst, doer, pos)
    local blockreason = GetEclipseFallCastBlockReason(inst, doer, pos)
    if blockreason == "NO_FUEL_EMPTY" or blockreason == "NO_FUEL_COST" then
        return false, "NO_FUEL"
    elseif blockreason == "NO_SANITY" then
        return false, "NO_SANITY"
    elseif blockreason == "SPELL_ON_COOLDOWN" then
        return false, "SPELL_ON_COOLDOWN"
    elseif blockreason == "SKILL_INACTIVE" then
        return false
    elseif blockreason == "NO_TARGETS" then
        return false, "NO_TARGETS"
    elseif blockreason ~= nil then
        return false
    end

    if pos == nil then
        return false, "NO_TARGETS"
    end

    local center = Vector3(pos.x, 0, pos.z)
    local spent_sanity = GetEclipseFallSpentSanity(doer)
    local scale_sanity = math.min(spent_sanity, V.ECLIPSE_FALL_MAX_SANITY_SCALE or 275)
    local sanity_mult = GetEclipseFallSanityMult(doer, scale_sanity)
    local sanity_cost = GetEclipseFallSanityCost(doer)

    inst.components.fueled:DoDelta(SpellCost(GetEclipseFallDurabilityCostPct(doer)), doer)
    if sanity_cost > 0 and doer ~= nil and doer.components ~= nil and doer.components.sanity ~= nil then
        doer.components.sanity:DoDelta(-sanity_cost)
    end
    RestartSpellCooldown(doer, V.ECLIPSE_FALL_COOLDOWN_ID, V.ECLIPSE_FALL_COOLDOWN_TIME)
    LaunchEclipseFall(doer, center, sanity_mult)
    return true
end

local function GetEclipseFallSpellData()
    return {
        spell_id = V.ECLIPSE_FALL_SPELL,
        label = STRINGS.SPELLS[V.ECLIPSE_FALL_SPELL] or "Eclipse Fall",
        onselect = function(inst)
            local player = ThePlayer
            if player ~= nil then
                require("skill_effect/waxwell/umbra/umbral_rift/common").CancelUmbralRiftSkill(player)
            end
            inst.components.spellbook:SetSpellName(STRINGS.SPELLS[V.ECLIPSE_FALL_SPELL] or "Eclipse Fall")
            inst.components.spellbook:SetSpellAction(nil)
            inst.components.aoetargeting:SetAlwaysValid(true)
            inst.components.aoetargeting:SetAllowWater(true)
            inst.components.aoetargeting:SetShouldRepeatCastFn(ShouldRepeatCastEclipseFall)
            ReticuleUtils.ApplySpellReticule(inst, inst.components.aoetargeting, V.ECLIPSE_FALL_RETICULE_SCALE, ReticuleUtils.ANIM_LARGE, {
                cast_range = V.ECLIPSE_FALL_CAST_RANGE,
                validfn = function()
                    return true
                end,
            })
            -- วง reticule ใช้ scale สำหรับแสดงผล/random เท่านั้น — deploy radius ต้องเป็น 0 ไม่งั้น map เช็ค IsDeployPointClear ในวง 8
            inst.components.aoetargeting:SetDeployRadius(0)
            if TheWorld.ismastersim then
                inst.components.aoetargeting:SetTargetFX(nil)
                inst.components.aoespell:SetSpellFn(EclipseFallSpellFn)
                inst.components.spellbook:SetSpellFn(nil)
            end
        end,
        execute = StartAOETargeting,
        atlas = "images/waxwell/waxwell_codex_icon.xml",
        normal = "codex_umbra_eclipse_fall.tex",
        widget_scale = V.ECLIPSE_FALL_ICON_SCALE,
        hit_radius = V.ECLIPSE_FALL_ICON_RADIUS,
        checkcooldown = function(user)
            return GetEclipseFallCooldownPercent(user)
        end,
        cooldowncolor = { .12, .28, .42, .50 },
        cooldownscale = 1.42,
    }
end

return {
    ECLIPSE_FALL_SPELL = V.ECLIPSE_FALL_SPELL,
    ECLIPSE_FALL_COOLDOWN_ID = V.ECLIPSE_FALL_COOLDOWN_ID,
    ECLIPSE_FALL_COOLDOWN_TIME = V.ECLIPSE_FALL_COOLDOWN_TIME,
    ECLIPSE_FALL_DURABILITY_COST_PCT = V.ECLIPSE_FALL_DURABILITY_COST_PCT,
    ECLIPSE_FALL_LV2_EXTRA_DURABILITY_COST_PCT = V.ECLIPSE_FALL_LV2_EXTRA_DURABILITY_COST_PCT,
    IsEclipseFall1Active = IsEclipseFall1Active,
    IsEclipseFall2Active = IsEclipseFall2Active,
    IsEclipseFallSkillActive = IsEclipseFallSkillActive,
    GetEclipseFallDurabilityCostPct = GetEclipseFallDurabilityCostPct,
    GetEclipseFallSpellData = GetEclipseFallSpellData,
}
