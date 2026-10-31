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

func test_normandy_map_is_symmetric_and_connected() -> void:
	var battle := NormandyScenario.build()
	var map := battle.map
	var mismatches := 0
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var m := Vector2i(map.width - 1 - x, y)
			if map.get_terrain(p) != map.get_terrain(m) or map.get_object(p) != map.get_object(m) \
					or map.get_edge(p, p + Vector2i(1, 0)) != map.get_edge(m, m + Vector2i(-1, 0)) \
					or map.get_edge(p, p + Vector2i(0, 1)) != map.get_edge(m, m + Vector2i(0, 1)):
				mismatches += 1
	check_eq(mismatches, 0, "map mirrors left to right")
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
	s.mirrored = false
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
	s.units.append(Scenario.unit_entry(0, "Tank", Vector2i(1, 7), Vector2i(1, -1)))
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
	check_eq(battle.get_unit(1).facing, Vector2i(1, -1), "tanks keep a diagonal facing")
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
	check(exported.mirrored, "a generated map is recognised as mirrored")
	check(exported.validate().is_empty(), "an exported generated map is valid: %s" % exported.validate())

	# Swapping the sides twice gives back the original.
	var twice := s.swapped().swapped()
	twice.title = s.title
	check_eq(twice.to_json(), s.to_json(), "swapping sides twice changes nothing")
	var swapped := s.swapped()
	check_eq(swapped.units[0]["team"], 0, "the German force now plays for the Allies")
	check_eq(swapped.units[0]["pos"], Vector2i(1, 4), "from the other side of the map")

	# Building half a map and mirroring it.
	var half := Scenario.create(10, 8)
	half.map.set_object(Vector2i(2, 2), Cover.FULL, "rock")
	half.map.set_edge(Vector2i(3, 5), Vector2i(4, 5), Cover.HALF, "stone")
	half.map.set_edge(Vector2i(4, 1), Vector2i(5, 1), Cover.FULL, "wall")
	half.map.set_object(Vector2i(8, 7), Cover.HALF, "crate")
	half.objectives.append({"name": "Mill", "center": Vector2(5, 4), "radius": 2.0})
	half.objectives.append({"name": "Copse", "center": Vector2(2, 6), "radius": 1.5})
	half.units.append(Scenario.unit_entry(0, "Rifleman", Vector2i(1, 3)))
	half.units.append(Scenario.unit_entry(1, "SMG", Vector2i(8, 3)))
	check(not half.is_symmetric(), "a half-built map isn't symmetric")
	half.mirror_west_to_east()
	check(half.is_symmetric(), "mirroring the west half makes it symmetric")
	check_eq(half.map.get_object(Vector2i(7, 2)), Cover.FULL, "objects are mirrored")
	check_eq(half.map.get_object(Vector2i(8, 7)), Cover.NONE, "the east half is replaced")
	check_eq(half.map.get_edge(Vector2i(5, 5), Vector2i(6, 5)), Cover.HALF, "walls are mirrored")
	check_eq(half.map.get_edge(Vector2i(4, 1), Vector2i(5, 1)), Cover.FULL, "a wall on the centre line stays")
	check_eq(half.objectives.size(), 3, "objectives off the centre line are mirrored")
	check_eq(half.units.size(), 2, "the Allied units are mirrored for Germany")
	check_eq(half.units[1]["pos"], Vector2i(8, 3), "onto the mirror tile")
	check_eq(half.units[1]["facing"], Vector2i(-1, 0), "facing west")
	check(Scenario.from_data({"map": {"width": 2}}) == null, "a bad file is refused")


func test_village_scenario_builds_the_village() -> void:
	var scenario := Scenario.load_file("res://scenarios/village.json")
	check(scenario != null, "bundled village scenario loads: %s" % Scenario.last_error)
	if scenario == null:
		return
	check(scenario.validate().is_empty(), "village scenario is valid: %s" % scenario.validate())
	check(scenario.is_symmetric(), "village scenario is mirrored")
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
	check(not LineOfSight.has_line(map, Vector2i(0, 0), Vector2i(5, 0)), "hedges block sight")
	check_eq(map.step_cost(Vector2i(0, 1), Vector2i(1, 0)), INF, "no cutting corners")
	map.set_object(Vector2i(5, 5), Cover.HALF)
	check_eq(map.step_cost(Vector2i(4, 4), Vector2i(5, 5)), INF, "can't stand on a crate")


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
	check_eq(battle.shot_odds(shooter, target)["hit"], 65 + 6 - 20, "aim + range - half cover")
	target.hunkered = true
	check_eq(battle.shot_odds(shooter, target)["hit"], 65 + 6 - 40, "hunkering doubles cover")
	target.hunkered = false
	shooter.suppression = Unit.SUPPRESSED_AT
	check_eq(battle.shot_odds(shooter, target)["hit"], 65 + 6 - 20 - CombatRules.SUPPRESSED_AIM_PENALTY, "suppressed shooters aim worse")
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


