class_name ActionIcons
extends RefCounted
## Vector icons for the battle actions, drawn in a unit box (-1..1) scaled to `s` pixels and centred on `at`,
## in the same flat style as the role badges (RoleIcons).


## One look for every icon: drawn in ink only, filling the same box (about -0.85..0.85), with one stroke
## weight (`w`) for every line, and solid shapes for objects (grenade, magazine, mine).
static func draw(c: CanvasItem, at: Vector2, action: String, s: float, ink: Color) -> void:
	var p := func(x: float, y: float) -> Vector2: return at + Vector2(x, y) * s
	var w := maxf(1.5, s * 0.14)
	match action:
		"shoot":
			# Crosshair.
			c.draw_arc(at, s * 0.6, 0.0, TAU, 32, ink, w, true)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				c.draw_line(at + d * s * 0.3, at + d * s * 0.85, ink, w)
			c.draw_circle(at, w * 0.6, ink)
		"suppress":
			# A burst: three tracers fanning out from a muzzle.
			c.draw_rect(Rect2(p.call(-0.85, -0.16), Vector2(0.4, 0.32) * s), ink)
			for dy: float in [-0.68, 0.0, 0.68]:
				var from: Vector2 = p.call(-0.4, dy * 0.12)
				var tip: Vector2 = p.call(0.62, dy)
				c.draw_line(from, tip, ink, w)
				c.draw_circle(tip + (tip - from).normalized() * s * 0.13, w * 0.95, ink)
		"overwatch":
			# An eye.
			var lid := PackedVector2Array()
			for i in 17:
				var t := i / 16.0
				lid.append(p.call(lerpf(-0.85, 0.85, t), -sin(t * PI) * 0.55))
			for i in 17:
				var t := i / 16.0
				lid.append(p.call(lerpf(0.85, -0.85, t), sin(t * PI) * 0.55))
			c.draw_polyline(lid, ink, w, true)
			c.draw_circle(at, s * 0.28, ink)
		"reload":
			# A magazine and a circling arrow.
			c.draw_rect(Rect2(p.call(-0.2, -0.45), Vector2(0.4, 0.9) * s), ink)
			c.draw_arc(at, s * 0.78, -PI * 0.3, PI * 1.2, 28, ink, w, true)
			var tip: Vector2 = p.call(cos(-PI * 0.3) * 0.78, sin(-PI * 0.3) * 0.78)
			c.draw_colored_polygon(PackedVector2Array([tip + Vector2(-0.32, -0.2) * s, tip + Vector2(0.2, 0.3) * s, tip + Vector2(0.25, -0.32) * s]), ink)
		"grenade":
			# A pineapple grenade with its lever and pin ring.
			c.draw_circle(p.call(0, 0.22), s * 0.6, ink)
			c.draw_rect(Rect2(p.call(-0.22, -0.62), Vector2(0.44, 0.3) * s), ink)
			c.draw_line(p.call(0.18, -0.55), p.call(0.62, 0.02), ink, w)
			c.draw_arc(p.call(-0.5, -0.62), s * 0.2, 0.0, TAU, 16, ink, w, true)
		"smoke":
			# Billowing puffs.
			for puff: Array in [[-0.42, 0.4, 0.42], [0.3, 0.42, 0.42], [-0.08, -0.12, 0.45], [0.52, -0.3, 0.32], [-0.55, -0.45, 0.3]]:
				c.draw_circle(p.call(puff[0], puff[1]), s * puff[2], ink)
		"rally":
			# A flag on a pole.
			c.draw_line(p.call(-0.55, -0.85), p.call(-0.55, 0.85), ink, w)
			c.draw_colored_polygon(PackedVector2Array([p.call(-0.55, -0.85), p.call(0.85, -0.5), p.call(-0.55, -0.1)]), ink)
			c.draw_line(p.call(-0.85, 0.85), p.call(-0.25, 0.85), ink, w)
		"medkit":
			# A first-aid box with a cross.
			c.draw_rect(Rect2(p.call(-0.78, -0.62), Vector2(1.56, 1.4) * s), ink, false, w)
			c.draw_line(p.call(-0.3, -0.62), p.call(-0.3, -0.85), ink, w)
			c.draw_line(p.call(0.3, -0.62), p.call(0.3, -0.85), ink, w)
			c.draw_line(p.call(-0.3, -0.85), p.call(0.3, -0.85), ink, w)
			c.draw_rect(Rect2(p.call(-0.14, -0.38), Vector2(0.28, 0.92) * s), ink)
			c.draw_rect(Rect2(p.call(-0.46, -0.06), Vector2(0.92, 0.28) * s), ink)
		"mortar":
			# The tube on its bipod and baseplate, and the shell's arc.
			c.draw_line(p.call(-0.62, 0.7), p.call(-0.2, -0.2), ink, w * 2.0)
			c.draw_line(p.call(-0.38, 0.2), p.call(-0.05, 0.8), ink, w)
			c.draw_line(p.call(-0.85, 0.8), p.call(-0.35, 0.8), ink, w)
			var arc := PackedVector2Array()
			for i in 13:
				var t := i / 12.0
				arc.append(p.call(lerpf(-0.12, 0.8, t), lerpf(-0.4, 0.55, t) - sin(t * PI) * 0.5))
			c.draw_polyline(arc, ink, w, true)
			c.draw_circle(p.call(0.8, 0.62), w * 1.1, ink)
		"stand":
			_figure(c, p, w, s, ink, "stand")
		"prone":
			_figure(c, p, w, s, ink, "prone")
		"clear_mine":
			# A mine with a probe reaching for it.
			c.draw_rect(Rect2(p.call(-0.75, 0.35), Vector2(1.5, 0.45) * s), ink)
			c.draw_rect(Rect2(p.call(-0.28, 0.12), Vector2(0.56, 0.23) * s), ink)
			c.draw_line(p.call(-0.85, -0.85), p.call(0.15, 0.0), ink, w)
		"tunnel":
			# A tunnel mouth: a hole in the ground with an arrow going down into it.
			c.draw_colored_polygon(PackedVector2Array([p.call(-0.85, 0.35), p.call(0.85, 0.35), p.call(0.55, 0.85), p.call(-0.55, 0.85)]), ink)
			c.draw_line(p.call(0.0, -0.85), p.call(0.0, 0.0), ink, w)
			c.draw_colored_polygon(PackedVector2Array([p.call(-0.35, -0.15), p.call(0.35, -0.15), p.call(0.0, 0.2)]), ink)
		"trap":
			# Sharpened stakes in a pit.
			c.draw_polyline(PackedVector2Array([p.call(-0.85, 0.15), p.call(-0.68, 0.85), p.call(0.68, 0.85), p.call(0.85, 0.15)]), ink, w)
			for x: float in [-0.42, 0.0, 0.42]:
				c.draw_colored_polygon(PackedVector2Array([p.call(x - 0.14, 0.8), p.call(x + 0.14, 0.8), p.call(x, -0.75)]), ink)
		"detonate":
			# A detonator: a box with a plunger, and a spark.
			c.draw_rect(Rect2(p.call(-0.65, 0.05), Vector2(1.3, 0.8) * s), ink)
			c.draw_line(p.call(-0.15, 0.05), p.call(-0.15, -0.55), ink, w)
			c.draw_line(p.call(-0.55, -0.55), p.call(0.25, -0.55), ink, w)
			for i in 4:
				var dir := Vector2.from_angle(i * TAU / 4 + 0.4)
				c.draw_line(p.call(0.62, -0.62) + dir * s * 0.1, p.call(0.62, -0.62) + dir * s * 0.26, ink, w * 0.8)
		"hold":
			# Hold: a hand raised, palm out.
			c.draw_rect(Rect2(p.call(-0.45, -0.1), Vector2(0.9, 0.8) * s), ink)
			for x: float in [-0.38, -0.12, 0.14, 0.4]:
				c.draw_line(p.call(x, -0.05), p.call(x, -0.75 if absf(x) < 0.3 else -0.6), ink, w * 1.3)
			c.draw_line(p.call(-0.45, 0.25), p.call(-0.8, -0.15), ink, w * 1.3)
		"next":
			# Next soldier: a double chevron.
			c.draw_polyline(PackedVector2Array([p.call(-0.65, -0.65), p.call(-0.05, 0.0), p.call(-0.65, 0.65)]), ink, w)
			c.draw_polyline(PackedVector2Array([p.call(0.05, -0.65), p.call(0.65, 0.0), p.call(0.05, 0.65)]), ink, w)
		"end":
			# End turn: an hourglass.
			c.draw_line(p.call(-0.65, -0.85), p.call(0.65, -0.85), ink, w)
			c.draw_line(p.call(-0.65, 0.85), p.call(0.65, 0.85), ink, w)
			c.draw_colored_polygon(PackedVector2Array([p.call(-0.55, -0.78), p.call(0.55, -0.78), p.call(0.0, 0.0)]), ink)
			c.draw_colored_polygon(PackedVector2Array([p.call(0.0, 0.0), p.call(0.55, 0.78), p.call(-0.55, 0.78)]), ink)
		"suggest":
			# A light bulb.
			c.draw_circle(p.call(0, -0.25), s * 0.55, ink)
			c.draw_rect(Rect2(p.call(-0.25, 0.25), Vector2(0.5, 0.42) * s), ink)
			c.draw_line(p.call(-0.22, 0.82), p.call(0.22, 0.82), ink, w)


