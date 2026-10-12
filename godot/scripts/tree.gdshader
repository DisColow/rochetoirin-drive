// Arbres proches (modèles 3D) : matériau des modèles repris tel quel, plus le vent : tout l'arbre ploie avec les
// rafales (d'autant plus qu'on monte), le feuillage frémit ; ombre des nuages qui passent.
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/env.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform bool leaf = false;
uniform float scissor = 0.45;
uniform float near_cut = 1e6;          // relais avec les imposteurs (vegetation.gd, impostor.gdshader)

varying vec3 v_wp;
varying float v_cd;

void vertex() {
	vec3 org = MODEL_MATRIX[3].xyz;
	v_cd = length((org - env_cam).xz);
	float s = length(MODEL_MATRIX[1].xyz);            // modèle de hauteur ~1, mis à la taille de l'arbre
	float h = clamp(VERTEX.y, 0.0, 1.2);
	float g = env_gust(org.xz);
	float bend = wind.z * (0.25 + 0.75 * g) * h * h * 0.022 * s;
	vec3 w = vec3(wind.x, 0.0, wind.y) * bend;
	w += vec3(wind.x, 0.0, wind.y) * sin(TIME * (0.9 + g) + org.x * 0.1) * 0.006 * s * h * h * wind.z;
	if (leaf) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float f = sin(TIME * 7.0 + wp.x * 2.1 + wp.z * 1.7 + wp.y * 1.3) * sin(TIME * 4.3 + wp.y * 2.7);
		w += vec3(0.4, 1.0, 0.3) * f * 0.03 * (0.3 + wind.z) * (0.4 + g) * h;
	}
	VERTEX += inverse(mat3(MODEL_MATRIX)) * w;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// s'efface là où l'imposteur apparaît : mêmes pixels de la trame, en négatif
	if (env_dither_keep(clamp((v_cd - (near_cut - 4.0)) / 8.0, 0.0, 1.0), FRAGCOORD.xy)) {
		discard;
	}
	vec4 c = texture(albedo_tex, UV);
	if (leaf && c.a < scissor) {
		discard;
	}
	ALBEDO = c.rgb * env_cloud(v_wp.xz) * mix(1.0, 0.75, wet);
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	ROUGHNESS = mix(0.85, 0.45, wet);
	SPECULAR = 0.3;
	if (leaf) {
		BACKLIGHT = vec3(0.18, 0.22, 0.1);
	}
}
