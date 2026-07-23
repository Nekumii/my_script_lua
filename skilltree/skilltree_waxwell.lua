--[[
=============================================================================
Waxwell Skill Tree Position Reference (4-quadrant layout)
=============================================================================
ไฟล์นี้ใช้ `pos = {x, y}` ในแต่ละ skill node

Engine (skilltreebuilder.lua):
  - ตำแหน่งจริงบนจอ = { x, y - 30 }
  - ORDERS = ตำแหน่งชื่อกลุ่มเท่านั้น ไม่เลื่อนไอคอนสกิล

Quadrant layout (พื้นที่ 4 ส่วนเท่ากัน):
  บนซ้าย = Puppeteer | บนขวา = Sovereign
  ล่างซ้าย = Umbra     | ล่างขวา = Emperor

ชื่อกลุ่ม (ORDERS):
  ซ้าย  x = -130  (Puppeteer + Umbra แนวตั้งตรงกัน)
  ขวา   x =  130  (Sovereign + Emperor แนวตั้งตรงกัน)
  บน    y =  215  (Puppeteer + Sovereign แนวนอนตรงกัน)
  ล่าง  y =   95  (Umbra + Emperor แนวนอนตรงกัน)

Grid step: x ทีละ 50 | y ทีละ 50

-----------------------------------------------------------------------------
คอลัมน์ X
-----------------------------------------------------------------------------
  ซ้าย: -230  -180  -130(root)  -80  -30
  ขวา:   30    80   130(root)  180  230

-----------------------------------------------------------------------------
แถว Y ต่อ branch
-----------------------------------------------------------------------------
  Puppeteer + Sovereign (บน): แถวบน 180 | แถวล่าง 130
  Umbra + Emperor (ล่าง)    : แถวบน  60 | แถวล่าง  10
  Locks (Emperor กลาง)      : y = 35 และ 0 ที่ x = 130

ศูนย์กลางกริดแต่ละกลุ่ม:
  Puppeteer / Umbra   -> x = -130
  Sovereign / Emperor -> x =  130
  บน (Puppeteer/Sovereign) -> y ศูนย์กลาง ~155
  ล่าง (Umbra/Emperor)     -> y ศูนย์กลาง ~35

-----------------------------------------------------------------------------
แผนที่สกิล -> pos
-----------------------------------------------------------------------------
  PUPPETEER:  x {-230,-180,-130,-80,-30}  y {180,130}
  UMBRA:      x {-230,-180,-130,-80,-30}  y {60,10}
  SOVEREIGN:  x {30,80,130,180,230}       y {180,130}
  EMPEROR:    x {30,230} skills + locks {130,35/0}  y {60,10}
              Shadow Stalker {30,60} | Imperial Regalia {230,60}
              Domain Expansion {30,10} | Empty1 {230,10}
=============================================================================
]]

local ORDERS =
{
    {"waxwell_puppeteer", {-130, 215}},
    {"waxwell_umbra",     {-130,  95}},
    {"waxwell_sovereign", { 130, 215}},
    {"waxwell_emperor",   { 130,  95}},
}

local ModConfig = require("mod_config")

local function IsSkillAllBypassLocks()
    local player = rawget(_G, "ThePlayer")
    if player == nil then
        return false
    end

    local debug = require("debug/init")
    return debug.IsSkillAllEnabled(player)
end

local function IsAllegianceCountLockOpen()
    if ModConfig.IsWaxwellBypassAllegianceCountLock() then
        return true
    end

    if IsSkillAllBypassLocks() then
        return true
    end

    return false
end

local function IsShadowAllegianceLockOpen(readonly)
    if IsSkillAllBypassLocks() then
        return true
    end

    if TheGenericKV:GetKV("fuelweaver_killed") == "1" then
        return true
    end

    if readonly then
        return "question"
    end

    return false
end

