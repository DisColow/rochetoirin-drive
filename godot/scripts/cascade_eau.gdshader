// Bord « cascade » (#157, cascade.gd) : bande d'eau peu profonde qui coule vers la lèvre. UV.x : abscisse le long du
// bord (m) ; UV.y : distance à la lèvre (m, 0 à la lèvre, 14 en amont où l'eau se fond dans le sol).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
#include "res://scripts/env.gdshaderinc"

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float d = UV.y;
	// courant : rides étirées dans le sens du courant, qui filent vers la lèvre en accélérant
	float vit = 2.0 + 4.0 * (1.0 - clamp(d / 14.0, 0.0, 1.0));
	vec2 q = vec2(UV.x * 0.35, (d + TIME * vit) * 0.9);
	float r1 = vnoise(q * vec2(1.0, 0.35));
	float r2 = vnoise(q * vec2(2.3, 0.8) + 7.3);
	float rides = r1 * 0.6 + r2 * 0.4;
	float ecume = smoothstep(2.5, 0.0, d) * (0.5 + 0.5 * r2) + smoothstep(0.62, 0.85, rides) * 0.35;
	vec3 eau = mix(vec3(0.07, 0.24, 0.30), vec3(0.16, 0.42, 0.48), rides);
	ALBEDO = mix(eau, vec3(0.92, 0.96, 0.98), clamp(ecume, 0.0, 1.0)) * env_cloud(v_wp.xz);
	ROUGHNESS = mix(0.06, 0.45, ecume);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = mix(0.0, 0.88, smoothstep(14.0, 9.0, d)) * mix(1.0, 0.95, ecume);
}
