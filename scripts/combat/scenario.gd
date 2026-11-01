class_name Scenario
extends RefCounted
## A hand-made battle: the map, both sides' units on exact tiles, objectives, reinforcement waves and the
## rules, saved as JSON that is easy to read and edit by hand. Made in the map editor, shipped in
## res://scenarios/, saved to user://scenarios/, and played or simulated (tools/balance.gd) like any skirmish.
##
## File format, version 1 (keys may come in any order; everything but "map" is optional):
## [codeblock]
## {
##   "format": "normandy-1944-scenario", "version": 1,
##   "theatre": "normandy" (optional, see Theatres; Normandy if left out),
##   "title": "Hedgerow ambush", "briefing": "Hold the crossroads.",
##   "vp_to_win": 12, "max_rounds": 20, "mirrored": true,
##   "map": {
##     "width": 4, "height": 3,
##     "legend": {".": "Grass", ",": "Rough ground", ...},   (informative; see TERRAIN_CHARS)
##     "terrain": ["..=.", "..=.", "ww=."],                   (one string per row, one char per tile)
##     "objects": [[1, 0, "tree"], [2, 2, "sandbags"]],      ([x, y, kind], cover comes from the kind)
##     "edges": [[0, 1, "E", "hedge"], [3, 0, "S", "wall"]], ([x, y, side N/E/S/W of that tile, kind])
##     "mines": [[2, 0], [3, 1, "punji"]]                     (buried mines or punji traps; optional)
##     "tunnels": [[5, 2, "Viet Cong"]]                       (tunnel entrances and whose they are; optional)
##   },
##   "objectives": [{"name": "Crossroads", "center": [2, 1.5], "radius": 2.5}],
##   "units": [{"team": "Allies", "role": "Officer", "pos": [0, 1], "facing": "E", "name": "Lt. Adams", "rank": 1}],
##   "reinforcements": [{"round": 4, "team": "Germany", "roster": ["Tank", "Rifleman"], "spawns": [[3, 1]]}]
## }
## [/codeblock]
## "team" is the side's name in its theatre, "Allies"/"Germany" in Normandy (or 0/1), "facing" one of N, NE, E, SE, S, SW, W, NW. Units without a name
## get one from the battle seed. Roster entries may also be {"role", "name", "rank"}. "mirrored" tells the
## editor to keep the east half a mirror image of the west half; the file always holds the whole map.

const FORMAT := "normandy-1944-scenario"
const VERSION := 1
const BUNDLED_DIR := "res://scenarios/"
const USER_DIR := "user://scenarios/"
## One character per TacticalMap.Terrain value, in enum order.
const TERRAIN_CHARS := ".,:#=wotxj~g"
## Object and edge kinds and the cover they give.
const OBJECT_COVER := {"rock": Cover.FULL, "tree": Cover.FULL, "crate": Cover.HALF, "sandbags": Cover.HALF, "hay": Cover.HALF, "pew": Cover.HALF, "wreck": Cover.FULL,
		"fuel": Cover.HALF, "oil_tank": Cover.FULL, "palm": Cover.FULL, "bamboo": Cover.FULL, "rice_sacks": Cover.HALF,
		"car": Cover.FULL, "hesco": Cover.FULL, "jersey": Cover.HALF}
const EDGE_COVER := {"wall": Cover.FULL, "hedge": Cover.FULL, "window": Cover.HALF, "stone": Cover.HALF, "fence": Cover.HALF,
		"dyke": Cover.HALF, "bamboo_wall": Cover.FULL, "bamboo_window": Cover.HALF, "mud_wall": Cover.FULL, "mud_window": Cover.HALF}
const FACINGS := {
	"N": Vector2i(0, -1), "NE": Vector2i(1, -1), "E": Vector2i(1, 0), "SE": Vector2i(1, 1),
	"S": Vector2i(0, 1), "SW": Vector2i(-1, 1), "W": Vector2i(-1, 0), "NW": Vector2i(-1, -1),
}
const SIDES := {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}

