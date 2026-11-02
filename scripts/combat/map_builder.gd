class_name MapBuilder
extends RefCounted
## Helpers for laying out maps: terrain, objects, walls and buildings, each placed exactly where it is asked
## for. Nothing is mirrored; the generators (see NaturalMap) and hand-made maps build both sides' ground.

const N := Vector2i(0, -1)
const E := Vector2i(1, 0)
const S := Vector2i(0, 1)
const W := Vector2i(-1, 0)

var map: TacticalMap


func _init(width: int, height: int) -> void:
	map = TacticalMap.new(width, height)


func terrain(rect: Rect2i, kind: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y)
			if map.in_bounds(p):
				map.set_terrain(p, kind)


func object(p: Vector2i, cover: int, kind: String) -> void:
	if map.in_bounds(p):
		map.set_object(p, cover, kind)


func mine(p: Vector2i, kind := "mine") -> void:
	map.set_mine(p, true, kind)


## Sets the edge on the dir side of tile p.
func side(p: Vector2i, dir: Vector2i, cover: int, kind: String) -> void:
	map.set_edge(p, p + dir, cover, kind)


## Puts edges all around a rect, then applies overrides [tile, dir, cover, kind] (cover NONE for a gap).
## Sides listed in `skip` are left open.
func enclose(rect: Rect2i, cover: int, kind: String, overrides: Array = [], skip: Array = []) -> void:
	for x in range(rect.position.x, rect.end.x):
		if not skip.has(N):
			side(Vector2i(x, rect.position.y), N, cover, kind)
		if not skip.has(S):
			side(Vector2i(x, rect.end.y - 1), S, cover, kind)
	for y in range(rect.position.y, rect.end.y):
		if not skip.has(W):
			side(Vector2i(rect.position.x, y), W, cover, kind)
		if not skip.has(E):
			side(Vector2i(rect.end.x - 1, y), E, cover, kind)
	for o: Array in overrides:
		side(o[0], o[1], o[2], o[3])


## A walled building with an indoor floor, doors [tile, dir] and windows [tile, dir]. Sides in `skip` get no
## wall. `style` "bamboo" makes a bamboo hut (walls a tank can push through), "mud" a mud-brick house, instead
## of a stone house.
func building(rect: Rect2i, doors: Array, windows: Array, skip: Array = [], style := "stone") -> void:
	terrain(rect, TacticalMap.Terrain.INDOOR)
	var wall: String = {"bamboo": "bamboo_wall", "mud": "mud_wall"}.get(style, "wall")
	var window: String = {"bamboo": "bamboo_window", "mud": "mud_window"}.get(style, "window")
	var overrides := []
	for d: Array in doors:
		overrides.append([d[0], d[1], Cover.NONE, ""])
	for w: Array in windows:
		overrides.append([w[0], w[1], Cover.HALF, window])
	enclose(rect, Cover.FULL, wall, overrides, skip)
