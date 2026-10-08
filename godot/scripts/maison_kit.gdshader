// Kit de détails des maisons (blender_maisons.py) : menuiseries, volets et portes (couleur d'instance), vitrages
// (reflet du ciel, fenêtres éclairées la nuit comme sur les façades : même tirage par position), métal, terre cuite.
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/env.gdshaderinc"

uniform int kind = 0;                 // 0 uni, 1 couleur d'instance, 2 vitrage
uniform vec3 albedo : source_color = vec3(0.8);
uniform float rough = 0.5;
uniform float metal = 0.0;
uniform float night = 0.0;

varying vec3 v_wp;
varying vec3 v_col;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = COLOR.rgb;
}

void fragment() {
	float sh = env_cloud(v_wp.xz);
	vec3 c = kind == 1 ? v_col : albedo;
	float r = rough;
	if (kind == 2) {
		// vitre : ciel reflété en haut, intérieur sombre en bas ; lumière chaude la nuit (une fenêtre sur deux)
		vec3 v = normalize(v_wp - CAMERA_POSITION_WORLD);
		float up = clamp(-v.y * 0.5 + 0.5 + (FRAGCOORD.y / VIEWPORT_SIZE.y - 0.5) * -0.2, 0.0, 1.0);
		c = mix(vec3(0.05, 0.06, 0.07), vec3(0.45, 0.55, 0.68), smoothstep(0.35, 0.75, up) * 0.6);
		r = 0.05;
		if (night > 0.0) {
			float lit = step(0.5, hash(floor(v_wp.xz * 0.9) + floor(v_wp.y / 2.7) * 7.31));
			EMISSION = vec3(1.0, 0.72, 0.42) * 1.8 * night * lit;
		}
	}
	ALBEDO = c * sh * (1.0 - 0.15 * wet);
	ROUGHNESS = mix(r, 0.1, wet * 0.5);
	METALLIC = metal;
}