var theatre_id := Theatres.DEFAULT
var title := "Untitled scenario"
var briefing := ""
var vp_to_win := 12
var max_rounds := 20
## Whether the editor mirrors edits from one half onto the other.
var mirrored := true
var map: TacticalMap
## Each: {"name": String, "center": Vector2 (grid), "radius": float}.
var objectives: Array[Dictionary] = []
## Each: {"team": int, "role": String, "pos": Vector2i, "facing": Vector2i, "name": String ("" = from the seed), "rank": int}.
var units: Array[Dictionary] = []
## Each: {"round": int, "team": int, "roster": Array (role names or {"role", "name", "rank"}), "spawns": Array[Vector2i]}.
var reinforcements: Array[Dictionary] = []
## Why the last from_data/load_file failed, if it did.
static var last_error := ""


## An empty grass map.
static func create(width: int, height: int, p_theatre := Theatres.DEFAULT) -> Scenario:
	var s := Scenario.new()
	s.theatre_id = p_theatre
	s.map = TacticalMap.new(width, height)
	return s


func theatre() -> Theatre:
	return Theatres.get_theatre(theatre_id)


## "Allies Rifleman": a side and role, for messages.
func _who(u: Dictionary) -> String:
	return "%s %s" % [theatre().team_name(u["team"]), theatre().role_name(u["team"], u["role"])]


## A unit entry with the defaults filled in.
static func unit_entry(team: int, role: String, pos: Vector2i, facing := Vector2i.ZERO, unit_name := "", rank := 0) -> Dictionary:
	if facing == Vector2i.ZERO:
		facing = Vector2i(1, 0) if team == 0 else Vector2i(-1, 0)
	return {"team": team, "role": role, "pos": pos, "facing": facing, "name": unit_name, "rank": rank}


# --- Building a battle ---

## The battle this scenario describes. The same seed always gives the same battle.
func build_battle(seed := 0) -> Battle:
	var rosters := [[], []]
	for u in units:
		var spec := {"role": u["role"], "pos": u["pos"], "facing": u["facing"], "rank": u["rank"]}
		if u["name"] != "":
			spec["name"] = u["name"]
		rosters[u["team"]].append(spec)
	var waves := []
	for wave in reinforcements:
		var spawns: Array = wave["spawns"]
		if spawns.is_empty():
			spawns = [_default_spawn(wave["team"])]
		waves.append({"round": wave["round"], "team": wave["team"], "roster": wave["roster"].duplicate(true), "spawns": spawns.duplicate()})
	var layout := {"map": copy_map(map), "objectives": objectives.duplicate(true), "spawns": [], "reinforcement_spawns": []}
	var options := {"theatre": theatre_id, "vp_to_win": vp_to_win, "max_rounds": max_rounds, "reinforcements": waves}
	options.merge(theatre().battle_options())
	return BattleFactory.create(layout, rosters, seed, options)


## A start tile for a wave without spawns: the team's first unit, or the middle of its map edge.
func _default_spawn(team: int) -> Vector2i:
	for u in units:
		if u["team"] == team:
			return u["pos"]
	return Vector2i(0 if team == 0 else map.width - 1, map.height / 2)


## A scenario capturing a battle as it stands (before it starts, ideally): map, living units, objectives,
## waves still to come and rules. Without keep_names, units get fresh names from each battle's seed.
static func from_battle(battle: Battle, p_title := "", keep_names := true) -> Scenario:
	var s := Scenario.new()
	s.theatre_id = battle.theatre_id
	s.title = p_title if p_title != "" else "Exported battle"
	s.map = copy_map(battle.map)
	s.vp_to_win = battle.vp_to_win
	s.max_rounds = battle.max_rounds
	for objective in battle.objectives:
		s.objectives.append({"name": objective["name"], "center": Vector2(objective["center"]), "radius": float(objective["radius"])})
	for u in battle.alive_units():
		s.units.append(unit_entry(u.team, u.role, u.pos, u.facing, u.name if keep_names else "", u.rank))
	for wave in battle.reinforcements:
		var roster := []
		var spawns: Array[Vector2i] = []
		for u: Unit in wave["units"]:
			roster.append({"role": u.role, "name": u.name, "rank": u.rank} if keep_names else (u.role if u.rank == 0 else {"role": u.role, "rank": u.rank}))
			spawns.append(u.pos)
		s.reinforcements.append({"round": wave["round"], "team": wave["team"], "roster": roster, "spawns": spawns})
	s.mirrored = s.is_symmetric()
	return s


