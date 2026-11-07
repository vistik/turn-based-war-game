class_name CombatRules
extends RefCounted
## Tunable combat numbers and the hit-chance formula.

## Defense given by none / half / full cover.
const COVER_DEFENSE := [0, 20, 40]
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
## Actions per soldier on the first side's opening turn (round 1); everyone else always gets two.
const FIRST_TURN_ACTIONS := 1
## A heavy machine gun fired after moving this turn, off the hip instead of from its bipod.
const HEAVY_MOVED_AIM_PENALTY := 25
## Extra suppression when a shot actually hits.
const HIT_SUPPRESSION_BONUS := 15
## Machine gun fire also suppresses (at half strength) the target's allies this close to it.
const MG_AREA_RADIUS := 2.0
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
const MEDKIT_HEAL := 5
## A medkit also takes this much off the patient's suppression, and may be used on an unhurt man this shaken.
const MEDKIT_CALM := 40
const MEDKIT_STEADIES_AT := 40

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
## How many stages explosions knock off walls, hedges and fences (TacticalMap.damage_edge): [round the tile
## they land on, further out]. A whole wall takes 3 stages to bring down (damaged, breached, gone), a window,
## low wall or fence 2. "direct_heavy": a tank shell or rocket fired at someone behind cover hits that cover.
const WALL_HITS := {
	"grenade": Vector2i(1, 1), "shell": Vector2i(2, 1), "charge": Vector2i(3, 3), "direct_heavy": 2,
}
## A building of two storeys falls in when this share of its outer walls is breached or gone, a taller one at
## COLLAPSE_SHARE_PER_STOREY less per storey above two (never under COLLAPSE_SHARE_MIN). Everyone in it takes
## COLLAPSE_DAMAGE, plus COLLAPSE_FALL_DAMAGE per floor they fall, and is badly shaken.
const COLLAPSE_SHARE := 0.4
const COLLAPSE_SHARE_PER_STOREY := 0.05
const COLLAPSE_SHARE_MIN := 0.25
const COLLAPSE_DAMAGE := [2, 4]
const COLLAPSE_FALL_DAMAGE := 2
const COLLAPSE_SUPPRESSION := 60
## Grenades, shells, rockets and mortar rounds set what burns in their blast alight, for BLAST_FIRE_TURNS: the
## chance per tile by its ground (dry crops and tall grass catch easily, grass and scrub less, roads, rubble,
## water and indoors never), BLAST_FIRE_CENTER more where it lands. Under someone standing in crops or tall
## grass at FIRE_UNDER_UNIT_SHARE of the chance (he burns at the start of his turn unless he gets out); not on
## upper floors.
const BLAST_FIRE_TURNS := 2
## Dry crops and tall grass burn longer.
const LONG_BURN_TURNS := 4
## Under a soldier, fire catches (and spreads) at this share of the usual chance, only in crops and tall grass.
const FIRE_UNDER_UNIT_SHARE := 0.5
## A fire smokes: its tile is full of smoke (blocking sight) while it burns and FIRE_SMOKE_TURNS after.
const FIRE_SMOKE_TURNS := 2
## A soldier who starts his turn beside a fire is shaken by the heat and smoke.
const FIRE_HEAT_SUPPRESSION := 10
const BLAST_FIRE_CHANCE := {
	TacticalMap.Terrain.WHEAT: 0.6, TacticalMap.Terrain.TALL_GRASS: 0.6, TacticalMap.Terrain.TRAMPLED: 0.5,
	TacticalMap.Terrain.ROUGH: 0.3, TacticalMap.Terrain.FLOOR: 0.2, TacticalMap.Terrain.JUNGLE: 0.25,
}
const BLAST_FIRE_CENTER := 0.3
## Once a round, each fire may spread to the tiles beside it (not diagonally), by their ground, and burns
## there for BLAST_FIRE_TURNS (LONG_BURN_TURNS in crops and tall grass). It spreads under a soldier only in
## crops or tall grass, at FIRE_UNDER_UNIT_SHARE of the chance; never under a tank, nor through a wall or hedge
## between the tiles. A fuel drum or oil tank beside a fire may cook off (FIRE_COOK_OFF).
const FIRE_SPREAD_CHANCE := {
	TacticalMap.Terrain.WHEAT: 0.22, TacticalMap.Terrain.TALL_GRASS: 0.22, TacticalMap.Terrain.TRAMPLED: 0.15,
	TacticalMap.Terrain.ROUGH: 0.08, TacticalMap.Terrain.FLOOR: 0.04, TacticalMap.Terrain.JUNGLE: 0.08,
}
const FIRE_COOK_OFF := 0.25
## A mine or IED sets the ground round it alight: each tile in its blast that can burn (not water, roads,
## rubble, trenches or indoors) catches at MINE_FIRE_CHANCE (a soldier's tile only in crops or tall grass, at
## FIRE_UNDER_UNIT_SHARE), and where any tile can burn at least one always does.
const MINE_FIRE_CHANCE := 0.6
## A wall knocked down to a breach or gone throws up brick dust on both sides: smoke (blocking sight) for
## DUST_TURNS, so it hangs through the other side's reply.
const DUST_TURNS := 2
## A building coming down buries its tiles and the ring round them in dust for COLLAPSE_DUST_TURNS.
const COLLAPSE_DUST_TURNS := 4
## Hay bales and crates burn. The chance a blast over one ("blast") or a fire beside it ("spread") sets it
## alight; it burns away (and its cover with it), hay for LONG_BURN_TURNS, a crate for BLAST_FIRE_TURNS.
const OBJECT_BURN_CHANCE := {"hay": {"blast": 0.7, "spread": 0.35}, "crate": {"blast": 0.3, "spread": 0.1}}
## A missed rifle, pistol or SMG round that ends in a car or oil tank may set it off.
const STRAY_COOK_OFF := {"car": 0.15, "oil_tank": 0.1, "fuel": 0.25}
## Blast concussion: an explosion shatters the glass of every window within its radius plus
## WINDOW_SHATTER_REACH (the frame stays, half cover as before).
const WINDOW_SHATTER_REACH := 2.0
## Rubble: a brick, stone or mud wall breached or brought down spills rubble (slow ground) onto the open
## tile on its far side from the blast or gun. A collapsing building spills onto each open tile round it at
## COLLAPSE_SPILL_CHANCE.
const COLLAPSE_SPILL_CHANCE := 0.6
## Tree bursts: a mortar or artillery shell landing among trees (one within TREE_BURST_REACH of where it
## comes down) bursts in the branches and rains splinters: TREE_BURST_RADIUS wider and TREE_BURST_DAMAGE
## more. Trees a blast catches are shattered to splintered scrub, or (off the centre, at TREE_FELL_CHANCE)
## brought down as a fallen trunk: half cover that blocks the way.
const TREE_BURST_REACH := 1.0
const TREE_BURST_RADIUS := 0.5
const TREE_BURST_DAMAGE := 1
const TREE_FELL_CHANCE := 0.5
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
## A missed rifle, pistol or SMG round flies on up to ROUND_FLIES_ON tiles past the target, until a full wall,
## a glazed window (which it shatters) or a tree or other solid object stops it. Anyone within
## STRAY_ROUND_LINE tiles of its flight, friends included, is hit with STRAY_ROUND_CHANCE each in turn
## (nearest the shooter first, only one), for half damage.
const ROUND_FLIES_ON := 5.0
const STRAY_ROUND_LINE := 0.5
const STRAY_ROUND_CHANCE := 10

