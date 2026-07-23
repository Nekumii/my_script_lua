local C = require("reticule/constants")

local mod_config

local M = {}

local VANILLA_SUMMON_CAST_RANGE = 8
local VANILLA_JOURNAL_RETICULE_PREFABS =
{
	reticuleaoe_1d2_12 = true,
	reticuleaoe_1_6 = true,
	reticuleaoe = true,
}
local ApplyReticuleTargetingHooks

local function GetModConfig()
	if mod_config == nil then
		mod_config = require("mod_config")
	end
	return mod_config
end

function M.IsReticuleRangeLockEnabled()
	if not GetModConfig().IsWaxwellEnabled() then
		return false
	end
	return GetModConfig().IsWaxwellReticuleRangeLockEnabled()
end

function M.GetVanillaSummonCastRange()
	return VANILLA_SUMMON_CAST_RANGE
end

local function ResolveTargetPoint(pos)
	if pos == nil then
		return nil
	end

	local x, y, z = pos.x, pos.y, pos.z
	if x == nil and pos.Get ~= nil then
		x, y, z = pos:Get()
	end
	if x == nil or z == nil then
		return nil
	end

	return x, y or 0, z
end

function M.ClampPointToCastRange(origin_x, origin_z, pos, range)
	local x, y, z = ResolveTargetPoint(pos)
	if x == nil or z == nil or origin_x == nil or origin_z == nil or range == nil then
		return pos
	end

	local dx = x - origin_x
	local dz = z - origin_z
	local dsq = dx * dx + dz * dz
	local range_sq = range * range
	if dsq <= range_sq + .001 then
		return Vector3(x, y, z)
	end
	if dsq <= 0 then
		return Vector3(origin_x, y, origin_z)
	end

	local scale = range / math.sqrt(dsq)
	return Vector3(origin_x + dx * scale, y, origin_z + dz * scale)
end

function M.IsPointWithinCastRange(origin_x, origin_z, pos, range)
	local x, pos_y, z = ResolveTargetPoint(pos)
	if x == nil or z == nil or origin_x == nil or origin_z == nil or range == nil then
		return false
	end

	local dx = x - origin_x
	local dz = z - origin_z
	return dx * dx + dz * dz <= range * range + .001
end

function M.MakeCastRangeMouseTargetFn(range, origin_fn)
	return function(inst, mousepos)
		if mousepos == nil or range == nil then
			return mousepos
		end

		local origin_x, origin_z
		if origin_fn ~= nil then
			origin_x, origin_z = origin_fn(inst)
		else
			local player = rawget(_G, "ThePlayer")
			if player == nil or not player:IsValid() or player.Transform == nil then
				return mousepos
			end
			local px, pos_y, pz = player.Transform:GetWorldPosition()
			origin_x, origin_z = px, pz
		end

		if origin_x == nil or origin_z == nil then
			return mousepos
		end

		return M.ClampPointToCastRange(origin_x, origin_z, mousepos, range)
	end
end

local function IsVanillaJournalReticulePrefab(prefab)
	return prefab ~= nil and VANILLA_JOURNAL_RETICULE_PREFABS[prefab] == true
end

local function ClearModReticuleVisualFields(reticule)
	if reticule == nil then
		return
	end

	reticule.scale = nil
	reticule.updatepositionfn = nil
end

local function DestroyActiveReticuleVisualIfPrefabMismatch(active_reticule)
	if active_reticule == nil
		or active_reticule.reticuleprefab == nil
		or active_reticule.reticule == nil
		or active_reticule.reticule.prefab == active_reticule.reticuleprefab then
		return
	end

	if active_reticule.DestroyReticule ~= nil then
		active_reticule:DestroyReticule()
	end
end

function M.IsVanillaJournalReticulePrefab(prefab)
	return IsVanillaJournalReticulePrefab(prefab)
end

local function IsModCustomJournalReticule(inst)
	return inst ~= nil
		and (inst._waxwell_umbral_rift_active == true or inst._skilltree_reticule_scale ~= nil)
end

