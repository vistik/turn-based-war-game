class_name MapGenerator
extends RefCounted
## Procedural Normandy battlefields, built with NaturalMap. The same seed (and style) always gives the same map.
##
## Four kinds of country, each lopsided the way real ground is; fairness comes from objectives each side walks
## about as far to (see NaturalMap.fair_objectives):
## - "bocage": a village where a winding road crosses a lane, a church, outlying farms, hedged fields.
## - "hamlets": a web of sunken lanes between farmsteads, small hedged fields and orchards, no village.
## - "town": a shelled market town, streets of stone houses round a square, many of them in ruins.
## - "forest": a road through a wood with a sawmill and a lodge in clearings, farmland on the open side.

## Map sizes offered in skirmish.
const SIZES := {"Standard": 44, "Large": 64, "Huge": 84}
const STYLES := [
	{"id": "bocage", "title": "Bocage crossroads", "blurb": "A village where the road crosses a lane, a church, farms and hedged fields."},
	{"id": "hamlets", "title": "Hedgerow hamlets", "blurb": "Sunken lanes between farmsteads; small hedged fields and orchards everywhere."},
	{"id": "town", "title": "Shelled market town", "blurb": "Streets of stone houses round a square, many of them in ruins."},
	{"id": "forest", "title": "Forest edge", "blurb": "A road through a wood: a sawmill and a lodge in its clearings, farmland beyond."},
]
const HOUSE_SIZES := [Vector2i(5, 4), Vector2i(4, 3), Vector2i(6, 4), Vector2i(4, 4)]


## Returns a layout for BattleFactory.create, with "style" set. No style picks one from the seed.
static func generate(seed: int, size := Vector2i(44, 44), style := "") -> Dictionary:
	if style == "":
		style = STYLES[posmod(seed, STYLES.size())]["id"]
	var layout := NaturalMap.generate(seed, size, func(nm: NaturalMap) -> Dictionary: return _build(nm, style))
	layout["style"] = style
	return layout


## Whether every spawn can reach every objective and the enemy's side.
static func is_playable(layout: Dictionary) -> bool:
	return NaturalMap.is_playable(layout)


static func _build(nm: NaturalMap, style: String) -> Dictionary:
	match style:
		"hamlets":
			_hamlets(nm)
		"town":
			_town(nm)
		"forest":
			_forest(nm)
		_:
			_bocage(nm)
	_hazards(nm)
	return nm.finish()


static func _scale(nm: NaturalMap) -> float:
	return float(nm.width * nm.height) / 1600.0


## A road from the west edge to the east edge, each end at its own height.
static func _east_west(nm: NaturalMap, road_width: int, bends := 2) -> Array[Vector2i]:
	var a := Vector2i(0, nm.rng.randi_range(int(nm.height * 0.25), int(nm.height * 0.75)))
	var b := Vector2i(nm.width - 1, nm.rng.randi_range(int(nm.height * 0.25), int(nm.height * 0.75)))
	return nm.road(nm.meander(a, b, bends, nm.height * 0.12), road_width)


## A road from the north edge to the south edge, both ends somewhere in the middle half.
static func _north_south(nm: NaturalMap, road_width: int, bends := 2) -> Array[Vector2i]:
	var a := Vector2i(nm.rng.randi_range(int(nm.width * 0.3), int(nm.width * 0.7)), 0)
	var b := Vector2i(nm.rng.randi_range(int(nm.width * 0.3), int(nm.width * 0.7)), nm.height - 1)
	return nm.road(nm.meander(a, b, bends, nm.width * 0.12), road_width)


## The middle of the map, where the objectives are fought over.
static func _middling(nm: NaturalMap, p: Vector2i) -> bool:
	return p.x > nm.width * 0.28 and p.x < nm.width * 0.72


