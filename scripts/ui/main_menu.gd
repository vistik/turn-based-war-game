extends Control
## Main menu and campaign screens. Starts campaign missions and skirmishes by handing a Battle to
## GameSession and switching to the battle scene.

const MUTED := UITheme.PAPER_DIM
const BAD := Color("ff7a6a")
const GOOD := Color("8fe08a")
## [label, size] of random maps. They are generated fresh each game; bigger ones bring bigger forces.
const RANDOM_MAPS := [["standard", 44], ["large", 64], ["huge", 84]]
## [label, flank, posture] for a skirmish side's deployment; "" flank keeps the map's usual spawns.
const DEPLOYMENTS := [
	["Usual spawns", "", ""],
	["Balanced, offensive", "balanced", "offensive"], ["Balanced, defensive", "balanced", "defensive"],
	["Left flank, offensive", "left", "offensive"], ["Left flank, defensive", "left", "defensive"],
	["Right flank, offensive", "right", "offensive"], ["Right flank, defensive", "right", "defensive"],
	["Random", "random", "random"],
]
## [label, team 0 is AI, team 1 is AI, side an agent plays over the agent link (-1: none)]
const SKIRMISH_MODES := [["Play vs AI", false, true, -1], ["Hotseat", false, false, -1], ["Watch AI vs AI", true, true, -1],
		["Agent vs AI", false, true, 0], ["Me vs agent", false, false, 1]]
## "%s" is team 0's name.
const SKIRMISH_MODE_HINTS := [
	"You play the %s against the AI.",
	"Two players on this computer take turns; the screen hides each side's view from the other.",
	"Sit back and watch the AI fight itself.",
	"An AI agent (such as Claude Code) plays the %s against the AI through the agent link; the battle screen shows how to connect it. See docs/MCP.md.",
	"You play the %s against an AI agent connected through the agent link.",
]

## The theatre new games are started in (Theatres), picked on the first page and kept while the game runs.
static var _theatre_id := Theatres.DEFAULT

var _page: Control
var _map_choice: OptionButton
## [label, setup "map", size] for the built-in maps in the map choice; scenario files are listed after them.
var _builtin_maps: Array = []
var _scenario_paths: Array[String] = []
var _recruit_choice: OptionButton
## Per side, the skirmish deployment picked (an index into DEPLOYMENTS), kept while the game runs.
var _deploy_choices: Array[OptionButton] = []
static var _last_deployments := [0, 0]
## The map, skirmish mode and online port picked last, kept while the game runs.
static var _last_map := 0
static var _last_mode := 0
static var _last_port := Net.DEFAULT_PORT
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

