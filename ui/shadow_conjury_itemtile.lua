local V = require("skill_effect/waxwell/sovereign/shadow_conjury/variables")

local SHADOW_TAG = "waxwell_shadow_ephemeral"
local SHADOW_PRODUCT_PREFIX = "waxwell_shadow_"
local TINT = V.UI_ICON_TINT

local function IsShadowConjuryPrefab(prefab)
    return prefab ~= nil and string.sub(prefab, 1, #SHADOW_PRODUCT_PREFIX) == SHADOW_PRODUCT_PREFIX
end

local function IsShadowConjuryItem(item)
    return item ~= nil and (item:HasTag(SHADOW_TAG) or IsShadowConjuryPrefab(item.prefab))
end

local function IsShadowConjuryRecipe(recipe)
    if recipe == nil then
        return false
    end
    return IsShadowConjuryPrefab(recipe.product) or IsShadowConjuryPrefab(recipe.name)
end

local function ApplyUiShadowTint(image)
    if image == nil then
        return
    end

    image:SetTint(TINT.r, TINT.g, TINT.b, TINT.a)

    if image.layers ~= nil then
        for _, layer in ipairs(image.layers) do
            if layer.SetTint ~= nil then
                layer:SetTint(TINT.r, TINT.g, TINT.b, TINT.a)
            end
        end
    end

    if image.children ~= nil then
        for _, child in ipairs(image.children) do
            ApplyUiShadowTint(child)
        end
    end
end

local function TintItemTileImage(itemtile)
    if not IsShadowConjuryItem(itemtile.item) then
        return
    end

    ApplyUiShadowTint(itemtile.image)
end

local function RegisterItemTileHooks(itemtile)
    TintItemTileImage(itemtile)

    if itemtile.item == nil then
        return
    end

    itemtile.inst:ListenForEvent("imagechange", function()
        TintItemTileImage(itemtile)
    end, itemtile.item)

    -- Stackable items only; non-stackable craft bounce uses ItemTile.sSetImageFromItem below.
    itemtile.inst:ListenForEvent("stacksizechange", function(invitem, data)
        if data == nil or data.src_pos == nil or not IsShadowConjuryItem(invitem) then
            return
        end

        if itemtile.movinganim ~= nil then
            ApplyUiShadowTint(itemtile.movinganim)
        end
    end, itemtile.item)
end

AddClassPostConstruct("widgets/itemtile", RegisterItemTileHooks)

AddClassPostConstruct("widgets/recipetile", function(self)
    local old_set_recipe = self.SetRecipe

    function self:SetRecipe(recipe)
        old_set_recipe(self, recipe)
        if IsShadowConjuryRecipe(recipe) then
            ApplyUiShadowTint(self.img)
        end
    end
end)

local ItemTile = require("widgets/itemtile")
local old_set_image_from_item = ItemTile.sSetImageFromItem

ItemTile.sSetImageFromItem = function(im, item)
    im = old_set_image_from_item(im, item)
    if IsShadowConjuryItem(item) then
        ApplyUiShadowTint(im)
    end
    return im
end

local RecipeTile = require("widgets/recipetile")
local old_set_image_from_recipe = RecipeTile.sSetImageFromRecipe

RecipeTile.sSetImageFromRecipe = function(im, recipe, skin_name, r, g, b)
    old_set_image_from_recipe(im, recipe, skin_name, r, g, b)
    if IsShadowConjuryRecipe(recipe) then
        ApplyUiShadowTint(im)
    end
end
