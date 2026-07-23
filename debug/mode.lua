local M = {}
local modglobals = rawget(_G, "GLOBAL") or _G
local AddPrefabPostInit = rawget(modglobals, "AddPrefabPostInit")
local AddPlayerPostInit = rawget(modglobals, "AddPlayerPostInit")
local AddClassPostConstruct = rawget(modglobals, "AddClassPostConstruct")
local net_bool = rawget(modglobals, "net_bool")
local string = rawget(modglobals, "string") or string
local rawset = rawget(modglobals, "rawset") or rawset
local require = rawget(modglobals, "require") or require
local math = rawget(modglobals, "math") or math
local table = rawget(modglobals, "table") or table
local ipairs = rawget(modglobals, "ipairs") or ipairs
local pairs = rawget(modglobals, "pairs") or pairs

local SKILL_TEST_COOLDOWN = 1
local SKILL_INFO_TAG = "skilltree_debug_skill_info"
local SKILL_INFO_NETVAR_NAME = "skilltree_debug.skill_info_enabled"
local SKILL_INFO_NETVAR_DIRTY = "skilltree_debug_skill_info_dirty"
local SKILL_ALL_NETVAR_NAME = "skilltree_debug.skill_all_enabled"
local SKILL_ALL_NETVAR_DIRTY = "skilltree_debug_skill_all_dirty"
local SKILL_INFO_WIDGET_X = 240
local SKILL_INFO_WIDGET_Y = -205
local SKILL_INFO_REFRESH_INTERVAL = .5
local reticule_constants = require("reticule/constants")
local reticule_utils = require("reticule/utils")
local reticule_debug = require("debug/reticule")
local debug_state = {
	shadows = {},
	fires = {},
}
local DEBUG_SHADOW_TAG = "skilltree_debug_shadow"
local DEBUG_SHADOW_RANGE_MIN = .1
local DEBUG_SHADOW_RANGE_MAX = 100
local DEBUG_FIRE_TAG = "skilltree_debug_fire"
local DEBUG_FIRE_SCALE_MIN = .1
local DEBUG_FIRE_SCALE_MAX = 10
-- Vanilla willow_shadow_fire_explode uses Transform scale 1.5.
local DEBUG_FIRE_VANILLA_SCALE = 1.5
local DEBUG_FIRE_CLEAR_COMMANDS = {
	skill_reticule_fire_clear = true,
	skill_reticule_fire_remove = true,
	skill_reticule_fire_delete = true,
}
local DEBUG_SHADOW_DIRECTION_COMMANDS = {
	skill_reticule_shadow_left = "left",
	skill_reticule_shadow_right = "right",
	skill_reticule_shadow_up = "up",
	skill_reticule_shadow_down = "down",
	skill_reticule_shadow_center = "center",
}
local DEBUG_SHADOW_CLEAR_COMMANDS = {
	skill_reticule_shadow_clear = true,
	skill_reticule_shadow_remove = true,
	skill_reticule_shadow_delete = true,
}
local DEBUG_SHADOW_WALK_STOP_DIST = .25
local DEBUG_SHADOW_MOVE_SPEED = 6
local skill_debug_console_commands_installed = false
local emperor_variables = require("skill_effect/waxwell/emperor/_shared/variables")
local umbra_variables = require("skill_effect/waxwell/umbra/_shared/variables")
local skilltree_defs = require("prefabs/skilltree_defs")

local cached_puppeteer_common
local cached_spell_utils
local cached_emperor_common
local cached_domain_expansion
local cached_umbra_common
local cached_sovereign_common
local AttachSkillInfoWidgetToControls
local EnsureCurrentPlayerSkillInfoHUD

local function GetPuppeteerCommon()
	if cached_puppeteer_common == nil then
		cached_puppeteer_common = require("skill_effect/waxwell/puppeteer/_shared/common")
	end
	return cached_puppeteer_common
end

local function GetSpellUtils()
	if cached_spell_utils == nil then
		cached_spell_utils = require("skill_effect/waxwell/_shared/codex_spell_utils")
	end
	return cached_spell_utils
end

local function GetEmperorCommon()
	if cached_emperor_common == nil then
		cached_emperor_common = require("skill_effect/waxwell/emperor/_shared/common")
	end
	return cached_emperor_common
end

local function GetDomainExpansion()
	if cached_domain_expansion == nil then
		cached_domain_expansion = require("skill_effect/waxwell/emperor/domain_expansion/common")
	end
	return cached_domain_expansion
end

local function GetUmbraCommon()
	if cached_umbra_common == nil then
		cached_umbra_common = require("skill_effect/waxwell/umbra/_shared/common")
	end
	return cached_umbra_common
end

local function GetSovereignCommon()
	if cached_sovereign_common == nil then
		cached_sovereign_common = require("skill_effect/waxwell/sovereign/_shared/common")
	end
	return cached_sovereign_common
end

local function GetTrackedSkills()
	local emperor_common = GetEmperorCommon()
	local domain_expansion = GetDomainExpansion()
	local umbra_common = GetUmbraCommon()

	return {
		{
			label = "Shadow Stalker",
			cooldown_id = emperor_common.SHADOW_STALKER_COOLDOWN_ID,
			get_state = function(owner)
				return emperor_common.GetShadowStalkerSpellState(owner)
			end,
		},
		{
			label = "Domain Expansion",
			cooldown_id = emperor_variables.DOMAIN_EXPANSION_COOLDOWN_ID,
			get_state = function(owner)
				return domain_expansion.GetDomainExpansionSpellState ~= nil and domain_expansion.GetDomainExpansionSpellState(owner) or nil
			end,
		},
		{
			label = "Fissure Eruption",
			cooldown_id = emperor_variables.FISSURE_ERUPTION_COOLDOWN_ID,
			get_state = function(owner)
				return emperor_common.GetFissureEruptionSpellState ~= nil and emperor_common.GetFissureEruptionSpellState(owner) or nil
			end,
		},
		{
			label = "Umbral Rift",
			cooldown_id = umbra_variables.UMBRAL_RIFT_COOLDOWN_ID,
			is_available = function(inst)
				return umbra_common.IsUmbralRiftSkillActive == nil or umbra_common.IsUmbralRiftSkillActive(inst)
			end,
		},
		{
			label = "Eclipse Fall",
			cooldown_id = umbra_common.ECLIPSE_FALL_COOLDOWN_ID,
			is_available = function(inst)
				return umbra_common.IsEclipseFallSkillActive == nil or umbra_common.IsEclipseFallSkillActive(inst)
			end,
		},
		{
			label = "Shadow Sneak",
			cooldown_id = umbra_variables.SHADOW_TRAP_COOLDOWN_ID,
			is_available = function()
				return require("mod_config").IsWaxwellUmbraBaseSpellCooldownFixEnabled()
			end,
		},
		{
			label = "Shadow Prison",
			cooldown_id = umbra_variables.SHADOW_PILLARS_COOLDOWN_ID,
			is_available = function()
				return require("mod_config").IsWaxwellUmbraBaseSpellCooldownFixEnabled()
			end,
		},
		}
end

local function GetGlobalState()
	return debug_state
end

local function IsEnabled(flag)
	local state = GetGlobalState()
	return state[flag] == true
end

local function SetEnabled(flag, enabled)
	local state = GetGlobalState()
	state[flag] = enabled == true or nil
	return state[flag] == true
end

local function PrintState(flag, enabled)
end

local function PrintDebugMessage(message)
	if message ~= nil then
		print(message)
	end
end

local function GetCurrentPlayer()
	return rawget(modglobals, "ThePlayer") or rawget(_G, "ThePlayer")
end

local function ParseConsoleCommandName(fnstr)
	if fnstr == nil then
		return nil
	end

	local cmd = string.match(fnstr, "^%s*([%w_.]+)%s*%(") or string.match(fnstr, "^%s*([%w_.]+)%s*$")
	if cmd == nil then
		return nil
	end

	return (cmd:gsub("^%s+", "")):gsub("%s+$", "")
end

local function ParseShadowRangeCommand(cmd)
	if cmd == nil then
		return nil
	end

	local range_str = string.match(cmd, "^skill_reticule_shadow(%d+%.?%d*)$")
		or string.match(cmd, "^skill_reticule_shadow(%d*%.%d+)$")
	if range_str == nil or range_str == "" then
		return nil
	end

	return tonumber(range_str)
end

local function ParseSkillReticuleScale(scale_str)
	if scale_str == nil or scale_str == "" then
		return nil
	end
	return tonumber(scale_str)
end

local function IsValidSkillReticuleScale(scale)
	return reticule_debug.IsValidScale(scale)
end

local function GetShadowRangeForReticuleScale(anim_key, scale)
	return reticule_debug.GetWorkRadiusForScale(anim_key, scale)
end

local function GetConsoleMouseWorldPosition()
	local console_world_position = rawget(modglobals, "ConsoleWorldPosition")
	if console_world_position ~= nil then
		local pos = console_world_position()
		if pos ~= nil then
			return pos.x, pos.z
		end
	end

	local theinput = rawget(modglobals, "TheInput")
	if theinput ~= nil and theinput.GetWorldPosition ~= nil then
		local pos = theinput:GetWorldPosition()
		if pos ~= nil then
			return pos.x, pos.z
		end
	end

	return nil, nil
