class_name ModernMapGenerator
extends RefCounted
## Procedural Afghanistan and Iraq battlefields, 2004-2010, built with NaturalMap. The same seed (and style)
## always gives the same map.
##
## - "helmand": a green zone of walled mud compounds among wheat fields edged with irrigation ditches and tree
##   lines, the bazaar where the roads meet and the mosque.
## - "town": an Iraqi town of stone houses along winding streets, the mosque, the market square and the police
##   station, with wrecked cars and concrete barriers.
## - "desert": a village of compounds in open desert, a dry wadi of rock and scrub cutting across, a
##   checkpoint on the highway.
## Then the insurgents (team 1, east) bury IEDs on the roads and ground the Coalition will cross.

const STYLES := [
	{"id": "helmand", "title": "Helmand green zone", "blurb": "Mud-walled compounds among wheat fields, irrigation ditches and tree lines."},
	{"id": "town", "title": "Iraqi town", "blurb": "Stone houses along winding streets, the market, the mosque and the police station."},
	{"id": "desert", "title": "Desert village", "blurb": "A village of compounds in open desert, a rocky wadi and a highway checkpoint."},
]


## Returns a layout for BattleFactory.create, with "style" set. No style picks one from the seed.
static func generate(seed: int, size := Vector2i(44, 44), style := "") -> Dictionary:
	if style == "":
		style = STYLES[posmod(seed, STYLES.size())]["id"]
	var layout := NaturalMap.generate(seed, size, func(nm: NaturalMap) -> Dictionary: return _build(nm, style))
	layout["style"] = style
	return layout


## [hills per 1600 tiles, hill height, chance a house has upper floors, most storeys] per style: flat-roofed
## town houses of up to three storeys, low hills on the green zone, rough ridges round the desert village.
const HEIGHTS := {"helmand": [1.5, 2, 0.3, 2], "town": [0.0, 0, 0.75, 3], "desert": [3.0, 2, 0.2, 2]}


static func _build(nm: NaturalMap, style: String) -> Dictionary:
	var scale := float(nm.width * nm.height) / 1600.0
	var heights: Array = HEIGHTS.get(style, HEIGHTS["helmand"])
	nm.hills = heights[0]
	nm.hill_height = heights[1]
	nm.tall_chance = heights[2]
	nm.tall_max = heights[3]
	match style:
		"town":
			_town(nm, scale)
		"desert":
			_desert(nm, scale)
		_:
			_helmand(nm, scale)
	var layout := nm.finish()
	if layout.is_empty():
		return layout
	layout["landing_zones"] = [nm.landing_zone(0), nm.landing_zone(1)]
	_bury_ieds(nm, layout, int(nm.rng.randi_range(3, 5) * scale))
	return layout


## A compound by the road at `at`: a mud-walled yard with the house against its back wall. Returns it, or an
## empty rect.
static func _roadside_compound(nm: NaturalMap, at: Vector2i, size: Vector2i) -> Rect2i:
	for attempt in 6:
		var offset := Vector2i(nm.rng.randi_range(-size.x - 2, 2), nm.rng.randi_range(-size.y - 2, 2))
		var rect := Rect2i(at + offset, size)
		if nm.fits(rect):
			nm.compound(rect, "mud_wall", Cover.FULL, nm.rng.randi_range(1, 2), "mud")
			return rect
	return Rect2i()


## Compounds anywhere on open ground, up to `count`.
static func _compounds(nm: NaturalMap, count: int, accept := Callable()) -> void:
	var built := 0
	for attempt in count * 6:
		if built >= count:
			return
		var rect := Rect2i(Vector2i(nm.rng.randi_range(NaturalMap.STRIP + 1, nm.width - NaturalMap.STRIP - 10), nm.rng.randi_range(1, nm.height - 9)),
				Vector2i(nm.rng.randi_range(6, 9), nm.rng.randi_range(6, 8)))
		if not nm.fits(rect) or (accept.is_valid() and not accept.call(rect.get_center())):
			continue
		nm.compound(rect, "mud_wall", Cover.FULL, nm.rng.randi_range(1, 2), "mud")
		if nm.rng.randf() < 0.6:
			nm.map.set_object(Vector2i(rect.position.x + 1, rect.end.y - 2), Cover.HALF, "hay" if nm.rng.randf() < 0.5 else "crate")
		built += 1