## A battle layout (as made by MapGenerator or NormandyScenario) with rosters placed, as a scenario.
static func from_layout(layout: Dictionary, rosters: Array, seed := 0, options := {}, p_title := "") -> Scenario:
	return from_battle(BattleFactory.create(layout, rosters, seed, options), p_title, false)


## A copy of a map's terrain, objects and walls, without smoke or tanks. Walls go in a fixed order.
static func copy_map(source: TacticalMap) -> TacticalMap:
	var copy := TacticalMap.new(source.width, source.height)
	for y in source.height:
		for x in source.width:
			var p := Vector2i(x, y)
			copy.set_terrain(p, source.get_terrain(p))
			if source.get_object(p) != Cover.NONE:
				copy.set_object(p, source.get_object(p), source.get_object_kind(p))
			if source.has_mine(p):
				copy.set_mine(p, true, source.get_mine_kind(p))
			if source.tunnel_owner(p) != -1:
				copy.set_tunnel(p, source.tunnel_owner(p))
	for key in _sorted_edges(source):
		var pair := TacticalMap.edge_tiles(key)
		copy.set_edge(pair[0], pair[1], source.get_edges()[key], source.edge_kind(key))
	return copy


static func _sorted_edges(source: TacticalMap) -> Array[Vector3i]:
	var keys: Array[Vector3i] = []
	keys.assign(source.get_edges().keys())
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return [a.y, a.x, a.z] < [b.y, b.x, b.z])
	return keys


# --- Mirroring ---

func mirror_tile(p: Vector2i) -> Vector2i:
	return Vector2i(map.width - 1 - p.x, p.y)


func mirror_point(g: Vector2) -> Vector2:
	return Vector2(map.width - g.x, g.y)


## -1 west of the centre line, 0 on it, 1 east of it.
func half_of(p: Vector2i) -> int:
	return signi(2 * p.x - (map.width - 1))


func _edge_half(key: Vector3i) -> int:
	var pair := TacticalMap.edge_tiles(key)
	return signi(pair[0].x + pair[1].x - (map.width - 1))


## Whether the map's east half is the mirror image of its west half.
func is_symmetric() -> bool:
	for y in map.height:
		for x in map.width / 2:
			var p := Vector2i(x, y)
			var m := mirror_tile(p)
			if map.get_terrain(p) != map.get_terrain(m) or map.get_object(p) != map.get_object(m) or map.get_object_kind(p) != map.get_object_kind(m) \
					or map.has_mine(p) != map.has_mine(m):
				return false
	for key: Vector3i in map.get_edges():
		var pair := TacticalMap.edge_tiles(key)
		var a := mirror_tile(pair[0])
		var b := mirror_tile(pair[1])
		if map.get_edge(a, b) != map.get_edges()[key] or map.get_edge_kind(a, b) != map.edge_kind(key):
			return false
	return true


## Rebuilds the east half as the mirror image of the west half: ground, cover, objectives east of the
## centre line, German units (mirrored Allied ones) and German reinforcement waves.
func mirror_west_to_east() -> void:
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if half_of(p) < 0:
				var m := mirror_tile(p)
				map.set_terrain(m, map.get_terrain(p))
				map.set_object(m, map.get_object(p), map.get_object_kind(p) if map.get_object(p) != Cover.NONE else "")
				map.set_mine(m, map.has_mine(p), map.get_mine_kind(p))
	for key: Vector3i in map.get_edges().keys():
		if _edge_half(key) > 0:
			var pair := TacticalMap.edge_tiles(key)
			map.set_edge(pair[0], pair[1], Cover.NONE)
	for key in _sorted_edges(map):
		if _edge_half(key) < 0:
			var pair := TacticalMap.edge_tiles(key)
			map.set_edge(mirror_tile(pair[0]), mirror_tile(pair[1]), map.get_edges()[key], map.edge_kind(key))
	var kept: Array[Dictionary] = []
	for objective in objectives:
		var x: float = objective["center"].x
		if x <= map.width * 0.5 + 0.01:
			kept.append(objective)
			if x < map.width * 0.5 - 0.01:
				kept.append({"name": objective["name"] + " (east)", "center": mirror_point(objective["center"]), "radius": objective["radius"]})
	objectives = kept
	var allied := units.filter(func(u: Dictionary) -> bool: return u["team"] == 0)
	units.assign(allied)
	for u: Dictionary in allied:
		units.append(mirrored_unit(u))
	var waves := reinforcements.filter(func(w: Dictionary) -> bool: return w["team"] == 0)
	reinforcements.assign(waves)
	for wave: Dictionary in waves:
		reinforcements.append(_mirrored_wave(wave))


