local Ephemeral = require("skill_effect/waxwell/sovereign/shadow_conjury/ephemeral")
local V = require("skill_effect/waxwell/sovereign/shadow_conjury/variables")
local ModCompat = require("mod_compatibility")

local function DefaultOnUnequip(inst, owner)
    owner.AnimState:Hide("ARM_carry")
    owner.AnimState:Show("ARM_normal")
    local skin_build = inst:GetSkinBuild()
    if skin_build ~= nil then
        owner:PushEvent("unequipskinneditem", inst:GetSkinName())
    end
end

local function MakeOnEquip(swap_build, sym_name)
    return function(inst, owner)
        local skin_build = inst:GetSkinBuild()
        if skin_build ~= nil then
            owner:PushEvent("equipskinneditem", inst:GetSkinName())
            owner.AnimState:OverrideItemSkinSymbol("swap_object", skin_build, sym_name, inst.GUID, swap_build)
        else
            owner.AnimState:OverrideSymbol("swap_object", swap_build, sym_name)
        end
        owner.AnimState:Show("ARM_carry")
        owner.AnimState:Hide("ARM_normal")
    end
end

local function ShadowPrefabName(base)
    return "waxwell_shadow_" .. base
end

local function MakeHandToolPrefab(base, def)
    local name = ShadowPrefabName(base)
    local assets = def.assets
    local prefabs = def.prefabs

    local function fn()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddNetwork()

        MakeInventoryPhysics(inst)

        inst.AnimState:SetBank(def.bank)
        inst.AnimState:SetBuild(def.build)
        inst.AnimState:PlayAnimation(def.anim or "idle")

        for _, tag in ipairs(def.tags or {}) do
            inst:AddTag(tag)
        end
        inst:AddTag("tool")
        if def.weapon ~= false then
            inst:AddTag("weapon")
        end

        if def.floater ~= nil then
            MakeInventoryFloatable(inst, unpack(def.floater))
        end

        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("inspectable")
        inst:AddComponent("inventoryitem")
        inst:AddComponent("equippable")
        inst.components.equippable:SetOnEquip(Ephemeral.WrapEquipWithTint(MakeOnEquip(def.swap_build, def.sym_name)))
        inst.components.equippable:SetOnUnequip(Ephemeral.WrapUnequipWithTint(DefaultOnUnequip))

        inst:AddComponent("tool")
        inst.components.tool:SetAction(def.tool_action, def.tool_efficiency)

        if def.weapon ~= false then
            inst:AddComponent("weapon")
            inst.components.weapon:SetDamage(def.damage)
            if def.attackwear ~= nil then
                inst.components.weapon.attackwear = def.attackwear
            end
        end

        if def.master_postinit ~= nil then
            def.master_postinit(inst)
        end

        Ephemeral.ApplyEphemeralLifetime(inst, base)
        MakeHauntableLaunch(inst)

        return inst
    end

    return Prefab(name, fn, assets, prefabs)
end

local function MakePitchforkPrefab()
    local base = "pitchfork"
    local name = ShadowPrefabName(base)
    local assets =
    {
        Asset("ANIM", "anim/pitchfork.zip"),
        Asset("ANIM", "anim/swap_pitchfork.zip"),
    }

    local function fn()
        local inst = CreateEntity()
        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddNetwork()
        MakeInventoryPhysics(inst)
        inst.AnimState:SetBank("pitchfork")
        inst.AnimState:SetBuild("pitchfork")
        inst.AnimState:PlayAnimation("idle")
        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("weapon")
        inst.components.weapon:SetDamage(TUNING.PITCHFORK_DAMAGE)
        inst:AddInherentAction(ACTIONS.TERRAFORM)
        inst:AddComponent("inspectable")
        inst:AddComponent("inventoryitem")
        inst:AddComponent("terraformer")
        inst:AddComponent("equippable")
        inst.components.equippable:SetOnEquip(Ephemeral.WrapEquipWithTint(MakeOnEquip("swap_pitchfork", "swap_pitchfork")))
        inst.components.equippable:SetOnUnequip(Ephemeral.WrapUnequipWithTint(DefaultOnUnequip))

        Ephemeral.ApplyEphemeralLifetime(inst, base)
        MakeHauntableLaunch(inst)
        return inst
    end

    return Prefab(name, fn, assets)
end

