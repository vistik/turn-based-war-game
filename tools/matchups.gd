extends SceneTree
## Unit-against-unit balance: within a theatre, every role on one side against every role on the other, one
## against one and two against two (the same role twice), AI against AI on a small arena with mirrored random
## cover. Last side standing wins; still going after ROUNDS rounds is a draw. Which side moves first
## alternates from game to game, so the first move's edge cancels out.
##
## Prints, per theatre and size, a table of the first side's score against each opponent (win 1, draw 0.5, as a
## percentage), then each role's average score against all the other side's roles, beside its price.
##
##   Godot --headless --path . -s tools/matchups.gd -- [--theatre ID] [--games N] [--sizes 1,2] [--jobs N] [--out report.md]

const ROUNDS := 15
const ARENA := Vector2i(20, 20)
const MAX_STEPS := 3000

var _jobs: Array = []
var _queue: Array = []
var _results := {}
var _mutex := Mutex.new()
var _done := 0


func _initialize() -> void:
	var theatres: Array = Theatres.IDS.duplicate()
	var games := 8
	var sizes := [1, 2]
	var jobs := clampi(OS.get_processor_count() - 1, 1, 8)
	var out := ""
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var value := args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--theatre":
				theatres = [value]
			"--games":
				games = maxi(2, value.to_int())
			"--sizes":
				sizes = Array(value.split(",")).map(func(s: String) -> int: return s.to_int())
			"--jobs":
				jobs = maxi(1, value.to_int())
			"--out":
				out = value
		i += 2
	for theatre_id: String in theatres:
		var theatre := Theatres.get_theatre(theatre_id)
		for size: int in sizes:
			for a: String in theatre.role_ids(0):
				for b: String in theatre.role_ids(1):
					for g in games:
						_jobs.append([theatre_id, size, a, b, g + 1])
	_queue = _jobs.duplicate()
	var started := Time.get_ticks_msec()
	print("Matchups: %s, sizes %s, %d games each, %d games on %d threads" % [", ".join(theatres), sizes, games, _jobs.size(), jobs])
	var threads: Array[Thread] = []
	for t in jobs:
		var thread := Thread.new()
		thread.start(_work)
		threads.append(thread)
	for thread in threads:
		thread.wait_to_finish()
	var report := _report(theatres, sizes)
	report += "\n%d games in %.0fs.\n" % [_jobs.size(), (Time.get_ticks_msec() - started) / 1000.0]
	print(report)
	if out != "":
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(report)
	quit()


func _work() -> void:
	while true:
		_mutex.lock()
		var job: Array = _queue.pop_front() if not _queue.is_empty() else []
		_mutex.unlock()
		if job.is_empty():
			return
		var winner := play(job[0], job[1], job[2], job[3], job[4])
		_mutex.lock()
		_done += 1
		if _done % 100 == 0:
			print("  %d / %d games" % [_done, _jobs.size()])
		var key := "%s/%d/%s/%s" % [job[0], job[1], job[2], job[3]]
		var tally: Array = _results.get(key, [0, 0, 0])
		tally[mini(winner, 2)] += 1
		_results[key] = tally
		_mutex.unlock()


## One game: `count` of role a (side 0, west) against `count` of role b (side 1, east). Returns the winner, or
## Battle.DRAW. Odd seeds let side 1 move first.
static func play(theatre_id: String, count: int, a: String, b: String, seed: int) -> int:
	var map := arena(seed)
	var units: Array[Unit] = []
	for i in count:
		var y := ARENA.y / 2 - count + 1 + i * 2
		units.append(Unit.create(units.size(), "A%d" % i, a, 0, Vector2i(2, y), 0, theatre_id))
		units.append(Unit.create(units.size(), "B%d" % i, b, 1, Vector2i(ARENA.x - 3, y), 0, theatre_id))
	var battle := Battle.new(map, units, seed * 7919 + 13)
	battle.theatre_id = theatre_id
	battle.max_rounds = ROUNDS
	if seed % 2 == 1:
		battle.current_team = 1
	battle.start()
	var ais := [TacticalAI.new(battle, 0), TacticalAI.new(battle, 1)]
	var steps := 0
	while battle.winner == -1 and battle.round_number <= ROUNDS and steps < MAX_STEPS:
		ais[battle.current_team].act()
		steps += 1
	return battle.winner if battle.winner != -1 else Battle.DRAW


