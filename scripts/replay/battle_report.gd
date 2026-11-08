class_name BattleReport
extends RefCounted
## The after-action report of a battle: per side and per soldier, the orders given, the shots fired and what they
## did against the odds they were taken at, cover, damage, morale, movement and losses. Built by playing a replay
## through from its start state (the engine is deterministic, so it ends exactly as recorded), so it works on the
## game-over screen and on any saved replay alike. Raw numbers only, for the player to judge luck against play:
## luck is how many more hits a side's dice gave than the odds promised; play shows in the odds it fought at, its
## cover and its losses.

## What each command counts as in the orders breakdown, in the order the breakdown lists them.
const ORDER_KINDS := {
	"move": "Moves", "tunnel": "Moves",
	"shoot": "Shots",
	"suppress": "Suppressive fire", "suppress_area": "Suppressive fire",
	"overwatch": "Overwatch",
	"shoot_object": "Fire at objects", "fire_at": "Fire at objects",
	"grenade": "Grenades", "smoke": "Smoke grenades", "mortar": "Mortar fire",
	"medkit": "Medkits", "rally": "Rallies", "reload": "Reloads", "stance": "Stance changes", "hold": "Holds",
}
## Hit-chance bands for the odds breakdown: [label, highest chance in the band].
const BANDS := [["Long odds (under 35%)", 34], ["Fair odds (35-64%)", 64], ["Good odds (65%+)", 100]]
## The soldier table's columns (unit_rows()).
const UNIT_COLUMNS := ["Soldier", "Role", "Shots", "Hits", "Avg %", "vs exp.", "Damage", "Kills", "End"]

## One Dictionary per team; see _empty_side().
var sides: Array[Dictionary] = [_empty_side(), _empty_side()]
## Unit id -> per-soldier numbers; see _empty_unit(). finish() adds names, roles and how each ended.
var units := {}
var team_names := ["", ""]
## Who played each side ("You", "AI"...), from the replay.
var players := ["", ""]
var winner := -1
var rounds := 0
var victory_points := [0, 0]
## False when the recording began mid-battle, so the report covers only part of it.
var complete := true
## "" when the replay played out as recorded, else what went wrong (the report then stops there).
var error := ""

## Unit id -> the id of who last hurt it, to credit the kill.
var _last_hit_by := {}
## Unit ids pinned down right now, so each time a man goes down is counted once.
var _pinned := {}


## Plays the replay through and tallies it.
static func from_replay(replay: Replay) -> BattleReport:
	var report := BattleReport.new()
	report.players = replay.sides.duplicate()
	report.complete = replay.from_start
	if replay.snapshot.is_empty():
		report.error = "The replay is empty."
		return report
	var battle := replay.build()
	if not battle.started:
		report.tally(battle, {}, battle.start())
	report.team_names = [battle.team_name(0), battle.team_name(1)]
	for i in replay.commands.size():
		var command: Dictionary = replay.commands[i]
		var team := _command_team(battle, command)
		var events := battle.execute(command)
		if events.is_empty():
			report.error = "Order %d of %d isn't possible any more." % [i + 1, replay.commands.size()]
			break
		report.tally(battle, command, events, team)
	report.finish(battle)
	return report


## Adds one command and the events it caused. `team` is the side that gave it (-1 for none).
func tally(battle: Battle, command: Dictionary, events: Array, team := -1) -> void:
	var cmd: String = command.get("cmd", "")
	if team >= 0 and cmd != "" and cmd != "end_turn":
		var side := sides[team]
		side["orders"] += 1
		var kind: String = ORDER_KINDS.get(cmd, "Other")
		side["order_kinds"][kind] = side["order_kinds"].get(kind, 0) + 1
	for e: Dictionary in events:
		match e["type"]:
			"shot":
				_tally_shot(battle, e)
			"damage":
				_tally_damage(battle, e)
			"death":
				_tally_death(battle, e)
			"move":
				var mover := battle.get_unit(e["unit"])
				if mover != null:
					var steps: int = e["path"].size() - 1
					sides[mover.team]["tiles_moved"] += steps
					_unit(mover)["tiles_moved"] += steps
			"suppression":
				if e["state"] != "pinned":
					_pinned.erase(e["unit"])
				elif not _pinned.has(e["unit"]):
					_pinned[e["unit"]] = true
					var pinned := battle.get_unit(e["unit"])
					if pinned != null:
						sides[pinned.team]["pinned"] += 1
			"status":
				var who := battle.get_unit(e["unit"])
				if who != null and e["text"] == "Panicked!":
					sides[who.team]["panicked"] += 1
			"heal":
				var healed := battle.get_unit(e["unit"])
				if healed != null:
					sides[healed.team]["healed"] += int(e["amount"])
			"objective":
				if e["owner"] == 0 or e["owner"] == 1:
					sides[e["owner"]]["captures"] += 1