## The first page: what's saved to carry on with, then one button per way to play. Each opens its own page
## with that mode's options.
func _show_main() -> void:
	Music.menu_theatre = _theatre_id
	var box := _new_page(480)
	var theatre := _theatre()
	_title(box, theatre.title, 48)
	_text(box, theatre.tagline, MUTED, 16, true)
	# Which war: every page below starts its games in the theatre picked here.
	var theatres := HBoxContainer.new()
	theatres.add_theme_constant_override("separation", 6)
	box.add_child(theatres)
	for other in Theatres.all():
		var pick := _button(theatres, other.title, func() -> void:
			_theatre_id = other.id
			_last_map = 0
			_show_main())
		pick.toggle_mode = true
		pick.button_pressed = other.id == _theatre_id
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gap(box, 12)
	var saves := _saved_games()
	for entry: Array in saves:
		_button(box, entry[0], entry[1], true)
	if not saves.is_empty():
		_gap(box, 8)
	_menu_button(box, "Campaign", "%d missions with one squad" % theatre.campaign_missions().size(), _show_campaign_menu)
	_menu_button(box, "Two-player campaign", "Spend supply over 3 to 5 maps", _show_war_setup)
	_menu_button(box, "Skirmish", "One battle against the AI, a friend or an agent", _show_skirmish)
	_menu_button(box, "Online", "Play another computer directly", _show_online)
	_gap(box, 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for spec: Array in [["Replays", _show_replays], ["Map editor", func() -> void: get_tree().change_scene_to_file("res://scenes/editor.tscn")],
			["Settings", _show_settings], ["Quit", get_tree().quit]]:
		_button(row, spec[0], spec[1]).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var music_label := func() -> String: return "Music: %s" % ("on" if GameSettings.music_volume > 0 else "off")
	var music: Button
	music = _button(box, music_label.call(), func() -> void:
		GameSettings.toggle_music()
		music.text = music_label.call())


## [label, action] for each saved game that can be continued.
func _saved_games() -> Array:
	var result := []
	var campaign_save := GameSession.peek("campaign")
	if not campaign_save.is_empty():
		var saved := Campaign.from_dict(campaign_save["campaign"])
		var total := saved.missions().size()
		result.append(["Continue %s: %s" % [saved.theatre().campaign_title(), "in battle" if not campaign_save["battle"].is_empty() else "mission %d of %d" % [mini(saved.mission_index + 1, total), total]], _continue.bind("campaign")])
	var war_save := GameSession.peek("war")
	if not war_save.is_empty():
		var saved_war := WarCampaign.from_dict(war_save["war"])
		var where := "in battle" if not war_save["battle"].is_empty() else ("finished" if saved_war.is_over() else "map %d of %d" % [saved_war.current + 1, saved_war.maps.size()])
		result.append(["Continue two-player campaign (%s): %s" % [saved_war.theatre().title, where], _continue.bind("war")])
	var skirmish_save := GameSession.peek("skirmish")
	if not skirmish_save.is_empty():
		result.append(["Continue skirmish: %s" % skirmish_save["title"], _continue.bind("skirmish")])
	var online_save := GameSession.peek("online")
	if not online_save.is_empty():
		result.append(["Continue online game: %s, round %d" % [online_save["title"], online_save["round"]], _show_online])
	return result


## A large menu button with a one-line description under its name.
func _menu_button(parent: Control, text: String, hint: String, action: Callable) -> void:
	var button := _button(parent, "", action)
	button.custom_minimum_size = Vector2(0, 58)
	var labels := VBoxContainer.new()
	labels.set_anchors_preset(Control.PRESET_FULL_RECT)
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	labels.add_theme_constant_override("separation", -2)
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(labels)
	for line: Array in [[text, UITheme.PAPER, 20], [hint, MUTED, 13]]:
		var label := _text(labels, line[0], line[1], line[2])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _show_campaign_menu() -> void:
	var box := _new_page(480)
	_title(box, _theatre().campaign_title(), 40)
	_text(box, _theatre().campaign_blurb(), MUTED, 15, true)
	_gap(box, 8)
	var campaign_save := GameSession.peek("campaign")
	if not campaign_save.is_empty():
		var saved := Campaign.from_dict(campaign_save["campaign"])
		_button(box, "Continue " + saved.theatre().campaign_title(), _continue.bind("campaign"), true)
	_button(box, "New campaign" + (" (replaces the saved one)" if not campaign_save.is_empty() else ""), _new_campaign, campaign_save.is_empty())
	_gap(box, 8)
	_button(box, "Back", _show_main)


## The map list: the theatre's hand-made map (if it has one) and random maps, then its scenarios on disk.
func _add_map_choice(parent: Control) -> void:
	var theatre := _theatre()
	_map_choice = OptionButton.new()
	_builtin_maps.clear()
	if not theatre.village_layout().is_empty():
		_builtin_maps.append(["%s (48x48, %s)" % [theatre.village_title(), _force_size(theatre.village_forces())], "village", 48])
	for spec: Array in RANDOM_MAPS:
		_builtin_maps.append(["Random map, %s (%dx%d, %s)" % [spec[0], spec[1], spec[1], _force_size(theatre.skirmish_forces(spec[1]))], "random", spec[1]])
	for map_spec: Array in _builtin_maps:
		_map_choice.add_item(map_spec[0])
	_scenario_paths.clear()
	for entry in Scenario.list_files():
		if entry["theatre"] != theatre.id:
			continue
		_map_choice.add_item("Scenario: %s" % entry["title"])
		_scenario_paths.append(entry["path"])
	_map_choice.selected = clampi(_last_map, 0, _map_choice.item_count - 1)
	_map_choice.item_selected.connect(func(index: int) -> void: _last_map = index)
	_map_choice.custom_minimum_size = Vector2(0, 40)
	_map_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_map_choice)


