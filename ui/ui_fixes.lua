local ModCompat = require("mod_compatibility")
local mod_config = require("mod_config")

--//////////////////// UI Fixes

-- Mind Over Matter HealthBadge:
-- redirecting / sanity>0 → hide env decrease (sanity absorbs; ignore IsHurt; kills fire flicker)
-- hp_hit tag             → force decrease without restarting anim every frame
local function ShouldSuppressMindOverMatterHealthArrow(owner)
    if owner == nil then
        return false
    end

    if owner:HasTag("mind_over_matter_redirecting") then
        return true
    end

    if not owner:HasTag("mind_over_matter_active") then
        return false
    end

    -- Before first damage tick sets redirecting, still hide env arrows while sanity can absorb.
    local sanity = owner.replica ~= nil and owner.replica.sanity or nil
    return sanity ~= nil and (sanity:GetCurrent() or 0) > 0
end

local function ShouldForceMindOverMatterHealthArrow(owner)
    return owner ~= nil and owner:HasTag("mind_over_matter_hp_hit")
end

AddClassPostConstruct("widgets/healthbadge", function(self)
    local old_OnUpdate = self.OnUpdate

    function self:OnUpdate(dt, ...)
        old_OnUpdate(self, dt, ...)

        local owner = self.owner
        if ShouldForceMindOverMatterHealthArrow(owner) then
            local anim = "arrow_loop_decrease_most"
            -- Keep arrowdir in sync but do NOT PlayAnimation every frame —
            -- old_OnUpdate resets arrowdir to neutral on combat hits, which would
            -- restart the loop and look static / cut short.
            if self._waxwell_mom_forced_arrow ~= anim then
                self._waxwell_mom_forced_arrow = anim
                self.arrowdir = anim
                if self.sanityarrow ~= nil then
                    self.sanityarrow:GetAnimState():PlayAnimation(anim, true)
                end
            else
                self.arrowdir = anim
            end
            return
        elseif self._waxwell_mom_forced_arrow ~= nil then
            self._waxwell_mom_forced_arrow = nil
            self.arrowdir = "neutral"
            if self.sanityarrow ~= nil then
                self.sanityarrow:GetAnimState():PlayAnimation("neutral", true)
            end
        end

        if ShouldSuppressMindOverMatterHealthArrow(owner)
            and self.arrowdir ~= nil
            and string.find(self.arrowdir, "decrease", 1, true) then
            self.arrowdir = "neutral"
            if self.sanityarrow ~= nil then
                self.sanityarrow:GetAnimState():PlayAnimation("neutral", true)
            end
        end
    end
end)

AddClassPostConstruct("widgets/sanitybadge", function(self)
    local old_SetPercent = self.SetPercent

    function self:SetPercent(val, max, penaltypercent)
        old_SetPercent(self, val, max, penaltypercent)

        if self.owner ~= nil and mod_config.IsDebugModeEnabled() then
            self.owner._skilltree_debug_sanity_current_percent = val
            self.owner._skilltree_debug_sanity_base_max = max
            self.owner._skilltree_debug_sanity_penalty_percent = penaltypercent or 0
        end

        local sanity = self.owner ~= nil and self.owner.replica ~= nil and self.owner.replica.sanity or nil
        if sanity ~= nil then
            local current = sanity:GetCurrent()
            if current ~= nil then
                self.num:SetString(tostring(math.max(0, math.ceil(current - 0.0001))))
            end
        end
    end
end)

-- =============================================================================
-- HUD replica timing — healthdelta/sanitydelta before owner.replica.* exists
-- =============================================================================

local function OwnerReplicaReady(owner, component)
    return owner ~= nil
        and owner.replica ~= nil
        and owner.replica[component] ~= nil
end

