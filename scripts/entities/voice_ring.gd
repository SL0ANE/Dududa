extends Sprite2D

signal on_hit_pawn(pawn: Pawn, radius: float)
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
@export var radius: float:
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

func _ready() -> void:
	_timer = 0.0
	_setup_apperance()


func _process(delta: float) -> void:
	var current_progress = _timer / duration
	progress = current_progress

	var current_radius = lerp(_radius_start, _radius_end, pow(current_progress, _pow0))

func _update_progress() -> void:
	var shader_material := material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("progress", _progress)

func _setup_apperance() -> void:
	var shader_material := material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("radius_start", _radius_start)
		shader_material.set_shader_parameter("radius_end", _radius_end)
		shader_material.set_shader_parameter("pow0", _pow0)
		shader_material.set_shader_parameter("pow1", _pow1)
	material = shader_material

	var target_scale := 2.0 * _radius_end / _source_sprite_scale
	scale = Vector2(target_scale, target_scale)
