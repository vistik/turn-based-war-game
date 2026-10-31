extends Control
## Main menu and campaign screens. Starts campaign missions and skirmishes by handing a Battle to
## GameSession and switching to the battle scene.

const ALLIED := Color("9cc45a")
const GERMAN := Color("b8c0c8")
const MUTED := UITheme.PAPER_DIM
const BAD := Color("ff7a6a")
const GOOD := Color("8fe08a")
## [label, setup "map", size]. Random maps are generated fresh each game; bigger ones bring bigger forces.
const SKIRMISH_MAPS := [
	["Normandy village (48x48, 8 a side)", "village", 48],
	["Random map, standard (44x44, 8 a side)", "random", 44],
	["Random map, large (64x64, 12 a side)", "random", 64],
	["Random map, huge (84x84, 15 a side with tanks)", "random", 84],
]
## [label, Allies are AI, Germany is AI]
const SKIRMISH_MODES := [["Play vs AI", false, true], ["Hotseat", false, false], ["Watch AI vs AI", true, true]]

var _page: Control
var _map_choice: OptionButton
## Scenario files listed after SKIRMISH_MAPS in the map choice.
var _scenario_paths: Array[String] = []
var _recruit_choice: OptionButton
var _address: LineEdit
var _port: LineEdit
## The map choice to host with, kept while the waiting page is up.
var _host_setup := {}
## The saved online game being hosted to continue (GameSession.online_offer), or {} for a new game.
var _host_offer := {}


func _ready() -> void:
	GameSettings.ensure_loaded()
	Net.peer_joined.connect(_on_peer_joined)
	Net.setup_received.connect(_start_online)
	Net.connection_failed.connect(_on_connection_failed)
	UITheme.apply()
	Net.resume_offered.connect(_on_resume_offered)
	Net.resume_started.connect(_on_resume_started)
	Net.resume_declined.connect(_on_resume_declined)
	Net.desynced.connect(_on_resume_failed)
	Net.disconnected.connect(_on_resume_failed.bind("The other player left."))
	var background := Control.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.draw.connect(UITheme.draw_backdrop.bind(background))
	background.resized.connect(background.queue_redraw)
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
	for map_spec: Array in SKIRMISH_MAPS:
		_map_choice.add_item(map_spec[0])
	_scenario_paths.clear()
	for entry in Scenario.list_files():
		_map_choice.add_item("Scenario: %s" % entry["title"])
		_scenario_paths.append(entry["path"])
	_map_choice.custom_minimum_size = Vector2(0, 40)
	box.add_child(_map_choice)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	box.add_child(modes)
	for i in SKIRMISH_MODES.size():
		var button := _button(modes, SKIRMISH_MODES[i][0], _start_skirmish.bind(i))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(box, "Map and scenario editor", func() -> void: get_tree().change_scene_to_file("res://scenes/editor.tscn"))

	_section(box, "Online")
	_text(box, "Play another computer directly, no server needed. The host picks the map above and plays the Allies. Both games check after every order that they still agree.", MUTED, 14, true)
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 8)
	box.add_child(host_row)
	_text(host_row, "Port", MUTED, 14)
	_port = LineEdit.new()
	_port.text = str(Net.DEFAULT_PORT)
	_port.custom_minimum_size = Vector2(90, 0)
	host_row.add_child(_port)
	var host_button := _button(host_row, "Host game", _host)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	box.add_child(join_row)
	_address = LineEdit.new()
	_address.placeholder_text = "Host address, e.g. 192.168.1.20 or 192.168.1.20:24944"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_address)
	_button(join_row, "Join game", _join)
	var online_save := GameSession.peek("online")
	if not online_save.is_empty():
		var side: String = Battle.TEAM_NAMES[online_save["team"]]
		_button(box, "Continue online game: %s, round %d, as %s" % [online_save["title"], online_save["round"], side], _host_resume, true)
		var hint := "Hosts your saved game on the port above; your opponent (%s) joins as usual and keeps their side. Or join them if they host it." % online_save["opponent"]
		_text(box, hint, MUTED, 14, true)
		if not online_save["hosted"]:
			_address.text = online_save["opponent"]
	_gap(box, 12)
	_button(box, "Settings", _show_settings)
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


