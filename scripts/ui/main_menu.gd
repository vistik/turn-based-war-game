extends Control
## Main menu and campaign screens. Starts campaign missions and skirmishes by handing a Battle to
## GameSession and switching to the battle scene.

const ALLIED := Color("9cc45a")
const GERMAN := Color("b8c0c8")
const MUTED := Color(1, 1, 1, 0.6)
const BAD := Color("ff7a6a")
const GOOD := Color("8fe08a")
const SKIRMISH_MAPS := ["Normandy village", "Random Normandy map"]
## [label, Allies are AI, Germany is AI]
const SKIRMISH_MODES := [["Play vs AI", false, true], ["Hotseat", false, false], ["Watch AI vs AI", true, true]]

var _page: Control
var _map_choice: OptionButton
var _recruit_choice: OptionButton


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.07, 0.075, 0.065)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	if GameSession.show_campaign and GameSession.campaign != null:
		GameSession.show_campaign = false
		_show_campaign()
	else:
		_show_main()


# --- Main menu ---

func _show_main() -> void:
	var box := _new_page(560)
	_title(box, "Normandy 1944", 48)
	_text(box, "Squad tactics in the bocage, June 1944. Allies against Germany.", MUTED, 16, true)
	_gap(box, 16)

	var campaign_save := GameSession.peek("campaign")
	if not campaign_save.is_empty():
		var saved := Campaign.from_dict(campaign_save["campaign"])
		var label := "Continue campaign: %s" % ("in battle" if not campaign_save["battle"].is_empty() else "mission %d of %d" % [mini(saved.mission_index + 1, Campaign.MISSIONS.size()), Campaign.MISSIONS.size()])
		_button(box, label, _continue.bind("campaign"), true)
	var skirmish_save := GameSession.peek("skirmish")
	if not skirmish_save.is_empty():
		_button(box, "Continue skirmish: %s" % skirmish_save["title"], _continue.bind("skirmish"), true)

	_section(box, "Campaign")
	_text(box, "Five missions from the beaches to Caen with one squad. Soldiers gain rank, get hurt and die for good.", MUTED, 14, true)
	_button(box, "New campaign", _new_campaign, true)

	_section(box, "Skirmish")
	_map_choice = OptionButton.new()
	for map_name in SKIRMISH_MAPS:
		_map_choice.add_item(map_name)
	_map_choice.custom_minimum_size = Vector2(0, 40)
	box.add_child(_map_choice)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	box.add_child(modes)
	for i in SKIRMISH_MODES.size():
		var button := _button(modes, SKIRMISH_MODES[i][0], _start_skirmish.bind(i))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gap(box, 12)
	_button(box, "Quit", get_tree().quit)


func _continue(slot: String) -> void:
	if not GameSession.load_game(slot):
		_show_main()
		return
	if GameSession.battle != null:
		get_tree().change_scene_to_file(GameSession.BATTLE_SCENE)
	else:
		_show_campaign()


func _new_campaign() -> void:
	GameSession.campaign = Campaign.create(randi())
	GameSession.battle = null
	GameSession.save_game()
	_show_campaign()


func _start_skirmish(mode: int) -> void:
	var seed := randi()
	var title: String = SKIRMISH_MAPS[_map_choice.selected]
	var battle: Battle
	if _map_choice.selected == 0:
		battle = NormandyScenario.build(seed)
	else:
		var waves := []
		for team in Battle.TEAM_COUNT:
			waves.append({"round": NormandyScenario.REINFORCEMENT_ROUND, "team": team, "roster": NormandyScenario.REINFORCEMENTS})
		battle = BattleFactory.create(MapGenerator.generate(seed, Vector2i(44, 44)), [NormandyScenario.ROSTER, NormandyScenario.ROSTER], seed, {"reinforcements": waves})
		title = "Random map #%d" % (seed % 10000)
	GameSession.campaign = null
	GameSession.start_battle(battle, [SKIRMISH_MODES[mode][1], SKIRMISH_MODES[mode][2]], title)
	get_tree().change_scene_to_file(GameSession.BATTLE_SCENE)


# --- Campaign screen ---

