require("stategraphs/commonstates")

local FeastBuffEffects = require("skill_effect/waxwell/emperor/shadow_stalker/feast_buff_effects")
local FeastLanternMC = require("skill_effect/waxwell/emperor/shadow_stalker/feast_lantern_mc")

local function ClearFeastBuffOnServer(inst)
    if TheWorld ~= nil and TheWorld.ismastersim and inst.ClearFeastBuff ~= nil then
        inst:ClearFeastBuff()
    end
end

local AREAATTACK_EXCLUDETAGS =
{
    "INLIMBO",
    "notarget",
    "invisible",
    "noattack",
    "flight",
    "player",
    "playerghost",
    "playercompanion",
    "companion",
    "shadow",
    "shadowchesspiece",
    "shadowcreature",
    "shadowminion",
    "stalkerminion",
    "chester",
    "glommer",
}

local function ShakeIfClose(inst)
    ShakeAllCameras(CAMERASHAKE.FULL, .5, .02, .2, inst, 30)
end

local function ShakeSummonRoar(inst)
    ShakeAllCameras(CAMERASHAKE.FULL, .7, .03, .4, inst, 30)
end

local function ShakeSummon(inst)
    ShakeAllCameras(CAMERASHAKE.VERTICAL, .5, .02, .2, inst, 30)
end

local function ShakePound(inst)
    ShakeAllCameras(CAMERASHAKE.VERTICAL, .5, .03, .7, inst, 30)
end

local function ShakeMindControl(inst)
    ShakeAllCameras(CAMERASHAKE.FULL, 2, .04, .075, inst, 30)
end

local MAIN_SHIELD_CD = 1.2
local function PickShield(inst)
    local t = GetTime()
    if (inst.sg.mem.lastshieldtime or 0) + .2 >= t then
        return
    end

    inst.sg.mem.lastshieldtime = t

    local dt = t - (inst.sg.mem.lastmainshield or 0)
    if dt >= MAIN_SHIELD_CD then
        inst.sg.mem.lastmainshield = t
        return math.random(3, 4)
    end

    local rnd = math.random()
    if rnd < dt / MAIN_SHIELD_CD then
        inst.sg.mem.lastmainshield = t
        return math.random(3, 4)
    end

    return rnd < dt / (MAIN_SHIELD_CD * 2) + .5 and 2 or 1
end

local function StartMindControlSound(inst)
    if inst.sg.mem.mindcontrolsoundtask ~= nil then
        inst.sg.mem.mindcontrolsoundtask:Cancel()
        inst.sg.mem.mindcontrolsoundtask = nil
        inst.SoundEmitter:KillSound("mindcontrol")
    end
    if not inst.SoundEmitter:PlayingSound("mindcontrol") then
        inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/mindcontrol_LP", "mindcontrol")
    end
end

local function OnMindControlSoundFaded(inst)
    inst.sg.mem.mindcontrolsoundtask = nil
    inst.SoundEmitter:KillSound("mindcontrol")
end

local function StopMindControlSound(inst)
    if inst.sg.mem.mindcontrolsoundtask == nil and inst.SoundEmitter:PlayingSound("mindcontrol") then
        inst.SoundEmitter:SetVolume("mindcontrol", 0)
        inst.sg.mem.mindcontrolsoundtask = inst:DoTaskInTime(10, OnMindControlSoundFaded)
    end
end

local function ApplyShadowTint(inst)
    inst.AnimState:SetMultColour(0, 0, 0, .75)
end

local function IsDead(inst)
    return inst.components.health ~= nil and inst.components.health:IsDead()
end

local function GoToDeath(inst)
    if not inst.sg:HasStateTag("dead") then
        inst.sg:GoToState(inst._force_despawn and "despawn" or "death")
    end
end

local function GoToIdleOrDeath(inst)
    if IsDead(inst) then
        GoToDeath(inst)
    else
        inst.sg:GoToState("idle")
    end
end

local function HideEatFx(inst)
    inst.AnimState:Hide("FX_EAT")
end

local function PrepareState(inst)
    ApplyShadowTint(inst)
    HideEatFx(inst)
    StopMindControlSound(inst)
