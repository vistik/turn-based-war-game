extends SceneTree
## Headless tests for terrain hazards: fuel drums and oil tanks, fire, mines, trampled wheat and barbed wire.
## Run: Godot --headless --path . -s tests/terrain_tests.gd

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


# --- Fuel drums, oil tanks and fire ---

func test_shooting_fuel_drums_blows_them_up() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(8, 5)], ["Rifleman", 1, Vector2i(14, 14)]])
	var shooter := battle.units[0]
	var enemy := battle.units[1]
	battle.map.set_object(Vector2i(8, 6), Cover.HALF, "fuel")
	check(battle.map.is_explosive(Vector2i(8, 6)), "fuel drums are explosive")
	check(battle.can_shoot_object(shooter, Vector2i(9, 9)) != "", "nothing to shoot at on an empty tile")
	check_eq(battle.can_shoot_object(shooter, Vector2i(8, 6)), "", "drums in sight can be shot")
	var odds := CombatRules.object_odds(shooter, shooter.pos, Vector2i(8, 6), "fuel")
	check(odds > 50, "drums are easy to hit (%d%%)" % odds)
	# Keep firing (with fresh turns) until a round hits.
	var events := []
	for i in 20:
		shooter.actions = 2
		shooter.ammo = shooter.weapon.clip_size
		battle.current_team = 0
		events = battle.execute({"cmd": "shoot_object", "unit": shooter.id, "tile": Vector2i(8, 6)})
		if not events_of(events, "detonation").is_empty():
			break
	check(not events_of(events, "object_shot").is_empty(), "the shot is an event")
	check_eq(events_of(events, "detonation").size(), 1, "the drums go up")
	check_eq(battle.map.get_object(Vector2i(8, 6)), Cover.NONE, "and are gone")
	check(enemy.hp < enemy.max_hp, "the man beside them is hurt")
	check(not battle.map.get_fires().is_empty(), "the ground burns")
	check_eq(shooter.actions, 0, "shooting at drums ends the turn")


func test_explosions_set_off_chain_reactions() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(1, 1)], ["Rifleman", 1, Vector2i(14, 14)]])
	var map := battle.map
	map.set_object(Vector2i(5, 5), Cover.HALF, "fuel")
	map.set_object(Vector2i(6, 6), Cover.HALF, "fuel")
	map.set_object(Vector2i(7, 7), Cover.FULL, "oil_tank")
	map.set_object(Vector2i(12, 12), Cover.HALF, "fuel")
	var events := battle._explode(battle.units[0], Vector2i(4, 5), 1.5, 3, 4, 0)
	check_eq(events_of(events, "detonation").size(), 3, "drums set off drums, which set off the oil tank")
	check(not map.is_explosive(Vector2i(7, 7)), "the oil tank is gone")
	check(map.is_explosive(Vector2i(12, 12)), "drums out of reach are left alone")
	var big := events_of(events, "explosion").filter(func(e: Dictionary) -> bool: return e["center"] == Vector2i(7, 7))
	check(not big.is_empty() and big[0]["radius"] == CombatRules.EXPLOSIVES["oil_tank"]["radius"], "the oil tank's blast is the big one")


func test_fire_blocks_movement_and_burns() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(10, 10)], ["Rifleman", 1, Vector2i(14, 14)]])
	var map := battle.map
	map.add_fire(Vector2i(3, 2), battle.turn_index + CombatRules.FIRE_TURNS)
	check(not battle.reachable(battle.units[0]).has(Vector2i(3, 2)), "nobody walks into a fire")
	map.add_fire(Vector2i(10, 10), battle.turn_index + CombatRules.FIRE_TURNS)
	var victim := battle.units[1]
	var events := battle.end_turn()
	check_eq(victim.hp, victim.max_hp - CombatRules.FIRE_DAMAGE, "standing in fire burns at the start of the turn")
	check(not events_of(events, "damage").is_empty(), "with a damage event")
	for i in CombatRules.FIRE_TURNS:
		battle.end_turn()
	check(map.get_fires().is_empty(), "fires burn out")


