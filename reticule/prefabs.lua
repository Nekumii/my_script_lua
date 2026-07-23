local C = require("reticule/constants")

local assets =
{
	Asset("ANIM", "anim/reticuleaoe.zip"),
}

local function UpdatePing(inst, s0, s1, t0, duration, multcolour, addcolour)
	if next(multcolour) == nil then
		multcolour[1], multcolour[2], multcolour[3], multcolour[4] = inst.AnimState:GetMultColour()
	end
	if next(addcolour) == nil then
		addcolour[1], addcolour[2], addcolour[3], addcolour[4] = inst.AnimState:GetAddColour()
	end

	local t = GetTime() - t0
	local k = 1 - math.max(0, t - C.PING_PAD_DURATION) / duration
	k = 1 - k * k

	local s = Lerp(s0, s1, k)
	local c = Lerp(1, 0, k)
	inst.Transform:SetScale(s, s, s)
	inst.AnimState:SetMultColour(multcolour[1], multcolour[2], multcolour[3], c * multcolour[4])

	k = math.min(C.PING_FLASH_TIME, t) / C.PING_FLASH_TIME
	c = math.max(0, 1 - k * k)
	inst.AnimState:SetAddColour(c * addcolour[1], c * addcolour[2], c * addcolour[3], c * addcolour[4])
end

local function MakeReticule(name, anim)
	local function fn()
		local inst = CreateEntity()

		inst:AddTag("FX")
		inst:AddTag("NOCLICK")
		inst.entity:SetCanSleep(false)
		inst.persists = false

		inst.entity:AddTransform()
		inst.entity:AddAnimState()

		inst.AnimState:SetBank("reticuleaoe")
		inst.AnimState:SetBuild("reticuleaoe")
		inst.AnimState:PlayAnimation(anim)
		inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGroundFixed)
		inst.AnimState:SetLayer(LAYER_WORLD_BACKGROUND)
		inst.AnimState:SetSortOrder(3)
		inst.AnimState:SetScale(1, 1)

		return inst
	end

	return Prefab(name, fn, assets)
end

local function MakePing(name, anim, scaleup)
	local function fn()
		local inst = CreateEntity()

		inst:AddTag("FX")
		inst:AddTag("NOCLICK")
		inst.entity:SetCanSleep(false)
		inst.persists = false

		inst.entity:AddTransform()
		inst.entity:AddAnimState()

		inst.AnimState:SetBank("reticuleaoe")
		inst.AnimState:SetBuild("reticuleaoe")
		inst.AnimState:PlayAnimation(anim)
		inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGroundFixed)
		inst.AnimState:SetLayer(LAYER_WORLD_BACKGROUND)
		inst.AnimState:SetSortOrder(3)
		inst.AnimState:SetScale(1, 1)
		inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")

		inst:DoPeriodicTask(0, UpdatePing, nil, 1, scaleup, GetTime(), C.PING_DURATION, {}, {})
		inst:DoTaskInTime(C.PING_DURATION, inst.Remove)

		return inst
	end

	return Prefab(name, fn, assets)
end

return {
	MakeReticule(C.PREFAB[C.ANIM_SMALL].reticule, C.ANIM[C.ANIM_SMALL]),
	MakePing(C.PREFAB[C.ANIM_SMALL].ping, C.ANIM[C.ANIM_SMALL], C.PING_SCALE_UP[C.ANIM_SMALL]),
	MakeReticule(C.PREFAB[C.ANIM_LARGE].reticule, C.ANIM[C.ANIM_LARGE]),
	MakePing(C.PREFAB[C.ANIM_LARGE].ping, C.ANIM[C.ANIM_LARGE], C.PING_SCALE_UP[C.ANIM_LARGE]),
}
