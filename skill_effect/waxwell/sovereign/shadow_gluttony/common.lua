local V = require("skill_effect/waxwell/sovereign/shadow_gluttony/variables")

local function IsShadowGluttonyActive(inst)
    if inst == nil or inst.prefab ~= "waxwell" then
        return false
    end

    if inst:HasTag("shadow_gluttony_active") then
        return true
    end

    return TheWorld.ismastersim
        and inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_shadow_gluttony")
end

local function IsShadowGluttonyFood(food)
    return food ~= nil
        and food.components ~= nil
        and food.components.edible ~= nil
        and food.components.edible.foodtype == V.SHADOW_GLUTTONY_FOODTYPE
end

local function RemoveArrayValue(tbl, value)
    if tbl == nil then
        return
    end

    for i = #tbl, 1, -1 do
        if tbl[i] == value then
            table.remove(tbl, i)
        end
    end
end

local function SetShadowGluttonyCanEat(inst, caneat)
    local eater = inst ~= nil and inst.components ~= nil and inst.components.eater or nil
    if eater == nil then
        return
    end

    local tag = V.SHADOW_GLUTTONY_FOODTYPE.."_eater"
    local hasentry = false
    for _, foodtype in ipairs(eater.caneat) do
        if foodtype == V.SHADOW_GLUTTONY_FOODTYPE then
            hasentry = true
            break
        end
    end

    if caneat then
        if not hasentry then
            table.insert(eater.caneat, V.SHADOW_GLUTTONY_FOODTYPE)
            table.insert(eater.preferseating, V.SHADOW_GLUTTONY_FOODTYPE)
        end
        if not inst:HasTag(tag) then
            inst:AddTag(tag)
        end
    else
        if hasentry then
            RemoveArrayValue(eater.caneat, V.SHADOW_GLUTTONY_FOODTYPE)
            RemoveArrayValue(eater.preferseating, V.SHADOW_GLUTTONY_FOODTYPE)
        end
        if inst:HasTag(tag) then
            inst:RemoveTag(tag)
        end
    end
end

-- Nightmare Fuel / Pure Horror grant sanity over 5s (stackable pool).
local function GetShadowGluttonyTickCount()
    return math.max(1, math.floor((V.SHADOW_GLUTTONY_REGEN_DURATION / V.SHADOW_GLUTTONY_REGEN_TICK) + 0.0001))
end

local function StopShadowGluttonyRegen(inst)
    local state = inst ~= nil and inst._waxwell_shadow_gluttony_regen or nil
    if state == nil then
        return
    end

    if state.task ~= nil then
        state.task:Cancel()
        state.task = nil
    end

    inst._waxwell_shadow_gluttony_regen = nil
end

local function TickShadowGluttonyRegen(inst)
    local state = inst ~= nil and inst._waxwell_shadow_gluttony_regen or nil
    if state == nil or not inst:IsValid() or inst.components == nil or inst.components.sanity == nil then
        StopShadowGluttonyRegen(inst)
        return
    end

    local ticks_left = state.ticks_left or 0
    local pending = state.pending or 0
    if ticks_left <= 0 or pending <= 0 then
        if pending > 0 then
            inst.components.sanity:DoDelta(pending)
        end
        StopShadowGluttonyRegen(inst)
        return
    end

    local heal = pending / ticks_left
    state.pending = pending - heal
    state.ticks_left = ticks_left - 1
    if heal > 0 then
        inst.components.sanity:DoDelta(heal)
    end

    if state.ticks_left <= 0 or (state.pending or 0) <= 0 then
        if (state.pending or 0) > 0 then
            inst.components.sanity:DoDelta(state.pending)
        end
        StopShadowGluttonyRegen(inst)
    end
end

local function AddShadowGluttonySanity(inst, amount)
    if inst == nil or amount == nil or amount <= 0 or not IsShadowGluttonyActive(inst) then
        return
    end

    if inst.components == nil or inst.components.sanity == nil then
        return
    end

    local state = inst._waxwell_shadow_gluttony_regen
    if state == nil then
        state = { pending = 0 }
        inst._waxwell_shadow_gluttony_regen = state
    end

    state.pending = (state.pending or 0) + amount
    state.ticks_left = GetShadowGluttonyTickCount()

    if state.task == nil then
        state.task = inst:DoPeriodicTask(V.SHADOW_GLUTTONY_REGEN_TICK, function(i)
            TickShadowGluttonyRegen(i)
        end)
    end
end

