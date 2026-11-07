class_name BattleFactory
extends RefCounted
## Builds a Battle from a map layout and the two sides' rosters.
##
## A layout is {"map": TacticalMap, "objectives": Array, "spawns": [team 0 tiles (west), team 1 tiles (east)],
## "reinforcement_spawns": [team 0 tiles, team 1 tiles]}: each side starts on its own tiles, nothing mirrored.
## A roster entry is a role name, or {"role", "name", "rank", "record_id"} for campaign soldiers.
## Scenarios add "pos" (an exact start tile), "facing" and "stance" to entries, and "spawns" (exact tiles) to
## reinforcement waves.

## options: theatre (an id, Normandy if left out), vp_to_win, max_rounds, kill_points and objective_points
## ([team 0, team 1], see Battle), points_scale (multiplies vp_to_win), reinforcements: [{"round", "team", "roster", "air"?, "tunnels"?}]. A wave that is "air"
## is flown in to the side's landing zone (the layout's "landing_zones"); one that comes by "tunnels" comes up
## at the side's tunnel entrances (the layout's "tunnels": [team 0 tiles, team 1 tiles]).
static func create(layout: Dictionary, rosters: Array, seed := 0, options := {}) -> Battle:
	var map: TacticalMap = layout["map"]
	var theatre_id: String = options.get("theatre", Theatres.DEFAULT)
	var theatre := Theatres.get_theatre(theatre_id)
	var names := _NameBook.new(seed, theatre)
	var units: Array[Unit] = []
	var taken := {}
	# Units on exact tiles first, so none of the others is put on one of them.
	for team in 2:
		for entry: Variant in rosters[team]:
			if entry is Dictionary and entry.has("pos"):
				taken[entry["pos"]] = true
	for team in 2:
		var roster: Array = theatre.playable_roster(team, rosters[team])
		for i in roster.size():
			var pos: Vector2i
			if roster[i] is Dictionary and roster[i].has("pos"):
				pos = roster[i]["pos"]
			else:
				var spawns: Array = layout["spawns"][team]
				pos = _free_tile(map, spawns[i % spawns.size()], taken)
			units.append(_make_unit(units.size(), roster[i], team, pos, names, theatre_id))
	var battle := Battle.new(map, units, seed)
	battle.opening_actions = CombatRules.FIRST_TURN_ACTIONS
	battle.theatre_id = theatre_id
	for objective: Dictionary in layout["objectives"]:
		var copy := objective.duplicate()
		copy["owner"] = -1
		battle.objectives.append(copy)
	# "points_scale" multiplies the points needed to win, so a theatre can score in halves (see ModernTheatre).
	battle.vp_to_win = options.get("vp_to_win", battle.vp_to_win) * int(options.get("points_scale", 1))
	battle.kill_points = options.get("kill_points", [0, 0]).duplicate()
	battle.objective_points = options.get("objective_points", [1, 1]).duplicate()
	# The side that lays punji traps knows where every trap on the map is; its tunnels it knows anyway.
	var trap_team := theatre.trap_team()
	if trap_team != -1:
		for p: Vector2i in map.get_mines():
			if map.get_mine_kind(p) != "mine":
				battle.known_mines[trap_team][p] = true
	battle.max_rounds = options.get("max_rounds", battle.max_rounds)
	var next_id := units.size()
	for wave: Dictionary in options.get("reinforcements", []):
		var team: int = wave["team"]
		var wave_roster: Array = theatre.playable_roster(team, wave["roster"])
		if wave_roster.is_empty():
			continue
		var wave_units: Array[Unit] = []
		# The wave's own tiles (scenarios), else a landing zone or tunnel entrances, else the side's usual ones.
		var spawns: Array = wave.get("spawns", layout["reinforcement_spawns"][team])
		if wave.get("air", false) and layout.has("landing_zones"):
			spawns = [layout["landing_zones"][team]]
		elif wave.get("tunnels", false) and not layout.get("tunnels", [[], []])[team].is_empty():
			spawns = layout["tunnels"][team]
		for i in wave_roster.size():
			var pos: Vector2i = spawns[i % spawns.size()]
			wave_units.append(_make_unit(next_id, wave_roster[i], team, pos, names, theatre_id))
			next_id += 1
		battle.reinforcements.append({"round": wave["round"], "team": team, "units": wave_units, "air": wave.get("air", false)})
	return battle


## Quick test: both sides set out in a firing line in the middle of a small map, every soldier on a tile in
## his own half with cover toward the enemy where there is any, and with something to fire at from where he
## stands: an enemy in sight (and not hopelessly out of range) for a rifle, an enemy in range his side can spot
## (or he can see himself, for a forward observer; anywhere in range for a mortar firing blind) for a mortar or radio. Placed in turns, a soldier from each
## side at a time, so each side's spots answer the other's; a couple of passes fix anyone left without a target.
## Both sides open with all their actions, so a sniper or mortar can fire on the first turn. Works on a battle
## not yet started; the same battle always comes out the same.
static func arrange_firing_line(battle: Battle) -> void:
	battle.opening_actions = Unit.ACTIONS_PER_TURN
	var map := battle.map
	var mid := map.width / 2
	var zones := [Vector2i(mid - 9, mid - 2), Vector2i(mid + 1, mid + 8)]
	var rows := Vector2i(roundi(map.height * 0.18), roundi(map.height * 0.82))
	var reachable := _connected(map, battle.units[0].pos)
	var candidates := [[], []]
	for team in 2:
		for y in range(rows.x, rows.y + 1):
			for x in range(zones[team].x, zones[team].y + 1):
				var p := Vector2i(x, y)
				if reachable.has(p) and not map.has_mine(p):
					candidates[team].append(p)
	var order: Array[Unit] = []
	var sides := [battle.alive_units(0), battle.alive_units(1)]
	for team in 2:
		# Spotters and gunners first, mortars and radios last: they fire at what the others find.
		sides[team].sort_custom(func(a: Unit, b: Unit) -> bool: return (0 if a.indirect.is_empty() else 1) < (0 if b.indirect.is_empty() else 1) or ((0 if a.indirect.is_empty() else 1) == (0 if b.indirect.is_empty() else 1) and a.id < b.id))
	for i in maxi(sides[0].size(), sides[1].size()):
		for team in 2:
			if i < sides[team].size():
				order.append(sides[team][i])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(battle.checksum())
	for pass_index in 3:
		for u in order:
			if pass_index > 0 and opening_targets(battle, u) > 0:
				continue
			var best := u.pos
			var best_score := -INF
			for p: Vector2i in candidates[u.team]:
				if p != u.pos and battle.unit_at(p) != null:
					continue
				var score := _firing_spot_score(battle, u, p) + rng.randf() * 2.0
				if score > best_score:
					best_score = score
					best = p
			u.pos = best
	for u in battle.units:
		u.facing = Vector2i(1, 0) if u.team == 0 else Vector2i(-1, 0)


