local EPHEMERAL_LIFETIME = 3 * TUNING.SEG_TIME
local EPHEMERAL_CANE_LIFETIME = TUNING.TOTAL_DAY_TIME / 2

-- 100% dark tint on item prefabs (0% brightness).
local SHADOW_TINT =
{
    r = 0,
    g = 0,
    b = 0,
    a = 1,
}

-- 95% dark tint on fire FX (5% brightness).
local FIRE_TINT =
{
    r = .05,
    g = .05,
    b = .05,
    a = 1,
}

-- 90% dark tint on inventory / crafting UI icons (10% brightness).
local UI_ICON_TINT =
{
    r = .1,
    g = .1,
    b = .1,
    a = 1,
}

local CONJURY_1_FUEL_COST = 2
local CONJURY_2_FUEL_COST = 4
local CONJURY_CANE_FUEL_COST = 6
local CONJURY_PANFLUTE_FUEL_COST = 8

local CONJURY_SKILL = "waxwell_shadow_conjury"

local BUILDER_TAG = "shadowmagic"

local CONJURY_1_BASE_ITEMS =
{
    "axe",
    "pickaxe",
    "shovel",
    "pitchfork",
    "razor",
    "farm_hoe",
    "torch",
}

local CONJURY_1_MOD_ITEMS =
{
    machete = true,
}

local CONJURY_2_BASE_ITEMS =
{
    "campfire",
    "bugnet",
    "fishingrod",
    "hammer",
    "trap",
    "birdtrap",
    "wateringcan",
    "umbrella",
}

local CONJURY_CANE_ITEM = "cane"
local CONJURY_PANFLUTE_ITEM = "panflute"

local SHADOW_DISPLAY_NAMES =
{
    axe = "Shadow Axe",
    pickaxe = "Shadow Pickaxe",
    shovel = "Shadow Shovel",
    pitchfork = "Shadow Pitchfork",
    razor = "Shadow Razor",
    farm_hoe = "Shadow Garden Hoe",
    torch = "Shadow Torch",
    machete = "Shadow Machete",
    campfire = "Shadow Campfire",
    bugnet = "Shadow Bug Net",
    cane = "Shadow Cane",
    fishingrod = "Shadow Fishing Rod",
    hammer = "Shadow Hammer",
    trap = "Shadow Trap",
    birdtrap = "Shadow Bird Trap",
    wateringcan = "Shadow Watering Can",
    umbrella = "Shadow Umbrella",
    panflute = "Shadow Pan Flute",
}

return {
    EPHEMERAL_LIFETIME = EPHEMERAL_LIFETIME,
    EPHEMERAL_CANE_LIFETIME = EPHEMERAL_CANE_LIFETIME,
    SHADOW_TINT = SHADOW_TINT,
    FIRE_TINT = FIRE_TINT,
    UI_ICON_TINT = UI_ICON_TINT,
    CONJURY_1_FUEL_COST = CONJURY_1_FUEL_COST,
    CONJURY_2_FUEL_COST = CONJURY_2_FUEL_COST,
    CONJURY_CANE_FUEL_COST = CONJURY_CANE_FUEL_COST,
    CONJURY_PANFLUTE_FUEL_COST = CONJURY_PANFLUTE_FUEL_COST,
    CONJURY_SKILL = CONJURY_SKILL,
    BUILDER_TAG = BUILDER_TAG,
    CONJURY_1_BASE_ITEMS = CONJURY_1_BASE_ITEMS,
    CONJURY_1_MOD_ITEMS = CONJURY_1_MOD_ITEMS,
    CONJURY_2_BASE_ITEMS = CONJURY_2_BASE_ITEMS,
    CONJURY_CANE_ITEM = CONJURY_CANE_ITEM,
    CONJURY_PANFLUTE_ITEM = CONJURY_PANFLUTE_ITEM,
    SHADOW_DISPLAY_NAMES = SHADOW_DISPLAY_NAMES,
}
