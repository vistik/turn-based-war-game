class_name ReplayControls
extends Node
## Watching a replay on the battle screen. A child of the battle view and the controller of both sides: the view
## asks it for the next events like it asks an online opponent (next_events()), and it executes the recorded
## commands one by one, pausing, stepping or skipping to the next turn as asked. The fog of war shown can be
## switched at any time between the Allies' view, Germany's view and the whole map. Nobody can give orders,
## nothing is saved and the advisor and agent link stay off. Restarting rebuilds the battle from the snapshot
## by reloading the scene.

signal _advance

## [label, view team, key, tooltip]
const VIEWS := [
	["Allies' view", 0, KEY_1, "Only what the Allies saw (1)"],
	["Germany's view", 1, KEY_2, "Only what Germany saw (2)"],
	["Whole map", -1, KEY_3, "No fog of war: both sides (3)"],
]
const BAD := Color("ff7a6a")

## Kept across restarts.
static var _last_view := -1
## Where leaving the replay goes: the campaign screen (watched from a campaign battle) or the main menu.
static var return_to_campaign := false

## The battle view (scripts/view/battle_view.gd).
var view: Node2D
var replay: Replay
## Whose fog of war is shown: 0, 1, or -1 for everything. The view's _view_team() returns it.
var view_team := -1
var paused := false
## Index of the next command to execute.
var index := 0
## Commands still to execute while paused (Next action).
var _steps := 0
## While skipping to the next turn: the turn index to leave, else -1.
var _until_turn := -1
var _play_button: Button
var _view_buttons: Array[Button] = []
var _status: Label


func _init(p_view: Node2D, p_replay: Replay) -> void:
	view = p_view
	replay = p_replay
	name = "ReplayControls"
	view_team = _last_view
	view.controllers = [self, self]


func _ready() -> void:
	view._buttons["quit"].text = "Leave replay"
	view._buttons["quit"].tooltip_text = "Back to the menu"
	_build_ui()
	_update_ui()


## The view's controller call: waits while paused, then executes the next recorded command and returns its
## events. Returns null at the end of the recording, or if the battle no longer plays out as recorded.
func next_events() -> Variant:
	while paused and _steps == 0:
		await _advance
	if _steps > 0:
		_steps -= 1
	if index >= replay.commands.size():
		paused = true
		_update_ui()
		if view.battle.winner == -1:
			view._show_banner("End of the recording", view.NEUTRAL_COLOR)
		return null
	var command: Dictionary = replay.commands[index]
	var turn: int = view.battle.turn_index
	var events: Array = view.battle.execute(command)
	if events.is_empty() or (replay.checkpoints.has(index) and view.battle.checksum() != replay.checkpoints[index]):
		paused = true
		_update_ui()
		view._show_overlay("replay_error", "This replay doesn't play out as recorded\nfrom order %d on (%s).\n\nThe game's rules have probably changed since.\n\nClick or press any key" % [index + 1, command.get("cmd", "?")], BAD)
		return null
	index += 1
	if _until_turn != -1 and view.battle.turn_index != turn:
		_until_turn = -1
		paused = true
		view._apply_turn_speed(view.battle.current_team)
	_update_ui()
	return events


func to_dict() -> Dictionary:
	return {}


func toggle_pause() -> void:
	paused = not paused
	_until_turn = -1
	_update_ui()
	_advance.emit()


## Plays one more command, then pauses.
func step() -> void:
	paused = true
	_steps += 1
	_update_ui()
	_advance.emit()


## Skips at instant speed to the start of the next turn, then pauses.
func next_turn() -> void:
	if index >= replay.commands.size():
		return
	_until_turn = view.battle.turn_index
	paused = false
	view._speed_index = view.SPEEDS.size() - 1
	view._update_speed_button()
	_update_ui()
	_advance.emit()


## Starts over: the scene is rebuilt from the snapshot (GameSession.watching is kept).
func restart() -> void:
	get_tree().reload_current_scene()


func set_view(team: int) -> void:
	view_team = team
	_last_view = team
	view._refresh()
	_update_ui()


func quit() -> void:
	GameSession.watching = null
	GameSession.battle = null
	GameSession.show_campaign = return_to_campaign
	return_to_campaign = false
	get_tree().change_scene_to_file(GameSession.MENU_SCENE)


## "AI", "You", ...: who played the side, for the turn banner.
func side_name(team: int) -> String:
	return replay.sides[team] if team < replay.sides.size() else ""


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			toggle_pause()
		KEY_N:
			step()
		KEY_ENTER, KEY_KP_ENTER:
			next_turn()
		KEY_R:
			restart()
		_:
			for spec: Array in VIEWS:
				if event.keycode == spec[2]:
					set_view(spec[1])
					get_viewport().set_input_as_handled()
			return
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_status.text = "Order %d of %d   Round %d" % [index, replay.commands.size(), view.battle.round_number]


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -view.PANEL_WIDTH * 0.5
	panel.offset_right = -view.PANEL_WIDTH * 0.5
	panel.offset_top = -10
	panel.offset_bottom = -10
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Above the game-over overlay, so the replay can be restarted from there.
	view._overlay.get_parent().add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	box.add_child(heading)
	var title := Label.new()
	title.text = "Replay"
	title.theme_type_variation = "HeaderSmall"
	heading.add_child(title)
	_status = Label.new()
	_status.theme_type_variation = "HelpLabel"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	_button(row, "Restart", "Start again from the beginning (R)", restart)
	_play_button = _button(row, "Pause", "Play or pause (Space)", toggle_pause)
	_play_button.custom_minimum_size = Vector2(70, 0)
	_button(row, "Next action", "Play the next order and pause (N)", step)
	_button(row, "Next turn", "Skip to the start of the next turn (Enter)", next_turn)
	row.add_child(VSeparator.new())
	var group := ButtonGroup.new()
	for spec: Array in VIEWS:
		var button := _button(row, spec[0], spec[3], set_view.bind(spec[1]))
		button.toggle_mode = true
		button.button_group = group
		_view_buttons.append(button)


func _button(parent: Control, text: String, tip: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = "SmallButton"
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _update_ui() -> void:
	if _play_button == null:
		return
	_play_button.text = "Play" if paused or index >= replay.commands.size() else "Pause"
	for i in VIEWS.size():
		_view_buttons[i].set_pressed_no_signal(VIEWS[i][1] == view_team)
