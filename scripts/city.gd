extends Node2D
## Cidade estática 2400 × 1800. Só o jogador e o HUD processam a cada frame.

const WORLD_SIZE := Vector2(2400, 1800)
const BUILDING_SCENE: PackedScene = preload("res://world/building.tscn")
const ROAD_X: Array[int] = [200, 900, 1600, 2300]
const ROAD_Y: Array[int] = [180, 900, 1620]
const ASPHALT := Color("263d41")
const SIDEWALK := Color("cbcdb9")
const CURB := Color("e5e3ce")
const YARD := Color("a4b39a")
const MARKING := Color("afbbac")


func _ready() -> void:
	_create_buildings()
	_create_boundary()
	queue_redraw()


func _create_buildings() -> void:
	var colors: Array[Color] = [Color("678780"), Color("75898a"), Color("b18c70"), Color("527a78")]
	var names: Array[String] = ["ATELIÊ", "MERCADO", "OFICINA", "ARMAZÉM", "GALERIA", "ESTÚDIO"]
	for row in range(2):
		for column in range(3):
			var origin := Vector2(280 + column * 700, 260 + row * 720)
			var index := row * 3 + column
			_add_building(origin + Vector2(36, 40), Vector2(208, 220), colors[index % 4], names[index], index % 3)
			_add_building(origin + Vector2(284, 40), Vector2(220, 366), colors[(index + 1) % 4], "PORTO LUME", (index + 1) % 3)
			_add_building(origin + Vector2(36, 326), Vector2(208, 194), colors[(index + 2) % 4], "AURORA", (index + 2) % 3)


func _add_building(origin: Vector2, size: Vector2, tint: Color, title: String, style: int) -> void:
	var building := BUILDING_SCENE.instantiate() as StaticBody2D
	building.position = origin
	building.set("footprint", size)
	building.set("roof_color", tint)
	building.set("building_name", title)
	building.set("roof_style", style)
	$Buildings.add_child(building)


func _create_boundary() -> void:
	var boundary := StaticBody2D.new()
	boundary.name = "WorldBoundary"
	boundary.collision_layer = 1
	boundary.collision_mask = 2
	add_child(boundary)
	var walls: Array[Rect2] = [
		Rect2(-32, -32, 2464, 32), Rect2(-32, 1800, 2464, 32),
		Rect2(-32, 0, 32, 1800), Rect2(2400, 0, 32, 1800),
	]
	for wall in walls:
		var shape := RectangleShape2D.new()
		shape.size = wall.size
		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.position = wall.get_center()
		boundary.add_child(collider)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), ASPHALT)
	_draw_lane_markings()
	for row in range(2):
		for column in range(3):
			_draw_block(Vector2(280 + column * 700, 260 + row * 720), row + column)
	for x in ROAD_X:
		for y in ROAD_Y:
			_draw_crossing(Vector2(x, y))
	_draw_parking(Vector2(960, 1020), false)
	_draw_parking(Vector2(1020, 840), true)
	_draw_parking(Vector2(440, 840), true)
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(1045, 952), "R U A   D A   B R I S A", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("718d88"))
	draw_string(font, Vector2(340, 1655), "A V E N I D A   A U R O R A", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("718d88"))


func _draw_lane_markings() -> void:
	for x in ROAD_X:
		for y in range(20, 1800, 62):
			if _away_from_intersections(y, ROAD_Y, 123):
				draw_rect(Rect2(x - 1, y, 2, 27), MARKING.darkened(0.12))
	for y in ROAD_Y:
		for x in range(20, 2400, 62):
			if _away_from_intersections(x, ROAD_X, 123):
				draw_rect(Rect2(x, y - 1, 27, 2), MARKING.darkened(0.12))


func _away_from_intersections(value: int, centers: Array[int], distance: int) -> bool:
	for center in centers:
		if abs(value - center) < distance:
			return false
	return true


func _draw_block(origin: Vector2, variation: int) -> void:
	var block := Rect2(origin, Vector2(540, 560))
	draw_rect(Rect2(origin + Vector2(6, 8), block.size), Color(0.06, 0.13, 0.14, 0.22))
	draw_rect(block, CURB)
	draw_rect(block.grow(-5), SIDEWALK)
	draw_rect(block.grow(-27), YARD)
	# Juntas da calçada e pequenos canteiros são apenas desenho estático.
	for x in range(38, 530, 40):
		draw_line(origin + Vector2(x, 5), origin + Vector2(x, 25), Color("b5bba9"), 1)
		draw_line(origin + Vector2(x, 535), origin + Vector2(x, 555), Color("b5bba9"), 1)
	for y in range(38, 550, 40):
		draw_line(origin + Vector2(5, y), origin + Vector2(25, y), Color("b5bba9"), 1)
		draw_line(origin + Vector2(515, y), origin + Vector2(535, y), Color("b5bba9"), 1)
	for offset in [Vector2(263, 92), Vector2(263, 278), Vector2(385, 477), Vector2(472, 477)]:
		_draw_tree(origin + offset, variation)
	# Banco de praça no pequeno pátio; placeholder sem gameplay.
	draw_rect(Rect2(origin + Vector2(297, 447), Vector2(48, 14)), Color("708778"))
	draw_rect(Rect2(origin + Vector2(296, 444), Vector2(48, 10)), Color("d6b389"))
	for bench_x in [302, 334]:
		draw_rect(Rect2(origin + Vector2(bench_x, 454), Vector2(4, 6)), Color("536d66"))


func _draw_tree(center: Vector2, variation: int) -> void:
	draw_rect(Rect2(center - Vector2(20, 20), Vector2(40, 40)), Color("8b9e86"))
	draw_circle(center + Vector2(5, 7), 24, Color(0.1, 0.2, 0.17, 0.2))
	draw_circle(center, 23, Color("3c6960") if variation % 2 == 0 else Color("527a63"))
	draw_circle(center + Vector2(-7, -7), 13, Color("638c70"))
	draw_circle(center + Vector2(9, 2), 10, Color("497861"))


func _draw_crossing(center: Vector2) -> void:
	for offset in range(-67, 68, 19):
		for side in [-1, 1]:
			draw_rect(Rect2(center + Vector2(offset, side * 108 - 16), Vector2(10, 32)), CURB.darkened(0.08))
			draw_rect(Rect2(center + Vector2(side * 108 - 16, offset), Vector2(32, 10)), CURB.darkened(0.08))
	for side in [-1, 1]:
		draw_line(center + Vector2(-74, side * 83), center + Vector2(-8, side * 83), MARKING, 2)
		draw_line(center + Vector2(side * 83, 8), center + Vector2(side * 83, 74), MARKING, 2)


func _draw_parking(origin: Vector2, horizontal: bool) -> void:
	for index in range(4):
		var offset := Vector2(index * 66, 0) if horizontal else Vector2(0, index * 105)
		var slot_size := Vector2(60, 38) if horizontal else Vector2(38, 96)
		draw_rect(Rect2(origin + offset - slot_size / 2.0, slot_size), Color("607c79"), false, 1.5)