local function OnShadowGluttonyItemEaten(item, eater)
    if eater == nil or eater.prefab ~= "waxwell" or not IsShadowGluttonyActive(eater) then
        return
    end

    if item ~= nil and item.prefab == "horrorfuel" then
        AddShadowGluttonySanity(eater, V.SHADOW_GLUTTONY_SANITY_PER_HORROR)
    else
        AddShadowGluttonySanity(eater, V.SHADOW_GLUTTONY_SANITY_PER_FUEL)
    end
end

local function RefreshShadowGluttonySkillState(inst)
    if inst == nil then
        return
    end

    SetShadowGluttonyCanEat(inst, IsShadowGluttonyActive(inst))
end

-- Redirect half of any positive HP heal from eating into sanity instead.
local function PatchShadowGluttonyEater(inst)
    local eater = inst ~= nil and inst.components ~= nil and inst.components.eater or nil
    if eater == nil or eater._waxwell_shadow_gluttony_patched then
        return
    end

    eater._waxwell_shadow_gluttony_patched = true

    local old_custom_stats_mod_fn = eater.custom_stats_mod_fn
    eater.custom_stats_mod_fn = function(owner, health_delta, hunger_delta, sanity_delta, food, feeder)
        if old_custom_stats_mod_fn ~= nil then
            health_delta, hunger_delta, sanity_delta =
                old_custom_stats_mod_fn(owner, health_delta, hunger_delta, sanity_delta, food, feeder)
        end

        if health_delta ~= nil and health_delta > 0 and IsShadowGluttonyActive(owner) then
            local moved = health_delta * V.SHADOW_GLUTTONY_HEAL_TO_SANITY_RATIO
            health_delta = health_delta - moved
            sanity_delta = (sanity_delta or 0) + moved
        end

        return health_delta, hunger_delta, sanity_delta
    end
end

local function RegisterShadowGluttonyPlayerHooks(inst)
    if inst == nil or inst.prefab ~= "waxwell" then
        return
    end

    if inst._waxwell_shadow_gluttony_player_hooks then
        return
    end

    inst._waxwell_shadow_gluttony_player_hooks = true
    PatchShadowGluttonyEater(inst)
end

local function ApplyShadowGluttonyEdible(inst)
    if inst == nil or not TheWorld.ismastersim then
        return
    end

    if inst.components.edible == nil then
        inst:AddComponent("edible")
    end

    inst.components.edible.foodtype = V.SHADOW_GLUTTONY_FOODTYPE
    inst.components.edible.hungervalue = 0
    inst.components.edible.healthvalue = 0
    inst.components.edible.sanityvalue = 0
    inst.components.edible:SetOnEatenFn(OnShadowGluttonyItemEaten)
end

local function RegisterShadowGluttonyComponentActions(env)
    if env == nil or env.AddComponentAction == nil then
        return
    end

    env.AddComponentAction("INVENTORY", "inventoryitem", function(inst, doer, actions, right)
        if inst ~= nil
            and (inst.prefab == "nightmarefuel" or inst.prefab == "horrorfuel")
            and doer ~= nil
            and doer.prefab == "waxwell"
            and IsShadowGluttonyActive(doer) then
            table.insert(actions, ACTIONS.EAT)
        end
    end)
end

local function ApplyShadowGluttonyToWaxwell(inst)
    if inst == nil or not TheWorld.ismastersim then
        return
    end

    inst:ListenForEvent("onactivateskill_server", RefreshShadowGluttonySkillState)
    inst:ListenForEvent("ondeactivateskill_server", function(player, data)
        if data ~= nil and data.skill == "waxwell_shadow_gluttony" then
            StopShadowGluttonyRegen(player)
        end
        RefreshShadowGluttonySkillState(player)
    end)
    inst:ListenForEvent("onsetskillselection_server", RefreshShadowGluttonySkillState)
    inst:ListenForEvent("ms_becameghost", function(player)
        SetShadowGluttonyCanEat(player, false)
    end)
    inst:ListenForEvent("ms_respawnedfromghost", RefreshShadowGluttonySkillState)

    inst:DoTaskInTime(0, function(player)
        RefreshShadowGluttonySkillState(player)
    end)
end

return {
    ApplyShadowGluttonyEdible = ApplyShadowGluttonyEdible,
    RegisterShadowGluttonyComponentActions = RegisterShadowGluttonyComponentActions,
    RegisterShadowGluttonyPlayerHooks = RegisterShadowGluttonyPlayerHooks,
    ApplyShadowGluttonyToWaxwell = ApplyShadowGluttonyToWaxwell,
    IsShadowGluttonyActive = IsShadowGluttonyActive,
}
