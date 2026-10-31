class_name ActionIcons
extends RefCounted
## Vector icons for the battle actions, drawn in a unit box (-1..1) scaled to `s` pixels and centred on `at`,
## in the same flat style as the role badges (RoleIcons).

const RED_CROSS := Color("d0342c")


static func draw(c: CanvasItem, at: Vector2, action: String, s: float, ink: Color) -> void:
	var p := func(x: float, y: float) -> Vector2: return at + Vector2(x, y) * s
	var w := maxf(1.5, s * 0.13)
	match action:
		"shoot":
			# Crosshair.
			c.draw_arc(at, s * 0.62, 0.0, TAU, 28, ink, w, true)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				c.draw_line(at + d * s * 0.35, at + d * s * 0.95, ink, w)
			c.draw_circle(at, w * 0.7, ink)
		"aimed":
			# A scope: crosshair in a heavy ring, steadied.
			c.draw_arc(at, s * 0.72, 0.0, TAU, 28, ink, w * 1.6, true)
			c.draw_arc(at, s * 0.3, 0.0, TAU, 20, ink, w * 0.8, true)
			c.draw_line(p.call(-0.72, 0), p.call(0.72, 0), ink, w * 0.7)
			c.draw_line(p.call(0, -0.72), p.call(0, 0.72), ink, w * 0.7)
		"overwatch":
			# An eye.
			var lid := PackedVector2Array()
			for i in 17:
				var t := i / 16.0
				lid.append(p.call(lerpf(-0.95, 0.95, t), -sin(t * PI) * 0.55))
			for i in 17:
				var t := i / 16.0
				lid.append(p.call(lerpf(0.95, -0.95, t), sin(t * PI) * 0.55))
			c.draw_polyline(lid, ink, w, true)
			c.draw_circle(at, s * 0.27, ink)
		"hunker":
			# A helmet ducked behind a wall.
			c.draw_rect(Rect2(p.call(-0.95, 0.15), Vector2(1.9, 0.75) * s), ink)
			var helmet := PackedVector2Array()
			for i in 13:
				var a := PI + PI * i / 12.0
				helmet.append(p.call(cos(a) * 0.55, 0.05 + sin(a) * 0.5))
			c.draw_colored_polygon(helmet, ink)
		"reload":
			# A magazine and a circling arrow.
			c.draw_rect(Rect2(p.call(-0.22, -0.55), Vector2(0.44, 1.1) * s), ink)
			c.draw_arc(at, s * 0.82, -PI * 0.35, PI * 1.15, 24, ink, w, true)
			var tip: Vector2 = p.call(cos(-PI * 0.35) * 0.82, sin(-PI * 0.35) * 0.82)
			c.draw_colored_polygon(PackedVector2Array([tip + Vector2(-0.3, -0.15) * s, tip + Vector2(0.15, 0.28) * s, tip + Vector2(0.22, -0.3) * s]), ink)
		"grenade":
			# A pineapple grenade with its lever and pin ring.
			c.draw_circle(p.call(0, 0.2), s * 0.55, ink)
			c.draw_rect(Rect2(p.call(-0.2, -0.55), Vector2(0.4, 0.3) * s), ink)
			c.draw_line(p.call(0.15, -0.5), p.call(0.55, 0.1), ink, w)
			c.draw_arc(p.call(-0.42, -0.6), s * 0.2, 0.0, TAU, 14, ink, w * 0.7, true)
		"smoke":
			# Billowing puffs.
			for puff: Array in [[-0.45, 0.35, 0.38], [0.2, 0.4, 0.42], [-0.1, -0.15, 0.4], [0.5, -0.25, 0.3], [-0.55, -0.45, 0.25]]:
				c.draw_circle(p.call(puff[0], puff[1]), s * puff[2], ink)
		"set_up":
			# A machine gun on its bipod.
			c.draw_line(p.call(-0.95, -0.25), p.call(0.95, -0.25), ink, w * 1.8)
			c.draw_line(p.call(-0.95, -0.25), p.call(-0.95, 0.15), ink, w * 1.6)
			c.draw_line(p.call(0.45, -0.25), p.call(0.1, 0.8), ink, w)
			c.draw_line(p.call(0.45, -0.25), p.call(0.8, 0.8), ink, w)
		"rally":
			# A flag on a pole.
			c.draw_line(p.call(-0.6, -0.9), p.call(-0.6, 0.95), ink, w)
			c.draw_colored_polygon(PackedVector2Array([p.call(-0.6, -0.9), p.call(0.85, -0.6), p.call(-0.6, -0.15)]), ink)
		"medkit":
			c.draw_rect(Rect2(p.call(-0.85, -0.85), Vector2(1.7, 1.7) * s), ink)
			c.draw_rect(Rect2(p.call(-0.17, -0.6), Vector2(0.34, 1.2) * s), RED_CROSS)
			c.draw_rect(Rect2(p.call(-0.6, -0.17), Vector2(1.2, 0.34) * s), RED_CROSS)
		"mortar":
			# The tube on its bipod, and the shell's arc.
			c.draw_line(p.call(-0.6, 0.8), p.call(-0.05, -0.15), ink, w * 1.8)
			c.draw_line(p.call(-0.3, 0.3), p.call(0.05, 0.8), ink, w * 0.8)
			c.draw_line(p.call(-0.9, 0.85), p.call(-0.25, 0.85), ink, w)
			var arc := PackedVector2Array()
			for i in 9:
				var t := i / 8.0
				arc.append(p.call(lerpf(0.05, 0.9, t), -0.25 - sin(t * PI) * 0.6 + t * 0.9))
			c.draw_polyline(arc, ink, w * 0.7, true)
		"pivot":
			# A turning arrow round a hull.
			c.draw_rect(Rect2(p.call(-0.3, -0.42), Vector2(0.6, 0.84) * s), ink)
			c.draw_arc(at, s * 0.82, PI * 0.15, PI * 1.6, 24, ink, w, true)
			var tip: Vector2 = p.call(cos(PI * 1.6) * 0.82, sin(PI * 1.6) * 0.82)
			c.draw_colored_polygon(PackedVector2Array([tip + Vector2(-0.32, -0.12) * s, tip + Vector2(0.28, -0.22) * s, tip + Vector2(0.0, 0.3) * s]), ink)
		"crouch":
			_figure(c, p, w, ink, "crouch")
		"stand":
			_figure(c, p, w, ink, "stand")
		"prone":
			_figure(c, p, w, ink, "prone")
		"suppress":
			# A burst: three tracers fanning out.
			for dy in [-0.5, 0.0, 0.5]:
				c.draw_line(p.call(-0.9, dy * 0.4), p.call(0.55, dy), ink, w)
				c.draw_circle(p.call(0.7, dy * 1.1), w * 0.9, ink)
		"clear_mine":
			# A mine with a probe across it.
			c.draw_rect(Rect2(p.call(-0.75, 0.15), Vector2(1.5, 0.45) * s), ink)
			c.draw_rect(Rect2(p.call(-0.25, -0.05), Vector2(0.5, 0.25) * s), ink)
			c.draw_line(p.call(-0.85, -0.85), p.call(0.15, 0.0), ink, w)
		"next":
			# Next soldier: chevron to a figure.
			c.draw_polyline(PackedVector2Array([p.call(-0.6, -0.6), p.call(0.0, 0.0), p.call(-0.6, 0.6)]), ink, w * 1.4)
			c.draw_polyline(PackedVector2Array([p.call(0.1, -0.6), p.call(0.7, 0.0), p.call(0.1, 0.6)]), ink, w * 1.4)
		"end":
			# End turn: an hourglass.
			c.draw_colored_polygon(PackedVector2Array([p.call(-0.6, -0.85), p.call(0.6, -0.85), p.call(0.0, 0.0)]), ink)
			c.draw_colored_polygon(PackedVector2Array([p.call(0.0, 0.0), p.call(0.6, 0.85), p.call(-0.6, 0.85)]), ink)
		"suggest":
			# A light bulb.
			c.draw_circle(p.call(0, -0.2), s * 0.55, ink)
			c.draw_rect(Rect2(p.call(-0.25, 0.3), Vector2(0.5, 0.45) * s), ink)
			c.draw_line(p.call(-0.25, 0.85), p.call(0.25, 0.85), ink, w)


