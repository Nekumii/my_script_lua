-- Shadow Reliquary — Codex Umbra ground recharge (dock at winch, repair fueled, UR parity).
local V = require("skill_effect/waxwell/emperor/shadow_reliquary/variables")

local CODEX_PREFAB = V.SHADOW_RELIQUARY_CODEX_PREFAB or "waxwelljournal"
local CODEX_BUSY_TAG = V.SHADOW_RELIQUARY_CODEX_BUSY_TAG or "waxwell_reliquary_codex_busy"
local CODEX_RIFT_BUSY_TAG = V.SHADOW_RELIQUARY_CODEX_RIFT_BUSY_TAG or "waxwell_reliquary_codex_rift_busy"
local REPAIR_RATE = V.SHADOW_RELIQUARY_CODEX_REPAIR_RATE or .05

-- =============================================================================
-- Private helpers
-- =============================================================================

local function IsCodex(journal)
    return journal ~= nil and journal:IsValid() and journal.prefab == CODEX_PREFAB
end

local function IsCodexOnGround(journal)
    if journal == nil or not journal:IsValid() or journal:IsInLimbo() then
        return false
    end
    local inv = journal.components ~= nil and journal.components.inventoryitem or nil
    return inv == nil or not inv:IsHeld()
end

local function IsCodexRiftTransfer(journal)
    return journal ~= nil
        and journal:IsValid()
        and (journal._umbral_rift_transferring or journal:HasTag(CODEX_RIFT_BUSY_TAG))
end

local function GetCodexOwnerUserid(journal)
    return journal ~= nil and journal._reliquary_owner_userid or nil
end

local function SetCodexOwnerUserid(journal, userid)
    if journal ~= nil and userid ~= nil then
        journal._reliquary_owner_userid = userid
    end
end

local function CancelCodexSuckTask(journal)
    if journal ~= nil and journal._reliquary_suck_task ~= nil then
        journal._reliquary_suck_task:Cancel()
        journal._reliquary_suck_task = nil
    end
end

local function CancelRiftTasksOnCodex(journal)
    if journal == nil then
        return
    end
    if journal._umbral_rift_static_emerge_task ~= nil then
        journal._umbral_rift_static_emerge_task:Cancel()
        journal._umbral_rift_static_emerge_task = nil
    end
    if journal._umbral_rift_transfer_task ~= nil then
        journal._umbral_rift_transfer_task:Cancel()
        journal._umbral_rift_transfer_task = nil
    end
end

local function CancelFloatTask(journal)
    if journal ~= nil and journal._floattask ~= nil then
        journal._floattask:Cancel()
        journal._floattask = nil
    end
end

local function StopRepairTask(journal)
    if journal ~= nil and journal._reliquary_repair_task ~= nil then
        journal._reliquary_repair_task:Cancel()
        journal._reliquary_repair_task = nil
    end
end

local function StopDockRaiseTask(journal)
    if journal ~= nil and journal._reliquary_dock_raise_task ~= nil then
        journal._reliquary_dock_raise_task:Cancel()
        journal._reliquary_dock_raise_task = nil
    end
end

local function StopDockHoldTask(journal)
    if journal ~= nil and journal._reliquary_dock_hold_task ~= nil then
        journal._reliquary_dock_hold_task:Cancel()
        journal._reliquary_dock_hold_task = nil
    end
end

local function SuspendCodexPhysics(journal)
    if journal == nil or not journal:IsValid() or journal.Physics == nil then
        return
    end
    if journal._reliquary_physics_saved == nil then
        journal._reliquary_physics_saved = journal.Physics:IsActive()
        journal.Physics:SetActive(false)
    end
end

local function ReleaseCodexPhysics(journal)
    if journal == nil or not journal:IsValid() or journal.Physics == nil then
        return
    end
    if journal._reliquary_physics_saved ~= nil then
        journal.Physics:SetActive(journal._reliquary_physics_saved)
        journal._reliquary_physics_saved = nil
    end
end

local function ApplyCodexDockSortOffset(journal, y)
    if journal == nil or not journal:IsValid() or journal.AnimState == nil then
        return
    end

    if y ~= nil and y > 0 then
        -- Lifted world Y would draw in front of the winch; offset sort depth to match ground.
        journal.AnimState:SetSortWorldOffset(0, -y, 0)
    else
        journal.AnimState:SetSortWorldOffset(0, 0, 0)
    end
end

local function SetCodexDockHeight(journal, y)
    if journal == nil or not journal:IsValid() then
        return
    end

    y = y or 0

    local x, _, z = journal.Transform:GetWorldPosition()
    if journal._reliquary_physics_saved ~= nil then
        journal.Transform:SetPosition(x, y, z)
    elseif journal.Physics ~= nil then
        journal.Physics:Stop()
        journal.Physics:Teleport(x, y, z)
    else
        journal.Transform:SetPosition(x, y, z)
    end

    ApplyCodexDockSortOffset(journal, y)
