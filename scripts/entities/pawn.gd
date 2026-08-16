extends CharacterBody2D
class_name Pawn


signal jumped(pawn: Pawn, jump_velocity: float)
signal turned(pawn: Pawn, old_facing: int, new_facing: int)
signal moved(pawn: Pawn, current_velocity: float, input_axis: float, grounded: bool)
signal move_started(pawn: Pawn, current_velocity: float, input_axis: float, grounded: bool)
signal move_active(pawn: Pawn, current_velocity: float, input_axis: float, grounded: bool)
signal move_ended(pawn: Pawn, current_velocity: float, input_axis: float, grounded: bool)
signal left_ground(pawn: Pawn)
signal started_falling(pawn: Pawn)
signal landed(pawn: Pawn, impact_velocity: Vector2, fall_distance_units: float)
signal wall_hit(pawn: Pawn, collision_normal: Vector2, impact_velocity: Vector2)
signal push_started(pawn: Pawn, other: Pawn, mode: int, direction: float)
signal push_active(pawn: Pawn, other: Pawn, mode: int, direction: float, overlap: float)
signal push_ended(pawn: Pawn, other: Pawn, mode: int)
signal pushed_started(pawn: Pawn, other: Pawn, mode: int, direction: float)
signal pushed_active(pawn: Pawn, other: Pawn, mode: int, direction: float, overlap: float)
signal pushed_ended(pawn: Pawn, other: Pawn, mode: int)
signal pawn_contact_started(pawn: Pawn, other: Pawn, normal: Vector2)
signal pawn_contact_active(pawn: Pawn, other: Pawn, normal: Vector2)
signal pawn_contact_ended(pawn: Pawn, other: Pawn, normal: Vector2)
signal interacted_primary(pawn: Pawn)
signal interacted_secondary(pawn: Pawn)


const PAWN_GROUP: StringName = &"pawn"
const CONTACT_EVENTS_ARM_DELAY_FRAMES := 2
# const FLOOR_SNAP_SUSPEND_AFTER_RESIZE_FRAMES := 2

static var _collider_id_to_pawn := {}

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

@export_group("Active Actions")
# Enable active horizontal movement input.
@export var movement_enabled := true
# Enable primary interaction input/dispatch.
@export var interact_primary_enabled := true
# Enable secondary interaction input/dispatch.
@export var interact_secondary_enabled := true

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

@export_group("Audio")
# Relative path to jump sound player node.
@export var jump_sfx_player_path: NodePath = ^"SoundEffects/SFXJump"
# Relative path to landing sound player node.
@export var land_sfx_player_path: NodePath = ^"SoundEffects/SFXLand"
# Optional landing sound effects selected by fall distance thresholds.
@export var land_sfx_streams: Array[AudioStream] = []
# Fall-distance thresholds for landing sound effects, expected in ascending order and one fewer than the sound effect count.
@export var land_sfx_distance_thresholds: Array[float] = []
# Relative path to footstep sound player node.
@export var footstep_sfx_player_path: NodePath = ^"SoundEffects/SFXFootstep"
# Optional alternating footstep streams.
@export var footstep_sfx_stream_a: AudioStream
@export var footstep_sfx_stream_b: AudioStream

@export_group("Nodes")
# Relative path to controller node used to build commands.
@export var controller_path: NodePath
# Relative paths to collision shapes. Each path must point directly to a CollisionShape2D.
@export var collision_shape_paths: Array[NodePath] = [^"CollisionShape2D"]
# Relative path to AnimationTree node.
@export var animation_tree_path: NodePath = ^"AnimationTree"
# Optional sprite node path. Empty is allowed for multi-part visuals.
@export var sprite_path: NodePath = ^"AnimatedSprite2D"
# Default art facing direction used to compute flip_h.
@export_enum("Left", "Mid", "Right") var sprite_default_facing := 0

var _facing := 1

var _controller: PawnController
var _collider: CollisionShape2D
var _collision_shapes: Array[CollisionShape2D] = []
var _jump_sfx_player: AudioStreamPlayer2D
var _land_sfx_player: AudioStreamPlayer2D
var _footstep_sfx_player: AudioStreamPlayer2D
var _next_footstep_sfx_index := 0
# Driven velocity is produced by the pawn movement model (input, jump profile).
var _driven_velocity := Vector2.ZERO
# External velocity is produced by gameplay systems (hit, wind, explosion).
# Keep this channel additive on X so external horizontal impulses do not get overwritten.
var _external_velocity := Vector2.ZERO
# Vertical movement is computed through a single channel to avoid driven/external Y cancellation.
var _vertical_velocity := 0.0
var _air_phase_time := 0.0
var _normalized_air_phase := 0.0
var _was_rising := false
var _was_falling := false
var _coyote_time_left := 0.0
var _jump_count_since_ground := 0
var _last_pawn_collision_mode := -1
var _was_moving := false
var _was_on_pawn_floor := false
var _airborne_start_y_px := INF
var _airborne_peak_y_px := INF
# Latched true while airborne if the pawn touched a ceiling, so the arc peak was clamped.
var _hit_ceiling_since_takeoff := false
var last_fall_distance_units := 0.0
var last_land_timestamp := 0
var land_timestamp := 0
var _contact_events_arm_frames_left := CONTACT_EVENTS_ARM_DELAY_FRAMES
var _pushing_prev := {}
var _pushed_prev := {}
var _pawn_contacts_prev := {}
var _floor_support_colliders_cached: Array[Object] = []
var _floor_support_normals := {}