local function MakeFarmHoePrefab()
    local base = "farm_hoe"
    local name = ShadowPrefabName(base)
    local assets =
    {
        Asset("ANIM", "anim/quagmire_hoe.zip"),
    }
    local prefabs = { "farm_soil" }

    local function fn()
        local inst = CreateEntity()
        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddNetwork()
        MakeInventoryPhysics(inst)
        inst.AnimState:SetBank("quagmire_hoe")
        inst.AnimState:SetBuild("quagmire_hoe")
        inst.AnimState:PlayAnimation("idle")
        inst:AddTag("sharp")
        inst:AddTag("weapon")
        MakeInventoryFloatable(inst, "med", 0.05, {0.9, 0.5, 0.9}, true, -7, {sym_build = "quagmire_hoe", sym_name = "swap_quagmire_hoe", anim = "idle"})
        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("inspectable")
        inst:AddComponent("inventoryitem")
        inst:AddComponent("equippable")
        inst.components.equippable:SetOnEquip(Ephemeral.WrapEquipWithTint(MakeOnEquip("quagmire_hoe", "swap_quagmire_hoe")))
        inst.components.equippable:SetOnUnequip(Ephemeral.WrapUnequipWithTint(DefaultOnUnequip))
        inst:AddComponent("weapon")
        inst.components.weapon:SetDamage(TUNING.FARM_HOE_DAMAGE)
        inst:AddInherentAction(ACTIONS.TILL)
        inst:AddComponent("farmtiller")

        Ephemeral.ApplyEphemeralLifetime(inst, base)
        MakeHauntableLaunch(inst)
        return inst
    end

    return Prefab(name, fn, assets, prefabs)
end

local function MakeRazorPrefab()
    local base = "razor"
    local name = ShadowPrefabName(base)
    local assets =
    {
        Asset("ANIM", "anim/razor.zip"),
        Asset("ANIM", "anim/swap_razor.zip"),
    }

    local function fn()
        local inst = CreateEntity()
        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddNetwork()
        MakeInventoryPhysics(inst)
        inst.AnimState:SetBank("razor")
        inst.AnimState:SetBuild("swap_razor")
        inst.AnimState:PlayAnimation("idle")
        inst:AddTag("donotautopick")
        MakeInventoryFloatable(inst, "small", 0.08, {0.9, 0.7, 0.9}, true, -2, {sym_build = "swap_razor"})
        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("inspectable")
        inst:AddComponent("inventoryitem")
        inst:AddComponent("shaver")
        Ephemeral.ApplyEphemeralLifetime(inst, base)
        MakeHauntableLaunch(inst)
        return inst
    end

    return Prefab(name, fn, assets)
end

local function MakeCanePrefab()
    local base = "cane"
    local name = ShadowPrefabName(base)
    local assets =
    {
        Asset("ANIM", "anim/cane.zip"),
        Asset("ANIM", "anim/swap_cane.zip"),
    }

    local function fn()
        local inst = CreateEntity()
        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddNetwork()
        MakeInventoryPhysics(inst)
        inst.AnimState:SetBank("cane")
        inst.AnimState:SetBuild("swap_cane")
        inst.AnimState:PlayAnimation("idle")
        inst:AddTag("weapon")
        MakeInventoryFloatable(inst, "med", 0.05, {0.85, 0.45, 0.85}, true, 1, {sym_build = "swap_cane"})
        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("weapon")
        inst.components.weapon:SetDamage(TUNING.CANE_DAMAGE)
        inst:AddComponent("inspectable")
        inst:AddComponent("inventoryitem")
        inst:AddComponent("equippable")
        inst.components.equippable:SetOnEquip(Ephemeral.WrapEquipWithTint(MakeOnEquip("swap_cane", "swap_cane")))
        inst.components.equippable:SetOnUnequip(Ephemeral.WrapUnequipWithTint(DefaultOnUnequip))
        inst.components.equippable.walkspeedmult = TUNING.CANE_SPEED_MULT

        Ephemeral.ApplyEphemeralLifetime(inst, base, V.EPHEMERAL_CANE_LIFETIME)
        MakeHauntableLaunch(inst)
        return inst
    end

    return Prefab(name, fn, assets)
end