# --- Stances, steady shots and suppressive fire ---
## Prone soldiers are small targets at range, smaller still behind low cover, but easy to hit up close
## or from a side their cover doesn't face (they lie side-on to the shooter).
const PRONE_DEFENSE := 20
const PRONE_LOW_COVER_DEFENSE := 10
const PRONE_CLOSE_RANGE := 2.5
const PRONE_CLOSE_PENALTY := 15
const PRONE_FLANKED_PENALTY := 10
## Steadier aim prone; a heavy machine gun on its bipod lying down steadier still.
const PRONE_AIM := 5
const PRONE_MG_AIM := 15
## Lying flat helps a soldier get over being shot at.
const PRONE_RECOVERY_BONUS := 10
## A steady shot: fired with both actions left (nothing else done that turn) for extra aim.
const STEADY_SHOT_BONUS := 15
## Suppressive fire, machine guns only: no damage, but this times the weapon's suppression on the target and the full amount
## on the target's allies close by, none of whom recover suppression at the start of their next turn.
## Burns this many rounds.
const SUPPRESSIVE_FIRE_FACTOR := 1.6
const SUPPRESSIVE_FIRE_RADIUS := 2.5
const SUPPRESSIVE_FIRE_AMMO := 2

# --- Height ---
## Aim bonus for shooting down at a target a level or more below (see TacticalMap.cover_against for what
## height does to cover).
const HIGH_GROUND_AIM := 10

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
	return weapon.heavy or weapon.anti_tank


