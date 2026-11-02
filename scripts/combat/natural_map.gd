class_name NaturalMap
extends RefCounted
## Toolkit for natural-looking battlefields that are fair without being symmetrical. The same seed always gives
## the same map.
##
## The ground comes from smooth noise (FastNoiseLite, domain-warped so the shapes curl and branch): a "wild"
## field for how rough and overgrown the land is (woods, jungle, scrub, hills a road would rather go round) and
## a "wet" field for how low and damp it is (crops, paddies, ditches). Roads are routed with A* across the wild
## field, so they bend round rough ground and join roads already built where they meet. Villages grow along the
## roads, every house facing the street. Farmland is a Voronoi patchwork of irregular fields with a hedge,
## wall or dyke where two fields meet. Nothing is mirrored: what keeps a map fair is distance. Generators
## register landmarks as they build, and fair_objectives() picks the ones each side walks about as far to.
##
## Generators build in this order: roads, then settlements and landmarks along them, then woods, then the
## field patchwork in the ground that is left, then clutter; then finish() raises hills (see `hills`) and picks
## spawns and objectives. Houses may get upper floors and a flat roof (see `tall_chance`, tall()).

## Columns kept free of structures along each side's edge, so both sides have room to deploy.
const STRIP := 4
const N := Vector2i(0, -1)
const E := Vector2i(1, 0)
const S := Vector2i(0, 1)
const W := Vector2i(-1, 0)
const DIRS := [N, E, S, W]
## Boundary kinds by strength: where two fields want different boundaries, the stronger one is built.
const EDGE_RANK := {"": 0, "fence": 1, "dyke": 2, "stone": 2, "hedge": 3, "mud_wall": 3}

var map: TacticalMap
var build: MapBuilder
var rng := RandomNumberGenerator.new()
var width: int
var height: int
## Tiles taken by roads, buildings and their surrounds, woods and clutter; later features stay off them.
var reserved := {}
## Tiles a road may not be routed through (buildings, walled yards).
var solid := {}
## Road tile -> the index of the road that laid it.
var roads := {}
## Tiles covered by woods() (fields don't hedge themselves off from a wood).
var wooded := {}
## Where roads met: tiles laid by one road that a later road joined.
var junctions: Array[Vector2i] = []
## Candidate objectives: {"name": String, "tile": Vector2i}.
var landmarks: Array[Dictionary] = []
## How uneven a walk to an objective may be (see fair_objectives). Generators ease it on later attempts.
var tolerance := 0.15
## Hills per 1600 tiles (44x44 is about 1900) and how many levels they rise, raised by finish() on the rough
## ground off roads, buildings and the deployment strips (see HeightGenerator). 0 hills keeps the map flat.
var hills := 0.0
var hill_height := 2
## Chance a hill two levels high or more is an escarpment, with one side a cliff nobody climbs.
var scarp_chance := 0.35
## Chance a house gets upper floors, and the most storeys it may have (2 or 3). Bamboo huts stay low.
var tall_chance := 0.0
var tall_max := 2
var _road_count := 0
var _wild := FastNoiseLite.new()
var _wet := FastNoiseLite.new()
var _grain := FastNoiseLite.new()


func _init(seed: int, size: Vector2i) -> void:
	width = size.x
	height = size.y
	build = MapBuilder.new(width, height)
	map = build.map
	rng.seed = seed
	_setup_noise(_wild, seed, 1.0 / 18.0, 3)
	_setup_noise(_wet, seed + 7717, 1.0 / 24.0, 2)
	_setup_noise(_grain, seed + 3391, 1.0 / 5.0, 1)


static func _setup_noise(noise: FastNoiseLite, seed: int, frequency: float, octaves: int) -> void:
	noise.seed = seed & 0x7fffffff
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.domain_warp_enabled = true
	noise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	noise.domain_warp_amplitude = 9.0
	noise.domain_warp_frequency = frequency * 0.8


# --- Noise ---

## How wild the ground is at p, about 0 (tame) to 1 (wild).
func wild(p: Vector2i) -> float:
	return clampf(_wild.get_noise_2d(p.x, p.y) * 0.9 + 0.5, 0.0, 1.0)


