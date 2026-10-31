extends SceneTree
## Two copies of the game playing each other online, AI on both sides, to check that every command
## arrives and both games stay identical. Start the host first, then the joiner:
##   Godot --headless --path . -s tests/net_match.gd -- host [port] [map size, 0 = village] [options]
##   Godot --headless --path . -s tests/net_match.gd -- join [port] [options]
## Options:
##   tamper          the joiner secretly rolls an extra die in round 3 (or, when resuming, right after
##                   loading), and both sides must notice.
##   stop N          both leave once round N starts, keeping their online saves (see tests/net_resume.sh).
##   resume          instead of a new game, the host offers its saved online game and the joiner adopts it.
##   --save-dir=DIR  where this copy keeps its saves (read by GameSession), so two copies don't share one.
##                   Without it the saves go to a throwaway folder, never the player's own.
##   --password=P    the game's password (default: none; both sides must use the same one).
##   refused         the joiner expects to be turned away, and prints why ("REFUSED: ...").
##   --local-port=N  the joiner sends from port N, and the host lets 127.0.0.1:N in (hole punching).

var _done := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool: return not a.begins_with("--"))
	var hosting: bool = args[0] == "host"
	var port := int(args[1]) if args.size() > 1 else 24944
	var tamper := args.has("tamper")
	var resume := args.has("resume")
	var stop_round := int(args[args.find("stop") + 1]) if args.has("stop") else 0
	if GameSession.save_dir == "user://":
		GameSession.save_dir = OS.get_temp_dir().path_join("normandy-net-match-%d" % OS.get_process_id())
	var net: Node = root.get_node("Net")
	var local_port := 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--password="):
			net.password = arg.trim_prefix("--password=")
		elif arg.begins_with("--local-port="):
			local_port = arg.trim_prefix("--local-port=").to_int()
	if args.has("refused"):
		net.connection_failed.connect(func() -> void: _finish("REFUSED: " + net.last_error))
	net.desynced.connect(func(reason: String) -> void: _finish("DESYNC DETECTED: " + reason))
	net.disconnected.connect(func() -> void: _finish("DISCONNECTED"))
	net.turn_agreed.connect(func(turn_index: int, checksum: String) -> void: GameSession.on_turn_agreed(turn_index, checksum, net.local_team))
	if resume:
		if not await _resume(net, hosting, port, tamper):
			return
	else:
		var setup := {}
		if hosting:
			net.host(port)
			if local_port != 0:
				net.let_in("127.0.0.1:%d" % local_port)
			await net.peer_joined
			var size := int(args[2]) if args.size() > 2 and args[2].is_valid_int() else 0
			setup = {"map": "village" if size == 0 else "random", "size": size, "seed": 4711, "game_id": GameSession.new_game_id()}
			net.send_setup(setup)
		else:
			net.join("127.0.0.1", port, local_port)
			setup = await net.setup_received
		var built := GameSession.build_skirmish(setup)
		GameSession.start_online(built[0], built[1], net.local_team, setup["game_id"], "test", hosting)
		GameSession.battle.start()
	var battle := GameSession.battle
	var ai := TacticalAI.new(battle, net.local_team)
	var remote := RemotePlayer.new(battle, net.remote_team(), net)
	var commands := 0
	var tampered := false
	while battle.winner == -1 and not _done:
		if stop_round > 0 and battle.round_number >= stop_round:
			_done = true
			# Wait for the other side's word that it agrees with our last turn change, then leave.
			await create_timer(2.0).timeout
			var saved := GameSession.peek("online")
			print("LEFT at round %d, turn %d, checksum %s; saved turn %d, checksum %s" % [battle.round_number, battle.turn_index, battle.checksum().left(12), saved.get("turn_index", -1), str(saved.get("checksum", "none")).left(12)])
			quit()
			return
		if tamper and not resume and not tampered and battle.round_number == 3:
			battle.rng.randi()
			tampered = true
		if battle.current_team == net.local_team:
			var command := ai.decide()
			battle.execute(command)
			net.send_command(command, battle.checksum())
		else:
			if await remote.next_events() == null:
				break
		commands += 1
	if not _done:
		_done = true
		# Let the last command reach the other side (and its word that it agrees come back) before hanging up.
		await create_timer(0.5).timeout
		print("%s: winner %d after %d rounds, %d commands, checksum %s, online save %s" % ["FINISHED" if battle.winner != -1 else "STOPPED", battle.winner, battle.round_number, commands, battle.checksum().left(12), "kept" if GameSession.has_save("online") else "cleared"])
		quit()


## Continues the saved online game. Returns false if that didn't work (and the run is finishing).
func _resume(net: Node, hosting: bool, port: int, tamper: bool) -> bool:
	if hosting:
		var offer := GameSession.online_offer()
		if offer.is_empty() or not GameSession.resume_online(offer, offer["team"], "test", true):
			_finish("NO SAVE TO CONTINUE")
			return false
		net.host(port, offer["team"])
		await net.peer_joined
		net.send_resume(offer)
		print("OFFERED round %d, turn %d, checksum %s" % [offer["round"], offer["turn_index"], offer["checksum"].left(12)])
	else:
		net.join("127.0.0.1", port)
		var offer: Dictionary = await net.resume_offered
		var difference := GameSession.compare_online(offer)
		print("JOINER: " + ("saves match" if difference == "" else difference + " Adopting the host's."))
		if not GameSession.resume_online(offer, net.local_team, "test", false):
			net.report_desync("The host's saved battle doesn't load the same here.")
			return false
		if tamper:
			GameSession.battle.rng.randi()
		net.accept_resume(GameSession.battle.checksum())
	await net.resume_started
	if _done:
		return false
	GameSession.save_online(net.local_team)
	print("RESUMED at round %d, turn %d, checksum %s" % [GameSession.battle.round_number, GameSession.battle.turn_index, GameSession.battle.checksum().left(12)])
	return true


func _finish(message: String) -> void:
	if _done:
		return
	_done = true
	print(message)
	# Give our last message time to reach the other side, which may be busy thinking through its turn.
	await create_timer(5.0).timeout
	quit()