func _skirmish_setup() -> Dictionary:
	var index := _map_choice.selected - SKIRMISH_MAPS.size()
	if index >= 0:
		var scenario := Scenario.load_file(_scenario_paths[index])
		if scenario != null:
			return {"map": "scenario", "scenario": scenario.to_data(), "seed": randi() % 1000000000 + 1}
		push_warning(Scenario.last_error)
	var spec: Array = SKIRMISH_MAPS[maxi(0, _map_choice.selected) if index < 0 else 0]
	return {"map": spec[1], "size": spec[2], "seed": randi() % 1000000000 + 1}


func _start_skirmish(mode: int) -> void:
	var built := GameSession.build_skirmish(_skirmish_setup())
	GameSession.campaign = null
	GameSession.start_battle(built[0], [SKIRMISH_MODES[mode][1], SKIRMISH_MODES[mode][2]], built[1])
	get_tree().change_scene_to_file(GameSession.BATTLE_SCENE)


# --- Online ---

func _host() -> void:
	var port := _port.text.to_int()
	_host_setup = _skirmish_setup()
	_host_setup["game_id"] = GameSession.new_game_id()
	_host_offer = {}
	var err := Net.host(port)
	if err != OK:
		_show_net_page("Can't host", "Couldn't open port %d (%s). Try another port." % [port, error_string(err)], "Back")
		return
	var addresses := Array(Net.local_addresses()).map(func(a: String) -> String: return "%s:%d" % [a, port])
	_show_net_page("Waiting for the other player",
			"%s\n\nThey choose Join game and type:\n%s\n\nOn the same network that just works. Over the internet, forward UDP port %d on your router to this computer, or both use a VPN such as Tailscale or ZeroTier." % [
			_map_choice.get_item_text(_map_choice.selected), "\n".join(addresses) if not addresses.is_empty() else "this computer's address", port], "Cancel")


func _join() -> void:
	var text := _address.text.strip_edges()
	if text == "":
		_address.placeholder_text = "Type the host's address first"
		return
	var host := text
	var port := Net.DEFAULT_PORT
	if text.count(":") == 1:
		host = text.get_slice(":", 0)
		port = text.get_slice(":", 1).to_int()
	var err := Net.join(host, port)
	if err != OK:
		_show_net_page("Can't connect", error_string(err), "Back")
	else:
		_show_net_page("Connecting to %s:%d..." % [host, port], "Waiting for the host. If nothing happens, check the address and port, and that the host clicked Host game.", "Cancel")


## A page shown while hosting or joining; its button gives up and goes back to the main menu.
func _show_net_page(title: String, text: String, button: String) -> void:
	var box := _new_page(560)
	_title(box, title, 32)
	_text(box, text, UITheme.PAPER, 16, true)
	_gap(box, 12)
	_button(box, button, func() -> void:
		Net.close()
		_show_main())


func _on_peer_joined() -> void:
	if not _host_offer.is_empty():
		Net.send_resume(_host_offer)
		_show_net_page("Continuing the saved game", "The other player joined and is loading the battle.", "Cancel")
		return
	Net.send_setup(_host_setup)
	_start_online(_host_setup)


func _on_connection_failed() -> void:
	_show_net_page("Couldn't connect", "The host didn't answer, or is running a different version of the game. Check the address and port, and that the host is waiting.", "Back")


## Both players build the same battle from the same setup.
func _start_online(setup: Dictionary) -> void:
	var built := GameSession.build_skirmish(setup)
	GameSession.start_online(built[0], built[1], Net.local_team, setup.get("game_id", GameSession.new_game_id()), Net.opponent, Net.is_host)
	get_tree().change_scene_to_file(GameSession.BATTLE_SCENE)


# --- Continuing a saved online game ---