end

local function ApplyCodexDockHeight(journal)
    SetCodexDockHeight(journal, V.SHADOW_RELIQUARY_CODEX_DOCK_Y_OFFSET or .25)
end

local function StartDockHoldTask(journal)
    StopDockHoldTask(journal)
    if journal == nil or not journal:IsValid() then
        return
    end

    SuspendCodexPhysics(journal)
    if journal.AnimState ~= nil then
        journal.AnimState:SetFloatParams(0, 0, 0)
    end
    ApplyCodexDockHeight(journal)

    journal._reliquary_dock_hold_task = journal:DoPeriodicTask(FRAMES, function(item)
        if item == nil or not item:IsValid() or not item._reliquary_docked then
            StopDockHoldTask(item)
            return
        end

        CancelFloatTask(item)
        ApplyCodexDockHeight(item)
    end)
end

local function StartDockRaiseTask(journal)
    StopDockRaiseTask(journal)
    StopDockHoldTask(journal)
    if journal == nil or not journal:IsValid() then
        return
    end

    local target_y = V.SHADOW_RELIQUARY_CODEX_DOCK_Y_OFFSET or .25
    if target_y <= 0 then
        StartDockHoldTask(journal)
        return
    end

    SuspendCodexPhysics(journal)
    if journal.AnimState ~= nil then
        journal.AnimState:SetFloatParams(0, 0, 0)
    end

    local _, start_y, _ = journal.Transform:GetWorldPosition()
    local start_time = GetTime()
    local duration = V.SHADOW_RELIQUARY_CODEX_DOCK_RAISE_TIME or .35

    journal._reliquary_dock_raise_task = journal:DoPeriodicTask(FRAMES, function(item)
        if item == nil or not item:IsValid() or not item._reliquary_docked then
            StopDockRaiseTask(item)
            return
        end

        CancelFloatTask(item)

        local t = math.clamp((GetTime() - start_time) / duration, 0, 1)
        local x, _, z = item.Transform:GetWorldPosition()
        SetCodexDockHeight(item, start_y + (target_y - start_y) * t)

        if t >= 1 then
            StopDockRaiseTask(item)
            StartDockHoldTask(item)
        end
    end)
end

local function ClearCodexDockHeight(journal)
    if journal == nil or not journal:IsValid() then
        return
    end

    SetCodexDockHeight(journal, 0)
end

local function EnsureCodexFlingReady(journal)
    if journal == nil or not journal:IsValid() then
        return
    end

    StopDockRaiseTask(journal)
    StopDockHoldTask(journal)
    ReleaseCodexPhysics(journal)

    if journal.AnimState ~= nil then
        journal.AnimState:SetSortWorldOffset(0, 0, 0)
    end

    if journal.Physics ~= nil then
        journal.Physics:SetActive(true)
        journal.Physics:Stop()
    end
end

local function PlayProximityOpen(journal)
    if journal == nil or journal.AnimState == nil then
        return
    end
    if journal.AnimState:IsCurrentAnimation("proximity_loop") then
        local t = journal.AnimState:GetCurrentAnimationTime()
        journal.AnimState:PlayAnimation("proximity_loop", true)
        journal.AnimState:SetTime(t)
    else
        journal.AnimState:PlayAnimation("proximity_pre")
        journal.AnimState:PushAnimation("proximity_loop", true)
    end
    if journal.SoundEmitter ~= nil and not journal.SoundEmitter:PlayingSound("idlesound") then
        journal.SoundEmitter:PlaySound("dontstarve/common/together/book_maxwell/active_LP", "idlesound")
        journal.SoundEmitter:SetVolume("idlesound", .5)
    end
end

local function PlayProximityClose(journal, instant)
    if journal == nil or journal.AnimState == nil then
        return
    end
    if instant then
        journal.AnimState:PlayAnimation("idle")
        if journal.SoundEmitter ~= nil then
            journal.SoundEmitter:KillSound("idlesound")
        end
        journal.isfloating = nil
    else
        journal.AnimState:PlayAnimation("proximity_pst")
        journal.AnimState:PushAnimation("idle", false)
        if journal.SoundEmitter ~= nil then
            journal.SoundEmitter:KillSound("idlesound")
        end
        journal.isfloating = nil
    end
end

-- =============================================================================
-- Public API
-- =============================================================================

local function IsEligibleCodex(base, journal)
    if base == nil or not base:IsValid() or base._deactivating then
        return false
    end
    if not IsCodex(journal) or not IsCodexOnGround(journal) then
        return false
    end
    if journal._reliquary_docked or journal:HasTag(CODEX_BUSY_TAG) or IsCodexRiftTransfer(journal) then
        return false
    end
    local fueled = journal.components ~= nil and journal.components.fueled or nil
    if fueled == nil then
        return false
    end
    if fueled:GetPercent() >= 1 then
        return false
    end
    return true
