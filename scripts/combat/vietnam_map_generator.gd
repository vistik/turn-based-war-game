class_name VietnamMapGenerator
extends RefCounted
## Procedural Vietnam battlefields, 1967, built with NaturalMap. The same seed (and style) always gives the
## same map.
##
## Red dirt trails wind across country of rice paddies divided by low dykes (the only cover in the open),
## elephant grass and jungle: thick undergrowth that hides whoever is in it and that sight can't get far
## through. Jungle grows where the ground is wildest, paddies where it is wettest. Three kinds of country:
## - "paddies": a valley of paddies with a hamlet on the trail and jungle on the high ground.
## - "jungle": a trail through deep jungle, a hamlet and a few clearings.
## - "delta": hamlets scattered among paddies and palm groves, little jungle.
## Then the Viet Cong (team 1, east) prepare the ground: tunnel entrances near their start and just behind
## each objective on their side, and punji traps on the trails and ground the Americans will cross.

const STYLES := [
	{"id": "paddies", "title": "Paddy valley", "blurb": "Rice paddies along a trail, a hamlet in the middle, jungle on the high ground."},
	{"id": "jungle", "title": "Jungle trail", "blurb": "A trail through deep jungle, a hamlet and a few clearings. Short sight lines."},
	{"id": "delta", "title": "Delta hamlets", "blurb": "Hamlets among paddies and palm groves; open, wet country with little jungle."},
]
const HUT_SIZES := [Vector2i(4, 3), Vector2i(4, 4), Vector2i(3, 3)]


## Returns a layout for BattleFactory.create, with "style" set. No style picks one from the seed.
static func generate(seed: int, size := Vector2i(44, 44), style := "") -> Dictionary:
	if style == "":
		style = STYLES[posmod(seed, STYLES.size())]["id"]
	var layout := NaturalMap.generate(seed, size, func(nm: NaturalMap) -> Dictionary: return _build(nm, style))
	layout["style"] = style
	return layout


static func _build(nm: NaturalMap, style: String) -> Dictionary:
	var scale := float(nm.width * nm.height) / 1600.0
	var laterite := TacticalMap.Terrain.ROAD
	# The trail, west to east, each end at its own height; a footpath north to south.
	var west := Vector2i(0, nm.rng.randi_range(int(nm.height * 0.25), int(nm.height * 0.75)))
	var east := Vector2i(nm.width - 1, nm.rng.randi_range(int(nm.height * 0.25), int(nm.height * 0.75)))
	nm.road(nm.meander(west, east, 3, nm.height * 0.15), 2 if style != "jungle" else 1, laterite, 8.0)
	var north := Vector2i(nm.rng.randi_range(int(nm.width * 0.3), int(nm.width * 0.7)), 0)
	var south := Vector2i(nm.rng.randi_range(int(nm.width * 0.3), int(nm.width * 0.7)), nm.height - 1)
	nm.road(nm.meander(north, south, 2, nm.width * 0.15), 1, laterite, 8.0)
	if not nm.junctions.is_empty():
		nm.landmark("Trail crossing", nm.junctions[0])

	var hamlets: int = {"paddies": 1, "jungle": 1, "delta": 3}[style] + int(nm.width >= 60)
	var away: Array = []
	var names := ["Hamlet", "Village", "Fishing hamlet", "Market hamlet"]
	for i in hamlets:
		for spot: Vector2i in MapGenerator._road_spots(nm, away, 11.0):
			if _hamlet(nm, spot, names[i]):
				away.append(spot)
				break
	_clearing(nm, "Landing zone", Vector2i(7, 6))
	if style == "jungle":
		_clearing(nm, "Bunker", Vector2i(5, 5))
	else:
		_temple(nm, away)

	match style:
		"jungle":
			nm.woods(0.55, TacticalMap.Terrain.JUNGLE, ["tree", "bamboo", "palm"], 0.14)
			_paddies(nm, 0.55)
		"delta":
			nm.woods(0.1, TacticalMap.Terrain.JUNGLE, ["tree", "bamboo"], 0.12)
			_groves(nm, scale)
			_paddies(nm, 0.3)
		_:
			nm.woods(0.28, TacticalMap.Terrain.JUNGLE, ["tree", "bamboo"], 0.12)
			_paddies(nm, 0.35)
	_grass(nm, scale)

	# Clutter: bomb craters, palms, termite mounds (rocks), rice sacks and a fuel drum from a supply drop.
	nm.patches(int(nm.rng.randi_range(3, 6) * scale), TacticalMap.Terrain.CRATER)
	nm.scatter(int(nm.rng.randi_range(3, 5) * scale), Cover.FULL, ["palm"])
	nm.scatter(int(nm.rng.randi_range(1, 3) * scale), Cover.FULL, ["rock"])
	nm.scatter(int(nm.rng.randi_range(1, 2) * scale), Cover.HALF, ["rice_sacks"])
	nm.scatter(1, Cover.HALF, ["fuel"])

	var layout := nm.finish()
	if layout.is_empty():
		return layout
	layout["landing_zones"] = [nm.landing_zone(0), nm.landing_zone(1)]
	layout["tunnels"] = [[], _dig_tunnels(nm, layout)]
	_lay_traps(nm, layout, int(nm.rng.randi_range(4, 6) * scale))
	return layout


