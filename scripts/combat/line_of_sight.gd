class_name LineOfSight
extends RefCounted
## Grid line of sight. Full cover blocks sight, half cover does not.
## A unit next to full cover can step out to either side of it to look around the corner.


## Traces a line between the centres of a and b, tile by tile.
static func has_line(map: TacticalMap, a: Vector2i, b: Vector2i) -> bool:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var nx := absi(b.x - a.x)
	var ny := absi(b.y - a.y)
	var ix := 0
	var iy := 0
	var current := a
	while ix < nx or iy < ny:
		# Which tile boundary does the line cross next: vertical (<0), horizontal (>0) or a corner (0)?
		var cmp := (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		var next: Vector2i
		if cmp == 0:
			next = current + step
			var side_x := Vector2i(next.x, current.y)
			var side_y := Vector2i(current.x, next.y)
			if not _open_corner(map, current, side_x, next) and not _open_corner(map, current, side_y, next):
				return false
			ix += 1
			iy += 1
		elif cmp < 0:
			next = Vector2i(current.x + step.x, current.y)
			if map.edge_blocks_sight(current, next):
				return false
			ix += 1
		else:
			next = Vector2i(current.x, current.y + step.y)
			if map.edge_blocks_sight(current, next):
				return false
			iy += 1
		current = next
		if current != b and map.blocks_sight(current):
			return false
	return true


## Tiles a unit on p can shoot or look from: its own tile plus step-out tiles beside any full cover.
static func peek_positions(map: TacticalMap, p: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [p]
	for d: Vector2i in TacticalMap.DIRS4:
		if map.cover_toward(p, d) != Cover.FULL:
			continue
		for side: Vector2i in [Vector2i(d.y, d.x), Vector2i(-d.y, -d.x)]:
			var q := p + side
			if map.is_passable(q) and map.get_edge(p, q) == Cover.NONE and not result.has(q):
				result.append(q)
	return result


## Whether a unit on `from` can see `to`. Set target_peeks when `to` holds a unit that can lean out too.
static func can_see(map: TacticalMap, from: Vector2i, to: Vector2i, sight_range: float, target_peeks := true) -> bool:
	if Vector2(from).distance_to(Vector2(to)) > sight_range:
		return false
	var targets: Array[Vector2i] = [to]
	if target_peeks:
		targets = peek_positions(map, to)
	for source in peek_positions(map, from):
		for target in targets:
			if has_line(map, source, target):
				return true
	return false


static func _open_corner(map: TacticalMap, a: Vector2i, via: Vector2i, b: Vector2i) -> bool:
	return not map.edge_blocks_sight(a, via) and not map.blocks_sight(via) and not map.edge_blocks_sight(via, b)
