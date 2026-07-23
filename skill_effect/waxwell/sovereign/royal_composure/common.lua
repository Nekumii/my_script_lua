local V = require("skill_effect/waxwell/sovereign/royal_composure/variables")
local ShadowTargets = require("skill_effect/waxwell/sovereign/_shared/shadow_creature_targets")
local ModCompat = require("mod_compatibility")

local function IsRoyalComposureActive(inst)
    return inst ~= nil
        and inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_royal_composure")
end

local function IsRoyalComposureFuelTarget(inst)
    if inst == nil or inst.prefab == nil then
        return false
    end

    if ShadowTargets.IsNightmareShadowCreatureTarget(inst) then
        return true
    end

    if V.ROYAL_COMPOSURE_FUEL_DROP_EXTRA_TARGETS[inst.prefab] then
        return true
    end

    -- Uncompromising boss-tier shadow spawn: excluded from bane/resilience but
    -- still eligible for bonus fuel drops.
    if inst.prefab == "creepingfear" and ModCompat.IsEnabled(ModCompat.MODS.UNCOMPROMISING) then
        return true
    end

    return false
end

local function CountFuelInLoot(prefabs)
    local count = 0
    for _, v in ipairs(prefabs) do
        if v == "nightmarefuel" then
            count = count + 1
        end
    end
    return count
end

local function PatchRoyalComposureLoot(self)
    if self == nil or self._waxwell_royal_composure_loot_patched then
        return
    end

    self._waxwell_royal_composure_loot_patched = true
    local old_DropLoot = self.DropLoot

    function self:DropLoot(pt, prefabs)
        prefabs = prefabs or self:GenerateLoot()

        local killer = self.GetLuckyUser ~= nil and self:GetLuckyUser() or nil
        if killer ~= nil
            and killer:IsValid()
            and killer.prefab == "waxwell"
            and killer:HasTag("royal_composure_active")
            and IsRoyalComposureFuelTarget(self.inst) then

            local fuelcount = CountFuelInLoot(prefabs)
            if fuelcount > 0 then
                for i = 1, fuelcount do
                    if math.random() < V.ROYAL_COMPOSURE_BONUS_FUEL_CHANCE then
                        table.insert(prefabs, V.ROYAL_COMPOSURE_BONUS_DROP_PREFAB)
                    end
                end
            end
        end

        return old_DropLoot(self, pt, prefabs)
    end
end

local function AdjustRoyalComposureNegativeDelta(delta)
    return delta < 0 and delta * V.ROYAL_COMPOSURE_NEGATIVE_RATE_MULT or delta
end

