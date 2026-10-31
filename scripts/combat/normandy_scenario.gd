class_name NormandyScenario
extends RefCounted
## A hand-made 48x48 Normandy village. The Allies come from the west, Germany from the east.
## Three objectives sit on the centre line: the church, the crossroads and the farm.

const SIZE := 48
const ROSTER := ["Officer", "Rifleman", "AT", "Medic", "SMG", "MG", "Sniper", "Mortar"]
const REINFORCEMENTS := ["Tank", "Rifleman"]
const REINFORCEMENT_ROUND := 4
## Allied (west) start positions. Germany gets the mirror image.
const SPAWNS := [
	Vector2i(3, 23), Vector2i(2, 19), Vector2i(2, 28), Vector2i(1, 24), Vector2i(3, 26), Vector2i(3, 21),
	Vector2i(1, 16), Vector2i(1, 31), Vector2i(2, 22), Vector2i(1, 26), Vector2i(3, 18), Vector2i(3, 29),
]
const REINFORCEMENT_SPAWNS := [Vector2i(1, 23), Vector2i(0, 10), Vector2i(0, 38)]
const N := MapBuilder.N
const E := MapBuilder.E
const S := MapBuilder.S
const W := MapBuilder.W


static func build(seed := 0) -> Battle:
	var waves := []
	for team in Battle.TEAM_COUNT:
		waves.append({"round": REINFORCEMENT_ROUND, "team": team, "roster": REINFORCEMENTS})
	return BattleFactory.create(layout(), [ROSTER, ROSTER], seed, {"reinforcements": waves})


static func layout() -> Dictionary:
	var b := MapBuilder.new(SIZE, SIZE)
	# Roads: the main east-west road, and the lane from the church down to the farm.
	b.terrain(Rect2i(0, 23, SIZE, 2), TacticalMap.Terrain.ROAD, false)
	b.terrain(Rect2i(23, 11, 2, 23), TacticalMap.Terrain.ROAD, false)

	# The church (north objective): pews inside, doors onto the lane.
	b.building(Rect2i(19, 4, 5, 7), [[Vector2i(23, 10), S]],
			[[Vector2i(19, 6), W], [Vector2i(19, 8), W], [Vector2i(21, 4), N], [Vector2i(23, 4), N]], [E])
	for p in [Vector2i(20, 6), Vector2i(21, 6), Vector2i(20, 8), Vector2i(21, 8)]:
		b.object(p, Cover.HALF, "pew")

	# The farm (south objective): a walled courtyard with hay bales in front of the farmhouse.
	b.enclose(Rect2i(18, 34, 6, 6), Cover.HALF, "stone", [[Vector2i(23, 34), N, Cover.NONE, ""], [Vector2i(18, 36), W, Cover.NONE, ""]], true, [E])
	b.building(Rect2i(19, 40, 5, 5), [[Vector2i(23, 40), N]], [[Vector2i(19, 42), W], [Vector2i(21, 44), S]], [E])
	for p in [Vector2i(20, 35), Vector2i(20, 38), Vector2i(22, 37)]:
		b.object(p, Cover.HALF, "hay")

	# Village houses at the crossroads, with sandbagged corners facing the junction.
	b.building(Rect2i(16, 16, 6, 5), [[Vector2i(19, 20), S], [Vector2i(21, 18), E]],
			[[Vector2i(18, 16), N], [Vector2i(20, 16), N], [Vector2i(16, 18), W]])
	b.building(Rect2i(16, 27, 6, 5), [[Vector2i(19, 27), N]],
			[[Vector2i(18, 31), S], [Vector2i(20, 31), S], [Vector2i(16, 29), W], [Vector2i(21, 29), E]])
	for p in [Vector2i(21, 22), Vector2i(21, 25), Vector2i(20, 22)]:
		b.object(p, Cover.HALF, "sandbags")
	for p in [Vector2i(15, 21), Vector2i(15, 26), Vector2i(22, 15)]:
		b.object(p, Cover.HALF, "crate")

	# Stone walls along the main road, with gaps.
	for x in range(6, 15):
		if x != 10:
			b.side(Vector2i(x, 22), S, Cover.HALF, "stone")
		if x != 9:
			b.side(Vector2i(x, 25), N, Cover.HALF, "stone")

	# Bocage: hedgerow fields. A wheat field to the north, an orchard to the south.
	b.enclose(Rect2i(5, 3, 11, 10), Cover.FULL, "hedge", [[Vector2i(10, 12), S, Cover.NONE, ""], [Vector2i(15, 7), E, Cover.NONE, ""], [Vector2i(8, 3), N, Cover.NONE, ""]])
	b.terrain(Rect2i(6, 4, 9, 8), TacticalMap.Terrain.WHEAT)
	b.enclose(Rect2i(5, 35, 11, 10), Cover.FULL, "hedge", [[Vector2i(10, 35), N, Cover.NONE, ""], [Vector2i(15, 40), E, Cover.NONE, ""]])
	for y in [37, 40, 43]:
		for x in [7, 10, 13]:
			b.object(Vector2i(x, y), Cover.FULL, "tree")
	# Hedgerows screening each start area.
	for y in range(15, 33):
		if y != 18 and y != 29 and (y < 22 or y > 25):
			b.side(Vector2i(7, y), E, Cover.FULL, "hedge")
	# A small wheat field and a copse between the start and the village.
	b.terrain(Rect2i(9, 27, 4, 5), TacticalMap.Terrain.WHEAT)
	for p in [Vector2i(10, 16), Vector2i(12, 17), Vector2i(10, 19), Vector2i(13, 20)]:
		b.object(p, Cover.FULL, "tree")

	# Scattered cover in no man's land near the centre line.
	for p in [Vector2i(18, 13), Vector2i(20, 33), Vector2i(12, 25), Vector2i(14, 31), Vector2i(17, 46), Vector2i(19, 2)]:
		b.terrain(Rect2i(p, Vector2i.ONE), TacticalMap.Terrain.CRATER)
	for p in [Vector2i(3, 8), Vector2i(2, 41), Vector2i(17, 10), Vector2i(16, 37)]:
		b.object(p, Cover.FULL, "rock")
	for p in [Vector2i(17, 12), Vector2i(18, 24), Vector2i(13, 33)]:
		b.object(p, Cover.HALF, "sandbags")
	b.terrain(Rect2i(1, 1, 3, 4), TacticalMap.Terrain.ROUGH)
	b.terrain(Rect2i(1, 43, 3, 4), TacticalMap.Terrain.ROUGH)
	b.terrain(Rect2i(16, 6, 2, 3), TacticalMap.Terrain.ROUGH)

	return {
		"map": b.map,
		"objectives": [
			{"name": "Church", "center": Vector2(24, 7.5), "radius": 2.5},
			{"name": "Crossroads", "center": Vector2(24, 24), "radius": 2.5},
			{"name": "Farm", "center": Vector2(24, 37), "radius": 2.5},
		],
		"spawns": SPAWNS,
		"reinforcement_spawns": REINFORCEMENT_SPAWNS,
	}
