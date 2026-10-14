// Rangs de cultures : bandes verticales de 3 m texturées (atlas de 4 cultures), posées sur le relief.
// Données d'instance : x = ligne de l'atlas / 6, y = décalage de texture (variété), z = teinte, w = hauteur de la bande (m) ;
// w < 0 : nappe horizontale (dessus des céréales et du feuillage), texture vue de dessus.
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/env.gdshaderinc"

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_enable;
// cultures écrasées au passage de la voiture (scripts/trample.gd) : R, V = sens de la marche, B = écrasement
uniform sampler2D trample_tex : filter_linear, repeat_disable;
uniform vec4 trample_zone = vec4(0.0, 0.0, 96.0, 0.0);   // coin x, coin z, taille (m), active

varying float v_tint;
varying float v_gust;
varying vec3 v_wp;
varying vec2 v_raw;      // nappes : coordonnées de texture continues (repli dans l'atlas au pixel, sans couture)
varying float v_sheet;   // nappes : ligne de l'atlas ; -1 pour les bandes verticales

void vertex() {
	float h = INSTANCE_CUSTOM.w;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_gust = env_gust(wp.xz);
	v_wp = wp;               // position avant écrasement (découpe de la trace au pixel près)
	if (h > 0.0) {
		// haut de la bande penché dans le sens du vent, plus fort dans les rafales
		float top = 1.0 - UV.y;
		vec3 w = vec3(wind.x, 0.0, wind.y) * top * (0.04 + 0.22 * v_gust) * wind.z * min(h, 1.5);
		VERTEX += inverse(mat3(MODEL_MATRIX)) * w;
	}
	if (trample_zone.w > 0.5) {
		vec2 tuv = (wp.xz - trample_zone.xy) / trample_zone.z;
		if (tuv.x > 0.0 && tuv.y > 0.0 && tuv.x < 1.0 && tuv.y < 1.0) {
			vec4 tr = textureLod(trample_tex, tuv, 0.0);
			// une bande fait jusqu'à 3 m : on lit aussi l'écrasement en son centre (une trace étroite passe entre
			// ses coins), et on garde le plus fort
			vec2 cuv = (MODEL_MATRIX[3].xz - trample_zone.xy) / trample_zone.z;
			vec4 trc = textureLod(trample_tex, clamp(cuv, vec2(0.001), vec2(0.999)), 0.0);
			if (trc.b > tr.b) { tr = trc; }
			if (tr.b > 0.05) {
				vec2 dir = normalize(tr.rg * 2.0 - 1.0 + vec2(1e-4));
				float var_t = fract(sin(dot(floor(wp.xz * 3.0), vec2(12.9898, 78.233))) * 43758.5453);
				float top = 1.0 - UV.y;
				vec3 d;
				if (h > 0.0) {
					// bande de plants verticale : fauchée net par la voiture (les tiges ont explosé en éclats,
					// trample.gd + dust.gd) ; il ne reste qu'un chaume de 10 à 20 cm
					float chaume = min(h, 0.12 + 0.08 * var_t);
					float haut = h * top;
					float k = clamp(tr.b * 1.3, 0.0, 1.0);
					d = vec3(0.0, (min(haut, chaume) - haut) * k, 0.0) + vec3(dir.x, 0.0, dir.y) * 0.05 * top * k;
				} else {
					// nappe du dessus : découpée dans la trace (fragment), descendue au sol au bord
					d = vec3(0.0, -0.7 * tr.b, 0.0);
				}
				VERTEX += inverse(mat3(MODEL_MATRIX)) * d;
			}
		}
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
	// dessus des céréales : trou net dans la trace (les tiges couchées sont dessinées au sol par le relief)
	if (v_sheet >= 0.0 && trample_zone.w > 0.5) {
		vec2 tuv = (v_wp.xz - trample_zone.xy) / trample_zone.z;
		if (tuv.x > 0.0 && tuv.y > 0.0 && tuv.x < 1.0 && tuv.y < 1.0 && texture(trample_tex, tuv).b > 0.45) {
			discard;
		}
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
