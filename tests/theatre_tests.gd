extends SceneTree
## Headless tests for theatres: Normandy as data, and Vietnam's sides, terrain, maps and rules (tunnels,
## punji traps, artillery and napalm, helicopter reinforcements, kill and objective points).
## Run: Godot --headless --path . -s tests/theatre_tests.gd

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


## A Vietnam battle on an open map; specs are [role, team, pos].
func make_battle(specs: Array, size := Vector2i(16, 16), theatre := "vietnam") -> Battle:
	var units: Array[Unit] = []
	for spec in specs:
		units.append(Unit.create(units.size(), "U%d" % units.size(), spec[0], spec[1], spec[2], 0, theatre))
	var battle := Battle.new(TacticalMap.new(size.x, size.y), units, 1234)
	battle.theatre_id = theatre
	battle.start()
	return battle


func events_of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


# --- Theatres as data ---

func test_normandy_units_are_unchanged() -> void:
	var rifleman := Unit.create(0, "A", "Rifleman", 0, Vector2i.ZERO)
	check_eq([rifleman.max_hp, rifleman.aim, rifleman.mobility, rifleman.grenades, rifleman.weapon.name], [7, 65, 7.0, 1, "M1 Garand"], "Allied rifleman")
	var german := Unit.create(1, "B", "Rifleman", 1, Vector2i.ZERO)
	check_eq(german.weapon.name, "Kar98k", "German rifleman")
	var officer := Unit.create(2, "C", "Officer", 0, Vector2i.ZERO, 2)
	check(officer.leader, "officers lead")
	check_eq([officer.aim, officer.max_hp, officer.smoke_grenades], [75, 9, 2], "rank adds aim and HP")
	var mortar := Unit.create(3, "D", "Mortar", 1, Vector2i.ZERO)
	check_eq([mortar.indirect["min"], mortar.indirect["max"], mortar.indirect["radius"]], [5.0, 22.0, 1.5], "mortar ranges")
	var tank := Unit.create(4, "E", "Tank", 0, Vector2i.ZERO)
	check(tank.vehicle and tank.weapon.anti_tank and tank.weapon.blast_radius == 1.0, "a Sherman")
	check_eq(CombatRules.armor_value(tank, "front"), 3, "tank front armour")
	check_eq(Theatres.get_theatre("normandy").team_name(1), "Germany", "side names")


func test_normandy_saves_have_no_theatre_fields() -> void:
	var battle := NormandyScenario.build(5)
	var data := battle.to_dict()
	check(not data.has("theatre") and not data.has("kill_points"), "a Normandy battle saves as before")
	check(not data["map"].has("tunnels"), "and its map too")
	check(not Unit.create(0, "A", "Rifleman", 0, Vector2i.ZERO).to_dict().has("traps"), "and its units too")


func test_vietnam_sides_have_their_own_units() -> void:
	var theatre := Theatres.get_theatre("vietnam")
	check_eq([theatre.team_name(0), theatre.team_name(1)], ["US Army", "Viet Cong"], "sides")
	check(theatre.has_role(0, "RTO") and not theatre.has_role(1, "RTO"), "only the Americans have a radio operator")
	check(theatre.has_role(1, "Guerrilla") and not theatre.has_role(0, "Guerrilla"), "only the VC have guerrillas")
	var grunt := Unit.create(0, "A", "Rifleman", 0, Vector2i.ZERO, 0, "vietnam")
	var guerrilla := Unit.create(1, "B", "Guerrilla", 1, Vector2i.ZERO, 0, "vietnam")
	check(grunt.max_hp > guerrilla.max_hp and grunt.aim > guerrilla.aim, "Americans are tougher and better shots")
	check(grunt.mobility < guerrilla.mobility, "and slower")
	check(guerrilla.has_trait("tunnels") and not grunt.has_trait("tunnels"), "VC use the tunnels")
	check(theatre.cost(1, "Guerrilla") < theatre.cost(0, "Rifleman"), "VC are cheaper")
	var forces := theatre.skirmish_forces(44)
	check(forces["rosters"][1].size() > forces["rosters"][0].size(), "more VC than Americans")
	var apc := Unit.create(2, "C", "M113", 0, Vector2i.ZERO, 0, "vietnam")
	check(apc.vehicle and CombatRules.armor_value(apc, "front") == 2, "the M113 is lightly armoured")
	check(not apc.weapon.anti_tank, "and its .50 cal is no anti-tank gun")


