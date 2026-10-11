// Rangs de cultures : bandes verticales de 3 m texturées (atlas de 4 cultures), posées sur le relief.
// Données d'instance : x = ligne de l'atlas / 6, y = décalage de texture (variété), z = teinte, w = hauteur de la bande (m) ;
// w < 0 : nappe horizontale (dessus des céréales et du feuillage), texture vue de dessus.
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/env.gdshaderinc"

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_enable;

varying float v_tint;
varying float v_gust;
varying vec3 v_wp;
varying vec2 v_raw;      // nappes : coordonnées de texture continues (repli dans l'atlas au pixel, sans couture)
varying float v_sheet;   // nappes : ligne de l'atlas ; -1 pour les bandes verticales

void vertex() {
	float h = INSTANCE_CUSTOM.w;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_gust = env_gust(wp.xz);
	v_wp = wp;
	if (h > 0.0) {
		// haut de la bande penché dans le sens du vent, plus fort dans les rafales
		float top = 1.0 - UV.y;
		vec3 w = vec3(wind.x, 0.0, wind.y) * top * (0.04 + 0.22 * v_gust) * wind.z * min(h, 1.5);
		VERTEX += inverse(mat3(MODEL_MATRIX)) * w;
	}
	float row = INSTANCE_CUSTOM.x * 6.0;
	v_sheet = h > 0.0 ? -1.0 : row;
	v_raw = vec2(UV.x + INSTANCE_CUSTOM.y, UV.y * 0.333 + INSTANCE_CUSTOM.y * 0.5);
	float vrow = h > 0.0 ? 1.0 - (1.0 - UV.y) * h / 3.0 : fract(UV.y * 0.33 + INSTANCE_CUSTOM.y * 0.5);
	UV = vec2(UV.x + INSTANCE_CUSTOM.y, (row + clamp(vrow, 0.002, 0.998)) / 6.0);
	v_tint = INSTANCE_CUSTOM.z;
}

void fragment() {
	if (!env_fade_keep(v_wp, FRAGCOORD.xy)) {
		discard;
	}
	vec2 uv = UV;
	vec2 gx = dFdx(UV), gy = dFdy(UV);
	if (v_sheet >= 0.0) {
		uv = vec2(v_raw.x, (v_sheet + clamp(fract(v_raw.y), 0.002, 0.998)) / 6.0);
		gx = dFdx(v_raw) * vec2(1.0, 1.0 / 6.0); gy = dFdy(v_raw) * vec2(1.0, 1.0 / 6.0);
	}
	vec4 c = textureGrad(albedo_atlas, uv, gx, gy);
	if (c.a < 0.5) {
		discard;
	}
	// reflets des rafales qui couchent les épis (vagues claires qui traversent le champ)
	ALBEDO = c.rgb * v_tint * (1.0 + (v_gust - 0.5) * 0.24 * wind.z) * env_cloud(v_wp.xz);
	NORMAL_MAP = textureGrad(normal_atlas, uv, gx, gy).rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