var _jump_height_on_jump := 0.0
var _jump_time_to_peak_on_jump := 0.0
var _jump_time_to_fall_on_jump := 0.0
# var _floor_snap_suspend_frames_left := 0
var _registered_collider_ids: Array[int] = []

# @onready var _animation_tree: AnimationTree = get_node_or_null(animation_tree_path)
@onready var _sprite: AnimatedSprite2D = _resolve_sprite()


func _enter_tree() -> void:
	# Reparenting can trigger tree exit/enter cycles; keep collider lookup in sync.
	if not tree_exiting.is_connected(_on_tree_exiting_unregister_collision_lookup):
		tree_exiting.connect(_on_tree_exiting_unregister_collision_lookup)

	_register_collision_lookup()


func _ready() -> void:
	if not is_in_group(PAWN_GROUP):
		add_to_group(PAWN_GROUP)

	_last_pawn_collision_mode = pawn_collision_mode
	call_deferred("_refresh_all_pawn_collisions")

	_cache_collision_shapes_from_paths()
	_collider = _resolve_movable_collider()
	_ensure_collider_bottom_aligned_on_spawn()
	_controller = _resolve_controller()
	_jump_sfx_player = get_node_or_null(jump_sfx_player_path) as AudioStreamPlayer2D
	_land_sfx_player = get_node_or_null(land_sfx_player_path) as AudioStreamPlayer2D
	_footstep_sfx_player = get_node_or_null(footstep_sfx_player_path) as AudioStreamPlayer2D
	# Ensure gravity/jump math has valid profile values even before first jump.
	_jump_height_on_jump = jump_height
	_jump_time_to_peak_on_jump = jump_time_to_peak
	_jump_time_to_fall_on_jump = jump_time_to_fall
	_contact_events_arm_frames_left = CONTACT_EVENTS_ARM_DELAY_FRAMES
	_refresh_floor_support_colliders_cache()
	# if _animation_tree:
		# _animation_tree.active = true

	# _ensure_valid_sprite_animation()


static func resolve_pawn_from_collider_id(collider_id: int) -> Pawn:
	if collider_id <= 0:
		return null

	var pawn := _collider_id_to_pawn.get(collider_id, null) as Pawn
	if pawn != null and is_instance_valid(pawn):
		return pawn

	if _collider_id_to_pawn.has(collider_id):
		_collider_id_to_pawn.erase(collider_id)
	return null


static func resolve_pawn_from_collider_node(collider: Node) -> Pawn:
	if collider == null:
		return null

	return resolve_pawn_from_collider_id(collider.get_instance_id())


func _register_collision_lookup() -> void:
	_unregister_collision_lookup()
	_register_collider_id(get_instance_id())

	for cs in _get_cached_collision_shapes():
		_register_collider_id(cs.get_instance_id())


func _register_collider_id(collider_id: int) -> void:
	if collider_id <= 0:
		return

	_collider_id_to_pawn[collider_id] = self
	_registered_collider_ids.append(collider_id)


func _unregister_collision_lookup() -> void:
	for collider_id in _registered_collider_ids:
		if _collider_id_to_pawn.get(collider_id, null) == self:
			_collider_id_to_pawn.erase(collider_id)

	_registered_collider_ids.clear()


func _on_tree_exiting_unregister_collision_lookup() -> void:
	_unregister_collision_lookup()


