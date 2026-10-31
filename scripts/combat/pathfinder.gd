class_name Pathfinder
extends RefCounted
## Dijkstra search over the tactical grid: 8-way, terrain- and wall-aware.
## Tanks search over (tile, heading): turning costs movement, and they can back up slowly without turning.

## The eight headings in clockwise order, starting north.
const HEADINGS := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
## Movement a tank spends per 45° it turns.
const TURN_COST := 1.0
## Backing up costs this many times the normal step.
const REVERSE_FACTOR := 2.0


## Returns {tile: {"cost": float, "prev": Vector2i}} for every tile reachable within max_cost.
## Tiles in `blocked` (e.g. occupied by units) can't be entered. Vehicles use the tank movement rules and
## start facing `facing`; their entries also carry "path" and "facings" (the hull's heading after each step).
static func search(map: TacticalMap, start: Vector2i, max_cost: float, blocked := {}, vehicle := false, facing := Vector2i(1, 0)) -> Dictionary:
	if vehicle:
		return _search_vehicle(map, start, max_cost, blocked, facing)
	var result := {start: {"cost": 0.0, "prev": start}}
	var heap := _Heap.new()
	heap.push(start, 0.0)
	while not heap.is_empty():
		var current: Vector2i = heap.pop()
		var current_cost: float = result[current]["cost"]
		if heap.last_priority > current_cost + 0.001:
			continue
		for d: Vector2i in TacticalMap.DIRS8:
			var next := current + d
			if blocked.has(next):
				continue
			var cost := current_cost + map.step_cost(current, next)
			if cost > max_cost + 0.001:
				continue
			if result.has(next) and cost >= result[next]["cost"] - 0.001:
				continue
			result[next] = {"cost": cost, "prev": current}
			heap.push(next, cost)
	return result


## The steps from the search start to dest, excluding the start tile.
static func path_to(result: Dictionary, dest: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not result.has(dest):
		return path
	if result[dest].has("path"):
		path.assign(result[dest]["path"])
		return path
	var p := dest
	while result[p]["prev"] != p:
		path.push_front(p)
		p = result[p]["prev"]
	return path


## Index into HEADINGS of the heading closest to a direction.
static func heading_index(dir: Vector2i) -> int:
	var found := HEADINGS.find(dir)
	if found != -1:
		return found
	var best := 0
	for i in HEADINGS.size():
		if Vector2(HEADINGS[i]).normalized().dot(Vector2(dir)) > Vector2(HEADINGS[best]).normalized().dot(Vector2(dir)):
			best = i
	return best


## Movement spent turning a tank from one heading to another.
static func turn_cost(from: Vector2i, to: Vector2i) -> float:
	var steps := absi(heading_index(from) - heading_index(to))
	return mini(steps, 8 - steps) * TURN_COST


static func _search_vehicle(map: TacticalMap, start: Vector2i, max_cost: float, blocked: Dictionary, facing: Vector2i) -> Dictionary:
	# A state is Vector3i(x, y, heading index). Pivoting in place is part of the first step's cost.
	var start_state := Vector3i(start.x, start.y, heading_index(facing))
	var costs := {start_state: 0.0}
	var prev := {start_state: start_state}
	var heap := _Heap.new()
	heap.push(start_state, 0.0)
	while not heap.is_empty():
		var state: Vector3i = heap.pop()
		var state_cost: float = costs[state]
		if heap.last_priority > state_cost + 0.001:
			continue
		var tile := Vector2i(state.x, state.y)
		var heading: Vector2i = HEADINGS[state.z]
		for i in HEADINGS.size():
			var d: Vector2i = HEADINGS[i]
			var next := tile + d
			if blocked.has(next):
				continue
			var step := map.vehicle_step_cost(tile, next)
			if step == INF:
				continue
			var next_state := Vector3i(next.x, next.y, i)
			var cost := state_cost + step + turn_cost(heading, d)
			if d == -heading:
				# Backing up: slower, but the hull keeps facing the same way.
				next_state.z = state.z
				cost = state_cost + step * REVERSE_FACTOR
			if cost > max_cost + 0.001:
				continue
			if costs.has(next_state) and cost >= costs[next_state] - 0.001:
				continue
			costs[next_state] = cost
			prev[next_state] = state
			heap.push(next_state, cost)

	var best := {}
	for state: Vector3i in costs:
		var tile := Vector2i(state.x, state.y)
		if not best.has(tile) or costs[state] < costs[best[tile]] - 0.001:
			best[tile] = state
	var result := {}
	for tile: Vector2i in best:
		var path: Array[Vector2i] = []
		var facings: Array[Vector2i] = []
		var state: Vector3i = best[tile]
		while prev[state] != state:
			path.push_front(Vector2i(state.x, state.y))
			facings.push_front(HEADINGS[state.z])
			state = prev[state]
		var before := Vector2i(prev[best[tile]].x, prev[best[tile]].y)
		result[tile] = {"cost": costs[best[tile]], "prev": before, "path": path, "facings": facings, "facing": HEADINGS[best[tile].z]}
	return result


## Binary min-heap of (item, priority). Stale entries are skipped by the caller via last_priority.
class _Heap:
	var _items := []
	var _priorities := PackedFloat64Array()
	var last_priority := 0.0

	func is_empty() -> bool:
		return _items.is_empty()

	func push(item: Variant, priority: float) -> void:
		_items.append(item)
		_priorities.append(priority)
		var i := _items.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if _priorities[parent] <= _priorities[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> Variant:
		var top: Variant = _items[0]
		last_priority = _priorities[0]
		var last := _items.size() - 1
		_swap(0, last)
		_items.remove_at(last)
		_priorities.remove_at(last)
		var i := 0
		var count := _items.size()
		while true:
			var smallest := i
			var left := i * 2 + 1
			var right := left + 1
			if left < count and _priorities[left] < _priorities[smallest]:
				smallest = left
			if right < count and _priorities[right] < _priorities[smallest]:
				smallest = right
			if smallest == i:
				break
			_swap(i, smallest)
			i = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var item: Variant = _items[a]
		_items[a] = _items[b]
		_items[b] = item
		var p := _priorities[a]
		_priorities[a] = _priorities[b]
		_priorities[b] = p
