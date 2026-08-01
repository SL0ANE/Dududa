@tool
extends Node2D


const GameUnits = preload("res://scripts/shared/game_units.gd")
const CollisionMetrics = preload("res://scripts/shared/collision_metrics.gd")
const PLAYER_PAWN_GROUP: StringName = &"player_pawn"


@export_group("Display")
@export var display := false

@export_group("Content Image")
@export var content_texture: Texture2D:
	set(value):
		content_texture = value
		_apply_content_texture()

@export var content_sprite_path: NodePath = ^"CanvasGroup/ContentSprite"

@export_group("Proximity")
@export var detect_players := true
@export var display_radius_units := 3.0


@onready var _content_sprite: Sprite2D = _resolve_content_sprite()


func _ready() -> void:
	_apply_content_texture()


func _physics_process(_delta: float) -> void:
	if not detect_players:
		return

	var should_display := _is_any_pawn_in_range()
	if display != should_display:
		display = should_display


func _resolve_content_sprite() -> Sprite2D:
	if content_sprite_path.is_empty():
		return null

	var node := get_node_or_null(content_sprite_path)
	if node is Sprite2D:
		return node

	return null


func _apply_content_texture() -> void:
	if _content_sprite == null:
		_content_sprite = _resolve_content_sprite()

	if _content_sprite:
		_content_sprite.texture = content_texture


func _is_any_pawn_in_range() -> bool:
	var radius_pixels := GameUnits.units_to_pixels(maxf(display_radius_units, 0.0))
	for node in get_tree().get_nodes_in_group(PLAYER_PAWN_GROUP):
		if node is Node2D and is_instance_valid(node):
			var pawn := node as Node2D
			if CollisionMetrics.compute_edge_distance_pixels(self, pawn) <= radius_pixels:
				return true

	return false
