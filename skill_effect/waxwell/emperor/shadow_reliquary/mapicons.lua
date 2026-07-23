-- Shadow Reliquary minimap icons: owner-private (default) or shared (mod setting).
local mod_config = require("mod_config")

-- =============================================================================
-- Private helpers
-- =============================================================================

local function FindOwnerPlayer(userid)
    if userid == nil or userid == "" or AllPlayers == nil then
        return nil
    end
    for _, player in ipairs(AllPlayers) do
        if player ~= nil and player.userid == userid then
            return player
        end
    end
    return nil
end

local function IsShareMinimapEnabled()
    return mod_config.IsShadowReliquaryShareMinimapEnabled()
end

local function ClearWaitPlayer(inst)
    if inst ~= nil and inst._mapicon_wait_player ~= nil and TheWorld ~= nil then
        TheWorld:RemoveEventCallback("ms_playerjoined", inst._mapicon_wait_player)
        inst._mapicon_wait_player = nil
    end
end

local function ClearMapIcons(inst)
    if inst == nil then
        return
    end
    ClearWaitPlayer(inst)
    if inst._mapicon_near ~= nil then
        if inst._mapicon_near:IsValid() then
            inst._mapicon_near:Remove()
        end
        inst._mapicon_near = nil
    end
    if inst._mapicon_far ~= nil then
        if inst._mapicon_far:IsValid() then
            inst._mapicon_far:Remove()
        end
        inst._mapicon_far = nil
    end
end

local function DisablePublicMinimap(inst)
    if inst ~= nil and inst.MiniMapEntity ~= nil then
        inst.MiniMapEntity:SetEnabled(false)
    end
end

local function ConfigureMapIconEntity(mapicon, icon)
    mapicon.MiniMapEntity:SetIcon(icon)
    mapicon.MiniMapEntity:SetPriority(20)
    mapicon.MiniMapEntity:SetCanUseCache(false)
    mapicon.MiniMapEntity:SetDrawOverFogOfWar(true, true)
end

local function SpawnTrackedMapIcon(prefab_name, inst, icon, restriction, owner)
    local mapicon = SpawnPrefab(prefab_name)
    if mapicon == nil then
        return nil
    end

    ConfigureMapIconEntity(mapicon, icon)
    mapicon:TrackEntity(inst, restriction, icon)

    if owner ~= nil and owner:IsValid() and mapicon.Network ~= nil then
        mapicon.Network:SetClassifiedTarget(owner)
    end

    return mapicon
end

local function AttachGlobalMapIcons(inst, icon, owner, restriction)
    ClearMapIcons(inst)
    DisablePublicMinimap(inst)

    inst._mapicon_near = SpawnTrackedMapIcon("globalmapiconnoproxy", inst, icon, restriction, owner)
    inst._mapicon_far = SpawnTrackedMapIcon("globalmapicon", inst, icon, restriction, owner)
end

local function AttachPrivateMapIcons(inst, owner, icon)
    if owner == nil or not owner:IsValid() or owner.userid == nil or owner.userid == "" then
        return
    end

    local restriction = "player_" .. owner.userid
    AttachGlobalMapIcons(inst, icon, owner, restriction)
end

local function AttachSharedMapIcons(inst, icon)
    AttachGlobalMapIcons(inst, icon, nil, nil)
end

-- =============================================================================
-- Public API
-- =============================================================================

local function EnsureMapIcons(inst, owner_userid, icon)
    if TheWorld == nil or not TheWorld.ismastersim then
        return
    end
    if inst == nil or not inst:IsValid() or icon == nil then
        return
    end

    if IsShareMinimapEnabled() then
        AttachSharedMapIcons(inst, icon)
        return
    end

    local owner = inst.owner
    if owner == nil or not owner:IsValid() then
        owner = FindOwnerPlayer(owner_userid)
        inst.owner = owner
    end
    if owner ~= nil then
        AttachPrivateMapIcons(inst, owner, icon)
        return
    end

    if owner_userid == nil or owner_userid == "" then
        return
    end
    if inst._mapicon_wait_player ~= nil then
        return
    end
    inst._mapicon_wait_player = function(_, player)
        if inst == nil or not inst:IsValid() then
            return
        end
        if player ~= nil and player.userid == owner_userid then
            inst.owner = player
            AttachPrivateMapIcons(inst, player, icon)
        end
    end
    TheWorld:ListenForEvent("ms_playerjoined", inst._mapicon_wait_player)
end

return {
    ClearMapIcons = ClearMapIcons,
    EnsureMapIcons = EnsureMapIcons,
    IsShareMinimapEnabled = IsShareMinimapEnabled,
}