## Road tiles in the middle of the map at least `apart` from every tile in `away`, nearest the middle first.
static func _road_spots(nm: NaturalMap, away: Array, apart: float) -> Array[Vector2i]:
	var spots: Array = []
	for p: Vector2i in nm.roads:
		if not _middling(nm, p) or p.y < 3 or p.y > nm.height - 4:
			continue
		if away.any(func(q: Vector2i) -> bool: return Vector2(p).distance_to(Vector2(q)) < apart):
			continue
		spots.append([nm.rng.randf(), p])
	spots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var result: Array[Vector2i] = []
	for s: Array in spots:
		result.append(s[1])
	return result


## The village church: pews inside, the door onto the road. Returns the church, or an empty rect.
static func _church(nm: NaturalMap, at: Vector2i, landmark_name := "Church") -> Rect2i:
	var rect := nm.roadside_house(at, Vector2i(7, 5), "stone", 2)
	if rect.size == Vector2i.ZERO:
		return rect
	var long_x := rect.size.x >= rect.size.y
	for i in range(1, (rect.size.x if long_x else rect.size.y) - 2, 2):
		for j in [1, rect.size.y - 2] if long_x else [1, rect.size.x - 2]:
			var p := rect.position + (Vector2i(i, j) if long_x else Vector2i(j, i))
			nm.map.set_object(p, Cover.HALF, "pew")
	nm.landmark(landmark_name, nm.nearest_open(rect.get_center()))
	return rect


## A farmstead by the road at `at`: the farmhouse with a walled yard and hay, maybe a barn. Returns whether it
## was built (and registers it as a landmark).
static func _farm(nm: NaturalMap, at: Vector2i, landmark_name: String) -> bool:
	var rect := nm.roadside_house(at, Vector2i(5, 4), "stone", nm.rng.randi_range(1, 2), "stone")
	if rect.size == Vector2i.ZERO:
		return false
	nm.landmark(landmark_name, nm.nearest_open(rect.get_center()))
	var spots := 0
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var p := rect.get_center() + Vector2i(dx, dy)
			if spots < 3 and nm.solid.has(p) and nm.map.get_terrain(p) != TacticalMap.Terrain.INDOOR and nm.map.is_passable(p) \
					and nm.rng.randf() < 0.25:
				nm.map.set_object(p, Cover.HALF, "hay")
				spots += 1
	# A barn further along the road.
	nm.village(at, 7.0, 1, [Vector2i(6, 4), Vector2i(5, 4)], "stone")
	return true


## The bocage: hedged fields of wheat, pasture and orchard, with a few stone-walled ones; copses where the
## ground is wildest.
static func _countryside(nm: NaturalMap, spacing: float, woods_share: float) -> void:
	nm.woods(woods_share, -1, ["tree"], 0.45)
	var fields := nm.patchwork(spacing, func(tiles: Array) -> Dictionary:
		var roll := nm.rng.randf()
		var damp := nm.wet(tiles[0])
		if roll < 0.22:
			nm.orchard(tiles)
		elif damp < 0.45 and roll < 0.7:
			nm.plant(tiles, TacticalMap.Terrain.WHEAT)
		elif roll < 0.8:
			nm.plant(tiles.filter(func(p: Vector2i) -> bool: return nm.grain(p) > 0.45), TacticalMap.Terrain.ROUGH)
		else:
			nm.dot(tiles, nm.rng.randi_range(0, 2), Cover.HALF, "hay")
		var edge := nm.rng.randf()
		if edge < 0.72:
			return {"edge": "hedge", "cover": Cover.FULL, "gaps": 0}
		if edge < 0.86:
			return {"edge": "stone", "cover": Cover.HALF, "gaps": 0}
		return {"edge": "", "cover": Cover.NONE, "gaps": 0})
	_field_landmarks(nm, fields)