func test_vietnam_battles_build_from_every_entry_point() -> void:
	for size in [44, 64, 84]:
		var built := GameSession.build_skirmish({"theatre": "vietnam", "map": "random", "size": size, "seed": 77})
		var battle: Battle = built[0]
		check_eq(battle.theatre_id, "vietnam", "%d: theatre" % size)
		check_eq(battle.objectives.size(), 3, "%d: three objectives" % size)
		check_eq(battle.objective_points, [1, 0], "%d: only the Americans score for ground" % size)
		check_eq(battle.kill_points, [0, 1], "%d: the VC score for kills" % size)
		var air := battle.reinforcements.filter(func(w: Dictionary) -> bool: return w["air"])
		check(not air.is_empty() and air[0]["team"] == 0, "%d: American reinforcements fly in" % size)
	var campaign := Campaign.create(3, "vietnam")
	for i in campaign.missions().size():
		campaign.mission_index = i
		var battle := campaign.build_battle(i + 1)
		check_eq(battle.alive_units(1).size(), campaign.missions()[i]["enemy"].size(), "mission %d enemy force" % (i + 1))
	var war := WarCampaign.create(3, 99, [true, true], "vietnam")
	for side in 2:
		var orders := war.ai_orders(side)
		check_eq(war.check_orders(side, orders), "", "AI orders for side %d are valid" % side)
		war.set_orders(side, orders)
	check_eq(war.build_battle().theatre_id, "vietnam", "two-player campaign battles")


func test_vietnam_maps_are_playable_and_prepared_by_the_vc() -> void:
	for seed in [1, 2, 3, 4]:
		for size in [36, 44, 64]:
			var layout := VietnamMapGenerator.generate(seed, Vector2i(size, size))
			var map: TacticalMap = layout["map"]
			check(MapGenerator.is_playable(layout), "seed %d %dx%d is playable" % [seed, size, size])
			var counts := {}
			for y in map.height:
				for x in map.width:
					var t := map.get_terrain(Vector2i(x, y))
					counts[t] = counts.get(t, 0) + 1
			for t in [TacticalMap.Terrain.JUNGLE, TacticalMap.Terrain.PADDY, TacticalMap.Terrain.TALL_GRASS]:
				check(counts.get(t, 0) > 0, "seed %d %dx%d has %s" % [seed, size, size, TacticalMap.TERRAIN_NAMES[t]])
			check(map.get_tunnels().size() >= 4, "seed %d: tunnels dug" % seed)
			for p: Vector2i in map.get_tunnels():
				check(map.tunnel_owner(p) == 1 and p.x >= map.width / 2, "tunnel %s is the VC's, on their half" % p)
			var traps := map.get_mines().keys().filter(func(p: Vector2i) -> bool: return map.get_mine_kind(p) == "punji")
			check(not traps.is_empty(), "seed %d: punji traps laid" % seed)
	var battle: Battle = GameSession.build_skirmish({"theatre": "vietnam", "map": "random", "size": 44, "seed": 5})[0]
	for p: Vector2i in battle.map.get_mines():
		if battle.map.get_mine_kind(p) == "punji":
			check(battle.mines_known_to(1).has(p) and not battle.mines_known_to(0).has(p), "the VC know their traps, the Americans don't")


# --- Terrain ---

func test_jungle_hides_and_blocks_sight() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 8)], ["Guerrilla", 1, Vector2i(8, 8)], ["Guerrilla", 1, Vector2i(15, 15)]])
	var us := battle.units[0]
	var vc := battle.units[1]
	check(battle.can_see(us, vc), "in the open he is seen")
	battle.map.set_terrain(vc.pos, TacticalMap.Terrain.JUNGLE)
	check(not battle.can_see(us, vc), "in the jungle he is hidden beyond 3 tiles, standing too")
	us.pos = Vector2i(6, 8)
	check(battle.can_see(us, vc), "but not up close")
	vc.pos = Vector2i(14, 8)
	battle.map.set_terrain(Vector2i(14, 8), TacticalMap.Terrain.FLOOR)
	for x in [8, 9]:
		battle.map.set_terrain(Vector2i(x, 8), TacticalMap.Terrain.JUNGLE)
	us.pos = Vector2i(2, 8)
	check(not LineOfSight.has_line(battle.map, us.pos, vc.pos), "two tiles of jungle block sight")
	battle.map.set_terrain(Vector2i(9, 8), TacticalMap.Terrain.FLOOR)
	check(LineOfSight.has_line(battle.map, us.pos, vc.pos), "one tile doesn't")