## How wet the ground is at p, about 0 to 1.
func wet(p: Vector2i) -> float:
	return clampf(_wet.get_noise_2d(p.x, p.y) * 0.9 + 0.5, 0.0, 1.0)


## Fine-grained variation at p, about 0 to 1, for ragged edges and uneven planting.
func grain(p: Vector2i) -> float:
	return clampf(_grain.get_noise_2d(p.x, p.y) * 0.8 + 0.5, 0.0, 1.0)


# --- Tiles ---

## Whether p lies between the two deployment strips.
func in_play(p: Vector2i) -> bool:
	return p.x >= STRIP and p.x < width - STRIP and p.y >= 0 and p.y < height


## A tile still free for a new feature: in play, not reserved, open and not a road.
func is_free(p: Vector2i) -> bool:
	return in_play(p) and not reserved.has(p) and map.is_passable(p) and not roads.has(p)


func reserve(rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			reserved[Vector2i(x, y)] = true


func overlaps(rect: Rect2i) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y)
			if reserved.has(p) or roads.has(p):
				return true
	return false


## Whether a plot (with its one-tile surround) fits: inside the play area and on unclaimed ground.
func fits(rect: Rect2i) -> bool:
	var around := rect.grow(1)
	return around.position.x >= STRIP and around.end.x <= width - STRIP and around.position.y >= 0 and around.end.y <= height \
			and not overlaps(around)


func set_terrain(p: Vector2i, kind: int) -> void:
	if map.in_bounds(p):
		map.set_terrain(p, kind)


## A random free tile (see is_free) that `accept` (if given) agrees to, reserved for the caller; (-1, -1) if
## none turned up.
func open_tile(accept := Callable()) -> Vector2i:
	for i in 80:
		var p := Vector2i(rng.randi_range(STRIP + 1, width - STRIP - 2), rng.randi_range(1, height - 2))
		if is_free(p) and (not accept.is_valid() or accept.call(p)):
			reserved[p] = true
			return p
	return Vector2i(-1, -1)


## `count` objects of the given kinds on free tiles.
func scatter(count: int, cover: int, kinds: Array, accept := Callable()) -> void:
	for i in count:
		var p := open_tile(accept)
		if p.x >= 0:
			map.set_object(p, cover, kinds[rng.randi_range(0, kinds.size() - 1)])


## `count` patches of terrain (craters, rubble...) on free tiles.
func patches(count: int, kind: int, accept := Callable()) -> void:
	for i in count:
		var p := open_tile(accept)
		if p.x >= 0:
			map.set_terrain(p, kind)


# --- Roads ---

## A wandering line from a to b through `bends` points pushed off the straight line, for road() to follow.
func meander(a: Vector2i, b: Vector2i, bends: int, sway: float) -> Array[Vector2i]:
	var points: Array[Vector2i] = [a]
	var along := Vector2(b - a)
	var across := along.orthogonal().normalized()
	for i in bends:
		var t := (i + 1.0) / (bends + 1.0) + rng.randf_range(-0.08, 0.08)
		var p := Vector2(a) + along * t + across * rng.randf_range(-sway, sway)
		points.append(Vector2i(clampi(roundi(p.x), 1, width - 2), clampi(roundi(p.y), 1, height - 2)))
	points.append(b)
	return points


