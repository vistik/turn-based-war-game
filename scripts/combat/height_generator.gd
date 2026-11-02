class_name HeightGenerator
extends RefCounted
## Rolling hills for generated maps: rounded rises a few levels high that step down one level at a time, so
## they can always be walked (no cliffs). Ground that must stay level (roads, buildings, paddies, the starts,
## the objectives' lane) stays at 0, and the hills ease down toward it. Raised on the west half and mirrored
## onto the east, like everything else on a generated map.


## Raises `count` hills up to `max_height` levels on the west half, keeping the tiles in `flat` at 0.
static func raise_hills(b: MapBuilder, rng: RandomNumberGenerator, flat: Dictionary, count: int, max_height: int) -> void:
	var map := b.map
	var mid := map.width / 2
	# How high each tile may rise: one level per tile away from ground that must stay flat.
	var limit := {}
	var queue: Array[Vector2i] = []
	for y in map.height:
		for x in mid:
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
			if q.x < 0 or q.x >= mid or q.y < 0 or q.y >= map.height or limit.has(q):
				continue
			limit[q] = limit[p] + 1
			queue.append(q)
	var heights := {}
	for i in count:
		var center := Vector2(rng.randf_range(6.0, mid - 3.0), rng.randf_range(2.0, map.height - 3.0))
		var top := rng.randi_range(1, max_height)
		# Each level of the hill is a ring this many tiles wide (over 1.5, so neighbours differ by a level at most).
		var ring := rng.randf_range(1.7, 2.8)
		var reach := ceili(top * ring)
		for y in range(int(center.y) - reach, int(center.y) + reach + 1):
			for x in range(int(center.x) - reach, int(center.x) + reach + 1):
				var p := Vector2i(x, y)
				if x < 0 or x >= mid or y < 0 or y >= map.height:
					continue
				var level := ceili(top - Vector2(p).distance_to(center) / ring)
				if level > heights.get(p, 0):
					heights[p] = level
	for p: Vector2i in heights:
		var level := mini(heights[p], limit.get(p, TacticalMap.MAX_ELEVATION))
		if level > 0:
			b.raise(Rect2i(p, Vector2i.ONE), level)
