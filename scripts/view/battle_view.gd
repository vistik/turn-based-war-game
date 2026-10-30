extends Node2D
## View of a Battle: draws the battlefield (isometric or top-down), takes player input, runs AI turns
## and plays back engine events. All art is procedural (TerrainPainter, SoldierPainter).
## The static ground is drawn on a child layer that only repaints when something changes;
## everything else repaints every frame so soldiers can animate.

const DrawLayer := preload("res://scripts/view/draw_layer.gd")

const PANEL_WIDTH := 400.0
const TEAM_COLORS := [Color("4aa3ff"), Color("ff6150")]
const TEAM_NAMES := ["Blue", "Red"]
const MOVE_COLOR := Color("4aa3ff")
const DASH_COLOR := Color("f5c542")
const KEY_ACTIONS := {
	KEY_1: "shoot", KEY_2: "overwatch", KEY_3: "hunker", KEY_4: "reload",
	KEY_5: "grenade", KEY_6: "medkit", KEY_TAB: "next", KEY_ENTER: "end", KEY_KP_ENTER: "end",
}
const ACTION_BUTTONS := [
	["shoot", "1 Shoot"], ["overwatch", "2 Overwatch"], ["hunker", "3 Hunker"], ["reload", "4 Reload"],
	["grenade", "5 Grenade"], ["medkit", "6 Medkit"], ["next", "Tab Next unit"], ["end", "Enter End turn"],
]
## [label, Blue is AI, Red is AI]
const GAME_MODES := [["Play vs AI (you are Blue)", false, true], ["Hotseat: two players", false, false], ["Watch AI vs AI", true, true]]
const SHOT_LABELS := {"miss": "MISS", "graze": "GRAZE", "hit": "HIT", "crit": "CRITICAL"}
## Playback speeds; 0 means instant.
const SPEEDS := [1.0, 2.0, 4.0, 0.0]
const SPEED_NAMES := ["1x", "2x", "4x", "Instant"]
const ZOOM_MIN := 0.35
const ZOOM_MAX := 2.5
const PAN_SPEED := 700.0

enum Mode { MOVE, SHOOT, GRENADE, MEDKIT }

var battle: Battle
## Per team: null for a human player, otherwise the TacticalAI playing it.
var controllers := [null, null]
var selected: Unit
var mode := Mode.MOVE
var hover := Vector2i(-1, -1)
var busy := false

var _proj: ViewProjection
var _camera: Camera2D
var _ground: Node2D
var _dragging := false
var _speed_index := 0
var _time := 0.0
var _turn_started := false
var _reach := {}
var _move_tiles := {}
var _visible_tiles := {}
var _seen_units := {}
var _target_odds := {}
var _flankers: Array[Unit] = []
## Presentation state that trails the engine while events play back. Positions are in grid space.
var _display_pos := {}
var _display_hp := {}
var _facing := {}
var _walking := {}
var _hit_at := {}
var _died_at := {}
## Units forced visible (e.g. while shooting) or tracked step by step while moving through fog.
var _revealed := {}
var _move_visibility := {}
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
var _menu: Control
var _banner: Label


func _ready() -> void:
	_font = ThemeDB.fallback_font
	battle = SkirmishScenario.build()
	_proj = ViewProjection.new(Vector2(battle.map.width, battle.map.height))
	_ground = DrawLayer.new()
	_ground.z_index = -1
	_ground.painter = _paint_ground
	add_child(_ground)
	_camera = Camera2D.new()
	add_child(_camera)
	for u in battle.units:
		_display_pos[u.id] = _center(u.pos)
		_display_hp[u.id] = u.hp
		_facing[u.id] = Vector2(1, 0) if u.team == 0 else Vector2(-1, 0)
	_build_ui()
	_focus(Vector2(battle.map.width, battle.map.height) * 0.5, false)
	_refresh()
	_show_overlay("setup", "", Color.WHITE)


func _start_game(mode_index: int) -> void:
	for team in 2:
		controllers[team] = TacticalAI.new(battle, team) if GAME_MODES[mode_index][team + 1] else null
	if controllers[0] != null and controllers[1] != null:
		_speed_index = 1
	_update_speed_button()
	_overlay_state = ""
	_overlay.hide()
	_run(battle.start())


