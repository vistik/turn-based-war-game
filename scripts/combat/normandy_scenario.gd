class_name NormandyScenario
extends RefCounted
## A 48x48 Normandy village. The Allies come from the west, Germany from the east.
## Features are placed on the west half and mirrored, so both sides fight over the same ground.
## Three objectives sit on the centre line: the church, the crossroads and the farm.

const SIZE := 48
const ROSTER := ["Officer", "Rifleman", "Rifleman", "Medic", "SMG", "MG", "Sniper", "Mortar"]
const NAMES := [
	["Lt. Hayes", "Brooks", "Carter", "Doyle", "Evans", "Foster", "Grant", "Hale"],
	["Lt. Vogel", "Albrecht", "Becker", "Dietz", "Engel", "Fischer", "Graf", "Hahn"],
]
## Allied (west) start positions, in roster order. Germany gets the mirror image.
const SPAWNS := [
	Vector2i(3, 23), Vector2i(2, 19), Vector2i(2, 28), Vector2i(1, 24),
	Vector2i(3, 26), Vector2i(3, 21), Vector2i(1, 16), Vector2i(1, 31),
]
const REINFORCEMENT_ROUND := 5
const REINFORCEMENT_SPAWNS := [Vector2i(0, 10), Vector2i(0, 38)]
const REINFORCEMENT_NAMES := [["Irwin", "Jensen"], ["Kessler", "Lang"]]
const N := Vector2i(0, -1)
const E := Vector2i(1, 0)
const S := Vector2i(0, 1)
const W := Vector2i(-1, 0)

var map := TacticalMap.new(SIZE, SIZE)


static func build(seed := 0) -> Battle:
	var builder := NormandyScenario.new()
	builder._lay_out()
	var units: Array[Unit] = []
	for team in Battle.TEAM_COUNT:
		for i in ROSTER.size():
			var spawn: Vector2i = SPAWNS[i] if team == 0 else builder._mirror(SPAWNS[i])
			units.append(Unit.create(units.size(), NAMES[team][i], ROSTER[i], team, spawn))
	var battle := Battle.new(builder.map, units, seed)
	battle.objectives = [
		{"name": "Church", "center": Vector2(24, 7.5), "radius": 2.5, "owner": -1},
		{"name": "Crossroads", "center": Vector2(24, 24), "radius": 2.5, "owner": -1},
		{"name": "Farm", "center": Vector2(24, 37), "radius": 2.5, "owner": -1},
	]
	var next_id := units.size()
	for team in Battle.TEAM_COUNT:
		var wave: Array[Unit] = []
		for i in REINFORCEMENT_SPAWNS.size():
			var spawn: Vector2i = REINFORCEMENT_SPAWNS[i] if team == 0 else builder._mirror(REINFORCEMENT_SPAWNS[i])
			wave.append(Unit.create(next_id, REINFORCEMENT_NAMES[team][i], "Rifleman", team, spawn))
			next_id += 1
		battle.reinforcements.append({"round": REINFORCEMENT_ROUND, "team": team, "units": wave})
	return battle


