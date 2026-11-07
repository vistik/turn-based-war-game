class_name WarCampaign
extends RefCounted
## The two-player campaign, played online: a series of 1-5 maps, each worth a different number of campaign
## points. Each side has one pool of supply for the whole campaign, topped up by an income after every map.
## Before every map both sides secretly decide how much of it to commit (between a minimum and a maximum),
## buy units with it, and choose a deployment:
## where to stand (balanced, left or right flank) and how (offensive: deployed further forward; defensive:
## further back, behind sandbags). Supply spent on a map is gone; whatever isn't spent stays for
## the maps to come. Winning a map scores its points (a draw splits them), and the most points wins.
##
## Unit prices, AI shopping lists and map names come from the theatre (Theatre.cost, the faction's
## "ai_wishes", "ai_heavy" and "fill_roles", Theatre.places).
##
## Orders are {"roster": Array of role names, "flank": "balanced"|"left"|"right",
## "posture": "offensive"|"defensive"}. Left and right are seen from each side's own edge, facing the enemy.
##
## The host chooses the settings (DEFAULT_SETTINGS): starting supply, income per map, the least and most a side
## may commit to one map, the most units on one map (0: the faction's own limit), the map size (0: a mix of
## SIZES) and the map style ("": each map's seed picks).

const SUPPLY := 100
## Supply a side must commit to each map, and may commit at most.
const MIN_SPEND := 12
const MAX_SPEND := 45
const MAX_UNITS := 14
const MAP_COUNTS := [1, 2, 3, 4, 5]
const DEFAULT_SETTINGS := {"supply": SUPPLY, "income": 0, "min_spend": MIN_SPEND, "max_spend": MAX_SPEND, "max_units": 0, "size": 0, "style": ""}
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
var settings := DEFAULT_SETTINGS.duplicate()
var _rng := RandomNumberGenerator.new()


## `p_settings`: any of DEFAULT_SETTINGS' keys; the rest keep their defaults.
static func create(map_count: int, seed: int, p_ai_sides := [false, true], p_theatre := Theatres.DEFAULT, p_settings := {}) -> WarCampaign:
	var war := WarCampaign.new()
	war.theatre_id = p_theatre
	war._rng.seed = seed
	war.ai_sides = p_ai_sides.duplicate()
	war.settings.merge(p_settings, true)
	war.supply = [int(war.settings["supply"]), int(war.settings["supply"])]
	# Every map is worth a different number of points, from 1 up to 5.
	var values := [1, 2, 3, 4, 5]
	_shuffle(values, war._rng)
	var places := war.theatre().places().duplicate()
	_shuffle(places, war._rng)
	for i in map_count:
		var map_seed := war._rng.randi_range(1, 999999)
		var size: int = SIZES[war._rng.randi_range(0, SIZES.size() - 1)]
		if int(war.settings["size"]) > 0:
			size = int(war.settings["size"])
		war.maps.append({"name": places[i], "seed": map_seed, "size": size, "points": values[i], "orders": [{}, {}], "result": {}})
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


## [least, most] supply a side may commit to the current map. Enough must be left (counting the income still
## to come) for the minimum on every map after this one; on the last map the minimum is whatever is left, if
## that's less.
func spend_limits(side: int) -> Array[int]:
	var left_after := maps.size() - current - 1
	var min_spend := int(settings["min_spend"])
	var reserve := maxi(0, (min_spend - income()) * left_after)
	var most := mini(int(settings["max_spend"]), supply[side] - reserve)
	var least := mini(min_spend, supply[side])
	return [least, maxi(least, most)]


## Supply each side gains after every map but the last.
func income() -> int:
	return int(settings["income"])


## Most units the side may field on one map.
func max_units(side: int) -> int:
	if int(settings["max_units"]) > 0:
		return int(settings["max_units"])
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
	if budget >= 36 and _rng.randf() < 0.6 and faction.get("ai_heavy", "") != "" and theatre().role_ids(side).has(faction["ai_heavy"]):
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
	var layout := theatre().generate_map(m["seed"], Vector2i(m["size"], m["size"]), settings["style"])
	# A small map can lack room for fair objectives; the next seeds (the same in both players' games) will do.
	var next_seed: int = m["seed"]
	while not layout.has("map") and next_seed < m["seed"] + 20:
		next_seed += 1
		layout = theatre().generate_map(next_seed, Vector2i(m["size"], m["size"]), settings["style"])
	var deployments: Array = m["orders"]
	var rosters := deploy(layout, [m["orders"][0]["roster"], m["orders"][1]["roster"]], deployments)
	var size: int = m["size"]
	var options := {"theatre": theatre_id, "vp_to_win": 8 + size / 8, "max_rounds": 12 + size / 8}
	options.merge(theatre().battle_options())
	return BattleFactory.create(layout, rosters, m["seed"], options)


