class_name DrawBatch
extends RefCounted
## Collects drawing (the same draw_* calls a CanvasItem takes) into one coloured triangle mesh, then hands it
## to a canvas item in a single call. The terrain painters draw a ground chunk as thousands of small
## polygons, lines and circles; drawn one by one, every frame turned them into thousands of draw calls,
## and a big map (most of all one covered in jungle) dropped to a crawl. Batched, a chunk is one draw call.
##
## Lines become thin quads (at least a pixel wide) and circles polygons; nothing is antialiased.

## Vertices per mesh before a new one is started.
const MAX_VERTICES := 30000

var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
## Meshes already full: [points, colors, indices].
var _done: Array = []


func draw_colored_polygon(points: PackedVector2Array, color: Color, _uvs := PackedVector2Array(), _texture: Texture2D = null) -> void:
	var count := points.size()
	if count < 3 or color.a <= 0.0:
		return
	var triangles := Geometry2D.triangulate_polygon(points)
	if triangles.is_empty():
		# Degenerate or self-touching outline: fan it from the first point.
		for i in range(1, count - 1):
			triangles.append_array([0, i, i + 1])
	_reserve(count)
	var base := _points.size()
	_points.append_array(points)
	for i in count:
		_colors.append(color)
	for index in triangles:
		_indices.append(base + index)


func draw_line(from: Vector2, to: Vector2, color: Color, width := -1.0, _antialiased := false) -> void:
	var along := to - from
	if along.length_squared() < 0.0001 or color.a <= 0.0:
		return
	var half := Vector2(-along.y, along.x).normalized() * maxf(1.0, width) * 0.5
	_quad(from + half, to + half, to - half, from - half, color)


func draw_polyline(points: PackedVector2Array, color: Color, width := -1.0, _antialiased := false) -> void:
	for i in points.size() - 1:
		draw_line(points[i], points[i + 1], color, width)


func draw_multiline(points: PackedVector2Array, color: Color, width := -1.0, _antialiased := false) -> void:
	for i in range(0, points.size() - 1, 2):
		draw_line(points[i], points[i + 1], color, width)


func draw_circle(position: Vector2, radius: float, color: Color, filled := true, width := -1.0, _antialiased := false) -> void:
	if radius <= 0.0:
		return
	var segments := clampi(int(radius * 1.5), 8, 24)
	if not filled:
		draw_arc(position, radius, 0.0, TAU, segments + 1, color, width)
		return
	var ring := PackedVector2Array()
	for i in segments:
		ring.append(position + Vector2.from_angle(TAU * i / segments) * radius)
	_reserve(segments + 1)
	var base := _points.size()
	_points.append(position)
	_colors.append(color)
	_points.append_array(ring)
	for i in segments:
		_colors.append(color)
		_indices.append_array([base, base + 1 + i, base + 1 + (i + 1) % segments])


func draw_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, point_count: int, color: Color, width := -1.0, _antialiased := false) -> void:
	var points := PackedVector2Array()
	for i in maxi(2, point_count):
		points.append(center + Vector2.from_angle(lerpf(start_angle, end_angle, i / float(maxi(2, point_count) - 1))) * radius)
	draw_polyline(points, color, width)


## Hands everything drawn so far to the canvas item (call it from that item's draw), and empties the batch.
func flush(item: CanvasItem) -> void:
	var rid := item.get_canvas_item()
	_done.append([_points, _colors, _indices])
	for mesh: Array in _done:
		if not mesh[2].is_empty():
			RenderingServer.canvas_item_add_triangle_array(rid, mesh[2], mesh[0], mesh[1])
	_done.clear()
	_points = PackedVector2Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	_reserve(4)
	var base := _points.size()
	_points.append_array([a, b, c, d])
	_colors.append_array([color, color, color, color])
	_indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## Starts a new mesh when this one would grow too big.
func _reserve(count: int) -> void:
	if _points.size() + count > MAX_VERTICES:
		_done.append([_points, _colors, _indices])
		_points = PackedVector2Array()
		_colors = PackedColorArray()
		_indices = PackedInt32Array()
