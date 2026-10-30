class_name TacticalMap
extends RefCounted
## Grid data for a battle: terrain, cover objects standing on tiles, and walls on the edges between tiles.

enum Terrain { FLOOR, ROUGH, RUBBLE }

## North, east, south, west.
const DIRS4 := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIRS8 := [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const TERRAIN_NAMES := ["Floor", "Rough ground", "Rubble"]
const TERRAIN_COST := [1.0, 2.0, 2.0]
const DIAGONAL_FACTOR := 1.5
## Extra cost for climbing over a half-height wall.
const VAULT_COST := 1.0

var width: int
var height: int
var _terrain := PackedInt32Array()
var _objects := PackedInt32Array()
## Edge key (see _edge_key) -> cover level.
var _edges := {}


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


## Cover level of the object standing on a tile. Any object blocks movement.
func get_object(p: Vector2i) -> int:
	return _objects[_index(p)] if in_bounds(p) else Cover.NONE


func set_object(p: Vector2i, cover: int) -> void:
	_objects[_index(p)] = cover


## Cover level of the wall between two orthogonally adjacent tiles.
func get_edge(a: Vector2i, b: Vector2i) -> int:
	return _edges.get(_edge_key(a, b), Cover.NONE)


func set_edge(a: Vector2i, b: Vector2i, cover: int) -> void:
	if cover == Cover.NONE:
		_edges.erase(_edge_key(a, b))
	else:
		_edges[_edge_key(a, b)] = cover


func get_edges() -> Dictionary:
	return _edges


## The two tiles on either side of an edge key.
static func edge_tiles(key: Vector3i) -> Array[Vector2i]:
	var a := Vector2i(key.x, key.y)
	var result: Array[Vector2i] = [a, a + (Vector2i(1, 0) if key.z == 0 else Vector2i(0, 1))]
	return result


func is_passable(p: Vector2i) -> bool:
	return in_bounds(p) and get_object(p) == Cover.NONE


## Path cost of stepping from a to the neighbouring tile b, or INF if the step is impossible.
func step_cost(a: Vector2i, b: Vector2i) -> float:
	if not is_passable(b):
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
			return INF
		Cover.HALF:
			return cost + VAULT_COST
	return cost


## Cover a unit standing on p gets on the side facing direction dir.
func cover_toward(p: Vector2i, dir: Vector2i) -> int:
	return maxi(get_edge(p, p + dir), get_object(p + dir))


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
	return get_object(p) == Cover.FULL


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


## Destroys every object and wall inside the radius. Objects leave rubble. Returns how many were destroyed.
func destroy_cover(center: Vector2i, radius: float) -> int:
	var area := {}
	var destroyed := 0
	for p in tiles_in_radius(center, radius):
		area[p] = true
		if get_object(p) != Cover.NONE:
			set_object(p, Cover.NONE)
			set_terrain(p, Terrain.RUBBLE)
			destroyed += 1
	for key: Vector3i in _edges.keys():
		var pair := edge_tiles(key)
		if area.has(pair[0]) or area.has(pair[1]):
			_edges.erase(key)
			destroyed += 1
	return destroyed


func _index(p: Vector2i) -> int:
	return p.y * width + p.x


static func _edge_key(a: Vector2i, b: Vector2i) -> Vector3i:
	if a.x != b.x:
		return Vector3i(mini(a.x, b.x), a.y, 0)
	return Vector3i(a.x, mini(a.y, b.y), 1)
