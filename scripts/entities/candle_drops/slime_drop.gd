extends CandleDrop
class_name SlimeDrop

var climate: float = 0.0

func _record_climate(pawn: Pawn) -> void:
	var diff: float = GameUnits.pixels_to_units(pawn.position.y) - climate
	if abs(diff) < 0.25:
		return

	climate = GameUnits.pixels_to_units(pawn.position.y)

func _bounce(pawn: Pawn, impact_velocity: Vector2, fall_distance_units: float) -> void:

	var required_height_px := maxf(0.0, pawn.position.y - GameUnits.units_to_pixels(climate))
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

func _on_absorb(man: CandleMan) -> void:
	if not man.started_falling.is_connected(_record_climate):
		man.started_falling.connect(_record_climate)
	if not man.landed.is_connected(_bounce):
		man.landed.connect(_bounce)

func _on_detach(man: CandleMan) -> void:
	if man.started_falling.is_connected(_record_climate):
		man.started_falling.disconnect(_record_climate)
		man.landed.disconnect(_bounce)
