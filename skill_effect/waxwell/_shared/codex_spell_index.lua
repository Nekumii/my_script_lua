local M = {}

local SpellIcon = require("skill_effect/waxwell/_shared/codex_spell_icon")
local ReticuleUtils = require("reticule/utils")

local SpellWheelRefresh

local function GetSpellWheelRefresh()
	if SpellWheelRefresh == nil then
		SpellWheelRefresh = require("wheel/refresh")
	end
	return SpellWheelRefresh
end

local SPELLBOOK_REFRESH_PERIOD = .5
local BUILDER_ORDER = { "puppeteer", "umbra", "emperor" }
local GetSpellItemKey
local GetSpellItemValue
local GetSpellItemBool
local GetSpellItemNumber

local function BuildSpellBlockSnapshot(item, owner)
	if item == nil then
		return {
			blocked = true,
			disabled = true,
			pct = nil,
			overlayonly = false,
			state = SpellIcon.STATE.DISABLED,
		}
	end

	local snapshot = SpellIcon.GetSnapshot(item, owner)
	return {
		blocked = SpellIcon.IsInteractionBlocked(snapshot),
		disabled = snapshot.state == SpellIcon.STATE.DISABLED,
		pct = snapshot.overlay_pct,
		overlayonly = snapshot.overlayonly == true,
		state = snapshot.state,
	}
end

local function ResolveOwner(inst, user)
    local owner = user
    if owner == nil and inst ~= nil and inst.components ~= nil and inst.components.inventoryitem ~= nil then
        owner = inst.components.inventoryitem:GetGrandOwner()
    end
    return owner or ThePlayer
end

local function OwnersMatch(a, b)
    return a == b or (a ~= nil and b ~= nil and a.userid ~= nil and a.userid == b.userid)
end

GetSpellItemKey = function(item)
    return item ~= nil and (item.spell_id or item.label) or nil
end

local IsSpellItemBlocked

local function WrapSpellItem(item)
    if item == nil or item._waxwell_spell_wrapped then
        return item
    end

    local wrapped = {}
    for key, value in pairs(item) do
        wrapped[key] = value
    end

    wrapped._waxwell_base_noselect = item._waxwell_base_noselect == true or item.noselect == true
    wrapped.noselect = wrapped._waxwell_base_noselect == true
    wrapped._waxwell_spell_wrapped = true
    return wrapped
end

GetSpellItemValue = function(value, owner, fallback)
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

GetSpellItemBool = function(value, owner, fallback)
    return GetSpellItemValue(value, owner, fallback == true) == true
end

GetSpellItemNumber = function(value, owner, fallback)
    local number = GetSpellItemValue(value, owner, fallback)
    return type(number) == "number" and number or fallback
end

IsSpellItemBlocked = function(item, owner)
    return BuildSpellBlockSnapshot(item, owner).blocked
end

local function SelectFirstAvailableSpell(spellbook, owner, preferredid)
    if spellbook == nil or spellbook.items == nil or spellbook._waxwell_old_select_spell == nil then
        return false
    end

    if preferredid ~= nil then
        local preferreditem = spellbook.items[preferredid]
        if preferreditem ~= nil and not IsSpellItemBlocked(preferreditem, owner) then
            spellbook._waxwell_old_select_spell(spellbook, preferredid)
            return true
        end
    end

    for id, item in ipairs(spellbook.items) do
        if not IsSpellItemBlocked(item, owner) then
            spellbook._waxwell_old_select_spell(spellbook, id)
            return true
        end
    end

    return false
end

local function EnsureSelectableCurrentSpell(spellbook, owner)
    if spellbook == nil or spellbook.items == nil then
        return false
    end

    local currentid = spellbook.spell_id
    if currentid ~= nil and spellbook.items[currentid] ~= nil and not IsSpellItemBlocked(spellbook.items[currentid], owner) then
        return true
    end

    return SelectFirstAvailableSpell(spellbook, owner, nil)
end

local function GetSpellListSignature(items)
    local parts = {}
    for _, item in ipairs(items or {}) do
        table.insert(parts, tostring(GetSpellItemKey(item) or "nil"))
    end
    return table.concat(parts, "|")
end

