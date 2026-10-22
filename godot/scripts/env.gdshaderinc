// Ambiance partagée par les matériaux du monde (paramètres de chaque matériau, tenus à jour par env.gd) :
//  wind   : x, y = direction du vent (plan xz), z = force (0 calme … 1 fort), w = inutilisé ;
//  clouds : x = assombrissement sous un nuage (0 = pas d'ombres de nuages), y = seuil de couverture, z, w inutilisés ;
//  wet    : 0 sec … 1 détrempé (pluie).
uniform vec4 wind = vec4(0.8, 0.6, 0.55, 0.0);
uniform vec4 clouds = vec4(0.0);
uniform float wet = 0.0;
// Fondu au loin (cells.gd) : distance (m) où l'objet a fini de s'effacer (0 : jamais) ; position de la caméra tenue à
// jour par env.gd (CAMERA_POSITION_WORLD serait celle de la lumière pendant le calcul des ombres).
uniform float fade_far = 0.0;
// Décor renversé par la voiture (casse.gd) : panneaux, clôtures. Point i : x, z, rayon (m), hauteur y au-dessus de
// laquelle les sommets sont effacés (ramenés sous le sol). casse_n = nombre de points utilisés.
uniform vec4 casse_pts[16];
uniform int casse_n = 0;

// Position (monde) d'un sommet après effacement des objets renversés.
vec3 env_casse(vec3 wp) {
	for (int i = 0; i < casse_n; i++) {
		vec4 c = casse_pts[i];
		if (wp.y > c.w && distance(wp.xz, c.xy) < c.z) {
			wp.y = c.w - 2.5;
		}
	}
	return wp;
}
uniform vec3 env_cam = vec3(0.0);

// Phares factices (réglage Économie, #124) : pas de vraie lampe (en Compatibility, chaque lampe redessine une fois de
// plus chaque objet qu'elle touche) ; le sol, les routes et les murs ajoutent eux-mêmes la lumière des phares du joueur.
//  env_phares      : xyz = milieu des deux phares (monde), w = intensité (0 : éteints) ;
//  env_phares_dir  : xyz = axe du faisceau (monde, normé), w = portée (m) ; env_phares_coul : couleur.
uniform vec4 env_phares = vec4(0.0);
uniform vec4 env_phares_dir = vec4(0.0, 0.0, 1.0, 45.0);
uniform vec3 env_phares_coul = vec3(1.0, 0.93, 0.8);
// Lumière des phares reçue en un point du monde (à ajouter : EMISSION += ALBEDO * env_phares_lum(wp)).
vec3 env_phares_lum(vec3 wp) {
	if (env_phares.w <= 0.0) {
		return vec3(0.0);
	}
	vec3 v = wp - env_phares.xyz;
	float d = dot(v, env_phares_dir.xyz);
	if (d <= 0.2 || d > env_phares_dir.w) {
		return vec3(0.0);
	}
	// deux phares écartés de ~1,2 m : faisceau large dès le pare-chocs, qui s'ouvre (~16°) et s'éteint au loin
	float lat = length(v - env_phares_dir.xyz * d);
	float cone = 1.0 - smoothstep(0.8 + d * 0.22, 1.6 + d * 0.42, lat);
	float att = pow(1.0 - d / env_phares_dir.w, 1.7) * smoothstep(0.2, 3.0, d);
	return env_phares_coul * env_phares.w * cone * att;
}

// Rafales qui traversent le paysage dans le sens du vent (0 … 1).
float env_gust(vec2 p) {
	vec2 d = wind.xy;
	float a = dot(p, d) * 0.045 - TIME * (1.0 + wind.z * 1.2);
	float b = dot(p, vec2(-d.y, d.x)) * 0.019 + TIME * 0.21;
	float g = sin(a + sin(b) * 2.2) * (0.65 + 0.35 * sin(b * 1.7 + a * 0.31));
	return clamp(0.5 + 0.5 * g, 0.0, 1.0);
}

// Ombre des nuages qui défilent avec le vent : 1 au soleil, 1 - clouds.x sous un nuage.
float env_cloud(vec2 p) {
	if (clouds.x <= 0.0) {
		return 1.0;
	}
	vec2 q = p * 0.0032 - wind.xy * TIME * 0.016;
	float n = sin(q.x * 1.7 + sin(q.y * 1.3)) * sin(q.y * 1.9 + sin(q.x * 0.7 + 1.3));
	n += 0.5 * sin(q.x * 3.1 - q.y * 2.3 + 2.0) * sin(q.y * 3.7 + q.x * 1.1);
	n += 0.25 * sin(q.x * 7.3 + q.y * 5.1) * sin(q.y * 6.1 - q.x * 4.7);
	return 1.0 - clouds.x * smoothstep(clouds.y, clouds.y + 0.3, n);
}

// Fondu par tramage (le rendu Compatibility n'a pas de fondu de distance) : pixel gardé si f (0 … 1) dépasse le
// seuil de la matrice de Bayer 4 × 4 de ce pixel. Fondus de distance des objets et fondus enchaînés.
const float ENV_BAYER[16] = { 0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0 };
bool env_dither_keep(float f, vec2 fc) {
	int i = int(mod(fc.x, 4.0)) + int(mod(fc.y, 4.0)) * 4;
	return f > (ENV_BAYER[i] + 0.5) / 16.0;
}
// Fondu au loin : disparaît progressivement de far - band à far (far <= 0 : pas de fondu).
bool env_far_keep(float d, float far, vec2 fc) {
	if (far <= 0.0) {
		return true;
	}
	float band = max(far * 0.12, 8.0);
	return env_dither_keep(clamp((far - d) / band, 0.0, 1.0), fc);
}
// Fondu au loin d'un point du monde, pour ce matériau : if (!env_fade_keep(v_wp, FRAGCOORD.xy)) { discard; }
bool env_fade_keep(vec3 wp, vec2 fc) {
	return env_far_keep(length(wp - env_cam), fade_far, fc);
}
