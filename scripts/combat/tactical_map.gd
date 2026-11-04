class_name TacticalMap
extends RefCounted
## Grid data for a battle: terrain, cover objects standing on tiles, walls on the edges between tiles,
## smoke, fires and buried mines. Objects and edges also carry a kind ("tree", "hedge", ...) that changes
## how they look, and for hedges, how they're crossed. Fuel drums and oil tanks are objects that explode.

## TRAMPLED is wheat (or tall grass) flattened by soldiers or tanks moving through it; WIRE is a barbed-wire
## entanglement. JUNGLE is dense undergrowth: slow, hides whoever is in it and blocks sight through it.
## PADDY is a flooded rice field: slow, open, and it bogs vehicles down. TALL_GRASS is elephant grass: it
## hides prone soldiers like wheat, a little closer in, and is trampled like it. TRENCH is dug below the ground:
## full cover against fire from outside it, none along it (fire down the trench line enfilades it), a little
## slow to walk and slower to climb in or out of. From in it you see along it and TRENCH_SIGHT tiles beyond its
## lip, and only from there (or from a level higher) can anyone see in.
enum Terrain { FLOOR, ROUGH, RUBBLE, INDOOR, ROAD, WHEAT, CRATER, TRAMPLED, WIRE, JUNGLE, PADDY, TALL_GRASS, TRENCH }