func _physics_process(delta: float) -> void:
	if _last_pawn_collision_mode != pawn_collision_mode:
		_last_pawn_collision_mode = pawn_collision_mode
		call_deferred("_refresh_all_pawn_collisions")

	var was_on_ground := is_on_floor()
	var was_on_pawn_floor := _was_on_pawn_floor
	var was_on_wall := is_on_wall()
	if was_on_ground:
		_coyote_time_left = coyote_time
		_jump_count_since_ground = 0
		_airborne_start_y_px = INF
		_airborne_peak_y_px = INF
		_hit_ceiling_since_takeoff = false
	else:
		_coyote_time_left = maxf(_coyote_time_left - delta, 0.0)
		if is_inf(_airborne_start_y_px):
			_airborne_start_y_px = global_position.y
			_airborne_peak_y_px = global_position.y
		elif global_position.y < _airborne_peak_y_px:
			_airborne_peak_y_px = global_position.y

	var command := _build_command(delta)
	var move_axis: float = command.get("move_axis", 0.0)
	if not movement_enabled:
		move_axis = 0.0
	var look_axis: float = command.get("look_axis", move_axis)
	var jump_pressed: bool = command.get("jump_pressed", false)
	if not jump_enabled:
		jump_pressed = false
	var interact_primary_pressed: bool = command.get("interact_primary_pressed", false)
	if not interact_primary_enabled:
		interact_primary_pressed = false
	var interact_secondary_pressed: bool = command.get("interact_secondary_pressed", false)
	if not interact_secondary_enabled:
		interact_secondary_pressed = false

	if interact_primary_pressed:
		on_interact_primary()
		interacted_primary.emit(self)

	if interact_secondary_pressed:
		on_interact_secondary()
		interacted_secondary.emit(self)

	var jumps_allowed := maxi(max_jump_count, 0)
	var has_jumps_left := _jump_count_since_ground < jumps_allowed
	var can_ground_jump := was_on_ground or _coyote_time_left > 0.0
	# Prevent unlimited delayed first-jump after walking off edges.
	# Air jumps are only allowed after at least one jump has been consumed.
	var can_air_jump := (not can_ground_jump) and _jump_count_since_ground > 0
	var can_jump := has_jumps_left and (can_ground_jump or can_air_jump)
	if jump_pressed and can_jump:
		_jump_height_on_jump = jump_height
		_jump_time_to_peak_on_jump = jump_time_to_peak
		_jump_time_to_fall_on_jump = jump_time_to_fall

		var jump_velocity := _compute_jump_velocity()
		_vertical_velocity = GameUnits.units_to_pixels(jump_velocity)
		_air_phase_time = 0.0
		_was_rising = true
		_coyote_time_left = 0.0
		_jump_count_since_ground += 1
		on_jump(jump_velocity)
		jumped.emit(self, jump_velocity)

	_apply_vertical_velocity(delta, was_on_ground)
	_apply_horizontal_velocity(move_axis, delta)
	_apply_external_forces(delta)
	_try_corner_correction(move_axis, delta)

	if _should_skip_move_and_slide_for_idle_solid(move_axis, jump_pressed, was_on_ground):
		velocity = Vector2.ZERO
		_driven_velocity = Vector2.ZERO
		_external_velocity = Vector2.ZERO
		_vertical_velocity = 0.0
		_update_animation_state(look_axis)
		_process_move_lifecycle(0.0, move_axis, was_on_ground)
		_refresh_floor_support_colliders_cache()
		_process_pawn_contact_events()
		_tick_contact_event_arm_delay()
		return

	# Merge channels only at the end of the frame.
	var pre_move_position := global_position
	var pre_slide_vertical_velocity := _vertical_velocity
	velocity = Vector2(_driven_velocity.x + _external_velocity.x, _vertical_velocity)
	var pre_slide_velocity := velocity

	move_and_slide()

	_try_floor_snap_after_slide(was_on_ground, was_on_pawn_floor, jump_pressed)
	_stabilize_idle_solid_pawn(move_axis, jump_pressed, pre_move_position)
	_was_on_pawn_floor = _is_current_floor_from_pawn()
	_apply_pawn_push_collisions()
	if was_on_ground and not is_on_floor():
		_airborne_start_y_px = pre_move_position.y
		_airborne_peak_y_px = minf(pre_move_position.y, global_position.y)
	if is_on_ceiling():
		_hit_ceiling_since_takeoff = true
	_process_contact_events(was_on_ground, was_on_wall, pre_slide_velocity)
	_process_pawn_contact_events()
	# Reconcile channels with collision result to avoid drift over time.
	_sync_velocity_components_after_slide(pre_slide_vertical_velocity)
	_update_animation_state(look_axis)
	var current_velocity := GameUnits.pixels_to_units(velocity.x)
	_process_move_lifecycle(current_velocity, move_axis, is_on_floor())
	_refresh_floor_support_colliders_cache()
	_tick_contact_event_arm_delay()


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


func _resolve_movable_collider() -> CollisionShape2D:
	var colliders := _get_active_collision_shapes()
	if not colliders.is_empty():
		return colliders[0]

	return null


func _get_movable_collider() -> CollisionShape2D:
	if _collider and is_instance_valid(_collider):
		return _collider

	_collider = _resolve_movable_collider()
	return _collider


