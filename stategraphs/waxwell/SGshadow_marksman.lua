require("stategraphs/commonstates")
local shadow_level = require("skill_effect/waxwell/_shared/shadow_level")

local function FixupWorkerCarry(inst, swap)
    if inst.prefab == "shadowworker" then
		if inst.sg.mem.swaptool == swap then
			return false
		end
		inst.sg.mem.swaptool = swap
		if swap == nil then
            inst.AnimState:ClearOverrideSymbol("swap_object")
            inst.AnimState:Hide("ARM_carry")
            inst.AnimState:Show("ARM_normal")
        else
            inst.AnimState:Show("ARM_carry")
            inst.AnimState:Hide("ARM_normal")
            inst.AnimState:OverrideSymbol("swap_object", swap, swap)
        end
		return true
    else
        if swap == nil then -- DEPRECATED workers.
            inst.AnimState:Hide("swap_arm_carry")
        --'else' case cannot exist old workers had one item only assumed.
        end
    end
end

local function DetachFX(fx)
	fx.Transform:SetPosition(fx.Transform:GetWorldPosition())
	fx.entity:SetParent(nil)
end

local function DoDespawnFX(inst)
	--shadow_despawn is in the air => detaches from sinking boats
	--shadow_glob_fx is on ground => dies with sinking boats
	local x, y, z = inst.Transform:GetWorldPosition()
	local fx1 = SpawnPrefab("shadow_despawn")
	local fx2 = SpawnPrefab("shadow_glob_fx")
	fx2.AnimState:SetScale(math.random() < .5 and -1.3 or 1.3, 1.3, 1.3)
	local platform = inst:GetCurrentPlatform()
	if platform ~= nil then
		fx1.entity:SetParent(platform.entity)
		fx2.entity:SetParent(platform.entity)
		fx1:ListenForEvent("onremove", function() DetachFX(fx1) end, platform)
		x, y, z = platform.entity:WorldToLocalSpace(x, y, z)
	end
	fx1.Transform:SetPosition(x, y, z)
	fx2.Transform:SetPosition(x, y, z)
end

local function TrySplashFX(inst, size)
	local x, y, z = inst.Transform:GetWorldPosition()
	if TheWorld.Map:IsOceanAtPoint(x, 0, z) then
		SpawnPrefab("ocean_splash_"..(size or "med")..tostring(math.random(2))).Transform:SetPosition(x, 0, z)
		return true
	end
end

local function TryStepSplash(inst)
	local t = GetTime()
	if (inst.sg.mem.laststepsplash == nil or inst.sg.mem.laststepsplash + .1 < t) and TrySplashFX(inst) then
		inst.sg.mem.laststepsplash = t
	end
end

local function DoSound(inst, sound)
	inst.SoundEmitter:PlaySound(sound)
end

local SHADOW_MARKSMAN_SPECIAL_AMMO_CD = "shadow_marksman_special_ammo_cd"
local SHADOW_MARKSMAN_SPECIAL_AMMO_COOLDOWN_LV1 = 15
local SHADOW_MARKSMAN_SPECIAL_AMMO_COOLDOWN_LV2 = 10
local SHADOW_MARKSMAN_TINT = { .08, .08, .08, 1 }
local SHADOW_MARKSMAN_RETINT_PERIOD = .1
local SHADOW_MARKSMAN_RETINT_DURATION = 4
local SHADOW_MARKSMAN_DARK_FX_TAG = "shadow_marksman_dark_fx_target"
local SHADOW_MARKSMAN_AMMO_GROUP_1 =
{
	"slingshotammo_stinger_proj",
	"slingshotammo_marble_proj",
	"slingshotammo_freeze_proj",
	"slingshotammo_honey_proj",
}
local SHADOW_MARKSMAN_AMMO_GROUP_2 =
{
	"slingshotammo_moonglass_proj",
	"slingshotammo_thulecite_proj",
	"slingshotammo_scrapfeather_proj",
	"slingshotammo_gelblob_proj",
}
local SHADOW_MARKSMAN_FX_REPLACEMENTS =
{
	slingshot_aoe_fx = "shadow_marksman_aoe_fx",
	shatter = "shadow_marksman_shatter",
	electrichitsparks = "shadow_marksman_electrichitsparks",
	electrichitsparks_electricimmune = "shadow_marksman_electrichitsparks_electricimmune",
	honey_trail = "shadow_marksman_honey_trail",
}

local function ShallowCopyAmmoDef(ammo_def)
	local copy = {}
	for k, v in pairs(ammo_def) do
		copy[k] = v
	end
	return copy
end

local function NoTentacleSpawnHoles(pt)
	return not TheWorld.Map:IsPointNearHole(pt)
end

local function SpawnShadowMarksmanTentacle(attacker, target, pt, starting_angle)
	local offset = FindWalkableOffset(pt, starting_angle, 2, 3, false, true, NoTentacleSpawnHoles, false, true, true)
	if offset == nil then
		return
	end

	local tentacle = SpawnPrefab("shadowtentacle")
	if tentacle == nil then
		return
	end

	tentacle.owner = attacker
	tentacle.Transform:SetPosition(pt.x + offset.x, 0, pt.z + offset.z)
	if target ~= nil
		and target:IsValid()
		and tentacle.components ~= nil
		and tentacle.components.combat ~= nil then
		tentacle.components.combat:SetTarget(target)
	end

	if tentacle.SoundEmitter ~= nil then
		tentacle.SoundEmitter:PlaySound("dontstarve/characters/walter/slingshot/shadowTentacleAttack_1")
		tentacle.SoundEmitter:PlaySound("dontstarve/characters/walter/slingshot/shadowTentacleAttack_2")
	end
end

local function ShadowMarksmanThuleciteOnHit(proj, attacker, target)
	if target == nil or not target:IsValid() then
		return
	end

	SpawnShadowMarksmanTentacle(attacker, target, target:GetPosition(), math.random() * TWOPI)
end

local function ApplyMarksmanLv2ThuleciteGuaranteedTentacle(projectile)
	if projectile == nil or projectile.ammo_def == nil or projectile.ammo_def.symbol ~= "thulecite" then
		return
	end

	projectile.ammo_def = ShallowCopyAmmoDef(projectile.ammo_def)
	projectile.ammo_def.onhit = ShadowMarksmanThuleciteOnHit
end

local function SetShadowMarksmanTint(inst)
	if inst ~= nil and inst.AnimState ~= nil then
		inst.AnimState:SetMultColour(unpack(SHADOW_MARKSMAN_TINT))
		inst.AnimState:SetAddColour(0, 0, 0, 0)
		inst.AnimState:SetLightOverride(0)
	end
end

local function ShouldRetintShadowMarksmanFX(ent)
	if ent == nil or not ent:IsValid() or ent.prefab == nil then
		return false
	end

	return ent.prefab == "slingshot_aoe_fx"
		or string.find(ent.prefab, "slingshotammo", 1, true) ~= nil
		or string.find(ent.prefab, "electrichitsparks", 1, true) ~= nil
		or ent.prefab == "shatter"
		or ent.prefab == "honey_trail"
