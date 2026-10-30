class_name TerrainPainter
extends RefCounted
## Procedural art for the battlefield: ground tiles, cast shadows and props
## (boulders, crates, sandbags, concrete walls, windows, fences) drawn as projected 3D shapes.
## Variation comes from a per-tile hash, so the map looks the same every time it is drawn.

## Shadow offset on the ground per tile of height, in grid space. The light comes from the north-west.
const LIGHT := Vector2(0.45, 0.3)
const SHADOW := Color(0, 0, 0, 0.26)
const GRASS := [Color("4a6739"), Color("587842")]
const GRASS_BLADES := [Color("3b5530"), Color("6f9050"), Color("7d8f4a")]
const DRY_GROUND := [Color("6b6540"), Color("7a7149")]
const BUSH := [Color("46552a"), Color("5a6a32")]
const RUBBLE := Color("5d564e")
const STONE := Color("8d867c")
const INDOOR := [Color("6e6153"), Color("75685a")]
const PLANK_LINE := Color("54483b")
const ROCK := [Color("8a8984"), Color("7b7266")]
const CRATE := Color("9c7442")
const SANDBAG := Color("a99b6d")
const CONCRETE := Color("c0c1bc")
const WOOD := Color("7b5b37")
const GLASS := Color(0.65, 0.82, 0.95, 0.28)
const WALL_HEIGHT := 1.05
const SILL_HEIGHT := 0.4
const LINTEL_BASE := 0.84
const WALL_HALF_THICKNESS := 0.07


## Deterministic pseudo-random 0..1 per tile (and salt).
static func noise(p: Vector2i, salt := 0) -> float:
	var h := p.x * 374761393 + p.y * 668265263 + salt * 1103515245
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


static func tile_poly(proj: ViewProjection, p: Vector2i) -> PackedVector2Array:
	var g := Vector2(p)
	return PackedVector2Array([
		proj.project(g), proj.project(g + Vector2(1, 0)),
		proj.project(g + Vector2(1, 1)), proj.project(g + Vector2(0, 1)),
	])


