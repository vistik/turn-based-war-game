class_name Campaign
extends RefCounted
## A five-mission Normandy campaign with one persistent Allied squad.
## Soldiers earn experience from missions and kills, rise in rank, get hurt and die for good.
## Supplies, earned by fighting, buy replacements. A lost mission can be tried again.
##
## A soldier record is {"id", "name", "role", "rank", "xp", "kills", "missions", "status", "out"}:
## status is "ready", "recovering" (sits out `out` more missions) or "dead".

const MISSIONS := [
	{
		"name": "Hedgerow Country",
		"briefing": "D+1. We push inland through the bocage. A thin German screen holds the church, the crossroads and the farm. Take them.",
		"map": {"seed": 1101, "size": Vector2i(36, 36)},
		"enemy": ["Officer", "Rifleman", "Rifleman", "SMG", "MG"],
		"vp_to_win": 8, "max_rounds": 14,
	},
	{
		"name": "The Village",
		"briefing": "D+3. A full German platoon is dug in around the village crossroads, with a mortar behind the church.",
		"map": "normandy",
		"enemy": ["Officer", "Rifleman", "Rifleman", "Medic", "SMG", "MG", "Sniper", "Mortar"],
		"vp_to_win": 10, "max_rounds": 16,
	},
	{
		"name": "Panzers in the Orchard",
		"briefing": "D+6. Recon spotted a Panzer IV among the orchards. Rifles won't scratch it: get the bazooka round its side or rear.",
		"map": {"seed": 3303, "size": Vector2i(40, 40)},
		"enemy": ["Officer", "Rifleman", "Rifleman", "SMG", "MG", "Tank"],
		"vp_to_win": 10, "max_rounds": 16,
	},
	{
		"name": "Counterattack",
		"briefing": "D+9. The Germans are coming back with armour. A Sherman has joined us. Hold the ground we took.",
		"map": {"seed": 4404, "size": Vector2i(40, 40)},
		"enemy": ["Officer", "Rifleman", "Rifleman", "SMG", "MG", "AT"],
		"enemy_reinforcements": [{"round": 3, "roster": ["Tank", "Rifleman", "Rifleman"]}, {"round": 6, "roster": ["Rifleman", "SMG"]}],
		"support": ["Tank"],
		"vp_to_win": 10, "max_rounds": 14,
	},
	{
		"name": "The Road to Caen",
		"briefing": "D+14. The last ridge before Caen. Everything they have left is waiting for us. This is it.",
		"map": {"seed": 5505, "size": Vector2i(46, 46)},
		"enemy": ["Officer", "Rifleman", "Rifleman", "Rifleman", "Medic", "SMG", "MG", "Sniper", "Mortar", "AT", "Tank"],
		"enemy_reinforcements": [{"round": 4, "roster": ["Tank", "Rifleman"]}],
		"support": ["Tank"],
		"vp_to_win": 12, "max_rounds": 18,
	},
]
const STARTING_ROLES := ["Officer", "Rifleman", "Rifleman", "AT", "Medic", "SMG", "MG", "Sniper"]
const RECRUIT_ROLES := ["Rifleman", "AT", "Medic", "SMG", "MG", "Sniper", "Mortar", "Officer"]
## Experience needed for corporal and sergeant.
const RANK_XP := [3, 7]
const RANK_TITLES := ["Private", "Corporal", "Sergeant"]
const SQUAD_SIZE := 8
const MAX_ROSTER := 12
const STARTING_SUPPLIES := 3
const RECRUIT_COST := 1
const WIN_SUPPLIES := 3
const LOSS_SUPPLIES := 1

var roster: Array[Dictionary] = []
var mission_index := 0
var supplies := STARTING_SUPPLIES
## The report from the last finished mission: {"mission", "won", "lines"}.
var last_report := {}
var _next_id := 0
var _rng := RandomNumberGenerator.new()


static func create(seed := 0) -> Campaign:
	var campaign := Campaign.new()
	if seed != 0:
		campaign._rng.seed = seed
	for role in STARTING_ROLES:
		campaign._add_soldier(role)
	return campaign


func is_won() -> bool:
	return mission_index >= MISSIONS.size()


## Out of soldiers and out of supplies to replace them.
func is_lost() -> bool:
	for soldier in roster:
		if soldier["status"] != "dead":
			return false
	return supplies < RECRUIT_COST


func current_mission() -> Dictionary:
	return MISSIONS[mini(mission_index, MISSIONS.size() - 1)]


## The soldiers who will deploy on the next mission: ready ones, officers first, up to SQUAD_SIZE.
func deployable() -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	for soldier in roster:
		if soldier["status"] == "ready":
			ready.append(soldier)
	ready.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["role"] == "Officer" and b["role"] != "Officer")
	return ready.slice(0, SQUAD_SIZE)


func living_soldiers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for soldier in roster:
		if soldier["status"] != "dead":
			result.append(soldier)
	return result


