-- Shared horizontal fling for Shadow Reliquary loot / codex release.
local M = {}

local function EnsureFlingPhysics(ent)
    if ent == nil or not ent:IsValid() or ent.Physics == nil then
        return false
    end

    ent.Physics:SetActive(true)
    ent.Physics:Stop()
    return true
end

function M.FlingEntity(ent, x, y, z, speed_min, speed_max, y_min, y_max, xz_spread)
    if ent == nil or not ent:IsValid() then
        return
    end

    speed_min = speed_min or 4
    speed_max = math.max(speed_min, speed_max or speed_min)
    y_min = y_min or 2.5
    y_max = math.max(y_min, y_max or y_min)

    local spread = xz_spread or 0
    local ox = spread > 0 and (math.random() * 2 - 1) * spread or 0
    local oz = spread > 0 and (math.random() * 2 - 1) * spread or 0
    local px, py, pz = x + ox, y or 0, z + oz

    local theta = math.random() * TWOPI
    local speed = speed_min + math.random() * (speed_max - speed_min)
    local yspeed = y_min + math.random() * (y_max - y_min)
    local vx = math.cos(theta) * speed
    local vz = -math.sin(theta) * speed

    if EnsureFlingPhysics(ent) then
        ent.Physics:Teleport(px, py, pz)
        ent.Physics:SetVel(vx, yspeed, vz)
    else
        ent.Transform:SetPosition(px + vx * 0.4, py, pz + vz * 0.4)
    end

    local inv = ent.components ~= nil and ent.components.inventoryitem or nil
    if inv ~= nil then
        inv:OnDropped(true)
    end
end

return M
