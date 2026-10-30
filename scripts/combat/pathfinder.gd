class_name Pathfinder
extends RefCounted
## Dijkstra search over the tactical grid: 8-way, terrain- and wall-aware.


## Returns {tile: {"cost": float, "prev": Vector2i}} for every tile reachable within max_cost.
## Tiles in `blocked` (e.g. occupied by units) can't be entered.
static func search(map: TacticalMap, start: Vector2i, max_cost: float, blocked := {}) -> Dictionary:
	var result := {start: {"cost": 0.0, "prev": start}}
	var open: Array[Vector2i] = [start]
	while not open.is_empty():
		var best := 0
		for i in range(1, open.size()):
			if result[open[i]]["cost"] < result[open[best]]["cost"]:
				best = i
		var current := open[best]
		open.remove_at(best)
		var current_cost: float = result[current]["cost"]
		for d: Vector2i in TacticalMap.DIRS8:
			var next := current + d
			if blocked.has(next):
				continue
			var cost := current_cost + map.step_cost(current, next)
			if cost > max_cost + 0.001:
				continue
			if not result.has(next):
				open.append(next)
			elif cost >= result[next]["cost"] - 0.001:
				continue
			result[next] = {"cost": cost, "prev": current}
	return result


## The steps from the search start to dest, excluding the start tile.
static func path_to(result: Dictionary, dest: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not result.has(dest):
		return path
	var p := dest
	while result[p]["prev"] != p:
		path.push_front(p)
		p = result[p]["prev"]
	return path
