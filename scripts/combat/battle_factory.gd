class_name BattleFactory
extends RefCounted
## Builds a Battle from a map layout and the two sides' rosters.
##
## A layout is {"map": TacticalMap, "objectives": Array, "spawns": Array[Vector2i] (Allied, west),
## "reinforcement_spawns": Array[Vector2i]}; German positions are the mirror image.
## A roster entry is a role name, or {"role", "name", "rank", "record_id"} for campaign soldiers.
## Scenarios add "pos" (an exact start tile) and "facing" to entries, and "spawns" (exact tiles, not
## mirrored) to reinforcement waves.

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
	for team in 2:
		var roster: Array = rosters[team]
		for i in roster.size():
			var pos: Vector2i
			if roster[i] is Dictionary and roster[i].has("pos"):
				pos = roster[i]["pos"]
				taken[pos] = true
			else:
				var spawn: Vector2i = layout["spawns"][i % layout["spawns"].size()]
				pos = _free_tile(map, _side(map, spawn, team), taken)
			units.append(_make_unit(units.size(), roster[i], team, pos, names, theatre_id))
	var battle := Battle.new(map, units, seed)
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
		var wave_units: Array[Unit] = []
		var spawns: Array = wave.get("spawns", layout["reinforcement_spawns"])
		# Exact tiles (not mirrored for the second side): scenario spawns, a landing zone, tunnel entrances.
		var exact: bool = wave.has("spawns")
		if wave.get("air", false) and layout.has("landing_zones"):
			spawns = [layout["landing_zones"][team]]
			exact = true
		elif wave.get("tunnels", false) and not layout.get("tunnels", [[], []])[team].is_empty():
			spawns = layout["tunnels"][team]
			exact = true
		for i in wave["roster"].size():
			var pos: Vector2i = spawns[i % spawns.size()] if exact else _side(map, spawns[i % spawns.size()], team)
			wave_units.append(_make_unit(next_id, wave["roster"][i], team, pos, names, theatre_id))
			next_id += 1
		battle.reinforcements.append({"round": wave["round"], "team": team, "units": wave_units, "air": wave.get("air", false)})
	return battle


static func _make_unit(id: int, entry: Variant, team: int, pos: Vector2i, names: _NameBook, theatre_id: String) -> Unit:
	var spec: Dictionary = entry if entry is Dictionary else {"role": entry}
	var role: String = spec["role"]
	var unit_name: String = spec.get("name", names.next(role, team))
	var u := Unit.create(id, unit_name, role, team, pos, spec.get("rank", 0), theatre_id)
	u.record_id = spec.get("record_id", -1)
	if spec.has("facing"):
		u.facing = spec["facing"]
	return u


static func _side(map: TacticalMap, p: Vector2i, team: int) -> Vector2i:
	return p if team == 0 else Vector2i(map.width - 1 - p.x, p.y)


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
