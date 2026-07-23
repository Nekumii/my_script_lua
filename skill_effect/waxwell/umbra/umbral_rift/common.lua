local spell_utils = require("skill_effect/waxwell/_shared/codex_spell_utils")
local cast_costs = require("skill_effect/waxwell/_shared/codex_cast_costs")
local cost_gate = require("skill_effect/waxwell/_shared/codex_cost_gate")
local ReticuleUtils = require("reticule/utils")
local shared = require("skill_effect/waxwell/umbra/_shared/cast_common")
local V = require("skill_effect/waxwell/umbra/umbral_rift/variables")

local UMBRAL_RIFT_PLACEMENT_RADIUS = ReticuleUtils.GetWorkRadius(V.UMBRAL_RIFT_RETICULE_SCALE, "s") or V.UMBRAL_RIFT_CLEAR_RADIUS
local UMBRAL_RIFT_PLACEMENT_AREA_SAMPLES = 12

local SpellCost = shared.SpellCost
local HasEnoughCodexFuel = shared.HasEnoughCodexFuel
local NotBlocked = shared.NotBlocked
local IsPassableGroundPoint = shared.IsPassableGroundPoint
local IsSpellOnCooldown = shared.IsSpellOnCooldown
local GetSpellCooldownPercent = shared.GetSpellCooldownPercent
local RestartSpellCooldown = shared.RestartSpellCooldown
local StartAOETargeting = shared.StartAOETargeting

local UMBRAL_RIFT_MARK_TAG = "waxwell_umbral_rift_mark"          -- อยู่บน mark entity (replicate ให้ client)
local UMBRAL_RIFT_MARK_ACTIVE_TAG = "waxwell_umbral_rift_mark_active" -- อยู่บน player (สัญญาณ phase MARK_ACTIVE)

-- namespace/name ของ mod RPC (client → server) ต้องตรงกันทั้ง hook.lua และ client_hooks.lua
local UMBRAL_RIFT_RPC =
{
    NAMESPACE = "waxwell_skilltree",
    PLACE_MARK = "umbral_rift_place_mark",
    BEGIN_WARP = "umbral_rift_begin_warp",
    CANCEL = "umbral_rift_cancel",
}

local IsUmbralRiftBook

local function SendUmbralRiftModRPC(name, ...)
    local mod_rpc = rawget(_G, "MOD_RPC")
    local id = mod_rpc ~= nil
        and mod_rpc[UMBRAL_RIFT_RPC.NAMESPACE] ~= nil
        and mod_rpc[UMBRAL_RIFT_RPC.NAMESPACE][name]
        or nil
    if id ~= nil then
        SendModRPCToServer(id, ...)
    end
end

-- =============================================================================
-- Private fields (per-doer state helpers)
-- =============================================================================

local function GetUmbralRiftMarkPos(doer)
    return doer ~= nil and doer._waxwell_umbral_rift_mark_pos or nil
end

-- ชื่อเดิม — โค้ด portal/validation ที่มีอยู่เรียกใช้อยู่ ให้ map ไปที่ mark pos
local function GetUmbralRiftPendingSource(doer)
    return GetUmbralRiftMarkPos(doer)
end

-- มี mark จุด 1 อยู่หรือไม่ (server: ref จริง / client: tag ที่ replicate มา)
local function HasUmbralRiftMark(doer)
    if doer == nil or not doer:IsValid() then
        return false
    end
    if doer._waxwell_umbral_rift_mark_pos ~= nil then
        return true
    end
    return doer:HasTag(UMBRAL_RIFT_MARK_ACTIVE_TAG)
end

-- ยังเปิดสกิลอยู่ (มี mark รอจุด 2) — ใช้ตอนสลับ spell / interrupt
local function IsUmbralRiftPendingActive(doer)
    return HasUmbralRiftMark(doer)
end

local function GetUmbralRiftCastBook(doer, pc)
    if doer == nil then
        return nil
    end

    local book = nil
    if doer.replica ~= nil and doer.replica.inventory ~= nil then
        book = doer.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
            or doer.replica.inventory:GetActiveItem()
    end
    if book == nil and doer.components ~= nil and doer.components.inventory ~= nil then
        book = doer.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
            or doer.components.inventory:GetActiveItem()
    end
    if book == nil and pc ~= nil and pc:IsAOETargeting() and pc.reticule ~= nil then
        book = pc.reticule.inst
    end
    if IsUmbralRiftBook(book) then
        return book
    end
    return nil
end

-- =============================================================================
-- Private main logic (mark lifecycle — server authority)
-- =============================================================================

local function StopUmbralRiftMarkTimers(doer)
    if doer == nil then
        return
    end

    if doer._waxwell_umbral_rift_mark_lifetime_task ~= nil then
        doer._waxwell_umbral_rift_mark_lifetime_task:Cancel()
        doer._waxwell_umbral_rift_mark_lifetime_task = nil
    end

    if doer._waxwell_umbral_rift_casting_stuck_task ~= nil then
        doer._waxwell_umbral_rift_casting_stuck_task:Cancel()
        doer._waxwell_umbral_rift_casting_stuck_task = nil
    end

    if doer._waxwell_umbral_rift_warp_reserve_task ~= nil then
        doer._waxwell_umbral_rift_warp_reserve_task:Cancel()
        doer._waxwell_umbral_rift_warp_reserve_task = nil
    end
end

local function RemoveUmbralRiftMark(doer, force)
    if doer == nil then
        return
    end

    if not force and (doer._waxwell_umbral_rift_casting or doer._waxwell_umbral_rift_warp_reserved) then
        return
    end

    StopUmbralRiftMarkTimers(doer)
    doer._waxwell_umbral_rift_casting = nil
    doer._waxwell_umbral_rift_warp_reserved = nil
    doer._waxwell_umbral_rift_mark_lifetime_expired = nil

    local pos = doer._waxwell_umbral_rift_mark_pos
    local ent = doer._waxwell_umbral_rift_mark_ent
    doer._waxwell_umbral_rift_mark_ent = nil
    doer._waxwell_umbral_rift_mark_pos = nil

    if ent ~= nil and ent:IsValid() then
        if ent.KillFX ~= nil then
            ent:KillFX()
        else
            ent:Remove()
        end
    elseif pos ~= nil then
        -- ref หลุด: fallback ค้นเฉพาะรัศมีแคบรอบ mark เดิม
        for _, e in ipairs(TheSim:FindEntities(pos.x, 0, pos.z, 3, { UMBRAL_RIFT_MARK_TAG })) do
            if e ~= nil and e:IsValid() then
                if e.KillFX ~= nil then
                    e:KillFX()
                else
                    e:Remove()
                end
            end
        end
    end

    if doer:IsValid() then
        doer:RemoveTag(UMBRAL_RIFT_MARK_ACTIVE_TAG)
    end
