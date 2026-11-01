extends Node2D
## The map and scenario editor. Paint ground, place cover, walls, hedges and fences, both sides' units,
## objectives and reinforcement spawns on the same isometric view the battles use; set the rules; save and
## load scenario files (user://scenarios/), play them, or let the AI play a few games to check the balance.
## With mirroring on, every edit is copied onto the other half of the map, so both sides get the same ground.
##
## Mouse: left paints or places, right removes, middle drag pans, wheel zooms. Keys: Q/E rotate, V iso or
## top-down, WASD/arrows pan, 1-7 pick a tool, R turns the selected unit, Ctrl+Z undoes, Ctrl+S saves.

const DrawLayer := preload("res://scripts/view/draw_layer.gd")

enum Tool { TERRAIN, OBJECT, EDGE, UNIT, OBJECTIVE, SPAWN, ERASE }
const TOOL_NAMES := ["Ground", "Objects", "Walls", "Units", "Objectives", "Spawns", "Erase"]
const TOOL_HINTS := [
	"Left paints the ground, right paints grass.",
	"Left places, right removes.",
	"Point at a tile's side. Left builds, right knocks down. Hedges and walls block sight; windows, low stone walls and fences give half cover.",
	"Left on an empty tile places a unit, on a unit selects it. Right removes. R turns the selected unit.",
	"Left on an empty spot adds an objective, inside one selects it. Right removes.",
	"Reinforcements arrive on these tiles. Left adds a tile to the selected wave, right removes it.",
	"Clears objects, walls, units and spawns under the brush.",
]
const PANEL_WIDTH := 360.0
const NEUTRAL := Color("e8e2cf")
const MUTED := Color(1, 1, 1, 0.6)
const BAD := Color("ff7a6a")
const GOOD := Color("8fe08a")
## "mine" isn't an object: it buries a mine (hidden from both sides in play) instead.
const OBJECT_KINDS := ["tree", "rock", "sandbags", "crate", "hay", "pew", "fuel", "oil_tank", "palm", "bamboo", "rice_sacks", "car", "hesco", "jersey", "mine"]
const EDGE_KINDS := ["hedge", "wall", "window", "stone", "fence", "dyke", "bamboo_wall", "bamboo_window", "mud_wall", "mud_window"]
const BRUSHES := [1, 2, 3, 5, 9]
const NEW_SIZES := [24, 32, 44, 48, 64, 84]
const CHUNK := 8
const GROUND_Z := -4
const SHADOW_Z := -3
const OVERLAY_Z := -1
const DEPTH_Z := 40.0
const TOP_Z := 4000
const ZOOM_MIN := 0.25
const ZOOM_MAX := 2.5
const PAN_SPEED := 800.0
const UNDO_LIMIT := 40

## The scenario being edited and the file it came from. Static, so it's still here after playing it.
static var edited: Scenario
static var edited_path := ""

var _s: Scenario
var _proj: ViewProjection
var _camera: Camera2D
var _font: Font
## Chunk -> [ground layer, shadow layer]; chunks waiting to be repainted.
var _chunks := {}
var _dirty := {}
## Tile -> prop node; edge key -> prop node.
var _object_nodes := {}
var _edge_nodes := {}
var _unit_nodes: Array[Node2D] = []
var _overlay: Node2D
var _faded := {}

var _tool := Tool.TERRAIN
var _terrain: int = TacticalMap.Terrain.ROAD
var _object_kind := "tree"
var _edge_kind := "hedge"
var _brush := 1
var _team := 0
var _role := "Rifleman"
var _facing := "E"
var _hover := Vector2i(-1, -1)
## The hovered tile side: [tile, direction].
var _hover_edge := [Vector2i(-1, -1), Vector2i.ZERO]
## The grid point under the mouse.
var _hover_point := Vector2(-1, -1)
## 0 idle, 1 painting with the left button, 2 removing with the right.
var _stroke := 0
var _stroke_last := ""
var _dragging := false
var _selected_unit := -1
var _selected_objective := -1
var _wave := 0
var _undo: Array[Dictionary] = []
var _batch: BalanceSim.Batch
var _batch_started := 0
var _batch_shown := -1

var _status: Label
var _problems: Label
var _tool_buttons: Array[Button] = []
var _options: VBoxContainer
var _hint: Label
var _title_edit: LineEdit
var _file_edit: LineEdit
var _load_choice: OptionButton
var _size_choice: OptionButton
var _vp_spin: SpinBox
var _rounds_spin: SpinBox
var _mirror_check: CheckBox
var _briefing_edit: TextEdit
var _wave_choice: OptionButton
var _wave_box: VBoxContainer
var _games_spin: SpinBox
## The theatre new maps are made in.
var _theatre_choice: OptionButton
var _sim_button: Button
var _sim_label: Label
var _panel: PanelContainer
## Set while widgets are filled from the scenario, so their change signals don't write back.
var _syncing := false


func _ready() -> void:
	_font = ThemeDB.fallback_font
	z_index = TOP_Z
	_camera = Camera2D.new()
	_camera.zoom = Vector2(0.7, 0.7)
	add_child(_camera)
	_build_ui()
	if edited == null:
		edited = Scenario.create(32, 32)
		edited.title = "New scenario"
		edited_path = ""
	_open(edited, edited_path)


func _exit_tree() -> void:
	_stop_sim()


## Starts editing a scenario: rebuilds the whole picture and fills in the panel.
func _open(scenario: Scenario, path: String) -> void:
	_s = scenario
	edited = scenario
	edited_path = path
	TerrainPainter.use_theatre(scenario.theatre_id)
	_selected_unit = -1
	_selected_objective = -1
	_wave = clampi(_wave, 0, maxi(0, _s.reinforcements.size() - 1))
	var rotation := _proj.rotation if _proj != null else 0
	var iso := _proj.isometric if _proj != null else true
	_proj = ViewProjection.new(Vector2(_s.map.width, _s.map.height))
	_proj.rotation = rotation
	_proj.isometric = iso
	_rebuild_all()
	_focus(Vector2(_s.map.width, _s.map.height) * 0.5)
	_sync_panel()


# --- Picture ---

func _layer(z: int, painter: Callable) -> Node2D:
	var layer: Node2D = DrawLayer.new()
	layer.z_as_relative = false
	layer.z_index = z
	layer.painter = painter
	add_child(layer)
	return layer


func _depth_z(g: Vector2, bias := 0.0) -> int:
	return clampi(1 + int((_proj.depth(g) + bias) * DEPTH_Z), 1, TOP_Z - 10)


