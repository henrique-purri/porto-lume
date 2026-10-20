extends "res://scripts/traffic_vehicle.gd"
## A road agent with dispatch destinations; it never reads an unseen target.

const DETECTION_DISTANCE: float = 600.0
const PURSUIT_SPEEDS: Array[float] = [125.0, 175.0, 205.0, 235.0]

var police_state: StringName = &"patrol"
var pursuit_level: int = 0
var pursuit_slot: int = 0
var last_known_position := Vector2.ZERO
var intercept_position := Vector2.ZERO
var _observed_velocity := Vector2.ZERO
var _police_manager: Node
var _searching: bool = false
var _block_remaining: float = 0.0
var _block_cooldown: float = 0.0


func configure(route_provider: RefCounted, spawn: Dictionary, seed_value: int, variant: int) -> void:
	super.configure(route_provider, spawn, seed_value, variant)
	_visual.set("body_color", Color("e0e6dc"))
	_visual.queue_redraw()
	_update_police_profile()


func set_police_manager(manager: Node) -> void:
	_police_manager = manager


func set_pursuit(target_position: Vector2, level: int, slot: int = 0, observed_velocity: Vector2 = Vector2.ZERO) -> void:
	if not target_position.is_finite():
		return
	last_known_position = target_position
	pursuit_level = clampi(level, 0, 3)
	pursuit_slot = maxi(slot, 0)
	_observed_velocity = observed_velocity.limit_length(340.0)
	if pursuit_level == 0:
		clear_pursuit()
		return
	intercept_position = _get_intercept_position()
	_update_police_profile()
	police_state = &"blocking" if _block_remaining > 0.0 else (&"searching" if _searching else &"pursuing")
	_refresh_uncommitted_turn()


func set_searching(searching: bool) -> void:
	_searching = searching
	if searching:
		_block_remaining = 0.0
	if pursuit_level > 0:
		police_state = &"blocking" if _block_remaining > 0.0 else (&"searching" if searching else &"pursuing")
		_visual.call("set_emergency_active", not searching)


func clear_pursuit() -> void:
	if pursuit_level == 0 and police_state == &"patrol":
		return
	pursuit_level = 0
	_searching = false
	_block_remaining = 0.0
	police_state = &"patrol"
	_observed_velocity = Vector2.ZERO
	_update_police_profile()
	_refresh_uncommitted_turn()


func get_police_state() -> StringName:
	return police_state


func _physics_process(delta: float) -> void:
	_block_remaining = maxf(_block_remaining - delta, 0.0)
	_block_cooldown = maxf(_block_cooldown - delta, 0.0)
	_try_begin_block()
	super._physics_process(delta)
	if pursuit_level > 0:
		police_state = &"blocking" if _block_remaining > 0.0 else (&"searching" if _searching else &"pursuing")


func set_simulation_enabled(enabled: bool) -> void:
	super.set_simulation_enabled(enabled)
	if is_instance_valid(_visual) and _visual.has_method("set_animation_enabled"):
		_visual.call("set_animation_enabled", enabled)


func can_see_target(target: Node2D) -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree() or not target.is_visible_in_tree():
		return false
	if not _simulation_enabled or global_position.distance_squared_to(target.global_position) > DETECTION_DISTANCE * DETECTION_DISTANCE:
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position, 1)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _update_police_profile() -> void:
	cruise_speed = PURSUIT_SPEEDS[pursuit_level]
	if pursuit_level < 2:
		_block_remaining = 0.0
	if pursuit_level > 0:
		acceleration = 120.0 + pursuit_level * 30.0
		following_gap = 23.0 - pursuit_level * 3.0
		following_headway = 0.48 - pursuit_level * 0.07
	else:
		acceleration = 100.0
		following_gap = 23.0
		following_headway = 0.48
	if is_instance_valid(_visual) and _visual.has_method("set_emergency_active"):
		_visual.call("set_emergency_active", pursuit_level > 0 and not _searching)


func _get_cruise_speed() -> float:
	return 0.0 if _block_remaining > 0.0 else PURSUIT_SPEEDS[pursuit_level]


