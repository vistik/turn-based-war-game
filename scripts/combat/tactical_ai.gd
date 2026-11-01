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
const OVERWATCH_VALUE := 10.0
## Score lost for a round spent on fuel drums or an oil tank instead of a soldier.
const OBJECT_SHOT_COST := 6.0
## Standing next to something that can blow up, while enemies are about.
const EXPLOSIVE_NEARBY_PENALTY := 8.0
const RELOAD_EMPTY_VALUE := 30.0
const MEDKIT_VALUE_PER_HP := 8.0
const RALLY_VALUE := 0.4
## What being crouched / prone is worth against, for the slower movement it means from now on.
const STANCE_MOBILITY_COST := [0.0, 2.0, 12.0]
## A stance's effect on incoming fire lasts beyond the next enemy turn, so it counts this many times over.
const STANCE_PERSISTENCE := 2.0
## Pinning an enemy (or just suppressing one) through their next turn with suppressive fire, and the rounds it burns.
const PIN_VALUE := 20.0
const SUPPRESS_STATE_VALUE := 6.0
const SUPPRESSIVE_AMMO_COST := 4.0
## Prone mortar and anti-tank teams can't use their weapon.
const PRONE_WEAPON_PENALTY := 12.0
## Going through the tunnels uses the whole turn; a hidden punji trap is worth this much (more on an
## objective's approaches or a trail), but not with enemies close enough to see it being laid.
const TUNNEL_COST := 4.0
## Setting off an IED spends it (and the bomb maker's turn), so it should catch someone.
const DETONATE_COST := 12.0
const TRAP_VALUE := 6.0
const TRAP_OBJECTIVE_BONUS := 6.0
const TRAP_TRAIL_BONUS := 3.0
## Rounds without seeing an enemy before the AI is fully impatient and pushes forward.
const PATIENCE_ROUNDS := 3.0

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
## Per-act cache of tile-to-tile sight, keyed by Vector4i(from, to).
var _sight_cache := {}


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


## The AI's memory, for save games.
func to_dict() -> Dictionary:
	return {"last_seen": _last_seen.duplicate(), "searching": _searching, "search_goal": _search_goal, "quiet_rounds": _quiet_rounds, "round": _round}


