class_name VehiclePainter
extends RefCounted
## Procedural tanks: tracks, hull, turret and gun as lit prisms in the tank's own frame (forward, right),
## projected with the view so they turn and rotate with the camera. A Sherman for the Allies with a white
## star; a Panzer IV for Germany with its boxy turret and a Balkenkreuz. Knocked-out tanks burn.
##
## Model "m113" is the turretless M113 armoured carrier, "mrap" a wheeled mine-resistant truck. draw_helicopter draws a UH-1 in flight.
##
## Pose keys used: facing (Vector2, grid), death (0..1), flash (0..1), time (seconds).

const TRACKS := Color("2c2b27")
const GUN := Color("2a2d31")
const WRECK := Color("2f2924")
const STAR := Color("e8e6dc")
## Tanks are drawn a bit larger than their tile so they read as tanks next to soldiers.
const SCALE := 1.3
const OLIVE_DRAB := Color("4b5132")
const HELI_GLASS := Color("6f8a96")
const ROTOR := Color("1c1d1c")


static func draw(c: CanvasItem, proj: ViewProjection, g: Vector2, unit: Unit, pose: Dictionary) -> void:
	var facing: Vector2 = pose["facing"]
	var right := Vector2(-facing.y, facing.x)
	# Brewing up: the hull blackens, and the turret is blown up off its ring and comes down askew.
	var death: float = pose["death"]
	var wrecked: bool = death >= 1.0
	var flash: float = pose["flash"]
	var look: Dictionary = Theatres.get_theatre(unit.theatre).faction(unit.team)["vehicle"]
	var hull: Color = (look["hull"] as Color).lerp(WRECK, death)
	var tracks := TRACKS.lerp(TRACKS.darkened(0.3), death)
	if flash > 0.0:
		hull = hull.lerp(Color.WHITE, flash)
	if unit.def.get("model", "") == "m113":
		_draw_m113(c, proj, g, facing, hull, tracks, look.get("marking", "none") == "star", pose)
		return
	if unit.def.get("model", "") == "mrap":
		_draw_mrap(c, proj, g, facing, hull, pose)
		return
	# The Panzer IV's boxy turret and long gun with its muzzle brake; otherwise the Sherman's round turret.
	var german: bool = unit.def.get("model", "") == "panzer4"
	var turret_turn := 0.5 * minf(1.0, death * 1.5)
	var turret_lift := sin(clampf(death / 0.7, 0.0, 1.0) * PI) * 0.45
	var turret_facing := facing.rotated(turret_turn)
	var turret_right := Vector2(-turret_facing.y, turret_facing.x)

	var k := SCALE
	var parts := [
		[_box(g, facing * k, right * k, -0.46, 0.46, 0.24, 0.4), 0.0, 0.26 * k, tracks],
		[_box(g, facing * k, right * k, -0.46, 0.46, -0.4, -0.24), 0.0, 0.26 * k, tracks],
		[_box(g, facing * k, right * k, -0.42, 0.44, -0.27, 0.27), 0.1 * k, 0.4 * k, hull],
	]
	var turret := _box(g, turret_facing * k, turret_right * k, -0.2, 0.15, -0.18, 0.18) if german else _octagon(g + facing * -0.03 * k, turret_facing, 0.2 * k)
	parts.append([turret, (0.4 + turret_lift) * k, (0.62 + turret_lift) * k, hull.lightened(0.05)])
	parts.sort_custom(func(a: Array, b: Array) -> bool: return _depth(proj, a[0], a[1]) < _depth(proj, b[0], b[1]))

	# The gun is drawn before the turret when it points away from the viewer, after it otherwise.
	var gun_from := proj.project(g + turret_facing * 0.08 * k, (0.52 + turret_lift) * k)
	var gun_to := proj.project(g + turret_facing * (0.66 if german else 0.62) * k, (0.54 + turret_lift - 0.12 * death) * k)
	var gun_toward_viewer := proj.depth(g + turret_facing) > proj.depth(g)
	for part: Array in parts:
		if part == parts.back() and not gun_toward_viewer:
			_gun(c, gun_from, gun_to, german, wrecked)
		var faces := TerrainPainter.prism(c, proj, part[0], part[1], part[2], part[3])
		if part[3] == tracks:
			for q: Array in faces:
				for t in [0.2, 0.4, 0.6, 0.8]:
					c.draw_line(q[0].lerp(q[1], t), q[3].lerp(q[2], t), tracks.lightened(0.15), 1.0)
	if gun_toward_viewer:
		_gun(c, gun_from, gun_to, german, wrecked)
	if death < 0.5:
		_marking(c, proj, g + turret_facing * -0.03 * k, turret_facing, german)
	if pose["death"] > 0.0:
		_burn(c, proj, g, pose["time"])


