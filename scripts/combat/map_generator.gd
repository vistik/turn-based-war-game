class_name MapGenerator
extends RefCounted
## Procedural Normandy battlefields. The same seed always gives the same map.
##
## A main road crosses the map with a village at the crossroads; a church to the north and a farm to the
## south sit on the centre line, each an objective, joined by a lane. The rest is bocage: hedged fields of
## grass, wheat, orchard or rough ground, with craters and scattered cover. Generated on the west half
## and mirrored. Maps where a spawn can't reach every objective are thrown away and rerolled.

const ATTEMPTS := 10
## Random tries at placing a field; most of the open ground ends up covered.
const FIELD_ATTEMPTS := 120


## Returns a layout for BattleFactory.create.
static func generate(seed: int, size := Vector2i(40, 40)) -> Dictionary:
	var layout := {}
	for attempt in ATTEMPTS:
		layout = _generate(seed + attempt * 7919, size)
		if is_playable(layout):
			return layout
	return layout


## Whether every spawn can walk to every objective and to the enemy's side.
static func is_playable(layout: Dictionary) -> bool:
	var map: TacticalMap = layout["map"]
	var targets: Array[Vector2i] = []
	for objective: Dictionary in layout["objectives"]:
		targets.append(Vector2i(objective["center"]))
	for spawn: Vector2i in layout["spawns"] + layout["reinforcement_spawns"]:
		if not map.is_passable(spawn):
			return false
	var reach := Pathfinder.search(map, layout["spawns"][0], 10000.0)
	for spawn: Vector2i in layout["spawns"] + layout["reinforcement_spawns"]:
		if not reach.has(spawn) or not reach.has(Vector2i(map.width - 1 - spawn.x, spawn.y)):
			return false
	for target in targets:
		if not reach.has(target):
			return false
	return true


