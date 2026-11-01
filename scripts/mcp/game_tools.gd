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
## The host is the battle screen (AdvisorView) or null in tests. It provides player_team(), agent_plays(),
## is_online(), is_busy(), view_busy(), show_proposal(suggestion), apply_command(command) -> String and
## set_fast_playback(on).
##
## An agent can also play a whole side: execute_command waits until the move has played out and answers with
## what the side saw happen, and wait_for_turn waits for the side's turn (or the end) and reports what the
## side saw of the other side's turn. The reports respect the fog of war like everything else.

const MAP_MARGIN := 6
const COVER_SPOTS := 8
const MAX_SPOTS := 30
## Most commands in one execute_command call.
const MAX_BATCH := 20
const TERRAIN_GLYPHS := [".", ",", ";", "_", "=", "\"", "o", "~", "x", "&", "%", "'"]
const LEGEND := {
	"tiles": ". grass  , rough ground  ; rubble  _ indoor floor  = road  \" wheat (hides you beyond 4 tiles; trampled when walked through)  ~ trampled wheat  x barbed wire (slow on foot)  o shell crater (half cover all round)  & jungle (slow, hides anyone in it beyond 3 tiles, sight only reaches 1 tile into it)  % rice paddy (slow, no cover)  ' elephant grass (hides crouching and prone soldiers beyond 3 tiles)",
	"objects": "T tree (full cover)  # rock or other full cover  W burning wreck (full cover)  + crate/sandbags/hay (half cover)  F fuel drums (half cover, explode)  O oil tank (full cover, big explosion). Objects block movement. Shoot drums/tanks with shoot_object",
	"hazards": "^ fire (impassable, burns whoever stands in it)  M a mine or punji trap your side knows of (clear it with clear_mine from next to it). Unspotted mines are hidden  U a tunnel entrance your side knows of",
	"units": "A-Z your units, a-z enemies in sight (see the unit lists for which is which), ? where an enemy was last seen",
	"smoke": "* smoke (blocks sight)",
	"edges": "Each tile is two characters: the tile, then its east edge. Between tile rows, a line shows each tile's south edge. | or - wall/hedge (full cover, blocks sight), ! or : fence/low wall/window (half cover)",
}
const COMMAND_HELP := "Commands: {\"cmd\": \"move\", \"unit\": id, \"tile\": [x, y]} | {\"cmd\": \"shoot\", \"unit\": id, \"target\": enemy id} | " \
		+ "{\"cmd\": \"overwatch\"|\"hunker\"|\"reload\"|\"set_up\"|\"rally\", \"unit\": id} | {\"cmd\": \"grenade\"|\"smoke\", \"unit\": id, \"tile\": [x, y]} | " \
		+ "{\"cmd\": \"mortar\", \"unit\": id, \"tile\": [x, y], \"kind\": \"he\"|\"smoke\"|\"napalm\"} | {\"cmd\": \"tunnel\"|\"trap\"|\"detonate\", \"unit\": id, \"tile\": [x, y]} | {\"cmd\": \"medkit\", \"unit\": id, \"target\": ally id} | " \
		+ "{\"cmd\": \"aimed_shot\"|\"suppress\", \"unit\": id, \"target\": enemy id} | {\"cmd\": \"stance\", \"unit\": id, \"stance\": 0 stand, 1 crouch, 2 prone} | " \
		+ "{\"cmd\": \"shoot_object\"|\"clear_mine\", \"unit\": id, \"tile\": [x, y]} | " \
		+ "{\"cmd\": \"pivot\", \"unit\": tank id, \"tile\": heading such as [1, 0] or [1, -1]} | {\"cmd\": \"end_turn\"}"

var battle: Battle
var host: Object
## The player's team when there's no host (tests).
var team := 0
## Team -> AdvisorAI, the suggestion AIs (separate from any opponent AI, with their own memory).
var advisors := {}
## What the player's side saw happen since the agent last asked (lines of text), most recent last.
var _seen_log: Array[String] = []
## Things that should make the agent rethink a list of orders (our units shot at, hurt, killed or panicking),
## gathered by note_events and cleared by execute between commands.
var _surprises: Array[String] = []
## Longest a waiting tool holds its answer, in seconds, and how many report lines are kept.
const MAX_WAIT := 55.0
const LOG_LIMIT := 200


func _init(p_battle: Battle, p_host: Object = null) -> void:
	battle = p_battle
	host = p_host


