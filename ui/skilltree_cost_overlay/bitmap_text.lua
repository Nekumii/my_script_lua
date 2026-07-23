-- =============================================================================
-- Bitmap glyph renderer
-- =============================================================================

local Widget = require("widgets/widget")
local Image = require("widgets/image")

local GLYPH_ATLAS = "images/_shared/skilltree_cost_glyphs.xml"
local GLYPH_SIZE = 18
local GLYPH_SPACING = 1
local TIGHT_SPACING = -5

local TIGHT_SUFFIX_TOKENS =
{
    percent = true,
    slash = true,
    s = true,
}

local TOKEN_TO_TEX =
{
    minus = "cost_minus.tex",
    plus = "cost_plus.tex",
    slash = "cost_slash.tex",
    equals = "cost_equals.tex",
    percent = "cost_percent.tex",
    less = "cost_less.tex",
    greater = "cost_greater.tex",
    dot = "cost_dot.tex",
    all = "cost_all.tex",
    s = "cost_s.tex",
    digit_0 = "cost_0.tex",
    digit_1 = "cost_1.tex",
    digit_2 = "cost_2.tex",
    digit_3 = "cost_3.tex",
    digit_4 = "cost_4.tex",
    digit_5 = "cost_5.tex",
    digit_6 = "cost_6.tex",
    digit_7 = "cost_7.tex",
    digit_8 = "cost_8.tex",
    digit_9 = "cost_9.tex",
}

local function IsDigitToken(token)
    return type(token) == "string" and token:sub(1, 6) == "digit_"
end

local function IsTightPair(prev, token)
    if prev == nil or token == nil then
        return false
    end

    if IsDigitToken(prev) and (IsDigitToken(token) or TIGHT_SUFFIX_TOKENS[token]) then
        return true
    end

    if prev == "slash" and token == "s" then
        return true
    end

    return false
end

local function GetGlyphStep(prev, token)
    local spacing = IsTightPair(prev, token) and TIGHT_SPACING or GLYPH_SPACING
    return GLYPH_SIZE + spacing
end

local BitmapText = Class(Widget, function(self, tokens)
    Widget._ctor(self, "bitmap_text")
    self._glyphs = {}
    self:SetTokens(tokens)
end)

local function ClearGlyphs(self)
    for _, glyph in ipairs(self._glyphs) do
        if glyph ~= nil and glyph.Kill ~= nil then
            glyph:Kill()
        end
    end
    self._glyphs = {}
end

function BitmapText:SetTokens(tokens)
    ClearGlyphs(self)

    if tokens == nil or #tokens == 0 then
        self._width = 0
        return
    end

    local x = 0
    local prev = nil

    for _, token in ipairs(tokens) do
        local tex = TOKEN_TO_TEX[token]
        if tex ~= nil then
            if prev ~= nil then
                x = x + GetGlyphStep(prev, token)
            end

            local glyph = self:AddChild(Image(GLYPH_ATLAS, tex))
            glyph:ScaleToSize(GLYPH_SIZE, GLYPH_SIZE)
            glyph:SetPosition(x + GLYPH_SIZE * .5, 0)
            prev = token
            self._glyphs[#self._glyphs + 1] = glyph
        end
    end

    self._width = #self._glyphs > 0 and (x + GLYPH_SIZE) or 0
end

function BitmapText:GetWidth()
    return self._width or 0
end

return {
    BitmapText = BitmapText,
    GLYPH_ATLAS = GLYPH_ATLAS,
    GLYPH_SIZE = GLYPH_SIZE,
}
