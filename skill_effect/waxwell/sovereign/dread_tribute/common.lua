local V = require("skill_effect/waxwell/sovereign/dread_tribute/variables")
local ModConfig = require("mod_config")

local function IsDreadTribute1Active(inst)
    return inst ~= nil
        and inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_dread_tribute_1")
end

local function IsDreadTribute2Active(inst)
    return inst ~= nil
        and inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_dread_tribute_2")
end

local function IsDreadTributeWeapon(inst)
    return inst ~= nil
        and inst.prefab ~= nil
        and V.DREAD_TRIBUTE_WEAPONS[inst.prefab] == true
end

local function GetDreadTributeWeapon(inst, weapon)
    if IsDreadTributeWeapon(weapon) then
        return weapon
    end

    if inst ~= nil
        and inst.components ~= nil
        and inst.components.inventory ~= nil then
        local equipped = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
        if IsDreadTributeWeapon(equipped) then
            return equipped
        end
    end

    return nil
end

local function IsDreadTributeLargeTarget(target)
    return target ~= nil and target:HasAnyTag("largecreature", "epic", "boss")
end

local function GetDreadTributeFlatDotDps(attacker)
    -- LV2 unlocks death explosion only; burn DoT stays at LV1 rates.
    if IsDreadTribute1Active(attacker) or IsDreadTribute2Active(attacker) then
        return V.DREAD_TRIBUTE_1_DOT_DPS
    end

    return nil
end

local function GetDreadTributePercentPerSecond(attacker, target)
    if IsDreadTribute1Active(attacker) or IsDreadTribute2Active(attacker) then
        return IsDreadTributeLargeTarget(target) and V.DREAD_TRIBUTE_1_DOT_PCT_LARGE or V.DREAD_TRIBUTE_1_DOT_PCT
    end

    return nil
end

local function GetDreadTributeBurnDamagePerTick(attacker, target)
    if attacker == nil or target == nil then
        return nil
    end

    if ModConfig.IsDreadTributePercentDamage() then
        local health = target.components ~= nil and target.components.health or nil
        local pct = GetDreadTributePercentPerSecond(attacker, target)
        if health == nil or pct == nil then
            return nil
        end

        return health.currenthealth * pct * 0.01 * V.DREAD_TRIBUTE_TICK
    end

    local dps = GetDreadTributeFlatDotDps(attacker)
    return dps ~= nil and dps * V.DREAD_TRIBUTE_TICK or nil
end

local function GetDreadTributeDotDps(attacker, target)
    if ModConfig.IsDreadTributePercentDamage() then
        local damage = GetDreadTributeBurnDamagePerTick(attacker, target)
        return damage ~= nil and damage / V.DREAD_TRIBUTE_TICK or nil
    end

    return GetDreadTributeFlatDotDps(attacker)
end

local function GetDreadTributeBaseSanityCost(attacker)
    if IsDreadTribute1Active(attacker) or IsDreadTribute2Active(attacker) then
        return V.DREAD_TRIBUTE_1_SANITY_COST
    end

    return nil
end

local function GetDreadTributeBurnRemainingPercent(target)
    local burn = target ~= nil and target._waxwell_dread_tribute_burn or nil
    if burn == nil or burn.endtime == nil then
        return nil
    end

    local remaining = burn.endtime - GetTime()
    if remaining <= 0 then
        return nil
    end

    return remaining / V.DREAD_TRIBUTE_BURN_DURATION
end

local function GetDreadTributeRefreshSanityCost(attacker, target)
    local base_cost = GetDreadTributeBaseSanityCost(attacker)
    if base_cost == nil then
        return nil
    end

    local remaining_pct = GetDreadTributeBurnRemainingPercent(target)
    if remaining_pct == nil then
        return base_cost
    end

    if remaining_pct > .50 then
        return 1
    end
    return 2
end

local function CanAffordDreadTributeHit(attacker, sanity_cost)
    return attacker ~= nil
        and attacker.components ~= nil
        and attacker.components.sanity ~= nil
        and sanity_cost ~= nil
        and attacker.components.sanity.current >= sanity_cost
end

local function IsValidDreadTributeBurnTarget(target)
    return target ~= nil
        and target:IsValid()
        and target.components ~= nil
        and target.components.health ~= nil
        and not target.components.health:IsDead()
end

local FIRE_OFFSET_DEFAULT = Vector3(0, 0, 0.1)