end

local function PrepareMindControlState(inst)
    ApplyShadowTint(inst)
    HideEatFx(inst)
end

local function IsValidFeastTarget(inst, target)
    return target ~= nil
        and target:IsValid()
        and target.components.health ~= nil
        and not target.components.health:IsDead()
        and inst.IsInWorkArea ~= nil
        and inst:IsInWorkArea(target, target:GetPhysicsRadius(0))
end

local function CancelFeastState(inst)
    inst.components.locomotor:StopMoving()
    inst:ClearFeastSpeed()
    inst:CancelFeast()
    GoToIdleOrDeath(inst)
end

local function SpawnShieldFx(inst)
    if inst.hasshield then
        local shieldtype = PickShield(inst)
        if shieldtype ~= nil then
            local fx = SpawnPrefab("stalker_shield"..tostring(shieldtype))
            fx.entity:SetParent(inst.entity)
            if shieldtype < 3 and math.random() < .5 then
                fx.AnimState:SetScale(-2.36, 2.36, 2.36)
            end
        end
    end
end

local events =
{
    CommonHandlers.OnLocomote(false, true),
    EventHandler("shadowdespawn", function(inst)
        if not IsDead(inst) then
            inst.sg:GoToState("despawn")
        end
    end),
    EventHandler("doattack", function(inst)
        if not (inst.sg:HasStateTag("busy") or IsDead(inst)) then
            inst.sg:GoToState("attack")
        end
    end),
    EventHandler("fossilsnare", function(inst, data)
        if FeastBuffEffects.IsDuelistCrowdControlBlocked(inst) then
            return
        end
        if not (inst.sg:HasStateTag("busy") or IsDead(inst)) and data ~= nil and data.targets ~= nil and #data.targets > 0 then
            inst.sg:GoToState("snare", data.targets)
        end
    end),
    EventHandler("fossilspikes", function(inst)
        if not (inst.sg:HasStateTag("busy") or IsDead(inst)) then
            inst.sg:GoToState("spikes")
        end
    end),
    EventHandler("shadowchannelers", function(inst)
        if not (inst.sg:HasStateTag("busy") or IsDead(inst)) then
            inst.sg:GoToState("summon_channelers_pre")
        end
    end),
    EventHandler("fossilfeast", function(inst, data)
        if not (inst.sg:HasStateTag("busy") or IsDead(inst)) and data ~= nil and data.target ~= nil then
            inst.sg:GoToState("eat_chase", data.target)
        end
    end),
    EventHandler("mindcontrol", function(inst)
        if FeastBuffEffects.IsDuelistCrowdControlBlocked(inst) then
            return
        end
        if not (inst.sg:HasStateTag("busy") or IsDead(inst)) then
            if inst.IsAtWorkCenter ~= nil and not inst:IsAtWorkCenter() then
                inst.sg:GoToState("mindcontrol_reposition")
            else
                inst.sg:GoToState("mindcontrol_pre")
            end
        end
    end),
    EventHandler("attacked", function(inst)
        SpawnShieldFx(inst)
        if inst._force_despawn then
            inst.sg:GoToState("despawn")
        elseif inst.sg:HasStateTag("mc_reposition") then
            -- Take damage normally; keep walking toward work center.
            return
        elseif not (inst.sg:HasStateTag("busy") or IsDead(inst)) then
            inst.sg:GoToState("hit", inst.hasshield)
        end
    end),
    EventHandler("death", function(inst)
        if not inst.sg:HasStateTag("dead") then
            GoToDeath(inst)
        end
    end),
}

