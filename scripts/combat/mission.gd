class_name Mission
extends RefCounted
## Win conditions. Every battle has a mission (Battle.mission); the usual one, "points", is the empty
## dictionary: objectives score every round, first to the target or most points at the round limit wins.
## The others have an attacker, the side that has to do something, and a defender, who wins if the round
## limit (Battle.max_rounds) comes first:
##
## - "hold", Last stand: one objective, the defender's at the start. The attacker wins by holding it at the
##   start of one of its own turns (so it held it through the defender's whole turn). The defender is the
##   weaker side, dug in.
## - "extract", Extraction: the attacker's VIP (a downed pilot, a liaison officer) is lying low deep in the
##   defender's half. Hidden from anyone further than HIDING_RANGE away and unable to act until one of his
##   own reaches him; then he has to be walked into the extraction zone. The defender wins by killing him.
##   On random maps he is down around the middle, a little toward the defender, and they don't know where.
## - "demolition": the defender guards targets. Attacking soldiers plant charges on them from next to them
##   (one action); a charge goes off at the start of the planting side's next turn unless a defender pulls it
##   first (one action, also from next to it). Destroying "needed" of them wins.
## - "assassinate", Assassination: the defender's VIP (a staff officer, a commissar) has to survive. He wins at
##   once by reaching the exit zone, which opens on round "opens". The attacker wins by killing him.
## With "vip_known" the VIP's enemies always know where he is; otherwise only what they see.
## The attacker moves first in every round (Battle.first_team). Wiping out the other side wins every mission,
## as always.
##
## The dictionary (saved with the battle; positions are grid tiles, centres are Vector2):
## [codeblock]
## {"type": "hold"|"extract"|"demolition"|"assassinate", "attacker": 0|1,
##  "vip": unit id, "vip_known": bool, "found": bool (extract),
##  "zone": {"name", "center": Vector2, "radius": float}, "opens": round the zone opens (assassinate),
##  "targets": [{"name", "tile": Vector2i, "state": "intact"|"armed"|"destroyed", "unit": planter id}], "needed": int}
## [/codeblock]
## Hold uses the battle's one objective. A mission setup (skirmish menu, war campaign, scenario) is
## {"type", "attacker", "vip_known"}; prepare() turns it into the dictionary above on a generated map.

const POINTS := "points"
const HOLD := "hold"
const EXTRACT := "extract"
const DEMOLITION := "demolition"
const ASSASSINATE := "assassinate"
const TYPES := [POINTS, HOLD, EXTRACT, DEMOLITION, ASSASSINATE]
const TITLES := {POINTS: "Victory points", HOLD: "Last stand", EXTRACT: "Extraction", DEMOLITION: "Demolition", ASSASSINATE: "Assassination"}
## One line about each, for menus. "%s" is the attacker, then the defender.
const BLURBS := {
	POINTS: "Objectives score every round; first to the target wins.",
	HOLD: "%s must take the one objective; %s, outnumbered and dug in, must hold it to the end.",
	EXTRACT: "%s go in for their VIP, hiding deep behind the lines, and bring him out; %s must stop them.",
	DEMOLITION: "%s must blow up the targets %s are guarding.",
	ASSASSINATE: "%s must kill the VIP %s are getting away.",
}
## The role id of a mission's VIP (see Theatre.vip_def).
const VIP_ROLE := "VIP"
## A VIP lying low can't be seen from further than this, until his side reaches him.
const HIDING_RANGE := 3.0
## A demolition charge: its blast and damage.
const CHARGE_RADIUS := 2.0
const CHARGE_DAMAGE := [4, 7]
const CHARGE_SHRED := 2
## Extraction and exit zones.
const ZONE_RADIUS := 3.5
## The Last stand objective is at least this big.
const HOLD_RADIUS := 3.0
const TARGET_COUNT := 3
const TARGETS_NEEDED := 2


static func type_of(mission: Dictionary) -> String:
	return mission.get("type", POINTS)


static func title(type: String) -> String:
	return TITLES.get(type, type)


