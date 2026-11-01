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
## Targets in a wheat field further than this are partly hidden (other terrain: TacticalMap.CONCEALMENT).
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
## Mortar ranges, blast and scatter are per role: see Theatre.INDIRECT_DEFAULTS and Unit.indirect.
const MEDKIT_HEAL := 4

# --- Terrain hazards ---
## Fuel drums and oil tanks: the blast when they go up, and how far around it the fire spreads.
const EXPLOSIVES := {
	"car": {"radius": 1.5, "damage_min": 3, "damage_max": 5, "fire": 1.0},
	"fuel": {"radius": 1.5, "damage_min": 3, "damage_max": 5, "fire": 1.0},
	"oil_tank": {"radius": 2.5, "damage_min": 4, "damage_max": 6, "fire": 2.0},
}
## Aim bonus for shooting at an explosive object: it doesn't duck, and an oil tank is hard to miss.
const OBJECT_SHOT_BONUS := {"fuel": 10, "oil_tank": 30, "car": 20}
## Fires burn for this many turns (both sides' turns count), and burn anyone still in them at the start of their turn.
const FIRE_TURNS := 4
const FIRE_DAMAGE := 2
const FIRE_SUPPRESSION := 20
## A mine hits whoever steps on it and the tiles beside it. Explosions still lose EXPLOSION_VS_ARMOR against tanks.
const MINE_RADIUS := 1.0
const MINE_DAMAGE_MIN := 4
const MINE_DAMAGE_MAX := 6
## Chance (%) a soldier spots each hidden mine next to him as he moves. Tank crews never do.
const MINE_SPOT_CHANCE := 50
## Punji traps: a camouflaged pit of sharpened stakes. Harder to spot than a mine; hurts (and wounds) only
## whoever steps in it; tanks crush them harmlessly.
const TRAP_SPOT_CHANCE := 35
const TRAP_DAMAGE_MIN := 2
const TRAP_DAMAGE_MAX := 4
## IEDs: a buried shell with a pressure plate, or set off by the bomb maker who can see it. A big blast that
## shaped charges drive through armour (vehicles lose only IED_VS_ARMOR of it). Hard to spot.
const IED_SPOT_CHANCE := 25
const IED_RADIUS := 1.5
const IED_DAMAGE_MIN := 4
const IED_DAMAGE_MAX := 7
const IED_VS_ARMOR := 1
## How far a bomb maker can be from an IED he sets off (he must see it).
const DETONATE_RANGE := 14.0
## Chance (%) a soldier spots each hidden enemy tunnel entrance next to him as he moves.
const TUNNEL_SPOT_CHANCE := 50
## Napalm: everyone within the radius burns, the ground catches fire, and jungle and grass burn away.
const NAPALM_RADIUS := 1.5
const NAPALM_DAMAGE_MIN := 3
const NAPALM_DAMAGE_MAX := 5
const NAPALM_SUPPRESSION := 60
## Thrown grenades (frag and smoke) land up to this many tiles off target per tile thrown, plus more for
## throwers with aim below THROW_STEADY_AIM and for throwers under fire. They bounce back off walls.
const THROW_SCATTER := 0.12
const THROW_STEADY_AIM := 70
const THROW_SCATTER_PER_AIM := 0.03
const THROW_SCATTER_SUPPRESSED := 0.6
const THROW_SCATTER_PINNED := 1.2

# --- Stray rounds ---
## A missed rocket or tank shell flies on and lands on a random tile from STRAY_SHORT tiles short of the
## target to STRAY_LONG tiles past it, within STRAY_WIDTH tiles of the line of fire (never at the shooter's feet).
const STRAY_SHORT := 1.0
const STRAY_LONG := 3.0
const STRAY_WIDTH := 1.0
## Chance that whoever stands where a stray rocket or shell lands takes a direct hit; otherwise only the blast.
const STRAY_HIT_CHANCE := 50
## A stray rocket bursts on the tile it lands on (SPLASH_DAMAGE, destroys cover there).
const ROCKET_BLAST_RADIUS := 0.5
## A machine gun's miss can hit anyone else beside the target (MG_AREA_RADIUS) or within MG_STRAY_LINE
## tiles of the line of fire, friends included: each in turn with MG_STRAY_CHANCE, for half damage.
const MG_STRAY_LINE := 0.75
const MG_STRAY_CHANCE := 20

# --- Stances, aimed shots and suppressive fire ---
## Crouching makes a soldier a little harder to hit, and a lot harder behind half cover (the low wall hides him).
const CROUCH_DEFENSE := 10
const CROUCH_HALF_COVER_DEFENSE := 20
## Prone soldiers are small targets at range, smaller still behind low cover, but easy to hit up close
## or from a side their cover doesn't face (they lie side-on to the shooter).
const PRONE_DEFENSE := 20
const PRONE_LOW_COVER_DEFENSE := 10
const PRONE_CLOSE_RANGE := 2.5
const PRONE_CLOSE_PENALTY := 15
const PRONE_FLANKED_PENALTY := 10
## Steadier aim crouched or prone; a machine gun set up on its bipod lying down steadier still.
const CROUCH_AIM := 5
const PRONE_AIM := 5
const PRONE_MG_AIM := 15
## Lying flat helps a soldier get over being shot at.
const PRONE_RECOVERY_BONUS := 10
## An aimed shot takes both actions.
const AIMED_SHOT_BONUS := 15
## Suppressive fire: no damage, but this times the weapon's suppression on the target and the full amount
## on the target's allies close by, none of whom recover suppression at the start of their next turn.
## Burns this many rounds.
const SUPPRESSIVE_FIRE_FACTOR := 1.5
const SUPPRESSIVE_FIRE_RADIUS := 1.5
const SUPPRESSIVE_FIRE_AMMO := 2

