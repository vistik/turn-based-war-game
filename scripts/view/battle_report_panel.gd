class_name BattleReportPanel
extends PanelContainer
## The after-action report (BattleReport) on screen: who won, then two tabs: both sides side by side (orders,
## shooting, the odds, luck, cover, damage, morale) and every soldier's own numbers. Opened from the game-over
## screen and from the replay controls; closed with its button or Esc.

const BAD := Color("ff7a6a")


## Builds the report from the replay (plays it through) and shows it over the given layer.
static func open(parent: Node, replay: Replay, team_colors: Array) -> BattleReportPanel:
	var panel := BattleReportPanel.new()
	parent.add_child(panel)
	panel._build(BattleReport.from_replay(replay), team_colors)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	return panel


## Keys stay with the report (the game-over screen under it leaves on any key); Esc closes it.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()
	if event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()


func _build(report: BattleReport, team_colors: Array) -> void:
	# Clicks stay on the report instead of dismissing the game-over screen under it.
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := Label.new()
	title.text = "After-action report"
	title.theme_type_variation = "HeaderMedium"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var summary := Label.new()
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if report.winner == 0 or report.winner == 1:
		summary.text = "%s win in %d rounds" % [report.team_names[report.winner], report.rounds]
		summary.add_theme_color_override("font_color", team_colors[report.winner])
	elif report.winner == Battle.DRAW:
		summary.text = "A draw after %d rounds" % report.rounds
	else:
		summary.text = "Unfinished, round %d" % report.rounds
	box.add_child(summary)
	for note in _notes(report):
		var label := Label.new()
		label.text = note
		label.theme_type_variation = "HelpLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(520, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", BAD)
		box.add_child(label)
	# The window's height (the panel may not be on screen yet, so not its own viewport's).
	var window := (Engine.get_main_loop() as SceneTree).root.get_visible_rect().size
	var height := clampi(int(window.y * 0.62), 240, 560)
	var tabs := TabContainer.new()
	# As wide as the widest tab, so switching doesn't resize the panel.
	tabs.use_hidden_tabs_for_min_size = true
	tabs.custom_minimum_size = Vector2(0, height)
	box.add_child(tabs)
	tabs.add_child(_sides_tab(report, team_colors))
	tabs.add_child(_soldiers_tab(report, team_colors))
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(140, 36)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(queue_free)
	box.add_child(close)


## Both sides side by side, a row per number, under section headings.
func _sides_tab(report: BattleReport, team_colors: Array) -> ScrollContainer:
	var scroll := _scroll("Sides")
	var grid := _grid(3)
	scroll.add_child(grid)
	_cell(grid, "", Color.TRANSPARENT, true)
	for team in 2:
		_cell(grid, _side_title(report, team), team_colors[team], true)
	for row: Array in report.rows():
		if row.size() == 1:
			_cell(grid, row[0], UITheme.KHAKI, true)
			_cell(grid, "", Color.TRANSPARENT)
			_cell(grid, "", Color.TRANSPARENT)
			continue
		var label := _cell(grid, row[0], UITheme.PAPER_DIM)
		label.tooltip_text = row[3]
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		for team in 2:
			_cell(grid, row[1 + team], UITheme.PAPER).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return scroll


## Each side's soldiers, one row each: shots, hits, odds, hits against the odds, damage, kills, how they ended.
func _soldiers_tab(report: BattleReport, team_colors: Array) -> ScrollContainer:
	var scroll := _scroll("Soldiers")
	# One grid for both sides, so their columns line up.
	var columns := BattleReport.UNIT_COLUMNS.size()
	var grid := _grid(columns)
	scroll.add_child(grid)
	for team in 2:
		_cell(grid, _side_title(report, team), team_colors[team], true)
		for i in columns - 1:
			_cell(grid, "", Color.TRANSPARENT)
		for column: String in BattleReport.UNIT_COLUMNS:
			_cell(grid, column, UITheme.KHAKI)
		for row: Array in report.unit_rows(team):
			for i in row.size():
				var cell := _cell(grid, row[i], BAD if row[i] == "Killed" else (UITheme.PAPER if i < 2 else UITheme.PAPER_DIM))
				if i >= 2:
					cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return scroll


func _side_title(report: BattleReport, team: int) -> String:
	var who: String = report.team_names[team]
	return who + (" (%s)" % report.players[team] if report.players[team] != "" else "")


func _scroll(tab_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return scroll


func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 2)
	return grid


func _notes(report: BattleReport) -> PackedStringArray:
	var notes := PackedStringArray()
	if not report.complete:
		notes.append("The recording began mid-battle, so this covers only part of it.")
	if report.error != "":
		notes.append("The replay stopped short: %s The game's rules have probably changed since." % report.error)
	return notes


func _cell(grid: GridContainer, text: String, color: Color, header := false) -> Label:
	var label := Label.new()
	label.text = text
	if header:
		label.theme_type_variation = "HeaderSmall"
	if color.a > 0.0:
		label.add_theme_color_override("font_color", color)
	grid.add_child(label)
	return label
