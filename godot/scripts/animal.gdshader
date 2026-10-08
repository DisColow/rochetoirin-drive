// Animaux des prés : robe dessinée selon l'espèce (taches pie rouge des Montbéliardes, Charolaises blanches, moutons à
// tête sombre, chevaux bais / alezans / gris), sabots sombres ; tête qui broute et queue qui bat (sans squelette).
// INSTANCE_CUSTOM : x = robe (0 … 1), y = phase.
shader_type spatial;
#include "res://scripts/env.gdshaderinc"

uniform int species = 0;          // 0 vache, 1 mouton, 2 cheval

varying vec3 v_lp;
varying vec3 v_wp;
varying float v_robe;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float noise3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	v_lp = VERTEX;
	v_robe = INSTANCE_CUSTOM.x;
	float ph = INSTANCE_CUSTOM.y * 6.283;
	float front = species == 1 ? 0.45 : (species == 0 ? 1.0 : 0.9);
	float head = smoothstep(front, front + 0.45, VERTEX.z);
	// tête qui broute : lent mouvement de haut en bas, petites pauses
	float graze = 0.5 + 0.5 * sin(TIME * 0.7 + ph);
	VERTEX.y -= head * graze * (species == 1 ? 0.06 : 0.12);
	// queue qui chasse les mouches
	float tail = smoothstep(-front - 0.1, -front - 0.5, VERTEX.z) * smoothstep(1.2, 0.5, VERTEX.y);
	VERTEX.x += tail * sin(TIME * 3.0 + ph * 2.0) * 0.08;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (!env_fade_keep(v_wp, FRAGCOORD.xy)) {
		discard;
	}
	vec3 p = v_lp;
	vec3 c;
	float rough = 0.85;
	if (species == 0) {
		vec3 blanc = vec3(0.86, 0.83, 0.77);
		vec3 roux = vec3(0.48, 0.2, 0.09);
		float n = noise3(p * 2.2 + vec3(v_robe * 7.0)) + 0.5 * noise3(p * 5.0);
		float spot = smoothstep(0.78, 0.86, n);
		float face = smoothstep(1.1, 1.3, p.z);                 // tête blanche
		float legs = smoothstep(0.6, 0.35, p.y);                 // bas des pattes blanc
		c = mix(roux, blanc, max(max(spot, face), legs));
		if (v_robe > 0.5) {
			c = vec3(0.88, 0.85, 0.76) * (0.92 + 0.1 * noise3(p * 6.0));        // Charolaise
		}
	} else if (species == 1) {
		c = vec3(0.86, 0.84, 0.78) * (0.85 + 0.2 * noise3(p * 18.0));
		float head = smoothstep(0.5, 0.6, p.z);
		float legs = smoothstep(0.3, 0.2, p.y);
		c = mix(c, vec3(0.16, 0.12, 0.1), max(head, legs));
		rough = 0.95;
	} else {
		vec3 robe = v_robe < 0.45 ? vec3(0.32, 0.17, 0.08) : (v_robe < 0.8 ? vec3(0.55, 0.28, 0.12) : vec3(0.72, 0.72, 0.7));
		float legs = smoothstep(0.75, 0.45, p.y) * (v_robe < 0.45 ? 1.0 : 0.0);
		float mane = smoothstep(1.55, 1.75, p.y) * smoothstep(0.4, 0.8, p.z) * smoothstep(1.2, 0.9, p.z);
		c = mix(robe, vec3(0.08, 0.06, 0.05), max(legs, mane * 0.8));
		rough = 0.55;
	}
	c = mix(c, vec3(0.08, 0.07, 0.06), smoothstep(0.1, 0.04, p.y));            // sabots
	ALBEDO = c * env_cloud(v_wp.xz) * (1.0 - 0.2 * wet);
	ROUGHNESS = mix(rough, 0.45, wet);
}
