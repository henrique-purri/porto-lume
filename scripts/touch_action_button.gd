extends Control
## A touch belongs to one button until release or cancellation. Sliding off a
## pedal releases it; sliding back in never accelerates without a fresh press.

signal activated

@export var caption: String = "ENTRAR":
	set(value):
		if caption == value:
			return
		caption = value
		queue_redraw()
@export var primary: bool = false
@export_range(12, 32, 1) var font_size: int = 18

const NO_POINTER: int = -1
const MOUSE_POINTER: int = -2
const CREAM := Color("e5e3ce")
const CORAL := Color("ee876e")
const ASPHALT := Color("263d41")

var _active_pointer: int = NO_POINTER
var _held: bool = false


func _ready() -> void:
	resized.connect(reset)
	visibility_changed.connect(reset)
	queue_redraw()


func is_held() -> bool:
	return _held and is_visible_in_tree()


func reset() -> void:
	_active_pointer = NO_POINTER
	_held = false
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT \
	or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
	or what == NOTIFICATION_APPLICATION_PAUSED \
	or what == NOTIFICATION_PAUSED:
		reset()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		reset()
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index == _active_pointer:
			if touch.canceled:
				reset()
			elif not touch.pressed:
				_release(_contains(touch.position))
			get_viewport().set_input_as_handled()
		elif touch.pressed and not touch.canceled and _active_pointer == NO_POINTER:
			if _contains(touch.position):
				_capture(touch.index)
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _active_pointer:
			# Keep the pointer reserved after sliding out, so another touch does
			# not turn this gesture into a fresh pedal press.
			if not _contains(drag.position):
				_held = false
				queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if not button.pressed and _active_pointer == MOUSE_POINTER:
			_release(_contains(button.position))
			get_viewport().set_input_as_handled()
		elif button.pressed and _active_pointer == NO_POINTER and _contains(button.position):
			_capture(MOUSE_POINTER)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _active_pointer == MOUSE_POINTER:
		var motion := event as InputEventMouseMotion
		if not _contains(motion.position):
			_held = false
			queue_redraw()
		get_viewport().set_input_as_handled()


func _contains(viewport_position: Vector2) -> bool:
	var local_position := get_global_transform_with_canvas().affine_inverse() * viewport_position
	return Rect2(Vector2.ZERO, size).has_point(local_position)


func _capture(pointer: int) -> void:
	_active_pointer = pointer
	_held = true
	queue_redraw()


func _release(inside: bool) -> void:
	var should_activate := _held and inside
	reset()
	if should_activate:
		activated.emit()


func _draw() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = CORAL if _held else Color(ASPHALT, 0.85)
	style.border_color = CORAL if primary or _held else Color(CREAM, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0.03, 0.09, 0.10, 0.22)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 3)
	draw_style_box(style, Rect2(Vector2.ZERO, size))
	var font := ThemeDB.fallback_font
	var lines := caption.split("\n")
	var line_height := float(font_size + 5)
	var top := (size.y - line_height * float(lines.size())) * 0.5
	var text_color := ASPHALT if _held else CREAM
	for index in lines.size():
		var width := font.get_string_size(lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := top + float(index) * line_height + font.get_ascent(font_size)
		draw_string(font, Vector2((size.x - width) * 0.5, baseline), lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
