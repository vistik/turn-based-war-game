extends SceneTree
## Headless tests for the combat engine and AI.
## Run: Godot --headless --path . -s tests/run_tests.gd

var _failures := 0
var _checks := 0


func _initialize() -> void:
	for method in get_method_list():
		var test_name: String = method["name"]
		if test_name.begins_with("test_"):
			call(test_name)
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


## A battle on an open map; specs are [role, team, pos].
func make_battle(specs: Array, size := Vector2i(16, 16)) -> Battle:
	var units: Array[Unit] = []
	for spec in specs:
		units.append(Unit.create(units.size(), "U%d" % units.size(), spec[0], spec[1], spec[2]))
	var battle := Battle.new(TacticalMap.new(size.x, size.y), units, 1234)
	battle.start()
	return battle


func events_of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


# --- Map and scenario ---

## How many tiles differ from the tile across the map (east for west): 0 for a mirrored map.
func mirror_mismatches(map: TacticalMap) -> int:
	var mismatches := 0
	for y in map.height:
		for x in map.width / 2:
			var p := Vector2i(x, y)
			var m := Vector2i(map.width - 1 - x, y)
			if map.get_terrain(p) != map.get_terrain(m) or map.get_object(p) != map.get_object(m) \
					or map.get_edge(p, p + Vector2i(0, 1)) != map.get_edge(m, m + Vector2i(0, 1)):
				mismatches += 1
	return mismatches


## How much further one side walks to the objectives in all than the other, as a share of both walks:
## 0 is even, 1 is all on one side.
func walk_imbalance(layout: Dictionary) -> float:
	var map: TacticalMap = layout["map"]
	var totals := [0.0, 0.0]
	for team in 2:
		var reach := Pathfinder.search(map, layout["spawns"][team][0], 100000.0)
		for objective: Dictionary in layout["objectives"]:
			totals[team] += reach[Vector2i(objective["center"])]["cost"] if reach.has(Vector2i(objective["center"])) else 1000.0
	return absf(totals[0] - totals[1]) / (totals[0] + totals[1])


func test_normandy_village_is_lopsided_fair_and_connected() -> void:
	var battle := NormandyScenario.build()
	var map := battle.map
	check(mirror_mismatches(map) > 100, "the village is not a mirror image (%d tiles differ)" % mirror_mismatches(map))
	var imbalance := walk_imbalance(NormandyScenario.layout())
	check(imbalance < 0.12, "but both sides walk about as far to the objectives (%.2f)" % imbalance)
	check_eq(battle.alive_units(0).size(), 8, "allied squad")
	check_eq(battle.alive_units(1).size(), 8, "german squad")
	check_eq(battle.objectives.size(), 3, "three objectives")
	for u in battle.units:
		check(map.is_passable(u.pos), "%s spawns on open ground" % u.name)
		var reach := Pathfinder.search(map, u.pos, 500.0, {})
		for objective in battle.objectives:
			var tile := Vector2i(objective["center"])
			check(reach.has(tile), "%s can walk to the %s" % [u.name, objective["name"]])


# --- Scenario files ---

## A small scenario using every feature of the format.
func make_scenario() -> Scenario:
	var s := Scenario.create(12, 10)
	s.title = "Test ground"
	s.briefing = "Hold the barn.\nNo retreat."
	s.vp_to_win = 7
	s.max_rounds = 9
	s.map.set_terrain(Vector2i(2, 3), TacticalMap.Terrain.WHEAT)
	s.map.set_terrain(Vector2i(5, 5), TacticalMap.Terrain.ROAD)
	s.map.set_terrain(Vector2i(6, 1), TacticalMap.Terrain.INDOOR)
	s.map.set_object(Vector2i(4, 4), Cover.FULL, "tree")
	s.map.set_object(Vector2i(7, 2), Cover.HALF, "sandbags")
	s.map.set_object(Vector2i(8, 8), Cover.FULL, "crate")
	s.map.set_edge(Vector2i(3, 3), Vector2i(4, 3), Cover.FULL, "hedge")
	s.map.set_edge(Vector2i(6, 1), Vector2i(6, 0), Cover.HALF, "window")
	s.map.set_edge(Vector2i(9, 9), Vector2i(8, 9), Cover.HALF, "fence")
	s.objectives.append({"name": "Barn", "center": Vector2(6, 4.5), "radius": 2.0})
	s.units.append(Scenario.unit_entry(0, "Officer", Vector2i(1, 4), Vector2i(1, 0), "Lt. Test", 2))
	s.units.append(Scenario.unit_entry(0, "Rifleman", Vector2i(1, 7), Vector2i(1, -1)))
	s.units.append(Scenario.unit_entry(1, "MG", Vector2i(10, 4), Vector2i(0, 1)))
	var spawns: Array[Vector2i] = [Vector2i(11, 0), Vector2i(11, 9)]
	s.reinforcements.append({"round": 3, "team": 1, "roster": ["Rifleman", {"role": "Sniper", "name": "Hans", "rank": 1}], "spawns": spawns})
	return s


func same_map(a: TacticalMap, b: TacticalMap) -> bool:
	if a.width != b.width or a.height != b.height or a.get_edges().size() != b.get_edges().size():
		return false
	for y in a.height:
		for x in a.width:
			var p := Vector2i(x, y)
			if a.get_terrain(p) != b.get_terrain(p) or a.get_object(p) != b.get_object(p) or a.get_object_kind(p) != b.get_object_kind(p):
				return false
	for key: Vector3i in a.get_edges():
		var pair := TacticalMap.edge_tiles(key)
		if b.get_edge(pair[0], pair[1]) != a.get_edges()[key] or b.get_edge_kind(pair[0], pair[1]) != a.edge_kind(key):
			return false
	return true


## Units as comparable rows: [id, name, role, team, pos, facing, rank], then reinforcements.
func unit_rows(battle: Battle) -> Array:
	var rows := []
	for u in battle.units:
		rows.append([u.id, u.name, u.role, u.team, u.pos, u.facing, u.rank])
	for wave in battle.reinforcements:
		for u: Unit in wave["units"]:
			rows.append([wave["round"], u.id, u.name, u.role, u.team, u.pos, u.rank])
	return rows


func test_scenario_round_trip() -> void:
	var s := make_scenario()
	var json := JSON.new()
	check_eq(json.parse(s.to_json()), OK, "scenario JSON parses")
	var loaded := Scenario.from_data(json.data)
	check(loaded != null, "scenario loads: %s" % Scenario.last_error)
	if loaded == null:
		return
	check_eq(loaded.to_json(), s.to_json(), "saving the loaded scenario gives the same file")
	check(same_map(loaded.map, s.map), "same map after a round trip")
	check_eq(loaded.objectives, s.objectives, "same objectives")
	var battle := loaded.build_battle(5)
	check_eq(unit_rows(battle), unit_rows(s.build_battle(5)), "same units")
	check_eq(battle.get_unit(0).name, "Lt. Test", "named units keep their name")
	check_eq(battle.get_unit(0).rank, 2, "and rank")
	check_eq(battle.get_unit(1).facing, Vector2i(1, -1), "units keep a diagonal facing")
	check_eq(battle.get_unit(2).pos, Vector2i(10, 4), "units start on their exact tile")
	check_eq(battle.reinforcements[0]["units"][1].name, "Hans", "reinforcements keep names")
	check_eq(battle.reinforcements[0]["units"][0].pos, Vector2i(11, 0), "reinforcements use the wave's spawn tiles")
	check_eq([battle.vp_to_win, battle.max_rounds], [7, 9], "rules carry over")
	check_eq(battle.map.get_object(Vector2i(8, 8)), Cover.FULL, "an unusual cover level for a kind is kept")
	check_eq(unit_rows(s.build_battle(5)), unit_rows(s.build_battle(5)), "the same seed builds the same battle")

	# Export from a battle, then build it again: the same battle.
	var original: Battle = GameSession.build_skirmish({"map": "random", "size": 44, "seed": 3})[0]
	var exported := Scenario.from_battle(original, "Random 3")
	var rebuilt := Scenario.from_data(exported.to_data()).build_battle(3)
	check(same_map(rebuilt.map, original.map), "exported map matches the battle's")
	check_eq(unit_rows(rebuilt), unit_rows(original), "exported units match the battle's")
	check_eq(rebuilt.objectives, original.objectives, "exported objectives match")
	check(exported.validate().is_empty(), "an exported generated map is valid: %s" % exported.validate())

	# Swapping the sides twice gives back the original.
	var twice := s.swapped().swapped()
	twice.title = s.title
	check_eq(twice.to_json(), s.to_json(), "swapping sides twice changes nothing")
	var swapped := s.swapped()
	check_eq(swapped.units[0]["team"], 0, "the German force now plays for the Allies")
	check_eq(swapped.units[0]["pos"], Vector2i(1, 4), "from the other side of the map")

	s.map.set_mine(Vector2i(3, 7), true)
	check(s.swapped().map.has_mine(Vector2i(8, 7)), "swapping sides takes the mines across too")
	check(not Scenario.from_data(s.to_data()).to_data().has("mirrored"), "scenario files no longer keep a mirror flag")
	var old := s.to_data()
	old["mirrored"] = true
	check(Scenario.from_data(old) != null, "an old file with the mirror flag still loads")
	check(Scenario.from_data({"map": {"width": 2}}) == null, "a bad file is refused")


func test_village_scenario_builds_the_village() -> void:
	var scenario := Scenario.load_file("res://scenarios/village.json")
	check(scenario != null, "bundled village scenario loads: %s" % Scenario.last_error)
	if scenario == null:
		return
	check(scenario.validate().is_empty(), "village scenario is valid: %s" % scenario.validate())
	var battle := scenario.build_battle(7)
	var village := NormandyScenario.build(7)
	check(same_map(battle.map, village.map), "same map as the hand-built village")
	check_eq(unit_rows(battle), unit_rows(village), "same soldiers in the same places")
	check_eq(battle.objectives, village.objectives, "same objectives")
	check_eq([battle.vp_to_win, battle.max_rounds], [village.vp_to_win, village.max_rounds], "same rules")
	check(Scenario.list_files().any(func(f: Dictionary) -> bool: return f["path"] == "res://scenarios/village.json"), "village is listed")
	# A short AI vs AI game on it.
	battle.max_rounds = 3
	var result := BalanceSim.play(battle, 7)
	check(result["winner"] != -1, "AI vs AI on the village scenario finishes")
	check_eq(result["survivors"][0] + result["survivors"][1], battle.alive_units().size(), "survivors counted")
	check_eq(BalanceSim.summarize([result, result])["games"], 2, "summary counts games")
	var ci := BalanceSim.wilson(5, 10)
	check(ci[0] < 0.5 and ci[1] > 0.5 and ci[0] > 0.2, "confidence interval around 50%")


# --- Movement and terrain ---

func test_path_costs() -> void:
	var map := TacticalMap.new(10, 10)
	var reach := Pathfinder.search(map, Vector2i(0, 0), 20.0)
	check_eq(reach[Vector2i(3, 0)]["cost"], 3.0, "straight move")
	check_eq(reach[Vector2i(2, 2)]["cost"], 3.0, "diagonals cost 1.5")
	map.set_terrain(Vector2i(1, 0), TacticalMap.Terrain.ROUGH)
	map.set_terrain(Vector2i(0, 1), TacticalMap.Terrain.ROAD)
	reach = Pathfinder.search(map, Vector2i(0, 0), 20.0)
	check_eq(reach[Vector2i(1, 0)]["cost"], 2.0, "rough ground costs double")
	check_eq(reach[Vector2i(0, 1)]["cost"], 0.75, "roads are quicker")


func test_walls_hedges_and_low_walls() -> void:
	var map := TacticalMap.new(10, 10)
	map.set_edge(Vector2i(0, 0), Vector2i(1, 0), Cover.HALF, "stone")
	check_eq(map.step_cost(Vector2i(0, 0), Vector2i(1, 0)), 2.0, "vaulting a low wall")
	map.set_edge(Vector2i(0, 0), Vector2i(1, 0), Cover.FULL, "wall")
	check_eq(map.step_cost(Vector2i(0, 0), Vector2i(1, 0)), INF, "walls block")
	map.set_edge(Vector2i(0, 0), Vector2i(1, 0), Cover.FULL, "hedge")
	check_eq(map.step_cost(Vector2i(0, 0), Vector2i(1, 0)), 1.0 + TacticalMap.HEDGE_COST, "pushing through a hedge")
	check(LineOfSight.has_line(map, Vector2i(0, 0), Vector2i(5, 0)), "standing, you see over a hedge")
	var low := TacticalMap.STANCE_EYE[Unit.Stance.PRONE]
	check(not LineOfSight.has_line(map, Vector2i(0, 0), Vector2i(5, 0), 0, 0, low, low), "lying down, you don't")
	check_eq(map.step_cost(Vector2i(0, 1), Vector2i(1, 0)), INF, "no cutting corners")
	map.set_object(Vector2i(5, 5), Cover.HALF)
	check_eq(map.step_cost(Vector2i(4, 4), Vector2i(5, 5)), INF, "can't stand on a crate")


func test_hedges_hide_the_prone_not_the_standing() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(8, 5)]])
	var map := battle.map
	for y in range(2, 9):
		map.set_edge(Vector2i(7, y), Vector2i(8, y), Cover.FULL, "hedge")
	var us := battle.units[0]
	var them := battle.units[1]
	check_eq(map.cover_against(them.pos, us.pos), Cover.HALF, "standing behind a hedge is half cover")
	check_eq(map.cover_against(them.pos, us.pos, 0, 0, true), Cover.FULL, "lying behind it, full cover")
	check(battle.can_see(us, them), "a soldier standing behind a hedge is seen")
	check(battle.can_see(them, us), "and sees over it")
	check_eq(battle.shot_odds(us, them)["cover"], Cover.HALF, "and is shot at through half cover")
	them.stance = Unit.Stance.PRONE
	check(not battle.can_see(us, them), "lying down behind it he is hidden")
	check(not battle.can_see(them, us), "and sees nothing past it")
	check(not battle.team_visible_tiles(1).has(Vector2i(4, 5)), "his view stops at the hedge")
	check_eq(battle.shot_odds(us, them)["cover"], Cover.FULL, "full cover lying down")
	map.damage_edge(TacticalMap.edge_key(Vector2i(7, 5), Vector2i(8, 5)), 1)
	check_eq(map.cover_against(them.pos, us.pos, 0, 0, true), Cover.HALF, "one hit breaches a hedge: half cover either way")


func test_crater_gives_cover_everywhere() -> void:
	var map := TacticalMap.new(10, 10)
	map.set_terrain(Vector2i(5, 5), TacticalMap.Terrain.CRATER)
	check_eq(map.cover_against(Vector2i(5, 5), Vector2i(9, 5)), Cover.HALF, "crater covers east")
	check_eq(map.cover_against(Vector2i(5, 5), Vector2i(5, 0)), Cover.HALF, "and north")


func test_units_block_paths() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 1, Vector2i(1, 0)]])
	check(not battle.reachable(battle.units[0]).has(Vector2i(1, 0)), "can't move onto a unit")


func test_move_and_dash_spend_actions() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 1, Vector2i(15, 15)]])
	var u := battle.units[0]
	battle.move(u, Vector2i(5, 0))
	check_eq(u.actions, 1, "short move costs one action")
	check(battle.reachable(u).has(Vector2i(12, 0)), "can still move 7")
	check(not battle.reachable(u).has(Vector2i(13, 0)), "but not 8")
	battle = make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 0, Vector2i(0, 15)], ["Rifleman", 1, Vector2i(15, 15)]])
	battle.move(battle.units[0], Vector2i(12, 0))
	check_eq(battle.units[0].actions, 0, "dash costs both actions")


# --- Sight ---

func test_line_of_sight_and_step_out() -> void:
	var map := TacticalMap.new(12, 12)
	map.set_object(Vector2i(4, 5), Cover.HALF)
	check(LineOfSight.has_line(map, Vector2i(2, 5), Vector2i(7, 5)), "half cover doesn't block sight")
	map.set_object(Vector2i(3, 5), Cover.FULL)
	check(not LineOfSight.has_line(map, Vector2i(2, 5), Vector2i(6, 5)), "full cover blocks sight")
	check(LineOfSight.can_see(map, Vector2i(2, 5), Vector2i(6, 5), 12.0), "stepping out sees round it")
	check(not LineOfSight.can_see(map, Vector2i(2, 5), Vector2i(10, 5), 6.0), "sight range limits")


func test_smoke_blocks_sight_then_clears() -> void:
	var battle := make_battle([["Officer", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(10, 5)], ["Rifleman", 0, Vector2i(0, 15)]])
	var officer := battle.units[0]
	check(battle.can_see(officer, battle.units[1]), "clear view before smoke")
	battle.throw_smoke(officer, Vector2i(6, 5))
	check(not battle.can_see(officer, battle.units[1]), "smoke blocks the view")
	check_eq(officer.actions, 1, "smoke takes one action")
	for i in CombatRules.SMOKE_TURNS:
		battle.end_turn()
	check(not battle.map.has_smoke(Vector2i(6, 5)), "smoke clears after two rounds")
	check(battle.can_see(officer, battle.units[1]), "view is back")


# --- Shooting ---

func test_directional_cover_and_flanking() -> void:
	var map := TacticalMap.new(12, 12)
	map.set_object(Vector2i(6, 5), Cover.HALF)
	check_eq(map.cover_against(Vector2i(5, 5), Vector2i(10, 5)), Cover.HALF, "cover faces attacker")
	check_eq(map.cover_against(Vector2i(5, 5), Vector2i(5, 0)), Cover.NONE, "flanked from the north")


func test_hit_chance() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(1, 5)], ["Rifleman", 1, Vector2i(5, 5)]])
	battle.map.set_object(Vector2i(4, 5), Cover.HALF)
	var shooter := battle.units[0]
	var target := battle.units[1]
	var range_mod := shooter.weapon.range_modifier(4.0)
	check_eq(range_mod, 8, "the Garand at 4 tiles (its table stretched by Weapon.RANGE_SCALE)")
	check_eq(battle.shot_odds(shooter, target)["hit"], 65 + range_mod - 20, "aim + range - half cover")
	shooter.suppression = Unit.SUPPRESSED_AT
	check_eq(battle.shot_odds(shooter, target)["hit"], 65 + range_mod - 20 - CombatRules.SUPPRESSED_AIM_PENALTY, "suppressed shooters aim worse")
	shooter.suppression = 0
	shooter.pos = Vector2i(5, 1)
	var odds := battle.shot_odds(shooter, target)
	check(odds["flanked"], "flanked from the side")
	check_eq(odds["crit"], 10 + CombatRules.FLANK_CRIT_BONUS, "flank crit bonus")