func _ensure_collider_bottom_aligned_on_spawn() -> void:
	var colliders := _get_active_collision_shapes()
	if colliders.size() != 1:
		return

	var collision_shape := colliders[0]
	if collision_shape.shape == null:
		return

	var half_height_px := _shape_half_height_pixels(collision_shape.shape)
	if half_height_px <= 0.0:
		return

	var bottom_local_y := collision_shape.position.y + half_height_px
	if is_equal_approx(bottom_local_y, 0.0):
		return

	push_warning("Pawn: CollisionShape2D bottom is not aligned to Pawn origin; auto-correcting on spawn.")
	collision_shape.position.y = -half_height_px


func _get_collider_height_px() -> float:
	var collision_shape := _get_movable_collider()
	if collision_shape != null and collision_shape.shape != null:
		var shape := collision_shape.shape
		if shape is RectangleShape2D:
			return (shape as RectangleShape2D).size.y
		if shape is CapsuleShape2D:
			var capsule := shape as CapsuleShape2D
			return capsule.height

	# Fallback supports multi-collider setups and shapes without explicit height API.
	var bounds := _get_collision_bounds_pixels()
	if bounds.size == Vector2.ZERO:
		return 0.0
	return bounds.size.y


func _get_collider_height_units() -> float:
	return GameUnits.pixels_to_units(_get_collider_height_px())


func _set_collider_height_units(new_height_units: float) -> void:
	var collision_shape := _get_movable_collider()
	if collision_shape == null:
		return
	if collision_shape.shape == null:
		return

	var was_on_ground := is_on_floor()

	if was_on_ground and _vertical_velocity > 0.0:
		_vertical_velocity = 0.0

	var old_height_px := _shape_half_height_pixels(collision_shape.shape) * 2.0
	var new_height_px := GameUnits.units_to_pixels(new_height_units)
	var shape := collision_shape.shape
	var half_height_px := 0.0
	if shape is RectangleShape2D:
		var rect := shape as RectangleShape2D
		rect.size.y = maxf(new_height_px, 1.0)
		half_height_px = rect.size.y * 0.5
	elif shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		capsule.height = maxf(new_height_px, 0.0)
		half_height_px = capsule.height * 0.5
	else:
		return

	# Keep collider bottom aligned to Pawn local origin (y = 0).
	collision_shape.position.y = -half_height_px

	var growth_px := maxf(new_height_px - old_height_px, 0.0)
	if growth_px > 0.0:
		_depenetrate_up_after_collider_resize(int(ceil(growth_px)) + 2)


func _depenetrate_up_after_collider_resize(max_up_px: int) -> void:
	if max_up_px <= 0:
		return

	if not test_move(global_transform, Vector2.ZERO):
		return

	for i in range(1, max_up_px + 1):
		var up := Vector2(0.0, -float(i))
		var candidate := global_transform.translated(up)
		if test_move(candidate, Vector2.ZERO):
			continue

		global_position += up
		velocity.y = minf(velocity.y, 0.0)
		_vertical_velocity = minf(_vertical_velocity, 0.0)
		return


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

	var is_rising := _vertical_velocity < 0.0
	if is_rising != _was_rising:
		_air_phase_time = 0.0
		_was_rising = is_rising

	_air_phase_time += delta
	var phase_time := _jump_time_to_peak_on_jump if is_rising else _jump_time_to_fall_on_jump
	_normalized_air_phase = clampf(_air_phase_time / maxf(phase_time, 0.001), 0.0, 1.0)

	var gravity := compute_gravity(is_rising)
	var gravity_curve_multiplier := maxf(_sample_curve(jump_gravity_curve, _normalized_air_phase, 1.0), 0.0)
	_normalized_air_phase = (_normalized_air_phase - 1.0 if is_rising else _normalized_air_phase)
	_vertical_velocity += GameUnits.units_to_pixels(gravity * gravity_curve_multiplier) * delta


func _apply_external_forces(delta: float) -> void:
	var drag := external_drag_ground if is_on_floor() else external_drag_air
	var drag_pixels := GameUnits.units_to_pixels(maxf(drag, 0.0))
	_external_velocity.x = move_toward(_external_velocity.x, 0.0, drag_pixels * delta)


func _sync_velocity_components_after_slide(pre_slide_vertical_velocity: float) -> void:
	_driven_velocity.x = velocity.x - _external_velocity.x
	# If callbacks changed vertical velocity after slide (e.g. landed bounce), keep authored value.
	if is_equal_approx(_vertical_velocity, pre_slide_vertical_velocity):
		_vertical_velocity = velocity.y
	if is_on_floor() and _vertical_velocity > 0.0:
		_vertical_velocity = 0.0