local function GetDreadTributeBurnAttach(target)
    local burnable = target.components ~= nil and target.components.burnable or nil
    local fxdata = burnable ~= nil and burnable.fxdata ~= nil and burnable.fxdata[1] or nil

    local symbol
    local fxlevel
    local offset = FIRE_OFFSET_DEFAULT
    local scale_mult = 1

    if fxdata ~= nil and fxdata.prefab ~= nil then
        fxlevel = burnable.fxlevel or 2
        offset = Vector3(fxdata.x or 0, fxdata.y or 0, fxdata.z or 0)
        scale_mult = fxdata.scale or 1
        symbol = fxdata.follow
    else
        local combat = target.components ~= nil and target.components.combat or nil
        symbol = combat ~= nil and combat.hiteffectsymbol or nil
        if symbol == nil then
            symbol = "swap_fire"
        end

        if target:HasTag("smallcreature") then
            fxlevel = 1
        elseif target:HasAnyTag("largecreature", "epic") then
            fxlevel = 3
        else
            fxlevel = 2
        end
    end

    if burnable ~= nil and burnable.fxoffset ~= nil then
        offset = offset + burnable.fxoffset
    end

    fxlevel = math.clamp(fxlevel or 2, 1, 3)
    return symbol, fxlevel, offset, scale_mult
end

local function KillDreadTributeBurnFX(burn)
    if burn == nil or burn.fx == nil then
        return
    end

    local fx = burn.fx
    burn.fx = nil

    if fx._waxwell_dt_pos_task ~= nil then
        fx._waxwell_dt_pos_task:Cancel()
        fx._waxwell_dt_pos_task = nil
    end

    if fx:IsValid() then
        fx:Remove()
    end
end

-- World-space follow (not FollowSymbol / AddChild).
-- UCM treeguard stomp / root anims swap symbols and can strip children, which
-- made FollowSymbol burn FX vanish mid-burn.
local function AttachDreadTributeBurnFXToTarget(target, fx, offset)
    if fx == nil or target == nil or not target:IsValid() then
        return
    end

    local ox = offset ~= nil and offset.x or 0
    local oy = offset ~= nil and offset.y or 0
    local oz = offset ~= nil and offset.z or 0

    local function UpdateBurnFxPosition()
        if not fx:IsValid() or not target:IsValid() then
            if fx:IsValid() and fx._waxwell_dt_pos_task ~= nil then
                fx._waxwell_dt_pos_task:Cancel()
                fx._waxwell_dt_pos_task = nil
            end
            return
        end

        local x, y, z = target.Transform:GetWorldPosition()
        fx.Transform:SetPosition(x + ox, y + oy, z + oz)
    end

    UpdateBurnFxPosition()
    if fx._waxwell_dt_pos_task ~= nil then
        fx._waxwell_dt_pos_task:Cancel()
    end
    fx._waxwell_dt_pos_task = fx:DoPeriodicTask(0, UpdateBurnFxPosition)
end

local function StopDreadTributeBurn(target)
    if target == nil then
        return
    end

    local burn = target._waxwell_dread_tribute_burn
    if burn == nil then
        return
    end

    target._waxwell_dread_tribute_burn = nil

    if burn.task ~= nil then
        burn.task:Cancel()
        burn.task = nil
    end

    if burn.fx_task ~= nil then
        burn.fx_task:Cancel()
        burn.fx_task = nil
    end

    if burn.onremovefn ~= nil then
        target:RemoveEventCallback("onremove", burn.onremovefn)
        burn.onremovefn = nil
    end

    if burn.ondeathfn ~= nil then
        target:RemoveEventCallback("death", burn.ondeathfn)
        burn.ondeathfn = nil
    end

    KillDreadTributeBurnFX(burn)
end

local DREAD_TRIBUTE_EXPLOSION_EXCLUDE_TAGS = { "INLIMBO", "player", "companion", "wall", "structure", "abigail" }

local function IsDreadTributeExplosionVictim(ent, source)
    if ent == nil
        or not ent:IsValid()
        or ent == source
        or ent.components == nil
        or ent.components.health == nil
        or ent.components.health:IsDead()
        or ent:HasAnyTag("player", "companion", "abigail", "wall", "structure") then
        return false
    end

    if ent.components.follower ~= nil then
        local leader = ent.components.follower:GetLeader()
        if leader ~= nil and leader:HasTag("player") then
            return false
        end
    end

    return ent.components.combat ~= nil
end

local function GetDreadTributeExplosionDamage(target)
    if IsDreadTributeLargeTarget(target) then
        return V.DREAD_TRIBUTE_2_EXPLOSION_DAMAGE_LARGE
    end
    return V.DREAD_TRIBUTE_2_EXPLOSION_DAMAGE
end

