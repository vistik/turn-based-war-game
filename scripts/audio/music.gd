extends Node
## Autoload `Music`: plays the game's music.
##
## The recorded tracks in res://music/ (and any the player adds to user://music/) play as one playlist that
## loops round all of them, in name order, carrying on through menus and battles alike.
##
## Anything dropped into the git-ignored local_music/ folder (in the project, or next to an exported game)
## replaces that playlist: when it holds any tracks, only those play. It is read straight from disk,
## subfolders included, and holds a .gdignore so Godot never imports or exports it.
##
## Without any tracks it falls back to the themes composed in code (MusicComposer): the theatre's battle
## theme in a battle and its menu theme everywhere else, crossfading when that changes.
##
## Silent when running headless (tests, tools) and while the music volume setting is off.

const FADE := 1.5
const BATTLE_SCENE := "res://scenes/battle.tscn"
const FOLDERS := ["res://music/", "user://music/"]
## Git-ignored folder for the player's own music, loaded raw from disk.
const LOCAL_FOLDER := "local_music"
const EXTENSIONS := ["mp3", "ogg", "wav"]

## The theatre the main menu has picked; its menu theme plays outside battles (composed themes only).
var menu_theatre := Theatres.DEFAULT

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _playing := ""
var _cache := {}
var _thread: Thread
var _enabled := true
## The recorded tracks, as paths, and the one playing.
var _playlist: Array[String] = []
var _track := -1


func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless"
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)
	_players[0].finished.connect(_next_track)
	_players[1].finished.connect(_next_track)
	if _enabled:
		_playlist = find_tracks()


## The recorded tracks in the music folders, in name order (as res:// or user:// paths).
## Music in local_music/ takes over: when it has any tracks, only those play.
static func find_tracks() -> Array[String]:
	var found := _local_tracks()
	if not found.is_empty():
		return found
	for folder: String in FOLDERS:
		if not DirAccess.dir_exists_absolute(folder):
			continue
		var names := []
		for file: String in DirAccess.get_files_at(folder):
			# Exported games list imported files by their .import (or .remap) entries.
			var name := file.trim_suffix(".import").trim_suffix(".remap")
			if EXTENSIONS.has(name.get_extension()) and not names.has(name):
				names.append(name)
		names.sort()
		for name: String in names:
			found.append(folder + name)
	return found


## The tracks in local_music/: the project's copy when running from source, the one beside the executable
## in an exported game. Subfolders are searched too, in name order.
static func _local_tracks() -> Array[String]:
	var folder := ProjectSettings.globalize_path("res://" + LOCAL_FOLDER)
	if OS.has_feature("template"):
		var base := OS.get_executable_path().get_base_dir()
		# On macOS the executable sits in <name>.app/Contents/MacOS/; look beside the .app instead.
		if base.ends_with(".app/Contents/MacOS"):
			base = base.get_base_dir().get_base_dir().get_base_dir()
		folder = base.path_join(LOCAL_FOLDER)
	var found: Array[String] = []
	_scan(folder, found)
	return found


static func _scan(folder: String, found: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	var files := Array(DirAccess.get_files_at(folder))
	files.sort()
	for file: String in files:
		if EXTENSIONS.has(file.get_extension().to_lower()):
			found.append(folder.path_join(file))
	var dirs := Array(DirAccess.get_directories_at(folder))
	dirs.sort()
	for dir: String in dirs:
		_scan(folder.path_join(dir), found)


func _process(delta: float) -> void:
	if not _enabled:
		return
	GameSettings.ensure_loaded()
	var on := GameSettings.music_volume > 0
	if not _playlist.is_empty():
		if on and _track == -1:
			_next_track()
		elif not on and _track != -1:
			_track = -1
			_playing = ""
	else:
		var wanted := _wanted() if on else ""
		if wanted != _playing:
			var stream := _stream(wanted) if wanted != "" else null
			if wanted == "" or stream != null:
				_switch(wanted, stream)
	# Fade the current track in to the set volume and the other one out.
	var target := linear_to_db(GameSettings.MUSIC_VOLUMES[GameSettings.music_volume]) if _playing != "" else -80.0
	for i in 2:
		var player := _players[i]
		var goal := target if i == _active else -80.0
		player.volume_db = move_toward(player.volume_db, goal, 80.0 * delta / FADE)
		if player.playing and player.volume_db <= -79.0 and (i != _active or _playing == ""):
			player.stop()


## The next recorded track, after the last one the first again.
func _next_track() -> void:
	if _playlist.is_empty() or GameSettings.music_volume == 0:
		return
	for attempt in _playlist.size():
		_track = (_track + 1) % _playlist.size()
		var stream := _load(_playlist[_track])
		if stream != null:
			_switch(_playlist[_track], stream, true)
			return


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var stream: AudioStream = null
	if path.begins_with("res://"):
		stream = load(path) as AudioStream
	else:
		match path.get_extension().to_lower():
			"mp3":
				stream = AudioStreamMP3.load_from_file(path)
			"ogg":
				stream = AudioStreamOggVorbis.load_from_file(path)
			"wav":
				stream = AudioStreamWAV.load_from_file(path)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	_cache[path] = stream
	return stream


## "<theatre>_<mood>" for what's on screen (composed themes).
func _wanted() -> String:
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == BATTLE_SCENE and GameSession.battle != null:
		return "%s_battle" % GameSession.battle.theatre_id
	return "%s_menu" % menu_theatre


## Starts a stream on the idle player; the playing one fades out. A playlist track starts at full volume
## straight after the last one ended, instead of fading in.
func _switch(key: String, stream: AudioStream, immediate := false) -> void:
	_playing = key
	_active = 1 - _active
	var player := _players[_active]
	player.stream = stream
	player.volume_db = linear_to_db(GameSettings.MUSIC_VOLUMES[GameSettings.music_volume]) if immediate else -80.0
	if stream != null:
		player.play()


## The composed theme for a key, or null while it is still being composed (it starts as soon as it's ready).
func _stream(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	if _thread != null and not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
	if _thread == null:
		var parts := key.split("_")
		_thread = Thread.new()
		_thread.start(_compose.bind(key, parts[0], parts[1]))
	return null


func _compose(key: String, theatre_id: String, mood: String) -> void:
	var stream := MusicComposer.render(theatre_id, mood)
	_store.call_deferred(key, stream)


func _store(key: String, stream: AudioStream) -> void:
	_cache[key] = stream


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
