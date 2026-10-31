class_name Battle
extends RefCounted
## The combat engine. Owns all battle state and applies the rules.
## Commands validate, change state and return event dictionaries for the view to play back.
## Event types: move, pivot, shot, throw, damage, death, explosion, smoke, smoke_clear, mortar_fire, strike,
## suppression, status, heal, objective, score, reinforcements, turn, game_over.
## A "shot" that went astray carries "stray" (the tile it ended up on) and, if it hit someone, "stray_unit".
##
## Every command can also be given as data through execute(), which is how AI moves, saved replays
## and the online opponent's moves are applied: {"cmd": "move", "unit": id, "tile": Vector2i}, etc.

const TEAM_COUNT := 2
const TEAM_NAMES := ["Allies", "Germany"]
## `winner` value when the game ends level.
const DRAW := 2
## throw_landings() samples a grenade's spread on this many rings of this many points.
const THROW_SAMPLE_RINGS := 4
const THROW_SAMPLE_SPOKES := 8

var map: TacticalMap
var units: Array[Unit] = []
var current_team := 0
var round_number := 1
## Counts every turn (both sides); smoke expiry is measured in these.
var turn_index := 0
## -1 while the battle is running, else the winning team or DRAW.
var winner := -1
var started := false
var rng := RandomNumberGenerator.new()

## Each: {"name": String, "center": Vector2 (grid), "radius": float, "owner": int (-1 = nobody)}.
var objectives: Array[Dictionary] = []
var victory_points := [0, 0]
var vp_to_win := 12
var max_rounds := 20
## Each: {"round": int, "team": int, "units": Array[Unit]}. Units join at the start of that team's turn.
var reinforcements: Array[Dictionary] = []
## Mortar shells in the air: {"team", "unit", "target": Vector2i, "kind": "he" or "smoke"}.
var strikes: Array[Dictionary] = []

## Vector3i(x, y, sight) -> tiles visible from there. Rebuilt when the map changes.
var _vision := {}
var _vision_revision := -1


func _init(p_map: TacticalMap, p_units: Array[Unit], p_seed := 0) -> void:
	map = p_map
	units = p_units
	if p_seed != 0:
		rng.seed = p_seed


func start() -> Array:
	started = true
	for u in alive_units():
		if u.vehicle:
			map.set_vehicle(u.pos, true)
	return _begin_turn(current_team)


# --- Queries ---

func get_unit(id: int) -> Unit:
	for u in units:
		if u.id == id:
			return u
	return null


func unit_at(p: Vector2i) -> Unit:
	for u in units:
		if u.is_alive() and u.pos == p:
			return u
	return null


func alive_units(team := -1) -> Array[Unit]:
	var result: Array[Unit] = []
	for u in units:
		if u.is_alive() and (team == -1 or u.team == team):
			result.append(u)
	return result


