extends Pawn
class_name CandleMan


const JUMP_SFX_STREAMS: Array[AudioStream] = [
	preload("res://sound_effects/character/jump/7.wav"),
	preload("res://sound_effects/character/jump/6.wav"),
	preload("res://sound_effects/character/jump/5.wav"),
	preload("res://sound_effects/character/jump/4.wav"),
	preload("res://sound_effects/character/jump/3.wav"),
	preload("res://sound_effects/character/jump/2.wav"),
	preload("res://sound_effects/character/jump/1.wav"),
	preload("res://sound_effects/character/jump/0.wav"),
]

const INTERACT_SFX_STREAMS: Array[AudioStream] = [
	preload("res://sound_effects/character/sing/0.wav"),
	preload("res://sound_effects/character/sing/1.wav"),
	preload("res://sound_effects/character/sing/2.wav"),
	preload("res://sound_effects/character/sing/3.wav"),
	# preload("res://sound_effects/character/sing/4.wav"),
	# preload("res://sound_effects/character/sing/5.wav"),
	# preload("res://sound_effects/character/sing/6.wav"),
	# preload("res://sound_effects/character/sing/7.wav"),
]

const ABSORB_SFX_STREAMS: Array[AudioStream] = [
	preload("res://sound_effects/skull_stacking/0.wav"),
	preload("res://sound_effects/skull_stacking/1.wav"),
	preload("res://sound_effects/skull_stacking/2.wav"),
	preload("res://sound_effects/skull_stacking/3.wav"),
	preload("res://sound_effects/skull_stacking/4.wav"),
	preload("res://sound_effects/skull_stacking/5.wav"),
	preload("res://sound_effects/skull_stacking/6.wav"),
	preload("res://sound_effects/skull_stacking/7.wav"),
]


@export_group("Drop Settings")
# Current remaining shrink steps.
@export var drop_count: int = 6
# Duration for CandleDrop absorb animation (seconds).
@export var absorb_duration: float = 0.25
# Extra absorb animation time (seconds) added per already absorbed settled drop.
@export var absorb_duration_per_absorbed_drop: float = 0.1
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
@export var drop_root_path: NodePath = ^"DropRoot"
@export var animation_bridge_path: NodePath = ^"AnimationBridge"

@export_group("Visual")
@export var visual_scale_tween_duration: float = 0.5
@export var visual_position_tween_duration: float = 0.25

@export_group("Jump Settings")
@export var jump_height_on_no_drops: float = 0.6
@export var jump_time_to_peak_on_no_drops: float = 0.175
@export var jump_time_to_fall_on_no_drops: float = 0.15

@export_group("Drop Initialization")
@export var drops_on_initialization: Array[PackedScene] = []

@export_group("Interaction")
@export var voice_ring: PackedScene = preload("res://prefabs/entities/depth_control/voice_ring.tscn")
@export var voice_ring_radius_end: float = 2.0
@export var interact_sfx_player_path: NodePath = ^"SoundEffects/SFXSing"
# Optional local point for primary interaction ring spawn.
@export var voice_ring_spawn_point_path: NodePath

@export_group("Absorb SFX")
@export var absorb_sfx_player_path: NodePath = ^"SoundEffects/SFXAbsorb"

var reference_original_height: float = 2.0

var _visual_scale_root: Node2D
var _visual_position_root: Node2D
var _visual_tween: Tween

var _visual_scale_base_scale: Vector2 = Vector2.ONE
var _visual_scale_base_position: Vector2 = Vector2.ZERO
var _visual_position_base_position: Vector2 = Vector2.ZERO

var _original_jump_height: float = 0.0
var _original_jump_time_to_peak: float = 0.0
var _original_jump_time_to_fall: float = 0.0
var _interact_sfx_player: AudioStreamPlayer2D
var _absorb_sfx_player: AudioStreamPlayer2D
var drop_root: Node2D
var animation_bridge: Node
var _absorbed_drops: Array[CandleDrop] = []
var _pending_absorb_drops: Array[CandleDrop] = []
var _active_voice_rings := {}


func _physics_process(delta: float) -> void:
	_update_voice_ring_enabled_state()
	_absorb_pending_drops()
	super._physics_process(delta)

