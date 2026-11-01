class_name BalanceSim
extends RefCounted
## AI vs AI games for balancing maps and scenarios, and the statistics over a batch of them.
## Used by tools/balance.gd (command line, several games at once on worker threads) and the map
## editor's "Test with AI" (a few AI steps per frame, so the window stays responsive).
##
## A game result: {"seed", "variant" ("normal" or "swapped"), "winner" (0, 1, Battle.DRAW or -1 when
## cut off), "reason" ("points", "rounds", "eliminated", "draw", "unfinished"), "rounds", "points": [a, g],
## "survivors": [a, g], "start_units": [a, g], "kills": {role: [allied kills, german kills]},
## "losses": {role: [a, g]}, "held": [a, g, nobody] (objective-rounds), "steps", "seconds"}.

## A safety net against AI stalemates on maps without objectives: AI steps before a game is called off.
const MAX_STEPS := 20000


## One AI vs AI game, played a slice at a time.
class Game:
	extends RefCounted
	var battle: Battle
	var seed := 0
	var variant := "normal"
	var _ais: Array
	var _steps := 0
	var _reason := ""
	var _held := [0, 0, 0]
	var _started_msec := 0
	var _elapsed_msec := 0
	var _start_units := [0, 0]

	func _init(p_battle: Battle, p_seed: int, p_variant := "normal") -> void:
		battle = p_battle
		seed = p_seed
		variant = p_variant
		_ais = [TacticalAI.new(battle, 0), TacticalAI.new(battle, 1)]
		for team in 2:
			_start_units[team] = battle.alive_units(team).size()
			for wave in battle.reinforcements:
				if wave["team"] == team:
					_start_units[team] += wave["units"].size()

	func is_done() -> bool:
		return battle.winner != -1 or _steps >= BalanceSim.MAX_STEPS

	## Plays AI steps for up to budget_msec (or to the end with a negative budget). Returns true when done.
	func advance(budget_msec := -1) -> bool:
		var started := Time.get_ticks_msec()
		if not battle.started:
			_note(battle.start())
		while not is_done():
			_note(_ais[battle.current_team].act())
			_steps += 1
			if budget_msec >= 0 and Time.get_ticks_msec() - started >= budget_msec:
				break
		_elapsed_msec += Time.get_ticks_msec() - started
		return is_done()

	func _note(events: Array) -> void:
		for event: Dictionary in events:
			match event["type"]:
				"score":
					# Objectives held at the end of a round.
					for objective in battle.objectives:
						_held[objective["owner"] if objective["owner"] != -1 else 2] += 1
				"game_over":
					_reason = event["reason"]

	func result() -> Dictionary:
		var winner := battle.winner
		var reason := _reason
		if winner == -1:
			reason = "unfinished"
		elif winner == Battle.DRAW:
			reason = "draw"
		elif reason == "points" and battle.victory_points[winner] < battle.vp_to_win:
			reason = "rounds"
		var kills := {}
		var losses := {}
		var everyone: Array[Unit] = battle.units.duplicate()
		for role in battle.theatre().all_role_ids():
			kills[role] = [0, 0]
			losses[role] = [0, 0]
		for u in everyone:
			if not kills.has(u.role):
				kills[u.role] = [0, 0]
				losses[u.role] = [0, 0]
			kills[u.role][u.team] += u.kills
			if not u.is_alive():
				losses[u.role][u.team] += 1
		return {
			"seed": seed, "variant": variant, "winner": winner, "reason": reason,
			"rounds": battle.round_number, "points": battle.victory_points.duplicate(),
			"survivors": [battle.alive_units(0).size(), battle.alive_units(1).size()],
			"start_units": _start_units.duplicate(),
			"kills": kills, "losses": losses, "held": _held.duplicate(),
			"steps": _steps, "seconds": _elapsed_msec / 1000.0,
			"names": [battle.team_name(0), battle.team_name(1)],
		}


