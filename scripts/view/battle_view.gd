extends Node2D
## View of a Battle: draws the battlefield (isometric or top-down), takes player input, runs AI turns
## and plays back engine events. All art is procedural (TerrainPainter, SoldierPainter).
##
## The picture is a retained scene of canvas items so the big map stays fast:
## terrain, shadows and fog are 8x8-tile chunks that repaint lazily when on screen; every prop is its own
## item, recorded once and faded or darkened through its modulate; soldiers and smoke redraw every frame.
## Props and soldiers are depth-sorted by z_index. The view itself draws markers and effects on top.

const DrawLayer := preload("res://scripts/view/draw_layer.gd")

const PANEL_WIDTH := 400.0
## UI accent colours: Allied green and German field grey.
const TEAM_COLORS := [Color("9cc45a"), Color("b8c0c8")]
const NEUTRAL_COLOR := Color("e8e2cf")
const MOVE_COLOR := Color("4aa3ff")
const DASH_COLOR := Color("f5c542")
const KEY_ACTIONS := {
	KEY_1: "shoot", KEY_2: "overwatch", KEY_3: "hunker", KEY_4: "reload", KEY_5: "grenade",
	KEY_6: "smoke", KEY_7: "set_up", KEY_8: "rally", KEY_9: "medkit", KEY_0: "mortar",
	KEY_TAB: "next", KEY_ENTER: "end", KEY_KP_ENTER: "end",
}
const ACTION_BUTTONS := [
	["shoot", "1 Shoot"], ["overwatch", "2 Overwatch"], ["hunker", "3 Hunker"], ["reload", "4 Reload"],
	["grenade", "5 Grenade"], ["smoke", "6 Smoke"], ["set_up", "7 Set up MG"], ["rally", "8 Rally"],
	["medkit", "9 Medkit"], ["mortar", "0 Mortar"], ["next", "Tab Next unit"], ["end", "Enter End turn"],
]
const SHOT_LABELS := {"miss": "MISS", "graze": "GRAZE", "hit": "HIT", "crit": "CRITICAL"}
const ROLE_TAGS := {"Officer": "Lt", "Rifleman": "Rfl", "Medic": "Med", "SMG": "SMG", "MG": "MG", "Sniper": "Snp", "Mortar": "Mtr", "AT": "AT", "Tank": "Tank"}
## Playback speeds; 0 means instant.
const SPEEDS := [1.0, 2.0, 4.0, 0.0]
const SPEED_NAMES := ["1x", "2x", "4x", "Instant"]
const ZOOM_MIN := 0.3
const ZOOM_MAX := 2.5
const PAN_SPEED := 800.0
const CHUNK := 8
## Absolute z_index of each layer. Props and soldiers sit between OVERLAY_Z and TOP_Z by depth.
const GROUND_Z := -4
const SHADOW_Z := -3
const FOG_Z := -2
const OVERLAY_Z := -1
const DEPTH_Z := 40.0
const TOP_Z := 4000
## Chunks repainted per frame, to spread the cost of a full repaint.
const CHUNK_BUDGET := 3

enum Mode { MOVE, SHOOT, GRENADE, SMOKE, MEDKIT, MORTAR }

var battle: Battle
## Per team: null for a human player, otherwise the TacticalAI playing it.
var controllers := [null, null]
var selected: Unit
var mode := Mode.MOVE
var hover := Vector2i(-1, -1)
var busy := false

var _proj: ViewProjection
var _camera: Camera2D
## Chunk -> [ground layer, shadow layer, fog layer], and the chunks waiting to be repainted.
var _chunks := {}
var _dirty_terrain := {}
var _dirty_fog := {}
var _overlay_layer: Node2D
var _layout_revision := -1
var _smoke_revision := -1
var _prop_nodes: Array[Node2D] = []
var _props_by_tile := {}
var _faded := {}
var _unit_nodes := {}
var _smoke_nodes := {}
var _dragging := false
var _speed_index := 0
var _mortar_kind := "he"
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
var _display_suppression := {}
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
var _score_label: RichTextLabel
var _unit_info: RichTextLabel
var _target_info: RichTextLabel
var _log: RichTextLabel
var _buttons := {}
var _overlay: ColorRect
var _overlay_label: Label
var _title_label: Label
var _banner: Label


func _ready() -> void:
	_font = ThemeDB.fallback_font
	if GameSession.battle == null:
		# Started straight from the editor: a quick skirmish against the AI.
		GameSession.campaign = null
		GameSession.start_battle(NormandyScenario.build(), [false, true], "Normandy village")
	battle = GameSession.battle
	_proj = ViewProjection.new(Vector2(battle.map.width, battle.map.height))
	z_index = TOP_Z
	for cy in ceili(battle.map.height / float(CHUNK)):
		for cx in ceili(battle.map.width / float(CHUNK)):
			var chunk := Vector2i(cx, cy)
			_chunks[chunk] = [
				_layer(GROUND_Z, _paint_ground_chunk.bind(chunk)),
				_layer(SHADOW_Z, _paint_shadow_chunk.bind(chunk)),
				_layer(FOG_Z, _paint_fog_chunk.bind(chunk)),
			]
	_overlay_layer = _layer(OVERLAY_Z, _paint_ground_overlays)
	_camera = Camera2D.new()
	_camera.zoom = Vector2(0.9, 0.9)
	add_child(_camera)
	for u in battle.units:
		_add_display_state(u)
	_build_ui()
	for team in 2:
		if GameSession.ai_teams[team]:
			var ai := TacticalAI.new(battle, team)
			ai.load_dict(GameSession.ai_states[team])
			controllers[team] = ai
	if controllers[0] != null and controllers[1] != null:
		_speed_index = 1
	_update_speed_button()
	_focus_on_team(_view_team() if _view_team() != -1 else battle.current_team)
	_refresh()
	if not battle.started:
		_run(battle.start())
	elif controllers[0] == null and controllers[1] == null:
		_show_overlay("handover", "%s's turn\n\nClick or press any key" % Battle.TEAM_NAMES[battle.current_team], TEAM_COLORS[battle.current_team])
	else:
		_turn_started = true
		_run([])


func _focus_on_team(team: int) -> void:
	var sum := Vector2.ZERO
	var count := 0
	for u in battle.alive_units(team):
		sum += _center(u.pos)
		count += 1
	_focus(sum / count if count > 0 else Vector2(battle.map.width, battle.map.height) * 0.5, false)


## Autosave: the battle in its current state, plus the AI's memory.
func _save() -> void:
	for team in 2:
		GameSession.ai_states[team] = controllers[team].to_dict() if controllers[team] != null else {}
	GameSession.save_game()


