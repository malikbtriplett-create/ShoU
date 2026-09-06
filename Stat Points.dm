//set these in the actual race proc eventually
mob/var/majin_stat_version=0

mob/var/stat_version=0

var/cur_stat_ver = 10012

mob/var
	tmp
		lastStatPointClick = 0

mob/verb/Skill_Points(type as text,skill as text)
    set name=".Skill_Points"
    set hidden=1

    if(world.time - lastStatPointClick <= world.tick_lag * 2) return
    lastStatPointClick = world.time

    if(!C) C=src
    if(!C) return
    if(!skill || skill == "") return
    if(!C.Redoing_Stats) return

    if(!(type in list("-","+"))) return
    if(!(winget(src,"skills","is-visible")=="true")) return

    var/canonical_stat = C.GetCanonicalAuthoritativeStatName(skill)
    if(!canonical_stat) return

    var/result = 0

    if(type == "+")
        result = C.InvestStatPoint(canonical_stat)
    else
        result = C.RemoveStatPoint(canonical_stat)

    if(!result) return

    C.UpdateStatAllocationUI(src)
mob/verb/Skill_Points_Done()
	set name=".Skill_Points_Done"
	set hidden=1

	if(!C) C=src

	var/remaining = C.GetRemainingStatPoints()

	if(remaining)
		alert(src,"You have [remaining] remaining points, they must be distributed before this window can be closed.")
	else
		winshow(src,"skills",0)

mob/var/Points=1
mob/var/Max_Points=1
mob/var/tmp/mob/C //The mob you are giving stats to when you hit the +- controls in Redo Stats

var/list/DU_Stat_Names = list(
	"Energy" = "Energy",
	"Strength" = "Strength",
	"Durability" = "Durability",
	"Speed" = "Speed",
	"Force" = "Force",
	"Resistance" = "Resistance",
	"Accuracy" = "Accuracy",
	"Regeneration" = "Regeneration",
	"Recovery" = "Recovery",
	"Anger" = "Anger"
)

var/list/DU_Stat_Growth_Rates = list(
	"Energy" = 0.1,
	"Strength" = 0.1,
	"Durability" = 0.1,
	"Speed" = 0.1,
	"Force" = 0.1,
	"Resistance" = 0.1,
	"Accuracy" = 0.1,
	"Regeneration" = 0.2,
	"Recovery" = 0.2,
	"Anger" = 0.1
)

var/list/DU_Stat_InvestmentCaps = list(
	"Energy" = 50,
	"Strength" = 50,
	"Durability" = 50,
	"Speed" = 50,
	"Force" = 50,
	"Resistance" = 50,
	"Accuracy" = 50,
	"Regeneration" = 25,
	"Recovery" = 25,
	"Anger" = 20
)

proc/GetAllStatNames()
	return list("Energy","Strength","Durability","Speed","Force","Resistance","Accuracy","Regeneration","Recovery","Anger")

proc/GetAuthoritativeStatNames()
	return list("Energy","Strength","Durability","Speed","Force","Resistance","Accuracy","Regeneration","Recovery","Anger")

#define STAT_RATING_UNDEFINED 0
#define STAT_RATING_VERY_LOW 1
#define STAT_RATING_LOW 2
#define STAT_RATING_AVERAGE 3
#define STAT_RATING_HIGH 4
#define STAT_RATING_VERY_HIGH 5
#define STAT_RATING_EXTREME 6

mob/proc/UpdateStatAllocationUI(mob/viewer)
		if(!viewer) viewer=src
		if(!viewer.client) return
		if(!viewer.client.screen) return

		winset(viewer,"skills.PointsRemaining","text=[GetRemainingStatPoints()]")

		winset(viewer,"skills.Energy","text=[GetEffectiveStat("Energy")]")
		winset(viewer,"skills.Strength","text=[GetEffectiveStat("Strength")]")
		winset(viewer,"skills.Durability","text=[GetEffectiveStat("Durability")]")
		winset(viewer,"skills.Speed","text=[GetEffectiveStat("Speed")]")
		winset(viewer,"skills.Force","text=[GetEffectiveStat("Force")]")
		winset(viewer,"skills.Resistance","text=[GetEffectiveStat("Resistance")]")
		winset(viewer,"skills.Accuracy","text=[GetEffectiveStat("Accuracy")]")
		winset(viewer,"skills.Regeneration","text=[GetEffectiveStat("Regeneration")]")
		winset(viewer,"skills.Recovery","text=[GetEffectiveStat("Recovery")]")
		winset(viewer,"skills.Anger","text=[GetEffectiveStat("Anger")]")

// ===== DU 2026 STAT GROWTH ENGINE : PHASE 5F.1 =====
// Purpose:
//   Centralize the conversion from stat allocation into the new DU combat-stat
//   growth model.
//
// Design:
//   Allocation -> Growth Weight -> BP Scaling -> Racial/Birth Modifier
//   -> Effective Combat Stat
//
// This layer is intentionally NOT connected to legacy Str/End/Spd/Pow/Res/Off
// combat formulas yet.
//
// Do not delete or migrate legacy stat consumers until the replacement engine
// has been validated and those consumers have been migrated individually.

// ---------------------------------------------------------------------------
// New-engine constants
// ---------------------------------------------------------------------------

// All new combat stats begin from a normalized value of 1.0 before growth
// and modifiers are applied.
var/const/DU_STAT_GROWTH_BASE = 1.0

// BP scaling is deliberately isolated behind one constant/proc so the actual
// curve can be changed without touching every stat consumer.
var/const/DU_STAT_BP_REFERENCE = 1.0
// ===== DU 2026 STAT GROWTH ENGINE : PHASE 5F.4 =====
// BP scaling constants.
//
// These are conservative prototype values.
//
// BP scaling is based on logarithmic BP magnitude rather than
// raw BP. This allows BP to influence combat-stat growth without
// turning BP into a direct damage multiplier.
//
// Reference curve:
//
//     BP 1,000       -> 1.00x
//     BP 10,000      -> 1.10x
//     BP 100,000     -> 1.20x
//     BP 1,000,000   -> 1.30x
//     BP 10,000,000  -> 1.40x
//
// These constants are GLOBAL and intentionally live alongside
// the existing DU_STAT_BP_REFERENCE constant.
//
// The Phase 5F.3 matchup engine remains separate and continues
// to handle BP differences between two characters.
//
// These values are NOT final balance.

#define DU_STAT_BP_GROWTH_PER_DECADE 0.10
#define DU_STAT_BP_MIN_SCALE 0.70
#define DU_BP_SUPPRESSION_ZERO_PRESSURE 0.20
#define DU_BP_SUPPRESSION_TWO_PRESSURE 0.65
#define DU_BP_SUPPRESSION_MAX_STAGES 2


