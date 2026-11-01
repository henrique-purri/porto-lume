extends "res://scripts/traffic_vehicle.gd"
## Patrol uses civilian lanes. Emergency driving uses the shared obstacle grid,
## real collisions and reported sightings, without lane/junction permissions.

const DETECTION_DISTANCE: float = 600.0
const VISION_HALF_ANGLE: float = PI / 3.0 # 120 degrees in front of the car.
const PURSUIT_SPEEDS: Array[float] = [125.0, 175.0, 205.0, 235.0]
const EMERGENCY_TURN_RATE: float = 3.2

var police_state: StringName = &"patrol"
var pursuit_level: int = 0
var pursuit_slot: int = 0
var last_known_position := Vector2.ZERO
var intercept_position := Vector2.ZERO
var _observed_velocity := Vector2.ZERO
var _police_manager: Node
var _navigation: RefCounted
var _searching: bool = false
var _returning: bool = false
var _return_lane: Dictionary = {}
var _emergency_path := PackedVector2Array()
var _path_index: int = 0
var _repath_remaining: float = 0.0
var _steering_remaining: float = 0.0
var _avoidance := Vector2.ZERO
var _stuck_time: float = 0.0
var _reverse_remaining: float = 0.0


func configure(route_provider: RefCounted, spawn: Dictionary, seed_value: int, variant: int) -> void:
	super.configure(route_provider, spawn, seed_value, variant)
	_returning = false
	_emergency_path.clear()
	_repath_remaining = 0.0
	_stuck_time = 0.0
	_reverse_remaining = 0.0
	_visual.set("body_color", Color("e0e6dc"))
	_visual.queue_redraw()
	_update_police_profile()


func set_police_manager(manager: Node) -> void:
	_police_manager = manager
	_navigation = manager.call("get_navigation") as RefCounted


func set_pursuit(target_position: Vector2, level: int, slot: int = 0, observed_velocity: Vector2 = Vector2.ZERO) -> void:
	if not target_position.is_finite():
		return
	if pursuit_level == 0 or last_known_position.distance_squared_to(target_position) > 80.0 * 80.0:
		_repath_remaining = 0.0
	last_known_position = target_position
	pursuit_level = clampi(level, 0, 3)
	pursuit_slot = maxi(slot, 0)
	_observed_velocity = observed_velocity.limit_length(340.0)
	if pursuit_level == 0:
		clear_pursuit()
		return
	# A pursuit must never keep a civilian intersection lease or queue slot.
	release_intersection()
	_returning = false
	intercept_position = _get_intercept_position()
	_update_police_profile()
	police_state = &"searching" if _searching else &"pursuing"


func set_searching(searching: bool) -> void:
	if searching != _searching:
		_repath_remaining = 0.0
	_searching = searching
	if pursuit_level > 0:
		police_state = &"searching" if searching else &"pursuing"
		_visual.call("set_emergency_active", not searching)


func clear_pursuit() -> void:
	if pursuit_level == 0 and police_state == &"patrol":
		return
	pursuit_level = 0
	_searching = false
	police_state = &"patrol"
	_observed_velocity = Vector2.ZERO
	_update_police_profile()
	_begin_return_to_lane()


func get_police_state() -> StringName:
	return police_state


func release_intersection() -> void:
	super.release_intersection()
	# A waiting car also has a queue entry before it owns a reservation.
	if current_to >= 0 and is_instance_valid(_manager) and _manager.has_method("release_intersection"):
		_manager.call("release_intersection", self, current_to)


func _physics_process(delta: float) -> void:
	if pursuit_level == 0 and not _returning:
		super._physics_process(delta)
		return
	if not _configured or not _simulation_enabled or not is_instance_valid(_navigation) or not bool(_navigation.get("ready")):
		stop()
		return
	_drive_emergency(delta)


