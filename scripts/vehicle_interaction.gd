extends Node
## Faz a troca de controle e mantém a mesma câmera entre os dois corpos.

const DRIVEABLE_SCENE: PackedScene = preload("res://vehicles/driveable_car.tscn")
const MAX_ACQUIRED_TRAFFIC: int = 2

@export var interaction_distance: float = 112.0
@export var world_bounds := Rect2(0, 0, 2400, 1800)

var current_vehicle: CharacterBody2D
var nearby_vehicle: PhysicsBody2D
var _player: CharacterBody2D
var _hud: CanvasLayer
var _vehicles: Node2D
var _traffic_source: Node
var _acquired_traffic: Array[CharacterBody2D] = []
var _cleanup_remaining: float = 1.0
var _camera: Camera2D
var _walking_layer: int
var _walking_mask: int
var _exit_shape := CircleShape2D.new()


func setup(player: CharacterBody2D, hud: CanvasLayer, vehicles: Node2D) -> void:
	_player = player
	_hud = hud
	_vehicles = vehicles
	_camera = player.get_node("Camera2D") as Camera2D
	_walking_layer = player.collision_layer
	_walking_mask = player.collision_mask
	_exit_shape.radius = 12.0 # Raio do jogador (10) mais folga para caminhar.
	_hud.connect("vehicle_action_requested", request_vehicle_action)
	for node: Node in vehicles.get_children():
		if node is CharacterBody2D and node.has_method("set_driver_active"):
			node.set_meta("initial_player_vehicle", true)
			node.set_meta("player_owned", true)
			break
	_update_nearby_vehicle()


func set_traffic_source(source: Node) -> void:
	_traffic_source = source


func _physics_process(delta: float) -> void:
	if is_instance_valid(_player):
		_update_nearby_vehicle()
		_cleanup_remaining -= delta
		if _cleanup_remaining <= 0.0:
			_cleanup_remaining = 1.0
			_cleanup_acquired_traffic()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo():
		if request_vehicle_action():
			get_viewport().set_input_as_handled()


func request_vehicle_action() -> bool:
	if not is_instance_valid(_player):
		return false
	if is_instance_valid(current_vehicle):
		return _exit_vehicle()
	_update_nearby_vehicle()
	if is_instance_valid(nearby_vehicle):
		var vehicle := _prepare_vehicle(nearby_vehicle)
		if not is_instance_valid(vehicle):
			return false
		_enter_vehicle(vehicle)
		return true
	return false


func _update_nearby_vehicle() -> void:
	if is_instance_valid(current_vehicle):
		_hud.call("set_vehicle_action", true, true)
		return
	nearby_vehicle = null
	var closest_distance := interaction_distance * interaction_distance
	var candidates: Array[Node] = []
	for node: Node in _vehicles.get_children():
		candidates.append(node)
	if is_instance_valid(_traffic_source):
		for node: Node in _traffic_source.call("get_vehicles"):
			candidates.append(node)
	for node: Node in candidates:
		if not _is_enterable(node):
			continue
		var candidate := node as PhysicsBody2D
		var distance := _player.global_position.distance_squared_to(candidate.global_position)
		if distance <= closest_distance and _can_reach_vehicle(candidate):
			closest_distance = distance
			nearby_vehicle = candidate
	_hud.call("set_vehicle_action", is_instance_valid(nearby_vehicle), false)


func _is_enterable(node: Node) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion() or not node is PhysicsBody2D or node.is_in_group("police_vehicles"):
		return false
	if node.has_method("set_driver_active"):
		return true
	if node is StaticBody2D:
		return (node as StaticBody2D).collision_layer & 4 != 0
	return node.is_in_group("traffic_vehicles") and absf(float(node.get("speed"))) < 12.0


func _can_reach_vehicle(vehicle: PhysicsBody2D) -> bool:
	# A proximidade não permite entrar através de um prédio ou outro carro.
	var query := PhysicsRayQueryParameters2D.create(_player.global_position, vehicle.global_position, 5)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == vehicle


