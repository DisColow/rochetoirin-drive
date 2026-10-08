// Matériau simple (couleur ou texture découpée, rugosité, métal) des objets posés par lots, à la place d'un StandardMaterial3D, pour le fondu
// au loin (cells.gd) et l'ambiance (ombre des nuages, pluie).
shader_type spatial;
render_mode cull_back;
#include "res://scripts/env.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.8);
uniform float rough = 0.5;
uniform float metal = 0.0;
uniform bool textured = false;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scissor = -1.0;      // seuil de découpe (alpha), < 0 : opaque

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (!env_fade_keep(v_wp, FRAGCOORD.xy)) {
		discard;
	}
	vec3 c = albedo;
	if (textured) {
		vec4 t = texture(tex, UV);
		if (t.a < scissor) {
			discard;
		}
		c *= t.rgb;
	}
	ALBEDO = c * env_cloud(v_wp.xz) * mix(1.0, 0.8, wet);
	ROUGHNESS = mix(rough, rough * 0.5, wet);
	METALLIC = metal;
}
