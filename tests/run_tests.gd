extends SceneTree
## Headless tests for the combat engine.
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


func test_skirmish_map_is_well_formed() -> void:
	for y in SkirmishScenario.LAYOUT.size():
		check_eq(SkirmishScenario.LAYOUT[y].length(), 24, "layout row %d width" % y)
	var battle := SkirmishScenario.build()
	check_eq(battle.alive_units(0).size(), 4, "blue units")
	check_eq(battle.alive_units(1).size(), 4, "red units")


func test_path_costs() -> void:
	var map := TacticalMap.new(10, 10)
	var reach := Pathfinder.search(map, Vector2i(0, 0), 20.0)
	check_eq(reach[Vector2i(3, 0)]["cost"], 3.0, "straight move")
	check_eq(reach[Vector2i(2, 2)]["cost"], 3.0, "diagonals cost 1.5")
	map.set_terrain(Vector2i(1, 0), TacticalMap.Terrain.ROUGH)
	reach = Pathfinder.search(map, Vector2i(0, 0), 20.0)
	check_eq(reach[Vector2i(1, 0)]["cost"], 2.0, "rough ground costs double")


func test_walls_block_and_low_walls_cost_extra() -> void:
	var map := TacticalMap.new(10, 10)
	map.set_edge(Vector2i(0, 0), Vector2i(1, 0), Cover.HALF)
	check_eq(map.step_cost(Vector2i(0, 0), Vector2i(1, 0)), 2.0, "vaulting a low wall")
	map.set_edge(Vector2i(0, 0), Vector2i(1, 0), Cover.FULL)
	check_eq(map.step_cost(Vector2i(0, 0), Vector2i(1, 0)), INF, "full walls block")
	check_eq(map.step_cost(Vector2i(0, 1), Vector2i(1, 0)), INF, "no cutting wall corners")
	map.set_object(Vector2i(5, 5), Cover.HALF)
	check_eq(map.step_cost(Vector2i(4, 4), Vector2i(5, 4)), 1.0, "beside a crate is fine")
	check_eq(map.step_cost(Vector2i(4, 4), Vector2i(5, 5)), INF, "can't stand on a crate")
	check_eq(map.step_cost(Vector2i(4, 5), Vector2i(5, 4)), INF, "no cutting crate corners")


func test_units_block_paths() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 1, Vector2i(1, 0)]])
	check(not battle.reachable(battle.units[0]).has(Vector2i(1, 0)), "can't move onto a unit")


func test_line_of_sight() -> void:
	var map := TacticalMap.new(12, 12)
	map.set_object(Vector2i(4, 5), Cover.HALF)
	check(LineOfSight.has_line(map, Vector2i(2, 5), Vector2i(7, 5)), "half cover doesn't block sight")
	map.set_object(Vector2i(4, 5), Cover.FULL)
	check(not LineOfSight.has_line(map, Vector2i(1, 5), Vector2i(7, 5)), "full cover blocks sight")
	map.set_object(Vector2i(4, 5), Cover.NONE)
	map.set_edge(Vector2i(4, 5), Vector2i(5, 5), Cover.FULL)
	check(not LineOfSight.has_line(map, Vector2i(1, 5), Vector2i(7, 5)), "walls block sight")
	check(LineOfSight.has_line(map, Vector2i(1, 1), Vector2i(7, 1)), "line clear of the wall")


func test_step_out_around_corner() -> void:
	var map := TacticalMap.new(12, 12)
	map.set_object(Vector2i(3, 5), Cover.FULL)
	check(not LineOfSight.has_line(map, Vector2i(2, 5), Vector2i(6, 5)), "direct line blocked")
	check(LineOfSight.can_see(map, Vector2i(2, 5), Vector2i(6, 5), 12.0), "stepping out sees round it")
	check(not LineOfSight.can_see(map, Vector2i(2, 5), Vector2i(10, 5), 6.0), "sight range limits")