func _process(delta: float) -> void:
	_time += delta
	_pan_with_keys(delta)
	if not busy and _overlay_state == "":
		_set_hover(_mouse_tile())
	for item in _floaters + _effects:
		item["age"] += delta
	_floaters = _floaters.filter(func(f: Dictionary) -> bool: return f["age"] < f["life"])
	_effects = _effects.filter(func(f: Dictionary) -> bool: return f["age"] < f["life"])
	queue_redraw()


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if _overlay_state != "":
		if event is InputEventKey and event.pressed and not event.echo and _overlay_state != "setup":
			_dismiss_overlay()
		return
	if _handle_camera_input(event):
		get_viewport().set_input_as_handled()
		return
	if busy or not _is_human_turn():
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


## Zoom, drag, rotate, view toggle and speed. Returns true when the event was used.
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
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				_change_speed(1)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_change_speed(-1)
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
		"speed":
			_change_speed(1, true)
			return
	if busy or _overlay_state != "" or battle.winner != -1 or not _is_human_turn():
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
	if event is InputEventMouseButton and event.pressed and _overlay_state != "setup":
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


func _mouse_tile() -> Vector2i:
	if get_viewport().get_mouse_position().x >= _panel.global_position.x:
		return Vector2i(-1, -1)
	return _proj.tile_at(get_local_mouse_position())


func _next_ready_unit(after: Unit) -> Unit:
	var ready := battle.alive_units(battle.current_team).filter(func(u: Unit) -> bool: return u.actions > 0)
	if ready.is_empty():
		return null
	return ready[(ready.find(after) + 1) % ready.size()]


func _is_human_turn() -> bool:
	return controllers[battle.current_team] == null


## The team whose fog of war is shown: the only human, the current human in hotseat, or -1 to see everything.
func _view_team() -> int:
	var humans := [0, 1].filter(func(t: int) -> bool: return controllers[t] == null)
	if humans.size() == 2:
		return battle.current_team
	return humans[0] if humans.size() == 1 else -1


# --- Camera ---

## The screen x offset that centres things in the map area left of the side panel.
func _view_shift() -> Vector2:
	return Vector2(PANEL_WIDTH * 0.5, 0) / _camera.zoom.x


func _focus(grid: Vector2, animate := true) -> void:
	var target := _proj.project(grid) + _view_shift()
	if animate and SPEEDS[_speed_index] != 0.0:
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
	_ground.queue_redraw()


func _toggle_view() -> void:
	var focus := _focused_grid()
	_proj.isometric = not _proj.isometric
	_focus(focus, false)
	_ground.queue_redraw()


func _change_speed(step: int, wrap := false) -> void:
	_speed_index = posmod(_speed_index + step, SPEEDS.size()) if wrap else clampi(_speed_index + step, 0, SPEEDS.size() - 1)
	_update_speed_button()


func _update_speed_button() -> void:
	_buttons["speed"].text = "Speed %s" % SPEED_NAMES[_speed_index]


# --- Engine calls, AI turns and event playback ---

func _run(events: Array) -> void:
	busy = true
	_reach = {}
	_move_tiles = {}
	for e: Dictionary in events:
		await _play_event(e)
	_revealed.clear()
	_move_visibility.clear()
	busy = false
	var ai_turn := battle.winner == -1 and _overlay_state == "" and not _is_human_turn()
	if ai_turn:
		selected = null
	elif _turn_started and _overlay_state == "":
		selected = _next_ready_unit(null)
		if selected != null:
			_focus(_display_pos[selected.id])
	elif selected == null or battle.can_act(selected) != "":
		selected = _next_ready_unit(selected)
	_turn_started = false
	mode = Mode.MOVE
	_refresh()
	if ai_turn:
		await get_tree().process_frame
		if SPEEDS[_speed_index] != 0.0:
			await _wait(0.2)
		if battle.winner == -1 and not _is_human_turn():
			_run(controllers[battle.current_team].act())


