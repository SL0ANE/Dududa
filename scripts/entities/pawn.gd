extends CharacterBody2D
class_name Pawn


signal jumped(jump_velocity: float)
signal turned(old_facing: int, new_facing: int)
signal moved(current_velocity: float, input_axis: float, grounded: bool)
signal move_started(current_velocity: float, input_axis: float, grounded: bool)
signal move_active(current_velocity: float, input_axis: float, grounded: bool)
signal move_ended(current_velocity: float, input_axis: float, grounded: bool)
signal landed(impact_velocity: Vector2)
signal wall_hit(collision_normal: Vector2, impact_velocity: Vector2)
signal push_started(other: Pawn, mode: int, direction: float)
signal push_active(other: Pawn, mode: int, direction: float, overlap: float)
signal push_ended(other: Pawn, mode: int)
signal pushed_started(other: Pawn, mode: int, direction: float)
signal pushed_active(other: Pawn, mode: int, direction: float, overlap: float)
signal pushed_ended(other: Pawn, mode: int)


const GameUnits = preload("res://scripts/shared/game_units.gd")
const PAWN_GROUP: StringName = &"pawn"

enum PawnCollisionMode {
	SOFT_PUSH,
	HARD_PUSH,
	SOLID,
	NO_COLLISION,
}

@export_group("Horizontal")
# Maximum horizontal move speed in game units/second.
@export var max_speed := 4.317
# Horizontal acceleration on ground in game units/second^2.
@export var ground_acceleration := 28.0
# Horizontal deceleration on ground when no move input.
@export var ground_deceleration := 32.0
# Horizontal acceleration/deceleration in air.
@export var air_acceleration := 8.0
# Extra multiplier when input direction is opposite current velocity.
@export var turn_acceleration_multiplier := 1.8
# Optional curve shaping horizontal response by speed error ratio [0..1].
@export var speed_change_curve: Curve
# Minimum horizontal speed (units/s) considered as moving for animation/state.
@export var moving_threshold := 0.08

@export_group("Jump")
# Enable active jump input.
@export var jump_enabled := true
# Total jump count allowed before landing (1 = single jump, 2 = double jump).
@export var max_jump_count := 1
# Jump apex height in game units.
@export var jump_height := 1.25
# Time from takeoff to apex in seconds.
@export var jump_time_to_peak := 0.27
# Time from apex to landing speed profile in seconds.
@export var jump_time_to_fall := 0.22
# Allow jump shortly after leaving ground.
@export var coyote_time := 0.1
# Optional curve shaping gravity during rise/fall phase [0..1].
@export var jump_gravity_curve: Curve

@export_group("External Force")
# Horizontal drag applied to external velocity while grounded.
@export var external_drag_ground := 220.0
# Horizontal drag applied to external velocity while airborne.
@export var external_drag_air := 80.0
# Clears downward external Y velocity when grounded.
@export var clear_downward_external_on_ground := true

@export_group("Active Actions")
# Enable active horizontal movement input.
@export var movement_enabled := true

@export_group("Pawn Collision")
# Pawn-to-pawn collision mode:
@export_enum("Soft Push", "Hard Push", "Solid", "NoCollision") var pawn_collision_mode: int = PawnCollisionMode.SOFT_PUSH
# Push intensity (units/s) used as gentle separation velocity.
@export var push_strength := 0.22
# Maximum push impulse added per collision contact (units/s).
@export var push_max_impulse := 0.12
# Extra horizontal contact padding (units). Keep 0 for strict shape-sized contact.
@export var push_contact_padding := 0.0
# Maximum direct horizontal separation applied per frame (units).
@export var push_max_separation_per_frame := 0.06
# Minecraft-like behavior: only apply push when both pawns are grounded.
@export var push_ground_only := true

@export_group("Collision Assist")
# Maximum upward correction in game units per frame.
@export var corner_correction_height := 0.18
# Minimum horizontal probe distance in pixels used by corner correction.
@export var corner_correction_probe_pixels := 1.0
# Snap distance used to keep pawn attached to ground on small downhill steps/slopes.
@export var floor_snap_length_units := 0.2
# Maximum downward driven velocity (units/s) still eligible for manual floor snap.
@export var floor_snap_max_fall_speed := 2.2

