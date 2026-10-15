extends Control
## Fixed, single-finger joystick. Input positions arrive in viewport coordinates;
## the inverse canvas transform keeps dragging correct with viewport stretching.

@export_range(0.0, 0.8, 0.01) var deadzone: float = 0.12
@export var activation_radius: float = 92.0
@export var travel_radius: float = 50.0

const NO_POINTER: int = -1
const MOUSE_POINTER: int = -2
const CREAM := Color("e5e3ce")
const TEAL := Color("3e6967")
const CORAL := Color("ee876e")
const ASPHALT := Color("263d41")

var _active_pointer: int = NO_POINTER
var _direction: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	resized.connect(reset)
	queue_redraw()


func get_direction() -> Vector2:
	return _direction


func reset() -> void:
	_active_pointer = NO_POINTER
	_direction = Vector2.ZERO
	_knob_offset = Vector2.ZERO
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
		if touch.index == _active_pointer and (not touch.pressed or touch.canceled):
			reset()
			get_viewport().set_input_as_handled()
		elif touch.pressed and not touch.canceled and _active_pointer == NO_POINTER:
			var local_position := _viewport_to_local(touch.position)
			if local_position.distance_to(size * 0.5) <= activation_radius:
				_active_pointer = touch.index
				_update_direction(local_position)
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _active_pointer:
			_update_direction(_viewport_to_local(drag.position))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if not button.pressed and _active_pointer == MOUSE_POINTER:
			reset()
			get_viewport().set_input_as_handled()
		elif button.pressed and _active_pointer == NO_POINTER:
			var local_position := _viewport_to_local(button.position)
			if local_position.distance_to(size * 0.5) <= activation_radius:
				_active_pointer = MOUSE_POINTER
				_update_direction(local_position)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _active_pointer == MOUSE_POINTER:
		var motion := event as InputEventMouseMotion
		_update_direction(_viewport_to_local(motion.position))
		get_viewport().set_input_as_handled()


func _viewport_to_local(viewport_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_position


func _update_direction(local_position: Vector2) -> void:
	_knob_offset = (local_position - size * 0.5).limit_length(travel_radius)
	var raw_direction := _knob_offset / maxf(travel_radius, 1.0)
	var strength := raw_direction.length()
	if strength <= deadzone:
		_direction = Vector2.ZERO
	else:
		var adjusted_strength := (strength - deadzone) / (1.0 - deadzone)
		_direction = raw_direction.normalized() * adjusted_strength
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var engaged := _active_pointer != NO_POINTER
	draw_circle(center + Vector2(0, 4), 80.0, Color(0.03, 0.09, 0.10, 0.10))
	draw_circle(center, 79.0, Color(ASPHALT, 0.64))
	draw_arc(center, 79.0, 0.0, TAU, 64, Color(CREAM, 0.24), 1.5, true)
	draw_arc(center, 57.0, 0.0, TAU, 48, Color(CREAM, 0.08), 1.0, true)
	for axis in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		draw_line(center + axis * 67.0, center + axis * 72.0, Color(CREAM, 0.35), 2.0, true)
	if engaged:
		draw_line(center, center + _knob_offset, Color(CREAM, 0.16), 5.0, true)
	var knob_center := center + _knob_offset
	draw_circle(knob_center + Vector2(0, 3), 30.0, Color(0.03, 0.09, 0.10, 0.28))
	draw_circle(knob_center, 29.0, CORAL if engaged else CREAM)
	draw_arc(knob_center, 23.0, 0.0, TAU, 32, Color(ASPHALT, 0.13), 1.0, true)
	draw_circle(knob_center, 3.0, Color(ASPHALT, 0.55))