func test_machine_gun_needs_setup_and_suppresses_an_area() -> void:
	var battle := make_battle([["MG", 0, Vector2i(2, 5)], ["Rifleman", 0, Vector2i(0, 15)], ["Rifleman", 1, Vector2i(9, 5)], ["Rifleman", 1, Vector2i(9, 6)]])
	var mg := battle.units[0]
	check(battle.can_shoot(mg, battle.units[2]) != "", "MG can't fire before setting up")
	battle.set_up(mg)
	check(battle.can_shoot(mg, battle.units[2]) == "", "set up, it can")
	battle.units[2].hp = 100
	battle.shoot(mg, battle.units[2])
	check(battle.units[3].suppression >= mg.weapon.suppression / 2, "neighbours are suppressed too")
	battle.end_turn()
	battle.end_turn()
	battle.move(mg, Vector2i(3, 5))
	check(not mg.deployed, "moving packs the gun away")


func test_reaction_fire_can_pin_a_runner() -> void:
	var battle := make_battle([["MG", 0, Vector2i(0, 8)], ["Rifleman", 1, Vector2i(10, 8)], ["Rifleman", 1, Vector2i(15, 15)]])
	var mg := battle.units[0]
	mg.deployed = true
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
	check_eq(battle.map.get_edge(Vector2i(7, 5), Vector2i(7, 6)), Cover.NONE, "wall destroyed")
	check_eq(battle.map.get_terrain(Vector2i(7, 5)), TacticalMap.Terrain.CRATER, "crater at the centre")
	check_eq(target.armor, 0, "armor shredded")
	var suppressed := events_of(events, "suppression").filter(func(e: Dictionary) -> bool: return e["unit"] == target.id and e["value"] >= CombatRules.EXPLOSION_SUPPRESSION)
	check(not suppressed.is_empty() or not target.is_alive(), "blast suppresses")


func test_mortar_needs_a_spotter_and_lands_next_turn() -> void:
	var battle := make_battle([["Mortar", 0, Vector2i(0, 8)], ["Rifleman", 0, Vector2i(10, 8)], ["Rifleman", 1, Vector2i(15, 8)], ["Rifleman", 1, Vector2i(15, 0)]], Vector2i(24, 16))
	var mortar := battle.units[0]
	check(battle.can_fire_mortar(mortar, Vector2i(2, 8), "he") != "", "minimum range")
	check(battle.can_fire_mortar(mortar, Vector2i(15, 8), "he") == "", "spotted target in range")
	for y in battle.map.height:
		battle.map.set_edge(Vector2i(11, y), Vector2i(12, y), Cover.FULL)
	check(battle.can_fire_mortar(mortar, Vector2i(15, 8), "he") != "", "nobody can see behind the wall")
	for y in battle.map.height:
		battle.map.set_edge(Vector2i(11, y), Vector2i(12, y), Cover.NONE)
	var moved := make_battle([["Mortar", 0, Vector2i(0, 8)], ["Rifleman", 0, Vector2i(0, 9)], ["Rifleman", 1, Vector2i(15, 8)]], Vector2i(24, 16))
	moved.move(moved.units[0], Vector2i(1, 8))
	check(moved.can_fire_mortar(moved.units[0], Vector2i(15, 8), "he") != "", "can't fire after moving")

	var events := battle.fire_mortar(mortar, Vector2i(15, 8), "he")
	check_eq(events[0]["type"], "mortar_fire", "shell fired")
	check_eq(battle.strikes.size(), 1, "shell in the air")
	check(events_of(events, "explosion").is_empty(), "nothing lands this turn")
	var landing := battle.end_turn()
	landing.append_array(battle.end_turn())
	var strikes := events_of(landing, "strike")
	check_eq(strikes.size(), 1, "lands at the start of our next turn")
	if not strikes.is_empty():
		var center: Vector2i = strikes[0]["center"]
		check(Vector2(center).distance_to(Vector2(15, 8)) <= Battle.mortar_scatter(Vector2i(0, 8), Vector2i(15, 8)) + 1.0, "within scatter")


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
	check_eq(patient.hp, 6, "healed 4")
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


