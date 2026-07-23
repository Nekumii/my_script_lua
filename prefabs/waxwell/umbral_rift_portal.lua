local assets =
{
    Asset("ANIM", "anim/pocketwatch_portal_fx.zip"),
}

local prefabs =
{
    "umbral_rift_portal_overlay",
    "umbral_rift_portal_underlay",
}

local PORTAL_DURATION_DEFAULT = 10
local PORTAL_TINT = { .18, .18, .18, 1 }
local PORTAL_LIGHT_COLOUR = { .2, .2, .24 }

-- Lazy require: avoid circular load with DE while still refreshing aggro after warp.
local outside_target_block
local function RefreshDomainTargetingAfterPortal(obj)
    if obj == nil or not obj:IsValid() then
        return
    end
    if outside_target_block == nil then
        local ok, mod = pcall(require, "skill_effect/waxwell/emperor/domain_expansion/outside_target_block")
        if ok then
            outside_target_block = mod
        end
    end
    if outside_target_block ~= nil
        and outside_target_block.HasActiveFields ~= nil
        and outside_target_block.HasActiveFields()
        and outside_target_block.RefreshCombatFocusAroundEntity ~= nil then
        outside_target_block.RefreshCombatFocusAroundEntity(obj, 40)
    end
end

local function ApplyPortalTint(animstate)
    animstate:SetMultColour(unpack(PORTAL_TINT))
end

local function PlayCloseAnimation(inst)
    inst.AnimState:PlayAnimation("portal_entrance_pst")
    if inst.overlay ~= nil and inst.overlay:IsValid() then
        inst.overlay.AnimState:PlayAnimation("portal_entrance_pst")
    end
    if inst.underlay ~= nil and inst.underlay:IsValid() then
        inst.underlay.AnimState:PlayAnimation("portal_entrance_pst")
    end
end

local function FinishPortalClose(inst)
    inst.Light:Enable(false)
    inst.SoundEmitter:KillSound("loop")
    inst.SoundEmitter:PlaySound("wanda1/wanda/portal_entrance_pst")
    PlayCloseAnimation(inst)
    inst.persists = false
    inst:DoTaskInTime(inst.AnimState:GetCurrentAnimationLength() + .2, inst.Remove)
end

local function HasRegisteredTeleportee(inst)
    return inst ~= nil
        and inst.components ~= nil
        and inst.components.teleporter ~= nil
        and inst.components.teleporter.teleportees ~= nil
        and next(inst.components.teleporter.teleportees) ~= nil
end

local function HasPendingPortalUser(inst)
    for _, player in ipairs(AllPlayers) do
        if player ~= nil
            and player:IsValid()
            and player.sg ~= nil
            and player.sg.currentstate ~= nil
            and (player.sg.currentstate.name == "entertownportal" or player.sg.currentstate.name == "jumpin")
            and player.sg.statemem ~= nil
            and player.sg.statemem.target == inst then
            return true
        end
    end
    return HasRegisteredTeleportee(inst)
end

local ClosePortal
local CloseSinglePortal
local HasActiveTeleportGrace

local function LockPortalUse(inst)
    if inst ~= nil and inst.components.teleporter ~= nil then
        inst.components.teleporter:SetEnabled(false)
    end
end

local function DisablePortalUse(inst)
    if inst ~= nil and inst.components.teleporter ~= nil then
        inst.components.teleporter:Target(nil)
        inst.components.teleporter:SetEnabled(false)
    end
end

