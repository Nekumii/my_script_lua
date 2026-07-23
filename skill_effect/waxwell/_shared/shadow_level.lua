--//////////////////// Shadow Level
local SHADOW_LEVEL_BONUS_PER_LEVEL = TUNING.SHADOWWAXWELL_PROTECTOR_DAMAGE_BONUS_PER_LEVEL
local SHADOW_LEVEL_RANGE = TUNING.SHADOWWAXWELL_PROTECTOR_SHADOW_LEADER_RADIUS
local modglobals = rawget(_G, "GLOBAL") or _G
local AddStategraphPostInitFn = rawget(modglobals, "AddStategraphPostInit")
local AddPrefabPostInitFn = rawget(modglobals, "AddPrefabPostInit")

local inner_incarnate_common = nil
local inner_incarnate_variables = nil

local function GetInnerIncarnateCommon()
    if inner_incarnate_common == nil then
        inner_incarnate_common = require("skill_effect/waxwell/sovereign/inner_incarnate/common")
    end
    return inner_incarnate_common
end

local function GetInnerIncarnateVariables()
    if inner_incarnate_variables == nil then
        inner_incarnate_variables = require("skill_effect/waxwell/sovereign/inner_incarnate/variables")
    end
    return inner_incarnate_variables
end

local function IsLeaderInnerIncarnateActive(leader)
    if leader == nil then
        return false
    end

    local common = GetInnerIncarnateCommon()
    return common ~= nil and common.IsInnerIncarnateActive(leader)
end

local function IsNearTarget(inst, target, range)
    return inst ~= nil
        and target ~= nil
        and inst:IsNear(target, range + target:GetPhysicsRadius(0))
end

local function IsLeaderNear(inst, leader, target, range)
    return inst ~= nil
        and leader ~= nil
        and (inst:IsNear(leader, range) or (target ~= nil and IsNearTarget(leader, target, range)))
end

local function GetEquippedShadowLevelFromInventory(inventory)
    local level = 0
    if inventory == nil then
        return level
    end

    for _, slot in pairs(EQUIPSLOTS) do
        local equip = inventory:GetEquippedItem(slot)
        if equip ~= nil and equip.components ~= nil and equip.components.shadowlevel ~= nil then
            level = level + equip.components.shadowlevel:GetCurrentLevel()
        end
    end

    return level
end

local function PlayerHasBoundLantern(player)
    if player == nil or not player:IsValid() or player.userid == nil then
        return false
    end

    local x, y, z = player.Transform:GetWorldPosition()
    for _, ent in ipairs(TheSim:FindEntities(x, y, z, 30, { "shadow_lanternbearer" }, { "INLIMBO" })) do
        if ent ~= nil
            and ent:IsValid()
            and ent._bound_target_userid ~= nil
            and ent._bound_target_userid == player.userid then
            return true
        end
    end

    return false
end

local function GetPlayerLanternShadowLevel(player)
    if not PlayerHasBoundLantern(player) then
        return 0
    end

    local vars = GetInnerIncarnateVariables()
    return vars ~= nil and vars.INNER_INCARNATE_LANTERN_SHADOW_LEVEL or 1
end

local function GetLeaderEquippedShadowLevel(inst, target)
    local leader = inst ~= nil and inst.components ~= nil and inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
    if leader == nil
        or leader.components == nil
        or leader.components.inventory == nil
        or not IsLeaderNear(inst, leader, target, SHADOW_LEVEL_RANGE) then
        return 0
    end

    return GetEquippedShadowLevelFromInventory(leader.components.inventory)
        + GetPlayerLanternShadowLevel(leader)
end

local function GetPlayerShadowLevel(player)
    if player == nil or not IsLeaderInnerIncarnateActive(player) then
        return 0
    end

    local inventory = player.components ~= nil and player.components.inventory or nil
    local vars = GetInnerIncarnateVariables()
    local passive = vars ~= nil and vars.INNER_INCARNATE_PASSIVE_SHADOW_LEVEL or 1

    return GetEquippedShadowLevelFromInventory(inventory)
        + GetPlayerLanternShadowLevel(player)
        + passive
end

local function GetTotalShadowLevel(inst, target)
    local leader = inst ~= nil and inst.components ~= nil and inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
    if leader ~= nil and IsLeaderInnerIncarnateActive(leader) then
        return 0
    end

    return GetLeaderEquippedShadowLevel(inst, target)
end

local function GetShadowLevelDamageBonus(inst, target)
    return GetTotalShadowLevel(inst, target) * SHADOW_LEVEL_BONUS_PER_LEVEL
end

local function GetPlayerShadowLevelDamageBonus(player)
    return GetPlayerShadowLevel(player) * SHADOW_LEVEL_BONUS_PER_LEVEL
end

