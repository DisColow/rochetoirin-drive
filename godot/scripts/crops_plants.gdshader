// Touffes des champs façon GTA San Andreas (v6.50, issue #61) : deux plans croisés par touffe, bande de champ tirée de
// l'atlas des touffes (pipeline/build_touffes.py : 4 cultures × 4 variantes, cases de 512 × 512 px).
// Données d'instance : x = culture (0 maïs, 1 céréales, 2 colza, 3 tournesol), y = variante (0-3), z = teinte,
// w = hauteur de la case (m). Une touffe touchée par la voiture disparaît (il a éclaté : trample.gd + dust.gd).
// Maïs (v6.71) et céréales (v6.72) (#117) : un seul plan, toujours parallèle à l'écran (tourné autour de la
// verticale), au lieu de la croix : on le traverse comme un décor de carton, sans qu'il pivote quand on le dépasse.
// Les touffes de céréales ont un contour irrégulier (blender_orge.py) : à plat, un haut droit faisait des bottes.
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/env.gdshaderinc"

uniform sampler2D plants_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D trample_tex : filter_linear, repeat_disable;
uniform vec4 trample_zone = vec4(0.0, 0.0, 96.0, 0.0);   // coin x, coin z, taille (m), active

varying float v_tint;
varying float v_gust;
varying float v_plat;
varying float v_culture;
varying vec3 v_wp;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	float h = INSTANCE_CUSTOM.w;
	v_plat = INSTANCE_CUSTOM.x < 1.5 ? 1.0 : 0.0;
	v_culture = INSTANCE_CUSTOM.x;
	if (v_plat > 0.5) {
		if (abs(VERTEX.x) < 0.01) {
			VERTEX = vec3(0.0, -50.0, 0.0);          // second plan de la croix : rien (triangles dégénérés)
		} else {
			vec3 r = INV_VIEW_MATRIX[0].xyz;          // droite de l'écran, ramenée à l'horizontale
			r = normalize(vec3(r.x, 0.0, r.z) + vec3(1e-4, 0.0, 0.0));
			vec3 decal = r * VERTEX.x * length(MODEL_MATRIX[0].xyz) + vec3(0.0, VERTEX.y * MODEL_MATRIX[1].y, 0.0);
			VERTEX = inverse(mat3(MODEL_MATRIX)) * decal;
		}
	}
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
	UV = vec2((INSTANCE_CUSTOM.y + UV.x) / 4.0, (INSTANCE_CUSTOM.x + UV.y) / 4.0);
	v_tint = INSTANCE_CUSTOM.z;
}

void fragment() {
	if (env_hors_monde(v_wp)) {          // bord « cascade » (#157)
		discard;
	}
	// fondu large (dernier 40 % de la portée) : les plants s'éclaircissent peu à peu au lieu de finir en mur
	float dc = length(v_wp - env_cam);
	if (fade_far > 0.0 && !env_dither_keep(clamp((fade_far - dc) / (fade_far * 0.4), 0.0, 1.0), FRAGCOORD.xy)) {
		discard;
	}
	vec4 c = texture(plants_atlas, UV);
	if (c.a < 0.5) {
		discard;
	}
	// éclairage doux : normale du plan ramenée vers le haut (feuillage fin, pas de face sombre) ; maïs (plan face à
	// l'écran) : normale horizontale vers la caméra, calculée ici (celle du sommet passe mal par la matrice d'instance)
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	vec3 n0 = FRONT_FACING ? NORMAL : -NORMAL;
	float vers_haut = 0.35;
	if (v_plat > 0.5) {
		// plan face à la caméra : souvent à contre-jour ; normale surtout vers le haut (comme l'herbe) et feuilles
		// translucides, sinon tout le champ devient sombre dès qu'on roule face au soleil
		vec3 nw = normalize(vec3(INV_VIEW_MATRIX[2].x, 0.0, INV_VIEW_MATRIX[2].z) + vec3(0.0, 0.0, 1e-4));
		n0 = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
		vers_haut = 0.75;
		BACKLIGHT = v_culture < 0.5 ? vec3(0.3, 0.36, 0.14) : vec3(0.4, 0.33, 0.12);   // feuilles / paille dorée
	}
	NORMAL = normalize(mix(n0, up, vers_haut));
	ALBEDO = c.rgb * v_tint * (1.0 + (v_gust - 0.5) * 0.18 * wind.z) * env_cloud(v_wp.xz);
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
