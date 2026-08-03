@tool
extends ColorRect
class_name PixelGridBackground

const DEFAULT_SHADER: Shader = preload("res://shaders/backgrounds/pixelart_grid_parallax_2d.gdshader")

@export var color0: Color = Color(0.5, 0.5, 0.5, 1.0):
	set(value):
		color0 = value
		_sync_static_shader_params()
@export var color1: Color = Color(0.75, 0.75, 0.75, 1.0):
	set(value):
		color1 = value
		_sync_static_shader_params()
@export_range(1.0, 512.0, 1.0) var cell_size: float = 16.0:
	set(value):
		cell_size = value
		_sync_static_shader_params()
@export_range(0.0, 2.0, 0.01) var parallax_factor: float = 1.0:
	set(value):
		parallax_factor = value
		_sync_static_shader_params()
@export var visible_in_game_only: bool = false:
	set(value):
		visible_in_game_only = value
		_update_runtime_visibility()

var _last_canvas_origin: Vector2 = Vector2.INF
var _last_stretch: Vector2 = Vector2.INF
var _last_canvas_scale: Vector2 = Vector2.INF

func _ready() -> void:
	_update_runtime_visibility()
	_fit_full_canvas()
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)

	_ensure_shader_material()
	_sync_static_shader_params()
	_sync_dynamic_shader_params(true)

func _process(_delta: float) -> void:
	_sync_dynamic_shader_params(false)

func _sync_static_shader_params() -> void:
	var shader_material := _ensure_shader_material()
	if shader_material == null:
		return

	shader_material.set_shader_parameter("color0", color0)
	shader_material.set_shader_parameter("color1", color1)
	shader_material.set_shader_parameter("cell_size", cell_size)
	shader_material.set_shader_parameter("parallax_factor", parallax_factor)

func _sync_dynamic_shader_params(force: bool) -> void:
	var shader_material := _ensure_shader_material()
	if shader_material == null:
		return

	# Canvas transform origin tracks camera movement, including zoom/smoothing effects.
	var canvas_origin := get_viewport().get_canvas_transform().origin
	var stretch := get_viewport().get_stretch_transform().get_scale()
	var canvas_scale := get_viewport().get_canvas_transform().get_scale().abs()

	if not force and canvas_origin == _last_canvas_origin and stretch == _last_stretch and canvas_scale == _last_canvas_scale:
		return

	_last_canvas_origin = canvas_origin
	_last_stretch = stretch
	_last_canvas_scale = canvas_scale

	shader_material.set_shader_parameter("camera_canvas_offset_px", -canvas_origin)
	shader_material.set_shader_parameter("stretch_scale", stretch)
	shader_material.set_shader_parameter("camera_zoom_scale", canvas_scale)

func _ensure_shader_material() -> ShaderMaterial:
	var shader_material := self.material as ShaderMaterial
	if shader_material == null:
		shader_material = ShaderMaterial.new()
		self.material = shader_material

	if shader_material.shader == null:
		shader_material.shader = DEFAULT_SHADER

	return shader_material

func _on_viewport_size_changed() -> void:
	_fit_full_canvas()

func _fit_full_canvas() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _update_runtime_visibility() -> void:
	if visible_in_game_only and Engine.is_editor_hint():
		self.visible = false
	else:
		self.visible = true
