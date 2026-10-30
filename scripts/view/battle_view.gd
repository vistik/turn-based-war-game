extends Node2D
## View of a Battle: draws the grid (isometric or top-down), takes hotseat input and plays back engine events.
## Placeholder art only: everything is drawn with primitives in _draw().

const PANEL_WIDTH := 400.0
const TEAM_COLORS := [Color("4aa3ff"), Color("ff6150")]
const TEAM_NAMES := ["Blue", "Red"]
const TERRAIN_COLORS := [Color("4b5a45"), Color("6a6440"), Color("5a5048")]
const ROCK_COLOR := Color("8d939b")
const CRATE_COLOR := Color("a07a3f")
const WALL_COLOR := Color("c3c7cc")
const LOW_WALL_COLOR := Color("b8a070")
const MOVE_COLOR := Color("4aa3ff")
const DASH_COLOR := Color("f5c542")
## Heights in tiles of things standing on the map, and the half-thickness of walls.
const FULL_HEIGHT := 1.0
const HALF_HEIGHT := 0.45
const WALL_THICKNESS := 0.07
const KEY_ACTIONS := {
	KEY_1: "shoot", KEY_2: "overwatch", KEY_3: "hunker", KEY_4: "reload",
	KEY_5: "grenade", KEY_6: "medkit", KEY_TAB: "next", KEY_ENTER: "end", KEY_KP_ENTER: "end",
}
const ACTION_BUTTONS := [
	["shoot", "1 Shoot"], ["overwatch", "2 Overwatch"], ["hunker", "3 Hunker"], ["reload", "4 Reload"],
	["grenade", "5 Grenade"], ["medkit", "6 Medkit"], ["next", "Tab Next unit"], ["end", "Enter End turn"],
]
const SHOT_LABELS := {"miss": "MISS", "graze": "GRAZE", "hit": "HIT", "crit": "CRITICAL"}
const ZOOM_MIN := 0.35
const ZOOM_MAX := 2.0
const PAN_SPEED := 700.0

enum Mode { MOVE, SHOOT, GRENADE, MEDKIT }

var battle: Battle
var selected: Unit
var mode := Mode.MOVE
var hover := Vector2i(-1, -1)
var busy := false

var _proj: ViewProjection
var _camera: Camera2D
var _dragging := false
var _reach := {}
var _move_tiles := {}
var _visible_tiles := {}
var _seen_units := {}
var _target_odds := {}
var _flankers: Array[Unit] = []
## Presentation state that trails the engine while events play back. Positions are in grid space.
var _display_pos := {}
var _display_hp := {}
var _revealed := {}
var _floaters := []
var _effects := []
var _overlay_state := ""

var _font: Font
var _panel: PanelContainer
var _turn_label: Label
var _unit_info: RichTextLabel
var _target_info: RichTextLabel
var _log: RichTextLabel
var _buttons := {}
var _overlay: ColorRect
var _overlay_label: Label


func _ready() -> void:
	_font = ThemeDB.fallback_font
	battle = SkirmishScenario.build()
	_proj = ViewProjection.new(Vector2(battle.map.width, battle.map.height))
	_camera = Camera2D.new()
	_camera.zoom = Vector2(1.0, 1.0)
	add_child(_camera)
	for u in battle.units:
		_display_pos[u.id] = _center(u.pos)
		_display_hp[u.id] = u.hp
	_build_ui()
	_focus(Vector2(battle.map.width, battle.map.height) * 0.5, false)
	_run(battle.start())


func _process(delta: float) -> void:
	_pan_with_keys(delta)
	if not busy and _overlay_state == "":
		_set_hover(_mouse_tile())
	if not busy and _floaters.is_empty() and _effects.is_empty():
		return
	for item in _floaters + _effects:
		item["age"] += delta
	_floaters = _floaters.filter(func(f: Dictionary) -> bool: return f["age"] < f["life"])
	_effects = _effects.filter(func(f: Dictionary) -> bool: return f["age"] < f["life"])
	queue_redraw()


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if _overlay_state != "":
		if event is InputEventKey and event.pressed and not event.echo:
			_dismiss_overlay()
		return
	if _handle_camera_input(event):
		get_viewport().set_input_as_handled()
		return
	if busy:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_click(_mouse_tile())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_set_mode(Mode.MOVE)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_set_mode(Mode.MOVE)
		elif KEY_ACTIONS.has(event.keycode):
			_on_action(KEY_ACTIONS[event.keycode])
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()


## Zoom, drag, rotate and view toggle. Returns true when the event was used.
func _handle_camera_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP when event.pressed:
				_zoom_by(1.1)
			MOUSE_BUTTON_WHEEL_DOWN when event.pressed:
				_zoom_by(1.0 / 1.1)
			MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
			_:
				return false
		return true
	if event is InputEventMouseMotion and _dragging:
		_camera.position -= event.relative / _camera.zoom
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				_rotate_view(-1)
			KEY_E:
				_rotate_view(1)
			KEY_V:
				_toggle_view()
			KEY_F:
				if selected != null:
					_focus(_display_pos[selected.id])
			_:
				return false
		return true
	return false