## Games played on worker threads. Start it, then poll results() until done() (or cancel()).
class Batch:
	extends RefCounted
	var source: Dictionary
	var jobs: Array = []
	var _queue: Array = []
	var _results := {}
	var _threads: Array[Thread] = []
	var _mutex := Mutex.new()
	var _cancelled := false

	## source: see BalanceSim.build. Plays seeds first_seed.., and with swap each seed with sides swapped too.
	func _init(p_source: Dictionary, games: int, first_seed: int, swap := false) -> void:
		source = p_source
		for seed in range(first_seed, first_seed + games):
			jobs.append([seed, "normal"])
			if swap:
				jobs.append([seed, "swapped"])
		_queue = jobs.duplicate()

	func start(thread_count: int) -> void:
		for i in clampi(thread_count, 1, jobs.size()):
			var thread := Thread.new()
			thread.start(_work)
			_threads.append(thread)

	## Finished results so far, in job order up to the first unfinished one.
	func results() -> Array:
		var done: Array = []
		_mutex.lock()
		for job: Array in jobs:
			var key := "%d/%s" % job
			if not _results.has(key):
				break
			done.append(_results[key])
		_mutex.unlock()
		return done

	func done() -> bool:
		return results().size() == jobs.size()

	func cancel() -> void:
		_mutex.lock()
		_cancelled = true
		_queue.clear()
		_mutex.unlock()

	## Waits for the worker threads to stop. Call once done, or after cancel().
	func wait() -> void:
		for thread in _threads:
			thread.wait_to_finish()
		_threads.clear()

	func _work() -> void:
		while true:
			_mutex.lock()
			var job: Array = _queue.pop_front() if not _queue.is_empty() else []
			_mutex.unlock()
			if job.is_empty():
				return
			var game := Game.new(BalanceSim.build(source, job[0], job[1]), job[0], job[1])
			while not game.advance(250):
				if _cancelled:
					return
			_mutex.lock()
			_results["%d/%s" % job] = game.result()
			_mutex.unlock()


## The battle for one game. source is {"scenario": scenario data (Scenario.to_data())} or
## {"map": "village" or "random", "size": N, "theatre": id (optional)}. "swapped" exchanges the sides' starting positions.
## Safe on worker threads: every battle gets its own map and units.
static func build(source: Dictionary, seed: int, variant := "normal") -> Battle:
	var scenario: Scenario
	if source.has("scenario"):
		scenario = Scenario.from_data(source["scenario"])
	else:
		var built: Battle = GameSession.build_skirmish({"theatre": source.get("theatre", Theatres.DEFAULT), "map": source.get("map", "village"),
				"size": source.get("size", 0), "seed": seed})[0]
		if variant == "normal":
			return built
		scenario = Scenario.from_battle(built, "", false)
	if variant == "swapped":
		scenario = scenario.swapped()
	return scenario.build_battle(seed)


## Plays a whole game and returns its result.
static func play(battle: Battle, seed: int, variant := "normal") -> Dictionary:
	var game := Game.new(battle, seed, variant)
	game.advance()
	return game.result()


## A one-line summary of a game.
static func describe(r: Dictionary) -> String:
	var who: String = (r["names"] + ["draw"])[r["winner"]] if r["winner"] != -1 else "unfinished"
	return "seed %4d%s: %-10s by %-10s round %2d, points %2d-%-2d, survivors %2d/%-2d vs %2d/%-2d, %4d steps, %.1fs" % [
		r["seed"], " swapped" if r["variant"] == "swapped" else "", who, r["reason"], r["rounds"], r["points"][0], r["points"][1],
		r["survivors"][0], r["start_units"][0], r["survivors"][1], r["start_units"][1], r["steps"], r["seconds"]]


