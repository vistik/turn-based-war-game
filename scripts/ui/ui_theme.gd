class_name UITheme
extends RefCounted
## The game's look: olive drab canvas panels, khaki buttons, paper fields and tooltips, typewriter text and
## stencil-style headings, all built in code. `apply()` merges it into Godot's default theme once, so every
## Control in every scene (CanvasLayers and popups included) picks it up without setting `theme` anywhere.
##
## Fonts are system fonts with fallbacks (a stencil or condensed face for headings, a typewriter face for text),
## so nothing is shipped. Type variations: HeaderLarge/Medium/Small (stencil headings), PrimaryButton (khaki),
## TopBar (the slim strip along the top of the battle screen), HelpLabel (small muted text).

const INK := Color("15160f")
const OLIVE_DARK := Color("23261a")
const OLIVE := Color("343926")
const OLIVE_LIGHT := Color("4a5134")
const OLIVE_HIGHLIGHT := Color("5d6641")
const KHAKI := Color("c8b884")
const KHAKI_LIGHT := Color("ddcf9e")
const KHAKI_DARK := Color("8c7f55")
const PAPER := Color("e9e1c8")
const PAPER_DIM := Color("b3ab90")
const PAPER_FIELD := Color("ddd3b0")
const TEXT_DARK := Color("27240f")
const STAMP_RED := Color("b5462f")

const STENCIL_FONTS := ["Stencil", "Stencil Std", "DIN Condensed", "Impact", "Arial Narrow", "sans-serif"]
const BUTTON_FONTS := ["DIN Condensed", "Avenir Next Condensed", "Arial Narrow", "Impact", "sans-serif"]
const TYPEWRITER_FONTS := ["American Typewriter", "Courier Prime", "Courier New", "Courier", "monospace"]

static var _applied := false
static var _theme: Theme


## Merges the theme into Godot's default theme. Safe to call from every scene's _ready; only the first call works.
static func apply() -> void:
	if _applied:
		return
	_applied = true
	ThemeDB.get_default_theme().merge_with(get_theme())


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


## The stencil heading font, for code that draws or sizes headings itself.
static func heading_font() -> Font:
	return get_theme().get_font("font", "HeaderLarge")


