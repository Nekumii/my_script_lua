local ModConfig = require("mod_config")
local FeastBuff = require("skill_effect/waxwell/emperor/shadow_stalker/feast_buff")
local FeastBuffIndicator = require("widgets/shadow_stalker_feast_buff_indicator")

local M = {}

local function IsUiEnabled()
    return ModConfig.IsShadowStalkerFeastBuffUiEnabled()
end

local function IsLocalClient()
    return ThePlayer ~= nil
end

local function GetSpellOwnerUserid(inst)
    if inst._shadow_stalker_spell_owner_userid_net ~= nil then
        local userid = inst._shadow_stalker_spell_owner_userid_net:value()
        if userid ~= nil and userid ~= "" then
            return userid
        end
    end

    return inst._shadow_stalker_spell_owner_userid
end

local function GetFollowerLeader(inst)
    if inst.replica ~= nil and inst.replica.follower ~= nil then
        return inst.replica.follower:GetLeader()
    end
    if inst.components ~= nil and inst.components.follower ~= nil then
        return inst.components.follower:GetLeader()
    end
    return nil
end

local function IsLocalSpellOwner(inst)
    if inst == nil or ThePlayer == nil or ThePlayer.userid == nil then
        return false
    end

    local owner_userid = GetSpellOwnerUserid(inst)
    if owner_userid ~= nil and owner_userid ~= "" then
        return ThePlayer.userid == owner_userid
    end

    return GetFollowerLeader(inst) == ThePlayer
end

local function ShouldAttachTo(inst)
    if inst == nil or not inst:IsValid() or not inst:HasTag("shadow_stalker") then
        return false
    end

    return IsLocalSpellOwner(inst)
end

local function ShouldRetryAttach(inst)
    if ShouldAttachTo(inst) then
        return true
    end

    local owner_userid = GetSpellOwnerUserid(inst)
    if owner_userid ~= nil and owner_userid ~= "" then
        return false
    end

    local leader = GetFollowerLeader(inst)
    return leader == nil or leader == ThePlayer
end

local function RefreshBuffType(inst)
    if inst._feast_buff_widget == nil then
        return
    end

    inst._feast_buff_widget:SetBuffType(FeastBuff.GetFeastBuffType(inst))
end

local function DetachWidget(inst)
    if inst._feast_buff_widget ~= nil then
        inst._feast_buff_widget:Kill()
        inst._feast_buff_widget = nil
    end
end

local function CleanupListeners(inst)
    if inst._feast_buff_ui_listeners then
        if inst._feast_buff_net ~= nil and inst._feast_buff_ui_listeners.net ~= nil then
            inst:RemoveEventCallback("shadow_stalker_feastbuffdirty", inst._feast_buff_ui_listeners.net)
        end
        if inst._feast_buff_ui_listeners.owner ~= nil then
            inst:RemoveEventCallback("shadow_stalker_spellownerdirty", inst._feast_buff_ui_listeners.owner)
        end
        if inst._feast_buff_ui_listeners.remove ~= nil then
            inst:RemoveEventCallback("onremove", inst._feast_buff_ui_listeners.remove)
        end
        inst._feast_buff_ui_listeners = nil
    end
end

local function Detach(inst)
    DetachWidget(inst)
    CleanupListeners(inst)
end

local function Attach(inst)
    if not IsLocalClient() or not IsUiEnabled() then
        Detach(inst)
        return
    end

    if not ShouldAttachTo(inst) then
        DetachWidget(inst)
        return
    end

    if inst._feast_buff_widget == nil then
        local widget = FeastBuffIndicator()
        ThePlayer.HUD:AddChild(widget)
        widget:SetHUD(ThePlayer.HUD.inst)
        inst._feast_buff_widget = widget
    end

    inst._feast_buff_widget:SetTarget(inst)
    RefreshBuffType(inst)
end

local function EnsureListeners(inst)
    inst._feast_buff_ui_listeners = inst._feast_buff_ui_listeners or {}

    if inst._feast_buff_ui_listeners.net == nil and inst._feast_buff_net ~= nil then
        inst._feast_buff_ui_listeners.net = function()
            RefreshBuffType(inst)
            if IsUiEnabled() and inst._feast_buff_widget == nil then
                Attach(inst)
            elseif not IsUiEnabled() then
                Detach(inst)
            end
        end
        inst:ListenForEvent("shadow_stalker_feastbuffdirty", inst._feast_buff_ui_listeners.net)
    end

    if inst._feast_buff_ui_listeners.owner == nil and inst._shadow_stalker_spell_owner_userid_net ~= nil then
        inst._feast_buff_ui_listeners.owner = function()
            if ShouldAttachTo(inst) then
                Attach(inst)
            else
                DetachWidget(inst)
            end
        end
        inst:ListenForEvent("shadow_stalker_spellownerdirty", inst._feast_buff_ui_listeners.owner)
    end

    if inst._feast_buff_ui_listeners.remove == nil then
        inst._feast_buff_ui_listeners.remove = function()
            Detach(inst)
        end
        inst:ListenForEvent("onremove", inst._feast_buff_ui_listeners.remove)
    end
end

local function TryAttach(inst, tries_left)
    if inst == nil or not inst:IsValid() then
        return
    end

    if not IsLocalClient() then
        return
    end

    EnsureListeners(inst)

    if ShouldAttachTo(inst) then
        Attach(inst)
        return
    end

    if not ShouldRetryAttach(inst) then
        DetachWidget(inst)
        return
    end

    if tries_left > 0 then
        inst:DoTaskInTime(0.25, function()
            TryAttach(inst, tries_left - 1)
        end)
    end
end

function M.ScheduleAttach(inst)
    if inst == nil then
        return
    end

    inst:DoTaskInTime(0, function()
        if not inst:IsValid() then
            return
        end

        if not IsLocalClient() then
            inst:DoTaskInTime(0.5, function()
                if inst:IsValid() then
                    TryAttach(inst, 8)
                end
            end)
            return
        end

        TryAttach(inst, 8)
    end)
end

function M.AttachClient(inst)
    if inst == nil or not IsLocalClient() then
        return
    end

    EnsureListeners(inst)
    Attach(inst)
end

function M.DetachClient(inst)
    Detach(inst)
end

return M
