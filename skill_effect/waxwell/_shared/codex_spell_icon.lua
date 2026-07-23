local V = require("skill_effect/waxwell/emperor/_shared/variables")

local M = {}

M.STATE = {
	READY = "ready",
	DISABLED = "disabled",
	ACTIVE = "active",
	TOGGLE = "toggle",
	COOLDOWN = "cooldown",
}

M.COLORS = {
	DISABLED = { .52, .16, .16, .65 },
	ACTIVE = { .10, .70, .24, .65 },
	TOGGLE = { .85, .72, .12, .65 },
	COOLDOWN = { .12, .28, .42, .65 },
}

M.FULL_OVERLAY = 1
M.WHEEL_FULL_OVERLAY_SCALE = 1.42
M.WHEEL_PARTIAL_OVERLAY_SCALE = .78

local TRANSITION_STATES =
{
	spawning = true,
	deactivating = true,
	activating = true,
	unlocking = true,
}

local emperor_common

local function GetEmperorCommon()
	if emperor_common == nil then
		emperor_common = require("skill_effect/waxwell/emperor/_shared/common")
	end
	return emperor_common
end

local function ResolveValue(value, owner, fallback)
	local result = value
	for _ = 1, 2 do
		if type(result) == "function" then
			result = result(owner)
		else
			break
		end
	end
	-- Must accept explicit false/0; `x ~= nil and x or fallback` turns false into fallback.
	if result == nil then
		return fallback
	end
	return result
end

local function ResolveBool(value, owner, fallback)
	return ResolveValue(value, owner, fallback == true) == true
end

local function ResolveNumber(value, owner, fallback)
	local number = ResolveValue(value, owner, fallback)
	return type(number) == "number" and number or fallback
end

local function ResolveColor(value, owner, fallback)
	local color = ResolveValue(value, owner, fallback)
	if type(color) ~= "table" or color[1] == nil or color[2] == nil or color[3] == nil or color[4] == nil then
		return fallback
	end
	return color
end

function M.GetItemKey(item)
	return item ~= nil and (item.spell_id or item.label) or nil
end

local function IsTransitionState(state)
	return state ~= nil and TRANSITION_STATES[state] == true
end

local function MakeDisabledSnapshot(overlay_pct)
	return {
		state = M.STATE.DISABLED,
		interactable = false,
		overlay_pct = overlay_pct,
		overlay_color = M.COLORS.DISABLED,
		overlayonly = false,
	}
end

function M.GetSpellState(item, owner)
	return ResolveValue(item ~= nil and item.get_spell_state or nil, owner, nil)
end

function M.GetCooldownPercent(item, owner)
	if item == nil then
		return nil
	end

	if item.get_cooldown_percent ~= nil then
		return ResolveNumber(item.get_cooldown_percent, owner, nil)
	end

	return ResolveNumber(item.checkcooldown, owner, nil)
end

function M.GetActiveDurationPercent(item, owner)
	if item == nil or item.get_active_duration_percent == nil then
		return nil
	end

	return ResolveNumber(item.get_active_duration_percent, owner, nil)
end

function M.GetEntityTimerRemainingPercent(ent, timer_name)
	if ent == nil or not ent:IsValid() or timer_name == nil then
		return nil
	end

	local timer = ent.components ~= nil and ent.components.timer or nil
	if timer == nil or not timer:TimerExists(timer_name) then
		return nil
	end

	local left = timer:GetTimeLeft(timer_name)
	local data = timer.timers ~= nil and timer.timers[timer_name] or nil
	local total = data ~= nil and data.initial_time or nil
	if left == nil or total == nil or total <= 0 then
		return nil
	end

	return math.clamp(left / total, 0, 1)
end

function M.GetDynamicBlock(item, owner)
	local common = GetEmperorCommon()
	if common.GetBlockedSpellOverlay ~= nil then
		return common.GetBlockedSpellOverlay(item, owner)
	end
	return nil, nil
end

