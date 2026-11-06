// Bord « cascade » (#157, #180, cascade.gd) : rideau d'eau qui tombe de la lèvre dans la mer de nuages. UV.x : abscisse
// le long du bord (m) ; UV.y : longueur parcourue depuis la lèvre (m) ; UV2.x : chute sous la lèvre (m), UV2.y : hauteur
// totale jusqu'aux nuages. #180 : filets d'eau marqués qui accélèrent en tombant (vitesse de chute libre), relief et
// reflets (bump calculé à l'écran), écume épaisse à la lèvre, eau qui blanchit en tombant et se perd en embruns.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
#include "res://scripts/env.gdshaderinc"

varying vec3 v_wp;
varying vec2 v_chute;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_chute = UV2;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float ch = v_chute.x;
	float rel = clamp(ch / max(v_chute.y, 1.0), 0.0, 1.0);
	// position « emportée » par la chute : temps de chute libre jusqu'ici (sqrt), le motif descend en accélérant
	float tc = sqrt(2.0 * max(ch, 0.0) / 9.8);
	float s = tc * 3.0 - TIME * 1.6;
	float f1 = vnoise(vec2(UV.x * 1.1, s * 1.2));
	float f2 = vnoise(vec2(UV.x * 3.4 + 3.1, s * 2.6 + 0.7));
	float f3 = vnoise(vec2(UV.x * 7.0 + 1.7, s * 5.0));
	float filets = f1 * 0.5 + f2 * 0.32 + f3 * 0.18;
	// relief des filets
	float h = filets;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2) * 0.14;
	NORMAL = normalize(abs(det) * NORMAL - grad * 6.0);
	// écume : bourrelet à la lèvre, filets blancs, puis l'eau blanchit en tombant (air mêlé)
	float levre = smoothstep(3.0, 0.0, ch);
	float blanc = smoothstep(0.55, 0.78, filets) * (0.45 + 0.55 * smoothstep(0.0, 40.0, ch));
	float aere = smoothstep(5.0, 70.0, ch) * 0.55;
	float ecume = clamp(levre + blanc + aere * filets, 0.0, 1.0);
	vec3 eau = mix(vec3(0.06, 0.30, 0.36), vec3(0.32, 0.60, 0.66), filets);
	vec3 c = mix(eau, vec3(0.95, 0.98, 1.0), ecume);
	// embruns : vers le bas, l'eau se fond dans une brume claire
	float brume = smoothstep(0.3, 0.92, rel);
	c = mix(c, vec3(0.90, 0.93, 0.96), brume);
	ALBEDO = c * env_cloud(v_wp.xz);
	ROUGHNESS = mix(0.08, 0.75, max(ecume, brume));
	SPECULAR = 0.6;
	ALPHA = clamp(mix(0.86 + 0.12 * filets, 0.0, smoothstep(0.72, 1.0, rel)) * mix(0.75, 1.0, smoothstep(0.0, 0.3, filets + levre)), 0.0, 1.0);
}