func _play_event(e: Dictionary) -> void:
	match e["type"]:
		"move":
			await _play_move(e)
		"shot":
			await _play_shot(e)
		"damage":
			var u := battle.get_unit(e["unit"])
			_display_hp[u.id] = e["hp"]
			_hit_at[u.id] = _time
			var text := "-%d" % e["amount"]
			if e["absorbed"] > 0:
				text += " (armor %d)" % e["absorbed"]
			_float(_display_pos[u.id], text, Color("ff7b6b"))
			await _wait(0.4)
		"death":
			var u := battle.get_unit(e["unit"])
			_died_at[u.id] = _time
			_float(_display_pos[u.id], "KILLED", Color("ff3b3b"))
			_log_line("[color=#ff6b6b]%s was killed.[/color]" % u.name)
			await _wait(0.6)
		"explosion":
			var u := battle.get_unit(e["unit"])
			_effects.append({"kind": "explosion", "at": _center(e["center"]), "radius": e["radius"] + 0.5, "age": 0.0, "life": 1.4})
			_ground.queue_redraw()
			_log_line("%s throws a grenade, destroying %d pieces of cover." % [u.name, e["destroyed"]])
			await _wait(0.6)
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
			var team: int = e["team"]
			var who := "%s team%s" % [TEAM_NAMES[team], " (AI)" if controllers[team] != null else ""]
			_log_line("[b][color=%s]Round %d: %s[/color][/b]" % [TEAM_COLORS[team].to_html(false), e["round"], who])
			_turn_started = true
			if controllers[0] == null and controllers[1] == null:
				_show_overlay("handover", "%s team's turn\n\nClick or press any key" % TEAM_NAMES[team], TEAM_COLORS[team])
			else:
				_show_banner("%s's turn" % who, TEAM_COLORS[team])
		"game_over":
			_log_line("[b]%s team wins![/b]" % TEAM_NAMES[e["winner"]])
			_show_overlay("game_over", "%s team wins!\n\nClick or press any key for the menu" % TEAM_NAMES[e["winner"]], TEAM_COLORS[e["winner"]])


func _play_move(e: Dictionary) -> void:
	var u := battle.get_unit(e["unit"])
	var path: Array = e["path"]
	var watched := u.team != _view_team() and _view_team() != -1
	if controllers[u.team] != null and (not watched or _viewer_sees(path[0]) or _viewer_sees(path[-1])):
		_focus(_center(path[int(path.size() / 2.0)]))
	_walking[u.id] = true
	for i in range(1, path.size()):
		_facing[u.id] = Vector2(path[i] - path[i - 1]).normalized()
		if watched:
			_move_visibility[u.id] = _viewer_sees(path[i])
		await _tween_unit(u.id, _center(path[i]), 0.16)
	_walking.erase(u.id)


func _play_shot(e: Dictionary) -> void:
	var shooter := battle.get_unit(e["shooter"])
	var target := battle.get_unit(e["target"])
	_revealed[shooter.id] = true
	_revealed[target.id] = true
	_facing[shooter.id] = (_display_pos[target.id] - _display_pos[shooter.id]).normalized()
	if e["reaction"]:
		_float(_display_pos[shooter.id], "OVERWATCH!", Color("ffd34d"))
		await _wait(0.45)
	else:
		await _wait(0.15)
	var from := SoldierPainter.muzzle(_proj, _display_pos[shooter.id], shooter, _pose(shooter))
	var to := _proj.project(_display_pos[target.id], 0.7)
	var hit: bool = e["result"] != "miss"
	if not hit:
		to = _proj.project(_display_pos[target.id] + Vector2.from_angle(randf() * TAU) * 0.7, 0.3)
	_effects.append({"kind": "muzzle", "at": from, "age": 0.0, "life": 0.1})
	_effects.append({"kind": "tracer", "from": from, "to": to, "age": 0.0, "life": 0.25})
	await _wait(0.12)
	_effects.append({"kind": "sparks" if hit else "puff", "at": to, "age": 0.0, "life": 0.4})
	await _wait(0.15)
	var label: String = SHOT_LABELS[e["result"]]
	_float(_display_pos[target.id], "%s (%d%%)" % [label, e["chance"]], Color.WHITE if e["result"] != "crit" else Color("ffb84d"))
	_log_line("%s%s shoots at %s: %s (%d%%)" % ["Overwatch: " if e["reaction"] else "", shooter.name, target.name, label, e["chance"]])
	await _wait(0.25)


func _viewer_sees(tile: Vector2i) -> bool:
	var team := _view_team()
	if team == -1:
		return true
	for u in battle.alive_units(team):
		if LineOfSight.can_see(battle.map, u.pos, tile, u.sight):
			return true
	return false


func _tween_unit(id: int, to: Vector2, duration: float) -> void:
	var speed: float = SPEEDS[_speed_index]
	if speed == 0.0:
		_display_pos[id] = to
		return
	var tween := create_tween()
	tween.tween_method(_set_display_pos.bind(id), _display_pos[id], to, duration / speed)
	await tween.finished


func _set_display_pos(pos: Vector2, id: int) -> void:
	_display_pos[id] = pos