func _pan_with_keys(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if dir != Vector2.ZERO and _overlay_state == "":
		_camera.position += dir.normalized() * PAN_SPEED * delta / _camera.zoom.x


func _on_click(tile: Vector2i) -> void:
	if not battle.map.in_bounds(tile):
		return
	var u := battle.unit_at(tile)
	var own := u != null and u.team == battle.current_team
	match mode:
		Mode.MOVE:
			if own:
				_select(u)
			elif selected != null and u == null and battle.can_move(selected, tile) == "":
				_run(battle.move(selected, tile))
		Mode.SHOOT:
			if u != null and battle.can_shoot(selected, u) == "":
				_run(battle.shoot(selected, u))
			elif own:
				_select(u)
		Mode.GRENADE:
			var err := battle.can_throw_grenade(selected, tile)
			if err == "":
				_run(battle.throw_grenade(selected, tile))
			else:
				_flash(err)
		Mode.MEDKIT:
			var err := battle.can_use_medkit(selected, u)
			if err == "":
				_run(battle.use_medkit(selected, u))
			else:
				_flash(err)


func _on_action(action: String) -> void:
	match action:
		"rotate_left":
			_rotate_view(-1)
			return
		"rotate_right":
			_rotate_view(1)
			return
		"toggle_view":
			_toggle_view()
			return
	if busy or _overlay_state != "" or battle.winner != -1:
		return
	if action == "end":
		_run(battle.end_turn())
		return
	if action == "next":
		_select(_next_ready_unit(selected), true)
		return
	if selected == null:
		return
	var err := ""
	match action:
		"shoot":
			# Same requirements as overwatch: able to act and has ammo.
			err = battle.can_overwatch(selected)
			if err == "" and battle.visible_enemies(selected).is_empty():
				err = "No enemies in line of sight"
			if err == "":
				_set_mode(Mode.SHOOT)
		"overwatch":
			err = battle.can_overwatch(selected)
			if err == "":
				_run(battle.overwatch(selected))
		"hunker":
			err = battle.can_hunker(selected)
			if err == "":
				_run(battle.hunker(selected))
		"reload":
			err = battle.can_reload(selected)
			if err == "":
				_run(battle.reload(selected))
		"grenade":
			err = battle.can_act(selected)
			if err == "" and selected.grenades <= 0:
				err = "No grenades left"
			if err == "":
				_set_mode(Mode.GRENADE)
		"medkit":
			err = battle.can_act(selected)
			if err == "" and selected.medkits <= 0:
				err = "No medkits left"
			if err == "":
				_set_mode(Mode.MEDKIT)
	if err != "":
		_flash(err)


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_dismiss_overlay()


func _dismiss_overlay() -> void:
	if _overlay_state == "game_over":
		get_tree().reload_current_scene()
		return
	_overlay_state = ""
	_overlay.hide()
	_select(_next_ready_unit(null), true)


func _select(u: Unit, focus := false) -> void:
	selected = u
	mode = Mode.MOVE
	if focus and u != null:
		_focus(_display_pos[u.id])
	_refresh()


func _set_mode(new_mode: Mode) -> void:
	if selected == null:
		return
	mode = new_mode
	_refresh()


func _set_hover(tile: Vector2i) -> void:
	if tile == hover:
		return
	hover = tile
	_flankers = _compute_flankers()
	_update_target_info()
	queue_redraw()


func _mouse_tile() -> Vector2i:
	if get_viewport().get_mouse_position().x >= _panel.global_position.x:
		return Vector2i(-1, -1)
	return _proj.tile_at(get_local_mouse_position())


func _next_ready_unit(after: Unit) -> Unit:
	var ready := battle.alive_units(battle.current_team).filter(func(u: Unit) -> bool: return u.actions > 0)
	if ready.is_empty():
		return null
	return ready[(ready.find(after) + 1) % ready.size()]


# --- Camera ---

## The screen x offset that centres things in the map area left of the side panel.
func _view_shift() -> Vector2:
	return Vector2(PANEL_WIDTH * 0.5, 0) / _camera.zoom.x


func _focus(grid: Vector2, animate := true) -> void:
	var target := _proj.project(grid) + _view_shift()
	if animate:
		create_tween().tween_property(_camera, "position", target, 0.25).set_trans(Tween.TRANS_SINE)
	else:
		_camera.position = target


func _focused_grid() -> Vector2:
	return _proj.unproject(_camera.position - _view_shift())


func _zoom_by(factor: float) -> void:
	var focus := _focused_grid()
	var zoom := clampf(_camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	_camera.zoom = Vector2(zoom, zoom)
	_focus(focus, false)


func _rotate_view(turns: int) -> void:
	var focus := _focused_grid()
	_proj.rotation = posmod(_proj.rotation + turns, 4)
	_focus(focus, false)
	queue_redraw()


func _toggle_view() -> void:
	var focus := _focused_grid()
	_proj.isometric = not _proj.isometric
	_focus(focus, false)
	queue_redraw()


# --- Engine calls and event playback ---

func _run(events: Array) -> void:
	busy = true
	_reach = {}
	_move_tiles = {}
	queue_redraw()
	for e: Dictionary in events:
		await _play_event(e)
	_revealed.clear()
	busy = false
	if _overlay_state == "" and (selected == null or battle.can_act(selected) != ""):
		selected = _next_ready_unit(selected)
	mode = Mode.MOVE
	_refresh()


func _play_event(e: Dictionary) -> void:
	match e["type"]:
		"move":
			var path: Array = e["path"]
			for i in range(1, path.size()):
				await _tween_unit(e["unit"], _center(path[i]), 0.08)
		"shot":
			await _play_shot(e)
		"damage":
			var u := battle.get_unit(e["unit"])
			_display_hp[u.id] = e["hp"]
			var text := "-%d" % e["amount"]
			if e["absorbed"] > 0:
				text += " (armor %d)" % e["absorbed"]
			_float(_display_pos[u.id], text, Color("ff7b6b"))
			await _wait(0.4)
		"death":
			var u := battle.get_unit(e["unit"])
			_float(_display_pos[u.id], "KILLED", Color("ff3b3b"))
			_log_line("[color=#ff6b6b]%s was killed.[/color]" % u.name)
			await _wait(0.5)
		"explosion":
			var u := battle.get_unit(e["unit"])
			_effects.append({"kind": "explosion", "at": _center(e["center"]), "radius": e["radius"] + 0.5, "age": 0.0, "life": 0.5})
			_log_line("%s throws a grenade, destroying %d pieces of cover." % [u.name, e["destroyed"]])
			await _wait(0.5)
		"status":
			var u := battle.get_unit(e["unit"])
			_float(_display_pos[u.id], e["text"], Color("ffd34d"))
			_log_line("%s: %s" % [u.name, e["text"]])
			await _wait(0.3)
		"heal":
			var u := battle.get_unit(e["unit"])
			_display_hp[u.id] = e["hp"]
			_float(_display_pos[u.id], "+%d HP" % e["amount"], Color("6bff8a"))
			_log_line("%s is patched up (+%d HP)." % [u.name, e["amount"]])
			await _wait(0.4)
		"turn":
			_log_line("[b][color=%s]Round %d: %s team[/color][/b]" % [TEAM_COLORS[e["team"]].to_html(false), e["round"], TEAM_NAMES[e["team"]]])
			_show_overlay("handover", "%s team's turn\n\nClick or press any key" % TEAM_NAMES[e["team"]], TEAM_COLORS[e["team"]])
		"game_over":
			_log_line("[b]%s team wins![/b]" % TEAM_NAMES[e["winner"]])
			_show_overlay("game_over", "%s team wins!\n\nClick or press any key to play again" % TEAM_NAMES[e["winner"]], TEAM_COLORS[e["winner"]])


func _play_shot(e: Dictionary) -> void:
	var shooter := battle.get_unit(e["shooter"])
	var target := battle.get_unit(e["target"])
	_revealed[shooter.id] = true
	_revealed[target.id] = true
	queue_redraw()
	if e["reaction"]:
		_float(_display_pos[shooter.id], "OVERWATCH!", Color("ffd34d"))
		await _wait(0.45)
	var from: Vector2 = _display_pos[shooter.id]
	var to: Vector2 = _display_pos[target.id]
	if e["result"] == "miss":
		to += Vector2.from_angle(randf() * TAU) * 0.8
	_effects.append({"kind": "tracer", "from": from, "to": to, "age": 0.0, "life": 0.35})
	await _wait(0.3)
	var label: String = SHOT_LABELS[e["result"]]
	_float(_display_pos[target.id], "%s (%d%%)" % [label, e["chance"]], Color.WHITE if e["result"] != "crit" else Color("ffb84d"))
	_log_line("%s%s shoots at %s: %s (%d%%)" % ["Overwatch: " if e["reaction"] else "", shooter.name, target.name, label, e["chance"]])
	await _wait(0.25)


func _tween_unit(id: int, to: Vector2, duration: float) -> void:
	var tween := create_tween()
	tween.tween_method(_set_display_pos.bind(id), _display_pos[id], to, duration)
	await tween.finished


func _set_display_pos(pos: Vector2, id: int) -> void:
	_display_pos[id] = pos
	queue_redraw()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Rising text over a grid position.
func _float(at: Vector2, text: String, color: Color) -> void:
	_floaters.append({"text": text, "at": at, "color": color, "age": 0.0, "life": 1.2})


func _flash(message: String) -> void:
	var at: Vector2 = _display_pos[selected.id] if selected != null else _center(hover)
	_float(at, message, Color("ff9b8a"))


# --- State caches and side panel ---

func _refresh() -> void:
	var team := battle.current_team
	_visible_tiles = battle.team_visible_tiles(team)
	_seen_units.clear()
	for u in battle.alive_units():
		if battle.team_sees(team, u):
			_seen_units[u.id] = true
	var can_act := selected != null and battle.can_act(selected) == ""
	_reach = battle.reachable(selected) if can_act and mode == Mode.MOVE else {}
	_move_tiles.clear()
	for p: Vector2i in _reach:
		if _reach[p]["cost"] <= selected.mobility + 0.001:
			_move_tiles[p] = true
	_target_odds.clear()
	if can_act and mode == Mode.SHOOT:
		for e in battle.visible_enemies(selected):
			_target_odds[e.id] = battle.shot_odds(selected, e)["hit"]
	_flankers = _compute_flankers()
	_update_panel()
	_update_target_info()
	queue_redraw()


## Visible enemies that would have no cover between them and the hovered move destination.
func _compute_flankers() -> Array[Unit]:
	var result: Array[Unit] = []
	if mode != Mode.MOVE or selected == null or not _reach.has(hover) or hover == selected.pos:
		return result
	for e in battle.enemies_of(selected):
		if _seen_units.has(e.id) and battle.map.cover_against(hover, e.pos) == Cover.NONE \
				and LineOfSight.can_see(battle.map, e.pos, hover, e.sight):
			result.append(e)
	return result


func _update_panel() -> void:
	_turn_label.text = "Round %d: %s team" % [battle.round_number, TEAM_NAMES[battle.current_team]]
	_turn_label.add_theme_color_override("font_color", TEAM_COLORS[battle.current_team])
	_unit_info.text = _describe_unit(selected) if selected != null else "No unit selected.\nClick one of your soldiers."
	var s := selected
	_buttons["shoot"].disabled = s == null or battle.can_overwatch(s) != ""
	_buttons["overwatch"].disabled = s == null or battle.can_overwatch(s) != ""
	_buttons["hunker"].disabled = s == null or battle.can_hunker(s) != ""
	_buttons["reload"].disabled = s == null or battle.can_reload(s) != ""
	_buttons["grenade"].disabled = s == null or battle.can_act(s) != "" or s.grenades <= 0
	_buttons["medkit"].disabled = s == null or battle.can_act(s) != "" or s.medkits <= 0
	_buttons["next"].disabled = _next_ready_unit(s) == null
	_buttons["end"].disabled = battle.winner != -1


func _describe_unit(u: Unit) -> String:
	var lines := PackedStringArray()
	lines.append("[b][color=%s]%s[/color][/b]  %s" % [TEAM_COLORS[u.team].to_html(false), u.name, u.role])
	lines.append("HP %d/%d   Armor %d   Aim %d   Mobility %d" % [u.hp, u.max_hp, u.armor, u.aim, u.mobility])
	lines.append("%s   Ammo %d/%d   Grenades %d   Medkits %d" % [u.weapon.name, u.ammo, u.weapon.clip_size, u.grenades, u.medkits])
	var status := "Actions left: %d/%d" % [u.actions, Unit.ACTIONS_PER_TURN]
	if u.overwatch:
		status += "   [color=#ffd34d]On overwatch[/color]"
	if u.hunkered:
		status += "   [color=#8fd3ff]Hunkered down[/color]"
	lines.append(status)
	match mode:
		Mode.SHOOT:
			lines.append("[color=#ff9b8a]Shooting: click a target. Right click cancels.[/color]")
		Mode.GRENADE:
			lines.append("[color=#ffb84d]Grenade: click a tile in range. Right click cancels.[/color]")
		Mode.MEDKIT:
			lines.append("[color=#6bff8a]Medkit: click yourself or an adjacent ally. Right click cancels.[/color]")
	return "\n".join(lines)


func _update_target_info() -> void:
	var map := battle.map
	var text := ""
	if selected != null and map.in_bounds(hover):
		var target := battle.unit_at(hover)
		match mode:
			Mode.MOVE, Mode.SHOOT:
				if target != null and target.team != selected.team and _seen_units.has(target.id) and battle.can_see(selected, target):
					text = _describe_odds(selected, target)
			Mode.GRENADE:
				var err := battle.can_throw_grenade(selected, hover)
				text = "[b]Frag grenade[/b]  range %d, radius %.1f\n%d-%d damage, ignores cover, shreds %d armor,\ndestroys cover. Hits friends too." % [
					CombatRules.GRENADE_RANGE, CombatRules.GRENADE_RADIUS, CombatRules.GRENADE_DAMAGE_MIN,
					CombatRules.GRENADE_DAMAGE_MAX, CombatRules.GRENADE_SHRED]
				if err != "":
					text += "\n[color=#ff6b6b]%s[/color]" % err
	if text == "" and map.in_bounds(hover):
		text = _describe_tile(hover)
	_target_info.text = text


func _describe_odds(shooter: Unit, target: Unit) -> String:
	var odds := battle.shot_odds(shooter, target)
	var lines := PackedStringArray()
	lines.append("[b]Target: %s[/b] (%s)  HP %d/%d  Armor %d" % [target.name, target.role, target.hp, target.max_hp, target.armor])
	lines.append("[color=#8fff9b]Hit %d%%[/color]   Graze %d%%   Crit %d%%" % [odds["hit"], odds["graze"], odds["crit"]])
	for m: Array in odds["modifiers"]:
		lines.append("    %s  %+d" % [m[0], m[1]])
	if odds["flanked"]:
		lines.append("[color=#ffb84d]No cover from this angle: +%d crit[/color]" % CombatRules.FLANK_CRIT_BONUS)
	if target.overwatch:
		lines.append("[color=#ffd34d]On overwatch[/color]")
	return "\n".join(lines)


func _describe_tile(p: Vector2i) -> String:
	var map := battle.map
	var lines := PackedStringArray()
	var object := map.get_object(p)
	if object != Cover.NONE:
		lines.append("[b]%s[/b]  (blocks movement%s)" % ["Low obstacle" if object == Cover.HALF else "High obstacle", ", blocks sight" if object == Cover.FULL else ""])
	else:
		lines.append("[b]%s[/b]  move cost %.0f" % [TacticalMap.TERRAIN_NAMES[map.get_terrain(p)], TacticalMap.TERRAIN_COST[map.get_terrain(p)]])
		var covers := PackedStringArray()
		for i in 4:
			var c := map.cover_toward(p, TacticalMap.DIRS4[i])
			if c != Cover.NONE:
				covers.append("%s %s" % [["N", "E", "S", "W"][i], Cover.NAMES[c].to_lower()])
		lines.append("Cover: " + (", ".join(covers) if not covers.is_empty() else "none"))
	if _reach.has(p) and selected != null:
		var cost: float = _reach[p]["cost"]
		lines.append("Path cost %.1f of %d: %s" % [cost, selected.mobility, "dash, uses both actions" if cost > selected.mobility + 0.001 else "one action"])
	if not _flankers.is_empty():
		lines.append("[color=#ff6b6b]Flanked here by %d enemy[/color]" % _flankers.size())
	if not _visible_tiles.has(p):
		lines.append("[color=#888]Not in sight[/color]")
	return "\n".join(lines)


func _log_line(text: String) -> void:
	_log.append_text(text + "\n")


func _show_overlay(state: String, text: String, color: Color) -> void:
	_overlay_state = state
	_overlay_label.text = text
	_overlay_label.add_theme_color_override("font_color", color)
	_overlay.show()


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
	style.bg_color = Color(0.1, 0.11, 0.13)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 20)
	box.add_child(_turn_label)
	_unit_info = _rich_label(96)
	box.add_child(_unit_info)

	var actions := HFlowContainer.new()
	box.add_child(actions)
	for spec: Array in ACTION_BUTTONS:
		_add_button(actions, spec[0], spec[1])

	box.add_child(HSeparator.new())
	_target_info = _rich_label(150)
	box.add_child(_target_info)
	box.add_child(HSeparator.new())
	_log = _rich_label(0)
	_log.fit_content = false
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_log)

	var view_row := HBoxContainer.new()
	box.add_child(view_row)
	_add_button(view_row, "rotate_left", "Q Rotate left")
	_add_button(view_row, "rotate_right", "E Rotate right")
	_add_button(view_row, "toggle_view", "V Iso / top-down")
	var help := Label.new()
	help.text = "LMB select / move / target   RMB, Esc cancel\nWASD or middle drag pan   Wheel zoom   F focus unit"
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(1, 1, 1, 0.6)
	box.add_child(help)

	_overlay = ColorRect.new()
	_overlay.color = Color(0.05, 0.06, 0.08, 0.97)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.gui_input.connect(_on_overlay_input)
	_overlay.hide()
	layer.add_child(_overlay)
	_overlay_label = Label.new()
	_overlay_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 32)
	_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_overlay_label)