local function BuildSkillsData(SkillTreeFns)
    local skills = {
        -- Group 1 : Puppeteer
        waxwell_fragmented_mind = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_FRAGMENTED_MIND,
            desc = STRINGS.SKILLTREE.desc.waxwell_fragmented_mind,
            icon = "waxwell_fragmented_mind",
            pos = {-130, 180},
            group = "waxwell_puppeteer",
            tags = {"waxwell_fragmented_mind"},
            onactivate = function(inst, fromload)
                inst:AddTag("fragmented_mind_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("fragmented_mind_active")
            end,
            root = true,
            connects = {
                "waxwell_expanded_dominion",
                "waxwell_tireless_servant_1",
                "waxwell_lethal_apparition_1",
                "waxwell_shadow_lanternbearer_1",
                "waxwell_shadow_marksman_1"
            }
        },
        waxwell_expanded_dominion = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_EXPANDED_DOMINION,
            desc = STRINGS.SKILLTREE.desc.waxwell_expanded_dominion,
            icon = "waxwell_expanded_dominion",
            pos = {-130, 130},
            group = "waxwell_puppeteer",
            tags = {"waxwell_expanded_dominion"},
            onactivate = function(inst, fromload)
                inst:AddTag("expanded_dominion_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("expanded_dominion_active")
            end
        },
        waxwell_tireless_servant_1 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_TIRELESS_SERVANT_1,
            desc = STRINGS.SKILLTREE.desc.waxwell_tireless_servant_1,
            icon = "waxwell_tireless_servant_1",
            pos = {-180, 180},
            group = "waxwell_puppeteer",
            tags = {"waxwell_tireless_servant_1"},
            onactivate = function(inst, fromload)
                inst:AddTag("tireless_servant_1_active")
            end,
			ondeactivate = function(inst, fromload)
                inst:RemoveTag("tireless_servant_1_active")
            end,
            connects = {
                "waxwell_tireless_servant_2"
            }
        },
        waxwell_tireless_servant_2 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_TIRELESS_SERVANT_2,
            desc = STRINGS.SKILLTREE.desc.waxwell_tireless_servant_2,
            icon = "waxwell_tireless_servant_2",
            pos = {-230, 180},
            group = "waxwell_puppeteer",
            tags = {"waxwell_tireless_servant_2"},
            onactivate = function(inst, fromload)
                inst:AddTag("tireless_servant_2_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("tireless_servant_2_active")
            end
        },
        waxwell_lethal_apparition_1 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_LETHAL_APPARITION_1,
            desc = STRINGS.SKILLTREE.desc.waxwell_lethal_apparition_1,
            icon = "waxwell_lethal_apparition_1",
            pos = {-80, 180},
            group = "waxwell_puppeteer",
            tags = {"waxwell_lethal_apparition_1"},
            onactivate = function(inst, fromload)
                inst:AddTag("lethal_apparition_1_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("lethal_apparition_1_active")
            end,
            connects = {
                "waxwell_lethal_apparition_2"
            }
        },
        waxwell_lethal_apparition_2 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_LETHAL_APPARITION_2,
            desc = STRINGS.SKILLTREE.desc.waxwell_lethal_apparition_2,
            icon = "waxwell_lethal_apparition_2",
            pos = {-30, 180},
            group = "waxwell_puppeteer",
            tags = {"waxwell_lethal_apparition_2"},
            onactivate = function(inst, fromload)
                inst:AddTag("lethal_apparition_2_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("lethal_apparition_2_active")
            end
        },
        waxwell_shadow_lanternbearer_1 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_SHADOW_LANTERNBEARER_1,
            desc = STRINGS.SKILLTREE.desc.waxwell_shadow_lanternbearer_1,
            icon = "waxwell_shadow_lanternbearer_1",
            pos = {-180, 130},
            group = "waxwell_puppeteer",
            tags = {"waxwell_shadow_lanternbearer_1"},
            onactivate = function(inst, fromload)
                inst:AddTag("shadow_lanternbearer_1_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("shadow_lanternbearer_1_active")
            end,
            connects = {
                "waxwell_shadow_lanternbearer_2"
            }
        },
        waxwell_shadow_lanternbearer_2 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_SHADOW_LANTERNBEARER_2,
            desc = STRINGS.SKILLTREE.desc.waxwell_shadow_lanternbearer_2,
            icon = "waxwell_shadow_lanternbearer_2",
            pos = {-230, 130},
            group = "waxwell_puppeteer",
            tags = {"waxwell_shadow_lanternbearer_2"},
            onactivate = function(inst, fromload)
                inst:AddTag("shadow_lanternbearer_2_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("shadow_lanternbearer_2_active")
            end
        },
        waxwell_shadow_marksman_1 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_SHADOW_MARKSMAN_1,
            desc = STRINGS.SKILLTREE.desc.waxwell_shadow_marksman_1,
            icon = "waxwell_shadow_marksman_1",
            pos = {-80, 130},
            group = "waxwell_puppeteer",
            tags = {"waxwell_shadow_marksman_1"},
            onactivate = function(inst, fromload)
                inst:AddTag("shadow_marksman_1_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("shadow_marksman_1_active")
            end,
            connects = {
                "waxwell_shadow_marksman_2"
            }
        },
        waxwell_shadow_marksman_2 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_SHADOW_MARKSMAN_2,
            desc = STRINGS.SKILLTREE.desc.waxwell_shadow_marksman_2,
            icon = "waxwell_shadow_marksman_2",
            pos = {-30, 130},
            group = "waxwell_puppeteer",
            tags = {"waxwell_shadow_marksman_2"},
            onactivate = function(inst, fromload)
                inst:AddTag("shadow_marksman_2_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("shadow_marksman_2_active")
            end
        },
        -- Group 2 : Umbra
        waxwell_dark_scholar = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_DARK_SCHOLAR,
            desc = STRINGS.SKILLTREE.desc.waxwell_dark_scholar,
            icon = "waxwell_dark_scholar",
            pos = {-130, 60},
            group = "waxwell_umbra",
            tags = {"waxwell_dark_scholar"},
            onactivate = function(inst, fromload)
                inst:AddTag("dark_scholar_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("dark_scholar_active")
            end,
            root = true,
            connects = {
                "waxwell_measured_invocation",
                "waxwell_lingering_dread_1",
                "waxwell_abyssal_binding_1",
                "waxwell_umbral_rift_1",
                "waxwell_eclipse_fall_1"
            }
        },
        waxwell_measured_invocation = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_MEASURED_INVOCATION,
            desc = STRINGS.SKILLTREE.desc.waxwell_measured_invocation,
            icon = "waxwell_measured_invocation",
            pos = {-130, 10},
            group = "waxwell_umbra",
            tags = {"waxwell_measured_invocation"},
            onactivate = function(inst, fromload)
                inst:AddTag("measured_invocation_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("measured_invocation_active")
            end
        },
        waxwell_lingering_dread_1 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_LINGERING_DREAD_1,
            desc = STRINGS.SKILLTREE.desc.waxwell_lingering_dread_1,
            icon = "waxwell_lingering_dread_1",
            pos = {-180, 60},
            group = "waxwell_umbra",
            tags = {"waxwell_lingering_dread_1"},
            onactivate = function(inst, fromload)
                inst:AddTag("lingering_dread_1_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("lingering_dread_1_active")
            end,
            connects = {
                "waxwell_lingering_dread_2"
            }
        },
        waxwell_lingering_dread_2 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_LINGERING_DREAD_2,
            desc = STRINGS.SKILLTREE.desc.waxwell_lingering_dread_2,
            icon = "waxwell_lingering_dread_2",
            pos = {-230, 60},
            group = "waxwell_umbra",
            tags = {"waxwell_lingering_dread_2"},
            onactivate = function(inst, fromload)
                inst:AddTag("lingering_dread_2_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("lingering_dread_2_active")
            end
        },
        waxwell_abyssal_binding_1 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_ABYSSAL_BINDING_1,
            desc = STRINGS.SKILLTREE.desc.waxwell_abyssal_binding_1,
            icon = "waxwell_abyssal_binding_1",
            pos = {-80, 60},
            group = "waxwell_umbra",
            tags = {"waxwell_abyssal_binding_1"},
            onactivate = function(inst, fromload)
                inst:AddTag("abyssal_binding_1_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("abyssal_binding_1_active")
            end,
            connects = {
                "waxwell_abyssal_binding_2"
            }
        },
        waxwell_abyssal_binding_2 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_ABYSSAL_BINDING_2,
            desc = STRINGS.SKILLTREE.desc.waxwell_abyssal_binding_2,
            icon = "waxwell_abyssal_binding_2",
            pos = {-30, 60},
            group = "waxwell_umbra",
            tags = {"waxwell_abyssal_binding_2"},
            onactivate = function(inst, fromload)
                inst:AddTag("abyssal_binding_2_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("abyssal_binding_2_active")
            end
        },
        waxwell_umbral_rift_1 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_UMBRAL_RIFT_1,
            desc = STRINGS.SKILLTREE.desc.waxwell_umbral_rift_1,
            icon = "waxwell_umbral_rift_1",
            pos = {-180, 10},
            group = "waxwell_umbra",
            tags = {"waxwell_umbral_rift_1"},
            onactivate = function(inst, fromload)
                inst:AddTag("umbral_rift_1_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("umbral_rift_1_active")
            end,
            connects = {
                "waxwell_umbral_rift_2"
            }
        },
        waxwell_umbral_rift_2 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_UMBRAL_RIFT_2,
            desc = STRINGS.SKILLTREE.desc.waxwell_umbral_rift_2,
            icon = "waxwell_umbral_rift_2",
            pos = {-230, 10},
            group = "waxwell_umbra",
            tags = {"waxwell_umbral_rift_2"},
            onactivate = function(inst, fromload)
                inst:AddTag("umbral_rift_2_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("umbral_rift_2_active")
            end
        },
        waxwell_eclipse_fall_1 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_ECLIPSE_FALL_1,
            desc = STRINGS.SKILLTREE.desc.waxwell_eclipse_fall_1,
            icon = "waxwell_eclipse_fall_1",
            pos = {-80, 10},
            group = "waxwell_umbra",
            tags = {"waxwell_eclipse_fall_1"},
            onactivate = function(inst, fromload)
                inst:AddTag("eclipse_fall_1_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("eclipse_fall_1_active")
            end,
            connects = {
                "waxwell_eclipse_fall_2"
            }
        },
        waxwell_eclipse_fall_2 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_ECLIPSE_FALL_2,
            desc = STRINGS.SKILLTREE.desc.waxwell_eclipse_fall_2,
            icon = "waxwell_eclipse_fall_2",
            pos = {-30, 10},
            group = "waxwell_umbra",
            tags = {"waxwell_eclipse_fall_2"},
            onactivate = function(inst, fromload)
                inst:AddTag("eclipse_fall_2_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("eclipse_fall_2_active")
            end
        },
        -- Group 3 : Sovereign
        waxwell_royal_composure = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_ROYAL_COMPOSURE,
            desc = STRINGS.SKILLTREE.desc.waxwell_royal_composure,
            icon = "waxwell_royal_composure",
            pos = {130, 180},
            group = "waxwell_sovereign",
            tags = {"waxwell_royal_composure"},
            onactivate = function(inst, fromload)
                inst:AddTag("royal_composure_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("royal_composure_active")
            end,
            root = true,
            connects = {
                "waxwell_shadow_conjury",
                "waxwell_shadow_gluttony",
                "waxwell_nightmare_dominion",
                "waxwell_mind_over_matter",
                "waxwell_minds_recompense"
            }
        },
        waxwell_shadow_conjury = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_SHADOW_CONJURY,
            desc = STRINGS.SKILLTREE.desc.waxwell_shadow_conjury,
            icon = "waxwell_shadow_conjury",
            pos = {80, 130},
            group = "waxwell_sovereign",
            tags = {"waxwell_shadow_conjury"},
            onactivate = function(inst, fromload)
                inst:AddTag("shadow_conjury_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("shadow_conjury_active")
            end
        },
        waxwell_shadow_gluttony = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_SHADOW_GLUTTONY,
            desc = STRINGS.SKILLTREE.desc.waxwell_shadow_gluttony,
            icon = "waxwell_shadow_gluttony",
            pos = {130, 130},
            group = "waxwell_sovereign",
            tags = {"waxwell_shadow_gluttony"},
            onactivate = function(inst, fromload)
                inst:AddTag("shadow_gluttony_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("shadow_gluttony_active")
            end
        },
        waxwell_nightmare_dominion = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_NIGHTMARE_DOMINION,
            desc = STRINGS.SKILLTREE.desc.waxwell_nightmare_dominion,
            icon = "waxwell_nightmare_dominion",
            pos = {80, 180},
            group = "waxwell_sovereign",
            tags = {"waxwell_nightmare_dominion"},
            onactivate = function(inst, fromload)
                inst:AddTag("nightmare_dominion_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("nightmare_dominion_active")
            end,
            connects = {
                "waxwell_dread_tribute_1"
            }
        },
        waxwell_dread_tribute_1 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_DREAD_TRIBUTE_1,
            desc = STRINGS.SKILLTREE.desc.waxwell_dread_tribute_1,
            icon = "waxwell_dread_tribute_1",
            pos = {30, 180},
            group = "waxwell_sovereign",
            tags = {"waxwell_dread_tribute_1"},
            onactivate = function(inst, fromload)
                inst:AddTag("dread_tribute_1_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("dread_tribute_1_active")
            end,
            connects = {
                "waxwell_dread_tribute_2"
            }
        },
        waxwell_dread_tribute_2 = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_DREAD_TRIBUTE_2,
            desc = STRINGS.SKILLTREE.desc.waxwell_dread_tribute_2,
            icon = "waxwell_dread_tribute_2",
            pos = {30, 130},
            group = "waxwell_sovereign",
            tags = {"waxwell_dread_tribute_2"},
            onactivate = function(inst, fromload)
                inst:AddTag("dread_tribute_2_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("dread_tribute_2_active")
            end
        },
        waxwell_mind_over_matter = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_MIND_OVER_MATTER,
            desc = STRINGS.SKILLTREE.desc.waxwell_mind_over_matter,
            icon = "waxwell_mind_over_matter",
            pos = {180, 180},
            group = "waxwell_sovereign",
            tags = {"waxwell_mind_over_matter"},
            onactivate = function(inst, fromload)
                inst:AddTag("mind_over_matter_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("mind_over_matter_active")
            end,
            connects = {
                "waxwell_chaos_inoculation"
            }
        },
        waxwell_chaos_inoculation = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_CHAOS_INOCULATION,
            desc = STRINGS.SKILLTREE.desc.waxwell_chaos_inoculation,
            icon = "waxwell_chaos_inoculation",
            pos = {230, 180},
            group = "waxwell_sovereign",
            tags = {"waxwell_chaos_inoculation"},
            onactivate = function(inst, fromload)
                inst:AddTag("chaos_inoculation_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("chaos_inoculation_active")
            end
        },
        waxwell_minds_recompense = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_MINDS_RECOMPENSE,
            desc = STRINGS.SKILLTREE.desc.waxwell_minds_recompense,
            icon = "waxwell_minds_recompense",
            pos = {180, 130},
            group = "waxwell_sovereign",
            tags = {"waxwell_minds_recompense"},
            onactivate = function(inst, fromload)
                inst:AddTag("sanity_recoup_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("sanity_recoup_active")
            end,
            connects = {
                "waxwell_inner_incarnate"
            }
        },
        waxwell_inner_incarnate = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_INNER_INCARNATE,
            desc = STRINGS.SKILLTREE.desc.waxwell_inner_incarnate,
            icon = "waxwell_inner_incarnate",
            pos = {230, 130},
            group = "waxwell_sovereign",
            tags = {"waxwell_inner_incarnate"},
            onactivate = function(inst, fromload)
                inst:AddTag("inner_incarnate_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("inner_incarnate_active")
            end
        },
        -- Group 4 : Emperor
        waxwell_shadow_stalker = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_SHADOW_STALKER,
            desc = STRINGS.SKILLTREE.desc.waxwell_shadow_stalker,
            icon = "waxwell_shadow_stalker",
            pos = {30, 60},
            group = "waxwell_emperor",
            tags = {"waxwell_shadow_stalker"},
            locks = {"allegiance_lock_count_14", "allegiance_lock_shadow"},
            onactivate = function(inst, fromload)
                inst:AddTag("shadow_stalker_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("shadow_stalker_active")
            end
        },
        waxwell_domain_expansion = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_DOMAIN_EXPANSION,
            desc = STRINGS.SKILLTREE.desc.waxwell_domain_expansion,
            icon = "waxwell_domain_expansion",
            pos = {230, 60},
            group = "waxwell_emperor",
            tags = {"waxwell_domain_expansion"},
            locks = {"allegiance_lock_count_14", "allegiance_lock_shadow"},
            onactivate = function(inst, fromload)
                inst:AddTag("domain_expansion_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("domain_expansion_active")
            end
        },
        waxwell_fissure_eruption = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_FISSURE_ERUPTION,
            desc = STRINGS.SKILLTREE.desc.waxwell_fissure_eruption,
            icon = "waxwell_fissure_eruption",
            pos = {30, 10},
            group = "waxwell_emperor",
            tags = {"waxwell_fissure_eruption"},
            locks = {"allegiance_lock_count_14", "allegiance_lock_shadow"},
            onactivate = function(inst, fromload)
                inst:AddTag("fissure_eruption_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("fissure_eruption_active")
            end
        },
        waxwell_shadow_reliquary = {
            title = STRINGS.SKILLTREE.NAMES.WAXWELL_SHADOW_RELIQUARY,
            desc = STRINGS.SKILLTREE.desc.waxwell_shadow_reliquary,
            icon = "waxwell_shadow_reliquary",
            pos = {230, 10},
            group = "waxwell_emperor",
            tags = {"waxwell_shadow_reliquary"},
            locks = {"allegiance_lock_count_14", "allegiance_lock_shadow"},
            onactivate = function(inst, fromload)
                inst:AddTag("shadow_reliquary_active")
            end,
            ondeactivate = function(inst, fromload)
                inst:RemoveTag("shadow_reliquary_active")
            end
        },
        -- Allegiance Lock
		allegiance_lock_count_14 = {
            desc = STRINGS.SKILLTREE.desc.allegiance_lock_count_14,
            pos = {130, 0},
            group = "allegiance_lock",
            tags = {"allegiance_lock_count_14"},
            lock_open = function(prefabname, activatedskills, readonly)
                if IsAllegianceCountLockOpen() then
                    return true
                end

                return SkillTreeFns.CountSkills(prefabname, activatedskills) >= 14
            end,
            root = true,
            connects = {
                "waxwell_shadow_stalker",
                "waxwell_domain_expansion",
                "waxwell_fissure_eruption",
                "waxwell_shadow_reliquary"
            }
        },
		allegiance_lock_shadow = {
            desc = STRINGS.SKILLTREE.desc.allegiance_lock_shadow,
            pos = {130, 35},
            group = "allegiance_lock",
            tags = {"allegiance_lock_shadow"},
            lock_open = function(prefabname, activatedskills, readonly)
                return IsShadowAllegianceLockOpen(readonly)
            end,
            root = true,
            connects = {
                "waxwell_shadow_stalker",
                "waxwell_domain_expansion",
                "waxwell_fissure_eruption",
                "waxwell_shadow_reliquary"
            }
        },
    }
	return {
		SKILLS = skills,
		ORDERS = ORDERS,
		-- หน้าเลือกตัว: สีจาก art ตรงๆ (tint_bright=false) / ในเกม: BLACK tint ตาม vanilla
		BACKGROUND_SETTINGS = {
			tint_bright = false,
		},
	}
end

return BuildSkillsData