func test_directional_cover_and_flanking() -> void:
	var map := TacticalMap.new(12, 12)
	map.set_object(Vector2i(6, 5), Cover.HALF)
	check_eq(map.cover_against(Vector2i(5, 5), Vector2i(10, 5)), Cover.HALF, "cover faces attacker")
	check_eq(map.cover_against(Vector2i(5, 5), Vector2i(10, 2)), Cover.HALF, "cover at an angle")
	check_eq(map.cover_against(Vector2i(5, 5), Vector2i(5, 0)), Cover.NONE, "flanked from the north")
	check_eq(map.cover_against(Vector2i(5, 5), Vector2i(1, 5)), Cover.NONE, "flanked from behind")
	map.set_edge(Vector2i(5, 5), Vector2i(5, 4), Cover.FULL)
	check_eq(map.cover_against(Vector2i(5, 5), Vector2i(5, 0)), Cover.FULL, "wall covers the north")


func test_hit_chance() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(1, 5)], ["Rifleman", 1, Vector2i(5, 5)]])
	battle.map.set_object(Vector2i(4, 5), Cover.HALF)
	var shooter := battle.units[0]
	var target := battle.units[1]
	var odds := battle.shot_odds(shooter, target)
	check_eq(odds["hit"], 65 + 6 - 20, "aim + range - half cover")
	check(not odds["flanked"], "not flanked behind cover")
	target.hunkered = true
	check_eq(battle.shot_odds(shooter, target)["hit"], 65 + 6 - 40, "hunkering doubles cover")
	target.hunkered = false
	shooter.pos = Vector2i(5, 1)
	odds = battle.shot_odds(shooter, target)
	check(odds["flanked"], "flanked from the side")
	check_eq(odds["crit"], 10 + CombatRules.FLANK_CRIT_BONUS, "flank crit bonus")
	var reaction := battle.shot_odds(shooter, target, true)
	check_eq(reaction["hit"], roundi((65 + 6) * 0.7), "reaction shot penalty")


func test_move_and_dash_spend_actions() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 1, Vector2i(15, 15)]])
	var u := battle.units[0]
	battle.move(u, Vector2i(5, 0))
	check_eq(u.actions, 1, "short move costs one action")
	check_eq(u.pos, Vector2i(5, 0), "moved")
	check(battle.reachable(u).has(Vector2i(12, 0)), "can still move 7")
	check(not battle.reachable(u).has(Vector2i(13, 0)), "but not 8")

	battle = make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 0, Vector2i(0, 15)], ["Rifleman", 1, Vector2i(15, 15)]])
	u = battle.units[0]
	battle.move(u, Vector2i(12, 0))
	check_eq(u.actions, 0, "dash costs both actions")
	check_eq(battle.current_team, 0, "turn continues while a teammate can act")


func test_shooting_ends_turn_and_uses_ammo() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 0, Vector2i(0, 2)], ["Rifleman", 1, Vector2i(5, 0)]])
	var u := battle.units[0]
	var events := battle.shoot(u, battle.units[2])
	check_eq(u.actions, 0, "shooting ends the unit's turn")
	check_eq(u.ammo, 3, "shot used ammo")
	check_eq(events[0]["type"], "shot", "shot event")
	check(battle.shoot(u, battle.units[2]).is_empty(), "can't shoot again")


func test_auto_end_turn_and_status_reset() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 1, Vector2i(15, 15)]])
	var red := battle.units[1]
	red.overwatch = true
	var events := battle.overwatch(battle.units[0])
	check_eq(events.back()["type"], "turn", "turn ends when nobody can act")
	check_eq(battle.current_team, 1, "red's turn")
	check(not red.overwatch, "overwatch clears at the start of the owner's turn")
	check_eq(red.actions, 2, "red has fresh actions")
	check(battle.units[0].overwatch, "blue still on overwatch")


func test_overwatch_interrupts_movement() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 8)], ["Rifleman", 1, Vector2i(10, 8)], ["Rifleman", 1, Vector2i(15, 15)]])
	var watcher := battle.units[0]
	battle.overwatch(watcher)
	check_eq(battle.current_team, 1, "red's turn")
	var mover := battle.units[1]
	var events := battle.move(mover, Vector2i(8, 8))
	var reactions := events.filter(func(e: Dictionary) -> bool: return e["type"] == "shot" and e["reaction"])
	check_eq(reactions.size(), 1, "exactly one overwatch shot")
	check(not watcher.overwatch, "overwatch is used up")
	check_eq(watcher.ammo, 3, "overwatch shot used ammo")


