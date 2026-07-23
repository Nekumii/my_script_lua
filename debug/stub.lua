-- =============================================================================
-- Debug stub (mod setting Debug Mode = Off)
-- =============================================================================

local M = {}

function M.IsModDebugEnabled()
    return false
end

function M.IsSkillTestEnabled()
    return false
end

function M.GetSkillTestCooldown(defaultcooldown)
    return defaultcooldown
end

function M.ShouldIgnoreCodexUmbraDurability()
    return false
end

function M.IsSkillInfoEnabled(owner)
    return false
end

function M.IsSkillAllEnabled(owner)
    return false
end

function M.GetSkillInfoString(owner)
    return nil
end

function M.Register(env)
end

return M
