local overlay_widget = require("ui/skilltree_cost_overlay/overlay_widget")

local function EnsureOverlay(infopanel)
	if infopanel == nil or infopanel._skilltree_cost_overlay ~= nil then
		return infopanel ~= nil and infopanel._skilltree_cost_overlay or nil
	end

	infopanel._skilltree_cost_overlay = infopanel:AddChild(overlay_widget.SkillTreeCostOverlay())
	infopanel._skilltree_cost_overlay:MoveToFront()
	return infopanel._skilltree_cost_overlay
end

AddClassPostConstruct("widgets/redux/skilltreewidget", function(self)
	if self.root ~= nil and self.root.infopanel ~= nil then
		EnsureOverlay(self.root.infopanel)
	end
end)

AddClassPostConstruct("widgets/redux/skilltreebuilder", function(self)
	local old_RefreshTree = self.RefreshTree

	function self:RefreshTree(...)
		old_RefreshTree(self, ...)

		local overlay = EnsureOverlay(self.infopanel)
		if overlay ~= nil then
			overlay:SetSkill(self.target, self.selectedskill)
		end
	end
end)