## Lays a road through the waypoints, routed with A* so it bends round wild ground (`avoid` sets how hard it
## tries) and runs along roads already built where they lead its way. Returns its tiles in order. With
## `register` false the line is laid as ground only (a dry riverbed, say): it is not a road for houses to face,
## and it ignores the roads.
func road(waypoints: Array[Vector2i], road_width := 1, kind := TacticalMap.Terrain.ROAD, avoid := 6.0, register := true) -> Array[Vector2i]:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, width, height)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()
	for y in height:
		for x in width:
			var p := Vector2i(x, y)
			if solid.has(p):
				grid.set_point_solid(p)
			elif roads.has(p) and register:
				grid.set_point_weight_scale(p, 0.4)
			else:
				var w := wild(p)
				grid.set_point_weight_scale(p, 1.0 + avoid * w * w + (2.0 if reserved.has(p) else 0.0))
	var index := _road_count
	_road_count += 1
	var path: Array[Vector2i] = []
	for i in waypoints.size() - 1:
		var leg := grid.get_id_path(waypoints[i], waypoints[i + 1])
		for j in leg.size():
			if j == 0 and not path.is_empty():
				continue
			path.append(leg[j])
	for i in path.size():
		var p := path[i]
		var step := path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]
		var tiles: Array[Vector2i] = [p]
		if road_width >= 2:
			tiles.append(p + (Vector2i(0, 1) if absi(step.x) >= absi(step.y) else Vector2i(1, 0)))
		for t in tiles:
			if not map.in_bounds(t) or solid.has(t):
				continue
			if register:
				if roads.has(t) and roads[t] != index and (junctions.is_empty() or Vector2(junctions.back()).distance_to(Vector2(t)) > 4.0):
					junctions.append(t)
				if not roads.has(t):
					roads[t] = index
			map.set_terrain(t, kind)
			map.set_object(t, Cover.NONE)
			reserved[t] = true
	return path


## The row where a road reaches a side's edge (team 0 west, 1 east), nearest the middle; -1 if none does.
func road_entry(team: int) -> int:
	var x := 0 if team == 0 else width - 1
	var best := -1
	for y in height:
		if roads.has(Vector2i(x, y)) and (best == -1 or absi(y - height / 2) < absi(best - height / 2)):
			best = y
	return best


## Which way the road runs at a road tile: E for east-west, S for north-south.
func road_heading(at: Vector2i) -> Vector2i:
	var across := int(roads.has(at + E)) + int(roads.has(at + W))
	var down := int(roads.has(at + N)) + int(roads.has(at + S))
	return E if across >= down else S


# --- Buildings ---

## A house with a door on the `door_side` wall and a window in each other wall (two in long ones).
## `style` as in MapBuilder.building. Reserves the plot.
func house(rect: Rect2i, door_side: Vector2i, style := "stone") -> void:
	var doors := [[_wall_tile(rect, door_side), door_side]]
	var windows := []
	for side: Vector2i in DIRS:
		if side == door_side:
			continue
		var length := rect.size.x if side.y != 0 else rect.size.y
		for i in (2 if length >= 5 else 1):
			windows.append([_wall_tile(rect, side), side])
	build.building(rect, doors, windows, [], style)
	if style != "bamboo" and tall_chance > 0.0 and rng.randf() < tall_chance:
		tall(rect, 3 if tall_max >= 3 and rng.randf() < 0.3 else 2, doors[0][0])
	reserve(rect.grow(1))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			solid[Vector2i(x, y)] = true


## Gives a building (or a corner of one: a tower) `count` storeys, with the stairs in the corner furthest from
## `door` (the rect's first corner if no door is given).
func tall(rect: Rect2i, count: int, door := Vector2i(-1, -1)) -> void:
	var corners := [rect.position, Vector2i(rect.end.x - 1, rect.position.y), Vector2i(rect.position.x, rect.end.y - 1), rect.end - Vector2i.ONE]
	var stairs: Vector2i = corners[0]
	if door.x >= 0:
		for c: Vector2i in corners:
			if Vector2(c).distance_to(Vector2(door)) > Vector2(stairs).distance_to(Vector2(door)):
				stairs = c
	build.tall_building(rect, count, stairs)


## A random tile along the `side` wall of a rect, off the corners where the wall is long enough.
func _wall_tile(rect: Rect2i, side: Vector2i) -> Vector2i:
	if side.y != 0:
		var x := rect.position.x + (rng.randi_range(1, rect.size.x - 2) if rect.size.x > 2 else 0)
		return Vector2i(x, rect.position.y if side == N else rect.end.y - 1)
	var y := rect.position.y + (rng.randi_range(1, rect.size.y - 2) if rect.size.y > 2 else 0)
	return Vector2i(rect.position.x if side == W else rect.end.x - 1, y)


