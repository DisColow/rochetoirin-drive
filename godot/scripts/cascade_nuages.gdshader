// Bord « cascade » (#157, #180, cascade.gd) : mer de nuages sous le monde, dans laquelle tombe la cascade. Grand plan au
// sommet de la couche, qui suit la caméra. #180 (cible : la beauté d'une skybox) : cumulus en relief par « parallaxe »
// (marche de quelques pas le long du regard dans un relief de nuages lu dans une texture de bruit lisse : bon marché
// sur téléphone), dômes arrondis éclairés par le soleil (ombre propre et ombres portées entre les bourgeons, liseré
// lumineux à contre-jour), creux bleutés, et brume qui fond la mer dans la couleur de l'horizon au loin.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D relief_nuages : filter_linear_mipmap, repeat_enable;   // R : hauteur des nuages (0-1), sans couture
uniform vec3 soleil_dir = vec3(0.4, 0.6, 0.3);       // vers le soleil (monde)
uniform vec3 soleil_coul = vec3(1.0, 0.97, 0.92);
uniform vec3 ciel_coul = vec3(0.70, 0.80, 0.92);     // horizon (couleur de la brume)
uniform float echelle = 0.0011;                      // 1 / taille d'un motif (m)
uniform float hmax = 90.0;                           // épaisseur des bourgeons (m)

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// niveau de mipmap explicite (lectures dans des boucles à branches : pas de dérivées fiables) d'après la distance
float haut(vec2 xz, float g_lod) {
	vec2 uv = xz * echelle + vec2(TIME * 0.0012, TIME * 0.0007);
	float n = textureLod(relief_nuages, uv, g_lod).r;          // une seule lecture (le bruit a déjà 4 octaves)
	return sqrt(smoothstep(0.30, 0.86, n));          // dômes arrondis (racine : bords à pic, sommets ronds)
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(v_wp - cam);
	float g_lod = clamp(log2(max(length(v_wp - cam), 1.0) * 0.004), 0.0, 6.0);
	float haut0 = v_wp.y;                              // sommet de la couche (le plan)
	float bas = haut0 - hmax;
	vec3 p = v_wp;
	vec3 hit = v_wp;
	float h;
	// marche vers le bas : 20 pas de hmax / 20 en altitude, 40 m au plus (au ras de l'horizon : 800 m de long), puis
	// 4 pas de dichotomie au point de contact (sans eux, des stries apparaissent en vue rasante)
	float pas = min((hmax / 20.0) / max(-rd.y, 0.02), 40.0);
	bool trouve = false;
	for (int i = 0; i < 20; i++) {
		if (p.y <= bas + hmax * haut(p.xz, g_lod)) {
			trouve = true;
			break;
		}
		p += rd * pas;
	}
	if (trouve) {
		vec3 a = p - rd * pas;
		vec3 b = p;
		for (int j = 0; j < 4; j++) {
			vec3 m = (a + b) * 0.5;
			if (m.y <= bas + hmax * haut(m.xz, g_lod)) {
				b = m;
			} else {
				a = m;
			}
		}
		hit = b;
	} else {
		hit = p;
	}
	h = clamp((hit.y - bas) / hmax, 0.0, 1.0);
	// normale : pente du relief
	float e = 6.0;
	float hc = haut(hit.xz, g_lod);
	float hx = haut(hit.xz + vec2(e, 0.0), g_lod) - hc;
	float hz = haut(hit.xz + vec2(0.0, e), g_lod) - hc;
	vec3 n = normalize(vec3(-hx * hmax / e, 1.0, -hz * hmax / e));
	// soleil un peu abaissé pour les seuls nuages : à midi, il écraserait les ombres (dômes tout blancs)
	vec3 L = normalize(vec3(soleil_dir.x, max(soleil_dir.y, 0.05) * 0.45, soleil_dir.z));
	// ombres portées entre les bourgeons : 3 pas vers le soleil
	float ombre = 1.0;
	for (int j = 1; j <= 3; j++) {
		vec3 q = hit + L * (14.0 * float(j)) + vec3(0.0, 1.0, 0.0);
		if (q.y < bas + hmax * haut(q.xz, g_lod)) {
			ombre -= 0.22;
		}
	}
	float diff = clamp(dot(n, L) * 0.7 + 0.3, 0.0, 1.0) * ombre;           // éclairage enveloppant (nuage diffus)
	float bord = pow(1.0 - clamp(dot(n, -rd), 0.0, 1.0), 3.0);                // liseré lumineux à contre-jour
	float contre = clamp(dot(rd, L), 0.0, 1.0);
	vec3 creux = mix(vec3(0.30, 0.37, 0.52), ciel_coul * 0.6, 0.3);
	vec3 sommet = vec3(1.0, 0.995, 0.985) * soleil_coul;
	vec3 c = mix(creux, sommet, clamp(diff * (0.55 + 0.45 * h), 0.0, 1.0));
	c += soleil_coul * bord * contre * 0.35;
	// brume : la mer se fond dans l'horizon au loin
	float dist = length(hit - cam);
	float f = 1.0 - exp(-dist / 9000.0);
	c = mix(c, ciel_coul, clamp(f * 1.1, 0.0, 1.0));
	ALBEDO = c;
}
