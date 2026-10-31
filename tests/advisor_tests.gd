extends SceneTree
## Headless tests for move suggestions (AdvisorAI) and the agent link (McpGameTools, McpServer).
## Run: Godot --headless --path . -s tests/advisor_tests.gd

var _failures := 0
var _checks := 0


func _initialize() -> void:
	for method in get_method_list():
		var test_name: String = method["name"]
		if test_name.begins_with("test_"):
			call(test_name)
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


## A battle on an open map; specs are [role, team, pos].
func make_battle(specs: Array, size := Vector2i(16, 16)) -> Battle:
	var units: Array[Unit] = []
	for spec in specs:
		units.append(Unit.create(units.size(), "U%d" % units.size(), spec[0], spec[1], spec[2]))
	var battle := Battle.new(TacticalMap.new(size.x, size.y), units, 1234)
	battle.start()
	return battle


func ids_in(list: Array) -> Array:
	return list.map(func(entry: Dictionary) -> int: return entry["id"])


# --- Fog of war ---

func test_state_hides_enemies_out_of_sight() -> void:
	# Enemy 1 is in plain view; enemy 2 is behind a wall of rocks, far away.
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(6, 2)], ["Rifleman", 1, Vector2i(28, 28)]], Vector2i(32, 32))
	for y in range(20, 32):
		battle.map.set_object(Vector2i(20, y), Cover.FULL, "rock")
	var tools := McpGameTools.new(battle)
	tools.team = 0
	var state := tools.get_state({"full_map": true})
	check_eq(ids_in(state["enemies_in_sight"]), [1], "only the enemy in sight is listed")
	var text := JSON.stringify(state)
	check(not text.contains("[28,28]"), "the hidden enemy's position appears nowhere in the state")
	var drawn := "\n".join(state["map"]["rows"].slice(1))
	check(drawn.contains("a") and not drawn.contains("b"), "only the enemy in sight is drawn on the map")
	check(state["your_units"][0].has("weapon") and state["enemies_in_sight"][0].get("weapon") is String, "enemies show only their weapon's name")
	check(not state["enemies_in_sight"][0].has("ammo") and not state["enemies_in_sight"][0].has("kit"), "no enemy ammo or kit")


func test_last_seen_enemies_are_remembered_not_tracked() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(6, 2)]], Vector2i(32, 32))
	var tools := McpGameTools.new(battle)
	tools.team = 0
	tools.get_state()
	# A rock wall goes up between us and he slips away: we remember where we saw him, not where he went.
	for y in range(0, 32):
		battle.map.set_object(Vector2i(4, y), Cover.FULL, "rock")
	battle.get_unit(1).pos = Vector2i(20, 20)
	var state := tools.get_state()
	check(state["enemies_in_sight"].is_empty(), "enemy out of sight")
	check_eq(state["enemies_last_seen"].size(), 1, "remembered")
	check_eq(state["enemies_last_seen"][0]["last_seen"], [6, 2], "at the last place we saw him")
	check(not JSON.stringify(state).contains("[20,20]"), "his real position stays hidden")


func test_tools_refuse_hidden_targets_alike() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(28, 28)], ["Rifleman", 1, Vector2i(29, 29)]], Vector2i(32, 32))
	battle.get_unit(2).hp = 0
	var tools := McpGameTools.new(battle)
	tools.team = 0
	# A live enemy out of sight and a dead one give the same answer, so ids reveal nothing.
	check_eq(tools.validate({"cmd": "shoot", "unit": 0, "target": 1}), tools.validate({"cmd": "shoot", "unit": 0, "target": 2}), "hidden and dead targets look alike")
	var preview: Dictionary = tools.preview(0, [3, 3])["result"]
	check(preview["enemies_in_sight"].is_empty(), "preview ignores enemies out of sight")


func test_advisor_does_not_know_the_enemy_start() -> void:
	# Mid-battle, the opponent AI's starting guess would be the enemy's real position; the advisor's isn't.
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 8)], ["Rifleman", 1, Vector2i(30, 30)]], Vector2i(32, 32))
	var advisor := AdvisorAI.new(battle, 0)
	check_eq(advisor._objective, Vector2(29, 8), "guesses from the mirrored map")