end

local function FormatDebugShadowRange(range)
	if range == nil then
		return "?"
	end

	local rounded = math.floor(range * 100 + .5) / 100
	if rounded == math.floor(rounded) then
		return string.format("%d", rounded)
	end

	local formatted = string.format("%.2f", rounded)
	return formatted:gsub("0+$", ""):gsub("%.$", "")
end

local function PruneDebugShadows()
	local kept = {}
	for _, inst in ipairs(debug_state.shadows or {}) do
		if inst ~= nil and inst:IsValid() then
			table.insert(kept, inst)
		end
	end
	debug_state.shadows = kept
end

local function GetDebugShadowInfoLine()
	PruneDebugShadows()

	if #(debug_state.shadows or {}) == 0 then
		return nil
	end

	local counts_by_range = {}
	for _, inst in ipairs(debug_state.shadows) do
		local range = inst._skilltree_debug_shadow_range or 0
		counts_by_range[range] = (counts_by_range[range] or 0) + 1
	end

	local ranges = {}
	for range in pairs(counts_by_range) do
		table.insert(ranges, range)
	end
	table.sort(ranges, function(a, b)
		return a < b
	end)

	local parts = {}
	for _, range in ipairs(ranges) do
		table.insert(parts, string.format("%s x%d", FormatDebugShadowRange(range), counts_by_range[range]))
	end

	return string.format("Shadow Reticule : %s", table.concat(parts, " / "))
end

local function GetDebugShadowMoveStep()
	local frames = rawget(modglobals, "FRAMES") or (1 / 30)
	return DEBUG_SHADOW_MOVE_SPEED * frames
end

local function PlayDebugShadowIdle(inst)
	if inst.AnimState ~= nil then
		inst.AnimState:PlayAnimation("idle_loop", true)
	end
end

local function PlayDebugShadowRun(inst)
	if inst.AnimState ~= nil then
		inst.AnimState:PlayAnimation("run_loop", true)
	end
end

local function FaceDebugShadowPoint(inst, target_x, target_z)
	if inst == nil or not inst:IsValid() or inst.Transform == nil then
		return
	end

	local x, y, z = inst.Transform:GetWorldPosition()
	local dx = target_x - x
	local dz = target_z - z
	if dx * dx + dz * dz <= 0 then
		return
	end

	local radians = rawget(modglobals, "RADIANS") or (180 / math.pi)
	inst.Transform:SetRotation(math.atan2(-dz, dx) * radians)
end

local function CreateDebugShadowVisual(home_x, home_z, range)
	local inst = CreateEntity()

	inst.entity:AddTransform()
	inst.entity:AddAnimState()

	inst:AddTag("FX")
	inst:AddTag("NOCLICK")
	inst:AddTag(DEBUG_SHADOW_TAG)
	inst.entity:SetCanSleep(false)
	inst.persists = false

	inst.Transform:SetFourFaced()

	inst.AnimState:SetBank("wilson")
	inst.AnimState:SetBuild("waxwell")
	inst.AnimState:OverrideSymbol("swap_object", "swap_nightmaresword_shadow", "swap_nightmaresword_shadow")
	inst.AnimState:Hide("ARM_normal")
	inst.AnimState:Hide("HAT")
	inst.AnimState:Hide("HAIR_HAT")
	inst.AnimState:SetMultColour(0, 0, 0, .5)
	if inst.AnimState.UsePointFiltering ~= nil then
		inst.AnimState:UsePointFiltering(true)
	end
	inst.AnimState:PlayAnimation("idle_loop", true)

	inst._skilltree_debug_shadow_range = range
	inst._skilltree_debug_shadow_home_x = home_x
	inst._skilltree_debug_shadow_home_z = home_z
	inst._skilltree_debug_shadow_ready = true

	inst.Transform:SetPosition(home_x, 0, home_z)

	return inst
end

local function ClampDebugShadowPosition(inst)
	local home_x = inst._skilltree_debug_shadow_home_x
	local home_z = inst._skilltree_debug_shadow_home_z
	local range = inst._skilltree_debug_shadow_range
	if home_x == nil or home_z == nil or range == nil then
		return
	end

	local x, y, z = inst.Transform:GetWorldPosition()
	local dx, dz = x - home_x, z - home_z
	local dist_sq = dx * dx + dz * dz
	if dist_sq > range * range and dist_sq > 0 then
		local dist = math.sqrt(dist_sq)
		inst.Transform:SetPosition(home_x + dx / dist * range, y, home_z + dz / dist * range)
	end
end

local function StopDebugShadowMove(inst)
	if inst == nil then
		return
	end

	inst._skilltree_debug_shadow_move_id = nil

	if inst._skilltree_debug_shadow_movetask ~= nil then
		inst._skilltree_debug_shadow_movetask:Cancel()
		inst._skilltree_debug_shadow_movetask = nil
	end

	if inst:IsValid() then
		PlayDebugShadowIdle(inst)
	end
end

local function StartDebugShadowMove(inst, target_x, target_z)
	if inst == nil or not inst:IsValid() then
		return false
	end

	StopDebugShadowMove(inst)

	if inst._skilltree_debug_shadow_home_x == nil or inst._skilltree_debug_shadow_range == nil then
		return false
	end

	local theworld = rawget(modglobals, "TheWorld") or rawget(_G, "TheWorld")
	if theworld == nil then
		return false
	end

	debug_state.shadow_move_id = (debug_state.shadow_move_id or 0) + 1
	local move_id = debug_state.shadow_move_id
	inst._skilltree_debug_shadow_move_id = move_id

	PlayDebugShadowRun(inst)
	FaceDebugShadowPoint(inst, target_x, target_z)

	inst._skilltree_debug_shadow_movetask = theworld:DoPeriodicTask(0, function()
		if not inst:IsValid() or inst._skilltree_debug_shadow_move_id ~= move_id then
			return
		end

		local x, y, z = inst.Transform:GetWorldPosition()
		local dx = target_x - x
		local dz = target_z - z
		local dist_sq = dx * dx + dz * dz

		if dist_sq <= DEBUG_SHADOW_WALK_STOP_DIST * DEBUG_SHADOW_WALK_STOP_DIST then
			inst.Transform:SetPosition(target_x, y, target_z)
			ClampDebugShadowPosition(inst)
			StopDebugShadowMove(inst)
			return
		end

		local dist = math.sqrt(dist_sq)
		local step = GetDebugShadowMoveStep()
		local move = math.min(step, dist)
		inst.Transform:SetPosition(x + dx / dist * move, y, z + dz / dist * move)
		ClampDebugShadowPosition(inst)
		FaceDebugShadowPoint(inst, target_x, target_z)
		PlayDebugShadowRun(inst)
	end)

	return true
end

local function GetDebugShadowMoveTarget(inst, direction)
	local home_x = inst._skilltree_debug_shadow_home_x
	local home_z = inst._skilltree_debug_shadow_home_z
	local range = inst._skilltree_debug_shadow_range
	if home_x == nil or home_z == nil or range == nil then
		return nil, nil
	end

	if direction == "center" then
		return home_x, home_z
	elseif direction == "left" then
		return home_x - range, home_z
	elseif direction == "right" then
		return home_x + range, home_z
	elseif direction == "up" then
		return home_x, home_z + range
	elseif direction == "down" then
		return home_x, home_z - range
	end

	return home_x, home_z
end

local function SpawnSkillDebugShadow(range)
	if range == nil or range < DEBUG_SHADOW_RANGE_MIN or range > DEBUG_SHADOW_RANGE_MAX then
		PrintDebugMessage(string.format(
			"skill_reticule_shadow: invalid range, use %.1f to %d",
			DEBUG_SHADOW_RANGE_MIN,
			DEBUG_SHADOW_RANGE_MAX
		))
		return false
	end

	local home_x, home_z = GetConsoleMouseWorldPosition()
	if home_x == nil or home_z == nil then
		PrintDebugMessage("skill_reticule_shadow: no mouse world position")
		return false
	end

	local inst = CreateDebugShadowVisual(home_x, home_z, range)
	if inst == nil then
		PrintDebugMessage("skill_reticule_shadow: spawn failed")
		return false
	end

	debug_state.shadows = debug_state.shadows or {}
	table.insert(debug_state.shadows, inst)

	PrintDebugMessage(string.format(
		"skill_reticule_shadow: spawned range %.2f at mouse position",
		range
	))
	return true
end

local function CommandDebugShadows(direction)
	PruneDebugShadows()

	local moved = 0
	for _, inst in ipairs(debug_state.shadows) do
		if inst:IsValid() then
			local target_x, target_z = GetDebugShadowMoveTarget(inst, direction)
			if target_x ~= nil and target_z ~= nil and StartDebugShadowMove(inst, target_x, target_z) then
				moved = moved + 1
			end
		end
	end

	if moved > 0 then
		PrintDebugMessage(string.format("skill_reticule_shadow_%s: %d shadow(s)", direction, moved))
	elseif #(debug_state.shadows or {}) == 0 then
		PrintDebugMessage("skill_reticule_shadow: no debug shadow reticule to move")
	end
	return moved > 0
