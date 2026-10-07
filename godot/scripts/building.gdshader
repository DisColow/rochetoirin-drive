// Bâtiments : un seul matériau, textures en tableau (couche = UV2.x), teinte par bâtiment (couleur de sommet).
// Albédo alpha = vitrage (lisse, reflète le ciel) ; normale alpha = rugosité.
shader_type spatial;
render_mode cull_back;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float night = 0.0;

varying flat float layer;
varying flat float ground;
varying vec3 tint;
varying vec3 wpos;

void vertex() {
	layer = UV2.x;
	ground = UV2.y;
	tint = COLOR.rgb;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec4 a = texture(albedo_tex, vec3(UV, layer));
	vec4 n = texture(normal_tex, vec3(UV, layer));
	// salissures douces à grande échelle (casse la répétition des textures), pas sur les vitres
	float dirt = 0.88 + 0.16 * vnoise(wpos.xz * 0.35 + wpos.y * 0.2);
	vec3 t = mix(tint * tint, vec3(1.0), a.a);
	// ombre douce au pied des murs (sol du bâtiment en UV2.y ; 0 = inconnu)
	float ao = ground > 1.0 ? mix(0.58, 1.0, smoothstep(0.0, 1.8, wpos.y - ground)) : 1.0;
	vec3 col = a.rgb * t * mix(dirt, 1.0, a.a) * ao;
	int L = int(layer + 0.5);
	bool is_wall = L <= 7 || L == 20;
	bool is_roof = (L >= 8 && L <= 11) || L == 19;
	if (is_wall) {
		// coulures verticales (pluie sous les appuis, en haut des murs)
		float s = vnoise(vec2((wpos.x + wpos.z) * 2.3, wpos.y * 0.12));
		col *= 1.0 - smoothstep(0.55, 0.92, s) * 0.13 * (1.0 - a.a);
	}
	if (is_roof) {
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		// tuiles inégales et mousse / lichen sur les pans orientés au nord
		col *= 0.92 + 0.16 * vnoise(wpos.xz * 3.1 + wpos.y);
		float north = clamp(-wn.z * 1.6, 0.0, 1.0);
		float moss = north * smoothstep(0.35, 0.8, vnoise(wpos.xz * 0.7 + 3.0)) * 0.55;
		col = mix(col, vec3(0.20, 0.24, 0.11), moss);
	}
	ALBEDO = col;
	// le soir et la nuit : une partie des fenêtres éclairées (lumière chaude), au hasard par fenêtre
	if (night > 0.0 && a.a > 0.5) {
		float lit = step(0.5, hash(floor(wpos.xz * 0.9) + floor(wpos.y / 2.7) * 7.31));
		EMISSION = vec3(1.0, 0.72, 0.42) * 1.8 * night * lit * a.a;
	}
	ROUGHNESS = mix(n.a, 0.04, a.a);
	SPECULAR = mix(0.4, 0.9, a.a);
	METALLIC = 0.0;
	NORMAL_MAP = n.rgb;
	NORMAL_MAP_DEPTH = 1.0;
}