end

-- หลังวาง mark นับ delay แล้ว fade (ยกเว้นตอนกำลังร่ายจุด 2)
local function StartUmbralRiftMarkLifetime(doer)
    if doer == nil or not doer:IsValid() then
        return
    end

    StopUmbralRiftMarkTimers(doer)
    doer._waxwell_umbral_rift_mark_lifetime_expired = nil

    doer._waxwell_umbral_rift_mark_lifetime_task = doer:DoTaskInTime(V.UMBRAL_RIFT_MARK_LIFETIME, function(player)
        player._waxwell_umbral_rift_mark_lifetime_task = nil
        if not HasUmbralRiftMark(player) then
            return
        end

        if player._waxwell_umbral_rift_casting or player._waxwell_umbral_rift_warp_reserved then
            player._waxwell_umbral_rift_mark_lifetime_expired = true
            return
        end

        RemoveUmbralRiftMark(player, true)
    end)
end

-- จุด 2: กัน mark ถูกลบก่อน CASTAOE ถึง server (ไม่ตั้ง _casting — ตั้งใน spell fn)
local function ReserveUmbralRiftWarpCast(doer)
    if doer == nil or not doer:IsValid() then
        return
    end

    StopUmbralRiftMarkTimers(doer)
    doer._waxwell_umbral_rift_warp_reserved = true

    if doer._waxwell_umbral_rift_warp_reserve_task ~= nil then
        doer._waxwell_umbral_rift_warp_reserve_task:Cancel()
        doer._waxwell_umbral_rift_warp_reserve_task = nil
    end

    doer._waxwell_umbral_rift_warp_reserve_task = doer:DoTaskInTime(3, function(player)
        player._waxwell_umbral_rift_warp_reserve_task = nil
        if not player:IsValid() or not player._waxwell_umbral_rift_warp_reserved then
            return
        end
        if player._waxwell_umbral_rift_casting then
            return
        end
        player._waxwell_umbral_rift_warp_reserved = nil
        if player._waxwell_umbral_rift_mark_lifetime_expired and HasUmbralRiftMark(player) then
            RemoveUmbralRiftMark(player, true)
            if player == ThePlayer then
                ResetUmbralRiftJournalState(player)
            end
        end
    end)
end

local function BeginUmbralRiftWarpCast(doer)
    if doer == nil or not doer:IsValid() then
        return
    end

    if doer._waxwell_umbral_rift_warp_reserve_task ~= nil then
        doer._waxwell_umbral_rift_warp_reserve_task:Cancel()
        doer._waxwell_umbral_rift_warp_reserve_task = nil
    end

    doer._waxwell_umbral_rift_warp_reserved = nil
    doer._waxwell_umbral_rift_casting = true
    StopUmbralRiftMarkTimers(doer)
end

-- ล้าง override บน journal (range, deploy, hooks) — เรียกเมื่อ UR จบ session
local function ResetUmbralRiftJournalState(doer, book)
    book = book or ReticuleUtils.GetWaxwellJournalFromDoer(doer)
    if book == nil or not book:IsValid() then
        return
    end

    local aoetargeting = book.components ~= nil and book.components.aoetargeting or nil
    if aoetargeting ~= nil then
        if aoetargeting.SetAlwaysValid ~= nil then
            aoetargeting:SetAlwaysValid(false)
        end
        if aoetargeting.SetAllowWater ~= nil then
            aoetargeting:SetAllowWater(false)
        end
    end

    ReticuleUtils.ResetVanillaJournalCastRange(book)
end

local function FinishUmbralRiftWarpCast(doer, opts)
    if doer == nil or not doer:IsValid() then
        return
    end

    opts = opts or {}

    local function ApplyFinish(player)
        if not player:IsValid() then
            return
        end

        if player._waxwell_umbral_rift_casting_stuck_task ~= nil then
            player._waxwell_umbral_rift_casting_stuck_task:Cancel()
            player._waxwell_umbral_rift_casting_stuck_task = nil
        end

        if player._waxwell_umbral_rift_warp_reserve_task ~= nil then
            player._waxwell_umbral_rift_warp_reserve_task:Cancel()
            player._waxwell_umbral_rift_warp_reserve_task = nil
        end

        player._waxwell_umbral_rift_warp_reserved = nil
        player._waxwell_umbral_rift_casting = nil

        if opts.success then
            RemoveUmbralRiftMark(player, true)
            if player == ThePlayer then
                ResetUmbralRiftJournalState(player)
            end
            return
        end

        if opts.keep_mark and HasUmbralRiftMark(player) then
            if player._waxwell_umbral_rift_mark_lifetime_expired then
                player._waxwell_umbral_rift_mark_lifetime_expired = nil
                RemoveUmbralRiftMark(player, true)
                if player == ThePlayer then
                    ResetUmbralRiftJournalState(player)
                end
            else
                StartUmbralRiftMarkLifetime(player)
            end
            return
        end

        RemoveUmbralRiftMark(player, true)
        if player == ThePlayer then
            ResetUmbralRiftJournalState(player)
        end
    end

    if opts.success then
        doer:DoTaskInTime(V.UMBRAL_RIFT_WARP_CAST_ANIM_TIME, ApplyFinish)
    else
        ApplyFinish(doer)
    end
end

-- ลบ mark อย่างเดียว (reticule ยังเปิด) — ใช้ภายใน / interrupt เบื้องต้น
local function ClearUmbralRiftPendingState(doer)
    RemoveUmbralRiftMark(doer, true)
end

-- opts.keep_mark — เก็บ mark ไว้ (cast fail ที่ยังเลือกจุด 2 ต่อได้)
-- opts.keep_journal_state — เก็บ reticule override ไว้ (คู่กับ keep_mark)
-- opts.skip_reticule_close — ไม่เรียก CancelAOETargeting (ใช้จาก hook หลังปิด reticule แล้ว)
-- opts.skip_mark_rpc — ไม่ส่ง RPC ลบ mark (server ลบแล้ว)
-- opts.book — journal ที่จะ reset (default หาเอง)
local function CleanupUmbralRiftSkill(doer, opts)
    if doer == nil then
        return
    end

    opts = opts or {}

    if not opts.keep_mark then
        doer._waxwell_umbral_rift_casting = nil
        doer._waxwell_umbral_rift_warp_reserved = nil
        doer._waxwell_umbral_rift_mark_lifetime_expired = nil
        StopUmbralRiftMarkTimers(doer)
    end

    if not opts.keep_mark then
        if TheWorld.ismastersim then
            RemoveUmbralRiftMark(doer, true)
        elseif doer == ThePlayer and not opts.skip_mark_rpc then
            SendUmbralRiftModRPC(UMBRAL_RIFT_RPC.CANCEL)
        end
    end

    if doer == ThePlayer and not opts.keep_journal_state then
        ResetUmbralRiftJournalState(doer, opts.book)

        if not opts.skip_reticule_close then
            local pc = doer.components ~= nil and doer.components.playercontroller or nil
            if pc ~= nil and pc:IsAOETargeting() then
                pc:CancelAOETargeting()
            end
        end
    end