func test_ai_sets_up_its_machine_gun() -> void:
	var battle := make_battle([["MG", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(10, 5)]])
	var ai := TacticalAI.new(battle, 0)
	var events := []
	while battle.current_team == 0 and battle.winner == -1:
		events.append_array(ai.act())
	check(not events_of(events, "shot").is_empty() or battle.units[0].deployed, "MG sets up to fire")


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
	check_eq(battle.can_pivot(tank, Vector2i(0, 1)), "Already facing that way", "no turning to the same facing")
	var actions := tank.actions
	battle.pivot(tank, Vector2i(-1, -1))
	check_eq(tank.facing, Vector2i(-1, -1), "pivots on the spot")
	check_eq(tank.actions, actions - 1, "a pivot costs an action")
	var soldier := make_battle([["Rifleman", 0, Vector2i(8, 8)], ["Rifleman", 1, Vector2i(15, 15)]])
	check(soldier.can_pivot(soldier.units[0], Vector2i(0, 1)) != "", "only tanks pivot")


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


func test_big_skirmish_maps() -> void:
	for size in [64, 84]:
		var built := GameSession.build_skirmish({"map": "random", "size": size, "seed": 4242})
		var battle: Battle = built[0]
		check_eq(battle.map.width, size, "map is %d wide" % size)
		check(battle.units.size() >= (12 if size == 64 else 15) * 2, "bigger forces on %dx%d" % [size, size])
		var layout := MapGenerator.generate(4242, Vector2i(size, size))
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
		units[0].deployed = true
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


func test_odds_info_lists_the_stray_risk() -> void:
	var battle := make_battle([["MG", 0, Vector2i(2, 8)], ["Rifleman", 1, Vector2i(9, 8)], ["Rifleman", 0, Vector2i(9, 9)]])
	battle.units[0].deployed = true
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
	mg.deployed = true
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
	GameSession.start_online(battle, "Test map", 1, "game-1", "1.2.3.4:24944", false)
	GameSession.save_online(1)
	var offer := GameSession.online_offer()
	check_eq(offer.get("checksum"), battle.checksum(), "the online save keeps the checksum")
	check_eq(offer.get("team"), 1, "the save knows our side")
	check_eq(GameSession.compare_online(offer), "", "our own save matches itself")
	var other := offer.duplicate()
	other["game_id"] = "game-2"
	check(GameSession.compare_online(other) != "", "a different game is noticed")
	var later := offer.duplicate()
	later["checksum"] = "x"
	later["turn_index"] = offer["turn_index"] + 2
	check(GameSession.compare_online(later).contains("older"), "an older save of ours is noticed")
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
	check_eq(GameSession.peek("online")["checksum"], copy.checksum(), "an agreed turn change is saved")
	copy.winner = 0
	GameSession.save_online(0)
	check(not GameSession.has_save("online"), "a finished online battle clears its save")
	DirAccess.remove_absolute(GameSession.save_dir)
	GameSession.save_dir = saved_dir
	GameSession.online = {}
	GameSession.battle = null


# --- Map generator ---

func test_generated_maps_are_fair_and_connected() -> void:
	for seed in [1, 2, 3, 4, 5, 77, 1234]:
		for size in [Vector2i(36, 36), Vector2i(46, 46)]:
			var layout := MapGenerator.generate(seed, size)
			var map: TacticalMap = layout["map"]
			check(MapGenerator.is_playable(layout), "seed %d %s is connected" % [seed, size])
			var mismatches := 0
			for y in map.height:
				for x in map.width:
					var p := Vector2i(x, y)
					var m := Vector2i(map.width - 1 - x, y)
					if map.get_terrain(p) != map.get_terrain(m) or map.get_object(p) != map.get_object(m) \
							or map.get_edge(p, p + Vector2i(0, 1)) != map.get_edge(m, m + Vector2i(0, 1)):
						mismatches += 1
			check_eq(mismatches, 0, "seed %d %s is mirrored" % [seed, size])
	var a: Dictionary = MapGenerator.generate(9, Vector2i(40, 40))["map"].to_dict()
	var b: Dictionary = MapGenerator.generate(9, Vector2i(40, 40))["map"].to_dict()
	check_eq(a, b, "same seed, same map")