local function GetDreadTributeExplosionScaleAndRadius(source)
    if IsDreadTributeLargeTarget(source) then
        return V.DREAD_TRIBUTE_2_EXPLOSION_SCALE_LARGE, V.DREAD_TRIBUTE_2_EXPLOSION_RADIUS_LARGE
    end
    return V.DREAD_TRIBUTE_2_EXPLOSION_SCALE, V.DREAD_TRIBUTE_2_EXPLOSION_RADIUS
end

local function TryDreadTributeDeathExplosion(target, burn)
    if target == nil or not target:IsValid() then
        return
    end

    -- One explosion per corpse (covers burn-death and overkill-without-burn).
    if target._waxwell_dread_tribute_exploded then
        return
    end

    if burn ~= nil and burn.exploded then
        return
    end

    if burn ~= nil then
        burn.exploded = true
    end
    target._waxwell_dread_tribute_exploded = true

    local attacker = burn ~= nil and burn.attacker or nil
    if attacker == nil
        or not attacker:IsValid()
        or not IsDreadTribute2Active(attacker) then
        return
    end

    local x, y, z = target.Transform:GetWorldPosition()
    local scale, radius = GetDreadTributeExplosionScaleAndRadius(target)
    -- Damage keyed to dying source size (same as scale/radius), not victim size.
    local damage = GetDreadTributeExplosionDamage(target)
    local fx = SpawnPrefab("waxwell_dread_tribute_explodefx")
    if fx ~= nil then
        fx.Transform:SetPosition(x, y, z)
        fx.Transform:SetScale(scale, scale, scale)
    end

    local ents = TheSim:FindEntities(x, y, z, radius, nil, DREAD_TRIBUTE_EXPLOSION_EXCLUDE_TAGS)
    for _, ent in ipairs(ents) do
        if IsDreadTributeExplosionVictim(ent, target) then
            -- Direct health delta: skip combat onhitother so explosion does not re-apply burn.
            ent.components.health:DoDelta(-damage, false, "waxwell_dread_tribute_explode", false, attacker, true)
        end
    end
end

local function SpawnDreadTributeBurnFX(target)
    local fx = SpawnPrefab("waxwell_dread_tribute_burnfx")
    if fx == nil or target == nil or not target:IsValid() then
        return nil
    end

    local symbol, fxlevel, offset, scale_mult = GetDreadTributeBurnAttach(target)
    local scale = target.Transform:GetScale() * scale_mult
    fx.Transform:SetScale(scale, scale, scale)
    fx.persists = false

    AttachDreadTributeBurnFXToTarget(target, fx, offset)

    if fx.components ~= nil and fx.components.firefx ~= nil then
        fx.components.firefx:SetLevel(fxlevel, true)
        if fx.components.firefx.light ~= nil and fx.components.firefx.light.Light ~= nil then
            fx.components.firefx.light.Light:Enable(false)
        end
    end

    return fx
end

local function EnsureDreadTributeBurnFX(target, burn)
    if burn == nil then
        return
    end

    if burn.fx == nil or not burn.fx:IsValid() then
        KillDreadTributeBurnFX(burn)
        burn.fx = SpawnDreadTributeBurnFX(target)
    elseif burn.fx.components ~= nil and burn.fx.components.firefx ~= nil then
        -- Keep loop anim alive if something forced a post/extinguish state.
        local firefx = burn.fx.components.firefx
        if firefx.level == nil or firefx.level < 1 then
            local _, fxlevel = GetDreadTributeBurnAttach(target)
            firefx:SetLevel(fxlevel or 2, true)
        end
    end
end

local function TickDreadTributeBurn(target)
    local burn = target ~= nil and target._waxwell_dread_tribute_burn or nil
    if burn == nil or not IsValidDreadTributeBurnTarget(target) then
        StopDreadTributeBurn(target)
        return
    end

    if GetTime() >= burn.endtime then
        StopDreadTributeBurn(target)
        return
    end

    EnsureDreadTributeBurnFX(target, burn)

    local damage = GetDreadTributeBurnDamagePerTick(burn.attacker, target)
    if (damage == nil or damage <= 0) and burn.dps ~= nil and burn.dps > 0 then
        damage = burn.dps * V.DREAD_TRIBUTE_TICK
    end

    if damage ~= nil and damage > 0 then
        target.components.health:DoDelta(
            -damage,
            nil,
            burn.attacker ~= nil and burn.attacker.prefab or "waxwell_dread_tribute",
            nil,
            burn.attacker
        )
    end
end