## The biggest fields in the middle of the map as fall-back objectives, named for what grows there
## (`plain` for a field of nothing much).
static func _field_landmarks(nm: NaturalMap, fields: Array, plain := "Meadow") -> void:
	var middle := fields.filter(func(tiles: Array) -> bool: return tiles.size() >= 12 and _middling(nm, tiles[tiles.size() / 2]))
	middle.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	for tiles: Array in middle.slice(0, 4):
		var center: Vector2i = tiles[tiles.size() / 2]
		var kind := nm.map.get_terrain(center)
		var landmark_name := "Wheat field" if kind == TacticalMap.Terrain.WHEAT else ("Orchard" if tiles.any(func(p: Vector2i) -> bool:
			return nm.map.get_object_kind(p) == "tree") else plain)
		nm.landmark(landmark_name, nm.nearest_open(center), 0.2)


static func _bocage(nm: NaturalMap) -> void:
	var scale := _scale(nm)
	_east_west(nm, 2)
	_north_south(nm, 1)
	if nm.width >= 60:
		# A farm track off to one side.
		var a := Vector2i(nm.rng.randi_range(int(nm.width * 0.2), int(nm.width * 0.8)), 0 if nm.rng.randf() < 0.5 else nm.height - 1)
		var b := Vector2i(nm.rng.randi_range(int(nm.width * 0.3), int(nm.width * 0.7)), nm.height / 2)
		nm.road(nm.meander(a, b, 1, 6.0), 1)
	var heart: Vector2i = nm.junctions[0] if not nm.junctions.is_empty() else Vector2i(nm.width / 2, nm.height / 2)
	nm.landmark("Crossroads", heart)
	var church_spots := _road_spots(nm, [heart], 4.0).filter(func(p: Vector2i) -> bool: return Vector2(p).distance_to(Vector2(heart)) < 11.0)
	for spot: Vector2i in church_spots:
		if _church(nm, spot).size != Vector2i.ZERO:
			break
	for p: Vector2i in [heart + Vector2i(2, -2), heart + Vector2i(-3, 3)]:
		if nm.map.in_bounds(p) and nm.map.is_passable(p) and not nm.roads.has(p):
			nm.map.set_object(p, Cover.HALF, "sandbags")
	nm.village(heart, 10.0, int(6 * sqrt(scale)), HOUSE_SIZES, "stone", 0.4, "stone")
	var away: Array = [heart]
	for farm_name: String in ["Farm", "Manor", "Mill"]:
		for spot in _road_spots(nm, away, 12.0):
			if _farm(nm, spot, farm_name):
				away.append(spot)
				break
	_countryside(nm, 8.5, 0.1)
	_clutter(nm, scale)


static func _hamlets(nm: NaturalMap) -> void:
	var scale := _scale(nm)
	# Sunken lanes wandering between the edges and each other.
	_east_west(nm, 1, 3)
	for i in 2 + int(nm.width >= 60):
		if i % 2 == 0:
			_north_south(nm, 1, 2)
		else:
			_east_west(nm, 1, 3)
	var away: Array = []
	for farm_name: String in ["Farm", "Manor", "Mill", "Hamlet", "Dairy"]:
		for spot in _road_spots(nm, away, 10.0):
			if _farm(nm, spot, farm_name):
				away.append(spot)
				break
	for spot in _road_spots(nm, away, 8.0):
		if _church(nm, spot, "Chapel").size != Vector2i.ZERO:
			break
	if not nm.junctions.is_empty():
		nm.landmark("Crossroads", nm.junctions[0])
	_countryside(nm, 6.5, 0.08)
	_clutter(nm, scale)


