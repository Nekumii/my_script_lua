local Widget = require("widgets/widget")
local Image = require("widgets/image")
local FeastBuff = require("skill_effect/waxwell/emperor/shadow_stalker/feast_buff")

local FeastBuffIndicator = Class(Widget, function(self)
    Widget._ctor(self, "shadow_stalker_feast_buff_indicator")

    self:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self:SetMaxPropUpscale(MAX_HUD_SCALE)

    local frame = FeastBuff.GetIcon(FeastBuff.TYPES.NONE)
    self.icon = self:AddChild(Image(frame.atlas, frame.tex))
    self.icon:SetClickable(false)
    self.icon:SetSize(FeastBuff.UI_IMAGE_SIZE, FeastBuff.UI_IMAGE_SIZE)
    self.icon:SetTint(1, 1, 1, FeastBuff.UI_OPACITY)

    self.target = nil
    self.bufftype = FeastBuff.TYPES.NONE
    self.offset = FeastBuff.UI_SYMBOL_OFFSET
    self.screen_offset = FeastBuff.UI_SCREEN_OFFSET
    self._parallax_x = 0
    self._parallax_y = 0

    self:Hide()
    self:StartUpdating()
end)

function FeastBuffIndicator:SetHUD(hud)
    if self.hashud then
        return
    end

    self.hashud = true

    local hudinst = hud ~= nil and (hud.inst or hud) or nil
    if hudinst == nil then
        return
    end

    local function refresh_scale()
        self.icon:SetScale(TheFrontEnd:GetHUDScale())
    end

    refresh_scale()
    self.inst:ListenForEvent("continuefrompause", refresh_scale, hudinst)
    self.inst:ListenForEvent("refreshhudsize", function(_, hudscale)
        self.icon:SetScale(hudscale or TheFrontEnd:GetHUDScale())
    end, hudinst)
end

function FeastBuffIndicator:SetTarget(target)
    if self.target ~= target then
        self._parallax_x = 0
        self._parallax_y = 0
    end
    self.target = target
    self:OnUpdate()
end

function FeastBuffIndicator:SetBuffType(bufftype)
    bufftype = bufftype or FeastBuff.TYPES.NONE
    if self.bufftype == bufftype then
        return
    end

    self.bufftype = bufftype
    local icon = FeastBuff.GetIcon(bufftype)
    self.icon:SetTexture(icon.atlas, icon.tex)
    self.icon:SetSize(FeastBuff.UI_IMAGE_SIZE, FeastBuff.UI_IMAGE_SIZE)
    self.icon:SetTint(1, 1, 1, FeastBuff.UI_OPACITY)
    self.icon:SetScale(TheFrontEnd:GetHUDScale())
end

local function GetTargetScreenPos(target)
    if target.AnimState ~= nil then
        local sx, sy, sz, ok = target.AnimState:GetSymbolPosition(
            FeastBuff.UI_SYMBOL,
            FeastBuff.UI_SYMBOL_OFFSET.x,
            FeastBuff.UI_SYMBOL_OFFSET.y,
            FeastBuff.UI_SYMBOL_OFFSET.z
        )
        if ok then
            return TheSim:GetScreenPos(sx, sy, sz)
        end
    end

    local wx, wy, wz = target.Transform:GetWorldPosition()
    return TheSim:GetScreenPos(wx, wy + FeastBuff.UI_WORLD_FALLBACK_OFFSET_Y, wz)
end

function FeastBuffIndicator:OnUpdate()
    local target = self.target
    if target == nil or not target:IsValid() or not target:HasTag("shadow_stalker") then
        self:Hide()
        return
    end

    local hud_scale = TheFrontEnd:GetHUDScale()
    self.icon:SetSize(FeastBuff.UI_IMAGE_SIZE, FeastBuff.UI_IMAGE_SIZE)
    self.icon:SetScale(hud_scale)
    self.icon:SetTint(1, 1, 1, FeastBuff.UI_OPACITY)

    local x, y = GetTargetScreenPos(target)
    local target_px, target_py = FeastBuff.GetParallaxScreenOffset(target)
    local smooth = FeastBuff.UI_PARALLAX_SMOOTH or 1
    self._parallax_x = self._parallax_x + (target_px - self._parallax_x) * smooth
    self._parallax_y = self._parallax_y + (target_py - self._parallax_y) * smooth

    self:SetPosition(
        x + self.screen_offset.x + self._parallax_x,
        y + self.screen_offset.y + self._parallax_y,
        0
    )
    if self.MoveToFront ~= nil then
        self:MoveToFront()
    end
    self:Show()
end

return FeastBuffIndicator
