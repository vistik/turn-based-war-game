class_name GameSession
extends RefCounted
## What the battle scene should play, plus saving and loading. Static so it survives scene changes.
## There are two save slots: a skirmish battle, and the online two-player campaign (with any battle in progress),
## saved between maps and at every turn change both players agreed on. Each save of a battle in
## progress also holds its replay so far (`recording`); finished replays are files of their own (Replay).

const SLOTS := {"skirmish": "user://skirmish.sav", "online": "user://online.sav"}
const SAVE_VERSION := 2
const MENU_SCENE := "res://scenes/main_menu.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"

## The battle to play (or being played), or null.
static var battle: Battle
## Per team: whether the AI plays it, and the AI's saved memory.
static var ai_teams := [false, true]
## The side an outside agent plays through the agent link (MCP), or -1. Set after start_battle().
static var agent_team := -1
static var ai_states := [{}, {}]
## Per team: the game plan picked for the AI on the skirmish menu (a key of TacticalAI.STRATEGIES), or "" to
## let it pick. Only read when a battle starts.
static var ai_plans := ["", ""]
static var battle_title := ""
## The running two-player campaign (supply and maps), played online, or null.
static var war: WarCampaign
## Ask the main menu to open the two-player campaign screen.
static var show_campaign := false
## The online game being played: {"game_id", "title", "opponent", "hosted"}, or {} when offline. While the
## players give orders it also holds this side's sealed orders until both have sealed ("sealed": {"map",
## "orders", "salt"}), the other side's commitment ("their_hash": {"map", "hash"}), and the map whose orders
## were sent ("revealed").
static var online := {}
## The battle being played as recorded so far (ReplayRecorder), or null. Saved with the battle, so the replay
## of a continued game is complete.
static var recording: Replay
## The replay being watched on the battle screen (ReplayControls), or null when playing.
static var watching: Replay
## The folder the save slots live in: user:// unless the command line gives --save-dir=PATH (after "--"),
## so tests, and two copies of the game on one computer, keep separate saves.
static var save_dir := _save_dir_from_args()


static func start_battle(p_battle: Battle, p_ai_teams: Array, title: String) -> void:
	battle = p_battle
	ai_teams = p_ai_teams.duplicate()
	agent_team = -1
	ai_states = [{}, {}]
	ai_plans = ["", ""]
	battle_title = title
	recording = null
	watching = null
	online = {}


## A skirmish from a setup {"theatre": id (Normandy if left out), "map": "village" or "random", "size": side
## length, "style": a Theatre.map_styles() id ("" or left out: the seed picks), "seed": int}, or {"map": "scenario", "scenario": Scenario.to_data(), "seed": int}: the same setup
## always builds the same battle, which is how both online players start identical games. "quick_test": true
## sets both sides out in a firing line (BattleFactory.arrange_firing_line).
## Bigger maps bring bigger forces, need more points to win and allow more rounds. Returns [battle, title].
## The default deployment: each side spread out along its whole edge (see WarCampaign.deployment_tiles).
const SPREAD_OUT := {"flank": "wide", "posture": "normal"}


static func build_skirmish(setup: Dictionary) -> Array:
	var seed: int = setup["seed"]
	if setup["map"] == "scenario":
		# A scenario file's data travels in the setup, so an online opponent needs no copy of the file.
		var scenario := Scenario.from_data(setup["scenario"])
		return [scenario.build_battle(seed), scenario.title]
	var theatre := Theatres.get_theatre(setup.get("theatre", Theatres.DEFAULT))
	# Where each side deploys: {"flank", "posture"} as in the two-player campaign, or {} for the usual spawns.
	var deployments: Array = setup.get("deployment", [SPREAD_OUT, SPREAD_OUT])
	var layout: Dictionary
	var forces: Dictionary
	var title: String
	if setup["map"] == "village" and not theatre.village_layout().is_empty():
		layout = theatre.village_layout()
		forces = theatre.village_forces()
		title = theatre.village_title()
	else:
		var size: int = setup.get("size", 44)
		layout = theatre.generate_map(seed, Vector2i(size, size), setup.get("style", ""))
		# Small maps can lack room for fair objectives; the next seeds (the same on both online games) will do.
		var next_seed := seed
		while not layout.has("map") and next_seed < seed + 20:
			next_seed += 1
			layout = theatre.generate_map(next_seed, Vector2i(size, size), setup.get("style", ""))
		forces = theatre.skirmish_forces(size)
		title = "%s %dx%d #%d" % [style_title(theatre, layout.get("style", "")), size, size, seed % 10000]
	var options := {"theatre": theatre.id, "reinforcements": forces["waves"], "max_rounds": forces["max_rounds"], "vp_to_win": forces["vp_to_win"]}
	options.merge(theatre.battle_options())
	var battle := BattleFactory.create(layout, WarCampaign.deploy(layout, forces["rosters"], deployments), seed, options)
	if setup.get("quick_test", false):
		BattleFactory.arrange_firing_line(battle)
	return [battle, title]