## A little soldier standing, crouching or lying down.
static func _figure(c: CanvasItem, p: Callable, w: float, ink: Color, pose: String) -> void:
	match pose:
		"stand":
			c.draw_circle(p.call(0, -0.72), w * 1.6, ink)
			c.draw_line(p.call(0, -0.5), p.call(0, 0.25), ink, w * 1.5)
			c.draw_line(p.call(0, 0.25), p.call(-0.3, 0.92), ink, w)
			c.draw_line(p.call(0, 0.25), p.call(0.3, 0.92), ink, w)
			c.draw_line(p.call(0, -0.3), p.call(0.5, -0.1), ink, w)
		"crouch":
			c.draw_circle(p.call(0.1, -0.35), w * 1.6, ink)
			c.draw_line(p.call(0.05, -0.15), p.call(-0.2, 0.4), ink, w * 1.5)
			c.draw_line(p.call(-0.2, 0.4), p.call(0.3, 0.45), ink, w)
			c.draw_line(p.call(0.3, 0.45), p.call(0.3, 0.9), ink, w)
			c.draw_line(p.call(-0.2, 0.4), p.call(-0.45, 0.9), ink, w)
			c.draw_line(p.call(0.0, 0.0), p.call(0.6, 0.1), ink, w)
		"prone":
			c.draw_circle(p.call(0.7, 0.3), w * 1.6, ink)
			c.draw_line(p.call(0.5, 0.45), p.call(-0.3, 0.55), ink, w * 1.5)
			c.draw_line(p.call(-0.3, 0.55), p.call(-0.95, 0.65), ink, w)
			c.draw_line(p.call(0.4, 0.5), p.call(0.95, 0.6), ink, w)
	c.draw_line(p.call(-1.0, 0.95), p.call(1.0, 0.95), Color(ink, 0.35), w * 0.6)
