class_name VehiclePainter
extends RefCounted
## Procedural tanks: tracks, hull, turret and gun as lit prisms in the tank's own frame (forward, right),
## projected with the view so they turn and rotate with the camera. A Sherman for the Allies with a white
## star; a Panzer IV for Germany with its boxy turret and a Balkenkreuz. Knocked-out tanks burn.
##
## Pose keys used: facing (Vector2, grid), death (0..1), flash (0..1), time (seconds).

const TRACKS := Color("2c2b27")
const GUN := Color("2a2d31")
const WRECK := Color("2f2924")
const HULLS := [Color("5d6838"), Color("5b6262")]
const STAR := Color("e8e6dc")
## Tanks are drawn a bit larger than their tile so they read as tanks next to soldiers.
const SCALE := 1.3


static func draw(c: CanvasItem, proj: ViewProjection, g: Vector2, unit: Unit, pose: Dictionary) -> void:
	var facing: Vector2 = pose["facing"]
	var right := Vector2(-facing.y, facing.x)
	# Brewing up: the hull blackens, and the turret is blown up off its ring and comes down askew.
	var death: float = pose["death"]
	var wrecked: bool = death >= 1.0
	var flash: float = pose["flash"]
	var hull: Color = (HULLS[unit.team] as Color).lerp(WRECK, death)
	var tracks := TRACKS.lerp(TRACKS.darkened(0.3), death)
	if flash > 0.0:
		hull = hull.lerp(Color.WHITE, flash)
	var german := unit.team == 1
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
