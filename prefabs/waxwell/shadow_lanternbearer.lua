local brain = require("brains/waxwell/shadow_lanternbearerbrain")
require("stategraphs/waxwell/SGshadow_lanternbearer")
local LanternFireflies = require("skill_effect/waxwell/puppeteer/shadow_lanternbearer/fireflies")

local assets =
{
    Asset("ANIM", "anim/swap_lantern.zip"),
}

local prefabs =
{
    "shadow_despawn",
    "shadow_glob_fx",
    "statue_transition_2",
    "ocean_splash_med1",
    "ocean_splash_med2",
    "ocean_splash_small1",
    "ocean_splash_small2",
}

local SHADOW_LANTERNBEARER_DURATION = TUNING.TOTAL_DAY_TIME / 2
local SHADOW_LANTERNBEARER_HEALTH = 5
local LIGHT_RADIUS = 5.25
local LIGHT_INTENSITY = .7
local LIGHT_FALLOFF = .8
local LIGHT_COLOUR = { 1, 244 / 255, 196 / 255 }
local LEADER_BLINK_MIN_DIST = 17.5
local LEADER_BLINK_COOLDOWN = 5
local LEADER_BLINK_CHECK_PERIOD = 1
local LEADER_BLINK_SPAWN_RADIUS = 2
local LEADER_BLINK_FAIL_DESPAWN_TIME = 5
local COMBAT_BLINK_MIN_RADIUS = 3.75
local COMBAT_BLINK_MAX_RADIUS = 6
local COMBAT_BLINK_MIN_MOVE_DIST = 4
local COMBAT_BLINK_MIN_ATTACKER_DIST = 4.5
local COMBAT_BLINK_MAX_OWNER_DIST = 12
local COMBAT_BLINK_OWNER_DIST_BUFFER = 2

local function DistSqXZ(ax, az, bx, bz)
    local dx = ax - bx
    local dz = az - bz
    return dx * dx + dz * dz
end

local function SaveSpawnPoint(inst, dont_overwrite)
    if not dont_overwrite or
        (
            inst.components.knownlocations:GetLocation("spawn") == nil and
            inst.components.knownlocations:GetLocation("spawnplatform") == nil
        )
    then
        local x, y, z = inst.Transform:GetWorldPosition()
        local platform = TheWorld.Map:GetPlatformAtPoint(x, z)
        if platform ~= nil then
            x, y, z = platform.entity:WorldToLocalSpace(x, 0, z)
            inst.components.knownlocations:ForgetLocation("spawn")
            inst.components.knownlocations:RememberLocation("spawnplatform", Vector3(x, 0, z))
            inst.components.entitytracker:TrackEntity("spawnplatform", platform)
        else
            inst.components.entitytracker:ForgetEntity("spawnplatform")
            inst.components.knownlocations:ForgetLocation("spawnplatform")
            inst.components.knownlocations:RememberLocation("spawn", Vector3(x, 0, z))
        end
    end
end

local function GetSpawnPoint(inst)
    local pt = inst.components.knownlocations:GetLocation("spawn")
    if pt ~= nil then
        return pt
    end

    pt = inst.components.knownlocations:GetLocation("spawnplatform")
    if pt ~= nil then
        local platform = inst.components.entitytracker:GetEntity("spawnplatform")
        if platform ~= nil then
            local x, y, z = platform.entity:LocalToWorldSpace(pt:Get())
            return Vector3(x, 0, z)
        end
    end
end

local function MakeSpawnPointTracker(inst)
    inst:AddComponent("knownlocations")
    inst:AddComponent("entitytracker")
    inst.SaveSpawnPoint = SaveSpawnPoint
    inst.GetSpawnPoint = GetSpawnPoint
end

local function DoRemove(inst)
    inst:Remove()
end

local function OnStalkerConsumed(inst)
    if inst.sg ~= nil and not inst.sg:HasStateTag("busy") then
        inst.sg:GoToState("quickdespawn")
    else
        inst:DoTaskInTime(0, OnSeekOblivion)
    end
end

local function OnSeekOblivion(inst)
    if inst:IsAsleep() then
        DoRemove(inst)
        return
    end

    inst.components.timer:StopTimer("obliviate")
    inst.sg:GoToState("quickdespawn")
