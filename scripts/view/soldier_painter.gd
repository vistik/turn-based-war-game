class_name SoldierPainter
extends RefCounted
## Procedural soldiers: a small 3D model of capsules and balls in the unit's own frame
## (forward, right, up), projected with the view so soldiers turn and rotate with the camera.
##
## Pose keys: facing (Vector2, grid), walk (0..1), phase (walk cycle, radians), crouch (bool), prone (bool),
## pinned (bool), deployed (bool), wounded (bool), death (0 standing .. 1 lying), fall_forward (bool, falls
## face down instead of on the back), flash (0..1 hit flash), breath (radians). A prone soldier is the standing model laid face down along his facing, rifle forward.

const SKIN := Color("d3a37b")
const GUN := Color("2a2d31")
const STOCK := Color("6b4a2b")
const BOOTS := Color("231f1b")
const OUTLINE := Color(0.06, 0.06, 0.07)
const WHITE := Color("e6e4dc")
const RED_CROSS := Color("c8302a")
const BRASS := Color("b8953e")
const LEATHER := Color("5e4630")
## Leaves and scrim tied onto a sniper's helmet.
const FOLIAGE := [Color("4f6b2c"), Color("6b7a35"), Color("5a4a2a")]
## Optional fifth entry of a model part: how it is laid down for the prone pose. Body parts are laid down
## whole, held parts (the weapon) are placed directly, arms are laid down at the shoulder and keep the hand.
const BODY := 0
const HELD := 1
const ARM := 2
## Allies (olive drab, M1 helmet) and Germany (field grey, Stahlhelm).
const FACTIONS := [
	{"uniform": Color("575d34"), "jacket": Color("6c7043"), "helmet": Color("4c5430"), "webbing": Color("8b7f57"), "stahlhelm": false},
	{"uniform": Color("4c5456"), "jacket": Color("5e686a"), "helmet": Color("3a4042"), "webbing": Color("2f2b27"), "stahlhelm": true},
]


static func draw(c: CanvasItem, proj: ViewProjection, g: Vector2, unit: Unit, pose: Dictionary) -> void:
	var facing: Vector2 = pose["facing"]
	var death: float = pose["death"]
	var flash: float = pose["flash"]
	var forward: bool = pose.get("fall_forward", false)
	var drawn := []
	if pose.get("prone", false):
		death = 0.0
	for part: Array in _model(unit, pose):
		var held: bool = part.size() > 4 and part[4] == HELD
		var a := _drop(part[0], death) if held else _fall(part[0], death, forward)
		var b := _drop(part[1], death) if held else _fall(part[1], death, forward)
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
	if pose.get("prone", false):
		return _to_screen(proj, g, pose["facing"], _prone_weapon(unit)[1])
	var chest := 0.84 * _crouch(pose)
	if unit.weapon.kind == "at":
		return _to_screen(proj, g, pose["facing"], Vector3(0.32, 0.08, chest + 0.05))
	return _to_screen(proj, g, pose["facing"], Vector3(_gun_length(unit), 0.06, chest - 0.07))


static func _crouch(pose: Dictionary) -> float:
	if pose.get("prone", false):
		return 1.0
	if pose["pinned"]:
		return 0.6
	return 0.72 if pose["crouch"] or pose["deployed"] else 1.0


