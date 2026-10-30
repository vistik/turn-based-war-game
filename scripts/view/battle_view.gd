extends Node2D
## Top-down view of a Battle: draws the grid, takes hotseat input and plays back engine events.
## Placeholder art only: everything is drawn with primitives in _draw().

const TILE := 28
const ORIGIN := Vector2(16, 24)
const PANEL_X := 704.0
const TEAM_COLORS := [Color("4aa3ff"), Color("ff6150")]
const TEAM_NAMES := ["Blue", "Red"]
const TERRAIN_COLORS := [Color("3a4237"), Color("4a4a30"), Color("4b3f37")]
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
const SHOT_LABELS := {"miss": "MISS", "graze": "GRAZE", "hit": "HIT", "crit": "CRITICAL"}

enum Mode { MOVE, SHOOT, GRENADE, MEDKIT }

var battle: Battle
var selected: Unit
var mode := Mode.MOVE
var hover := Vector2i(-1, -1)
var busy := false

var _reach := {}
var _visible_tiles := {}
var _seen_units := {}
var _target_odds := {}
var _flankers: Array[Unit] = []
## Presentation state that trails the engine while events play back.
var _display_pos := {}
var _display_hp := {}
var _revealed := {}
var _floaters := []
var _effects := []
var _overlay_state := ""

var _font: Font
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
	for u in battle.units:
		_display_pos[u.id] = _center(u.pos)
		_display_hp[u.id] = u.hp
	_build_ui()
	_run(battle.start())


func _process(delta: float) -> void:
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
	if busy:
		return
	if event is InputEventMouseMotion:
		_set_hover(_tile_at(get_local_mouse_position()))
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_click(_tile_at(get_local_mouse_position()))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_set_mode(Mode.MOVE)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_set_mode(Mode.MOVE)
		elif KEY_ACTIONS.has(event.keycode):
			_on_action(KEY_ACTIONS[event.keycode])
	else:
		return
	get_viewport().set_input_as_handled()


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
	if busy or _overlay_state != "" or battle.winner != -1:
		return
	if action == "end":
		_run(battle.end_turn())
		return
	if action == "next":
		_select(_next_ready_unit(selected))
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
	_select(_next_ready_unit(null))


func _select(u: Unit) -> void:
	selected = u
	mode = Mode.MOVE
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


func _next_ready_unit(after: Unit) -> Unit:
	var ready := battle.alive_units(battle.current_team).filter(func(u: Unit) -> bool: return u.actions > 0)
	if ready.is_empty():
		return null
	return ready[(ready.find(after) + 1) % ready.size()]


# --- Engine calls and event playback ---

func _run(events: Array) -> void:
	busy = true
	_reach = {}
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
			_effects.append({"kind": "explosion", "at": _center(e["center"]), "radius": e["radius"] * TILE + TILE * 0.5, "age": 0.0, "life": 0.5})
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
		to += Vector2.from_angle(randf() * TAU) * TILE * 0.8
	_effects.append({"kind": "tracer", "from": from, "to": to, "age": 0.0, "life": 0.35})
	await _wait(0.3)
	var label: String = SHOT_LABELS[e["result"]]
	_float(_display_pos[target.id] + Vector2(0, -12), "%s (%d%%)" % [label, e["chance"]], Color.WHITE if e["result"] != "crit" else Color("ffb84d"))
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


func _float(at: Vector2, text: String, color: Color) -> void:
	_floaters.append({"text": text, "at": at + Vector2(0, -16), "color": color, "age": 0.0, "life": 1.2})


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
	var panel := PanelContainer.new()
	panel.position = Vector2(PANEL_X, ORIGIN.y)
	panel.size = Vector2(1280 - PANEL_X - 16, TILE * battle.map.height)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
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
		var button := Button.new()
		button.text = spec[1]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_action.bind(spec[0]))
		actions.add_child(button)
		_buttons[spec[0]] = button

	box.add_child(HSeparator.new())
	_target_info = _rich_label(150)
	box.add_child(_target_info)
	box.add_child(HSeparator.new())
	_log = _rich_label(0)
	_log.fit_content = false
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_log)
	var help := Label.new()
	help.text = "LMB select / move / target    RMB or Esc cancel"
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


func _rich_label(min_height: float) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.focus_mode = Control.FOCUS_NONE
	label.custom_minimum_size = Vector2(0, min_height)
	return label


# --- Drawing ---