local function BuildRefreshState(spellbook, owner)
    local parts = {}
    local providers = spellbook._waxwell_spell_refresh_state_providers or nil
    if providers ~= nil then
        for _, key in ipairs(spellbook._waxwell_spell_refresh_state_order or {}) do
            local provider = providers[key]
            if provider ~= nil then
                table.insert(parts, tostring(provider(owner) or "nil"))
            end
        end
    end
    return table.concat(parts, "|")
end

local function BuildSpellItems(spellbook, owner)
    local items = spellbook._waxwell_base_items or spellbook.items
    local builders = spellbook._waxwell_spell_builders or nil

    if builders ~= nil then
        for _, key in ipairs(spellbook._waxwell_spell_builder_order or {}) do
            local builder = builders[key]
            if builder ~= nil then
                items = builder(items, owner)
            end
        end
    end

    local wrappeditems = {}
    for index, item in ipairs(items or {}) do
        wrappeditems[index] = WrapSpellItem(item)
    end

    return wrappeditems
end

local function DetachOwnerRefreshListener(spellbook)
    if spellbook._waxwell_refresh_owner ~= nil and spellbook._waxwell_refresh_owner_listener ~= nil then
        spellbook._waxwell_refresh_owner:RemoveEventCallback("waxwell_emperor_spell_refresh", spellbook._waxwell_refresh_owner_listener)
        spellbook._waxwell_refresh_owner = nil
        spellbook._waxwell_refresh_owner_listener = nil
    end
end

local function AttachOwnerRefreshListener(inst, spellbook, owner)
    if owner == nil or spellbook._waxwell_refresh_owner == owner then
        return
    end

    DetachOwnerRefreshListener(spellbook)

    spellbook._waxwell_refresh_owner = owner
    spellbook._waxwell_refresh_owner_listener = function()
        M.RefreshSpellbook(spellbook, owner)
    end
    owner:ListenForEvent("waxwell_emperor_spell_refresh", spellbook._waxwell_refresh_owner_listener)
end

local function EnsureJournalRegistrationTable(spellbook, field)
    if spellbook == nil or field == nil then
        return nil
    end

    spellbook[field] = spellbook[field] or {}
    return spellbook[field]
end

local function CancelScheduledWheelRefresh(spellbook)
	if spellbook == nil then
		return
	end

	if spellbook._waxwell_wheel_refresh_task ~= nil then
		spellbook._waxwell_wheel_refresh_task:Cancel()
		spellbook._waxwell_wheel_refresh_task = nil
	end

	spellbook._waxwell_pending_wheel_itemschanged = nil
end

local function ScheduleOpenWheelRefresh(spellbook, owner, itemschanged)
	local inst = spellbook ~= nil and spellbook.inst or nil
	if inst == nil then
		return false
	end

	local resolved_owner = ResolveOwner(inst, owner)
	local hud = resolved_owner ~= nil and resolved_owner.HUD or nil
	if hud == nil or hud.IsSpellWheelOpen == nil or hud.GetCurrentOpenSpellBook == nil then
		return false
	end

	if not hud:IsSpellWheelOpen() or hud:GetCurrentOpenSpellBook() ~= inst then
		return false
	end

	if itemschanged then
		if spellbook._waxwell_wheel_refresh_task ~= nil then
			spellbook._waxwell_pending_wheel_itemschanged = true
			return true
		end

		spellbook._waxwell_pending_wheel_itemschanged = true
		spellbook._waxwell_wheel_refresh_task = inst:DoTaskInTime(0, function()
			spellbook._waxwell_wheel_refresh_task = nil
			local rebuild = spellbook._waxwell_pending_wheel_itemschanged == true
			spellbook._waxwell_pending_wheel_itemschanged = nil
			GetSpellWheelRefresh().RefreshOpenWheelVisuals(ResolveOwner(inst, owner), inst, {
				rebuild_items = rebuild,
				forceinit = rebuild,
			})
		end)
		return true
	end

	GetSpellWheelRefresh().RefreshOpenWheelVisuals(resolved_owner, inst, {
		rebuild_items = false,
		forceinit = false,
	})
	return true
end