func test_wheat_conceals_at_range() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 5)], ["Rifleman", 1, Vector2i(8, 5)]])
	var before: int = battle.shot_odds(battle.units[0], battle.units[1])["hit"]
	battle.map.set_terrain(Vector2i(8, 5), TacticalMap.Terrain.WHEAT)
	check_eq(battle.shot_odds(battle.units[0], battle.units[1])["hit"], before - CombatRules.WHEAT_CONCEALMENT, "wheat hides at range")
	battle.units[0].pos = Vector2i(5, 5)
	var close: int = battle.shot_odds(battle.units[0], battle.units[1])["hit"]
	battle.map.set_terrain(Vector2i(8, 5), TacticalMap.Terrain.FLOOR)
	check_eq(battle.shot_odds(battle.units[0], battle.units[1])["hit"], close, "but not up close")


func test_a_shell_hit_shows_the_blast_before_the_kill() -> void:
	var battle := make_battle([["Tank", 0, Vector2i(2, 8)], ["Rifleman", 1, Vector2i(7, 8)]])
	battle.units[0].aim = 300
	battle.units[1].hp = 1
	var events := battle.shoot(battle.units[0], battle.units[1])
	var types: Array = events.map(func(e: Dictionary) -> String: return e["type"])
	check_eq(types[0], "shot", "the shot comes first")
	check(types.has("explosion") and types.has("death"), "the shell bursts and kills (%s)" % [types])
	check(types.find("explosion") < types.find("damage") and types.find("damage") < types.find("death"), "then the blast, then the hit and the kill (%s)" % [types])


func test_the_first_side_opens_with_one_action() -> void:
	var battle: Battle = GameSession.build_skirmish({"map": "random", "size": 32, "seed": 77})[0]
	battle.start()
	check(battle.alive_units(0).all(func(u: Unit) -> bool: return u.actions == 1), "the side moving first has one action each in round 1")
	check_eq(Battle.from_dict(battle.to_dict()).opening_actions, 1, "and a saved battle remembers it")
	battle.end_turn()
	check(battle.alive_units(1).all(func(u: Unit) -> bool: return u.actions == 2), "the other side gets both")
	battle.end_turn()
	check(battle.alive_units(0).all(func(u: Unit) -> bool: return u.actions == 2), "and so does the first side from round 2")


func test_vehicles_are_switched_off() -> void:
	for theatre_id: String in ["normandy", "vietnam", "modern"]:
		var battle: Battle = GameSession.build_skirmish({"theatre": theatre_id, "map": "random", "size": 84, "seed": 3})[0]
		check(not battle.units.any(func(u: Unit) -> bool: return u.vehicle), "%s: no vehicles in a big skirmish" % theatre_id)
		check(not battle.reinforcements.any(func(w: Dictionary) -> bool: return w["units"].any(func(u: Unit) -> bool: return u.vehicle)),
				"%s: nor among the reinforcements" % theatre_id)
		var theatre := Theatres.get_theatre(theatre_id)
		check(not theatre.role_ids(0).any(func(r: String) -> bool: return theatre.is_vehicle(0, r)), "%s: none for sale" % theatre_id)


func test_observed_fire_lands_at_once() -> void:
	var battle := make_battle([["Mortar", 0, Vector2i(2, 8)], ["Rifleman", 0, Vector2i(9, 8)], ["Rifleman", 1, Vector2i(10, 9)]], Vector2i(24, 24))
	battle.units[2].hp = 50
	var events := battle.fire_mortar(battle.units[0], Vector2i(10, 9), "he")
	check(events_of(events, "mortar_fire")[0].get("observed", false), "a target a soldier of ours can see is observed")
	check_eq(events_of(events, "strike").size(), 1, "and the round comes down at once")
	check(battle.strikes.is_empty(), "nothing is left pending")
	var blind := make_battle([["Mortar", 0, Vector2i(2, 8)], ["Rifleman", 1, Vector2i(14, 8)]], Vector2i(24, 24))
	blind.map.set_edge(Vector2i(13, 8), Vector2i(14, 8), Cover.FULL, "wall")
	blind.map.set_edge(Vector2i(14, 7), Vector2i(14, 8), Cover.FULL, "wall")
	blind.map.set_edge(Vector2i(14, 8), Vector2i(14, 9), Cover.FULL, "wall")
	blind.map.set_edge(Vector2i(14, 8), Vector2i(15, 8), Cover.FULL, "wall")
	if not blind.is_spotted(0, Vector2i(14, 8)):
		var blind_events := blind.fire_mortar(blind.units[0], Vector2i(14, 8), "he")
		check_eq(events_of(blind_events, "strike").size(), 1, "blind fire lands at once too")
		check(not blind_events[0]["observed"], "marked as fired blind")
		check(blind.strikes.is_empty(), "nothing left pending")


func test_medkit_steadies_a_shaken_man() -> void:
	var battle := make_battle([["Medic", 0, Vector2i(2, 2)], ["Rifleman", 0, Vector2i(3, 2)], ["Rifleman", 1, Vector2i(14, 14)]])
	var patient := battle.units[1]
	patient.suppression = 60
	check_eq(battle.can_use_medkit(battle.units[0], patient), "", "an unhurt but shaken soldier can be treated")
	battle.use_medkit(battle.units[0], patient)
	check_eq(patient.suppression, 20, "the medkit takes 40 off his suppression")


func test_heavy_mg_fires_on_the_move_but_worse() -> void:
	var battle := make_battle([["MG", 0, Vector2i(2, 8)], ["Rifleman", 1, Vector2i(10, 8)]])
	var mg := battle.units[0]
	var still: int = battle.shot_odds(mg, battle.units[1])["hit"]
	battle.move(mg, Vector2i(3, 8))
	check_eq(battle.can_fire(mg), "", "the gun can fire after moving")
	check_eq(battle.shot_odds(mg, battle.units[1])["hit"], still - CombatRules.HEAVY_MOVED_AIM_PENALTY, "at a penalty")
	check(battle.can_suppress(mg, battle.units[1]) != "", "but lays no suppressive fire")


func test_fire_smokes_and_scorches_its_neighbours() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(5, 5)], ["Rifleman", 1, Vector2i(14, 14)]])
	battle.map.set_terrain(Vector2i(6, 5), TacticalMap.Terrain.WHEAT)
	battle._ignite(Vector2i(6, 5))
	check(battle.map.has_smoke(Vector2i(6, 5)), "a fire fills its tile with smoke")
	check_eq(battle.map.get_fires()[Vector2i(6, 5)], battle.turn_index + CombatRules.LONG_BURN_TURNS, "crops burn longer")
	battle.end_turn()
	var events := battle.end_turn()
	check(battle.units[0].suppression >= CombatRules.FIRE_HEAT_SUPPRESSION or events_of(events, "suppression").size() > 0, "the heat shakes a soldier next to it")


func test_upper_floor_blasts_weaken_a_building() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(1, 1)], ["Rifleman", 1, Vector2i(14, 14)]])
	var map := battle.map
	for y in range(4, 7):
		for x in range(4, 7):
			map.set_terrain(Vector2i(x, y), TacticalMap.Terrain.INDOOR)
			map.set_storeys(Vector2i(x, y), 3)
	for i in range(4, 7):
		map.set_edge(Vector2i(i, 3), Vector2i(i, 4), Cover.FULL, "wall")
		map.set_edge(Vector2i(i, 6), Vector2i(i, 7), Cover.FULL, "wall")
		map.set_edge(Vector2i(3, i), Vector2i(4, i), Cover.FULL, "wall")
		map.set_edge(Vector2i(6, i), Vector2i(7, i), Cover.FULL, "wall")
	battle._explode(battle.units[0], Vector2i(4, 4), 1.0, 1, 1, 0, null, CombatRules.EXPLOSION_VS_ARMOR, 1, CombatRules.WALL_HITS["shell"])
	check_eq(map.edge_damage(TacticalMap.edge_key(Vector2i(4, 3), Vector2i(4, 4))), 1, "a shell on the first floor knocks a stage off that room's outer walls")
	check(battle.collapse_progress(Vector2i(5, 5)) == 0.0, "only damaged, nothing breached yet")
	check(battle._collapse_share([Vector2i(4, 4)] as Array[Vector2i]) < CombatRules.COLLAPSE_SHARE, "a three-storey building needs fewer broken walls")


func test_a_mine_sets_the_ground_alight() -> void:
	for seed in 6:
		var units: Array[Unit] = [Unit.create(0, "U0", "Rifleman", 0, Vector2i(5, 5)), Unit.create(1, "U1", "Rifleman", 1, Vector2i(14, 14))]
		var battle := Battle.new(TacticalMap.new(16, 16), units, seed)
		battle.start()
		units[0].hp = 100
		battle.map.set_mine(Vector2i(6, 5), true)
		var events := battle._trigger_mine(units[0], Vector2i(6, 5))
		var lit := battle.map.tiles_in_radius(Vector2i(6, 5), CombatRules.MINE_RADIUS).filter(func(p: Vector2i) -> bool: return battle.map.has_fire(p))
		check(not lit.is_empty() and not events_of(events, "fire").is_empty(), "a mine always starts a fire on open ground (seed %d)" % seed)
		check(not battle.map.has_fire(units[0].pos), "but not under the soldier on grass")
	var road := make_battle([["Rifleman", 0, Vector2i(5, 5)], ["Rifleman", 1, Vector2i(14, 14)]])
	for p in road.map.tiles_in_radius(Vector2i(6, 5), 1.5):
		road.map.set_terrain(p, TacticalMap.Terrain.ROAD)
	road.units[0].hp = 100
	road.map.set_mine(Vector2i(6, 5), true)
	road._trigger_mine(road.units[0], Vector2i(6, 5))
	check(road.map.get_fires().is_empty(), "a road doesn't burn")


func test_breached_walls_and_collapses_raise_dust() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(1, 1)], ["Rifleman", 1, Vector2i(14, 14)]])
	var map := battle.map
	map.set_edge(Vector2i(8, 8), Vector2i(9, 8), Cover.FULL, "wall")
	map.set_edge(Vector2i(8, 10), Vector2i(9, 10), Cover.HALF, "fence")
	var events := battle._explode(null, Vector2i(8, 8), 0.5, 1, 1, 0, null, CombatRules.EXPLOSION_VS_ARMOR, 0, CombatRules.WALL_HITS["shell"])
	check(map.edge_damage(TacticalMap.edge_key(Vector2i(8, 8), Vector2i(9, 8))) >= 2, "the shell breaches the wall")
	check(map.has_smoke(Vector2i(9, 8)), "brick dust fills the far side")
	check_eq(map.get_smoke()[Vector2i(9, 8)], battle.turn_index + CombatRules.DUST_TURNS, "for a short while")
	check_eq(events_of(events, "dust").size(), 1, "one dust cloud")
	var fence := battle._explode(null, Vector2i(8, 10), 0.5, 1, 1, 0, null, CombatRules.EXPLOSION_VS_ARMOR, 0, CombatRules.WALL_HITS["shell"])
	check(events_of(fence, "dust").is_empty(), "a fence knocked down throws up no dust")
	var tiles: Array[Vector2i] = [Vector2i(3, 12), Vector2i(4, 12)]
	var collapse := battle._collapse(tiles)
	check(map.has_smoke(Vector2i(3, 12)) and map.has_smoke(Vector2i(5, 13)), "a collapse buries the ruins and the ground round them in dust")
	check(events_of(collapse, "dust").size() == 1 and events_of(collapse, "dust")[0].get("collapse", false), "and says so")


func test_hay_and_crates_burn() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(1, 1)], ["Rifleman", 1, Vector2i(14, 14)]])
	var map := battle.map
	map.set_object(Vector2i(6, 6), Cover.HALF, "hay")
	battle._ignite(Vector2i(6, 6))
	check_eq(map.get_object(Vector2i(6, 6)), Cover.NONE, "a burning hay bale is gone, its cover with it")
	check_eq(map.get_fires()[Vector2i(6, 6)], battle.turn_index + CombatRules.LONG_BURN_TURNS, "hay burns long")
	var caught := 0
	for seed in 10:
		var units: Array[Unit] = [Unit.create(0, "U0", "Rifleman", 0, Vector2i(1, 1)), Unit.create(1, "U1", "Rifleman", 1, Vector2i(14, 14))]
		var b := Battle.new(TacticalMap.new(16, 16), units, seed + 1)
		b.start()
		b.map.set_object(Vector2i(7, 7), Cover.HALF, "hay")
		b.map.set_terrain(Vector2i(6, 7), TacticalMap.Terrain.ROAD)
		b.map.add_fire(Vector2i(6, 7), b.turn_index + 10)
		for i in 4:
			b._spread_fires()
		if b.map.has_fire(Vector2i(7, 7)):
			caught += 1
	check(caught >= 5, "fire next door sets hay alight (%d of 10)" % caught)
	map.set_object(Vector2i(10, 10), Cover.HALF, "hay")
	var blasts := 0
	for i in 10:
		map.set_object(Vector2i(10, 10), Cover.HALF, "hay")
		map.clear_fires(battle.turn_index + 100)
		battle._explode(null, Vector2i(10, 10), 1.0, 0, 0, 0)
		if map.has_fire(Vector2i(10, 10)):
			blasts += 1
	check(blasts >= 4, "a blast over a hay bale usually sets it burning (%d of 10)" % blasts)


func test_rockets_fire_at_any_tile() -> void:
	var battle := make_battle([["AT", 0, Vector2i(2, 5)], ["Rifleman", 0, Vector2i(2, 9)], ["Rifleman", 1, Vector2i(9, 5)]], Vector2i(24, 16))
	var at := battle.units[0]
	var rifle := battle.units[1]
	var hidden := battle.units[2]
	check_eq(battle.can_fire_at_tile(at, Vector2i(8, 9)), "", "a rocket can be fired at an empty tile")
	check(battle.can_fire_at_tile(rifle, Vector2i(8, 9)) != "", "a rifle can't")
	check(battle.can_fire_at_tile(at, Vector2i(3, 5)) != "", "not right next to him")
	at.aim = 200
	hidden.hp = 100
	battle.map.set_edge(Vector2i(8, 5), Vector2i(9, 5), Cover.FULL, "wall")
	var events := battle.execute({"cmd": "fire_at", "unit": at.id, "tile": Vector2i(9, 5)})
	check_eq(events_of(events, "ground_shot").size(), 1, "it fires")
	check(events_of(events, "ground_shot")[0]["hit"], "and with that aim lands on target")
	check(hidden.hp <= 100 - at.weapon.damage_min, "whoever is there takes the warhead")
	check(battle.map.edge_damage(TacticalMap.edge_key(Vector2i(8, 5), Vector2i(9, 5))) >= 2, "and the wall beside him is breached")
	check_eq(at.ammo, 0, "it uses the round")


func test_machine_gun_rakes_a_tile_and_breaks_walls() -> void:
	var battle := make_battle([["MG", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(9, 6)], ["Rifleman", 1, Vector2i(15, 15)], ["Rifleman", 0, Vector2i(0, 15)]])
	var mg := battle.units[0]
	var near := battle.units[1]
	var key := TacticalMap.edge_key(Vector2i(8, 5), Vector2i(9, 5))
	battle.map.set_edge(Vector2i(8, 5), Vector2i(9, 5), Cover.FULL, "wall")
	check_eq(battle.can_suppress_tile(mg, Vector2i(9, 5)), "", "a machine gun can rake an empty tile")
	var events := battle.execute({"cmd": "suppress_area", "unit": mg.id, "tile": Vector2i(9, 5)})
	check_eq(events_of(events, "area_fire").size(), 1, "it fires")
	check(near.suppression >= mg.weapon.suppression, "an enemy beside the tile is shaken")
	check_eq(battle.map.edge_damage(key), 1, "the wall facing the gun takes a stage")
	for i in 2:
		mg.actions = Unit.ACTIONS_PER_TURN
		mg.ammo = mg.weapon.clip_size
		battle.execute({"cmd": "suppress_area", "unit": mg.id, "tile": Vector2i(9, 5)})
	check(not battle.map.get_edges().has(key), "three bursts bring a brick wall down")
	var rifle := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	check(rifle.can_suppress_tile(rifle.units[0], Vector2i(9, 5)) != "", "a rifleman can't")


func test_blasts_blow_in_windows_nearby() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(1, 1)], ["Rifleman", 1, Vector2i(14, 14)]])
	var map := battle.map
	map.set_edge(Vector2i(8, 6), Vector2i(8, 7), Cover.HALF, "window")
	map.set_edge(Vector2i(12, 6), Vector2i(12, 7), Cover.HALF, "window")
	var near := TacticalMap.edge_key(Vector2i(8, 6), Vector2i(8, 7))
	var far := TacticalMap.edge_key(Vector2i(12, 6), Vector2i(12, 7))
	var events := battle._explode(null, Vector2i(6, 6), 1.0, 0, 0, 0)
	check_eq(map.edge_kind(near), "broken_window", "a window a couple of tiles from the blast loses its glass")
	check_eq(map.get_edge(Vector2i(8, 6), Vector2i(8, 7)), Cover.HALF, "the frame is still half cover")
	check_eq(map.edge_kind(far), "window", "one further off is spared")
	check_eq(events_of(events, "explosion")[0].get("windows", []).size(), 1, "the explosion lists the window it blew in")


func test_broken_walls_and_collapses_spill_rubble() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(1, 1)], ["Rifleman", 1, Vector2i(14, 14)]])
	var map := battle.map
	map.set_edge(Vector2i(8, 8), Vector2i(9, 8), Cover.FULL, "wall")
	var events := battle._explode(null, Vector2i(8, 8), 0.5, 0, 0, 0, null, CombatRules.EXPLOSION_VS_ARMOR, 0, CombatRules.WALL_HITS["shell"])
	check_eq(map.get_terrain(Vector2i(9, 8)), TacticalMap.Terrain.RUBBLE, "the wall spills rubble on the side away from the blast")
	check_eq(events_of(events, "dust")[0].get("rubble", []), [Vector2i(9, 8)], "and the dust event says where")
	check_eq(map.cover_toward(Vector2i(9, 8), Vector2i(0, -1)), Cover.HALF, "rubble is half cover on every side")
	var tiles: Array[Vector2i] = []
	for y in range(3, 5):
		for x in range(3, 5):
			tiles.append(Vector2i(x, y))
			map.set_terrain(Vector2i(x, y), TacticalMap.Terrain.INDOOR)
	var collapse := battle._collapse(tiles)
	var spilled: Array = events_of(collapse, "dust")[0]["rubble"]
	check(not spilled.is_empty(), "a collapse spills rubble round the ruins (%d tiles)" % spilled.size())
	for p: Vector2i in spilled:
		check(not tiles.has(p) and map.get_terrain(p) == TacticalMap.Terrain.RUBBLE, "onto the ground outside it")