function M.GetSnapshot(item, owner)
	if item == nil then
		return {
			state = M.STATE.DISABLED,
			interactable = false,
			overlay_pct = nil,
			overlay_color = M.COLORS.DISABLED,
			overlayonly = false,
		}
	end

	local block_pct, block_color = M.GetDynamicBlock(item, owner)
	if block_pct ~= nil then
		return {
			state = M.STATE.DISABLED,
			interactable = false,
			overlay_pct = block_pct,
			overlay_color = block_color or M.COLORS.DISABLED,
			overlayonly = false,
		}
	end

	local spell_state = M.GetSpellState(item, owner)
	if spell_state == "active" then
		if item.spell_toggle == true then
			local duration_pct = M.GetActiveDurationPercent(item, owner)
			if duration_pct ~= nil then
				return {
					state = M.STATE.TOGGLE,
					interactable = true,
					overlay_pct = math.clamp(duration_pct, 0, 1),
					overlay_color = M.COLORS.TOGGLE,
					overlayonly = false,
				}
			end

			return {
				state = M.STATE.TOGGLE,
				interactable = true,
				overlay_pct = M.FULL_OVERLAY,
				overlay_color = M.COLORS.TOGGLE,
				overlayonly = true,
			}
		end

		return {
			state = M.STATE.ACTIVE,
			interactable = false,
			overlay_pct = M.FULL_OVERLAY,
			overlay_color = M.COLORS.ACTIVE,
			overlayonly = true,
		}
	end

	if IsTransitionState(spell_state) then
		return MakeDisabledSnapshot(M.FULL_OVERLAY)
	end

	if item.checkenabled ~= nil and not ResolveBool(item.checkenabled, owner, true) then
		return MakeDisabledSnapshot(M.FULL_OVERLAY)
	end

	local pct = M.GetCooldownPercent(item, owner)
	if pct ~= nil and pct > 0 then
		return {
			state = M.STATE.COOLDOWN,
			interactable = false,
			overlay_pct = math.clamp(pct, 0, 1),
			overlay_color = ResolveColor(item.cooldowncolor, owner, M.COLORS.COOLDOWN),
			overlayonly = false,
		}
	end

	return {
		state = M.STATE.READY,
		interactable = true,
		overlay_pct = nil,
		overlay_color = nil,
		overlayonly = false,
	}
end

function M.IsInteractionBlocked(snapshot)
	return snapshot == nil or snapshot.interactable ~= true
end

function M.ShouldBlockItem(item, owner)
	return M.IsInteractionBlocked(M.GetSnapshot(item, owner))
end

function M.NeedsWheelVisualRefresh(item, owner)
	if item == nil or item.anims ~= nil then
		return false
	end

	if item.checkcooldown ~= nil
		or item.get_cooldown_percent ~= nil
		or item.get_active_duration_percent ~= nil
		or item.get_spell_state ~= nil
		or item.checkenabled ~= nil then
		return true
	end

	local widget = item.widget
	if widget ~= nil and widget.cooldown ~= nil then
		local state = widget.cooldown._skilltree_state
		if state ~= nil and state.visible == true then
			return true
		end
	end

	return M.GetSnapshot(item, owner).state ~= M.STATE.READY
end

function M.BindToggleSpellItem(item, get_state_fn, get_cooldown_fn, get_active_duration_fn)
	if item == nil then
		return item
	end

	item.spell_toggle = true
	item.get_spell_state = get_state_fn
	item.get_cooldown_percent = get_cooldown_fn
	item.get_active_duration_percent = get_active_duration_fn
	item.cooldownscale = item.cooldownscale or 1.42
	item.cooldowncolor = item.cooldowncolor or M.COLORS.COOLDOWN

	return item
end

function M.BindActiveSpellItem(item, get_state_fn, get_cooldown_fn)
	if item == nil then
		return item
	end

	item.spell_toggle = false
	item.get_spell_state = get_state_fn
	item.get_cooldown_percent = get_cooldown_fn
	item.cooldownscale = item.cooldownscale or 1.42
	item.cooldowncolor = item.cooldowncolor or M.COLORS.COOLDOWN

	return item
end

M.ACTIVE_OVERLAY_PERCENT = V.SHADOW_STALKER_ACTIVE_OVERLAY_PERCENT
		or V.DOMAIN_EXPANSION_ACTIVE_OVERLAY_PERCENT
		or M.FULL_OVERLAY

return M
