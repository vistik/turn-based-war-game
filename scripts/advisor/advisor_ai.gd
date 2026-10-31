class_name AdvisorAI
extends TacticalAI
## The tactical AI working for a human player: it suggests a move instead of making it.
## Same planning as the opponent AI, with its own memory, and it plays fair (only what the team sees).
## suggest() returns the command plus a short explanation built from the AI's own scoring.

## Names for what gives cover, by object or edge kind.
const COVER_NAMES := {
	"rock": "the rocks", "tree": "the tree", "crate": "the crates", "sandbags": "the sandbags", "hay": "the hay bales",
	"pew": "the pews", "wreck": "the wreck", "wall": "the wall", "hedge": "the hedge", "window": "the window",
	"fence": "the fence", "stone": "the low wall", "crater": "the crater", "tank": "the tank",
}


func _init(p_battle: Battle, p_team: int) -> void:
	super(p_battle, p_team)
	# The opponent AI guesses where the enemy is from their real starting positions. An advisor may be
	# created mid-battle, when that would give enemy positions away, so it guesses from the mirrored map:
	# the enemy started opposite our own side.
	var sum := Vector2.ZERO
	var count := 0
	for u in battle.alive_units(team):
		sum += Vector2(battle.map.width - 1 - u.pos.x, u.pos.y)
		count += 1
	_objective = sum / maxi(1, count) if count > 0 else Vector2(battle.map.width, battle.map.height) * 0.5


## The AI's suggestion for its team's next move, or for one unit when `only` is given.
## Returns {"command": Dictionary for Battle.execute, "unit": id or -1, "kind": String, "text": one-line
## explanation, "reasons": Array[String], "score": float, "target": id or -1, "tile": Vector2i or null}
## or {"error": String} when there's nothing to suggest.
func suggest(only: Unit = null) -> Dictionary:
	if battle.winner != -1:
		return {"error": "The battle is over"}
	if battle.current_team != team:
		return {"error": "Not your turn"}
	if only != null:
		var err := battle.can_act(only)
		if err == "" and only.team != team:
			err = "Not your unit"
		if err != "":
			return {"error": err}
	# decide() also updates the AI's memory of the enemy and its patience.
	var command := decide()
	var seen := _seen_enemies()
	var u: Unit = only if only != null else battle.get_unit(command.get("unit", -1))
	if u == null:
		return {"command": {"cmd": "end_turn"}, "unit": -1, "kind": "end_turn", "text": "Nothing useful left to do: end the turn.",
				"reasons": [], "score": 0.0, "target": -1, "tile": null}
	var plan := _best_plan(u, seen)
	if plan.is_empty():
		return {"error": "%s has nothing useful to do" % u.name}
	command = _command(plan)
	var result := {"command": command, "unit": u.id, "kind": plan["kind"], "score": snappedf(plan["value"], 0.1),
			"target": plan["target"].id if plan["target"] != null else -1,
			"tile": plan["tile"] if command.has("tile") else null}
	var reasons := _reasons(u, plan, seen)
	result["text"] = _headline(u, plan, seen) + (": " + ", ".join(reasons) if not reasons.is_empty() else "")
	result["reasons"] = reasons
	return result


# --- Explanations ---