@export_group("Nodes")
# Relative path to controller node used to build commands.
@export var controller_path: NodePath
# Relative path to AnimationTree node.
@export var animation_tree_path: NodePath = ^"AnimationTree"
# Optional sprite node path. Empty is allowed for multi-part visuals.
@export var sprite_path: NodePath = ^"AnimatedSprite2D"
# Default art facing direction used to compute flip_h.
@export_enum("Left", "Right") var sprite_default_facing := -1

var _facing := 1

var _controller: PawnController
# Driven velocity is produced by the pawn movement model (input, jump profile).
var _driven_velocity := Vector2.ZERO
# External velocity is produced by gameplay systems (hit, wind, explosion).
# Keep this channel additive so external impulses do not get overwritten by jump logic.
var _external_velocity := Vector2.ZERO
var _air_phase_time := 0.0
var _normalized_air_phase := 0.0
var _was_rising := false
var _coyote_time_left := 0.0
var _jump_count_since_ground := 0
var _last_pawn_collision_mode := -1
var _was_moving := false
var _pushing_prev := {}
var _pushed_prev := {}

# @onready var _animation_tree: AnimationTree = get_node_or_null(animation_tree_path)
@onready var _sprite: AnimatedSprite2D = _resolve_sprite()


func _ready() -> void:
	if not is_in_group(PAWN_GROUP):
		add_to_group(PAWN_GROUP)

	_last_pawn_collision_mode = pawn_collision_mode
	call_deferred("_refresh_all_pawn_collisions")

	_controller = _resolve_controller()
	# if _animation_tree:
		# _animation_tree.active = true

	# _ensure_valid_sprite_animation()


func _physics_process(delta: float) -> void:
	if _last_pawn_collision_mode != pawn_collision_mode:
		_last_pawn_collision_mode = pawn_collision_mode
		call_deferred("_refresh_all_pawn_collisions")

	var was_on_ground := is_on_floor()
	var was_on_wall := is_on_wall()
	if was_on_ground:
		_coyote_time_left = coyote_time
		_jump_count_since_ground = 0
	else:
		_coyote_time_left = maxf(_coyote_time_left - delta, 0.0)

	if was_on_ground:
		_driven_velocity.y = 0.0

	var command := _build_command(delta)
	var move_axis: float = command.get("move_axis", 0.0)
	if not movement_enabled:
		move_axis = 0.0
	var look_axis: float = command.get("look_axis", move_axis)
	var jump_pressed: bool = command.get("jump_pressed", false)
	if not jump_enabled:
		jump_pressed = false

	var jumps_allowed := maxi(max_jump_count, 0)
	var has_jumps_left := _jump_count_since_ground < jumps_allowed
	var can_ground_jump := was_on_ground or _coyote_time_left > 0.0
	var can_jump := has_jumps_left and (can_ground_jump or not was_on_ground)
	if jump_pressed and can_jump:
		var jump_velocity := _compute_jump_velocity()
		_driven_velocity.y = GameUnits.units_to_pixels(jump_velocity)
		_air_phase_time = 0.0
		_was_rising = true
		_coyote_time_left = 0.0
		_jump_count_since_ground += 1
		on_jump(jump_velocity)
		jumped.emit(jump_velocity)

	_apply_vertical_velocity(delta, was_on_ground)
	_apply_horizontal_velocity(move_axis, delta)
	_apply_external_forces(delta)
	_try_corner_correction(move_axis, delta)
	# Merge channels only at the end of the frame.
	velocity = _driven_velocity + _external_velocity
	var pre_slide_velocity := velocity
	move_and_slide()
	_try_floor_snap_after_slide(was_on_ground, jump_pressed)
	_apply_pawn_push_collisions()
	_process_contact_events(was_on_ground, was_on_wall, pre_slide_velocity)
	# Reconcile channels with collision result to avoid drift over time.
	_sync_velocity_components_after_slide()
	_update_animation_state(look_axis)
	var current_velocity := GameUnits.pixels_to_units(velocity.x)
	_process_move_lifecycle(current_velocity, move_axis, is_on_floor())


func _build_command(delta: float) -> Dictionary:
	if _controller:
		return _controller.build_command(self, delta)
	return PawnController.default_command()


