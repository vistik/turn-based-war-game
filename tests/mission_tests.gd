extends SceneTree
## Headless tests for missions (Mission): Last stand, Extraction, Demolition and Assassination.
## Run: Godot --headless --path . -s tests/mission_tests.gd

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


func events_of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## A mission battle on an open 20x20 map. specs are [role, team, pos]; the layout's objectives as given.
func make_mission(specs: Array, mission: Dictionary, objectives := [], max_rounds := 6) -> Battle:
	var rosters := [[], []]
	for spec: Array in specs:
		rosters[spec[1]].append({"role": spec[0], "pos": spec[2]})
	var layout := {"map": TacticalMap.new(20, 20), "objectives": objectives, "spawns": [Vector2i(1, 10)], "reinforcement_spawns": [Vector2i(0, 10)]}
	var battle := BattleFactory.create(layout, rosters, 77, {"mission": mission, "max_rounds": max_rounds})
	battle.start()
	return battle


func unit_of(battle: Battle, role: String, team: int) -> Unit:
	for u in battle.units:
		if u.role == role and u.team == team:
			return u
	return null


func end_turns(battle: Battle, count: int) -> Array:
	var events := []
	for i in count:
		events.append_array(battle.execute({"cmd": "end_turn"}))
	return events


# --- Last stand ---

func test_last_stand_attacker_must_hold_through_a_turn() -> void:
	var objective := {"name": "Crossroads", "center": Vector2(10, 10), "radius": 2.0}
	var battle := make_mission([["Rifleman", 0, Vector2i(5, 10)], ["Rifleman", 1, Vector2i(18, 2)]], {"type": "hold", "attacker": 0}, [objective])
	check_eq(battle.objectives[0]["owner"], 1, "the objective starts out the defender's")
	check_eq(battle.first_team, 0, "the attacker moves first")
	var attacker := unit_of(battle, "Rifleman", 0)
	battle.execute({"cmd": "move", "unit": attacker.id, "tile": Vector2i(10, 10)})
	check_eq(battle.objectives[0]["owner"], 0, "the attacker takes it")
	check_eq(battle.winner, -1, "but hasn't won yet")
	end_turns(battle, 1)
	check_eq(battle.winner, -1, "the defender gets a turn to take it back")
	var events := end_turns(battle, 1)
	check_eq(battle.winner, 0, "still holding it at the start of the attacker's turn wins")
	check_eq(events_of(events, "game_over")[0]["reason"], "taken", "won by taking it")


func test_last_stand_defender_wins_on_the_clock() -> void:
	var objective := {"name": "Crossroads", "center": Vector2(10, 10), "radius": 2.0}
	var battle := make_mission([["Rifleman", 0, Vector2i(1, 1)], ["Rifleman", 1, Vector2i(18, 18)]], {"type": "hold", "attacker": 1}, [objective], 3)
	check_eq(battle.current_team, 1, "the attacker (team 1) moves first")
	var events := end_turns(battle, 5)
	check_eq(battle.winner, -1, "still running in the last round")
	events = end_turns(battle, 1)
	check_eq(battle.winner, 0, "the defender wins when the last round is over")
	check_eq(events_of(events, "game_over")[0]["reason"], "held", "by holding out")
	check_eq(battle.round_number, 3, "after round 3")


# --- Extraction ---

func test_extraction_vip_hides_until_found_then_gets_out() -> void:
	var zone := {"name": "Extraction point", "center": Vector2(2.5, 10.5), "radius": 2.0}
	var battle := make_mission([["Rifleman", 0, Vector2i(4, 10)], [Mission.VIP_ROLE, 0, Vector2i(12, 10)], ["Rifleman", 1, Vector2i(16, 10)]],
			{"type": "extract", "attacker": 0, "vip_team": 0, "found": false, "zone": zone})
	var vip := battle.vip()
	var rescuer := unit_of(battle, "Rifleman", 0)
	var enemy := unit_of(battle, "Rifleman", 1)
	check(vip != null and vip.role == Mission.VIP_ROLE, "the VIP is the mission's")
	check(vip.hiding, "he starts out hiding")
	check_eq(vip.actions, 0, "and can't act")
	check(not battle.team_sees(1, vip), "the enemy can't see him from 4 tiles")
	enemy.pos = Vector2i(14, 10)
	check(battle.team_sees(1, vip), "but can from 2")
	enemy.pos = Vector2i(16, 10)
	battle.execute({"cmd": "move", "unit": rescuer.id, "tile": Vector2i(11, 10)})
	check(not vip.hiding and battle.mission["found"], "a rescuer next to him finds him")
	check_eq(vip.actions, Unit.ACTIONS_PER_TURN, "and he can move at once")
	vip.pos = Vector2i(3, 9)
	battle.execute({"cmd": "move", "unit": vip.id, "tile": Vector2i(2, 10)})
	check_eq(battle.winner, 0, "walking him into the zone wins")