func _add_button(parent: Control, action: String, text: String) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_action.bind(action))
	parent.add_child(button)
	_buttons[action] = button


func _rich_label(min_height: float) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.focus_mode = Control.FOCUS_NONE
	label.custom_minimum_size = Vector2(0, min_height)
	return label


# --- Drawing ---

func _draw() -> void:
	_draw_ground()
	_draw_ground_overlays()
	_draw_world()
	_draw_markers()
	_draw_effects()


func _draw_ground() -> void:
	var map := battle.map
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var terrain := map.get_terrain(p)
			var color: Color = TERRAIN_COLORS[terrain]
			if (x + y) % 2 == 1:
				color = color.darkened(0.06)
			draw_colored_polygon(_tile_poly(p), color)
			var center := _center(p)
			if terrain == TacticalMap.Terrain.ROUGH:
				for o: Vector2 in [Vector2(-0.22, -0.18), Vector2(0.2, -0.05), Vector2(-0.05, 0.22)]:
					var at := _proj.project(center + o)
					draw_line(at, _proj.project(center + o, 0.18) + Vector2(2, 0), Color("8f8752"), 2.0)
			elif terrain == TacticalMap.Terrain.RUBBLE:
				for o: Vector2 in [Vector2(-0.2, -0.15), Vector2(0.15, 0.1), Vector2(-0.1, 0.25), Vector2(0.22, -0.22)]:
					draw_colored_polygon(_diamond(center + o, 0.08), Color("80746a"))
			if not _visible_tiles.has(p):
				draw_colored_polygon(_tile_poly(p), Color(0, 0, 0, 0.45))
	for y in map.height:
		for x in map.width:
			draw_polyline(_tile_outline(Vector2i(x, y)), Color(0, 0, 0, 0.18), 1.0)