## How many enemies u could open fire on from where he stands (see arrange_firing_line).
static func opening_targets(battle: Battle, u: Unit) -> int:
	var count := 0
	var spec := u.indirect
	var spotted := {}
	if not spec.is_empty() and spec.get("spotter", "team") == "team":
		spotted = battle.team_visible_tiles(u.team)
	for e in battle.alive_units(1 - u.team):
		var distance := Vector2(u.pos).distance_to(Vector2(e.pos))
		if spec.is_empty():
			if u.weapon.range_modifier(distance) > -30 and battle.can_see(u, e):
				count += 1
		elif distance >= spec["min"] + 0.5 and distance <= spec["max"]:
			match spec.get("spotter", "team"):
				"self":
					if battle.can_see(u, e):
						count += 1
				"team":
					if spotted.has(e.pos):
						count += 1
				_:
					# Fires on any tile in range; it still wants one its side can see, so the round lands close.
					count += 1
	return count


static func _firing_spot_score(battle: Battle, u: Unit, p: Vector2i) -> float:
	var old := u.pos
	u.pos = p
	var targets := opening_targets(battle, u)
	var score := 0.0
	if targets > 0:
		score += 100.0 + minf(targets, 3) * 4.0
	var nearest := INF
	var cover := 0.0
	var seen := 0
	for e in battle.alive_units(1 - u.team):
		var d := Vector2(p).distance_to(Vector2(e.pos))
		nearest = minf(nearest, d)
		if d <= 14.0:
			cover += battle.map.cover_against(p, e.pos)
			seen += 1
	if seen > 0:
		score += cover / seen * 25.0
	if nearest < 4.0:
		score -= 40.0
	# Mortars and snipers hang back; everyone else keeps a few tiles from the enemy, not on top of him.
	if not u.indirect.is_empty() or u.weapon.kind == "sniper":
		score += minf(nearest, 14.0) * 1.5
	else:
		score -= absf(nearest - 8.0) * 1.0
	for f in battle.alive_units(u.team):
		if f != u and maxi(absi(f.pos.x - p.x), absi(f.pos.y - p.y)) <= 1:
			score -= 8.0
	u.pos = old
	return score


## Tiles reachable on foot from `from` (any number of steps).
static func _connected(map: TacticalMap, from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var a: Vector2i = queue.pop_back()
		for d: Vector2i in TacticalMap.DIRS4:
			var b: Vector2i = a + d
			if not seen.has(b) and map.in_bounds(b) and map.is_passable(b) and map.step_cost(a, b, 0, 0) < INF:
				seen[b] = true
				queue.append(b)
	return seen


static func _make_unit(id: int, entry: Variant, team: int, pos: Vector2i, names: _NameBook, theatre_id: String) -> Unit:
	var spec: Dictionary = entry if entry is Dictionary else {"role": entry}
	var role: String = spec["role"]
	var unit_name: String = spec.get("name", names.next(role, team))
	var u := Unit.create(id, unit_name, role, team, pos, spec.get("rank", 0), theatre_id)
	u.record_id = spec.get("record_id", -1)
	if spec.has("facing"):
		u.facing = spec["facing"]
	if spec.has("stance") and not u.vehicle:
		u.stance = Unit.stance_from(spec["stance"])
	return u


static func _free_tile(map: TacticalMap, p: Vector2i, taken: Dictionary) -> Vector2i:
	for radius in range(0, 8):
		for y in range(p.y - radius, p.y + radius + 1):
			for x in range(p.x - radius, p.x + radius + 1):
				var t := Vector2i(x, y)
				if map.is_passable(t) and not taken.has(t):
					taken[t] = true
					return t
	return p


## Hands out unique soldier names per side, from the theatre's faction name lists.
class _NameBook:
	var _rng := RandomNumberGenerator.new()
	var _used := {}
	var _tanks := [0, 0]
	var _theatre: Theatre

	func _init(seed: int, theatre: Theatre) -> void:
		_rng.seed = seed + 99
		_theatre = theatre

	func next(role: String, team: int) -> String:
		var def := _theatre.role_def(team, role)
		var faction := _theatre.faction(team)
		if def.get("vehicle", false):
			var options: Array = faction["vehicle_names"]
			_tanks[team] += 1
			return options[(_tanks[team] - 1) % options.size()]
		var pool: Array = faction["surnames"]
		var surname: String = pool[_rng.randi_range(0, pool.size() - 1)]
		for i in pool.size():
			if not _used.has(surname):
				break
			surname = pool[(pool.find(surname) + 1) % pool.size()]
		_used[surname] = true
		return def.get("name_prefix", "") + surname
