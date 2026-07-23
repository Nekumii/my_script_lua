local skill_cost_display = require("skill_info/skill_cost_display")
local bitmap_text = require("ui/skilltree_cost_overlay/bitmap_text")

local Widget = require("widgets/widget")
local Image = require("widgets/image")

local GLYPH_ATLAS = bitmap_text.GLYPH_ATLAS
local ICON_SIZE = 26
local ICON_GAP = 0
local LEFT_TEXT_OFFSET = -15
local RIGHT_TEXT_OFFSET = 70

local DURABILITY_X, DURABILITY_Y = -203, -44
local SANITY_X, SANITY_Y = 110, -44

local SkillTreeCostOverlay = Class(Widget, function(self)
    Widget._ctor(self, "skilltree_cost_overlay")

    self.durability_row = self:AddChild(Widget("durability_row"))
    self.durability_row:SetPosition(DURABILITY_X, DURABILITY_Y)
    self.durability_icon = self.durability_row:AddChild(Image(GLYPH_ATLAS, "cost_durability.tex"))
    self.durability_icon:ScaleToSize(ICON_SIZE, ICON_SIZE)
    self.durability_text = self.durability_row:AddChild(bitmap_text.BitmapText())

    self.penalty_row = self:AddChild(Widget("penalty_row"))
    self.penalty_row:SetPosition(SANITY_X, SANITY_Y)
    self.penalty_icon = self.penalty_row:AddChild(Image(GLYPH_ATLAS, "cost_sanity_penalty.tex"))
    self.penalty_icon:ScaleToSize(ICON_SIZE, ICON_SIZE)
    self.penalty_text = self.penalty_row:AddChild(bitmap_text.BitmapText())

    self.sanity_row = self:AddChild(Widget("sanity_row"))
    self.sanity_row:SetPosition(SANITY_X, SANITY_Y)
    self.sanity_icon = self.sanity_row:AddChild(Image(GLYPH_ATLAS, "cost_sanity.tex"))
    self.sanity_icon:ScaleToSize(ICON_SIZE, ICON_SIZE)
    self.sanity_text = self.sanity_row:AddChild(bitmap_text.BitmapText())

    self:Hide()
end)

local function LayoutLeftRow(icon, text)
    local text_width = text:GetWidth()

    icon:SetPosition(0, 0)
    text:SetPosition(ICON_SIZE * .5 + ICON_GAP + text_width * .5 + LEFT_TEXT_OFFSET, 0)
end

local function LayoutRightRow(icon, text)
    local text_width = text:GetWidth()

    icon:SetPosition(0, 0)
    text:SetPosition(-ICON_SIZE * .5 - ICON_GAP - text_width * .5 + RIGHT_TEXT_OFFSET, 0)
end

function SkillTreeCostOverlay:SetSkill(prefab, skill_id)
    local cost = skill_cost_display.GetCostDisplay(prefab, skill_id)
    if cost == nil then
        self:Hide()
        return
    end

    local durability_tokens = skill_cost_display.BuildDurabilityTokens(cost)
    local sanity_penalty_tokens = skill_cost_display.BuildSanityPenaltyTokens(cost)
    local sanity_tokens = skill_cost_display.BuildSanityTokens(cost)

    if durability_tokens == nil and sanity_penalty_tokens == nil and sanity_tokens == nil then
        self:Hide()
        return
    end

    if durability_tokens ~= nil then
        self.durability_row:Show()
        self.durability_text:SetTokens(durability_tokens)
        LayoutLeftRow(self.durability_icon, self.durability_text)
    else
        self.durability_row:Hide()
    end

    if sanity_penalty_tokens ~= nil then
        self.penalty_row:Show()
        self.penalty_text:SetTokens(sanity_penalty_tokens)
        LayoutRightRow(self.penalty_icon, self.penalty_text)
    else
        self.penalty_row:Hide()
    end

    if sanity_tokens ~= nil then
        self.sanity_row:Show()
        self.sanity_text:SetTokens(sanity_tokens)
        LayoutRightRow(self.sanity_icon, self.sanity_text)
    else
        self.sanity_row:Hide()
    end

    self:Show()
end

return {
    SkillTreeCostOverlay = SkillTreeCostOverlay,
}
