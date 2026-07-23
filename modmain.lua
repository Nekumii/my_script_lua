GLOBAL.setmetatable(env,{__index=function(t,k) return GLOBAL.rawget(GLOBAL,k) end})


--//////////////////// Prefab Files
PrefabFiles = {
    "reticule_skilltree",
    "waxwell/shadow_stalker",
    "waxwell/shadow_stalker_fossilspike",
    "waxwell/shadow_stalker_fossilspike2",
    "waxwell/waxwell_shadow_firefly",
    "waxwell/waxwell_shadow_firefly_explodefx",
    "waxwell/shadow_lanternbearer",
    "waxwell/shadow_marksman",
    "waxwell/shadow_marksman_hitfx",
    "waxwell/shadow_marksman_darkfx",
    "waxwell/shadow_marksman_honey_trail",
    "waxwell/eclipse_ground_chunks_breaking",
    "waxwell/eclipse_burntground",
    "waxwell/umbral_rift_portal",
    "waxwell/umbral_rift_mark",
    "waxwell/domainexpansion_field",
    "waxwell/domain_expansion_barrier_pillar",
    "waxwell/domain_expansion_spike_fx",
    "waxwell/waxwell_fissure_eruption_sinkhole",
    "waxwell/waxwell_fissure_eruption_dust_fx",
    "waxwell/waxwell_shadow_reliquary_base",
    "waxwell/waxwell_shadow_sunken_chest",
    "waxwell/waxwell_shadow_torchfire",
    "waxwell/waxwell_shadow_conjury_items",
    "waxwell/waxwell_dread_tribute_burnfx",
    "waxwell/waxwell_dread_tribute_explodefx",
    "waxwell/waxwell_mom_shield_fx",
}


--//////////////////// Skilltree Config
local ModConfig = require("mod_config")
ModConfig.SetModName(modname)
local ENABLE_WAXWELL = ModConfig.IsWaxwellEnabled()


--//////////////////// Assets
Assets = {}

local function AddAssets(assetlist)
    for _, asset in ipairs(assetlist) do
        table.insert(Assets, asset)
    end
end

if ENABLE_WAXWELL then
    AddAssets({
        Asset("IMAGE", "images/waxwell/waxwell_background.tex"),
        Asset("ATLAS", "images/waxwell/waxwell_background.xml"),
        Asset("IMAGE", "images/waxwell/waxwell_skill_icon.tex"),
        Asset("ATLAS", "images/waxwell/waxwell_skill_icon.xml"),
        Asset("IMAGE", "images/waxwell/waxwell_codex_icon.tex"),
        Asset("ATLAS", "images/waxwell/waxwell_codex_icon.xml"),
        Asset("IMAGE", "images/waxwell/waxwell_minimap_icon.tex"),
        Asset("ATLAS", "images/waxwell/waxwell_minimap_icon.xml"),
    })
    AddMinimapAtlas("images/waxwell/waxwell_minimap_icon.xml")
end


--//////////////////// Skilltree String
STRINGS.SKILLTREE = STRINGS.SKILLTREE or {}
local SKILLTREE = STRINGS.SKILLTREE
SKILLTREE.PANELS = SKILLTREE.PANELS or {}
SKILLTREE.NAMES = SKILLTREE.NAMES or {}
SKILLTREE.desc = SKILLTREE.desc or {}
STRINGS.CHARACTERS.GENERIC.ACTIONFAIL.CASTAOE.HASPET = STRINGS.CHARACTERS.GENERIC.ACTIONFAIL.BUILD.HASPET


--//////////////////// Skill Info
require("skill_info/skill_info_allegiance_lock")
if ENABLE_WAXWELL then
    require("skill_info/skill_info_waxwell")
end


--//////////////////// Skilltree Registration
local skilltree_defs = require("prefabs/skilltree_defs")

MOD_SKILLTREE_PREFABS = {}

local function RegisterModSkillTreePrefab(prefab)
    if prefab ~= nil then
        MOD_SKILLTREE_PREFABS[prefab] = true
    end
end

-- Maxwell
if ENABLE_WAXWELL then
    local BuildSkillsData_Waxwell = require("skilltree/skilltree_waxwell")
    if BuildSkillsData_Waxwell then
        local data = BuildSkillsData_Waxwell(skilltree_defs.FN)
        if data then
            skilltree_defs.CreateSkillTreeFor("waxwell", data.SKILLS)
            skilltree_defs.SKILLTREE_ORDERS["waxwell"] = data.ORDERS
            if data.BACKGROUND_SETTINGS ~= nil then
                skilltree_defs.SKILLTREE_METAINFO["waxwell"].BACKGROUND_SETTINGS = data.BACKGROUND_SETTINGS
            end
            RegisterModSkillTreePrefab("waxwell")
        end
    end
end


--//////////////////// Background and Icon Overrides
-- Overrides the background image
local old_get_bg = GetSkilltreeBG
function GLOBAL.GetSkilltreeBG(imagename, ...)
    if ENABLE_WAXWELL and imagename ~= nil and imagename:find("waxwell") then
        return MODROOT.."images/waxwell/waxwell_background.xml"
    else
        return old_get_bg(imagename, ...)
    end
end
-- Overrides the skill icon atlas
local old_get_icon = GetSkilltreeIconAtlas
function GLOBAL.GetSkilltreeIconAtlas(imagename, ...)
    if ENABLE_WAXWELL and imagename ~= nil and imagename:find("waxwell") then
        return MODROOT.."images/waxwell/waxwell_skill_icon.xml"
    else
        return old_get_icon(imagename, ...)
    end
end


--//////////////////// Skill Tree Cost Overlay (all characters)
if not GLOBAL.TheNet:IsDedicated() then
    modimport("scripts/ui/skilltree_cost_overlay/init.lua")
end

--//////////////////// Skill Effects Registration
-- Spell Wheel (load before skill effects that lazy-require wheel/refresh)
modimport("scripts/wheel/init.lua")

if ENABLE_WAXWELL then
    local WaxwellSkillEffects = require("skill_effect/waxwell/init")
    WaxwellSkillEffects.Register(env)
end


--//////////////////// Require
-- UI Fixes
modimport("scripts/ui/ui_fixes.lua")
if not GLOBAL.TheNet:IsDedicated() then
    modimport("scripts/system/player_classified_sanity_guard.lua")
end
if ENABLE_WAXWELL then
    modimport("scripts/ui/shadow_conjury_itemtile.lua")
end
-- Debug Mode
require("debug/init").Register(env)
-- Waxwell
if ENABLE_WAXWELL then
    require("string/waxwell/string_waxwell")
    require("string/waxwell/string_conjury").Register()
    modimport("scripts/reticule/client_hooks.lua")
    modimport("scripts/skill_effect/waxwell/_shared/shadow_level.lua")
end
