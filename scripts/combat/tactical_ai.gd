class_name TacticalAI
extends RefCounted
## Utility AI for one team. It plays fair: it only knows what its team can see, plus where it last saw enemies.
## Every call to decide() scores all plans for all units and returns the best one as a single engine command
## (or end_turn); act() also applies it and returns the resulting events.
##
## Scores are in "expected damage x 10" units so offence, defence, objectives and positioning can be compared.

const KILL_BONUS := 40.0
## How much a point of expected incoming damage at a tile counts against standing there.
const DANGER_WEIGHT := 0.8
## Danger from enemies we only remember (not currently seen) counts this much.
const REMEMBERED_THREAT := 0.5
## Score per level of cover (half = 1, full = 2) on the best side of a tile, and per level of cover
## facing where the enemy is (or is expected to come from). Ending a move in the open costs extra.
const COVER_WEIGHT := 6.0
const FACING_COVER_WEIGHT := 9.0
const OPEN_GROUND_PENALTY := 10.0
## Score lost per tile of distance from the goal when no enemy is in sight.
const APPROACH_WEIGHT := 3.0
## Score lost per tile away from the role's preferred range (its "range") to the nearest seen enemy.
const RANGE_WEIGHT := 1.5
## Score per point of suppression a shot or blast adds to an enemy.
const SUPPRESSION_VALUE := 0.15
## Standing on an objective we don't hold / already hold, and the pull toward the nearest one we don't hold.
const OBJECTIVE_TAKE := 14.0
const OBJECTIVE_HOLD := 6.0
const OBJECTIVE_PULL := 1.0
## Points behind the enemy at which taking objectives matters twice as much (and so on, up to 3x).
const URGENCY_POINTS := 2.0
## Allies this close together risk sharing a grenade or shell.
const CROWDING_PENALTY := 4.0
## Danger of standing where a mortar shell is about to land.
const STRIKE_DANGER := 45.0
const GRENADE_COST := 20.0
## Harm a stray round (see Battle.stray_risks) may do to our own soldiers counts this many times over, and
## a shot that would hit one of them more than FRIENDLY_FIRE_LIMIT of the time costs FRIENDLY_FIRE_PENALTY more.
## Strays into enemies count at STRAY_ENEMY_VALUE.
const FRIENDLY_FIRE_WEIGHT := 3.0
const FRIENDLY_FIRE_LIMIT := 0.12
const FRIENDLY_FIRE_PENALTY := 25.0
const STRAY_ENEMY_VALUE := 0.5
const MORTAR_COST := 10.0
## Enemies may move before a mortar shell lands, so only part of its value counts.
const MORTAR_CERTAINTY := 0.5
## Observed fire comes down at once; only the scatter keeps it from being certain.
const MORTAR_OBSERVED_CERTAINTY := 0.85
const OVERWATCH_VALUE := 10.0  # kept for a quiet front: see _overwatch_value
## Score lost for a round spent on fuel drums or an oil tank instead of a soldier.
const OBJECT_SHOT_COST := 6.0
## Standing next to something that can blow up, while enemies are about.
const EXPLOSIVE_NEARBY_PENALTY := 8.0
const RELOAD_EMPTY_VALUE := 30.0
const MEDKIT_VALUE_PER_HP := 10.0
## A medic is drawn toward hurt or shaken allies (per tile of distance to the nearest), and they toward him.
const MEDIC_PULL := 0.8
const RALLY_VALUE := 0.25
## Rallying a soldier out of pinned down, or out of suppressed, and rallying one who can still act this turn.
const RALLY_UNPIN := 25.0
const RALLY_STEADY := 10.0
const RALLY_CAN_ACT := 10.0
## An officer is drawn toward shaken soldiers out of his reach (per tile beyond it).
const OFFICER_PULL := 1.5
## Suppressive fire: the share of a pinned enemy's best shot at us it takes away, and the bonus when the gun
## can't hit well (target in good cover) or catches several.
const THREAT_DENIAL := 0.5
const SUPPRESS_BONUS := 8.0
## Smoke: the share of the danger it takes off allies in it, the cost per ally of ours whose shot it blocks,
## and the cost of the grenade. Only worth throwing for allies in real danger (SMOKE_DANGER).
const SMOKE_RELIEF := 0.7
const SMOKE_BLOCKS_SHOT := 12.0
const SMOKE_COST := 10.0
const SMOKE_DANGER := 15.0
## Overwatch: the chance an enemy moves (lower if he's on overwatch or holding an objective), the share of
## the other lanes' value (only one shot fires), and the most it's worth against a shot available now.
const OVERWATCH_MOVE_CHANCE := 0.6
const OVERWATCH_SETTLED_CHANCE := 0.3
const OVERWATCH_OTHER_LANES := 0.25
const OVERWATCH_VS_SHOT := 0.8
## A sniper who moves gets his shot next turn: worth this share of it now.
const NEXT_TURN_SHOT := 0.5
## Clearing a known enemy mine or tunnel entrance, more if it's in the way or in an objective.
const CLEAR_MINE_VALUE := 6.0
const CLEAR_MINE_IN_WAY := 15.0
## The bomb maker keeps his IEDs in sight (per IED he can see from a tile).
const IED_WATCH_VALUE := 6.0
## Heavy weapons and shells at a building with enemies inside: per enemy, per share of the way to collapse.
const COLLAPSE_VALUE := 15.0
## Standing beside a fire, or on dry crops or grass that a fire next to it may spread to.
const FIRE_BESIDE_PENALTY := 6.0
const FIRE_CATCH_PENALTY := 4.0
## What being prone is worth against, for the slower movement it means from now on.
const STANCE_MOBILITY_COST := {Unit.Stance.STAND: 0.0, Unit.Stance.PRONE: 12.0}
## A stance's effect on incoming fire lasts beyond the next enemy turn, so it counts this many times over.
const STANCE_PERSISTENCE := 2.0
## Pinning an enemy (or just suppressing one) through their next turn with suppressive fire, and the rounds it burns.
const PIN_VALUE := 30.0
const SUPPRESS_STATE_VALUE := 6.0
const SUPPRESSIVE_AMMO_COST := 2.0
## Prone mortar and anti-tank teams can't use their weapon.
const PRONE_WEAPON_PENALTY := 12.0
## Going through the tunnels uses the whole turn; a hidden punji trap is worth this much (more on an
## objective's approaches or a trail), but not with enemies close enough to see it being laid.
const TUNNEL_COST := 4.0
## Setting off an IED spends it (and the bomb maker's turn), so it should catch someone.
const DETONATE_COST := 8.0
const TRAP_VALUE := 6.0
const TRAP_OBJECTIVE_BONUS := 6.0
const TRAP_TRAIL_BONUS := 3.0
## Rounds without seeing an enemy before the AI is fully impatient and pushes forward.
const PATIENCE_ROUNDS := 3.0
## Worth of each level of height a soldier stands at (on top of what it does for his shots and cover).
const HEIGHT_WEIGHT := 2.0

