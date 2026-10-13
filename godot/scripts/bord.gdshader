// Talus des bords de la carte (build_bord.py, bord.gd) : herbe qui vire à la roche et à la terre là où c'est raide,
// stries de ravinement, ombre des nuages et fondu au loin (env.gdshaderinc). UV.y : distance hors de la carte (0 … 1).
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/env.gdshaderinc"

varying vec3 v_wp;
varying vec3 v_n;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_n = NORMAL;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	if (!env_fade_keep(v_wp, FRAGCOORD.xy)) {
		discard;
	}
	float raide = 1.0 - clamp(normalize(v_n).y, 0.0, 1.0);
	float n1 = vnoise(v_wp.xz * 0.35) * 0.6 + vnoise(v_wp.xz * 1.7) * 0.4;
	vec3 herbe = mix(vec3(0.27, 0.36, 0.13), vec3(0.38, 0.44, 0.18), n1);
	vec3 terre = mix(vec3(0.42, 0.33, 0.22), vec3(0.52, 0.42, 0.30), n1);
	vec3 roche = mix(vec3(0.48, 0.46, 0.42), vec3(0.62, 0.60, 0.55), vnoise(v_wp.xz * 0.9 + v_wp.y * 0.5));
	float stries = smoothstep(0.55, 0.9, vnoise(vec2((v_wp.x + v_wp.z) * 0.6, v_wp.y * 0.15)));
	vec3 c = mix(herbe, terre, smoothstep(0.25, 0.45, raide + n1 * 0.15));
	c = mix(c, roche, smoothstep(0.5, 0.7, raide + stries * 0.2));
	ALBEDO = c * env_cloud(v_wp.xz) * (1.0 - 0.25 * wet);
	ROUGHNESS = mix(0.95, 0.5, wet);
}