local function StartDeferredClose(inst, skipsibling)
    if inst == nil or not inst:IsValid() then
        return
    end

    if skipsibling == false then
        inst._deferred_close_skipsibling = false
    elseif inst._deferred_close_skipsibling == nil then
        inst._deferred_close_skipsibling = skipsibling
    end

    if not HasPendingPortalUser(inst) then
        LockPortalUse(inst)
    end

    if inst._deferred_close_task == nil then
        inst._deferred_close_task = inst:DoPeriodicTask(.1, function(portal)
            if not portal:IsValid() then
                return
            end

            if HasActiveTeleportGrace(portal)
                or HasPendingPortalUser(portal)
                or (portal.components.teleporter ~= nil and portal.components.teleporter:IsBusy()) then
                return
            end

            if portal._deferred_close_task ~= nil then
                portal._deferred_close_task:Cancel()
                portal._deferred_close_task = nil
            end

            local deferred_skipsibling = portal._deferred_close_skipsibling
            portal._deferred_close_skipsibling = nil
            ClosePortal(portal, deferred_skipsibling)
        end)
    end
end

HasActiveTeleportGrace = function(inst)
    return inst ~= nil
        and inst._teleport_grace_end_time ~= nil
        and GetTime() < inst._teleport_grace_end_time
end

local ClearIncomingTeleport

local function MarkIncomingTeleport(inst, doer)
    if inst == nil or not inst:IsValid() or doer == nil or not doer:IsValid() then
        return
    end

    inst._incoming_teleportees = inst._incoming_teleportees or {}
    if not inst._incoming_teleportees[doer] then
        inst._incoming_teleportees[doer] = true
        inst._incoming_teleportee_count = (inst._incoming_teleportee_count or 0) + 1
    end

    doer._umbral_rift_arrival_portal = inst
    if doer._umbral_rift_arrival_state_fn == nil then
        doer._umbral_rift_arrival_state_fn = function(player)
            local portal = player._umbral_rift_arrival_portal
            local currentstate = player.sg ~= nil and player.sg.currentstate ~= nil and player.sg.currentstate.name or nil
            if portal == nil
                or currentstate == nil
                or (currentstate ~= "exittownportal_pre" and currentstate ~= "exittownportal" and currentstate ~= "jumpout") then
                if portal ~= nil and portal:IsValid() then
                    ClearIncomingTeleport(portal, player)
                end
            end
        end
        doer:ListenForEvent("newstate", doer._umbral_rift_arrival_state_fn)
        doer:ListenForEvent("onremove", doer._umbral_rift_arrival_state_fn)
    end
end

ClearIncomingTeleport = function(inst, doer)
    if inst == nil or inst._incoming_teleportees == nil or doer == nil then
        return
    end

    if inst._incoming_teleportees[doer] then
        inst._incoming_teleportees[doer] = nil
        inst._incoming_teleportee_count = math.max(0, (inst._incoming_teleportee_count or 1) - 1)
    end

    if doer._umbral_rift_arrival_portal == inst then
        doer._umbral_rift_arrival_portal = nil
        if doer._umbral_rift_arrival_state_fn ~= nil then
            doer:RemoveEventCallback("newstate", doer._umbral_rift_arrival_state_fn)
            doer:RemoveEventCallback("onremove", doer._umbral_rift_arrival_state_fn)
            doer._umbral_rift_arrival_state_fn = nil
        end
    end
end

local function HasIncomingTeleport(inst)
    return inst ~= nil
        and (inst._incoming_teleportee_count or 0) > 0
end

local function IsPortalShutdownBlocked(inst)
    return inst ~= nil
        and inst:IsValid()
        and (
            HasActiveTeleportGrace(inst)
            or HasPendingPortalUser(inst)
            or HasIncomingTeleport(inst)
            or (inst.components.teleporter ~= nil and inst.components.teleporter:IsBusy())
        )
end

local function RequestPortalShutdown(inst, skipsibling)
    if inst == nil or not inst:IsValid() or inst._closing then
        return
    end

    if not HasPendingPortalUser(inst) then
        LockPortalUse(inst)
    end

    if HasActiveTeleportGrace(inst)
        or HasPendingPortalUser(inst)
        or (inst.components.teleporter ~= nil and inst.components.teleporter:IsBusy()) then
        StartDeferredClose(inst, skipsibling)
    else
        ClosePortal(inst, skipsibling)
    end
end

