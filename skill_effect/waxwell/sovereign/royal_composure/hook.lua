local common = require("skill_effect/waxwell/sovereign/royal_composure/common")

local PatchRoyalComposureSanity = common.PatchRoyalComposureSanity
local PatchRoyalComposureLoot = common.PatchRoyalComposureLoot

local M = {}

function M.Register(env)
    env.AddComponentPostInit("sanity", function(self)
        PatchRoyalComposureSanity(self)
    end)

    env.AddComponentPostInit("lootdropper", function(self)
        PatchRoyalComposureLoot(self)
    end)
end

return M