local function MakeFishingrodPrefab()
    local base = "fishingrod"
    local name = ShadowPrefabName(base)
    local assets =
    {
        Asset("ANIM", "anim/fishingrod.zip"),
        Asset("ANIM", "anim/swap_fishingrod.zip"),
    }

    local function onunequip(inst, owner)
        DefaultOnUnequip(inst, owner)
        owner.AnimState:ClearOverrideSymbol("fishingline")
        owner.AnimState:ClearOverrideSymbol("FX_fishing")
    end

    local function onequip(inst, owner)
        local skin_build = inst:GetSkinBuild()
        if skin_build ~= nil then
            owner:PushEvent("equipskinneditem", inst:GetSkinName())
            owner.AnimState:OverrideItemSkinSymbol("swap_object", skin_build, "swap_fishingrod", inst.GUID, "swap_fishingrod")
        else
            owner.AnimState:OverrideSymbol("swap_object", "swap_fishingrod", "swap_fishingrod")
        end
        owner.AnimState:OverrideSymbol("fishingline", "swap_fishingrod", "fishingline")
        owner.AnimState:OverrideSymbol("FX_fishing", "swap_fishingrod", "FX_fishing")
        owner.AnimState:Show("ARM_carry")
        owner.AnimState:Hide("ARM_normal")
    end

    local function fn()
        local inst = CreateEntity()
        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddNetwork()
        MakeInventoryPhysics(inst)
        inst.AnimState:SetBank("fishingrod")
        inst.AnimState:SetBuild("fishingrod")
        inst.AnimState:PlayAnimation("idle")
        inst:AddTag("fishingrod")
        inst:AddTag("allow_action_on_impassable")
        inst:AddTag("weapon")
        MakeInventoryFloatable(inst, "med", 0.05, {0.8, 0.4, 0.8}, true, -12, {sym_build = "swap_fishingrod"})
        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("fishingrod")
        inst.components.fishingrod:SetWaitTimes(4, 40)
        inst.components.fishingrod:SetStrainTimes(0, 5)
        inst:AddComponent("weapon")
        inst.components.weapon:SetDamage(TUNING.FISHINGROD_DAMAGE)
        inst.components.weapon.attackwear = 4
        inst:AddComponent("inspectable")
        inst:AddComponent("inventoryitem")
        inst:AddComponent("equippable")
        inst.components.equippable:SetOnEquip(Ephemeral.WrapEquipWithTint(onequip))
        inst.components.equippable:SetOnUnequip(Ephemeral.WrapUnequipWithTint(onunequip))

        Ephemeral.ApplyEphemeralLifetime(inst, base)
        MakeHauntableLaunch(inst)
        return inst
    end

    return Prefab(name, fn, assets)
end

local function MakeTorchPrefab()
    local base = "torch"
    local name = ShadowPrefabName(base)
    local assets =
    {
        Asset("ANIM", "anim/torch.zip"),
        Asset("ANIM", "anim/swap_torch.zip"),
        Asset("SOUND", "sound/common.fsb"),
    }
    local prefabs = { "waxwell_shadow_torchfire" }

    local function onattack(weapon, attacker, target)
        if target ~= nil
            and target:IsValid()
            and target.components ~= nil
            and target.components.burnable ~= nil
            and (
                TryLuckRoll(
                    attacker,
                    TUNING.TORCH_ATTACK_IGNITE_PERCENT * target.components.burnable.flammability,
                    LuckFormulas.LighterIgniteOnAttack
                )
                or (
                    attacker.components ~= nil
                    and attacker.components.skilltreeupdater ~= nil
                    and attacker.components.skilltreeupdater:IsActivated("willow_controlled_burn_1")
                )
            ) then
            target.components.burnable:Ignite(nil, attacker)
        end
    end

    local function onequip(inst, owner)
        local skin_build = inst:GetSkinBuild()
        if skin_build ~= nil then
            owner:PushEvent("equipskinneditem", inst:GetSkinName())
            owner.AnimState:OverrideItemSkinSymbol("swap_object", skin_build, "swap_torch", inst.GUID, "swap_torch")
        else
            owner.AnimState:OverrideSymbol("swap_object", "swap_torch", "swap_torch")
        end
        owner.AnimState:Show("ARM_carry")
        owner.AnimState:Hide("ARM_normal")

        if inst.fires == nil then
            inst.fires = {}
            local fx = SpawnPrefab("waxwell_shadow_torchfire")
            fx.entity:SetParent(owner.entity)
            fx.entity:AddFollower()
            fx.Follower:FollowSymbol(owner.GUID, "swap_object", fx.fx_offset_x or 0, fx.fx_offset, 0)
            fx:AttachLightTo(owner)
            Ephemeral.ApplyTorchFireTint(fx)
            table.insert(inst.fires, fx)
        end
    end

    local function onunequip(inst, owner)
        local skin_build = inst:GetSkinBuild()
        if skin_build ~= nil then
            owner:PushEvent("unequipskinneditem", inst:GetSkinName())
        end

        if inst.fires ~= nil then
            for _, fx in ipairs(inst.fires) do
                fx:Remove()
            end
            inst.fires = nil
        end

        DefaultOnUnequip(inst, owner)
    end

    local function fn()
        local inst = CreateEntity()
        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddNetwork()
        MakeInventoryPhysics(inst)
        inst.AnimState:SetBank("torch")
        inst.AnimState:SetBuild("swap_torch")
        inst.AnimState:PlayAnimation("idle")
        inst:AddTag("wildfireprotected")
        inst:AddTag("lighter")
        inst:AddTag("waterproofer")
        inst:AddTag("weapon")
        MakeInventoryFloatable(inst, "med", nil, 0.68)
        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("weapon")
        inst.components.weapon:SetDamage(TUNING.TORCH_DAMAGE)
        inst.components.weapon:SetOnAttack(onattack)
        inst:AddComponent("lighter")
        inst:AddComponent("inventoryitem")
        inst:AddComponent("equippable")
        inst.components.equippable:SetOnEquip(Ephemeral.WrapEquipWithTint(onequip))
        inst.components.equippable:SetOnUnequip(Ephemeral.WrapUnequipWithTint(onunequip))
        inst:AddComponent("waterproofer")
        inst.components.waterproofer:SetEffectiveness(TUNING.WATERPROOFNESS_SMALL)
        inst:AddComponent("inspectable")

        Ephemeral.ApplyEphemeralLifetime(inst, base)
        MakeHauntableLaunch(inst)
        return inst
    end

    return Prefab(name, fn, assets, prefabs)
