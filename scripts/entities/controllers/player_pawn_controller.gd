extends "res://scripts/entities/controllers/pawn_controller.gd"
class_name PlayerPawnController


@export var move_left_action: StringName = &"move_left"
@export var move_right_action: StringName = &"move_right"
@export var jump_action: StringName = &"jump"
@export var interact_primary_action: StringName = &"interact_primary"
@export var interact_secondary_action: StringName = &"interact_secondary"

var _jump_key_was_down := false
var _interact_primary_key_was_down := false
var _interact_secondary_key_was_down := false


func _ready() -> void:
	var pawn := get_parent()
	if pawn and pawn is CharacterBody2D and not pawn.is_in_group(&"player_pawn"):
		pawn.add_to_group(&"player_pawn")


func build_command(_pawn: CharacterBody2D, _delta: float) -> Dictionary:
	var left_down := _is_action_or_key_pressed(move_left_action, Key.KEY_A)
	var right_down := _is_action_or_key_pressed(move_right_action, Key.KEY_D)
	var move_axis := float(int(right_down) - int(left_down))
	var jump_pressed := _is_jump_just_pressed()
	var interact_primary_pressed := _is_action_or_key_just_pressed(interact_primary_action, Key.KEY_E, "_interact_primary_key_was_down")
	var interact_secondary_pressed := _is_action_or_key_just_pressed(interact_secondary_action, Key.KEY_Q, "_interact_secondary_key_was_down")

	return {
		"move_axis": move_axis,
		"jump_pressed": jump_pressed,
		"interact_primary_pressed": interact_primary_pressed,
		"interact_secondary_pressed": interact_secondary_pressed,
	}


func _is_action_or_key_pressed(action: StringName, fallback_key: Key) -> bool:
	if InputMap.has_action(action):
		return Input.is_action_pressed(action)
	return Input.is_physical_key_pressed(fallback_key)


func _is_jump_just_pressed() -> bool:
	if InputMap.has_action(jump_action):
		return Input.is_action_just_pressed(jump_action)

	var jump_down := Input.is_physical_key_pressed(Key.KEY_W) or Input.is_physical_key_pressed(Key.KEY_SPACE)
	var jump_pressed := jump_down and not _jump_key_was_down
	_jump_key_was_down = jump_down
	return jump_pressed


func _is_action_or_key_just_pressed(action: StringName, fallback_key: Key, key_state_field: StringName) -> bool:
	if InputMap.has_action(action):
		return Input.is_action_just_pressed(action)

	var key_down := Input.is_physical_key_pressed(fallback_key)
	var was_down := bool(get(key_state_field))
	set(key_state_field, key_down)
	return key_down and not was_down