## Whether a weapon's misses fly on as single rounds (see ROUND_FLIES_ON): rifles, pistols, SMGs and sniper
## rifles. Machine guns, rockets and shells stray their own way (misses_stray); grenade launchers and
## mortars don't.
static func misses_fly_on(weapon: Weapon) -> bool:
	return not misses_stray(weapon) and weapon.blast_radius <= 0.0


## Chance (0-100) to hit an explosive object of `kind` on `tile` from `from`.
## A bazooka, Panzerschreck or RPG can be fired at any tile its gunner can see, enemy or not: a still patch of
## ground is easier to hit than a man (GROUND_SHOT_BONUS). A miss lands near it, like any stray rocket.
const GROUND_SHOT_BONUS := 20


static func fires_at_ground(weapon: Weapon) -> bool:
	return weapon.anti_tank


static func ground_odds(shooter: Unit, from: Vector2i, tile: Vector2i) -> int:
	var hit: int = shooter.aim + shooter.weapon.range_modifier(Vector2(from).distance_to(Vector2(tile))) + GROUND_SHOT_BONUS
	if shooter.is_pinned():
		hit -= PINNED_AIM_PENALTY
	elif shooter.is_suppressed():
		hit -= SUPPRESSED_AIM_PENALTY
	return clampi(hit, 0, 100)


static func object_odds(shooter: Unit, from: Vector2i, tile: Vector2i, kind: String) -> int:
	var hit: int = shooter.aim + shooter.weapon.range_modifier(Vector2(from).distance_to(Vector2(tile))) + OBJECT_SHOT_BONUS.get(kind, 0)
	if shooter.is_pinned():
		hit -= PINNED_AIM_PENALTY
	elif shooter.is_suppressed():
		hit -= SUPPRESSED_AIM_PENALTY
	return clampi(hit, 0, 100)


## Hit, graze and crit chances (0-100) plus the itemised modifiers behind the hit chance.
## `steady`: a steady shot (fired with both actions left) for extra aim.
static func shot_odds(map: TacticalMap, shooter: Unit, target: Unit, reaction := false, steady := false) -> Dictionary:
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

	if shooter.weapon.heavy and shooter.moved and not reaction:
		modifiers.append(["Fired on the move", -HEAVY_MOVED_AIM_PENALTY])
		hit -= HEAVY_MOVED_AIM_PENALTY
	if steady:
		modifiers.append(["Steady shot", STEADY_SHOT_BONUS])
		hit += STEADY_SHOT_BONUS
	if shooter.stance == Unit.Stance.PRONE:
		var prone_aim := PRONE_MG_AIM if shooter.weapon.heavy else PRONE_AIM
		modifiers.append(["Prone, steady aim", prone_aim])
		hit += prone_aim

	if map.has_height() and map.floor_height(shooter.pos, shooter.level) - map.floor_height(target.pos, target.level) >= 1.0:
		modifiers.append(["High ground", HIGH_GROUND_AIM])
		hit += HIGH_GROUND_AIM

	var cover := Cover.NONE if reaction else map.cover_against(target.pos, shooter.pos, target.level, shooter.level,
			not target.vehicle and target.stance == Unit.Stance.PRONE)
	if cover != Cover.NONE:
		var defense: int = COVER_DEFENSE[cover]
		modifiers.append(["%s cover" % Cover.NAMES[cover], -defense])
		hit -= defense

	if not target.vehicle and target.stance != Unit.Stance.STAND:
		var stance_mod := _stance_defense(map, target, cover, distance, reaction)
		modifiers.append(stance_mod)
		hit += stance_mod[1]

	if target.vehicle:
		modifiers.append(["Large target", LARGE_TARGET_BONUS])
		hit += LARGE_TARGET_BONUS
	elif target.level == 0 and not map.concealment(target.pos).is_empty() and distance > map.concealment(target.pos)["range"]:
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


## The [label, hit modifier] a prone target gives a shot.
static func _stance_defense(map: TacticalMap, target: Unit, cover: int, distance: float, reaction: bool) -> Array:
	if distance <= PRONE_CLOSE_RANGE:
		return ["Prone, close range", PRONE_CLOSE_PENALTY]
	if not reaction and cover == Cover.NONE and map.has_cover(target.pos, target.level):
		return ["Prone, flanked", PRONE_FLANKED_PENALTY]
	if cover == Cover.HALF:
		return ["Prone behind low cover", -(PRONE_DEFENSE + PRONE_LOW_COVER_DEFENSE)]
	return ["Prone", -PRONE_DEFENSE]