end

local function MakeMachetePrefab()
    local base = "machete"
    local name = ShadowPrefabName(base)
    local assets =
    {
        Asset("ANIM", "anim/machete.zip"),
        Asset("ANIM", "anim/swap_machete.zip"),
    }

    local function fn()
        local inst = CreateEntity()
        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddNetwork()
        MakeInventoryPhysics(inst)
        inst.AnimState:SetBank("machete")
        inst.AnimState:SetBuild("machete")
        inst.AnimState:PlayAnimation("idle")
        inst:AddTag("sharp")
        inst:AddTag("machete")
        inst:AddTag("aquatic")
        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("weapon")
        inst.components.weapon:SetDamage(TUNING.AXE_DAMAGE * .88)
        inst:AddComponent("tool")
        inst.components.tool:SetAction(ACTIONS.HACK)
        inst:AddComponent("equippable")
        inst.components.equippable:SetOnEquip(Ephemeral.WrapEquipWithTint(MakeOnEquip("swap_machete", "swap_machete")))
        inst.components.equippable:SetOnUnequip(Ephemeral.WrapUnequipWithTint(DefaultOnUnequip))
        inst:AddComponent("inspectable")
        inst:AddComponent("inventoryitem")

        Ephemeral.ApplyEphemeralLifetime(inst, base)
        return inst
    end

    return Prefab(name, fn, assets)
end

local function MakeCampfirePrefab()
    local base = "campfire"
    local name = ShadowPrefabName(base)
    local assets = { Asset("ANIM", "anim/campfire.zip") }
    local prefabs = { "campfirefire", "collapse_small", "ash", "charcoal" }

    local PROPAGATE_RANGES = { 1, 2, 3, 4 }
    local HEAT_OUTPUTS = { 2, 5, 5, 10 }

    local function onextinguish(inst)
        if inst.components.fueled ~= nil then
            inst.components.fueled:InitializeFuelLevel(0)
        end
    end

    local function ontakefuel(inst)
        inst.SoundEmitter:PlaySound("dontstarve/common/fireAddFuel")
    end

    local function updatefuelrate(inst)
        inst.components.fueled.rate = TheWorld.state.israining and inst.components.rainimmunity == nil
            and 1 + TUNING.CAMPFIRE_RAIN_RATE * TheWorld.state.precipitationrate
            or 1
    end

    local function onupdatefueled(inst)
        if inst.components.burnable ~= nil and inst.components.fueled ~= nil then
            updatefuelrate(inst)
            inst.components.burnable:SetFXLevel(inst.components.fueled:GetCurrentSection(), inst.components.fueled:GetSectionPercent())
        end
    end

    local function onfuelchange(newsection, oldsection, inst)
        if newsection <= 0 then
            if inst.components.burnable ~= nil then
                inst.components.burnable:Extinguish()
            end
            inst.persists = false
            Ephemeral.RemoveWithDespawnFX(inst)
        else
            if inst.components.burnable ~= nil and not inst.components.burnable:IsBurning() then
                updatefuelrate(inst)
                inst.components.burnable:Ignite()
            end
            inst.AnimState:PlayAnimation("idle")
            inst.components.burnable:SetFXLevel(newsection, inst.components.fueled:GetSectionPercent())
            inst.components.propagator.propagaterange = PROPAGATE_RANGES[newsection]
            inst.components.propagator.heatoutput = HEAT_OUTPUTS[newsection]
            Ephemeral.TintBurnableFireFX(inst)
        end
    end

    local function onbuilt(inst)
        inst.AnimState:PlayAnimation("place")
        inst.AnimState:PushAnimation("idle", false)
        inst.SoundEmitter:PlaySound("dontstarve/common/fireAddFuel")
    end

    local function fn()
        local inst = CreateEntity()
        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddNetwork()
        inst:SetDeploySmartRadius(1)
        MakeObstaclePhysics(inst, .2)
        inst.AnimState:SetBank("campfire")
        inst.AnimState:SetBuild("campfire")
        inst.AnimState:PlayAnimation("idle", false)
        inst:AddTag("campfire")
        inst:AddTag("NPC_workable")
        inst:AddTag("cooker")
        inst:AddTag("storytellingprop")
        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("propagator")
        inst:AddComponent("burnable")
        inst.components.burnable:AddBurnFX("campfirefire", Vector3(0, 0, 0), "firefx", true)
        inst:ListenForEvent("onextinguish", onextinguish)
        inst:AddComponent("workable")
        inst.components.workable:SetWorkAction(nil)
        inst:AddComponent("cooker")
        inst:AddComponent("fueled")
        inst.components.fueled.maxfuel = TUNING.CAMPFIRE_FUEL_MAX
        inst.components.fueled.accepting = true
        inst.components.fueled.fueltype = FUELTYPE.NIGHTMARE
        inst.components.fueled:SetSections(4)
        inst.components.fueled:SetTakeFuelFn(ontakefuel)
        inst.components.fueled:SetUpdateFn(onupdatefueled)
        inst.components.fueled:SetSectionCallback(onfuelchange)
        inst.components.fueled:InitializeFuelLevel(TUNING.CAMPFIRE_FUEL_START)
        inst.components.fueled:SetCanTakeFuelItemFn(function(fuel_inst, item)
            return item ~= nil and item.prefab == "nightmarefuel"
        end)
        inst:AddComponent("storytellingprop")
        inst:AddComponent("inspectable")
        inst:ListenForEvent("onbuilt", onbuilt)
        inst:AddComponent("hauntable")
        inst.components.hauntable:SetHauntValue(TUNING.HAUNT_SMALL)

        inst:AddTag("waxwell_shadow_ephemeral")
        Ephemeral.ApplyShadowTint(inst)
        inst:DoTaskInTime(0, Ephemeral.TintBurnableFireFX)
        return inst
    end

    return Prefab(name, fn, assets, prefabs),
        MakePlacer(name .. "_placer", "campfire", "campfire", "preview")
