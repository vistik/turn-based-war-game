class_name Battle
extends RefCounted
## The combat engine. Owns all battle state and applies the rules.
## Commands validate, change state and return event dictionaries for the view to play back.
## Event types: move, shot, damage, death, explosion, status, heal, turn, game_over.

const TEAM_COUNT := 2

var map: TacticalMap
var units: Array[Unit] = []
var current_team := 0
var round_number := 1
var winner := -1
var rng := RandomNumberGenerator.new()


func _init(p_map: TacticalMap, p_units: Array[Unit], p_seed := 0) -> void:
	map = p_map
	units = p_units
	if p_seed != 0:
		rng.seed = p_seed


func start() -> Array:
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
	if u == null or not u.is_alive() or u.actions <= 0:
		return {}
	var blocked := {}
	for other in alive_units():
		if other != u:
			blocked[other.pos] = true
	return Pathfinder.search(map, u.pos, u.mobility * mini(u.actions, Unit.ACTIONS_PER_TURN), blocked)


## Actions used by a move of the given path cost: one for a normal move, two for a dash.
func actions_for_cost(u: Unit, cost: float) -> int:
	return 1 if cost <= u.mobility + 0.001 else 2


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
		var r := ceili(u.sight)
		for y in range(u.pos.y - r, u.pos.y + r + 1):
			for x in range(u.pos.x - r, u.pos.x + r + 1):
				var p := Vector2i(x, y)
				if map.in_bounds(p) and not result.has(p) and LineOfSight.can_see(map, u.pos, p, u.sight, false):
					result[p] = true
	return result


func shot_odds(shooter: Unit, target: Unit, reaction := false) -> Dictionary:
	return CombatRules.shot_odds(map, shooter, target, reaction)


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
	if dest == u.pos or not reachable(u).has(dest):
		return "Can't reach that tile"
	return ""


func can_shoot(u: Unit, target: Unit) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if target == null or not target.is_alive() or target.team == u.team:
		return "Not a valid target"
	if u.ammo <= 0:
		return "Out of ammo, reload first"
	if not can_see(u, target):
		return "No line of sight"
	return ""


func can_overwatch(u: Unit) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if u.ammo <= 0:
		return "Out of ammo, reload first"
	return ""


func can_hunker(u: Unit) -> String:
	var err := can_act(u)
	if err != "":
		return err
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


func can_throw_grenade(u: Unit, tile: Vector2i) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if u.grenades <= 0:
		return "No grenades left"
	if not map.in_bounds(tile):
		return "Out of bounds"
	if not LineOfSight.can_see(map, u.pos, tile, CombatRules.GRENADE_RANGE, false):
		return "Out of range or line of sight"
	return ""


func can_use_medkit(u: Unit, target: Unit) -> String:
	var err := can_act(u)
	if err != "":
		return err
	if u.medkits <= 0:
		return "No medkits left"
	if target == null or not target.is_alive() or target.team != u.team:
		return "Can only heal allies"
	if absi(target.pos.x - u.pos.x) > 1 or absi(target.pos.y - u.pos.y) > 1:
		return "Must be adjacent"
	if target.hp >= target.max_hp:
		return "Already at full health"
	return ""


# --- Commands: return [] when not allowed ---

func move(u: Unit, dest: Vector2i) -> Array:
	if can_move(u, dest) != "":
		return []
	var reach := reachable(u)
	u.actions -= actions_for_cost(u, reach[dest]["cost"])
	var events := []
	var segment: Array[Vector2i] = [u.pos]
	for step in Pathfinder.path_to(reach, dest):
		u.pos = step
		segment.append(step)
		for watcher in _overwatchers_seeing(u):
			if segment.size() > 1:
				events.append({"type": "move", "unit": u.id, "path": segment})
				segment = [step]
			events.append_array(_fire(watcher, u, true))
			if not u.is_alive():
				break
		if not u.is_alive():
			break
	if segment.size() > 1:
		events.append({"type": "move", "unit": u.id, "path": segment})
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
	var events: Array = [{"type": "status", "unit": u.id, "text": "Overwatch"}]
	events.append_array(_after_action())
	return events


