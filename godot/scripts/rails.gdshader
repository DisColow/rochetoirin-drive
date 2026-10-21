// Voies ferrées (#125, rails.gd) : ballast (gravier gris, grains estompés au loin), traverses en béton peintes sur le
// dessus tous les 0,6 m, rails (dessus brillant, flancs rouillés). UV = (écart à l'axe de la voie, distance le long
// de la voie) en mètres ; COLOR.r = 1 pour les rails, COLOR.g = 1 pour leur dessus.
shader_type spatial;
#include "res://scripts/env.gdshaderinc"

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float u = UV.x, v = UV.y;
	vec3 c;
	float rough = 0.95;
	float metal = 0.0;
	float loin = clamp(fwidth(v) * 5.0, 0.0, 1.0);          // au loin : couleurs moyennes (pas de moiré)
	if (COLOR.r > 0.5) {
		bool dessus = COLOR.g > 0.5;
		c = dessus ? vec3(0.66, 0.66, 0.68) : vec3(0.3, 0.19, 0.12);
		metal = dessus ? 0.85 : 0.15;
		rough = dessus ? 0.28 : 0.8;
	} else {
		vec3 gris = vec3(0.43, 0.41, 0.38);
		float n = h21(floor(vec2(u, v) * 9.0)) * 0.6 + h21(floor(vec2(u, v) * 21.0)) * 0.4;
		c = mix(gris * (0.72 + 0.56 * n), gris, loin);
		float tv = abs(fract(v / 0.6) - 0.5) * 0.6;       // distance au milieu de la traverse la plus proche (m)
		float trav = (abs(u) < 1.3 && tv < 0.13) ? 1.0 : 0.0;
		vec3 beton = vec3(0.6, 0.59, 0.56) * (0.92 + 0.08 * h21(floor(vec2(u * 4.0, v / 0.6))));
		c = mix(c, mix(beton, mix(gris, beton, 0.43), loin), trav);
		c *= 1.0 - 0.25 * smoothstep(0.12, 0.0, abs(abs(u) - 0.72)) * (1.0 - loin);    // ombre au pied des rails
		c *= 1.0 - 0.18 * smoothstep(1.7, 2.4, abs(u));                             // talus plus sombres
	}
	ALBEDO = c * env_cloud(v_wp.xz) * (1.0 - 0.3 * wet);
	METALLIC = metal;
	ROUGHNESS = mix(rough, 0.25, wet * 0.7);
}
