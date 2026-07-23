-- Lanternbearer LV2 firefly spawn gate: only spawn during relevant combat.
local Profiles = require("skill_effect/waxwell/_shared/shadow_firefly/profiles")

local M = {}

local THREAT_MUST_TAGS = { "_combat", "_health" }
local THREAT_CANT_TAGS = { "INLIMBO", "playerghost", "companion", "player" }
local THREAT_ONEOF_TAGS = { "monster", "prey", "insect", "hostile", "character", "animal" }

local function IsValidBoundPlayer(player)
    return player ~= nil
        and player:IsValid()
        and player:HasTag("player")
        and not player:HasTag("playerghost")
        and player.entity:IsVisible()
end

local function GetBoundPlayer(lantern)
    if lantern == nil or not lantern:IsValid() then
        return nil
    end

    if lantern.GetTargetPlayer ~= nil then
        local player = lantern:GetTargetPlayer()
        if IsValidBoundPlayer(player) then
            return player
        end
    end

    local player = lantern._bound_target
    if IsValidBoundPlayer(player) then
        return player
    end

    if lantern._bound_target_userid ~= nil then
        for _, p in ipairs(AllPlayers) do
            if p ~= nil and p.userid == lantern._bound_target_userid then
                return p
            end
        end
    end

    return nil
end

local function FindWaxwellOwner(lantern)
    if lantern == nil then
        return nil
    end

    local owner = lantern._waxwell_owner
    if owner ~= nil and owner:IsValid() then
        return owner
    end

    if lantern._waxwell_owner_userid ~= nil then
        for _, player in ipairs(AllPlayers) do
            if player ~= nil and player.userid == lantern._waxwell_owner_userid then
                lantern._waxwell_owner = player
                return player
            end
        end
    end

    return nil
end

local function GetSpawnZoneRadius(lantern)
    local light_radius = 5.25
    if lantern ~= nil and lantern:IsValid() and lantern.Light ~= nil then
        light_radius = lantern.Light:GetRadius()
    end
    return light_radius * (Profiles.LANTERNBEARER_SPAWN_ZONE_MULT or 1.25)
end

local function IsInSpawnZone(lantern, ent, radius)
    if lantern == nil or ent == nil or not ent:IsValid() then
        return false
    end

    local lx, ly, lz = lantern.Transform:GetWorldPosition()
    local ex, ey, ez = ent.Transform:GetWorldPosition()
    local dx, dz = ex - lx, ez - lz
    return dx * dx + dz * dz <= radius * radius
end

local function IsProtectedEntity(lantern, ent)
    if ent == nil or not ent:IsValid() then
        return false
    end

    local player = GetBoundPlayer(lantern)
    local owner = FindWaxwellOwner(lantern)

    if ent == player or ent == owner then
        return true
    end

    if owner ~= nil
        and owner.components ~= nil
        and owner.components.combat ~= nil
        and owner.components.combat:IsAlly(ent) then
        return true
    end

    if player ~= nil
        and player.components ~= nil
        and player.components.combat ~= nil
        and player.components.combat:IsAlly(ent) then
        return true
    end

    if ent:HasTag("companion") or ent:HasTag("playerpet") or ent:HasTag("shadowminion") then
        local follower = ent.components ~= nil and ent.components.follower or nil
        local leader = follower ~= nil and follower:GetLeader() or nil
        if leader == player or leader == owner then
            return true
        end
    end

    if owner ~= nil
        and owner.components ~= nil
        and owner.components.petleash ~= nil
        and owner.components.petleash:IsPet(ent) then
        return true
    end

    if player ~= nil
        and player.components ~= nil
        and player.components.petleash ~= nil
        and player.components.petleash:IsPet(ent) then
        return true
    end

    return false
end

local function IsValidThreatEnemy(lantern, ent)
    if ent == nil
        or not ent:IsValid()
        or ent == lantern
        or ent.components == nil
        or ent.components.combat == nil
        or ent.components.health == nil
        or ent.components.health:IsDead() then
        return false
    end

    if ent:HasTag("player")
        or ent:HasTag("companion")
        or ent:HasTag("playerpet")
        or ent:HasTag("shadow_lanternbearer")
        or ent:HasTag("waxwell_shadow_firefly") then
        return false
    end

    return true
end

local function IsEnemyThreateningProtected(lantern, enemy)
    if not IsValidThreatEnemy(lantern, enemy) then
        return false
    end

    local target = enemy.components.combat.target
    return target ~= nil and IsProtectedEntity(lantern, target)
end

local function HasEnemyInZone(lantern, radius)
    local lx, ly, lz = lantern.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(lx, ly, lz, radius, THREAT_MUST_TAGS, THREAT_CANT_TAGS, THREAT_ONEOF_TAGS)
    for _, ent in ipairs(ents) do
        if IsValidThreatEnemy(lantern, ent) then
            return true
        end
    end
    return false
end

local function HasThreatInZone(lantern, radius)
    local lx, ly, lz = lantern.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(lx, ly, lz, radius, THREAT_MUST_TAGS, THREAT_CANT_TAGS, THREAT_ONEOF_TAGS)
    for _, ent in ipairs(ents) do
        if IsEnemyThreateningProtected(lantern, ent) then
            return true
        end
    end
    return false
