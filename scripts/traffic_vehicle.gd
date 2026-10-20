extends CharacterBody2D
## Lane-following NPC. Shared roads/manager own topology and junction priority.

const CONTACTS := preload("res://scripts/vehicle_contacts.gd")
const ROADS := preload("res://scripts/traffic_routes.gd")
const BODY_COLORS: Array[Color] = [Color("6aa5b5"), Color("dfba64"), Color("9b90bb"), Color("92ad81")]
const SERVICE_BRAKING: float = 210.0
const ENTRY_STOP_DISTANCE: float = 47.0
const JUNCTION_CLEAR_DISTANCE: float = 144.0

var driven: bool = true
var speed: float = 0.0
var cruise_speed: float = 120.0
var acceleration: float = 95.0
var following_gap: float = 23.0
var following_headway: float = 0.48
var appearance_variant: int = 0
var current_from: int = -1
var current_to: int = -1
var current_next: int = -1
var active_route := PackedVector2Array()

var _routes: RefCounted
var _manager: Node
var _rng := RandomNumberGenerator.new()
var _route_index: int = 0
var _state: StringName = &"paused"
var _simulation_enabled: bool = true
var _perception_remaining: float = 0.0
var _obstacle_clearance: float = INF
var _reserved_junction: int = -1
var _reserved_exit_direction := Vector2.ZERO
var _entry_point := Vector2.ZERO
var _incoming_direction := Vector2.ZERO
var _has_entered_junction: bool = false
var _configured: bool = false
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _visual: Node2D = $Visual


func _ready() -> void:
	set_physics_process(_configured and _simulation_enabled)


func configure(route_provider: RefCounted, spawn: Dictionary, seed_value: int, variant: int) -> void:
	_release_reservation()
	_routes = route_provider
	_rng.seed = seed_value
	current_from = int(spawn.get("from", -1))
	current_to = int(spawn.get("to", -1))
	current_next = int(spawn["next"]) if spawn.has("next") else _choose_next_intersection()
	global_position = spawn.get("position", Vector2.ZERO)
	var direction: Vector2 = spawn.get("direction", _routes.call("get_direction", current_from, current_to))
	global_rotation = direction.angle() + PI / 2.0
	appearance_variant = posmod(variant, BODY_COLORS.size())
	cruise_speed = _rng.randf_range(100.0, 145.0)
	acceleration = _rng.randf_range(75.0, 120.0)
	following_gap = _rng.randf_range(18.0, 30.0)
	following_headway = _rng.randf_range(0.35, 0.62)
	_perception_remaining = _rng.randf_range(0.0, 0.15)
	_obstacle_clearance = INF
	_build_route(true)
	_visual.set("body_color", BODY_COLORS[appearance_variant])
	_visual.queue_redraw()
	_configured = true
	driven = true
	_state = &"driving"
	stop()
	set_physics_process(_simulation_enabled)


func set_traffic_manager(manager: Node) -> void:
	_manager = manager


func set_simulation_enabled(enabled: bool) -> void:
	_simulation_enabled = enabled
	driven = enabled
	set_physics_process(enabled and _configured)
	stop()
	_perception_remaining = 0.0
	_state = &"driving" if enabled else &"paused"


func stop() -> void:
	speed = 0.0
	velocity = Vector2.ZERO


func get_state_name() -> StringName:
	return _state


func get_route_points() -> PackedVector2Array:
	return active_route


func release_intersection() -> void:
	_release_reservation()


func _physics_process(delta: float) -> void:
	if not _simulation_enabled or not _configured or active_route.is_empty():
		stop()
		return
	var previous := global_transform
	_release_cleared_reservation()
	_perception_remaining -= delta
	if _perception_remaining <= 0.0:
		_perception_remaining = _rng.randf_range(0.10, 0.16)
		_refresh_obstacle_clearance()
	var desired_speed: float = _get_cruise_speed()
	var junction_travel_limit: float = INF
	var entry_distance: float = (_entry_point - global_position).dot(_incoming_direction)
	if not _has_entered_junction and entry_distance < 0.5:
		_has_entered_junction = true
	# The body waits before its nose enters the shared intersection. Reservations
	# survive the end of a leg until the rear of the capsule has cleared it.
	var braking_distance: float = speed * speed / (2.0 * SERVICE_BRAKING)
	if not _has_entered_junction and entry_distance < braking_distance + ENTRY_STOP_DISTANCE + 85.0:
		if not _request_intersection():
			var stopping_space: float = maxf(entry_distance - ENTRY_STOP_DISTANCE, 0.0)
			junction_travel_limit = stopping_space
			desired_speed = minf(desired_speed, sqrt(2.0 * SERVICE_BRAKING * stopping_space))
	if _has_entered_junction or entry_distance < 65.0:
		desired_speed = minf(desired_speed, _get_corner_speed())
	var gap: float = following_gap + speed * following_headway
	if is_finite(_obstacle_clearance):
		var clear_space: float = maxf(_obstacle_clearance - gap, 0.0)
		desired_speed = minf(desired_speed, sqrt(2.0 * SERVICE_BRAKING * clear_space))
	if desired_speed < 2.0:
		desired_speed = 0.0
	speed = move_toward(speed, desired_speed, (acceleration if desired_speed > speed else SERVICE_BRAKING) * delta)
	var requested_travel: float = speed * delta
	_move_along_route(minf(requested_travel, junction_travel_limit))
	if requested_travel > junction_travel_limit:
		# Preserve the stop line even after a long frame; no stored thrust can
		# carry a vehicle into an intersection without permission.
		stop()
	var displacement: float = previous.origin.distance_to(global_position)
	if is_finite(_obstacle_clearance):
		_obstacle_clearance = maxf(_obstacle_clearance - displacement, 0.0)
	_state = &"waiting" if speed < 2.0 else &"driving"
	_release_cleared_reservation()
	CONTACTS.notify(self, _collision_shape, previous, delta)


