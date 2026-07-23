local assets =
{
    Asset("ANIM", "anim/fossil_spike.zip"),
}

local prefabs =
{
    "erode_ash",
    "shadow_stalker_fossilspike_base",
}

local NUM_VARIATIONS = 7
local PHYSICS_RADIUS = .2
local DAMAGE_RADIUS_PADDING = .5
local WHITELIST_PREFABS = { lureplant = true, eyeplant = true }
local SHADOW_TINT_ALPHA = .75
local BARRIER_SCAN_RADIUS = 1.2
local BARRIER_PUSH_INSET = .35
local SHADOW_STALKER_FOSSILSPIKE_DAMAGE = 8
local SHADOW_STALKER_FOSSILSPIKE_PLANAR_DAMAGE = 2
local targeting_rules = require("skill_effect/_shared/targeting_rules")

local function KeepTargetFn()
    return false
end

local function ApplyShadowTint(inst)
    inst.AnimState:SetMultColour(0, 0, 0, SHADOW_TINT_ALPHA)
end

local function ChangeToObstacle(inst)
    inst:RemoveEventCallback("animover", ChangeToObstacle)
    local x, y, z = inst.Transform:GetWorldPosition()
    inst.Physics:Stop()
    inst.Physics:SetMass(0)
    inst.Physics:SetCollisionMask(
        COLLISION.ITEMS,
        COLLISION.WORLD
    )
    inst.Physics:Teleport(x, 0, z)
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
local NON_COLLAPSIBLE_TAGS = { "stalker", "flying", "shadow", "ghost", "playerghost", "FX", "NOCLICK", "DECOR", "INLIMBO" }
local TOSSITEM_MUST_TAGS = { "_inventoryitem" }
local TOSSITEM_CANT_TAGS = { "locomotor", "INLIMBO" }
local BARRIER_MUST_TAGS = { "_health", "_combat", "locomotor" }
local BARRIER_CANT_TAGS =
{
    "INLIMBO",
    "player",
    "playerghost",
    "companion",
    "playercompanion",
    "chester",
    "glommer",
    "shadow",
    "shadowcreature",
    "shadowminion",
    "stalkerminion",
    "flying",
    "ghost",
}

local function IsBarrierTarget(inst, target)
    return targeting_rules.IsEntityAllowed(target,
    {
        name = "shadow_stalker_barrier",
        must_tags = BARRIER_MUST_TAGS,
        blacklist_tags = BARRIER_CANT_TAGS,
        extra_check = function(ent)
            return ent:IsValid()
                and ent.components.health ~= nil
                and not ent.components.health:IsDead()
                and ent.components.locomotor ~= nil
                and not ent:HasTag("largecreature")
                and not ent:HasTag("epic")
                and not ent:HasTag("smallepic")
                and (inst._owner == nil or not inst._owner:IsValid() or (inst._owner.IsValidEnemy ~= nil and inst._owner:IsValidEnemy(ent)))
        end,
    })
end

local function KeepMonstersInside(inst)
    if inst._snarecenter == nil or inst._snareradius == nil then
        return
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(x, y, z, BARRIER_SCAN_RADIUS, BARRIER_MUST_TAGS, BARRIER_CANT_TAGS)
    local maxradius = math.max(0, inst._snareradius - BARRIER_PUSH_INSET)
    local map = TheWorld.Map

    for _, target in ipairs(ents) do
        if IsBarrierTarget(inst, target) then
            local tx, ty, tz = target.Transform:GetWorldPosition()
            local dx = tx - inst._snarecenter.x
            local dz = tz - inst._snarecenter.z
            local distsq = dx * dx + dz * dz
            if distsq > maxradius * maxradius and distsq > 0 then
                local dist = math.sqrt(distsq)
                local nx = inst._snarecenter.x + dx / dist * maxradius
                local nz = inst._snarecenter.z + dz / dist * maxradius
                if map:IsPassableAtPoint(nx, 0, nz) and not map:IsPointNearHole(Vector3(nx, 0, nz)) then
                    if target.Physics ~= nil then
                        target.Physics:Teleport(nx, 0, nz)
                    else
                        target.Transform:SetPosition(nx, 0, nz)
                    end
                end
            end
        end
    end
end

