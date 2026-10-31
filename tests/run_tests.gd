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
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(7, 5)], ["Rifleman", 1, Vector2i(15, 15)]])
	battle.map.set_object(Vector2i(6, 5), Cover.HALF)
	battle.map.set_edge(Vector2i(7, 5), Vector2i(7, 6), Cover.FULL)
	var target := battle.units[1]
	target.armor = 1
	var events := battle.throw_grenade(battle.units[0], Vector2i(7, 5))
	check_eq(events[0]["type"], "explosion", "explosion event")
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
	map.set_object(Vector2i(6, 6), Cover.FULL, "tree")
	var tank := battle.units[0]
	check(not battle.reachable(tank).has(Vector2i(6, 6)), "trees stop tanks")
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
