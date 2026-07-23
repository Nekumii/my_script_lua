local V = require("skill_effect/waxwell/emperor/domain_expansion/variables")
local spell_utils = require("skill_effect/waxwell/_shared/codex_spell_utils")
local debug = require("debug/init")
local SpellIcon = require("skill_effect/waxwell/_shared/codex_spell_icon")

local CastSpellBookFromInventory = spell_utils.CastSpellBookFromInventory
local TriggerInstantSpellbookCast = CastSpellBookFromInventory

local function PushSpellRefresh(owner)
    if owner ~= nil and TheWorld ~= nil then
        TheWorld:PushEvent("waxwell_emperor_spell_refresh", { owner = owner })
    end
end

local function ResolveSpellOwner(inst, doer, fallback)
    local owner = doer
    if (owner == nil or owner.components == nil) and inst ~= nil and inst.components ~= nil and inst.components.inventoryitem ~= nil then
        owner = inst.components.inventoryitem:GetGrandOwner()
    end
    return owner or fallback or ThePlayer
end

local function IsDomainExpansionSkillActive(inst)
    return inst ~= nil
        and (
            (inst.components ~= nil
                and inst.components.skilltreeupdater ~= nil
                and inst.components.skilltreeupdater:IsActivated("waxwell_domain_expansion"))
            or inst:HasTag("domain_expansion_active")
        )
end

local function ClearDomainExpansionStateCache(owner)
    if owner ~= nil then
        owner._waxwell_domain_expansion_field_cache = nil
        owner._waxwell_domain_expansion_state_cache = nil
    end
end

local function GetDomainField(owner)
    if owner == nil then
        return nil
    end

    local field = owner._waxwell_domain_expansion_field
    if field ~= nil and field:IsValid() then
        return field
    end

    local now = GetTime ~= nil and GetTime() or 0
    local cache = owner._waxwell_domain_expansion_field_cache
    if cache ~= nil and cache.time == now then
        local cachedfield = cache.field
        if cachedfield ~= nil and cachedfield:IsValid() then
            return cachedfield
        end
        return nil
    end

    if owner.userid ~= nil then
        for _, ent in pairs(Ents) do
            if ent ~= nil and ent:IsValid() and ent.prefab == "domainexpansion_field" and not ent._ending and ent._owner_userid == owner.userid then
                if ent.RebindOwner ~= nil then
                    ent:RebindOwner(owner)
                else
                    owner._waxwell_domain_expansion_field = ent
                end
                owner._waxwell_domain_expansion_field_cache = { time = now, field = ent }
                return ent
            end
        end
    end

    owner._waxwell_domain_expansion_field_cache = { time = now, field = nil }

    return nil
end

local function GetDomainExpansionSpellState(owner)
    if owner == nil then
        return nil
    end

    local now = GetTime ~= nil and GetTime() or 0
    local cache = owner._waxwell_domain_expansion_state_cache
    if cache ~= nil and cache.time == now then
        return cache.state, cache.field
    end

    local field = GetDomainField(owner)
    local state = owner._waxwell_domain_expansion_pending_state
    if field ~= nil then
        if field._ending then
            state = "deactivating"
        else
            state = "active"
        end
    end

    owner._waxwell_domain_expansion_state_cache = {
        time = now,
        state = state,
        field = field,
    }

    return state, field
end

local function IsDomainExpansionSummonLockActive(owner)
    return GetDomainExpansionSpellState(owner) ~= nil
end

local function ClearPendingDomainState(owner)
    if owner ~= nil then
        owner._waxwell_domain_expansion_pending_state = nil
        owner._waxwell_domain_expansion_pending_position = nil
        ClearDomainExpansionStateCache(owner)
    end
end

local function GetDomainExpansionCooldownTimeRemaining(owner)
    return spell_utils.GetSpellCooldownTimeRemaining(owner, V.DOMAIN_EXPANSION_COOLDOWN_ID)