## Parts as [a, b, width px, color] in local space Vector3(forward, right, up), up in tiles of height.
static func _model(unit: Unit, pose: Dictionary) -> Array:
	var faction: Dictionary = FACTIONS[unit.team]
	var k := _crouch(pose)
	var prone: bool = pose.get("prone", false)
	var walk: float = pose["walk"] * (0.4 if prone else 1.0)
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
	if prone:
		var held := _prone_weapon(unit)
		grip = held[0]
		muzzle = held[1]

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
		[grip, grip.lerp(muzzle, 0.4), width, STOCK if unit.weapon.kind in ["rifle", "carbine", "sniper", "mg"] else jacket.darkened(0.3), HELD],
		[grip.lerp(muzzle, 0.4), muzzle, width - 1.0, GUN if unit.weapon.kind != "at" else jacket.darkened(0.3), HELD],
		[Vector3(0, 0.11, chest - 0.02), grip + Vector3(0, 0.01, -0.01) if prone else Vector3(0.08, 0.07, chest - 0.11), 4.5, jacket, ARM],
		[Vector3(0, -0.11, chest - 0.02), grip.lerp(muzzle, 0.6) + Vector3(0, -0.01, 0), 4.5, jacket, ARM],
	]
	# Helmets: the American M1 has a round brim, the German Stahlhelm a flared skirt at the back.
	# German officers wear the peaked field cap instead; American officers a white stripe down the helmet.
	if faction["stahlhelm"] and unit.role == "Officer":
		parts.append([Vector3(-0.03, 0, head + 0.035), Vector3(0.03, 0, head + 0.045), 13.0, uniform.darkened(0.25)])
		parts.append([Vector3(0.09, 0, head + 0.0), Vector3(0.09, 0, head + 0.0), 6.5, BOOTS])
		parts.append([Vector3(0.05, 0, head + 0.045), Vector3(0.05, 0, head + 0.045), 3.0, Color("c9c2a8")])
	elif faction["stahlhelm"]:
		parts.append([Vector3(-0.07, 0, head - 0.035), Vector3(0.0, 0, head - 0.005), 14.5, helmet.darkened(0.15)])
	else:
		parts.append([Vector3(-0.05, 0, head - 0.005), Vector3(0.05, 0, head - 0.005), 14.0, helmet.darkened(0.15)])
	if not (faction["stahlhelm"] and unit.role == "Officer"):
		parts.append([Vector3(-0.01, 0, head + 0.03), Vector3(-0.01, 0, head + 0.03), 12.5, helmet])

	match unit.weapon.kind:
		"smg":
			parts.append([grip.lerp(muzzle, 0.5), grip.lerp(muzzle, 0.5) + Vector3(0, 0, -0.06 if prone else -0.12), 3.0, GUN, HELD])
		"sniper":
			parts.append([grip.lerp(muzzle, 0.35) + Vector3(0, 0, 0.05), grip.lerp(muzzle, 0.6) + Vector3(0, 0, 0.05), 3.5, GUN, HELD])
		"mg":
			parts.append([grip.lerp(muzzle, 0.45), grip.lerp(muzzle, 0.45) + Vector3(0, 0.04, -0.06), 4.0, GUN, HELD])
			if pose["deployed"]:
				var bipod := grip.lerp(muzzle, 0.85)
				for side in [-0.06, 0.06]:
					var foot := Vector3(bipod.x + 0.03, 0.06 + side, 0.0) if prone else Vector3(length * 0.95, 0.06 + side, 0.02)
					parts.append([bipod, foot, 2.0, GUN, HELD])
	match unit.role:
		"Officer":
			# Binoculars on the chest and a map case at the hip.
			for side in [-0.025, 0.025]:
				parts.append([Vector3(0.08, side, chest - 0.06), Vector3(0.08, side, chest - 0.06), 4.5, GUN])
			parts.append([Vector3(0.0, -0.13, hip + 0.02), Vector3(0.0, -0.13, hip - 0.08), 6.0, LEATHER])
			if not faction["stahlhelm"]:
				parts.append([Vector3(-0.07, 0, head + 0.045), Vector3(0.05, 0, head + 0.05), 3.0, WHITE])
		"Medic":
			parts.append([Vector3(-0.1, 0, hip + 0.12), Vector3(-0.1, 0, chest - 0.03), 9.0, WHITE])
			parts.append([Vector3(-0.15, 0, chest - 0.1), Vector3(-0.15, 0, chest - 0.1), 4.5, RED_CROSS])
			parts.append([Vector3(0.05, 0, head + 0.06), Vector3(0.05, 0, head + 0.06), 5.0, WHITE])
			parts.append([Vector3(0.065, 0, head + 0.065), Vector3(0.065, 0, head + 0.065), 2.5, RED_CROSS])
		"Mortar":
			# The tube over the shoulder and the round baseplate on the back.
			parts.append([Vector3(-0.12, 0.06, hip + 0.02), Vector3(-0.17, -0.06, chest + 0.28), 6.0, GUN.lightened(0.15)])
			parts.append([Vector3(-0.13, 0, chest - 0.12), Vector3(-0.13, 0, chest - 0.12), 11.0, GUN.lightened(0.05)])
		"Rifleman":
			parts.append([Vector3(-0.09, 0, hip + 0.12), Vector3(-0.09, 0, chest - 0.03), 9.0, uniform.darkened(0.15)])
		"SMG":
			# Magazine pouches across the front.
			for side in [-0.05, 0.05]:
				parts.append([Vector3(0.07, side, hip + 0.1), Vector3(0.07, side, hip + 0.18), 4.0, faction["webbing"]])
		"MG":
			# An ammunition belt over the shoulder and a box at the hip.
			parts.append([Vector3(0.05, -0.1, hip + 0.06), Vector3(0.05, 0.1, chest + 0.02), 3.5, BRASS])
			parts.append([Vector3(-0.02, 0.15, hip - 0.02), Vector3(-0.02, 0.15, hip - 0.1), 7.0, GUN.lightened(0.2)])
			parts.append([Vector3(-0.09, 0, hip + 0.12), Vector3(-0.09, 0, chest - 0.03), 10.0, uniform.darkened(0.15)])
		"Sniper":
			# Camouflage scrim on the helmet.
			for i in 4:
				var angle := TAU * i / 4.0 + 0.4
				parts.append([Vector3(cos(angle) * 0.05, sin(angle) * 0.06, head + 0.06), Vector3(cos(angle) * 0.05, sin(angle) * 0.06, head + 0.06),
						5.0, FOLIAGE[i % FOLIAGE.size()]])
		"AT":
			# A bag of spare rockets on the back, warheads showing.
			parts.append([Vector3(-0.1, 0.03, hip + 0.06), Vector3(-0.1, 0.03, chest + 0.02), 8.0, LEATHER])
			for side in [-0.01, 0.07]:
				parts.append([Vector3(-0.11, side, chest + 0.06), Vector3(-0.11, side, chest + 0.06), 4.0, GUN.lightened(0.25)])
	if pose["wounded"]:
		parts.append([Vector3(0, -0.12, chest - 0.06), Vector3(0, -0.12, chest - 0.06), 5.0, WHITE])
	if prone:
		for part: Array in parts:
			var kind: int = part[4] if part.size() > 4 else BODY
			if kind != HELD:
				part[0] = _prone(part[0])
			if kind == BODY:
				part[1] = _prone(part[1])
	return parts