func _update_animation_state(look_axis: float) -> void:
	var old_facing := _facing
	if not is_zero_approx(look_axis):
		_facing = 0 if look_axis < 0.0 else 2
	elif not is_zero_approx(velocity.x):
		_facing = 0 if velocity.x < 0.0 else 2

	if old_facing != _facing:
		on_turn(old_facing, _facing)
		turned.emit(self, old_facing, _facing)

	if _sprite and sprite_default_facing != 1:
		var clamped_default_facing := 0 if sprite_default_facing < 1 else 2
		_sprite.flip_h = _facing != clamped_default_facing


func _process_contact_events(was_on_ground: bool, was_on_wall: bool, pre_slide_velocity: Vector2) -> void:
	var on_ground_now := is_on_floor()
	if was_on_ground and not on_ground_now:
		on_left_ground()
		left_ground.emit(self)

	var is_falling_now := not on_ground_now and velocity.y > 0.0
	if is_falling_now and not _was_falling:
		on_started_falling()
		started_falling.emit(self)
	_was_falling = is_falling_now

	if _contact_events_arm_frames_left > 0:
		return

	if not was_on_ground and on_ground_now:
		var impact_velocity := GameUnits.pixels_to_units_v2(pre_slide_velocity)
		var fall_distance_units := 0.0
		if not is_inf(_airborne_start_y_px):
			var landing_y_px := global_position.y
			var fall_distance_px := maxf(0.0, landing_y_px - _airborne_peak_y_px)
			fall_distance_units = GameUnits.pixels_to_units(fall_distance_px)
			last_fall_distance_units = fall_distance_units
			last_land_timestamp = land_timestamp
			land_timestamp = Engine.get_physics_frames()
			_airborne_start_y_px = INF
			_airborne_peak_y_px = INF
		on_landed(impact_velocity, fall_distance_units)
		landed.emit(self, impact_velocity, fall_distance_units)

	if not was_on_wall and is_on_wall():
		var wall_normal := _get_wall_collision_normal()
		var wall_impact_velocity := GameUnits.pixels_to_units_v2(pre_slide_velocity)
		on_wall_hit(wall_normal, wall_impact_velocity)
		wall_hit.emit(self, wall_normal, wall_impact_velocity)


func _tick_contact_event_arm_delay() -> void:
	if _contact_events_arm_frames_left > 0:
		_contact_events_arm_frames_left -= 1


func _process_pawn_contact_events() -> void:
	var contacts_curr := {}
	for collider in _floor_support_colliders_cached:
		var other := collider as Pawn
		if other == null or other == self or not is_instance_valid(other):
			continue
		var key := other.get_instance_id()
		contacts_curr[key] = {
			"other": other,
			"normal": _floor_support_normals.get(key, Vector2.UP),
		}

	_append_geometric_pawn_contacts(contacts_curr)

	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		if collision == null:
			continue

		var other := collision.get_collider() as Pawn
		if other == null or other == self or not is_instance_valid(other):
			continue

		var key := other.get_instance_id()
		contacts_curr[key] = {
			"other": other,
			"normal": collision.get_normal(),
		}

	for key in contacts_curr.keys():
		var data: Dictionary = contacts_curr[key]
		var other := data["other"] as Pawn
		var normal: Vector2 = data["normal"]
		if not _pawn_contacts_prev.has(key):
			on_pawn_contact_started(other, normal)
			pawn_contact_started.emit(self, other, normal)
		on_pawn_contact_active(other, normal)
		pawn_contact_active.emit(self, other, normal)

	for key in _pawn_contacts_prev.keys():
		if contacts_curr.has(key):
			continue
		var previous: Dictionary = _pawn_contacts_prev[key]
		var other := previous["other"] as Pawn
		if other == null or not is_instance_valid(other):
			continue
		var normal: Vector2 = previous.get("normal", Vector2.UP)
		on_pawn_contact_ended(other, normal)
		pawn_contact_ended.emit(self, other, normal)

	_pawn_contacts_prev = contacts_curr


func _append_geometric_pawn_contacts(contacts_curr: Dictionary) -> void:
	var my_bounds := _get_collision_bounds_pixels()
	if my_bounds.size == Vector2.ZERO:
		return

	var my_center := my_bounds.get_center()
	my_bounds = my_bounds.grow(1.0)
	for node in get_tree().get_nodes_in_group(PAWN_GROUP):
		var other := node as Pawn
		if other == null or other == self or not is_instance_valid(other):
			continue

		var other_bounds := other._get_collision_bounds_pixels()
		if other_bounds.size == Vector2.ZERO or not my_bounds.intersects(other_bounds.grow(1.0)):
			continue

		var delta := my_center - other_bounds.get_center()
		var normal := Vector2.UP
		if absf(delta.x) > absf(delta.y):
			normal = Vector2(signf(delta.x), 0.0)
		elif not is_zero_approx(delta.y):
			normal = Vector2(0.0, signf(delta.y))

		var key := other.get_instance_id()
		if not contacts_curr.has(key):
			contacts_curr[key] = {
				"other": other,
				"normal": normal,
			}


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


