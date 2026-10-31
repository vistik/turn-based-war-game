class_name McpGameTools
extends RefCounted
## The agent link's tools: what an outside agent may ask the game, answered as JSON-friendly data.
## Everything is seen from the player's side and respects the fog of war: enemies appear only while the
## team can see them (plus where they were last seen), with what the screen shows of them (HP, suppression,
## status), never their ammo or kit. Hypotheticals (preview) only consider enemies in sight, and nothing
## rolls dice, so the agent can't learn outcomes in advance.
##
## Tiles are [x, y] arrays; x grows east, y grows south. Commands use the engine's format (Battle.execute)
## with tiles as [x, y].
##
## The host is the battle screen (AdvisorView) or null in tests. It provides player_team(), is_online(),
## is_busy(), show_proposal(suggestion) and apply_command(command) -> String.

const MAP_MARGIN := 6
const COVER_SPOTS := 8
const TERRAIN_GLYPHS := [".", ",", ";", "_", "=", "\"", "o"]
const LEGEND := {
	"tiles": ". grass  , rough ground  ; rubble  _ indoor floor  = road  \" wheat (hides you beyond 4 tiles)  o shell crater (half cover all round)",
	"objects": "T tree (full cover)  # rock or other full cover  W burning wreck (full cover)  + crate/sandbags/hay (half cover). Objects block movement",
	"units": "A-Z your units, a-z enemies in sight (see the unit lists for which is which), ? where an enemy was last seen",
	"smoke": "* smoke (blocks sight)",
	"edges": "Each tile is two characters: the tile, then its east edge. Between tile rows, a line shows each tile's south edge. | or - wall/hedge (full cover, blocks sight), ! or : fence/low wall/window (half cover)",
}
const COMMAND_HELP := "Commands: {\"cmd\": \"move\", \"unit\": id, \"tile\": [x, y]} | {\"cmd\": \"shoot\", \"unit\": id, \"target\": enemy id} | " \
		+ "{\"cmd\": \"overwatch\"|\"hunker\"|\"reload\"|\"set_up\"|\"rally\", \"unit\": id} | {\"cmd\": \"grenade\"|\"smoke\", \"unit\": id, \"tile\": [x, y]} | " \
		+ "{\"cmd\": \"mortar\", \"unit\": id, \"tile\": [x, y], \"kind\": \"he\"|\"smoke\"} | {\"cmd\": \"medkit\", \"unit\": id, \"target\": ally id} | " \
		+ "{\"cmd\": \"pivot\", \"unit\": tank id, \"tile\": heading such as [1, 0] or [1, -1]} | {\"cmd\": \"end_turn\"}"

var battle: Battle
var host: Object
## The player's team when there's no host (tests).
var team := 0
## Team -> AdvisorAI, the suggestion AIs (separate from any opponent AI, with their own memory).
var advisors := {}


func _init(p_battle: Battle, p_host: Object = null) -> void:
	battle = p_battle
	host = p_host


func advisor_for(p_team: int) -> AdvisorAI:
	if not advisors.has(p_team):
		advisors[p_team] = AdvisorAI.new(battle, p_team)
	return advisors[p_team]


func player_team() -> int:
	return host.player_team() if host != null else team


func instructions() -> String:
	return "You are helping a player of Normandy 1944, a turn-based WW2 squad tactics game (like XCOM) on a square grid. " \
		+ "Call get_state first, then get_unit_options or preview to weigh moves, suggest_move for the game's own AI opinion, " \
		+ "and propose_move to put your recommendation on the player's screen; the player decides whether to accept it. " \
		+ "Rules in brief: 2 actions per turn; moving uses 1 (or both for a dash); shooting, overwatch, hunkering, grenades and the mortar end the unit's turn. " \
		+ "Cover is directional: half -20, full -40 to hit; no cover from the shooter's side means flanked (+40 crit). " \
		+ "Objectives score 1 point per round while only your side stands in them. You only know what the player's side can see."