func _ready() -> void:
	super._ready()
	_visual_scale_root = get_node_or_null(visual_scale_path)
	_visual_position_root = get_node_or_null(visual_position_path)
	drop_root = get_node_or_null(drop_root_path) as Node2D
	animation_bridge = get_node_or_null(animation_bridge_path)
	if _visual_scale_root and _visual_position_root:
		_visual_scale_base_scale = _visual_scale_root.scale
		_visual_scale_base_position = _visual_scale_root.position
		_visual_position_base_position = _visual_position_root.position

	else:
		push_warning("CandleMan: visual roots not found; visual height changes are disabled.")

	if drop_root == null:
		push_warning("CandleMan: drop_root_path is invalid.")
	if animation_bridge == null:
		push_warning("CandleMan: animation_bridge_path is invalid.")

	_original_jump_height = jump_height
	_original_jump_time_to_peak = jump_time_to_peak
	_original_jump_time_to_fall = jump_time_to_fall
	_interact_sfx_player = get_node_or_null(interact_sfx_player_path) as AudioStreamPlayer2D
	_absorb_sfx_player = get_node_or_null(absorb_sfx_player_path) as AudioStreamPlayer2D

	var current_height_units := _get_collider_height_units()
	if current_height_units <= 0.0:
		push_warning("CandleMan: unsupported or missing CollisionShape2D; drop behavior disabled.")
		return

	_sync_jump_state()
	# On initialization keep the bottom edge fixed and apply visual scale immediately.
	_apply_drop(drop_count, false, false)
	_spawn_absorbed_drops_on_initialization()


func on_jump(_jump_velocity: float) -> void:
	super.on_jump(_jump_velocity)
	_request_detach_bottom_drop_on_jump()

	if height_per_drop <= 0.0:
		return
	if drop_count <= 0:
		return

	# During gameplay keep the top edge fixed while shrinking.
	_apply_drop(drop_count - 1, true, true)


func on_interact_primary() -> void:
	# Primary interaction intent is routed through Pawn.interacted_primary to AnimationBridge.
	pass


func _get_jump_sfx_stream_for_jump(_jump_velocity: float) -> AudioStream:
	var sfx_index := _map_drop_count_to_sfx_index(drop_count)
	if sfx_index < 0 or sfx_index >= JUMP_SFX_STREAMS.size():
		return null

	return JUMP_SFX_STREAMS[sfx_index]


func _map_drop_count_to_sfx_index(remaining_drop_count: int) -> int:
	# 0 drop -> 7.wav, 7+ drop -> 0.wav
	return clampi(remaining_drop_count, 0, 7)


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
		if keep_top and (collider_height_delta_px < 0.0 or !animate_visual):
			global_position.y += collider_height_delta_px

	_apply_visual_height(target_height_units, keep_top, animate_visual)
	_sync_jump_state()


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
	var offset = 0.0;
	if keep_top:
		offset -= (target_scale.y - _visual_scale_root.scale.y) * GameUnits.units_to_pixels(reference_original_height) * 0.5
	_visual_scale_root.position = Vector2(_visual_scale_base_position.x, target_scale_position.y + offset)

	if not animate:
		_visual_position_root.position = target_visual_position
		_visual_scale_root.scale = target_scale
		_visual_scale_root.position = target_scale_position
		return

	var scale_duration := maxf(visual_scale_tween_duration, 0.0)

	var position_duration := maxf(visual_position_tween_duration, 0.0)

	_visual_tween = create_tween()
	_visual_tween.set_trans(Tween.TRANS_SINE)
	_visual_tween.set_ease(Tween.EASE_OUT)
	if scale_duration > 0.0:
		_visual_tween.parallel().tween_property(_visual_scale_root, "scale", target_scale, scale_duration)
		_visual_tween.parallel().tween_property(_visual_scale_root, "position", target_scale_position, scale_duration)
	else:
		_visual_scale_root.scale = target_scale
		_visual_scale_root.position = target_scale_position

	if position_duration > 0.0:
		_visual_tween.parallel().tween_property(_visual_position_root, "position", target_visual_position, position_duration)
	else:
		_visual_position_root.position = target_visual_position


func _compute_visual_position_root_position(target_height_units: float) -> Vector2:
	if _visual_position_root == null:
		return Vector2.ZERO

	var original_px := GameUnits.units_to_pixels(reference_original_height)
	var target_px := GameUnits.units_to_pixels(target_height_units)
	return Vector2(
		_visual_position_base_position.x,
		_visual_position_base_position.y + original_px - target_px
	)


func _sync_jump_state() -> void:
	if drop_count <= 0:
		if (jump_height_on_no_drops <= 0):
			jump_enabled = false
		jump_height = jump_height_on_no_drops
		jump_time_to_peak = jump_time_to_peak_on_no_drops
		jump_time_to_fall = jump_time_to_fall_on_no_drops
	else:
		jump_enabled = true
		jump_height = _original_jump_height
		jump_time_to_peak = _original_jump_time_to_peak
		jump_time_to_fall = _original_jump_time_to_fall

