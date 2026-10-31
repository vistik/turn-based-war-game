class_name AdvisorView
extends Node2D
## Move suggestions on the battle screen, and the agent link (MCP server) while a battle is open.
## A child of the battle view: it reads the view's state and selects units through it, but only the player
## gives orders. H asks the game's AI for the best move (Shift+H: for the selected soldier); the suggestion is
## highlighted on the map with a short reason, and the player clicks the destination or target (or Accept)
## to carry it out. An agent connected through the link can show its own proposals the same way.

const SUGGEST_KEY := KEY_H
const ADVICE_COLOR := Color("7ee0ff")
const AGENT_COLOR := Color("d9a6ff")
## Card sits in the bottom left of the map area.
const CARD_WIDTH := 430.0

## The battle view (scripts/view/battle_view.gd).
var view: Node2D
var tools: McpGameTools
var server: McpServer

## The suggestion on screen: AdvisorAI.suggest() output plus "source" ("AI" or "Agent"), or {}.
var _suggestion := {}
## Team, round and actions left when the suggestion was made; any change clears it.
var _shown_at := ""
var _suggest_button: Button
var _link_button: Button
var _card: PanelContainer
var _card_title: Label
var _card_text: RichTextLabel
var _accept_button: Button
var _link_panel: PanelContainer
var _link_text: RichTextLabel
var _act_toggle: CheckBox
var _last_request := ""
var _last_request_at := -1.0
var _time := 0.0


func _init(p_view: Node2D) -> void:
	view = p_view
	name = "Advisor"


func _ready() -> void:
	AdvisorSettings.load_settings()
	z_as_relative = false
	z_index = view.TOP_Z + 1
	tools = McpGameTools.new(view.battle, self)
	_build_ui()
	if AdvisorSettings.mcp_enabled:
		_start_link()
	_update_ui()


func _exit_tree() -> void:
	if server != null:
		server.stop()


func _process(delta: float) -> void:
	_time += delta
	if server != null:
		server.poll()
	if not _suggestion.is_empty() and (_state_key() != _shown_at or view.busy or not _human_turn()):
		_clear()
	_update_ui()
	if not _suggestion.is_empty():
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or view._overlay_state != "":
		return
	if event.keycode == SUGGEST_KEY:
		_on_suggest(event.shift_pressed)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and not _suggestion.is_empty():
		# The view also uses Escape (cancel targeting); let it through.
		_clear()


# --- Host interface for McpGameTools ---

## The side the player plays: the only human, the human whose turn it is in hotseat, -1 if AI vs AI.
func player_team() -> int:
	return view._view_team()


func is_online() -> bool:
	return view._online


func is_busy() -> bool:
	return view.busy or view._overlay_state != "" or not _human_turn()


func show_proposal(suggestion: Dictionary) -> void:
	_suggestion = suggestion
	_shown_at = _state_key()
	var u: Unit = view.battle.get_unit(suggestion.get("unit", -1))
	if u != null:
		view._select(u, true)
		match suggestion["kind"]:
			"shoot", "aimed_shot", "suppress":
				view._shot_cmd = suggestion["kind"]
				view._set_mode(view.Mode.SHOOT)
			"grenade":
				view._set_mode(view.Mode.GRENADE)
			"smoke":
				view._set_mode(view.Mode.SMOKE)
			"medkit":
				view._set_mode(view.Mode.MEDKIT)
			"mortar":
				view._mortar_kind = suggestion["command"].get("kind", "he")
				view._set_mode(view.Mode.MORTAR)
	var source: String = suggestion.get("source", "AI")
	view._log_line("[color=#%s]%s suggests: %s[/color]" % [(AGENT_COLOR if source == "Agent" else ADVICE_COLOR).to_html(false), source, suggestion["text"]])
	_update_ui()
	queue_redraw()


## Carries out an agent's command (only when the player allowed it). Returns "" or why it didn't.
func apply_command(command: Dictionary) -> String:
	if is_online() or not AdvisorSettings.agent_may_act:
		return "Not allowed"
	if is_busy():
		return "Wait: the last move is still playing out"
	view._log_line("[color=#%s]Agent orders: %s[/color]" % [AGENT_COLOR.to_html(false), tools.describe(command)])
	_clear()
	view._command(command)
	return ""