## Game plans: each side picks one when the battle starts (from the battle's seed, so replays and saves play
## out the same) and it shapes the whole game: where the side goes, which objectives it goes for and in what
## order, how tight it keeps together and how bold it is. Keys a plan may set (anything left out is as usual):
##   "weight": how often it is picked; "objectives": needs at least this many objectives;
##   "vehicle": needs a tank;
##   "lane": -1 (our left) or 1 (our right) to come in along that flank, "wings" to split the force and take both;
##   "focus": which objectives to go for first: "pair" (two neighbours, then dig in on them), "left", "right",
##            "centre", "wings" (each wing its own side) or "home" (the one nearest our start);
##   "cohesion": keep close together; "escort": the infantry follow behind the tanks;
##   "ambush": share of the battle spent waiting near home before the counterattack;
##   "aggression" / "urgency": the least they ever are; "patience": how much slower impatience grows;
##   scales on the usual weights: "danger", "open_ground", "kill", "objective_pull", "overwatch";
##   "range": tiles further out than the role's usual range to fight from.
const STRATEGIES := {
	"broad_front": {"name": "Broad front", "text": "advance on a wide front and take what it can", "weight": 2.0},
	"hold_two": {"name": "Take two and hold", "text": "take two neighbouring objectives, then dig in on them",
			"weight": 2.0, "objectives": 2, "focus": "pair", "overwatch": 1.3},
	"left_hook": {"name": "Left hook", "text": "swing wide around our left, rolling up the objectives from that side",
			"lane": -1, "focus": "left"},
	"right_hook": {"name": "Right hook", "text": "swing wide around our right, rolling up the objectives from that side",
			"lane": 1, "focus": "right"},
	"centre_punch": {"name": "Punch through the centre", "text": "drive together, straight through the middle",
			"focus": "centre", "cohesion": true, "aggression": 0.3},
	"pincer": {"name": "Pincer", "text": "split in two and come in on both flanks", "lane": "wings", "focus": "wings"},
	"armoured_spearhead": {"name": "Armoured spearhead", "text": "the tanks lead, the infantry follow in their cover",
			"weight": 2.0, "vehicle": true, "escort": true, "aggression": 0.3},
	"ambush": {"name": "Wait and counterattack", "text": "sit tight near home and let the enemy come, then strike back",
			"ambush": 0.4, "focus": "home", "overwatch": 1.6},
	"blitz": {"name": "All-out push", "text": "rush forward and accept the losses",
			"aggression": 0.8, "urgency": 0.5, "danger": 0.7, "open_ground": 0.6, "overwatch": 0.5},
	"attrition": {"name": "Bleed them", "text": "fight from good cover at long range and make every shot count",
			"kill": 1.3, "objective_pull": 0.4, "range": 1.5, "danger": 1.2, "patience": 2.0},
}
## Flank lanes run this share of half the map's width out from the centre line, and a soldier may stray this
## far from his lane before it costs. Lanes fade out as he closes on his goal.
const LANE_SHARE := 0.55
const LANE_SLACK := 3.0
const LANE_WEIGHT := 0.6
const LANE_FADE := 8.0
## Punching through the centre: score lost per tile further than COHESION_RADIUS from the rest.
const COHESION_RADIUS := 4.0
const COHESION_WEIGHT := 0.8
## Armoured spearhead: infantry lose this per tile ahead of the nearest tank and per tile beyond
## ESCORT_RADIUS from it; tanks don't get further than TANK_LEASH ahead of their infantry.
const ESCORT_AHEAD_WEIGHT := 3.0
const ESCORT_RADIUS := 5.0
const ESCORT_CLOSE_WEIGHT := 1.0
const TANK_LEASH := 7.0
## Digging in on held objectives, and waiting near home before a counterattack (per tile too far out).
const DIG_IN_PULL := 4.0
const ANCHOR_PULL := 1.5
## Behind by this much urgency with this share of the battle gone, any plan becomes an all-out push.
const DESPERATE_URGENCY := 1.0
const DESPERATE_SHARE := 0.6

var battle: Battle
var team: int
## Enemy id -> tile where we last saw them.
var _last_seen := {}
## Where we expect the enemy before we have seen anyone: their starting area.
var _objective: Vector2
## Once contact is lost, we search the middle of the area our team can't currently see.
var _searching := false
var _search_goal: Vector2
## Rounds in a row our team started without any enemy in sight.
var _quiet_rounds := 0
var _round := -1
## 0 = cautious .. 1 = impatient; grows while nothing happens, to break overwatch standoffs.
var _aggression := 0.0
## 0 while level or ahead on points, growing as the enemy pulls ahead: objectives then outweigh caution.
var _urgency := 0.0
## Cache of tile-to-tile sight, keyed by Vector4i(from, to); sight depends only on the map, so it is kept
## from one decision to the next until the map changes (its revision moves on: walls fall, smoke drifts...).
var _sight_cache := {}
var _sight_revision := -1
## Per decision: where each seen enemy is likely to step next (_likely_steps), by unit id.
var _step_cache := {}
## While a decision is being worked out, the enemies we see (_seen_enemies), so scoring thousands of shots
## doesn't look them up again for each one; null otherwise.
var _seen_now: Variant = null
## The floor the unit being judged would stand on at the tile being judged (-1: its own floor at its own
## tile, else the ground).
var _at_level := -1

## The game plan (a key of STRATEGIES), and every plan played so far this battle, in order.
var strategy := "broad_front"
var plans: Array[String] = []
## Where our side started, which way the enemy lies from there, and our left (perpendicular to that).
var _home: Vector2
var _forward := Vector2.RIGHT
var _left := Vector2.UP
## Unit id -> -1 (left wing) or 1 (right wing), from where they started.
var _wings := {}
## Indices of the two objectives a "pair" plan goes for, left one first.
var _pair: Array[int] = []
## A "Wait and counterattack" plan has struck back.
var _sprung := false
## Per-decide cache of each unit's goal under the plan: unit id -> Vector2 (Vector2.INF: none), and of
## _plan_shape(): -1 - unit id -> Dictionary.
var _plan_goals := {}


func _init(p_battle: Battle, p_team: int) -> void:
	battle = p_battle
	team = p_team
	var sum := Vector2.ZERO
	var count := 0
	for u in battle.units:
		if u.team != team:
			sum += Vector2(u.pos)
			count += 1
	_objective = sum / maxi(1, count)
	_read_the_ground()
	set_strategy(_pick_strategy())


## The AI's memory, for save games.
func to_dict() -> Dictionary:
	return {"last_seen": _last_seen.duplicate(), "searching": _searching, "search_goal": _search_goal, "quiet_rounds": _quiet_rounds, "round": _round,
		"objective": _objective, "strategy": strategy, "plans": plans.duplicate(), "home": _home, "forward": _forward,
		"wings": _wings.duplicate(), "pair": _pair.duplicate(), "sprung": _sprung}


func load_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	_last_seen = data["last_seen"].duplicate()
	_searching = data["searching"]
	_search_goal = data["search_goal"]
	_quiet_rounds = data["quiet_rounds"]
	_round = data["round"]
	if data.has("strategy"):
		_objective = data["objective"]
		_home = data["home"]
		_forward = data["forward"]
		_left = Vector2(_forward.y, -_forward.x)
		_wings = data["wings"].duplicate()
		_pair.assign(data["pair"])
		_sprung = data["sprung"]
		strategy = data["strategy"]
		plans.assign(data["plans"])


func act() -> Array:
	if battle.winner != -1 or battle.current_team != team:
		return []
	var command := decide()
	var events := battle.execute(command)
	if events.is_empty() and command["cmd"] != "end_turn":
		push_warning("AI command %s was rejected; ending turn" % command)
		return battle.execute({"cmd": "end_turn"})
	return events


## The AI's next command, as data for Battle.execute().
func decide() -> Dictionary:
	if battle.winner != -1 or battle.current_team != team:
		return {"cmd": "end_turn"}
	if _sight_revision != battle.map.revision:
		_sight_cache.clear()
		_sight_revision = battle.map.revision
	_step_cache.clear()
	_plan_goals.clear()
	_remember()
	var seen := _seen_enemies()
	var new_round := battle.round_number != _round
	if new_round:
		_round = battle.round_number
		_quiet_rounds = _quiet_rounds + 1 if seen.is_empty() else 0
	if not seen.is_empty():
		_quiet_rounds = 0
	_urgency = clampf((battle.victory_points[1 - team] - battle.victory_points[team]) / URGENCY_POINTS, 0.0, 2.0)
	if new_round:
		_review_strategy()
	var patience := _plan_float("patience", 1.0) * (3.0 if _digging_in() else 1.0)
	_aggression = clampf(_quiet_rounds / (PATIENCE_ROUNDS * patience), 0.0, 1.0)
	if _ambushing():
		_aggression = 0.0
	else:
		_aggression = maxf(_aggression, _plan_float("aggression", 0.0))
	_urgency = maxf(_urgency, _plan_float("urgency", 0.0))
	if _searching and seen.is_empty() and _last_seen.is_empty():
		_search_goal = _fog_center()
	var best := {}
	_seen_now = seen
	for u in battle.alive_units(team):
		if u.actions <= 0:
			continue
		var plan := _best_plan(u, seen)
		if not plan.is_empty() and (best.is_empty() or plan["value"] > best["value"]):
			best = plan
	_seen_now = null
	if best.is_empty():
		return {"cmd": "end_turn"}
	return _command(best)


# --- Planning ---