func test_shells_burst_in_trees_and_bring_them_down() -> void:
	var battle := make_battle([["Mortar", 0, Vector2i(1, 1)], ["Rifleman", 1, Vector2i(14, 14)], ["Rifleman", 1, Vector2i(9, 3)]])
	var map := battle.map
	map.set_object(Vector2i(9, 9), Cover.FULL, "tree")
	check(battle.tree_burst_at(Vector2i(9, 8)), "a shell beside a tree bursts in its branches")
	check(not battle.tree_burst_at(Vector2i(4, 4)), "not out in the open")
	var events := battle._land_strike({"unit": battle.units[0].id, "target": Vector2i(9, 8), "scatter": 0.0, "kind": "he"})
	var blast: Dictionary = events_of(events, "explosion")[0]
	check(blast.get("tree_burst", false), "the strike is a tree burst")
	check_eq(blast["radius"], battle.units[0].indirect["radius"] + CombatRules.TREE_BURST_RADIUS, "and reaches further")
	var logs := 0
	var shattered := 0
	for seed in 8:
		var units: Array[Unit] = [Unit.create(0, "U0", "Rifleman", 0, Vector2i(1, 1)), Unit.create(1, "U1", "Rifleman", 1, Vector2i(14, 14))]
		var b := Battle.new(TacticalMap.new(16, 16), units, seed)
		b.start()
		for y in range(6, 11):
			for x in range(6, 11):
				b.map.set_object(Vector2i(x, y), Cover.FULL, "tree")
		b._explode(null, Vector2i(8, 8), 1.5, 0, 0, 0)
		check_eq(b.map.get_object(Vector2i(8, 8)), Cover.NONE, "the tree it lands on is shattered")
		for p in b.map.tiles_in_radius(Vector2i(8, 8), 1.5):
			if b.map.get_object_kind(p) == "log":
				logs += 1
				check_eq(b.map.get_object(p), Cover.HALF, "a fallen trunk is half cover")
			elif b.map.get_terrain(p) == TacticalMap.Terrain.ROUGH and b.map.get_object(p) == Cover.NONE:
				shattered += 1
	check(logs > 10 and shattered > 10, "trees come down as trunks or splintered scrub (%d trunks, %d splintered)" % [logs, shattered])


func test_rocket_backblast() -> void:
	var battle := make_battle([["AT", 0, Vector2i(5, 5)], ["Rifleman", 0, Vector2i(4, 5)], ["Rifleman", 1, Vector2i(11, 5)], ["Rifleman", 0, Vector2i(0, 15)]])
	var at := battle.units[0]
	var mate := battle.units[1]
	check_eq(battle.backblast_tile(at, Vector2i(11, 5)), Vector2i(4, 5), "the backblast goes straight back")
	var hp := mate.hp
	var events := battle.execute({"cmd": "fire_at", "unit": at.id, "tile": Vector2i(11, 7)})
	check_eq(events_of(events, "backblast").size(), 1, "firing a rocket throws a backblast")
	check(mate.hp < hp and mate.suppression >= CombatRules.BACKBLAST_SUPPRESSION, "and burns and shakes a friend standing behind")
	var walled := make_battle([["AT", 0, Vector2i(5, 5)], ["Rifleman", 1, Vector2i(11, 5)], ["Rifleman", 0, Vector2i(0, 15)]])
	walled.map.set_edge(Vector2i(4, 5), Vector2i(5, 5), Cover.FULL, "wall")
	var bounce := walled.execute({"cmd": "fire_at", "unit": walled.units[0].id, "tile": Vector2i(11, 7)})
	check(events_of(bounce, "backblast")[0].get("bounced", false), "a wall right behind throws it back")
	check(walled.units[0].suppression >= CombatRules.BACKBLAST_BOUNCE_SUPPRESSION, "and shakes the gunner")
	var fires := 0
	for seed in 10:
		var units: Array[Unit] = [Unit.create(0, "U0", "AT", 0, Vector2i(5, 5)), Unit.create(1, "U1", "Rifleman", 1, Vector2i(11, 5)), Unit.create(2, "U2", "Rifleman", 0, Vector2i(0, 15))]
		var b := Battle.new(TacticalMap.new(16, 16), units, seed)
		b.start()
		b.map.set_terrain(Vector2i(4, 5), TacticalMap.Terrain.WHEAT)
		b.execute({"cmd": "fire_at", "unit": units[0].id, "tile": Vector2i(11, 7)})
		if b.map.has_fire(Vector2i(4, 5)):
			fires += 1
	check(fires >= 2 and fires <= 8, "in dry wheat the backblast sometimes starts a fire (%d of 10)" % fires)
	var rifle := make_battle([["Rifleman", 0, Vector2i(5, 5)], ["Rifleman", 1, Vector2i(11, 5)]])
	check(events_of(rifle.execute({"cmd": "shoot", "unit": rifle.units[0].id, "target": rifle.units[1].id}), "backblast").is_empty(), "a rifle has none")


func test_hold_ends_a_soldiers_turn() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 0, Vector2i(2, 4)], ["Rifleman", 1, Vector2i(13, 13)]])
	var a := battle.units[0]
	var b := battle.units[1]
	var events := battle.execute({"cmd": "hold", "unit": a.id})
	check(not events.is_empty(), "a soldier with actions left can hold")
	check_eq(a.actions, 0, "holding spends his actions")
	check_eq(a.pos, Vector2i(2, 2), "and he stays put")
	check_eq(battle.current_team, 0, "the turn goes on while others can act")
	check(battle.execute({"cmd": "hold", "unit": a.id}).is_empty(), "he can't hold twice")
	check(battle.execute({"cmd": "hold", "unit": battle.units[2].id}).is_empty(), "nor hold for the enemy")
	battle.execute({"cmd": "move", "unit": b.id, "tile": Vector2i(3, 4)})
	battle.execute({"cmd": "hold", "unit": b.id})
	check_eq(battle.current_team, 1, "the last soldier to hold ends the turn")


func test_shooting_ends_turn_and_suppresses() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 0, Vector2i(0, 2)], ["Rifleman", 1, Vector2i(5, 0)]])
	var u := battle.units[0]
	var target := battle.units[2]
	target.hp = 100
	var events := battle.shoot(u, target)
	check_eq(u.actions, 0, "shooting ends the unit's turn")
	check_eq(u.ammo, u.weapon.clip_size - 1, "shot used ammo")
	check(target.suppression >= u.weapon.suppression, "every shot suppresses, hit or miss")
	check_eq(events_of(events, "suppression").size(), 1, "suppression event")


func test_wounds_slow_units_for_two_turns() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 1, Vector2i(15, 15)]])
	var u := battle.units[0]
	battle._damage(u, 2, 0)
	check(u.is_wounded(), "hit units are wounded")
	check_eq(u.current_mobility(), u.mobility - Unit.WOUND_MOBILITY_PENALTY, "wounds cost mobility")
	battle.end_turn()
	battle.end_turn()
	check(u.is_wounded(), "still wounded for the second turn")
	battle.end_turn()
	battle.end_turn()
	check(not u.is_wounded(), "wound wears off after two turns")