## Statistics over a batch of results.
static func summarize(results: Array) -> Dictionary:
	var n := results.size()
	var wins := [0, 0, 0]
	var unfinished := 0
	var reasons := {}
	var rounds := 0.0
	var survivors := [0.0, 0.0]
	var held := [0.0, 0.0, 0.0]
	var kills := {}
	var losses := {}
	# Allied (first mover) and west-start results.
	var west_wins := 0
	var decided := 0
	for r: Dictionary in results:
		var w: int = r["winner"]
		if w == -1:
			unfinished += 1
		else:
			wins[w] += 1
		if w == 0 or w == 1:
			decided += 1
			# Allies start in the west unless the sides were swapped.
			if (w == 0) == (r["variant"] != "swapped"):
				west_wins += 1
		reasons[r["reason"]] = reasons.get(r["reason"], 0) + 1
		rounds += r["rounds"]
		for t in 2:
			survivors[t] += r["survivors"][t]
		for i in 3:
			held[i] += r["held"][i]
		for role: String in r["kills"]:
			if not kills.has(role):
				kills[role] = [0.0, 0.0]
				losses[role] = [0.0, 0.0]
			for t in 2:
				kills[role][t] += r["kills"][role][t]
				losses[role][t] += r["losses"][role][t]
	var held_total := maxf(1.0, held[0] + held[1] + held[2])
	var per := maxf(1.0, n)
	for role: String in kills:
		for t in 2:
			kills[role][t] /= per
			losses[role][t] /= per
	return {
		"games": n, "wins": wins, "unfinished": unfinished, "reasons": reasons,
		"win_rate": [wins[0] / per, wins[1] / per], "draw_rate": wins[2] / per,
		"win_ci": [wilson(wins[0], n), wilson(wins[1], n)],
		"decided": decided, "west_wins": west_wins,
		"west_ci": wilson(west_wins, decided),
		# Allied share of decided games: above 0.5 favours the side that moves first.
		"first_mover_share": wins[0] / maxf(1.0, wins[0] + wins[1]),
		"first_mover_ci": wilson(wins[0], wins[0] + wins[1]),
		"avg_rounds": rounds / per, "avg_survivors": [survivors[0] / per, survivors[1] / per],
		"control": [held[0] / held_total, held[1] / held_total, held[2] / held_total],
		"kills": kills, "losses": losses,
		"swapped": results.any(func(r: Dictionary) -> bool: return r["variant"] == "swapped"),
		"swap_identical": _swaps_identical(results),
		"names": results[0]["names"] if n > 0 else ["Allies", "Germany"],
	}


## Whether every swapped game played out exactly like the original of the same seed. Happens when the map
## and both forces are mirror images: the engine and AI are mirror-symmetric, so the swap changes nothing.
static func _swaps_identical(results: Array) -> bool:
	var normal := {}
	for r: Dictionary in results:
		if r["variant"] == "normal":
			normal[r["seed"]] = r
	var compared := 0
	for r: Dictionary in results:
		if r["variant"] == "swapped" and normal.has(r["seed"]):
			var o: Dictionary = normal[r["seed"]]
			if o["winner"] != r["winner"] or o["rounds"] != r["rounds"] or o["points"] != r["points"] or o["steps"] != r["steps"]:
				return false
			compared += 1
	return compared > 0


## 95% Wilson score interval for k successes out of n, as [low, high].
static func wilson(k: int, n: int) -> Array:
	if n == 0:
		return [0.0, 1.0]
	var z := 1.96
	var p := float(k) / n
	var denom := 1.0 + z * z / n
	var center := (p + z * z / (2.0 * n)) / denom
	var half := z * sqrt(p * (1.0 - p) / n + z * z / (4.0 * n * n)) / denom
	return [maxf(0.0, center - half), minf(1.0, center + half)]