func enemies_of(u: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	for other in alive_units():
		if other.team != u.team:
			result.append(other)
	return result


## Tiles the unit can reach with its remaining actions: {tile: {"cost": float, "prev": Vector2i}}.
func reachable(u: Unit) -> Dictionary:
	if u == null or not u.is_alive() or u.actions <= 0 or u.is_pinned():
		return {}
	var blocked := {}
	for other in alive_units():
		if other != u:
			blocked[other.pos] = true
	return Pathfinder.search(map, u.pos, u.current_mobility() * mini(u.actions, Unit.ACTIONS_PER_TURN), blocked, u.vehicle, u.facing)


## Actions used by a move of the given path cost: one for a normal move, two for a dash.
func actions_for_cost(u: Unit, cost: float) -> int:
	return 1 if cost <= u.current_mobility() + 0.001 else 2


func can_see(viewer: Unit, target: Unit) -> bool:
	return LineOfSight.can_see(map, viewer.pos, target.pos, viewer.sight)


func visible_enemies(u: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	for e in enemies_of(u):
		if can_see(u, e):
			result.append(e)
	return result


func team_sees(team: int, target: Unit) -> bool:
	if target.team == team:
		return true
	for u in alive_units(team):
		if can_see(u, target):
			return true
	return false


## Set of tiles currently in sight of any unit on the team (everything else is fog of war).
func team_visible_tiles(team: int) -> Dictionary:
	var result := {}
	for u in alive_units(team):
		result.merge(visible_from(u.pos, u.sight))
	return result


func visible_from(pos: Vector2i, sight: float) -> Dictionary:
	if _vision_revision != map.revision:
		_vision.clear()
		_vision_revision = map.revision
	var key := Vector3i(pos.x, pos.y, roundi(sight * 10))
	if not _vision.has(key):
		var tiles := {}
		var r := ceili(sight)
		for y in range(pos.y - r, pos.y + r + 1):
			for x in range(pos.x - r, pos.x + r + 1):
				var p := Vector2i(x, y)
				if map.in_bounds(p) and LineOfSight.can_see(map, pos, p, sight, false):
					tiles[p] = true
		_vision[key] = tiles
	return _vision[key]


func shot_odds(shooter: Unit, target: Unit, reaction := false) -> Dictionary:
	return CombatRules.shot_odds(map, shooter, target, reaction)


func officer_near(u: Unit) -> bool:
	for ally in alive_units(u.team):
		if ally != u and ally.role == "Officer" and Vector2(ally.pos).distance_to(Vector2(u.pos)) <= CombatRules.OFFICER_RADIUS:
			return true
	return false


## Where a mortar shell could land when aimed at target from origin.
static func mortar_scatter(origin: Vector2i, target: Vector2i) -> float:
	return Vector2(origin).distance_to(Vector2(target)) * CombatRules.MORTAR_SCATTER


## Where a grenade aimed at `tile` with this scatter (CombatRules.throw_scatter) may land: {tile: probability}.
## Samples the same spread throw_grenade rolls, walls included, so previews and the AI match the dice.
func throw_landings(tile: Vector2i, scatter: float) -> Dictionary:
	if scatter <= 0.0:
		return {tile: 1.0}
	var result := {}
	var weight := 1.0 / (THROW_SAMPLE_RINGS * THROW_SAMPLE_SPOKES)
	for ring in THROW_SAMPLE_RINGS:
		for spoke in THROW_SAMPLE_SPOKES:
			var offset := Vector2.from_angle((spoke + 0.5) / THROW_SAMPLE_SPOKES * TAU) * (ring + 0.5) / THROW_SAMPLE_RINGS * scatter
			var spot := _throw_landing(tile, offset, scatter)
			result[spot] = result.get(spot, 0.0) + weight
	return result


## Tiles a missed rocket or tank shell fired from `from` at `target` may land on (see CombatRules.STRAY_*).
func stray_tiles(from: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var dir := Vector2(target - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	var r := ceili(CombatRules.STRAY_LONG + CombatRules.STRAY_WIDTH)
	for y in range(target.y - r, target.y + r + 1):
		for x in range(target.x - r, target.x + r + 1):
			var p := Vector2i(x, y)
			var offset := Vector2(p - target)
			var along := offset.dot(dir)
			if p == target or not map.in_bounds(p) or Vector2(p).distance_to(Vector2(from)) < 1.5:
				continue
			if along >= -CombatRules.STRAY_SHORT - 0.01 and along <= CombatRules.STRAY_LONG + 0.01 and absf(offset.dot(side)) <= CombatRules.STRAY_WIDTH + 0.01:
				result.append(p)
	return result


## Everyone but the target a machine gun firing from `from` could hit with a miss: anyone beside the target,
## or close to the line of fire between the gun and the target. Tanks are safe from it.
func mg_bystanders(shooter: Unit, from: Vector2i, target: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	var a := Vector2(from)
	var b := Vector2(target.pos)
	for u in alive_units():
		if u == shooter or u == target or u.vehicle:
			continue
		var p := Vector2(u.pos)
		var t := (p - a).dot(b - a) / maxf(0.001, a.distance_squared_to(b))
		var near_line := t > 0.0 and t < 1.0 and p.distance_to(a.lerp(b, t)) <= CombatRules.MG_STRAY_LINE
		if near_line or p.distance_to(b) <= CombatRules.MG_AREA_RADIUS:
			result.append(u)
	return result


## Who else a shot from `from` could hurt if it misses: [{"unit", "chance" (0-1, given a miss), "damage" (expected
## if it does)}]. Machine guns endanger bystanders near the line of fire; rockets and shells whoever is near
## where they may land. Empty for other weapons.
func stray_risks(shooter: Unit, from: Vector2i, target: Unit) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var weapon := shooter.weapon
	var rolls := weapon.damage_max - weapon.damage_min + 1
	if weapon.needs_setup:
		var half := 0.0
		for d in range(weapon.damage_min, weapon.damage_max + 1):
			half += maxi(1, floori(d / 2.0)) / float(rolls)
		# Bystanders are rolled for in turn, and only one can be hit.
		var untouched := 1.0
		for u in mg_bystanders(shooter, from, target):
			var chance := untouched * CombatRules.MG_STRAY_CHANCE / 100.0
			untouched -= chance
			result.append({"unit": u, "chance": chance, "damage": maxf(0.0, half - u.armor)})
	elif weapon.anti_tank:
		var radius := weapon.blast_radius if weapon.blast_radius > 0.0 else CombatRules.ROCKET_BLAST_RADIUS
		var reach := CombatRules.STRAY_LONG + CombatRules.STRAY_WIDTH + radius
		var tiles: Array[Vector2i] = []
		for u in alive_units():
			if u != shooter and u != target and Vector2(u.pos).distance_to(Vector2(target.pos)) <= reach:
				tiles = stray_tiles(from, target.pos)
				break
		var direct := (weapon.damage_min + weapon.damage_max) / 2.0
		var splash := (CombatRules.SPLASH_DAMAGE_MIN + CombatRules.SPLASH_DAMAGE_MAX) / 2.0
		var hit_chance := CombatRules.STRAY_HIT_CHANCE / 100.0
		for u in alive_units():
			if u == shooter or u == target or tiles.is_empty():
				continue
			if Vector2(u.pos).distance_to(Vector2(target.pos)) > reach:
				continue
			var on := 0
			var near := 0
			for t in tiles:
				if t == u.pos:
					on += 1
				elif Vector2(t).distance_to(Vector2(u.pos)) <= radius:
					near += 1
			if on + near == 0:
				continue
			var hit := maxf(0.0, direct - u.armor)
			var blast := maxf(0.0, splash - u.armor)
			if u.vehicle:
				hit = maxf(0.0, direct - CombatRules.VEHICLE_ARMOR[CombatRules.armor_side(u, from)])
				blast = maxf(0.0, splash - CombatRules.EXPLOSION_VS_ARMOR)
			var damage := (on * (hit_chance * hit + (1.0 - hit_chance) * blast) + near * blast) / (on + near)
			if damage > 0.0:
				result.append({"unit": u, "chance": float(on + near) / tiles.size(), "damage": damage})
	return result


# --- Validation: each returns "" when allowed, otherwise the reason it isn't ---

func can_act(u: Unit) -> String:
	if winner != -1:
		return "The battle is over"
	if u == null or not u.is_alive():
		return "No unit selected"
	if u.team != current_team:
		return "Not your unit"
	if u.actions <= 0:
		return "No actions left"
	return ""


func can_move(u: Unit, dest: Vector2i) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if u.is_pinned():
		return "Pinned down, can't move"
	if dest == u.pos or not reachable(u).has(dest):
		return "Can't reach that tile"
	return ""


func can_shoot(u: Unit, target: Unit) -> String:
	var err := can_fire(u)
	if err != "":
		return err
	if target == null or not target.is_alive() or target.team == u.team:
		return "Not a valid target"
	if not can_see(u, target):
		return "No line of sight"
	return ""


## Whether the unit's weapon is ready to fire at all (shoot or overwatch).
func can_fire(u: Unit) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if u.ammo <= 0:
		return "Out of ammo, reload first"
	if u.weapon.needs_setup and not u.deployed:
		return "Set up the machine gun first"
	return ""


func can_overwatch(u: Unit) -> String:
	var err := can_fire(u)
	if err != "":
		return err
	if u.is_pinned():
		return "Pinned down"
	return ""


func can_set_up(u: Unit) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if not u.weapon.needs_setup:
		return "Only machine guns need setting up"
	if u.deployed:
		return "Already set up"
	return ""


## Tanks can turn on the spot to face a direction (one of Pathfinder.HEADINGS) for one action.
func can_pivot(u: Unit, dir: Vector2i) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if not u.vehicle:
		return "Only tanks turn on the spot"
	if not Pathfinder.HEADINGS.has(dir):
		return "Not a direction"
	if dir == u.facing:
		return "Already facing that way"
	return ""


func can_hunker(u: Unit) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if u.vehicle:
		return "Tanks can't hunker down"
	if not map.has_cover(u.pos):
		return "Needs cover to hunker down"
	return ""


func can_reload(u: Unit) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if u.ammo >= u.weapon.clip_size:
		return "Already fully loaded"
	return ""


func can_rally(u: Unit) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if u.role != "Officer":
		return "Only officers can rally"
	for ally in alive_units(u.team):
		if ally.suppression > 0 and Vector2(ally.pos).distance_to(Vector2(u.pos)) <= CombatRules.OFFICER_RADIUS:
			return ""
	return "Nobody nearby needs rallying"


func can_throw_grenade(u: Unit, tile: Vector2i) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if u.grenades <= 0:
		return "No grenades left"
	return _check_throw(u, tile, CombatRules.GRENADE_RANGE)


func can_throw_smoke(u: Unit, tile: Vector2i) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if u.smoke_grenades <= 0:
		return "No smoke grenades left"
	return _check_throw(u, tile, CombatRules.SMOKE_RANGE)


func can_fire_mortar(u: Unit, tile: Vector2i, kind: String) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if u.role != "Mortar":
		return "Only the mortar team can fire the mortar"
	if (u.mortar_rounds if kind == "he" else u.mortar_smoke) <= 0:
		return "No %s rounds left" % ("high explosive" if kind == "he" else "smoke")
	if u.actions < Unit.ACTIONS_PER_TURN:
		return "The mortar can't fire after moving"
	if not map.in_bounds(tile):
		return "Out of bounds"
	var distance := Vector2(u.pos).distance_to(Vector2(tile))
	if distance < CombatRules.MORTAR_MIN_RANGE:
		return "Too close for the mortar"
	if distance > CombatRules.MORTAR_MAX_RANGE:
		return "Out of mortar range"
	if not team_visible_tiles(u.team).has(tile):
		return "Nobody can spot that tile"
	return ""


func can_use_medkit(u: Unit, target: Unit) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if u.medkits <= 0:
		return "No medkits left"
	if target == null or not target.is_alive() or target.team != u.team:
		return "Can only treat allies"
	if target.vehicle:
		return "A medic can't fix a tank"
	if absi(target.pos.x - u.pos.x) > 1 or absi(target.pos.y - u.pos.y) > 1:
		return "Must be adjacent"
	if target.hp >= target.max_hp and not target.is_wounded():
		return "Not hurt"
	return ""


func _check_throw(u: Unit, tile: Vector2i, throw_range: float) -> String:
	if not map.in_bounds(tile):
		return "Out of bounds"
	if not LineOfSight.can_see(map, u.pos, tile, throw_range, false):
		return "Out of range or line of sight"
	return ""


# --- Commands: return [] when not allowed ---

func move(u: Unit, dest: Vector2i) -> Array:
	if can_move(u, dest) != "":
		return []
	var reach := reachable(u)
	u.actions -= actions_for_cost(u, reach[dest]["cost"])
	u.deployed = false
	var events := []
	var segment: Array[Vector2i] = [u.pos]
	# Tanks: the hull's heading after each step (they turn, and may back up).
	var facings: Array = reach[dest].get("facings", [])
	var segment_facings: Array[Vector2i] = [u.facing]
	var path := Pathfinder.path_to(reach, dest)
	for i in path.size():
		var step := path[i]
		var previous := u.pos
		u.pos = step
		u.facing = facings[i] if u.vehicle else step - previous
		if u.vehicle:
			_drive(previous, step)
		segment.append(step)
		segment_facings.append(u.facing)
		for watcher in _overwatchers_seeing(u):
			if segment.size() > 1:
				events.append({"type": "move", "unit": u.id, "path": segment, "facings": segment_facings})
				segment = [step]
				segment_facings = [u.facing]
			events.append_array(_fire(watcher, u, true))
			if not u.is_alive() or u.is_pinned():
				break
		if not u.is_alive():
			break
		if u.is_pinned():
			# Pinned by fire on the way: the rest of the move is lost.
			u.actions = 0
			events.append({"type": "status", "unit": u.id, "text": "Pinned down!"})
			break
	if segment.size() > 1:
		events.append({"type": "move", "unit": u.id, "path": segment, "facings": segment_facings})
	events.append_array(_after_action())
	return events


## Shooting always ends the unit's turn.
func shoot(u: Unit, target: Unit) -> Array:
	if can_shoot(u, target) != "":
		return []
	u.actions = 0
	var events := _fire(u, target, false)
	events.append_array(_after_action())
	return events


func overwatch(u: Unit) -> Array:
	if can_overwatch(u) != "":
		return []
	u.actions = 0
	u.overwatch = true
	return _status(u, "Overwatch")


func set_up(u: Unit) -> Array:
	if can_set_up(u) != "":
		return []
	u.actions -= 1
	u.deployed = true
	return _status(u, "MG set up")


func pivot(u: Unit, dir: Vector2i) -> Array:
	if can_pivot(u, dir) != "":
		return []
	u.actions -= 1
	var events: Array = [{"type": "pivot", "unit": u.id, "from": u.facing, "to": dir}]
	u.facing = dir
	events.append_array(_after_action())
	return events


func hunker(u: Unit) -> Array:
	if can_hunker(u) != "":
		return []
	u.actions = 0
	u.hunkered = true
	return _status(u, "Hunkered down")


func reload(u: Unit) -> Array:
	if can_reload(u) != "":
		return []
	u.actions -= 1
	u.ammo = u.weapon.clip_size
	return _status(u, "Reloaded")


func rally(u: Unit) -> Array:
	if can_rally(u) != "":
		return []
	u.actions -= 1
	var events: Array = [{"type": "status", "unit": u.id, "text": "Rally!"}]
	for ally in alive_units(u.team):
		if ally.suppression > 0 and Vector2(ally.pos).distance_to(Vector2(u.pos)) <= CombatRules.OFFICER_RADIUS:
			events.append_array(_suppress(ally, -CombatRules.RALLY_AMOUNT))
	events.append_array(_after_action())
	return events


## Grenades ignore cover, destroy it, shred armor and hit everyone in the blast, friends included.
## They may land off target (CombatRules.throw_scatter) and bounce back off walls.
func throw_grenade(u: Unit, tile: Vector2i) -> Array:
	if can_throw_grenade(u, tile) != "":
		return []
	u.actions = 0
	u.grenades -= 1
	var landing := _roll_throw(u, tile)
	var events: Array = [{"type": "throw", "unit": u.id, "target": tile, "center": landing, "kind": "grenade"}]
	events.append_array(_explode(u, landing, CombatRules.GRENADE_RADIUS, CombatRules.GRENADE_DAMAGE_MIN, CombatRules.GRENADE_DAMAGE_MAX, CombatRules.GRENADE_SHRED))
	events.append_array(_after_action())
	return events


## Throwing smoke takes one action, so the thrower can still move through it.
func throw_smoke(u: Unit, tile: Vector2i) -> Array:
	if can_throw_smoke(u, tile) != "":
		return []
	u.actions -= 1
	u.smoke_grenades -= 1
	var landing := _roll_throw(u, tile)
	var events: Array = [{"type": "throw", "unit": u.id, "target": tile, "center": landing, "kind": "smoke"}]
	events.append_array(_make_smoke(u, landing, CombatRules.SMOKE_RADIUS))
	events.append_array(_after_action())
	return events


## The shell lands at the start of this team's next turn, scattered around the target.
func fire_mortar(u: Unit, tile: Vector2i, kind: String) -> Array:
	if can_fire_mortar(u, tile, kind) != "":
		return []
	u.actions = 0
	if kind == "he":
		u.mortar_rounds -= 1
	else:
		u.mortar_smoke -= 1
	strikes.append({"team": u.team, "unit": u.id, "target": tile, "kind": kind, "scatter": mortar_scatter(u.pos, tile)})
	var events: Array = [{"type": "mortar_fire", "unit": u.id, "target": tile, "kind": kind}]
	events.append_array(_after_action())
	return events


## Medkits heal and also treat wounds.
func use_medkit(u: Unit, target: Unit) -> Array:
	if can_use_medkit(u, target) != "":
		return []
	u.actions -= 1
	u.medkits -= 1
	var amount := mini(CombatRules.MEDKIT_HEAL, target.max_hp - target.hp)
	target.hp += amount
	target.wounded_turns = 0
	var events: Array = [{"type": "heal", "unit": target.id, "amount": amount, "hp": target.hp}]
	events.append_array(_after_action())
	return events


## Applies a command given as data. Returns its events, or [] when it isn't allowed.
func execute(command: Dictionary) -> Array:
	var cmd: String = command.get("cmd", "")
	if cmd == "end_turn":
		return end_turn()
	var u := get_unit(command.get("unit", -1))
	if u == null:
		return []
	var tile: Vector2i = command.get("tile", Vector2i.ZERO)
	var target := get_unit(command.get("target", -1))
	match cmd:
		"move":
			return move(u, tile)
		"pivot":
			return pivot(u, tile)
		"shoot":
			return shoot(u, target) if target != null else []
		"overwatch":
			return overwatch(u)
		"set_up":
			return set_up(u)
		"hunker":
			return hunker(u)
		"reload":
			return reload(u)
		"rally":
			return rally(u)
		"grenade":
			return throw_grenade(u, tile)
		"smoke":
			return throw_smoke(u, tile)
		"mortar":
			return fire_mortar(u, tile, command.get("kind", "he"))
		"medkit":
			return use_medkit(u, target) if target != null else []
	return []


## A fingerprint of the whole battle state. Two games that applied the same commands have the same one.
func checksum() -> String:
	return var_to_str(to_dict()).sha256_text()


func end_turn() -> Array:
	if winner != -1:
		return []
	for u in alive_units(current_team):
		u.actions = 0
		u.wounded_turns = maxi(0, u.wounded_turns - 1)
	var events := []
	turn_index += 1
	current_team = (current_team + 1) % TEAM_COUNT
	if current_team == 0:
		events.append_array(_score_round())
		if winner != -1:
			return events
		round_number += 1
	events.append_array(_begin_turn(current_team))
	return events


# --- Internals ---

## Starts a team's turn: reinforcements, its mortar shells land, smoke clears, suppression wears off.
## Overwatch and hunker last until the start of the unit's own next turn.
func _begin_turn(team: int) -> Array:
	var events: Array = [{"type": "turn", "team": team, "round": round_number}]
	events.append_array(_arrive_reinforcements(team))
	var cleared := map.clear_smoke(turn_index)
	if not cleared.is_empty():
		events.append({"type": "smoke_clear", "tiles": cleared})
	for strike in strikes.duplicate():
		if strike["team"] == team:
			strikes.erase(strike)
			events.append_array(_land_strike(strike))
	for u in alive_units(team):
		u.actions = Unit.ACTIONS_PER_TURN
		u.overwatch = false
		u.hunkered = false
		if u.suppression > 0:
			var recovery := CombatRules.SUPPRESSION_RECOVERY
			if map.has_cover(u.pos):
				recovery += CombatRules.COVER_RECOVERY_BONUS
			if officer_near(u):
				recovery += CombatRules.OFFICER_RECOVERY_BONUS
			events.append_array(_suppress(u, -recovery))
	events.append_array(_check_victory())
	events.append_array(_update_objectives())
	return events


func _arrive_reinforcements(team: int) -> Array:
	var events := []
	for wave in reinforcements.duplicate():
		if wave["team"] != team or wave["round"] != round_number:
			continue
		reinforcements.erase(wave)
		var ids := []
		for u: Unit in wave["units"]:
			u.pos = _free_tile_near(u.pos)
			units.append(u)
			ids.append(u.id)
			if u.vehicle:
				map.set_vehicle(u.pos, true)
		events.append({"type": "reinforcements", "team": team, "units": ids})
	return events


# --- Saving ---

func to_dict() -> Dictionary:
	var waves := []
	for wave in reinforcements:
		waves.append({"round": wave["round"], "team": wave["team"], "units": wave["units"].map(func(u: Unit) -> Dictionary: return u.to_dict())})
	return {
		"map": map.to_dict(),
		"units": units.map(func(u: Unit) -> Dictionary: return u.to_dict()),
		"current_team": current_team, "round_number": round_number, "turn_index": turn_index,
		"winner": winner, "started": started, "rng_seed": rng.seed, "rng_state": rng.state,
		"objectives": objectives.duplicate(true), "victory_points": victory_points.duplicate(),
		"vp_to_win": vp_to_win, "max_rounds": max_rounds,
		"reinforcements": waves, "strikes": strikes.duplicate(true),
	}


static func from_dict(data: Dictionary) -> Battle:
	var loaded_units: Array[Unit] = []
	for u: Dictionary in data["units"]:
		loaded_units.append(Unit.from_dict(u))
	var battle := Battle.new(TacticalMap.from_dict(data["map"]), loaded_units)
	battle.current_team = data["current_team"]
	battle.round_number = data["round_number"]
	battle.turn_index = data["turn_index"]
	battle.winner = data["winner"]
	battle.started = data["started"]
	battle.rng.seed = data["rng_seed"]
	battle.rng.state = data["rng_state"]
	battle.objectives.assign(data["objectives"].duplicate(true))
	battle.victory_points = data["victory_points"].duplicate()
	battle.vp_to_win = data["vp_to_win"]
	battle.max_rounds = data["max_rounds"]
	for wave: Dictionary in data["reinforcements"]:
		var wave_units: Array[Unit] = []
		for u: Dictionary in wave["units"]:
			wave_units.append(Unit.from_dict(u))
		battle.reinforcements.append({"round": wave["round"], "team": wave["team"], "units": wave_units})
	battle.strikes.assign(data["strikes"].duplicate(true))
	return battle


func _free_tile_near(p: Vector2i) -> Vector2i:
	for radius in range(0, 6):
		for y in range(p.y - radius, p.y + radius + 1):
			for x in range(p.x - radius, p.x + radius + 1):
				var t := Vector2i(x, y)
				if map.is_passable(t) and unit_at(t) == null:
					return t
	return p


func _land_strike(strike: Dictionary) -> Array:
	var target: Vector2i = strike["target"]
	var offset := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * float(strike["scatter"])
	var landing := Vector2i((Vector2(target) + offset).round())
	landing = landing.clamp(Vector2i.ZERO, Vector2i(map.width - 1, map.height - 1))
	var shooter := get_unit(strike["unit"])
	var events: Array = [{"type": "strike", "unit": shooter.id, "target": target, "center": landing, "kind": strike["kind"]}]
	if strike["kind"] == "he":
		events.append_array(_explode(shooter, landing, CombatRules.MORTAR_RADIUS, CombatRules.MORTAR_DAMAGE_MIN, CombatRules.MORTAR_DAMAGE_MAX, 0))
	else:
		events.append_array(_make_smoke(shooter, landing, CombatRules.SMOKE_RADIUS + 0.5))
	return events


## Damages everyone in the radius (tanks barely), suppresses everyone near it and destroys cover.
## `spared` (the direct-hit target of a tank shell) takes no blast damage on top of the hit.
func _explode(source: Unit, center: Vector2i, radius: float, damage_min: int, damage_max: int, shred: int, spared: Unit = null) -> Array:
	var destroyed := map.destroy_cover(center, radius)
	var events: Array = [{"type": "explosion", "unit": source.id, "center": center, "radius": radius, "destroyed": destroyed}]
	for victim in alive_units():
		if victim == spared:
			continue
		var distance := Vector2(victim.pos).distance_to(Vector2(center))
		if distance <= radius:
			var damage := rng.randi_range(damage_min, damage_max)
			if victim.vehicle:
				damage = maxi(0, damage - CombatRules.EXPLOSION_VS_ARMOR)
			if damage > 0:
				events.append_array(_damage(victim, damage, shred, source))
		if victim.is_alive() and distance <= radius + 1.0:
			events.append_array(_suppress(victim, CombatRules.EXPLOSION_SUPPRESSION))
	return events


## A random tile next to p, for shells that miss.
func _near(p: Vector2i) -> Vector2i:
	var d: Vector2i = TacticalMap.DIRS8[rng.randi_range(0, 7)]
	return (p + d).clamp(Vector2i.ZERO, Vector2i(map.width - 1, map.height - 1))


## Where a grenade thrown by u at tile actually lands.
func _roll_throw(u: Unit, tile: Vector2i) -> Vector2i:
	var scatter := CombatRules.throw_scatter(u, u.pos, tile)
	if scatter <= 0.0:
		return tile
	var offset := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * scatter
	return _throw_landing(tile, offset, scatter)


## The tile a grenade aimed at tile and thrown `offset` off lands on: never more than scatter tiles from the
## target, and short of any wall or building in the way, which it bounces back off.
func _throw_landing(tile: Vector2i, offset: Vector2, scatter: float) -> Vector2i:
	var spot := Vector2i((Vector2(tile) + offset).round())
	while Vector2(spot).distance_to(Vector2(tile)) > scatter + 0.001:
		spot -= Vector2i(signi(spot.x - tile.x), signi(spot.y - tile.y))
	spot = spot.clamp(Vector2i.ZERO, Vector2i(map.width - 1, map.height - 1))
	return _trace(tile, spot)


## The last tile reached going in a straight line from a toward b, stopping in front of walls, buildings and
## other full cover (smoke doesn't stop anything). The same tile stepping as LineOfSight.has_line.
func _trace(a: Vector2i, b: Vector2i) -> Vector2i:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var nx := absi(b.x - a.x)
	var ny := absi(b.y - a.y)
	var ix := 0
	var iy := 0
	var current := a
	while ix < nx or iy < ny:
		var cmp := (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		var next: Vector2i
		var blocked := false
		if cmp == 0:
			next = current + step
			var side_x := Vector2i(next.x, current.y)
			var side_y := Vector2i(current.x, next.y)
			blocked = not _open_step(current, side_x, next) and not _open_step(current, side_y, next)
			ix += 1
			iy += 1
		elif cmp < 0:
			next = Vector2i(current.x + step.x, current.y)
			blocked = map.edge_blocks_sight(current, next)
			ix += 1
		else:
			next = Vector2i(current.x, current.y + step.y)
			blocked = map.edge_blocks_sight(current, next)
			iy += 1
		if blocked or map.get_object(next) == Cover.FULL:
			return current
		current = next
	return current


func _open_step(a: Vector2i, via: Vector2i, b: Vector2i) -> bool:
	return not map.edge_blocks_sight(a, via) and map.get_object(via) != Cover.FULL and not map.edge_blocks_sight(via, b)


## Where a miss goes. A machine gun burst may hit someone near the line of fire instead (half damage); a rocket
## or shell lands on a stray tile near or behind the target, may hit whoever stands there and bursts.
## Marks the stray tile (and anyone hit) on the shot event.
func _stray(shooter: Unit, target: Unit, shot: Dictionary) -> Array:
	var weapon := shooter.weapon
	var events := []
	if weapon.needs_setup:
		for bystander in mg_bystanders(shooter, shooter.pos, target):
			if rng.randi_range(0, 99) < CombatRules.MG_STRAY_CHANCE:
				shot["stray"] = bystander.pos
				shot["stray_unit"] = bystander.id
				var damage := maxi(1, floori(rng.randi_range(weapon.damage_min, weapon.damage_max) / 2.0))
				events.append_array(_damage(bystander, damage, 0, shooter))
				if bystander.is_alive():
					events.append_array(_suppress(bystander, CombatRules.HIT_SUPPRESSION_BONUS))
				break
		return events
	var tiles := stray_tiles(shooter.pos, target.pos)
	var landing := _near(target.pos) if tiles.is_empty() else _trace(target.pos, tiles[rng.randi_range(0, tiles.size() - 1)])
	shot["stray"] = landing
	var victim := unit_at(landing)
	if victim == target or (victim != null and rng.randi_range(0, 99) >= CombatRules.STRAY_HIT_CHANCE):
		victim = null
	var radius := weapon.blast_radius if weapon.blast_radius > 0.0 else CombatRules.ROCKET_BLAST_RADIUS
	events.append_array(_explode(shooter, landing, radius, CombatRules.SPLASH_DAMAGE_MIN, CombatRules.SPLASH_DAMAGE_MAX, 0, victim))
	if victim != null and victim.is_alive():
		# A direct hit (after the blast, so a knocked-out tank's wreck survives it).
		shot["stray_unit"] = victim.id
		var damage := rng.randi_range(weapon.damage_min, weapon.damage_max)
		if victim.vehicle:
			damage = maxi(0, damage - CombatRules.VEHICLE_ARMOR[CombatRules.armor_side(victim, shooter.pos)])
		events.append_array(_damage(victim, damage, 0, shooter))
	return events


## A tank moving from a to b flattens what's in its way: crates, sandbags, trees, fences, walls and hedges.
func _drive(a: Vector2i, b: Vector2i) -> void:
	map.set_vehicle(a, false)
	map.set_vehicle(b, true)
	if map.get_object(b) != Cover.NONE:
		map.set_object(b, Cover.NONE)
		map.set_terrain(b, TacticalMap.Terrain.RUBBLE)
	if (a.x == b.x or a.y == b.y) and map.get_edge(a, b) != Cover.NONE:
		map.set_edge(a, b, Cover.NONE)


func _make_smoke(source: Unit, center: Vector2i, radius: float) -> Array:
	var tiles := map.tiles_in_radius(center, radius)
	for p in tiles:
		map.add_smoke(p, turn_index + CombatRules.SMOKE_TURNS)
	return [{"type": "smoke", "unit": source.id, "center": center, "tiles": tiles}]


func _status(u: Unit, text: String) -> Array:
	var events: Array = [{"type": "status", "unit": u.id, "text": text}]
	events.append_array(_after_action())
	return events


func _overwatchers_seeing(u: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	for e in enemies_of(u):
		if e.overwatch and e.ammo > 0 and not e.is_pinned() and can_see(e, u):
			result.append(e)
	return result


func _fire(shooter: Unit, target: Unit, reaction: bool) -> Array:
	var odds := shot_odds(shooter, target, reaction)
	shooter.ammo -= 1
	if reaction:
		shooter.overwatch = false
	var roll := rng.randi_range(0, 99)
	var result := "miss"
	if roll < odds["hit"]:
		result = "crit" if rng.randi_range(0, 99) < odds["crit"] else "hit"
	elif roll < odds["hit"] + odds["graze"]:
		result = "graze"
	var events: Array = [{
		"type": "shot", "shooter": shooter.id, "target": target.id,
		"result": result, "chance": odds["hit"], "reaction": reaction,
	}]
	var weapon := shooter.weapon
	if result != "miss":
		var damage := rng.randi_range(weapon.damage_min, weapon.damage_max)
		if result == "crit":
			damage += weapon.crit_damage
		elif result == "graze":
			damage = maxi(1, floori(damage / 2.0))
		if target.vehicle and not weapon.anti_tank:
			events.append({"type": "status", "unit": target.id, "text": "Bounced off the armour"})
		else:
			if target.vehicle:
				var side := CombatRules.armor_side(target, shooter.pos)
				events[0]["armor"] = side
				damage = maxi(0, damage - CombatRules.VEHICLE_ARMOR[side])
			events.append_array(_damage(target, damage, 0, shooter))
	if result == "miss" and CombatRules.misses_stray(weapon):
		events.append_array(_stray(shooter, target, events[0]))
	elif weapon.blast_radius > 0.0 and result != "miss":
		# High explosive bursts on the target.
		events.append_array(_explode(shooter, target.pos, weapon.blast_radius, CombatRules.SPLASH_DAMAGE_MIN, CombatRules.SPLASH_DAMAGE_MAX, 0, target))
	if target.is_alive():
		var suppression := shooter.weapon.suppression + (CombatRules.HIT_SUPPRESSION_BONUS if result != "miss" else 0)
		events.append_array(_suppress(target, suppression))
	if shooter.weapon.needs_setup:
		for ally in alive_units(target.team):
			if ally != target and Vector2(ally.pos).distance_to(Vector2(target.pos)) <= CombatRules.MG_AREA_RADIUS:
				events.append_array(_suppress(ally, int(shooter.weapon.suppression / 2.0)))
	return events


## Shred strips armor before the damage lands; remaining armor absorbs damage point for point.
## Survivors are wounded, which slows them for their next turns. A destroyed tank leaves a burning wreck.
func _damage(target: Unit, amount: int, shred: int, attacker: Unit = null) -> Array:
	target.armor = maxi(0, target.armor - shred)
	var absorbed := mini(target.armor, amount)
	var dealt := amount - absorbed
	target.hp = maxi(0, target.hp - dealt)
	if dealt > 0 and target.is_alive():
		target.wounded_turns = Unit.WOUND_TURNS
	var events: Array = [{"type": "damage", "unit": target.id, "amount": dealt, "absorbed": absorbed, "hp": target.hp, "wounded": target.is_wounded()}]
	if not target.is_alive():
		target.overwatch = false
		target.hunkered = false
		target.actions = 0
		if attacker != null and attacker.team != target.team:
			attacker.kills += 1
		if target.vehicle:
			map.set_vehicle(target.pos, false)
			map.set_object(target.pos, Cover.FULL, "wreck")
		events.append({"type": "death", "unit": target.id, "vehicle": target.vehicle})
		events.append_array(_shake_morale(target))
	return events


## Changes a unit's suppression; being pinned cancels overwatch. Emits the new level and state.
func _suppress(u: Unit, amount: int) -> Array:
	if u.vehicle:
		return []
	var was := u.suppression
	u.suppression = clampi(u.suppression + amount, 0, 100)
	if u.suppression == was:
		return []
	if u.is_pinned():
		u.overwatch = false
	var state := "pinned" if u.is_pinned() else ("suppressed" if u.is_suppressed() else "steady")
	return [{"type": "suppression", "unit": u.id, "value": u.suppression, "state": state, "previous": was}]


## A death can panic nearby allies; losing the officer shakes everyone.
func _shake_morale(dead: Unit) -> Array:
	var events := []
	for ally in alive_units(dead.team):
		if dead.role == "Officer":
			events.append_array(_suppress(ally, CombatRules.OFFICER_DEATH_SUPPRESSION))
		if ally.vehicle or Vector2(ally.pos).distance_to(Vector2(dead.pos)) > CombatRules.PANIC_RADIUS or ally.is_pinned():
			continue
		var chance := CombatRules.PANIC_CHANCE
		if officer_near(ally):
			chance -= CombatRules.OFFICER_PANIC_REDUCTION
		if ally.is_wounded():
			chance += CombatRules.PANIC_WOUNDED_BONUS
		if rng.randi_range(0, 99) < chance:
			events.append({"type": "status", "unit": ally.id, "text": "Panicked!"})
			events.append_array(_suppress(ally, 100))
	return events


## Objectives change hands when only one side has soldiers inside.
func _update_objectives() -> Array:
	var events := []
	for i in objectives.size():
		var objective := objectives[i]
		var present := [0, 0]
		for u in alive_units():
			if (Vector2(u.pos) + Vector2(0.5, 0.5)).distance_to(objective["center"]) <= objective["radius"]:
				present[u.team] += 1
		var owner: int = objective["owner"]
		if present[0] > 0 and present[1] == 0:
			owner = 0
		elif present[1] > 0 and present[0] == 0:
			owner = 1
		if owner != objective["owner"]:
			objective["owner"] = owner
			events.append({"type": "objective", "index": i, "owner": owner})
	return events


## At the end of every round, each held objective scores a point for its owner.
func _score_round() -> Array:
	if objectives.is_empty():
		return []
	for objective in objectives:
		if objective["owner"] != -1:
			victory_points[objective["owner"]] += 1
	var events: Array = [{"type": "score", "points": victory_points.duplicate()}]
	if victory_points[0] >= vp_to_win or victory_points[1] >= vp_to_win or round_number >= max_rounds:
		if victory_points[0] == victory_points[1]:
			winner = DRAW
		else:
			winner = 0 if victory_points[0] > victory_points[1] else 1
		events.append({"type": "game_over", "winner": winner, "reason": "points"})
	return events


func _check_victory() -> Array:
	if winner != -1:
		return []
	for team in TEAM_COUNT:
		if alive_units(team).is_empty():
			winner = (team + 1) % TEAM_COUNT
			return [{"type": "game_over", "winner": winner, "reason": "eliminated"}]
	return []


## Checks for victory and objectives, then ends the turn automatically once nobody on the team can act.
func _after_action() -> Array:
	var events := _check_victory()
	if winner != -1:
		return events
	events.append_array(_update_objectives())
	for u in alive_units(current_team):
		if u.actions > 0:
			return events
	events.append_array(end_turn())
	return events
