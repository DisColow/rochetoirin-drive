// Voitures garées, tracteurs, poubelles fusionnés en une seule surface (props.gd _fusionner, #124 étape 2 : un appel de
// dessin par case au lieu d'un par matériau) : chaque sommet porte la couleur de son matériau d'origine (UV, UV2.x), son
// aspect métallique et sa rugosité (UV2.y = métal × 10 + rugosité). UV2.y = −1 : carrosserie, couleur par instance
// (INSTANCE_CUSTOM), vernis brillant, un peu de poussière en bas de caisse (comme paint.gdshader) ; mouillée sous la
// pluie, ombre des nuages.
shader_type spatial;
#include "res://scripts/env.gdshaderinc"

varying vec3 v_col;
varying vec3 v_wp;
varying float v_y;
varying float v_peint;
varying vec2 v_rm;

void vertex() {
	v_peint = UV2.y < -0.5 ? 1.0 : 0.0;
	v_col = mix(vec3(UV, UV2.x), INSTANCE_CUSTOM.rgb, v_peint);
	float rm = max(UV2.y, 0.0);
	v_rm = vec2(fract(rm), floor(rm) * 0.1);
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
	float rough = mix(v_rm.x, mix(0.32, 0.6, dirt), peint);
	ROUGHNESS = mix(rough, mix(rough * 0.5, 0.08, peint), wet);
	METALLIC = mix(v_rm.y, 0.15, peint);
	CLEARCOAT = 0.7 * peint;
	CLEARCOAT_ROUGHNESS = mix(0.15, 0.04, wet);
}