func _wait(seconds: float) -> void:
	var speed: float = SPEEDS[_speed_index]
	if speed == 0.0:
		return
	await get_tree().create_timer(seconds / speed).timeout


## Rising text over a grid position.
func _float(at: Vector2, text: String, color: Color) -> void:
	_floaters.append({"text": text, "at": at, "color": color, "age": 0.0, "life": 1.2})


func _flash(message: String) -> void:
	var at: Vector2 = _display_pos[selected.id] if selected != null else _center(hover)
	_float(at, message, Color("ff9b8a"))


# --- State caches and side panel ---

func _refresh() -> void:
	var view := _view_team()
	_visible_tiles.clear()
	_seen_units.clear()
	if view == -1:
		for y in battle.map.height:
			for x in battle.map.width:
				_visible_tiles[Vector2i(x, y)] = true
		for u in battle.alive_units():
			_seen_units[u.id] = true
	else:
		_visible_tiles = battle.team_visible_tiles(view)
		for u in battle.alive_units():
			if battle.team_sees(view, u):
				_seen_units[u.id] = true
	var can_act := selected != null and battle.can_act(selected) == "" and _is_human_turn()
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
	_ground.queue_redraw()


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
	var team := battle.current_team
	_turn_label.text = "Round %d: %s team%s" % [battle.round_number, TEAM_NAMES[team], " (AI)" if controllers[team] != null else ""]
	_turn_label.add_theme_color_override("font_color", TEAM_COLORS[team])
	if not _is_human_turn():
		_unit_info.text = "[i]%s team is taking its turn...[/i]" % TEAM_NAMES[team]
	elif selected != null:
		_unit_info.text = _describe_unit(selected)
	else:
		_unit_info.text = "No unit selected.\nClick one of your soldiers."
	var s := selected if _is_human_turn() else null
	_buttons["shoot"].disabled = s == null or battle.can_overwatch(s) != ""
	_buttons["overwatch"].disabled = s == null or battle.can_overwatch(s) != ""
	_buttons["hunker"].disabled = s == null or battle.can_hunker(s) != ""
	_buttons["reload"].disabled = s == null or battle.can_reload(s) != ""
	_buttons["grenade"].disabled = s == null or battle.can_act(s) != "" or s.grenades <= 0
	_buttons["medkit"].disabled = s == null or battle.can_act(s) != "" or s.medkits <= 0
	_buttons["next"].disabled = s == null or _next_ready_unit(s) == null
	_buttons["end"].disabled = battle.winner != -1 or not _is_human_turn()


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
	if selected != null and map.in_bounds(hover) and _is_human_turn():
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
	_overlay_label.visible = state != "setup"
	_menu.visible = state == "setup"
	_overlay.show()


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.6)


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

	var view_row := HFlowContainer.new()
	box.add_child(view_row)
	_add_button(view_row, "rotate_left", "Q Rotate left")
	_add_button(view_row, "rotate_right", "E Rotate right")
	_add_button(view_row, "toggle_view", "V Iso / top")
	_add_button(view_row, "speed", "Speed 1x")
	var help := Label.new()
	help.text = "LMB select / move / target   RMB, Esc cancel\nWASD or middle drag pan   Wheel zoom   F focus   +/- speed"
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(1, 1, 1, 0.6)
	box.add_child(help)

	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -400 - PANEL_WIDTH * 0.5
	_banner.offset_right = 400 - PANEL_WIDTH * 0.5
	_banner.offset_top = 24
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 30)
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	layer.add_child(_banner)

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

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	_menu = center
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 14)
	center.add_child(menu)
	var title := Label.new()
	title.text = "Tactical Skirmish"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	menu.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Four soldiers a side. Use cover, flank, don't bunch up."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.6)
	menu.add_child(subtitle)
	for i in GAME_MODES.size():
		var button := Button.new()
		button.text = GAME_MODES[i][0]
		button.custom_minimum_size = Vector2(340, 48)
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(_start_game.bind(i))
		menu.add_child(button)


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

## Ground, fog and cast shadows: the static layer under everything else.
func _paint_ground(c: CanvasItem) -> void:
	var map := battle.map
	for y in map.height:
		for x in map.width:
			TerrainPainter.draw_tile(c, _proj, map, Vector2i(x, y))
	for y in map.height:
		for x in map.width:
			if map.get_object(Vector2i(x, y)) != Cover.NONE:
				TerrainPainter.draw_object_shadow(c, _proj, map, Vector2i(x, y))
	for key: Vector3i in map.get_edges():
		TerrainPainter.draw_edge_shadow(c, _proj, map, key)
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if not _visible_tiles.has(p):
				c.draw_colored_polygon(TerrainPainter.tile_poly(_proj, p), Color(0.02, 0.03, 0.06, 0.5))
			c.draw_polyline(_tile_outline(p), Color(0, 0, 0, 0.1), 1.0)


