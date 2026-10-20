extends RefCounted
## Shared non-blocking pedestrian contacts for player and traffic vehicles.


static func notify(body: CharacterBody2D, collision_shape: CollisionShape2D, previous: Transform2D, delta: float) -> void:
	if not is_instance_valid(body) or not is_instance_valid(collision_shape) or collision_shape.shape == null:
		return
	# Only sweep the movement that survived collision resolution. Never hit a
	# pedestrian through a building where move_and_slide stopped the vehicle.
	var displacement: Vector2 = body.global_position - previous.origin
	var actual_velocity: Vector2 = displacement / maxf(delta, 0.0001)
	if actual_velocity.length_squared() < 36.0:
		return
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.collision_mask = 8
	query.exclude = [body.get_rid()]
	query.collide_with_areas = false
	var contacted: Dictionary = {}
	var steps := clampi(ceili(displacement.length() / 10.0), 1, 4)
	for step in range(steps + 1):
		query.transform = previous.interpolate_with(body.global_transform, float(step) / float(steps)) * collision_shape.transform
		for contact: Dictionary in body.get_world_2d().direct_space_state.intersect_shape(query, 16):
			var pedestrian: Object = contact.get("collider")
			if not is_instance_valid(pedestrian) or not pedestrian.has_method("receive_vehicle_hit"):
				continue
			var identifier := pedestrian.get_instance_id()
			if contacted.has(identifier):
				continue
			contacted[identifier] = true
			var accepted: bool = bool(pedestrian.call("receive_vehicle_hit", actual_velocity, body.global_position))
			if accepted and body.is_in_group("player_controlled_vehicle"):
				var crime_system := body.get_tree().get_first_node_in_group("crime_system")
				if is_instance_valid(crime_system):
					crime_system.call("register_crime", &"pedestrian_hit", body, pedestrian)