func _update_voice_ring_enabled_state() -> void:
	interact_primary_enabled = is_on_floor()

	if not interact_primary_enabled:
		for ring in _active_voice_rings.keys():
			var vr := ring as VoiceRing
			if vr != null and is_instance_valid(vr):
				vr.lock_radius_at_current_progress()

func spawn_primary_voice_ring() -> void:

	if voice_ring == null:
		push_warning("CandleMan: voice_ring is not assigned.")
		return
	if not _validate_voice_ring_scene_root():
		return

	var spawn_parent := get_tree().current_scene
	if spawn_parent == null:
		spawn_parent = get_tree().root
	if spawn_parent == null:
		push_warning("CandleMan: unable to spawn voice ring because no scene parent exists.")
		return

	var spawned_any := false
	spawned_any = _spawn_voice_ring_at_configured_point(spawn_parent) or spawned_any
	# spawned_any = _spawn_voice_ring_at_each_drop_midpoint(spawn_parent) or spawned_any
	if not spawned_any:
		spawned_any = _spawn_voice_ring_at(spawn_parent, global_position)

	if not spawned_any:
		return

	_play_primary_interact_sfx()


func _validate_voice_ring_scene_root() -> bool:
	var test_instance := voice_ring.instantiate()
	if test_instance == null:
		push_warning("CandleMan: failed to instantiate voice_ring scene.")
		return false
	if not (test_instance is Node2D):
		push_warning("CandleMan: voice_ring root must be Node2D.")
		test_instance.queue_free()
		return false

	test_instance.queue_free()
	return true


func _spawn_voice_ring_at(spawn_parent: Node, spawn_position: Vector2) -> bool:
	var instance := voice_ring.instantiate()
	if not (instance is VoiceRing):
		if instance != null and is_instance_valid(instance):
			instance.queue_free()
		return false

	var ring := instance as VoiceRing
	ring.configure_target_radius_end(maxf(voice_ring_radius_end, 0.0))
	spawn_parent.add_child(ring)
	ring.global_position = spawn_position

	ring.on_hit_pawn.connect(_absorb_drop)
	ring.on_progress_end.connect(_on_voice_ring_progress_end.bind(ring), CONNECT_ONE_SHOT)
	ring.tree_exiting.connect(_on_voice_ring_tree_exiting.bind(ring), CONNECT_ONE_SHOT)
	_active_voice_rings[ring] = true

	return true


func _on_voice_ring_progress_end(ring: VoiceRing) -> void:
	if _active_voice_rings.has(ring):
		_active_voice_rings.erase(ring)


func _on_voice_ring_tree_exiting(ring: VoiceRing) -> void:
	if _active_voice_rings.has(ring):
		_active_voice_rings.erase(ring)

func _absorb_drop(pawn: Pawn, _radius: float, emit_timestamp: int) -> void:
	# print("CandleMan: _absorb_drop called with pawn: ", pawn, ", radius: ", radius)
	if pawn == null:
		return
	if not (pawn is CandleDrop):
		return

	var drop := pawn as CandleDrop
	if drop.state != CandleDrop.DropState.INDEPENDENT:
		return

	if absi(emit_timestamp - drop.detach_timestamp) < 500:
		# print("CandleMan: Ignoring absorb for recently detached drop. emit_timestamp: ", emit_timestamp, ", drop.detach_timestamp: ", drop.detach_timestamp)
		return

	if _pending_absorb_drops.has(drop):
		return

	_pending_absorb_drops.append(drop)


func _spawn_voice_ring_at_configured_point(spawn_parent: Node) -> bool:
	if voice_ring_spawn_point_path.is_empty():
		return false

	var point_node := get_node_or_null(voice_ring_spawn_point_path) as Node2D
	if point_node == null:
		return false

	return _spawn_voice_ring_at(spawn_parent, point_node.global_position)