# --- Suggestions ---

func _available() -> String:
	if is_online() and not AdvisorSettings.help_online:
		return "Suggestions are off in online games"
	if view.battle.winner != -1 or not _human_turn():
		return "Not your turn"
	if view.busy or view._overlay_state != "":
		return "Wait for the move to finish"
	return ""


func _on_suggest(for_selected: bool) -> void:
	var err := _available()
	if err != "":
		view._flash(err)
		return
	var only: Unit = view.selected if for_selected else null
	var suggestion := tools.advisor_for(view.battle.current_team).suggest(only)
	if suggestion.has("error"):
		view._flash(suggestion["error"])
		return
	suggestion["source"] = "AI"
	show_proposal(suggestion)


func _accept() -> void:
	if _suggestion.is_empty() or _available() != "":
		return
	var command: Dictionary = _suggestion["command"]
	var err := tools.validate(command)
	_clear()
	if err != "":
		view._flash(err)
		return
	view._command(command)


func _clear() -> void:
	if _suggestion.is_empty():
		return
	_suggestion = {}
	queue_redraw()
	_update_ui()


func _human_turn() -> bool:
	return view.battle.winner == -1 and view._is_human_turn()


func _state_key() -> String:
	var actions := 0
	for u in view.battle.alive_units(view.battle.current_team):
		actions += u.actions
	return "%d/%d/%d" % [view.battle.round_number, view.battle.current_team, actions]


# --- Agent link ---

func _start_link() -> void:
	if server == null:
		server = McpServer.new(tools, AdvisorSettings.token())
		server.on_request = _on_request
	var err := server.start(AdvisorSettings.mcp_port)
	if err != OK:
		view._log_line("[color=#ff6b6b]Agent link: can't listen on port %d (%s)[/color]" % [AdvisorSettings.mcp_port, error_string(err)])
		server = null
		return
	view._log_line("[color=#%s]Agent link on: %s[/color]" % [AGENT_COLOR.to_html(false), server.url()])


func _stop_link() -> void:
	if server != null:
		server.stop()
		server = null
		view._log_line("Agent link off.")


func _toggle_link() -> void:
	AdvisorSettings.mcp_enabled = server == null
	AdvisorSettings.save_settings()
	if AdvisorSettings.mcp_enabled:
		_start_link()
	else:
		_stop_link()
	_update_ui()


func _on_request(method: String) -> void:
	_last_request = method
	_last_request_at = _time


## The command to give Claude Code for this run of the game.
func setup_command() -> String:
	return "claude mcp add --transport http normandy %s --header \"Authorization: Bearer %s\"" % [server.url() if server != null else "http://127.0.0.1:%d/mcp" % AdvisorSettings.mcp_port, AdvisorSettings.token()]


func _copy_setup() -> void:
	DisplayServer.clipboard_set(setup_command())
	view._flash("Copied the Claude Code setup command")


func _on_act_toggled(on: bool) -> void:
	AdvisorSettings.agent_may_act = on
	AdvisorSettings.save_settings()


# --- UI ---