func _resolve_controller() -> PawnController:
	if not controller_path.is_empty():
		var node := get_node_or_null(controller_path)
		if node is PawnController:
			return node

	for child in get_children():
		if child is PawnController:
			return child

	return null


func _resolve_sprite() -> AnimatedSprite2D:
	if sprite_path.is_empty():
		return null

	var node := get_node_or_null(sprite_path)
	if node is AnimatedSprite2D:
		return node

	return null


func _apply_horizontal_velocity(move_axis: float, delta: float) -> void:
	move_axis = clampf(move_axis, -1.0, 1.0)
	var max_speed_pixels := GameUnits.units_to_pixels(max_speed)
	var is_grounded := is_on_floor()

	var target_speed := 0.0
	var base_change := air_acceleration

	if not is_zero_approx(move_axis):
		target_speed = move_axis * max_speed_pixels
		base_change = ground_acceleration if is_grounded else air_acceleration
	else:
		base_change = ground_deceleration if is_grounded else air_acceleration

	var speed_error := absf(target_speed - _driven_velocity.x)
	var normalized_error := 0.0
	if max_speed_pixels > 0.0:
		normalized_error = clampf(speed_error / max_speed_pixels, 0.0, 1.0)

	var curve_multiplier := maxf(_sample_curve(speed_change_curve, normalized_error, 1.0), 0.0)
	if not is_zero_approx(move_axis) and signf(move_axis) != signf(_driven_velocity.x) and not is_zero_approx(_driven_velocity.x):
		curve_multiplier *= maxf(turn_acceleration_multiplier, 1.0)

	var change_rate_pixels := GameUnits.units_to_pixels(base_change * curve_multiplier)
	_driven_velocity.x = move_toward(_driven_velocity.x, target_speed, change_rate_pixels * delta)


func _apply_vertical_velocity(delta: float, was_on_ground: bool) -> void:
	if was_on_ground:
		_normalized_air_phase = 0.0
		_air_phase_time = 0.0
		_was_rising = false
		return

	var is_rising := _driven_velocity.y < 0.0
	if is_rising != _was_rising:
		_air_phase_time = 0.0
		_was_rising = is_rising

	_air_phase_time += delta
	var phase_time := jump_time_to_peak if is_rising else jump_time_to_fall
	_normalized_air_phase = clampf(_air_phase_time / maxf(phase_time, 0.001), 0.0, 1.0)

	var gravity := _compute_gravity(is_rising)
	var gravity_curve_multiplier := maxf(_sample_curve(jump_gravity_curve, _normalized_air_phase, 1.0), 0.0)
	_normalized_air_phase = (_normalized_air_phase - 1.0 if is_rising else _normalized_air_phase)
	_driven_velocity.y += GameUnits.units_to_pixels(gravity * gravity_curve_multiplier) * delta


func _apply_external_forces(delta: float) -> void:
	var drag := external_drag_ground if is_on_floor() else external_drag_air
	var drag_pixels := GameUnits.units_to_pixels(maxf(drag, 0.0))
	_external_velocity.x = move_toward(_external_velocity.x, 0.0, drag_pixels * delta)

	# Keep Y drag lower by default so knock-up and knock-down feel impactful.
	_external_velocity.y = move_toward(_external_velocity.y, 0.0, drag_pixels * 0.5 * delta)


func _sync_velocity_components_after_slide() -> void:
	if is_on_floor() and clear_downward_external_on_ground and _external_velocity.y > 0.0:
		_external_velocity.y = 0.0

	_driven_velocity = velocity - _external_velocity


func _update_animation_state(look_axis: float) -> void:
	var old_facing := _facing
	if not is_zero_approx(look_axis):
		_facing = -1 if look_axis < 0.0 else 1
	elif not is_zero_approx(velocity.x):
		_facing = -1 if velocity.x < 0.0 else 1

	if old_facing != _facing:
		on_turn(old_facing, _facing)
		turned.emit(old_facing, _facing)

	if _sprite:
		var clamped_default_facing := -1 if sprite_default_facing < 0 else 1
		_sprite.flip_h = _facing != clamped_default_facing