end

-- ยกเลิกทั้งสกิล: ลบ mark (server/RPC) + ล้าง journal state + ปิด reticule
local function CancelUmbralRiftSkill(doer)
    CleanupUmbralRiftSkill(doer)
end

local function IsUmbralRift1Active(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_umbral_rift_1"))
            or inst:HasTag("umbral_rift_1_active")
        )
end

local function IsUmbralRift2Active(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_umbral_rift_2"))
            or inst:HasTag("umbral_rift_2_active")
        )
end

local function IsUmbralRiftSkillActive(inst)
    return IsUmbralRift1Active(inst) or IsUmbralRift2Active(inst)
end
local function HasUmbralRiftPlacementClearance(pt)
    if pt == nil then
        return false
    end

    local ents = TheSim:FindEntities(pt.x, 0, pt.z, V.UMBRAL_RIFT_CLEAR_RADIUS, nil, V.UMBRAL_RIFT_PLACEMENT_CANT_TAGS)
    for _, ent in ipairs(ents) do
        if ent ~= nil
            and ent:IsValid()
            and ent.entity ~= nil
            and ent.entity:IsVisible()
            and not ent:HasTag("waxwell_shadow_reliquary_base")
            and (ent:HasTag("tree") or ent:HasTag("boulder") or ent:HasTag("structure") or ent:HasTag("wall") or ent:HasTag("campfire") or ent:HasTag("pickable")) then
            return false
        end
    end

    return true
end

local function ResolveUmbralRiftPoint(pos)
    if pos == nil then
        return nil
    end

    local x, _, z = pos.x, pos.y, pos.z
    if x == nil and pos.Get ~= nil then
        x, _, z = pos:Get()
    end
    if x == nil or z == nil then
        return nil
    end

    return Vector3(x, 0, z)
end

local function GetUmbralRiftCastOriginXZ(doer)
    if doer ~= nil and doer:IsValid() and doer.Transform ~= nil then
        local x, _, z = doer.Transform:GetWorldPosition()
        return x, z
    end

    local player = ThePlayer
    if player ~= nil and player:IsValid() and player.Transform ~= nil then
        local x, _, z = player.Transform:GetWorldPosition()
        return x, z
    end

    return nil, nil
end

local function IsUmbralRiftWithinCastRange(doer, pt)
    pt = ResolveUmbralRiftPoint(pt)
    if pt == nil then
        return false
    end

    local origin_x, origin_z = GetUmbralRiftCastOriginXZ(doer)
    if origin_x == nil or origin_z == nil then
        return false
    end

    return ReticuleUtils.IsPointWithinCastRange(origin_x, origin_z, pt, V.UMBRAL_RIFT_CAST_RANGE)
end

local function GetUmbralRiftForbiddenCenter(doer)
    if doer == nil then
        return nil
    end

    -- server: ตำแหน่ง mark ที่เก็บไว้
    local pending = GetUmbralRiftMarkPos(doer)
    if pending ~= nil then
        return pending
    end

    if not doer:IsValid() then
        return nil
    end

    -- server/client: ใช้ mark entity โดยตรงถ้ามี ref
    local ent = doer._waxwell_umbral_rift_mark_ent
    if ent ~= nil and ent:IsValid() then
        local x, _, z = ent.Transform:GetWorldPosition()
        return Vector3(x, 0, z)
    end

    -- client: mark เป็น networked entity ที่ replicate มา หาได้ด้วย tag
    if doer:HasTag(UMBRAL_RIFT_MARK_ACTIVE_TAG) then
        local px, _, pz = doer.Transform:GetWorldPosition()
        local ents = TheSim:FindEntities(px, 0, pz, V.UMBRAL_RIFT_CAST_RANGE + 8, { UMBRAL_RIFT_MARK_TAG })
        if ents[1] ~= nil and ents[1]:IsValid() then
            local ex, _, ez = ents[1].Transform:GetWorldPosition()
            return Vector3(ex, 0, ez)
        end
    end

    return nil
end

local function DoesUmbralRiftOverlapForbiddenZone(pt, forbidden_center)
    if pt == nil or forbidden_center == nil then
        return false
    end

    local radius = UMBRAL_RIFT_PLACEMENT_RADIUS
    local dx = pt.x - forbidden_center.x
    local dz = pt.z - forbidden_center.z
    local min_center_dist = radius * 2
    return dx * dx + dz * dz < min_center_dist * min_center_dist
end

local function DoesUmbralRiftOverlapActivePortals(pt, doer)
    if pt == nil then
        return false
    end

    local search_x, search_z = pt.x, pt.z
    if doer ~= nil and doer:IsValid() then
        local doer_x, doer_y, doer_z = doer.Transform:GetWorldPosition()
        search_x, search_z = doer_x, doer_z
    end

    local search_radius = V.UMBRAL_RIFT_CAST_RANGE + UMBRAL_RIFT_PLACEMENT_RADIUS * 2
    local portals = TheSim:FindEntities(search_x, 0, search_z, search_radius, { "umbral_rift_portal" })
    for _, portal in ipairs(portals) do
        if portal ~= nil and portal:IsValid() then
            local x, _, z = portal.Transform:GetWorldPosition()
            if DoesUmbralRiftOverlapForbiddenZone(pt, Vector3(x, 0, z)) then
                return true
            end
        end
    end

    local ents = TheSim:FindEntities(search_x, 0, search_z, search_radius, nil, { "INLIMBO" })
    for _, ent in ipairs(ents) do
        if ent ~= nil
            and ent:IsValid()
            and ent.prefab == "umbral_rift_portal"
            and not ent:HasTag("umbral_rift_portal") then
            local x, _, z = ent.Transform:GetWorldPosition()
            if DoesUmbralRiftOverlapForbiddenZone(pt, Vector3(x, 0, z)) then
                return true
            end
        end
    end

    return false
end

