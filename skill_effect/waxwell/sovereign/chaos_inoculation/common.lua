local V = require("skill_effect/waxwell/sovereign/chaos_inoculation/variables")

local function IsChaosInoculationActive(inst)
    if inst == nil then
        return false
    end

    -- Prefer the tag-based state: it's updated immediately on skill activation/respec,
    -- while skilltreeupdater:IsActivated(...) may lag for a tick depending on event order.
    if inst.HasTag ~= nil and inst:HasTag("chaos_inoculation_active") then
        return true
    end

    return inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_chaos_inoculation")
end

local function GetChaosInoculationHealthPenalty(health)
    if health == nil or health.maxhealth == nil or health.maxhealth <= 0 then
        return 0
    end

    return math.clamp(
        1 - (V.CHAOS_INOCULATION_EFFECTIVE_MAX_HEALTH / health.maxhealth),
        0,
        1
    )
end

local function GetChaosInoculationCharacterSanityMax(inst)
    return inst ~= nil and inst._waxwell_chaos_inoculation_character_sanity_max or nil
end

local function EnsureChaosInoculationCharacterSanityMax(inst, sanity)
    if inst == nil or inst._waxwell_chaos_inoculation_character_sanity_max ~= nil then
        return
    end

    local max = sanity ~= nil and sanity.max or 0
    if IsChaosInoculationActive(inst) then
        if inst._waxwell_chaos_inoculation_base_sanity_max ~= nil then
            inst._waxwell_chaos_inoculation_character_sanity_max = inst._waxwell_chaos_inoculation_base_sanity_max
        else
            inst._waxwell_chaos_inoculation_character_sanity_max = math.max(0, max - V.CHAOS_INOCULATION_EXTRA_SANITY)
        end
    else
        inst._waxwell_chaos_inoculation_character_sanity_max = max
    end
end

local function ChaosInoculationSanityWasModified(inst)
    return inst ~= nil
        and (inst._waxwell_chaos_inoculation_sanity_modified
            or inst._waxwell_chaos_inoculation_applied_extra
            or inst._waxwell_chaos_inoculation_base_sanity_max ~= nil)
end

local function CaptureChaosInoculationBaseSanityMax(sanity, inst)
    if inst ~= nil and inst._waxwell_chaos_inoculation_base_sanity_max ~= nil then
        return inst._waxwell_chaos_inoculation_base_sanity_max
    end

    local max = sanity ~= nil and sanity.max or 0
    if inst ~= nil and ChaosInoculationSanityWasModified(inst) then
        return math.max(0, max - V.CHAOS_INOCULATION_EXTRA_SANITY)
    end

    local character_max = GetChaosInoculationCharacterSanityMax(inst)
    if character_max ~= nil and max > character_max then
        return character_max
    end

    return max
end

local function GetChaosInoculationBaseSanityMax(sanity, inst)
    return CaptureChaosInoculationBaseSanityMax(sanity, inst)
end

local function ResolveChaosInoculationRestoreBase(sanity, inst)
    if inst == nil or sanity == nil then
        return nil
    end

    if inst._waxwell_chaos_inoculation_base_sanity_max ~= nil then
        return inst._waxwell_chaos_inoculation_base_sanity_max
    end

    if ChaosInoculationSanityWasModified(inst) then
        return math.max(0, (sanity.max or 0) - V.CHAOS_INOCULATION_EXTRA_SANITY)
    end

    local character_max = GetChaosInoculationCharacterSanityMax(inst)
    if character_max ~= nil and (sanity.max or 0) > character_max then
        return character_max
    end

    return nil
end

local function ClearChaosInoculationSanityBonus(inst, sanity, old_SetMax)
    local base = ResolveChaosInoculationRestoreBase(sanity, inst)
    inst._waxwell_chaos_inoculation_base_sanity_max = nil
    inst._waxwell_chaos_inoculation_applied_extra = nil
    inst._waxwell_chaos_inoculation_sanity_modified = nil

    if base ~= nil and sanity.max ~= base then
        if old_SetMax ~= nil then
            old_SetMax(sanity, base)
        else
            sanity.max = base
        end
    end

    sanity:RecalculatePenalty()
end

-- Real summon penalty from the penalty table (not the HUD-adjusted self.penalty).
local function GetChaosInoculationRealSanityPenalty(sanity, inst)
    local penalty = 0
    if sanity ~= nil and sanity.sanity_penalties ~= nil then
        for _, v in pairs(sanity.sanity_penalties) do
            penalty = penalty + v
        end
    end

    local base = GetChaosInoculationBaseSanityMax(sanity, inst)
    local floor = base > 0 and (1 - (5 / base)) or 1
    return math.min(penalty, floor)
end