// ===== END DU 2026 STAT GROWTH ENGINE : PHASE 5F.4 =====


// ---------------------------------------------------------------------------
// GetStatGrowthWeight()
//
// Returns the allocation-derived growth weight for one authoritative stat.
//
// This is intentionally separate from GetStatValue() because GetStatValue()
// remains the Phase 1 compatibility calculation for the time being.
// ---------------------------------------------------------------------------

mob/proc/GetStatGrowthWeight(stat_name)
    var/canonical = GetCanonicalAuthoritativeStatName(stat_name)

    if(!canonical)
        return 0

    if(!islist(stat_investment))
        return 0

    var/investment = stat_investment[canonical]

    if(!isnum(investment))
        investment = 0

    var/growth = DU_Stat_Growth_Rates[canonical]

    if(!isnum(growth))
        growth = 0.1

    return max(0, investment * growth)

// ---------------------------------------------------------------------------
// GetStatBPScale()
//
// Phase 5F.1 deliberately uses a neutral BP scale.
//
// This gives us a single authoritative hook for the future BP growth curve
// without changing combat balance yet.
//
// Later phases will replace the neutral return with the finalized BP curve.
// ---------------------------------------------------------------------------

mob/proc/GetStatBPScale(stat_name)
    var/canonical = GetCanonicalAuthoritativeStatName(stat_name)

    if(!canonical)
        return 1.0

    // -----------------------------------------------------------------------
    // DU 2026 STAT GROWTH ENGINE : PHASE 5F.4
    //
    // Only combat-power stats receive BP-based growth scaling.
    //
    // Strength
    // Durability
    // Speed
    // Force
    // Resistance
    // Accuracy
    //
    // Energy, Regeneration, Recovery, and Anger remain static here.
    // Energy receives separate treatment in a later phase.
    //
    // BP is deliberately compressed through a logarithmic curve.
    // A tenfold increase in BP changes the growth scale by only 0.10.
    // -----------------------------------------------------------------------

    if(!IsCombatPowerStat(canonical))
        return 1.0

    var/my_bp = max(BP, 1)

    var/log_bp = log(max(my_bp, 1), 10)

    // BP 1,000 is the reference point.
    var/decades_from_reference = log_bp - 3

    var/scale = 1.0 + (decades_from_reference * DU_STAT_BP_GROWTH_PER_DECADE)

    return max(DU_STAT_BP_MIN_SCALE, scale)
// ===== DU 2026 STAT GROWTH ENGINE : PHASE 5F.2 =====
// Stat growth classification.
//
// This phase does not change the existing growth calculation.
// It gives the new engine an explicit distinction between:
//
//   Combat-power stats
//     Strength
//     Durability
//     Speed
//     Force
//     Resistance
//     Accuracy
//
// and:
//
//   Rate/control stats
//     Energy
//     Regeneration
//     Recovery
//     Anger
//
// Combat-power stats may receive BP scaling in a later phase.
// Rate/control stats must not automatically inflate with BP.
//
// Keeping this distinction centralized prevents future stat
// formulas from accidentally treating every stat identically.

// Returns 1 when the stat is a combat-power stat.
// Returns 0 for rate/control stats or invalid names.

mob/proc/IsCombatPowerStat(stat_name)
    var/canonical = GetCanonicalAuthoritativeStatName(stat_name)

    if(!canonical)
        return 0

    switch(canonical)
        if("Strength", "Durability", "Speed", "Force", "Resistance", "Accuracy")
            return 1

    return 0


// Returns 1 when the stat is a rate/control stat.
// Returns 0 for combat-power stats or invalid names.

mob/proc/IsRateControlStat(stat_name)
    var/canonical = GetCanonicalAuthoritativeStatName(stat_name)

    if(!canonical)
        return 0

    switch(canonical)
        if("Energy", "Regeneration", "Recovery", "Anger")
            return 1

    return 0


// Returns the growth category used by the new engine.
//
// "Combat" = may eventually scale with BP.
// "Rate"   = remains a direct/static stat value.
// null     = invalid/unsupported stat.

mob/proc/GetStatGrowthCategory(stat_name)
    var/canonical = GetCanonicalAuthoritativeStatName(stat_name)

    if(!canonical)
        return null

    if(IsCombatPowerStat(canonical))
        return "Combat"

    if(IsRateControlStat(canonical))
        return "Rate"

    return null

// ---------------------------------------------------------------------------
// GetStatGrowthValue()
//
// New-engine normalized stat value:
//
//   base
//   + allocation growth
//
// BP scaling is currently neutral and is intentionally kept behind
// GetStatBPScale().
//
// Racial/birth modifiers remain supplied by the existing modifier-source
// system so Phase 5F.1 does not duplicate modifier ownership.
// ---------------------------------------------------------------------------

mob/proc/GetStatGrowthValue(stat_name)
    var/canonical = GetCanonicalAuthoritativeStatName(stat_name)

    if(!canonical)
        return 1.0

    var/growth_value = DU_STAT_GROWTH_BASE
    growth_value += GetStatGrowthWeight(canonical)

    growth_value *= GetStatBPScale(canonical)

    return max(0, growth_value)

// ---------------------------------------------------------------------------
// GetNewEffectiveStat()
//
// This is the first central entry point for the 2026 stat engine.
//
// It intentionally does NOT replace GetEffectiveStat() yet.
// That allows us to validate the new calculation beside the existing
// compatibility layer before migrating gameplay consumers.
// ---------------------------------------------------------------------------

mob/proc/GetNewEffectiveStat(stat_name)
    var/canonical = GetCanonicalAuthoritativeStatName(stat_name)

    if(!canonical)
        return 1.0

    var/value = GetStatGrowthValue(canonical)

    // Existing modifier sources remain the authoritative source of temporary
    // and racial/birth modifiers during the migration period.
    //
    // GetStatModifier() is intentionally not used here because the existing
    // aggregate list already represents the authoritative modifier total.
    if(islist(stat_modifiers))
        var/modifier = stat_modifiers[canonical]

        if(isnum(modifier))
            value += modifier

    return max(0, value)

// ---------------------------------------------------------------------------
// CompareNewStatEngine()
//
// Development helper for validating the new engine against the current
// compatibility calculation.
//
// This does not alter character state.
// ---------------------------------------------------------------------------

