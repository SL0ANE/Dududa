extends Pawn
class_name CandleDrop


enum DropState {
	INDEPENDENT,
	ABSORBED,
}

@export_group("Absorb")
@export var absorb_animation_param_path: StringName = &"parameters/conditions/is_absorbing"
# Horizontal offset for alternating left/right layout while absorbed, in pixels.
@export var absorb_alternate_x_offset_pixels: int = 1

@export_group("Appearance")
var _sprite_presets: Array[SpriteFrames] = []
@export var sprite_presets: Array[SpriteFrames]:
	get:
		return _sprite_presets
	set(value):
		_sprite_presets = value
		_update_sprite_frames()
@export var sprite_preset_index: int = 0:
	get:
		return _sprite_preset_index
	set(value):
		_sprite_preset_index = value
		_update_sprite_frames()
var _sprite_preset_index: int = 0
@export_enum("Left", "Right") var current_facing: int = -1:
	get:
		return _current_facing
	set(value):
		_current_facing = value
		_update_facing_flip()
var _current_facing: int = -1

var state: int = DropState.INDEPENDENT
var detach_timestamp: int = -65535

var _candle_man: CandleMan = null
var _animation_tree: AnimationTree
var _independent_parent: Node
var _absorb_animating := false
var _absorb_elapsed := 0.0
var _absorb_duration_current := 0.0
var _absorb_start_global_position := Vector2.ZERO
var _notify_candle_man_on_absorb_settled := false
var _tree_param_keys := {}
var _saved_movement_enabled := true
var _saved_jump_enabled := true
var _saved_pawn_collision_mode: int = PawnCollisionMode.SOFT_PUSH
var _saved_z_index := 0
var _current_expression_source: Node = null

# Public expression value for AnimationTree transition expressions.
var expr_is_absorbing := false

# Always true, kept for compatibility with existing tree expressions.
var expr_bridge_connected = false


func _ready() -> void:
	_update_appearance()
	super._ready()
	_independent_parent = get_parent()
	_animation_tree = get_node_or_null(animation_tree_path) as AnimationTree
	_cache_tree_parameter_keys()
	_enter_independent_state()


func _exit_tree() -> void:
	_detach_from_animation_bridge(_current_expression_source)


func _physics_process(delta: float) -> void:
	if state == DropState.INDEPENDENT:
		super._physics_process(delta)
		return

	if _absorb_animating:
		_update_absorb_animation(delta)
	else:
		_snap_to_absorbed_slot()


func absorb_into(candle_man: CandleMan, absorb_duration_seconds: float, apply_candle_man_growth: bool = true) -> void:
	_absorb_into_internal(candle_man, absorb_duration_seconds, true, apply_candle_man_growth)


func absorb_into_immediate(candle_man: CandleMan, apply_candle_man_growth: bool = true) -> void:
	_absorb_into_internal(candle_man, 0.0, false, apply_candle_man_growth)


func _absorb_into_internal(candle_man: CandleMan, absorb_duration_seconds: float, animate: bool, apply_candle_man_growth: bool) -> void:
	if candle_man == null:
		return


	if state == DropState.ABSORBED and _candle_man == candle_man and (not _absorb_animating):
		return

	if state == DropState.ABSORBED:
		detach_to_independent()

	_on_absorb(candle_man)

	_current_facing = 0 if randf() < 0.5 else 1
	_sprite_preset_index = randi() % max(sprite_presets.size(), 1)
	_update_appearance()

	_candle_man = candle_man
	state = DropState.ABSORBED

	# Logical changes happen at absorb start.
	_saved_movement_enabled = movement_enabled
	_saved_jump_enabled = jump_enabled
	_saved_pawn_collision_mode = pawn_collision_mode
	_saved_z_index = z_index
	_candle_man.register_absorbed_drop(self, apply_candle_man_growth)
	_update_absorbed_z_order_from_stack_index()
	_set_collision_enabled(false)
	movement_enabled = false
	jump_enabled = false
	velocity = Vector2.ZERO

	_set_absorb_animation_flag(true)

	_absorb_duration_current = maxf(absorb_duration_seconds, 0.0)
	_notify_candle_man_on_absorb_settled = animate and _absorb_duration_current > 0.0
	if animate and _absorb_duration_current > 0.0:
		_absorb_animating = true
		_absorb_elapsed = 0.0
		_absorb_start_global_position = global_position
		return

	_finalize_absorb_visual_state()


func detach_from_candle_man_due_jump() -> void:
	if state != DropState.ABSORBED:
		return

	if _candle_man != null and _absorb_animating and _candle_man.is_bottom_absorbed_drop(self):
		_complete_absorb_animation_immediately()

	detach_to_independent()


func is_absorbed_settled() -> bool:
	return state == DropState.ABSORBED and (not _absorb_animating)


func detach_to_independent() -> void:
	if state == DropState.INDEPENDENT:
		return

	_on_detach(_candle_man)
	detach_timestamp = Time.get_ticks_msec()

	var old_candle_man: CandleMan = _candle_man
	if old_candle_man != null:
		old_candle_man.unregister_absorbed_drop(self)

	_absorb_animating = false
	_absorb_elapsed = 0.0
	_notify_candle_man_on_absorb_settled = false
	state = DropState.INDEPENDENT
	_candle_man = null

	var target_parent: Node = _independent_parent
	if old_candle_man != null and is_instance_valid(old_candle_man) and old_candle_man.get_parent() != null:
		target_parent = old_candle_man.get_parent()
	if target_parent != null and get_parent() != target_parent:
		reparent(target_parent, true)
	_independent_parent = target_parent

	_set_collision_enabled(true)
	movement_enabled = _saved_movement_enabled
	jump_enabled = _saved_jump_enabled
	_airborne_peak_y_px = global_position.y
	_airborne_start_y_px = global_position.y
	_driven_velocity = Vector2.ZERO
	_vertical_velocity = 0.0

	if pawn_collision_mode != _saved_pawn_collision_mode:
		pawn_collision_mode = _saved_pawn_collision_mode
		call_deferred("_refresh_all_pawn_collisions")
	z_index = _saved_z_index

	_enter_independent_state()