func tool_list() -> Array:
	var unit_arg := {"type": "integer", "description": "Unit id (from get_state)"}
	var tile_arg := {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2, "description": "[x, y]"}
	var command_arg := {
		"type": "object", "description": COMMAND_HELP,
		"properties": {
			"cmd": {"type": "string", "enum": ["move", "shoot", "overwatch", "hunker", "reload", "set_up", "rally", "grenade", "smoke", "mortar", "medkit", "pivot", "end_turn"]},
			"unit": {"type": "integer"}, "target": {"type": "integer"}, "tile": tile_arg, "kind": {"type": "string", "enum": ["he", "smoke"]},
		},
		"required": ["cmd"],
	}
	var read_only := {"readOnlyHint": true, "openWorldHint": false}
	return [
		{"name": "get_state", "title": "Battle state",
			"description": "What the player's side knows: round, turn, score, objectives, your units (HP, ammo, actions, status, kit), enemies in sight, last-seen enemies, marked mortar strikes and an ASCII map around the action. Respects the fog of war.",
			"inputSchema": {"type": "object", "properties": {
				"area": {"type": "array", "items": {"type": "integer"}, "minItems": 4, "maxItems": 4, "description": "Optional map window [x, y, width, height]; default: around your units and the enemies in sight"},
				"full_map": {"type": "boolean", "description": "Return the whole map (can be large)"}}},
			"annotations": read_only},
		{"name": "get_unit_options", "title": "Unit options",
			"description": "For one of your units: which actions are allowed (or why not), shot odds against every enemy it can see, and the best cover spots it can reach this turn.",
			"inputSchema": {"type": "object", "properties": {"unit": unit_arg, "all_tiles": {"type": "boolean", "description": "Also list every reachable tile as [x, y, path cost]"}}, "required": ["unit"]},
			"annotations": read_only},
		{"name": "preview", "title": "Preview a position",
			"description": "What a unit would face standing on a tile: path cost and actions, cover on each side, cover and exposure against each enemy in sight, shots it could take from there, and the AI's danger estimate. Changes nothing.",
			"inputSchema": {"type": "object", "properties": {"unit": unit_arg, "tile": tile_arg}, "required": ["unit", "tile"]},
			"annotations": read_only},
		{"name": "suggest_move", "title": "Ask the game's AI",
			"description": "The built-in tactical AI's suggestion for the player's next move (or for one unit), with its reasons. It only knows what the player's side can see. Set show to also put it on the player's screen.",
			"inputSchema": {"type": "object", "properties": {"unit": unit_arg, "show": {"type": "boolean"}}},
			"annotations": read_only},
		{"name": "propose_move", "title": "Propose a move",
			"description": "Shows a move on the player's screen (highlighted, with your note) for them to accept or ignore. The player makes the move, not you. " + COMMAND_HELP,
			"inputSchema": {"type": "object", "properties": {"command": command_arg, "note": {"type": "string", "description": "Short reason shown to the player, e.g. 'Flank the MG from the orchard'"}}, "required": ["command"]},
			"annotations": {"readOnlyHint": false, "destructiveHint": false, "openWorldHint": false}},
		{"name": "execute_command", "title": "Make a move",
			"description": "Makes a move for the player. Only works when the player has switched on \"Agent may play my moves\" in the game, and never in online games. " + COMMAND_HELP,
			"inputSchema": {"type": "object", "properties": {"command": command_arg}, "required": ["command"]},
			"annotations": {"readOnlyHint": false, "destructiveHint": true, "openWorldHint": false}},
	]


