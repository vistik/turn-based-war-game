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
## The orders being written on the two-player campaign's orders page.
var _order_side := 0
var _order_counts := {}
var _order_flank := "balanced"
var _order_posture := "offensive"
var _order_labels := {}
var _order_total: Label
var _order_seal: Button
var _address: LineEdit
var _port: LineEdit
var _password: LineEdit
## The password typed last, kept while the game runs so it needn't be typed again.
static var _last_password := ""
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
	if GameSession.show_campaign and GameSession.war != null:
		GameSession.show_campaign = false
		_show_war()
	elif GameSession.show_campaign and GameSession.campaign != null:
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

	_section(box, "Two-player campaign")
	_text(box, "3 to 5 maps worth different points, one pool of supply each. Before every map both sides secretly commit supply, buy units and pick a deployment.", MUTED, 14, true)
	var war_save := GameSession.peek("war")
	if not war_save.is_empty():
		var saved_war := WarCampaign.from_dict(war_save["war"])
		var where := "in battle" if not war_save["battle"].is_empty() else ("finished" if saved_war.is_over() else "map %d of %d" % [saved_war.current + 1, saved_war.maps.size()])
		_button(box, "Continue two-player campaign: %s" % where, _continue.bind("war"), true)
	_button(box, "New two-player campaign", _show_war_setup)

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
	_text(box, "Play another computer directly, at home or over the internet, no server needed. The host picks the map above and plays the Allies. Both games check after every order that they still agree.", MUTED, 14, true)
	var password_row := HBoxContainer.new()
	password_row.add_theme_constant_override("separation", 8)
	box.add_child(password_row)
	_text(password_row, "Password", MUTED, 14)
	_password = LineEdit.new()
	_password.secret = true
	_password.text = _last_password
	_password.placeholder_text = "Agree one with your opponent; both type the same"
	_password.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	password_row.add_child(_password)
	var show_password := CheckBox.new()
	show_password.text = "Show"
	show_password.toggled.connect(func(on: bool) -> void: _password.secret = not on)
	password_row.add_child(show_password)
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
	_address.placeholder_text = "Host address, e.g. 192.168.1.20 or 203.0.113.7:24944"
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
	elif GameSession.war != null:
		_show_war()
	else:
		_show_campaign()


func _new_campaign() -> void:
	GameSession.war = null
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
	GameSession.war = null
	GameSession.start_battle(built[0], [SKIRMISH_MODES[mode][1], SKIRMISH_MODES[mode][2]], built[1])
	get_tree().change_scene_to_file(GameSession.BATTLE_SCENE)


# --- Online ---

func _host() -> void:
	var port := _port.text.to_int()
	_host_setup = _skirmish_setup()
	_host_setup["game_id"] = GameSession.new_game_id()
	_host_offer = {}
	if not await _open_game(port, 0):
		return
	_show_host_page(_map_choice.get_item_text(_map_choice.selected))


## Hosting: reach the internet (router and STUN), then listen on `port` as `team`. False if it didn't work
## (an error page is up) or the player cancelled meanwhile.
func _open_game(port: int, team: int) -> bool:
	if not _take_password():
		return false
	_show_net_page("Opening the game", "Asking your router to open port %d and looking up your internet address..." % port, "Cancel")
	var page := _page
	await Net.prepare_internet(port, true)
	if _page != page:
		return false
	var err := Net.host(port, team)
	if err != OK:
		_show_net_page("Can't host", "Couldn't open port %d (%s). Try another port." % [port, error_string(err)], "Back")
		return false
	return true


func _take_password() -> bool:
	var text := _password.text
	if text.strip_edges() == "":
		_password.placeholder_text = "Type a password first (agree it with your opponent)"
		_password.grab_focus()
		return false
	_last_password = text
	Net.password = text
	return true


