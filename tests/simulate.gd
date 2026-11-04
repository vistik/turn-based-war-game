extends SceneTree
## Plays AI vs AI battles headlessly and prints the results.
## Run: Godot --headless --path . -s tests/simulate.gd -- [games] [first_seed] [map size, 0 = the village]
##        [Allied plan] [German plan] (keys of TacticalAI.STRATEGIES; left out or "-": picked as in a real game)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 10
	var first_seed := int(args[1]) if args.size() > 1 else 1
	var size := int(args[2]) if args.size() > 2 else 0
	var forced := [args[3] if args.size() > 3 else "-", args[4] if args.size() > 4 else "-"]
	var wins := [0, 0]
	var draws := 0
	var total_rounds := 0
	var started := Time.get_ticks_msec()
	for seed in range(first_seed, first_seed + games):
		var result := play(seed, size, forced)
		total_rounds += result["rounds"]
		if result["winner"] == -1 or result["winner"] == Battle.DRAW:
			draws += 1
		else:
			wins[result["winner"]] += 1
		print("seed %3d: %-8s in %2d rounds, points %s, %2d survivors, %3d AI steps, %.1fs, slowest step %dms, plans %s" % [
			seed, ["Allies", "Germany", "draw"][result["winner"]] if result["winner"] != -1 else "unfinished",
			result["rounds"], result["points"], result["survivors"], result["steps"], result["seconds"], result["slowest"], result["plans"]])
	print("Allies %d, Germany %d, draws %d. Average %.1f rounds, %.1fs per game." % [
		wins[0], wins[1], draws, float(total_rounds) / games, (Time.get_ticks_msec() - started) / 1000.0 / games])
	quit()


static func play(seed: int, size := 0, forced := ["-", "-"]) -> Dictionary:
	var started := Time.get_ticks_msec()
	var battle: Battle = GameSession.build_skirmish({"map": "village" if size == 0 else "random", "size": size, "seed": seed})[0]
	var ais := [TacticalAI.new(battle, 0), TacticalAI.new(battle, 1)]
	for team in 2:
		if forced[team] != "-":
			ais[team].plans.clear()
			ais[team].set_strategy(forced[team])
	battle.start()
	var steps := 0
	var slowest := 0
	while battle.winner == -1:
		var step_started := Time.get_ticks_msec()
		ais[battle.current_team].act()
		slowest = maxi(slowest, Time.get_ticks_msec() - step_started)
		steps += 1
	return {
		"winner": battle.winner,
		"rounds": battle.round_number,
		"survivors": battle.alive_units().size(),
		"points": battle.victory_points,
		"steps": steps,
		"slowest": slowest,
		"plans": [" > ".join(ais[0].plans), " > ".join(ais[1].plans)],
		"seconds": (Time.get_ticks_msec() - started) / 1000.0,
	}