local function IsUmbralRiftPlacementAreaValid(pt, doer, check_cast_range)
    if pt == nil then
        return false
    end

    if check_cast_range ~= false and not IsUmbralRiftWithinCastRange(doer, pt) then
        return false
    end

    if not IsPassableGroundPoint(pt) or not HasUmbralRiftPlacementClearance(pt) then
        return false
    end

    local forbidden = doer ~= nil and GetUmbralRiftForbiddenCenter(doer) or nil
    if forbidden ~= nil and DoesUmbralRiftOverlapForbiddenZone(pt, forbidden) then
        return false
    end

    if DoesUmbralRiftOverlapActivePortals(pt, doer) then
        return false
    end

    local radius = UMBRAL_RIFT_PLACEMENT_RADIUS
    for i = 0, UMBRAL_RIFT_PLACEMENT_AREA_SAMPLES - 1 do
        local theta = i * TWOPI / UMBRAL_RIFT_PLACEMENT_AREA_SAMPLES
        local sample = Vector3(pt.x + math.cos(theta) * radius, 0, pt.z + math.sin(theta) * radius)
        if not IsPassableGroundPoint(sample) then
            return false
        end
    end

    return true
end

local function ResolveUmbralRiftTargetPoint(pos, doer)
    local pt = ResolveUmbralRiftPoint(pos)
    if pt == nil then
        return nil
    end

    if IsUmbralRiftPlacementAreaValid(pt, doer) then
        return pt
    end

    return nil
end

local function UmbralRiftReticuleValidFn(inst, reticule, pos)
    local pt = ResolveUmbralRiftPoint(pos)
    if pt == nil then
        return false
    end

    local doer = ThePlayer
    local check_cast_range = ReticuleUtils.IsReticuleRangeLockEnabled()
    return IsUmbralRiftPlacementAreaValid(pt, doer, check_cast_range)
end

local function IsFriendlyOrSummonedTarget(ent)
    if ent == nil then
        return true
    end

    if ent:HasTag("player")
        or ent:HasTag("companion")
        or ent:HasTag("playerpet")
        or ent:HasTag("shadowminion")
        or ent:HasTag("stalkerminion")
        or ent:HasTag("chester")
        or ent:HasTag("hutch")
        or ent:HasTag("glommer")
        or ent:HasTag("abigail")
        or ent:HasTag("structure")
        or ent:HasTag("wall") then
        return true
    end

    local follower = ent.components ~= nil and ent.components.follower or nil
    local leader = follower ~= nil and follower:GetLeader() or nil
    if leader ~= nil and (leader:HasTag("player") or leader:HasTag("companion") or leader:HasTag("shadowmagic")) then
        return true
    end

    return false
end

local function FindNearbyPassablePoint(origin, radius, attempts)
    if origin == nil then
        return nil
    end

    if radius == nil or radius <= 0 then
        return IsPassableGroundPoint(origin) and Vector3(origin.x, 0, origin.z) or nil
    end

    attempts = attempts or 12
    for i = 1, attempts do
        local theta = math.random() * TWOPI
        local distance = math.sqrt(math.random()) * radius
        local candidate = Vector3(
            origin.x + math.cos(theta) * distance,
            0,
            origin.z + math.sin(theta) * distance
        )
        if IsPassableGroundPoint(candidate) and HasUmbralRiftPlacementClearance(candidate) then
            return candidate
        end
    end

    local theta = math.random() * TWOPI
    local offset = FindWalkableOffset(origin, theta, radius, 16, false, true, NotBlocked, true, true)
    if (type(offset) == "table" or type(offset) == "userdata") and offset.x ~= nil and offset.z ~= nil then
        local candidate = Vector3(origin.x + offset.x, 0, origin.z + offset.z)
        if IsPassableGroundPoint(candidate) and HasUmbralRiftPlacementClearance(candidate) then
            return candidate
        end
    end

    return nil
end

local function GetUmbralRiftDuration(inst)
    return IsUmbralRift2Active(inst) and V.UMBRAL_RIFT_UPGRADED_DURATION or V.UMBRAL_RIFT_BASE_DURATION
end

local function GetUmbralRiftCooldownTime(inst)
    return IsUmbralRift2Active(inst) and V.UMBRAL_RIFT_UPGRADED_COOLDOWN_TIME or V.UMBRAL_RIFT_BASE_COOLDOWN_TIME
end

local function GetUmbralRiftDurabilityCostPct(inst)
    return V.UMBRAL_RIFT_DURABILITY_COST_PCT + (IsUmbralRift2Active(inst) and V.UMBRAL_RIFT_LV2_EXTRA_DURABILITY_COST_PCT or 0)
end

local function GetUmbralRiftSanityCost(inst)
    -- Same path as Shadow Sneak / Prison: MED base, LV2 uses UMBRA_SKILL_2_SANITY_COST (20).
    local umbra_shared_V = require("skill_effect/waxwell/umbra/_shared/variables")
    local cost = V.UMBRAL_RIFT_SANITY_COST
    if IsUmbralRift2Active(inst) then
        cost = math.abs(umbra_shared_V.UMBRA_SKILL_2_SANITY_COST or 20)
    end
    local dark_scholar = require("skill_effect/waxwell/umbra/dark_scholar/common")
    return dark_scholar.GetDarkScholarSanityCost(cost, inst)
end

local function CanAffordUmbralRiftCast(book, doer)
    cast_costs.EnsureRegistered()
    return cast_costs.CanAffordCurrentCodexCast(book, doer)
end

local function ShouldKeepUmbralRiftMarkOnCastFail(blockreason)
    return cost_gate.IsResourceBlockReason(blockreason)
        or blockreason == "NO_TARGETS"
end

local function IsUmbralRiftOnCooldown(doer)
    return IsSpellOnCooldown(doer, V.UMBRAL_RIFT_COOLDOWN_ID)
end

local function GetUmbralRiftCooldownPercent(doer)
    return GetSpellCooldownPercent(doer, V.UMBRAL_RIFT_COOLDOWN_ID)
end

IsUmbralRiftBook = function(book)
    if book == nil then
        return false
    end

    local spellbook = book.components ~= nil and book.components.spellbook
        or book.replica ~= nil and book.replica.spellbook
        or nil
    if spellbook == nil then
        return false
    end

    local spellname = spellbook.GetSpellName ~= nil and spellbook:GetSpellName() or nil
    local expected = STRINGS.SPELLS[V.UMBRAL_RIFT_SPELL] or STRINGS.SPELLS.UMBRAL_RIFT
    return spellname == expected
end

-- ใช้จาก spell wheel guards ตอนสลับสกิล (ยกเลิก UR ถ้าไม่ใช่รายการนี้)
local function IsUmbralRiftWheelItem(item)
    if item == nil then
        return false
    end

    if item.spell_id == V.UMBRAL_RIFT_SPELL then
        return true
    end

    local expected = STRINGS.SPELLS[V.UMBRAL_RIFT_SPELL] or STRINGS.SPELLS.UMBRAL_RIFT
    return item.label == expected