static func _generate(seed: int, size: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := MapBuilder.new(size.x, size.y)
	var w := size.x
	var h := size.y
	var mid := w / 2
	## Tiles on the west half that bocage fields and clutter must stay off.
	var reserved := {}

	# The main road and the crossroads.
	var road := rng.randi_range(int(h * 0.38), h - 18)
	b.terrain(Rect2i(0, road, w, 2), TacticalMap.Terrain.ROAD, false)
	_reserve(reserved, Rect2i(0, road - 1, mid, 4))
	_reserve(reserved, Rect2i(0, 0, 4, h))
	# The lane and the landmarks along the centre line.
	_reserve(reserved, Rect2i(mid - 2, 0, 2, h))

	# North landmark: the church, with a lane down to the road.
	var church := rng.randi_range(1, maxi(1, road - 12))
	b.building(Rect2i(mid - 5, church, 5, 7), [[Vector2i(mid - 1, church + 6), MapBuilder.S]],
			[[Vector2i(mid - 5, church + 2), MapBuilder.W], [Vector2i(mid - 5, church + 4), MapBuilder.W], [Vector2i(mid - 3, church), MapBuilder.N]], [MapBuilder.E])
	for p in [Vector2i(mid - 4, church + 2), Vector2i(mid - 3, church + 2), Vector2i(mid - 4, church + 4), Vector2i(mid - 3, church + 4)]:
		b.object(p, Cover.HALF, "pew")
	b.terrain(Rect2i(mid - 1, church + 7, 2, road - church - 7), TacticalMap.Terrain.ROAD, false)
	_reserve(reserved, Rect2i(mid - 6, church, 6, 7))

	# South landmark: the farm, a walled courtyard in front of the farmhouse.
	var farm := rng.randi_range(road + 6, maxi(road + 6, h - 12))
	b.enclose(Rect2i(mid - 6, farm, 6, 6), Cover.HALF, "stone",
			[[Vector2i(mid - 1, farm), MapBuilder.N, Cover.NONE, ""], [Vector2i(mid - 6, farm + 2), MapBuilder.W, Cover.NONE, ""]], true, [MapBuilder.E])
	b.building(Rect2i(mid - 5, farm + 6, 5, 5), [[Vector2i(mid - 1, farm + 6), MapBuilder.N]],
			[[Vector2i(mid - 5, farm + 8), MapBuilder.W], [Vector2i(mid - 3, farm + 10), MapBuilder.S]], [MapBuilder.E])
	for p in [Vector2i(mid - 5, farm + 1), Vector2i(mid - 4, farm + 4), Vector2i(mid - 2, farm + 2)]:
		if rng.randf() < 0.8:
			b.object(p, Cover.HALF, "hay")
	b.terrain(Rect2i(mid - 1, road + 2, 2, farm - road - 2), TacticalMap.Terrain.ROAD, false)
	_reserve(reserved, Rect2i(mid - 7, farm, 7, 11))

	# Village houses beside the crossroads, sandbags on the junction corners.
	b.building(Rect2i(mid - 11, road - 6, 5, 4), [[Vector2i(mid - 9, road - 3), MapBuilder.S], [Vector2i(mid - 7, road - 5), MapBuilder.E]],
			[[Vector2i(mid - 10, road - 6), MapBuilder.N], [Vector2i(mid - 11, road - 4), MapBuilder.W]])
	b.building(Rect2i(mid - 11, road + 3, 5, 4), [[Vector2i(mid - 9, road + 3), MapBuilder.N]],
			[[Vector2i(mid - 10, road + 6), MapBuilder.S], [Vector2i(mid - 7, road + 5), MapBuilder.E]])
	_reserve(reserved, Rect2i(mid - 11, road - 6, 5, 4))
	_reserve(reserved, Rect2i(mid - 11, road + 3, 5, 4))
	b.object(Vector2i(mid - 3, road - 1), Cover.HALF, "sandbags")
	b.object(Vector2i(mid - 3, road + 2), Cover.HALF, "sandbags")
	b.object(Vector2i(mid - 6, road - 2), Cover.HALF, "crate")

	# Stone walls along the road, broken up.
	for x in range(5, mid - 12):
		if rng.randf() < 0.55:
			b.side(Vector2i(x, road - 1), MapBuilder.S, Cover.HALF, "stone")
		if rng.randf() < 0.55:
			b.side(Vector2i(x, road + 2), MapBuilder.N, Cover.HALF, "stone")

	# Bocage: rows of hedged fields across the rest of the west half.
	# Bocage: hedged fields packed into the open ground. Fields may share a hedgerow with each other,
	# but keep a tile clear of roads and buildings.
	var fields := {}
	for attempt in FIELD_ATTEMPTS:
		var size_ := Vector2i(rng.randi_range(4, 9), rng.randi_range(4, 8))
		var corner := Vector2i(rng.randi_range(5, maxi(5, mid - 3 - size_.x)), rng.randi_range(1, h - 2 - size_.y))
		var rect := Rect2i(corner, size_)
		if rect.end.x <= mid - 2 and not _overlaps(reserved, rect.grow(1)) and not _overlaps(fields, rect):
			_field(b, rng, rect)
			_reserve(fields, rect)
	reserved.merge(fields)

	# Clutter in the open ground between fields.
	for i in rng.randi_range(4, 7):
		var p := _open_tile(b, rng, reserved, mid)
		b.terrain(Rect2i(p, Vector2i.ONE), TacticalMap.Terrain.CRATER)
	for i in rng.randi_range(2, 4):
		var p := _open_tile(b, rng, reserved, mid)
		b.object(p, Cover.FULL, "rock" if rng.randf() < 0.5 else "tree")
	for i in rng.randi_range(2, 4):
		var p := _open_tile(b, rng, reserved, mid)
		b.object(p, Cover.HALF, "sandbags" if rng.randf() < 0.5 else "crate")

	var spawns: Array[Vector2i] = []
	var center := road + 1
	for offset in [0, -2, 2, -4, 4, -6, 6, -1, 1, -3, 3, 5]:
		spawns.append(Vector2i(1 + absi(offset) % 3, clampi(center + offset, 0, h - 1)))
	return {
		"map": b.map,
		"objectives": [
			{"name": "Church", "center": Vector2(mid, church + 3.5), "radius": 2.5},
			{"name": "Crossroads", "center": Vector2(mid, road + 1), "radius": 2.5},
			{"name": "Farm", "center": Vector2(mid, farm + 3), "radius": 2.5},
		],
		"spawns": spawns,
		"reinforcement_spawns": [Vector2i(1, road), Vector2i(0, 2), Vector2i(0, h - 3)],
	}


## A hedged (or walled, or open) field with grass, wheat, an orchard or rough ground inside.
static func _field(b: MapBuilder, rng: RandomNumberGenerator, rect: Rect2i) -> void:
	var boundary := rng.randf()
	if boundary < 0.8:
		var kind := "hedge" if boundary < 0.68 else "stone"
		var cover := Cover.FULL if kind == "hedge" else Cover.HALF
		var gaps := []
		for dir: Vector2i in [MapBuilder.N, MapBuilder.S, MapBuilder.W, MapBuilder.E]:
			for i in rng.randi_range(1, 2):
				var along := rect.size.x if dir.y != 0 else rect.size.y
				var t := rng.randi_range(1, along - 2)
				var tile := Vector2i(rect.position.x + t, rect.position.y if dir == MapBuilder.N else rect.end.y - 1) if dir.y != 0 \
						else Vector2i(rect.position.x if dir == MapBuilder.W else rect.end.x - 1, rect.position.y + t)
				gaps.append([tile, dir, Cover.NONE, ""])
		b.enclose(rect, cover, kind, gaps)
	var inside := rect.grow(-1) if rect.size.x > 4 and rect.size.y > 4 else rect
	var crop := rng.randf()
	if crop < 0.3:
		b.terrain(rect, TacticalMap.Terrain.WHEAT)
	elif crop < 0.5:
		for ty in range(inside.position.y, inside.end.y, 3):
			for tx in range(inside.position.x, inside.end.x, 3):
				b.object(Vector2i(tx, ty), Cover.FULL, "tree")
	elif crop < 0.62:
		b.terrain(inside, TacticalMap.Terrain.ROUGH)
	else:
		for i in rng.randi_range(0, 2):
			var p := inside.position + Vector2i(rng.randi_range(0, inside.size.x - 1), rng.randi_range(0, inside.size.y - 1))
			b.object(p, Cover.HALF, "hay")


static func _reserve(reserved: Dictionary, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			reserved[Vector2i(x, y)] = true


static func _overlaps(reserved: Dictionary, rect: Rect2i) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if reserved.has(Vector2i(x, y)):
				return true
	return false


## A random free tile on the west half, away from the spawn zone and reserved features.
static func _open_tile(b: MapBuilder, rng: RandomNumberGenerator, reserved: Dictionary, mid: int) -> Vector2i:
	for i in 50:
		var p := Vector2i(rng.randi_range(6, mid - 3), rng.randi_range(1, b.map.height - 2))
		if not reserved.has(p) and b.map.is_passable(p) and b.map.get_terrain(p) != TacticalMap.Terrain.ROAD:
			reserved[p] = true
			return p
	return Vector2i(6, 1)