func call_tool(name: String, args: Dictionary) -> Dictionary:
	if host != null and host.is_online() and not AdvisorSettings.help_online:
		return {"error": "Help is switched off in online games."}
	if player_team() == -1:
		return {"error": "No human player in this battle (AI vs AI)."}
	match name:
		"get_state":
			return {"result": get_state(args)}
		"get_unit_options":
			return unit_options(int(args.get("unit", -1)), bool(args.get("all_tiles", false)))
		"preview":
			return preview(int(args.get("unit", -1)), args.get("tile"))
		"suggest_move":
			return suggest(int(args.get("unit", -1)), bool(args.get("show", false)))
		"propose_move":
			return propose(args.get("command"), str(args.get("note", "")))
		"execute_command":
			return execute(args.get("command"))
	return {"error": "Unknown tool: %s" % name}


# --- State ---

func get_state(args := {}) -> Dictionary:
	var side := player_team()
	var advisor := advisor_for(side)
	advisor._remember()
	var mine := []
	var glyphs := {}
	for u in battle.alive_units(side):
		glyphs[u.id] = char(65 + mine.size()) if mine.size() < 26 else "@"
		var data := _own_unit(u)
		data["glyph"] = glyphs[u.id]
		mine.append(data)
	var enemies := []
	for e in _seen_enemies(side):
		glyphs[e.id] = char(97 + enemies.size()) if enemies.size() < 26 else "x"
		var data := _enemy_unit(e)
		data["glyph"] = glyphs[e.id]
		enemies.append(data)
	var remembered := []
	for id: int in advisor._last_seen:
		var e := battle.get_unit(id)
		if not battle.team_sees(side, e):
			remembered.append({"id": id, "role": e.role, "last_seen": _tile(advisor._last_seen[id])})
	var objectives := []
	for objective in battle.objectives:
		objectives.append({"name": objective["name"], "center": [snappedf(objective["center"].x, 0.1), snappedf(objective["center"].y, 0.1)],
				"radius": objective["radius"], "held_by": _team_name(objective["owner"])})
	var strikes := []
	for strike in battle.strikes:
		strikes.append({"kind": strike["kind"], "target": _tile(strike["target"]), "radius": snappedf((CombatRules.MORTAR_RADIUS if strike["kind"] == "he" else CombatRules.SMOKE_RADIUS) + float(strike["scatter"]), 0.1),
				"fired_by": _team_name(strike.get("team", -1))})
	return {
		"you_are": Battle.TEAM_NAMES[side], "your_turn": battle.current_team == side and battle.winner == -1 and not _host_busy(),
		"current_side": Battle.TEAM_NAMES[battle.current_team], "round": battle.round_number, "max_rounds": battle.max_rounds,
		"winner": _team_name(battle.winner) if battle.winner >= 0 and battle.winner < Battle.TEAM_COUNT else ("draw" if battle.winner == Battle.DRAW else null),
		"score": {"you": battle.victory_points[side], "enemy": battle.victory_points[1 - side], "to_win": battle.vp_to_win},
		"objectives": objectives, "your_units": mine, "enemies_in_sight": enemies, "enemies_last_seen": remembered,
		"incoming_mortar_strikes": strikes, "map": _map_view(args, side, glyphs, remembered),
		"agent_may_act": AdvisorSettings.agent_may_act and not _online(),
	}


func _own_unit(u: Unit) -> Dictionary:
	var data := {
		"id": u.id, "name": u.name, "role": u.role, "pos": _tile(u.pos), "hp": u.hp, "max_hp": u.max_hp,
		"actions": u.actions, "mobility": u.current_mobility(), "aim": u.aim, "sight": u.sight,
		"weapon": {"name": u.weapon.name, "damage": [u.weapon.damage_min, u.weapon.damage_max], "ammo": u.ammo, "clip": u.weapon.clip_size,
				"needs_setup": u.weapon.needs_setup, "anti_tank": u.weapon.anti_tank},
		"suppression": u.suppression, "status": _status(u), "cover_here": _cover_sides(u.pos),
	}
	var kit := {}
	for item: Array in [["grenades", u.grenades], ["smoke_grenades", u.smoke_grenades], ["medkits", u.medkits], ["mortar_he", u.mortar_rounds], ["mortar_smoke", u.mortar_smoke]]:
		if item[1] > 0:
			kit[item[0]] = item[1]
	if not kit.is_empty():
		data["kit"] = kit
	if u.vehicle:
		data["facing"] = _tile(u.facing)
	return data