end

local function MarkCodexUnlocking(journal)
    if not IsCodex(journal) then
        return
    end
    journal._unlocking = true
    journal:AddTag(CODEX_BUSY_TAG)
    if journal.components ~= nil and journal.components.inventoryitem ~= nil then
        journal.components.inventoryitem.canbepickedup = false
    end
end

local function ClearCodexUnlocking(journal)
    if not IsCodex(journal) then
        return
    end
    journal._unlocking = false
    journal:RemoveTag(CODEX_BUSY_TAG)
    if journal.components ~= nil and journal.components.inventoryitem ~= nil then
        journal.components.inventoryitem.canbepickedup = true
    end
end

local function DockCodexVisual(journal)
    if not IsCodex(journal) then
        return
    end
    CancelFloatTask(journal)
    if journal._activetask ~= nil then
        journal._activetask:Cancel()
        journal._activetask = nil
    end
    journal._reliquary_docked = true
    journal.isfloating = true
    if journal.AnimState ~= nil then
        journal.AnimState:SetFinalOffset(V.SHADOW_RELIQUARY_STACKED_FINAL_OFFSET or 1)
    end
    MarkCodexUnlocking(journal)
    PlayProximityOpen(journal)
    StartDockRaiseTask(journal)
end

local function UndockCodexVisual(journal, instant)
    if not IsCodex(journal) then
        return
    end
    StopRepairTask(journal)
    StopDockRaiseTask(journal)
    StopDockHoldTask(journal)
    journal._reliquary_docked = nil
    if journal.AnimState ~= nil then
        journal.AnimState:SetFinalOffset(0)
    end
    ClearCodexUnlocking(journal)
    ClearCodexDockHeight(journal)
    ReleaseCodexPhysics(journal)
    PlayProximityClose(journal, instant == true)
end

local function StartRepairTask(base, journal, oncomplete)
    StopRepairTask(journal)
    if not IsCodex(journal) then
        return
    end

    journal._reliquary_repair_task = journal:DoPeriodicTask(1, function(item)
        if item == nil or not item:IsValid() or base == nil or not base:IsValid() then
            StopRepairTask(item)
            return
        end
        if base._deactivating then
            StopRepairTask(item)
            if oncomplete ~= nil then
                oncomplete(false)
            end
            return
        end

        local fueled = item.components ~= nil and item.components.fueled or nil
        if fueled == nil then
            StopRepairTask(item)
            if oncomplete ~= nil then
                oncomplete(false)
            end
            return
        end

        if fueled:GetPercent() < 1 then
            local maxfuel = fueled.maxfuel or 1
            fueled:DoDelta(REPAIR_RATE * maxfuel)
        end

        if fueled:GetPercent() >= 1 then
            StopRepairTask(item)
            if oncomplete ~= nil then
                oncomplete(true)
            end
        end
    end)
end

local function BeginCodexRepair(base, journal, oncomplete)
    DockCodexVisual(journal)
    StartRepairTask(base, journal, oncomplete)
end

local function AbortShadowReliquaryUnlockForCodex(journal)
    if not IsCodex(journal) then
        return
    end

    CancelCodexSuckTask(journal)
    if journal._reliquary_docked or journal._unlocking or journal:HasTag(CODEX_BUSY_TAG) then
        UndockCodexVisual(journal, true)
    else
        ClearCodexUnlocking(journal)
    end

    local x, _, z = journal.Transform:GetWorldPosition()
    local search = math.max((V.SHADOW_RELIQUARY_SUCK_RADIUS or 3) * 4, 16)
    for _, base in ipairs(TheSim:FindEntities(x, 0, z, search, { "waxwell_shadow_reliquary_base" })) do
        if base ~= nil
            and base:IsValid()
            and base._unlocking
            and base._docked_codex == journal then
            base._unlocking = false
            base._docked_codex = nil
            if base.AnimState ~= nil then
                base.AnimState:PlayAnimation("idle", true)
            end
            if base.SoundEmitter ~= nil then
                base.SoundEmitter:KillAllSounds()
            end
        end
    end
end

local function SetShadowReliquaryCodexRiftTransfer(journal, transferring)
    if not IsCodex(journal) then
        return
    end

    if transferring then
        AbortShadowReliquaryUnlockForCodex(journal)
        journal._umbral_rift_transferring = true
        journal:AddTag(CODEX_RIFT_BUSY_TAG)
    else
        journal._umbral_rift_transferring = nil
        journal:RemoveTag(CODEX_RIFT_BUSY_TAG)
    end
end

local function IsShadowReliquaryCodexRiftTransfer(journal)
    return IsCodexRiftTransfer(journal)
end

