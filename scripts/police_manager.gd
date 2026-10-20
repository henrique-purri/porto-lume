extends Node2D
## Small police population. Dispatch uses reported positions; sight uses walls.
## Police share the existing traffic lanes, solid bodies and junction ownership.

const POLICE_SCENE: PackedScene = preload("res://vehicles/police_car.tscn")

@export_range(0, 4) var max_active_police: int = 4
@export var minimum_spawn_distance: float = 520.0
@export var spawn_radius: float = 1400.0
@export var dispatch_radius: float = 900.0
@export var despawn_radius: float = 1700.0
@export var spawn_view_margin: float = 160.0
@export var maintenance_interval: float = 0.8
@export var perception_interval: float = 0.25
@export var seed_value: int = 0

var population_enabled: bool = true
var routes: RefCounted
var _player: CharacterBody2D
var _interaction: Node
var _traffic: Node
var _crime: Node
var _vehicles: Array[CharacterBody2D] = []
var _random := RandomNumberGenerator.new()
var _population_timer: Timer
var _perception_timer: Timer
var _spawn_shape := CapsuleShape2D.new()
var _configured: bool = false
var _suspended: bool = false
var _dispatch_pending: bool = false
var _known_position := Vector2.ZERO
var _known_velocity := Vector2.ZERO


func _ready() -> void:
	_spawn_shape.radius = 24.0
	_spawn_shape.height = 88.0
	_population_timer = _make_timer("PolicePopulationTimer", maintenance_interval, refresh_population)
	_perception_timer = _make_timer("PolicePerceptionTimer", perception_interval, update_observation)


func _make_timer(title: String, interval: float, callback: Callable) -> Timer:
	var timer := Timer.new()
	timer.name = title
	timer.wait_time = interval
	timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(timer)
	timer.timeout.connect(callback)
	return timer


func setup(player: CharacterBody2D, interaction: Node, traffic: Node, crime: Node) -> void:
	_player = player
	_interaction = interaction
	_traffic = traffic
	_crime = crime
	routes = traffic.get("routes") as RefCounted
	if seed_value == 0:
		_random.randomize()
	else:
		_random.seed = seed_value
	_crime.connect("crime_registered", _on_crime_registered)
	_crime.connect("wanted_changed", _on_wanted_changed)
	_configured = true
	_population_timer.start()
	_perception_timer.start()
	_initial_population.call_deferred()


func _initial_population() -> void:
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
	if not is_instance_valid(_crime):
		return 0
	var level := int(_crime.get("wanted_level"))
	return mini([1, 1, 2, 4][clampi(level, 0, 3)], max_active_police)


func refresh_population(_initial: bool = false) -> void:
	if not _configured or not population_enabled or _suspended:
		return
	var focus := get_focus_actor()
	if not is_instance_valid(focus):
		return
	var excluded := get_visible_world_rect().grow(spawn_view_margin)
	var center := focus.global_position
	var target := get_target_count()
	var responding: bool = int(_crime.get("wanted_level")) > 0 and _dispatch_pending
	for index in range(_vehicles.size() - 1, -1, -1):
		var car := _vehicles[index]
		if not is_instance_valid(car):
			_vehicles.remove_at(index)
		elif car.is_queued_for_deletion() or (not excluded.has_point(car.global_position) and (car.global_position.distance_squared_to(center) > despawn_radius * despawn_radius or _vehicles.size() > target)):
			_retire(car)
			_vehicles.remove_at(index)
	# Reinforcements are staggered even when several stars arrive at once.
	if get_active_count() >= target:
		return
	var candidates: Array = routes.call("get_spawn_candidates")
	for index in range(candidates.size()):
		var swap: int = _random.randi_range(index, candidates.size() - 1)
		var candidate: Dictionary = candidates[swap]
		candidates[swap] = candidates[index]
		candidates[index] = candidate
		var point: Vector2 = candidate["position"]
		var distance := point.distance_squared_to(center)
		if excluded.has_point(point) or distance < minimum_spawn_distance * minimum_spawn_distance or distance > spawn_radius * spawn_radius:
			continue
		# The actual focus is used for safety/streaming only. Reinforcements
		# investigate the reported area, not a new hidden position they never saw.
		if responding and point.distance_squared_to(_known_position) > dispatch_radius * dispatch_radius:
			continue
		if not _can_spawn(candidate):
			continue
		var car := POLICE_SCENE.instantiate() as CharacterBody2D
		add_child(car)
		car.call("set_traffic_manager", _traffic)
		car.call("set_police_manager", self)
		car.call("configure", routes, candidate, _random.randi(), get_active_count())
		_vehicles.append(car)
		_send_orders(false)
		break