## A house beside the road at `at`, `setback` tiles back from it, its door onto the road. Its long side runs
## along the road. With `yard` (an edge kind) a walled yard is added behind it. Returns the house, or an
## empty Rect2i if there was no room on either side of the road.
func roadside_house(at: Vector2i, size: Vector2i, style := "stone", setback := 1, yard := "") -> Rect2i:
	var heading := road_heading(at)
	var sides := [N, S] if heading == E else [W, E]
	if rng.randf() < 0.5:
		sides.reverse()
	var long := maxi(size.x, size.y)
	var short := mini(size.x, size.y)
	var dims := Vector2i(long, short) if heading == E else Vector2i(short, long)
	for side: Vector2i in sides:
		# Step across the road to its far edge on this side.
		var edge := at
		while roads.has(edge + side):
			edge += side
		var shift := rng.randi_range(-(long - 1), 0)
		var near := edge + side * (setback + 1)
		var rect: Rect2i
		match side:
			N: rect = Rect2i(at.x + shift, near.y - dims.y + 1, dims.x, dims.y)
			S: rect = Rect2i(at.x + shift, near.y, dims.x, dims.y)
			W: rect = Rect2i(near.x - dims.x + 1, at.y + shift, dims.x, dims.y)
			_: rect = Rect2i(near.x, at.y + shift, dims.x, dims.y)
		if not fits(rect):
			continue
		var plot := rect
		var back := Rect2i()
		if yard != "":
			back = _behind(rect, side, 3)
			if fits(back):
				plot = rect.merge(back)
			else:
				back = Rect2i()
		house(rect, -side, style)
		if back.size != Vector2i.ZERO:
			build.enclose(back, Cover.HALF if yard != "mud_wall" else Cover.FULL, yard, [[_wall_tile(back, side), side, Cover.NONE, ""]], [-side])
			for y in range(back.position.y, back.end.y):
				for x in range(back.position.x, back.end.x):
					solid[Vector2i(x, y)] = true
			reserve(plot.grow(1))
		return rect
	return Rect2i()


## The strip `depth` deep behind a rect on its `side`.
static func _behind(rect: Rect2i, side: Vector2i, depth: int) -> Rect2i:
	match side:
		N: return Rect2i(rect.position.x, rect.position.y - depth, rect.size.x, depth)
		S: return Rect2i(rect.position.x, rect.end.y, rect.size.x, depth)
		W: return Rect2i(rect.position.x - depth, rect.position.y, depth, rect.size.y)
		_: return Rect2i(rect.end.x, rect.position.y, depth, rect.size.y)


## Houses along the roads within `radius` of `center`, nearest first, up to `count`. Sizes are picked from
## `sizes` (Vector2i, long side first). Returns the houses built.
func village(center: Vector2i, radius: float, count: int, sizes: Array, style := "stone", yard_chance := 0.0, yard := "") -> Array[Rect2i]:
	var spots: Array = []
	for p: Vector2i in roads:
		var d := Vector2(p).distance_to(Vector2(center))
		if d <= radius:
			spots.append([d + rng.randf() * 3.0, p])
	spots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var built: Array[Rect2i] = []
	for spot: Array in spots:
		if built.size() >= count:
			break
		var size: Vector2i = sizes[rng.randi_range(0, sizes.size() - 1)]
		var rect := roadside_house(spot[1], size, style, rng.randi_range(1, 2), yard if rng.randf() < yard_chance else "")
		if rect.size != Vector2i.ZERO:
			built.append(rect)
	return built


## Knocks a house about: about `amount` of its walls come down and its floor turns to rubble in places. Its
## upper floors (if any) are gone.
func ruin(rect: Rect2i, amount: float) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y)
			map.set_storeys(p, 1)
			map.set_stairs(p, false)
			if rng.randf() < amount:
				map.set_terrain(p, TacticalMap.Terrain.RUBBLE)
			for d: Vector2i in DIRS:
				if not rect.has_point(p + d) and map.get_edge(p, p + d) != Cover.NONE and rng.randf() < amount:
					map.set_edge(p, p + d, Cover.NONE)