func _best_plan(u: Unit, seen: Array[Unit]) -> Dictionary:
	var map := battle.map
	var here := u.pos
	var stay := _position_score(u, here, seen)
	var plans: Array[Dictionary] = []

	if battle.can_fire(u) == "":
		for e in seen:
			if battle.can_see(u, e):
				plans.append(_plan(u, "shoot", stay + _shot_value(u, here, e, Battle.is_steady(u)), e))
				if battle.can_suppress(u, e) == "":
					plans.append(_plan(u, "suppress", stay + _suppress_value(u, e, seen), e))
		for tile in _explosives_near(seen):
			if battle.can_shoot_object(u, tile) == "":
				var kind := battle.map.get_object_kind(tile)
				var spec: Dictionary = CombatRules.EXPLOSIVES[kind]
				var chance := CombatRules.object_odds(u, here, tile, kind) / 100.0
				var value := _blast_value(tile, spec["radius"], spec["damage_min"], spec["damage_max"], 0, seen)
				if value > 0.0:
					plans.append(_plan(u, "shoot_object", stay + value * chance - OBJECT_SHOT_COST, null, tile))
		if not u.is_pinned():
			plans.append(_plan(u, "overwatch", stay + _overwatch_value(u, here, seen)))
	if u.grenades > 0:
		for tile in _tiles_around(seen):
			if battle.can_throw_grenade(u, tile) == "":
				var value := _grenade_value(u, tile, seen)
				if value > 0.0:
					plans.append(_plan(u, "grenade", stay + value - GRENADE_COST, null, tile))
	if not u.indirect.is_empty() and u.mortar_rounds > 0 and (u.actions >= Unit.ACTIONS_PER_TURN or not u.indirect["still"]):
		var spec := u.indirect
		for tile in _tiles_around(seen):
			if battle.can_fire_mortar(u, tile, "he") == "":
				# Fire lands at once; blind fire scatters wider (firing_scatter) and is less sure to land on anyone.
				var observed := battle.is_observed(u, tile)
				var value := _blast_value(tile, spec["radius"] + battle.firing_scatter(u, tile) * 0.5,
						spec["damage"][0], spec["damage"][1], 0, seen)
				if value > 0.0:
					value += _collapse_bonus(tile, seen)
					plans.append(_plan(u, "mortar", stay + value * (MORTAR_OBSERVED_CERTAINTY if observed else MORTAR_CERTAINTY) - MORTAR_COST, null, tile))
	if u.medkits > 0:
		for ally in battle.alive_units(team):
			var value := _medkit_value(ally)
			if value > 0.0 and battle.can_use_medkit(u, ally) == "":
				plans.append(_plan(u, "medkit", stay + value, ally))
	if battle.can_rally(u) == "":
		plans.append(_plan(u, "rally", stay + _rally_value(u)))
	# Smoke over allies in danger, most of all pinned ones who can't get out by themselves.
	if u.smoke_grenades > 0 and u.stance != Unit.Stance.PRONE and not seen.is_empty():
		for ally in battle.alive_units(team):
			if battle.can_throw_smoke(u, ally.pos) == "":
				var value := _smoke_value(ally.pos, seen)
				if value > 0.0:
					plans.append(_plan(u, "smoke", stay + value, null, ally.pos))
	# Clearing an enemy mine or tunnel entrance next to us, when it's quiet enough.
	if not u.vehicle and battle.theatre().trap_team() != team and _danger(u, here, seen) < 10.0:
		for d: Vector2i in TacticalMap.DIRS8:
			var tile := here + d
			if battle.can_clear_mine(u, tile) == "":
				plans.append(_plan(u, "clear_mine", stay + _clear_value(u, tile), null, tile))
	if u.ammo < u.weapon.clip_size:
		var reload_value := RELOAD_EMPTY_VALUE if u.ammo == 0 else (4.0 if seen.is_empty() else 0.0)
		plans.append(_plan(u, "reload", stay + reload_value))
	if u.vehicle:
		# Turning on the spot (a move to its own tile with a facing) to put the front armour toward the threat.
		var facing := u.facing
		for dir: Vector2i in Pathfinder.HEADINGS:
			if battle.can_move(u, here, u.level, dir) == "":
				u.facing = dir
				var turn := _plan(u, "move", _position_score(u, here, seen) - 2.0, null, here)
				turn["facing"] = dir
				plans.append(turn)
		u.facing = facing

	if not u.vehicle:
		plans.append_array(_stance_plans(u, seen))

	# Down one tunnel entrance and up another.
	if u.has_trait("tunnels") and map.tunnel_owner(here) == team and u.actions >= Unit.ACTIONS_PER_TURN:
		for dest: Vector2i in map.get_tunnels():
			if battle.can_tunnel(u, dest) == "":
				plans.append(_plan(u, "tunnel", _position_score(u, dest, seen) - TUNNEL_COST, null, dest))
	# Punji traps where the enemy will come, while nobody is watching.
	if u.traps > 0 and u.has_trait("traps"):
		var watched := seen.any(func(e: Unit) -> bool: return Vector2(e.pos).distance_to(Vector2(here)) <= 6.0)
		if not watched:
			for d: Vector2i in TacticalMap.DIRS8:
				if battle.can_lay_trap(u, here + d) == "":
					plans.append(_plan(u, "trap", stay + _trap_value(here + d), null, here + d))

	# The bomb maker sets off an IED when enemies walk close to it.
	if u.has_trait("detonator") and u.actions > 0:
		for tile: Vector2i in battle.mines_known_to(team):
			if battle.can_detonate(u, tile) == "":
				var value := _blast_value(tile, CombatRules.IED_RADIUS, CombatRules.IED_DAMAGE_MIN, CombatRules.IED_DAMAGE_MAX, 0, seen)
				if value > 0.0:
					plans.append(_plan(u, "detonate", stay + value - DETONATE_COST, null, tile))

	# A sniper who has fired stays put.
	var reach := {} if u.weapon.fires_standing_still() and u.fired else battle.reachable(u)
	for tile: Vector2i in reach:
		# Every floor of the tile within a move (on maps with height), else just the tile.
		var levels: Dictionary = reach[tile].get("levels", {reach[tile]["level"]: reach[tile]["cost"]})
		for level: int in levels:
			if (tile == here and level == u.level) or levels[level] > u.current_mobility() + 0.001:
				continue
			var facing := u.facing
			if u.vehicle:
				# Judge the spot with the hull facing the way it will end up.
				u.facing = reach[tile]["facing"]
			_at_level = level
			var value := _position_score(u, tile, seen)
			if u.actions >= 2:
				value += _followup_value(u, tile, seen)
			_at_level = -1
			u.facing = facing
			var plan := _plan(u, "move", value, null, tile)
			if levels.size() > 1 or level != 0:
				plan["level"] = level
			plans.append(plan)

	var best := {}
	for plan in plans:
		if best.is_empty() or plan["value"] > best["value"]:
			best = plan
	return best


func _plan(u: Unit, kind: String, value: float, target: Unit = null, tile := Vector2i.ZERO) -> Dictionary:
	return {"unit": u, "kind": kind, "value": value, "target": target, "tile": tile}


## Going prone or standing up on the spot (then the best thing to do there with the action left), and for a
## prone soldier, standing up to move further than it could crawl.
func _stance_plans(u: Unit, seen: Array[Unit]) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	var here := u.pos
	var current := u.stance
	var mobility_weight := 0.5 if u.is_pinned() else 1.0
	var stay := _position_score(u, here, seen)
	for stance: int in [Unit.Stance.STAND, Unit.Stance.PRONE]:
		if battle.can_change_stance(u, stance) != "":
			continue
		u.stance = stance as Unit.Stance
		u.actions -= 1
		# A stance keeps paying off (or costing) for as long as the soldier holds the spot.
		var value: float = stay + (_position_score(u, here, seen) - stay) * STANCE_PERSISTENCE \
				- (STANCE_MOBILITY_COST[stance] - STANCE_MOBILITY_COST[current]) * mobility_weight
		if u.actions > 0:
			value += _stay_followup_value(u, seen)
		if stance == Unit.Stance.PRONE:
			value += mini(u.suppression, CombatRules.PRONE_RECOVERY_BONUS) * SUPPRESSION_VALUE * 2.0
			if not u.indirect.is_empty() or u.weapon.kind == "at":
				value -= PRONE_WEAPON_PENALTY
		if stance == Unit.Stance.STAND and u.actions > 0 and not u.is_pinned():
			# Up, then a full-speed move with the action left.
			var reach := battle.reachable(u)
			for tile: Vector2i in reach:
				if tile != here:
					_at_level = reach[tile]["level"]
					value = maxf(value, _position_score(u, tile, seen) + STANCE_MOBILITY_COST[current])
					_at_level = -1
		u.actions += 1
		u.stance = current
		var plan := _plan(u, "stance", value)
		plan["stance"] = stance
		plans.append(plan)
	return plans


## Best use of an action left over when staying on the spot: shoot, overwatch or reload.
func _stay_followup_value(u: Unit, seen: Array[Unit]) -> float:
	if u.ammo == 0:
		return RELOAD_EMPTY_VALUE
	if battle.can_fire(u) != "":
		return 0.0
	var best := _overwatch_value(u, u.pos, seen)
	for e in seen:
		if battle.can_see(u, e):
			best = maxf(best, _shot_value(u, u.pos, e))
	return best