func _process_contact_events(was_on_ground: bool, was_on_wall: bool, pre_slide_velocity: Vector2) -> void:
	if not was_on_ground and is_on_floor():
		var impact_velocity := GameUnits.pixels_to_units_v2(pre_slide_velocity)
		on_landed(impact_velocity)
		landed.emit(impact_velocity)

	if not was_on_wall and is_on_wall():
		var wall_normal := _get_wall_collision_normal()
		var wall_impact_velocity := GameUnits.pixels_to_units_v2(pre_slide_velocity)
		on_wall_hit(wall_normal, wall_impact_velocity)
		wall_hit.emit(wall_normal, wall_impact_velocity)


func _try_corner_correction(move_axis: float, delta: float) -> void:
	if not is_on_floor():
		return
	if is_zero_approx(move_axis):
		return

	var max_up_px := int(ceil(GameUnits.units_to_pixels(maxf(corner_correction_height, 0.0))))
	if max_up_px <= 0:
		return

	var dir := signf(move_axis)
	var horizontal_px := maxf(absf(velocity.x * delta), corner_correction_probe_pixels)
	var horizontal_probe := Vector2(dir * horizontal_px, 0.0)

	# Only attempt correction if this frame would hit a horizontal obstacle.
	if not test_move(global_transform, horizontal_probe):
		return

	for i in range(1, max_up_px + 1):
		var up := Vector2(0.0, -float(i))
		var elevated := global_transform.translated(up)

		# Require free space at elevated position first.
		if test_move(elevated, Vector2.ZERO):
			continue

		# If elevated position can move horizontally, apply correction.
		if not test_move(elevated, horizontal_probe):
			global_position += up
			return


func _try_floor_snap_after_slide(was_on_ground: bool, jump_pressed: bool) -> void:
	if jump_pressed:
		return
	if is_on_floor():
		return
	if not was_on_ground:
		return
	# Do not re-snap while moving upward (jump, knock-up, moving platforms, etc.).
	if velocity.y < 0.0:
		return
	if _driven_velocity.y < 0.0:
		return
	if _external_velocity.y < 0.0:
		return
	if floor_snap_length_units <= 0.0:
		return

	var max_fall_px := GameUnits.units_to_pixels(maxf(floor_snap_max_fall_speed, 0.0))
	if _driven_velocity.y > max_fall_px:
		return

	# Keep ground contact when descending slopes so locomotion state stays stable.
	var original_floor_snap := self.floor_snap_length
	self.floor_snap_length = GameUnits.units_to_pixels(floor_snap_length_units)
	apply_floor_snap()
	self.floor_snap_length = original_floor_snap


func _get_wall_collision_normal() -> Vector2:
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		if collision and absf(collision.get_normal().x) > 0.5:
			return collision.get_normal()
	return Vector2.ZERO