func test_tall_grass_hides_crouching_soldiers_and_paddies_slow() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 8)], ["Guerrilla", 1, Vector2i(8, 8)]])
	var vc := battle.units[1]
	battle.map.set_terrain(vc.pos, TacticalMap.Terrain.TALL_GRASS)
	check(battle.can_see(battle.units[0], vc), "standing in tall grass is seen")
	vc.stance = Unit.Stance.CROUCH
	check(not battle.can_see(battle.units[0], vc), "crouching in it isn't")
	check(battle.map.step_cost(Vector2i(3, 3), Vector2i(4, 3)) < 1.5, "grass is quick going")
	battle.map.set_terrain(Vector2i(4, 3), TacticalMap.Terrain.PADDY)
	check_eq(battle.map.step_cost(Vector2i(3, 3), Vector2i(4, 3)), 2.0, "a paddy is slow on foot")
	check_eq(battle.map.vehicle_step_cost(Vector2i(3, 3), Vector2i(4, 3)), 3.0, "and bogs vehicles down")


# --- Tunnels ---

func test_viet_cong_move_through_their_tunnels() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Guerrilla", 1, Vector2i(14, 14)], ["Guerrilla", 1, Vector2i(14, 2)]], Vector2i(16, 16))
	battle.map.set_tunnel(Vector2i(14, 14), 1)
	battle.map.set_tunnel(Vector2i(9, 3), 1)
	battle.end_turn()
	var vc := battle.units[1]
	check(battle.can_tunnel(battle.units[0], Vector2i(9, 3)) != "", "Americans can't use them")
	check_eq(battle.can_tunnel(vc, Vector2i(9, 3)), "", "a guerrilla on an entrance can")
	check(battle.can_tunnel(vc, Vector2i(5, 5)) != "", "only to another entrance")
	var events := battle.execute({"cmd": "tunnel", "unit": vc.id, "tile": Vector2i(9, 3)})
	check_eq(vc.pos, Vector2i(9, 3), "comes up at the other entrance")
	check_eq(vc.actions, 0, "using the whole turn")
	check_eq(events_of(events, "tunnel").size(), 1, "a tunnel event")
	check(battle.known_tunnels[0].has(Vector2i(9, 3)), "the American who saw him come up knows where that entrance is")
	check(not battle.known_tunnels[0].has(Vector2i(14, 14)), "but not the one he went down (out of sight)")


func test_found_tunnels_can_be_blown_in() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(5, 5)], ["Guerrilla", 1, Vector2i(14, 14)]])
	battle.map.set_tunnel(Vector2i(6, 5), 1)
	check(battle.can_clear_mine(battle.units[0], Vector2i(6, 5)) != "", "an entrance nobody has found can't be blown")
	battle.known_tunnels[0][Vector2i(6, 5)] = true
	var events := battle.execute({"cmd": "clear_mine", "unit": 0, "tile": Vector2i(6, 5)})
	check_eq(events_of(events, "tunnel_collapsed").size(), 1, "blown in")
	check_eq(battle.map.tunnel_owner(Vector2i(6, 5)), -1, "gone")


func test_soldiers_spot_tunnel_entrances_as_they_pass() -> void:
	var found := 0
	for seed in 20:
		var battle := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["Guerrilla", 1, Vector2i(15, 15)]])
		battle.rng.seed = seed + 1
		battle.map.set_tunnel(Vector2i(4, 4), 1)
		battle.execute({"cmd": "move", "unit": 0, "tile": Vector2i(6, 5)})
		found += int(battle.known_tunnels[0].has(Vector2i(4, 4)))
	check(found > 3 and found < 17, "about half the time (%d of 20)" % found)


# --- Traps ---