## What the screen shows of an enemy: no ammo, no kit.
func _enemy_unit(e: Unit) -> Dictionary:
	var data := {"id": e.id, "name": e.name, "role": e.role, "weapon": e.weapon.name, "pos": _tile(e.pos), "hp": e.hp, "max_hp": e.max_hp,
			"suppression": e.suppression, "status": _status(e), "cover_here": _cover_sides(e.pos)}
	if e.vehicle:
		data["facing"] = _tile(e.facing)
	return data


func _status(u: Unit) -> Array:
	var tags := []
	if u.is_pinned():
		tags.append("pinned")
	elif u.is_suppressed():
		tags.append("suppressed")
	if u.is_wounded():
		tags.append("wounded")
	for flag: Array in [[u.overwatch, "overwatch"], [u.hunkered, "hunkered"], [u.deployed, "mg_set_up"], [u.vehicle, "tank"]]:
		if flag[0]:
			tags.append(flag[1])
	return tags


## Cover on each side of a tile: {"N": "full", ...}, only the sides that have some.
func _cover_sides(p: Vector2i) -> Dictionary:
	var sides := {}
	for i in 4:
		var c := battle.map.cover_toward(p, TacticalMap.DIRS4[i])
		if c != Cover.NONE:
			sides[["N", "E", "S", "W"][i]] = Cover.NAMES[c].to_lower()
	return sides


func _map_view(args: Dictionary, side: int, glyphs: Dictionary, remembered: Array) -> Dictionary:
	var map := battle.map
	var rect := Rect2i()
	var area: Variant = args.get("area")
	if args.get("full_map", false):
		rect = Rect2i(0, 0, map.width, map.height)
	elif area is Array and area.size() == 4:
		rect = Rect2i(int(area[0]), int(area[1]), maxi(1, int(area[2])), maxi(1, int(area[3])))
	else:
		var first := true
		for u in battle.alive_units():
			if glyphs.has(u.id):
				rect = Rect2i(u.pos, Vector2i.ONE) if first else rect.expand(u.pos).expand(u.pos + Vector2i.ONE)
				first = false
		rect = rect.grow(MAP_MARGIN)
	rect = rect.intersection(Rect2i(0, 0, map.width, map.height))
	var last_seen := {}
	for entry: Dictionary in remembered:
		last_seen[Vector2i(entry["last_seen"][0], entry["last_seen"][1])] = true
	var rows := PackedStringArray()
	var header := "    "
	for x in range(rect.position.x, rect.end.x):
		header += "%d " % (x % 10)
	rows.append(header)
	for y in range(rect.position.y, rect.end.y):
		var line := "%3d " % y
		var under := "    "
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y)
			line += _glyph(p, glyphs, last_seen)
			var east := map.get_edge(p, p + Vector2i(1, 0))
			line += "|" if east == Cover.FULL else ("!" if east == Cover.HALF else " ")
			var south := map.get_edge(p, p + Vector2i(0, 1))
			under += ("-" if south == Cover.FULL else (":" if south == Cover.HALF else " ")) + " "
		rows.append(line.rstrip(" "))
		if under.strip_edges() != "":
			rows.append(under.rstrip(" "))
	return {"origin": _tile(rect.position), "size": _tile(rect.size), "full_size": [map.width, map.height], "rows": rows, "legend": LEGEND}


func _glyph(p: Vector2i, glyphs: Dictionary, last_seen: Dictionary) -> String:
	var map := battle.map
	var u := battle.unit_at(p)
	if u != null and glyphs.has(u.id):
		return glyphs[u.id]
	if last_seen.has(p):
		return "?"
	var object := map.get_object(p)
	if object == Cover.FULL:
		var kind := map.get_object_kind(p)
		return "T" if kind == "tree" else ("W" if kind == "wreck" else "#")
	if object == Cover.HALF:
		return "+"
	if map.has_smoke(p):
		return "*"
	return TERRAIN_GLYPHS[map.get_terrain(p)]