func _quit_to_menu() -> void:
	if battle.winner == -1:
		_save()
	GameSession.battle = null
	GameSession.show_campaign = GameSession.campaign != null
	get_tree().change_scene_to_file(GameSession.MENU_SCENE)


func _add_display_state(u: Unit) -> void:
	_display_pos[u.id] = _center(u.pos)
	_display_hp[u.id] = u.hp
	_display_suppression[u.id] = u.suppression
	_facing[u.id] = Vector2(1, 0) if u.team == 0 else Vector2(-1, 0)
	_unit_nodes[u.id] = _layer(0, _paint_unit.bind(u))


func _process(delta: float) -> void:
	_time += delta
	_pan_with_keys(delta)
	if battle.map.layout_revision != _layout_revision:
		_layout_revision = battle.map.layout_revision
		_rebuild_props()
		_mark_chunks_dirty(true)
	if battle.map.revision != _smoke_revision:
		_smoke_revision = battle.map.revision
		_sync_smoke()
	_repaint_dirty_chunks()
	_update_units()
	_update_prop_fading()
	for node: Node2D in _smoke_nodes.values():
		node.queue_redraw()
	if not battle.strikes.is_empty():
		_overlay_layer.queue_redraw()
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
		if event is InputEventKey and event.pressed and not event.echo:
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
	var err := ""
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
			err = battle.can_throw_grenade(selected, tile)
			if err == "":
				_run(battle.throw_grenade(selected, tile))
		Mode.SMOKE:
			err = battle.can_throw_smoke(selected, tile)
			if err == "":
				_run(battle.throw_smoke(selected, tile))
		Mode.MORTAR:
			err = battle.can_fire_mortar(selected, tile, _mortar_kind)
			if err == "":
				_run(battle.fire_mortar(selected, tile, _mortar_kind))
		Mode.MEDKIT:
			err = battle.can_use_medkit(selected, u)
			if err == "":
				_run(battle.use_medkit(selected, u))
	if err != "":
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
		"quit":
			if not busy:
				_quit_to_menu()
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
			err = battle.can_fire(selected)
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
		"set_up":
			err = battle.can_set_up(selected)
			if err == "":
				_run(battle.set_up(selected))
		"rally":
			err = battle.can_rally(selected)
			if err == "":
				_run(battle.rally(selected))
		"grenade":
			err = battle.can_act(selected)
			if err == "" and selected.grenades <= 0:
				err = "No grenades left"
			if err == "":
				_set_mode(Mode.GRENADE)
		"smoke":
			err = battle.can_act(selected)
			if err == "" and selected.smoke_grenades <= 0:
				err = "No smoke grenades left"
			if err == "":
				_set_mode(Mode.SMOKE)
		"medkit":
			err = battle.can_act(selected)
			if err == "" and selected.medkits <= 0:
				err = "No medkits left"
			if err == "":
				_set_mode(Mode.MEDKIT)
		"mortar":
			err = battle.can_act(selected)
			if err == "" and selected.role != "Mortar":
				err = "Only the mortar team can fire the mortar"
			if err == "":
				# Pressing again switches between high explosive and smoke rounds.
				if mode == Mode.MORTAR:
					_mortar_kind = "smoke" if _mortar_kind == "he" else "he"
				else:
					_mortar_kind = "he" if selected.mortar_rounds > 0 else "smoke"
				_set_mode(Mode.MORTAR)
	if err != "":
		_flash(err)


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_dismiss_overlay()


func _dismiss_overlay() -> void:
	if _overlay_state == "game_over":
		if GameSession.campaign != null:
			GameSession.campaign.complete_mission(battle)
		GameSession.battle = null
		GameSession.save_game()
		GameSession.show_campaign = GameSession.campaign != null
		get_tree().change_scene_to_file(GameSession.MENU_SCENE)
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
	_overlay_layer.queue_redraw()


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
		create_tween().tween_property(_camera, "position", target, 0.3).set_trans(Tween.TRANS_SINE)
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
	_reproject()


func _toggle_view() -> void:
	var focus := _focused_grid()
	_proj.isometric = not _proj.isometric
	_focus(focus, false)
	_reproject()


func _change_speed(step: int, wrap := false) -> void:
	_speed_index = posmod(_speed_index + step, SPEEDS.size()) if wrap else clampi(_speed_index + step, 0, SPEEDS.size() - 1)
	_update_speed_button()


func _update_speed_button() -> void:
	_buttons["speed"].text = "Speed %s" % SPEED_NAMES[_speed_index]


## The world-space rectangle currently on screen, for culling.
func _view_rect() -> Rect2:
	var size := get_viewport_rect().size / _camera.zoom
	return Rect2(_camera.position - size * 0.5, size).grow(120.0)


# --- Engine calls, AI turns and event playback ---

