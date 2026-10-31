class_name SoldierPainter
extends RefCounted
## Procedural soldiers: a small 3D model of capsules and balls in the unit's own frame
## (forward, right, up), projected with the view so soldiers turn and rotate with the camera.
##
## Pose keys: facing (Vector2, grid), walk (0..1), phase (walk cycle, radians), crouch (bool), pinned (bool),
## deployed (bool), wounded (bool), death (0 standing .. 1 lying), flash (0..1 hit flash), breath (radians).

const SKIN := Color("d3a37b")
const GUN := Color("2a2d31")
const STOCK := Color("6b4a2b")
const BOOTS := Color("231f1b")
const OUTLINE := Color(0.06, 0.06, 0.07)
const WHITE := Color("e6e4dc")
const RED_CROSS := Color("c8302a")
## Allies (olive drab, M1 helmet) and Germany (field grey, Stahlhelm).
const FACTIONS := [
	{"uniform": Color("575d34"), "jacket": Color("6c7043"), "helmet": Color("4c5430"), "webbing": Color("8b7f57"), "stahlhelm": false},
	{"uniform": Color("4c5456"), "jacket": Color("5e686a"), "helmet": Color("3a4042"), "webbing": Color("2f2b27"), "stahlhelm": true},
]


static func draw(c: CanvasItem, proj: ViewProjection, g: Vector2, unit: Unit, pose: Dictionary) -> void:
	var facing: Vector2 = pose["facing"]
	var death: float = pose["death"]
	var flash: float = pose["flash"]
	var drawn := []
	for part: Array in _model(unit, pose):
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
	var chest := 0.84 * _crouch(pose)
	if unit.weapon.kind == "at":
		return _to_screen(proj, g, pose["facing"], Vector3(0.32, 0.08, chest + 0.05))
	return _to_screen(proj, g, pose["facing"], Vector3(_gun_length(unit), 0.06, chest - 0.07))


static func _crouch(pose: Dictionary) -> float:
	if pose["pinned"]:
		return 0.6
	return 0.72 if pose["crouch"] or pose["deployed"] else 1.0