func _command(plan: Dictionary) -> Dictionary:
	var command := {"cmd": plan["kind"], "unit": plan["unit"].id}
	if plan["target"] != null:
		command["target"] = plan["target"].id
	if plan["kind"] in ["move", "grenade", "smoke", "mortar", "shoot_object", "tunnel", "trap", "detonate", "clear_mine"]:
		command["tile"] = plan["tile"]
	if plan["kind"] == "stance":
		command["stance"] = plan["stance"]
	if plan.has("level"):
		command["level"] = plan["level"]
	if plan.has("facing"):
		command["facing"] = plan["facing"]
	if plan["kind"] == "mortar":
		command["kind"] = "he"
	return command


## What a punji trap on the tile is worth: more on the way into an objective (from the enemy's side) or on a trail.
func _trap_value(tile: Vector2i) -> float:
	var value := TRAP_VALUE
	for objective in battle.objectives:
		var center: Vector2 = objective["center"]
		var distance := (Vector2(tile) + Vector2(0.5, 0.5)).distance_to(center)
		var enemy_side := (tile.x < center.x) == (team == 1)
		if distance <= float(objective["radius"]) + 3.0 and enemy_side:
			value += TRAP_OBJECTIVE_BONUS
			break
	if battle.map.get_terrain(tile) == TacticalMap.Terrain.ROAD:
		value += TRAP_TRAIL_BONUS
	return value


## How good it is to stand on a tile at the end of an action: cover, danger, objectives, range and approach.
func _position_score(u: Unit, tile: Vector2i, seen: Array[Unit]) -> float:
	var map := battle.map
	var score := 0.0
	var level := _level_of(u, tile)
	if not u.vehicle:
		var best_cover := Cover.NONE
		for d: Vector2i in TacticalMap.DIRS4:
			best_cover = maxi(best_cover, map.cover_toward(tile, d, level))
		score += best_cover * COVER_WEIGHT
		# Cover only helps on the side the shots come from: toward the enemies we know of, else the goal.
		var threats := _threats(seen)
		var facing_cover := 0.0
		if threats.is_empty():
			facing_cover = map.cover_against(tile, Vector2i(_goal(tile).round()), level)
		else:
			var weights := 0.0
			for threat: Array in threats:
				facing_cover += map.cover_against(tile, threat[1], level, threat[3]) * threat[2]
				weights += threat[2]
			facing_cover /= weights
		score += facing_cover * FACING_COVER_WEIGHT
		if best_cover == Cover.NONE:
			score -= OPEN_GROUND_PENALTY * (1.0 if not seen.is_empty() else 0.5) * _plan_float("open_ground", 1.0)
		if map.has_height():
			score += map.floor_height(tile, level) * HEIGHT_WEIGHT

	var caution := 2.0 - float(u.hp) / u.max_hp
	score -= _danger(u, tile, seen) * DANGER_WEIGHT * caution * _plan_float("danger", 1.0)
	score += _strategy_score(u, tile)

	var point := Vector2(tile) + Vector2(0.5, 0.5)
	var nearest_open := INF
	for objective in battle.objectives:
		var distance: float = point.distance_to(objective["center"])
		if distance <= objective["radius"]:
			score += OBJECTIVE_HOLD if objective["owner"] == team else OBJECTIVE_TAKE * (1.0 + _urgency)
		if objective["owner"] != team:
			nearest_open = minf(nearest_open, distance)
	# The plan says which objective (or spot) to make for first.
	var plan_goal := _plan_goal(u)
	if plan_goal != Vector2.INF:
		nearest_open = point.distance_to(plan_goal)

	if seen.is_empty():
		var goal := plan_goal if plan_goal != Vector2.INF else _goal(tile)
		goal = _lane_goal(u, goal)
		score -= Vector2(tile).distance_to(goal) * APPROACH_WEIGHT * (1.0 + 2.0 * _aggression)
	else:
		var nearest := INF
		for e in seen:
			nearest = minf(nearest, Vector2(tile).distance_to(Vector2(e.pos)))
		score -= absf(nearest - (float(u.def.get("range", 6.0)) + _plan_float("range", 0.0)) * Weapon.RANGE_SCALE) * RANGE_WEIGHT
		if nearest_open < INF and not u.def.get("holds_back", false):
			score -= nearest_open * OBJECTIVE_PULL * (1.0 + 2.0 * _urgency) * _plan_float("objective_pull", 1.0)

	for ally in battle.alive_units(team):
		if ally != u and Vector2(ally.pos).distance_to(Vector2(tile)) <= CombatRules.GRENADE_RADIUS:
			score -= CROWDING_PENALTY
	score -= _support_distance(u, tile) * (MEDIC_PULL if u.medkits > 0 else OFFICER_PULL)
	if u.has_trait("detonator"):
		for ied: Vector2i in battle.mines_known_to(team):
			if battle.map.get_mine_kind(ied) == "ied" and Vector2(tile).distance_to(Vector2(ied)) <= CombatRules.DETONATE_RANGE \
					and _can_see(tile, ied, u.sight, level):
				score += IED_WATCH_VALUE
	if level == 0 and not u.vehicle:
		if battle._beside_fire(tile):
			score -= FIRE_BESIDE_PENALTY
			if battle.map.get_terrain(tile) in TacticalMap.LONG_BURNING:
				score -= FIRE_CATCH_PENALTY
	if not seen.is_empty():
		for d: Vector2i in TacticalMap.DIRS8:
			if battle.map.is_explosive(tile + d):
				score -= EXPLOSIVE_NEARBY_PENALTY
				break
	return score


## What a medkit on an ally is worth: the health it gives back (more for a man close to death), treating a
## wound, and steadying him if he's shaken. 0 if he needs none of it.
func _medkit_value(ally: Unit) -> float:
	if ally.vehicle:
		return 0.0
	var missing := ally.max_hp - ally.hp
	var shaken := ally.suppression >= CombatRules.MEDKIT_STEADIES_AT
	if missing < 2 and not ally.is_wounded() and not shaken:
		return 0.0
	var value := mini(CombatRules.MEDKIT_HEAL, missing) * MEDKIT_VALUE_PER_HP * (1.5 if ally.hp <= 3 else 1.0)
	if ally.is_wounded():
		value += 10.0
	value += mini(ally.suppression, CombatRules.MEDKIT_CALM) * SUPPRESSION_VALUE * 2.0
	return value


## Whether a soldier on tile (at level) would be next to the ally, on the same floor (to treat him).
func _beside(tile: Vector2i, level: int, ally: Unit) -> bool:
	return maxi(absi(tile.x - ally.pos.x), absi(tile.y - ally.pos.y)) == 1 \
			and battle.map.floor_height(tile, level) == battle.map.floor_height(ally.pos, ally.level)


## What rallying is worth: the suppression it lifts off allies in reach, and more for each it gets out of pinned
## or suppressed, and for those who can still act this turn.
func _rally_value(u: Unit) -> float:
	var value := 0.0
	for ally in battle.alive_units(team):
		if ally.suppression <= 0 or Vector2(ally.pos).distance_to(Vector2(u.pos)) > CombatRules.OFFICER_RADIUS:
			continue
		var after := maxi(0, ally.suppression - CombatRules.RALLY_AMOUNT)
		var gain := mini(ally.suppression, CombatRules.RALLY_AMOUNT) * RALLY_VALUE
		if ally.is_pinned() and after < Unit.PINNED_AT:
			gain += RALLY_UNPIN
		elif ally.is_suppressed() and after < Unit.SUPPRESSED_AT:
			gain += RALLY_STEADY
		if ally.actions > 0 and ally != u:
			gain += RALLY_CAN_ACT
		value += gain
	return value


## Smoke on a tile: the danger it takes off allies in it (more for pinned ones), less what it costs us in shots
## we could take from there. 0 unless someone in it is in real danger.
func _smoke_value(tile: Vector2i, seen: Array[Unit]) -> float:
	var relief := 0.0
	var blocked := 0
	for ally in battle.alive_units(team):
		if Vector2(ally.pos).distance_to(Vector2(tile)) > CombatRules.SMOKE_RADIUS:
			continue
		var danger := _danger(ally, ally.pos, seen)
		if danger >= SMOKE_DANGER:
			relief += danger * DANGER_WEIGHT * SMOKE_RELIEF * (1.5 if ally.is_pinned() else 1.0)
		if seen.any(func(e: Unit) -> bool: return battle.can_see(ally, e)):
			blocked += 1
	if relief <= 0.0:
		return 0.0
	return relief - blocked * SMOKE_BLOCKS_SHOT - SMOKE_COST