static func _gun(c: CanvasItem, from: Vector2, to: Vector2, german: bool, wrecked: bool) -> void:
	var color := WRECK.darkened(0.2) if wrecked else GUN
	c.draw_line(from, to, Color(0.05, 0.05, 0.06), 7.0)
	c.draw_line(from, to, color, 4.5)
	if german:
		c.draw_circle(to, 3.5, color)


## The white Allied star, or a Balkenkreuz, painted on the turret roof.
static func _marking(c: CanvasItem, proj: ViewProjection, center: Vector2, facing: Vector2, german: bool) -> void:
	var right := Vector2(-facing.y, facing.x) * SCALE
	var top := 0.621 * SCALE
	facing *= SCALE
	if german:
		for arm: Array in [[facing, right], [right, facing]]:
			var along: Vector2 = arm[0]
			var across: Vector2 = arm[1]
			var bar := PackedVector2Array([
				proj.project(center - along * 0.1 - across * 0.03, top), proj.project(center + along * 0.1 - across * 0.03, top),
				proj.project(center + along * 0.1 + across * 0.03, top), proj.project(center - along * 0.1 + across * 0.03, top),
			])
			c.draw_colored_polygon(bar, Color(0.08, 0.08, 0.08))
		return
	var star := PackedVector2Array()
	for i in 10:
		var radius := 0.11 if i % 2 == 0 else 0.045
		star.append(proj.project(center + facing.rotated(TAU * i / 10.0) * radius, top))
	c.draw_colored_polygon(star, STAR)


## Flames and smoke rising from a knocked-out tank.
static func _burn(c: CanvasItem, proj: ViewProjection, g: Vector2, time: float) -> void:
	for i in 5:
		var t := fmod(time * 0.5 + i * 0.2, 1.0)
		var drift := Vector2(sin(time + i), cos(time * 0.7 + i)) * 0.1 * t
		c.draw_circle(proj.project(g + drift, 0.7 + t * 1.6), 8.0 + 14.0 * t, Color(0.2, 0.19, 0.18, 0.55 * (1.0 - t)))
	for i in 3:
		var flicker := 0.5 + 0.5 * sin(time * 9.0 + i * 2.0)
		c.draw_circle(proj.project(g + Vector2(0.08 * (i - 1), 0.05 * i), 0.66 + 0.1 * flicker), 4.0 + 3.0 * flicker, Color(1.0, 0.55 + 0.25 * flicker, 0.15, 0.85))


## A rectangle in the tank's frame, as a grid footprint.
static func _box(g: Vector2, facing: Vector2, right: Vector2, back: float, front: float, left: float, right_edge: float) -> PackedVector2Array:
	return PackedVector2Array([
		g + facing * back + right * left, g + facing * front + right * left,
		g + facing * front + right * right_edge, g + facing * back + right * right_edge,
	])


