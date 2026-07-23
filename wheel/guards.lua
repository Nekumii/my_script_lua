local SpellIcon = require("skill_effect/waxwell/_shared/codex_spell_icon")
local ReticuleUtils = require("reticule/utils")

local umbral_rift_common
local function GetUmbralRiftCommon()
	if umbral_rift_common == nil then
		umbral_rift_common = require("skill_effect/waxwell/umbra/umbral_rift/common")
	end
	return umbral_rift_common
end

local M = {}

local function GetOwner(wheel, item)
	if wheel ~= nil and wheel.owner ~= nil then
		return wheel.owner
	end
	return ThePlayer
end

function M.ShouldBlockInteraction(wheel, item)
	if item == nil then
		return false
	end
	return SpellIcon.IsInteractionBlocked(SpellIcon.GetSnapshot(item, GetOwner(wheel, item)))
end

function M.ApplyItemGuards(wheel, item)
	local widget = item ~= nil and item.widget or nil
	if widget == nil then
		return
	end

	widget._skilltree_current_item = item
	widget._skilltree_current_wheel = wheel
	item._skilltree_base_noselect = item._skilltree_base_noselect == true or item.noselect == true

	if item._skilltree_item_callbacks_guarded then
		return
	end

	item._skilltree_item_callbacks_guarded = true
	item._skilltree_base_execute = item.execute
	item._skilltree_base_onselect = item.onselect
	item._skilltree_base_ondown = item.ondown

	local function blocked()
		return M.ShouldBlockInteraction(widget._skilltree_current_wheel or wheel, widget._skilltree_current_item or item)
	end

	item.execute = function(...)
		if blocked() then
			return false
		end

		local player = GetOwner(widget._skilltree_current_wheel or wheel, widget._skilltree_current_item or item)
		if player ~= nil and not GetUmbralRiftCommon().IsUmbralRiftWheelItem(item) then
			GetUmbralRiftCommon().CancelUmbralRiftSkill(player)
		end

		local execute = item._skilltree_base_execute
		if execute ~= nil then
			local ret = execute(...)
			local inst = select(1, ...)
			if inst ~= nil and inst:IsValid() and inst.prefab == "waxwelljournal" then
				if not GetUmbralRiftCommon().IsUmbralRiftWheelItem(item) then
					ReticuleUtils.PrepareVanillaJournalSpellReticule(inst)
				end
				ReticuleUtils.EnsureJournalReticuleRangeLock(inst)
			end
			return ret
		end
	end

	item.onselect = function(...)
		if blocked() then
			return false
		end

		-- สลับไปสกิลอื่น: ยกเลิก Umbral Rift ทั้งหมด (mark + journal state + reticule)
		local player = GetOwner(widget._skilltree_current_wheel or wheel, widget._skilltree_current_item or item)
		if player ~= nil and not GetUmbralRiftCommon().IsUmbralRiftWheelItem(item) then
			GetUmbralRiftCommon().CancelUmbralRiftSkill(player)
		end

		local onselect = item._skilltree_base_onselect
		if onselect ~= nil then
			local ret = onselect(...)
			local inst = select(1, ...)
			if inst ~= nil and inst:IsValid() and inst.prefab == "waxwelljournal" then
				if not GetUmbralRiftCommon().IsUmbralRiftWheelItem(item) then
					ReticuleUtils.PrepareVanillaJournalSpellReticule(inst)
				end
				ReticuleUtils.EnsureJournalReticuleRangeLock(inst)
			end
			return ret
		end
	end

	item.ondown = function(...)
		if blocked() then
			return true
		end
		local ondown = item._skilltree_base_ondown
		if ondown ~= nil then
			return ondown(...)
		end
	end

	if widget.onclick ~= widget._skilltree_guard_onclick then
		widget._skilltree_base_onclick = widget.onclick
	end
	if widget.ondown ~= widget._skilltree_guard_ondown then
		widget._skilltree_base_ondown = widget.ondown
	end
	if widget.OnControl ~= widget._skilltree_guard_oncontrol then
		widget._skilltree_base_oncontrol = widget.OnControl
	end
	if widget.OnMouseButton ~= widget._skilltree_guard_onmousebutton then
		widget._skilltree_base_onmousebutton = widget.OnMouseButton
	end

	widget._skilltree_guard_onclick = function(...)
		if blocked() then
			return true
		end
		local onclick = widget._skilltree_base_onclick
		if onclick ~= nil then
			return onclick(...)
		end
	end

	widget._skilltree_guard_ondown = function(...)
		if blocked() then
			return true
		end
		local ondown = widget._skilltree_base_ondown
		if ondown ~= nil then
			return ondown(...)
		end
	end

	widget._skilltree_guard_oncontrol = function(self, ...)
		if blocked() then
			return true
		end
		local oncontrol = self._skilltree_base_oncontrol
		if oncontrol ~= nil then
			return oncontrol(self, ...)
		end
	end

	widget._skilltree_guard_onmousebutton = function(self, ...)
		if blocked() then
			return true
		end
		local onmousebutton = self._skilltree_base_onmousebutton
		if onmousebutton ~= nil then
			return onmousebutton(self, ...)
		end
	end

	widget.onclick = widget._skilltree_guard_onclick
	widget.ondown = widget._skilltree_guard_ondown
	widget.OnControl = widget._skilltree_guard_oncontrol
	widget.OnMouseButton = widget._skilltree_guard_onmousebutton
end

function M.ApplyWheelItemEnabledState(wheel, item, index, blocked, forceinit)
	if item == nil or item.widget == nil then
		return
	end

	local widget = item.widget
	local base_noselect = item._skilltree_base_noselect == true
	item.noselect = base_noselect
	item._skilltree_wheel_blocked = blocked

	if base_noselect then
		if forceinit or widget.enabled then
			widget:Disable()
		end
		if widget.SetClickable ~= nil then
			widget:SetClickable(false)
		end
		if widget.ClearFocus ~= nil then
			widget:ClearFocus()
		end
		if wheel.selected_label ~= nil and wheel.selected_label._currentwidget == widget then
			wheel.selected_label:SetString("")
			wheel.selected_label._currentwidget = nil
		end
		if wheel.cur_cell_index == index then
			wheel.cur_cell_index = 0
		end
		return
	end

	if forceinit or not widget.enabled then
		widget:Enable()
	end
	if widget.SetClickable ~= nil then
		widget:SetClickable(true)
	end
end

return M