# --- Suggestions ---

func test_suggestion_is_a_legal_command() -> void:
	var battle := NormandyScenario.build(7)
	battle.start()
	var tools := McpGameTools.new(battle)
	tools.team = battle.current_team
	for i in 6:
		var suggestion := tools.advisor_for(battle.current_team).suggest()
		check(not suggestion.has("error"), "suggests something")
		var command: Dictionary = suggestion["command"]
		check(suggestion["text"] is String and suggestion["text"] != "", "with an explanation")
		check_eq(tools.validate(command), "", "%s is legal" % command)
		# The JSON form round-trips back to the same engine command.
		var json := McpGameTools.command_to_json(command)
		check_eq(tools.command_from_json(JSON.parse_string(JSON.stringify(json))), command, "JSON round trip")
		var events := battle.execute(command)
		check(command["cmd"] == "end_turn" or not events.is_empty(), "the engine accepts %s" % command)
		tools.team = battle.current_team


func test_suggestion_matches_the_ai_and_changes_nothing() -> void:
	var battle := NormandyScenario.build(11)
	battle.start()
	var team := battle.current_team
	var before := battle.checksum()
	var suggestion := AdvisorAI.new(battle, team).suggest()
	check_eq(battle.checksum(), before, "suggesting changes no game state")
	var opponent_ai := TacticalAI.new(battle, team)
	# The same planner picks the same move (only the starting guess differs, before contact).
	check_eq(suggestion["command"]["cmd"], opponent_ai.decide()["cmd"], "same kind of move as the AI")


func test_suggest_for_one_unit() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["SMG", 0, Vector2i(2, 4)], ["Rifleman", 1, Vector2i(8, 3)]])
	battle.map.set_object(Vector2i(3, 2), Cover.HALF, "sandbags")
	var advisor := AdvisorAI.new(battle, 0)
	var suggestion := advisor.suggest(battle.get_unit(1))
	check_eq(suggestion["unit"], 1, "about the unit asked for")
	check_eq(suggestion["command"]["unit"], 1, "commands that unit")
	check(advisor.suggest(battle.get_unit(2)).has("error"), "can't advise the enemy")


func test_shot_explanation() -> void:
	# An enemy in the open, already in sight, and badly hurt: the advice is to shoot him.
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(6, 2)]])
	battle.get_unit(1).hp = 2
	battle.get_unit(0).actions = 1
	var suggestion := AdvisorAI.new(battle, 0).suggest()
	check_eq(suggestion["command"], {"cmd": "shoot", "unit": 0, "target": 1}, "takes the shot")
	check(suggestion["text"].contains("% hit") and suggestion["text"].contains("flanked"), "explains odds and flank: %s" % suggestion["text"])


# --- Tools ---

func test_unit_options_and_preview() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(9, 2)]])
	battle.map.set_edge(Vector2i(4, 4), Vector2i(5, 4), Cover.FULL, "hedge")
	var tools := McpGameTools.new(battle)
	tools.team = 0
	var options: Dictionary = tools.unit_options(0)["result"]
	check(options["allowed"].has("move") and options["allowed"].has("shoot"), "can move and shoot")
	check_eq(options["targets"][0]["target"], 1, "odds against the enemy in sight")
	check(not options["moves"]["best_spots"].is_empty(), "lists cover spots")
	var preview: Dictionary = tools.preview(0, [4, 4])["result"]
	check(preview["reachable"], "the hedge is in reach")
	check_eq(preview["cover"].get("E"), "full", "full cover east")
	check_eq(preview["enemies_in_sight"][0]["your_cover"], "full", "covered against the enemy")
	check_eq(battle.get_unit(0).pos, Vector2i(2, 2), "preview puts the unit back")
	check(tools.unit_options(1).has("error"), "no options for enemy units")


func test_execute_needs_permission() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(9, 2)]])
	var tools := McpGameTools.new(battle)
	tools.team = 0
	AdvisorSettings.agent_may_act = false
	check(tools.call_tool("execute_command", {"command": {"cmd": "move", "unit": 0, "tile": [3, 3]}}).has("error"), "refused by default")
	check_eq(battle.get_unit(0).pos, Vector2i(2, 2), "nothing moved")


