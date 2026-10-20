extends SceneTree
## Actual city, pedestrian, vehicle and streaming integration checks.
## Run: godot --headless --path . --script res://tests/pedestrian_test.gd

const PEDESTRIAN_SCENE := "res://npc/pedestrian.tscn"
const MAX_PEDESTRIANS: int = 10

# Deliberately supplies a blocked destination in the isolated collision check.
# The actor must resolve walls even when a future route provider makes a mistake.
class OpenTestPaths extends RefCounted:

	func get_spawn_points() -> PackedVector2Array:
		return PackedVector2Array([Vector2.ZERO])


	func make_path(from: Vector2, _rng: RandomNumberGenerator) -> PackedVector2Array:
		return PackedVector2Array([from + Vector2(180, 0)])


	func is_pedestrian_area(_point: Vector2) -> bool:
		return true


	func get_nearest_point(point: Vector2) -> Vector2:
		return point


var _main: Node2D
var _player: CharacterBody2D
var _car: CharacterBody2D
var _interaction: Node
var _manager: Node
var _paths: RefCounted
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 0
	var scene := load("res://scenes/main.tscn") as PackedScene
	if not _check(scene != null, "existing main scene loads with pedestrian resources"):
		quit(1)
		return
	_main = scene.instantiate() as Node2D
	root.add_child(_main)
	_main.get_node("CrimeSystem").call("set_enabled", false)
	_main.get_node("PoliceManager").call("set_population_enabled", false)
	# Controlled pedestrian fixtures stay independent of random moving traffic.
	# The traffic integration suite exercises both live populations together.
	_main.get_node("TrafficManager").call("set_population_enabled", false)
	_player = _main.get_node_or_null("Player") as CharacterBody2D
	_car = _main.get_node_or_null("City/Vehicles/ParkedCar") as CharacterBody2D
	_interaction = _main.get_node_or_null("VehicleInteraction")
	_manager = _main.get_node_or_null("PedestrianManager")
	if not _check(_manager != null and _player != null and _car != null \
		and _interaction != null, "pedestrians extend the existing player/vehicle composition"):
		quit(1)
		return
	_paths = _manager.get("paths") as RefCounted
	await _physics_steps(3)
	_check_population_and_routes()
	await _check_sidewalk_walking()
	await _check_blocked_destination()
	await _check_vehicle_reactions()
	await _check_population_streaming_and_exit()
	await _check_focus_and_performance()
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)
	if _failures == 0:
		print("PASS: all Porto Lume pedestrian integration checks")
	else:
		printerr("FAIL: %d pedestrian integration check(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check_population_and_routes() -> void:
	var pedestrians := _pedestrians()
	_check(int(_manager.get("max_active_pedestrians")) == MAX_PEDESTRIANS \
		and int(_manager.call("get_active_count")) == MAX_PEDESTRIANS \
		and pedestrians.size() == MAX_PEDESTRIANS,
		"the city starts with exactly ten active pedestrians and a hard limit of ten")
	_check(_manager.call("get_focus_actor") == _player,
		"population follows the walking player before entering a vehicle")
	var spawn_clear := true
	var speeds: Dictionary = {}
	var appearances: Dictionary = {}
	for pedestrian: CharacterBody2D in pedestrians:
		spawn_clear = spawn_clear and not _body_overlaps(pedestrian, 7) \
			and bool(_paths.call("is_pedestrian_area", pedestrian.global_position))
		var speed := float(pedestrian.get("walk_speed"))
		spawn_clear = spawn_clear and speed >= 45.0 and speed <= 72.0 \
			and pedestrian.collision_layer == 8 and pedestrian.collision_mask == 7
		speeds[snappedf(speed, 0.1)] = true
		appearances[int(pedestrian.get("appearance_variant"))] = true
	_check(spawn_clear, "pedestrians spawn on pedestrian areas clear of buildings, player and cars")
	_check(speeds.size() >= 3 and appearances.size() >= 3,
		"the actual population mixes walking speeds and at least three distinct appearances")
	var points: PackedVector2Array = _paths.call("get_spawn_points")
	var rng := RandomNumberGenerator.new()
	rng.seed = 302026
	var valid_paths := not points.is_empty()
	var destinations: Dictionary = {}
	var source: Vector2 = points[0] if not points.is_empty() else Vector2.ZERO
	for _attempt in range(32):
		var route: PackedVector2Array = _paths.call("make_path", source, rng)
		valid_paths = valid_paths and not route.is_empty()
		var previous := source
		for waypoint: Vector2 in route:
			valid_paths = valid_paths and waypoint.distance_to(source) < 800.0
			# Sample between points as well: valid endpoints alone could hide a
			# straight shortcut through a building or across an entire road.
			for sample in range(9):
				var point := previous.lerp(waypoint, float(sample) / 8.0)
				valid_paths = valid_paths and bool(_paths.call("is_pedestrian_area", point))
			previous = waypoint
		if not route.is_empty():
			destinations[route[route.size() - 1]] = true
	_check(valid_paths and destinations.size() >= 3,
		"random nearby destinations produce multiple routes whose complete segments stay on sidewalks")


func _check_sidewalk_walking() -> void:
	var pedestrians := _pedestrians()
	var starts: Dictionary = {}
	var furthest: Dictionary = {}
	for pedestrian: CharacterBody2D in pedestrians:
		starts[pedestrian.get_instance_id()] = pedestrian.global_position
		furthest[pedestrian.get_instance_id()] = 0.0
	var safe_walking := true
	for step in range(120):
		await _physics_steps(1)
		for pedestrian: CharacterBody2D in pedestrians:
			if not is_instance_valid(pedestrian):
				continue
			var id := pedestrian.get_instance_id()
			furthest[id] = maxf(float(furthest[id]),
				pedestrian.global_position.distance_to(starts[id]))
			if step % 6 == 0:
				safe_walking = safe_walking and not _body_overlaps(pedestrian, 1) \
					and bool(_paths.call("is_pedestrian_area", pedestrian.global_position))
	var walking_count := 0
	for distance: float in furthest.values():
		if distance > 12.0:
			walking_count += 1
	_check(safe_walking and walking_count >= 4,
		"multiple real NPCs walk over 120 physics ticks without leaving sidewalks or crossing buildings")


func _check_blocked_destination() -> void:
	var paths := OpenTestPaths.new()
	var pedestrian := _spawn_test_pedestrian(Vector2(5000, 5000), paths, 7401)
	var wall := _blocker(Vector2(5070, 5000), Vector2(20, 180))
	await _physics_steps(2)
	var collision_safe := true
	var attempted_approach := false
	for _step in range(120):
		await _physics_steps(1)
		collision_safe = collision_safe and pedestrian.global_position.x <= 5051.2 \
			and not _body_overlaps(pedestrian, 1)
		attempted_approach = attempted_approach or pedestrian.global_position.x > 5030.0
	_check(collision_safe and attempted_approach,
		"a pedestrian directed at an unexpected solid wall stops or redirects instead of clipping through it")
	pedestrian.queue_free()
	wall.queue_free()
	await _physics_steps(2)


func _check_vehicle_reactions() -> void:
	# Suspend only the manager during controlled fixtures; the real car and
	# isolated NPCs remain active and use the actual physics/hit implementation.
	_manager.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_manager.call("clear_population")
	await _physics_steps(2)
	_player.global_position = _car.global_position + Vector2(-60, 0)
	_check(bool(_interaction.call("request_vehicle_action")),
		"the original parked car still accepts the player before NPC vehicle checks")
	_car.call("stop")
	_car.global_position = Vector2(294, 630)
	_car.global_rotation = 0.0
	var pedestrian := _spawn_test_pedestrian(Vector2(294, 500), _paths, 7402)
	pedestrian.call("set_vehicle_threat", _car)
	await _physics_steps(2)
	var start := pedestrian.global_position
	_car.set("speed", 120.0)
	var observed_fleeing := false
	for _step in range(15):
		await _physics_steps(1)
		observed_fleeing = observed_fleeing \
			or pedestrian.call("get_state_name") == &"fleeing"
	_check(observed_fleeing and pedestrian.global_position.y < start.y - 4.0 \
		and not _body_overlaps(pedestrian, 1),
		"a real approaching driven car makes a sidewalk pedestrian flee away without entering buildings")
	_car.call("stop")
	pedestrian.queue_free()
	await _physics_steps(2)
	# A second fixture starts in the car's actual trajectory. No direct call to
	# receive_vehicle_hit triggers the initial fall: the moving car must detect it.
	_car.global_position = Vector2(900, 835)
	_car.global_rotation = 0.0
	pedestrian = _spawn_test_pedestrian(Vector2(900, 780), OpenTestPaths.new(), 7403)
	await _physics_steps(2)
	start = pedestrian.global_position
	_car.set("speed", 240.0)
	var hit_observed := false
	for _step in range(18):
		await _physics_steps(1)
		if pedestrian.call("get_state_name") == &"fallen":
			hit_observed = true
			break
	_check(hit_observed and pedestrian.collision_mask == 3,
		"the real moving vehicle detects NPC contact and triggers the simple fallen reaction")
	if hit_observed:
		var first_impulse := pedestrian.velocity
		pedestrian.call("receive_vehicle_hit", Vector2(0, 320), pedestrian.global_position - Vector2(0, 30))
		_check(pedestrian.velocity.is_equal_approx(first_impulse),
			"immediate repeated vehicle contact cannot stack knockback during the hit cooldown")
	_car.call("stop")
	_car.global_position = Vector2(900, 1000)
	await _physics_steps(22)
	_check(hit_observed and pedestrian.global_position.distance_to(start) > 10.0 \
		and not _body_overlaps(pedestrian, 1),
		"the fallen pedestrian visibly slides from knockback while retaining solid-world collisions")
	await _physics_steps(78)
	_check(pedestrian.call("get_state_name") != &"fallen" \
		and pedestrian.collision_layer == 8 and pedestrian.collision_mask == 7 \
		and pedestrian.is_physics_processing(),
		"after the simple fall the NPC recovers automatically and resumes its normal simulation")
	pedestrian.queue_free()
	_manager.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _physics_steps(2)


func _check_population_streaming_and_exit() -> void:
	_manager.call("clear_population")
	_car.call("stop")
	_car.global_position = Vector2(2300, 1500)
	_manager.call("refresh_population", true)
	await _physics_steps(2)
	_check(_manager.call("get_focus_actor") == _car \
		and int(_manager.call("get_active_count")) == MAX_PEDESTRIANS,
		"population recenters on the controlled car while the hidden player remains elsewhere")
	var old_pedestrians := _pedestrians()
	for pedestrian: CharacterBody2D in old_pedestrians:
		pedestrian.global_position = Vector2(20000, 20000)
	_manager.call("refresh_population")
	var safely_retired := true
	for pedestrian: CharacterBody2D in old_pedestrians:
		safely_retired = safely_retired and pedestrian.is_queued_for_deletion() \
			and not pedestrian.visible and not pedestrian.is_physics_processing() \
			and pedestrian.collision_layer == 0 and pedestrian.collision_mask == 0
	_check(safely_retired and int(_manager.call("get_active_count")) == 2,
		"far NPCs immediately stop rendering/colliding and one maintenance pass spawns only two replacements")
	for _pass in range(12):
		_manager.call("refresh_population")
	_check(int(_manager.call("get_active_count")) == MAX_PEDESTRIANS,
		"repeated replenishment fills the population without exceeding the ten-NPC cap")
	await _physics_steps(2)
	var pedestrians := _pedestrians()
	var valid_spawn := true
	for pedestrian: CharacterBody2D in pedestrians:
		valid_spawn = valid_spawn and not _body_overlaps(pedestrian, 7) \
			and bool(_paths.call("is_pedestrian_area", pedestrian.global_position)) \
			and pedestrian.global_position.distance_to(_car.global_position) \
				<= float(_manager.get("spawn_radius")) + 5.0
	_check(valid_spawn and pedestrians.size() == MAX_PEDESTRIANS,
		"the regenerated population appears near the driven car on clear pedestrian areas")
	# Occupy the first door candidate with a real NPC. The existing exit system
	# must choose another position, rather than placing the player inside it.
	var door_pedestrian: CharacterBody2D = pedestrians[0]
	door_pedestrian.set_physics_process(false)
	door_pedestrian.velocity = Vector2.ZERO
	door_pedestrian.global_position = _car.to_global(Vector2(-46, 0))
	await _physics_steps(2)
	var candidate: Vector2 = _interaction.call("find_safe_exit_position", _car)
	var exited := bool(_interaction.call("request_vehicle_action"))
	await _physics_steps(2)
	_check(candidate.is_finite() and exited and _player.visible \
		and _interaction.get("current_vehicle") == null \
		and _player.global_position.distance_to(door_pedestrian.global_position) > 21.0 \
		and not _body_overlaps(_player, 13) \
		and _manager.call("get_focus_actor") == _player,
		"exiting avoids an NPC beside the door and safely restores the walking player and population focus")


func _check_focus_and_performance() -> void:
	var positions: Dictionary = {}
	for pedestrian: CharacterBody2D in _pedestrians():
		positions[pedestrian.get_instance_id()] = pedestrian.global_position
	_main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _physics_steps(12)
	var suspended := true
	for pedestrian: CharacterBody2D in _pedestrians():
		suspended = suspended and positions.has(pedestrian.get_instance_id()) \
			and pedestrian.global_position.is_equal_approx(positions[pedestrian.get_instance_id()]) \
			and not pedestrian.is_physics_processing() and pedestrian.velocity.is_zero_approx()
	_check(suspended and _pedestrians().size() == MAX_PEDESTRIANS,
		"losing application focus suspends NPC motion and population maintenance without accumulating actors")
	_main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _physics_steps(20)
	var resumed := true
	for pedestrian: CharacterBody2D in _pedestrians():
		resumed = resumed and pedestrian.is_physics_processing()
	_check(resumed, "returning to Safari resumes every active pedestrian simulation")
	var total_ms := 0.0
	var maximum_ms := 0.0
	var samples := 0
	var bounded := true
	for _step in range(120):
		await _physics_steps(1)
		var milliseconds := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		if milliseconds > 0.0:
			total_ms += milliseconds
			maximum_ms = maxf(maximum_ms, milliseconds)
			samples += 1
		bounded = bounded and int(_manager.call("get_active_count")) <= MAX_PEDESTRIANS \
			and _pedestrians().size() <= MAX_PEDESTRIANS
	_check(bounded and _pedestrians().size() == MAX_PEDESTRIANS,
		"120 more simulation ticks preserve the active cap without population growth")
	if samples > 0:
		var average_ms := total_ms / float(samples)
		print("PERFORMANCE walking: headless Cloud, 10 NPCs, %d physics samples, average %.3f ms, maximum %.3f ms; this is not an iPhone FPS measurement"
			% [samples, average_ms, maximum_ms])
		_check(average_ms < 16.0,
			"headless ten-NPC physics remains below a coarse 16 ms average regression budget")
	else:
		print("PERFORMANCE: this headless backend did not expose physics timing; no iPhone FPS claim")
	await _check_flee_performance()


func _check_flee_performance() -> void:
	# All ten NPCs initially perceive a close, moving/driven car. Keep the car
	# stationary as a controlled threat so path replanning, rather than driving
	# out of range, determines the cost of the initial group fleeing reaction.
	var original_position := _car.global_position
	var original_rotation := _car.global_rotation
	_car.call("set_driver_active", true)
	_car.global_position = Vector2(2300, 1310)
	_car.global_rotation = 0.0
	_car.set_physics_process(false)
	_car.set("speed", 80.0)
	var pedestrians := _pedestrians()
	for index in pedestrians.size():
		var pedestrian := pedestrians[index]
		pedestrian.call("set_simulation_enabled", false)
		pedestrian.global_position = Vector2(2206, 1220 + index * 18)
		pedestrian.call("set_vehicle_threat", _car)
		pedestrian.call("set_simulation_enabled", true)
	var total_ms := 0.0
	var maximum_ms := 0.0
	var samples := 0
	var fleeing_observed: Dictionary = {}
	var bounded := true
	var collision_safe := true
	for step in range(120):
		await _physics_steps(1)
		var milliseconds := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		if milliseconds > 0.0:
			total_ms += milliseconds
			maximum_ms = maxf(maximum_ms, milliseconds)
			samples += 1
		bounded = bounded and _pedestrians().size() == MAX_PEDESTRIANS
		for pedestrian: CharacterBody2D in pedestrians:
			if pedestrian.call("get_state_name") == &"fleeing":
				fleeing_observed[pedestrian.get_instance_id()] = true
			if step % 6 == 0:
				collision_safe = collision_safe and not _body_overlaps(pedestrian, 1)
	_check(bounded and fleeing_observed.size() == MAX_PEDESTRIANS and collision_safe,
		"all ten pedestrians react to the close car while retaining the active cap and world collisions")
	if samples > 0:
		var average_ms := total_ms / float(samples)
		print("PERFORMANCE fleeing: headless Cloud, 10 NPCs, %d physics samples, average %.3f ms, maximum %.3f ms; this is not an iPhone FPS measurement"
			% [samples, average_ms, maximum_ms])
		_check(average_ms < 16.0,
			"headless ten-NPC flee/path-replanning physics remains below a coarse 16 ms average regression budget")
	else:
		print("PERFORMANCE fleeing: this headless backend did not expose physics timing; no iPhone FPS claim")
	_car.call("set_driver_active", false)
	_car.global_position = original_position
	_car.global_rotation = original_rotation


func _spawn_test_pedestrian(position: Vector2, provider: RefCounted, seed_value: int) -> CharacterBody2D:
	var scene := load(PEDESTRIAN_SCENE) as PackedScene
	var pedestrian := scene.instantiate() as CharacterBody2D
	_main.add_child(pedestrian)
	pedestrian.call("configure", provider, position, seed_value, 1)
	return pedestrian


func _blocker(position: Vector2, dimensions: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 14
	body.position = position
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = dimensions
	collision.shape = rectangle
	body.add_child(collision)
	_main.add_child(body)
	return body


func _body_overlaps(body: CharacterBody2D, mask: int) -> bool:
	var collision := body.get_node("CollisionShape2D") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.collision_mask = mask
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	return not body.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _pedestrians() -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = _manager.call("get_pedestrians")
	return result


func _physics_steps(count: int) -> void:
	for _step in range(count):
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> bool:
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		printerr("FAIL: " + description)
	return condition