## The other side's counterpart of a unit, on the mirror tile and facing the other way. Names aren't copied.
func mirrored_unit(u: Dictionary) -> Dictionary:
	var facing: Vector2i = u["facing"]
	return unit_entry(1 - u["team"], u["role"], mirror_tile(u["pos"]), Vector2i(-facing.x, facing.y), "", u["rank"])


func _mirrored_wave(wave: Dictionary) -> Dictionary:
	var spawns: Array[Vector2i] = []
	for p: Vector2i in wave["spawns"]:
		spawns.append(mirror_tile(p))
	var roster: Array = wave["roster"].map(func(e: Variant) -> Variant: return e["role"] if e is Dictionary and e.get("rank", 0) == 0 else e)
	return {"round": wave["round"], "team": 1 - wave["team"], "roster": roster, "spawns": spawns}


## The same battle with the sides' starting positions exchanged: the map flipped east to west and every
## unit, wave and objective moved across with it, each force handed to the other side (Allies still move
## first). Comparing results with the original separates the ground's advantage from the first move.
func swapped() -> Scenario:
	var s := Scenario.new()
	s.title = title + " (sides swapped)"
	s.briefing = briefing
	s.vp_to_win = vp_to_win
	s.max_rounds = max_rounds
	s.mirrored = mirrored
	s.map = TacticalMap.new(map.width, map.height)
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var m := mirror_tile(p)
			s.map.set_terrain(m, map.get_terrain(p))
			if map.get_object(p) != Cover.NONE:
				s.map.set_object(m, map.get_object(p), map.get_object_kind(p))
	for key in _sorted_edges(map):
		var pair := TacticalMap.edge_tiles(key)
		s.map.set_edge(mirror_tile(pair[0]), mirror_tile(pair[1]), map.get_edges()[key], map.edge_kind(key))
	for objective in objectives:
		s.objectives.append({"name": objective["name"], "center": mirror_point(objective["center"]), "radius": objective["radius"]})
	for team in 2:
		for u in units:
			if u["team"] == 1 - team:
				var m := mirrored_unit(u)
				m["name"] = u["name"]
				s.units.append(m)
	for wave in reinforcements:
		s.reinforcements.append(_mirrored_wave(wave))
	return s


# --- Checks ---

## Problems that would make the scenario unplayable or odd. Empty when all is well.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var taken := {}
	var counts := [0, 0]
	for u in units:
		var p: Vector2i = u["pos"]
		counts[u["team"]] += 1
		if not map.in_bounds(p):
			problems.append("%s at %s is off the map" % [_who(u), p])
		elif not map.is_passable(p):
			problems.append("%s at %s stands on an object" % [_who(u), p])
		if taken.has(p):
			problems.append("Two units share tile %s" % p)
		taken[p] = true
	for team in 2:
		if counts[team] == 0:
			problems.append("%s have no units" % theatre().team_name(team))
	if objectives.is_empty():
		problems.append("No objectives: the battle can only end by elimination, never on the round limit")
	for wave in reinforcements:
		for p: Vector2i in wave["spawns"]:
			if not map.is_passable(p):
				problems.append("Round %d %s reinforcement spawn %s is blocked" % [wave["round"], theatre().team_name(wave["team"]), p])
		if wave["roster"].is_empty():
			problems.append("Round %d %s reinforcement wave is empty" % [wave["round"], theatre().team_name(wave["team"])])
	# Each side's infantry must be able to walk to every objective.
	var checked := {}
	for u in units:
		if checked.has(u["team"]) or not map.in_bounds(u["pos"]) or not map.is_passable(u["pos"]) or theatre().role_def(u["team"], u["role"]).get("vehicle", false):
			continue
		checked[u["team"]] = true
		var reach := Pathfinder.search(map, u["pos"], 100000.0)
		for objective in objectives:
			var target := Vector2i(objective["center"])
			if not reach.has(target) and map.is_passable(target):
				problems.append("%s at %s can't reach %s" % [_who(u), u["pos"], objective["name"]])
	return problems


