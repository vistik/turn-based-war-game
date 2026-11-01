class_name WarCampaign
extends RefCounted
## The two-player campaign: a series of 3-5 maps, each worth a different number of campaign points.
## Each side has one pool of supply for the whole campaign. Before every map both sides secretly decide how
## much of it to commit (between a minimum and a maximum), buy units with it, and choose a deployment:
## where to stand (balanced, left or right flank) and how (offensive: deployed further forward; defensive:
## further back, behind sandbags, crouched). Supply spent on a map is gone; whatever isn't spent stays for
## the maps to come. Winning a map scores its points (a draw splits them), and the most points wins.
##
## Unit prices, AI shopping lists and map names come from the theatre (Theatre.cost, the faction's
## "ai_wishes", "ai_heavy" and "fill_roles", Theatre.places).
##
## Orders are {"roster": Array of role names, "flank": "balanced"|"left"|"right",
## "posture": "offensive"|"defensive"}. Left and right are seen from each side's own edge, facing the enemy.

const SUPPLY := 100
## Supply a side must commit to each map, and may commit at most.
const MIN_SPEND := 12
const MAX_SPEND := 45
const MAX_UNITS := 14
const MAP_COUNTS := [3, 4, 5]
const FLANKS := ["balanced", "left", "right"]
const POSTURES := ["offensive", "defensive"]
const SIZES := [36, 40, 44, 48]

## Each: {"name", "seed", "size", "points", "orders": [Allied, German] (or {} until given), "result": {} or
## {"winner": team or Battle.DRAW, "vp": [a, b], "spent": [a, b]}}.
var theatre_id := Theatres.DEFAULT
var maps: Array[Dictionary] = []
var supply := [SUPPLY, SUPPLY]
var scores := [0, 0]
var current := 0
## Per side: whether the AI plays it.
var ai_sides := [false, true]
var _rng := RandomNumberGenerator.new()


static func create(map_count: int, seed: int, p_ai_sides := [false, true], p_theatre := Theatres.DEFAULT) -> WarCampaign:
	var war := WarCampaign.new()
	war.theatre_id = p_theatre
	war._rng.seed = seed
	war.ai_sides = p_ai_sides.duplicate()
	# Every map is worth a different number of points, from 1 up to 5.
	var values := [1, 2, 3, 4, 5]
	_shuffle(values, war._rng)
	var places := war.theatre().places().duplicate()
	_shuffle(places, war._rng)
	for i in map_count:
		war.maps.append({
			"name": places[i], "seed": war._rng.randi_range(1, 999999), "size": SIZES[war._rng.randi_range(0, SIZES.size() - 1)],
			"points": values[i], "orders": [{}, {}], "result": {},
		})
	return war


func theatre() -> Theatre:
	return Theatres.get_theatre(theatre_id)


func is_over() -> bool:
	return current >= maps.size()


func current_map() -> Dictionary:
	return maps[mini(current, maps.size() - 1)]


## The side ahead at the end, Battle.DRAW if level, or -1 while the campaign is running.
## Level on campaign points goes to the side with more victory points over all its battles.
func winner() -> int:
	if not is_over():
		return -1
	if scores[0] != scores[1]:
		return 0 if scores[0] > scores[1] else 1
	var vp := [0, 0]
	for m in maps:
		for side in 2:
			vp[side] += m["result"]["vp"][side]
	if vp[0] != vp[1]:
		return 0 if vp[0] > vp[1] else 1
	return Battle.DRAW


## [least, most] supply a side may commit to the current map. Enough must be left for the minimum on
## every map still to come; on the last map the minimum is whatever is left, if that's less.
func spend_limits(side: int) -> Array[int]:
	var left_after := maps.size() - current - 1
	var most := mini(MAX_SPEND, supply[side] - MIN_SPEND * left_after)
	var least := mini(MIN_SPEND, supply[side])
	return [least, maxi(least, most)]


## Most units the side may field on one map.
func max_units(side: int) -> int:
	return theatre().faction(side).get("max_units", MAX_UNITS)


## What a side pays for a roster.
func cost_of(side: int, roster: Array) -> int:
	return theatre().cost_of(side, roster)


## Why these orders can't be given for the current map ("" if they can).
func check_orders(side: int, orders: Dictionary) -> String:
	if is_over():
		return "The campaign is over"
	var roster: Array = orders.get("roster", [])
	if roster.is_empty():
		return "Buy at least one unit"
	if roster.size() > max_units(side):
		return "At most %d units" % max_units(side)
	for role in roster:
		if not theatre().has_role(side, role):
			return "Unknown unit: %s" % role
	var cost := cost_of(side, roster)
	var limits := spend_limits(side)
	if cost < limits[0]:
		return "Commit at least %d supply to this map" % limits[0]
	if cost > limits[1]:
		return "At most %d supply on this map" % limits[1]
	if not FLANKS.has(orders.get("flank")) or not POSTURES.has(orders.get("posture")):
		return "Choose a deployment"
	return ""


