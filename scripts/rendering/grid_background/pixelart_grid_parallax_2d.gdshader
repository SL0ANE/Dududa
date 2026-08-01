shader_type canvas_item;

uniform vec4 color0 : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 color1 : source_color = vec4(0.75, 0.75, 0.75, 1.0);
uniform float cell_size = 32.0;
uniform float parallax_factor = 0.5;
uniform vec2 camera_canvas_offset_px = vec2(0.0);
uniform vec2 stretch_scale = vec2(1.0);
uniform vec2 camera_zoom_scale = vec2(1.0);

void fragment() {
    vec2 safe_scale = max(stretch_scale, vec2(0.0001));
    vec2 safe_zoom = max(camera_zoom_scale, vec2(0.0001));
    vec2 screen_px = FRAGCOORD.xy / safe_scale / safe_zoom;
    vec2 parallax_px = (camera_canvas_offset_px / safe_zoom) * parallax_factor;

    vec2 uv = (screen_px + parallax_px) / max(cell_size, 1.0);

    // Analytic checker AA based on screen-space derivatives.
    vec2 w = max(fwidth(uv), vec2(1e-5)) * 0.5;
    vec2 s = 2.0 * (
        abs(fract((uv - 0.5 * w) * 0.5) - 0.5)
        - abs(fract((uv + 0.5 * w) * 0.5) - 0.5)
    ) / w;
    float checker = 0.5 - 0.5 * s.x * s.y;

    COLOR = mix(color0, color1, checker);
}