end

local function GetUmbralRiftCastBlockReason(inst, doer, pos, selecting_end)
    cast_costs.EnsureRegistered()
    local resource_block = cost_gate.GetResourceBlockReason(inst, doer, cast_costs.ResolveCastCosts(inst, doer))
    if resource_block ~= nil then
        return resource_block
    elseif not IsUmbralRiftSkillActive(doer) then
        return "SKILL_INACTIVE"
    elseif not selecting_end and IsUmbralRiftOnCooldown(doer) then
        return "SPELL_ON_COOLDOWN"
    elseif ResolveUmbralRiftTargetPoint(pos, doer) == nil then
        return "NO_TARGETS"
    end

    return nil
end

local function IsUmbralRiftTransferTarget(ent)
    local inventoryitem = ent ~= nil and ent.components ~= nil and ent.components.inventoryitem or nil
    if inventoryitem ~= nil then
        return require("skill_effect/_shared/targeting_rules").IsEntityAllowed(ent,
        {
            name = "umbral_rift_transfer_item",
            blacklist_tags = V.UMBRAL_RIFT_TRANSFER_EXCLUDE_TAGS,
            extra_check = function(target)
                return target:IsValid()
                    and target.Transform ~= nil
                    and inventoryitem:GetGrandOwner() == nil
                    and not target:HasTag("waxwell_ssc_busy")
                    and not target:HasTag("waxwell_ssc_rift_busy")
                    and not target:HasTag("waxwell_reliquary_codex_busy")
                    and not target:HasTag("waxwell_reliquary_codex_rift_busy")
                    and not target._reliquary_docked
                    and not target._unlocking
                    and not target._smashing
            end,
        })
    end

    return require("skill_effect/_shared/targeting_rules").IsEntityAllowed(ent,
    {
        name = "umbral_rift_transfer",
        must_tags = V.UMBRAL_RIFT_LIVING_TARGET_MUST_TAGS,
        one_of_tags = V.UMBRAL_RIFT_LIVING_TARGET_ONEOF_TAGS,
        blacklist_prefabs = V.UMBRAL_RIFT_LIVING_TARGET_PREFAB_BLACKLIST,
        blacklist_tags = { "shadowcreature", "shadow_aligned", "epic", "largecreature", "heavy", "playerowned" },
        extra_check = function(target)
            if not target:IsValid() or target.Transform == nil then
                return false
            end

            local health = target.components ~= nil and target.components.health or nil
            return health == nil or not health:IsDead()
        end,
    })
end

local function GetUmbralRiftTransferTargets(portal, seen)
    local targets = {}
    if portal == nil or not portal:IsValid() then
        return targets
    end

    local x, y, z = portal.Transform:GetWorldPosition()
    local searchradius = V.UMBRAL_RIFT_LV2_TRANSFER_SEARCH_RADIUS
    local transferradius = V.UMBRAL_RIFT_LV2_TRANSFER_RADIUS
    for _, ent in ipairs(TheSim:FindEntities(x, y, z, searchradius, nil, V.UMBRAL_RIFT_TRANSFER_EXCLUDE_TAGS)) do
        if seen[ent] == nil and IsUmbralRiftTransferTarget(ent) then
            local ex, _, ez = ent.Transform:GetWorldPosition()
            local dx = ex - x
            local dz = ez - z
            if dx * dx + dz * dz <= transferradius * transferradius then
                seen[ent] = true
                table.insert(targets, ent)
            end
        end
    end

    return targets
end

local function MoveEntityToPoint(ent, x, z)
    if ent == nil or not ent:IsValid() or ent.Transform == nil then
        return
    end

    if ent.Physics ~= nil then
        ent.Physics:Stop()
        ent.Physics:Teleport(x, 0, z)
    else
        ent.Transform:SetPosition(x, 0, z)
    end
end

local function IsStaticUmbralRiftTransferTarget(ent)
    return ent ~= nil
        and (string.find(ent.prefab or "", "^chesspiece_") ~= nil
            or ent:HasTag("heavy")
            or (ent.components ~= nil and ent.components.heavyobstaclephysics ~= nil))
end

local function CancelUmbralRiftStaticEmergence(ent)
    if ent._umbral_rift_static_emerge_task ~= nil then
        ent._umbral_rift_static_emerge_task:Cancel()
        ent._umbral_rift_static_emerge_task = nil
    end
end

local function GetShadowReliquaryCommon()
    local ok, reliquary = pcall(require, "skill_effect/waxwell/emperor/shadow_reliquary/common")
    if ok then
        return reliquary
    end
    return nil
end

local function SetShadowReliquaryChestRiftTransfer(ent, transferring)
    if ent == nil or not ent:IsValid() or not ent:HasTag("waxwell_shadow_sunken_chest") then
        return
    end
    local reliquary = GetShadowReliquaryCommon()
    if reliquary ~= nil and reliquary.SetShadowReliquaryChestRiftTransfer ~= nil then
        reliquary.SetShadowReliquaryChestRiftTransfer(ent, transferring)
    end
end

local function SetShadowReliquaryCodexRiftTransfer(ent, transferring)
    if ent == nil or not ent:IsValid() or ent.prefab ~= "waxwelljournal" then
        return
    end
    local reliquary = GetShadowReliquaryCommon()
    if reliquary ~= nil and reliquary.SetShadowReliquaryCodexRiftTransfer ~= nil then
        reliquary.SetShadowReliquaryCodexRiftTransfer(ent, transferring)
    end
end

local function TryReliquaryAbsorbRiftCodex(ent, tx, tz)
    if ent == nil or not ent:IsValid() or ent.prefab ~= "waxwelljournal" then
        return false
    end
    local reliquary = GetShadowReliquaryCommon()
    if reliquary ~= nil and reliquary.TryAbsorbShadowReliquaryCodex ~= nil then
        return reliquary.TryAbsorbShadowReliquaryCodex(ent, tx, tz)
    end
    return false
end

local function TryReliquaryAbsorbRiftChest(ent, tx, tz)
    if ent == nil or not ent:IsValid() or not ent:HasTag("waxwell_shadow_sunken_chest") then
        return false
    end
    local reliquary = GetShadowReliquaryCommon()
    if reliquary ~= nil and reliquary.TryAbsorbShadowReliquaryChest ~= nil then
        return reliquary.TryAbsorbShadowReliquaryChest(ent, tx, tz)
    end
    return false
end

