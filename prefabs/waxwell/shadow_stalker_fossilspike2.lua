local SpikeLogic = require("skill_effect/waxwell/emperor/shadow_stalker/spikes")

local SHADOW_TINT_ALPHA = .75
local NUM_VARIATIONS = 7
local PHYSICS_RADIUS = .2
local DAMAGE_RADIUS_PADDING = .5
local WHITELIST_PREFABS = { lureplant = true, eyeplant = true }
local SHADOW_SIZE = { 1.2, .75 }
local SHADOW_STALKER_SPIKE_DAMAGE = 24
local SHADOW_STALKER_SPIKE_PLANAR_DAMAGE = 6
local targeting_rules = require("skill_effect/_shared/targeting_rules")

local function ApplyShadowTint(inst)
    inst.AnimState:SetMultColour(0, 0, 0, SHADOW_TINT_ALPHA)
end

local function KeepTargetFn()
    return false
end

local function SpikeLaunch(inst, launcher, basespeed, startheight, startradius)
    local x0, y0, z0 = launcher.Transform:GetWorldPosition()
    local x1, y1, z1 = inst.Transform:GetWorldPosition()
    local dx, dz = x1 - x0, z1 - z0
    local dsq = dx * dx + dz * dz
    local angle
    if dsq > 0 then
        local dist = math.sqrt(dsq)
        angle = math.atan2(dz / dist, dx / dist) + (math.random() * 20 - 10) * DEGREES
    else
        angle = TWOPI * math.random()
    end
    local sina, cosa = math.sin(angle), math.cos(angle)
    local speed = basespeed + math.random()
    inst.Physics:Teleport(x0 + startradius * cosa, startheight, z0 + startradius * sina)
    inst.Physics:SetVel(cosa * speed, speed * 5 + math.random() * 2, sina * speed)
end

local COLLAPSIBLE_WORK_ACTIONS =
{
    CHOP = true,
    DIG = true,
    HAMMER = true,
    MINE = true,
}
local COLLAPSIBLE_TAGS = { "_combat", "pickable", "NPC_workable" }
for k, v in pairs(COLLAPSIBLE_WORK_ACTIONS) do
    table.insert(COLLAPSIBLE_TAGS, k.."_workable")
end
local NON_COLLAPSIBLE_TAGS = { "stalker", "shadow", "playerghost", "FX", "NOCLICK", "DECOR", "INLIMBO" }
local TOSSITEM_MUST_TAGS = { "_inventoryitem" }
local TOSSITEM_CANT_TAGS = { "locomotor", "INLIMBO" }