func _enter_independent_state() -> void:
	_set_absorb_animation_flag(false)
	_set_animation_expression_source(self)


func _update_absorb_animation(delta: float) -> void:
	if _candle_man == null:
		detach_to_independent()
		return

	_absorb_elapsed += maxf(delta, 0.0)
	var t := clampf(_absorb_elapsed / maxf(_absorb_duration_current, 0.0001), 0.0, 1.0)
	var eased := sin(t * PI * 0.5)
	var target_global := _get_current_absorb_target_global_position()
	global_position = _absorb_start_global_position.lerp(target_global, eased)

	if t >= 1.0:
		_finalize_absorb_visual_state()


func _finalize_absorb_visual_state() -> void:
	var should_notify_settled := _notify_candle_man_on_absorb_settled
	_notify_candle_man_on_absorb_settled = false

	_absorb_animating = false
	_absorb_elapsed = 0.0
	_absorb_duration_current = 0.0
	_set_absorb_animation_flag(false)

	if _candle_man == null:
		detach_to_independent()
		return

	var drop_root := _candle_man.drop_root as Node2D
	if drop_root != null and get_parent() != drop_root:
		reparent(drop_root, true)
	_update_absorbed_z_order_from_stack_index()

	_set_animation_expression_source(_candle_man.animation_bridge as Node)
	_snap_to_absorbed_slot()

	if should_notify_settled:
		_candle_man.on_absorbed_drop_animation_finished(self)


func _complete_absorb_animation_immediately() -> void:
	if state != DropState.ABSORBED:
		return

	if not _absorb_animating:
		return

	global_position = _get_current_absorb_target_global_position()
	_finalize_absorb_visual_state()


func _get_current_absorb_target_global_position() -> Vector2:
	if _candle_man == null:
		return global_position

	var idx: int = _candle_man.get_absorbed_drop_bottom_index(self)
	if idx < 0:
		idx = 0
	return _candle_man.get_bottom_drop_global_position(idx) + _get_alternating_absorb_offset(idx)


func _snap_to_absorbed_slot() -> void:
	if state != DropState.ABSORBED:
		return
	global_position = _get_current_absorb_target_global_position()


func _set_collision_enabled(enabled: bool) -> void:
	for collider in _get_cached_collision_shapes():
		collider.disabled = not enabled

	var target_mode := PawnCollisionMode.SOFT_PUSH if enabled else PawnCollisionMode.NO_COLLISION
	if pawn_collision_mode == target_mode:
		return

	if enabled:
		pawn_collision_mode = PawnCollisionMode.SOFT_PUSH
	else:
		pawn_collision_mode = PawnCollisionMode.NO_COLLISION

	# CandleDrop can stay in a custom physics loop while absorbed, so force a collision-table refresh.
	call_deferred("_refresh_all_pawn_collisions")


func _set_animation_expression_source(node: Node) -> void:
	if _animation_tree == null:
		return
	if node == null:
		return
	if _current_expression_source == node:
		return

	_detach_from_animation_bridge(_current_expression_source)

	_animation_tree.advance_expression_base_node = _animation_tree.get_path_to(node)
	_current_expression_source = node
	_attach_to_animation_bridge(node)


func _attach_to_animation_bridge(node: Node) -> void:
	if _animation_tree == null or node == null:
		return
	if not node.has_method("register_animation_tree"):
		return

	var animation_player := _resolve_animation_player_for_tree()
	node.call("register_animation_tree", _animation_tree, animation_player)


func _detach_from_animation_bridge(node: Node) -> void:
	if _animation_tree == null or node == null:
		return
	if not node.has_method("unregister_animation_tree"):
		return

	node.call("unregister_animation_tree", _animation_tree)


func _resolve_animation_player_for_tree() -> AnimationPlayer:
	if _animation_tree == null:
		return null
	if _animation_tree.anim_player.is_empty():
		return null

	return _animation_tree.get_node_or_null(_animation_tree.anim_player) as AnimationPlayer


func _set_absorb_animation_flag(value: bool) -> void:
	expr_is_absorbing = value
	_try_set_tree_parameter(absorb_animation_param_path, value)


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


func _update_absorbed_z_order_from_stack_index() -> void:
	if _candle_man == null:
		return

	var idx: int = int(_candle_man.call("get_absorbed_drop_bottom_index", self))
	if idx < 0:
		return

	z_index = - idx


func _get_alternating_absorb_offset(idx: int) -> Vector2:
	var x := absi(absorb_alternate_x_offset_pixels)
	if x <= 0:
		return Vector2.ZERO

	var phase := posmod(idx, 3)
	if phase == 0:
		return Vector2(-float(x), 0.0)
	if phase == 1:
		return Vector2.ZERO

	return Vector2(float(x), 0.0)

func _update_appearance() -> void:
	_update_sprite_frames()
	_update_facing_flip()


func _update_sprite_frames() -> void:
	if _sprite == null:
		return
	if sprite_presets.size() <= 0:
		return

	var preset_idx: int = clampi(sprite_preset_index, 0, sprite_presets.size() - 1)
	var preset := sprite_presets[preset_idx]
	_sprite.frames = preset


func _update_facing_flip() -> void:
	if _sprite == null:
		return

	_sprite.flip_h = current_facing > 0

func _on_absorb(man: CandleMan) -> void:
	pass

func _on_detach(man: CandleMan) -> void:
	pass