end

local function IgnoreNonBlinkDamage(inst, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
    -- Always enforce single-point damage per hit for the lanternbearer.
    -- Strategy:
    -- 1) If the damage is the special blink-spend cause, allow it.
    -- 2) If the lanternbearer is actively in a blinking/invisible state, ignore other damage.
    -- 3) Otherwise, cancel the incoming damage and apply a controlled -1 HP instead.
    if amount ~= nil and amount < 0 and cause ~= "shadow_lanternbearer_blink" then
        if inst.sg ~= nil and inst.sg:HasStateTag("blinking") then
            return true
        end

        -- Record the time of this incoming hit so the leader_blink state doesn't double-apply
        -- the spend-health later. Apply the actual -1 damage on the next tick to avoid
        -- recursive DoDelta calls inside the redirect.
        inst._shadow_lanternbearer_last_damage_time = GetTime()
        inst:DoTaskInTime(0, function(inst)
            if inst.components ~= nil and inst.components.health ~= nil and not inst.components.health:IsDead() then
                if inst:IsValid() and inst.components.health ~= nil then
                    inst.components.health:DoDelta(-1, false, "shadow_lanternbearer_blink", true, afflicter, true)
                end
                if inst.components.health:IsDead() then
                    inst:PushEvent("seekoblivion")
                end
            end
        end)

        return true
    end
end

local function OnTimerDone(inst, data)
    if data ~= nil and data.name == "obliviate" then
        OnSeekOblivion(inst)
    end
end

local function OnEntitySleep(inst)
    if inst._obliviatetask == nil then
        inst._obliviatetask = inst:DoTaskInTime(TUNING.SHADOWWAXWELL_MINION_IDLE_DESPAWN_TIME, DoRemove)
    end
end

local function OnEntityWake(inst)
    if inst._obliviatetask ~= nil then
        inst._obliviatetask:Cancel()
        inst._obliviatetask = nil
    end
end

local function MakeOblivionSeeker(inst, duration)
    inst:ListenForEvent("timerdone", OnTimerDone)
    inst:AddComponent("timer")
    inst.components.timer:StartTimer("obliviate", duration)
    inst.OnEntitySleep = OnEntitySleep
    inst.OnEntityWake = OnEntityWake
end

local function IsValidTargetPlayer(player)
    return player ~= nil
        and player:IsValid()
        and player:HasTag("player")
        and not player:HasTag("playerghost")
        and player.entity:IsVisible()
end

local function IsBindableTargetPlayer(player)
    return player ~= nil
        and player:IsValid()
        and player:HasTag("player")
        and not player:HasTag("playerghost")
end

local function FindPlayerByUserID(userid)
    if userid == nil then
        return nil
    end

    for _, player in ipairs(AllPlayers) do
        if player ~= nil and player.userid == userid then
            return player
        end
    end
end

local function GetTargetPlayer(inst)
    if inst._bound_target ~= nil and inst._bound_target:IsValid() then
        return inst._bound_target
    end

    local player = FindPlayerByUserID(inst._bound_target_userid)
    if player ~= nil then
        inst._bound_target = player
        return player
    end
end

local function GetBoundLanternbearerForPlayer(player)
    if player == nil then
        return nil
    end

    local lanternbearer = player._waxwell_shadow_lanternbearer
    if lanternbearer ~= nil and lanternbearer:IsValid() then
        return lanternbearer
    end

    player._waxwell_shadow_lanternbearer = nil
    return nil
end

local function SetTargetPlayer(inst, player)
    local oldplayer = inst._bound_target
    if oldplayer == nil and inst._bound_target_userid ~= nil then
        oldplayer = FindPlayerByUserID(inst._bound_target_userid)
    end

    if oldplayer ~= nil and oldplayer ~= player and oldplayer._waxwell_shadow_lanternbearer == inst then
        oldplayer._waxwell_shadow_lanternbearer = nil
    end

    inst._bound_target = player
    inst._bound_target_userid = player ~= nil and player.userid or nil
    if inst._bound_target_userid_net ~= nil then
        inst._bound_target_userid_net:set(inst._bound_target_userid or "")
    end

    if player ~= nil then
        player._waxwell_shadow_lanternbearer = inst
    end
end