## A hamlet of bamboo huts along the trail at `at`, rice sacks in the yard and palms round it.
static func _hamlet(nm: NaturalMap, at: Vector2i, hamlet_name: String) -> bool:
	var huts := nm.village(at, 7.0, nm.rng.randi_range(3, 4), HUT_SIZES, "bamboo")
	if huts.size() < 2:
		return false
	nm.landmark(hamlet_name, nm.nearest_open(at))
	for rect in huts:
		var yard := rect.get_center() + Vector2i(nm.rng.randi_range(-3, 3), nm.rng.randi_range(-3, 3))
		if nm.is_free(yard):
			nm.map.set_object(yard, Cover.HALF, "rice_sacks")
			nm.reserved[yard] = true
	for i in 4:
		var p := at + Vector2i(nm.rng.randi_range(-7, 7), nm.rng.randi_range(-7, 7))
		if nm.is_free(p):
			nm.map.set_object(p, Cover.FULL, "palm")
			nm.reserved[p] = true
	return true


## A clearing in the middle of the map kept clear of jungle: a landing zone with a sandbagged corner, or a
## bunker ringed with sandbags.
static func _clearing(nm: NaturalMap, clearing_name: String, size: Vector2i) -> void:
	for attempt in 40:
		var at := Vector2i(nm.rng.randi_range(int(nm.width * 0.3), int(nm.width * 0.7) - size.x), nm.rng.randi_range(2, nm.height - size.y - 3))
		var rect := Rect2i(at, size)
		if not nm.fits(rect) or nm.landmarks.any(func(m: Dictionary) -> bool: return Vector2(m["tile"]).distance_to(Vector2(rect.get_center())) < 9.0):
			continue
		nm.reserve(rect.grow(1))
		var c := rect.get_center()
		if clearing_name == "Bunker":
			for d: Vector2i in [Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(2, -1), Vector2i(2, 1), Vector2i(0, -2), Vector2i(1, 2)]:
				nm.map.set_object(c + d, Cover.HALF, "sandbags")
			nm.map.set_object(c + Vector2i(-1, 0), Cover.HALF, "crate")
		else:
			nm.map.set_object(rect.position, Cover.HALF, "sandbags")
			nm.map.set_object(rect.position + Vector2i(1, 0), Cover.HALF, "sandbags")
			nm.map.set_object(rect.end - Vector2i(1, 1), Cover.HALF, "crate")
		nm.landmark(clearing_name, c)
		return


## A stone pagoda by the trail, away from the hamlets.
static func _temple(nm: NaturalMap, away: Array) -> void:
	for spot: Vector2i in MapGenerator._road_spots(nm, away, 9.0):
		var rect := nm.roadside_house(spot, Vector2i(5, 5), "stone", 2)
		if rect.size != Vector2i.ZERO:
			nm.landmark("Pagoda", nm.nearest_open(rect.get_center()))
			for d: Vector2i in [Vector2i(-1, -1), Vector2i(1, 1)]:
				var p := rect.get_center() + d
				if rect.has_point(p):
					nm.map.set_object(p, Cover.HALF, "rice_sacks")
			return


