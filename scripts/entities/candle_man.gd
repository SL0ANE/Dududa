extends Pawn


@export_group("Drop Settings")
# Current remaining shrink steps.
@export var drop_count: int = 6
# Initial shrink steps applied once on spawn.
# Amount removed from body height per jump, in game units.
@export var height_per_drop: float = 0.5
# Non-candle legacy part (in game units) that must remain after all drops.
@export var legacy_height: float = 0.5
# Collider-only height offset in game units.
# Positive values make collider taller than visuals; negative values make it shorter.
@export var collider_height_shift: float = -0.0625
@export var visual_top_offset: float = 0.25
@export var visual_bottom_offset: float = 0.25

@export_group("Drop Nodes")
# Assign a Node2D whose local origin is already at visual top.
@export var visual_scale_path: NodePath = ^"VisualScaleRoot"
@export var visual_position_path: NodePath = ^"VisualPositionRoot"

@export_group("Visual")
@export var visual_drop_duration: float = 0.14

var reference_original_height: float = 2.0

var _visual_scale_root: Node2D
var _visual_position_root: Node2D
var _visual_tween: Tween

var _visual_scale_base_scale: Vector2 = Vector2.ONE
var _visual_scale_base_position: Vector2 = Vector2.ZERO
var _visual_position_base_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	super._ready()
	_visual_scale_root = get_node_or_null(visual_scale_path)
	_visual_position_root = get_node_or_null(visual_position_path)
	if _visual_scale_root and _visual_position_root:
		_visual_scale_base_scale = _visual_scale_root.scale
		_visual_scale_base_position = _visual_scale_root.position
		_visual_position_base_position = _visual_position_root.position

	else:
		push_warning("CandleMan: visual roots not found; visual height changes are disabled.")

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
	
	var current_collider_height_units := _get_collider_height_units()
	if current_collider_height_units <= 0.0:
		return

	# Visuals always follow exact computed gameplay height.
	var target_height_units := legacy_height + drop_count * height_per_drop
	# Collider can be offset from visuals, but position compensation uses collider delta.
	var target_collider_height_units := maxf(target_height_units + collider_height_shift, 0.0)

	if not is_equal_approx(current_collider_height_units, target_collider_height_units):
		var collider_height_delta_units := target_collider_height_units - current_collider_height_units
		_set_collider_height_units(target_collider_height_units)
		var collider_height_delta_px := GameUnits.units_to_pixels(collider_height_delta_units)
		if keep_top:
			global_position.y += collider_height_delta_px

	_apply_visual_height(target_height_units, keep_top, animate_visual)
	_sync_jump_enabled_state()


func _apply_visual_height(target_height_units: float, keep_top: bool, animate: bool) -> void:
	if _visual_scale_root == null or _visual_position_root == null:
		return

	if _visual_tween:
		_visual_tween.kill()
		_visual_tween = null

	var safe_original_height := maxf(reference_original_height - visual_top_offset + visual_bottom_offset, 0.0001)
	var visual_height_units := maxf(target_height_units - visual_top_offset + visual_bottom_offset, 0.0)
	var ratio := maxf(visual_height_units / safe_original_height, 0.0)
	var target_scale := Vector2(_visual_scale_base_scale.x, _visual_scale_base_scale.y * ratio)
	var target_scale_position := Vector2(_visual_scale_base_position.x, _visual_scale_base_position.y - GameUnits.units_to_pixels(visual_height_units - safe_original_height) * 0.5)
	var target_visual_position := _compute_visual_position_root_position(target_height_units)
	_visual_position_root.position = target_visual_position
	var offset = 0.0;
	if keep_top:
		offset -= (target_scale.y - _visual_scale_root.scale.y) * GameUnits.units_to_pixels(reference_original_height) * 0.5
	_visual_scale_root.position = Vector2(_visual_scale_base_position.x, target_scale_position.y + offset)

	if not animate:
		_visual_scale_root.scale = target_scale
		_visual_scale_root.position = target_scale_position
		return

	_visual_tween = create_tween()
	_visual_tween.set_trans(Tween.TRANS_SINE)
	_visual_tween.set_ease(Tween.EASE_OUT)
	_visual_tween.parallel().tween_property(_visual_scale_root, "scale", target_scale, visual_drop_duration)
	_visual_tween.parallel().tween_property(_visual_scale_root, "position", target_scale_position, visual_drop_duration)


func _compute_visual_position_root_position(target_height_units: float) -> Vector2:
	if _visual_position_root == null:
		return Vector2.ZERO

	var original_px := GameUnits.units_to_pixels(reference_original_height)
	var target_px := GameUnits.units_to_pixels(target_height_units)
	return Vector2(
		_visual_position_base_position.x,
		_visual_position_base_position.y + original_px - target_px
	)


func _sync_jump_enabled_state() -> void:
	jump_enabled = drop_count > 0 and height_per_drop > 0.0