local function HasLanternbearerForPlayer(player, ignoreinst)
    if player == nil then
        return false
    end

    local cached = GetBoundLanternbearerForPlayer(player)
    if cached ~= nil then
        return cached ~= ignoreinst
    end

    local x, y, z = player.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(x, y, z, 30, { "shadow_lanternbearer" }, { "INLIMBO" })
    for _, ent in ipairs(ents) do
        if ent ~= ignoreinst
            and ent:IsValid()
            and ent._bound_target_userid ~= nil
            and ent._bound_target_userid == player.userid then
            player._waxwell_shadow_lanternbearer = ent
            return true
        elseif ent == ignoreinst
            and ent:IsValid()
            and ent._bound_target_userid ~= nil
            and ent._bound_target_userid == player.userid then
            player._waxwell_shadow_lanternbearer = ent
        end
    end

    return false
end

local function BindTargetPlayer(inst, player)
    if not IsValidTargetPlayer(player) or HasLanternbearerForPlayer(player, inst) then
        SetTargetPlayer(inst, nil)
        inst:DoTaskInTime(0, OnSeekOblivion)
        return false
    end

    SetTargetPlayer(inst, player)
    return true
end

local function SetOwner(inst, owner)
    inst._waxwell_owner = owner
    inst._waxwell_owner_userid = owner ~= nil and owner.userid or nil

    if inst.components.follower ~= nil then
        inst.components.follower:SetLeader(owner)
    end
end

local function GetOwner(inst)
    local owner = inst._waxwell_owner
    if owner == nil and inst._waxwell_owner_userid ~= nil then
        owner = FindPlayerByUserID(inst._waxwell_owner_userid)
        inst._waxwell_owner = owner
    end
    return owner
end

local NoHoles

local function MarkShadowLanternbearer2(inst)
    if inst ~= nil and not inst:HasTag("shadow_lanternbearer_2") then
        inst._waxwell_lanternbearer_lv2 = true
        inst:AddTag("shadow_lanternbearer_2")
        LanternFireflies.BeginLanternFireflies(inst)
    end
end

NoHoles = function(pt)
    return pt ~= nil and not TheWorld.Map:IsPointNearHole(pt)
end

local function IsVectorOffset(offset)
    -- Guard against non-vector returns (boolean/nil/etc) from FindWalkableOffset
    local t = type(offset)
    if offset == nil then
        return false
    end
    if (t == "table" or t == "userdata") and offset.x ~= nil and offset.z ~= nil then
        return true
    end
    return false
end

local function GetBlinkTargetPosition(inst, player)
    local playerpos = player ~= nil and player:GetPosition() or nil
    if playerpos == nil then
        return nil
    end

    local offset =
        FindWalkableOffset(playerpos, math.random() * TWOPI, LEADER_BLINK_SPAWN_RADIUS, 12, true, true, NoHoles, true, true)
        or FindWalkableOffset(playerpos, math.random() * TWOPI, LEADER_BLINK_SPAWN_RADIUS - .75, 12, true, true, NoHoles, true, true)
        or FindWalkableOffset(playerpos, math.random() * TWOPI, LEADER_BLINK_SPAWN_RADIUS + .75, 12, true, true, NoHoles, true, true)

    if IsVectorOffset(offset) then
        return playerpos + offset
    end

    return nil
end