func _spawn_voice_ring_at_each_drop_midpoint(spawn_parent: Node) -> bool:
	var step_px := GameUnits.units_to_pixels(maxf(height_per_drop, 0.0))
	if step_px <= 0.0:
		return false

	var spawned_any := false
	for drop in _absorbed_drops:
		if drop == null or not is_instance_valid(drop):
			continue

		# During absorb animation, current global_position is transient.
		# Prefer the absorbed slot target so ring anchors stay stable.
		var drop_bottom := drop.global_position
		drop_bottom = drop._get_current_absorb_target_global_position()
		var drop_mid := drop_bottom + Vector2(0.0, -step_px * 0.5)
		spawned_any = _spawn_voice_ring_at(spawn_parent, drop_mid) or spawned_any

	# Fallback keeps behavior usable even before absorbed drop nodes are registered.
	if not spawned_any:
		for i in range(maxi(drop_count, 0)):
			var drop_bottom_fallback := get_bottom_drop_global_position(i)
			var drop_mid_fallback := drop_bottom_fallback + Vector2(0.0, -step_px * 0.5)
			spawned_any = _spawn_voice_ring_at(spawn_parent, drop_mid_fallback) or spawned_any

	return spawned_any


func _play_primary_interact_sfx() -> void:
	if _interact_sfx_player == null:
		return

	var stream_to_play := _get_primary_interact_sfx_stream(drop_count)
	if stream_to_play == null:
		stream_to_play = _interact_sfx_player.stream
	if stream_to_play == null:
		return

	if _interact_sfx_player.stream != stream_to_play:
		_interact_sfx_player.stream = stream_to_play
	_interact_sfx_player.play()


func _get_primary_interact_sfx_stream(remaining_drop_count: int) -> AudioStream:
	var sfx_index := _map_drop_count_to_sfx_index(remaining_drop_count)
	if INTERACT_SFX_STREAMS.size() == 0:
		return null
	
	sfx_index = clampi(sfx_index, 0, INTERACT_SFX_STREAMS.size() - 1)

	return INTERACT_SFX_STREAMS[sfx_index]

func _absorb_pending_drops() -> void:
	if _pending_absorb_drops.is_empty():
		return

	var incoming_drop_count: int = 0
	var incoming_drop_support_flags := {}

	for drop in _pending_absorb_drops:
		if drop == null or not is_instance_valid(drop):
			continue
		incoming_drop_count += 1
		incoming_drop_support_flags[drop] = false

	if incoming_drop_count <= 0:
		_pending_absorb_drops.clear()
		return

	var standing_only_on_incoming_drops := true
	var support_colliders := get_floor_support_colliders_cached()
	if support_colliders.is_empty():
		standing_only_on_incoming_drops = false

	for collider in support_colliders:
		if collider is CandleDrop:
			var floor_drop := collider as CandleDrop
			if not incoming_drop_support_flags.has(floor_drop):
				standing_only_on_incoming_drops = false
				break

			incoming_drop_support_flags[floor_drop] = true
			continue

		standing_only_on_incoming_drops = false
		break

	if standing_only_on_incoming_drops:
		for drop in incoming_drop_support_flags:
			if not incoming_drop_support_flags[drop]:
				# print("CandleMan: standing on non-supported incoming drop: ", drop)
				standing_only_on_incoming_drops = false
				break

	for drop in _pending_absorb_drops:
		if drop == null or not is_instance_valid(drop):
			continue
		var effective_absorb_duration := _compute_absorb_duration_for_new_drop()
		drop.absorb_into(self, effective_absorb_duration, true)

	# print("Absorbing %d drops. Standing only on incoming drops: %s" % [incoming_drop_count, standing_only_on_incoming_drops])
	_apply_drop(drop_count + incoming_drop_count, true, !standing_only_on_incoming_drops)
	_pending_absorb_drops.clear()
func register_absorbed_drop(drop: CandleDrop, apply_height_and_count: bool = true) -> void:
	if drop == null:
		return
	if _absorbed_drops.has(drop):
		return

	# Keep order from top to bottom; newly absorbed drops are appended as the new bottom.
	_absorbed_drops.append(drop)
	if apply_height_and_count:
		_play_absorb_sfx_for_drop_index(_absorbed_drops.size() - 1)
		# _apply_drop(drop_count + 1, true, true)


func on_absorbed_drop_animation_finished(drop: CandleDrop) -> void:
	if drop == null:
		return

	var absorbed_drop_bottom_index := get_absorbed_drop_bottom_index(drop)
	if absorbed_drop_bottom_index < 0:
		return

	# _play_absorb_sfx_for_drop_index(absorbed_drop_bottom_index)


func unregister_absorbed_drop(drop: CandleDrop) -> void:
	if drop == null:
		return

	var idx := _absorbed_drops.find(drop)
	if idx < 0:
		return

	_absorbed_drops.remove_at(idx)


func is_bottom_absorbed_drop(drop: CandleDrop) -> bool:
	if drop == null:
		return false
	if _absorbed_drops.is_empty():
		return false

	return _absorbed_drops[_absorbed_drops.size() - 1] == drop