end

local function ClearSkillDebugShadows()
	PruneDebugShadows()

	local removed = #debug_state.shadows
	for _, inst in ipairs(debug_state.shadows) do
		if inst:IsValid() then
			StopDebugShadowMove(inst)
			inst:Remove()
		end
	end
	debug_state.shadows = {}

	if removed > 0 then
		PrintDebugMessage(string.format("skill_reticule_shadow: removed %d debug shadow reticule(s)", removed))
	end
	return removed
end

local function GetDebugReticuleInfoLine()
	return reticule_debug.GetInfoLine()
end

local function SpawnSkillDebugReticule(anim_key, scale)
	if anim_key ~= "s" and anim_key ~= "l" then
		PrintDebugMessage("skill_reticule: invalid anim, use 's' (idle_small) or 'l' (idle_1d2_12)")
		return false
	end

	if scale == nil or not IsValidSkillReticuleScale(scale) then
		PrintDebugMessage(string.format(
			"skill_reticule: invalid scale, use %.1f to %d (e.g. skill_reticule_s0.5, skill_reticule_l1.75)",
			reticule_constants.DEBUG_SCALE_MIN,
			reticule_constants.DEBUG_SCALE_MAX
		))
		return false
	end

	local spawn_x, spawn_z = GetConsoleMouseWorldPosition()
	if spawn_x == nil or spawn_z == nil then
		PrintDebugMessage("skill_reticule: no mouse world position")
		return false
	end

	local ok, result = reticule_debug.Spawn(anim_key, scale, spawn_x, spawn_z)
	if not ok then
		if result == "invalid scale" then
			PrintDebugMessage(string.format(
				"skill_reticule: invalid scale, use %.1f to %d (e.g. skill_reticule_s0.5, skill_reticule_l1.75)",
				reticule_constants.DEBUG_SCALE_MIN,
				reticule_constants.DEBUG_SCALE_MAX
			))
		elseif result == "no position" then
			PrintDebugMessage("skill_reticule: no mouse world position")
		else
			PrintDebugMessage("skill_reticule: spawn failed")
		end
		return false
	end

	local shadow_range = GetShadowRangeForReticuleScale(anim_key, scale)
	PrintDebugMessage(string.format(
		"skill_reticule: spawned %s scale %.2f at mouse (shadow range ~%s)",
		anim_key == "s" and "Small" or "Large",
		scale,
		FormatDebugShadowRange(shadow_range)
	))
	return true
end

local function ClearSkillDebugReticules()
	local removed = reticule_debug.Clear()
	if removed > 0 then
		PrintDebugMessage(string.format("skill_reticule: removed %d debug reticule(s)", removed))
	end
	return removed
end

local function PruneDebugFires()
	local kept = {}
	for _, inst in ipairs(debug_state.fires or {}) do
		if inst ~= nil and inst:IsValid() then
			table.insert(kept, inst)
		end
	end
	debug_state.fires = kept
end

local function GetDebugFireInfoLine()
	PruneDebugFires()

	if #(debug_state.fires or {}) == 0 then
		return nil
	end

	local counts_by_scale = {}
	for _, inst in ipairs(debug_state.fires) do
		local scale = inst._skilltree_debug_fire_scale or 0
		counts_by_scale[scale] = (counts_by_scale[scale] or 0) + 1
	end

	local scales = {}
	for scale in pairs(counts_by_scale) do
		table.insert(scales, scale)
	end
	table.sort(scales, function(a, b)
		return a < b
	end)

	local parts = {}
	for _, scale in ipairs(scales) do
		table.insert(parts, string.format("%s x%d", FormatDebugShadowRange(scale), counts_by_scale[scale]))
	end

	return string.format("Fire Explode : %s", table.concat(parts, " / "))
end

local function CreateDebugFireExplodeVisual(spawn_x, spawn_z, scale)
	local inst = CreateEntity()

	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddSoundEmitter()

	inst:AddTag("FX")
	inst:AddTag("NOCLICK")
	inst:AddTag(DEBUG_FIRE_TAG)
	inst.entity:SetCanSleep(false)
	inst.persists = false

	-- Mirror willow_shadow_fire_explode (fx.lua): deer_fire_charge blast, black tint.
	inst.AnimState:SetBank("deer_fire_charge")
	inst.AnimState:SetBuild("deer_fire_charge")
	inst.AnimState:SetMultColour(0, 0, 0, .6)
	inst.AnimState:PlayAnimation("blast")
	inst.Transform:SetScale(scale, scale, scale)
	inst.Transform:SetPosition(spawn_x, 0, spawn_z)

	inst._skilltree_debug_fire_scale = scale

	local function ReplayBlast()
		if not inst:IsValid() then
			return
		end
		inst.AnimState:PlayAnimation("blast")
		if inst.SoundEmitter ~= nil then
			inst.SoundEmitter:PlaySound("dontstarve/common/deathpoof")
		end
	end

	inst:ListenForEvent("animover", ReplayBlast)
	if inst.SoundEmitter ~= nil then
		inst.SoundEmitter:PlaySound("dontstarve/common/deathpoof")
	end

	return inst
end

local function ParseFireScaleCommand(cmd)
	if cmd == nil then
		return nil
	end

	local scale_str = string.match(cmd, "^skill_reticule_fire(%d+%.?%d*)$")
		or string.match(cmd, "^skill_reticule_fire(%d*%.%d+)$")
	if scale_str == nil or scale_str == "" then
		return nil
	end

	return tonumber(scale_str)
end

local function SpawnSkillDebugFire(scale)
	if scale == nil or scale < DEBUG_FIRE_SCALE_MIN or scale > DEBUG_FIRE_SCALE_MAX then
		PrintDebugMessage(string.format(
			"skill_reticule_fire: invalid scale, use %.1f to %d (vanilla willow_shadow_fire_explode = %.1f)",
			DEBUG_FIRE_SCALE_MIN,
			DEBUG_FIRE_SCALE_MAX,
			DEBUG_FIRE_VANILLA_SCALE
		))
		return false
	end

	local spawn_x, spawn_z = GetConsoleMouseWorldPosition()
	if spawn_x == nil or spawn_z == nil then
		PrintDebugMessage("skill_reticule_fire: no mouse world position")
		return false
	end

	local inst = CreateDebugFireExplodeVisual(spawn_x, spawn_z, scale)
	if inst == nil then
		PrintDebugMessage("skill_reticule_fire: spawn failed")
		return false
	end

	debug_state.fires = debug_state.fires or {}
	table.insert(debug_state.fires, inst)

	PrintDebugMessage(string.format(
		"skill_reticule_fire: looping willow_shadow_fire_explode scale %.2f at mouse (vanilla=%.1f)",
		scale,
		DEBUG_FIRE_VANILLA_SCALE
	))
	return true
end

local function ClearSkillDebugFires()
	PruneDebugFires()

	local removed = #debug_state.fires
	for _, inst in ipairs(debug_state.fires) do
		if inst:IsValid() then
			inst:Remove()
		end
	end
	debug_state.fires = {}

	if removed > 0 then
		PrintDebugMessage(string.format("skill_reticule_fire: removed %d debug fire explode(s)", removed))
	end
	return removed
end

-- Spawns a Shadow Reliquary sunken chest at the mouse (host only).
local function SpawnSkillDebugChestAtMouse(tier_key)
	local theworld = rawget(modglobals, "TheWorld") or rawget(_G, "TheWorld")
	if theworld == nil or not theworld.ismastersim then
		PrintDebugMessage("skill_chest_" .. tier_key:sub(1, 1) .. ": requires host / mastersim")
		return false
	end

	local spawn_x, spawn_z = GetConsoleMouseWorldPosition()
	if spawn_x == nil or spawn_z == nil then
		PrintDebugMessage("skill_chest_" .. tier_key:sub(1, 1) .. ": no mouse world position")
		return false
	end

	local player = rawget(modglobals, "ThePlayer") or rawget(_G, "ThePlayer")
	local ok, common = pcall(require, "skill_effect/waxwell/emperor/shadow_reliquary/common")
	local chest = nil
	if ok and common ~= nil and common.SpawnShadowReliquaryChest ~= nil then
		chest = common.SpawnShadowReliquaryChest(
			player,
			spawn_x,
			spawn_z,
			player ~= nil and player.userid or nil,
			tier_key
		)
	end

	local cmd = "skill_chest_" .. tier_key:sub(1, 1)
	if chest == nil then
		PrintDebugMessage(cmd .. ": spawn failed")
		return false
	end

	PrintDebugMessage(string.format(
		"%s: spawned %s at mouse (%.1f, %.1f) owner=%s",
		cmd,
		tier_key,
		spawn_x,
		spawn_z,
		(player ~= nil and player.userid) or "nil"
	))
	return true
end

local function SpawnSkillDebugChestS()
	return SpawnSkillDebugChestAtMouse("small")
end