local function GetCombatBlinkTargetPosition(inst, attacker)
    local player = inst:GetTargetPlayer()
    local playerpos = player ~= nil and player:GetPosition() or nil
    if playerpos == nil then
        return nil
    end

    local instpos = inst:GetPosition()
    local attackerpos = attacker ~= nil and attacker:IsValid() and attacker:GetPosition() or nil
    local owner = GetOwner(inst)
    local ownerpos = owner ~= nil and owner:IsValid() and owner:GetPosition() or nil
    local maxownerdistsq = nil
    if ownerpos ~= nil then
        local currentownerdist = math.sqrt(DistSqXZ(instpos.x, instpos.z, ownerpos.x, ownerpos.z))
        local maxownerdist = math.max(COMBAT_BLINK_MAX_OWNER_DIST, currentownerdist + COMBAT_BLINK_OWNER_DIST_BUFFER)
        maxownerdistsq = maxownerdist * maxownerdist
    end

    local function IsValidCombatBlinkOffset(offset)
        if not IsVectorOffset(offset) then
            return false
        end

        local px = playerpos.x + offset.x
        local pz = playerpos.z + offset.z
        if DistSqXZ(px, pz, instpos.x, instpos.z) < (COMBAT_BLINK_MIN_MOVE_DIST * COMBAT_BLINK_MIN_MOVE_DIST) then
            return false
        end

        if attackerpos ~= nil and DistSqXZ(px, pz, attackerpos.x, attackerpos.z) < (COMBAT_BLINK_MIN_ATTACKER_DIST * COMBAT_BLINK_MIN_ATTACKER_DIST) then
            return false
        end

        if ownerpos ~= nil and maxownerdistsq ~= nil and DistSqXZ(px, pz, ownerpos.x, ownerpos.z) > maxownerdistsq then
            return false
        end

        return true
    end

    local theta = attacker ~= nil and attacker:IsValid() and attacker:GetAngleToPoint(playerpos:Get()) * DEGREES or math.random() * TWOPI
    local behind = theta + PI

    local offsets =
    {
        FindWalkableOffset(playerpos, behind, COMBAT_BLINK_MAX_RADIUS, 8, true, true, NoHoles, true, true),
        FindWalkableOffset(playerpos, behind + 30 * DEGREES, (COMBAT_BLINK_MIN_RADIUS + COMBAT_BLINK_MAX_RADIUS) * .5, 8, true, true, NoHoles, true, true),
        FindWalkableOffset(playerpos, behind - 30 * DEGREES, (COMBAT_BLINK_MIN_RADIUS + COMBAT_BLINK_MAX_RADIUS) * .5, 8, true, true, NoHoles, true, true),
        FindWalkableOffset(playerpos, math.random() * TWOPI, COMBAT_BLINK_MAX_RADIUS, 12, true, true, NoHoles, true, true),
        FindWalkableOffset(playerpos, math.random() * TWOPI, COMBAT_BLINK_MIN_RADIUS, 12, true, true, NoHoles, true, true),
    }

    for _, offset in ipairs(offsets) do
        if IsValidCombatBlinkOffset(offset) then
            return Vector3(playerpos.x + offset.x, 0, playerpos.z + offset.z)
        end
    end

    return nil
end

local function ClearBlinkFailState(inst)
    inst._leader_blink_fail_start = nil
end

local function TryBlinkToTargetPlayer(inst)
    if inst.sg == nil
        or inst.sg:HasStateTag("busy")
        or inst.sg:HasStateTag("blinking")
        or inst.components.timer == nil
        or inst.components.timer:TimerExists("leader_blink_cd") then
        return
    end

    local player = inst:GetTargetPlayer()
    if not IsValidTargetPlayer(player) then
        ClearBlinkFailState(inst)
        return
    end

    if inst:GetDistanceSqToInst(player) < (LEADER_BLINK_MIN_DIST * LEADER_BLINK_MIN_DIST) then
        ClearBlinkFailState(inst)
        return
    end

    local pt = GetBlinkTargetPosition(inst, player)
    if pt == nil then
        if inst._leader_blink_fail_start == nil then
            inst._leader_blink_fail_start = GetTime()
        elseif GetTime() - inst._leader_blink_fail_start >= LEADER_BLINK_FAIL_DESPAWN_TIME then
            inst:PushEvent("seekoblivion")
        end
        return
    end

    ClearBlinkFailState(inst)
    inst.components.timer:StartTimer("leader_blink_cd", LEADER_BLINK_COOLDOWN)
    inst.sg:GoToState("leader_blink", { targetpos = pt })
end

local function ValidateBinding(inst)
    local player = inst:GetTargetPlayer()
    if not IsBindableTargetPlayer(player) or HasLanternbearerForPlayer(player, inst) then
        inst:PushEvent("seekoblivion")
    end
end

