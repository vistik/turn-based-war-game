extends SceneTree
## Renders every role for both sides in several poses to a PNG, to look at the soldier art.
##   Godot --path . -s tools/soldier_preview.gd -- [theatre] out.png [zoom] [detail] [lying] [german] [scroll=<px>] [page=<n>]
## With a theatre id first ("normandy", "vietnam"), each side's own roles are drawn (the sides may have
## different roles), followed by the theatre's vehicles from four directions and, for Vietnam, the Huey.
## Without one, the original Normandy roles are drawn. Needs a window (not --headless), since it renders.

const ROLES := ["Officer", "Rifleman", "SMG", "MG", "Sniper", "Medic", "Mortar", "AT"]
const POSES := ["stand", "walk", "crouch", "prone", "aim_left", "dead"]

var _out := "soldiers.png"
var _zoom := 3.0
## "" draws the original Normandy layout.
var _theatre := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and Theatres.exists(args[0]):
		_theatre = args[0]
		args = args.slice(1)
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1 and args[1].is_valid_float():
		_zoom = float(args[1])
	root.size = Vector2i(1600, 2000)
	var canvas := Node2D.new()
	canvas.scale = Vector2(_zoom, _zoom)
	canvas.position = Vector2(60, 40)
	for arg: String in args:
		if arg.begins_with("scroll="):
			canvas.position.y -= float(arg.trim_prefix("scroll=")) * _zoom
	canvas.draw.connect(_paint.bind(canvas))
	var bg := ColorRect.new()
	bg.color = Color("5f6b3a")
	bg.size = Vector2(4000, 4000)
	root.add_child(bg)
	root.add_child(canvas)
	_shoot.call_deferred()


## The roles drawn for a team: the original list, or the theatre's foot roles for that team.
func _roles(team: int) -> Array:
	if _theatre == "":
		return ROLES
	var theatre := Theatres.get_theatre(_theatre)
	return theatre.role_ids(team).filter(func(r: String) -> bool: return not theatre.role_def(team, r)["vehicle"])


func _unit(index: int, role: String, team: int) -> Unit:
	if _theatre == "":
		return Unit.create(index, "S", role, team, Vector2i.ZERO)
	return Unit.create(index, "S", role, team, Vector2i.ZERO, 0, _theatre)


func _pose(facing: Vector2, kind: String) -> Dictionary:
	return {"facing": facing, "walk": 1.0 if kind == "walk" else 0.0, "phase": 1.2, "crouch": kind == "crouch",
			"prone": kind == "prone", "pinned": false, "deployed": false, "wounded": false,
			"death": 1.0 if kind == "dead" else 0.0, "flash": 0.0, "breath": 0.0, "time": 0.0}


func _paint(c: Node2D) -> void:
	if OS.get_cmdline_user_args().has("detail"):
		_paint_detail(c)
		return
	var proj := ViewProjection.new(Vector2(100, 100))
	var origin := proj.project(Vector2(0, 0))
	for team in 2:
		var roles := _roles(team)
		for r in roles.size():
			for p in POSES.size():
				var u := _unit(r, roles[r], team)
				var pose := _pose(Vector2(1, 1).normalized() if POSES[p] != "aim_left" else Vector2(-1, 1).normalized(), POSES[p])
				var screen := Vector2(40 + r * 60, 50 + (team * POSES.size() + p) * 62)
				# A grid point whose projection lands on `screen`.
				var g := proj.unproject(screen - Vector2.ZERO) - proj.unproject(origin) + proj.unproject(origin)
				var ring := TerrainPainter.ground_circle(proj, g, 0.34)
				c.draw_colored_polygon(TerrainPainter.ground_circle(proj, g + TerrainPainter.LIGHT * 0.25, 0.26, false), Color(0, 0, 0, 0.3))
				c.draw_polyline(ring, Color(["9cc45a", "b8c0c8"][team], 0.6), 2.0)
				SoldierPainter.draw(c, proj, g, u, pose)
	if _theatre != "":
		_paint_vehicles(c, proj)


## Each vehicle role of the theatre from four directions (the last one burning), then the helicopter.
func _paint_vehicles(c: Node2D, proj: ViewProjection) -> void:
	var theatre := Theatres.get_theatre(_theatre)
	var row := 0
	var facings := [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 0)]
	for team in 2:
		for role: String in theatre.role_ids(team):
			if not theatre.role_def(team, role)["vehicle"]:
				continue
			for f in facings.size():
				var u := _unit(0, role, team)
				var pose := _pose((facings[f] as Vector2).normalized(), "dead" if f == facings.size() - 1 else "stand")
				var screen := Vector2(60 + f * 95, 50 + 12 * 62 + row * 90)
				var g := proj.unproject(screen)
				c.draw_colored_polygon(TerrainPainter.ground_circle(proj, g + TerrainPainter.LIGHT * 0.3, 0.55, false), Color(0, 0, 0, 0.3))
				VehiclePainter.draw(c, proj, g, u, pose)
			row += 1
	if _theatre == "vietnam":
		for f in 3:
			var g := proj.unproject(Vector2(90 + f * 150, 50 + 12 * 62 + row * 90 + 60))
			VehiclePainter.draw_helicopter(c, proj, g, (facings[f] as Vector2).normalized(), [1.5, 0.6, 0.0][f], 0.37 * f)


## Which five roles the theatre detail view shows ("page=1" for the sixth to tenth).
func _page() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("page="):
			return int(arg.trim_prefix("page="))
	return 0


func _shoot() -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out)
	print("saved ", _out)
	quit()


## A few roles up close, from four directions, standing, walking and crouched.
func _paint_detail(c: Node2D) -> void:
	var proj := ViewProjection.new(Vector2(100, 100))
	var facings := [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)]
	for team in 2:
		var side := 1 - team if OS.get_cmdline_user_args().has("german") else team
		var roles := ["Rifleman", "Officer", "MG", "Medic"] if _theatre == "" else _roles(side).slice(_page() * 5, _page() * 5 + 5)
		for r in roles.size():
			for f in facings.size():
				for p in 3:
					var lying := OS.get_cmdline_user_args().has("lying")
					var u := _unit(r, roles[r], side)
					var pose := {"facing": (facings[f] as Vector2).normalized(), "walk": 1.0 if p == 1 and not lying else 0.0, "phase": 1.2,
							"crouch": p == 2 and not lying, "prone": lying and p < 2, "pinned": false, "deployed": lying and p == 1, "wounded": false,
							"death": 1.0 if lying and p == 2 else 0.0, "flash": 0.0, "breath": 0.0, "time": 0.0}
					var screen := Vector2(30 + (f * 3 + p) * 34, 50 + (team * roles.size() + r) * 52)
					var g := proj.unproject(screen)
					c.draw_polyline(TerrainPainter.ground_circle(proj, g, 0.34), Color(["9cc45a", "b8c0c8"][team], 0.6), 1.5)
					SoldierPainter.draw(c, proj, g, u, pose)