# --- Options and previews ---

func unit_options(id: int, all_tiles := false) -> Dictionary:
	var side := player_team()
	var u := battle.get_unit(id)
	if u == null or u.team != side or not u.is_alive():
		return {"error": "No such unit on your side: %s" % id}
	var seen := _seen_enemies(side)
	var targets := []
	for e in seen:
		if battle.can_see(u, e):
			targets.append(_shot(u, e))
	var reach := battle.reachable(u)
	var spots := []
	var one_action := 0
	var all := []
	for tile: Vector2i in reach:
		if tile == u.pos:
			continue
		var cost: float = reach[tile]["cost"]
		var actions := battle.actions_for_cost(u, cost)
		if actions == 1:
			one_action += 1
		if all_tiles:
			all.append([tile.x, tile.y, snappedf(cost, 0.01)])
		var counts := _cover_counts(tile, seen)
		var best := Cover.NONE
		for d: Vector2i in TacticalMap.DIRS4:
			best = maxi(best, battle.map.cover_toward(tile, d))
		var rank := counts[0] * 2.0 + counts[1] - counts[2] * 3.0 + best * 0.5 - cost * 0.05 - (actions - 1) * 0.5
		spots.append({"tile": _tile(tile), "cost": snappedf(cost, 0.01), "actions": actions, "best_cover": Cover.NAMES[best].to_lower(),
				"vs_enemies_in_sight": {"full": counts[0], "half": counts[1], "exposed": counts[2]}, "objective": _objective_at(tile), "_rank": rank})
	spots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["_rank"] > b["_rank"])
	spots = spots.slice(0, COVER_SPOTS)
	for spot: Dictionary in spots:
		spot.erase("_rank")
		if spot["objective"] == null:
			spot.erase("objective")
	var actions := {}
	actions["move"] = battle.can_act(u) if battle.can_act(u) != "" else ("" if not reach.is_empty() else "Can't move")
	actions["shoot"] = battle.can_fire(u) if battle.can_fire(u) != "" else ("" if not targets.is_empty() else "No enemy in line of sight")
	actions["overwatch"] = battle.can_overwatch(u)
	actions["hunker"] = battle.can_hunker(u)
	actions["reload"] = battle.can_reload(u)
	actions["set_up"] = battle.can_set_up(u)
	actions["rally"] = battle.can_rally(u)
	actions["grenade"] = battle.can_act(u) if u.grenades > 0 else "No grenades"
	actions["smoke"] = battle.can_act(u) if u.smoke_grenades > 0 else "No smoke grenades"
	actions["medkit"] = battle.can_act(u) if u.medkits > 0 else "No medkits"
	if u.role == "Mortar":
		actions["mortar"] = battle.can_act(u) if u.actions >= Unit.ACTIONS_PER_TURN else "The mortar can't fire after moving"
	if u.vehicle:
		actions["pivot"] = battle.can_act(u)
	var allowed := []
	var blocked := {}
	for action: String in actions:
		if actions[action] == "":
			allowed.append(action)
		else:
			blocked[action] = actions[action]
	var result := {"unit": _own_unit(u), "allowed": allowed, "not_allowed": blocked, "targets": targets,
			"moves": {"one_action_tiles": one_action, "dash_tiles": reach.size() - 1 - one_action if not reach.is_empty() else 0, "best_spots": spots},
			"ranges": {"grenade": CombatRules.GRENADE_RANGE, "smoke": CombatRules.SMOKE_RANGE, "mortar": [CombatRules.MORTAR_MIN_RANGE, CombatRules.MORTAR_MAX_RANGE]}}
	if u.medkits > 0:
		var patients := []
		for ally in battle.alive_units(side):
			if battle.can_use_medkit(u, ally) == "":
				patients.append(ally.id)
		result["medkit_targets"] = patients
	if all_tiles:
		result["moves"]["all_tiles"] = all
	return {"result": result}