## Waiting for the other player: where they can find us, and a way to let them through the NAT.
func _show_host_page(what: String) -> void:
	var box := _new_page(600)
	_title(box, "Waiting for the other player", 32)
	_text(box, what, UITheme.PAPER, 16, true)
	_text(box, "They choose Join game, type the same password, and one of these addresses:", UITheme.PAPER, 16, true)
	var port := _port.text.to_int()
	var lines := []
	if Net.internet_address != "":
		lines.append("Over the internet:  %s" % Net.internet_address)
	for address: String in Net.local_addresses():
		lines.append("On your network:  %s:%d" % [address, port])
	_text(box, "\n".join(lines) if not lines.is_empty() else "This computer's address, port %d" % port, Color.WHITE, 17, true)
	if Net.internet_address != "":
		_button(box, "Copy internet address", func() -> void: DisplayServer.clipboard_set(Net.internet_address))
	if Net.router_opened:
		_text(box, "Your router opened the port, so they should get straight in.", GOOD, 14, true)
	elif Net.internet_address != "":
		_text(box, "Your router didn't open the port by itself. If they can't get in, ask them for the internet address their game shows and paste it here:", MUTED, 14, true)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var theirs := LineEdit.new()
		theirs.placeholder_text = "Their internet address, e.g. 198.51.100.4:41234"
		theirs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(theirs)
		var status := _text(box, "", MUTED, 14, true)
		_button(row, "Let them in", func() -> void:
			if Net.let_in(theirs.text):
				status.text = "Opening the way to %s for a minute. They should get in now." % theirs.text.strip_edges()
			else:
				status.text = "That isn't an address like 198.51.100.4:41234.")
		_text(box, "If that doesn't work either, forward UDP port %d on your router to this computer, or both use a VPN such as Tailscale." % port, MUTED, 14, true)
	else:
		_text(box, "Couldn't find your internet address. Over the internet, forward UDP port %d on your router to this computer, or both use a VPN such as Tailscale." % port, MUTED, 14, true)
	_gap(box, 12)
	_button(box, "Cancel", func() -> void:
		Net.close()
		_show_main())


func _join() -> void:
	var text := _address.text.strip_edges()
	if text == "":
		_address.placeholder_text = "Type the host's address first"
		return
	if not _take_password():
		return
	var parts := Nat.split_address(text, Net.DEFAULT_PORT)
	var host: String = parts[0]
	var port: int = parts[1]
	var local_port := 0
	if not Nat.is_local(host):
		# Send from a port of our own choosing, and find out how the internet sees it, so the host can
		# open the way to it if their router won't let us in.
		local_port = randi_range(30000, 60000)
		_show_net_page("Connecting to %s:%d..." % [host, port], "Looking up your internet address...", "Cancel")
		var page := _page
		await Net.prepare_internet(local_port, false)
		if _page != page:
			return
	var err := Net.join(host, port, local_port)
	if err != OK:
		_show_net_page("Can't connect", error_string(err), "Back")
	elif local_port != 0 and Net.internet_address != "":
		var box := _new_page(600)
		_title(box, "Connecting to %s:%d..." % [host, port], 32)
		_text(box, "Waiting for the host. If you don't get in within a few seconds, send the host your internet address so they can let you in:", UITheme.PAPER, 16, true)
		_text(box, Net.internet_address, Color.WHITE, 17, true)
		var address := Net.internet_address
		_button(box, "Copy my internet address", func() -> void: DisplayServer.clipboard_set(address))
		_text(box, "Keeps trying for a minute and a half.", MUTED, 14, true)
		_gap(box, 12)
		_button(box, "Cancel", func() -> void:
			Net.close()
			_show_main())
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
	if Net.last_error != "":
		_show_net_page("Couldn't connect", Net.last_error, "Back")
	else:
		_show_net_page("Couldn't connect", "The host didn't answer. Check the address and port, and that the host is waiting. Over the internet, the host may need to forward the port or let you in with your internet address.", "Back")


## Both players build the same battle from the same setup.
func _start_online(setup: Dictionary) -> void:
	GameSession.war = null
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
	if not await _open_game(port, offer["team"]):
		return
	_host_offer = offer
	_show_host_page("Continuing %s, round %d, as %s." % [offer["title"], offer["round"], Battle.TEAM_NAMES[offer["team"]]])


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
	GameSession.war = null
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


# --- Two-player campaign ---

