extends CandleDrop
class_name SlimeDrop

# Fixed bounce launch speed (units/s) is cached on the pawn, not on this drop, so it
# survives across drops and stays valid even if _bounce_vertical is called for a pawn
# that is not owned by this instance.
const BOUNCE_HEIGHT_META: StringName = &"slime_bounce_height"


func _bounce_vertical(pawn: Pawn, fall_distance_units: float) -> void:
	if not is_instance_valid(pawn):
		return

	# Recomputing the launch speed from the measured fall distance every bounce feeds
	# discrete-integration error back into itself, so the height keeps growing. Instead
	# establish the launch speed once and reuse it, so every bounce reaches the same
	# expected height. Only recompute when a ceiling clamped the reachable peak, which
	# legitimately changes the target height.
	var needs_recompute := pawn.has_hit_ceiling_since_takeoff() or not pawn.has_meta(BOUNCE_HEIGHT_META)
	var launch_speed_units: float
	if needs_recompute:
		var required_height_units := maxf(fall_distance_units, 0.0)
		var recorded_height_units := GameUnits.pixels_to_units(pawn.position.y) - required_height_units
		if required_height_units <= 0.1:
			return
		# Match Pawn jump-rise gravity so the bounce can reach the recorded peak height.
		var rise_gravity := pawn.compute_gravity(true)
		launch_speed_units = sqrt(2.0 * rise_gravity * required_height_units)
		pawn.set_meta(BOUNCE_HEIGHT_META, recorded_height_units)
	else:
		var recorded_height_units = float(pawn.get_meta(BOUNCE_HEIGHT_META))
		var required_height_units = GameUnits.pixels_to_units(pawn.position.y) - recorded_height_units
		if required_height_units <= 0.1:
			return
		launch_speed_units = sqrt(2.0 * pawn.compute_gravity(true) * required_height_units)

	if launch_speed_units <= 0.0:
		return

	pawn.set_external_velocity(Vector2(0.0, -launch_speed_units))

func _bounce_onland(pawn: Pawn, _impact_velocity: Vector2, fall_distance_units: float) -> void:
	if not _candle_man.is_bottom_absorbed_drop(self):
		return
	_bounce_vertical(pawn, fall_distance_units)


func _on_absorb(man: CandleMan) -> void:
	# Start a fresh bounce sequence: drop any cached speed so the next landing re-establishes it.
	if not man.landed.is_connected(_bounce_onland):
		man.landed.connect(_bounce_onland)


func _on_detach(man: CandleMan) -> void:
	if man.landed.is_connected(_bounce_onland):
		man.landed.disconnect(_bounce_onland)
