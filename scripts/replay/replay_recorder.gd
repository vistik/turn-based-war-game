class_name ReplayRecorder
extends Node
## Records the battle being played for its replay. A child of the battle view (never while watching a replay):
## carries on GameSession.recording if it belongs to this battle (a continued save), else starts a new one,
## records every command the battle executes, saves the replay when the battle ends, and offers to watch it
## on the game-over screen.

## The battle view (scripts/view/battle_view.gd).
var view: Node2D
var replay: Replay
var _saved := false
var _watch_button: Button


func _init(p_view: Node2D) -> void:
	view = p_view
	name = "ReplayRecorder"
	var battle: Battle = view.battle
	replay = GameSession.recording
	if replay == null or replay.head != battle.checksum():
		replay = Replay.begin(battle, GameSession.battle_title, _mode(), [_side(0), _side(1)])
		GameSession.recording = replay
	replay.attach(battle)


func _exit_tree() -> void:
	replay.detach()


func _process(_delta: float) -> void:
	if not _saved and view.battle.winner != -1:
		_saved = true
		replay.finish(view.battle)
		if GameSession.recording == replay:
			GameSession.recording = null
		replay.save_file()
	if _saved and replay.path != "" and view._overlay_state == "game_over" and _watch_button == null:
		_watch_button = Button.new()
		_watch_button.text = "Watch replay"
		_watch_button.theme_type_variation = "PrimaryButton"
		_watch_button.focus_mode = Control.FOCUS_NONE
		_watch_button.custom_minimum_size = Vector2(220, 44)
		_watch_button.pressed.connect(_watch)
		view._overlay.add_child(_watch_button)
		_watch_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 80)


## Leaves the battle as usual (campaign results, saves) and watches its replay instead of the menu.
func _watch() -> void:
	ReplayControls.return_to_campaign = GameSession.campaign != null or GameSession.war != null
	GameSession.watching = replay
	view._dismiss_overlay()


static func _mode() -> String:
	if not GameSession.online.is_empty():
		return "online"
	if GameSession.war != null:
		return "war"
	return "campaign" if GameSession.campaign != null else "skirmish"


func _side(team: int) -> String:
	var controller: Variant = view.controllers[team]
	if controller is RemotePlayer:
		return "Opponent online"
	if controller != null:
		return "AI"
	return "You" if view.controllers[1 - team] != null else "Player %d" % (team + 1)