func test_pinned_units_cannot_move_and_recover() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(5, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	var u := battle.units[0]
	u.suppression = 80
	check(u.is_pinned(), "80 suppression pins")
	check(battle.move(u, Vector2i(6, 5)).is_empty(), "pinned units can't move")
	check(battle.reachable(u).is_empty(), "no move range while pinned")
	battle.end_turn()
	battle.end_turn()
	check_eq(u.suppression, 80 - CombatRules.SUPPRESSION_RECOVERY, "suppression wears off each turn")


func test_officer_rallies_and_steadies() -> void:
	var battle := make_battle([["Officer", 0, Vector2i(5, 5)], ["Rifleman", 0, Vector2i(6, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	var rifleman := battle.units[1]
	rifleman.suppression = 90
	battle.rally(battle.units[0])
	check_eq(rifleman.suppression, 90 - CombatRules.RALLY_AMOUNT, "rally removes suppression")
	battle.end_turn()
	battle.end_turn()
	check_eq(rifleman.suppression, maxi(0, 40 - CombatRules.SUPPRESSION_RECOVERY - CombatRules.OFFICER_RECOVERY_BONUS), "officer nearby speeds recovery")


func test_officer_death_shakes_the_squad() -> void:
	var battle := make_battle([["Officer", 0, Vector2i(5, 5)], ["Rifleman", 0, Vector2i(15, 0)], ["Rifleman", 1, Vector2i(15, 15)]])
	battle._damage(battle.units[0], 50, 0)
	check(battle.units[1].suppression >= CombatRules.OFFICER_DEATH_SUPPRESSION, "squad is shaken")


func test_machine_gun_fires_best_set_up_and_suppresses_an_area() -> void:
	var battle := make_battle([["MG", 0, Vector2i(2, 5)], ["Rifleman", 0, Vector2i(0, 15)], ["Rifleman", 1, Vector2i(9, 5)], ["Rifleman", 1, Vector2i(9, 6)]])
	var mg := battle.units[0]
	check(mg.weapon.heavy and not mg.weapon.fires_standing_still(), "a heavy machine gun can fire after moving")
	check(battle.can_shoot(mg, battle.units[2]) == "", "standing still, it fires at once")
	battle.units[2].hp = 100
	battle.shoot(mg, battle.units[2])
	check(battle.units[3].suppression >= mg.weapon.suppression / 2, "neighbours are suppressed too")
	battle.end_turn()
	battle.end_turn()
	battle.move(mg, Vector2i(3, 5))
	check_eq(battle.can_shoot(mg, battle.units[2]), "", "after moving it can still fire")
	check(battle.shot_odds(mg, battle.units[2])["modifiers"].any(func(m: Array) -> bool: return m[0] == "Fired on the move"), "but off the hip")
	check(battle.can_suppress(mg, battle.units[2]) != "", "and lays no suppressive fire")


func test_blasts_set_crops_alight() -> void:
	var lit := 0
	var under_soldier := 0
	for seed in 12:
		var units: Array[Unit] = [Unit.create(0, "U0", "Rifleman", 0, Vector2i(2, 8)), Unit.create(1, "U1", "Rifleman", 1, Vector2i(8, 8)), Unit.create(2, "U2", "Rifleman", 1, Vector2i(15, 15))]
		var battle := Battle.new(TacticalMap.new(16, 16), units, seed)
		battle.start()
		for y in 16:
			for x in 16:
				battle.map.set_terrain(Vector2i(x, y), TacticalMap.Terrain.WHEAT)
		units[1].hp = 100
		battle.throw_grenade(units[0], Vector2i(7, 8))
		for p: Vector2i in battle.map.get_fires():
			lit += 1
			check(battle.map.get_terrain(p) in [TacticalMap.Terrain.ROUGH, TacticalMap.Terrain.CRATER], "the wheat burns away (or the crater burns)")
		if battle.map.has_fire(units[1].pos):
			under_soldier += 1
	check(lit > 12, "grenades in a wheat field start fires (%d tiles)" % lit)
	check(under_soldier < 12, "less often under a soldier (%d of 12)" % under_soldier)


func test_fire_spreads_through_dry_crops_not_roads() -> void:
	var units: Array[Unit] = [Unit.create(0, "U0", "Rifleman", 0, Vector2i(0, 0)), Unit.create(1, "U1", "Rifleman", 1, Vector2i(15, 0))]
	var battle := Battle.new(TacticalMap.new(16, 16), units, 7)
	battle.start()
	for y in range(4, 12):
		for x in 16:
			battle.map.set_terrain(Vector2i(x, y), TacticalMap.Terrain.WHEAT if x < 8 else TacticalMap.Terrain.ROAD)
	battle.map.add_fire(Vector2i(7, 8), 1000)
	battle.map.add_fire(Vector2i(8, 8), 1000)
	for i in 16:
		battle.end_turn()
	for p: Vector2i in battle.map.get_fires():
		check(p.x < 8 or p == Vector2i(8, 8), "nothing burns on the road")
	var burnt := 0
	for y in range(4, 12):
		for x in 8:
			if battle.map.get_terrain(Vector2i(x, y)) == TacticalMap.Terrain.ROUGH:
				burnt += 1
	check(burnt > 4, "it spreads through the wheat (%d tiles burnt)" % burnt)
	check(burnt < 64, "but not all of it at once")


func test_walls_come_down_in_stages() -> void:
	var map := TacticalMap.new(8, 8)
	map.set_edge(Vector2i(3, 3), Vector2i(4, 3), Cover.FULL, "wall")
	var key := TacticalMap.edge_key(Vector2i(3, 3), Vector2i(4, 3))
	check(map.damage_edge(key, 1), "a hit damages it")
	check_eq(map.get_edge(Vector2i(3, 3), Vector2i(4, 3)), Cover.FULL, "damaged: still full cover")
	map.damage_edge(key, 1)
	check_eq(map.get_edge(Vector2i(3, 3), Vector2i(4, 3)), Cover.HALF, "breached: half cover")
	check_eq(map.get_edge_kind(Vector2i(3, 3), Vector2i(4, 3)), "wall", "still a wall")
	map.damage_edge(key, 1)
	check_eq(map.get_edge(Vector2i(3, 3), Vector2i(4, 3)), Cover.NONE, "then gone")
	check_eq(map.edge_damage(key), 3, "and remembered as gone")
	map.set_edge(Vector2i(5, 5), Vector2i(5, 6), Cover.FULL, "wall")
	var chipped := TacticalMap.edge_key(Vector2i(5, 5), Vector2i(5, 6))
	map.damage_edge(chipped, 1, 1)
	check(not map.damage_edge(chipped, 1, 1), "a machine gun only chips a stone wall")
	map.set_edge(Vector2i(1, 1), Vector2i(2, 1), Cover.HALF, "window")
	map.damage_edge(TacticalMap.edge_key(Vector2i(1, 1), Vector2i(2, 1)), 1)
	check_eq(map.get_edge_kind(Vector2i(1, 1), Vector2i(2, 1)), "broken_window", "a hit window loses its glass")
	var copy := TacticalMap.from_dict(map.to_dict())
	check_eq(copy.edge_damage(chipped), 1, "damage is saved")


func test_hedges_are_shot_apart_quickly() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(8, 5)]])
	var map := battle.map
	var key := TacticalMap.edge_key(Vector2i(7, 5), Vector2i(8, 5))
	var rifle := battle.units[0]
	var them := battle.units[1]
	map.set_edge(Vector2i(7, 5), Vector2i(8, 5), Cover.FULL, "hedge")
	check_eq(events_of(battle._hit_cover(rifle, them), "wall_hit").size(), 1, "a rifle shot tears into a hedge")
	check_eq(map.edge_damage(key), 1, "a stage at a time")
	battle._hit_cover(rifle, them)
	check_eq(map.get_edge(Vector2i(7, 5), Vector2i(8, 5)), Cover.HALF, "two shots breach it")
	battle._hit_cover(rifle, them)
	check_eq(map.get_edge(Vector2i(7, 5), Vector2i(8, 5)), Cover.NONE, "three and it's gone")
	map.set_edge(Vector2i(7, 5), Vector2i(8, 5), Cover.FULL, "wall")
	check(battle._hit_cover(rifle, them).is_empty(), "rifles leave walls standing")
	var mg := Unit.create(9, "MG", "MG", 0, Vector2i(2, 5))
	map.set_edge(Vector2i(7, 5), Vector2i(8, 5), Cover.FULL, "hedge")
	battle._hit_cover(mg, them)
	check_eq(map.get_edge(Vector2i(7, 5), Vector2i(8, 5)), Cover.HALF, "a machine gun burst breaches a hedge")
	battle._hit_cover(mg, them)
	check_eq(map.get_edge(Vector2i(7, 5), Vector2i(8, 5)), Cover.NONE, "and the next clears it")
	var tank := Unit.create(10, "Tank", "Tank", 0, Vector2i(2, 5))
	map.set_edge(Vector2i(7, 5), Vector2i(8, 5), Cover.FULL, "hedge")
	battle._hit_cover(tank, them)
	check_eq(map.get_edge(Vector2i(7, 5), Vector2i(8, 5)), Cover.NONE, "a shell blows it away")
	map.set_edge(Vector2i(7, 5), Vector2i(8, 5), Cover.FULL, "hedge")
	map.blast_cover(Vector2i(9, 5), 1.5, 2, 1)
	check_eq(map.get_edge(Vector2i(7, 5), Vector2i(8, 5)), Cover.HALF, "a blast nearby breaches it")


func test_tank_shell_breaches_the_wall_in_front() -> void:
	var battle := make_battle([["Tank", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(8, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	battle.map.set_edge(Vector2i(7, 5), Vector2i(8, 5), Cover.FULL, "wall")
	battle.map.set_edge(Vector2i(7, 4), Vector2i(8, 4), Cover.FULL, "wall")
	battle.units[1].hp = 100
	var tank := battle.units[0]
	battle.units[1].stance = Unit.Stance.STAND
	var events := battle._hit_cover(tank, battle.units[1])
	check_eq(events_of(events, "wall_hit").size(), 1, "the shell hits the wall in front of him")
	check_eq(battle.map.get_edge(Vector2i(7, 5), Vector2i(8, 5)), Cover.HALF, "and breaches it")
	check_eq(battle.map.edge_damage(TacticalMap.edge_key(Vector2i(7, 4), Vector2i(8, 4))), 0, "the wall beside it stands")
	var mg := Unit.create(9, "MG", "MG", 0, Vector2i(2, 5))
	battle.map.set_edge(Vector2i(7, 5), Vector2i(8, 5), Cover.FULL, "wall")
	battle._hit_cover(mg, battle.units[1])
	battle._hit_cover(mg, battle.units[1])
	check_eq(battle.map.get_edge(Vector2i(7, 5), Vector2i(8, 5)), Cover.FULL, "a machine gun only chips it")
	battle.map.set_edge(Vector2i(7, 5), Vector2i(8, 5), Cover.HALF, "fence")
	battle._hit_cover(mg, battle.units[1])
	battle._hit_cover(mg, battle.units[1])
	check_eq(battle.map.get_edge(Vector2i(7, 5), Vector2i(8, 5)), Cover.NONE, "but shoots a fence apart")


func test_a_building_collapses_when_enough_walls_are_down() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 1, Vector2i(6, 6)], ["Rifleman", 1, Vector2i(15, 15)]])
	var map := battle.map
	var rect := Rect2i(5, 5, 3, 3)
	for y in range(5, 8):
		for x in range(5, 8):
			map.set_terrain(Vector2i(x, y), TacticalMap.Terrain.INDOOR)
			map.set_storeys(Vector2i(x, y), 2)
	map.set_stairs(Vector2i(5, 5), true)
	var walls: Array[Vector3i] = []
	for y in range(5, 8):
		for x in range(5, 8):
			for d: Vector2i in TacticalMap.DIRS4:
				if not rect.has_point(Vector2i(x, y) + d):
					map.set_edge(Vector2i(x, y), Vector2i(x, y) + d, Cover.FULL, "wall")
					walls.append(TacticalMap.edge_key(Vector2i(x, y), Vector2i(x, y) + d))
	var upstairs := battle.units[1]
	upstairs.level = 2
	upstairs.hp = 100
	# Breach four of the twelve walls: it still stands (two storeys come down at 40%).
	for i in 4:
		map.damage_edge(walls[i], 2)
	var events := battle._collapse_weakened({})
	check(events_of(events, "collapse").is_empty(), "four of twelve walls down: it stands")
	var before := map.get_edge_damage().duplicate()
	map.damage_edge(walls[4], 2)
	events = battle._collapse_weakened(before)
	check_eq(events_of(events, "collapse").size(), 1, "five of twelve: it comes down")
	check_eq(map.get_storeys(Vector2i(6, 6)), 0, "no floors left")
	check_eq(map.get_terrain(Vector2i(6, 6)), TacticalMap.Terrain.RUBBLE, "a heap of rubble")
	check_eq(upstairs.level, 0, "the soldier on the roof falls")
	check(upstairs.hp <= 100 - CombatRules.COLLAPSE_DAMAGE[0] - 2 * CombatRules.COLLAPSE_FALL_DAMAGE, "and is hurt by the fall")


func test_climbing_through_a_window_smashes_it() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(4, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	for y in 16:
		battle.map.set_edge(Vector2i(5, y), Vector2i(6, y), Cover.FULL, "wall")
	battle.map.set_edge(Vector2i(5, 5), Vector2i(6, 5), Cover.HALF, "window")
	var events := battle.move(battle.units[0], Vector2i(7, 5))
	check_eq(battle.units[0].pos, Vector2i(7, 5), "he climbs through the window")
	check_eq(battle.map.get_edge_kind(Vector2i(5, 5), Vector2i(6, 5)), "broken_window", "and the glass is gone")
	check_eq(battle.map.get_edge(Vector2i(5, 5), Vector2i(6, 5)), Cover.HALF, "still half cover")
	check_eq(events_of(events, "window_broken").size(), 1, "one window smashed")
	battle.end_turn()
	battle.end_turn()
	battle.move(battle.units[0], Vector2i(4, 5))
	check_eq(battle.map.get_edge_kind(Vector2i(5, 5), Vector2i(6, 5)), "broken_window", "a broken window stays broken")


func test_sniper_moves_or_fires_not_both() -> void:
	var battle := make_battle([["Sniper", 0, Vector2i(2, 5)], ["Rifleman", 0, Vector2i(0, 15)], ["Rifleman", 1, Vector2i(10, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	var sniper := battle.units[0]
	var target := battle.units[2]
	target.hp = 100
	battle.move(sniper, Vector2i(3, 5))
	check(sniper.moved and sniper.actions > 0, "moved one step, an action left")
	check(battle.can_shoot(sniper, target) != "", "a sniper can't fire after moving")
	check(battle.can_overwatch(sniper) != "", "nor go on overwatch")
	battle.end_turn()
	battle.end_turn()
	check(not sniper.moved, "a new turn clears it")
	check(battle.can_shoot(sniper, target) == "", "standing still, he can fire")
	battle.shoot(sniper, target)
	check(battle.can_move(sniper, Vector2i(3, 6)) != "", "and can't move after firing")
	check(sniper.ammo == 0, "one round, then a reload")
	battle.end_turn()
	battle.end_turn()
	check(battle.can_shoot(sniper, target) != "", "empty after every shot")
	battle.reload(sniper)
	check(sniper.ammo == 1 and sniper.actions == 1, "a reload takes one action")
	check(battle.can_shoot(sniper, target) != "", "and he can't fire with the one left")
	check(battle.can_overwatch(sniper) != "", "nor go on overwatch")
	check(battle.can_suppress(sniper, target) != "", "snipers don't lay down suppressive fire")
	battle.end_turn()
	battle.end_turn()
	check(battle.can_shoot(sniper, target) == "", "loaded, with both actions, he fires next turn")
	var rifleman := battle.units[1]
	battle.move(rifleman, Vector2i(1, 15))
	check(battle.can_shoot(rifleman, target) == "" or not battle.can_see(rifleman, target), "other soldiers still move and fire")


func test_reaction_fire_can_pin_a_runner() -> void:
	var battle := make_battle([["MG", 0, Vector2i(0, 8)], ["Rifleman", 1, Vector2i(10, 8)], ["Rifleman", 1, Vector2i(15, 15)]])
	var mg := battle.units[0]
	battle.overwatch(mg)
	var runner := battle.units[1]
	runner.hp = 100
	runner.suppression = 40
	var events := battle.move(runner, Vector2i(6, 8))
	check_eq(events_of(events, "shot").size(), 1, "one overwatch burst")
	check(runner.is_pinned(), "the burst pins the runner")
	check(runner.pos != Vector2i(6, 8), "and stops the move short")


# --- Explosives ---

func test_grenade_destroys_cover_and_leaves_a_crater() -> void:
	# Thrown from two tiles away: too close to land off target.
	var battle := make_battle([["Rifleman", 0, Vector2i(5, 5)], ["Rifleman", 1, Vector2i(7, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	battle.map.set_object(Vector2i(6, 5), Cover.HALF)
	battle.map.set_edge(Vector2i(7, 5), Vector2i(7, 6), Cover.FULL)
	var target := battle.units[1]
	target.armor = 1
	var events := battle.throw_grenade(battle.units[0], Vector2i(7, 5))
	check_eq(events[0]["type"], "throw", "throw event")
	check_eq(events[0]["center"], Vector2i(7, 5), "a short throw lands on target")
	check_eq(events[1]["type"], "explosion", "explosion event")
	check_eq(battle.map.get_object(Vector2i(6, 5)), Cover.NONE, "crate destroyed")
	var wall := TacticalMap.edge_key(Vector2i(7, 5), Vector2i(7, 6))
	check_eq(battle.map.edge_damage(wall), 1, "a grenade damages the wall a stage")
	check_eq(battle.map.get_edge(Vector2i(7, 5), Vector2i(7, 6)), Cover.FULL, "still full cover")
	check_eq(battle.map.get_terrain(Vector2i(7, 5)), TacticalMap.Terrain.CRATER, "crater at the centre")
	check_eq(target.armor, 0, "armor shredded")
	var suppressed := events_of(events, "suppression").filter(func(e: Dictionary) -> bool: return e["unit"] == target.id and e["value"] >= CombatRules.EXPLOSION_SUPPRESSION)
	check(not suppressed.is_empty() or not target.is_alive(), "blast suppresses")


func test_mortar_fires_blind_and_lands_next_turn() -> void:
	var battle := make_battle([["Mortar", 0, Vector2i(0, 8)], ["Rifleman", 0, Vector2i(10, 8)], ["Rifleman", 1, Vector2i(15, 8)], ["Rifleman", 1, Vector2i(15, 0)]], Vector2i(24, 16))
	var mortar := battle.units[0]
	check(battle.can_fire_mortar(mortar, Vector2i(2, 8), "he") != "", "minimum range")
	check(battle.can_fire_mortar(mortar, Vector2i(15, 8), "he") == "", "spotted target in range")
	var observed := battle.firing_scatter(mortar, Vector2i(15, 8))
	check(is_equal_approx(observed, Battle.mortar_scatter(mortar.pos, Vector2i(15, 8), mortar.indirect) * Battle.IMMEDIATE_SCATTER), "fire that lands at once scatters twice as far")
	for y in battle.map.height:
		battle.map.set_edge(Vector2i(11, y), Vector2i(12, y), Cover.FULL)
	check(not battle.is_spotted(0, Vector2i(15, 8)), "nobody can see behind the wall")
	check(battle.can_fire_mortar(mortar, Vector2i(15, 8), "he") == "", "indirect fire at an unseen tile")
	check(is_equal_approx(battle.firing_scatter(mortar, Vector2i(15, 8)), observed * Battle.BLIND_SCATTER), "unobserved fire scatters further")
	check(battle.can_fire_mortar(mortar, Vector2i(23, 8), "he") != "", "still out of range")
	for y in battle.map.height:
		battle.map.set_edge(Vector2i(11, y), Vector2i(12, y), Cover.NONE)
	var moved := make_battle([["Mortar", 0, Vector2i(0, 8)], ["Rifleman", 0, Vector2i(0, 9)], ["Rifleman", 1, Vector2i(15, 8)]], Vector2i(24, 16))
	moved.move(moved.units[0], Vector2i(1, 8))
	check(moved.can_fire_mortar(moved.units[0], Vector2i(15, 8), "he") != "", "can't fire after moving")

	var events := battle.fire_mortar(mortar, Vector2i(15, 8), "he")
	check_eq(events[0]["type"], "mortar_fire", "shell fired")
	check(events[0].get("observed", false), "at a target a soldier of ours can see")
	check(battle.strikes.is_empty(), "observed fire isn't left in the air")
	var strikes := events_of(events, "strike")
	check_eq(strikes.size(), 1, "it comes down at once")
	if not strikes.is_empty():
		var center: Vector2i = strikes[0]["center"]
		check(Vector2(center).distance_to(Vector2(15, 8)) <= battle.firing_scatter(battle.units[0], Vector2i(15, 8)) + 1.0, "within scatter")


# --- Objectives and the flow of battle ---

func test_objectives_score_points_and_win() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(5, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	battle.objectives = [{"name": "Hill", "center": Vector2(5.5, 5.5), "radius": 1.5, "owner": -1}]
	battle.vp_to_win = 2
	var events := battle.overwatch(battle.units[0])
	check_eq(events_of(events, "objective").size(), 1, "taking an objective")
	check_eq(battle.objectives[0]["owner"], 0, "allies hold the hill")
	battle.end_turn()
	check_eq(battle.victory_points, [1, 0], "a point for the round")
	battle.end_turn()
	events = battle.end_turn()
	check_eq(battle.winner, 0, "enough points wins")
	check_eq(events_of(events, "game_over").size(), 1, "game over")


func test_round_limit_ends_the_battle() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(5, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	battle.objectives = [{"name": "Hill", "center": Vector2(10.5, 10.5), "radius": 1.0, "owner": -1}]
	battle.max_rounds = 2
	for i in 4:
		battle.end_turn()
	check_eq(battle.winner, Battle.DRAW, "level on points after the last round is a draw")


func test_reinforcements_arrive() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(5, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	var wave: Array[Unit] = [Unit.create(10, "New", "Rifleman", 0, Vector2i(5, 5))]
	battle.reinforcements.append({"round": 2, "team": 0, "units": wave})
	battle.end_turn()
	var events := battle.end_turn()
	check_eq(events_of(events, "reinforcements").size(), 1, "reinforcements event")
	check_eq(battle.alive_units(0).size(), 2, "they join the battle")
	check(wave[0].pos != Vector2i(5, 5), "on a free tile")
	check_eq(wave[0].actions, 2, "ready to act")


func test_auto_end_turn_and_status_reset() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 1, Vector2i(15, 15)]])
	var red := battle.units[1]
	red.overwatch = true
	battle.overwatch(battle.units[0])
	check_eq(battle.current_team, 1, "turn ends when nobody can act")
	check(not red.overwatch, "overwatch clears at the start of the owner's turn")
	check(battle.units[0].overwatch, "the other side keeps theirs")


func test_medkit_heals_and_treats_wounds() -> void:
	var battle := make_battle([["Medic", 0, Vector2i(0, 0)], ["Rifleman", 0, Vector2i(1, 1)], ["Rifleman", 1, Vector2i(15, 15)]])
	var patient := battle.units[1]
	check(battle.can_use_medkit(battle.units[0], patient) != "", "can't treat a healthy unit")
	battle._damage(patient, 5, 0)
	battle.use_medkit(battle.units[0], patient)
	check_eq(patient.hp, mini(patient.max_hp, 2 + CombatRules.MEDKIT_HEAL), "healed")
	check(not patient.is_wounded(), "wound treated")


func test_victory_by_elimination() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 1, Vector2i(1, 0)]])
	battle.units[1].hp = 1
	var events := []
	for i in 50:
		if battle.winner != -1:
			break
		if battle.current_team == 1:
			battle.end_turn()
		else:
			events = battle.shoot(battle.units[0], battle.units[1])
	check_eq(battle.winner, 0, "allies win")
	check_eq(events.back()["type"], "game_over", "game over event")


func test_seeded_battles_are_deterministic() -> void:
	var outcomes := []
	for i in 2:
		var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 0, Vector2i(0, 1)], ["Rifleman", 1, Vector2i(9, 0)]])
		battle.units[2].hp = 100
		var results := []
		for j in 4:
			var e := battle.shoot(battle.units[j % 2], battle.units[2])
			results.append(e[0]["result"] if not e.is_empty() else "-")
			if battle.current_team == 1:
				battle.end_turn()
		outcomes.append(results)
	check_eq(outcomes[0], outcomes[1], "same seed, same results")


# --- View maths ---

func test_projection_round_trips() -> void:
	var proj := ViewProjection.new(Vector2(24, 20))
	for iso in [true, false]:
		proj.isometric = iso
		for rotation in 4:
			proj.rotation = rotation
			for g: Vector2 in [Vector2(0.5, 0.5), Vector2(3.25, 17.75), Vector2(23.5, 0.1)]:
				var back := proj.unproject(proj.project(g))
				check(back.distance_to(g) < 0.001, "round trip iso=%s rotation=%d %s -> %s" % [iso, rotation, g, back])


# --- AI ---

func test_ai_takes_the_kill() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(5, 2)], ["Rifleman", 1, Vector2i(15, 15)]])
	battle.units[1].hp = 1
	var ai := TacticalAI.new(battle, 0)
	var shots := []
	while battle.current_team == 0 and battle.winner == -1:
		shots.append_array(events_of(ai.act(), "shot"))
	check_eq(shots.size(), 1, "AI shoots during its turn")
	check_eq(shots[0].get("target") if not shots.is_empty() else null, 1, "at the wounded enemy")


func test_ai_does_not_see_through_fog() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(1, 1)], ["Rifleman", 1, Vector2i(14, 14)]])
	for x in 16:
		battle.map.set_edge(Vector2i(x, 7), Vector2i(x, 8), Cover.FULL)
	var ai := TacticalAI.new(battle, 0)
	ai.act()
	check(ai._seen_enemies().is_empty(), "enemy behind the wall is unseen")
	check(ai._last_seen.is_empty(), "and not remembered")


func test_ai_machine_gun_fires_from_where_it_stands() -> void:
	var battle := make_battle([["MG", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(10, 5)]])
	var ai := TacticalAI.new(battle, 0)
	var events := []
	while battle.current_team == 0 and battle.winner == -1:
		events.append_array(ai.act())
	check(not events_of(events, "shot").is_empty(), "the MG opens fire")
	check(events_of(events, "move").is_empty(), "from where it stands")


func test_ai_battle_finishes() -> void:
	var battle := NormandyScenario.build(7)
	battle.max_rounds = 6
	var ais := [TacticalAI.new(battle, 0), TacticalAI.new(battle, 1)]
	battle.start()
	var steps := 0
	while battle.winner == -1 and steps < 2000:
		ais[battle.current_team].act()
		steps += 1
	check(battle.winner != -1, "AI vs AI on the Normandy map reaches a result (steps %d, round %d)" % [steps, battle.round_number])


func test_ai_picks_a_game_plan() -> void:
	var picked := {}
	for seed in range(1, 25):
		var battle: Battle = GameSession.build_skirmish({"map": "village", "seed": seed})[0]
		var ai := TacticalAI.new(battle, 0)
		picked[ai.strategy] = true
		check_eq(TacticalAI.new(battle, 0).strategy, ai.strategy, "seed %d: the same plan every time" % seed)
		check(TacticalAI.STRATEGIES.has(ai.strategy), "a known plan")
		check(not ai.plan_summary().is_empty(), "with a description for the log")
	check(picked.size() >= 5, "plans vary from battle to battle (%s)" % [picked.keys()])
	var tankless := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(13, 13)]])
	for seed in range(1, 40):
		tankless.rng.seed = seed
		check(TacticalAI.new(tankless, 0).strategy not in ["armoured_spearhead", "hold_two"], "no tank plan without tanks, no pair without objectives")


func test_ai_plan_chosen_on_the_menu() -> void:
	var battle: Battle = GameSession.build_skirmish({"map": "village", "seed": 3})[0]
	var ai := TacticalAI.new(battle, 1)
	check(ai.choose_strategy("pincer"), "a plan that suits the battle is taken")
	check_eq(ai.plans, ["pincer"] as Array[String], "and replaces the random one")
	var tankless := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(13, 13)]])
	var other := TacticalAI.new(tankless, 0)
	var picked := other.strategy
	check(not other.choose_strategy("armoured_spearhead"), "a tank plan without tanks is refused")
	check(not other.choose_strategy(""), "random keeps the pick")
	check_eq(other.strategy, picked, "so the random plan stays")


func test_ai_flank_plans_go_round_their_flank() -> void:
	# The Allies start on the west, so their left is north (low y).
	var mean_y := {}
	for plan in ["left_hook", "right_hook"]:
		var battle: Battle = GameSession.build_skirmish({"map": "village", "seed": 3})[0]
		var ai := TacticalAI.new(battle, 0)
		ai.set_strategy(plan)
		battle.start()
		while battle.round_number < 4 and battle.winner == -1:
			if battle.current_team == 0:
				ai.act()
			else:
				battle.execute({"cmd": "end_turn"})
		var sum := 0.0
		var units := battle.alive_units(0)
		for u in units:
			sum += u.pos.y
		mean_y[plan] = sum / units.size()
		check_eq(ai.plans[-1], plan, "%s is still the plan" % plan)
	check(mean_y["left_hook"] + 4.0 < mean_y["right_hook"], "a left hook ends up north of a right hook (%s)" % [mean_y])


