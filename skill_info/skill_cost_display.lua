-- =============================================================================
-- Skill cost display registry
-- =============================================================================

local M = {}

local providers = {}

function M.RegisterCharacter(prefab, provider)
    if prefab ~= nil and provider ~= nil then
        providers[prefab] = provider
    end
end

function M.GetCostDisplay(prefab, skill_id)
    if prefab == nil or skill_id == nil then
        return nil
    end

    local provider = providers[prefab]
    if provider == nil then
        return nil
    end

    return provider(skill_id)
end

local function AppendDigits(tokens, value)
    local text = tostring(math.floor(value + 0.5))
    for i = 1, #text do
        tokens[#tokens + 1] = "digit_" .. text:sub(i, i)
    end
end

local function AppendMinus(tokens)
    tokens[#tokens + 1] = "minus"
end

function M.BuildDurabilityTokens(cost)
    if cost == nil or cost.durability_pct == nil then
        return nil
    end

    local tokens = {}
    AppendMinus(tokens)
    AppendDigits(tokens, cost.durability_pct)
    tokens[#tokens + 1] = "percent"
    return tokens
end

function M.BuildSanityPenaltyTokens(cost)
    if cost == nil or cost.sanity_penalty_pct == nil then
        return nil
    end

    local tokens = {}
    AppendMinus(tokens)
    AppendDigits(tokens, cost.sanity_penalty_pct)
    tokens[#tokens + 1] = "percent"
    return tokens
end

function M.BuildSanityTokens(cost)
    if cost == nil then
        return nil
    end

    if cost.sanity_all then
        return { "all" }
    end

    if cost.sanity_discount ~= nil then
        local tokens = {}
        AppendMinus(tokens)
        AppendDigits(tokens, cost.sanity_discount.base or 0)
        tokens[#tokens + 1] = "greater"
        AppendDigits(tokens, cost.sanity_discount.rehit or 0)
        return tokens
    end

    if cost.sanity_cast_min ~= nil then
        local tokens = { "greater" }
        AppendDigits(tokens, cost.sanity_cast_min)
        return tokens
    end

    if cost.sanity_per_sec ~= nil then
        local tokens = {}
        AppendDigits(tokens, cost.sanity_per_sec.min or 0)
        if cost.sanity_per_sec.max ~= nil then
            tokens[#tokens + 1] = "greater"
            AppendDigits(tokens, cost.sanity_per_sec.max)
        end
        tokens[#tokens + 1] = "slash"
        tokens[#tokens + 1] = "s"
        return tokens
    end

    if cost.sanity_flat ~= nil then
        local tokens = {}
        AppendMinus(tokens)
        AppendDigits(tokens, cost.sanity_flat)
        return tokens
    end

    return nil
end

return M