local function ScheduleDreadTributeBurnTicks(target, burn)
    if burn.task ~= nil then
        burn.task:Cancel()
        burn.task = nil
    end

    -- Periodic + closure: avoids stale callbacks and keeps rehit refresh reliable.
    burn.task = target:DoPeriodicTask(V.DREAD_TRIBUTE_TICK, function(inst)
        TickDreadTributeBurn(inst)
    end)

    -- Faster FX keepalive for anim-heavy bosses (e.g. UCM treeguard stomp).
    if burn.fx_task ~= nil then
        burn.fx_task:Cancel()
        burn.fx_task = nil
    end
    burn.fx_task = target:DoPeriodicTask(.25, function(inst)
        local active = inst._waxwell_dread_tribute_burn
        if active ~= nil then
            EnsureDreadTributeBurnFX(inst, active)
        end
    end)
end

local function EnsureDreadTributeBurnListeners(target, burn)
    if burn.onremovefn ~= nil then
        return
    end

    burn.onremovefn = function()
        StopDreadTributeBurn(target)
    end

    burn.ondeathfn = function()
        local active = target._waxwell_dread_tribute_burn
        if active ~= nil then
            TryDreadTributeDeathExplosion(target, active)
        end
        StopDreadTributeBurn(target)
    end

    target:ListenForEvent("onremove", burn.onremovefn)
    target:ListenForEvent("death", burn.ondeathfn)
end

local function ApplyDreadTributeBurn(attacker, target, sanity_cost)
    local dps = GetDreadTributeDotDps(attacker, target)
    if dps == nil or dps <= 0 or sanity_cost == nil then
        return false
    end

    local burn = target._waxwell_dread_tribute_burn
    if burn == nil then
        burn =
        {
            attacker = attacker,
            fx = SpawnDreadTributeBurnFX(target),
        }
        target._waxwell_dread_tribute_burn = burn
        EnsureDreadTributeBurnListeners(target, burn)
    else
        EnsureDreadTributeBurnFX(target, burn)
        burn.attacker = attacker
    end

    burn.dps = dps
    burn.endtime = GetTime() + V.DREAD_TRIBUTE_BURN_DURATION
    ScheduleDreadTributeBurnTicks(target, burn)

    attacker.components.sanity:DoDelta(-sanity_cost)
    return true
end

local function TryDreadTributeOverkillExplosion(attacker, target)
    if attacker == nil
        or target == nil
        or not target:IsValid()
        or not IsDreadTribute2Active(attacker)
        or target._waxwell_dread_tribute_exploded then
        return false
    end

    -- Target already dead from this hit (burn never applied — death runs before onhitother).
    local burn = { attacker = attacker, exploded = false }
    TryDreadTributeDeathExplosion(target, burn)
    return target._waxwell_dread_tribute_exploded == true
end

local function TryApplyDreadTributeBurnOnHit(attacker, target, weapon)
    if not TheWorld.ismastersim
        or attacker == nil
        or attacker.prefab ~= "waxwell"
        or target == nil
        or not target:IsValid()
        or GetDreadTributeWeapon(attacker, weapon) == nil then
        return
    end

    if IsValidDreadTributeBurnTarget(target) then
        local sanity_cost = GetDreadTributeRefreshSanityCost(attacker, target)
        if sanity_cost == nil or not CanAffordDreadTributeHit(attacker, sanity_cost) then
            return
        end

        ApplyDreadTributeBurn(attacker, target, sanity_cost)
        return
    end

    -- Overkill: corpse is already dead when onhitother fires — still explode with DT2.
    local health = target.components ~= nil and target.components.health or nil
    if health ~= nil and health:IsDead() and IsDreadTribute2Active(attacker) then
        local sanity_cost = GetDreadTributeBaseSanityCost(attacker)
        if sanity_cost == nil or not CanAffordDreadTributeHit(attacker, sanity_cost) then
            return
        end

        attacker.components.sanity:DoDelta(-sanity_cost)
        TryDreadTributeOverkillExplosion(attacker, target)
    end
end

local function OnDreadTributeHitOther(inst, data)
    TryApplyDreadTributeBurnOnHit(inst, data ~= nil and data.target or nil, data ~= nil and data.weapon or nil)
end

local function ApplyDreadTributeToWaxwell(inst)
    if inst == nil or not TheWorld.ismastersim then
        return
    end

    inst:ListenForEvent("onhitother", OnDreadTributeHitOther)
end

return {
    IsDreadTributeWeapon = IsDreadTributeWeapon,
    GetDreadTributeWeapon = GetDreadTributeWeapon,
    StopDreadTributeBurn = StopDreadTributeBurn,
    ApplyDreadTributeToWaxwell = ApplyDreadTributeToWaxwell,
}
