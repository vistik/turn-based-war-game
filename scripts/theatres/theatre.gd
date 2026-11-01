class_name Theatre
extends RefCounted
## A theatre of war: the two sides, their units and weapons, and the maps, campaigns and forces they fight
## with. The engine (Battle, the AI, the view) is shared by every theatre; everything that makes Normandy
## Normandy or Vietnam Vietnam lives in a Theatre subclass and is reached through Theatres.get_theatre(id).
##
## A faction (one per team) is a Dictionary:
## [codeblock]
## {"name": "Allies" (plural, as in "Allies win"), "adjective": "Allied", "color": Color (UI accent),
##  "look": {...} (uniform, see SoldierPainter), "surnames": [...], "vehicle_names": [...],
##  "roles": {role id: role definition, ...} (in display order),
##  "max_units": most units a side may field on a two-player campaign map (default 14),
##  "ai_wishes": [...], "ai_heavy": role, "fill_roles": [...] (two-player campaign AI shopping lists)}
## [/codeblock]
## A role definition is made by role() and holds everything Unit.create needs: stats, gear, the weapon spec
## (see Weapon.from_spec), traits and presentation keys. Role ids are what saves, scenarios and commands use.

## Default role fields; role() fills in whatever a definition leaves out.
const ROLE_DEFAULTS := {
	"name": "", "hp": 7, "aim": 65, "mobility": 7.0, "sight": 18.0,
	"grenades": 0, "smoke": 0, "medkits": 0, "mortar_rounds": 0, "mortar_smoke": 0,
	## A tank or other armoured vehicle, and the damage each side of its armour stops.
	"vehicle": false, "hull_armor": {},
	## Rallies and steadies those around it; its death shakes the whole side.
	"leader": false,
	## Indirect fire (mortar, artillery): see Theatre.indirect(). Empty for everyone else.
	"indirect": {},
	## How far the role likes to keep from the enemy (AI, scaled by Weapon.RANGE_SCALE like the range tables),
	## and whether it hangs back from objectives.
	"range": 6.0, "holds_back": false,
	## Grenade throwing range (a grenade launcher reaches further).
	"throw_range": 10.0,
	## Two-player campaign price and the line describing it.
	"cost": 3, "note": "",
	## Presentation: the badge icon, the kit drawn on the soldier, the vehicle model. Default to the role id.
	"icon": "", "kit": "", "model": "",
	## Put before the soldier's name, as "Lt. ".
	"name_prefix": "",
	## Further abilities, by name (see Unit.has_trait): "tunnels" (moves through its side's tunnels),
	## "traps" (lays traps: "traps" is how many it carries, "trap_kind" what kind, "punji" or "ied"),
	## "detonator" (sets off its side's IEDs it can see).
	"traits": [], "traps": 0, "trap_kind": "punji",
	## Body armour: damage it stops from every hit, until grenades shred it (Unit.armor).
	"body_armor": 0,
	## Chance (%) to spot each hidden mine, trap or IED it walks past, when better than the usual (EOD).
	"spot_chance": 0,
}
## Indirect fire defaults: a light mortar.
const INDIRECT_DEFAULTS := {
	"name": "mortar", "min": 5.0, "max": 22.0, "radius": 1.5, "damage": [3, 5],
	## Tiles off target per tile of distance, plus a flat amount.
	"scatter": 0.08, "scatter_flat": 0.0,
	## Shell kinds it can fire, in the order the UI offers them: "he", "smoke", "napalm".
	"kinds": ["he", "smoke"],
	## Must not have moved this turn (a mortar being set up), and who must see the target: "team" or "self".
	"still": true, "spotter": "team",
}

var id := ""
var title := ""
## One line for the menu.
var tagline := ""
## [team 0 faction, team 1 faction].
var factions: Array[Dictionary] = []


## A complete role definition from the fields given.
static func role(fields: Dictionary) -> Dictionary:
	var result := ROLE_DEFAULTS.duplicate(true)
	result.merge(fields, true)
	if not result["indirect"].is_empty():
		var spec: Dictionary = INDIRECT_DEFAULTS.duplicate(true)
		spec.merge(result["indirect"], true)
		result["indirect"] = spec
	return result


func faction(team: int) -> Dictionary:
	return factions[clampi(team, 0, factions.size() - 1)]


## "Allies", "Germany": the side as the game names it ("%s win").
func team_name(team: int) -> String:
	return faction(team)["name"]


func team_color(team: int) -> Color:
	return faction(team)["color"]


## The role's definition for this team, or {} if the team has no such role.
func role_def(team: int, role_id: String) -> Dictionary:
	return faction(team)["roles"].get(role_id, {})


func has_role(team: int, role_id: String) -> bool:
	return faction(team)["roles"].has(role_id)


## The team's role ids in display order.
func role_ids(team: int) -> Array:
	return faction(team)["roles"].keys()


## Every role id either side has, team 0's first.
func all_role_ids() -> Array:
	var result := role_ids(0).duplicate()
	for r in role_ids(1):
		if not result.has(r):
			result.append(r)
	return result


## How the role is called in the game ("Rifleman", "M60 gunner").
func role_name(team: int, role_id: String) -> String:
	var def := role_def(team, role_id)
	return def.get("name", role_id) if def.get("name", "") != "" else role_id


func cost(team: int, role_id: String) -> int:
	return role_def(team, role_id).get("cost", 0)


func cost_of(team: int, roster: Array) -> int:
	var total := 0
	for r: String in roster:
		total += cost(team, r)
	return total


## The team that lays (and so knows about) traps and IEDs: the one with a role that has the "traps" trait, or -1.
func trap_team() -> int:
	for team in factions.size():
		for r: String in role_ids(team):
			if role_def(team, r)["traits"].has("traps"):
				return team
	return -1


# --- Content: each theatre overrides these ---

## A random battlefield: {"map", "objectives", "spawns", "reinforcement_spawns"} (see BattleFactory).
func generate_map(_seed: int, _size: Vector2i) -> Dictionary:
	return {}


## Whether a generated layout is connected enough to play.
func is_playable(_layout: Dictionary) -> bool:
	return true


## The theatre's hand-made skirmish map, or {} if it has none.
func village_layout() -> Dictionary:
	return {}


## The name of the hand-made map in the menu.
func village_title() -> String:
	return ""


## The forces for a random-map skirmish of this side length: {"rosters": [a, b], "waves": [{"round", "team",
## "roster", "air"?}...], "max_rounds", "vp_to_win"} and optionally "kill_points" (see Battle.kill_points).
func skirmish_forces(_size: int) -> Dictionary:
	return {}


## Forces on the hand-made map (same shape as skirmish_forces).
func village_forces() -> Dictionary:
	return skirmish_forces(48)


## The single-player campaign: its name and missions (see Campaign).
func campaign_title() -> String:
	return ""


## A line about the campaign for its menu page.
func campaign_blurb() -> String:
	return ""


## [title, text] shown when the campaign is won.
func campaign_victory() -> Array:
	return ["Victory", "The campaign is won."]


func campaign_missions() -> Array:
	return []


func campaign_starting_roles() -> Array:
	return []


func campaign_recruit_roles() -> Array:
	return []


## Names for the maps of a two-player campaign.
func places() -> Array:
	return []


## Battle options every battle in this theatre gets (see BattleFactory.create), such as kill points.
func battle_options() -> Dictionary:
	return {}