func preview(id: int, tile_value: Variant) -> Dictionary:
	var side := player_team()
	var u := battle.get_unit(id)
	if u == null or u.team != side or not u.is_alive():
		return {"error": "No such unit on your side: %s" % id}
	var tile: Variant = _parse_tile(tile_value)
	if tile == null or not battle.map.in_bounds(tile):
		return {"error": "tile must be [x, y] inside the %dx%d map" % [battle.map.width, battle.map.height]}
	var map := battle.map
	var reach := battle.reachable(u)
	var result := {"unit": u.id, "tile": _tile(tile), "terrain": TacticalMap.TERRAIN_NAMES[map.get_terrain(tile)],
			"in_sight_now": battle.team_visible_tiles(side).has(tile), "cover": _cover_sides(tile)}
	if map.get_object(tile) != Cover.NONE:
		result["blocked_by"] = map.get_object_kind(tile)
	if tile == u.pos:
		result["reachable"] = true
		result["cost"] = 0.0
	elif reach.has(tile) and battle.can_move(u, tile) == "":
		result["reachable"] = true
		result["cost"] = snappedf(reach[tile]["cost"], 0.01)
		result["actions"] = battle.actions_for_cost(u, reach[tile]["cost"])
		var path := []
		for p in Pathfinder.path_to(reach, tile):
			path.append(_tile(p))
		result["path"] = path
		if u.vehicle:
			result["facing_after"] = _tile(reach[tile]["facing"])
	else:
		result["reachable"] = false
		result["why_not"] = battle.can_move(u, tile) if battle.can_act(u) == "" else battle.can_act(u)
	var objective: Variant = _objective_at(tile)
	if objective != null:
		result["objective"] = objective
	# Pretend the unit stands there to read cover and odds; enemies we can't see are left out.
	var advisor := advisor_for(side)
	var seen := _seen_enemies(side)
	var saved_pos := u.pos
	var saved_facing := u.facing
	if result.get("facing_after") != null:
		u.facing = reach[tile]["facing"]
	u.pos = tile
	var against := []
	for e in seen:
		var entry := {"id": e.id, "name": e.name, "role": e.role, "distance": snappedf(Vector2(tile).distance_to(Vector2(e.pos)), 0.1)}
		var they_see := LineOfSight.can_see(map, e.pos, tile, e.sight)
		entry["can_see_you"] = they_see
		if not u.vehicle:
			var cover := map.cover_against(tile, e.pos)
			entry["your_cover"] = Cover.NAMES[cover].to_lower()
			entry["flanked"] = they_see and cover == Cover.NONE
		else:
			entry["armour_facing_them"] = CombatRules.armor_side(u, e.pos)
		if they_see:
			entry["their_hit_chance"] = battle.shot_odds(e, u)["hit"]
		if LineOfSight.can_see(map, tile, e.pos, u.sight):
			var odds := battle.shot_odds(u, e)
			entry["your_shot"] = {"hit": odds["hit"], "crit": odds["crit"], "flanked": odds["flanked"]}
		against.append(entry)
	var danger: float = advisor._danger(u, tile, seen)[0]
	u.pos = saved_pos
	u.facing = saved_facing
	result["enemies_in_sight"] = against
	result["danger"] = snappedf(danger / 10.0, 0.01)
	result["danger_note"] = "Expected damage per enemy turn from enemies you know about, as the AI estimates it"
	return {"result": result}


func suggest(id := -1, show := false) -> Dictionary:
	var side := player_team()
	var only: Unit = null
	if id != -1:
		only = battle.get_unit(id)
		if only == null or only.team != side:
			return {"error": "No such unit on your side: %s" % id}
	if _host_busy():
		return {"error": "Wait: the last move is still playing out"}
	var suggestion := advisor_for(side).suggest(only)
	if suggestion.has("error"):
		return suggestion
	if show and host != null:
		suggestion["source"] = "AI"
		host.show_proposal(suggestion)
	return {"result": {"command": command_to_json(suggestion["command"]), "text": suggestion["text"], "reasons": suggestion["reasons"],
			"score": suggestion["score"], "shown_to_player": show and host != null}}


