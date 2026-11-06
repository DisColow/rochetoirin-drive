// Bord « cascade » (#157, #180, cascade.gd) : rivière peu profonde qui court vers la lèvre. UV.x : abscisse le long du
// bord (m) ; UV.y : distance à la lèvre (m, 0 à la lèvre, 14 en amont où l'eau se fond dans le sol).
// #180 : courant lisible (stries étirées dans le sens de l'écoulement qui filent vers la lèvre en accélérant), relief
// des vagues par « bump » calculé à l'écran (pas de texture ni de tangentes), reflets du soleil, couleur qui passe du
// vert profond au turquoise près de la chute, écume qui se forme à l'approche de la lèvre et sur les crêtes.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
#include "res://scripts/env.gdshaderinc"

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float d = UV.y;
	float pres = 1.0 - clamp(d / 14.0, 0.0, 1.0);           // 0 en amont, 1 à la lèvre
	// courant qui accélère vers la lèvre : abscisse « emportée » (s'intègre en d²) pour que les motifs s'étirent
	float vit = 1.6 + 5.5 * pres * pres;
	float s = d * (1.0 + 0.18 * d) * 0.5 + TIME * vit;
	// stries : bruit étiré dans le sens du courant (fréquence faible en s, forte le long du bord)
	float st1 = vnoise(vec2(UV.x * 1.3, s * 0.22));
	float st2 = vnoise(vec2(UV.x * 3.1 + 5.7, s * 0.5 + 1.3));
	float vag = vnoise(vec2(UV.x * 0.45 + s * 0.08, s * 0.35 - TIME * 0.4));      // houle qui roule
	float h = st1 * 0.45 + st2 * 0.25 + vag * 0.3;
	// relief : gradient de surface d'après les dérivées à l'écran (méthode de Mikkelsen)
	float amp = mix(0.05, 0.16, pres);
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float hx = dFdx(h) * amp;
	float hy = dFdy(h) * amp;
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (hx * r1 + hy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * 6.0);
	// écume : à l'approche de la lèvre (bouillonnement), sur les crêtes des stries, et un liseré en amont
	float bouillon = smoothstep(4.5, 0.0, d) * (0.45 + 0.55 * st2);
	float cretes = smoothstep(0.66, 0.86, st1 * 0.6 + st2 * 0.4) * (0.25 + 0.75 * pres);
	float ecume = clamp(bouillon + cretes, 0.0, 1.0);
	vec3 profond = vec3(0.03, 0.17, 0.22);
	vec3 clair = vec3(0.10, 0.40, 0.44);
	vec3 eau = mix(profond, clair, pres * 0.8 + vag * 0.2);
	ALBEDO = mix(eau, vec3(0.93, 0.97, 1.0), ecume) * env_cloud(v_wp.xz);
	ROUGHNESS = mix(0.04, 0.5, ecume);
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = mix(0.0, 0.92, smoothstep(14.0, 8.5, d)) * mix(1.0, 0.97, ecume);
}
