class_name RoleIcons
extends RefCounted
## Small vector icons for each role, drawn in a round badge ringed in the team colour, so roles read at a
## glance above the units. Icons are drawn in a unit box (-1..1) scaled to the badge.

const INK := Color("ece6d2")
const BADGE := Color(0.07, 0.07, 0.06, 0.85)
const RED_CROSS := Color("d0342c")


## The icon a unit's badge shows: its role's "icon", or the role itself.
static func icon_of(unit: Unit) -> String:
	var icon: String = unit.def.get("icon", "")
	return icon if icon != "" else unit.role


## A badge with the role's icon, centred on `at`, `radius` pixels across.
static func draw_badge(c: CanvasItem, at: Vector2, role: String, team_color: Color, radius := 8.0) -> void:
	if role == "Medic":
		c.draw_circle(at, radius, Color("ece6d2"))
	else:
		c.draw_circle(at, radius, BADGE)
	c.draw_arc(at, radius, 0.0, TAU, 24, team_color, 1.8, true)
	draw_icon(c, at, role, radius * 0.72)


static func draw_icon(c: CanvasItem, at: Vector2, role: String, s: float) -> void:
	var p := func(x: float, y: float) -> Vector2: return at + Vector2(x, y) * s
	var w := maxf(1.2, s * 0.22)
	match role:
		"Officer":
			var star := PackedVector2Array()
			for i in 10:
				var r := 1.0 if i % 2 == 0 else 0.42
				star.append(p.call(sin(TAU * i / 10.0) * r, -cos(TAU * i / 10.0) * r))
			c.draw_colored_polygon(star, INK)
		"Rifleman":
			# A rifle on the slant: long barrel, wooden stock.
			c.draw_line(p.call(-0.9, 0.55), p.call(0.95, -0.6), INK, w)
			c.draw_line(p.call(-0.9, 0.55), p.call(-0.55, 0.85), INK, w * 1.6)
		"SMG":
			# Short gun with a magazine hanging down.
			c.draw_line(p.call(-0.85, -0.15), p.call(0.85, -0.15), INK, w * 1.3)
			c.draw_line(p.call(0.0, -0.15), p.call(0.05, 0.75), INK, w * 1.2)
			c.draw_line(p.call(-0.85, -0.15), p.call(-0.8, 0.45), INK, w * 1.2)
		"MG":
			# Heavy barrel on a bipod.
			c.draw_line(p.call(-0.95, -0.35), p.call(0.95, -0.35), INK, w * 1.6)
			c.draw_line(p.call(0.45, -0.35), p.call(0.1, 0.8), INK, w)
			c.draw_line(p.call(0.45, -0.35), p.call(0.8, 0.8), INK, w)
		"Sniper":
			# Crosshair.
			c.draw_arc(at, s * 0.75, 0.0, TAU, 20, INK, w, true)
			c.draw_line(p.call(-1.0, 0.0), p.call(1.0, 0.0), INK, w * 0.8)
			c.draw_line(p.call(0.0, -1.0), p.call(0.0, 1.0), INK, w * 0.8)
		"Medic":
			c.draw_rect(Rect2(p.call(-0.28, -0.9), Vector2(0.56, 1.8) * s), RED_CROSS)
			c.draw_rect(Rect2(p.call(-0.9, -0.28), Vector2(1.8, 0.56) * s), RED_CROSS)
		"Mortar":
			# A steep tube on its bipod and baseplate, a shell leaving the muzzle.
			c.draw_line(p.call(-0.45, 0.7), p.call(0.25, -0.65), INK, w * 1.8)
			c.draw_line(p.call(0.0, -0.15), p.call(0.6, 0.75), INK, w)
			c.draw_line(p.call(-0.85, 0.8), p.call(-0.05, 0.8), INK, w * 1.2)
			c.draw_circle(p.call(0.55, -0.9), s * 0.16, INK)
		"AT":
			# Rocket launcher tube with the warhead.
			c.draw_line(p.call(-0.95, 0.45), p.call(0.45, -0.25), INK, w * 2.0)
			c.draw_colored_polygon(PackedVector2Array([p.call(0.35, -0.55), p.call(1.0, -0.55), p.call(0.55, 0.05)]), INK)
		"Tank":
			c.draw_rect(Rect2(p.call(-1.0, -0.05), Vector2(2.0, 0.7) * s), INK)
			c.draw_rect(Rect2(p.call(-0.45, -0.5), Vector2(0.85, 0.45) * s), INK)
			c.draw_line(p.call(0.35, -0.3), p.call(1.05, -0.3), INK, w)
		"Grenadier":
			# The M79: a short, fat barrel on a wooden stock, its grenade arcing away.
			c.draw_line(p.call(-0.95, 0.75), p.call(-0.25, 0.3), INK, w * 1.4)
			c.draw_line(p.call(-0.3, 0.33), p.call(0.35, -0.08), INK, w * 2.4)
			c.draw_arc(p.call(0.75, 0.15), s * 0.55, PI * 1.05, PI * 1.6, 8, INK, w * 0.6, true)
			c.draw_circle(p.call(0.8, -0.55), s * 0.2, INK)
		"RTO":
			# A field radio with its whip antenna.
			c.draw_rect(Rect2(p.call(-0.7, -0.15), Vector2(1.1, 1.0) * s), INK)
			c.draw_circle(p.call(-0.35, 0.3), s * 0.13, BADGE)
			c.draw_line(p.call(-0.05, 0.12), p.call(0.2, 0.12), BADGE, maxf(1.0, w * 0.6))
			c.draw_line(p.call(0.2, -0.15), p.call(0.75, -1.0), INK, maxf(1.0, w * 0.6))
			c.draw_circle(p.call(0.75, -1.0), s * 0.1, INK)
		"Sapper":
			# A satchel charge: a strapped bundle with a burning fuse.
			c.draw_rect(Rect2(p.call(-0.85, -0.25), Vector2(1.3, 0.95) * s), INK)
			for x in [-0.42, 0.02]:
				c.draw_line(p.call(x, -0.25), p.call(x, 0.7), BADGE, maxf(1.0, w * 0.5))
			c.draw_line(p.call(-0.85, 0.22), p.call(0.45, 0.22), BADGE, maxf(1.0, w * 0.5))
			c.draw_polyline(PackedVector2Array([p.call(0.45, -0.1), p.call(0.7, -0.35), p.call(0.6, -0.65)]), INK, maxf(1.0, w * 0.6))
			c.draw_circle(p.call(0.62, -0.78), s * 0.18, Color("f0a43a"))
		"APC":
			# A box-shaped tracked carrier: sloping nose, flat roof, a gun on top.
			c.draw_colored_polygon(PackedVector2Array([p.call(-1.0, -0.45), p.call(0.4, -0.45), p.call(1.0, 0.05), p.call(1.0, 0.4),
				p.call(-1.0, 0.4)]), INK)
			c.draw_rect(Rect2(p.call(-0.95, 0.5), Vector2(1.9, 0.38) * s), INK)
			for x in [-0.6, -0.1, 0.4]:
				c.draw_circle(p.call(x, 0.69), s * 0.12, BADGE)
			c.draw_line(p.call(-0.2, -0.45), p.call(-0.2, -0.75), INK, w)
			c.draw_line(p.call(-0.2, -0.72), p.call(0.5, -0.72), INK, w * 0.8)
		"EOD":
			# A mine detector: the shaft with its handle and the flat round search head.
			c.draw_line(p.call(0.75, -0.9), p.call(-0.35, 0.5), INK, w)
			c.draw_line(p.call(0.75, -0.9), p.call(0.45, -0.95), INK, w * 1.3)
			c.draw_colored_polygon(PackedVector2Array([p.call(-0.95, 0.55), p.call(-0.6, 0.35), p.call(0.05, 0.6), p.call(-0.3, 0.85)]), INK)
			c.draw_line(p.call(0.4, -0.45), p.call(0.15, -0.65), INK, w * 0.8)
