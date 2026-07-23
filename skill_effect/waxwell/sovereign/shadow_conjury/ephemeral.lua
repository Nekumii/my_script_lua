local V = require("skill_effect/waxwell/sovereign/shadow_conjury/variables")

local TIME_BAR_MAX = 100
local TIME_BAR_TICK = 1

local function ApplyShadowTint(inst)
    if inst.AnimState ~= nil then
        inst.AnimState:SetMultColour(V.SHADOW_TINT.r, V.SHADOW_TINT.g, V.SHADOW_TINT.b, V.SHADOW_TINT.a)
    end
end

local function ScheduleShadowTint(inst)
    if inst == nil or not inst:IsValid() then
        return
    end

    ApplyShadowTint(inst)
    inst:DoTaskInTime(0, function()
        if inst:IsValid() then
            ApplyShadowTint(inst)
        end
    end)
end

local function ApplyFireTint(fx)
    if fx ~= nil and fx.AnimState ~= nil then
        fx.AnimState:SetMultColour(V.FIRE_TINT.r, V.FIRE_TINT.g, V.FIRE_TINT.b, V.FIRE_TINT.a)
    end
end

local function TintBurnableFireFX(inst)
    if inst == nil or inst.components == nil or inst.components.burnable == nil then
        return
    end

    for _, fx in ipairs(inst.components.burnable.fxchildren) do
        ApplyFireTint(fx)
    end
end

local function ApplyTorchFireTint(fx)
    if fx == nil then
        return
    end

    if fx._light ~= nil and fx._light.Light ~= nil then
        local t = V.FIRE_TINT
        fx._light.Light:SetColour(t.r, t.g, t.b)
        fx._light.Light:SetIntensity(.04)
    end
end

local function ApplyEquippedTint(owner)
    if owner ~= nil and owner.AnimState ~= nil then
        local r, g, b, a = V.SHADOW_TINT.r, V.SHADOW_TINT.g, V.SHADOW_TINT.b, V.SHADOW_TINT.a
        for _, sym in ipairs({ "swap_object", "fishingline", "FX_fishing" }) do
            owner.AnimState:SetSymbolMultColour(sym, r, g, b, a)
        end
    end
end

local function ClearEquippedTint(owner)
    if owner ~= nil and owner.AnimState ~= nil then
        for _, sym in ipairs({ "swap_object", "fishingline", "FX_fishing" }) do
            owner.AnimState:SetSymbolMultColour(sym, 1, 1, 1, 1)
        end
    end
end

local function WrapEquipWithTint(on_equip)
    return function(inst, owner)
        if on_equip ~= nil then
            on_equip(inst, owner)
        end
        ApplyEquippedTint(owner)
        if owner ~= nil then
            owner:DoTaskInTime(0, function()
                if owner:IsValid() then
                    ApplyEquippedTint(owner)
                end
            end)
        end
    end
end

local function WrapUnequipWithTint(on_unequip)
    return function(inst, owner)
        if on_unequip ~= nil then
            on_unequip(inst, owner)
        end
        ClearEquippedTint(owner)
        ScheduleShadowTint(inst)
    end
end

local function DetachFX(fx)
    fx.Transform:SetPosition(fx.Transform:GetWorldPosition())
    fx.entity:SetParent(nil)
end

local function PlayDespawnFX(inst)
    if inst == nil or not inst:IsValid() then
        return
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    local fx1 = SpawnPrefab("shadow_despawn")
    local fx2 = SpawnPrefab("shadow_glob_fx")
    if fx1 == nil or fx2 == nil then
        return
    end

    fx2.AnimState:SetScale(math.random() < .5 and -1.3 or 1.3, 1.3, 1.3)
    local platform = inst:GetCurrentPlatform()
    if platform ~= nil then
        fx1.entity:SetParent(platform.entity)
        fx2.entity:SetParent(platform.entity)
        fx1:ListenForEvent("onremove", function()
            DetachFX(fx1)
        end, platform)
        x, y, z = platform.entity:WorldToLocalSpace(x, y, z)
    end
    fx1.Transform:SetPosition(x, y, z)
    fx2.Transform:SetPosition(x, y, z)
end

local function CancelTimeBarTask(inst)
    if inst._waxwell_shadow_timebar_task ~= nil then
        inst._waxwell_shadow_timebar_task:Cancel()
        inst._waxwell_shadow_timebar_task = nil
    end
end

local function GetRemainingLifetime(inst)
    if inst._waxwell_shadow_expire_time == nil then
        return 0
    end
    return inst._waxwell_shadow_expire_time - GetTime()
end

local function SyncTimeBarPercent(inst)
    if inst.components.finiteuses == nil then
        return
    end

    local remaining = GetRemainingLifetime(inst)
    if remaining <= 0 then
        inst.components.finiteuses:SetPercent(0)
        return
    end

    local lifetime = inst._waxwell_shadow_lifetime or V.EPHEMERAL_LIFETIME
    inst.components.finiteuses:SetPercent(remaining / lifetime)
end