function M.RefreshSpellbook(spellbook, user)
    if spellbook == nil then
        return false
    end

    local inst = spellbook.inst
    local owner = ResolveOwner(inst, user)
    local oldrefreshstate = spellbook._waxwell_last_refresh_state
    local selected_key = nil
    if spellbook.spell_id ~= nil and spellbook.items ~= nil and spellbook.items[spellbook.spell_id] ~= nil then
        selected_key = GetSpellItemKey(spellbook.items[spellbook.spell_id])
    end

    local items = BuildSpellItems(spellbook, owner)
    local refreshstate = BuildRefreshState(spellbook, owner)
    local signature = GetSpellListSignature(items)
    local itemschanged = spellbook.items == nil or signature ~= spellbook._waxwell_spell_signature

    if itemschanged then
        spellbook:SetItems(items)
        spellbook._waxwell_spell_signature = signature
    end
    spellbook._waxwell_last_refresh_state = refreshstate
    local refreshchanged = oldrefreshstate ~= refreshstate

    if spellbook.items ~= nil then
        for _, item in ipairs(spellbook.items) do
            if item ~= nil then
                item.noselect = item._waxwell_base_noselect == true
            end
        end
    end

    if itemschanged and spellbook.items ~= nil and spellbook._waxwell_old_select_spell ~= nil then
        local restored = false
        if selected_key ~= nil then
            for id, item in ipairs(spellbook.items) do
                if GetSpellItemKey(item) == selected_key then
                    restored = SelectFirstAvailableSpell(spellbook, owner, id)
                    break
                end
            end
        end

        if not restored then
            SelectFirstAvailableSpell(spellbook, owner, spellbook.spell_id or 1)
        end
    end

    EnsureSelectableCurrentSpell(spellbook, owner)

    if refreshchanged and spellbook.items ~= nil and spellbook.spell_id ~= nil then
        local selecteditem = spellbook.items[spellbook.spell_id]
        if selecteditem ~= nil and selecteditem.onselect ~= nil then
            local snapshot = BuildSpellBlockSnapshot(selecteditem, owner)
            local was_blocked = spellbook._waxwell_selected_was_blocked == true
            spellbook._waxwell_selected_was_blocked = snapshot.blocked
            if was_blocked and not snapshot.blocked then
                selecteditem.onselect(inst)
            end
        end
    end

    ScheduleOpenWheelRefresh(spellbook, owner, itemschanged)

    return itemschanged
end

function M.EnsurePatched(inst, spellbook)
    if inst == nil or spellbook == nil then
        return
    end

    spellbook._waxwell_base_items = spellbook._waxwell_base_items or spellbook.items
    spellbook._waxwell_spell_builders = spellbook._waxwell_spell_builders or {}
    spellbook._waxwell_spell_builder_order = spellbook._waxwell_spell_builder_order or {}
    spellbook._waxwell_spell_refresh_state_providers = spellbook._waxwell_spell_refresh_state_providers or {}
    spellbook._waxwell_spell_refresh_state_order = spellbook._waxwell_spell_refresh_state_order or {}

    if spellbook._waxwell_spell_index_patched then
        return
    end

    spellbook._waxwell_spell_index_patched = true
    spellbook._waxwell_old_open_spellbook = spellbook.OpenSpellBook
    spellbook._waxwell_old_close_spellbook = spellbook.CloseSpellBook
    spellbook._waxwell_old_select_spell = spellbook.SelectSpell

    function spellbook:SelectSpell(id, user)
        local owner = ResolveOwner(inst, user)
        if TheWorld ~= nil and TheWorld.ismastersim then
            M.RefreshSpellbook(self, owner)
        end

        local item = self.items ~= nil and self.items[id] or nil
        if item ~= nil and IsSpellItemBlocked(item, owner) then
            return false
        end

        local ret = self._waxwell_old_select_spell(self, id)
        if inst.prefab == "waxwelljournal" then
            ReticuleUtils.PrepareVanillaJournalSpellReticule(inst)
            ReticuleUtils.EnsureJournalReticuleRangeLock(inst)
        end
        return ret
    end

    TheWorld:ListenForEvent("waxwell_emperor_spell_refresh", function(_, data)
        if data == nil or data.owner == nil then
            return
        end

        local owner = ResolveOwner(inst)
        if OwnersMatch(owner, data.owner) then
            M.RefreshSpellbook(spellbook, data.owner)
        end
    end)

    function spellbook:OpenSpellBook(user)
        M.RefreshSpellbook(self, user)

        local owner = ResolveOwner(inst, user)
        AttachOwnerRefreshListener(inst, self, owner)
        self._waxwell_last_refresh_state = BuildRefreshState(self, owner)

        local selecteditem = self.items ~= nil and self.spell_id ~= nil and self.items[self.spell_id] or nil
        if selecteditem ~= nil then
            self._waxwell_selected_was_blocked = BuildSpellBlockSnapshot(selecteditem, owner).blocked
        else
            self._waxwell_selected_was_blocked = nil
        end

        if self._waxwell_refresh_task ~= nil then
            self._waxwell_refresh_task:Cancel()
        end
        self._waxwell_refresh_task = inst:DoPeriodicTask(SPELLBOOK_REFRESH_PERIOD, function()
            local currentowner = ResolveOwner(inst, owner)
            local currentstate = BuildRefreshState(self, currentowner)
            if currentstate ~= self._waxwell_last_refresh_state then
                M.RefreshSpellbook(self, currentowner)
            end
        end)

        return self._waxwell_old_open_spellbook(self, user)
    end

    function spellbook:CloseSpellBook()
        CancelScheduledWheelRefresh(self)
        self._waxwell_last_refresh_state = nil

        if self._waxwell_refresh_task ~= nil then
            self._waxwell_refresh_task:Cancel()
            self._waxwell_refresh_task = nil
        end
        DetachOwnerRefreshListener(self)
        return self._waxwell_old_close_spellbook(self)
    end
