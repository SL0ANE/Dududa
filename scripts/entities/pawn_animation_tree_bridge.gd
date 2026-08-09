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
@export var param_air_progress_path: StringName = &"parameters/Jump/blend_position"
@export var use_parameter_path_aliases := true

const _TREE_PARAM_PATH_ALIASES := {
	&"air_progress": [
		&"parameters/Jump/blend_position",
		&"parameters/Locomotion/Jump/blend_position",
		&"parameters/EnabledState/Jump/blend_position",
	],
}

var _pawn: Pawn
var _animation_tree: AnimationTree
var _last_facing := 1
var _managed_trees := {}
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
var expr_primary_interact_enabled := true
var expr_secondary_interact_enabled := true
var expr_primary_interact_requested := false
var expr_secondary_interact_requested := false

# Always true, kept for compatibility with existing tree expressions.
var expr_bridge_connected = true
var _pending_primary_interact_request := false
var _pending_secondary_interact_request := false

func _ready() -> void:
	_pawn = get_node_or_null(pawn_path) as Pawn
	_animation_tree = get_node_or_null(animation_tree_path) as AnimationTree

	if _pawn == null:
		push_warning("PawnAnimationTreeBridge: pawn_path is invalid.")
		return
	if _animation_tree == null:
		push_warning("PawnAnimationTreeBridge: animation_tree_path is invalid.")
	if not _pawn.jumped.is_connected(_on_pawn_jumped):
		_pawn.jumped.connect(_on_pawn_jumped)
	if not _pawn.interacted_primary.is_connected(_on_pawn_interacted_primary):
		_pawn.interacted_primary.connect(_on_pawn_interacted_primary)
	if not _pawn.interacted_secondary.is_connected(_on_pawn_interacted_secondary):
		_pawn.interacted_secondary.connect(_on_pawn_interacted_secondary)

	if _animation_tree != null:
		register_animation_tree(_animation_tree, _resolve_tree_animation_player(_animation_tree), force_bridge_expression_base)
	_last_state_name = _get_current_state_name(_animation_tree)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _pawn == null:
		return

	_sync_expression_values(delta)
	_sync_tree_parameters()
	_log_state_transition_if_needed()


func register_animation_tree(animation_tree: AnimationTree, animation_player: AnimationPlayer = null, bind_expression_base := true) -> bool:
	if animation_tree == null:
		return false

	if bind_expression_base:
		animation_tree.advance_expression_base_node = animation_tree.get_path_to(self)

	if animation_player != null:
		_set_tree_animation_player(animation_tree, animation_player)

	var tree_key := animation_tree.get_instance_id()
	_managed_trees[tree_key] = {
		"tree": animation_tree,
		"param_keys": _build_tree_parameter_keys(animation_tree),
		"resolved_param_paths": {},
	}

	animation_tree.active = true
	_sync_tree_parameters_to_entry(_managed_trees[tree_key])
	return true


func unregister_animation_tree(animation_tree: AnimationTree) -> void:
	if animation_tree == null:
		return

	var tree_key := animation_tree.get_instance_id()
	if _managed_trees.has(tree_key):
		_managed_trees.erase(tree_key)


func register_animation_player(animation_player: AnimationPlayer, animation_tree: AnimationTree = null) -> bool:
	if animation_player == null:
		return false

	var target_tree := animation_tree
	if target_tree == null:
		target_tree = _resolve_tree_for_animation_player(animation_player)
	if target_tree == null:
		return false

	return register_animation_tree(target_tree, animation_player)


func unregister_animation_player(animation_player: AnimationPlayer) -> void:
	if animation_player == null:
		return

	var target_tree := _resolve_tree_for_animation_player(animation_player)
	if target_tree != null:
		unregister_animation_tree(target_tree)


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
	expr_primary_interact_enabled = _pawn.interact_primary_enabled
	expr_secondary_interact_enabled = _pawn.interact_secondary_enabled
	expr_primary_interact_requested = _pending_primary_interact_request
	expr_secondary_interact_requested = _pending_secondary_interact_request
	_pending_primary_interact_request = false
	_pending_secondary_interact_request = false

	expr_airborne_progress = _compute_airborne_progress()


func _update_elapsed_activity_timers(moving: bool, delta: float) -> void:
	if moving:
		_time_since_last_move_seconds = 0.0
	else:
		_time_since_last_move_seconds += maxf(delta, 0.0)

	_time_since_last_jump_seconds += maxf(delta, 0.0)


func _on_pawn_jumped(_jump_velocity: float) -> void:
	_time_since_last_jump_seconds = 0.0


func _on_pawn_interacted_primary() -> void:
	_pending_primary_interact_request = true


func _on_pawn_interacted_secondary() -> void:
	_pending_secondary_interact_request = true


func play_primary_interact_effect() -> void:
	if _pawn == null:
		return

	# Animation tracks can call this method to spawn the interaction effect at the chosen timing.
	if _pawn.has_method("spawn_primary_voice_ring"):
		_pawn.call("spawn_primary_voice_ring")