static func display_name(soldier: Dictionary) -> String:
	if soldier["role"] == "Officer":
		return "Lt. " + soldier["name"]
	return "%s %s" % [Unit.RANK_NAMES[soldier["rank"]], soldier["name"]]


## The battle for the current mission, with our deployable squad (plus any support) against the enemy.
func build_battle(seed: int) -> Battle:
	var mission := current_mission()
	var layout := NormandyScenario.layout() if mission["map"] is String else MapGenerator.generate(mission["map"]["seed"], mission["map"]["size"])
	var allies := []
	for soldier in deployable():
		allies.append({"role": soldier["role"], "name": display_name(soldier), "rank": soldier["rank"], "record_id": soldier["id"]})
	allies.append_array(mission.get("support", []))
	var waves := []
	for wave: Dictionary in mission.get("enemy_reinforcements", []):
		waves.append({"round": wave["round"], "team": 1, "roster": wave["roster"]})
	return BattleFactory.create(layout, [allies, mission["enemy"]], seed, {
		"vp_to_win": mission["vp_to_win"], "max_rounds": mission["max_rounds"], "reinforcements": waves,
	})


## Applies a finished battle to the roster: deaths, wounds, experience, promotions and supplies.
func complete_mission(battle: Battle) -> Dictionary:
	var mission := current_mission()
	var won := battle.winner == 0
	var lines: Array[String] = []
	var fought := {}
	for u in battle.units:
		if u.team != 0 or u.record_id < 0:
			continue
		var soldier := _soldier(u.record_id)
		fought[soldier["id"]] = true
		soldier["missions"] += 1
		soldier["kills"] += u.kills
		if not u.is_alive():
			soldier["status"] = "dead"
			lines.append("%s (%s) was killed in action." % [display_name(soldier), soldier["role"]])
			continue
		soldier["xp"] += 1 + u.kills
		var new_rank := _rank_for(soldier["xp"])
		if new_rank > soldier["rank"]:
			soldier["rank"] = new_rank
			lines.append("%s (%s) is promoted to %s." % [soldier["name"], soldier["role"], RANK_TITLES[new_rank]])
		if u.hp * 2 <= u.max_hp:
			soldier["status"] = "recovering"
			soldier["out"] = 1
			lines.append("%s is badly wounded and will sit out the next mission." % display_name(soldier))
	for soldier in roster:
		if soldier["status"] == "recovering" and not fought.has(soldier["id"]):
			soldier["out"] -= 1
			if soldier["out"] <= 0:
				soldier["status"] = "ready"
				lines.append("%s is back on duty." % display_name(soldier))
	supplies += WIN_SUPPLIES if won else LOSS_SUPPLIES
	lines.append("Supplies +%d." % (WIN_SUPPLIES if won else LOSS_SUPPLIES))
	if won:
		mission_index += 1
	last_report = {"mission": mission["name"], "won": won, "lines": lines}
	return last_report


func can_recruit() -> bool:
	return supplies >= RECRUIT_COST and living_soldiers().size() < MAX_ROSTER


func recruit(role: String) -> Dictionary:
	if not can_recruit():
		return {}
	supplies -= RECRUIT_COST
	return _add_soldier(role)


func to_dict() -> Dictionary:
	return {"roster": roster.duplicate(true), "mission_index": mission_index, "supplies": supplies,
			"last_report": last_report.duplicate(true), "next_id": _next_id, "rng_state": _rng.state, "rng_seed": _rng.seed}


static func from_dict(data: Dictionary) -> Campaign:
	var campaign := Campaign.new()
	campaign.roster.assign(data["roster"].duplicate(true))
	campaign.mission_index = data["mission_index"]
	campaign.supplies = data["supplies"]
	campaign.last_report = data["last_report"].duplicate(true)
	campaign._next_id = data["next_id"]
	campaign._rng.seed = data["rng_seed"]
	campaign._rng.state = data["rng_state"]
	return campaign


func _add_soldier(role: String) -> Dictionary:
	var used := {}
	for soldier in roster:
		used[soldier["name"]] = true
	var pool: Array = BattleFactory.SURNAMES[0]
	var surname: String = pool[_rng.randi_range(0, pool.size() - 1)]
	for i in pool.size():
		if not used.has(surname):
			break
		surname = pool[(pool.find(surname) + 1) % pool.size()]
	var soldier := {"id": _next_id, "name": surname, "role": role, "rank": 0, "xp": 0, "kills": 0, "missions": 0, "status": "ready", "out": 0}
	_next_id += 1
	roster.append(soldier)
	return soldier


func _soldier(id: int) -> Dictionary:
	for soldier in roster:
		if soldier["id"] == id:
			return soldier
	return {}


static func _rank_for(xp: int) -> int:
	var rank := 0
	for threshold: int in RANK_XP:
		if xp >= threshold:
			rank += 1
	return rank
