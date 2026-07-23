local SpellIcon = require("skill_effect/waxwell/_shared/codex_spell_icon")
local Utils = require("wheel/utils")
local Guards = require("wheel/guards")

local M = {}

local UIAnim = require("widgets/uianim")

local function GetOverlayScale(item, snapshot)
	if item ~= nil and item.cooldownscale ~= nil then
		return item.cooldownscale
	end

	if snapshot ~= nil and snapshot.overlay_pct ~= nil and snapshot.overlay_pct > 0 then
		if snapshot.overlayonly or snapshot.overlay_pct >= (SpellIcon.FULL_OVERLAY or 1) then
			return SpellIcon.WHEEL_FULL_OVERLAY_SCALE or 1.42
		end
	end

	return SpellIcon.WHEEL_PARTIAL_OVERLAY_SCALE or .78
end

local function EnsureOverlayWidget(widget, item, snapshot)
	if widget == nil or widget.cooldown ~= nil then
		return widget ~= nil and widget.cooldown or nil
	end

	local owner = ThePlayer
	local cooldowncolor = snapshot ~= nil and snapshot.overlay_color
		or Utils.ResolveColor(item.cooldowncolor, owner, SpellIcon.COLORS.COOLDOWN)
	local parent = (widget.image ~= nil and widget.image.AddChild ~= nil) and widget.image or widget
	local cooldown = parent:AddChild(UIAnim())
	cooldown:SetClickable(false)
	cooldown:GetAnimState():SetBank("status_meter_circle")
	cooldown:GetAnimState():SetBuild("status_meter_circle")
	cooldown:GetAnimState():PlayAnimation("meter")
	cooldown:GetAnimState():AnimateWhilePaused(false)
	cooldown:GetAnimState():SetMultColour(unpack(cooldowncolor))
	cooldown:SetScale(GetOverlayScale(item, snapshot))
	cooldown:Hide()

	widget.cooldown = cooldown
	return cooldown
end

function M.RefreshItemOverlay(wheel, item, index, forceinit)
	if item == nil or item.anims ~= nil or item.widget == nil then
		return
	end

	Guards.ApplyItemGuards(wheel, item)

	local owner = wheel.owner or ThePlayer
	local snapshot = SpellIcon.GetSnapshot(item, owner)
	local blocked = SpellIcon.IsInteractionBlocked(snapshot)
	local cooldown = EnsureOverlayWidget(item.widget, item, snapshot)
	if cooldown == nil then
		Guards.ApplyWheelItemEnabledState(wheel, item, index, blocked, forceinit)
		return
	end

	local cooldowncolor = snapshot.overlay_color or Utils.ResolveColor(item.cooldowncolor, owner, SpellIcon.COLORS.COOLDOWN)
	local visible = snapshot.overlay_pct ~= nil and snapshot.overlay_pct > 0
	local shownpct = visible and (snapshot.overlayonly and 1 or math.clamp(snapshot.overlay_pct, 0, 1)) or nil
	local state = cooldown._skilltree_state or {}
	local targetscale = GetOverlayScale(item, snapshot)

	if forceinit
		or state.icon_state ~= snapshot.state
		or not Utils.AreColorsEqual(state.cooldowncolor, cooldowncolor)
		or state.scale ~= targetscale then
		cooldown:GetAnimState():SetMultColour(unpack(cooldowncolor))
		state.cooldowncolor = { cooldowncolor[1], cooldowncolor[2], cooldowncolor[3], cooldowncolor[4] }
	end

	if forceinit or state.scale ~= targetscale then
		cooldown:SetScale(targetscale)
		state.scale = targetscale
	end

	Guards.ApplyWheelItemEnabledState(wheel, item, index, blocked, forceinit)

	if visible then
		if forceinit or state.visible ~= true or state.pct ~= shownpct or state.icon_state ~= snapshot.state then
			cooldown:GetAnimState():SetPercent("meter", shownpct)
		end
		if forceinit or state.visible ~= true then
			cooldown:Show()
		end
	elseif forceinit or state.visible ~= false then
		cooldown:Hide()
	end

	state.visible = visible
	state.pct = shownpct
	state.blocked = blocked
	state.overlayonly = snapshot.overlayonly == true
	state.icon_state = snapshot.state
	cooldown._skilltree_state = state
end

function M.ClearWheelOverlays(wheel)
	if wheel == nil or wheel.activeitems == nil then
		return
	end

	for _, item in ipairs(wheel.activeitems) do
		if item ~= nil and item.anims == nil and item.widget ~= nil and item.widget.cooldown ~= nil then
			item.widget.cooldown._skilltree_state = nil
			item.widget.cooldown:Hide()
		end
	end
end

function M.ClearBlockedSelection(wheel)
	if wheel == nil or wheel.activeitems == nil then
		return
	end

	local currentindex = wheel.cur_cell_index
	local currentitem = currentindex ~= nil and currentindex > 0 and wheel.activeitems[currentindex] or nil
	if currentitem ~= nil and Guards.ShouldBlockInteraction(wheel, currentitem) then
		wheel.cur_cell_index = 0
	end
end

function M.RefreshAllItems(wheel, forceinit)
	if wheel == nil or wheel.activeitems == nil then
		return false
	end

	local hasdynamicitems = false
	for i, item in ipairs(wheel.activeitems) do
		if item ~= nil and item.anims == nil and item.widget ~= nil then
			hasdynamicitems = true
			M.RefreshItemOverlay(wheel, item, i, forceinit)
		end
	end

	M.ClearBlockedSelection(wheel)
	return hasdynamicitems
end

return M
