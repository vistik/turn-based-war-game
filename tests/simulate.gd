extends SceneTree
## Plays AI vs AI battles headlessly and prints the results.
## Run: Godot --headless --path . -s tests/simulate.gd -- [games] [first_seed]

const MAX_ROUNDS := 40


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 10
	var first_seed := int(args[1]) if args.size() > 1 else 1
	var wins := [0, 0]
	var draws := 0
	var total_rounds := 0
	var started := Time.get_ticks_msec()
	for seed in range(first_seed, first_seed + games):
		var result := play(seed)
		total_rounds += result["rounds"]
		if result["winner"] == -1:
			draws += 1
		else:
			wins[result["winner"]] += 1
		print("seed %3d: %-5s in %2d rounds, %d survivors, %d AI steps, %.1fs" % [
			seed, ["Blue", "Red"][result["winner"]] if result["winner"] != -1 else "draw",
			result["rounds"], result["survivors"], result["steps"], result["seconds"]])
	print("Blue %d, Red %d, draws %d. Average %.1f rounds, %.1fs per game." % [
		wins[0], wins[1], draws, float(total_rounds) / games, (Time.get_ticks_msec() - started) / 1000.0 / games])
	quit()


static func play(seed: int, max_rounds := MAX_ROUNDS) -> Dictionary:
	var started := Time.get_ticks_msec()
	var battle := SkirmishScenario.build(seed)
	var ais := [TacticalAI.new(battle, 0), TacticalAI.new(battle, 1)]
	battle.start()
	var steps := 0
	while battle.winner == -1 and battle.round_number <= max_rounds:
		ais[battle.current_team].act()
		steps += 1
	return {
		"winner": battle.winner,
		"rounds": battle.round_number,
		"survivors": battle.alive_units().size(),
		"steps": steps,
		"seconds": (Time.get_ticks_msec() - started) / 1000.0,
	}