func _show_war_setup() -> void:
	var box := _new_page(560)
	_title(box, "Two-player campaign", 36)
	_text(box, ("Each side gets %d supply for the whole campaign. Every map is worth a different number of points (1 to 5). " +
			"Before each map both sides secretly commit between %d and %d supply, buy units with it and choose a deployment. " +
			"Supply committed to a map is gone, the rest is kept for later maps. Win a map to take its points; a draw splits them. " +
			"Most points at the end wins.") % [WarCampaign.SUPPLY, WarCampaign.MIN_SPEND, WarCampaign.MAX_SPEND], UITheme.PAPER, 15, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_text(row, "Maps", MUTED, 15)
	var count := OptionButton.new()
	for n: int in WarCampaign.MAP_COUNTS:
		count.add_item("%d maps" % n)
	count.selected = 1
	row.add_child(count)
	_text(row, "Germany", MUTED, 15)
	var opponent := OptionButton.new()
	opponent.add_item("Second player (hotseat)")
	opponent.add_item("AI")
	row.add_child(opponent)
	_gap(box, 8)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_button(buttons, "Start", func() -> void: _new_war(WarCampaign.MAP_COUNTS[count.selected], opponent.selected == 1), true)
	_button(buttons, "Back", _show_main)


func _new_war(map_count: int, vs_ai: bool) -> void:
	GameSession.campaign = null
	GameSession.battle = null
	GameSession.war = WarCampaign.create(map_count, randi() % 1000000 + 1, [false, vs_ai])
	GameSession.save_game()
	_show_war()


func _show_war() -> void:
	var war := GameSession.war
	# The AI writes its orders on its own, without seeing the other side's.
	if not war.is_over():
		for side in 2:
			if war.ai_sides[side] and not war.has_orders(side):
				war.set_orders(side, war.ai_orders(side))
	var box := _new_page(760)
	_title(box, "Two-player campaign", 36)
	var colors := [ALLIED, GERMAN]
	var score := HBoxContainer.new()
	score.add_theme_constant_override("separation", 30)
	box.add_child(score)
	for side in 2:
		_text(score, "%s%s: %d points, %d supply left" % [Battle.TEAM_NAMES[side], " (AI)" if war.ai_sides[side] else "",
				war.scores[side], war.supply[side]], colors[side], 17)

	_section(box, "Maps")
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 22)
	box.add_child(grid)
	for header in ["Map", "Size", "Points", "Supply spent", "Result"]:
		_text(grid, header, MUTED, 13)
	for i in war.maps.size():
		var m: Dictionary = war.maps[i]
		var now := i == war.current
		var color := UITheme.PAPER if now else (Color(1, 1, 1, 0.75) if not m["result"].is_empty() else MUTED)
		_text(grid, ("▶ " if now else "") + m["name"], color, 15)
		_text(grid, "%dx%d" % [m["size"], m["size"]], color, 15)
		_text(grid, str(m["points"]), color, 15)
		var result: Dictionary = m["result"]
		if result.is_empty():
			_text(grid, "", color, 15)
			_text(grid, "next" if now else "", color, 15)
		else:
			_text(grid, "%d / %d" % result["spent"], color, 15)
			var won: int = result["winner"]
			_text(grid, "Draw, %d each" % floori(m["points"] / 2.0) if won == Battle.DRAW else "%s win (+%d)" % [Battle.TEAM_NAMES[won], m["points"]],
					colors[won] if won != Battle.DRAW else color, 15)

	if war.is_over():
		var won := war.winner()
		_section(box, "The campaign is over")
		_text(box, "A draw." if won == Battle.DRAW else "%s win the campaign, %d to %d." % [Battle.TEAM_NAMES[won], war.scores[won], war.scores[1 - won]],
				colors[won] if won != Battle.DRAW else UITheme.PAPER, 20)
		_gap(box, 8)
		var end_buttons := HBoxContainer.new()
		end_buttons.add_theme_constant_override("separation", 10)
		box.add_child(end_buttons)
		_button(end_buttons, "New two-player campaign", _show_war_setup, true)
		_button(end_buttons, "Main menu", _show_main)
		return

	var m := war.current_map()
	_section(box, "Map %d of %d: %s, worth %d point%s" % [war.current + 1, war.maps.size(), m["name"], m["points"], "" if m["points"] == 1 else "s"])
	var left := 0
	for i in range(war.current + 1, war.maps.size()):
		left += war.maps[i]["points"]
	_text(box, "Still to come after this map: %d point%s over %d map%s." % [left, "" if left == 1 else "s", war.maps.size() - war.current - 1,
			"" if war.maps.size() - war.current - 1 == 1 else "s"], MUTED, 14)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	for side in 2:
		if war.has_orders(side):
			_text(buttons, "%s: orders sealed" % Battle.TEAM_NAMES[side], colors[side], 15)
		else:
			_button(buttons, "%s: give orders" % Battle.TEAM_NAMES[side], _show_orders.bind(side), true)
	_gap(box, 6)
	var fight_row := HBoxContainer.new()
	fight_row.add_theme_constant_override("separation", 10)
	box.add_child(fight_row)
	var fight := _button(fight_row, "Reveal orders and fight", _show_reveal, true)
	fight.disabled = not war.ready_to_fight()
	_button(fight_row, "Main menu", _show_main)
	if not war.ai_sides[1]:
		_text(box, "Hotseat: each player gives orders while the other looks away. Sealed orders stay hidden until both are in.", MUTED, 13, true)