func test_tanks_running_over_drums_set_them_off() -> void:
	var battle := make_battle([["Tank", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(14, 14)]])
	var tank := battle.units[0]
	tank.facing = Vector2i(1, 0)
	battle.map.set_object(Vector2i(3, 5), Cover.HALF, "fuel")
	var reach := battle.reachable(tank)
	check(reach.has(Vector2i(3, 5)), "a tank can drive over drums")
	check(reach[Vector2i(3, 5)]["cost"] > TacticalMap.CRUSH_COST + 1.0, "but it costs a lot, so it only does when it must")
	var events := battle.move(tank, Vector2i(3, 5))
	check_eq(events_of(events, "detonation").size(), 1, "the drums go up under the tank")
	check(events_of(events, "explosion").any(func(e: Dictionary) -> bool: return e["center"] == Vector2i(3, 5)), "the blast is right under it")
	check_eq(tank.actions, 0, "and it stops there")
	battle.map.set_object(Vector2i(6, 6), Cover.FULL, "oil_tank")
	check(not battle.reachable(tank).has(Vector2i(6, 6)), "oil tanks stop tanks")


# --- Mines ---

func test_mines_are_hidden_until_spotted_and_hurt() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(14, 14)]])
	var u := battle.units[0]
	battle.map.set_mine(Vector2i(5, 5), true)
	check(battle.reachable(u).has(Vector2i(5, 5)), "unknown mines don't show in the move range")
	check(battle.mines_known_to(0).is_empty() and battle.mines_known_to(1).is_empty(), "nobody knows about it yet")
	# Walk across: either he spots it and stops short, or he steps on it.
	var events := battle.move(u, Vector2i(7, 5))
	var spotted := not events_of(events, "mines_spotted").is_empty()
	var blew := not events_of(events, "mine").is_empty()
	check(spotted != blew, "he either spots the mine or steps on it (spotted %s, blew %s)" % [spotted, blew])
	if spotted:
		check(battle.mines_known_to(0).has(Vector2i(5, 5)), "his side now knows the mine")
		check(not battle.mines_known_to(1).has(Vector2i(5, 5)), "the other side doesn't")
		check_eq(u.pos, Vector2i(4, 5), "he stopped short of it")
		u.actions = 2
		check(not battle.reachable(u).has(Vector2i(5, 5)), "known mines are kept out of the move range")
		check_eq(battle.can_clear_mine(u, Vector2i(5, 5)), "", "he can clear it from next to it")
		battle.execute({"cmd": "clear_mine", "unit": u.id, "tile": Vector2i(5, 5)})
		check(not battle.map.has_mine(Vector2i(5, 5)), "cleared")
		check_eq(u.actions, 1, "clearing costs an action")
	else:
		check(u.hp < u.max_hp, "the mine hurts")
		check(not battle.map.has_mine(Vector2i(5, 5)), "and is used up")


func test_mine_spotting_and_blasts() -> void:
	var a := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(14, 14)]])
	var b := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(14, 14)]])
	for battle in [a, b]:
		battle.map.set_mine(Vector2i(5, 5), true)
		battle.map.set_mine(Vector2i(6, 4), true)
	a.move(a.units[0], Vector2i(8, 5))
	b.move(b.units[0], Vector2i(8, 5))
	check_eq(a.checksum(), b.checksum(), "mines play out the same for the same seed")
	var tank_battle := make_battle([["Tank", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(14, 14)]])
	tank_battle.units[0].facing = Vector2i(1, 0)
	tank_battle.map.set_mine(Vector2i(4, 5), true)
	var events := tank_battle.move(tank_battle.units[0], Vector2i(6, 5))
	check(events_of(events, "mines_spotted").is_empty(), "tank crews don't spot mines")
	check_eq(events_of(events, "mine").size(), 1, "the tank drives onto it")
	check_eq(tank_battle.units[0].pos, Vector2i(4, 5), "and stops there")
	var blast := make_battle([["Rifleman", 0, Vector2i(1, 1)], ["Rifleman", 1, Vector2i(14, 14)]])
	blast.map.set_mine(Vector2i(7, 7), true)
	blast.known_mines[1][Vector2i(7, 7)] = true
	blast._explode(blast.units[0], Vector2i(7, 8), 1.5, 3, 4, 0)
	check(not blast.map.has_mine(Vector2i(7, 7)), "shellfire clears mines")
	check(not blast.mines_known_to(1).has(Vector2i(7, 7)), "and they're struck off the map")


