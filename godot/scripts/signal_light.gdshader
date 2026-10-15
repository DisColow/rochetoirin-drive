// Feux tricolores : cycle de 60 s (vert 27 s, orange 3 s, rouge 30 s), décalé selon le carrefour et l'axe
// Effacé avec son mât quand on renverse le feu (#68 : env_casse), fondu au loin comme les panneaux (env_fade_keep).
shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://scripts/env.gdshaderinc"
uniform int bulb = 0;          // 0 rouge, 1 orange, 2 vert
varying vec3 v_wp;
void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (casse_n > 0) {
		vec3 w2 = env_casse(v_wp);
		if (w2.y != v_wp.y) {
			VERTEX = (inverse(MODEL_MATRIX) * vec4(w2, 1.0)).xyz;
			v_wp = w2;
		}
	}
}
void fragment() {
	if (!env_fade_keep(v_wp, FRAGCOORD.xy)) {
		discard;
	}
	vec3 w = v_wp;
	float phase = fract(sin(dot(floor(w.xz / 60.0), vec2(12.9898, 78.233))) * 43758.5453) * 60.0;
	// axes perpendiculaires d'un même carrefour en opposition de phase (rouge pour l'un quand l'autre est vert)
	vec3 n = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float t = mod(TIME + phase + (abs(n.x) > abs(n.z) ? 30.0 : 0.0), 60.0);
	int on = t < 27.0 ? 2 : (t < 30.0 ? 1 : 0);
	vec3 col = bulb == 0 ? vec3(1.0, 0.08, 0.05) : (bulb == 1 ? vec3(1.0, 0.55, 0.05) : vec3(0.1, 1.0, 0.45));
	ALBEDO = on == bulb ? col * 2.5 : col * 0.08;
}