end

function M.EnsureSpellLabel(spellid, label)
    if spellid == nil or label == nil then
        return label
    end

    STRINGS.SPELLS = STRINGS.SPELLS or {}
    if STRINGS.SPELLS[spellid] == nil then
        STRINGS.SPELLS[spellid] = label
    end

    return STRINGS.SPELLS[spellid]
end

function M.RegisterJournalSpellBuilder(inst, spellbook, key, builder)
    if inst == nil or spellbook == nil or key == nil or builder == nil then
        return false
    end

    local registrations = EnsureJournalRegistrationTable(spellbook, "_waxwell_registered_journal_builders")
    if registrations[key] then
        return false
    end

    registrations[key] = true
    M.RegisterBuilder(inst, spellbook, key, builder)
    return true
end

function M.RegisterBuilder(inst, spellbook, key, builder)
    if inst == nil or spellbook == nil or key == nil or builder == nil then
        return
    end

    M.EnsurePatched(inst, spellbook)
    spellbook._waxwell_spell_builders[key] = builder

    local haskey = false
    for _, existing in ipairs(spellbook._waxwell_spell_builder_order) do
        if existing == key then
            haskey = true
            break
        end
    end

    if not haskey then
        local inserted = false
        local wantedindex = nil
        for index, wantedkey in ipairs(BUILDER_ORDER) do
            if wantedkey == key then
                wantedindex = index
                break
            end
        end

        if wantedindex ~= nil then
            for index, existing in ipairs(spellbook._waxwell_spell_builder_order) do
                local existingindex = nil
                for orderindex, wantedkey in ipairs(BUILDER_ORDER) do
                    if wantedkey == existing then
                        existingindex = orderindex
                        break
                    end
                end

                if existingindex ~= nil and wantedindex < existingindex then
                    table.insert(spellbook._waxwell_spell_builder_order, index, key)
                    inserted = true
                    break
                end
            end
        end

        if not inserted then
            table.insert(spellbook._waxwell_spell_builder_order, key)
        end
    end
end

function M.RegisterRefreshStateProvider(inst, spellbook, key, provider)
    if inst == nil or spellbook == nil or key == nil or provider == nil then
        return
    end

    M.EnsurePatched(inst, spellbook)
    spellbook._waxwell_spell_refresh_state_providers[key] = provider

    for _, existing in ipairs(spellbook._waxwell_spell_refresh_state_order) do
        if existing == key then
            return
        end
    end

    table.insert(spellbook._waxwell_spell_refresh_state_order, key)
end

function M.RegisterJournalRefreshStateProvider(inst, spellbook, key, provider)
    if inst == nil or spellbook == nil or key == nil or provider == nil then
        return false
    end

    local registrations = EnsureJournalRegistrationTable(spellbook, "_waxwell_registered_journal_refresh_state_providers")
    if registrations[key] then
        return false
    end

    registrations[key] = true
    M.RegisterRefreshStateProvider(inst, spellbook, key, provider)
    return true
end

return M