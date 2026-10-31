class_name GameSession
extends RefCounted
## What the battle scene should play, plus saving and loading. Static so it survives scene changes.
## There are two save slots: the campaign (with any battle in progress) and a skirmish battle, plus a third
## for the online game in progress, saved at every turn change both players agreed on. Each save of a battle in
## progress also holds its replay so far (`recording`); finished replays are files of their own (Replay).

const SLOTS := {"campaign": "user://campaign.sav", "skirmish": "user://skirmish.sav", "online": "user://online.sav", "war": "user://war.sav"}
const SAVE_VERSION := 1
const MENU_SCENE := "res://scenes/main_menu.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"

## The battle to play (or being played), or null.
static var battle: Battle
## Per team: whether the AI plays it, and the AI's saved memory.
static var ai_teams := [false, true]
static var ai_states := [{}, {}]
static var battle_title := ""
## The running campaign, or null in skirmish.
static var campaign: Campaign
## The running two-player campaign (supply and maps), or null.
static var war: WarCampaign
## Ask the main menu to open the campaign screen.
static var show_campaign := false
## The online game being played: {"game_id", "title", "opponent", "hosted"}, or {} when offline.
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
	ai_states = [{}, {}]
	battle_title = title
	recording = null
	watching = null


## A skirmish from a setup {"map": "village" or "random", "size": side length, "seed": int}, or
## {"map": "scenario", "scenario": Scenario.to_data(), "seed": int}: the same setup
## always builds the same battle, which is how both online players start identical games.
## Bigger maps bring bigger forces, need more points to win and allow more rounds. Returns [battle, title].
static func build_skirmish(setup: Dictionary) -> Array:
	var seed: int = setup["seed"]
	if setup["map"] == "scenario":
		# A scenario file's data travels in the setup, so an online opponent needs no copy of the file.
		var scenario := Scenario.from_data(setup["scenario"])
		return [scenario.build_battle(seed), scenario.title]
	# Where each side deploys: {"flank", "posture"} as in the two-player campaign, or {} for the usual spawns.
	var deployments: Array = setup.get("deployment", [{}, {}])
	if setup["map"] == "village":
		return [NormandyScenario.build(seed, deployments), "Normandy village"]
	var size: int = setup["size"]
	var roster := NormandyScenario.ROSTER.duplicate()
	var wave := NormandyScenario.REINFORCEMENTS.duplicate()
	var rounds := 20
	var points := 12
	if size >= 60:
		roster.append_array(["Rifleman", "Rifleman", "SMG", "AT"])
		wave.append("Rifleman")
		rounds = 24
		points = 16
	if size >= 80:
		roster.append_array(["Tank", "MG", "Medic"])
		wave.append_array(["Tank", "SMG"])
		rounds = 28
		points = 20
	var waves := []
	for team in Battle.TEAM_COUNT:
		waves.append({"round": NormandyScenario.REINFORCEMENT_ROUND, "team": team, "roster": wave})
	var layout := MapGenerator.generate(seed, Vector2i(size, size))
	var battle := BattleFactory.create(layout, WarCampaign.deploy(layout, [roster, roster], deployments), seed,
			{"reinforcements": waves, "max_rounds": rounds, "vp_to_win": points})
	WarCampaign.brace(battle, deployments)
	return [battle, "Random %dx%d map #%d" % [size, size, seed % 10000]]


static func current_slot() -> String:
	if war != null:
		return "war"
	return "campaign" if campaign != null else "skirmish"


static func slot_path(slot: String) -> String:
	return save_dir.path_join(SLOTS[slot].get_file())


static func _save_dir_from_args() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-dir="):
			return arg.trim_prefix("--save-dir=")
	return "user://"