func test_sappers_lay_punji_traps() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Sapper", 1, Vector2i(8, 8)]])
	battle.end_turn()
	var sapper := battle.units[1]
	check_eq(sapper.traps, 2, "a sapper carries two traps")
	check(battle.can_lay_trap(sapper, Vector2i(10, 8)) != "", "only next to him")
	var events := battle.execute({"cmd": "trap", "unit": sapper.id, "tile": Vector2i(9, 8)})
	check_eq(events_of(events, "trap_laid").size(), 1, "laid")
	check(battle.map.has_mine(Vector2i(9, 8)) and battle.map.get_mine_kind(Vector2i(9, 8)) == "punji", "a punji trap")
	check(battle.mines_known_to(1).has(Vector2i(9, 8)) and not battle.mines_known_to(0).has(Vector2i(9, 8)), "only his side knows")
	check_eq(sapper.traps, 1, "one left")
	var copy := Battle.from_dict(battle.to_dict())
	check_eq(copy.get_unit(sapper.id).traps, 1, "saved")
	check_eq(copy.checksum(), battle.checksum(), "and loads the same")


func test_punji_traps_wound_soldiers_but_not_vehicles() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 5)], ["M113", 0, Vector2i(2, 9)], ["Guerrilla", 1, Vector2i(15, 15)]])
	battle.map.set_mine(Vector2i(3, 5), true, "punji")
	var grunt := battle.units[0]
	var events := battle.execute({"cmd": "move", "unit": grunt.id, "tile": Vector2i(5, 5)})
	var traps := events_of(events, "mine")
	check(traps.size() == 1 and traps[0].get("kind") == "punji", "steps into it")
	check(grunt.hp < grunt.max_hp and grunt.hp >= grunt.max_hp - CombatRules.TRAP_DAMAGE_MAX, "hurt")
	check(events_of(events, "explosion").is_empty(), "no blast")
	battle.map.set_mine(Vector2i(4, 9), true, "punji")
	var apc := battle.units[1]
	battle.execute({"cmd": "move", "unit": apc.id, "tile": Vector2i(6, 9)})
	check_eq(apc.pos, Vector2i(6, 9), "the M113 rolls straight over")
	check(not battle.map.has_mine(Vector2i(4, 9)) and apc.hp == apc.max_hp, "crushing it harmlessly")


# --- Artillery, napalm, scoring, helicopters ---

func test_the_radio_operator_calls_in_napalm() -> void:
	var battle := make_battle([["RTO", 0, Vector2i(2, 8)], ["Guerrilla", 1, Vector2i(9, 8)], ["Guerrilla", 1, Vector2i(15, 1)]], Vector2i(20, 16))
	var rto := battle.units[0]
	check_eq(rto.indirect["kinds"], ["he", "napalm"], "high explosive or napalm")
	battle.execute({"cmd": "move", "unit": rto.id, "tile": Vector2i(3, 8)})
	check_eq(battle.can_fire_mortar(rto, Vector2i(9, 8), "napalm"), "", "he can call it in after moving, on what he sees")
	for x in range(9, 12):
		battle.map.set_terrain(Vector2i(x, 8), TacticalMap.Terrain.JUNGLE)
	battle.execute({"cmd": "mortar", "unit": rto.id, "tile": Vector2i(9, 8), "kind": "napalm"})
	check_eq(rto.mortar_smoke, 0, "the napalm round is spent")
	var events := battle.end_turn()
	events.append_array(battle.end_turn())
	var napalm := events_of(events, "napalm")
	check_eq(napalm.size(), 1, "it lands")
	if not napalm.is_empty():
		var center: Vector2i = napalm[0]["center"]
		check(battle.map.has_fire(center) or battle.map.get_object(center) != Cover.NONE, "the ground burns")
		check(battle.map.get_terrain(center) != TacticalMap.Terrain.JUNGLE, "the jungle burns away")


func test_kills_and_ground_score_differently_in_vietnam() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 8)], ["Guerrilla", 1, Vector2i(5, 8)], ["Guerrilla", 1, Vector2i(15, 15)]])
	battle.kill_points = [0, 1]
	battle.objective_points = [1, 0]
	battle.objectives.append({"name": "A", "center": Vector2(15.5, 15.5), "radius": 1.5, "owner": 1})
	var grunt := battle.units[0]
	grunt.hp = 1
	var events := battle._damage(grunt, 3, 0, battle.units[1])
	check_eq(events_of(events, "kill_points").size(), 1, "a kill scores")
	check_eq(battle.victory_points, [0, 1], "a point for the VC")
	battle._score_round()
	check_eq(battle.victory_points, [0, 1], "holding ground scores nothing for the VC")


