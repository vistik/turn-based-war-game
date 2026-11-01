extends SceneTree
## Balance testing: plays many AI vs AI games on a scenario or a built-in map and reports how they went.
##
## Godot --headless --path . -s tools/balance.gd -- [options]
##   --scenario PATH   a scenario file (res://scenarios/village.json, user://scenarios/x.json or a plain path)
##   --map NAME        village (default) or random; --size N picks a random map size (44, 64, 84)
##   --games N         games to play (default 20), with seeds --seed S, S+1, ... (default 1)
##   --jobs N          games at once on worker threads (default: CPU cores - 1, at most 8)
##   --swap            also play every seed with the start positions exchanged, to separate the
##                     ground's advantage from the Allies' first move
##   --csv PATH        write one row per game; --json PATH writes the games and the summary
##   --quiet           only print the summary
##
## The Allies always move first. On a mirrored map with the same forces, the Allied share of decided games
## is the first mover's advantage; --swap tells it apart from an uneven map or scenario.

var _scenario_data := {}
var _map := "village"
var _theatre := Theatres.DEFAULT
var _size := 0
var _games := 20
var _first_seed := 1
var _jobs := 1
var _swap := false
var _quiet := false
var _csv_path := ""
var _json_path := ""


func _initialize() -> void:
	if not _parse(OS.get_cmdline_user_args()):
		quit(1)
		return
	var source := {"scenario": _scenario_data} if not _scenario_data.is_empty() else {"map": _map, "size": _size, "theatre": _theatre}
	var batch := BalanceSim.Batch.new(source, _games, _first_seed, _swap)
	var total := batch.jobs.size()
	print("Balance run: %s, %d games, seeds %d-%d, %d at a time%s" % [_describe_source(), total, _first_seed, _first_seed + _games - 1,
			mini(_jobs, total), ", each seed also with the start positions swapped" if _swap else ""])
	var started := Time.get_ticks_msec()
	batch.start(_jobs)
	# Print results in seed order as they come in.
	var printed := 0
	while printed < total:
		OS.delay_msec(100)
		var ready := batch.results()
		while printed < ready.size():
			if not _quiet:
				print(BalanceSim.describe(ready[printed]))
			printed += 1
	batch.wait()
	var results := batch.results()
	var summary := BalanceSim.summarize(results)
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	print("")
	print(BalanceSim.format_summary(summary))
	print("Took %.0fs on %d threads." % [seconds, mini(_jobs, total)])
	if _csv_path != "":
		_write(_csv_path, BalanceSim.to_csv(results))
	if _json_path != "":
		_write(_json_path, JSON.stringify({"source": _describe_source(), "summary": summary, "games": results}, "\t", false))
	quit()


func _parse(args: PackedStringArray) -> bool:
	_jobs = clampi(OS.get_processor_count() - 1, 1, 8)
	var i := 0
	while i < args.size():
		var arg := args[i]
		var value := args[i + 1] if i + 1 < args.size() else ""
		match arg:
			"--scenario":
				var path := value if value.contains("://") or value.is_absolute_path() else "res://" + value
				var scenario := Scenario.load_file(path)
				if scenario == null:
					printerr("Can't load scenario: %s" % Scenario.last_error)
					return false
				for problem in scenario.validate():
					print("Warning: " + problem)
				_scenario_data = scenario.to_data()
				i += 1
			"--theatre":
				if not Theatres.exists(value):
					printerr("Unknown theatre: %s (%s)" % [value, ", ".join(Theatres.IDS)])
					return false
				_theatre = value
				i += 1
			"--map":
				_map = value
				i += 1
			"--size":
				_size = value.to_int()
				_map = "village" if _size == 0 else "random"
				i += 1
			"--games":
				_games = maxi(1, value.to_int())
				i += 1
			"--seed":
				_first_seed = value.to_int()
				i += 1
			"--jobs":
				_jobs = maxi(1, value.to_int())
				i += 1
			"--swap":
				_swap = true
			"--quiet":
				_quiet = true
			"--csv":
				_csv_path = value
				i += 1
			"--json":
				_json_path = value
				i += 1
			"--help", "-h":
				print("Usage: Godot --headless --path . -s tools/balance.gd -- [--scenario PATH | [--theatre normandy|vietnam] --map village|random --size N] [--games N] [--seed S] [--jobs N] [--swap] [--csv PATH] [--json PATH] [--quiet]")
				return false
			_:
				printerr("Unknown option: %s (try --help)" % arg)
				return false
		i += 1
	if _map == "random" and _size == 0:
		_size = 44
	return true


func _describe_source() -> String:
	if not _scenario_data.is_empty():
		return "scenario \"%s\" (%dx%d)" % [_scenario_data["title"], _scenario_data["map"]["width"], _scenario_data["map"]["height"]]
	var theatre := Theatres.get_theatre(_theatre)
	return theatre.village_title() if _map == "village" else "%s random %dx%d maps" % [theatre.title, _size, _size]


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Can't write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(text)
	print("Wrote %s" % path)
