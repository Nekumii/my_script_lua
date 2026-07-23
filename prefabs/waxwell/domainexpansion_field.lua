local V = require("skill_effect/waxwell/emperor/domain_expansion/variables")
local spell_utils = require("skill_effect/waxwell/_shared/codex_spell_utils")
local outside_target_block = require("skill_effect/waxwell/emperor/domain_expansion/outside_target_block")

local BARRIER_ENFORCE_PERIOD = 0 -- every frame for smooth slide
local BARRIER_SEPARATION = 1
local BARRIER_CATCH = .7
local PILLAR_WARNING_CHECK_PERIOD = .5
local OWNER_PRESENCE_PERIOD = 0 -- every frame; outfit/speed follow owner in/out
local FLYING_SKIP_TAGS = { "flying", "bird", "flyingcreature", "inflight" }
local BARRIER_CANT_TAGS = { "INLIMBO", "FX", "NOCLICK", "DECOR" }
local SHADOW_CREATURE_MUST_TAGS = { "shadowcreature" }
local KILL_SANITY_SKIP_TAGS = {
    "player", "playerghost", "companion", "INLIMBO", "FX", "NOCLICK", "DECOR",
    "wall", "structure", "shadowminion", "abigail",
}
local VOLUNTARY_SLEEP_END_TAGS = { "bedroll", "tent" } -- tent / bedroll always end DE
local FORCED_SLEEP_END_TAGS = { "sleeping" } -- mandrake / boss CC / etc.

local emperor_common

local function GetEmperorCommon()
    if emperor_common == nil then
        emperor_common = require("skill_effect/waxwell/emperor/_shared/common")
    end
    return emperor_common
end

local function GetBarrierBand()
    return math.max(BARRIER_CATCH, V.DOMAIN_EXPANSION_BARRIER_BAND or BARRIER_CATCH)
end

local function PushSpellRefresh(owner)
    if owner ~= nil and TheWorld ~= nil then
        TheWorld:PushEvent("waxwell_emperor_spell_refresh", { owner = owner })
    end
end

local function ClearPendingDomainState(owner)
    if owner ~= nil then
        owner._waxwell_domain_expansion_pending_state = nil
        owner._waxwell_domain_expansion_pending_position = nil
    end
end

local function ApplyDomainSpeedBoost(owner)
    if owner == nil or not owner:IsValid() then
        return
    end
    local locomotor = owner.components ~= nil and owner.components.locomotor or nil
    if locomotor ~= nil then
        locomotor:SetExternalSpeedMultiplier(
            owner,
            V.DOMAIN_EXPANSION_SPEED_KEY or "waxwell_domain_expansion_speed",
            V.DOMAIN_EXPANSION_SPEED_MULT or 1.20
        )
    end
end

local function ClearDomainSpeedBoost(owner)
    if owner == nil or not owner:IsValid() then
        return
    end
    local locomotor = owner.components ~= nil and owner.components.locomotor or nil
    if locomotor ~= nil then
        locomotor:RemoveExternalSpeedMultiplier(
            owner,
            V.DOMAIN_EXPANSION_SPEED_KEY or "waxwell_domain_expansion_speed"
        )
    end
end

local function IsPointInDomain(inst, x, z)
    if inst == nil then
        return false
    end
    local cx, _, cz = inst.Transform:GetWorldPosition()
    local radius = inst.radius or V.DOMAIN_EXPANSION_RADIUS
    local dx = x - cx
    local dz = z - cz
    return (dx * dx + dz * dz) <= (radius * radius)
end

local function IsOwnerInsideDomain(inst, owner)
    if inst == nil or owner == nil or not owner:IsValid() or owner.Transform == nil then
        return false
    end
    local ox, _, oz = owner.Transform:GetWorldPosition()
    return IsPointInDomain(inst, ox, oz)
end