end

local function MakeTrapPrefab()
    local base = "trap"
    local name = ShadowPrefabName(base)
    local assets =
    {
        Asset("ANIM", "anim/trap.zip"),
        Asset("SOUND", "sound/common.fsb"),
        Asset("MINIMAP_IMAGE", "rabbittrap"),
    }

    local sounds =
    {
        close = "dontstarve/common/trap_close",
        rustle = "dontstarve/common/trap_rustle",
    }

    local function on_float(inst)
        inst.AnimState:PlayAnimation("side")
    end

    local function on_not_float(inst)
        inst.AnimState:PlayAnimation("idle")
    end

    local function fn()
        local inst = CreateEntity()
        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddMiniMapEntity()
        inst.entity:AddNetwork()
        MakeInventoryPhysics(inst)
        inst.MiniMapEntity:SetIcon("rabbittrap.png")
        inst.AnimState:SetBank("trap")
        inst.AnimState:SetBuild("trap")
        inst.AnimState:PlayAnimation("idle")
        inst:AddTag("trap")
        MakeInventoryFloatable(inst, "med", 0.05, {0.8, 0.5, 0.8})
        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst.sounds = sounds
        inst:AddComponent("inventoryitem")
        inst:AddComponent("inspectable")
        inst:AddComponent("trap")
        inst.components.trap.targettag = "canbetrapped"
        inst.components.trap:SetOnHarvestFn(function() end)
        inst.components.trap.baitsortorder = 1

        inst:ListenForEvent("floater_startfloating", on_float)
        inst:ListenForEvent("floater_stopfloating", on_not_float)

        Ephemeral.ApplyEphemeralLifetime(inst, base)
        MakeHauntableLaunch(inst)
        inst:SetStateGraph("SGtrap")
        return inst
    end

    return Prefab(name, fn, assets)
end

