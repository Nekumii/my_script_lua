local V = require("skill_effect/waxwell/sovereign/sanity_recoup/variables")

local function IsSanityRecoupActive(inst)
    return inst ~= nil
        and inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_minds_recompense")
end

local function GetSanityRecoupTickCount()
    return math.max(1, math.floor((V.SANITY_RECOUP_DURATION / V.SANITY_RECOUP_TICK) + 0.0001))
end

local function StopSanityRecoup(inst)
    local state = inst ~= nil and inst._waxwell_sanity_recoup or nil
    if state == nil then
        return
    end

    if state.task ~= nil then
        state.task:Cancel()
        state.task = nil
    end

    inst._waxwell_sanity_recoup = nil
end

local function TickSanityRecoup(inst)
    local state = inst ~= nil and inst._waxwell_sanity_recoup or nil
    if state == nil or not inst:IsValid() or inst.components == nil or inst.components.sanity == nil then
        StopSanityRecoup(inst)
        return
    end

    local ticks_left = state.ticks_left or 0
    local pending = state.pending or 0
    if ticks_left <= 0 or pending <= 0 then
        if pending > 0 then
            inst.components.sanity:DoDelta(pending)
        end
        StopSanityRecoup(inst)
        return
    end

    -- Equal slices: 4s / 1s → exactly 4 heals.
    local heal = pending / ticks_left
    state.pending = pending - heal
    state.ticks_left = ticks_left - 1
    if heal > 0 then
        inst.components.sanity:DoDelta(heal)
    end

    if state.ticks_left <= 0 or (state.pending or 0) <= 0 then
        if (state.pending or 0) > 0 then
            inst.components.sanity:DoDelta(state.pending)
        end
        StopSanityRecoup(inst)
    end
end

-- Single shared pool: every hit adds to pending and refreshes the tick window.
local function AddSanityRecoup(inst, damage)
    if inst == nil or damage == nil or damage <= 0 or not IsSanityRecoupActive(inst) then
        return
    end

    if inst.components == nil or inst.components.sanity == nil then
        return
    end

    local add = damage * V.SANITY_RECOUP_RATIO
    if add <= 0 then
        return
    end

    local state = inst._waxwell_sanity_recoup
    if state == nil then
        state = { pending = 0 }
        inst._waxwell_sanity_recoup = state
    end

    state.pending = (state.pending or 0) + add
    if V.SANITY_RECOUP_MAX_PENDING ~= nil then
        state.pending = math.min(state.pending, V.SANITY_RECOUP_MAX_PENDING)
    end

    state.ticks_left = GetSanityRecoupTickCount()
    state.endtime = GetTime() + V.SANITY_RECOUP_DURATION

    if state.task == nil then
        state.task = inst:DoPeriodicTask(V.SANITY_RECOUP_TICK, function(i)
            TickSanityRecoup(i)
        end)
    end
end

-- Combat attacks only, using pre-armor original_damage from the attacked event.
local function OnSanityRecoupAttacked(inst, data)
    if data == nil or not IsSanityRecoupActive(inst) then
        return
    end

    local damage = data.original_damage
    if damage == nil or damage <= 0 then
        return
    end

    AddSanityRecoup(inst, damage)
end

local function ApplySanityRecoupToWaxwell(inst)
    if inst == nil or not TheWorld.ismastersim or inst._waxwell_sanity_recoup_patched then
        return
    end

    inst._waxwell_sanity_recoup_patched = true

    inst:ListenForEvent("attacked", OnSanityRecoupAttacked)

    inst:ListenForEvent("ondeactivateskill_server", function(_, data)
        if data ~= nil and data.skill == "waxwell_minds_recompense" then
            StopSanityRecoup(inst)
        end
    end)
end

return {
    IsSanityRecoupActive = IsSanityRecoupActive,
    ApplySanityRecoupToWaxwell = ApplySanityRecoupToWaxwell,
    StopSanityRecoup = StopSanityRecoup,
}
