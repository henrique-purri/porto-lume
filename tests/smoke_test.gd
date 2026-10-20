extends SceneTree
## Real-scene integration check; no mocks and no wall-clock timing.
## Run: godot --headless --path . --script res://tests/smoke_test.gd

const ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]
const OPEN_INTERSECTION := Vector2(900, 900)

var _main: Node2D
var _player: CharacterBody2D
var _joystick: Control
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if not _check(scene != null, "main scene loads"):
		quit(1)
		return
	_main = scene.instantiate() as Node2D
	root.add_child(_main)
	_main.get_node("CrimeSystem").call("set_enabled", false)
	_main.get_node("PoliceManager").call("set_population_enabled", false)
	# Keep the original movement/collision fixtures free of random NPC blockers.
	# The pedestrian integration suite exercises the populated city separately.
	_main.get_node("PedestrianManager").call("set_population_enabled", false)
	_main.get_node("TrafficManager").call("set_population_enabled", false)
	_player = _main.get_node_or_null("Player") as CharacterBody2D
	_joystick = _main.get_node_or_null("HUD/Controls/Joystick") as Control
	if not _check(_player != null and _joystick != null, "player and real mobile joystick exist"):
		quit(1)
		return
	await _physics_steps(2)
	_check(_player.get("joystick") == _joystick, "main connects joystick to player")
	_check_city_and_spawn()
	_check_camera()
	_check_keyboard_bindings()
	await _check_eight_direction_movement()
	await _check_building_and_boundary_collisions()
	await _check_touch_input()
	_release_actions()
	_joystick.call("reset")
	if _failures == 0:
		print("PASS: all Porto Lume integration checks")
	else:
		printerr("FAIL: %d integration check(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check_city_and_spawn() -> void:
	var buildings := _main.get_node("City/Buildings")
	var footprints_match: bool = buildings.get_child_count() == 18
	for building: Node in buildings.get_children():
		var body := building as StaticBody2D
		if body == null or body.collision_layer != 1 or body.collision_mask != 2:
			footprints_match = false
			continue
		var footprint: Vector2 = body.get("footprint")
		var collision: CollisionShape2D
		for child: Node in body.get_children():
			if child is CollisionShape2D:
				collision = child as CollisionShape2D
				break
		if collision == null or not collision.shape is RectangleShape2D:
			footprints_match = false
			continue
		var rectangle := collision.shape as RectangleShape2D
		footprints_match = footprints_match \
			and rectangle.size.is_equal_approx(footprint) \
			and collision.position.is_equal_approx(footprint / 2.0) \
			and footprint.x >= 150.0 and footprint.y >= 150.0 \
			and not collision.disabled
	_check(footprints_match, "18 buildings have solid colliders matching their visible footprints")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = (_player.get_node("CollisionShape2D") as CollisionShape2D).shape
	query.transform = _player.global_transform
	query.collision_mask = 1
	var overlaps := _player.get_world_2d().direct_space_state.intersect_shape(query)
	_check(overlaps.is_empty(), "player starts clear of buildings and world boundaries")


func _check_camera() -> void:
	var camera := _player.get_node("Camera2D") as Camera2D
	_check(camera.enabled and camera.position_smoothing_enabled \
		and is_equal_approx(camera.position_smoothing_speed, 6.0) \
		and camera.ignore_rotation and camera.zoom == Vector2.ONE \
		and camera.limit_left == 0 and camera.limit_top == 0 \
		and camera.limit_right == 2400 and camera.limit_bottom == 1800,
		"following camera has smoothing, upright rotation and map limits")


func _check_keyboard_bindings() -> void:
	var bindings: Dictionary = {
		KEY_A: &"move_left", KEY_LEFT: &"move_left",
		KEY_D: &"move_right", KEY_RIGHT: &"move_right",
		KEY_W: &"move_up", KEY_UP: &"move_up",
		KEY_S: &"move_down", KEY_DOWN: &"move_down",
	}
	var correct := true
	for physical_key: int in bindings:
		var event := InputEventKey.new()
		event.physical_keycode = physical_key
		event.pressed = true
		for action: StringName in ACTIONS:
			correct = correct and (InputMap.event_is_action(event, action) == (action == bindings[physical_key]))
	_check(correct, "physical WASD and arrow keys map to the correct directions")


func _check_eight_direction_movement() -> void:
	var directions: Array[Vector2] = [
		Vector2.RIGHT, Vector2(1, 1), Vector2.DOWN, Vector2(-1, 1),
		Vector2.LEFT, Vector2(-1, -1), Vector2.UP, Vector2(1, -1),
	]
	var correct: bool = true
	var smallest_distance: float = INF
	var largest_distance: float = 0.0
	var speed: float = _player.get("move_speed")
	for direction: Vector2 in directions:
		await _prepare_at(OPEN_INTERSECTION)
		var start: Vector2 = _player.position
		var start_frame: int = Engine.get_physics_frames()
		_press_direction(direction)
		await _physics_steps(24)
		var displacement: Vector2 = _player.position - start
		var frames: int = Engine.get_physics_frames() - start_frame
		var expected_distance: float = speed * float(frames) / float(Engine.physics_ticks_per_second)
		correct = correct and displacement.length() > 70.0 \
			and displacement.normalized().is_equal_approx(direction.normalized()) \
			and absf(displacement.length() - expected_distance) < 0.15 \
			and absf(_player.velocity.length() - speed) < 0.01
		smallest_distance = minf(smallest_distance, displacement.length())
		largest_distance = maxf(largest_distance, displacement.length())
		_release_actions()
	_check(correct and largest_distance - smallest_distance < 0.15,
		"8 directions travel %.1f–%.1f px in 24 physics ticks at %.0f px/s; diagonal speed is normalized"
		% [smallest_distance, largest_distance, speed])


func _check_building_and_boundary_collisions() -> void:
	await _prepare_at(Vector2(300, 400))
	Input.action_press("move_right")
	await _physics_steps(30)
	_check(_player.position.x > 303.0 and _player.position.x <= 306.05 \
		and absf(_player.position.y - 400.0) < 0.05 \
		and _player.get_slide_collision_count() > 0,
		"walking into building at (316, 300), size (208, 220), stops before x=306")
	await _prepare_at(Vector2(30, 100))
	Input.action_press("move_left")
	await _physics_steps(30)
	_check(_player.position.x >= 9.95 and _player.position.x <= 10.2 \
		and _player.get_slide_collision_count() > 0,
		"world boundary keeps the player's radius inside x >= 10")
	_release_actions()


func _check_touch_input() -> void:
	await _prepare_at(OPEN_INTERSECTION)
	var center: Vector2 = _joystick.size * 0.5
	var radius: float = _joystick.get("travel_radius")
	# This point is in viewport coordinates, so it stays on the free right side.
	var right_side := Vector2(root.get_visible_rect().size.x - 40.0, 400.0)
	_touch(7, right_side, true)
	_drag(7, right_side + Vector2(-30, -30))
	_check(_joystick_direction().is_zero_approx(), "touching the free right side does not activate movement")
	_touch(7, right_side, false)
	_touch(11, _joystick_point(center), true)
	_check(_joystick_direction().is_zero_approx(), "joystick center has a neutral deadzone")
	_drag(11, _joystick_point(center + Vector2.RIGHT * radius))
	var start: Vector2 = _player.position
	await _physics_steps(12)
	_check((_player.position - start).x > 35.0 \
		and absf((_player.position - start).y) < 0.05,
		"real touch press and drag move the player right")
	_touch(27, _joystick_point(center + Vector2.LEFT * radius), true)
	_drag(27, _joystick_point(center + Vector2.UP * radius))
	_touch(27, _joystick_point(center), false)
	_check(_joystick_direction().is_equal_approx(Vector2.RIGHT),
		"a second finger cannot replace or release the captured joystick finger")
	_touch(11, _joystick_point(center), false, true)
	var stopped_at: Vector2 = _player.position
	await _physics_steps(3)
	_check(_joystick_direction().is_zero_approx() \
		and _player.velocity.is_zero_approx() and _player.position.is_equal_approx(stopped_at),
		"canceled touch releases movement without a stuck finger")
	# Verify a diagonal through the full touchscreen-to-player path too.
	_touch(41, _joystick_point(center), true)
	_drag(41, _joystick_point(center + Vector2(1, -1).normalized() * radius))
	start = _player.position
	await _physics_steps(12)
	var diagonal: Vector2 = _player.position - start
	_check(diagonal.length() > 35.0 and diagonal.length() < 45.0 \
		and diagonal.normalized().is_equal_approx(Vector2(1, -1).normalized()),
		"touchscreen diagonal also preserves walking speed")
	Input.action_press("move_left")
	_main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	stopped_at = _player.position
	await _physics_steps(3)
	_check(_joystick_direction().is_zero_approx() \
		and _player.velocity.is_zero_approx() and _player.position.is_equal_approx(stopped_at) \
		and not Input.is_action_pressed("move_left"),
		"losing application focus clears touch, keyboard and movement")
	_main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_touch(42, _joystick_point(center), true)
	_drag(42, _joystick_point(center + Vector2.RIGHT * radius))
	await _physics_steps(6)
	_check(_player.position.x - stopped_at.x > 15.0, "a new finger can move after focus returns")
	_touch(42, _joystick_point(center), false)
	await _physics_steps(2)
	_check(_player.velocity.is_zero_approx(), "normal touch release stops the player")


func _prepare_at(position: Vector2) -> void:
	_release_actions()
	_joystick.call("reset")
	_player.call("reset_motion")
	_player.position = position
	await _physics_steps(2)


func _physics_steps(count: int) -> void:
	for _step in range(count):
		await physics_frame
		# physics_frame emits before node callbacks; process_frame follows them.
		await process_frame


func _press_direction(direction: Vector2) -> void:
	if direction.x < 0.0:
		Input.action_press("move_left")
	elif direction.x > 0.0:
		Input.action_press("move_right")
	if direction.y < 0.0:
		Input.action_press("move_up")
	elif direction.y > 0.0:
		Input.action_press("move_down")


func _release_actions() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _joystick_direction() -> Vector2:
	return _joystick.call("get_direction")


func _joystick_point(local_position: Vector2) -> Vector2:
	return _joystick.get_global_transform_with_canvas() * local_position


func _touch(index: int, viewport_position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = viewport_position
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)


func _drag(index: int, viewport_position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = viewport_position
	root.push_input(event, true)


func _check(condition: bool, description: String) -> bool:
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		printerr("FAIL: " + description)
	return condition
