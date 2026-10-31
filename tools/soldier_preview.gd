extends SceneTree
## Renders every role for both sides in several poses to a PNG, to look at the soldier art.
##   Godot --path . -s tools/soldier_preview.gd -- out.png [zoom]
## Needs a window (not --headless), since it renders.

const ROLES := ["Officer", "Rifleman", "SMG", "MG", "Sniper", "Medic", "Mortar", "AT"]
const POSES := ["stand", "walk", "crouch", "prone", "aim_left", "dead"]

var _out := "soldiers.png"
var _zoom := 3.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_zoom = float(args[1])
	root.size = Vector2i(1600, 2000)
	var canvas := Node2D.new()
	canvas.scale = Vector2(_zoom, _zoom)
	canvas.position = Vector2(60, 40)
	canvas.draw.connect(_paint.bind(canvas))
	var bg := ColorRect.new()
	bg.color = Color("5f6b3a")
	bg.size = Vector2(4000, 4000)
	root.add_child(bg)
	root.add_child(canvas)
	_shoot.call_deferred()


func _paint(c: Node2D) -> void:
	if OS.get_cmdline_user_args().has("detail"):
		_paint_detail(c)
		return
	var proj := ViewProjection.new(Vector2(100, 100))
	var origin := proj.project(Vector2(0, 0))
	for team in 2:
		for r in ROLES.size():
			for p in POSES.size():
				var u := Unit.create(r, "S", ROLES[r], team, Vector2i.ZERO)
				var pose := {"facing": Vector2(1, 1).normalized() if POSES[p] != "aim_left" else Vector2(-1, 1).normalized(),
						"walk": 1.0 if POSES[p] == "walk" else 0.0, "phase": 1.2, "crouch": POSES[p] == "crouch",
						"prone": POSES[p] == "prone", "pinned": false, "deployed": false, "wounded": false,
						"death": 1.0 if POSES[p] == "dead" else 0.0, "flash": 0.0, "breath": 0.0, "time": 0.0}
				var screen := Vector2(40 + r * 60, 50 + (team * POSES.size() + p) * 62)
				# A grid point whose projection lands on `screen`.
				var g := proj.unproject(screen - Vector2.ZERO) - proj.unproject(origin) + proj.unproject(origin)
				var ring := TerrainPainter.ground_circle(proj, g, 0.34)
				c.draw_colored_polygon(TerrainPainter.ground_circle(proj, g + TerrainPainter.LIGHT * 0.25, 0.26, false), Color(0, 0, 0, 0.3))
				c.draw_polyline(ring, Color(["9cc45a", "b8c0c8"][team], 0.6), 2.0)
				SoldierPainter.draw(c, proj, g, u, pose)


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
	var roles := ["Rifleman", "Officer", "MG", "Medic"]
	for team in 2:
		for r in roles.size():
			for f in facings.size():
				for p in 3:
					var lying := OS.get_cmdline_user_args().has("lying")
					var side := 1 - team if OS.get_cmdline_user_args().has("german") else team
					var u := Unit.create(r, "S", roles[r], side, Vector2i.ZERO)
					var pose := {"facing": (facings[f] as Vector2).normalized(), "walk": 1.0 if p == 1 and not lying else 0.0, "phase": 1.2,
							"crouch": p == 2 and not lying, "prone": lying and p < 2, "pinned": false, "deployed": lying and p == 1, "wounded": false,
							"death": 1.0 if lying and p == 2 else 0.0, "flash": 0.0, "breath": 0.0, "time": 0.0}
					var screen := Vector2(30 + (f * 3 + p) * 34, 50 + (team * roles.size() + r) * 52)
					var g := proj.unproject(screen)
					c.draw_polyline(TerrainPainter.ground_circle(proj, g, 0.34), Color(["9cc45a", "b8c0c8"][team], 0.6), 1.5)
					SoldierPainter.draw(c, proj, g, u, pose)
