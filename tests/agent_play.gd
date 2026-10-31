extends SceneTree
## An agent plays a whole battle over the agent link, the way Claude Code would: the real battle screen in
## "Agent vs AI" mode, and HTTP requests to its MCP server. The "agent" here just takes the game's own
## suggestion each time (suggest_move), makes it with execute_command, and waits with wait_for_turn.
##   Godot --headless --path . -s tests/agent_play.gd [-- --port=N]
## Saves go to a throwaway folder and no settings are written. Exits non-zero if the battle doesn't finish.

const MAX_COMMANDS := 3000
const MAX_SECONDS := 900

var _port := 26500
var _token := ""
var _id := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			_port = arg.trim_prefix("--port=").to_int()
	GameSession.save_dir = OS.get_temp_dir().path_join("normandy-agent-play-%d" % OS.get_process_id())
	# Fast playback, in memory only.
	GameSettings.ensure_loaded()
	GameSettings.instant_movement = true
	GameSettings.own_speed = 3
	GameSettings.opponent_speed = 3
	GameSettings.confirm_end_turn = false
	AdvisorSettings.load_settings()
	AdvisorSettings.mcp_port = _port
	AdvisorSettings.agent_may_act = false
	_token = AdvisorSettings.token()
	var built := GameSession.build_skirmish({"map": "random", "size": 44, "seed": 1944})
	GameSession.campaign = null
	GameSession.war = null
	GameSession.start_battle(built[0], [false, true], built[1])
	GameSession.agent_team = 0
	change_scene_to_file(GameSession.BATTLE_SCENE)
	await create_timer(1.0).timeout

	var started := Time.get_ticks_msec()
	var tools: Array = (await _rpc("tools/list", {}))["result"]["tools"].map(func(t: Dictionary) -> String: return t["name"])
	print("tools: ", ", ".join(tools))
	var commands := 0
	var rejected := 0
	var last := {}
	var batch_checked := false
	var batch_ok := false
	while commands < MAX_COMMANDS and Time.get_ticks_msec() - started < MAX_SECONDS * 1000:
		var turn: Dictionary = await _tool("wait_for_turn", {"timeout_seconds": 20})
		if turn.get("game_over", false):
			last = turn
			break
		if not turn.get("your_turn", false):
			continue
		if not batch_checked:
			batch_checked = true
			batch_ok = await _check_batch(turn.get("state", {}))
		var advice: Dictionary = await _tool("suggest_move", {})
		var command: Dictionary = advice.get("command", {"cmd": "end_turn"})
		var done: Dictionary = await _tool("execute_command", {"command": command})
		if done.has("error"):
			rejected += 1
			if rejected > 20:
				break
			await _tool("execute_command", {"command": {"cmd": "end_turn"}})
		commands += 1
		last = done
		if commands == 1:
			print("first move: ", JSON.stringify(done).left(400))
	var state: Dictionary = await _tool("get_state", {})
	var battle := GameSession.battle
	print("commands %d, rejected %d, winner %d, round %d, score %s" % [commands, rejected, battle.winner, battle.round_number, str(battle.victory_points)])
	print("last report: ", JSON.stringify(last).left(400))
	print("state says winner: ", state.get("winner"))
	print("batch of orders: ", "OK" if batch_ok else "FAILED")
	var ok: bool = batch_ok and battle.winner != -1 and state.get("winner") != null and last.get("game_over", false)
	print("AGENT GAME " + ("FINISHED" if ok else "DID NOT FINISH"))
	DirAccess.remove_absolute(GameSession.slot_path("skirmish"))
	quit(0 if ok else 1)


## On the first turn: wait_for_turn brought the state, and one execute_command call with a list of orders
## (two riflemen each move to a 1-action spot from get_unit_options, then overwatch) plays them all, fast.
func _check_batch(state: Dictionary) -> bool:
	if not state.has("your_units") or state.has("map"):
		print("batch check: wait_for_turn gave no state (or a map)")
		return false
	var orders := []
	for u: Dictionary in state["your_units"]:
		if u["role"] != "Rifleman" or u["actions"] < 2 or orders.size() >= 4:
			continue
		var options: Dictionary = await _tool("get_unit_options", {"unit": u["id"]})
		for spot: Dictionary in options.get("moves", {}).get("best_spots", []):
			if spot["actions"] == 1:
				orders.append({"cmd": "move", "unit": u["id"], "tile": spot["tile"]})
				orders.append({"cmd": "overwatch", "unit": u["id"]})
				break
	if orders.is_empty():
		print("batch check: no riflemen to order")
		return false
	var done: Dictionary = await _tool("execute_command", {"commands": orders, "fast": true})
	print("batch: ", JSON.stringify(done).left(500))
	return done.has("steps") and not done["steps"].is_empty() and (done["steps"].size() == orders.size() or done.has("stopped"))


## Calls a tool; returns its parsed result, or {"error": text}.
func _tool(name: String, arguments: Dictionary) -> Dictionary:
	var reply: Dictionary = await _rpc("tools/call", {"name": name, "arguments": arguments})
	if reply.has("error"):
		return {"error": reply["error"]}
	var content: Dictionary = reply["result"]["content"][0]
	if reply["result"]["isError"]:
		return {"error": content["text"]}
	return JSON.parse_string(content["text"])


func _rpc(method: String, params: Dictionary) -> Dictionary:
	_id += 1
	var body := JSON.stringify({"jsonrpc": "2.0", "id": _id, "method": method, "params": params})
	var http := HTTPClient.new()
	http.connect_to_host("127.0.0.1", _port)
	while http.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		http.poll()
		await process_frame
	http.request(HTTPClient.METHOD_POST, "/mcp", ["Content-Type: application/json", "Authorization: Bearer " + _token, "Host: 127.0.0.1"], body)
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		await process_frame
	var data := PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_BODY or (http.get_status() == HTTPClient.STATUS_CONNECTED and not http.has_response()):
		http.poll()
		var chunk := http.read_response_body_chunk()
		data.append_array(chunk)
		if chunk.is_empty():
			await process_frame
	http.close()
	var parsed: Variant = JSON.parse_string(data.get_string_from_utf8())
	return parsed if parsed is Dictionary else {"error": "bad reply: " + data.get_string_from_utf8().left(200)}
