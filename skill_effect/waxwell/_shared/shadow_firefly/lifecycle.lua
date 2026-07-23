local Profiles = require("skill_effect/waxwell/_shared/shadow_firefly/profiles")
local Explosion = require("skill_effect/waxwell/_shared/shadow_firefly/explosion")
local Movement = require("skill_effect/waxwell/_shared/shadow_firefly/movement")
local Aggro = require("skill_effect/waxwell/_shared/shadow_firefly/aggro")

local M = {}

local HOST_WATCH_PERIOD = 1

local function SetupPassThroughPhysics(inst)
    if inst.Physics == nil then
        MakeGhostPhysics(inst, 0, 0)
    end
    inst.Physics:SetMass(0)
    inst.Physics:ClearCollisionMask()
    inst.Physics:SetActive(true)
    inst.Physics:Stop()
end

local function PlayShadowDespawnFx(inst)
    local fx = SpawnPrefab("shadow_despawn")
    if fx ~= nil then
        local x, y, z = inst.Transform:GetWorldPosition()
        fx.Transform:SetPosition(x, y, z)
    end
end

local function CancelFireflyTasks(inst)
    if inst._shadow_firefly_lifetime_task ~= nil then
        inst._shadow_firefly_lifetime_task:Cancel()
        inst._shadow_firefly_lifetime_task = nil
    end
    if inst._shadow_firefly_lifetime_world_task ~= nil then
        inst._shadow_firefly_lifetime_world_task:Cancel()
        inst._shadow_firefly_lifetime_world_task = nil
    end
    if inst._shadow_firefly_fade_safety_task ~= nil then
        inst._shadow_firefly_fade_safety_task:Cancel()
        inst._shadow_firefly_fade_safety_task = nil
    end
    if inst._shadow_firefly_host_watch_task ~= nil then
        inst._shadow_firefly_host_watch_task:Cancel()
        inst._shadow_firefly_host_watch_task = nil
    end
    Movement.Stop(inst)
    Aggro.Stop(inst)
end

local function DoProfileExplosion(inst)
    local profile = Profiles.GetProfile(inst._shadow_firefly_profile)
    if profile == nil or profile.explosion_damage == nil then
        return false
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    local aggro_opts = nil
    if profile.explosion_aggro_redirect_chance ~= nil and profile.explosion_aggro_redirect_chance > 0 then
        aggro_opts = {
            chance = profile.explosion_aggro_redirect_chance,
            host = inst._shadow_firefly_host,
            fallback = inst._shadow_firefly_attacker,
        }
    end

    Explosion.DoExplosion(
        x, y, z,
        inst._shadow_firefly_attacker,
        profile.explosion_scale,
        profile.explosion_radius,
        profile.explosion_damage,
        aggro_opts
    )
    return true
end

local function FinishRemove(inst, play_despawn_fx)
    if inst.Light ~= nil then
        inst.Light:Enable(false)
    end
    inst:Hide()

    if play_despawn_fx then
        PlayShadowDespawnFx(inst)
    end
    inst:Remove()
end

function M.FadeOutAndRemove(inst)
    if inst._shadow_firefly_dying or inst._shadow_firefly_fading then
        return
    end

    inst._shadow_firefly_fading = true
    inst:AddTag("NOCLICK")
    inst:AddTag("notarget")

    CancelFireflyTasks(inst)

    if inst.AnimState ~= nil then
        inst.AnimState:PlayAnimation("swarm_pst")
        local anim_len = inst.AnimState:GetCurrentAnimationLength() + FRAMES
        inst:DoTaskInTime(anim_len, inst.Remove)
        inst._shadow_firefly_fade_safety_task = inst:DoTaskInTime(math.max(anim_len, 0) + 2, function()
            if inst ~= nil and inst:IsValid() then
                inst:Remove()
            end
        end)
    else
        PlayShadowDespawnFx(inst)
        inst:Remove()
    end
end