## Notes how the battle ended and who each soldier was.
func finish(battle: Battle) -> void:
	winner = battle.winner
	rounds = battle.round_number
	victory_points = battle.victory_points.duplicate()
	for u in battle.units:
		var stats := _unit(u)
		stats["name"] = u.name
		stats["role"] = u.role
		stats["alive"] = u.is_alive()
		stats["hp"] = u.hp
		stats["max_hp"] = u.max_hp


func _tally_shot(battle: Battle, e: Dictionary) -> void:
	var result: String = e["result"]
	if result == "suppressing":
		return
	var shooter := battle.get_unit(e["shooter"])
	if shooter == null:
		return
	var side := sides[shooter.team]
	var chance := int(e["chance"])
	var hit := chance / 100.0
	var landed := result == "hit" or result == "crit"
	for stats: Dictionary in [side, _unit(shooter)]:
		stats["shots"] += 1
		stats["chance_sum"] += float(chance)
		stats["expected_hits"] += hit
		if landed:
			stats["hits"] += 1
		if result == "crit":
			stats["crits"] += 1
	side["expected_crits"] += hit * float(e.get("crit_chance", 0)) / 100.0
	match result:
		"graze":
			side["grazes"] += 1
		"miss":
			side["misses"] += 1
	var band: Dictionary = side["bands"][_band(chance)]
	band["shots"] += 1
	band["expected"] += hit
	if landed:
		band["hits"] += 1
	if e.get("reaction", false):
		side["reaction_shots"] += 1
		if landed:
			side["reaction_hits"] += 1
	elif e.has("cover"):
		# Overwatch fires at men on the move, where cover doesn't count, so only aimed shots tell it.
		side["aimed"] += 1
		match int(e["cover"]):
			Cover.FULL:
				side["at_full"] += 1
			Cover.HALF:
				side["at_half"] += 1
		if e.get("flanked", false):
			side["flanking"] += 1
			if result == "crit":
				side["flank_crits"] += 1


func _tally_damage(battle: Battle, e: Dictionary) -> void:
	var target := battle.get_unit(e["unit"])
	if target == null:
		return
	var amount := int(e["amount"])
	sides[target.team]["damage_taken"] += amount
	_unit(target)["damage_taken"] += amount
	var attacker := battle.get_unit(e.get("by", -1))
	if attacker == null:
		sides[target.team]["damage_other"] += amount
		return
	_last_hit_by[target.id] = attacker.id
	if attacker.team == target.team:
		sides[attacker.team]["friendly_damage"] += amount
	else:
		sides[attacker.team]["damage_dealt"] += amount
		_unit(attacker)["damage_dealt"] += amount


func _tally_death(battle: Battle, e: Dictionary) -> void:
	var dead := battle.get_unit(e["unit"])
	if dead == null:
		return
	sides[dead.team]["losses"] += 1
	var killer := battle.get_unit(_last_hit_by.get(dead.id, -1))
	if killer != null and killer.team != dead.team:
		sides[killer.team]["kills"] += 1
		_unit(killer)["kills"] += 1


func _unit(u: Unit) -> Dictionary:
	if not units.has(u.id):
		units[u.id] = _empty_unit(u.team)
	return units[u.id]


static func _band(chance: int) -> int:
	for i in BANDS.size():
		if chance <= BANDS[i][1]:
			return i
	return BANDS.size() - 1


# --- Reading it ---

func avg_chance(team: int) -> float:
	return _avg(sides[team])


func hit_rate(team: int) -> float:
	var side := sides[team]
	return 100.0 * side["hits"] / side["shots"] if side["shots"] > 0 else 0.0


## Share of hits that were crits, in percent.
func crit_rate(team: int) -> float:
	var side := sides[team]
	return 100.0 * side["crits"] / side["hits"] if side["hits"] > 0 else 0.0


## Hits beyond what the odds promised (negative: fewer).
func luck(team: int) -> float:
	return sides[team]["hits"] - sides[team]["expected_hits"]


