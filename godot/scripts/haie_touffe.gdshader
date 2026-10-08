// Touffes de feuillage des haies (blender_haies.py, feuilles dessinées par build_haie_tex.py) : cartes découpées,
// éclairage doux de feuillage (normale tirée vers l'extérieur de la touffe), lumière qui traverse, balancement au vent.
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/env.gdshaderinc"

uniform sampler2D leaves : source_color, filter_linear_mipmap, repeat_disable;

varying vec3 v_wp;
varying vec3 v_tint;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 org = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float g = env_gust(wp.xz);
	float amp = 0.035 * (0.3 + wind.z) * (0.4 + g);
	vec3 off = vec3(wind.x, 0.0, wind.y) * amp * sin(TIME * 2.3 + dot(org.xz, vec2(0.7, 1.3)))
		+ vec3(0.0, 0.012, 0.0) * sin(TIME * 3.1 + org.x);
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * off) * clamp(length(VERTEX) * 2.0, 0.0, 1.0);
	// normale « en dôme » : la touffe s'éclaire comme une boule de feuillage, pas comme des cartes plates
	NORMAL = normalize(mix(NORMAL, normalize(VERTEX + vec3(0.0, 0.0, 0.25)), 0.75));
	v_wp = wp;
	v_tint = COLOR.rgb;
}

void fragment() {
	if (!env_fade_keep(v_wp, FRAGCOORD.xy)) {
		discard;
	}
	vec4 t = texture(leaves, UV);
	if (t.a < 0.5) {
		discard;
	}
	vec3 c = t.rgb * v_tint * 1.2 * env_cloud(v_wp.xz);
	ALBEDO = c * (1.0 - 0.2 * wet);
	ROUGHNESS = mix(0.72, 0.25, wet);
	SPECULAR = 0.25;
	BACKLIGHT = c * 0.45;
}
