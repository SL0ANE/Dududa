shader_type canvas_item;
#include "res://shaders/includes/noise.gdshaderinc"
#include "res://shaders/includes/sdf.gdshaderinc"

varying float v_left_right_distance;
varying float v_top_bottom_distance;
varying vec2 pos_offset;

uniform vec4 base_color : source_color = vec4(1.0, 0.306, 0.522, 1.0);
uniform float radius_0 = 64.0;
uniform float radius_1 = 64.0;


void vertex() {
	int id = VERTEX_ID % 4;
	bool is_left = (id == 0 || id == 1);
	bool is_top = (id == 0 || id == 3);

	vec2 world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vec2 world_pos_opposite_x = (MODEL_MATRIX * vec4(vec2(-VERTEX.x, VERTEX.y), 0.0, 1.0)).xy;
	vec2 world_pos_opposite_y = (MODEL_MATRIX * vec4(vec2(VERTEX.x, -VERTEX.y), 0.0, 1.0)).xy;
	float left_right_distance = distance(world_pos, world_pos_opposite_x);
	float top_bottom_distance = distance(world_pos, world_pos_opposite_y);
	v_left_right_distance = left_right_distance;
	v_top_bottom_distance = top_bottom_distance;
	
	pos_offset = MODEL_MATRIX[3].xy;
	UV = vec2(is_left ? 0.0 : left_right_distance, is_top ? 0.0 : top_bottom_distance);
}

void fragment() {
	vec2 uv = UV;
	uv = floor(uv);

	vec2 center = vec2(v_left_right_distance * 0.5, v_top_bottom_distance * 0.5);
	float sdCircle0 = length(uv - center) - radius_0;
	float sdCircle1 = length(uv - center) - min(radius_1, radius_0);

	float sdRing = max(sdCircle0, -sdCircle1);

	if (sdRing >= 0.0) discard;

	COLOR = base_color;
}