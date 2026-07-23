local C = require("reticule/constants")
local ReticuleUtils = require("reticule/utils")
local emperor_variables = require("skill_effect/waxwell/emperor/_shared/variables")

local assets =
{
	Asset("ANIM", "anim/reticuleaoe.zip"),
}

local RETICULE_SCALE = emperor_variables.DOMAIN_EXPANSION_RETICULE_SCALE

local function fn()
	local inst = CreateEntity()

	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddNetwork()

	inst:AddTag("FX")
	inst:AddTag("NOCLICK")
	inst.entity:SetCanSleep(false)
	inst.persists = false

	ReticuleUtils.ConfigureGroundReticuleVisual(inst, RETICULE_SCALE, C.ANIM_LARGE, {
		loop = true,
		sort_order = 2,
		multcolour = { 1, .78, .22, .72 },
		addcolour = { .08, .03, 0, 0 },
		bloom = true,
	})

	inst.entity:SetPristine()

	return inst
end

return Prefab("domain_expansion_reticule", fn, assets)