func advisor_for(p_team: int) -> AdvisorAI:
	if not advisors.has(p_team):
		advisors[p_team] = AdvisorAI.new(battle, p_team)
	return advisors[p_team]


func player_team() -> int:
	return host.player_team() if host != null else team


## The rules an agent keeps tripping over, said once for instructions() and the tool descriptions.
const RULES := "Rules in brief: 2 actions per turn; a move within the unit's mobility uses 1 action, a longer one (a dash) uses both, so a unit that dashes can't shoot that turn. " \
		+ "Shooting, overwatch, hunkering, grenades, smoke and the mortar end the unit's turn. " \
		+ "Cover is directional: half -20, full -40 to hit; no cover from the shooter's side means flanked (+40 crit). Range, hunkering and crouching behind cover lower the odds further. " \
		+ "Objectives: one changes hands when only one side has soldiers inside its radius, and stays held after they leave. At the end of every round each held objective scores 1 point for its holder, " \
		+ "even while the other side stands in it too, so to stop the enemy scoring you must take it (be the only side inside), not just contest it. " \
		+ "Grenades and smoke need a clear line to the tile within range and can't be thrown lying down. " \
		+ "The mortar needs both actions (it can't fire after moving), a target 5-22 tiles away that someone on your side can see, and its round lands at the start of your NEXT turn, with some scatter; enemy strikes show in get_state as incoming_mortar_strikes, so move out of their radius. " \
		+ "A medkit treats an adjacent ally or the unit carrying it. Hunkering needs cover. A machine gun must set up (1 action) before it can shoot or overwatch, and moving packs it up again. " \
		+ "Enemies out of sight may be on overwatch: moving across open ground in front of unscouted positions draws fire. Small arms can't hurt tanks; tanks take more damage from the side and rear. " \
		+ "Vietnam: the Viet Cong move between their tunnel entrances (tunnel: both actions, from one of your entrances to another) and sappers lay punji traps next to them (trap); " \
		+ "an enemy tunnel entrance you have found can be blown in from next to it with clear_mine. The radio operator's artillery (mortar command, he or napalm) needs no setting up but he must see the target himself. " \
		+ "There the Americans score for objectives and the Viet Cong for every American killed. " \
		+ "Afghanistan and Iraq: insurgent bomb makers plant IEDs (trap) and set them off when they can see them (detonate); the Coalition's EOD tech spots them far more often, and its JTAC calls air strikes (mortar command) on what he sees. Coalition score for objectives, insurgents for kills. " \
		+ "You only know what your side can see."


func instructions() -> String:
	if host != null and host.agent_plays():
		return "You are playing %s in %s, a turn-based squad tactics game (like XCOM) on a square grid, against an opponent. " % [battle.team_name(player_team()), battle.theatre().title] \
			+ "Loop until the battle ends: call wait_for_turn, which returns the battle state once it's your turn; weigh moves with get_unit_options (its filters find tiles in an objective, " \
			+ "in cover from an enemy, or with a shot at a target) and preview (suggest_move gives the game's own AI opinion). " \
			+ "Then give your orders with execute_command: send several at once as a commands list; it plays them in order and stops early if something unexpected happens " \
			+ "(one of your units is shot at or hurt, or a new enemy comes into sight), so you can rethink. Set fast to skip the playback. " \
			+ "End your turn with {\"cmd\": \"end_turn\"} (it also ends once no unit can act). " + RULES
	return "You are helping a player of Normandy 1944, a turn-based WW2 squad tactics game (like XCOM) on a square grid. " \
		+ "Call get_state first, then get_unit_options or preview to weigh moves, suggest_move for the game's own AI opinion, " \
		+ "and propose_move to put your recommendation on the player's screen; the player decides whether to accept it. " + RULES


