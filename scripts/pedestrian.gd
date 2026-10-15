extends CharacterBody2D
## Lightweight pavement walker: one shared graph, staggered thinking, no damage.

const SHIRT_COLORS: Array[Color] = [Color("e2bd64"), Color("69a9c2"), Color("88a86c"), Color("af8bc1")]
const SKIN_COLORS: Array[Color] = [Color("e3ab7e"), Color("ac7756"), Color("805943")]
const HIT_COOLDOWN: float = 1.6
const THREAT_DISTANCE: float = 150.0

var walk_speed: float = 56.0
var appearance_variant: int = 0

var _paths: RefCounted
var _rng := RandomNumberGenerator.new()
var _vehicle: CharacterBody2D
var _route := PackedVector2Array()
var _route_index: int = 0
var _state: StringName = &"paused"
var _facing := Vector2.DOWN
var _walking: bool = false
var _walk_phase: float = 0.0
var _skin_variant: int = 0
var _think_remaining: float = 0.0
var _pause_remaining: float = 0.0
var _flee_remaining: float = 0.0
var _flee_replan_remaining: float = 0.0
var _fallen_remaining: float = 0.0
var _hit_cooldown: float = 0.0
var _blocked_time: float = 0.0
var _simulation_enabled: bool = true
var _last_hit_origin := Vector2.ZERO
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func configure(path_provider: RefCounted, spawn_position: Vector2, seed_value: int, variant: int) -> void:
	_paths = path_provider
	global_position = spawn_position
	_rng.seed = seed_value
	appearance_variant = posmod(variant, SHIRT_COLORS.size())
	walk_speed = _rng.randf_range(45.0, 72.0)
	_skin_variant = _rng.randi_range(0, SKIN_COLORS.size() - 1)
	_pause_remaining = _rng.randf_range(0.05, 0.5)
	_think_remaining = _rng.randf_range(0.0, 0.28)
	queue_redraw()


func set_vehicle_threat(vehicle: CharacterBody2D) -> void:
	_vehicle = vehicle


func set_simulation_enabled(enabled: bool) -> void:
	_simulation_enabled = enabled
	set_physics_process(enabled)
	visible = enabled
	collision_layer = 8 if enabled else 0
	if not enabled:
		velocity = Vector2.ZERO
		_walking = false
	else:
		_think_remaining = 0.0
		queue_redraw()


func get_state_name() -> StringName:
	return _state


func receive_vehicle_hit(vehicle_velocity: Vector2, vehicle_position: Vector2) -> void:
	if not _simulation_enabled or _hit_cooldown > 0.0 or vehicle_velocity.length_squared() < 36.0:
		return
	_hit_cooldown = HIT_COOLDOWN
	_last_hit_origin = vehicle_position
	_fallen_remaining = 1.0
	_route.clear()
	_route_index = 0
	_flee_remaining = 0.0
	_pause_remaining = 0.0
	var away: Vector2 = vehicle_position.direction_to(global_position)
	var direction: Vector2 = (vehicle_velocity.normalized() * 0.75 + away * 0.25).normalized()
	velocity = direction * clampf(vehicle_velocity.length() * 0.7 + 55.0, 85.0, 250.0)
	collision_mask = 3
	_set_state(&"fallen")


func _physics_process(delta: float) -> void:
	_hit_cooldown = maxf(_hit_cooldown - delta, 0.0)
	_flee_replan_remaining = maxf(_flee_replan_remaining - delta, 0.0)
	if _state == &"fallen":
		_update_fallen(delta)
		_update_art(delta)
		return
	_pause_remaining = maxf(_pause_remaining - delta, 0.0)
	_flee_remaining = maxf(_flee_remaining - delta, 0.0)
	_think_remaining -= delta
	if _think_remaining <= 0.0:
		_think_remaining = _rng.randf_range(0.18, 0.28)
		_think()
	if _flee_remaining <= 0.0 and _state == &"fleeing":
		_set_state(&"walking")
	if _pause_remaining > 0.0 or _route_index >= _route.size():
		velocity = Vector2.ZERO
		if _state != &"fleeing":
			_set_state(&"paused")
	else:
		_follow_route(delta)
	_update_art(delta)


func _think() -> void:
	if _is_vehicle_threatening():
		_flee_remaining = 1.2
		_pause_remaining = 0.0
		if _state != &"fleeing" or _flee_replan_remaining <= 0.0:
			_request_route(true)
			_flee_replan_remaining = 0.65
		_set_state(&"fleeing")
	elif _pause_remaining <= 0.0 and _route_index >= _route.size():
		_request_route(false)
		if not _route.is_empty():
			_set_state(&"walking")


func _is_vehicle_threatening() -> bool:
	return is_instance_valid(_vehicle) and bool(_vehicle.get("driven")) \
		and absf(float(_vehicle.get("speed"))) > 12.0 \
		and global_position.distance_squared_to(_vehicle.global_position) < THREAT_DISTANCE * THREAT_DISTANCE


func _request_route(flee: bool) -> void:
	if not is_instance_valid(_paths):
		return
	if flee and is_instance_valid(_vehicle) and _paths.has_method("make_flee_path"):
		_route = _paths.call("make_flee_path", global_position, _vehicle.global_position, _rng)
	else:
		_route = _paths.call("make_path", global_position, _rng)
	_route_index = 0
	_blocked_time = 0.0