## Host the saved online game again, on our old side, and wait for the opponent to join.
func _host_resume() -> void:
	var port := _port.text.to_int()
	var offer := GameSession.online_offer()
	if offer.is_empty() or not GameSession.resume_online(offer, offer["team"], GameSession.peek("online")["opponent"], true):
		_show_net_page("Can't continue", "The saved online game couldn't be loaded.", "Back")
		return
	var err := Net.host(port, offer["team"])
	if err != OK:
		_show_net_page("Can't host", "Couldn't open port %d (%s). Try another port." % [port, error_string(err)], "Back")
		return
	_host_offer = offer
	var addresses := Array(Net.local_addresses()).map(func(a: String) -> String: return "%s:%d" % [a, port])
	_show_net_page("Waiting for the other player",
			"Continuing %s, round %d, as %s.\n\nThey choose Join game and type:\n%s" % [offer["title"], offer["round"],
			Battle.TEAM_NAMES[offer["team"]], "\n".join(addresses) if not addresses.is_empty() else "this computer's address"], "Cancel")


## Joiner: the host wants to continue a saved game. Matching saves go straight on; otherwise ask first.
func _on_resume_offered(offer: Dictionary) -> void:
	var difference := GameSession.compare_online(offer)
	if difference == "" or not GameSession.has_save("online"):
		_accept_resume(offer)
		return
	var box := _new_page(560)
	_title(box, "Continue the host's saved game?", 32)
	_text(box, "%s, playing as %s.\n\n%s\n\nContinuing replaces your saved online game with the host's." % [
			offer.get("title", "?"), Battle.TEAM_NAMES[Net.local_team], difference], Color.WHITE, 16, true)
	_gap(box, 12)
	_button(box, "Continue from the host's save", _accept_resume.bind(offer), true)
	_button(box, "Leave", func() -> void:
		Net.decline_resume()
		_show_main())


func _accept_resume(offer: Dictionary) -> void:
	if not GameSession.resume_online(offer, Net.local_team, Net.opponent, false):
		Net.report_desync("The host's saved battle doesn't load the same here.")
		return
	Net.accept_resume(GameSession.battle.checksum())
	_show_net_page("Continuing the saved game", "Checking that both games loaded the same battle...", "Cancel")


## Both games hold the same battle: save it as agreed, and play on.
func _on_resume_started() -> void:
	GameSession.save_online(Net.local_team)
	get_tree().change_scene_to_file(GameSession.BATTLE_SCENE)


func _on_resume_declined() -> void:
	Net.close()
	_show_net_page("Not continued", "The other player chose not to continue this game. Your save is kept.", "Back")


## The connection broke, or the two games didn't load the same battle, while setting up.
func _on_resume_failed(reason: String) -> void:
	Net.close()
	_show_net_page("Couldn't continue the game", reason + " Your save is kept.", "Back")


# --- Settings ---

func _show_settings() -> void:
	var box := _new_page(560)
	_title(box, "Settings", 40)
	_text(box, "Saved as you change them. They only change how battles are shown, never how they play out.", MUTED, 14, true)
	box.add_child(SettingsPanel.new())
	_gap(box, 12)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_button(buttons, "Back", _show_main, true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(buttons, "Restore defaults", func() -> void:
		GameSettings.reset()
		GameSettings.save_settings()
		GameSettings.apply_window()
		_show_settings())


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
			_text(box, "• " + line, Color(UITheme.PAPER, 0.85), 14)

	if not campaign.is_won() and not campaign.is_lost():
		var mission := campaign.current_mission()
		_section(box, "Briefing")
		_text(box, mission["briefing"], UITheme.PAPER, 15, true)
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
		var color := Color(UITheme.PAPER, 0.35) if dead else UITheme.PAPER
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

## Replaces the current page with a fresh, centred, scrollable column on a canvas panel.
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
		margin.add_theme_constant_override("margin_" + side, 28)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	center.add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(inner)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 8)
	inner.add_child(box)
	return box


func _title(parent: Control, text: String, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.uppercase = true
	label.theme_type_variation = "HeaderLarge"
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)


func _section(parent: Control, text: String) -> void:
	_gap(parent, 10)
	_title(parent, text, 21)
	parent.add_child(HSeparator.new())


func _text(parent: Control, text: String, color: Color, size: int, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(300, 0)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, action: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44 if primary else 38)
	button.add_theme_font_size_override("font_size", 19 if primary else 16)
	if primary:
		button.theme_type_variation = "PrimaryButton"
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _gap(parent: Control, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	parent.add_child(spacer)
