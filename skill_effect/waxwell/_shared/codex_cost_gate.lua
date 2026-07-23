local debug = require("debug/init")

local M = {}

local function GetCodexMaxFuel()
    local large = TUNING ~= nil and TUNING.LARGE_FUEL or nil
    return large ~= nil and large * 4 or nil
end

-- waxwelljournal มี fueled แค่ฝั่ง server; client อ่าน durability จาก percentused ของ inventoryitem
local function GetCodexFuelPercent(book)
    if book == nil or (book.IsValid ~= nil and not book:IsValid()) then
        return nil, nil
    end

    local fueled = book.components ~= nil and book.components.fueled or nil
    if fueled ~= nil then
        if fueled.GetPercent ~= nil and fueled.IsEmpty ~= nil then
            local ok, percent, is_empty = pcall(function()
                return fueled:GetPercent(), fueled:IsEmpty()
            end)
            if ok and percent ~= nil then
                return percent, is_empty == true
            end
        end

        local current = fueled.currentfuel
        if current ~= nil then
            local codex_max = GetCodexMaxFuel()
            if codex_max ~= nil and codex_max > 0 then
                local maxfuel = fueled.maxfuel ~= nil and fueled.maxfuel > 0 and fueled.maxfuel or codex_max
                return current / maxfuel, current <= 0
            end
        end
    end

    local invitem = book.replica ~= nil and book.replica.inventoryitem or nil
    local classified = invitem ~= nil and invitem.classified or nil
    if classified == nil or (classified.IsValid ~= nil and not classified:IsValid()) then
        return nil, nil
    end

    local percentused = classified.percentused
    if percentused == nil or type(percentused.value) ~= "function" then
        return nil, nil
    end

    local ok, raw = pcall(function()
        return percentused:value()
    end)
    if not ok or raw == nil or raw == 255 then
        return nil, nil
    end

    local percent = raw / 100
    return percent, percent <= 0
end

function M.GetSanityCurrent(doer)
    if doer == nil then
        return 0
    end

    local sanity = doer.components ~= nil and doer.components.sanity or nil
    if sanity ~= nil then
        return sanity.current or 0
    end

    sanity = doer.replica ~= nil and doer.replica.sanity or nil
    if sanity ~= nil and sanity.GetCurrent ~= nil then
        return sanity:GetCurrent() or 0
    end

    return 0
end

function M.HasEnoughSanity(doer, sanity_cost)
    if sanity_cost == nil or sanity_cost <= 0 then
        return true
    end

    return M.GetSanityCurrent(doer) >= sanity_cost
end

function M.HasEnoughCodexFuel(book, costpct)
    if debug.ShouldIgnoreCodexUmbraDurability() then
        return true
    end

    if costpct == nil then
        return true
    end

    local percent, is_empty = GetCodexFuelPercent(book)
    if percent == nil then
        return true
    end
    if is_empty then
        return false
    end

    local codex_max = GetCodexMaxFuel()
    if codex_max == nil then
        return true
    end

    local cost = costpct * codex_max
    return percent * codex_max >= cost - .001
end

function M.GetFuelBlockReason(book, costpct)
    if costpct == nil then
        return nil
    end

    local percent, is_empty = GetCodexFuelPercent(book)
    if percent == nil then
        return nil
    elseif is_empty then
        return "NO_FUEL_EMPTY"
    elseif not M.HasEnoughCodexFuel(book, costpct) then
        return "NO_FUEL_COST"
    end

    return nil
end

function M.GetResourceBlockReason(book, doer, costs)
    if costs == nil then
        return nil
    end

    if debug.IsSkillTestEnabled() then
        return nil
    end

    local mod_config = require("mod_config")
    if not mod_config.IsWaxwellCodexCostGateEnabled() then
        return nil
    end

    local fuelreason = M.GetFuelBlockReason(book, costs.fuel_pct)
    local sanity_cost = costs.sanity
    local sanity_blocked = sanity_cost ~= nil
        and sanity_cost > 0
        and not M.HasEnoughSanity(doer, sanity_cost)

    if fuelreason ~= nil and sanity_blocked then
        return "NO_FUEL_AND_SANITY"
    elseif fuelreason ~= nil then
        return fuelreason
    elseif sanity_blocked then
        return "NO_SANITY"
    end

    return nil
end

function M.CanAffordResources(book, doer, costs)
    return M.GetResourceBlockReason(book, doer, costs) == nil
end

function M.IsResourceBlockReason(blockreason)
    return blockreason == "NO_FUEL_EMPTY"
        or blockreason == "NO_FUEL_COST"
        or blockreason == "NO_SANITY"
        or blockreason == "NO_FUEL_AND_SANITY"
end

function M.MapResourceBlockToFail(blockreason)
    if blockreason == "NO_FUEL_AND_SANITY" then
        return false, "NO_FUEL_AND_SANITY"
    elseif blockreason == "NO_FUEL_EMPTY" or blockreason == "NO_FUEL_COST" then
        return false, "NO_FUEL"
    elseif blockreason == "NO_SANITY" then
        return false, "NO_SANITY"
    end

    return nil
end

function M.GetCastBlockedSpeechLine(blockreason)
    local failreason = nil
    if blockreason == "NO_FUEL_AND_SANITY" then
        failreason = "NO_FUEL_AND_SANITY"
    elseif blockreason == "NO_FUEL_EMPTY" or blockreason == "NO_FUEL_COST" then
        failreason = "NO_FUEL"
    elseif blockreason == "NO_SANITY" then
        failreason = "NO_SANITY"
    end

    local castaoe = STRINGS.CHARACTERS ~= nil
        and STRINGS.CHARACTERS.WAXWELL ~= nil
        and STRINGS.CHARACTERS.WAXWELL.ACTIONFAIL ~= nil
        and STRINGS.CHARACTERS.WAXWELL.ACTIONFAIL.CASTAOE
        or nil

    return failreason ~= nil and castaoe ~= nil and castaoe[failreason] or nil
end

local function SayCastBlockedLine(doer, blockreason)
    local line = M.GetCastBlockedSpeechLine(blockreason)
    if line == nil or doer == nil then
        return
    end

    local talker = doer.components ~= nil and doer.components.talker or nil
    if talker ~= nil
        and not (doer.components.health ~= nil and doer.components.health:IsDead()) then
        talker:Say(line)
    end
end

function M.PlayClientCastBlockedFeedback(pc, blockreason, doer)
    TheFocalPoint.SoundEmitter:PlaySound("dontstarve/HUD/click_negative", nil, .4)
    if pc ~= nil and pc.reticule ~= nil and pc.reticule.Blip ~= nil then
        pc.reticule:Blip()
    end

    doer = doer or (pc ~= nil and pc.inst or nil)
    SayCastBlockedLine(doer, blockreason)
end

return M
