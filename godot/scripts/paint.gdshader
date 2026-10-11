// Carrosseries des voitures garées : couleur par instance (INSTANCE_CUSTOM), vernis brillant qui reflète le ciel,
// un peu de poussière en bas de caisse ; mouillée sous la pluie, ombre des nuages.
shader_type spatial;
#include "res://scripts/env.gdshaderinc"

varying vec3 v_col;
varying vec3 v_wp;
varying float v_y;

void vertex() {
	v_col = INSTANCE_CUSTOM.rgb;
	v_y = VERTEX.y;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (!env_fade_keep(v_wp, FRAGCOORD.xy)) {
		discard;
	}
	float dirt = (1.0 - smoothstep(0.3, 0.75, v_y)) * (1.0 - wet * 0.7);
	ALBEDO = mix(v_col, vec3(0.42, 0.38, 0.32), dirt * 0.35) * env_cloud(v_wp.xz);
	ROUGHNESS = mix(mix(0.32, 0.6, dirt), 0.08, wet);
	METALLIC = 0.15;
	CLEARCOAT = 0.7;
	CLEARCOAT_ROUGHNESS = mix(0.15, 0.04, wet);
}
