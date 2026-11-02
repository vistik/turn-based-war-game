class_name MapPreview
extends TextureRect
## A minimap of a battle layout, seen from above: ground, woods and cover, walls and hedges, buildings,
## the objectives and where each side starts. Mines, traps, IEDs and tunnels are secret and not shown.

const PIXELS := 4
## Ground colours by TacticalMap.Terrain, and the theatres' own grass and roads.
const GROUND := {
	TacticalMap.Terrain.FLOOR: Color("587842"), TacticalMap.Terrain.ROUGH: Color("6f6c45"), TacticalMap.Terrain.RUBBLE: Color("77706a"),
	TacticalMap.Terrain.INDOOR: Color("8a5a46"), TacticalMap.Terrain.ROAD: Color("9a8a68"), TacticalMap.Terrain.WHEAT: Color("b8a050"),
	TacticalMap.Terrain.CRATER: Color("3b342b"), TacticalMap.Terrain.TRAMPLED: Color("a08d4c"), TacticalMap.Terrain.WIRE: Color("5a5650"),
	TacticalMap.Terrain.JUNGLE: Color("23401b"), TacticalMap.Terrain.PADDY: Color("5f8c86"), TacticalMap.Terrain.TALL_GRASS: Color("8f9c4e"),
	TacticalMap.Terrain.TRENCH: Color("4a3b2a"),
}
const THEATRE_GROUND := {
	"vietnam": {TacticalMap.Terrain.FLOOR: Color("568431"), TacticalMap.Terrain.ROAD: Color("a2563a")},
	"modern": {TacticalMap.Terrain.FLOOR: Color("b9a77c"), TacticalMap.Terrain.ROUGH: Color("a08a62"), TacticalMap.Terrain.ROAD: Color("8d8273"),
		TacticalMap.Terrain.INDOOR: Color("9c8466")},
}
const TREE := Color("2c4a22")
const ROCK := Color("8a8984")
const CLUTTER := Color("c2a868")
const BURNS := Color("9a3a26")
const WALL := Color("2a2420")
const HEDGE := Color("1f3a18")
const LOW_WALL := Color("c6bca7")
const DYKE := Color("6b5137")
const OBJECTIVE := Color("f2d16b")
const TREE_KINDS := ["tree", "palm", "bamboo"]


## Shows a layout (as made by Theatre.generate_map), drawn for its theatre.
func show_layout(layout: Dictionary, theatre_id := "") -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture = ImageTexture.create_from_image(render(layout, theatre_id))


## The layout as an image, PIXELS per tile.
static func render(layout: Dictionary, theatre_id := "", team_colors := [Color("6fa8dc"), Color("e06666")]) -> Image:
	var map: TacticalMap = layout["map"]
	var k := PIXELS
	var image := Image.create(map.width * k, map.height * k, false, Image.FORMAT_RGBA8)
	var ground: Dictionary = GROUND.duplicate()
	ground.merge(THEATRE_GROUND.get(theatre_id, {}), true)
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var color: Color = ground[map.get_terrain(p)]
			# A faint checker so the grid reads.
			if (x + y) % 2 == 0:
				color = color.darkened(0.04)
			image.fill_rect(Rect2i(x * k, y * k, k, k), color)
			if map.get_object(p) != Cover.NONE:
				var kind := map.get_object_kind(p)
				var mark := CLUTTER
				if TREE_KINDS.has(kind):
					mark = TREE
				elif kind == "rock" or kind == "hesco":
					mark = ROCK
				elif TacticalMap.EXPLOSIVE_KINDS.has(kind):
					mark = BURNS
				image.fill_rect(Rect2i(x * k + 1, y * k + 1, k - 2, k - 2) if mark != TREE else Rect2i(x * k, y * k, k, k), mark)
	for key: Vector3i in map.get_edges():
		var pair := TacticalMap.edge_tiles(key)
		var edge_kind := map.edge_kind(key)
		var color := WALL
		if edge_kind == "hedge":
			color = HEDGE
		elif edge_kind == "stone" or edge_kind == "fence" or edge_kind.ends_with("window"):
			color = LOW_WALL
		elif edge_kind == "dyke":
			color = DYKE
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		if a.x != b.x:
			image.fill_rect(Rect2i(maxi(a.x, b.x) * k - 1, a.y * k, 2, k), color)
		else:
			image.fill_rect(Rect2i(a.x * k, maxi(a.y, b.y) * k - 1, k, 2), color)
	for objective: Dictionary in layout.get("objectives", []):
		_ring(image, Vector2(objective["center"]) * k, float(objective["radius"]) * k, OBJECTIVE)
	var spawns: Array = layout.get("spawns", [[], []])
	for team in spawns.size():
		for p: Vector2i in spawns[team]:
			image.fill_rect(Rect2i(p.x * k, p.y * k, k, k), team_colors[team])
	return image


static func _ring(image: Image, center: Vector2, radius: float, color: Color) -> void:
	for step in 96:
		var angle := TAU * step / 96.0
		for t: float in [radius - 0.5, radius + 0.5]:
			var q := center + Vector2(cos(angle), sin(angle)) * t
			var px := Vector2i(q)
			if px.x >= 0 and px.y >= 0 and px.x < image.get_width() and px.y < image.get_height():
				image.set_pixelv(px, color)