func _can_spawn(candidate: Dictionary) -> bool:
	var point: Vector2 = candidate["position"]
	var nearby: Array[Node] = get_tree().get_nodes_in_group("moving_vehicles")
	nearby.append_array(get_tree().get_nodes_in_group("player_controlled_vehicle"))
	for node: Node in nearby:
		if node is Node2D and is_instance_valid(node) and not node.is_queued_for_deletion() and (node as Node2D).global_position.distance_squared_to(point) < 175.0 * 175.0:
			return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _spawn_shape
	var direction: Vector2 = candidate["direction"]
	query.transform = Transform2D(direction.angle() + PI / 2.0, point)
	query.collision_mask = 15
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func update_observation() -> void:
	if not _configured or not population_enabled or _suspended or not is_instance_valid(_crime):
		return
	var target := get_focus_actor()
	if not is_instance_valid(target):
		return
	var seen := false
	if int(_crime.get("wanted_level")) > 0:
		for car: CharacterBody2D in get_vehicles():
			if bool(car.call("can_see_target", target)):
				seen = true
				break
	if seen:
		_known_position = target.global_position
		_known_velocity = (target as CharacterBody2D).velocity if target is CharacterBody2D else Vector2.ZERO
		_dispatch_pending = true
	_crime.call("set_police_observation", seen, _known_position)
	_send_orders(seen)


func _send_orders(seen: bool) -> void:
	var level := int(_crime.get("wanted_level"))
	var active := get_vehicles()
	active.sort_custom(func(first: CharacterBody2D, second: CharacterBody2D) -> bool:
		return first.global_position.distance_squared_to(_known_position) < second.global_position.distance_squared_to(_known_position))
	var slot := 0
	for car: CharacterBody2D in active:
		if level > 0 and _dispatch_pending and slot < get_target_count():
			car.call("set_pursuit", _known_position, level, slot, _known_velocity)
			car.call("set_searching", not seen)
		else:
			car.call("clear_pursuit")
		slot += 1


func _on_crime_registered(_type: StringName, _added: float, position: Vector2) -> void:
	# Dispatch receives the incident location. Further hidden player movement
	# cannot update it; only a new crime or confirmed police sighting can.
	_known_position = position
	_known_velocity = Vector2.ZERO
	_dispatch_pending = true
	_send_orders(false)


func _on_wanted_changed(level: int, _heat: float) -> void:
	if level == 0:
		_dispatch_pending = false
		_known_velocity = Vector2.ZERO
	_send_orders(false)


func _retire(car: CharacterBody2D) -> void:
	if not is_instance_valid(car):
		return
	car.call("release_intersection")
	car.call("set_simulation_enabled", false)
	car.collision_layer = 0
	car.collision_mask = 0
	car.hide()
	car.queue_free()


func clear_population() -> void:
	for car: CharacterBody2D in _vehicles:
		_retire(car)
	_vehicles.clear()
	if is_instance_valid(_crime):
		_crime.call("set_police_observation", false, _known_position)


func set_population_enabled(enabled: bool) -> void:
	population_enabled = enabled
	if not enabled:
		_population_timer.stop()
		_perception_timer.stop()
		clear_population()
	elif _configured and not _suspended:
		_population_timer.start()
		_perception_timer.start()
		refresh_population()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_suspended = true
		if is_instance_valid(_population_timer):
			_population_timer.stop()
			_perception_timer.stop()
		for car: CharacterBody2D in get_vehicles():
			car.call("set_simulation_enabled", false)
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		_suspended = false
		for car: CharacterBody2D in get_vehicles():
			car.call("set_simulation_enabled", true)
		if _configured and population_enabled:
			_population_timer.start()
			_perception_timer.start()