func _rebuild_all() -> void:
	for chunk: Vector2i in _chunks:
		for node: Node2D in _chunks[chunk]:
			node.queue_free()
	_chunks.clear()
	_dirty.clear()
	for node: Node2D in _object_nodes.values() + _edge_nodes.values():
		node.queue_free()
	_object_nodes.clear()
	_edge_nodes.clear()
	_faded.clear()
	if _overlay != null:
		_overlay.queue_free()
	for cy in ceili(_s.map.height / float(CHUNK)):
		for cx in ceili(_s.map.width / float(CHUNK)):
			var chunk := Vector2i(cx, cy)
			_chunks[chunk] = [_layer(GROUND_Z, _paint_ground.bind(chunk)), _layer(SHADOW_Z, _paint_shadows.bind(chunk))]
	for y in _s.map.height:
		for x in _s.map.width:
			_sync_object(Vector2i(x, y))
	for key: Vector3i in _s.map.get_edges():
		_sync_edge(key)
	_overlay = _layer(OVERLAY_Z, _paint_overlay)
	_rebuild_units()


## After a rotation or view toggle everything is re-recorded and re-sorted.
func _reproject() -> void:
	for chunk: Vector2i in _chunks:
		for node: Node2D in _chunks[chunk]:
			node.queue_redraw()
	for node: Node2D in _object_nodes.values() + _edge_nodes.values():
		node.z_index = _depth_z(node.get_meta("center"))
		node.queue_redraw()
	_rebuild_units()


func _paint_ground(c: CanvasItem, chunk: Vector2i) -> void:
	for p in _chunk_tiles(chunk):
		TerrainPainter.draw_tile(c, _proj, _s.map, p)
		c.draw_polyline(_tile_outline(p), Color(0, 0, 0, 0.1), 1.0)


func _paint_shadows(c: CanvasItem, chunk: Vector2i) -> void:
	for p in _chunk_tiles(chunk):
		if _s.map.get_object(p) != Cover.NONE:
			TerrainPainter.draw_object_shadow(c, _proj, _s.map, p)
	for key: Vector3i in _s.map.get_edges():
		if Vector2i(key.x, key.y) / CHUNK == chunk:
			TerrainPainter.draw_edge_shadow(c, _proj, _s.map, key)


func _chunk_tiles(chunk: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for y in range(chunk.y * CHUNK, mini((chunk.y + 1) * CHUNK, _s.map.height)):
		for x in range(chunk.x * CHUNK, mini((chunk.x + 1) * CHUNK, _s.map.width)):
			tiles.append(Vector2i(x, y))
	return tiles


## A tile changed: repaint its chunk (and neighbours, for shadows across the border) and its props.
func _touch(p: Vector2i) -> void:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var chunk := (p + Vector2i(dx, dy)) / CHUNK
			if _chunks.has(chunk):
				_dirty[chunk] = true
	_sync_object(p)
	for key in [Vector3i(p.x, p.y, 0), Vector3i(p.x, p.y, 1), Vector3i(p.x - 1, p.y, 0), Vector3i(p.x, p.y - 1, 1)]:
		_sync_edge(key)


func _sync_object(p: Vector2i) -> void:
	if _object_nodes.has(p):
		_object_nodes[p].queue_free()
		_object_nodes.erase(p)
		_faded.erase(p)
	if _s.map.get_object(p) != Cover.NONE:
		var center := Vector2(p) + Vector2(0.5, 0.5)
		var node := _layer(_depth_z(center), func(c: CanvasItem) -> void: TerrainPainter.draw_object(c, _proj, _s.map, p, 1.0, false))
		node.set_meta("center", center)
		_object_nodes[p] = node


func _sync_edge(key: Vector3i) -> void:
	if _edge_nodes.has(key):
		_edge_nodes[key].queue_free()
		_edge_nodes.erase(key)
		_faded.erase(key)
	if _s.map.get_edges().has(key):
		var pair := TacticalMap.edge_tiles(key)
		var center := (Vector2(pair[0]) + Vector2(pair[1])) * 0.5 + Vector2(0.5, 0.5)
		var node := _layer(_depth_z(center), func(c: CanvasItem) -> void: TerrainPainter.draw_edge(c, _proj, _s.map, key, 1.0, false))
		node.set_meta("center", center)
		_edge_nodes[key] = node


func _rebuild_units() -> void:
	for node in _unit_nodes:
		node.queue_free()
	_unit_nodes.clear()
	for i in _s.units.size():
		var entry: Dictionary = _s.units[i]
		var center := Vector2(entry["pos"]) + Vector2(0.5, 0.5)
		_unit_nodes.append(_layer(_depth_z(center, 0.05), _paint_unit.bind(i)))
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _paint_unit(c: CanvasItem, i: int) -> void:
	if i >= _s.units.size():
		return
	var entry: Dictionary = _s.units[i]
	var u := Unit.create(i, "", entry["role"], entry["team"], entry["pos"], entry["rank"], _s.theatre_id)
	u.facing = entry["facing"]
	var g := Vector2(u.pos) + Vector2(0.5, 0.5)
	var pose := {"facing": Vector2(u.facing).normalized(), "walk": 0.0, "phase": 0.0, "crouch": false, "pinned": false,
			"deployed": false, "wounded": false, "death": 0.0, "flash": 0.0, "breath": i * 1.7, "time": 0.0}
	var radius := 0.6 if u.vehicle else 0.4
	c.draw_colored_polygon(TerrainPainter.ground_circle(_proj, g + TerrainPainter.LIGHT * 0.25, radius * 0.65, false), Color(0, 0, 0, 0.3))
	c.draw_polyline(TerrainPainter.ground_circle(_proj, g, radius), Color.WHITE if i == _selected_unit else _team_color(u.team), 3.0 if i == _selected_unit else 1.5)
	if u.vehicle:
		VehiclePainter.draw(c, _proj, g, u, pose)
	else:
		SoldierPainter.draw(c, _proj, g, u, pose)


## Ground markings: brush, hovered wall, objectives, spawns, the centre line and the map border.
func _paint_overlay(c: CanvasItem) -> void:
	var w := _s.map.width
	var h := _s.map.height
	var border := PackedVector2Array([_proj.project(Vector2(0, 0)), _proj.project(Vector2(w, 0)), _proj.project(Vector2(w, h)), _proj.project(Vector2(0, h)), _proj.project(Vector2(0, 0))])
	c.draw_polyline(border, Color(1, 1, 1, 0.5), 2.0)
	# The editor shows every mine; in play each side only sees the ones it has spotted.
	for p: Vector2i in _s.map.get_mines():
		TerrainPainter.draw_trap(c, _proj, p, _s.map.get_mine_kind(p))
	for p: Vector2i in _s.map.get_tunnels():
		TerrainPainter.draw_tunnel(c, _proj, p)
	if _s.mirrored:
		for y in h:
			if y % 2 == 0:
				c.draw_line(_proj.project(Vector2(w * 0.5, y)), _proj.project(Vector2(w * 0.5, y + 1)), Color(1, 1, 1, 0.45), 2.0)
	for i in _s.objectives.size():
		var objective: Dictionary = _s.objectives[i]
		var selected := i == _selected_objective
		c.draw_polyline(TerrainPainter.ground_circle(_proj, objective["center"], objective["radius"]), Color.WHITE if selected else NEUTRAL, 3.0 if selected else 1.5)
	for wi in _s.reinforcements.size():
		var wave: Dictionary = _s.reinforcements[wi]
		var color: Color = _team_color(wave["team"])
		color.a = 0.75 if wi == _wave and _tool == Tool.SPAWN else 0.35
		for p: Vector2i in wave["spawns"]:
			c.draw_colored_polygon(TerrainPainter.tile_poly(_proj, p), color)
	if not _s.map.in_bounds(_hover):
		return
	var color := Color(1, 1, 1, 0.8)
	if _tool == Tool.EDGE:
		for edge in _with_mirror_edges(_hover_edge[0], _hover_edge[1]):
			var a: Vector2i = edge[0]
			var dir: Vector2i = edge[1]
			var ends := _edge_ends(a, dir)
			c.draw_line(_proj.project(ends[0]), _proj.project(ends[1]), Color("ffd84a"), 4.0)
		return
	for p in _brush_tiles(_hover):
		for q in _with_mirror(p):
			c.draw_polyline(_tile_outline(q), color if q == p else Color(1, 1, 1, 0.35), 2.0)


## Flags, unit tags and wave labels on top of everything.
func _draw() -> void:
	if _s == null:
		return
	for objective in _s.objectives:
		var base := _proj.project(objective["center"])
		var top := _proj.project(objective["center"], 2.2)
		draw_line(base, top, Color("3a3226"), 3.0)
		draw_colored_polygon(PackedVector2Array([top, top + Vector2(22, 3), top + Vector2(22, 15), top + Vector2(0, 14)]), NEUTRAL)
		_label(top + Vector2(-80, -8), "%s (r %.1f)" % [objective["name"], objective["radius"]], NEUTRAL, 160)
	for i in _s.units.size():
		var entry: Dictionary = _s.units[i]
		var at := _proj.project(Vector2(entry["pos"]) + Vector2(0.5, 0.5), 2.0 if _s.theatre().role_def(entry["team"], entry["role"]).get("vehicle", false) else 1.6)
		var tag: String = entry["role"] if entry["name"] == "" else entry["name"]
		if entry["rank"] > 0:
			tag += " " + "*".repeat(entry["rank"])
		_label(at + Vector2(-60, 0), tag, Color.WHITE if i == _selected_unit else _team_color(entry["team"]), 120, 11)
	for wave in _s.reinforcements:
		for p: Vector2i in wave["spawns"]:
			_label(_proj.project(Vector2(p) + Vector2(0.5, 0.5), 0.3) + Vector2(-40, 0), "R%d" % wave["round"], _team_color(wave["team"]), 80, 11)


func _label(at: Vector2, text: String, color: Color, width: float, size := 13) -> void:
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, 4, Color(0, 0, 0, 0.8))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