func _draw() -> void:
	_draw_ground_overlays()
	_draw_world()
	_draw_markers()
	_draw_effects()


func _draw_ground_overlays() -> void:
	if busy or selected == null or not _is_human_turn():
		return
	if mode == Mode.MOVE and not _reach.is_empty():
		for p: Vector2i in _reach:
			if p != selected.pos:
				draw_colored_polygon(TerrainPainter.tile_poly(_proj, p), (MOVE_COLOR if _move_tiles.has(p) else DASH_COLOR) * Color(1, 1, 1, 0.1))
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
					draw_colored_polygon(TerrainPainter.tile_poly(_proj, p), Color(1, 0.55, 0.1, 0.4))
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


## Props, walls and soldiers, painted back to front.
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
	if map.in_bounds(hover) and _is_human_turn():
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
				TerrainPainter.draw_object(self, _proj, map, p, 0.3 if _occludes(_center(p), focus) else 1.0, not _visible_tiles.has(p))
			"edge":
				var key: Vector3i = item[2]
				var pair := TacticalMap.edge_tiles(key)
				var mid := (_center(pair[0]) + _center(pair[1])) * 0.5
				var dark := not _visible_tiles.has(pair[0]) and not _visible_tiles.has(pair[1])
				TerrainPainter.draw_edge(self, _proj, map, key, 0.3 if _occludes(mid, focus) else 1.0, dark)
			"unit":
				_draw_unit(item[2])


func _is_drawn(u: Unit) -> bool:
	if _display_hp[u.id] <= 0:
		return true
	if _revealed.has(u.id):
		return true
	if _move_visibility.has(u.id):
		return _move_visibility[u.id]
	return _view_team() == -1 or u.team == _view_team() or _seen_units.has(u.id)


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


func _pose(u: Unit) -> Dictionary:
	var death := 0.0
	if _display_hp[u.id] <= 0:
		death = clampf((_time - _died_at.get(u.id, -10.0)) / 0.45, 0.0, 1.0)
	return {
		"facing": _facing[u.id],
		"walk": 1.0 if _walking.has(u.id) else 0.0,
		"phase": _time * 14.0 + u.id,
		"crouch": u.hunkered and death == 0.0,
		"death": death,
		"flash": clampf(1.0 - (_time - _hit_at.get(u.id, -10.0)) / 0.3, 0.0, 1.0),
		"breath": _time * 2.2 + u.id * 1.7,
	}


func _draw_unit(u: Unit) -> void:
	var g: Vector2 = _display_pos[u.id]
	var pose := _pose(u)
	if pose["death"] > 0.0:
		var facing: Vector2 = pose["facing"]
		draw_colored_polygon(_ground_circle(g - facing * 0.3, 0.05 + 0.25 * pose["death"], false), Color(0.35, 0.03, 0.03, 0.7))
	else:
		draw_colored_polygon(_ground_circle(g + TerrainPainter.LIGHT * 0.25, 0.26, false), Color(0, 0, 0, 0.3))
		if u == selected:
			draw_polyline(_ground_circle(g, 0.42), Color.WHITE, 2.5)
		if mode == Mode.SHOOT and _target_odds.has(u.id):
			var hovered := battle.map.in_bounds(hover) and battle.unit_at(hover) == u
			draw_polyline(_ground_circle(g, 0.45), Color("ff4040") if hovered else Color("ff8080"), 3.0 if hovered else 1.5)
	SoldierPainter.draw(self, _proj, g, u, TEAM_COLORS[u.team], pose)


