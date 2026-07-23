local ReticuleUtils = require("reticule/utils")
local umbral_rift_V = require("skill_effect/waxwell/umbra/umbral_rift/variables")

local umbral_rift_common
local journal_cast_gate
local shadow_lanternbearer_common

local function GetUmbralRiftCommon()
	if umbral_rift_common == nil then
		umbral_rift_common = require("skill_effect/waxwell/umbra/umbral_rift/common")
	end
	return umbral_rift_common
end

local function GetJournalCastGate()
	if journal_cast_gate == nil then
		journal_cast_gate = require("skill_effect/waxwell/_shared/journal_cast_gate")
	end
	return journal_cast_gate
end

local function GetShadowLanternbearerCommon()
	if shadow_lanternbearer_common == nil then
		shadow_lanternbearer_common = require("skill_effect/waxwell/puppeteer/shadow_lanternbearer/common")
	end
	return shadow_lanternbearer_common
end

local function IsWaxwellJournalReticuleActive(pc)
	return pc:IsAOETargeting()
		and pc.reticule ~= nil
		and pc.reticule.inst ~= nil
		and pc.reticule.inst.prefab == "waxwelljournal"
end

local function SendUmbralRiftModRPC(rpc, name, ...)
	local mod_rpc = rawget(_G, "MOD_RPC")
	local id = mod_rpc ~= nil
		and mod_rpc[rpc.NAMESPACE] ~= nil
		and mod_rpc[rpc.NAMESPACE][name]
		or nil
	if id ~= nil then
		SendModRPCToServer(id, ...)
	end
end

local function PlayCodexCastBlockedFeedback(pc, book, doer)
	GetJournalCastGate().PlayClientCastBlockedFeedback(pc, book, doer)
end

local function PlayLanternbearerCastBlockedFeedback(pc, doer, failreason)
	GetShadowLanternbearerCommon().PlayLanternbearerCastBlockedFeedback(pc, doer, failreason)
end

local function GetLanternbearerCastBlockReason(book, doer, pos)
	return GetShadowLanternbearerCommon().GetLanternbearerCastBlockReason(book, doer, pos)
end

local function IsUmbralRiftBook(book)
	return GetUmbralRiftCommon().IsUmbralRiftBook(book)
end

local function IsUmbralRiftReticuleActive(pc)
	return IsWaxwellJournalReticuleActive(pc)
		and IsUmbralRiftBook(pc.reticule.inst)
end

local function HasUmbralRiftMark(player)
	return GetUmbralRiftCommon().HasUmbralRiftMark(player)
end

local function CanCastUmbralRiftWarp(book, doer)
	return GetUmbralRiftCommon().CanCastUmbralRiftWarp(book, doer)
end

local function GetCastAOEItem(rmb)
	if rmb == nil then
		return nil
	end

	return rmb.invobject or rmb.target
end

local function IsValidCastAOEAction(rmb)
	if rmb == nil or rmb.action ~= ACTIONS.CASTAOE then
		return rmb ~= nil
	end

	local item = GetCastAOEItem(rmb)
	local pos = rmb:GetActionPoint()
	if item == nil or pos == nil then
		return false
	end

	return ReticuleUtils.CanCastAOEAtPoint(item, pos)
end

local function FilterInvalidAOECastActions(inst, pos, actions)
	if inst == nil or pos == nil or actions == nil then
		return
	end

	for i = #actions, 1, -1 do
		if actions[i] == ACTIONS.CASTAOE and not ReticuleUtils.CanCastAOEAtPoint(inst, pos) then
			table.remove(actions, i)
		end
	end
end

local function PatchAOESpellPointAction()
	if rawget(_G, "_skilltree_aoespell_point_patched") then
		return true
	end

	local component_actions = rawget(_G, "COMPONENT_ACTIONS")
	if component_actions == nil
		or component_actions.POINT == nil
		or component_actions.POINT.aoespell == nil then
		return false
	end

	rawset(_G, "_skilltree_aoespell_point_patched", true)

	local old_aoespell_point_action = component_actions.POINT.aoespell
	component_actions.POINT.aoespell = function(inst, doer, pos, actions, right, target)
		local count = actions ~= nil and #actions or 0
		old_aoespell_point_action(inst, doer, pos, actions, right, target)
		if right and actions ~= nil and #actions > count then
			FilterInvalidAOECastActions(inst, pos, actions)
		end
	end

	return true