## A readable report of a summary.
static func format_summary(s: Dictionary) -> String:
	var lines := PackedStringArray()
	var pct := func(x: float) -> String: return "%.0f%%" % (x * 100.0)
	var ci := func(c: Array) -> String: return "%s-%s" % [pct.call(c[0]), pct.call(c[1])]
	var a: String = s["names"][0]
	var g: String = s["names"][1]
	lines.append("%d games. %s %d, %s %d, draws %d%s." % [s["games"], a, s["wins"][0], g, s["wins"][1], s["wins"][2],
			", unfinished %d" % s["unfinished"] if s["unfinished"] > 0 else ""])
	lines.append("Win rate: %s %s (95%% CI %s), %s %s (95%% CI %s), draws %s." % [
			a, pct.call(s["win_rate"][0]), ci.call(s["win_ci"][0]), g, pct.call(s["win_rate"][1]), ci.call(s["win_ci"][1]), pct.call(s["draw_rate"])])
	lines.append("First mover: the %s always move first; they took %s of decided games (95%% CI %s). 50%% = no edge." % [
			a, pct.call(s["first_mover_share"]), ci.call(s["first_mover_ci"])])
	if s["swapped"] and s["swap_identical"]:
		lines.append("Start side: every swapped game played out exactly like the original. Map and forces are mirror images, so the start side makes no difference; only the first move does.")
	elif s["swapped"]:
		lines.append("Start side: the west start won %d of %d decided games, %s (95%% CI %s)." % [
				s["west_wins"], s["decided"], pct.call(float(s["west_wins"]) / maxf(1.0, s["decided"])), ci.call(s["west_ci"])])
	var reasons := PackedStringArray()
	for key: String in ["points", "rounds", "eliminated", "draw", "unfinished"]:
		if s["reasons"].has(key):
			reasons.append("%s %d" % [{"points": "reached points", "rounds": "most points at round limit", "eliminated": "elimination", "draw": "draw", "unfinished": "unfinished"}[key], s["reasons"][key]])
	lines.append("Endings: %s. Average %.1f rounds." % [", ".join(reasons), s["avg_rounds"]])
	lines.append("Average survivors: %s %.1f, %s %.1f." % [a, s["avg_survivors"][0], g, s["avg_survivors"][1]])
	lines.append("Objective control (share of objective-rounds): %s %s, %s %s, nobody %s." % [
			a, pct.call(s["control"][0]), g, pct.call(s["control"][1]), pct.call(s["control"][2])])
	lines.append("Per game, by role:   kills %s / %s    losses %s / %s" % [a, g, a, g])
	for role: String in s["kills"]:
		var k: Array = s["kills"][role]
		var l: Array = s["losses"][role]
		if k[0] + k[1] + l[0] + l[1] > 0.0:
			lines.append("  %-9s %12.2f / %-12.2f %10.2f / %.2f" % [role, k[0], k[1], l[0], l[1]])
	return "\n".join(lines)


## Results as CSV, one row per game.
static func to_csv(results: Array) -> String:
	var header := ["seed", "variant", "winner", "reason", "rounds", "points_allies", "points_germany", "survivors_allies", "survivors_germany",
			"held_allies", "held_germany", "held_nobody", "steps", "seconds"]
	var roles := []
	for r: Dictionary in results:
		for role: String in r["kills"]:
			if not roles.has(role):
				roles.append(role)
	for role: String in roles:
		header.append_array(["kills_%s_allies" % role.to_lower(), "kills_%s_germany" % role.to_lower()])
	var rows := PackedStringArray([",".join(header)])
	for r: Dictionary in results:
		var row := [r["seed"], r["variant"], ["allies", "germany", "draw"][r["winner"]] if r["winner"] != -1 else "unfinished", r["reason"], r["rounds"],
				r["points"][0], r["points"][1], r["survivors"][0], r["survivors"][1], r["held"][0], r["held"][1], r["held"][2], r["steps"], "%.2f" % r["seconds"]]
		for role: String in roles:
			row.append_array(r["kills"].get(role, [0, 0]))
		rows.append(",".join(row.map(func(v: Variant) -> String: return str(v))))
	return "\n".join(rows) + "\n"
