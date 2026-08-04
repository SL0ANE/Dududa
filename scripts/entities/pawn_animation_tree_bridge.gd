extends Node
class_name PawnAnimationTreeBridge

const Units = preload("res://scripts/shared/game_units.gd")

@export_group("Nodes")
@export var pawn_path: NodePath = ^".."
@export var animation_tree_path: NodePath = ^"../AnimationTree"
@export var force_bridge_expression_base := true

@export_group("Debug")
@export var debug_log_state_transitions := false

@export_group("Tree Parameters")
@export var param_is_on_floor_path: StringName = &"parameters/conditions/is_on_floor"
@export var param_is_moving_path: StringName = &"parameters/conditions/is_moving"
@export var param_move_axis_path: StringName = &"parameters/Locomotion/move_axis"
@export var param_facing_path: StringName = &"parameters/Locomotion/facing"
@export var param_horizontal_speed_path: StringName = &"parameters/Locomotion/horizontal_speed"
@export var param_vertical_speed_path: StringName = &"parameters/Locomotion/vertical_speed"
@export var param_time_since_last_move_path: StringName = &"parameters/Locomotion/time_since_last_move"
@export var param_time_since_last_jump_path: StringName = &"parameters/Jump/time_since_last_jump"
@export var jump_request_path: StringName = &"parameters/Jump/request"
@export var land_request_path: StringName = &"parameters/Land/request"
@export var turn_request_path: StringName = &"parameters/Turn/request"
@export var pushed_request_path: StringName = &"parameters/Pushed/request"
@export var param_air_progress_path: StringName = &"parameters/Jump/blend_position"

var _pawn: Pawn
var _animation_tree: AnimationTree
var _last_facing := 1
var _tree_param_keys := {}
var _last_state_name: StringName = &""
var _time_since_last_move_seconds := 0.0
var _time_since_last_jump_seconds := 0.0

# Public expression values read by AnimationTree transition expressions.
var expr_is_on_floor := false
var expr_is_moving := false
var expr_speed_x_abs := 0.0
var expr_vertical_speed := 0.0
var expr_facing := 1
var expr_is_pushed := false # Kept for compatibility with existing tree expressions.
var expr_airborne_progress := 0.0
var expr_vertical_speed_norm := 0.0
var expr_time_since_last_move_seconds := 0.0
var expr_time_since_last_jump_seconds := 0.0

# Always true, kept for compatibility with existing tree expressions.
var expr_bridge_connected = true

func _ready() -> void:
	_pawn = get_node_or_null(pawn_path) as Pawn
	_animation_tree = get_node_or_null(animation_tree_path) as AnimationTree

	if _pawn == null:
		push_warning("PawnAnimationTreeBridge: pawn_path is invalid.")
		return
	if _animation_tree == null:
		push_warning("PawnAnimationTreeBridge: animation_tree_path is invalid.")
		return
	if not _pawn.jumped.is_connected(_on_pawn_jumped):
		_pawn.jumped.connect(_on_pawn_jumped)

	_bind_expression_base()
	_cache_tree_parameter_keys()
	_animation_tree.active = true
	_last_state_name = _get_current_state_name()
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _pawn == null or _animation_tree == null:
		return

	_sync_expression_values(delta)
	_sync_tree_parameters()
	_log_state_transition_if_needed()


func _bind_expression_base() -> void:
	if _animation_tree == null:
		return

	if force_bridge_expression_base:
		_animation_tree.advance_expression_base_node = _animation_tree.get_path_to(self)
		return

	if _animation_tree.advance_expression_base_node.is_empty():
		_animation_tree.advance_expression_base_node = _animation_tree.get_path_to(_pawn)


func _cache_tree_parameter_keys() -> void:
	_tree_param_keys.clear()
	if _animation_tree == null:
		return

	for p in _animation_tree.get_property_list():
		if not (p is Dictionary):
			continue
		var name_value = (p as Dictionary).get("name", "")
		var name_text := String(name_value)
		if name_text.is_empty():
			continue
		_tree_param_keys[name_text] = true