## Stalls, crates and a wrecked car round a road tile: a bazaar or market.
static func _market(nm: NaturalMap, at: Vector2i, landmark_name: String) -> void:
	for i in 7:
		var p := at + Vector2i(nm.rng.randi_range(-4, 4), nm.rng.randi_range(-3, 3))
		if nm.map.in_bounds(p) and nm.map.is_passable(p) and Vector2(p).distance_to(Vector2(at)) > 1.5:
			nm.map.set_object(p, Cover.HALF if i < 5 else Cover.FULL, "crate" if i < 5 else "car")
	nm.landmark(landmark_name, at)


static func _mosque(nm: NaturalMap, away: Array) -> void:
	for spot: Vector2i in MapGenerator._road_spots(nm, away, 10.0):
		var rect := nm.roadside_house(spot, Vector2i(5, 5), "stone", 2, "stone")
		if rect.size != Vector2i.ZERO:
			nm.landmark("Mosque", nm.nearest_open(rect.get_center()))
			away.append(spot)
			return


static func _helmand(nm: NaturalMap, scale: float) -> void:
	MapGenerator._east_west(nm, 2, 2)
	MapGenerator._north_south(nm, 1, 2)
	var away: Array = []
	if not nm.junctions.is_empty():
		_market(nm, nm.junctions[0], "Bazaar")
		away.append(nm.junctions[0])
		nm.village(nm.junctions[0], 6.0, 2, [Vector2i(4, 3)], "mud")
	_mosque(nm, away)
	for spot: Vector2i in MapGenerator._road_spots(nm, away, 10.0):
		var rect := _roadside_compound(nm, spot, Vector2i(8, 8))
		if rect.size != Vector2i.ZERO:
			# The house against its north wall (see NaturalMap.compound) rises two storeys: a flat roof to
			# watch the valley from.
			nm.tall(Rect2i(rect.position + Vector2i(1, 1), Vector2i(rect.size.x - 2, 3)), 2)
			nm.landmark("Compound", nm.nearest_open(rect.get_center() + Vector2i(0, 2)))
			nm.object_near(rect.get_center() + Vector2i(0, 2), Cover.HALF, "hay")
			break
	_compounds(nm, int(9 * scale))
	# Tree lines in the wildest ground, then fields of wheat (or poppies) edged with ditches.
	nm.woods(0.08, -1, ["tree"], 0.5)
	var fields := nm.patchwork(7.0, func(tiles: Array) -> Dictionary:
		if nm.rng.randf() < 0.75:
			nm.plant(tiles, TacticalMap.Terrain.WHEAT)
		return {"edge": "dyke", "cover": Cover.HALF, "gaps": 1})
	for tiles: Array in fields:
		# A tree line along a field's edge here and there.
		if nm.rng.randf() < 0.35:
			for p: Vector2i in tiles:
				if not tiles.has(p + Vector2i(0, -1)) and nm.rng.randf() < 0.5 and nm.map.is_passable(p):
					nm.map.set_object(p, Cover.FULL, "tree")
		# Fields are minor landmarks (as in Normandy), named for where they lie, so small maps with few
		# buildings still have a fair set of objectives to pick from.
		if tiles.size() >= 12:
			var center: Vector2i = tiles[tiles.size() / 2]
			var where := "North" if center.y < nm.height / 3 else ("South" if center.y >= nm.height * 2 / 3 else "Middle")
			var kind := "wheat field" if nm.map.get_terrain(center) == TacticalMap.Terrain.WHEAT else "fallow field"
			nm.landmark("%s %s" % [where, kind], nm.nearest_open(center), 0.2)
	_clutter(nm, scale, ["rock", "tree"], ["crate", "hay"])