local function RequestPairShutdown(inst)
    if inst == nil or not inst:IsValid() then
        return
    end

    local linked = inst._linked_portal
    if linked ~= nil and linked:IsValid() then
        inst._shutdown_partner = linked
        linked._shutdown_partner = inst
    end

    local function tryclosepair(portal)
        if portal == nil or not portal:IsValid() or portal._closing then
            if portal ~= nil and portal._pair_close_task ~= nil then
                portal._pair_close_task:Cancel()
                portal._pair_close_task = nil
            end
            return
        end

        local partner = portal._shutdown_partner
        local selfpending = HasPendingPortalUser(portal)
        local partnerpending = partner ~= nil and partner:IsValid() and HasPendingPortalUser(partner)
        local selfincoming = HasIncomingTeleport(portal)
        local partnerincoming = partner ~= nil and partner:IsValid() and HasIncomingTeleport(partner)

        if selfpending and partnerpending then
            return
        end

        if selfpending then
            if partner ~= nil and partner:IsValid() then
                LockPortalUse(partner)
            end
            return
        end

        if partnerpending then
            LockPortalUse(portal)
            return
        end

        if portal._pair_close_task ~= nil then
            portal._pair_close_task:Cancel()
            portal._pair_close_task = nil
        end
        if partner ~= nil and partner._pair_close_task ~= nil then
            partner._pair_close_task:Cancel()
            partner._pair_close_task = nil
        end

        if selfincoming and partnerincoming then
            if portal._pair_close_task == nil then
                portal._pair_close_task = portal:DoPeriodicTask(.1, tryclosepair)
            end
            if partner ~= nil and partner:IsValid() and partner._pair_close_task == nil then
                partner._pair_close_task = partner:DoPeriodicTask(.1, tryclosepair)
            end
            return
        elseif selfincoming then
            StartDeferredClose(portal, true)
            if partner ~= nil and partner:IsValid() and not partner._closing then
                CloseSinglePortal(partner)
            end
            return
        elseif partnerincoming then
            if not portal._closing then
                CloseSinglePortal(portal)
            end
            if partner ~= nil and partner:IsValid() then
                StartDeferredClose(partner, true)
            end
            return
        end

        ClosePortal(portal, false)
    end

    if inst._pair_close_task == nil then
        inst._pair_close_task = inst:DoPeriodicTask(.1, tryclosepair)
    end
    if linked ~= nil and linked:IsValid() and linked._pair_close_task == nil then
        linked._pair_close_task = linked:DoPeriodicTask(.1, tryclosepair)
    end
end

CloseSinglePortal = function(inst)
    if inst == nil or not inst:IsValid() or inst._closing then
        return
    elseif HasActiveTeleportGrace(inst) then
        StartDeferredClose(inst, true)
        return
    elseif HasPendingPortalUser(inst) then
        StartDeferredClose(inst, true)
        return
    elseif HasIncomingTeleport(inst) then
        StartDeferredClose(inst, true)
        return
    elseif inst.components.teleporter ~= nil and inst.components.teleporter:IsBusy() then
        StartDeferredClose(inst, true)
        return
    end

    inst._closing = true

    if inst._deferred_close_task ~= nil then
        inst._deferred_close_task:Cancel()
        inst._deferred_close_task = nil
    end
    if inst._pair_close_task ~= nil then
        inst._pair_close_task:Cancel()
        inst._pair_close_task = nil
    end

    inst._deferred_close_skipsibling = nil
    inst._linked_portal = nil
    inst._shutdown_partner = nil

    DisablePortalUse(inst)
    FinishPortalClose(inst)
end

