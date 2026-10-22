// Voitures de la circulation (circulation.gd, #132) : modèle des voitures garées fusionné en une surface comme dans
// props.gdshader (couleur de chaque matériau dans UV, UV2.x ; UV2.y = métal × 10 + rugosité), avec des feux :
// UV2.y = −1 carrosserie (couleur par voiture : INSTANCE_CUSTOM.rgb), −2 phares avant, −3 feux arrière,
// −4 clignotants (côté d'après VERTEX.x : gauche < 0, le modèle regarde vers −Z).
// INSTANCE_CUSTOM.a = (bits + 0,5) / 16 ; bits : 1 phares allumés, 2 freinage, 4 clignotant gauche, 8 clignotant droit.
shader_type spatial;
#include "res://scripts/env.gdshaderinc"

varying vec3 v_col;
varying vec3 v_wp;
varying float v_y;
varying float v_peint;
varying vec2 v_rm;
varying float v_feu;               // 1 : phare avant, 2 : feu arrière, 3 : clignotant
varying float v_phares;
varying float v_frein;
varying float v_clign;             // clignotant de ce côté demandé

void vertex() {
	v_peint = (UV2.y < -0.5 && UV2.y > -1.5) ? 1.0 : 0.0;
	v_feu = UV2.y < -3.5 ? 3.0 : (UV2.y < -2.5 ? 2.0 : (UV2.y < -1.5 ? 1.0 : 0.0));
	v_col = mix(vec3(UV, UV2.x), INSTANCE_CUSTOM.rgb, v_peint);
	float rm = v_feu > 0.5 ? 0.3 : max(UV2.y, 0.0);
	v_rm = vec2(fract(rm), floor(rm) * 0.1);
	int bits = int(INSTANCE_CUSTOM.a * 16.0);
	v_phares = float(bits & 1);
	v_frein = float((bits >> 1) & 1);
	v_clign = float((bits >> (VERTEX.x < 0.0 ? 2 : 3)) & 1);
	v_y = VERTEX.y;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (!env_fade_keep(v_wp, FRAGCOORD.xy)) {
		discard;
	}
	float peint = step(0.5, v_peint);
	float dirt = (1.0 - smoothstep(0.3, 0.75, v_y)) * (1.0 - wet * 0.7) * peint;
	ALBEDO = mix(v_col, vec3(0.42, 0.38, 0.32), dirt * 0.35) * env_cloud(v_wp.xz) * mix(mix(1.0, 0.8, wet), 1.0, peint);
	EMISSION += ALBEDO * env_phares_lum(v_wp);
	if (v_feu > 2.5) {
		// clignotants : orange, 1,5 clignement par seconde
		EMISSION += vec3(1.0, 0.45, 0.02) * v_clign * step(0.5, fract(TIME * 1.5)) * 4.0;
	} else if (v_feu > 1.5) {
		// feux arrière : veilleuses la nuit, stop vif au freinage
		EMISSION += vec3(1.0, 0.05, 0.03) * (v_phares * 0.8 + v_frein * 3.0);
	} else if (v_feu > 0.5) {
		EMISSION += vec3(1.0, 0.92, 0.75) * v_phares * 3.5;
	}
	float rough = mix(v_rm.x, mix(0.32, 0.6, dirt), peint);
	ROUGHNESS = mix(rough, mix(rough * 0.5, 0.08, peint), wet);
	METALLIC = mix(v_rm.y, 0.15, peint);
	CLEARCOAT = 0.7 * peint;
	CLEARCOAT_ROUGHNESS = mix(0.15, 0.04, wet);
}