end

-- =============================================================================
-- Umbral Rift — two-point cast (client input glue)
-- =============================================================================

-- ส่ง "วาง mark จุด 1" ไป server (หรือเรียกตรงเมื่อ ismastersim)
local function RequestPlaceUmbralRiftMark(player, book, pt)
	local common = GetUmbralRiftCommon()
	if TheWorld.ismastersim then
		local ok = common.PlaceUmbralRiftMark(player, Vector3(pt.x, 0, pt.z), book)
		if not ok then
			TheFocalPoint.SoundEmitter:PlaySound("dontstarve/HUD/click_negative", nil, .4)
		end
	else
		local rpc = common.UMBRAL_RIFT_RPC
		SendUmbralRiftModRPC(rpc, rpc.PLACE_MARK, pt.x, pt.z)
	end
end

-- ยกเลิกทั้งสกิล (ลบ mark ฝั่ง server + ปิด reticule ฝั่ง client)
local function StopUmbralRiftWalkToPlace(player)
	if player == nil then
		return
	end

	if player._waxwell_umbral_rift_walk_task ~= nil then
		player._waxwell_umbral_rift_walk_task:Cancel()
		player._waxwell_umbral_rift_walk_task = nil
	end

	local locomotor = player.components ~= nil and player.components.locomotor or nil
	if locomotor ~= nil then
		if locomotor.atdestfn == player._waxwell_umbral_rift_atdestfn then
			locomotor.atdestfn = nil
		end
		if player._waxwell_umbral_rift_walk_active then
			locomotor:Stop()
			locomotor:Clear()
		end
	end

	local pc = player.components ~= nil and player.components.playercontroller or nil
	if pc ~= nil then
		pc.directwalking = false
		pc.dragwalking = false
	end

	player._waxwell_umbral_rift_atdestfn = nil
	player._waxwell_umbral_rift_walk_active = nil
	player._waxwell_umbral_rift_walk_target = nil
end

local function StartUmbralRiftWalkToPlace(pc, player, book, pt)
	StopUmbralRiftWalkToPlace(player)

	local locomotor = player.components ~= nil and player.components.locomotor or nil
	if locomotor == nil then
		return
	end

	local dest = Vector3(pt.x, 0, pt.z)
	local cast_range = umbral_rift_V.UMBRAL_RIFT_CAST_RANGE
	local aoetargeting = book ~= nil and book.components ~= nil and book.components.aoetargeting or nil
	if aoetargeting ~= nil and aoetargeting.GetRange ~= nil then
		local range = aoetargeting:GetRange()
		if range ~= nil and range > 0 then
			cast_range = range
		end
	end

	player._waxwell_umbral_rift_walk_active = true
	player._waxwell_umbral_rift_walk_target = { x = pt.x, z = pt.z }

	player._waxwell_umbral_rift_atdestfn = function()
		if not player:IsValid() or not player._waxwell_umbral_rift_walk_active then
			return
		end

		StopUmbralRiftWalkToPlace(player)

		if not IsUmbralRiftReticuleActive(pc) then
			return
		end

		if pc.reticule ~= nil and pc.reticule.PingReticuleAt ~= nil then
			pc.reticule:PingReticuleAt(dest)
		end
		RequestPlaceUmbralRiftMark(player, book, dest)
	end

	locomotor.atdestfn = player._waxwell_umbral_rift_atdestfn
	locomotor:GoToPoint(dest, nil, false)
	locomotor.arrive_dist = cast_range
end

local function RequestCancelUmbralRift(pc)
	StopUmbralRiftWalkToPlace(pc.inst)
	GetUmbralRiftCommon().CancelUmbralRiftSkill(pc.inst)