func _run(events: Array) -> void:
	busy = true
	_reach = {}
	_move_tiles = {}
	_overlay_layer.queue_redraw()
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
	if _turn_started and battle.winner == -1 and _is_human_turn():
		_save()
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
			if u.vehicle:
				_effects.append({"kind": "explosion", "at": _display_pos[u.id], "radius": 1.2, "age": 0.0, "life": 1.4})
				_float(_display_pos[u.id], "KNOCKED OUT", Color("ff3b3b"))
				_log_line("[color=#ff6b6b]%s is knocked out![/color]" % u.name)
			else:
				_float(_display_pos[u.id], "KILLED", Color("ff3b3b"))
				_log_line("[color=#ff6b6b]%s (%s) was killed.[/color]" % [u.name, u.role])
			await _wait(0.6)
		"suppression":
			var u := battle.get_unit(e["unit"])
			_display_suppression[u.id] = e["value"]
			var was_pinned: bool = e["previous"] >= Unit.PINNED_AT
			var was_suppressed: bool = e["previous"] >= Unit.SUPPRESSED_AT
			if e["state"] == "pinned" and not was_pinned:
				_float(_display_pos[u.id], "PINNED DOWN", Color("ff5544"))
				_log_line("%s is pinned down." % u.name)
				await _wait(0.3)
			elif e["state"] == "suppressed" and not was_suppressed:
				_float(_display_pos[u.id], "Suppressed", Color("ffa040"))
				await _wait(0.2)
		"explosion":
			_effects.append({"kind": "explosion", "at": _center(e["center"]), "radius": e["radius"] + 0.5, "age": 0.0, "life": 1.4})
			_log_line("Explosion: %d pieces of cover destroyed." % e["destroyed"])
			await _wait(0.6)
		"smoke":
			_effects.append({"kind": "puff_burst", "at": _center(e["center"]), "age": 0.0, "life": 0.8})
			_log_line("%s lays smoke." % battle.get_unit(e["unit"]).name)
			await _wait(0.4)
		"smoke_clear":
			_log_line("[color=#999]The smoke clears.[/color]")
		"mortar_fire":
			await _play_mortar_fire(e)
		"strike":
			var center := _center(e["center"])
			_effects.append({"kind": "incoming", "at": center, "age": 0.0, "life": 0.35})
			if _view_team() == -1 or _viewer_sees(e["center"]) or controllers[battle.current_team] == null:
				_focus(center)
			await _wait(0.35)
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
		"objective":
			var objective: Dictionary = battle.objectives[e["index"]]
			var owner: int = e["owner"]
			_float(objective["center"], "%s take the %s" % [Battle.TEAM_NAMES[owner], objective["name"]], TEAM_COLORS[owner])
			_log_line("[color=%s]%s take the %s.[/color]" % [TEAM_COLORS[owner].to_html(false), Battle.TEAM_NAMES[owner], objective["name"]])
			await _wait(0.3)
		"score":
			var points: Array = e["points"]
			_log_line("Score after the round: Allies %d, Germany %d." % [points[0], points[1]])
		"reinforcements":
			var team: int = e["team"]
			for id: int in e["units"]:
				_add_display_state(battle.get_unit(id))
			_log_line("[color=%s]%s reinforcements arrive.[/color]" % [TEAM_COLORS[team].to_html(false), Battle.TEAM_NAMES[team]])
			if _view_team() == -1 or _view_team() == team:
				_show_banner("%s reinforcements!" % Battle.TEAM_NAMES[team], TEAM_COLORS[team])
		"turn":
			var team: int = e["team"]
			var who := "%s%s" % [Battle.TEAM_NAMES[team], " (AI)" if controllers[team] != null else ""]
			_log_line("[b][color=%s]Round %d: %s[/color][/b]" % [TEAM_COLORS[team].to_html(false), e["round"], who])
			_turn_started = true
			if controllers[0] == null and controllers[1] == null:
				_show_overlay("handover", "%s's turn\n\nClick or press any key" % Battle.TEAM_NAMES[team], TEAM_COLORS[team])
			else:
				_show_banner("Turn: %s" % who, TEAM_COLORS[team])
		"game_over":
			var winner: int = e["winner"]
			var how := "by holding the objectives" if e.get("reason") == "points" else "by wiping out the enemy"
			if winner == Battle.DRAW:
				_log_line("[b]The battle ends in a draw.[/b]")
				_show_overlay("game_over", "A draw: %d to %d\n\nClick or press any key to continue" % battle.victory_points, NEUTRAL_COLOR)
			else:
				_log_line("[b]%s win %s![/b]" % [Battle.TEAM_NAMES[winner], how])
				_show_overlay("game_over", "%s win %s!\n%d to %d\n\nClick or press any key to continue" % [Battle.TEAM_NAMES[winner], how, battle.victory_points[0], battle.victory_points[1]], TEAM_COLORS[winner])


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
	var bursts := 3 if shooter.weapon.kind in ["mg", "smg"] else 1
	for i in bursts:
		_effects.append({"kind": "muzzle", "at": from, "age": 0.0, "life": 0.1})
		_effects.append({"kind": "tracer", "from": from, "to": to + Vector2(randf_range(-4, 4), randf_range(-4, 4)) * i, "age": 0.0, "life": 0.25})
		await _wait(0.07)
	await _wait(0.05)
	_effects.append({"kind": "sparks" if hit else "puff", "at": to, "age": 0.0, "life": 0.4})
	await _wait(0.15)
	var label: String = SHOT_LABELS[e["result"]]
	_float(_display_pos[target.id], "%s (%d%%)" % [label, e["chance"]], Color.WHITE if e["result"] != "crit" else Color("ffb84d"))
	var armour := " on its %s armour" % e["armor"] if e.has("armor") else ""
	_log_line("%s%s shoots at %s: %s (%d%%)%s" % ["Overwatch: " if e["reaction"] else "", shooter.name, target.name, label, e["chance"], armour])
	await _wait(0.25)


func _play_mortar_fire(e: Dictionary) -> void:
	var u := battle.get_unit(e["unit"])
	var target := _center(e["target"])
	_facing[u.id] = (target - _display_pos[u.id]).normalized()
	_revealed[u.id] = true
	_effects.append({"kind": "muzzle", "at": _proj.project(_display_pos[u.id], 0.9), "age": 0.0, "life": 0.15})
	_effects.append({"kind": "shell", "from": _display_pos[u.id], "to": target, "age": 0.0, "life": 0.8})
	var round_name := "high explosive" if e["kind"] == "he" else "smoke"
	_log_line("%s fires a %s round. It lands at the start of their next turn." % [u.name, round_name])
	await _wait(0.8)


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
	_floaters.append({"text": text, "at": at, "color": color, "age": 0.0, "life": 1.3})


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
		if _reach[p]["cost"] <= selected.current_mobility() + 0.001:
			_move_tiles[p] = true
	_target_odds.clear()
	if can_act and mode == Mode.SHOOT:
		for e in battle.visible_enemies(selected):
			_target_odds[e.id] = battle.shot_odds(selected, e)["hit"]
	_flankers = _compute_flankers()
	_update_panel()
	_update_target_info()
	_mark_chunks_dirty(false)
	_update_prop_darkness()
	_overlay_layer.queue_redraw()


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
	_turn_label.text = "Round %d/%d: %s%s" % [battle.round_number, battle.max_rounds, Battle.TEAM_NAMES[team], " (AI)" if controllers[team] != null else ""]
	_turn_label.add_theme_color_override("font_color", TEAM_COLORS[team])
	var holders := PackedStringArray()
	for objective in battle.objectives:
		var owner: int = objective["owner"]
		var color: Color = TEAM_COLORS[owner] if owner != -1 else NEUTRAL_COLOR
		holders.append("[color=%s]%s[/color]" % [color.to_html(false), objective["name"]])
	_score_label.text = "[color=%s]Allies %d[/color]  vs  [color=%s]Germany %d[/color]   (%d to win)\n%s" % [
		TEAM_COLORS[0].to_html(false), battle.victory_points[0], TEAM_COLORS[1].to_html(false), battle.victory_points[1],
		battle.vp_to_win, "   ".join(holders)]
	if not _is_human_turn():
		_unit_info.text = "[i]%s are taking their turn...[/i]" % Battle.TEAM_NAMES[team]
	elif selected != null:
		_unit_info.text = _describe_unit(selected)
	else:
		_unit_info.text = "No soldier selected.\nClick one of your soldiers."
	var s := selected if _is_human_turn() else null
	var visible := {
		"grenade": s != null and s.grenades > 0, "smoke": s != null and s.smoke_grenades > 0,
		"set_up": s != null and s.weapon.needs_setup, "rally": s != null and s.role == "Officer",
		"medkit": s != null and s.medkits > 0, "mortar": s != null and s.role == "Mortar",
	}
	for action: String in visible:
		_buttons[action].visible = visible[action]
	_buttons["shoot"].disabled = s == null or battle.can_fire(s) != ""
	_buttons["overwatch"].disabled = s == null or battle.can_overwatch(s) != ""
	_buttons["hunker"].disabled = s == null or battle.can_hunker(s) != ""
	_buttons["reload"].disabled = s == null or battle.can_reload(s) != ""
	_buttons["set_up"].disabled = s == null or battle.can_set_up(s) != ""
	_buttons["rally"].disabled = s == null or battle.can_rally(s) != ""
	for action in ["grenade", "smoke", "medkit", "mortar"]:
		_buttons[action].disabled = s == null or battle.can_act(s) != ""
	if s != null and s.role == "Mortar":
		_buttons["mortar"].disabled = s.actions < Unit.ACTIONS_PER_TURN
		_buttons["mortar"].text = "0 Mortar: %s" % ("smoke" if mode == Mode.MORTAR and _mortar_kind == "smoke" else "HE")
	_buttons["next"].disabled = s == null or _next_ready_unit(s) == null
	_buttons["end"].disabled = battle.winner != -1 or not _is_human_turn()


