class_name SoldierPainter
extends RefCounted
## Procedural soldiers: a small 3D model of capsules and balls in the unit's own frame
## (forward, right, up), projected with the view so soldiers turn and rotate with the camera.
##
## Built like a person: legs that bend at the knee, hips, a torso broad from the front and slim from the side,
## shoulders, arms bent at the elbow holding the weapon, neck, head and helmet. Each side has its own
## uniform, boots and helmet (its faction's "look"), and each role its kit.
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
## Mottled spots on a camouflage helmet cover.
const MOTTLE := [Color("6f6a3f"), Color("3b4527"), Color("7b5f3c")]
const BLACK_FURNITURE := Color("1b1c1e")
const FORTY_MM := Color("c2a84f")
const RADIO := Color("3c4428")
const RICE_TUBE := Color("b3a682")
const CHICOM := Color("8b7d52")
const SATCHEL := Color("6b5b3a")
const NVG_MOUNT := Color("1d1e1f")
const SHEMAGH := Color("ddd5c4")
const SHEMAGH_RED := Color("a8322c")
const DETECTOR := Color("3c3f3a")
const RPG_WOOD := Color("7a5534")
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
## Each side's uniform comes from its theatre faction's "look": jacket, trousers, helmet, webbing, boots,
## leggings (or null), pack and skin colours, "headgear" and "officer_headgear" (see _headgear), and
## "wood_stock" (SMGs and MGs with wooden furniture). Optional: "black_rifles" (rifles with black plastic
## furniture, the M16), "sandals" (bare ankles and feet in sandals), "pith" (pith helmet colour), "body_armor" (a plate
## carrier with pouches over the jacket), "robe" (a long tunic hanging to the knees), "pakol" (pakol cap colour),
## "rpg" (the AT weapon is an RPG with its warhead showing).


