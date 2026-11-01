class_name TerrainPainter
extends RefCounted
## Procedural art for the battlefield: ground tiles, cast shadows, props and smoke, drawn as projected 3D shapes.
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
const ROAD := [Color("7a6b50"), Color("837457")]
const RUT := Color("5e523c")
const WHEAT := [Color("a28c45"), Color("ad9850")]
const WHEAT_STALKS := [Color("c9b060"), Color("d9c274"), Color("9c8640")]
const CRATER_FLOOR := Color("3b342b")
const CRATER_RIM := Color("6e604c")
const ROCK := [Color("8a8984"), Color("7b7266")]
const CRATE := Color("9c7442")
const SANDBAG := Color("a99b6d")
const HAY := Color("c7a95a")
const WOOD := Color("7b5b37")
const MASONRY := Color("c6bca7")
const STONE_WALL := Color("9b9183")
const HEDGE := [Color("34502a"), Color("426236"), Color("2c4322")]
const TRUNK := Color("5a4330")
const LEAVES := [Color("38562a"), Color("466a33"), Color("57793d")]
const GLASS := Color(0.65, 0.82, 0.95, 0.28)
const FUEL_DRUM := [Color("7a2e22"), Color("4f5a2f"), Color("6d3a24")]
const OIL_TANK := Color("8c8f8a")
const WIRE := Color("4a4640")
const WIRE_POST := Color("5a4632")
const FLAME := [Color(1.0, 0.82, 0.3), Color(1.0, 0.5, 0.12), Color(0.85, 0.22, 0.08)]
const MINE := Color("3d3a33")
const MINE_SIGN := Color("e7d9a8")
const WALL_HEIGHT := 1.05
const HEDGE_HEIGHT := 1.0
const LOW_WALL_HEIGHT := 0.45
const SILL_HEIGHT := 0.4
const LINTEL_BASE := 0.84
const WALL_HALF_THICKNESS := 0.07
# Vietnam: tropical ground, red laterite, paddies, jungle, palms and bamboo.
const TROPIC_GRASS := [Color("487429"), Color("568431")]
const TROPIC_BLADES := [Color("3a6224"), Color("78a843"), Color("8fb54f")]
const LATERITE := [Color("a2563a"), Color("ae6340")]
const LATERITE_RUT := Color("7a3b25")
const FLAT_GRASS := [Color("7f8b4b"), Color("8b9254")]
const FLAT_BLADES := [Color("b9b878"), Color("a4ad68"), Color("cbc68d")]
const EARTH_FLOOR := [Color("6b5137"), Color("765b3f")]
const MAT := Color("b19661")
const JUNGLE_FLOOR := [Color("1f3317"), Color("263c1b")]
const JUNGLE_LEAVES := [Color("24441b"), Color("2f5a22"), Color("3d6c29"), Color("1f3d26")]
const PADDY_WATER := [Color("5b6b56"), Color("66755d")]
const PADDY_MUD := Color("4d4632")
const RICE := [Color("7fb547"), Color("9ccb5c"), Color("6a9e3a")]
const ELEPHANT_GRASS_GROUND := [Color("7b8045"), Color("878b4c")]
const ELEPHANT_GRASS := [Color("c3c27a"), Color("a9b25e"), Color("d4cd8c"), Color("98a253")]
const PLUME := Color("e4ddb4")
const PALM_TRUNK := Color("8a7458")
const FRONDS := [Color("3c6b28"), Color("4c8032"), Color("5e943e")]
const COCONUT := Color("6b5428")
const BAMBOO := Color("9aa851")
const BAMBOO_LEAVES := [Color("5f8f34"), Color("74a43f")]
const BURLAP := Color("b59d6c")
const DYKE_EARTH := Color("6b5539")
const DYKE_GRASS := [Color("5c8a37"), Color("6f9c42")]
const BAMBOO_WALL := Color("b49b5b")
const THATCH := Color("a58c55")
const JUNGLE_TRUNK := Color("6a5a48")
const JUNGLE_CANOPY := [Color("23461d"), Color("2f5a24"), Color("3f702d")]
const TUNNEL_HOLE := Color("120e0a")
const STAKE := Color("c9b27a")
const DYKE_HEIGHT := 0.3
# Afghanistan and Iraq.
const DUST := [Color("a8936a"), Color("b39e74")]
const DRY_TUFT := [Color("7d7a4a"), Color("8d8455"), Color("6b6a40")]
const PEBBLE := Color("8a7c62")
const STONY := [Color("958463"), Color("9e8d6b")]
const GREY_ROAD := [Color("8e8676"), Color("978f7e")]
const GREY_RUT := Color("756d5e")
const GREEN_WHEAT := [Color("848e3f"), Color("909847")]
const GREEN_STALKS := [Color("c2b45e"), Color("9fa752"), Color("cfc06e")]
const POPPY := [Color("d1342a"), Color("e8e0d8"), Color("c94a7a")]
const FLAT_WHEAT := [Color("9a9558"), Color("a49c62")]
const EARTH := [Color("9a8566"), Color("a38e6e")]
const RUG := [Color("7e3029"), Color("6a3d2c"), Color("38425a")]
const POPLAR_LEAVES := [Color("53682f"), Color("5f7636"), Color("6e843d")]
const POPLAR_TRUNK := Color("8a7a62")
const DITCH_WATER := Color("6c7c6c")
const DITCH_EARTH := Color("8f7a55")
const DITCH_BANK_HEIGHT := 0.22
const MUD_BRICK := Color("b49b71")
const MUD_HALF_THICKNESS := 0.09
const CAR_BURNT := Color("4a3d33")
const RUST := Color("8a4a26")
const HESCO_SAND := Color("b6a275")
const HESCO_MESH := Color("7d7562")
const HESCO_HEIGHT := 1.0
const CONCRETE := Color("b5b0a4")
const IED_SHELL := Color("5d6248")

## The theatre whose palette the ground is drawn in ("normandy" or "vietnam"). Set when a battle or scenario loads.
static var theatre := "normandy"


static func use_theatre(theatre_id: String) -> void:
	theatre = theatre_id


static func _tropical() -> bool:
	return theatre == "vietnam"


## Afghanistan and Iraq: dust, stone, mud brick and green-gold fields.
static func _arid() -> bool:
	return theatre == "modern"


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


