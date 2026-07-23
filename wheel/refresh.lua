local Utils = require("wheel/utils")

local M = {}

local function GetOpenSpellWheel(owner, invobject)
	if owner == nil or invobject == nil or owner.HUD == nil then
		return nil
	end

	local hud = owner.HUD
	if hud.IsSpellWheelOpen == nil or hud.GetCurrentOpenSpellBook == nil then
		return nil
	end

	if not hud:IsSpellWheelOpen() or hud:GetCurrentOpenSpellBook() ~= invobject then
		return nil
	end

	return hud.controls ~= nil and hud.controls.spellwheel or nil
end

function M.SyncWheelItemsFromSpellbook(spellbook, wheel)
	if spellbook == nil or wheel == nil or spellbook.items == nil or wheel.activeitems == nil then
		return
	end

	local bookitems_by_key = {}
	for _, bookitem in ipairs(spellbook.items) do
		local key = Utils.GetSpellItemKey(bookitem)
		if key ~= nil then
			bookitems_by_key[key] = bookitem
		end
	end

	for _, wheelitem in ipairs(wheel.activeitems) do
		local bookitem = bookitems_by_key[Utils.GetSpellItemKey(wheelitem)]
		if bookitem ~= nil then
			for _, field in ipairs(Utils.DYNAMIC_FIELDS) do
				wheelitem[field] = bookitem[field]
			end
		end
	end
end

function M.RefreshOpenWheelVisuals(owner, invobject, opts)
	opts = opts or {}

	local wheel = GetOpenSpellWheel(owner, invobject)
	if wheel == nil then
		return false
	end

	wheel.owner = owner or wheel.owner or ThePlayer

	local spellbook = invobject.components ~= nil and invobject.components.spellbook or nil
	if spellbook ~= nil then
		M.SyncWheelItemsFromSpellbook(spellbook, wheel)
	end

	if opts.rebuild_items == true and spellbook ~= nil and spellbook.items ~= nil then
		owner.HUD:OpenSpellWheel(invobject, spellbook.items, spellbook.radius, spellbook.focus_radius, spellbook.bgdata)
		return true
	end

	if wheel.RefreshSkillTreeItemStates ~= nil then
		wheel:RefreshSkillTreeItemStates(opts.forceinit == true)
		return true
	end

	return false
end

return M