AddClassPostConstruct("widgets/statusdisplays", function(self)
    local old_SetHealthPercent = self.SetHealthPercent
    if type(old_SetHealthPercent) == "function" then
        function self:SetHealthPercent(pct, ...)
            if not OwnerReplicaReady(self.owner, "health") then
                return
            end
            return old_SetHealthPercent(self, pct, ...)
        end
    end

    local old_SetHungerPercent = self.SetHungerPercent
    if type(old_SetHungerPercent) == "function" then
        function self:SetHungerPercent(pct, ...)
            if not OwnerReplicaReady(self.owner, "hunger") then
                return
            end
            return old_SetHungerPercent(self, pct, ...)
        end
    end

    local old_SetSanityPercent = self.SetSanityPercent
    if type(old_SetSanityPercent) == "function" then
        function self:SetSanityPercent(pct, ...)
            if not OwnerReplicaReady(self.owner, "sanity") then
                return
            end
            return old_SetSanityPercent(self, pct, ...)
        end
    end
end)

local function GetFunctionUpvalue(fn, upvaluename)
    if type(fn) ~= "function" or upvaluename == nil or debug == nil or debug.getupvalue == nil then
        return nil
    end

    local index = 1
    while true do
        local name, value = debug.getupvalue(fn, index)
        if name == nil then
            return nil
        elseif name == upvaluename then
            return value
        end
        index = index + 1
    end
end

if ModCompat.IsEnabled(ModCompat.MODS.STAT_CHANGE_DISPLAY) then
    -- Load after workshop-3606056931 (modinfo priority) so we wrap its Health/Hunger/SanityDelta.
    AddClassPostConstruct("widgets/statusdisplays", function(self)
        local scd_HealthDelta = self.HealthDelta
        local wrapped_old_healthdelta = GetFunctionUpvalue(scd_HealthDelta, "old_healthdelta")
        if type(scd_HealthDelta) == "function" then
            function self:HealthDelta(data, ...)
                if not OwnerReplicaReady(self.owner, "health") then
                    if type(wrapped_old_healthdelta) == "function" then
                        return wrapped_old_healthdelta(self, data, ...)
                    end
                    return
                end
                return scd_HealthDelta(self, data, ...)
            end
        end

        local scd_HungerDelta = self.HungerDelta
        local wrapped_old_hungerdelta = GetFunctionUpvalue(scd_HungerDelta, "old_hungerdelta")
        if type(scd_HungerDelta) == "function" then
            function self:HungerDelta(data, ...)
                if not OwnerReplicaReady(self.owner, "hunger") then
                    if type(wrapped_old_hungerdelta) == "function" then
                        return wrapped_old_hungerdelta(self, data, ...)
                    end
                    return
                end
                return scd_HungerDelta(self, data, ...)
            end
        end

        local scd_SanityDelta = self.SanityDelta
        local wrapped_old_sanitydelta = GetFunctionUpvalue(scd_SanityDelta, "old_sanitydelta")
        if type(scd_SanityDelta) == "function" then
            function self:SanityDelta(data, ...)
                local owner = self.owner
                if owner ~= nil
                    and owner:HasTag("imperial_regalia_buff_active")
                    and data ~= nil
                    and not data.overtime
                    and type(wrapped_old_sanitydelta) == "function" then
                    return wrapped_old_sanitydelta(self, data, ...)
                end

                if not OwnerReplicaReady(owner, "sanity") then
                    if type(wrapped_old_sanitydelta) == "function" then
                        return wrapped_old_sanitydelta(self, data, ...)
                    end
                    return
                end

                return scd_SanityDelta(self, data, ...)
            end
        end
    end)
end

if ModCompat.IsEnabled(ModCompat.MODS.ITEM_INFO_UPDATED) then
    AddClassPostConstruct("widgets/iteminfo_equip_manager", function(self)
        local old_UpdatePos = self.UpdatePos

        function self:UpdatePos(...)
            if ThePlayer == nil or ThePlayer.replica == nil or ThePlayer.replica.inventory == nil then
                return
            end

            return old_UpdatePos(self, ...)
        end
    end)

    AddClassPostConstruct("widgets/iteminfo_equip", function(self)
        local old_OnUpdate = self.OnUpdate

        function self:OnUpdate(dt, ...)
            if ThePlayer == nil or ThePlayer.replica == nil or ThePlayer.replica.inventory == nil then
                if self.HideInfo ~= nil then
                    self:HideInfo()
                end
                return
            end

            return old_OnUpdate(self, dt, ...)
        end
    end)
