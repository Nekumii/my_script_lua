local persist_utils = require("skill_effect/waxwell/_shared/persist_utils")
local V = require("skill_effect/waxwell/umbra/lingering_dread/variables")

local function IsLingeringDread1Active(inst)
    return inst ~= nil
        and inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_lingering_dread_1")
end

local function IsLingeringDread2Active(inst)
    return inst ~= nil
        and inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_lingering_dread_2")
end

local function GetLingeringDreadPanicTime(inst)
    return TUNING.SHADOW_TRAP_PANIC_TIME * V.LINGERING_DREAD_1_PANIC_MULT
end

local function HasLingeringDread1Trap(inst)
    return persist_utils.HasFlagOrTag(inst, "_waxwell_lingering_dread_1_trap", V.LINGERING_DREAD_1_TRAP_TAG)
end

local function MarkLingeringDread1Trap(inst)
    persist_utils.MarkFlagAndTag(inst, "_waxwell_lingering_dread_1_trap", V.LINGERING_DREAD_1_TRAP_TAG, function(target)
        target._waxwell_shadow_trap_panic_time = GetLingeringDreadPanicTime(target)
    end)
end

local function HasLingeringDread2Trap(inst)
    return persist_utils.HasFlagOrTag(inst, "_waxwell_lingering_dread_2_trap", V.LINGERING_DREAD_2_TRAP_TAG)
end

local function MarkLingeringDread2Trap(inst)
    persist_utils.MarkFlagAndTag(inst, "_waxwell_lingering_dread_2_trap", V.LINGERING_DREAD_2_TRAP_TAG)
end

local function IsShadowSneakCursed(inst)
    return inst ~= nil and (inst._waxwell_shadow_sneak_curse or inst:HasTag(V.SHADOW_SNEAK_CURSE_TAG))
end

local function GetShadowSneakCurseDamageTakenMult(inst)
    return inst ~= nil and (inst._waxwell_shadow_sneak_curse_mult or V.SHADOW_SNEAK_CURSE_DAMAGE_TAKEN_MULT) or V.SHADOW_SNEAK_CURSE_DAMAGE_TAKEN_MULT
end

local function RefreshShadowSneakDebuffFX(inst)
    local fx = inst ~= nil and inst._shadow_trap_fx or nil
    if fx == nil or fx.AnimState == nil then
        return
    end

    local mult = IsShadowSneakCursed(inst) and V.SHADOW_SNEAK_DEBUFF_FX_CURSE_MULT or V.SHADOW_SNEAK_DEBUFF_FX_DEFAULT_MULT
    local add = IsShadowSneakCursed(inst) and V.SHADOW_SNEAK_DEBUFF_FX_CURSE_ADD or V.SHADOW_SNEAK_DEBUFF_FX_DEFAULT_ADD
    fx.AnimState:SetMultColour(mult[1], mult[2], mult[3], mult[4])
    fx.AnimState:SetAddColour(add[1], add[2], add[3], add[4])
end

local function ClearShadowSneakCurse(inst)
    if inst == nil then
        return
    end

    inst._waxwell_shadow_sneak_curse = nil
    inst._waxwell_shadow_sneak_curse_mult = nil
    if inst:HasTag(V.SHADOW_SNEAK_CURSE_TAG) then
        inst:RemoveTag(V.SHADOW_SNEAK_CURSE_TAG)
    end

    if inst._waxwell_shadow_sneak_curse_task ~= nil then
        inst._waxwell_shadow_sneak_curse_task:Cancel()
        inst._waxwell_shadow_sneak_curse_task = nil
    end

    RefreshShadowSneakDebuffFX(inst)
end