# --- Campaign ---

func test_campaign_mission_updates_the_roster() -> void:
	var campaign := Campaign.create(5)
	check_eq(campaign.deployable().size(), 8, "full squad deploys")
	var battle := campaign.build_battle(11)
	var ours := battle.alive_units(0)
	check_eq(ours.size(), 8, "squad on the field")
	check_eq(ours[0].role, "Officer", "officer leads")
	ours[1].hp = 0
	ours[2].kills = 3
	ours[3].hp = 1
	battle.winner = 0
	var report := campaign.complete_mission(battle)
	check(report["won"], "mission won")
	check_eq(campaign.mission_index, 1, "on to mission two")
	check_eq(campaign.supplies, Campaign.STARTING_SUPPLIES + Campaign.WIN_SUPPLIES, "supplies earned")
	var dead := campaign._soldier(ours[1].record_id)
	var veteran := campaign._soldier(ours[2].record_id)
	var hurt := campaign._soldier(ours[3].record_id)
	check_eq(dead["status"], "dead", "the dead stay dead")
	check_eq(veteran["xp"], 4, "xp from the mission and kills")
	check_eq(veteran["rank"], 1, "promoted to corporal")
	check_eq(hurt["status"], "recovering", "badly wounded sits out")
	check(not campaign.deployable().has(hurt), "not deployable while recovering")
	var recruit := campaign.recruit("Mortar")
	check_eq(recruit["role"], "Mortar", "recruited a replacement")
	check_eq(campaign.supplies, Campaign.STARTING_SUPPLIES + Campaign.WIN_SUPPLIES - Campaign.RECRUIT_COST, "recruiting costs supplies")
	var promoted := campaign.build_battle(12).units.filter(func(u: Unit) -> bool: return u.record_id == veteran["id"])
	check_eq(promoted[0].aim, 65 + Unit.RANK_AIM, "rank improves aim in battle")
	var restored := Campaign.from_dict(campaign.to_dict())
	check_eq(restored.to_dict(), campaign.to_dict(), "campaign saves and loads")
	battle = campaign.build_battle(13)
	battle.winner = 1
	campaign.complete_mission(battle)
	check_eq(hurt["status"], "ready", "back after sitting one out")
	check_eq(campaign.mission_index, 1, "a lost mission is retried")


func test_every_campaign_mission_builds() -> void:
	var campaign := Campaign.create(3)
	for i in Campaign.MISSIONS.size():
		campaign.mission_index = i
		var battle := campaign.build_battle(i + 1)
		var mission: Dictionary = Campaign.MISSIONS[i]
		check_eq(battle.alive_units(1).size(), mission["enemy"].size(), "%s enemy force" % mission["name"])
		check_eq(battle.objectives.size(), 3, "%s objectives" % mission["name"])


# --- Settings ---

const TEST_SETTINGS := "user://test_settings.cfg"


