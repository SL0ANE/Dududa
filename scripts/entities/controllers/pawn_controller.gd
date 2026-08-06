extends Node
class_name PawnController


static func default_command() -> Dictionary:
	return {
		"move_axis": 0.0,
		"look_axis": 0.0,
		"jump_pressed": false,
		"interact_primary_pressed": false,
		"interact_secondary_pressed": false,
	}


func build_command(_pawn: CharacterBody2D, _delta: float) -> Dictionary:
	return default_command()
