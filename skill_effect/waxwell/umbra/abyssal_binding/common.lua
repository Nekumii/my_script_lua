local persist_utils = require("skill_effect/waxwell/_shared/persist_utils")
local V = require("skill_effect/waxwell/umbra/abyssal_binding/variables")

local function IsAbyssalBinding1Active(inst)
    return inst ~= nil
        and inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_abyssal_binding_1")
end

local function IsAbyssalBinding2Active(inst)
    return inst ~= nil
        and inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_abyssal_binding_2")
end

local function GetAbyssalBinding1Duration(duration, inst)
    local mult = inst ~= nil and inst._waxwell_abyssal_binding_1_duration_mult or V.ABYSSAL_BINDING_1_DURATION_MULT
    return duration * mult
end

local function PatchAbyssalBinding1Lifetime(inst, hasmarkfn)
    local timer = inst.components.timer
    if timer == nil or timer._waxwell_abyssal_binding_1_duration_patched then
        return
    end

    timer._waxwell_abyssal_binding_1_duration_patched = true
    local old_StartTimer = timer.StartTimer
    function timer:StartTimer(name, time, paused, initialtime, ...)
        if name == "lifetime" and hasmarkfn(self.inst) and time ~= nil then
            time = GetAbyssalBinding1Duration(time, self.inst)
            if initialtime ~= nil then
                initialtime = GetAbyssalBinding1Duration(initialtime, self.inst)
            end
        end
        return old_StartTimer(self, name, time, paused, initialtime, ...)
    end
end

local HasAbyssalBinding2ShadowPillar
local ScheduleAbyssalBinding2ShadowPillarImpact

local function PatchAbyssalBinding2ShadowPillarImpact(inst)
    local timer = inst.components.timer
    if timer == nil or timer._waxwell_abyssal_binding_2_impact_patched then
        return
    end

    timer._waxwell_abyssal_binding_2_impact_patched = true
    local old_StartTimer = timer.StartTimer
    function timer:StartTimer(name, time, paused, initialtime, ...)
        if name == "lifetime" and HasAbyssalBinding2ShadowPillar(self.inst) then
            ScheduleAbyssalBinding2ShadowPillarImpact(self.inst)
        end
        return old_StartTimer(self, name, time, paused, initialtime, ...)
    end
end

local function HasAbyssalBinding1ShadowPillar(inst)
    return persist_utils.HasFlagOrTag(inst, "_waxwell_abyssal_binding_1_shadow_pillar", V.ABYSSAL_BINDING_1_PILLAR_TAG)
end

local function MarkAbyssalBinding1ShadowPillar(inst)
    persist_utils.MarkFlagAndTag(inst, "_waxwell_abyssal_binding_1_shadow_pillar", V.ABYSSAL_BINDING_1_PILLAR_TAG)
end

local function HasAbyssalBinding1ShadowPillarTarget(inst)
    return persist_utils.HasFlagOrTag(inst, "_waxwell_abyssal_binding_1_shadow_pillar_target", V.ABYSSAL_BINDING_1_TARGET_TAG)
end

local function MarkAbyssalBinding1ShadowPillarTarget(inst)
    persist_utils.MarkFlagAndTag(inst, "_waxwell_abyssal_binding_1_shadow_pillar_target", V.ABYSSAL_BINDING_1_TARGET_TAG)
end

HasAbyssalBinding2ShadowPillar = function(inst)
    return persist_utils.HasFlagOrTag(inst, "_waxwell_abyssal_binding_2_shadow_pillar", V.ABYSSAL_BINDING_2_PILLAR_TAG)
end

local function MarkAbyssalBinding2ShadowPillar(inst)
    persist_utils.MarkFlagAndTag(inst, "_waxwell_abyssal_binding_2_shadow_pillar", V.ABYSSAL_BINDING_2_PILLAR_TAG)
end

local function GetDebugLocal(level, wantedname)
    local debuglib = _G.debug
    if debuglib == nil or debuglib.getlocal == nil then
        return nil
    end

    level = level + 1
    local index = 1
    while true do
        local name, value = debuglib.getlocal(level, index)
        if name == nil then
            return nil
        elseif name == wantedname then
            return value
        end
        index = index + 1
    end
end

local function GetShadowPillarsCasterFromSpawnStack()
    local debuglib = _G.debug
    if debuglib == nil or debuglib.getinfo == nil then
        return nil
    end

    local level = 2
    while true do
        local info = debuglib.getinfo(level, "S")
        if info == nil then
            return nil
        end

        local source = info.source
        if source ~= nil and string.find(source, V.ABYSSAL_BINDING_1_SOURCE_FILE, 1, true) ~= nil then
            local item = GetDebugLocal(level, "item")
            if item ~= nil and item.prefab == "waxwelljournal" then
                return GetDebugLocal(level, "caster")
            end
        end

        level = level + 1
    end
end

local ABYSSAL_BINDING_2_TARGET_MUST_TAGS = { "_combat" }
local ABYSSAL_BINDING_2_TARGET_NO_TAGS = { "INLIMBO", "flight", "invisible", "notarget", "noattack", "player", "playerghost", "wall", "companion", "shadowminion" }
local ABYSSAL_BINDING_2_TARGET_ONE_OF_TAGS = { "monster", "animal", "smallcreature" }

