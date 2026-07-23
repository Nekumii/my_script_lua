local V = require("skill_effect/waxwell/sovereign/shadow_conjury/variables")
local Factory = require("skill_effect/waxwell/sovereign/shadow_conjury/common")
local ModCompat = require("mod_compatibility")

local M = {}

local function AddConjuryRecipe(env, recipename, fuelcost, skill, opts)
    opts = opts or {}

    local recipeopts =
    {
        builder_skill = skill,
        builder_tag = V.BUILDER_TAG,
        product = opts.product or recipename,
        no_deconstruction = true,
        image = opts.image,
        placer = opts.placer,
        min_spacing = opts.min_spacing,
    }

    env.AddCharacterRecipe(
        recipename,
        { Ingredient("nightmarefuel", fuelcost) },
        TECH.NONE,
        recipeopts
    )
end

function M.Register(env)
    for _, base in ipairs(V.CONJURY_1_BASE_ITEMS) do
        local recipename = Factory.ShadowPrefabName(base)
        AddConjuryRecipe(env, recipename, V.CONJURY_1_FUEL_COST, V.CONJURY_SKILL, {
            image = base .. ".tex",
        })
    end

    if ModCompat.HasTropicalMacheteSupport() and PrefabExists("machete") then
        AddConjuryRecipe(env, Factory.ShadowPrefabName("machete"), V.CONJURY_1_FUEL_COST, V.CONJURY_SKILL, {
            image = "machete.tex",
        })
    end

    for _, base in ipairs(V.CONJURY_2_BASE_ITEMS) do
        local recipename = Factory.ShadowPrefabName(base)
        local opts =
        {
            image = base .. ".tex",
        }

        if base == "campfire" then
            opts.placer = recipename .. "_placer"
            opts.min_spacing = 2
        end

        AddConjuryRecipe(env, recipename, V.CONJURY_2_FUEL_COST, V.CONJURY_SKILL, opts)
    end

    AddConjuryRecipe(env, Factory.ShadowPrefabName(V.CONJURY_CANE_ITEM), V.CONJURY_CANE_FUEL_COST, V.CONJURY_SKILL, {
        image = V.CONJURY_CANE_ITEM .. ".tex",
    })

    AddConjuryRecipe(env, Factory.ShadowPrefabName(V.CONJURY_PANFLUTE_ITEM), V.CONJURY_PANFLUTE_FUEL_COST, V.CONJURY_SKILL, {
        image = V.CONJURY_PANFLUTE_ITEM .. ".tex",
    })
end

return M