# --- JSON ---

## The scenario as plain JSON data.
func to_data() -> Dictionary:
	var legend := {}
	for i in TERRAIN_CHARS.length():
		legend[TERRAIN_CHARS[i]] = TacticalMap.TERRAIN_NAMES[i]
	var rows := []
	for y in map.height:
		var row := ""
		for x in map.width:
			row += TERRAIN_CHARS[map.get_terrain(Vector2i(x, y))]
		rows.append(row)
	var objects := []
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if map.get_object(p) != Cover.NONE:
				var kind := map.get_object_kind(p)
				var entry := [x, y, kind]
				if OBJECT_COVER.get(kind, -1) != map.get_object(p):
					entry.append("full" if map.get_object(p) == Cover.FULL else "half")
				objects.append(entry)
	var edges := []
	for key in _sorted_edges(map):
		var kind := map.edge_kind(key)
		var entry := [key.x, key.y, "E" if key.z == 0 else "S", kind]
		if EDGE_COVER.get(kind, -1) != map.get_edges()[key]:
			entry.append("full" if map.get_edges()[key] == Cover.FULL else "half")
		edges.append(entry)
	var mines := []
	for y in map.height:
		for x in map.width:
			if map.has_mine(Vector2i(x, y)):
				mines.append([x, y] if map.get_mine_kind(Vector2i(x, y)) == "mine" else [x, y, map.get_mine_kind(Vector2i(x, y))])
	var unit_data := []
	for u in units:
		var entry := {"team": theatre().team_name(u["team"]), "role": u["role"], "pos": _pair(u["pos"]), "facing": facing_name(u["facing"])}
		if u["name"] != "":
			entry["name"] = u["name"]
		if u["rank"] != 0:
			entry["rank"] = u["rank"]
		unit_data.append(entry)
	var wave_data := []
	for wave in reinforcements:
		wave_data.append({"round": wave["round"], "team": theatre().team_name(wave["team"]), "roster": wave["roster"].duplicate(true),
				"spawns": wave["spawns"].map(func(p: Vector2i) -> Array: return _pair(p))})
	var map_data := {"width": map.width, "height": map.height, "legend": legend, "terrain": rows, "objects": objects, "edges": edges}
	if not mines.is_empty():
		map_data["mines"] = mines
	var tunnels := []
	for y in map.height:
		for x in map.width:
			if map.tunnel_owner(Vector2i(x, y)) != -1:
				tunnels.append([x, y, theatre().team_name(map.tunnel_owner(Vector2i(x, y)))])
	if not tunnels.is_empty():
		map_data["tunnels"] = tunnels
	var data := {
		"format": FORMAT, "version": VERSION,
		"title": title, "briefing": briefing,
		"vp_to_win": vp_to_win, "max_rounds": max_rounds, "mirrored": mirrored,
		"map": map_data,
		"objectives": objectives.map(func(o: Dictionary) -> Dictionary: return {"name": o["name"], "center": _pair(o["center"]), "radius": _number(o["radius"])}),
		"units": unit_data,
		"reinforcements": wave_data,
	}
	if theatre_id != Theatres.DEFAULT:
		data["theatre"] = theatre_id
	return data


