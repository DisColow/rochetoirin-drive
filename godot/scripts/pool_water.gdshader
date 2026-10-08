// Eau des piscines : turquoise, légères vagues (normales animées), reflets plus forts en vue rasante, reflets
// lumineux mouvants au fond ; ambiance commune (ombre des nuages) et fondu au loin (env.gdshaderinc).
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
#include "res://scripts/env.gdshaderinc"

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (!env_fade_keep(v_wp, FRAGCOORD.xy)) {
		discard;
	}
	vec2 p = v_wp.xz;
	float t = TIME;
	vec2 g = vec2(cos(p.x * 2.1 + t * 1.3) + 0.6 * cos(p.y * 1.7 - t * 1.1),
		sin(p.y * 2.3 + t * 1.2) + 0.6 * sin(p.x * 1.9 - t * 0.9)) * 0.05;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(g.x, 1.0, g.y)), 0.0)).xyz);
	float caus = pow(0.5 + 0.5 * sin(p.x * 3.1 + t * 0.8 + 1.5 * sin(p.y * 2.7 + t)) * sin(p.y * 3.3 - t * 0.7 + 1.3 * sin(p.x * 2.2)), 3.0);
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 c = mix(vec3(0.32, 0.78, 0.84), vec3(0.06, 0.45, 0.6), 0.45);
	ALBEDO = (c + caus * 0.1) * env_cloud(v_wp.xz);
	ROUGHNESS = 0.04;
	SPECULAR = 0.7;
	ALPHA = mix(0.8, 0.97, f);
}
