local V = require("skill_effect/waxwell/emperor/shadow_stalker/variables")
local domain_expansion = require("skill_effect/waxwell/emperor/domain_expansion/common")
local ReticuleUtils = require("reticule/utils")
local SpellIcon = require("skill_effect/waxwell/_shared/codex_spell_icon")

return function(shared)
    local CanAddShadowServant = shared.CanAddShadowServant
    local GetFragmentedMindPenalty = shared.GetFragmentedMindPenalty
    local ResolveSpellOwner = shared.ResolveSpellOwner
    local PushEmperorSpellRefresh = shared.PushEmperorSpellRefresh
    local FindShadowStalkerSpawnPoint = shared.FindShadowStalkerSpawnPoint
    local HasEnoughCodexFuel = shared.HasEnoughCodexFuel
    local SpellCost = shared.SpellCost
    local IsSpellOnCooldown = shared.IsSpellOnCooldown
    local GetSpellCooldownPercent = shared.GetSpellCooldownPercent
    local RestartSpellCooldown = shared.RestartSpellCooldown
    local StartAOETargeting = shared.StartAOETargeting
    local TriggerInstantSpellbookCast = shared.TriggerInstantSpellbookCast

    local function IsShadowStalkerSkillActive(inst)
        return inst ~= nil
            and (
                (inst.components ~= nil
                    and inst.components.skilltreeupdater ~= nil
                    and inst.components.skilltreeupdater:IsActivated("waxwell_shadow_stalker"))
                or inst:HasTag("shadow_stalker_active")
            )
    end

    local function IsShadowStalkerDying(pet)
        if pet == nil or not pet:IsValid() then
            return false
        end

        if pet._shadow_stalker_spell_deactivating then
            return true
        end

        if pet.sg ~= nil and pet.sg:HasStateTag("dead") then
            return true
        end

        local health = pet.components ~= nil and pet.components.health or nil
        return health ~= nil and health:IsDead()
    end

    local function FindOccupyingShadowStalker(owner)
        local petleash = owner ~= nil and owner.components ~= nil and owner.components.petleash or nil
        local pets = petleash ~= nil and petleash:GetPets() or nil
        if pets ~= nil then
            for pet in pairs(pets) do
                if pet ~= nil and pet:IsValid() and pet.prefab == "shadow_stalker" then
                    return pet
                end
            end
        end
    end

    local function FindActiveShadowStalker(owner)
        local pet = FindOccupyingShadowStalker(owner)
        if pet == nil or IsShadowStalkerDying(pet) then
            return nil
        end

        if pet:HasTag(V.SHADOW_STALKER_ACTIVE_TAG) or pet._shadow_stalker_spell_spawning then
            return pet
        end
    end

    local function GetShadowStalkerSpellState(owner)
        local pet = FindOccupyingShadowStalker(owner)
        if pet == nil then
            return nil, nil
        elseif IsShadowStalkerDying(pet) then
            return "deactivating", pet
        elseif pet._shadow_stalker_spell_spawning then
            return "spawning", pet
        elseif pet:HasTag(V.SHADOW_STALKER_ACTIVE_TAG) or pet._shadow_stalker_spell_active then
            return "active", pet
        end

        return nil, nil
    end

    local function GetShadowStalkerPenalty()
        return .75
    end

    local function IsShadowStalkerOnCooldown(doer)
        return IsSpellOnCooldown(doer, V.SHADOW_STALKER_COOLDOWN_ID)
    end

    local function GetShadowStalkerCooldownPercent(doer)
        return GetSpellCooldownPercent(doer, V.SHADOW_STALKER_COOLDOWN_ID)
    end

    local function GetShadowStalkerActiveDurationPercent(owner)
        local state, pet = GetShadowStalkerSpellState(owner)
        if state ~= "active" or pet == nil then
            return nil
        end

        return SpellIcon.GetEntityTimerRemainingPercent(pet, V.SHADOW_STALKER_LIFETIME_TIMER)
    end

    local function GetShadowStalkerCastBlockReason(inst, doer, pos)
        if inst == nil or inst.components == nil or inst.components.fueled == nil then
            return "MISSING_FUELED"
        elseif inst.components.fueled:IsEmpty() then
            return "NO_FUEL_EMPTY"
        elseif not HasEnoughCodexFuel(inst, V.SHADOW_STALKER_DURABILITY_COST_PCT) then
            return "NO_FUEL_COST"
        elseif not IsShadowStalkerSkillActive(doer) then
            return "SKILL_INACTIVE"
        elseif IsShadowStalkerOnCooldown(doer) then
            return "SPELL_ON_COOLDOWN"
        elseif domain_expansion ~= nil and domain_expansion.IsDomainExpansionSummonLockActive ~= nil and domain_expansion.IsDomainExpansionSummonLockActive(doer) then
            return "HASPET"
        elseif FindOccupyingShadowStalker(doer) ~= nil then
            return "HASPET"
        end

        local petleash = doer ~= nil and doer.components ~= nil and doer.components.petleash or nil
        local sanity = doer ~= nil and doer.components ~= nil and doer.components.sanity or nil
        local penalty = GetFragmentedMindPenalty(doer, "shadow_stalker") or GetShadowStalkerPenalty()
        if petleash == nil then
            return "NO_PETLEASH"
        elseif sanity == nil then
            return "NO_SANITY"
        elseif petleash:IsFullForPrefab("shadow_stalker") then
            return "FULL_FOR_PREFAB"
        elseif not CanAddShadowServant(petleash, "shadow_stalker") then
            return "SHADOW_SLOT_CAP"
        elseif sanity:GetPenaltyPercent() + penalty > TUNING.MAXIMUM_SANITY_PENALTY then
            return "SANITY_CAP"
        elseif FindShadowStalkerSpawnPoint(doer, pos) == nil then
            return "NO_TARGETS"
        end

        return nil
    end

    local function ShouldRepeatCastShadowStalker(inst, doer)
        return false
    end

    local function ShadowStalkerSpellFn(inst, doer, pos)
        local blockreason = GetShadowStalkerCastBlockReason(inst, doer, pos)
        if blockreason == "NO_FUEL_EMPTY" or blockreason == "NO_FUEL_COST" then
            return false, "NO_FUEL"
        elseif blockreason == "SPELL_ON_COOLDOWN" then
            return false, "SPELL_ON_COOLDOWN"
        elseif blockreason == "SKILL_INACTIVE" then
            return false
        elseif blockreason ~= nil and blockreason ~= "NO_TARGETS" then
            return false, "HASPET"
        elseif blockreason == "NO_TARGETS" then
            return false, "NO_TARGETS"
        end

        local spawnpos = FindShadowStalkerSpawnPoint(doer, pos)
        if spawnpos == nil then
            return false, "NO_TARGETS"
        end

        local owner = ResolveSpellOwner(inst, doer)
        if FindOccupyingShadowStalker(owner) ~= nil then
            return false, "HASPET"
        end

        local pet = doer.components.petleash:SpawnPetAt(spawnpos.x, 0, spawnpos.z, "shadow_stalker")
        if pet == nil then
            return false
        end
        if not pet:HasTag(V.SHADOW_STALKER_ACTIVE_TAG) then
            pet:AddTag(V.SHADOW_STALKER_ACTIVE_TAG)
        end
        pet._shadow_stalker_spell_active = true
        pet._shadow_stalker_spell_spawning = true
        pet._shadow_stalker_spell_owner = owner
        pet._shadow_stalker_spell_owner_userid = owner ~= nil and owner.userid or nil
        if pet._shadow_stalker_spell_owner_userid_net ~= nil then
            pet._shadow_stalker_spell_owner_userid_net:set(pet._shadow_stalker_spell_owner_userid or "")
        end
        if pet.EnsureOwnerDeathListener ~= nil and owner ~= nil then
            pet:EnsureOwnerDeathListener(owner)
        end
        if pet.SaveSpawnPoint ~= nil then
            pet:SaveSpawnPoint()
        end
        PushEmperorSpellRefresh(owner)

        local function onremovefn(inst_removed)
            if owner ~= nil then
                RestartSpellCooldown(owner, V.SHADOW_STALKER_COOLDOWN_ID, V.SHADOW_STALKER_COOLDOWN_TIME)
                PushEmperorSpellRefresh(owner)
            end
        end
        pet:ListenForEvent("onremove", onremovefn)

        inst.components.fueled:DoDelta(SpellCost(V.SHADOW_STALKER_DURABILITY_COST_PCT), doer)
        return true
    end

    local function RequestShadowStalkerDeactivate(owner)
        if owner == nil or owner.components == nil or owner.components.petleash == nil then
            return false
        end

        local pet = FindActiveShadowStalker(owner)
        if pet == nil then
            return false
        end

        if pet._shadow_stalker_spell_deactivating then
            return false
        end

        if pet.RequestSpellDeactivate ~= nil then
            pet:RequestSpellDeactivate()
        else
            pet._force_despawn = true
            if pet.sg ~= nil then
                pet.sg:GoToState("despawn")
            end
        end

        PushEmperorSpellRefresh(owner)
        return true
    end

    local function RemoveShadowStalkerSpellFn(inst, doer, pos)
        local owner = ResolveSpellOwner(inst, doer)
        return RequestShadowStalkerDeactivate(owner)
    end

    local function GetShadowStalkerSpellData(user)
        local function GetCurrentState(inst)
            return GetShadowStalkerSpellState(ResolveSpellOwner(inst, user))
        end

        local item = {
            spell_id = V.SHADOW_STALKER_SPELL,
            label = STRINGS.SPELLS[V.SHADOW_STALKER_SPELL] or "Shadow Stalker",
            onselect = function(inst)
                local currentstate = GetCurrentState(inst)
                local isactive = currentstate == "active"
                inst.components.spellbook:SetSpellName(STRINGS.SPELLS[V.SHADOW_STALKER_SPELL] or "Shadow Stalker")
                inst.components.spellbook:SetSpellAction(isactive and ACTIONS.CAST_SPELLBOOK or nil)
                inst.components.aoetargeting:SetAlwaysValid(false)
                inst.components.aoetargeting:SetAllowWater(false)
                inst.components.aoetargeting:SetDeployRadius(0)
                inst.components.aoetargeting:SetShouldRepeatCastFn(ShouldRepeatCastShadowStalker)
                ReticuleUtils.ApplySpellReticule(inst, inst.components.aoetargeting, V.SHADOW_STALKER_RETICULE_SCALE, ReticuleUtils.ANIM_LARGE, {
                    cast_range = V.SHADOW_STALKER_CAST_RANGE,
                })
                if isactive then
                    inst.components.spellbook:SetSpellFn(RemoveShadowStalkerSpellFn)
                    if TheWorld.ismastersim then
                        inst.components.aoetargeting:SetTargetFX(nil)
                        inst.components.aoespell:SetSpellFn(nil)
                    end
                else
                    inst.components.spellbook:SetSpellFn(nil)
                    if TheWorld.ismastersim then
                        inst.components.aoetargeting:SetTargetFX("reticuleaoesummontarget_1d2")
                        inst.components.aoespell:SetSpellFn(ShadowStalkerSpellFn)
                    end
                end
            end,
            execute = function(inst)
                local currentstate = GetCurrentState(inst)
                local isactive = currentstate == "active"
                local isbusy = currentstate == "spawning" or currentstate == "deactivating"
                if isbusy then
                    return true
                end
                if isactive then
                    TriggerInstantSpellbookCast(inst, ACTIONS.CAST_SPELLBOOK)
                else
                    StartAOETargeting(inst)
                end
            end,
            atlas = "images/waxwell/waxwell_codex_icon.xml",
            normal = "codex_umbra_shadow_stalker.tex",
            widget_scale = V.SHADOW_STALKER_ICON_SCALE,
            hit_radius = V.SHADOW_STALKER_ICON_RADIUS,
        }

        return SpellIcon.BindToggleSpellItem(item,
            function(u)
                return GetShadowStalkerSpellState(u)
            end,
            function(u)
                return GetShadowStalkerCooldownPercent(u)
            end,
            function(u)
                return GetShadowStalkerActiveDurationPercent(u)
            end)
    end

    return {
        IsShadowStalkerSkillActive = IsShadowStalkerSkillActive,
        FindActiveShadowStalker = FindActiveShadowStalker,
        GetShadowStalkerSpellState = GetShadowStalkerSpellState,
        GetShadowStalkerSpellData = GetShadowStalkerSpellData,
        RequestShadowStalkerDeactivate = RequestShadowStalkerDeactivate,
    }
end