local function MakeBirdTrapPrefab()
    local base = "birdtrap"
    local name = ShadowPrefabName(base)
    local assets =
    {
        Asset("ANIM", "anim/birdtrap.zip"),
        Asset("SOUND", "sound/common.fsb"),
        Asset("ANIM", "anim/crow_build.zip"),
        Asset("ANIM", "anim/robin_build.zip"),
        Asset("ANIM", "anim/robin_winter_build.zip"),
        Asset("ANIM", "anim/canary_build.zip"),
        Asset("ANIM", "anim/bird_mutant_build.zip"),
        Asset("ANIM", "anim/bird_mutant_spitter_build.zip"),
    }
    local prefabs =
    {
        "crow",
        "robin",
        "robin_winter",
        "canary",
        "bird_mutant",
        "bird_mutant_spitter",
        "mutatedbird",
    }

    local sounds =
    {
        close = "dontstarve/common/birdtrap_close",
        rustle = "dontstarve/common/birdtrap_rustle",
    }

    local function CatchOffScreen(inst)
        inst._sleeptask = nil
        if not inst:IsInLimbo() and inst.components.trap ~= nil and inst.components.trap:IsBaited() and math.random() < 0.5 then
            local birdspawner = TheWorld.components.birdspawner
            if birdspawner ~= nil then
                local pos = inst:GetPosition()
                local bird = birdspawner:SpawnBird(pos)
                if bird ~= nil then
                    bird.Physics:Teleport(pos:Get())
                    bird:ReturnToScene()
                    inst.components.trap.target = bird
                    inst.components.trap:DoSpring()
                    inst.sg:GoToState("full")
                end
            end
        end
    end

    local function OnEntitySleep(inst)
        if inst._sleeptask ~= nil then
            inst._sleeptask:Cancel()
        end
        inst._sleeptask = inst:DoTaskInTime(1, CatchOffScreen)
    end

    local function OnEntityWake(inst)
        if inst._sleeptask ~= nil then
            inst._sleeptask:Cancel()
            inst._sleeptask = nil
        end
    end

    local function SetTrappedSymbols(inst, build)
        inst.trappedbuild = build
        inst.AnimState:OverrideSymbol("trapped", build, "trapped")
    end

    local function OnSpring(inst, target)
        if target.trappedbuild then
            SetTrappedSymbols(inst, target.trappedbuild)
        end
    end

    local function OnSave(inst, data)
        if inst.trappedbuild then
            data.trappedbuild = inst.trappedbuild
        end
    end

    local function OnLoad(inst, data)
        if data and data.trappedbuild then
            SetTrappedSymbols(inst, data.trappedbuild)
        end
    end

    local function fn()
        local inst = CreateEntity()
        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddMiniMapEntity()
        inst.entity:AddNetwork()
        MakeInventoryPhysics(inst)
        inst.MiniMapEntity:SetIcon("birdtrap.png")
        inst.AnimState:SetBank("birdtrap")
        inst.AnimState:SetBuild("birdtrap")
        inst.AnimState:PlayAnimation("idle")
        inst.sounds = sounds
        inst:AddTag("trap")
        MakeInventoryFloatable(inst, "large", nil, 0.75)
        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst.scrapbook_animoffsetbgx = 5
        inst.scrapbook_animoffsetbgy = 30
        inst:AddComponent("inspectable")
        inst:AddComponent("inventoryitem")
        inst:AddComponent("trap")
        inst.components.trap.targettag = "bird"
        inst.components.trap:SetOnHarvestFn(function(trap_inst)
            trap_inst.trappedbuild = nil
        end)
        inst.components.trap:SetOnSpringFn(OnSpring)
        inst.components.trap.baitsortorder = 1

        inst.OnEntitySleep = OnEntitySleep
        inst.OnEntityWake = OnEntityWake
        inst.OnSave = OnSave
        inst.OnLoad = OnLoad

        Ephemeral.ApplyEphemeralLifetime(inst, base)
        inst:SetStateGraph("SGtrap")
        return inst
    end

    return Prefab(name, fn, assets, prefabs)
end

-- Always full of water while alive: time bar uses finiteuses; watering does not deplete it.
local function MakeWateringCanPrefab()
    local base = "wateringcan"
    local name = ShadowPrefabName(base)
    local assets =
    {
        Asset("ANIM", "anim/wateringcan.zip"),
        Asset("ANIM", "anim/swap_wateringcan.zip"),
    }

    local function onequip(inst, owner)
        owner.AnimState:OverrideSymbol("swap_object", "swap_wateringcan", "swap_wateringcan")
        owner.AnimState:Show("ARM_carry")
        owner.AnimState:Hide("ARM_normal")
    end

    local function fn()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddSoundEmitter()
        inst.entity:AddNetwork()

        inst.Transform:SetTwoFaced()

        MakeInventoryPhysics(inst)

        inst.AnimState:SetBank("wateringcan")
        inst.AnimState:SetBuild("wateringcan")
        inst.AnimState:PlayAnimation("idle")

        MakeInventoryFloatable(inst, "small", 0.1, 1)

        inst:AddTag("wateringcan")

        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("inspectable")
        inst:AddComponent("inventoryitem")

        inst:AddComponent("wateryprotection")
        inst.components.wateryprotection.extinguishheatpercent = TUNING.WATERINGCAN_EXTINGUISH_HEAT_PERCENT
        inst.components.wateryprotection.temperaturereduction = TUNING.WATERINGCAN_TEMP_REDUCTION
        inst.components.wateryprotection.witherprotectiontime = TUNING.WATERINGCAN_PROTECTION_TIME
        inst.components.wateryprotection.addwetness = TUNING.WATERINGCAN_WATER_AMOUNT
        inst.components.wateryprotection.protection_dist = TUNING.WATERINGCAN_PROTECTION_DIST
        inst.components.wateryprotection:AddIgnoreTag("player")

        inst:AddComponent("equippable")
        inst.components.equippable:SetOnEquip(Ephemeral.WrapEquipWithTint(onequip))
        inst.components.equippable:SetOnUnequip(Ephemeral.WrapUnequipWithTint(DefaultOnUnequip))

        inst:AddComponent("weapon")
        inst.components.weapon:SetDamage(TUNING.UNARMED_DAMAGE)
        inst.components.weapon.attackwearmultipliers:SetModifier(inst, 0)

        Ephemeral.ApplyEphemeralLifetime(inst, base)
        MakeHauntableLaunch(inst)

        return inst
    end

    return Prefab(name, fn, assets, { "gridplacer" })
end