mob/proc/CompareNewStatEngine(stat_name)
    var/canonical = GetCanonicalAuthoritativeStatName(stat_name)

    if(!canonical)
        return null

    return list(
        "Stat" = canonical,
        "Investment" = GetStatInvestment(canonical),
        "Growth Weight" = GetStatGrowthWeight(canonical),
        "BP Scale" = GetStatBPScale(canonical),
        "New Engine" = GetNewEffectiveStat(canonical),
        "Compatibility Engine" = GetEffectiveStat(canonical)
    )

// ===== END DU 2026 STAT GROWTH ENGINE : PHASE 5F.1 =====

mob/proc/GetEffectiveStat(stat_name)
	var/canonical = GetCanonicalAuthoritativeStatName(stat_name)
	if(!canonical) return 0

	var/investment = GetStatInvestment(canonical)
	var/growth = DU_Stat_Growth_Rates[canonical]
	if(!isnum(growth)) growth = 0.1

	var/allocation_value = investment * growth
	var/modifier_value = 0

	if(islist(stat_modifiers) && isnum(stat_modifiers[canonical]))
		modifier_value = stat_modifiers[canonical]

	return 1.0 + allocation_value + modifier_value

mob/proc/GetCanonicalAuthoritativeStatName(stat_name)
	var/canonical = GetCanonicalStatName(stat_name)
	if(!(canonical in GetAuthoritativeStatNames())) return null
	return canonical

mob/proc/GetStatModifierInstanceKey(instance_id = null)
	if(isnull(instance_id)) return "__default__"
	return "[instance_id]"

mob/proc/SetStatModifierSource(source_id, list/modifiers, instance_id = null, lifetime = "persistent")
	if(!istext(source_id) || !length(source_id)) return 0
	if(!islist(modifiers) || !modifiers.len) return 0
	if(!istext(lifetime) || !length(lifetime)) return 0

	var/list/normalized_modifiers = new/list
	for(var/stat_name in modifiers)
		var/canonical = GetCanonicalAuthoritativeStatName(stat_name)
		if(!canonical || !isnum(modifiers[stat_name])) return 0
		if(!isnum(normalized_modifiers[canonical])) normalized_modifiers[canonical] = 0
		normalized_modifiers[canonical] += modifiers[stat_name]

	if(!islist(stat_modifier_sources)) stat_modifier_sources = new/list
	var/list/source_instances = stat_modifier_sources[source_id]
	if(!islist(source_instances))
		source_instances = new/list
		stat_modifier_sources[source_id] = source_instances

	var/instance_key = GetStatModifierInstanceKey(instance_id)
	source_instances[instance_key] = list(
		"source_id" = source_id,
		"instance_id" = instance_id,
		"lifetime" = lifetime,
		"modifiers" = normalized_modifiers
	)
	RebuildStatModifiers()
	return 1

mob/proc/RemoveStatModifierSource(source_id, instance_id = null)
	if(!istext(source_id) || !length(source_id)) return 0
	if(!islist(stat_modifier_sources)) return 0
	var/list/source_instances = stat_modifier_sources[source_id]
	if(!islist(source_instances)) return 0
	var/instance_key = GetStatModifierInstanceKey(instance_id)
	if(!(instance_key in source_instances)) return 0
	source_instances -= instance_key
	if(!source_instances.len) stat_modifier_sources -= source_id
	RebuildStatModifiers()
	return 1

mob/proc/RemoveAllStatModifierSources(source_id)
	if(!istext(source_id) || !length(source_id)) return 0
	if(!islist(stat_modifier_sources) || !(source_id in stat_modifier_sources)) return 0
	stat_modifier_sources -= source_id
	RebuildStatModifiers()
	return 1

mob/proc/RebuildStatModifiers()
	if(!islist(stat_modifiers)) stat_modifiers = new/list
	var/list/authoritative_names = GetAuthoritativeStatNames()
	for(var/stat_name in authoritative_names)
		stat_modifiers[stat_name] = 0

	if(!islist(stat_modifier_sources)) return 1
	for(var/source_id in stat_modifier_sources)
		var/list/source_instances = stat_modifier_sources[source_id]
		if(!islist(source_instances)) continue
		for(var/instance_key in source_instances)
			var/list/source_record = source_instances[instance_key]
			if(!islist(source_record)) continue
			var/list/source_modifiers = source_record["modifiers"]
			if(!islist(source_modifiers)) continue
			for(var/stat_name in source_modifiers)
				var/canonical = GetCanonicalAuthoritativeStatName(stat_name)
				if(!canonical || !isnum(source_modifiers[stat_name])) continue
				stat_modifiers[canonical] += source_modifiers[stat_name]
	return 1

mob/proc/MigrateLegacyStatModifiers()
	if(!islist(stat_modifier_sources)) stat_modifier_sources = new/list
	if(islist(stat_modifier_sources["__legacy_aggregate__"])) return 1
	if(!islist(stat_modifiers)) return 1

	var/list/legacy_modifiers = new/list
	for(var/stat_name in GetAuthoritativeStatNames())
		if(isnum(stat_modifiers[stat_name]) && stat_modifiers[stat_name] != 0)
			legacy_modifiers[stat_name] = stat_modifiers[stat_name]
	if(!legacy_modifiers.len) return 1
	return SetStatModifierSource("__legacy_aggregate__", legacy_modifiers, null, "migration")

mob/Admin5/verb/Report_Stat_Modifier_Sources()
	set name = "Report Stat Modifier Sources"
	set category = "Admin"
	if(!islist(stat_modifier_sources) || !stat_modifier_sources.len)
		src << "Stat modifier sources: none."
		return
	src << "Stat modifier sources:"
	for(var/source_id in stat_modifier_sources)
		var/list/source_instances = stat_modifier_sources[source_id]
		if(!islist(source_instances)) continue
		for(var/instance_key in source_instances)
			var/list/source_record = source_instances[instance_key]
			if(!islist(source_record)) continue
			var/list/source_modifiers = source_record["modifiers"]
			var/lifetime = source_record["lifetime"]
			src << "- [source_id] / [instance_key] ([lifetime]): [source_modifiers]"
	src << "Aggregate: [stat_modifiers]"