ClosePortal = function(inst, skipsibling)
    if inst._closing then
        return
    elseif HasActiveTeleportGrace(inst) then
        StartDeferredClose(inst, skipsibling)
        return
    elseif HasPendingPortalUser(inst) then
        StartDeferredClose(inst, skipsibling)
        return
    elseif inst.components.teleporter ~= nil and inst.components.teleporter:IsBusy() then
        StartDeferredClose(inst, skipsibling)
        return
    end

    inst._closing = true
    local linked = inst._linked_portal
    inst._linked_portal = nil

    if inst._deferred_close_task ~= nil then
        inst._deferred_close_task:Cancel()
        inst._deferred_close_task = nil
    end
    if inst._pair_close_task ~= nil then
        inst._pair_close_task:Cancel()
        inst._pair_close_task = nil
    end
    inst._deferred_close_skipsibling = nil
    inst._shutdown_partner = nil

    DisablePortalUse(inst)

    if linked ~= nil and linked:IsValid() then
        if linked._pair_close_task ~= nil then
            linked._pair_close_task:Cancel()
            linked._pair_close_task = nil
        end
        linked._shutdown_partner = nil
        linked._linked_portal = nil
        DisablePortalUse(linked)
    end

    if not skipsibling and linked ~= nil and linked:IsValid() then
        ClosePortal(linked, true)
    end

    FinishPortalClose(inst)
end

local function OnTimerDone(inst, data)
    if data ~= nil and data.name == "closeportal" then
        RequestPairShutdown(inst)
    end
end

local function OnActivate(inst, doer)
    if inst == nil
        or inst._closing
        or inst.components.teleporter == nil
        or not inst.components.teleporter.enabled
        or inst._linked_portal == nil
        or not inst._linked_portal:IsValid() then
        return
    end

    if doer ~= nil and doer:HasTag("player") then
        MarkIncomingTeleport(inst._linked_portal, doer)
        RefreshDomainTargetingAfterPortal(doer)
    end

    local grace_end_time = GetTime() + 1
    inst._teleport_grace_end_time = grace_end_time
    inst._linked_portal._teleport_grace_end_time = grace_end_time

    if doer ~= nil and doer.components.talker ~= nil then
        doer.components.talker:ShutUp()
    end
end

local function LinkPortal(inst, other)
    inst._linked_portal = other
    if inst.components.teleporter ~= nil then
        inst.components.teleporter:Target(other)
    end
end

local function SetLifetime(inst, duration)
    if inst.components.timer ~= nil then
        inst.components.timer:StopTimer("closeportal")
        inst.components.timer:StartTimer("closeportal", duration or PORTAL_DURATION_DEFAULT)
    end
end

local function OnRemovePortal(inst)
    local linked = inst._linked_portal
    inst._linked_portal = nil
    if linked ~= nil and linked:IsValid() and not linked._closing then
        ClosePortal(linked, true)
    end
end

local function MarkUmbralRift2(inst)
    inst._umbral_rift_2 = true
end

local function common_visual_fn(inst, isunderlay)
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("pocketwatch_portal_fx")
    inst.AnimState:SetBuild("pocketwatch_portal_fx")
    inst.AnimState:PlayAnimation("portal_entrance_pre")
    inst.AnimState:PushAnimation("portal_entrance_loop", true)
    inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
    ApplyPortalTint(inst.AnimState)

    if isunderlay then
        inst.AnimState:SetLayer(LAYER_BELOW_GROUND)
        inst.AnimState:SetSortOrder(ANIM_SORT_ORDER_BELOW_GROUND.BOAT_LIP)
        inst.AnimState:SetFinalOffset(3)
        inst.AnimState:SetOceanBlendParams(TUNING.OCEAN_SHADER.EFFECT_TINT_AMOUNT)
        inst.AnimState:SetInheritsSortKey(false)
        inst.AnimState:Hide("front")
        inst.AnimState:Hide("back")
    else
        inst.AnimState:SetInheritsSortKey(false)
        inst.AnimState:Hide("back")
        inst.AnimState:Hide("water_shadow")
    end

    inst:AddTag("FX")
    inst:AddTag("umbral_rift_portal")
    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false
    return inst
end

local function overlayfn()
    local inst = CreateEntity()
    return common_visual_fn(inst, false)
end

