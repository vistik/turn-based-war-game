class_name SettingsPanel
extends VBoxContainer
## The settings controls, shared by the main menu's Settings page and the in-battle settings popup.
## Every change is saved straight away and announced through `changed`.

signal changed

const MUTED := Color(1, 1, 1, 0.6)


func _ready() -> void:
	GameSettings.ensure_loaded()
	add_theme_constant_override("separation", 6)
	_heading("Battle playback")
	_toggle("Instant movement", "Soldiers and tanks jump straight to where they're going instead of walking there.",
			"instant_movement")
	_toggle("Follow opponent moves", "The camera pans to the AI's or online opponent's units when they move or fire.",
			"follow_opponent")
	_choice("Speed of your turns", "Playback of your own orders. +/- in battle changes it too.",
			"own_speed", GameSettings.SPEED_NAMES)
	_choice("Speed of opponent turns", "Playback of the AI's or online opponent's turns.",
			"opponent_speed", GameSettings.SPEED_NAMES)
	_heading("Controls")
	_choice("Camera pan speed", "How fast WASD and the arrow keys move the camera.",
			"pan_speed", GameSettings.PAN_SPEED_NAMES)
	_toggle("Show hit chances", "Hit, graze and crit odds when hovering or aiming at a target.", "show_hit_chance")
	_toggle("Confirm end turn", "Ask before ending the turn while some units can still act.", "confirm_end_turn")
	_heading("Display")
	_toggle("Fullscreen", "Play in fullscreen instead of a window.", "fullscreen")


func _set_value(key: String, value: Variant) -> void:
	var data := GameSettings.to_dict()
	data[key] = value
	GameSettings.from_dict(data)
	GameSettings.save_settings()
	if key == "fullscreen":
		GameSettings.apply_window()
	changed.emit()


func _heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("e8e2cf"))
	if get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		add_child(gap)
	add_child(label)
	add_child(HSeparator.new())


## A row with the setting's name and hint on the left and its control on the right.
func _row(title: String, hint: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", 15)
	text.add_child(name_label)
	var hint_label := Label.new()
	hint_label.text = hint
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", MUTED)
	text.add_child(hint_label)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)


func _toggle(title: String, hint: String, key: String) -> void:
	var check := CheckButton.new()
	check.button_pressed = GameSettings.to_dict()[key]
	check.toggled.connect(func(on: bool) -> void: _set_value(key, on))
	_row(title, hint, check)


func _choice(title: String, hint: String, key: String, names: Array) -> void:
	var option := OptionButton.new()
	for item: String in names:
		option.add_item(item)
	option.selected = GameSettings.to_dict()[key]
	option.custom_minimum_size = Vector2(120, 0)
	option.item_selected.connect(func(index: int) -> void: _set_value(key, index))
	_row(title, hint, option)