function M.ResetVanillaJournalCastRange(inst, opts)
	if inst == nil or not inst:IsValid() then
		return
	end

	opts = opts or {}
	local clear_repeat_cast = opts.clear_repeat_cast ~= false

	inst._waxwell_umbral_rift_active = nil
	inst._skilltree_reticule_scale = nil
	inst._skilltree_reticule_anim = nil
	inst._skilltree_reticule_work_radius = nil

	M.ClearReticuleTargetingHooks(inst)

	local aoetargeting = inst.components ~= nil and inst.components.aoetargeting or nil
	if aoetargeting == nil then
		return
	end

	local range = M.GetVanillaSummonCastRange()
	if aoetargeting.SetRange ~= nil then
		aoetargeting:SetRange(range)
	end
	if aoetargeting.reticule ~= nil then
		aoetargeting.reticule.twinstickrange = range
		ClearModReticuleVisualFields(aoetargeting.reticule)
	end

	local active_reticule = inst.components ~= nil and inst.components.reticule or nil
	if active_reticule ~= nil then
		ClearModReticuleVisualFields(active_reticule)
	end

	if aoetargeting.SetDeployRadius ~= nil then
		aoetargeting:SetDeployRadius(0)
	end
	if clear_repeat_cast and aoetargeting.SetShouldRepeatCastFn ~= nil then
		aoetargeting:SetShouldRepeatCastFn(nil)
	end

	if M.IsReticuleRangeLockEnabled() then
		local validfn = aoetargeting.reticule ~= nil and aoetargeting.reticule.validfn or nil
		ApplyReticuleTargetingHooks(inst, aoetargeting, M.MakeCastRangeMouseTargetFn(range, nil), validfn)
	end
end

local function SyncVanillaJournalReticuleHooks(inst, aoetargeting, active_reticule)
	if active_reticule ~= nil and aoetargeting ~= nil and aoetargeting.reticule ~= nil then
		active_reticule.mousetargetfn = aoetargeting.reticule.mousetargetfn
		active_reticule.validfn = aoetargeting.reticule.validfn
		if aoetargeting.reticule.twinstickrange ~= nil then
			active_reticule.twinstickrange = aoetargeting.reticule.twinstickrange
		end
		ClearModReticuleVisualFields(active_reticule)
	end
end

-- คืน journal เป็นค่า vanilla (range 8) หลังออกจาก UR / spell mod — ทำแม้ reticule lock ปิด
function M.PrepareVanillaJournalSpellReticule(inst, aoetargeting, active_reticule)
	if inst == nil or not inst:IsValid() then
		return
	end

	aoetargeting = aoetargeting or (inst.components ~= nil and inst.components.aoetargeting or nil)
	if aoetargeting == nil or aoetargeting.reticule == nil then
		return
	end

	active_reticule = active_reticule or (inst.components ~= nil and inst.components.reticule or nil)

	local prefab = (active_reticule ~= nil and active_reticule.reticuleprefab)
		or aoetargeting.reticule.reticuleprefab
	if not IsVanillaJournalReticulePrefab(prefab) then
		return
	end

	M.ResetVanillaJournalCastRange(inst, { clear_repeat_cast = false })
	SyncVanillaJournalReticuleHooks(inst, aoetargeting, active_reticule)
	DestroyActiveReticuleVisualIfPrefabMismatch(active_reticule)
end

-- สกิล vanilla — sync clamp ตอนเปิด reticule (lock On เท่านั้น, หลัง PrepareVanilla แล้ว)
function M.EnsureJournalReticuleRangeLock(inst, aoetargeting, active_reticule)
	if inst == nil then
		return
	end

	aoetargeting = aoetargeting or (inst.components ~= nil and inst.components.aoetargeting or nil)
	if aoetargeting == nil or aoetargeting.GetRange == nil then
		return
	end

	local prefab = aoetargeting.reticule ~= nil and aoetargeting.reticule.reticuleprefab or nil
	if IsVanillaJournalReticulePrefab(prefab) then
		M.PrepareVanillaJournalSpellReticule(inst, aoetargeting, active_reticule)
		return
	end

	if not M.IsReticuleRangeLockEnabled() then
		return
	end

	local range = aoetargeting:GetRange()
	if range == nil or range <= 0 then
		return
	end

	-- spell mod ที่ตั้ง mousetargetfn เอง (UR/EF/SS) — sync ลง active reticule แล้วจบ
	if IsModCustomJournalReticule(inst)
		and aoetargeting.reticule ~= nil
		and aoetargeting.reticule.mousetargetfn ~= nil then
		if active_reticule ~= nil and active_reticule.mousetargetfn == nil then
			active_reticule.mousetargetfn = aoetargeting.reticule.mousetargetfn
		end
		return
	end

	local mousetargetfn = M.MakeCastRangeMouseTargetFn(range, nil)
	local validfn = aoetargeting.reticule ~= nil and aoetargeting.reticule.validfn or nil
	ApplyReticuleTargetingHooks(inst, aoetargeting, mousetargetfn, validfn)
end

