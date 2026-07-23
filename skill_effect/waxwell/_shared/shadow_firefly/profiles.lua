local M = {}

M.PROFILE_FEAST_MC = "feast_mc"
M.PROFILE_LANTERNBEARER_LV2 = "lanternbearer_lv2"

M.FIREFLY_MIN_SEP = 3.5
M.FIREFLY_PREFAB = "waxwell_shadow_firefly"

M.LANTERNBEARER_SPAWN_INTERVAL = 10
M.LANTERNBEARER_SPAWN_COUNT = 3
M.LANTERNBEARER_BURST_DURATION = .65
M.LANTERNBEARER_BURST_OFFSET = .35
M.LANTERNBEARER_SPAWN_ZONE_MULT = 1.25
M.LANTERNBEARER_SPAWN_GATE_OFF_DELAY = 2
M.LANTERNBEARER_SPAWN_GATE_CHECK_PERIOD = .5
M.LANTERNBEARER_LIFETIME = 3
M.LANTERNBEARER_WALK_SPEED = 5.25 -- base 3.5 × 1.5
M.LANTERNBEARER_HUNT_RADIUS_MULT = 1.5
M.LANTERNBEARER_AGGRO_REDIRECT_PERIOD = 0.5
M.LANTERNBEARER_AGGRO_REDIRECT_CHANCE = 0.5
M.LANTERNBEARER_EXPLOSION_DAMAGE = 12
M.LANTERNBEARER_EXPLOSION_SCALE = 1.35
M.LANTERNBEARER_EXPLOSION_RADIUS = M.LANTERNBEARER_EXPLOSION_SCALE * 1.5
M.LANTERNBEARER_EXPLOSION_AGGRO_REDIRECT_CHANCE = 0.33
M.FIREFLY_VISUAL_Y_OFFSET = 1.25

M.FEAST_MC_SPAWN_DURATION = 3.5
M.FEAST_MC_COUNT_LV1 = 6
M.FEAST_MC_COUNT_LV2 = 12

M.PROFILES = {
    [M.PROFILE_FEAST_MC] = {
        id = M.PROFILE_FEAST_MC,
        tag = "waxwell_shadow_firefly_feast_mc",
        explode_on_death = false,
        explode_on_expire = false,
        lifetime = nil,
        hunt_enemies = false,
    },
    [M.PROFILE_LANTERNBEARER_LV2] = {
        id = M.PROFILE_LANTERNBEARER_LV2,
        tag = "waxwell_shadow_firefly_lanternbearer",
        explode_on_death = true,
        explode_on_expire = true,
        lifetime = M.LANTERNBEARER_LIFETIME,
        walk_speed = M.LANTERNBEARER_WALK_SPEED,
        hunt_enemies = true,
        explosion_damage = M.LANTERNBEARER_EXPLOSION_DAMAGE,
        explosion_scale = M.LANTERNBEARER_EXPLOSION_SCALE,
        explosion_radius = M.LANTERNBEARER_EXPLOSION_RADIUS,
        explosion_aggro_redirect_chance = M.LANTERNBEARER_EXPLOSION_AGGRO_REDIRECT_CHANCE,
    },
}

function M.GetProfile(profile_id)
    return profile_id ~= nil and M.PROFILES[profile_id] or nil
end

function M.GetLanternbearerSearchRadius(host)
    local base = 5.25
    if host ~= nil and host:IsValid() and host.Light ~= nil then
        base = host.Light:GetRadius()
    end
    return base * M.LANTERNBEARER_HUNT_RADIUS_MULT
end

return M
