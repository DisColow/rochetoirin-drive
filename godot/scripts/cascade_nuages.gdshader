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

float haut(vec2 xz) {
	vec2 uv = xz * echelle + vec2(TIME * 0.0012, TIME * 0.0007);
	float n = texture(relief_nuages, uv).r * 0.72 + texture(relief_nuages, uv * 2.7 + 0.31).r * 0.28;
	return sqrt(smoothstep(0.30, 0.86, n));          // dômes arrondis (racine : bords à pic, sommets ronds)
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(v_wp - cam);
	float haut0 = v_wp.y;                              // sommet de la couche (le plan)
	float bas = haut0 - hmax;
	vec3 p = v_wp;
	vec3 hit = v_wp;
	float h = 0.0;
	// marche vers le bas : 12 pas de hmax / 12 en altitude (bornée à 900 m de long au ras de l'horizon)
	float dy = hmax / 12.0;
	float pas = min(dy / max(-rd.y, 0.02), 75.0);
	float prec_y = p.y;
	float prec_s = 1.0;
	bool trouve = false;
	for (int i = 0; i < 12; i++) {
		float hs = bas + hmax * haut(p.xz);
		float s = p.y - hs;
		if (s <= 0.0) {
			float k = prec_s / max(prec_s - s, 1e-4);           // affinage linéaire entre les deux pas
			hit = mix(p - rd * pas, p, k);
			h = clamp((hit.y - bas) / hmax, 0.0, 1.0);
			trouve = true;
			break;
		}
		prec_s = s;
		p += rd * pas;
	}
	if (!trouve) {
		hit = p;
		h = 0.0;
	}
	// normale : pente du relief
	float e = 6.0;
	float hc = haut(hit.xz);
	float hx = haut(hit.xz + vec2(e, 0.0)) - hc;
	float hz = haut(hit.xz + vec2(0.0, e)) - hc;
	vec3 n = normalize(vec3(-hx * hmax / e, 1.0, -hz * hmax / e));
	// soleil un peu abaissé pour les seuls nuages : à midi, il écraserait les ombres (dômes tout blancs)
	vec3 L = normalize(vec3(soleil_dir.x, max(soleil_dir.y, 0.05) * 0.45, soleil_dir.z));
	// ombres portées entre les bourgeons : 3 pas vers le soleil
	float ombre = 1.0;
	for (int j = 1; j <= 3; j++) {
		vec3 q = hit + L * (14.0 * float(j)) + vec3(0.0, 1.0, 0.0);
		if (q.y < bas + hmax * haut(q.xz)) {
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
