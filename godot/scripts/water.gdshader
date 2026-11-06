// Eau des étangs, rivières et ruisseaux (water.gd). #183 (« rendu comme UE5 sans que ça rame ») : tout est calculé dans
// le shader, sans texture d'écran ni de profondeur (interdites en Compatibility, voir CLAUDE.md) :
// - houle : 4 trains de vagues de directions et longueurs différentes, normales analytiques (somme de sinus façon
//   Gerstner), plus des rides fines en bruit ; cours d'eau : tout est entraîné dans le sens du courant (UV2) ;
// - couleur : corps d'eau bleu-vert clair (au lieu du vert presque noir), plus clair sur les crêtes ;
// - reflets : Fresnel de Schlick qui renvoie la couleur du ciel du jeu (`ciel`, tenu à jour par water.gd), reflets
//   du soleil par le moteur (rugosité très faible, qui monte un peu sur les rides), scintillements au loin atténués ;
// - écume légère sur les crêtes des cours d'eau rapides.
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
#include "res://scripts/env.gdshaderinc"

uniform vec3 deep : source_color = vec3(0.020, 0.085, 0.090);
uniform vec3 shallow : source_color = vec3(0.060, 0.190, 0.170);
uniform vec3 ciel = vec3(0.62, 0.74, 0.88);           // couleur du ciel à l'horizon (water.gd)

varying vec3 wpos;
varying vec2 flow;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = UV2;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// un train de vagues : direction d, longueur l (m), amplitude a (m), vitesse c (m/s) ; ajoute la hauteur et la pente
void vague(vec2 p, vec2 d, float l, float a, float c, float t, inout float h, inout vec2 pente) {
	float k = 6.2831 / l;
	float ph = k * (dot(d, p) - c * t);
	h += a * sin(ph);
	pente += d * (a * k * cos(ph));
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	bool courant = length(flow) > 0.1;
	vec2 fd = courant ? normalize(flow) : vec2(0.8, 0.6);
	vec2 fs = vec2(-fd.y, fd.x);
	// entraînement par le courant (cours d'eau) ; brise lente (plans d'eau)
	vec2 q = courant ? p - fd * t * 1.4 : p;
	float h = 0.0;
	vec2 pente = vec2(0.0);
	float cal = courant ? 0.0 : 1.0;
	vague(q, normalize(fd + fs * 0.35), 7.0, 0.05, 1.2 * cal, t, h, pente);
	vague(q, normalize(fd - fs * 0.55), 4.3, 0.035, 1.0 * cal, t, h, pente);
	vague(q, normalize(fs + fd * 0.2), 2.6, 0.02, 0.8, t, h, pente);
	vague(q, normalize(-fs + fd * 0.6), 1.5, 0.012, 0.6, t, h, pente);
	// rides fines (bruit), plus marquées sur un cours d'eau
	float e = 0.06;
	vec2 rp = q * 2.3 + vec2(t * 0.21, -t * 0.17);
	float r0 = vnoise(rp);
	float rx = vnoise(rp + vec2(e, 0.0)) - r0;
	float rz = vnoise(rp + vec2(0.0, e)) - r0;
	float ar = courant ? 0.10 : 0.05;
	pente += vec2(rx, rz) / e * ar * 0.43;
	// atténuation au loin (sinon scintillement), normale
	float dist = length(VERTEX);
	float att = 1.0 - smoothstep(25.0, 260.0, dist);
	vec3 n_world = normalize(vec3(-pente.x * att, 1.0, -pente.y * att));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	// couleur du corps d'eau, crêtes plus claires
	float crete = clamp(h * 6.0 + 0.5, 0.0, 1.0);
	vec3 corps = mix(deep, shallow, 0.35 + 0.45 * crete);
	// reflet du ciel (Fresnel de Schlick, eau : F0 = 0,02)
	float cv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - cv, 5.0);
	vec3 c = mix(corps, ciel * 0.9, clamp(fres, 0.0, 0.85));
	// écume des cours d'eau rapides, sur les crêtes et les rides
	float ecume = courant ? smoothstep(0.72, 0.95, crete * 0.6 + r0 * 0.5) * clamp(length(flow), 0.0, 1.0) * 0.6 : 0.0;
	c = mix(c, vec3(0.9, 0.93, 0.95), ecume);
	ALBEDO = c * env_cloud(wpos.xz);
	ROUGHNESS = mix(0.03, 0.12, clamp(length(pente) * 0.6, 0.0, 1.0)) + ecume * 0.4;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
