extends "res://scripts/entities/controllers/pawn_controller.gd"
class_name AIPawnController

const CollisionMetrics = preload("res://scripts/shared/collision_metrics.gd")

# Explicit target node path. If set and valid, it has priority over group search.
@export var target_path: NodePath
# Fallback target source: nearest Node2D in this group.
@export var target_group: StringName = &"player_pawn"
# Keep this edge-to-edge distance (in game units) from target.
@export var follow_distance := 3.0
# Ignore tiny X deltas to reduce jitter around target center.
@export var horizontal_deadzone := 0.05
# Deadzone for look direction decisions (units). Inside this range keep previous facing.
@export var look_deadzone := 0.2
# If true, brake before changing move direction.
@export var stop_before_turn := true
# Minimum horizontal speed (units/s) required to trigger brake-before-turn.
@export var turn_brake_speed_threshold := 0.08
# Physics mask used by wall/ground ray checks.
@export var collision_mask := 1

@export_group("Platform Checks")
# Stop before edges where no ground is detected.
@export var prevent_edge_fall := true
# Lift edge probe origin above foot level so uphill slopes are still detected as ground.
@export var ground_check_lift := 0.28
# Extra near probe ratio used to avoid false edge detection at slope/flat seams.
@export var ground_check_near_probe_scale := 0.45

@export_group("Jump Decisions")
# Allow jump when a wall is directly ahead.
@export var jump_when_blocked := true

@export_group("Auto Tuning")
# wall_check_distance = pawn.max_speed * this scale.
@export var wall_check_distance_scale := 0.18
# wall_check_height = pawn.jump_height * this scale.
@export var wall_check_height_scale := 0.72
# ground_check_forward = pawn.max_speed * this scale.
@export var ground_check_forward_scale := 0.14
# ground_check_depth = pawn.jump_height * this scale.
@export var ground_check_depth_scale := 1.2
# jump_target_height = pawn.jump_height * this scale.
@export var jump_target_height_scale := 0.6
# jump_cooldown = pawn.jump_time_to_peak * this scale.
@export var jump_cooldown_scale := 0.7

var _jump_cooldown_left := 0.0
var _last_look_axis := 1.0


func build_command(pawn: CharacterBody2D, delta: float) -> Dictionary:
	_jump_cooldown_left = maxf(_jump_cooldown_left - delta, 0.0)

	var target := _resolve_target(pawn)
	if target == null:
		return PawnController.default_command()

	var pawn_center := _get_collision_reference_position(pawn)
	var target_center := _get_collision_reference_position(target)
	var to_target_now := target_center - pawn_center
	var desired_axis := _resolve_look_axis(to_target_now.x)

	var edge_distance_pixels := _compute_edge_distance_pixels(pawn, target)
	var stop_distance_pixels := GameUnits.units_to_pixels(maxf(follow_distance, 0.0))
	if edge_distance_pixels <= stop_distance_pixels:
		return {
			"move_axis": 0.0,
			"look_axis": desired_axis,
			"jump_pressed": false,
		}

	var move_axis := _resolve_turning_axis(pawn, desired_axis)
	var jump_pressed := false

	if not is_zero_approx(move_axis):
		if prevent_edge_fall and _would_step_off_edge(pawn, move_axis):
			move_axis = 0.0
		elif _can_try_jump(pawn):
			if jump_when_blocked and _is_wall_ahead(pawn, move_axis):
				jump_pressed = true
			elif _should_jump_toward_target(pawn, target, move_axis):
				jump_pressed = true

	if jump_pressed:
		_jump_cooldown_left = _get_jump_cooldown(pawn)

	return {
		"move_axis": move_axis,
		"look_axis": desired_axis,
		"jump_pressed": jump_pressed,
	}


func _resolve_look_axis(delta_x_pixels: float) -> float:
	var delta_x_units := GameUnits.pixels_to_units(delta_x_pixels)
	if absf(delta_x_units) > maxf(look_deadzone, horizontal_deadzone):
		_last_look_axis = signf(delta_x_units)

	return _last_look_axis


