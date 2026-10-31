class_name GameSession
extends RefCounted
## What the battle scene should play, plus saving and loading. Static so it survives scene changes.
## There are two save slots: the campaign (with any battle in progress) and a skirmish battle.

const SLOTS := {"campaign": "user://campaign.sav", "skirmish": "user://skirmish.sav"}
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
## Ask the main menu to open the campaign screen.
static var show_campaign := false


static func start_battle(p_battle: Battle, p_ai_teams: Array, title: String) -> void:
	battle = p_battle
	ai_teams = p_ai_teams.duplicate()
	ai_states = [{}, {}]
	battle_title = title


static func current_slot() -> String:
	return "campaign" if campaign != null else "skirmish"


static func has_save(slot: String) -> bool:
	return FileAccess.file_exists(SLOTS[slot])


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
		"battle": battle.to_dict() if running else {},
		"ai_teams": ai_teams, "ai_states": ai_states, "title": battle_title,
	}
	var file := FileAccess.open(SLOTS[slot], FileAccess.WRITE)
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
	battle = Battle.from_dict(data["battle"]) if not data["battle"].is_empty() else null
	ai_teams = data["ai_teams"]
	ai_states = data["ai_states"]
	battle_title = data["title"]
	return true


## The raw contents of a slot, or {} if there is nothing usable.
static func peek(slot: String) -> Dictionary:
	if not has_save(slot):
		return {}
	var file := FileAccess.open(SLOTS[slot], FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = file.get_var()
	if not data is Dictionary or data.get("version") != SAVE_VERSION:
		return {}
	return data


static func delete_save(slot: String) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(SLOTS[slot])