func _headline(u: Unit, plan: Dictionary, seen: Array[Unit]) -> String:
	var target: Unit = plan["target"]
	match plan["kind"]:
		"move":
			var tile: Vector2i = plan["tile"]
			var spot := _cover_name(tile) if not u.vehicle else ""
			for objective in battle.objectives:
				if (Vector2(tile) + Vector2(0.5, 0.5)).distance_to(objective["center"]) <= objective["radius"]:
					spot = "the %s" % objective["name"].to_lower() if spot == "" else spot + " at the %s" % objective["name"].to_lower()
					break
			var verb := "Dash" if battle.actions_for_cost(u, battle.reachable(u)[tile]["cost"]) > 1 else "Move"
			return "%s %s to %s" % [verb, u.name, spot if spot != "" else "(%d, %d)" % [tile.x, tile.y]]
		"shoot":
			return "%s: shoot %s" % [u.name, target.name]
		"medkit":
			return "%s: treat %s" % [u.name, "himself" if target == u else target.name]
		"grenade":
			return "%s: grenade at (%d, %d)" % [u.name, plan["tile"].x, plan["tile"].y]
		"mortar":
			return "%s: mortar strike at (%d, %d)" % [u.name, plan["tile"].x, plan["tile"].y]
		"pivot":
			return "%s: turn to face %s" % [u.name, _compass(plan["tile"])]
		"set_up":
			return "%s: set up the machine gun" % u.name
	return "%s: %s" % [u.name, plan["kind"].capitalize().to_lower()]


func _reasons(u: Unit, plan: Dictionary, seen: Array[Unit]) -> Array[String]:
	var reasons: Array[String] = []
	var target: Unit = plan["target"]
	match plan["kind"]:
		"move":
			reasons = _move_reasons(u, plan["tile"], seen)
		"shoot":
			var odds := battle.shot_odds(u, target)
			reasons.append("%d%% hit" % odds["hit"])
			if target.vehicle:
				reasons.append("hits its %s armour" % CombatRules.armor_side(target, u.pos))
			elif odds["flanked"]:
				reasons.append("flanked (%d%% crit)" % odds["crit"])
			elif odds["cover"] != Cover.NONE:
				reasons.append("target in %s cover" % Cover.NAMES[odds["cover"]].to_lower())
			var outcome := _expected_damage(u, u.pos, target, target.pos)
			if outcome[1] >= 0.05:
				reasons.append("%d%% kill chance" % roundi(outcome[1] * 100.0))
			if target.overwatch:
				reasons.append("breaks his overwatch")
		"overwatch":
			var near := 0
			for e in seen:
				if Vector2(u.pos).distance_to(Vector2(e.pos)) <= u.sight + 3.0:
					near += 1
			reasons.append("%s in range if they move" % _enemies(near) if near > 0 else "watches the approach")
		"hunker":
			var threats := _cover_counts(u.pos, seen)
			reasons.append("doubles cover against %s in sight" % _enemies(threats[0] + threats[1]) if not seen.is_empty() else "stays hidden")
		"reload":
			reasons.append("%d/%d rounds left" % [u.ammo, u.weapon.clip_size])
		"rally":
			var count := 0
			for ally in battle.alive_units(team):
				if ally.suppression > 0 and Vector2(ally.pos).distance_to(Vector2(u.pos)) <= CombatRules.OFFICER_RADIUS:
					count += 1
			reasons.append("steadies %d suppressed soldier%s" % [count, "" if count == 1 else "s"])
		"medkit":
			reasons.append("HP %d/%d%s" % [target.hp, target.max_hp, ", treats the wound" if target.is_wounded() else ""])
		"grenade", "mortar":
			var names := PackedStringArray()
			var radius := CombatRules.GRENADE_RADIUS if plan["kind"] == "grenade" else CombatRules.MORTAR_RADIUS
			for e in seen:
				if Vector2(e.pos).distance_to(Vector2(plan["tile"])) <= radius:
					names.append(e.name)
			if not names.is_empty():
				reasons.append("catches " + ", ".join(names))
			if plan["kind"] == "mortar":
				reasons.append("lands next turn")
		"set_up":
			reasons.append("ready to fire next action" if u.actions >= 2 else "ready for next turn")
		"pivot":
			reasons.append("front armour toward the threat")
	return reasons


