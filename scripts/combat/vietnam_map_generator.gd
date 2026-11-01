class_name VietnamMapGenerator
extends RefCounted
## Procedural Vietnam battlefields, 1967. The same seed always gives the same map.
##
## A red dirt trail crosses the map. On the centre line sit three objectives: a hamlet of bamboo huts to the
## north, the trail crossing in the middle and a landing zone cut out of the jungle to the south. Between the
## two start areas lie rice paddies divided by low dykes (the only cover in the open), patches of elephant
## grass, and jungle: thick undergrowth that hides whoever is in it and that sight can't get far through.
## Generated on the west half and mirrored, like MapGenerator; maps a spawn can't cross are rerolled.
## Then the Viet Cong (team 1, east) prepare the ground, which is not mirrored: tunnel entrances on their
## half and close behind the objectives, and punji traps on the approaches the Americans will use.

const ATTEMPTS := 10
## Jungle blobs, paddy fields and grass patches tried on a 40x40 map (scaled with area).
const JUNGLE_BLOBS := 9
const PADDY_ATTEMPTS := 40
const GRASS_PATCHES := 5


## Returns a layout for BattleFactory.create.
static func generate(seed: int, size := Vector2i(44, 44)) -> Dictionary:
	var layout := {}
	for attempt in ATTEMPTS:
		layout = _generate(seed + attempt * 7919, size)
		if MapGenerator.is_playable(layout):
			return layout
	return layout