func test_extraction_vip_killed_loses() -> void:
	var zone := {"name": "Extraction point", "center": Vector2(2.5, 10.5), "radius": 2.0}
	var battle := make_mission([["Rifleman", 0, Vector2i(4, 10)], [Mission.VIP_ROLE, 0, Vector2i(12, 10)], ["Rifleman", 1, Vector2i(16, 10)]],
			{"type": "extract", "attacker": 0, "vip_team": 0, "found": false, "zone": zone})
	var vip := battle.vip()
	var events := battle._damage(vip, 99, 0)
	events.append_array(battle._check_victory())
	check_eq(battle.winner, 1, "killing the VIP wins for the defender")
	check_eq(events_of(events, "game_over")[0]["reason"], "vip_killed", "by killing him")


func test_extraction_lone_hiding_vip_is_eliminated() -> void:
	var zone := {"name": "Extraction point", "center": Vector2(2.5, 10.5), "radius": 2.0}
	var battle := make_mission([["Rifleman", 0, Vector2i(4, 10)], [Mission.VIP_ROLE, 0, Vector2i(12, 10)], ["Rifleman", 1, Vector2i(16, 10)]],
			{"type": "extract", "attacker": 0, "vip_team": 0, "found": false, "zone": zone})
	battle._damage(unit_of(battle, "Rifleman", 0), 99, 0)
	battle._check_victory()
	check_eq(battle.winner, 1, "a VIP still hiding can't carry on alone")


func test_vip_known_is_always_seen() -> void:
	var zone := {"name": "Exit", "center": Vector2(10.5, 1.5), "radius": 2.0}
	var battle := make_mission([["Rifleman", 0, Vector2i(1, 18)], [Mission.VIP_ROLE, 1, Vector2i(18, 2)], ["Rifleman", 1, Vector2i(18, 18)]],
			{"type": "assassinate", "attacker": 0, "vip_team": 1, "vip_known": true, "zone": zone, "opens": 3})
	battle.map.set_edge(Vector2i(17, 2), Vector2i(18, 2), Cover.FULL, "wall")
	check(battle.team_sees(0, battle.vip()), "the hunters always know where a known VIP is")
	check(not battle.can_see(unit_of(battle, "Rifleman", 0), battle.vip()), "though they still need a line of sight to shoot")


# --- Assassination ---

func test_assassination_exit_opens_on_its_round() -> void:
	var zone := {"name": "Exit", "center": Vector2(10.5, 1.5), "radius": 2.0}
	var battle := make_mission([["Rifleman", 0, Vector2i(1, 18)], [Mission.VIP_ROLE, 1, Vector2i(12, 2)], ["Rifleman", 1, Vector2i(18, 18)]],
			{"type": "assassinate", "attacker": 0, "vip_team": 1, "zone": zone, "opens": 2})
	var vip := battle.vip()
	end_turns(battle, 1)
	battle.execute({"cmd": "move", "unit": vip.id, "tile": Vector2i(10, 1)})
	check_eq(battle.winner, -1, "the exit isn't open in round 1")
	end_turns(battle, 2)
	check_eq(battle.winner, 1, "at the start of his side's turn in round 2 he is out")


