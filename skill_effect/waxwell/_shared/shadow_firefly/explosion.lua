local Profiles = require("skill_effect/waxwell/_shared/shadow_firefly/profiles")

local M = {}

local EXPLOSION_EXCLUDE_TAGS = { "INLIMBO", "player", "companion", "wall", "structure", "abigail" }

local function IsExplosionVictim(ent, source)
    if ent == nil
        or not ent:IsValid()
        or ent == source
        or ent.components == nil
        or ent.components.health == nil
        or ent.components.health:IsDead()
        or ent:HasAnyTag("player", "companion", "abigail", "wall", "structure") then
        return false
    end

    if ent.components.follower ~= nil then
        local leader = ent.components.follower:GetLeader()
        if leader ~= nil and leader:HasTag("player") then
            return false
        end
    end

    return ent.components.combat ~= nil
end

local function ResolveExplosionAggroTarget(aggro_opts)
    if aggro_opts == nil then
        return nil
    end

    local host = aggro_opts.host
    if host ~= nil and host:IsValid() then
        return host
    end

    local fallback = aggro_opts.fallback
    if fallback ~= nil and fallback:IsValid() then
        return fallback
    end

    return nil
end

local function TryRedirectExplosionAggro(ent, aggro_opts)
    if aggro_opts == nil
        or aggro_opts.chance == nil
        or aggro_opts.chance <= 0
        or ent.components.combat == nil
        or math.random() >= aggro_opts.chance then
        return
    end

    local target = ResolveExplosionAggroTarget(aggro_opts)
    if target ~= nil and ent.components.combat:CanTarget(target) then
        ent.components.combat:SuggestTarget(target)
    end
end

function M.DoExplosion(x, y, z, attacker, scale, radius, damage, aggro_opts)
    if x == nil or y == nil or z == nil then
        return
    end

    scale = scale or 2
    radius = radius or (scale * 1.5)
    damage = damage or 12

    local fx = SpawnPrefab("waxwell_shadow_firefly_explodefx")
    if fx ~= nil then
        fx.Transform:SetPosition(x, y + Profiles.FIREFLY_VISUAL_Y_OFFSET, z)
        fx.Transform:SetScale(scale, scale, scale)
    end

    local ents = TheSim:FindEntities(x, y, z, radius, nil, EXPLOSION_EXCLUDE_TAGS)
    for _, ent in ipairs(ents) do
        if IsExplosionVictim(ent, nil) then
            ent.components.health:DoDelta(-damage, false, "waxwell_shadow_firefly_explode", false, attacker, true)
            TryRedirectExplosionAggro(ent, aggro_opts)
        end
    end
end

return M