func _describe_unit(u: Unit) -> String:
	var lines := PackedStringArray()
	lines.append("[b][color=%s]%s[/color][/b]  %s, %s" % [TEAM_COLORS[u.team].to_html(false), u.name, u.role, u.weapon.name])
	lines.append("HP %d/%d   Aim %d   Move %.0f%s   Ammo %d/%d" % [u.hp, u.max_hp, u.aim, u.current_mobility(),
			"" if u.current_mobility() == u.mobility else " (of %.0f)" % u.mobility, u.ammo, u.weapon.clip_size])
	var kit := PackedStringArray()
	for item: Array in [[u.grenades, "grenades"], [u.smoke_grenades, "smoke"], [u.medkits, "medkits"], [u.mortar_rounds, "HE rounds"], [u.mortar_smoke, "smoke rounds"]]:
		if item[0] > 0:
			kit.append("%d %s" % [item[0], item[1]])
	if not kit.is_empty():
		lines.append(", ".join(kit))
	var status := PackedStringArray(["Actions %d/%d" % [u.actions, Unit.ACTIONS_PER_TURN]])
	if u.is_pinned():
		status.append("[color=#ff5544]Pinned (%d)[/color]" % u.suppression)
	elif u.suppression > 0:
		status.append("[color=#ffa040]Suppression %d[/color]" % u.suppression)
	if u.is_wounded():
		status.append("[color=#ff8080]Wounded (%d turns)[/color]" % u.wounded_turns)
	if u.deployed:
		status.append("[color=#ffd34d]MG set up[/color]")
	if u.overwatch:
		status.append("[color=#ffd34d]Overwatch[/color]")
	if u.hunkered:
		status.append("[color=#8fd3ff]Hunkered[/color]")
	lines.append("   ".join(status))
	match mode:
		Mode.SHOOT:
			lines.append("[color=#ff9b8a]Shooting: click a target. Right click cancels.[/color]")
		Mode.GRENADE:
			lines.append("[color=#ffb84d]Grenade: click a tile in range. Right click cancels.[/color]")
		Mode.SMOKE:
			lines.append("[color=#c8d0d8]Smoke: click a tile in range. Right click cancels.[/color]")
		Mode.MORTAR:
			lines.append("[color=#ffb84d]Mortar (%s): click a spotted tile. Press 0 to switch rounds.[/color]" % ("smoke" if _mortar_kind == "smoke" else "high explosive"))
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
				text = "[b]Frag grenade[/b]  range %d, radius %.1f\n%d-%d damage, ignores cover, destroys it.\nHits friends too." % [
					CombatRules.GRENADE_RANGE, CombatRules.GRENADE_RADIUS, CombatRules.GRENADE_DAMAGE_MIN, CombatRules.GRENADE_DAMAGE_MAX]
				text += _error_line(battle.can_throw_grenade(selected, hover))
			Mode.SMOKE:
				text = "[b]Smoke grenade[/b]  range %d, radius %.1f\nBlocks line of sight for two rounds. Takes one action." % [CombatRules.SMOKE_RANGE, CombatRules.SMOKE_RADIUS]
				text += _error_line(battle.can_throw_smoke(selected, hover))
			Mode.MORTAR:
				text = "[b]Mortar, %s[/b]  range %d-%d\nLands at the start of your next turn, up to %.1f tiles off target.\nNeeds a soldier who can see the target." % [
					"smoke" if _mortar_kind == "smoke" else "high explosive", CombatRules.MORTAR_MIN_RANGE, CombatRules.MORTAR_MAX_RANGE,
					Battle.mortar_scatter(selected.pos, hover)]
				text += _error_line(battle.can_fire_mortar(selected, hover, _mortar_kind))
	if text == "" and map.in_bounds(hover):
		text = _describe_tile(hover)
	_target_info.text = text


func _error_line(err: String) -> String:
	return "" if err == "" else "\n[color=#ff6b6b]%s[/color]" % err


func _describe_odds(shooter: Unit, target: Unit) -> String:
	var odds := battle.shot_odds(shooter, target)
	var lines := PackedStringArray()
	lines.append("[b]Target: %s[/b] (%s)  HP %d/%d" % [target.name, target.role, target.hp, target.max_hp])
	lines.append("[color=#8fff9b]Hit %d%%[/color]   Graze %d%%   Crit %d%%   Suppression +%d" % [odds["hit"], odds["graze"], odds["crit"], shooter.weapon.suppression])
	for m: Array in odds["modifiers"]:
		lines.append("    %s  %+d" % [m[0], m[1]])
	if target.vehicle:
		if not shooter.weapon.anti_tank:
			lines.append("[color=#ff6b6b]Small arms can't hurt a tank[/color]")
		else:
			var side := CombatRules.armor_side(target, shooter.pos)
			lines.append("[color=#ffb84d]Hitting its %s armour: -%d damage[/color]" % [side, CombatRules.VEHICLE_ARMOR[side]])
	elif odds["flanked"]:
		lines.append("[color=#ffb84d]No cover from this angle: +%d crit[/color]" % CombatRules.FLANK_CRIT_BONUS)
	if shooter.weapon.blast_radius > 0.0:
		lines.append("High explosive: blasts cover and anyone next to the target")
	if target.overwatch:
		lines.append("[color=#ffd34d]On overwatch[/color]")
	return "\n".join(lines)