func test_ai_plans_adapt() -> void:
	var battle: Battle = GameSession.build_skirmish({"map": "village", "seed": 3})[0]
	battle.start()
	var ai := TacticalAI.new(battle, 0)
	ai.set_strategy("hold_two")
	check(not ai._digging_in(), "nothing to dig in on yet")
	for i: int in ai._pair:
		battle.objectives[i]["owner"] = 0
	check(ai._digging_in(), "digs in once both objectives are held")
	var wings := {}
	for u in battle.alive_units(0):
		wings[ai._plan_goal(u)] = true
	check_eq(wings.size(), 2, "and each wing stays on its own one")

	ai.set_strategy("ambush")
	check(ai._ambushing(), "waits at first")
	battle.victory_points[1] = 1
	ai._review_strategy()
	check(not ai._ambushing(), "and strikes back once behind")

	var tanks := make_battle([["Tank", 0, Vector2i(2, 2)], ["Rifleman", 0, Vector2i(2, 4)], ["Rifleman", 1, Vector2i(13, 13)]])
	var tank_ai := TacticalAI.new(tanks, 0)
	tank_ai.plans.clear()
	tank_ai.set_strategy("armoured_spearhead")
	tanks.units[0].hp = 0
	tank_ai._review_strategy()
	check_eq(tank_ai.strategy, "broad_front", "the spearhead gives way when the tanks are gone")
	check_eq(tank_ai.plans, ["armoured_spearhead", "broad_front"] as Array[String], "and the log shows both plans")

	var copy := TacticalAI.new(tanks, 0)
	copy.load_dict(tank_ai.to_dict())
	check_eq(copy.strategy, tank_ai.strategy, "the plan is saved")
	check_eq(copy.plan_summary(), tank_ai.plan_summary(), "with its history")


# --- Tanks ---

