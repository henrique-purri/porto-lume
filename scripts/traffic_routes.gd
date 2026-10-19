extends RefCounted
## Small directed lane graph over the existing city's streets.
## Intersection IDs use row * 4 + column. A leg travels from one intersection's
## exit, along its right-hand lane, and through the next intersection's curve.
## This module contains map geometry only; agents and population remain separate.

const WORLD_SIZE := Vector2(2400, 1800)
const ROAD_X: Array[int] = [200, 900, 1600, 2300]
const ROAD_Y: Array[int] = [180, 900, 1620]
const ROAD_HALF_WIDTH := 80.0
const LANE_OFFSET := 32.0
const APPROACH_DISTANCE := 96.0
const STRAIGHT_SAMPLE_DISTANCE := 32.0
const CURVE_SAMPLE_DISTANCE := 8.0
const SPAWN_SPACING := 150.0

var _intersections := PackedVector2Array()
var _blocks: Array[Rect2] = []
var _neighbors: Array[PackedInt32Array] = []
var _spawn_candidates: Array[Dictionary] = []


func _init() -> void:
	for y in ROAD_Y:
		for x in ROAD_X:
			_intersections.append(Vector2(x, y))
	for row in range(ROAD_Y.size()):
		for column in range(ROAD_X.size()):
			var adjacent := PackedInt32Array()
			if column > 0:
				adjacent.append(row * ROAD_X.size() + column - 1)
			if column + 1 < ROAD_X.size():
				adjacent.append(row * ROAD_X.size() + column + 1)
			if row > 0:
				adjacent.append((row - 1) * ROAD_X.size() + column)
			if row + 1 < ROAD_Y.size():
				adjacent.append((row + 1) * ROAD_X.size() + column)
			_neighbors.append(adjacent)
	for row in range(2):
		for column in range(3):
			_blocks.append(Rect2(280 + column * 700, 260 + row * 720, 540, 560))
	_build_spawn_candidates()


## Immutable copies prevent population callers from changing the shared graph.
func get_intersections() -> PackedVector2Array:
	return _intersections.duplicate()


func get_center(intersection_id: int) -> Vector2:
	if intersection_id < 0 or intersection_id >= _intersections.size():
		return Vector2.ZERO
	return _intersections[intersection_id]


func get_direction(from_id: int, to_id: int) -> Vector2:
	if not _is_neighbor(from_id, to_id):
		return Vector2.ZERO
	return (get_center(to_id) - get_center(from_id)).normalized()


## Positive margin checks a circular clearance from curbs and world borders.
## Asphalt is the actual drawn map: the world rectangle minus its six blocks.
func is_road_position(point: Vector2, margin: float = 0.0) -> bool:
	var clearance := maxf(margin, 0.0)
	if point.x < clearance or point.y < clearance:
		return false
	if point.x > WORLD_SIZE.x - clearance or point.y > WORLD_SIZE.y - clearance:
		return false
	for block in _blocks:
		if block.has_point(point):
			return false
		if clearance > 0.0:
			var closest := point.clamp(block.position, block.end)
			if point.distance_squared_to(closest) < clearance * clearance:
				return false
	return true


## Each dictionary has from/to graph IDs, lane position and travel direction.
## Spawn points are restricted to straight segments, away from junction curves.
func get_spawn_candidates() -> Array[Dictionary]:
	return _spawn_candidates.duplicate(true)


## No U-turns: edge intersections naturally select their remaining legal turn.
## Straight travel has a small preference, producing calmer urban circulation.
func choose_next(previous_id: int, current_id: int, rng: RandomNumberGenerator) -> int:
	if current_id < 0 or current_id >= _neighbors.size():
		return -1
	var choices := PackedInt32Array()
	var incoming := get_direction(previous_id, current_id)
	for neighbor in _neighbors[current_id]:
		if neighbor == previous_id:
			continue
		choices.append(neighbor)
		if get_direction(current_id, neighbor).dot(incoming) > 0.99:
			choices.append(neighbor)
	if choices.is_empty():
		return -1
	return choices[rng.randi_range(0, choices.size() - 1)]


## Curve tangents match the incoming and outgoing lane directions exactly.
## next_id may only be a legal neighbor of to_id and may not equal from_id.
func build_leg(from_id: int, to_id: int, next_id: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var incoming := get_direction(from_id, to_id)
	var outgoing := get_direction(to_id, next_id)
	if incoming == Vector2.ZERO or outgoing == Vector2.ZERO or next_id == from_id:
		return points
	var center := get_center(to_id)
	var start := get_center(from_id) + incoming * APPROACH_DISTANCE + _right(incoming) * LANE_OFFSET
	var entry := center - incoming * APPROACH_DISTANCE + _right(incoming) * LANE_OFFSET
	var exit := center + outgoing * APPROACH_DISTANCE + _right(outgoing) * LANE_OFFSET
	_append_line(points, start, entry)
	if incoming.dot(outgoing) > 0.99:
		_append_line(points, entry, exit)
	else:
		# Intersect the two cardinal tangent lines to obtain the Bezier control.
		var tangent_distance := (exit - entry).cross(outgoing) / incoming.cross(outgoing)
		var control := entry + incoming * tangent_distance
		var length_bound := entry.distance_to(control) + control.distance_to(exit)
		var sample_count := maxi(2, ceili(length_bound / CURVE_SAMPLE_DISTANCE))
		for index in range(1, sample_count + 1):
			var weight := float(index) / float(sample_count)
			var inverse := 1.0 - weight
			points.append(entry * inverse * inverse + control * 2.0 * inverse * weight + exit * weight * weight)
	return points


func _build_spawn_candidates() -> void:
	for from_id in range(_intersections.size()):
		for to_id in _neighbors[from_id]:
			var direction := get_direction(from_id, to_id)
			var start := get_center(from_id) + direction * APPROACH_DISTANCE + _right(direction) * LANE_OFFSET
			var end := get_center(to_id) - direction * APPROACH_DISTANCE + _right(direction) * LANE_OFFSET
			var count := maxi(1, floori(start.distance_to(end) / SPAWN_SPACING))
			for index in range(count):
				var position := start.lerp(end, float(index + 1) / float(count + 1))
				_spawn_candidates.append({"from": from_id, "to": to_id, "position": position, "direction": direction})


func _append_line(points: PackedVector2Array, start: Vector2, end: Vector2) -> void:
	if points.is_empty():
		points.append(start)
	var sample_count := maxi(1, ceili(start.distance_to(end) / STRAIGHT_SAMPLE_DISTANCE))
	for index in range(1, sample_count + 1):
		points.append(start.lerp(end, float(index) / float(sample_count)))


func _is_neighbor(from_id: int, to_id: int) -> bool:
	return from_id >= 0 and from_id < _neighbors.size() and _neighbors[from_id].has(to_id)


func _right(direction: Vector2) -> Vector2:
	return Vector2(-direction.y, direction.x)