local function TryAbsorbShadowReliquaryCodex(journal, x, z, radius_override)
    if TheWorld == nil or not TheWorld.ismastersim then
        return false
    end
    if not IsCodex(journal) or journal._unlocking or IsCodexRiftTransfer(journal) then
        return false
    end
    if not IsCodexOnGround(journal) then
        return false
    end

    local radius = radius_override or V.SHADOW_RELIQUARY_SUCK_RADIUS
    local bases = TheSim:FindEntities(x, 0, z, radius, { "waxwell_shadow_reliquary_base" })
    local best_base
    local best_dist_sq
    for _, base in ipairs(bases) do
        if base ~= nil
            and base:IsValid()
            and not base._deactivating
            and not base._unlocking
            and base.TryRechargeCodex ~= nil then
            local bx, _, bz = base.Transform:GetWorldPosition()
            local dx, dz = bx - x, bz - z
            local dist_sq = dx * dx + dz * dz
            if best_dist_sq == nil or dist_sq < best_dist_sq then
                best_dist_sq = dist_sq
                best_base = base
            end
        end
    end
    if best_base ~= nil then
        best_base:TryRechargeCodex(journal)
        return true
    end

    return false
end

-- =============================================================================
-- Journal hooks
-- =============================================================================

local function TryAbsorbAfterDrop(inst)
    if inst == nil or not inst:IsValid() or inst._unlocking or inst._reliquary_docked then
        return
    end
    local inv = inst.components.inventoryitem
    if inv ~= nil and inv:IsHeld() then
        return
    end
    local x, _, z = inst.Transform:GetWorldPosition()
    local radius = (V.SHADOW_RELIQUARY_SUCK_RADIUS or 3) + (V.SHADOW_RELIQUARY_DROP_ABSORB_PAD or 1)
    TryAbsorbShadowReliquaryCodex(inst, x, z, radius)
end

local function OnJournalDropped(inst)
    TryAbsorbAfterDrop(inst)
    inst:DoTaskInTime(.35, TryAbsorbAfterDrop)
end

local function OnJournalPutInInventory(inst, data)
    if data ~= nil and data.owner ~= nil and data.owner.userid ~= nil then
        SetCodexOwnerUserid(inst, data.owner.userid)
    end
end

local function RegisterJournalHooks(env)
    if env == nil or env.AddPrefabPostInit == nil then
        return
    end

    env.AddPrefabPostInit(CODEX_PREFAB, function(inst)
        if not TheWorld.ismastersim or inst._reliquary_codex_drop_hooked then
            return
        end
        inst._reliquary_codex_drop_hooked = true

        inst:ListenForEvent("onputininventory", OnJournalPutInInventory)

        local fueled = inst.components.fueled
        if fueled ~= nil and not inst._reliquary_fuel_hooked then
            inst._reliquary_fuel_hooked = true
            local old_ontakefuelfn = fueled.ontakefuelfn
            fueled:SetTakeFuelFn(function(item, fuelvalue)
                if item ~= nil and item._reliquary_docked then
                    return
                end
                if old_ontakefuelfn ~= nil then
                    old_ontakefuelfn(item, fuelvalue)
                end
            end)
        end

        local inv = inst.components.inventoryitem
        if inv == nil then
            return
        end

        local old_ondropped = inst._reliquary_old_ondropped
        if old_ondropped == nil then
            inst._reliquary_old_ondropped = inv.ondropped
            old_ondropped = inst._reliquary_old_ondropped
        end
        inv:SetOnDroppedFn(function(item)
            if old_ondropped ~= nil then
                old_ondropped(item)
            end
            OnJournalDropped(item)
        end)
    end)
end

return {
    IsCodex = IsCodex,
    IsEligibleCodex = IsEligibleCodex,
    IsShadowReliquaryCodexRiftTransfer = IsShadowReliquaryCodexRiftTransfer,
    SetShadowReliquaryCodexRiftTransfer = SetShadowReliquaryCodexRiftTransfer,
    AbortShadowReliquaryUnlockForCodex = AbortShadowReliquaryUnlockForCodex,
    MarkCodexUnlocking = MarkCodexUnlocking,
    ClearCodexUnlocking = ClearCodexUnlocking,
    DockCodexVisual = DockCodexVisual,
    UndockCodexVisual = UndockCodexVisual,
    BeginCodexRepair = BeginCodexRepair,
    StartRepairTask = StartRepairTask,
    StopRepairTask = StopRepairTask,
    EnsureCodexFlingReady = EnsureCodexFlingReady,
    CancelCodexSuckTask = CancelCodexSuckTask,
    CancelRiftTasksOnCodex = CancelRiftTasksOnCodex,
    TryAbsorbShadowReliquaryCodex = TryAbsorbShadowReliquaryCodex,
    RegisterJournalHooks = RegisterJournalHooks,
}