## The faction look a unit is drawn in.
static func look_of(unit: Unit) -> Dictionary:
	return Theatres.get_theatre(unit.theatre).faction(unit.team)["look"]


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
	var faction: Dictionary = look_of(unit)
	var skin: Color = faction.get("skin", SKIN)
	var stock_color: Color = STOCK if faction.get("wood_stock", false) else GUN
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
		if faction.get("sandals", false):
			# Trousers to just above the ankle, bare skin, and a foot on a thin sole.
			var hem := ankle.lerp(knee, 0.3)
			parts.append([knee, hem, 4.2, trousers])
			parts.append([hem, ankle, 3.2, skin])
			parts.append([ankle + Vector3(-0.02, 0, -0.04), ankle + Vector3(0.05, 0, -0.045), 3.0, faction["boots"]])
			parts.append([ankle + Vector3(-0.015, 0, -0.03), ankle + Vector3(0.04, 0, -0.035), 2.4, skin])
			continue
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
	if faction.get("robe", false):
		# The long shirt of the shalwar kameez, hanging to the knees front and back.
		for side: float in [-1.0, 1.0]:
			parts.append([Vector3(0.0, 0.05 * side, hip + 0.04), Vector3(0.025 + 0.13 * bend, 0.065 * side, 0.3 + 0.03 * bend), 6.2, jacket])
		parts.append([Vector3(0.0, 0.0, hip + 0.04), Vector3(0.03 + 0.13 * bend, 0.0, 0.29 + 0.03 * bend), 6.0, jacket.darkened(0.06)])
	if faction.get("body_armor", false):
		# A plate carrier: front and back plates, shoulder straps, and pouches along the front.
		var carrier := webbing
		for side: float in [-1.0, 1.0]:
			parts.append([_up(f, 0.045, 0.04 * side, 0.6), _up(f, 0.045, 0.04 * side, 0.74), 5.6, carrier])
			parts.append([_up(f, -0.05, 0.04 * side, 0.6), _up(f, -0.05, 0.04 * side, 0.75), 5.6, carrier.darkened(0.08)])
			parts.append([_up(f, 0.035, 0.065 * side, 0.76), _up(f, -0.04, 0.065 * side, 0.77), 2.6, carrier.darkened(0.1)])
		for side: float in [-0.055, 0.0, 0.055]:
			parts.append([_up(f, 0.07, side, 0.6), _up(f, 0.07, side, 0.655), 3.2, carrier.darkened(0.14)])
	parts.append([_up(f, 0.0, 0, 0.8), _up(f, 0.005, 0, 0.86), 3.0, skin])
	parts.append([Vector3(head_x, 0, head), Vector3(head_x, 0, head), 5.5, skin])

	# The weapon: wooden stock and handguard, metal receiver and barrel.
	var butt: Vector3 = hold["butt"]
	var grip: Vector3 = hold["grip"]
	var muzzle_at: Vector3 = hold["muzzle"]
	match kind:
		"at" when faction.get("rpg", false):
			# The RPG: a slim tube with wooden heat guards, a flared venturi behind and the warhead in front.
			var front := butt.lerp(muzzle_at, 0.82)
			parts.append([butt, front, 3.4, Color("3e4136"), HELD])
			parts.append([butt.lerp(muzzle_at, 0.35), butt.lerp(muzzle_at, 0.6), 4.4, RPG_WOOD, HELD])
			parts.append([butt, butt + (muzzle_at - butt) * 0.05, 5.0, GUN, HELD])
			parts.append([front, muzzle_at, 6.4, Color("5a5f45"), HELD])
			parts.append([muzzle_at, muzzle_at + (muzzle_at - butt).normalized() * 0.05, 3.0, Color("6b704f"), HELD])
			parts.append([grip, grip + Vector3(0, 0, -0.07), 2.2, GUN, HELD])
		"at":
			parts.append([butt, muzzle_at, 5.2, Color("4a4d3a"), HELD])
			parts.append([butt, butt + (muzzle_at - butt) * 0.06, 6.2, GUN, HELD])
			parts.append([grip, grip + Vector3(0, 0, -0.07), 2.2, GUN, HELD])
		"smg":
			parts.append([butt, grip, 3.0, stock_color, HELD])
			parts.append([grip, muzzle_at, 2.8, GUN, HELD])
			var well := grip.lerp(muzzle_at, 0.35)
			parts.append([well, well + Vector3(0, 0, -0.1), 2.4, GUN, HELD])
		"mg":
			parts.append([butt, grip, 3.4, stock_color, HELD])
			parts.append([grip, grip.lerp(muzzle_at, 0.45), 3.8, GUN, HELD])
			parts.append([grip.lerp(muzzle_at, 0.45), muzzle_at, 2.6, GUN.lightened(0.12), HELD])
			var belt_at := grip.lerp(muzzle_at, 0.2)
			parts.append([belt_at, belt_at + Vector3(-0.02, 0.06, -0.08), 2.4, BRASS, HELD])
			if pose["deployed"]:
				var bipod := grip.lerp(muzzle_at, 0.85)
				for side: float in [-0.06, 0.06]:
					var foot := Vector3(bipod.x + 0.03, bipod.y + side, 0.0) if prone else Vector3(muzzle_at.x * 0.95, bipod.y + side, 0.02)
					parts.append([bipod, foot, 1.8, GUN, HELD])
		"assault":
			# The AK-47: wooden stock and handguard, and the curved magazine.
			var guard_from := grip.lerp(muzzle_at, 0.42)
			var guard_to := grip.lerp(muzzle_at, 0.68)
			parts.append([butt, grip, 3.4, STOCK, HELD])
			parts.append([grip, guard_from, 3.0, GUN, HELD])
			parts.append([guard_from, guard_to, 3.0, STOCK.darkened(0.05), HELD])
			parts.append([guard_to, muzzle_at, 1.7, GUN, HELD])
			var well := grip.lerp(muzzle_at, 0.3)
			var mag_bend := well + Vector3(0.025, 0, -0.06)
			parts.append([well, mag_bend, 2.4, GUN.lightened(0.05), HELD])
			parts.append([mag_bend, mag_bend + Vector3(0.045, 0, -0.045), 2.4, GUN.lightened(0.05), HELD])
		"launcher":
			# The M79: a wooden stock and a short, fat barrel.
			parts.append([butt, grip, 3.6, STOCK, HELD])
			parts.append([grip, grip.lerp(muzzle_at, 0.3), 2.6, GUN, HELD])
			parts.append([grip.lerp(muzzle_at, 0.3), muzzle_at, 4.0, GUN.lightened(0.12), HELD])
			parts.append([grip.lerp(muzzle_at, 0.32), grip.lerp(muzzle_at, 0.6), 3.0, STOCK.darkened(0.1), HELD])
		_ when kind == "rifle" and faction.get("black_rifles", false):
			# The M16: black furniture, a carrying handle on top and a straight magazine.
			var fore_end := grip.lerp(muzzle_at, 0.62)
			parts.append([butt, grip, 3.2, BLACK_FURNITURE, HELD])
			parts.append([grip, fore_end, 3.0, BLACK_FURNITURE, HELD])
			parts.append([fore_end, muzzle_at, 1.6, GUN, HELD])
			var handle := grip.lerp(muzzle_at, 0.12) + Vector3(0, 0, 0.035)
			parts.append([handle, handle + (muzzle_at - grip) * 0.2, 1.8, BLACK_FURNITURE, HELD])
			var well := grip.lerp(muzzle_at, 0.22)
			parts.append([well, well + Vector3(0.01, 0, -0.08), 2.2, GUN, HELD])
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
		parts.append([hands[i], hands[i], 3.2, skin, HELD])

	# Headgear, over everything else (see _headgear).
	var top := Vector3(head_x - 0.01, 0, head)
	# The face under the brim; it sorts with the helmet, so it only shows when he looks towards the camera.
	parts.append([top + Vector3(0.055, 0, -0.015), top + Vector3(0.055, 0, -0.015), 3.8, skin, BODY, HEAD_LAYER])
	_headgear(parts, faction["officer_headgear"] if unit.leader else faction["headgear"], top, faction, jacket, helmet)

	match _kit(unit):
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
		"EOD":
			# A small pack and a mine detector slung across the back, its search head at the bottom.
			parts.append([_up(f, -0.09, 0, 0.6), _up(f, -0.09, 0, 0.72), 6.5, faction["pack"]])
			var handle := _up(f, -0.12, -0.08, 0.92)
			var head_at := _up(f, -0.12, 0.11, 0.42)
			parts.append([handle, head_at, 1.6, DETECTOR])
			parts.append([handle, handle + Vector3(0.0, -0.02, 0.04), 2.6, Color("c9a23a")])
			parts.append([head_at + Vector3(0.0, -0.04, 0.0), head_at + Vector3(0.0, 0.05, -0.02), 4.6, DETECTOR.lightened(0.1)])
		"Grenadier":
			# A vest of 40mm rounds: rows of brass noses across the chest, and a pack.
			parts.append([_up(f, -0.08, 0, 0.58), _up(f, -0.08, 0, 0.72), 7.0, faction["pack"]])
			for side: float in [-1.0, 1.0]:
				parts.append([_up(f, 0.045, 0.05 * side, 0.6), _up(f, 0.045, 0.05 * side, 0.73), 4.6, webbing.darkened(0.15)])
				for row in 3:
					var z := 0.61 + row * 0.055
					parts.append([_up(f, 0.065, 0.05 * side, z), _up(f, 0.065, 0.05 * side, z), 2.8, FORTY_MM])
		"RTO":
			# The PRC-25 radio on a frame on his back, its tall whip antenna, and the handset at his shoulder.
			parts.append([_up(f, -0.1, 0, 0.56), _up(f, -0.1, 0, 0.74), 8.5, RADIO])
			parts.append([_up(f, -0.12, 0, 0.6), _up(f, -0.12, 0, 0.7), 5.0, RADIO.lightened(0.1)])
			parts.append([_up(f, -0.12, 0.05, 0.76), _up(f, -0.16, 0.07, 1.45), 0.8, GUN])
			parts.append([_up(f, -0.16, 0.07, 1.45), _up(f, -0.16, 0.07, 1.45), 1.8, GUN])
			parts.append([_up(f, 0.02, -0.1, 0.77), _up(f, 0.04, -0.1, 0.72), 2.6, GUN])
		"Guerrilla":
			# A cloth tube of rice slung from shoulder to hip, tied off in sections.
			var from := _up(f, 0.02, -0.09, 0.77)
			var to := Vector3(0.03, 0.1, hip + 0.02)
			for i in 6:
				var a := from.lerp(to, i / 6.0)
				var b := from.lerp(to, (i + 1) / 6.0)
				parts.append([a + Vector3(0.025, 0, 0), b + Vector3(0.025, 0, 0), 3.4, RICE_TUBE.darkened(0.08 * (i % 2))])
			parts.append([Vector3(-0.02, -0.11, hip + 0.02), Vector3(-0.02, -0.11, hip - 0.04), 4.2, webbing])
		"Assault":
			# A Chinese chest rig: three magazine pouches across the front on shoulder straps.
			for side: float in [-1.0, 1.0]:
				parts.append([_up(f, 0.05, 0.06 * side, 0.6), _up(f, 0.03, 0.06 * side, 0.77), 1.6, CHICOM.darkened(0.15)])
			parts.append([_up(f, 0.05, -0.08, 0.6), _up(f, 0.05, 0.08, 0.6), 2.4, CHICOM.darkened(0.1)])
			for side: float in [-0.05, 0.0, 0.05]:
				parts.append([_up(f, 0.065, side, 0.61), _up(f, 0.065, side, 0.68), 3.4, CHICOM])
		"Sapper":
			# Satchel charges: a bundle on the back with its fuse, and a bag at the hip.
			parts.append([_up(f, -0.09, -0.02, 0.6), _up(f, -0.09, 0.03, 0.72), 8.0, SATCHEL])
			parts.append([_up(f, -0.12, -0.04, 0.66), _up(f, -0.12, 0.05, 0.66), 2.0, SATCHEL.darkened(0.35)])
			parts.append([_up(f, -0.1, 0.04, 0.74), _up(f, -0.05, 0.1, 0.8), 1.0, Color("c8302a")])
			parts.append([Vector3(-0.01, 0.12, hip + 0.01), Vector3(-0.01, 0.12, hip - 0.08), 6.0, SATCHEL.darkened(0.1)])
			parts.append([_up(f, 0.03, -0.09, 0.77), Vector3(0.03, 0.12, hip + 0.02), 1.4, SATCHEL.darkened(0.3)])
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


