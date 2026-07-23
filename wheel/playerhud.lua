AddClassPostConstruct("screens/playerhud", function(self)
	local old_OpenSpellWheel = self.OpenSpellWheel

	function self:OpenSpellWheel(invobject, items, radius, focus_radius, bgdata)
		local wheel = self.controls ~= nil and self.controls.spellwheel or nil
		if wheel ~= nil then
			wheel.owner = self.owner or wheel.owner or ThePlayer
		end

		old_OpenSpellWheel(self, invobject, items, radius, focus_radius, bgdata)

		wheel = self.controls ~= nil and self.controls.spellwheel or nil
		if wheel == nil or wheel.activeitems == nil then
			return
		end

		wheel.owner = self.owner or wheel.owner or ThePlayer

		if wheel.RefreshSkillTreeItemStates ~= nil then
			wheel:RefreshSkillTreeItemStates(true)
		end
	end
end)
