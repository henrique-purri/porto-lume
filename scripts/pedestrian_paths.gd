extends RefCounted
## Small immutable sidewalk graph shared by the whole pedestrian population.
## No navigation baking or per-frame path search is needed on mobile browsers.

const BLOCK_SIZE := Vector2(540.0, 560.0)
const WALKER_RADIUS: float = 9.0

var _points := PackedVector2Array()
var _spawn_points := PackedVector2Array()
var _neighbors: Dictionary = {}
var _ring_neighbors: Dictionary = {}
var _buildings: Array[Rect2] = []


func _init() -> void:
	for row in range(2):
		for column in range(3):
			_add_block(Vector2(280 + column * 700, 260 + row * 720))


func _add_block(origin: Vector2) -> void:
	var ring: Array[int] = []
	# Clockwise perimeter, with all four corners included exactly once.
	for step in range(8):
		ring.append(_add_point(origin + Vector2(14 + step * 64, 14)))
	for step in range(8):
		ring.append(_add_point(origin + Vector2(526, 14 + step * 66.5)))
	for step in range(8):
		ring.append(_add_point(origin + Vector2(526 - step * 64, 546)))
	for step in range(8):
		ring.append(_add_point(origin + Vector2(14, 546 - step * 66.5)))
	for index in range(ring.size()):
		var point_id: int = ring[index]
		_connect(point_id, ring[(index + 1) % ring.size()])
		_ring_neighbors[point_id] = [ring[posmod(index - 1, ring.size())], ring[(index + 1) % ring.size()]]
		_spawn_points.append(_points[point_id])
	# The narrow open passage is only a recovery route after knockback. Normal
	# destinations and spawns stay on the sidewalk ring around each block.
	var previous: int = ring[4]
	for passage_y in [82.0, 150.0, 218.0, 286.0, 354.0, 422.0, 490.0]:
		var point_id: int = _add_point(origin + Vector2(270, passage_y))
		_connect(previous, point_id)
		previous = point_id
	_connect(previous, ring[20])
	_buildings.append(Rect2(origin + Vector2(36, 40), Vector2(208, 220)).grow(WALKER_RADIUS))
	_buildings.append(Rect2(origin + Vector2(284, 40), Vector2(220, 366)).grow(WALKER_RADIUS))
	_buildings.append(Rect2(origin + Vector2(36, 326), Vector2(208, 194)).grow(WALKER_RADIUS))


func _add_point(point: Vector2) -> int:
	var point_id: int = _points.size()
	_points.append(point)
	_neighbors[point_id] = []
	return point_id


func _connect(first: int, second: int) -> void:
	_neighbors[first].append(second)
	_neighbors[second].append(first)


func get_spawn_points() -> PackedVector2Array:
	return _spawn_points


func get_nearest_point(point: Vector2) -> Vector2:
	return _points[_find_connection(point)]


func is_pedestrian_area(point: Vector2) -> bool:
	for row in range(2):
		for column in range(3):
			var local: Vector2 = point - Vector2(280 + column * 700, 260 + row * 720)
			if not Rect2(Vector2.ZERO, BLOCK_SIZE).has_point(local):
				continue
			if local.x <= 28.0 or local.x >= 512.0 or local.y <= 28.0 or local.y >= 532.0:
				return true
			if local.x >= 253.0 and local.x <= 275.0:
				return true
	return false


func make_path(from_position: Vector2, rng: RandomNumberGenerator) -> PackedVector2Array:
	return _make_path_from_connection(from_position, rng, _find_connection(from_position))


func _make_path_from_connection(from_position: Vector2, rng: RandomNumberGenerator, connection: int) -> PackedVector2Array:
	var current: int = connection
	var result := PackedVector2Array()
	var needs_connection: bool = from_position.distance_squared_to(_points[current]) > 16.0
	if needs_connection:
		result.append(_points[current])
	var previous: int = -1
	for step in range(rng.randi_range(2, 5)):
		var options: Array = _ring_neighbors.get(current, _neighbors[current]).duplicate()
		if options.size() > 1:
			options.erase(previous)
		var next: int = int(options[rng.randi_range(0, options.size() - 1)])
		result.append(_points[next])
		previous = current
		current = next
	# When starting halfway along an edge, avoid walking back to its nearest
	# endpoint only to reverse immediately. This also lets a fleeing pedestrian
	# turn away from the car at once instead of stepping toward it first.
	if needs_connection and result.size() > 1:
		var first_step: Vector2 = result[0] - from_position
		var second_step: Vector2 = result[1] - result[0]
		if first_step.dot(second_step) < 0.0 and _segment_clear(from_position, result[1]):
			result.remove_at(0)
	return result


func make_flee_path(from_position: Vector2, threat_position: Vector2, rng: RandomNumberGenerator) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_score: float = -INF
	var connection: int = _find_connection(from_position)
	var away: Vector2 = threat_position.direction_to(from_position)
	# A handful of tiny graph routes avoids expensive navigation or collision
	# searches. Resolve the shared start only once for all eight candidates.
	# Every edge is the same safe pavement used during ordinary walks.
	for attempt in range(8):
		var candidate: PackedVector2Array = _make_path_from_connection(from_position, rng, connection)
		if candidate.is_empty():
			continue
		var score: float = candidate[candidate.size() - 1].distance_to(threat_position)
		var first_direction: Vector2 = from_position.direction_to(candidate[0])
		score += first_direction.dot(away) * 160.0
		if score > best_score:
			best_score = score
			best = candidate
	return best


func _find_connection(from_position: Vector2) -> int:
	var closest: int = 0
	var closest_distance: float = INF
	# Almost all walkers are already on a sidewalk edge. Find its nearest node
	# with cheap distances before doing geometry checks against the buildings.
	for index in range(_points.size()):
		var distance: float = from_position.distance_squared_to(_points[index])
		if distance < closest_distance:
			closest = index
			closest_distance = distance
	if _segment_clear(from_position, _points[closest]):
		return closest
	# Knockback can leave a walker behind a corner. Retain the original visible
	# connection search there, so recovery never shortcuts through a building.
	closest = 0
	closest_distance = INF
	for index in range(_points.size()):
		var distance: float = from_position.distance_squared_to(_points[index])
		if distance < closest_distance and _segment_clear(from_position, _points[index]):
			closest = index
			closest_distance = distance
	return closest


func _segment_clear(from: Vector2, to: Vector2) -> bool:
	for building in _buildings:
		if building.has_point(from) or building.has_point(to):
			return false
		var top_left: Vector2 = building.position
		var top_right := Vector2(building.end.x, building.position.y)
		var bottom_right: Vector2 = building.end
		var bottom_left := Vector2(building.position.x, building.end.y)
		if Geometry2D.segment_intersects_segment(from, to, top_left, top_right) != null:
			return false
		if Geometry2D.segment_intersects_segment(from, to, top_right, bottom_right) != null:
			return false
		if Geometry2D.segment_intersects_segment(from, to, bottom_right, bottom_left) != null:
			return false
		if Geometry2D.segment_intersects_segment(from, to, bottom_left, top_left) != null:
			return false
	return true