func _build_route(find_spawn_segment: bool = false) -> void:
	active_route = _routes.call("build_leg", current_from, current_to, current_next)
	_route_index = 0
	_incoming_direction = _routes.call("get_direction", current_from, current_to)
	var center: Vector2 = _routes.call("get_center", current_to)
	var right := Vector2(-_incoming_direction.y, _incoming_direction.x)
	_entry_point = center - _incoming_direction * ROADS.APPROACH_DISTANCE + right * ROADS.LANE_OFFSET
	_has_entered_junction = false
	if not find_spawn_segment or active_route.size() < 2:
		return
	# Spawn candidates lie on straight lanes; select the containing segment
	# rather than first driving backwards to the start of the complete leg.
	var closest_distance: float = INF
	for index in range(active_route.size() - 1):
		var nearest := Geometry2D.get_closest_point_to_segment(global_position, active_route[index], active_route[index + 1])
		var distance: float = nearest.distance_squared_to(global_position)
		if distance < closest_distance:
			closest_distance = distance
			_route_index = index + 1


func _move_along_route(distance: float) -> void:
	var remaining: float = distance
	var iterations: int = 0
	while remaining > 0.0001 and iterations < 8:
		iterations += 1
		if _route_index >= active_route.size():
			current_from = current_to
			current_to = current_next
			current_next = _choose_next_intersection()
			_build_route()
			if active_route.is_empty():
				stop()
				return
		var offset: Vector2 = active_route[_route_index] - global_position
		var waypoint_distance: float = offset.length()
		if waypoint_distance < 0.001:
			_route_index += 1
			continue
		var direction: Vector2 = offset / waypoint_distance
		if not _try_face(direction):
			stop()
			return
		var step_distance: float = minf(remaining, waypoint_distance)
		velocity = direction * speed
		var collision := move_and_collide(direction * step_distance)
		if collision != null:
			# Do not slide around a stopped vehicle, onto a pavement or through a
			# corner. Wait on the existing lane until the obstruction goes away.
			stop()
			_obstacle_clearance = 0.0
			_perception_remaining = minf(_perception_remaining, 0.05)
			return
		remaining -= step_distance
		if step_distance >= waypoint_distance - 0.001:
			_route_index += 1


func _refresh_obstacle_clearance() -> void:
	var forward := Vector2.UP.rotated(global_rotation)
	var braking_distance: float = speed * speed / (2.0 * SERVICE_BRAKING)
	var lookahead: float = maxf(110.0, braking_distance + following_gap + speed * following_headway + 30.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _collision_shape.shape
	query.transform = global_transform * _collision_shape.transform
	query.collision_mask = 15
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.margin = 0.1
	var state := get_world_2d().direct_space_state
	if not state.intersect_shape(query, 1).is_empty():
		_obstacle_clearance = 0.0
		return
	query.motion = forward * lookahead
	var fractions := state.cast_motion(query)
	_obstacle_clearance = float(fractions[0]) * lookahead if fractions.size() > 0 and fractions[0] < 0.999 else INF


func _choose_next_intersection() -> int:
	# Specialized road agents can choose destinations while retaining this
	# controller's lane geometry, collision handling and junction reservations.
	return int(_routes.call("choose_next", current_from, current_to, _rng))


func _get_cruise_speed() -> float:
	return cruise_speed


func _get_corner_speed() -> float:
	return 90.0


func _try_face(direction: Vector2) -> bool:
	var angle: float = direction.angle() + PI / 2.0
	if absf(angle_difference(global_rotation, angle)) < 0.0001:
		return true
	var proposed := Transform2D(angle, global_position)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _collision_shape.shape
	query.transform = proposed * _collision_shape.transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.margin = 0.02
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	global_transform = proposed
	return true


func _request_intersection() -> bool:
	if _reserved_junction == current_to:
		return true
	if not is_instance_valid(_manager) or not _manager.has_method("request_intersection"):
		return true
	if not bool(_manager.call("request_intersection", self, current_to)):
		return false
	_reserved_junction = current_to
	_reserved_exit_direction = _routes.call("get_direction", current_to, current_next)
	return true


func _release_cleared_reservation() -> void:
	if _reserved_junction < 0:
		return
	var center: Vector2 = _routes.call("get_center", _reserved_junction)
	if (global_position - center).dot(_reserved_exit_direction) >= JUNCTION_CLEAR_DISTANCE:
		_release_reservation()


func _release_reservation() -> void:
	if _reserved_junction >= 0 and is_instance_valid(_manager) and _manager.has_method("release_intersection"):
		_manager.call("release_intersection", self, _reserved_junction)
	_reserved_junction = -1
	_reserved_exit_direction = Vector2.ZERO


func _exit_tree() -> void:
	_release_reservation()
