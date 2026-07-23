local MAGIC_SPELL_NAMES =
{
    [STRINGS.SPELLS.SHADOW_TRAP or "Shadow Sneak"] = true,
    [STRINGS.SPELLS.SHADOW_PILLARS or "Shadow Prison"] = true,
    [STRINGS.SPELLS.UMBRAL_RIFT or "Umbral Rift"] = true,
    [STRINGS.SPELLS.ECLIPSE_FALL or "Eclipse Fall"] = true,
    [STRINGS.SPELLS.DOMAIN_EXPANSION or "Domain Expansion"] = true,
    [STRINGS.SPELLS.FISSURE_ERUPTION or "Fissure Eruption"] = true,
}

local SUMMON_SPELL_NAMES =
{
    [STRINGS.SPELLS.SHADOW_WORKER or "Shadow Worker"] = true,
    [STRINGS.SPELLS.SHADOW_PROTECTOR or "Shadow Duelist"] = true,
    [STRINGS.SPELLS.SHADOW_LANTERNBEARER or "Shadow Lanternbearer"] = true,
    [STRINGS.SPELLS.SHADOW_MARKSMAN or "Shadow Marksman"] = true,
    [STRINGS.SPELLS.SHADOW_STALKER or "Shadow Stalker"] = true,
}

local function GetSpellName(book)
    local spellbook = book ~= nil and book.components ~= nil and book.components.spellbook or book
    return spellbook ~= nil and spellbook.GetSpellName ~= nil and spellbook:GetSpellName() or nil
end

local function IsMagicSpellName(spellname)
    return spellname ~= nil and MAGIC_SPELL_NAMES[spellname] or false
end

local function IsSummonSpellName(spellname)
    return spellname ~= nil and SUMMON_SPELL_NAMES[spellname] or false
end

local function IsMagicSpell(book)
    return IsMagicSpellName(GetSpellName(book))
end

local function IsSummonSpell(book)
    return IsSummonSpellName(GetSpellName(book))
end

return {
    MAGIC_SPELL_NAMES = MAGIC_SPELL_NAMES,
    SUMMON_SPELL_NAMES = SUMMON_SPELL_NAMES,
    IsMagicSpellName = IsMagicSpellName,
    IsSummonSpellName = IsSummonSpellName,
    IsMagicSpell = IsMagicSpell,
    IsSummonSpell = IsSummonSpell,
}