function M.ForceDespawn(inst)
    if inst == nil or not inst:IsValid() or inst._shadow_firefly_dying then
        return
    end

    M.FadeOutAndRemove(inst)
end

function M.ExpireAndExplode(inst)
    if inst == nil or not inst:IsValid() or inst._shadow_firefly_dying then
        return
    end

    inst._shadow_firefly_dying = true
    inst._shadow_firefly_fading = false
    inst:AddTag("NOCLICK")
    inst:AddTag("notarget")
    inst.persists = false

    CancelFireflyTasks(inst)

    local profile = Profiles.GetProfile(inst._shadow_firefly_profile)
    local exploded = profile ~= nil and profile.explode_on_expire
    if exploded then
        DoProfileExplosion(inst)
    end

    FinishRemove(inst, false)
end

local function OnFireflyKilled(inst)
    if inst._shadow_firefly_dying then
        return
    end

    inst._shadow_firefly_dying = true
    inst:AddTag("NOCLICK")
    inst:AddTag("notarget")
    inst.persists = false

    CancelFireflyTasks(inst)

    local profile = Profiles.GetProfile(inst._shadow_firefly_profile)
    local exploded = profile ~= nil
        and profile.explode_on_death
        and inst._shadow_firefly_killed_by_combat
        and not inst._shadow_firefly_fading
    if exploded then
        DoProfileExplosion(inst)
    end

    FinishRemove(inst, not exploded)
end

local function OnAttacked(inst)
    inst._shadow_firefly_killed_by_combat = true
end

local function WatchHost(inst)
    local host = inst._shadow_firefly_host
    if host == nil or not host:IsValid() then
        M.ForceDespawn(inst)
    end
end

function M.Configure(inst, opts)
    if inst == nil or opts == nil then
        return
    end

    local profile = Profiles.GetProfile(opts.profile)
    if profile == nil then
        return
    end

    inst._shadow_firefly_profile = profile.id
    inst._shadow_firefly_host = opts.host
    inst._shadow_firefly_attacker = opts.attacker
    inst._shadow_firefly_killed_by_combat = false
    inst._shadow_firefly_fading = false
    inst._shadow_firefly_dying = false

    inst:AddTag(profile.tag)

    if not TheWorld.ismastersim then
        return
    end

    inst.entity:SetCanSleep(false)

    SetupPassThroughPhysics(inst)

    inst._shadow_firefly_host_watch_task = inst:DoPeriodicTask(HOST_WATCH_PERIOD, WatchHost)

    if profile.lifetime ~= nil and profile.lifetime > 0 then
        local lifetime = profile.lifetime
        inst._shadow_firefly_lifetime_task = inst:DoTaskInTime(lifetime, function()
            M.ExpireAndExplode(inst)
        end)
        -- Backup: inst tasks pause while asleep; world task still fires.
        inst._shadow_firefly_lifetime_world_task = TheWorld:DoTaskInTime(lifetime + 0.25, function()
            if inst ~= nil and inst:IsValid() and not inst._shadow_firefly_dying then
                M.ExpireAndExplode(inst)
            end
        end)
    end

    if profile.hunt_enemies then
        Movement.Setup(inst)
        if opts.burst_dir ~= nil then
            Movement.BeginBurstScatter(
                inst,
                opts.burst_dir.x,
                opts.burst_dir.z,
                opts.burst_duration
            )
        end
        Aggro.Setup(inst)
    end

    if inst._shadow_firefly_death_fn == nil then
        inst._shadow_firefly_death_fn = function()
            OnFireflyKilled(inst)
        end
        inst:ListenForEvent("death", inst._shadow_firefly_death_fn)
    end

    if inst._shadow_firefly_attacked_fn == nil then
        inst._shadow_firefly_attacked_fn = function()
            OnAttacked(inst)
        end
        inst:ListenForEvent("attacked", inst._shadow_firefly_attacked_fn)
    end
end

M.OnFireflyKilled = OnFireflyKilled

return M