func get_absorbed_drop_bottom_index(drop: CandleDrop) -> int:
	if drop == null:
		return -1

	return _absorbed_drops.find(drop)


func get_bottom_drop_global_position(bottom_index: int = 0) -> Vector2:
	var clamped_index := maxi(bottom_index, 0)
	var step_units := maxf(height_per_drop, 0.0)
	var step_px := GameUnits.units_to_pixels(step_units)

	if drop_root != null and is_instance_valid(drop_root):
		return drop_root.to_global(Vector2(0.0, step_px * float(clamped_index)))

	return global_position + Vector2(0.0, step_px * float(clamped_index))


func _request_detach_bottom_drop_on_jump() -> void:
	if _absorbed_drops.is_empty():
		return

	var bottom := _absorbed_drops[_absorbed_drops.size() - 1]
	if bottom == null or not is_instance_valid(bottom):
		_absorbed_drops.remove_at(_absorbed_drops.size() - 1)
		return

	bottom.detach_from_candle_man_due_jump()


func _spawn_absorbed_drops_on_initialization() -> void:
	var spawn_count := maxi(drop_count, 0)
	if spawn_count <= 0:
		return

	if drops_on_initialization.is_empty():
		push_warning("CandleMan: drops_on_initialization is empty; no initial drops were spawned.")
		return

	for i in range(spawn_count):
		var scene := _pick_random_drop_scene_for_initialization()
		if scene == null:
			continue

		var instance := scene.instantiate()
		if not (instance is Node2D):
			push_warning("CandleMan: drops_on_initialization scene root must be Node2D.")
			continue

		var drop_node := instance as Node2D
		add_child(drop_node)
		drop_node.global_position = get_bottom_drop_global_position(i)

		# Wait until the drop has completed _ready before driving absorb logic.
		if drop_node.is_node_ready():
			_try_absorb_initial_drop(drop_node)
		else:
			drop_node.ready.connect(_on_initial_drop_ready.bind(drop_node), CONNECT_ONE_SHOT)


func _pick_random_drop_scene_for_initialization() -> PackedScene:
	var valid_scenes: Array[PackedScene] = []
	for scene in drops_on_initialization:
		if scene != null:
			valid_scenes.append(scene)

	if valid_scenes.is_empty():
		push_warning("CandleMan: drops_on_initialization contains no valid scenes.")
		return null

	var idx := randi() % valid_scenes.size()
	return valid_scenes[idx]


func _on_initial_drop_ready(drop_node: Node2D) -> void:
	_try_absorb_initial_drop(drop_node)


func _try_absorb_initial_drop(drop_node: Node2D) -> void:
	if drop_node == null or not is_instance_valid(drop_node):
		return
	if not (drop_node is CandleDrop):
		push_warning("CandleMan: initial drop scene root must be CandleDrop.")
		return

	# Initial drops should match configured drop_count and not add extra height/count again.
	var drop := drop_node as CandleDrop
	drop.absorb_into_immediate(self, false)


func _compute_absorb_duration_for_new_drop() -> float:
	var base_duration := maxf(absorb_duration, 0.0)
	var extra_per_drop := maxf(absorb_duration_per_absorbed_drop, 0.0)
	if is_zero_approx(extra_per_drop):
		return base_duration

	var settled_absorbed_count := 0
	for drop in _absorbed_drops:
		if drop == null or not is_instance_valid(drop):
			continue
		if drop.is_absorbed_settled():
			settled_absorbed_count += 1

	return base_duration + float(settled_absorbed_count) * extra_per_drop


func _play_absorb_sfx_for_drop_index(absorbed_drop_bottom_index: int) -> void:
	if _absorb_sfx_player == null:
		return

	var stream_to_play := _get_absorb_sfx_stream_for_drop_index(absorbed_drop_bottom_index)
	if stream_to_play == null:
		stream_to_play = _absorb_sfx_player.stream
	if stream_to_play == null:
		return

	if _absorb_sfx_player.stream != stream_to_play:
		_absorb_sfx_player.stream = stream_to_play
	_absorb_sfx_player.play()


func _get_absorb_sfx_stream_for_drop_index(absorbed_drop_bottom_index: int) -> AudioStream:
	if ABSORB_SFX_STREAMS.is_empty():
		return null

	var clamped_index := clampi(absorbed_drop_bottom_index, 0, ABSORB_SFX_STREAMS.size() - 1)
	return ABSORB_SFX_STREAMS[clamped_index]