static func rect_poly(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


## A roughly round footprint; jitter > 0 makes it irregular, like a boulder.
static func blob_poly(center: Vector2, radius: float, p: Vector2i, jitter: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 8:
		var angle := TAU * i / 8.0 + (noise(p, 40 + i) - 0.5) * jitter
		points.append(center + Vector2.from_angle(angle) * radius * (1.0 + (noise(p, 50 + i) - 0.5) * jitter))
	return points


# --- Ground ---

static func draw_tile(c: CanvasItem, proj: ViewProjection, map: TacticalMap, p: Vector2i) -> void:
	var g := Vector2(p)
	var n := noise(p)
	match map.get_terrain(p):
		TacticalMap.Terrain.FLOOR:
			c.draw_colored_polygon(tile_poly(proj, p), GRASS[0].lerp(GRASS[1], n))
			for i in 6:
				var at := g + Vector2(0.1, 0.1) + Vector2(noise(p, i * 2 + 1), noise(p, i * 2 + 2)) * 0.8
				c.draw_line(proj.project(at), proj.project(at + Vector2(0.04, -0.05), 0.1), GRASS_BLADES[i % 3], 1.5)
		TacticalMap.Terrain.ROUGH:
			c.draw_colored_polygon(tile_poly(proj, p), DRY_GROUND[0].lerp(DRY_GROUND[1], n))
			for i in 2:
				var at := g + Vector2(0.25, 0.25) + Vector2(noise(p, i * 3 + 7), noise(p, i * 3 + 8)) * 0.5
				for j in 3:
					var offset := Vector2.from_angle(TAU * j / 3.0 + n) * 0.07
					var color: Color = BUSH[(i + j) % 2]
					c.draw_circle(proj.project(at + offset, 0.06), 4.0 + noise(p, i + j) * 2.0, color)
				c.draw_circle(proj.project(at + Vector2(-0.03, -0.03), 0.12), 2.5, BUSH[1].lightened(0.25))
		TacticalMap.Terrain.RUBBLE:
			c.draw_colored_polygon(tile_poly(proj, p), RUBBLE.lerp(RUBBLE.lightened(0.1), n))
			for i in 7:
				var at := g + Vector2(0.12, 0.12) + Vector2(noise(p, i * 2 + 11), noise(p, i * 2 + 12)) * 0.76
				var size := 0.04 + noise(p, i + 30) * 0.06
				var stone := PackedVector2Array([
					proj.project(at + Vector2(-size, 0)), proj.project(at + Vector2(0, -size), size),
					proj.project(at + Vector2(size, 0)), proj.project(at + Vector2(0, size)),
				])
				c.draw_colored_polygon(stone, STONE.darkened(noise(p, i + 20) * 0.35))
		TacticalMap.Terrain.INDOOR:
			c.draw_colored_polygon(tile_poly(proj, p), INDOOR[0].lerp(INDOOR[1], n))
			for i in range(1, 4):
				var y := i / 4.0
				c.draw_line(proj.project(g + Vector2(0, y)), proj.project(g + Vector2(1, y)), PLANK_LINE, 1.0)
			var seam := 0.2 + n * 0.6
			c.draw_line(proj.project(g + Vector2(seam, 0.25)), proj.project(g + Vector2(seam, 0.5)), PLANK_LINE, 1.0)


## The shadow a prism of the given height casts on the ground.
static func draw_shadow(c: CanvasItem, proj: ViewProjection, footprint: PackedVector2Array, height: float) -> void:
	var points := PackedVector2Array()
	for p in footprint:
		points.append(proj.project(p))
		points.append(proj.project(p + LIGHT * height))
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	if hull.size() >= 3:
		c.draw_colored_polygon(hull, SHADOW)


static func draw_object_shadow(c: CanvasItem, proj: ViewProjection, map: TacticalMap, p: Vector2i) -> void:
	var full := map.get_object(p) == Cover.FULL
	draw_shadow(c, proj, rect_poly(Rect2(Vector2(p), Vector2.ONE).grow(-0.12 if full else -0.2)), _rock_height(p) if full else 0.45)


static func draw_edge_shadow(c: CanvasItem, proj: ViewProjection, map: TacticalMap, key: Vector3i) -> void:
	var low: bool = map.get_edges()[key] == Cover.HALF
	var height := 0.25 if low and not _is_window(map, key) else WALL_HEIGHT
	draw_shadow(c, proj, _edge_rect(key, 0.0, 1.0, WALL_HALF_THICKNESS), height)


# --- Props ---

## A vertical prism over a convex grid footprint, lit from LIGHT. Returns the visible side faces
## as screen quads [bottom a, bottom b, top b, top a] so callers can add surface detail.
static func prism(c: CanvasItem, proj: ViewProjection, footprint: PackedVector2Array, base: float, top: float, color: Color, alpha := 1.0) -> Array:
	var faces := []
	var center := Vector2.ZERO
	for p in footprint:
		center += p
	center /= footprint.size()
	if proj.isometric:
		var toward_light := -LIGHT.normalized()
		for i in footprint.size():
			var a := footprint[i]
			var b := footprint[(i + 1) % footprint.size()]
			var normal := Vector2(b.y - a.y, a.x - b.x)
			if normal.dot((a + b) * 0.5 - center) < 0.0:
				normal = -normal
			# Only faces pointing toward the viewer (down the screen) are visible.
			var screen_normal := proj.rotate_grid(normal) - proj.rotate_grid(Vector2.ZERO)
			if screen_normal.x + screen_normal.y <= 0.001:
				continue
			var shade := 0.55 + 0.4 * maxf(0.0, normal.normalized().dot(toward_light))
			var quad := PackedVector2Array([proj.project(a, base), proj.project(b, base), proj.project(b, top), proj.project(a, top)])
			c.draw_colored_polygon(quad, Color(color.darkened(1.0 - shade), alpha))
			faces.append(quad)
	var top_poly := PackedVector2Array()
	for p in footprint:
		top_poly.append(proj.project(p, top))
	c.draw_colored_polygon(top_poly, Color(color.lightened(0.12), alpha))
	top_poly.append(top_poly[0])
	c.draw_polyline(top_poly, Color(color.darkened(0.45), alpha * 0.8), 1.0)
	return faces


static func draw_object(c: CanvasItem, proj: ViewProjection, map: TacticalMap, p: Vector2i, alpha: float, dark: bool) -> void:
	var center := Vector2(p) + Vector2(0.5, 0.5)
	var tint := 0.45 if dark else 0.0
	if map.get_object(p) == Cover.FULL:
		# A boulder: a wide irregular base with a smaller, offset cap.
		var color: Color = ROCK[0].lerp(ROCK[1], noise(p, 3)).darkened(tint)
		var height := _rock_height(p)
		var split := height * (0.5 + noise(p, 4) * 0.15)
		var faces := prism(c, proj, blob_poly(center, 0.44, p, 0.7), 0.0, split, color, alpha)
		var cap_center := center + Vector2(noise(p, 8) - 0.5, noise(p, 9) - 0.5) * 0.14
		faces.append_array(prism(c, proj, blob_poly(cap_center, 0.29, p + Vector2i(7, 3), 0.7), split, height, color.lightened(0.06), alpha))
		for i in faces.size():
			var q: Array = faces[i]
			if noise(p, 70 + i) < 0.5:
				var t := 0.3 + noise(p, 60 + i) * 0.4
				c.draw_line(q[0].lerp(q[3], t), q[1].lerp(q[2], t + 0.2), Color(color.darkened(0.4), alpha * 0.7), 1.0)
	elif noise(p, 5) < 0.5:
		_draw_crate(c, proj, Rect2(center - Vector2(0.31, 0.31), Vector2(0.62, 0.62)), 0.5, CRATE.darkened(tint), alpha)
	else:
		var color := SANDBAG.darkened(tint)
		var faces := prism(c, proj, blob_poly(center, 0.4, p, 0.05), 0.0, 0.42, color, alpha)
		var seam := Color(color.darkened(0.35), alpha)
		for q: Array in faces:
			for t in [0.36, 0.7]:
				c.draw_line(q[0].lerp(q[3], t), q[1].lerp(q[2], t), seam, 1.0)
			var bottom: Vector2 = q[0].lerp(q[1], 0.5)
			var top: Vector2 = q[3].lerp(q[2], 0.5)
			c.draw_line(bottom, bottom.lerp(top, 0.36), seam, 1.0)
		for i in 3:
			c.draw_circle(proj.project(center + Vector2.from_angle(TAU * i / 3.0 + 0.4) * 0.17, 0.43), 4.0, Color(color.lightened(0.18), alpha))


static func _draw_crate(c: CanvasItem, proj: ViewProjection, rect: Rect2, height: float, color: Color, alpha: float) -> void:
	var faces := prism(c, proj, rect_poly(rect), 0.0, height, color, alpha)
	var line := Color(color.darkened(0.45), alpha)
	for q: Array in faces:
		c.draw_line(q[0].lerp(q[3], 0.5), q[1].lerp(q[2], 0.5), line, 1.0)
		c.draw_line(q[0], q[2], line, 1.0)
		c.draw_polyline(PackedVector2Array([q[0], q[1], q[2], q[3], q[0]]), line, 1.5)
	var corners := rect_poly(rect)
	c.draw_line(proj.project(corners[0], height), proj.project(corners[2], height), line, 1.0)
	c.draw_line(proj.project(corners[1], height), proj.project(corners[3], height), line, 1.0)


static func draw_edge(c: CanvasItem, proj: ViewProjection, map: TacticalMap, key: Vector3i, alpha: float, dark: bool) -> void:
	var tint := 0.45 if dark else 0.0
	if map.get_edges()[key] == Cover.FULL:
		var color := CONCRETE.darkened(tint)
		var faces := prism(c, proj, _edge_rect(key, 0.0, 1.0, WALL_HALF_THICKNESS), 0.0, WALL_HEIGHT, color, alpha)
		for q: Array in faces:
			c.draw_colored_polygon(PackedVector2Array([q[0], q[1], q[1].lerp(q[2], 0.08), q[0].lerp(q[3], 0.08)]), Color(color.darkened(0.45), alpha))
			c.draw_line(q[0].lerp(q[3], 0.55), q[1].lerp(q[2], 0.55), Color(color.darkened(0.25), alpha), 1.0)
	elif _is_window(map, key):
		var color := CONCRETE.darkened(tint)
		prism(c, proj, _edge_rect(key, 0.0, 1.0, WALL_HALF_THICKNESS), 0.0, SILL_HEIGHT, color, alpha)
		var frame := _edge_frame(key)
		var a: Vector2 = frame[0] + frame[1] * 0.1
		var b: Vector2 = frame[0] + frame[1] * 0.9
		c.draw_colored_polygon(PackedVector2Array([
			proj.project(a, SILL_HEIGHT), proj.project(b, SILL_HEIGHT), proj.project(b, LINTEL_BASE), proj.project(a, LINTEL_BASE),
		]), Color(GLASS, GLASS.a * alpha))
		prism(c, proj, _edge_rect(key, 0.0, 0.1, WALL_HALF_THICKNESS), 0.0, WALL_HEIGHT, color, alpha)
		prism(c, proj, _edge_rect(key, 0.9, 1.0, WALL_HALF_THICKNESS), 0.0, WALL_HEIGHT, color, alpha)
		prism(c, proj, _edge_rect(key, 0.0, 1.0, WALL_HALF_THICKNESS), LINTEL_BASE, WALL_HEIGHT, color, alpha)
	else:
		var color := WOOD.darkened(tint)
		for t in [0.0, 0.5, 1.0]:
			prism(c, proj, _edge_rect(key, t - 0.04, t + 0.04, 0.045), 0.0, 0.55, color.darkened(0.1), alpha)
		for rail: Array in [[0.14, 0.21], [0.34, 0.41]]:
			prism(c, proj, _edge_rect(key, 0.0, 1.0, 0.025), rail[0], rail[1], color, alpha)


static func _rock_height(p: Vector2i) -> float:
	return 0.9 + noise(p, 7) * 0.3


## A half-height wall next to an indoor tile is a window; out in the open it's a fence.
static func _is_window(map: TacticalMap, key: Vector3i) -> bool:
	var pair := TacticalMap.edge_tiles(key)
	return map.get_terrain(pair[0]) == TacticalMap.Terrain.INDOOR or map.get_terrain(pair[1]) == TacticalMap.Terrain.INDOOR


## [start corner, direction along the edge, direction across it] in grid space.
static func _edge_frame(key: Vector3i) -> Array:
	if key.z == 0:
		return [Vector2(key.x + 1, key.y), Vector2(0, 1), Vector2(1, 0)]
	return [Vector2(key.x, key.y + 1), Vector2(1, 0), Vector2(0, 1)]


## A thin rectangle lying along part of an edge (from..to in 0..1 of its length).
static func _edge_rect(key: Vector3i, from: float, to: float, half_thickness: float) -> PackedVector2Array:
	var frame := _edge_frame(key)
	var start: Vector2 = frame[0]
	var along: Vector2 = frame[1]
	var across: Vector2 = frame[2] * half_thickness
	return PackedVector2Array([
		start + along * from - across, start + along * to - across,
		start + along * to + across, start + along * from + across,
	])
