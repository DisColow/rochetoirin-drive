// Bâtiments : un seul matériau, textures en tableau (couche = UV2.x), teinte par bâtiment (couleur de sommet).
// Albédo alpha = vitrage (lisse, reflète le ciel) ; normale alpha = rugosité.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;

varying flat float layer;
varying vec3 tint;
varying vec3 wpos;

void vertex() {
	layer = UV2.x;
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
	ALBEDO = a.rgb * t * mix(dirt, 1.0, a.a);
	ROUGHNESS = mix(n.a, 0.04, a.a);
	SPECULAR = mix(0.4, 0.9, a.a);
	METALLIC = 0.0;
	NORMAL_MAP = n.rgb;
	NORMAL_MAP_DEPTH = 1.0;
}
