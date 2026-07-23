local Utils = require("wheel/utils")
local Overlay = require("wheel/overlay")

AddClassPostConstruct("widgets/wheel", function(self)
	local function RunRefresh(wheel, forceinit)
		if wheel == nil or not wheel.isopen or wheel.activeitems == nil then
			return false
		end

		wheel.owner = wheel.owner or ThePlayer
		return Overlay.RefreshAllItems(wheel, forceinit)
	end

	self.RefreshSkillTreeItemStates = function(wheel, forceinit)
		wheel = wheel or self
		local hasdynamicitems = RunRefresh(wheel, forceinit)
		if wheel.isopen and hasdynamicitems then
			wheel._skilltree_cooldown_updates_active = true
			wheel._skilltree_cooldown_elapsed = wheel._skilltree_cooldown_elapsed or 0
			wheel:StartUpdating()
		end
		return hasdynamicitems
	end

	local old_OnUpdate = self.OnUpdate
	function self:OnUpdate(dt)
		if old_OnUpdate ~= nil then
			old_OnUpdate(self, dt)
		end

		if not self._skilltree_cooldown_updates_active then
			return
		end

		self._skilltree_cooldown_elapsed = (self._skilltree_cooldown_elapsed or 0) + (dt or 0)
		if self._skilltree_cooldown_elapsed >= Utils.COOLDOWN_REFRESH_INTERVAL then
			self._skilltree_cooldown_elapsed = 0
			Overlay.RefreshAllItems(self, false)
		end
	end

	local old_Open = self.Open
	function self:Open(dataset_name)
		old_Open(self, dataset_name)

		if not self.isopen or self.activeitems == nil then
			return
		end

		local function AfterWheelOpen(forceinit)
			if not self.isopen or self.activeitems == nil then
				return
			end

			local hasdynamicitems = RunRefresh(self, forceinit)
			if not hasdynamicitems then
				self._skilltree_cooldown_updates_active = nil
				self._skilltree_cooldown_elapsed = nil
				return
			end

			self._skilltree_cooldown_updates_active = true
			self._skilltree_cooldown_elapsed = 0
			self:StartUpdating()
		end

		if self:IsEnabled() then
			AfterWheelOpen(true)
		elseif self.inst ~= nil and self.inst.DoTaskInTime ~= nil then
			if self._skilltree_open_refresh_task ~= nil then
				self._skilltree_open_refresh_task:Cancel()
			end
			self._skilltree_open_refresh_task = self.inst:DoTaskInTime(0, function()
				self._skilltree_open_refresh_task = nil
				AfterWheelOpen(true)
			end)
		else
			AfterWheelOpen(true)
		end
	end

	local old_Close = self.Close
	function self:Close(...)
		if self._skilltree_open_refresh_task ~= nil then
			self._skilltree_open_refresh_task:Cancel()
			self._skilltree_open_refresh_task = nil
		end

		self._skilltree_cooldown_updates_active = nil
		self._skilltree_cooldown_elapsed = nil
		self:StopUpdating()
		Overlay.ClearWheelOverlays(self)

		return old_Close(self, ...)
	end
end)