local function PatchRoyalComposureSanity(self)
    if self == nil or self._waxwell_royal_composure_patched then
        return
    end

    self._waxwell_royal_composure_patched = true
    local old_Recalc = self.Recalc

    function self:Recalc(dt)
        if self.inst == nil or self.inst.prefab ~= "waxwell" or not IsRoyalComposureActive(self.inst) then
            return old_Recalc(self, dt)
        end

        local dapper_delta = 0
        if self.dapperness_mult ~= 0 then
            local total_dapperness = self.dapperness
            for _, v in pairs(self.inst.components.inventory.equipslots) do
                local equippable = v.components.equippable
                if equippable ~= nil then
                    local item_dapperness = self.get_equippable_dappernessfn ~= nil
                        and self.get_equippable_dappernessfn(self.inst, equippable)
                        or equippable:GetDapperness(self.inst, self.no_moisture_penalty)
                    total_dapperness = total_dapperness + item_dapperness
                end
            end

            total_dapperness = total_dapperness * self.dapperness_mult
            dapper_delta = total_dapperness * TUNING.SANITY_DAPPERNESS
        end

        local light_sanity_drain = V.LIGHT_SANITY_DRAINS[self.mode]
        local light_delta = 0

        if not self.light_drain_immune_sources:Get() then
            if TheWorld.state.isday and not TheWorld:HasTag("cave") then
                light_delta = light_sanity_drain.DAY
            else
                local lightval = CanEntitySeeInDark(self.inst) and .9 or self.inst.LightWatcher:GetLightValue()
                light_delta =
                    (
                        (lightval > TUNING.SANITY_HIGH_LIGHT and light_sanity_drain.NIGHT_LIGHT)
                        or (lightval < TUNING.SANITY_LOW_LIGHT and light_sanity_drain.NIGHT_DARK)
                        or light_sanity_drain.NIGHT_DIM
                    ) * self.night_drain_mult
            end
        end
        light_delta = AdjustRoyalComposureNegativeDelta(light_delta)

        local aura_delta = 0
        if not self.sanity_aura_immune_sources:Get() then
            local x, y, z = self.inst.Transform:GetWorldPosition()
            local ents = TheSim:FindEntities(x, y, z, TUNING.SANITY_AURA_SEACH_RANGE, V.SANITYRECALC_MUST_TAGS, V.SANITYRECALC_CANT_TAGS)
            for _, v in ipairs(ents) do
                if v.components.sanityaura ~= nil and v ~= self.inst then
                    local is_aura_immune = false
                    if self.sanity_aura_immunities ~= nil then
                        for tag, sources in pairs(self.sanity_aura_immunities) do
                            if not sources:Get() then
                                self.sanity_aura_immunities[tag] = nil
                                if next(self.sanity_aura_immunities) == nil then
                                    self.sanity_aura_immunities = nil
                                    break
                                end
                            elseif v:HasTag(tag) then
                                is_aura_immune = true
                                break
                            end
                        end
                    end

                    if not is_aura_immune then
                        local aura_val = v.components.sanityaura:GetAura(self.inst)
                        aura_val = aura_val < 0
                            and (self.neg_aura_absorb > 0 and self.neg_aura_absorb * -aura_val or aura_val) * self:GetAuraMultipliers()
                            or aura_val
                        aura_val = AdjustRoyalComposureNegativeDelta(aura_val)
                        aura_delta = aura_delta + ((aura_val < 0 and self.neg_aura_immune_sources:Get()) and 0 or aura_val)
                    end
                end
            end
        end

        local mount = self.inst.components.rider:IsRiding() and self.inst.components.rider:GetMount() or nil
        if mount ~= nil and mount.components.sanityaura ~= nil then
            local aura_val = mount.components.sanityaura:GetAura(self.inst)
            aura_val = aura_val < 0
                and (self.neg_aura_absorb > 0 and self.neg_aura_absorb * -aura_val or aura_val) * self:GetAuraMultipliers()
                or aura_val
            aura_val = AdjustRoyalComposureNegativeDelta(aura_val)
            aura_delta = aura_delta + ((aura_val < 0 and self.neg_aura_immune_sources:Get()) and 0 or aura_val)
        end

        self:RecalcGhostDrain()
        local ghost_delta = TUNING.SANITY_GHOST_PLAYER_DRAIN * self.ghost_drain_mult

        self.rate = dapper_delta + light_delta + aura_delta + ghost_delta + self.externalmodifiers:Get()

        if self.custom_rate_fn ~= nil then
            self.rate = self.rate + self.custom_rate_fn(self.inst, dt)
        end

        self.rate = self.rate * self.rate_modifier
        self.ratescale =
            (self.rate > .2 and RATE_SCALE.INCREASE_HIGH) or
            (self.rate > .1 and RATE_SCALE.INCREASE_MED) or
            (self.rate > .01 and RATE_SCALE.INCREASE_LOW) or
            (self.rate < -.3 and RATE_SCALE.DECREASE_HIGH) or
            (self.rate < -.1 and RATE_SCALE.DECREASE_MED) or
            (self.rate < -.02 and RATE_SCALE.DECREASE_LOW) or
            RATE_SCALE.NEUTRAL

        self:DoDelta(self.rate * dt, true)
    end
end

return {
    IsRoyalComposureActive = IsRoyalComposureActive,
    IsRoyalComposureFuelTarget = IsRoyalComposureFuelTarget,
    PatchRoyalComposureSanity = PatchRoyalComposureSanity,
    PatchRoyalComposureLoot = PatchRoyalComposureLoot,
}
