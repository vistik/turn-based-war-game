extends SceneTree
## Two copies of the game playing an online two-player campaign against each other, AI on both sides, to
## check that every message and command arrives and both games stay identical. Start the host first, then
## the joiner:
##   Godot --headless --path . -s tests/net_match.gd -- host [port] [map size, 0 = a mix] [options]
##   Godot --headless --path . -s tests/net_match.gd -- join [port] [options]
## Each map, both sides seal their orders (the AI's), reveal them once both are in, and fight the battle.
## Options:
##   maps N          host: the campaign's number of maps (default 1: a single battle).
##   tamper          the joiner secretly rolls an extra die in round 3 (or, when resuming, right after
##                   loading), and both sides must notice.
##   cheat           the joiner reveals other orders than it sealed, and both sides must notice.
##   stop N          both leave once round N starts, keeping their online saves (see tests/net_resume.sh).
##   resume          instead of a new campaign, the host offers its saved one and the joiner adopts it.
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
			var maps := int(args[args.find("maps") + 1]) if args.has("maps") else 1
			var war := WarCampaign.create(maps, 4711, [false, false], Theatres.DEFAULT, {"size": size, "supply": 60 * maps, "max_spend": 60})
			setup = {"war": war.to_dict(), "game_id": GameSession.new_game_id()}
			net.send_setup(setup)
		else:
			net.join("127.0.0.1", port, local_port)
			setup = await net.setup_received
		GameSession.start_online_war(WarCampaign.from_dict(setup["war"]), net.local_team, setup["game_id"], "test", hosting)
		GameSession.save_online(net.local_team)
	var war := GameSession.war
	var commands := 0
	while not war.is_over() and not _done:
		if GameSession.battle == null:
			if not await _give_orders(net, args.has("cheat") and not hosting):
				return
			var m := war.current_map()
			GameSession.start_online_battle(war.build_battle(), "Map %d: %s" % [war.current + 1, m["name"]])
			GameSession.save_online(net.local_team)
			GameSession.battle.start()
		var battle := GameSession.battle
		var ai := TacticalAI.new(battle, net.local_team)
		var remote := RemotePlayer.new(battle, net.remote_team(), net)
		var tampered := false
		while battle.winner == -1 and not _done:
			if stop_round > 0 and battle.round_number >= stop_round:
				_done = true
				# Wait for the other side's word that it agrees with our last turn change, then leave.
				await create_timer(2.0).timeout
				var saved := GameSession.peek("online")
				print("LEFT at map %d, round %d, turn %d, checksum %s; saved turn %d, checksum %s" % [war.current + 1, battle.round_number, battle.turn_index,
						GameSession.online_checksum().right(12), saved.get("turn_index", -1), str(saved.get("checksum", "none")).right(12)])
				quit()
				return
			if tamper and not resume and not tampered and battle.round_number == 3:
				battle.rng.randi()
				tampered = true
			if battle.current_team == net.local_team:
				var command := ai.decide()
				battle.execute(command)
				net.send_command(command, battle.checksum())
				# Let the connection breathe between our moves (the AI can think for a second each), or the other
				# side hears nothing for the whole turn and gives up on us.
				await process_frame
			else:
				if await remote.next_events() == null:
						break
			commands += 1
		if battle.winner == -1:
			break
		war.complete_map(battle)
		GameSession.battle = null
		GameSession.save_online(net.local_team)
		print("MAP %d done: winner %d, scores %s" % [war.current, battle.winner, war.scores])
	if not _done:
		_done = true
		# Let the last command reach the other side (and its word that it agrees come back) before hanging up.
		await create_timer(0.5).timeout
		print("%s: winner %d, scores %s, %d commands, checksum %s, online save %s" % ["FINISHED" if war.is_over() else "STOPPED", war.winner(), war.scores, commands,
				war.checksum().left(12), "kept" if GameSession.has_save("online") else "cleared"])
		quit()


## Seals the AI's orders for this map and waits until both sides' orders are in. False if the run ended first.
## `cheat`: reveal other orders than the ones sealed.
func _give_orders(net: Node, cheat: bool) -> bool:
	var war := GameSession.war
	if not war.ready_to_fight():
		# The AI chooses from a copy of the campaign, so its dice leave the shared campaign untouched.
		var orders := WarCampaign.from_dict(war.to_dict()).ai_orders(net.local_team)
		if GameSession.seal_orders(net, orders) != "":
			_finish("ORDERS REFUSED")
			return false
		if cheat:
			var other: Dictionary = GameSession.online["sealed"]["orders"].duplicate(true)
			other["posture"] = "defensive" if other["posture"] == "offensive" else "offensive"
			GameSession.online["sealed"]["orders"] = other
		GameSession.process_war_messages(net)
	while not war.ready_to_fight() and not _done:
		await net.war_message
		GameSession.process_war_messages(net)
	return not _done


## Continues the saved online campaign. Returns false if that didn't work (and the run is finishing).
func _resume(net: Node, hosting: bool, port: int, tamper: bool) -> bool:
	if hosting:
		var offer := GameSession.online_offer()
		if offer.is_empty() or not GameSession.resume_online(offer, offer["team"], "test", true):
			_finish("NO SAVE TO CONTINUE")
			return false
		net.host(port, offer["team"])
		await net.peer_joined
		net.send_resume(offer)
		print("OFFERED %s, checksum %s" % [GameSession.describe_online(offer), offer["checksum"].right(12)])
	else:
		net.join("127.0.0.1", port)
		var offer: Dictionary = await net.resume_offered
		var difference := GameSession.compare_online(offer)
		print("JOINER: " + ("saves match" if difference == "" else difference + " Adopting the host's."))
		if not GameSession.resume_online(offer, net.local_team, "test", false):
			net.report_desync("The host's saved campaign doesn't load the same here.")
			return false
		if tamper and GameSession.battle != null:
			GameSession.battle.rng.randi()
		net.accept_resume(GameSession.online_checksum())
	await net.resume_started
	if _done:
		return false
	GameSession.save_online(net.local_team)
	print("RESUMED at map %d, checksum %s" % [GameSession.war.current + 1, GameSession.online_checksum().right(12)])
	return true


func _finish(message: String) -> void:
	if _done:
		return
	_done = true
	print(message)
	# Give our last message time to reach the other side, which may be busy thinking through its turn.
	await create_timer(5.0).timeout
	quit()