func _resolve_turning_axis(pawn: CharacterBody2D, desired_axis: float) -> float:
	if not stop_before_turn or is_zero_approx(desired_axis):
		return desired_axis

	var horizontal_speed := GameUnits.pixels_to_units(pawn.velocity.x)
	if is_zero_approx(horizontal_speed):
		return desired_axis

	var moving_opposite := signf(horizontal_speed) != signf(desired_axis)
	var above_threshold := absf(horizontal_speed) > turn_brake_speed_threshold
	if moving_opposite and above_threshold:
		# Hold input for one phase so pawn brakes first, then re-accelerates toward target.
		return 0.0

	return desired_axis


func _can_try_jump(pawn: CharacterBody2D) -> bool:
	if _jump_cooldown_left > 0.0:
		return false

	if not (pawn is Pawn):
		return pawn.is_on_floor()

	var movement_pawn := pawn as Pawn
	if not movement_pawn.jump_enabled:
		return false

	# Single jump keeps legacy behavior: only jump from floor.
	if movement_pawn.max_jump_count <= 1:
		return pawn.is_on_floor()

	# Multi-jump pawns may request jump in air; Pawn validates remaining jumps.
	return true


func _should_jump_toward_target(pawn: CharacterBody2D, target: Node2D, move_axis: float) -> bool:
	if is_zero_approx(move_axis):
		return false
	if _is_target_airborne(target):
		return false

	var pawn_center := _get_collision_reference_position(pawn)
	var target_center := _get_collision_reference_position(target)
	var delta_units := GameUnits.pixels_to_units_v2(target_center - pawn_center)
	var target_above := delta_units.y < -_get_jump_target_height(pawn)
	var target_on_same_side := signf(delta_units.x) == signf(move_axis) and absf(delta_units.x) > horizontal_deadzone
	return target_above and target_on_same_side


func _is_target_airborne(target: Node2D) -> bool:
	if target is CharacterBody2D:
		return not (target as CharacterBody2D).is_on_floor()
	return false


func _is_wall_ahead(pawn: CharacterBody2D, move_axis: float) -> bool:
	if is_zero_approx(move_axis):
		return false

	var ahead_offset := GameUnits.units_to_pixels(_get_wall_check_distance(pawn))
	var half_height := _get_collision_half_height_pixels_from_node(pawn)
	var pawn_center := _get_collision_reference_position(pawn)

	# Probe around shin/chest levels. This avoids false positives from ceilings
	# while still detecting low and mid-height obstacles that require a jump.
	var shin_y := pawn_center.y + half_height * 0.35
	var chest_y := pawn_center.y - half_height * 0.25

	var from_shin := Vector2(pawn_center.x, shin_y)
	var to_shin := from_shin + Vector2(move_axis * ahead_offset, 0.0)
	var shin_hit := _ray_cast(pawn, from_shin, to_shin)
	if _is_blocking_wall_hit(pawn, shin_hit, move_axis):
		return true

	var from_chest := Vector2(pawn_center.x, chest_y)
	var to_chest := from_chest + Vector2(move_axis * ahead_offset, 0.0)
	var chest_hit := _ray_cast(pawn, from_chest, to_chest)
	return _is_blocking_wall_hit(pawn, chest_hit, move_axis)


func _would_step_off_edge(pawn: CharacterBody2D, move_axis: float) -> bool:
	if is_zero_approx(move_axis):
		return false

	var forward := GameUnits.units_to_pixels(_get_ground_check_forward(pawn))
	var depth := GameUnits.units_to_pixels(_get_ground_check_depth(pawn))
	var half_height := _get_collision_half_height_pixels_from_node(pawn)
	var pawn_center := _get_collision_reference_position(pawn)
	var lift := GameUnits.units_to_pixels(maxf(ground_check_lift, 0.0))
	var foot_y := pawn_center.y + half_height
	var near_scale := clampf(ground_check_near_probe_scale, 0.0, 1.0)
	var near_forward := maxf(forward * near_scale, GameUnits.units_to_pixels(horizontal_deadzone))
	var probe_offsets := [forward, near_forward]

	# Start slightly above foot and cast downward further to support uphill/downhill slopes.
	for offset in probe_offsets:
		var from := Vector2(pawn_center.x + move_axis * offset, foot_y - lift)
		var to := from + Vector2(0.0, depth + lift * 2.0)
		var hit := _ray_cast(pawn, from, to)
		if hit.is_empty():
			continue

		var normal: Vector2 = hit.get("normal", Vector2.ZERO)
		if _is_walkable_floor_normal(pawn, normal):
			return false

	return true


