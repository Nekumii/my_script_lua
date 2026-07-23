local mod_config = require("mod_config")

if mod_config.IsSkillTreeCostOverlayEnabled() and not TheNet:IsDedicated() then
	table.insert(Assets, Asset("IMAGE", "images/_shared/skilltree_cost_glyphs.tex"))
	table.insert(Assets, Asset("ATLAS", "images/_shared/skilltree_cost_glyphs.xml"))

	modimport("scripts/ui/skilltree_cost_overlay/hooks.lua")

	if mod_config.IsWaxwellEnabled() then
		require("skill_info/skill_cost_waxwell").Register()
	end
end