local function GetChaosInoculationEffectiveSanityMax(sanity, inst)
    local base = GetChaosInoculationBaseSanityMax(sanity, inst)
    local real = GetChaosInoculationRealSanityPenalty(sanity, inst)
    return base * (1 - real) + V.CHAOS_INOCULATION_EXTRA_SANITY
end

-- HUD / vanilla clamp use self.penalty as a fraction of sanity.max.
-- Convert so max*(1-display) == base*(1-real)+extra.
local function GetChaosInoculationDisplaySanityPenalty(sanity, inst)
    local max = sanity ~= nil and sanity.max or 0
    if max <= 0 then
        return 0
    end

    return math.clamp(1 - (GetChaosInoculationEffectiveSanityMax(sanity, inst) / max), 0, 1)
end

local function RefreshChaosInoculationHealth(inst)
    if inst == nil or not TheWorld.ismastersim or inst.components == nil or inst.components.health == nil then
        return
    end

    local health = inst.components.health
    if IsChaosInoculationActive(inst) then
        if inst._waxwell_chaos_inoculation_original_health_penalty == nil then
            inst._waxwell_chaos_inoculation_original_health_penalty = health.penalty or 0
        end

        health.penalty = GetChaosInoculationHealthPenalty(health)
        health:ForceUpdateHUD(true)
    elseif inst._waxwell_chaos_inoculation_original_health_penalty ~= nil then
        health.penalty = inst._waxwell_chaos_inoculation_original_health_penalty
        inst._waxwell_chaos_inoculation_original_health_penalty = nil
        health.currenthealth = health:GetMaxWithPenalty()
        health:ForceUpdateHUD(true)
    end
end

local function RefreshChaosInoculationSanity(inst, old_SetMax)
    if inst == nil or not TheWorld.ismastersim or inst.components == nil or inst.components.sanity == nil then
        return
    end

    local sanity = inst.components.sanity
    if IsChaosInoculationActive(inst) then
        if inst._waxwell_chaos_inoculation_base_sanity_max == nil then
            inst._waxwell_chaos_inoculation_base_sanity_max = CaptureChaosInoculationBaseSanityMax(sanity, inst)
        end

        local desired_max = inst._waxwell_chaos_inoculation_base_sanity_max + V.CHAOS_INOCULATION_EXTRA_SANITY
        if sanity.max ~= desired_max then
            sanity.max = desired_max
        end
        inst._waxwell_chaos_inoculation_applied_extra = true
        inst._waxwell_chaos_inoculation_sanity_modified = true

        sanity:RecalculatePenalty()
        return
    elseif ChaosInoculationSanityWasModified(inst) then
        ClearChaosInoculationSanityBonus(inst, sanity, old_SetMax)
        return
    else
        local character_max = GetChaosInoculationCharacterSanityMax(inst)
        if character_max ~= nil and (sanity.max or 0) > character_max then
            if old_SetMax ~= nil then
                old_SetMax(sanity, character_max)
            else
                sanity.max = character_max
            end
            sanity:RecalculatePenalty()
            return
        end
    end

    sanity:DoDelta(0)
end

local function RefreshChaosInoculation(inst, old_SetMax)
    RefreshChaosInoculationHealth(inst)
    RefreshChaosInoculationSanity(inst, old_SetMax)
end

