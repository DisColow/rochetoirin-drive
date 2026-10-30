// Relief lointain : texture de l'orthophoto, courbure terrestre (réfraction standard, k = 0,13) au-delà de 8 km
shader_type spatial;
render_mode cull_back, specular_disabled;
#include "res://scripts/bout_monde.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
const float R_EFF = 7.32e6;

varying vec3 v_wp;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wp = w;
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = length(w.xz - cam.xz);
	if (d > 8000.0) {
		VERTEX.y -= (d * d - 64e6) / (2.0 * R_EFF);
	}
}

void fragment() {
#ifdef BOUT_MONDE
	if (env_hors_monde(v_wp)) {          // bord « cascade » (#157) : variante chargée avec l'option (env.gd)
		discard;
	}
#endif
	vec3 c = texture(tex, UV).rgb;
	ALBEDO = c * 0.95;
	ROUGHNESS = 0.95;
}