## A walled enclosure with gates, its walls of `kind`, and (optionally) a house against its north wall.
func compound(rect: Rect2i, kind: String, cover: int, gates: int, house_style := "") -> void:
	var gaps := []
	var sides := DIRS.duplicate()
	for i in gates:
		var side: Vector2i = sides.pop_at(rng.randi_range(0, sides.size() - 1))
		gaps.append([_wall_tile(rect, side), side, Cover.NONE, ""])
	build.enclose(rect, cover, kind, gaps)
	if house_style != "" and rect.size.x >= 5 and rect.size.y >= 6:
		var home := Rect2i(rect.position + Vector2i(1, 1), Vector2i(rect.size.x - 2, 3))
		house(home, S, house_style)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			solid[Vector2i(x, y)] = true
	reserve(rect.grow(1))


## An object on the open tile nearest p (not indoors, not inside a walled plot), if there is one close by.
func object_near(p: Vector2i, cover: int, kind: String) -> void:
	for radius in range(0, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var t := p + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) == radius and in_play(t) and map.is_passable(t) and not solid.has(t) \
						and map.get_terrain(t) != TacticalMap.Terrain.INDOOR:
					map.set_object(t, cover, kind)
					reserved[t] = true
					return


## Registers a candidate objective. Landmarks with a higher `priority` are picked first when the walks are
## about as fair; plain fields and woods have a low one.
func landmark(landmark_name: String, tile: Vector2i, priority := 1.0) -> void:
	landmarks.append({"name": landmark_name, "tile": tile, "priority": priority})


## A landmark at the middle of a building or plot, or the nearest open tile to it.
func landmark_at(landmark_name: String, rect: Rect2i) -> void:
	landmark(landmark_name, nearest_open(rect.get_center()))


## The open tile nearest p (p itself if open).
func nearest_open(p: Vector2i) -> Vector2i:
	for radius in range(0, 8):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var t := p + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) == radius and map.in_bounds(t) and map.is_passable(t):
					return t
	return p


# --- Ground cover ---

## Covers the wildest `share` of the free ground (where `accept`, if given, agrees) with clumps of woodland:
## `terrain` laid under it (-1 keeps the ground) and objects of the `trees` kinds planted at about `density`,
## thinning out at the edges. Returns the tiles covered.
func woods(share: float, terrain: int, trees: Array, density: float, accept := Callable()) -> Array[Vector2i]:
	var candidates: Array = []
	for y in height:
		for x in range(STRIP, width - STRIP):
			var p := Vector2i(x, y)
			if is_free(p) and (not accept.is_valid() or accept.call(p)):
				candidates.append([wild(p) + grain(p) * 0.12, p])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var take := int(candidates.size() * share)
	var covered: Array[Vector2i] = []
	for i in take:
		var p: Vector2i = candidates[i][1]
		if terrain >= 0:
			map.set_terrain(p, terrain)
		# Thick in the heart of the wood, sparse at its edge.
		var depth := 1.0 - float(i) / take
		if not trees.is_empty() and rng.randf() < density * (0.35 + 0.65 * depth):
			map.set_object(p, Cover.FULL, trees[rng.randi_range(0, trees.size() - 1)])
		reserved[p] = true
		wooded[p] = true
		covered.append(p)
	return covered