func test_small_arms_bounce_off_tanks() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["Tank", 1, Vector2i(5, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	var tank := battle.units[1]
	for i in 6:
		battle.units[0].actions = 2
		battle.current_team = 0
		battle.shoot(battle.units[0], tank)
		battle.units[0].ammo = 8
	check_eq(tank.hp, tank.max_hp, "rifle fire never hurts a tank")
	check_eq(tank.suppression, 0, "tanks can't be suppressed")


func test_anti_tank_damage_depends_on_armour_side() -> void:
	var battle := make_battle([["AT", 0, Vector2i(2, 5)], ["Tank", 1, Vector2i(5, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	var tank := battle.units[1]
	tank.facing = Vector2i(-1, 0)
	check_eq(CombatRules.armor_side(tank, Vector2i(2, 5)), "front", "facing the shooter")
	check_eq(CombatRules.armor_side(tank, Vector2i(9, 5)), "rear", "shot from behind")
	check_eq(CombatRules.armor_side(tank, Vector2i(5, 1)), "side", "shot from the side")
	var ai := TacticalAI.new(battle, 0)
	var front := ai._expected_damage(battle.units[0], Vector2i(2, 5), tank, tank.pos)[0]
	var rear := ai._expected_damage(battle.units[0], Vector2i(8, 5), tank, tank.pos)[0]
	check(rear > front, "rear shots do more damage (%.2f vs %.2f)" % [rear, front])
	check_eq(ai._expected_damage(battle.units[2], Vector2i(10, 5), tank, tank.pos)[0], 0.0, "AI knows rifles can't hurt tanks")


func test_tanks_crush_and_push_through() -> void:
	var battle := make_battle([["Tank", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	var map := battle.map
	# A line of crates with a hedge behind it, right across the map: the tank has to go through.
	for y in map.height:
		map.set_object(Vector2i(3, y), Cover.HALF, "crate")
		map.set_edge(Vector2i(3, y), Vector2i(4, y), Cover.FULL, "hedge")
	map.set_object(Vector2i(6, 6), Cover.FULL, "rock")
	var tank := battle.units[0]
	check(not battle.reachable(tank).has(Vector2i(6, 6)), "rocks stop tanks")
	battle.move(tank, Vector2i(5, 5))
	check_eq(tank.pos, Vector2i(5, 5), "drove through")
	var crates := 0
	var hedges := 0
	for y in map.height:
		crates += int(map.get_object(Vector2i(3, y)) == Cover.HALF)
		hedges += int(map.get_edge(Vector2i(3, y), Vector2i(4, y)) == Cover.FULL)
	check_eq(crates, map.height - 1, "one crate crushed")
	check_eq(hedges, map.height - 1, "one hedge flattened")
	check(tank.facing.x > 0, "facing the way it drove")
	check(map.has_vehicle(Vector2i(5, 5)) and not map.has_vehicle(Vector2i(2, 5)), "tank tile tracked")
	check_eq(map.cover_toward(Vector2i(4, 5), Vector2i(1, 0)), Cover.HALF, "soldiers can shelter behind a tank")


func test_tanks_knock_down_trees() -> void:
	var battle := make_battle([["Tank", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	battle.map.set_object(Vector2i(3, 5), Cover.FULL, "tree")
	battle.move(battle.units[0], Vector2i(4, 5))
	check_eq(battle.units[0].pos, Vector2i(4, 5), "drove through the tree")
	check_eq(battle.map.get_object(Vector2i(3, 5)), Cover.NONE, "the tree is gone")
	var blocked := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	blocked.map.set_object(Vector2i(3, 5), Cover.FULL, "tree")
	check(not blocked.reachable(blocked.units[0]).has(Vector2i(3, 5)), "soldiers still can't walk through trees")


func test_tanks_pay_to_turn_and_back_up_slowly() -> void:
	var battle := make_battle([["Tank", 0, Vector2i(8, 8)], ["Rifleman", 1, Vector2i(15, 15)]])
	var tank := battle.units[0]
	tank.facing = Vector2i(1, 0)
	var reach := battle.reachable(tank)
	check_eq(reach[Vector2i(10, 8)]["cost"], 2.0, "straight ahead costs just the ground")
	check_eq(reach[Vector2i(8, 10)]["cost"], 4.0, "turning 90 degrees costs 2 more")
	check_eq(reach[Vector2i(6, 8)]["cost"], 4.0, "backing up two tiles costs double")
	check_eq(reach[Vector2i(6, 8)]["facing"], Vector2i(1, 0), "backing up keeps the front toward the enemy")
	var events := battle.move(tank, Vector2i(8, 10))
	check_eq(tank.facing, Vector2i(0, 1), "faces the way it turned")
	check_eq(events_of(events, "move")[0]["facings"].size(), events_of(events, "move")[0]["path"].size(), "move events carry the hull's facing per step")
	check(battle.can_move(tank, tank.pos, -1, Vector2i(0, 1)) != "", "no turning to the same facing")
	var actions := tank.actions
	events = battle.execute({"cmd": "move", "unit": tank.id, "tile": tank.pos, "facing": Vector2i(-1, -1)})
	check_eq(tank.facing, Vector2i(-1, -1), "turns on the spot: a move to its own tile with a facing")
	check_eq(events_of(events, "pivot").size(), 1, "shown as a pivot")
	check_eq(tank.actions, actions - 1, "turning on the spot costs an action")
	var soldier := make_battle([["Rifleman", 0, Vector2i(8, 8)], ["Rifleman", 1, Vector2i(15, 15)]])
	check(soldier.can_move(soldier.units[0], Vector2i(9, 8), -1, Vector2i(0, 1)) != "", "only tanks choose a facing")


func test_tanks_choose_where_to_face_at_the_end_of_a_move() -> void:
	var battle := make_battle([["Tank", 0, Vector2i(8, 8)], ["Rifleman", 1, Vector2i(15, 15)]])
	var tank := battle.units[0]
	tank.facing = Vector2i(1, 0)
	var reach := battle.reachable(tank)
	check_eq(battle.move_cost(tank, reach, Vector2i(10, 8), 0, Vector2i(-1, 0)), 2.0 + 4.0, "turning 180 degrees at the end adds 4")
	check(battle.can_move(tank, Vector2i(9, 8), -1, Vector2i(0, 1)) == "", "within one action: it can")
	check(battle.can_move(tank, Vector2i(9, 8), -1, Vector2i(3, 1)) != "", "facings are headings")
	var events := battle.execute({"cmd": "move", "unit": tank.id, "tile": Vector2i(9, 8), "facing": Vector2i(0, 1)})
	check_eq(tank.pos, Vector2i(9, 8), "drove there")
	check_eq(tank.facing, Vector2i(0, 1), "and turned to face south")
	check_eq(events_of(events, "pivot").size(), 1, "the turn shows as a pivot after the move")
	check_eq(tank.actions, 1, "one action for both")
	var big_turn := battle.move_cost(tank, battle.reachable(tank), Vector2i(9, 8 + int(tank.current_mobility()) - 1), 0, Vector2i(0, -1))
	check(big_turn > tank.current_mobility(), "a long drive and a full turn may not fit")


func test_commands_as_data_and_checksums() -> void:
	var a := NormandyScenario.build(77)
	var b := NormandyScenario.build(77)
	a.start()
	b.start()
	check_eq(a.checksum(), b.checksum(), "same setup, same checksum")
	var ai := TacticalAI.new(a, 0)
	for i in 40:
		if a.winner != -1:
			break
		ai.team = a.current_team
		var command := ai.decide()
		check(not a.execute(command).is_empty(), "AI command %s is valid" % command.get("cmd"))
		b.execute(command)
		if a.checksum() != b.checksum():
			break
	check_eq(a.checksum(), b.checksum(), "replaying the same commands keeps both games identical")
	check(a.execute({"cmd": "move", "unit": 999, "tile": Vector2i(1, 1)}).is_empty(), "unknown units are rejected")
	var enemy := a.alive_units(1 - a.current_team)[0]
	check(a.execute({"cmd": "overwatch", "unit": enemy.id}).is_empty(), "the other side's units are rejected")
	b.rng.randi()
	check(a.checksum() != b.checksum(), "a different dice state changes the checksum")


func test_ai_prefers_cover_facing_the_enemy() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(4, 8)], ["Rifleman", 1, Vector2i(13, 8)]])
	# Two spots the same distance from the enemy: one behind a wall facing them, one in the open.
	battle.map.set_edge(Vector2i(7, 6), Vector2i(8, 6), Cover.FULL, "wall")
	var ai := TacticalAI.new(battle, 0)
	var seen: Array[Unit] = [battle.units[1]]
	var covered := ai._position_score(battle.units[0], Vector2i(7, 6), seen)
	var open := ai._position_score(battle.units[0], Vector2i(7, 10), seen)
	check(covered > open + 20.0, "cover toward the enemy is worth a lot (%.1f vs %.1f)" % [covered, open])
	var wrong_side := make_battle([["Rifleman", 0, Vector2i(4, 8)], ["Rifleman", 1, Vector2i(13, 8)]])
	wrong_side.map.set_edge(Vector2i(7, 6), Vector2i(6, 6), Cover.FULL, "wall")
	var ai2 := TacticalAI.new(wrong_side, 0)
	var behind := ai2._position_score(wrong_side.units[0], Vector2i(7, 6), [wrong_side.units[1]] as Array[Unit])
	check(covered > behind + 10.0, "cover on the far side counts less (%.1f vs %.1f)" % [covered, behind])


func test_skirmish_plays_the_previewed_map() -> void:
	for theatre in Theatres.all():
		var style: String = theatre.map_styles()[1]["id"]
		var preview := theatre.generate_map(555, Vector2i(44, 44), style)
		var built: Array = GameSession.build_skirmish({"theatre": theatre.id, "map": "random", "size": 44, "style": style, "seed": 555})
		check(same_map(built[0].map, preview["map"]), "%s: the skirmish is fought on the map the menu showed" % theatre.id)
		check(built[1].begins_with(theatre.map_styles()[1]["title"]), "%s: and is named for its kind (%s)" % [theatre.id, built[1]])


func test_big_skirmish_maps() -> void:
	for size in [64, 84]:
		var built := GameSession.build_skirmish({"map": "random", "size": size, "seed": 4242})
		var battle: Battle = built[0]
		check_eq(battle.map.width, size, "map is %d wide" % size)
		check(battle.units.size() >= (12 if size == 64 else 15) * 2, "bigger forces on %dx%d" % [size, size])
		var layout := MapGenerator.generate(4242, Vector2i(size, size), "bocage")
		check(MapGenerator.is_playable(layout), "%dx%d map is playable" % [size, size])
		var walls := 0
		for key: Vector3i in layout["map"].get_edges():
			walls += 1
		check(walls > size * 8, "%dx%d map has plenty of hedges and walls (%d)" % [size, size, walls])


func test_tank_shell_splashes_and_wrecks_burn() -> void:
	var battle := make_battle([["Tank", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(8, 5)], ["Rifleman", 1, Vector2i(8, 6)], ["Rifleman", 1, Vector2i(15, 15)]])
	battle.map.set_object(Vector2i(7, 5), Cover.HALF, "sandbags")
	battle.units[1].hp = 50
	battle.units[2].hp = 50
	var events := battle.shoot(battle.units[0], battle.units[1])
	check_eq(events_of(events, "explosion").size(), 1, "the shell explodes")
	check(battle.units[2].hp < 50 or Vector2(events_of(events, "explosion")[0]["center"]).distance_to(Vector2(8, 6)) > 1.0, "splash hits the neighbour")
	var wreck_battle := make_battle([["AT", 0, Vector2i(2, 5)], ["Tank", 1, Vector2i(5, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	wreck_battle._damage(wreck_battle.units[1], 100, 0, wreck_battle.units[0])
	check_eq(wreck_battle.map.get_object(Vector2i(5, 5)), Cover.FULL, "a destroyed tank leaves a wreck")
	check_eq(wreck_battle.map.get_object_kind(Vector2i(5, 5)), "wreck", "kind is wreck")
	check_eq(wreck_battle.units[0].kills, 1, "kill credited")


# --- Stray grenades and rounds ---

func test_grenade_scatter_stays_in_radius_and_is_deterministic() -> void:
	var landings := []
	var off_target := 0
	var outside := 0
	for seed in range(1, 41):
		var units: Array[Unit] = [Unit.create(0, "A", "Rifleman", 0, Vector2i(2, 8)), Unit.create(1, "B", "Rifleman", 1, Vector2i(15, 15))]
		units[0].aim = 50
		units[0].suppression = Unit.SUPPRESSED_AT
		var battle := Battle.new(TacticalMap.new(16, 16), units, seed)
		battle.start()
		var target := Vector2i(11, 8)
		var scatter := CombatRules.throw_scatter(units[0], units[0].pos, target)
		var events := battle.throw_grenade(units[0], target)
		var landing: Vector2i = events_of(events, "throw")[0]["center"]
		check_eq(events_of(events, "explosion")[0]["center"], landing, "the blast is where it landed")
		if Vector2(landing).distance_to(Vector2(target)) > scatter + 0.001:
			outside += 1
		if landing != target:
			off_target += 1
		landings.append(landing)
		var spread := battle.throw_landings(target, scatter)
		var total := 0.0
		for spot: Vector2i in spread:
			total += spread[spot]
			if Vector2(spot).distance_to(Vector2(target)) > scatter + 0.001:
				outside += 1
		check(absf(total - 1.0) < 0.001, "landing odds add up to 1")
	check_eq(outside, 0, "grenades never land beyond the stated scatter")
	check(off_target > 0 and off_target < 40, "long, shaky throws sometimes land off target (%d of 40)" % off_target)
	var again := []
	for seed in [1, 2, 3]:
		var units: Array[Unit] = [Unit.create(0, "A", "Rifleman", 0, Vector2i(2, 8)), Unit.create(1, "B", "Rifleman", 1, Vector2i(15, 15))]
		units[0].aim = 50
		units[0].suppression = Unit.SUPPRESSED_AT
		var battle := Battle.new(TacticalMap.new(16, 16), units, seed)
		battle.start()
		again.append(events_of(battle.throw_grenade(units[0], Vector2i(11, 8)), "throw")[0]["center"])
	check_eq(again, landings.slice(0, 3), "same seed, same landing")


func test_grenades_bounce_off_walls() -> void:
	var beyond := 0
	for seed in range(1, 31):
		var units: Array[Unit] = [Unit.create(0, "A", "Rifleman", 0, Vector2i(2, 8)), Unit.create(1, "B", "Rifleman", 1, Vector2i(0, 15))]
		units[0].aim = 40
		units[0].suppression = Unit.PINNED_AT
		var map := TacticalMap.new(16, 16)
		for y in 16:
			map.set_edge(Vector2i(10, y), Vector2i(11, y), Cover.FULL)
		var battle := Battle.new(map, units, seed)
		battle.start()
		var landing: Vector2i = events_of(battle.throw_grenade(units[0], Vector2i(10, 8)), "throw")[0]["center"]
		if landing.x > 10:
			beyond += 1
	check_eq(beyond, 0, "a grenade never flies through a wall")


func test_stray_rockets_can_hit_friends() -> void:
	var friend_hits := 0
	var outside := 0
	for seed in range(1, 61):
		var units: Array[Unit] = [
			Unit.create(0, "AT", "AT", 0, Vector2i(2, 8)), Unit.create(1, "Target", "Rifleman", 1, Vector2i(6, 8)),
			Unit.create(2, "Friend", "Rifleman", 0, Vector2i(8, 8)),
		]
		units[1].defense = 200
		units[1].hp = 50
		units[2].hp = 50
		var battle := Battle.new(TacticalMap.new(16, 16), units, seed)
		battle.start()
		var zone := battle.stray_tiles(units[0].pos, units[1].pos)
		var shot: Dictionary = events_of(battle.shoot(units[0], units[1]), "shot")[0]
		check_eq(shot["result"], "miss", "can't hit")
		if not zone.has(shot.get("stray", Vector2i(-1, -1))):
			outside += 1
		if units[2].hp < 50:
			friend_hits += 1
	check_eq(outside, 0, "missed rockets land in the stray zone")
	check(friend_hits > 0, "stray rockets can hit friends (%d of 60)" % friend_hits)
	var battle := make_battle([["AT", 0, Vector2i(2, 8)], ["Rifleman", 1, Vector2i(6, 8)], ["Rifleman", 0, Vector2i(8, 8)]])
	var risks := battle.stray_risks(battle.units[0], battle.units[0].pos, battle.units[1])
	check(risks.size() == 1 and risks[0]["unit"] == battle.units[2] and risks[0]["chance"] > 0.0, "the friend behind the target is at risk")


func test_stray_machine_gun_rounds_hit_bystanders() -> void:
	var hits := {}
	for seed in range(1, 61):
		var units: Array[Unit] = [
			Unit.create(0, "MG", "MG", 0, Vector2i(2, 8)), Unit.create(1, "Target", "Rifleman", 1, Vector2i(9, 8)),
			Unit.create(2, "Friend", "Rifleman", 0, Vector2i(9, 9)), Unit.create(3, "Enemy", "Rifleman", 1, Vector2i(5, 8)),
			Unit.create(4, "Clear", "Rifleman", 0, Vector2i(5, 12)),
		]
		units[1].defense = 200
		for u in units:
			u.hp = 50
		var battle := Battle.new(TacticalMap.new(16, 16), units, seed)
		battle.start()
		var shot: Dictionary = events_of(battle.shoot(units[0], units[1]), "shot")[0]
		if shot.has("stray_unit"):
			hits[shot["stray_unit"]] = true
		check_eq(units[4].hp, 50, "nobody far from the line of fire is hit")
	check(hits.has(2), "a stray burst can hit a friend beside the target")
	check(hits.has(3), "or an enemy in the line of fire")
	var battle := make_battle([["MG", 0, Vector2i(2, 8)], ["Rifleman", 1, Vector2i(9, 8)], ["Rifleman", 0, Vector2i(9, 9)], ["Rifleman", 0, Vector2i(5, 12)]])
	var at_risk := battle.mg_bystanders(battle.units[0], battle.units[0].pos, battle.units[1])
	check_eq(at_risk, [battle.units[2]], "only the friend beside the target is at risk")


func test_missed_rifle_rounds_fly_on() -> void:
	# A friend just behind the target can catch a missed round; one behind a wall can't.
	var friend_hits := 0
	var walled_hits := 0
	for seed in range(1, 121):
		for walled in [false, true]:
			var units: Array[Unit] = [
				Unit.create(0, "Shooter", "Rifleman", 0, Vector2i(2, 8)), Unit.create(1, "Target", "Rifleman", 1, Vector2i(6, 8)),
				Unit.create(2, "Friend", "Rifleman", 0, Vector2i(8, 8)),
			]
			for u in units:
				u.hp = 50
			units[1].defense = 200
			var map := TacticalMap.new(16, 16)
			if walled:
				map.set_edge(Vector2i(6, 8), Vector2i(7, 8), Cover.FULL, "wall")
			var battle := Battle.new(map, units, seed)
			battle.start()
			var shot: Dictionary = events_of(battle.shoot(units[0], units[1]), "shot")[0]
			check_eq(shot["result"], "miss", "can't hit")
			check(shot.has("stray"), "a missed rifle round goes somewhere")
			if units[2].hp < 50:
				if walled:
					walled_hits += 1
				else:
					friend_hits += 1
					check_eq(shot.get("stray_unit", -1), 2, "the hit is marked on the shot")
	check(friend_hits > 0 and friend_hits < 40, "a stray round sometimes hits the friend behind the target (%d of 120)" % friend_hits)
	check_eq(walled_hits, 0, "a wall behind the target stops the round")
	# A diagonal shot flies on diagonally, round the corners of the tiles it passes.
	var slant := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(6, 5)]])
	var flight := slant.round_flight(Vector2i(2, 2), slant.units[1])
	check(flight["tile"].x > 6 and flight["tile"].y > 5, "a diagonal miss flies on past the target (%s)" % [flight["tile"]])
	slant.units[1].defense = 200
	check(events_of(slant.shoot(slant.units[0], slant.units[1]), "shot")[0].has("stray"), "and the shot is marked where it went")
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 8)], ["Rifleman", 1, Vector2i(6, 8)], ["Rifleman", 0, Vector2i(8, 8)]])
	var risks := battle.stray_risks(battle.units[0], battle.units[0].pos, battle.units[1])
	check(risks.size() == 1 and risks[0]["unit"] == battle.units[2], "the odds warn about the friend behind the target")
	# A glazed window behind the target stops the round and shatters.
	var glass := make_battle([["Rifleman", 0, Vector2i(2, 8)], ["Rifleman", 1, Vector2i(6, 8)]])
	glass.map.set_edge(Vector2i(7, 8), Vector2i(8, 8), Cover.HALF, "window")
	glass.units[1].defense = 200
	var events := glass.shoot(glass.units[0], glass.units[1])
	check_eq(glass.map.get_edge_kind(Vector2i(7, 8), Vector2i(8, 8)), "broken_window", "the window behind is shot out")
	check_eq(events_of(events, "window_broken").size(), 1, "and the glass breaking is told")
	check(events_of(events, "shot")[0].has("stray_edge"), "the round is drawn ending at the window")


func test_odds_info_lists_the_stray_risk() -> void:
	var battle := make_battle([["MG", 0, Vector2i(2, 8)], ["Rifleman", 1, Vector2i(9, 8)], ["Rifleman", 0, Vector2i(9, 9)]])
	battle.units[2].name = "Pvt. Friend"
	var view: Node2D = load("res://scripts/view/battle_view.gd").new()
	view.battle = battle
	var text: String = view._describe_odds(battle.units[0], battle.units[1])
	check(text.contains("Misses may hit: Pvt. Friend (friendly)"), "the odds panel warns about friends in the line of fire")
	view.selected = battle.units[0]
	var scatter_text: String = view._describe_scatter(Vector2i(9, 8), CombatRules.GRENADE_RADIUS, true)
	check(scatter_text.contains("tiles off target") and scatter_text.contains("Pvt. Friend"), "the grenade panel shows the scatter and who it could catch")
	view.free()


func test_ai_weighs_friendly_fire() -> void:
	var battle := make_battle([["MG", 0, Vector2i(2, 8)], ["Rifleman", 1, Vector2i(9, 8)], ["Rifleman", 0, Vector2i(9, 9)], ["Rifleman", 1, Vector2i(15, 2)]])
	var mg := battle.units[0]
	var ai := TacticalAI.new(battle, 0)
	var risky := ai._shot_value(mg, mg.pos, battle.units[1])
	battle.units[2].pos = Vector2i(0, 15)
	var clear := ai._shot_value(mg, mg.pos, battle.units[1])
	check(risky < clear, "firing past a friend is worth less (%.1f vs %.1f)" % [risky, clear])
	battle.units[2].pos = Vector2i(9, 9)
	var grenade_battle := make_battle([["Rifleman", 0, Vector2i(2, 8)], ["Rifleman", 1, Vector2i(11, 8)], ["Rifleman", 0, Vector2i(12, 9)], ["Rifleman", 1, Vector2i(15, 2)]])
	var thrower := grenade_battle.units[0]
	thrower.aim = 50
	var grenade_ai := TacticalAI.new(grenade_battle, 0)
	var seen: Array[Unit] = [grenade_battle.units[1]]
	var aimed := grenade_ai._blast_value(Vector2i(10, 8), CombatRules.GRENADE_RADIUS, CombatRules.GRENADE_DAMAGE_MIN, CombatRules.GRENADE_DAMAGE_MAX, CombatRules.GRENADE_SHRED, seen)
	check(grenade_ai._grenade_value(thrower, Vector2i(10, 8), seen) < aimed, "a scattering grenade near a friend is worth less than a perfect throw")


# --- Saving ---

func test_save_and_load_round_trip() -> void:
	var battle := NormandyScenario.build(42)
	var ais := [TacticalAI.new(battle, 0), TacticalAI.new(battle, 1)]
	battle.start()
	for i in 12:
		ais[battle.current_team].act()
	var copy := Battle.from_dict(battle.to_dict())
	check_eq(copy.round_number, battle.round_number, "round restored")
	check_eq(copy.current_team, battle.current_team, "turn restored")
	check_eq(copy.units.size(), battle.units.size(), "units restored")
	for i in battle.units.size():
		check_eq(copy.units[i].to_dict(), battle.units[i].to_dict(), "unit %d restored" % i)
	check_eq(copy.map.to_dict(), battle.map.to_dict(), "map restored")
	check_eq(copy.victory_points, battle.victory_points, "points restored")
	# Same rolls after loading: both copies play on identically.
	var copy_ais := [TacticalAI.new(copy, 0), TacticalAI.new(copy, 1)]
	copy_ais[0].load_dict(ais[0].to_dict())
	copy_ais[1].load_dict(ais[1].to_dict())
	for i in 10:
		var a: Array = ais[battle.current_team].act()
		var b: Array = copy_ais[copy.current_team].act()
		check_eq(var_to_str(b), var_to_str(a), "step %d plays out the same after loading" % i)


## A two-map online campaign with both sides' orders in for the first map.
func _online_war() -> WarCampaign:
	var war := WarCampaign.create(2, 31, [false, false])
	for side in 2:
		war.set_orders(side, {"roster": ["Officer", "Rifleman", "Rifleman", "MG"], "flank": "balanced", "posture": "offensive"})
	return war


func test_online_campaign_saves_between_maps() -> void:
	var saved_dir := GameSession.save_dir
	GameSession.save_dir = OS.get_temp_dir().path_join("normandy-war-test-%d" % OS.get_process_id())
	var war := _online_war()
	GameSession.start_online_war(war, 0, "game-w", "1.2.3.4:24944", true)
	GameSession.save_online(0)
	var offer := GameSession.online_offer()
	check(offer.get("battle", {"x": 1}).is_empty(), "between maps there is no battle in the save")
	check(GameSession.describe_online(offer).contains("giving orders"), "the save says the players are giving orders")
	check(GameSession.resume_online(offer, 1, "", false), "the campaign loads from the offer")
	check_eq(GameSession.war.checksum(), war.checksum(), "the same campaign")
	check(GameSession.battle == null, "and no battle yet")
	var fake := Battle.new(TacticalMap.new(4, 4), [] as Array[Unit])
	fake.winner = 0
	GameSession.war.complete_map(fake)
	GameSession.war.current = GameSession.war.maps.size()
	GameSession.save_online(1)
	check(not GameSession.has_save("online"), "a finished campaign clears its save")
	DirAccess.remove_absolute(GameSession.save_dir)
	GameSession.save_dir = saved_dir
	GameSession.online = {}
	GameSession.war = null


func test_online_save_continues_identically() -> void:
	var saved_dir := GameSession.save_dir
	GameSession.save_dir = OS.get_temp_dir().path_join("normandy-test-%d" % OS.get_process_id())
	var battle: Battle = GameSession.build_skirmish({"map": "random", "size": 44, "seed": 99})[0]
	battle.start()
	var ai := TacticalAI.new(battle, 0)
	while battle.round_number < 3:
		ai.team = battle.current_team
		battle.execute(ai.decide())
	# Saved to disk and loaded back, the battle has the same checksum (dictionary order, floats, dice).
	GameSession.start_online_war(_online_war(), 1, "game-1", "1.2.3.4:24944", false)
	GameSession.start_online_battle(battle, "Test map")
	GameSession.save_online(1)
	var offer := GameSession.online_offer()
	check_eq(offer.get("checksum"), GameSession.online_checksum(), "the online save keeps the checksum")
	check(str(offer.get("checksum")).ends_with(battle.checksum()), "the battle's included")
	check_eq(offer.get("team"), 1, "the save knows our side")
	check_eq(GameSession.compare_online(offer), "", "our own save matches itself")
	var other := offer.duplicate()
	other["game_id"] = "game-2"
	check(GameSession.compare_online(other) != "", "a different game is noticed")
	var later := offer.duplicate()
	later["checksum"] = "x"
	later["turn_index"] = offer["turn_index"] + 2
	check(GameSession.compare_online(later).contains("round"), "a different point in the game is noticed")
	check(not GameSession.resume_online(later, 0, "", true), "a battle that doesn't match its checksum isn't loaded")
	check(GameSession.resume_online(offer, 0, "", true), "the offer loads")
	var copy := GameSession.battle
	check(copy != battle, "a fresh battle was loaded")
	check_eq(copy.checksum(), battle.checksum(), "loaded battle has the same checksum")
	# Both play on under the same commands and stay identical.
	for i in 60:
		if battle.winner != -1:
			break
		ai.team = battle.current_team
		var command := ai.decide()
		check_eq(var_to_str(copy.execute(command)), var_to_str(battle.execute(command)), "command %d plays out the same after loading" % i)
		if copy.checksum() != battle.checksum():
			break
	check_eq(copy.checksum(), battle.checksum(), "both games stay identical after loading")
	# Agreeing on a turn change saves; a finished battle clears the save.
	GameSession.on_turn_agreed(copy.turn_index, "not the state", 0)
	check_eq(GameSession.peek("online")["checksum"], offer["checksum"], "a state the games don't agree on isn't saved")
	GameSession.on_turn_agreed(copy.turn_index, copy.checksum(), 0)
	check_eq(GameSession.peek("online")["checksum"], GameSession.online_checksum(), "an agreed turn change is saved")
	copy.winner = 0
	GameSession.save_online(0)
	check(GameSession.peek("online").get("battle", {"x": 1}).is_empty(), "once the battle is over the save keeps only the campaign")
	GameSession.delete_save("online")
	DirAccess.remove_absolute(GameSession.save_dir)
	GameSession.save_dir = saved_dir
	GameSession.online = {}
	GameSession.war = null
	GameSession.battle = null


# --- Replays ---

## Plays AI vs AI until the battle ends (or `steps` commands), returning how many commands were executed.
func play_ai(battle: Battle, steps := 3000) -> int:
	var ais := [TacticalAI.new(battle, 0), TacticalAI.new(battle, 1)]
	var count := 0
	while battle.winner == -1 and count < steps:
		ais[battle.current_team].act()
		count += 1
	return count


func test_replay_records_and_plays_back() -> void:
	var saved_dir := GameSession.save_dir
	GameSession.save_dir = OS.get_temp_dir().path_join("normandy-replay-test-%d" % OS.get_process_id())
	var battle: Battle = GameSession.build_skirmish({"map": "random", "size": 44, "seed": 321})[0]
	battle.max_rounds = 6
	var replay := Replay.begin(battle, "Replay test", "skirmish", ["AI", "AI"])
	replay.attach(battle)
	battle.start()
	play_ai(battle)
	check(battle.winner != -1, "the recorded AI battle ends")
	replay.finish(battle)
	check(replay.commands.size() > 20, "every command is recorded (%d)" % replay.commands.size())
	check(not replay.checkpoints.is_empty(), "turn changes are checkpointed")
	check(replay.result != "", "the result is noted")
	var recorded := replay.commands.size()
	battle.execute({"cmd": "move", "unit": -5})
	check_eq(replay.commands.size(), recorded, "rejected commands aren't recorded")
	var path := replay.save_file()
	check(path != "" and FileAccess.file_exists(path), "the replay is saved to the replays folder")
	check(path.begins_with(GameSession.save_dir), "replays follow --save-dir")
	var listed := Replay.list()
	check_eq(listed.size(), 1, "the replay is listed")
	check_eq(listed[0].get("title"), "Replay test", "the list shows its title")
	check_eq(listed[0].get("orders"), replay.commands.size(), "the list shows its length")
	var loaded := Replay.load_file(path)
	check(loaded != null, "the replay loads")
	check_eq(loaded.verify(), "", "the loaded replay plays out as recorded")
	# Played back by hand: the same final state.
	var copy := loaded.build()
	check(not copy.started, "the replay starts before the first turn")
	copy.start()
	for command in loaded.commands:
		copy.execute(command)
	check_eq(copy.checksum(), battle.checksum(), "the replay ends in the same state")
	check_eq(copy.winner, battle.winner, "the replay ends with the same winner")
	# A replay that doesn't match is reported.
	var broken := Replay.load_file(path)
	broken.commands.remove_at(1)
	check(broken.verify() != "", "a replay that plays out differently is reported")
	var tampered := Replay.load_file(path)
	tampered.snapshot["rng_state"] = int(tampered.snapshot["rng_state"]) + 1
	check(tampered.verify() != "", "different dice are noticed")
	# Only the newest are kept.
	for i in Replay.KEEP + 2:
		replay.save_file()
	check_eq(Replay.list().size(), Replay.KEEP, "only the newest %d replays are kept" % Replay.KEEP)
	Replay.delete_file(Replay.list()[0]["path"])
	check_eq(Replay.list().size(), Replay.KEEP - 1, "a replay can be deleted")
	for entry in Replay.list():
		Replay.delete_file(entry["path"])
	DirAccess.remove_absolute(Replay.folder())
	DirAccess.remove_absolute(GameSession.save_dir)
	GameSession.save_dir = saved_dir


func test_battle_report_tallies_the_replay() -> void:
	var battle: Battle = GameSession.build_skirmish({"map": "random", "size": 44, "seed": 321})[0]
	battle.max_rounds = 6
	var replay := Replay.begin(battle, "Report test", "skirmish", ["AI", "AI"])
	replay.attach(battle)
	battle.start()
	play_ai(battle)
	replay.finish(battle)
	var report := BattleReport.from_replay(replay)
	check_eq(report.error, "", "the report plays the replay through")
	check_eq(report.winner, battle.winner, "the report knows who won")
	var orders := 0
	for command in replay.commands:
		if command["cmd"] != "end_turn":
			orders += 1
	check_eq(report.sides[0]["orders"] + report.sides[1]["orders"], orders, "every order is counted for its side")
	var losses := 0
	for u in battle.units:
		if not u.is_alive():
			losses += 1
	check_eq(report.sides[0]["losses"] + report.sides[1]["losses"], losses, "every death is counted")
	for team in 2:
		var side: Dictionary = report.sides[team]
		check_eq(side["hits"] + side["grazes"] + side["misses"], side["shots"], "every shot hit, grazed or missed")
		check(side["crits"] <= side["hits"], "crits are hits")
		check(side["expected_hits"] <= side["shots"], "expected hits can't exceed the shots")
		check(side["at_full"] + side["at_half"] <= side["aimed"], "cover is counted on aimed shots")
	check(report.sides[0]["shots"] + report.sides[1]["shots"] > 0, "the AI battle has shots in it")
	check(report.rows().size() > 10, "the report has its table")
	var dealt := 0
	var kills := 0
	for team in 2:
		dealt += report.sides[team]["damage_dealt"] + report.sides[team]["friendly_damage"] + report.sides[team]["damage_other"]
		kills += report.sides[team]["kills"]
	check_eq(dealt, report.sides[0]["damage_taken"] + report.sides[1]["damage_taken"], "all damage taken was dealt by someone or something")
	check(kills <= losses, "no more kills than losses")
	var soldiers := report.unit_rows(0).size() + report.unit_rows(1).size()
	check_eq(soldiers, battle.units.size(), "every soldier has a row")


## Luck from hand-made dice: hits against the odds.
func test_battle_report_counts_luck() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(9, 2)]])
	var report := BattleReport.new()
	for i in 10:
		# The Allies hit all ten 50% shots, Germany hits half of its own.
		report.tally(battle, {}, [{"type": "shot", "shooter": 0, "target": 1, "result": "hit", "chance": 50, "crit_chance": 10, "reaction": false, "cover": Cover.HALF, "flanked": false}])
		report.tally(battle, {}, [{"type": "shot", "shooter": 1, "target": 0, "result": "hit" if i % 2 == 0 else "miss", "chance": 50, "crit_chance": 10, "reaction": false, "cover": Cover.NONE, "flanked": true}])
	check_eq(report.luck(0), 5.0, "five hits beyond the odds")
	check_eq(report.luck(1), 0.0, "right on the odds")
	check_eq(report.avg_chance(0), 50.0, "the average hit chance")
	check_eq(report.hit_rate(1), 50.0, "the share of shots that hit")
	check_eq(report.sides[0]["at_half"], 10, "shots at half cover are counted")
	check_eq(report.sides[1]["flanking"], 10, "flanking shots are counted")
	check(is_equal_approx(report.sides[0]["expected_crits"], 0.5), "expected crits: hit chance times crit chance")
	report.tally(battle, {"cmd": "move", "unit": 0}, [], 0)
	check_eq(report.sides[0]["order_kinds"].get("Moves", 0), 1, "orders are counted by kind")
	check_eq(report.sides[0]["bands"][1]["shots"], 10, "50% shots fall in the fair-odds band")
	check_eq(report.units[0]["shots"], 10, "each soldier's shots are counted")
	# Damage is credited to who dealt it, and the kill to who hurt the man last.
	report.tally(battle, {}, [{"type": "damage", "unit": 1, "amount": 4, "by": 0}, {"type": "death", "unit": 1}])
	report.tally(battle, {}, [{"type": "damage", "unit": 0, "amount": 2, "by": -1}])
	check_eq(report.sides[0]["damage_dealt"], 4, "damage dealt by the side")
	check_eq(report.sides[0]["kills"], 1, "the kill goes to the shooter's side")
	check_eq(report.units[0]["kills"], 1, "and to the shooter")
	check_eq(report.sides[1]["losses"], 1, "the loss to the other side")
	check_eq(report.sides[0]["damage_other"], 2, "damage nobody dealt is kept apart")


func test_saved_battles_keep_their_replay() -> void:
	var saved_dir := GameSession.save_dir
	GameSession.save_dir = OS.get_temp_dir().path_join("normandy-replay-save-%d" % OS.get_process_id())
	var built: Array = GameSession.build_skirmish({"map": "random", "size": 44, "seed": 77})
	var battle: Battle = built[0]
	battle.max_rounds = 6
	GameSession.war = null
	GameSession.start_battle(battle, [true, true], built[1])
	GameSession.recording = Replay.begin(battle, built[1], "skirmish", ["AI", "AI"])
	GameSession.recording.attach(battle)
	battle.start()
	play_ai(battle, 60)
	var recorded := GameSession.recording.commands.size()
	GameSession.save_game()
	GameSession.recording.detach()
	check(GameSession.load_game("skirmish"), "the skirmish save loads")
	var loaded := GameSession.battle
	check(loaded != battle, "a fresh battle was loaded")
	check(GameSession.recording != null, "the save keeps the replay")
	check_eq(GameSession.recording.commands.size(), recorded, "with every command so far")
	check_eq(GameSession.recording.head, loaded.checksum(), "and it leads to the saved state")
	# Played on after loading, the replay covers the whole battle.
	GameSession.recording.attach(loaded)
	play_ai(loaded)
	check(loaded.winner != -1, "the continued battle ends")
	GameSession.recording.finish(loaded)
	check(GameSession.recording.commands.size() > recorded, "commands after loading are recorded too")
	check_eq(GameSession.recording.verify(), "", "the replay of a continued battle plays out from the very start")
	# Online saves keep it too, and continuing our own save picks it up again.
	var online: Battle = GameSession.build_skirmish({"map": "random", "size": 44, "seed": 78})[0]
	GameSession.start_online_war(_online_war(), 0, "game-r", "1.2.3.4:24944", true)
	GameSession.start_online_battle(online, "Online test")
	GameSession.recording = Replay.begin(online, "Online test", "online", ["You", "Opponent online"])
	GameSession.recording.attach(online)
	online.start()
	play_ai(online, 30)
	recorded = GameSession.recording.commands.size()
	GameSession.save_online(0)
	GameSession.recording.detach()
	check(GameSession.resume_online(GameSession.online_offer(), 0, "", true), "the online save loads")
	check(GameSession.recording != null and GameSession.recording.commands.size() == recorded, "continuing an online game keeps its replay")
	check_eq(GameSession.recording.head, GameSession.battle.checksum(), "the online replay leads to the saved state")
	check_eq(GameSession.recording.verify(), "", "the online replay plays out as recorded")
	GameSession.delete_save("online")
	GameSession.delete_save("skirmish")
	DirAccess.remove_absolute(GameSession.save_dir)
	GameSession.save_dir = saved_dir
	GameSession.online = {}
	GameSession.war = null
	GameSession.battle = null
	GameSession.recording = null


# --- Map generator ---

func test_generated_maps_are_lopsided_but_fair_and_connected() -> void:
	for theatre in Theatres.all():
		for style: Dictionary in theatre.map_styles():
			for seed in [1, 2, 77]:
				for size in [Vector2i(36, 36), Vector2i(46, 46)]:
					var layout := theatre.generate_map(seed, size, style["id"])
					var what := "%s %s seed %d %s" % [theatre.id, style["id"], seed, size]
					check_eq(layout["style"], style["id"], what + ": the style asked for")
					check(theatre.is_playable(layout), what + " is connected")
					check_eq(layout["objectives"].size(), 3, what + ": three objectives")
					check(mirror_mismatches(layout["map"]) > size.x * 4, what + " is no mirror image")
					var imbalance := walk_imbalance(layout)
					check(imbalance < 0.2, what + ": both sides walk about as far to the objectives (%.2f)" % imbalance)
					check(layout["spawns"][0].all(func(p: Vector2i) -> bool: return p.x < 4) and layout["spawns"][1].all(func(p: Vector2i) -> bool: return p.x >= size.x - 4),
							what + ": each side starts on its own edge")
	var a: Dictionary = MapGenerator.generate(9, Vector2i(40, 40))["map"].to_dict()
	var b: Dictionary = MapGenerator.generate(9, Vector2i(40, 40))["map"].to_dict()
	check_eq(a, b, "same seed, same map")
	var styles := {}
	for seed in 8:
		styles[MapGenerator.generate(seed, Vector2i(40, 40))["style"]] = true
	check_eq(styles.size(), MapGenerator.STYLES.size(), "with no style asked for, the seed picks among them all")


# --- Campaign ---

# --- Settings ---

const TEST_SETTINGS := "user://test_settings.cfg"


func test_settings_save_and_load_round_trip() -> void:
	GameSettings.reset()
	check_eq(GameSettings.to_dict(), GameSettings.defaults(), "reset gives the defaults")
	check(not GameSettings.load_settings("user://no_such_settings.cfg"), "a missing file reports false")
	check_eq(GameSettings.to_dict(), GameSettings.defaults(), "a missing file keeps the defaults")
	var changed := {
		"instant_movement": true, "follow_opponent": false, "own_speed": 2, "opponent_speed": 3,
		"pan_speed": 0, "show_hit_chance": false, "confirm_end_turn": true, "fullscreen": true, "music_volume": 4,
	}
	GameSettings.from_dict(changed)
	GameSettings.save_settings(TEST_SETTINGS)
	GameSettings.reset()
	check(GameSettings.load_settings(TEST_SETTINGS), "the saved file loads")
	check_eq(GameSettings.to_dict(), changed, "every setting survives saving and loading")
	check_eq(GameSettings.speed_for(true), 2, "own turns use their own speed")
	check_eq(GameSettings.speed_for(false), 3, "opponent turns use theirs")
	DirAccess.remove_absolute(TEST_SETTINGS)
	GameSettings.reset()


func test_settings_ignore_bad_values() -> void:
	var file := ConfigFile.new()
	file.set_value("settings", "instant_movement", "yes")
	file.set_value("settings", "own_speed", 99)
	file.set_value("settings", "pan_speed", -4)
	file.set_value("settings", "follow_opponent", false)
	file.set_value("settings", "unknown", 1)
	file.save(TEST_SETTINGS)
	check(GameSettings.load_settings(TEST_SETTINGS), "a hand-edited file still loads")
	check_eq(GameSettings.instant_movement, false, "a wrongly typed value falls back to the default")
	check_eq(GameSettings.own_speed, GameSettings.SPEED_NAMES.size() - 1, "speed clamped to the fastest")
	check_eq(GameSettings.pan_speed, 0, "pan speed clamped to the slowest")
	check_eq(GameSettings.follow_opponent, false, "good values are kept")
	DirAccess.remove_absolute(TEST_SETTINGS)
	GameSettings.reset()


# --- Stances, steady shots and suppressive fire ---

func has_modifier(odds: Dictionary, label: String) -> bool:
	for m: Array in odds["modifiers"]:
		if m[0] == label:
			return true
	return false


func test_stances_cost_an_action_and_slow_movement() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Tank", 0, Vector2i(0, 10)], ["Rifleman", 1, Vector2i(15, 15)]])
	var u := battle.units[0]
	check(battle.can_change_stance(u, Unit.Stance.STAND) != "", "already standing")
	check(battle.can_change_stance(u, 3) != "", "not a stance")
	check(battle.can_change_stance(u, 1) != "", "crouching is gone")
	check(battle.can_change_stance(battle.units[1], Unit.Stance.PRONE) != "", "tanks have no stances")
	check(battle.can_change_stance(battle.units[2], Unit.Stance.PRONE) != "", "not on the other side's turn")
	var events := battle.change_stance(u, Unit.Stance.PRONE)
	check_eq(events_of(events, "stance").size(), 1, "stance event")
	check_eq(u.actions, 1, "going prone costs an action")
	check_eq(u.current_mobility(), u.mobility / Unit.STANCE_MOVE_COST[Unit.Stance.PRONE], "prone moves cost x3")
	u.actions = 2
	check(battle.reachable(u).has(Vector2i(4, 0)) and not battle.reachable(u).has(Vector2i(5, 0)), "crawling: 4 tiles on both actions")
	check_eq(u.current_sight(), u.sight - Unit.STANCE_SIGHT[Unit.Stance.PRONE], "prone soldiers see less far")
	u.wounded_turns = 2
	u.suppression = Unit.SUPPRESSED_AT
	check_eq(u.current_mobility(), Unit.MIN_CRAWL, "a slowed soldier can still crawl a tile")
	u.suppression = Unit.PINNED_AT
	check_eq(u.current_mobility(), 0.0, "pinned soldiers can't crawl either")
	u.stance = Unit.Stance.STAND
	check_eq(battle.can_change_stance(u, Unit.Stance.PRONE), "", "pinned soldiers can still get down")


func test_stance_modifiers_in_hit_chance() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 5)], ["Rifleman", 1, Vector2i(8, 5)]])
	var shooter := battle.units[0]
	var target := battle.units[1]
	var base: int = battle.shot_odds(shooter, target)["hit"]
	battle.map.set_object(Vector2i(7, 5), Cover.HALF)
	target.stance = Unit.Stance.PRONE
	var odds := battle.shot_odds(shooter, target)
	check_eq(odds["hit"], base - 20 - CombatRules.PRONE_DEFENSE - CombatRules.PRONE_LOW_COVER_DEFENSE, "prone behind low cover")
	check(has_modifier(odds, "Prone behind low cover"), "prone line")
	shooter.pos = Vector2i(8, 0)
	target.stance = Unit.Stance.STAND
	var flanked: int = battle.shot_odds(shooter, target)["hit"]
	target.stance = Unit.Stance.PRONE
	check_eq(battle.shot_odds(shooter, target)["hit"], flanked + CombatRules.PRONE_FLANKED_PENALTY, "prone and flanked: easier to hit")
	battle.map.set_object(Vector2i(7, 5), Cover.NONE)
	check_eq(battle.shot_odds(shooter, target)["hit"], flanked - CombatRules.PRONE_DEFENSE, "prone in the open at range")
	var reaction_prone: int = battle.shot_odds(shooter, target, true)["hit"]
	target.stance = Unit.Stance.STAND
	check(reaction_prone < battle.shot_odds(shooter, target, true)["hit"], "crawling is safer under overwatch")
	shooter.pos = Vector2i(6, 5)
	var close: int = battle.shot_odds(shooter, target)["hit"]
	target.stance = Unit.Stance.PRONE
	check_eq(battle.shot_odds(shooter, target)["hit"], mini(100, close + CombatRules.PRONE_CLOSE_PENALTY), "prone up close: easy to hit")
	target.stance = Unit.Stance.STAND
	shooter.pos = Vector2i(0, 5)
	shooter.stance = Unit.Stance.PRONE
	check_eq(battle.shot_odds(shooter, target)["hit"], base + CombatRules.PRONE_AIM, "prone shooters aim steadier")
	var mg := Unit.create(9, "MG", "MG", 0, Vector2i(0, 5))
	var mg_base: int = battle.shot_odds(mg, target)["hit"]
	mg.stance = Unit.Stance.PRONE
	check_eq(battle.shot_odds(mg, target)["hit"], mg_base + CombatRules.PRONE_MG_AIM, "a heavy machine gun on its bipod, lying down")