func _draw_ground_overlays() -> void:
	if busy or selected == null:
		return
	if mode == Mode.MOVE and not _reach.is_empty():
		for p: Vector2i in _reach:
			if p != selected.pos:
				draw_colored_polygon(_tile_poly(p), (MOVE_COLOR if _move_tiles.has(p) else DASH_COLOR) * Color(1, 1, 1, 0.12))
		_draw_region_border(_reach, DASH_COLOR)
		_draw_region_border(_move_tiles, MOVE_COLOR)
	if not battle.map.in_bounds(hover):
		return
	draw_polyline(_tile_outline(hover), Color(1, 1, 1, 0.8), 2.0)
	match mode:
		Mode.MOVE:
			if _reach.has(hover) and hover != selected.pos:
				var color := MOVE_COLOR if _move_tiles.has(hover) else DASH_COLOR
				var points := PackedVector2Array([_proj.project(_center(selected.pos))])
				for p in Pathfinder.path_to(_reach, hover):
					points.append(_proj.project(_center(p)))
				draw_polyline(points, color, 3.0)
				draw_polyline(_ground_circle(_center(hover), 0.3), color, 2.5)
		Mode.GRENADE:
			draw_polyline(_ground_circle(_center(selected.pos), CombatRules.GRENADE_RANGE), Color(1, 0.7, 0.3, 0.5), 1.5)
			if battle.can_throw_grenade(selected, hover) == "":
				for p in battle.map.tiles_in_radius(hover, CombatRules.GRENADE_RADIUS):
					draw_colored_polygon(_tile_poly(p), Color(1, 0.55, 0.1, 0.4))
		Mode.MEDKIT:
			for u in battle.alive_units(selected.team):
				if battle.can_use_medkit(selected, u) == "":
					draw_polyline(_ground_circle(_display_pos[u.id], 0.45), Color("6bff8a"), 2.5)