local function SyncOwnerInDomainEffects(inst)
    if inst == nil or not inst:IsValid() or inst._ending or not inst._active then
        return
    end

    local owner = inst.owner
    if owner == nil or not owner:IsValid() then
        return
    end

    -- Never re-apply outfit/speed while DE is ending or sanity-floor lock is set.
    if owner._waxwell_imperial_regalia_sanity_floor_ended then
        ClearDomainSpeedBoost(owner)
        return
    end

    local common = GetEmperorCommon()
    local inside = IsOwnerInsideDomain(inst, owner)
    if inside then
        ApplyDomainSpeedBoost(owner)
        if common.ResumeImperialRegaliaOutfit ~= nil then
            common.ResumeImperialRegaliaOutfit(owner)
        end
    else
        ClearDomainSpeedBoost(owner)
        if common.SuspendImperialRegaliaOutfit ~= nil then
            common.SuspendImperialRegaliaOutfit(owner)
        end
    end
end

local function IsFlyingEntity(ent)
    if ent == nil then
        return false
    end
    for _, tag in ipairs(FLYING_SKIP_TAGS) do
        if ent:HasTag(tag) then
            return true
        end
    end
    return false
end

local function RemoveBarrierPillars(inst)
    if inst._barrier_pillars == nil then
        return
    end

    for _, pillar in ipairs(inst._barrier_pillars) do
        if pillar ~= nil and pillar:IsValid() then
            if pillar.KillFX ~= nil then
                pillar:KillFX()
            else
                pillar:Remove()
            end
        end
    end
    inst._barrier_pillars = nil
end

local function SetPillarsWarning(inst, active)
    if inst._barrier_pillars == nil then
        return
    end

    for _, pillar in ipairs(inst._barrier_pillars) do
        if pillar ~= nil and pillar:IsValid() and pillar.SetWarning ~= nil then
            pillar:SetWarning(active)
        end
    end
end

local function UpdatePillarWarningFromSanity(inst)
    if inst == nil or not inst:IsValid() or inst._ending or not inst._active then
        return
    end

    local owner = inst.owner
    local sanity = owner ~= nil and owner:IsValid() and owner.components ~= nil and owner.components.sanity or nil
    if sanity == nil then
        SetPillarsWarning(inst, false)
        return
    end

    local maxsanity = sanity.max or 0
    if maxsanity <= 0 then
        SetPillarsWarning(inst, false)
        return
    end

    local threshold = V.DOMAIN_EXPANSION_PILLAR_WARNING_SANITY or .10
    local percent = (sanity.current or 0) / maxsanity
    -- <10% → shake; >10% → idle; ==10% keep current state
    if percent < threshold then
        SetPillarsWarning(inst, true)
    elseif percent > threshold then
        SetPillarsWarning(inst, false)
    end
end