function M.ConfigureSpellCastRange(inst, aoetargeting, range, opts)
	if inst == nil or aoetargeting == nil or range == nil then
		return
	end

	opts = opts or {}

	aoetargeting:SetRange(range)

	if aoetargeting.reticule ~= nil then
		aoetargeting.reticule.twinstickrange = range
	end

	local mousetargetfn = opts.mousetargetfn
	if mousetargetfn == nil and M.IsReticuleRangeLockEnabled() then
		mousetargetfn = M.MakeCastRangeMouseTargetFn(range, opts.origin_fn)
	end

	ApplyReticuleTargetingHooks(inst, aoetargeting, mousetargetfn, opts.validfn)
end

local function NormalizeAnim(anim)
	if anim == "s" then
		return C.ANIM_SMALL
	end
	if anim == "l" then
		return C.ANIM_LARGE
	end
	return anim
end

function M.GetAnimName(anim)
	return C.ANIM[NormalizeAnim(anim)]
end

function M.GetWorkRadius(scale, anim)
	local anim_id = NormalizeAnim(anim)
	local factor = C.RANGE_PER_SCALE[anim_id]
	if factor == nil or scale == nil then
		return nil
	end
	return scale * factor
end

function M.GetScaleForWorkRadius(work_radius, anim)
	local anim_id = NormalizeAnim(anim)
	local factor = C.RANGE_PER_SCALE[anim_id]
	if factor == nil or work_radius == nil or factor == 0 then
		return nil
	end
	return work_radius / factor
end

function M.IsValidScale(scale)
	return scale ~= nil and scale >= C.DEBUG_SCALE_MIN and scale <= C.DEBUG_SCALE_MAX
end

function M.ConfigureGroundReticuleVisual(inst, scale, anim, opts)
	opts = opts or {}

	local anim_id = NormalizeAnim(anim)
	local anim_name = C.ANIM[anim_id]
	if anim_name == nil or scale == nil or inst == nil or inst.AnimState == nil then
		return false
	end

	inst.AnimState:SetBank("reticuleaoe")
	inst.AnimState:SetBuild("reticuleaoe")
	inst.AnimState:PlayAnimation(anim_name, opts.loop == true)
	inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGroundFixed)
	inst.AnimState:SetLayer(LAYER_WORLD_BACKGROUND)
	inst.AnimState:SetSortOrder(opts.sort_order or 3)
	inst.AnimState:SetScale(scale, scale)

	local colour = opts.multcolour
	if colour ~= nil then
		inst.AnimState:SetMultColour(colour[1], colour[2], colour[3], colour[4] or 1)
	else
		inst.AnimState:SetMultColour(1, 1, 1, opts.alpha or .95)
	end

	local addcolour = opts.addcolour
	if addcolour ~= nil then
		inst.AnimState:SetAddColour(addcolour[1], addcolour[2], addcolour[3], addcolour[4] or 0)
	end

	if opts.bloom then
		inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
	end

	inst._skilltree_reticule_anim = anim_id
	inst._skilltree_reticule_scale = scale

	return true
end

function M.ApplyReticuleScale(owner, entity)
	if owner == nil or entity == nil or entity.AnimState == nil then
		return
	end

	local scale = owner._skilltree_reticule_scale
	if scale == nil and owner.components ~= nil and owner.components.aoetargeting ~= nil then
		local aoetargeting_reticule = owner.components.aoetargeting.reticule
		if aoetargeting_reticule ~= nil then
			scale = aoetargeting_reticule.scale
		end
	end
	if scale == nil and owner.components ~= nil and owner.components.reticule ~= nil then
		scale = owner.components.reticule.scale
	end
	if scale ~= nil then
		entity.AnimState:SetScale(scale, scale)
	end
end

local function ResolveReticulePosition(pos)
	if pos == nil then
		return nil
	end
	if pos.GetPosition ~= nil then
		return pos:GetPosition()
	end
	if pos.x ~= nil and pos.z ~= nil then
		return pos
	end
	return pos
end

local function ReticuleUpdatePositionFn(owner, pos, entity, ease, smoothing, dt)
	M.ApplyReticuleScale(owner, entity)

	local pt = ResolveReticulePosition(pos)
	if pt ~= nil and entity ~= nil and entity.Transform ~= nil then
		if ease and dt and smoothing then
			local x0, _, z0 = entity.Transform:GetWorldPosition()
			local x = Lerp(x0, pt.x, dt * smoothing)
			local z = Lerp(z0, pt.z, dt * smoothing)
			entity.Transform:SetPosition(x, 0, z)
		else
			entity.Transform:SetPosition(pt.x, 0, pt.z)
		end
	end
end