local function ApplyShadowSneakCurse(inst, duration)
    if inst == nil or duration == nil or duration <= 0 then
        return
    end

    inst._waxwell_shadow_sneak_curse = true
    inst._waxwell_shadow_sneak_curse_mult = inst._waxwell_pending_shadow_sneak_curse_mult or inst._waxwell_shadow_sneak_curse_mult or V.SHADOW_SNEAK_CURSE_DAMAGE_TAKEN_MULT
    inst._waxwell_pending_shadow_sneak_curse_mult = nil
    if not inst:HasTag(V.SHADOW_SNEAK_CURSE_TAG) then
        inst:AddTag(V.SHADOW_SNEAK_CURSE_TAG)
    end

    if inst._waxwell_shadow_sneak_curse_task ~= nil then
        inst._waxwell_shadow_sneak_curse_task:Cancel()
        inst._waxwell_shadow_sneak_curse_task = nil
    end
    inst._waxwell_shadow_sneak_curse_task = inst:DoTaskInTime(duration, ClearShadowSneakCurse)
    RefreshShadowSneakDebuffFX(inst)

    if not inst._waxwell_shadow_sneak_curse_deathcleanup then
        inst._waxwell_shadow_sneak_curse_deathcleanup = function(target)
            ClearShadowSneakCurse(target)
        end
        inst:ListenForEvent("death", inst._waxwell_shadow_sneak_curse_deathcleanup)
        inst:ListenForEvent("onremove", inst._waxwell_shadow_sneak_curse_deathcleanup)
    end
end

local function WithAdjustedLingeringDreadShadowTrapSpawn(doer, fn)
    if fn == nil or (not IsLingeringDread1Active(doer) and not IsLingeringDread2Active(doer)) then
        return fn()
    end

    local old_SpawnPrefab = _G.SpawnPrefab
    _G.SpawnPrefab = function(prefab, ...)
        local spawned = old_SpawnPrefab(prefab, ...)
        if prefab == "shadow_trap" and spawned ~= nil then
            if IsLingeringDread1Active(doer) then
                MarkLingeringDread1Trap(spawned)
            end
            if IsLingeringDread2Active(doer) then
                MarkLingeringDread2Trap(spawned)
            end
        end
        return spawned
    end

    local ok, result, reason = xpcall(fn, debug.traceback)
    _G.SpawnPrefab = old_SpawnPrefab

    if not ok then
        error(result)
    end

    return result, reason
end

local SHADOW_TRAP_TARGET_RADIUS = 6
local SHADOW_TRAP_TARGET_MUST_TAGS = nil
local SHADOW_TRAP_TARGET_NO_TAGS = { "epic", "notraptrigger", "ghost", "player", "INLIMBO", "flight", "invisible", "notarget" }
local SHADOW_TRAP_TARGET_ONE_OF_TAGS = { "monster", "character", "animal", "smallcreature" }

local function CanShadowTrapPanic(target)
    return (target.components.hauntable ~= nil and target.components.hauntable.panicable) or target.has_nightmare_state
end

local function EndShadowTrapSpeedMult(target)
    target._shadow_trap_task = nil
    if target._shadow_trap_fx ~= nil then
        target._shadow_trap_fx:KillFX()
        target._shadow_trap_fx = nil
    end
    if target.components.locomotor ~= nil then
        target.components.locomotor:RemoveExternalSpeedMultiplier(target, "shadow_trap")
    end
end