local function DoDamage(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local radius = PHYSICS_RADIUS + ((inst._damage_radius_padding_mult or 1) * DAMAGE_RADIUS_PADDING)
    local ents = TheSim:FindEntities(x, 0, z, radius, nil, NON_COLLAPSIBLE_TAGS, COLLAPSIBLE_TAGS)
    local hitset = {}
    for _, v in ipairs(ents) do
        if v:IsValid() then
            local isworkable = false
            if v.components.workable ~= nil then
                local work_action = v.components.workable:GetWorkAction()
                isworkable =
                    ((work_action == nil and v:HasTag("NPC_workable")) or
                    (v.components.workable:CanBeWorked() and work_action ~= nil and COLLAPSIBLE_WORK_ACTIONS[work_action.id]))
            end
            if isworkable then
                v.components.workable:Destroy(inst)
                if v:IsValid() and v:HasTag("stump") then
                    v:Remove()
                end
                hitset[v] = true
            elseif v.components.pickable ~= nil
                and v.components.pickable:CanBePicked()
                and not v:HasTag("intense") then
                v.components.pickable:Pick(inst)
                hitset[v] = true
            elseif v.components.combat ~= nil
                and v.components.health ~= nil
                and not v.components.health:IsDead() then
                if v.components.locomotor == nil and not inst:HasTag("epic") then
                    v.components.health:Kill()
                    hitset[v] = true
                elseif inst.components.combat:IsValidTarget(v) then
                    inst.components.combat:DoAttack(v)
                    hitset[v] = true
                end
            end
        end
    end

    local wents = TheSim:FindEntities(x, 0, z, radius)
    for _, v in ipairs(wents) do
        if targeting_rules.IsEntityAllowed(v,
        {
            name = "shadow_stalker_spike_whitelist",
            whitelist_prefabs = WHITELIST_PREFABS,
            extra_check = function(ent)
                return ent:IsValid() and not hitset[ent]
            end,
        }) then
            if v.components.health ~= nil and not v.components.health:IsDead() then
                if v.components.locomotor == nil and not inst:HasTag("epic") then
                    v.components.health:Kill()
                elseif inst.components.combat ~= nil and inst.components.combat:IsValidTarget(v) then
                    inst.components.combat:DoAttack(v)
                end
                hitset[v] = true
            end
        end
    end

    local totoss = TheSim:FindEntities(x, 0, z, radius, TOSSITEM_MUST_TAGS, TOSSITEM_CANT_TAGS)
    for _, v in ipairs(totoss) do
        if v.components.mine ~= nil then
            v.components.mine:Deactivate()
        end
        if not v.components.inventoryitem.nobounce and v.Physics ~= nil and v.Physics:IsActive() then
            SpikeLaunch(v, inst, .8 + PHYSICS_RADIUS, PHYSICS_RADIUS * .4, PHYSICS_RADIUS + v:GetPhysicsRadius(0))
        end
    end
end

local function OnKill(inst)
    inst:AddTag("NOCLICK")
    ErodeAway(inst, 1)
end

local function KillSpike(inst)
    if inst.killtask ~= nil then
        inst.killtask:Cancel()
        inst.killtask = nil
    end
    if not inst.killed then
        if inst.basefx ~= nil then
            inst.killed = true

            if inst.task ~= nil then
                inst.task:Cancel()
                inst.task = nil
            end

            SpawnPrefab("erode_ash").Transform:SetPosition(inst.Transform:GetWorldPosition())
            inst:DoTaskInTime(.5, OnKill)
        else
            inst:Remove()
        end
    end
end

local function OnImpact(inst)
    inst:RemoveEventCallback("animover", OnImpact)
    inst._ss_telegraph_phase = "done"
    inst.AnimState:PlayAnimation("impact")
    ApplyShadowTint(inst)

    if inst.lighttask ~= nil then
        inst.lighttask:Cancel()
        inst.lighttask = nil
    end
    inst.AnimState:SetLightOverride(0)

    if inst.shadowtask ~= nil then
        inst.shadowtask:Cancel()
        inst.shadowtask = nil
    end
    if inst.shadowtask2 ~= nil then
        inst.shadowtask2:Cancel()
        inst.shadowtask2 = nil
    end
    inst.DynamicShadow:Enable(false)

    inst.basefx = SpawnPrefab("shadow_stalker_fossilspike2_base")
    inst.basefx.entity:SetParent(inst.entity)

    if inst.soundlevel ~= nil then
        inst.SoundEmitter:PlaySoundWithParams("dontstarve/creatures/together/stalker/fossil_spike", { level = inst.soundlevel })
    else
        inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/fossil_spike")
    end

    DoDamage(inst)
    inst.killtask = inst:DoTaskInTime(.35, KillSpike)
end

local SHADOW_DELTA2 = -.2
local function UpdateShadow2(inst)
    if inst.shadowtask ~= nil then
        inst.shadowtask:Cancel()
        inst.shadowtask = nil
    end
    inst.shadowsize = inst.shadowsize + SHADOW_DELTA2
    local k = 1 - inst.shadowsize
    k = 1 - k * k
    if k <= .5 then
        k = .5
        if inst.shadowtask2 ~= nil then
            inst.shadowtask2:Cancel()
            inst.shadowtask2 = nil
        end
    end
    inst.DynamicShadow:SetSize(k * SHADOW_SIZE[1], k * SHADOW_SIZE[2])
end

local SHADOW_DELTA = .05
local function UpdateShadow(inst)
    inst.shadowsize = inst.shadowsize + SHADOW_DELTA
    if inst.shadowsize > 0 then
        inst.DynamicShadow:Enable(true)
        if inst.shadowsize >= 1 then
            inst.shadowsize = 1
            if inst.shadowtask ~= nil then
                inst.shadowtask:Cancel()
                inst.shadowtask = nil
            end
        end
    end
    local k = inst.shadowsize * inst.shadowsize
    inst.DynamicShadow:SetSize(k * SHADOW_SIZE[1], k * SHADOW_SIZE[2])
end

local LIGHT_DELTA = .03
local function UpdateLight(inst)
    inst.lightvalue = inst.lightvalue + LIGHT_DELTA
    if inst.lightvalue >= 1 then
        inst.lightvalue = 1
        if inst.lighttask ~= nil then
            inst.lighttask:Cancel()
            inst.lighttask = nil
        end
    end
    inst.AnimState:SetLightOverride(0)
end

local function StartAppearFx(inst)
    inst.shadowsize = 0
    if inst.shadowtask ~= nil then
        inst.shadowtask:Cancel()
    end
    if inst.shadowtask2 ~= nil then
        inst.shadowtask2:Cancel()
    end
    if inst.lighttask ~= nil then
        inst.lighttask:Cancel()
    end
    inst.shadowtask = inst:DoPeriodicTask(0, UpdateShadow)
    inst.shadowtask2 = inst:DoPeriodicTask(0, UpdateShadow2, 43 * FRAMES)
    inst.lightvalue = 0
    inst.lighttask = inst:DoPeriodicTask(0, UpdateLight)
end

local function OnAppearOver(inst)
    inst:RemoveEventCallback("animover", OnAppearOver)
    OnImpact(inst)
end

local function EnterTelegraphAppear(inst)
    if inst._ss_telegraph_phase == "telegraph" or inst._ss_telegraph_phase == "done" then
        return
    end

    inst._ss_telegraph_phase = "telegraph"

    local variation = inst._ss_variation or 1
    if variation > 1 then
        inst.AnimState:OverrideSymbol("bone1", "fossil_spike2", "bone"..tostring(variation))
    end

    inst.AnimState:PlayAnimation("appear")
    ApplyShadowTint(inst)
    StartAppearFx(inst)
    inst:ListenForEvent("animover", OnAppearOver)

    if inst.SoundEmitter ~= nil then
        inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/out", nil, 0.35)
    end
end

local function MoveTowardDesired(inst)
    local stalker = inst._ss_stalker
    if stalker == nil or not stalker:IsValid() then
        return false
    end

    local tx, ty, tz = SpikeLogic.GetDesiredWorldPosition(stalker, inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local dx, dy, dz = tx - x, ty - y, tz - z
    local dist_sq = dx * dx + dy * dy + dz * dz
    local arrive = SpikeLogic.ARRIVE_DIST
    if dist_sq <= arrive * arrive then
        inst.Transform:SetPosition(tx, ty, tz)
        return true
    end

    local dist = math.sqrt(dist_sq)
    local step = SpikeLogic.MOVE_SPEED * FRAMES
    if step >= dist then
        inst.Transform:SetPosition(tx, ty, tz)
        return true
    end

    local inv = 1 / dist
    inst.Transform:SetPosition(x + dx * inv * step, y + dy * inv * step, z + dz * inv * step)
    return false
end

local function CancelShadowStalkerTelegraph(inst)
    if inst._ss_move_task ~= nil then
        inst._ss_move_task:Cancel()
        inst._ss_move_task = nil
    end
    if inst.shadowtask ~= nil then
        inst.shadowtask:Cancel()
        inst.shadowtask = nil
    end
    if inst.shadowtask2 ~= nil then
        inst.shadowtask2:Cancel()
        inst.shadowtask2 = nil
    end
    if inst.lighttask ~= nil then
        inst.lighttask:Cancel()
        inst.lighttask = nil
    end
    inst:RemoveEventCallback("animover", OnAppearOver)
    inst:RemoveEventCallback("animover", OnImpact)
end

local function UpdateShadowStalkerTelegraph(inst)
    if inst._ss_telegraph_phase == "done" then
        return
    end

    local arrived = MoveTowardDesired(inst)
    if arrived and inst._ss_telegraph_phase == "travel" then
        EnterTelegraphAppear(inst)
    end
end

local function BeginShadowStalkerTelegraph(inst, config)
    CancelShadowStalkerTelegraph(inst)

    config = config or {}
    inst._ss_stalker = config.stalker
    inst._ss_variation = config.variation or math.random(NUM_VARIATIONS)
    inst._ss_telegraph_phase = "travel"
    inst.soundlevel = config.scale ~= nil and (config.scale / 1.5) or 1

    inst.AnimState:PlayAnimation("empty", false)
    ApplyShadowTint(inst)

    inst._ss_move_task = inst:DoPeriodicTask(0, UpdateShadowStalkerTelegraph)
    UpdateShadowStalkerTelegraph(inst)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddDynamicShadow()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("fossil_spike2")
    inst.AnimState:SetBuild("fossil_spike2")
    inst.AnimState:PlayAnimation("empty")
    inst.AnimState:SetFinalOffset(1)
    inst.AnimState:SetLightOverride(0)
    ApplyShadowTint(inst)

    inst.DynamicShadow:Enable(false)

    inst:AddTag("notarget")
    inst:AddTag("fossilspike")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("combat")
    inst.components.combat:SetDefaultDamage(SHADOW_STALKER_SPIKE_DAMAGE)
    inst.components.combat.playerdamagepercent = 0
    inst.components.combat:SetKeepTargetFunction(KeepTargetFn)

    inst:AddComponent("planardamage")
    inst.components.planardamage:SetBaseDamage(SHADOW_STALKER_SPIKE_PLANAR_DAMAGE)

    inst.persists = false

    inst.BeginShadowStalkerTelegraph = BeginShadowStalkerTelegraph
    inst.UpdateShadowStalkerTelegraph = UpdateShadowStalkerTelegraph
    inst.CancelShadowStalkerTelegraph = CancelShadowStalkerTelegraph
    inst.KillSpike = KillSpike

    return inst
end

local function basefn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("fossil_spike2")
    inst.AnimState:SetBuild("fossil_spike2")
    inst.AnimState:PlayAnimation("base_impact")
    inst.AnimState:SetLayer(LAYER_BACKGROUND)
    inst.AnimState:SetSortOrder(3)
    inst.AnimState:SetLightOverride(0)
    ApplyShadowTint(inst)

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false

    return inst
end

return Prefab("shadow_stalker_fossilspike2", fn),
    Prefab("shadow_stalker_fossilspike2_base", basefn)