## A label and a control side by side.
func _field(parent: Control, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	_text(row, label, MUTED, 15).custom_minimum_size = Vector2(90, 0)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


func _show_skirmish() -> void:
	var box := _new_page(520)
	_title(box, "Skirmish", 40)
	var map_row := HBoxContainer.new()
	_add_map_choice(map_row)
	_field(box, "Map", map_row)
	var opponent := OptionButton.new()
	for mode: Array in SKIRMISH_MODES:
		opponent.add_item(mode[0])
	opponent.selected = _last_mode
	opponent.item_selected.connect(func(index: int) -> void: _last_mode = index)
	_field(box, "Mode", opponent)
	var mode_hint := _text(box, "", MUTED, 13, true)
	var describe := func(index: int) -> void:
		var hint: String = SKIRMISH_MODE_HINTS[index]
		mode_hint.text = hint % _theatre().team_name(0) if hint.contains("%s") else hint
	opponent.item_selected.connect(describe)
	describe.call(opponent.selected)

	# Deployments are folded away: most battles use the usual spawns.
	var deploy_toggle := CheckButton.new()
	deploy_toggle.text = "Choose deployments"
	deploy_toggle.button_pressed = _last_deployments != [0, 0]
	box.add_child(deploy_toggle)
	var deploy_box := VBoxContainer.new()
	deploy_box.add_theme_constant_override("separation", 6)
	box.add_child(deploy_box)
	_deploy_choices.clear()
	for side in 2:
		var choice := OptionButton.new()
		for entry: Array in DEPLOYMENTS:
			choice.add_item(entry[0])
		choice.selected = _last_deployments[side]
		choice.item_selected.connect(func(index: int) -> void: _last_deployments[side] = index)
		_field(deploy_box, _theatre().team_name(side), choice)
		_deploy_choices.append(choice)
	_text(deploy_box, "Balanced along your edge or massed on a flank (seen from your own edge); offensive deploys further forward, defensive further back behind sandbags. Scenarios place their own units.", MUTED, 13, true)
	deploy_box.visible = deploy_toggle.button_pressed
	deploy_toggle.toggled.connect(func(on: bool) -> void:
		deploy_box.visible = on
		if not on:
			for side in 2:
				_deploy_choices[side].selected = 0
				_last_deployments[side] = 0)
	_gap(box, 8)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_button(buttons, "Start", func() -> void: _start_skirmish(opponent.selected), true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(buttons, "Back", _show_main)


func _show_online() -> void:
	var box := _new_page(520)
	_title(box, "Online", 40)
	_text(box, "Play another computer directly, at home or over the internet, no server needed. Both games check after every order that they still agree.", MUTED, 14, true)
	_password = LineEdit.new()
	_password.secret = true
	_password.text = _last_password
	_password.placeholder_text = "Agree one with your opponent"
	var password_row := HBoxContainer.new()
	password_row.add_theme_constant_override("separation", 8)
	password_row.add_child(_password)
	_password.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var show_password := CheckBox.new()
	show_password.text = "Show"
	show_password.toggled.connect(func(on: bool) -> void: _password.secret = not on)
	password_row.add_child(show_password)
	_field(box, "Password", password_row)
	_port = LineEdit.new()
	_port.text = str(_last_port)
	_port.text_changed.connect(func(text: String) -> void: _last_port = text.to_int() if text.is_valid_int() else Net.DEFAULT_PORT)

	var online_save := GameSession.peek("online")
	if not online_save.is_empty():
		_section(box, "Your saved game")
		_text(box, "%s, round %d, as %s, against %s. Host it again and your opponent joins as usual, or join them if they host it." % [
				online_save["title"], online_save["round"], GameSession.side_name(online_save["battle"], online_save["team"]), online_save["opponent"]], MUTED, 14, true)
		_button(box, "Continue: host the saved game", _host_resume, true)

	_section(box, "Host a new game")
	_text(box, "You play the %s on the map you pick (%s; switch on the first page)." % [_theatre().team_name(0), _theatre().title], MUTED, 14, true)
	var map_row := HBoxContainer.new()
	_add_map_choice(map_row)
	_field(box, "Map", map_row)
	_button(box, "Host game", _host, online_save.is_empty())

	_section(box, "Join a game")
	_address = LineEdit.new()
	_address.placeholder_text = "The address the host's game shows"
	if not online_save.is_empty() and not online_save["hosted"]:
		_address.text = online_save["opponent"]
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	join_row.add_child(_address)
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(join_row, "Join", _join)
	_field(box, "Address", join_row)

	_gap(box, 8)
	_field(box, "Port", _port)
	_text(box, "UDP port to host on (%d unless you need another). Joining uses the port in the address, or this one." % Net.DEFAULT_PORT, MUTED, 12, true)
	_gap(box, 8)
	_button(box, "Back", _show_main)


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
	GameSession.campaign = Campaign.create(randi(), _theatre_id)
	GameSession.battle = null
	GameSession.save_game()
	_show_campaign()


func _skirmish_setup() -> Dictionary:
	var index := _map_choice.selected - _builtin_maps.size()
	if index >= 0:
		var scenario := Scenario.load_file(_scenario_paths[index])
		if scenario != null:
			return {"map": "scenario", "scenario": scenario.to_data(), "seed": randi() % 1000000000 + 1}
		push_warning(Scenario.last_error)
	var spec: Array = _builtin_maps[maxi(0, _map_choice.selected) if index < 0 else 0]
	return {"theatre": _theatre_id, "map": spec[1], "size": spec[2], "seed": randi() % 1000000000 + 1, "deployment": _chosen_deployments()}


## The two sides' deployments for GameSession.build_skirmish, with "Random" settled now so both online games
## build the same battle.
func _chosen_deployments() -> Array:
	var result := []
	for side in 2:
		var entry: Array = DEPLOYMENTS[_deploy_choices[side].selected if side < _deploy_choices.size() else 0]
		if entry[1] == "random":
			entry = DEPLOYMENTS[randi_range(1, DEPLOYMENTS.size() - 2)]
		result.append({} if entry[1] == "" else {"flank": entry[1], "posture": entry[2]})
	return result


func _start_skirmish(mode: int) -> void:
	var built := GameSession.build_skirmish(_skirmish_setup())
	GameSession.campaign = null
	GameSession.war = null
	GameSession.start_battle(built[0], [SKIRMISH_MODES[mode][1], SKIRMISH_MODES[mode][2]], built[1])
	GameSession.agent_team = SKIRMISH_MODES[mode][3]
	get_tree().change_scene_to_file(GameSession.BATTLE_SCENE)


# --- Online ---

func _host() -> void:
	var port := _port.text.to_int()
	_host_setup = _skirmish_setup()
	_host_setup["game_id"] = GameSession.new_game_id()
	_host_offer = {}
	if not await _open_game(port, 0):
		return
	_show_host_page(_map_choice.get_item_text(_map_choice.selected), port)


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
func _show_host_page(what: String, port: int) -> void:
	var box := _new_page(600)
	_title(box, "Waiting for the other player", 32)
	_text(box, what, UITheme.PAPER, 16, true)
	_text(box, "They choose Join game, type the same password, and one of these addresses:", UITheme.PAPER, 16, true)
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
		_show_online())


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
		# The host's internet address is our own: it's behind the same router (or on this computer), and
		# most routers won't pass a connection to their own address back inside.
		if host == Net.internet_address.get_slice(":", 0):
			Net.close()
			_show_net_page("The host is on your network",
					"%s is this network's own internet address, so the host is behind the same router as you (or on this computer). Join with the address the host's page shows under \"On your network\" instead, e.g. 192.168.1.20:%d." % [host, port], "Back")
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
			_show_online())
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
		_show_online())


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
	_show_host_page("Continuing %s, round %d, as %s." % [offer["title"], offer["round"], GameSession.side_name(offer["battle"], offer["team"])], port)