func test_settings_save_and_load_round_trip() -> void:
	GameSettings.reset()
	check_eq(GameSettings.to_dict(), GameSettings.defaults(), "reset gives the defaults")
	check(not GameSettings.load_settings("user://no_such_settings.cfg"), "a missing file reports false")
	check_eq(GameSettings.to_dict(), GameSettings.defaults(), "a missing file keeps the defaults")
	var changed := {
		"instant_movement": true, "follow_opponent": false, "own_speed": 2, "opponent_speed": 3,
		"pan_speed": 0, "show_hit_chance": false, "confirm_end_turn": true, "fullscreen": true,
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


# --- Stances, aimed shots and suppressive fire ---

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
	check(battle.can_change_stance(battle.units[1], Unit.Stance.CROUCH) != "", "tanks have no stances")
	check(battle.can_change_stance(battle.units[2], Unit.Stance.CROUCH) != "", "not on the other side's turn")
	var events := battle.change_stance(u, Unit.Stance.CROUCH)
	check_eq(events_of(events, "stance").size(), 1, "stance event")
	check_eq(u.actions, 1, "crouching costs an action")
	check_eq(u.current_mobility(), u.mobility / Unit.STANCE_MOVE_COST[Unit.Stance.CROUCH], "crouched moves cost x1.5")
	check(battle.reachable(u).has(Vector2i(4, 0)) and not battle.reachable(u).has(Vector2i(5, 0)), "crouched: 4 tiles on one action")
	battle.change_stance(u, Unit.Stance.PRONE)
	check_eq(u.actions, 0, "going prone costs an action")
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
	target.stance = Unit.Stance.CROUCH
	var odds := battle.shot_odds(shooter, target)
	check_eq(odds["hit"], base - CombatRules.CROUCH_DEFENSE, "crouched targets are harder to hit")
	check(has_modifier(odds, "Crouched"), "shown as its own line")
	battle.map.set_object(Vector2i(7, 5), Cover.HALF)
	check_eq(battle.shot_odds(shooter, target)["hit"], base - 20 - CombatRules.CROUCH_HALF_COVER_DEFENSE, "crouching behind half cover counts more")
	target.stance = Unit.Stance.PRONE
	odds = battle.shot_odds(shooter, target)
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
	shooter.stance = Unit.Stance.CROUCH
	check_eq(battle.shot_odds(shooter, target)["hit"], base + CombatRules.CROUCH_AIM, "crouched shooters aim steadier")
	shooter.stance = Unit.Stance.PRONE
	check_eq(battle.shot_odds(shooter, target)["hit"], base + CombatRules.PRONE_AIM, "and prone ones")
	var mg := Unit.create(9, "MG", "MG", 0, Vector2i(0, 5))
	var mg_base: int = battle.shot_odds(mg, target)["hit"]
	mg.stance = Unit.Stance.PRONE
	mg.deployed = true
	check_eq(battle.shot_odds(mg, target)["hit"], mg_base + CombatRules.PRONE_MG_AIM, "a machine gun on its bipod, lying down")


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
	battle.units[0].stance = Unit.Stance.CROUCH
	check_eq(battle.can_throw_grenade(battle.units[0], Vector2i(6, 2)), "", "crouched soldiers can throw")


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


func test_aimed_shot_takes_both_actions() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 5)], ["Rifleman", 1, Vector2i(8, 5)]])
	var u := battle.units[0]
	var target := battle.units[1]
	target.hp = 100
	var normal: int = battle.shot_odds(u, target)["hit"]
	var odds := battle.shot_odds(u, target, false, true)
	check_eq(odds["hit"], normal + CombatRules.AIMED_SHOT_BONUS, "aimed shots hit more often")
	check(has_modifier(odds, "Aimed shot"), "shown as its own line")
	u.actions = 1
	check(battle.can_aimed_shot(u, target) != "", "needs both actions")
	check(battle.execute({"cmd": "aimed_shot", "unit": u.id, "target": target.id}).is_empty(), "rejected as data too")
	u.actions = 2
	var events := battle.execute({"cmd": "aimed_shot", "unit": u.id, "target": target.id})
	var shots := events_of(events, "shot")
	check_eq(shots.size(), 1, "one shot")
	check(shots[0].get("aimed", false), "marked as aimed")
	check_eq(shots[0]["chance"], normal + CombatRules.AIMED_SHOT_BONUS, "rolled at the aimed chance")
	check_eq(u.actions, 0, "ends the turn")
	check(u.fired, "the shooter has fired")


func test_suppressive_fire_pins_without_damage() -> void:
	var battle := make_battle([["MG", 0, Vector2i(0, 5)], ["AT", 0, Vector2i(0, 9)], ["Rifleman", 1, Vector2i(8, 5)],
			["Rifleman", 1, Vector2i(8, 6)], ["Tank", 1, Vector2i(12, 12)]])
	var mg := battle.units[0]
	var target := battle.units[2]
	check(battle.can_suppress(mg, target) != "", "the MG must be set up")
	mg.deployed = true
	check(battle.can_suppress(mg, battle.units[4]) != "", "tanks ignore suppression")
	check(battle.can_suppress(battle.units[1], target) != "", "rockets can't suppress")
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
	war.set_orders(1, {"roster": ["Tank", "Rifleman", "SMG"], "flank": "balanced", "posture": "offensive"})
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
		check_eq(u.stance, Unit.Stance.CROUCH, "a defensive deployment starts crouched")
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
	check_eq(result["spent"], [WarCampaign.cost_of(["Officer", "Rifleman", "Rifleman", "MG", "AT"]), WarCampaign.cost_of(["Tank", "Rifleman", "SMG"])], "supply spent recorded")
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