static func _town(nm: NaturalMap) -> void:
	var scale := _scale(nm)
	_east_west(nm, 2, 2)
	for i in 1 + int(nm.width >= 60):
		_north_south(nm, 2, 1)
	_east_west(nm, 1, 2)
	_north_south(nm, 1, 2)
	var heart: Vector2i = nm.junctions[0] if not nm.junctions.is_empty() else Vector2i(nm.width / 2, nm.height / 2)
	# The square: paved, a fountain (rock) and a wrecked lorry.
	var square := Rect2i(heart - Vector2i(3, 2), Vector2i(6, 5))
	for y in range(square.position.y, square.end.y):
		for x in range(square.position.x, square.end.x):
			var p := Vector2i(x, y)
			if nm.in_play(p) and not nm.solid.has(p):
				nm.map.set_terrain(p, TacticalMap.Terrain.ROAD)
				nm.roads[p] = -1
				nm.reserved[p] = true
	nm.map.set_object(heart + Vector2i(1, 1), Cover.FULL, "rock")
	nm.map.set_object(heart + Vector2i(-2, 0), Cover.FULL, "wreck")
	nm.landmark("Town square", heart)
	for spot: Vector2i in _road_spots(nm, [heart], 4.0):
		if Vector2(spot).distance_to(Vector2(heart)) < 9.0 and _church(nm, spot).size != Vector2i.ZERO:
			break
	for spot: Vector2i in _road_spots(nm, [heart], 8.0):
		var hall := nm.roadside_house(spot, Vector2i(7, 5), "stone", 1)
		if hall.size != Vector2i.ZERO:
			nm.landmark("Town hall", nm.nearest_open(hall.get_center()))
			break
	for spot: Vector2i in _road_spots(nm, [heart], 14.0):
		var station := nm.roadside_house(spot, Vector2i(6, 4), "stone", 2)
		if station.size != Vector2i.ZERO:
			nm.landmark("Station", nm.nearest_open(station.get_center()))
			break
	var houses := nm.village(heart, nm.width * 0.45, int(22 * scale), [Vector2i(4, 3), Vector2i(5, 4), Vector2i(4, 4), Vector2i(6, 3)], "stone", 0.25, "stone")
	# The shelling: houses in ruins, rubble and craters in the streets, barricades and wrecks.
	for rect in houses:
		if nm.rng.randf() < 0.35:
			nm.ruin(rect, nm.rng.randf_range(0.25, 0.6))
	nm.patches(int(8 * scale), TacticalMap.Terrain.RUBBLE)
	nm.patches(int(8 * scale), TacticalMap.Terrain.CRATER)
	var street := func(p: Vector2i) -> bool: return nm.roads.has(p)
	for i in int(5 * scale):
		var p := Vector2i(nm.rng.randi_range(NaturalMap.STRIP + 2, nm.width - NaturalMap.STRIP - 3), nm.rng.randi_range(2, nm.height - 3))
		if street.call(p) and nm.map.is_passable(p) and Vector2(p).distance_to(Vector2(heart)) > 3.0:
			nm.map.set_object(p, Cover.FULL if nm.rng.randf() < 0.4 else Cover.HALF, "wreck" if nm.rng.randf() < 0.4 else "sandbags")
	# Gardens and allotments behind the houses, walled or fenced.
	var gardens := nm.patchwork(6.0, func(tiles: Array) -> Dictionary:
		if nm.rng.randf() < 0.3:
			nm.orchard(tiles)
		elif nm.rng.randf() < 0.3:
			nm.plant(tiles, TacticalMap.Terrain.ROUGH)
		var roll := nm.rng.randf()
		return {"edge": "stone" if roll < 0.5 else ("fence" if roll < 0.75 else "hedge"),
				"cover": Cover.FULL if roll >= 0.75 else Cover.HALF, "gaps": 1})
	_field_landmarks(nm, gardens, "Gardens")
	_clutter(nm, scale * 0.6)


