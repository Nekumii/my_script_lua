local M = {}
local debug = require("debug/init")
local pairs = rawget(_G, "pairs") or pairs

local function GetSpellbookCooldowns(doer)
    return doer ~= nil and doer.components ~= nil and doer.components.spellbookcooldowns or nil
end

function M.GetSpellHash(spellname)
    return type(spellname) == "string" and hash(spellname) or spellname
end

function M.IsSpellOnCooldown(doer, cooldownid)
    local spellbookcooldowns = GetSpellbookCooldowns(doer)
    return spellbookcooldowns ~= nil and spellbookcooldowns:IsInCooldown(cooldownid)
end

function M.GetSpellCooldownPercent(doer, cooldownid)
    local spellbookcooldowns = GetSpellbookCooldowns(doer)
    return spellbookcooldowns ~= nil and spellbookcooldowns:GetSpellCooldownPercent(cooldownid) or nil
end

function M.RestartSpellCooldown(doer, cooldownid, cooldown)
    local spellbookcooldowns = GetSpellbookCooldowns(doer)
    if spellbookcooldowns ~= nil then
        cooldown = debug.GetSkillTestCooldown(cooldown)
        spellbookcooldowns:RestartSpellCooldown(cooldownid, cooldown)
    end
end

function M.StopSpellCooldown(doer, cooldownid)
    local spellbookcooldowns = GetSpellbookCooldowns(doer)
    if spellbookcooldowns ~= nil then
        spellbookcooldowns:StopSpellCooldown(cooldownid)
    end
end

function M.GetSpellCooldownTimeRemaining(doer, cooldownid)
    local spellbookcooldowns = GetSpellbookCooldowns(doer)
    if spellbookcooldowns == nil or spellbookcooldowns.cooldowns == nil then
        return nil
    end

    local cooldown = spellbookcooldowns.cooldowns[M.GetSpellHash(cooldownid)]
    if cooldown ~= nil and cooldown.GetPercent ~= nil and cooldown.GetLength ~= nil then
        return math.max(0, cooldown:GetPercent() * cooldown:GetLength())
    end

    return nil
end

function M.ApplySkillTestCooldownOverride(doer)
    local spellbookcooldowns = GetSpellbookCooldowns(doer)
    if spellbookcooldowns == nil or spellbookcooldowns.cooldowns == nil or not debug.IsSkillTestEnabled() then
        return 0
    end

    local changed = 0
    for spellhash, cooldown in pairs(spellbookcooldowns.cooldowns) do
        if cooldown ~= nil then
            if spellbookcooldowns.ismastersim and spellbookcooldowns.RestartSpellCooldown ~= nil then
                spellbookcooldowns:RestartSpellCooldown(spellhash, debug.GetSkillTestCooldown(cooldown.GetLength ~= nil and cooldown:GetLength() or 1))
                changed = changed + 1
            elseif cooldown.RestartSpellCooldown ~= nil then
                cooldown:RestartSpellCooldown(debug.GetSkillTestCooldown(cooldown.GetLength ~= nil and cooldown:GetLength() or 1))
                changed = changed + 1
            end
        end
    end

    return changed
end

function M.StartAOETargeting(inst)
    local playercontroller = ThePlayer ~= nil and ThePlayer.components ~= nil and ThePlayer.components.playercontroller or nil
    if playercontroller ~= nil then
        playercontroller:StartAOETargetingUsing(inst)
    end
end

function M.CastSpellBookFromInventory(inst, spell_action)
    local playercontroller = ThePlayer ~= nil and ThePlayer.components ~= nil and ThePlayer.components.playercontroller or nil
    local inventory_replica = ThePlayer ~= nil and ThePlayer.replica ~= nil and ThePlayer.replica.inventory or nil
    local inventory = ThePlayer ~= nil and ThePlayer.components ~= nil and ThePlayer.components.inventory or nil

    if inventory_replica ~= nil and inventory_replica.CastSpellBookFromInv ~= nil then
        inventory_replica:CastSpellBookFromInv(inst)
    elseif playercontroller ~= nil and not playercontroller.ismastersim and playercontroller.RemoteCastSpellBookFromInv ~= nil then
        playercontroller:RemoteCastSpellBookFromInv(
            inst,
            inst.components ~= nil and inst.components.spellbook ~= nil and inst.components.spellbook:GetSelectedSpell() or 0,
            spell_action or ACTIONS.CAST_SPELLBOOK
        )
    elseif inventory ~= nil and inventory.CastSpellBookFromInv ~= nil then
        inventory:CastSpellBookFromInv(inst, inst.components ~= nil and inst.components.spellbook ~= nil and inst.components.spellbook:GetSelectedSpell() or nil)
    end
end

return M