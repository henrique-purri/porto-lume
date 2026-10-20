extends SceneTree
## Integration checks against the actual city, vehicle, camera and touch HUD.
## Run: godot --headless --path . --script res://tests/vehicle_test.gd

const ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]
const OPEN_ROAD := Vector2(900, 900)

var _main: Node2D
var _player: CharacterBody2D
var _car: CharacterBody2D
var _interaction: Node
var _hud: CanvasLayer
var _camera: Camera2D
var _joystick: Control
var _action: Control
var _accelerator: Control
var _brake: Control
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if not _check(scene != null, "existing main scene loads"):
		quit(1)
		return
	_main = scene.instantiate() as Node2D
	root.add_child(_main)
	_main.get_node("CrimeSystem").call("set_enabled", false)
	_main.get_node("PoliceManager").call("set_population_enabled", false)
	# Keep the original driving/exit fixtures free of random NPC blockers.
	# The pedestrian integration suite covers NPC contact and safe exits.
	_main.get_node("PedestrianManager").call("set_population_enabled", false)
	_main.get_node("TrafficManager").call("set_population_enabled", false)
	_player = _main.get_node_or_null("Player") as CharacterBody2D
	_car = _main.get_node_or_null("City/Vehicles/ParkedCar") as CharacterBody2D
	_interaction = _main.get_node_or_null("VehicleInteraction")
	_hud = _main.get_node_or_null("HUD") as CanvasLayer
	_joystick = _main.get_node_or_null("HUD/Controls/Joystick") as Control
	_action = _main.get_node_or_null("HUD/Controls/VehicleAction") as Control
	_accelerator = _main.get_node_or_null("HUD/Controls/Accelerator") as Control
	_brake = _main.get_node_or_null("HUD/Controls/Brake") as Control
	if not _check(_player != null and _car != null and _interaction != null \
		and _hud != null and _joystick != null and _action != null \
		and _accelerator != null and _brake != null,
		"existing player and parked car connect to vehicle interaction and driving HUD"):
		quit(1)
		return
	_camera = _player.get_node("Camera2D") as Camera2D
	await _physics_steps(2)
	await _check_entering_and_proximity()
	if _interaction.get("current_vehicle") != _car:
		quit(1)
		return
	await _check_acceleration_and_coasting()
	await _check_braking_and_reverse()
	await _check_steering()
	await _check_multitouch_and_focus()
	await _check_collisions()
	await _check_exiting()
	_release_actions()
	_hud.call("reset_controls")
	if _failures == 0:
		print("PASS: all Porto Lume vehicle integration checks")
	else:
		printerr("FAIL: %d vehicle integration check(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check_entering_and_proximity() -> void:
	_player.global_position = OPEN_ROAD
	await _physics_steps(2)
	_check(not _action.is_visible_in_tree() \
		and not bool(_interaction.call("request_vehicle_action")),
		"entry action is hidden and refused beyond interaction range")
	_player.global_position = Vector2(900, 1060)
	await _physics_steps(2)
	_check(_action.is_visible_in_tree() \
		and not _accelerator.is_visible_in_tree() and not _brake.is_visible_in_tree(),
		"approaching the original car reveals entry without showing pedals on foot")
	_touch(1, _center(_action), true)
	_check(_interaction.get("current_vehicle") == null,
		"pressing entry waits for touch release")
	_touch(1, _center(_action), false)
	await _physics_steps(2)
	_check(_interaction.get("current_vehicle") == _car and bool(_car.get("driven")) \
		and not _player.visible and not _player.is_physics_processing() \
		and _player.collision_layer == 0 and _player.collision_mask == 0,
		"releasing the real action touch transfers control and disables the pedestrian")
	_check(_camera.get_parent() == _car and _camera.enabled and _camera.ignore_rotation \
		and _camera.position_smoothing_enabled and _car.get("control_source") == _hud,
		"the existing smooth, upright camera follows the driven car")
	_check(_action.is_visible_in_tree() and _accelerator.is_visible_in_tree() \
		and _brake.is_visible_in_tree(), "driving shows exit and independent accelerator/brake controls")


func _check_acceleration_and_coasting() -> void:
	await _prepare_car(OPEN_ROAD)
	var start := _car.global_position
	_touch(10, _center(_accelerator), true)
	await _physics_steps(12)
	var first_speed := _speed()
	await _physics_steps(12)
	var second_speed := _speed()
	_check(first_speed > 20.0 and second_speed > first_speed + 20.0 \
		and _car.global_position.y < start.y - 10.0,
		"holding the touchscreen accelerator progressively increases forward speed")
	_touch(10, _center(_accelerator), false)
	start = _car.global_position
	await _physics_steps(12)
	_check(_speed() > 0.0 and _speed() < second_speed \
		and _car.global_position.y < start.y - 5.0,
		"releasing the accelerator coasts while progressively slowing")
	await _physics_steps(90)
	_check(absf(_speed()) < 0.01 and _car.velocity.is_zero_approx(),
		"coasting eventually stops without any held input")


func _check_braking_and_reverse() -> void:
	await _prepare_car(OPEN_ROAD)
	_touch(20, _center(_accelerator), true)
	await _physics_steps(24)
	_touch(20, _center(_accelerator), false)
	var forward_speed := _speed()
	_touch(21, _center(_brake), true)
	await _physics_steps(6)
	_check(_speed() > 0.0 and _speed() < forward_speed * 0.75,
		"brake first reduces forward speed instead of instantly selecting reverse")
	await _physics_steps(24)
	var start := _car.global_position
	await _physics_steps(8)
	_check(_speed() < -10.0 and _car.global_position.y > start.y + 1.0,
		"continuing to hold brake after stopping drives in reverse")
	_touch(21, _center(_brake), false)


func _check_steering() -> void:
	for direction: float in [-1.0, 1.0]:
		await _prepare_car(OPEN_ROAD)
		var start := _car.global_position
		_touch(30, _center(_accelerator), true)
		_touch(31, _center(_joystick), true)
		_drag(31, _joystick_edge(direction))
		await _physics_steps(24)
		_check(_car.rotation * direction > 0.1 \
			and (_car.global_position.x - start.x) * direction > 0.5 \
			and _speed() > 50.0,
			"simultaneous pedal + %s joystick turns the moving car in that direction"
			% ("left" if direction < 0.0 else "right"))
		_touch(30, _center(_accelerator), false)
		_touch(31, _center(_joystick), false)


func _check_multitouch_and_focus() -> void:
	await _prepare_car(OPEN_ROAD)
	_touch(40, _center(_accelerator), true)
	_touch(41, _center(_joystick), true)
	_drag(41, _joystick_edge(1.0))
	_touch(42, _center(_accelerator), true)
	_touch(42, _center(_accelerator), false)
	await _physics_steps(12)
	_check(bool(_accelerator.call("is_held")) and _speed() > 30.0 \
		and float(_hud.call("get_drive_steering")) > 0.5,
		"an unrelated finger cannot release the held pedal or steering finger")
	_touch(40, _center(_accelerator), false, true)
	_touch(41, _center(_joystick), false, true)
	var speed_before := _speed()
	await _physics_steps(3)
	_check(not bool(_accelerator.call("is_held")) \
		and is_zero_approx(float(_hud.call("get_drive_throttle"))) \
		and is_zero_approx(float(_hud.call("get_drive_steering"))) \
		and _speed() < speed_before,
		"canceled touches release both pedal and joystick without stuck driving input")
	_touch(43, _center(_accelerator), true)
	_drag(43, _center(_accelerator) + Vector2(0, -_accelerator.size.y - 20.0))
	_drag(43, _center(_accelerator))
	_check(not bool(_accelerator.call("is_held")),
		"sliding off a pedal releases it; sliding back does not silently reaccelerate")
	_touch(43, _center(_accelerator), false)
	_touch(44, _center(_accelerator), true)
	_touch(45, _center(_joystick), true)
	_drag(45, _joystick_edge(-1.0))
	Input.action_press("move_up")
	_main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var stopped_at := _car.global_position
	await _physics_steps(3)
	_check(_car.global_position.is_equal_approx(stopped_at) \
		and _car.velocity.is_zero_approx() and is_zero_approx(_speed()) \
		and not bool(_accelerator.call("is_held")) \
		and is_zero_approx(float(_hud.call("get_drive_steering"))) \
		and not Input.is_action_pressed("move_up"),
		"losing browser focus stops the vehicle and clears keyboard and all touch captures")
	_main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_touch(46, _center(_accelerator), true)
	await _physics_steps(8)
	_check(_speed() > 15.0 and not _car.global_position.is_equal_approx(stopped_at),
		"a fresh touch resumes driving after focus returns")
	_touch(46, _center(_accelerator), false)


func _check_collisions() -> void:
	await _prepare_car(Vector2(900, 400), PI * 0.5)
	_touch(50, _center(_accelerator), true)
	await _physics_steps(60)
	_check(_car.global_position.x > 970.0 and _car.global_position.x <= 976.1 \
		and absf(_speed()) < 1.0 and _car.get_slide_collision_count() > 0 \
		and not _body_overlaps_world(_car),
		"accelerating into the building at x=1016 stops the complete car before its wall")
	_touch(50, _center(_accelerator), false)
	await _prepare_car(Vector2(580, 840), PI * 0.5)
	_touch(51, _center(_accelerator), true)
	await _physics_steps(60)
	_check(_car.global_position.x > 655.0 and _car.global_position.x <= 660.1 \
		and absf(_speed()) < 1.0 and _car.get_slide_collision_count() > 0 \
		and not _body_overlaps_world(_car),
		"the remaining parked car is a solid obstacle for the driven car")
	_touch(51, _center(_accelerator), false)
	await _prepare_car(Vector2(994, 440))
	_touch(52, _center(_accelerator), true)
	_touch(53, _center(_joystick), true)
	_drag(53, _joystick_edge(1.0))
	var overlaps := false
	for _step in range(36):
		await _physics_steps(1)
		overlaps = overlaps or _body_overlaps_world(_car)
	_check(not overlaps and _car.global_position.y < 430.0,
		"steering beside a building checks the rotated body every frame without clipping through it")
	_touch(52, _center(_accelerator), false)
	_touch(53, _center(_joystick), false)


func _check_exiting() -> void:
	await _prepare_car(OPEN_ROAD)
	var blockers: Array[StaticBody2D] = []
	# Enclose the car while leaving its own capsule clear. Every door/front/back
	# exit is blocked, so the driver must remain inside instead of teleporting.
	for side: float in [-1.0, 1.0]:
		blockers.append(_blocker(OPEN_ROAD + Vector2(46.0 * side, 0), Vector2(30, 160)))
		blockers.append(_blocker(OPEN_ROAD + Vector2(0, 68.0 * side), Vector2(120, 24)))
	await _physics_steps(2)
	var candidate: Vector2 = _interaction.call("find_safe_exit_position", _car)
	var exited: bool = _interaction.call("request_vehicle_action")
	_check(not candidate.is_finite() and not exited \
		and _interaction.get("current_vehicle") == _car \
		and not _player.visible and _camera.get_parent() == _car,
		"all exits obstructed refuses leaving and keeps driver and camera in the car")
	for blocker in blockers:
		blocker.queue_free()
	await _physics_steps(2)
	await _prepare_car(Vector2(990, 400))
	_touch(60, _center(_action), true)
	_touch(60, _center(_action), false)
	await _physics_steps(2)
	_check(_interaction.get("current_vehicle") == null and not bool(_car.get("driven")) \
		and _player.visible and _player.is_physics_processing() \
		and _player.collision_layer == 2 and _player.collision_mask == 13 \
		and _player.global_position.distance_to(_car.global_position) < 90.0 \
		and not _body_overlaps_world(_player),
		"the same action exits beside a building into a nearby position clear of car and walls")
	_check(_camera.get_parent() == _player and _camera.ignore_rotation \
		and _camera.position_smoothing_enabled and not _accelerator.is_visible_in_tree() \
		and not _brake.is_visible_in_tree(),
		"exiting restores the existing pedestrian camera and walking HUD")
	var start := _player.global_position
	_touch(61, _center(_joystick), true)
	_drag(61, _joystick_edge(-1.0))
	await _physics_steps(8)
	_check(_player.global_position.x < start.x - 20.0 \
		and _car.velocity.is_zero_approx() and is_zero_approx(_speed()),
		"after exiting the joystick moves the pedestrian while the car remains parked")
	_touch(61, _center(_joystick), false)


func _prepare_car(position: Vector2, angle: float = 0.0) -> void:
	_release_actions()
	_hud.call("reset_controls")
	_car.call("stop")
	_car.global_position = position
	_car.global_rotation = angle
	await _physics_steps(2)


func _blocker(position: Vector2, dimensions: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 6
	body.position = position
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = dimensions
	collision.shape = rectangle
	body.add_child(collision)
	_main.add_child(body)
	return body


func _body_overlaps_world(body: CharacterBody2D) -> bool:
	var collision := body.get_node("CollisionShape2D") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.collision_mask = 5
	query.exclude = [body.get_rid()]
	return not body.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _speed() -> float:
	return float(_car.get("speed"))


func _physics_steps(count: int) -> void:
	for _step in range(count):
		await physics_frame
		await process_frame


func _release_actions() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func _joystick_edge(direction: float) -> Vector2:
	var radius: float = _joystick.get("travel_radius")
	return _joystick.get_global_transform_with_canvas() \
		* (_joystick.size * 0.5 + Vector2(direction * radius, 0))


func _touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)


func _drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	root.push_input(event, true)


func _check(condition: bool, description: String) -> bool:
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		printerr("FAIL: " + description)
	return condition
