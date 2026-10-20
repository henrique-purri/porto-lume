extends SceneTree
## Real physics events, dispatch visibility, street pursuit and bounded spawning.
## Run: godot --headless --path . --script res://tests/wanted_test.gd

const POLICE_SCENE := preload("res://vehicles/police_car.tscn")
const TRAFFIC_SCENE := preload("res://vehicles/traffic_car.tscn")
const PEDESTRIAN_SCENE := preload("res://npc/pedestrian.tscn")
const ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]

class OpenTestPaths extends RefCounted:
	func make_path(from: Vector2, _rng: RandomNumberGenerator) -> PackedVector2Array:
		return PackedVector2Array([from + Vector2(160, 0)])


var _main: Node2D
var _player: CharacterBody2D
var _car: CharacterBody2D
var _interaction: Node
var _crime: Node
var _police: Node
var _traffic: Node
var _pedestrians: Node
var _routes: RefCounted
var _fixtures: Array[Node] = []
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 0
	# The headless backend can start with a square native window. Exercise the
	# game's actual landscape configuration before cycling orientation below.
	root.size = Vector2i(1152, 648)
	var scene := load("res://scenes/main.tscn") as PackedScene
	if not _check(scene != null, "the existing scene loads the modular crime and police resources"):
		quit(1)
		return
	_main = scene.instantiate() as Node2D
	_main.get_node("PoliceManager").set("seed_value", 550026)
	_main.get_node("TrafficManager").set("seed_value", 550027)
	_main.get_node("PedestrianManager").set("seed_value", 550028)
	root.add_child(_main)
	_player = _main.get_node("Player") as CharacterBody2D
	_car = _main.get_node("City/Vehicles/ParkedCar") as CharacterBody2D
	_interaction = _main.get_node("VehicleInteraction")
	_crime = _main.get_node("CrimeSystem")
	_police = _main.get_node("PoliceManager")
	_traffic = _main.get_node("TrafficManager")
	_pedestrians = _main.get_node("PedestrianManager")
	_routes = _traffic.get("routes") as RefCounted
	_police.call("set_population_enabled", false)
	_traffic.call("set_population_enabled", false)
	_pedestrians.call("set_population_enabled", false)
	_crime.set_physics_process(false)
	await _steps(3)
	_check_heat_and_decay()
	await _check_wanted_hud()
	await _check_population_and_streaming()
	await _check_physical_crimes()
	await _check_theft()
	await _check_police_routes_and_sight()
	await _check_dispatch_and_escape()
	await _check_foot_and_vehicle_pursuit()
	await _check_combined_performance()
	_release_actions()
	if _failures == 0:
		print("PASS: all Porto Lume wanted and police integration checks")
	else:
		printerr("FAIL: %d wanted/police integration check(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check_heat_and_decay() -> void:
	_crime.call("reset")
	_check(_heat() == 0.0 and _level() == 0 and _crime.get("state") == &"free",
		"zero heat starts free with zero stars")
	_check(not bool(_crime.call("register_crime", &"unknown_crime")) and _heat() == 0.0,
		"unregistered crime names cannot create heat")
	_check(bool(_crime.call("register_crime_type", &"test_one", 1.0)) \
		and bool(_crime.call("register_crime_type", &"test_58", 58.0)) \
		and bool(_crime.call("register_crime_type", &"test_79", 79.0)) \
		and bool(_crime.call("register_crime_type", &"test_max", 500.0)) \
		and not bool(_crime.call("register_crime_type", &"invalid", -1.0)),
		"the crime registry accepts independent severities and rejects invalid definitions")
	_crime.call("register_crime", &"test_one", _player)
	_check(_level() == 1 and _heat() == 1.0, "one heat point raises the first wanted star")
	_crime.call("register_crime", &"test_58")
	_check(_level() == 1 and _heat() == 59.0, "heat below sixty retains only one star")
	_crime.call("register_crime", &"test_one")
	_check(_level() == 2 and _heat() == 60.0, "sixty heat points raise the second star")
	_crime.call("register_crime", &"test_79")
	_check(_level() == 2 and _heat() == 139.0, "heat below one hundred forty retains two stars")
	_crime.call("register_crime", &"test_one")
	_check(_level() == 3 and _heat() == 140.0, "one hundred forty heat points raise the third star")
	_crime.call("register_crime", &"test_max")
	_check(_level() == 3 and _heat() == 240.0, "heat is capped and wanted never exceeds three stars")
	_crime.call("reset")
	var first := bool(_crime.call("register_crime", &"pedestrian_hit", _car, _player))
	var duplicate := bool(_crime.call("register_crime", &"pedestrian_hit", _car, _player))
	var different := bool(_crime.call("register_crime", &"pedestrian_hit", _car, _car))
	_check(first and not duplicate and different and _heat() == 90.0,
		"crime cooldowns prevent repeated victim spam while allowing different victims")
	_crime.call("advance_time", 1.7)
	_check(bool(_crime.call("register_crime", &"pedestrian_hit", _car, _player)) and _heat() == 135.0,
		"a victim cooldown expires using simulation time")
	_crime.call("reset")
	_crime.call("register_crime_type", &"test_140", 140.0)
	_crime.call("register_crime", &"test_140", _player)
	_crime.call("set_police_observation", true, Vector2(900, 900))
	_crime.call("advance_time", 20.0)
	_check(_heat() == 140.0 and _crime.get("state") == &"pursued",
		"confirmed police sight keeps pursuit active and prevents heat decay")
	_crime.call("set_police_observation", false, Vector2(2000, 1500))
	_crime.call("advance_time", 7.0)
	_check(_heat() == 140.0 and _crime.get("state") == &"hidden" \
		and (_crime.get("last_known_position") as Vector2).is_equal_approx(Vector2(900, 900)),
		"hidden status retains wanted and freezes the last sighting during the escape grace period")
	_crime.call("advance_time", 1.5)
	_check(is_equal_approx(_heat(), 137.0) and _level() == 2,
		"heat decays only after the eight-second unseen grace and stars fall progressively")
	_crime.call("advance_time", 13.0)
	_check(is_equal_approx(_heat(), 59.0) and _level() == 1, "continued escape drops the second star")
	_crime.call("advance_time", 10.0)
	_check(_heat() == 0.0 and _level() == 0 and _crime.get("state") == &"free",
		"continued concealment clears heat and returns the player to completely free")
	_crime.call("register_crime", &"vehicle_theft", _car)
	_crime.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_crime.call("advance_time", 100.0)
	var blocked := not bool(_crime.call("register_crime", &"vehicle_theft", _car))
	_check(blocked and _heat() == 65.0, "losing Safari focus pauses heat simulation and crime registration")
	_crime.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_crime.set_physics_process(false)
	_crime.call("reset")


func _check_wanted_hud() -> void:
	var display := _main.get_node("HUD/Controls/WantedDisplay") as Control
	_crime.call("register_crime", &"vehicle_theft", _car)
	_check(int(display.get("wanted_level")) == 2 \
		and display.call("get_status_text") == "ESCONDIDO · PROCURADO",
		"crime signals fill the HUD stars and show hidden-but-wanted status")
	_crime.call("set_police_observation", true, _player.global_position)
	_check(display.call("get_status_text") == "EM PERSEGUIÇÃO",
		"a confirmed sighting updates the HUD to active pursuit")
	_crime.call("set_police_observation", false, _player.global_position)
	_crime.call("advance_time", 20.0)
	_check(int(display.get("wanted_level")) == 0 and display.call("get_status_text") == "LIVRE" \
		and display.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"escaping clears the HUD stars and the status panel never captures touchscreen input")
	var original_size := root.size
	for size: Vector2i in [Vector2i(1152, 648), Vector2i(648, 1152)]:
		root.size = size
		await _steps(3)
		var clear := true
		for name: String in ["Joystick", "VehicleAction", "Accelerator", "Brake"]:
			var control := _main.get_node("HUD/Controls/" + name) as Control
			clear = clear and not display.get_global_rect().intersects(control.get_global_rect())
		_check(clear, "wanted HUD leaves all touch control regions clear in %s" % ("landscape" if size.x > size.y else "portrait"))
	root.size = original_size
	await _steps(3)
	_sync_camera()
	_crime.call("reset")


func _check_population_and_streaming() -> void:
	_police.call("set_population_enabled", true)
	_police.call("refresh_population", true)
	await _steps(2)
	_check(int(_police.call("get_target_count")) == 1 and _police_cars().size() == 1,
		"one patrol vehicle circulates while the player is free")
	_crime.call("register_crime", &"test_one", _player)
	_check(int(_police.call("get_target_count")) == 1, "wanted one requests only one police unit")
	_crime.call("register_crime_type", &"test_59", 59.0)
	_crime.call("register_crime", &"test_59", _player)
	_check(int(_police.call("get_target_count")) == 2, "wanted two requests two police units")
	_crime.call("register_crime", &"test_max", _player)
	_check(int(_police.call("get_target_count")) == 4 \
		and int(_police.get("max_active_police")) == 4, "wanted three has a hard maximum of four police units")
	for _pass in range(6):
		_police.call("refresh_population")
	await _steps(1)
	var excluded := _camera_rect().grow(float(_police.get("spawn_view_margin")))
	var safe := _police_cars().size() == 4
	for car: CharacterBody2D in _police_cars():
		safe = safe and not excluded.has_point(car.global_position) \
			and car.global_position.distance_to(_player.global_position) >= 517.0 \
			and not _overlaps(car, 7) and _on_road(car)
	if not safe:
		print("POLICE SPAWN DIAGNOSTIC: count=%d view=%s focus=%s known=%s" % [_police_cars().size(), excluded, _player.global_position, _crime.get("last_known_position")])
		for car: CharacterBody2D in _police_cars():
			print("POLICE BODY: position=%s overlap=%s road=%s onscreen=%s" % [car.global_position, _overlaps(car, 7), _on_road(car), excluded.has_point(car.global_position)])
	_check(safe, "all four reinforcements spawn outside the actual camera with distance and collision clearance")
	var retained_positions: Array[Vector2] = [Vector2(868, 1040), Vector2(932, 1040), Vector2(868, 1200), Vector2(932, 1200)]
	var unit_index := 0
	for car: CharacterBody2D in _police_cars():
		car.set_physics_process(false)
		car.global_position = retained_positions[unit_index]
		unit_index += 1
	await _steps(2)
	_crime.call("reset")
	_crime.call("register_crime", &"pedestrian_hit", _player, _player)
	_police.call("refresh_population")
	var active_pursuers := 0
	for car: CharacterBody2D in _police_cars():
		active_pursuers += int(int(car.get("pursuit_level")) > 0)
	_check(_police_cars().size() == 4 and active_pursuers == 1,
		"when wanted falls to one star, visible extra units remain present but only one continues pursuing")
	var cars := _police_cars()
	var old_radius := float(_police.get("despawn_radius"))
	_police.set("despawn_radius", 100.0)
	var retained: CharacterBody2D = cars[0]
	retained.set_physics_process(false)
	retained.global_position = _camera_rect().get_center() + Vector2(180, 0)
	await _steps(2)
	_police.call("refresh_population")
	_check(not retained.is_queued_for_deletion() and retained in _police_cars(),
		"visible police remain present even when beyond a despawn threshold")
	_police.set("despawn_radius", old_radius)
	for car: CharacterBody2D in _police_cars():
		car.set_physics_process(false)
		car.global_position = Vector2(20000, 20000)
	cars = _police_cars()
	_police.call("refresh_population")
	var retired := true
	for car: CharacterBody2D in cars:
		retired = retired and car.is_queued_for_deletion() and not car.visible \
			and car.collision_layer == 0 and car.collision_mask == 0
	_check(retired and _police_cars().size() <= 1,
		"distant offscreen police retire safely and replacements are staggered one at a time")
	_police.call("set_population_enabled", false)
	_crime.call("reset")
	_player.global_position = Vector2(200, 180)
	_crime.call("register_crime", &"vehicle_theft", _player)
	var incident: Vector2 = _crime.get("last_known_position")
	# No new sighting or incident accompanies this move into another district.
	_player.global_position = Vector2(1600, 1620)
	await _steps(2)
	_sync_camera()
	_police.call("set_population_enabled", true)
	for _pass in range(5):
		_police.call("refresh_population")
	await _steps(1)
	var dispatched_to_incident := not _police_cars().is_empty()
	for car: CharacterBody2D in _police_cars():
		dispatched_to_incident = dispatched_to_incident \
			and car.global_position.distance_to(incident) <= float(_police.get("dispatch_radius")) + 3.0 \
			and car.global_position.distance_to(_player.global_position) >= 517.0
	_check(dispatched_to_incident and (_crime.get("last_known_position") as Vector2).is_equal_approx(incident),
		"reinforcements remain anchored to the reported incident instead of spawning around an unseen player")
	_police.call("set_population_enabled", false)
	_crime.call("reset")
	await _steps(2)


func _check_physical_crimes() -> void:
	_player.global_position = Vector2(100, 100)
	_car.call("set_driver_active", true)
	_car.global_position = Vector2(900, 835)
	_car.global_rotation = 0.0
	var pedestrian := _spawn_pedestrian(Vector2(900, 780), 560026)
	await _steps(2)
	_car.set("speed", 240.0)
	var fell := false
	for _step in range(18):
		await _steps(1)
		fell = fell or pedestrian.call("get_state_name") == &"fallen"
		if fell:
			break
	_check(fell and _heat() == 45.0 and _level() == 1,
		"a real pedestrian hit by the driven player car generates forty-five heat")
	_car.call("stop")
	await _steps(5)
	_check(_heat() == 45.0, "a fallen pedestrian cannot generate heat on every contact frame")
	_car.call("set_driver_active", false)
	_car.global_position = Vector2(100, 230)
	await _clear_fixtures()
	_crime.call("reset")
	var npc := _spawn_traffic(Vector2(560, 932), 570026)
	pedestrian = _spawn_pedestrian(Vector2(610, 932), 570027)
	npc.set("speed", 240.0)
	await _steps(5)
	_check(pedestrian.call("get_state_name") == &"fallen" and _heat() == 0.0,
		"a real civilian-car pedestrian hit never attributes the NPC's crime to the player")
	await _clear_fixtures()
	var obstacle := _spawn_traffic(Vector2(720, 932), 580026)
	obstacle.set_physics_process(false)
	obstacle.call("stop")
	_car.global_position = Vector2(480, 932)
	_car.global_rotation = PI / 2.0
	_car.call("set_driver_active", true)
	Input.action_press("move_up")
	await _steps(110)
	_check(_heat() == 15.0 and not _overlaps(_car, 4),
		"a real player-car impact against another vehicle generates fifteen heat without overlap")
	_crime.call("advance_time", 2.0)
	await _steps(90)
	_check(_heat() == 15.0, "holding acceleration against the same car does not generate repeated impact crimes")
	_release_actions()
	_car.call("stop")
	_car.global_position = Vector2(480, 932)
	await _steps(3)
	_crime.call("advance_time", 2.0)
	Input.action_press("move_up")
	await _steps(110)
	_check(_heat() == 30.0, "separating and deliberately hitting again registers another vehicle collision")
	_release_actions()
	_car.call("set_driver_active", false)
	await _clear_fixtures()
	_crime.call("reset")
	_car.global_position = Vector2(950, 400)
	_car.global_rotation = PI / 2.0
	_car.call("set_driver_active", true)
	Input.action_press("move_up")
	await _steps(60)
	_check(_heat() == 0.0 and not _overlaps(_car, 1), "hitting a building does not count as hitting a vehicle")
	_release_actions()
	_car.call("set_driver_active", false)
	_car.global_position = Vector2(100, 230)
	await _steps(2)


func _check_theft() -> void:
	_crime.call("reset")
	_car.global_position = Vector2(960, 1110)
	_car.global_rotation = 0.0
	_player.global_position = Vector2(900, 1060)
	await _steps(2)
	var entered := bool(_interaction.call("request_vehicle_action"))
	_check(entered and _interaction.get("current_vehicle") == _car and _heat() == 0.0,
		"entering the original coral car remains legal")
	_check(bool(_interaction.call("request_vehicle_action")), "the existing action still exits the original vehicle safely")
	_car.global_position = Vector2(100, 230)
	var original := _main.get_node("City/Vehicles/ParkedCar2") as StaticBody2D
	var transform := original.global_transform
	_player.global_position = original.global_position + Vector2(-60, 0)
	await _steps(2)
	entered = bool(_interaction.call("request_vehicle_action"))
	var acquired: CharacterBody2D = _interaction.get("current_vehicle") as CharacterBody2D
	_check(entered and is_instance_valid(acquired) and acquired != _car \
		and acquired.global_position.distance_to(transform.origin) < 0.1 \
		and original.is_queued_for_deletion() and _heat() == 65.0 and _level() == 2,
		"entering the other parked car safely transfers control and reports vehicle theft")
	_check(not _player.visible and _main.get_viewport().get_camera_2d().get_parent() == acquired \
		and acquired.is_in_group("player_controlled_vehicle"),
		"the acquired vehicle uses the original hidden-player, camera and controller transfer")
	var exited := bool(_interaction.call("request_vehicle_action"))
	_check(exited and _player.visible and not _overlaps(_player, 13), "exiting an acquired car finds a safe walking position")
	var previous_heat := _heat()
	entered = bool(_interaction.call("request_vehicle_action"))
	_check(entered and _interaction.get("current_vehicle") == acquired and _heat() == previous_heat,
		"re-entering an already acquired car does not charge another theft")
	_interaction.call("request_vehicle_action")
	acquired.queue_free()
	await _steps(2)
	_crime.call("reset")
	_traffic.call("set_population_enabled", true)
	_traffic.call("refresh_population", true)
	await _steps(2)
	var candidates: Array[CharacterBody2D] = _traffic.call("get_vehicles")
	if not _check(not candidates.is_empty(), "civilian traffic remains available for stopped-car acquisition"):
		return
	var civilian: CharacterBody2D = candidates[0]
	civilian.set_physics_process(false)
	civilian.call("stop")
	var old_position := civilian.global_position
	_player.global_position = civilian.to_global(Vector2(-60, 0))
	await _steps(2)
	var before_count := int(_traffic.call("get_active_count"))
	entered = bool(_interaction.call("request_vehicle_action"))
	acquired = _interaction.get("current_vehicle") as CharacterBody2D
	_check(entered and is_instance_valid(acquired) and civilian.is_queued_for_deletion() \
		and int(_traffic.call("get_active_count")) == before_count - 1 \
		and acquired.global_position.distance_to(old_position) < 0.1 and _heat() == 65.0,
		"stealing stopped civilian traffic retires its AI once and reuses the existing driving system")
	_interaction.call("request_vehicle_action")
	if is_instance_valid(acquired):
		acquired.queue_free()
	_traffic.call("set_population_enabled", false)
	_crime.call("reset")
	await _steps(2)


func _check_police_routes_and_sight() -> void:
	_player.global_position = Vector2(100, 100)
	for next_id: int in [1, 6, 9]:
		var car := _spawn_police(4, 5, next_id, Vector2(650, 932), 590026 + next_id)
		var target: Vector2 = _routes.call("get_center", next_id)
		car.call("set_pursuit", target, 1, 0)
		var safe := true
		var advanced := false
		for step in range(420):
			await _steps(1)
			if step % 3 == 0:
				safe = safe and _on_road(car) and not _overlaps(car, 1)
			advanced = advanced or int(car.get("current_from")) == 5
			if advanced:
				break
		_check(safe and advanced and int(car.get("current_to")) == next_id,
			"real police pursue through a %s junction route while keeping their complete body on asphalt"
			% {1: "left-turn", 6: "straight", 9: "right-turn"}[next_id])
		await _clear_fixtures()
	var decisions: Dictionary = {}
	var destinations: Dictionary = {}
	for slot: int in [1, 2, 3]:
		var car := _spawn_police(1, 5, 9, Vector2(868, 600), 600026 + slot)
		car.call("set_pursuit", Vector2(900, 900), 3, slot)
		decisions[int(car.get("current_next"))] = true
		destinations[car.get("intercept_position")] = true
		_check(float(car.get("cruise_speed")) > 205.0, "wanted three increases police pressure above wanted two")
		await _clear_fixtures()
	_check(decisions.size() >= 3 and destinations.size() == 3,
		"wanted-three interception slots distribute units toward different legal junction approaches")
	var block_car := _spawn_police(4, 5, 6, Vector2(500, 932), 605026)
	block_car.set("speed", 205.0)
	block_car.call("set_pursuit", Vector2(430, 932), 2, 1, Vector2(100, 0))
	var blocking := false
	var blocked_safely := true
	for _step in range(110):
		await _steps(1)
		blocking = blocking or block_car.call("get_police_state") == &"blocking"
		blocked_safely = blocked_safely and block_car.global_position.x < 757.1 \
			and _on_road(block_car) and not _overlaps(block_car, 5)
	_check(blocking and blocked_safely and float(block_car.get("speed")) < 2.0,
		"wanted-two interception can brake to a temporary roadblock before the junction without curb intrusion")
	var stopped_at := block_car.global_position
	await _steps(40)
	_check(float(block_car.get("speed")) > 10.0 and block_car.global_position.distance_to(stopped_at) > 8.0,
		"the temporary police roadblock releases itself and resumes street movement")
	block_car.call("set_searching", true)
	_check(block_car.call("get_police_state") == &"searching",
		"losing the sighting cancels active blocking and changes the unit to search")
	await _clear_fixtures()
	var sight_car := _spawn_police(0, 4, 5, Vector2(294, 400), 610026)
	sight_car.set_physics_process(false)
	_player.global_position = Vector2(294, 600)
	await _steps(2)
	_check(bool(sight_car.call("can_see_target", _player)), "a nearby walking player on an open line is visible to police")
	_player.global_position = Vector2(540, 400)
	await _steps(2)
	_check(not bool(sight_car.call("can_see_target", _player)), "buildings block police sight instead of detecting through walls")
	_player.global_position = Vector2(294, 1100)
	await _steps(2)
	_check(not bool(sight_car.call("can_see_target", _player)), "police detection has a bounded distance")
	await _clear_fixtures()


func _check_dispatch_and_escape() -> void:
	_crime.call("reset")
	_player.global_position = Vector2(294, 600)
	_police.call("set_population_enabled", true)
	_police.call("refresh_population")
	await _steps(2)
	var cars := _police_cars()
	if not _check(cars.size() == 1, "the detection fixture uses a real managed patrol unit"):
		return
	var car: CharacterBody2D = cars[0]
	car.global_position = Vector2(294, 400)
	car.set_physics_process(false)
	_crime.call("register_crime", &"pedestrian_hit", _player, _player)
	await _steps(2)
	_police.call("update_observation")
	var known: Vector2 = _crime.get("last_known_position")
	_check(_crime.get("state") == &"pursued" and car.call("get_police_state") == &"pursuing" \
		and known.is_equal_approx(_player.global_position),
		"a real patrol detects and pursues the wanted player on foot")
	_player.global_position = Vector2(540, 400)
	await _steps(2)
	_police.call("update_observation")
	_check(_crime.get("state") == &"hidden" and car.call("get_police_state") == &"searching" \
		and (_crime.get("last_known_position") as Vector2).is_equal_approx(known) \
		and (car.get("last_known_position") as Vector2).is_equal_approx(known),
		"behind a building, dispatch searches the last sighting without tracking the hidden player's real position")
	_crime.call("advance_time", 8.5)
	_check(_heat() < 45.0 and _heat() > 0.0 and _level() == 1,
		"being unseen in the actual police manager begins gradual heat loss")
	_crime.call("advance_time", 8.0)
	_police.call("update_observation")
	_check(_heat() == 0.0 and _crime.get("state") == &"free" and car.call("get_police_state") == &"patrol",
		"escaping real police visibility eventually clears wanted and returns the unit to patrol")
	_police.call("set_population_enabled", false)
	await _steps(2)


func _check_foot_and_vehicle_pursuit() -> void:
	_crime.call("reset")
	_car.global_position = Vector2(960, 1110)
	_car.global_rotation = 0.0
	_player.global_position = Vector2(900, 1100)
	_police.call("set_population_enabled", true)
	_police.call("refresh_population")
	await _steps(2)
	var car: CharacterBody2D = _police_cars()[0]
	car.call("configure", _routes, {"from": 9, "to": 5, "next": 1,
		"position": Vector2(932, 1400), "direction": Vector2.UP}, 620026, 0)
	_crime.call("register_crime", &"pedestrian_hit", _player, _player)
	_police.call("update_observation")
	var start_distance := car.global_position.distance_to(_player.global_position)
	await _steps(60)
	_check(_police.call("get_focus_actor") == _player and _crime.get("state") == &"pursued" \
		and car.global_position.distance_to(_player.global_position) < start_distance - 40.0 and _on_road(car),
		"a moving patrol closes distance to a wanted pedestrian along the road")
	_player.global_position = _car.global_position + Vector2(-60, 0)
	await _steps(2)
	var entered := bool(_interaction.call("request_vehicle_action"))
	_police.call("update_observation")
	_check(entered and _police.call("get_focus_actor") == _car \
		and _crime.get("state") == &"pursued", "entering the player car transfers pursuit to the driven vehicle")
	Input.action_press("move_up")
	await _steps(60)
	_release_actions()
	_car.call("stop")
	_police.call("update_observation")
	_check(car.call("get_police_state") == &"pursuing" and _on_road(car) \
		and not _overlaps(car, 5), "police keep using street routes while chasing the player driving")
	_interaction.call("request_vehicle_action")
	_police.call("set_population_enabled", false)
	_crime.call("reset")
	await _steps(2)


func _check_combined_performance() -> void:
	_car.global_position = Vector2(960, 1110)
	_car.global_rotation = 0.0
	_player.global_position = Vector2(900, 1060)
	await _steps(2)
	_check(bool(_interaction.call("request_vehicle_action")), "the original car remains usable after crime and pursuit scenarios")
	_crime.call("register_crime", &"test_max", _car)
	_sync_camera()
	_police.call("set_population_enabled", true)
	_traffic.call("set_population_enabled", true)
	_pedestrians.call("set_population_enabled", true)
	_pedestrians.call("refresh_population", true)
	_traffic.call("refresh_population", true)
	for _pass in range(6):
		_police.call("refresh_population")
	var initial_slots_clear := true
	var new_vehicles: Array[CharacterBody2D] = _police_cars()
	new_vehicles.append_array(_traffic.call("get_vehicles"))
	for first in range(new_vehicles.size()):
		for second in range(first + 1, new_vehicles.size()):
			initial_slots_clear = initial_slots_clear \
				and new_vehicles[first].global_position.distance_to(new_vehicles[second].global_position) >= 170.0
	_check(initial_slots_clear,
		"police and civilian spawns reserve separate slots before their new physics transforms synchronize")
	await _steps(5)
	_check(_police_cars().size() == 4 and int(_traffic.call("get_active_count")) == 6 \
		and int(_pedestrians.call("get_active_count")) == 10,
		"wanted three supports four police, six traffic vehicles and ten pedestrians together")
	var before: Dictionary = {}
	for car: CharacterBody2D in _police_cars():
		before[car.get_instance_id()] = car.global_position
	var heat_before := _heat()
	_main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _steps(12)
	var paused := is_equal_approx(_heat(), heat_before)
	for car: CharacterBody2D in _police_cars():
		paused = paused and car.global_position.is_equal_approx(before[car.get_instance_id()]) \
			and not car.is_physics_processing() and car.velocity.is_zero_approx()
	_check(paused and _police_cars().size() == 4, "Safari focus loss freezes police, population and wanted simulation")
	_main.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _steps(3)
	var total_ms := 0.0
	var maximum_ms := 0.0
	var samples := 0
	var safe := true
	var bounded := true
	var moving := false
	var reported_violation := false
	for step in range(240):
		await _steps(1)
		var milliseconds := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		if milliseconds > 0.0:
			total_ms += milliseconds
			maximum_ms = maxf(maximum_ms, milliseconds)
			samples += 1
		bounded = bounded and _police_cars().size() <= 4 and int(_traffic.call("get_active_count")) <= 6 \
			and int(_pedestrians.call("get_active_count")) <= 10
		for car: CharacterBody2D in _police_cars():
			moving = moving or float(car.get("speed")) > 10.0
			if step % 6 == 0:
				var on_road := _on_road(car)
				var overlaps := _overlaps(car, 5)
				if (not on_road or overlaps) and not reported_violation:
					reported_violation = true
					var shape := car.get_node("CollisionShape2D") as CollisionShape2D
					var query := PhysicsShapeQueryParameters2D.new()
					query.shape = shape.shape
					query.transform = shape.global_transform
					query.collision_mask = 5
					query.exclude = [car.get_rid()]
					var hits := car.get_world_2d().direct_space_state.intersect_shape(query, 8)
					print("POLICE LIVE DIAGNOSTIC tick=%d body=%s pos=%s rot=%s speed=%s onroad=%s state=%s from=%s to=%s next=%s hits=%s" % [step, car.name, car.global_position, car.global_rotation, car.get("speed"), on_road, car.call("get_police_state"), car.get("current_from"), car.get("current_to"), car.get("current_next"), hits])
					for hit: Dictionary in hits:
						var collider := hit.get("collider") as Node2D
						if is_instance_valid(collider):
							print("POLICE COLLIDER: path=%s pos=%s rot=%s script=%s" % [collider.get_path(), collider.global_position, collider.global_rotation, collider.get_script()])
				safe = safe and on_road and not overlaps
	if not (safe and bounded and moving):
		print("POLICE LIVE FLAGS: safe=%s bounded=%s moving=%s" % [safe, bounded, moving])
	_check(safe and bounded and moving, "maximum live populations move without growth, vehicle overlap or police curb intrusion")
	if samples > 0:
		var average_ms := total_ms / float(samples)
		print("PERFORMANCE wanted: headless Cloud, 4 police + 6 cars + 10 pedestrians, %d physics samples, average %.3f ms, maximum %.3f ms; this is not an iPhone FPS measurement" % [samples, average_ms, maximum_ms])
		_check(average_ms < 16.0, "combined wanted, police, traffic and pedestrian physics remains inside a coarse average regression budget")
	else:
		print("PERFORMANCE wanted: headless backend exposes no physics timing samples; no iPhone FPS claim")
	_check(bool(_interaction.call("request_vehicle_action")) and _player.visible \
		and _police.call("get_focus_actor") == _player, "safe vehicle exit restores walking control and police focus")


func _spawn_pedestrian(position: Vector2, seed_value: int) -> CharacterBody2D:
	var body := PEDESTRIAN_SCENE.instantiate() as CharacterBody2D
	_main.add_child(body)
	body.call("configure", OpenTestPaths.new(), position, seed_value, 2)
	_fixtures.append(body)
	return body


func _spawn_traffic(position: Vector2, seed_value: int) -> CharacterBody2D:
	var body := TRAFFIC_SCENE.instantiate() as CharacterBody2D
	_main.add_child(body)
	body.call("configure", _routes, {"from": 4, "to": 5, "next": 6,
		"position": position, "direction": Vector2.RIGHT}, seed_value, 0)
	body.call("set_traffic_manager", _traffic)
	_fixtures.append(body)
	return body


func _spawn_police(from_id: int, to_id: int, next_id: int, position: Vector2, seed_value: int) -> CharacterBody2D:
	var body := POLICE_SCENE.instantiate() as CharacterBody2D
	_main.add_child(body)
	var direction: Vector2 = _routes.call("get_direction", from_id, to_id)
	body.call("configure", _routes, {"from": from_id, "to": to_id, "next": next_id,
		"position": position, "direction": direction}, seed_value, 0)
	body.call("set_traffic_manager", _traffic)
	_fixtures.append(body)
	return body


func _clear_fixtures() -> void:
	for node: Node in _fixtures:
		if is_instance_valid(node):
			if node.has_method("release_intersection"):
				node.call("release_intersection")
			node.set_physics_process(false)
			node.queue_free()
	_fixtures.clear()
	await _steps(2)


func _heat() -> float:
	return float(_crime.get("heat"))


func _level() -> int:
	return int(_crime.get("wanted_level"))


func _police_cars() -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = _police.call("get_vehicles")
	return result


func _overlaps(body: CharacterBody2D, mask: int) -> bool:
	var collider := body.get_node("CollisionShape2D") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collider.shape
	query.transform = collider.global_transform
	query.collision_mask = mask
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	return not body.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _on_road(body: CharacterBody2D) -> bool:
	var forward := Vector2.UP.rotated(body.global_rotation)
	for offset: float in [-19.0, 0.0, 19.0]:
		if not bool(_routes.call("is_road_position", body.global_position + forward * offset, 21.0)):
			return false
	return true


func _camera_rect() -> Rect2:
	var camera := _main.get_viewport().get_camera_2d()
	var size: Vector2 = _main.get_viewport_rect().size / camera.zoom
	return Rect2(camera.get_screen_center_position() - size * 0.5, size)


func _sync_camera() -> void:
	var camera := _main.get_viewport().get_camera_2d()
	camera.reset_smoothing()
	camera.force_update_scroll()


func _steps(count: int) -> void:
	for _step in range(count):
		await physics_frame
		await process_frame


func _release_actions() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _check(condition: bool, description: String) -> bool:
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		printerr("FAIL: " + description)
	return condition