local function EnsureReticuleTargetPos(reticule_component)
	if reticule_component == nil or reticule_component.targetpos ~= nil then
		return
	end

	local theinput = rawget(_G, "TheInput")
	if theinput ~= nil and theinput.GetWorldPosition ~= nil then
		reticule_component.targetpos = theinput:GetWorldPosition()
	elseif reticule_component.targetfn ~= nil then
		reticule_component.targetpos = reticule_component.targetfn(reticule_component.inst)
	end
end

local function TryRefreshPlayerReticule(inst)
	local theplayer = rawget(_G, "ThePlayer")
	if theplayer == nil or theplayer.components == nil or theplayer.components.playercontroller == nil then
		return
	end

	local pc = theplayer.components.playercontroller
	local reticule = pc.reticule
	if reticule ~= nil and reticule.inst == inst then
		local theinput = rawget(_G, "TheInput")
		if reticule.mouseenabled or (theinput ~= nil and theinput.ControllerAttached ~= nil and theinput:ControllerAttached()) then
			pc:RefreshReticule(inst)
			EnsureReticuleTargetPos(pc.reticule)
		end
	end
end

local function SyncPlayerControllerReticule(inst, mousetargetfn, validfn)
	local theplayer = rawget(_G, "ThePlayer")
	if theplayer == nil or theplayer.components == nil or theplayer.components.playercontroller == nil then
		return
	end

	local pc = theplayer.components.playercontroller
	if pc.reticule == nil or pc.reticule.inst ~= inst then
		return
	end

	pc.reticule.mousetargetfn = mousetargetfn
	pc.reticule.validfn = validfn
end

ApplyReticuleTargetingHooks = function(inst, aoetargeting, mousetargetfn, validfn)
	if aoetargeting == nil or aoetargeting.reticule == nil then
		return
	end

	aoetargeting.reticule.mousetargetfn = mousetargetfn
	aoetargeting.reticule.validfn = validfn

	local active_reticule = inst.components ~= nil and inst.components.reticule or nil
	if active_reticule ~= nil then
		active_reticule.mousetargetfn = mousetargetfn
		active_reticule.validfn = validfn
	end

	SyncPlayerControllerReticule(inst, mousetargetfn, validfn)
end

function M.GetWaxwellJournalFromDoer(doer)
	if doer == nil then
		return nil
	end

	local pc = doer.components ~= nil and doer.components.playercontroller or nil
	if pc ~= nil and pc.reticule ~= nil and pc.reticule.inst ~= nil and pc.reticule.inst.prefab == "waxwelljournal" then
		return pc.reticule.inst
	end

	if doer.replica ~= nil and doer.replica.inventory ~= nil then
		local book = doer.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
		if book ~= nil and book.prefab == "waxwelljournal" then
			return book
		end
	end

	if doer.components ~= nil and doer.components.inventory ~= nil then
		local book = doer.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
		if book ~= nil and book.prefab == "waxwelljournal" then
			return book
		end
	end

	return nil
end

function M.ClearReticuleTargetingHooks(inst)
	if inst == nil then
		return
	end

	local aoetargeting = inst.components ~= nil and inst.components.aoetargeting or nil
	ApplyReticuleTargetingHooks(inst, aoetargeting, nil, nil)
end

local function SyncActiveReticuleComponent(inst, aoetargeting, reticule, prefabs, opts)
	local active_reticule = inst.components.reticule
	if active_reticule == nil then
		return
	end

	if active_reticule.reticuleprefab ~= prefabs.reticule and active_reticule.DestroyReticule ~= nil then
		active_reticule:DestroyReticule()
	end

	active_reticule.reticuleprefab = prefabs.reticule
	active_reticule.pingprefab = prefabs.ping
	active_reticule.scale = reticule.scale
	active_reticule.updatepositionfn = ReticuleUpdatePositionFn

	if active_reticule.reticule ~= nil then
		M.ApplyReticuleScale(inst, active_reticule.reticule)
	end

	EnsureReticuleTargetPos(active_reticule)
end