# --- MCP protocol ---

func test_mcp_protocol() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(9, 2)]])
	var tools := McpGameTools.new(battle)
	tools.team = 0
	var server := McpServer.new(tools, "secret")
	var init: Dictionary = server.handle_rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}}})
	check_eq(init["result"]["protocolVersion"], "2025-06-18", "agrees on the protocol version")
	check(init["result"]["capabilities"].has("tools"), "offers tools")
	check_eq(server.handle_rpc({"jsonrpc": "2.0", "method": "notifications/initialized"}), null, "notifications get no reply")
	var listed: Array = server.handle_rpc({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})["result"]["tools"]
	var names := listed.map(func(t: Dictionary) -> String: return t["name"])
	for name in ["get_state", "get_unit_options", "preview", "suggest_move", "propose_move", "execute_command"]:
		check(names.has(name), "lists %s" % name)
	var call: Dictionary = server.handle_rpc({"jsonrpc": "2.0", "id": 3.0, "method": "tools/call", "params": {"name": "get_state", "arguments": {}}})
	check_eq(call["id"], 3, "echoes the id as an integer")
	check(not call["result"]["isError"], "get_state works")
	check(JSON.parse_string(call["result"]["content"][0]["text"]) is Dictionary, "returns JSON text")
	check_eq(server.handle_rpc({"jsonrpc": "2.0", "id": 4, "method": "nope"})["error"]["code"], -32601, "unknown method")
	check(names.has("wait_for_turn"), "lists wait_for_turn")
	# Waiting tools answer later: handle_http hands back a pending call, which answers at once here
	# because it is already our turn.
	var request := {"method": "POST", "path": "/mcp", "query": {}, "headers": {"authorization": "Bearer secret", "host": "127.0.0.1"},
			"body": JSON.stringify({"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "wait_for_turn", "arguments": {}}})}
	var pending: Array = server.handle_http(request)
	check_eq(pending[0], McpServer.PENDING, "wait_for_turn is answered later")
	var waited: Dictionary = pending[1]["wait"].call()["result"]
	check(waited["your_turn"], "and says it's our turn")
	tools.note_events([{"type": "move", "unit": 0, "path": [Vector2i(2, 2), Vector2i(3, 2)]}, {"type": "move", "unit": 1, "path": [Vector2i(30, 30)]}])
	check_eq(tools.take_seen().size(), 2, "reports our move and the enemy moving in sight")
	check(tools.take_seen().is_empty(), "each report is given once")
	var batch := {"method": "POST", "path": "/mcp", "query": {}, "headers": {"authorization": "Bearer secret", "host": "127.0.0.1"},
			"body": JSON.stringify([{"jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": {"name": "wait_for_turn", "arguments": {}}}])}
	check(server.handle_http(batch)[2].contains("can't be called in a batch"), "waiting tools refuse batches")


func test_mcp_http_rules() -> void:
	var tools := McpGameTools.new(make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(9, 2)]]))
	var server := McpServer.new(tools, "secret")
	var body := JSON.stringify({"jsonrpc": "2.0", "id": 1, "method": "ping"})
	var raw := "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:27001\r\nAuthorization: Bearer secret\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s" % [body.to_utf8_buffer().size(), body]
	var request := McpServer.parse_http(raw.to_utf8_buffer())
	check_eq(request["path"], "/mcp", "parses the path")
	check_eq(server.handle_http(request)[0], 200, "authorised ping")
	check(McpServer.parse_http(raw.left(raw.length() - 3).to_utf8_buffer()).is_empty(), "waits for the whole body")
	var wrong := request.duplicate(true)
	wrong["headers"]["authorization"] = "Bearer guess"
	check_eq(server.handle_http(wrong)[0], 401, "wrong token refused")
	var web := request.duplicate(true)
	web["headers"]["origin"] = "https://evil.example"
	check_eq(server.handle_http(web)[0], 403, "web pages refused")
	var get := request.duplicate(true)
	get["method"] = "GET"
	check_eq(server.handle_http(get)[0], 405, "no event stream")
	var note := request.duplicate(true)
	note["body"] = JSON.stringify({"jsonrpc": "2.0", "method": "notifications/initialized"})
	check_eq(server.handle_http(note)[0], 202, "notifications accepted")


