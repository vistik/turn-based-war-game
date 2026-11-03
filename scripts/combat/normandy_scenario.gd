class_name NormandyScenario
extends RefCounted
## A hand-made 48x48 Normandy village. The Allies come from the west, Germany from the east. Nothing is
## mirrored: the road jogs south at the crossroads, the church stands nearer the Germans and the farm nearer the
## Allies, and each side's approach has its own fields, hedges and copses. The three objectives are about as
## far from each side in all.

const SIZE := 48
const ROSTER := ["Officer", "Rifleman", "AT", "Medic", "SMG", "MG", "Sniper", "Mortar"]
const REINFORCEMENTS := ["Tank", "Rifleman"]
const REINFORCEMENT_ROUND := 4
## Start positions: the Allies on the west edge round the road, Germany on the east edge round theirs.
const SPAWNS := [
	[Vector2i(3, 23), Vector2i(2, 19), Vector2i(2, 28), Vector2i(1, 24), Vector2i(3, 26), Vector2i(3, 21),
	Vector2i(1, 16), Vector2i(1, 31), Vector2i(2, 22), Vector2i(1, 26), Vector2i(3, 18), Vector2i(3, 29)],
	[Vector2i(44, 25), Vector2i(45, 21), Vector2i(45, 29), Vector2i(46, 24), Vector2i(44, 27), Vector2i(44, 22),
	Vector2i(46, 18), Vector2i(46, 32), Vector2i(45, 24), Vector2i(46, 27), Vector2i(44, 19), Vector2i(44, 30)],
]
const REINFORCEMENT_SPAWNS := [[Vector2i(0, 22), Vector2i(0, 10), Vector2i(0, 38)], [Vector2i(47, 24), Vector2i(47, 6), Vector2i(47, 41)]]
const N := MapBuilder.N
const E := MapBuilder.E
const S := MapBuilder.S
const W := MapBuilder.W


## `deployments`: per side {"flank", "posture"} as in WarCampaign.deploy, or {} for the usual spawns.
static func build(seed := 0, deployments := [{}, {}]) -> Battle:
	var waves := []
	for team in Battle.TEAM_COUNT:
		waves.append({"round": REINFORCEMENT_ROUND, "team": team, "roster": REINFORCEMENTS})
	var village := layout()
	return BattleFactory.create(village, WarCampaign.deploy(village, [ROSTER, ROSTER], deployments), seed, {"reinforcements": waves})