## A line about the mission type with the sides named, for menus.
static func blurb(type: String, attacker: int, theatre: Theatre) -> String:
	var text: String = BLURBS.get(type, "")
	return text % [theatre.team_name(attacker), theatre.team_name(1 - attacker)] if text.contains("%s") else text


## Round limits for a mission on a map of this side length (points games keep their own).
static func rounds_for(type: String, size: int) -> int:
	var bigger := 2 if size >= 60 else 0
	bigger += 2 if size >= 80 else 0
	match type:
		HOLD:
			return 8 + bigger
		DEMOLITION:
			return 14 + bigger
		EXTRACT, ASSASSINATE:
			return 12 + bigger
	return 20


## What `team` has to do, in a line: "Hold the Crossroads to the end of round 10".
static func goal_text(battle: Battle, team: int) -> String:
	var mission := battle.mission
	var type := type_of(mission)
	var attacking: bool = mission.get("attacker", 0) == team
	var by := "by the end of round %d" % battle.max_rounds
	match type:
		HOLD:
			var place: String = battle.objectives[0]["name"] if not battle.objectives.is_empty() else "objective"
			return ("Take the %s and hold it through their turn, %s" % [place, by]) if attacking \
					else ("Hold the %s to the end of round %d" % [place, battle.max_rounds])
		EXTRACT:
			var vip_name := vip_name(battle)
			return ("Reach the %s and get him to the %s, %s" % [vip_name, zone_name(battle), by]) if attacking \
					else ("Kill the enemy %s or stop him getting out until the end of round %d" % [vip_name, battle.max_rounds])
		DEMOLITION:
			return ("Blow up %d of the %d targets, %s" % [mission["needed"], mission["targets"].size(), by]) if attacking \
					else ("Keep at least %d of the targets standing to the end of round %d" % [mission["targets"].size() - mission["needed"] + 1, battle.max_rounds])
		ASSASSINATE:
			var vip_name := vip_name(battle)
			return ("Kill the %s %s" % [vip_name, by]) if attacking \
					else ("Keep the %s alive to the end of round %d, or get him to the %s (open from round %d)" % [vip_name, battle.max_rounds, zone_name(battle), mission.get("opens", 1)])
	return "Hold objectives: first to %d points wins" % battle.vp_to_win


## The mission's state in a few words for the top bar, from `team`'s point of view.
static func status_text(battle: Battle, team: int) -> String:
	var mission := battle.mission
	var left := battle.max_rounds - battle.round_number
	var clock := "last round" if left <= 0 else ("%d rounds left" % (left + 1))
	match type_of(mission):
		HOLD:
			var owner: int = battle.objectives[0]["owner"] if not battle.objectives.is_empty() else -1
			var held := "nobody" if owner == -1 else battle.team_name(owner)
			return "Last stand: %s held by %s, %s" % [battle.objectives[0]["name"] if not battle.objectives.is_empty() else "objective", held, clock]
		EXTRACT:
			var vip := battle.vip()
			var state := "dead" if vip == null or not vip.is_alive() else ("with his side" if mission.get("found", false) else "hiding")
			return "Extraction: %s %s, %s" % [vip_name(battle), state, clock]
		DEMOLITION:
			var destroyed := 0
			var armed := 0
			for t: Dictionary in mission["targets"]:
				destroyed += 1 if t["state"] == "destroyed" else 0
				armed += 1 if t["state"] == "armed" else 0
			return "Demolition: %d of %d blown%s, %s" % [destroyed, mission["needed"], (", %d armed" % armed) if armed > 0 else "", clock]
		ASSASSINATE:
			var opens: int = mission.get("opens", 1)
			var exit := "exit open" if battle.round_number >= opens else "exit opens round %d" % opens
			return "Assassination: %s, %s" % [exit, clock]
	return ""


