// Relief de remplacement (relief.gd) : là où la région Terrain3D n'est pas chargée, maillage léger habillé de l'aspect
// du vrai relief vu de loin (albédo, normale du monde, rugosité / AO / spéculaire cuits par tools/bake_relief.gd).
// Masque 32 × 32 (une case par région, 1 = chargée) : là, le remplaçant s'efface, sauf une bordure de 32 m le long
// des régions non chargées, glissée sous le vrai relief (aucun interstice au raccord).
shader_type spatial;
render_mode cull_back;

#include "res://scripts/env.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normale_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D matiere_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D masque : filter_nearest, repeat_disable;
uniform vec4 zone = vec4(0.0, 0.0, 1.0, 1.0);    // x0, z0, largeur, profondeur (m) couvertes par les textures

const float REG = 1024.0;
const float BORD = 32.0;

varying vec2 v_xz;

bool charge(vec2 p) {
	ivec2 c = ivec2(floor(p / REG)) + ivec2(16);
	if (c.x < 0 || c.y < 0 || c.x > 31 || c.y > 31) {
		return false;
	}
	return texelFetch(masque, c, 0).r > 0.5;
}

void vertex() {
	v_xz = VERTEX.xz;
	// sommet entouré de régions chargées : sous le vrai relief
	if (charge(VERTEX.xz + vec2(0.5, 0.5)) && charge(VERTEX.xz + vec2(-0.5, 0.5))
			&& charge(VERTEX.xz + vec2(0.5, -0.5)) && charge(VERTEX.xz + vec2(-0.5, -0.5))) {
		VERTEX.y -= 4.0;
	}
}

void fragment() {
	vec2 p = v_xz;
	if (env_hors_monde(vec3(p.x, 0.0, p.y))) {          // bord « cascade » (#157)
		discard;
	}
	if (charge(p)) {
		vec2 f = p - floor(p / REG) * REG;
		bool bord = (f.x < BORD && !charge(p - vec2(REG, 0.0))) || (f.x > REG - BORD && !charge(p + vec2(REG, 0.0)))
				|| (f.y < BORD && !charge(p - vec2(0.0, REG))) || (f.y > REG - BORD && !charge(p + vec2(0.0, REG)));
		if (!bord) {
			discard;
		}
	}
	vec2 uv = (p - zone.xy) / zone.zw;
	vec3 n = normalize(texture(normale_tex, uv).xyz * 2.0 - 1.0);
	vec3 m = texture(matiere_tex, uv).rgb;
	float wet_k = wet * smoothstep(0.6, 0.95, n.y);
	ALBEDO = texture(albedo_tex, uv).rgb * env_cloud(p) * (1.0 - 0.38 * wet_k);
	ROUGHNESS = mix(m.r, 0.22, wet_k * 0.85);
	AO = m.g;
	SPECULAR = m.b;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