local function TryTrapTarget(inst, targets)
    local x, y, z = inst.Transform:GetWorldPosition()
    local panic_time = inst._waxwell_shadow_trap_panic_time or TUNING.SHADOW_TRAP_PANIC_TIME

    for _, target in ipairs(TheSim:FindEntities(x, 0, z, SHADOW_TRAP_TARGET_RADIUS, SHADOW_TRAP_TARGET_MUST_TAGS, SHADOW_TRAP_TARGET_NO_TAGS, SHADOW_TRAP_TARGET_ONE_OF_TAGS)) do
        if not targets[target]
            and CanShadowTrapPanic(target)
            and not (target.components.health ~= nil and target.components.health:IsDead())
            and target.entity:IsVisible() then
            targets[target] = true

            local tx, ty, tz = target.Transform:GetWorldPosition()
            local fx = SpawnPrefab("shadow_despawn")
            local platform = target:GetCurrentPlatform()
            if platform ~= nil then
                fx.entity:SetParent(platform.entity)
                fx.Transform:SetPosition(platform.entity:WorldToLocalSpace(tx, ty, tz))
                fx:ListenForEvent("onremove", function()
                    fx.Transform:SetPosition(fx.Transform:GetWorldPosition())
                    fx.entity:SetParent(nil)
                end, platform)
            else
                fx.Transform:SetPosition(tx, ty, tz)
            end

            if target.has_nightmare_state then
                target:PushEvent("ms_forcenightmarestate", { duration = TUNING.SHADOW_TRAP_NIGHTMARE_TIME + math.random() })
            end
            if not (target.sg ~= nil and target.sg:HasStateTag("noattack")) then
                target:PushEvent("attacked", { attacker = nil, damage = 0 })
            end

            if not target.has_nightmare_state and target.components.hauntable ~= nil and target.components.hauntable.panicable then
                target.components.hauntable:Panic(panic_time)
                if HasLingeringDread2Trap(inst) then
                    target._waxwell_pending_shadow_sneak_curse_mult = V.SHADOW_SNEAK_CURSE_DAMAGE_TAKEN_MULT
                    ApplyShadowSneakCurse(target, panic_time)
                end
                if target.components.locomotor ~= nil then
                    if target._shadow_trap_task ~= nil then
                        target._shadow_trap_task:Cancel()
                    else
                        target._shadow_trap_fx = SpawnPrefab("shadow_trap_debuff_fx")
                        target._shadow_trap_fx.entity:SetParent(target.entity)
                        target._shadow_trap_fx:OnSetTarget(target)
                        RefreshShadowSneakDebuffFX(target)
                    end
                    target._shadow_trap_task = target:DoTaskInTime(panic_time, EndShadowTrapSpeedMult)
                    target.components.locomotor:SetExternalSpeedMultiplier(target, "shadow_trap", TUNING.SHADOW_TRAP_SPEED_MULT)
                end
            end
        end
    end
end

local function StopShadowTrapTask(inst, task)
    task:Cancel()
end

local function TriggerLingeringDreadShadowTrap(inst)
    if not inst.persists then
        return
    elseif not inst.sg:HasStateTag("activated") then
        if inst.task ~= nil then
            inst.task:Cancel()
            inst.task = nil
        end
        inst.sg:GoToState("activate")
        return
    end

    inst.persists = false
    inst:AddTag("NOBLOCK")
    local task = inst:DoPeriodicTask(.25, TryTrapTarget, 0, {})
    inst:DoTaskInTime(.75, StopShadowTrapTask, task)
    inst:DoTaskInTime(.5, inst.EnableGroundFX, false)
    inst:DoTaskInTime(1.2 + 10 * FRAMES, inst.Remove)
end

return {
    IsLingeringDread1Active = IsLingeringDread1Active,
    IsLingeringDread2Active = IsLingeringDread2Active,
    HasLingeringDread1Trap = HasLingeringDread1Trap,
    HasLingeringDread2Trap = HasLingeringDread2Trap,
    MarkLingeringDread1Trap = MarkLingeringDread1Trap,
    MarkLingeringDread2Trap = MarkLingeringDread2Trap,
    IsShadowSneakCursed = IsShadowSneakCursed,
    GetShadowSneakCurseDamageTakenMult = GetShadowSneakCurseDamageTakenMult,
    WithAdjustedLingeringDreadShadowTrapSpawn = WithAdjustedLingeringDreadShadowTrapSpawn,
    TriggerLingeringDreadShadowTrap = TriggerLingeringDreadShadowTrap,
    SHADOW_SNEAK_CURSE_DAMAGE_TAKEN_MULT = V.SHADOW_SNEAK_CURSE_DAMAGE_TAKEN_MULT,
}