func propose(value: Variant, note: String) -> Dictionary:
	var command := command_from_json(value)
	if command.has("error"):
		return command
	var err := validate(command)
	if err != "":
		return {"error": "Not a legal move right now: %s" % err}
	if host == null:
		return {"error": "No screen to show it on"}
	var u := battle.get_unit(command.get("unit", -1))
	var target := battle.get_unit(command.get("target", -1))
	var text := note.strip_edges().left(200)
	if text == "":
		text = describe(command)
	host.show_proposal({"command": command, "unit": u.id if u != null else -1, "kind": command["cmd"], "text": text, "reasons": [],
			"target": target.id if target != null else -1, "tile": command.get("tile"), "source": "Agent"})
	return {"result": {"shown_to_player": true, "command": command_to_json(command), "text": text,
			"note": "The player decides. Call get_state later to see what they did."}}


func execute(value: Variant) -> Dictionary:
	if _online():
		return {"error": "The agent can't make moves in online games."}
	if not AdvisorSettings.agent_may_act:
		return {"error": "The player hasn't allowed the agent to make moves. Use propose_move instead, or ask them to switch on \"Agent may play my moves\" in the battle screen."}
	var command := command_from_json(value)
	if command.has("error"):
		return command
	var err := validate(command)
	if err != "":
		return {"error": "Not a legal move right now: %s" % err}
	if host == null:
		return {"error": "No game screen"}
	err = host.apply_command(command)
	if err != "":
		return {"error": err}
	return {"result": {"done": describe(command), "note": "Applied. The screen is playing it out; call get_state for the new situation."}}


# --- Commands ---