local function SpawnSkillDebugChestM()
	return SpawnSkillDebugChestAtMouse("medium")
end

local function SpawnSkillDebugChestL()
	return SpawnSkillDebugChestAtMouse("large")
end

-- Forces small/medium/large chest waves on the active Shadow Reliquary base
-- (tier spawn rules + intro FX; not at mouse).
local function SpawnSkillDebugChestAuto()
	local theworld = rawget(modglobals, "TheWorld") or rawget(_G, "TheWorld")
	if theworld == nil or not theworld.ismastersim then
		PrintDebugMessage("skill_chest_auto: requires host / mastersim")
		return false
	end

	local player = rawget(modglobals, "ThePlayer") or rawget(_G, "ThePlayer")
	local ok, common = pcall(require, "skill_effect/waxwell/emperor/shadow_reliquary/common")
	if not ok or common == nil or common.GetShadowReliquaryBase == nil then
		PrintDebugMessage("skill_chest_auto: failed to load shadow reliquary common")
		return false
	end

	local base = common.GetShadowReliquaryBase(player)
	if base == nil or not base:IsValid() or base.ForceSpawnChestTier == nil then
		PrintDebugMessage("skill_chest_auto: no active Shadow Reliquary base for current player")
		return false
	end

	local tiers = { "small", "medium", "large" }
	local parts = {}
	local any = false
	for _, tier in ipairs(tiers) do
		local spawned = base:ForceSpawnChestTier(tier) == true
		if spawned then
			any = true
		end
		table.insert(parts, tier .. "=" .. (spawned and "ok" or "skip"))
	end

	PrintDebugMessage("skill_chest_auto: " .. table.concat(parts, ", "))
	return any
end

local function ClearAllSkillDebugChests()
	local theworld = rawget(modglobals, "TheWorld") or rawget(_G, "TheWorld")
	if theworld == nil or not theworld.ismastersim then
		PrintDebugMessage("skill_chest_clear: requires host / mastersim")
		return false
	end

	local count = 0
	for _, ent in pairs(Ents) do
		if ent ~= nil
			and ent:IsValid()
			and ent:HasTag("waxwell_shadow_sunken_chest") then
			local x, y, z = ent.Transform:GetWorldPosition()
			local fx = SpawnPrefab("shadow_despawn")
			if fx ~= nil then
				fx.Transform:SetPosition(x, y, z)
			end
			ent:Remove()
			count = count + 1
		end
	end

	PrintDebugMessage("skill_chest_clear: removed " .. tostring(count) .. " chest(s)")
	return count > 0
end

local function TryRunSkillSpawnChestConsoleCommand(fnstr)
	local cmd = ParseConsoleCommandName(fnstr)
	if cmd == "skill_chest_s" then
		SpawnSkillDebugChestS()
		return true
	end
	if cmd == "skill_chest_m" then
		SpawnSkillDebugChestM()
		return true
	end
	if cmd == "skill_chest_l" then
		SpawnSkillDebugChestL()
		return true
	end
	return false
end

local function TryRunSkillChestAutoConsoleCommand(fnstr)
	local cmd = ParseConsoleCommandName(fnstr)
	if cmd ~= "skill_chest_auto" then
		return false
	end
	SpawnSkillDebugChestAuto()
	return true
end

local function TryRunSkillChestClearConsoleCommand(fnstr)
	local cmd = ParseConsoleCommandName(fnstr)
	if cmd ~= "skill_chest_clear" then
		return false
	end
	ClearAllSkillDebugChests()
	return true
end

local function TryRunSkillReticuleConsoleCommand(fnstr)
	if fnstr == nil then
		return false
	end

	local cmd = ParseConsoleCommandName(fnstr)
	if cmd == nil then
		return false
	end

	if string.match(cmd, "^skill_reticule_shadow") then
		if DEBUG_SHADOW_CLEAR_COMMANDS[cmd] then
			ClearSkillDebugShadows()
			return true
		end

		local direction = DEBUG_SHADOW_DIRECTION_COMMANDS[cmd]
		if direction ~= nil then
			CommandDebugShadows(direction)
			return true
		end

		local range = ParseShadowRangeCommand(cmd)
		if range ~= nil then
			SpawnSkillDebugShadow(range)
			return true
		end

		if cmd == "skill_reticule_shadow" then
			PrintDebugMessage(string.format(
				"skill_reticule_shadow: use skill_reticule_shadow[range] (%.1f-%d) or _left/_right/_up/_down/_center",
				DEBUG_SHADOW_RANGE_MIN,
				DEBUG_SHADOW_RANGE_MAX
			))
			return true
		end

		return false
	end

	if string.match(cmd, "^skill_reticule_fire") then
		if DEBUG_FIRE_CLEAR_COMMANDS[cmd] then
			ClearSkillDebugFires()
			return true
		end

		local scale = ParseFireScaleCommand(cmd)
		if scale ~= nil then
			SpawnSkillDebugFire(scale)
			return true
		end

		if cmd == "skill_reticule_fire" then
			PrintDebugMessage(string.format(
				"skill_reticule_fire: use skill_reticule_fire[scale] (%.1f-%d, vanilla=%.1f)",
				DEBUG_FIRE_SCALE_MIN,
				DEBUG_FIRE_SCALE_MAX,
				DEBUG_FIRE_VANILLA_SCALE
			))
			return true
		end

		PrintDebugMessage(string.format(
			"skill_reticule_fire: invalid scale, use %.1f to %d (e.g. skill_reticule_fire%.1f)",
			DEBUG_FIRE_SCALE_MIN,
			DEBUG_FIRE_SCALE_MAX,
			DEBUG_FIRE_VANILLA_SCALE
		))
		return true
	end

	if not string.match(cmd, "^skill_reticule_") then
		return false
	end

	if cmd == "skill_reticule_clear" or cmd == "skill_reticule_remove" or cmd == "skill_reticule_delete" then
		ClearSkillDebugReticules()
		return true
	end

	local anim_key, scale_str = string.match(cmd, "^skill_reticule_([sl])(%d*%.?%d+)$")
	if anim_key ~= nil and scale_str ~= nil then
		SpawnSkillDebugReticule(anim_key, ParseSkillReticuleScale(scale_str))
		return true
	end

	local anim_letter = string.match(cmd, "^skill_reticule_(.)")
	if anim_letter ~= "s" and anim_letter ~= "l" then
		PrintDebugMessage("skill_reticule: invalid anim, use 's' (idle_small) or 'l' (idle_1d2_12)")
	else
		PrintDebugMessage(string.format(
			"skill_reticule: invalid scale, use %.1f to %d (e.g. skill_reticule_s0.5, skill_reticule_l1.75)",
			reticule_constants.DEBUG_SCALE_MIN,
			reticule_constants.DEBUG_SCALE_MAX
		))
	end
	return true
end

local function InstallSkillDebugConsoleCommands()
	if skill_debug_console_commands_installed then
		return
	end
	skill_debug_console_commands_installed = true

	local g = modglobals
	rawset(g, "skill_reticule_clear", ClearSkillDebugReticules)
	rawset(g, "skill_reticule_remove", ClearSkillDebugReticules)
	rawset(g, "skill_reticule_delete", ClearSkillDebugReticules)
	rawset(g, "skill_reticule_shadow_left", function()
		return CommandDebugShadows("left")
	end)
	rawset(g, "skill_reticule_shadow_right", function()
		return CommandDebugShadows("right")
	end)
	rawset(g, "skill_reticule_shadow_up", function()
		return CommandDebugShadows("up")
	end)
	rawset(g, "skill_reticule_shadow_down", function()
		return CommandDebugShadows("down")
	end)
	rawset(g, "skill_reticule_shadow_center", function()
		return CommandDebugShadows("center")
	end)
	rawset(g, "skill_reticule_shadow_clear", ClearSkillDebugShadows)
	rawset(g, "skill_reticule_shadow_remove", ClearSkillDebugShadows)
	rawset(g, "skill_reticule_shadow_delete", ClearSkillDebugShadows)
	rawset(g, "skill_reticule_fire_clear", ClearSkillDebugFires)
	rawset(g, "skill_reticule_fire_remove", ClearSkillDebugFires)
	rawset(g, "skill_reticule_fire_delete", ClearSkillDebugFires)
	rawset(g, "skill_chest_s", SpawnSkillDebugChestS)
	rawset(g, "skill_chest_m", SpawnSkillDebugChestM)
	rawset(g, "skill_chest_l", SpawnSkillDebugChestL)
	rawset(g, "skill_chest_auto", SpawnSkillDebugChestAuto)
	rawset(g, "skill_chest_clear", ClearAllSkillDebugChests)

	local old_execute = rawget(g, "ExecuteConsoleCommand")
	if old_execute == nil then
		return
	end

	rawset(g, "ExecuteConsoleCommand", function(fnstr, guid, x, z)
		if TryRunSkillSpawnChestConsoleCommand(fnstr) then
			return
		end
		if TryRunSkillChestAutoConsoleCommand(fnstr) then
			return
		end
		if TryRunSkillChestClearConsoleCommand(fnstr) then
			return
		end
		if TryRunSkillReticuleConsoleCommand(fnstr) then
			return
		end
		return old_execute(fnstr, guid, x, z)
	end)
