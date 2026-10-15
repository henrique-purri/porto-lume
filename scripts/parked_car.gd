extends Node2D
## Arte compartilhada pelo carro controlável e pelo veículo estacionado.

@export var body_color := Color("ee876e")


func _draw() -> void:
	draw_style_box(_box(Color(0.05, 0.1, 0.12, 0.25), 7), Rect2(-19, -35, 43, 82))
	for wheel_y in [-23, 19]:
		draw_rect(Rect2(-22, wheel_y, 6, 14), Color("172d32"))
		draw_rect(Rect2(16, wheel_y, 6, 14), Color("172d32"))
	draw_style_box(_box(Color("263d41"), 8), Rect2(-19, -40, 38, 80))
	draw_style_box(_box(body_color, 7), Rect2(-17, -38, 34, 76))
	draw_rect(Rect2(-13, -19, 26, 14), Color("32535e"))
	draw_rect(Rect2(-12, 15, 24, 10), Color("32535e"))
	draw_rect(Rect2(-12, -2, 24, 14), body_color.lightened(0.12))
	draw_line(Vector2(-12, -31), Vector2(12, -31), body_color.lightened(0.3), 2)
	for light_x in [-13, 8]:
		draw_rect(Rect2(light_x, -36, 5, 4), Color("f3e5b8"))
		draw_rect(Rect2(light_x, 33, 5, 4), Color("a64f48"))
	draw_rect(Rect2(-23, -8, 5, 7), body_color)
	draw_rect(Rect2(18, -8, 5, 7), body_color)


func _box(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style