func _drive_emergency(delta: float) -> void:
	var previous := global_transform
	_repath_remaining -= delta
	_steering_remaining -= delta
	_reverse_remaining = maxf(_reverse_remaining - delta, 0.0)
	if _repath_remaining <= 0.0:
		_repath_remaining = _rng.randf_range(0.6, 0.85)
		var goal: Vector2 = _return_lane.get("position", global_position) if _returning else _get_intercept_position()
		intercept_position = goal
		_emergency_path = _navigation.call("find_path", global_position, goal)
		_path_index = 0
		# Only simplify across swept, building-free segments, never through a wall.
		for index in range(mini(_emergency_path.size(), 7) - 1, -1, -1):
			if bool(_navigation.call("can_drive_direct", global_position, _emergency_path[index])):
				_path_index = index
				break
	while _path_index < _emergency_path.size() - 1 and global_position.distance_to(_emergency_path[_path_index]) < 28.0:
		_path_index += 1
	if _emergency_path.is_empty():
		stop()
		return
	var goal_distance := global_position.distance_to(_emergency_path[_emergency_path.size() - 1])
	if _returning and goal_distance < 13.0:
		_resume_lane_patrol()
		return
	var offset := _emergency_path[_path_index] - global_position
	var desired_direction := offset.normalized()
	if _steering_remaining <= 0.0:
		_steering_remaining = _rng.randf_range(0.12, 0.18)
		_avoidance = _choose_emergency_direction(desired_direction)
	if not _avoidance.is_zero_approx():
		desired_direction = _avoidance
	var forward := Vector2.UP.rotated(global_rotation)
	var angle := forward.angle_to(desired_direction)
	if not desired_direction.is_zero_approx():
		_try_face(forward.rotated(clampf(angle, -EMERGENCY_TURN_RATE * delta, EMERGENCY_TURN_RATE * delta)))
	forward = Vector2.UP.rotated(global_rotation)
	var desired_speed := 110.0 if _returning else PURSUIT_SPEEDS[pursuit_level]
	if absf(angle) > 0.45:
		desired_speed = minf(desired_speed, 65.0)
	if absf(angle) > 1.4:
		desired_speed = 0.0 # Turn before moving away from the next waypoint.
	var stopping_radius := 0.0 if _returning else 58.0
	if _path_index == _emergency_path.size() - 1:
		desired_speed = minf(desired_speed, maxf(goal_distance - stopping_radius, 0.0) * 2.0)
	if _reverse_remaining > 0.0:
		desired_speed = -65.0
	speed = move_toward(speed, desired_speed, (acceleration if desired_speed > speed else SERVICE_BRAKING * 2.0) * delta)
	velocity = forward * speed
	var collision := move_and_collide(velocity * delta)
	if collision != null:
		stop()
	var moved := previous.origin.distance_to(global_position)
	_stuck_time = _stuck_time + delta if moved < 0.1 and desired_speed > 5.0 else 0.0
	if _stuck_time > 1.4:
		# A short, physically checked back-off lets a car retry a blocked turn.
		if _motion_clearance(-forward, 75.0) > 60.0:
			_reverse_remaining = 0.7
		_stuck_time = 0.0
		_repath_remaining = 0.0
	_state = &"waiting" if absf(speed) < 2.0 else &"driving"
	CONTACTS.notify(self, _collision_shape, previous, delta)


func _choose_emergency_direction(wish: Vector2) -> Vector2:
	# Civilian following/stop lines do not apply. A short fan tries to pass
	# stopped traffic on either side; actual swept-body collisions still win.
	if wish.is_zero_approx() or _motion_clearance(wish, 125.0) > 110.0:
		return wish
	var best := wish
	var best_score := -INF
	for turn: float in [0.0, -0.65, 0.65, -1.15, 1.15]:
		var direction := wish.rotated(turn)
		var clearance := _motion_clearance(direction, 125.0)
		var score := clearance - absf(turn) * 22.0
		if score > best_score:
			best_score = score
			best = direction
	return best


func _motion_clearance(direction: Vector2, distance: float) -> float:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _collision_shape.shape
	query.transform = Transform2D(direction.angle() + PI / 2.0, global_position) * _collision_shape.transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var space := get_world_2d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return 0.0
	query.motion = direction * distance
	var fractions := space.cast_motion(query)
	return fractions[0] * distance if fractions.size() > 0 else 0.0


func _begin_return_to_lane() -> void:
	release_intersection()
	_return_lane = {}
	var closest := INF
	for candidate: Dictionary in _routes.call("get_spawn_candidates"):
		var distance := global_position.distance_squared_to(candidate["position"])
		if distance < closest:
			closest = distance
			_return_lane = candidate
	_returning = not _return_lane.is_empty()
	_repath_remaining = 0.0
	_stuck_time = 0.0
	_reverse_remaining = 0.0


func _resume_lane_patrol() -> void:
	var direction: Vector2 = _return_lane["direction"]
	if not _try_face(direction):
		stop()
		return
	var spawn := _return_lane.duplicate()
	spawn["position"] = global_position # Keep the real position, never snap.
	configure(_routes, spawn, _rng.randi(), appearance_variant)


func set_simulation_enabled(enabled: bool) -> void:
	super.set_simulation_enabled(enabled)
	if is_instance_valid(_visual) and _visual.has_method("set_animation_enabled"):
		_visual.call("set_animation_enabled", enabled)


func can_see_target(target: Node2D) -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree() or not target.is_visible_in_tree():
		return false
	var offset := target.global_position - global_position
	if not _simulation_enabled or offset.length_squared() > DETECTION_DISTANCE * DETECTION_DISTANCE:
		return false
	var forward := Vector2.UP.rotated(global_rotation)
	if not offset.is_zero_approx() and forward.dot(offset.normalized()) < cos(VISION_HALF_ANGLE):
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position, 1)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _update_police_profile() -> void:
	cruise_speed = PURSUIT_SPEEDS[pursuit_level]
	acceleration = 100.0 if pursuit_level == 0 else 120.0 + pursuit_level * 30.0
	if is_instance_valid(_visual) and _visual.has_method("set_emergency_active"):
		_visual.call("set_emergency_active", pursuit_level > 0 and not _searching)


func _get_intercept_position() -> Vector2:
	var destination := last_known_position
	# Search uses the frozen last report. Predictive offsets apply only while
	# the target is actually observed; they never reveal its hidden position.
	if not _searching and pursuit_level >= 2 and pursuit_slot > 0:
		destination += _observed_velocity * (0.65 if pursuit_level == 2 else 1.0)
		if pursuit_level >= 3:
			var offsets: Array[Vector2] = [Vector2.ZERO, Vector2(100, 0), Vector2(0, 100), Vector2(-100, 0)]
			destination += offsets[pursuit_slot % offsets.size()]
	return destination.clamp(Vector2(60, 60), Vector2(2340, 1740))