## Clearing a known enemy mine or tunnel entrance: more if it lies on the way to where we're going, or in an
## objective.
func _clear_value(u: Unit, tile: Vector2i) -> float:
	var value := CLEAR_MINE_VALUE
	var goal := _plan_goal(u)
	if goal == Vector2.INF:
		goal = _goal(u.pos)
	var a := Vector2(u.pos)
	var to_goal := goal - a
	var t := clampf((Vector2(tile) - a).dot(to_goal) / maxf(0.001, to_goal.length_squared()), 0.0, 1.0)
	if Vector2(tile).distance_to(a + to_goal * t) <= 1.0 and t > 0.0:
		value += CLEAR_MINE_IN_WAY
	for objective in battle.objectives:
		if (Vector2(tile) + Vector2(0.5, 0.5)).distance_to(objective["center"]) <= objective["radius"]:
			value += CLEAR_MINE_IN_WAY
			break
	return value


## Bringing a building down on enemies inside it: per enemy we can see in it, by how close it is to falling.
func _collapse_bonus(tile: Vector2i, seen: Array[Unit]) -> float:
	var progress := battle.collapse_progress(tile)
	if progress <= 0.0:
		return 0.0
	var inside := 0
	for e in seen:
		if battle.map.get_storeys(e.pos) >= 2 and battle.map.is_indoors(e.pos, e.level) and Vector2(e.pos).distance_to(Vector2(tile)) <= 4.0:
			inside += 1
	return minf(progress, 1.0) * inside * COLLAPSE_VALUE


## How far a medic (with kits) is from the nearest ally who needs him, or an officer beyond his reach from the
## nearest shaken soldier: what pulls them toward their men. 0 for everyone else, or when nobody needs them.
func _support_distance(u: Unit, tile: Vector2i) -> float:
	var medic := u.medkits > 0
	if not medic and not u.leader:
		return 0.0
	var nearest := INF
	for ally in battle.alive_units(team):
		if ally == u or ally.vehicle:
			continue
		var needs := _medkit_value(ally) > 0.0 if medic else ally.suppression >= Unit.SUPPRESSED_AT
		if needs:
			nearest = minf(nearest, Vector2(tile).distance_to(Vector2(ally.pos)))
	if nearest == INF:
		return 0.0
	return maxf(0.0, nearest - (1.0 if medic else CombatRules.OFFICER_RADIUS))


