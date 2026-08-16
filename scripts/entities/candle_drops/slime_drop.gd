extends CandleDrop
class_name SlimeDrop

# Fixed bounce launch speed (units/s) is cached on the pawn, not on this drop, so it
# survives across drops and stays valid even if _bounce_vertical is called for a pawn
# that is not owned by this instance.
const BOUNCE_HEIGHT_META: StringName = &"slime_bounce_height"
const BOUNCE_TIMESTAMP_META: StringName = &"slime_bounce_timestamp"

static func _bounce_vertical(pawn: Pawn, fall_distance_units: float) -> void:
	if not is_instance_valid(pawn):
		return

	# Recomputing the launch speed from the measured fall distance every bounce feeds
	# discrete-integration error back into itself, so the height keeps growing. Instead
	# establish the launch speed once and reuse it, so every bounce reaches the same
	# expected height. Only recompute when a ceiling clamped the reachable peak, which
	# legitimately changes the target height.
	var meta_outdated := not pawn.has_meta(BOUNCE_HEIGHT_META)
	var current_timestamp := Engine.get_physics_frames()

	if not meta_outdated:
		var last_bounce_timestamp := int(pawn.get_meta(BOUNCE_TIMESTAMP_META))
		var lt := pawn.last_land_timestamp if is_inf(pawn._airborne_start_y_px) else pawn.land_timestamp
		meta_outdated = lt - last_bounce_timestamp > 1
		# print("Checking if meta is outdated for ", pawn, " last_bounce_timestamp: ", last_bounce_timestamp, " lt: ", lt, " meta_outdated: ", meta_outdated, "fall_distance_units: ", fall_distance_units, " airborne_start_y_px: ", pawn._airborne_start_y_px, " airborne_peak_y_px: ", pawn._airborne_peak_y_px)

	
	var needs_recompute := pawn.has_hit_ceiling_since_takeoff() or meta_outdated
	var launch_speed_units: float
	if needs_recompute:
		var required_height_units := maxf(fall_distance_units, 0.0)
		var recorded_height_units := GameUnits.pixels_to_units(pawn.global_position.y) - required_height_units
		if required_height_units <= 0.25:
			return
		# Match Pawn jump-rise gravity so the bounce can reach the recorded peak height.
		var rise_gravity := pawn.compute_gravity(true)
		launch_speed_units = sqrt(2.0 * rise_gravity * required_height_units)
		pawn.set_meta(BOUNCE_HEIGHT_META, recorded_height_units)
	else:
		var recorded_height_units = float(pawn.get_meta(BOUNCE_HEIGHT_META))
		var required_height_units = GameUnits.pixels_to_units(pawn.global_position.y) - recorded_height_units
		if required_height_units <= 0.25:
			return
		launch_speed_units = sqrt(2.0 * pawn.compute_gravity(true) * required_height_units)

	pawn.set_external_velocity(Vector2(0.0, -launch_speed_units))
	pawn.set_meta(BOUNCE_TIMESTAMP_META, current_timestamp)

static func _bounce_horizontal(pawn: Pawn, total_velocity: Vector2, away_dir: float) -> void:
	if not is_instance_valid(pawn):
		return
	if is_zero_approx(away_dir):
		return

	# Ground drag decays a small external impulse almost instantly (displacement ~= speed^2 /
	# (2 * drag)), so enforce a minimum push speed and add a hop to switch to weaker air drag.
	var bounce_speed := absf(total_velocity.x)
	var target_velocity_x := signf(away_dir) * bounce_speed * 8.0
	
	pawn.set_external_velocity(Vector2(0.0, 1.5))


func _bounce_onland(pawn: Pawn, _impact_velocity: Vector2, fall_distance_units: float) -> void:
	if not _candle_man.is_bottom_absorbed_drop(self):
		return
	_bounce_vertical(pawn, fall_distance_units)

func on_pawn_contact_active(_other: Pawn, _normal: Vector2) -> void:
	print("[SlimeDrop.on_pawn_contact_active] self: ", self, " other: ", _other, " normal: ", _normal, " state: ", state)
	if state != DropState.INDEPENDENT:
		return

	if abs(_normal.y) < 0.5:
		# _normal's sign convention isn't reliable here (SOFT_PUSH pawns never produce a real
		# slide-collision normal), so derive the push-away direction from actual positions instead.
		var away_dir := signf(_other.global_position.x - global_position.x)
		if is_zero_approx(away_dir):
			print("[SlimeDrop.on_pawn_contact_active] skipped, away_dir is zero (same x position)")
			return

		var other_velocity_units := GameUnits.pixels_to_units_v2(_other.velocity)
		print("[SlimeDrop.on_pawn_contact_active] horizontal branch, away_dir: ", away_dir, " other_velocity_units: ", other_velocity_units)
		if other_velocity_units.x * away_dir >= 0.0:
			print("[SlimeDrop.on_pawn_contact_active] skipped, other not approaching (velocity.x * away_dir = ", other_velocity_units.x * away_dir, ")")
			return

		# _bounce_horizontal(_other, other_velocity_units, -away_dir)
	else:
		if Engine.get_physics_frames() - _other.land_timestamp > 1:
			return
		
		if _normal.y * _other._vertical_velocity > 0.0:
			return

		if is_finite(_other._airborne_peak_y_px):
			_bounce_vertical(_other, GameUnits.pixels_to_units(_other._airborne_peak_y_px - _other.global_position.y))
		else:
			_bounce_vertical(_other, _other.last_fall_distance_units)

func on_landed(_impact_velocity: Vector2, fall_distance_units: float = 0.0) -> void:
	super.on_landed(_impact_velocity, fall_distance_units)

	if state != DropState.INDEPENDENT:
		return

	_bounce_vertical(self, fall_distance_units)
	

func _on_absorb(man: CandleMan) -> void:
	# Start a fresh bounce sequence: drop any cached speed so the next landing re-establishes it.
	if not man.landed.is_connected(_bounce_onland):
		man.landed.connect(_bounce_onland)


func _on_detach(man: CandleMan) -> void:
	if man.landed.is_connected(_bounce_onland):
		man.landed.disconnect(_bounce_onland)

	self.set_meta(BOUNCE_TIMESTAMP_META, -1)