local function IsAbyssalBinding2FriendlyTarget(target)
    if target == nil then
        return true
    end

    if target:HasTag("playerowned") or target.bedazzled then
        return true
    end

    local follower = target.components ~= nil and target.components.follower or nil
    return follower ~= nil and follower:GetLeader() ~= nil
end

local function CanAbyssalBinding2HitTarget(inst, target)
    if inst == nil or target == nil then
        return false
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    local radius = V.ABYSSAL_BINDING_2_IMPACT_RADIUS + (target.GetPhysicsRadius ~= nil and target:GetPhysicsRadius(0) or 0)
    return target:GetDistanceSqToPoint(x, 0, z) <= radius * radius
end

local function TriggerAbyssalBinding2ShadowPillarImpact(inst)
    if inst == nil or not inst:IsValid() or not HasAbyssalBinding2ShadowPillar(inst) or inst._waxwell_abyssal_binding_2_shadow_pillar_hit then
        return
    end

    inst._waxwell_abyssal_binding_2_shadow_pillar_impact_task = nil
    inst._waxwell_abyssal_binding_2_shadow_pillar_hit = true

    local x, y, z = inst.Transform:GetWorldPosition()
    for _, target in ipairs(TheSim:FindEntities(x, 0, z, V.ABYSSAL_BINDING_2_IMPACT_SEARCH_RADIUS, ABYSSAL_BINDING_2_TARGET_MUST_TAGS, ABYSSAL_BINDING_2_TARGET_NO_TAGS, ABYSSAL_BINDING_2_TARGET_ONE_OF_TAGS)) do
        if require("skill_effect/_shared/targeting_rules").IsEntityAllowed(target,
        {
            name = "abyssal_binding_2_impact",
            must_tags = ABYSSAL_BINDING_2_TARGET_MUST_TAGS,
            one_of_tags = ABYSSAL_BINDING_2_TARGET_ONE_OF_TAGS,
            blacklist_tags = ABYSSAL_BINDING_2_TARGET_NO_TAGS,
            extra_check = function(ent)
                return ent.components ~= nil
                    and ent.components.combat ~= nil
                    and ent.components.health ~= nil
                    and not ent.components.health:IsDead()
                    and ent.entity:IsVisible()
                    and not IsAbyssalBinding2FriendlyTarget(ent)
                    and CanAbyssalBinding2HitTarget(inst, ent)
            end,
        }) then
            local attacker = inst._waxwell_abyssal_binding_2_caster
            local damage = inst._waxwell_abyssal_binding_2_damage or V.ABYSSAL_BINDING_2_DAMAGE
            target.components.combat:GetAttacked(attacker, damage)
        end
    end
end

ScheduleAbyssalBinding2ShadowPillarImpact = function(inst, delayoverride)
    if inst == nil or not HasAbyssalBinding2ShadowPillar(inst) or inst._waxwell_abyssal_binding_2_shadow_pillar_hit then
        return
    end

    if inst._waxwell_abyssal_binding_2_shadow_pillar_impact_task ~= nil then
        inst._waxwell_abyssal_binding_2_shadow_pillar_impact_task:Cancel()
        inst._waxwell_abyssal_binding_2_shadow_pillar_impact_task = nil
    end

    inst._waxwell_abyssal_binding_2_shadow_pillar_impact_task =
        inst:DoTaskInTime(delayoverride ~= nil and delayoverride or V.ABYSSAL_BINDING_2_IMPACT_DELAY, TriggerAbyssalBinding2ShadowPillarImpact)
end

local function ResumeAbyssalBinding2ShadowPillarImpact(inst)
    if inst == nil or not HasAbyssalBinding2ShadowPillar(inst) or inst._waxwell_abyssal_binding_2_shadow_pillar_hit then
        return
    end

    local timer = inst.components ~= nil and inst.components.timer or nil
    local elapsed = timer ~= nil and timer:TimerExists("lifetime") and timer:GetTimeElapsed("lifetime") or nil
    ScheduleAbyssalBinding2ShadowPillarImpact(inst, math.max(0, V.ABYSSAL_BINDING_2_IMPACT_DELAY - (elapsed or 0)))
end

return {
    IsAbyssalBinding1Active = IsAbyssalBinding1Active,
    IsAbyssalBinding2Active = IsAbyssalBinding2Active,
    HasAbyssalBinding1ShadowPillar = HasAbyssalBinding1ShadowPillar,
    HasAbyssalBinding1ShadowPillarTarget = HasAbyssalBinding1ShadowPillarTarget,
    HasAbyssalBinding2ShadowPillar = HasAbyssalBinding2ShadowPillar,
    MarkAbyssalBinding1ShadowPillar = MarkAbyssalBinding1ShadowPillar,
    MarkAbyssalBinding1ShadowPillarTarget = MarkAbyssalBinding1ShadowPillarTarget,
    MarkAbyssalBinding2ShadowPillar = MarkAbyssalBinding2ShadowPillar,
    PatchAbyssalBinding1Lifetime = PatchAbyssalBinding1Lifetime,
    PatchAbyssalBinding2ShadowPillarImpact = PatchAbyssalBinding2ShadowPillarImpact,
    ResumeAbyssalBinding2ShadowPillarImpact = ResumeAbyssalBinding2ShadowPillarImpact,
    ScheduleAbyssalBinding2ShadowPillarImpact = ScheduleAbyssalBinding2ShadowPillarImpact,
    GetShadowPillarsCasterFromSpawnStack = GetShadowPillarsCasterFromSpawnStack,
}