static func _generate(seed: int, size: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := MapBuilder.new(size.x, size.y)
	var w := size.x
	var h := size.y
	var mid := w / 2
	var area_scale := float(w * h) / 1600.0
	## Tiles on the west half that paddies, jungle and clutter must stay off.
	var reserved := {}

	# The trail: red dirt across the map, and a footpath down the centre line joining the objectives.
	var trail := rng.randi_range(int(h * 0.4), h - 16)
	b.terrain(Rect2i(0, trail, w, 2), TacticalMap.Terrain.ROAD, false)
	MapGenerator._reserve(reserved, Rect2i(0, trail - 1, mid, 4))
	MapGenerator._reserve(reserved, Rect2i(0, 0, 4, h))
	MapGenerator._reserve(reserved, Rect2i(mid - 2, 0, 2, h))

	# North: the hamlet, bamboo huts round a yard with rice sacks and a few palms.
	var hamlet := rng.randi_range(2, maxi(2, trail - 13))
	b.building(Rect2i(mid - 4, hamlet, 4, 4), [[Vector2i(mid - 2, hamlet + 3), MapBuilder.S]],
			[[Vector2i(mid - 4, hamlet + 1), MapBuilder.W], [Vector2i(mid - 2, hamlet), MapBuilder.N]], [MapBuilder.E], "bamboo")
	b.building(Rect2i(mid - 9, hamlet + 1, 4, 3), [[Vector2i(mid - 6, hamlet + 2), MapBuilder.E]],
			[[Vector2i(mid - 8, hamlet + 1), MapBuilder.N], [Vector2i(mid - 9, hamlet + 2), MapBuilder.W]], [], "bamboo")
	b.building(Rect2i(mid - 8, hamlet + 6, 4, 3), [[Vector2i(mid - 6, hamlet + 6), MapBuilder.N]],
			[[Vector2i(mid - 8, hamlet + 7), MapBuilder.W], [Vector2i(mid - 5, hamlet + 8), MapBuilder.S]], [], "bamboo")
	for p in [Vector2i(mid - 3, hamlet + 5), Vector2i(mid - 4, hamlet + 6)]:
		b.object(p, Cover.HALF, "rice_sacks")
	for p in [Vector2i(mid - 10, hamlet + 5), Vector2i(mid - 2, hamlet + 8), Vector2i(mid - 5, hamlet - 1)]:
		if b.map.in_bounds(p) and rng.randf() < 0.85:
			b.object(p, Cover.FULL, "palm")
	b.terrain(Rect2i(mid - 1, hamlet + 4, 2, trail - hamlet - 4), TacticalMap.Terrain.ROAD, false)
	MapGenerator._reserve(reserved, Rect2i(mid - 11, maxi(0, hamlet - 2), 11, 12))

	# The trail crossing: a sandbagged checkpoint on the junction.
	b.object(Vector2i(mid - 3, trail - 1), Cover.HALF, "sandbags")
	b.object(Vector2i(mid - 3, trail + 2), Cover.HALF, "sandbags")
	b.object(Vector2i(mid - 5, trail - 2), Cover.HALF, "rice_sacks")

	# South: the landing zone, a clearing of short grass ringed by jungle, with a sandbagged corner.
	var lz := rng.randi_range(trail + 7, maxi(trail + 7, h - 8))
	var clearing := Rect2i(mid - 6, lz - 3, 6, 6)
	MapGenerator._reserve(reserved, clearing.grow(1))
	b.object(Vector2i(mid - 6, lz - 3), Cover.HALF, "sandbags")
	b.object(Vector2i(mid - 5, lz + 2), Cover.HALF, "crate")
	b.terrain(Rect2i(mid - 1, trail + 2, 2, maxi(0, lz - trail - 5)), TacticalMap.Terrain.ROAD, false)
	# The jungle wall round the clearing, with gaps on the trail side and towards the start.
	var ring := clearing.grow(2)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, mini(ring.end.x, mid - 1)):
			var p := Vector2i(x, y)
			if clearing.grow(1).has_point(p) or not b.map.in_bounds(p) or reserved.has(p):
				continue
			if absi(y - lz) <= 1 or x >= mid - 3:
				continue
			b.terrain(Rect2i(p, Vector2i.ONE), TacticalMap.Terrain.JUNGLE)
	MapGenerator._reserve(reserved, ring)

	# Rice paddies: flooded fields divided by low dykes, the open ground between the starts and the centre.
	var paddies := {}
	for attempt in int(PADDY_ATTEMPTS * area_scale):
		var block := Vector2i(rng.randi_range(4, 7), rng.randi_range(3, 6))
		var corner := Vector2i(rng.randi_range(6, maxi(6, mid - 3 - block.x)), rng.randi_range(1, h - 2 - block.y))
		var rect := Rect2i(corner, block)
		if rect.end.x > mid - 2 or MapGenerator._overlaps(reserved, rect) or MapGenerator._overlaps(paddies, rect):
			continue
		b.terrain(rect, TacticalMap.Terrain.PADDY)
		var gaps := []
		for dir: Vector2i in [MapBuilder.N, MapBuilder.S, MapBuilder.W, MapBuilder.E]:
			var along := rect.size.x if dir.y != 0 else rect.size.y
			var t := rng.randi_range(0, along - 1)
			var tile := Vector2i(rect.position.x + t, rect.position.y if dir == MapBuilder.N else rect.end.y - 1) if dir.y != 0 \
					else Vector2i(rect.position.x if dir == MapBuilder.W else rect.end.x - 1, rect.position.y + t)
			gaps.append([tile, dir, Cover.NONE, ""])
		b.enclose(rect, Cover.HALF, "dyke", gaps)
		MapGenerator._reserve(paddies, rect)
		if rng.randf() < 0.3:
			b.object(rect.position + Vector2i(-1, rng.randi_range(0, rect.size.y - 1)), Cover.FULL, "palm")
	reserved.merge(paddies)

	# Jungle: blobs of thick undergrowth with tall trees and bamboo, mostly on the flanks and edges.
	for i in int(JUNGLE_BLOBS * area_scale):
		var center := Vector2(rng.randf_range(4, mid - 3), rng.randf_range(0, h))
		var radius := rng.randf_range(2.5, 5.5)
		for y in range(int(center.y - radius) - 1, int(center.y + radius) + 2):
			for x in range(int(center.x - radius) - 1, int(center.x + radius) + 2):
				var p := Vector2i(x, y)
				if p.x < 4 or p.x >= mid - 2 or not b.map.in_bounds(p) or reserved.has(p):
					continue
				# Ragged edges.
				if Vector2(p).distance_to(center) > radius * rng.randf_range(0.75, 1.15):
					continue
				b.terrain(Rect2i(p, Vector2i.ONE), TacticalMap.Terrain.JUNGLE)
				var roll := rng.randf()
				if roll < 0.08:
					b.object(p, Cover.FULL, "tree")
				elif roll < 0.12:
					b.object(p, Cover.FULL, "bamboo")
				reserved[p] = true

	# Elephant grass in the open ground.
	for i in int(GRASS_PATCHES * area_scale):
		var at := MapGenerator._open_tile(b, rng, reserved, mid)
		var patch := Rect2i(at, Vector2i(rng.randi_range(2, 4), rng.randi_range(2, 4)))
		for y in range(patch.position.y, patch.end.y):
			for x in range(patch.position.x, patch.end.x):
				var p := Vector2i(x, y)
				if p.x < mid - 2 and b.map.in_bounds(p) and not reserved.has(p) and b.map.get_terrain(p) == TacticalMap.Terrain.FLOOR:
					b.terrain(Rect2i(p, Vector2i.ONE), TacticalMap.Terrain.TALL_GRASS)
					reserved[p] = true

	# Clutter: bomb craters, palms, termite mounds (rocks), a few fuel drums from a supply drop.
	for i in int(rng.randi_range(3, 6) * area_scale):
		b.terrain(Rect2i(MapGenerator._open_tile(b, rng, reserved, mid), Vector2i.ONE), TacticalMap.Terrain.CRATER)
	for i in int(rng.randi_range(3, 5) * area_scale):
		b.object(MapGenerator._open_tile(b, rng, reserved, mid), Cover.FULL, "palm")
	for i in int(rng.randi_range(1, 3) * area_scale):
		b.object(MapGenerator._open_tile(b, rng, reserved, mid), Cover.FULL, "rock")
	for i in int(rng.randi_range(1, 2) * area_scale):
		b.object(MapGenerator._open_tile(b, rng, reserved, mid), Cover.HALF, "rice_sacks")
	b.object(MapGenerator._open_tile(b, rng, reserved, mid), Cover.HALF, "fuel")

	var tunnels := _dig_tunnels(b, rng, [hamlet + 2, trail + 1, lz])
	_lay_traps(b, rng, trail, int(rng.randi_range(4, 6) * area_scale))

	var spawns: Array[Vector2i] = []
	var center := trail + 1
	for offset in [0, -2, 2, -4, 4, -6, 6, -1, 1, -3, 3, 5, -5, 7, -7, 8]:
		spawns.append(Vector2i(1 + absi(offset) % 3, clampi(center + offset, 0, h - 1)))
	return {
		"map": b.map,
		"objectives": [
			{"name": "Hamlet", "center": Vector2(mid, hamlet + 2.5), "radius": 2.5},
			{"name": "Trail crossing", "center": Vector2(mid, trail + 1), "radius": 2.5},
			{"name": "Landing zone", "center": Vector2(mid, lz + 0.5), "radius": 2.5},
		],
		"spawns": spawns,
		"reinforcement_spawns": [Vector2i(1, trail), Vector2i(0, 2), Vector2i(0, h - 3)],
		# A helicopter landing zone in each side's half, for reinforcements flown in.
		"landing_zones": [Vector2i(mid - 10, lz), Vector2i(w - 1 - (mid - 10), lz)],
		"tunnels": [[], tunnels],
	}