## The orders page: buy units within this map's supply limits and choose a deployment.
func _show_orders(side: int) -> void:
	var war := GameSession.war
	_order_side = side
	_order_counts = {}
	_order_flank = "balanced"
	_order_posture = "offensive"
	_order_labels = {}
	var m := war.current_map()
	var limits := war.spend_limits(side)
	var box := _new_page(700)
	_title(box, "%s orders: %s" % [Battle.TEAM_NAMES[side], m["name"]], 32)
	_text(box, "Worth %d point%s. You have %d supply: commit between %d and %d to this map. Up to %d units." % [
			m["points"], "" if m["points"] == 1 else "s", war.supply[side], limits[0], limits[1], WarCampaign.MAX_UNITS], UITheme.PAPER, 15, true)

	_section(box, "Units")
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	for role: String in WarCampaign.UNIT_COSTS:
		_order_counts[role] = 0
		_text(grid, role, UITheme.PAPER, 15)
		_text(grid, "%d supply" % WarCampaign.UNIT_COSTS[role], MUTED, 14)
		_text(grid, WarCampaign.UNIT_NOTES[role], MUTED, 13)
		_button(grid, "-", _change_order.bind(role, -1))
		_order_labels[role] = _text(grid, "0", UITheme.PAPER, 16)
		_button(grid, "+", _change_order.bind(role, 1))

	_section(box, "Deployment")
	var flank_row := HBoxContainer.new()
	flank_row.add_theme_constant_override("separation", 10)
	box.add_child(flank_row)
	_text(flank_row, "Where", MUTED, 15)
	var flank := OptionButton.new()
	for item in ["Balanced: spread along your edge", "Left flank: massed on your left", "Right flank: massed on your right"]:
		flank.add_item(item)
	flank.item_selected.connect(func(i: int) -> void: _order_flank = WarCampaign.FLANKS[i])
	flank_row.add_child(flank)
	var posture_row := HBoxContainer.new()
	posture_row.add_theme_constant_override("separation", 10)
	box.add_child(posture_row)
	_text(posture_row, "How", MUTED, 15)
	var posture := OptionButton.new()
	posture.add_item("Offensive: deploy further forward, closer to the objectives")
	posture.add_item("Defensive: deploy back, behind sandbags, crouched")
	posture.item_selected.connect(func(i: int) -> void: _order_posture = WarCampaign.POSTURES[i])
	posture_row.add_child(posture)

	_gap(box, 8)
	_order_total = _text(box, "", UITheme.PAPER, 16)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_order_seal = _button(buttons, "Seal orders", _seal_orders, true)
	_button(buttons, "Back", _show_war)
	_update_orders()


func _change_order(role: String, step: int) -> void:
	_order_counts[role] = maxi(0, _order_counts[role] + step)
	_update_orders()


func _current_orders() -> Dictionary:
	var roster := []
	for role: String in _order_counts:
		for i in _order_counts[role]:
			roster.append(role)
	return {"roster": roster, "flank": _order_flank, "posture": _order_posture}


func _update_orders() -> void:
	for role: String in _order_counts:
		_order_labels[role].text = str(_order_counts[role])
	var orders := _current_orders()
	var err := GameSession.war.check_orders(_order_side, orders)
	_order_total.text = "Committed: %d supply, %d unit%s.%s" % [WarCampaign.cost_of(orders["roster"]), orders["roster"].size(),
			"" if orders["roster"].size() == 1 else "s", "" if err == "" else "  " + err]
	_order_total.add_theme_color_override("font_color", UITheme.PAPER if err == "" else BAD)
	_order_seal.disabled = err != ""


func _seal_orders() -> void:
	if GameSession.war.set_orders(_order_side, _current_orders()) != "":
		return
	GameSession.save_game()
	_show_war()


## Both sides' orders side by side, then the battle.
func _show_reveal() -> void:
	var war := GameSession.war
	var m := war.current_map()
	var box := _new_page(700)
	_title(box, "Orders for %s" % m["name"], 32)
	var colors := [ALLIED, GERMAN]
	for side in 2:
		var orders: Dictionary = m["orders"][side]
		_section(box, Battle.TEAM_NAMES[side])
		_text(box, "%d supply committed: %s" % [WarCampaign.cost_of(orders["roster"]), _force(orders["roster"])], colors[side], 15, true)
		_text(box, "Deployment: %s, %s." % [{"balanced": "balanced", "left": "left flank", "right": "right flank"}[orders["flank"]], orders["posture"]], UITheme.PAPER, 15)
	_gap(box, 8)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_button(buttons, "Fight", _start_war_battle, true)
	_button(buttons, "Back", _show_war)


func _start_war_battle() -> void:
	var war := GameSession.war
	var m := war.current_map()
	GameSession.campaign = null
	GameSession.start_battle(war.build_battle(), war.ai_sides, "Map %d of %d: %s (%d points)" % [war.current + 1, war.maps.size(), m["name"], m["points"]])
	GameSession.save_game()
	get_tree().change_scene_to_file(GameSession.BATTLE_SCENE)


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