func test_grenade_destroys_cover_and_shreds() -> void:
	var battle := make_battle([["Heavy", 0, Vector2i(2, 5)], ["Heavy", 1, Vector2i(7, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	battle.map.set_object(Vector2i(6, 5), Cover.HALF)
	battle.map.set_edge(Vector2i(7, 5), Vector2i(7, 6), Cover.FULL)
	var target := battle.units[1]
	var events := battle.throw_grenade(battle.units[0], Vector2i(7, 5))
	check_eq(events[0]["type"], "explosion", "explosion event")
	check_eq(battle.map.get_object(Vector2i(6, 5)), Cover.NONE, "crate destroyed")
	check_eq(battle.map.get_terrain(Vector2i(6, 5)), TacticalMap.Terrain.RUBBLE, "leaves rubble")
	check_eq(battle.map.get_edge(Vector2i(7, 5), Vector2i(7, 6)), Cover.NONE, "wall destroyed")
	check_eq(target.armor, 0, "armor shredded")
	check(target.hp <= target.max_hp - CombatRules.GRENADE_DAMAGE_MIN, "grenade damage ignores shredded armor")
	check_eq(battle.units[0].grenades, 1, "grenade used")
	check(battle.throw_grenade(battle.units[0], Vector2i(15, 5)).is_empty(), "turn already over")


func test_grenade_needs_range_and_sight() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 1, Vector2i(15, 15)]], Vector2i(24, 24))
	var u := battle.units[0]
	check(battle.can_throw_grenade(u, Vector2i(10, 0)) == "", "in range")
	check(battle.can_throw_grenade(u, Vector2i(11, 0)) != "", "out of range")
	battle.map.set_edge(Vector2i(2, 0), Vector2i(3, 0), Cover.FULL)
	battle.map.set_edge(Vector2i(2, 1), Vector2i(3, 1), Cover.FULL)
	check(battle.can_throw_grenade(u, Vector2i(5, 0)) != "", "behind a wall")


func test_medkit() -> void:
	var battle := make_battle([["Medic", 0, Vector2i(0, 0)], ["Rifleman", 0, Vector2i(1, 1)], ["Rifleman", 1, Vector2i(15, 15)]])
	var patient := battle.units[1]
	check(battle.can_use_medkit(battle.units[0], patient) != "", "can't heal a healthy unit")
	patient.hp = 2
	battle.use_medkit(battle.units[0], patient)
	check_eq(patient.hp, 6, "healed 4")
	check_eq(battle.units[0].actions, 1, "medkit doesn't end the turn")


func test_armor_absorbs_damage() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Heavy", 1, Vector2i(15, 15)]])
	var heavy := battle.units[1]
	var events := battle._damage(heavy, 4, 0)
	check_eq(events[0]["absorbed"], 1, "armor absorbs one")
	check_eq(heavy.hp, 6, "took 3")


func test_victory() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 1, Vector2i(1, 0)]])
	battle.units[1].hp = 1
	battle.units[1].armor = 0
	var events := []
	for i in 50:
		if battle.winner != -1:
			break
		if battle.current_team == 1:
			battle.end_turn()
		else:
			events = battle.shoot(battle.units[0], battle.units[1])
	check_eq(battle.winner, 0, "blue wins")
	check_eq(events.back()["type"], "game_over", "game over event")
	check(battle.end_turn().is_empty(), "no more turns")


func test_seeded_battles_are_deterministic() -> void:
	var outcomes := []
	for i in 2:
		var battle := make_battle([["Rifleman", 0, Vector2i(0, 0)], ["Rifleman", 0, Vector2i(0, 1)], ["Heavy", 1, Vector2i(9, 0)]])
		var results := []
		for j in 4:
			var e := battle.shoot(battle.units[j % 2], battle.units[2])
			results.append(e[0]["result"] if not e.is_empty() else "-")
			if battle.current_team == 1:
				battle.end_turn()
		outcomes.append(results)
	check_eq(outcomes[0], outcomes[1], "same seed, same results")