func _describe_tile(p: Vector2i) -> String:
	var map := battle.map
	var lines := PackedStringArray()
	var object := map.get_object(p)
	if object != Cover.NONE:
		lines.append("[b]%s[/b]  (%s cover, blocks movement%s)" % [map.get_object_kind(p).capitalize(), "full" if object == Cover.FULL else "half", ", blocks sight" if object == Cover.FULL else ""])
	else:
		lines.append("[b]%s[/b]  move cost %s" % [TacticalMap.TERRAIN_NAMES[map.get_terrain(p)], str(TacticalMap.TERRAIN_COST[map.get_terrain(p)])])
		var covers := PackedStringArray()
		for i in 4:
			var d: Vector2i = TacticalMap.DIRS4[i]
			var c := map.cover_toward(p, d)
			if c != Cover.NONE:
				covers.append("%s %s" % [["N", "E", "S", "W"][i], Cover.NAMES[c].to_lower()])
		lines.append("Cover: " + (", ".join(covers) if not covers.is_empty() else "none"))
	if map.has_smoke(p):
		lines.append("[color=#c8d0d8]Smoke: blocks sight[/color]")
	for objective in battle.objectives:
		if (Vector2(p) + Vector2(0.5, 0.5)).distance_to(objective["center"]) <= objective["radius"]:
			lines.append("Objective: %s" % objective["name"])
	if _reach.has(p) and selected != null:
		var cost: float = _reach[p]["cost"]
		lines.append("Path cost %.1f: %s" % [cost, "dash, uses both actions" if not _move_tiles.has(p) else "one action"])
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
	style.bg_color = Color(0.11, 0.11, 0.1)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	_title_label = Label.new()
	_title_label.text = GameSession.battle_title
	_title_label.add_theme_font_size_override("font_size", 13)
	_title_label.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_title_label)
	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 20)
	box.add_child(_turn_label)
	_score_label = _rich_label(40)
	box.add_child(_score_label)
	box.add_child(HSeparator.new())
	_unit_info = _rich_label(90)
	box.add_child(_unit_info)

	var actions := HFlowContainer.new()
	box.add_child(actions)
	for spec: Array in ACTION_BUTTONS:
		_add_button(actions, spec[0], spec[1])

	box.add_child(HSeparator.new())
	_target_info = _rich_label(130)
	box.add_child(_target_info)
	box.add_child(HSeparator.new())
	_log = _rich_label(0)
	_log.fit_content = false
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_log)

	var view_row := HFlowContainer.new()
	box.add_child(view_row)
	_add_button(view_row, "rotate_left", "Q Rotate")
	_add_button(view_row, "rotate_right", "E Rotate")
	_add_button(view_row, "toggle_view", "V Iso / top")
	_add_button(view_row, "speed", "Speed 1x")
	_add_button(view_row, "quit", "Save & quit")
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
	_overlay.color = Color(0.06, 0.06, 0.05, 0.97)
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


# --- Scene layers ---

func _layer(z: int, painter: Callable) -> Node2D:
	var layer: Node2D = DrawLayer.new()
	layer.z_as_relative = false
	layer.z_index = z
	layer.painter = painter
	add_child(layer)
	return layer


## z_index that sorts something at grid point g by depth among props and soldiers.
func _depth_z(g: Vector2, bias := 0.0) -> int:
	return clampi(1 + int((_proj.depth(g) + bias) * DEPTH_Z), 1, TOP_Z - 10)


## After a rotation or view toggle: everything must be re-recorded and re-sorted.
func _reproject() -> void:
	_mark_chunks_dirty(true)
	for node in _prop_nodes:
		node.z_index = _depth_z(node.get_meta("center"))
		node.queue_redraw()
	for p: Vector2i in _smoke_nodes:
		_smoke_nodes[p].z_index = _depth_z(_center(p), 0.3)
	_overlay_layer.queue_redraw()


func _mark_chunks_dirty(terrain: bool) -> void:
	for chunk: Vector2i in _chunks:
		_dirty_fog[chunk] = true
		if terrain:
			_dirty_terrain[chunk] = true


## Repaints dirty chunks that are on screen, a few terrain chunks per frame. Off-screen ones wait.
func _repaint_dirty_chunks() -> void:
	var view := _view_rect()
	var budget := CHUNK_BUDGET
	for chunk: Vector2i in _dirty_terrain.keys():
		if budget > 0 and _chunk_rect(chunk).intersects(view):
			_chunks[chunk][0].queue_redraw()
			_chunks[chunk][1].queue_redraw()
			_dirty_terrain.erase(chunk)
			budget -= 1
	for chunk: Vector2i in _dirty_fog.keys():
		if _chunk_rect(chunk).intersects(view):
			_chunks[chunk][2].queue_redraw()
			_dirty_fog.erase(chunk)


func _chunk_rect(chunk: Vector2i) -> Rect2:
	var origin := Vector2(chunk * CHUNK)
	var rect := Rect2(_proj.project(origin), Vector2.ZERO)
	for corner in [Vector2(CHUNK, 0), Vector2(0, CHUNK), Vector2(CHUNK, CHUNK)]:
		rect = rect.expand(_proj.project(origin + corner))
	return rect.grow(80.0)


