class_name GameSettings
extends RefCounted
## Player preferences, saved to user://settings.cfg. Static, like GameSession, so every scene (and the
## headless tests) can read them without an autoload. Presentation only: nothing here touches the engine,
## so battles play out the same whatever is set.

const PATH := "user://settings.cfg"
## Playback speeds by index, matching SPEEDS in battle_view.gd (0.0 = instant).
const SPEED_NAMES := ["1x", "2x", "4x", "Instant"]
## Camera pan speed multipliers for the keyboard.
const PAN_SPEEDS := [0.5, 1.0, 1.5, 2.0]
const PAN_SPEED_NAMES := ["Slow", "Normal", "Fast", "Very fast"]

## Soldiers and tanks jump straight to their destination instead of walking there.
static var instant_movement := false
## The camera pans to the opponent's (AI or online) units when they move or call in a strike.
static var follow_opponent := true
## Playback speed index for your own turns, and for the AI's or online opponent's turns.
static var own_speed := 0
static var opponent_speed := 0
## Index into PAN_SPEEDS.
static var pan_speed := 1
## Hit, graze and crit chances on hovered targets and over targets while aiming.
static var show_hit_chance := true
## Ask before ending the turn while some units can still act.
static var confirm_end_turn := false
static var fullscreen := false

static var _loaded := false


## Loads the settings once and applies the window mode. Safe to call from every scene's _ready.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	load_settings()
	apply_window()


## Every setting with its default, keyed by name. The names double as the ConfigFile keys.
static func defaults() -> Dictionary:
	return {
		"instant_movement": false, "follow_opponent": true, "own_speed": 0, "opponent_speed": 0,
		"pan_speed": 1, "show_hit_chance": true, "confirm_end_turn": false, "fullscreen": false,
	}


static func to_dict() -> Dictionary:
	return {
		"instant_movement": instant_movement, "follow_opponent": follow_opponent, "own_speed": own_speed,
		"opponent_speed": opponent_speed, "pan_speed": pan_speed, "show_hit_chance": show_hit_chance,
		"confirm_end_turn": confirm_end_turn, "fullscreen": fullscreen,
	}


## Sets every known setting from a dictionary. Missing or wrongly typed values fall back to the default,
## and indices are clamped, so an old or hand-edited file can't break anything.
static func from_dict(data: Dictionary) -> void:
	var defaults := defaults()
	var values := {}
	for key: String in defaults:
		var value: Variant = data.get(key, defaults[key])
		values[key] = value if typeof(value) == typeof(defaults[key]) else defaults[key]
	instant_movement = values["instant_movement"]
	follow_opponent = values["follow_opponent"]
	own_speed = clampi(values["own_speed"], 0, SPEED_NAMES.size() - 1)
	opponent_speed = clampi(values["opponent_speed"], 0, SPEED_NAMES.size() - 1)
	pan_speed = clampi(values["pan_speed"], 0, PAN_SPEEDS.size() - 1)
	show_hit_chance = values["show_hit_chance"]
	confirm_end_turn = values["confirm_end_turn"]
	fullscreen = values["fullscreen"]


static func reset() -> void:
	from_dict({})


## Reads the file, or keeps the defaults if there is none. Returns false if the file is missing or unreadable.
static func load_settings(path := PATH) -> bool:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		reset()
		return false
	var data := {}
	for key: String in defaults():
		if file.has_section_key("settings", key):
			data[key] = file.get_value("settings", key)
	from_dict(data)
	return true


static func save_settings(path := PATH) -> void:
	var file := ConfigFile.new()
	var data := to_dict()
	for key: String in data:
		file.set_value("settings", key, data[key])
	var err := file.save(path)
	if err != OK:
		push_error("Could not save settings: %s" % error_string(err))


## Puts the window in fullscreen or windowed mode. Does nothing when running headless.
static func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	var current := DisplayServer.window_get_mode()
	var is_full := current == DisplayServer.WINDOW_MODE_FULLSCREEN or current == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if is_full != fullscreen:
		DisplayServer.window_set_mode(want)


## The playback speed index for a turn: your own, or the opponent's.
static func speed_for(own_turn: bool) -> int:
	return own_speed if own_turn else opponent_speed


## Remembers a speed picked in battle (with +/- or the speed button) for that kind of turn.
static func set_speed_for(own_turn: bool, index: int) -> void:
	if own_turn:
		own_speed = index
	else:
		opponent_speed = index
	save_settings()
