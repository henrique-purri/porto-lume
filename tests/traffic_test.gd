extends SceneTree
## Real-scene checks for lane routes, queues, physical collisions and streaming.
## Run: godot --headless --path . --script res://tests/traffic_test.gd

const TRAFFIC_SCENE := "res://vehicles/traffic_car.tscn"
const MAX_VEHICLES := 6
const ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]

var _main: Node2D
var _player: CharacterBody2D
var _player_car: CharacterBody2D
var _interaction: Node
var _manager: Node
var _pedestrian_manager: Node
var _routes: RefCounted
var _fixtures: Array[CharacterBody2D] = []
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 0
	var scene := load("res://scenes/main.tscn") as PackedScene
	if not _check(scene != null, "existing city loads with the modular traffic resources"):
		quit(1)
		return
	_main = scene.instantiate() as Node2D
	_main.get_node("TrafficManager").set("seed_value", 420026)
	_main.get_node("PedestrianManager").set("seed_value", 430026)
	root.add_child(_main)
	_player = _main.get_node_or_null("Player") as CharacterBody2D
	_player_car = _main.get_node_or_null("City/Vehicles/ParkedCar") as CharacterBody2D
	_interaction = _main.get_node_or_null("VehicleInteraction")
	_manager = _main.get_node_or_null("TrafficManager")
	_pedestrian_manager = _main.get_node_or_null("PedestrianManager")
	if not _check(_manager != null and _pedestrian_manager != null and _player != null \
		and _player_car != null and _interaction != null,
		"traffic extends the original player, car, touch UI and pedestrian composition"):
		quit(1)
		return
	_routes = _manager.get("routes") as RefCounted
	await _physics_steps(5)
	_check_route_graph()
	_check_initial_population()
	await _check_camera_and_streaming()
	_manager.call("set_population_enabled", false)
	_pedestrian_manager.call("set_population_enabled", false)
	await _physics_steps(2)
	_player.global_position = Vector2(100, 100)
	_player_car.global_position = Vector2(100, 230)
	await _check_real_turns()
	await _check_following_queue()
	await _check_player_vehicle_collision()
	await _check_reservation_guards()
	await _check_crossing_priority()
	await _check_traffic_pedestrian_reaction()
	await _check_live_population_and_performance()
	for action: StringName in ACTIONS:
		Input.action_release(action)
	if _failures == 0:
		print("PASS: all Porto Lume traffic integration checks")
	else:
		printerr("FAIL: %d traffic integration check(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check_route_graph() -> void:
	var centers: PackedVector2Array = _routes.call("get_intersections")
	_check(centers.size() == 12, "lane graph uses the twelve existing street intersections")
	var rng := RandomNumberGenerator.new()
	rng.seed = 440026
	var legal_choices := true
	var safe_hulls := true
	var legs := 0
	var turn_count := 0
	for from_id in centers.size():
		for to_id in centers.size():
			var incoming: Vector2 = _routes.call("get_direction", from_id, to_id)
			if incoming.is_zero_approx():
				continue
			for _attempt in range(16):
				var chosen := int(_routes.call("choose_next", from_id, to_id, rng))
				var outgoing: Vector2 = _routes.call("get_direction", to_id, chosen)
				legal_choices = legal_choices and chosen != from_id and not outgoing.is_zero_approx()
			for next_id in centers.size():
				var outgoing: Vector2 = _routes.call("get_direction", to_id, next_id)
				if outgoing.is_zero_approx() or next_id == from_id:
					continue
				var route: PackedVector2Array = _routes.call("build_leg", from_id, to_id, next_id)
				legs += 1
				turn_count += int(absf(incoming.cross(outgoing)) > 0.5)
				safe_hulls = safe_hulls and route.size() > 2
				for index in range(1, route.size()):
					var direction := route[index] - route[index - 1]
					if direction.is_zero_approx():
						continue
					direction = direction.normalized()
					for sample in range(3):
						var point := route[index - 1].lerp(route[index], float(sample) / 2.0)
						safe_hulls = safe_hulls and _capsule_on_asphalt(point, direction)
	_check(legal_choices and legs >= 60 and turn_count >= 40,
		"all legal directed legs include straight, left and right choices without U-turns")
	_check(safe_hulls,
		"the complete 80 by 42 vehicle hull stays on actual asphalt along every legal lane and curve")
	var candidates: Array = _routes.call("get_spawn_candidates")
	var legal_spawns := candidates.size() >= 50
	for candidate: Dictionary in candidates:
		var direction: Vector2 = _routes.call("get_direction", candidate["from"], candidate["to"])
		legal_spawns = legal_spawns and direction.is_equal_approx(candidate["direction"]) \
			and _capsule_on_asphalt(candidate["position"], direction)
	_check(legal_spawns, "streaming candidates are legal directed straight-lane positions with full-body clearance")


func _check_initial_population() -> void:
	var cars := _vehicles()
	_check(int(_manager.get("max_active_vehicles")) == MAX_VEHICLES \
		and not cars.is_empty() and cars.size() <= MAX_VEHICLES \
		and int(_manager.call("get_active_count")) == cars.size(),
		"traffic starts populated and has a hard default cap of six NPC vehicles")
	_check(_manager.call("get_focus_actor") == _player,
		"traffic streaming initially follows the walking player")
	var speeds: Dictionary = {}
	var acceleration_values: Dictionary = {}
	var appearances: Dictionary = {}
	var safe := true
	var hidden_rect: Rect2 = _manager.call("get_visible_world_rect")
	hidden_rect = hidden_rect.grow(float(_manager.get("spawn_view_margin")))
	for car: CharacterBody2D in cars:
		safe = safe and car.collision_layer == 4 and car.collision_mask & 5 == 5 \
			and not _body_overlaps(car, 7) and not hidden_rect.has_point(car.global_position) \
			and car.global_position.distance_to(_player.global_position) \
				>= float(_manager.get("minimum_spawn_distance")) - 3.0 \
			and _capsule_on_asphalt(car.global_position, Vector2.UP.rotated(car.global_rotation))
		speeds[snappedf(float(car.get("cruise_speed")), 0.1)] = true
		acceleration_values[snappedf(float(car.get("acceleration")), 0.1)] = true
		appearances[int(car.get("appearance_variant"))] = true
	_check(safe, "initial traffic spawns off-camera, away from the player and clear of solid obstacles")
	_check(speeds.size() >= 2 and acceleration_values.size() >= 2 and appearances.size() >= 2,
		"the live population mixes vehicle colors, cruising speeds and acceleration")


func _check_camera_and_streaming() -> void:
	var original_size := root.size
	_manager.call("set_population_enabled", false)
	for size: Vector2i in [Vector2i(1152, 648), Vector2i(648, 1152)]:
		root.size = size
		await _physics_steps(3)
		_sync_camera()
		var camera_rect := _actual_camera_rect()
		var reported: Rect2 = _manager.call("get_visible_world_rect")
		_check(reported.position.distance_to(camera_rect.position) < 0.1 \
			and reported.size.distance_to(camera_rect.size) < 0.1,
			"spawn exclusion follows the actual camera transform in %s orientation"
			% ("landscape" if size.x > size.y else "portrait"))
		_manager.call("set_population_enabled", true)
		_manager.call("refresh_population", true)
		await _physics_steps(1)
		var outside := true
		var excluded := reported.grow(float(_manager.get("spawn_view_margin")))
		for car: CharacterBody2D in _vehicles():
			outside = outside and not excluded.has_point(car.global_position) \
				and car.global_position.distance_to(_player.global_position) \
					>= float(_manager.get("minimum_spawn_distance")) - 3.0
		_check(outside and _vehicles().size() <= MAX_VEHICLES,
			"replenishment never appears inside the expanded %s camera or near the player"
			% ("landscape" if size.x > size.y else "portrait"))
		_manager.call("set_population_enabled", false)
		await _physics_steps(2)
	root.size = original_size
	await _physics_steps(3)
	_sync_camera()
	_manager.call("set_population_enabled", true)
	_manager.call("refresh_population", true)
	await _physics_steps(2)
	var cars := _vehicles()
	var old_radius := float(_manager.get("despawn_radius"))
	_manager.set("despawn_radius", 100.0)
	if not cars.is_empty():
		var retained: CharacterBody2D = cars[0]
		retained.set_physics_process(false)
		retained.global_position = _actual_camera_rect().get_center() + Vector2(180, 0)
		await _physics_steps(1)
		_manager.call("refresh_population")
		_check(not retained.is_queued_for_deletion() and retained in _vehicles(),
			"a distant or excess car still inside the camera is retained instead of visibly disappearing")
	_manager.set("despawn_radius", old_radius)
	_manager.call("clear_population")
	await _physics_steps(2)
	_manager.call("refresh_population", true)
	await _physics_steps(1)
	cars = _vehicles()
	for car: CharacterBody2D in cars:
		car.set_physics_process(false)
		car.global_position = Vector2(20000, 20000)
	_manager.call("refresh_population")
	var retired := not cars.is_empty()
	for car: CharacterBody2D in cars:
		retired = retired and car.is_queued_for_deletion() and not car.visible \
			and not car.is_physics_processing() and car.collision_layer == 0 and car.collision_mask == 0
	_check(retired and _vehicles().size() <= 1,
		"far offscreen cars immediately retire without collisions and one maintenance pass spawns at most one replacement")
	for _pass in range(10):
		_manager.call("refresh_population")
	_check(not _vehicles().is_empty() and _vehicles().size() <= MAX_VEHICLES,
		"bounded replenishment restores local traffic without exceeding its cap")


func _check_real_turns() -> void:
	for next_id: int in [1, 6, 9]:
		var car := _spawn_car(4, 5, next_id, Vector2(650, 932), 450026 + next_id)
		car.set("cruise_speed", 120.0)
		var safe := true
		var advanced := false
		for step in range(420):
			await _physics_steps(1)
			if step % 3 == 0:
				safe = safe and not _body_overlaps(car, 1) \
					and _capsule_on_asphalt(car.global_position, Vector2.UP.rotated(car.global_rotation))
			advanced = advanced or int(car.get("current_from")) == 5
			if advanced:
				break
		_check(safe and advanced and int(car.get("current_to")) == next_id,
			"a real NPC completes the %s intersection route without entering a sidewalk or building"
			% ({1: "left-turn", 6: "straight", 9: "right-turn"}[next_id]))
		await _clear_fixtures()


func _check_following_queue() -> void:
	var lead := _spawn_car(4, 5, 6, Vector2(720, 932), 460026)
	lead.set_physics_process(false)
	lead.call("stop")
	var second := _spawn_car(4, 5, 6, Vector2(540, 932), 460027)
	var third := _spawn_car(4, 5, 6, Vector2(360, 932), 460028)
	var safe := true
	for step in range(330):
		await _physics_steps(1)
		if step % 3 == 0:
			safe = safe and second.global_position.x < lead.global_position.x - 79.0 \
				and third.global_position.x < second.global_position.x - 79.0 \
				and not _body_overlaps(second, 4) and not _body_overlaps(third, 4)
	_check(safe and second.global_position.x > 560.0 and third.global_position.x > 390.0 \
		and float(second.get("speed")) < 3.0 and float(third.get("speed")) < 3.0,
		"three real vehicles form a stopped queue with separation instead of overlapping or crossing the leader")
	var second_start := second.global_position
	var third_start := third.global_position
	lead.set_physics_process(true)
	await _physics_steps(150)
	_check(second.global_position.distance_to(second_start) > 35.0 \
		and third.global_position.distance_to(third_start) > 20.0 \
		and not _body_overlaps(second, 4) and not _body_overlaps(third, 4),
		"queued vehicles progressively resume when the car ahead clears the lane")
	await _clear_fixtures()
	# The unoccupied original player car is a real solid lane obstruction too.
	_player_car.call("stop")
	_player_car.global_position = Vector2(710, 932)
	_player_car.global_rotation = PI * 0.5
	var blocked := _spawn_car(4, 5, 6, Vector2(490, 932), 460029)
	await _physics_steps(240)
	var stopped := blocked.global_position.x > 530.0 \
		and blocked.global_position.x < _player_car.global_position.x - 79.0 \
		and float(blocked.get("speed")) < 3.0 and not _body_overlaps(blocked, 4)
	_check(stopped, "an NPC brakes and waits when the original player vehicle blocks its lane")
	var before := blocked.global_position
	_player_car.global_position = Vector2(100, 230)
	await _physics_steps(90)
	_check(blocked.global_position.distance_to(before) > 35.0 \
		and float(blocked.get("speed")) > 20.0,
		"the blocked NPC resumes its route after the player car moves away")
	await _clear_fixtures()


func _check_player_vehicle_collision() -> void:
	var traffic := _spawn_car(4, 5, 6, Vector2(720, 932), 470026)
	traffic.set_physics_process(false)
	traffic.call("stop")
	_player_car.global_position = Vector2(480, 932)
	_player_car.global_rotation = PI * 0.5
	_player_car.call("set_driver_active", true)
	Input.action_press("move_up")
	var collision_seen := false
	var safe := true
	for _step in range(150):
		await _physics_steps(1)
		collision_seen = collision_seen or _player_car.get_slide_collision_count() > 0
		safe = safe and _player_car.global_position.x <= traffic.global_position.x - 79.0 \
			and not _body_overlaps(_player_car, 4)
	Input.action_release("move_up")
	_check(collision_seen and safe and absf(float(_player_car.get("speed"))) < 1.0,
		"the actual player-controlled car physically stops against an NPC car without tunneling or stored thrust")
	_player_car.call("set_driver_active", false)
	_player_car.global_position = Vector2(100, 230)
	await _clear_fixtures()


func _check_reservation_guards() -> void:
	var lead := _spawn_car(4, 5, 6, Vector2(680, 932), 475026)
	var follower := _spawn_car(4, 5, 6, Vector2(530, 932), 475027)
	await _physics_steps(2)
	var follower_reserved := bool(_manager.call("request_intersection", follower, 5))
	var leader_reserved := bool(_manager.call("request_intersection", lead, 5))
	_check(not follower_reserved and leader_reserved,
		"a follower cannot reserve the junction before its own leader and deadlock the lane")
	await _clear_fixtures()
	var holder := _spawn_car(4, 5, 6, Vector2(900, 932), 475030)
	await _physics_steps(1)
	var acquired := bool(_manager.call("request_intersection", holder, 5))
	holder.set_physics_process(false)
	var waiting := _spawn_car(1, 5, 9, Vector2(868, 680), 475031)
	await _physics_steps(2)
	var passed_paused_owner := bool(_manager.call("request_intersection", waiting, 5))
	_check(acquired and not passed_paused_owner,
		"a paused solid vehicle inside the crossing retains ownership until it clears or is explicitly retired")
	await _clear_fixtures()
	_player_car.global_position = Vector2(1045, 932)
	_player_car.global_rotation = PI * 0.5
	# Commit the obstacle teleport to PhysicsServer before new actors begin
	# their first perception/reservation callbacks.
	await _physics_steps(2)
	var blocked := _spawn_car(4, 5, 6, Vector2(680, 932), 475028)
	var clear_approach := _spawn_car(1, 5, 9, Vector2(868, 680), 475029)
	await _physics_steps(2)
	var blocked_reserved := bool(_manager.call("request_intersection", blocked, 5))
	var clear_reserved := bool(_manager.call("request_intersection", clear_approach, 5))
	if blocked_reserved or not clear_reserved:
		print("RESERVATION DIAGNOSTIC: blocked route granted=%s, clear route granted=%s"
			% [blocked_reserved, clear_reserved])
	_check(not blocked_reserved and clear_reserved,
		"a blocked outbound lane stays outside the crossing while an unrelated clear approach can proceed")
	_player_car.global_position = Vector2(100, 230)
	await _clear_fixtures()


func _check_crossing_priority() -> void:
	var east := _spawn_car(4, 5, 6, Vector2(640, 932), 480026)
	var south := _spawn_car(1, 5, 9, Vector2(868, 640), 480027)
	east.set("cruise_speed", 110.0)
	south.set("cruise_speed", 110.0)
	var crossed_east := false
	var crossed_south := false
	var safe := true
	var waited := false
	var intersection := Rect2(Vector2(790, 790), Vector2(220, 220))
	for step in range(600):
		await _physics_steps(1)
		crossed_east = crossed_east or int(east.get("current_from")) == 5
		crossed_south = crossed_south or int(south.get("current_from")) == 5
		var east_inside := intersection.has_point(east.global_position)
		var south_inside := intersection.has_point(south.global_position)
		safe = safe and not (east_inside and south_inside)
		if step % 3 == 0:
			safe = safe and not _body_overlaps(east, 4) and not _body_overlaps(south, 4)
		waited = waited or ((east_inside and float(south.get("speed")) < 3.0) \
			or (south_inside and float(east.get("speed")) < 3.0))
		if crossed_east and crossed_south:
			break
	_check(safe and waited,
		"conflicting approaches yield before the crossing and never occupy its core simultaneously")
	_check(crossed_east and crossed_south,
		"both real cars make progress after the intersection reservation is released without gridlock")
	await _clear_fixtures()


func _check_traffic_pedestrian_reaction() -> void:
	var traffic := _spawn_car(4, 5, 6, Vector2(560, 932), 485026)
	var pedestrian := (load("res://npc/pedestrian.tscn") as PackedScene).instantiate() as CharacterBody2D
	_main.add_child(pedestrian)
	pedestrian.call("configure", _pedestrian_manager.get("paths"), Vector2(650, 994), 485027, 2)
	var sources: Array[CharacterBody2D] = [traffic]
	pedestrian.call("set_vehicle_sources", sources)
	var fled := false
	var safe := true
	for step in range(90):
		await _physics_steps(1)
		fled = fled or pedestrian.call("get_state_name") == &"fleeing"
		if step % 3 == 0:
			safe = safe and not _body_overlaps(pedestrian, 1)
	_check(fled and safe,
		"a nearby real moving traffic car makes an existing sidewalk pedestrian flee without crossing buildings")
	# The shared source list may briefly retain a car that was culled before
	# the pedestrian manager's next refresh. That stale reference must be safe.
	await _clear_fixtures()
	pedestrian.call("set_simulation_enabled", false)
	pedestrian.global_position = Vector2(650, 994)
	pedestrian.call("set_simulation_enabled", true)
	await _physics_steps(30)
	_check(pedestrian.is_physics_processing() and pedestrian.global_position.is_finite(),
		"pedestrians continue safely when a traffic source is freed before their next perception update")
	pedestrian.queue_free()
	await _physics_steps(2)


func _check_live_population_and_performance() -> void:
	_player_car.call("stop")
	_player_car.global_position = Vector2(960, 1110)
	_player_car.global_rotation = 0.0
	_player.global_position = Vector2(900, 1110)
	await _physics_steps(3)
	_check(bool(_interaction.call("request_vehicle_action")),
		"the original entry action still transfers control to the existing player car")
	_sync_camera()
	_pedestrian_manager.call("set_population_enabled", true)
	_pedestrian_manager.call("refresh_population", true)
	_manager.call("set_population_enabled", true)
	_manager.call("refresh_population", true)
	await _physics_steps(5)
	_check(_manager.call("get_focus_actor") == _player_car \
		and _vehicles().size() == MAX_VEHICLES \
		and int(_pedestrian_manager.call("get_active_count")) == 10,
		"driving centers the full six-vehicle traffic population on the car alongside ten pedestrians")
	var positions: Dictionary = {}
	for car: CharacterBody2D in _vehicles():
		positions[car.get_instance_id()] = car.global_position
	_main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _physics_steps(12)
	var paused := true
	for car: CharacterBody2D in _vehicles():
		paused = paused and positions.has(car.get_instance_id()) \
			and car.global_position.is_equal_approx(positions[car.get_instance_id()]) \
			and not car.is_physics_processing() and car.velocity.is_zero_approx()
	_check(paused and _vehicles().size() == MAX_VEHICLES,
		"losing Safari focus freezes traffic and maintenance without losing or duplicating cars")
	_main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _physics_steps(3)
	var resumed := true
	for car: CharacterBody2D in _vehicles():
		resumed = resumed and car.is_physics_processing()
	_check(resumed, "returning to Safari resumes every active traffic vehicle")
	var total_ms := 0.0
	var maximum_ms := 0.0
	var samples := 0
	var bounded := true
	var safe := true
	var moving := false
	for step in range(240):
		await _physics_steps(1)
		var milliseconds := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		if milliseconds > 0.0:
			total_ms += milliseconds
			maximum_ms = maxf(maximum_ms, milliseconds)
			samples += 1
		bounded = bounded and _vehicles().size() <= MAX_VEHICLES \
			and int(_pedestrian_manager.call("get_active_count")) <= 10
		for car: CharacterBody2D in _vehicles():
			moving = moving or float(car.get("speed")) > 10.0
			if step % 6 == 0:
				safe = safe and not _body_overlaps(car, 5) \
					and _capsule_on_asphalt(car.global_position, Vector2.UP.rotated(car.global_rotation))
	_check(bounded and moving and safe,
		"six live traffic vehicles and ten pedestrians run together without cap growth, vehicle overlap or curb intrusion")
	if samples > 0:
		var average_ms := total_ms / float(samples)
		print("PERFORMANCE traffic: headless Cloud, 6 cars + 10 pedestrians, %d physics samples, average %.3f ms, maximum %.3f ms; this is not an iPhone FPS measurement"
			% [samples, average_ms, maximum_ms])
		_check(average_ms < 16.0,
			"combined traffic and pedestrian physics stays below a coarse 16 ms average regression budget")
	else:
		print("PERFORMANCE traffic: headless backend exposes no physics timing; no iPhone FPS claim")
	_check(bool(_interaction.call("request_vehicle_action")) and _player.visible \
		and _manager.call("get_focus_actor") == _player,
		"the existing exit action restores the walking player and traffic streaming focus")


func _spawn_car(from_id: int, to_id: int, next_id: int, position: Vector2, seed_value: int) -> CharacterBody2D:
	var scene := load(TRAFFIC_SCENE) as PackedScene
	var car := scene.instantiate() as CharacterBody2D
	_main.add_child(car)
	var direction: Vector2 = _routes.call("get_direction", from_id, to_id)
	car.call("configure", _routes, {"from": from_id, "to": to_id, "next": next_id,
		"position": position, "direction": direction}, seed_value, _fixtures.size() % 5)
	car.call("set_traffic_manager", _manager)
	_fixtures.append(car)
	return car


func _clear_fixtures() -> void:
	for car: CharacterBody2D in _fixtures:
		if is_instance_valid(car):
			_manager.call("release_intersection", car, int(car.get("current_to")))
			car.call("set_simulation_enabled", false)
			car.queue_free()
	_fixtures.clear()
	await _physics_steps(2)


func _vehicles() -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = _manager.call("get_vehicles")
	return result


func _capsule_on_asphalt(position: Vector2, direction: Vector2) -> bool:
	# An 80x42 capsule is the union of radius-21 circles along its central
	# 38px segment. Checking both ends plus its center covers the full hull.
	for offset: float in [-19.0, 0.0, 19.0]:
		if not bool(_routes.call("is_road_position", position + direction * offset, 21.0)):
			return false
	return true


func _body_overlaps(body: CharacterBody2D, mask: int) -> bool:
	var shape := body.get_node("CollisionShape2D") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	query.collision_mask = mask
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	return not body.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _actual_camera_rect() -> Rect2:
	var inverse := _main.get_viewport().get_canvas_transform().affine_inverse()
	return inverse * _main.get_viewport_rect()


func _sync_camera() -> void:
	var camera := _main.get_viewport().get_camera_2d()
	if is_instance_valid(camera):
		camera.reset_smoothing()
		camera.force_update_scroll()


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