func _chunk_tiles(chunk: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for y in range(chunk.y * CHUNK, mini((chunk.y + 1) * CHUNK, battle.map.height)):
		for x in range(chunk.x * CHUNK, mini((chunk.x + 1) * CHUNK, battle.map.width)):
			tiles.append(Vector2i(x, y))
	return tiles


func _paint_ground_chunk(c: CanvasItem, chunk: Vector2i) -> void:
	for p in _chunk_tiles(chunk):
		TerrainPainter.draw_tile(c, _proj, battle.map, p)
		c.draw_polyline(_tile_outline(p), Color(0, 0, 0, 0.08), 1.0)


## Shadows sit on their own layer so they can fall across chunk borders onto ground drawn later.
func _paint_shadow_chunk(c: CanvasItem, chunk: Vector2i) -> void:
	var map := battle.map
	for p in _chunk_tiles(chunk):
		if map.get_object(p) != Cover.NONE:
			TerrainPainter.draw_object_shadow(c, _proj, map, p)
	for key: Vector3i in map.get_edges():
		if Vector2i(key.x, key.y) / CHUNK == chunk:
			TerrainPainter.draw_edge_shadow(c, _proj, map, key)


func _paint_fog_chunk(c: CanvasItem, chunk: Vector2i) -> void:
	for p in _chunk_tiles(chunk):
		if not _visible_tiles.has(p):
			c.draw_colored_polygon(TerrainPainter.tile_poly(_proj, p), Color(0.03, 0.03, 0.05, 0.5))


## One canvas item per object and wall, recorded once. Rebuilt when the map layout changes.
func _rebuild_props() -> void:
	for node in _prop_nodes:
		node.queue_free()
	_prop_nodes.clear()
	_props_by_tile.clear()
	_faded.clear()
	var map := battle.map
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if map.get_object(p) != Cover.NONE:
				var tiles: Array[Vector2i] = [p]
				_add_prop(_paint_object.bind(p), _center(p), tiles)
	for key: Vector3i in map.get_edges():
		var pair := TacticalMap.edge_tiles(key)
		_add_prop(_paint_edge.bind(key), (_center(pair[0]) + _center(pair[1])) * 0.5, pair)
	_update_prop_darkness()


func _add_prop(painter: Callable, center: Vector2, tiles: Array[Vector2i]) -> void:
	var node := _layer(_depth_z(center), painter)
	node.set_meta("center", center)
	node.set_meta("tiles", tiles)
	node.set_meta("dark", false)
	_prop_nodes.append(node)
	for t in tiles:
		if not _props_by_tile.has(t):
			_props_by_tile[t] = []
		_props_by_tile[t].append(node)


func _paint_object(c: CanvasItem, p: Vector2i) -> void:
	TerrainPainter.draw_object(c, _proj, battle.map, p, 1.0, false)


func _paint_edge(c: CanvasItem, key: Vector3i) -> void:
	TerrainPainter.draw_edge(c, _proj, battle.map, key, 1.0, false)


## Props out of sight are darkened, like the fog under them.
func _update_prop_darkness() -> void:
	for node in _prop_nodes:
		var dark := true
		for t: Vector2i in node.get_meta("tiles"):
			if _visible_tiles.has(t):
				dark = false
		if dark != node.get_meta("dark"):
			node.set_meta("dark", dark)
			_apply_prop_modulate(node)


## Props standing in front of a soldier or the cursor turn see-through. Only nearby props are checked.
func _update_prop_fading() -> void:
	var wanted := {}
	if _proj.isometric:
		var focus: Array[Vector2] = []
		if battle.map.in_bounds(hover) and _is_human_turn():
			focus.append(_center(hover))
		for u in battle.alive_units():
			if _display_pos.has(u.id) and _is_drawn(u):
				focus.append(_display_pos[u.id])
		for f in focus:
			var tile := Vector2i(f.floor())
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					for node: Node2D in _props_by_tile.get(tile + Vector2i(dx, dy), []):
						if not wanted.has(node) and _occludes(node.get_meta("center"), f):
							wanted[node] = true
	var changed := []
	for node: Node2D in _faded:
		if not wanted.has(node):
			changed.append(node)
	for node: Node2D in wanted:
		if not _faded.has(node):
			changed.append(node)
	_faded = wanted
	for node: Node2D in changed:
		if is_instance_valid(node):
			_apply_prop_modulate(node)


func _apply_prop_modulate(node: Node2D) -> void:
	var shade := 0.55 if node.get_meta("dark") else 1.0
	node.modulate = Color(shade, shade, shade, 0.3 if _faded.has(node) else 1.0)


## Whether a tall thing at grid point g stands in front of focus point f, hiding it.
func _occludes(g: Vector2, f: Vector2) -> bool:
	var r := _proj.rotate_grid(g)
	var rf := _proj.rotate_grid(f)
	return r.x + r.y > rf.x + rf.y + 0.1 and r.x > rf.x - 0.7 and r.y > rf.y - 0.7 and r.distance_to(rf) < 2.6


func _sync_smoke() -> void:
	var smoke := battle.map.get_smoke()
	for p: Vector2i in _smoke_nodes.keys():
		if not smoke.has(p):
			_smoke_nodes[p].queue_free()
			_smoke_nodes.erase(p)
	for p: Vector2i in smoke:
		if not _smoke_nodes.has(p):
			_smoke_nodes[p] = _layer(_depth_z(_center(p), 0.3), _paint_smoke.bind(p))


func _paint_smoke(c: CanvasItem, p: Vector2i) -> void:
	TerrainPainter.draw_smoke(c, _proj, p, _time)


func _update_units() -> void:
	for u in battle.units:
		if not _unit_nodes.has(u.id):
			continue
		var node: Node2D = _unit_nodes[u.id]
		node.visible = _is_drawn(u)
		if node.visible:
			node.z_index = _depth_z(_display_pos[u.id], 0.05)
			node.queue_redraw()


func _is_drawn(u: Unit) -> bool:
	if not _display_pos.has(u.id):
		return false
	if _display_hp[u.id] <= 0:
		return true
	if _revealed.has(u.id):
		return true
	if _move_visibility.has(u.id):
		return _move_visibility[u.id]
	return _view_team() == -1 or u.team == _view_team() or _seen_units.has(u.id)


# --- Drawing ---

func _draw() -> void:
	_draw_markers()
	_draw_effects()


func _paint_ground_overlays(c: CanvasItem) -> void:
	for objective in battle.objectives:
		var owner: int = objective["owner"]
		var color: Color = TEAM_COLORS[owner] if owner != -1 else NEUTRAL_COLOR
		c.draw_polyline(TerrainPainter.ground_circle(_proj, objective["center"], objective["radius"]), Color(color, 0.7), 2.5)
	for strike in battle.strikes:
		var he: bool = strike["kind"] == "he"
		var color := Color(1, 0.3, 0.2, 0.8) if he else Color(0.8, 0.85, 0.9, 0.8)
		var center := _center(strike["target"])
		var radius := (CombatRules.MORTAR_RADIUS if he else CombatRules.SMOKE_RADIUS) + float(strike["scatter"])
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		c.draw_colored_polygon(TerrainPainter.ground_circle(_proj, center, radius, false), Color(color, 0.08 + 0.08 * pulse))
		c.draw_polyline(TerrainPainter.ground_circle(_proj, center, radius), color, 2.0)
	if busy or selected == null or not _is_human_turn():
		return
	if mode == Mode.MOVE and not _reach.is_empty():
		for p: Vector2i in _reach:
			if p != selected.pos:
				c.draw_colored_polygon(TerrainPainter.tile_poly(_proj, p), (MOVE_COLOR if _move_tiles.has(p) else DASH_COLOR) * Color(1, 1, 1, 0.1))
		_draw_region_border(c, _reach, DASH_COLOR)
		_draw_region_border(c, _move_tiles, MOVE_COLOR)
	if mode == Mode.MORTAR:
		var at := _center(selected.pos)
		c.draw_polyline(TerrainPainter.ground_circle(_proj, at, CombatRules.MORTAR_MIN_RANGE), Color(1, 0.4, 0.3, 0.5), 1.5)
		c.draw_polyline(TerrainPainter.ground_circle(_proj, at, CombatRules.MORTAR_MAX_RANGE), Color(1, 0.7, 0.3, 0.5), 1.5)
	if not battle.map.in_bounds(hover):
		return
	c.draw_polyline(_tile_outline(hover), Color(1, 1, 1, 0.8), 2.0)
	match mode:
		Mode.MOVE:
			if _reach.has(hover) and hover != selected.pos:
				var color := MOVE_COLOR if _move_tiles.has(hover) else DASH_COLOR
				var points := PackedVector2Array([_proj.project(_center(selected.pos))])
				for p in Pathfinder.path_to(_reach, hover):
					points.append(_proj.project(_center(p)))
				c.draw_polyline(points, color, 3.0)
				c.draw_polyline(TerrainPainter.ground_circle(_proj, _center(hover), 0.3), color, 2.5)
		Mode.GRENADE, Mode.SMOKE:
			var grenade := mode == Mode.GRENADE
			var throw_range := CombatRules.GRENADE_RANGE if grenade else CombatRules.SMOKE_RANGE
			var radius := CombatRules.GRENADE_RADIUS if grenade else CombatRules.SMOKE_RADIUS
			var color := Color(1, 0.55, 0.1, 0.4) if grenade else Color(0.8, 0.85, 0.9, 0.35)
			c.draw_polyline(TerrainPainter.ground_circle(_proj, _center(selected.pos), throw_range), Color(color, 0.6), 1.5)
			var ok := battle.can_throw_grenade(selected, hover) == "" if grenade else battle.can_throw_smoke(selected, hover) == ""
			if ok:
				for p in battle.map.tiles_in_radius(hover, radius):
					c.draw_colored_polygon(TerrainPainter.tile_poly(_proj, p), color)
		Mode.MORTAR:
			if battle.can_fire_mortar(selected, hover, _mortar_kind) == "":
				var he := _mortar_kind == "he"
				var radius := (CombatRules.MORTAR_RADIUS if he else CombatRules.SMOKE_RADIUS) + Battle.mortar_scatter(selected.pos, hover)
				var color := Color(1, 0.45, 0.15, 0.3) if he else Color(0.8, 0.85, 0.9, 0.3)
				c.draw_colored_polygon(TerrainPainter.ground_circle(_proj, _center(hover), radius, false), color)
				c.draw_polyline(TerrainPainter.ground_circle(_proj, _center(hover), radius), Color(color, 0.9), 2.0)
		Mode.MEDKIT:
			for u in battle.alive_units(selected.team):
				if battle.can_use_medkit(selected, u) == "":
					c.draw_polyline(TerrainPainter.ground_circle(_proj, _display_pos[u.id], 0.45), Color("6bff8a"), 2.5)


## Outlines the boundary of a set of tiles, like XCOM's move range border.
func _draw_region_border(c: CanvasItem, tiles: Dictionary, color: Color) -> void:
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for p: Vector2i in tiles:
		for i in 4:
			if not tiles.has(p + TacticalMap.DIRS4[i]):
				var a: Vector2 = Vector2(p) + corners[i]
				var b: Vector2 = Vector2(p) + corners[(i + 1) % 4]
				c.draw_line(_proj.project(a), _proj.project(b), color, 2.5)


func _pose(u: Unit) -> Dictionary:
	var death := 0.0
	if _display_hp[u.id] <= 0:
		death = clampf((_time - _died_at.get(u.id, -10.0)) / 0.45, 0.0, 1.0)
	var alive := death == 0.0
	return {
		"facing": _facing[u.id],
		"walk": 1.0 if _walking.has(u.id) else 0.0,
		"phase": _time * 14.0 + u.id,
		"crouch": u.hunkered and alive,
		"pinned": _display_suppression[u.id] >= Unit.PINNED_AT and alive,
		"deployed": u.deployed and alive,
		"wounded": u.is_wounded() and alive,
		"death": death,
		"flash": clampf(1.0 - (_time - _hit_at.get(u.id, -10.0)) / 0.3, 0.0, 1.0),
		"breath": _time * 2.2 + u.id * 1.7,
		"time": _time,
	}


func _paint_unit(c: CanvasItem, u: Unit) -> void:
	var g: Vector2 = _display_pos[u.id]
	var pose := _pose(u)
	if u.vehicle:
		c.draw_colored_polygon(TerrainPainter.ground_circle(_proj, g + TerrainPainter.LIGHT * 0.3, 0.55, false), Color(0, 0, 0, 0.3))
		if u == selected:
			c.draw_polyline(TerrainPainter.ground_circle(_proj, g, 0.65), Color.WHITE, 2.5)
		if mode == Mode.SHOOT and _target_odds.has(u.id):
			c.draw_polyline(TerrainPainter.ground_circle(_proj, g, 0.68), Color("ff4040"), 2.5)
		VehiclePainter.draw(c, _proj, g, u, pose)
		return
	if pose["death"] > 0.0:
		var facing: Vector2 = pose["facing"]
		c.draw_colored_polygon(TerrainPainter.ground_circle(_proj, g - facing * 0.3, 0.05 + 0.25 * pose["death"], false), Color(0.33, 0.03, 0.03, 0.7))
	else:
		c.draw_colored_polygon(TerrainPainter.ground_circle(_proj, g + TerrainPainter.LIGHT * 0.25, 0.26, false), Color(0, 0, 0, 0.3))
		if u == selected:
			c.draw_polyline(TerrainPainter.ground_circle(_proj, g, 0.42), Color.WHITE, 2.5)
		if mode == Mode.SHOOT and _target_odds.has(u.id):
			var hovered := battle.map.in_bounds(hover) and battle.unit_at(hover) == u
			c.draw_polyline(TerrainPainter.ground_circle(_proj, g, 0.45), Color("ff4040") if hovered else Color("ff8080"), 3.0 if hovered else 1.5)
	SoldierPainter.draw(c, _proj, g, u, pose)


## Flags, unit tags, HP and suppression bars, drawn above everything so walls never hide them.
func _draw_markers() -> void:
	for objective in battle.objectives:
		var owner: int = objective["owner"]
		var color: Color = TEAM_COLORS[owner] if owner != -1 else NEUTRAL_COLOR
		var base := _proj.project(objective["center"])
		var top := _proj.project(objective["center"], 2.2)
		draw_line(base, top, Color("3a3226"), 3.0)
		var wave := sin(_time * 3.0) * 2.0
		draw_colored_polygon(PackedVector2Array([top, top + Vector2(22, 3 + wave), top + Vector2(22, 15 + wave), top + Vector2(0, 14)]), color)
		draw_string_outline(_font, top + Vector2(-60, -8), objective["name"], HORIZONTAL_ALIGNMENT_CENTER, 120, 13, 4, Color(0, 0, 0, 0.8))
		draw_string(_font, top + Vector2(-60, -8), objective["name"], HORIZONTAL_ALIGNMENT_CENTER, 120, 13, color)
	for strike in battle.strikes:
		var at := _proj.project(_center(strike["target"]), 0.4)
		var label := "INCOMING" if strike["kind"] == "he" else "SMOKE ROUND"
		draw_string_outline(_font, at + Vector2(-60, 0), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, 4, Color(0, 0, 0, 0.8))
		draw_string(_font, at + Vector2(-60, 0), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color("ff6a50") if strike["kind"] == "he" else Color("d8dee4"))

	var view := _view_rect()
	for u in battle.units:
		if not _display_pos.has(u.id) or _display_hp[u.id] <= 0 or not _is_drawn(u):
			continue
		var top := _proj.project(_display_pos[u.id], 1.1 if u.vehicle else 1.15) + Vector2(0, -14)
		if not view.has_point(top):
			continue
		draw_rect(Rect2(top + Vector2(-14, -1), Vector2(28, 9)), Color(0, 0, 0, 0.65))
		if u.max_hp > 10:
			draw_rect(Rect2(top + Vector2(-13, 0), Vector2(26, 3)), Color("3a3a3a"))
			draw_rect(Rect2(top + Vector2(-13, 0), Vector2(26.0 * _display_hp[u.id] / u.max_hp, 3)), Color("6bff8a"))
		else:
			var pip_w := 26.0 / u.max_hp
			for i in u.max_hp:
				draw_rect(Rect2(top + Vector2(-13 + i * pip_w, 0), Vector2(pip_w - 1, 3)), Color("6bff8a") if i < _display_hp[u.id] else Color("3a3a3a"))
		var suppression: int = _display_suppression[u.id]
		if suppression > 0:
			var bar_color := Color("ff5544") if suppression >= Unit.PINNED_AT else (Color("ffa040") if suppression >= Unit.SUPPRESSED_AT else Color("c8b060"))
			draw_rect(Rect2(top + Vector2(-13, 4), Vector2(26.0 * suppression / 100.0, 2)), bar_color)
		draw_rect(Rect2(top + Vector2(-14, 8), Vector2(28, 2)), TEAM_COLORS[u.team])
		draw_string(_font, top + Vector2(-44, 7), ROLE_TAGS.get(u.role, ""), HORIZONTAL_ALIGNMENT_RIGHT, 28, 10, Color(TEAM_COLORS[u.team], 0.9))
		if u.team == battle.current_team and _is_human_turn():
			for i in u.actions:
				draw_circle(top + Vector2(19 + i * 6, 3), 2.5, Color("f5c542"))
		var tags := PackedStringArray()
		if suppression >= Unit.PINNED_AT:
			tags.append("PINNED")
		elif suppression >= Unit.SUPPRESSED_AT:
			tags.append("SUPPRESSED")
		if u.is_wounded():
			tags.append("DAMAGED" if u.vehicle else "WOUNDED")
		if u.overwatch:
			tags.append("OVERWATCH")
		elif u.deployed:
			tags.append("MG READY")
		if u.hunkered:
			tags.append("HUNKERED")
		if not tags.is_empty():
			var tag_color := Color("ff7060") if suppression >= Unit.SUPPRESSED_AT or u.is_wounded() else Color("ffd34d")
			draw_string_outline(_font, top + Vector2(-60, -5), " ".join(tags), HORIZONTAL_ALIGNMENT_CENTER, 120, 10, 3, Color(0, 0, 0, 0.7))
			draw_string(_font, top + Vector2(-60, -5), " ".join(tags), HORIZONTAL_ALIGNMENT_CENTER, 120, 10, tag_color)
		if mode == Mode.SHOOT and _target_odds.has(u.id):
			draw_string_outline(_font, top + Vector2(-30, -18), "%d%%" % _target_odds[u.id], HORIZONTAL_ALIGNMENT_CENTER, 60, 15, 4, Color(0, 0, 0, 0.8))
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
			"puff_burst":
				for i in 6:
					var at := _proj.project(fx["at"] + Vector2.from_angle(i * TAU / 6) * 1.2 * t, 0.3 + t * 0.4)
					draw_circle(at, 8.0 + 14.0 * t, Color(0.85, 0.85, 0.83, 0.6 * (1.0 - t)))
			"shell":
				var from: Vector2 = fx["from"]
				var to: Vector2 = fx["to"]
				var at := _proj.project(from.lerp(to, t), 4.0 * t * (1.0 - t) * 6.0)
				draw_circle(at, 3.5, Color("1d1d1b"))
				draw_circle(at + Vector2(0, 3), 4.0 * (1.0 - t), Color(0.8, 0.8, 0.8, 0.3))
			"incoming":
				var at := _proj.project(fx["at"], 6.0 * (1.0 - t))
				draw_line(at, at + Vector2(0, -26), Color(1, 1, 0.9, 0.5), 2.0)
				draw_circle(at, 3.0, Color("1d1d1b"))
			"explosion":
				_draw_explosion(fx["at"], fx["radius"], t)
	for f in _floaters:
		var t: float = f["age"] / f["life"]
		var color: Color = f["color"]
		color.a = 1.0 - t * t
		var at: Vector2 = _proj.project(f["at"], 1.5) + Vector2(-110, -22 - 24 * t)
		draw_string_outline(_font, at, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 220, 14, 4, Color(0, 0, 0, color.a))
		draw_string(_font, at, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 220, 14, color)


## Flash, fireball, then rising smoke and flying debris.
func _draw_explosion(center: Vector2, radius: float, t: float) -> void:
	if t < 0.35:
		var k := t / 0.35
		draw_colored_polygon(TerrainPainter.ground_circle(_proj, center, radius * (0.5 + 0.5 * k), false), Color(1, 0.5, 0.1, 0.55 * (1.0 - k)))
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