## Crits beyond what the odds promised.
func crit_luck(team: int) -> float:
	return sides[team]["crits"] - sides[team]["expected_crits"]


## The side table: [label, side 0 value, side 1 value, tooltip] rows, and section headings as [heading].
func rows() -> Array:
	var result := []
	result.append(["Result"])
	result.append(_row("Victory points", func(t: int) -> String: return str(victory_points[t]), ""))
	result.append(_row("Objectives taken", func(t: int) -> String: return str(sides[t]["captures"]),
			"Times the side took an objective, from the enemy or from nobody"))
	result.append(["Orders"])
	result.append(_row("Orders given", func(t: int) -> String: return str(sides[t]["orders"]),
			"Every order: moves, shots, overwatch, grenades, reloads..."))
	var kinds: Array[String] = []
	for kind: String in ORDER_KINDS.values() + ["Other"]:
		if not kinds.has(kind) and (sides[0]["order_kinds"].has(kind) or sides[1]["order_kinds"].has(kind)):
			kinds.append(kind)
	for kind in kinds:
		result.append(_row("   " + kind, func(t: int) -> String: return str(sides[t]["order_kinds"].get(kind, 0)), ""))
	result.append(["Shooting"])
	result.append(_row("Shots taken", func(t: int) -> String: return str(sides[t]["shots"]),
			"Aimed shots at soldiers and vehicles, overwatch included (suppressive fire isn't aimed)"))
	result.append(_row("Avg hit chance", func(t: int) -> String: return _pct(avg_chance(t), sides[t]["shots"]),
			"The odds the side fought at: cover, flanking, range and height decide it"))
	result.append(_row("Hits", func(t: int) -> String: return "%d (%s)" % [sides[t]["hits"], _pct(hit_rate(t), sides[t]["shots"])],
			"Hits and crits, and the share of shots that hit"))
	result.append(_row("Crits", func(t: int) -> String: return "%d (%s of hits)" % [sides[t]["crits"], _pct(crit_rate(t), sides[t]["hits"])], ""))
	result.append(_row("Grazes", func(t: int) -> String: return str(sides[t]["grazes"]), "Shots that only just caught the target, for half damage"))
	result.append(_row("Misses", func(t: int) -> String: return str(sides[t]["misses"]), ""))
	result.append(_row("Overwatch shots", func(t: int) -> String: return "%d, %d hit" % [sides[t]["reaction_shots"], sides[t]["reaction_hits"]], ""))
	result.append(["By the odds"])
	for i in BANDS.size():
		result.append(_row(BANDS[i][0], func(t: int) -> String: return _band_text(sides[t]["bands"][i]),
				"Shots taken at these odds: how many hit, and how many the odds promised"))
	result.append(["Luck"])
	result.append(_row("Expected hits", func(t: int) -> String: return "%.1f" % sides[t]["expected_hits"],
			"What the odds promised: the hit chances of every shot added up"))
	result.append(_row("Hits vs expected", func(t: int) -> String: return "%+.1f" % luck(t) if sides[t]["shots"] > 0 else "-",
			"Hits minus expected hits: above zero the dice gave more than the odds promised"))
	result.append(_row("Expected crits", func(t: int) -> String: return "%.1f" % sides[t]["expected_crits"],
			"Each shot's hit chance times its crit chance, added up"))
	result.append(_row("Crits vs expected", func(t: int) -> String: return "%+.1f" % crit_luck(t) if sides[t]["shots"] > 0 else "-", ""))
	result.append(["Cover"])
	result.append(_row("Shots at full cover", func(t: int) -> String: return _share(sides[t]["at_full"], sides[t]["aimed"]),
			"Aimed shots (not overwatch) at a target behind full cover"))
	result.append(_row("Shots at half cover", func(t: int) -> String: return _share(sides[t]["at_half"], sides[t]["aimed"]), ""))
	result.append(_row("Flanking shots", func(t: int) -> String: return _share(sides[t]["flanking"], sides[t]["aimed"]),
			"Aimed shots at a target with no cover from the shooter: easier to hit, more crits"))
	result.append(_row("Crits on the flank", func(t: int) -> String: return str(sides[t]["flank_crits"]), ""))
	result.append(_row("Own men flanked", func(t: int) -> String: return _share(sides[1 - t]["flanking"], sides[1 - t]["aimed"]),
			"Of the aimed shots the enemy took at this side, how many caught a man with no cover"))
	result.append(["Damage"])
	result.append(_row("Damage dealt", func(t: int) -> String: return str(sides[t]["damage_dealt"]),
			"Health the side took off the enemy: shots, grenades, shells, backblast"))
	result.append(_row("Kills", func(t: int) -> String: return str(sides[t]["kills"]), ""))
	result.append(_row("Damage taken", func(t: int) -> String: return str(sides[t]["damage_taken"]), "Health lost to every cause"))
	result.append(_row("   from fire, mines, collapses", func(t: int) -> String: return str(sides[t]["damage_other"]),
			"Damage nobody dealt directly"))
	result.append(_row("Friendly fire", func(t: int) -> String: return str(sides[t]["friendly_damage"]),
			"Health the side took off its own men"))
	result.append(_row("Healed", func(t: int) -> String: return str(sides[t]["healed"]), "Health given back with medkits"))
	result.append(_row("Losses", func(t: int) -> String: return str(sides[t]["losses"]), ""))
	result.append(["Morale and movement"])
	result.append(_row("Times pinned down", func(t: int) -> String: return str(sides[t]["pinned"]), ""))
	result.append(_row("Panics", func(t: int) -> String: return str(sides[t]["panicked"]), ""))
	result.append(_row("Tiles moved", func(t: int) -> String: return str(sides[t]["tiles_moved"]), ""))
	return result


