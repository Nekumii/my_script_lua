-- =============================================================================
-- Domain Expansion combat focus block (cross-barrier)
-- =============================================================================
-- Blocks combat targeting across an active DE circle in BOTH directions:
--   outside → inside  AND  inside → outside
-- Also exposes helpers for Umbral Rift enter/exit retarget refreshes.

local V = require("skill_effect/waxwell/emperor/domain_expansion/variables")

local ACTIVE_FIELDS = {}
local ACTIVE_FIELD_COUNT = 0

local FOCUS_CLEAR_PERIOD = .5
local FOCUS_CLEAR_EXTRA_RANGE = 40
local FOCUS_CLEAR_CANT_TAGS = { "INLIMBO", "FX", "NOCLICK", "DECOR" }

local M = {}

local function GetFieldRadius(field)
    if field._domain_radius ~= nil then
        local radius = field._domain_radius:value()
        if radius ~= nil and radius > 0 then
            return radius
        end
    end

    return field.radius or V.DOMAIN_EXPANSION_RADIUS
end

local function IsFieldLive(field)
    if field == nil or not field:IsValid() then
        return false
    end

    if field._domain_live ~= nil then
        return field._domain_live:value()
    end

    return field._active == true and field._ending ~= true
end

local function IsPointInDomain(field, x, z)
    if field == nil or not field:IsValid() then
        return false
    end
    local cx, _, cz = field.Transform:GetWorldPosition()
    local radius = GetFieldRadius(field)
    local dx = x - cx
    local dz = z - cz
    return (dx * dx + dz * dz) <= (radius * radius)
end

function M.RegisterField(field)
    if field ~= nil and ACTIVE_FIELDS[field] == nil then
        ACTIVE_FIELDS[field] = true
        ACTIVE_FIELD_COUNT = ACTIVE_FIELD_COUNT + 1
    end
end

function M.UnregisterField(field)
    if field ~= nil and ACTIVE_FIELDS[field] ~= nil then
        ACTIVE_FIELDS[field] = nil
        ACTIVE_FIELD_COUNT = math.max(0, ACTIVE_FIELD_COUNT - 1)
    end
end

function M.HasActiveFields()
    return ACTIVE_FIELD_COUNT > 0
end

-- True when attacker and target sit on opposite sides of an active DE barrier.
function M.IsCrossDomainTarget(attacker, target)
    if attacker == nil or target == nil or attacker == target then
        return false
    end
    if not attacker:IsValid() or not target:IsValid() then
        return false
    end
    if attacker.Transform == nil or target.Transform == nil then
        return false
    end

    local ax, _, az = attacker.Transform:GetWorldPosition()
    local tx, _, tz = target.Transform:GetWorldPosition()

    for field in pairs(ACTIVE_FIELDS) do
        if not IsFieldLive(field) then
            ACTIVE_FIELDS[field] = nil
            ACTIVE_FIELD_COUNT = math.max(0, ACTIVE_FIELD_COUNT - 1)
        else
            local attacker_inside = IsPointInDomain(field, ax, az)
            local target_inside = IsPointInDomain(field, tx, tz)
            if attacker_inside ~= target_inside then
                return true
            end
        end
    end

    return false
end

function M.ClearCombatFocusForEntity(ent)
    local combat = ent ~= nil and ent:IsValid() and ent.components ~= nil and ent.components.combat or nil
    local target = combat ~= nil and combat.target or nil
    if target ~= nil and target:IsValid() and M.IsCrossDomainTarget(ent, target) then
        combat:DropTarget()
    end
end

-- Drop focus on the teleported entity AND nearby mobs that were targeting it.
function M.RefreshCombatFocusAroundEntity(ent, radius)
    if ent == nil or not ent:IsValid() or not M.HasActiveFields() then
        return
    end

    M.ClearCombatFocusForEntity(ent)

    if ent.Transform == nil then
        return
    end

    local x, _, z = ent.Transform:GetWorldPosition()
    local search = radius or FOCUS_CLEAR_EXTRA_RANGE
    local ents = TheSim:FindEntities(x, 0, z, search, nil, FOCUS_CLEAR_CANT_TAGS)
    for _, other in ipairs(ents) do
        if other ~= ent then
            local combat = other.components ~= nil and other.components.combat or nil
            if combat ~= nil and combat.target == ent and M.IsCrossDomainTarget(other, ent) then
                combat:DropTarget()
            elseif combat ~= nil and combat.target ~= nil and M.IsCrossDomainTarget(other, combat.target) then
                combat:DropTarget()
            end
        end
    end
end

function M.ClearOutsideFocusOnField(field)
    if field == nil or not field:IsValid() or not IsFieldLive(field) then
        return
    end

    local function TryDrop(ent)
        local combat = ent ~= nil and ent:IsValid() and ent.components ~= nil and ent.components.combat or nil
        local target = combat ~= nil and combat.target or nil
        if target ~= nil and target:IsValid() and M.IsCrossDomainTarget(ent, target) then
            combat:DropTarget()
        end
    end

    local cx, _, cz = field.Transform:GetWorldPosition()
    local radius = GetFieldRadius(field)
    local searchradius = radius + FOCUS_CLEAR_EXTRA_RANGE
    local ents = TheSim:FindEntities(cx, 0, cz, searchradius, nil, FOCUS_CLEAR_CANT_TAGS)

    for _, ent in ipairs(ents) do
        TryDrop(ent)
    end
end

function M.GetFocusClearPeriod()
    return FOCUS_CLEAR_PERIOD
end

return M
