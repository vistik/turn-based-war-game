class_name SoldierPainter
extends RefCounted
## Procedural soldiers: a small 3D model of capsules and balls in the unit's own frame
## (forward, right, up), projected with the view so soldiers turn and rotate with the camera.
##
## Built like a person: legs that bend at the knee, hips, a torso broad from the front and slim from the side,
## shoulders, arms bent at the elbow holding the weapon, neck, head and helmet. Each side has its own
## uniform, boots and helmet (see FACTIONS), and each role its kit.
##
## Pose keys: facing (Vector2, grid), walk (0..1), phase (walk cycle, radians), crouch (bool), prone (bool),
## pinned (bool), deployed (bool), wounded (bool), death (0 standing .. 1 lying), fall_forward (bool, falls
## face down instead of on the back), flash (0..1 hit flash), breath (radians). A prone soldier is the standing model laid face down along his facing, rifle forward.

const SKIN := Color("d3a37b")
const GUN := Color("2a2d31")
const STOCK := Color("6b4a2b")
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
## Optional sixth entry: the layer. The helmet (and what's on it) is drawn over the rest of the soldier, as
## the camera always looks down on it.
const HEAD_LAYER := 1
const HEAD_DETAIL := 2
## Optional seventh entry: the part is a flat horizontal disc of this radius (tiles) round its first point,
## such as a helmet brim, instead of a capsule.
## Allies: M1941 khaki field jacket, olive trousers, canvas leggings, brown boots and the round M1 helmet.
## Germany: field grey tunic and trousers, black jackboots and the flared Stahlhelm.
const FACTIONS := [
	{"jacket": Color("857c4f"), "trousers": Color("5a5a3a"), "helmet": Color("535a33"), "webbing": Color("a0976a"),
		"boots": Color("5b412a"), "leggings": Color("aaa07a"), "pack": Color("6d6a45"), "stahlhelm": false},
	{"jacket": Color("5c6459"), "trousers": Color("50564f"), "helmet": Color("474c48"), "webbing": Color("2b2723"),
		"boots": Color("1c1a18"), "leggings": null, "pack": Color("5d5141"), "stahlhelm": true},
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
		var layer: int = part[5] if part.size() > 5 else 0
		var disc: float = part[6] if part.size() > 6 else 0.0
		var a := _drop(part[0], death) if held else _fall(part[0], death, forward)
		var b := _drop(part[1], death) if held else _fall(part[1], death, forward)
		# Lying dead, the helmet is just another part on the ground.
		if death >= 0.5:
			layer = 0
		drawn.append([_depth(proj, g, facing, (a + b) * 0.5) + layer * 100.0, a, b, part[2], part[3], disc])
	drawn.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for d: Array in drawn:
		var color: Color = d[4]
		if flash > 0.0:
			color = color.lerp(Color.WHITE, flash)
		if d[5] > 0.0:
			var ring := PackedVector2Array()
			for i in 16:
				var angle := TAU * i / 16.0
				ring.append(_to_screen(proj, g, facing, d[1] + Vector3(cos(angle), sin(angle), 0.0) * d[5]))
			c.draw_colored_polygon(ring, color)
			ring.append(ring[0])
			c.draw_polyline(ring, OUTLINE, 1.4, true)
			continue
		var a := _to_screen(proj, g, facing, d[1])
		var b := _to_screen(proj, g, facing, d[2])
		var width: float = d[3]
		_capsule(c, a, b, width + (2.0 if width >= 3.5 else 1.3), OUTLINE)
		_capsule(c, a, b, width, color)


## Screen position of the weapon's muzzle, for flashes and tracers.
static func muzzle(proj: ViewProjection, g: Vector2, unit: Unit, pose: Dictionary) -> Vector2:
	if pose.get("prone", false):
		return _to_screen(proj, g, pose["facing"], _prone_weapon(unit)[1])
	return _to_screen(proj, g, pose["facing"], _hold(unit, _frame(pose))["muzzle"])


## How the body is bent: bend 0 standing .. 1 squatting low (pinned), the hip height, how far the upper body
## has dropped, and how far it leans forward.
static func _frame(pose: Dictionary) -> Dictionary:
	var bend := 0.0
	if not pose.get("prone", false):
		if pose["pinned"]:
			bend = 1.0
		elif pose["crouch"] or pose["deployed"]:
			bend = 0.75
	var walk: float = pose["walk"] * (0.4 if pose.get("prone", false) else 1.0)
	var bob := absf(cos(pose["phase"])) * 0.02 * walk + sin(pose["breath"]) * 0.005
	var hip := lerpf(0.48, 0.3, bend)
	return {"bend": bend, "hip": hip + bob, "drop": 0.48 - hip - bob, "lean": 0.08 * bend, "walk": walk}


## A point of the upper body, given for a soldier standing straight: lowered and leaned with the pose.
static func _up(f: Dictionary, x: float, y: float, z: float) -> Vector3:
	return Vector3(x + f["lean"] * maxf(0.0, z - 0.48) / 0.4, y, z - f["drop"])


## Where the weapon is held: butt, grip (right hand), fore (left hand) and muzzle, standing or crouched.
## Rifles are held at the ready, butt in the shoulder; the rocket launcher rests on the shoulder.
static func _hold(unit: Unit, f: Dictionary) -> Dictionary:
	var length := _gun_length(unit)
	if unit.weapon.kind == "at":
		return {"butt": _up(f, -0.26, 0.09, 0.8), "grip": _up(f, 0.04, 0.09, 0.78), "fore": _up(f, 0.16, 0.08, 0.8),
				"muzzle": _up(f, length, 0.09, 0.82)}
	var low := 0.03 if unit.weapon.kind == "mg" else 0.0
	return {"butt": _up(f, -0.02, 0.07, 0.74 - low), "grip": _up(f, 0.09, 0.07, 0.72 - low),
			"fore": _up(f, length * 0.55, 0.06, 0.735 - low), "muzzle": _up(f, length, 0.07, 0.745 - low)}


## Parts as [a, b, width px, color, kind, layer, disc radius] in local space Vector3(forward, right, up),
## up in tiles of height (a standing soldier is a little over 1 tall).
static func _model(unit: Unit, pose: Dictionary) -> Array:
	var faction: Dictionary = FACTIONS[unit.team]
	var f := _frame(pose)
	var prone: bool = pose.get("prone", false)
	var bend: float = f["bend"]
	var hip: float = f["hip"]
	var s: float = sin(pose["phase"]) * 0.11 * f["walk"]
	var jacket: Color = faction["jacket"]
	var trousers: Color = faction["trousers"]
	var helmet: Color = faction["helmet"]
	var webbing: Color = faction["webbing"]
	var kind: String = unit.weapon.kind
	var hold := _hold(unit, f)
	if prone:
		var held := _prone_weapon(unit)
		hold = {"butt": held[0] - Vector3(0.14, 0, 0.01), "grip": held[0], "fore": held[0].lerp(held[1], 0.55), "muzzle": held[1]}
	var chest := _up(f, 0.0, 0.0, 0.77).z
	var head := _up(f, 0.0, 0.0, 0.9).z - (0.03 if pose["pinned"] else 0.0)
	var head_x := _up(f, 0.01, 0.0, 0.9).x + (0.03 if pose["pinned"] else 0.0)

	var parts := []
	# Legs: thigh, shin, then leggings (US) or jackboots (German), and the boot. Crouching bends the knees
	# forward rather than shrinking the man.
	for side: float in [-1.0, 1.0]:
		var y := 0.055 * side
		var swing := s * side
		var knee := Vector3(0.02 + swing * 0.5 + 0.15 * bend, y, 0.26 + 0.02 * bend)
		var ankle := Vector3(swing + 0.02 * bend, y, 0.07)
		var cuff := ankle.lerp(knee, 0.55 if faction["leggings"] != null else 0.75)
		parts.append([Vector3(0, y, hip), knee, 4.8, trousers])
		parts.append([knee, cuff, 4.2, trousers])
		parts.append([cuff, ankle, 4.5 if faction["leggings"] != null else 4.7, faction["leggings"] if faction["leggings"] != null else faction["boots"]])
		parts.append([ankle + Vector3(-0.02, 0, -0.035), ankle + Vector3(0.05, 0, -0.04), 4.0, faction["boots"]])
	# Hips, torso (two halves, so the soldier is broad from the front and slim from the side), shoulders,
	# belt and webbing straps, neck and head.
	parts.append([Vector3(0, -0.05, hip + 0.01), Vector3(0, 0.05, hip + 0.01), 5.5, trousers])
	for side: float in [-1.0, 1.0]:
		parts.append([Vector3(0, 0.045 * side, hip + 0.05), _up(f, 0.0, 0.05 * side, 0.74), 6.0, jacket])
	parts.append([_up(f, 0.0, -0.09, 0.765), _up(f, 0.0, 0.09, 0.765), 5.0, jacket])
	parts.append([Vector3(0.035, -0.06, hip + 0.05), Vector3(0.035, 0.06, hip + 0.05), 3.2, webbing])
	for side: float in [-1.0, 1.0]:
		parts.append([Vector3(0.04, 0.045 * side, hip + 0.06), _up(f, 0.035, 0.065 * side, 0.76), 1.6, webbing])
	parts.append([_up(f, 0.0, 0, 0.8), _up(f, 0.005, 0, 0.86), 3.0, SKIN])
	parts.append([Vector3(head_x, 0, head), Vector3(head_x, 0, head), 5.5, SKIN])

	# The weapon: wooden stock and handguard, metal receiver and barrel.
	var butt: Vector3 = hold["butt"]
	var grip: Vector3 = hold["grip"]
	var muzzle_at: Vector3 = hold["muzzle"]
	match kind:
		"at":
			parts.append([butt, muzzle_at, 5.2, Color("4a4d3a"), HELD])
			parts.append([butt, butt + (muzzle_at - butt) * 0.06, 6.2, GUN, HELD])
			parts.append([grip, grip + Vector3(0, 0, -0.07), 2.2, GUN, HELD])
		"smg":
			parts.append([butt, grip, 3.0, STOCK if unit.team == 0 else GUN, HELD])
			parts.append([grip, muzzle_at, 2.8, GUN, HELD])
			var well := grip.lerp(muzzle_at, 0.35)
			parts.append([well, well + Vector3(0, 0, -0.1), 2.4, GUN, HELD])
		"mg":
			parts.append([butt, grip, 3.4, STOCK if unit.team == 0 else GUN, HELD])
			parts.append([grip, grip.lerp(muzzle_at, 0.45), 3.8, GUN, HELD])
			parts.append([grip.lerp(muzzle_at, 0.45), muzzle_at, 2.6, GUN.lightened(0.12), HELD])
			var belt_at := grip.lerp(muzzle_at, 0.2)
			parts.append([belt_at, belt_at + Vector3(-0.02, 0.06, -0.08), 2.4, BRASS, HELD])
			if pose["deployed"]:
				var bipod := grip.lerp(muzzle_at, 0.85)
				for side: float in [-0.06, 0.06]:
					var foot := Vector3(bipod.x + 0.03, bipod.y + side, 0.0) if prone else Vector3(muzzle_at.x * 0.95, bipod.y + side, 0.02)
					parts.append([bipod, foot, 1.8, GUN, HELD])
		_:
			var fore_end := grip.lerp(muzzle_at, 0.62)
			parts.append([butt, grip, 3.4, STOCK, HELD])
			parts.append([grip, fore_end, 2.8, STOCK.darkened(0.1), HELD])
			parts.append([grip, grip.lerp(muzzle_at, 0.25), 2.6, GUN, HELD])
			parts.append([fore_end, muzzle_at, 1.7, GUN, HELD])
			if kind == "sniper":
				var mount := grip.lerp(muzzle_at, 0.15) + Vector3(0, 0, 0.035)
				parts.append([mount, mount + (muzzle_at - grip) * 0.3, 2.4, GUN.lightened(0.1), HELD])
	# Arms: upper arm from the shoulder, forearm to the hand on the weapon.
	var hands := [grip, hold["fore"]]
	var elbows := [_up(f, 0.0, 0.15, 0.64), _up(f, 0.16, -0.05, 0.65)]
	if kind == "at":
		elbows = [_up(f, -0.02, 0.15, 0.68), _up(f, 0.1, -0.03, 0.7)]
	for i in 2:
		var shoulder := _up(f, 0.0, 0.1 if i == 0 else -0.1, 0.765)
		parts.append([shoulder, elbows[i], 4.0, jacket])
		parts.append([elbows[i], hands[i], 3.6, jacket, ARM])
		parts.append([hands[i], hands[i], 3.2, SKIN, HELD])

	# Headgear, over everything else: the American M1 is a round dome with a narrow brim all round, the
	# German Stahlhelm a dome with a flared skirt over the ears and neck. German officers wear the peaked cap;
	# American officers a white stripe down the back of the helmet.
	var top := Vector3(head_x - 0.01, 0, head)
	# The face under the brim; it sorts with the helmet, so it only shows when he looks towards the camera.
	parts.append([top + Vector3(0.055, 0, -0.015), top + Vector3(0.055, 0, -0.015), 3.8, SKIN, BODY, HEAD_LAYER])
	if faction["stahlhelm"] and unit.role == "Officer":
		parts.append([top + Vector3(-0.005, 0, 0.045), top + Vector3(-0.005, 0, 0.045), 0.0, jacket.darkened(0.2), BODY, HEAD_LAYER, 0.075])
		parts.append([top + Vector3(0.0, 0, 0.03), top + Vector3(-0.01, 0, 0.06), 6.0, jacket.darkened(0.25), BODY, HEAD_LAYER])
		parts.append([top + Vector3(0.06, -0.03, 0.025), top + Vector3(0.06, 0.03, 0.025), 2.4, faction["boots"], BODY, HEAD_DETAIL])
		parts.append([top + Vector3(0.045, 0, 0.065), top + Vector3(0.045, 0, 0.065), 2.0, Color("c9c2a8"), BODY, HEAD_DETAIL])
	elif faction["stahlhelm"]:
		# The skirt flares out low over the ears and the back of the neck; the dome sits high and narrow.
		parts.append([top + Vector3(-0.035, 0, -0.012), top + Vector3(-0.035, 0, -0.012), 0.0, helmet.darkened(0.22), BODY, HEAD_LAYER, 0.1])
		parts.append([top + Vector3(-0.015, 0, 0.01), top + Vector3(-0.015, 0, 0.01), 0.0, helmet.darkened(0.1), BODY, HEAD_LAYER, 0.08])
		parts.append([top + Vector3(-0.01, 0, 0.05), top + Vector3(-0.015, 0, 0.06), 6.6, helmet, BODY, HEAD_LAYER])
	else:
		# A broad, low dome over a level brim all round.
		parts.append([top + Vector3(0.0, 0, 0.02), top + Vector3(0.0, 0, 0.02), 0.0, helmet.darkened(0.2), BODY, HEAD_LAYER, 0.098])
		parts.append([top + Vector3(-0.01, -0.012, 0.045), top + Vector3(-0.01, 0.012, 0.045), 7.6, helmet, BODY, HEAD_LAYER])
		if unit.role == "Officer":
			parts.append([top + Vector3(-0.07, 0, 0.05), top + Vector3(0.0, 0, 0.085), 2.0, WHITE, BODY, HEAD_DETAIL])

	match unit.role:
		"Officer":
			# Binoculars on the chest and a map case at the hip.
			for side: float in [-0.02, 0.02]:
				parts.append([_up(f, 0.06, side, 0.69), _up(f, 0.06, side, 0.69), 3.0, GUN])
			parts.append([Vector3(0.0, -0.11, hip + 0.02), Vector3(0.0, -0.11, hip - 0.07), 4.5, LEATHER])
		"Medic":
			# Red cross on a white patch on the helmet, an armband, and aid pouches at both hips.
			parts.append([top + Vector3(0.025, 0, 0.065), top + Vector3(0.025, 0, 0.065), 4.2, WHITE, BODY, HEAD_DETAIL])
			parts.append([top + Vector3(0.03, 0, 0.068), top + Vector3(0.03, 0, 0.068), 2.0, RED_CROSS, BODY, HEAD_DETAIL])
			parts.append([_up(f, 0.0, -0.13, 0.72), _up(f, 0.02, -0.125, 0.69), 3.8, WHITE])
			for side: float in [-1.0, 1.0]:
				parts.append([Vector3(0.0, 0.1 * side, hip + 0.02), Vector3(0.0, 0.1 * side, hip - 0.04), 4.6, WHITE.darkened(0.1)])
			parts.append([_up(f, -0.08, 0, 0.6), _up(f, -0.08, 0, 0.72), 7.0, faction["pack"]])
		"Mortar":
			# The tube over the shoulder and the round baseplate on the back.
			parts.append([_up(f, -0.1, 0.06, 0.55), _up(f, -0.15, -0.07, 1.02), 5.0, GUN.lightened(0.15)])
			parts.append([_up(f, -0.1, 0, 0.66), _up(f, -0.1, 0, 0.66), 0.0, GUN.lightened(0.05), BODY, 0, 0.09])
		"Rifleman":
			parts.append([_up(f, -0.08, 0, 0.58), _up(f, -0.08, 0, 0.73), 7.5, faction["pack"]])
			parts.append([_up(f, -0.07, -0.07, 0.76), _up(f, -0.07, 0.07, 0.76), 3.5, faction["pack"].darkened(0.15)])
		"SMG":
			# Magazine pouches across the front.
			for side: float in [-0.05, 0.05]:
				parts.append([Vector3(0.05, side, hip + 0.07), Vector3(0.055, side, hip + 0.15), 3.2, webbing])
		"MG":
			# A belt of ammunition across the chest, a box at the hip and a pack.
			parts.append([Vector3(0.05, 0.09, hip + 0.05), _up(f, 0.05, -0.09, 0.75), 2.6, BRASS])
			parts.append([Vector3(-0.01, 0.13, hip - 0.0), Vector3(-0.01, 0.13, hip - 0.09), 5.5, GUN.lightened(0.2)])
			parts.append([_up(f, -0.08, 0, 0.58), _up(f, -0.08, 0, 0.72), 7.5, faction["pack"]])
		"Sniper":
			# Camouflage scrim on the helmet.
			for i in 5:
				var angle := TAU * i / 5.0 + 0.4
				var at := top + Vector3(cos(angle) * 0.045, sin(angle) * 0.05, 0.05)
				parts.append([at, at, 3.6, FOLIAGE[i % FOLIAGE.size()], BODY, HEAD_DETAIL])
		"AT":
			# A bag of spare rockets on the back, warheads showing.
			parts.append([_up(f, -0.09, -0.02, 0.57), _up(f, -0.09, -0.02, 0.73), 7.0, LEATHER])
			for side: float in [-0.05, 0.02]:
				parts.append([_up(f, -0.1, side, 0.78), _up(f, -0.1, side, 0.78), 3.4, GUN.lightened(0.25)])
	if pose["wounded"]:
		parts.append([_up(f, 0.0, 0.13, 0.7), _up(f, 0.02, 0.135, 0.67), 4.0, WHITE])
	if prone:
		for part: Array in parts:
			var part_kind: int = part[4] if part.size() > 4 else BODY
			if part_kind != HELD:
				part[0] = _prone(part[0])
			if part_kind == BODY:
				part[1] = _prone(part[1])
	return parts


## Lays a point of the standing model face down along the facing: height becomes forward (head first),
## the back (-forward) becomes up. The head is lifted a little to look along the sights.
static func _prone(v: Vector3) -> Vector3:
	return Vector3(v.z * 0.8 - 0.42, v.y * 1.15, 0.07 - v.x * 0.6 + maxf(0.0, v.z - 0.8) * 0.45)


## [grip, muzzle] of the weapon held by a prone soldier, in the prone model's space.
static func _prone_weapon(unit: Unit) -> Array:
	if unit.weapon.kind == "at":
		return [Vector3(-0.02, 0.08, 0.17), Vector3(0.5, 0.08, 0.19)]
	var grip := Vector3(0.12, 0.06, 0.1)
	return [grip, grip + Vector3(_gun_length(unit) - 0.06, 0, 0.02)]


static func _gun_length(unit: Unit) -> float:
	return {"rifle": 0.56, "carbine": 0.46, "smg": 0.38, "mg": 0.62, "sniper": 0.6, "at": 0.4}.get(unit.weapon.kind, 0.52)


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