mob/proc/GetStatRating(stat_name)
	if(!(stat_name in GetAuthoritativeStatNames())) return STAT_RATING_UNDEFINED
	var/effective_value = GetEffectiveStat(stat_name)

	switch(stat_name)
		if("Regeneration")
			if(effective_value < 1) return STAT_RATING_VERY_LOW
			if(effective_value < 1.4) return STAT_RATING_LOW
			if(effective_value < 2.6) return STAT_RATING_AVERAGE
			if(effective_value < 5) return STAT_RATING_HIGH
			if(effective_value < 8) return STAT_RATING_VERY_HIGH
			return STAT_RATING_EXTREME
		if("Recovery")
			if(effective_value < 1) return STAT_RATING_VERY_LOW
			if(effective_value < 1.4) return STAT_RATING_LOW
			if(effective_value < 2.6) return STAT_RATING_AVERAGE
			if(effective_value < 5) return STAT_RATING_HIGH
			if(effective_value < 10) return STAT_RATING_VERY_HIGH
			return STAT_RATING_EXTREME
		if("Energy", "Anger") return STAT_RATING_UNDEFINED
		if("Strength", "Durability", "Speed", "Force", "Resistance", "Accuracy")
			if(effective_value < 4) return STAT_RATING_VERY_LOW
			if(effective_value < 6) return STAT_RATING_LOW
			if(effective_value < 9) return STAT_RATING_AVERAGE
			if(effective_value < 12) return STAT_RATING_HIGH
			if(effective_value < 15) return STAT_RATING_VERY_HIGH
			return STAT_RATING_EXTREME
	return STAT_RATING_UNDEFINED

mob/proc/GetCanonicalStatName(stat_name)
	if(!stat_name) return null

	var/lower = lowertext(stat_name)

	for(var/i in GetAuthoritativeStatNames())
		if(lower == lowertext(i))
			return i

	return null

mob/proc/GetRaceStatPool(race_name = null, class_name = null)
	if(!race_name) race_name = src.Race
	if(!class_name) class_name = src.Class

	var/list/defaultPools = list(
		"Yasai" = 55,
		"Half Yasai" = 55,
		"Human" = 55,
		"Tsujin" = 55,
		"Alien" = 55
	)

	if(class_name == "Low Class" && race_name == "Yasai") return 55
	if(race_name == "Tsujin") return 68
	if(race_name in defaultPools) return defaultPools[race_name]
	return 55

mob/proc/GetStatCap(stat_name)
	var/canonical = GetCanonicalStatName(stat_name)
	if(!canonical) return 0
	if(!(canonical in DU_Stat_InvestmentCaps)) return 0
	return DU_Stat_InvestmentCaps[canonical]

mob/proc/GetStatPointCost(stat_name)
	var/canonical = GetCanonicalStatName(stat_name)
	if(!canonical) return 0
	return 1

mob/proc/GetTotalStatInvestment()
		var/total = 0

		for(var/stat_name in GetAuthoritativeStatNames())
				total += GetStatInvestment(stat_name)

		return total
mob/proc/GetStatInvestment(stat_name)
	var/canonical = GetCanonicalStatName(stat_name)
	if(!canonical) return 0
	if(!islist(stat_investment)) stat_investment = new/list
	if(!isnum(stat_investment[canonical])) stat_investment[canonical] = 0
	return stat_investment[canonical]

mob/proc/GetStatValue(stat_name)
	var/investment = GetStatInvestment(stat_name)
	var/canonical = GetCanonicalStatName(stat_name)
	if(!canonical) return 1.0
	var/growth = DU_Stat_Growth_Rates[canonical]
	if(!isnum(growth)) growth = 0.1
	return 1.0 + (investment * growth)

mob/proc/GetTotalInvestedPoints()
	var/total = 0

	for(var/stat_name in GetAuthoritativeStatNames())
		total += GetStatInvestment(stat_name)

	return total

mob/proc/GetRemainingStatPoints()
	if(!stat_pool_total) stat_pool_total = GetRaceStatPool()
	return max(0, stat_pool_total - GetTotalInvestedPoints())

mob/proc/ValidateStatAllocation()
	if(!isnum(stat_pool_total) || stat_pool_total <= 0) return 0
	if(!islist(stat_investment)) stat_investment = new/list
	for(var/key in stat_investment)
		if(!GetCanonicalStatName(key)) return 0
	if(GetTotalInvestedPoints() > stat_pool_total) return 0
	for(var/stat_name in GetAllStatNames())
		if(GetStatInvestment(stat_name) < 0) return 0
		if(GetStatInvestment(stat_name) > GetStatCap(stat_name)) return 0
	return 1

mob/proc/CanInvestStatPoint(stat_name)
	var/canonical = GetCanonicalStatName(stat_name)
	if(!canonical) return 0
	if(GetStatInvestment(canonical) >= GetStatCap(canonical)) return 0
	if((GetTotalInvestedPoints() + 1) > stat_pool_total) return 0
	if(!ValidateStatAllocation()) return 0
	return 1

mob/proc/InvestStatPoint(stat_name)
	var/canonical = GetCanonicalStatName(stat_name)
	if(!canonical) return 0
	if(!CanInvestStatPoint(canonical)) return 0
	if(!islist(stat_investment)) stat_investment = new/list
	stat_investment[canonical] += 1
	if(!isnum(stat_pool_total) || stat_pool_total <= 0) stat_pool_total = GetRaceStatPool()
	Points = GetRemainingStatPoints()
	Max_Points = stat_pool_total
	return 1

mob/proc/CanRemoveStatPoint(stat_name)
	var/canonical = GetCanonicalStatName(stat_name)
	if(!canonical) return 0
	if(GetStatInvestment(canonical) <= 0) return 0
	if(!ValidateStatAllocation()) return 0
	return 1

mob/proc/RemoveStatPoint(stat_name)
	var/canonical = GetCanonicalStatName(stat_name)
	if(!canonical) return 0
	if(!CanRemoveStatPoint(canonical)) return 0
	if(!islist(stat_investment)) stat_investment = new/list
	stat_investment[canonical] = max(0, stat_investment[canonical] - 1)
	if(!isnum(stat_pool_total) || stat_pool_total <= 0) stat_pool_total = GetRaceStatPool()
	Points = GetRemainingStatPoints()
	Max_Points = stat_pool_total
	return 1

mob/proc/InitializeStatAllocation()
	if(!islist(stat_base_values)) stat_base_values = new/list
	if(!islist(stat_investment)) stat_investment = new/list
	if(!islist(stat_modifiers)) stat_modifiers = new/list
	if(!islist(stat_modifier_sources)) stat_modifier_sources = new/list

	if(!isnum(stat_schema_version) || stat_schema_version <= 0)
		stat_schema_version = 1

	if(!isnum(stat_pool_total) || stat_pool_total <= 0)
		stat_pool_total = GetRaceStatPool()

	var/list/authoritative_names = GetAuthoritativeStatNames()

	for(var/key in stat_base_values.Copy())
		if(!(key in authoritative_names))
			stat_base_values -= key

	for(var/key in stat_investment.Copy())
		if(!(key in authoritative_names))
			stat_investment -= key

	for(var/key in stat_modifiers.Copy())
		if(!(key in authoritative_names))
			stat_modifiers -= key

	for(var/stat_name in authoritative_names)
		stat_base_values[stat_name] = 1.0
		if(!isnum(stat_investment[stat_name]) || stat_investment[stat_name] < 0)
			stat_investment[stat_name] = 0
		if(!isnum(stat_modifiers[stat_name]))
			stat_modifiers[stat_name] = 0

	if(stat_schema_version < 2)
		MigrateLegacyStatModifiers()

	stat_schema_version = 3
	RebuildStatModifiers()

	Points = GetRemainingStatPoints()
	Max_Points = stat_pool_total

	return 1