func test_prone_soldiers_cannot_throw_or_fire_rockets() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Officer", 0, Vector2i(2, 4)], ["AT", 0, Vector2i(2, 6)],
			["Mortar", 0, Vector2i(2, 8)], ["Rifleman", 1, Vector2i(9, 2)]])
	for u in battle.alive_units(0):
		u.stance = Unit.Stance.PRONE
	check(battle.can_throw_grenade(battle.units[0], Vector2i(6, 2)) != "", "no grenades lying down")
	check(battle.can_throw_smoke(battle.units[1], Vector2i(6, 4)) != "", "no smoke lying down")
	check(battle.can_fire(battle.units[2]) != "", "no rockets lying down")
	check(battle.can_fire_mortar(battle.units[3], Vector2i(9, 2), "he") != "", "no mortar lying down")
	check_eq(battle.can_shoot(battle.units[0], battle.units[4]), "", "rifles fire fine")
	battle.units[0].stance = Unit.Stance.STAND
	check_eq(battle.can_throw_grenade(battle.units[0], Vector2i(6, 2)), "", "standing soldiers can throw")


func test_prone_in_the_wheat_hides_until_it_fires() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 5)], ["Rifleman", 1, Vector2i(8, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	var viewer := battle.units[0]
	var hidden := battle.units[1]
	battle.map.set_terrain(hidden.pos, TacticalMap.Terrain.WHEAT)
	check(battle.can_see(viewer, hidden), "standing in the wheat: seen")
	hidden.stance = Unit.Stance.PRONE
	check(not battle.can_see(viewer, hidden) and not battle.team_sees(0, hidden), "lying in the wheat: hidden at range")
	viewer.pos = Vector2i(5, 5)
	check(battle.can_see(viewer, hidden), "but not up close")
	viewer.pos = Vector2i(0, 5)
	hidden.fired = true
	check(battle.can_see(viewer, hidden), "the muzzle flash gives him away")
	battle.end_turn()
	check(not hidden.fired, "until his next turn")
	check(not battle.can_see(viewer, hidden), "hidden again")


func test_prone_soldiers_recover_faster() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(5, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	var u := battle.units[0]
	u.suppression = 90
	u.stance = Unit.Stance.PRONE
	battle.end_turn()
	battle.end_turn()
	check_eq(u.suppression, 90 - CombatRules.SUPPRESSION_RECOVERY - CombatRules.PRONE_RECOVERY_BONUS, "lying flat helps")


func test_a_shot_with_both_actions_is_steady() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 5)], ["Rifleman", 1, Vector2i(8, 5)]])
	var u := battle.units[0]
	var target := battle.units[1]
	target.hp = 100
	var normal: int = battle.shot_odds(u, target)["hit"]
	var odds := battle.shot_odds(u, target, false, true)
	check_eq(odds["hit"], normal + CombatRules.STEADY_SHOT_BONUS, "steady shots hit more often")
	check(has_modifier(odds, "Steady shot"), "shown as its own line")
	check(not has_modifier(battle.shot_odds(u, target, true, true), "Steady shot"), "never for reaction fire")
	check(battle.execute({"cmd": "aimed_shot", "unit": u.id, "target": target.id}).is_empty(), "the old aimed shot command is gone")
	check(Battle.is_steady(u), "both actions left: steady")
	var events := battle.execute({"cmd": "shoot", "unit": u.id, "target": target.id})
	var shots := events_of(events, "shot")
	check_eq(shots.size(), 1, "one shot")
	check(shots[0].get("steady", false), "marked as steady")
	check_eq(shots[0]["chance"], normal + CombatRules.STEADY_SHOT_BONUS, "rolled at the steady chance")
	check_eq(u.actions, 0, "ends the turn")
	check_eq(battle.current_team, 1, "and with nobody left to act, the side's turn")
	battle.end_turn()
	battle.move(u, Vector2i(1, 5))
	check(not Battle.is_steady(u), "after moving: not steady")
	events = battle.execute({"cmd": "shoot", "unit": u.id, "target": target.id})
	shots = events_of(events, "shot")
	check(not shots[0].get("steady", false), "a plain shot")
	check_eq(shots[0]["chance"], battle.shot_odds(u, target)["hit"], "rolled at the plain chance")


func test_suppressive_fire_pins_without_damage() -> void:
	var battle := make_battle([["MG", 0, Vector2i(0, 5)], ["AT", 0, Vector2i(0, 9)], ["Rifleman", 1, Vector2i(8, 5)],
			["Rifleman", 1, Vector2i(8, 6)], ["Tank", 1, Vector2i(12, 12)]])
	var mg := battle.units[0]
	var target := battle.units[2]
	check(battle.can_suppress(mg, battle.units[4]) != "", "tanks ignore suppression")
	check(battle.can_suppress(battle.units[1], target) != "", "rockets can't suppress")
	var rifles := make_battle([["Rifleman", 0, Vector2i(0, 5)], ["Rifleman", 1, Vector2i(8, 5)]])
	check_eq(rifles.can_suppress(rifles.units[0], rifles.units[1]), "Only machine gunners lay down suppressive fire", "nor can riflemen")
	mg.ammo = 1
	check(battle.can_suppress(mg, target) != "", "needs two rounds")
	mg.ammo = mg.weapon.clip_size
	var events := battle.execute({"cmd": "suppress", "unit": mg.id, "target": target.id})
	check(not events.is_empty(), "suppressive fire as data")
	check(events_of(events, "damage").is_empty() and target.hp == target.max_hp, "no damage")
	var amount := roundi(mg.weapon.suppression * CombatRules.SUPPRESSIVE_FIRE_FACTOR)
	check_eq(target.suppression, amount, "heavy suppression on the target")
	check_eq(battle.units[3].suppression, mg.weapon.suppression, "and on the man beside him")
	check_eq(mg.ammo, mg.weapon.clip_size - CombatRules.SUPPRESSIVE_FIRE_AMMO, "burns rounds")
	check_eq(mg.actions, 0, "ends the turn")
	battle.end_turn()
	check_eq(target.suppression, amount, "no recovery at the start of their next turn")
	check(not target.under_fire, "only for one turn")
	battle.end_turn()
	battle.end_turn()
	check_eq(target.suppression, amount - CombatRules.SUPPRESSION_RECOVERY, "then it wears off as usual")


