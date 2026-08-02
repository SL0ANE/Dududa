extends Pawn


@export_group("Drop Settings")
# Current remaining shrink steps.
@export var drop_count: int = 6
# Initial shrink steps applied once on spawn.
# Amount removed from body height per jump, in game units.
@export var height_per_drop: float = 0.5
# Non-candle legacy part (in game units) that must remain after all drops.
@export var legacy_height: float = 0.5

@export_group("Drop Nodes")
@export var collision_shape_path: NodePath = ^"CollisionShape2D"
# Assign a Node2D whose local origin is already at visual top.
@export var visual_root_path: NodePath = ^"VisualTopAnchor"

@export_group("Visual")
@export var visual_drop_duration: float = 0.14

var _visual_root: Node2D
var _visual_tween: Tween

var _visual_base_scale: Vector2 = Vector2.ONE
var _visual_base_position: Vector2 = Vector2.ZERO
var _visual_original_height: float = 2.0

func _ready() -> void:
	super._ready()
	_visual_root = _resolve_visual_root()
	if _visual_root:
		_visual_base_scale = _visual_root.scale
		_visual_base_position = _visual_root.position
	else:
		push_warning("CandleMan: visual root not found; visual height changes are disabled.")

	var current_height_units := _get_collider_height_units()
	if current_height_units <= 0.0:
		push_warning("CandleMan: unsupported or missing CollisionShape2D; drop behavior disabled.")
		return

	_sync_jump_enabled_state()
	# On initialization keep the bottom edge fixed and apply visual scale immediately.
	_apply_drop(drop_count, false, false)


func on_jump(_jump_velocity: float) -> void:
	if height_per_drop <= 0.0:
		return
	if drop_count <= 0:
		return

	# During gameplay keep the top edge fixed while shrinking.
	_apply_drop(drop_count - 1, true, true)


func _apply_drop(target_remaining_drop_count: int, keep_top: bool, animate_visual: bool) -> void:
	if height_per_drop <= 0.0:
		return

	drop_count = max(target_remaining_drop_count, 0)
	
	var current_height_units := _get_collider_height_units()
	if current_height_units <= 0.0:
		return

	var target_height_units := legacy_height + drop_count * height_per_drop

	if not is_equal_approx(current_height_units, target_height_units):
		var height_delta_units := target_height_units - current_height_units
		_set_collider_height_units(target_height_units)
		var height_delta_px := GameUnits.units_to_pixels(height_delta_units)
		if keep_top:
			global_position.y += height_delta_px * 0.5
		else:
			global_position.y -= height_delta_px * 0.5

	var target_ratio := target_height_units / _visual_original_height
	_apply_visual_height(target_ratio, animate_visual, keep_top)

	_sync_jump_enabled_state()


func _apply_visual_height(target_ratio: float, animate: bool, keep_top: bool) -> void:
	if _visual_root == null:
		return

	if _visual_tween:
		_visual_tween.kill()
		_visual_tween = null

	var ratio := maxf(target_ratio, 0.0)
	var target_scale := Vector2(_visual_base_scale.x, _visual_base_scale.y * ratio)
	var target_position := _compute_visual_anchor_position(target_scale.y, keep_top)
	if not animate:
		_visual_root.scale = target_scale
		_visual_root.position = target_position
		return

	_visual_tween = create_tween()
	_visual_tween.set_trans(Tween.TRANS_SINE)
	_visual_tween.set_ease(Tween.EASE_OUT)
	_visual_tween.parallel().tween_property(_visual_root, "scale", target_scale, visual_drop_duration)
	_visual_tween.parallel().tween_property(_visual_root, "position", target_position, visual_drop_duration)


func _compute_visual_anchor_position(target_scale_y: float, keep_top: bool) -> Vector2:
	if _visual_root == null:
		return Vector2.ZERO

	var delta_scale_y := target_scale_y - _visual_base_scale.y
	var delta_y := _visual_original_height * delta_scale_y * 0.5
	if keep_top:
		return Vector2(_visual_base_position.x, _visual_base_position.y + delta_y)
	return Vector2(_visual_base_position.x, _visual_base_position.y - delta_y)


func _sync_jump_enabled_state() -> void:
	jump_enabled = drop_count > 0 and height_per_drop > 0.0


func _get_collider_height_px() -> float:
	var collision_shape := _get_collision_shape_node()
	if collision_shape == null:
		return 0.0
	if collision_shape.shape == null:
		return 0.0

	var shape := collision_shape.shape
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.y
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		# Use end-to-end height for consistent gameplay semantics.
		return capsule.height + capsule.radius * 2.0

	return 0.0


func _get_collider_height_units() -> float:
	return GameUnits.pixels_to_units(_get_collider_height_px())


func _set_collider_height_units(new_height_units: float) -> void:
	var collision_shape := _get_collision_shape_node()
	if collision_shape == null:
		return
	if collision_shape.shape == null:
		return

	var new_height_px := GameUnits.units_to_pixels(new_height_units)
	var shape := collision_shape.shape
	if shape is RectangleShape2D:
		var rect := shape as RectangleShape2D
		rect.size.y = maxf(new_height_px, 1.0)
		return

	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		capsule.height = maxf(new_height_px, 0.0)


func _get_collision_shape_node() -> CollisionShape2D:
	var node := get_node_or_null(collision_shape_path)
	if node is CollisionShape2D:
		return node as CollisionShape2D
	return null


func _resolve_visual_root() -> Node2D:
	if not visual_root_path.is_empty():
		var visual_node := get_node_or_null(visual_root_path)
		if visual_node is Node2D:
			return visual_node as Node2D

	if not sprite_path.is_empty():
		var sprite_node := get_node_or_null(sprite_path)
		if sprite_node is Node2D:
			return sprite_node as Node2D

	var fallback := get_node_or_null(^"AnimatedSprite2D")
	if fallback is Node2D:
		return fallback as Node2D

	return null