extends Node
class_name PawnAnimationTreeBridge

enum DriveMode {
	STATE_MACHINE,
	DIRECT_ANIMATION_PLAYER,
}

@export_group("Nodes")
@export var pawn_path: NodePath = ^".."
@export var animation_tree_path: NodePath = ^"../AnimationTree"
@export var animation_player_path: NodePath = ^"../AnimationPlayer"

@export_group("Drive")
@export_enum("StateMachine", "DirectAnimationPlayer") var drive_mode: int = DriveMode.DIRECT_ANIMATION_PLAYER
@export var direct_mode_jump_hold_time := 0.08
@export var auto_fallback_to_direct := true
@export var direct_move_speed_threshold_pixels := 1.0

@export_group("State Machine Paths")
# AnimationTree property path for locomotion state machine playback object.
# For a root-level state machine use parameters/playback.
# For a nested state machine use something like parameters/Locomotion/playback.
# This is what the bridge calls travel(...) on for Idle/Move/Air/Jump switching.
@export var locomotion_playback_path: StringName = &"parameters/Locomotion/playback"

@export_group("Locomotion States")
@export var idle_state: StringName = &"Idle"
@export var move_state: StringName = &"Move"
@export var air_state: StringName = &"Air"
@export var jump_state: StringName = &"Jump"

# Push state in the same locomotion state machine.
@export_group("Push State")
@export var pushed_state: StringName = &"Pushed"

var _pawn: Pawn
var _animation_tree: AnimationTree
var _animation_player: AnimationPlayer
var _locomotion_sm: AnimationNodeStateMachinePlayback
var _is_pushed_active := false
var _jump_hold_left := 0.0

const ROOT_PLAYBACK_PATH: StringName = &"parameters/playback"


func _ready() -> void:
	_pawn = get_node_or_null(pawn_path) as Pawn
	_animation_tree = get_node_or_null(animation_tree_path) as AnimationTree
	_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer

	if _pawn == null:
		push_warning("PawnAnimationTreeBridge: pawn_path is invalid.")
		return
	if _animation_tree == null:
		push_warning("PawnAnimationTreeBridge: animation_tree_path is invalid.")
		return
	if drive_mode == DriveMode.DIRECT_ANIMATION_PLAYER and _animation_player == null:
		push_warning("PawnAnimationTreeBridge: animation_player_path is invalid for direct mode.")
		return

	_bind_expression_base_if_empty()
	if drive_mode == DriveMode.STATE_MACHINE:
		_cache_playbacks()
		if _locomotion_sm == null and auto_fallback_to_direct and _animation_player:
			push_warning("PawnAnimationTreeBridge: locomotion playback not found, auto-fallback to direct mode.")
			drive_mode = DriveMode.DIRECT_ANIMATION_PLAYER
	_connect_pawn_signals()
	set_physics_process(drive_mode == DriveMode.DIRECT_ANIMATION_PLAYER)
	# Parent Pawn._ready may force AnimationTree.active = true.
	# Apply our drive-mode final state after ready order settles.
	call_deferred("_apply_animation_tree_drive_state")


func _apply_animation_tree_drive_state() -> void:
	if _animation_tree == null:
		return

	_animation_tree.active = drive_mode == DriveMode.STATE_MACHINE


func _physics_process(delta: float) -> void:
	if drive_mode != DriveMode.DIRECT_ANIMATION_PLAYER:
		return
	if _pawn == null or _animation_player == null:
		return
	if _animation_tree and _animation_tree.active:
		# Keep direct mode authoritative over animation output.
		_animation_tree.active = false

	_jump_hold_left = maxf(_jump_hold_left - delta, 0.0)

	# Keep pushed clip active while pushed lifecycle is active.
	if _is_pushed_active:
		_play_animation(pushed_state)
		return

	# Prevent immediate override right after jump trigger.
	if _jump_hold_left > 0.0:
		return

	# Hard sync by runtime body state (not by cached anim flags),
	# so locomotion clip selection stays correct even when signals are missed.
	var grounded := _pawn.is_on_floor()
	if not grounded:
		_play_animation(air_state)
		return

	var moving_by_speed := absf(_pawn.velocity.x) > maxf(direct_move_speed_threshold_pixels, 0.0)
	if moving_by_speed:
		_play_animation(move_state)
	else:
		_play_animation(idle_state)


func _bind_expression_base_if_empty() -> void:
	if _animation_tree.advance_expression_base_node.is_empty():
		_animation_tree.advance_expression_base_node = _animation_tree.get_path_to(_pawn)


func _cache_playbacks() -> void:
	var locomotion_playback = _animation_tree.get(locomotion_playback_path)
	if not (locomotion_playback is AnimationNodeStateMachinePlayback):
		# Compatibility: if no nested locomotion state machine is configured,
		# fall back to root playback so a flat/root state machine works out of the box.
		locomotion_playback = _animation_tree.get(ROOT_PLAYBACK_PATH)

	if locomotion_playback is AnimationNodeStateMachinePlayback:
		_locomotion_sm = locomotion_playback as AnimationNodeStateMachinePlayback