## Joiner: the host wants to continue a saved game. Matching saves go straight on; otherwise ask first.
func _on_resume_offered(offer: Dictionary) -> void:
	var difference := GameSession.compare_online(offer)
	if difference == "" or not GameSession.has_save("online"):
		_accept_resume(offer)
		return
	var box := _new_page(560)
	_title(box, "Continue the host's saved game?", 32)
	_text(box, "%s, playing as %s.\n\n%s\n\nContinuing replaces your saved online game with the host's." % [
			offer.get("title", "?"), GameSession.side_name(offer.get("battle", {}), Net.local_team), difference], Color.WHITE, 16, true)
	_gap(box, 12)
	_button(box, "Continue from the host's save", _accept_resume.bind(offer), true)
	_button(box, "Leave", func() -> void:
		Net.decline_resume()
		_show_online())


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


# --- Replays ---

## Finished battles (Replay files, newest first) and the battles in progress in the save slots.
func _show_replays() -> void:
	var box := _new_page(700)
	_title(box, "Replays", 40)
	_text(box, "Every battle is recorded. Watch one again with the fog of war of either side, or the whole map. The last %d finished battles are kept." % Replay.KEEP, MUTED, 14, true)
	var in_progress := []
	for slot in ["campaign", "skirmish", "war", "online"]:
		var data := GameSession.peek(slot)
		if not data.get("replay", {}).is_empty():
			in_progress.append(data["replay"])
	if not in_progress.is_empty():
		_section(box, "In progress")
		for data: Dictionary in in_progress:
			_replay_row(box, data, "")
	_section(box, "Finished battles")
	var finished := Replay.list()
	if finished.is_empty():
		_text(box, "None yet.", MUTED, 14)
	for data in finished:
		_replay_row(box, data, data["path"])
	_gap(box, 12)
	_button(box, "Back", _show_main, true)