func _compute_airborne_progress() -> float:
	if expr_is_on_floor:
		return -1.0

	return _pawn._normalized_air_phase * 0.5 + 0.5


func _sync_tree_parameters() -> void:
	if _pawn == null:
		return

	var stale_keys: Array[int] = []
	for tree_key in _managed_trees.keys():
		var entry = _managed_trees[tree_key]
		var tree := entry.get("tree", null) as AnimationTree
		if tree == null or not is_instance_valid(tree):
			stale_keys.append(tree_key)
			continue

		_sync_tree_parameters_to_entry(entry)

	for key in stale_keys:
		_managed_trees.erase(key)


func _set_tree_parameter(path: StringName, value: Variant) -> void:
	for entry in _managed_trees.values():
		_try_set_tree_parameter_on_entry(entry, path, value)


func _sync_tree_parameters_to_entry(entry: Dictionary) -> void:
	_set_tree_parameter_by_semantic(entry, &"air_progress", param_air_progress_path, expr_airborne_progress)


func _set_tree_parameter_on_entry(entry: Dictionary, path: StringName, value: Variant) -> void:
	_try_set_tree_parameter_on_entry(entry, path, value)


func _set_tree_parameter_by_semantic(entry: Dictionary, semantic_key: StringName, preferred_path: StringName, value: Variant) -> void:
	if not use_parameter_path_aliases:
		_set_tree_parameter_on_entry(entry, preferred_path, value)
		return

	var resolved_paths: Dictionary = entry.get("resolved_param_paths", {}) as Dictionary
	if resolved_paths.has(semantic_key):
		var cached_path := resolved_paths.get(semantic_key, &"") as StringName
		if _try_set_tree_parameter_on_entry(entry, cached_path, value):
			return
		resolved_paths.erase(semantic_key)

	var candidate_paths: Array[StringName] = [preferred_path]
	for alias_path in _get_semantic_alias_paths(semantic_key):
		if alias_path == preferred_path:
			continue
		candidate_paths.append(alias_path)

	for candidate_path in candidate_paths:
		if _try_set_tree_parameter_on_entry(entry, candidate_path, value):
			resolved_paths[semantic_key] = candidate_path
			entry["resolved_param_paths"] = resolved_paths
			return


func _get_semantic_alias_paths(semantic_key: StringName) -> Array[StringName]:
	var aliases: Array[StringName] = []
	if not _TREE_PARAM_PATH_ALIASES.has(semantic_key):
		return aliases

	var raw_aliases = _TREE_PARAM_PATH_ALIASES.get(semantic_key, [])
	if not (raw_aliases is Array):
		return aliases

	for alias_path in raw_aliases:
		aliases.append(StringName(alias_path))

	return aliases


func _try_set_tree_parameter_on_entry(entry: Dictionary, path: StringName, value: Variant) -> bool:
	var tree := entry.get("tree", null) as AnimationTree
	if tree == null or not is_instance_valid(tree):
		return false

	var key := String(path)
	if key.is_empty():
		return false

	var param_keys: Dictionary = entry.get("param_keys", {}) as Dictionary
	if param_keys.is_empty():
		return false
	if not param_keys.has(key):
		return false

	tree.set(path, value)
	return true


func _build_tree_parameter_keys(animation_tree: AnimationTree) -> Dictionary:
	var keys := {}
	if animation_tree == null:
		return keys

	for p in animation_tree.get_property_list():
		if not (p is Dictionary):
			continue
		var name_value = (p as Dictionary).get("name", "")
		var name_text := String(name_value)
		if name_text.is_empty():
			continue
		keys[name_text] = true

	return keys


func _set_tree_animation_player(animation_tree: AnimationTree, animation_player: AnimationPlayer) -> void:
	if animation_tree == null or animation_player == null:
		return

	animation_tree.anim_player = animation_tree.get_path_to(animation_player)


func _resolve_tree_animation_player(animation_tree: AnimationTree) -> AnimationPlayer:
	if animation_tree == null:
		return null
	if animation_tree.anim_player.is_empty():
		return null

	return animation_tree.get_node_or_null(animation_tree.anim_player) as AnimationPlayer


func _resolve_tree_for_animation_player(animation_player: AnimationPlayer) -> AnimationTree:
	if animation_player == null or _managed_trees.is_empty():
		return null

	for entry in _managed_trees.values():
		var tree := entry.get("tree", null) as AnimationTree
		if tree == null or not is_instance_valid(tree):
			continue
		var resolved_player := _resolve_tree_animation_player(tree)
		if resolved_player == animation_player:
			return tree

	return null


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


func _get_current_state_name(animation_tree: AnimationTree) -> StringName:
	if animation_tree == null:
		return &""

	var playback = animation_tree.get("parameters/playback")
	if playback is AnimationNodeStateMachinePlayback:
		return (playback as AnimationNodeStateMachinePlayback).get_current_node()

	return &""


func _log_state_transition_if_needed() -> void:
	if not debug_log_state_transitions:
		return
	if _pawn == null or _animation_tree == null:
		return

	var current_state := _get_current_state_name(_animation_tree)
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