func _build_ui() -> void:
	# A button among the battle panel's actions, and the link switch beside Save & quit.
	var actions: Control = view._buttons["next"].get_parent()
	_suggest_button = _button(actions, "H Suggest", _on_suggest.bind(false))
	_suggest_button.tooltip_text = "The AI's best move for your side (Shift+H: for the selected soldier). You still make the move."
	var view_row: Control = view._buttons["quit"].get_parent()
	_link_button = _button(view_row, "Agent link", _toggle_link)
	_link_button.tooltip_text = "Let an AI agent (Claude Code, Claude Desktop...) see your side of the battle and suggest moves, over MCP on this computer only."
	view_row.move_child(_link_button, view._buttons["quit"].get_index())

	var layer := CanvasLayer.new()
	add_child(layer)
	_card = _panel(layer, ADVICE_COLOR)
	_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.offset_left = 12
	_card.offset_top = -12
	_card.offset_bottom = -12
	_card.offset_right = 12 + CARD_WIDTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_card.get_child(0).add_child(box)
	_card_title = Label.new()
	_card_title.add_theme_font_size_override("font_size", 13)
	box.add_child(_card_title)
	_card_text = RichTextLabel.new()
	_card_text.bbcode_enabled = true
	_card_text.fit_content = true
	_card_text.custom_minimum_size = Vector2(CARD_WIDTH - 24, 0)
	_card_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_card_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_accept_button = _button(row, "Accept", _accept)
	_button(row, "Dismiss (Esc)", _clear)
	var hint := Label.new()
	hint.text = "or click the highlighted tile or target"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.55)
	row.add_child(hint)
	_card.hide()

	_link_panel = _panel(layer, AGENT_COLOR)
	_link_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_link_panel.offset_left = 12
	_link_panel.offset_top = 12
	_link_panel.offset_right = 12 + CARD_WIDTH
	var link_box := VBoxContainer.new()
	link_box.add_theme_constant_override("separation", 4)
	_link_panel.get_child(0).add_child(link_box)
	_link_text = RichTextLabel.new()
	_link_text.bbcode_enabled = true
	_link_text.fit_content = true
	_link_text.custom_minimum_size = Vector2(CARD_WIDTH - 24, 0)
	_link_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	link_box.add_child(_link_text)
	var link_row := HBoxContainer.new()
	link_row.add_theme_constant_override("separation", 8)
	link_box.add_child(link_row)
	_button(link_row, "Copy Claude Code command", _copy_setup)
	_act_toggle = CheckBox.new()
	_act_toggle.text = "Agent may play my moves"
	_act_toggle.focus_mode = Control.FOCUS_NONE
	_act_toggle.button_pressed = AdvisorSettings.agent_may_act
	_act_toggle.toggled.connect(_on_act_toggled)
	link_row.add_child(_act_toggle)
	_link_panel.hide()


func _update_ui() -> void:
	if _suggest_button == null:
		return
	_suggest_button.disabled = _available() != ""
	_link_button.text = "Agent link: %s" % ("on" if server != null else "off")
	_link_panel.visible = server != null
	if server != null:
		var lines := PackedStringArray()
		lines.append("[b][color=#%s]Agent link on[/color][/b]  %s" % [AGENT_COLOR.to_html(false), server.url()])
		lines.append("Token: [code]%s[/code]" % AdvisorSettings.token())
		if is_online():
			lines.append("Online game: %s; the agent can never move for you here." % ("read-only help allowed" if AdvisorSettings.help_online else "help is off"))
		if _last_request_at >= 0.0:
			lines.append("[color=#aaa]Last request: %s, %ds ago[/color]" % [_last_request, int(_time - _last_request_at)])
		var text := "\n".join(lines)
		if _link_text.text != text:
			_link_text.text = text
		_act_toggle.disabled = is_online()
	_card.visible = not _suggestion.is_empty()
	if _card.visible:
		var agent: bool = _suggestion.get("source") == "Agent"
		_card_title.text = "AGENT SUGGESTS" if agent else "SUGGESTED MOVE"
		_card_title.add_theme_color_override("font_color", AGENT_COLOR if agent else ADVICE_COLOR)
		_card_text.text = _suggestion["text"]
		_accept_button.disabled = _available() != ""


func _panel(parent: Node, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.11, 0.94)
	style.border_color = Color(accent, 0.8)
	style.border_width_left = 3
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	return panel


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button


# --- Map highlight ---