## Reads JSON data. Returns null (and sets last_error) if it isn't a usable scenario.
static func from_data(data: Variant) -> Scenario:
	last_error = ""
	if not data is Dictionary or not data.get("map") is Dictionary:
		last_error = "Not a scenario: no map"
		return null
	if data.get("format", FORMAT) != FORMAT or int(data.get("version", VERSION)) > VERSION:
		last_error = "Unknown scenario format or newer version"
		return null
	var m: Dictionary = data["map"]
	var width := int(m.get("width", 0))
	var height := int(m.get("height", 0))
	if width < 4 or height < 4 or width > 256 or height > 256:
		last_error = "Map size %dx%d is out of range" % [width, height]
		return null
	var theatre_name := str(data.get("theatre", Theatres.DEFAULT))
	if not Theatres.exists(theatre_name):
		last_error = "Unknown theatre: %s" % theatre_name
		return null
	var s := Scenario.create(width, height, theatre_name)
	s.title = str(data.get("title", s.title))
	s.briefing = str(data.get("briefing", ""))
	s.vp_to_win = int(data.get("vp_to_win", s.vp_to_win))
	s.max_rounds = int(data.get("max_rounds", s.max_rounds))
	s.mirrored = bool(data.get("mirrored", false))
	var chars := TERRAIN_CHARS
	if m.get("legend") is Dictionary:
		# A custom legend maps characters to terrain names.
		var custom := {}
		for c: String in m["legend"]:
			custom[c] = TacticalMap.TERRAIN_NAMES.find(m["legend"][c])
		var rows: Array = m.get("terrain", [])
		for y in mini(rows.size(), height):
			var row := str(rows[y])
			for x in mini(row.length(), width):
				var t: int = custom.get(row[x], chars.find(row[x]))
				s.map.set_terrain(Vector2i(x, y), maxi(0, t))
	else:
		var rows: Array = m.get("terrain", [])
		for y in mini(rows.size(), height):
			var row := str(rows[y])
			for x in mini(row.length(), width):
				s.map.set_terrain(Vector2i(x, y), maxi(0, chars.find(row[x])))
	for entry in m.get("objects", []):
		var p := Vector2i(int(entry[0]), int(entry[1]))
		var kind := str(entry[2]) if entry.size() > 2 else "crate"
		var cover: int = OBJECT_COVER.get(kind, Cover.HALF)
		if entry.size() > 3:
			cover = Cover.FULL if entry[3] == "full" else Cover.HALF
		if s.map.in_bounds(p):
			s.map.set_object(p, cover, kind)
	for entry in m.get("edges", []):
		var p := Vector2i(int(entry[0]), int(entry[1]))
		var side: Vector2i = SIDES.get(str(entry[2]), Vector2i(1, 0))
		var kind := str(entry[3]) if entry.size() > 3 else "wall"
		var cover: int = EDGE_COVER.get(kind, Cover.HALF)
		if entry.size() > 4:
			cover = Cover.FULL if entry[4] == "full" else Cover.HALF
		if s.map.in_bounds(p) and s.map.in_bounds(p + side):
			s.map.set_edge(p, p + side, cover, kind)
	for entry in m.get("mines", []):
		var p := Vector2i(int(entry[0]), int(entry[1]))
		if s.map.in_bounds(p):
			s.map.set_mine(p, true, str(entry[2]) if entry.size() > 2 else "mine")
	for entry in m.get("tunnels", []):
		var p := Vector2i(int(entry[0]), int(entry[1]))
		if s.map.in_bounds(p) and entry.size() > 2:
			s.map.set_tunnel(p, s._team(entry[2]))
	for o in data.get("objectives", []):
		s.objectives.append({"name": str(o.get("name", "Objective")), "center": _vec2(o.get("center", [0, 0])), "radius": float(o.get("radius", 2.5))})
	for u in data.get("units", []):
		var team := s._team(u.get("team", 0))
		var role := str(u.get("role", s.theatre().role_ids(team)[0]))
		if not s.theatre().has_role(team, role):
			last_error = "Unknown role: %s" % role
			return null
		s.units.append(unit_entry(team, role, _vec2i(u.get("pos", [0, 0])), FACINGS.get(str(u.get("facing", "")), Vector2i.ZERO),
				str(u.get("name", "")), int(u.get("rank", 0))))
	for w in data.get("reinforcements", []):
		var roster := []
		for e in w.get("roster", []):
			roster.append({"role": str(e["role"]), "name": str(e["name"]), "rank": int(e.get("rank", 0))} if e is Dictionary and e.has("name")
					else ({"role": str(e["role"]), "rank": int(e.get("rank", 0))} if e is Dictionary else str(e)))
		var wave_team := s._team(w.get("team", 0))
		for e in roster:
			var role: String = e["role"] if e is Dictionary else e
			if not s.theatre().has_role(wave_team, role):
				last_error = "Unknown role in reinforcements: %s" % role
				return null
		var spawns: Array[Vector2i] = []
		for p in w.get("spawns", []):
			spawns.append(_vec2i(p))
		s.reinforcements.append({"round": int(w.get("round", 4)), "team": wave_team, "roster": roster, "spawns": spawns})
	return s


