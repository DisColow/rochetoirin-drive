// Enrobé : texture PBR mélangée à deux échelles (casse la répétition des fissures), grandes plaques plus sombres ou
// plus claires (reprises, usure), légère brillance d'usure ; coordonnées monde.
shader_type spatial;
render_mode cull_back;
#include "res://scripts/env.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.62, 0.62, 0.63);
uniform float scale = 0.30;
uniform bool motorway = false;     // enrobé d'autoroute : plus sombre et plus uniforme, sans regards ni reprises

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 u1 = p * scale;
	vec2 u2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * scale * 0.37 + vec2(0.31, 0.17);
	float m = smoothstep(0.3, 0.7, vnoise(p * 0.05));
	vec3 a = mix(texture(albedo_tex, u1).rgb, texture(albedo_tex, u2).rgb, m);
	vec3 n = mix(texture(normal_tex, u1).rgb, texture(normal_tex, u2).rgb, m);
	float r = mix(texture(rough_tex, u1).r, texture(rough_tex, u2).r, m);
	// plaques : reprises plus sombres, zones usées plus claires
	float big = vnoise(p * 0.018) * 0.6 + vnoise(p * 0.07) * 0.4;
	float patch = smoothstep(0.62, 0.68, vnoise(p * 0.035 + 7.0));
	if (motorway) {
		// enrobé drainant : texture adoucie (moins de fissures), quelques bandes de reprise très étirées
		a = mix(a, vec3(dot(a, vec3(0.333))), 0.35) * 0.9 + 0.08 * vec3(0.42);
		big = vnoise(p * 0.006) * 0.7 + vnoise(p * 0.03) * 0.3;
		patch *= 0.35;
	}
	vec3 c = a * tint * (0.86 + 0.28 * big);
	c *= mix(1.0, 0.72, patch);
	// plaques d'égout en fonte (une case de 26 m sur cinq), anneau et motif de grille, posées dans l'enrobé
	vec2 mc = floor(p / 26.0);
	vec2 mp = (mc + vec2(0.3) + 0.4 * vec2(hash(mc), hash(mc + 7.3))) * 26.0;
	float md = length(p - mp);
	if (!motorway && hash(mc + 3.1) < 0.2 && md < 0.36) {
		float grid = step(0.5, fract((p.x - mp.x) * 7.0)) * 0.12 + step(0.5, fract((p.y - mp.y) * 7.0)) * 0.12;
		vec3 iron = vec3(0.16, 0.15, 0.14) * (0.8 + grid) * (md > 0.31 ? 0.75 : 1.0);
		c = mix(c, iron, smoothstep(0.36, 0.34, md));
		r = 0.45;
	}
	// pluie : enrobé assombri et brillant (reflets du ciel et des phares), flaques dans les creux avec ronds de gouttes
	float puddle = smoothstep(0.56, 0.63, vnoise(p * 0.11 + 3.0) * 0.7 + vnoise(p * 0.45) * 0.3) * smoothstep(0.4, 0.9, wet);
	c *= mix(1.0, 0.6, wet);
	c = mix(c, c * 0.5, puddle);
	ALBEDO = c * env_cloud(wpos.xz);
	vec2 cell = fract(p * 1.3) - 0.5;
	float ph = fract(hash(floor(p * 1.3)) + TIME * 0.9);
	float ring = sin((length(cell) - ph * 0.5) * 60.0) * (1.0 - ph) * step(length(cell), ph * 0.5 + 0.03);
	vec3 flat_n = vec3(0.5 + cell.x * ring * 0.25, 0.5 + cell.y * ring * 0.25, 1.0);
	NORMAL_MAP = mix(mix(n, vec3(0.5, 0.5, 1.0), wet * 0.5), flat_n, puddle);
	ROUGHNESS = mix(mix(clamp(r * 0.95 + 0.05 - patch * 0.08, 0.3, 1.0), 0.14, wet * 0.85), 0.03, puddle);
}