func load_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	_last_seen = data["last_seen"].duplicate()
	_searching = data["searching"]
	_search_goal = data["search_goal"]
	_quiet_rounds = data["quiet_rounds"]
	_round = data["round"]


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
	_sight_cache.clear()
	_remember()
	var seen := _seen_enemies()
	if battle.round_number != _round:
		_round = battle.round_number
		_quiet_rounds = _quiet_rounds + 1 if seen.is_empty() else 0
	if not seen.is_empty():
		_quiet_rounds = 0
	_aggression = clampf(_quiet_rounds / PATIENCE_ROUNDS, 0.0, 1.0)
	_urgency = clampf((battle.victory_points[1 - team] - battle.victory_points[team]) / URGENCY_POINTS, 0.0, 2.0)
	if _searching and seen.is_empty() and _last_seen.is_empty():
		_search_goal = _fog_center()
	var best := {}
	for u in battle.alive_units(team):
		if u.actions <= 0:
			continue
		var plan := _best_plan(u, seen)
		if not plan.is_empty() and (best.is_empty() or plan["value"] > best["value"]):
			best = plan
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
				plans.append(_plan(u, "shoot", stay + _shot_value(u, here, e), e))
				if battle.can_aimed_shot(u, e) == "":
					plans.append(_plan(u, "aimed_shot", stay + _shot_value(u, here, e, true), e))
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
	if battle.can_set_up(u) == "":
		var ready_value := OVERWATCH_VALUE * 0.6
		if u.actions >= 2:
			for e in seen:
				if battle.can_see(u, e):
					ready_value = maxf(ready_value, _shot_value(u, here, e))
		plans.append(_plan(u, "set_up", stay + ready_value))
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
				var value := _blast_value(tile, spec["radius"] + Battle.mortar_scatter(u.pos, tile, spec) * 0.5,
						spec["damage"][0], spec["damage"][1], 0, seen)
				if value > 0.0:
					plans.append(_plan(u, "mortar", stay + value * MORTAR_CERTAINTY - MORTAR_COST, null, tile))
	if u.medkits > 0:
		for ally in battle.alive_units(team):
			var missing := ally.max_hp - ally.hp
			if (missing >= 2 or ally.is_wounded()) and battle.can_use_medkit(u, ally) == "":
				var value := mini(CombatRules.MEDKIT_HEAL, missing) * MEDKIT_VALUE_PER_HP + (8.0 if ally.is_wounded() else 0.0)
				plans.append(_plan(u, "medkit", stay + value, ally))
	if battle.can_rally(u) == "":
		var relief := 0.0
		for ally in battle.alive_units(team):
			if Vector2(ally.pos).distance_to(Vector2(u.pos)) <= CombatRules.OFFICER_RADIUS:
				relief += mini(ally.suppression, CombatRules.RALLY_AMOUNT) * (2.0 if ally.is_pinned() else 1.0)
		plans.append(_plan(u, "rally", stay + relief * RALLY_VALUE))
	if u.ammo < u.weapon.clip_size:
		var reload_value := RELOAD_EMPTY_VALUE if u.ammo == 0 else (4.0 if seen.is_empty() else 0.0)
		plans.append(_plan(u, "reload", stay + reload_value))
	if map.has_cover(here) and not u.vehicle:
		plans.append(_plan(u, "hunker", stay + _danger(u, here, seen)[1]))
	if u.vehicle:
		# Turning on the spot to put the front armour toward the threat.
		var facing := u.facing
		for dir: Vector2i in Pathfinder.HEADINGS:
			if battle.can_pivot(u, dir) == "":
				u.facing = dir
				plans.append(_plan(u, "pivot", _position_score(u, here, seen) - 2.0, null, dir))
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

	var reach := battle.reachable(u)
	for tile: Vector2i in reach:
		if tile == here or reach[tile]["cost"] > u.current_mobility() + 0.001:
			continue
		var facing := u.facing
		if u.vehicle:
			# Judge the spot with the hull facing the way it will end up.
			u.facing = reach[tile]["facing"]
		var value := _position_score(u, tile, seen)
		if u.actions >= 2:
			value += _followup_value(u, tile, seen)
		u.facing = facing
		plans.append(_plan(u, "move", value, null, tile))

	var best := {}
	for plan in plans:
		if best.is_empty() or plan["value"] > best["value"]:
			best = plan
	return best


func _plan(u: Unit, kind: String, value: float, target: Unit = null, tile := Vector2i.ZERO) -> Dictionary:
	return {"unit": u, "kind": kind, "value": value, "target": target, "tile": tile}


## Changing stance on the spot (then the best thing to do there with the action left), and for a crouched or
## prone soldier, standing up to move further than it could crawl.
func _stance_plans(u: Unit, seen: Array[Unit]) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	var here := u.pos
	var current := u.stance
	var mobility_weight := 0.5 if u.is_pinned() else 1.0
	var stay := _position_score(u, here, seen)
	for stance: int in [Unit.Stance.STAND, Unit.Stance.CROUCH, Unit.Stance.PRONE]:
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
					value = maxf(value, _position_score(u, tile, seen) + STANCE_MOBILITY_COST[current])
		u.actions += 1
		u.stance = current
		var plan := _plan(u, "stance", value)
		plan["stance"] = stance
		plans.append(plan)
	return plans