static func _build() -> Theme:
	var t := Theme.new()
	var typewriter := _system_font(TYPEWRITER_FONTS, 400)
	var typewriter_bold := _system_font(TYPEWRITER_FONTS, 700)
	var typewriter_italic := _system_font(TYPEWRITER_FONTS, 400, true)
	var stencil := _spaced(_system_font(STENCIL_FONTS, 700), 2)
	var condensed := _spaced(_system_font(BUTTON_FONTS, 700), 1)
	t.default_font = typewriter
	t.default_font_size = 15

	# Panels: olive canvas with a dark rim and a light inner edge, like a painted crate.
	var canvas := _canvas_box(Color(OLIVE, 0.96), 1)
	_margins(canvas, 14, 12)
	t.set_stylebox("panel", "PanelContainer", canvas)
	t.set_stylebox("panel", "Panel", canvas)
	t.set_type_variation("TopBar", "PanelContainer")
	var bar := _flat(Color(OLIVE_DARK, 0.95), Color(KHAKI_DARK, 0.7), 0)
	bar.border_width_bottom = 2
	_margins(bar, 12, 4)
	t.set_stylebox("panel", "TopBar", bar)
	var popup := _flat(OLIVE_DARK, KHAKI_DARK, 1)
	_margins(popup, 6, 6)
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("panel", "AcceptDialog", canvas)
	t.set_stylebox("embedded_border", "Window", _flat(OLIVE_DARK, KHAKI_DARK, 2))
	t.set_color("title_color", "Window", KHAKI)
	t.set_font("title_font", "Window", condensed)

	# Text.
	t.set_color("font_color", "Label", PAPER)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	for spec: Array in [["HeaderLarge", 30], ["HeaderMedium", 21], ["HeaderSmall", 16]]:
		t.set_type_variation(spec[0], "Label")
		t.set_font("font", spec[0], stencil)
		t.set_font_size("font_size", spec[0], spec[1])
		t.set_color("font_color", spec[0], KHAKI)
	t.set_type_variation("HelpLabel", "Label")
	t.set_font_size("font_size", "HelpLabel", 12)
	t.set_color("font_color", "HelpLabel", PAPER_DIM)
	t.set_color("default_color", "RichTextLabel", PAPER)
	t.set_font("normal_font", "RichTextLabel", typewriter)
	t.set_font("bold_font", "RichTextLabel", typewriter_bold)
	t.set_font("italics_font", "RichTextLabel", typewriter_italic)
	t.set_font("bold_italics_font", "RichTextLabel", typewriter_bold)
	for item in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		t.set_font_size(item, "RichTextLabel", 13)
	t.set_color("selection_color", "RichTextLabel", Color(KHAKI, 0.35))

	# Buttons: olive plates with a heavy bottom edge that sink in when pressed.
	for type in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		t.set_font("font", type, condensed)
		t.set_font_size("font_size", type, 16)
		t.set_color("font_color", type, PAPER)
		t.set_color("font_hover_color", type, Color("fff7dc"))
		t.set_color("font_pressed_color", type, KHAKI_LIGHT)
		t.set_color("font_focus_color", type, PAPER)
		t.set_color("font_hover_pressed_color", type, KHAKI_LIGHT)
		t.set_color("font_disabled_color", type, Color(PAPER, 0.32))
		t.set_color("icon_normal_color", type, PAPER)
		t.set_color("icon_hover_color", type, Color("fff7dc"))
		t.set_color("icon_pressed_color", type, KHAKI_LIGHT)
		t.set_color("icon_disabled_color", type, Color(PAPER, 0.32))
		t.set_constant("h_separation", type, 6)
	for type in ["Button", "OptionButton", "MenuButton"]:
		_button_styles(t, type, OLIVE_LIGHT, OLIVE_HIGHLIGHT, OLIVE_DARK)
	for type in ["CheckBox", "CheckButton"]:
		var clear := StyleBoxEmpty.new()
		_margins(clear, 4, 4)
		for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
			t.set_stylebox(state, type, clear)
		t.set_stylebox("focus", type, _focus_box())
	t.set_type_variation("PrimaryButton", "Button")
	_button_styles(t, "PrimaryButton", KHAKI, KHAKI_LIGHT, KHAKI_DARK)
	t.set_color("font_color", "PrimaryButton", TEXT_DARK)
	t.set_color("font_hover_color", "PrimaryButton", INK)
	t.set_color("font_pressed_color", "PrimaryButton", INK)
	t.set_color("font_focus_color", "PrimaryButton", TEXT_DARK)
	t.set_color("font_hover_pressed_color", "PrimaryButton", INK)
	t.set_color("font_disabled_color", "PrimaryButton", Color(TEXT_DARK, 0.45))
	# Compact plates for the battle screen.
	t.set_type_variation("SmallButton", "Button")
	_button_styles(t, "SmallButton", OLIVE_LIGHT, OLIVE_HIGHLIGHT, OLIVE_DARK, 7)
	t.set_font_size("font_size", "SmallButton", 15)

	# Paper fields: line edits and spin boxes look like a form to be typed on.
	var field := _flat(PAPER_FIELD, KHAKI_DARK, 1)
	field.border_width_bottom = 2
	_margins(field, 8, 5)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = STAMP_RED
	var field_read_only := field.duplicate() as StyleBoxFlat
	field_read_only.bg_color = Color(PAPER_FIELD, 0.6)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field_read_only)
	t.set_stylebox("normal", "TextEdit", field)
	t.set_stylebox("focus", "TextEdit", field_focus)
	for type in ["LineEdit", "TextEdit"]:
		t.set_color("font_color", type, TEXT_DARK)
		t.set_color("font_placeholder_color", type, Color(TEXT_DARK, 0.45))
		t.set_color("font_readonly_color", type, Color(TEXT_DARK, 0.6))
		t.set_color("caret_color", type, TEXT_DARK)
		t.set_color("selection_color", type, Color(KHAKI_DARK, 0.5))
		t.set_color("font_selected_color", type, INK)
		t.set_color("clear_button_color", type, TEXT_DARK)

	# Menus and lists.
	var hover_row := _flat(OLIVE_HIGHLIGHT, KHAKI_DARK, 0)
	_margins(hover_row, 6, 2)
	t.set_stylebox("hover", "PopupMenu", hover_row)
	t.set_font("font", "PopupMenu", condensed)
	t.set_font_size("font_size", "PopupMenu", 16)
	t.set_color("font_color", "PopupMenu", PAPER)
	t.set_color("font_hover_color", "PopupMenu", Color("fff7dc"))
	t.set_color("font_disabled_color", "PopupMenu", Color(PAPER, 0.35))
	t.set_color("font_separator_color", "PopupMenu", KHAKI)
	t.set_constant("v_separation", "PopupMenu", 6)
	var list := _flat(Color(INK, 0.6), Color(KHAKI_DARK, 0.6), 1)
	_margins(list, 4, 4)
	t.set_stylebox("panel", "ItemList", list)
	t.set_stylebox("panel", "Tree", list)
	t.set_stylebox("selected", "ItemList", _flat(OLIVE_HIGHLIGHT, KHAKI_DARK, 0))
	t.set_stylebox("selected_focus", "ItemList", _flat(OLIVE_HIGHLIGHT, KHAKI, 1))
	t.set_stylebox("hovered", "ItemList", _flat(Color(OLIVE_HIGHLIGHT, 0.5), KHAKI_DARK, 0))
	t.set_color("font_color", "ItemList", PAPER)
	t.set_color("font_selected_color", "ItemList", Color("fff7dc"))
	t.set_color("font_hovered_color", "ItemList", Color("fff7dc"))

	# Tabs, for any page that groups settings.
	var tab := _flat(OLIVE_DARK, Color(KHAKI_DARK, 0.6), 1)
	_margins(tab, 12, 5)
	var tab_selected := _flat(OLIVE, KHAKI, 0)
	tab_selected.border_width_top = 2
	_margins(tab_selected, 12, 5)
	var tab_hover := tab.duplicate() as StyleBoxFlat
	tab_hover.bg_color = OLIVE_LIGHT
	for type in ["TabBar", "TabContainer"]:
		t.set_stylebox("tab_unselected", type, tab)
		t.set_stylebox("tab_hovered", type, tab_hover)
		t.set_stylebox("tab_selected", type, tab_selected)
		t.set_stylebox("tab_disabled", type, tab)
		t.set_font("font", type, condensed)
		t.set_font_size("font_size", type, 16)
		t.set_color("font_selected_color", type, KHAKI_LIGHT)
		t.set_color("font_unselected_color", type, PAPER_DIM)
		t.set_color("font_hovered_color", type, PAPER)
	t.set_stylebox("panel", "TabContainer", canvas)

	# Sliders, scroll bars and separators.
	var track := _flat(Color(INK, 0.7), Color(KHAKI_DARK, 0.4), 1)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", _flat(KHAKI_DARK, KHAKI_DARK, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(KHAKI, KHAKI, 0))
	for spec: Array in [["VScrollBar", true], ["HScrollBar", false]]:
		var type: String = spec[0]
		var gutter := _flat(Color(INK, 0.45), Color(0, 0, 0, 0), 0)
		gutter.set_corner_radius_all(3)
		gutter.set_content_margin_all(4)
		var grabber := _flat(Color(KHAKI_DARK, 0.85), Color(0, 0, 0, 0), 0)
		grabber.set_corner_radius_all(3)
		grabber.set_content_margin_all(4)
		var lit := grabber.duplicate() as StyleBoxFlat
		lit.bg_color = KHAKI
		t.set_stylebox("scroll", type, gutter)
		t.set_stylebox("scroll_focus", type, gutter)
		t.set_stylebox("grabber", type, grabber)
		t.set_stylebox("grabber_highlight", type, lit)
		t.set_stylebox("grabber_pressed", type, lit)
	for spec: Array in [["HSeparator", false], ["VSeparator", true]]:
		var line := StyleBoxLine.new()
		line.color = Color(KHAKI, 0.3)
		line.thickness = 2
		line.vertical = spec[1]
		t.set_stylebox("separator", spec[0], line)
		t.set_constant("separation", spec[0], 9)

	# Tooltips: a typed note on khaki paper.
	var note := _flat(PAPER_FIELD, KHAKI_DARK, 1)
	note.shadow_color = Color(0, 0, 0, 0.35)
	note.shadow_size = 4
	_margins(note, 9, 6)
	t.set_stylebox("panel", "TooltipPanel", note)
	t.set_color("font_color", "TooltipLabel", TEXT_DARK)
	t.set_font("font", "TooltipLabel", typewriter)
	t.set_font_size("font_size", "TooltipLabel", 13)
	return t