end

-- คืน true = จัดการเองแล้ว (บล็อก flow vanilla) / false = ปล่อยให้ vanilla ทำต่อ (จุด 2 warp)
local function HandleUmbralRiftConfirm(pc, book)
	if not IsUmbralRiftBook(book) then
		return false
	end

	local player = pc.inst

	if HasUmbralRiftMark(player) then
		-- จุด 2 (warp): ตรวจ cost ก่อน แล้วปล่อยให้ vanilla เล่น anim + cast
		if not CanCastUmbralRiftWarp(book, player) then
			PlayCodexCastBlockedFeedback(pc, book, player)
			return true -- บล็อก: ไม่เล่น anim, mark + reticule ยังอยู่
		end

		local common = GetUmbralRiftCommon()
		if TheWorld.ismastersim then
			common.ReserveUmbralRiftWarpCast(player)
		else
			local rpc = common.UMBRAL_RIFT_RPC
			SendUmbralRiftModRPC(rpc, rpc.BEGIN_WARP)
		end

		return false -- ปล่อย vanilla → CASTAOE → book anim → warp
	end

	-- จุด 1 (mark): ไม่เล่น anim, ไม่ผ่าน CASTAOE, reticule คงเปิด (กลายเป็น reticule2)
	local act = pc:GetRightMouseAction()
	if act == nil or act.action ~= ACTIONS.CASTAOE then
		return true -- จุดไม่ valid → ไม่ทำอะไร
	end

	local pt = act:GetActionPoint()
	if pt == nil and act.GetDynamicActionPoint ~= nil then
		pt = act:GetDynamicActionPoint()
	end
	if pt == nil then
		return true
	end

	if not CanCastUmbralRiftWarp(book, player) then
		PlayCodexCastBlockedFeedback(pc, book, player)
		return true
	end

	if not ReticuleUtils.IsReticuleRangeLockEnabled()
		and not GetUmbralRiftCommon().IsUmbralRiftWithinCastRange(player, pt) then
		StartUmbralRiftWalkToPlace(pc, player, book, pt)
		return true
	end

	if pc.reticule ~= nil and pc.reticule.PingReticuleAt ~= nil then
		pc.reticule:PingReticuleAt(pt)
	end
	RequestPlaceUmbralRiftMark(player, book, pt)
	return true
end

-- =============================================================================
-- Component post inits
-- =============================================================================

AddComponentPostInit("reticule", function(Reticule)
	local old_CreateReticule = Reticule.CreateReticule

	function Reticule:CreateReticule(...)
		if self.inst ~= nil and self.inst.prefab == "waxwelljournal" then
			local aoetargeting = self.inst.components ~= nil and self.inst.components.aoetargeting or nil
			ReticuleUtils.PrepareVanillaJournalSpellReticule(self.inst, aoetargeting, self)
			ReticuleUtils.EnsureJournalReticuleRangeLock(self.inst, aoetargeting, self)

			if self.reticule ~= nil
				and self.reticuleprefab ~= nil
				and self.reticule.prefab ~= self.reticuleprefab
				and self.DestroyReticule ~= nil then
				self:DestroyReticule()
			end
		end

		old_CreateReticule(self, ...)

		if self.reticule ~= nil then
			ReticuleUtils.ApplyReticuleScale(self.inst, self.reticule)
		end

		if self.targetpos == nil then
			local theinput = rawget(_G, "TheInput")
			if self.mouseenabled and theinput ~= nil and theinput.GetWorldPosition ~= nil then
				self.targetpos = theinput:GetWorldPosition()
			elseif self.targetfn ~= nil then
				self.targetpos = self.targetfn(self.inst)
			end
		end
	end
end)

AddComponentPostInit("aoespell", function(self)
	local old_CanCast = self.CanCast

	function self:CanCast(doer, pos)
		if not old_CanCast(self, doer, pos) then
			return false
		end

		return ReticuleUtils.CanCastAOEAtPoint(self.inst, pos)
	end
end)