func _move_reasons(u: Unit, tile: Vector2i, seen: Array[Unit]) -> Array[String]:
	var reasons: Array[String] = []
	if u.vehicle:
		var front := 0
		for e in seen:
			if CombatRules.armor_side(u, e.pos) == "front":
				front += 1
		if front > 0:
			reasons.append("front armour toward %s" % _enemies(front))
	else:
		if seen.is_empty():
			var best := Cover.NONE
			for d: Vector2i in TacticalMap.DIRS4:
				best = maxi(best, battle.map.cover_toward(tile, d))
			reasons.append("%s cover" % Cover.NAMES[best].to_lower() if best != Cover.NONE else "in the open")
		else:
			var counts := _cover_counts(tile, seen)
			if counts[0] > 0:
				reasons.append("full cover facing %s" % _enemies(counts[0]))
			if counts[1] > 0:
				reasons.append("half cover facing %d" % counts[1])
			if counts[2] > 0:
				reasons.append("exposed to %s" % _enemies(counts[2]))
			elif counts[0] + counts[1] == 0:
				reasons.append("out of sight of the enemy")
	var here := _danger(u, u.pos, seen)[0]
	var there := _danger(u, tile, seen)[0]
	if there + 1.0 < here * 0.7:
		reasons.append("safer than where %s stands" % ("it" if u.vehicle else "he"))
	for objective in battle.objectives:
		if (Vector2(tile) + Vector2(0.5, 0.5)).distance_to(objective["center"]) <= objective["radius"]:
			reasons.append("holds the %s" % objective["name"] if objective["owner"] == team else "contests the %s" % objective["name"])
	if seen.is_empty():
		var goal := _goal(tile)
		var closer := Vector2(u.pos).distance_to(goal) - Vector2(tile).distance_to(goal)
		if closer >= 1.0:
			reasons.append("%.0f tiles closer to %s" % [closer, _goal_name(goal)])
	elif u.actions >= 2 and battle.actions_for_cost(u, battle.reachable(u)[tile]["cost"]) == 1 and u.ammo > 0 and not u.weapon.needs_setup:
		# The follow-up the AI counted on: the best shot from the new spot.
		var best_target: Unit = null
		var best_hit := -1
		var saved := u.pos
		u.pos = tile
		for e in seen:
			if _can_see(tile, e.pos, u.sight):
				var hit: int = battle.shot_odds(u, e)["hit"]
				if hit > best_hit:
					best_hit = hit
					best_target = e
		u.pos = saved
		if best_target != null:
			reasons.append("then shoot %s at %d%%" % [best_target.name, best_hit])
	return reasons


## [enemies the tile has full cover against, half cover against, no cover against (and that can see it)].
func _cover_counts(tile: Vector2i, seen: Array[Unit]) -> Array[int]:
	var counts: Array[int] = [0, 0, 0]
	for e in seen:
		if not _can_see(e.pos, tile, e.sight):
			continue
		match battle.map.cover_against(tile, e.pos):
			Cover.FULL:
				counts[0] += 1
			Cover.HALF:
				counts[1] += 1
			_:
				counts[2] += 1
	return counts


## What gives the best cover on a tile, e.g. "the hedge", or "" in the open.
func _cover_name(tile: Vector2i) -> String:
	var map := battle.map
	var best := Cover.NONE
	var name := ""
	for d: Vector2i in TacticalMap.DIRS4:
		var level := map.cover_toward(tile, d)
		if level <= best:
			continue
		best = level
		if map.get_edge(tile, tile + d) == level:
			name = map.get_edge_kind(tile, tile + d)
		elif map.get_object(tile + d) == level:
			name = map.get_object_kind(tile + d)
		elif map.get_terrain(tile) == TacticalMap.Terrain.CRATER:
			name = "crater"
		else:
			name = "tank"
	return COVER_NAMES.get(name, "the " + name) if name != "" else ""


func _goal_name(goal: Vector2) -> String:
	for objective in battle.objectives:
		if objective["center"].distance_to(goal) < 0.5:
			return "the %s" % objective["name"]
	return "the enemy" if not _last_seen.is_empty() else "where the enemy should be"


static func _enemies(count: int) -> String:
	return "%d enem%s" % [count, "y" if count == 1 else "ies"]


static func _compass(dir: Vector2i) -> String:
	return ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][Pathfinder.heading_index(dir)]