## A little soldier standing or lying down, on the ground line.
static func _figure(c: CanvasItem, p: Callable, w: float, s: float, ink: Color, pose: String) -> void:
	match pose:
		# A solid body (twice the stroke) and limbs at the usual stroke, so the figure carries as much ink as
		# the other icons.
		"stand":
			c.draw_circle(p.call(0, -0.64), s * 0.22, ink)
			c.draw_line(p.call(0, -0.4), p.call(0, 0.22), ink, w * 2.0)
			c.draw_line(p.call(0, 0.15), p.call(-0.32, 0.82), ink, w * 1.3)
			c.draw_line(p.call(0, 0.15), p.call(0.32, 0.82), ink, w * 1.3)
			c.draw_line(p.call(0, -0.25), p.call(0.6, -0.05), ink, w)
		"prone":
			c.draw_circle(p.call(0.6, 0.4), s * 0.22, ink)
			c.draw_line(p.call(0.38, 0.6), p.call(-0.38, 0.66), ink, w * 2.0)
			c.draw_line(p.call(-0.32, 0.66), p.call(-0.85, 0.76), ink, w * 1.3)
			c.draw_line(p.call(0.3, 0.6), p.call(0.85, 0.48), ink, w)
	c.draw_line(p.call(-0.85, 0.88), p.call(0.85, 0.88), Color(ink, ink.a * 0.4), w * 0.6)
