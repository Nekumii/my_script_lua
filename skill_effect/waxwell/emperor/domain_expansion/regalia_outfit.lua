local V = require("skill_effect/waxwell/emperor/domain_expansion/variables")
local ModCompat = require("mod_compatibility")

local function GetDomainExpansionCommon()
    return require("skill_effect/waxwell/emperor/domain_expansion/common")
end

return function(shared)
    local PushEmperorSpellRefresh = shared.PushEmperorSpellRefresh

    local function HasNeckSlotMod()
        return ModCompat.HasNeckSlotMod()
    end

    local function GetImperialRegaliaTempPrefabs()
        local prefabs = {}
        for slot, prefab in pairs(V.IMPERIAL_REGALIA_TEMP_PREFABS) do
            prefabs[slot] = prefab
        end
        if HasNeckSlotMod() then
            prefabs[EQUIPSLOTS.NECK] = "yellowamulet"
        end
        return prefabs
    end

    local function IsImperialRegaliaSkillActive(inst)
        return inst ~= nil
            and (
                (inst.components ~= nil
                    and inst.components.skilltreeupdater ~= nil
                    and inst.components.skilltreeupdater:IsActivated("waxwell_domain_expansion"))
                or inst:HasTag("domain_expansion_active")
            )
    end

    local function IsImperialRegaliaBuffActive(inst)
        return inst ~= nil
            and inst._waxwell_imperial_regalia_active == true
            and not inst._waxwell_imperial_regalia_outfit_suspended
    end

    local function GetImperialRegaliaSpellState(owner)
        if owner == nil then
            return nil
        elseif owner._waxwell_imperial_regalia_deactivating then
            return "deactivating"
        elseif owner._waxwell_imperial_regalia_activating then
            return "activating"
        elseif owner._waxwell_imperial_regalia_active then
            return "active"
        end
        return nil
    end

    local FinalizeImperialRegaliaActivate

    local function RefreshImperialRegaliaTag(inst)
        if inst == nil then
            return
        end

        if inst._waxwell_imperial_regalia_active and not inst._waxwell_imperial_regalia_outfit_suspended then
            if not inst:HasTag(V.IMPERIAL_REGALIA_TAG) then
                inst:AddTag(V.IMPERIAL_REGALIA_TAG)
            end
        elseif inst:HasTag(V.IMPERIAL_REGALIA_TAG) then
            inst:RemoveTag(V.IMPERIAL_REGALIA_TAG)
        end
    end

    local function WithSuppressedImperialSanityCost(doer, fn)
        local sanity = doer ~= nil and doer.components ~= nil and doer.components.sanity or nil
        if sanity == nil or fn == nil then
            return fn ~= nil and fn() or nil
        end

        local old_DoDelta = sanity.DoDelta
        sanity.DoDelta = function(self, delta, ...)
            if delta ~= nil and delta < 0 then
                return self.current
            end
            return old_DoDelta(self, delta, ...)
        end

        local results = { fn() }
        sanity.DoDelta = old_DoDelta
        return unpack(results)
    end

    local function FreezeImperialItemState(item, istemp)
        if item == nil or not item:IsValid() then
            return
        end

        local state = item._waxwell_imperial_regalia_freeze_state
        if state == nil then
            state = {}
            item._waxwell_imperial_regalia_freeze_state = state
        end
        state.istemp = istemp == true

        local finiteuses = item.components ~= nil and item.components.finiteuses or nil
        if finiteuses ~= nil and state.finiteuses == nil then
            state.finiteuses = {
                current = finiteuses.current,
                total = finiteuses.total,
                Use = finiteuses.Use,
                SetUses = finiteuses.SetUses,
                SetPercent = finiteuses.SetPercent,
                OnUsedAsItem = finiteuses.OnUsedAsItem,
            }
            finiteuses:SetIgnoreCombatDurabilityLoss(true)
            finiteuses.Use = function() end
            finiteuses.SetUses = function(self, val)
                if val ~= nil and val > self.current then
                    return state.finiteuses.SetUses(self, val)
                end
            end
            finiteuses.SetPercent = function(self, amount)
                if amount ~= nil and amount > self:GetPercent() then
                    return state.finiteuses.SetPercent(self, amount)
                end
            end
            finiteuses.OnUsedAsItem = function() end
        end

        local armor = item.components ~= nil and item.components.armor or nil
        if armor ~= nil and state.armor == nil then
            state.armor = {
                condition = armor.condition,
                maxcondition = armor.maxcondition,
                indestructible = armor.indestructible,
                TakeDamage = armor.TakeDamage,
                SetCondition = armor.SetCondition,
                SetPercent = armor.SetPercent,
            }
            armor.TakeDamage = function() end
            armor.SetCondition = function(self, amount)
                if amount ~= nil and amount > self.condition then
                    return state.armor.SetCondition(self, amount)
                end
            end
            armor.SetPercent = function(self, amount)
                if amount ~= nil and amount > self:GetPercent() then
                    return state.armor.SetPercent(self, amount)
                end
            end
            armor.indestructible = true
        end

        local fueled = item.components ~= nil and item.components.fueled or nil
        if fueled ~= nil and state.fueled == nil then
            state.fueled = {
                currentfuel = fueled.currentfuel,
                maxfuel = fueled.maxfuel,
                DoDelta = fueled.DoDelta,
                StartConsuming = fueled.StartConsuming,
                SetPercent = fueled.SetPercent,
            }
            fueled:StopConsuming()
            fueled.StartConsuming = function() end
            fueled.DoDelta = function(self, delta, ...)
                if delta ~= nil and delta > 0 then
                    return state.fueled.DoDelta(self, delta, ...)
                end
                return self.currentfuel
            end
            fueled.SetPercent = function(self, amount)
                if amount ~= nil and amount > self:GetPercent() then
                    return state.fueled.SetPercent(self, amount)
                end
            end
        end

        local perishable = item.components ~= nil and item.components.perishable or nil
        if perishable ~= nil and state.perishable == nil then
            state.perishable = {
                StartPerishing = perishable.StartPerishing,
            }
            perishable:StopPerishing()
            perishable.StartPerishing = function() end
        end
    end

    local function RestoreImperialRegaliaCastSanity(owner)
        if owner == nil or not owner:IsValid() then
            return
        end

        local preserved = owner._waxwell_imperial_regalia_cast_sanity
        if preserved == nil then
            return
        end

        local sanity = owner.components ~= nil and owner.components.sanity or nil
        if sanity ~= nil then
            sanity.current = math.min(math.max(preserved, 0), sanity.max - (sanity.max * sanity.penalty))
            sanity:DoDelta(0)
        end

        owner._waxwell_imperial_regalia_cast_sanity = nil
    end

    local function SetImperialRegaliaForceSanityZero(owner, enable)
        if owner == nil or owner.components == nil or owner.components.sanity == nil then
            return
        end

        local sanity = owner.components.sanity
        if enable then
            if owner._waxwell_imperial_regalia_old_IsCrazy == nil and type(sanity.IsCrazy) == "function" then
                owner._waxwell_imperial_regalia_old_IsCrazy = sanity.IsCrazy
                sanity.IsCrazy = function(self)
                    return true
                end
            end
        elseif owner._waxwell_imperial_regalia_old_IsCrazy ~= nil then
            sanity.IsCrazy = owner._waxwell_imperial_regalia_old_IsCrazy
            owner._waxwell_imperial_regalia_old_IsCrazy = nil
        end
    end

    local function IncreaseImperialRegaliaDrain(owner)
        -- Flat drain only; no ramp.
    end

    local function GetImperialRegaliaDrainPerSecond(owner)
        if owner == nil or not owner._waxwell_imperial_regalia_active then
            return 0
        end

        local start = V.IMPERIAL_REGALIA_SANITY_DRAIN_START or 1
        local step = V.IMPERIAL_REGALIA_SANITY_DRAIN_STEP or 1
        local interval = V.IMPERIAL_REGALIA_SANITY_DRAIN_STEP_INTERVAL or 3
        local max_drain = V.IMPERIAL_REGALIA_SANITY_DRAIN_MAX or 10
        local elapsed = GetTime() - (owner._waxwell_imperial_regalia_drain_start_time or GetTime())
        local steps = math.floor(elapsed / interval)

        return math.min(max_drain, start + steps * step)
    end

    local function UnfreezeImperialItemState(item)
        if item == nil or not item:IsValid() then
            return
        end

        local state = item._waxwell_imperial_regalia_freeze_state
        if state == nil then
            return
        end

        local finiteuses = item.components ~= nil and item.components.finiteuses or nil
        if finiteuses ~= nil and state.finiteuses ~= nil then
            finiteuses.Use = state.finiteuses.Use
            finiteuses.SetUses = state.finiteuses.SetUses
            finiteuses.SetPercent = state.finiteuses.SetPercent
            finiteuses.OnUsedAsItem = state.finiteuses.OnUsedAsItem
            finiteuses:SetIgnoreCombatDurabilityLoss(false)
            if state.istemp then
                finiteuses:SetMaxUses(math.max(finiteuses.total or 0, 999999))
                state.finiteuses.SetUses(finiteuses, math.max(finiteuses.current or 0, 999999))
            else
                state.finiteuses.SetUses(finiteuses, state.finiteuses.current)
                finiteuses:SetMaxUses(state.finiteuses.total)
            end
        end

        local armor = item.components ~= nil and item.components.armor or nil
        if armor ~= nil and state.armor ~= nil then
            armor.TakeDamage = state.armor.TakeDamage
            armor.SetCondition = state.armor.SetCondition
            armor.SetPercent = state.armor.SetPercent
            armor.indestructible = state.armor.indestructible
            if state.istemp then
                armor.condition = math.max(armor.condition or 0, 999999)
                armor.maxcondition = math.max(armor.maxcondition or 0, 999999)
            else
                armor.maxcondition = state.armor.maxcondition
                state.armor.SetCondition(armor, state.armor.condition)
            end
        end

        local fueled = item.components ~= nil and item.components.fueled or nil
        if fueled ~= nil and state.fueled ~= nil then
            fueled.DoDelta = state.fueled.DoDelta
            fueled.StartConsuming = state.fueled.StartConsuming
            fueled.SetPercent = state.fueled.SetPercent
            if state.istemp then
                state.fueled.SetPercent(fueled, 1)
                fueled:StopConsuming()
            else
                fueled.currentfuel = state.fueled.currentfuel
                fueled.maxfuel = state.fueled.maxfuel
                if fueled.inst ~= nil then
                    fueled.inst:PushEvent("percentusedchange", { percent = fueled:GetPercent() })
                end
            end
        end

        local perishable = item.components ~= nil and item.components.perishable or nil
        if perishable ~= nil and state.perishable ~= nil then
            perishable.StartPerishing = state.perishable.StartPerishing
            if not state.istemp then
                perishable:StartPerishing()
            end
        end

        item._waxwell_imperial_regalia_freeze_state = nil
    end

    local function NeutralizeImperialTempEquippable(item)
        local equippable = item ~= nil and item.components ~= nil and item.components.equippable or nil
        if equippable == nil then
            return
        end

        item._waxwell_imperial_regalia_temp_equippable_state = item._waxwell_imperial_regalia_temp_equippable_state or {
            dapperness = equippable.dapperness,
            dapperfn = equippable.dapperfn,
            is_magic_dapperness = equippable.is_magic_dapperness,
            onequipfn = equippable.onequipfn,
            onunequipfn = equippable.onunequipfn,
        }

        equippable.dapperness = 0
        equippable.dapperfn = nil
        equippable.is_magic_dapperness = nil

        local function ApplyImperialHelmetVision(owner, source)
            local playervision = owner ~= nil and owner.components ~= nil and owner.components.playervision or nil
            if playervision ~= nil and source ~= nil then
                playervision:PushForcedNightVision(source, 2, V.IMPERIAL_REGALIA_HELMET_COLOURCUBES, true)
            end
        end

        local function RemoveImperialHelmetVision(owner, source)
            local playervision = owner ~= nil and owner.components ~= nil and owner.components.playervision or nil
            if playervision ~= nil and source ~= nil then
                playervision:PopForcedNightVision(source)
            end
        end

        local function ApplyImperialSkeletonHatVisual(inst, owner)
            if inst == nil or owner == nil or owner.AnimState == nil then
                return
            end

            local build = inst.AnimState ~= nil and inst.AnimState:GetBuild() or nil
            if build ~= nil and build ~= "" then
                owner.AnimState:OverrideSymbol("swap_hat", build, "swap_hat")
            end

            owner.AnimState:ClearOverrideSymbol("headbase_hat")
            owner.AnimState:Show("HAT")
            owner.AnimState:Show("HAIR_HAT")
            owner.AnimState:Hide("HAIR_NOHAT")
            owner.AnimState:Hide("HAIR")

            if owner.isplayer then
                owner.AnimState:Hide("HEAD")
                owner.AnimState:Show("HEAD_HAT")
                owner.AnimState:Show("HEAD_HAT_NOHELM")
                owner.AnimState:Hide("HEAD_HAT_HELM")
            end

            if inst.components ~= nil and inst.components.fueled ~= nil then
                inst.components.fueled:StartConsuming()
            end
        end

        local function RemoveImperialSkeletonHatVisual(inst, owner)
            if inst == nil or owner == nil or owner.AnimState == nil then
                return
            end

            owner.AnimState:ClearOverrideSymbol("headbase_hat")
            owner.AnimState:ClearOverrideSymbol("swap_hat")
            owner.AnimState:Hide("HAT")
            owner.AnimState:Hide("HAIR_HAT")
            owner.AnimState:Show("HAIR_NOHAT")
            owner.AnimState:Show("HAIR")

            if owner.isplayer then
                owner.AnimState:Show("HEAD")
                owner.AnimState:Hide("HEAD_HAT")
                owner.AnimState:Hide("HEAD_HAT_NOHELM")
                owner.AnimState:Hide("HEAD_HAT_HELM")
            end

            if inst.components ~= nil and inst.components.fueled ~= nil then
                inst.components.fueled:StopConsuming()
            end
        end

        local old_onequipfn = item._waxwell_imperial_regalia_temp_equippable_state.onequipfn
        equippable.onequipfn = function(inst, owner, from_ground)
            if inst ~= nil and inst.prefab == "skeletonhat" then
                ApplyImperialSkeletonHatVisual(inst, owner)
            elseif old_onequipfn ~= nil then
                old_onequipfn(inst, owner, from_ground)
            end
            if owner ~= nil and owner.components ~= nil and owner.components.sanity ~= nil then
                owner.components.sanity:SetInducedInsanity(inst, false)
                owner.components.sanity:SetInducedLunacy(inst, false)
                owner.components.sanity:EnableLunacy(false, inst)
                owner.components.sanity:DoDelta(0)
            end
            if inst ~= nil and inst.prefab == "skeletonhat" then
                ApplyImperialHelmetVision(owner, inst)
            end
        end

        local old_onunequipfn = item._waxwell_imperial_regalia_temp_equippable_state.onunequipfn
        equippable.onunequipfn = function(inst, owner)
            if inst ~= nil and inst.prefab == "skeletonhat" then
                RemoveImperialHelmetVision(owner, inst)
                RemoveImperialSkeletonHatVisual(inst, owner)
            elseif old_onunequipfn ~= nil then
                old_onunequipfn(inst, owner)
            end
            if owner ~= nil and owner.components ~= nil and owner.components.sanity ~= nil then
                owner.components.sanity:SetInducedInsanity(inst, false)
                owner.components.sanity:SetInducedLunacy(inst, false)
                owner.components.sanity:EnableLunacy(false, inst)
                owner.components.sanity:DoDelta(0)
            end
        end
    end

    local function RestoreImperialTempEquippable(item)
        local equippable = item ~= nil and item.components ~= nil and item.components.equippable or nil
        local state = item ~= nil and item._waxwell_imperial_regalia_temp_equippable_state or nil
        if equippable == nil or state == nil then
            return
        end

        local owner = item.components ~= nil and item.components.inventoryitem ~= nil and item.components.inventoryitem:GetGrandOwner() or nil
        if item.prefab == "skeletonhat" and owner ~= nil and owner.components ~= nil and owner.components.playervision ~= nil then
            owner.components.playervision:PopForcedNightVision(item)
        end

        equippable.dapperness = state.dapperness
        equippable.dapperfn = state.dapperfn
        equippable.is_magic_dapperness = state.is_magic_dapperness
        equippable.onequipfn = state.onequipfn
        equippable.onunequipfn = state.onunequipfn
        item._waxwell_imperial_regalia_temp_equippable_state = nil
    end

    local function CleanStashedImperialItem(item)
        if item == nil or not item:IsValid() then
            return
        end

        UnfreezeImperialItemState(item)
        if item:HasTag("INLIMBO") then
            item:RemoveTag("INLIMBO")
        end
        item.entity:SetParent(nil)
        item:Show()
    end

    local function StashImperialEquippedItem(owner, slot, item)
        if owner == nil or item == nil or not item:IsValid() then
            return
        end

        owner._waxwell_imperial_regalia_stashed = owner._waxwell_imperial_regalia_stashed or {}
        if item.components.inventoryitem ~= nil then
            item.components.inventoryitem:OnRemoved()
        end
        FreezeImperialItemState(item, false)
        item.entity:SetParent(nil)
        item:Hide()
        if not item:HasTag("INLIMBO") then
            item:AddTag("INLIMBO")
        end
        owner._waxwell_imperial_regalia_stashed[slot] = item
    end

    local function CreateImperialTempItem(owner, slot, prefab)
        local item = SpawnPrefab(prefab)
        if item == nil then
            return nil
        end

        item.persists = false
        item._waxwell_imperial_regalia_temp = true
        if item.components.equippable ~= nil then
            item.components.equippable:SetPreventUnequipping(true)
        end
        if item.components.finiteuses ~= nil then
            item.components.finiteuses:SetMaxUses(999999)
            item.components.finiteuses:SetUses(999999)
        end
        if item.components.armor ~= nil and item.components.armor.SetCondition ~= nil then
            item.components.armor:SetCondition(999999)
        end
        if item.components.fueled ~= nil then
            item.components.fueled:StopConsuming()
            if item.components.fueled.SetPercent ~= nil then
                item.components.fueled:SetPercent(1)
            end
        end
        if item.components.perishable ~= nil then
            item.components.perishable:StopPerishing()
        end
        FreezeImperialItemState(item, true)
        NeutralizeImperialTempEquippable(item)

        return item
    end

    local function RestoreImperialEquipment(owner)
        local inventory = owner ~= nil and owner.components ~= nil and owner.components.inventory or nil
        if inventory == nil then
            return
        end

        local tempitems = owner._waxwell_imperial_regalia_temp_items or {}
        for slot, item in pairs(tempitems) do
            if item ~= nil and item:IsValid() and inventory.equipslots[slot] == item then
                inventory:Unequip(slot, nil, true)
                RestoreImperialTempEquippable(item)
                item:Remove()
            elseif item ~= nil and item:IsValid() then
                RestoreImperialTempEquippable(item)
                item:Remove()
            end
        end
        owner._waxwell_imperial_regalia_temp_items = nil

        local stashed = owner._waxwell_imperial_regalia_stashed or {}
        for slot, item in pairs(stashed) do
            if item ~= nil and item:IsValid() then
                CleanStashedImperialItem(item)
                inventory:Equip(item, true, true)
            end
        end
        owner._waxwell_imperial_regalia_stashed = nil
    end

    local function DetachImperialRegaliaFX(fx)
        fx.Transform:SetPosition(fx.Transform:GetWorldPosition())
        fx.entity:SetParent(nil)
    end

    local function SpawnImperialRegaliaDeactivateFX(owner)
        if owner == nil or not owner:IsValid() then
            return
        end

        local x, y, z = owner.Transform:GetWorldPosition()
        local fx1 = SpawnPrefab("shadow_despawn")
        local fx2 = SpawnPrefab("shadow_glob_fx")
        if fx1 == nil or fx2 == nil then
            if fx1 ~= nil then
                fx1:Remove()
            end
            if fx2 ~= nil then
                fx2:Remove()
            end
            return
        end

        fx2.AnimState:SetScale(math.random() < .5 and -1.3 or 1.3, 1.3, 1.3)

        local platform = owner.GetCurrentPlatform ~= nil and owner:GetCurrentPlatform() or nil
        if platform ~= nil then
            fx1.entity:SetParent(platform.entity)
            fx2.entity:SetParent(platform.entity)
            fx1:ListenForEvent("onremove", function()
                DetachImperialRegaliaFX(fx1)
            end, platform)
            x, y, z = platform.entity:WorldToLocalSpace(x, y, z)
        end

        fx1.Transform:SetPosition(x, y, z)
        fx2.Transform:SetPosition(x, y, z)
    end

    local function DetachImperialRegaliaSanityFloorListener(owner)
        if owner ~= nil and owner._waxwell_imperial_regalia_sanity_floor_fn ~= nil then
            owner:RemoveEventCallback("sanitydelta", owner._waxwell_imperial_regalia_sanity_floor_fn)
            owner._waxwell_imperial_regalia_sanity_floor_fn = nil
        end
    end

    local function FinalizeImperialRegaliaDeactivate(owner, shouldstartcooldown, showfx)
        if owner == nil then
            return
        end

        if showfx ~= false and owner.entity ~= nil and owner.entity:IsVisible() and not owner:HasTag("INLIMBO") then
            SpawnImperialRegaliaDeactivateFX(owner)
        end

        RestoreImperialEquipment(owner)
        DetachImperialRegaliaSanityFloorListener(owner)
        owner._waxwell_imperial_regalia_active = nil
        owner._waxwell_imperial_regalia_activating = nil
        owner._waxwell_imperial_regalia_deactivating = nil
        owner._waxwell_imperial_regalia_outfit_suspended = nil
        if owner._waxwell_imperial_regalia_drain_task ~= nil then
            owner._waxwell_imperial_regalia_drain_task:Cancel()
            owner._waxwell_imperial_regalia_drain_task = nil
        end
        if owner._waxwell_imperial_regalia_rate_task ~= nil then
            owner._waxwell_imperial_regalia_rate_task:Cancel()
            owner._waxwell_imperial_regalia_rate_task = nil
        end
        owner._waxwell_imperial_regalia_current_drain = nil
        owner._waxwell_imperial_regalia_drain_start_time = nil
        RefreshImperialRegaliaTag(owner)
        PushEmperorSpellRefresh(owner)
    end

    local function EquipImperialRegaliaOutfit(owner)
        local inventory = owner ~= nil and owner.components ~= nil and owner.components.inventory or nil
        if inventory == nil then
            return false
        end

        owner._waxwell_imperial_regalia_temp_items = owner._waxwell_imperial_regalia_temp_items or {}
        local prefabs = GetImperialRegaliaTempPrefabs()
        for slot, prefab in pairs(prefabs) do
            local equipped = inventory:GetEquippedItem(slot)
            if equipped ~= nil and not equipped._waxwell_imperial_regalia_temp then
                local stashed = inventory:Unequip(slot, nil, true)
                if stashed ~= nil then
                    StashImperialEquippedItem(owner, slot, stashed)
                end
            elseif equipped ~= nil and equipped._waxwell_imperial_regalia_temp then
                inventory:Unequip(slot, nil, true)
                equipped:Remove()
            end

            local tempitem = CreateImperialTempItem(owner, slot, prefab)
            if tempitem ~= nil then
                if tempitem.components ~= nil
                    and tempitem.components.equippable ~= nil
                    and tempitem.components.equippable.equipslot == slot then
                    inventory:Equip(tempitem, true, true)
                    owner._waxwell_imperial_regalia_temp_items[slot] = tempitem
                else
                    tempitem:Remove()
                end
            end
        end

        return true
    end

    -- Strip outfit while DE stays active (drain continues). Race-safe vs DE end.
    local function SuspendImperialRegaliaOutfit(owner)
        if owner == nil or not owner:IsValid() then
            return false
        end
        if owner._waxwell_imperial_regalia_outfit_suspended then
            return false
        end
        if not owner._waxwell_imperial_regalia_active and not owner._waxwell_imperial_regalia_activating then
            return false
        end
        if owner._waxwell_imperial_regalia_sanity_floor_ended then
            return false
        end

        local field = owner._waxwell_domain_expansion_field
        if field ~= nil and field:IsValid() and field._ending then
            return false
        end

        RestoreImperialEquipment(owner)
        SetImperialRegaliaForceSanityZero(owner, false)
        owner._waxwell_imperial_regalia_activating = nil
        owner._waxwell_imperial_regalia_deactivating = nil
        owner._waxwell_imperial_regalia_outfit_suspended = true
        RefreshImperialRegaliaTag(owner)
        PushEmperorSpellRefresh(owner)
        return true
    end

    local function ResumeImperialRegaliaOutfit(owner)
        if owner == nil or not owner:IsValid() then
            return false
        end
        if owner._waxwell_imperial_regalia_sanity_floor_ended then
            return false
        end

        local field = owner._waxwell_domain_expansion_field
        if field == nil or not field:IsValid() or field._ending or not field._active then
            return false
        end

        if owner._waxwell_imperial_regalia_active and not owner._waxwell_imperial_regalia_outfit_suspended then
            return false
        end

        if not EquipImperialRegaliaOutfit(owner) then
            return false
        end

        owner._waxwell_imperial_regalia_outfit_suspended = nil
        owner._waxwell_imperial_regalia_activating = nil
        owner._waxwell_imperial_regalia_deactivating = nil
        owner._waxwell_imperial_regalia_active = true
        SetImperialRegaliaForceSanityZero(owner, true)
        RefreshImperialRegaliaTag(owner)
        PushEmperorSpellRefresh(owner)
        return true
    end

    local function ForceImperialRegaliaDeactivate(owner, shouldstartcooldown, showfx)
        if owner == nil then
            return false
        end
        if not owner._waxwell_imperial_regalia_active
            and not owner._waxwell_imperial_regalia_activating
            and not owner._waxwell_imperial_regalia_deactivating
            and not owner._waxwell_imperial_regalia_outfit_suspended then
            return false
        end

        FinalizeImperialRegaliaDeactivate(owner, shouldstartcooldown ~= false, showfx)
        return true
    end

    local function RequestImperialRegaliaDeactivate(owner, shouldstartcooldown, showfx)
        if owner == nil or owner._waxwell_imperial_regalia_deactivating then
            return false
        elseif not owner._waxwell_imperial_regalia_active and not owner._waxwell_imperial_regalia_activating then
            return false
        end

        owner._waxwell_imperial_regalia_activating = nil
        owner._waxwell_imperial_regalia_deactivating = true
        PushEmperorSpellRefresh(owner)
        owner:DoTaskInTime(0, function(inst)
            FinalizeImperialRegaliaDeactivate(inst, shouldstartcooldown ~= false, showfx)
        end)
        return true
    end

    local function EndRegaliaOrDomainFromSanity(owner)
        local domain_expansion = GetDomainExpansionCommon()
        if domain_expansion ~= nil and domain_expansion.RequestDomainExpansionDeactivate ~= nil then
            domain_expansion.RequestDomainExpansionDeactivate(owner)
        end
    end

    local function TryEndAtSanityFloor(owner)
        if owner == nil or not owner:IsValid() then
            return false
        end
        if owner._waxwell_imperial_regalia_sanity_floor_ended then
            return false
        end
        if not owner._waxwell_imperial_regalia_active then
            return false
        end

        local sanity = owner.components ~= nil and owner.components.sanity or nil
        if sanity == nil then
            return false
        end

        local min_sanity = V.IMPERIAL_REGALIA_SANITY_END_MIN or 1
        if (sanity.current or 0) > min_sanity then
            return false
        end

        -- Lock before teardown so recoup/drain cannot keep DE alive once the floor is hit.
        owner._waxwell_imperial_regalia_sanity_floor_ended = true
        EndRegaliaOrDomainFromSanity(owner)
        return true
    end

    local function OnImperialRegaliaSanityDelta(owner, _data)
        TryEndAtSanityFloor(owner)
    end

    local function AttachImperialRegaliaSanityFloorListener(owner)
        DetachImperialRegaliaSanityFloorListener(owner)
        if owner == nil then
            return
        end

        owner._waxwell_imperial_regalia_sanity_floor_fn = OnImperialRegaliaSanityDelta
        owner:ListenForEvent("sanitydelta", owner._waxwell_imperial_regalia_sanity_floor_fn)
    end

    local function DrainImperialRegaliaSanity(owner)
        if owner == nil or not owner:IsValid() or not owner._waxwell_imperial_regalia_active then
            return
        end
        if owner._waxwell_imperial_regalia_sanity_floor_ended then
            return
        end

        local sanity = owner.components ~= nil and owner.components.sanity or nil
        if sanity == nil then
            RequestImperialRegaliaDeactivate(owner, true)
            return
        end

        local min_sanity = V.IMPERIAL_REGALIA_SANITY_END_MIN or 1
        local drain = GetImperialRegaliaDrainPerSecond(owner)
        local current = sanity.current or 0

        -- Never drain below the end floor (e.g. 2 hit by 4 → leave 1, then end).
        local actual = math.min(drain, math.max(0, current - min_sanity))
        if actual > 0 then
            sanity:DoDelta(-actual)
        end

        TryEndAtSanityFloor(owner)
    end

    FinalizeImperialRegaliaActivate = function(owner)
        if owner == nil or not owner:IsValid() then
            return
        end

        local petleash = owner.components ~= nil and owner.components.petleash or nil
        if petleash ~= nil then
            local pets = petleash:GetPets()
            if pets ~= nil and next(pets) ~= nil then
                owner:DoTaskInTime(.1, FinalizeImperialRegaliaActivate)
                return
            end
        end

        if not EquipImperialRegaliaOutfit(owner) then
            owner._waxwell_imperial_regalia_activating = nil
            return
        end

        owner._waxwell_imperial_regalia_activating = nil
        owner._waxwell_imperial_regalia_active = true
        owner._waxwell_imperial_regalia_outfit_suspended = nil
        owner._waxwell_imperial_regalia_sanity_floor_ended = nil
        RefreshImperialRegaliaTag(owner)
        RestoreImperialRegaliaCastSanity(owner)
        if owner._waxwell_imperial_regalia_drain_task ~= nil then
            owner._waxwell_imperial_regalia_drain_task:Cancel()
        end
        owner._waxwell_imperial_regalia_drain_task = owner:DoPeriodicTask(V.IMPERIAL_REGALIA_SANITY_DRAIN_PERIOD, DrainImperialRegaliaSanity, V.IMPERIAL_REGALIA_SANITY_DRAIN_PERIOD)
        owner._waxwell_imperial_regalia_current_drain = nil
        owner._waxwell_imperial_regalia_drain_start_time = GetTime()
        if owner._waxwell_imperial_regalia_rate_task ~= nil then
            owner._waxwell_imperial_regalia_rate_task:Cancel()
            owner._waxwell_imperial_regalia_rate_task = nil
        end
        SetImperialRegaliaForceSanityZero(owner, true)
        AttachImperialRegaliaSanityFloorListener(owner)
        owner:DoTaskInTime(0, RestoreImperialRegaliaCastSanity)
        owner:DoTaskInTime(FRAMES * 2, RestoreImperialRegaliaCastSanity)
        PushEmperorSpellRefresh(owner)
    end

    return {
        IsImperialRegaliaSkillActive = IsImperialRegaliaSkillActive,
        IsImperialRegaliaBuffActive = IsImperialRegaliaBuffActive,
        GetImperialRegaliaSpellState = GetImperialRegaliaSpellState,
        GetImperialRegaliaDrainPerSecond = GetImperialRegaliaDrainPerSecond,
        RequestImperialRegaliaDeactivate = RequestImperialRegaliaDeactivate,
        ForceImperialRegaliaDeactivate = ForceImperialRegaliaDeactivate,
        FinalizeImperialRegaliaActivate = FinalizeImperialRegaliaActivate,
        SuspendImperialRegaliaOutfit = SuspendImperialRegaliaOutfit,
        ResumeImperialRegaliaOutfit = ResumeImperialRegaliaOutfit,
    }
end