## Best use of an action left over when staying on the spot: shoot, overwatch, set up or reload.
func _stay_followup_value(u: Unit, seen: Array[Unit]) -> float:
	if u.ammo == 0:
		return RELOAD_EMPTY_VALUE
	if battle.can_set_up(u) == "":
		return OVERWATCH_VALUE * 0.6
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
	if plan["kind"] in ["move", "pivot", "grenade", "mortar", "shoot_object", "tunnel", "trap", "detonate"]:
		command["tile"] = plan["tile"]
	if plan["kind"] == "stance":
		command["stance"] = plan["stance"]
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
	if not u.vehicle:
		var best_cover := Cover.NONE
		for d: Vector2i in TacticalMap.DIRS4:
			best_cover = maxi(best_cover, map.cover_toward(tile, d))
		score += best_cover * COVER_WEIGHT
		# Cover only helps on the side the shots come from: toward the enemies we know of, else the goal.
		var threats := _threats(seen)
		var facing_cover := 0.0
		if threats.is_empty():
			facing_cover = map.cover_against(tile, Vector2i(_goal(tile).round()))
		else:
			var weights := 0.0
			for threat: Array in threats:
				facing_cover += map.cover_against(tile, threat[1]) * threat[2]
				weights += threat[2]
			facing_cover /= weights
		score += facing_cover * FACING_COVER_WEIGHT
		if best_cover == Cover.NONE:
			score -= OPEN_GROUND_PENALTY * (1.0 if not seen.is_empty() else 0.5)

	var caution := 2.0 - float(u.hp) / u.max_hp
	score -= _danger(u, tile, seen)[0] * DANGER_WEIGHT * caution

	var point := Vector2(tile) + Vector2(0.5, 0.5)
	var nearest_open := INF
	for objective in battle.objectives:
		var distance: float = point.distance_to(objective["center"])
		if distance <= objective["radius"]:
			score += OBJECTIVE_HOLD if objective["owner"] == team else OBJECTIVE_TAKE * (1.0 + _urgency)
		if objective["owner"] != team:
			nearest_open = minf(nearest_open, distance)

	if seen.is_empty():
		score -= Vector2(tile).distance_to(_goal(tile)) * APPROACH_WEIGHT * (1.0 + 2.0 * _aggression)
	else:
		var nearest := INF
		for e in seen:
			nearest = minf(nearest, Vector2(tile).distance_to(Vector2(e.pos)))
		score -= absf(nearest - float(u.def.get("range", 6.0)) * Weapon.RANGE_SCALE) * RANGE_WEIGHT
		if nearest_open < INF and not u.def.get("holds_back", false):
			score -= nearest_open * OBJECTIVE_PULL * (1.0 + 2.0 * _urgency)

	for ally in battle.alive_units(team):
		if ally != u and Vector2(ally.pos).distance_to(Vector2(tile)) <= CombatRules.GRENADE_RADIUS:
			score -= CROWDING_PENALTY
	if not seen.is_empty():
		for d: Vector2i in TacticalMap.DIRS8:
			if battle.map.is_explosive(tile + d):
				score -= EXPLOSIVE_NEARBY_PENALTY
				break
	return score


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


## [expected incoming damage x 10, how much of it hunkering down would prevent] for standing on a tile.
func _danger(u: Unit, tile: Vector2i, seen: Array[Unit]) -> Array[float]:
	var danger := 0.0
	var hunker_gain := 0.0
	for threat in _threats(seen):
		var e: Unit = threat[0]
		var from: Vector2i = threat[1]
		var weight: float = threat[2]
		if not _can_see(from, tile, e.sight):
			continue
		if Battle.hidden_at(battle.map, from, u, tile):
			# Lying in the wheat (or hidden in the grass or jungle), out of their sight.
			continue
		var outcome := _expected_damage(e, from, u, tile)
		danger += (outcome[0] * 10.0 + outcome[1] * KILL_BONUS * 0.5) * weight
		var cover := battle.map.cover_against(tile, from)
		if cover != Cover.NONE:
			hunker_gain += CombatRules.COVER_DEFENSE[cover] / 100.0 * _average_damage(e) * 10.0 * weight
	for strike in battle.strikes:
		if strike["kind"] != "smoke" and Vector2(tile).distance_to(Vector2(strike["target"])) <= battle.strike_reach(strike) + 0.5:
			danger += STRIKE_DANGER
	return [danger, hunker_gain]


