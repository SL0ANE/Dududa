shader_type canvas_item;
#include "res://shaders/includes/noise.gdshaderinc"
#include "res://shaders/includes/sdf.gdshaderinc"

varying float v_left_right_distance;
varying float v_top_bottom_distance;
varying vec2 pos_offset;

uniform vec4 outline_color : source_color = vec4(1.0, 0.306, 0.522, 1.0);
uniform vec4 base_color : source_color = vec4(0.043, 0.047, 0.086, 1.0);

vec4 modified_voronoi(vec3 uvw, vec2 offset, float scale, float radius, float width, float height, float threshold) {
	uvw = uvw + vec3(offset, 0.0);
	vec3 i_uvw = floor(uvw / scale);
	vec3 f_uvw = fract(uvw / scale);
	vec4 rta = vec4(0.0, 0.0, 0.0, 10.0);
	vec2 a = vec2(0.5 * width, radius + scale) + offset;
	vec2 b = vec2(0.5 * width, height - radius - scale) + offset;

	for (int k=-1; k<=1; k++ ) {
		for (int j=-1; j<=1; j++ ) {
			for (int i=-1; i<=1; i++ ) {
				vec3 neighbor = vec3(float(i),float(j),float(k));
				vec3 point = i_uvw + neighbor;
				float hash_value = hash13(point);
				
				point = 0.5 + (hash33(point) - 0.5);
				point = 0.5 + 0.5 * sin(TAU * point);
				point = (floor(point * scale - vec3(offset, 0.0)) + vec3(offset, 0.0)) / scale;

				vec3 op = (i_uvw + neighbor + point) * scale;
				float sd = sdSegment(op.xy, a, b) - radius;

				vec3 diff = neighbor + point - f_uvw;
				float dist = length(diff);
				if ( dist < rta.w && hash_value < threshold && sd < 0.0) {
					rta.xyz = point;
					rta.w = dist;
				}
			}
		}
	}

	return rta;
}

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
	float left_right_distance = v_left_right_distance;
	float top_bottom_distance = v_top_bottom_distance;
	
	float scale = 5.0;
	vec4 noise0 = modified_voronoi(vec3(uv, TIME * 8.0), pos_offset, 6.0, 8.0, left_right_distance, top_bottom_distance, 0.75) * scale;
	vec4 noise1 = modified_voronoi(vec3(uv, TIME * 4.0), pos_offset, 8.0, 8.0, left_right_distance, top_bottom_distance, 0.75) * scale;

	float outline = 1.0;
	float threshold = 2.5;
	float val = min(noise0.w, noise1.w);

	if (val > threshold) discard;

	COLOR = mix(base_color, outline_color, step(threshold - outline, val));
}

//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
