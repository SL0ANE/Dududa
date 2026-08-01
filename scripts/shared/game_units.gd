extends RefCounted
class_name GameUnits


const PIXELS_PER_UNIT_SETTING := "dududa/pixels_per_unit"
const DEFAULT_PIXELS_PER_UNIT := 16.0


static func pixels_per_unit() -> float:
	return maxf(float(ProjectSettings.get_setting(PIXELS_PER_UNIT_SETTING, DEFAULT_PIXELS_PER_UNIT)), 0.001)


static func units_to_pixels(value: float) -> float:
	return value * pixels_per_unit()


static func pixels_to_units(value: float) -> float:
	return value / pixels_per_unit()


static func units_to_pixels_v2(value: Vector2) -> Vector2:
	var ppu := pixels_per_unit()
	return value * ppu


static func pixels_to_units_v2(value: Vector2) -> Vector2:
	var ppu := pixels_per_unit()
	return value / ppu