end

local function PrintSkillInfoTrace(message)
end

local function SetSkillAllState(player, enabled)
	if player == nil then
		return
	end

	player._skilltree_debug_skill_full_active = enabled == true or nil
	if player._skilltree_debug_skill_all_enabled ~= nil then
		player._skilltree_debug_skill_all_enabled:set(enabled == true)
	end
end

local function GetActiveSkillNames(skilltreeupdater)
	local names = {}
	local activatedskills = skilltreeupdater ~= nil and skilltreeupdater.GetActivatedSkills ~= nil and skilltreeupdater:GetActivatedSkills() or nil
	if activatedskills ~= nil then
		for skill, enabled in pairs(activatedskills) do
			if enabled then
				table.insert(names, skill)
			end
		end
	end
	return names
end

local function GetAvailableSkillPoints(skilltreeupdater)
	return skilltreeupdater ~= nil and skilltreeupdater.GetAvailableSkillPoints ~= nil and skilltreeupdater:GetAvailableSkillPoints() or 0
end

local function GetAllocatedSkillCount(skilltreeupdater)
	return #GetActiveSkillNames(skilltreeupdater)
end

local function GetTotalSkillPoints(skilltreeupdater)
	return math.max(0, GetAvailableSkillPoints(skilltreeupdater) + GetAllocatedSkillCount(skilltreeupdater))
end

local function GetAllUpgradeableSkillNames(prefab)
	local defs = prefab ~= nil and skilltree_defs.SKILLTREE_DEFS[prefab] or nil
	if defs == nil then
		return {}
	end

	local names = {}
	for skill_name, skill_data in pairs(defs) do
		if skill_data ~= nil and skill_data.rpc_id ~= nil then
			table.insert(names, skill_name)
		end
	end
	table.sort(names)
	return names
end

local function GetUpgradeableSkillCount(prefab)
	local metainfo = prefab ~= nil and skilltree_defs.SKILLTREE_METAINFO[prefab] or nil
	if metainfo ~= nil and metainfo.TOTAL_SKILLS_COUNT ~= nil then
		return metainfo.TOTAL_SKILLS_COUNT
	end
	return #GetAllUpgradeableSkillNames(prefab)
end

local function EnsureSkillFullSaveGuard(player, skilltreeupdater)
	if player == nil or skilltreeupdater == nil or skilltreeupdater.skilltree == nil then
		return
	end

	local skilltree = skilltreeupdater.skilltree
	if not skilltree._skilltree_debug_skill_full_save_guarded then
		skilltree._skilltree_debug_skill_full_save_guarded = true
		skilltree._skilltree_debug_original_UpdateSaveState = skilltree.UpdateSaveState
		skilltree.UpdateSaveState = function(self, characterprefab)
			if player._skilltree_debug_skill_full_active then
				self.dirty = true
				return true
			end

			return self:_skilltree_debug_original_UpdateSaveState(characterprefab)
		end

		skilltree._skilltree_debug_original_Save = skilltree.Save
		skilltree.Save = function(self, force_save, characterprefab)
			if player._skilltree_debug_skill_full_active then
				return
			end

			return self:_skilltree_debug_original_Save(force_save, characterprefab)
		end
	end

	if not skilltreeupdater._skilltree_debug_skill_full_save_guarded then
		skilltreeupdater._skilltree_debug_skill_full_save_guarded = true
		skilltreeupdater._skilltree_debug_original_OnSave = skilltreeupdater.OnSave
		skilltreeupdater.OnSave = function(self)
			if self.inst ~= nil and self.inst._skilltree_debug_skill_full_active and self.inst._skilltree_debug_skill_full_restore_blob ~= nil then
				return {
					skilltreeblob = self.inst._skilltree_debug_skill_full_restore_blob,
					skilltreeblobprefab = self.inst.prefab,
				}
			end

			return self:_skilltree_debug_original_OnSave()
		end
	end
end

local function RemoveAllCurrentSkills(skilltreeupdater, skip_validation)
	if skilltreeupdater == nil then
		return 0, 0
	end

	if skip_validation then
		skilltreeupdater:SetSkipValidation(true)
	end

	local removed_count = 0
	for _ = 1, 32 do
		local active_skills = GetActiveSkillNames(skilltreeupdater)
		if #active_skills == 0 then
			break
		end

		local removed_this_pass = 0
		for _, skill in ipairs(active_skills) do
			if skilltreeupdater:IsActivated(skill) then
				skilltreeupdater:DeactivateSkill(skill)
				if not skilltreeupdater:IsActivated(skill) then
					removed_count = removed_count + 1
					removed_this_pass = removed_this_pass + 1
				end
			end
		end

		if removed_this_pass == 0 then
			break
		end
	end

	if skip_validation then
		skilltreeupdater:SetSkipValidation(false)
	end

	return removed_count, #GetActiveSkillNames(skilltreeupdater)
end

local function RefreshAfterSkillReset(player)
	if player == nil or player.components == nil then
		return
	end

	local petleash = player.components.petleash
	local ok, expanded_hook = pcall(require, "skill_effect/waxwell/puppeteer/expanded_dominion/hook")
	if ok and expanded_hook ~= nil and expanded_hook.RefreshWaxwellShadowServantState ~= nil then
		expanded_hook.RefreshWaxwellShadowServantState(player)
	elseif petleash ~= nil and petleash._waxwell_base_maxpets ~= nil and petleash.GetMaxPets ~= nil and petleash.SetMaxPets ~= nil then
		local targetmax = petleash._waxwell_base_maxpets
		if petleash:GetMaxPets() ~= targetmax then
			petleash:SetMaxPets(targetmax)
		end
	end

	local sanity = player.components.sanity
	if sanity ~= nil and sanity.RecalculatePenalty ~= nil then
		sanity:RecalculatePenalty()
	end

	local emperor_common = GetEmperorCommon()
	local domain_expansion = GetDomainExpansion()
	if domain_expansion ~= nil and domain_expansion.RequestDomainExpansionDeactivate ~= nil then
		domain_expansion.RequestDomainExpansionDeactivate(player)
	end

	EnsureCurrentPlayerSkillInfoHUD(player, "skill_reset")
	player:PushEvent("newskillpointupdated")
	player:PushEvent("onsetskillselection_server")
end

local function ClearSkillFullSnapshot(player)
	if player == nil then
		return
	end

	SetSkillAllState(player, false)
	player._skilltree_debug_skill_full_restore_blob = nil
	player._skilltree_debug_skill_full_restore_points = nil
end

local function FullSkillsForPlayer(player)
	if player == nil or player.components == nil or player.components.skilltreeupdater == nil then
		return false
	end

	local skilltreeupdater = player.components.skilltreeupdater
	local prefab = player.prefab
	local skill_names = GetAllUpgradeableSkillNames(prefab)
	if #skill_names == 0 then
		return false
	end

	EnsureSkillFullSaveGuard(player, skilltreeupdater)

	if not player._skilltree_debug_skill_full_active then
		player._skilltree_debug_skill_full_restore_blob = skilltreeupdater.skilltree:EncodeSkillTreeData(prefab)
		player._skilltree_debug_skill_full_restore_points = GetTotalSkillPoints(skilltreeupdater)
	end

	local cleared_count = 0
	if GetAllocatedSkillCount(skilltreeupdater) > 0 then
		cleared_count = RemoveAllCurrentSkills(skilltreeupdater, true)
	end

	SetSkillAllState(player, true)

	local target_skill_count = GetUpgradeableSkillCount(prefab)

	skilltreeupdater:SetSkipValidation(true)
	local activated_count = 0
	for _, skill in ipairs(skill_names) do
		if not skilltreeupdater:IsActivated(skill) then
			skilltreeupdater:ActivateSkill(skill)
			if skilltreeupdater:IsActivated(skill) then
				activated_count = activated_count + 1
			end
		end
	end
	skilltreeupdater:SetSkipValidation(player._skilltree_debug_skill_full_active == true)

	player:PushEvent("newskillpointupdated")
	player:PushEvent("onsetskillselection_server")

	local active_total = GetAllocatedSkillCount(skilltreeupdater)
	local available_points = GetAvailableSkillPoints(skilltreeupdater)
	return true
end

local function FullCurrentPlayerSkills()
	return FullSkillsForPlayer(GetCurrentPlayer())
end

local function EnsureSkillAllAfterSkillTreeInit(player)
	if player == nil or not player:IsValid() then
		return
	end

	local needs_apply = player._skilltree_debug_skill_full_pending == true
		or player._skilltree_debug_skill_full_active == true
	if not needs_apply then
		return
	end

	local skilltreeupdater = player.components ~= nil and player.components.skilltreeupdater or nil
	if skilltreeupdater == nil then
		return
	end

	local target = GetUpgradeableSkillCount(player.prefab)
	local active = GetAllocatedSkillCount(skilltreeupdater)
	if player._skilltree_debug_skill_full_active == true and active >= target then
		player._skilltree_debug_skill_full_pending = nil
		return
	end

	if FullSkillsForPlayer(player) then
		player._skilltree_debug_skill_full_pending = nil
	end