## Why a battle ended, for the game-over screen: "by holding the objectives".
static func outcome_text(battle: Battle, reason: String) -> String:
	match reason:
		"points":
			return "by holding the objectives"
		"eliminated":
			return "by wiping out the enemy"
		"taken":
			return "by taking the %s" % (battle.objectives[0]["name"] if not battle.objectives.is_empty() else "objective")
		"held":
			return "by holding out"
		"extracted":
			return "by getting the %s out" % vip_name(battle)
		"vip_killed":
			return "by killing the %s" % vip_name(battle)
		"escaped":
			return "by getting the %s away" % vip_name(battle)
		"survived":
			return "by keeping the %s alive" % vip_name(battle)
		"demolished":
			return "by blowing up the targets"
		"saved":
			return "by keeping the targets standing"
		"time":
			return "by running out the clock"
	return ""


static func vip_name(battle: Battle) -> String:
	var vip := battle.vip()
	if vip != null:
		return battle.theatre().role_name(vip.team, VIP_ROLE).to_lower()
	return "VIP"


static func zone_name(battle: Battle) -> String:
	return battle.mission.get("zone", {}).get("name", "exit").to_lower()


# --- Random maps ---

## A random-map force adapted to the mission (forces as Theatre.skirmish_forces): the Last stand defender and
## the Extraction raiders get no reinforcements, and the round limit is the mission's.
static func adapt_forces(forces: Dictionary, setup: Dictionary, size: int) -> Dictionary:
	var type: String = setup.get("type", POINTS)
	if type == POINTS:
		return forces
	var result := forces.duplicate(true)
	var attacker: int = setup.get("attacker", 0)
	var weak := -1
	if type == HOLD:
		weak = 1 - attacker
	elif type == EXTRACT:
		weak = attacker
	if weak != -1:
		result["waves"] = result["waves"].filter(func(w: Dictionary) -> bool: return w["team"] != weak)
	result["max_rounds"] = rounds_for(type, size)
	return result