## Rice paddies in the wetter ground: flooded fields divided by low dykes, a gap or two in each.
static func _paddies(nm: NaturalMap, wettest: float) -> void:
	nm.patchwork(6.0, func(tiles: Array) -> Dictionary:
		nm.plant(tiles, TacticalMap.Terrain.PADDY)
		if nm.rng.randf() < 0.25:
			nm.dot(tiles, 1, Cover.FULL, "palm")
		return {"edge": "dyke", "cover": Cover.HALF, "gaps": 1},
		func(p: Vector2i) -> bool: return nm.wet(p) >= wettest)


## Palm groves on the drier delta ground.
static func _groves(nm: NaturalMap, scale: float) -> void:
	for i in int(5 * scale):
		var at := nm.open_tile(func(p: Vector2i) -> bool: return nm.wet(p) < 0.5)
		if at.x < 0:
			continue
		for j in 6:
			var p := at + Vector2i(nm.rng.randi_range(-2, 2), nm.rng.randi_range(-2, 2))
			if nm.is_free(p) and nm.rng.randf() < 0.6:
				nm.map.set_object(p, Cover.FULL, "palm")
				nm.reserved[p] = true


## Elephant grass in the open ground, in patches that follow the noise.
static func _grass(nm: NaturalMap, scale: float) -> void:
	var patches := 0
	for i in int(12 * scale):
		if patches >= int(5 * scale):
			return
		var at := nm.open_tile(func(p: Vector2i) -> bool: return nm.map.get_terrain(p) == TacticalMap.Terrain.FLOOR)
		if at.x < 0:
			continue
		patches += 1
		var radius := nm.rng.randf_range(1.5, 3.0)
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var p := at + Vector2i(dx, dy)
				if (nm.is_free(p) or p == at) and nm.map.get_terrain(p) == TacticalMap.Terrain.FLOOR \
						and Vector2(dx, dy).length() <= radius * (0.7 + nm.grain(p) * 0.6):
					nm.map.set_terrain(p, TacticalMap.Terrain.TALL_GRASS)
					nm.reserved[p] = true


## Viet Cong tunnel entrances (team 1): one a few tiles behind each objective on their side, a couple near
## their start, one or two out in their part of the map. Returns the entrances.
static func _dig_tunnels(nm: NaturalMap, layout: Dictionary) -> Array[Vector2i]:
	var w := nm.width
	var h := nm.height
	var wanted: Array[Vector2i] = []
	for objective: Dictionary in layout["objectives"]:
		var c := Vector2i(objective["center"])
		wanted.append(c + Vector2i(nm.rng.randi_range(4, 6), nm.rng.randi_range(-2, 2)))
	for i in 2:
		wanted.append(Vector2i(w - nm.rng.randi_range(4, 7), nm.rng.randi_range(int(h * 0.25), int(h * 0.75))))
	for i in 1 + int(w >= 60):
		wanted.append(Vector2i(nm.rng.randi_range(int(w * 0.6), w - 8), nm.rng.randi_range(2, h - 3)))
	var result: Array[Vector2i] = []
	for want in wanted:
		var tile := _free_tile(nm.map, want, int(w * 0.4))
		if tile != Vector2i(-1, -1) and not result.has(tile):
			nm.map.set_tunnel(tile, 1)
			result.append(tile)
	return result


## Punji traps on the American approaches: on the trails short of the objectives and in the open ground
## between the American start and the objectives.
static func _lay_traps(nm: NaturalMap, layout: Dictionary, count: int) -> void:
	var map := nm.map
	var front := 0
	for objective: Dictionary in layout["objectives"]:
		front = maxi(front, int(objective["center"].x))
	var trail: Array[Vector2i] = []
	for p: Vector2i in nm.roads:
		if p.x >= 8 and p.x < front:
			trail.append(p)
	for i in count:
		var want := trail[nm.rng.randi_range(0, trail.size() - 1)] if i % 2 == 0 and not trail.is_empty() \
				else Vector2i(nm.rng.randi_range(8, maxi(8, front - 2)), nm.rng.randi_range(2, map.height - 3))
		var tile := _free_tile(map, want, 6, front)
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