-- scale = reticule AnimState scale, anim = 1/2 or "s"/"l"
-- opts.auto_work_radius = true → SetDeployRadius ตามสูตร และคืนค่าวงทำงาน (number)
-- สำเร็จโดยไม่ auto → return true | ล้มเหลว → return false
function M.ApplySpellReticule(inst, aoetargeting, scale, anim, opts)
	if inst == nil or aoetargeting == nil or scale == nil or anim == nil then
		return false
	end

	opts = opts or {}
	local anim_id = NormalizeAnim(anim)
	local prefabs = C.PREFAB[anim_id]
	if prefabs == nil then
		return false
	end

	local work_radius = M.GetWorkRadius(scale, anim_id)

	inst._skilltree_reticule_scale = scale
	inst._skilltree_reticule_anim = anim_id
	inst._skilltree_reticule_work_radius = work_radius

	if opts.cast_range ~= nil then
		aoetargeting:SetRange(opts.cast_range)
		if aoetargeting.reticule ~= nil then
			aoetargeting.reticule.twinstickrange = opts.cast_range
		end
	end

	local reticule = aoetargeting.reticule
	reticule.scale = scale
	reticule.reticuleprefab = prefabs.reticule
	reticule.pingprefab = prefabs.ping
	reticule.updatepositionfn = ReticuleUpdatePositionFn

	local mousetargetfn = opts.mousetargetfn
	if mousetargetfn == nil and opts.cast_range ~= nil and M.IsReticuleRangeLockEnabled() then
		mousetargetfn = M.MakeCastRangeMouseTargetFn(opts.cast_range, opts.origin_fn)
	end
	ApplyReticuleTargetingHooks(inst, aoetargeting, mousetargetfn, opts.validfn)

	SyncActiveReticuleComponent(inst, aoetargeting, reticule, prefabs, opts)
	TryRefreshPlayerReticule(inst)

	if opts.auto_work_radius then
		if work_radius == nil then
			return false
		end
		aoetargeting:SetDeployRadius(work_radius)
		return work_radius
	end

	return true
end

function M.SpawnGroundReticule(scale, anim, x, z, opts)
	opts = opts or {}

	local anim_id = NormalizeAnim(anim)
	if C.ANIM[anim_id] == nil or scale == nil then
		return nil
	end

	local inst = CreateEntity()
	inst.entity:AddTransform()
	inst.entity:AddAnimState()

	inst:AddTag("FX")
	inst:AddTag("NOCLICK")
	inst:AddTag(C.DEBUG_TAG)
	inst.entity:SetCanSleep(false)
	inst.persists = false

	if not M.ConfigureGroundReticuleVisual(inst, scale, anim_id, opts) then
		inst:Remove()
		return nil
	end

	inst.Transform:SetPosition(x, 0, z)

	return inst
end

M.ANIM_SMALL = C.ANIM_SMALL
M.ANIM_LARGE = C.ANIM_LARGE
M.RANGE_PER_SCALE = C.RANGE_PER_SCALE

function M.ResolveReticuleValidFn(inst)
	if inst == nil then
		return nil
	end

	local reticule = inst.components ~= nil and inst.components.reticule or nil
	if reticule ~= nil and reticule.validfn ~= nil then
		return reticule.validfn
	end

	local aoetargeting = inst.components ~= nil and inst.components.aoetargeting or nil
	if aoetargeting ~= nil and aoetargeting.reticule ~= nil then
		return aoetargeting.reticule.validfn
	end

	return nil
end

function M.CanCastAOEAtPoint(inst, pos, map)
	if inst == nil or pos == nil then
		return false
	end

	map = map or (TheWorld ~= nil and TheWorld.Map or nil)
	if map == nil then
		return false
	end

	local alwayspassable, allowwater, deployradius
	local aoetargeting = inst.components ~= nil and inst.components.aoetargeting or nil
	if aoetargeting ~= nil then
		alwayspassable = aoetargeting.alwaysvalid
		allowwater = aoetargeting.allowwater
		deployradius = aoetargeting.deployradius
	end

	alwayspassable = alwayspassable or inst:HasTag("allow_action_on_impassable")

	local reticule = inst.components ~= nil and inst.components.reticule or nil
	if reticule ~= nil and reticule.ispassableatallpoints then
		alwayspassable = true
	end

	if aoetargeting ~= nil and aoetargeting.GetRange ~= nil and M.IsReticuleRangeLockEnabled() then
		local range = aoetargeting:GetRange()
		if range ~= nil and range > 0 then
			local player = rawget(_G, "ThePlayer")
			if player ~= nil and player:IsValid() and player.Transform ~= nil then
				local x, pos_y, z = player.Transform:GetWorldPosition()
				local px, pz = pos.x, pos.z
				if pos.Get ~= nil then
					local get_x, get_y, get_z = pos:Get()
					px, pz = get_x, get_z
				end
				if px ~= nil and pz ~= nil then
					local dx, dz = px - x, pz - z
					if dx * dx + dz * dz > range * range + .001 then
						return false
					end
				end
			end
		end
	end

	if not map:CanCastAtPoint(pos, alwayspassable, allowwater, deployradius) then
		return false
	end

	local validfn = M.ResolveReticuleValidFn(inst)
	if validfn ~= nil then
		return validfn(inst, reticule ~= nil and reticule.reticule or nil, pos, alwayspassable, allowwater, deployradius) == true
	end

	return true
end

return M