mob/proc/GetStatMod(stat)
	. = 0
	switch(stat)
		if("Str") return Math.Floor((Str - 6) / 3) + transStrBonus * (1 - GetTraitRank("Fulfilled Potential") * 0.1)
		if("Spd") return Math.Floor((Spd - 6) / 3) + (transSpdBonus + transRefBonus) * (1 - GetTraitRank("Fulfilled Potential") * 0.1)
		if("Dur") return Math.Floor((End - 6) / 3) + transDurBonus * (1 - GetTraitRank("Fulfilled Potential") * 0.1)
		if("For") return Math.Floor((Pow - 6) / 3) + transForBonus * (1 - GetTraitRank("Fulfilled Potential") * 0.1)
		if("Res") return Math.Floor((Res - 6) / 3) + transResBonus * (1 - GetTraitRank("Fulfilled Potential") * 0.1)
		if("Acc") return Math.Floor((Off - 6) / 3) + transAccBonus * (1 - GetTraitRank("Fulfilled Potential") * 0.1)
		if("Ref") return Math.Floor((Spd - 6) / 3) + (transSpdBonus + transRefBonus) * (1 - GetTraitRank("Fulfilled Potential") * 0.1)

proc/GetStatModFromNum(n)
	if(!n || !isnum(n)) return 0
	return Math.Floor((n - 6) / 3)

mob/var
	transStrBonus = 0
	transSpdBonus = 0
	transDurBonus = 0
	transForBonus = 0
	transResBonus = 0
	transAccBonus = 0
	transRefBonus = 0

mob/proc/GetReadableStatMod(stat)
	. = "0"
	var/t = GetStatMod(stat)
	return t >= 0 ? "+[t]" : "[t]"
	
mob/proc/GetTierBonus(mod = 0.5)
	return 1 + ((effectiveBPTier - 1) * mod)
	
proc/GetModifiedTierBonus(mod = 0.5, mob/bigger, mob/smaller)
	var/tierDiff = bigger.effectiveBPTier - smaller.effectiveBPTier
	return 1 + tierDiff * mod

mob/proc/Raise_Energy(Amount=1)
	if(!C) C=src
	var/old_mod=C.Eff
	C.Eff+=0.1*Amount
	C.max_ki*=C.Eff/old_mod
	C.Ki*=C.Eff/old_mod

mob/proc/Raise_Speed(Amount=1)
	if(!C) C=src
	C.Spd+=Amount

mob/proc/Raise_Strength(Amount=1)
	if(!C) C=src
	C.Str+=Amount

mob/proc/Raise_Durability(Amount=1)
	if(!C) C=src
	C.End+=Amount

mob/proc/Raise_Force(Amount=1)
	if(!C) C=src
	C.Pow+=Amount

mob/proc/Raise_Resist(Amount=1)
	if(!C) C=src
	C.Res+=Amount

mob/proc/Raise_Offense(Amount=1)
	if(!C) C=src
	C.Off+=Amount

mob/proc/Raise_Defense(Amount=1)
	if(!C) C=src
	C.Def+=Amount

mob/proc/Raise_Regeneration(Amount=1)
	if(!C) C=src
	C.regen+=0.2*Amount

mob/proc/Raise_Recovery(Amount=1)
	if(!C) C=src
	C.recov+=0.2*Amount

mob/proc/Raise_Anger(Amount=1)
	if(!C) C=src
	C.max_anger+=10*Amount

/*
============================================================
RACIAL STAT MODIFIERS
============================================================

Authoritative stats begin at 1.0.
Player allocation determines the build.
Race supplies small additive modifiers.
Racial modifiers do not consume allocation points.
============================================================
*/

mob/proc/GetRacialStatModifiers()
    var/list/modifiers = new/list

    switch(Race)
        if("Human")
            modifiers["Accuracy"] = 0.2
            modifiers["Recovery"] = 0.2


        if("Tsujin")
            // Intentionally no innate stat modifiers.

        if("Puranto")
            modifiers["Durability"] = 0.2
            modifiers["Regeneration"] = 0.3
            modifiers["Recovery"] = 0.2

        if("Yasai")
            modifiers["Strength"] = 0.2
            modifiers["Force"] = 0.2
            modifiers["Speed"] = 0.2

            if(Class == "Legendary")
                modifiers["Durability"] = 0.2
                modifiers["Resistance"] = 0.2

        if("Legendary Yasai")
            modifiers["Durability"] = 0.2
            modifiers["Resistance"] = 0.2
            modifiers["Strength"] = 0.2
            modifiers["Force"] = 0.2

        if("Half Yasai")
            modifiers["Strength"] = 0.1
            modifiers["Force"] = 0.1
            modifiers["Speed"] = 0.1
            modifiers["Accuracy"] = 0.1

        if("Bio-Android")
            modifiers["Regeneration"] = 0.4

        if("Majin")
            modifiers["Regeneration"] = 0.5

        if("Kai")
            modifiers["Energy"] = 0.2
            modifiers["Force"] = 0.2
            modifiers["Recovery"] = 0.2

        if("Demon")
            modifiers["Strength"] = 0.2
            modifiers["Force"] = 0.2
            modifiers["Regeneration"] = 0.1

        if("Frost Lord")
            modifiers["Force"] = 0.2
            modifiers["Resistance"] = 0.2
            modifiers["Speed"] = 0.2

        if("Onion Lad")
            modifiers["Energy"] = 0.3
            modifiers["Regeneration"] = 0.3
            modifiers["Recovery"] = 0.3

        if("Bojack")
            modifiers["Durability"] = 0.3
            modifiers["Resistance"] = 0.3

    return modifiers

mob/proc/SyncRacialStatModifiers()
	RemoveAllStatModifierSources("race")

	var/list/racial_modifiers = GetRacialStatModifiers()

	if(islist(racial_modifiers) && racial_modifiers.len)
		SetStatModifierSource("race",racial_modifiers,null,"persistent")

	return 1