func _try_floor_snap_after_slide(was_on_ground: bool, was_on_pawn_floor: bool, jump_pressed: bool) -> void:
	if jump_pressed:
		return
	if is_on_floor():
		return
	if not was_on_ground:
		return
	# Avoid treating stacked pawns as snap-floor; this prevents jitter and downhill force propagation.
	if was_on_pawn_floor:
		return
	# Do not re-snap while moving upward (jump, knock-up, moving platforms, etc.).
	if velocity.y < 0.0:
		return
	if _vertical_velocity < 0.0:
		return
	if floor_snap_length_units <= 0.0:
		return

	var max_fall_px := GameUnits.units_to_pixels(maxf(floor_snap_max_fall_speed, 0.0))
	if _vertical_velocity > max_fall_px:
		return

	# Keep ground contact when descending slopes so locomotion state stays stable.
	var original_floor_snap := self.floor_snap_length
	self.floor_snap_length = GameUnits.units_to_pixels(floor_snap_length_units)
	apply_floor_snap()
	self.floor_snap_length = original_floor_snap


func _is_current_floor_from_pawn() -> bool:
	if not is_on_floor():
		return false

	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		if collision == null:
			continue
		if collision.get_normal().y > -0.5:
			continue
		if collision.get_collider() is Pawn:
			return true

	return false


func get_floor_support_colliders_cached() -> Array[Object]:
	return _floor_support_colliders_cached.duplicate()


func _refresh_floor_support_colliders_cache() -> void:
	_floor_support_colliders_cached = _get_floor_support_colliders()
	_floor_support_normals = _get_floor_support_normals()


func _get_floor_support_normals() -> Dictionary:
	var normals := {}
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		if collision == null or collision.get_normal().y > -0.5:
			continue

		var support := collision.get_collider() as Pawn
		if support == null or support == self:
			continue

		normals[support.get_instance_id()] = collision.get_normal()

	return normals


func _get_floor_support_colliders(probe_distance_px: float = 2.0) -> Array[Object]:
	if not is_on_floor():
		return []

	var bounds := _get_collision_bounds_pixels()
	if bounds.size == Vector2.ZERO:
		return []

	var safe_probe_px := maxf(probe_distance_px, 0.5)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(maxf(bounds.size.x - 1.0, 1.0), safe_probe_px)

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, Vector2(bounds.position.x + bounds.size.x * 0.5, bounds.position.y + bounds.size.y + safe_probe_px * 0.5))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var space_state := get_world_2d().direct_space_state
	var hits := space_state.intersect_shape(query, 32)
	var supports: Array[Object] = []
	var seen := {}
	for hit in hits:
		var collider: Object = hit.get("collider") as Object
		if collider == null:
			continue
		if not is_instance_valid(collider):
			continue
		if collider == self:
			continue

		var id: int = collider.get_instance_id()
		if seen.has(id):
			continue

		seen[id] = true
		supports.append(collider)

	return supports


func _stabilize_idle_solid_pawn(move_axis: float, jump_pressed: bool, pre_move_position: Vector2) -> void:
	if pawn_collision_mode != PawnCollisionMode.SOLID:
		return
	if absf(move_axis) > 0.001:
		return
	if jump_pressed:
		return

	if not is_on_floor():
		return

	if is_equal_approx(global_position.x, pre_move_position.x) and is_equal_approx(global_position.y, pre_move_position.y):
		return

	# Keep SOLID idle pawns horizontally stable, but do not undo downward floor corrections.
	var stabilized_position := global_position
	stabilized_position.x = pre_move_position.x
	if global_position.y < pre_move_position.y:
		stabilized_position.y = pre_move_position.y
	global_position = stabilized_position

	velocity.x = 0.0
	_driven_velocity.x = 0.0
	_external_velocity.x = 0.0