## Unit HP, status and target labels, drawn above everything so walls never hide them.
func _draw_markers() -> void:
	for u in battle.units:
		if _display_hp[u.id] <= 0 or not _is_drawn(u):
			continue
		var top := _proj.project(_display_pos[u.id], 1.15) + Vector2(0, -14)
		var pip_w := 26.0 / u.max_hp
		draw_rect(Rect2(top + Vector2(-14, -1), Vector2(28, 5)), Color(0, 0, 0, 0.65))
		for i in u.max_hp:
			draw_rect(Rect2(top + Vector2(-13 + i * pip_w, 0), Vector2(pip_w - 1, 3)), Color("6bff8a") if i < _display_hp[u.id] else Color("3a3a3a"))
		draw_rect(Rect2(top + Vector2(-14, 5), Vector2(28, 2)), TEAM_COLORS[u.team])
		if u.team == battle.current_team and _is_human_turn():
			for i in u.actions:
				draw_circle(top + Vector2(19 + i * 6, 2), 2.5, Color("f5c542"))
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
			"muzzle":
				var at: Vector2 = fx["at"]
				draw_circle(at, 7.0 * (1.0 - t), Color(1, 0.95, 0.6, 1.0 - t))
				for i in 4:
					draw_line(at, at + Vector2.from_angle(i * TAU / 4 + 0.6) * 11.0 * (1.0 - t), Color(1, 0.8, 0.3, 1.0 - t), 2.0)
			"tracer":
				var from: Vector2 = fx["from"]
				var to: Vector2 = fx["to"]
				var head := from.lerp(to, minf(1.0, t * 2.5))
				var tail := from.lerp(to, maxf(0.0, t * 2.5 - 0.6))
				draw_line(tail, head, Color(1, 0.85, 0.4, 0.4), 4.0)
				draw_line(tail, head, Color(1, 1, 0.8, 1.0), 1.5)
			"sparks":
				var at: Vector2 = fx["at"]
				for i in 6:
					var dir := Vector2.from_angle(i * TAU / 6 + 0.3)
					draw_line(at + dir * 14.0 * t, at + dir * (4.0 + 14.0 * t), Color(1, 0.7, 0.3, 1.0 - t), 2.0)
			"puff":
				draw_circle(fx["at"] + Vector2(0, -8.0 * t), 4.0 + 8.0 * t, Color(0.7, 0.66, 0.58, 0.5 * (1.0 - t)))
			"explosion":
				_draw_explosion(fx["at"], fx["radius"], t)
	for f in _floaters:
		var t: float = f["age"] / f["life"]
		var color: Color = f["color"]
		color.a = 1.0 - t * t
		var at: Vector2 = _proj.project(f["at"], 1.4) + Vector2(-90, -20 - 24 * t)
		draw_string_outline(_font, at, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 180, 14, 4, Color(0, 0, 0, color.a))
		draw_string(_font, at, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 180, 14, color)


## Flash, fireball, then rising smoke and flying debris.
func _draw_explosion(center: Vector2, radius: float, t: float) -> void:
	if t < 0.35:
		var k := t / 0.35
		draw_colored_polygon(_ground_circle(center, radius * (0.5 + 0.5 * k), false), Color(1, 0.5, 0.1, 0.55 * (1.0 - k)))
		draw_circle(_proj.project(center, 0.3), 30.0 * (0.4 + k), Color(1, 0.75 + 0.2 * (1.0 - k), 0.4, 0.9 * (1.0 - k)))
	for i in 7:
		var dir := Vector2.from_angle(i * TAU / 7 + 0.5)
		var drift := center + dir * radius * 0.4 * t
		draw_circle(_proj.project(drift, 0.2 + t * 1.2 + (i % 3) * 0.15), 9.0 + 16.0 * t, Color(0.35, 0.33, 0.3, 0.55 * (1.0 - t)))
	if t < 0.6:
		var k := t / 0.6
		for i in 10:
			var dir := Vector2.from_angle(i * TAU / 10 + 0.2)
			var height := 1.2 * k * (1.0 - k) * 4.0 * (0.5 + 0.5 * ((i * 7) % 3) / 2.0)
			draw_rect(Rect2(_proj.project(center + dir * radius * 1.1 * k, height), Vector2(3, 3)), Color(0.25, 0.22, 0.2, 1.0 - k))


func _center(p: Vector2i) -> Vector2:
	return Vector2(p) + Vector2(0.5, 0.5)


func _tile_outline(p: Vector2i) -> PackedVector2Array:
	var poly := TerrainPainter.tile_poly(_proj, p)
	poly.append(poly[0])
	return poly


## A circle on the ground, radius in tiles. Closed for outlines; open (no repeated point) for filling.
func _ground_circle(g: Vector2, radius: float, closed := true) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segments := clampi(int(radius * 16), 16, 96)
	for i in segments:
		points.append(_proj.project(g + Vector2.from_angle(TAU * i / segments) * radius))
	if closed:
		points.append(points[0])
	return points