func _apply_pawn_push_collisions() -> void:
	var pushing_curr := {}
	var pushed_curr := {}

	if pawn_collision_mode != PawnCollisionMode.SOFT_PUSH and pawn_collision_mode != PawnCollisionMode.HARD_PUSH:
		_finalize_push_lifecycle(pushing_curr, pushed_curr)
		return

	if push_ground_only and not is_on_floor():
		_finalize_push_lifecycle(pushing_curr, pushed_curr)
		return

	var my_bounds := _get_collision_bounds_pixels()
	if my_bounds.size == Vector2.ZERO:
		_finalize_push_lifecycle(pushing_curr, pushed_curr)
		return

	for node in get_tree().get_nodes_in_group(PAWN_GROUP):
		if not (node is Pawn):
			continue

		var other := node as Pawn
		if other == self:
			continue
		if get_instance_id() > other.get_instance_id():
			continue
		var pair_mode := _resolve_pair_collision_mode(other)
		if pair_mode != PawnCollisionMode.SOFT_PUSH and pair_mode != PawnCollisionMode.HARD_PUSH:
			continue
		if push_ground_only and (not is_on_floor() or not other.is_on_floor()):
			continue

		my_bounds = _get_collision_bounds_pixels()
		if my_bounds.size == Vector2.ZERO:
			continue

		var other_bounds := other._get_collision_bounds_pixels()
		if other_bounds.size == Vector2.ZERO:
			continue

		var my_min_y := my_bounds.position.y
		var my_max_y := my_bounds.position.y + my_bounds.size.y
		var other_min_y := other_bounds.position.y
		var other_max_y := other_bounds.position.y + other_bounds.size.y
		var overlap_y := minf(my_max_y, other_max_y) - maxf(my_min_y, other_min_y)
		if overlap_y <= 0.0:
			continue

		var my_min_x := my_bounds.position.x
		var my_max_x := my_bounds.position.x + my_bounds.size.x
		var other_min_x := other_bounds.position.x
		var other_max_x := other_bounds.position.x + other_bounds.size.x
		var overlap_x := minf(my_max_x, other_max_x) - maxf(my_min_x, other_min_x)
		var padding_px := GameUnits.units_to_pixels(maxf(push_contact_padding, 0.0))
		var overlap := overlap_x + padding_px
		if overlap <= 0.0:
			continue

		var my_center_x := my_bounds.position.x + my_bounds.size.x * 0.5
		var other_center_x := other_bounds.position.x + other_bounds.size.x * 0.5
		var delta_x := other_center_x - my_center_x

		var push_dir := signf(delta_x)
		if is_zero_approx(push_dir):
			push_dir = signf(velocity.x - other.velocity.x)
		if is_zero_approx(push_dir):
			push_dir = 1.0

		var max_sep_px := GameUnits.units_to_pixels(maxf(push_max_separation_per_frame, 0.0))
		var sep_px := 0.0
		if pair_mode == PawnCollisionMode.HARD_PUSH:
			# Hard push: stronger separation, overlap is quickly resolved.
			sep_px = minf(overlap * 0.5, max_sep_px)
		else:
			# Soft push: light separation so overlapped pawns still drift apart.
			sep_px = minf(overlap * 0.15, max_sep_px * 0.35)

		if sep_px > 0.0:
			global_position.x -= push_dir * sep_px
			other.global_position.x += push_dir * sep_px

		var overlap_units := GameUnits.pixels_to_units(overlap)
		var impulse := clampf(push_strength + overlap_units * 0.1, 0.0, push_max_impulse)
		add_external_impulse(Vector2(-push_dir * impulse, 0.0))
		other.add_external_impulse(Vector2(push_dir * impulse, 0.0))

		_register_push_contact(pushing_curr, other, pair_mode, push_dir, overlap_units)
		_register_pushed_contact(pushed_curr, other, pair_mode, -push_dir, overlap_units)

	_finalize_push_lifecycle(pushing_curr, pushed_curr)


func _get_collision_bounds_pixels() -> Rect2:
	var has_shape := false
	var min_x := 0.0
	var max_x := 0.0
	var min_y := 0.0
	var max_y := 0.0

	for child in find_children("*", "CollisionShape2D", true, false):
		if not (child is CollisionShape2D):
			continue

		var cs := child as CollisionShape2D
		if cs.disabled or cs.shape == null:
			continue

		var center := cs.global_position
		var half_extents := _shape_half_extents_pixels(cs.shape)
		if half_extents == Vector2.ZERO:
			continue

		var shape_min_x := center.x - half_extents.x
		var shape_max_x := center.x + half_extents.x
		var shape_min_y := center.y - half_extents.y
		var shape_max_y := center.y + half_extents.y

		if not has_shape:
			min_x = shape_min_x
			max_x = shape_max_x
			min_y = shape_min_y
			max_y = shape_max_y
			has_shape = true
			continue

		min_x = minf(min_x, shape_min_x)
		max_x = maxf(max_x, shape_max_x)
		min_y = minf(min_y, shape_min_y)
		max_y = maxf(max_y, shape_max_y)

	if not has_shape:
		return Rect2(global_position, Vector2.ZERO)

	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


func _process_move_lifecycle(current_velocity: float, input_axis: float, grounded: bool) -> void:
	var is_moving_now := absf(current_velocity) > moving_threshold

	if is_moving_now and not _was_moving:
		on_move_started(current_velocity, input_axis, grounded)
		move_started.emit(current_velocity, input_axis, grounded)

	if is_moving_now:
		# Keep active updates in air too, so animation/state machines can react continuously.
		on_move_active(current_velocity, input_axis, grounded)
		move_active.emit(current_velocity, input_axis, grounded)
		# Legacy compatibility.
		on_move(current_velocity, input_axis, grounded)
		moved.emit(current_velocity, input_axis, grounded)

	if not is_moving_now and _was_moving:
		on_move_ended(current_velocity, input_axis, grounded)
		move_ended.emit(current_velocity, input_axis, grounded)

	_was_moving = is_moving_now