## Draws the menu backdrop on a full-screen Control: dark olive with a faint map grid and a vignette.
static func draw_backdrop(c: Control) -> void:
	var size := c.size
	c.draw_rect(Rect2(Vector2.ZERO, size), Color("1b1d14"))
	var step := 40.0
	var lines := 0
	var x := fmod(size.x * 0.5, step)
	while x < size.x:
		c.draw_line(Vector2(x, 0), Vector2(x, size.y), Color(KHAKI, 0.07 if lines % 5 == 0 else 0.03), 1.0)
		x += step
		lines += 1
	lines = 0
	var y := fmod(size.y * 0.5, step)
	while y < size.y:
		c.draw_line(Vector2(0, y), Vector2(size.x, y), Color(KHAKI, 0.07 if lines % 5 == 0 else 0.03), 1.0)
		y += step
		lines += 1
	# Vignette: dark bands fading in from each edge.
	var dark := Color(0, 0, 0, 0.55)
	var clear := Color(0, 0, 0, 0)
	var band := minf(size.x, size.y) * 0.3
	c.draw_polygon([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, band), Vector2(0, band)], [dark, dark, clear, clear])
	c.draw_polygon([Vector2(0, size.y - band), Vector2(size.x, size.y - band), size, Vector2(0, size.y)], [clear, clear, dark, dark])
	c.draw_polygon([Vector2.ZERO, Vector2(band, 0), Vector2(band, size.y), Vector2(0, size.y)], [dark, clear, clear, dark])
	c.draw_polygon([Vector2(size.x - band, 0), Vector2(size.x, 0), size, Vector2(size.x - band, size.y)], [clear, dark, dark, clear])


