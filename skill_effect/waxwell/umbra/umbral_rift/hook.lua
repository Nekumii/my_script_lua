local common = require("skill_effect/waxwell/umbra/umbral_rift/common")

local UMBRAL_RIFT_RPC = common.UMBRAL_RIFT_RPC
local PlaceUmbralRiftMark = common.PlaceUmbralRiftMark
local RemoveUmbralRiftMark = common.RemoveUmbralRiftMark
local CancelUmbralRiftSkill = common.CancelUmbralRiftSkill
local HasUmbralRiftMark = common.HasUmbralRiftMark
local IsUmbralRiftBook = common.IsUmbralRiftBook

local M = {}

-- =============================================================================
-- Constants
-- =============================================================================

-- state ที่ถือว่าเป็น interrupt → ลบ mark + ปิดสกิล
local UMBRAL_RIFT_INTERRUPT_STATES =
{
    death = true,
    frozen = true,
    stunlock = true,
    sleep = true,
    knockback = true,
    electrocute = true,
    sinkhole = true,
}

-- =============================================================================
-- Private helper
-- =============================================================================

local function IsUmbralRiftTargetingBook(player)
    if player == nil or not player:IsValid() then
        return false
    end

    local pc = player.components ~= nil and player.components.playercontroller or nil
    if pc == nil or not pc:IsAOETargeting() or pc.reticule == nil then
        return false
    end

    return IsUmbralRiftBook(pc.reticule.inst)
end

local function ClearUmbralRiftFromInterrupt(player)
    if player == nil then
        return
    end

    if HasUmbralRiftMark(player) or IsUmbralRiftTargetingBook(player) then
        CancelUmbralRiftSkill(player)
    end
end

-- =============================================================================
-- Registration
-- =============================================================================

local function RegisterUmbralRiftRPC(env)
    if rawget(_G, "_waxwell_umbral_rift_rpc_registered") then
        return
    end
    rawset(_G, "_waxwell_umbral_rift_rpc_registered", true)

    env.AddModRPCHandler(UMBRAL_RIFT_RPC.NAMESPACE, UMBRAL_RIFT_RPC.PLACE_MARK, function(player, x, z)
        if player == nil or not player:IsValid() or x == nil or z == nil then
            return
        end
        PlaceUmbralRiftMark(player, Vector3(x, 0, z))
    end)

    env.AddModRPCHandler(UMBRAL_RIFT_RPC.NAMESPACE, UMBRAL_RIFT_RPC.BEGIN_WARP, function(player)
        if player == nil or not player:IsValid() then
            return
        end
        common.ReserveUmbralRiftWarpCast(player)
    end)

    env.AddModRPCHandler(UMBRAL_RIFT_RPC.NAMESPACE, UMBRAL_RIFT_RPC.CANCEL, function(player)
        if player == nil or not player:IsValid() then
            return
        end
        -- อย่าลบ mark ตอนกำลัง warp จุด 2 (reticule ปิดก่อน spell fn รันบน server)
        if player._waxwell_umbral_rift_casting or player._waxwell_umbral_rift_warp_reserved then
            return
        end
        -- server: ลบ mark เท่านั้น (reticule ปิดฝั่ง client ที่เรียก RPC)
        RemoveUmbralRiftMark(player, true)
    end)
end

function M.Register(env)
    local AddPrefabPostInit = env.AddPrefabPostInit

    RegisterUmbralRiftRPC(env)

    AddPrefabPostInit("waxwell", function(inst)
        if not TheWorld.ismastersim then
            return
        end

        inst:ListenForEvent("death", function(player)
            CancelUmbralRiftSkill(player)
        end)

        inst:ListenForEvent("newstate", function(player, data)
            if data == nil or data.statename == nil then
                return
            end

            if UMBRAL_RIFT_INTERRUPT_STATES[data.statename] then
                ClearUmbralRiftFromInterrupt(player)
            end
        end)
    end)
end

return M