## Outlines the boundary of a set of tiles, like XCOM's move range border.
func _draw_region_border(tiles: Dictionary, color: Color) -> void:
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for p: Vector2i in tiles:
		for i in 4:
			if not tiles.has(p + TacticalMap.DIRS4[i]):
				var a: Vector2 = Vector2(p) + corners[i]
				var b: Vector2 = Vector2(p) + corners[(i + 1) % 4]
				draw_line(_proj.project(a), _proj.project(b), color, 2.5)


## Objects, walls and units, painted back to front.
func _draw_world() -> void:
	var map := battle.map
	var items := []
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if map.get_object(p) != Cover.NONE:
				items.append([_proj.depth(_center(p)), "object", p])
	for key: Vector3i in map.get_edges():
		var pair := TacticalMap.edge_tiles(key)
		items.append([_proj.depth((_center(pair[0]) + _center(pair[1])) * 0.5), "edge", key])
	var focus: Array[Vector2] = []
	if map.in_bounds(hover):
		focus.append(_center(hover))
	for u in battle.units:
		if _is_drawn(u):
			items.append([_proj.depth(_display_pos[u.id]) + 0.01, "unit", u])
			if _display_hp[u.id] > 0:
				focus.append(_display_pos[u.id])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])

	for item: Array in items:
		match item[1]:
			"object":
				var p: Vector2i = item[2]
				var full := map.get_object(p) == Cover.FULL
				var rect := Rect2(Vector2(p), Vector2.ONE).grow(-0.04 if full else -0.17)
				var color := ROCK_COLOR if full else CRATE_COLOR
				if not _visible_tiles.has(p):
					color = color.darkened(0.45)
				_draw_prism(rect, FULL_HEIGHT if full else HALF_HEIGHT, color, _occludes(_center(p), focus))
			"edge":
				var key: Vector3i = item[2]
				var pair := TacticalMap.edge_tiles(key)
				var full: bool = map.get_edges()[key] == Cover.FULL
				var rect := Rect2(key.x + 1 - WALL_THICKNESS, key.y, WALL_THICKNESS * 2, 1) if key.z == 0 \
						else Rect2(key.x, key.y + 1 - WALL_THICKNESS, 1, WALL_THICKNESS * 2)
				var color := WALL_COLOR if full else LOW_WALL_COLOR
				if not _visible_tiles.has(pair[0]) and not _visible_tiles.has(pair[1]):
					color = color.darkened(0.45)
				_draw_prism(rect, FULL_HEIGHT if full else HALF_HEIGHT, color, _occludes(rect.get_center(), focus))
			"unit":
				_draw_unit(item[2])