func _ray_cast(pawn: CharacterBody2D, from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = collision_mask
	query.exclude = [pawn]
	return pawn.get_world_2d().direct_space_state.intersect_ray(query)


func _is_blocking_wall_hit(pawn: CharacterBody2D, hit: Dictionary, move_axis: float) -> bool:
	if hit.is_empty():
		return false

	var normal: Vector2 = hit.get("normal", Vector2.ZERO)
	if normal == Vector2.ZERO:
		return true
	if _is_walkable_floor_normal(pawn, normal):
		return false

	var threshold := sin(_get_max_walkable_slope_angle(pawn))
	# Treat as wall when slope normal opposes movement beyond pawn's walkable slope limit.
	return normal.x * move_axis <= -threshold


func _is_walkable_floor_normal(pawn: CharacterBody2D, normal: Vector2) -> bool:
	if normal == Vector2.ZERO:
		return false

	var n := normal.normalized()
	var max_angle := _get_max_walkable_slope_angle(pawn)
	var min_up_dot := cos(max_angle)
	# up dot normal = Vector2.UP.dot(normal) = -normal.y
	return -n.y >= min_up_dot


func _get_max_walkable_slope_angle(pawn: CharacterBody2D) -> float:
	return clampf(pawn.floor_max_angle, 0.0, PI * 0.5)


func _get_wall_check_distance(pawn: CharacterBody2D) -> float:
	var movement_pawn := pawn as Pawn
	return maxf(movement_pawn.max_speed * wall_check_distance_scale, horizontal_deadzone)


func _get_wall_check_height(pawn: CharacterBody2D) -> float:
	var movement_pawn := pawn as Pawn
	return maxf(movement_pawn.jump_height * wall_check_height_scale, 0.1)


func _get_ground_check_forward(pawn: CharacterBody2D) -> float:
	var movement_pawn := pawn as Pawn
	return maxf(movement_pawn.max_speed * ground_check_forward_scale, horizontal_deadzone)


func _get_ground_check_depth(pawn: CharacterBody2D) -> float:
	var movement_pawn := pawn as Pawn
	return maxf(movement_pawn.jump_height * ground_check_depth_scale, 0.2)


func _get_jump_target_height(pawn: CharacterBody2D) -> float:
	var movement_pawn := pawn as Pawn
	return maxf(movement_pawn.jump_height * jump_target_height_scale, 0.1)


func _get_jump_cooldown(pawn: CharacterBody2D) -> float:
	var movement_pawn := pawn as Pawn
	return maxf(movement_pawn.jump_time_to_peak * jump_cooldown_scale, 0.05)


func _resolve_target(pawn: CharacterBody2D) -> Node2D:
	var direct_target := _get_target_from_path(pawn)
	if direct_target:
		return direct_target

	return _find_nearest_target_in_group(pawn)


func _get_target_from_path(pawn: CharacterBody2D) -> Node2D:
	if target_path.is_empty():
		return null

	var node := get_node_or_null(target_path)
	if node == pawn:
		return null
	if node is Node2D:
		return node

	return null


func _find_nearest_target_in_group(pawn: CharacterBody2D) -> Node2D:
	if String(target_group).is_empty():
		return null

	var nearest: Node2D
	var best_distance := INF
	var pawn_center := _get_collision_reference_position(pawn)

	for node in get_tree().get_nodes_in_group(target_group):
		if node == pawn:
			continue
		if not (node is Node2D):
			continue

		var target := node as Node2D
		var target_center := _get_collision_reference_position(target)
		var d := pawn_center.distance_squared_to(target_center)
		if d < best_distance:
			best_distance = d
			nearest = target

	return nearest


func _compute_edge_distance_pixels(a: CharacterBody2D, b: Node2D) -> float:
	return CollisionMetrics.compute_edge_distance_pixels(a, b)


func _get_collision_half_height_pixels_from_node(node: Node) -> float:
	return CollisionMetrics.get_collision_half_height_pixels_from_node(node)


func _get_collision_reference_position(node: Node) -> Vector2:
	return CollisionMetrics.get_collision_reference_position_from_node(node)