local function TryReliquaryAbsorbRiftEntity(ent, tx, tz)
    if TryReliquaryAbsorbRiftChest(ent, tx, tz) then
        return true
    end
    return TryReliquaryAbsorbRiftCodex(ent, tx, tz)
end

local function FinishUmbralRiftEntityTransfer(sourceportal, targetportal, ent)
    if ent == nil or not ent:IsValid() or targetportal == nil or not targetportal:IsValid() then
        return false
    end

    SetShadowReliquaryChestRiftTransfer(ent, false)
    SetShadowReliquaryCodexRiftTransfer(ent, false)
    SetShadowReliquaryCodexRiftTransfer(ent, false)

    local tx, _, tz = targetportal.Transform:GetWorldPosition()
    if not ent._umbral_rift_static_transfer and sourceportal ~= nil and sourceportal:IsValid() then
        sourceportal:RemoveChild(ent)
    end

    local theta = math.random() * TWOPI
    local dx = math.cos(theta)
    local dz = math.sin(theta)

    if ent._umbral_rift_static_transfer then
        ent._umbral_rift_static_transfer = nil
        if ent.Show ~= nil then
            ent:Show()
        end
        -- Place the static item at the portal center, then smoothly lerp it outward
        MoveEntityToPoint(ent, tx, tz)
        CancelUmbralRiftStaticEmergence(ent)
        if TryReliquaryAbsorbRiftEntity(ent, tx, tz) then
            return true
        end
        local emerge_time = V.UMBRAL_RIFT_LV2_STATIC_EMERGE_TIME
        local startx, startz = tx, tz
        local static_offset = V.UMBRAL_RIFT_LV2_STATIC_EMERGE_OFFSET
        local endx = tx + dx * static_offset
        local endz = tz + dz * static_offset
        local elapsed = 0
        ent._umbral_rift_static_emerge_task = ent:DoPeriodicTask(FRAMES, function(item)
            if item == nil or not item:IsValid() then
                if item ~= nil and item._umbral_rift_static_emerge_task ~= nil then
                    item._umbral_rift_static_emerge_task:Cancel()
                    item._umbral_rift_static_emerge_task = nil
                end
                return
            end
            elapsed = elapsed + FRAMES
            local t = math.min(1, emerge_time > 0 and (elapsed / emerge_time) or 1)
            local nx = Lerp(startx, endx, t)
            local nz = Lerp(startz, endz, t)
            MoveEntityToPoint(item, nx, nz)
            if t >= 1 then
                if item._umbral_rift_static_emerge_task ~= nil then
                    item._umbral_rift_static_emerge_task:Cancel()
                    item._umbral_rift_static_emerge_task = nil
                end
            end
        end)
    else
        ent:ReturnToScene()
        MoveEntityToPoint(ent, tx, tz)
        if TryReliquaryAbsorbRiftEntity(ent, tx, tz) then
            return true
        end
    end

    local emerge_offset = V.UMBRAL_RIFT_LV2_EMERGE_OFFSET
    if not IsStaticUmbralRiftTransferTarget(ent) then
        if ent.Physics ~= nil then
            ent.Physics:SetVel(dx * V.UMBRAL_RIFT_LV2_EMERGE_SPEED, 0, dz * V.UMBRAL_RIFT_LV2_EMERGE_SPEED)
        else
            ent.Transform:SetPosition(tx + dx * emerge_offset, 0, tz + dz * emerge_offset)
        end
    elseif ent.Physics ~= nil then
        ent.Transform:SetPosition(tx + dx * emerge_offset, 0, tz + dz * emerge_offset)
    end

    return true
end

local function BeginUmbralRiftEntityTransfer(sourceportal, ent)
    if sourceportal == nil
        or not sourceportal:IsValid()
        or ent == nil
        or not ent:IsValid()
        or sourceportal._linked_portal == nil
        or not sourceportal._linked_portal:IsValid() then
        return false
    end

    local sx, _, sz = sourceportal.Transform:GetWorldPosition()
    local ex, _, ez = ent.Transform:GetWorldPosition()
    local elapsed = 0

    if ent._umbral_rift_transfer_task ~= nil then
        ent._umbral_rift_transfer_task:Cancel()
        ent._umbral_rift_transfer_task = nil
    end

    SetShadowReliquaryChestRiftTransfer(ent, true)
    SetShadowReliquaryCodexRiftTransfer(ent, true)

    ent._umbral_rift_transfer_task = ent:DoPeriodicTask(FRAMES, function(item)
        if item == nil or not item:IsValid() or sourceportal == nil or not sourceportal:IsValid() then
            if item ~= nil then
                item._umbral_rift_transfer_task = nil
                SetShadowReliquaryChestRiftTransfer(item, false)
                SetShadowReliquaryCodexRiftTransfer(item, false)
            end
            return
        end

        elapsed = elapsed + FRAMES
        local t = math.min(1, elapsed / V.UMBRAL_RIFT_LV2_SUCTION_TIME)
        local nx = Lerp(ex, sx, t)
        local nz = Lerp(ez, sz, t)
        MoveEntityToPoint(item, nx, nz)

        if t >= 1 then
            item._umbral_rift_transfer_task:Cancel()
            item._umbral_rift_transfer_task = nil

            if item:IsValid() and sourceportal:IsValid() and sourceportal._linked_portal ~= nil and sourceportal._linked_portal:IsValid() then
                if IsStaticUmbralRiftTransferTarget(item) then
                    item._umbral_rift_static_transfer = true
                    if item.Hide ~= nil then
                        item:Hide()
                    end
                else
                    sourceportal:AddChild(item)
                    item.Transform:SetPosition(0, 0, 0)
                    item:RemoveFromScene()
                end
                -- Cargo waits for portal pipeline: suck → merge stacks in limbo → emerge
                sourceportal._umbral_rift_cargo = sourceportal._umbral_rift_cargo or {}
                table.insert(sourceportal._umbral_rift_cargo, item)
            end
        end
    end)

    return true
end

local function StopUmbralRiftItemPhysics(ent)
    if ent ~= nil and ent:IsValid() and ent.Physics ~= nil then
        ent.Physics:Stop()
    end
end