end

local function ApplyPersistedDebugState(player, reason)
	if player == nil then
		return
	end

	if player._skilltree_debug_restore_modes_task ~= nil then
		player._skilltree_debug_restore_modes_task:Cancel()
		player._skilltree_debug_restore_modes_task = nil
	end

	local attempts = 0
	player._skilltree_debug_restore_modes_task = player:DoPeriodicTask(.25, function()
		attempts = attempts + 1
		if player == nil or not player:IsValid() or player.components == nil or player.components.skilltreeupdater == nil then
			if attempts >= 16 and player._skilltree_debug_restore_modes_task ~= nil then
				player._skilltree_debug_restore_modes_task:Cancel()
				player._skilltree_debug_restore_modes_task = nil
			end
			return
		end

		local data = player._skilltree_debug_persisted_state
		if data ~= nil then
			if data.skill_test ~= nil then
				SetEnabled("skill_test", data.skill_test == true)
				if data.skill_test == true then
					local spell_utils = GetSpellUtils()
					if spell_utils.ApplySkillTestCooldownOverride ~= nil then
						spell_utils.ApplySkillTestCooldownOverride(player)
					end
				end
			end

			if data.skill_info ~= nil then
				SetEnabled("skill_info", data.skill_info == true)
			end

			if data.skill_full == true then
				player._skilltree_debug_skill_full_pending = true
			end

			player._skilltree_debug_persisted_state = nil
		end

		local enabled = IsEnabled("skill_info")
		local allplayers = rawget(modglobals, "AllPlayers") or rawget(_G, "AllPlayers")
		if allplayers ~= nil then
			for _, current in ipairs(allplayers) do
				if current ~= nil then
					if current._skilltree_debug_skill_info_enabled ~= nil then
						current._skilltree_debug_skill_info_enabled:set(enabled)
					end
					if enabled then
						if not current:HasTag(SKILL_INFO_TAG) then
							current:AddTag(SKILL_INFO_TAG)
						end
					elseif current:HasTag(SKILL_INFO_TAG) then
						current:RemoveTag(SKILL_INFO_TAG)
					end
				end
			end
		end
		player:DoTaskInTime(0, function(current)
			if current == nil or not current:IsValid() then
				return
			end
			local controls = current.HUD ~= nil and current.HUD.controls or nil
			if controls ~= nil then
				AttachSkillInfoWidgetToControls(controls, reason or "persist")
			end
		end)
		if player._skilltree_debug_restore_modes_task ~= nil then
			player._skilltree_debug_restore_modes_task:Cancel()
			player._skilltree_debug_restore_modes_task = nil
		end
	end, 0)
end

local function ResetCurrentPlayerSkills()
	local player = GetCurrentPlayer()
	if player == nil or player.components == nil or player.components.skilltreeupdater == nil then
		return false
	end

	local skilltreeupdater = player.components.skilltreeupdater
	local had_skill_full_flag = player._skilltree_debug_skill_full_active == true
	local restore_points = had_skill_full_flag and player._skilltree_debug_skill_full_restore_points or nil
	local before_points = skilltreeupdater.GetAvailableSkillPoints ~= nil and skilltreeupdater:GetAvailableSkillPoints() or nil
	local removed_count, remaining_count = RemoveAllCurrentSkills(skilltreeupdater, had_skill_full_flag)

	RefreshAfterSkillReset(player)
	if had_skill_full_flag then
		ClearSkillFullSnapshot(player)
		player:PushEvent("newskillpointupdated")
		player:PushEvent("onsetskillselection_server")
	end

	remaining_count = #GetActiveSkillNames(skilltreeupdater)
	local after_points = skilltreeupdater.GetAvailableSkillPoints ~= nil and skilltreeupdater:GetAvailableSkillPoints() or nil
	local refunded_points = before_points ~= nil and after_points ~= nil and math.max(0, after_points - before_points) or nil

	if remaining_count > 0 then
		return false
	end

	return true
end

function M.IsSkillTestEnabled()
	return IsEnabled("skill_test")
end

function M.GetSkillTestCooldown(defaultcooldown)
	return M.IsSkillTestEnabled() and SKILL_TEST_COOLDOWN or defaultcooldown
end

function M.ShouldIgnoreCodexUmbraDurability()
	return M.IsSkillTestEnabled()
end

local function SetSkillInfoTag(enabled)
	local theworld = rawget(modglobals, "TheWorld") or rawget(_G, "TheWorld")
	if theworld == nil or not theworld.ismastersim then
		return
	end

	local allplayers = rawget(modglobals, "AllPlayers") or rawget(_G, "AllPlayers")
	if allplayers == nil then
		return
	end

	for _, player in ipairs(allplayers) do
		if player ~= nil then
			if player._skilltree_debug_skill_info_enabled ~= nil then
				player._skilltree_debug_skill_info_enabled:set(enabled)
			end
			if enabled then
				if not player:HasTag(SKILL_INFO_TAG) then
					player:AddTag(SKILL_INFO_TAG)
				end
			elseif player:HasTag(SKILL_INFO_TAG) then
				player:RemoveTag(SKILL_INFO_TAG)
			end
		end
	end
end

function M.IsSkillInfoEnabled(owner)
	return IsEnabled("skill_info")
		or (owner ~= nil and owner._skilltree_debug_skill_info_enabled ~= nil and owner._skilltree_debug_skill_info_enabled:value())
		or (owner ~= nil and owner.HasTag ~= nil and owner:HasTag(SKILL_INFO_TAG))
end

function M.IsSkillAllEnabled(owner)
	return owner ~= nil and (
		owner._skilltree_debug_skill_full_active == true
		or (owner._skilltree_debug_skill_all_enabled ~= nil and owner._skilltree_debug_skill_all_enabled:value())
	)
end

local function FormatPercent(value)
	return math.max(0, math.floor((value or 0) * 100 + .5))
end

local function FormatSeconds(value)
	if value == nil then
		return nil
	end

	if value < 10 then
		return string.format("%.1f", math.max(0, value))
	end

	return tostring(math.max(0, math.ceil(value - .0001)))
end

local function FormatStateLabel(state)
	if state == nil then
		return nil
	elseif state == "active" then
		return "active"
	elseif state == "activating" or state == "spawning" then
		return "starting"
	elseif state == "deactivating" then
		return "ending"
	end

	return tostring(state)
end

local function GetDebugSanityData(owner)
	local base_max = owner ~= nil and owner._skilltree_debug_sanity_base_max or nil
	local penalty = owner ~= nil and owner._skilltree_debug_sanity_penalty_percent or nil
	if base_max == nil or penalty == nil then
		local sanity = owner ~= nil and ((owner.replica ~= nil and owner.replica.sanity) or (owner.components ~= nil and owner.components.sanity)) or nil
		if sanity == nil then
			return nil, nil, nil
		end

		base_max = (sanity.GetMax ~= nil and sanity:GetMax()) or sanity.max or nil
		penalty = (sanity.GetPenaltyPercent ~= nil and sanity:GetPenaltyPercent()) or 0
	end

	local effective_max = base_max ~= nil and math.max(0, math.floor((base_max * (1 - penalty)) + .5)) or nil
	return effective_max, base_max, penalty
end

local function GetDebugSanityRegenPerMinute(owner)
	local sanity = owner ~= nil and owner.components ~= nil and owner.components.sanity or nil
	return sanity ~= nil and sanity.rate ~= nil and sanity.rate * 60 or nil
end

local function GetDebugSummonSlotData(owner)
	local petleash = owner ~= nil and owner.components ~= nil and owner.components.petleash or nil
	if petleash == nil then
		return nil, nil
	end

	local puppeteer_common = GetPuppeteerCommon()
	return puppeteer_common.GetUsedShadowServantSlots(petleash), puppeteer_common.GetExpandedDominionMaxPets(petleash)
end

local function CountPetsByPrefab(owner, prefab)
	local petleash = owner ~= nil and owner.components ~= nil and owner.components.petleash or nil
	local pets = petleash ~= nil and petleash.GetPets ~= nil and petleash:GetPets() or nil
	if pets == nil then
		return nil
	end

	local count = 0
	for pet in pairs(pets) do
		if pet ~= nil and pet:IsValid() and pet.prefab == prefab then
			count = count + 1
		end
	end

	return count
end

local function CountShadowWorkers(owner)
	local petleash = owner ~= nil and owner.components ~= nil and owner.components.petleash or nil
	local pets = petleash ~= nil and petleash.GetPets ~= nil and petleash:GetPets() or nil
	if pets == nil then
		return nil, nil
	end

	local puppeteer_common = GetPuppeteerCommon()
	local IsFreeShadowServant = puppeteer_common.IsFreeShadowServant
	local regular_count = 0
	local free_count = 0

	for pet in pairs(pets) do
		if pet ~= nil and pet:IsValid() and pet.prefab == "shadowworker" then
			if IsFreeShadowServant ~= nil and IsFreeShadowServant(pet) then
				free_count = free_count + 1
			else
				regular_count = regular_count + 1
			end
		end
	end

	return regular_count, free_count
