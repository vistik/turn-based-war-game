class_name TacticalAI
extends RefCounted
## Utility AI for one team. It plays fair: it only knows what its team can see, plus where it last saw enemies.
## Every call to act() scores all plans for all units, issues the best one as a single engine command
## (or ends the turn) and returns the resulting events.
##
## Scores are in "expected damage x 10" units so offence, defence, objectives and positioning can be compared.

const KILL_BONUS := 40.0
## How much a point of expected incoming damage at a tile counts against standing there.
const DANGER_WEIGHT := 0.8
## Danger from enemies we only remember (not currently seen) counts this much.
const REMEMBERED_THREAT := 0.5
const COVER_WEIGHT := 4.0
## Score lost per tile of distance from the goal when no enemy is in sight.
const APPROACH_WEIGHT := 3.0
## Score lost per tile away from the role's preferred range to the nearest seen enemy.
const RANGE_WEIGHT := 1.5
const PREFERRED_RANGE := {"Officer": 5.0, "Rifleman": 7.0, "Medic": 6.0, "SMG": 3.0, "MG": 9.0, "Sniper": 12.0, "Mortar": 14.0}
## Score per point of suppression a shot or blast adds to an enemy.
const SUPPRESSION_VALUE := 0.15
## Standing on an objective we don't hold / already hold, and the pull toward the nearest one we don't hold.
const OBJECTIVE_TAKE := 14.0
const OBJECTIVE_HOLD := 6.0
const OBJECTIVE_PULL := 1.0
## Allies this close together risk sharing a grenade or shell.
const CROWDING_PENALTY := 4.0
## Danger of standing where a mortar shell is about to land.
const STRIKE_DANGER := 45.0
const GRENADE_COST := 20.0
const MORTAR_COST := 10.0
## Enemies may move before a mortar shell lands, so only part of its value counts.
const MORTAR_CERTAINTY := 0.5
const OVERWATCH_VALUE := 10.0
const RELOAD_EMPTY_VALUE := 30.0
const MEDKIT_VALUE_PER_HP := 8.0
const RALLY_VALUE := 0.4
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


func act() -> Array:
	if battle.winner != -1 or battle.current_team != team:
		return []
	_sight_cache.clear()
	_remember()
	var seen := _seen_enemies()
	if battle.round_number != _round:
		_round = battle.round_number
		_quiet_rounds = _quiet_rounds + 1 if seen.is_empty() else 0
	if not seen.is_empty():
		_quiet_rounds = 0
	_aggression = clampf(_quiet_rounds / PATIENCE_ROUNDS, 0.0, 1.0)
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
		return battle.end_turn()
	var events := _execute(best)
	if events.is_empty():
		push_warning("AI plan %s was rejected; ending turn" % best["kind"])
		return battle.end_turn()
	return events


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
				var value := _blast_value(tile, CombatRules.GRENADE_RADIUS, CombatRules.GRENADE_DAMAGE_MIN, CombatRules.GRENADE_DAMAGE_MAX, CombatRules.GRENADE_SHRED, seen)
				if value > 0.0:
					plans.append(_plan(u, "grenade", stay + value - GRENADE_COST, null, tile))
	if u.role == "Mortar" and u.mortar_rounds > 0 and u.actions >= Unit.ACTIONS_PER_TURN:
		for tile in _tiles_around(seen):
			if battle.can_fire_mortar(u, tile, "he") == "":
				var value := _blast_value(tile, CombatRules.MORTAR_RADIUS + Battle.mortar_scatter(u.pos, tile) * 0.5,
						CombatRules.MORTAR_DAMAGE_MIN, CombatRules.MORTAR_DAMAGE_MAX, 0, seen)
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
	if map.has_cover(here):
		plans.append(_plan(u, "hunker", stay + _danger(u, here, seen)[1]))

	var reach := battle.reachable(u)
	for tile: Vector2i in reach:
		if tile == here or reach[tile]["cost"] > u.current_mobility() + 0.001:
			continue
		var value := _position_score(u, tile, seen)
		if u.actions >= 2:
			value += _followup_value(u, tile, seen)
		plans.append(_plan(u, "move", value, null, tile))

	var best := {}
	for plan in plans:
		if best.is_empty() or plan["value"] > best["value"]:
			best = plan
	return best


func _plan(u: Unit, kind: String, value: float, target: Unit = null, tile := Vector2i.ZERO) -> Dictionary:
	return {"unit": u, "kind": kind, "value": value, "target": target, "tile": tile}


func _execute(plan: Dictionary) -> Array:
	var u: Unit = plan["unit"]
	match plan["kind"]:
		"shoot":
			return battle.shoot(u, plan["target"])
		"grenade":
			return battle.throw_grenade(u, plan["tile"])
		"mortar":
			return battle.fire_mortar(u, plan["tile"], "he")
		"medkit":
			return battle.use_medkit(u, plan["target"])
		"rally":
			return battle.rally(u)
		"set_up":
			return battle.set_up(u)
		"reload":
			return battle.reload(u)
		"overwatch":
			return battle.overwatch(u)
		"hunker":
			return battle.hunker(u)
		"move":
			return battle.move(u, plan["tile"])
	return []


