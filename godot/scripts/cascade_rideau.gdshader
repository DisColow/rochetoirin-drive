// Bord « cascade » (#157, cascade.gd) : rideau d'eau qui tombe de la lèvre dans la mer de nuages. UV.x : abscisse le
// long du bord (m) ; UV.y : longueur parcourue depuis la lèvre (m) ; UV2.x : chute sous la lèvre (m), UV2.y : hauteur
// totale jusqu'aux nuages. Filets d'eau qui accélèrent en tombant, écume à la lèvre, embruns vers le bas.
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
	// filets : bruit très étiré verticalement qui défile vers le bas (vitesse de chute qui croît avec la hauteur)
	float defile = TIME * (2.5 + sqrt(ch + 1.0) * 1.6);
	float f1 = vnoise(vec2(UV.x * 0.9, (UV.y - defile) * 0.05));
	float f2 = vnoise(vec2(UV.x * 2.7 + 3.1, (UV.y - defile * 1.3) * 0.11));
	float filets = f1 * 0.55 + f2 * 0.45;
	float ecume = smoothstep(4.0, 0.0, ch) + smoothstep(0.55, 0.8, filets) * 0.6;
	vec3 eau = mix(vec3(0.12, 0.34, 0.40), vec3(0.55, 0.72, 0.78), filets);
	vec3 c = mix(eau, vec3(0.93, 0.97, 1.0), clamp(ecume, 0.0, 1.0));
	// embruns : vers le bas, l'eau se fond dans une brume claire
	float brume = smoothstep(0.35, 0.95, rel);
	c = mix(c, vec3(0.88, 0.92, 0.95), brume);
	ALBEDO = c;
	ROUGHNESS = mix(0.15, 0.8, max(ecume, brume));
	SPECULAR = 0.5;
	ALPHA = clamp(mix(0.82 + 0.15 * filets, 0.0, smoothstep(0.75, 1.0, rel)), 0.0, 1.0);
}