## North, east, south, west.
const DIRS4 := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIRS8 := [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const TERRAIN_NAMES := ["Grass", "Rough ground", "Rubble", "Indoor floor", "Road", "Wheat field", "Shell crater", "Trampled wheat", "Barbed wire",
		"Jungle", "Rice paddy", "Elephant grass", "Trench"]
const TERRAIN_COST := [1.0, 2.0, 2.0, 1.0, 0.75, 1.5, 1.5, 1.0, 4.0, 2.0, 2.0, 1.5, 1.5]
## Extra cost for climbing down into a trench or up out of it.
const TRENCH_CLIMB_COST := 1.0
## How many tiles past a trench's edge sight from inside it reaches (and from how far out anyone sees in).
const TRENCH_SIGHT := 3
## What a tank pays where it differs from TERRAIN_COST: it rolls over wire, ploughs through undergrowth and
## bogs down in flooded paddies.
const VEHICLE_TERRAIN_COST := {Terrain.WIRE: 1.0, Terrain.JUNGLE: 3.0, Terrain.PADDY: 3.0, Terrain.TALL_GRASS: 1.0, Terrain.TRENCH: 3.0}
## What a tank leaves behind it.
const VEHICLE_FLATTENS := {Terrain.WIRE: Terrain.FLOOR, Terrain.WHEAT: Terrain.TRAMPLED, Terrain.TALL_GRASS: Terrain.TRAMPLED, Terrain.JUNGLE: Terrain.ROUGH}
## Crops and grass a standing soldier tramples flat as he walks out of it.
const TRAMPLES := {Terrain.WHEAT: Terrain.TRAMPLED, Terrain.TALL_GRASS: Terrain.TRAMPLED}
## Terrain that hides those in it from anyone further than "range" tiles away, in the listed stances, unless
## they have fired; and makes them harder to hit beyond that range ("defense", shown as "label"). Stances are
## Unit.Stance values (0 standing, 2 prone).
const CONCEALMENT := {
	Terrain.WHEAT: {"range": 4.0, "stances": [2], "defense": 10, "label": "In the wheat"},
	Terrain.TALL_GRASS: {"range": 3.0, "stances": [2], "defense": 10, "label": "In the tall grass"},
	Terrain.JUNGLE: {"range": 3.0, "stances": [0, 2], "defense": 15, "label": "In the jungle"},
}
## Sight passes through at most this many jungle tiles (not counting the two ends).
const JUNGLE_SIGHT_TILES := 1
## Objects a tank can knock down and drive through (at TREE_COST).
const FELLABLE_KINDS := ["tree", "palm", "bamboo"]
## Objects that blow up when shot, caught in a blast or run over: fuel drums (half cover) and oil tanks (full).
const EXPLOSIVE_KINDS := ["fuel", "oil_tank", "car"]
const DIAGONAL_FACTOR := 1.5
## Extra cost for climbing over a half-height wall, and for pushing through a hedgerow.
const VAULT_COST := 1.0
const HEDGE_COST := 3.0
## Extra cost for a tank flattening a crate, sandbags, a fence or a low wall, and for knocking down a tree.
const CRUSH_COST := 1.0
const TREE_COST := 2.0
## What driving over fuel drums costs a tank on its path, so it only does it when there's no other way.
const FUEL_CRUSH_COST := 6.0
## Low obstacles and hedges a tank can drive through (and destroys on the way).
const CRUSHABLE_EDGES := ["fence", "stone", "hedge", "dyke", "bamboo_wall", "bamboo_window"]
## Edges that are full cover when whole. They take three stages to bring down: damaged (still full cover),
## breached (half cover, a gap to climb and shoot through), gone. Half-cover edges go in two.
const FULL_EDGE_KINDS := ["wall", "hedge", "bamboo_wall", "mud_wall"]
## Light edges a machine gun can shoot to pieces; it only chips stone, brick and mud walls.
## Ground that burns long and can catch even under a soldier (CombatRules.LONG_BURN_TURNS).
const LONG_BURNING := [Terrain.WHEAT, Terrain.TALL_GRASS, Terrain.TRAMPLED]
const FLIMSY_EDGES := ["fence", "hedge", "bamboo_wall", "bamboo_window", "window", "broken_window"]
## Hedges are only leaves and twigs: every hit on one knocks this many times the stages off (see damage_edge).
const HEDGE_DAMAGE_FACTOR := 2

# --- Height ---
## Heights are in levels: one level is a storey, about three metres. Ground rises in whole levels (hills,
## ridges, terraces), up to MAX_ELEVATION. A building has 1 to MAX_STOREYS storeys; one of two storeys or
## more has a flat roof soldiers can stand on, reached by its stairs. Single-storey buildings have pitched
## roofs nobody stands on. A soldier's level is the floor he stands on: 0 is the ground (or the ground floor),
## a building's storey count is its roof.
const MAX_ELEVATION := 3
const MAX_STOREYS := 3
## Eye height above the floor, in levels, for each stance (Unit.Stance: 0 standing, 2 prone). Vehicles count as standing.
const STANCE_EYE := {0: 0.55, 2: 0.12}
## How tall things are, in levels, for seeing over them from higher up. Other full-cover objects stand
## FULL_OBJECT_HEIGHT high, free-standing full walls WALL_HEIGHT; building walls reach the roof.
const OBJECT_HEIGHT := {"tree": 2.5, "palm": 2.5, "poplar": 3.0, "bamboo": 2.0, "oil_tank": 1.3}
const FULL_OBJECT_HEIGHT := 1.0
const WALL_HEIGHT := 1.0
## Shoulder high: a standing soldier (STANCE_EYE) sees and shoots over a hedge, one lying down doesn't.
const HEDGE_HEIGHT := 0.45
const SMOKE_HEIGHT := 2.0
## Jungle canopy: sight below it counts the jungle tiles it passes (JUNGLE_SIGHT_TILES); above it, not.
const CANOPY_HEIGHT := 2.0
## Extra path cost of climbing one level: up a slope, onto a roof from a hillside. Going down is free.
## Ground two or more levels apart is a cliff nobody climbs.
const CLIMB_COST := 1.0
## Going up or down one storey on a staircase.
const STAIRS_COST := 1.5
## Tanks labour up slopes.
const VEHICLE_CLIMB_COST := 2.0

var width: int
var height: int
## Bumped on every change, so caches (vision, drawing) know when to rebuild.
var revision := 0
## Bumped only when terrain, objects or walls change (not smoke).
var layout_revision := 0
## LineOfSight's peek positions per (x, y, level), valid while revision equals peek_cache_revision.
var peek_cache := {}
var peek_cache_revision := -1
var _terrain := PackedInt32Array()
var _objects := PackedInt32Array()
var _object_kinds := {}
## Edge key (see _edge_key) -> cover level, and -> kind.
var _edges := {}
var _edge_kinds := {}
## Damage to walls, hedges and fences, by edge key (see damage_edge): 1 damaged, 2 breached, 3 gone. Gone
## edges are kept here so a building still knows how many of its walls have fallen.
var _edge_damage := {}
## Tile -> battle turn index at which the smoke there clears.
var _smoke := {}
## Tiles with a tank on them: they give half cover to soldiers beside them.
var _vehicles := {}
## Tile -> battle turn index at which the fire there burns out. Nobody can enter a burning tile.
var _fires := {}
## Tiles with a mine buried in them: true for a mine, or the kind of trap ("punji"). Which side knows about
## which mine is kept by the Battle.
var _mines := {}
## Tunnel entrances: tile -> the team whose tunnels they are (Vietnam). The enemy has to find them.
var _tunnels := {}
## Ground height of each tile, in levels.
var _elevation := PackedInt32Array()
## Building tiles of more than one storey: tile -> storeys. Other indoor tiles have one.
var _storeys := {}
## Tiles with a staircase, which joins every floor of the building there, roof included.
var _stairs := {}
## Whether any ground is raised, any building is taller than one storey, or any stairs exist. Flat maps take
## the old, quicker paths for sight and movement.
var _tall := false
## Per tile, the height of the tallest thing there that can block sight (ground, object, smoke, roof), and
## the map revision it was worked out for (see tile_tops).
var _tops := PackedFloat32Array()
var _tops_revision := -1
var _trench_distance := PackedByteArray()
var _trench_revision := -1


func _init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	_terrain.resize(width * height)
	_terrain.fill(Terrain.FLOOR)
	_objects.resize(width * height)
	_objects.fill(Cover.NONE)
	_elevation.resize(width * height)
	_elevation.fill(0)


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func get_terrain(p: Vector2i) -> int:
	return _terrain[_index(p)] if in_bounds(p) else Terrain.FLOOR


func set_terrain(p: Vector2i, terrain: int) -> void:
	_terrain[_index(p)] = terrain
	revision += 1
	layout_revision += 1


## Cover level of the object standing on a tile. Any object blocks movement.
func get_object(p: Vector2i) -> int:
	return _objects[_index(p)] if in_bounds(p) else Cover.NONE


## Kinds: full cover "rock", "tree", "palm", "bamboo", "oil_tank", "car" (a wreck that burns when hit), "hesco";
## half cover "crate", "sandbags", "hay", "pew", "fuel", "rice_sacks", "jersey" (a concrete barrier),
## "howitzer" (a field gun behind its shield).
func get_object_kind(p: Vector2i) -> String:
	return _object_kinds.get(p, "rock" if get_object(p) == Cover.FULL else "crate")


func set_object(p: Vector2i, cover: int, kind := "") -> void:
	_objects[_index(p)] = cover
	if kind == "" or cover == Cover.NONE:
		_object_kinds.erase(p)
	else:
		_object_kinds[p] = kind
	revision += 1
	layout_revision += 1


# --- Height ---

func has_height() -> bool:
	return _tall


func get_elevation(p: Vector2i) -> int:
	return _elevation[_index(p)] if in_bounds(p) else 0


func set_elevation(p: Vector2i, level: int) -> void:
	level = clampi(level, 0, MAX_ELEVATION)
	_elevation[_index(p)] = level
	if level != 0:
		_tall = true
	revision += 1
	layout_revision += 1


## Storeys of the building on the tile: 0 outdoors, 1 or more indoors.
func get_storeys(p: Vector2i) -> int:
	if get_terrain(p) != Terrain.INDOOR:
		return 0
	return _storeys.get(p, 1)


func set_storeys(p: Vector2i, storeys: int) -> void:
	storeys = clampi(storeys, 1, MAX_STOREYS)
	if storeys <= 1:
		_storeys.erase(p)
	else:
		_storeys[p] = storeys
		_tall = true
	revision += 1
	layout_revision += 1


func has_stairs(p: Vector2i) -> bool:
	return _stairs.has(p)


func set_stairs(p: Vector2i, present: bool) -> void:
	if present:
		_stairs[p] = true
		_tall = true
	else:
		_stairs.erase(p)
	revision += 1
	layout_revision += 1


func get_stairs() -> Dictionary:
	return _stairs


func get_tall_buildings() -> Dictionary:
	return _storeys


## The highest level anyone can stand at on the tile: the roof of a building of two storeys or more,
## else the ground (or ground floor).
func top_level(p: Vector2i) -> int:
	var storeys := get_storeys(p)
	return storeys if storeys >= 2 else 0


func can_stand(p: Vector2i, level: int) -> bool:
	return in_bounds(p) and level >= 0 and level <= top_level(p)


func is_roof(p: Vector2i, level: int) -> bool:
	return level > 0 and level == get_storeys(p)


## Inside a building on that floor (ground floor included).
func is_indoors(p: Vector2i, level: int) -> bool:
	return level < get_storeys(p)


## Height of the floor a soldier at that level on the tile stands on.
func floor_height(p: Vector2i, level := 0) -> float:
	return get_elevation(p) + level


func eye_height(p: Vector2i, level := 0, stance := 0) -> float:
	return floor_height(p, level) + STANCE_EYE[stance]


## Per tile (indexed y * width + x), the top of whatever there could block a line of sight: lines passing
## over higher than this go through untouched. Rebuilt when the map changes.
func tile_tops() -> PackedFloat32Array:
	if _tops_revision != revision:
		_tops_revision = revision
		_tops.resize(width * height)
		for y in height:
			for x in width:
				var p := Vector2i(x, y)
				var i := _index(p)
				var top := float(_elevation[i])
				if _objects[i] == Cover.FULL:
					top = maxf(top, object_top(p))
				if _smoke.has(p):
					top = maxf(top, _elevation[i] + SMOKE_HEIGHT)
				if _terrain[i] == Terrain.INDOOR:
					top = maxf(top, _elevation[i] + get_storeys(p))
				if _terrain[i] == Terrain.JUNGLE:
					top = maxf(top, _elevation[i] + CANOPY_HEIGHT)
				_tops[i] = top
	return _tops


## The level a soldier at level `from_level` on a reaches by stepping onto the neighbouring tile b, or -1 if he
## can't get there that way. Indoors, a floor leads only to the same floor next door, and only the ground floor
## leads outside. Out in the open (on the ground or a roof) he can step to open ground or a roof within one
## level of his own, and from the ground through a door into a ground floor level with it.
func arrival_level(a: Vector2i, from_level: int, b: Vector2i) -> int:
	if not in_bounds(b):
		return -1
	var terrain_b := _terrain[_index(b)]
	if from_level == 0 and terrain_b != Terrain.INDOOR and get_terrain(a) != Terrain.INDOOR:
		# Open ground to open ground, the common case.
		return 0 if absi(_elevation[_index(a)] - _elevation[_index(b)]) <= 1 else -1
	var storeys_b := get_storeys(b)
	if is_indoors(a, from_level):
		if storeys_b > 0 and from_level < storeys_b and get_elevation(a) == get_elevation(b):
			return from_level
		if from_level == 0 and storeys_b == 0 and absi(get_elevation(a) - get_elevation(b)) <= 1:
			return 0
		return -1
	var here := get_elevation(a) + from_level
	if storeys_b == 0:
		return 0 if absi(here - get_elevation(b)) <= 1 else -1
	if from_level == 0 and get_storeys(a) == 0 and here == get_elevation(b):
		return 0
	if storeys_b >= 2 and absi(here - (get_elevation(b) + storeys_b)) <= 1:
		return storeys_b
	return -1


## The wall between two neighbouring tiles as it stands at the height of a step or a soldier at those
## levels: up on a roof, walls between building tiles are gone and the building's outer edge is a parapet
## (half cover); everywhere else the wall is the same on every floor.
func edge_at(a: Vector2i, b: Vector2i, level_a := 0, level_b := 0) -> int:
	if is_roof(a, level_a) or is_roof(b, level_b):
		var indoor_a := get_storeys(a) > 0
		var indoor_b := get_storeys(b) > 0
		if indoor_a and indoor_b:
			return Cover.NONE
		return Cover.HALF
	return get_edge(a, b)


## Cover level of the wall between two orthogonally adjacent tiles.
func get_edge(a: Vector2i, b: Vector2i) -> int:
	return _edges.get(_edge_key(a, b), Cover.NONE)


## Kinds: full cover "wall", "hedge", "bamboo_wall", "mud_wall"; half cover "window", "broken_window" (one
## climbed through), "fence", "stone", "dyke", "bamboo_window", "mud_window".
func get_edge_kind(a: Vector2i, b: Vector2i) -> String:
	return edge_kind(_edge_key(a, b))


func edge_kind(key: Vector3i) -> String:
	return _edge_kinds.get(key, "wall" if _edges.get(key, Cover.NONE) == Cover.FULL else "fence")


func set_edge(a: Vector2i, b: Vector2i, cover: int, kind := "") -> void:
	var key := _edge_key(a, b)
	_edge_damage.erase(key)
	if cover == Cover.NONE:
		_edges.erase(key)
		_edge_kinds.erase(key)
	else:
		_edges[key] = cover
		if kind == "":
			_edge_kinds.erase(key)
		else:
			_edge_kinds[key] = kind
	revision += 1
	layout_revision += 1


func get_edges() -> Dictionary:
	return _edges


## How damaged the edge is: 0 whole, 1 damaged, 2 breached, 3 gone (see damage_edge).
func edge_damage(key: Vector3i) -> int:
	return _edge_damage.get(key, 0)


func get_edge_damage() -> Dictionary:
	return _edge_damage


## Knocks an edge `stages` steps toward gone, no further than `cap` (a machine gun only chips stone). A full
## wall or hedge is breached at 2 (down to half cover, its kind kept) and gone at 3; a window, low wall or
## fence is gone at 2. A hit window loses its glass. A hedge takes HEDGE_DAMAGE_FACTOR times the stages.
## Returns whether anything changed.
func damage_edge(key: Vector3i, stages: int, cap := 3) -> bool:
	if not _edges.has(key) or stages <= 0:
		return false
	var kind := edge_kind(key)
	if kind == "hedge":
		stages *= HEDGE_DAMAGE_FACTOR
	var before: int = _edge_damage.get(key, 0)
	var damage := mini(before + stages, maxi(cap, before))
	if damage == before:
		return false
	if damage >= (3 if FULL_EDGE_KINDS.has(kind) else 2):
		_edges.erase(key)
		_edge_kinds.erase(key)
		_edge_damage[key] = 3
	else:
		_edge_damage[key] = damage
		_edge_kinds[key] = "broken_window" if kind == "window" else kind
		if damage >= 2:
			_edges[key] = Cover.HALF
	revision += 1
	layout_revision += 1
	return true


## The two tiles on either side of an edge key.
static func edge_tiles(key: Vector3i) -> Array[Vector2i]:
	var a := Vector2i(key.x, key.y)
	var result: Array[Vector2i] = [a, a + (Vector2i(1, 0) if key.z == 0 else Vector2i(0, 1))]
	return result


func has_smoke(p: Vector2i) -> bool:
	return _smoke.has(p)


func get_smoke() -> Dictionary:
	return _smoke


func add_smoke(p: Vector2i, until_turn: int) -> void:
	_smoke[p] = maxi(until_turn, _smoke.get(p, 0))
	revision += 1


## Clears smoke that has run out by the given turn index; returns the cleared tiles.
func clear_smoke(turn_index: int) -> Array[Vector2i]:
	var cleared: Array[Vector2i] = []
	for p: Vector2i in _smoke.keys():
		if _smoke[p] <= turn_index:
			_smoke.erase(p)
			cleared.append(p)
	if not cleared.is_empty():
		revision += 1
	return cleared


func is_explosive(p: Vector2i) -> bool:
	return get_object(p) != Cover.NONE and EXPLOSIVE_KINDS.has(get_object_kind(p))


func has_fire(p: Vector2i) -> bool:
	return _fires.has(p)


func get_fires() -> Dictionary:
	return _fires


func add_fire(p: Vector2i, until_turn: int) -> void:
	_fires[p] = maxi(until_turn, _fires.get(p, 0))
	revision += 1


## Puts out fires that have burnt out by the given turn index; returns their tiles.
func clear_fires(turn_index: int) -> Array[Vector2i]:
	var cleared: Array[Vector2i] = []
	for p: Vector2i in _fires.keys():
		if _fires[p] <= turn_index:
			_fires.erase(p)
			cleared.append(p)
	if not cleared.is_empty():
		revision += 1
	return cleared


func has_mine(p: Vector2i) -> bool:
	return _mines.has(p)


func get_mines() -> Dictionary:
	return _mines


func set_mine(p: Vector2i, present: bool, kind := "mine") -> void:
	if present:
		_mines[p] = true if kind == "mine" else kind
	else:
		_mines.erase(p)
	revision += 1


## "mine", or the kind of trap ("punji") buried on the tile.
func get_mine_kind(p: Vector2i) -> String:
	var value: Variant = _mines.get(p, true)
	return value if value is String else "mine"


## The team whose tunnel entrance is on the tile, or -1.
func tunnel_owner(p: Vector2i) -> int:
	return _tunnels.get(p, -1)


func get_tunnels() -> Dictionary:
	return _tunnels


func set_tunnel(p: Vector2i, team: int) -> void:
	if team < 0:
		_tunnels.erase(p)
	else:
		_tunnels[p] = team
	revision += 1


func set_vehicle(p: Vector2i, present: bool) -> void:
	if present:
		_vehicles[p] = true
	else:
		_vehicles.erase(p)
	revision += 1


func has_vehicle(p: Vector2i) -> bool:
	return _vehicles.has(p)


func is_passable(p: Vector2i) -> bool:
	return in_bounds(p) and get_object(p) == Cover.NONE


## Path cost of stepping from a to the neighbouring tile b, or INF if the step is impossible. Levels: the
## floor stood on at a, and the one arrived at on b (-1: work it out with arrival_level).
func step_cost(a: Vector2i, b: Vector2i, level_a := 0, level_b := -1) -> float:
	if not _tall:
		return _flat_step_cost(a, b)
	if level_b < 0:
		level_b = arrival_level(a, level_a, b)
	if level_b < 0:
		return INF
	if level_b == 0 and (not is_passable(b) or _fires.has(b)):
		return INF
	var cost: float = TERRAIN_COST[get_terrain(b)] + (trench_climb(a, b) if level_a == 0 else 0.0) if level_b == 0 else 1.0
	if level_a == 0 and level_b == 0 and _level_open(a, b) and (a.x == b.x or a.y == b.y or (_level_open(a, Vector2i(b.x, a.y)) and _level_open(a, Vector2i(a.x, b.y)))):
		# Level open ground: as on a flat map.
		return _flat_step_cost(a, b)
	var rise := floor_height(b, level_b) - floor_height(a, level_a)
	if a.x != b.x and a.y != b.y:
		# Diagonals only across level ground, and no cutting corners past objects or walls.
		if rise != 0.0:
			return INF
		for side: Vector2i in [Vector2i(b.x, a.y), Vector2i(a.x, b.y)]:
			if arrival_level(a, level_a, side) != level_a or floor_height(side, level_a) != floor_height(a, level_a):
				return INF
			if level_a == 0 and not is_passable(side):
				return INF
			if edge_at(a, side, level_a, level_a) != Cover.NONE or edge_at(side, b, level_a, level_b) != Cover.NONE:
				return INF
		return cost * DIAGONAL_FACTOR
	if rise > 0.0:
		cost += CLIMB_COST * rise
	match edge_at(a, b, level_a, level_b):
		Cover.FULL:
			return cost + HEDGE_COST if get_edge_kind(a, b) == "hedge" else INF
		Cover.HALF:
			return cost + VAULT_COST
	return cost


## Whether p is in a trench or within TRENCH_SIGHT tiles of one (counting diagonals as one): as far as
## sight from a trench reaches.
func beside_trench(p: Vector2i) -> bool:
	if not in_bounds(p):
		return false
	if _trench_revision != layout_revision:
		_build_trench_distance()
	return _trench_distance[_index(p)] <= TRENCH_SIGHT


## Every tile's distance in steps (diagonals count one) to the nearest trench, capped at TRENCH_SIGHT + 1.
func _build_trench_distance() -> void:
	_trench_revision = layout_revision
	_trench_distance.resize(width * height)
	_trench_distance.fill(TRENCH_SIGHT + 1)
	var frontier: Array[Vector2i] = []
	for y in height:
		for x in width:
			if _terrain[y * width + x] == Terrain.TRENCH:
				_trench_distance[y * width + x] = 0
				frontier.append(Vector2i(x, y))
	for step in range(1, TRENCH_SIGHT + 1):
		var next: Array[Vector2i] = []
		for p in frontier:
			for d: Vector2i in DIRS8:
				var q := p + d
				if in_bounds(q) and _trench_distance[_index(q)] > step:
					_trench_distance[_index(q)] = step
					next.append(q)
		frontier = next


## What stepping from a to b costs on top of the ground for climbing into or out of a trench.
func trench_climb(a: Vector2i, b: Vector2i) -> float:
	return TRENCH_CLIMB_COST if (get_terrain(a) == Terrain.TRENCH) != (get_terrain(b) == Terrain.TRENCH) else 0.0


## Whether b is open ground (no building) level with open ground at a.
func _level_open(a: Vector2i, b: Vector2i) -> bool:
	if not in_bounds(b):
		return false
	var i := _index(a)
	var j := _index(b)
	return _elevation[i] == _elevation[j] and _terrain[i] != Terrain.INDOOR and _terrain[j] != Terrain.INDOOR


## Climbing or descending a staircase on p by one storey, or INF without stairs or a floor there.
func stairs_cost(p: Vector2i, from_level: int, to_level: int) -> float:
	if not _stairs.has(p) or absi(from_level - to_level) != 1 or not can_stand(p, to_level) or not can_stand(p, from_level):
		return INF
	return STAIRS_COST


func _flat_step_cost(a: Vector2i, b: Vector2i) -> float:
	if not is_passable(b) or _fires.has(b):
		return INF
	var cost: float = TERRAIN_COST[get_terrain(b)] + trench_climb(a, b)
	if a.x != b.x and a.y != b.y:
		# No cutting corners past objects or walls.
		var side_x := Vector2i(b.x, a.y)
		var side_y := Vector2i(a.x, b.y)
		if not is_passable(side_x) or not is_passable(side_y):
			return INF
		for pair in [[a, side_x], [side_x, b], [a, side_y], [side_y, b]]:
			if get_edge(pair[0], pair[1]) != Cover.NONE:
				return INF
		return cost * DIAGONAL_FACTOR
	match get_edge(a, b):
		Cover.FULL:
			return cost + HEDGE_COST if get_edge_kind(a, b) == "hedge" else INF
		Cover.HALF:
			return cost + VAULT_COST
	return cost


## Path cost of a tank driving from a to b. Tanks crush low obstacles, fences and walls, knock down trees
## and push through hedges, all of which they destroy, but can't pass rocks, wrecks or buildings.
func vehicle_step_cost(a: Vector2i, b: Vector2i) -> float:
	if not in_bounds(b) or not _tank_can_enter(b) or _fires.has(b):
		return INF
	# Tanks roll straight over barbed wire, but bog down in paddies.
	var terrain := get_terrain(b)
	var cost: float = VEHICLE_TERRAIN_COST.get(terrain, TERRAIN_COST[terrain])
	if _tall:
		# Up one level at a time, and diagonally only across level ground.
		var rise := get_elevation(b) - get_elevation(a)
		if absi(rise) > 1 or get_storeys(b) > 1:
			return INF
		if rise != 0 and a.x != b.x and a.y != b.y:
			return INF
		if a.x != b.x and a.y != b.y and (get_elevation(Vector2i(b.x, a.y)) != get_elevation(a) or get_elevation(Vector2i(a.x, b.y)) != get_elevation(a)):
			return INF
		if rise > 0:
			cost += VEHICLE_CLIMB_COST
	if get_object_kind(b) == "fuel" and get_object(b) != Cover.NONE:
		# Possible, but the drums go up under the tank.
		cost += FUEL_CRUSH_COST
	elif get_object(b) == Cover.HALF:
		cost += CRUSH_COST
	elif get_object(b) == Cover.FULL:
		cost += TREE_COST
	if a.x != b.x and a.y != b.y:
		var side_x := Vector2i(b.x, a.y)
		var side_y := Vector2i(a.x, b.y)
		if get_object(side_x) == Cover.FULL or get_object(side_y) == Cover.FULL:
			return INF
		for pair in [[a, side_x], [side_x, b], [a, side_y], [side_y, b]]:
			if get_edge(pair[0], pair[1]) != Cover.NONE:
				return INF
		return cost * DIAGONAL_FACTOR
	if get_edge(a, b) != Cover.NONE:
		var kind := get_edge_kind(a, b)
		if not CRUSHABLE_EDGES.has(kind):
			return INF
		cost += HEDGE_COST + CRUSH_COST if kind == "hedge" else CRUSH_COST
	return cost


func _tank_can_enter(p: Vector2i) -> bool:
	return get_object(p) != Cover.FULL or FELLABLE_KINDS.has(get_object_kind(p))


## The concealment of a tile's terrain (see CONCEALMENT), or {}.
func concealment(p: Vector2i) -> Dictionary:
	return CONCEALMENT.get(get_terrain(p), {})


func is_jungle(p: Vector2i) -> bool:
	return get_terrain(p) == Terrain.JUNGLE


## Cover a unit standing on p gets on the side facing direction dir.
## A crater covers every side; a tank alongside counts as half cover; a bank of higher ground is full cover.
## A trench is full cover on every side except where it runs on into more trench.
## Upstairs, only the building's walls and windows count (an open doorway below is wall up there); on a
## roof, the parapet is half cover and a taller building alongside full cover.
## A whole hedge is full cover to someone lying behind it (`prone`) but only half to someone standing, who
## sees over it.
func cover_toward(p: Vector2i, dir: Vector2i, level := 0, prone := false) -> int:
	var q := p + dir
	if level > 0:
		if is_roof(p, level):
			var beside := floor_height(q, get_storeys(q))
			if beside > floor_height(p, level) + 0.5:
				return Cover.FULL
			if get_storeys(q) > 0 and beside == floor_height(p, level):
				return Cover.NONE
			return Cover.HALF
		var wall := get_edge(p, q)
		if wall == Cover.NONE and not (get_storeys(q) > level and get_elevation(q) == get_elevation(p)):
			return Cover.FULL
		return wall
	var edge := get_edge(p, q)
	if edge == Cover.FULL and not prone and get_edge_kind(p, q) == "hedge":
		edge = Cover.HALF
	var cover := maxi(edge, get_object(q))
	if _vehicles.has(q):
		cover = maxi(cover, Cover.HALF)
	if get_terrain(p) == Terrain.CRATER:
		cover = maxi(cover, Cover.HALF)
	elif get_terrain(p) == Terrain.TRENCH and get_terrain(q) != Terrain.TRENCH:
		cover = Cover.FULL
	if _tall and in_bounds(q) and get_elevation(q) > get_elevation(p):
		cover = Cover.FULL
	return cover


func has_cover(p: Vector2i, level := 0) -> bool:
	for d: Vector2i in DIRS4:
		if cover_toward(p, d, level, true) != Cover.NONE:
			return true
	return false


## Best cover protecting a unit on target from an attacker on attacker_pos.
## A side's cover counts when the attacker is in front of it, within roughly 63° of straight on.
## Shooting down from a level or more above, low cover no longer hides the target; from two levels above,
## full cover only half does. `prone`: the target lies down (see cover_toward).
func cover_against(target: Vector2i, attacker_pos: Vector2i, target_level := 0, attacker_level := 0, prone := false) -> int:
	var offset := attacker_pos - target
	var best := Cover.NONE
	for d: Vector2i in DIRS4:
		var along := offset.x * d.x + offset.y * d.y
		var across := absi(offset.x * d.y - offset.y * d.x)
		if along > 0 and along * 2 >= across:
			best = maxi(best, cover_toward(target, d, target_level, prone))
	if _tall and best != Cover.NONE:
		var drop := floor_height(attacker_pos, attacker_level) - floor_height(target, target_level)
		if drop >= 2.0:
			best -= 1
		elif drop >= 1.0 and best == Cover.HALF:
			best = Cover.NONE
	return best


func blocks_sight(p: Vector2i) -> bool:
	return get_object(p) == Cover.FULL or _smoke.has(p)


func edge_blocks_sight(a: Vector2i, b: Vector2i) -> bool:
	return get_edge(a, b) == Cover.FULL


## How high the full-cover object on p reaches.
func object_top(p: Vector2i) -> float:
	return get_elevation(p) + OBJECT_HEIGHT.get(get_object_kind(p), FULL_OBJECT_HEIGHT)


## How high a full wall or hedge between a and b reaches: a building's walls go up to its roof.
func edge_top(a: Vector2i, b: Vector2i) -> float:
	var top := 0.0
	for side: Vector2i in [a, b]:
		if get_storeys(side) > 0:
			top = maxf(top, floor_height(side, get_storeys(side)))
	if top > 0.0:
		return top
	var base := maxi(get_elevation(a), get_elevation(b))
	return base + (HEDGE_HEIGHT if get_edge_kind(a, b) == "hedge" else WALL_HEIGHT)


func tiles_in_radius(center: Vector2i, radius: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var r := ceili(radius)
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			var p := Vector2i(x, y)
			if in_bounds(p) and Vector2(center).distance_to(Vector2(p)) <= radius:
				result.append(p)
	return result


## Destroys every object and wall inside the radius and blasts a crater at the centre.
## Objects leave rubble. Returns how many pieces of cover were destroyed.
func destroy_cover(center: Vector2i, radius: float) -> int:
	return blast_cover(center, radius, 3, 3)


## A blast: clears objects, wire, mines and tunnel entrances in reach and leaves a crater, and knocks the
## walls, hedges and fences round the tile it lands on `center_stages` steps toward gone (damage_edge), those
## further out `area_stages`. Returns how many things it destroyed or damaged.
func blast_cover(center: Vector2i, radius: float, center_stages: int, area_stages: int) -> int:
	var area := {}
	var destroyed := 0
	for p in tiles_in_radius(center, radius):
		area[p] = true
		# Blasts set off buried mines, cave in tunnel entrances and tear up barbed wire.
		_mines.erase(p)
		_tunnels.erase(p)
		if get_terrain(p) == Terrain.WIRE:
			set_terrain(p, Terrain.FLOOR)
			destroyed += 1
		if get_object(p) != Cover.NONE:
			set_object(p, Cover.NONE)
			if not _storeys.has(p):
				set_terrain(p, Terrain.RUBBLE)
			destroyed += 1
	for key: Vector3i in _edges.keys():
		var pair := edge_tiles(key)
		var stages := center_stages if center in pair else (area_stages if area.has(pair[0]) or area.has(pair[1]) else 0)
		if damage_edge(key, stages):
			destroyed += 1
	if in_bounds(center) and get_terrain(center) not in [Terrain.INDOOR, Terrain.TRENCH]:
		set_terrain(center, Terrain.CRATER)
	revision += 1
	layout_revision += 1
	return destroyed


func to_dict() -> Dictionary:
	var data := {
		"width": width, "height": height, "terrain": _terrain.duplicate(), "objects": _objects.duplicate(),
		"object_kinds": _object_kinds.duplicate(), "edges": _edges.duplicate(), "edge_kinds": _edge_kinds.duplicate(),
		"smoke": _smoke.duplicate(), "vehicles": _vehicles.duplicate(), "fires": _fires.duplicate(), "mines": _mines.duplicate(),
	}
	# Only maps with tunnels say so, so maps without read (and checksum) as they always have. Likewise heights.
	if not _tunnels.is_empty():
		data["tunnels"] = _tunnels.duplicate()
	if _elevation.count(0) != _elevation.size():
		data["elevation"] = _elevation.duplicate()
	if not _storeys.is_empty():
		data["storeys"] = _storeys.duplicate()
	if not _stairs.is_empty():
		data["stairs"] = _stairs.duplicate()
	if not _edge_damage.is_empty():
		data["edge_damage"] = _edge_damage.duplicate()
	return data


static func from_dict(data: Dictionary) -> TacticalMap:
	var map := TacticalMap.new(data["width"], data["height"])
	map._terrain = data["terrain"].duplicate()
	map._objects = data["objects"].duplicate()
	map._object_kinds = data["object_kinds"].duplicate()
	map._edges = data["edges"].duplicate()
	map._edge_kinds = data["edge_kinds"].duplicate()
	map._edge_damage = data.get("edge_damage", {}).duplicate()
	map._smoke = data["smoke"].duplicate()
	map._vehicles = data["vehicles"].duplicate()
	map._fires = data.get("fires", {}).duplicate()
	map._mines = data.get("mines", {}).duplicate()
	map._tunnels = data.get("tunnels", {}).duplicate()
	if data.has("elevation"):
		map._elevation = PackedInt32Array(data["elevation"])
	map._storeys = data.get("storeys", {}).duplicate()
	map._stairs = data.get("stairs", {}).duplicate()
	map._tall = map._elevation.count(0) != map._elevation.size() or not map._storeys.is_empty() or not map._stairs.is_empty()
	return map


## The key of the edge between two orthogonally adjacent tiles (as get_edges() uses).
static func edge_key(a: Vector2i, b: Vector2i) -> Vector3i:
	return _edge_key(a, b)


func _index(p: Vector2i) -> int:
	return p.y * width + p.x


static func _edge_key(a: Vector2i, b: Vector2i) -> Vector3i:
	if a.x != b.x:
		return Vector3i(mini(a.x, b.x), a.y, 0)
	return Vector3i(a.x, mini(a.y, b.y), 1)