## Fuel drums and oil tanks close enough to an enemy we can see for their blast to reach him.
func _explosives_near(seen: Array[Unit]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for e in seen:
		for y in range(e.pos.y - 3, e.pos.y + 4):
			for x in range(e.pos.x - 3, e.pos.x + 4):
				var p := Vector2i(x, y)
				if battle.map.is_explosive(p) and not result.has(p) \
						and Vector2(p).distance_to(Vector2(e.pos)) <= CombatRules.EXPLOSIVES[battle.map.get_object_kind(p)]["radius"]:
					result.append(p)
	return result


## Expected incoming damage x 10 (plus marked shells) for standing on a tile.
func _danger(u: Unit, tile: Vector2i, seen: Array[Unit]) -> float:
	var danger := 0.0
	var level := _level_of(u, tile)
	for threat in _threats(seen):
		var e: Unit = threat[0]
		var from: Vector2i = threat[1]
		var weight: float = threat[2]
		var from_level: int = threat[3]
		if not _can_see(from, tile, e.sight, from_level, level):
			continue
		if Battle.hidden_at(battle.map, from, u, tile, level):
			# Lying in the wheat (or hidden in the grass or jungle), out of their sight.
			continue
		var outcome := _expected_damage(e, from, u, tile, false, from_level, level)
		danger += (outcome[0] * 10.0 + outcome[1] * KILL_BONUS * 0.5) * weight
	for strike in battle.strikes:
		if strike["kind"] != "smoke" and Vector2(tile).distance_to(Vector2(strike["target"])) <= battle.strike_reach(strike) + 0.5:
			danger += STRIKE_DANGER
	return danger


## Best thing to do with the second action after moving to a tile.
func _followup_value(u: Unit, tile: Vector2i, seen: Array[Unit]) -> float:
	if u.ammo == 0:
		return RELOAD_EMPTY_VALUE
	var level := _level_of(u, tile)
	if u.weapon.fires_standing_still():
		# A sniper who moves can't fire (or overwatch) this turn, but a spot with a shot is worth it next turn.
		var later := 0.0
		for e in seen:
			if _can_see(tile, e.pos, u.sight, level, e.level):
				later = maxf(later, _shot_value(u, tile, e, true))
		return later * NEXT_TURN_SHOT
	var best := _overwatch_value(u, tile, seen)
	if u.medkits > 0:
		for ally in battle.alive_units(team):
			if ally != u and _beside(tile, level, ally):
				best = maxf(best, _medkit_value(ally))
	for e in seen:
		if _can_see(tile, e.pos, u.sight, level, e.level):
			best = maxf(best, _shot_value(u, tile, e))
	for p in _explosives_near(seen):
		if _can_see(tile, p, u.sight, level):
			var kind := battle.map.get_object_kind(p)
			var spec: Dictionary = CombatRules.EXPLOSIVES[kind]
			var value := _blast_value(p, spec["radius"], spec["damage_min"], spec["damage_max"], 0, seen)
			best = maxf(best, value * CombatRules.object_odds(u, tile, p, kind) / 100.0 - OBJECT_SHOT_COST)
	return best


func _shot_value(u: Unit, from: Vector2i, target: Unit, steady := false) -> float:
	var outcome := _expected_damage(u, from, target, target.pos, steady, _level_of(u, from), target.level)
	var value := (outcome[0] * 10.0 + outcome[1] * KILL_BONUS * _plan_float("kill", 1.0)) + (5.0 if target.overwatch else 0.0)
	if CombatRules.misses_stray(u.weapon):
		value -= _stray_cost(u, from, target)
	if target.vehicle:
		# Tanks shrug off suppression; knocking one out is worth a lot.
		return value * 1.5
	var suppression := mini(100 - target.suppression, u.weapon.suppression)
	if u.weapon.blast_radius > 0.0:
		var splash := (CombatRules.SPLASH_DAMAGE_MIN + CombatRules.SPLASH_DAMAGE_MAX) / 2.0 * 10.0
		for other in battle.alive_units():
			if other != target and Vector2(other.pos).distance_to(Vector2(target.pos)) <= u.weapon.blast_radius:
				value += splash * (-2.0 if other.team == team else 0.6)
		if battle.map.has_cover(target.pos, target.level):
			value += 6.0
	if u.weapon.anti_tank or u.weapon.blast_radius > 0.0:
		value += _collapse_bonus(target.pos, _seen_now if _seen_now != null else _seen_enemies())
	if u.weapon.heavy:
		for ally in battle.alive_units(target.team):
			if ally != target and Vector2(ally.pos).distance_to(Vector2(target.pos)) <= CombatRules.MG_AREA_RADIUS:
				suppression += mini(100 - ally.suppression, int(u.weapon.suppression / 2.0))
	return value + suppression * SUPPRESSION_VALUE


## What a miss may cost: harm to our own soldiers near the line of fire or where the round may land,
## minus the chance of hurting other enemies we can see.
func _stray_cost(u: Unit, from: Vector2i, target: Unit) -> float:
	var risks := battle.stray_risks(u, from, target)
	if risks.is_empty():
		return 0.0
	var saved := [u.pos, u.level]
	u.level = _level_of(u, from)
	u.pos = from
	var odds := battle.shot_odds(u, target)
	u.pos = saved[0]
	u.level = saved[1]
	var miss: float = 1.0 - (odds["hit"] + odds["graze"]) / 100.0
	var cost := 0.0
	for risk in risks:
		var victim: Unit = risk["unit"]
		var damage: float = risk["damage"]
		var chance: float = risk["chance"] * miss
		var harm := damage * 10.0 + (KILL_BONUS if victim.hp <= ceili(damage) else 0.0)
		if victim.team == team:
			cost += harm * chance * FRIENDLY_FIRE_WEIGHT
			if chance > FRIENDLY_FIRE_LIMIT:
				cost += FRIENDLY_FIRE_PENALTY
		elif battle.team_sees(team, victim):
			cost -= harm * chance * STRAY_ENEMY_VALUE
	return cost


## Suppressive fire: what the suppression it leaves on the target and its neighbours through their next turn is worth.
## Pinning a man also stops him shooting at us next turn (THREAT_DENIAL of his best shot); it's worth more when
## the gun can't hit him well anyway, or catches several.
func _suppress_value(u: Unit, target: Unit, seen: Array[Unit]) -> float:
	var amount := roundi(u.weapon.suppression * CombatRules.SUPPRESSIVE_FIRE_FACTOR)
	var value := _suppression_gain(target, amount) + _denial(target, amount) - SUPPRESSIVE_AMMO_COST
	var caught := 1
	for other in battle.alive_units(target.team):
		if other != target and not other.vehicle and seen.has(other) \
				and Vector2(other.pos).distance_to(Vector2(target.pos)) <= CombatRules.SUPPRESSIVE_FIRE_RADIUS:
			value += _suppression_gain(other, u.weapon.suppression) + _denial(other, u.weapon.suppression)
			caught += 1
	if caught >= 2 or battle.shot_odds(u, target)["hit"] < 45:
		value += SUPPRESS_BONUS
	return value


## The shots at us an enemy won't take if this much suppression pins him through his next turn.
func _denial(e: Unit, amount: int) -> float:
	var otherwise := maxi(0, e.suppression - CombatRules.SUPPRESSION_RECOVERY)
	if mini(100, e.suppression + amount) < Unit.PINNED_AT or otherwise >= Unit.PINNED_AT:
		return 0.0
	var best := 0.0
	for ours in battle.alive_units(team):
		if _can_see(e.pos, ours.pos, e.sight, e.level, ours.level):
			best = maxf(best, _expected_damage(e, e.pos, ours, ours.pos, false, e.level, ours.level)[0] * 10.0)
	return best * THREAT_DENIAL + (10.0 if e.overwatch else 0.0)


func _suppression_gain(e: Unit, amount: int) -> float:
	var level := mini(100, e.suppression + amount)
	var value := (level - e.suppression) * SUPPRESSION_VALUE
	# Without suppressive fire they would have recovered this much by their turn.
	var otherwise := maxi(0, e.suppression - CombatRules.SUPPRESSION_RECOVERY)
	if level >= Unit.PINNED_AT and otherwise < Unit.PINNED_AT:
		value += PIN_VALUE + (5.0 if e.overwatch else 0.0)
	elif level >= Unit.SUPPRESSED_AT and otherwise < Unit.SUPPRESSED_AT:
		value += SUPPRESS_STATE_VALUE
	return value


## What overwatch from a tile is worth: the shots it would get at enemies likely to move through its sight
## (the best lane, plus a little for the others, since only one shot fires), weighed by how likely each is to
## move. Never more than OVERWATCH_VS_SHOT of a shot we could take right now. With no enemy in sight, only a
## little while they were seen lately, so a quiet front doesn't make everyone sit on overwatch.
func _overwatch_value(u: Unit, tile: Vector2i, seen: Array[Unit]) -> float:
	var scale := _plan_float("overwatch", 1.0)
	if seen.is_empty():
		var quiet := OVERWATCH_VALUE * 0.3 if not _last_seen.is_empty() else 0.0
		return quiet * (1.0 - _aggression) * scale
	var level := _level_of(u, tile)
	var lanes: Array[float] = []
	var shot_now := 0.0
	for e in seen:
		if Vector2(tile).distance_to(Vector2(e.pos)) > u.sight + e.current_mobility():
			continue
		if _can_see(tile, e.pos, u.sight, level, e.level):
			shot_now = maxf(shot_now, _shot_value(u, tile, e))
		var lane := 0.0
		for p: Vector2i in _likely_steps(e):
			if _can_see(tile, p, u.sight, level, e.level):
				lane = maxf(lane, _expected_damage(u, tile, e, p, false, level, e.level)[0] * 10.0)
		if lane > 0.0:
			var settled := e.overwatch or _holds_objective(e)
			lanes.append(lane * (OVERWATCH_SETTLED_CHANCE if settled else OVERWATCH_MOVE_CHANCE))
	if lanes.is_empty():
		return 0.0
	lanes.sort()
	var value: float = lanes[-1]
	for i in lanes.size() - 1:
		value += lanes[i] * OVERWATCH_OTHER_LANES
	if shot_now > 0.0:
		value = minf(value, shot_now * OVERWATCH_VS_SHOT)
	return value * scale


## Where an enemy is likely to be after his next move: toward the nearest objective his side doesn't hold
## (else our nearest soldier), a full move and half of one.
func _likely_steps(e: Unit) -> Array[Vector2i]:
	if _step_cache.has(e.id):
		return _step_cache[e.id]
	var from := Vector2(e.pos)
	var goal := Vector2.INF
	var best := INF
	for objective in battle.objectives:
		if objective["owner"] != e.team:
			var d: float = from.distance_to(objective["center"])
			if d < best:
				best = d
				goal = objective["center"]
	if goal == Vector2.INF:
		for ours in battle.alive_units(team):
			var d := from.distance_to(Vector2(ours.pos))
			if d < best:
				best = d
				goal = Vector2(ours.pos)
	var steps: Array[Vector2i] = []
	if goal != Vector2.INF and best > 0.5:
		var reach := minf(e.current_mobility(), best)
		for share: float in [1.0, 0.5]:
			var p := Vector2i((from + (goal - from).normalized() * reach * share).round())
			if battle.map.in_bounds(p) and not steps.has(p) and p != e.pos:
				steps.append(p)
	_step_cache[e.id] = steps
	return steps


func _holds_objective(e: Unit) -> bool:
	for objective in battle.objectives:
		if objective["owner"] == e.team and (Vector2(e.pos) + Vector2(0.5, 0.5)).distance_to(objective["center"]) <= objective["radius"]:
			return true
	return false


## Tiles worth considering for grenades and shells: on and around every enemy we can see.
func _tiles_around(seen: Array[Unit]) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for e in seen:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var t := e.pos + Vector2i(dx, dy)
				if battle.map.in_bounds(t) and not tiles.has(t):
					tiles.append(t)
	return tiles


## A grenade's value averaged over where it may land (it scatters with range, aim and suppression).
func _grenade_value(u: Unit, tile: Vector2i, seen: Array[Unit]) -> float:
	var aimed := _blast_value(tile, CombatRules.GRENADE_RADIUS, CombatRules.GRENADE_DAMAGE_MIN, CombatRules.GRENADE_DAMAGE_MAX, CombatRules.GRENADE_SHRED, seen)
	if aimed <= 0.0:
		return 0.0
	var landings := battle.throw_landings(tile, CombatRules.throw_scatter(u, u.pos, tile))
	var value := 0.0
	for spot: Vector2i in landings:
		var spot_value := aimed if spot == tile else _blast_value(spot, CombatRules.GRENADE_RADIUS, CombatRules.GRENADE_DAMAGE_MIN, CombatRules.GRENADE_DAMAGE_MAX, CombatRules.GRENADE_SHRED, seen, false)
		value += spot_value * landings[spot]
	return value


## Value of a blast on tile: damage, kills and suppression to enemies we can see, minus twice that to our own.
## 0 when it would hit no enemy, unless require_hit is off (for where a grenade may stray).
func _blast_value(tile: Vector2i, radius: float, damage_min: int, damage_max: int, shred: int, seen: Array[Unit], require_hit := true) -> float:
	var value := 0.0
	var hits := 0
	var average := (damage_min + damage_max) / 2.0
	var map := battle.map
	var occupant := battle.unit_at(tile)
	var blast_height := map.floor_height(tile, occupant.level if occupant != null else 0)
	for victim in battle.alive_units():
		var distance := Vector2(victim.pos).distance_to(Vector2(tile))
		if distance > radius + 1.0:
			continue
		if map.has_height() and absf(map.floor_height(victim.pos, victim.level) - blast_height) > 1.0:
			continue
		if victim.team != team and not seen.has(victim):
			continue
		var victim_value := 0.0 if victim.vehicle else mini(100 - victim.suppression, CombatRules.EXPLOSION_SUPPRESSION) * SUPPRESSION_VALUE
		if distance <= radius:
			var armor := CombatRules.EXPLOSION_VS_ARMOR if victim.vehicle else maxi(0, victim.armor - shred)
			var kill := 0.0
			if damage_min - armor >= victim.hp:
				kill = 1.0
			elif damage_max - armor >= victim.hp:
				kill = 0.5
			victim_value += (maxf(0.0, average - armor) * 10.0 + kill * KILL_BONUS)
			if victim.team != team:
				hits += 1
				if battle.map.has_cover(victim.pos, victim.level):
					value += 6.0
		value += -victim_value * 2.0 if victim.team == team else victim_value
	# Fuel drums and oil tanks in the blast go up too (counted one level deep).
	if require_hit:
		for p in battle.map.tiles_in_radius(tile, radius):
			if battle.map.is_explosive(p) and p != tile:
				var spec: Dictionary = CombatRules.EXPLOSIVES[battle.map.get_object_kind(p)]
				var chain := _blast_value(p, spec["radius"], spec["damage_min"], spec["damage_max"], 0, seen, false)
				value += chain
				if chain > 0.0:
					hits += 1
	return value if hits > 0 or not require_hit else 0.0


# --- Game plan ---

## Plays the given plan (a key of STRATEGIES) from now on.
func set_strategy(key: String) -> void:
	strategy = key
	_sprung = false
	_plan_goals.clear()
	if plans.is_empty() or plans[-1] != key:
		plans.append(key)


## Plays a plan picked by the player instead of the one picked at random, if it suits this battle (else keeps
## the random one). Returns whether it did. "" keeps the random one.
func choose_strategy(key: String) -> bool:
	if not STRATEGIES.has(key) or not _fits(key):
		return false
	plans.clear()
	set_strategy(key)
	return true


## The plans played this battle, for the log: "Left hook (swing wide ...), then All-out push".
func plan_summary() -> String:
	var parts: Array[String] = []
	for i in plans.size():
		var plan: Dictionary = STRATEGIES[plans[i]]
		parts.append("%s (%s)" % [plan["name"], plan["text"]] if i == 0 else String(plan["name"]))
	return ", then ".join(parts)


## A setting of the current plan, or the default when it doesn't set it.
func _plan_value(key: String, default: Variant) -> Variant:
	return STRATEGIES[strategy].get(key, default)


func _plan_float(key: String, default: float) -> float:
	return float(STRATEGIES[strategy].get(key, default))


## Where we start, which way the enemy is, the two wings, and the pair of objectives a "pair" plan would take.
func _read_the_ground() -> void:
	var mine := battle.units.filter(func(u: Unit) -> bool: return u.team == team)
	var sum := Vector2.ZERO
	for u: Unit in mine:
		sum += Vector2(u.pos)
	_home = sum / mine.size() if not mine.is_empty() else Vector2(battle.map.width, battle.map.height) * 0.5
	var toward := _objective - _home
	if toward.length() < 1.0:
		toward = Vector2.RIGHT if team == 0 else Vector2.LEFT
	_forward = toward.normalized()
	_left = Vector2(_forward.y, -_forward.x)
	mine.sort_custom(func(a: Unit, b: Unit) -> bool: return _lat(Vector2(a.pos)) < _lat(Vector2(b.pos)) or (_lat(Vector2(a.pos)) == _lat(Vector2(b.pos)) and a.id < b.id))
	for i in mine.size():
		_wings[mine[i].id] = -1 if i < mine.size() / 2.0 else 1
	var order := _objectives_by_lat()
	if order.size() >= 2:
		var first := _plan_rng("pair").randi_range(0, order.size() - 2)
		_pair.assign([order[first], order[first + 1]])


## A random number generator for the AI's own choices, seeded from the battle, so it picks the same every time
## (replays, saves, online) without touching the battle's dice.
func _plan_rng(what: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([battle.rng.seed, team, what])
	return rng


func _pick_strategy() -> String:
	var options: Array = STRATEGIES.keys().filter(_fits)
	var total := 0.0
	for key: String in options:
		total += float(STRATEGIES[key].get("weight", 1.0))
	var roll := _plan_rng("plan").randf() * total
	for key: String in options:
		roll -= float(STRATEGIES[key].get("weight", 1.0))
		if roll < 0.0:
			return key
	return "broad_front"


## Whether a plan suits this battle: enough objectives, and a tank for a tank plan.
func _fits(key: String) -> bool:
	var plan: Dictionary = STRATEGIES[key]
	if plan.has("objectives") and battle.objectives.size() < plan["objectives"]:
		return false
	if plan.get("vehicle", false) and not _has_tank():
		return false
	return true


func _has_tank() -> bool:
	return battle.alive_units(team).any(func(u: Unit) -> bool: return u.vehicle)


## Once a round: a plan that no longer makes sense gives way. Tanks gone, the spearhead becomes a broad
## front; the ambush springs when its time is up or we fall behind; and far behind late on, anything
## becomes an all-out push.
func _review_strategy() -> void:
	var share := float(battle.round_number) / maxi(1, battle.max_rounds)
	if STRATEGIES[strategy].get("vehicle", false) and not _has_tank():
		set_strategy("broad_front")
	if STRATEGIES[strategy].has("ambush") and not _sprung:
		var behind: bool = battle.victory_points[1 - team] > battle.victory_points[team]
		if share >= float(STRATEGIES[strategy]["ambush"]) or behind or _enemy_holds_home():
			_sprung = true
			_plan_goals.clear()
	if strategy != "blitz" and _urgency >= DESPERATE_URGENCY and share >= DESPERATE_SHARE:
		set_strategy("blitz")


func _ambushing() -> bool:
	return STRATEGIES[strategy].has("ambush") and not _sprung


## A "pair" plan holds both its objectives and stays on them (unless falling behind on points).
func _digging_in() -> bool:
	if _plan_value("focus", "") != "pair" or _pair.is_empty() or _urgency >= DESPERATE_URGENCY:
		return false
	return _pair.all(func(i: int) -> bool: return battle.objectives[i]["owner"] == team)


## The enemy has taken the objective nearest our start.
func _enemy_holds_home() -> bool:
	var home := _home_objective()
	return home != -1 and battle.objectives[home]["owner"] == 1 - team


## How far along our left (negative) or right (positive) of the map's centre line a point is.
func _lat(p: Vector2) -> float:
	return -(p - Vector2(battle.map.width, battle.map.height) * 0.5).dot(_left)


## Half the map's width, seen from our side.
func _half_width() -> float:
	return (absf(_left.x) * battle.map.width + absf(_left.y) * battle.map.height) * 0.5


## -1 for the left wing, 1 for the right.
func _wing(u: Unit) -> int:
	return _wings.get(u.id, -1 if _lat(Vector2(u.pos)) < 0.0 else 1)


func _objectives_by_lat() -> Array[int]:
	var order: Array[int] = []
	for i in battle.objectives.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _lat(battle.objectives[a]["center"]) < _lat(battle.objectives[b]["center"]))
	return order


func _home_objective() -> int:
	var best := -1
	for i in battle.objectives.size():
		if best == -1 or _home.distance_to(battle.objectives[i]["center"]) < _home.distance_to(battle.objectives[best]["center"]):
			best = i
	return best


## The objectives a unit should go for, first one first; empty to go for the nearest open one as usual.
func _focus_order(u: Unit) -> Array[int]:
	var none: Array[int] = []
	if battle.objectives.is_empty():
		return none
	if _urgency >= DESPERATE_URGENCY and _plan_value("focus", "") != "home":
		return none
	var order := _objectives_by_lat()
	match _plan_value("focus", ""):
		"pair":
			if _pair.is_empty():
				return none
			# Each wing takes the objective on its side of the pair.
			var pair: Array[int] = [_pair[0], _pair[1]]
			if _wing(u) > 0:
				pair.reverse()
			return pair
		"left":
			return order
		"right":
			order.reverse()
			return order
		"centre":
			order.sort_custom(func(a: int, b: int) -> bool: return absf(_lat(battle.objectives[a]["center"])) < absf(_lat(battle.objectives[b]["center"])))
			return order
		"wings":
			if _wing(u) > 0:
				order.reverse()
			return order
		"home":
			if _ambushing():
				none.append(_home_objective())
			return none
	return none


## Where the plan sends a unit (an objective, or where to wait), or Vector2.INF to go the usual way.
func _plan_goal(u: Unit) -> Vector2:
	if _plan_goals.has(u.id):
		return _plan_goals[u.id]
	var goal := Vector2.INF
	var order := _focus_order(u)
	if _digging_in():
		goal = battle.objectives[order[0]]["center"]
	else:
		for i in order:
			if battle.objectives[i]["owner"] != team or _ambushing():
				goal = battle.objectives[i]["center"]
				break
	if goal == Vector2.INF and _ambushing():
		# Nothing to hold: wait a few tiles out from where we started.
		goal = _clamp_to_map(_home + _forward * 4.0)
	_plan_goals[u.id] = goal
	return goal


## The lane a unit keeps to (as a _lat() value), or INF when it goes where it likes: support weapons that hold
## back, and every unit once the plan has no lanes.
func _lane(u: Unit) -> float:
	var lane: Variant = _plan_value("lane", null)
	if lane == null or u.def.get("holds_back", false):
		return INF
	var side := float(_wing(u)) if lane is String else float(lane)
	return side * LANE_SHARE * _half_width()


## How much a unit still keeps to its lane on the way to a goal: fully while far off, not at all once there.
func _lane_fade(u: Unit, goal: Vector2) -> float:
	return clampf(((goal - Vector2(u.pos)).dot(_forward) - 3.0) / LANE_FADE, 0.0, 1.0)


## A goal moved sideways into the unit's lane, so it comes in along the flank and turns in at the end.
func _lane_goal(u: Unit, goal: Vector2) -> Vector2:
	var lane := _lane(u)
	if lane == INF or goal == Vector2.INF:
		return goal
	var fade := _lane_fade(u, goal)
	return _clamp_to_map(goal - _left * (lane - _lat(goal)) * fade)


func _clamp_to_map(p: Vector2) -> Vector2:
	return p.clamp(Vector2.ZERO, Vector2(battle.map.width - 1, battle.map.height - 1))


## What the plan adds to standing on a tile: keeping to a lane, close together, behind the tanks, on the
## objectives we dug in on, or near home while waiting.
func _strategy_score(u: Unit, tile: Vector2i) -> float:
	var score := 0.0
	var p := Vector2(tile)
	var shape := _plan_shape(u)
	if shape["fade"] > 0.0:
		score -= maxf(0.0, absf(_lat(p) - shape["lane"]) - LANE_SLACK) * LANE_WEIGHT * shape["fade"]
	if shape["together"] != Vector2.INF:
		score -= maxf(0.0, p.distance_to(shape["together"]) - COHESION_RADIUS) * COHESION_WEIGHT
	if _plan_value("escort", false):
		score += _escort_score(u, p)
	if _digging_in() or _ambushing():
		var goal := _plan_goal(u)
		if goal != Vector2.INF:
			var reach := 1.0
			for objective in battle.objectives:
				if objective["center"] == goal:
					reach += float(objective["radius"])
			var outside := maxf(0.0, (p + Vector2(0.5, 0.5)).distance_to(goal) - reach - (3.0 if _ambushing() else 0.0))
			score -= outside * (DIG_IN_PULL if _digging_in() else ANCHOR_PULL)
	return score


## What _strategy_score() needs about a unit, worked out once per decide: the lane (as a _lat() value) and how
## much it still counts, and where the rest of the side is (Vector2.INF when the plan doesn't keep together).
func _plan_shape(u: Unit) -> Dictionary:
	var key := -1 - u.id
	if _plan_goals.has(key):
		return _plan_goals[key]
	var shape := {"lane": 0.0, "fade": 0.0, "together": Vector2.INF}
	var lane := _lane(u)
	if lane != INF:
		var goal := _plan_goal(u) if _plan_goal(u) != Vector2.INF else _goal(u.pos)
		shape["fade"] = _lane_fade(u, goal)
		shape["lane"] = lerpf(_lat(goal), lane, shape["fade"])
	if _plan_value("cohesion", false):
		var sum := Vector2.ZERO
		var count := 0
		for ally in battle.alive_units(team):
			if ally != u:
				sum += Vector2(ally.pos)
				count += 1
		if count > 0:
			shape["together"] = sum / count
	_plan_goals[key] = shape
	return shape


## Armoured spearhead: infantry stay close behind the nearest tank; tanks don't run off from their infantry.
func _escort_score(u: Unit, p: Vector2) -> float:
	if u.vehicle:
		var sum := Vector2.ZERO
		var count := 0
		for ally in battle.alive_units(team):
			if not ally.vehicle:
				sum += Vector2(ally.pos)
				count += 1
		if count == 0:
			return 0.0
		return -maxf(0.0, (p - sum / count).dot(_forward) - TANK_LEASH) * ESCORT_CLOSE_WEIGHT
	var lead: Unit = null
	for ally in battle.alive_units(team):
		if ally.vehicle and (lead == null or p.distance_to(Vector2(ally.pos)) < p.distance_to(Vector2(lead.pos))):
			lead = ally
	if lead == null:
		return 0.0
	var ahead := (p - Vector2(lead.pos)).dot(_forward)
	return -maxf(0.0, ahead + 1.0) * ESCORT_AHEAD_WEIGHT - maxf(0.0, p.distance_to(Vector2(lead.pos)) - ESCORT_RADIUS) * ESCORT_CLOSE_WEIGHT


# --- Knowledge ---

func _remember() -> void:
	for e in battle.units:
		if e.team == team:
			continue
		if not e.is_alive():
			_last_seen.erase(e.id)
		elif battle.team_sees(team, e):
			_last_seen[e.id] = e.pos
			_searching = true
		elif _last_seen.has(e.id) and _team_sees_tile(_last_seen[e.id]):
			# We are looking at where they were, and they're gone.
			_last_seen.erase(e.id)


func _seen_enemies() -> Array[Unit]:
	var result: Array[Unit] = []
	for e in battle.alive_units():
		if e.team != team and battle.team_sees(team, e):
			result.append(e)
	return result


## [enemy, position we believe they're at, weight, floor] for every enemy we know about.
func _threats(seen: Array[Unit]) -> Array:
	var result := []
	for e in seen:
		result.append([e, e.pos, 1.0, e.level])
	for id: int in _last_seen:
		var e := battle.get_unit(id)
		if not seen.has(e):
			result.append([e, _last_seen[id], REMEMBERED_THREAT * (1.0 - 0.8 * _aggression), 0])
	return result


## Where to head when no enemy is in sight: the nearest objective we don't hold,
## else the nearest remembered enemy, else wherever we expect them to be.
func _goal(from: Vector2i) -> Vector2:
	var best := _search_goal if _searching else _objective
	var best_distance := INF
	for objective in battle.objectives:
		var d := Vector2(from).distance_to(objective["center"])
		if objective["owner"] != team and d < best_distance:
			best_distance = d
			best = objective["center"]
	if best_distance < INF:
		return best
	for id: int in _last_seen:
		var d := Vector2(from).distance_to(Vector2(_last_seen[id]))
		if d < best_distance:
			best_distance = d
			best = Vector2(_last_seen[id])
	return best


func _fog_center() -> Vector2:
	var visible := battle.team_visible_tiles(team)
	var sum := Vector2.ZERO
	var count := 0
	for y in battle.map.height:
		for x in battle.map.width:
			if not visible.has(Vector2i(x, y)) and battle.map.is_passable(Vector2i(x, y)):
				sum += Vector2(x, y)
				count += 1
	return sum / count if count > 0 else _objective


func _team_sees_tile(tile: Vector2i) -> bool:
	for u in battle.alive_units(team):
		if battle.visible_from(u.pos, u.sight, u.level).has(tile):
			return true
	return false


# --- Hypothetical combat maths ---

## The floor the unit would be on at the tile being judged.
func _level_of(u: Unit, tile: Vector2i) -> int:
	if _at_level >= 0:
		return _at_level
	return u.level if u != null and tile == u.pos else 0


func _can_see(from: Vector2i, to: Vector2i, sight: float, from_level := 0, to_level := 0) -> bool:
	var map := battle.map
	if map.has_height():
		sight += LineOfSight.HEIGHT_SIGHT_BONUS * maxf(0.0, map.floor_height(from, from_level) - map.floor_height(to, to_level))
	if Vector2(from).distance_to(Vector2(to)) > sight:
		return false
	var key := Vector4i(from.x + 1024 * from_level, from.y, to.x + 1024 * to_level, to.y)
	if not _sight_cache.has(key):
		_sight_cache[key] = LineOfSight.can_see(map, from, to, INF, true, from_level, to_level)
	return _sight_cache[key]


## [expected damage, kill probability] of shooter (standing on from) firing at target (standing on at), on the
## given floors (-1: where they are now).
func _expected_damage(shooter: Unit, from: Vector2i, target: Unit, at: Vector2i, steady := false, from_level := -1, at_level := -1) -> Array[float]:
	var saved := [shooter.pos, target.pos, shooter.level, target.level]
	shooter.pos = from
	target.pos = at
	if from_level >= 0:
		shooter.level = from_level
	if at_level >= 0:
		target.level = at_level
	var odds := battle.shot_odds(shooter, target, false, steady)
	shooter.pos = saved[0]
	target.pos = saved[1]
	shooter.level = saved[2]
	target.level = saved[3]

	var w := shooter.weapon
	var armor := target.armor
	if target.vehicle:
		if not w.anti_tank:
			return [0.0, 0.0]
		var saved_pos := target.pos
		target.pos = at
		armor = CombatRules.armor_value(target, CombatRules.armor_side(target, from))
		target.pos = saved_pos
	var hit: float = odds["hit"] / 100.0
	var crit: float = odds["crit"] / 100.0
	var graze: float = odds["graze"] / 100.0
	var rolls := w.damage_max - w.damage_min + 1
	var expected := 0.0
	var kill := 0.0
	for d in range(w.damage_min, w.damage_max + 1):
		var normal := maxi(0, d - armor)
		var critical := maxi(0, d + w.crit_damage - armor)
		var grazed := maxi(0, maxi(1, floori(d / 2.0)) - armor)
		expected += (hit * ((1.0 - crit) * normal + crit * critical) + graze * grazed) / rolls
		kill += (hit * ((1.0 - crit) * float(normal >= target.hp) + crit * float(critical >= target.hp)) + graze * float(grazed >= target.hp)) / rolls
	return [expected, kill]


func _average_damage(u: Unit) -> float:
	return (u.weapon.damage_min + u.weapon.damage_max) / 2.0