end

local function IsOwnerHitTargetActive(lantern, radius)
    local target = lantern._lanternbearer_ff_owner_hit_target
    if target == nil or not target:IsValid() then
        lantern._lanternbearer_ff_owner_hit_target = nil
        return false
    end

    if target.components == nil
        or target.components.health == nil
        or target.components.health:IsDead()
        or not IsInSpawnZone(lantern, target, radius) then
        lantern._lanternbearer_ff_owner_hit_target = nil
        return false
    end

    return true
end

local function DisarmSpawnGate(lantern)
    lantern._lanternbearer_ff_spawn_armed = false
    lantern._lanternbearer_ff_spawn_off_at = nil
    lantern._lanternbearer_ff_owner_hit_target = nil
end

local function UpdateSpawnGate(lantern)
    if lantern == nil or not lantern:IsValid() then
        return
    end

    if lantern._lanternbearer_owner_hit_listener == nil then
        HookOwnerCombat(lantern)
    end

    local radius = GetSpawnZoneRadius(lantern)
    if not HasEnemyInZone(lantern, radius) then
        DisarmSpawnGate(lantern)
        return
    end

    local threat_active = HasThreatInZone(lantern, radius)
    local owner_hit_active = IsOwnerHitTargetActive(lantern, radius)
    local combat_active = threat_active or owner_hit_active

    if combat_active then
        lantern._lanternbearer_ff_spawn_armed = true
        lantern._lanternbearer_ff_spawn_off_at = nil
        return
    end

    if lantern._lanternbearer_ff_spawn_armed ~= true then
        return
    end

    local delay = Profiles.LANTERNBEARER_SPAWN_GATE_OFF_DELAY or 2
    local off_at = lantern._lanternbearer_ff_spawn_off_at
    if off_at == nil then
        lantern._lanternbearer_ff_spawn_off_at = GetTime() + delay
    elseif GetTime() >= off_at then
        lantern._lanternbearer_ff_spawn_armed = false
        lantern._lanternbearer_ff_spawn_off_at = nil
        lantern._lanternbearer_ff_owner_hit_target = nil
    end
end

local function OnOwnerHitOther(lantern, _, data)
    if lantern == nil or not lantern:IsValid() or data == nil then
        return
    end

    local target = data.target
    local damage = data.damageresolved or data.damage or 0
    if target == nil
        or not target:IsValid()
        or damage == nil
        or damage <= 0
        or target.components == nil
        or target.components.health == nil
        or target.components.health:IsDead() then
        return
    end

    if not IsInSpawnZone(lantern, target, GetSpawnZoneRadius(lantern)) then
        return
    end

    lantern._lanternbearer_ff_owner_hit_target = target
    lantern._lanternbearer_ff_spawn_armed = true
    lantern._lanternbearer_ff_spawn_off_at = nil
end

local function HookOwnerCombat(lantern)
    local owner = FindWaxwellOwner(lantern)
    if owner == nil or not owner:IsValid() then
        return
    end

    if lantern._lanternbearer_owner_hit_listener == owner and lantern._lanternbearer_owner_hit_fn ~= nil then
        return
    end

    M.UnhookOwnerCombat(lantern)

    lantern._lanternbearer_owner_hit_fn = function(_, data)
        OnOwnerHitOther(lantern, _, data)
    end
    lantern._lanternbearer_owner_hit_listener = owner
    owner:ListenForEvent("onhitother", lantern._lanternbearer_owner_hit_fn)
end

function M.UnhookOwnerCombat(lantern)
    if lantern == nil then
        return
    end

    if lantern._lanternbearer_owner_hit_fn ~= nil and lantern._lanternbearer_owner_hit_listener ~= nil then
        lantern._lanternbearer_owner_hit_listener:RemoveEventCallback(
            "onhitother",
            lantern._lanternbearer_owner_hit_fn
        )
    end

    lantern._lanternbearer_owner_hit_fn = nil
    lantern._lanternbearer_owner_hit_listener = nil
end

function M.CanSpawnFireflies(lantern)
    return lantern ~= nil
        and lantern:IsValid()
        and lantern._lanternbearer_ff_spawn_armed == true
end

function M.Begin(lantern)
    if lantern == nil or not TheWorld.ismastersim then
        return
    end

    DisarmSpawnGate(lantern)
    HookOwnerCombat(lantern)

    if lantern._lanternbearer_ff_gate_task ~= nil then
        lantern._lanternbearer_ff_gate_task:Cancel()
    end

    local period = Profiles.LANTERNBEARER_SPAWN_GATE_CHECK_PERIOD or .5
    lantern._lanternbearer_ff_gate_task = lantern:DoPeriodicTask(period, UpdateSpawnGate)
    UpdateSpawnGate(lantern)
end

function M.End(lantern)
    if lantern == nil then
        return
    end

    if lantern._lanternbearer_ff_gate_task ~= nil then
        lantern._lanternbearer_ff_gate_task:Cancel()
        lantern._lanternbearer_ff_gate_task = nil
    end

    M.UnhookOwnerCombat(lantern)
    DisarmSpawnGate(lantern)
end

return M
