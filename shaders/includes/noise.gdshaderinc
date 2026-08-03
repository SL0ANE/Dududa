#include "res://shaders/includes/hash.gdshaderinc"
#include "res://shaders/includes/const.gdshaderinc"

vec3 voronoi(vec2 uv) {
    vec2 i_uv = floor(uv);
    vec2 f_uv = fract(uv);
    vec3 rta = vec3(0.0, 0.0, 10.0);
    for (int j=-1; j<=1; j++ ) {
        for (int i=-1; i<=1; i++ ) {
            vec2 neighbor = vec2(float(i),float(j));
            vec2 point = i_uv + neighbor;
            point = 0.5 + (hash22(point) - 0.5);
            point = 0.5 + 0.5 * sin(TAU * point);

            vec2 diff = neighbor + point - f_uv;
            float dist = length(diff);
            if ( dist < rta.z ) {
                rta.xy = point;
                rta.z = dist;
            }
        }
    }
    return rta;
}

vec4 voronoi(vec3 uvw) {
    vec3 i_uvw = floor(uvw);
    vec3 f_uvw = fract(uvw);
    vec4 rta = vec4(0.0, 0.0, 0.0, 10.0);

    for (int k=-1; k<=1; k++ ) {
        for (int j=-1; j<=1; j++ ) {
            for (int i=-1; i<=1; i++ ) {
                vec3 neighbor = vec3(float(i),float(j),float(k));
                vec3 point = i_uvw + neighbor;
                point = 0.5 + (hash33(point) - 0.5);
                point = 0.5 + 0.5 * sin(TAU * point);

                vec3 diff = neighbor + point - f_uvw;
                float dist = length(diff);
                if ( dist < rta.w ) {
                    rta.xyz = point;
                    rta.w = dist;
                }
            }
        }
    }

    return rta;
}