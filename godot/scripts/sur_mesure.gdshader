// Bâtiments sur mesure (sur_mesure.gd, ex. la boulangerie) : façades « en aplat » peintes dans un atlas.
// Atlas alpha : 0 = mur, 0,5 = vitre (lisse, reflète le ciel), 1 = vitre éclairée la nuit.
// Couleur de sommet : r = rugosité, g = toit (variations, mousse au nord), b = mur (salissures, coulures).
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/env.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float night = 0.0;

varying vec3 wpos;
varying vec3 vcol;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR.rgb;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec4 a = texture(atlas, UV);
	float vitre = smoothstep(0.25, 0.45, a.a);
	vec3 col = a.rgb;
	if (vcol.b > 0.5) {
		// salissures douces et coulures sous l'égout (pas sur les vitres)
		col *= mix(0.92 + 0.12 * vnoise(wpos.xz * 0.35 + wpos.y * 0.2), 1.0, vitre);
		float s = vnoise(vec2((wpos.x + wpos.z) * 2.3, wpos.y * 0.12));
		col *= 1.0 - smoothstep(0.55, 0.92, s) * 0.10 * (1.0 - vitre);
	}
	if (vcol.g > 0.5) {
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		col *= 0.92 + 0.16 * vnoise(wpos.xz * 3.1 + wpos.y);
		float north = clamp(-wn.z * 1.6, 0.0, 1.0);
		col = mix(col, vec3(0.20, 0.24, 0.11), north * smoothstep(0.35, 0.8, vnoise(wpos.xz * 0.7 + 3.0)) * 0.45);
	}
	ALBEDO = col * env_cloud(wpos.xz) * (1.0 - 0.2 * wet);
	if (night > 0.0 && a.a > 0.75) {
		EMISSION = vec3(1.0, 0.72, 0.42) * 1.8 * night;
	}
	ROUGHNESS = mix(vcol.r, 0.04, vitre) * (1.0 - 0.45 * wet);
	SPECULAR = mix(0.35, 0.9, vitre);
	METALLIC = 0.0;
}