## Converts an agent's JSON command (tiles as [x, y]) to engine form, or {"error": ...}.
func command_from_json(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("cmd") is String:
		return {"error": "command must be an object with a cmd. " + COMMAND_HELP}
	var command := {"cmd": value["cmd"]}
	if value.has("unit"):
		command["unit"] = int(value["unit"])
	if value.has("target"):
		command["target"] = int(value["target"])
	var tile: Variant = value.get("tile", value.get("dir"))
	if tile != null:
		tile = _parse_tile(tile)
		if tile == null:
			return {"error": "tile must be [x, y]"}
		command["tile"] = tile
	if value.has("kind"):
		command["kind"] = str(value["kind"])
	return command


static func command_to_json(command: Dictionary) -> Dictionary:
	var result := command.duplicate()
	if result.get("tile") is Vector2i:
		result["tile"] = [result["tile"].x, result["tile"].y]
	return result


## Why the player's side can't give this command now ("" if it can). Never rolls dice, and treats enemies
## out of sight as unknown, so it gives nothing away.
func validate(command: Dictionary) -> String:
	var side := player_team()
	if battle.winner != -1:
		return "The battle is over"
	if battle.current_team != side:
		return "Not your turn"
	if _host_busy():
		return "Wait: the last move is still playing out"
	var cmd: String = command.get("cmd", "")
	if cmd == "end_turn":
		return ""
	var u := battle.get_unit(command.get("unit", -1))
	if u == null or u.team != side:
		return "No such unit on your side"
	var tile: Vector2i = command.get("tile", Vector2i(-1, -1))
	var target := battle.get_unit(command.get("target", -1))
	if cmd in ["move", "grenade", "smoke", "mortar"] and not command.has("tile"):
		return "%s needs a tile" % cmd
	match cmd:
		"move":
			return battle.can_move(u, tile)
		"shoot":
			if target == null or target.team == side or not target.is_alive() or not battle.team_sees(side, target):
				return "Unknown target: not an enemy in sight"
			return battle.can_shoot(u, target)
		"overwatch":
			return battle.can_overwatch(u)
		"hunker":
			return battle.can_hunker(u)
		"reload":
			return battle.can_reload(u)
		"set_up":
			return battle.can_set_up(u)
		"rally":
			return battle.can_rally(u)
		"grenade":
			return battle.can_throw_grenade(u, tile)
		"smoke":
			return battle.can_throw_smoke(u, tile)
		"mortar":
			return battle.can_fire_mortar(u, tile, command.get("kind", "he"))
		"medkit":
			return battle.can_use_medkit(u, target)
		"pivot":
			return battle.can_pivot(u, tile) if command.has("tile") else "pivot needs a heading, e.g. [1, 0]"
	return "Unknown command: %s" % cmd


## A short description of a command, e.g. "Pvt. Baker: move to (12, 30)".
func describe(command: Dictionary) -> String:
	var u := battle.get_unit(command.get("unit", -1))
	var target := battle.get_unit(command.get("target", -1))
	var cmd: String = command.get("cmd", "")
	if cmd == "end_turn" or u == null:
		return "End the turn"
	var text := "%s: %s" % [u.name, cmd.replace("_", " ")]
	if target != null:
		text += " " + target.name
	if command.get("tile") is Vector2i:
		text += " (%d, %d)" % [command["tile"].x, command["tile"].y]
	return text


# --- Helpers ---

func _seen_enemies(side: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for e in battle.alive_units():
		if e.team != side and battle.team_sees(side, e):
			result.append(e)
	return result


func _shot(u: Unit, e: Unit) -> Dictionary:
	var odds := battle.shot_odds(u, e)
	var modifiers := []
	for m: Array in odds["modifiers"]:
		modifiers.append([m[0], m[1]])
	var entry := {"target": e.id, "name": e.name, "role": e.role, "hit": odds["hit"], "graze": odds["graze"], "crit": odds["crit"],
			"flanked": odds["flanked"], "target_cover": Cover.NAMES[odds["cover"]].to_lower(), "distance": snappedf(odds["distance"], 0.1),
			"modifiers": modifiers}
	var outcome: Array[float] = advisor_for(u.team)._expected_damage(u, u.pos, e, e.pos)
	entry["expected_damage"] = snappedf(outcome[0], 0.01)
	entry["kill_chance"] = snappedf(outcome[1], 0.01)
	if e.vehicle:
		entry["armour_side"] = CombatRules.armor_side(e, u.pos)
		if not u.weapon.anti_tank:
			entry["note"] = "Small arms can't hurt a tank"
	return entry


## [full, half, exposed]: enemies in sight that the tile has full cover from, half cover from, or none (and that can see it).
func _cover_counts(tile: Vector2i, seen: Array[Unit]) -> Array[int]:
	var counts: Array[int] = [0, 0, 0]
	for e in seen:
		if not LineOfSight.can_see(battle.map, e.pos, tile, e.sight):
			continue
		counts[2 - battle.map.cover_against(tile, e.pos)] += 1
	return counts


func _objective_at(tile: Vector2i) -> Variant:
	for objective in battle.objectives:
		if (Vector2(tile) + Vector2(0.5, 0.5)).distance_to(objective["center"]) <= objective["radius"]:
			return objective["name"]
	return null


func _host_busy() -> bool:
	return host != null and host.is_busy()


func _online() -> bool:
	return host != null and host.is_online()


static func _tile(p: Vector2i) -> Array:
	return [p.x, p.y]


static func _parse_tile(value: Variant) -> Variant:
	if value is Array and value.size() == 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
		return Vector2i(int(value[0]), int(value[1]))
	if value is Dictionary and value.has("x") and value.has("y"):
		return Vector2i(int(value["x"]), int(value["y"]))
	return null


static func _team_name(team: int) -> Variant:
	return Battle.TEAM_NAMES[team] if team >= 0 and team < Battle.TEAM_COUNT else null
