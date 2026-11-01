class_name Replay
extends RefCounted
## A recorded battle: the state it started from and every command executed after that. The engine is
## deterministic, so rebuilding the start state and executing the commands in order replays it exactly.
## Recorded while a battle is played (ReplayRecorder), kept in the save while the battle is in progress, and
## written to user://replays/ (or --save-dir) when it ends. ReplayControls plays one back on the battle screen.
## The battle's checksum is kept at every turn change and at the end, so a replay that no longer plays out the
## same (the rules changed since) is reported instead of shown.

const VERSION := 1
const FOLDER := "replays"
const EXTENSION := "replay"
## Finished replays kept; the oldest go first.
const KEEP := 20

var title := ""
## Unix time the recording began.
var date := 0
## "skirmish", "campaign", "war" (two-player campaign) or "online".
var mode := "skirmish"
## Who played each side, e.g. ["Player", "AI"].
var sides := ["", ""]
## How it ended ("Allies win 12 to 7"), or "" while in progress.
var result := ""
var winner := -1
var rounds := 0
## False when recording began mid-battle (a save from before replays were recorded).
var from_start := true
## Battle.to_dict() when recording began.
var snapshot := {}
var commands: Array[Dictionary] = []
## Command index -> the battle's checksum after it, at every turn change and at the end.
var checkpoints := {}
## The battle's checksum after the last command (kept up to date while recording, by to_dict()).
var head := ""
## The file it was loaded from, or "".
var path := ""

## The battle being recorded, while attached.
var _battle: Battle
var _turn := -1


## Starts recording a battle as it is now (normally before Battle.start()).
static func begin(battle: Battle, p_title: String, p_mode: String, p_sides: Array) -> Replay:
	var replay := Replay.new()
	replay.title = p_title
	replay.mode = p_mode
	replay.sides = p_sides.duplicate()
	replay.date = int(Time.get_unix_time_from_system())
	replay.from_start = not battle.started
	replay.snapshot = battle.to_dict()
	replay.head = battle.checksum()
	return replay


## Records every command the battle executes from now on.
func attach(battle: Battle) -> void:
	detach()
	_battle = battle
	_turn = battle.turn_index
	battle.executed.connect(_on_executed)


func detach() -> void:
	if _battle != null and _battle.executed.is_connected(_on_executed):
		_battle.executed.disconnect(_on_executed)
	_battle = null


func _on_executed(command: Dictionary) -> void:
	commands.append(command.duplicate(true))
	if _battle.turn_index != _turn or _battle.winner != -1:
		_turn = _battle.turn_index
		checkpoints[commands.size() - 1] = _battle.checksum()


## Notes how the battle ended and stops recording.
func finish(battle: Battle) -> void:
	winner = battle.winner
	rounds = battle.round_number
	head = battle.checksum()
	var points := "%d to %d" % [battle.victory_points[0], battle.victory_points[1]]
	result = "Draw, %s" % points if winner == Battle.DRAW else "%s win, %s" % [battle.team_name(winner), points]
	detach()


## The battle as it was when recording began.
func build() -> Battle:
	return Battle.from_dict(snapshot.duplicate(true))


## Plays the whole replay without showing it. Returns "" if it ends exactly as recorded, else what went wrong.
func verify() -> String:
	if snapshot.is_empty():
		return "The replay is empty."
	var battle := build()
	if not battle.started:
		battle.start()
	for i in commands.size():
		if battle.execute(commands[i]).is_empty():
			return "Order %d of %d (%s) isn't possible any more." % [i + 1, commands.size(), commands[i].get("cmd", "?")]
		if checkpoints.has(i) and battle.checksum() != checkpoints[i]:
			return "The battle plays out differently from order %d on." % (i + 1)
	if head != "" and battle.checksum() != head:
		return "The battle ends differently from the recording."
	return ""


## Title, date, sides and result: what a list of replays shows.
func meta() -> Dictionary:
	return {"version": VERSION, "title": title, "date": date, "mode": mode, "sides": sides.duplicate(), "result": result,
			"winner": winner, "rounds": rounds, "from_start": from_start, "orders": commands.size(),
			"theatre": snapshot.get("theatre", Theatres.DEFAULT)}


func to_dict() -> Dictionary:
	if _battle != null:
		head = _battle.checksum()
	var data := meta()
	data.merge({"snapshot": snapshot, "commands": commands, "checkpoints": checkpoints, "head": head})
	return data


static func from_dict(data: Dictionary) -> Replay:
	if data.get("version") != VERSION or not data.get("snapshot") is Dictionary:
		return null
	var replay := Replay.new()
	replay.title = data.get("title", "")
	replay.date = data.get("date", 0)
	replay.mode = data.get("mode", "skirmish")
	replay.sides = data.get("sides", ["", ""]).duplicate()
	replay.result = data.get("result", "")
	replay.winner = data.get("winner", -1)
	replay.rounds = data.get("rounds", 0)
	replay.from_start = data.get("from_start", true)
	replay.snapshot = data["snapshot"]
	replay.commands.assign(data.get("commands", []))
	replay.checkpoints = data.get("checkpoints", {})
	replay.head = data.get("head", "")
	return replay


# --- Files ---
# A replay file holds two values: meta() first, so listing replays needn't read the battles, then to_dict().

static func folder() -> String:
	return GameSession.save_dir.path_join(FOLDER)


## Writes the replay to the replays folder, keeping only the newest KEEP. Returns the path, or "" on failure.
func save_file() -> String:
	DirAccess.make_dir_recursive_absolute(folder())
	path = folder().path_join("%d-%08x.%s" % [int(Time.get_unix_time_from_system()), randi(), EXTENSION])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not save the replay: %s" % FileAccess.get_open_error())
		path = ""
		return ""
	file.store_var(meta())
	file.store_var(to_dict())
	file.close()
	var files := _files()
	for i in maxi(0, files.size() - KEEP):
		DirAccess.remove_absolute(folder().path_join(files[i]))
	return path


## The saved replays, newest first: meta() plus "path".
static func list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var files := _files()
	files.reverse()
	for file_name in files:
		var file := FileAccess.open(folder().path_join(file_name), FileAccess.READ)
		if file == null:
			continue
		var data: Variant = file.get_var()
		if data is Dictionary and data.get("version") == VERSION:
			data["path"] = folder().path_join(file_name)
			result.append(data)
	return result


static func load_file(file_path: String) -> Replay:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return null
	file.get_var()
	var data: Variant = file.get_var()
	if not data is Dictionary:
		return null
	var replay := from_dict(data)
	if replay != null:
		replay.path = file_path
	return replay


static func delete_file(file_path: String) -> void:
	if file_path.get_base_dir() == folder() and FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)


## Replay file names, oldest first (they start with the unix time they were saved).
static func _files() -> PackedStringArray:
	var names := PackedStringArray()
	for file_name in DirAccess.get_files_at(folder()):
		if file_name.get_extension() == EXTENSION:
			names.append(file_name)
	names.sort()
	return names


## A date for lists: "2026-10-31 14:05", in local time.
static func date_text(unix: int) -> String:
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	var d := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]