end

local function RetintShadowMarksmanFXNearTarget(target)
	if target == nil or not target:IsValid() then
		return
	end

	local x, y, z = target.Transform:GetWorldPosition()
	local ents = TheSim:FindEntities(x, y, z, 8, { "FX" }, { "INLIMBO" })
	for _, ent in ipairs(ents) do
		if ShouldRetintShadowMarksmanFX(ent) then
			if ent.SetColorType ~= nil then
				ent:SetColorType("shadow")
			end
			SetShadowMarksmanTint(ent)
		end
	end
end

local function RetintShadowMarksmanAttachedFX(target)
	if target == nil or not target:IsValid() then
		return
	end

	if target._slingshot_slow ~= nil and target._slingshot_slow.fx ~= nil then
		SetShadowMarksmanTint(target._slingshot_slow.fx)
	end
end

local function StopShadowMarksmanRetintTask(target)
	if target ~= nil and target._shadow_marksman_retint_task ~= nil then
		target._shadow_marksman_retint_task:Cancel()
		target._shadow_marksman_retint_task = nil
	end
end

local function ClearShadowMarksmanDarkFXTarget(target)
	if target ~= nil and target:IsValid() then
		target._shadow_marksman_dark_fx_until = nil
		target:RemoveTag(SHADOW_MARKSMAN_DARK_FX_TAG)
		if target._shadow_marksman_dark_fx_task ~= nil then
			target._shadow_marksman_dark_fx_task:Cancel()
			target._shadow_marksman_dark_fx_task = nil
		end
	end
end

local function MarkShadowMarksmanDarkFXTarget(target, duration)
	if target == nil or not target:IsValid() then
		return
	end

	duration = duration or SHADOW_MARKSMAN_RETINT_DURATION
	target._shadow_marksman_dark_fx_until = GetTime() + duration
	if not target:HasTag(SHADOW_MARKSMAN_DARK_FX_TAG) then
		target:AddTag(SHADOW_MARKSMAN_DARK_FX_TAG)
	end

	if target._shadow_marksman_dark_fx_task ~= nil then
		target._shadow_marksman_dark_fx_task:Cancel()
	end
	target._shadow_marksman_dark_fx_task = target:DoTaskInTime(duration, ClearShadowMarksmanDarkFXTarget)
end

local function StartShadowMarksmanRetintTask(target, duration)
	if target == nil or not target:IsValid() then
		return
	end

	MarkShadowMarksmanDarkFXTarget(target, duration)
	StopShadowMarksmanRetintTask(target)

	local endtime = GetTime() + (duration or SHADOW_MARKSMAN_RETINT_DURATION)
	target._shadow_marksman_retint_task = target:DoPeriodicTask(SHADOW_MARKSMAN_RETINT_PERIOD, function(inst)
		if not inst:IsValid() or GetTime() >= endtime then
			StopShadowMarksmanRetintTask(inst)
			return
		end

		RetintShadowMarksmanAttachedFX(inst)
		RetintShadowMarksmanFXNearTarget(inst)
	end)
end

local function SpawnShadowMarksmanImpactFX(target, ammo_def)
	if target == nil or not target:IsValid() then
		return
	end

	local fx = SpawnPrefab("shadow_marksman_hitfx")
	if fx ~= nil then
		fx.Transform:SetPosition(target.Transform:GetWorldPosition())
		SetShadowMarksmanTint(fx)
		fx:DoTaskInTime(0, SetShadowMarksmanTint)
	end

	RetintShadowMarksmanFXNearTarget(target)
	RetintShadowMarksmanAttachedFX(target)
	target:DoTaskInTime(0, RetintShadowMarksmanFXNearTarget)
	target:DoTaskInTime(.1, RetintShadowMarksmanFXNearTarget)
	StartShadowMarksmanRetintTask(target)
end

local function IsMarksmanLv1(inst)
	return inst ~= nil and (inst._waxwell_marksman_lv1 or inst:HasTag("shadow_marksman_1"))
end

local function IsMarksmanLv2(inst)
	return inst ~= nil and (inst._waxwell_marksman_lv2 or inst:HasTag("shadow_marksman_2"))
end

local function GetMarksmanSpecialAmmoCooldown(inst)
	if IsMarksmanLv2(inst) then
		return SHADOW_MARKSMAN_SPECIAL_AMMO_COOLDOWN_LV2
	end
	return SHADOW_MARKSMAN_SPECIAL_AMMO_COOLDOWN_LV1
end

local function GetMarksmanAmmoGroup(inst)
	if IsMarksmanLv2(inst) then
		return SHADOW_MARKSMAN_AMMO_GROUP_2
	elseif IsMarksmanLv1(inst) then
		return SHADOW_MARKSMAN_AMMO_GROUP_1
	end
end

