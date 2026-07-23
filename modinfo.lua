name = "Skill Tree"

author = "Kanadui"
version = "1.0"
description = [[
Adds custom character skill trees and experimental reworks.

Current focus:
- Maxwell skill tree overhaul
- Codex Umbra Shadow Stalker summon
]]
forumthread = ""

dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false
all_clients_require_mod=true

api_version = 10  

-- Load after client HUD mods (e.g. Stat Change Display) so ui_fixes can wrap their post-constructs.
priority = 1

icon_atlas = "modicon.xml"
icon = "modicon.tex"

server_filter_tags = {""}

local empty_opts = {{description = "", data = 0}}
local function Title(title, hover)
    return {
        name = title,
        hover = hover or "",
        options = empty_opts,
        default = 0,
    }
end

-- Option order: see #Mods/Skill Tree/AI Memory/mod_settings.txt
-- Off/vanilla/default LEFT — On/mod/custom RIGHT. Do not change `default` when reordering.

configuration_options =
{
    Title("Settings", ""),

    {
        name = "skilltree_cost_overlay",
        label = "Skill Cost Overlay",
        hover = "Show durability and sanity costs on the skill tree info panel for any character with registered cost data.",
        options =
        {
            {
                description = "Off",
                data = "off",
                hover = "Hide skill tree cost badges and skip loading overlay assets.",
            },
            {
                description = "On",
                data = "on",
                hover = "Display cost badges on skill descriptions when cost data exists.",
            },
        },
        default = "on",
    },

    Title("Character Skill Trees", ""),

    {
        name = "enable_waxwell",
        label = "Maxwell",
        hover = "Choose whether Maxwell uses this mod's custom skill tree.",
        options =
        {
            {description = "Off", data = false, hover = "Maxwell will keep the vanilla skill tree."},
            {description = "On", data = true, hover = "Maxwell will use the custom skill tree from this mod."},
        },
        default = true,
    },

    Title("Maxwell", ""),

    {
        name = "waxwell_codex_cost_gate",
        label = "Codex Spell Cost Block",
        hover = "Block codex spell casts when fuel or sanity is insufficient.",
        options =
        {
            {
                description = "Off",
                data = "off",
                hover = "Vanilla behavior — spells are not blocked for low fuel or sanity.",
            },
            {
                description = "On",
                data = "on",
                hover = "Block casts with feedback when fuel or sanity is insufficient.",
            },
        },
        default = "on",
    },
    {
        name = "waxwell_umbra_base_spell_cooldown",
        label = "Shadow Sneak / Prison Cooldown",
        hover = "Adds a cooldown to Shadow Sneak and Shadow Prison after each successful cast.",
        options =
        {
            {
                description = "Off",
                data = "off",
                hover = "Vanilla behavior — no extra cooldown.",
            },
            {
                description = "On",
                data = "on",
                hover = "Adds a 10 second cooldown after each successful cast.",
            },
        },
        default = "on",
    },
    {
        name = "waxwell_reticule_range_lock",
        label = "Reticule Cast Range Lock",
        hover = "Lock the reticule center to the spell cast range edge, or allow free aiming and walk into range.",
        options =
        {
            {
                description = "Off",
                data = "off",
                hover = "Aim the reticule anywhere; Maxwell walks into range before casting.",
            },
            {
                description = "On",
                data = "on",
                hover = "Clamp the reticule center to the cast range (edge matches spell range).",
            },
        },
        default = "on",
    },
    {
        name = "waxwell_dread_tribute_damage_mode",
        label = "Dread Tribute Burn Damage",
        hover = "Flat uses fixed damage per second. Percent scales burn damage from the target's current health.",
        options =
        {
            {
                description = "Flat",
                data = "flat",
                hover = "LV1: 3/s | LV2: 5/s (flat damage).",
            },
            {
                description = "Percent",
                data = "percent",
                hover = "LV1: 2%/s (0.3%/s large/epic) | LV2: 3%/s (0.5%/s large/epic) of target current health.",
            },
        },
        default = "flat",
    },
    {
        name = "waxwell_shadow_stalker_feast_buff_ui",
        label = "Shadow Stalker Feast Buff Icon",
        hover = "Show a feast buff icon above Shadow Stalker while it is active.",
        options =
        {
            {
                description = "Off",
                data = "off",
                hover = "Hide the overhead feast buff indicator.",
            },
            {
                description = "On",
                data = "on",
                hover = "Show an icon above Shadow Stalker for the current feast buff.",
            },
        },
        default = "off",
    },
    {
        name = "waxwell_shadow_reliquary_share_minimap",
        label = "Shadow Reliquary Minimap Icons",
        hover = "When Shared, all players see every Shadow Sunken Chest and winch on the map (refreshed about once per second). When Private, only the skill owner sees their own icons.",
        options =
        {
            {
                description = "Private",
                data = "off",
                hover = "Only the Maxwell who placed the winch sees their chest and winch icons.",
            },
            {
                description = "Shared",
                data = "on",
                hover = "Everyone sees all Shadow Reliquary chest and winch icons on the map.",
            },
        },
        default = "off",
    },
    {
        name = "waxwell_bypass_allegiance_count_lock",
        label = "Bypass Emperor Skill Count Lock",
        hover = "Skip the 14 spent skill points requirement for Emperor allegiance lock. Ancient Fuelweaver kill is still required.",
        options =
        {
            {
                description = "Off",
                data = "off",
                hover = "Vanilla — need 14+ skills spent before Emperor nodes unlock.",
            },
            {
                description = "On",
                data = "on",
                hover = "Count lock opens immediately (unlocked icon). Fuelweaver lock unchanged.",
            },
        },
        default = "off",
    },

    Title("Debug", ""),

    {
        name = "debug_mode",
        label = "Debug Mode",
        hover = "Enable skill info HUD, console debug commands, skill_test overrides, and related debug tooling.",
        options =
        {
            {
                description = "Off",
                data = "off",
                hover = "Disable debug HUD, console commands, skill_test, and skill info updates.",
            },
            {
                description = "On",
                data = "on",
                hover = "Enable debug tooling for development and testing.",
            },
        },
        default = "off",
    },
}