func test_helicopters_bring_american_reinforcements_to_the_landing_zone() -> void:
	var layout := VietnamMapGenerator.generate(3, Vector2i(44, 44))
	var lz: Vector2i = layout["landing_zones"][0]
	var battle := BattleFactory.create(layout, [["Rifleman"], ["Guerrilla"]], 3,
			{"theatre": "vietnam", "reinforcements": [{"round": 2, "team": 0, "roster": ["Rifleman", "Rifleman"], "air": true}]})
	battle.start()
	battle.end_turn()
	var events := battle.end_turn()
	var arrivals := events_of(events, "reinforcements")
	check(not arrivals.is_empty() and arrivals[0].get("air", false), "they fly in")
	for id: int in arrivals[0]["units"] if not arrivals.is_empty() else []:
		check(Vector2(battle.get_unit(id).pos).distance_to(Vector2(lz)) <= 3.0, "at the landing zone")


func test_vietnam_battles_save_and_replay_identically() -> void:
	var battle: Battle = GameSession.build_skirmish({"theatre": "vietnam", "map": "random", "size": 44, "seed": 9})[0]
	var start := battle.to_dict()
	battle.start()
	var ais := [TacticalAI.new(battle, 0), TacticalAI.new(battle, 1)]
	var commands := []
	battle.executed.connect(func(command: Dictionary) -> void: commands.append(command))
	for i in 120:
		if battle.winner != -1:
			break
		ais[battle.current_team].act()
	var copy := Battle.from_dict(battle.to_dict())
	check_eq(copy.checksum(), battle.checksum(), "a saved Vietnam battle loads identically")
	check_eq(copy.theatre_id, "vietnam", "and stays in Vietnam")
	var replayed := Battle.from_dict(start)
	replayed.start()
	for command: Dictionary in commands:
		replayed.execute(command)
	check_eq(replayed.checksum(), battle.checksum(), "replaying the orders gives the same battle")


func test_vietnam_scenarios_round_trip() -> void:
	var battle: Battle = GameSession.build_skirmish({"theatre": "vietnam", "map": "random", "size": 36, "seed": 4})[0]
	var scenario := Scenario.from_battle(battle, "Test")
	var loaded := Scenario.from_data(JSON.parse_string(scenario.to_json()))
	check(loaded != null, "loads: %s" % Scenario.last_error)
	if loaded == null:
		return
	check_eq(loaded.theatre_id, "vietnam", "theatre kept")
	check_eq(loaded.map.get_tunnels(), battle.map.get_tunnels(), "tunnels kept")
	var punji := battle.map.get_mines().keys().filter(func(p: Vector2i) -> bool: return battle.map.get_mine_kind(p) == "punji")
	check(not punji.is_empty() and loaded.map.get_mine_kind(punji[0]) == "punji", "traps kept")
	check_eq(loaded.units.size(), scenario.units.size(), "units kept")
	var rebuilt := loaded.build_battle(1)
	check_eq(rebuilt.theatre_id, "vietnam", "builds a Vietnam battle")
	check_eq(rebuilt.kill_points, [0, 1], "with Vietnam's scoring")


# --- Iraq 2004 ---

func test_modern_maps_come_in_two_styles_with_ieds() -> void:
	for style in ModernMapGenerator.STYLES:
		for size in [36, 44, 64]:
			var layout := ModernMapGenerator.generate(11, Vector2i(size, size), style)
			var map: TacticalMap = layout["map"]
			check(MapGenerator.is_playable(layout), "%s %dx%d is playable" % [style, size, size])
			var ieds := map.get_mines().keys().filter(func(p: Vector2i) -> bool: return map.get_mine_kind(p) == "ied")
			check(ieds.size() >= 2, "%s %dx%d: IEDs buried (%d)" % [style, size, size, ieds.size()])
			for p: Vector2i in ieds:
				check(p.x < map.width / 2, "IED %s is on the Coalition's way in" % p)
	check(ModernMapGenerator.generate(2, Vector2i(44, 44))["style"] != ModernMapGenerator.generate(3, Vector2i(44, 44))["style"], "the seed picks the style")
	for size in [44, 64, 84]:
		var battle: Battle = GameSession.build_skirmish({"theatre": "modern", "map": "random", "size": size, "seed": 21})[0]
		check_eq(battle.team_name(1), "Insurgents", "%d: the insurgents" % size)
		for p: Vector2i in battle.map.get_mines():
			check(battle.mines_known_to(1).has(p) and not battle.mines_known_to(0).has(p), "the insurgents know their IEDs")