# --- Faster agent turns ---

## Stands in for the battle screen: carries out commands at once and tells the tools what happened.
class FakeHost:
	var battle: Battle
	## Weak, so the host and the tools (which hold the host) don't keep each other alive.
	var tools: WeakRef
	var fast_calls: Array[bool] = []

	func player_team() -> int:
		return 0

	func agent_plays() -> bool:
		return true

	func is_online() -> bool:
		return false

	func is_busy() -> bool:
		return battle.current_team != 0

	func view_busy() -> bool:
		return false

	func show_proposal(_suggestion: Dictionary) -> void:
		pass

	func apply_command(command: Dictionary) -> String:
		var events := battle.execute(command)
		if events.is_empty():
			return "Nothing happened"
		tools.get_ref().note_events(events)
		return ""

	func set_fast_playback(on: bool) -> void:
		fast_calls.append(on)


func make_hosted(specs: Array) -> Array:
	var battle := make_battle(specs)
	var host := FakeHost.new()
	host.battle = battle
	var tools := McpGameTools.new(battle, host)
	host.tools = weakref(tools)
	return [battle, tools, host]


## Runs a waiting tool's answer to the end.
func finish(outcome: Dictionary) -> Dictionary:
	if not outcome.has("wait"):
		return outcome
	var answer: Variant = outcome["wait"].call()
	var guard := 0
	while answer == null and guard < 100:
		answer = outcome["wait"].call()
		guard += 1
	return answer


func test_state_has_no_map_unless_asked() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(6, 2)]])
	var tools := McpGameTools.new(battle)
	tools.team = 0
	var state := tools.get_state()
	check(not state.has("map"), "no map by default")
	check(tools.get_state({"map": true}).has("map"), "map when asked")
	check(tools.get_state({"area": [0, 0, 5, 5]}).has("map"), "map for an area")
	check_eq(state["threats"].size(), 1, "the enemy in the open threatens our rifleman")
	check_eq(state["threats"][0]["seen_by"][0]["enemy"], 1, "names the enemy")
	check(state["threats"][0]["seen_by"][0]["their_hit"] > 0, "with his odds")


func test_unit_option_filters() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(9, 2)]])
	battle.map.set_edge(Vector2i(4, 4), Vector2i(5, 4), Cover.FULL, "hedge")
	battle.objectives.append({"name": "Barn", "center": Vector2(4.5, 6.5), "radius": 1.5, "owner": -1})
	var tools := McpGameTools.new(battle)
	tools.team = 0
	var options: Dictionary = tools.unit_options(0, true)["result"]
	check_eq(options["moves"]["all_tiles"][0].size(), 4, "all_tiles carry the actions used")
	check(options["moves"]["best_spots"].any(func(s: Dictionary) -> bool: return s.has("shots")), "spots list the shots from there")
	var in_barn: Dictionary = tools.unit_options(0, false, {"objective": "barn"})["result"]["moves"]
	check(not in_barn["matching_spots"].is_empty(), "finds tiles in the objective")
	check(in_barn["matching_spots"].all(func(s: Dictionary) -> bool: return s["objective"] == "Barn"), "only tiles in the objective")
	var covered: Array = tools.unit_options(0, false, {"covered_from": 1, "limit": 30})["result"]["moves"]["matching_spots"]
	check(covered.any(func(s: Dictionary) -> bool: return s["tile"] == [4, 4]), "the hedge covers from the enemy")
	check(covered.all(func(s: Dictionary) -> bool: return s["vs_enemies_in_sight"]["exposed"] == 0), "no exposed tiles")
	var shooting: Array = tools.unit_options(0, false, {"shoot_target": 1})["result"]["moves"]["matching_spots"]
	check(not shooting.is_empty(), "tiles to shoot from")
	check(shooting.all(func(s: Dictionary) -> bool: return s["actions"] == 1 and s["shots"][0]["target"] == 1), "1-action moves with a shot at the target")
	check(tools.unit_options(0, false, {"objective": "Nowhere"}).has("error"), "unknown objective")
	check(tools.unit_options(0, false, {"shoot_target": 0}).has("error"), "the target must be an enemy")
	check_eq(battle.get_unit(0).pos, Vector2i(2, 2), "the unit is put back")


