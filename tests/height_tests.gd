extends SceneTree
## Headless tests for height: hills and cliffs, multi-storey buildings, stairs, roofs, and what height does to
## sight, cover, shooting and blasts.
## Run: Godot --headless --path . -s tests/height_tests.gd

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


## A battle on the given map; specs are [role, team, pos] or [role, team, pos, level].
func make_battle(map: TacticalMap, specs: Array) -> Battle:
	var units: Array[Unit] = []
	for spec in specs:
		var u := Unit.create(units.size(), "U%d" % units.size(), spec[0], spec[1], spec[2])
		if spec.size() > 3:
			u.level = spec[3]
		units.append(u)
	var battle := Battle.new(map, units, 1234)
	battle.start()
	return battle


func raise(map: TacticalMap, rect: Rect2i, level: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			map.set_elevation(Vector2i(x, y), level)


## A stone building of `storeys` with a door on its west side at `door`, windows all along its east side, and
## stairs in its north-west corner.
func tower(rect: Rect2i, storeys: int, door: Vector2i) -> TacticalMap:
	var b := MapBuilder.new(20, 20)
	var windows := []
	for y in range(rect.position.y, rect.end.y):
		windows.append([Vector2i(rect.end.x - 1, y), MapBuilder.E])
	b.building(rect, [[door, MapBuilder.W]], windows, [], "stone")
	b.storeys(rect, storeys)
	b.map.set_stairs(rect.position, true)
	return b.map


func events_of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


# --- The map ---

func test_flat_maps_have_no_height() -> void:
	var map := TacticalMap.new(8, 8)
	check(not map.has_height(), "a new map is flat")
	check(not map.to_dict().has("elevation"), "and saves as it always has")
	var b := MapBuilder.new(10, 10)
	b.building(Rect2i(2, 2, 3, 3), [], [], [], "stone")
	check(not b.map.has_height(), "a single-storey building doesn't make it tall")
	check_eq(b.map.get_storeys(Vector2i(3, 3)), 1, "it has one storey")
	check_eq(b.map.top_level(Vector2i(3, 3)), 0, "and no roof to stand on")


func test_height_saves_and_loads() -> void:
	var map := tower(Rect2i(4, 4, 3, 3), 3, Vector2i(4, 5))
	raise(map, Rect2i(12, 0, 4, 4), 2)
	var loaded := TacticalMap.from_dict(map.to_dict())
	check(loaded.has_height(), "a tall map loads tall")
	check_eq(loaded.get_elevation(Vector2i(13, 1)), 2, "elevation survives a save")
	check_eq(loaded.get_storeys(Vector2i(5, 5)), 3, "so do storeys")
	check(loaded.has_stairs(Vector2i(4, 4)), "and stairs")
	check_eq(loaded.top_level(Vector2i(5, 5)), 3, "a three-storey building's roof is level 3")


# --- Moving ---

func test_slopes_cost_more_going_up_and_cliffs_stop_everyone() -> void:
	var map := TacticalMap.new(12, 12)
	raise(map, Rect2i(5, 0, 7, 12), 1)
	raise(map, Rect2i(8, 0, 4, 12), 3)
	check_eq(map.step_cost(Vector2i(4, 5), Vector2i(5, 5)), 1.0 + TacticalMap.CLIMB_COST, "climbing a level costs extra")
	check_eq(map.step_cost(Vector2i(5, 5), Vector2i(4, 5)), 1.0, "going down is free")
	check_eq(map.step_cost(Vector2i(7, 5), Vector2i(8, 5)), INF, "two levels up is a cliff")
	check_eq(map.step_cost(Vector2i(8, 5), Vector2i(7, 5)), INF, "and nobody jumps off one")
	check_eq(map.step_cost(Vector2i(4, 4), Vector2i(5, 5)), INF, "no climbing diagonally")
	check_eq(map.vehicle_step_cost(Vector2i(4, 5), Vector2i(5, 5)), 1.0 + TacticalMap.VEHICLE_CLIMB_COST, "tanks labour uphill")
	check_eq(map.vehicle_step_cost(Vector2i(7, 5), Vector2i(8, 5)), INF, "and can't climb cliffs")
	var battle := make_battle(map, [["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(11, 11)]])
	var reach := battle.reachable(battle.units[0])
	check(reach.has(Vector2i(6, 5)), "the slope is in reach")
	check(not reach.has(Vector2i(8, 5)), "the clifftop isn't")


func test_stairs_lead_up_through_every_floor_to_the_roof() -> void:
	var map := tower(Rect2i(4, 4, 3, 3), 2, Vector2i(4, 5))
	var battle := make_battle(map, [["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(18, 18)]])
	var u := battle.units[0]
	u.mobility = 12.0
	check_eq(map.arrival_level(Vector2i(3, 5), 0, Vector2i(4, 5)), 0, "in through the door to the ground floor")
	check_eq(map.arrival_level(Vector2i(3, 4), 0, Vector2i(4, 4)), 0, "through the wall it's the same floor (walls stop it)")
	check_eq(map.step_cost(Vector2i(3, 4), Vector2i(4, 4)), INF, "and the wall does")
	check_eq(map.arrival_level(Vector2i(5, 5), 1, Vector2i(7, 5)), -1, "nobody walks out of an upstairs window")
	var reach := battle.reachable(u)
	check(reach.has(Vector2i(5, 5)), "the ground floor is in reach")
	check(reach[Vector2i(4, 4)]["levels"].has(1), "the first floor is, up the stairs")
	check(reach[Vector2i(4, 4)]["levels"].has(2), "and so is the roof")
	check(reach[Vector2i(6, 6)]["levels"].has(2), "the whole roof is")
	check_eq(battle.can_move(u, Vector2i(6, 6), 2), "", "he can go up onto the roof")
	var events := battle.move(u, Vector2i(6, 6), 2)
	check_eq(u.pos, Vector2i(6, 6), "he ends on the tile")
	check_eq(u.level, 2, "up on the roof")
	var moves := events_of(events, "move")
	check(not moves.is_empty() and moves[0].has("levels"), "the move says which floor each step is on")
	var path: Array = moves[0]["path"]
	var levels: Array = moves[0]["levels"]
	check_eq(path.size(), levels.size(), "a floor for every step")
	check(path.count(Vector2i(4, 4)) >= 3, "the stairs repeat the tile, one step a floor")


func test_one_unit_per_tile_whatever_the_floor() -> void:
	var map := tower(Rect2i(4, 4, 3, 3), 2, Vector2i(4, 5))
	var battle := make_battle(map, [["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 0, Vector2i(5, 5), 1], ["Rifleman", 1, Vector2i(18, 18)]])
	var reach := battle.reachable(battle.units[0])
	check(not reach.has(Vector2i(5, 5)), "a soldier upstairs blocks the tile below him")


func test_roof_from_a_hillside() -> void:
	var map := tower(Rect2i(4, 4, 3, 3), 2, Vector2i(4, 5))
	raise(map, Rect2i(7, 0, 5, 20), 2)
	check_eq(map.arrival_level(Vector2i(7, 5), 0, Vector2i(6, 5)), 2, "from a hill as high as the roof, step onto it")
	check_eq(map.step_cost(Vector2i(7, 5), Vector2i(6, 5)), 1.0 + TacticalMap.VAULT_COST, "over the parapet")


# --- Sight ---

func test_ridges_block_sight_and_height_sees_over_walls() -> void:
	var map := TacticalMap.new(20, 12)
	map.set_elevation(Vector2i(10, 5), 1)
	check(not LineOfSight.has_line(map, Vector2i(5, 5), Vector2i(15, 5)), "a ridge between blocks sight")
	raise(map, Rect2i(0, 0, 4, 12), 2)
	check(LineOfSight.has_line(map, Vector2i(2, 5), Vector2i(15, 5)), "from a higher hill you see over it")
	var flat := TacticalMap.new(20, 12)
	flat.set_edge(Vector2i(10, 5), Vector2i(11, 5), Cover.FULL, "wall")
	flat.set_elevation(Vector2i(19, 11), 1)
	check(not LineOfSight.has_line(flat, Vector2i(5, 5), Vector2i(15, 5)), "a wall blocks sight on level ground")
	check(LineOfSight.has_line(flat, Vector2i(5, 5), Vector2i(15, 5), 2, 0), "but not from two storeys up")
	flat.set_object(Vector2i(8, 5), Cover.FULL, "tree")
	check(not LineOfSight.has_line(flat, Vector2i(5, 5), Vector2i(15, 5), 2, 0), "trees are taller than that")


func test_floors_and_upstairs_walls_block_sight() -> void:
	var map := tower(Rect2i(4, 4, 3, 3), 3, Vector2i(4, 5))
	# Outside to the east, past the windows.
	check(LineOfSight.has_line(map, Vector2i(6, 5), Vector2i(12, 5), 1, 0), "out of an upstairs window")
	check(LineOfSight.has_line(map, Vector2i(6, 5), Vector2i(12, 5), 2, 0), "from the floor above too")
	check(not LineOfSight.has_line(map, Vector2i(5, 5), Vector2i(1, 5), 1, 0), "upstairs, where the door is below there's wall")
	check(LineOfSight.has_line(map, Vector2i(5, 5), Vector2i(1, 5), 0, 0), "the door is open on the ground floor")
	check(not LineOfSight.has_line(map, Vector2i(5, 5), Vector2i(6, 6), 0, 1), "the ceiling hides the floor above")
	check(LineOfSight.has_line(map, Vector2i(5, 5), Vector2i(6, 6), 1, 1), "on the same floor they see each other")
	check(LineOfSight.has_line(map, Vector2i(5, 5), Vector2i(14, 12), 3, 0), "from the roof, down over the parapet")
	check(not LineOfSight.has_line(map, Vector2i(1, 5), Vector2i(5, 5), 0, 1), "nobody outside sees through the walls upstairs")
	check(LineOfSight.has_line(map, Vector2i(14, 12), Vector2i(5, 5), 0, 1), "but through the windows they do")


func test_height_sees_further() -> void:
	var map := TacticalMap.new(40, 10)
	raise(map, Rect2i(0, 0, 3, 10), 2)
	check(LineOfSight.can_see(map, Vector2i(1, 5), Vector2i(22, 5), 18.0), "two levels up sees four tiles further")
	check(not LineOfSight.can_see(map, Vector2i(22, 5), Vector2i(1, 5), 18.0), "looking up doesn't")


func test_nothing_hides_upstairs() -> void:
	var map := tower(Rect2i(4, 4, 3, 3), 2, Vector2i(4, 5))
	var battle := make_battle(map, [["Rifleman", 0, Vector2i(14, 5)], ["Rifleman", 1, Vector2i(6, 5), 1]])
	battle.units[1].stance = Unit.Stance.PRONE
	check(not Battle.hidden_at(map, Vector2i(14, 5), battle.units[1], Vector2i(6, 5), 1), "there's no wheat upstairs")


func test_tile_vision_sees_rooftops() -> void:
	var map := tower(Rect2i(4, 4, 3, 3), 2, Vector2i(4, 5))
	raise(map, Rect2i(10, 0, 6, 20), 3)
	var battle := make_battle(map, [["Rifleman", 0, Vector2i(12, 5)], ["Rifleman", 1, Vector2i(18, 18)]])
	check(battle.visible_from(Vector2i(12, 5), 18.0).has(Vector2i(5, 5)), "the roof is in sight from the hill")
	check_eq(battle.target_level(Vector2i(12, 5), 0, Vector2i(5, 5), 18.0), 2, "the roof, not the floors below it")


# --- Cover and shooting ---

func test_banks_and_parapets_are_cover() -> void:
	var map := tower(Rect2i(4, 4, 3, 3), 2, Vector2i(4, 5))
	raise(map, Rect2i(12, 0, 4, 20), 1)
	check_eq(map.cover_toward(Vector2i(11, 5), Vector2i(1, 0)), Cover.FULL, "a bank of higher ground is full cover")
	check_eq(map.cover_toward(Vector2i(6, 5), Vector2i(1, 0), 2), Cover.HALF, "the parapet is half cover on the roof")
	check_eq(map.cover_toward(Vector2i(5, 5), Vector2i(1, 0), 2), Cover.NONE, "but not in the middle of it")
	check_eq(map.cover_toward(Vector2i(4, 5), Vector2i(-1, 0), 1), Cover.FULL, "upstairs the doorway below is wall")
	check_eq(map.cover_toward(Vector2i(6, 5), Vector2i(1, 0), 1), Cover.HALF, "and the windows are windows")


func test_high_ground_beats_low_cover() -> void:
	var map := TacticalMap.new(20, 12)
	map.set_edge(Vector2i(10, 5), Vector2i(9, 5), Cover.HALF, "stone")
	check_eq(map.cover_against(Vector2i(10, 5), Vector2i(4, 5)), Cover.HALF, "a low wall covers on level ground")
	raise(map, Rect2i(0, 0, 5, 12), 1)
	check_eq(map.cover_against(Vector2i(10, 5), Vector2i(3, 5), 0, 0), Cover.NONE, "but not against fire from a level up")
	map.set_edge(Vector2i(10, 5), Vector2i(9, 5), Cover.FULL, "hedge")
	check_eq(map.cover_against(Vector2i(10, 5), Vector2i(3, 5)), Cover.FULL, "a hedge still covers from one level up")
	raise(map, Rect2i(0, 0, 5, 12), 2)
	check_eq(map.cover_against(Vector2i(10, 5), Vector2i(3, 5)), Cover.HALF, "from two levels up only half")


func test_high_ground_aims_better() -> void:
	var map := TacticalMap.new(20, 12)
	raise(map, Rect2i(0, 0, 5, 12), 1)
	var battle := make_battle(map, [["Rifleman", 0, Vector2i(3, 5)], ["Rifleman", 1, Vector2i(10, 5)]])
	var odds := battle.shot_odds(battle.units[0], battle.units[1])
	var labels: Array = odds["modifiers"].map(func(m: Array) -> String: return m[0])
	check(labels.has("High ground"), "shooting down gets the high ground bonus")
	var back := battle.shot_odds(battle.units[1], battle.units[0])
	labels = back["modifiers"].map(func(m: Array) -> String: return m[0])
	check(not labels.has("High ground"), "shooting up doesn't")


# --- Blasts ---

func test_blasts_stay_on_their_floor() -> void:
	var map := tower(Rect2i(4, 4, 3, 3), 3, Vector2i(4, 5))
	var battle := make_battle(map, [["Rifleman", 0, Vector2i(14, 5)], ["Rifleman", 1, Vector2i(5, 5), 3], ["Rifleman", 1, Vector2i(6, 6), 0]])
	var roof := battle.units[1]
	var below := battle.units[2]
	var events := battle._explode(battle.units[0], Vector2i(5, 5), 1.5, 3, 3, 0, null, CombatRules.EXPLOSION_VS_ARMOR, 3)
	check(roof.hp < roof.max_hp, "a shell on the roof hurts whoever is up there")
	check_eq(below.hp, below.max_hp, "not the ground floor three storeys down")
	check_eq(events_of(events, "explosion")[0]["destroyed"], 0, "and it tears up no walls")
	check_eq(map.get_storeys(Vector2i(5, 5)), 3, "the building stands")


func test_grenades_go_for_the_floor_the_enemy_is_on() -> void:
	var map := tower(Rect2i(4, 4, 3, 3), 2, Vector2i(4, 5))
	var battle := make_battle(map, [["Rifleman", 0, Vector2i(10, 5)], ["Rifleman", 1, Vector2i(6, 5), 1]])
	check_eq(battle.aim_level(battle.units[0], Vector2i(6, 5), 10.0), 1, "the throw goes for the soldier upstairs")
	check_eq(battle.landing_level(Vector2i(7, 5), 1.0), 0, "one that falls outside lands on the ground")


func test_old_commands_still_move_on_flat_maps() -> void:
	var battle := make_battle(TacticalMap.new(12, 12), [["Rifleman", 0, Vector2i(2, 2)], ["Rifleman", 1, Vector2i(10, 10)]])
	var events := battle.execute({"cmd": "move", "unit": 0, "tile": Vector2i(4, 2)})
	check(not events.is_empty(), "a move without a level works")
	check(not events_of(events, "move")[0].has("levels"), "and on a flat map the event says nothing of floors")
	check_eq(battle.units[0].level, 0, "everyone stays on the ground")


# --- Generated maps ---

func test_generated_maps_have_walkable_hills_and_tall_buildings() -> void:
	for theatre_id in ["normandy", "vietnam", "modern"]:
		var theatre := Theatres.get_theatre(theatre_id)
		for seed in [3, 4]:
			var layout := theatre.generate_map(seed, Vector2i(44, 44))
			var map: TacticalMap = layout["map"]
			var name := "%s #%d" % [theatre_id, seed]
			var raised := 0
			var cliffs := 0
			var crooked := 0
			var raised_starts := 0
			for y in map.height:
				for x in map.width:
					var p := Vector2i(x, y)
					raised += int(map.get_elevation(p) > 0)
					for d: Vector2i in TacticalMap.DIRS8:
						if map.in_bounds(p + d) and absi(map.get_elevation(p) - map.get_elevation(p + d)) > 1:
							cliffs += 1
					# A building stands on level ground.
					if map.get_storeys(p) > 0:
						for d: Vector2i in TacticalMap.DIRS4:
							if map.get_storeys(p + d) > 0 and map.get_elevation(p + d) != map.get_elevation(p):
								crooked += 1
			if layout.get("style", "") != "town":
				check(raised > 0, "%s has hills" % name)
			check_eq(cliffs, 0, "%s: hills step a level at a time" % name)
			check_eq(crooked, 0, "%s: buildings stand on level ground" % name)
			for team in 2:
				for p: Vector2i in layout["spawns"][team]:
					raised_starts += int(map.get_elevation(p) > 0)
			check_eq(raised_starts, 0, "%s: both sides start on level ground" % name)
			if theatre_id != "vietnam":
				check(not map.get_tall_buildings().is_empty(), "%s has tall buildings" % name)
				for p: Vector2i in map.get_stairs():
					check(map.get_storeys(p) >= 2, "%s: stairs at %s are in a tall building" % [name, p])
			if theatre_id == "normandy":
				check(MapGenerator.is_playable(layout), "%s is playable" % name)


func test_generated_roofs_can_be_reached() -> void:
	var layout := MapGenerator.generate(3, Vector2i(44, 44))
	var map: TacticalMap = layout["map"]
	var reach := Pathfinder.search(map, layout["spawns"][0][0], 10000.0)
	var roofs := 0
	for p: Vector2i in map.get_tall_buildings():
		if map.get_storeys(p) >= 2 and reach.has(p) and reach[p]["levels"].has(map.get_storeys(p)):
			roofs += 1
	check(roofs > 0, "some roofs can be climbed to from the start (%d tiles)" % roofs)


# --- Scenario files ---

func test_scenarios_keep_height() -> void:
	var s := Scenario.create(20, 20)
	s.map = tower(Rect2i(4, 4, 3, 3), 3, Vector2i(4, 5))
	raise(s.map, Rect2i(12, 2, 3, 3), 2)
	var data := s.to_data()
	check(data["map"].has("elevation"), "elevation is written")
	check(data["map"].has("storeys") and data["map"].has("stairs"), "so are storeys and stairs")
	var back := Scenario.from_data(JSON.parse_string(s.to_json()))
	check(back != null, "the scenario loads (%s)" % Scenario.last_error)
	if back == null:
		return
	check_eq(back.map.get_elevation(Vector2i(13, 3)), 2, "elevation survives")
	check_eq(back.map.get_storeys(Vector2i(5, 5)), 3, "storeys survive")
	check(back.map.has_stairs(Vector2i(4, 4)), "stairs survive")
	var flat := Scenario.create(10, 10)
	check(not flat.to_data()["map"].has("elevation"), "flat scenarios say nothing of height")
	# Swapping sides flips the map east to west, heights, storeys and stairs with it.
	var swapped := s.swapped()
	check_eq(swapped.map.get_elevation(Vector2i(19 - 13, 3)), 2, "the hill moves across")
	check_eq(swapped.map.get_storeys(Vector2i(19 - 5, 5)), 3, "so does the tower")
	check(swapped.map.has_stairs(Vector2i(19 - 4, 4)), "and its stairs")


# --- The agent link ---

func test_agents_can_climb() -> void:
	var map := tower(Rect2i(4, 4, 3, 3), 2, Vector2i(4, 5))
	var battle := make_battle(map, [["Rifleman", 0, Vector2i(2, 5)], ["Rifleman", 1, Vector2i(18, 18)]])
	battle.units[0].mobility = 12.0
	var tools := McpGameTools.new(battle)
	var command := tools.command_from_json({"cmd": "move", "unit": 0, "tile": [5, 5], "level": 2})
	check_eq(command.get("level"), 2, "a move takes a level")
	check_eq(tools.validate(command), "", "up to the roof is legal")
	var preview: Dictionary = tools.preview(0, [5, 5], 2)["result"]
	check(preview["reachable"] and preview.get("on_roof", false), "preview knows it's the roof")
	var state := tools.get_state()
	check(state["your_units"][0].has("level"), "units report their floor on maps with height")
	battle.execute(command)
	check_eq(battle.units[0].level, 2, "and the move goes up there")


# --- The AI ---

func test_the_ai_climbs_for_a_shot() -> void:
	# A windowless tower: from inside, nothing to see; from its roof, the enemy in the open.
	var b := MapBuilder.new(24, 12)
	b.building(Rect2i(4, 4, 3, 3), [[Vector2i(4, 5), MapBuilder.W]], [], [], "stone")
	b.tall_building(Rect2i(4, 4, 3, 3), 2, Vector2i(6, 5))
	var battle := make_battle(b.map, [["Rifleman", 0, Vector2i(6, 5)], ["Rifleman", 1, Vector2i(14, 5)]])
	battle.units[1].hp = 2
	var ai := TacticalAI.new(battle, 0)
	var command := ai.decide()
	check_eq(command.get("cmd"), "move", "the AI moves")
	check(int(command.get("level", 0)) > 0, "upstairs, to get a shot (%s)" % command)