static func _system_font(names: Array, weight: int, italic := false) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(names)
	font.font_weight = weight
	font.font_italic = italic
	return font


static func _spaced(base: Font, spacing: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = base
	font.spacing_glyph = spacing
	return font


static func _flat(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(2)
	return box


static func _margins(box: StyleBox, horizontal: float, vertical: float) -> void:
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	box.content_margin_top = vertical
	box.content_margin_bottom = vertical


static func _focus_box() -> StyleBoxFlat:
	var box := _flat(Color(0, 0, 0, 0), Color(KHAKI, 0.8), 1)
	box.draw_center = false
	box.expand_margin_left = 2
	box.expand_margin_right = 2
	box.expand_margin_top = 2
	box.expand_margin_bottom = 2
	return box


## Normal, hover, pressed and disabled plates for a button type in one colour family.
static func _button_styles(t: Theme, type: String, base: Color, lit: Color, sunk: Color, padding := 10) -> void:
	var normal := _flat(base, INK, 1)
	normal.border_width_bottom = 3
	normal.border_color = Color(INK, 0.9)
	_margins(normal, padding, 3)
	normal.content_margin_bottom = 5
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = lit
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = sunk
	pressed.border_width_top = 3
	pressed.border_width_bottom = 1
	pressed.content_margin_top = 5
	pressed.content_margin_bottom = 3
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(base.darkened(0.45), 0.8)
	disabled.border_color = Color(INK, 0.5)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, _focus_box())


## A tiled canvas-texture panel: olive cloth with a little noise, a dark rim and a lighter inner edge.
static func _canvas_box(base: Color, seed_value: int) -> StyleBoxTexture:
	var size := 50
	var rim := 4
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for y in size:
		for x in size:
			var shade := rng.randf_range(-0.018, 0.018)
			# A faint weave every third thread.
			if (x - rim) % 3 == 0:
				shade -= 0.008
			if (y - rim) % 3 == 0:
				shade -= 0.008
			var color := Color(base.r + shade, base.g + shade, base.b + shade, base.a)
			var edge := mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
			if edge == 0:
				color = Color(INK, 0.95)
			elif edge == 1:
				color = Color(KHAKI_DARK.r, KHAKI_DARK.g, KHAKI_DARK.b, 0.55)
			elif edge == 2:
				color = color.darkened(0.25)
			image.set_pixel(x, y, color)
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(image)
	box.texture_margin_left = rim
	box.texture_margin_right = rim
	box.texture_margin_top = rim
	box.texture_margin_bottom = rim
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return box
