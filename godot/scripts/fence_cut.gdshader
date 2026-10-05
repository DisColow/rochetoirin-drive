// Clôtures, murets, haies, portails : textures en tableau (couche = UV2.x), teinte par clôture (couleur de sommet).
// Matériau « cut » : alpha de l'albédo = découpe (grillages, grilles, bord feuillu des haies), deux faces.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool cut = false;

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
	if (cut) {
		// découpe qui tient au loin : l'alpha moyenné des niveaux de mipmap est renforcé (fils fins encore visibles)
		vec2 dx = dFdx(UV * 512.0); vec2 dy = dFdy(UV * 512.0);
		float lod = 0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1e-6));
		if (a.a * (1.0 + max(lod, 0.0) * 0.7) < 0.5) { discard; }
	}
	// variation douce de couleur (haies moins uniformes, salissures)
	float v = 0.86 + 0.24 * vnoise(wpos.xz * 0.45 + wpos.y * 0.3);
	ALBEDO = a.rgb * tint * tint * v;
	ROUGHNESS = n.a;
	NORMAL_MAP = n.rgb;
	NORMAL_MAP_DEPTH = 1.0;
}