static func _octagon(center: Vector2, facing: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 8:
		points.append(center + facing.rotated(TAU * (i + 0.5) / 8.0) * radius)
	return points


static func _depth(proj: ViewProjection, footprint: PackedVector2Array, base: float) -> float:
	var center := Vector2.ZERO
	for p in footprint:
		center += p
	center /= footprint.size()
	return proj.depth(center) + base * 0.6 if proj.isometric else base


# --- M113 ---

## The M113: a tall aluminium box on full-length tracks with a sloping glacis at the front, no turret, and
## the commander's .50 cal on a pintle behind a small shield.
static func _draw_m113(c: CanvasItem, proj: ViewProjection, g: Vector2, facing: Vector2, hull: Color, tracks: Color, star: bool, pose: Dictionary) -> void:
	var k := SCALE
	var right := Vector2(-facing.y, facing.x)
	var death: float = pose["death"]
	var f := facing * k
	var r := right * k
	var top := 0.56 * k
	var nose := 0.24 * k
	var at := func(x: float, y: float) -> Vector2: return g + f * x + r * y
	var parts := [
		[_box(g, f, r, -0.47, 0.47, 0.22, 0.38), 0.0, 0.22 * k, tracks],
		[_box(g, f, r, -0.47, 0.47, -0.38, -0.22), 0.0, 0.22 * k, tracks],
	]
	parts.sort_custom(func(a: Array, b: Array) -> bool: return _depth(proj, a[0], a[1]) < _depth(proj, b[0], b[1]))
	for part: Array in parts:
		var faces := TerrainPainter.prism(c, proj, part[0], part[1], part[2], part[3])
		for q: Array in faces:
			for t in [0.15, 0.3, 0.45, 0.6, 0.75, 0.9]:
				c.draw_line(q[0].lerp(q[1], t), q[3].lerp(q[2], t), tracks.lightened(0.15), 1.0)
	# Side-on counts as facing the viewer: the glacis then shows beside the hull rather than behind it.
	var front_toward_viewer := proj.depth(g + facing) >= proj.depth(g) - 0.01
	# The glacis: a quad sloping from the roof's front edge down to the nose, with its side triangles.
	var glacis := PackedVector2Array([proj.project(at.call(0.24, -0.36), top), proj.project(at.call(0.24, 0.36), top),
		proj.project(at.call(0.47, 0.36), nose), proj.project(at.call(0.47, -0.36), nose)])
	var glacis_color := hull.lightened(0.05) if front_toward_viewer else hull.darkened(0.2)
	var draw_glacis := func() -> void:
		for side: float in [-0.36, 0.36]:
			if proj.depth(g + right * signf(side)) > proj.depth(g) + 0.01:
				var tri := PackedVector2Array([proj.project(at.call(0.24, side), top), proj.project(at.call(0.47, side), nose),
					proj.project(at.call(0.24, side), nose)])
				c.draw_colored_polygon(tri, hull.darkened(0.25))
		if absf((glacis[1] - glacis[0]).cross(glacis[3] - glacis[0])) > 1.0:
			c.draw_colored_polygon(glacis, glacis_color)
		c.draw_polyline(PackedVector2Array([glacis[0], glacis[1], glacis[2], glacis[3], glacis[0]]), hull.darkened(0.45), 1.0)
		# The trim vane folded down across the glacis.
		c.draw_line(glacis[0].lerp(glacis[3], 0.45), glacis[1].lerp(glacis[2], 0.45), hull.darkened(0.3), 2.0)
	if not front_toward_viewer:
		draw_glacis.call()
	TerrainPainter.prism(c, proj, _box(g, f, r, 0.24, 0.47, -0.36, 0.36), 0.12 * k, nose, hull.darkened(0.05))
	var faces := TerrainPainter.prism(c, proj, _box(g, f, r, -0.47, 0.24, -0.36, 0.36), 0.12 * k, top, hull)
	for q: Array in faces:
		c.draw_line(q[0].lerp(q[3], 0.82), q[1].lerp(q[2], 0.82), hull.darkened(0.25), 1.0)
	if front_toward_viewer:
		draw_glacis.call()
	# Roof: the driver's hatch at the front left, the big cargo hatch behind, and the rear ramp line.
	var roof := func(x: float, y: float) -> Vector2: return proj.project(at.call(x, y), top + 0.002)
	c.draw_colored_polygon(PackedVector2Array([roof.call(0.08, -0.3), roof.call(0.2, -0.3), roof.call(0.2, -0.16), roof.call(0.08, -0.16)]), hull.darkened(0.2))
	c.draw_polyline(PackedVector2Array([roof.call(-0.42, -0.24), roof.call(-0.12, -0.24), roof.call(-0.12, 0.24), roof.call(-0.42, 0.24), roof.call(-0.42, -0.24)]), hull.darkened(0.35), 1.0)
	if star and death < 0.5:
		var center: Vector2 = at.call(-0.27, 0.0)
		var star_points := PackedVector2Array()
		for i in 10:
			var radius := 0.11 if i % 2 == 0 else 0.045
			star_points.append(proj.project(center + f.rotated(TAU * i / 10.0) * radius, top + 0.003))
		c.draw_colored_polygon(star_points, STAR)
	# The commander's cupola (front right), the .50 on its pintle, and the gun shield.
	var cupola_at: Vector2 = at.call(0.04, 0.17)
	var gun_facing := facing.rotated(0.5 * minf(1.0, death * 1.5))
	var gun_from := proj.project(cupola_at + gun_facing * 0.05 * k, top + 0.17 * k)
	var gun_to := proj.project(cupola_at + gun_facing * 0.5 * k, top + (0.18 - 0.1 * death) * k)
	var shield := _box(cupola_at, gun_facing * k, Vector2(-gun_facing.y, gun_facing.x) * k, 0.08, 0.11, -0.1, 0.1)
	if not front_toward_viewer:
		_gun(c, gun_from, gun_to, false, death >= 1.0)
		TerrainPainter.prism(c, proj, shield, top + 0.06 * k, top + 0.24 * k, hull.lightened(0.04))
	TerrainPainter.prism(c, proj, _octagon(cupola_at, facing, 0.09 * k), top, top + 0.07 * k, hull.darkened(0.08))
	c.draw_line(proj.project(cupola_at, top + 0.07 * k), gun_from, GUN, 2.5)
	c.draw_circle(gun_from, 3.0, GUN)
	if front_toward_viewer:
		TerrainPainter.prism(c, proj, shield, top + 0.06 * k, top + 0.24 * k, hull.lightened(0.04))
		_gun(c, gun_from, gun_to, false, death >= 1.0)
	c.draw_circle(gun_to, 2.2, GUN)
	if death > 0.0:
		_burn(c, proj, g, pose["time"])


# --- Helicopter ---

## A UH-1 "Huey" in olive drab at `height` tiles above ground point g (grid, the tile centre), nose along
## `facing`: fuselage, cabin glass, open cargo door, tail boom and fin, spinning tail rotor, skids and a
## translucent main-rotor disc turning with `time`. Its shadow falls on the ground below.
static func draw_helicopter(c: CanvasItem, proj: ViewProjection, g: Vector2, facing: Vector2, height: float, time: float, alpha := 1.0) -> void:
	facing = facing.normalized() if facing.length() > 0.0 else Vector2(1, 0)
	var right := Vector2(-facing.y, facing.x)
	var k := 1.15
	var f := facing * k
	var r := right * k
	var h := height + 0.2 * k
	var at := func(x: float, y: float) -> Vector2: return g + f * x + r * y
	var cabin := PackedVector2Array([at.call(-0.32, -0.18), at.call(0.34, -0.18), at.call(0.56, -0.09), at.call(0.62, 0.0),
		at.call(0.56, 0.09), at.call(0.34, 0.18), at.call(-0.32, 0.18)])
	var boom := PackedVector2Array([at.call(-0.3, -0.07), at.call(-0.3, 0.07), at.call(-1.15, 0.03), at.call(-1.15, -0.03)])
	# The shadow on the ground: fuselage, boom and a faint rotor disc, offset by the light.
	var shadow_alpha := 0.26 * alpha * clampf(1.2 - height * 0.12, 0.35, 1.0)
	var off := TerrainPainter.LIGHT * h
	for poly: PackedVector2Array in [cabin, boom]:
		var pts := PackedVector2Array()
		for p in poly:
			pts.append(proj.project(p + off))
		c.draw_colored_polygon(pts, Color(0, 0, 0, shadow_alpha))
	c.draw_colored_polygon(TerrainPainter.ground_circle(proj, g + off, 0.95 * k, false), Color(0, 0, 0, shadow_alpha * 0.3))
	var drab := OLIVE_DRAB
	# Skids under the cabin, with struts.
	for side: float in [-0.2, 0.2]:
		var skid := PackedVector2Array([proj.project(at.call(-0.3, side), h - 0.16 * k), proj.project(at.call(0.42, side), h - 0.16 * k),
			proj.project(at.call(0.5, side), h - 0.12 * k)])
		c.draw_polyline(skid, Color(ROTOR, alpha), 2.2)
		for x in [-0.15, 0.25]:
			c.draw_line(proj.project(at.call(x, side), h - 0.16 * k), proj.project(at.call(x, side * 0.8), h), Color(ROTOR, alpha), 1.6)
	var tail_toward_viewer := proj.depth(g - facing) > proj.depth(g)
	var right_toward_viewer := proj.depth(g + right) > proj.depth(g)
	var draw_tail := func() -> void:
		TerrainPainter.prism(c, proj, boom, h + 0.2 * k, h + 0.32 * k, drab, alpha)
		var fin := _box(g, f, r, -1.2, -1.08, -0.02, 0.02)
		TerrainPainter.prism(c, proj, fin, h + 0.2 * k, h + 0.58 * k, drab.darkened(0.05), alpha)
		# Small horizontal stabiliser.
		TerrainPainter.prism(c, proj, _box(g, f, r, -0.9, -0.82, -0.16, 0.16), h + 0.25 * k, h + 0.27 * k, drab, alpha)
		# The tail rotor on the fin's left side, spinning in the vertical plane.
		var hub_side := 0.05 if not right_toward_viewer else -0.05
		hub_side = -0.05 if right_toward_viewer else 0.05
		var hub: Vector2 = at.call(-1.14, -hub_side)
		var hub_h := h + 0.46 * k
		var spin := time * 40.0
		c.draw_polyline(_vertical_ring(proj, hub, facing, hub_h, 0.13 * k), Color(ROTOR, 0.25 * alpha), 1.0)
		for blade in 2:
			var a := spin + PI * blade
			var tip := proj.project(hub + facing * cos(a) * 0.13 * k, hub_h + sin(a) * 0.13 * k)
			var tail_tip := proj.project(hub - facing * cos(a) * 0.13 * k, hub_h - sin(a) * 0.13 * k)
			c.draw_line(tail_tip, tip, Color(ROTOR, 0.6 * alpha), 1.4)
	if not tail_toward_viewer:
		draw_tail.call()
	# Fuselage: the lower hull, the cabin above it and the glazed nose.
	var lower := TerrainPainter.prism(c, proj, cabin, h, h + 0.18 * k, drab.darkened(0.06), alpha)
	var upper_cabin := PackedVector2Array([at.call(-0.32, -0.18), at.call(0.34, -0.18), at.call(0.34, 0.18), at.call(-0.32, 0.18)])
	var faces := TerrainPainter.prism(c, proj, upper_cabin, h + 0.18 * k, h + 0.38 * k, drab, alpha)
	# The open cargo doors: dark openings on the cabin sides, with a door gunner's M60 poking out.
	for q: Array in faces:
		if (q[0] as Vector2).distance_to(q[1]) < 0.4 * ViewProjection.TILE_H:
			continue
		var door := PackedVector2Array([q[0].lerp(q[1], 0.25), q[0].lerp(q[1], 0.6), q[3].lerp(q[2], 0.6), q[3].lerp(q[2], 0.25)])
		door[0] = door[0].lerp(door[3], 0.05)
		door[1] = door[1].lerp(door[2], 0.05)
		c.draw_colored_polygon(door, Color(0.06, 0.06, 0.05, alpha))
	var nose := PackedVector2Array([at.call(0.34, -0.18), at.call(0.56, -0.09), at.call(0.62, 0.0), at.call(0.56, 0.09), at.call(0.34, 0.18)])
	TerrainPainter.prism(c, proj, nose, h + 0.18 * k, h + 0.32 * k, HELI_GLASS, alpha)
	# Engine housing and rotor mast on the roof.
	TerrainPainter.prism(c, proj, _box(g, f, r, -0.3, 0.12, -0.1, 0.1), h + 0.38 * k, h + 0.48 * k, drab.darkened(0.1), alpha)
	var mast_top := proj.project(at.call(0.0, 0.0), h + 0.58 * k)
	c.draw_line(proj.project(at.call(0.0, 0.0), h + 0.48 * k), mast_top, Color(ROTOR, alpha), 2.5)
	if tail_toward_viewer:
		draw_tail.call()
	# The main rotor: a translucent disc with two blurred blades sweeping round.
	var disc := TerrainPainter.ground_circle(proj, g, 0.98 * k, false, h + 0.58 * k)
	c.draw_colored_polygon(disc, Color(0.12, 0.12, 0.12, 0.16 * alpha))
	disc.append(disc[0])
	c.draw_polyline(disc, Color(0.1, 0.1, 0.1, 0.22 * alpha), 1.0)
	var spin := time * 22.0
	for trail in 4:
		for blade in 2:
			var a := spin + PI * blade - trail * 0.12
			var tip := proj.project(g + Vector2.from_angle(a) * 0.98 * k, h + 0.58 * k)
			var other := proj.project(g + Vector2.from_angle(a) * 0.08 * k, h + 0.58 * k)
			c.draw_line(other, tip, Color(ROTOR, (0.75 - trail * 0.18) * alpha), 2.4 - trail * 0.4)
	c.draw_circle(mast_top, 2.5, Color(ROTOR, alpha))


## A circle standing upright in the plane of `along` and up, for the tail rotor.
static func _vertical_ring(proj: ViewProjection, center: Vector2, along: Vector2, height: float, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 17:
		var a := TAU * i / 16.0
		points.append(proj.project(center + along * cos(a) * radius, height + sin(a) * radius))
	return points


# --- MRAP ---

const TYRE := Color("1f1f1e")
const MRAP_GLASS := Color("5d6a6e")


## An MRAP: a tall armoured truck on four big wheels, a V-shaped belly, a bonnet in front of a boxy crew cab
## with thick little windows, and a gunner's ring on the roof with a .50 cal behind a shield.
static func _draw_mrap(c: CanvasItem, proj: ViewProjection, g: Vector2, facing: Vector2, hull: Color, pose: Dictionary) -> void:
	var k := SCALE
	var right := Vector2(-facing.y, facing.x)
	var death: float = pose["death"]
	var f := facing * k
	var r := right * k
	var tyre := TYRE.lerp(WRECK.darkened(0.3), death)
	var wheel_r := 0.15 * k
	var near_right := proj.depth(g + right) > proj.depth(g)
	var wheels_on := func(side: float) -> void:
		for x in [-0.3, 0.27]:
			var center: Vector2 = g + f * x + r * side
			var ring := PackedVector2Array()
			for i in 16:
				var a := TAU * i / 16.0
				ring.append(proj.project(center + facing * cos(a) * wheel_r, wheel_r + sin(a) * wheel_r))
			c.draw_colored_polygon(ring, tyre)
			c.draw_circle(proj.project(center, wheel_r), 3.0, hull.darkened(0.3))
	wheels_on.call(-0.32 if near_right else 0.32)
	# The V-hull belly, then the body, with the bonnet and the cab sorted by depth.
	TerrainPainter.prism(c, proj, _box(g, f, r, -0.44, 0.38, -0.18, 0.18), 0.1 * k, 0.24 * k, hull.darkened(0.3))
	var parts := [
		[_box(g, f, r, -0.46, 0.12, -0.3, 0.3), 0.22 * k, 0.72 * k, hull],
		[_box(g, f, r, 0.12, 0.47, -0.27, 0.27), 0.22 * k, 0.48 * k, hull.darkened(0.04)],
	]
	parts.sort_custom(func(a: Array, b: Array) -> bool: return _depth(proj, a[0], a[1]) < _depth(proj, b[0], b[1]))
	for part: Array in parts:
		var faces := TerrainPainter.prism(c, proj, part[0], part[1], part[2], part[3])
		if part[2] > 0.6 * k:
			# Small thick windows high on the cab, and a seam along it.
			for q: Array in faces:
				var long: bool = (q[0] as Vector2).distance_to(q[1]) > 0.5 * ViewProjection.TILE_H
				var spans := [[0.55, 0.75], [0.8, 0.95]] if long else [[0.15, 0.45], [0.55, 0.85]]
				for span: Array in spans:
					var win := PackedVector2Array([_on_face(q, span[0], 0.55), _on_face(q, span[1], 0.55), _on_face(q, span[1], 0.82),
						_on_face(q, span[0], 0.82)])
					c.draw_colored_polygon(win, MRAP_GLASS.lerp(WRECK, death))
				c.draw_line(q[0].lerp(q[3], 0.3), q[1].lerp(q[2], 0.3), hull.darkened(0.25), 1.0)
		else:
			# The grille on the bonnet.
			for q: Array in faces:
				for t in [0.3, 0.5, 0.7]:
					c.draw_line(_on_face(q, t, 0.2), _on_face(q, t, 0.8), hull.darkened(0.3), 1.0)
	wheels_on.call(0.32 if near_right else -0.32)
	# The gunner's ring and shield on the roof, and the .50.
	var top := 0.72 * k
	var ring_at := g + f * -0.14
	var gun_facing := facing.rotated(0.5 * minf(1.0, death * 1.5))
	var gun_right := Vector2(-gun_facing.y, gun_facing.x)
	var gun_from := proj.project(ring_at + gun_facing * 0.05 * k, top + 0.16 * k)
	var gun_to := proj.project(ring_at + gun_facing * 0.52 * k, top + (0.17 - 0.1 * death) * k)
	var shield := _box(ring_at, gun_facing * k, gun_right * k, 0.1, 0.13, -0.13, 0.13)
	var front_toward_viewer := proj.depth(g + gun_facing) >= proj.depth(g) - 0.01
	TerrainPainter.prism(c, proj, _octagon(ring_at, facing, 0.12 * k), top, top + 0.05 * k, hull.darkened(0.1))
	if not front_toward_viewer:
		_gun(c, gun_from, gun_to, false, death >= 1.0)
	TerrainPainter.prism(c, proj, shield, top + 0.05 * k, top + 0.26 * k, hull.lightened(0.04))
	for side: float in [-1.0, 1.0]:
		var wing := _box(ring_at, gun_facing * k, gun_right * k, -0.02, 0.1, 0.11 * side - 0.015, 0.11 * side + 0.015)
		TerrainPainter.prism(c, proj, wing, top + 0.05 * k, top + 0.22 * k, hull.lightened(0.02))
	c.draw_circle(gun_from, 3.0, GUN)
	if front_toward_viewer:
		_gun(c, gun_from, gun_to, false, death >= 1.0)
	c.draw_circle(gun_to, 2.2, GUN)
	if death > 0.0:
		_burn(c, proj, g, pose["time"])


## A point on a prism face quad [bottom a, bottom b, top b, top a]: u along it, v up it.
static func _on_face(q: Array, u: float, v: float) -> Vector2:
	var bottom: Vector2 = (q[0] as Vector2).lerp(q[1], u)
	var top: Vector2 = (q[3] as Vector2).lerp(q[2], u)
	return bottom.lerp(top, v)