## The menu name of one of a theatre's map styles ("Random map" if it has none by that id).
static func style_title(theatre: Theatre, style: String) -> String:
	for entry: Dictionary in theatre.map_styles():
		if entry["id"] == style:
			return entry["title"]
	return "Random map"


static func current_slot() -> String:
	return "skirmish"


static func slot_path(slot: String) -> String:
	return save_dir.path_join(SLOTS[slot].get_file())


static func _save_dir_from_args() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-dir="):
			return arg.trim_prefix("--save-dir=")
	return "user://"


static func has_save(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Saves the skirmish in progress. A skirmish with no battle left to continue just clears its slot. (The
## online two-player campaign is saved by save_online.)
static func save_game() -> void:
	if not online.is_empty():
		return
	var slot := current_slot()
	var running := battle != null and battle.winner == -1
	if not running:
		delete_save(slot)
		return
	var data := {
		"version": SAVE_VERSION,
		"battle": battle.to_dict(),
		"ai_teams": ai_teams, "agent_team": agent_team, "ai_states": ai_states, "title": battle_title,
		"replay": recording.to_dict() if running and recording != null else {},
	}
	_write(slot, data)


static func _write(slot: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("Could not save: %s" % FileAccess.get_open_error())
		return
	file.store_var(data)


## Loads a slot. Returns false if it is missing or can't be read.
static func load_game(slot: String) -> bool:
	var data := peek(slot)
	if data.is_empty():
		return false
	war = null
	online = {}
	battle = Battle.from_dict(data["battle"]) if not data["battle"].is_empty() else null
	ai_teams = data["ai_teams"]
	agent_team = data.get("agent_team", -1)
	ai_states = data["ai_states"]
	battle_title = data["title"]
	recording = Replay.from_dict(data["replay"]) if battle != null and not data.get("replay", {}).is_empty() else null
	watching = null
	return true


## The raw contents of a slot, or {} if there is nothing usable.
static func peek(slot: String) -> Dictionary:
	if not has_save(slot):
		return {}
	var file := FileAccess.open(slot_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = file.get_var()
	if not data is Dictionary or data.get("version") != SAVE_VERSION:
		return {}
	return data


static func delete_save(slot: String) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(slot_path(slot))


# --- Online games ---
# Both players save the online battle at every turn change their two games agreed on (Net.turn_agreed).
# To continue, either player hosts the saved game again and offers it (online_offer); the other joins and
# compares it with their own save (compare_online). The host's save is the one played on: when the saves
# differ the joining player is asked first, and once both have loaded it their checksums must match.

## A fresh id for a new online game; it goes out with the setup so both players file their saves under it.
static func new_game_id() -> String:
	return "%08x%08x" % [randi(), randi()]


## Starts (or resumes) an online two-player campaign between maps: `team` is the side played on this
## computer, `opponent` a hint for finding them again (the address used) and `hosted` whether this computer hosts.
static func start_online_war(p_war: WarCampaign, team: int, game_id: String, opponent: String, hosted: bool) -> void:
	war = p_war
	battle = null
	recording = null
	watching = null
	online = {"game_id": game_id, "title": "%s, %d map%s" % [p_war.theatre().title, p_war.maps.size(), "" if p_war.maps.size() == 1 else "s"],
			"opponent": opponent, "hosted": hosted, "team": team}


## Starts playing the campaign's current map online (both players build the same battle from the campaign).
static func start_online_battle(p_battle: Battle, title: String) -> void:
	var keep := online.duplicate()
	start_battle(p_battle, [false, false], "%s, online as %s" % [title, p_battle.team_name(int(keep.get("team", 0)))])
	online = keep
	online.erase("sealed")
	online.erase("their_hash")
	online.erase("revealed")


## Our orders for the current map are sealed: kept here with a secret salt, and only their hash goes to the
## other player (`net`: the Net autoload). They follow once both sides have sealed (process_war_messages).
static func seal_orders(net: Node, orders: Dictionary) -> String:
	var err := war.check_orders(int(online["team"]), orders)
	if err != "":
		return err
	var salt := "%08x%08x%08x" % [randi(), randi(), randi()]
	online["sealed"] = {"map": war.current, "orders": orders.duplicate(true), "salt": salt}
	net.send_war({"kind": "sealed", "map": war.current, "hash": WarCampaign.orders_hash(orders, salt)})
	process_war_messages(net)
	return ""


static func orders_sealed() -> bool:
	return war != null and online.get("sealed", {}).get("map", -1) == war.current


static func their_orders_sealed() -> bool:
	return war != null and online.get("their_hash", {}).get("map", -1) == war.current


## Handles the other player's campaign messages waiting in net.war_inbox for the current map (later maps'
## wait their turn): their sealed hash, then their orders, which must match it and the campaign's rules (or
## the games are out of step: net.report_desync). Sends ours once both have sealed. Saves once both sides'
## orders are in. Returns whether anything changed.
static func process_war_messages(net: Node) -> bool:
	if war == null or war.is_over() or online.is_empty():
		return false
	var team := int(online["team"])
	var changed := false
	var later: Array[Dictionary] = []
	for message: Dictionary in net.take_war_messages():
		var map_index := int(message.get("map", -1))
		if map_index > war.current:
			later.append(message)
			continue
		if map_index < war.current:
			continue
		match message.get("kind", ""):
			"sealed":
				online["their_hash"] = {"map": map_index, "hash": str(message.get("hash", ""))}
				changed = true
			"reveal":
				var orders: Variant = message.get("orders")
				var salt: Variant = message.get("salt")
				if not orders is Dictionary or not salt is String or not their_orders_sealed() \
						or WarCampaign.orders_hash(orders, salt) != online["their_hash"]["hash"]:
					net.report_desync("The other side's orders don't match what they sealed.")
					return false
				var err := war.set_orders(1 - team, orders)
				if err != "":
					net.report_desync("The other side's orders break the campaign's rules (%s)." % err)
					return false
				changed = true
	net.war_inbox.append_array(later)
	if orders_sealed() and their_orders_sealed() and online.get("revealed", -1) != war.current:
		var sealed: Dictionary = online["sealed"]
		online["revealed"] = war.current
		net.send_war({"kind": "reveal", "map": war.current, "orders": sealed["orders"], "salt": sealed["salt"]})
		war.set_orders(team, sealed["orders"])
		changed = true
	if changed and war.ready_to_fight():
		save_online(team)
	return changed


## The checksum both players' games compare: the campaign's, and the battle's if one is being fought.
static func online_checksum() -> String:
	var running := battle != null and battle.winner == -1
	return (war.checksum() if war != null else "") + ":" + (battle.checksum() if running else "")


## Saves the online campaign as it is now (with the battle being fought, if any), or clears its slot once the
## campaign is over.
static func save_online(team: int) -> void:
	if war == null or online.is_empty():
		return
	if war.is_over():
		end_online()
		return
	var running := battle != null and battle.winner == -1
	_write("online", {
		"version": SAVE_VERSION, "game_id": online["game_id"], "team": team, "title": online["title"],
		"opponent": online["opponent"], "hosted": online["hosted"], "war": war.to_dict(), "battle": battle.to_dict() if running else {},
		"checksum": online_checksum(), "map": war.current, "round": battle.round_number if running else 0,
		"turn_index": battle.turn_index if running else -1, "current_team": battle.current_team if running else 0,
		"saved_at": int(Time.get_unix_time_from_system()), "replay": recording.to_dict() if running and recording != null else {},
	})


## Both games agree on the state after a turn change (Net.turn_agreed): save it if we are still there.
static func on_turn_agreed(turn_index: int, checksum: String, team: int) -> void:
	if battle != null and battle.turn_index == turn_index and battle.checksum() == checksum:
		save_online(team)


## The online campaign is over: clear its save (but not a different game's).
static func end_online() -> void:
	if not online.is_empty() and peek("online").get("game_id") == online["game_id"]:
		delete_save("online")


## The saved online campaign as an offer for the other player: everything they need to continue it, battle
## state included. Returns {} if there is none or it doesn't reproduce its own checksum.
static func online_offer() -> Dictionary:
	var data := peek("online")
	if data.is_empty():
		return {}
	if _saved_checksum(data["war"], data["battle"]) != data["checksum"]:
		push_error("The online save doesn't load identically.")
		return {}
	var offer := {}
	for key in ["game_id", "team", "title", "war", "battle", "checksum", "map", "round", "turn_index", "current_team"]:
		offer[key] = data[key]
	return offer


static func _saved_checksum(war_data: Dictionary, battle_data: Dictionary) -> String:
	return WarCampaign.from_dict(war_data).checksum() + ":" + (Battle.from_dict(battle_data).checksum() if not battle_data.is_empty() else "")


## Where a saved online campaign stands, in words: "map 2 of 4, round 3" or "map 2 of 4, giving orders".
static func describe_online(data: Dictionary) -> String:
	var maps: int = data.get("war", {}).get("maps", []).size()
	var where := "map %d of %d" % [int(data.get("map", 0)) + 1, maps]
	if data.get("battle", {}).is_empty():
		return where + ", giving orders"
	return where + ", round %d, %s to move" % [int(data.get("round", 0)), side_name(data.get("battle", {}), clampi(int(data.get("current_team", 0)), 0, 1))]


## A side's name in a saved battle (Battle.to_dict()), whichever theatre it is from.
static func side_name(battle_data: Variant, team: int) -> String:
	var theatre_id: String = battle_data.get("theatre", Theatres.DEFAULT) if battle_data is Dictionary else Theatres.DEFAULT
	return Theatres.get_theatre(theatre_id).team_name(team)


## How the host's offer differs from our own online save, for the joining player to confirm: "" when the
## two are identical.
static func compare_online(offer: Dictionary) -> String:
	var own := peek("online")
	var theirs := "The host's save is at %s." % describe_online(offer)
	if own.is_empty():
		return "You have no saved online campaign. " + theirs
	if own["game_id"] != offer.get("game_id"):
		return "Your saved online campaign is a different one (%s). " % own["title"] + theirs
	if own["checksum"] == offer.get("checksum"):
		return ""
	return "Your save is at %s. " % describe_online(own) + theirs


## Loads an offered online campaign (and its battle, if one was being fought) to play as `team`. Returns false
## (and loads nothing) if the offer is malformed or doesn't reproduce the offered checksum.
static func resume_online(offer: Dictionary, team: int, opponent: String, hosted: bool) -> bool:
	for key in ["game_id", "war", "battle", "checksum"]:
		if not offer.has(key):
			return false
	if not offer["war"] is Dictionary or not offer["battle"] is Dictionary or not offer["checksum"] is String or offer["war"].is_empty():
		return false
	if _saved_checksum(offer["war"], offer["battle"]) != offer["checksum"]:
		return false
	var loaded_war := WarCampaign.from_dict(offer["war"])
	start_online_war(loaded_war, team, offer["game_id"], opponent, hosted)
	if not offer["battle"].is_empty():
		var m := loaded_war.current_map()
		start_online_battle(Battle.from_dict(offer["battle"]), "Map %d of %d: %s" % [loaded_war.current + 1, loaded_war.maps.size(), m["name"]])
		# Our own recording leads to exactly this state if our save is the one being continued.
		var own := peek("online")
		if own.get("game_id") == offer["game_id"] and own.get("checksum") == offer["checksum"] and not own.get("replay", {}).is_empty():
			recording = Replay.from_dict(own["replay"])
	return true