/* Compatibility entry point for existing creation and redo callers. */
mob/proc/Racial_Stats(mob/P,Start_Redo_Stats=1,modless_check=1)
	if(!P) P=src

	InitializeStatAllocation()
	SyncRacialStatModifiers()

	if(Start_Redo_Stats)
		BeginStatAllocation(P)

	stat_version=cur_stat_ver
	return 1


mob/proc/BeginStatAllocation(mob/P)
	if(!P) P=src

	P.C=src
	Points=GetRemainingStatPoints()
	Max_Points=stat_pool_total
	Redoing_Stats=1

	if(P.client)
		UpdateStatAllocationUI(P)
		winshow(P,"skills",1)

		while(P&&P.client&&(winget(P,"skills","is-visible")=="true"))
			sleep(2)

	Redoing_Stats=0

	Points=GetRemainingStatPoints()
	Max_Points=stat_pool_total

	return 1

var
	lssj_ki_mult = 2.5

mob/var/Modless_Gain=1

mob/var/tmp/Redoing_Stats

obj/Redo_Stats
	var/Last_Redo=0
	var/tmp/Redoing_Stats
	verb/Redo_Stats()
		set category="Other"
		if(!usr.Points)
			if(Last_Redo+5>GetGlobalYear())
				usr<<"You can not do this til year [Last_Redo+5]"
				return
		Last_Redo=GetGlobalYear()
		usr.Redo_Stats(usr)


mob/proc/Duplicate(include_unclonables = 0, nullLoc = 0, wipeOriginalsContents)
	var/list/L = new
	for(var/mob/M in src)
		L += M
		M.SafeTeleport(null)
		contents -= M
	for(var/obj/o in src)
		if(!o.clonable && include_unclonables == 0)
			L += o
			o.loc = null
			contents -= o
			item_list -= o
			hotbar -= o
	Save_Obj(src)
	var/mob/M = new type //fix bug where it comes out as wrong mob type when you dupe splits or zoms or bodies etc
	Load_Obj(M)
	M.Savable_NPC = 1
	if(!(locate(/obj/Resources) in M)) M.contents += GetCachedObject(/obj/Resources)
	for(var/V in L)
		if(ismob(V))
			var/mob/m2 = V
			m2.SafeTeleport(src)
			//contents += V
		else if(isobj(V))
			var/obj/o = V
			o.Move(src)
	M.Status_Running=0
	if(nullLoc) M.SafeTeleport(null)
	if(wipeOriginalsContents)
		for(var/atom/movable/a in src)
			a.SafeTeleport(null)
			contents -= a
			a.DeleteNoWait()
	return M

mob/proc/CheckStatVersion()
	if(!src || !client) return
	if(stat_version != cur_stat_ver)
		alert(src, "Stats have been updated.  You must redo your stats before continuing playing.")
		Redo_Stats(src)

mob/proc/Redo_Stats(mob/P) //If P, P gets to do the stats on this mob
	if(!P) P=src
	if(!can_redo_stats)
		P << "Can not redo stats on this character type"
		return
	var/mob/original = src
	original.Save()
	Redoing_Stats = 1
	//we have to set this to wipeOriginalsContents to stop the duplication bugs
	var/mob/copy = Duplicate(include_unclonables = 1, nullLoc = 1, wipeOriginalsContents = 1)
	copy.SafeTeleport(null)
	//letting them mind swap with these during the process causes a lot of duplication bugs
	original.canMindSwapWith = 0
	copy.canMindSwapWith = 0
	copy.UnlockedTransformations = original.UnlockedTransformations
	copy.traits = original.traits

	var/transformation/T = copy.GetActiveForm()
	if(T) T.ExitForm(copy)

	original.Savable = 0 //to stop a bug where you open the redo stats menu while having a sword or anything else on you that changes stats then
		//you simply log out, and when you come back the sword (and everything else) is gone from your inventory (intentionally) but this means you keep
		//the doubled strength and you can keep stacking it. so instead make them unsavable so they reload their last valid save

	/*//to fix a bug where you redo stats then drop all your items then when you hit done all of them are duped
	//so now you only get them back if you finish redo stats
	for(var/obj/items/i in item_list)
		i.loc = null
		del(i)
	item_list = new/list
	for(var/obj/Module/m in src)
		m.loc = null
		del(m)
	SetRes(0)*/
	//fix a body dupe bug, where while you are binded, you redo stats, the copy will be sent to the bind spawn in hell, while it's there you can dupe
	for(var/obj/Curse/c in copy)
		c.loc = null
		del(c)
	sleep(1)
	copy.Revert_All()
	copy.Redoing_Stats = 1
	copy.max_ki/=copy.Eff
	copy.Ki/=copy.Eff
	copy.Eff=1
	copy.Str = 6
	copy.End = 6
	copy.Pow = 6
	copy.Res = 6
	copy.Spd = 6
	copy.Off = 6
	copy.Def = 6
	copy.regen=1
	copy.recov=1
	copy.max_anger=100
	copy.Racial_Stats(P) //it will not progress past this until the redo stats menu is closed
	if(!original)
		src << "They have logged out. Redo stats is cancelled."
		if(copy.grabber) copy.grabber.ReleaseGrab()
		copy.SafeTeleport(null)
		Redoing_Stats = 0
		copy.Redoing_Stats = 0
		del(copy)
		return
	//this means they have somehow taken the copy out of the void, for duplication purposes. so stop
	if(copy.loc)
		src << "Something went wrong"
		if(copy.grabber) copy.grabber.ReleaseGrab()
		copy.SafeTeleport(null)
		Redoing_Stats = 0
		copy.Redoing_Stats = 0
		del(copy)
		return
	//---
	copy.Redoing_Stats=0
	copy.Apply_t_injections(original.T_Injections)
	Switch_Bodies(src,copy)
	copy.SafeTeleport(original.loc)
	copy.canMindSwapWith = 1 //process is over, let them mind swap again as normal
	original.SafeTeleport(null)
	//if the original was binded, so is the copy
	for(var/obj/Curse/c in original)
		original.contents -= c
		c.loc = null
		copy.contents += c
	if(original) del(original)

mob/proc/ResolveProjectileBlock(obj/Blast/projectile)
	if(!blocking || !projectile) return 0
	if(!projectile.Deflectable) return 0

	// Speed controls the initial Perfect Block reaction window.
	// Holding Block does not refresh this window.
	var/perfect_window = 2 + round(Math.Max(GetStatMod("Spd"), 1) / 2)
	perfect_window = Math.Clamp(perfect_window, 2, 5)

	var/block_age = world.time - block_started_at

	if(block_started_at > 0 && block_age >= 0 && block_age <= perfect_window)
		// Consume the initial Perfect Block window.
		block_started_at = 0

		// Store the projectile for the second-stage deflection.
		deflecting_projectile = projectile
		deflect_input_start = world.time
		deflect_window = perfect_window

		// Mark the projectile as deflected so its normal collision
		// resolution does not immediately damage the blocker.
		projectile.deflected = 1

		// Start the directional steering window.
		SpawnProjectileDeflectionWindow()

		return 1

	// Initial Perfect Block window expired.
	block_started_at = 0

	return 0