func _sync_expression_values(delta: float) -> void:
	if _pawn == null:
		return

	var grounded := _is_pawn_grounded()
	var moving := _is_pawn_moving()
	_update_elapsed_activity_timers(moving, delta)

	expr_is_on_floor = grounded
	expr_is_moving = moving
	expr_speed_x_abs = absf(_pawn.velocity.x)
	expr_vertical_speed = _pawn.velocity.y
	expr_facing = _get_pawn_facing()
	expr_is_pushed = false
	expr_time_since_last_move_seconds = _time_since_last_move_seconds
	expr_time_since_last_jump_seconds = _time_since_last_jump_seconds

	expr_airborne_progress = _compute_airborne_progress()


func _update_elapsed_activity_timers(moving: bool, delta: float) -> void:
	if moving:
		_time_since_last_move_seconds = 0.0
	else:
		_time_since_last_move_seconds += maxf(delta, 0.0)

	_time_since_last_jump_seconds += maxf(delta, 0.0)


func _on_pawn_jumped(_jump_velocity: float) -> void:
	_time_since_last_jump_seconds = 0.0


func _compute_airborne_progress() -> float:
	if expr_is_on_floor:
		return -1.0

	return _pawn._normalized_air_phase * 0.5 + 0.5


func _sync_tree_parameters() -> void:
	if _animation_tree == null or _pawn == null:
		return

	_set_tree_parameter(param_is_on_floor_path, expr_is_on_floor)
	_set_tree_parameter(param_is_moving_path, expr_is_moving)
	_set_tree_parameter(param_move_axis_path, _get_pawn_move_axis())
	_set_tree_parameter(param_facing_path, expr_facing)
	_set_tree_parameter(param_horizontal_speed_path, expr_speed_x_abs)
	_set_tree_parameter(param_vertical_speed_path, expr_vertical_speed)
	_set_tree_parameter(param_time_since_last_move_path, expr_time_since_last_move_seconds)
	_set_tree_parameter(param_time_since_last_jump_path, expr_time_since_last_jump_seconds)
	_set_tree_parameter(param_air_progress_path, expr_airborne_progress)


func _set_tree_parameter(path: StringName, value: Variant) -> void:
	_try_set_tree_parameter(path, value)


func _try_set_tree_parameter(path: StringName, value: Variant) -> bool:
	if _animation_tree == null:
		return false

	var key := String(path)
	if key.is_empty():
		return false
	if not _tree_param_keys.has(key):
		return false

	_animation_tree.set(path, value)
	return true


func _is_pawn_grounded() -> bool:
	if _pawn == null:
		return false
	return _pawn.is_on_floor()


func _is_pawn_moving() -> bool:
	if _pawn == null:
		return false

	var threshold_units := 0.0
	if _pawn is Pawn:
		threshold_units = (_pawn as Pawn).moving_threshold
	var threshold_pixels := Units.units_to_pixels(maxf(threshold_units, 0.0))
	return absf(_pawn.velocity.x) > threshold_pixels


func _get_pawn_move_axis() -> float:
	if _pawn == null:
		return 0.0

	if absf(_pawn.velocity.x) < 0.001:
		return 0.0
	return signf(_pawn.velocity.x)


func _get_pawn_facing() -> int:
	if _pawn == null:
		return 1

	if absf(_pawn.velocity.x) >= 0.001:
		_last_facing = -1 if _pawn.velocity.x < 0.0 else 1

	return _last_facing


func _get_current_state_name() -> StringName:
	if _animation_tree == null:
		return &""

	var playback = _animation_tree.get("parameters/playback")
	if playback is AnimationNodeStateMachinePlayback:
		return (playback as AnimationNodeStateMachinePlayback).get_current_node()

	return &""


func _log_state_transition_if_needed() -> void:
	if not debug_log_state_transitions:
		return
	if _pawn == null or _animation_tree == null:
		return

	var current_state := _get_current_state_name()
	if current_state == _last_state_name:
		return

	var now_ms := Time.get_ticks_msec()
	var from_state := "<none>" if _last_state_name.is_empty() else String(_last_state_name)
	var to_state := "<none>" if current_state.is_empty() else String(current_state)
	var vx_units := Units.pixels_to_units(_pawn.velocity.x)
	var vy_units := Units.pixels_to_units(_pawn.velocity.y)

	print(
		"[PawnAnimTransition][", now_ms, " ms] ",
		from_state, " -> ", to_state,
		" floor=", expr_is_on_floor,
		" moving=", expr_is_moving,
		" vx=", snappedf(vx_units, 0.001),
		" vy=", snappedf(vy_units, 0.001),
		" air=", snappedf(expr_airborne_progress, 0.001)
	)

	_last_state_name = current_state
