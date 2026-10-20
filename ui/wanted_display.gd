extends Control
## Three geometric stars keep the status readable without a symbol font.

const GOLD := Color("efc875")
const INK := Color("263d41")
const STATUS_COLORS: Dictionary = {
	&"free": Color("b5d0ac"),
	&"hidden": Color("efc875"),
	&"pursued": Color("f39a87"),
}

var wanted_level: int = 0
var pursuit_state: StringName = &"free"
var heat: float = 0.0

@onready var status_label: Label = $StatusLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	_update_label()


func set_status(level: int, state: StringName, heat_value: float = 0.0) -> void:
	var next_level := clampi(level, 0, 3)
	var next_state: StringName = state if STATUS_COLORS.has(state) else &"hidden"
	if next_level == 0:
		next_state = &"free"
	heat = maxf(heat_value, 0.0)
	if wanted_level == next_level and pursuit_state == next_state:
		return
	wanted_level = next_level
	pursuit_state = next_state
	if is_node_ready():
		_update_label()
	queue_redraw()


func get_status_text() -> String:
	match pursuit_state:
		&"pursued":
			return "EM PERSEGUIÇÃO"
		&"hidden":
			return "ESCONDIDO · PROCURADO"
	return "LIVRE"


func _update_label() -> void:
	status_label.text = get_status_text()
	status_label.add_theme_color_override("font_color", STATUS_COLORS[pursuit_state])


func _draw() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.08, 0.15, 0.17, 0.90)
	panel.border_color = Color(0.75, 0.81, 0.75, 0.34)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	draw_style_box(panel, Rect2(Vector2.ZERO, size))
	for index in range(3):
		var center := Vector2(size.x * 0.5 + float(index - 1) * 45.0, 24.0)
		var points := PackedVector2Array()
		for point in range(10):
			var angle := -PI * 0.5 + float(point) * PI / 5.0
			var radius: float = 15.5 if point % 2 == 0 else 7.0
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(points, GOLD if index < wanted_level else INK)
		points.append(points[0])
		draw_polyline(points, GOLD if index < wanted_level else Color("99aaa4"), 1.5, true)
