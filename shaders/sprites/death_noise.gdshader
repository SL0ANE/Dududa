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

	radius = min(radius, height * 0.25);
	scale = min(scale, height * 0.25);
	
	uvw = uvw / vec3(scale, scale, 1.0);
	vec3 i_uvw = floor(uvw);
	vec3 f_uvw = fract(uvw);
	vec4 rta = vec4(0.0, 0.0, 0.0, 10.0);
	vec2 a = vec2(0.5 * width, min(radius + scale, 0.5 * height)) + offset;
	vec2 b = vec2(0.5 * width, max(height - radius - scale, 0.5 * height)) + offset;

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

float sample_noise(vec2 uv, float width, float height, vec2 offset)
{
	float scale = 5.0;
	vec4 noise0 = modified_voronoi(vec3(uv, TIME * 2.0), offset, 6.0, 6.0, width, height, 0.75) * scale;
	vec4 noise1 = modified_voronoi(vec3(uv, TIME * 1.0), offset, 8.0, 6.0, width, height, 0.75) * scale;

	float val = min(noise0.w, noise1.w);

	return step(val, 2.5);
}

void fragment() {
	vec2 uv = UV;
	uv = floor(uv);
	
	float c = sample_noise(uv, v_left_right_distance, v_top_bottom_distance, vec2(0.0, 0.0));
	float u = sample_noise(uv - vec2(1.0, 0.0), v_left_right_distance, v_top_bottom_distance, vec2(0.0, 0.0));
	float d = sample_noise(uv + vec2(1.0, 0.0), v_left_right_distance, v_top_bottom_distance, vec2(0.0, 0.0));
	float l = sample_noise(uv - vec2(0.0, 1.0), v_left_right_distance, v_top_bottom_distance, vec2(0.0, 0.0));
	float r = sample_noise(uv + vec2(0.0, 1.0), v_left_right_distance, v_top_bottom_distance, vec2(0.0, 0.0));

	float outline = max(max(u, d), max(l, r));

	/* float radius = 8.0;
	float scale = 5.0;
	vec2 a = vec2(0.5 * v_left_right_distance, min(radius + scale, 0.5 * v_top_bottom_distance)) + pos_offset;
	vec2 b = vec2(0.5 * v_left_right_distance, max(v_top_bottom_distance - radius - scale, 0.5 * v_top_bottom_distance)) + pos_offset;
	float sd = sdSegment(uv, a, b) - radius;
	COLOR = vec4(sd, sd, sd, 1.0); */


	if(max(c, outline) < 0.5) {
		discard;
	}

	COLOR = mix(outline_color, base_color, c);
}