mob/proc/SpawnProjectileDeflectionWindow()
	set waitfor = 0
	set instant = 1

	var/mob/M = src

	if(!M) return
	if(!M.deflecting_projectile) return

	var/start_time = M.deflect_input_start
	var/window = M.deflect_window

	if(start_time <= 0 || window <= 0)
		M.ClearProjectileDeflection()
		return

	while(M && M.deflecting_projectile)
		var/obj/Blast/projectile = M.deflecting_projectile

		if(!projectile)
			M.ClearProjectileDeflection()
			return

		var/elapsed = world.time - start_time

		// A directional key must be pressed AFTER the Perfect Block.
		if(M.last_directional_keydown_time > start_time)
			var/new_dir

			// Direction is relative to the blocker current facing.
			// North = forward.
			// South = backward.
			// West = player-left.
			// East = player-right.
			switch(M.last_directional_key_down)
				if("north")
					new_dir = M.dir
				if("south")
					new_dir = turn(M.dir, 180)
				if("west")
					new_dir = turn(M.dir, -90)
				if("east")
					new_dir = turn(M.dir, 90)

			if(new_dir)
				projectile.dir = new_dir
				walk(projectile, new_dir)
				M.ClearProjectileDeflection()
				return

		// No directional input yet. Let the second timing window expire.
		if(elapsed >= window)
			var/random_dir = pick(NORTH, SOUTH, EAST, WEST)
			projectile.dir = random_dir
			walk(projectile, random_dir)
			M.ClearProjectileDeflection()
			return

		sleep(world.tick_lag)

	if(M)
		M.ClearProjectileDeflection()

mob/proc/ClearProjectileDeflection()
	deflecting_projectile = null
	deflect_input_start = 0
	deflect_window = 0

// ===== DU 2026 STAT MATCHUP ENGINE : PHASE 5F.3 =====
//
// Purpose:
// Establish the relationship between Stat Ratings and Battle Power.
//
// Design:
// 1. Stat Rating establishes the matchup at equal BP.
// 2. BP difference modifies how strongly that matchup is expressed.
// 3. BP does NOT change the character's actual Stat Rating.
// 4. BP does NOT create an absolute damage gate.
// 5. An already-disadvantaged rating matchup is not blindly penalized twice.
// 6. An already-favorable rating matchup can be compressed by a large BP gap,
//    but the lower-BP character remains capable of dealing meaningful effects.
//
// This is an engine layer only.
// Existing BP calculation and legacy combat consumers remain untouched.

// Rating bracket values.
// These values represent ordering only.
#define DU_MATCHUP_RATING_VERY_LOW 0
#define DU_MATCHUP_RATING_LOW 1
#define DU_MATCHUP_RATING_AVERAGE 2
#define DU_MATCHUP_RATING_HIGH 3
#define DU_MATCHUP_RATING_VERY_HIGH 4
#define DU_MATCHUP_RATING_EXTREME 5

// BP ratio limits.
//
// These are intentionally conservative prototype values.
// They are NOT final combat balance values.
//
// A ratio below 1.0 means the attacker has less BP.
// A ratio above 1.0 means the attacker has more BP.
#define DU_BP_MATCHUP_MIN_RATIO 0.01
#define DU_BP_MATCHUP_MAX_RATIO 100.0

// BP adjustment strength.
//
// 0.0 = BP has no influence.
// 1.0 = full prototype influence.
//
// Kept separate so the eventual balance pass can tune BP influence
// without rewriting matchup logic.
#define DU_BP_MATCHUP_STRENGTH 1.0

mob/proc/GetStatRatingValue(stat_rating)
    switch(stat_rating)
        if(STAT_RATING_VERY_LOW)
            return DU_MATCHUP_RATING_VERY_LOW
        if(STAT_RATING_LOW)
            return DU_MATCHUP_RATING_LOW
        if(STAT_RATING_AVERAGE)
            return DU_MATCHUP_RATING_AVERAGE
        if(STAT_RATING_HIGH)
            return DU_MATCHUP_RATING_HIGH
        if(STAT_RATING_VERY_HIGH)
            return DU_MATCHUP_RATING_VERY_HIGH
        if(STAT_RATING_EXTREME)
            return DU_MATCHUP_RATING_EXTREME

    return DU_MATCHUP_RATING_AVERAGE

mob/proc/GetStatRatingDifference(attacker_rating, defender_rating)
    var/attacker_value = GetStatRatingValue(attacker_rating)
    var/defender_value = GetStatRatingValue(defender_rating)

    return attacker_value - defender_value

mob/proc/GetBPMatchupRatio(mob/other)
    if(!other)
        return 1.0

    var/my_bp = max(BP, 1)
    var/other_bp = max(other.BP, 1)

    var/ratio = my_bp / other_bp

    return Math.Clamp(
        ratio,
        DU_BP_MATCHUP_MIN_RATIO,
        DU_BP_MATCHUP_MAX_RATIO
    )

/*
============================================================
DU 2026 STAT GROWTH ENGINE : PHASE 5F.5
ONE-SIDED BP RATING SUPPRESSION
============================================================

Purpose:
    Convert the BP relationship between two characters into
    temporary rating-stage suppression.

Core rule:
    Stat Rating determines the matchup.
    BP determines how strongly the matchup manifests.

One-sided rule:
    ONLY the lower-BP character can be suppressed.

    The higher-BP character NEVER receives a rating increase.

Normalization:
    lower BP / higher BP

Examples:
    250k vs 1m = 25%
    1m vs 250k = 25%

Pressure:
    log10(100 / relationship%)

Suppression:
    pressure < 0.20
        = 0 stages

    pressure >= 0.20 and < 0.65
        = -1 stage

    pressure >= 0.65
        = -2 stages

Maximum:
    -2 stages

Important:
    This does NOT permanently modify the character's displayed
    rating. It produces a temporary matchup rating only.
============================================================
*/

mob/proc/GetLowerBPMatchupRatio(mob/other)
    if(!other)
        return 1.0

    var/my_bp = max(BP, 1)
    var/other_bp = max(other.BP, 1)

    var/higher_bp = max(my_bp, other_bp)
    var/lower_bp = min(my_bp, other_bp)

    if(higher_bp <= 0)
        return 1.0

    return lower_bp / higher_bp