func _is_drawn(u: Unit) -> bool:
	if _display_hp[u.id] <= 0:
		return true
	return u.team == battle.current_team or _seen_units.has(u.id) or _revealed.has(u.id)


## Whether a tall thing at grid point g stands in front of any focus point, hiding it.
func _occludes(g: Vector2, focus: Array[Vector2]) -> bool:
	if not _proj.isometric:
		return false
	var r := _proj.rotate_grid(g)
	for f in focus:
		var rf := _proj.rotate_grid(f)
		if r.x + r.y > rf.x + rf.y + 0.1 and r.x > rf.x - 0.7 and r.y > rf.y - 0.7 and r.distance_to(rf) < 2.6:
			return true
	return false


## A box standing on the grid rect. Iso shows top and the two viewer-facing sides; top-down shows the top with a shadow.
func _draw_prism(rect: Rect2, height: float, color: Color, faded: bool) -> void:
	var a := _proj.rotate_grid(rect.position)
	var b := _proj.rotate_grid(rect.end)
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var corners := [lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)]
	var alpha := 0.3 if faded else 1.0
	var top := PackedVector2Array()
	for c: Vector2 in corners:
		top.append(_proj.project_rotated(c, height))
	if _proj.isometric:
		for side: Array in [[1, 2, color.darkened(0.25)], [3, 2, color.darkened(0.45)]]:
			var c0: Vector2 = corners[side[0]]
			var c1: Vector2 = corners[side[1]]
			var face := PackedVector2Array([
				_proj.project_rotated(c0), _proj.project_rotated(c1),
				_proj.project_rotated(c1, height), _proj.project_rotated(c0, height),
			])
			var shade: Color = side[2]
			draw_colored_polygon(face, Color(shade, alpha))
	else:
		var shadow := PackedVector2Array()
		for point in top:
			shadow.append(point + Vector2(1, 1) * height * 7.0)
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	draw_colored_polygon(top, Color(color.lightened(0.12), alpha))
	top.append(top[0])
	draw_polyline(top, Color(color.darkened(0.5), alpha), 1.0)


