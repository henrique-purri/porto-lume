extends Node2D
## População local limitada. O centro acompanha o corpo atualmente controlado.

const PEDESTRIAN_SCENE: PackedScene = preload("res://npc/pedestrian.tscn")
const PATHS_SCRIPT: Script = preload("res://scripts/pedestrian_paths.gd")

@export_range(0, 20) var max_active_pedestrians: int = 10
@export var spawn_radius: float = 760.0
@export var despawn_radius: float = 1100.0
@export var minimum_spawn_distance: float = 150.0
@export_range(1, 4) var spawn_budget: int = 2
@export var maintenance_interval: float = 0.75
@export var seed_value: int = 0

var paths: RefCounted
var population_enabled: bool = true
var _player: CharacterBody2D
var _interaction: Node
var _vehicles: Node2D
var _vehicle_threat: CharacterBody2D
var _pedestrians: Array[CharacterBody2D] = []
var _random := RandomNumberGenerator.new()
var _maintenance_timer: Timer
var _spawn_shape := CircleShape2D.new()
var _spawn_serial: int = 0
var _configured: bool = false
var _suspended: bool = false


func _ready() -> void:
	_maintenance_timer = Timer.new()
	_maintenance_timer.name = "PopulationTimer"
	_maintenance_timer.wait_time = maintenance_interval
	_maintenance_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(_maintenance_timer)
	_maintenance_timer.timeout.connect(refresh_population)
	_spawn_shape.radius = 12.0


func setup(player: CharacterBody2D, interaction: Node, vehicles: Node2D) -> void:
	_player = player
	_interaction = interaction
	_vehicles = vehicles
	paths = PATHS_SCRIPT.new()
	if seed_value == 0:
		_random.randomize()
	else:
		_random.seed = seed_value
	for node: Node in vehicles.get_children():
		if node is CharacterBody2D and node.has_method("set_driver_active"):
			_vehicle_threat = node as CharacterBody2D
			break
	_configured = true
	_maintenance_timer.start()
	refresh_population.call_deferred(true)


func get_focus_actor() -> Node2D:
	if is_instance_valid(_interaction):
		var driven: Variant = _interaction.get("current_vehicle")
		if is_instance_valid(driven) and driven is Node2D:
			return driven as Node2D
	return _player


func get_active_count() -> int:
	var count := 0
	for pedestrian: CharacterBody2D in _pedestrians:
		if is_instance_valid(pedestrian) and not pedestrian.is_queued_for_deletion():
			count += 1
	return count


func get_pedestrians() -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = []
	for pedestrian: CharacterBody2D in _pedestrians:
		if is_instance_valid(pedestrian) and not pedestrian.is_queued_for_deletion():
			result.append(pedestrian)
	return result


func refresh_population(initial: bool = false) -> void:
	if not _configured or not population_enabled or _suspended:
		return
	var actor := get_focus_actor()
	if not is_instance_valid(actor):
		return
	var center := actor.global_position
	for index in range(_pedestrians.size() - 1, -1, -1):
		var pedestrian := _pedestrians[index]
		if not is_instance_valid(pedestrian):
			_pedestrians.remove_at(index)
		elif pedestrian.is_queued_for_deletion() or pedestrian.global_position.distance_squared_to(center) > despawn_radius * despawn_radius or _pedestrians.size() > max_active_pedestrians:
			_remove_pedestrian(pedestrian)
			_pedestrians.remove_at(index)
	var needed := mini(max_active_pedestrians - get_active_count(), max_active_pedestrians if initial else spawn_budget)
	if needed <= 0:
		return
	var candidates: Array[Vector2] = []
	var points: PackedVector2Array = paths.call("get_spawn_points")
	for point: Vector2 in points:
		var distance := point.distance_squared_to(center)
		if distance >= minimum_spawn_distance * minimum_spawn_distance and distance <= spawn_radius * spawn_radius:
			candidates.append(point)
	# Ordem aleatória própria, sem depender do gerador global ou fazer busca infinita.
	for index in candidates.size():
		var swap_index := _random.randi_range(index, candidates.size() - 1)
		var point := candidates[swap_index]
		candidates[swap_index] = candidates[index]
		candidates[index] = point
		if not _can_spawn(point):
			continue
		var pedestrian := PEDESTRIAN_SCENE.instantiate() as CharacterBody2D
		add_child(pedestrian)
		pedestrian.call("configure", paths, point, _random.randi(), _spawn_serial % 5)
		pedestrian.call("set_vehicle_threat", _vehicle_threat)
		_pedestrians.append(pedestrian)
		_spawn_serial += 1
		needed -= 1
		if needed <= 0:
			break


func _can_spawn(point: Vector2) -> bool:
	for pedestrian: CharacterBody2D in _pedestrians:
		if is_instance_valid(pedestrian) and pedestrian.global_position.distance_squared_to(point) < 40.0 * 40.0:
			return false
	for vehicle: Node in _vehicles.get_children():
		if vehicle is Node2D and (vehicle as Node2D).global_position.distance_squared_to(point) < 70.0 * 70.0:
			return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _spawn_shape
	query.transform = Transform2D(0, point)
	query.collision_mask = 15
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _remove_pedestrian(pedestrian: CharacterBody2D) -> void:
	if not is_instance_valid(pedestrian):
		return
	pedestrian.call("set_simulation_enabled", false)
	pedestrian.collision_layer = 0
	pedestrian.collision_mask = 0
	pedestrian.hide()
	pedestrian.queue_free()


func clear_population() -> void:
	for pedestrian: CharacterBody2D in _pedestrians:
		_remove_pedestrian(pedestrian)
	_pedestrians.clear()


func set_population_enabled(enabled: bool) -> void:
	population_enabled = enabled
	if not enabled:
		_maintenance_timer.stop()
		clear_population()
	elif _configured and not _suspended:
		_maintenance_timer.start()
		refresh_population()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_suspended = true
		if is_instance_valid(_maintenance_timer):
			_maintenance_timer.stop()
		for pedestrian: CharacterBody2D in get_pedestrians():
			pedestrian.call("set_simulation_enabled", false)
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		_suspended = false
		for pedestrian: CharacterBody2D in get_pedestrians():
			pedestrian.call("set_simulation_enabled", true)
		if _configured and population_enabled:
			_maintenance_timer.start()