## A circle on the ground (radius in tiles). Closed for outlines; open (no repeated point) for filling.
static func ground_circle(proj: ViewProjection, g: Vector2, radius: float, closed := true, height := 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segments := clampi(int(radius * 16), 16, 96)
	for i in segments:
		points.append(proj.project(g + Vector2.from_angle(TAU * i / segments) * radius, height))
	if closed:
		points.append(points[0])
	return points


# --- Ground ---

static func draw_tile(c: CanvasItem, proj: ViewProjection, map: TacticalMap, p: Vector2i) -> void:
	var g := Vector2(p)
	var n := noise(p)
	if _arid() and _draw_arid_tile(c, proj, map, p, g, n):
		return
	match map.get_terrain(p):
		TacticalMap.Terrain.FLOOR when _tropical():
			# Lush scrub: brighter grass, more blades and the odd broad-leafed tuft.
			c.draw_colored_polygon(tile_poly(proj, p), TROPIC_GRASS[0].lerp(TROPIC_GRASS[1], n))
			for i in 8:
				var at := g + Vector2(0.08, 0.08) + Vector2(noise(p, i * 2 + 1), noise(p, i * 2 + 2)) * 0.84
				c.draw_line(proj.project(at), proj.project(at + Vector2(0.03, -0.05), 0.13), TROPIC_BLADES[i % 3], 1.5)
			if n > 0.55:
				var tuft := g + Vector2(0.25, 0.25) + Vector2(noise(p, 31), noise(p, 32)) * 0.5
				for j in 4:
					var dir := Vector2.from_angle(TAU * j / 4.0 + n * 3.0)
					_leaf(c, proj.project(tuft), proj.project(tuft + dir * 0.13, 0.1), 2.2, TROPIC_BLADES[j % 3].darkened(0.1))
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
		TacticalMap.Terrain.INDOOR when _tropical():
			# Packed earth, mostly under a woven bamboo mat.
			c.draw_colored_polygon(tile_poly(proj, p), EARTH_FLOOR[0].lerp(EARTH_FLOOR[1], n))
			if n > 0.25:
				var lo := 0.08 + noise(p, 3) * 0.05
				var hi := 0.92 - noise(p, 4) * 0.05
				var mat := MAT.darkened(noise(p, 5) * 0.12)
				c.draw_colored_polygon(PackedVector2Array([proj.project(g + Vector2(lo, lo)), proj.project(g + Vector2(hi, lo)),
					proj.project(g + Vector2(hi, hi)), proj.project(g + Vector2(lo, hi))]), mat)
				for i in range(1, 7):
					var t := lerpf(lo, hi, i / 7.0)
					c.draw_line(proj.project(g + Vector2(t, lo)), proj.project(g + Vector2(t, hi)), mat.darkened(0.2), 1.0)
					c.draw_line(proj.project(g + Vector2(lo, t)), proj.project(g + Vector2(hi, t)), mat.darkened(0.12), 1.0)
			else:
				for i in 4:
					var at := g + Vector2(0.1, 0.1) + Vector2(noise(p, i + 3), noise(p, i + 9)) * 0.8
					c.draw_circle(proj.project(at), 1.5, EARTH_FLOOR[0].darkened(0.25))
		TacticalMap.Terrain.INDOOR:
			c.draw_colored_polygon(tile_poly(proj, p), INDOOR[0].lerp(INDOOR[1], n))
			for i in range(1, 4):
				var y := i / 4.0
				c.draw_line(proj.project(g + Vector2(0, y)), proj.project(g + Vector2(1, y)), PLANK_LINE, 1.0)
			var seam := 0.2 + n * 0.6
			c.draw_line(proj.project(g + Vector2(seam, 0.25)), proj.project(g + Vector2(seam, 0.5)), PLANK_LINE, 1.0)
		TacticalMap.Terrain.ROAD when _tropical():
			# A red laterite track, deeply rutted, with puddles in the ruts.
			c.draw_colored_polygon(tile_poly(proj, p), LATERITE[0].lerp(LATERITE[1], n))
			var along_x := map.get_terrain(p + Vector2i(1, 0)) == TacticalMap.Terrain.ROAD or map.get_terrain(p - Vector2i(1, 0)) == TacticalMap.Terrain.ROAD
			var side := Vector2(0, 0.045) if along_x else Vector2(0.045, 0)
			for t in [0.3, 0.7]:
				var a := g + (Vector2(0, t) if along_x else Vector2(t, 0))
				var b := a + (Vector2(1, 0) if along_x else Vector2(0, 1))
				c.draw_line(proj.project(a), proj.project(b), LATERITE_RUT, 3.0)
				c.draw_line(proj.project(a + side), proj.project(b + side), LATERITE[1].lightened(0.12), 1.0)
			if n > 0.6:
				var t := 0.3 if n > 0.8 else 0.7
				var at := g + (Vector2(0.2 + n * 0.4, t) if along_x else Vector2(t, 0.2 + n * 0.4))
				c.draw_colored_polygon(ground_circle(proj, at, 0.07, false), Color(0.55, 0.6, 0.62, 0.55))
			for i in 4:
				var at := g + Vector2(noise(p, i + 3), noise(p, i + 9)) * 0.9 + Vector2(0.05, 0.05)
				c.draw_circle(proj.project(at), 1.5, LATERITE[0].darkened(0.3))
		TacticalMap.Terrain.ROAD:
			c.draw_colored_polygon(tile_poly(proj, p), ROAD[0].lerp(ROAD[1], n))
			var along_x := map.get_terrain(p + Vector2i(1, 0)) == TacticalMap.Terrain.ROAD or map.get_terrain(p - Vector2i(1, 0)) == TacticalMap.Terrain.ROAD
			for t in [0.3, 0.7]:
				var a := g + (Vector2(0, t) if along_x else Vector2(t, 0))
				var b := a + (Vector2(1, 0) if along_x else Vector2(0, 1))
				c.draw_line(proj.project(a), proj.project(b), RUT, 2.0)
			for i in 3:
				var at := g + Vector2(noise(p, i + 3), noise(p, i + 9)) * 0.9 + Vector2(0.05, 0.05)
				c.draw_circle(proj.project(at), 1.5, ROAD[0].darkened(0.25))
		TacticalMap.Terrain.WHEAT:
			c.draw_colored_polygon(tile_poly(proj, p), WHEAT[0].lerp(WHEAT[1], n))
			for i in 12:
				var at := g + Vector2(0.06, 0.06) + Vector2(noise(p, i * 2 + 1), noise(p, i * 2 + 2)) * 0.88
				var top := proj.project(at + Vector2(0.02, -0.02), 0.35 + noise(p, i + 40) * 0.1)
				var color: Color = WHEAT_STALKS[i % 3]
				c.draw_line(proj.project(at), top, color.darkened(0.2), 1.2)
				c.draw_circle(top, 1.6, color)
		TacticalMap.Terrain.CRATER:
			c.draw_colored_polygon(tile_poly(proj, p), DRY_GROUND[0].darkened(0.1))
			var center := g + Vector2(0.5, 0.5)
			c.draw_colored_polygon(ground_circle(proj, center, 0.44, false), CRATER_RIM)
			c.draw_colored_polygon(ground_circle(proj, center, 0.34, false), CRATER_FLOOR)
			c.draw_polyline(ground_circle(proj, center + Vector2(0.03, 0.03), 0.3), CRATER_FLOOR.darkened(0.3), 1.5)
		TacticalMap.Terrain.TRAMPLED when _tropical():
			# Grass pressed flat, mostly one way, over bare earth.
			c.draw_colored_polygon(tile_poly(proj, p), FLAT_GRASS[0].lerp(FLAT_GRASS[1], n))
			var flat := n * TAU
			for i in 12:
				var at := g + Vector2(0.06, 0.06) + Vector2(noise(p, i * 2 + 1), noise(p, i * 2 + 2)) * 0.8
				var lie := Vector2.from_angle(flat + (noise(p, i + 50) - 0.5) * 0.9) * 0.2
				c.draw_line(proj.project(at), proj.project(at + lie, 0.015), FLAT_BLADES[i % 3], 1.4)
		TacticalMap.Terrain.TRAMPLED:
			# Flattened stalks lying every which way on churned soil.
			c.draw_colored_polygon(tile_poly(proj, p), WHEAT[0].darkened(0.18).lerp(DRY_GROUND[1], 0.3 + n * 0.2))
			for i in 10:
				var at := g + Vector2(0.08, 0.08) + Vector2(noise(p, i * 2 + 1), noise(p, i * 2 + 2)) * 0.84
				var lie := Vector2.from_angle(noise(p, i + 50) * TAU) * 0.16
				c.draw_line(proj.project(at), proj.project(at + lie, 0.02), WHEAT_STALKS[i % 3].darkened(0.15), 1.4)
		TacticalMap.Terrain.WIRE:
			# Grass with posts and coils of barbed wire.
			c.draw_colored_polygon(tile_poly(proj, p), GRASS[0].lerp(GRASS[1], n).darkened(0.1))
			var posts := [g + Vector2(0.15, 0.2 + n * 0.2), g + Vector2(0.85, 0.6 + n * 0.2)]
			for post: Vector2 in posts:
				c.draw_line(proj.project(post), proj.project(post, 0.45), WIRE_POST, 2.5)
			for k in 3:
				var h := 0.12 + k * 0.13
				c.draw_line(proj.project(posts[0], h), proj.project(posts[1], h + 0.03), WIRE, 1.0)
			for i in 6:
				var at: Vector2 = posts[0].lerp(posts[1], (i + 0.5) / 6.0)
				c.draw_arc(proj.project(at, 0.22), 6.0, 0.0, TAU, 8, WIRE.lightened(0.15), 1.0)
		TacticalMap.Terrain.JUNGLE:
			_draw_jungle(c, proj, p, g, n)
		TacticalMap.Terrain.PADDY:
			_draw_paddy(c, proj, p, g, n)
		TacticalMap.Terrain.TALL_GRASS:
			_draw_tall_grass(c, proj, p, g, n)


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
	var center := Vector2(p) + Vector2(0.5, 0.5)
	match map.get_object_kind(p):
		"tree" when _arid():
			c.draw_colored_polygon(ground_circle(proj, center + LIGHT * 1.5, 0.36, false), SHADOW)
			draw_shadow(c, proj, blob_poly(center, 0.06, p, 0.0), 1.0)
		"car":
			draw_shadow(c, proj, rect_poly(Rect2(Vector2(p), Vector2.ONE).grow(-0.14)), 0.5)
		"hesco":
			draw_shadow(c, proj, rect_poly(Rect2(Vector2(p), Vector2.ONE).grow(-0.06)), HESCO_HEIGHT)
		"jersey":
			draw_shadow(c, proj, rect_poly(Rect2(Vector2(p), Vector2.ONE).grow(-0.2)), 0.5)
		"tree" when _tropical():
			c.draw_colored_polygon(ground_circle(proj, center + LIGHT * 1.6, 0.62, false), SHADOW)
		"tree":
			c.draw_colored_polygon(ground_circle(proj, center + LIGHT * 1.2, 0.5, false), SHADOW)
		"palm":
			var crown := center + _palm_lean(p)
			draw_shadow(c, proj, blob_poly(center, 0.06, p, 0.0), PALM_HEIGHT)
			c.draw_colored_polygon(ground_circle(proj, crown + LIGHT * PALM_HEIGHT, 0.42, false), SHADOW)
		"bamboo":
			draw_shadow(c, proj, blob_poly(center, 0.26, p, 0.3), 1.2)
		"rice_sacks":
			draw_shadow(c, proj, rect_poly(Rect2(Vector2(p), Vector2.ONE).grow(-0.16)), 0.4)
		"rock":
			draw_shadow(c, proj, rect_poly(Rect2(Vector2(p), Vector2.ONE).grow(-0.12)), _rock_height(p))
		"oil_tank":
			draw_shadow(c, proj, rect_poly(Rect2(Vector2(p), Vector2.ONE).grow(-0.08)), 1.3)
		_:
			draw_shadow(c, proj, rect_poly(Rect2(Vector2(p), Vector2.ONE).grow(-0.2)), 0.45)


static func draw_edge_shadow(c: CanvasItem, proj: ViewProjection, map: TacticalMap, key: Vector3i) -> void:
	var kind := map.edge_kind(key)
	var height: float = {"wall": WALL_HEIGHT, "window": WALL_HEIGHT, "hedge": HEDGE_HEIGHT, "stone": LOW_WALL_HEIGHT,
		"dyke": DYKE_HEIGHT, "bamboo_wall": WALL_HEIGHT, "bamboo_window": WALL_HEIGHT, "mud_wall": WALL_HEIGHT,
		"mud_window": WALL_HEIGHT}.get(kind, 0.25)
	if kind == "dyke" and _arid():
		height = DITCH_BANK_HEIGHT
	var thickness: float = {"hedge": 0.1, "dyke": 0.15, "mud_wall": MUD_HALF_THICKNESS, "mud_window": MUD_HALF_THICKNESS}.get(kind, WALL_HALF_THICKNESS)
	draw_shadow(c, proj, _edge_rect(key, 0.0, 1.0, thickness), height)


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
	match map.get_object_kind(p):
		"tree" when _arid():
			_draw_poplar(c, proj, p, center, tint, alpha)
		"car":
			_draw_car(c, proj, p, center, tint, alpha)
		"hesco":
			_draw_hesco(c, proj, p, center, tint, alpha)
		"jersey":
			_draw_jersey(c, proj, p, center, tint, alpha)
		"wreck":
			pass  # The knocked-out tank itself is drawn by the view.
		"rock":
			_draw_rock(c, proj, p, center, ROCK[0].lerp(ROCK[1], noise(p, 3)).darkened(tint), alpha)
		"tree" when _tropical():
			_draw_jungle_tree(c, proj, p, center, tint, alpha)
		"tree":
			_draw_tree(c, proj, p, center, tint, alpha)
		"palm":
			_draw_palm(c, proj, p, center, tint, alpha)
		"bamboo":
			_draw_bamboo(c, proj, p, center, tint, alpha)
		"rice_sacks":
			_draw_rice_sacks(c, proj, p, center, BURLAP.darkened(tint), alpha)
		"sandbags":
			_draw_sandbags(c, proj, p, center, SANDBAG.darkened(tint), alpha)
		"hay":
			var color := HAY.darkened(tint)
			prism(c, proj, blob_poly(center, 0.34, p, 0.0), 0.0, 0.5, color, alpha)
			for r in [0.24, 0.14]:
				c.draw_polyline(ground_circle(proj, center, r, true, 0.5), Color(color.darkened(0.3), alpha), 1.0)
		"fuel":
			# A cluster of fuel drums with bands round them.
			for i in 3:
				var at := center + Vector2.from_angle(TAU * i / 3.0 + 0.6) * 0.17
				var color: Color = FUEL_DRUM[i].darkened(tint)
				var faces := prism(c, proj, blob_poly(at, 0.13, p, 0.0), 0.0, 0.45, color, alpha)
				for q: Array in faces:
					for t in [0.3, 0.7]:
						c.draw_line(q[0].lerp(q[3], t), q[1].lerp(q[2], t), Color(color.darkened(0.4), alpha), 1.0)
				c.draw_circle(proj.project(at + Vector2(0.04, -0.03), 0.45), 2.0, Color(color.darkened(0.5), alpha))
		"oil_tank":
			# A storage tank: banded steel cylinder with a domed roof and a ladder.
			var color := OIL_TANK.darkened(tint)
			var faces := prism(c, proj, blob_poly(center, 0.44, p, 0.0), 0.0, 1.25, color, alpha)
			for q: Array in faces:
				for t in [0.25, 0.5, 0.75]:
					c.draw_line(q[0].lerp(q[3], t), q[1].lerp(q[2], t), Color(color.darkened(0.3), alpha), 1.0)
			prism(c, proj, blob_poly(center, 0.3, p, 0.0), 1.25, 1.38, color.lightened(0.08), alpha)
			var ladder := center + Vector2(0.3, 0.32)
			c.draw_line(proj.project(ladder), proj.project(ladder, 1.25), Color(color.darkened(0.55), alpha), 1.5)
			c.draw_polyline(ground_circle(proj, center, 0.2, true, 1.385), Color(0.6, 0.1, 0.08, alpha), 2.0)
		"pew":
			var color := WOOD.darkened(tint)
			prism(c, proj, rect_poly(Rect2(center - Vector2(0.42, 0.14), Vector2(0.84, 0.28))), 0.0, 0.32, color, alpha)
			prism(c, proj, rect_poly(Rect2(center + Vector2(-0.42, 0.1), Vector2(0.84, 0.06))), 0.0, 0.62, color.darkened(0.1), alpha)
		_:
			_draw_crate(c, proj, Rect2(center - Vector2(0.31, 0.31), Vector2(0.62, 0.62)), 0.5, CRATE.darkened(tint), alpha)


## A boulder: a wide irregular base with a smaller, offset cap.
static func _draw_rock(c: CanvasItem, proj: ViewProjection, p: Vector2i, center: Vector2, color: Color, alpha: float) -> void:
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


static func _draw_tree(c: CanvasItem, proj: ViewProjection, p: Vector2i, center: Vector2, tint: float, alpha: float) -> void:
	prism(c, proj, blob_poly(center, 0.08, p, 0.2), 0.0, 0.8, TRUNK.darkened(tint), alpha)
	var puffs := []
	for i in 8:
		var offset := Vector2.from_angle(TAU * i / 8.0 + noise(p, i)) * 0.26 * noise(p, i + 20)
		puffs.append([center + offset, 0.9 + noise(p, i + 30) * 0.55, 9.0 + noise(p, i + 40) * 6.0])
	puffs.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	for i in puffs.size():
		var puff: Array = puffs[i]
		var color: Color = LEAVES[mini(2, int(i * 3.0 / puffs.size()))]
		c.draw_circle(proj.project(puff[0], puff[1]), puff[2], Color(color.darkened(tint), alpha))


static func _draw_sandbags(c: CanvasItem, proj: ViewProjection, p: Vector2i, center: Vector2, color: Color, alpha: float) -> void:
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
	match map.edge_kind(key):
		"dyke" when _arid():
			_draw_ditch(c, proj, key, tint, alpha)
		"mud_wall":
			_draw_mud_wall(c, proj, key, 0.0, 1.0, 0.0, WALL_HEIGHT, tint, alpha)
		"mud_window":
			# A mud wall with a small square opening under a wooden lintel.
			_draw_mud_wall(c, proj, key, 0.0, 1.0, 0.0, SILL_HEIGHT + 0.1, tint, alpha)
			_draw_mud_wall(c, proj, key, 0.0, 0.3, SILL_HEIGHT + 0.1, WALL_HEIGHT, tint, alpha)
			_draw_mud_wall(c, proj, key, 0.7, 1.0, SILL_HEIGHT + 0.1, WALL_HEIGHT, tint, alpha)
			_draw_mud_wall(c, proj, key, 0.0, 1.0, LINTEL_BASE - 0.04, WALL_HEIGHT, tint, alpha)
			prism(c, proj, _edge_rect(key, 0.26, 0.74, MUD_HALF_THICKNESS + 0.01), LINTEL_BASE - 0.08, LINTEL_BASE - 0.03, WOOD.darkened(tint), alpha)
		"wall":
			var color := MASONRY.darkened(tint)
			var faces := prism(c, proj, _edge_rect(key, 0.0, 1.0, WALL_HALF_THICKNESS), 0.0, WALL_HEIGHT, color, alpha)
			for q: Array in faces:
				c.draw_colored_polygon(PackedVector2Array([q[0], q[1], q[1].lerp(q[2], 0.08), q[0].lerp(q[3], 0.08)]), Color(color.darkened(0.45), alpha))
				for t in [0.35, 0.7]:
					c.draw_line(q[0].lerp(q[3], t), q[1].lerp(q[2], t), Color(color.darkened(0.18), alpha), 1.0)
		"window":
			var color := MASONRY.darkened(tint)
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
		"hedge":
			var p := Vector2i(key.x * 2 + key.z, key.y)
			var color: Color = HEDGE[0].darkened(tint)
			prism(c, proj, _edge_rect(key, 0.0, 1.0, 0.1), 0.0, HEDGE_HEIGHT * 0.85, color, alpha)
			var frame := _edge_frame(key)
			for i in 5:
				var t := (i + 0.5) / 5.0
				var at: Vector2 = frame[0] + frame[1] * t + frame[2] * (noise(p, i) - 0.5) * 0.15
				var leaf: Color = HEDGE[(i + key.x + key.y) % 3]
				c.draw_circle(proj.project(at, HEDGE_HEIGHT * (0.75 + noise(p, i + 10) * 0.2)), 8.0 + noise(p, i + 20) * 3.0, Color(leaf.darkened(tint), alpha))
		"stone":
			var color := STONE_WALL.darkened(tint)
			var faces := prism(c, proj, _edge_rect(key, 0.0, 1.0, 0.09), 0.0, LOW_WALL_HEIGHT, color, alpha)
			var line := Color(color.darkened(0.35), alpha)
			for q: Array in faces:
				c.draw_line(q[0].lerp(q[3], 0.5), q[1].lerp(q[2], 0.5), line, 1.0)
				for t in [0.25, 0.6, 0.85]:
					var bottom: Vector2 = q[0].lerp(q[1], t)
					var top: Vector2 = q[3].lerp(q[2], t)
					var shift := 0.5 if t > 0.5 else 0.0
					c.draw_line(bottom.lerp(top, shift), bottom.lerp(top, shift + 0.5), line, 1.0)
		"dyke":
			_draw_dyke(c, proj, key, tint, alpha)
		"bamboo_wall":
			_draw_bamboo_wall(c, proj, key, 0.0, 1.0, 0.0, WALL_HEIGHT, tint, alpha)
		"bamboo_window":
			# A bamboo wall with a window opening; a rolled-up mat blind hangs under the lintel.
			_draw_bamboo_wall(c, proj, key, 0.0, 1.0, 0.0, SILL_HEIGHT, tint, alpha)
			_draw_bamboo_wall(c, proj, key, 0.0, 0.12, SILL_HEIGHT, WALL_HEIGHT, tint, alpha)
			_draw_bamboo_wall(c, proj, key, 0.88, 1.0, SILL_HEIGHT, WALL_HEIGHT, tint, alpha)
			_draw_bamboo_wall(c, proj, key, 0.0, 1.0, LINTEL_BASE, WALL_HEIGHT, tint, alpha)
			var frame := _edge_frame(key)
			var a: Vector2 = frame[0] + frame[1] * 0.14
			var b: Vector2 = frame[0] + frame[1] * 0.86
			c.draw_line(proj.project(a, LINTEL_BASE - 0.04), proj.project(b, LINTEL_BASE - 0.04), Color(THATCH.darkened(tint + 0.15), alpha), 5.0)
			c.draw_line(proj.project(a, LINTEL_BASE - 0.06), proj.project(b, LINTEL_BASE - 0.06), Color(THATCH.darkened(tint + 0.4), alpha), 1.0)
		_:
			var color := WOOD.darkened(tint)
			for t in [0.0, 0.5, 1.0]:
				prism(c, proj, _edge_rect(key, t - 0.04, t + 0.04, 0.045), 0.0, 0.55, color.darkened(0.1), alpha)
			for rail: Array in [[0.14, 0.21], [0.34, 0.41]]:
				prism(c, proj, _edge_rect(key, 0.0, 1.0, 0.025), rail[0], rail[1], color, alpha)


## A drifting cloud of smoke over a tile.
static func draw_smoke(c: CanvasItem, proj: ViewProjection, p: Vector2i, time: float) -> void:
	var center := Vector2(p) + Vector2(0.5, 0.5)
	for i in 3:
		var drift := Vector2(sin(time * 0.6 + i * 2.1 + p.x), cos(time * 0.5 + i * 1.7 + p.y)) * 0.12
		var height := 0.3 + i * 0.35 + sin(time * 0.8 + i + p.y) * 0.05
		var shade := 0.72 + noise(p, i) * 0.12
		c.draw_circle(proj.project(center + drift, height), 20.0 - i * 3.0, Color(shade, shade, shade * 0.98, 0.55))


## Flames licking up from a burning tile, with embers.
static func draw_fire(c: CanvasItem, proj: ViewProjection, p: Vector2i, time: float) -> void:
	var center := Vector2(p) + Vector2(0.5, 0.5)
	c.draw_colored_polygon(ground_circle(proj, center, 0.42, false), Color(0.12, 0.06, 0.03, 0.55))
	for i in 5:
		var at := center + Vector2(noise(p, i * 3 + 1) - 0.5, noise(p, i * 3 + 2) - 0.5) * 0.6
		var flicker := 0.5 + 0.5 * sin(time * (8.0 + i) + i * 1.9 + p.x)
		var height := 0.25 + flicker * 0.3
		var color: Color = FLAME[(i + int(time * 6.0)) % 3]
		var base := proj.project(at)
		var tip := proj.project(at + Vector2(0.02, -0.02) * flicker, height)
		var side := Vector2(4.0 + flicker * 2.0, 0)
		c.draw_colored_polygon(PackedVector2Array([base - side, tip, base + side]), Color(color, 0.85))
	for i in 2:
		var t := fmod(time * 0.6 + noise(p, i + 9), 1.0)
		c.draw_circle(proj.project(center + Vector2(0.1 * i, 0.0), 0.5 + t * 0.9), 2.0 + t * 6.0, Color(0.15, 0.13, 0.12, 0.45 * (1.0 - t)))


## A spotted mine: the buried disc and a little warning sign.
static func draw_mine(c: CanvasItem, proj: ViewProjection, p: Vector2i) -> void:
	var center := Vector2(p) + Vector2(0.5, 0.5)
	c.draw_colored_polygon(ground_circle(proj, center, 0.18, false), MINE)
	c.draw_polyline(ground_circle(proj, center, 0.18), MINE.lightened(0.3), 1.0)
	var post := center + Vector2(-0.28, -0.28)
	c.draw_line(proj.project(post), proj.project(post, 0.4), WIRE_POST, 2.0)
	var top := proj.project(post, 0.4)
	c.draw_colored_polygon(PackedVector2Array([top + Vector2(-7, -9), top + Vector2(7, -9), top + Vector2(0, 2)]), MINE_SIGN)
	c.draw_line(top + Vector2(0, -7), top + Vector2(0, -3), Color(0.6, 0.1, 0.08), 1.5)


static func _rock_height(p: Vector2i) -> float:
	return 0.9 + noise(p, 7) * 0.3


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


# --- Vietnam ---

const PALM_HEIGHT := 1.75


## A pointed leaf from base to tip, `width` pixels across at its widest, with a pale midrib.
static func _leaf(c: CanvasItem, base: Vector2, tip: Vector2, width: float, color: Color) -> void:
	var along := tip - base
	if along.length() < 0.5:
		return
	var across := Vector2(-along.y, along.x).normalized() * width
	var mid := base + along * 0.42
	c.draw_colored_polygon(PackedVector2Array([base, mid + across, tip, mid - across]), color)
	c.draw_line(base, base.lerp(tip, 0.85), color.lightened(0.18), 0.8)


## Jungle: a dark floor packed with ferns and broad leaves at several heights, low enough that whoever
## stands in it still shows above it.
static func _draw_jungle(c: CanvasItem, proj: ViewProjection, p: Vector2i, g: Vector2, n: float) -> void:
	c.draw_colored_polygon(tile_poly(proj, p), JUNGLE_FLOOR[0].lerp(JUNGLE_FLOOR[1], n))
	var leaves := []
	# Fern fans low down.
	for i in 7:
		var at := g + Vector2(0.1, 0.1) + Vector2(noise(p, i * 2 + 61), noise(p, i * 2 + 62)) * 0.8
		var spin := noise(p, i + 70) * TAU
		for j in 6:
			var dir := Vector2.from_angle(spin + TAU * j / 6.0)
			leaves.append([proj.depth(at + dir * 0.1), at, at + dir * (0.2 + noise(p, i * 6 + j) * 0.08), 0.03, 0.18 + noise(p, j + 80) * 0.12,
				2.4, JUNGLE_LEAVES[(i + j) % 3]])
	# Big broad leaves standing up higher.
	for i in 6:
		var at := g + Vector2(0.12, 0.12) + Vector2(noise(p, i * 2 + 91), noise(p, i * 2 + 92)) * 0.76
		var dir := Vector2.from_angle(noise(p, i + 100) * TAU)
		leaves.append([proj.depth(at + dir * 0.12), at, at + dir * 0.28, 0.1, 0.4 + noise(p, i + 110) * 0.15, 6.5,
			JUNGLE_LEAVES[(i + 1) % 4]])
	# Vines and stems standing up through it.
	for i in 2:
		var at := g + Vector2(0.2, 0.2) + Vector2(noise(p, i + 120), noise(p, i + 122)) * 0.6
		leaves.append([proj.depth(at), at, at + Vector2(0.03, -0.02), 0.0, 0.6, 1.2, JUNGLE_TRUNK.darkened(0.3)])
	leaves.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for leaf: Array in leaves:
		var color: Color = leaf[6]
		_leaf(c, proj.project(leaf[1], leaf[3]), proj.project(leaf[2], leaf[4]), leaf[5], color)


## A flooded rice paddy: muddy water catching the sky, and rows of rice shoots mirrored in it.
static func _draw_paddy(c: CanvasItem, proj: ViewProjection, p: Vector2i, g: Vector2, n: float) -> void:
	c.draw_colored_polygon(tile_poly(proj, p), PADDY_WATER[0].lerp(PADDY_WATER[1], n))
	for i in 2:
		var at := g + Vector2(0.1 + noise(p, i + 5) * 0.4, 0.15 + noise(p, i + 7) * 0.7)
		c.draw_colored_polygon(ground_circle(proj, at + Vector2(0.15, 0.0), 0.12, false), Color(PADDY_MUD, 0.35))
	for i in 3:
		var at := g + Vector2(0.1 + noise(p, i + 11) * 0.5, 0.1 + noise(p, i + 13) * 0.8)
		c.draw_line(proj.project(at), proj.project(at + Vector2(0.3, 0.0)), Color(0.82, 0.9, 0.95, 0.22), 2.0)
	for r in 4:
		for k in 4:
			var at := g + Vector2((k + 0.5) / 4.0 + (noise(p, r * 4 + k + 20) - 0.5) * 0.08, (r + 0.5) / 4.0)
			var base := proj.project(at)
			for s in 3:
				var color: Color = RICE[(s + r + k) % 3]
				var off := Vector2(-0.03 + s * 0.03, 0.02 - s * 0.02)
				var tip := proj.project(at + off, 0.13 + noise(p, r * 12 + k * 3 + s) * 0.06)
				c.draw_line(base + (base - tip) * 0.6, base, Color(color, 0.22), 1.2)
				c.draw_line(base, tip, color, 1.3)


## A tall rainforest tree: a pale trunk with buttress roots and a broad, flat, dark canopy.
static func _draw_jungle_tree(c: CanvasItem, proj: ViewProjection, p: Vector2i, center: Vector2, tint: float, alpha: float) -> void:
	var trunk := JUNGLE_TRUNK.darkened(tint)
	for i in 3:
		var dir := Vector2.from_angle(TAU * i / 3.0 + noise(p, 3) * TAU)
		c.draw_line(proj.project(center + dir * 0.2), proj.project(center + dir * 0.04, 0.3), Color(trunk.darkened(0.15), alpha), 3.0)
	prism(c, proj, blob_poly(center, 0.08, p, 0.2), 0.0, 1.25, trunk, alpha)
	var puffs := []
	for i in 11:
		var offset := Vector2.from_angle(TAU * i / 11.0 + noise(p, i)) * 0.36 * (0.3 + 0.7 * noise(p, i + 20))
		puffs.append([center + offset, 1.25 + noise(p, i + 30) * 0.4, 10.0 + noise(p, i + 40) * 6.0])
	puffs.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	for i in puffs.size():
		var puff: Array = puffs[i]
		var color: Color = JUNGLE_CANOPY[mini(2, int(i * 3.0 / puffs.size()))]
		c.draw_circle(proj.project(puff[0], puff[1]), puff[2], Color(color.darkened(tint), alpha))


## Where the crown of a palm leans to, from its foot (grid).
static func _palm_lean(p: Vector2i) -> Vector2:
	return Vector2.from_angle(noise(p, 5) * TAU) * (0.18 + noise(p, 6) * 0.12)


## A coconut palm: a slender ringed trunk curving up to a crown of drooping fronds and a few coconuts.
static func _draw_palm(c: CanvasItem, proj: ViewProjection, p: Vector2i, center: Vector2, tint: float, alpha: float) -> void:
	var lean := _palm_lean(p)
	var trunk := PALM_TRUNK.darkened(tint)
	var points := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		points.append(proj.project(center + lean * t * t, PALM_HEIGHT * t))
	for i in 8:
		var w := lerpf(6.0, 3.6, i / 8.0)
		c.draw_line(points[i], points[i + 1], Color(trunk.darkened(0.5), alpha), w + 1.6)
	for i in 8:
		var w := lerpf(6.0, 3.6, i / 8.0)
		c.draw_line(points[i], points[i + 1], Color(trunk, alpha), w)
		c.draw_line(points[i].lerp(points[i + 1], 0.5) + Vector2(-w * 0.5, 0), points[i].lerp(points[i + 1], 0.5) + Vector2(w * 0.5, 0),
			Color(trunk.darkened(0.3), alpha), 1.0)
	var top := center + lean
	var fronds := []
	for i in 8:
		var dir := Vector2.from_angle(TAU * i / 8.0 + noise(p, i + 10) * 0.5)
		var reach := 0.5 + noise(p, i + 20) * 0.15
		fronds.append([proj.depth(top + dir * reach) + (0.0 if dir.y < 0 else 0.0), dir, reach, i])
	fronds.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var coconuts_drawn := false
	for frond: Array in fronds:
		var dir: Vector2 = frond[1]
		var reach: float = frond[2]
		var i: int = frond[3]
		if not coconuts_drawn and proj.depth(top + dir) > proj.depth(top):
			coconuts_drawn = true
			for k in 3:
				c.draw_circle(proj.project(top + Vector2.from_angle(TAU * k / 3.0) * 0.05, PALM_HEIGHT - 0.06), 3.0, Color(COCONUT.darkened(tint), alpha))
		var color: Color = FRONDS[i % 3].darkened(tint)
		# An arching frond: up a little, then drooping down to its tip, with leaflets along it.
		var spine := PackedVector2Array()
		for k in 6:
			var t := k / 5.0
			spine.append(proj.project(top + dir * reach * t, PALM_HEIGHT + 0.12 * sin(t * PI * 0.7) - 0.45 * t * t))
		for k in 5:
			var a := spine[k]
			var b := spine[k + 1]
			var across := Vector2(-(b - a).y, (b - a).x).normalized() * lerpf(6.0, 2.0, k / 5.0)
			c.draw_colored_polygon(PackedVector2Array([a + across, b + across * 0.7, b - across * 0.7, a - across]), Color(color, alpha))
		c.draw_polyline(spine, Color(color.lightened(0.2), alpha), 1.0)
	if not coconuts_drawn:
		for k in 3:
			c.draw_circle(proj.project(top + Vector2.from_angle(TAU * k / 3.0) * 0.05, PALM_HEIGHT - 0.06), 3.0, Color(COCONUT.darkened(tint), alpha))


## A clump of bamboo: tall jointed stalks leaning out from the root, with sprays of narrow leaves.
static func _draw_bamboo(c: CanvasItem, proj: ViewProjection, p: Vector2i, center: Vector2, tint: float, alpha: float) -> void:
	var stalks := []
	for i in 11:
		var at := center + Vector2.from_angle(TAU * i / 11.0 + noise(p, i) * 0.8) * 0.22 * sqrt(noise(p, i + 10))
		var lean := (at - center) * 0.9 + Vector2(noise(p, i + 20) - 0.5, noise(p, i + 30) - 0.5) * 0.15
		stalks.append([proj.depth(at), at, lean, 1.2 + noise(p, i + 40) * 0.6, i])
	stalks.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	c.draw_colored_polygon(ground_circle(proj, center, 0.24, false), Color(BAMBOO_LEAVES[0].darkened(0.5 + tint), alpha * 0.6))
	for stalk: Array in stalks:
		var at: Vector2 = stalk[1]
		var lean: Vector2 = stalk[2]
		var h: float = stalk[3]
		var i: int = stalk[4]
		var color := BAMBOO.darkened(tint + noise(p, i + 50) * 0.2)
		var base := proj.project(at)
		var tip := proj.project(at + lean, h)
		c.draw_line(base, tip, Color(color.darkened(0.45), alpha), 4.2)
		c.draw_line(base, tip, Color(color, alpha), 2.8)
		for k in range(1, int(h / 0.22)):
			var joint := base.lerp(tip, k * 0.22 / h)
			c.draw_line(joint + Vector2(-2, 0), joint + Vector2(2, 0), Color(color.darkened(0.4), alpha), 1.2)
		for k in 4:
			var from := base.lerp(tip, 0.6 + k * 0.1)
			var side := -1.0 if (k + i) % 2 == 0 else 1.0
			var leaf_tip := from + Vector2(side * (6.0 + noise(p, i * 4 + k) * 4.0), 3.0)
			_leaf(c, from, leaf_tip, 1.6, Color(BAMBOO_LEAVES[(k + i) % 2].darkened(tint), alpha))


## Burlap rice sacks stacked two high, tied at the ends.
static func _draw_rice_sacks(c: CanvasItem, proj: ViewProjection, p: Vector2i, center: Vector2, color: Color, alpha: float) -> void:
	var along_x := noise(p, 2) < 0.5
	var sacks := []
	for row in [-0.13, 0.13]:
		sacks.append([Vector2(0.0, row) if along_x else Vector2(row, 0.0), 0.0, 0.2])
	sacks.append([Vector2.ZERO, 0.2, 0.38])
	for i in sacks.size():
		var sack: Array = sacks[i]
		var size := Vector2(0.62, 0.24) if along_x else Vector2(0.24, 0.62)
		if i == 2:
			size = Vector2(0.24, 0.5) if along_x else Vector2(0.5, 0.24)
		var shade := color.darkened(noise(p, i + 5) * 0.12)
		var rect := Rect2(center + sack[0] - size * 0.5, size)
		var faces := prism(c, proj, rect_poly(rect), sack[1], sack[2], shade, alpha)
		for q: Array in faces:
			for t in [0.12, 0.88]:
				c.draw_line(q[0].lerp(q[1], t), q[3].lerp(q[2], t), Color(shade.darkened(0.35), alpha), 1.0)
		# A stencilled band across the top.
		var mid := rect.get_center()
		var across := Vector2(0, size.y * 0.5) if size.x > size.y else Vector2(size.x * 0.5, 0)
		c.draw_line(proj.project(mid - across, sack[2]), proj.project(mid + across, sack[2]), Color(0.45, 0.3, 0.2, alpha * 0.7), 2.0)


## A paddy dyke: a low earthen bank with grass along its top.
static func _draw_dyke(c: CanvasItem, proj: ViewProjection, key: Vector3i, tint: float, alpha: float) -> void:
	var color := DYKE_EARTH.darkened(tint)
	var faces := prism(c, proj, _edge_rect(key, -0.02, 1.02, 0.15), 0.0, DYKE_HEIGHT, color, alpha)
	for q: Array in faces:
		c.draw_line(q[0].lerp(q[3], 0.35), q[1].lerp(q[2], 0.4), Color(color.darkened(0.25), alpha), 1.0)
	var top := PackedVector2Array()
	for pt in _edge_rect(key, -0.02, 1.02, 0.13):
		top.append(proj.project(pt, DYKE_HEIGHT))
	c.draw_colored_polygon(top, Color(DYKE_GRASS[0].darkened(tint), alpha))
	var frame := _edge_frame(key)
	var p := Vector2i(key.x * 2 + key.z, key.y)
	for i in 9:
		var t := (i + 0.5) / 9.0
		var at: Vector2 = frame[0] + frame[1] * t + frame[2] * (noise(p, i) - 0.5) * 0.2
		c.draw_line(proj.project(at, DYKE_HEIGHT), proj.project(at + Vector2(0.02, -0.02), DYKE_HEIGHT + 0.1), Color(DYKE_GRASS[1].darkened(tint), alpha), 1.5)


## A wall of lashed bamboo poles (from..to along the edge, base..top in height), as on a hamlet hut.
static func _draw_bamboo_wall(c: CanvasItem, proj: ViewProjection, key: Vector3i, from: float, to: float, base: float, top: float, tint: float, alpha: float) -> void:
	var color := BAMBOO_WALL.darkened(tint)
	var faces := prism(c, proj, _edge_rect(key, from, to, 0.05), base, top, color, alpha)
	var poles := maxi(2, int((to - from) * 14.0))
	for q: Array in faces:
		var long: bool = (q[0] as Vector2).distance_to(q[1]) > 4.0
		if long:
			for i in range(1, poles):
				var t := float(i) / poles
				c.draw_line(q[0].lerp(q[1], t), q[3].lerp(q[2], t), Color(color.darkened(0.3), alpha), 1.0)
		# Lashings across the poles.
		for h in [0.2, 0.75]:
			var z := lerpf(base, top, h)
			if (z - base) > 0.06 and (top - z) > 0.06:
				var hb := (z - base) / (top - base)
				c.draw_line(q[0].lerp(q[3], hb), q[1].lerp(q[2], hb), Color(LEATHER_TIE.darkened(tint), alpha), 1.6)
	if top >= WALL_HEIGHT - 0.01:
		# Ragged thatch along the top.
		var frame := _edge_frame(key)
		var a: Vector2 = frame[0] + frame[1] * from
		var b: Vector2 = frame[0] + frame[1] * to
		c.draw_line(proj.project(a, top + 0.03), proj.project(b, top + 0.03), Color(THATCH.darkened(tint + 0.1), alpha), 4.0)


const LEATHER_TIE := Color("6a5534")


## A tunnel entrance: a small square hole with a wooden trapdoor propped open beside it, in leaf litter.
static func draw_tunnel(c: CanvasItem, proj: ViewProjection, p: Vector2i) -> void:
	var center := Vector2(p) + Vector2(0.5, 0.5)
	for i in 7:
		var at := center + Vector2(noise(p, i + 1) - 0.5, noise(p, i + 9) - 0.5) * 0.8
		var color: Color = [Color("6b5532"), Color("4f5f2c"), Color("7a6238")][i % 3]
		c.draw_colored_polygon(ground_circle(proj, at, 0.045, false), color)
	var hole := Rect2(center - Vector2(0.14, 0.17), Vector2(0.34, 0.34))
	c.draw_colored_polygon(tile_poly_rect(proj, hole.grow(0.05)), Color("5a4630"))
	c.draw_colored_polygon(tile_poly_rect(proj, hole), TUNNEL_HOLE)
	# The far inner wall catches a little light.
	c.draw_line(proj.project(hole.position), proj.project(Vector2(hole.end.x, hole.position.y)), Color("3a2c1e"), 2.0)
	# The lid, hinged on the hole's back edge and propped open, leaning back.
	var hinge_a := Vector2(hole.position.x - 0.04, hole.position.y)
	var hinge_b := Vector2(hole.position.x - 0.04, hole.end.y)
	var lift := Vector2(-0.12, -0.02)
	var lid := PackedVector2Array([proj.project(hinge_a), proj.project(hinge_b), proj.project(hinge_b + lift, 0.3), proj.project(hinge_a + lift, 0.3)])
	c.draw_colored_polygon(lid, WOOD.lightened(0.1))
	for t in [0.33, 0.66]:
		c.draw_line(lid[0].lerp(lid[1], t), lid[3].lerp(lid[2], t), WOOD.darkened(0.35), 1.0)
	c.draw_polyline(PackedVector2Array([lid[0], lid[1], lid[2], lid[3], lid[0]]), WOOD.darkened(0.5), 1.0)
	# Leaves and grass tied on top of the lid as camouflage.
	c.draw_circle(lid[0].lerp(lid[2], 0.5), 3.0, Color("4f6b2c"))
	c.draw_circle(lid[1].lerp(lid[3], 0.3), 2.0, Color("6b5532"))


## A ground polygon for a grid rectangle.
static func tile_poly_rect(proj: ViewProjection, rect: Rect2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for pt in rect_poly(rect):
		points.append(proj.project(pt))
	return points


## A spotted trap: "punji" (a pit of sharpened bamboo stakes), "ied" (a buried shell, found) or "mine".
static func draw_trap(c: CanvasItem, proj: ViewProjection, p: Vector2i, kind: String) -> void:
	if kind == "ied":
		_draw_ied(c, proj, p)
		return
	if kind != "punji":
		draw_mine(c, proj, p)
		return
	var center := Vector2(p) + Vector2(0.5, 0.5)
	var pit := Rect2(center - Vector2(0.27, 0.27), Vector2(0.54, 0.54))
	c.draw_colored_polygon(tile_poly_rect(proj, pit.grow(0.04)), Color("6b5236"))
	c.draw_colored_polygon(tile_poly_rect(proj, pit), Color("2a1f14"))
	# A broken mat of sticks that hid it, fallen in at one side.
	for i in 3:
		var y := pit.position.y + 0.05 + i * 0.04
		c.draw_line(proj.project(Vector2(pit.position.x - 0.03, y)), proj.project(Vector2(pit.position.x + 0.2, y + 0.02)), Color("8a7148"), 1.5)
	var stakes := []
	for i in 13:
		var at := pit.position + Vector2(0.08 + noise(p, i * 2 + 1) * 0.38, 0.08 + noise(p, i * 2 + 2) * 0.38)
		stakes.append([proj.depth(at), at, i])
	stakes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for stake: Array in stakes:
		var at: Vector2 = stake[1]
		var i: int = stake[2]
		var base := proj.project(at, -0.1)
		var tip := proj.project(at + Vector2(noise(p, i + 40) - 0.5, noise(p, i + 50) - 0.5) * 0.06, 0.08 + noise(p, i + 60) * 0.1)
		c.draw_line(base, tip, STAKE.darkened(0.45), 3.0)
		c.draw_line(base, tip, STAKE, 1.8)
		c.draw_circle(tip, 0.8, STAKE.lightened(0.3))


## Elephant grass: tall pale blades bending every way, some with feathery plumes.
static func _draw_tall_grass(c: CanvasItem, proj: ViewProjection, p: Vector2i, g: Vector2, n: float) -> void:
	c.draw_colored_polygon(tile_poly(proj, p), ELEPHANT_GRASS_GROUND[0].lerp(ELEPHANT_GRASS_GROUND[1], n))
	var blades := []
	for i in 22:
		var at := g + Vector2(0.04, 0.04) + Vector2(noise(p, i * 2 + 1), noise(p, i * 2 + 2)) * 0.92
		blades.append([proj.depth(at), at, i])
	blades.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for blade: Array in blades:
		var at: Vector2 = blade[1]
		var i: int = blade[2]
		var lean := Vector2.from_angle(noise(p, i + 80) * TAU) * (0.06 + noise(p, i + 90) * 0.1)
		var h := 0.6 + noise(p, i + 40) * 0.3
		var color: Color = ELEPHANT_GRASS[i % 4]
		var line := PackedVector2Array([proj.project(at), proj.project(at + lean * 0.25, h * 0.55), proj.project(at + lean, h)])
		c.draw_polyline(line, color.darkened(0.15), 1.7)
		if i % 5 == 0:
			c.draw_line(line[2], line[2] + (line[2] - line[1]).normalized() * 5.0, PLUME, 2.4)


# --- Afghanistan and Iraq ---

## Draws the ground of an arid tile; returns false for terrain drawn as everywhere else.
static func _draw_arid_tile(c: CanvasItem, proj: ViewProjection, map: TacticalMap, p: Vector2i, g: Vector2, n: float) -> bool:
	match map.get_terrain(p):
		TacticalMap.Terrain.FLOOR:
			# Dusty tan ground with sparse dry tufts and pebbles.
			c.draw_colored_polygon(tile_poly(proj, p), DUST[0].lerp(DUST[1], n))
			for i in 4:
				var at := g + Vector2(0.1, 0.1) + Vector2(noise(p, i * 2 + 1), noise(p, i * 2 + 2)) * 0.8
				for j in 3:
					var lean := Vector2(-0.04 + j * 0.04, -0.03)
					c.draw_line(proj.project(at), proj.project(at + lean, 0.08), DRY_TUFT[(i + j) % 3], 1.3)
			for i in 4:
				var at := g + Vector2(noise(p, i + 13), noise(p, i + 17)) * 0.9 + Vector2(0.05, 0.05)
				c.draw_circle(proj.project(at), 1.4, PEBBLE.darkened(noise(p, i + 21) * 0.2))
		TacticalMap.Terrain.ROUGH:
			# Stony ground: scattered stones and a thorny shrub.
			c.draw_colored_polygon(tile_poly(proj, p), STONY[0].lerp(STONY[1], n))
			for i in 6:
				var at := g + Vector2(0.12, 0.12) + Vector2(noise(p, i * 2 + 11), noise(p, i * 2 + 12)) * 0.76
				var size := 0.04 + noise(p, i + 30) * 0.05
				var stone := PackedVector2Array([
					proj.project(at + Vector2(-size, 0)), proj.project(at + Vector2(0, -size), size * 0.8),
					proj.project(at + Vector2(size, 0)), proj.project(at + Vector2(0, size)),
				])
				c.draw_colored_polygon(stone, STONE.darkened(0.1 + noise(p, i + 20) * 0.3))
			var bush := g + Vector2(0.3, 0.3) + Vector2(noise(p, 41), noise(p, 42)) * 0.4
			for j in 5:
				var dir := Vector2.from_angle(TAU * j / 5.0 + n * 3.0)
				c.draw_line(proj.project(bush), proj.project(bush + dir * 0.1, 0.12), DRY_TUFT[j % 3].darkened(0.15), 1.4)
		TacticalMap.Terrain.ROAD:
			# Grey-tan dirt or worn asphalt with ruts and potholes.
			c.draw_colored_polygon(tile_poly(proj, p), GREY_ROAD[0].lerp(GREY_ROAD[1], n))
			var along_x := map.get_terrain(p + Vector2i(1, 0)) == TacticalMap.Terrain.ROAD or map.get_terrain(p - Vector2i(1, 0)) == TacticalMap.Terrain.ROAD
			for t in [0.3, 0.7]:
				var a := g + (Vector2(0, t) if along_x else Vector2(t, 0))
				var b := a + (Vector2(1, 0) if along_x else Vector2(0, 1))
				c.draw_line(proj.project(a), proj.project(b), GREY_RUT, 2.0)
			if n > 0.65:
				var at := g + Vector2(0.25 + noise(p, 3) * 0.5, 0.25 + noise(p, 4) * 0.5)
				c.draw_colored_polygon(ground_circle(proj, at, 0.08, false), GREY_RUT.darkened(0.2))
			for i in 3:
				var at := g + Vector2(noise(p, i + 3), noise(p, i + 9)) * 0.9 + Vector2(0.05, 0.05)
				c.draw_circle(proj.project(at), 1.4, GREY_ROAD[0].darkened(0.25))
		TacticalMap.Terrain.WHEAT:
			# Green-gold wheat, with poppies flowering here and there.
			c.draw_colored_polygon(tile_poly(proj, p), GREEN_WHEAT[0].lerp(GREEN_WHEAT[1], n))
			for i in 12:
				var at := g + Vector2(0.06, 0.06) + Vector2(noise(p, i * 2 + 1), noise(p, i * 2 + 2)) * 0.88
				var top := proj.project(at + Vector2(0.02, -0.02), 0.32 + noise(p, i + 40) * 0.1)
				var color: Color = GREEN_STALKS[i % 3]
				c.draw_line(proj.project(at), top, color.darkened(0.25), 1.2)
				if noise(p, i + 60) > 0.75:
					c.draw_circle(top, 2.0, POPPY[i % 3])
				else:
					c.draw_circle(top, 1.5, color)
		TacticalMap.Terrain.TRAMPLED:
			c.draw_colored_polygon(tile_poly(proj, p), FLAT_WHEAT[0].lerp(DUST[1], 0.3 + n * 0.2))
			for i in 10:
				var at := g + Vector2(0.08, 0.08) + Vector2(noise(p, i * 2 + 1), noise(p, i * 2 + 2)) * 0.84
				var lie := Vector2.from_angle(noise(p, i + 50) * TAU) * 0.16
				c.draw_line(proj.project(at), proj.project(at + lie, 0.02), GREEN_STALKS[i % 3].darkened(0.2), 1.4)
		TacticalMap.Terrain.INDOOR:
			# Packed earth floors, some with a rug, and cracks.
			c.draw_colored_polygon(tile_poly(proj, p), EARTH[0].lerp(EARTH[1], n))
			if n > 0.72:
				var color: Color = RUG[int(noise(p, 7) * 3.0) % 3]
				var lo := Vector2(0.15, 0.2)
				var hi := Vector2(0.85, 0.8)
				var rug := PackedVector2Array([proj.project(g + lo), proj.project(g + Vector2(hi.x, lo.y)), proj.project(g + hi), proj.project(g + Vector2(lo.x, hi.y))])
				c.draw_colored_polygon(rug, color)
				var inner := PackedVector2Array([proj.project(g + lo + Vector2(0.07, 0.07)), proj.project(g + Vector2(hi.x - 0.07, lo.y + 0.07)),
					proj.project(g + hi - Vector2(0.07, 0.07)), proj.project(g + Vector2(lo.x + 0.07, hi.y - 0.07)), proj.project(g + lo + Vector2(0.07, 0.07))])
				c.draw_polyline(inner, Color("d8c08a"), 1.0)
				c.draw_circle(proj.project(g + Vector2(0.5, 0.5)), 2.5, Color("d8c08a"))
			else:
				var a := g + Vector2(0.2 + noise(p, 3) * 0.3, 0.2)
				c.draw_polyline(PackedVector2Array([proj.project(a), proj.project(a + Vector2(0.15, 0.2)), proj.project(a + Vector2(0.1, 0.45))]), EARTH[0].darkened(0.25), 1.0)
		_:
			return false
	return true


## A poplar: a pale trunk and a tall, narrow column of leaves.
static func _draw_poplar(c: CanvasItem, proj: ViewProjection, p: Vector2i, center: Vector2, tint: float, alpha: float) -> void:
	prism(c, proj, blob_poly(center, 0.06, p, 0.2), 0.0, 0.7, POPLAR_TRUNK.darkened(tint), alpha)
	for i in 12:
		var t := i / 11.0
		var h := 0.6 + t * 1.3
		var width := sin(PI * (0.15 + t * 0.85)) * 0.13 + 0.04
		var offset := Vector2(noise(p, i) - 0.5, noise(p, i + 20) - 0.5) * width
		var color: Color = POPLAR_LEAVES[(i + int(noise(p, i + 30) * 2.0)) % 3]
		c.draw_circle(proj.project(center + offset, h), 6.0 + width * 30.0, Color(color.darkened(tint), alpha))


## A burnt-out sedan: rusted, blackened body, the glass gone, sitting on bare rims.
static func _draw_car(c: CanvasItem, proj: ViewProjection, p: Vector2i, center: Vector2, tint: float, alpha: float) -> void:
	var along := Vector2(1, 0).rotated(round(noise(p, 2) * 3.0) * PI * 0.5 + (noise(p, 3) - 0.5) * 0.5)
	var across := Vector2(-along.y, along.x)
	var box := func(back: float, front: float, half: float) -> PackedVector2Array:
		return PackedVector2Array([center + along * back - across * half, center + along * front - across * half,
			center + along * front + across * half, center + along * back + across * half])
	var body := CAR_BURNT.darkened(tint)
	for x in [-0.27, 0.27]:
		for side in [-0.21, 0.21]:
			c.draw_colored_polygon(ground_circle(proj, center + along * x + across * side, 0.07, false, 0.04), Color(Color("2a2420").darkened(tint), alpha))
	var faces := prism(c, proj, box.call(-0.42, 0.42, 0.21), 0.08, 0.28, body, alpha)
	for q: Array in faces:
		# Rust streaks where the paint burnt off, and the line of the doors.
		for i in 2:
			var u := 0.15 + noise(p, i + 10) * 0.6
			c.draw_colored_polygon(PackedVector2Array([_on_face(q, u, 0.3), _on_face(q, u + 0.16, 0.25), _on_face(q, u + 0.14, 0.8),
				_on_face(q, u + 0.02, 0.75)]), Color(RUST.darkened(tint + 0.1), alpha * 0.75))
		c.draw_line(_on_face(q, 0.5, 0.0), _on_face(q, 0.5, 1.0), Color(body.darkened(0.4), alpha), 1.0)
	var cabin := prism(c, proj, box.call(-0.2, 0.14, 0.18), 0.28, 0.46, body.darkened(0.15), alpha)
	for q: Array in cabin:
		var hole := PackedVector2Array([_on_face(q, 0.12, 0.15), _on_face(q, 0.88, 0.15), _on_face(q, 0.88, 0.85), _on_face(q, 0.12, 0.85)])
		c.draw_colored_polygon(hole, Color(0.08, 0.07, 0.06, alpha))
	var bonnet: PackedVector2Array = box.call(0.18, 0.4, 0.15)
	var patch := PackedVector2Array()
	for pt in bonnet:
		patch.append(proj.project(pt, 0.285))
	c.draw_colored_polygon(patch, Color(RUST.darkened(tint + 0.15), alpha * 0.7))


## A HESCO bastion: a wire-mesh basket lined with fabric and filled with sand.
static func _draw_hesco(c: CanvasItem, proj: ViewProjection, p: Vector2i, center: Vector2, tint: float, alpha: float) -> void:
	var rect := Rect2(center - Vector2(0.44, 0.44), Vector2(0.88, 0.88))
	var color := HESCO_SAND.darkened(tint)
	var faces := prism(c, proj, rect_poly(rect), 0.0, HESCO_HEIGHT, color, alpha)
	var mesh := Color(HESCO_MESH.darkened(tint), alpha * 0.8)
	for q: Array in faces:
		for i in range(1, 6):
			var t := i / 6.0
			c.draw_line(q[0].lerp(q[1], t), q[3].lerp(q[2], t), mesh, 1.0)
		for t in [0.25, 0.5, 0.75]:
			c.draw_line(q[0].lerp(q[3], t), q[1].lerp(q[2], t), mesh, 1.0)
		c.draw_line(q[0].lerp(q[1], 0.5), q[3].lerp(q[2], 0.5), Color(HESCO_MESH.darkened(tint + 0.2), alpha), 1.6)
	# The sand inside, a little below the rim, and the seam between the two cells.
	var top := PackedVector2Array()
	for pt in rect_poly(rect.grow(-0.04)):
		top.append(proj.project(pt, HESCO_HEIGHT - 0.03))
	c.draw_colored_polygon(top, Color(color.darkened(0.12), alpha))
	c.draw_line(proj.project(Vector2(rect.get_center().x, rect.position.y), HESCO_HEIGHT), proj.project(Vector2(rect.get_center().x, rect.end.y), HESCO_HEIGHT), mesh, 1.6)


## A concrete jersey barrier: a wide foot and a tall narrow top.
static func _draw_jersey(c: CanvasItem, proj: ViewProjection, p: Vector2i, center: Vector2, tint: float, alpha: float) -> void:
	var along_x := noise(p, 2) < 0.5
	var size := func(length: float, width: float) -> Rect2:
		var extent := Vector2(length, width) if along_x else Vector2(width, length)
		return Rect2(center - extent * 0.5, extent)
	var color := CONCRETE.darkened(tint + noise(p, 5) * 0.08)
	prism(c, proj, rect_poly(size.call(0.86, 0.3)), 0.0, 0.12, color.darkened(0.05), alpha)
	prism(c, proj, rect_poly(size.call(0.86, 0.2)), 0.12, 0.24, color, alpha)
	var faces := prism(c, proj, rect_poly(size.call(0.86, 0.12)), 0.24, 0.5, color.lightened(0.04), alpha)
	for q: Array in faces:
		c.draw_line(q[0].lerp(q[1], 0.5), q[3].lerp(q[2], 0.5), Color(color.darkened(0.3), alpha), 1.0)
		c.draw_circle(q[0].lerp(q[2], 0.4), 1.5, Color(color.darkened(0.35), alpha))


## A mud-brick compound wall (from..to along the edge, base..top in height) with a rounded top and patches.
static func _draw_mud_wall(c: CanvasItem, proj: ViewProjection, key: Vector3i, from: float, to: float, base: float, top: float, tint: float, alpha: float) -> void:
	var color := MUD_BRICK.darkened(tint)
	var rounded := top >= WALL_HEIGHT - 0.01
	var faces := prism(c, proj, _edge_rect(key, from, to, MUD_HALF_THICKNESS), base, top - (0.05 if rounded else 0.0), color, alpha)
	var p := Vector2i(key.x * 2 + key.z, key.y)
	for i in faces.size():
		var q: Array = faces[i]
		for t in [0.3, 0.62]:
			var h := (lerpf(0.0, WALL_HEIGHT, t) - base) / maxf(0.01, top - base)
			if h > 0.05 and h < 0.95:
				c.draw_line(q[0].lerp(q[3], h), q[1].lerp(q[2], h), Color(color.darkened(0.12), alpha * 0.7), 1.0)
		if noise(p, i + 3) > 0.5 and (q[0] as Vector2).distance_to(q[1]) > 10.0:
			# A patch of fresher mud plaster.
			var u := 0.2 + noise(p, i + 5) * 0.5
			var v := 0.2 + noise(p, i + 6) * 0.4
			c.draw_colored_polygon(PackedVector2Array([_on_face(q, u, v), _on_face(q, u + 0.18, v), _on_face(q, u + 0.16, v + 0.2),
				_on_face(q, u + 0.02, v + 0.22)]), Color(color.lightened(0.06), alpha * 0.7))
	if rounded:
		prism(c, proj, _edge_rect(key, from, to, MUD_HALF_THICKNESS * 0.75), top - 0.05, top - 0.01, color.lightened(0.04), alpha)
		prism(c, proj, _edge_rect(key, from, to, MUD_HALF_THICKNESS * 0.4), top - 0.01, top + 0.02, color.lightened(0.08), alpha)


## An irrigation ditch: a low earth bank with a strip of muddy water along one side and weeds on top.
static func _draw_ditch(c: CanvasItem, proj: ViewProjection, key: Vector3i, tint: float, alpha: float) -> void:
	var frame := _edge_frame(key)
	var start: Vector2 = frame[0]
	var along: Vector2 = frame[1]
	var across: Vector2 = frame[2]
	var water := PackedVector2Array([proj.project(start + across * 0.12), proj.project(start + along + across * 0.12),
		proj.project(start + along + across * 0.3), proj.project(start + across * 0.3)])
	c.draw_colored_polygon(water, Color(DITCH_WATER.darkened(tint), alpha))
	c.draw_line(proj.project(start + across * 0.2), proj.project(start + along + across * 0.2), Color(0.85, 0.9, 0.9, 0.25 * alpha), 1.0)
	var color := DITCH_EARTH.darkened(tint)
	prism(c, proj, _edge_rect(key, -0.02, 1.02, 0.11), 0.0, DITCH_BANK_HEIGHT, color, alpha)
	var p := Vector2i(key.x * 2 + key.z, key.y)
	for i in 7:
		var t := (i + 0.5) / 7.0
		var at := start + along * t + across * (noise(p, i) - 0.5) * 0.15
		c.draw_line(proj.project(at, DITCH_BANK_HEIGHT), proj.project(at + Vector2(0.02, -0.02), DITCH_BANK_HEIGHT + 0.09), Color(DRY_TUFT[i % 3].darkened(tint), alpha), 1.4)


## A found IED: a patch of disturbed earth, the nose of a buried shell and a wire running off.
static func _draw_ied(c: CanvasItem, proj: ViewProjection, p: Vector2i) -> void:
	var center := Vector2(p) + Vector2(0.5, 0.5)
	c.draw_colored_polygon(blob_poly_projected(proj, center, 0.3, p), Color("6e5a40"))
	for i in 6:
		var at := center + Vector2(noise(p, i + 1) - 0.5, noise(p, i + 9) - 0.5) * 0.5
		c.draw_circle(proj.project(at, 0.01), 2.0, Color("5a4932"))
	# The shell nose, poking up at an angle.
	var base := proj.project(center + Vector2(-0.04, 0.02))
	var tip := proj.project(center + Vector2(0.06, -0.06), 0.1)
	c.draw_line(base, tip, Color(0.08, 0.08, 0.07), 7.0)
	c.draw_line(base, tip, IED_SHELL, 5.0)
	c.draw_circle(tip, 2.5, IED_SHELL.lightened(0.2))
	# The command wire snaking away.
	var wire := PackedVector2Array()
	for i in 6:
		var t := i / 5.0
		wire.append(proj.project(center + Vector2(-0.05 - t * 0.4, 0.03 + sin(t * 7.0) * 0.06)))
	c.draw_polyline(wire, Color(0.85, 0.2, 0.15), 1.2)


## An irregular ground patch, projected.
static func blob_poly_projected(proj: ViewProjection, center: Vector2, radius: float, p: Vector2i) -> PackedVector2Array:
	var points := PackedVector2Array()
	for pt in blob_poly(center, radius, p, 0.5):
		points.append(proj.project(pt))
	return points


## A point on a prism face quad [bottom a, bottom b, top b, top a]: u along it, v up it.
static func _on_face(q: Array, u: float, v: float) -> Vector2:
	var bottom: Vector2 = (q[0] as Vector2).lerp(q[1], u)
	var top: Vector2 = (q[3] as Vector2).lerp(q[2], u)
	return bottom.lerp(top, v)