func _draw_unit(u: Unit) -> void:
	var g: Vector2 = _display_pos[u.id]
	var color: Color = TEAM_COLORS[u.team]
	var ground := _proj.project(g)
	if _display_hp[u.id] <= 0:
		draw_line(ground - Vector2(7, 4), ground + Vector2(7, 4), color.darkened(0.4), 3.0)
		draw_line(ground - Vector2(-7, 4), ground + Vector2(-7, 4), color.darkened(0.4), 3.0)
		return
	draw_colored_polygon(_ground_circle(g, 0.3, false), Color(0, 0, 0, 0.35))
	if u == selected:
		draw_polyline(_ground_circle(g, 0.42), Color.WHITE, 2.5)
	if mode == Mode.SHOOT and _target_odds.has(u.id):
		var hovered := battle.map.in_bounds(hover) and battle.unit_at(hover) == u
		draw_polyline(_ground_circle(g, 0.45), Color("ff4040") if hovered else Color("ff8080"), 3.0 if hovered else 1.5)
	var head := _proj.project(g, 0.75)
	if _proj.isometric:
		draw_rect(Rect2(ground.x - 7, head.y, 14, ground.y - head.y), color.darkened(0.35))
	draw_circle(head, 11, color)
	draw_arc(head, 11, 0, TAU, 24, color.darkened(0.55), 1.5)
	draw_string(_font, head + Vector2(-8, 5), u.role[0], HORIZONTAL_ALIGNMENT_CENTER, 16, 13, Color.BLACK)