## Best thing to do with the second action after moving to a tile.
func _followup_value(u: Unit, tile: Vector2i, seen: Array[Unit]) -> float:
	if u.ammo == 0:
		return RELOAD_EMPTY_VALUE
	if u.weapon.needs_setup:
		# Moving packs the gun away: the second action can only set it up again.
		return OVERWATCH_VALUE * 0.6
	var best := _overwatch_value(u, tile, seen)
	for e in seen:
		if _can_see(tile, e.pos, u.sight):
			best = maxf(best, _shot_value(u, tile, e))
	for p in _explosives_near(seen):
		if _can_see(tile, p, u.sight):
			var kind := battle.map.get_object_kind(p)
			var spec: Dictionary = CombatRules.EXPLOSIVES[kind]
			var value := _blast_value(p, spec["radius"], spec["damage_min"], spec["damage_max"], 0, seen)
			best = maxf(best, value * CombatRules.object_odds(u, tile, p, kind) / 100.0 - OBJECT_SHOT_COST)
	return best


func _shot_value(u: Unit, from: Vector2i, target: Unit, aimed := false) -> float:
	var outcome := _expected_damage(u, from, target, target.pos, aimed)
	var value := outcome[0] * 10.0 + outcome[1] * KILL_BONUS + (5.0 if target.overwatch else 0.0)
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
		if battle.map.has_cover(target.pos):
			value += 6.0
	if u.weapon.needs_setup:
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
	var saved := u.pos
	u.pos = from
	var odds := battle.shot_odds(u, target)
	u.pos = saved
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
func _suppress_value(u: Unit, target: Unit, seen: Array[Unit]) -> float:
	var value := _suppression_gain(target, roundi(u.weapon.suppression * CombatRules.SUPPRESSIVE_FIRE_FACTOR)) - SUPPRESSIVE_AMMO_COST
	for other in battle.alive_units(target.team):
		if other != target and not other.vehicle and seen.has(other) \
				and Vector2(other.pos).distance_to(Vector2(target.pos)) <= CombatRules.SUPPRESSIVE_FIRE_RADIUS:
			value += _suppression_gain(other, u.weapon.suppression)
	return value


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


func _overwatch_value(u: Unit, tile: Vector2i, seen: Array[Unit]) -> float:
	for e in seen:
		if Vector2(tile).distance_to(Vector2(e.pos)) <= u.sight + 3.0:
			return OVERWATCH_VALUE
	var value := OVERWATCH_VALUE * 0.5 if not _last_seen.is_empty() else 2.0
	return value * (1.0 - _aggression)


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
	for victim in battle.alive_units():
		var distance := Vector2(victim.pos).distance_to(Vector2(tile))
		if distance > radius + 1.0:
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
			victim_value += maxf(0.0, average - armor) * 10.0 + kill * KILL_BONUS
			if victim.team != team:
				hits += 1
				if battle.map.has_cover(victim.pos):
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


## [enemy, position we believe they're at, weight] for every enemy we know about.
func _threats(seen: Array[Unit]) -> Array:
	var result := []
	for e in seen:
		result.append([e, e.pos, 1.0])
	for id: int in _last_seen:
		var e := battle.get_unit(id)
		if not seen.has(e):
			result.append([e, _last_seen[id], REMEMBERED_THREAT * (1.0 - 0.8 * _aggression)])
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
		if battle.visible_from(u.pos, u.sight).has(tile):
			return true
	return false


# --- Hypothetical combat maths ---

func _can_see(from: Vector2i, to: Vector2i, sight: float) -> bool:
	if Vector2(from).distance_to(Vector2(to)) > sight:
		return false
	var key := Vector4i(from.x, from.y, to.x, to.y)
	if not _sight_cache.has(key):
		_sight_cache[key] = LineOfSight.can_see(battle.map, from, to, INF)
	return _sight_cache[key]


## [expected damage, kill probability] of shooter (standing on from) firing at target (standing on at).
func _expected_damage(shooter: Unit, from: Vector2i, target: Unit, at: Vector2i, aimed := false) -> Array[float]:
	var saved := [shooter.pos, target.pos]
	shooter.pos = from
	target.pos = at
	var odds := battle.shot_odds(shooter, target, false, aimed)
	shooter.pos = saved[0]
	target.pos = saved[1]

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
