// Commerces (modèles Blender) : un seul shader, comportement selon « kind » :
// 0 uni, 1 enseigne (case de l'atlas en INSTANCE_CUSTOM, éclairée la nuit), 2 toile rayée (couleur d'instance),
// 3 couleur d'instance (bandeaux, auvents), 4 intérieur de boutique (rayons, éclairé la nuit), 5 lumineux (croix,
// carotte, ampoules), 6 verre ; plus l'ambiance (ombre des nuages, pluie).
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/env.gdshaderinc"

uniform int kind = 0;
uniform vec3 albedo : source_color = vec3(0.8);
uniform float rough = 0.5;
uniform float metal = 0.0;
uniform vec3 glow : source_color = vec3(0.0);
uniform float night = 0.0;
uniform float grid = 0.0;            // filets et grillages : maille (m), trous découpés
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;

varying vec4 v_c;
varying vec3 v_wp;

void vertex() {
	v_c = INSTANCE_CUSTOM;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float sh = env_cloud(v_wp.xz);
	vec3 c = albedo;
	float r = rough;
	vec3 e = vec3(0.0);
	if (kind == 1) {
		c = texture(atlas, v_c.xy + clamp(vec2(UV.x, 1.0 - UV.y), 0.004, 0.996) * v_c.zw).rgb;
		e = c * night * 0.9;
		r = 0.3;
	} else if (kind == 2) {
		float st = step(0.5, fract(UV.x * 4.0));
		c = mix(v_c.rgb, vec3(0.93, 0.9, 0.82), st * 0.85);
	} else if (kind == 3) {
		c = v_c.a > 0.0 ? v_c.rgb : albedo;
	} else if (kind == 4) {
		float shelf = step(0.75, fract(UV.y * 5.0)) * 0.35;
		float prod = step(0.5, fract(UV.x * 7.0 + floor(UV.y * 5.0) * 0.37)) * 0.25;
		c = albedo * (0.75 + prod - shelf);
		e = vec3(1.0, 0.86, 0.62) * c * (0.25 + 0.9 * night);
	} else if (kind == 5) {
		e = glow * (0.35 + 2.2 * night);
	} else if (kind == 8) {
		// balise à chevrons bleus sur fond blanc
		float ch = step(0.5, fract(UV.x * 2.5 + abs(UV.y - 0.5) * 2.5));
		c = mix(vec3(0.95), vec3(0.08, 0.22, 0.58), ch);
	} else if (kind == 7) {
		vec2 g = fract(UV / grid);
		if (g.x > 0.18 && g.y > 0.18) {
			discard;
		}
	} else if (kind == 6) {
		// vitrage : reflet du ciel + rayons et produits devinés derrière, éclairés la nuit
		float shelf = step(0.72, fract(UV.y * 4.0));
		float prod = step(0.45, fract(UV.x * 5.0 + floor(UV.y * 4.0) * 0.31));
		vec3 inside = mix(vec3(0.32, 0.3, 0.27), vec3(0.62, 0.5, 0.36), prod) * (1.0 - shelf * 0.5);
		c = mix(vec3(0.1, 0.12, 0.14), inside, 0.55);
		e = inside * vec3(1.0, 0.88, 0.7) * (0.12 + 1.1 * night);
		r = 0.06;
	}
	ALBEDO = c * sh * (1.0 - 0.15 * wet);
	ROUGHNESS = mix(r, 0.08, wet * 0.6);
	METALLIC = kind == 6 ? 0.25 : metal;
	EMISSION = e;
}