## Places both rosters as their deployments say ({"flank", "posture"}; {} keeps a side on the map's usual
## spawns) and builds sandbags in front of defensive deployments. Returns the rosters with positions, for
## BattleFactory.create on the same layout. Also used by skirmishes.
static func deploy(layout: Dictionary, rosters: Array, deployments: Array) -> Array:
	if deployments.all(func(d: Dictionary) -> bool: return d.is_empty()):
		return rosters
	var map: TacticalMap = layout["map"]
	var reachable := Pathfinder.search(map, layout["spawns"][0][0], 100000.0)
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


## Start tiles for a side's units: a band along its own edge ("wide": nearly corner to corner), shifted to the
## chosen flank ("contact": next to the middle of the map, close to the enemy), nearer the enemy when offensive ("normal" and "defensive" stay 1-5 tiles in). Only tiles connected to the rest of the map are used.
static func deployment_tiles(map: TacticalMap, side: int, orders: Dictionary, reachable: Dictionary, taken: Dictionary) -> Array[Vector2i]:
	var count: int = orders["roster"].size()
	var h := map.height
	var depth: Array[int] = [1, 5]
	if orders["posture"] == "offensive":
		depth = [5, 10]
	var band: Array[int] = [roundi(h * 0.12), roundi(h * 0.88)]
	# Left is north for the Allies, who face east, and south for Germany, who face west.
	var flank: String = orders["flank"]
	if flank == "contact":
		# Already face to face: a few tiles back from the middle of the map, each on its own half.
		var mid := map.width / 2
		depth = [mid - 6, mid - 2]
		band = [roundi(h * 0.25), roundi(h * 0.75)]
	elif flank == "wide":
		# Spread out over the whole edge, corner to corner.
		band = [roundi(h * 0.04), roundi(h * 0.96)]
	elif flank != "balanced":
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
	# Bands are worked out from the west edge; Germany's run the same distance in from the east edge.
	var from_edge := func(p: Vector2i) -> Vector2i: return p if side == 0 else Vector2i(map.width - 1 - p.x, p.y)
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
				var tile: Vector2i = from_edge.call(p)
				if map.in_bounds(tile) and map.is_passable(tile) and reachable.has(tile) and not taken.has(tile):
					return tile
	return from_edge.call(want)


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
	if not is_over():
		for side in 2:
			supply[side] += income()
	return m["result"]


func to_dict() -> Dictionary:
	return {"theatre": theatre_id, "maps": maps.duplicate(true), "supply": supply.duplicate(), "scores": scores.duplicate(), "current": current,
			"ai_sides": ai_sides.duplicate(), "settings": settings.duplicate(), "rng_seed": _rng.seed, "rng_state": _rng.state}


static func from_dict(data: Dictionary) -> WarCampaign:
	var war := WarCampaign.new()
	war.theatre_id = data.get("theatre", Theatres.DEFAULT)
	war.maps.assign(data["maps"].duplicate(true))
	war.supply = data["supply"].duplicate()
	war.scores = data["scores"].duplicate()
	war.current = data["current"]
	war.ai_sides = data["ai_sides"].duplicate()
	war.settings.merge(data.get("settings", {}), true)
	war._rng.seed = data["rng_seed"]
	war._rng.state = data["rng_state"]
	return war


## What both players' games compare to know they hold the same campaign.
func checksum() -> String:
	return var_to_str(to_dict()).sha256_text()


## The commitment a side sends when it seals its orders: a hash of the orders and a secret salt. The orders
## themselves follow only once both sides have sealed, and must match it, so neither can see the other's
## first or change its own after.
static func orders_hash(orders: Dictionary, salt: String) -> String:
	return (var_to_str(orders) + "|" + salt).sha256_text()


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap
