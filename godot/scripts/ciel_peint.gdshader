// Ciel peint des heures sans photo (fin d'après-midi, coucher, nuit, temps gris : main.gd set_time / set_weather),
// avec des nuages (issue #57) : dégradé haut / horizon, soleil (ou lune), et un plafond de nuages projeté
// (assets/fx/nuages.png de pipeline/build_nuages_tex.py), éclairés côté soleil, plus sombres dessous, effacés vers
// l'horizon. Pas de TIME : un ciel qui change se recalcule entièrement (reflets) ; les nuages glissent par `vent`,
// mis à jour de loin en loin par main.gd.
shader_type sky;

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

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 c = mix(horizon, haut, pow(clamp(h, 0.0, 1.0), 0.55));
	if (h < 0.0) {
		c = mix(horizon * 0.85, sol, clamp(-h * 5.0, 0.0, 1.0));
	}
	float s = LIGHT0_ENABLED ? dot(d, LIGHT0_DIRECTION) : 0.0;
	vec3 sc = LIGHT0_ENABLED ? LIGHT0_COLOR * LIGHT0_ENERGY : vec3(0.0);
	c += sc * (smoothstep(1.0 - 0.0006 * taille_soleil, 1.0 - 0.0002 * taille_soleil, s) * 6.0 + pow(max(s, 0.0), 48.0) * 0.3);
	if (h > 0.0 && !AT_CUBEMAP_PASS) {
		vec2 uv = d.xz / (h + 0.08) * 0.22 + vent;
		float n = texture(nuages, uv).r * 0.72 + texture(nuages, uv * 3.1 + vec2(0.37, 0.11)).g * 0.28;
		float a = smoothstep(couverture, couverture + 0.18, n) * smoothstep(0.0, 0.18, h);
		// relief : la masse un peu plus loin vers le soleil assombrit le dessous
		vec2 vers = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION.xz + vec2(1e-4)) : vec2(0.0);
		float n2 = texture(nuages, uv + vers * 0.035).r * 0.72 + texture(nuages, (uv + vers * 0.035) * 3.1 + vec2(0.37, 0.11)).g * 0.28;
		float lum = clamp(0.55 + (n - n2) * 5.0, 0.0, 1.0);
		vec3 nc = mix(ombre, clair, lum);
		nc += sc * 0.35 * pow(max(s, 0.0), 6.0);                 // liseré lumineux près du soleil
		c = mix(c, nc * mix(1.0, energie, 0.5), a * 0.92);
	}
	COLOR = c * energie;
}
