class_name BattleFactory
extends RefCounted
## Builds a Battle from a map layout and the two sides' rosters.
##
## A layout is {"map": TacticalMap, "objectives": Array, "spawns": Array[Vector2i] (Allied, west),
## "reinforcement_spawns": Array[Vector2i]}; German positions are the mirror image.
## A roster entry is a role name, or {"role", "name", "rank", "record_id"} for campaign soldiers.
## Scenarios add "pos" (an exact start tile) and "facing" to entries, and "spawns" (exact tiles, not
## mirrored) to reinforcement waves.

const SURNAMES := [
	["Adams", "Baker", "Collins", "Dawson", "Ellis", "Fisher", "Garcia", "Hughes", "Kowalski", "Lewis",
	"Murphy", "Novak", "O'Brien", "Parker", "Reyes", "Sullivan", "Turner", "Walsh", "Young", "Zimmer"],
	["Bauer", "Braun", "Frank", "Hartmann", "Huber", "Jung", "Keller", "Koch", "Krause", "Lehmann",
	"Maier", "Neumann", "Otto", "Peters", "Richter", "Schulz", "Schwarz", "Vogt", "Weber", "Wolff"],
]
const TANK_NAMES := [["Sherman \"Lucky\"", "Sherman \"Bulldog\"", "Sherman \"Ironside\""], ["Panzer IV 412", "Panzer IV 427", "Panzer IV 433"]]


## options: vp_to_win, max_rounds, reinforcements: [{"round", "team", "roster"}].
static func create(layout: Dictionary, rosters: Array, seed := 0, options := {}) -> Battle:
	var map: TacticalMap = layout["map"]
	var names := _NameBook.new(seed)
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
			units.append(_make_unit(units.size(), roster[i], team, pos, names))
	var battle := Battle.new(map, units, seed)
	for objective: Dictionary in layout["objectives"]:
		var copy := objective.duplicate()
		copy["owner"] = -1
		battle.objectives.append(copy)
	battle.vp_to_win = options.get("vp_to_win", battle.vp_to_win)
	battle.max_rounds = options.get("max_rounds", battle.max_rounds)
	var next_id := units.size()
	for wave: Dictionary in options.get("reinforcements", []):
		var team: int = wave["team"]
		var wave_units: Array[Unit] = []
		var spawns: Array = wave.get("spawns", layout["reinforcement_spawns"])
		for i in wave["roster"].size():
			var pos: Vector2i = spawns[i % spawns.size()] if wave.has("spawns") else _side(map, spawns[i % spawns.size()], team)
			wave_units.append(_make_unit(next_id, wave["roster"][i], team, pos, names))
			next_id += 1
		battle.reinforcements.append({"round": wave["round"], "team": team, "units": wave_units})
	return battle


static func _make_unit(id: int, entry: Variant, team: int, pos: Vector2i, names: _NameBook) -> Unit:
	var spec: Dictionary = entry if entry is Dictionary else {"role": entry}
	var role: String = spec["role"]
	var unit_name: String = spec.get("name", names.next(role, team))
	var u := Unit.create(id, unit_name, role, team, pos, spec.get("rank", 0))
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


## Hands out unique soldier names per side.
class _NameBook:
	var _rng := RandomNumberGenerator.new()
	var _used := {}
	var _tanks := [0, 0]

	func _init(seed: int) -> void:
		_rng.seed = seed + 99

	func next(role: String, team: int) -> String:
		if role == "Tank":
			var options: Array = BattleFactory.TANK_NAMES[team]
			_tanks[team] += 1
			return options[(_tanks[team] - 1) % options.size()]
		var pool: Array = BattleFactory.SURNAMES[team]
		var surname: String = pool[_rng.randi_range(0, pool.size() - 1)]
		for i in pool.size():
			if not _used.has(surname):
				break
			surname = pool[(pool.find(surname) + 1) % pool.size()]
		_used[surname] = true
		return ("Lt. " if role == "Officer" else "") + surname
