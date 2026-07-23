require("stategraphs/commonstates")

local function DetachFX(fx)
    fx.Transform:SetPosition(fx.Transform:GetWorldPosition())
    fx.entity:SetParent(nil)
end

local function DoDespawnFX(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local fx1 = SpawnPrefab("shadow_despawn")
    local fx2 = SpawnPrefab("shadow_glob_fx")
    fx2.AnimState:SetScale(math.random() < .5 and -1.3 or 1.3, 1.3, 1.3)
    local platform = inst:GetCurrentPlatform()
    if platform ~= nil then
        fx1.entity:SetParent(platform.entity)
        fx2.entity:SetParent(platform.entity)
        fx1:ListenForEvent("onremove", function() DetachFX(fx1) end, platform)
        x, y, z = platform.entity:WorldToLocalSpace(x, y, z)
    end
    fx1.Transform:SetPosition(x, y, z)
    fx2.Transform:SetPosition(x, y, z)
end

local function TrySplashFX(inst, size)
    local x, y, z = inst.Transform:GetWorldPosition()
    if TheWorld.Map:IsOceanAtPoint(x, 0, z) then
        SpawnPrefab("ocean_splash_"..(size or "med")..tostring(math.random(2))).Transform:SetPosition(x, 0, z)
        return true
    end
end

local function TryStepSplash(inst)
    local t = GetTime()
    if (inst.sg.mem.laststepsplash == nil or inst.sg.mem.laststepsplash + .1 < t) and TrySplashFX(inst) then
        inst.sg.mem.laststepsplash = t
    end
end

local function DoSound(inst, sound)
    inst.SoundEmitter:PlaySound(sound)
end

local function SetHidden(inst, hidden)
    if hidden then
        inst:Hide()
        if inst.DynamicShadow ~= nil then
            inst.DynamicShadow:Enable(false)
        end
        if inst.Light ~= nil then
            inst.Light:Enable(false)
        end
    else
        inst:Show()
        if inst.DynamicShadow ~= nil then
            inst.DynamicShadow:Enable(true)
        end
        if inst.Light ~= nil then
            inst.Light:Enable(true)
        end
    end
end

local events =
{
    CommonHandlers.OnLocomote(true, false),
    CommonHandlers.OnDeath(),
    EventHandler("attacked", function(inst, data)
        if inst.components.health ~= nil and not inst.components.health:IsDead() and not inst.sg:HasStateTag("busy") then
            local blinkdata = inst.TryGetCombatBlinkData ~= nil and inst:TryGetCombatBlinkData(data ~= nil and data.attacker or nil) or nil
            if blinkdata ~= nil then
                inst.sg:GoToState("leader_blink", blinkdata)
            else
                inst.sg:GoToState("hit")
            end
        end
    end),
    EventHandler("dance", function(inst)
        if not inst.sg:HasStateTag("busy") and (inst._brain_dancedata ~= nil or not inst.sg:HasStateTag("dancing")) then
            inst.sg:GoToState("dance")
        end
    end),
}

local states =
{
    State{
        name = "spawn",
        tags = { "busy", "noattack", "temp_invincible" },

        onenter = function(inst, mult)
            inst.Physics:Stop()
            ToggleOffCharacterCollisions(inst)
            inst.AnimState:PlayAnimation("minion_spawn")
            mult = mult or (0.8 + math.random() * 0.2)
            inst.AnimState:SetDeltaTimeMultiplier(mult)

            mult = 1 / mult
            inst.sg.statemem.tasks =
            {
                inst:DoTaskInTime(0 * FRAMES * mult, DoSound, "maxwell_rework/shadow_worker/spawn"),
                inst:DoTaskInTime(0 * FRAMES * mult, TrySplashFX),
                inst:DoTaskInTime(20 * FRAMES * mult, TrySplashFX),
                inst:DoTaskInTime(44 * FRAMES * mult, TrySplashFX, "small"),
            }
            inst.sg:SetTimeout(70 * FRAMES * mult)
        end,

        ontimeout = function(inst)
            inst.sg:AddStateTag("caninterrupt")
            ToggleOnCharacterCollisions(inst)
            inst.AnimState:SetDeltaTimeMultiplier(1)
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },

        onexit = function(inst)
            ToggleOnCharacterCollisions(inst)
            inst.AnimState:SetDeltaTimeMultiplier(1)
            if inst.sg.statemem.tasks ~= nil then
                for _, task in ipairs(inst.sg.statemem.tasks) do
                    task:Cancel()
                end
            end
        end,
    },

    State{
        name = "quickspawn",

        onenter = function(inst)
            SpawnPrefab("statue_transition_2").Transform:SetPosition(inst.Transform:GetWorldPosition())
            inst.sg:GoToState("idle")
        end,
    },

    State{
        name = "quickdespawn",

        onenter = function(inst)
            DoDespawnFX(inst)
            if inst.sg.mem.laststepsplash ~= GetTime() then
                TrySplashFX(inst)
            end
            inst:Remove()
        end,
    },

    State{
        name = "leader_blink",
        tags = { "busy", "noattack", "temp_invincible", "blinking" },

        onenter = function(inst, data)
            inst.Physics:Stop()
            ToggleOffCharacterCollisions(inst)
            inst.AnimState:PlayAnimation("idle_loop", true)

            inst.sg.statemem.targetpos = data ~= nil and data.targetpos or nil
            local mult = data ~= nil and data.mult or nil
            local spendhealth = data ~= nil and data.spendhealth or false
            inst.sg.statemem.tasks =
            {
                inst:DoTaskInTime(0, DoDespawnFX),
                inst:DoTaskInTime(0, TrySplashFX),
                inst:DoTaskInTime(10 * FRAMES, function(inst)
                    SetHidden(inst, true)
                end),
                inst:DoTaskInTime(20 * FRAMES, function(inst)
                    local pt = inst.sg.statemem.targetpos
                    if spendhealth
                        and inst.components.health ~= nil
                        and not inst.components.health:IsDead() then
                        local now = GetTime()
                        local last = inst._shadow_lanternbearer_last_damage_time
                        if last ~= nil and now - last <= 1 then
                            -- Damage was already handled by the redirect (we applied -1);
                            -- clear the timestamp and skip applying another -1.
                            inst._shadow_lanternbearer_last_damage_time = nil
                        else
                            inst.components.health:DoDelta(-1, false, "shadow_lanternbearer_blink", true, inst, true)
                            if inst.components.health:IsDead() then
                                inst:PushEvent("seekoblivion")
                                return
                            end
                        end
                    end
                    if pt ~= nil then
                        inst.Transform:SetPosition(pt:Get())
                    end
                    SetHidden(inst, false)
                    inst.sg.statemem.blinked = true
                    inst.sg:GoToState("spawn", mult or 1.1)
                end),
            }
        end,

        onexit = function(inst)
            ToggleOnCharacterCollisions(inst)
            SetHidden(inst, false)
            if inst.sg.statemem.tasks ~= nil then
                for _, task in ipairs(inst.sg.statemem.tasks) do
                    task:Cancel()
                end
            end
        end,
    },

    State{
        name = "idle",
        tags = {"idle", "canrotate"},

        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("idle_loop", true)
        end,
    },

    State{
        name = "run_start",
        tags = {"moving", "running", "canrotate"},

        onenter = function(inst)
            inst.components.locomotor:RunForward()
            inst.AnimState:PlayAnimation("run_pre")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("run")
                end
            end),
        },

        timeline =
        {
            TimeEvent(1 * FRAMES, TryStepSplash),
            TimeEvent(3 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("dontstarve/maxwell/shadowmax_step")
            end),
        },
    },

    State{
        name = "run",
        tags = {"moving", "running", "canrotate"},

        onenter = function(inst)
            inst.components.locomotor:RunForward()
            if not inst.AnimState:IsCurrentAnimation("run_loop") then
                inst.AnimState:PlayAnimation("run_loop", true)
            end
            inst.sg:SetTimeout(inst.AnimState:GetCurrentAnimationLength())
        end,

        timeline =
        {
            TimeEvent(5 * FRAMES, TryStepSplash),
            TimeEvent(7 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("dontstarve/maxwell/shadowmax_step")
                inst.sg.mem.laststepsplash = GetTime()
            end),
            TimeEvent(13 * FRAMES, TryStepSplash),
            TimeEvent(15 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("dontstarve/maxwell/shadowmax_step")
                inst.sg.mem.laststepsplash = GetTime()
            end),
        },

        ontimeout = function(inst)
            inst.sg.statemem.running = true
            inst.sg:GoToState("run")
        end,

        onexit = function(inst)
            if not inst.sg.statemem.running then
                TryStepSplash(inst)
            end
        end,
    },

    State{
        name = "run_stop",
        tags = {"canrotate", "idle"},

        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("run_pst")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },
    },

    State{
        name = "hit",
        tags = {"hit", "busy"},

        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("hit")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },
    },

    State{
        name = "dance",
        tags = {"idle", "dancing"},

        onenter = function(inst)
            inst.Physics:Stop()

            local ignoreplay = inst.AnimState:IsCurrentAnimation("run_pst")
            if inst._brain_dancedata and #inst._brain_dancedata > 0 then
                for _, data in ipairs(inst._brain_dancedata) do
                    if ignoreplay then
                        inst.AnimState:PushAnimation(data.anim, data.loop)
                    else
                        inst.AnimState:PlayAnimation(data.anim, data.loop)
                        ignoreplay = true
                    end
                end
            else
                if ignoreplay then
                    inst.AnimState:PushAnimation("emoteXL_pre_dance0")
                else
                    inst.AnimState:PlayAnimation("emoteXL_pre_dance0")
                end
                inst.AnimState:PushAnimation("emoteXL_loop_dance0", true)
            end
            inst._brain_dancedata = nil
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() and not inst.AnimState:IsCurrentAnimation("emoteXL_loop_dance0") then
                    inst.AnimState:PushAnimation("emoteXL_loop_dance0", true)
                end
            end),
        },
    },
}

return StateGraph("SGshadow_lanternbearer", states, events, "spawn")