end

if ModCompat.IsEnabled(ModCompat.MODS.SIMPLE_HEALTH_BAR_DST) then
    AddComponentPostInit("hallucinations", function(self)
        if self == nil or self.GetDebugString == nil then
            return
        end

        local hallucinations = GetFunctionUpvalue(self.GetDebugString, "_hallucinations")
        if type(hallucinations) ~= "table" then
            return
        end

        for _, hallucination in pairs(hallucinations) do
            local params = hallucination ~= nil and hallucination.params or nil
            local old_spawnfn = params ~= nil and params.spawnfn or nil

            if type(old_spawnfn) == "function" and params._skilltree_shb_safe_spawnfn ~= true then
                local safe_spawnfn
                safe_spawnfn = function(inst, hallucinationdata)
                    local player = GetFunctionUpvalue(old_spawnfn, "_player")
                    local sanity = player ~= nil and player.replica ~= nil and player.replica.sanity or nil
                    if sanity == nil then
                        hallucinationdata.task = inst:DoTaskInTime(1, safe_spawnfn, hallucinationdata)
                        return
                    end

                    return old_spawnfn(inst, hallucinationdata)
                end

                params.spawnfn = safe_spawnfn
                params._skilltree_shb_safe_spawnfn = true
            end
        end
    end)
end

if ModCompat.HasPlaceStatuesCompatMod() then
    AddComponentPostInit("playercontroller", function(self)
        if self == nil or self.inst == nil or self._skilltree_place_statues_inventory_guard_task ~= nil then
            return
        end

        self._skilltree_place_statues_inventory_guard_task = self.inst:DoTaskInTime(0, function()
            self._skilltree_place_statues_inventory_guard_task = nil

            local old_OnUpdate = self.OnUpdate
            if old_OnUpdate == nil or self._skilltree_place_statues_inventory_guard then
                return
            end

            self._skilltree_place_statues_inventory_guard = true

            function self:OnUpdate(...)
                if ThePlayer == nil or ThePlayer.replica == nil or ThePlayer.replica.inventory == nil then
                    return old_OnUpdate(self, ...)
                end

                return old_OnUpdate(self, ...)
            end
        end)
    end)
end

AddComponentPostInit("playercontroller", function(self)
    if self == nil or self.inst == nil then
        return
    end

    local old_OnUpdate = self.OnUpdate
    if type(old_OnUpdate) ~= "function" then
        return
    end

    function self:OnUpdate(...)
        if self.inst == nil or self.inst.replica == nil or self.inst.replica.inventory == nil then
            return old_OnUpdate(self, ...)
        end

        return old_OnUpdate(self, ...)
    end
end)

AddComponentPostInit("playeractionpicker", function(self)
    if self == nil or self._skilltree_inventory_guarded then
        return
    end

    self._skilltree_inventory_guarded = true

    local old_GetLeftClickActions = self.GetLeftClickActions
    if type(old_GetLeftClickActions) == "function" then
        function self:GetLeftClickActions(...)
            if self.inst == nil or self.inst.replica == nil or self.inst.replica.inventory == nil then
                return {}
            end
            return old_GetLeftClickActions(self, ...)
        end
    end

    local old_DoGetMouseActions = self.DoGetMouseActions
    if type(old_DoGetMouseActions) == "function" then
        function self:DoGetMouseActions(...)
            if self.inst == nil or self.inst.replica == nil or self.inst.replica.inventory == nil then
                return {}
            end
            return old_DoGetMouseActions(self, ...)
        end
    end
end)