## Splits the free ground (where `accept`, if given, agrees) into irregular fields about `spacing` tiles
## across, a Voronoi patchwork with wobbly borders, and hands each to `dress`:
## dress.call(tiles: Array[Vector2i]) -> {"edge": kind ("" for none), "cover": Cover level, "gaps": extra gaps}.
## Where two fields meet the stronger boundary of the two is built along the border, with a gap or more to
## walk through; a field also puts its boundary along any road or building it meets. Fields too small to
## bother with are dressed but left unfenced. Returns the fields' tile lists.
func patchwork(spacing: float, dress: Callable, accept := Callable()) -> Array:
	# Sites on a jittered grid, so fields come out about the same size but no two alike.
	var cols := ceili(width / spacing) + 1
	var rows := ceili(height / spacing) + 1
	var sites: Array[Vector2] = []
	for gy in rows:
		for gx in cols:
			sites.append(Vector2((gx + rng.randf_range(0.15, 0.85)) * spacing, (gy + rng.randf_range(0.15, 0.85)) * spacing))
	var cell_of := {}
	var cells: Array = []
	for i in sites.size():
		cells.append([])
	for y in height:
		for x in range(STRIP, width - STRIP):
			var p := Vector2i(x, y)
			if not is_free(p) or (accept.is_valid() and not accept.call(p)):
				continue
			var gx := int(x / spacing)
			var gy := int(y / spacing)
			var best := -1
			var best_d := INF
			for oy in range(maxi(0, gy - 2), mini(rows, gy + 3)):
				for ox in range(maxi(0, gx - 2), mini(cols, gx + 3)):
					var i := oy * cols + ox
					var d := Vector2(p) + Vector2(0.5, 0.5) - sites[i]
					# Nearly square distance: borders run mostly straight along the grid with the odd slant,
					# as hedgerows do. Smooth noise bends them gently, a different way for each site.
					var dist := maxf(absf(d.x), absf(d.y)) + 0.2 * minf(absf(d.x), absf(d.y)) \
							+ _wet.get_noise_2d(p.x + i * 37.0, p.y - i * 53.0) * spacing * 0.18
					if dist < best_d:
						best_d = dist
						best = i
			cell_of[p] = best
			cells[best].append(p)
	var fields: Array = []
	var decisions := {}
	for i in cells.size():
		if cells[i].is_empty():
			continue
		var decision: Dictionary = dress.call(cells[i])
		if cells[i].size() < 6:
			decision = {"edge": "", "cover": Cover.NONE, "gaps": 0}
		decisions[i] = decision
		fields.append(cells[i])
	# Borders, grouped by the pair of fields (or field and outside, -1) they divide.
	var borders := {}
	for i: int in decisions:
		for p: Vector2i in cells[i]:
			for d: Vector2i in DIRS:
				var q := p + d
				if not map.in_bounds(q) or not in_play(q):
					continue
				var other: int = cell_of.get(q, -1)
				if other == i or (other != -1 and other < i):
					continue
				if other == -1 and (not reserved.has(q) or wooded.has(q)):
					continue
				var key := Vector2i(i, other)
				if not borders.has(key):
					borders[key] = []
				borders[key].append([p, q])
	for key: Vector2i in borders:
		var mine: Dictionary = decisions[key.x]
		var chosen := mine
		if key.y != -1:
			var theirs: Dictionary = decisions.get(key.y, mine)
			if EDGE_RANK.get(theirs["edge"], 0) > EDGE_RANK.get(mine["edge"], 0):
				chosen = theirs
		if chosen["edge"] == "":
			continue
		var line: Array = borders[key]
		var gaps := {}
		var openings := maxi(1, line.size() / (5 if key.y == -1 else 7)) + int(chosen.get("gaps", 0))
		for g in openings:
			gaps[rng.randi_range(0, line.size() - 1)] = true
		for j in line.size():
			var pair: Array = line[j]
			if gaps.has(j) or map.get_edge(pair[0], pair[1]) != Cover.NONE:
				continue
			map.set_edge(pair[0], pair[1], chosen["cover"], chosen["edge"])
	return fields


## Fills a field with a crop: `kind` terrain over all its tiles.
func plant(tiles: Array, kind: int) -> void:
	for p: Vector2i in tiles:
		map.set_terrain(p, kind)


## Trees in rows across a field, an orchard, keeping off its border so the hedge gaps stay open.
func orchard(tiles: Array, kind := "tree", step := 3) -> void:
	var inside := {}
	for p: Vector2i in tiles:
		inside[p] = true
	for p: Vector2i in tiles:
		if posmod(p.x, step) == 1 and posmod(p.y, step) == 1 and DIRS.all(func(d: Vector2i) -> bool: return inside.has(p + d)):
			map.set_object(p, Cover.FULL, kind)


## A few objects dropped in a field.
func dot(tiles: Array, count: int, cover: int, kind: String) -> void:
	for i in count:
		var p: Vector2i = tiles[rng.randi_range(0, tiles.size() - 1)]
		if map.is_passable(p) and not roads.has(p):
			map.set_object(p, cover, kind)


# --- Sides and objectives ---

