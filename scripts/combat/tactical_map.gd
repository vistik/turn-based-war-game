class_name TacticalMap
extends RefCounted
## Grid data for a battle: terrain, cover objects standing on tiles, walls on the edges between tiles,
## smoke, fires and buried mines. Objects and edges also carry a kind ("tree", "hedge", ...) that changes
## how they look, and for hedges, how they're crossed. Fuel drums and oil tanks are objects that explode.

## TRAMPLED is wheat (or tall grass) flattened by soldiers or tanks moving through it; WIRE is a barbed-wire
## entanglement. JUNGLE is dense undergrowth: slow, hides whoever is in it and blocks sight through it.
## PADDY is a flooded rice field: slow, open, and it bogs vehicles down. TALL_GRASS is elephant grass: it
## hides crouching soldiers as well as prone ones, and is trampled like wheat.
enum Terrain { FLOOR, ROUGH, RUBBLE, INDOOR, ROAD, WHEAT, CRATER, TRAMPLED, WIRE, JUNGLE, PADDY, TALL_GRASS }

## North, east, south, west.
const DIRS4 := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIRS8 := [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const TERRAIN_NAMES := ["Grass", "Rough ground", "Rubble", "Indoor floor", "Road", "Wheat field", "Shell crater", "Trampled wheat", "Barbed wire",
		"Jungle", "Rice paddy", "Elephant grass"]
const TERRAIN_COST := [1.0, 2.0, 2.0, 1.0, 0.75, 1.5, 1.5, 1.0, 4.0, 2.0, 2.0, 1.5]
## What a tank pays where it differs from TERRAIN_COST: it rolls over wire, ploughs through undergrowth and
## bogs down in flooded paddies.
const VEHICLE_TERRAIN_COST := {Terrain.WIRE: 1.0, Terrain.JUNGLE: 3.0, Terrain.PADDY: 3.0, Terrain.TALL_GRASS: 1.0}
## What a tank leaves behind it.
const VEHICLE_FLATTENS := {Terrain.WIRE: Terrain.FLOOR, Terrain.WHEAT: Terrain.TRAMPLED, Terrain.TALL_GRASS: Terrain.TRAMPLED, Terrain.JUNGLE: Terrain.ROUGH}
## Crops and grass a standing or crouching soldier tramples flat as he walks out of it.
const TRAMPLES := {Terrain.WHEAT: Terrain.TRAMPLED, Terrain.TALL_GRASS: Terrain.TRAMPLED}
## Terrain that hides those in it from anyone further than "range" tiles away, in the listed stances, unless
## they have fired; and makes them harder to hit beyond that range ("defense", shown as "label").
const CONCEALMENT := {
	Terrain.WHEAT: {"range": 4.0, "stances": [2], "defense": 10, "label": "In the wheat"},
	Terrain.TALL_GRASS: {"range": 3.0, "stances": [1, 2], "defense": 10, "label": "In the tall grass"},
	Terrain.JUNGLE: {"range": 3.0, "stances": [0, 1, 2], "defense": 15, "label": "In the jungle"},
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

var width: int
var height: int
## Bumped on every change, so caches (vision, drawing) know when to rebuild.
var revision := 0
## Bumped only when terrain, objects or walls change (not smoke).
var layout_revision := 0
var _terrain := PackedInt32Array()
var _objects := PackedInt32Array()
var _object_kinds := {}
## Edge key (see _edge_key) -> cover level, and -> kind.
var _edges := {}
var _edge_kinds := {}
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


func _init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	_terrain.resize(width * height)
	_terrain.fill(Terrain.FLOOR)
	_objects.resize(width * height)
	_objects.fill(Cover.NONE)


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
## half cover "crate", "sandbags", "hay", "pew", "fuel", "rice_sacks", "jersey" (a concrete barrier).
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


## Cover level of the wall between two orthogonally adjacent tiles.
func get_edge(a: Vector2i, b: Vector2i) -> int:
	return _edges.get(_edge_key(a, b), Cover.NONE)


## Kinds: full cover "wall", "hedge", "bamboo_wall", "mud_wall"; half cover "window", "fence", "stone", "dyke",
## "bamboo_window", "mud_window".
func get_edge_kind(a: Vector2i, b: Vector2i) -> String:
	return edge_kind(_edge_key(a, b))


func edge_kind(key: Vector3i) -> String:
	return _edge_kinds.get(key, "wall" if _edges.get(key, Cover.NONE) == Cover.FULL else "fence")


func set_edge(a: Vector2i, b: Vector2i, cover: int, kind := "") -> void:
	var key := _edge_key(a, b)
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


## Path cost of stepping from a to the neighbouring tile b, or INF if the step is impossible.
func step_cost(a: Vector2i, b: Vector2i) -> float:
	if not is_passable(b) or _fires.has(b):
		return INF
	var cost: float = TERRAIN_COST[get_terrain(b)]
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
## A crater covers every side; a tank alongside counts as half cover.
func cover_toward(p: Vector2i, dir: Vector2i) -> int:
	var cover := maxi(get_edge(p, p + dir), get_object(p + dir))
	if _vehicles.has(p + dir):
		cover = maxi(cover, Cover.HALF)
	if get_terrain(p) == Terrain.CRATER:
		cover = maxi(cover, Cover.HALF)
	return cover


func has_cover(p: Vector2i) -> bool:
	for d: Vector2i in DIRS4:
		if cover_toward(p, d) != Cover.NONE:
			return true
	return false


## Best cover protecting a unit on target from an attacker on attacker_pos.
## A side's cover counts when the attacker is in front of it, within roughly 63° of straight on.
func cover_against(target: Vector2i, attacker_pos: Vector2i) -> int:
	var offset := attacker_pos - target
	var best := Cover.NONE
	for d: Vector2i in DIRS4:
		var along := offset.x * d.x + offset.y * d.y
		var across := absi(offset.x * d.y - offset.y * d.x)
		if along > 0 and along * 2 >= across:
			best = maxi(best, cover_toward(target, d))
	return best


func blocks_sight(p: Vector2i) -> bool:
	return get_object(p) == Cover.FULL or _smoke.has(p)


func edge_blocks_sight(a: Vector2i, b: Vector2i) -> bool:
	return get_edge(a, b) == Cover.FULL


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
			set_terrain(p, Terrain.RUBBLE)
			destroyed += 1
	for key: Vector3i in _edges.keys():
		var pair := edge_tiles(key)
		if area.has(pair[0]) or area.has(pair[1]):
			_edges.erase(key)
			_edge_kinds.erase(key)
			destroyed += 1
	if in_bounds(center) and get_terrain(center) != Terrain.INDOOR:
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
	# Only maps with tunnels say so, so maps without read (and checksum) as they always have.
	if not _tunnels.is_empty():
		data["tunnels"] = _tunnels.duplicate()
	return data


static func from_dict(data: Dictionary) -> TacticalMap:
	var map := TacticalMap.new(data["width"], data["height"])
	map._terrain = data["terrain"].duplicate()
	map._objects = data["objects"].duplicate()
	map._object_kinds = data["object_kinds"].duplicate()
	map._edges = data["edges"].duplicate()
	map._edge_kinds = data["edge_kinds"].duplicate()
	map._smoke = data["smoke"].duplicate()
	map._vehicles = data["vehicles"].duplicate()
	map._fires = data.get("fires", {}).duplicate()
	map._mines = data.get("mines", {}).duplicate()
	map._tunnels = data.get("tunnels", {}).duplicate()
	return map


func _index(p: Vector2i) -> int:
	return p.y * width + p.x


static func _edge_key(a: Vector2i, b: Vector2i) -> Vector3i:
	if a.x != b.x:
		return Vector3i(mini(a.x, b.x), a.y, 0)
	return Vector3i(a.x, mini(a.y, b.y), 1)