func _register_push_contact(curr: Dictionary, other: Pawn, mode: int, direction: float, overlap: float) -> void:
	curr[other.get_instance_id()] = {
		"other": other,
		"mode": mode,
		"direction": direction,
		"overlap": overlap,
	}


func _register_pushed_contact(curr: Dictionary, other: Pawn, mode: int, direction: float, overlap: float) -> void:
	curr[other.get_instance_id()] = {
		"other": other,
		"mode": mode,
		"direction": direction,
		"overlap": overlap,
	}


func _finalize_push_lifecycle(pushing_curr: Dictionary, pushed_curr: Dictionary) -> void:
	for key in pushing_curr.keys():
		var data: Dictionary = pushing_curr[key]
		var other := data["other"] as Pawn
		var mode := int(data["mode"])
		var direction := float(data["direction"])
		var overlap := float(data["overlap"])

		if not _pushing_prev.has(key):
			on_push_started(other, mode, direction)
			push_started.emit(other, mode, direction)

		on_push_active(other, mode, direction, overlap)
		push_active.emit(other, mode, direction, overlap)

	for key in _pushing_prev.keys():
		if pushing_curr.has(key):
			continue
		var prev: Dictionary = _pushing_prev[key]
		var prev_other := prev["other"] as Pawn
		var prev_mode := int(prev["mode"])
		on_push_ended(prev_other, prev_mode)
		push_ended.emit(prev_other, prev_mode)

	for key in pushed_curr.keys():
		var data: Dictionary = pushed_curr[key]
		var other := data["other"] as Pawn
		var mode := int(data["mode"])
		var direction := float(data["direction"])
		var overlap := float(data["overlap"])

		if not _pushed_prev.has(key):
			on_pushed_started(other, mode, direction)
			pushed_started.emit(other, mode, direction)

		on_pushed_active(other, mode, direction, overlap)
		pushed_active.emit(other, mode, direction, overlap)

	for key in _pushed_prev.keys():
		if pushed_curr.has(key):
			continue
		var prev: Dictionary = _pushed_prev[key]
		var prev_other := prev["other"] as Pawn
		var prev_mode := int(prev["mode"])
		on_pushed_ended(prev_other, prev_mode)
		pushed_ended.emit(prev_other, prev_mode)

	_pushing_prev = pushing_curr.duplicate(true)
	_pushed_prev = pushed_curr.duplicate(true)


func _refresh_all_pawn_collisions() -> void:
	if not is_inside_tree():
		return

	var nodes := get_tree().get_nodes_in_group(PAWN_GROUP)
	for i in range(nodes.size()):
		if not (nodes[i] is Pawn):
			continue
		var a := nodes[i] as Pawn
		for j in range(i + 1, nodes.size()):
			if not (nodes[j] is Pawn):
				continue
			var b := nodes[j] as Pawn
			var should_collide := a._should_collide_with(b)
			a._set_collision_exception_with(b, not should_collide)
			b._set_collision_exception_with(a, not should_collide)


func _should_collide_with(other: Pawn) -> bool:
	if other == null:
		return false

	return _resolve_pair_collision_mode(other) == PawnCollisionMode.SOLID


func _resolve_pair_collision_mode(other: Pawn) -> int:
	if other == null:
		return PawnCollisionMode.NO_COLLISION

	if pawn_collision_mode == PawnCollisionMode.NO_COLLISION:
		return PawnCollisionMode.NO_COLLISION
	if other.pawn_collision_mode == PawnCollisionMode.NO_COLLISION:
		return PawnCollisionMode.NO_COLLISION

	var self_push := pawn_collision_mode == PawnCollisionMode.SOFT_PUSH or pawn_collision_mode == PawnCollisionMode.HARD_PUSH
	var other_push := other.pawn_collision_mode == PawnCollisionMode.SOFT_PUSH or other.pawn_collision_mode == PawnCollisionMode.HARD_PUSH

	if self_push and other_push:
		if pawn_collision_mode == PawnCollisionMode.HARD_PUSH or other.pawn_collision_mode == PawnCollisionMode.HARD_PUSH:
			return PawnCollisionMode.HARD_PUSH
		return PawnCollisionMode.SOFT_PUSH

	return PawnCollisionMode.SOLID


func _get_collision_half_width_pixels() -> float:
	var max_half_width := 0.0
	for child in get_children():
		if not (child is CollisionShape2D):
			continue

		var cs := child as CollisionShape2D
		if cs.disabled or cs.shape == null:
			continue

		var shape_half_width := _shape_half_width_pixels(cs.shape)
		shape_half_width += absf(cs.position.x)
		max_half_width = maxf(max_half_width, shape_half_width)

	return max_half_width


func _get_collision_half_height_pixels() -> float:
	var max_half_height := 0.0
	for child in get_children():
		if not (child is CollisionShape2D):
			continue

		var cs := child as CollisionShape2D
		if cs.disabled or cs.shape == null:
			continue

		var shape_half_height := _shape_half_height_pixels(cs.shape)
		shape_half_height += absf(cs.position.y)
		max_half_height = maxf(max_half_height, shape_half_height)

	return max_half_height


func _shape_half_width_pixels(shape: Shape2D) -> float:
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.x * 0.5
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		return capsule.radius

	return 0.0


func _shape_half_height_pixels(shape: Shape2D) -> float:
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.y * 0.5
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		# In Godot, CapsuleShape2D.height is the full end-to-end height.
		return capsule.height * 0.5

	return 0.0


func _shape_half_extents_pixels(shape: Shape2D) -> Vector2:
	if shape is CircleShape2D:
		var circle := shape as CircleShape2D
		return Vector2(circle.radius, circle.radius)
	if shape is RectangleShape2D:
		var rect := shape as RectangleShape2D
		return rect.size * 0.5
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		return Vector2(capsule.radius, capsule.height * 0.5)

	return Vector2.ZERO


func _set_collision_exception_with(other: PhysicsBody2D, disabled: bool) -> void:
	if disabled:
		add_collision_exception_with(other)
	else:
		remove_collision_exception_with(other)


func add_external_impulse(impulse: Vector2) -> void:
	# Public API for one-shot forces. Unit space: right(+x), down(+y), up(-y).
	# Example: add_external_impulse(Vector2(10.0, -14.0))
	_external_velocity += GameUnits.units_to_pixels_v2(impulse)


func set_external_velocity(velocity_value: Vector2) -> void:
	# Public API for persistent forces when a system owns the whole external channel.
	_external_velocity = GameUnits.units_to_pixels_v2(velocity_value)


# Hooks for subclass extension.
func on_jump(_jump_velocity: float) -> void:
	pass


func on_turn(_old_facing: int, _new_facing: int) -> void:
	pass


func on_move(_current_velocity: float, _input_axis: float, _grounded: bool) -> void:
	pass


func on_move_started(_current_velocity: float, _input_axis: float, _grounded: bool) -> void:
	pass


func on_move_active(_current_velocity: float, _input_axis: float, _grounded: bool) -> void:
	pass


func on_move_ended(_current_velocity: float, _input_axis: float, _grounded: bool) -> void:
	pass


func on_landed(_impact_velocity: Vector2) -> void:
	pass


func on_wall_hit(_collision_normal: Vector2, _impact_velocity: Vector2) -> void:
	pass


func on_push_started(_other: Pawn, _mode: int, _direction: float) -> void:
	pass


func on_push_active(_other: Pawn, _mode: int, _direction: float, _overlap: float) -> void:
	pass


func on_push_ended(_other: Pawn, _mode: int) -> void:
	pass


func on_pushed_started(_other: Pawn, _mode: int, _direction: float) -> void:
	pass


func on_pushed_active(_other: Pawn, _mode: int, _direction: float, _overlap: float) -> void:
	pass


func on_pushed_ended(_other: Pawn, _mode: int) -> void:
	pass

func _compute_jump_velocity() -> float:
	return (-2.0 * jump_height) / maxf(jump_time_to_peak, 0.001)


func _compute_gravity(is_rising: bool) -> float:
	var phase_time := jump_time_to_peak if is_rising else jump_time_to_fall
	return (2.0 * jump_height) / pow(maxf(phase_time, 0.001), 2.0)


func _sample_curve(curve: Curve, x: float, fallback: float) -> float:
	if curve == null:
		return fallback
	return curve.sample_baked(clampf(x, 0.0, 1.0))
