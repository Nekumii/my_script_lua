local debug = require("debug/init")
local V = require("skill_effect/waxwell/puppeteer/_shared/variables")

local tireless_servant_common = nil
local lethal_apparition_common = nil
local shadow_lanternbearer_common = nil
local shadow_marksman_common = nil

local function GetTirelessServantCommon()
    if tireless_servant_common == nil then
        tireless_servant_common = require("skill_effect/waxwell/puppeteer/tireless_servant/common")
    end

    return tireless_servant_common
end

local function GetLethalApparitionCommon()
    if lethal_apparition_common == nil then
        lethal_apparition_common = require("skill_effect/waxwell/puppeteer/lethal_apparition/common")
    end

    return lethal_apparition_common
end

local function GetShadowLanternbearerCommon()
    if shadow_lanternbearer_common == nil then
        shadow_lanternbearer_common = require("skill_effect/waxwell/puppeteer/shadow_lanternbearer/common")
    end

    return shadow_lanternbearer_common
end

local function GetShadowMarksmanCommon()
    if shadow_marksman_common == nil then
        shadow_marksman_common = require("skill_effect/waxwell/puppeteer/shadow_marksman/common")
    end

    return shadow_marksman_common
end

local function SpellCost(pct)
    return pct * TUNING.LARGE_FUEL * -4
end

local function GetCodexUmbraFuelCost(pct)
    if debug.ShouldIgnoreCodexUmbraDurability() then
        return 0
    end
    return pct ~= nil and pct * TUNING.LARGE_FUEL * -4 or nil
end

local function HasCodexUmbraFuelForCost(fueled, fueldelta)
    if debug.ShouldIgnoreCodexUmbraDurability() then
        return true
    end
    return fueled ~= nil
        and fueldelta ~= nil
        and fueled.currentfuel ~= nil
        and fueled.currentfuel >= math.abs(fueldelta) - .001
end

local function HasCodexUmbraFuelForPct(book, pct)
    local fueled = book ~= nil and book.components ~= nil and book.components.fueled or nil
    return HasCodexUmbraFuelForCost(fueled, GetCodexUmbraFuelCost(pct))
end

local function WithAdjustedCodexUmbraCastCosts(fueled, expectedfueldelta, adjustedfueldelta, sanity, expectedsanitydelta, adjustedsanitydelta, fn)
    if fn == nil then
        return
    end

    local old_FueledDoDelta = fueled ~= nil and fueled.DoDelta or nil
    if old_FueledDoDelta ~= nil and expectedfueldelta ~= nil and adjustedfueldelta ~= nil then
        fueled.DoDelta = function(self, delta, ...)
            if delta ~= nil and math.abs(delta - expectedfueldelta) < .001 then
                delta = adjustedfueldelta
            end

            return old_FueledDoDelta(self, delta, ...)
        end
    end

    local old_SanityDoDelta = sanity ~= nil and sanity.DoDelta or nil
    if old_SanityDoDelta ~= nil and expectedsanitydelta ~= nil and adjustedsanitydelta ~= nil then
        sanity.DoDelta = function(self, delta, ...)
            if delta == expectedsanitydelta then
                delta = adjustedsanitydelta
            end

            return old_SanityDoDelta(self, delta, ...)
        end
    end

    local ok, result, reason = xpcall(fn, debug.traceback)

    if old_FueledDoDelta ~= nil then
        fueled.DoDelta = old_FueledDoDelta
    end
    if old_SanityDoDelta ~= nil then
        sanity.DoDelta = old_SanityDoDelta
    end

    if not ok then
        error(result)
    end

    return result, reason
end

local function WithAdjustedTirelessServant2CastCosts(book, fn)
    if fn == nil then
        return
    end

    local fueled = book ~= nil and book.components ~= nil and book.components.fueled or nil
    if fueled == nil then
        return fn()
    end

    return WithAdjustedCodexUmbraCastCosts(
        fueled,
        GetCodexUmbraFuelCost(V.TIRELESS_SERVANT_2_BASE_DURABILITY_COST_PCT),
        GetCodexUmbraFuelCost(V.TIRELESS_SERVANT_2_DURABILITY_COST_PCT),
        nil,
        nil,
        nil,
        fn
    )
end

local function WithAdjustedLethalApparition2CastCosts(book, fn)
    if fn == nil then
        return
    end

    local fueled = book ~= nil and book.components ~= nil and book.components.fueled or nil
    if fueled == nil then
        return fn()
    end

    return WithAdjustedCodexUmbraCastCosts(
        fueled,
        GetCodexUmbraFuelCost(V.LETHAL_APPARITION_2_BASE_DURABILITY_COST_PCT),
        GetCodexUmbraFuelCost(V.LETHAL_APPARITION_2_DURABILITY_COST_PCT),
        nil,
        nil,
        nil,
        fn
    )
end

local function GetShadowServantCodexCostPct(prefab, owner)
    prefab = prefab ~= nil and string.lower(prefab) or nil
    if prefab == "shadowworker" then
        return GetTirelessServantCommon().IsTirelessServant2Active(owner)
            and V.TIRELESS_SERVANT_2_DURABILITY_COST_PCT
            or V.TIRELESS_SERVANT_2_BASE_DURABILITY_COST_PCT
    elseif prefab == "shadowprotector" then
        return GetLethalApparitionCommon().IsLethalApparition2Active(owner)
            and V.LETHAL_APPARITION_2_DURABILITY_COST_PCT
            or V.LETHAL_APPARITION_2_BASE_DURABILITY_COST_PCT
    elseif prefab == "shadow_marksman" then
        return GetShadowMarksmanCommon().IsShadowMarksman2Active(owner)
            and V.SHADOW_MARKSMAN_2_DURABILITY_COST_PCT
            or V.SHADOW_MARKSMAN_2_BASE_DURABILITY_COST_PCT
    elseif prefab == "shadow_lanternbearer" then
        return GetShadowLanternbearerCommon().IsShadowLanternbearer2Active(owner)
            and V.SHADOW_LANTERNBEARER_2_DURABILITY_COST_PCT
            or V.SHADOW_LANTERNBEARER_2_BASE_DURABILITY_COST_PCT
    end
end

return {
    SpellCost = SpellCost,
    GetCodexUmbraFuelCost = GetCodexUmbraFuelCost,
    HasCodexUmbraFuelForCost = HasCodexUmbraFuelForCost,
    HasCodexUmbraFuelForPct = HasCodexUmbraFuelForPct,
    WithAdjustedCodexUmbraCastCosts = WithAdjustedCodexUmbraCastCosts,
    WithAdjustedTirelessServant2CastCosts = WithAdjustedTirelessServant2CastCosts,
    WithAdjustedLethalApparition2CastCosts = WithAdjustedLethalApparition2CastCosts,
    GetShadowServantCodexCostPct = GetShadowServantCodexCostPct,
}