func _prepare_vehicle(source: PhysicsBody2D) -> CharacterBody2D:
	if source.has_method("set_driver_active"):
		return source as CharacterBody2D
	if not _is_enterable(source):
		return null
	var from_traffic: bool = source.is_in_group("traffic_vehicles")
	_cleanup_acquired_traffic()
	if from_traffic and _acquired_traffic.size() >= MAX_ACQUIRED_TRAFFIC:
		_hud.call("show_feedback", "Nenhum outro carro disponível agora")
		return null
	var transform := source.global_transform
	var color: Color = source.get("body_color") if source is StaticBody2D else source.get_node("Visual").get("body_color")
	# Retire the old AI/body before enabling its replacement; both never collide
	# or run simultaneously. All handling/camera behavior uses the original scene.
	if from_traffic:
		if not is_instance_valid(_traffic_source) or not bool(_traffic_source.call("release_vehicle", source)):
			return null
	else:
		source.collision_layer = 0
		source.collision_mask = 0
		source.hide()
		source.queue_free()
	var vehicle := DRIVEABLE_SCENE.instantiate() as CharacterBody2D
	vehicle.name = "AcquiredCar"
	_vehicles.add_child(vehicle)
	vehicle.global_transform = transform
	vehicle.get_node("Visual").set("body_color", color)
	vehicle.get_node("Visual").queue_redraw()
	vehicle.set_meta("player_owned", false)
	vehicle.set_meta("acquired_traffic", from_traffic)
	if from_traffic:
		_acquired_traffic.append(vehicle)
	return vehicle


func _cleanup_acquired_traffic() -> void:
	var view: Rect2 = get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_visible_rect()
	view = view.grow(180.0)
	var focus: Node2D = current_vehicle if is_instance_valid(current_vehicle) else _player
	for index in range(_acquired_traffic.size() - 1, -1, -1):
		var car := _acquired_traffic[index]
		if not is_instance_valid(car) or car.is_queued_for_deletion():
			_acquired_traffic.remove_at(index)
		elif car != current_vehicle and not view.has_point(car.global_position) and car.global_position.distance_squared_to(focus.global_position) > 900.0 * 900.0:
			car.collision_layer = 0
			car.collision_mask = 0
			car.hide()
			car.queue_free()
			_acquired_traffic.remove_at(index)


func _enter_vehicle(vehicle: CharacterBody2D) -> void:
	var theft: bool = not bool(vehicle.get_meta("player_owned", false)) and not bool(vehicle.get_meta("initial_player_vehicle", false))
	reset_controls()
	current_vehicle = vehicle
	nearby_vehicle = null
	_player.set_physics_process(false)
	_player.collision_layer = 0
	_player.collision_mask = 0
	_player.hide()
	vehicle.set("control_source", _hud)
	vehicle.call("set_driver_active", true)
	_hud.call("set_driving", true)
	_hud.call("set_vehicle_action", true, true)
	_follow(vehicle)
	if theft:
		vehicle.set_meta("player_owned", true)
		var crime_system := get_tree().get_first_node_in_group("crime_system")
		if is_instance_valid(crime_system):
			crime_system.call("register_crime", &"vehicle_theft", vehicle, vehicle)


func _exit_vehicle() -> bool:
	# O botão estaciona primeiro. Sem uma saída livre, permanece no veículo.
	reset_controls()
	var exit_position := find_safe_exit_position(current_vehicle)
	if not exit_position.is_finite():
		_hud.call("show_feedback", "Sem espaço para sair")
		return false
	var vehicle := current_vehicle
	current_vehicle = null
	vehicle.call("set_driver_active", false)
	_player.global_position = exit_position
	_player.collision_layer = _walking_layer
	_player.collision_mask = _walking_mask
	_player.call("reset_motion")
	_player.show()
	_player.set_physics_process(true)
	_hud.call("set_driving", false)
	_follow(_player)
	_update_nearby_vehicle()
	return true


func find_safe_exit_position(vehicle: CharacterBody2D) -> Vector2:
	var offsets: Array[Vector2] = [
		Vector2(-46, 0), Vector2(46, 0),
		Vector2(-46, 26), Vector2(46, 26),
		Vector2(0, 68), Vector2(0, -68),
		Vector2(-46, -26), Vector2(46, -26),
	]
	var safe_bounds := world_bounds.grow(-_exit_shape.radius)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _exit_shape
	query.collision_mask = 13 # Construções, veículos e pedestres na posição de saída.
	query.exclude = [_player.get_rid()]
	query.collide_with_areas = false
	for offset: Vector2 in offsets:
		var point := vehicle.to_global(offset)
		if not safe_bounds.has_point(point):
			continue
		query.transform = Transform2D(0.0, point)
		if vehicle.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			return point
	return Vector2.INF


func _follow(target: Node2D) -> void:
	_camera.reparent(target, false)
	_camera.position = Vector2.ZERO
	_camera.rotation = 0.0
	_camera.make_current()


func reset_controls() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down", &"interact"]:
		Input.action_release(action)
	if is_instance_valid(_player):
		_player.call("reset_motion")
	if is_instance_valid(_hud):
		_hud.call("reset_controls")
	if is_instance_valid(current_vehicle):
		current_vehicle.call("stop")
