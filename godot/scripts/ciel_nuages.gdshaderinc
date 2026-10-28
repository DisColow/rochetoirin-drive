// Ciel peint (#57) : dégradé haut / horizon, soleil (ou lune), et un plafond de nuages projeté
// (assets/fx/nuages.png de pipeline/build_nuages_tex.py), éclairés côté soleil, plus sombres dessous, effacés vers
// l'horizon. Commun à ciel_peint.gdshader et à ciel_midi.gdshader (v6.91 : météo variable, le ciel photo de midi se
// couvre en fondu vers ce ciel peint, `gris`). Les variables LIGHT0_* n'existent que dans sky() : passées en argument.
// v6.93 : étoiles la nuit (`etoiles`, 0-1), sous les nuages. v6.96 : arc-en-ciel (`arc`, 0-1) à l'opposé du soleil.

uniform vec3 haut : source_color = vec3(0.26, 0.44, 0.75);
uniform vec3 horizon : source_color = vec3(0.88, 0.80, 0.66);
uniform vec3 sol : source_color = vec3(0.12, 0.13, 0.12);
uniform float energie = 1.0;
uniform sampler2D nuages : filter_linear_mipmap, repeat_enable;
uniform float couverture = 0.55;            // seuil : plus haut, moins de nuages
uniform vec3 clair : source_color = vec3(1.0, 0.95, 0.88);
uniform vec3 ombre : source_color = vec3(0.45, 0.47, 0.55);
uniform vec2 vent = vec2(0.0);
uniform float taille_soleil = 1.0;
uniform float etoiles = 0.0;
uniform float arc = 0.0;

// Couleur de l'arc-en-ciel à la position x de sa bande (0 violet, 1 rouge), bords adoucis, rien en dehors.
vec3 arc_couleur(float x) {
	float e = smoothstep(-0.15, 0.1, x) * (1.0 - smoothstep(0.9, 1.15, x));
	vec3 k = clamp(abs(fract(mix(0.76, 0.0, clamp(x, 0.0, 1.0)) + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return mix(vec3(1.0), k, 0.75) * e;
}

float hachage13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

// Étoiles : une case sur ~70 d'une grille de directions (0,4° : une étoile fait 1 à 2 pixels, sans scintiller quand la
// caméra bouge), placée au hasard dans sa case ; quelques-unes bien plus brillantes, blanc bleuté à jaune pâle.
vec3 etoile(vec3 d) {
	vec3 p = d * 140.0;
	vec3 c = floor(p);
	float r = hachage13(c);
	if (r < 0.986) {
		return vec3(0.0);
	}
	vec3 o = vec3(hachage13(c + 17.1), hachage13(c + 41.7), hachage13(c + 73.3)) * 0.6 + 0.2;
	float eclat = pow((r - 0.986) / 0.014, 3.0);
	float s = smoothstep(0.2 + 0.18 * eclat, 0.0, length(fract(p) - o));
	vec3 teinte = mix(vec3(0.72, 0.8, 1.0), vec3(1.0, 0.9, 0.72), hachage13(c + 5.3));
	return teinte * s * (0.35 + 2.4 * eclat);
}

vec3 ciel_peint(vec3 d, bool l0, vec3 l0_dir, vec3 l0_lum, bool cubemap) {
	float h = d.y;
	vec3 c = mix(horizon, haut, pow(clamp(h, 0.0, 1.0), 0.55));
	if (h < 0.0) {
		c = mix(horizon * 0.85, sol, clamp(-h * 5.0, 0.0, 1.0));
	}
	float s = l0 ? dot(d, l0_dir) : 0.0;
	vec3 sc = l0 ? l0_lum : vec3(0.0);
	c += sc * (smoothstep(1.0 - 0.0006 * taille_soleil, 1.0 - 0.0002 * taille_soleil, s) * 6.0 + pow(max(s, 0.0), 48.0) * 0.3);
	if (h > 0.0 && !cubemap) {
		if (etoiles > 0.0) {
			c += etoile(d) * etoiles * smoothstep(0.03, 0.2, h) / max(energie, 0.2);
		}
		vec2 uv = d.xz / (h + 0.08) * 0.22 + vent;
		float n = texture(nuages, uv).r * 0.72 + texture(nuages, uv * 3.1 + vec2(0.37, 0.11)).g * 0.28;
		float a = smoothstep(couverture, couverture + 0.18, n) * smoothstep(0.0, 0.18, h);
		// relief : la masse un peu plus loin vers le soleil assombrit le dessous
		vec2 vers = l0 ? normalize(l0_dir.xz + vec2(1e-4)) : vec2(0.0);
		float n2 = texture(nuages, uv + vers * 0.035).r * 0.72 + texture(nuages, (uv + vers * 0.035) * 3.1 + vec2(0.37, 0.11)).g * 0.28;
		float lum = clamp(0.55 + (n - n2) * 5.0, 0.0, 1.0);
		vec3 nc = mix(ombre, clair, lum);
		nc += sc * 0.35 * pow(max(s, 0.0), 6.0);                 // liseré lumineux près du soleil
		c = mix(c, nc * mix(1.0, energie, 0.5), a * 0.92);
		// arc-en-ciel : à 40,5-42,5° du point opposé au soleil (rouge dehors), arc secondaire pâle et inversé à
		// 50,5-53,5° ; sous l'horizon quand le soleil est à plus de 42° (midi) : comme le vrai, on ne le voit pas
		if (arc > 0.0 && l0) {
			float ang = degrees(acos(clamp(dot(d, -l0_dir), -1.0, 1.0)));
			vec3 col = arc_couleur((ang - 40.5) / 2.0) + 0.4 * arc_couleur((53.5 - ang) / 3.0);
			c += col * arc * 0.3 * smoothstep(0.0, 0.1, h) * (1.0 - 0.5 * a);
		}
	}
	return c * energie;
}
