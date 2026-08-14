extends CandleDrop
class_name SlimeDrop

func on_pawn_contact_started(_other: Pawn, normal: Vector2) -> void:
	if state != DropState.INDEPENDENT:
		return

	print("SlimeDrop: on_pawn_contact_started normal=%s" % normal)


func _bounce_vertical(pawn: Pawn, fall_distance_units: float) -> void:
	print("SlimeDrop: _bounce_vertical fall_distance_units=%f" % fall_distance_units)
	var required_height_px := GameUnits.units_to_pixels(fall_distance_units)
	if required_height_px <= 0.0:
		return

	var required_height_units := GameUnits.pixels_to_units(required_height_px)
	if required_height_units <= 0.0:
		return

	# Match Pawn jump-rise gravity so bounce can reach the recorded peak height.
	print("Bounce: required_height_units = %f" % required_height_units)
	var rise_gravity := pawn.compute_gravity(true)
	var required_upward_speed := sqrt(2.0 * rise_gravity * required_height_units)

	if not is_instance_valid(pawn):
		return
	pawn.set_external_velocity(Vector2(0.0, -required_upward_speed))
	# pawn._driven_velocity = Vector2(pawn._driven_velocity.x, 0.0)

func _bounce_onland(pawn: Pawn, impact_velocity: Vector2, fall_distance_units: float) -> void:
	_bounce_vertical(pawn, fall_distance_units)

func _on_absorb(man: CandleMan) -> void:
	if not man.landed.is_connected(_bounce_onland):
		man.landed.connect(_bounce_onland)

func _on_detach(man: CandleMan) -> void:
	if man.landed.is_connected(_bounce_onland):
		man.landed.disconnect(_bounce_onland)