func _show_campaign() -> void:
	var campaign := GameSession.campaign
	var box := _new_page(860)
	var total := Campaign.MISSIONS.size()
	if campaign.is_won():
		_title(box, "Victory in Normandy", 40)
		_text(box, "Your squad fought its way to Caen. The campaign is won.", GOOD, 18, true)
	elif campaign.is_lost():
		_title(box, "The company is spent", 40)
		_text(box, "No soldiers left and no supplies to replace them. The campaign is lost.", BAD, 18, true)
	else:
		var mission := campaign.current_mission()
		_title(box, "Mission %d of %d: %s" % [campaign.mission_index + 1, total, mission["name"]], 32)
	_text(box, "Supplies: %d   (a replacement costs %d)" % [campaign.supplies, Campaign.RECRUIT_COST], MUTED, 15)

	if not campaign.last_report.is_empty():
		var report := campaign.last_report
		_section(box, "After action: %s" % report["mission"])
		_text(box, "Victory" if report["won"] else "Defeat. The mission can be tried again.", GOOD if report["won"] else BAD, 17)
		for line: String in report["lines"]:
			_text(box, "• " + line, Color(1, 1, 1, 0.85), 14)

	if not campaign.is_won() and not campaign.is_lost():
		var mission := campaign.current_mission()
		_section(box, "Briefing")
		_text(box, mission["briefing"], Color.WHITE, 15, true)
		_text(box, "Enemy: %s" % _force(mission["enemy"]), GERMAN, 14, true)
		if mission.has("enemy_reinforcements"):
			for wave: Dictionary in mission["enemy_reinforcements"]:
				_text(box, "   Round %d reinforcements: %s" % [wave["round"], _force(wave["roster"])], GERMAN, 14, true)
		if mission.has("support"):
			_text(box, "Support: %s" % _force(mission["support"]), ALLIED, 14)
		_text(box, "Win: first to %d points from the church, crossroads and farm, or wipe them out. %d rounds." % [mission["vp_to_win"], mission["max_rounds"]], MUTED, 14, true)

	_section(box, "Your squad")
	var deploying := {}
	for soldier in campaign.deployable():
		deploying[soldier["id"]] = true
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 22)
	box.add_child(grid)
	for header in ["Soldier", "Role", "XP", "Kills", "Missions", "Status", ""]:
		_text(grid, header, MUTED, 13)
	for soldier in campaign.roster:
		var dead: bool = soldier["status"] == "dead"
		var color := Color(1, 1, 1, 0.35) if dead else Color.WHITE
		_text(grid, Campaign.display_name(soldier), ALLIED if not dead else color, 14)
		_text(grid, soldier["role"], color, 14)
		_text(grid, str(soldier["xp"]), color, 14)
		_text(grid, str(soldier["kills"]), color, 14)
		_text(grid, str(soldier["missions"]), color, 14)
		var status: String = {"ready": "Ready", "recovering": "Wounded, sits out", "dead": "Killed in action"}[soldier["status"]]
		_text(grid, status, BAD if soldier["status"] != "ready" else color, 14)
		_text(grid, "Deploys" if deploying.has(soldier["id"]) else "", GOOD, 13)

	if not campaign.is_won():
		var recruit := HBoxContainer.new()
		recruit.add_theme_constant_override("separation", 8)
		box.add_child(recruit)
		_recruit_choice = OptionButton.new()
		for role in Campaign.RECRUIT_ROLES:
			_recruit_choice.add_item(role)
		recruit.add_child(_recruit_choice)
		var hire := _button(recruit, "Recruit (%d supply)" % Campaign.RECRUIT_COST, _recruit)
		hire.disabled = not campaign.can_recruit()
		_text(recruit, "Up to %d soldiers deploy; officers first." % Campaign.SQUAD_SIZE, MUTED, 13)

	_gap(box, 8)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	if campaign.is_won() or campaign.is_lost():
		_button(buttons, "New campaign", _new_campaign, true)
	else:
		var start := _button(buttons, "Start mission", _start_mission, true)
		start.disabled = campaign.deployable().is_empty()
	_button(buttons, "Main menu", _show_main)


func _recruit() -> void:
	GameSession.campaign.recruit(Campaign.RECRUIT_ROLES[_recruit_choice.selected])
	GameSession.save_game()
	_show_campaign()


func _start_mission() -> void:
	var campaign := GameSession.campaign
	var battle := campaign.build_battle(randi())
	GameSession.start_battle(battle, [false, true], "Mission %d: %s" % [campaign.mission_index + 1, campaign.current_mission()["name"]])
	GameSession.save_game()
	get_tree().change_scene_to_file(GameSession.BATTLE_SCENE)


## "Officer, 2 Rifleman, Tank" from a list of roles.
static func _force(roles: Array) -> String:
	var counts := {}
	for role: String in roles:
		counts[role] = counts.get(role, 0) + 1
	var parts := PackedStringArray()
	for role: String in counts:
		parts.append(role if counts[role] == 1 else "%d %s" % [counts[role], role])
	return ", ".join(parts)


# --- Widgets ---

## Replaces the current page with a fresh, centred, scrollable column.
func _new_page(width: float) -> VBoxContainer:
	if _page != null:
		_page.queue_free()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_page = scroll
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var margin := MarginContainer.new()
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	center.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	return box


func _title(parent: Control, text: String, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("e8e2cf"))
	parent.add_child(label)


func _section(parent: Control, text: String) -> void:
	_gap(parent, 10)
	_title(parent, text, 22)
	parent.add_child(HSeparator.new())


func _text(parent: Control, text: String, color: Color, size: int, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(300, 0)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, action: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 46 if primary else 40)
	button.add_theme_font_size_override("font_size", 18 if primary else 16)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _gap(parent: Control, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	parent.add_child(spacer)
