extends Node2D
## Bounded local traffic and a small FIFO crossing coordinator.
## Route/actor APIs are independent of the car's appearance or future role.

const CAR_SCENE: PackedScene = preload("res://vehicles/traffic_car.tscn")
const ROUTES_SCRIPT: Script = preload("res://scripts/traffic_routes.gd")

@export_range(0, 12) var max_active_vehicles: int = 6
@export_range(0, 12) var walking_vehicle_target: int = 4
@export var minimum_spawn_distance: float = 520.0
@export var spawn_radius: float = 1400.0
@export var despawn_radius: float = 1700.0
@export var spawn_view_margin: float = 160.0
@export var maintenance_interval: float = 0.8
@export_range(1, 2) var spawn_budget: int = 1
@export var seed_value: int = 0

var routes: RefCounted
var population_enabled: bool = true
var _player: CharacterBody2D
var _interaction: Node
var _vehicles: Array[CharacterBody2D] = []
var _random := RandomNumberGenerator.new()
var _timer: Timer
var _configured: bool = false
var _suspended: bool = false
var _serial: int = 0
var _car_shape := CapsuleShape2D.new()
var _junction_owners: Dictionary = {}
var _junction_queues: Dictionary = {}


func _ready() -> void:
	_car_shape.radius = 24.0
	_car_shape.height = 88.0
	_timer = Timer.new()
	_timer.name = "TrafficPopulationTimer"
	_timer.wait_time = maintenance_interval
	_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(_timer)
	_timer.timeout.connect(refresh_population)


func setup(player: CharacterBody2D, interaction: Node, _parked_vehicles: Node2D) -> void:
	_player = player
	_interaction = interaction
	routes = ROUTES_SCRIPT.new()
	if seed_value == 0:
		_random.randomize()
	else:
		_random.seed = seed_value
	_configured = true
	_timer.start()
	_initial_population.call_deferred()


func _initial_population() -> void:
	# Camera2D must have applied its real scroll/limits before the first spawn.
	await get_tree().process_frame
	await get_tree().process_frame
	refresh_population(true)


func get_focus_actor() -> Node2D:
	if is_instance_valid(_interaction):
		var vehicle: Variant = _interaction.get("current_vehicle")
		if is_instance_valid(vehicle) and vehicle is Node2D:
			return vehicle as Node2D
	return _player


func get_visible_world_rect() -> Rect2:
	# Includes smoothing, camera limits, zoom and both phone orientations.
	return get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()


func get_vehicles() -> Array[CharacterBody2D]:
	var active: Array[CharacterBody2D] = []
	for car: CharacterBody2D in _vehicles:
		if is_instance_valid(car) and not car.is_queued_for_deletion():
			active.append(car)
	return active


func get_active_count() -> int:
	return get_vehicles().size()


func get_target_count() -> int:
	var driving: bool = is_instance_valid(_interaction) and is_instance_valid(_interaction.get("current_vehicle"))
	return max_active_vehicles if driving else mini(walking_vehicle_target, max_active_vehicles)


func refresh_population(initial: bool = false) -> void:
	if not _configured or not population_enabled or _suspended:
		return
	var focus := get_focus_actor()
	if not is_instance_valid(focus):
		return
	var center := focus.global_position
	var excluded := get_visible_world_rect().grow(spawn_view_margin)
	var target := get_target_count()
	for index in range(_vehicles.size() - 1, -1, -1):
		var car := _vehicles[index]
		if not is_instance_valid(car):
			_vehicles.remove_at(index)
			continue
		var outside: bool = not excluded.has_point(car.global_position)
		if car.is_queued_for_deletion() or (outside and (car.global_position.distance_squared_to(center) > despawn_radius * despawn_radius or _vehicles.size() > target)):
			_retire(car)
			_vehicles.remove_at(index)
	var needed := mini(target - get_active_count(), target if initial else spawn_budget)
	if needed <= 0:
		return
	var candidates: Array = routes.call("get_spawn_candidates")
	# Bounded shuffle: each street slot is tried at most once per maintenance.
	for index in range(candidates.size()):
		var swap: int = _random.randi_range(index, candidates.size() - 1)
		var candidate: Dictionary = candidates[swap]
		candidates[swap] = candidates[index]
		candidates[index] = candidate
		var point: Vector2 = candidate["position"]
		var distance := point.distance_squared_to(center)
		if excluded.has_point(point) or distance < minimum_spawn_distance * minimum_spawn_distance or distance > spawn_radius * spawn_radius:
			continue
		if not _can_spawn(candidate):
			continue
		var car := CAR_SCENE.instantiate() as CharacterBody2D
		add_child(car)
		car.call("set_traffic_manager", self)
		car.call("configure", routes, candidate, _random.randi(), _serial)
		_vehicles.append(car)
		_serial += 1
		needed -= 1
		if needed <= 0:
			break


