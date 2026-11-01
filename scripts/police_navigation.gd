extends RefCounted
## Shared, small emergency-driving grid. Only buildings/borders are baked;
## moving bodies remain real physics obstacles, handled by each car.

const CELL_SIZE: float = 40.0
const CLEARANCE: float = 43.0 # Circumscribes the 80-unit police capsule.

var _grid := AStarGrid2D.new()
var _world: World2D
var _bounds := Rect2()
var _open_cells: Array[Vector2i] = []
var _shape := CircleShape2D.new()
var ready: bool = false


func setup(world: World2D, bounds: Rect2) -> void:
	_world = world
	_bounds = bounds
	_shape.radius = CLEARANCE
	_grid.region = Rect2i(Vector2i.ZERO, Vector2i(ceil(bounds.size / CELL_SIZE)))
	_grid.cell_size = Vector2.ONE * CELL_SIZE
	_grid.offset = bounds.position + Vector2.ONE * CELL_SIZE * 0.5
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()
	_open_cells.clear()
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.collision_mask = 1
	query.collide_with_areas = false
	for y in range(_grid.region.size.y):
		for x in range(_grid.region.size.x):
			var cell := Vector2i(x, y)
			var point := _grid.get_point_position(cell)
			query.transform = Transform2D(0.0, point)
			var solid := not bounds.grow(-CLEARANCE).has_point(point) \
				or not world.direct_space_state.intersect_shape(query, 1).is_empty()
			_grid.set_point_solid(cell, solid)
			if not solid:
				_open_cells.append(cell)
	ready = not _open_cells.is_empty()


func find_path(from: Vector2, destination: Vector2) -> PackedVector2Array:
	if not ready:
		return PackedVector2Array()
	if can_drive_direct(from, destination):
		return PackedVector2Array([destination])
	var start := _nearest_open_cell(from)
	var end := _nearest_open_cell(destination)
	var path := _grid.get_point_path(start, end)
	# Preserve a reachable exact goal, including the original lane position
	# when returning to patrol. No snapping or teleporting to the grid.
	if not path.is_empty() and can_drive_direct(path[path.size() - 1], destination):
		path.append(destination)
	return path


func can_drive_direct(from: Vector2, destination: Vector2) -> bool:
	if not ready or not _bounds.grow(-CLEARANCE).has_point(destination):
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.transform = Transform2D(0.0, from)
	query.collision_mask = 1
	query.collide_with_areas = false
	if not _world.direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	query.motion = destination - from
	var fractions := _world.direct_space_state.cast_motion(query)
	return fractions.size() > 0 and fractions[0] >= 0.9999


func _nearest_open_cell(point: Vector2) -> Vector2i:
	var cell := Vector2i(floor((point - _grid.offset) / CELL_SIZE + Vector2.ONE * 0.5))
	if _grid.is_in_boundsv(cell) and not _grid.is_point_solid(cell):
		return cell
	var nearest := _open_cells[0]
	var distance := INF
	for candidate: Vector2i in _open_cells:
		var candidate_distance := _grid.get_point_position(candidate).distance_squared_to(point)
		if candidate_distance < distance:
			distance = candidate_distance
			nearest = candidate
	return nearest