local function MakeUmbrellaPrefab()
    local base = "umbrella"
    local name = ShadowPrefabName(base)
    local assets =
    {
        Asset("ANIM", "anim/umbrella.zip"),
        Asset("ANIM", "anim/swap_umbrella.zip"),
    }

    local function onequip(inst, owner)
        owner.AnimState:OverrideSymbol("swap_object", "swap_umbrella", "swap_umbrella")
        owner.AnimState:Show("ARM_carry")
        owner.AnimState:Hide("ARM_normal")
        if owner.DynamicShadow ~= nil then
            owner.DynamicShadow:SetSize(2.2, 1.4)
        end
    end

    local function onunequip(inst, owner)
        DefaultOnUnequip(inst, owner)
        if owner.DynamicShadow ~= nil then
            owner.DynamicShadow:SetSize(1.3, 0.6)
        end
    end

    local function fn()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddNetwork()

        MakeInventoryPhysics(inst)

        inst.AnimState:SetBank("umbrella")
        inst.AnimState:SetBuild("umbrella")
        inst.AnimState:PlayAnimation("idle")

        inst:AddTag("nopunch")
        inst:AddTag("umbrella")
        inst:AddTag("waterproofer")

        MakeInventoryFloatable(inst, "large")

        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("tradable")
        inst:AddComponent("waterproofer")
        inst.components.waterproofer:SetEffectiveness(TUNING.WATERPROOFNESS_HUGE)

        inst:AddComponent("inspectable")
        inst:AddComponent("inventoryitem")

        inst:AddComponent("equippable")
        inst.components.equippable:SetOnEquip(Ephemeral.WrapEquipWithTint(onequip))
        inst.components.equippable:SetOnUnequip(Ephemeral.WrapUnequipWithTint(onunequip))

        inst:AddComponent("insulator")
        inst.components.insulator:SetSummer()
        inst.components.insulator:SetInsulation(TUNING.INSULATION_MED)

        if inst.components.floater ~= nil then
            inst.components.floater:SetScale({ .75, 0.35, 1.0 })
            inst.components.floater:SetBankSwapOnFloat(true, -35, {
                sym_name = "swap_umbrella_float",
                sym_build = "swap_umbrella",
            })
        end

        Ephemeral.ApplyEphemeralLifetime(inst, base)
        MakeHauntableLaunch(inst)

        return inst
    end

    return Prefab(name, fn, assets)
end

-- Single-use: play once → despawn. Also expires after 3 segments if unused.
local function MakePanFlutePrefab()
    local base = "panflute"
    local name = ShadowPrefabName(base)
    local assets =
    {
        Asset("ANIM", "anim/pan_flute.zip"),
    }

    local HEAR_ONEOF_TAGS = { "sleeper", "player", "tendable_farmplant" }

    local function HearPanFlute(inst, musician, instrument)
        if inst ~= musician
            and (TheNet:GetPVPEnabled() or not inst:HasTag("player"))
            and not (inst.components.freezable ~= nil and inst.components.freezable:IsFrozen())
            and not (inst.components.pinnable ~= nil and inst.components.pinnable:IsStuck())
            and not (inst.components.fossilizable ~= nil and inst.components.fossilizable:IsFossilized())
            and inst:HasAnyTag(HEAR_ONEOF_TAGS) then
            local sleeptime = instrument.panflute_sleeptime or TUNING.PANFLUTE_SLEEPTIME
            local mount = inst.components.rider ~= nil and inst.components.rider:GetMount() or nil
            if mount ~= nil then
                mount:PushEvent("ridersleep", { sleepiness = 10, sleeptime = sleeptime })
            end
            if inst.components.farmplanttendable ~= nil then
                inst.components.farmplanttendable:TendTo(musician)
            elseif inst.components.sleeper ~= nil then
                inst.components.sleeper:AddSleepiness(10, sleeptime)
            elseif inst.components.grogginess ~= nil then
                inst.components.grogginess:AddGrogginess(10, sleeptime)
            else
                inst:PushEvent("knockedout")
            end
        end
    end

    local function OnPlayed(inst, musician)
        inst.panflute_sleeptime = TUNING.PANFLUTE_SLEEPTIME
    end

    local function OnFinishedPlaying(inst, musician)
        Ephemeral.RemoveWithDespawnFX(inst)
    end

    local function fn()
        local inst = CreateEntity()

        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddNetwork()

        MakeInventoryPhysics(inst)

        inst:AddTag("flute")
        inst:AddTag("tool")

        inst.AnimState:SetBank("pan_flute")
        inst.AnimState:SetBuild("pan_flute")
        inst.AnimState:PlayAnimation("idle")

        MakeInventoryFloatable(inst, "small", 0.05, 0.8)

        inst.entity:SetPristine()

        if not TheWorld.ismastersim then
            return inst
        end

        inst:AddComponent("inspectable")
        inst:AddComponent("instrument")
        inst.components.instrument:SetRange(TUNING.PANFLUTE_SLEEPRANGE)
        inst.components.instrument:SetOnPlayedFn(OnPlayed)
        inst.components.instrument:SetOnHeardFn(HearPanFlute)
        inst.components.instrument:SetOnFinishedPlayingFn(OnFinishedPlaying)

        inst:AddComponent("tool")
        inst.components.tool:SetAction(ACTIONS.PLAY)

        inst:AddComponent("inventoryitem")

        -- Time bar only — no PLAY consumption; one successful play despawns above.
        Ephemeral.ApplyEphemeralLifetime(inst, base)
        MakeHauntableLaunch(inst)

        inst:ListenForEvent("floater_startfloating", function(flute)
            flute.AnimState:PlayAnimation("float")
        end)
        inst:ListenForEvent("floater_stopfloating", function(flute)
            flute.AnimState:PlayAnimation("idle")
        end)

        return inst
    end

    return Prefab(name, fn, assets)
