local common = require("skill_effect/waxwell/sovereign/shadow_gluttony/common")

local ApplyShadowGluttonyEdible = common.ApplyShadowGluttonyEdible
local RegisterShadowGluttonyComponentActions = common.RegisterShadowGluttonyComponentActions
local RegisterShadowGluttonyPlayerHooks = common.RegisterShadowGluttonyPlayerHooks

local M = {}

function M.Register(env)
    local AddPrefabPostInit = env.AddPrefabPostInit

    RegisterShadowGluttonyComponentActions(env)

    AddPrefabPostInit("nightmarefuel", ApplyShadowGluttonyEdible)
    AddPrefabPostInit("horrorfuel", ApplyShadowGluttonyEdible)

    AddPrefabPostInit("waxwell", function(inst)
        RegisterShadowGluttonyPlayerHooks(inst)
    end)
end

return M