local states =
{
    State{
        name = "spawn",
        tags = { "busy", "canrotate", "nofreeze" },

        onenter = function(inst)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end

            inst.Physics:Stop()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("enter")
        end,

        timeline =
        {
            TimeEvent(0 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/in") end),
            TimeEvent(26 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/out") end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    if inst._shadow_stalker_spell_spawning then
                        inst._shadow_stalker_spell_spawning = nil
                        local leader = inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
                        if leader ~= nil and leader.components.waxwelljournal ~= nil then
                            local journal = leader.components.waxwelljournal.inst
                            if journal ~= nil and journal.components.spellbook ~= nil then
                                journal.components.spellbook:PushEvent("waxwell_shadow_stalker_spawned", { owner = leader })
                            end
                        end
                        if TheWorld ~= nil then
                            TheWorld:PushEvent("waxwell_emperor_spell_refresh", { owner = leader })
                        end
                    end
                    GoToIdleOrDeath(inst)
                end
            end),
        },
    },

    State{
        name = "idle",
        tags = { "idle", "canrotate" },

        onenter = function(inst)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            inst.Physics:Stop()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("idle")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    GoToIdleOrDeath(inst)
                end
            end),
        },
    },

    State{
        name = "walk_start",
        tags = { "moving", "canrotate" },

        onenter = function(inst)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            inst.components.locomotor:StopMoving()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("walk_pre")
        end,

        timeline =
        {
            TimeEvent(14 * FRAMES, function(inst)
                inst.components.locomotor:WalkForward()
            end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    if IsDead(inst) then
                        GoToDeath(inst)
                    else
                        inst.sg:GoToState("walk")
                    end
                end
            end),
        },
    },

    State{
        name = "walk",
        tags = { "moving", "canrotate" },

        onenter = function(inst)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            inst.components.locomotor:WalkForward()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("walk_loop", true)
            inst.sg:SetTimeout(inst.AnimState:GetCurrentAnimationLength())
        end,

        timeline =
        {
            TimeEvent(0 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/footstep") end),
            TimeEvent(15 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/footstep") end),
            TimeEvent(32 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/footstep") end),
        },

        ontimeout = function(inst)
            if IsDead(inst) then
                GoToDeath(inst)
            else
                inst.sg:GoToState("walk")
            end
        end,
    },

    State{
        name = "walk_stop",
        tags = { "canrotate" },

        onenter = function(inst)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            inst.components.locomotor:StopMoving()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("walk_pst")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    GoToIdleOrDeath(inst)
                end
            end),
        },
    },

    State{
        name = "attack",
        tags = { "attack", "busy" },

        onenter = function(inst)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            inst.components.locomotor:StopMoving()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("attack")
            inst.components.combat:StartAttack()
            inst.sg.statemem.target = inst.components.combat.target
            inst._targetlock_time = GetTime() + 1.5
            inst._targetlock_target = inst.sg.statemem.target
            inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/out")
        end,

        timeline =
        {
            TimeEvent(3 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/head") end),
            TimeEvent(13 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/attack_swipe") end),
            TimeEvent(32 * FRAMES, function(inst)
                if not IsDead(inst) then
                    inst.components.combat:DoAttack(inst.sg.statemem.target)
                end
            end),
            TimeEvent(47 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/head") end),
            TimeEvent(63 * FRAMES, function(inst)
                inst.sg:RemoveStateTag("busy")
            end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    GoToIdleOrDeath(inst)
                end
            end),
        },
    },

    State{
        name = "snare",
        tags = { "attack", "busy", "snare" },

        onenter = function(inst, targets)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            inst.components.locomotor:StopMoving()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("attack1")
            inst:StartAbility("snare")
            inst.sg.statemem.targets = targets
        end,

        timeline =
        {
            TimeEvent(0 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/attack1_pbaoe_pre") end),
            TimeEvent(24 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/attack1_pbaoe") end),
            TimeEvent(25.5 * FRAMES, function(inst)
                ShakePound(inst)
                inst.components.combat:DoAreaAttack(inst, 3.5, nil, nil, nil, AREAATTACK_EXCLUDETAGS)
                if inst.sg.statemem.targets ~= nil then
                    inst:SpawnSnares(inst.sg.statemem.targets)
                end
            end),
            TimeEvent(39 * FRAMES, function(inst)
                inst.sg:RemoveStateTag("busy")
            end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    GoToIdleOrDeath(inst)
                end
            end),
        },
    },

    State{
        name = "spikes",
        tags = { "attack", "busy", "spikes" },

        onenter = function(inst)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            inst.components.locomotor:StopMoving()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("spike")
            inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/attack1_pbaoe_pre")
            inst:StartAbility("spikes")
        end,

        timeline =
        {
            TimeEvent(6 * FRAMES, function(inst)
                inst:SpawnSpikes()
            end),
            TimeEvent(8 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/out") end),
            TimeEvent(12 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/in") end),
            TimeEvent(30 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/laugh")
            end),
            TimeEvent(48 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/taunt_short", nil, .6) end),
            TimeEvent(50 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/attack1_pbaoe") end),
            TimeEvent(51 * FRAMES, function(inst)
                ShakePound(inst)
                inst.components.combat:DoAreaAttack(inst, 3.5, nil, nil, nil, AREAATTACK_EXCLUDETAGS)
            end),
            TimeEvent(61 * FRAMES, function(inst)
                inst.sg:RemoveStateTag("busy")
            end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    GoToIdleOrDeath(inst)
                end
            end),
        },
    },

    State{
        name = "summon_channelers_pre",
        tags = { "busy", "summoning" },

        onenter = function(inst)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            inst.components.locomotor:StopMoving()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("taunt3_pre")
            inst.sg.statemem.count = 2
            inst:StartAbility("channelers")
        end,

        events =
        {
            EventHandler("attacked", function(inst)
                inst.sg.statemem.count = inst.sg.statemem.count - 1
            end),
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst:SpawnChannelers()
                    inst:BattleChatter("summon_channelers")
                    inst.sg:GoToState("summon_channelers_loop", inst.sg.statemem.count)
                end
            end),
        },
    },

    State{
        name = "summon_channelers_loop",
        tags = { "busy", "summoning" },

        onenter = function(inst, count)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            inst.components.locomotor:StopMoving()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("taunt3_loop")
            inst.sg.statemem.count = count or 0
        end,

        timeline =
        {
            TimeEvent(8 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/taunt_short") end),
            TimeEvent(11 * FRAMES, ShakeSummonRoar),
            TimeEvent(29 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/taunt_short") end),
            TimeEvent(34 * FRAMES, ShakeSummonRoar),
        },

        events =
        {
            EventHandler("attacked", function(inst)
                inst.sg.statemem.count = inst.sg.statemem.count - 1
            end),
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    if inst.sg.statemem.count > 1 then
                        inst.sg:GoToState("summon_channelers_loop", inst.sg.statemem.count - 1)
                    else
                        inst.sg:GoToState("summon_channelers_pst")
                    end
                end
            end),
        },
    },

    State{
        name = "summon_channelers_pst",
        tags = { "busy", "summoning" },

        onenter = function(inst)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            inst.components.locomotor:StopMoving()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("taunt3_pst")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    GoToIdleOrDeath(inst)
                end
            end),
        },
    },

    State{
        name = "eat_chase",
        tags = { "busy", "feasting", "moving", "canrotate" },

        onenter = function(inst, target)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            if not IsValidFeastTarget(inst, target) then
                CancelFeastState(inst)
                return
            end

            if inst:GetDistanceSqToInst(target) <= (2.4 + target:GetPhysicsRadius(0)) * (2.4 + target:GetPhysicsRadius(0)) then
                inst.sg:GoToState("eat_pre", target)
                return
            end

            PrepareState(inst)
            inst.sg.statemem.target = target
            inst.sg.statemem.lastdistsq = inst:GetDistanceSqToInst(target)
            inst.sg.statemem.stucktime = 0
            local x, _, z = inst.Transform:GetWorldPosition()
            inst.sg.statemem.lastx = x
            inst.sg.statemem.lastz = z
            inst:ApplyFeastSpeed()
            inst.AnimState:PlayAnimation("walk_loop", true)
            inst:ForceFacePoint(target.Transform:GetWorldPosition())
            inst.components.locomotor:RunForward()
            inst.sg:SetTimeout(2)
        end,

        onupdate = function(inst)
            local target = inst.sg.statemem.target
            if not IsValidFeastTarget(inst, target) then
                CancelFeastState(inst)
                return
            end

            inst.components.locomotor:GoToPoint(target:GetPosition())
            local distsq = inst:GetDistanceSqToInst(target)
            if distsq <= (2.4 + target:GetPhysicsRadius(0)) * (2.4 + target:GetPhysicsRadius(0)) then
                inst.sg:GoToState("eat_pre", target)
                return
            end

            inst:ForceFacePoint(target.Transform:GetWorldPosition())
            inst.components.locomotor:RunForward()

            local x, _, z = inst.Transform:GetWorldPosition()
            local dx = x - (inst.sg.statemem.lastx or x)
            local dz = z - (inst.sg.statemem.lastz or z)
            local movedsq = dx * dx + dz * dz

            if distsq >= (inst.sg.statemem.lastdistsq or distsq) - .04 and movedsq <= .0016 then
                inst.sg.statemem.stucktime = (inst.sg.statemem.stucktime or 0) + FRAMES
                if inst.sg.statemem.stucktime >= .5 then
                    CancelFeastState(inst)
                    return
                end
            else
                inst.sg.statemem.stucktime = 0
            end

            inst.sg.statemem.lastdistsq = distsq
            inst.sg.statemem.lastx = x
            inst.sg.statemem.lastz = z
        end,

        ontimeout = function(inst)
            CancelFeastState(inst)
        end,

        onexit = function(inst)
            inst.components.locomotor:StopMoving()
            inst:ClearFeastSpeed()
        end,
    },

    State{
        name = "eat_pre",
        tags = { "busy", "feasting" },

        onenter = function(inst, target)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            if not IsValidFeastTarget(inst, target) then
                CancelFeastState(inst)
                return
            end
            inst.components.locomotor:StopMoving()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("taunt2_pre")
            inst.sg.statemem.target = target
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("eat_loop", inst.sg.statemem.target)
                end
            end),
        },
    },

    State{
        name = "eat_loop",
        tags = { "busy", "feasting" },

        onenter = function(inst, target)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            if not IsValidFeastTarget(inst, target) then
                CancelFeastState(inst)
                return
            end
            inst.components.locomotor:StopMoving()
            PrepareState(inst)
            inst.sg.statemem.target = target
            inst.AnimState:PlayAnimation("taunt2_loop1")
        end,

        timeline =
        {
            TimeEvent(9 * FRAMES, function(inst)
                inst.sg.statemem.feast_ate = inst:EatMinions(inst.sg.statemem.target) > 0
                if inst.sg.statemem.feast_ate then
                    inst.AnimState:Show("FX_EAT")
                else
                    inst.AnimState:Hide("FX_EAT")
                end
                inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/taunt_short")
            end),
            TimeEvent(11.5 * FRAMES, ShakeIfClose),
            TimeEvent(21 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/out") end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    if inst.sg.statemem.feast_ate == false and inst.CancelFeast ~= nil then
                        inst:CancelFeast()
                    end
                    inst.sg:GoToState("eat_pst")
                end
            end),
        },
    },

    State{
        name = "eat_pst",
        tags = { "busy" },

        onenter = function(inst)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            inst.components.locomotor:StopMoving()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("taunt2_pst")
        end,

        timeline =
        {
            TimeEvent(8 * FRAMES, function(inst)
                inst.sg:RemoveStateTag("busy")
            end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    GoToIdleOrDeath(inst)
                end
            end),
        },
    },

    State{
        name = "mindcontrol_reposition",
        tags = { "busy", "mindcontrol", "mc_reposition", "moving", "canrotate" },

        onenter = function(inst)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end

            if inst.IsAtWorkCenter ~= nil and inst:IsAtWorkCenter() then
                inst.sg:GoToState("mindcontrol_pre")
                return
            end

            local center = inst.GetWorkCenter ~= nil and inst:GetWorkCenter() or nil
            if center == nil then
                inst.sg:GoToState("mindcontrol_pre")
                return
            end

            PrepareState(inst)
            inst.sg.statemem.center = center
            inst:ApplyMindControlRepositionSpeed()
            inst.AnimState:PlayAnimation("walk_loop", true)
            inst:ForceFacePoint(center.x, center.y, center.z)
            inst.components.locomotor:RunForward()
            inst.components.locomotor:GoToPoint(Vector3(center.x, 0, center.z))
        end,

        onupdate = function(inst)
            if inst.IsAtWorkCenter ~= nil and inst:IsAtWorkCenter() then
                inst.sg:GoToState("mindcontrol_pre")
                return
            end

            local center = inst.sg.statemem.center
            if center ~= nil then
                inst:ForceFacePoint(center.x, center.y, center.z)
                inst.components.locomotor:GoToPoint(Vector3(center.x, 0, center.z))
                inst.components.locomotor:RunForward()
            end
        end,

        onexit = function(inst)
            inst.components.locomotor:StopMoving()
            if inst.ClearMindControlRepositionSpeed ~= nil then
                inst:ClearMindControlRepositionSpeed()
            end
        end,
    },

    State{
        name = "mindcontrol_pre",
        tags = { "busy", "mindcontrol" },

        onenter = function(inst)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            inst.sg.mem.lantern_mc_upgrade = FeastBuffEffects.HasLanternMcUpgrade(inst)
            if inst.sg.mem.lantern_mc_upgrade then
                FeastBuffEffects.ClearImmediateLanternMcChain(inst)
                FeastLanternMC.BeginLanternFeastMindControl(inst)
            elseif FeastBuffEffects.WantsImmediateLanternMcChain(inst) then
                FeastBuffEffects.ClearImmediateLanternMcChain(inst)
            end
            inst.components.locomotor:StopMoving()
            PrepareMindControlState(inst)
            inst.AnimState:PlayAnimation("control_pre")
            inst.sg.statemem.count = 4
            inst:StartAbility("mindcontrol")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("mindcontrol_loop", inst.sg.statemem.count)
                end
            end),
        },
    },

    State{
        name = "mindcontrol_loop",
        tags = { "busy", "mindcontrol" },

        onenter = function(inst, count)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            inst.components.locomotor:StopMoving()
            PrepareMindControlState(inst)
            inst.AnimState:PlayAnimation("control_loop")
            StartMindControlSound(inst)
            inst.sg.statemem.count = inst:MindControl() > 0 and count or 0
            ShakeMindControl(inst)
        end,

        onupdate = function(inst)
            if inst:MindControl() <= 0 then
                inst.sg.statemem.count = 0
            end
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    if inst.sg.statemem.count > 1 then
                        inst.sg.statemem.continue = true
                        inst.sg:GoToState("mindcontrol_loop", inst.sg.statemem.count - 1)
                    else
                        inst.sg:GoToState("mindcontrol_pst")
                    end
                end
            end),
        },

        onexit = function(inst)
            if not inst.sg.statemem.continue then
                StopMindControlSound(inst)
                if FeastLanternMC.IsLanternMcSessionActive(inst) then
                    FeastLanternMC.EndLanternFeastMindControl(inst)
                end
            end
        end,
    },

    State{
        name = "mindcontrol_pst",
        tags = { "busy", "mindcontrol" },

        onenter = function(inst)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            if FeastLanternMC.IsLanternMcSessionActive(inst) then
                FeastLanternMC.EndLanternFeastMindControl(inst)
            end
            inst.sg.mem.lantern_mc_upgrade = nil
            inst.components.locomotor:StopMoving()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("control_pst")
        end,

        timeline =
        {
            TimeEvent(8 * FRAMES, function(inst)
                inst.sg:RemoveStateTag("busy")
            end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    GoToIdleOrDeath(inst)
                end
            end),
        },
    },

    State{
        name = "hit",
        tags = { "hit", "busy" },

        onenter = function(inst, shielded)
            if IsDead(inst) then
                GoToDeath(inst)
                return
            end
            inst.components.locomotor:StopMoving()
            PrepareState(inst)
            if shielded then
                inst.AnimState:PlayAnimation("shield")
                inst.sg:SetTimeout(18 * FRAMES)
            else
                inst.AnimState:PlayAnimation("hit")
                inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/hit")
                inst.sg:SetTimeout(16 * FRAMES)
            end
            CommonHandlers.UpdateHitRecoveryDelay(inst)
        end,

        ontimeout = function(inst)
            if not IsDead(inst) then
                if inst.sg.statemem.dosnare then
                    local targets = inst:FindSnareTargets()
                    if targets ~= nil then
                        inst.sg:GoToState("snare", targets)
                        return
                    end
                end
                if inst.sg.statemem.dospikes then
                    inst.sg:GoToState("spikes")
                    return
                elseif inst.sg.statemem.doattack then
                    inst.sg:GoToState("attack")
                    return
                end
            end
            inst.sg.statemem.doattack = nil
            inst.sg.statemem.dosnare = nil
            inst.sg.statemem.dospikes = nil
            inst.sg:RemoveStateTag("busy")
        end,

        events =
        {
            EventHandler("doattack", function(inst)
                inst.sg.statemem.doattack = true
            end),
            EventHandler("fossilsnare", function(inst)
                inst.sg.statemem.dosnare = true
            end),
            EventHandler("fossilspikes", function(inst)
                inst.sg.statemem.dospikes = true
            end),
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    if not IsDead(inst) then
                        if inst.sg.statemem.dosnare then
                            local targets = inst:FindSnareTargets()
                            if targets ~= nil then
                                inst.sg:GoToState("snare", targets)
                                return
                            end
                        end
                        if inst.sg.statemem.dospikes then
                            inst.sg:GoToState("spikes")
                            return
                        elseif inst.sg.statemem.doattack then
                            inst.sg:GoToState("attack")
                            return
                        end
                    end
                    GoToIdleOrDeath(inst)
                end
            end),
        },
    },

    State{
        name = "death",
        tags = { "busy", "dead" },

        onenter = function(inst)
            if inst.BeginShadowStalkerSpellDeactivate ~= nil then
                inst:BeginShadowStalkerSpellDeactivate()
            end
            inst._force_despawn = nil
            ClearFeastBuffOnServer(inst)
            inst.components.locomotor:StopMoving()
            PrepareState(inst)
            inst.AnimState:PlayAnimation("death")
            inst:AddTag("NOCLICK")
            inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death")
        end,

        timeline =
        {
            TimeEvent(15 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death_pop") end),
            TimeEvent(17 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death_pop") end),
            TimeEvent(21 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death_pop") end),
            TimeEvent(24 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death_pop") end),
            TimeEvent(27 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death_pop") end),
            TimeEvent(30 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death_pop")
                inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death_bone_drop")
            end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst:Remove()
                end
            end),
        },
    },

    State{
        name = "quickdespawn",

        onenter = function(inst)
            ClearFeastBuffOnServer(inst)
            local fx = SpawnPrefab("shadow_despawn")
            if fx ~= nil then
                fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
            end
            inst:Remove()
        end,
    },

    State{
        name = "despawn",
        tags = { "busy", "dead", "noattack", "notalking" },

        onenter = function(inst)
            if inst.BeginShadowStalkerSpellDeactivate ~= nil then
                inst:BeginShadowStalkerSpellDeactivate()
            end
            inst.components.locomotor:StopMoving()
            ClearFeastBuffOnServer(inst)
            if inst.components.combat ~= nil then
                inst.components.combat:SetTarget(nil)
                inst.components.combat:DropTarget()
            end
            if inst.components.health ~= nil and not inst.components.health:IsDead() then
                inst.components.health:SetInvincible(true)
                inst.components.health:Kill()
            end
            PrepareState(inst)
            inst.AnimState:PlayAnimation("death")
            inst:AddTag("NOCLICK")
            inst:AddTag("notarget")
            inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death")

            local fx = SpawnPrefab("shadow_despawn")
            if fx ~= nil then
                fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
            end
        end,

        timeline =
        {
            TimeEvent(15 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death_pop") end),
            TimeEvent(17 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death_pop") end),
            TimeEvent(21 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death_pop") end),
            TimeEvent(24 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death_pop") end),
            TimeEvent(27 * FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death_pop") end),
            TimeEvent(30 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death_pop")
                inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/death_bone_drop")
            end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst:Remove()
                end
            end),
        },
    },
}

return StateGraph("SGshadow_stalker", states, events, "idle")
