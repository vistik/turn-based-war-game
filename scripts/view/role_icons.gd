class_name RoleIcons
extends RefCounted
## Small vector icons for each role, drawn in a round badge ringed in the team colour, so roles read at a
## glance above the units. Icons are drawn in a unit box (-1..1) scaled to the badge.

const INK := Color("ece6d2")
const BADGE := Color(0.07, 0.07, 0.06, 0.85)
const RED_CROSS := Color("d0342c")


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
