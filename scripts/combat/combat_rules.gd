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
## Targets in a wheat field further than this are partly hidden.
const WHEAT_CONCEALMENT := 10
const WHEAT_CONCEALMENT_RANGE := 4.0

# --- Suppression and morale ---
const SUPPRESSED_AIM_PENALTY := 15
const PINNED_AIM_PENALTY := 30
## Extra suppression when a shot actually hits.
const HIT_SUPPRESSION_BONUS := 15
## Machine gun fire also suppresses (at half strength) the target's allies this close to it.
const MG_AREA_RADIUS := 1.5
## Suppression from an explosion to everyone within its radius + 1.
const EXPLOSION_SUPPRESSION := 50
## Suppression lost at the start of each of the unit's turns, plus bonuses for cover and a nearby officer.
const SUPPRESSION_RECOVERY := 35
const COVER_RECOVERY_BONUS := 10
const OFFICER_RECOVERY_BONUS := 25
const OFFICER_RADIUS := 5.0
## Rally removes this much suppression from the officer's allies in OFFICER_RADIUS.
const RALLY_AMOUNT := 50
## When a soldier dies, allies this close may panic (become pinned).
const PANIC_RADIUS := 5.0
const PANIC_CHANCE := 30
const PANIC_WOUNDED_BONUS := 10
const OFFICER_PANIC_REDUCTION := 20
## Losing the officer shakes the whole squad.
const OFFICER_DEATH_SUPPRESSION := 40

# --- Grenades, smoke and mortars ---
const GRENADE_RANGE := 10.0
const GRENADE_RADIUS := 1.5
const GRENADE_DAMAGE_MIN := 3
const GRENADE_DAMAGE_MAX := 4
const GRENADE_SHRED := 1
const SMOKE_RANGE := 8.0
const SMOKE_RADIUS := 1.5
## Smoke lasts this many turns (both sides' turns count, so 4 = two rounds).
const SMOKE_TURNS := 4
const MORTAR_MIN_RANGE := 5.0
const MORTAR_MAX_RANGE := 22.0
const MORTAR_RADIUS := 1.5
const MORTAR_DAMAGE_MIN := 3
const MORTAR_DAMAGE_MAX := 5
## Shells land up to this many tiles off target per tile of distance.
const MORTAR_SCATTER := 0.08
const MEDKIT_HEAL := 4

# --- Tanks ---
## Damage each armour side stops from anti-tank hits.
const VEHICLE_ARMOR := {"front": 3, "side": 1, "rear": 0}
const LARGE_TARGET_BONUS := 10
## Explosions lose this much damage against tanks.
const EXPLOSION_VS_ARMOR := 3
## A tank shell's blast hurts everyone else near where it lands.
const SPLASH_DAMAGE_MIN := 2
const SPLASH_DAMAGE_MAX := 3


## Which armour faces an attacker standing on `from`: the front within 60° of the tank's facing, the rear likewise.
static func armor_side(target: Unit, from: Vector2i) -> String:
	var toward := Vector2(from - target.pos).normalized()
	var alignment := toward.dot(Vector2(target.facing).normalized())
	if alignment > 0.5:
		return "front"
	if alignment < -0.5:
		return "rear"
	return "side"


## Hit, graze and crit chances (0-100) plus the itemised modifiers behind the hit chance.
static func shot_odds(map: TacticalMap, shooter: Unit, target: Unit, reaction := false) -> Dictionary:
	var distance := Vector2(shooter.pos).distance_to(Vector2(target.pos))
	var modifiers := [["Aim", shooter.aim]]
	var hit := shooter.aim

	var range_mod := shooter.weapon.range_modifier(distance)
	if range_mod != 0:
		modifiers.append(["Range %.1f" % distance, range_mod])
		hit += range_mod

	if shooter.is_pinned():
		modifiers.append(["Pinned down", -PINNED_AIM_PENALTY])
		hit -= PINNED_AIM_PENALTY
	elif shooter.is_suppressed():
		modifiers.append(["Suppressed", -SUPPRESSED_AIM_PENALTY])
		hit -= SUPPRESSED_AIM_PENALTY

	var cover := Cover.NONE if reaction else map.cover_against(target.pos, shooter.pos)
	if cover != Cover.NONE:
		var defense: int = COVER_DEFENSE[cover]
		modifiers.append(["%s cover" % Cover.NAMES[cover], -defense])
		hit -= defense
		if target.hunkered:
			var bonus := defense * (HUNKER_MULTIPLIER - 1)
			modifiers.append(["Hunkered", -bonus])
			hit -= bonus

	if target.vehicle:
		modifiers.append(["Large target", LARGE_TARGET_BONUS])
		hit += LARGE_TARGET_BONUS
	elif map.get_terrain(target.pos) == TacticalMap.Terrain.WHEAT and distance > WHEAT_CONCEALMENT_RANGE:
		modifiers.append(["In the wheat", -WHEAT_CONCEALMENT])
		hit -= WHEAT_CONCEALMENT

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