local function OnAttacked(inst, data)
    local attacker = data ~= nil and data.attacker or nil
    if attacker == nil or not attacker:IsValid() then
        return
    end

    local owner = inst._waxwell_owner
    if owner == nil and inst._waxwell_owner_userid ~= nil then
        owner = FindPlayerByUserID(inst._waxwell_owner_userid)
        inst._waxwell_owner = owner
    end

    if attacker == owner or attacker.userid == inst._bound_target_userid then
        inst:PushEvent("seekoblivion")
        return
    end

    -- If we're currently in the spawn animation, immediately interrupt it and blink away.
    if inst.sg ~= nil and inst.sg.currentstate ~= nil and inst.sg.currentstate.name == "spawn" then
        local pt = GetCombatBlinkTargetPosition(inst, attacker)
        if pt ~= nil and inst.components.timer ~= nil then
            inst.components.timer:StartTimer("leader_blink_cd", LEADER_BLINK_COOLDOWN)
            inst.sg:GoToState("leader_blink", { targetpos = pt, mult = 1.2, spendhealth = true })
        else
            local player = inst:GetTargetPlayer()
            if player ~= nil then
                local pt2 = GetBlinkTargetPosition(inst, player)
                if pt2 ~= nil and inst.components.timer ~= nil then
                    inst.components.timer:StartTimer("leader_blink_cd", LEADER_BLINK_COOLDOWN)
                    inst.sg:GoToState("leader_blink", { targetpos = pt2 })
                end
            end
        end

        -- Let damage resolve this tick; if we're dead, despawn.
        inst:DoTaskInTime(0, function(inst)
            if inst.components == nil or inst.components.health == nil then
                return
            end
            if inst.components.health:IsDead() then
                inst:PushEvent("seekoblivion")
            end
        end)

        return
    end
end

local function TryGetCombatBlinkData(inst, attacker)
    if attacker == nil or not attacker:IsValid() then
        return nil
    end

    local owner = GetOwner(inst)

    if attacker == owner or attacker.userid == inst._bound_target_userid then
        return nil
    end

    if inst.components.timer == nil
        or inst.sg == nil
        or inst.sg:HasStateTag("busy")
        or inst.sg:HasStateTag("blinking") then
        return nil
    end

    local pt = GetCombatBlinkTargetPosition(inst, attacker)
    if pt == nil then
        return nil
    end

    return { targetpos = pt, mult = 1.2, spendhealth = true }
end