## One replay: title, date, sides and result, with Watch (and Delete for a file).
func _replay_row(parent: Control, data: Dictionary, path: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	_text(info, data.get("title", "?"), Color.WHITE, 16)
	var sides: Array = data.get("sides", ["", ""])
	var result: String = data.get("result", "")
	var theatre := Theatres.get_theatre(data.get("theatre", Theatres.DEFAULT))
	var details := "%s   %s (%s) vs %s (%s)   %s" % [Replay.date_text(data.get("date", 0)), theatre.team_name(0), sides[0], theatre.team_name(1), sides[1],
			result if result != "" else "in progress, %d orders" % data.get("orders", data.get("commands", []).size())]
	var winner: int = data.get("winner", -1)
	_text(info, details, theatre.team_color(winner) if winner == 0 or winner == 1 else MUTED, 13)
	_button(row, "Watch", _watch_replay.bind(data, path))
	if path != "":
		_button(row, "Delete", func() -> void:
			Replay.delete_file(path)
			_show_replays())


func _watch_replay(data: Dictionary, path: String) -> void:
	var replay := Replay.load_file(path) if path != "" else Replay.from_dict(data)
	var problem := "The replay can't be read." if replay == null else replay.verify()
	if problem != "":
		var box := _new_page(560)
		_title(box, "Can't show this replay", 32)
		_text(box, problem + " The game's rules have probably changed since it was recorded.", Color.WHITE, 16, true)
		_gap(box, 12)
		_button(box, "Back", _show_replays, true)
		return
	ReplayControls.return_to_campaign = false
	GameSession.watching = replay
	get_tree().change_scene_to_file(GameSession.BATTLE_SCENE)


# --- Campaign screen ---

func _show_campaign() -> void:
	var campaign := GameSession.campaign
	var theatre := campaign.theatre()
	var ours := theatre.team_color(0)
	var theirs := theatre.team_color(1)
	var box := _new_page(860)
	var total := campaign.missions().size()
	if campaign.is_won():
		var victory := theatre.campaign_victory()
		_title(box, victory[0], 40)
		_text(box, victory[1], GOOD, 18, true)
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
		_text(box, "Enemy: %s" % _force(mission["enemy"], 1, theatre), theirs, 14, true)
		if mission.has("enemy_reinforcements"):
			for wave: Dictionary in mission["enemy_reinforcements"]:
				_text(box, "   Round %d reinforcements: %s" % [wave["round"], _force(wave["roster"], 1, theatre)], theirs, 14, true)
		if mission.has("support"):
			_text(box, "Support: %s" % _force(mission["support"], 0, theatre), ours, 14)
		_text(box, "Win: first to %d points from the objectives, or wipe them out. %d rounds." % [mission["vp_to_win"] * int(theatre.battle_options().get("points_scale", 1)), mission["max_rounds"]], MUTED, 14, true)

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
		_text(grid, campaign.display_name(soldier), ours if not dead else color, 14)
		_text(grid, campaign.role_name(soldier["role"]), color, 14)
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
		for role: String in campaign.recruit_roles():
			_recruit_choice.add_item(campaign.role_name(role))
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
	GameSession.campaign.recruit(GameSession.campaign.recruit_roles()[_recruit_choice.selected])
	GameSession.save_game()
	_show_campaign()


func _start_mission() -> void:
	var campaign := GameSession.campaign
	var battle := campaign.build_battle(randi())
	GameSession.start_battle(battle, [false, true], "Mission %d: %s" % [campaign.mission_index + 1, campaign.current_mission()["name"]])
	GameSession.save_game()
	get_tree().change_scene_to_file(GameSession.BATTLE_SCENE)


## "Officer, 2 Rifleman, Tank" from a team's list of roles.
static func _force(roles: Array, team: int, theatre: Theatre) -> String:
	var counts := {}
	for entry: Variant in roles:
		var role: String = entry["role"] if entry is Dictionary else entry
		counts[role] = counts.get(role, 0) + 1
	var parts := PackedStringArray()
	for role: String in counts:
		var role_name := theatre.role_name(team, role)
		parts.append(role_name if counts[role] == 1 else "%d %s" % [counts[role], role_name])
	return ", ".join(parts)


## "8 a side" or "8 vs 12" for a skirmish's starting forces.
static func _force_size(forces: Dictionary) -> String:
	var sizes: Array = forces["rosters"].map(func(r: Array) -> int: return r.size())
	return "%d a side" % sizes[0] if sizes[0] == sizes[1] else "%d vs %d" % sizes


func _theatre() -> Theatre:
	return Theatres.get_theatre(_theatre_id)


# --- Two-player campaign ---

func _show_war_setup() -> void:
	var box := _new_page(560)
	_title(box, "Two-player campaign", 36)
	_text(box, "%s: %s against %s." % [_theatre().title, _theatre().team_name(0), _theatre().team_name(1)], MUTED, 15, true)
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
	_text(row, _theatre().team_name(1), MUTED, 15)
	var opponent := OptionButton.new()
	opponent.add_item("Second player (hotseat)")
	opponent.add_item("AI")
	row.add_child(opponent)
	_gap(box, 8)
	var saved := not GameSession.peek("war").is_empty()
	if saved:
		var saved_war := WarCampaign.from_dict(GameSession.peek("war")["war"])
		_button(box, "Continue the saved campaign (%s)" % saved_war.theatre().title, _continue.bind("war"), true)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_button(buttons, "Start a new one" + (" (replaces the saved one)" if saved else ""), func() -> void: _new_war(WarCampaign.MAP_COUNTS[count.selected], opponent.selected == 1), not saved)
	_button(buttons, "Back", _show_main)


func _new_war(map_count: int, vs_ai: bool) -> void:
	GameSession.campaign = null
	GameSession.battle = null
	GameSession.war = WarCampaign.create(map_count, randi() % 1000000 + 1, [false, vs_ai], _theatre_id)
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
	var colors := [war.theatre().team_color(0), war.theatre().team_color(1)]
	var score := HBoxContainer.new()
	score.add_theme_constant_override("separation", 30)
	box.add_child(score)
	for side in 2:
		_text(score, "%s%s: %d points, %d supply left" % [war.theatre().team_name(side), " (AI)" if war.ai_sides[side] else "",
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
			_text(grid, "Draw, %d each" % floori(m["points"] / 2.0) if won == Battle.DRAW else "%s win (+%d)" % [war.theatre().team_name(won), m["points"]],
					colors[won] if won != Battle.DRAW else color, 15)

	if war.is_over():
		var won := war.winner()
		_section(box, "The campaign is over")
		_text(box, "A draw." if won == Battle.DRAW else "%s win the campaign, %d to %d." % [war.theatre().team_name(won), war.scores[won], war.scores[1 - won]],
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
			_text(buttons, "%s: orders sealed" % war.theatre().team_name(side), colors[side], 15)
		else:
			_button(buttons, "%s: give orders" % war.theatre().team_name(side), _show_orders.bind(side), true)
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
	_title(box, "%s orders: %s" % [war.theatre().team_name(side), m["name"]], 32)
	_text(box, "Worth %d point%s. You have %d supply: commit between %d and %d to this map. Up to %d units." % [
			m["points"], "" if m["points"] == 1 else "s", war.supply[side], limits[0], limits[1], war.max_units(side)], UITheme.PAPER, 15, true)

	_section(box, "Units")
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	var shop: Array = war.theatre().role_ids(side)
	# Cheapest first.
	shop.sort_custom(func(a: String, b: String) -> bool: return war.theatre().cost(side, a) < war.theatre().cost(side, b))
	for role: String in shop:
		var def := war.theatre().role_def(side, role)
		_order_counts[role] = 0
		_text(grid, war.theatre().role_name(side, role), UITheme.PAPER, 15)
		_text(grid, "%d supply" % def["cost"], MUTED, 14)
		_text(grid, def["note"], MUTED, 13)
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
	_order_total.text = "Committed: %d supply, %d unit%s.%s" % [GameSession.war.cost_of(_order_side, orders["roster"]), orders["roster"].size(),
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
	var colors := [war.theatre().team_color(0), war.theatre().team_color(1)]
	for side in 2:
		var orders: Dictionary = m["orders"][side]
		_section(box, war.theatre().team_name(side))
		_text(box, "%d supply committed: %s" % [war.cost_of(side, orders["roster"]), _force(orders["roster"], side, war.theatre())], colors[side], 15, true)
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