# --- Wheat and wire ---

func test_wheat_is_trampled_by_walking_not_crawling() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 0, Vector2i(2, 8)], ["Rifleman", 1, Vector2i(14, 14)]])
	var map := battle.map
	for x in range(2, 8):
		map.set_terrain(Vector2i(x, 5), TacticalMap.Terrain.WHEAT)
		map.set_terrain(Vector2i(x, 8), TacticalMap.Terrain.WHEAT)
	battle.move(battle.units[0], Vector2i(5, 5))
	check_eq(map.get_terrain(Vector2i(3, 5)), TacticalMap.Terrain.TRAMPLED, "wheat walked through is trampled")
	check_eq(map.get_terrain(Vector2i(2, 5)), TacticalMap.Terrain.TRAMPLED, "including where he set off from")
	check_eq(map.get_terrain(Vector2i(5, 5)), TacticalMap.Terrain.WHEAT, "the wheat he stands in still hides him")
	var crawler := battle.units[1]
	crawler.stance = Unit.Stance.PRONE
	battle.move(crawler, Vector2i(3, 8))
	check_eq(map.get_terrain(Vector2i(2, 8)), TacticalMap.Terrain.WHEAT, "crawling leaves the wheat standing")
	var odds_before: int = battle.shot_odds(battle.units[2], battle.units[0])["hit"]
	map.set_terrain(Vector2i(5, 5), TacticalMap.Terrain.TRAMPLED)
	check(battle.shot_odds(battle.units[2], battle.units[0])["hit"] > odds_before, "trampled wheat hides nobody")


func test_barbed_wire_slows_soldiers_not_tanks() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["Tank", 0, Vector2i(2, 9)], ["Rifleman", 1, Vector2i(14, 14)]])
	var map := battle.map
	map.set_terrain(Vector2i(3, 5), TacticalMap.Terrain.WIRE)
	map.set_terrain(Vector2i(3, 9), TacticalMap.Terrain.WIRE)
	check_eq(battle.reachable(battle.units[0])[Vector2i(3, 5)]["cost"], TacticalMap.TERRAIN_COST[TacticalMap.Terrain.WIRE], "wire is slow going on foot")
	var tank := battle.units[1]
	tank.facing = Vector2i(1, 0)
	battle.move(tank, Vector2i(4, 9))
	check_eq(map.get_terrain(Vector2i(3, 9)), TacticalMap.Terrain.FLOOR, "tanks flatten the wire")
	map.destroy_cover(Vector2i(3, 5), 1.0)
	check(map.get_terrain(Vector2i(3, 5)) != TacticalMap.Terrain.WIRE, "explosions blow gaps in it")


# --- AI, saves, scenarios and the generator ---

func test_ai_blows_up_drums_next_to_enemies() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(3, 8)], ["Rifleman", 1, Vector2i(11, 7)], ["Rifleman", 1, Vector2i(11, 9)]])
	battle.map.set_object(Vector2i(11, 8), Cover.HALF, "fuel")
	battle.map.set_object(Vector2i(4, 7), Cover.FULL, "rock")
	battle.map.set_object(Vector2i(4, 9), Cover.FULL, "rock")
	battle.units[0].grenades = 0
	# Behind a low wall facing them already, so there's nowhere better to go first.
	battle.map.set_edge(Vector2i(3, 8), Vector2i(4, 8), Cover.HALF, "stone")
	var ai := TacticalAI.new(battle, 0)
	var command := ai.decide()
	if command.get("cmd") == "move":
		# Stepping into better cover first is fine; the drums should be its second action.
		battle.execute(command)
		command = ai.decide()
	check_eq(command.get("cmd"), "shoot_object", "with two enemies by the drums, it shoots the drums (%s)" % command)
	check(not battle.execute(command).is_empty(), "and the engine takes the order")
	var open := make_battle([["Rifleman", 0, Vector2i(3, 8)], ["Rifleman", 1, Vector2i(11, 7)], ["Rifleman", 1, Vector2i(11, 9)]])
	open.map.set_object(Vector2i(11, 8), Cover.HALF, "fuel")
	var open_ai := TacticalAI.new(open, 0)
	open_ai._remember()
	var seen := open_ai._seen_enemies()
	check(open_ai._followup_value(open.units[0], Vector2i(3, 8), seen) > open_ai._shot_value(open.units[0], Vector2i(3, 8), open.units[1]),
			"after a move, blowing up the drums counts as a follow-up too")


func test_hazards_survive_saving_and_scenarios() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(14, 14)]])
	battle.map.set_mine(Vector2i(6, 6), true)
	battle.known_mines[0][Vector2i(6, 6)] = true
	battle.map.add_fire(Vector2i(8, 8), 9)
	battle.map.set_object(Vector2i(9, 9), Cover.FULL, "oil_tank")
	battle.map.set_terrain(Vector2i(3, 3), TacticalMap.Terrain.WIRE)
	battle.map.set_terrain(Vector2i(4, 3), TacticalMap.Terrain.TRAMPLED)
	var copy := Battle.from_dict(battle.to_dict())
	check_eq(copy.checksum(), battle.checksum(), "a saved battle keeps mines, fires and what each side knows")
	check(copy.mines_known_to(0).has(Vector2i(6, 6)) and copy.map.has_fire(Vector2i(8, 8)), "loaded")
	var scenario := Scenario.from_battle(battle)
	var loaded := Scenario.from_data(JSON.parse_string(scenario.to_json()))
	check(loaded != null and loaded.map.has_mine(Vector2i(6, 6)), "scenarios keep mines")
	check_eq(loaded.map.get_object_kind(Vector2i(9, 9)), "oil_tank", "and oil tanks")
	check_eq(loaded.map.get_terrain(Vector2i(3, 3)), TacticalMap.Terrain.WIRE, "and wire")
	check_eq(loaded.map.get_terrain(Vector2i(4, 3)), TacticalMap.Terrain.TRAMPLED, "and trampled wheat")


func test_generated_maps_have_hazards_on_both_sides() -> void:
	for size in [44, 64]:
		var layout := MapGenerator.generate(808, Vector2i(size, size))
		var map: TacticalMap = layout["map"]
		var fuel := 0
		var oil := 0
		var wire := 0
		for y in map.height:
			for x in map.width:
				var p := Vector2i(x, y)
				fuel += int(map.get_object_kind(p) == "fuel" and map.get_object(p) != Cover.NONE)
				oil += int(map.get_object_kind(p) == "oil_tank" and map.get_object(p) != Cover.NONE)
				wire += int(map.get_terrain(p) == TacticalMap.Terrain.WIRE)
		check(fuel >= 2 and fuel % 2 == 0, "%dx%d: fuel drums, mirrored (%d)" % [size, size, fuel])
		check(oil == (2 if size >= 56 else 0), "%dx%d: an oil tank a side on big maps (%d)" % [size, size, oil])
		check(wire >= 2 and wire % 2 == 0, "%dx%d: barbed wire, mirrored (%d)" % [size, size, wire])
		check(map.get_mines().size() >= 2 and map.get_mines().size() % 2 == 0, "%dx%d: minefields, mirrored (%d)" % [size, size, map.get_mines().size()])
		for p: Vector2i in map.get_mines():
			check(map.has_mine(Vector2i(map.width - 1 - p.x, p.y)), "mine at %s has a twin" % p)
		check(MapGenerator.is_playable(layout), "%dx%d: still playable" % [size, size])
