extends StaticBody2D
## Bloco reutilizável: dimensões da arte e da colisão vêm do mesmo footprint.

@export var footprint := Vector2(220, 260)
@export var roof_color := Color("63817c")
@export var accent_color := Color("e8ba83")
@export var building_name := "ATELIÊ"
@export_range(0, 2) var roof_style: int = 0


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = footprint
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = footprint / 2.0
	add_child(collider)
	queue_redraw()


func _draw() -> void:
	var area := Rect2(Vector2.ZERO, footprint)
	draw_rect(Rect2(Vector2(9, 12), footprint + Vector2(3, 2)), Color(0.06, 0.13, 0.14, 0.23))
	draw_rect(area, Color("354e50"))
	draw_rect(area.grow(-5), roof_color)
	draw_rect(area.grow(-13), roof_color.darkened(0.1), false, 2.0)
	# Faixa da fachada/entrada, sem perspectiva ou texturas.
	draw_rect(Rect2(6, footprint.y - 13, footprint.x - 12, 7), accent_color)
	var door_x := footprint.x * 0.5 - 13.0
	draw_rect(Rect2(door_x, footprint.y - 7, 26, 8), Color("304c50"))
	draw_rect(Rect2(door_x - 5, footprint.y + 1, 36, 5), Color("b6bdab"))
	if roof_style == 0:
		_draw_vent(Vector2(28, 28), Vector2(42, 33))
		_draw_vent(Vector2(82, 28), Vector2(42, 33))
		draw_rect(Rect2(28, footprint.y - 68, footprint.x - 56, 15), roof_color.lightened(0.1))
	elif roof_style == 1:
		for row in range(2):
			for column in range(3):
				var origin := Vector2(27 + column * 41, 30 + row * 30)
				draw_rect(Rect2(origin + Vector2(3, 3), Vector2(34, 22)), roof_color.darkened(0.23))
				draw_rect(Rect2(origin, Vector2(34, 22)), Color("365b65"))
				draw_line(origin + Vector2(17, 2), origin + Vector2(17, 20), Color("739b9d"), 1)
	else:
		_draw_vent(Vector2(footprint.x - 72, 30), Vector2(42, 38))
		for y in range(30, int(footprint.y) - 60, 28):
			draw_line(Vector2(24, y), Vector2(footprint.x - 90, y), roof_color.lightened(0.08), 3)
	# Identificação só visual; não representa missão ou interação.
	var font: Font = ThemeDB.fallback_font
	var font_size := 13
	var label_width := font.get_string_size(building_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var label_pos := Vector2((footprint.x - label_width) / 2.0, footprint.y - 29)
	draw_string(font, label_pos, building_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("e5e3ce"))


func _draw_vent(origin: Vector2, vent_size: Vector2) -> void:
	draw_rect(Rect2(origin + Vector2(4, 5), vent_size), Color(0.1, 0.2, 0.2, 0.2))
	draw_rect(Rect2(origin, vent_size), Color("a3b0a3"))
	for offset in range(7, int(vent_size.x) - 3, 6):
		draw_line(origin + Vector2(offset, 6), origin + Vector2(offset, vent_size.y - 6), Color("728d85"), 2)