func _connect_pawn_signals() -> void:
	_pawn.move_started.connect(_on_move_started)
	_pawn.move_active.connect(_on_move_active)
	_pawn.move_ended.connect(_on_move_ended)
	_pawn.jumped.connect(_on_jumped)
	_pawn.landed.connect(_on_landed)
	_pawn.pushed_started.connect(_on_pushed_started)
	_pawn.pushed_ended.connect(_on_pushed_ended)


func _on_move_started(_speed: float, _input_axis: float, grounded: bool) -> void:
	if _is_pushed_active:
		return

	if drive_mode == DriveMode.DIRECT_ANIMATION_PLAYER:
		if grounded:
			_play_animation(move_state)
		else:
			_play_animation(air_state)
		return

	if _locomotion_sm == null:
		return

	if grounded:
		_locomotion_sm.travel(move_state)
	else:
		_locomotion_sm.travel(air_state)


func _on_move_active(_speed: float, _input_axis: float, grounded: bool) -> void:
	if _is_pushed_active:
		return

	if drive_mode == DriveMode.DIRECT_ANIMATION_PLAYER:
		if grounded:
			_play_animation(move_state)
		else:
			_play_animation(air_state)
		return

	if _locomotion_sm == null:
		return

	if grounded:
		_locomotion_sm.travel(move_state)
	else:
		_locomotion_sm.travel(air_state)


func _on_move_ended(_speed: float, _input_axis: float, grounded: bool) -> void:
	if _is_pushed_active:
		return

	if drive_mode == DriveMode.DIRECT_ANIMATION_PLAYER:
		if grounded:
			_play_animation(idle_state)
		return

	if _locomotion_sm == null:
		return

	if grounded:
		_locomotion_sm.travel(idle_state)


func _on_jumped(_jump_velocity: float) -> void:
	if _is_pushed_active:
		return

	if drive_mode == DriveMode.DIRECT_ANIMATION_PLAYER:
		_jump_hold_left = maxf(direct_mode_jump_hold_time, 0.0)
		_play_animation(jump_state, true)
		return

	if _locomotion_sm == null:
		return

	_locomotion_sm.travel(jump_state)


func _on_landed(_impact_velocity: Vector2) -> void:
	if _is_pushed_active:
		return

	_travel_locomotion_from_pawn_state()


func _travel_locomotion_from_pawn_state() -> void:
	if not _pawn.anim_is_on_floor:
		if drive_mode == DriveMode.DIRECT_ANIMATION_PLAYER:
			_play_animation(air_state)
		elif _locomotion_sm:
			_locomotion_sm.travel(air_state)
		return

	if _pawn.anim_is_moving:
		if drive_mode == DriveMode.DIRECT_ANIMATION_PLAYER:
			_play_animation(move_state)
		elif _locomotion_sm:
			_locomotion_sm.travel(move_state)
	else:
		if drive_mode == DriveMode.DIRECT_ANIMATION_PLAYER:
			_play_animation(idle_state)
		elif _locomotion_sm:
			_locomotion_sm.travel(idle_state)


func _on_pushed_started(_other: Pawn, _mode: int, _direction: float) -> void:
	_is_pushed_active = true

	if drive_mode == DriveMode.DIRECT_ANIMATION_PLAYER:
		_play_animation(pushed_state, true)
		return

	if _locomotion_sm == null:
		return

	_locomotion_sm.travel(pushed_state)


func _on_pushed_ended(_other: Pawn, _mode: int) -> void:
	_is_pushed_active = false

	_travel_locomotion_from_pawn_state()


func _play_animation(state_name: StringName, force_restart := false) -> void:
	if _animation_player == null:
		return

	var clip := _resolve_clip_name(state_name)
	if clip.is_empty():
		return

	if not _animation_player.has_animation(clip):
		return

	if not force_restart and _animation_player.current_animation == clip and _animation_player.is_playing():
		return

	_animation_player.play(clip)


func _resolve_clip_name(state_name: StringName) -> String:
	# Fast path: state name equals AnimationPlayer clip name.
	var state_text := String(state_name)
	if not state_text.is_empty() and _animation_player and _animation_player.has_animation(state_text):
		return state_text

	# Fallback: read mapped clip from AnimationTree StateMachine state node.
	if _animation_tree == null:
		return ""
	if not (_animation_tree.tree_root is AnimationNodeStateMachine):
		return ""

	var sm := _animation_tree.tree_root as AnimationNodeStateMachine
	if not sm.has_node(state_name):
		return ""

	var state_node := sm.get_node(state_name)
	if state_node is AnimationNodeAnimation:
		return String((state_node as AnimationNodeAnimation).animation)

	return ""
