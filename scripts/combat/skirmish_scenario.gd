class_name SkirmishScenario
extends RefCounted
## Hand-made 24x24 test map, four soldiers a side.
## Legend: . floor, : rough ground, o half cover object, # full cover object, A / B team spawns.

const LAYOUT := [
	"::::........:::.........",
	":::.....o....::.....##..",
	"::......o...........##..",
	"...##..............o....",
	".A.##..............o...B",
	".......:::..........:...",
	"..o....:::..........:...",
	"..o.....................",
	".A......................",
	".....##.......o.....o.B.",
	"......#.......o.....o...",
	".......................#",
	".A..o.................##",
	"....o..........o........",
	"...............o....::B.",
	"..::......::..........:.",
	"..::......::......##....",
	".......#..........##....",
	".A.....#.....o..........",
	"......::.....o......o..B",
	"......::.......::...o...",
	"..o............::.......",
	"..o......##.............",
	":::......##.......:::::.",
]
const ROSTER := ["Rifleman", "Assault", "Heavy", "Medic"]
const NAMES := [["Ash", "Brick", "Cole", "Dune"], ["Vex", "Wolf", "Xan", "Yara"]]
## The central building: full walls with doors and windows (half cover) punched in.
const BUILDING := Rect2i(9, 8, 6, 7)
const DOORS := [[Vector2i(8, 11), Vector2i(9, 11)], [Vector2i(14, 12), Vector2i(15, 12)], [Vector2i(12, 14), Vector2i(12, 15)]]
const WINDOWS := [
	[Vector2i(11, 7), Vector2i(11, 8)], [Vector2i(12, 7), Vector2i(12, 8)],
	[Vector2i(10, 14), Vector2i(10, 15)], [Vector2i(8, 9), Vector2i(9, 9)], [Vector2i(14, 9), Vector2i(15, 9)],
]
## A low fence north of the building's east side.
const FENCE := [[Vector2i(16, 6), Vector2i(16, 7)], [Vector2i(17, 6), Vector2i(17, 7)], [Vector2i(18, 6), Vector2i(18, 7)], [Vector2i(19, 6), Vector2i(19, 7)]]


static func build(seed := 0) -> Battle:
	var map := TacticalMap.new(LAYOUT[0].length(), LAYOUT.size())
	var spawns := [[], []]
	for y in LAYOUT.size():
		var row: String = LAYOUT[y]
		assert(row.length() == map.width, "Row %d has the wrong width" % y)
		for x in row.length():
			var p := Vector2i(x, y)
			match row[x]:
				":":
					map.set_terrain(p, TacticalMap.Terrain.ROUGH)
				"o":
					map.set_object(p, Cover.HALF)
				"#":
					map.set_object(p, Cover.FULL)
				"A":
					spawns[0].append(p)
				"B":
					spawns[1].append(p)

	for y in range(BUILDING.position.y, BUILDING.end.y):
		for x in range(BUILDING.position.x, BUILDING.end.x):
			map.set_terrain(Vector2i(x, y), TacticalMap.Terrain.INDOOR)
	_wall_rect(map, BUILDING)
	for pair in DOORS:
		map.set_edge(pair[0], pair[1], Cover.NONE)
	for pair in WINDOWS + FENCE:
		map.set_edge(pair[0], pair[1], Cover.HALF)

	var units: Array[Unit] = []
	for team in Battle.TEAM_COUNT:
		for i in ROSTER.size():
			units.append(Unit.create(units.size(), NAMES[team][i], ROSTER[i], team, spawns[team][i]))
	return Battle.new(map, units, seed)


static func _wall_rect(map: TacticalMap, rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		map.set_edge(Vector2i(x, rect.position.y - 1), Vector2i(x, rect.position.y), Cover.FULL)
		map.set_edge(Vector2i(x, rect.end.y - 1), Vector2i(x, rect.end.y), Cover.FULL)
	for y in range(rect.position.y, rect.end.y):
		map.set_edge(Vector2i(rect.position.x - 1, y), Vector2i(rect.position.x, y), Cover.FULL)
		map.set_edge(Vector2i(rect.end.x - 1, y), Vector2i(rect.end.x, y), Cover.FULL)