func _follow_route(delta: float) -> void:
	while _route_index < _route.size() and global_position.distance_squared_to(_route[_route_index]) < 36.0:
		_route_index += 1
	if _route_index >= _route.size():
		velocity = Vector2.ZERO
		_pause_remaining = _rng.randf_range(0.25, 1.1) if _state != &"fleeing" else 0.0
		return
	var direction: Vector2 = global_position.direction_to(_route[_route_index])
	var speed_multiplier: float = 1.85 if _state == &"fleeing" else 1.0
	velocity = direction * walk_speed * speed_multiplier
	var previous_position: Vector2 = global_position
	move_and_slide()
	var traveled: float = previous_position.distance_to(global_position)
	if traveled < walk_speed * delta * 0.2:
		_blocked_time += delta
	else:
		_blocked_time = 0.0
	if _blocked_time > 0.28:
		_route.clear()
		_route_index = 0
		_pause_remaining = _rng.randf_range(0.2, 0.55)
		velocity = Vector2.ZERO
		_blocked_time = 0.0
		_set_state(&"paused")


func _update_fallen(delta: float) -> void:
	_fallen_remaining -= delta
	move_and_slide()
	velocity = velocity.move_toward(Vector2.ZERO, 245.0 * delta)
	if _fallen_remaining > 0.0:
		return
	# Keep the same small collision circle while lying down. Wait/crawl out if
	# a car stopped over the pedestrian, then restore normal vehicle collisions.
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _collision_shape.shape
	query.transform = global_transform * _collision_shape.transform
	query.collision_mask = 7
	query.exclude = [get_rid()]
	query.margin = 0.0
	var overlaps: Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query, 1)
	if not overlaps.is_empty():
		var obstacle: Node2D = overlaps[0].get("collider") as Node2D
		var origin: Vector2 = obstacle.global_position if is_instance_valid(obstacle) else _last_hit_origin
		var away: Vector2 = origin.direction_to(global_position)
		if away.is_zero_approx():
			away = Vector2.RIGHT
		velocity = away * 65.0
		_fallen_remaining = 0.1
		return
	collision_mask = 7
	velocity = Vector2.ZERO
	_pause_remaining = _rng.randf_range(0.15, 0.4)
	_think_remaining = 0.0
	_set_state(&"paused")


func _set_state(value: StringName) -> void:
	if _state != value:
		_state = value
		queue_redraw()


func _update_art(delta: float) -> void:
	var was_walking: bool = _walking
	var previous_facing: Vector2 = _facing
	_walking = _state != &"fallen" and velocity.length_squared() > 1.0
	if _walking:
		_facing = velocity.normalized()
		_walk_phase = fmod(_walk_phase + delta * (17.0 if _state == &"fleeing" else 10.0), TAU)
	else:
		_walk_phase = 0.0
	if _walking or was_walking or not previous_facing.is_equal_approx(_facing):
		queue_redraw()


func _draw() -> void:
	var ink := Color("263e48")
	var shirt: Color = SHIRT_COLORS[appearance_variant]
	var skin: Color = SKIN_COLORS[_skin_variant]
	draw_set_transform(Vector2(1, 5), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 12.5, Color(0.035, 0.065, 0.09, 0.20))
	var angle: float = _facing.angle() + PI / 2.0
	if _state == &"fallen":
		draw_set_transform(Vector2.ZERO, angle + PI / 2.0, Vector2(1.0, 0.72))
	else:
		draw_set_transform(Vector2.ZERO, angle)
	var stride: float = sin(_walk_phase) * 2.4 if _walking else 0.0
	draw_line(Vector2(-3.8, 3), Vector2(-4.4, 11 + stride), ink, 5.0, true)
	draw_line(Vector2(3.8, 3), Vector2(4.4, 11 - stride), ink, 5.0, true)
	draw_rect(Rect2(-7.5, -5.5, 15, 13), ink)
	draw_rect(Rect2(-6, -4.5, 12, 10.5), shirt)
	draw_line(Vector2(-8, -2), Vector2(-8.8, 4 - stride), shirt, 4.0, true)
	draw_line(Vector2(8, -2), Vector2(8.8, 4 + stride), shirt, 4.0, true)
	draw_circle(Vector2(-8.8, 4.8 - stride), 2.0, skin)
	draw_circle(Vector2(8.8, 4.8 + stride), 2.0, skin)
	if appearance_variant % 2 == 0:
		# Backpack and cap distinguish civilians from the coral-jacketed player.
		draw_rect(Rect2(-4.0, 0, 8, 6), shirt.darkened(0.35))
		draw_line(Vector2(-4, -2), Vector2(-4, 5), ink, 1.0)
		draw_line(Vector2(4, -2), Vector2(4, 5), ink, 1.0)
	draw_circle(Vector2(0, -8.5), 6.3, ink)
	draw_circle(Vector2(0, -8.8), 5.3, skin)
	if appearance_variant % 2 == 1:
		draw_arc(Vector2(0, -8.5), 4.6, 0.0, PI, 10, shirt.darkened(0.12), 4.0, true)
		draw_line(Vector2(-4, -13), Vector2(4, -13), shirt.lightened(0.2), 2.0, true)
	else:
		draw_arc(Vector2(0, -8.5), 4.4, 0.0, PI, 10, Color("524638"), 3.5, true)
	if _state == &"fallen":
		draw_arc(Vector2(0, -16), 5.0, 0.3, 2.8, 8, Color("e5e3ce"), 1.2, true)
	draw_set_transform(Vector2.ZERO)