func _tile_outline(p: Vector2i) -> PackedVector2Array:
	var poly := TerrainPainter.tile_poly(_proj, p)
	poly.append(poly[0])
	return poly


## The two ground corners of the side dir of tile p.
func _edge_ends(p: Vector2i, dir: Vector2i) -> Array[Vector2]:
	var c := Vector2(p) + Vector2(0.5, 0.5) + Vector2(dir) * 0.5
	var along := Vector2(absi(dir.y), absi(dir.x)) * 0.5
	return [c - along, c + along]


## Props standing in front of the cursor turn see-through, so the tiles behind them can be edited.
func _update_fading() -> void:
	var wanted := {}
	if _proj.isometric and _s.map.in_bounds(_hover):
		var f := Vector2(_hover) + Vector2(0.5, 0.5)
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var t := _hover + Vector2i(dx, dy)
				for key: Variant in [t, Vector3i(t.x, t.y, 0), Vector3i(t.x, t.y, 1)]:
					var node: Node2D = _object_nodes.get(key) if key is Vector2i else _edge_nodes.get(key)
					if node != null and _occludes(node.get_meta("center"), f):
						wanted[key] = node
	for key: Variant in _faded:
		if not wanted.has(key) and is_instance_valid(_faded[key]):
			_faded[key].modulate = Color.WHITE
	for key: Variant in wanted:
		wanted[key].modulate = Color(1, 1, 1, 0.3)
	_faded = wanted


func _occludes(g: Vector2, f: Vector2) -> bool:
	var r := _proj.rotate_grid(g)
	var rf := _proj.rotate_grid(f)
	return r.x + r.y > rf.x + rf.y + 0.1 and r.x > rf.x - 0.7 and r.y > rf.y - 0.7 and r.distance_to(rf) < 2.6


# --- Frame ---

func _process(delta: float) -> void:
	_pan_with_keys(delta)
	for chunk: Vector2i in _dirty:
		for node: Node2D in _chunks[chunk]:
			node.queue_redraw()
	_dirty.clear()
	_update_hover()
	_poll_sim()


func _update_hover() -> void:
	var tile := Vector2i(-1, -1)
	var edge := [Vector2i(-1, -1), Vector2i.ZERO]
	if get_viewport().get_mouse_position().x < _panel.global_position.x:
		var g := _proj.unproject(get_local_mouse_position())
		_hover_point = g
		tile = Vector2i(floori(g.x), floori(g.y))
		if _s.map.in_bounds(tile):
			var f := g - Vector2(tile)
			var sides := {Vector2i(0, -1): f.y, Vector2i(0, 1): 1.0 - f.y, Vector2i(-1, 0): f.x, Vector2i(1, 0): 1.0 - f.x}
			var best := Vector2i.ZERO
			for dir: Vector2i in sides:
				if _s.map.in_bounds(tile + dir) and (best == Vector2i.ZERO or sides[dir] < sides[best]):
					best = dir
			edge = [tile, best]
		else:
			tile = Vector2i(-1, -1)
	if tile != _hover or edge != _hover_edge:
		var previous := _hover
		_hover = tile
		_hover_edge = edge
		_overlay.queue_redraw()
		_update_fading()
		if _stroke != 0 and _tool in [Tool.TERRAIN, Tool.OBJECT, Tool.ERASE] and _s.map.in_bounds(previous) and _s.map.in_bounds(tile):
			# The mouse can skip tiles between frames: paint the whole line.
			for p in Geometry2D.bresenham_line(previous, tile):
				_hover = p
				_apply_stroke()
		elif _stroke != 0:
			_apply_stroke()
		_show_hover_status()


