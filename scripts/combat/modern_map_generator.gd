class_name ModernMapGenerator
extends RefCounted
## Procedural Afghanistan and Iraq battlefields, 2004-2010. The same seed always gives the same map.
##
## Two styles, picked by the seed: "helmand", a green zone of walled mud compounds among wheat fields, irrigation
## ditches and tree lines, and "town", an Iraqi town of stone houses on a street grid with wrecked cars and
## concrete barriers. Either way a road crosses the map and three objectives sit on the centre line. Built on
## the west half and mirrored, like MapGenerator; then the insurgents (team 1, east) bury IEDs along the
## Coalition's approach, which is not mirrored. Maps a spawn can't cross are rerolled.

const ATTEMPTS := 10
const STYLES := ["helmand", "town"]
## Compounds tried on a 40x40 map (scaled with area), and their size range.
const COMPOUND_ATTEMPTS := 40
const FIELD_ATTEMPTS := 60
## Town blocks: streets every this many tiles.
const BLOCK := 9


## Returns a layout for BattleFactory.create, with "style" set.
static func generate(seed: int, size := Vector2i(44, 44), style := "") -> Dictionary:
	if style == "":
		style = STYLES[posmod(seed, STYLES.size())]
	var layout := {}
	for attempt in ATTEMPTS:
		layout = _generate(seed + attempt * 7919, size, style)
		if MapGenerator.is_playable(layout):
			return layout
	return layout


static func _generate(seed: int, size: Vector2i, style: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := MapBuilder.new(size.x, size.y)
	var w := size.x
	var h := size.y
	var mid := w / 2
	var reserved := {}
	var road := rng.randi_range(int(h * 0.4), h - 16)
	b.terrain(Rect2i(0, road, w, 2), TacticalMap.Terrain.ROAD, false)
	MapGenerator._reserve(reserved, Rect2i(0, road - 1, mid, 4))
	MapGenerator._reserve(reserved, Rect2i(0, 0, 4, h))
	MapGenerator._reserve(reserved, Rect2i(mid - 2, 0, 2, h))
	var north := rng.randi_range(2, maxi(2, road - 13))
	var south := rng.randi_range(road + 6, maxi(road + 6, h - 10))
	var names: Array
	if style == "town":
		names = _town(b, rng, reserved, road, north, south)
	else:
		names = _helmand(b, rng, reserved, road, north, south)
	_bury_ieds(b, rng, road, int(rng.randi_range(3, 5) * float(w * h) / 1600.0))

	var spawns: Array[Vector2i] = []
	for offset in [0, -2, 2, -4, 4, -6, 6, -1, 1, -3, 3, 5, -5, 7, -7, 8]:
		spawns.append(Vector2i(1 + absi(offset) % 3, clampi(road + 1 + offset, 0, h - 1)))
	return {
		"map": b.map,
		"style": style,
		"objectives": [
			{"name": names[0], "center": Vector2(mid, north + 3.5), "radius": 2.5},
			{"name": names[1], "center": Vector2(mid, road + 1), "radius": 2.5},
			{"name": names[2], "center": Vector2(mid, south + 3), "radius": 2.5},
		],
		"spawns": spawns,
		"reinforcement_spawns": [Vector2i(1, road), Vector2i(0, 2), Vector2i(0, h - 3)],
		"landing_zones": [Vector2i(5, south), Vector2i(w - 6, south)],
	}


## The green zone: a walled compound, the bazaar on the crossing and the mosque; mud-walled compounds, wheat
## fields edged with irrigation ditches, tree lines. Returns the objectives' names.
static func _helmand(b: MapBuilder, rng: RandomNumberGenerator, reserved: Dictionary, road: int, north: int, south: int) -> Array:
	var w := b.map.width
	var h := b.map.height
	var mid := w / 2
	var area_scale := float(w * h) / 1600.0
	# The big compound on the centre line, its gate on the track down to the road.
	b.enclose(Rect2i(mid - 6, north, 6, 8), Cover.FULL, "mud_wall",
			[[Vector2i(mid - 1, north + 7), MapBuilder.S, Cover.NONE, ""], [Vector2i(mid - 6, north + 4), MapBuilder.W, Cover.NONE, ""]], true, [MapBuilder.E])
	b.building(Rect2i(mid - 5, north + 1, 4, 3), [[Vector2i(mid - 3, north + 3), MapBuilder.S]],
			[[Vector2i(mid - 5, north + 2), MapBuilder.W]], [], "mud")
	b.object(Vector2i(mid - 4, north + 6), Cover.HALF, "hay")
	b.terrain(Rect2i(mid - 1, north + 8, 2, road - north - 8), TacticalMap.Terrain.ROAD, false)
	MapGenerator._reserve(reserved, Rect2i(mid - 7, maxi(0, north - 1), 7, 10))
	# The bazaar: stalls and a wrecked car round the crossing, two little shops.
	for p in [Vector2i(mid - 4, road - 1), Vector2i(mid - 6, road + 2), Vector2i(mid - 3, road + 2)]:
		b.object(p, Cover.HALF, "crate")
	b.object(Vector2i(mid - 8, road - 1), Cover.FULL, "car")
	b.building(Rect2i(mid - 7, road - 5, 4, 3), [[Vector2i(mid - 5, road - 3), MapBuilder.S]], [[Vector2i(mid - 7, road - 4), MapBuilder.W]], [], "mud")
	MapGenerator._reserve(reserved, Rect2i(mid - 9, road - 6, 9, 10))
	# The mosque in its walled yard.
	b.building(Rect2i(mid - 4, south + 2, 4, 5), [[Vector2i(mid - 2, south + 2), MapBuilder.N]],
			[[Vector2i(mid - 4, south + 4), MapBuilder.W], [Vector2i(mid - 3, south + 6), MapBuilder.S]], [MapBuilder.E])
	b.enclose(Rect2i(mid - 6, south, 6, 8), Cover.HALF, "stone", [[Vector2i(mid - 1, south), MapBuilder.N, Cover.NONE, ""],
			[Vector2i(mid - 6, south + 1), MapBuilder.W, Cover.NONE, ""]], true, [MapBuilder.E])
	b.terrain(Rect2i(mid - 1, road + 2, 2, maxi(0, south - road - 2)), TacticalMap.Terrain.ROAD, false)
	MapGenerator._reserve(reserved, Rect2i(mid - 7, south - 1, 7, 10))

	# Compounds: mud walls with a gate or two, a house in a corner, a yard.
	for attempt in int(COMPOUND_ATTEMPTS * area_scale):
		var rect := Rect2i(Vector2i(rng.randi_range(5, mid - 10), rng.randi_range(1, h - 9)), Vector2i(rng.randi_range(6, 9), rng.randi_range(6, 8)))
		if rect.end.x > mid - 2 or rect.end.y > h - 1 or MapGenerator._overlaps(reserved, rect.grow(1)):
			continue
		var gates := []
		for i in rng.randi_range(1, 2):
			var dir: Vector2i = [MapBuilder.N, MapBuilder.S, MapBuilder.W, MapBuilder.E][rng.randi_range(0, 3)]
			var along := rect.size.x if dir.y != 0 else rect.size.y
			var t := rng.randi_range(1, along - 2)
			var tile := Vector2i(rect.position.x + t, rect.position.y if dir == MapBuilder.N else rect.end.y - 1) if dir.y != 0 \
					else Vector2i(rect.position.x if dir == MapBuilder.W else rect.end.x - 1, rect.position.y + t)
			gates.append([tile, dir, Cover.NONE, ""])
		b.enclose(rect, Cover.FULL, "mud_wall", gates)
		var house := Rect2i(rect.position + Vector2i(1, 1), Vector2i(rect.size.x - 2, 3))
		b.building(house, [[Vector2i(house.position.x + 1, house.end.y - 1), MapBuilder.S]], [[Vector2i(house.end.x - 1, house.position.y + 1), MapBuilder.E]], [], "mud")
		if rng.randf() < 0.6:
			b.object(Vector2i(rect.position.x + 1, rect.end.y - 2), Cover.HALF, "hay" if rng.randf() < 0.5 else "crate")
		MapGenerator._reserve(reserved, rect.grow(1))

	# Fields of wheat (or poppies), ditches along their edges, tree lines on the banks.
	var fields := {}
	for attempt in int(FIELD_ATTEMPTS * area_scale):
		var rect := Rect2i(Vector2i(rng.randi_range(5, mid - 6), rng.randi_range(1, h - 7)), Vector2i(rng.randi_range(4, 8), rng.randi_range(3, 6)))
		if rect.end.x > mid - 2 or MapGenerator._overlaps(reserved, rect) or MapGenerator._overlaps(fields, rect):
			continue
		b.terrain(rect, TacticalMap.Terrain.WHEAT)
		var ditch: Vector2i = [MapBuilder.N, MapBuilder.S, MapBuilder.W, MapBuilder.E][rng.randi_range(0, 3)]
		var along := rect.size.x if ditch.y != 0 else rect.size.y
		for t in along:
			var tile := Vector2i(rect.position.x + t, rect.position.y if ditch == MapBuilder.N else rect.end.y - 1) if ditch.y != 0 \
					else Vector2i(rect.position.x if ditch == MapBuilder.W else rect.end.x - 1, rect.position.y + t)
			if t != along / 2:
				b.side(tile, ditch, Cover.HALF, "dyke")
			if rng.randf() < 0.3 and b.map.is_passable(tile + ditch) and not reserved.has(tile + ditch):
				b.object(tile + ditch, Cover.FULL, "tree")
		MapGenerator._reserve(fields, rect)
	reserved.merge(fields)
	_clutter(b, rng, reserved, area_scale, ["rock", "tree"], ["crate", "hay"])
	return ["Compound", "Bazaar", "Mosque"]


## An Iraqi town: a street grid of stone houses with courtyards, the mosque, the market square and the police
## station. Returns the objectives' names.
static func _town(b: MapBuilder, rng: RandomNumberGenerator, reserved: Dictionary, road: int, north: int, south: int) -> Array:
	var w := b.map.width
	var h := b.map.height
	var mid := w / 2
	var area_scale := float(w * h) / 1600.0
	# Streets: the main road, cross streets every BLOCK tiles and one down the centre.
	var streets := [road]
	var y := road - BLOCK
	while y > 1:
		streets.append(y)
		y -= BLOCK
	y = road + BLOCK
	while y < h - 2:
		streets.append(y)
		y += BLOCK
	for sy: int in streets:
		b.terrain(Rect2i(4, sy, mid - 4, 1), TacticalMap.Terrain.ROAD)
		MapGenerator._reserve(reserved, Rect2i(0, sy - 1, mid, 3))
	var x := mid - 2 - BLOCK
	var avenues := []
	while x > 5:
		avenues.append(x)
		b.terrain(Rect2i(x, 0, 1, h), TacticalMap.Terrain.ROAD)
		MapGenerator._reserve(reserved, Rect2i(x - 1, 0, 3, h))
		x -= BLOCK
	b.terrain(Rect2i(mid - 1, 0, 2, h), TacticalMap.Terrain.ROAD, false)

	# The mosque (north), the market square (centre), the police station behind barriers (south).
	b.building(Rect2i(mid - 5, north + 1, 5, 5), [[Vector2i(mid - 3, north + 5), MapBuilder.S]],
			[[Vector2i(mid - 5, north + 2), MapBuilder.W], [Vector2i(mid - 3, north + 1), MapBuilder.N]], [MapBuilder.E])
	MapGenerator._reserve(reserved, Rect2i(mid - 6, maxi(0, north), 6, 8))
	for p in [Vector2i(mid - 4, road - 2), Vector2i(mid - 6, road - 1), Vector2i(mid - 4, road + 3), Vector2i(mid - 7, road + 2)]:
		b.object(p, Cover.HALF, "crate")
	b.object(Vector2i(mid - 3, road + 2), Cover.FULL, "car")
	MapGenerator._reserve(reserved, Rect2i(mid - 8, road - 3, 8, 7))
	b.building(Rect2i(mid - 5, south + 2, 5, 4), [[Vector2i(mid - 3, south + 2), MapBuilder.N]],
			[[Vector2i(mid - 5, south + 3), MapBuilder.W], [Vector2i(mid - 4, south + 5), MapBuilder.S]], [MapBuilder.E])
	for p in [Vector2i(mid - 5, south), Vector2i(mid - 2, south)]:
		b.object(p, Cover.FULL, "hesco")
	b.object(Vector2i(mid - 6, south + 1), Cover.HALF, "jersey")
	MapGenerator._reserve(reserved, Rect2i(mid - 7, south - 1, 7, 9))

	# Houses filling the blocks, each with a low-walled yard; alleys between them.
	for attempt in int(70 * area_scale):
		var house := Rect2i(Vector2i(rng.randi_range(5, mid - 7), rng.randi_range(1, h - 6)), Vector2i(rng.randi_range(3, 5), rng.randi_range(3, 4)))
		var yard := Rect2i(house.position + Vector2i(0, house.size.y), Vector2i(house.size.x, 2))
		var plot := house.merge(yard)
		if plot.end.x > mid - 2 or plot.end.y > h - 1 or MapGenerator._overlaps(reserved, plot.grow(1)):
			continue
		b.building(house, [[Vector2i(house.position.x + rng.randi_range(0, house.size.x - 1), house.end.y - 1), MapBuilder.S]],
				[[Vector2i(house.position.x, house.position.y + 1), MapBuilder.W], [Vector2i(house.end.x - 1, house.position.y + 1), MapBuilder.E]])
		if rng.randf() < 0.6:
			b.enclose(yard, Cover.HALF, "stone", [[Vector2i(yard.position.x + yard.size.x / 2, yard.end.y - 1), MapBuilder.S, Cover.NONE, ""]], true, [MapBuilder.N])
		MapGenerator._reserve(reserved, plot.grow(1))
	# Wrecked cars and concrete barriers on the streets, rubble where houses have come down.
	for sy: int in streets:
		for i in rng.randi_range(0, 2):
			var p := Vector2i(rng.randi_range(6, mid - 4), sy)
			if b.map.is_passable(p) and not avenues.has(p.x):
				if rng.randf() < 0.5:
					b.object(p, Cover.FULL, "car")
				else:
					b.object(p, Cover.HALF, "jersey")
	for i in int(rng.randi_range(2, 4) * area_scale):
		var at := MapGenerator._open_tile(b, rng, reserved, mid)
		b.terrain(Rect2i(at, Vector2i(2, 2)).intersection(Rect2i(0, 0, mid - 2, h)), TacticalMap.Terrain.RUBBLE)
	_clutter(b, rng, reserved, area_scale, ["rock"], ["jersey", "sandbags", "crate"])
	return ["Mosque", "Market", "Police station"]


static func _clutter(b: MapBuilder, rng: RandomNumberGenerator, reserved: Dictionary, area_scale: float, full: Array, half: Array) -> void:
	var mid := b.map.width / 2
	for i in int(rng.randi_range(2, 4) * area_scale):
		b.terrain(Rect2i(MapGenerator._open_tile(b, rng, reserved, mid), Vector2i.ONE), TacticalMap.Terrain.CRATER)
	for i in int(rng.randi_range(2, 4) * area_scale):
		b.object(MapGenerator._open_tile(b, rng, reserved, mid), Cover.FULL, full[rng.randi_range(0, full.size() - 1)])
	for i in int(rng.randi_range(2, 4) * area_scale):
		b.object(MapGenerator._open_tile(b, rng, reserved, mid), Cover.HALF, half[rng.randi_range(0, half.size() - 1)])
	b.object(MapGenerator._open_tile(b, rng, reserved, mid), Cover.FULL, "car")


## IEDs on the Coalition's way in: the road west of the crossing, and the tracks and streets near it.
static func _bury_ieds(b: MapBuilder, rng: RandomNumberGenerator, road: int, count: int) -> void:
	var map := b.map
	var mid := map.width / 2
	for i in maxi(2, count):
		var want := Vector2i(rng.randi_range(8, mid - 4), road + rng.randi_range(0, 1)) if i % 2 == 0 \
				else Vector2i(rng.randi_range(mid - 3, mid - 1), rng.randi_range(2, map.height - 3))
		var tile := VietnamMapGenerator._free_tile(map, want, 6, mid)
		if tile != Vector2i(-1, -1) and not map.has_mine(tile):
			map.set_mine(tile, true, "ied")
