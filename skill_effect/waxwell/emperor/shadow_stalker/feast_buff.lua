local CodexIcons = require("skill_effect/waxwell/_shared/codex_icon_atlas")

local M = {}

M.TYPES = {
    NONE = "none",
    DUELIST = "duelist",
    WORKER = "worker",
    LANTERN = "lantern",
    MARKSMAN = "marksman",
}

local PREFAB_TO_TYPE =
{
    shadowprotector = M.TYPES.DUELIST,
    shadowwaxwell = M.TYPES.DUELIST,
    shadowworker = M.TYPES.WORKER,
    shadow_lanternbearer = M.TYPES.LANTERN,
    shadow_marksman = M.TYPES.MARKSMAN,
}

local NET_INDEX =
{
    [M.TYPES.NONE] = 0,
    [M.TYPES.DUELIST] = 1,
    [M.TYPES.WORKER] = 2,
    [M.TYPES.LANTERN] = 3,
    [M.TYPES.MARKSMAN] = 4,
}

local INDEX_TO_TYPE =
{
    [0] = M.TYPES.NONE,
    [1] = M.TYPES.DUELIST,
    [2] = M.TYPES.WORKER,
    [3] = M.TYPES.LANTERN,
    [4] = M.TYPES.MARKSMAN,
}

M.UI_OPACITY = 0.6
M.UI_IMAGE_SIZE = 88
M.UI_SYMBOL = "torso"
-- Negative Y raises the icon in symbol space (same convention as talker offsets).
M.UI_SYMBOL_OFFSET = Vector3(0, -410, 0)
M.UI_SCREEN_OFFSET = Vector3(0, 0, 0)
M.UI_WORLD_FALLBACK_OFFSET_Y = 3.5

-- Viewer-relative screen nudge: keeps icon on visual chest center as camera orbits.
M.UI_PARALLAX_ENABLED = true
M.UI_PARALLAX_LATERAL = 12
M.UI_PARALLAX_LATERAL_FAR_REF = 6
M.UI_PARALLAX_LATERAL_FAR_MIN = 0.12
M.UI_PARALLAX_LATERAL_FAR_MAX = 0.28
M.UI_PARALLAX_LATERAL_FAR_START = 10
M.UI_PARALLAX_LATERAL_FAR_EXTRA_REF = 6
M.UI_PARALLAX_LATERAL_FAR_END_SCALE = 0.4
M.UI_PARALLAX_DEPTH_UP = 48
M.UI_PARALLAX_DEPTH_DOWN = 5
M.UI_PARALLAX_SMOOTH = 0.4
M.UI_PARALLAX_FALLOFF_NEAR = 6
M.UI_PARALLAX_FALLOFF_FAR = 16
M.UI_PARALLAX_MIN_DIST = 0.5

local function GetParallaxFalloff(dist)
    if dist <= M.UI_PARALLAX_FALLOFF_NEAR then
        return 0
    end
    if dist >= M.UI_PARALLAX_FALLOFF_FAR then
        return 1
    end

    local t = (dist - M.UI_PARALLAX_FALLOFF_NEAR) / (M.UI_PARALLAX_FALLOFF_FAR - M.UI_PARALLAX_FALLOFF_NEAR)
    return t * t * (3 - 2 * t)
end

function M.GetParallaxScreenOffset(target)
    if not M.UI_PARALLAX_ENABLED or target == nil or ThePlayer == nil or TheCamera == nil then
        return 0, 0
    end

    local px, _, pz = ThePlayer.Transform:GetWorldPosition()
    local sx, _, sz = target.Transform:GetWorldPosition()
    local dx, dz = px - sx, pz - sz
    local dist_sq = dx * dx + dz * dz
    if dist_sq < M.UI_PARALLAX_MIN_DIST * M.UI_PARALLAX_MIN_DIST then
        return 0, 0
    end

    local dist = math.sqrt(dist_sq)
    local falloff = GetParallaxFalloff(dist)
    if falloff <= 0 then
        return 0, 0
    end

    local inv_dist = 1 / dist
    local right = TheCamera:GetRightVec()
    local down = TheCamera:GetDownVec()
    local lateral = (dx * right.x + dz * right.z) * inv_dist
    local depth = (dx * down.x + dz * down.z) * inv_dist
    local hud_scale = TheFrontEnd:GetHUDScale()
    local lateral_falloff = falloff * falloff * falloff
    local far_damp = math.clamp(
        M.UI_PARALLAX_LATERAL_FAR_REF / dist,
        M.UI_PARALLAX_LATERAL_FAR_MIN,
        M.UI_PARALLAX_LATERAL_FAR_MAX
    )
    local far_extra = 1
    if dist > M.UI_PARALLAX_LATERAL_FAR_START then
        far_extra = math.clamp(M.UI_PARALLAX_LATERAL_FAR_EXTRA_REF / dist, M.UI_PARALLAX_LATERAL_FAR_MIN, 1)
    end
    local far_end_scale = 1
    if dist > M.UI_PARALLAX_LATERAL_FAR_START then
        local far_span = M.UI_PARALLAX_FALLOFF_FAR - M.UI_PARALLAX_LATERAL_FAR_START
        if far_span > 0 then
            local far_t = math.clamp((dist - M.UI_PARALLAX_LATERAL_FAR_START) / far_span, 0, 1)
            far_end_scale = 1 - far_t * (1 - (M.UI_PARALLAX_LATERAL_FAR_END_SCALE or 0.4))
        end
    end
    local lateral_px = lateral * M.UI_PARALLAX_LATERAL * hud_scale * lateral_falloff * far_damp * far_extra * far_end_scale

    local depth_px
    if depth < 0 then
        depth_px = -depth * M.UI_PARALLAX_DEPTH_UP * hud_scale * falloff
    else
        depth_px = depth * M.UI_PARALLAX_DEPTH_DOWN * hud_scale * falloff
    end

    return lateral_px, depth_px