## Puts a mission setup ({"type", "attacker", "vip_known"}) on a generated layout. Returns {"layout",
## "rosters", "mission"}: the layout with its objectives as the mission needs (and target objects placed on
## its map), the rosters with VIPs added and defenders placed where the mission wants them, and the mission
## dictionary for BattleFactory ("vip" is filled in there). The same seed always gives the same result.
static func prepare(theatre: Theatre, layout: Dictionary, rosters: Array, setup: Dictionary, seed: int, max_rounds: int) -> Dictionary:
	var type: String = setup.get("type", POINTS)
	if type == POINTS:
		return {"layout": layout, "rosters": rosters, "mission": {}}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 7717
	var map: TacticalMap = layout["map"]
	var attacker: int = clampi(setup.get("attacker", 0), 0, 1)
	var defender := 1 - attacker
	var out := layout.duplicate()
	var placed := [_entries(rosters[0]), _entries(rosters[1])]
	var taken := {}
	for side in 2:
		for entry: Dictionary in placed[side]:
			if entry.has("pos"):
				taken[entry["pos"]] = true
	var reach := Pathfinder.search(map, spawn_center(layout, attacker), 100000.0)
	var mission := {"type": type, "attacker": attacker}
	match type:
		HOLD:
			var objective := _central_objective(layout)
			objective["radius"] = maxf(float(objective["radius"]), HOLD_RADIUS)
			out["objectives"] = [objective]
			_dig_in(map, placed[defender], [Vector2(objective["center"])], float(objective["radius"]) + 3.0, attacker, reach, taken, rng)
		EXTRACT, ASSASSINATE:
			var side := attacker if type == EXTRACT else defender
			# The downed VIP lies just past the middle; the one getting away starts among his own, at the back.
			var depth := rng.randf_range(0.45, 0.58) if type == EXTRACT else rng.randf_range(0.84, 0.92)
			var want := _from_edge(map, attacker, depth, rng.randf_range(0.2, 0.8))
			var vip_tile := _spot_near(map, want, reach, taken, attacker, 8, true)
			taken[vip_tile] = true
			placed[side].append({"role": VIP_ROLE, "pos": vip_tile})
			mission["vip_team"] = side
			mission["vip_known"] = bool(setup.get("vip_known", false))
			out["objectives"] = []
			if type == EXTRACT:
				mission["found"] = false
				var center := Vector2(_spot_near(map, Vector2i(spawn_center(layout, attacker)), reach, {}, attacker, 6, false)) + Vector2(0.5, 0.5)
				mission["zone"] = {"name": "Extraction point", "center": center, "radius": ZONE_RADIUS}
			else:
				# Two bodyguards stay with him; the exit is out on a flank, on the centre line.
				var guards := 0
				for entry: Dictionary in placed[side]:
					if guards >= 2 or entry["role"] == VIP_ROLE or theatre.role_def(side, entry["role"]).get("vehicle", false):
						continue
					if entry.has("pos"):
						taken.erase(entry["pos"])
					entry["pos"] = _spot_near(map, vip_tile, reach, taken, attacker, 6, true)
					taken[entry["pos"]] = true
					guards += 1
				var edge_y := 3 if rng.randf() < 0.5 else map.height - 4
				var exit := _spot_near(map, Vector2i(map.width / 2, edge_y), reach, taken, attacker, 6, false)
				mission["zone"] = {"name": "Exit", "center": Vector2(exit) + Vector2(0.5, 0.5), "radius": ZONE_RADIUS}
				mission["opens"] = maxi(3, max_rounds / 3)
		DEMOLITION:
			var names: Array = theatre.faction(defender).get("targets", ["Target A", "Target B", "Target C"])
			var kind: String = theatre.faction(defender).get("target_object", "crate")
			var targets := []
			var centers: Array[Vector2] = []
			for i in TARGET_COUNT:
				var y := (0.2 + 0.3 * i) + rng.randf_range(-0.06, 0.06)
				var want := _from_edge(map, attacker, rng.randf_range(0.55, 0.72), y)
				var tile := _target_tile(map, want, reach, taken)
				taken[tile] = true
				map.set_object(tile, Cover.HALF, kind)
				targets.append({"name": names[i % names.size()], "tile": tile, "state": "intact", "unit": -1})
				centers.append(Vector2(tile))
			mission["targets"] = targets
			mission["needed"] = TARGETS_NEEDED
			out["objectives"] = []
			_dig_in(map, placed[defender], centers, 6.0, attacker, reach, taken, rng)
	return {"layout": out, "rosters": placed, "mission": mission}


## Where a side's units start: the middle of its spawns (team 1's are the mirror image of the layout's).
static func spawn_center(layout: Dictionary, team: int) -> Vector2i:
	var map: TacticalMap = layout["map"]
	var sum := Vector2.ZERO
	var spawns: Array = layout["spawns"]
	for p: Vector2i in spawns:
		sum += Vector2(p if team == 0 else Vector2i(map.width - 1 - p.x, p.y))
	return Vector2i((sum / maxi(1, spawns.size())).round())


static func _entries(roster: Array) -> Array:
	var result := []
	for entry: Variant in roster:
		result.append((entry as Dictionary).duplicate() if entry is Dictionary else {"role": entry})
	return result


## A tile `depth` of the way across from the attacker's edge, `across` of the way down.
static func _from_edge(map: TacticalMap, attacker: int, depth: float, across: float) -> Vector2i:
	var x := roundi(depth * (map.width - 1))
	return Vector2i(x if attacker == 0 else map.width - 1 - x, roundi(across * (map.height - 1)))


## The layout's objective nearest the middle of the map (a copy).
static func _central_objective(layout: Dictionary) -> Dictionary:
	var map: TacticalMap = layout["map"]
	var middle := Vector2(map.width, map.height) / 2.0
	var best := {}
	for objective: Dictionary in layout["objectives"]:
		if best.is_empty() or Vector2(objective["center"]).distance_to(middle) < Vector2(best["center"]).distance_to(middle):
			best = objective
	if best.is_empty():
		return {"name": "Crossroads", "center": middle, "radius": HOLD_RADIUS}
	return best.duplicate()