func test_stances_replay_and_save() -> void:
	var a := make_battle([["Rifleman", 0, Vector2i(0, 5)], ["Rifleman", 1, Vector2i(8, 5)]])
	var b := make_battle([["Rifleman", 0, Vector2i(0, 5)], ["Rifleman", 1, Vector2i(8, 5)]])
	var command := {"cmd": "stance", "unit": 0, "stance": Unit.Stance.PRONE}
	check(not a.execute(command).is_empty(), "stance change as data")
	check(a.checksum() != b.checksum(), "the stance is part of the checksum")
	b.execute(command)
	check_eq(a.checksum(), b.checksum(), "same commands, same state")
	check(a.execute({"cmd": "stance", "unit": 0, "stance": 7}).is_empty(), "bad stances are rejected")
	a.units[1].under_fire = true
	a.units[1].fired = true
	var copy := Battle.from_dict(a.to_dict())
	check_eq(copy.units[0].stance, Unit.Stance.PRONE, "stance saved")
	check(copy.units[1].under_fire and copy.units[1].fired, "fire state saved")
	check_eq(copy.checksum(), a.checksum(), "identical after loading")
	var crouched := a.units[0].to_dict()
	crouched["stance"] = 1
	check_eq(Unit.from_dict(crouched).stance, Unit.Stance.STAND, "a save from when crouching existed loads standing")
	var old := a.units[0].to_dict()
	old.erase("stance")
	old.erase("fired")
	old.erase("under_fire")
	check_eq(Unit.from_dict(old).stance, Unit.Stance.STAND, "saves from before stances load standing")


func test_ai_uses_stances() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(3, 10)], ["Rifleman", 1, Vector2i(12, 8)], ["Rifleman", 1, Vector2i(12, 12)],
			["MG", 1, Vector2i(13, 10)]], Vector2i(20, 20))
	battle.units[0].suppression = 80
	var command := TacticalAI.new(battle, 0).decide()
	check(command["cmd"] == "stance" and command["stance"] == Unit.Stance.PRONE, "pinned in the open, it gets down (%s)" % command)
	battle = make_battle([["Rifleman", 0, Vector2i(3, 10)], ["Rifleman", 1, Vector2i(19, 19)]], Vector2i(20, 20))
	battle.units[0].stance = Unit.Stance.PRONE
	command = TacticalAI.new(battle, 0).decide()
	check(command["cmd"] == "stance" and command["stance"] == Unit.Stance.STAND, "with nobody in sight, it gets up to move on (%s)" % command)


# --- Two-player campaign ---

func test_war_campaign_maps_and_spend_limits() -> void:
	var war := WarCampaign.create(5, 321)
	check_eq(war.maps.size(), 5, "five maps")
	var values := {}
	for m in war.maps:
		values[m["points"]] = true
	check_eq(values.size(), 5, "every map is worth a different number of points")
	check_eq(war.spend_limits(0), [WarCampaign.MIN_SPEND, WarCampaign.MAX_SPEND] as Array[int], "first map: min and max")
	check(war.check_orders(0, {"roster": ["Rifleman"], "flank": "left", "posture": "offensive"}) != "", "too little supply")
	check(war.check_orders(0, {"roster": ["Tank", "Tank", "Tank", "Rifleman"], "flank": "left", "posture": "offensive"}) != "", "too much supply")
	check(war.check_orders(0, {"roster": ["Rifleman", "Rifleman", "Rifleman", "Rifleman"], "flank": "up", "posture": "offensive"}) != "", "unknown flank")
	check_eq(war.check_orders(0, {"roster": ["Rifleman", "Rifleman", "Rifleman", "Rifleman"], "flank": "right", "posture": "defensive"}), "", "4 riflemen is 12 supply")
	# Late in the campaign the maximum keeps enough back for the maps still to come.
	war.current = 3
	war.supply[0] = 40
	check_eq(war.spend_limits(0), [WarCampaign.MIN_SPEND, 40 - WarCampaign.MIN_SPEND] as Array[int], "leaves the minimum for the last map")
	war.current = 4
	war.supply[0] = 9
	check_eq(war.spend_limits(0), [9, 9] as Array[int], "the last map can only use what is left")


func test_war_campaign_settings_and_income() -> void:
	var settings := {"supply": 60, "income": 20, "min_spend": 10, "max_spend": 30, "max_units": 6, "size": 32}
	var war := WarCampaign.create(3, 55, [false, false], "normandy", settings)
	check_eq(war.supply, [60, 60], "the host's starting supply")
	check(war.maps.all(func(m: Dictionary) -> bool: return m["size"] == 32), "every map is the chosen size")
	check_eq(war.max_units(0), 6, "the host's unit cap")
	check_eq(war.spend_limits(0), [10, 30] as Array[int], "the host's commit limits")
	war.supply[0] = 25
	check_eq(war.spend_limits(0)[1], 25, "income still to come means nothing need be held back")
	war.supply[0] = 60
	var roster := ["Rifleman", "Rifleman", "Rifleman"]
	war.set_orders(0, {"roster": roster, "flank": "left", "posture": "offensive"})
	war.set_orders(1, {"roster": roster, "flank": "left", "posture": "offensive"})
	check(war.build_battle().map.width == 32, "the battle is on the chosen map size")
	var fake := Battle.new(TacticalMap.new(4, 4), [] as Array[Unit])
	fake.winner = 0
	war.complete_map(fake)
	check_eq(war.supply[0], 60 - war.cost_of(0, roster) + 20, "income arrives after the map")
	var copy := WarCampaign.from_dict(war.to_dict())
	check_eq(copy.settings["income"], 20, "settings are saved")
	check_eq(copy.checksum(), war.checksum(), "and load the same campaign")
	var single := WarCampaign.create(1, 9, [false, false])
	check_eq(single.maps.size(), 1, "a one-map campaign is a single battle")
	var orders := {"roster": roster, "flank": "right", "posture": "defensive"}
	var hash := WarCampaign.orders_hash(orders, "salt1")
	check_eq(WarCampaign.orders_hash(orders.duplicate(true), "salt1"), hash, "sealed orders check out when revealed")
	check(WarCampaign.orders_hash({"roster": roster, "flank": "left", "posture": "defensive"}, "salt1") != hash, "changed orders don't")
	check(WarCampaign.orders_hash(orders, "salt2") != hash, "nor another salt")


func test_war_campaign_ai_orders_are_valid() -> void:
	for seed in [1, 2, 3, 4, 5, 6]:
		var war := WarCampaign.create(3 + seed % 3, seed, [true, true])
		while not war.is_over():
			for side in 2:
				if war.has_orders(side):
					continue
				var orders := war.ai_orders(side)
				check_eq(war.set_orders(side, orders), "", "AI orders accepted (seed %d, map %d)" % [seed, war.current])
			if not war.ready_to_fight():
				break
			# Pretend the Allies won, to move on and spend supply.
			var fake := Battle.new(TacticalMap.new(4, 4), [] as Array[Unit])
			fake.winner = 0
			war.complete_map(fake)
		check(war.supply[0] >= 0 and war.supply[1] >= 0, "never overspent")


func test_war_campaign_deployment_and_scoring() -> void:
	var war := WarCampaign.create(3, 77)
	war.set_orders(0, {"roster": ["Officer", "Rifleman", "Rifleman", "MG", "AT"], "flank": "left", "posture": "defensive"})
	war.set_orders(1, {"roster": ["MG", "Rifleman", "SMG"], "flank": "balanced", "posture": "offensive"})
	check(war.ready_to_fight(), "both sides have orders")
	var battle := war.build_battle()
	var size: int = war.current_map()["size"]
	check_eq(battle.alive_units(0).size(), 5, "the Allies field what they bought")
	check_eq(battle.alive_units(1).size(), 3, "and Germany")
	var north := 0
	var sandbags := 0
	for u in battle.alive_units(0):
		north += int(u.pos.y < size / 2)
		check(u.pos.x < size / 2, "Allies deploy on their own half")
		sandbags += int(battle.map.get_object_kind(u.pos + Vector2i(1, 0)) == "sandbags")
	check_eq(north, 5, "left flank for the Allies is north")
	check(sandbags >= 3, "defensive soldiers start behind sandbags (%d)" % sandbags)
	for u in battle.alive_units(1):
		check(u.pos.x >= size / 2, "Germany deploys on its own half")
		check(u.pos.x >= size - 12, "offensive, but still near its edge")
	battle.winner = 1
	battle.victory_points = [3, 9]
	var points: int = war.current_map()["points"]
	var result := war.complete_map(battle)
	check_eq(war.scores, [0, points], "the winner takes the map's points")
	check_eq(result["spent"], [war.cost_of(0, ["Officer", "Rifleman", "Rifleman", "MG", "AT"]), war.cost_of(1, ["MG", "Rifleman", "SMG"])], "supply spent recorded")
	check_eq(war.supply[0], WarCampaign.SUPPLY - result["spent"][0], "spent supply is gone")
	var copy := WarCampaign.from_dict(war.to_dict())
	check_eq(copy.to_dict(), war.to_dict(), "save and load round trip")
	check_eq(copy.current, 1, "on to the next map")


func test_nat_helpers() -> void:
	var transaction := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
	var request := Nat.stun_request(transaction)
	check_eq(request.size(), 20, "STUN request is a bare 20-byte header")
	check_eq(request.slice(8), transaction, "STUN request carries the transaction id")
	# A Binding Success answer with XOR-MAPPED-ADDRESS for 203.0.113.7:41234.
	var answer := PackedByteArray([0x01, 0x01, 0x00, 0x0C, 0x21, 0x12, 0xA4, 0x42])
	answer.append_array(transaction)
	var port := 41234 ^ 0x2112
	answer.append_array([0x00, 0x20, 0x00, 0x08, 0x00, 0x01, port >> 8, port & 0xFF,
			203 ^ 0x21, 0 ^ 0x12, 113 ^ 0xA4, 7 ^ 0x42])
	check_eq(Nat.stun_address(answer, transaction), "203.0.113.7:41234", "STUN answer decodes the XOR-mapped address")
	var other := transaction.duplicate()
	other[0] = 99
	check_eq(Nat.stun_address(answer, other), "", "STUN answer to another request is ignored")
	check_eq(Nat.stun_address(PackedByteArray([1, 2, 3]), transaction), "", "garbage isn't a STUN answer")
	check_eq(Nat.split_address(" 203.0.113.7:41234 ", 24944), ["203.0.113.7", 41234], "address with port")
	check_eq(Nat.split_address("example.org", 24944), ["example.org", 24944], "address without port")
	for local: String in ["127.0.0.1", "192.168.1.20", "10.0.0.5", "172.20.1.1", "100.101.1.2", "localhost"]:
		check(Nat.is_local(local), "%s is on the local network" % local)
	for remote: String in ["203.0.113.7", "172.32.0.1", "8.8.8.8", "example.org"]:
		check(not Nat.is_local(remote), "%s is over the internet" % remote)


func test_online_password_key() -> void:
	var net_script: GDScript = load("res://scripts/net/net_session.gd")
	var key: PackedByteArray = net_script.password_key("fox-hole")
	check_eq(key.size(), 32, "password key is a SHA-256")
	check_eq(key, net_script.password_key("fox-hole"), "the same password gives the same key")
	check(key != net_script.password_key("foxhole"), "a different password gives a different key")


func test_overwatch_holds_fire_on_targets_it_cannot_hurt() -> void:
	# Germany's rifleman watches; an Allied tank and then a rifleman move into view.
	var battle := make_battle([["Tank", 0, Vector2i(2, 8)], ["Rifleman", 0, Vector2i(2, 10)], ["Rifleman", 1, Vector2i(10, 8)]])
	var tank := battle.units[0]
	var watcher := battle.units[2]
	watcher.overwatch = true
	check(not CombatRules.can_hurt(watcher.weapon, tank, watcher.pos), "a rifle can't hurt a tank")
	check(CombatRules.can_hurt(Unit.create(99, "AT", "AT", 1, Vector2i.ZERO).weapon, tank, watcher.pos), "a rocket can")
	var events := battle.execute({"cmd": "move", "unit": tank.id, "tile": Vector2i(4, 8)})
	check_eq(tank.pos, Vector2i(4, 8), "the tank drove into view")
	check(events_of(events, "shot").is_empty(), "rifle overwatch ignores the tank")
	check(watcher.overwatch, "and stays on overwatch")
	events = battle.execute({"cmd": "move", "unit": battle.units[1].id, "tile": Vector2i(4, 10)})
	check_eq(events_of(events, "shot").size(), 1, "but fires at the rifleman")


func test_quick_test_firing_line_on_other_maps() -> void:
	# The quick test page can pick the map kind and size; the line must still give everyone a target.
	var contact := {"flank": "contact", "posture": "normal"}
	for setup: Dictionary in [{"theatre": "normandy", "map": "village"}, {"theatre": "modern", "map": "random", "size": 44, "style": "town"}]:
		setup.merge({"seed": 99, "deployment": [contact, contact], "quick_test": true})
		var battle: Battle = GameSession.build_skirmish(setup)[0]
		for u in battle.units:
			check(BattleFactory.opening_targets(battle, u) > 0, "%s %s: the %s has something to fire at" % [setup["theatre"], setup["map"], u.role])
		var xs := battle.alive_units(0).map(func(u: Unit) -> int: return u.pos.x)
		check(xs.max() < battle.map.width / 2, "%s %s: the first side keeps to its half" % [setup["theatre"], setup["map"]])


func test_quick_test_battle_starts_in_contact() -> void:
	var contact := {"flank": "contact", "posture": "normal"}
	for theatre: String in ["normandy", "vietnam", "modern"]:
		var setup := {"theatre": theatre, "map": "random", "size": 32, "seed": 4242, "deployment": [contact, contact], "quick_test": true}
		var battle: Battle = GameSession.build_skirmish(setup)[0]
		check_eq(battle.map.width, 32, "%s: the quick test map is small" % theatre)
		check_eq(battle.checksum(), GameSession.build_skirmish(setup)[0].checksum(), "%s: the same setup sets out the same line" % theatre)
		var xs := [battle.alive_units(0).map(func(u: Unit) -> int: return u.pos.x), battle.alive_units(1).map(func(u: Unit) -> int: return u.pos.x)]
		check(xs[0].max() < 16 and xs[1].min() >= 16, "%s: each side stays on its own half" % theatre)
		check(xs[0].min() >= 4 and xs[1].max() <= 27, "%s: nobody starts back at the edge" % theatre)
		var covered := 0
		for u in battle.units:
			check(BattleFactory.opening_targets(battle, u) > 0, "%s: the %s has something to fire at" % [theatre, u.role])
			var nearest: Unit = null
			for e in battle.alive_units(1 - u.team):
				if nearest == null or Vector2(u.pos).distance_to(Vector2(e.pos)) < Vector2(u.pos).distance_to(Vector2(nearest.pos)):
					nearest = e
			if battle.map.cover_against(u.pos, nearest.pos) > Cover.NONE:
				covered += 1
		check(covered * 4 >= battle.units.size() * 3, "%s: most start in cover from the nearest enemy (%d of %d)" % [theatre, covered, battle.units.size()])
		battle.start()
		for u in battle.alive_units(battle.current_team):
			var can := battle.alive_units(1 - u.team).any(func(e: Unit) -> bool:
				return battle.can_shoot(u, e) == "" or (not u.indirect.is_empty() and battle.can_fire_mortar(u, e.pos, u.indirect["kinds"][0]) == ""))
			check(can, "%s: the %s can open fire on the first turn" % [theatre, u.role])


func test_skirmish_deployments() -> void:
	var usual: Battle = GameSession.build_skirmish({"map": "random", "size": 44, "seed": 321})[0]
	var spread: Battle = GameSession.build_skirmish({"map": "random", "size": 44, "seed": 321, "deployment": [GameSession.SPREAD_OUT, GameSession.SPREAD_OUT]})[0]
	check_eq(spread.checksum(), usual.checksum(), "no deployment spreads both sides out")
	var spawns: Battle = GameSession.build_skirmish({"map": "random", "size": 44, "seed": 321, "deployment": [{}, {}]})[0]
	check(spawns.checksum() != usual.checksum(), "an empty deployment keeps the grouped usual spawns")
	var ys: Array = usual.alive_units(0).map(func(u: Unit) -> int: return u.pos.y)
	check(ys.max() - ys.min() >= 44 * 0.6, "spread out covers most of the edge")
	var setup := {"map": "random", "size": 44, "seed": 321,
			"deployment": [{"flank": "left", "posture": "offensive"}, {"flank": "balanced", "posture": "defensive"}]}
	var battle: Battle = GameSession.build_skirmish(setup)[0]
	check_eq(battle.checksum(), GameSession.build_skirmish(setup)[0].checksum(), "the same setup builds the same battle")
	var allies := battle.units.filter(func(u: Unit) -> bool: return u.team == 0)
	var germans := battle.units.filter(func(u: Unit) -> bool: return u.team == 1)
	check(allies.all(func(u: Unit) -> bool: return u.pos.y < 44 / 2 + 2), "Allies massed on their left (north)")
	check(battle.units.all(func(u: Unit) -> bool: return u.stance == Unit.Stance.STAND), "everyone starts standing")
	var sandbags := germans.filter(func(u: Unit) -> bool:
		var front: Vector2i = u.pos + Vector2i(-1, 0)
		return battle.map.in_bounds(front) and battle.map.get_object(front) == Cover.HALF)
	check(sandbags.size() >= germans.size() / 2, "defensive Germans mostly start behind sandbags")
	var village: Battle = GameSession.build_skirmish({"map": "village", "seed": 5, "deployment": [{"flank": "right", "posture": "defensive"}, {}]})[0]
	check(village.units.filter(func(u: Unit) -> bool: return u.team == 0).all(func(u: Unit) -> bool: return u.pos.y >= 48 / 2 - 2),
			"the village takes deployments too (Allies' right is south)")