func _draw() -> void:
	if _suggestion.is_empty() or view.busy:
		return
	var battle: Battle = view.battle
	var proj: ViewProjection = view._proj
	var u := battle.get_unit(_suggestion.get("unit", -1))
	if u == null:
		return
	var color := AGENT_COLOR if _suggestion.get("source") == "Agent" else ADVICE_COLOR
	var pulse := 0.6 + 0.4 * sin(_time * 5.0)
	var from: Vector2 = view._display_pos[u.id]
	draw_polyline(TerrainPainter.ground_circle(proj, from, 0.5), Color(color, pulse), 2.5)
	var command: Dictionary = _suggestion["command"]
	var target := battle.get_unit(command.get("target", -1))
	var label := ""
	var label_at := from
	match command["cmd"]:
		"move":
			var tile: Vector2i = command["tile"]
			var reach := battle.reachable(u)
			var points := PackedVector2Array([proj.project(from)])
			for p in Pathfinder.path_to(reach, tile):
				points.append(proj.project(view._center(p)))
			if points.size() > 1:
				draw_polyline(points, Color(color, 0.9), 4.0)
			var at: Vector2 = view._center(tile)
			draw_colored_polygon(TerrainPainter.tile_poly(proj, tile), Color(color, 0.25 * pulse))
			draw_polyline(TerrainPainter.ground_circle(proj, at, 0.42), color, 3.0)
			for d: Vector2i in TacticalMap.DIRS4:
				var c := battle.map.cover_toward(tile, d)
				if c != Cover.NONE:
					_draw_shield(proj.project(at + Vector2(d) * 0.36, 0.5), c == Cover.FULL)
			if reach.has(tile) and battle.actions_for_cost(u, reach[tile]["cost"]) > 1:
				label = "DASH HERE"
			else:
				label = "MOVE HERE"
			label_at = at
		"shoot", "aimed_shot", "suppress", "medkit":
			if target != null:
				var at: Vector2 = view._display_pos[target.id]
				draw_line(proj.project(from, 0.6), proj.project(at, 0.6), Color(color, 0.8), 2.5)
				draw_polyline(TerrainPainter.ground_circle(proj, at, 0.55), color, 3.0)
				match command["cmd"]:
					"medkit":
						label = "TREAT"
					"suppress":
						label = "SUPPRESS"
					_:
						label = "%d%%" % battle.shot_odds(u, target, false, command["cmd"] == "aimed_shot")["hit"]
				label_at = at
		"stance":
			label = ["STAND UP", "CROUCH", "GO PRONE"][command.get("stance", 0)]
		"grenade", "smoke", "mortar":
			var tile: Vector2i = command["tile"]
			var radius := CombatRules.GRENADE_RADIUS if command["cmd"] == "grenade" else (CombatRules.SMOKE_RADIUS if command["cmd"] == "smoke" else CombatRules.MORTAR_RADIUS)
			var at: Vector2 = view._center(tile)
			draw_line(proj.project(from, 0.6), proj.project(at), Color(color, 0.8), 2.0)
			draw_polyline(TerrainPainter.ground_circle(proj, at, radius), color, 3.0)
			label = command["cmd"].to_upper()
			label_at = at
		"pivot":
			view._draw_heading(self, u.pos, command["tile"], color)
			label = "TURN"
		_:
			label = command["cmd"].replace("_", " ").to_upper()
	var top := proj.project(label_at, 1.2) + Vector2(0, -14)
	draw_string_outline(view._font, top + Vector2(-70, 0), label, HORIZONTAL_ALIGNMENT_CENTER, 140, 16, 5, Color(0, 0, 0, 0.85))
	draw_string(view._font, top + Vector2(-70, 0), label, HORIZONTAL_ALIGNMENT_CENTER, 140, 16, color)


## A cover shield like the battle view's, half filled for half cover.
func _draw_shield(at: Vector2, full: bool) -> void:
	var shape := PackedVector2Array([at + Vector2(-6, -7), at + Vector2(6, -7), at + Vector2(6, 1), at + Vector2(0, 7), at + Vector2(-6, 1)])
	draw_colored_polygon(shape, Color("8fd3ff") if full else Color(0.1, 0.15, 0.2, 0.8))
	if not full:
		draw_colored_polygon(PackedVector2Array([at + Vector2(-6, 0), at + Vector2(6, 0), at + Vector2(6, 1), at + Vector2(0, 7), at + Vector2(-6, 1)]), Color("8fd3ff"))
	shape.append(shape[0])
	draw_polyline(shape, Color("0d2030"), 1.5)