## Open ground with cover scattered on the west half and mirrored: rocks, trees, sandbags, crates and low walls.
static func arena(seed: int) -> TacticalMap:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 31 + 7
	var b := MapBuilder.new(ARENA.x, ARENA.y)
	var kinds := [[Cover.FULL, "rock"], [Cover.FULL, "tree"], [Cover.HALF, "sandbags"], [Cover.HALF, "crate"]]
	for i in 10:
		var p := Vector2i(rng.randi_range(4, ARENA.x / 2 - 1), rng.randi_range(1, ARENA.y - 2))
		if b.map.is_passable(p):
			var kind: Array = kinds[rng.randi_range(0, kinds.size() - 1)]
			b.object(p, kind[0], kind[1])
	for i in 3:
		var p := Vector2i(rng.randi_range(4, ARENA.x / 2 - 2), rng.randi_range(1, ARENA.y - 2))
		b.side(p, MapBuilder.E if rng.randf() < 0.5 else MapBuilder.S, Cover.HALF, "stone")
	return b.map


func _report(theatres: Array, sizes: Array) -> String:
	var text := ""
	for theatre_id: String in theatres:
		var theatre := Theatres.get_theatre(theatre_id)
		var rows: Array = theatre.role_ids(0)
		var cols: Array = theatre.role_ids(1)
		for size: int in sizes:
			text += "\n## %s, %dv%d: %s's score against each %s unit (%%; win 1, draw 0.5)\n\n" % [
					theatre.title, size, size, theatre.team_name(0), theatre.team_name(1)]
			text += "| %s \\ %s | %s |\n" % [theatre.team_name(0), theatre.team_name(1), " | ".join(cols.map(func(c: String) -> String: return _short(c)))]
			text += "|---|" + "---|".repeat(cols.size()) + "\n"
			var averages := [{}, {}]
			for a: String in rows:
				var cells := PackedStringArray()
				for b: String in cols:
					var score := _score(theatre_id, size, a, b)
					cells.append("%d" % roundi(score * 100.0))
					averages[0][a] = averages[0].get(a, 0.0) + score / cols.size()
					averages[1][b] = averages[1].get(b, 0.0) + (1.0 - score) / rows.size()
				text += "| %s | %s |\n" % [a, " | ".join(cells)]
			for team in 2:
				text += "\n%s, average score against every enemy unit type (cost in supply):\n" % theatre.team_name(team)
				var ranked: Array = averages[team].keys()
				ranked.sort_custom(func(x: String, y: String) -> bool: return averages[team][x] > averages[team][y])
				for role: String in ranked:
					text += "  %-14s %3d%%   cost %2d\n" % [role, roundi(averages[team][role] * 100.0), theatre.cost(team, role)]
			var draws := 0
			var total := 0
			for a: String in rows:
				for b: String in cols:
					var tally: Array = _results.get("%s/%d/%s/%s" % [theatre_id, size, a, b], [0, 0, 0])
					draws += tally[2]
					total += tally[0] + tally[1] + tally[2]
			text += "\nDraws (nobody wiped out in %d rounds): %d%% of games.\n" % [ROUNDS, roundi(100.0 * draws / maxi(1, total))]
	return text


func _score(theatre_id: String, size: int, a: String, b: String) -> float:
	var tally: Array = _results.get("%s/%d/%s/%s" % [theatre_id, size, a, b], [0, 0, 0])
	var games: int = tally[0] + tally[1] + tally[2]
	return (tally[0] + 0.5 * tally[2]) / maxf(1.0, games)


static func _short(role: String) -> String:
	return role if role.length() <= 8 else role.substr(0, 8)