func test_assassination_survival_and_kill() -> void:
	var zone := {"name": "Exit", "center": Vector2(10.5, 1.5), "radius": 2.0}
	var specs := [["Rifleman", 0, Vector2i(1, 18)], [Mission.VIP_ROLE, 1, Vector2i(18, 10)], ["Rifleman", 1, Vector2i(18, 18)]]
	var mission := {"type": "assassinate", "attacker": 0, "vip_team": 1, "zone": zone, "opens": 2}
	var battle := make_mission(specs, mission, [], 2)
	var events := end_turns(battle, 4)
	check_eq(battle.winner, 1, "keeping him alive to the end wins")
	check_eq(events_of(events, "game_over")[0]["reason"], "survived", "by keeping him alive")
	battle = make_mission(specs, mission, [], 2)
	battle._damage(battle.vip(), 99, 0)
	battle._check_victory()
	check_eq(battle.winner, 0, "killing him wins for the hunters")


# --- Demolition ---

func demolition() -> Battle:
	var targets := [{"name": "Ammo dump", "tile": Vector2i(10, 10), "state": "intact", "unit": -1},
			{"name": "Radio post", "tile": Vector2i(10, 16), "state": "intact", "unit": -1}]
	var battle := make_mission([["Rifleman", 0, Vector2i(9, 10)], ["Rifleman", 1, Vector2i(18, 2)], ["Rifleman", 1, Vector2i(18, 18)]],
			{"type": "demolition", "attacker": 0, "targets": targets, "needed": 1})
	battle.map.set_object(Vector2i(10, 10), Cover.HALF, "crate")
	return battle


func test_demolition_charge_goes_off_next_turn() -> void:
	var battle := demolition()
	var sapper := unit_of(battle, "Rifleman", 0)
	check_eq(battle.can_plant(sapper, Vector2i(10, 16)), "Only from next to it", "too far to plant")
	check_eq(battle.charge_tiles(sapper), [Vector2i(10, 10)], "the target next to him")
	var events := battle.execute({"cmd": "plant", "unit": sapper.id, "tile": Vector2i(10, 10)})
	check_eq(events_of(events, "charge")[0]["state"], "armed", "the charge is set")
	check_eq(sapper.actions, 1, "for one action")
	check(battle.can_plant(sapper, Vector2i(10, 10)) != "", "and can't be set twice")
	battle.execute({"cmd": "move", "unit": sapper.id, "tile": Vector2i(4, 10)})
	check_eq(battle.current_team, 1, "with no actions left the turn passes")
	check_eq(battle.target_at(Vector2i(10, 10))["state"], "armed", "still armed through the defender's turn")
	events = end_turns(battle, 1)
	check_eq(battle.target_at(Vector2i(10, 10))["state"], "destroyed", "it goes off at the start of the attacker's turn")
	check_eq(battle.map.get_object(Vector2i(10, 10)), Cover.NONE, "taking the target with it")
	check_eq(battle.winner, 0, "enough targets blown wins")
	check_eq(events_of(events, "game_over")[0]["reason"], "demolished", "by blowing them up")


func test_demolition_defender_pulls_the_charge() -> void:
	var battle := demolition()
	var sapper := unit_of(battle, "Rifleman", 0)
	var guard := unit_of(battle, "Rifleman", 1)
	battle.execute({"cmd": "plant", "unit": sapper.id, "tile": Vector2i(10, 10)})
	end_turns(battle, 1)
	guard.pos = Vector2i(11, 11)
	check(battle.can_plant(guard, Vector2i(10, 10)) != "", "defenders don't plant")
	var events := battle.execute({"cmd": "defuse", "unit": guard.id, "tile": Vector2i(10, 10)})
	check_eq(events_of(events, "charge")[0]["state"], "defused", "the charge is pulled")
	end_turns(battle, 1)
	check_eq(battle.target_at(Vector2i(10, 10))["state"], "intact", "and nothing goes off")
	check_eq(battle.winner, -1, "the battle goes on")


func test_ai_plants_and_pulls_charges() -> void:
	var battle := demolition()
	var command := TacticalAI.new(battle, 0).decide()
	check_eq(command["cmd"], "plant", "the AI plants a charge on the target next to it")
	battle.execute(command)
	end_turns(battle, 1)
	unit_of(battle, "Rifleman", 1).pos = Vector2i(11, 10)
	unit_of(battle, "Rifleman", 0).pos = Vector2i(2, 2)
	check_eq(TacticalAI.new(battle, 1).decide()["cmd"], "defuse", "and pulls one next to its own")