end

local HAND_TOOL_DEFS =
{
    axe =
    {
        assets = { Asset("ANIM", "anim/axe.zip"), Asset("ANIM", "anim/swap_axe.zip") },
        bank = "axe", build = "axe", swap_build = "swap_axe", sym_name = "swap_axe",
        tags = { "sharp", "possessable_axe" },
        tool_action = ACTIONS.CHOP, damage = TUNING.AXE_DAMAGE,
        floater = { "small", 0.05, {1.2, 0.75, 1.2}, true, -11, {sym_build = "swap_axe", sym_name = "swap_axe", anim = "idle"} },
    },
    pickaxe =
    {
        assets = { Asset("ANIM", "anim/pickaxe.zip"), Asset("ANIM", "anim/swap_pickaxe.zip") },
        bank = "pickaxe", build = "pickaxe", swap_build = "swap_pickaxe", sym_name = "swap_pickaxe",
        tags = { "sharp" },
        tool_action = ACTIONS.MINE, damage = TUNING.PICK_DAMAGE,
        floater = { "small", 0.05, {1.1, 0.6, 1.1}, true, -11, {sym_build = "swap_pickaxe", sym_name = "swap_pickaxe", anim = "idle"} },
    },
    shovel =
    {
        assets = { Asset("ANIM", "anim/shovel.zip"), Asset("ANIM", "anim/swap_shovel.zip") },
        bank = "shovel", build = "shovel", swap_build = "swap_shovel", sym_name = "swap_shovel",
        tool_action = ACTIONS.DIG, damage = TUNING.SHOVEL_DAMAGE,
        floater = { "small", 0.05, {1.1, 0.45, 1.1}, true, -11, {sym_build = "swap_shovel", sym_name = "swap_shovel", anim = "idle"} },
    },
    hammer =
    {
        assets = { Asset("ANIM", "anim/hammer.zip"), Asset("ANIM", "anim/swap_hammer.zip") },
        bank = "hammer", build = "hammer", swap_build = "swap_hammer", sym_name = "swap_hammer",
        tool_action = ACTIONS.HAMMER, damage = TUNING.HAMMER_DAMAGE,
        floater = { "small", 0.05, {1.1, 0.45, 1.1}, true, -11, {sym_build = "swap_hammer", sym_name = "swap_hammer", anim = "idle"} },
    },
    bugnet =
    {
        assets = { Asset("ANIM", "anim/bugnet.zip"), Asset("ANIM", "anim/swap_bugnet.zip") },
        bank = "bugnet", build = "swap_bugnet", swap_build = "swap_bugnet", sym_name = "swap_bugnet",
        tool_action = ACTIONS.NET, damage = TUNING.BUGNET_DAMAGE,
        attackwear = 3,
        floater = { "med", 0.09, {0.9, 0.4, 0.9}, true, -14.5, {sym_build = "swap_bugnet"} },
    },
}

local function BuildPrefabs()
    local out = {}

    for base, def in pairs(HAND_TOOL_DEFS) do
        table.insert(out, MakeHandToolPrefab(base, def))
    end

    table.insert(out, MakePitchforkPrefab())
    table.insert(out, MakeFarmHoePrefab())
    table.insert(out, MakeRazorPrefab())
    table.insert(out, MakeCanePrefab())
    table.insert(out, MakeFishingrodPrefab())
    table.insert(out, MakeTorchPrefab())
    table.insert(out, MakeTrapPrefab())
    table.insert(out, MakeBirdTrapPrefab())
    table.insert(out, MakeWateringCanPrefab())
    table.insert(out, MakeUmbrellaPrefab())
    table.insert(out, MakePanFlutePrefab())

    if ModCompat.HasTropicalMacheteSupport() and PrefabExists("machete") then
        table.insert(out, MakeMachetePrefab())
    end

    local campfire, placer = MakeCampfirePrefab()
    table.insert(out, campfire)
    table.insert(out, placer)

    return out
end

return {
    ShadowPrefabName = ShadowPrefabName,
    BuildPrefabs = BuildPrefabs,
}