## Parts as [a, b, width px, color] in local space Vector3(forward, right, up), up in tiles of height.
static func _model(unit: Unit, pose: Dictionary) -> Array:
	var faction: Dictionary = FACTIONS[unit.team]
	var k := _crouch(pose)
	var walk: float = pose["walk"]
	var phase: float = pose["phase"]
	var s := sin(phase) * 0.11 * walk
	var bob := absf(cos(phase)) * 0.02 * walk + sin(pose["breath"]) * 0.006
	var hip := 0.5 * k + bob
	var chest := 0.84 * k + bob
	var head := 1.0 * k + bob - (0.04 if pose["pinned"] else 0.0)
	var knee := 0.27 * k
	var uniform: Color = faction["uniform"]
	var jacket: Color = faction["jacket"]
	var helmet: Color = faction["helmet"]
	var length := _gun_length(unit)
	var width := 5.5 if unit.weapon.kind == "mg" else (4.5 if unit.weapon.kind == "smg" else 3.5)
	var grip := Vector3(0.0, 0.06, chest - 0.1)
	var muzzle := Vector3(length, 0.06, chest - 0.07)
	if unit.weapon.kind == "at":
		# A rocket launcher rests on the shoulder.
		grip = Vector3(-0.2, 0.08, chest + 0.03)
		muzzle = Vector3(0.32, 0.08, chest + 0.05)
		width = 6.5

	var parts := [
		# Legs and boots.
		[Vector3(0, -0.06, hip), Vector3(0.04 + s * 0.5, -0.07, knee), 5.0, uniform],
		[Vector3(0.04 + s * 0.5, -0.07, knee), Vector3(s, -0.07, 0.04), 4.5, uniform],
		[Vector3(s + 0.03, -0.07, 0.03), Vector3(s + 0.03, -0.07, 0.03), 6.0, BOOTS],
		[Vector3(0, 0.06, hip), Vector3(0.04 - s * 0.5, 0.07, knee), 5.0, uniform],
		[Vector3(0.04 - s * 0.5, 0.07, knee), Vector3(-s, 0.07, 0.04), 4.5, uniform],
		[Vector3(-s + 0.03, 0.07, 0.03), Vector3(-s + 0.03, 0.07, 0.03), 6.0, BOOTS],
		# Body, belt and head.
		[Vector3(0, 0, hip + 0.03), Vector3(0, 0, chest), 11.0, jacket],
		[Vector3(0, 0, hip + 0.02), Vector3(0, 0, hip + 0.02), 10.0, faction["webbing"]],
		[Vector3(0.06, 0, head - 0.01), Vector3(0.06, 0, head - 0.01), 6.0, SKIN],
		# Weapon: wooden stock, metal barrel. Arms hold it at the grip and fore-end.
		[grip, grip.lerp(muzzle, 0.4), width, STOCK if unit.weapon.kind in ["rifle", "carbine", "sniper", "mg"] else jacket.darkened(0.3)],
		[grip.lerp(muzzle, 0.4), muzzle, width - 1.0, GUN if unit.weapon.kind != "at" else jacket.darkened(0.3)],
		[Vector3(0, 0.11, chest - 0.02), Vector3(0.08, 0.07, chest - 0.11), 4.5, jacket],
		[Vector3(0, -0.11, chest - 0.02), grip.lerp(muzzle, 0.6) + Vector3(0, -0.01, 0), 4.5, jacket],
	]
	# Helmets: the American M1 has a round brim, the German Stahlhelm a flared skirt at the back.
	if faction["stahlhelm"]:
		parts.append([Vector3(-0.07, 0, head - 0.035), Vector3(0.0, 0, head - 0.005), 14.5, helmet.darkened(0.15)])
	else:
		parts.append([Vector3(-0.05, 0, head - 0.005), Vector3(0.05, 0, head - 0.005), 14.0, helmet.darkened(0.15)])
	parts.append([Vector3(-0.01, 0, head + 0.03), Vector3(-0.01, 0, head + 0.03), 12.5, helmet])

	match unit.weapon.kind:
		"smg":
			parts.append([grip.lerp(muzzle, 0.5), grip.lerp(muzzle, 0.5) + Vector3(0, 0, -0.12), 3.0, GUN])
		"sniper":
			parts.append([grip.lerp(muzzle, 0.35) + Vector3(0, 0, 0.05), grip.lerp(muzzle, 0.6) + Vector3(0, 0, 0.05), 3.5, GUN])
		"mg":
			parts.append([grip.lerp(muzzle, 0.45), grip.lerp(muzzle, 0.45) + Vector3(0, 0.04, -0.06), 4.0, GUN])
			if pose["deployed"]:
				for side in [-0.06, 0.06]:
					parts.append([grip.lerp(muzzle, 0.85), Vector3(length * 0.95, 0.06 + side, 0.02), 2.0, GUN])
	match unit.role:
		"Officer":
			for side in [-0.025, 0.025]:
				parts.append([Vector3(0.08, side, chest - 0.06), Vector3(0.08, side, chest - 0.06), 4.0, GUN])
		"Medic":
			parts.append([Vector3(-0.1, 0, hip + 0.12), Vector3(-0.1, 0, chest - 0.03), 9.0, WHITE])
			parts.append([Vector3(-0.15, 0, chest - 0.1), Vector3(-0.15, 0, chest - 0.1), 4.5, RED_CROSS])
			parts.append([Vector3(0.05, 0, head + 0.06), Vector3(0.05, 0, head + 0.06), 5.0, WHITE])
			parts.append([Vector3(0.065, 0, head + 0.065), Vector3(0.065, 0, head + 0.065), 2.5, RED_CROSS])
		"Mortar":
			parts.append([Vector3(-0.12, 0.06, hip + 0.02), Vector3(-0.17, -0.06, chest + 0.28), 6.0, GUN.lightened(0.15)])
		"Rifleman", "Sniper", "MG", "AT":
			parts.append([Vector3(-0.09, 0, hip + 0.12), Vector3(-0.09, 0, chest - 0.03), 9.0, uniform.darkened(0.15)])
	if pose["wounded"]:
		parts.append([Vector3(0, -0.12, chest - 0.06), Vector3(0, -0.12, chest - 0.06), 5.0, WHITE])
	return parts


static func _gun_length(unit: Unit) -> float:
	return {"rifle": 0.46, "carbine": 0.38, "smg": 0.3, "mg": 0.52, "sniper": 0.5, "at": 0.32}.get(unit.weapon.kind, 0.44)


## Rotates a standing point toward lying on the back as death goes 0 -> 1.
static func _fall(v: Vector3, death: float) -> Vector3:
	if death <= 0.0:
		return v
	var lying := Vector3(-v.z * 0.9 + v.x * 0.3, v.y, 0.03 + maxf(0.0, v.x) * 0.15)
	return v.lerp(lying, death * death)


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
