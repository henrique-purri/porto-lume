extends CharacterBody2D
## Walking controller shared by keyboard and touchscreen input.
## The joystick only needs to provide get_direction() -> Vector2.

@export_range(50.0, 500.0, 1.0) var move_speed: float = 205.0
@export var joystick: Node
@export_range(0.0, 0.9, 0.01) var joystick_deadzone: float = 0.14

var _facing: Vector2 = Vector2.DOWN
var _walking: bool = false
var _walk_phase: float = 0.0
var _has_focus: bool = true


func _physics_process(delta: float) -> void:
	var direction: Vector2 = _get_movement_direction() if _has_focus else Vector2.ZERO
	var previous_facing: Vector2 = _facing
	var was_walking: bool = _walking
	velocity = direction * move_speed
	move_and_slide()
	_walking = get_real_velocity().length_squared() > 1.0
	if direction.length_squared() > 0.0:
		_facing = direction
	if _walking:
		_walk_phase = fmod(_walk_phase + delta * 15.0, TAU)
	else:
		_walk_phase = 0.0
	if _walking or was_walking or not previous_facing.is_equal_approx(_facing):
		queue_redraw()


func _get_movement_direction() -> Vector2:
	var keyboard: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	if keyboard.length_squared() > 0.0:
		return keyboard.normalized()
	if not is_instance_valid(joystick) or not joystick.has_method("get_direction"):
		return Vector2.ZERO
	var touch_direction: Vector2 = joystick.call("get_direction")
	if touch_direction.length_squared() <= joystick_deadzone * joystick_deadzone:
		return Vector2.ZERO
	# Eight fixed headings keep diagonal walking as fast as cardinal walking.
	var snapped_angle: float = roundf(touch_direction.angle() / (PI / 4.0)) * (PI / 4.0)
	return Vector2.from_angle(snapped_angle)


func reset_motion() -> void:
	velocity = Vector2.ZERO
	_walking = false
	_walk_phase = 0.0
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_has_focus = false
		reset_motion()
		for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
			Input.action_release(action)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_has_focus = true


func _draw() -> void:
	# All artwork is generated from simple shapes and uses no texture resources.
	# Rotating only the drawing keeps the collision shape and camera upright.
	draw_set_transform(Vector2(1.0, 6.0), 0.0, Vector2(1.0, 0.52))
	draw_circle(Vector2.ZERO, 16.0, Color(0.035, 0.065, 0.09, 0.24))
	draw_set_transform(Vector2.ZERO, _facing.angle() + PI / 2.0)
	var stride: float = sin(_walk_phase) * 2.8 if _walking else 0.0
	var ink: Color = Color("233c48")
	var trousers: Color = Color("304c5a")
	var coral: Color = Color("ec795f")
	var skin: Color = Color("efb382")
	# Dark shoes and alternating legs communicate walking at phone scale.
	draw_rect(Rect2(-8.0, 9.0 + stride, 6.0, 7.0), ink)
	draw_rect(Rect2(2.0, 9.0 - stride, 6.0, 7.0), ink)
	draw_line(Vector2(-4.5, 3.0), Vector2(-5.0, 10.0 + stride), trousers, 7.0, true)
	draw_line(Vector2(4.5, 3.0), Vector2(5.0, 10.0 - stride), trousers, 7.0, true)
	# A coral jacket is the prototype's identifying silhouette.
	var jacket: PackedVector2Array = PackedVector2Array([
		Vector2(-10.0, -6.0), Vector2(10.0, -6.0),
		Vector2(8.0, 7.0), Vector2(-8.0, 7.0)
	])
	draw_colored_polygon(jacket, ink)
	draw_rect(Rect2(-7.5, -5.0, 15.0, 10.0), coral)
	draw_line(Vector2(-10.0, -3.0), Vector2(-11.0, 4.0 - stride), coral, 5.5, true)
	draw_line(Vector2(10.0, -3.0), Vector2(11.0, 4.0 + stride), coral, 5.5, true)
	draw_circle(Vector2(-11.0, 5.0 - stride), 2.7, skin)
	draw_circle(Vector2(11.0, 5.0 + stride), 2.7, skin)
	draw_line(Vector2(0.0, -2.0), Vector2(0.0, 5.0), Color("b4544d"), 1.4, true)
	# Head, hair and a small front highlight show the current facing direction.
	draw_circle(Vector2(0.0, -9.0), 7.8, ink)
	draw_circle(Vector2(0.0, -9.5), 6.7, skin)
	draw_arc(Vector2(0.0, -9.0), 5.3, 0.0, PI, 12, Color("493e3d"), 4.8, true)
	draw_line(Vector2(-3.0, -14.0), Vector2(2.0, -14.0), Color("ffd9a7"), 1.7, true)
	draw_set_transform(Vector2.ZERO)