func test_execute_runs_a_list() -> void:
	var hosted := make_hosted([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(14, 14)]])
	var battle: Battle = hosted[0]
	var tools: McpGameTools = hosted[1]
	var host: FakeHost = hosted[2]
	var answer: Dictionary = finish(tools.call_tool("execute_command", {"fast": true, "commands": [
			{"cmd": "move", "unit": 0, "tile": [3, 2]}, {"cmd": "overwatch", "unit": 0}]}))["result"]
	check_eq(answer["steps"].size(), 2, "both ran")
	check(not answer.has("stopped"), "nothing stopped them")
	check_eq(battle.get_unit(0).pos, Vector2i(3, 2), "first unit moved")
	check(battle.get_unit(0).overwatch, "and is on overwatch")
	check_eq(host.fast_calls.front(), true, "fast playback switched on")
	check_eq(host.fast_calls.back(), false, "and off again")
	# A command that isn't legal any more stops the list; the rest is reported, not run.
	answer = finish(tools.call_tool("execute_command", {"commands": [
			{"cmd": "move", "unit": 1, "tile": [3, 5]}, {"cmd": "shoot", "unit": 1, "target": 2}, {"cmd": "end_turn"}]}))["result"]
	check_eq(answer["steps"].size(), 1, "stops at the illegal command")
	check_eq(battle.get_unit(1).pos, Vector2i(3, 5), "after the legal move")
	check(answer["stopped"].contains("not legal"), "says why: %s" % answer.get("stopped"))
	check_eq(answer["not_done"].size(), 2, "lists what didn't run")
	check_eq(battle.current_team, 0, "the turn wasn't ended")
	check(tools.call_tool("execute_command", {"commands": [{"cmd": "fly", "unit": 0}]}).has("error"), "unknown commands are refused")
	check(tools.call_tool("execute_command", {"commands": [{"unit": 0}]}).has("error"), "malformed commands are refused up front")


func test_execute_stops_on_a_surprise() -> void:
	var hosted := make_hosted([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 0, Vector2i(2, 9)], ["Rifleman", 1, Vector2i(8, 2)]])
	var battle: Battle = hosted[0]
	var tools: McpGameTools = hosted[1]
	battle.get_unit(2).overwatch = true
	var answer: Dictionary = finish(tools.call_tool("execute_command", {"commands": [
			{"cmd": "move", "unit": 0, "tile": [4, 2]}, {"cmd": "move", "unit": 1, "tile": [3, 9]}]}))["result"]
	check_eq(answer["steps"].size(), 1, "stopped after the first move")
	check(answer["steps"][0].has("surprises"), "the overwatch shot is a surprise")
	check(answer["stopped"].begins_with("Stopped after a surprise"), "says so")
	check_eq(battle.get_unit(1).pos, Vector2i(2, 9), "the second unit stayed put")


func test_wait_for_turn_includes_state() -> void:
	var hosted := make_hosted([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(14, 14)]])
	var tools: McpGameTools = hosted[1]
	var answer: Dictionary = finish(tools.call_tool("wait_for_turn", {}))["result"]
	check(answer["your_turn"], "our turn")
	check(answer["state"]["your_units"].size() == 1 and not answer["state"].has("map"), "with the state, no map")
	check(not finish(tools.call_tool("wait_for_turn", {"include_state": false}))["result"].has("state"), "unless asked not to")


func test_instructions_explain_objectives() -> void:
	var hosted := make_hosted([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(14, 14)]])
	var text: String = hosted[1].instructions()
	check(text.contains("stays held after they leave"), "objectives stay held")
	check(text.contains("NEXT turn"), "when mortar rounds land")
	check(text.contains("commands list"), "mentions batching")