local function GetMarksmanProjectilePrefab(inst)
	local ammogroup = GetMarksmanAmmoGroup(inst)
	if ammogroup == nil then
		return "slingshotammo_rock_proj"
	end

	local timer = inst.components.timer
	if timer ~= nil and timer:TimerExists(SHADOW_MARKSMAN_SPECIAL_AMMO_CD) then
		return "slingshotammo_rock_proj"
	end

	local projectileprefab = ammogroup[math.random(#ammogroup)]

	if timer ~= nil then
		timer:StartTimer(SHADOW_MARKSMAN_SPECIAL_AMMO_CD, GetMarksmanSpecialAmmoCooldown(inst))
	end

	return projectileprefab
end

local GetLeaderShadowLevelDamageBonus

local function LaunchMarksmanProjectile(inst, target)
	if target == nil or not target:IsValid() then
		return
	end

	local projectile = SpawnPrefab(GetMarksmanProjectilePrefab(inst))
	if projectile ~= nil then
		if IsMarksmanLv2(inst) then
			ApplyMarksmanLv2ThuleciteGuaranteedTentacle(projectile)
		end

		local x, y, z = inst.Transform:GetWorldPosition()
		projectile.Transform:SetPosition(x, y + 1.2, z)
		SetShadowMarksmanTint(projectile)

		local shadowlevelbonus = GetLeaderShadowLevelDamageBonus(inst, target)
		local hasbasedamage = projectile.components.weapon ~= nil and projectile.components.weapon.damage ~= nil
		if shadowlevelbonus > 0 and hasbasedamage then
			local basedamage = projectile.components.weapon.damage
			if projectile.ammo_def ~= nil and projectile.ammo_def.symbol == "scrapfeather" then
				projectile._shadowlevelbonus = shadowlevelbonus
			else
				projectile.components.weapon:SetDamage(function(proj, attacker, hit_target)
					return (FunctionOrValue(basedamage, proj, attacker, hit_target) or 0) + shadowlevelbonus
				end)
			end
		end

		if projectile.components.weapon ~= nil and projectile.components.weapon.onattack ~= nil then
			local old_onattack = projectile.components.weapon.onattack
			projectile.noimpactfx = true
			projectile.components.weapon:SetOnAttack(function(proj, attacker, attacked_target)
				local old_SpawnPrefab = SpawnPrefab
				SpawnPrefab = function(name, ...)
					name = SHADOW_MARKSMAN_FX_REPLACEMENTS[name] or name
					return old_SpawnPrefab(name, ...)
				end

				local ok, err = xpcall(function()
					old_onattack(proj, attacker, attacked_target)
				end, debug.traceback)

				SpawnPrefab = old_SpawnPrefab

				if not ok then
					error(err)
				end

				SpawnShadowMarksmanImpactFX(attacked_target, proj.ammo_def)
				if proj.ammo_def ~= nil and proj.ammo_def.symbol == "scrapfeather" then
					local sparkprefab = attacked_target ~= nil and attacked_target:HasTag("electricdamageimmune")
						and "shadow_marksman_electrichitsparks_electricimmune"
						or "shadow_marksman_electrichitsparks"
					local sparks = SpawnPrefab(sparkprefab)
					if sparks ~= nil and sparks.AlignToTarget ~= nil then
						sparks:AlignToTarget(attacked_target, attacker ~= nil and attacker or inst)
					end
				end
				StartShadowMarksmanRetintTask(attacked_target)
			end)
		end

		if projectile.ammo_def ~= nil and projectile.ammo_def.symbol == "scrapfeather" and projectile.components.weapon ~= nil then
			local basedamage = projectile.components.weapon.damage
			local bonusdamage = projectile._shadowlevelbonus or 0
			local electric_damage_mult = projectile.components.weapon.electric_damage_mult or TUNING.SLINGSHOT_AMMO_SCRAPFEATHER_DRY_DAMAGE_MULT
			local electric_wet_damage_mult = projectile.components.weapon.electric_wet_damage_mult or TUNING.SLINGSHOT_AMMO_SCRAPFEATHER_WET_DAMAGE_MULT
			projectile.components.weapon:SetDamage(function(_, attacker, hit_target)
				local wetness = hit_target ~= nil and hit_target.GetWetMultiplier ~= nil and hit_target:GetWetMultiplier() or 0
				local base = FunctionOrValue(basedamage, projectile, attacker, hit_target) or 0
				return base * (electric_damage_mult + electric_wet_damage_mult * wetness) + bonusdamage
			end)
			projectile.components.weapon.stimuli = nil
			projectile.components.weapon.electric_damage_mult = nil
			projectile.components.weapon.electric_wet_damage_mult = nil
		end

		if projectile.components.projectile ~= nil then
			projectile.components.projectile:Throw(inst, target, inst)
		else
			projectile:Remove()
		end
	end
end

local function NotBlocked(pt)
	return not TheWorld.Map:IsGroundTargetBlocked(pt)
end

local function IsNearTarget(inst, target, range)
	return inst:IsNear(target, range + target:GetPhysicsRadius(0))
end

local function IsLeaderNear(inst, leader, target, range)
	--leader is in range of us or our target
	return inst:IsNear(leader, range) or (target ~= nil and IsNearTarget(leader, target, range))
end

local COMBAT_TIMEOUT = 6
local function CheckCombatLeader(inst, target)
	local score = 0
	local leader = inst.components.follower:GetLeader()
	if leader ~= nil then
		local isnear = IsLeaderNear(inst, leader, target, TUNING.SHADOWWAXWELL_PROTECTOR_ACTIVE_LEADER_RANGE)
		local leader_combat = leader.components.combat
		if leader_combat ~= nil then
			local t = GetTime()
			if math.max(leader_combat.laststartattacktime or 0, leader_combat.lastdoattacktime or 0) + COMBAT_TIMEOUT > t then
				if target ~= nil and leader_combat:IsRecentTarget(target) then
					--leader attacking same target as me, ignore range
					score = 4
				elseif isnear then
					--leader is near me, but fighting something else
					score = 3.5
				else
					local leader_target = Ents[leader_combat.lasttargetGUID]
					if leader_target ~= nil and leader_target:IsValid() and inst:IsNear(leader_target, TUNING.SHADOWWAXWELL_PROTECTOR_ACTIVE_LEADER_RANGE) then
						--i'm near my leader's target, so that counts too
						score = 3.5
					end
				end
			end
			if score == 0 and leader_combat:GetLastAttackedTime() + COMBAT_TIMEOUT > t then
				if target ~= nil and leader_combat.lastattacker == target then
					--leader got hit by my target, ignore range
					score = 3
				elseif isnear then
					--leader is near me, but got hit by something else
					score = 2.5
				else
					local attacker = leader_combat.lastattacker
					if attacker ~= nil and attacker:IsValid() and IsNearTarget(inst, attacker, TUNING.SHADOWWAXWELL_PROTECTOR_ACTIVE_LEADER_RANGE) then
						--i'm near my leader's attacker, so that counts too
						score = 2.5
					end
				end
			end
		end
		if score == 0 and isnear then
			score = 1.5
		end
	end

	--0 is most inactive, 4 is most active, convert score to %
	score = score / 4

	--Scale attack speed
	inst.components.combat:SetAttackPeriod(Lerp(TUNING.SHADOWWAXWELL_PROTECTOR_ATTACK_PERIOD_INACTIVE_LEADER, TUNING.SHADOWWAXWELL_PROTECTOR_ATTACK_PERIOD, score))

	--Scale shadowstrike cooldown
	local elapsed = inst.components.timer ~= nil and inst.components.timer:GetTimeElapsed("shadowstrike_cd") or nil
	if elapsed ~= nil then
		inst.components.timer:StopTimer("shadowstrike_cd")
		local cd = Lerp(TUNING.SHADOWWAXWELL_SHADOWSTRIKE_COOLDOWN_INACTIVE_LEADER, TUNING.SHADOWWAXWELL_SHADOWSTRIKE_COOLDOWN, score)
		if elapsed < cd then
			inst.components.timer:StartTimer("shadowstrike_cd", cd - elapsed, nil, cd)
		end
	end
end

local function CheckLeaderShadowLevel(inst, target)
	local basedamage = inst:HasTag("shadowmarksman")
		and TUNING.SLINGSHOT_AMMO_DAMAGE_ROCKS
		or TUNING.SHADOWWAXWELL_PROTECTOR_DAMAGE
	inst.components.combat:SetDefaultDamage(basedamage + shadow_level.GetShadowLevelDamageBonus(inst, target))
end

GetLeaderShadowLevelDamageBonus = function(inst, target)
	return shadow_level.GetShadowLevelDamageBonus(inst, target)
end

local function TryRepeatAction(inst, buffaction, right)
	if buffaction ~= nil and
		buffaction:IsValid() and
		buffaction.target ~= nil and
		buffaction.target.components.workable ~= nil and
		buffaction.target.components.workable:CanBeWorked() and
		buffaction.target:IsActionValid(buffaction.action, right)
		then
		local otheraction = inst:GetBufferedAction()
		if otheraction == nil or (
			otheraction.target == buffaction.target and
			otheraction.action == buffaction.action
		) then
			inst.components.locomotor:Stop()
			inst:ClearBufferedAction()
			inst:PushBufferedAction(buffaction)
			return true
		end
	end
	return false
end

local actionhandlers =
{
    ActionHandler(ACTIONS.CHOP,
        function(inst)
			if FixupWorkerCarry(inst, "swap_axe") then
				return "item_out_chop"
			elseif not inst.sg:HasStateTag("prechop") then
                return inst.sg:HasStateTag("chopping")
                    and "chop"
                    or "chop_start"
            end
        end),
    ActionHandler(ACTIONS.MINE,
        function(inst)
			if FixupWorkerCarry(inst, "swap_pickaxe") then
				return "item_out_mine"
			elseif not inst.sg:HasStateTag("premine") then
                return inst.sg:HasStateTag("mining")
                    and "mine"
                    or "mine_start"
            end
        end),
    ActionHandler(ACTIONS.DIG,
        function(inst)
			if FixupWorkerCarry(inst, "swap_shovel") then
				return "item_out_dig"
			elseif not inst.sg:HasStateTag("predig") then
                return inst.sg:HasStateTag("digging")
                    and "dig"
                    or "dig_start"
            end
        end),
    ActionHandler(ACTIONS.GIVE, "give"),
    ActionHandler(ACTIONS.GIVEALLTOPLAYER, "give"),
    ActionHandler(ACTIONS.DROP, "give"),
    ActionHandler(ACTIONS.PICKUP, "take"),
    ActionHandler(ACTIONS.CHECKTRAP, "take"),
    ActionHandler(ACTIONS.PICK,
		function(inst, action)
			return action.target ~= nil
				and (action.target.components.pickable ~= nil and (
						(action.target.components.pickable.jostlepick and "doshortaction") or -- Short action for jostling.
						(action.target.components.pickable.quickpick and "doshortaction") or
						"dolongaction"
					)) or
					(action.target.components.searchable ~= nil and (
						(action.target.components.searchable.jostlesearch and "doshortaction") or
						(action.target.components.searchable.quicksearch and "doshortaction") or
						"dolongaction"
					))
				or nil
		end),
}

local events =
{
    CommonHandlers.OnLocomote(true, false),
    --CommonHandlers.OnAttacked(),
    CommonHandlers.OnDeath(),
    --CommonHandlers.OnAttack(),
	EventHandler("attacked", function(inst, data)
		if not (inst.components.health:IsDead() or inst.components.health:IsInvincible()) then
			inst.sg:GoToState("disappear", data ~= nil and data.attacker or nil)
		end
	end),
	EventHandler("doattack", function(inst, data)
		if inst.components.health ~= nil and not inst.components.health:IsDead() and not inst.sg:HasStateTag("busy") then
			if inst.components.combat.attackrange == 5 then
				inst.sg:GoToState("lunge_pre", data ~= nil and data.target or nil)
			else
				inst.sg:GoToState("attack", data ~= nil and data.target or nil)
			end
		end
	end),
    EventHandler("dance", function(inst)
        if not inst.sg:HasStateTag("busy") and (inst._brain_dancedata ~= nil or not inst.sg:HasStateTag("dancing")) then
            inst.sg:GoToState("dance")
        end
    end),
}

local states =
{
	State{
		name = "spawn",
		tags = { "busy", "noattack", "temp_invincible" },

		onenter = function(inst, mult)
			inst.Physics:Stop()
			ToggleOffCharacterCollisions(inst)
			inst.AnimState:PlayAnimation("minion_spawn")
           -- inst.SoundEmitter:PlaySound("maxwell_rework/shadow_worker/spawn")
			mult = mult or (0.8 + math.random() * 0.2)
			inst.AnimState:SetDeltaTimeMultiplier(mult)

			mult = 1 / mult
			inst.sg.statemem.tasks =

			{
                inst:DoTaskInTime(0 * FRAMES * mult, DoSound, "maxwell_rework/shadow_worker/spawn"),
				inst:DoTaskInTime(0 * FRAMES * mult, TrySplashFX),
				inst:DoTaskInTime(20 * FRAMES * mult, TrySplashFX),
				inst:DoTaskInTime(44 * FRAMES * mult, TrySplashFX, "small"),
			}
			inst.sg:SetTimeout(70 * FRAMES * mult)
		end,

		ontimeout = function(inst)
			inst.sg:AddStateTag("caninterrupt")
			ToggleOnCharacterCollisions(inst)
			inst.AnimState:SetDeltaTimeMultiplier(1)
		end,

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					inst.sg:GoToState("idle")
				end
			end),
		},

		onexit = function(inst)
			if not inst.sg.statemem.spawn then
				ToggleOnCharacterCollisions(inst)
				inst.AnimState:SetDeltaTimeMultiplier(1)
			end
			for i, v in ipairs(inst.sg.statemem.tasks) do
				v:Cancel()
			end
		end,
	},

	State{
		name = "quickspawn",

		onenter = function(inst)
			SpawnPrefab("statue_transition_2").Transform:SetPosition(inst.Transform:GetWorldPosition())
			inst.sg:GoToState("idle")
		end,
	},

	State{
		name = "quickdespawn",

		onenter = function(inst)
			DoDespawnFX(inst)
			if inst.sg.mem.laststepsplash ~= GetTime() then
				TrySplashFX(inst)
			end
			inst:Remove()
		end,
	},

    State{
        name = "idle",
        tags = {"idle", "canrotate"},

        onenter = function(inst, pushanim)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("idle_loop", true)
			if inst:HasTag("shadowmarksman") then
				inst.components.combat:SetRange(TUNING.SLINGSHOT_DISTANCE, TUNING.SLINGSHOT_DISTANCE_MAX)
			elseif inst.components.timer ~= nil and not inst.components.timer:TimerExists("shadowstrike_cd") then
				inst.components.combat:SetRange(5)
			end
        end,
    },

	State{
		name = "ready_pre",
		tags = { "idle", "canrotate" },

		onenter = function(inst)
			inst.Physics:Stop()
			if inst:HasTag("shadowmarksman") then
				inst.AnimState:PlayAnimation("idle_loop", true)
				inst.components.combat:SetRange(TUNING.SLINGSHOT_DISTANCE, TUNING.SLINGSHOT_DISTANCE_MAX)
			else
				inst.AnimState:PlayAnimation("ready_stance_pre")
			end
			if not inst:HasTag("shadowmarksman") and inst.components.timer ~= nil and not inst.components.timer:TimerExists("shadowstrike_cd") then
				inst.components.combat:SetRange(5)
			end
		end,

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					inst.sg:GoToState(inst:HasTag("shadowmarksman") and "idle" or "ready")
				end
			end),
		},
	},

	State{
		name = "ready",
		tags = { "idle", "canrotate" },

		onenter = function(inst)
			inst.AnimState:PlayAnimation("ready_stance_loop", true)
		end,

		onupdate = function(inst)
			if not inst.components.combat:HasTarget() then
				inst.sg:GoToState("ready_pst")
			end
		end,
	},

	State{
		name = "ready_pst",
		tags = { "idle", "canrotate" },

		onenter = function(inst)
			inst.AnimState:PlayAnimation("ready_stance_pst")
		end,

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					inst.sg:GoToState("idle")
				end
			end),
		},
	},

    State{
        name = "run_start",
        tags = {"moving", "running", "canrotate"},

        onenter = function(inst)
            inst.components.locomotor:RunForward()
            inst.AnimState:PlayAnimation("run_pre")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("run")
                end
            end),
        },

        timeline =
        {
			TimeEvent(1 * FRAMES, TryStepSplash),
			TimeEvent(3 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("dontstarve/maxwell/shadowmax_step")
            end),
        },
    },

    State{
        name = "run",
        tags = {"moving", "running", "canrotate"},

        onenter = function(inst)
            inst.components.locomotor:RunForward()
            if not inst.AnimState:IsCurrentAnimation("run_loop") then
                inst.AnimState:PlayAnimation("run_loop", true)
            end
            inst.sg:SetTimeout(inst.AnimState:GetCurrentAnimationLength())
        end,

        timeline =
        {
			TimeEvent(5 * FRAMES, TryStepSplash),
            TimeEvent(7 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("dontstarve/maxwell/shadowmax_step")
				inst.sg.mem.laststepsplash = GetTime()
            end),
			TimeEvent(13 * FRAMES, TryStepSplash),
            TimeEvent(15 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound("dontstarve/maxwell/shadowmax_step")
				inst.sg.mem.laststepsplash = GetTime()
            end),
        },

        ontimeout = function(inst)
			inst.sg.statemem.running = true
            inst.sg:GoToState("run")
        end,

		onexit = function(inst)
			if not inst.sg.statemem.running then
				TryStepSplash(inst)
			end
		end,
    },

    State{
        name = "run_stop",
        tags = {"canrotate", "idle"},

        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("run_pst")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },
    },

	State{
        name = "attack",
		tags = {"attack", "abouttoattack", "busy"},

		onenter = function(inst, target)
			inst.components.locomotor:Stop()
			if inst:HasTag("shadowmarksman") then
				inst.AnimState:PlayAnimation("slingshot_pre")
				inst.AnimState:PushAnimation("slingshot", false)
			else
				inst.AnimState:PlayAnimation("atk_pre")
				inst.AnimState:PushAnimation("atk", false)
			end

			inst.components.combat:StartAttack()
			if target == nil then
				target = inst.components.combat.target
			end
			if target ~= nil and target:IsValid() then
				inst.sg.statemem.target = target
				inst:ForceFacePoint(target.Transform:GetWorldPosition())
			else
				target = nil
			end
			if not inst:HasTag("shadowmarksman") then
				CheckCombatLeader(inst, target)
			end
        end,

        timeline =
        {
			TimeEvent(5 * FRAMES, function(inst)
				if inst:HasTag("shadowmarksman") then
					inst.SoundEmitter:PlaySound("dontstarve/characters/walter/slingshot/stretch")
				end
			end),
			TimeEvent(6 * FRAMES, function(inst)
				if not inst:HasTag("shadowmarksman") then
					inst.SoundEmitter:PlaySound("dontstarve/wilson/attack_nightsword")
				end
			end),
			TimeEvent(8*FRAMES, function(inst)
				inst.sg:RemoveStateTag("abouttoattack")
				local target = inst.sg.statemem.target
				if inst:HasTag("shadowmarksman") then
					CheckLeaderShadowLevel(inst, target ~= nil and target:IsValid() and target or nil)
					LaunchMarksmanProjectile(inst, target)
					inst.SoundEmitter:PlaySound("dontstarve/characters/walter/slingshot/shoot")
				else
					CheckLeaderShadowLevel(inst, target ~= nil and target:IsValid() and target or nil)
					inst.sg.statemem.recoilstate = "attack_recoil"
					inst.components.combat:DoAttack(target) --purposely not checking valid for this call
				end
			end),
            TimeEvent(12*FRAMES, function(inst) -- Keep FRAMES time synced up with ShouldKiteProtector.
                inst.sg:RemoveStateTag("busy")
            end),
            TimeEvent(13*FRAMES, function(inst)
                inst.sg:RemoveStateTag("attack")
            end),
			TimeEvent(16 * FRAMES, function(inst)
				if inst.isprotector and not inst:HasTag("shadowmarksman") and inst.components.combat:HasTarget() then
					inst.sg:GoToState("ready_pre")
				end
			end),
        },

        events =
        {
			EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },

		onexit = function(inst)
			if inst.sg:HasStateTag("abouttoattack") then
				inst.components.combat:CancelAttack()
			end
		end,
    },

    State{
        name = "death",
        tags = {"busy"},

        onenter = function(inst)
            inst.Physics:Stop()
            --FixupWorkerCarry(inst, nil)
            inst.AnimState:PlayAnimation("death")
        end,

		timeline =
		{
			TimeEvent(13 * FRAMES, TrySplashFX),
			TimeEvent(38 * FRAMES, TrySplashFX),
		},

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
					DoDespawnFX(inst)
					TrySplashFX(inst)
                    inst:Remove()
                end
            end),
        },
    },

    State{
        name = "take",
        tags = {"busy"},
        onenter = function(inst)
            inst.components.locomotor:Stop()
            inst.AnimState:PlayAnimation("pickup")
            inst.AnimState:PushAnimation("pickup_pst", false)
        end,

        timeline =
        {
            TimeEvent(6 * FRAMES, function(inst)
                inst:PerformBufferedAction()
            end),
        },

        events=
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle") 
                end
            end),
        },
    },

    State{
        name = "give",
        tags = {"busy"},
        onenter = function(inst)
            inst.components.locomotor:Stop()
            inst.AnimState:PlayAnimation("give")
            inst.AnimState:PushAnimation("give_pst", false)
        end,

        timeline =
        {
            TimeEvent(14 * FRAMES, function(inst)
                inst:PerformBufferedAction()
            end),
        },

        events=
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },
    },

    State{
        name = "hit",
        tags = {"busy"},

        onenter = function(inst)
            inst:ClearBufferedAction()
            inst.AnimState:PlayAnimation("hit")
            inst.Physics:Stop()
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },

        timeline =
        {
            TimeEvent(3*FRAMES, function(inst)
                inst.sg:RemoveStateTag("busy")
            end),
        },
    },

    State{
        name = "stunned",
        tags = {"busy", "canrotate"},

        onenter = function(inst)
            inst:ClearBufferedAction()
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("idle_sanity_pre")
            inst.AnimState:PushAnimation("idle_sanity_loop", true)
            inst.sg:SetTimeout(5)
        end,

        ontimeout = function(inst)
            inst.sg:GoToState("idle")
        end,
    },

    State{
        name = "chop_start",
        tags = {"prechop", "working"},

        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("chop_pre")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("chop")
                end
            end),
        },
    },

    State{
        name = "chop",
        tags = {"prechop", "chopping", "working"},

        onenter = function(inst)
			inst.sg.statemem.action = inst:GetBufferedAction()
            inst.AnimState:PlayAnimation("chop_loop")
        end,

        timeline =
        {
            TimeEvent(2 * FRAMES, function(inst)
                inst:PerformBufferedAction()
            end),
			TimeEvent(14 * FRAMES, function(inst)
                inst.sg:RemoveStateTag("prechop")
				TryRepeatAction(inst, inst.sg.statemem.action)
            end),
            TimeEvent(16*FRAMES, function(inst)
                inst.sg:RemoveStateTag("chopping")
            end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },
    },

    State{
        name = "mine_start",
        tags = {"premine", "working"},

        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("pickaxe_pre")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("mine")
                end
            end),
        },
    },

    State{
        name = "mine",
        tags = {"premine", "mining", "working"},

        onenter = function(inst)
			inst.sg.statemem.action = inst:GetBufferedAction()
            inst.AnimState:PlayAnimation("pickaxe_loop")
        end,

        timeline =
        {
            TimeEvent(7 * FRAMES, function(inst)
				if inst.sg.statemem.action ~= nil then
					PlayMiningFX(inst, inst.sg.statemem.action.target)
					inst.sg.statemem.recoilstate = "mine_recoil"
                    inst:PerformBufferedAction()
                end
            end),
            TimeEvent(14 * FRAMES, function(inst)
				inst.sg:RemoveStateTag("premine")
				TryRepeatAction(inst, inst.sg.statemem.action)
            end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.AnimState:PlayAnimation("pickaxe_pst")
                    inst.sg:GoToState("idle", true)
                end
            end),
        },
    },

	State{
		name = "mine_recoil",
		tags = { "busy", "recoil" },

		onenter = function(inst, data)
			inst.components.locomotor:Stop()
			inst:ClearBufferedAction()

			inst.AnimState:PlayAnimation("pickaxe_recoil")
			if data ~= nil and data.target ~= nil and data.target:IsValid() then
                local pos = data.target:GetPosition()

                if data.target.recoil_effect_offset then
                    pos = pos + data.target.recoil_effect_offset
                end
                
				SpawnPrefab("impact").Transform:SetPosition(pos:Get())
			end
			inst.Physics:SetMotorVelOverride(-6, 0, 0)
		end,

		onupdate = function(inst)
			if inst.sg.statemem.speed ~= nil then
				inst.Physics:SetMotorVelOverride(inst.sg.statemem.speed, 0, 0)
				inst.sg.statemem.speed = inst.sg.statemem.speed * 0.75
			end
		end,

		timeline =
		{
			FrameEvent(4, function(inst)
				inst.sg.statemem.speed = -3
			end),
			FrameEvent(17, function(inst)
				inst.sg.statemem.speed = nil
				inst.Physics:ClearMotorVelOverride()
				inst.Physics:Stop()
			end),
			FrameEvent(23, function(inst)
				inst.sg:RemoveStateTag("busy")
			end),
			FrameEvent(30, function(inst)
				inst.sg:GoToState("idle", true)
			end),
		},

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					inst.sg:GoToState("idle")
				end
			end),
		},

		onexit = function(inst)
			inst.Physics:ClearMotorVelOverride()
			inst.Physics:Stop()
		end,
	},

	State{
		name = "attack_recoil",
		tags = { "busy", "recoil" },

		onenter = function(inst, data)
			inst.components.locomotor:Stop()
			inst:ClearBufferedAction()

			inst.AnimState:PlayAnimation("atk_recoil")
			if data ~= nil and data.target ~= nil and data.target:IsValid() then
                local pos = data.target:GetPosition()

                if data.target.recoil_effect_offset then
                    pos = pos + data.target.recoil_effect_offset
                end
                
				SpawnPrefab("impact").Transform:SetPosition(pos:Get())
			end
			inst.Physics:SetMotorVelOverride(-6, 0, 0)
		end,

		onupdate = function(inst)
			if inst.sg.statemem.speed ~= nil then
				inst.Physics:SetMotorVelOverride(inst.sg.statemem.speed, 0, 0)
				inst.sg.statemem.speed = inst.sg.statemem.speed * 0.75
			end
		end,

		timeline =
		{
			FrameEvent(4, function(inst)
				inst.sg.statemem.speed = -3
			end),
			FrameEvent(17, function(inst)
				inst.sg.statemem.speed = nil
				inst.Physics:ClearMotorVelOverride()
				inst.Physics:Stop()
			end),
			FrameEvent(23, function(inst)
				inst.sg:RemoveStateTag("busy")
			end),
			FrameEvent(30, function(inst)
				inst.sg:GoToState("idle", true)
			end),
		},

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					inst.sg:GoToState("idle")
				end
			end),
		},

		onexit = function(inst)
			inst.Physics:ClearMotorVelOverride()
			inst.Physics:Stop()
		end,
	},

    State{
        name = "dig_start",
        tags = {"predig", "working"},

        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("shovel_pre")
        end,

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("dig")
                end
            end),
        },
    },

    State{
        name = "dig",
        tags = {"predig", "digging", "working"},

        onenter = function(inst)
			inst.sg.statemem.action = inst:GetBufferedAction()
            inst.AnimState:PlayAnimation("shovel_loop")
        end,

        timeline =
        {
            TimeEvent(15 * FRAMES, function(inst)
                inst:PerformBufferedAction()
                inst.SoundEmitter:PlaySound("dontstarve/wilson/dig")
            end),
            TimeEvent(35 * FRAMES, function(inst)
                inst.sg:RemoveStateTag("predig")
				TryRepeatAction(inst, inst.sg.statemem.action, true)
            end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.AnimState:PlayAnimation("shovel_pst")
                    inst.sg:GoToState("idle", true)
                end
            end),
        },
    },

    State{
        name = "dance",
        tags = {"idle", "dancing"},

        onenter = function(inst)
            inst.components.locomotor:Stop()
            inst:ClearBufferedAction()
            local ignoreplay = inst.AnimState:IsCurrentAnimation("run_pst")
            if inst._brain_dancedata and #inst._brain_dancedata > 0 then
                for _, data in ipairs(inst._brain_dancedata) do
                    if data.play and not ignoreplay then
                        inst.AnimState:PlayAnimation(data.anim, data.loop)
                    else
                        inst.AnimState:PushAnimation(data.anim, data.loop)
                    end
                end
            else
                -- NOTES(JBK): No dance data do default dance.
                if ignoreplay then
                    inst.AnimState:PushAnimation("emoteXL_pre_dance0")
                else
                    inst.AnimState:PlayAnimation("emoteXL_pre_dance0")
                end
                inst.AnimState:PushAnimation("emoteXL_loop_dance0", true)
            end
            inst._brain_dancedata = nil -- Remove reference no matter what so garbage collector can pick up the memory.
        end,
    },

    State{
        name = "dolongaction",
        tags = { "doing", "busy", "nodangle" },

        onenter = function(inst, timeout)
            if timeout == nil then
                timeout = 1
            elseif timeout > 1 then
                inst.sg:AddStateTag("slowaction")
            end
            inst.sg:SetTimeout(timeout)
            inst.components.locomotor:Stop()
            inst.AnimState:PlayAnimation("build_pre")
            inst.AnimState:PushAnimation("build_loop", true)
            if inst.bufferedaction ~= nil then
                inst.sg.statemem.action = inst.bufferedaction
                if inst.bufferedaction.target ~= nil and inst.bufferedaction.target:IsValid() then
					inst.bufferedaction.target:PushEvent("startlongaction", inst)
                end
            end
        end,

        timeline =
        {
            TimeEvent(4 * FRAMES, function(inst)
                inst.sg:RemoveStateTag("busy")
            end),
        },

        ontimeout = function(inst)
            inst.AnimState:PlayAnimation("build_pst")
            inst:PerformBufferedAction()
        end,

        events =
        {
            EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },

        onexit = function(inst)
            if inst.bufferedaction == inst.sg.statemem.action then
                inst:ClearBufferedAction()
            end
        end,
    },

    State{
        name = "doshortaction",
        tags = { "doing", "busy" },

        onenter = function(inst)
            inst.components.locomotor:Stop()
			inst.AnimState:PlayAnimation("pickup")
			inst.AnimState:PushAnimation("pickup_pst", false)

            inst.sg.statemem.action = inst.bufferedaction
            inst.sg:SetTimeout(10 * FRAMES)
        end,

        timeline =
        {
            TimeEvent(4 * FRAMES, function(inst)
                inst.sg:RemoveStateTag("busy")
            end),
            TimeEvent(6 * FRAMES, function(inst)
                inst:PerformBufferedAction()
            end),
        },

        ontimeout = function(inst)
            --pickup_pst should still be playing
            inst.sg:GoToState("idle", true)
        end,

        onexit = function(inst)
            if inst.bufferedaction == inst.sg.statemem.action then
                inst:ClearBufferedAction()
            end
        end,
    },

    State{
        name = "jumpout",
        tags = { "busy", "canrotate", "jumping" },

        onenter = function(inst)
            inst.components.locomotor:Stop()
            inst.AnimState:PlayAnimation("jumpout")
            inst.Physics:SetMotorVel(4, 0, 0)
			inst.Physics:SetCollisionMask(COLLISION.GROUND)
        end,

        timeline =
        {
            TimeEvent(10 * FRAMES, function(inst)
                inst.Physics:SetMotorVel(3, 0, 0)
            end),
            TimeEvent(15 * FRAMES, function(inst)
                inst.Physics:SetMotorVel(2, 0, 0)
            end),
            TimeEvent(15.2 * FRAMES, function(inst)
                inst.sg.statemem.physicson = true
				inst.Physics:SetCollisionMask(
					COLLISION.WORLD,
					COLLISION.CHARACTERS,
					COLLISION.GIANTS
				)
            end),
            TimeEvent(17 * FRAMES, function(inst)
                inst.Physics:SetMotorVel(1, 0, 0)
            end),
            TimeEvent(18 * FRAMES, function(inst)
                inst.Physics:Stop()
            end),
        },

        events =
        {
            EventHandler("animover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },

        onexit = function(inst)
            if not inst.sg.statemem.physicson then
				inst.Physics:SetCollisionMask(
					COLLISION.WORLD,
					COLLISION.CHARACTERS,
					COLLISION.GIANTS
				)
            end
        end,
    },

	State{
		name = "disappear",
		tags = { "busy", "noattack", "temp_invincible", "phasing" },

		onenter = function(inst, attacker)
			inst.components.locomotor:Stop()
			inst:ClearBufferedAction()
			ToggleOffCharacterCollisions(inst)
			inst.AnimState:PlayAnimation("disappear")
			if attacker ~= nil and attacker:IsValid() then
				inst.sg.statemem.attackerpos = attacker:GetPosition()
			end
			TrySplashFX(inst, "small")
			inst:DropAggro()
		end,

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					local theta =
						inst.sg.statemem.attackerpos ~= nil and
						inst:GetAngleToPoint(inst.sg.statemem.attackerpos) or
						inst.Transform:GetRotation()

					theta = (theta + 165 + math.random() * 30) * DEGREES

					local pos = inst:GetPosition()
					pos.y = 0

					local offs =
						FindWalkableOffset(pos, theta, 4 + math.random(), 8, false, true, NotBlocked, true, true) or
						FindWalkableOffset(pos, theta, 2 + math.random(), 6, false, true, NotBlocked, true, true)

					if (type(offs) == "table" or type(offs) == "userdata") and offs.x ~= nil and offs.z ~= nil then
						pos.x = pos.x + offs.x
						pos.z = pos.z + offs.z
					end
					inst.Physics:Teleport(pos:Get())
					if inst.sg.statemem.attackerpos ~= nil then
						inst:ForceFacePoint(inst.sg.statemem.attackerpos)
					end

					inst.sg.statemem.appearing = true
					inst.sg:GoToState("appear")
				end
			end),
		},

		onexit = function(inst)
			if not inst.sg.statemem.appearing then
				ToggleOnCharacterCollisions(inst)
			end
		end,
	},

	State{
		name = "appear",
		tags = { "busy", "noattack", "temp_invincible", "phasing" },

		onenter = function(inst)
			inst.components.locomotor:Stop()
			ToggleOffCharacterCollisions(inst)
			inst.AnimState:PlayAnimation("appear")
		end,

		timeline =
		{
			TimeEvent(9 * FRAMES, function(inst)
				TrySplashFX(inst, "small")
			end),
			TimeEvent(11 * FRAMES, function(inst)
				inst.sg:RemoveStateTag("temp_invincible")
				inst.sg:RemoveStateTag("phasing")
				ToggleOnCharacterCollisions(inst)
			end),
			TimeEvent(13 * FRAMES, function(inst)
				inst.sg:RemoveStateTag("busy")
			end),
		},

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					inst.sg:GoToState("idle")
				end
			end),
		},

		onexit = ToggleOnCharacterCollisions,
	},

	State{
		name = "lunge_pre",
		tags = { "attack", "busy" },

		onenter = function(inst, target)
			inst:StopBrain("SGshadowwaxwell_lunge")
			inst.components.locomotor:Stop()
			inst.AnimState:SetBankAndPlayAnimation("lavaarena_shadow_lunge", "lunge_pre")

			inst.components.combat:StartAttack()
			if target == nil then
				target = inst.components.combat.target
			end
			if target ~= nil and target:IsValid() then
				inst.sg.statemem.target = target
				inst.sg.statemem.targetpos = target:GetPosition()
				inst:ForceFacePoint(inst.sg.statemem.targetpos:Get())
			else
				target = nil
			end
			CheckCombatLeader(inst, target)
		end,

		onupdate = function(inst)
			if inst.sg.statemem.target ~= nil then
				if inst.sg.statemem.target:IsValid() then
					inst.sg.statemem.targetpos = inst.sg.statemem.target:GetPosition()
				else
					inst.sg.statemem.target = nil
				end
			end
		end,

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					inst.sg.statemem.lunge = true
					inst.sg:GoToState("lunge_loop", { target = inst.sg.statemem.target, targetpos = inst.sg.statemem.targetpos })
				end
			end),
		},

		onexit = function(inst)
			if not inst.sg.statemem.lunge then
				inst.components.combat:CancelAttack()
				inst:RestartBrain("SGshadowwaxwell_lunge")
				inst.AnimState:SetBank("wilson")
			end
		end,
	},

	State{
		name = "lunge_loop",
		tags = { "attack", "busy", "noattack", "temp_invincible" },

		onenter = function(inst, data)
			inst.AnimState:PlayAnimation("lunge_loop") --NOTE: this anim NOT a loop yo
			inst.SoundEmitter:PlaySound("dontstarve/wilson/attack_nightsword")
			inst.SoundEmitter:PlaySound("dontstarve/impacts/impact_shadow_med_sharp")
			inst.Physics:ClearCollidesWith(COLLISION.GIANTS)
			ToggleOffCharacterCollisions(inst)
			TrySplashFX(inst)
			inst:DropAggro()

			if inst.components.timer ~= nil then
				inst.components.timer:StopTimer("shadowstrike_cd")
				inst.components.timer:StartTimer("shadowstrike_cd", TUNING.SHADOWWAXWELL_SHADOWSTRIKE_COOLDOWN)
			end

			if data ~= nil then
				if data.target ~= nil and data.target:IsValid() then
					inst.sg.statemem.target = data.target
					inst:ForceFacePoint(data.target.Transform:GetWorldPosition())
				elseif data.targetpos ~= nil then
					inst:ForceFacePoint(data.targetpos)
				end
			end
			inst.Physics:SetMotorVelOverride(35, 0, 0)

			inst.sg:SetTimeout(8 * FRAMES)
		end,

		onupdate = function(inst)
			if inst.sg.statemem.attackdone then
				return
			end
			local target = inst.sg.statemem.target
			if target == nil or not target:IsValid() then
				if inst.sg.statemem.animdone then
					inst.sg.statemem.lunge = true
					inst.sg:GoToState("lunge_pst")
					return
				end
				inst.sg.statemem.target = nil
			elseif inst:IsNear(target, 1) then
				local fx = SpawnPrefab(math.random() < .5 and "shadowstrike_slash_fx" or "shadowstrike_slash2_fx")
				local x, y, z = target.Transform:GetWorldPosition()
				fx.Transform:SetPosition(x, y + 1.5, z)
				fx.Transform:SetRotation(inst.Transform:GetRotation())

				CheckLeaderShadowLevel(inst, target)
				inst.components.combat.externaldamagemultipliers:SetModifier(inst, TUNING.SHADOWWAXWELL_SHADOWSTRIKE_DAMAGE_MULT, "shadowstrike")
				inst.components.combat:DoAttack(target)
				--Drop aggro again here, since we're in i-frames, and we might've
				--triggered spawners, and they will be initially targeted on me.
				inst:DropAggro()
				if inst.sg.statemem.animdone then
					inst.sg.statemem.lunge = true
					inst.sg:GoToState("lunge_pst", target)
					return
				end
				inst.sg.statemem.attackdone = true
			end
		end,

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					if inst.sg.statemem.attackdone or inst.sg.statemem.target == nil then
						inst.sg.statemem.lunge = true
						inst.sg:GoToState("lunge_pst", inst.sg.statemem.target)
						return
					end
					inst.sg.statemem.animdone = true
				end
			end),
		},

		ontimeout = function(inst)
			inst.sg.statemem.lunge = true
			inst.sg:GoToState("lunge_pst")
		end,

		onexit = function(inst)
			inst.components.combat.externaldamagemultipliers:RemoveModifier(inst, "shadowstrike")
			inst.components.combat:SetRange(2)
			if not inst.sg.statemem.lunge then
				inst:RestartBrain("SGshadowwaxwell_lunge")
				inst.AnimState:SetBank("wilson")
				inst.Physics:CollidesWith(COLLISION.GIANTS)
				ToggleOnCharacterCollisions(inst)
			end
		end,
	},

	State{
		name = "lunge_pst",
		tags = { "busy", "noattack", "temp_invincible", "phasing" },

		onenter = function(inst, target)
			inst.AnimState:PlayAnimation("lunge_pst")
			inst.Physics:SetMotorVelOverride(12, 0, 0)
			inst.sg.statemem.target = target
		end,

		onupdate = function(inst)
			inst.Physics:SetMotorVelOverride(inst.Physics:GetMotorVel() * .8, 0, 0)
		end,

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					local target = inst.sg.statemem.target
					local pos = inst:GetPosition()
					pos.y = 0
					local moved = false
					if target ~= nil then
						if target:IsValid() then
							local targetpos = target:GetPosition()
							local dx, dz = targetpos.x - pos.x, targetpos.z - pos.z
							local radius = math.sqrt(dx * dx + dz * dz)
							local theta = math.atan2(dz, -dx)
							local offs = FindWalkableOffset(targetpos, theta, radius + 3 + math.random(), 8, false, true, NotBlocked, true, true)
							if (type(offs) == "table" or type(offs) == "userdata") and offs.x ~= nil and offs.z ~= nil then
								pos.x = targetpos.x + offs.x
								pos.z = targetpos.z + offs.z
								inst.Physics:Teleport(pos:Get())
								moved = true
							end
						else
							target = nil
						end
					end
					if not moved and not TheWorld.Map:IsPassableAtPoint(pos.x, 0, pos.z, true) then
						pos = FindNearbyLand(pos, 1) or FindNearbyLand(pos, 2)
						if pos ~= nil then
							inst.Physics:Teleport(pos.x, 0, pos.z)
						end
					end

					if target ~= nil then
						inst:ForceFacePoint(target.Transform:GetWorldPosition())
					end

					inst.sg.statemem.appearing = true
					inst.sg:GoToState("appear")
				end
			end),
		},

		onexit = function(inst)
			inst:RestartBrain("SGshadowwaxwell_lunge")
			inst.AnimState:SetBank("wilson")
			inst.Physics:CollidesWith(COLLISION.GIANTS)
			if not inst.sg.statemem.appearing then
				ToggleOnCharacterCollisions(inst)
			end
		end,
	},

	State{
		name = "item_out_chop",
		onenter = function(inst) inst.sg:GoToState("item_out", "chop") end,
	},

	State{
		name = "item_out_mine",
		onenter = function(inst) inst.sg:GoToState("item_out", "mine") end,
	},

	State{
		name = "item_out_dig",
		onenter = function(inst) inst.sg:GoToState("item_out", "dig") end,
	},

	State{
		name = "item_out",
		tags = { "working" },

		onenter = function(inst, action)
			inst.components.locomotor:StopMoving()
			inst.AnimState:PlayAnimation("item_out")
			if action ~= nil then
				inst.sg:AddStateTag("pre"..action)
				inst.sg.statemem.action = action
				inst.sg:SetTimeout(9 * FRAMES)
			else
				inst.sg:RemoveStateTag("working")
				inst.sg:AddStateTag("idle")
			end
		end,

		ontimeout = function(inst)
			inst.sg:GoToState(inst.sg.statemem.action.."_start")
		end,

		events =
		{
			EventHandler("animover", function(inst)
				if inst.AnimState:AnimDone() then
					inst.sg:GoToState("idle")
				end
			end),
		},
	},
}

return StateGraph("shadow_marksman", states, events, "spawn", actionhandlers)