# --- Saving, building, scenarios ---

func test_missions_save_and_load() -> void:
	var points: Battle = GameSession.build_skirmish({"map": "random", "size": 44, "seed": 9})[0]
	check(not points.to_dict().has("mission"), "a points game saves as it always did")
	for type: String in [Mission.HOLD, Mission.EXTRACT, Mission.DEMOLITION, Mission.ASSASSINATE]:
		var setup := {"map": "random", "size": 44, "seed": 9, "mission": {"type": type, "attacker": 1, "vip_known": true}}
		var battle: Battle = GameSession.build_skirmish(setup)[0]
		check_eq(battle.checksum(), GameSession.build_skirmish(setup)[0].checksum(), "%s: the same setup builds the same battle" % type)
		battle.start()
		var copy := Battle.from_dict(battle.to_dict())
		check_eq(copy.checksum(), battle.checksum(), "%s survives a save" % type)
		check_eq(copy.first_team, 1, "%s: the attacker still moves first" % type)
		check_eq(copy.mission_type(), type, "%s: the mission is kept" % type)


func test_missions_build_on_every_theatre() -> void:
	for theatre_id: String in Theatres.IDS:
		for type: String in [Mission.HOLD, Mission.EXTRACT, Mission.DEMOLITION, Mission.ASSASSINATE]:
			for attacker in 2:
				var battle: Battle = GameSession.build_skirmish({"theatre": theatre_id, "map": "random", "size": 44, "seed": 3 + attacker,
						"mission": {"type": type, "attacker": attacker}})[0]
				var what := "%s %s, attacker %d" % [theatre_id, type, attacker]
				check_eq(battle.current_team, attacker, what + ": the attacker moves first")
				check_eq(battle.max_rounds, Mission.rounds_for(type, 44), what + ": the mission's round limit")
				match type:
					Mission.HOLD:
						check_eq(battle.objectives.size(), 1, what + ": one objective")
						check_eq(battle.objectives[0]["owner"], 1 - attacker, what + ": the defender's")
						check(battle.reinforcements.all(func(w: Dictionary) -> bool: return w["team"] == attacker), what + ": no defender reinforcements")
					Mission.EXTRACT, Mission.ASSASSINATE:
						var vip := battle.vip()
						check(vip != null, what + ": has a VIP")
						if vip != null:
							check_eq(vip.team, attacker if type == Mission.EXTRACT else 1 - attacker, what + ": on the right side")
							check_eq(vip.hiding, type == Mission.EXTRACT, what + ": hiding only in an extraction")
							check(battle.map.is_passable(vip.pos), what + ": on open ground")
						check(battle.mission.has("zone"), what + ": has a zone")
						check(battle.map.is_passable(Vector2i(battle.mission["zone"]["center"])), what + ": the zone is open ground")
					Mission.DEMOLITION:
						check_eq(battle.mission["targets"].size(), Mission.TARGET_COUNT, what + ": three targets")
						for t: Dictionary in battle.mission["targets"]:
							check(battle.map.get_object(t["tile"]) != Cover.NONE, what + ": a target stands on its tile")
							var x: int = t["tile"].x
							check((x > 22) == (attacker == 0), what + ": targets on the defender's half")