func _should_skip_move_and_slide_for_idle_solid(move_axis: float, jump_pressed: bool, was_on_ground: bool) -> bool:
	if pawn_collision_mode != PawnCollisionMode.SOLID:
		return false
	if not was_on_ground:
		return false
	if absf(move_axis) > 0.001:
		return false
	if jump_pressed:
		return false
	if absf(_external_velocity.x) > 0.001 or absf(_vertical_velocity) > 0.001:
		return false

	# Keep updating normally if support below was lost.
	return test_move(global_transform, Vector2(0.0, 1.0))


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

	for cs in _get_active_collision_shapes():

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
		move_started.emit(self, current_velocity, input_axis, grounded)

	if is_moving_now:
		# Keep active updates in air too, so animation/state machines can react continuously.
		on_move_active(current_velocity, input_axis, grounded)
		move_active.emit(self, current_velocity, input_axis, grounded)
		# Legacy compatibility.
		on_move(current_velocity, input_axis, grounded)
		moved.emit(self, current_velocity, input_axis, grounded)

	if not is_moving_now and _was_moving:
		on_move_ended(current_velocity, input_axis, grounded)
		move_ended.emit(self, current_velocity, input_axis, grounded)

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
			push_started.emit(self, other, mode, direction)

		on_push_active(other, mode, direction, overlap)
		push_active.emit(self, other, mode, direction, overlap)

	for key in _pushing_prev.keys():
		if pushing_curr.has(key):
			continue
		var prev: Dictionary = _pushing_prev[key]
		var prev_other := prev["other"] as Pawn
		var prev_mode := int(prev["mode"])
		on_push_ended(prev_other, prev_mode)
		push_ended.emit(self, prev_other, prev_mode)

	for key in pushed_curr.keys():
		var data: Dictionary = pushed_curr[key]
		var other := data["other"] as Pawn
		var mode := int(data["mode"])
		var direction := float(data["direction"])
		var overlap := float(data["overlap"])

		if not _pushed_prev.has(key):
			on_pushed_started(other, mode, direction)
			pushed_started.emit(self, other, mode, direction)

		on_pushed_active(other, mode, direction, overlap)
		pushed_active.emit(self, other, mode, direction, overlap)

	for key in _pushed_prev.keys():
		if pushed_curr.has(key):
			continue
		var prev: Dictionary = _pushed_prev[key]
		var prev_other := prev["other"] as Pawn
		var prev_mode := int(prev["mode"])
		on_pushed_ended(prev_other, prev_mode)
		pushed_ended.emit(self, prev_other, prev_mode)

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
	for cs in _get_active_collision_shapes():

		var shape_half_width := _shape_half_width_pixels(cs.shape)
		shape_half_width += absf(cs.position.x)
		max_half_width = maxf(max_half_width, shape_half_width)

	return max_half_width


func _get_collision_half_height_pixels() -> float:
	var max_half_height := 0.0
	for cs in _get_active_collision_shapes():

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


func _get_active_collision_shapes() -> Array[CollisionShape2D]:
	if _collision_shapes.is_empty():
		_cache_collision_shapes_from_paths()

	var colliders: Array[CollisionShape2D] = []
	for cached in _collision_shapes:
		if cached == null or not is_instance_valid(cached):
			continue

		var cs := cached as CollisionShape2D
		if cs.disabled or cs.shape == null:
			continue

		colliders.append(cs)

	return colliders


func _get_cached_collision_shapes() -> Array[CollisionShape2D]:
	if _collision_shapes.is_empty():
		_cache_collision_shapes_from_paths()

	var colliders: Array[CollisionShape2D] = []
	for cached in _collision_shapes:
		if cached == null or not is_instance_valid(cached):
			continue
		colliders.append(cached)

	return colliders


func _cache_collision_shapes_from_paths() -> void:
	_collision_shapes.clear()

	if collision_shape_paths.is_empty():
		push_warning("Pawn: collision_shape_paths is empty.")
		return

	for collider_path in collision_shape_paths:
		if collider_path.is_empty():
			continue

		var path_node := get_node_or_null(collider_path)
		if path_node == null:
			push_warning("Pawn: invalid collision shape path: %s" % String(collider_path))
			continue

		if not (path_node is CollisionShape2D):
			push_warning("Pawn: path does not reference CollisionShape2D: %s" % String(collider_path))
			continue

		var collider := path_node as CollisionShape2D
		if _collision_shapes.has(collider):
			continue

		_collision_shapes.append(collider)


func _set_collision_exception_with(other: PhysicsBody2D, disabled: bool) -> void:
	if disabled:
		add_collision_exception_with(other)
	else:
		remove_collision_exception_with(other)


func add_external_impulse(impulse: Vector2) -> void:
	# Public API for one-shot forces. Unit space: right(+x), down(+y), up(-y).
	# Example: add_external_impulse(Vector2(10.0, -14.0))
	var impulse_px := GameUnits.units_to_pixels_v2(impulse)
	_external_velocity.x += impulse_px.x
	_vertical_velocity += impulse_px.y


func set_external_velocity(velocity_value: Vector2) -> void:
	# Public API for persistent forces when a system owns velocity channels.
	var velocity_px := GameUnits.units_to_pixels_v2(velocity_value)
	_external_velocity.x = velocity_px.x
	_vertical_velocity = velocity_px.y


func has_hit_ceiling_since_takeoff() -> bool:
	# True when the most recent airborne arc's peak was clamped by a ceiling.
	return _hit_ceiling_since_takeoff