func _show_hover_status() -> void:
	if not _s.map.in_bounds(_hover):
		return
	var text := "%d, %d  %s" % [_hover.x, _hover.y, TacticalMap.TERRAIN_NAMES[_s.map.get_terrain(_hover)]]
	if _s.map.get_object(_hover) != Cover.NONE:
		text += ", %s" % _s.map.get_object_kind(_hover)
	var i := _unit_index_at(_hover)
	if i != -1:
		text += ", " + _s._who(_s.units[i])
	_status.text = text


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP when event.pressed:
				_zoom_by(1.1)
			MOUSE_BUTTON_WHEEL_DOWN when event.pressed:
				_zoom_by(1.0 / 1.1)
			MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if event.pressed and _s.map.in_bounds(_hover):
					_checkpoint()
					_stroke = 1 if event.button_index == MOUSE_BUTTON_LEFT else 2
					_stroke_last = ""
					_apply_stroke()
					if _tool in [Tool.UNIT, Tool.OBJECTIVE, Tool.SPAWN]:
						_stroke = 0
				elif not event.pressed:
					if _stroke != 0:
						_after_edit()
					_stroke = 0
			_:
				return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_camera.position -= event.relative / _camera.zoom
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if _typing():
			return
		var ctrl: bool = event.ctrl_pressed or event.meta_pressed
		match event.keycode:
			KEY_Z when ctrl:
				_undo_last()
			KEY_S when ctrl:
				_save()
			KEY_Q:
				_rotate_view(-1)
			KEY_E:
				_rotate_view(1)
			KEY_V:
				_toggle_view()
			KEY_R:
				_turn_selected_unit()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
				_set_tool(event.keycode - KEY_1)
			_:
				return
		get_viewport().set_input_as_handled()


## Whether a text field has the keyboard.
func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit or focus is SpinBox


func _pan_with_keys(delta: float) -> void:
	if _typing():
		return
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if (Input.is_key_pressed(KEY_S) and not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_META)) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if dir != Vector2.ZERO:
		_camera.position += dir.normalized() * PAN_SPEED * delta / _camera.zoom.x


func _view_shift() -> Vector2:
	return Vector2(PANEL_WIDTH * 0.5, 0) / _camera.zoom.x


func _focus(grid: Vector2) -> void:
	_camera.position = _proj.project(grid) + _view_shift()


func _focused_grid() -> Vector2:
	return _proj.unproject(_camera.position - _view_shift())