func _get_corner_speed() -> float:
	return 90.0 + pursuit_level * 7.0


func _request_intersection() -> bool:
	# A unit making a roadblock must not acquire a crossing while braking.
	return false if _block_remaining > 0.0 else super._request_intersection()


func _try_begin_block() -> void:
	if pursuit_level < 2 or pursuit_slot == 0 or _searching or _block_cooldown > 0.0 or not _configured:
		return
	if _reserved_junction >= 0 or _has_entered_junction or _observed_velocity.length_squared() < 35.0 * 35.0:
		return
	var entry_distance: float = (_entry_point - global_position).dot(_incoming_direction)
	var braking_distance: float = speed * speed / (2.0 * SERVICE_BRAKING)
	if entry_distance < ENTRY_STOP_DISTANCE + braking_distance + 100.0:
		return
	var target_heading := _observed_velocity.normalized()
	var separation := global_position - last_known_position
	var lateral := Vector2(-target_heading.y, target_heading.x)
	# A unit that reached a lane ahead of the observed target may briefly hold
	# it. Never stop the crossing itself, and never teleport/slide into the way.
	if separation.dot(target_heading) < 30.0 or absf(separation.dot(lateral)) > 75.0:
		return
	if global_position.distance_squared_to(intercept_position) > 180.0 * 180.0:
		return
	_block_remaining = 2.0 if pursuit_level == 2 else 3.0
	_block_cooldown = 8.0


func _refresh_uncommitted_turn() -> void:
	if not _configured or _reserved_junction >= 0 or _has_entered_junction:
		return
	var entry_distance: float = (_entry_point - global_position).dot(_incoming_direction)
	# Never rewrite geometry on the junction curve or after obtaining a lease.
	# Before the entry, a newly observed destination can safely replace only
	# the future curve; _build_route(true) retains the car's current lane point.
	if entry_distance < ENTRY_STOP_DISTANCE + 16.0:
		return
	var desired_next: int = _choose_next_intersection()
	if desired_next >= 0 and desired_next != current_next:
		current_next = desired_next
		_build_route(true)


func _choose_next_intersection() -> int:
	if pursuit_level <= 0 or not is_instance_valid(_routes):
		return super._choose_next_intersection()
	var centers: PackedVector2Array = _routes.call("get_intersections")
	var destination := _get_intercept_position()
	intercept_position = destination
	var current_center: Vector2 = _routes.call("get_center", current_to)
	var incoming: Vector2 = _routes.call("get_direction", current_from, current_to)
	var best: int = -1
	var best_score: float = INF
	for candidate in range(centers.size()):
		if candidate == current_from:
			continue
		var direction: Vector2 = _routes.call("get_direction", current_to, candidate)
		if direction.is_zero_approx():
			continue
		# Manhattan road distance is exact on this small rectangular graph.
		# A small straight preference avoids oscillating equal-cost decisions.
		var offset: Vector2 = centers[candidate] - destination
		var score: float = absf(offset.x) + absf(offset.y)
		score -= direction.dot(incoming) * 12.0
		# Distinct interception slots choose different equal-distance approaches.
		var lateral: float = (centers[candidate] - current_center).cross(destination - current_center)
		if pursuit_level >= 3 and pursuit_slot % 2 == 1:
			score += signf(lateral) * 8.0
		if score < best_score:
			best_score = score
			best = candidate
	return best if best >= 0 else super._choose_next_intersection()


func _get_intercept_position() -> Vector2:
	var destination := last_known_position
	if pursuit_level >= 2 and pursuit_slot > 0:
		destination += _observed_velocity * (0.9 if pursuit_level == 2 else 1.35)
	if pursuit_level >= 3:
		# Spread cars toward neighboring junction approaches instead of placing
		# every unit on the same destination. These are dispatch goals only;
		# the inherited controller still follows legal street lanes and curves.
		var offsets: Array[Vector2] = [Vector2.ZERO, Vector2(210, 0), Vector2(0, 210), Vector2(-210, 0)]
		destination += offsets[pursuit_slot % offsets.size()]
	return destination.clamp(Vector2(100, 100), Vector2(2300, 1700))