AddComponentPostInit("playeractionpicker", function(self)
	if self._skilltree_aoecast_filter_patched then
		return
	end

	self._skilltree_aoecast_filter_patched = true

	local old_DoGetMouseActions = self.DoGetMouseActions
	function self:DoGetMouseActions(position, target, spellbook)
		local lmb, rmb = old_DoGetMouseActions(self, position, target, spellbook)
		if not IsValidCastAOEAction(rmb) then
			rmb = nil
		end
		return lmb, rmb
	end
end)

if not PatchAOESpellPointAction() then
	AddSimPostInit(function()
		PatchAOESpellPointAction()
	end)
end

AddComponentPostInit("playercontroller", function(self)
	if self._waxwell_umbral_rift_cancel_patched then
		return
	end

	self._waxwell_umbral_rift_cancel_patched = true

	local function IsUmbralRiftReticuleActiveLocal(pc)
		return IsUmbralRiftReticuleActive(pc)
	end

	-- คลิกซ้าย: จุด 1 วาง mark (ไม่ anim) / จุด 2 ปล่อย vanilla warp
	local old_OnLeftClick = self.OnLeftClick
	function self:OnLeftClick(down, ...)
		if down
			and self:UsingMouse()
			and self:IsEnabled()
			and not self:IsBusy()
			and IsUmbralRiftReticuleActiveLocal(self) then
			if HandleUmbralRiftConfirm(self, self.reticule.inst) then
				return
			end
		elseif down
			and self:UsingMouse()
			and self:IsEnabled()
			and IsWaxwellJournalReticuleActive(self) then
			local book = self.reticule.inst
			if not self:IsBusy() then
				if not GetJournalCastGate().CanAffordCurrentCodexCast(book, self.inst) then
					PlayCodexCastBlockedFeedback(self, book, self.inst)
					return
				end
			end

			local pos = self.reticule ~= nil and self.reticule.targetpos or nil
			local lanternfail = pos ~= nil and GetLanternbearerCastBlockReason(book, self.inst, pos) or nil
			if lanternfail ~= nil then
				PlayLanternbearerCastBlockedFeedback(self, self.inst, lanternfail)
				return
			end
		end

		return old_OnLeftClick(self, down, ...)
	end

	-- คลิกขวา: ยกเลิกทั้งสกิล (ลบ mark + ปิด reticule)
	local old_OnRightClick = self.OnRightClick
	function self:OnRightClick(down, ...)
		if down and IsUmbralRiftReticuleActiveLocal(self) then
			RequestCancelUmbralRift(self)
			return
		end

		return old_OnRightClick(self, down, ...)
	end

	-- controller: ปุ่ม alt action = ยกเลิก
	local old_DoControllerAltActionButton = self.DoControllerAltActionButton
	function self:DoControllerAltActionButton(...)
		if IsUmbralRiftReticuleActiveLocal(self) then
			RequestCancelUmbralRift(self)
			return
		end

		return old_DoControllerAltActionButton(self, ...)
	end

	-- ปิด reticule ด้วยวิธีอื่น (ร่ายเสร็จ, ปิด spellbook) — เคลียร์ UR state ที่ค้างบน journal
	local old_CancelAOETargeting = self.CancelAOETargeting
	function self:CancelAOETargeting(...)
		local book = self.reticule ~= nil and self.reticule.inst or nil
		local was_ur = book ~= nil and book._waxwell_umbral_rift_active == true
		local ret = old_CancelAOETargeting(self, ...)
		if was_ur and self.inst == ThePlayer then
			StopUmbralRiftWalkToPlace(self.inst)
			local ur_common = GetUmbralRiftCommon()
			-- จุด 2: reticule ปิดก่อน warp เสร็จ — เก็บ mark + journal (range 20) ไว้จน spell fn จบ
			local keep_mark = ur_common.HasUmbralRiftMark(self.inst)
			ur_common.CleanupUmbralRiftSkill(self.inst, {
				skip_reticule_close = true,
				book = book,
				keep_mark = keep_mark,
				keep_journal_state = keep_mark,
			})
		end
		return ret
	end
end)