local function SpawnBarrierPillars(inst)
    RemoveBarrierPillars(inst)

    local cx, cy, cz = inst.Transform:GetWorldPosition()
    local radius = inst.radius or V.DOMAIN_EXPANSION_RADIUS
    local count = V.DOMAIN_EXPANSION_BARRIER_PILLAR_COUNT or 28
    inst._barrier_pillars = {}

    local delays = {}
    local period = 1 / math.max(1, count)
    for i = 0, count - 1 do
        table.insert(delays, i * period * .35)
    end

    for i = 1, count do
        local theta = (i / count) * TWOPI
        local px = cx + math.cos(theta) * radius
        local pz = cz + math.sin(theta) * radius
        local pillar = SpawnPrefab("domain_expansion_barrier_pillar")
        if pillar ~= nil then
            pillar.Transform:SetPosition(px, 0, pz)
            pillar.Transform:SetRotation(-theta * RADIANS + 90)
            local delay = table.remove(delays, math.random(#delays)) or 0
            if pillar.BeginRaise ~= nil then
                pillar:BeginRaise(delay)
            end
            table.insert(inst._barrier_pillars, pillar)
        end
    end

    UpdatePillarWarningFromSanity(inst)
end

local function AddBarrierEntity(ents, ent, seen)
    if ent ~= nil and ent:IsValid() and seen[ent.GUID] == nil then
        seen[ent.GUID] = true
        table.insert(ents, ent)
    end
end

local function FindBarrierEntities(cx, cz, searchradius)
    local ents = {}
    local seen = {}

    for _, ent in ipairs(TheSim:FindEntities(cx, 0, cz, searchradius, nil, BARRIER_CANT_TAGS)) do
        AddBarrierEntity(ents, ent, seen)
    end

    -- Shadow creatures can be intangible/no-click in some states, so give them a
    -- dedicated pass instead of relying only on the broad physical query.
    for _, ent in ipairs(TheSim:FindEntities(cx, 0, cz, searchradius, SHADOW_CREATURE_MUST_TAGS, { "INLIMBO", "FX" })) do
        AddBarrierEntity(ents, ent, seen)
    end

    return ents
end

local function SetEntityXZ(ent, x, y, z)
    if ent.Physics ~= nil and ent.Physics:IsActive() and ent.Physics.Teleport ~= nil then
        ent.Physics:Teleport(x, y, z)
    else
        ent.Transform:SetPosition(x, y, z)
    end
end

local function ClearRadialMotion(ent, nx, nz, block_outward)
    if ent == nil or ent.Physics == nil or not ent.Physics:IsActive() then
        return
    end

    if ent.Physics.GetMotorVel ~= nil and ent.Physics.SetMotorVel ~= nil then
        local mx, my, mz = ent.Physics:GetMotorVel()
        mx = mx or 0
        my = my or 0
        mz = mz or 0
        local motor_radial = mx * nx + mz * nz
        if block_outward and motor_radial > 0 then
            ent.Physics:SetMotorVel(mx - motor_radial * nx, my, mz - motor_radial * nz)
        elseif not block_outward and motor_radial < 0 then
            ent.Physics:SetMotorVel(mx - motor_radial * nx, my, mz - motor_radial * nz)
        end
    end

    if ent.Physics.GetVelocity ~= nil and ent.Physics.SetVel ~= nil then
        local vx, vy, vz = ent.Physics:GetVelocity()
        vx = vx or 0
        vy = vy or 0
        vz = vz or 0
        local vel_radial = vx * nx + vz * nz
        if block_outward and vel_radial > 0 then
            ent.Physics:SetVel(vx - vel_radial * nx, vy, vz - vel_radial * nz)
        elseif not block_outward and vel_radial < 0 then
            ent.Physics:SetVel(vx - vel_radial * nx, vy, vz - vel_radial * nz)
        end
    end
end

local function EnforceBarrier(inst)
    if inst == nil or not inst:IsValid() or inst._ending or not inst._active then
        return
    end

    local cx, cy, cz = inst.Transform:GetWorldPosition()
    local radius = inst.radius or V.DOMAIN_EXPANSION_RADIUS
    local catch = BARRIER_CATCH
    local separation = BARRIER_SEPARATION
    local searchradius = radius + catch + 1
    local ents = FindBarrierEntities(cx, cz, searchradius)

    for _, ent in ipairs(ents) do
        if ent ~= nil
            and ent:IsValid()
            and ent.Transform ~= nil
            and not IsFlyingEntity(ent)
            and ent.prefab ~= "domainexpansion_field"
            and not ent:HasTag("domain_expansion_barrier")
            and not ent:HasTag("domain_expansion_spike") then
            local ex, ey, ez = ent.Transform:GetWorldPosition()
            local dx = ex - cx
            local dz = ez - cz
            local distsq = dx * dx + dz * dz
            if distsq > .0001 then
                local dist = math.sqrt(distsq)
                local nx = dx / dist
                local nz = dz / dist
                if dist >= radius then
                    -- Outside: block entering; slide along outer membrane.
                    ClearRadialMotion(ent, nx, nz, false)
                    if dist < radius + catch then
                        local target = radius + separation
                        if math.abs(dist - target) > .02 then
                            SetEntityXZ(ent, cx + nx * target, ey, cz + nz * target)
                        end
                    end
                else
                    -- Inside: block exiting; slide along inner membrane.
                    ClearRadialMotion(ent, nx, nz, true)
                    if dist > radius - catch then
                        local target = radius - separation
                        if math.abs(dist - target) > .02 then
                            SetEntityXZ(ent, cx + nx * target, ey, cz + nz * target)
                        end
                    end
                end
            end
        end
    end
end

local function RemoveSpikeFX(inst)
    if inst._spike_fx == nil then
        return
    end

    for _, spike in ipairs(inst._spike_fx) do
        if spike ~= nil and spike:IsValid() then
            if spike.FinishAndRemove ~= nil then
                spike:FinishAndRemove()
            else
                spike:Remove()
            end
        end
    end
    inst._spike_fx = nil
end

local function IsFarEnoughFromSpikes(points, x, z, minspacing)
    local minsq = minspacing * minspacing
    for _, pt in ipairs(points) do
        local dx = x - pt.x
        local dz = z - pt.z
        if dx * dx + dz * dz < minsq then
            return false
        end
    end
    return true
end

local function SpawnSpikeFX(inst)
    RemoveSpikeFX(inst)

    local cx, _, cz = inst.Transform:GetWorldPosition()
    local radius = inst.radius or V.DOMAIN_EXPANSION_RADIUS
    local count = V.DOMAIN_EXPANSION_SPIKE_COUNT or 10
    local edgepad = V.DOMAIN_EXPANSION_SPIKE_EDGE_PADDING or 1.25
    local minspacing = V.DOMAIN_EXPANSION_SPIKE_MIN_SPACING or 1.75
    local innerradius = math.max(1, radius - edgepad)
    local points = {}
    inst._spike_fx = {}

    for i = 1, count do
        local px, pz
        for _ = 1, 40 do
            local theta = math.random() * TWOPI
            local dist = math.sqrt(math.random()) * innerradius
            local candidate_x = cx + math.cos(theta) * dist
            local candidate_z = cz + math.sin(theta) * dist
            if IsFarEnoughFromSpikes(points, candidate_x, candidate_z, minspacing) then
                px, pz = candidate_x, candidate_z
                break
            end
        end

        if px == nil then
            local theta = ((i - 1) / count) * TWOPI
            local dist = innerradius * (.45 + .4 * ((i % 3) / 2))
            px = cx + math.cos(theta) * dist
            pz = cz + math.sin(theta) * dist
        end

        table.insert(points, { x = px, z = pz })

        local delay = (i - 1) * (1 + math.random() * .5) * FRAMES
        inst:DoTaskInTime(delay, function()
            if inst == nil or not inst:IsValid() or inst._ending or not inst._active then
                return
            end

            local spike = SpawnPrefab("domain_expansion_spike_fx")
            if spike ~= nil then
                spike.Transform:SetPosition(px, 0, pz)
                if spike.BeginFall ~= nil then
                    spike:BeginFall(math.random(7))
                end
                table.insert(inst._spike_fx, spike)
            end
        end)
    end
end

local function HasKillSanitySkipTag(victim)
    for _, tag in ipairs(KILL_SANITY_SKIP_TAGS) do
        if victim:HasTag(tag) then
            return true
        end
    end
    return false
end

local function IsKillCreditAfflicter(owner, afflicter)
    if owner == nil or afflicter == nil or not afflicter:IsValid() then
        return false
    end
    if afflicter == owner then
        return true
    end
    if afflicter._waxwell_owner == owner then
        return true
    end
    local follower = afflicter.components ~= nil and afflicter.components.follower or nil
    if follower ~= nil and follower.leader == owner then
        return true
    end
    return false
end

local function GetKillSanityRestore(victim)
    if victim == nil or not victim:IsValid() then
        return nil
    end
    if HasKillSanitySkipTag(victim) then
        return nil
    end
    if victim.components == nil or victim.components.health == nil then
        return nil
    end

    if victim:HasAnyTag("largecreature", "epic", "boss", "smallepic") then
        return V.DOMAIN_EXPANSION_KILL_SANITY_LARGE or 30
    end

    if victim:HasAnyTag("monster", "animal", "insect", "prey", "hostile", "character")
        or victim.components.combat ~= nil then
        return V.DOMAIN_EXPANSION_KILL_SANITY_SMALL or 5
    end

    return nil
end

local function OnEntityDeath(inst, data)
    if inst == nil or not inst:IsValid() or inst._ending or not inst._active then
        return
    end

    local victim = data ~= nil and data.inst or nil
    if victim == nil or not victim:IsValid() then
        return
    end

    local owner = inst.owner
    if owner == nil or not owner:IsValid() then
        return
    end

    if not IsKillCreditAfflicter(owner, data.afflicter) then
        return
    end

    local vx, _, vz = victim.Transform:GetWorldPosition()
    if not IsPointInDomain(inst, vx, vz) then
        return
    end

    local amount = GetKillSanityRestore(victim)
    if amount == nil or amount <= 0 then
        return
    end

    local sanity = owner.components ~= nil and owner.components.sanity or nil
    if sanity ~= nil then
        sanity:DoDelta(amount)
    end
end

local function DetachWorldDeathListener(inst)
    if inst._on_entity_death ~= nil and TheWorld ~= nil then
        TheWorld:RemoveEventCallback("entity_death", inst._on_entity_death)
    end
    inst._on_entity_death = nil
end

local function AttachWorldDeathListener(inst)
    DetachWorldDeathListener(inst)
    inst._on_entity_death = function(_, data)
        OnEntityDeath(inst, data)
    end
    TheWorld:ListenForEvent("entity_death", inst._on_entity_death)
end

local function SetDomainFieldNetworkState(inst, live)
    if inst._domain_live == nil then
        return
    end

    inst._domain_radius:set(inst.radius or V.DOMAIN_EXPANSION_RADIUS)
    inst._domain_live:set(live == true)
end

local function StopOutsideFocusClear(inst)
    if inst._outside_focus_task ~= nil then
        inst._outside_focus_task:Cancel()
        inst._outside_focus_task = nil
    end
end

local function StartOutsideFocusClear(inst)
    StopOutsideFocusClear(inst)
    SetDomainFieldNetworkState(inst, true)
    outside_target_block.RegisterField(inst)
    outside_target_block.ClearOutsideFocusOnField(inst)
    inst._outside_focus_task = inst:DoPeriodicTask(
        outside_target_block.GetFocusClearPeriod(),
        function()
            outside_target_block.ClearOutsideFocusOnField(inst)
        end
    )
end

local function StopOwnerPresenceTask(inst)
    if inst._owner_presence_task ~= nil then
        inst._owner_presence_task:Cancel()
        inst._owner_presence_task = nil
    end
end

local function StartOwnerPresenceTask(inst)
    StopOwnerPresenceTask(inst)
    SyncOwnerInDomainEffects(inst)
    inst._owner_presence_task = inst:DoPeriodicTask(OWNER_PRESENCE_PERIOD, SyncOwnerInDomainEffects)
end

local function DetachOwnerListeners(inst)
    if inst.owner ~= nil and inst._owner_onremove ~= nil then
        inst.owner:RemoveEventCallback("onremove", inst._owner_onremove)
    end
    if inst.owner ~= nil and inst._owner_death ~= nil then
        inst.owner:RemoveEventCallback("death", inst._owner_death)
    end
    if inst.owner ~= nil and inst._owner_newstate ~= nil then
        inst.owner:RemoveEventCallback("newstate", inst._owner_newstate)
    end
    inst._owner_onremove = nil
    inst._owner_death = nil
    inst._owner_newstate = nil
end

local function AttachOwnerListeners(inst, owner)
    if inst == nil or owner == nil or not owner:IsValid() then
        return
    end

    DetachOwnerListeners(inst)

    inst.owner = owner
    inst._owner_userid = owner.userid
    owner._waxwell_domain_expansion_field = inst

    inst._owner_onremove = function()
        if inst ~= nil and inst:IsValid() then
            inst:RequestDeactivate("owner_removed")
        end
    end
    inst._owner_death = function()
        if inst ~= nil and inst:IsValid() then
            inst:RequestDeactivate("owner_death")
        end
    end
    -- Tent/bedroll always end DE. Forced sleep (mandrake/boss/etc.) ends only outside the circle.
    inst._owner_newstate = function(player)
        if inst == nil or not inst:IsValid() or inst._ending or not inst._active then
            return
        end
        local sg = player ~= nil and player.sg or nil
        if sg == nil then
            return
        end

        for _, tag in ipairs(VOLUNTARY_SLEEP_END_TAGS) do
            if sg:HasStateTag(tag) then
                inst:RequestDeactivate("owner_sleep_bed")
                return
            end
        end

        local forced_sleep = false
        for _, tag in ipairs(FORCED_SLEEP_END_TAGS) do
            if sg:HasStateTag(tag) then
                forced_sleep = true
                break
            end
        end
        if forced_sleep and not IsOwnerInsideDomain(inst, player) then
            inst:RequestDeactivate("owner_sleep_outside")
        end
    end

    owner:ListenForEvent("onremove", inst._owner_onremove)
    owner:ListenForEvent("death", inst._owner_death)
    owner:ListenForEvent("newstate", inst._owner_newstate)
end

local function EndDomain(inst)
    if inst == nil or inst._ending then
        return
    end

    inst._ending = true
    inst._active = false

    if inst._barrier_task ~= nil then
        inst._barrier_task:Cancel()
        inst._barrier_task = nil
    end
    if inst._warning_task ~= nil then
        inst._warning_task:Cancel()
        inst._warning_task = nil
    end

    StopOwnerPresenceTask(inst)
    StopOutsideFocusClear(inst)
    SetDomainFieldNetworkState(inst, false)
    outside_target_block.UnregisterField(inst)
    DetachWorldDeathListener(inst)
    RemoveSpikeFX(inst)
    RemoveBarrierPillars(inst)

    local owner = inst.owner
    ClearDomainSpeedBoost(owner)
    if owner ~= nil and owner._waxwell_domain_expansion_field == inst then
        owner._waxwell_domain_expansion_field = nil
    end
    ClearPendingDomainState(owner)
    DetachOwnerListeners(inst)

    local common = GetEmperorCommon()
    -- Force immediate outfit restore so gear does not lag a frame behind field end
    -- (pillars may still play lower FX — that is visual only).
    if owner ~= nil and owner:IsValid() and common.ForceImperialRegaliaDeactivate ~= nil then
        common.ForceImperialRegaliaDeactivate(owner, false, false)
    elseif owner ~= nil and owner:IsValid() and common.RequestImperialRegaliaDeactivate ~= nil then
        common.RequestImperialRegaliaDeactivate(owner, false, false)
    end


    if owner ~= nil and owner:IsValid() then
        spell_utils.RestartSpellCooldown(owner, V.DOMAIN_EXPANSION_COOLDOWN_ID, V.DOMAIN_EXPANSION_COOLDOWN_TIME)
    end
    PushSpellRefresh(owner)

    inst._owner_userid = nil
    inst:Remove()
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddNetwork()

    -- Invisible logic entity at domain center — must not block AOE deploy.
    -- Spikes: FX/NOBLOCK (cast inside OK). Pillars: no FX/NOBLOCK (block rift on posts).
    inst:AddTag("FX")
    inst:AddTag("NOCLICK")
    inst:AddTag("NOBLOCK")
    inst:AddTag("allow_casting")
    inst:AddTag("CLASSIFIED")
    inst:AddTag("domain_expansion_field")
    inst.persists = false

    inst._domain_live = net_bool(inst.GUID, "domainexpansion_field._live", "domainexpansion_livedirty")
    inst._domain_radius = net_float(inst.GUID, "domainexpansion_field._radius")
    inst._domain_live:set_local(false)
    inst._domain_radius:set_local(V.DOMAIN_EXPANSION_RADIUS)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        local function OnDomainLiveDirty()
            if inst._domain_live:value() then
                outside_target_block.RegisterField(inst)
            else
                outside_target_block.UnregisterField(inst)
            end
        end

        inst:ListenForEvent("domainexpansion_livedirty", OnDomainLiveDirty)
        inst:ListenForEvent("onremove", function()
            outside_target_block.UnregisterField(inst)
        end)

        inst:DoTaskInTime(0, function()
            if inst:IsValid() then
                OnDomainLiveDirty()
            end
        end)

        return inst
    end

    inst.radius = V.DOMAIN_EXPANSION_RADIUS
    inst._active = false
    inst._ending = false
    inst.owner = nil
    inst._owner_userid = nil
    inst._barrier_pillars = nil
    inst._spike_fx = nil
    inst._barrier_task = nil
    inst._warning_task = nil
    inst._outside_focus_task = nil
    inst._owner_presence_task = nil
    inst._owner_onremove = nil
    inst._owner_death = nil
    inst._owner_newstate = nil
    inst._on_entity_death = nil

    function inst:GetPersistData()
        local x, y, z = self.Transform:GetWorldPosition()
        return {
            pos = { x = x, z = z },
            radius = self.radius or V.DOMAIN_EXPANSION_RADIUS,
        }
    end

    function inst:RequestDeactivate(reason)
        EndDomain(self)
    end

    function inst:RebindOwner(owner)
        if owner == nil or not owner:IsValid() then
            return
        end

        AttachOwnerListeners(self, owner)
        ClearPendingDomainState(owner)
        StartOwnerPresenceTask(self)
        if self._barrier_pillars == nil or #self._barrier_pillars == 0 then
            SpawnBarrierPillars(self)
        end
        if self._spike_fx == nil or #self._spike_fx == 0 then
            SpawnSpikeFX(self)
        end
        if self._barrier_task == nil then
            self._barrier_task = self:DoPeriodicTask(BARRIER_ENFORCE_PERIOD, EnforceBarrier)
        end
        if self._warning_task == nil then
            self._warning_task = self:DoPeriodicTask(PILLAR_WARNING_CHECK_PERIOD, UpdatePillarWarningFromSanity)
        end
        StartOutsideFocusClear(self)
        AttachWorldDeathListener(self)
        UpdatePillarWarningFromSanity(self)
        PushSpellRefresh(owner)
    end

    function inst:Activate(owner, pos, radius, persistdata)
        if owner == nil or not owner:IsValid() then
            return
        end

        self.Transform:SetPosition(pos.x, 0, pos.z)
        self.radius = radius or self.radius
        self._active = true
        self._ending = false
        ClearPendingDomainState(owner)
        AttachOwnerListeners(self, owner)

        SpawnBarrierPillars(self)
        SpawnSpikeFX(self)

        if self._barrier_task ~= nil then
            self._barrier_task:Cancel()
        end
        self._barrier_task = self:DoPeriodicTask(BARRIER_ENFORCE_PERIOD, EnforceBarrier)

        if self._warning_task ~= nil then
            self._warning_task:Cancel()
        end
        self._warning_task = self:DoPeriodicTask(PILLAR_WARNING_CHECK_PERIOD, UpdatePillarWarningFromSanity)
        StartOutsideFocusClear(self)
        AttachWorldDeathListener(self)
        UpdatePillarWarningFromSanity(self)

        local common = GetEmperorCommon()
        if common.FinalizeImperialRegaliaActivate ~= nil then
            owner._waxwell_imperial_regalia_activating = true
            owner._waxwell_imperial_regalia_active = nil
            owner._waxwell_imperial_regalia_deactivating = nil
            owner._waxwell_imperial_regalia_outfit_suspended = nil
            common.FinalizeImperialRegaliaActivate(owner)
        end

        StartOwnerPresenceTask(self)
        PushSpellRefresh(owner)
    end

    return inst
end

return Prefab("domainexpansion_field", fn)
