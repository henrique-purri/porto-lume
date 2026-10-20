extends CharacterBody2D
## Arcade driving. The HUD supplies independent throttle and steering values.

const VEHICLE_CONTACTS: Script = preload("res://scripts/vehicle_contacts.gd")

@export var control_source: Node
@export_range(100.0, 600.0, 1.0) var maximum_forward_speed: float = 340.0
@export_range(40.0, 300.0, 1.0) var maximum_reverse_speed: float = 130.0
@export_range(100.0, 900.0, 1.0) var acceleration: float = 300.0
@export_range(200.0, 1500.0, 1.0) var braking: float = 650.0
@export_range(20.0, 300.0, 1.0) var coast_deceleration: float = 90.0
@export_range(0.5, 5.0, 0.1) var turn_rate: float = 2.4

var driven: bool = false
var speed: float = 0.0

var _steering: float = 0.0
var _has_focus: bool = true
var _vehicle_contacts: Dictionary = {}
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	set_physics_process(driven and _has_focus)


func set_driver_active(value: bool) -> void:
	driven = value
	if value:
		add_to_group("player_controlled_vehicle")
	else:
		remove_from_group("player_controlled_vehicle")
	_vehicle_contacts.clear()
	stop()
	set_physics_process(driven and _has_focus)


func stop() -> void:
	speed = 0.0
	velocity = Vector2.ZERO
	_steering = 0.0


func _physics_process(delta: float) -> void:
	if not driven or not _has_focus:
		stop()
		return
	var previous_transform: Transform2D = global_transform
	var throttle: float = Input.get_axis("move_down", "move_up")
	var steering_input: float = Input.get_axis("move_left", "move_right")
	if is_instance_valid(control_source):
		if control_source.has_method("get_drive_throttle"):
			throttle += float(control_source.call("get_drive_throttle"))
		if control_source.has_method("get_drive_steering"):
			steering_input += float(control_source.call("get_drive_steering"))
	throttle = clampf(throttle, -1.0, 1.0)
	steering_input = clampf(steering_input, -1.0, 1.0)
	_update_speed(throttle, delta)
	_steering = move_toward(_steering, steering_input, 7.0 * delta)
	if absf(speed) > 8.0:
		var speed_factor: float = minf(absf(speed) / 110.0, 1.0)
		var rotation_delta: float = _steering * turn_rate * speed_factor * signf(speed) * delta
		_try_rotate(rotation_delta)
	var forward: Vector2 = Vector2.UP.rotated(global_rotation)
	velocity = forward * speed
	var incoming_velocity := velocity
	move_and_slide()
	_report_vehicle_collisions(incoming_velocity)
	if get_slide_collision_count() > 0:
		# Keep only the speed that survived sliding, so a wall never stores thrust.
		var actual_speed: float = get_real_velocity().dot(forward)
		speed = clampf(actual_speed, 0.0, speed) if speed > 0.0 else clampf(actual_speed, speed, 0.0)
	_notify_pedestrian_contacts(previous_transform, delta)


func _notify_pedestrian_contacts(previous: Transform2D, delta: float) -> void:
	VEHICLE_CONTACTS.notify(self, _collision_shape, previous, delta)


func _report_vehicle_collisions(incoming_velocity: Vector2) -> void:
	var contacts: Dictionary = {}
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		var other := collision.get_collider() as CollisionObject2D
		if not is_instance_valid(other) or other.collision_layer & 4 == 0:
			continue
		var identifier: int = other.get_instance_id()
		contacts[identifier] = true
		# A police car hitting an idle player is not a crime by the player.
		# Sustained pushing also remains a single contact until they separate.
		var own_impact: float = -incoming_velocity.dot(collision.get_normal())
		var relative_impact: float = -(incoming_velocity - collision.get_collider_velocity()).dot(collision.get_normal())
		if not driven or _vehicle_contacts.has(identifier) or own_impact < 45.0 or relative_impact < 45.0:
			continue
		var crime_system := get_tree().get_first_node_in_group("crime_system")
		if is_instance_valid(crime_system):
			crime_system.call("register_crime", &"vehicle_collision", self, other)
	_vehicle_contacts = contacts


func _update_speed(throttle: float, delta: float) -> void:
	if absf(throttle) < 0.01:
		var drag: float = coast_deceleration + absf(speed) * 0.15
		speed = move_toward(speed, 0.0, drag * delta)
		return
	if speed * throttle < 0.0:
		# The opposite pedal first brakes to a complete stop, then selects reverse.
		speed = move_toward(speed, 0.0, braking * absf(throttle) * delta)
		return
	var maximum_speed: float = maximum_forward_speed if throttle > 0.0 else maximum_reverse_speed
	speed = move_toward(speed, maximum_speed * throttle, acceleration * absf(throttle) * delta)


func _try_rotate(rotation_delta: float) -> void:
	if is_zero_approx(rotation_delta):
		return
	# move_and_slide resolves translation only. Test the rotated capsule as well
	# so steering beside a building cannot sweep the car through its wall.
	var proposed_transform: Transform2D = global_transform.rotated_local(rotation_delta)
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = _collision_shape.shape
	query.transform = proposed_transform * _collision_shape.transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.margin = 0.02
	query.collide_with_bodies = true
	query.collide_with_areas = false
	if get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		global_transform = proposed_transform


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_has_focus = false
		stop()
		set_physics_process(false)
		for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
			Input.action_release(action)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_has_focus = true
		set_physics_process(driven)