end

local function BuildTrackedSkillLines(owner)
	local lines = {}

	local worker_count, free_worker_count = CountShadowWorkers(owner)
	if worker_count ~= nil and worker_count > 0 then
		table.insert(lines, string.format("Shadow Worker : active x%d", worker_count))
	end
	if free_worker_count ~= nil and free_worker_count > 0 then
		table.insert(lines, string.format("Shadow Worker (Free) : x%d", free_worker_count))
	end

	local duelist_count = CountPetsByPrefab(owner, "shadowprotector")
	if duelist_count ~= nil and duelist_count > 0 then
		table.insert(lines, string.format("Shadow Duelist : active x%d", duelist_count))
	end

	local marksman_count = CountPetsByPrefab(owner, "shadow_marksman")
	if marksman_count ~= nil and marksman_count > 0 then
		table.insert(lines, string.format("Shadow Marksman : active x%d", marksman_count))
	end

	local lanternbearer_count = CountPetsByPrefab(owner, "shadow_lanternbearer")
	if lanternbearer_count ~= nil and lanternbearer_count > 0 then
		table.insert(lines, string.format("Shadow Lanternbearer : active x%d", lanternbearer_count))
	end

	local spell_utils = GetSpellUtils()
	for _, entry in ipairs(GetTrackedSkills()) do
		local available = entry.is_available == nil or entry.is_available(owner)
		if available then
		local state = entry.get_state ~= nil and entry.get_state(owner) or nil
		local state_label = FormatStateLabel(state)
		if state_label ~= nil then
			table.insert(lines, string.format("%s : %s", entry.label, state_label))
		end

		local cooldown = entry.cooldown_id ~= nil and spell_utils.GetSpellCooldownTimeRemaining(owner, entry.cooldown_id) or nil
		if cooldown ~= nil and cooldown > 0 then
			table.insert(lines, string.format("%s Cooldown : %ss", entry.label, FormatSeconds(cooldown)))
		end
		end
	end

	return lines
end

local function BuildSkillInfoString(owner)
	local effective_max, base_max, penalty = GetDebugSanityData(owner)
	local sanity_regen = GetDebugSanityRegenPerMinute(owner)
	local used_slots, max_slots = GetDebugSummonSlotData(owner)
	local lines = BuildTrackedSkillLines(owner)

	local reticule_line = GetDebugReticuleInfoLine()
	if reticule_line ~= nil then
		table.insert(lines, reticule_line)
	end

	local shadow_line = GetDebugShadowInfoLine()
	if shadow_line ~= nil then
		table.insert(lines, shadow_line)
	end

	local fire_line = GetDebugFireInfoLine()
	if fire_line ~= nil then
		table.insert(lines, fire_line)
	end

	local sanity_line = effective_max ~= nil and base_max ~= nil
		and string.format("Max Sanity : %d/%d", effective_max, base_max)
		or "Max Sanity : -/-"
	local sanity_penalty_line = string.format("Max Sanity Penalty : %d%%", FormatPercent(penalty))
	local sanity_regen_line = sanity_regen ~= nil
		and string.format("Sanity Regen : %.2f/min", sanity_regen)
		or "Sanity Regen : -/min"
	local slot_line = used_slots ~= nil and max_slots ~= nil
		and string.format("Summon Slot : %d/%d", used_slots, max_slots)
		or "Summon Slot : -/-"
	local skill_full_line = string.format("Skill All : %s", M.IsSkillAllEnabled(owner) and "on" or "off")
	local skill_test_line = string.format("Skill Test : %s", M.IsSkillTestEnabled() and "on" or "off")

	table.insert(lines, 1, skill_test_line)
	table.insert(lines, 1, skill_full_line)
	table.insert(lines, 1, slot_line)
	table.insert(lines, 1, sanity_regen_line)
	table.insert(lines, 1, sanity_penalty_line)
	table.insert(lines, 1, sanity_line)

	return table.concat(lines, "\n")
end

function M.GetSkillInfoString(owner)
	return BuildSkillInfoString(owner)
end

local function DebugSkillInfoWidgetState(controls, reason, owner, text)
end

AttachSkillInfoWidgetToControls = function(controls, source)
	if controls == nil then
		PrintSkillInfoTrace(string.format("attach skipped: controls nil source=%s", tostring(source)))
		return false
	end

	if controls._skilltree_debug_skill_info_patched then
		DebugSkillInfoWidgetState(controls, "attach-existing:" .. tostring(source), controls.owner, controls._skilltree_debug_skill_info ~= nil and controls._skilltree_debug_skill_info.GetString ~= nil and controls._skilltree_debug_skill_info:GetString() or nil)
		return true
	end

	if controls.topleft_root == nil then
		PrintSkillInfoTrace(string.format("attach waiting: missing topleft_root source=%s", tostring(source)))
		return false
	end

	controls._skilltree_debug_skill_info_patched = true

	local Widget = require("widgets/widget")
	local Text = require("widgets/text")
	local font = rawget(modglobals, "BODYTEXTFONT") or rawget(modglobals, "UIFONT") or rawget(modglobals, "TALKINGFONT")
	controls._skilltree_debug_skill_info_root = controls:AddChild(Widget("skilltree_debug_skill_info_root"))
	controls._skilltree_debug_skill_info_root:SetHAnchor(rawget(modglobals, "ANCHOR_LEFT") or 0)
	controls._skilltree_debug_skill_info_root:SetVAnchor(rawget(modglobals, "ANCHOR_TOP") or 0)
	if controls._skilltree_debug_skill_info_root.SetScaleMode ~= nil then
		controls._skilltree_debug_skill_info_root:SetScaleMode(rawget(modglobals, "SCALEMODE_PROPORTIONAL") or 0)
	end
	controls._skilltree_debug_skill_info_root:SetPosition(SKILL_INFO_WIDGET_X, SKILL_INFO_WIDGET_Y, 0)
	controls._skilltree_debug_skill_info = controls._skilltree_debug_skill_info_root:AddChild(Text(font, 24, "skill_info widget ready"))
	controls._skilltree_debug_skill_info:SetPosition(170, -56, 0)
	if controls._skilltree_debug_skill_info.SetRegionSize ~= nil then
		controls._skilltree_debug_skill_info:SetRegionSize(340, 220)
	end
	if controls._skilltree_debug_skill_info.SetHAlign ~= nil then
		controls._skilltree_debug_skill_info:SetHAlign(rawget(modglobals, "ALIGN_LEFT") or rawget(modglobals, "ANCHOR_LEFT") or 0)
	end
	controls._skilltree_debug_skill_info:SetColour(1, 1, 1, .95)
	controls._skilltree_debug_skill_info:Hide()
	controls._skilltree_debug_skill_info_root:Hide()
	DebugSkillInfoWidgetState(controls, "attach-created:" .. tostring(source), controls.owner, "skill_info widget ready")

	local function RefreshSkillInfoWidget()
		if controls._skilltree_debug_skill_info == nil then
			PrintSkillInfoTrace("refresh skipped: text widget nil")
			return
		end

		if controls.owner == nil or not M.IsSkillInfoEnabled(controls.owner) then
			if controls._skilltree_debug_skill_info_root ~= nil then
				controls._skilltree_debug_skill_info_root:Hide()
			end
			controls._skilltree_debug_skill_info:Hide()
			if controls._skilltree_debug_skill_info_visible then
				controls._skilltree_debug_skill_info_visible = false
				DebugSkillInfoWidgetState(controls, "hide", controls.owner, nil)
			end
			return
		end

		local text = BuildSkillInfoString(controls.owner)
		if text ~= controls._skilltree_debug_skill_info_last_text then
			controls._skilltree_debug_skill_info:SetString(text)
			controls._skilltree_debug_skill_info_last_text = text
		end
		if controls._skilltree_debug_skill_info_root ~= nil then
			if controls._skilltree_debug_skill_info_root.MoveToFront ~= nil then
				controls._skilltree_debug_skill_info_root:MoveToFront()
			end
			controls._skilltree_debug_skill_info_root:Show()
		end
		if controls._skilltree_debug_skill_info.MoveToFront ~= nil then
			controls._skilltree_debug_skill_info:MoveToFront()
		end
		controls._skilltree_debug_skill_info:Show()
		controls._skilltree_debug_skill_info_visible = true
		DebugSkillInfoWidgetState(controls, "refresh", controls.owner, text)
	end

	local old_OnUpdate = controls.OnUpdate
	function controls:OnUpdate(dt, ...)
		if old_OnUpdate ~= nil then
			old_OnUpdate(self, dt, ...)
		end

		local enabled = self.owner ~= nil and M.IsSkillInfoEnabled(self.owner) or false
		if enabled ~= self._skilltree_debug_skill_info_last_enabled then
			self._skilltree_debug_skill_info_last_enabled = enabled
			self._skilltree_debug_skill_info_refresh_elapsed = 0
			RefreshSkillInfoWidget()
			return
		end

		self._skilltree_debug_skill_info_refresh_elapsed = (self._skilltree_debug_skill_info_refresh_elapsed or 0) + (dt or 0)
		if self._skilltree_debug_skill_info_refresh_elapsed >= SKILL_INFO_REFRESH_INTERVAL then
			self._skilltree_debug_skill_info_refresh_elapsed = 0
			RefreshSkillInfoWidget()
		end
	end

	controls._skilltree_debug_skill_info_refresh_elapsed = 0
	controls._skilltree_debug_skill_info_last_enabled = controls.owner ~= nil and M.IsSkillInfoEnabled(controls.owner) or false
	RefreshSkillInfoWidget()
	return true