func hunker(u: Unit) -> Array:
	if can_hunker(u) != "":
		return []
	u.actions = 0
	u.hunkered = true
	var events: Array = [{"type": "status", "unit": u.id, "text": "Hunkered down"}]
	events.append_array(_after_action())
	return events


func reload(u: Unit) -> Array:
	if can_reload(u) != "":
		return []
	u.actions -= 1
	u.ammo = u.weapon.clip_size
	var events: Array = [{"type": "status", "unit": u.id, "text": "Reloaded"}]
	events.append_array(_after_action())
	return events


## Grenades ignore cover, destroy it, shred armor and hit everyone in the blast, friends included.
func throw_grenade(u: Unit, tile: Vector2i) -> Array:
	if can_throw_grenade(u, tile) != "":
		return []
	u.actions = 0
	u.grenades -= 1
	var area := map.tiles_in_radius(tile, CombatRules.GRENADE_RADIUS)
	var destroyed := map.destroy_cover(tile, CombatRules.GRENADE_RADIUS)
	var events: Array = [{
		"type": "explosion", "unit": u.id, "center": tile,
		"radius": CombatRules.GRENADE_RADIUS, "destroyed": destroyed,
	}]
	for victim in alive_units():
		if victim.pos in area:
			var damage := rng.randi_range(CombatRules.GRENADE_DAMAGE_MIN, CombatRules.GRENADE_DAMAGE_MAX)
			events.append_array(_damage(victim, damage, CombatRules.GRENADE_SHRED))
	events.append_array(_after_action())
	return events


func use_medkit(u: Unit, target: Unit) -> Array:
	if can_use_medkit(u, target) != "":
		return []
	u.actions -= 1
	u.medkits -= 1
	var amount := mini(CombatRules.MEDKIT_HEAL, target.max_hp - target.hp)
	target.hp += amount
	var events: Array = [{"type": "heal", "unit": target.id, "amount": amount, "hp": target.hp}]
	events.append_array(_after_action())
	return events


func end_turn() -> Array:
	if winner != -1:
		return []
	for u in alive_units(current_team):
		u.actions = 0
	current_team = (current_team + 1) % TEAM_COUNT
	if current_team == 0:
		round_number += 1
	return _begin_turn(current_team)


# --- Internals ---

## Overwatch and hunker last until the start of the unit's own next turn.
func _begin_turn(team: int) -> Array:
	for u in alive_units(team):
		u.actions = Unit.ACTIONS_PER_TURN
		u.overwatch = false
		u.hunkered = false
	return [{"type": "turn", "team": team, "round": round_number}]


func _overwatchers_seeing(u: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	for e in enemies_of(u):
		if e.overwatch and e.ammo > 0 and can_see(e, u):
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
	if result != "miss":
		var damage := rng.randi_range(shooter.weapon.damage_min, shooter.weapon.damage_max)
		if result == "crit":
			damage += shooter.weapon.crit_damage
		elif result == "graze":
			damage = maxi(1, floori(damage / 2.0))
		events.append_array(_damage(target, damage, 0))
	return events


## Shred strips armor before the damage lands; remaining armor absorbs damage point for point.
func _damage(target: Unit, amount: int, shred: int) -> Array:
	target.armor = maxi(0, target.armor - shred)
	var absorbed := mini(target.armor, amount)
	target.hp = maxi(0, target.hp - (amount - absorbed))
	var events: Array = [{"type": "damage", "unit": target.id, "amount": amount - absorbed, "absorbed": absorbed, "hp": target.hp}]
	if not target.is_alive():
		target.overwatch = false
		target.hunkered = false
		target.actions = 0
		events.append({"type": "death", "unit": target.id})
	return events


## Checks for victory, then ends the turn automatically once nobody on the team can act.
func _after_action() -> Array:
	for team in TEAM_COUNT:
		if alive_units(team).is_empty():
			winner = (team + 1) % TEAM_COUNT
			return [{"type": "game_over", "winner": winner}]
	for u in alive_units(current_team):
		if u.actions > 0:
			return []
	return end_turn()
