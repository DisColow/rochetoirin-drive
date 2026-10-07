// Enrobé : texture PBR mélangée à deux échelles (casse la répétition des fissures), grandes plaques plus sombres ou
// plus claires (reprises, usure), légère brillance d'usure ; coordonnées monde.
shader_type spatial;
render_mode cull_back;
#include "res://scripts/env.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.62, 0.62, 0.63);
uniform float scale = 0.30;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 u1 = p * scale;
	vec2 u2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * scale * 0.37 + vec2(0.31, 0.17);
	float m = smoothstep(0.3, 0.7, vnoise(p * 0.05));
	vec3 a = mix(texture(albedo_tex, u1).rgb, texture(albedo_tex, u2).rgb, m);
	vec3 n = mix(texture(normal_tex, u1).rgb, texture(normal_tex, u2).rgb, m);
	float r = mix(texture(rough_tex, u1).r, texture(rough_tex, u2).r, m);
	// plaques : reprises plus sombres, zones usées plus claires
	float big = vnoise(p * 0.018) * 0.6 + vnoise(p * 0.07) * 0.4;
	float patch = smoothstep(0.62, 0.68, vnoise(p * 0.035 + 7.0));
	vec3 c = a * tint * (0.86 + 0.28 * big);
	c *= mix(1.0, 0.72, patch);
	ALBEDO = c * env_cloud(wpos.xz);
	NORMAL_MAP = n;
	ROUGHNESS = clamp(r * 0.95 + 0.05 - patch * 0.08, 0.3, 1.0);
}
