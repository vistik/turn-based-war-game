class_name ActionButton
extends Button
## A square button on the battle screen's action bar: the action's icon (ActionIcons), its key in the corner,
## and an optional badge such as how many grenades are left. The name and key show as a tooltip and on the
## bar's caption while hovered.

const SIZE := 50.0

## Which icon to draw (an ActionIcons name; may differ from the action, e.g. "stand" for crouch when crouched).
var icon_name := ""
var key := ""
## Small text in the bottom right corner ("2", "HE"), or "".
var badge := ""
## What the button does, for the tooltip and caption.
var title := ""
var primary := false


func _init(p_icon: String, p_key: String, p_title: String) -> void:
	icon_name = p_icon
	key = p_key
	title = p_title
	custom_minimum_size = Vector2(SIZE, SIZE)
	focus_mode = Control.FOCUS_NONE
	theme_type_variation = "SmallButton"
	tooltip_text = describe()


func describe() -> String:
	return "%s (%s)" % [title, key] if key != "" else title


func set_look(p_icon: String, p_title: String, p_badge := "") -> void:
	if p_icon == icon_name and p_title == title and p_badge == badge:
		return
	icon_name = p_icon
	title = p_title
	badge = p_badge
	tooltip_text = describe()
	queue_redraw()


func _draw() -> void:
	var ink := UITheme.TEXT_DARK if primary else UITheme.PAPER
	if disabled:
		ink = Color(ink, 0.3)
	elif is_hovered() and not primary:
		ink = UITheme.KHAKI_LIGHT
	ActionIcons.draw(self, size * 0.5 + Vector2(0, 2), icon_name, size.y * 0.3, ink)
	var font := get_theme_default_font()
	if key != "":
		draw_string(font, Vector2(4, 12), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(ink, ink.a * 0.75))
	if badge != "":
		draw_string(font, Vector2(0, size.y - 4), badge, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 12, ink)