# --- Tanks ---
## Damage each armour side stops from anti-tank hits, unless the vehicle's role says otherwise (Unit.hull_armor).
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


## The damage a vehicle's armour stops on that side ("front", "side" or "rear").
static func armor_value(target: Unit, side: String) -> int:
	return target.hull_armor.get(side, VEHICLE_ARMOR[side])


## How far (in tiles) a grenade thrown from `from` at `tile` may land off target.
static func throw_scatter(thrower: Unit, from: Vector2i, tile: Vector2i) -> float:
	var scatter := Vector2(from).distance_to(Vector2(tile)) * THROW_SCATTER
	scatter += maxi(0, THROW_STEADY_AIM - thrower.aim) * THROW_SCATTER_PER_AIM
	if thrower.is_pinned():
		scatter += THROW_SCATTER_PINNED
	elif thrower.is_suppressed():
		scatter += THROW_SCATTER_SUPPRESSED
	return scatter


## Whether a hit from `weapon` fired from `from` could do any damage to `target`: small arms bounce off
## tanks, and an anti-tank weapon must be able to beat the armour facing it, even with a critical hit.
static func can_hurt(weapon: Weapon, target: Unit, from: Vector2i) -> bool:
	if not target.vehicle:
		return true
	if not weapon.anti_tank:
		return false
	return weapon.damage_max + weapon.crit_damage > armor_value(target, armor_side(target, from))


## Whether a weapon's misses can hit something else: machine guns, rockets and tank guns.
static func misses_stray(weapon: Weapon) -> bool:
	return weapon.needs_setup or weapon.anti_tank


## Hit, graze and crit chances (0-100) plus the itemised modifiers behind the hit chance.
## `aimed`: an aimed shot (both actions) for extra aim.
## Chance (0-100) to hit an explosive object of `kind` on `tile` from `from`.
static func object_odds(shooter: Unit, from: Vector2i, tile: Vector2i, kind: String) -> int:
	var hit: int = shooter.aim + shooter.weapon.range_modifier(Vector2(from).distance_to(Vector2(tile))) + OBJECT_SHOT_BONUS.get(kind, 0)
	if shooter.is_pinned():
		hit -= PINNED_AIM_PENALTY
	elif shooter.is_suppressed():
		hit -= SUPPRESSED_AIM_PENALTY
	return clampi(hit, 0, 100)


static func shot_odds(map: TacticalMap, shooter: Unit, target: Unit, reaction := false, aimed := false) -> Dictionary:
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

	if aimed:
		modifiers.append(["Aimed shot", AIMED_SHOT_BONUS])
		hit += AIMED_SHOT_BONUS
	var steady := 0
	if shooter.stance == Unit.Stance.CROUCH:
		steady = CROUCH_AIM
	elif shooter.stance == Unit.Stance.PRONE:
		steady = PRONE_MG_AIM if shooter.deployed else PRONE_AIM
	if steady != 0:
		modifiers.append(["%s, steady aim" % Unit.STANCE_NAMES[shooter.stance], steady])
		hit += steady

	var cover := Cover.NONE if reaction else map.cover_against(target.pos, shooter.pos)
	if cover != Cover.NONE:
		var defense: int = COVER_DEFENSE[cover]
		modifiers.append(["%s cover" % Cover.NAMES[cover], -defense])
		hit -= defense
		if target.hunkered:
			var bonus := defense * (HUNKER_MULTIPLIER - 1)
			modifiers.append(["Hunkered", -bonus])
			hit -= bonus

	if not target.vehicle and target.stance != Unit.Stance.STAND:
		var stance_mod := _stance_defense(map, target, cover, distance, reaction)
		modifiers.append(stance_mod)
		hit += stance_mod[1]

	if target.vehicle:
		modifiers.append(["Large target", LARGE_TARGET_BONUS])
		hit += LARGE_TARGET_BONUS
	elif not map.concealment(target.pos).is_empty() and distance > map.concealment(target.pos)["range"]:
		var hidden := map.concealment(target.pos)
		modifiers.append([hidden["label"], -hidden["defense"]])
		hit -= hidden["defense"]

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


## The [label, hit modifier] a crouched or prone target gives a shot.
static func _stance_defense(map: TacticalMap, target: Unit, cover: int, distance: float, reaction: bool) -> Array:
	if target.stance == Unit.Stance.CROUCH:
		if cover == Cover.HALF:
			return ["Crouched behind cover", -CROUCH_HALF_COVER_DEFENSE]
		return ["Crouched", -CROUCH_DEFENSE]
	if distance <= PRONE_CLOSE_RANGE:
		return ["Prone, close range", PRONE_CLOSE_PENALTY]
	if not reaction and cover == Cover.NONE and map.has_cover(target.pos):
		return ["Prone, flanked", PRONE_FLANKED_PENALTY]
	if cover == Cover.HALF:
		return ["Prone behind low cover", -(PRONE_DEFENSE + PRONE_LOW_COVER_DEFENSE)]
	return ["Prone", -PRONE_DEFENSE]