func _zoom_by(factor: float) -> void:
	var focus := _focused_grid()
	var zoom := clampf(_camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	_camera.zoom = Vector2(zoom, zoom)
	_focus(focus)


func _rotate_view(turns: int) -> void:
	var focus := _focused_grid()
	_proj.rotation = posmod(_proj.rotation + turns, 4)
	_focus(focus)
	_reproject()


func _toggle_view() -> void:
	var focus := _focused_grid()
	_proj.isometric = not _proj.isometric
	_focus(focus)
	_reproject()


# --- Editing ---

## Applies the current tool where the mouse is. Strokes skip spots they've already done.
func _apply_stroke() -> void:
	if not _s.map.in_bounds(_hover):
		return
	var spot := "%s%s" % [_hover, _hover_edge] if _tool == Tool.EDGE else str(_hover)
	if spot == _stroke_last:
		return
	_stroke_last = spot
	var removing := _stroke == 2
	match _tool:
		Tool.TERRAIN:
			for p in _brush_tiles(_hover):
				for q in _with_mirror(p):
					_s.map.set_terrain(q, TacticalMap.Terrain.FLOOR if removing else _terrain)
					_touch(q)
		Tool.OBJECT:
			for q in _with_mirror(_hover):
				if removing:
					_s.map.set_object(q, Cover.NONE)
					_s.map.set_mine(q, false)
				elif _object_kind == "mine":
					_s.map.set_mine(q, _s.map.is_passable(q))
				elif _unit_index_at(q) == -1:
					_s.map.set_object(q, Scenario.OBJECT_COVER[_object_kind], _object_kind)
				_touch(q)
		Tool.EDGE:
			for edge in _with_mirror_edges(_hover_edge[0], _hover_edge[1]):
				var a: Vector2i = edge[0]
				var b: Vector2i = a + edge[1]
				_s.map.set_edge(a, b, Cover.NONE if removing else Scenario.EDGE_COVER[_edge_kind], "" if removing else _edge_kind)
				_touch(a)
				_touch(b)
		Tool.ERASE:
			for p in _brush_tiles(_hover):
				for q in _with_mirror(p):
					_erase(q)
		Tool.UNIT:
			_unit_click(_hover, removing)
		Tool.OBJECTIVE:
			_objective_click(_hover, removing)
		Tool.SPAWN:
			_spawn_click(_hover, removing)
	_overlay.queue_redraw()


func _erase(p: Vector2i) -> void:
	_s.map.set_object(p, Cover.NONE)
	_s.map.set_mine(p, false)
	for dir: Vector2i in TacticalMap.DIRS4:
		if _s.map.in_bounds(p + dir):
			_s.map.set_edge(p, p + dir, Cover.NONE)
			_touch(p + dir)
	_touch(p)
	var i := _unit_index_at(p)
	if i != -1:
		_s.units.remove_at(i)
		_selected_unit = -1
		_rebuild_units()
	for wave in _s.reinforcements:
		wave["spawns"].erase(p)


func _unit_click(p: Vector2i, removing: bool) -> void:
	var i := _unit_index_at(p)
	if removing:
		if i != -1:
			var entry: Dictionary = _s.units[i]
			_s.units.remove_at(i)
			if _s.mirrored:
				var twin := _unit_index_at(_s.mirror_tile(p))
				if twin != -1 and _s.units[twin]["team"] != entry["team"] and _s.units[twin]["role"] == entry["role"]:
					_s.units.remove_at(twin)
			_selected_unit = -1
	elif i != -1:
		_selected_unit = i
		var entry: Dictionary = _s.units[i]
		_team = entry["team"]
		_role = entry["role"]
		_facing = Scenario.facing_name(entry["facing"])
		_show_tool_options()
	elif _s.map.is_passable(p):
		var facing: Vector2i = Scenario.FACINGS[_facing]
		var entry := Scenario.unit_entry(_team, _role, p, facing)
		_s.units.append(entry)
		_selected_unit = _s.units.size() - 1
		if _s.mirrored and _s.mirror_tile(p) != p and _unit_index_at(_s.mirror_tile(p)) == -1 and _s.map.is_passable(_s.mirror_tile(p)):
			_s.units.append(_s.mirrored_unit(entry))
	else:
		_flash("Units can't stand on objects")
	_rebuild_units()
	_after_edit()


func _turn_selected_unit() -> void:
	if _selected_unit == -1 or _selected_unit >= _s.units.size():
		return
	_checkpoint()
	var names := Scenario.FACINGS.keys()
	var entry: Dictionary = _s.units[_selected_unit]
	_facing = names[(names.find(Scenario.facing_name(entry["facing"])) + 1) % names.size()]
	_set_unit_facing(entry, Scenario.FACINGS[_facing])
	_show_tool_options()


func _set_unit_facing(entry: Dictionary, facing: Vector2i) -> void:
	var twin: Variant = _mirror_twin(entry)
	entry["facing"] = facing
	if twin != null:
		twin["facing"] = Vector2i(-facing.x, facing.y)
	_rebuild_units()


## With mirroring on: the other side's unit on the mirror tile with the same role, or null.
func _mirror_twin(entry: Dictionary) -> Variant:
	if not _s.mirrored:
		return null
	var i := _unit_index_at(_s.mirror_tile(entry["pos"]))
	if i == -1 or _s.units[i] == entry or _s.units[i]["team"] == entry["team"] or _s.units[i]["role"] != entry["role"]:
		return null
	return _s.units[i]


func _objective_click(p: Vector2i, removing: bool) -> void:
	var at := _objective_point(p)
	var i := _objective_at(at)
	if removing:
		if i != -1:
			_s.objectives.remove_at(i)
		_selected_objective = -1
	elif i != -1:
		_selected_objective = i
	else:
		_s.objectives.append({"name": "Objective %d" % (_s.objectives.size() + 1), "center": at, "radius": 2.5})
		_selected_objective = _s.objectives.size() - 1
		if _s.mirrored and absf(at.x - _s.map.width * 0.5) > 0.01:
			_s.objectives.append({"name": "Objective %d" % (_s.objectives.size() + 1), "center": _s.mirror_point(at), "radius": 2.5})
	_show_tool_options()
	queue_redraw()
	_after_edit()


## Where a new objective goes: the mouse position to the nearest half tile, or onto the centre line
## when mirroring and close to it, so a shared objective sits exactly between the two sides.
func _objective_point(p: Vector2i) -> Vector2:
	var at := Vector2(p) + Vector2(0.5, 0.5)
	if Rect2(Vector2(p), Vector2.ONE).grow(0.01).has_point(_hover_point):
		at = (_hover_point * 2.0).round() * 0.5
	if _s.mirrored and absf(at.x - _s.map.width * 0.5) <= 0.75:
		at.x = _s.map.width * 0.5
	return at


func _objective_at(at: Vector2) -> int:
	for i in _s.objectives.size():
		if at.distance_to(_s.objectives[i]["center"]) <= _s.objectives[i]["radius"]:
			return i
	return -1


func _spawn_click(p: Vector2i, removing: bool) -> void:
	if _s.reinforcements.is_empty():
		_flash("Add a reinforcement wave first")
		return
	var spawns: Array = _s.reinforcements[_wave]["spawns"]
	if removing:
		spawns.erase(p)
	elif not spawns.has(p):
		if _s.map.is_passable(p):
			spawns.append(p)
		else:
			_flash("Spawns must be on open ground")
	queue_redraw()
	_after_edit()


func _unit_index_at(p: Vector2i) -> int:
	for i in _s.units.size():
		if _s.units[i]["pos"] == p:
			return i
	return -1


func _brush_tiles(center: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if _tool != Tool.TERRAIN and _tool != Tool.ERASE:
		tiles.append(center)
		return tiles
	var from := -(_brush - 1) / 2
	for dy in range(from, from + _brush):
		for dx in range(from, from + _brush):
			var p := center + Vector2i(dx, dy)
			if _s.map.in_bounds(p):
				tiles.append(p)
	return tiles


## The tile and, with mirroring on, its mirror image.
func _with_mirror(p: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = [p]
	if _s.mirrored and _s.mirror_tile(p) != p:
		tiles.append(_s.mirror_tile(p))
	return tiles


func _with_mirror_edges(p: Vector2i, dir: Vector2i) -> Array:
	var edges := [[p, dir]]
	if _s.mirrored:
		var m := _s.mirror_tile(p)
		var m_dir := Vector2i(-dir.x, dir.y)
		# An edge on the centre line is its own mirror image.
		if not (m == p + dir and m + m_dir == p) and m != p:
			edges.append([m, m_dir])
	return edges


## Remembers the scenario before a change, for Ctrl+Z.
func _checkpoint() -> void:
	_undo.append(_s.to_data())
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()


func _undo_last() -> void:
	if _undo.is_empty():
		_flash("Nothing to undo")
		return
	var scenario := Scenario.from_data(_undo.pop_back())
	var view := _focused_grid()
	_open(scenario, edited_path)
	_focus(view)
	_flash("Undone")


## After any change: refresh the problem list.
func _after_edit() -> void:
	var problems := _s.validate()
	_problems.text = "No problems found." if problems.is_empty() else "• " + "\n• ".join(problems.slice(0, 6)) + ("\n…" if problems.size() > 6 else "")
	_problems.add_theme_color_override("font_color", GOOD if problems.is_empty() else BAD)
	queue_redraw()


func _flash(text: String) -> void:
	_status.text = text


# --- Panel ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -PANEL_WIDTH
	_panel.offset_right = -12
	_panel.offset_top = 12
	_panel.offset_bottom = -12
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.11, 0.1)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	_text(box, "Map editor", NEUTRAL, 20)
	_status = _text(box, "", MUTED, 12)

	_section(box, "Tool")
	var tools := GridContainer.new()
	tools.columns = 4
	box.add_child(tools)
	var group := ButtonGroup.new()
	for i in TOOL_NAMES.size():
		var button := _button(tools, "%d %s" % [i + 1, TOOL_NAMES[i]], _set_tool.bind(i))
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tool_buttons.append(button)
	_options = VBoxContainer.new()
	box.add_child(_options)
	_hint = _text(box, "", MUTED, 12, true)
	_mirror_check = CheckBox.new()
	_mirror_check.text = "Mirror edits onto the other half"
	_mirror_check.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			_s.mirrored = on
			_overlay.queue_redraw())
	box.add_child(_mirror_check)
	_button(box, "Copy west half onto east half now", _mirror_now)

	_section(box, "Scenario")
	_title_edit = _line(box, "Title", func(text: String) -> void: _s.title = text)
	var rules := HBoxContainer.new()
	box.add_child(rules)
	_text(rules, "Points to win", MUTED, 13)
	_vp_spin = _spin(rules, 1, 99, func(v: float) -> void: _s.vp_to_win = int(v))
	_text(rules, "Rounds", MUTED, 13)
	_rounds_spin = _spin(rules, 1, 99, func(v: float) -> void: _s.max_rounds = int(v))
	_text(box, "Briefing", MUTED, 13)
	_briefing_edit = TextEdit.new()
	_briefing_edit.custom_minimum_size = Vector2(0, 70)
	_briefing_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_briefing_edit.text_changed.connect(func() -> void:
		if not _syncing:
			_s.briefing = _briefing_edit.text)
	box.add_child(_briefing_edit)

	_section(box, "Reinforcements")
	var wave_row := HBoxContainer.new()
	box.add_child(wave_row)
	_wave_choice = OptionButton.new()
	_wave_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_choice.item_selected.connect(func(i: int) -> void:
		_wave = i
		_sync_wave()
		_overlay.queue_redraw())
	wave_row.add_child(_wave_choice)
	_button(wave_row, "Add", _add_wave)
	_button(wave_row, "Remove", _remove_wave)
	_wave_box = VBoxContainer.new()
	box.add_child(_wave_box)

	_section(box, "Problems")
	_problems = _text(box, "", GOOD, 12, true)

	_section(box, "File")
	_file_edit = _line(box, "File name", Callable())
	var file_row := HBoxContainer.new()
	box.add_child(file_row)
	_button(file_row, "Save", _save).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(file_row, "Start from the hand-made map", _load_builtin.bind("village")).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var load_row := HBoxContainer.new()
	box.add_child(load_row)
	_load_choice = OptionButton.new()
	_load_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_choice.fit_to_longest_item = false
	load_row.add_child(_load_choice)
	_button(load_row, "Load", _load_selected)
	var theatre_row := HBoxContainer.new()
	box.add_child(theatre_row)
	_text(theatre_row, "New maps in", MUTED, 13)
	_theatre_choice = OptionButton.new()
	for theatre in Theatres.all():
		_theatre_choice.add_item(theatre.title)
	_theatre_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theatre_row.add_child(_theatre_choice)
	var new_row := HBoxContainer.new()
	box.add_child(new_row)
	_size_choice = OptionButton.new()
	for size in NEW_SIZES:
		_size_choice.add_item("%dx%d" % [size, size])
	_size_choice.select(1)
	new_row.add_child(_size_choice)
	_button(new_row, "New empty", _new_map).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(new_row, "New random", _load_builtin.bind("random")).size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_section(box, "Play")
	var play_row := HBoxContainer.new()
	box.add_child(play_row)
	for spec: Array in [["Play vs AI", [false, true]], ["Hotseat", [false, false]], ["Watch AI", [true, true]]]:
		_button(play_row, spec[0], _play.bind(spec[1])).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sim_row := HBoxContainer.new()
	box.add_child(sim_row)
	_text(sim_row, "AI vs AI games", MUTED, 13)
	_games_spin = _spin(sim_row, 1, 200, Callable())
	_games_spin.value = 8
	_sim_button = _button(sim_row, "Test with AI", _toggle_sim)
	_sim_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sim_label = _text(box, "Plays AI vs AI games on worker threads and sums up who wins, how and where. For big runs use tools/balance.gd.", MUTED, 12, true)

	_gap(box, 6)
	_text(box, "LMB paint/place   RMB remove   Ctrl+Z undo\nMiddle drag or WASD pan   Wheel zoom   Q/E rotate   V view", MUTED, 12)
	_button(box, "Main menu", _quit)


## Fills the panel from the scenario.
func _sync_panel() -> void:
	_syncing = true
	_title_edit.text = _s.title
	_vp_spin.value = _s.vp_to_win
	_rounds_spin.value = _s.max_rounds
	_mirror_check.button_pressed = _s.mirrored
	_briefing_edit.text = _s.briefing
	_file_edit.text = edited_path.get_file().get_basename() if edited_path.begins_with(Scenario.USER_DIR) else _slug(_s.title)
	_syncing = false
	_theatre_choice.select(maxi(0, Theatres.IDS.find(_s.theatre_id)))
	_refresh_file_list()
	_sync_waves()
	_set_tool(_tool)
	_after_edit()


func _set_tool(tool: int) -> void:
	_tool = tool
	_tool_buttons[tool].button_pressed = true
	_hint.text = TOOL_HINTS[tool]
	_show_tool_options()
	if _overlay != null:
		_overlay.queue_redraw()


## The options for the current tool: ground type, object or wall kind, unit details, objective details.
func _show_tool_options() -> void:
	for child in _options.get_children():
		child.queue_free()
	match _tool:
		Tool.TERRAIN:
			_choice(_options, "Ground", Array(TacticalMap.TERRAIN_NAMES), _terrain, func(i: int) -> void: _terrain = i)
			_brush_choice()
		Tool.OBJECT:
			_choice(_options, "Object", OBJECT_KINDS.map(func(k: String) -> String: return "mine (buried, hidden)" if k == "mine" else "%s (%s cover)" % [k, "full" if Scenario.OBJECT_COVER[k] == Cover.FULL else "half"]),
					OBJECT_KINDS.find(_object_kind), func(i: int) -> void: _object_kind = OBJECT_KINDS[i])
		Tool.EDGE:
			_choice(_options, "Wall", EDGE_KINDS.map(func(k: String) -> String: return "%s (%s cover)" % [k, "full" if Scenario.EDGE_COVER[k] == Cover.FULL else "half"]),
					EDGE_KINDS.find(_edge_kind), func(i: int) -> void: _edge_kind = EDGE_KINDS[i])
		Tool.ERASE:
			_brush_choice()
		Tool.UNIT:
			_unit_options()
		Tool.OBJECTIVE:
			_objective_options()
		Tool.SPAWN:
			_text(_options, "Wave: %s" % (_wave_choice.get_item_text(_wave) if not _s.reinforcements.is_empty() else "none yet (add one below)"), MUTED, 13, true)


func _brush_choice() -> void:
	_choice(_options, "Brush", BRUSHES.map(func(b: int) -> String: return "%dx%d" % [b, b]), BRUSHES.find(_brush), func(i: int) -> void: _brush = BRUSHES[i])


## Side, role and facing for new units; with a unit selected, they change that unit.
func _team_names() -> Array:
	return [_s.theatre().team_name(0), _s.theatre().team_name(1)]


func _team_color(team: int) -> Color:
	return _s.theatre().team_color(team)


func _unit_options() -> void:
	var entry: Variant = _s.units[_selected_unit] if _selected_unit >= 0 and _selected_unit < _s.units.size() else null
	var theatre := _s.theatre()
	var roles := theatre.role_ids(_team)
	if not roles.has(_role):
		_role = roles[0]
	_choice(_options, "Side", _team_names(), _team, func(i: int) -> void:
		_team = i
		if entry != null:
			_checkpoint()
			entry["team"] = i
			if not theatre.has_role(i, entry["role"]):
				entry["role"] = theatre.role_ids(i)[0]
			_rebuild_units()
		# The other side has its own roles.
		_set_tool.call_deferred(Tool.UNIT))
	_choice(_options, "Role", roles.map(func(r: String) -> String: return theatre.role_name(_team, r)), roles.find(_role), func(i: int) -> void:
		_role = roles[i]
		if entry != null:
			_checkpoint()
			var twin: Variant = _mirror_twin(entry)
			entry["role"] = _role
			if twin != null:
				twin["role"] = _role
			_rebuild_units())
	var facings: Array = Scenario.FACINGS.keys()
	_choice(_options, "Facing", facings, facings.find(_facing), func(i: int) -> void:
		_facing = facings[i]
		if entry != null:
			_checkpoint()
			_set_unit_facing(entry, Scenario.FACINGS[_facing]))
	if entry == null:
		_text(_options, "No unit selected: left click places a new one%s." % (" (and its mirror twin)" if _s.mirrored else ""), MUTED, 12, true)
		return
	_text(_options, "Selected: %s at %d, %d" % [_s._who(entry), entry["pos"].x, entry["pos"].y], _team_color(entry["team"]), 13)
	_line(_options, "Name (empty = from the seed)", func(text: String) -> void:
		entry["name"] = text.strip_edges()
		queue_redraw()).text = entry["name"]
	_choice(_options, "Rank", Array(Unit.RANK_NAMES), entry["rank"], func(i: int) -> void:
		entry["rank"] = i
		queue_redraw())


func _objective_options() -> void:
	if _selected_objective < 0 or _selected_objective >= _s.objectives.size():
		_text(_options, "%d objectives. Each scores a point per round for the side holding it alone." % _s.objectives.size(), MUTED, 12, true)
		return
	var objective: Dictionary = _s.objectives[_selected_objective]
	_line(_options, "Name", func(text: String) -> void:
		objective["name"] = text
		queue_redraw()).text = objective["name"]
	var row := HBoxContainer.new()
	_options.add_child(row)
	_text(row, "Radius", MUTED, 13)
	var spin := _spin(row, 0.5, 10.0, func(v: float) -> void:
		objective["radius"] = v
		queue_redraw()
		_overlay.queue_redraw())
	spin.step = 0.5
	spin.value = objective["radius"]


func _sync_waves() -> void:
	_wave_choice.clear()
	for wave in _s.reinforcements:
		_wave_choice.add_item("Round %d, %s: %d units" % [wave["round"], _s.theatre().team_name(wave["team"]), wave["roster"].size()])
	_wave = clampi(_wave, 0, maxi(0, _s.reinforcements.size() - 1))
	if not _s.reinforcements.is_empty():
		_wave_choice.select(_wave)
	_sync_wave()


func _sync_wave() -> void:
	for child in _wave_box.get_children():
		child.queue_free()
	if _s.reinforcements.is_empty():
		_text(_wave_box, "No reinforcements.", MUTED, 12)
		return
	var wave: Dictionary = _s.reinforcements[_wave]
	var row := HBoxContainer.new()
	_wave_box.add_child(row)
	_text(row, "Round", MUTED, 13)
	_spin(row, 1, 99, func(v: float) -> void:
		wave["round"] = int(v)
		_update_wave_label()).value = wave["round"]
	_choice(row, "", _team_names(), wave["team"], func(i: int) -> void:
		wave["team"] = i
		_update_wave_label()
		_overlay.queue_redraw())
	var roster := PackedStringArray(wave["roster"].map(func(e: Variant) -> String: return e["role"] if e is Dictionary else e))
	var edit := _line(_wave_box, "Roster, e.g. " + ", ".join(_s.theatre().role_ids(wave["team"]).slice(0, 2)), func(text: String) -> void:
		var parsed := []
		for part in text.split(",", false):
			# Role ids, matched ignoring case.
			for role: String in _s.theatre().role_ids(wave["team"]):
				if role.to_lower() == part.strip_edges().to_lower():
					parsed.append(role)
		wave["roster"] = parsed
		_update_wave_label()
		_after_edit())
	edit.text = ", ".join(roster)
	_text(_wave_box, "%d spawn tiles. Pick the Spawns tool to place them." % wave["spawns"].size(), MUTED, 12)


func _update_wave_label() -> void:
	var wave: Dictionary = _s.reinforcements[_wave]
	_wave_choice.set_item_text(_wave, "Round %d, %s: %d units" % [wave["round"], _s.theatre().team_name(wave["team"]), wave["roster"].size()])
	queue_redraw()


func _add_wave() -> void:
	_checkpoint()
	var spawns: Array[Vector2i] = []
	_s.reinforcements.append({"round": 4, "team": 0, "roster": [_s.theatre().role_ids(0)[0]], "spawns": spawns})
	_wave = _s.reinforcements.size() - 1
	_sync_waves()
	_set_tool(Tool.SPAWN)
	_after_edit()


func _remove_wave() -> void:
	if _s.reinforcements.is_empty():
		return
	_checkpoint()
	_s.reinforcements.remove_at(_wave)
	_sync_waves()
	_overlay.queue_redraw()
	_after_edit()


func _mirror_now() -> void:
	_checkpoint()
	_s.mirror_west_to_east()
	_s.mirrored = true
	var view := _focused_grid()
	_open(_s, edited_path)
	_focus(view)
	_flash("East half rebuilt from the west half")


# --- Files ---

func _refresh_file_list() -> void:
	_load_choice.clear()
	for entry in Scenario.list_files():
		_load_choice.add_item("%s%s" % [entry["title"], "" if entry["user"] else " (bundled)"])
		_load_choice.set_item_metadata(_load_choice.item_count - 1, entry["path"])


func _save() -> void:
	var name := _slug(_file_edit.text if _file_edit.text.strip_edges() != "" else _s.title)
	var path := Scenario.USER_DIR + name + ".json"
	var err := _s.save_file(path)
	if err != OK:
		_flash("Couldn't save: %s" % error_string(err))
		return
	edited_path = path
	_file_edit.text = name
	_refresh_file_list()
	_flash("Saved %s" % path)


func _load_selected() -> void:
	if _load_choice.selected < 0:
		return
	var path: String = _load_choice.get_item_metadata(_load_choice.selected)
	var scenario := Scenario.load_file(path)
	if scenario == null:
		_flash(Scenario.last_error)
		return
	_undo.clear()
	_open(scenario, path)
	_flash("Loaded %s" % path)


## Starts from a built-in map of the chosen theatre: its hand-made map, or a random map of the chosen size.
func _load_builtin(kind: String) -> void:
	_checkpoint()
	var seed := randi() % 10000 + 1
	var size: int = NEW_SIZES[_size_choice.selected]
	var theatre_id: String = Theatres.IDS[_theatre_choice.selected]
	if kind == "village" and Theatres.get_theatre(theatre_id).village_layout().is_empty():
		_flash("%s has no hand-made map" % Theatres.get_theatre(theatre_id).title)
		return
	var built := GameSession.build_skirmish({"theatre": theatre_id, "map": kind, "size": size, "seed": seed})
	var scenario := Scenario.from_battle(built[0], built[1], false)
	_open(scenario, "")
	_flash("Started from %s" % built[1])


func _new_map() -> void:
	_checkpoint()
	var size: int = NEW_SIZES[_size_choice.selected]
	var scenario := Scenario.create(size, size, Theatres.IDS[_theatre_choice.selected])
	scenario.title = "New %dx%d scenario" % [size, size]
	_open(scenario, "")


static func _slug(text: String) -> String:
	var slug := ""
	for c in text.strip_edges().to_lower():
		slug += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while slug.contains("__"):
		slug = slug.replace("__", "_")
	return slug.trim_prefix("_").trim_suffix("_") if slug.trim_prefix("_").trim_suffix("_") != "" else "scenario"


# --- Playing and testing ---

func _play(ai_teams: Array) -> void:
	var problems := _s.validate()
	for team in 2:
		if not _s.units.any(func(u: Dictionary) -> bool: return u["team"] == team):
			_flash("Both sides need units to play")
			return
	if not problems.is_empty():
		_flash("Playing despite %d problem(s)" % problems.size())
	_stop_sim()
	var battle := _s.build_battle(randi() % 1000000000 + 1)
	GameSession.campaign = null
	GameSession.war = null
	GameSession.start_battle(battle, ai_teams, _s.title)
	get_tree().change_scene_to_file(GameSession.BATTLE_SCENE)


func _toggle_sim() -> void:
	if _batch != null:
		_stop_sim()
		_sim_label.text = "Stopped."
		return
	for team in 2:
		if not _s.units.any(func(u: Dictionary) -> bool: return u["team"] == team):
			_flash("Both sides need units to test")
			return
	_batch = BalanceSim.Batch.new({"scenario": _s.to_data()}, int(_games_spin.value), 1)
	_batch.start(clampi(OS.get_processor_count() - 1, 1, 8))
	_batch_started = Time.get_ticks_msec()
	_batch_shown = -1
	_sim_button.text = "Stop"
	_sim_label.text = "Playing %d games..." % _batch.jobs.size()


func _poll_sim() -> void:
	if _batch == null:
		return
	var results := _batch.results()
	if results.size() == _batch_shown:
		return
	_batch_shown = results.size()
	if results.is_empty():
		return
	var text := BalanceSim.format_summary(BalanceSim.summarize(results))
	if _batch.done():
		_batch.wait()
		_batch = null
		_sim_button.text = "Test with AI"
		text += "\nDone in %.0fs." % ((Time.get_ticks_msec() - _batch_started) / 1000.0)
	else:
		text = "%d of %d games played...\n" % [results.size(), _batch.jobs.size()] + text
	_sim_label.text = text


func _stop_sim() -> void:
	if _batch != null:
		_batch.cancel()
		_batch.wait()
		_batch = null
		_sim_button.text = "Test with AI"


func _quit() -> void:
	_stop_sim()
	get_tree().change_scene_to_file(GameSession.MENU_SCENE)


# --- Widgets ---

func _section(parent: Control, text: String) -> void:
	_gap(parent, 4)
	_text(parent, text, NEUTRAL, 16)
	parent.add_child(HSeparator.new())


func _text(parent: Control, text: String, color: Color, size: int, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(PANEL_WIDTH - 50, 0)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 13)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _line(parent: Control, placeholder: String, on_change: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if on_change.is_valid():
		edit.text_changed.connect(func(text: String) -> void:
			if not _syncing:
				on_change.call(text))
	parent.add_child(edit)
	return edit


func _spin(parent: Control, low: float, high: float, on_change: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.focus_mode = Control.FOCUS_NONE
	spin.get_line_edit().focus_mode = Control.FOCUS_CLICK
	if on_change.is_valid():
		spin.value_changed.connect(func(v: float) -> void:
			if not _syncing:
				on_change.call(v))
	parent.add_child(spin)
	return spin


func _choice(parent: Control, label: String, items: Array, selected: int, on_select: Callable) -> OptionButton:
	var row := parent
	if label != "":
		row = HBoxContainer.new()
		parent.add_child(row)
		_text(row, label, MUTED, 13).custom_minimum_size = Vector2(60, 0)
	var choice := OptionButton.new()
	choice.focus_mode = Control.FOCUS_NONE
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		choice.add_item(str(item))
	choice.select(maxi(0, selected))
	choice.item_selected.connect(on_select)
	row.add_child(choice)
	return choice


func _gap(parent: Control, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	parent.add_child(spacer)