local function DoDamage(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(x, 0, z, PHYSICS_RADIUS + DAMAGE_RADIUS_PADDING, nil, NON_COLLAPSIBLE_TAGS, COLLAPSIBLE_TAGS)
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

    -- ensure whitelist prefabs in range are also damaged even if filtered by tags
    local wents = TheSim:FindEntities(x, 0, z, PHYSICS_RADIUS + DAMAGE_RADIUS_PADDING)
    for _, v in ipairs(wents) do
        if targeting_rules.IsEntityAllowed(v,
        {
            name = "shadow_stalker_fossilspike_whitelist",
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

    local totoss = TheSim:FindEntities(x, 0, z, PHYSICS_RADIUS + DAMAGE_RADIUS_PADDING, TOSSITEM_MUST_TAGS, TOSSITEM_CANT_TAGS)
    for _, v in ipairs(totoss) do
        if v.components.mine ~= nil then
            v.components.mine:Deactivate()
        end
    end
end

local function OnKill2(inst)
    inst:AddTag("NOCLICK")
    inst.Physics:SetActive(false)
    ErodeAway(inst, 1)
end

local function OnKill(inst)
    SpawnPrefab("erode_ash").Transform:SetPosition(inst.Transform:GetWorldPosition())
    inst:DoTaskInTime(.5, OnKill2)
end

local function KillSpike(inst)
    if not inst.killed then
        if inst._barriertask ~= nil then
            inst._barriertask:Cancel()
            inst._barriertask = nil
        end

        if inst.basefx ~= nil then
            inst.killed = true

            if inst.task ~= nil then
                inst.task:Cancel()
                inst.task = nil
            end

            inst:RemoveEventCallback("animover", ChangeToObstacle)

            if inst.basefx:IsValid() then
                inst.basefx.AnimState:PlayAnimation("base_pst"..tostring(inst.basefx.variation))
                inst:DoTaskInTime(1, OnKill)
            else
                OnKill(inst)
            end
        else
            inst:Remove()
        end
    end
end

local function StartSpike(inst, duration, variation)
    inst.task = inst:DoTaskInTime(duration, KillSpike)

    if variation > 1 then
        inst.AnimState:OverrideSymbol("bone1", "fossil_spike", "bone"..tostring(variation))
    end

    inst.basefx = SpawnPrefab("shadow_stalker_fossilspike_base")
    inst.basefx.entity:SetParent(inst.entity)

    inst:ListenForEvent("animover", ChangeToObstacle)
    inst.AnimState:PlayAnimation("fossil_pst")
    ApplyShadowTint(inst)

    inst.SoundEmitter:PlaySound("dontstarve/creatures/together/stalker/fossil_spike")

    DoDamage(inst)

    if inst._barriertask == nil then
        inst._barriertask = inst:DoPeriodicTask(0.1, KeepMonstersInside)
    end
end

local function RestartSpike(inst, delay, duration, variation)
    if inst.task ~= nil then
        inst.task:Cancel()
        if variation == nil then
            variation = math.random(NUM_VARIATIONS)
        elseif variation > NUM_VARIATIONS then
            variation = (variation - 1) % NUM_VARIATIONS + 1
        end
        inst.task = inst:DoTaskInTime(delay or 0, StartSpike, duration, variation)
    end
end

local function SetSnareData(inst, owner, centerx, centerz, radius)
    inst._owner = owner
    inst._snarecenter = Vector3(centerx, 0, centerz)
    inst._snareradius = radius
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddPhysics()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("fossil_spike")
    inst.AnimState:SetBuild("fossil_spike")
    inst.AnimState:PlayAnimation("empty")
    inst.AnimState:SetFinalOffset(1)
    ApplyShadowTint(inst)

    inst.Physics:SetMass(99999)
    inst.Physics:SetCollisionGroup(COLLISION.SMALLOBSTACLES)
    inst.Physics:SetCollisionMask(
        COLLISION.ITEMS,
        COLLISION.WORLD
    )
    inst.Physics:SetCapsule(PHYSICS_RADIUS, 2)

    inst:AddTag("notarget")
    inst:AddTag("groundspike")
    inst:AddTag("fossilspike")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("combat")
    inst.components.combat:SetDefaultDamage(SHADOW_STALKER_FOSSILSPIKE_DAMAGE)
    inst.components.combat.playerdamagepercent = 0
    inst.components.combat:SetKeepTargetFunction(KeepTargetFn)

    inst:AddComponent("planardamage")
    inst.components.planardamage:SetBaseDamage(SHADOW_STALKER_FOSSILSPIKE_PLANAR_DAMAGE)

    inst.persists = false

    inst.task = inst:DoTaskInTime(0, StartSpike, 5 + math.random(), math.random(NUM_VARIATIONS))
    inst.RestartSpike = RestartSpike
    inst.KillSpike = KillSpike
    inst.SetSnareData = SetSnareData

    return inst
end

local function basefn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    inst.AnimState:SetBank("fossil_spike")
    inst.AnimState:SetBuild("fossil_spike")
    inst.AnimState:PlayAnimation("base_pre1")
    inst.AnimState:SetLayer(LAYER_BACKGROUND)
    inst.AnimState:SetSortOrder(3)
    ApplyShadowTint(inst)

    inst:AddTag("FX")
    inst:AddTag("NOCLICK")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.persists = false

    inst.variation = math.random(3)
    if inst.variation > 1 then
        inst.AnimState:PlayAnimation("base_pre"..tostring(inst.variation))
    end

    return inst
end

return Prefab("shadow_stalker_fossilspike", fn, assets, prefabs),
    Prefab("shadow_stalker_fossilspike_base", basefn, assets)
