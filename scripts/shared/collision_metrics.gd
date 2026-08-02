extends RefCounted
class_name CollisionMetrics


static func get_collision_reference_position_from_node(node: Node) -> Vector2:
	if node == null:
		return Vector2.ZERO

	var count := 0
	var sum := Vector2.ZERO

	for child in node.find_children("*", "CollisionShape2D", true, false):
		if not (child is CollisionShape2D):
			continue

		var cs := child as CollisionShape2D
		if cs.disabled or cs.shape == null:
			continue

		sum += cs.global_position
		count += 1

	if count > 0:
		return sum / float(count)

	if node is Node2D:
		return (node as Node2D).global_position

	return Vector2.ZERO


static func compute_edge_distance_pixels(a: Node2D, b: Node2D) -> float:
	var a_center := get_collision_reference_position_from_node(a)
	var b_center := get_collision_reference_position_from_node(b)
	var center_distance := a_center.distance_to(b_center)
	var radius_sum := get_collision_radius_pixels_from_node(a) + get_collision_radius_pixels_from_node(b)
	return maxf(center_distance - radius_sum, 0.0)


static func get_collision_radius_pixels_from_node(node: Node) -> float:
	var origin := _get_node_origin(node)
	var max_radius := 0.0

	for child in node.find_children("*", "CollisionShape2D", true, false):
		if not (child is CollisionShape2D):
			continue

		var cs := child as CollisionShape2D
		if cs.disabled or cs.shape == null:
			continue

		var shape_radius := _shape_radius_pixels(cs.shape)
		shape_radius += origin.distance_to(cs.global_position)
		max_radius = maxf(max_radius, shape_radius)

	for child in node.find_children("*", "CollisionPolygon2D", true, false):
		if not (child is CollisionPolygon2D):
			continue

		var cp := child as CollisionPolygon2D
		if cp.disabled or cp.polygon.is_empty():
			continue

		for point in cp.polygon:
			var world_point := cp.global_transform * point
			max_radius = maxf(max_radius, origin.distance_to(world_point))

	return max_radius


static func get_collision_half_height_pixels_from_node(node: Node) -> float:
	var origin := _get_node_origin(node)
	var max_half_height := 0.0

	for child in node.find_children("*", "CollisionShape2D", true, false):
		if not (child is CollisionShape2D):
			continue

		var cs := child as CollisionShape2D
		if cs.disabled or cs.shape == null:
			continue

		var shape_half_height := _shape_half_height_pixels(cs.shape)
		shape_half_height += absf(cs.global_position.y - origin.y)
		max_half_height = maxf(max_half_height, shape_half_height)

	for child in node.find_children("*", "CollisionPolygon2D", true, false):
		if not (child is CollisionPolygon2D):
			continue

		var cp := child as CollisionPolygon2D
		if cp.disabled or cp.polygon.is_empty():
			continue

		for point in cp.polygon:
			var world_point := cp.global_transform * point
			max_half_height = maxf(max_half_height, absf(world_point.y - origin.y))

	return max_half_height


static func _get_node_origin(node: Node) -> Vector2:
	return get_collision_reference_position_from_node(node)


static func _shape_radius_pixels(shape: Shape2D) -> float:
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.length() * 0.5
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		# Use the farthest distance to center under Godot's end-to-end capsule height.
		return maxf(capsule.radius, capsule.height * 0.5)

	return 0.0


static func _shape_half_height_pixels(shape: Shape2D) -> float:
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.y * 0.5
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		return capsule.height * 0.5

	return 0.0