func set_orders(side: int, orders: Dictionary) -> String:
	var err := check_orders(side, orders)
	if err == "":
		maps[current]["orders"][side] = orders.duplicate(true)
	return err


func has_orders(side: int) -> bool:
	return not current_map()["orders"][side].is_empty()


func ready_to_fight() -> bool:
	return not is_over() and has_orders(0) and has_orders(1)


## Orders for a side the AI plays. It never looks at the other side's orders. It commits supply in
## proportion to what this map is worth out of everything left, with some noise to stay hard to read.
func ai_orders(side: int) -> Dictionary:
	var left_points := 0
	for i in range(current, maps.size()):
		left_points += maps[i]["points"]
	var share := float(current_map()["points"]) / maxi(1, left_points)
	var limits := spend_limits(side)
	var budget := clampi(roundi(supply[side] * share * _rng.randf_range(0.8, 1.25)), limits[0], limits[1])
	var roster: Array = []
	var cost := 0
	# An officer and a core of riflemen first, then support weapons, then more riflemen.
	var faction := theatre().faction(side)
	var wishes: Array = faction["ai_wishes"].duplicate()
	if budget >= 36 and _rng.randf() < 0.6 and faction.get("ai_heavy", "") != "":
		wishes.insert(1, faction["ai_heavy"])
	for role: String in wishes:
		if roster.size() >= max_units(side):
			break
		if cost + theatre().cost(side, role) <= budget:
			roster.append(role)
			cost += theatre().cost(side, role)
	# Top up to the minimum with whatever fits, handing units back until something does.
	while cost < limits[0]:
		var extra := _fill(side, limits[0] - cost, limits[1] - cost)
		if not extra.is_empty() or roster.is_empty():
			roster.append_array(extra)
			break
		cost -= theatre().cost(side, roster.pop_back())
	return {"roster": roster, "flank": FLANKS[_rng.randi_range(0, 2)], "posture": POSTURES[_rng.randi_range(0, 1)]}


## Cheap units costing between `least` and `most` supply in total, or [] if no mix does.
func _fill(side: int, least: int, most: int) -> Array:
	# Fewest units for each total, built up from the cheapest roles.
	var best := {0: []}
	for amount in range(1, most + 1):
		for role: String in theatre().faction(side)["fill_roles"]:
			var rest: int = amount - theatre().cost(side, role)
			if best.has(rest) and (not best.has(amount) or best[rest].size() + 1 < best[amount].size()):
				best[amount] = best[rest] + [role]
	for amount in range(least, most + 1):
		if best.has(amount):
			return best[amount]
	return []


## The battle for the current map, both sides deployed as ordered.
func build_battle() -> Battle:
	var m := current_map()
	var layout := theatre().generate_map(m["seed"], Vector2i(m["size"], m["size"]))
	var deployments: Array = m["orders"]
	var rosters := deploy(layout, [m["orders"][0]["roster"], m["orders"][1]["roster"]], deployments)
	var size: int = m["size"]
	var options := {"theatre": theatre_id, "vp_to_win": 8 + size / 8, "max_rounds": 12 + size / 8}
	options.merge(theatre().battle_options())
	var battle := BattleFactory.create(layout, rosters, m["seed"], options)
	brace(battle, deployments)
	return battle


## Places both rosters as their deployments say ({"flank", "posture"}; {} keeps a side on the map's usual
## spawns) and builds sandbags in front of defensive deployments. Returns the rosters with positions, for
## BattleFactory.create on the same layout. Also used by skirmishes.
static func deploy(layout: Dictionary, rosters: Array, deployments: Array) -> Array:
	if deployments.all(func(d: Dictionary) -> bool: return d.is_empty()):
		return rosters
	var map: TacticalMap = layout["map"]
	var reachable := Pathfinder.search(map, layout["spawns"][0], 100000.0)
	var taken := {}
	var placed := [[], []]
	var defensive_tiles := [[], []]
	for side in 2:
		var deployment: Dictionary = deployments[side]
		if deployment.is_empty():
			placed[side] = rosters[side]
			continue
		var orders := {"roster": rosters[side], "flank": deployment["flank"], "posture": deployment["posture"]}
		var tiles := deployment_tiles(map, side, orders, reachable, taken)
		for i in rosters[side].size():
			var entry: Variant = rosters[side][i]
			var spec: Dictionary = (entry as Dictionary).duplicate() if entry is Dictionary else {"role": entry}
			spec["pos"] = tiles[i]
			placed[side].append(spec)
		if deployment["posture"] == "defensive":
			defensive_tiles[side] = tiles
	# Defensive deployments start behind sandbags, facing the enemy.
	for side in 2:
		var forward := Vector2i(1, 0) if side == 0 else Vector2i(-1, 0)
		for tile: Vector2i in defensive_tiles[side]:
			var front: Vector2i = tile + forward
			if map.in_bounds(front) and map.is_passable(front) and not taken.has(front) and map.get_edge(tile, front) == Cover.NONE:
				map.set_object(front, Cover.HALF, "sandbags")
	return placed


