// Peinture de la voiture du joueur (garage, issue #43 ; tuning.gd) : couleur, finition (vernie, nacrée, mate, chromée)
// et vinyles posés dans le repère de la voiture (x à gauche, y en haut, z vers l'avant) :
//   1 bandes de course (dessus, avant, arrière), 2 bande latérale, 3-6 motifs de vinyles.png vus de côté
//   (3 flammes, 4 éclairs, 5 damier, 6 camouflage, ce dernier aussi sur le dessus).
// Vinyles coupés au seuil : pas de transparence mélangée (docs/kb/performances.md).
shader_type spatial;

uniform vec3 couleur : source_color = vec3(0.015, 0.015, 0.018);
uniform float metal = 0.0;
uniform float rugosite = 0.32;
uniform float vernis = 0.8;
uniform float vernis_rug = 0.1;
uniform float nacre = 0.0;          // reflet coloré en bord de pièce
uniform int vinyle = 0;
uniform sampler2D vin_tex : source_color, filter_linear_mipmap;
uniform vec3 vin_col : source_color = vec3(0.95);
uniform mat4 vers_voiture;          // repère du maillage -> repère de la voiture
uniform vec4 bornes = vec4(-2.81, 2.64, -0.17, 1.72);   // z min, z max, y min, y max de la caisse

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = (vers_voiture * vec4(VERTEX, 1.0)).xyz;
	ln = normalize(mat3(vers_voiture) * NORMAL);
}

float bande(float x, float a, float b, float f) {
	return smoothstep(a - f, a + f, x) * (1.0 - smoothstep(b - f, b + f, x));
}

void fragment() {
	vec3 c = couleur;
	float m = metal;
	float r = rugosite;
	float u = (lp.z - bornes.x) / (bornes.y - bornes.x);           // 0 arrière -> 1 avant
	float v = 1.0 - (lp.y - bornes.z) / (bornes.w - bornes.z);     // 0 haut -> 1 bas
	vec4 vin = vec4(0.0);
	if (vinyle == 1) {
		float ax = abs(lp.x);
		float a = bande(ax, 0.10, 0.27, 0.004) * (1.0 - bande(ax, 0.155, 0.165, 0.002));
		vin = vec4(vin_col, a * step(-0.3, ln.y));
	} else if (vinyle == 2) {
		float y0 = 0.60 + (lp.z - bornes.x) * 0.02;                // filet qui monte vers l'avant
		vin = vec4(vin_col, bande(lp.y, y0, y0 + 0.07, 0.004) * step(0.4, abs(ln.x)) * step(u, 0.97) * step(0.03, u));
	} else if (vinyle >= 3) {
		float rang = float(vinyle - 3);
		vec2 uv = vec2(u, (v + rang) / 4.0);
		float cote = step(0.35, abs(ln.x));
		if (vinyle == 6 && cote < 0.5) {
			uv = vec2(u, (clamp(lp.x * 0.25 + 0.5, 0.0, 1.0) + rang) / 4.0);   // camouflage : aussi le dessus
			cote = 1.0;
		}
		vin = texture(vin_tex, clamp(uv, vec2(0.002, rang / 4.0 + 0.002), vec2(0.998, (rang + 1.0) / 4.0 - 0.002)));
		vin.a *= cote;
	}
	if (vin.a > 0.5) {
		c = vin.rgb;
		m = 0.0;
		r = max(r, 0.35);
	}
	if (nacre > 0.0) {
		float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		c = mix(c, c.gbr * 0.6 + vec3(0.25, 0.22, 0.35) * 0.5, f * nacre);
	}
	ALBEDO = c;
	METALLIC = m;
	ROUGHNESS = r;
	CLEARCOAT = vernis;
	CLEARCOAT_ROUGHNESS = vernis_rug;
}