static func has_save(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Saves the current slot: the campaign (if any) and the battle in progress (if any).
## A skirmish with no battle left to continue just clears its slot.
static func save_game() -> void:
	var slot := current_slot()
	var running := battle != null and battle.winner == -1
	if slot == "skirmish" and not running:
		delete_save(slot)
		return
	var data := {
		"version": SAVE_VERSION,
		"campaign": campaign.to_dict() if campaign != null else {},
		"war": war.to_dict() if war != null else {},
		"battle": battle.to_dict() if running else {},
		"ai_teams": ai_teams, "ai_states": ai_states, "title": battle_title,
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
	campaign = Campaign.from_dict(data["campaign"]) if not data["campaign"].is_empty() else null
	war = WarCampaign.from_dict(data["war"]) if not data.get("war", {}).is_empty() else null
	battle = Battle.from_dict(data["battle"]) if not data["battle"].is_empty() else null
	ai_teams = data["ai_teams"]
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


## Starts playing an online battle. `title` is the map's name, `team` the side played on this computer,
## `opponent` a hint for finding them again (the address used) and `hosted` whether this computer hosts.
static func start_online(p_battle: Battle, title: String, team: int, game_id: String, opponent: String, hosted: bool) -> void:
	campaign = null
	start_battle(p_battle, [false, false], "%s, online as %s" % [title, Battle.TEAM_NAMES[team]])
	online = {"game_id": game_id, "title": title, "opponent": opponent, "hosted": hosted}


## Saves the online battle as it is now, or clears its slot once the battle is over.
static func save_online(team: int) -> void:
	if battle == null or online.is_empty():
		return
	if battle.winner != -1:
		end_online()
		return
	_write("online", {
		"version": SAVE_VERSION, "game_id": online["game_id"], "team": team, "title": online["title"],
		"opponent": online["opponent"], "hosted": online["hosted"], "battle": battle.to_dict(),
		"checksum": battle.checksum(), "round": battle.round_number, "turn_index": battle.turn_index,
		"current_team": battle.current_team, "saved_at": int(Time.get_unix_time_from_system()),
		"replay": recording.to_dict() if recording != null else {},
	})


## Both games agree on the state after a turn change (Net.turn_agreed): save it if we are still there.
static func on_turn_agreed(turn_index: int, checksum: String, team: int) -> void:
	if battle != null and battle.turn_index == turn_index and battle.checksum() == checksum:
		save_online(team)


## The online battle is over: clear its save (but not a different game's).
static func end_online() -> void:
	if not online.is_empty() and peek("online").get("game_id") == online["game_id"]:
		delete_save("online")


## The saved online game as an offer for the other player: everything they need to continue it, battle
## state included. Returns {} if there is none or it doesn't reproduce its own checksum.
static func online_offer() -> Dictionary:
	var data := peek("online")
	if data.is_empty():
		return {}
	if Battle.from_dict(data["battle"]).checksum() != data["checksum"]:
		push_error("The online save doesn't load identically.")
		return {}
	var offer := {}
	for key in ["game_id", "team", "title", "battle", "checksum", "round", "turn_index", "current_team"]:
		offer[key] = data[key]
	return offer


## How the host's offer differs from our own online save, for the joining player to confirm: "" when the
## two are identical.
static func compare_online(offer: Dictionary) -> String:
	var own := peek("online")
	var theirs := "The host's save is from round %d, %s to move." % [int(offer.get("round", 0)), Battle.TEAM_NAMES[clampi(int(offer.get("current_team", 0)), 0, 1)]]
	if own.is_empty():
		return "You have no saved online game. " + theirs
	if own["game_id"] != offer.get("game_id"):
		return "Your saved online game is a different one (%s). " % own["title"] + theirs
	if own["checksum"] == offer.get("checksum"):
		return ""
	if own["turn_index"] == offer.get("turn_index"):
		return "Both saves are from round %d, but they differ." % own["round"]
	var when := "older" if own["turn_index"] < int(offer.get("turn_index", 0)) else "newer"
	return "Your save is %s: round %d, %s to move. " % [when, own["round"], Battle.TEAM_NAMES[own["current_team"]]] + theirs


## Loads an offered online battle to play as `team`. Returns false (and loads nothing) if the offer is
## malformed or its battle doesn't reproduce the offered checksum.
static func resume_online(offer: Dictionary, team: int, opponent: String, hosted: bool) -> bool:
	for key in ["game_id", "title", "battle", "checksum"]:
		if not offer.has(key):
			return false
	if not offer["battle"] is Dictionary or not offer["checksum"] is String:
		return false
	var loaded := Battle.from_dict(offer["battle"])
	if loaded.checksum() != offer["checksum"]:
		return false
	start_online(loaded, offer["title"], team, offer["game_id"], opponent, hosted)
	# Our own recording leads to exactly this state if our save is the one being continued.
	var own := peek("online")
	if own.get("game_id") == offer["game_id"] and own.get("checksum") == offer["checksum"] and not own.get("replay", {}).is_empty():
		recording = Replay.from_dict(own["replay"])
	return true