## The kit drawn on a soldier: its role's "kit", or the role itself.
static func _kit(unit: Unit) -> String:
	var kit: String = unit.def.get("kit", "")
	return kit if kit != "" else unit.role


## Adds the head gear parts. Styles: "m1" (the American M1, a round dome with a narrow brim all round),
## "m1_striped" (an officer's, a white stripe down the back), "stahlhelm" (a dome with a flared skirt over the
## ears and neck), "peaked_cap" (the German officer's cap).
static func _headgear(parts: Array, style: String, top: Vector3, faction: Dictionary, jacket: Color, helmet: Color) -> void:
	match style:
		"peaked_cap":
			parts.append([top + Vector3(-0.005, 0, 0.045), top + Vector3(-0.005, 0, 0.045), 0.0, jacket.darkened(0.2), BODY, HEAD_LAYER, 0.075])
			parts.append([top + Vector3(0.0, 0, 0.03), top + Vector3(-0.01, 0, 0.06), 6.0, jacket.darkened(0.25), BODY, HEAD_LAYER])
			parts.append([top + Vector3(0.06, -0.03, 0.025), top + Vector3(0.06, 0.03, 0.025), 2.4, faction["boots"], BODY, HEAD_DETAIL])
			parts.append([top + Vector3(0.045, 0, 0.065), top + Vector3(0.045, 0, 0.065), 2.0, Color("c9c2a8"), BODY, HEAD_DETAIL])
		"stahlhelm":
			# The skirt flares out low over the ears and the back of the neck; the dome sits high and narrow.
			parts.append([top + Vector3(-0.035, 0, -0.012), top + Vector3(-0.035, 0, -0.012), 0.0, helmet.darkened(0.22), BODY, HEAD_LAYER, 0.1])
			parts.append([top + Vector3(-0.015, 0, 0.01), top + Vector3(-0.015, 0, 0.01), 0.0, helmet.darkened(0.1), BODY, HEAD_LAYER, 0.08])
			parts.append([top + Vector3(-0.01, 0, 0.05), top + Vector3(-0.015, 0, 0.06), 6.6, helmet, BODY, HEAD_LAYER])
		"conical":
			# The conical straw hat: a wide, shallow cone, drawn as stacked rings rising to a point.
			# A wide straw brim, the lit upper cone, and its point.
			var straw: Color = helmet
			parts.append([top + Vector3(0.0, 0, 0.025), top + Vector3(0.0, 0, 0.025), 0.0, straw.darkened(0.1), BODY, HEAD_LAYER, 0.15])
			parts.append([top + Vector3(-0.012, -0.008, 0.06), top + Vector3(-0.012, -0.008, 0.06), 0.0, straw.lightened(0.12), BODY, HEAD_DETAIL, 0.07])
			parts.append([top + Vector3(-0.01, -0.006, 0.095), top + Vector3(-0.01, -0.006, 0.095), 2.0, straw.lightened(0.25), BODY, HEAD_DETAIL])
		"pith":
			# The pith helmet: a tall rounded dome over a sloping brim, a red star badge at the front.
			var pith: Color = faction.get("pith", helmet)
			parts.append([top + Vector3(0.0, 0, 0.012), top + Vector3(0.0, 0, 0.012), 0.0, pith.darkened(0.2), BODY, HEAD_LAYER, 0.14])
			parts.append([top + Vector3(-0.005, -0.008, 0.045), top + Vector3(-0.005, 0.008, 0.06), 6.4, pith, BODY, HEAD_LAYER])
			parts.append([top + Vector3(-0.005, 0, 0.085), top + Vector3(-0.005, 0, 0.085), 1.8, pith.lightened(0.18), BODY, HEAD_DETAIL])
			parts.append([top + Vector3(0.06, 0, 0.045), top + Vector3(0.06, 0, 0.045), 2.0, Color("c8302a"), BODY, HEAD_DETAIL])
		"mich":
			# The MICH: a high-cut dome without a brim, side rails, and the night-vision mount at the front.
			parts.append([top + Vector3(-0.005, 0, 0.02), top + Vector3(-0.005, 0, 0.02), 0.0, helmet.darkened(0.18), BODY, HEAD_LAYER, 0.085])
			parts.append([top + Vector3(-0.01, -0.01, 0.045), top + Vector3(-0.01, 0.01, 0.05), 7.4, helmet, BODY, HEAD_LAYER])
			for side: float in [-1.0, 1.0]:
				parts.append([top + Vector3(0.03, 0.068 * side, 0.03), top + Vector3(-0.04, 0.068 * side, 0.03), 1.6, NVG_MOUNT, BODY, HEAD_DETAIL])
			parts.append([top + Vector3(0.05, 0, 0.075), top + Vector3(0.06, 0, 0.065), 1.8, NVG_MOUNT, BODY, HEAD_DETAIL])
			parts.append([top + Vector3(-0.03, 0.0, 0.08), top + Vector3(-0.03, 0.0, 0.08), 2.0, helmet.darkened(0.25), BODY, HEAD_DETAIL])
		"turban":
			# Cloth wound round the head, with its loose end hanging at the back.
			parts.append([top + Vector3(0.0, 0, 0.02), top + Vector3(0.0, 0, 0.02), 0.0, helmet.darkened(0.12), BODY, HEAD_LAYER, 0.09])
			parts.append([top + Vector3(-0.005, -0.02, 0.045), top + Vector3(-0.005, 0.02, 0.055), 8.4, helmet, BODY, HEAD_LAYER])
			parts.append([top + Vector3(0.04, -0.045, 0.045), top + Vector3(-0.01, 0.05, 0.075), 1.0, helmet.lightened(0.1), BODY, HEAD_DETAIL])
			parts.append([top + Vector3(-0.04, -0.05, 0.05), top + Vector3(0.01, 0.045, 0.07), 1.0, helmet.lightened(0.1), BODY, HEAD_DETAIL])
			parts.append([top + Vector3(-0.07, 0.03, 0.02), top + Vector3(-0.09, 0.04, -0.09), 2.6, helmet.darkened(0.05), BODY, HEAD_LAYER])
		"pakol":
			# The flat, round wool cap with its rolled brim.
			var wool: Color = faction.get("pakol", Color("7a6a50"))
			parts.append([top + Vector3(-0.005, -0.022, 0.035), top + Vector3(-0.005, 0.022, 0.035), 7.6, wool.darkened(0.12), BODY, HEAD_LAYER])
			parts.append([top + Vector3(-0.005, -0.015, 0.06), top + Vector3(-0.005, 0.015, 0.06), 6.4, wool.lightened(0.06), BODY, HEAD_DETAIL])
		"shemagh":
			# A chequered scarf wrapped over the head and round the face.
			parts.append([top + Vector3(0.0, 0, 0.02), top + Vector3(0.0, 0, 0.02), 0.0, SHEMAGH.darkened(0.1), BODY, HEAD_LAYER, 0.085])
			parts.append([top + Vector3(-0.005, -0.01, 0.045), top + Vector3(-0.005, 0.01, 0.055), 7.6, SHEMAGH, BODY, HEAD_LAYER])
			for i in 5:
				var angle := TAU * i / 5.0
				var at := top + Vector3(cos(angle) * 0.04, sin(angle) * 0.045, 0.06)
				parts.append([at, at, 1.6, SHEMAGH_RED, BODY, HEAD_DETAIL])
			parts.append([top + Vector3(-0.07, 0.0, 0.0), top + Vector3(-0.08, 0.0, -0.08), 3.0, SHEMAGH.darkened(0.08), BODY, HEAD_LAYER])
		"m1_covered":
			# The M1 in its leaf-pattern cloth cover, mottled, with an elastic band round it.
			parts.append([top + Vector3(0.0, 0, 0.02), top + Vector3(0.0, 0, 0.02), 0.0, helmet.darkened(0.2), BODY, HEAD_LAYER, 0.098])
			parts.append([top + Vector3(-0.01, -0.012, 0.045), top + Vector3(-0.01, 0.012, 0.045), 7.6, helmet, BODY, HEAD_LAYER])
			var spots := [Vector3(0.02, -0.03, 0.06), Vector3(-0.03, 0.025, 0.065), Vector3(0.0, 0.035, 0.05), Vector3(-0.04, -0.02, 0.05),
				Vector3(0.035, 0.015, 0.05), Vector3(-0.005, -0.005, 0.075)]
			for i in spots.size():
				parts.append([top + spots[i], top + spots[i], 2.2, MOTTLE[i % MOTTLE.size()], BODY, HEAD_DETAIL])
			parts.append([top + Vector3(-0.065, -0.045, 0.032), top + Vector3(-0.065, 0.045, 0.032), 1.6, Color("1e1e1a"), BODY, HEAD_DETAIL])
			parts.append([top + Vector3(-0.06, 0.05, 0.035), top + Vector3(-0.06, 0.05, 0.035), 2.4, Color("d8d4c4"), BODY, HEAD_DETAIL])
		_:
			# A broad, low dome over a level brim all round.
			parts.append([top + Vector3(0.0, 0, 0.02), top + Vector3(0.0, 0, 0.02), 0.0, helmet.darkened(0.2), BODY, HEAD_LAYER, 0.098])
			parts.append([top + Vector3(-0.01, -0.012, 0.045), top + Vector3(-0.01, 0.012, 0.045), 7.6, helmet, BODY, HEAD_LAYER])
			if style == "m1_striped":
				parts.append([top + Vector3(-0.07, 0, 0.05), top + Vector3(0.0, 0, 0.085), 2.0, WHITE, BODY, HEAD_DETAIL])


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
	return {"rifle": 0.56, "carbine": 0.46, "smg": 0.38, "mg": 0.62, "sniper": 0.6, "at": 0.4, "assault": 0.47, "launcher": 0.33}.get(unit.weapon.kind, 0.52)


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