end

local function HasDomainExpansionSanityToCast(owner)
    if owner == nil then
        return false
    end

    local min_sanity = V.DOMAIN_EXPANSION_SANITY_CAST_MIN or 50
    local cost_gate = require("skill_effect/waxwell/_shared/codex_cost_gate")
    local current = cost_gate.GetSanityCurrent(owner)
    return current > min_sanity
end

local function GetDomainExpansionPersistData(owner)
    if owner == nil then
        return nil
    end

    local data = {}
    local field = GetDomainField(owner)
    if field ~= nil and not field._ending and field._active then
        local fielddata = field.GetPersistData ~= nil and field:GetPersistData() or nil
        if fielddata ~= nil and fielddata.pos ~= nil then
            data.active = true
            data.pos = fielddata.pos
            data.radius = fielddata.radius or V.DOMAIN_EXPANSION_RADIUS
        end
    end

    if owner._waxwell_domain_expansion_pending_state ~= nil then
        data.pending_state = owner._waxwell_domain_expansion_pending_state
        if owner._waxwell_domain_expansion_pending_position ~= nil then
            data.pending_pos = {
                x = owner._waxwell_domain_expansion_pending_position.x,
                z = owner._waxwell_domain_expansion_pending_position.z,
            }
        end
    end

    local cooldown_time = GetDomainExpansionCooldownTimeRemaining(owner)
    if cooldown_time ~= nil and cooldown_time > 0 then
        data.cooldown_time = cooldown_time
    end

    return next(data) ~= nil and data or nil
end

local function RestoreDomainExpansionPersistData(owner, data)
    if owner == nil or data == nil then
        return
    end

    ClearDomainExpansionStateCache(owner)

    owner:DoTaskInTime(0, function(player)
        local existing = GetDomainField(player)
        if existing ~= nil and not existing._ending then
            if existing.RebindOwner ~= nil then
                existing:RebindOwner(player)
            end
            spell_utils.StopSpellCooldown(player, V.DOMAIN_EXPANSION_COOLDOWN_ID)
            ClearPendingDomainState(player)
            PushSpellRefresh(player)
            return
        end

        if data.active and data.pos ~= nil then
            local field = SpawnPrefab("domainexpansion_field")
            if field ~= nil then
                spell_utils.StopSpellCooldown(player, V.DOMAIN_EXPANSION_COOLDOWN_ID)
                ClearPendingDomainState(player)
                field:Activate(player, Vector3(data.pos.x, 0, data.pos.z), data.radius or V.DOMAIN_EXPANSION_RADIUS, data)
                PushSpellRefresh(player)
                return
            end
        end

        if data.pending_state ~= nil then
            player._waxwell_domain_expansion_pending_state = data.pending_state
            if data.pending_pos ~= nil then
                player._waxwell_domain_expansion_pending_position = Vector3(data.pending_pos.x, 0, data.pending_pos.z)
            end
            if data.pending_state == "spawning" and data.pending_pos ~= nil then
                WaitForExistingPetsToClear(player, Vector3(data.pending_pos.x, 0, data.pending_pos.z))
            end
        end

        if (data.cooldown_time or 0) > 0 and player.components ~= nil and player.components.spellbookcooldowns ~= nil then
            spell_utils.RestartSpellCooldown(player, V.DOMAIN_EXPANSION_COOLDOWN_ID, data.cooldown_time)
        end

        PushSpellRefresh(player)
    end)
end

local function IsDomainExpansionOnCooldown(doer)
    return spell_utils.IsSpellOnCooldown(doer, V.DOMAIN_EXPANSION_COOLDOWN_ID)
end

local function GetDomainExpansionCooldownPercent(doer)
    return spell_utils.GetSpellCooldownPercent(doer, V.DOMAIN_EXPANSION_COOLDOWN_ID)
end

local function SpellCost(pct)
    if debug.ShouldIgnoreCodexUmbraDurability() then
        return 0
    end
    return pct * TUNING.LARGE_FUEL * -4
