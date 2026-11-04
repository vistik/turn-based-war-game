class_name LineOfSight
extends RefCounted
## Grid line of sight. Full cover and smoke block sight, half cover does not, nor does a hedge to anyone standing
## (it's shoulder high, TacticalMap.HEDGE_HEIGHT, also on flat maps), and so does a thick stretch of
## jungle (more than TacticalMap.JUNGLE_SIGHT_TILES jungle tiles between the two ends).
## A unit next to full cover can step out to either side of it to look around the corner.
##
## On maps with height the line runs from eye to eye (TacticalMap.eye_height) and things only block it if
## they reach up to it: ridges and banks of higher ground, objects, walls and hedges by their height, smoke
## and jungle canopy up to theirs. Floors and roofs block lines that pass through them, building walls
## rise to the roof, and upstairs an open doorway below is wall. A soldier's own floor never blocks him: he
## can lean over a parapet or out of a window to look down.

## Sight reaches this many tiles further for every level the viewer stands above the target's floor.
const HEIGHT_SIGHT_BONUS := 2.0


## Traces a line between the centres of a and b, tile by tile. Eye heights default to someone standing on
## the given levels.
static func has_line(map: TacticalMap, a: Vector2i, b: Vector2i, level_a := 0, level_b := 0, eye_a := -1.0, eye_b := -1.0) -> bool:
	if not map.has_height():
		return _flat_line(map, a, b, eye_a if eye_a >= 0.0 else TacticalMap.STANCE_EYE[0], eye_b if eye_b >= 0.0 else TacticalMap.STANCE_EYE[0])
	if eye_a < 0.0:
		eye_a = map.eye_height(a, level_a)
	if eye_b < 0.0:
		eye_b = map.eye_height(b, level_b)
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var nx := absi(b.x - a.x)
	var ny := absi(b.y - a.y)
	var ix := 0
	var iy := 0
	var current := a
	var jungle := 0
	var h_in := eye_a
	var tops := map.tile_tops()
	var width := map.width
	while ix < nx or iy < ny:
		var cmp := (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		var t: float
		if cmp <= 0:
			t = (ix + 0.5) / nx
		else:
			t = (iy + 0.5) / ny
		var h := lerpf(eye_a, eye_b, t)
		# Leaving `current`: whatever stands in it, and its floors and roof.
		if current == a:
			if _crosses_floor(map, current, h_in, h, level_a):
				return false
		elif minf(h_in, h) < tops[current.y * width + current.x]:
			if _tile_blocks(map, current, h_in, h):
				return false
			if map.is_jungle(current) and minf(h_in, h) < map.get_elevation(current) + TacticalMap.CANOPY_HEIGHT:
				jungle += 1
				if jungle > TacticalMap.JUNGLE_SIGHT_TILES:
					return false
		var next: Vector2i
		if cmp == 0:
			next = current + step
			var side_x := Vector2i(next.x, current.y)
			var side_y := Vector2i(current.x, next.y)
			if not _open_corner_at(map, current, side_x, next, h) and not _open_corner_at(map, current, side_y, next, h):
				return false
			ix += 1
			iy += 1
		elif cmp < 0:
			next = Vector2i(current.x + step.x, current.y)
			if _edge_blocks(map, current, next, h):
				return false
			ix += 1
		else:
			next = Vector2i(current.x, current.y + step.y)
			if _edge_blocks(map, current, next, h):
				return false
			iy += 1
		current = next
		h_in = h
	return not _crosses_floor(map, b, h_in, eye_b, level_b)


## Tiles a unit on p can shoot or look from: its own tile plus step-out tiles beside any full cover, on the
## same floor.
static func peek_positions(map: TacticalMap, p: Vector2i, level := 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = [p]
	for d: Vector2i in TacticalMap.DIRS4:
		if map.cover_toward(p, d, level, true) != Cover.FULL:
			continue
		for side: Vector2i in [Vector2i(d.y, d.x), Vector2i(-d.y, -d.x)]:
			var q := p + side
			if result.has(q):
				continue
			if level == 0 and not map.has_height():
				if map.is_passable(q) and map.get_edge(p, q) == Cover.NONE:
					result.append(q)
			elif map.arrival_level(p, level, q) == level and map.floor_height(q, level) == map.floor_height(p, level) \
					and map.edge_at(p, q, level, level) == Cover.NONE and (level > 0 or map.is_passable(q)):
				result.append(q)
	return result


## Whether a unit on `from` can see `to`. Set target_peeks when `to` holds a unit that can lean out too.
## Smoke blocks sight through it, and hides anyone standing in it from all but adjacent tiles. Levels and
## stances set the eye heights at either end; standing higher than the target's floor sees further.
static func can_see(map: TacticalMap, from: Vector2i, to: Vector2i, sight_range: float, target_peeks := true,
		from_level := 0, to_level := 0, from_stance := 0, to_stance := 0) -> bool:
	var distance := Vector2(from).distance_to(Vector2(to))
	if map.has_height():
		sight_range += HEIGHT_SIGHT_BONUS * maxf(0.0, map.floor_height(from, from_level) - map.floor_height(to, to_level))
	if distance > sight_range:
		return false
	if distance > 1.5 and (map.has_smoke(from) or map.has_smoke(to)):
		return false
	if _sunk_in_trench(map, from, from_level, to, to_level) or _sunk_in_trench(map, to, to_level, from, from_level):
		return false
	var targets: Array[Vector2i] = [to]
	if target_peeks:
		targets = _cached_peeks(map, to, to_level)
	var from_eye: float = TacticalMap.STANCE_EYE[from_stance]
	var to_eye: float = TacticalMap.STANCE_EYE[to_stance]
	for source in _cached_peeks(map, from, from_level):
		for target in targets:
			if has_line(map, source, target, from_level, to_level, map.floor_height(source, from_level) + from_eye, map.floor_height(target, to_level) + to_eye):
				return true
	return false


## Whether someone in a trench on p and someone on other can't see each other over its lip: from a trench you
## see along it and TacticalMap.TRENCH_SIGHT tiles past it, nothing further, unless the other stands a level or
## more higher.
static func _sunk_in_trench(map: TacticalMap, p: Vector2i, level: int, other: Vector2i, other_level: int) -> bool:
	if level != 0 or map.get_terrain(p) != TacticalMap.Terrain.TRENCH or map.beside_trench(other):
		return false
	return not (map.has_height() and map.floor_height(other, other_level) >= map.floor_height(p) + 1.0)


## peek_positions, remembered on the map until it changes. The cache lives on the map rather than in a static
## so battles played at once on worker threads (tools/balance.gd) never share it.
static func _cached_peeks(map: TacticalMap, p: Vector2i, level: int) -> Array[Vector2i]:
	if map.revision != map.peek_cache_revision:
		map.peek_cache.clear()
		map.peek_cache_revision = map.revision
	var key := Vector3i(p.x, p.y, level)
	var cached: Variant = map.peek_cache.get(key)
	if cached == null:
		cached = peek_positions(map, p, level)
		map.peek_cache[key] = cached
	return cached


## On flat ground only hedges care about eye heights: lines pass over them above TacticalMap.HEDGE_HEIGHT.
static func _flat_line(map: TacticalMap, a: Vector2i, b: Vector2i, eye_a: float, eye_b: float) -> bool:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var nx := absi(b.x - a.x)
	var ny := absi(b.y - a.y)
	var ix := 0
	var iy := 0
	var current := a
	var jungle := 0
	while ix < nx or iy < ny:
		# Which tile boundary does the line cross next: vertical (<0), horizontal (>0) or a corner (0)?
		var cmp := (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		var h := lerpf(eye_a, eye_b, (ix + 0.5) / nx if cmp <= 0 else (iy + 0.5) / ny)
		var next: Vector2i
		if cmp == 0:
			next = current + step
			var side_x := Vector2i(next.x, current.y)
			var side_y := Vector2i(current.x, next.y)
			if not _open_corner(map, current, side_x, next, h) and not _open_corner(map, current, side_y, next, h):
				return false
			ix += 1
			iy += 1
		elif cmp < 0:
			next = Vector2i(current.x + step.x, current.y)
			if _flat_edge_blocks(map, current, next, h):
				return false
			ix += 1
		else:
			next = Vector2i(current.x, current.y + step.y)
			if _flat_edge_blocks(map, current, next, h):
				return false
			iy += 1
		current = next
		if current != b and map.blocks_sight(current):
			return false
		if current != b and map.is_jungle(current):
			jungle += 1
			if jungle > TacticalMap.JUNGLE_SIGHT_TILES:
				return false
	return true


static func _open_corner(map: TacticalMap, a: Vector2i, via: Vector2i, b: Vector2i, h: float) -> bool:
	return not _flat_edge_blocks(map, a, via, h) and not map.blocks_sight(via) and not _flat_edge_blocks(map, via, b, h)


static func _flat_edge_blocks(map: TacticalMap, a: Vector2i, b: Vector2i, h: float) -> bool:
	if not map.edge_blocks_sight(a, b):
		return false
	return h < TacticalMap.HEDGE_HEIGHT or map.get_edge_kind(a, b) != "hedge"


static func _open_corner_at(map: TacticalMap, a: Vector2i, via: Vector2i, b: Vector2i, h: float) -> bool:
	return not _edge_blocks(map, a, via, h) and not _tile_blocks(map, via, h, h) and not _edge_blocks(map, via, b, h)


## Whether something on tile p blocks a line passing over it between heights h_in and h_out: the ground,
## an object, smoke, or a floor or roof of the building there.
static func _tile_blocks(map: TacticalMap, p: Vector2i, h_in: float, h_out: float) -> bool:
	var low := minf(h_in, h_out)
	var ground := map.get_elevation(p)
	if low < ground:
		return true
	if map.get_object(p) == Cover.FULL and low < map.object_top(p):
		return true
	if map.has_smoke(p) and low < ground + TacticalMap.SMOKE_HEIGHT:
		return true
	return _crosses_floor(map, p, h_in, h_out, -1)


## Whether a line between heights h_in and h_out inside tile p goes through one of the building's upper
## floors or its roof (ignoring the floor at `own_level`, the one a soldier there stands on).
static func _crosses_floor(map: TacticalMap, p: Vector2i, h_in: float, h_out: float, own_level: int) -> bool:
	var storeys := map.get_storeys(p)
	if storeys == 0:
		return false
	var ground := map.get_elevation(p)
	for k in range(1, storeys + 1):
		if k == own_level:
			continue
		var slab := float(ground + k)
		if (h_in - slab) * (h_out - slab) < 0.0:
			return true
	return false


## Whether the boundary between neighbouring tiles c and n blocks a line crossing it at height h.
static func _edge_blocks(map: TacticalMap, c: Vector2i, n: Vector2i, h: float) -> bool:
	var cover := map.get_edge(c, n)
	if cover == Cover.FULL:
		return h < map.edge_top(c, n)
	if cover == Cover.NONE:
		# Upstairs, where the ground floor has a doorway, there is wall.
		return _upstairs_wall(map, c, n, h) or _upstairs_wall(map, n, c, h)
	return false


static func _upstairs_wall(map: TacticalMap, inside: Vector2i, other: Vector2i, h: float) -> bool:
	var storeys := map.get_storeys(inside)
	if storeys < 2:
		return false
	var rel := h - map.get_elevation(inside)
	if rel < 1.0 or rel >= storeys:
		return false
	var other_storeys := map.get_storeys(other)
	var other_rel := h - map.get_elevation(other)
	return other_storeys == 0 or other_rel < 0.0 or other_rel >= other_storeys
