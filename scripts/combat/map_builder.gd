class_name MapBuilder
extends RefCounted
## Helpers for laying out maps. Features are placed on the west half and, by default, mirrored
## onto the east half, so both sides always fight over the same ground.

const N := Vector2i(0, -1)
const E := Vector2i(1, 0)
const S := Vector2i(0, 1)
const W := Vector2i(-1, 0)

var map: TacticalMap


func _init(width: int, height: int) -> void:
	map = TacticalMap.new(width, height)


func mirror(p: Vector2i) -> Vector2i:
	return Vector2i(map.width - 1 - p.x, p.y)


func terrain(rect: Rect2i, kind: int, mirrored := true) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y)
			if map.in_bounds(p):
				map.set_terrain(p, kind)
				if mirrored:
					map.set_terrain(mirror(p), kind)


func object(p: Vector2i, cover: int, kind: String, mirrored := true) -> void:
	map.set_object(p, cover, kind)
	if mirrored:
		map.set_object(mirror(p), cover, kind)


func mine(p: Vector2i, mirrored := true, kind := "mine") -> void:
	map.set_mine(p, true, kind)
	if mirrored:
		map.set_mine(mirror(p), true, kind)


## Sets the edge on the dir side of tile p.
func side(p: Vector2i, dir: Vector2i, cover: int, kind: String, mirrored := true) -> void:
	map.set_edge(p, p + dir, cover, kind)
	if mirrored:
		map.set_edge(mirror(p), mirror(p + dir), cover, kind)


## Puts edges all around a rect, then applies overrides [tile, dir, cover, kind] (cover NONE for a gap).
## Sides listed in `skip` are left open.
func enclose(rect: Rect2i, cover: int, kind: String, overrides: Array = [], mirrored := true, skip: Array = []) -> void:
	for x in range(rect.position.x, rect.end.x):
		if not skip.has(N):
			side(Vector2i(x, rect.position.y), N, cover, kind, mirrored)
		if not skip.has(S):
			side(Vector2i(x, rect.end.y - 1), S, cover, kind, mirrored)
	for y in range(rect.position.y, rect.end.y):
		if not skip.has(W):
			side(Vector2i(rect.position.x, y), W, cover, kind, mirrored)
		if not skip.has(E):
			side(Vector2i(rect.end.x - 1, y), E, cover, kind, mirrored)
	for o: Array in overrides:
		side(o[0], o[1], o[2], o[3], mirrored)


## A walled building with an indoor floor, doors [tile, dir] and windows [tile, dir].
## Buildings that straddle the centre line are built as a west half that skips its east wall.
## `style` "bamboo" makes a bamboo hut (walls a tank can push through), "mud" a mud-brick house, instead of a
## stone house.
func building(rect: Rect2i, doors: Array, windows: Array, skip: Array = [], style := "stone", mirrored := true) -> void:
	terrain(rect, TacticalMap.Terrain.INDOOR, mirrored)
	var wall: String = {"bamboo": "bamboo_wall", "mud": "mud_wall"}.get(style, "wall")
	var window: String = {"bamboo": "bamboo_window", "mud": "mud_window"}.get(style, "window")
	var overrides := []
	for d: Array in doors:
		overrides.append([d[0], d[1], Cover.NONE, ""])
	for w: Array in windows:
		overrides.append([w[0], w[1], Cover.HALF, window])
	enclose(rect, Cover.FULL, wall, overrides, mirrored, skip)