func _can_spawn(candidate: Dictionary) -> bool:
	var point: Vector2 = candidate["position"]
	for car: CharacterBody2D in _vehicles:
		if is_instance_valid(car) and car.global_position.distance_squared_to(point) < 175.0 * 175.0:
			return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _car_shape
	var direction: Vector2 = candidate["direction"]
	query.transform = Transform2D(direction.angle() + PI / 2.0, point)
	query.collision_mask = 15
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func request_intersection(car: CharacterBody2D, junction: int) -> bool:
	if not is_instance_valid(car) or _suspended:
		return false
	_prune_junction(junction)
	var owner: CharacterBody2D = _owner(junction)
	if owner == car:
		return true
	# A faster follower must never reserve a crossing ahead of its own leader.
	# Otherwise the leader waits for its follower while the follower queues behind
	# the leader: a deadlock even when the crossing and destination are empty.
	if _approach_has_leader(car, junction):
		release_intersection(car, junction)
		return false
	var queue: Array = _junction_queues.get(junction, [])
	var found := false
	for entry: Dictionary in queue:
		if entry["car"].get_ref() == car:
			entry["seen"] = Time.get_ticks_msec()
			found = true
			break
	if not found:
		queue.append({"car": weakref(car), "seen": Time.get_ticks_msec()})
	_junction_queues[junction] = queue
	if is_instance_valid(owner) or queue.is_empty():
		return false
	# Preserve arrival order among cars that can actually leave the crossing.
	# A blocked destination lane must not freeze traffic on all four approaches.
	var eligible_index: int = -1
	for index in range(queue.size()):
		var queued_car: CharacterBody2D = queue[index]["car"].get_ref() as CharacterBody2D
		if is_instance_valid(queued_car) and not _approach_has_leader(queued_car, junction) and _exit_is_clear(queued_car, junction):
			eligible_index = index
			break
	if eligible_index < 0 or queue[eligible_index]["car"].get_ref() != car:
		return false
	_junction_owners[junction] = weakref(car)
	queue.remove_at(eligible_index)
	return true


func _approach_has_leader(car: CharacterBody2D, junction: int) -> bool:
	var from_id: int = int(car.get("current_from"))
	var direction: Vector2 = routes.call("get_direction", from_id, junction)
	var right := Vector2(-direction.y, direction.x)
	for node: Node in get_tree().get_nodes_in_group("traffic_vehicles"):
		var other := node as CharacterBody2D
		if not is_instance_valid(other) or other == car or other.is_queued_for_deletion():
			continue
		if int(other.get("current_to")) != junction or int(other.get("current_from")) != from_id:
			continue
		var offset := other.global_position - car.global_position
		if offset.dot(direction) > 1.0 and absf(offset.dot(right)) < 45.0:
			return true
	return false


func _exit_is_clear(car: CharacterBody2D, junction: int) -> bool:
	var next: int = int(car.get("current_next"))
	if next < 0:
		return false
	var direction: Vector2 = routes.call("get_direction", junction, next)
	var right := Vector2(-direction.y, direction.x)
	var center: Vector2 = routes.call("get_center", junction)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _car_shape
	query.collision_mask = 7
	query.exclude = [car.get_rid()]
	query.collide_with_areas = false
	# Enough space for the whole car beyond the conflict area; do not enter
	# a crossing whose destination lane is already backed up.
	for distance: float in [145.0, 205.0]:
		query.transform = Transform2D(direction.angle() + PI / 2.0, center + direction * distance + right * 32.0)
		if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true


func _owner(junction: int) -> CharacterBody2D:
	var reference: WeakRef = _junction_owners.get(junction)
	if reference == null:
		return null
	return reference.get_ref() as CharacterBody2D


func _prune_junction(junction: int) -> void:
	var owner := _owner(junction)
	# A temporarily paused owner can still physically occupy the crossing.
	# Keep it reserved until rear clearance, explicit retirement or deletion.
	if not is_instance_valid(owner) or owner.is_queued_for_deletion():
		_junction_owners.erase(junction)
	var queue: Array = _junction_queues.get(junction, [])
	for index in range(queue.size() - 1, -1, -1):
		var car: CharacterBody2D = queue[index]["car"].get_ref() as CharacterBody2D
		if not is_instance_valid(car) or car.is_queued_for_deletion() or not car.is_physics_processing() or Time.get_ticks_msec() - int(queue[index]["seen"]) > 750:
			queue.remove_at(index)
	_junction_queues[junction] = queue


func release_intersection(car: CharacterBody2D, junction: int) -> void:
	if _owner(junction) == car:
		_junction_owners.erase(junction)
	var queue: Array = _junction_queues.get(junction, [])
	for index in range(queue.size() - 1, -1, -1):
		if queue[index]["car"].get_ref() == car:
			queue.remove_at(index)


func _retire(car: CharacterBody2D) -> void:
	if not is_instance_valid(car):
		return
	for junction: int in _junction_owners.keys():
		release_intersection(car, junction)
	for junction: int in _junction_queues.keys():
		release_intersection(car, junction)
	car.call("set_simulation_enabled", false)
	car.collision_layer = 0
	car.collision_mask = 0
	car.hide()
	car.queue_free()


func clear_population() -> void:
	for car: CharacterBody2D in _vehicles:
		_retire(car)
	_vehicles.clear()


func set_population_enabled(enabled: bool) -> void:
	population_enabled = enabled
	if not enabled:
		_timer.stop()
		clear_population()
	elif _configured and not _suspended:
		_timer.start()
		refresh_population()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_suspended = true
		if is_instance_valid(_timer):
			_timer.stop()
		for car: CharacterBody2D in get_vehicles():
			car.call("set_simulation_enabled", false)
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		_suspended = false
		for car: CharacterBody2D in get_vehicles():
			car.call("set_simulation_enabled", true)
		if _configured and population_enabled:
			_timer.start()