func _draw() -> void:
	_draw_tiles()
	_draw_edges()
	_draw_fog()
	_draw_mode_overlay()
	_draw_units()
	_draw_effects()


func _draw_tiles() -> void:
	var map := battle.map
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var rect := _rect(p)
			var terrain := map.get_terrain(p)
			draw_rect(rect, TERRAIN_COLORS[terrain])
			draw_rect(rect, Color(0, 0, 0, 0.25), false, 1.0)
			var c := rect.get_center()
			if terrain == TacticalMap.Terrain.ROUGH:
				for o: Vector2 in [Vector2(-6, -5), Vector2(5, -2), Vector2(-2, 6)]:
					draw_line(c + o, c + o + Vector2(2, -4), Color("6b6a40"), 1.5)
			elif terrain == TacticalMap.Terrain.RUBBLE:
				for o: Vector2 in [Vector2(-6, -4), Vector2(4, 3), Vector2(-3, 7), Vector2(6, -6)]:
					draw_rect(Rect2(c + o, Vector2(3, 3)), Color("736255"))
			match map.get_object(p):
				Cover.HALF:
					draw_rect(rect.grow(-5), Color("8a6d3b"))
					draw_rect(rect.grow(-5), Color("5c4524"), false, 2.0)
				Cover.FULL:
					draw_rect(rect.grow(-1), Color("6e737a"))
					draw_rect(rect.grow(-4), Color("878c93"), false, 2.0)
			if _reach.has(p) and p != selected.pos:
				var dash: bool = _reach[p]["cost"] > selected.mobility + 0.001
				draw_rect(rect, (DASH_COLOR if dash else MOVE_COLOR) * Color(1, 1, 1, 0.18))


func _draw_edges() -> void:
	var edges := battle.map.get_edges()
	for key: Vector3i in edges:
		var a := ORIGIN + Vector2(key.x + 1, key.y) * TILE if key.z == 0 else ORIGIN + Vector2(key.x, key.y + 1) * TILE
		var b := a + (Vector2(0, TILE) if key.z == 0 else Vector2(TILE, 0))
		if edges[key] == Cover.FULL:
			draw_line(a, b, Color("c9ccd1"), 4.0)
		else:
			draw_dashed_line(a, b, Color("c9a86b"), 3.0, 5.0)


func _draw_fog() -> void:
	for y in battle.map.height:
		for x in battle.map.width:
			if not _visible_tiles.has(Vector2i(x, y)):
				draw_rect(_rect(Vector2i(x, y)), Color(0, 0, 0, 0.5))


func _draw_mode_overlay() -> void:
	if busy or selected == null or not battle.map.in_bounds(hover):
		return
	match mode:
		Mode.MOVE:
			if _reach.has(hover) and hover != selected.pos:
				_draw_path_preview()
		Mode.GRENADE:
			var center := _center(selected.pos)
			draw_arc(center, CombatRules.GRENADE_RANGE * TILE, 0, TAU, 96, Color(1, 0.7, 0.3, 0.35), 1.5)
			if battle.can_throw_grenade(selected, hover) == "":
				for p in battle.map.tiles_in_radius(hover, CombatRules.GRENADE_RADIUS):
					draw_rect(_rect(p), Color(1, 0.55, 0.1, 0.35))
				draw_line(center, _center(hover), Color(1, 0.7, 0.3, 0.6), 1.5)
			else:
				var c := _center(hover)
				draw_line(c - Vector2(6, 6), c + Vector2(6, 6), Color.RED, 2.0)
				draw_line(c - Vector2(-6, 6), c + Vector2(-6, 6), Color.RED, 2.0)
		Mode.MEDKIT:
			for u in battle.alive_units(selected.team):
				if battle.can_use_medkit(selected, u) == "":
					draw_arc(_display_pos[u.id], 14, 0, TAU, 32, Color("6bff8a"), 2.0)


