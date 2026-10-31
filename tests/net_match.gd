extends SceneTree
## Two copies of the game playing each other online, AI on both sides, to check that every command
## arrives and both games stay identical. Start the host first, then the joiner:
##   Godot --headless --path . -s tests/net_match.gd -- host [port] [map size, 0 = village]
##   Godot --headless --path . -s tests/net_match.gd -- join [port] [tamper]
## With "tamper" the joiner secretly rolls an extra die in round 3, and both sides must notice.

var _done := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var hosting := args[0] == "host"
	var port := int(args[1]) if args.size() > 1 else 24944
	var net: Node = root.get_node("Net")
	net.desynced.connect(func(reason: String) -> void: _finish("DESYNC DETECTED: " + reason))
	net.disconnected.connect(func() -> void: _finish("DISCONNECTED"))
	var setup := {}
	if hosting:
		net.host(port)
		await net.peer_joined
		var size := int(args[2]) if args.size() > 2 else 0
		setup = {"map": "village" if size == 0 else "random", "size": size, "seed": 4711}
		net.send_setup(setup)
	else:
		net.join("127.0.0.1", port)
		setup = await net.setup_received
	var tamper := args.size() > 2 and args[2] == "tamper"
	var battle: Battle = GameSession.build_skirmish(setup)[0]
	var ai := TacticalAI.new(battle, net.local_team)
	var remote := RemotePlayer.new(battle, net.remote_team(), net)
	battle.start()
	var commands := 0
	var tampered := false
	while battle.winner == -1 and not _done:
		if tamper and not tampered and battle.round_number == 3:
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
		print("%s: winner %d after %d rounds, %d commands, checksum %s" % ["FINISHED" if battle.winner != -1 else "STOPPED", battle.winner, battle.round_number, commands, battle.checksum().left(12)])
		# Let the last command reach the other side before hanging up.
		await create_timer(0.5).timeout
		quit()


func _finish(message: String) -> void:
	if _done:
		return
	_done = true
	print(message)
	# Give our last message time to reach the other side, which may be busy thinking through its turn.
	await create_timer(5.0).timeout
	quit()