## A side's soldier table, one row per soldier in UNIT_COLUMNS order, in the order they joined the battle.
func unit_rows(team: int) -> Array:
	var result := []
	var ids: Array = units.keys()
	ids.sort()
	for id: int in ids:
		var u: Dictionary = units[id]
		if u["team"] != team or u["name"] == "":
			continue
		var fate := "Killed" if not u["alive"] else "%d/%d hp" % [u["hp"], u["max_hp"]]
		result.append([u["name"], u["role"], str(u["shots"]), str(u["hits"]), _pct(_avg(u), u["shots"]),
				"%+.1f" % (u["hits"] - u["expected_hits"]) if u["shots"] > 0 else "-",
				str(u["damage_dealt"]), str(u["kills"]), fate])
	return result


func _row(label: String, value: Callable, tip: String) -> Array:
	return [label, value.call(0), value.call(1), tip]


static func _avg(stats: Dictionary) -> float:
	return stats["chance_sum"] / stats["shots"] if stats["shots"] > 0 else 0.0


## "8: 2 hit, 2.1 exp."
static func _band_text(band: Dictionary) -> String:
	if band["shots"] == 0:
		return "-"
	return "%d: %d hit, %.1f exp." % [band["shots"], band["hits"], band["expected"]]


## "62%", or "-" when there was nothing to count.
static func _pct(value: float, count: int) -> String:
	return "%d%%" % roundi(value) if count > 0 else "-"


## "4 (25%)".
static func _share(part: int, whole: int) -> String:
	return "%d (%s)" % [part, _pct(100.0 * part / whole if whole > 0 else 0.0, whole)]


static func _empty_side() -> Dictionary:
	var bands := []
	for i in BANDS.size():
		bands.append({"shots": 0, "hits": 0, "expected": 0.0})
	return {"orders": 0, "order_kinds": {}, "shots": 0, "reaction_shots": 0, "reaction_hits": 0, "hits": 0,
			"crits": 0, "grazes": 0, "misses": 0, "aimed": 0, "at_full": 0, "at_half": 0, "flanking": 0,
			"flank_crits": 0, "chance_sum": 0.0, "expected_hits": 0.0, "expected_crits": 0.0, "bands": bands,
			"damage_dealt": 0, "damage_taken": 0, "damage_other": 0, "friendly_damage": 0, "healed": 0,
			"kills": 0, "losses": 0, "pinned": 0, "panicked": 0, "tiles_moved": 0, "captures": 0}


static func _empty_unit(team: int) -> Dictionary:
	return {"team": team, "name": "", "role": "", "alive": true, "hp": 0, "max_hp": 0, "shots": 0, "hits": 0,
			"crits": 0, "chance_sum": 0.0, "expected_hits": 0.0, "damage_dealt": 0, "damage_taken": 0, "kills": 0,
			"tiles_moved": 0}


static func _command_team(battle: Battle, command: Dictionary) -> int:
	if command.get("cmd", "") == "end_turn":
		return battle.current_team
	var u := battle.get_unit(command.get("unit", -1))
	return u.team if u != null else -1