static func layout() -> Dictionary:
	var b := MapBuilder.new(SIZE, SIZE)
	# Roads: the main road comes in from the west, jogs south at the crossroads and runs on east. A lane runs
	# north to the church and a track south-west to the farm.
	b.terrain(Rect2i(0, 22, 22, 2), TacticalMap.Terrain.ROAD)
	b.terrain(Rect2i(20, 22, 4, 4), TacticalMap.Terrain.ROAD)
	b.terrain(Rect2i(22, 24, 26, 2), TacticalMap.Terrain.ROAD)
	b.terrain(Rect2i(23, 8, 2, 14), TacticalMap.Terrain.ROAD)
	b.terrain(Rect2i(21, 26, 2, 10), TacticalMap.Terrain.ROAD)
	b.terrain(Rect2i(20, 35, 1, 1), TacticalMap.Terrain.ROAD)

	# The church (north objective), east of the lane: pews inside, the door onto the lane.
	b.building(Rect2i(25, 6, 7, 5), [[Vector2i(25, 8), W]],
			[[Vector2i(27, 6), N], [Vector2i(29, 6), N], [Vector2i(31, 8), E], [Vector2i(28, 10), S]])
	for p in [Vector2i(27, 7), Vector2i(29, 7), Vector2i(27, 9), Vector2i(29, 9)]:
		b.object(p, Cover.HALF, "pew")

	# The farm (south objective), west of the track: a walled yard with hay in front of the farmhouse.
	b.enclose(Rect2i(13, 34, 7, 5), Cover.HALF, "stone", [[Vector2i(19, 35), E, Cover.NONE, ""], [Vector2i(13, 36), W, Cover.NONE, ""]])
	b.building(Rect2i(13, 39, 6, 4), [[Vector2i(15, 39), N]], [[Vector2i(13, 40), W], [Vector2i(17, 42), S], [Vector2i(18, 40), E]])
	for p in [Vector2i(14, 35), Vector2i(17, 37), Vector2i(18, 35)]:
		b.object(p, Cover.HALF, "hay")

	# Village houses round the crossroads, each facing the road.
	b.building(Rect2i(15, 16, 6, 5), [[Vector2i(17, 20), S]], [[Vector2i(16, 16), N], [Vector2i(19, 16), N], [Vector2i(15, 18), W], [Vector2i(20, 18), E]])
	b.building(Rect2i(14, 25, 5, 4), [[Vector2i(16, 25), N]], [[Vector2i(14, 26), W], [Vector2i(16, 28), S], [Vector2i(18, 27), E]])
	b.building(Rect2i(26, 17, 5, 4), [[Vector2i(26, 19), W]], [[Vector2i(28, 17), N], [Vector2i(30, 19), E], [Vector2i(28, 20), S]])
	b.building(Rect2i(26, 27, 6, 4), [[Vector2i(28, 27), N]], [[Vector2i(26, 29), W], [Vector2i(31, 28), E], [Vector2i(29, 30), S]])
	b.building(Rect2i(33, 19, 4, 4), [[Vector2i(34, 22), S]], [[Vector2i(33, 20), W], [Vector2i(36, 20), E]])
	for p in [Vector2i(19, 21), Vector2i(25, 23), Vector2i(23, 26)]:
		b.object(p, Cover.HALF, "sandbags")
	for p in [Vector2i(13, 21), Vector2i(25, 21), Vector2i(32, 26)]:
		b.object(p, Cover.HALF, "crate")

	# Stone walls along the west road, broken by gates; a low wall in front of the German start.
	for x in range(6, 14):
		if x != 9:
			b.side(Vector2i(x, 21), S, Cover.HALF, "stone")
		if x != 11:
			b.side(Vector2i(x, 24), N, Cover.HALF, "stone")
	for y in range(15, 31):
		if y != 20 and y != 28 and (y < 24 or y > 25):
			b.side(Vector2i(41, y), E, Cover.HALF, "stone")

	# The Allied side: a hedged wheat field to the north-west, an orchard to the south-west, a hedgerow
	# screening the start and a copse beside the road.
	b.enclose(Rect2i(4, 3, 12, 11), Cover.FULL, "hedge", [[Vector2i(10, 13), S, Cover.NONE, ""], [Vector2i(15, 7), E, Cover.NONE, ""], [Vector2i(7, 3), N, Cover.NONE, ""]])
	b.terrain(Rect2i(5, 4, 10, 9), TacticalMap.Terrain.WHEAT)
	b.enclose(Rect2i(3, 40, 9, 7), Cover.FULL, "hedge", [[Vector2i(8, 40), N, Cover.NONE, ""], [Vector2i(11, 43), E, Cover.NONE, ""]])
	for p in [Vector2i(5, 42), Vector2i(8, 42), Vector2i(5, 45), Vector2i(8, 45)]:
		b.object(p, Cover.FULL, "tree")
	for y in range(15, 33):
		if y != 18 and y != 29 and (y < 22 or y > 24):
			b.side(Vector2i(7, y), E, Cover.FULL, "hedge")
	for p in [Vector2i(10, 27), Vector2i(12, 29), Vector2i(9, 31), Vector2i(11, 32)]:
		b.object(p, Cover.FULL, "tree")

	# The German side: a big walled wheat field to the north-east, a hedged pasture to the south-east, an
	# orchard behind the farm track and a copse by their start.
	b.enclose(Rect2i(34, 3, 10, 12), Cover.HALF, "stone", [[Vector2i(38, 14), S, Cover.NONE, ""], [Vector2i(34, 9), W, Cover.NONE, ""]])
	b.terrain(Rect2i(35, 4, 8, 10), TacticalMap.Terrain.WHEAT)
	b.enclose(Rect2i(33, 30, 11, 9), Cover.FULL, "hedge", [[Vector2i(37, 30), N, Cover.NONE, ""], [Vector2i(33, 35), W, Cover.NONE, ""], [Vector2i(40, 38), S, Cover.NONE, ""]])
	for p in [Vector2i(36, 33), Vector2i(40, 35)]:
		b.object(p, Cover.HALF, "hay")
	for y in [41, 44]:
		for x in [26, 29, 32]:
			b.object(Vector2i(x, y), Cover.FULL, "tree")
	for p in [Vector2i(36, 16), Vector2i(38, 17), Vector2i(37, 19), Vector2i(39, 20), Vector2i(36, 21)]:
		b.object(p, Cover.FULL, "tree")

	# Shell holes, rocks and sandbags where the fighting has already been.
	for p in [Vector2i(19, 12), Vector2i(30, 34), Vector2i(12, 24), Vector2i(16, 31), Vector2i(37, 46), Vector2i(20, 2), Vector2i(31, 15)]:
		b.terrain(Rect2i(p, Vector2i.ONE), TacticalMap.Terrain.CRATER)
	for p in [Vector2i(3, 8), Vector2i(2, 41), Vector2i(18, 11), Vector2i(43, 44), Vector2i(29, 13)]:
		b.object(p, Cover.FULL, "rock")
	for p in [Vector2i(17, 13), Vector2i(30, 23), Vector2i(26, 35)]:
		b.object(p, Cover.HALF, "sandbags")
	b.terrain(Rect2i(1, 1, 3, 4), TacticalMap.Terrain.ROUGH)
	b.terrain(Rect2i(44, 40, 3, 5), TacticalMap.Terrain.ROUGH)
	b.terrain(Rect2i(18, 5, 2, 3), TacticalMap.Terrain.ROUGH)

	return {
		"map": b.map,
		"objectives": [
			{"name": "Church", "center": Vector2(28.5, 8.5), "radius": 2.5},
			{"name": "Crossroads", "center": Vector2(22.5, 24.0), "radius": 2.5},
			{"name": "Farm", "center": Vector2(16.5, 36.5), "radius": 2.5},
		],
		"spawns": SPAWNS,
		"reinforcement_spawns": REINFORCEMENT_SPAWNS,
	}
