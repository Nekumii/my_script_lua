local C = require("reticule/constants")
local ReticuleUtils = require("reticule/utils")

local M = {}

local debug_state = {
	reticules = {},
}

local function PruneDebugReticules()
	local kept = {}
	for _, inst in ipairs(debug_state.reticules) do
		if inst ~= nil and inst:IsValid() then
			table.insert(kept, inst)
		end
	end
	debug_state.reticules = kept
end

function M.IsValidScale(scale)
	return ReticuleUtils.IsValidScale(scale)
end

function M.GetWorkRadiusForScale(anim_key, scale)
	local anim = C.DEBUG_ANIM_KEY[anim_key] or anim_key
	return ReticuleUtils.GetWorkRadius(scale, anim)
end

function M.GetInfoLine()
	PruneDebugReticules()

	local small_count = 0
	local large_count = 0
	for _, inst in ipairs(debug_state.reticules) do
		if inst._skilltree_debug_reticule_anim == C.ANIM_SMALL then
			small_count = small_count + 1
		else
			large_count = large_count + 1
		end
	end

	if small_count == 0 and large_count == 0 then
		return nil
	end

	return string.format("Reticule : Small %d / Large %d", small_count, large_count)
end

function M.Spawn(anim_key, scale, spawn_x, spawn_z)
	local anim = C.DEBUG_ANIM_KEY[anim_key]
	if anim == nil then
		return false, "invalid anim"
	end

	if not ReticuleUtils.IsValidScale(scale) then
		return false, "invalid scale"
	end

	if spawn_x == nil or spawn_z == nil then
		return false, "no position"
	end

	local inst = ReticuleUtils.SpawnGroundReticule(scale, anim, spawn_x, spawn_z)
	if inst == nil then
		return false, "spawn failed"
	end

	table.insert(debug_state.reticules, inst)
	return true, inst
end

function M.Clear()
	PruneDebugReticules()

	local removed = #debug_state.reticules
	for _, inst in ipairs(debug_state.reticules) do
		if inst:IsValid() then
			inst:Remove()
		end
	end
	debug_state.reticules = {}

	return removed
end

return M