-- รวม stack ระหว่างอยู่ในวาร์ป (ก่อนออก portal) — ใช้รายการ cargo ไม่ใช้ FindEntities
local function ConsolidateUmbralRiftStacksInPortal(portal)
    if portal == nil or not portal:IsValid() or not TheWorld.ismastersim then
        return
    end

    local cargo = portal._umbral_rift_cargo
    if cargo == nil or #cargo < 2 then
        return
    end

    local stacks = {}
    for _, ent in ipairs(cargo) do
        if ent ~= nil
            and ent:IsValid()
            and ent.components ~= nil
            and ent.components.stackable ~= nil
            and ent.components.inventoryitem ~= nil then
            StopUmbralRiftItemPhysics(ent)
            table.insert(stacks, ent)
        end
    end

    if #stacks < 2 then
        return
    end

    table.sort(stacks, function(a, b)
        return (a.components.stackable:StackSize() or 0) > (b.components.stackable:StackSize() or 0)
    end)

    for i = 1, #stacks do
        local target = stacks[i]
        local tstack = target ~= nil and target:IsValid() and target.components ~= nil and target.components.stackable or nil
        if tstack ~= nil and not tstack:IsFull() then
            for j = #stacks, i + 1, -1 do
                local donor = stacks[j]
                local dstack = donor ~= nil and donor:IsValid() and donor.components ~= nil and donor.components.stackable or nil
                if donor ~= nil
                    and donor:IsValid()
                    and donor.prefab == target.prefab
                    and dstack ~= nil
                    and (tstack.CanStackWith == nil or tstack:CanStackWith(donor)) then
                    tstack:Put(donor)
                    if donor == nil or not donor:IsValid() then
                        table.remove(stacks, j)
                    end
                    if tstack:IsFull() then
                        break
                    end
                end
            end
        end
    end

    -- Rebuild cargo after merges removed some entities
    local kept = {}
    for _, ent in ipairs(cargo) do
        if ent ~= nil and ent:IsValid() then
            table.insert(kept, ent)
        end
    end
    portal._umbral_rift_cargo = kept
end

local function EmergeUmbralRiftCargo(portal)
    if portal == nil or not portal:IsValid() then
        return
    end

    local cargo = portal._umbral_rift_cargo
    portal._umbral_rift_cargo = nil
    if cargo == nil then
        return
    end

    local targetportal = portal._linked_portal
    for _, ent in ipairs(cargo) do
        if ent ~= nil and ent:IsValid() then
            FinishUmbralRiftEntityTransfer(portal, targetportal, ent)
        end
    end
end

-- suck done → merge in limbo → travel → emerge
local function ScheduleUmbralRiftCargoPipeline(portal_a, portal_b)
    local scheduler = (portal_a ~= nil and portal_a:IsValid() and portal_a)
        or (portal_b ~= nil and portal_b:IsValid() and portal_b)
    if scheduler == nil then
        return
    end

    local merge_at = V.UMBRAL_RIFT_LV2_SUCTION_TIME + FRAMES
    local emerge_at = V.UMBRAL_RIFT_LV2_SUCTION_TIME + V.UMBRAL_RIFT_LV2_TRAVEL_TIME + FRAMES

    scheduler:DoTaskInTime(merge_at, function()
        ConsolidateUmbralRiftStacksInPortal(portal_a)
        ConsolidateUmbralRiftStacksInPortal(portal_b)
    end)

    scheduler:DoTaskInTime(emerge_at, function()
        EmergeUmbralRiftCargo(portal_a)
        EmergeUmbralRiftCargo(portal_b)
    end)
end

local function TransferUmbralRiftTargets(sourceportal, targets)
    if sourceportal == nil
        or not sourceportal:IsValid()
        or sourceportal._linked_portal == nil
        or not sourceportal._linked_portal:IsValid() then
        return 0
    end

    local moved = 0
    for _, ent in ipairs(targets) do
        if IsUmbralRiftTransferTarget(ent) then
            moved = moved + (BeginUmbralRiftEntityTransfer(sourceportal, ent) and 1 or 0)
        end
    end

    if moved > 0 and sourceportal.SoundEmitter ~= nil then
        sourceportal.SoundEmitter:PlaySound("dontstarve/common/teleportworm/swallow")
    end

    return moved
end

local function TriggerUmbralRift2Transfer(portal_a, portal_b)
    if portal_a == nil or portal_b == nil or not portal_a:IsValid() or not portal_b:IsValid() then
        return
    end

    local seen = {}
    local source_targets = GetUmbralRiftTransferTargets(portal_a, seen)
    local target_targets = GetUmbralRiftTransferTargets(portal_b, seen)

    TransferUmbralRiftTargets(portal_a, source_targets)
    TransferUmbralRiftTargets(portal_b, target_targets)
    ScheduleUmbralRiftCargoPipeline(portal_a, portal_b)
end

local function SpawnUmbralRiftPair(doer, sourcepos, targetpos)
    local portal_a = SpawnPrefab("umbral_rift_portal")
    local portal_b = SpawnPrefab("umbral_rift_portal")
    if portal_a == nil or portal_b == nil then
        if portal_a ~= nil then
            portal_a:Remove()
        end
        if portal_b ~= nil then
            portal_b:Remove()
        end
        return false
    end

    portal_a.Transform:SetPosition(sourcepos.x, 0, sourcepos.z)
    portal_b.Transform:SetPosition(targetpos.x, 0, targetpos.z)
    portal_a:SetLifetime(GetUmbralRiftDuration(doer))
    portal_b:SetLifetime(GetUmbralRiftDuration(doer))
    if IsUmbralRift2Active(doer) then
        portal_a:MarkUmbralRift2()
        portal_b:MarkUmbralRift2()
    end
    portal_a:LinkPortal(portal_b)
    portal_b:LinkPortal(portal_a)
    if IsUmbralRift2Active(doer) then
        portal_a:DoTaskInTime(0, function()
            TriggerUmbralRift2Transfer(portal_a, portal_b)
        end)
    end
    return true
end

-- =============================================================================
-- Public API (cast — point 1 mark / point 2 warp)
-- =============================================================================

-- ตรวจ cost พอสำหรับ warp จุด 2 หรือไม่ (ใช้ทั้ง client gate + server)
local function CanCastUmbralRiftWarp(book, doer)
    return CanAffordUmbralRiftCast(book, doer)
end

-- วาง mark จุด 1 (server เท่านั้น) — ไม่เล่น anim, ไม่หัก cost
-- คืน true เมื่อวางสำเร็จ / false, reason เมื่อถูกบล็อก (cost/target/cooldown)
local function PlaceUmbralRiftMark(doer, pt, book)
    if not TheWorld.ismastersim or doer == nil or not doer:IsValid() or pt == nil then
        return false
    end

    book = book or GetUmbralRiftCastBook(doer)
    if book == nil then
        return false, "NO_BOOK"
    end

    local blockreason = GetUmbralRiftCastBlockReason(book, doer, pt, false)
    if blockreason ~= nil then
        return false, blockreason
    end

    local target = ResolveUmbralRiftTargetPoint(pt, doer)
    if target == nil then
        return false, "NO_TARGETS"
    end

    RemoveUmbralRiftMark(doer, true)

    local mark = SpawnPrefab("umbral_rift_mark")
    if mark == nil then
        return false
    end
    mark.Transform:SetPosition(target.x, 0, target.z)

    doer._waxwell_umbral_rift_mark_ent = mark
    doer._waxwell_umbral_rift_mark_pos = Vector3(target.x, 0, target.z)
    doer:AddTag(UMBRAL_RIFT_MARK_ACTIVE_TAG)

    StartUmbralRiftMarkLifetime(doer)
    return true