end

local function HasEnoughCodexFuel(inst, costpct)
    if debug.ShouldIgnoreCodexUmbraDurability() then
        return true
    end
    local fueled = inst ~= nil and inst.components ~= nil and inst.components.fueled or nil
    local cost = SpellCost(costpct)
    return fueled ~= nil
        and fueled.currentfuel ~= nil
        and cost ~= nil
        and fueled.currentfuel >= math.abs(cost) - .001
end

local function GetDomainExpansionCastBlockReason(inst, doer)
    if inst == nil or inst.components == nil or inst.components.fueled == nil then
        return "MISSING_FUELED"
    elseif inst.components.fueled:IsEmpty() then
        return "NO_FUEL_EMPTY"
    elseif not HasEnoughCodexFuel(inst, V.DOMAIN_EXPANSION_DURABILITY_COST_PCT) then
        return "NO_FUEL_COST"
    elseif not IsDomainExpansionSkillActive(doer) then
        return "SKILL_INACTIVE"
    elseif IsDomainExpansionOnCooldown(doer) then
        return "SPELL_ON_COOLDOWN"
    elseif not HasDomainExpansionSanityToCast(doer) then
        return "SANITY_GATE"
    end

    return nil
end

local function BeginDomainExpansionField(owner, pos)
    if owner == nil or not owner:IsValid() then
        return false
    end

    ClearDomainExpansionStateCache(owner)

    local state = GetDomainExpansionSpellState(owner)
    if state ~= "spawning" then
        return false
    end

    local field = SpawnPrefab("domainexpansion_field")
    if field == nil then
        ClearPendingDomainState(owner)
        PushSpellRefresh(owner)
        return false
    end

    owner._waxwell_domain_expansion_field = field
    ClearDomainExpansionStateCache(owner)
    ClearPendingDomainState(owner)
    field:Activate(owner, pos, V.DOMAIN_EXPANSION_RADIUS)
    PushSpellRefresh(owner)
    return true
end

local function WaitForExistingPetsToClear(owner, pos)
    if owner == nil or not owner:IsValid() then
        return
    end
    if owner.components ~= nil and owner.components.health ~= nil and owner.components.health:IsDead() then
        ClearPendingDomainState(owner)
        PushSpellRefresh(owner)
        return
    end

    local petleash = owner.components ~= nil and owner.components.petleash or nil
    local pets = petleash ~= nil and petleash:GetPets() or nil
    if pets ~= nil and next(pets) ~= nil then
        owner:DoTaskInTime(FRAMES, WaitForExistingPetsToClear, pos)
        return
    end

    BeginDomainExpansionField(owner, pos)
end

local function RequestDomainExpansionDeactivate(owner)
    local field = GetDomainField(owner)
    if field ~= nil and field.RequestDeactivate ~= nil then
        ClearDomainExpansionStateCache(owner)
        field:RequestDeactivate("manual")
        return true
    end
    return false
end

local function DomainExpansionSpellFn(inst, doer, pos)
    local owner = ResolveSpellOwner(inst, doer)
    if owner == nil then
        return false
    end

    local state = GetDomainExpansionSpellState(owner)
    if state == "active" then
        return RequestDomainExpansionDeactivate(owner)
    elseif state ~= nil then
        return false
    end

    local castpos = owner:GetPosition()
    local blockreason = GetDomainExpansionCastBlockReason(inst, owner, castpos)
    if blockreason == "NO_FUEL_EMPTY" or blockreason == "NO_FUEL_COST" then
        return false, "NO_FUEL"
    elseif blockreason == "SPELL_ON_COOLDOWN" then
        return false, "SPELL_ON_COOLDOWN"
    elseif blockreason == "SKILL_INACTIVE" or blockreason == "SANITY_GATE" then
        return false
    elseif blockreason ~= nil then
        return false
    end

    owner._waxwell_domain_expansion_pending_state = "spawning"
    owner._waxwell_domain_expansion_pending_position = Vector3(castpos.x, 0, castpos.z)
    ClearDomainExpansionStateCache(owner)
    PushSpellRefresh(owner)

    if owner.components ~= nil and owner.components.petleash ~= nil then
        owner.components.petleash:DespawnAllPets()
    end

    if inst.components ~= nil and inst.components.fueled ~= nil then
        inst.components.fueled:DoDelta(SpellCost(V.DOMAIN_EXPANSION_DURABILITY_COST_PCT), owner)
    end

    owner:DoTaskInTime(0, WaitForExistingPetsToClear, castpos)
    return true
