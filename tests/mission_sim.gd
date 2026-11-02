extends SceneTree
## Plays AI vs AI battles of one mission headlessly and prints how they ended.
## Run: Godot --headless --path . -s tests/mission_sim.gd -- [mission] [games] [first_seed] [map size, 0 = the village] [theatre] [attacker] [vip_known 0/1]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var type := args[0] if args.size() > 0 else Mission.HOLD
	var games := int(args[1]) if args.size() > 1 else 6
	var first_seed := int(args[2]) if args.size() > 2 else 1
	var size := int(args[3]) if args.size() > 3 else 44
	var theatre := args[4] if args.size() > 4 else Theatres.DEFAULT
	var attacker := int(args[5]) if args.size() > 5 else 0
	var known := args.size() > 6 and args[6] == "1"
	var wins := [0, 0, 0]
	var reasons := {}
	var started := Time.get_ticks_msec()
	for seed in range(first_seed, first_seed + games):
		var setup := {"theatre": theatre, "map": "village" if size == 0 else "random", "size": size, "seed": seed,
			"mission": {"type": type, "attacker": attacker, "vip_known": known}}
		var battle: Battle = GameSession.build_skirmish(setup)[0]
		var ais := [TacticalAI.new(battle, 0), TacticalAI.new(battle, 1)]
		var reason := "unfinished"
		var log := []
		battle.start()
		var steps := 0
		while battle.winner == -1 and steps < 4000:
			for e: Dictionary in ais[battle.current_team].act():
				if e["type"] == "game_over":
					reason = e["reason"]
				elif e["type"] in ["vip_found", "charge"]:
					log.append("r%d %s%s" % [battle.round_number, e["type"], (":" + e["state"]) if e.has("state") else ""])
			steps += 1
		var w: int = battle.winner if battle.winner != -1 else Battle.DRAW
		wins[w] += 1
		reasons[reason] = reasons.get(reason, 0) + 1
		print("seed %3d: %-11s %-11s round %2d, alive %d v %d  %s" % [seed, battle.team_name(w) if w < 2 else "draw", reason,
			battle.round_number, battle.alive_units(0).size(), battle.alive_units(1).size(), " ".join(log)])
	print("%s, %s attacking: %s %d, %s %d, draws %d; %s; %.1fs per game" % [type, Theatres.get_theatre(theatre).team_name(attacker),
		Theatres.get_theatre(theatre).team_name(0), wins[0], Theatres.get_theatre(theatre).team_name(1), wins[1], wins[2], reasons,
		(Time.get_ticks_msec() - started) / 1000.0 / games])
	quit()