## The free, reachable tile nearest `want`, preferring one in cover (facing the attacker) if `cover`.
static func _spot_near(map: TacticalMap, want: Vector2i, reach: Dictionary, taken: Dictionary, attacker: int, radius: int, cover: bool) -> Vector2i:
	var from := Vector2i(0 if attacker == 0 else map.width - 1, want.y)
	var best := want
	var best_score := INF
	for r in range(0, maxi(map.width, map.height)):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var p := want + Vector2i(dx, dy)
				if not map.in_bounds(p) or not map.is_passable(p) or not reach.has(p) or taken.has(p):
					continue
				var score := Vector2(p).distance_to(Vector2(want))
				if cover:
					score -= map.cover_against(p, from) * 2.0 + (1.0 if map.has_cover(p) else 0.0)
				if score < best_score:
					best_score = score
					best = p
		if best_score < INF and r >= radius:
			break
	return best


## A tile for a demolition target near `want`: open ground with room all round to walk up to it.
static func _target_tile(map: TacticalMap, want: Vector2i, reach: Dictionary, taken: Dictionary) -> Vector2i:
	for r in range(0, maxi(map.width, map.height)):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var p := want + Vector2i(dx, dy)
				if not map.in_bounds(p) or not map.is_passable(p) or not reach.has(p) or taken.has(p) or map.has_mine(p):
					continue
				var open := 0
				for d: Vector2i in TacticalMap.DIRS8:
					if map.is_passable(p + d) and reach.has(p + d) and not taken.has(p + d) and (absi(d.x) + absi(d.y) == 2 or map.get_edge(p, p + d) == Cover.NONE):
						open += 1
				if open >= 6:
					return p
	return want


## Places a defending roster around `centers` (spread over them in turn), within `spread` tiles, in cover
## facing the attacker where it can, crouched and facing the attacker's edge; sandbags where there's no cover.
## Units may stand next to each other only when there's no room left.
static func _dig_in(map: TacticalMap, roster: Array, centers: Array, spread: float, attacker: int, reach: Dictionary, taken: Dictionary, rng: RandomNumberGenerator) -> void:
	# Toward the attacker's edge.
	var forward := Vector2i(-1, 0) if attacker == 0 else Vector2i(1, 0)
	for i in roster.size():
		var entry: Dictionary = roster[i]
		var center: Vector2 = centers[i % centers.size()]
		if entry.has("pos"):
			taken.erase(entry["pos"])
		var best := Vector2i(center)
		var best_score := -INF
		for y in range(floori(center.y - spread), ceili(center.y + spread) + 1):
			for x in range(floori(center.x - spread), ceili(center.x + spread) + 1):
				var p := Vector2i(x, y)
				var distance := (Vector2(p) + Vector2(0.5, 0.5)).distance_to(center)
				if distance > spread or not map.in_bounds(p) or not map.is_passable(p) or not reach.has(p) or taken.has(p):
					continue
				if _crowded(p, taken):
					continue
				var from := Vector2i(0 if attacker == 0 else map.width - 1, p.y)
				var score := map.cover_against(p, from) * 3.0 + (1.0 if map.has_cover(p) else 0.0) - distance * 0.4 + rng.randf() * 0.8
				if score > best_score:
					best_score = score
					best = p
		if best_score == -INF:
			best = _spot_near(map, Vector2i(center), reach, taken, attacker, 4, true)
		taken[best] = true
		entry["pos"] = best
		entry["facing"] = forward
		# Crouched (BattleFactory leaves vehicles standing).
		entry["stance"] = Unit.Stance.CROUCH
		var front := best + forward
		var from_edge := Vector2i(0 if attacker == 0 else map.width - 1, best.y)
		if map.cover_against(best, from_edge) == Cover.NONE and map.in_bounds(front) and map.is_passable(front) \
				and not taken.has(front) and map.get_edge(best, front) == Cover.NONE:
			map.set_object(front, Cover.HALF, "sandbags")


static func _crowded(p: Vector2i, taken: Dictionary) -> bool:
	for d: Vector2i in TacticalMap.DIRS8:
		if taken.has(p + d):
			return true
	return false