static func _town(nm: NaturalMap, scale: float) -> void:
	MapGenerator._east_west(nm, 2, 2)
	for i in 2 + int(nm.width >= 60):
		MapGenerator._north_south(nm, 1, 2)
	MapGenerator._east_west(nm, 1, 3)
	if nm.width >= 60:
		MapGenerator._east_west(nm, 1, 3)
	var heart: Vector2i = nm.junctions[0] if not nm.junctions.is_empty() else Vector2i(nm.width / 2, nm.height / 2)
	_market(nm, heart, "Market")
	var away: Array = [heart]
	_mosque(nm, away)
	for spot: Vector2i in MapGenerator._road_spots(nm, away, 10.0):
		var station := nm.roadside_house(spot, Vector2i(6, 5), "stone", 2)
		if station.size != Vector2i.ZERO:
			nm.tall(station, 2)
			nm.landmark("Police station", nm.nearest_open(station.get_center()))
			# Blast walls and a barrier on the street in front.
			for d: Vector2i in [Vector2i(-2, -2), Vector2i(2, 2), Vector2i(-2, 2), Vector2i(2, -2)]:
				nm.object_near(spot + d, Cover.FULL, "hesco")
			nm.object_near(spot, Cover.HALF, "jersey")
			break
	var houses := nm.village(heart, nm.width * 0.5, int(24 * scale), [Vector2i(4, 3), Vector2i(5, 4), Vector2i(4, 4), Vector2i(3, 3)], "stone", 0.5, "stone")
	for rect in houses:
		if nm.rng.randf() < 0.12:
			nm.ruin(rect, 0.4)
	# Wrecked cars and concrete barriers in the streets, rubble where houses have come down.
	for i in int(7 * scale):
		var p := Vector2i(nm.rng.randi_range(NaturalMap.STRIP + 2, nm.width - NaturalMap.STRIP - 3), nm.rng.randi_range(2, nm.height - 3))
		if nm.roads.has(p) and nm.map.is_passable(p) and Vector2(p).distance_to(Vector2(heart)) > 3.0:
			nm.map.set_object(p, Cover.FULL if nm.rng.randf() < 0.5 else Cover.HALF, "car" if nm.rng.randf() < 0.5 else "jersey")
	nm.patches(int(4 * scale), TacticalMap.Terrain.RUBBLE)
	# Walled gardens and waste ground between the streets.
	var plots := nm.patchwork(6.0, func(tiles: Array) -> Dictionary:
		if nm.rng.randf() < 0.3:
			nm.plant(tiles, TacticalMap.Terrain.ROUGH)
		elif nm.rng.randf() < 0.3:
			nm.dot(tiles, 2, Cover.FULL, "palm")
		return {"edge": "stone" if nm.rng.randf() < 0.7 else "", "cover": Cover.HALF, "gaps": 1})
	MapGenerator._field_landmarks(nm, plots, "Waste ground")
	_clutter(nm, scale * 0.7, ["rock"], ["jersey", "sandbags", "crate"])


static func _desert(nm: NaturalMap, scale: float) -> void:
	MapGenerator._east_west(nm, 2, 1)
	# The wadi: a dry riverbed of rough ground and boulders winding north to south.
	var a := Vector2i(nm.rng.randi_range(int(nm.width * 0.3), int(nm.width * 0.7)), 0)
	var b := Vector2i(nm.rng.randi_range(int(nm.width * 0.3), int(nm.width * 0.7)), nm.height - 1)
	var bed := nm.road(nm.meander(a, b, 3, nm.width * 0.18), 2, TacticalMap.Terrain.ROUGH, 2.0, false)
	for p: Vector2i in bed:
		if not nm.roads.has(p) and nm.rng.randf() < 0.12:
			nm.map.set_object(p, Cover.FULL, "rock")
	# The highway crosses the wadi on a causeway.
	for p: Vector2i in nm.roads:
		nm.map.set_terrain(p, TacticalMap.Terrain.ROAD)
	var mid := bed[bed.size() / 2]
	nm.landmark("Wadi", nm.nearest_open(mid))
	# The checkpoint on the highway: blast walls and barriers, a sandbagged post.
	var away: Array = []
	for spot: Vector2i in MapGenerator._road_spots(nm, [mid], 8.0):
		for d: Vector2i in [Vector2i(-2, -2), Vector2i(-2, 3), Vector2i(2, -2), Vector2i(2, 3)]:
			nm.object_near(spot + d, Cover.FULL, "hesco")
		nm.object_near(spot + Vector2i(0, -3), Cover.HALF, "sandbags")
		nm.landmark("Checkpoint", spot)
		away.append(spot)
		break
	# The village: compounds clustered round a well, a mosque, a fuel station on the highway.
	var well := Vector2i(nm.rng.randi_range(int(nm.width * 0.3), int(nm.width * 0.7)), nm.rng.randi_range(4, nm.height - 5))
	for attempt in 20:
		if nm.is_free(well) and Vector2(well).distance_to(Vector2(away[0] if not away.is_empty() else mid)) > 10.0:
			break
		well = Vector2i(nm.rng.randi_range(int(nm.width * 0.3), int(nm.width * 0.7)), nm.rng.randi_range(4, nm.height - 5))
	nm.map.set_object(well, Cover.HALF, "jersey")
	nm.reserve(Rect2i(well - Vector2i(2, 2), Vector2i(5, 5)))
	nm.landmark("Well", nm.nearest_open(well + Vector2i(1, 0)))
	_compounds(nm, int(5 * scale) + 2, func(c: Vector2i) -> bool: return Vector2(c).distance_to(Vector2(well)) < 7.0 + 4.0 * sqrt(scale))
	_compounds(nm, int(scale))
	_mosque(nm, away)
	for spot: Vector2i in MapGenerator._road_spots(nm, away, 10.0):
		var shop := nm.roadside_house(spot, Vector2i(4, 3), "stone", 1)
		if shop.size != Vector2i.ZERO:
			nm.object_near(spot + (shop.get_center() - spot).sign(), Cover.HALF, "fuel")
			nm.object_near(spot - (shop.get_center() - spot).sign() * 2, Cover.FULL, "car")
			nm.landmark("Fuel station", nm.nearest_open(shop.get_center()))
			break
	# Scrub and boulders where the ground is wild, a few small irrigated plots near the well.
	nm.woods(0.12, TacticalMap.Terrain.ROUGH, ["rock", "rock", "tree"], 0.2)
	nm.patchwork(6.0, func(tiles: Array) -> Dictionary:
		nm.plant(tiles, TacticalMap.Terrain.WHEAT)
		return {"edge": "dyke", "cover": Cover.HALF, "gaps": 1},
		func(p: Vector2i) -> bool: return Vector2(p).distance_to(Vector2(well)) < 9.0)
	_clutter(nm, scale, ["rock"], ["crate", "jersey"])


static func _clutter(nm: NaturalMap, scale: float, full: Array, half: Array) -> void:
	nm.patches(int(nm.rng.randi_range(2, 4) * scale), TacticalMap.Terrain.CRATER)
	nm.scatter(int(nm.rng.randi_range(2, 4) * scale), Cover.FULL, full)
	nm.scatter(int(nm.rng.randi_range(2, 4) * scale), Cover.HALF, half)
	nm.scatter(1, Cover.FULL, ["car"])


## IEDs on the Coalition's way in: on the roads between their start and the objectives, and near the
## objectives on their side.
static func _bury_ieds(nm: NaturalMap, layout: Dictionary, count: int) -> void:
	var map := nm.map
	var front := 0
	for objective: Dictionary in layout["objectives"]:
		front = maxi(front, int(objective["center"].x))
	var road: Array[Vector2i] = []
	for p: Vector2i in nm.roads:
		if p.x >= 8 and p.x < front and map.get_terrain(p) == TacticalMap.Terrain.ROAD:
			road.append(p)
	for i in maxi(2, count):
		var want: Vector2i
		if i % 2 == 0 and not road.is_empty():
			want = road[nm.rng.randi_range(0, road.size() - 1)]
		else:
			var objective: Dictionary = layout["objectives"][nm.rng.randi_range(0, layout["objectives"].size() - 1)]
			want = Vector2i(objective["center"]) - Vector2i(nm.rng.randi_range(3, 6), nm.rng.randi_range(-3, 3))
		var tile := VietnamMapGenerator._free_tile(map, want, 6, front)
		if tile != Vector2i(-1, -1) and not map.has_mine(tile):
			map.set_mine(tile, true, "ied")