end

EnsureCurrentPlayerSkillInfoHUD = function(inst, source)
	local player = inst or GetCurrentPlayer()
	if player == nil then
		PrintSkillInfoTrace(string.format("hud ensure skipped: no player source=%s", tostring(source)))
		return
	end

	if player._skilltree_debug_skill_info_attach_task ~= nil then
		player._skilltree_debug_skill_info_attach_task:Cancel()
		player._skilltree_debug_skill_info_attach_task = nil
	end

	local attempts = 0
	player._skilltree_debug_skill_info_attach_task = player:DoPeriodicTask(.5, function()
		attempts = attempts + 1
		local controls = player.HUD ~= nil and player.HUD.controls or nil
		if AttachSkillInfoWidgetToControls(controls, tostring(source) .. ":attempt" .. tostring(attempts)) then
			if player._skilltree_debug_skill_info_attach_task ~= nil then
				player._skilltree_debug_skill_info_attach_task:Cancel()
				player._skilltree_debug_skill_info_attach_task = nil
			end
			return
		end

		if attempts >= 12 then
			PrintSkillInfoTrace(string.format("hud ensure gave up after %d attempts source=%s", attempts, tostring(source)))
			if player._skilltree_debug_skill_info_attach_task ~= nil then
				player._skilltree_debug_skill_info_attach_task:Cancel()
				player._skilltree_debug_skill_info_attach_task = nil
			end
		end
	end, 0)
end

function M.Register(env)
	local AddPlayerPostInitFn = env ~= nil and env.AddPlayerPostInit or AddPlayerPostInit
	local AddPrefabPostInitFn = env ~= nil and env.AddPrefabPostInit or AddPrefabPostInit
	local AddClassPostConstructFn = env ~= nil and env.AddClassPostConstruct or AddClassPostConstruct

	if AddPlayerPostInitFn ~= nil and net_bool ~= nil then
		AddPlayerPostInitFn(function(inst)
			if inst == nil or inst._skilltree_debug_skill_info_enabled ~= nil then
				return
			end

			inst._skilltree_debug_skill_info_enabled = net_bool(inst.GUID, SKILL_INFO_NETVAR_NAME, SKILL_INFO_NETVAR_DIRTY)
			inst._skilltree_debug_skill_all_enabled = net_bool(inst.GUID, SKILL_ALL_NETVAR_NAME, SKILL_ALL_NETVAR_DIRTY)
			local theworld = rawget(modglobals, "TheWorld") or rawget(_G, "TheWorld")
			if theworld ~= nil and theworld.ismastersim then
				inst._skilltree_debug_skill_info_enabled:set(IsEnabled("skill_info"))
				inst._skilltree_debug_skill_all_enabled:set(inst._skilltree_debug_skill_full_active == true)

				local old_OnSave = inst.OnSave
				inst.OnSave = function(player, data)
					local refs = nil
					if old_OnSave ~= nil then
						refs = old_OnSave(player, data)
					end

					data = data or {}
					data._skilltree_debug_persisted_state = {
						skill_test = M.IsSkillTestEnabled(),
						skill_info = M.IsSkillInfoEnabled(player),
						skill_full = player._skilltree_debug_skill_full_active == true,
					}

					return refs
				end

				local old_OnLoad = inst.OnLoad
				inst.OnLoad = function(player, data)
					if old_OnLoad ~= nil then
						old_OnLoad(player, data)
					end

					player._skilltree_debug_persisted_state = data ~= nil and data._skilltree_debug_persisted_state or nil
					ApplyPersistedDebugState(player, "load")
				end

				ApplyPersistedDebugState(inst, "playerpostinit")

				inst:ListenForEvent("ms_skilltreeinitialized", function()
					EnsureSkillAllAfterSkillTreeInit(inst)
				end)
			elseif inst == GetCurrentPlayer() then
				EnsureCurrentPlayerSkillInfoHUD(inst, "playerpostinit")
			end
		end)
	end

	local function ToggleSkillTest(force_state)
		local enabled = force_state
		if enabled == nil then
			enabled = not M.IsSkillTestEnabled()
		end
		enabled = SetEnabled("skill_test", enabled)
		if enabled then
			local spell_utils = GetSpellUtils()
			local changed = 0
			local theworld = rawget(modglobals, "TheWorld") or rawget(_G, "TheWorld")
			if theworld ~= nil and theworld.ismastersim then
				local allplayers = rawget(modglobals, "AllPlayers") or rawget(_G, "AllPlayers") or {}
				for _, player in ipairs(allplayers) do
					changed = changed + (spell_utils.ApplySkillTestCooldownOverride ~= nil and spell_utils.ApplySkillTestCooldownOverride(player) or 0)
				end
			else
				changed = spell_utils.ApplySkillTestCooldownOverride ~= nil and spell_utils.ApplySkillTestCooldownOverride(GetCurrentPlayer()) or 0
			end
		end
		PrintState("skill_test", enabled)
		return enabled
	end

	local function ToggleSkillInfo(force_state)
		local enabled = force_state
		if enabled == nil then
			enabled = not M.IsSkillInfoEnabled(rawget(modglobals, "ThePlayer") or rawget(_G, "ThePlayer"))
		end
		enabled = SetEnabled("skill_info", enabled)
		SetSkillInfoTag(enabled)
		PrintSkillInfoTrace(string.format("toggle enabled=%s localplayer=%s tag=%s", tostring(enabled), tostring(GetCurrentPlayer() ~= nil), tostring(GetCurrentPlayer() ~= nil and GetCurrentPlayer():HasTag(SKILL_INFO_TAG) or false)))
		EnsureCurrentPlayerSkillInfoHUD(GetCurrentPlayer(), "toggle")
		PrintState("skill_info", enabled)
		return enabled
	end

	rawset(modglobals, "skill_test", ToggleSkillTest)
	rawset(modglobals, "skill_test_on", function()
		return ToggleSkillTest(true)
	end)
	rawset(modglobals, "skill_test_off", function()
		return ToggleSkillTest(false)
	end)
	rawset(modglobals, "skill_test_status", function()
		local enabled = M.IsSkillTestEnabled()
		PrintState("skill_test", enabled)
		return enabled
	end)
	rawset(modglobals, "skill_info", ToggleSkillInfo)
	rawset(modglobals, "skill_info_on", function()
		return ToggleSkillInfo(true)
	end)
	rawset(modglobals, "skill_info_off", function()
		return ToggleSkillInfo(false)
	end)
	rawset(modglobals, "skill_info_status", function()
		local enabled = M.IsSkillInfoEnabled(rawget(modglobals, "ThePlayer") or rawget(_G, "ThePlayer"))
		PrintState("skill_info", enabled)
		return enabled
	end)
	rawset(modglobals, "skill_full", nil)
	rawset(modglobals, "skill_all", FullCurrentPlayerSkills)
	rawset(modglobals, "skill_reset", ResetCurrentPlayerSkills)
	InstallSkillDebugConsoleCommands()

	if AddClassPostConstructFn ~= nil then
		AddClassPostConstructFn("widgets/controls", function(self)
			if self == nil then
				return
			end
			AttachSkillInfoWidgetToControls(self, "classpostconstruct")
		end)
	end

	if AddPrefabPostInitFn == nil then
		return
	end

	AddPrefabPostInitFn("waxwelljournal", function(inst)
		local theworld = rawget(modglobals, "TheWorld") or rawget(_G, "TheWorld")
		if theworld == nil or not theworld.ismastersim or inst.components == nil or inst.components.fueled == nil or inst._skill_tree_debug_fueled_patched then
			return
		end

		inst._skill_tree_debug_fueled_patched = true

		local fueled = inst.components.fueled
		local old_DoDelta = fueled.DoDelta
		fueled.DoDelta = function(self, delta, ...)
			if M.ShouldIgnoreCodexUmbraDurability() and delta ~= nil and delta < 0 then
				return old_DoDelta(self, 0, ...)
			end

			return old_DoDelta(self, delta, ...)
		end
	end)
end

M.DEBUG_RETICULE_RANGE_PER_SCALE = reticule_constants.RANGE_PER_SCALE
M.GetWorkRadiusForReticuleScale = reticule_utils.GetWorkRadius
M.GetReticuleScaleForWorkRadius = reticule_utils.GetScaleForWorkRadius
M.GetShadowRangeForReticuleScale = M.GetWorkRadiusForReticuleScale
M.GetReticuleScaleForShadowRange = M.GetReticuleScaleForWorkRadius

return M