func _draw_path_preview() -> void:
	var cost: float = _reach[hover]["cost"]
	var color := DASH_COLOR if cost > selected.mobility + 0.001 else MOVE_COLOR
	var points := PackedVector2Array([_center(selected.pos)])
	for p in Pathfinder.path_to(_reach, hover):
		points.append(_center(p))
	draw_polyline(points, color, 2.5)
	var end := _center(hover)
	draw_arc(end, 8, 0, TAU, 24, color, 2.0)
	# Cover shields on each side of the destination, like XCOM.
	for d: Vector2i in TacticalMap.DIRS4:
		var c := battle.map.cover_toward(hover, d)
		if c == Cover.NONE:
			continue
		var at := end + Vector2(d) * TILE * 0.36 - Vector2(4, 4)
		draw_rect(Rect2(at, Vector2(8, 8)), Color("8fd3ff"), c == Cover.FULL)
		if c == Cover.HALF:
			draw_rect(Rect2(at + Vector2(0, 4), Vector2(8, 4)), Color("8fd3ff"))
	for e in _flankers:
		draw_dashed_line(end, _display_pos[e.id], Color(1, 0.3, 0.3, 0.7), 1.5, 6.0)
	if color == DASH_COLOR:
		draw_string(_font, end + Vector2(-14, -12), "DASH", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DASH_COLOR)


func _draw_units() -> void:
	for u in battle.units:
		var at: Vector2 = _display_pos[u.id]
		var color: Color = TEAM_COLORS[u.team]
		if _display_hp[u.id] <= 0:
			draw_line(at - Vector2(6, 6), at + Vector2(6, 6), color.darkened(0.4), 3.0)
			draw_line(at - Vector2(-6, 6), at + Vector2(-6, 6), color.darkened(0.4), 3.0)
			continue
		if u.team != battle.current_team and not _seen_units.has(u.id) and not _revealed.has(u.id):
			continue
		if u == selected:
			draw_arc(at, 14, 0, TAU, 32, Color.WHITE, 2.0)
		if mode == Mode.SHOOT and _target_odds.has(u.id):
			var hovered := battle.map.in_bounds(hover) and battle.unit_at(hover) == u
			draw_arc(at, 14, 0, TAU, 32, Color("ff4040") if hovered else Color("ff8080"), 3.0 if hovered else 1.5)
			draw_string(_font, at + Vector2(-16, -16), "%d%%" % _target_odds[u.id], HORIZONTAL_ALIGNMENT_CENTER, 32, 12, Color.WHITE)
		draw_circle(at, 10, color)
		draw_arc(at, 10, 0, TAU, 24, color.darkened(0.5), 1.5)
		draw_string(_font, at + Vector2(-8, 5), u.role[0], HORIZONTAL_ALIGNMENT_CENTER, 16, 13, Color.BLACK)
		# HP pips under the unit.
		var pip_w := 22.0 / u.max_hp
		for i in u.max_hp:
			var pip := Rect2(at + Vector2(-11 + i * pip_w, 11), Vector2(pip_w - 1, 3))
			draw_rect(pip, Color("6bff8a") if i < _display_hp[u.id] else Color(0, 0, 0, 0.6))
		if u.team == battle.current_team:
			for i in u.actions:
				draw_circle(at + Vector2(12, -10 + i * 6), 2.0, Color("f5c542"))
		if u.overwatch:
			draw_string(_font, at + Vector2(-13, -12), "OW", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("ffd34d"))
		if u.hunkered:
			draw_string(_font, at + Vector2(-13, -12), "HUNK", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("8fd3ff"))


func _draw_effects() -> void:
	for fx in _effects:
		var t: float = fx["age"] / fx["life"]
		match fx["kind"]:
			"tracer":
				draw_line(fx["from"], fx["to"], Color(1, 0.9, 0.5, 1.0 - t), 2.0)
			"explosion":
				draw_circle(fx["at"], fx["radius"] * (0.4 + 0.6 * t), Color(1, 0.55, 0.15, 0.6 * (1.0 - t)))
	for f in _floaters:
		var t: float = f["age"] / f["life"]
		var color: Color = f["color"]
		color.a = 1.0 - t * t
		var at: Vector2 = f["at"] + Vector2(-80, -24 * t)
		draw_string(_font, at + Vector2(1, 1), f["text"], HORIZONTAL_ALIGNMENT_CENTER, 160, 13, Color(0, 0, 0, color.a))
		draw_string(_font, at, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 160, 13, color)


func _center(p: Vector2i) -> Vector2:
	return ORIGIN + (Vector2(p) + Vector2(0.5, 0.5)) * TILE


func _rect(p: Vector2i) -> Rect2:
	return Rect2(ORIGIN + Vector2(p) * TILE, Vector2(TILE, TILE))


func _tile_at(pixel: Vector2) -> Vector2i:
	var local := (pixel - ORIGIN) / TILE
	return Vector2i(floori(local.x), floori(local.y))