end

-- spell fn จุด 2 (warp) — เรียกผ่าน vanilla CASTAOE → book anim
-- ต้องมี mark อยู่ก่อนเสมอ (จุด 1 ไม่ผ่านที่นี่แล้ว)
local function UmbralRiftSpellFn(inst, doer, pos)
    BeginUmbralRiftWarpCast(doer)

    local sourcepos = GetUmbralRiftMarkPos(doer)
    if sourcepos == nil then
        FinishUmbralRiftWarpCast(doer)
        return false
    end

    local blockreason = GetUmbralRiftCastBlockReason(inst, doer, pos, true)
    if blockreason ~= nil then
        FinishUmbralRiftWarpCast(doer, {
            keep_mark = ShouldKeepUmbralRiftMarkOnCastFail(blockreason),
        })
        if blockreason == "NO_FUEL_AND_SANITY" then
            return false, "NO_FUEL_AND_SANITY"
        elseif blockreason == "NO_FUEL_EMPTY" or blockreason == "NO_FUEL_COST" then
            return false, "NO_FUEL"
        elseif blockreason == "NO_SANITY" then
            return false, "NO_SANITY"
        elseif blockreason == "SPELL_ON_COOLDOWN" then
            return false, "SPELL_ON_COOLDOWN"
        elseif blockreason == "NO_TARGETS" then
            return false, "NO_TARGETS"
        end
        return false
    end

    local targetpos = ResolveUmbralRiftTargetPoint(pos, doer)
    if targetpos == nil then
        FinishUmbralRiftWarpCast(doer, { keep_mark = true })
        return false, "NO_TARGETS"
    end

    if not SpawnUmbralRiftPair(doer, sourcepos, targetpos) then
        FinishUmbralRiftWarpCast(doer)
        return false
    end

    FinishUmbralRiftWarpCast(doer, { success = true })

    inst.components.fueled:DoDelta(SpellCost(GetUmbralRiftDurabilityCostPct(doer)), doer)
    if doer.components ~= nil and doer.components.sanity ~= nil then
        doer.components.sanity:DoDelta(-GetUmbralRiftSanityCost(doer))
    end
    RestartSpellCooldown(doer, V.UMBRAL_RIFT_COOLDOWN_ID, GetUmbralRiftCooldownTime(doer))

    return true
end
local function GetUmbralRiftSpellData()
    return {
        spell_id = V.UMBRAL_RIFT_SPELL,
        label = STRINGS.SPELLS[V.UMBRAL_RIFT_SPELL],
        onselect = function(inst)
            inst._waxwell_umbral_rift_active = true
            inst.components.spellbook:SetSpellName(STRINGS.SPELLS[V.UMBRAL_RIFT_SPELL])
            inst.components.spellbook:SetSpellAction(nil)
            inst.components.aoetargeting:SetAlwaysValid(false)
            inst.components.aoetargeting:SetAllowWater(false)
            -- จุด 2 = single cast (ไม่ repeat) → คลิกแล้ว vanilla ปิด reticule + เล่น anim + warp
            inst.components.aoetargeting:SetShouldRepeatCastFn(function() return false end)
            ReticuleUtils.ApplySpellReticule(inst, inst.components.aoetargeting, V.UMBRAL_RIFT_RETICULE_SCALE, "s", {
                cast_range = V.UMBRAL_RIFT_CAST_RANGE,
                auto_work_radius = true,
                validfn = UmbralRiftReticuleValidFn,
            })
            if TheWorld.ismastersim then
                inst.components.aoetargeting:SetTargetFX("reticuleaoesummontarget_1d2")
                inst.components.aoespell:SetSpellFn(UmbralRiftSpellFn)
                inst.components.spellbook:SetSpellFn(nil)
            end
        end,
        execute = StartAOETargeting,
        atlas = "images/waxwell/waxwell_codex_icon.xml",
        normal = "codex_umbra_umbral_rift.tex",
        widget_scale = V.UMBRAL_RIFT_ICON_SCALE,
        hit_radius = V.UMBRAL_RIFT_ICON_RADIUS,
        checkcooldown = function(user)
            return GetUmbralRiftCooldownPercent(user)
        end,
        cooldowncolor = { .12, .28, .42, .50 },
        cooldownscale = 1.42,
    }
end

return {
    UMBRAL_RIFT_SPELL = V.UMBRAL_RIFT_SPELL,
    UMBRAL_RIFT_RPC = UMBRAL_RIFT_RPC,
    IsUmbralRift1Active = IsUmbralRift1Active,
    IsUmbralRift2Active = IsUmbralRift2Active,
    IsUmbralRiftSkillActive = IsUmbralRiftSkillActive,
    IsUmbralRiftBook = IsUmbralRiftBook,
    IsUmbralRiftWheelItem = IsUmbralRiftWheelItem,
    GetUmbralRiftCastBook = GetUmbralRiftCastBook,
    GetUmbralRiftPendingSource = GetUmbralRiftPendingSource,
    HasUmbralRiftMark = HasUmbralRiftMark,
    IsUmbralRiftWithinCastRange = IsUmbralRiftWithinCastRange,
    IsUmbralRiftPendingActive = IsUmbralRiftPendingActive,
    PlaceUmbralRiftMark = PlaceUmbralRiftMark,
    ReserveUmbralRiftWarpCast = ReserveUmbralRiftWarpCast,
    BeginUmbralRiftWarpCast = BeginUmbralRiftWarpCast,
    RemoveUmbralRiftMark = RemoveUmbralRiftMark,
    CanCastUmbralRiftWarp = CanCastUmbralRiftWarp,
    CanAffordUmbralRiftCast = CanAffordUmbralRiftCast,
    GetUmbralRiftSanityCost = GetUmbralRiftSanityCost,
    ClearUmbralRiftPendingState = ClearUmbralRiftPendingState,
    CancelUmbralRiftSkill = CancelUmbralRiftSkill,
    CleanupUmbralRiftSkill = CleanupUmbralRiftSkill,
    ResetUmbralRiftJournalState = ResetUmbralRiftJournalState,
    GetUmbralRiftSpellData = GetUmbralRiftSpellData,
}