## Lays a point of the standing model face down along the facing: height becomes forward (head first),
## the back (-forward) becomes up. The head is lifted a little to look along the sights.
static func _prone(v: Vector3) -> Vector3:
	return Vector3(v.z * 0.8 - 0.42, v.y * 1.15, 0.07 - v.x * 0.6 + maxf(0.0, v.z - 0.85) * 0.4)


## [grip, muzzle] of the weapon held by a prone soldier, in the prone model's space.
static func _prone_weapon(unit: Unit) -> Array:
	if unit.weapon.kind == "at":
		return [Vector3(-0.02, 0.08, 0.17), Vector3(0.5, 0.08, 0.19)]
	var grip := Vector3(0.2, 0.06, 0.1)
	return [grip, grip + Vector3(_gun_length(unit), 0, 0.02)]


static func _gun_length(unit: Unit) -> float:
	return {"rifle": 0.46, "carbine": 0.38, "smg": 0.3, "mg": 0.52, "sniper": 0.5, "at": 0.32}.get(unit.weapon.kind, 0.44)


## A standing point as the soldier dies, death going 0 -> 1: the knees give, then he falls on his back (or
## face down) gathering speed like a dropped weight, and the body bounces once as it lands.
static func _fall(v: Vector3, death: float, forward := false) -> Vector3:
	if death <= 0.0:
		return v
	var lying := Vector3(-v.z * 0.9 + v.x * 0.3, v.y, 0.03 + maxf(0.0, v.x) * 0.15)
	if forward:
		lying = Vector3(v.z * 0.9 - v.x * 0.3, v.y * 1.1, 0.03 + maxf(0.0, -v.x) * 0.15)
	var buckle := clampf(death / 0.25, 0.0, 1.0)
	var sagged := Vector3(v.x, v.y, v.z * (1.0 - 0.2 * buckle))
	var drop := clampf((death - 0.2) / 0.6, 0.0, 1.0)
	var p := sagged.lerp(lying, drop * drop)
	if death > 0.8:
		p.z += sin((death - 0.8) / 0.2 * PI) * 0.035
	return p


## A point of the weapon as the dying soldier lets go: it drops and lands flat beside him.
static func _drop(v: Vector3, death: float) -> Vector3:
	if death <= 0.0:
		return v
	var landed := Vector3(v.x * 0.7 + 0.05, v.y + 0.3, 0.02)
	var t := clampf((death - 0.1) / 0.45, 0.0, 1.0)
	var p := v.lerp(landed, t * t)
	if t >= 1.0 and death < 0.75:
		p.z += sin((death - 0.55) / 0.2 * PI) * 0.03
	return p


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