static func _forest(nm: NaturalMap) -> void:
	var scale := _scale(nm)
	_east_west(nm, 1, 3)
	_north_south(nm, 1, 2)
	# Clearings in the wood: the sawmill, the lodge, a charcoal burners' clearing.
	for clearing_name: String in ["Sawmill", "Lodge", "Clearing"]:
		for attempt in 30:
			var at := Vector2i(nm.rng.randi_range(int(nm.width * 0.3), int(nm.width * 0.7)), nm.rng.randi_range(3, nm.height - 9))
			var rect := Rect2i(at, Vector2i(nm.rng.randi_range(6, 8), nm.rng.randi_range(5, 7)))
			if not nm.fits(rect) or nm.landmarks.any(func(m: Dictionary) -> bool: return Vector2(m["tile"]).distance_to(Vector2(at)) < 10.0):
				continue
			nm.reserve(rect.grow(1))
			match clearing_name:
				"Sawmill":
					nm.house(Rect2i(rect.position + Vector2i(1, 1), Vector2i(5, 3)), NaturalMap.S, "stone")
					for x in range(rect.position.x, rect.end.x, 2):
						nm.map.set_object(Vector2i(x, rect.end.y - 1), Cover.HALF, "crate")
				"Lodge":
					nm.house(Rect2i(rect.position + Vector2i(1, 1), Vector2i(4, 3)), NaturalMap.S, "stone")
					nm.map.set_object(rect.position + Vector2i(rect.size.x - 1, rect.size.y - 1), Cover.HALF, "fuel")
				_:
					nm.map.set_object(rect.get_center() + Vector2i(1, 0), Cover.HALF, "crate")
					nm.map.set_object(rect.get_center() + Vector2i(-2, 1), Cover.FULL, "rock")
			nm.landmark(clearing_name, nm.nearest_open(rect.get_center() + Vector2i(0, rect.size.y / 2)))
			break
	if not nm.junctions.is_empty():
		nm.landmark("Crossroads", nm.junctions[0])
	nm.woods(0.45, TacticalMap.Terrain.ROUGH, ["tree", "tree", "tree", "rock"], 0.6)
	var fields := nm.patchwork(9.0, func(tiles: Array) -> Dictionary:
		if nm.rng.randf() < 0.5:
			nm.plant(tiles, TacticalMap.Terrain.WHEAT)
		else:
			nm.dot(tiles, nm.rng.randi_range(0, 2), Cover.HALF, "hay")
		return {"edge": "hedge" if nm.rng.randf() < 0.6 else "fence", "cover": Cover.FULL, "gaps": 0})
	_field_landmarks(nm, fields)
	_clutter(nm, scale * 0.7)


## Shell craters, rocks and lone trees, sandbags and crates.
static func _clutter(nm: NaturalMap, scale: float) -> void:
	nm.patches(int(nm.rng.randi_range(4, 7) * scale), TacticalMap.Terrain.CRATER)
	nm.scatter(int(nm.rng.randi_range(2, 4) * scale), Cover.FULL, ["rock", "tree"])
	nm.scatter(int(nm.rng.randi_range(2, 4) * scale), Cover.HALF, ["sandbags", "crate"])


## Fuel drums and (on bigger maps) an oil tank that explode, a hidden minefield or two, barbed wire across the
## open ground. Anywhere: nothing is copied from one side to the other.
static func _hazards(nm: NaturalMap) -> void:
	var scale := _scale(nm)
	var big := int(nm.width >= 56)
	nm.scatter(maxi(2, int(nm.rng.randi_range(2, 4) * scale)), Cover.HALF, ["fuel"])
	if big:
		nm.scatter(1, Cover.FULL, ["oil_tank"])
	for i in 2 + big:
		var at := nm.open_tile()
		if at.x < 0:
			continue
		for j in nm.rng.randi_range(3, 5):
			var p := at + Vector2i(nm.rng.randi_range(-1, 1), nm.rng.randi_range(-1, 1))
			if nm.in_play(p) and nm.map.is_passable(p) and not nm.roads.has(p) and nm.map.get_terrain(p) != TacticalMap.Terrain.INDOOR:
				nm.build.mine(p)
	for i in 2 + big:
		var at := nm.open_tile()
		if at.x < 0:
			continue
		var along := Vector2i(0, 1) if nm.rng.randf() < 0.5 else Vector2i(1, 0)
		for j in nm.rng.randi_range(3, 5):
			var p := at + along * j
			if nm.is_free(p) or p == at:
				nm.map.set_terrain(p, TacticalMap.Terrain.WIRE)
				nm.reserved[p] = true
