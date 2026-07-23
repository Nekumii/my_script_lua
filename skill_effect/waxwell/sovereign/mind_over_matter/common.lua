local V = require("skill_effect/waxwell/sovereign/mind_over_matter/variables")

local function IsMindOverMatterActive(inst)
    return inst ~= nil
        and inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_mind_over_matter")
end

-- HealthBadge (client):
--   mind_over_matter_redirecting → hide decrease arrows (damage went to sanity only)
--   mind_over_matter_hp_hit     → show decrease arrows (HP actually lost)
local MOM_REDIRECTING_TAG = "mind_over_matter_redirecting"
local MOM_HP_HIT_TAG = "mind_over_matter_hp_hit"
local MOM_HP_HIT_DURATION = 2.5

local function SetTag(inst, tag, enabled)
    if inst == nil or not inst:IsValid() then
        return
    end

    if enabled then
        if not inst:HasTag(tag) then
            inst:AddTag(tag)
        end
    elseif inst:HasTag(tag) then
        inst:RemoveTag(tag)
    end
end

local function ClearMindOverMatterHpHit(inst)
    if inst == nil then
        return
    end

    if inst._waxwell_mom_hp_hit_task ~= nil then
        inst._waxwell_mom_hp_hit_task:Cancel()
        inst._waxwell_mom_hp_hit_task = nil
    end

    SetTag(inst, MOM_HP_HIT_TAG, false)
end

local function PulseMindOverMatterHpHit(inst)
    if inst == nil or not inst:IsValid() then
        return
    end

    SetTag(inst, MOM_REDIRECTING_TAG, false)
    SetTag(inst, MOM_HP_HIT_TAG, true)

    if inst._waxwell_mom_hp_hit_task ~= nil then
        inst._waxwell_mom_hp_hit_task:Cancel()
    end

    inst._waxwell_mom_hp_hit_task = inst:DoTaskInTime(MOM_HP_HIT_DURATION, function()
        inst._waxwell_mom_hp_hit_task = nil
        SetTag(inst, MOM_HP_HIT_TAG, false)
    end)
end

local function RefreshMindOverMatterDapperness(inst)
    if inst == nil or not TheWorld.ismastersim or inst.components == nil or inst.components.sanity == nil then
        return
    end

    local ok, inner_incarnate = pcall(require, "skill_effect/waxwell/sovereign/inner_incarnate/common")
    if ok and inner_incarnate ~= nil and inner_incarnate.RefreshInnerIncarnateSanityRegen ~= nil then
        inner_incarnate.RefreshInnerIncarnateSanityRegen(inst)
        return
    end

    inst.components.sanity.dapperness = IsMindOverMatterActive(inst)
        and V.MIND_OVER_MATTER_DAPPERNESS
        or TUNING.DAPPERNESS_LARGE
end

local function SetMindOverMatterRedirecting(inst, redirecting)
    if redirecting then
        ClearMindOverMatterHpHit(inst)
        SetTag(inst, MOM_REDIRECTING_TAG, true)
    else
        SetTag(inst, MOM_REDIRECTING_TAG, false)
    end
end

local function ApplyMindOverMatterToWaxwell(inst)
    if inst == nil or not TheWorld.ismastersim or inst._waxwell_mind_over_matter_patched then
        return
    end

    inst._waxwell_mind_over_matter_patched = true
    RefreshMindOverMatterDapperness(inst)

    local health = inst.components.health
    if health == nil then
        return
    end

    local old_DoDelta = health.DoDelta
    function health:DoDelta(...)
        local args = { ... }
        self._waxwell_mind_over_matter_suppress_healthdelta = nil

        local old_PushEvent = inst.PushEvent
        inst.PushEvent = function(event_inst, event, data, ...)
            if event == "healthdelta"
                and self._waxwell_mind_over_matter_suppress_healthdelta
                and data ~= nil
                and math.abs(data.amount or 0) < .000001 then
                return
            end

            return old_PushEvent(event_inst, event, data, ...)
        end

        local ok, result = xpcall(function()
            return old_DoDelta(self, unpack(args))
        end, debug.traceback)

        inst.PushEvent = old_PushEvent
        self._waxwell_mind_over_matter_suppress_healthdelta = nil

        if not ok then
            error(result)
        end

        return result
    end

    local old_deltamodifierfn = health.deltamodifierfn
    health.deltamodifierfn = function(target, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
        if old_deltamodifierfn ~= nil then
            amount = old_deltamodifierfn(target, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
        end

        if health._waxwell_mind_over_matter_applying
            or amount == nil
            or amount >= 0
            or not IsMindOverMatterActive(target)
            or target.components == nil
            or target.components.sanity == nil then
            return amount
        end

        local sanity = target.components.sanity
        local sanity_damage = math.min(sanity.current or 0, -amount)
        if sanity_damage <= 0 then
            -- Sanity empty: whole hit lands on HP.
            PulseMindOverMatterHpHit(target)
            return amount
        end

        health._waxwell_mind_over_matter_applying = true
        sanity:DoDelta(-sanity_damage, overtime)
        health._waxwell_mind_over_matter_applying = nil


        local remaining_damage = amount + sanity_damage
        if math.abs(remaining_damage) < .000001 then
            remaining_damage = 0
            health._waxwell_mind_over_matter_suppress_healthdelta = true
            -- Full redirect to sanity — hide HP arrows even if HP was already not full.
            SetMindOverMatterRedirecting(target, true)
        else
            -- Overflow into HP — show HP arrows (combat + fire/etc).
            PulseMindOverMatterHpHit(target)
        end

        return remaining_damage
    end

    inst:ListenForEvent("onactivateskill_server", function()
        RefreshMindOverMatterDapperness(inst)
    end)
    inst:ListenForEvent("ondeactivateskill_server", function(_, data)
        RefreshMindOverMatterDapperness(inst)
        if data ~= nil and data.skill == "waxwell_mind_over_matter" then
            SetMindOverMatterRedirecting(inst, false)
            ClearMindOverMatterHpHit(inst)
        end
    end)
end

return {
    IsMindOverMatterActive = IsMindOverMatterActive,
    RefreshMindOverMatterDapperness = RefreshMindOverMatterDapperness,
    ApplyMindOverMatterToWaxwell = ApplyMindOverMatterToWaxwell,
}