## The scenario as JSON text, laid out for reading: one map row, object, wall, unit or objective per line.
func to_json() -> String:
	return _pretty(to_data(), "") + "\n"


func save_file(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_json())
	return OK


## Loads a scenario file, or returns null (with last_error set).
static func load_file(path: String) -> Scenario:
	if not FileAccess.file_exists(path):
		last_error = "No such file: %s" % path
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		last_error = "%s line %d: %s" % [path.get_file(), json.get_error_line(), json.get_error_message()]
		return null
	return from_data(json.data)


## Scenario files to offer: bundled ones first, then the player's. Each: {"path", "title", "user": bool, "theatre"}.
static func list_files() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for dir_path in [BUNDLED_DIR, USER_DIR]:
		if not DirAccess.dir_exists_absolute(dir_path):
			continue
		var files := Array(DirAccess.get_files_at(dir_path))
		files.sort()
		for file: String in files:
			if file.get_extension() != "json":
				continue
			var path: String = dir_path + file
			var json := JSON.new()
			var label := file.get_basename()
			var theatre_name := Theatres.DEFAULT
			if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary:
				label = str(json.data.get("title", label))
				theatre_name = str(json.data.get("theatre", theatre_name))
			found.append({"path": path, "title": label, "user": dir_path == USER_DIR, "theatre": theatre_name})
	return found


func _team(value: Variant) -> int:
	if value is String:
		return 1 if value.to_lower() == theatre().team_name(1).to_lower() else 0
	return clampi(int(value), 0, 1)


## The compass name (N, NE, ...) of a facing.
static func facing_name(dir: Vector2i) -> String:
	for key: String in FACINGS:
		if FACINGS[key] == dir:
			return key
	return "E"


static func _pair(v: Variant) -> Array:
	return [_number(v.x), _number(v.y)]


## Whole numbers as ints, so the file says 24 rather than 24.0.
static func _number(f: float) -> Variant:
	return int(f) if is_equal_approx(f, roundf(f)) else f


static func _vec2(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and a.size() >= 2 else Vector2.ZERO


static func _vec2i(a: Variant) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1])) if a is Array and a.size() >= 2 else Vector2i.ZERO


## JSON with small arrays and flat dictionaries kept on one line.
static func _pretty(value: Variant, indent: String) -> String:
	var inner := indent + "\t"
	if value is Dictionary:
		var flat := JSON.stringify(value, "", false)
		if _is_flat(value) and flat.length() <= 160:
			return flat
		var parts := PackedStringArray()
		for key in value:
			parts.append(inner + JSON.stringify(str(key)) + ": " + _pretty(value[key], inner))
		return "{\n" + ",\n".join(parts) + "\n" + indent + "}"
	if value is Array:
		var flat := JSON.stringify(value, "", false)
		if value.is_empty() or (_is_flat(value) and flat.length() <= 100):
			return flat
		var parts := PackedStringArray()
		for item in value:
			parts.append(inner + _pretty(item, inner))
		return "[\n" + ",\n".join(parts) + "\n" + indent + "]"
	return JSON.stringify(value)


## Whether every value is a scalar, or a short array of scalars.
static func _is_flat(value: Variant) -> bool:
	for item in (value.values() if value is Dictionary else value):
		if item is Dictionary:
			return false
		if item is Array:
			for x in item:
				if x is Array or x is Dictionary:
					return false
	return true
