// Plants des champs un par un (#142, issue #25) : deux plans croisés par plant, sprite tiré de l'atlas des plants
// (tools/bake_cultures.gd -- --seulement=plants : 4 cultures × 8 variantes, cases de 256 × 512 px).
// Données d'instance : x = culture (0 maïs, 1 céréales, 2 colza, 3 tournesol), y = variante (0-7), z = teinte,
// w = hauteur de la case (m). Un plant touché par la voiture disparaît (il a éclaté : trample.gd + dust.gd).
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/env.gdshaderinc"

uniform sampler2D plants_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D trample_tex : filter_linear, repeat_disable;
uniform vec4 trample_zone = vec4(0.0, 0.0, 96.0, 0.0);   // coin x, coin z, taille (m), active

varying float v_tint;
varying float v_gust;
varying vec3 v_wp;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	float h = INSTANCE_CUSTOM.w;
	v_gust = env_gust(base.xz);
	// haut du plant penché dans le sens du vent, plus fort dans les rafales (le pied reste en place)
	float top = 1.0 - UV.y;                       // UV.y : 0 en haut du sprite, 1 au pied
	vec3 w = vec3(wind.x, 0.0, wind.y) * top * top * (0.03 + 0.16 * v_gust) * wind.z * min(h, 2.0);
	w += vec3(wind.x, 0.0, wind.y) * top * 0.025 * sin(TIME * 2.3 + base.x * 1.7 + base.z * 1.3) * wind.z;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * w;
	if (trample_zone.w > 0.5) {
		vec2 tuv = (base.xz - trample_zone.xy) / trample_zone.z;
		if (tuv.x > 0.0 && tuv.y > 0.0 && tuv.x < 1.0 && tuv.y < 1.0 && textureLod(trample_tex, tuv, 0.0).b > 0.3) {
			VERTEX = vec3(0.0, -50.0, 0.0);          // plant éclaté : plus rien (triangle dégénéré sous le sol)
		}
	}
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	UV = vec2((INSTANCE_CUSTOM.y + UV.x) / 8.0, (INSTANCE_CUSTOM.x + UV.y) / 4.0);
	v_tint = INSTANCE_CUSTOM.z;
}

void fragment() {
	// fondu large (dernier 40 % de la portée) : les plants s'éclaircissent peu à peu au lieu de finir en mur
	float dc = length(v_wp - env_cam);
	if (fade_far > 0.0 && !env_dither_keep(clamp((fade_far - dc) / (fade_far * 0.4), 0.0, 1.0), FRAGCOORD.xy)) {
		discard;
	}
	vec4 c = texture(plants_atlas, UV);
	if (c.a < 0.5) {
		discard;
	}
	// éclairage doux : normale du plan ramenée vers le haut (feuillage fin, pas de face sombre)
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(FRONT_FACING ? NORMAL : -NORMAL, up, 0.35));
	ALBEDO = c.rgb * v_tint * (1.0 + (v_gust - 0.5) * 0.18 * wind.z) * env_cloud(v_wp.xz);
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