func tool_list() -> Array:
	var unit_arg := {"type": "integer", "description": "Unit id (from get_state)"}
	var tile_arg := {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2, "description": "[x, y]"}
	var command_arg := {
		"type": "object", "description": COMMAND_HELP,
		"properties": {
			"cmd": {"type": "string", "enum": ["move", "shoot", "aimed_shot", "suppress", "stance", "shoot_object", "clear_mine", "overwatch", "hunker", "reload", "set_up", "rally", "grenade", "smoke", "mortar", "medkit", "pivot", "tunnel", "trap", "detonate", "end_turn"]},
			"unit": {"type": "integer"}, "target": {"type": "integer"}, "tile": tile_arg, "kind": {"type": "string", "enum": ["he", "smoke", "napalm"]},
			"stance": {"type": "integer", "enum": [0, 1, 2], "description": "0 stand, 1 crouch, 2 prone"},
		},
		"required": ["cmd"],
	}
	var read_only := {"readOnlyHint": true, "openWorldHint": false}
	return [
		{"name": "get_state", "title": "Battle state",
			"description": "What the player's side knows: round, turn, score, objectives (and who holds them), your units (HP, ammo, actions, status, kit), enemies in sight, last-seen enemies, incoming mortar strikes, " \
				+ "and threats: which enemies in sight can see each of your units, with their hit chance and your cover against them. Respects the fog of war. " \
				+ "No map unless you ask for one (map, area or full_map): an ASCII map around the action, which costs a lot of text.",
			"inputSchema": {"type": "object", "properties": {
				"map": {"type": "boolean", "description": "Include an ASCII map around your units and the enemies in sight"},
				"area": {"type": "array", "items": {"type": "integer"}, "minItems": 4, "maxItems": 4, "description": "Include the map for this window [x, y, width, height]"},
				"full_map": {"type": "boolean", "description": "Include the whole map (large)"}}},
			"annotations": read_only},
		{"name": "get_unit_options", "title": "Unit options",
			"description": "For one of your units: which actions are allowed (or why not), shot odds against every enemy it can see now, and the best spots it can reach this turn. " \
				+ "Each spot says how many actions the move uses, its cover against the enemies in sight, the objective it's in, and the shots the unit could still take from there (only after a 1-action move). " \
				+ "Filters narrow the spots to tiles in an objective, in cover from an enemy, or with a shot at a target, e.g. {\"unit\": 3, \"objective\": \"Farm\", \"shoot_target\": 10}.",
			"inputSchema": {"type": "object", "properties": {
				"unit": unit_arg,
				"objective": {"type": "string", "description": "Only tiles inside this objective (by name)"},
				"covered_from": {"type": "integer", "description": "Only tiles with cover against this enemy (or out of its sight)"},
				"shoot_target": {"type": "integer", "description": "Only tiles the unit can reach with 1 action and still shoot this enemy from; best odds first"},
				"limit": {"type": "integer", "description": "How many spots to list (default %d, most %d)" % [COVER_SPOTS, MAX_SPOTS]},
				"all_tiles": {"type": "boolean", "description": "Also list every reachable tile as [x, y, path cost, actions used]"}}, "required": ["unit"]},
			"annotations": read_only},
		{"name": "preview", "title": "Preview a position",
			"description": "What a unit would face standing on a tile: path cost and the actions the move would use (not the actions left), cover on each side, cover and exposure against each enemy in sight, shots it could take from there, and the AI's danger estimate. Changes nothing.",
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
		{"name": "execute_command", "title": "Make moves",
			"description": "Makes moves for your side and waits until they have played out, then tells you what your side saw happen (shots, hits, overwatch fire, deaths). " \
				+ "Give one command, or a commands list (up to %d) to play in order, e.g. a move then overwatch for each of several units. " % MAX_BATCH \
				+ "A list stops early when something unexpected happens (one of your units is shot at, hurt or panics, or a new enemy comes into sight) unless stop_on_surprise is false, " \
				+ "and stops at the first command that isn't legal any more; the answer lists what ran and what didn't. " \
				+ "Set fast to skip the playback animation. Works when the agent plays this side (\"Agent vs AI\" or \"Me vs agent\"), or when the player has switched on \"Agent may play my moves\"; never in online games. " + COMMAND_HELP,
			"inputSchema": {"type": "object", "properties": {
				"command": command_arg,
				"commands": {"type": "array", "items": command_arg, "maxItems": MAX_BATCH, "description": "Several commands, played in order"},
				"stop_on_surprise": {"type": "boolean", "description": "Stop a list early when something unexpected happens (default true)"},
				"fast": {"type": "boolean", "description": "Play the moves out instantly instead of animating them"}}},
			"annotations": {"readOnlyHint": false, "destructiveHint": true, "openWorldHint": false}},
		{"name": "wait_for_turn", "title": "Wait for your turn",
			"description": "Waits until it's your side's turn and nothing is playing out, or the battle is over, for up to timeout_seconds (default and most %d). " % int(MAX_WAIT) \
				+ "Returns whose turn it is, the round and score, what your side saw happen meanwhile (the enemy's moves in sight, shots at your units, mortar rounds), " \
				+ "and, once it's your turn, the battle state as get_state gives it (without the map). If it times out, call it again.",
			"inputSchema": {"type": "object", "properties": {
				"timeout_seconds": {"type": "number", "description": "How long to wait (1-%d)" % int(MAX_WAIT)},
				"include_state": {"type": "boolean", "description": "Include the battle state when it's your turn (default true)"},
				"fast": {"type": "boolean", "description": "Play the other side's moves out instantly instead of animating them"}}},
			"annotations": read_only},
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
			return unit_options(int(args.get("unit", -1)), bool(args.get("all_tiles", false)), args)
		"preview":
			return preview(int(args.get("unit", -1)), args.get("tile"))
		"suggest_move":
			return suggest(int(args.get("unit", -1)), bool(args.get("show", false)))
		"propose_move":
			return propose(args.get("command"), str(args.get("note", "")))
		"execute_command":
			var list: Variant = args.get("commands")
			if list == null:
				list = [args.get("command")]
			return execute(list, bool(args.get("stop_on_surprise", true)), bool(args.get("fast", false)))
		"wait_for_turn":
			return wait_for_turn(float(args.get("timeout_seconds", MAX_WAIT)), bool(args.get("include_state", true)), bool(args.get("fast", false)))
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
		strikes.append({"kind": strike["kind"], "target": _tile(strike["target"]), "radius": snappedf(battle.strike_reach(strike), 0.1),
				"fired_by": _team_name(strike.get("team", -1))})
	var state := {
		"you_are": battle.team_name(side), "your_turn": battle.current_team == side and battle.winner == -1 and not _host_busy(),
		"current_side": battle.team_name(battle.current_team), "round": battle.round_number, "max_rounds": battle.max_rounds,
		"winner": _team_name(battle.winner) if battle.winner >= 0 and battle.winner < Battle.TEAM_COUNT else ("draw" if battle.winner == Battle.DRAW else null),
		"score": {"you": battle.victory_points[side], "enemy": battle.victory_points[1 - side], "to_win": battle.vp_to_win},
		"objectives": objectives, "your_units": mine, "enemies_in_sight": enemies, "enemies_last_seen": remembered,
		"incoming_mortar_strikes": strikes, "threats": _threats(side),
		"agent_may_act": (AdvisorSettings.agent_may_act or (host != null and host.agent_plays())) and not _online(),
	}
	if args.get("map", false) or args.get("full_map", false) or args.get("area") is Array:
		state["map"] = _map_view(args, side, glyphs, remembered)
	return state


## For each of the side's units that an enemy in sight can see: who, their hit chance and our cover against them.
func _threats(side: int) -> Array:
	var seen := _seen_enemies(side)
	var result := []
	for u in battle.alive_units(side):
		var by := []
		for e in seen:
			if not battle.can_see(e, u):
				continue
			var entry := {"enemy": e.id, "role": e.role, "their_hit": battle.shot_odds(e, u)["hit"]}
			if u.vehicle:
				entry["armour_facing_them"] = CombatRules.armor_side(u, e.pos)
			else:
				entry["your_cover"] = Cover.NAMES[battle.map.cover_against(u.pos, e.pos)].to_lower()
			by.append(entry)
		if not by.is_empty():
			result.append({"unit": u.id, "name": u.name, "seen_by": by})
	return result


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
	if map.has_fire(p):
		return "^"
	if map.has_mine(p) and battle.mines_known_to(player_team()).has(p):
		return "M"
	if battle.tunnels_known_to(player_team()).has(p):
		return "U"
	if map.is_explosive(p):
		return "O" if map.get_object_kind(p) == "oil_tank" else "F"
	if object == Cover.FULL:
		var kind := map.get_object_kind(p)
		return "T" if kind == "tree" else ("W" if kind == "wreck" else "#")
	if object == Cover.HALF:
		return "+"
	if map.has_smoke(p):
		return "*"
	return TERRAIN_GLYPHS[map.get_terrain(p)]


# --- Options and previews ---

func unit_options(id: int, all_tiles := false, filters := {}) -> Dictionary:
	var side := player_team()
	var u := battle.get_unit(id)
	if u == null or u.team != side or not u.is_alive():
		return {"error": "No such unit on your side: %s" % id}
	var seen := _seen_enemies(side)
	var targets := []
	for e in seen:
		if battle.can_see(u, e):
			targets.append(_shot(u, e))
	# Filters: objective name, an enemy to be covered from, an enemy to shoot at after moving.
	var objective_name := str(filters.get("objective", "")).strip_edges().to_lower()
	if objective_name != "" and not battle.objectives.any(func(o: Dictionary) -> bool: return str(o["name"]).to_lower() == objective_name):
		return {"error": "No objective called %s" % filters["objective"]}
	var covered_from: Unit = null
	var shoot_target: Unit = null
	for key: String in ["covered_from", "shoot_target"]:
		if filters.get(key) == null:
			continue
		var e := battle.get_unit(int(filters[key]))
		if e == null or e.team == side or not e.is_alive() or not seen.has(e):
			return {"error": "%s must be an enemy in sight" % key}
		if key == "covered_from":
			covered_from = e
		else:
			shoot_target = e
	var filtered := objective_name != "" or covered_from != null or shoot_target != null
	var limit := clampi(int(filters.get("limit", COVER_SPOTS)), 1, MAX_SPOTS)
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
			all.append([tile.x, tile.y, snappedf(cost, 0.01), actions])
		var objective: Variant = _objective_at(tile)
		if objective_name != "" and (objective == null or str(objective).to_lower() != objective_name):
			continue
		if covered_from != null and LineOfSight.can_see(battle.map, covered_from.pos, tile, covered_from.sight) \
				and battle.map.cover_against(tile, covered_from.pos) == Cover.NONE:
			continue
		var shot_odds := 0
		if shoot_target != null:
			if actions > 1 or not _can_shoot_after_moving(u):
				continue
			var odds: Variant = _odds_from(u, tile, shoot_target)
			if odds == null or odds["hit"] <= 0:
				continue
			shot_odds = odds["hit"]
		var counts := _cover_counts(tile, seen)
		var best := Cover.NONE
		for d: Vector2i in TacticalMap.DIRS4:
			best = maxi(best, battle.map.cover_toward(tile, d))
		var rank := counts[0] * 2.0 + counts[1] - counts[2] * 3.0 + best * 0.5 - cost * 0.05 - (actions - 1) * 0.5 + shot_odds * 0.05
		spots.append({"tile": tile, "cost": snappedf(cost, 0.01), "actions": actions, "best_cover": Cover.NAMES[best].to_lower(),
				"vs_enemies_in_sight": {"full": counts[0], "half": counts[1], "exposed": counts[2]}, "objective": objective, "_rank": rank})
	spots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["_rank"] > b["_rank"])
	spots = spots.slice(0, limit)
	for spot: Dictionary in spots:
		spot.erase("_rank")
		if spot["objective"] == null:
			spot.erase("objective")
		var tile: Vector2i = spot["tile"]
		spot["tile"] = _tile(tile)
		# The shots the unit could still take after a 1-action move there.
		if spot["actions"] == 1 and _can_shoot_after_moving(u):
			var shots := []
			for e in seen:
				if shoot_target != null and e != shoot_target:
					continue
				var odds: Variant = _odds_from(u, tile, e)
				if odds != null:
					shots.append({"target": e.id, "hit": odds["hit"], "crit": odds["crit"], "flanked": odds["flanked"]})
			if not shots.is_empty():
				spot["shots"] = shots
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
	if not u.indirect.is_empty():
		actions["mortar"] = battle.can_act(u) if u.actions >= Unit.ACTIONS_PER_TURN or not u.indirect["still"] else "The %s can't fire after moving" % u.indirect["name"]
	if u.vehicle:
		actions["pivot"] = battle.can_act(u)
	else:
		actions["stance"] = battle.can_act(u)
		actions["aimed_shot"] = actions["shoot"] if u.actions >= Unit.ACTIONS_PER_TURN or actions["shoot"] != "" else "Needs both actions"
		actions["suppress"] = actions["shoot"]
	var allowed := []
	var blocked := {}
	for action: String in actions:
		if actions[action] == "":
			allowed.append(action)
		else:
			blocked[action] = actions[action]
	var moves := {"one_action_tiles": one_action, "dash_tiles": reach.size() - 1 - one_action if not reach.is_empty() else 0}
	moves["matching_spots" if filtered else "best_spots"] = spots
	if filtered and spots.is_empty():
		moves["note"] = "No reachable tile matches those filters this turn"
	var result := {"unit": _own_unit(u), "allowed": allowed, "not_allowed": blocked, "targets": targets, "moves": moves,
			"ranges": {"grenade": CombatRules.GRENADE_RANGE, "smoke": CombatRules.SMOKE_RANGE, "mortar": [u.indirect.get("min", 0.0), u.indirect.get("max", 0.0)]}}
	if u.def.get("throw_range", CombatRules.GRENADE_RANGE) != CombatRules.GRENADE_RANGE:
		result["ranges"]["grenade"] = u.def["throw_range"]
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


## Plays a list of commands (agent JSON) in order, each once the last has played out. A list of one answers
## like a single move: {"done", "what_happened", ...}. A longer list answers with "steps", one per command
## that ran, and stops early at a surprise (see note_events) or at a command that isn't legal any more.
func execute(values: Variant, stop_on_surprise := true, fast := false) -> Dictionary:
	if _online():
		return {"error": "The agent can't make moves in online games."}
	if not AdvisorSettings.agent_may_act and not (host != null and host.agent_plays()):
		return {"error": "The player hasn't allowed the agent to make moves. Use propose_move instead, or ask them to switch on \"Agent may play my moves\" in the battle screen."}
	if not values is Array or values.is_empty():
		return {"error": "Give a command, or commands as a list. " + COMMAND_HELP}
	if values.size() > MAX_BATCH:
		return {"error": "At most %d commands at a time" % MAX_BATCH}
	var commands: Array[Dictionary] = []
	for value: Variant in values:
		var command := command_from_json(value)
		if command.has("error"):
			return {"error": "Command %d: %s" % [commands.size() + 1, command["error"]]} if values.size() > 1 else command
		commands.append(command)
	var single := commands.size() == 1
	var err := validate(commands[0])
	if err != "":
		return {"error": ("Not a legal move right now: %s" % err) if single else ("Command 1 (%s) is not legal right now: %s. Nothing was done." % [describe(commands[0]), err])}
	if host == null:
		return {"error": "No game screen"}
	_seen_log.clear()
	_surprises.clear()
	_set_fast(fast)
	var run := {"index": 0, "steps": [], "stopped": "", "seen": _seen_ids()}
	err = host.apply_command(commands[0])
	if err != "":
		if fast:
			_set_fast(false)
		return {"error": err}
	var deadline := [Time.get_ticks_msec() + int(MAX_WAIT * 1000)]
	# Answer once the moves (and any reactions to them) have played out on screen.
	return {"wait": func() -> Variant:
		if fast:
			_set_fast(true)
		if host.view_busy() and Time.get_ticks_msec() < deadline[0]:
			return null
		var command: Dictionary = commands[run["index"]]
		var step := {"done": describe(command), "what_happened": take_seen()}
		var surprises := _surprises.duplicate()
		_surprises.clear()
		var now_seen := _seen_ids()
		for id: int in now_seen:
			if not run["seen"].has(id):
				var e := battle.get_unit(id)
				surprises.append("New enemy in sight: %s at %s" % [_who(e), _tile(e.pos)])
		run["seen"] = now_seen
		if not surprises.is_empty():
			step["surprises"] = surprises
		run["steps"].append(step)
		run["index"] += 1
		while run["index"] < commands.size() and run["stopped"] == "":
			if host.view_busy():
				run["stopped"] = "The last move was still playing out after %d seconds" % int(MAX_WAIT)
				break
			if not surprises.is_empty() and stop_on_surprise:
				run["stopped"] = "Stopped after a surprise: %s" % "; ".join(surprises)
				break
			var next: Dictionary = commands[run["index"]]
			var why := validate(next)
			if why == "":
				why = host.apply_command(next)
			if why != "":
				run["stopped"] = "%s is not legal now: %s" % [describe(next), why]
				break
			deadline[0] = Time.get_ticks_msec() + int(MAX_WAIT * 1000)
			return null
		if fast:
			_set_fast(false)
		var result := {}
		if single:
			result = step
		else:
			result["steps"] = run["steps"]
			if run["stopped"] != "":
				result["stopped"] = run["stopped"]
				var left := []
				for i in range(run["index"], commands.size()):
					left.append(command_to_json(commands[i]))
				result["not_done"] = left
		result.merge(_turn_summary())
		return {"result": result}}


## Waits (up to `timeout` seconds) for the player's side to be able to act, or for the battle to end. Once it's
## the side's turn the answer includes the battle state (without the map) unless include_state is false.
func wait_for_turn(timeout: float, include_state := true, fast := false) -> Dictionary:
	var side := player_team()
	var deadline := Time.get_ticks_msec() + int(clampf(timeout, 1.0, MAX_WAIT) * 1000)
	return {"wait": func() -> Variant:
		if fast:
			_set_fast(true)
		var ready := battle.winner != -1 or (battle.current_team == side and not _host_busy())
		if not ready and Time.get_ticks_msec() < deadline:
			return null
		if fast:
			_set_fast(false)
		var result := _turn_summary()
		result["what_happened"] = take_seen()
		_surprises.clear()
		if not ready:
			result["timed_out"] = true
			result["note"] = "Still the other side's turn (or a move is playing out). Call wait_for_turn again."
		elif include_state and battle.winner == -1:
			result["state"] = get_state()
		return {"result": result}}


## Fast playback on the battle screen (instant moves) while the agent waits, or back to the usual speed.
func _set_fast(on: bool) -> void:
	if host != null and host.has_method("set_fast_playback"):
		host.set_fast_playback(on)


func _seen_ids() -> Dictionary:
	var ids := {}
	for e in _seen_enemies(player_team()):
		ids[e.id] = true
	return ids


## Whose turn it is and how the battle stands, from the player's side.
func _turn_summary() -> Dictionary:
	var side := player_team()
	var summary := {
		"your_turn": battle.winner == -1 and battle.current_team == side and not _host_busy(),
		"current_side": battle.team_name(battle.current_team), "round": battle.round_number,
		"score": {"you": battle.victory_points[side], "enemy": battle.victory_points[1 - side], "to_win": battle.vp_to_win},
	}
	if battle.winner != -1:
		summary["game_over"] = true
		summary["winner"] = "draw" if battle.winner == Battle.DRAW else ("you" if battle.winner == side else "the enemy")
	else:
		var ready := 0
		for u in battle.alive_units(side):
			if battle.can_act(u) == "":
				ready += 1
		summary["your_units_that_can_act"] = ready if battle.current_team == side else 0
	return summary


# --- What the side saw happen ---

## The report lines gathered since the last call, and forgets them.
func take_seen() -> Array[String]:
	var lines := _seen_log.duplicate()
	_seen_log.clear()
	return lines


## Called with every list of events the screen plays: keeps a line for each thing the player's side could
## see happen, as the screen shows it.
func note_events(events: Array) -> void:
	var side := player_team()
	if side == -1:
		return
	for e: Dictionary in events:
		var line := _event_line(e, side)
		if line != "":
			_seen_log.append(line)
			if _is_surprise(e, side):
				_surprises.append(line.trim_suffix("."))
	if _seen_log.size() > LOG_LIMIT:
		_seen_log = _seen_log.slice(_seen_log.size() - LOG_LIMIT)
	if _surprises.size() > LOG_LIMIT:
		_surprises = _surprises.slice(_surprises.size() - LOG_LIMIT)


## Whether an event should stop a list of orders: an enemy shooting at one of our units, one of ours hurt,
## killed or panicking, or stepping on a mine.
func _is_surprise(e: Dictionary, side: int) -> bool:
	match e["type"]:
		"shot":
			var shooter := battle.get_unit(e["shooter"])
			var target := battle.get_unit(e["target"])
			return shooter != null and target != null and shooter.team != side and target.team == side
		"damage", "death", "mine":
			var u := battle.get_unit(e.get("unit", -1))
			return u != null and u.team == side
		"status":
			var u := battle.get_unit(e.get("unit", -1))
			return u != null and u.team == side and str(e.get("text", "")).begins_with("Panicked")
	return false


func _event_line(e: Dictionary, side: int) -> String:
	var u := battle.get_unit(e.get("unit", -1))
	var mine := u != null and u.team == side
	var visible := u != null and (mine or battle.team_sees(side, u))
	match e["type"]:
		"move":
			if mine:
				return "%s moved to %s." % [_who(u), _tile(e["path"][-1])]
			if visible:
				return "Enemy %s moved into sight at %s." % [_who(u), _tile(e["path"][-1])]
		"shot":
			var shooter := battle.get_unit(e["shooter"])
			var target := battle.get_unit(e["target"])
			if shooter.team == side or target.team == side or battle.team_sees(side, shooter):
				var what := "Overwatch: " if e["reaction"] else ""
				var chance := "" if e["result"] == "suppressing" else " (%d%%)" % e["chance"]
				return "%s%s shot at %s: %s%s." % [what, _who(shooter), _who(target), e["result"], chance]
		"damage":
			if visible:
				return "%s took %d damage, %d HP left." % [_who(u), e["amount"], e["hp"]]
		"death":
			return "%s was %s." % [_who(u), "knocked out" if u.vehicle else "killed"]
		"suppression":
			var was := "pinned" if e["previous"] >= Unit.PINNED_AT else ("suppressed" if e["previous"] >= Unit.SUPPRESSED_AT else "")
			if mine and e["state"] in ["suppressed", "pinned"] and e["state"] != was:
				return "%s is %s (suppression %d)." % [_who(u), e["state"], e["value"]]
		"status":
			if visible:
				return "%s: %s." % [_who(u), e["text"]]
		"throw":
			if mine or visible:
				return "%s threw a %s; it landed at %s." % [_who(u), e["kind"], _tile(e["center"])]
		"explosion":
			return "Explosion at %s." % str(_tile(e["center"]))
		"strike":
			return "A mortar round came down at %s." % str(_tile(e["center"]))
		"mortar_fire":
			return "%s fired the mortar." % _who(u) if mine else ("Enemy %s fired a mortar." % _who(u) if visible else "A mortar fired somewhere.")
		"mine":
			return "%s stepped on a mine at %s." % [_who(u), _tile(e["tile"])] if visible else "A mine went off at %s." % str(_tile(e["tile"]))
		"mines_spotted":
			if e["team"] == side:
				return "Mines spotted at %s." % ", ".join(e["tiles"].map(func(t: Vector2i) -> String: return str(_tile(t))))
		"objective":
			return "%s took the %s." % [battle.team_name(e["owner"]), battle.objectives[e["index"]]["name"]]
		"reinforcements":
			return "%s reinforcements arrived." % battle.team_name(e["team"])
		"turn":
			return "Round %d: %s's turn." % [e["round"], battle.team_name(e["team"])]
		"game_over":
			var winner: int = e["winner"]
			return "The battle is over: %s." % ("a draw" if winner == Battle.DRAW else ("you won" if winner == side else "you lost"))
	return ""


func _who(u: Unit) -> String:
	return "%s %s (id %d)" % [u.role, u.name, u.id]


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
	if value.has("stance"):
		command["stance"] = int(value["stance"])
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
	if cmd in ["move", "grenade", "smoke", "mortar", "shoot_object", "clear_mine", "tunnel", "trap", "detonate"] and not command.has("tile"):
		return "%s needs a tile" % cmd
	match cmd:
		"move":
			return battle.can_move(u, tile)
		"shoot", "aimed_shot", "suppress":
			if target == null or target.team == side or not target.is_alive() or not battle.team_sees(side, target):
				return "Unknown target: not an enemy in sight"
			if cmd == "aimed_shot":
				return battle.can_aimed_shot(u, target)
			return battle.can_suppress(u, target) if cmd == "suppress" else battle.can_shoot(u, target)
		"stance":
			return battle.can_change_stance(u, command.get("stance", -1)) if command.has("stance") else "stance needs 0 (stand), 1 (crouch) or 2 (prone)"
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
		"shoot_object":
			return battle.can_shoot_object(u, tile)
		"clear_mine":
			return battle.can_clear_mine(u, tile)
		"tunnel":
			return battle.can_tunnel(u, tile)
		"trap":
			return battle.can_lay_trap(u, tile)
		"detonate":
			return battle.can_detonate(u, tile)
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
	if cmd == "stance" and command.get("stance", -1) in [0, 1, 2]:
		text = "%s: %s" % [u.name, ["stand up", "crouch", "go prone"][command["stance"]]]
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


## Whether the unit's weapon could fire after it has spent an action moving (a machine gun packs up when it
## moves; an empty weapon needs reloading first).
func _can_shoot_after_moving(u: Unit) -> bool:
	return u.ammo > 0 and not u.weapon.needs_setup


## The unit's odds against an enemy if it stood on `tile` ({hit, crit, flanked}), or null without a line of sight.
## Puts the unit back afterwards.
func _odds_from(u: Unit, tile: Vector2i, e: Unit) -> Variant:
	var saved := u.pos
	u.pos = tile
	var result: Variant = null
	if battle.can_see(u, e):
		var odds := battle.shot_odds(u, e)
		result = {"hit": odds["hit"], "crit": odds["crit"], "flanked": odds["flanked"]}
	u.pos = saved
	return result


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


func _team_name(team: int) -> Variant:
	return battle.team_name(team) if team >= 0 and team < Battle.TEAM_COUNT else null
