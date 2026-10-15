extends Node
## Faz a troca de controle e mantém a mesma câmera entre os dois corpos.

@export var interaction_distance: float = 112.0
@export var world_bounds := Rect2(0, 0, 2400, 1800)

var current_vehicle: CharacterBody2D
var nearby_vehicle: CharacterBody2D
var _player: CharacterBody2D
var _hud: CanvasLayer
var _vehicles: Node2D
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
	_update_nearby_vehicle()


func _physics_process(_delta: float) -> void:
	if is_instance_valid(_player):
		_update_nearby_vehicle()


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
		_enter_vehicle(nearby_vehicle)
		return true
	return false


func _update_nearby_vehicle() -> void:
	if is_instance_valid(current_vehicle):
		_hud.call("set_vehicle_action", true, true)
		return
	nearby_vehicle = null
	var closest_distance := interaction_distance * interaction_distance
	for node: Node in _vehicles.get_children():
		if not node is CharacterBody2D or not node.has_method("set_driver_active"):
			continue
		var candidate := node as CharacterBody2D
		var distance := _player.global_position.distance_squared_to(candidate.global_position)
		if distance <= closest_distance and _can_reach_vehicle(candidate):
			closest_distance = distance
			nearby_vehicle = candidate
	_hud.call("set_vehicle_action", is_instance_valid(nearby_vehicle), false)


func _can_reach_vehicle(vehicle: CharacterBody2D) -> bool:
	# A proximidade não permite entrar através de um prédio ou outro carro.
	var query := PhysicsRayQueryParameters2D.create(_player.global_position, vehicle.global_position, 5)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == vehicle


func _enter_vehicle(vehicle: CharacterBody2D) -> void:
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