## How good it is to stand on a tile at the end of an action: cover, danger, objectives, range and approach.
func _position_score(u: Unit, tile: Vector2i, seen: Array[Unit]) -> float:
	var map := battle.map
	var best_cover := Cover.NONE
	for d: Vector2i in TacticalMap.DIRS4:
		best_cover = maxi(best_cover, map.cover_toward(tile, d))
	var score := best_cover * COVER_WEIGHT

	var caution := 2.0 - float(u.hp) / u.max_hp
	score -= _danger(u, tile, seen)[0] * DANGER_WEIGHT * caution

	var point := Vector2(tile) + Vector2(0.5, 0.5)
	var nearest_open := INF
	for objective in battle.objectives:
		var distance: float = point.distance_to(objective["center"])
		if distance <= objective["radius"]:
			score += OBJECTIVE_HOLD if objective["owner"] == team else OBJECTIVE_TAKE
		if objective["owner"] != team:
			nearest_open = minf(nearest_open, distance)

	if seen.is_empty():
		score -= Vector2(tile).distance_to(_goal(tile)) * APPROACH_WEIGHT * (1.0 + 2.0 * _aggression)
	else:
		var nearest := INF
		for e in seen:
			nearest = minf(nearest, Vector2(tile).distance_to(Vector2(e.pos)))
		score -= absf(nearest - PREFERRED_RANGE.get(u.role, 6.0)) * RANGE_WEIGHT
		if nearest_open < INF and u.role != "Mortar" and u.role != "Sniper":
			score -= nearest_open * OBJECTIVE_PULL

	for ally in battle.alive_units(team):
		if ally != u and Vector2(ally.pos).distance_to(Vector2(tile)) <= CombatRules.GRENADE_RADIUS:
			score -= CROWDING_PENALTY
	return score


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
		var outcome := _expected_damage(e, from, u, tile)
		danger += (outcome[0] * 10.0 + outcome[1] * KILL_BONUS * 0.5) * weight
		var cover := battle.map.cover_against(tile, from)
		if cover != Cover.NONE:
			hunker_gain += CombatRules.COVER_DEFENSE[cover] / 100.0 * _average_damage(e) * 10.0 * weight
	for strike in battle.strikes:
		if strike["kind"] == "he" and Vector2(tile).distance_to(Vector2(strike["target"])) <= CombatRules.MORTAR_RADIUS + float(strike["scatter"]) + 0.5:
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
	return best


func _shot_value(u: Unit, from: Vector2i, target: Unit) -> float:
	var outcome := _expected_damage(u, from, target, target.pos)
	var value := outcome[0] * 10.0 + outcome[1] * KILL_BONUS + (5.0 if target.overwatch else 0.0)
	var suppression := mini(100 - target.suppression, u.weapon.suppression)
	if u.weapon.needs_setup:
		for ally in battle.alive_units(target.team):
			if ally != target and Vector2(ally.pos).distance_to(Vector2(target.pos)) <= CombatRules.MG_AREA_RADIUS:
				suppression += mini(100 - ally.suppression, int(u.weapon.suppression / 2.0))
	return value + suppression * SUPPRESSION_VALUE


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


func _blast_value(tile: Vector2i, radius: float, damage_min: int, damage_max: int, shred: int, seen: Array[Unit]) -> float:
	var value := 0.0
	var hits := 0
	var average := (damage_min + damage_max) / 2.0
	for victim in battle.alive_units():
		var distance := Vector2(victim.pos).distance_to(Vector2(tile))
		if distance > radius + 1.0:
			continue
		if victim.team != team and not seen.has(victim):
			continue
		var victim_value := mini(100 - victim.suppression, CombatRules.EXPLOSION_SUPPRESSION) * SUPPRESSION_VALUE
		if distance <= radius:
			var armor := maxi(0, victim.armor - shred)
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
	return value if hits > 0 else 0.0


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
func _expected_damage(shooter: Unit, from: Vector2i, target: Unit, at: Vector2i) -> Array[float]:
	var saved := [shooter.pos, target.pos]
	shooter.pos = from
	target.pos = at
	var odds := battle.shot_odds(shooter, target)
	shooter.pos = saved[0]
	target.pos = saved[1]

	var hit: float = odds["hit"] / 100.0
	var crit: float = odds["crit"] / 100.0
	var graze: float = odds["graze"] / 100.0
	var w := shooter.weapon
	var rolls := w.damage_max - w.damage_min + 1
	var expected := 0.0
	var kill := 0.0
	for d in range(w.damage_min, w.damage_max + 1):
		var normal := maxi(0, d - target.armor)
		var critical := maxi(0, d + w.crit_damage - target.armor)
		var grazed := maxi(0, maxi(1, floori(d / 2.0)) - target.armor)
		expected += (hit * ((1.0 - crit) * normal + crit * critical) + graze * grazed) / rolls
		kill += (hit * ((1.0 - crit) * float(normal >= target.hp) + crit * float(critical >= target.hp)) + graze * float(grazed >= target.hp)) / rolls
	return [expected, kill]


func _average_damage(u: Unit) -> float:
	return (u.weapon.damage_min + u.weapon.damage_max) / 2.0