## Viet Cong tunnel entrances (team 1): a couple near their start, one a few tiles behind each objective on
## their side, and one or two out on their flanks. Returns the entrances.
static func _dig_tunnels(b: MapBuilder, rng: RandomNumberGenerator, objective_rows: Array) -> Array[Vector2i]:
	var map := b.map
	var w := map.width
	var h := map.height
	var mid := w / 2
	var wanted: Array[Vector2i] = []
	for y: int in objective_rows:
		wanted.append(Vector2i(mid + rng.randi_range(4, 6), y + rng.randi_range(-2, 2)))
	for i in 2:
		wanted.append(Vector2i(w - rng.randi_range(4, 7), rng.randi_range(int(h * 0.25), int(h * 0.75))))
	for i in 1 + int(w >= 60):
		wanted.append(Vector2i(rng.randi_range(mid + 6, w - 8), rng.randi_range(2, h - 3)))
	var result: Array[Vector2i] = []
	for want in wanted:
		var tile := _free_tile(map, want, mid + 2)
		if tile != Vector2i(-1, -1) and not result.has(tile):
			map.set_tunnel(tile, 1)
			result.append(tile)
	return result


## Punji traps on the American approaches: on the trail and in the open ground short of the centre line.
static func _lay_traps(b: MapBuilder, rng: RandomNumberGenerator, trail: int, count: int) -> void:
	var map := b.map
	var mid := map.width / 2
	for i in count:
		var want := Vector2i(rng.randi_range(mid - 12, mid - 3), trail + rng.randi_range(0, 1)) if i % 2 == 0 \
				else Vector2i(rng.randi_range(8, mid - 3), rng.randi_range(2, map.height - 3))
		var tile := _free_tile(map, want, 6, mid - 2)
		if tile != Vector2i(-1, -1) and not map.has_mine(tile):
			map.set_mine(tile, true, "punji")


## A free, open tile near `want` with min_x <= x < max_x (no object, tunnel, trap or building floor), or (-1, -1).
static func _free_tile(map: TacticalMap, want: Vector2i, min_x: int, max_x := -1) -> Vector2i:
	if max_x < 0:
		max_x = map.width - 1
	for radius in range(0, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var p := want + Vector2i(dx, dy)
				if p.x < min_x or p.x >= max_x or not map.in_bounds(p) or not map.is_passable(p):
					continue
				if map.has_mine(p) or map.tunnel_owner(p) != -1 or map.get_terrain(p) == TacticalMap.Terrain.INDOOR:
					continue
				return p
	return Vector2i(-1, -1)