local function OnDancingPlayerData(inst, data)
    if data == nil then
        return
    end

    local player = data.inst
    if player == nil or player ~= inst:GetTargetPlayer() then
        return
    end

    inst._brain_dancedata = data.dancedata
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddLight()
    inst.entity:AddNetwork()

    inst.Light:Enable(true)
    inst.Light:SetRadius(LIGHT_RADIUS)
    inst.Light:SetFalloff(LIGHT_FALLOFF)
    inst.Light:SetIntensity(LIGHT_INTENSITY)
    inst.Light:SetColour(unpack(LIGHT_COLOUR))

    inst:SetPhysicsRadiusOverride(.5)
    MakeGhostPhysics(inst, 1, inst.physicsradiusoverride)

    inst.Transform:SetFourFaced(inst)

    inst.AnimState:SetBank("wilson")
    inst.AnimState:SetBuild("waxwell")
    inst.AnimState:OverrideSymbol("fx_wipe", "wilson_fx", "fx_wipe")
    inst.AnimState:PlayAnimation("minion_spawn")
    inst.AnimState:SetMultColour(0, 0, 0, .5)
    inst.AnimState:UsePointFiltering(true)
    inst.AnimState:AddOverrideBuild("waxwell_minion_spawn")
    inst.AnimState:AddOverrideBuild("waxwell_minion_appear")
    inst.AnimState:OverrideSymbol("swap_object", "swap_lantern", "swap_lantern")
    inst.AnimState:OverrideSymbol("lantern_overlay", "swap_lantern", "lantern_overlay")
    inst.AnimState:Hide("ARM_normal")
    inst.AnimState:Show("lantern_overlay")
    inst.AnimState:Hide("HAT")
    inst.AnimState:Hide("HAIR_HAT")

    inst:AddTag("scarytoprey")
    inst:AddTag("shadowminion")
    inst:AddTag("shadow_lanternbearer")
    inst:AddTag("companion")
    inst:AddTag("NOBLOCK")

    inst._bound_target_userid_net = net_string(inst.GUID, "shadow_lanternbearer._bound_target_userid", "shadow_lanternbearer_targetuseriddirty")

    inst.SetTargetPlayer = BindTargetPlayer
    inst.GetTargetPlayer = GetTargetPlayer
    inst.SetWaxwellOwner = SetOwner
    inst.MarkShadowLanternbearer2 = MarkShadowLanternbearer2
    inst.TryGetCombatBlinkData = TryGetCombatBlinkData

    inst:SetPrefabNameOverride("shadowwaxwell")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("skinner")
    inst.components.skinner:SetupNonPlayerData()

    inst:AddComponent("locomotor")
    inst.components.locomotor.runspeed = TUNING.SHADOWWAXWELL_PROTECTOR_SPEED
    inst.components.locomotor:SetTriggersCreep(false)
    inst.components.locomotor.pathcaps = { ignorecreep = true }
    inst.components.locomotor:SetSlowMultiplier(.6)

    inst:AddComponent("health")
    inst.components.health:SetMaxHealth(SHADOW_LANTERNBEARER_HEALTH)
    inst.components.health.nofadeout = true
    inst.components.health.redirect = IgnoreNonBlinkDamage

    inst:AddComponent("combat")
    inst.components.combat.hiteffectsymbol = "torso"
    inst.components.combat:SetDefaultDamage(0)
    inst.components.combat:SetAttackPeriod(TUNING.SHADOWWAXWELL_PROTECTOR_ATTACK_PERIOD)
    inst.components.combat:SetRange(0)

    inst:AddComponent("follower")
    inst.components.follower.keepdeadleader = true
    inst.components.follower.keepleaderduringminigame = true
    inst.components.follower.noleashing = true

    MakeSpawnPointTracker(inst)
    MakeOblivionSeeker(inst, SHADOW_LANTERNBEARER_DURATION + math.random())

    inst:SetBrain(brain)
    inst:SetStateGraph("waxwell/SGshadow_lanternbearer")

    inst:ListenForEvent("attacked", OnAttacked)
    inst:ListenForEvent("seekoblivion", OnSeekOblivion)
    inst:ListenForEvent("stalkerconsumed", OnStalkerConsumed)
    inst:ListenForEvent("dancingplayerdata", function(world, data) OnDancingPlayerData(inst, data) end, TheWorld)
    inst:ListenForEvent("onremove", function(inst)
        LanternFireflies.EndLanternFireflies(inst)
        local player = inst._bound_target
        if player == nil and inst._bound_target_userid ~= nil then
            player = FindPlayerByUserID(inst._bound_target_userid)
        end
        if player ~= nil and player._waxwell_shadow_lanternbearer == inst then
            player._waxwell_shadow_lanternbearer = nil
        end
    end)

    inst._bindvalidationtask = inst:DoPeriodicTask(1, ValidateBinding)
    inst._leaderblinktask = inst:DoPeriodicTask(LEADER_BLINK_CHECK_PERIOD, TryBlinkToTargetPlayer)

    local old_OnSave = inst.OnSave
    inst.OnSave = function(inst, data)
        local refs = nil
        if old_OnSave ~= nil then
            refs = old_OnSave(inst, data)
        end

        if data ~= nil then
            data._waxwell_owner_userid = inst._waxwell_owner_userid
            data._bound_target_userid = inst._bound_target_userid
            data._waxwell_lanternbearer_lv2 = inst._waxwell_lanternbearer_lv2 or nil
        end

        return refs
    end

    local old_OnLoad = inst.OnLoad
    inst.OnLoad = function(inst, data)
        if old_OnLoad ~= nil then
            old_OnLoad(inst, data)
        end

        if data ~= nil then
            inst._waxwell_owner_userid = data._waxwell_owner_userid
            inst._bound_target_userid = data._bound_target_userid
            if data._waxwell_lanternbearer_lv2 then
                MarkShadowLanternbearer2(inst)
            end
        end

        inst:DoTaskInTime(0, function(inst)
            if inst._bound_target_userid ~= nil then
                local player = FindPlayerByUserID(inst._bound_target_userid)
                if player ~= nil then
                    BindTargetPlayer(inst, player)
                else
                    inst:PushEvent("seekoblivion")
                end
            end
        end)
    end

    return inst
end

return Prefab("shadow_lanternbearer", fn, assets, prefabs)
