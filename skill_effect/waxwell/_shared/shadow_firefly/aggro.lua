local Profiles = require("skill_effect/waxwell/_shared/shadow_firefly/profiles")

local M = {}

local AGGRO_MUST_TAGS = { "_combat", "_health" }
local AGGRO_CANT_TAGS = { "INLIMBO", "playerghost", "companion" }
local AGGRO_ONEOF_TAGS = { "monster", "prey", "insect", "hostile", "character", "animal" }

local function IsValidBoundPlayer(player)
    return player ~= nil
        and player:IsValid()
        and player:HasTag("player")
        and not player:HasTag("playerghost")
        and player.entity:IsVisible()
end

local function GetBoundPlayer(host)
    if host == nil or not host:IsValid() then
        return nil
    end

    if host.GetTargetPlayer ~= nil then
        local player = host:GetTargetPlayer()
        if IsValidBoundPlayer(player) then
            return player
        end
    end

    local player = host._bound_target
    if IsValidBoundPlayer(player) then
        return player
    end

    if host._bound_target_userid ~= nil then
        for _, p in ipairs(AllPlayers) do
            if p ~= nil and p.userid == host._bound_target_userid then
                return p
            end
        end
    end

    return nil
end

local function ShouldRedirectAggro(ent, player, owner)
    local target = ent.components.combat.target
    return target == player
        or target == owner
        or (target == nil and ent.components.combat:CanTarget(player))
end

local function TryRedirectNearbyAggro(fly)
    if fly == nil
        or not fly:IsValid()
        or fly._shadow_firefly_dying
        or fly._shadow_firefly_fading then
        return
    end

    local host = fly._shadow_firefly_host
    local player = GetBoundPlayer(host)
    if not IsValidBoundPlayer(player) then
        return
    end

    local owner = fly._shadow_firefly_attacker
    if owner == nil and host ~= nil then
        owner = host._waxwell_owner
    end

    local fx, fy, fz = fly.Transform:GetWorldPosition()
    local range = Profiles.GetLanternbearerSearchRadius(host)
    local ents = TheSim:FindEntities(fx, fy, fz, range, AGGRO_MUST_TAGS, AGGRO_CANT_TAGS, AGGRO_ONEOF_TAGS)

    for _, ent in ipairs(ents) do
        if ent ~= fly
            and ent:IsValid()
            and ent.components.combat ~= nil
            and ent.components.health ~= nil
            and not ent.components.health:IsDead()
            and math.random() < Profiles.LANTERNBEARER_AGGRO_REDIRECT_CHANCE
            and ent.components.combat:CanTarget(fly)
            and ShouldRedirectAggro(ent, player, owner) then
            ent.components.combat:SetTarget(fly)
        end
    end
end

function M.Setup(inst)
    if inst == nil or not inst:IsValid() then
        return
    end

    if inst._shadow_firefly_aggro_task ~= nil then
        inst._shadow_firefly_aggro_task:Cancel()
    end
    inst._shadow_firefly_aggro_task = inst:DoPeriodicTask(
        Profiles.LANTERNBEARER_AGGRO_REDIRECT_PERIOD,
        TryRedirectNearbyAggro
    )
end

function M.Stop(inst)
    if inst == nil then
        return
    end

    if inst._shadow_firefly_aggro_task ~= nil then
        inst._shadow_firefly_aggro_task:Cancel()
        inst._shadow_firefly_aggro_task = nil
    end
end

return M
