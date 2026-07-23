-- =============================================================================
-- Debug facade — loads full implementation only when mod setting is On
-- =============================================================================

local stub = require("debug/stub")

local mod_config
local mode

local M = {}

local function IsModDebugEnabled()
    if mod_config == nil then
        mod_config = require("mod_config")
    end
    return mod_config.IsDebugModeEnabled()
end

function M.IsModDebugEnabled()
    return IsModDebugEnabled()
end

local function GetBackend()
    if not IsModDebugEnabled() then
        return stub
    end

    if mode == nil then
        mode = require("debug/mode")
    end

    return mode
end

function M.Register(env)
    if IsModDebugEnabled() then
        GetBackend().Register(env)
    end
end

setmetatable(M, {
    __index = function(_, key)
        return GetBackend()[key]
    end,
})

return M