local function underlayfn()
    local inst = CreateEntity()
    return common_visual_fn(inst, true)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddLight()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("pocketwatch_portal_fx")
    inst.AnimState:SetBuild("pocketwatch_portal_fx")
    inst.AnimState:PlayAnimation("portal_entrance_pre")
    inst.AnimState:PushAnimation("portal_entrance_loop", true)
    inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
    inst.AnimState:SetSortOrder(-1)
    inst.AnimState:Hide("front")
    inst.AnimState:Hide("water_shadow")
    ApplyPortalTint(inst.AnimState)

    inst.Light:SetRadius(1.6)
    inst.Light:SetIntensity(.45)
    inst.Light:SetFalloff(1.5)
    inst.Light:SetColour(unpack(PORTAL_LIGHT_COLOUR))
    inst.Light:Enable(true)
    inst.Light:EnableClientModulation(true)

    inst:AddTag("ignorewalkableplatforms")
    inst:SetPhysicsRadiusOverride(1)
    inst:SetPrefabNameOverride("umbral_rift_portal")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("timer")
    inst:AddComponent("teleporter")
    inst.components.teleporter.offset = 3
    inst.components.teleporter.trynooffset = true
    inst.components.teleporter.jumpinanim = nil
    inst.components.teleporter.overrideteleportarrivestate = "jumpout"
    inst.components.teleporter.stopcamerafades = true
    inst.components.teleporter.travelcameratime = 0
    inst.components.teleporter.travelarrivetime = 0.15
    inst.components.teleporter.onActivate = OnActivate
    inst.components.teleporter.OnDoneTeleporting = function(portal, obj)
        RefreshDomainTargetingAfterPortal(obj)
        if obj ~= nil and obj:IsValid() and obj._umbral_rift_arrival_state_fn ~= nil then
            obj._umbral_rift_arrival_state_fn(obj)
        else
            ClearIncomingTeleport(portal, obj)
        end
    end

    inst:ListenForEvent("timerdone", OnTimerDone)
    inst.SoundEmitter:PlaySound("wanda1/wanda/portal_entrance_pre")
    inst:DoTaskInTime(25 * FRAMES, function(portal)
        if portal:IsValid() and not portal._closing then
            portal.SoundEmitter:PlaySound("wanda2/characters/wanda/watch/portal_LP", "loop")
        end
    end)

    inst.overlay = SpawnPrefab("umbral_rift_portal_overlay")
    if inst.overlay ~= nil then
        inst.overlay.entity:SetParent(inst.entity)
        inst.highlightchildren = { inst.overlay }
    end

    inst.underlay = SpawnPrefab("umbral_rift_portal_underlay")
    if inst.underlay ~= nil then
        inst.underlay.entity:SetParent(inst.entity)
    end

    inst.OnSave = function(portal, data)
        if data ~= nil then
            data._umbral_rift_2 = portal._umbral_rift_2 or nil
            data._linked_portal = portal._linked_portal ~= nil and portal._linked_portal.GUID or nil
        end
        return portal._linked_portal ~= nil and { portal._linked_portal.GUID } or nil
    end

    inst.OnLoad = function(portal, data)
        if data ~= nil and data._umbral_rift_2 then
            portal._umbral_rift_2 = true
        end
        portal._linked_portal_guid = data ~= nil and data._linked_portal or nil
    end

    inst.LoadPostPass = function(portal, newents, data)
        if portal._linked_portal_guid ~= nil and newents ~= nil then
            local linked = newents[portal._linked_portal_guid]
            linked = linked ~= nil and linked.entity or nil
            if linked ~= nil and linked:IsValid() then
                portal:LinkPortal(linked)
            end
        end
    end

    inst.LinkPortal = LinkPortal
    inst.SetLifetime = SetLifetime
    inst.ClosePortal = ClosePortal
    inst.MarkUmbralRift2 = MarkUmbralRift2
    inst.OnRemoveEntity = OnRemovePortal

    return inst
end

return Prefab("umbral_rift_portal", fn, assets, prefabs),
    Prefab("umbral_rift_portal_overlay", overlayfn, assets),
    Prefab("umbral_rift_portal_underlay", underlayfn, assets)
