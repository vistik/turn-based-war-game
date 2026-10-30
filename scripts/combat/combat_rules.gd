class_name CombatRules
extends RefCounted
## Tunable combat numbers and the hit-chance formula.

## Defense given by none / half / full cover.
const COVER_DEFENSE := [0, 20, 40]
## Hunkering down doubles the defense a unit's cover gives.
const HUNKER_MULTIPLIER := 2
## Overwatch shots hit with 70% of normal aim, and targets on the move get no cover.
const REACTION_AIM_FACTOR := 0.7
## Extra crit chance against targets with no cover from the shooter's angle.
const FLANK_CRIT_BONUS := 40
## Rolls just above the hit chance still graze for half damage.
const GRAZE_BAND := 10
const GRENADE_RANGE := 10.0
const GRENADE_RADIUS := 1.5
const GRENADE_DAMAGE_MIN := 3
const GRENADE_DAMAGE_MAX := 4
const GRENADE_SHRED := 1
const MEDKIT_HEAL := 4


## Hit, graze and crit chances (0-100) plus the itemised modifiers behind the hit chance.
static func shot_odds(map: TacticalMap, shooter: Unit, target: Unit, reaction := false) -> Dictionary:
	var distance := Vector2(shooter.pos).distance_to(Vector2(target.pos))
	var modifiers := [["Aim", shooter.aim]]
	var hit := shooter.aim

	var range_mod := shooter.weapon.range_modifier(distance)
	if range_mod != 0:
		modifiers.append(["Range %.1f" % distance, range_mod])
		hit += range_mod

	var cover := Cover.NONE if reaction else map.cover_against(target.pos, shooter.pos)
	if cover != Cover.NONE:
		var defense: int = COVER_DEFENSE[cover]
		modifiers.append(["%s cover" % Cover.NAMES[cover], -defense])
		hit -= defense
		if target.hunkered:
			var bonus := defense * (HUNKER_MULTIPLIER - 1)
			modifiers.append(["Hunkered", -bonus])
			hit -= bonus

	if target.defense != 0:
		modifiers.append(["Defense", -target.defense])
		hit -= target.defense

	if reaction and hit > 0:
		var penalty := hit - roundi(hit * REACTION_AIM_FACTOR)
		modifiers.append(["Reaction shot", -penalty])
		hit -= penalty

	hit = clampi(hit, 0, 100)
	var flanked := not reaction and cover == Cover.NONE
	var crit := shooter.weapon.crit_chance + (FLANK_CRIT_BONUS if flanked else 0)
	return {
		"hit": hit,
		"graze": mini(GRAZE_BAND, 100 - hit) if hit > 0 else 0,
		"crit": clampi(crit, 0, 100),
		"cover": cover,
		"flanked": flanked,
		"distance": distance,
		"modifiers": modifiers,
	}