mob/proc/GetBPMatchupPressure(mob/other)

    var/relationship = GetLowerBPMatchupRatio(other)
    relationship = max(min(relationship, 1.0), 0.000001)

    return abs(log(relationship, 10))


mob/proc/GetBPMatchupSuppressionStages(mob/other)
    if(!other)
        return 0

    var/my_bp = max(BP, 1)
    var/other_bp = max(other.BP, 1)

    // Equal BP means neither character is lower.
    if(my_bp == other_bp)
        return 0


    var/pressure = GetBPMatchupPressure(other)

    if(pressure < DU_BP_SUPPRESSION_ZERO_PRESSURE)
        return 0

    if(pressure < DU_BP_SUPPRESSION_TWO_PRESSURE)
        return 1

    return DU_BP_SUPPRESSION_MAX_STAGES


mob/proc/GetBPAdjustedStatRating(stat_rating, mob/other)
    var/rating = stat_rating

    if(!other)
        return rating

    var/my_bp = max(BP, 1)
    var/other_bp = max(other.BP, 1)

    // Higher-BP character receives NO rating increase.
    //
    // This is intentionally one-sided.
    if(my_bp >= other_bp)
        return rating

    var/suppression = GetBPMatchupSuppressionStages(other)

    rating = max(
        STAT_RATING_VERY_LOW,
        rating - suppression
    )

    return rating


mob/proc/GetBPAdjustedMatchupRating(attacker_rating, defender_rating, mob/other)
    var/attacker = GetBPAdjustedStatRating(attacker_rating, other)


    return GetStatRatingDifference(attacker, defender_rating)


mob/proc/GetBPAdjustedEffectiveMatchupRating(attacker_rating, defender_rating, mob/other)
    var/attacker = GetBPAdjustedStatRating(attacker_rating, other)


    var/difference = GetStatRatingDifference(attacker, defender_rating)

    if(difference <= -4)
        return DU_MATCHUP_RATING_VERY_LOW

    if(difference <= -2)
        return DU_MATCHUP_RATING_LOW

    if(difference < 1)
        return DU_MATCHUP_RATING_AVERAGE

    if(difference < 2)
        return DU_MATCHUP_RATING_HIGH

    if(difference < 4)
        return DU_MATCHUP_RATING_VERY_HIGH

    return DU_MATCHUP_RATING_EXTREME


mob/proc/CompareBPAdjustedStatMatchupEngine(attacker_rating, defender_rating, mob/other)
    var/attacker_rating_value = GetBPAdjustedStatRating(
        attacker_rating,
        other
    )

    var/defender_rating_value = GetStatRatingValue(
        defender_rating
    )

    var/bp_relationship = GetLowerBPMatchupRatio(other)
    var/bp_pressure = GetBPMatchupPressure(other)
    var/suppression = GetBPMatchupSuppressionStages(other)

    return list(
        "Attacker Rating" = attacker_rating,
        "Attacker Effective Rating" = attacker_rating_value,
        "Defender Rating" = defender_rating,
        "Defender Effective Rating" = defender_rating_value,
        "BP Relationship" = bp_relationship,
        "BP Pressure" = bp_pressure,
        "Suppression Stages" = suppression,
        "Effective Matchup Rating" = GetBPAdjustedEffectiveMatchupRating(
            attacker_rating,
            defender_rating,
            other
        )
    )
mob/proc/GetBPMatchupAdjustment(mob/other)
    if(!other)
        return 0.0

    var/ratio = GetBPMatchupRatio(other)

    // Logarithmic BP comparison.
    //
    // ratio = 1.0 means equal BP and therefore zero adjustment.
    // ratio > 1.0 favors the attacker.
    // ratio < 1.0 favors the defender.
    //
    // The logarithmic relationship prevents extremely large BP values
    // from producing proportionally gigantic matchup changes.
    var/adjustment = log(ratio, 10)

    return adjustment * DU_BP_MATCHUP_STRENGTH

mob/proc/GetEffectiveStatMatchup(attacker_rating, defender_rating, mob/other)
    var/rating_difference = GetStatRatingDifference(
        attacker_rating,
        defender_rating
    )

    var/bp_adjustment = GetBPMatchupAdjustment(other)

    // Rating establishes the matchup.
    // BP then modifies that matchup.
    //
    // BP cannot automatically punish an already-negative rating matchup
    // a second time simply because the attacker has lower BP.
    //
    // Likewise, BP cannot erase a strong rating advantage outright.
    //
    // This produces a bounded matchup score that remains centered around
    // the rating comparison.
    var/final_difference = rating_difference

    if(rating_difference > 0)
        final_difference = rating_difference + bp_adjustment
    else
        if(rating_difference < 0)
            if(bp_adjustment > 0)
                final_difference = rating_difference + bp_adjustment
        else
            final_difference = bp_adjustment

    return final_difference

mob/proc/GetEffectiveMatchupRating(attacker_rating, defender_rating, mob/other)
    var/matchup = GetEffectiveStatMatchup(
        attacker_rating,
        defender_rating,
        other
    )

    if(matchup <= -4)
        return STAT_RATING_VERY_LOW

    if(matchup <= -2)
        return STAT_RATING_LOW

    if(matchup < 1)
        return STAT_RATING_AVERAGE

    if(matchup < 2)
        return STAT_RATING_HIGH

    if(matchup < 4)
        return STAT_RATING_VERY_HIGH

    return STAT_RATING_EXTREME

mob/proc/CompareStatMatchupEngine(
    attacker_rating,
    defender_rating,
    mob/other
)
    var/rating_difference = GetStatRatingDifference(
        attacker_rating,
        defender_rating
    )

    var/bp_ratio = GetBPMatchupRatio(other)

    var/bp_adjustment = GetBPMatchupAdjustment(other)

    var/effective_difference = GetEffectiveStatMatchup(
        attacker_rating,
        defender_rating,
        other
    )

    var/effective_rating = GetEffectiveMatchupRating(
        attacker_rating,
        defender_rating,
        other
    )

    return list(
        "attacker_rating" = attacker_rating,
        "defender_rating" = defender_rating,
        "rating_difference" = rating_difference,
        "attacker_bp" = BP,
        "defender_bp" = other ? other.BP : 1,
        "bp_ratio" = bp_ratio,
        "bp_adjustment" = bp_adjustment,
        "effective_difference" = effective_difference,
        "effective_rating" = effective_rating
    )

// ===== END DU 2026 STAT MATCHUP ENGINE : PHASE 5F.3 =====