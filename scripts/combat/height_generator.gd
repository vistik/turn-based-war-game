class_name HeightGenerator
extends RefCounted
## Rolling hills for generated maps: rounded rises a few levels high that step down one level at a time, so
## they can always be walked (no cliffs). Ground that must stay level (roads, buildings, paddies, the
## deployment strips) stays at 0, and the hills ease down toward it. Nothing is mirrored: each hill is raised
## where it falls, and NaturalMap picks objectives fair to both sides after the hills are up.


## Raises `count` hills up to `max_height` levels over the whole map, keeping the tiles in `flat` at 0. Each
## hill's top is the best of a few random spots by `prefer` (prefer.call(p: Vector2i) -> float, higher is
## better; empty takes the first spot), so hills can be steered onto rough ground. Returns each hill's top
## tile that ended up raised.
static func raise_hills(b: MapBuilder, rng: RandomNumberGenerator, flat: Dictionary, count: int, max_height: int, prefer := Callable()) -> Array[Vector2i]:
	var map := b.map
	# How high each tile may rise: one level per tile away from ground that must stay flat.
	var limit := {}
	var queue: Array[Vector2i] = []
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if flat.has(p):
				limit[p] = 0
				queue.append(p)
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		for d: Vector2i in TacticalMap.DIRS8:
			var q := p + d
			if not map.in_bounds(q) or limit.has(q):
				continue
			limit[q] = limit[p] + 1
			queue.append(q)
	var heights := {}
	var tops: Array[Vector2i] = []
	for i in count:
		var center := Vector2.ZERO
		var best := -INF
		for sample in (4 if prefer.is_valid() else 1):
			var spot := Vector2(rng.randf_range(3.0, map.width - 3.0), rng.randf_range(2.0, map.height - 3.0))
			var score: float = prefer.call(Vector2i(spot)) if prefer.is_valid() else 0.0
			if score > best:
				best = score
				center = spot
		tops.append(Vector2i(center))
		var top := rng.randi_range(1, max_height)
		# Each level of the hill is a ring this many tiles wide (over 1.5, so neighbours differ by a level at most).
		var ring := rng.randf_range(1.7, 2.8)
		var reach := ceili(top * ring)
		for y in range(int(center.y) - reach, int(center.y) + reach + 1):
			for x in range(int(center.x) - reach, int(center.x) + reach + 1):
				var p := Vector2i(x, y)
				if not map.in_bounds(p):
					continue
				var level := ceili(top - Vector2(p).distance_to(center) / ring)
				if level > heights.get(p, 0):
					heights[p] = level
	for p: Vector2i in heights:
		var level := mini(heights[p], limit.get(p, TacticalMap.MAX_ELEVATION))
		if level > 0:
			b.raise(Rect2i(p, Vector2i.ONE), level)
	var raised: Array[Vector2i] = []
	for p in tops:
		if map.in_bounds(p) and map.get_elevation(p) > 0:
			raised.append(p)
	return raised
