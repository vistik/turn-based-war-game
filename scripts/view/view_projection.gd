class_name ViewProjection
extends RefCounted
## Maps grid space to screen space and back, for an isometric or top-down view rotated in quarter turns.
## In grid space tile p covers [p, p + 1), so a unit stands at p + 0.5. Height is in tile units.

const TILE_W := 64.0
const TILE_H := 32.0
const HEIGHT_PX := 36.0
const TOP_DOWN_TILE := 40.0

var isometric := true
## Quarter turns clockwise.
var rotation := 0
var size: Vector2


func _init(p_size: Vector2) -> void:
	size = p_size


func rotate_grid(g: Vector2) -> Vector2:
	match rotation:
		1:
			return Vector2(size.y - g.y, g.x)
		2:
			return Vector2(size.x - g.x, size.y - g.y)
		3:
			return Vector2(g.y, size.x - g.x)
	return g


func unrotate_grid(r: Vector2) -> Vector2:
	match rotation:
		1:
			return Vector2(r.y, size.y - r.x)
		2:
			return Vector2(size.x - r.x, size.y - r.y)
		3:
			return Vector2(size.x - r.y, r.x)
	return r


## Projects an already rotated grid point. Height only shows in the isometric view.
func project_rotated(r: Vector2, height := 0.0) -> Vector2:
	if isometric:
		return Vector2((r.x - r.y) * TILE_W * 0.5, (r.x + r.y) * TILE_H * 0.5 - height * HEIGHT_PX)
	return r * TOP_DOWN_TILE


func project(g: Vector2, height := 0.0) -> Vector2:
	return project_rotated(rotate_grid(g), height)


## The ground-level grid point under a screen point.
func unproject(s: Vector2) -> Vector2:
	var r := s / TOP_DOWN_TILE
	if isometric:
		var a := s.x / (TILE_W * 0.5)
		var b := s.y / (TILE_H * 0.5)
		r = Vector2((a + b) * 0.5, (b - a) * 0.5)
	return unrotate_grid(r)


func tile_at(s: Vector2) -> Vector2i:
	var g := unproject(s)
	return Vector2i(floori(g.x), floori(g.y))


## Draw-order key: things with a larger depth are nearer the viewer and drawn later.
func depth(g: Vector2) -> float:
	var r := rotate_grid(g)
	return r.x + r.y