func test_scenario_mission_round_trip() -> void:
	var battle: Battle = GameSession.build_skirmish({"map": "random", "size": 44, "seed": 12, "mission": {"type": Mission.EXTRACT, "attacker": 0}})[0]
	var scenario := Scenario.from_battle(battle, "Rescue", false)
	check_eq(Mission.type_of(scenario.mission), Mission.EXTRACT, "the mission comes into the scenario")
	check(scenario.units.any(func(u: Dictionary) -> bool: return u["role"] == Mission.VIP_ROLE), "and so does the VIP")
	check(scenario.validate().is_empty(), "with no problems: %s" % ", ".join(scenario.validate()))
	var loaded := Scenario.from_data(JSON.parse_string(scenario.to_json()))
	check(loaded != null, "the JSON loads: %s" % Scenario.last_error)
	check_eq(loaded.mission["zone"]["center"], scenario.mission["zone"]["center"], "zone kept")
	var rebuilt := loaded.build_battle(12)
	check_eq(rebuilt.mission_type(), Mission.EXTRACT, "and builds an extraction")
	check(rebuilt.vip() != null and rebuilt.vip().hiding, "with its VIP hiding")
	var swapped := loaded.swapped()
	check_eq(swapped.mission["attacker"], 1, "swapping sides swaps the attacker")
	check(swapped.validate().is_empty(), "and stays valid: %s" % ", ".join(swapped.validate()))
	loaded.units = loaded.units.filter(func(u: Dictionary) -> bool: return u["role"] != Mission.VIP_ROLE) as Array[Dictionary]
	check(Array(loaded.validate()).any(func(p: String) -> bool: return p.contains("VIP")), "a missing VIP is a problem")
	var demo := Scenario.from_battle(GameSession.build_skirmish({"map": "random", "size": 44, "seed": 12, "mission": {"type": Mission.DEMOLITION, "attacker": 1}})[0])
	check_eq(demo.mission["targets"].size(), Mission.TARGET_COUNT, "demolition targets come along")
	check_eq(Scenario.from_data(JSON.parse_string(demo.to_json())).build_battle(1).mission["targets"].size(), Mission.TARGET_COUNT, "and survive the JSON")
	var hold := Scenario.from_battle(GameSession.build_skirmish({"map": "random", "size": 44, "seed": 12, "mission": {"type": Mission.HOLD, "attacker": 1}})[0])
	check(hold.validate().is_empty(), "a last stand scenario is fine with its one objective")
	hold.objectives.append({"name": "Extra", "center": Vector2(5, 5), "radius": 2.0})
	check(not hold.validate().is_empty(), "but not with two")


func test_war_campaign_rolls_missions() -> void:
	var war := WarCampaign.create(5, 4242, [false, true])
	check(war.maps.all(func(m: Dictionary) -> bool: return m.has("mission")), "every map has a mission setup")
	check_eq(WarCampaign.create(5, 4242, [false, true]).maps, war.maps, "the same seed rolls the same missions")
	var types := {}
	for seed in range(1, 30):
		for m: Dictionary in WarCampaign.create(5, seed).maps:
			types[Mission.type_of(m["mission"])] = true
	check_eq(types.size(), Mission.TYPES.size(), "every mission type turns up")
	check(war.check_orders(0, {"roster": [Mission.VIP_ROLE, "Rifleman", "Rifleman", "Rifleman", "Rifleman"], "flank": "balanced", "posture": "offensive"}) != "",
			"nobody buys a VIP")
	for type: String in [Mission.HOLD, Mission.EXTRACT, Mission.DEMOLITION, Mission.ASSASSINATE]:
		war.maps[war.current]["mission"] = {"type": type, "attacker": 1}
		for side in 2:
			war.maps[war.current]["orders"][side] = war.ai_orders(side)
		var battle := war.build_battle()
		check_eq(battle.mission_type(), type, "the war campaign builds a %s map" % type)
		check_eq(battle.first_team, 1, "%s: the attacker moves first" % type)


func test_mission_text() -> void:
	for type: String in [Mission.HOLD, Mission.EXTRACT, Mission.DEMOLITION, Mission.ASSASSINATE]:
		var battle: Battle = GameSession.build_skirmish({"map": "random", "size": 44, "seed": 5, "mission": {"type": type, "attacker": 0}})[0]
		for team in 2:
			check(Mission.goal_text(battle, team) != "", "%s has a goal for side %d" % [type, team])
			check(Mission.status_text(battle, team).begins_with(Mission.title(type)), "%s status names the mission" % type)
	var tools := McpGameTools.new(GameSession.build_skirmish({"map": "random", "size": 44, "seed": 5, "mission": {"type": Mission.DEMOLITION, "attacker": 0}})[0])
	var state := tools.get_state()
	check(state.has("mission") and state["mission"]["targets"].size() == Mission.TARGET_COUNT, "the agent link reports the mission")
	check_eq(state["mission"]["you_are"], "attacker", "and which side we are")