local function ApplyShadowLevelCombatBonus(inst)
    if inst.components == nil or inst.components.combat == nil then
        return
    end

    local combat = inst.components.combat
    if combat._skilltree_shadow_level_bonus_patched then
        return
    end
    combat._skilltree_shadow_level_bonus_patched = true

    local old_bonusdamagefn = combat.bonusdamagefn
    combat.bonusdamagefn = function(attacker, target, damage, weapon)
        local bonus = 0
        if old_bonusdamagefn ~= nil then
            bonus = old_bonusdamagefn(attacker, target, damage, weapon) or 0
        end
        if attacker == nil or not attacker:IsValid() then
            return bonus
        end

        return bonus + GetShadowLevelDamageBonus(attacker, target ~= nil and target:IsValid() and target or nil)
    end
end

if AddStategraphPostInitFn ~= nil
    and AddPrefabPostInitFn ~= nil
    and not rawget(modglobals, "_skilltree_shadow_level_hooks_loaded") then
    rawset(modglobals, "_skilltree_shadow_level_hooks_loaded", true)

    AddStategraphPostInitFn("shadowwaxwell", function(sg)
        local attack = sg.states ~= nil and sg.states.attack or nil
        if attack ~= nil and not attack._waxwell_shadowlevel_aura_patched then
            attack._waxwell_shadowlevel_aura_patched = true
            local timeline = attack.timeline
            if timeline ~= nil and timeline[2] ~= nil then
                timeline[2].fn = function(inst)
                    inst.sg:RemoveStateTag("abouttoattack")
                    local target = inst.sg.statemem.target
                    local basedamage = TUNING.SHADOWWAXWELL_PROTECTOR_DAMAGE
                    inst.components.combat:SetDefaultDamage(basedamage + GetShadowLevelDamageBonus(inst, target ~= nil and target:IsValid() and target or nil))
                    inst.sg.statemem.recoilstate = "attack_recoil"
                    inst.components.combat:DoAttack(target)
                end
            end
        end

        local lunge_loop = sg.states ~= nil and sg.states.lunge_loop or nil
        if lunge_loop ~= nil and not lunge_loop._waxwell_shadowlevel_aura_patched then
            lunge_loop._waxwell_shadowlevel_aura_patched = true
            lunge_loop.onupdate = function(inst)
                if inst.sg.statemem.attackdone then
                    return
                end
                local target = inst.sg.statemem.target
                if target == nil or not target:IsValid() then
                    if inst.sg.statemem.animdone then
                        inst.sg.statemem.lunge = true
                        inst.sg:GoToState("lunge_pst")
                        return
                    end
                    inst.sg.statemem.target = nil
                elseif inst:IsNear(target, 1) then
                    local fx = SpawnPrefab(math.random() < .5 and "shadowstrike_slash_fx" or "shadowstrike_slash2_fx")
                    local x, y, z = target.Transform:GetWorldPosition()
                    fx.Transform:SetPosition(x, y + 1.5, z)
                    fx.Transform:SetRotation(inst.Transform:GetRotation())

                    inst.components.combat:SetDefaultDamage(TUNING.SHADOWWAXWELL_PROTECTOR_DAMAGE + GetShadowLevelDamageBonus(inst, target))
                    inst.components.combat.externaldamagemultipliers:SetModifier(inst, TUNING.SHADOWWAXWELL_SHADOWSTRIKE_DAMAGE_MULT, "shadowstrike")
                    inst.components.combat:DoAttack(target)
                    inst:DropAggro()
                    if inst.sg.statemem.animdone then
                        inst.sg.statemem.lunge = true
                        inst.sg:GoToState("lunge_pst", target)
                        return
                    end
                    inst.sg.statemem.attackdone = true
                end
            end
        end
    end)

    AddPrefabPostInitFn("shadowprotector", function(inst)
        if not TheWorld.ismastersim then
            return
        end

        if inst.components == nil or inst.components.combat == nil then
            return
        end

        inst.components.combat:SetDefaultDamage(TUNING.SHADOWWAXWELL_PROTECTOR_DAMAGE)
        ApplyShadowLevelCombatBonus(inst)
    end)

    AddPrefabPostInitFn("shadow_stalker", function(inst)
        if not TheWorld.ismastersim or inst.components == nil or inst.components.combat == nil then
            return
        end

        ApplyShadowLevelCombatBonus(inst)
    end)
end

return {
    GetLeaderEquippedShadowLevel = GetLeaderEquippedShadowLevel,
    GetPlayerLanternShadowLevel = GetPlayerLanternShadowLevel,
    GetPlayerShadowLevel = GetPlayerShadowLevel,
    GetTotalShadowLevel = GetTotalShadowLevel,
    GetShadowLevelDamageBonus = GetShadowLevelDamageBonus,
    GetPlayerShadowLevelDamageBonus = GetPlayerShadowLevelDamageBonus,
    PlayerHasBoundLantern = PlayerHasBoundLantern,
    IsLeaderInnerIncarnateActive = IsLeaderInnerIncarnateActive,
}