end

local function GetDomainExpansionSpellData(user)
    local DOMAIN_EXPANSION_LABEL = STRINGS.SPELLS[V.DOMAIN_EXPANSION_SPELL] or "Domain Expansion"

    local function GetCurrentState(inst)
        return GetDomainExpansionSpellState(ResolveSpellOwner(inst, user))
    end

    local item = {
        spell_id = V.DOMAIN_EXPANSION_SPELL,
        label = DOMAIN_EXPANSION_LABEL,
        onselect = function(inst)
            local currentstate = GetCurrentState(inst)
            local isactive = currentstate == "active"

            inst.components.spellbook:SetSpellName(DOMAIN_EXPANSION_LABEL)
            inst.components.spellbook:SetSpellAction(nil)
            inst.components.aoetargeting:SetRange(nil)
            inst.components.aoetargeting:SetAlwaysValid(false)
            inst.components.aoetargeting:SetAllowWater(false)
            inst.components.aoetargeting:SetDeployRadius(0)
            inst.components.aoetargeting:SetShouldRepeatCastFn(function()
                return false
            end)
            inst.components.aoetargeting:SetTargetFX(nil)
            inst.components.spellbook:SetSpellFn(DomainExpansionSpellFn)
            if TheWorld.ismastersim then
                inst.components.aoespell:SetSpellFn(nil)
            end
        end,
        execute = function(inst)
            local currentstate = GetCurrentState(inst)
            local isbusy = currentstate == "spawning" or currentstate == "deactivating"
            if isbusy then
                return true
            end
            if currentstate == "active" then
                CastSpellBookFromInventory(inst, ACTIONS.CAST_SPELLBOOK)
                return
            end
            TriggerInstantSpellbookCast(inst, ACTIONS.CAST_SPELLBOOK)
        end,
        atlas = "images/waxwell/waxwell_codex_icon.xml",
        normal = "codex_umbra_imperial_regalia.tex",
        widget_scale = V.DOMAIN_EXPANSION_ICON_SCALE,
        hit_radius = V.DOMAIN_EXPANSION_ICON_RADIUS,
        checkenabled = function(u)
            if GetDomainExpansionSpellState(u) ~= nil then
                return true
            end
            return HasDomainExpansionSanityToCast(u)
        end,
    }

    return SpellIcon.BindToggleSpellItem(item,
        function(u)
            return GetDomainExpansionSpellState(u)
        end,
        function(u)
            return GetDomainExpansionCooldownPercent(u)
        end)
end

return {
    IsDomainExpansionSkillActive = IsDomainExpansionSkillActive,
    GetDomainExpansionSpellData = GetDomainExpansionSpellData,
    GetDomainExpansionSpellState = function(owner)
        local state = GetDomainExpansionSpellState(owner)
        return state
    end,
    IsDomainExpansionSummonLockActive = IsDomainExpansionSummonLockActive,
    HasDomainExpansionSanityToCast = HasDomainExpansionSanityToCast,
    RequestDomainExpansionDeactivate = RequestDomainExpansionDeactivate,
    GetDomainExpansionPersistData = GetDomainExpansionPersistData,
    RestoreDomainExpansionPersistData = RestoreDomainExpansionPersistData,
}
