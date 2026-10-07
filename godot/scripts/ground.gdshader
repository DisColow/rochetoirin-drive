// Sols des routes hors enrobé (terre, trottoirs, béton, coussins, peinture) : texture PBR en coordonnées du maillage,
// plus l'ambiance (ombre des nuages, sol mouillé plus sombre et brillant).
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/env.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool textured = true;
uniform vec3 tint : source_color = vec3(1.0);
uniform float uv_scale = 0.5;
uniform float rough = 0.6;
uniform float wet_dark = 0.35;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	UV *= uv_scale;
}

void fragment() {
	float k = wet;
	if (textured) {
		ALBEDO = texture(albedo_tex, UV).rgb * tint * env_cloud(wpos.xz) * (1.0 - wet_dark * k);
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		ROUGHNESS = mix(texture(rough_tex, UV).r, 0.18, k * 0.8);
	} else {
		ALBEDO = tint * env_cloud(wpos.xz) * (1.0 - wet_dark * 0.5 * k);
		ROUGHNESS = mix(rough, 0.2, k * 0.8);
	}
}