func _play_jump_sfx(stream_override: AudioStream = null) -> void:
	if _jump_sfx_player == null:
		return

	var stream_to_play := stream_override
	if stream_to_play == null:
		stream_to_play = _jump_sfx_player.stream
	if stream_to_play == null:
		return

	if _jump_sfx_player.stream != stream_to_play:
		_jump_sfx_player.stream = stream_to_play
	_jump_sfx_player.play()


func _get_jump_sfx_stream_for_jump(_jump_velocity: float) -> AudioStream:
	return null


func _play_land_sfx(stream_override: AudioStream = null) -> void:
	if _land_sfx_player == null:
		return

	var stream_to_play := stream_override
	if stream_to_play == null:
		stream_to_play = _land_sfx_player.stream
	if stream_to_play == null:
		return

	if _land_sfx_player.stream != stream_to_play:
		_land_sfx_player.stream = stream_to_play
	_land_sfx_player.play()


func _get_land_sfx_stream_for_landing(_impact_velocity: Vector2, fall_distance_units: float) -> AudioStream:
	if land_sfx_streams.is_empty():
		return null

	if land_sfx_streams.size() == 1:
		return land_sfx_streams[0]

	if land_sfx_distance_thresholds.is_empty():
		return land_sfx_streams[0]

	# print("land_distance: " + str(fall_distance_units))

	var threshold_count := land_sfx_distance_thresholds.size()
	var stream_count := land_sfx_streams.size()
	if threshold_count >= stream_count:
		threshold_count = maxf(0.0, float(stream_count - 1))

	for index in range(int(threshold_count)):
		var threshold := land_sfx_distance_thresholds[index]
		if fall_distance_units < threshold:
			return land_sfx_streams[index]

	var last_index := int(minf(float(stream_count - 1), float(threshold_count)))
	return land_sfx_streams[last_index]


func play_footstep_sfx() -> void:
	if _footstep_sfx_player == null:
		return
	if not is_on_floor():
		return
	if absf(velocity.x) <= GameUnits.units_to_pixels(moving_threshold):
		return

	var stream_to_play: AudioStream = null
	if footstep_sfx_stream_a != null and footstep_sfx_stream_b != null:
		stream_to_play = footstep_sfx_stream_a if _next_footstep_sfx_index == 0 else footstep_sfx_stream_b
		_next_footstep_sfx_index = (_next_footstep_sfx_index + 1) % 2
	elif footstep_sfx_stream_a != null:
		stream_to_play = footstep_sfx_stream_a
	elif footstep_sfx_stream_b != null:
		stream_to_play = footstep_sfx_stream_b
	else:
		stream_to_play = _footstep_sfx_player.stream

	if stream_to_play == null:
		return
	if _footstep_sfx_player.stream != stream_to_play:
		_footstep_sfx_player.stream = stream_to_play
	_footstep_sfx_player.play()


# Hooks for subclass extension.
func on_jump(jump_velocity: float) -> void:
	_play_jump_sfx(_get_jump_sfx_stream_for_jump(jump_velocity))


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


func on_left_ground() -> void:
	pass


func on_started_falling() -> void:
	pass


func on_landed(_impact_velocity: Vector2, fall_distance_units: float = 0.0) -> void:
	_play_land_sfx(_get_land_sfx_stream_for_landing(_impact_velocity, fall_distance_units))


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


func on_pawn_contact_started(_other: Pawn, _normal: Vector2) -> void:
	pass


func on_pawn_contact_active(_other: Pawn, _normal: Vector2) -> void:
	pass


func on_pawn_contact_ended(_other: Pawn, _normal: Vector2) -> void:
	pass


func on_interact_primary() -> void:
	pass


func on_interact_secondary() -> void:
	pass

func _compute_jump_velocity() -> float:
	var height := _jump_height_on_jump
	if is_zero_approx(height):
		height = jump_height
	var time_to_peak := _jump_time_to_peak_on_jump
	if time_to_peak <= 0.0:
		time_to_peak = jump_time_to_peak
	return (-2.0 * height) / maxf(time_to_peak, 0.001)


func compute_gravity(is_rising: bool) -> float:
	var height := _jump_height_on_jump
	if is_zero_approx(height):
		height = jump_height
	var phase_time := _jump_time_to_peak_on_jump if is_rising else _jump_time_to_fall_on_jump
	if phase_time <= 0.0:
		phase_time = jump_time_to_peak if is_rising else jump_time_to_fall
	return (2.0 * height) / pow(maxf(phase_time, 0.001), 2.0)


func _sample_curve(curve: Curve, x: float, fallback: float) -> float:
	if curve == null:
		return fallback
	return curve.sample_baked(clampf(x, 0.0, 1.0))