func test_coalition_soldiers_wear_body_armour() -> void:
	var rifleman := Unit.create(0, "A", "Rifleman", 0, Vector2i.ZERO, 0, "modern")
	check_eq(rifleman.armor, 1, "body armour")
	var battle := make_battle([["Rifleman", 0, Vector2i(2, 2)], ["Fighter", 1, Vector2i(14, 14)]], Vector2i(16, 16), "modern")
	var events := battle._damage(battle.units[0], 3, 0)
	check_eq(events[0]["amount"], 2, "it stops a point of every hit")


func test_bomb_makers_plant_and_set_off_ieds() -> void:
	var battle := make_battle([["Rifleman", 0, Vector2i(9, 5)], ["Rifleman", 0, Vector2i(2, 14)], ["Bomb Maker", 1, Vector2i(14, 5)]], Vector2i(16, 16), "modern")
	battle.end_turn()
	var maker := battle.units[2]
	battle.execute({"cmd": "trap", "unit": maker.id, "tile": Vector2i(13, 5)})
	check_eq(battle.map.get_mine_kind(Vector2i(13, 5)), "ied", "he plants an IED")
	battle.map.set_mine(Vector2i(9, 6), true, "ied")
	battle.known_mines[1][Vector2i(9, 6)] = true
	check_eq(battle.can_detonate(maker, Vector2i(9, 6)), "", "and can set off one he sees")
	var grunt := battle.units[0]
	var hp := grunt.hp
	var events := battle.execute({"cmd": "detonate", "unit": maker.id, "tile": Vector2i(9, 6)})
	check_eq(events_of(events, "ied").size(), 1, "it goes off")
	check(grunt.hp < hp, "catching the soldier beside it")
	check(not battle.map.has_mine(Vector2i(9, 6)), "and is spent")
	check_eq(maker.actions, 0, "ending his turn")


func test_ieds_hurt_vehicles_and_the_eod_tech_finds_them() -> void:
	var battle := make_battle([["MRAP", 0, Vector2i(2, 5)], ["Fighter", 1, Vector2i(15, 15)]], Vector2i(16, 16), "modern")
	battle.map.set_mine(Vector2i(4, 5), true, "ied")
	var mrap := battle.units[0]
	battle.execute({"cmd": "move", "unit": mrap.id, "tile": Vector2i(6, 5)})
	check(mrap.hp <= mrap.max_hp - (CombatRules.IED_DAMAGE_MIN - CombatRules.IED_VS_ARMOR), "an IED tears into the MRAP")
	var found := [0, 0]
	for seed in 20:
		for i in 2:
			var test := make_battle([["EOD Tech" if i == 0 else "Rifleman", 0, Vector2i(2, 5)], ["Fighter", 1, Vector2i(15, 15)]], Vector2i(16, 16), "modern")
			test.rng.seed = seed + 1
			test.map.set_mine(Vector2i(4, 4), true, "ied")
			test.execute({"cmd": "move", "unit": 0, "tile": Vector2i(6, 5)})
			found[i] += int(test.mines_known_to(0).has(Vector2i(4, 4)))
	check(found[0] > found[1] + 6, "the EOD tech spots IEDs far more often (%d vs %d of 20)" % found)


# --- Music ---

func test_every_theatre_has_menu_and_battle_themes() -> void:
	for theatre_id: String in Theatres.IDS:
		var stream := MusicComposer.render(theatre_id, "battle")
		var samples := stream.data.size() / 2
		check(samples > MusicComposer.RATE * 20, "%s battle theme lasts over 20 s" % theatre_id)
		check_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s battle theme loops" % theatre_id)
		var loud := 0
		for i in range(0, samples, 101):
			loud += int(absi(stream.data.decode_s16(i * 2)) > 1000)
		check(loud > samples / 101 / 4, "%s battle theme isn't silent" % theatre_id)
	check_eq(MusicComposer.render("vietnam", "menu").data, MusicComposer.render("vietnam", "menu").data, "a theme is the same every time")