## Defensive deployments start crouched (tanks excepted).
static func brace(battle: Battle, deployments: Array) -> void:
	for u in battle.units:
		if not u.vehicle and deployments[u.team].get("posture", "") == "defensive":
			u.stance = Unit.Stance.CROUCH


## Start tiles for a side's units: a band along its own edge, shifted to the chosen flank, nearer the enemy
## when offensive. Only tiles connected to the rest of the map are used.
static func deployment_tiles(map: TacticalMap, side: int, orders: Dictionary, reachable: Dictionary, taken: Dictionary) -> Array[Vector2i]:
	var count: int = orders["roster"].size()
	var h := map.height
	var depth: Array[int] = [1, 5]
	if orders["posture"] == "offensive":
		depth = [5, 10]
	var band: Array[int] = [roundi(h * 0.12), roundi(h * 0.88)]
	# Left is north for the Allies, who face east, and south for Germany, who face west.
	var flank: String = orders["flank"]
	if flank != "balanced":
		var north := (flank == "left") == (side == 0)
		band = [roundi(h * 0.08), roundi(h * 0.45)]
		if not north:
			band = [roundi(h * 0.55), roundi(h * 0.92)]
	var result: Array[Vector2i] = []
	for i in count:
		var y: int = band[0] + roundi((i + 0.5) * (band[1] - band[0]) / count)
		var x: int = depth[0] + (i % 2) * 2 + (depth[1] - depth[0]) / 3
		var want := Vector2i(x, y)
		var tile := _free_near(map, want, side, depth, reachable, taken)
		taken[tile] = true
		result.append(tile)
	return result


static func _free_near(map: TacticalMap, want: Vector2i, side: int, depth: Array, reachable: Dictionary, taken: Dictionary) -> Vector2i:
	var mirror := func(p: Vector2i) -> Vector2i: return p if side == 0 else Vector2i(map.width - 1 - p.x, p.y)
	for radius in range(0, maxi(map.width, map.height)):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var p: Vector2i = want + Vector2i(dx, dy)
				# Keep to the deployment zone while there is room, then take anything on our half.
				if radius < 6 and (p.x < depth[0] or p.x > depth[1]):
					continue
				if p.x < 0 or p.x >= map.width / 2:
					continue
				var tile: Vector2i = mirror.call(p)
				if map.in_bounds(tile) and map.is_passable(tile) and reachable.has(tile) and not taken.has(tile):
					return tile
	return mirror.call(want)


## Applies a finished battle: the winner scores the map's points (a draw splits them, rounding down),
## both sides pay what they committed, and the campaign moves on. Returns the map's result.
func complete_map(battle: Battle) -> Dictionary:
	var m := current_map()
	var spent := [cost_of(0, m["orders"][0]["roster"]), cost_of(1, m["orders"][1]["roster"])]
	for side in 2:
		supply[side] -= spent[side]
	var won: int = battle.winner
	if won == 0 or won == 1:
		scores[won] += m["points"]
	else:
		won = Battle.DRAW
		for side in 2:
			scores[side] += floori(m["points"] / 2.0)
	m["result"] = {"winner": won, "vp": battle.victory_points.duplicate(), "spent": spent}
	current += 1
	return m["result"]


func to_dict() -> Dictionary:
	return {"theatre": theatre_id, "maps": maps.duplicate(true), "supply": supply.duplicate(), "scores": scores.duplicate(), "current": current,
			"ai_sides": ai_sides.duplicate(), "rng_seed": _rng.seed, "rng_state": _rng.state}


static func from_dict(data: Dictionary) -> WarCampaign:
	var war := WarCampaign.new()
	war.theatre_id = data.get("theatre", Theatres.DEFAULT)
	war.maps.assign(data["maps"].duplicate(true))
	war.supply = data["supply"].duplicate()
	war.scores = data["scores"].duplicate()
	war.current = data["current"]
	war.ai_sides = data["ai_sides"].duplicate()
	war._rng.seed = data["rng_seed"]
	war._rng.state = data["rng_state"]
	return war


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap
