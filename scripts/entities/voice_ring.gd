@tool
extends Sprite2D
class_name VoiceRing

const GameUnits = preload("res://scripts/shared/game_units.gd")

signal on_hit_pawn(pawn: Pawn, radius: float, emit_timestamp: int)
signal on_progress_end()

@export_group("Appearance")
var _radius_start := 0.5
@export var radius_start: float:
	get:
		return _radius_start
	set(value):
		_radius_start = value
		_setup_apperance()

var _radius_end := 4.0
@export var radius_end: float:
	get:
		return _radius_end
	set(value):
		_radius_end = value
		_setup_apperance()

var _source_sprite_scale := 8.0
@export var source_sprite_scale : float:
	get:
		return _source_sprite_scale
	set(value):
		_source_sprite_scale = value
		_setup_apperance()

var _progress := 0.0
@export var progress: float:
	get:
		return _progress
	set(value):
		_progress = value
		_update_progress()

@export var duration := 0.5

var _pow0 := 2.0
@export var pow0: float:
	get:
		return _pow0
	set(value):
		_pow0 = value
		_setup_apperance()

var _pow1 := 2.75
@export var pow1: float:
	get:
		return _pow1
	set(value):
		_pow1 = value
		_setup_apperance()

var _timer := 0.0
var _hit_pawn_ids := {}
var _query_shape := CircleShape2D.new()
var _query_params := PhysicsShapeQueryParameters2D.new()
var _query_max_results := 16
var _emit_timestamp : int = 0

func _ready() -> void:
	_timer = 0.0
	_emit_timestamp = Time.get_ticks_msec()
	_query_params.shape = _query_shape
	_query_params.collide_with_bodies = true
	_query_params.collide_with_areas = false
	_ensure_unique_material_instance()
	_setup_apperance()


func _enter_tree() -> void:
	_ensure_unique_material_instance()
	_setup_apperance()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if duration <= 0.0:
		_timer = 0.0
		progress = 1.0
		_collect_pawns_in_radius(_radius_end)
		on_progress_end.emit()
		queue_free()
		return

	_timer = minf(_timer + maxf(delta, 0.0), duration)
	var current_progress := clampf(_timer / duration, 0.0, 1.0)
	var applied_progress := _map_progress_to_out_sine(current_progress)
	progress = applied_progress

	var current_radius: float = lerpf(_radius_start, _radius_end, pow(progress, _pow0))
	_collect_pawns_in_radius(current_radius)

	if _timer >= duration:
		on_progress_end.emit()
		queue_free()


func _collect_pawns_in_radius(current_radius: float) -> void:
	if not is_finite(current_radius) or current_radius <= 0.0:
		return

	var radius_pixels := GameUnits.units_to_pixels(current_radius)
	if not is_finite(radius_pixels) or radius_pixels <= 0.0:
		return

	_query_shape.radius = radius_pixels
	_query_params.transform = Transform2D(0.0, global_position)

	var hits: Array = get_world_2d().direct_space_state.intersect_shape(_query_params)
	var hit_count := mini(hits.size(), _query_max_results)
	for i in range(hit_count):
		var hit_dict: Dictionary = hits[i]
		var collider_id := int(hit_dict.get("collider_id", -1))
		var pawn := Pawn.resolve_pawn_from_collider_id(collider_id)
		if pawn == null:
			continue

		var pawn_id := pawn.get_instance_id()
		if _hit_pawn_ids.has(pawn_id):
			continue

		_hit_pawn_ids[pawn_id] = true
		on_hit_pawn.emit(pawn, current_radius, _emit_timestamp)
func _update_progress() -> void:
	var shader_material := material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("progress", _progress)


func _map_progress_to_out_sine(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return sin(t * PI * 0.5)

func _setup_apperance() -> void:
	var shader_material := material as ShaderMaterial
	# print("Setting up appearance for voice ring with radius_start: ", _radius_start, ", radius_end: ", _radius_end, ", pow0: ", _pow0, ", pow1: ", _pow1)
	if shader_material:
		shader_material.set_shader_parameter("radius_start", GameUnits.units_to_pixels(_radius_start))
		shader_material.set_shader_parameter("radius_end", GameUnits.units_to_pixels(_radius_end))
		shader_material.set_shader_parameter("pow0", _pow0)
		shader_material.set_shader_parameter("pow1", _pow1)
	material = shader_material

	var target_scale := 2.0 * _radius_end / _source_sprite_scale
	scale = Vector2(target_scale, target_scale)


func _ensure_unique_material_instance() -> void:
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return

	# VoiceRing animates shader params every frame; material must be unique per instance.
	if shader_material.resource_local_to_scene:
		return

	var unique_material := shader_material.duplicate() as ShaderMaterial
	if unique_material == null:
		return

	unique_material.resource_local_to_scene = true
	material = unique_material