local function ApplyChaosInoculationToWaxwell(inst)
    if inst == nil or not TheWorld.ismastersim or inst._waxwell_chaos_inoculation_patched then
        return
    end

    inst._waxwell_chaos_inoculation_patched = true

    local health = inst.components.health
    local sanity = inst.components.sanity
    if health == nil or sanity == nil then
        return
    end

    EnsureChaosInoculationCharacterSanityMax(inst, sanity)

    local old_SetPenalty = health.SetPenalty
    function health:SetPenalty(penalty, ...)
        if IsChaosInoculationActive(inst) then
            self.penalty = GetChaosInoculationHealthPenalty(self)
            return
        end

        return old_SetPenalty(self, penalty, ...)
    end

    local old_SetMaxHealth = health.SetMaxHealth
    function health:SetMaxHealth(amount, ...)
        local result = old_SetMaxHealth(self, amount, ...)
        if IsChaosInoculationActive(inst) then
            RefreshChaosInoculationHealth(inst)
        end
        return result
    end

    local old_DeltaPenalty = health.DeltaPenalty
    function health:DeltaPenalty(delta, ...)
        if IsChaosInoculationActive(inst) then
            RefreshChaosInoculationHealth(inst)
            return
        end
        return old_DeltaPenalty(self, delta, ...)
    end

    local old_GetMaxWithPenalty = sanity.GetMaxWithPenalty
    function sanity:GetMaxWithPenalty()
        if IsChaosInoculationActive(inst) then
            return GetChaosInoculationEffectiveSanityMax(self, inst)
        end

        return old_GetMaxWithPenalty(self)
    end

    local old_RecalculatePenalty = sanity.RecalculatePenalty
    function sanity:RecalculatePenalty()
        if not IsChaosInoculationActive(inst) then
            return old_RecalculatePenalty(self)
        end

        local base = GetChaosInoculationBaseSanityMax(self, inst)
        local desired_max = base + V.CHAOS_INOCULATION_EXTRA_SANITY
        if self.max ~= desired_max then
            self.max = desired_max
        end
        inst._waxwell_chaos_inoculation_applied_extra = true
        inst._waxwell_chaos_inoculation_sanity_modified = true

        -- self.penalty becomes HUD/clamp display fraction; real pet penalty stays in sanity_penalties.
        self.penalty = GetChaosInoculationDisplaySanityPenalty(self, inst)
        self:DoDelta(0)
    end

    local old_DoDelta = sanity.DoDelta
    function sanity:DoDelta(delta, ...)
        if not IsChaosInoculationActive(inst) or self.redirect ~= nil or self.ignore then
            return old_DoDelta(self, delta, ...)
        end

        local result = old_DoDelta(self, delta, ...)
        local cap = self:GetMaxWithPenalty()
        if (self.current or 0) > cap then
            self.current = cap
        end
        return result
    end

    local old_SetMax = sanity.SetMax
    function sanity:SetMax(amount, ...)
        if IsChaosInoculationActive(inst) then
            inst._waxwell_chaos_inoculation_base_sanity_max = amount
            inst._waxwell_chaos_inoculation_applied_extra = true
            inst._waxwell_chaos_inoculation_sanity_modified = true
            amount = amount + V.CHAOS_INOCULATION_EXTRA_SANITY
        end
        return old_SetMax(self, amount, ...)
    end

    local old_OnSave = health.OnSave
    function health:OnSave(...)
        local data = old_OnSave(self, ...)
        if inst._waxwell_chaos_inoculation_original_health_penalty ~= nil then
            data.waxwell_chaos_inoculation_original_health_penalty =
                inst._waxwell_chaos_inoculation_original_health_penalty
        end
        return data
    end

    local old_OnLoad = health.OnLoad
    function health:OnLoad(data, ...)
        old_OnLoad(self, data, ...)

        if data ~= nil and data.waxwell_chaos_inoculation_original_health_penalty ~= nil then
            inst._waxwell_chaos_inoculation_original_health_penalty =
                data.waxwell_chaos_inoculation_original_health_penalty

            if data.penalty ~= nil then
                self.penalty = data.penalty
                self:ForceUpdateHUD(true)
            end
        end

        if IsChaosInoculationActive(inst) then
            RefreshChaosInoculationHealth(inst)
        end
    end

    local old_SanityOnSave = sanity.OnSave
    function sanity:OnSave(...)
        local data = old_SanityOnSave(self, ...) or {}
        if inst._waxwell_chaos_inoculation_base_sanity_max ~= nil then
            data.waxwell_chaos_inoculation_base_sanity_max = inst._waxwell_chaos_inoculation_base_sanity_max
        end
        return data
    end

    local old_SanityOnLoad = sanity.OnLoad
    function sanity:OnLoad(data, ...)
        old_SanityOnLoad(self, data, ...)
        if data ~= nil and data.waxwell_chaos_inoculation_base_sanity_max ~= nil then
            inst._waxwell_chaos_inoculation_base_sanity_max = data.waxwell_chaos_inoculation_base_sanity_max
            inst._waxwell_chaos_inoculation_applied_extra = true
            inst._waxwell_chaos_inoculation_sanity_modified = true
        end
        if IsChaosInoculationActive(inst) then
            RefreshChaosInoculationSanity(inst, old_SetMax)
        elseif ChaosInoculationSanityWasModified(inst) then
            ClearChaosInoculationSanityBonus(inst, self, old_SetMax)
        end
    end

    RefreshChaosInoculation(inst, old_SetMax)

    inst:ListenForEvent("onactivateskill_server", function()
        RefreshChaosInoculation(inst, old_SetMax)
    end)
    inst:ListenForEvent("ondeactivateskill_server", function()
        RefreshChaosInoculation(inst, old_SetMax)
    end)
    inst:ListenForEvent("ms_respawnedfromghost", function()
        RefreshChaosInoculation(inst, old_SetMax)
    end)
    inst:ListenForEvent("onsetskillselection_server", function()
        RefreshChaosInoculation(inst, old_SetMax)
    end)
end

return {
    IsChaosInoculationActive = IsChaosInoculationActive,
    RefreshChaosInoculation = RefreshChaosInoculation,
    ApplyChaosInoculationToWaxwell = ApplyChaosInoculationToWaxwell,
}
