local puppeteer_common = require("skill_effect/waxwell/puppeteer/_shared/common")
local spell_utils = require("skill_effect/waxwell/_shared/codex_spell_utils")
local debug = require("debug/init")

local M = {}

M.CanAddShadowServant = puppeteer_common.CanAddShadowServant
M.GetFragmentedMindPenalty = puppeteer_common.GetFragmentedMindPenalty
M.IsSpellOnCooldown = spell_utils.IsSpellOnCooldown
M.GetSpellCooldownPercent = spell_utils.GetSpellCooldownPercent
M.GetSpellCooldownTimeRemaining = spell_utils.GetSpellCooldownTimeRemaining
M.RestartSpellCooldown = spell_utils.RestartSpellCooldown
M.StopSpellCooldown = spell_utils.StopSpellCooldown
M.StartAOETargeting = spell_utils.StartAOETargeting
M.TriggerInstantSpellbookCast = spell_utils.CastSpellBookFromInventory

local function NotBlocked(pt)
    return pt ~= nil and not TheWorld.Map:IsGroundTargetBlocked(pt)
end

local function IsPassableGroundPoint(pt)
    return pt ~= nil
        and TheWorld.Map:IsPassableAtPoint(pt.x, 0, pt.z, true)
        and NotBlocked(pt)
end

function M.FindNearbyPassablePoint(origin, radius, attempts, minradius)
    if origin == nil then
        return nil
    end

    if radius == nil or radius <= 0 then
        return IsPassableGroundPoint(origin) and Vector3(origin.x, 0, origin.z) or nil
    end

    attempts = attempts or 12
    minradius = math.max(0, math.min(radius, minradius or 0))

    for _ = 1, attempts do
        local theta = math.random() * TWOPI
        local lerp = math.sqrt(math.random())
        local distance = minradius + (radius - minradius) * lerp
        local candidate = Vector3(
            origin.x + math.cos(theta) * distance,
            0,
            origin.z + math.sin(theta) * distance
        )
        if IsPassableGroundPoint(candidate) then
            return candidate
        end
    end

    local theta = math.random() * TWOPI
    local offset = FindWalkableOffset(origin, theta, radius, 16, false, true, NotBlocked, true, true)
    if (type(offset) == "table" or type(offset) == "userdata") and offset.x ~= nil and offset.z ~= nil then
        local candidate = Vector3(origin.x + offset.x, 0, origin.z + offset.z)
        if IsPassableGroundPoint(candidate) then
            return candidate
        end
    end

    return nil
end

function M.FindShadowStalkerSpawnPoint(doer, pos)
    if doer == nil or pos == nil then
        return nil
    end

    if IsPassableGroundPoint(pos) then
        return Vector3(pos.x, 0, pos.z)
    end

    local theta = doer:GetAngleToPoint(pos) * DEGREES
    local offset = FindWalkableOffset(pos, theta, 3, 16, false, true, NotBlocked, true, true)
    if (type(offset) == "table" or type(offset) == "userdata") and offset.x ~= nil and offset.z ~= nil then
        local candidate = Vector3(pos.x + offset.x, 0, pos.z + offset.z)
        if IsPassableGroundPoint(candidate) then
            return candidate
        end
    end

    return nil
end

function M.SpellCost(pct)
    if debug.ShouldIgnoreCodexUmbraDurability() then
        return 0
    end
    return pct * TUNING.LARGE_FUEL * -4
end

function M.HasEnoughCodexFuel(inst, costpct)
    if debug.ShouldIgnoreCodexUmbraDurability() then
        return true
    end
    local fueled = inst ~= nil and inst.components ~= nil and inst.components.fueled or nil
    local cost = M.SpellCost(costpct)
    return fueled ~= nil
        and fueled.currentfuel ~= nil
        and cost ~= nil
        and fueled.currentfuel >= math.abs(cost) - .001
end

function M.IsDarkScholarActive(inst)
    return inst ~= nil
        and inst.components ~= nil
        and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("waxwell_dark_scholar")
end

function M.ResolveSpellOwner(inst, doer, fallback)
    local owner = doer
    if (owner == nil or owner.components == nil) and inst ~= nil and inst.components ~= nil and inst.components.inventoryitem ~= nil then
        owner = inst.components.inventoryitem:GetGrandOwner()
    end
    return owner or fallback or ThePlayer
end

function M.PushEmperorSpellRefresh(owner)
    if TheWorld ~= nil and owner ~= nil then
        TheWorld:PushEvent("waxwell_emperor_spell_refresh", { owner = owner })
    end
end

return M