## Unit HP, status and target labels, drawn above everything so walls never hide them.
func _draw_markers() -> void:
	for u in battle.units:
		if _display_hp[u.id] <= 0 or not _is_drawn(u):
			continue
		var top := _proj.project(_display_pos[u.id], 0.75) + Vector2(0, -15)
		var pip_w := 24.0 / u.max_hp
		draw_rect(Rect2(top + Vector2(-13, -1), Vector2(26, 5)), Color(0, 0, 0, 0.6))
		for i in u.max_hp:
			draw_rect(Rect2(top + Vector2(-12 + i * pip_w, 0), Vector2(pip_w - 1, 3)), Color("6bff8a") if i < _display_hp[u.id] else Color("3a3a3a"))
		if u.team == battle.current_team:
			for i in u.actions:
				draw_circle(top + Vector2(17 + i * 6, 1), 2.5, Color("f5c542"))
		var status := "OVERWATCH" if u.overwatch else ("HUNKERED" if u.hunkered else "")
		if status != "":
			draw_string(_font, top + Vector2(-40, -5), status, HORIZONTAL_ALIGNMENT_CENTER, 80, 10, Color("ffd34d") if u.overwatch else Color("8fd3ff"))
		if mode == Mode.SHOOT and _target_odds.has(u.id):
			draw_string(_font, top + Vector2(-30, -18), "%d%%" % _target_odds[u.id], HORIZONTAL_ALIGNMENT_CENTER, 60, 15, Color.WHITE)
	if busy or selected == null or not battle.map.in_bounds(hover) or mode != Mode.MOVE or not _reach.has(hover) or hover == selected.pos:
		return
	# Cover shields on each side of the move destination, and lines to enemies that would flank it.
	var center := _center(hover)
	for d: Vector2i in TacticalMap.DIRS4:
		var c := battle.map.cover_toward(hover, d)
		if c != Cover.NONE:
			_draw_shield(_proj.project(center + Vector2(d) * 0.36, 0.5), c == Cover.FULL)
	for e in _flankers:
		draw_dashed_line(_proj.project(center, 0.5), _proj.project(_display_pos[e.id], 0.5), Color(1, 0.3, 0.3, 0.8), 2.0, 6.0)
	if not _move_tiles.has(hover):
		draw_string(_font, _proj.project(center) + Vector2(-30, 20), "DASH", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, DASH_COLOR)


func _draw_shield(at: Vector2, full: bool) -> void:
	var shape := PackedVector2Array([at + Vector2(-6, -7), at + Vector2(6, -7), at + Vector2(6, 1), at + Vector2(0, 7), at + Vector2(-6, 1)])
	draw_colored_polygon(shape, Color("8fd3ff") if full else Color(0.1, 0.15, 0.2, 0.8))
	if not full:
		draw_colored_polygon(PackedVector2Array([at + Vector2(-6, 0), at + Vector2(6, 0), at + Vector2(6, 1), at + Vector2(0, 7), at + Vector2(-6, 1)]), Color("8fd3ff"))
	shape.append(shape[0])
	draw_polyline(shape, Color("0d2030"), 1.5)


func _draw_effects() -> void:
	for fx in _effects:
		var t: float = fx["age"] / fx["life"]
		match fx["kind"]:
			"tracer":
				draw_line(_proj.project(fx["from"], 0.6), _proj.project(fx["to"], 0.6), Color(1, 0.9, 0.5, 1.0 - t), 2.5)
			"explosion":
				draw_colored_polygon(_ground_circle(fx["at"], fx["radius"] * (0.4 + 0.6 * t), false), Color(1, 0.55, 0.15, 0.6 * (1.0 - t)))
	for f in _floaters:
		var t: float = f["age"] / f["life"]
		var color: Color = f["color"]
		color.a = 1.0 - t * t
		var at: Vector2 = _proj.project(f["at"], 1.2) + Vector2(-90, -20 - 24 * t)
		draw_string(_font, at + Vector2(1, 1), f["text"], HORIZONTAL_ALIGNMENT_CENTER, 180, 14, Color(0, 0, 0, color.a))
		draw_string(_font, at, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 180, 14, color)


func _center(p: Vector2i) -> Vector2:
	return Vector2(p) + Vector2(0.5, 0.5)


func _tile_poly(p: Vector2i) -> PackedVector2Array:
	var g := Vector2(p)
	return PackedVector2Array([
		_proj.project(g), _proj.project(g + Vector2(1, 0)),
		_proj.project(g + Vector2(1, 1)), _proj.project(g + Vector2(0, 1)),
	])


func _tile_outline(p: Vector2i) -> PackedVector2Array:
	var poly := _tile_poly(p)
	poly.append(poly[0])
	return poly


func _diamond(g: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		_proj.project(g + Vector2(-r, 0)), _proj.project(g + Vector2(0, -r)),
		_proj.project(g + Vector2(r, 0)), _proj.project(g + Vector2(0, r)),
	])


## A circle on the ground, radius in tiles. Closed for outlines; open (no repeated point) for filling.
func _ground_circle(g: Vector2, radius: float, closed := true) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segments := clampi(int(radius * 16), 16, 96)
	for i in segments:
		points.append(_proj.project(g + Vector2.from_angle(TAU * i / segments) * radius))
	if closed:
		points.append(points[0])
	return points