end

local function ResolveAtlas(atlas)
    if atlas == nil then
        return atlas
    end
    if resolvefilepath ~= nil then
        return resolvefilepath(atlas) or atlas
    end
    return atlas
end

M.ICONS =
{
    [M.TYPES.NONE] =
    {
        atlas = CodexIcons.ATLAS,
        tex = CodexIcons.BUFF_FRAME,
    },
    [M.TYPES.DUELIST] =
    {
        atlas = "images/spell_icons.xml",
        tex = "shadow_protector.tex",
    },
    [M.TYPES.WORKER] =
    {
        atlas = "images/spell_icons.xml",
        tex = "shadow_worker.tex",
    },
    [M.TYPES.LANTERN] =
    {
        atlas = CodexIcons.ATLAS,
        tex = CodexIcons.SHADOW_LANTERNBEARER,
    },
    [M.TYPES.MARKSMAN] =
    {
        atlas = CodexIcons.ATLAS,
        tex = CodexIcons.SHADOW_MARKSMAN,
    },
}

function M.GetTypeFromPrefab(prefab)
    return prefab ~= nil and PREFAB_TO_TYPE[prefab] or nil
end

function M.GetTypeFromTarget(target)
    if target == nil then
        return nil
    end

    local bufftype = M.GetTypeFromPrefab(target.prefab)
    if bufftype ~= nil then
        return bufftype
    end

    if target:HasTag("shadow_lanternbearer") then
        return M.TYPES.LANTERN
    end
    if target:HasTag("shadow_marksman") then
        return M.TYPES.MARKSMAN
    end

    return nil
end

function M.GetTypeFromNetIndex(index)
    return INDEX_TO_TYPE[index or 0] or M.TYPES.NONE
end

function M.GetNetIndex(bufftype)
    return NET_INDEX[bufftype or M.TYPES.NONE] or 0
end

function M.GetIcon(bufftype)
    local icon = M.ICONS[bufftype or M.TYPES.NONE] or M.ICONS[M.TYPES.NONE]
    return {
        atlas = ResolveAtlas(icon.atlas),
        tex = icon.tex,
    }
end

function M.GetFeastBuffType(inst)
    if inst == nil then
        return M.TYPES.NONE
    end

    if inst._feast_buff_net ~= nil then
        return M.GetTypeFromNetIndex(inst._feast_buff_net:value())
    end

    return inst._feast_buff_type or M.TYPES.NONE
end

function M.SetFeastBuffType(inst, bufftype)
    if inst == nil or not TheWorld.ismastersim then
        return
    end

    bufftype = bufftype or M.TYPES.NONE
    if bufftype == M.TYPES.NONE then
        inst._feast_buff_type = nil
    else
        inst._feast_buff_type = bufftype
    end

    if inst._feast_buff_net ~= nil then
        inst._feast_buff_net:set(M.GetNetIndex(bufftype))
    end

    local FeastBuffEffects = require("skill_effect/waxwell/emperor/shadow_stalker/feast_buff_effects")
    if bufftype == M.TYPES.NONE then
        FeastBuffEffects.RemoveAll(inst)
    else
        FeastBuffEffects.Apply(inst, bufftype)
    end
end

function M.ClearFeastBuff(inst)
    M.SetFeastBuffType(inst, M.TYPES.NONE)
end

return M