local function ReleaseTrapContents(inst)
    local trapcmp = inst.components.trap
    if trapcmp == nil or not trapcmp.issprung or trapcmp.lootprefabs == nil then
        return
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    local timeintrap = inst.components.timer ~= nil and inst.components.timer:GetTimeElapsed("foodspoil") or 0

    for _, prefab in ipairs(trapcmp.lootprefabs) do
        local loot = SpawnPrefab(prefab)
        if loot ~= nil then
            if loot.restoredatafromtrap ~= nil then
                loot:restoredatafromtrap(trapcmp.lootdata)
            end
            loot.Transform:SetPosition(x, y, z)
            if loot.ReturnToScene ~= nil then
                loot:ReturnToScene()
            end
            if loot.components.perishable ~= nil then
                loot.components.perishable:LongUpdate(timeintrap)
            end
        end
    end

    if trapcmp.numsouls ~= nil then
        TheWorld:PushEvent("starvedtrapsouls", { numsouls = trapcmp.numsouls, trap = inst })
    end

    trapcmp:StopStarvation()
end

local function RemoveWithDespawnFX(inst)
    if inst == nil or not inst:IsValid() or inst._waxwell_shadow_despawning then
        return
    end

    inst._waxwell_shadow_despawning = true
    CancelTimeBarTask(inst)
    ReleaseTrapContents(inst)
    PlayDespawnFX(inst)
    inst:Remove()
end

local function TickTimeBar(inst)
    local remaining = GetRemainingLifetime(inst)
    if remaining <= 0 then
        RemoveWithDespawnFX(inst)
        return
    end

    SyncTimeBarPercent(inst)
end

local function StartTimeBar(inst)
    CancelTimeBarTask(inst)
    SyncTimeBarPercent(inst)
    inst._waxwell_shadow_timebar_task = inst:DoPeriodicTask(TIME_BAR_TICK, TickTimeBar)
end

local function ChainOnSave(inst, fn)
    local old = inst.OnSave
    inst.OnSave = function(save_inst, data)
        if old ~= nil then
            old(save_inst, data)
        end
        fn(save_inst, data)
    end
end

local function ChainOnLoad(inst, fn)
    local old = inst.OnLoad
    inst.OnLoad = function(load_inst, data)
        if old ~= nil then
            old(load_inst, data)
        end
        fn(load_inst, data)
    end
end

local function ApplyVanillaInventoryImage(inst, imagename)
    if inst.components.inventoryitem ~= nil and imagename ~= nil then
        inst.components.inventoryitem.imagename = imagename
    end
end

local function ApplyTimeBar(inst)
    inst:AddComponent("finiteuses")
    inst.components.finiteuses:SetMaxUses(TIME_BAR_MAX)
    inst.components.finiteuses:SetUses(TIME_BAR_MAX)
    inst.components.finiteuses:SetOnFinished(RemoveWithDespawnFX)
end

local function ApplyEphemeralLifetime(inst, imagename, lifetime)
    inst:AddTag("waxwell_shadow_ephemeral")
    -- Block use as a crafting ingredient in any other recipe (checked in GetCraftingIngredient).
    inst:AddTag("nocrafting")

    ScheduleShadowTint(inst)
    ApplyVanillaInventoryImage(inst, imagename)
    ApplyTimeBar(inst)

    lifetime = lifetime or V.EPHEMERAL_LIFETIME
    inst._waxwell_shadow_lifetime = lifetime
    inst._waxwell_shadow_expire_time = GetTime() + lifetime

    inst:ListenForEvent("unequipped", ScheduleShadowTint)
    inst:ListenForEvent("onputininventory", ScheduleShadowTint)
    inst:ListenForEvent("ondropped", ScheduleShadowTint)

    if inst.components.inventoryitem ~= nil then
        local old_onputin = inst.components.inventoryitem.onputininventoryfn
        inst.components.inventoryitem:SetOnPutInInventoryFn(function(item, owner)
            if old_onputin ~= nil then
                old_onputin(item, owner)
            end
            ScheduleShadowTint(item)
        end)
    end

    ChainOnSave(inst, function(save_inst, data)
        data.waxwell_shadow_expire_time = save_inst._waxwell_shadow_expire_time
        data.waxwell_shadow_lifetime = save_inst._waxwell_shadow_lifetime
    end)

    ChainOnLoad(inst, function(load_inst, data)
        if data ~= nil then
            if data.waxwell_shadow_lifetime ~= nil then
                load_inst._waxwell_shadow_lifetime = data.waxwell_shadow_lifetime
            end
            if data.waxwell_shadow_expire_time ~= nil then
                load_inst._waxwell_shadow_expire_time = data.waxwell_shadow_expire_time
            end
        end
        StartTimeBar(load_inst)
        ScheduleShadowTint(load_inst)
    end)

    StartTimeBar(inst)
end

return {
    ApplyShadowTint = ApplyShadowTint,
    ScheduleShadowTint = ScheduleShadowTint,
    ApplyFireTint = ApplyFireTint,
    ApplyTorchFireTint = ApplyTorchFireTint,
    TintBurnableFireFX = TintBurnableFireFX,
    ApplyEquippedTint = ApplyEquippedTint,
    ClearEquippedTint = ClearEquippedTint,
    WrapEquipWithTint = WrapEquipWithTint,
    WrapUnequipWithTint = WrapUnequipWithTint,
    PlayDespawnFX = PlayDespawnFX,
    RemoveWithDespawnFX = RemoveWithDespawnFX,
    ApplyEphemeralLifetime = ApplyEphemeralLifetime,
}
