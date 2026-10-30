class_name SoldierPainter
extends RefCounted
## Procedural soldiers: a small 3D model of capsules and balls in the unit's own frame
## (forward, right, up), projected with the view so soldiers turn and rotate with the camera.
##
## Pose keys: facing (Vector2, grid), walk (0..1), phase (walk cycle, radians), crouch (bool),
## death (0 standing .. 1 lying), flash (0..1 hit flash), breath (radians).

const SKIN := Color("d3a37b")
const GUN := Color("2a2d31")
const BOOTS := Color("231f1b")
const OUTLINE := Color(0.06, 0.06, 0.07)
const MEDIC_WHITE := Color("e6e4dc")
const MEDIC_RED := Color("d0322b")


static func draw(c: CanvasItem, proj: ViewProjection, g: Vector2, unit: Unit, team_color: Color, pose: Dictionary) -> void:
	var facing: Vector2 = pose["facing"]
	var death: float = pose["death"]
	var flash: float = pose["flash"]
	var drawn := []
	for part: Array in _model(unit, team_color, pose):
		var a := _fall(part[0], death)
		var b := _fall(part[1], death)
		drawn.append([_depth(proj, g, facing, (a + b) * 0.5), _to_screen(proj, g, facing, a), _to_screen(proj, g, facing, b), part[2], part[3]])
	drawn.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for d: Array in drawn:
		var color: Color = d[4]
		if flash > 0.0:
			color = color.lerp(Color.WHITE, flash)
		_capsule(c, d[1], d[2], d[3] + 2.5, OUTLINE)
		_capsule(c, d[1], d[2], d[3], color)


## Screen position of the weapon's muzzle, for flashes and tracers.
static func muzzle(proj: ViewProjection, g: Vector2, unit: Unit, pose: Dictionary) -> Vector2:
	var gun := _gun(unit)
	var chest := 0.84 * (0.72 if pose["crouch"] else 1.0)
	return _to_screen(proj, g, pose["facing"], Vector3(gun[0], 0.06, chest - 0.07))


## Parts as [a, b, width px, color] in local space Vector3(forward, right, up), up in tiles of height.
static func _model(unit: Unit, team_color: Color, pose: Dictionary) -> Array:
	var k := 0.72 if pose["crouch"] else 1.0
	var walk: float = pose["walk"]
	var phase: float = pose["phase"]
	var s := sin(phase) * 0.11 * walk
	var bob := absf(cos(phase)) * 0.02 * walk + sin(pose["breath"]) * 0.006
	var hip := 0.5 * k + bob
	var chest := 0.84 * k + bob
	var head := 1.0 * k + bob
	var knee := 0.27 * k
	var heavy := unit.role == "Heavy"
	var uniform := team_color.darkened(0.55).lerp(Color("3d4235"), 0.45)
	var vest := team_color.darkened(0.12)
	var helmet := team_color.darkened(0.4)
	var gun := _gun(unit)
	var length: float = gun[0]

	var parts := [
		[Vector3(0, -0.06, hip), Vector3(0.04 + s * 0.5, -0.07, knee), 5.0, uniform],
		[Vector3(0.04 + s * 0.5, -0.07, knee), Vector3(s, -0.07, 0.04), 4.5, uniform],
		[Vector3(s + 0.03, -0.07, 0.03), Vector3(s + 0.03, -0.07, 0.03), 6.0, BOOTS],
		[Vector3(0, 0.06, hip), Vector3(0.04 - s * 0.5, 0.07, knee), 5.0, uniform],
		[Vector3(0.04 - s * 0.5, 0.07, knee), Vector3(-s, 0.07, 0.04), 4.5, uniform],
		[Vector3(-s + 0.03, 0.07, 0.03), Vector3(-s + 0.03, 0.07, 0.03), 6.0, BOOTS],
		[Vector3(0, 0, hip + 0.03), Vector3(0, 0, chest), 14.0 if heavy else 11.0, vest],
		[Vector3(0, 0, hip + 0.02), Vector3(0, 0, hip + 0.02), 10.0, uniform.darkened(0.3)],
		[Vector3(-0.01, 0, head + 0.03), Vector3(-0.01, 0, head + 0.03), 12.5, helmet],
		[Vector3(0.06, 0, head - 0.01), Vector3(0.06, 0, head - 0.01), 6.0, SKIN],
		[Vector3(0.0, 0.06, chest - 0.1), Vector3(length, 0.06, chest - 0.07), gun[1], GUN],
		[Vector3(0, 0.11, chest - 0.02), Vector3(0.08, 0.07, chest - 0.11), 4.5, uniform],
		[Vector3(0, -0.11, chest - 0.02), Vector3(length * 0.6, 0.05, chest - 0.08), 4.5, uniform],
	]
	match unit.role:
		"Heavy":
			parts.append([Vector3(-0.1, 0, hip + 0.1), Vector3(-0.1, 0, chest - 0.04), 11.0, Color("3a3c38")])
			for side in [-0.12, 0.12]:
				parts.append([Vector3(0, side, chest), Vector3(0, side, chest), 8.0, vest.darkened(0.2)])
		"Medic":
			parts.append([Vector3(-0.1, 0, hip + 0.12), Vector3(-0.1, 0, chest - 0.03), 9.0, MEDIC_WHITE])
			parts.append([Vector3(-0.15, 0, chest - 0.1), Vector3(-0.15, 0, chest - 0.1), 4.5, MEDIC_RED])
			parts.append([Vector3(0, -0.12, chest - 0.05), Vector3(0, -0.12, chest - 0.05), 5.0, MEDIC_WHITE])
		"Rifleman":
			parts.append([Vector3(-0.09, 0, hip + 0.12), Vector3(-0.09, 0, chest - 0.03), 9.0, Color("5b5a3c")])
	return parts


## [length in tiles, width px] of the unit's weapon.
static func _gun(unit: Unit) -> Array:
	if unit.weapon.name == "Shotgun":
		return [0.34, 4.5]
	if unit.role == "Heavy":
		return [0.5, 6.0]
	return [0.44, 3.5]


## Rotates a standing point toward lying on the back as death goes 0 -> 1.
static func _fall(v: Vector3, death: float) -> Vector3:
	if death <= 0.0:
		return v
	var lying := Vector3(-v.z * 0.9 + v.x * 0.3, v.y, 0.03 + maxf(0.0, v.x) * 0.15)
	var t := death * death
	return v.lerp(lying, t)


static func _to_screen(proj: ViewProjection, g: Vector2, facing: Vector2, v: Vector3) -> Vector2:
	var right := Vector2(-facing.y, facing.x)
	return proj.project(g + facing * v.x + right * v.y, v.z)


## Nearer the viewer is larger. Top-down looks straight down, so only height matters.
static func _depth(proj: ViewProjection, g: Vector2, facing: Vector2, v: Vector3) -> float:
	if not proj.isometric:
		return v.z
	var right := Vector2(-facing.y, facing.x)
	return proj.depth(g + facing * v.x + right * v.y) + v.z * 0.6


static func _capsule(c: CanvasItem, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	c.draw_circle(a, width * 0.5, color)
	if a.distance_to(b) > 0.5:
		c.draw_line(a, b, color, width)
		c.draw_circle(b, width * 0.5, color)