func _lay_out() -> void:
	# Roads: the main east-west road, and the lane from the church down to the farm.
	_terrain(Rect2i(0, 23, SIZE, 2), TacticalMap.Terrain.ROAD, false)
	_terrain(Rect2i(23, 11, 2, 23), TacticalMap.Terrain.ROAD, false)

	# The church (north objective): pews inside, doors onto the lane.
	_building(Rect2i(19, 4, 5, 7), [[Vector2i(23, 10), S]],
			[[Vector2i(19, 6), W], [Vector2i(19, 8), W], [Vector2i(21, 4), N], [Vector2i(23, 4), N]], [E])
	for p in [Vector2i(20, 6), Vector2i(21, 6), Vector2i(20, 8), Vector2i(21, 8)]:
		_object(p, Cover.HALF, "pew")

	# The farm (south objective): a walled courtyard with hay bales in front of the farmhouse.
	_enclose(Rect2i(18, 34, 6, 6), Cover.HALF, "stone", [[Vector2i(23, 34), N, Cover.NONE, ""], [Vector2i(18, 36), W, Cover.NONE, ""]], true, [E])
	_building(Rect2i(19, 40, 5, 5), [[Vector2i(23, 40), N]], [[Vector2i(19, 42), W], [Vector2i(21, 44), S]], [E])
	for p in [Vector2i(20, 35), Vector2i(20, 38), Vector2i(22, 37)]:
		_object(p, Cover.HALF, "hay")

	# Village houses at the crossroads, with sandbagged corners facing the junction.
	_building(Rect2i(16, 16, 6, 5), [[Vector2i(19, 20), S], [Vector2i(21, 18), E]],
			[[Vector2i(18, 16), N], [Vector2i(20, 16), N], [Vector2i(16, 18), W]])
	_building(Rect2i(16, 27, 6, 5), [[Vector2i(19, 27), N]],
			[[Vector2i(18, 31), S], [Vector2i(20, 31), S], [Vector2i(16, 29), W], [Vector2i(21, 29), E]])
	for p in [Vector2i(21, 22), Vector2i(21, 25), Vector2i(20, 22)]:
		_object(p, Cover.HALF, "sandbags")
	for p in [Vector2i(15, 21), Vector2i(15, 26), Vector2i(22, 15)]:
		_object(p, Cover.HALF, "crate")

	# Stone walls along the main road, with gaps.
	for x in range(6, 15):
		if x != 10:
			_side(Vector2i(x, 22), S, Cover.HALF, "stone")
		if x != 9:
			_side(Vector2i(x, 25), N, Cover.HALF, "stone")

	# Bocage: hedgerow fields. A wheat field to the north, an orchard to the south.
	_enclose(Rect2i(5, 3, 11, 10), Cover.FULL, "hedge", [[Vector2i(10, 12), S, Cover.NONE, ""], [Vector2i(15, 7), E, Cover.NONE, ""], [Vector2i(8, 3), N, Cover.NONE, ""]])
	_terrain(Rect2i(6, 4, 9, 8), TacticalMap.Terrain.WHEAT)
	_enclose(Rect2i(5, 35, 11, 10), Cover.FULL, "hedge", [[Vector2i(10, 35), N, Cover.NONE, ""], [Vector2i(15, 40), E, Cover.NONE, ""]])
	for y in [37, 40, 43]:
		for x in [7, 10, 13]:
			_object(Vector2i(x, y), Cover.FULL, "tree")
	# Hedgerows screening each start area.
	for y in range(15, 33):
		if y != 18 and y != 29 and (y < 22 or y > 25):
			_side(Vector2i(7, y), E, Cover.FULL, "hedge")
	# A small wheat field and a copse between the start and the village.
	_terrain(Rect2i(9, 27, 4, 5), TacticalMap.Terrain.WHEAT)
	for p in [Vector2i(10, 16), Vector2i(12, 17), Vector2i(10, 19), Vector2i(13, 20)]:
		_object(p, Cover.FULL, "tree")

	# Scattered cover in no man's land near the centre line.
	for p in [Vector2i(18, 13), Vector2i(20, 33), Vector2i(12, 25), Vector2i(14, 31), Vector2i(17, 46), Vector2i(19, 2)]:
		_terrain(Rect2i(p, Vector2i.ONE), TacticalMap.Terrain.CRATER)
	for p in [Vector2i(3, 8), Vector2i(2, 41), Vector2i(17, 10), Vector2i(16, 37)]:
		_object(p, Cover.FULL, "rock")
	for p in [Vector2i(17, 12), Vector2i(18, 24), Vector2i(13, 33)]:
		_object(p, Cover.HALF, "sandbags")
	_terrain(Rect2i(1, 1, 3, 4), TacticalMap.Terrain.ROUGH)
	_terrain(Rect2i(1, 43, 3, 4), TacticalMap.Terrain.ROUGH)
	_terrain(Rect2i(16, 6, 2, 3), TacticalMap.Terrain.ROUGH)


# --- Builders: each places a feature on the west half and, by default, its mirror image ---

func _mirror(p: Vector2i) -> Vector2i:
	return Vector2i(SIZE - 1 - p.x, p.y)


func _terrain(rect: Rect2i, terrain: int, mirrored := true) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			map.set_terrain(Vector2i(x, y), terrain)
			if mirrored:
				map.set_terrain(_mirror(Vector2i(x, y)), terrain)


func _object(p: Vector2i, cover: int, kind: String, mirrored := true) -> void:
	map.set_object(p, cover, kind)
	if mirrored:
		map.set_object(_mirror(p), cover, kind)


## Sets the edge on the dir side of tile p.
func _side(p: Vector2i, dir: Vector2i, cover: int, kind: String, mirrored := true) -> void:
	map.set_edge(p, p + dir, cover, kind)
	if mirrored:
		map.set_edge(_mirror(p), _mirror(p + dir), cover, kind)


## Puts edges all around a rect, then applies overrides [tile, dir, cover, kind] (cover NONE for a gap).
## Sides listed in `skip` are left open.
func _enclose(rect: Rect2i, cover: int, kind: String, overrides: Array, mirrored := true, skip: Array = []) -> void:
	for x in range(rect.position.x, rect.end.x):
		if not skip.has(N):
			_side(Vector2i(x, rect.position.y), N, cover, kind, mirrored)
		if not skip.has(S):
			_side(Vector2i(x, rect.end.y - 1), S, cover, kind, mirrored)
	for y in range(rect.position.y, rect.end.y):
		if not skip.has(W):
			_side(Vector2i(rect.position.x, y), W, cover, kind, mirrored)
		if not skip.has(E):
			_side(Vector2i(rect.end.x - 1, y), E, cover, kind, mirrored)
	for o: Array in overrides:
		_side(o[0], o[1], o[2], o[3], mirrored)


## A walled building with an indoor floor, doors [tile, dir] and windows [tile, dir].
## Buildings that straddle the centre line are built as a west half that skips its east wall.
func _building(rect: Rect2i, doors: Array, windows: Array, skip: Array = []) -> void:
	_terrain(rect, TacticalMap.Terrain.INDOOR)
	var overrides := []
	for d: Array in doors:
		overrides.append([d[0], d[1], Cover.NONE, ""])
	for w: Array in windows:
		overrides.append([w[0], w[1], Cover.HALF, "window"])
	_enclose(rect, Cover.FULL, "wall", overrides, true, skip)