## Start tiles for a side along its own edge (team 0 west, 1 east), around row `center`.
func spawn_tiles(team: int, center: int, count := 16) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var taken := {}
	for i in count:
		var offset := (i + 1) / 2 * (1 if i % 2 == 0 else -1)
		var col := 1 + absi(offset) % 3
		var want := Vector2i(col if team == 0 else width - 1 - col, clampi(center + offset, 1, height - 2))
		var tile := _open_near(want, team, taken)
		taken[tile] = true
		result.append(tile)
	return result


## Where a side's reinforcements walk on: its edge at the road (or the middle), and near each corner.
func reinforcement_tiles(team: int, center: int) -> Array[Vector2i]:
	var x := 0 if team == 0 else width - 1
	var result: Array[Vector2i] = []
	for y in [center, 2, height - 3]:
		result.append(_open_near(Vector2i(x, y), team, {}))
	return result


func _open_near(want: Vector2i, team: int, taken: Dictionary) -> Vector2i:
	for radius in range(0, 10):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var p := want + Vector2i(dx, dy)
				var strip := p.x < STRIP if team == 0 else p.x >= width - STRIP
				if strip and map.in_bounds(p) and map.is_passable(p) and not taken.has(p):
					return p
	return want


## A clear tile for helicopters in a side's third of the map: the free tile there with the most open ground
## around it.
func landing_zone(team: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := -1.0
	var x0 := STRIP + 2 if team == 0 else int(width * 0.68)
	var x1 := int(width * 0.32) if team == 0 else width - STRIP - 2
	for i in 60:
		var p := Vector2i(rng.randi_range(x0, x1), rng.randi_range(3, height - 4))
		if not map.is_passable(p) or map.get_terrain(p) == TacticalMap.Terrain.INDOOR:
			continue
		var open := 0
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var q := p + Vector2i(dx, dy)
				if map.in_bounds(q) and map.is_passable(q) and map.get_terrain(q) != TacticalMap.Terrain.JUNGLE:
					open += 1
		var score := open + rng.randf()
		if score > best_score:
			best_score = score
			best = p
	return best if best.x >= 0 else nearest_open(Vector2i(x0, height / 2))


## Picks `count` objectives from the landmarks so neither side has much the shorter walk to them. Each must be
## within `tolerance` of an even split of the two sides' walking distances (0.15: one side walks at most about
## 35% further), the set as a whole as even as can be, and the objectives spread out. `starts` holds a tile
## from each side. Returns them north to south as Battle objectives, or [] if no fair set exists.
func fair_objectives(starts: Array, count := 3, tolerance := 0.15) -> Array:
	var reach := [Pathfinder.search(map, starts[0], 100000.0), Pathfinder.search(map, starts[1], 100000.0)]
	var fair: Array = []
	for mark: Dictionary in landmarks:
		var tile: Vector2i = mark["tile"]
		if not reach[0].has(tile) or not reach[1].has(tile):
			continue
		var a: float = reach[0][tile]["cost"]
		var b: float = reach[1][tile]["cost"]
		var bias := (a - b) / maxf(1.0, a + b)
		if absf(bias) <= tolerance and not fair.any(func(f: Dictionary) -> bool: return f["name"] == mark["name"]):
			fair.append({"name": mark["name"], "tile": tile, "bias": bias, "priority": mark["priority"]})
	if fair.size() < count:
		return []
	var spread := maxf(6.0, height / 6.0)
	var best: Array = []
	var best_score := -INF
	for combo in _combinations(fair.size(), count):
		var total := 0.0
		var worst := 0.0
		var worth := 0.0
		var closest := INF
		for i: int in combo:
			total += fair[i]["bias"]
			worth += fair[i]["priority"]
			worst = maxf(worst, absf(fair[i]["bias"]))
			for j: int in combo:
				if j > i:
					closest = minf(closest, Vector2(fair[i]["tile"]).distance_to(Vector2(fair[j]["tile"])))
		if closest < spread:
			continue
		var score := -absf(total) * 3.0 - worst + 0.6 * minf(closest, height * 0.5) / height + 0.3 * worth
		if score > best_score:
			best_score = score
			best = combo
	if best.is_empty():
		return []
	var picked: Array = best.map(func(i: int) -> Dictionary: return fair[i])
	picked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tile"].y < b["tile"].y)
	return picked.map(func(f: Dictionary) -> Dictionary:
		return {"name": f["name"], "center": Vector2(f["tile"]) + Vector2(0.5, 0.5), "radius": 2.5})


static func _combinations(n: int, k: int) -> Array:
	var result: Array = []
	var combo: Array = []
	_combine(0, n, k, combo, result)
	return result


static func _combine(start: int, n: int, k: int, combo: Array, result: Array) -> void:
	if combo.size() == k:
		result.append(combo.duplicate())
		return
	for i in range(start, n):
		combo.append(i)
		_combine(i + 1, n, k, combo, result)
		combo.pop_back()


## Builds a map with `recipe` (recipe.call(nm: NaturalMap) -> layout, {} on failure) until one comes out
## playable, easing the fairness tolerance a little each time. Tries ATTEMPTS seeds derived from `seed`.
static func generate(seed: int, size: Vector2i, recipe: Callable, attempts := 16) -> Dictionary:
	var fallback := {}
	for attempt in attempts:
		var nm := NaturalMap.new(seed + attempt * 7919, size)
		# The last try takes the most even objectives it can find, however uneven.
		nm.tolerance = 1.0 if attempt == attempts - 1 else 0.15 + 0.01 * attempt
		var layout: Dictionary = recipe.call(nm)
		if layout.is_empty():
			continue
		if is_playable(layout):
			return layout
		fallback = layout
	return fallback


## Whether every spawn can walk to every other spawn (its own side's and the enemy's) and to every objective.
static func is_playable(layout: Dictionary) -> bool:
	var map: TacticalMap = layout["map"]
	var tiles: Array = []
	for team in 2:
		tiles.append_array(layout["spawns"][team])
		tiles.append_array(layout["reinforcement_spawns"][team])
	for p: Vector2i in tiles:
		if not map.is_passable(p):
			return false
	var reach := Pathfinder.search(map, tiles[0], 100000.0)
	for p: Vector2i in tiles:
		if not reach.has(p):
			return false
	for objective: Dictionary in layout["objectives"]:
		if not reach.has(Vector2i(objective["center"])):
			return false
	return true


## The finished layout for BattleFactory.create, with both sides' spawns round the rows given (a road's entry
## if there is one), and objectives fair to both; {} if no fair set of objectives could be found.
func finish(extra := {}) -> Dictionary:
	_raise_hills()
	var centers := []
	for team in 2:
		var entry := road_entry(team)
		centers.append(entry if entry >= 0 else rng.randi_range(int(height * 0.3), int(height * 0.7)))
	var spawns := [spawn_tiles(0, centers[0]), spawn_tiles(1, centers[1])]
	var objectives := fair_objectives([spawns[0][0], spawns[1][0]], 3, tolerance)
	if objectives.is_empty():
		return {}
	var layout := {
		"map": map,
		"objectives": objectives,
		"spawns": spawns,
		"reinforcement_spawns": [reinforcement_tiles(0, centers[0]), reinforcement_tiles(1, centers[1])],
	}
	layout.merge(extra)
	return layout


## Raises `hills` hills on the wilder ground, keeping roads, buildings and their surrounds, paddies and the
## deployment strips level. Each hilltop becomes a minor landmark ("Hill 104"), so there is high ground to
## fight over and fair_objectives has more to choose from.
func _raise_hills() -> void:
	var count := roundi(hills * width * height / 1600.0)
	if count <= 0:
		return
	var flat := {}
	for y in height:
		for x in width:
			var p := Vector2i(x, y)
			var terrain := map.get_terrain(p)
			if not in_play(p) or roads.has(p) or terrain == TacticalMap.Terrain.PADDY or terrain == TacticalMap.Terrain.INDOOR:
				flat[p] = true
	for p: Vector2i in solid:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				flat[p + Vector2i(dx, dy)] = true
	var tops := HeightGenerator.raise_hills(build, rng, flat, count, hill_height, wild, scarp_chance)
	for i in tops.size():
		var top := nearest_open(tops[i])
		landmark("Hill %d" % (80 + map.get_elevation(top) * 15 + i * 7 + rng.randi_range(0, 5)), top, 0.3)
