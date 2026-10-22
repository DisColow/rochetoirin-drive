// Commerces (modèles Blender) : un seul shader, comportement selon « kind » :
// 0 uni, 1 enseigne (case de l'atlas en INSTANCE_CUSTOM, éclairée la nuit), 2 toile rayée (couleur d'instance),
// 3 couleur d'instance (bandeaux, auvents), 4 intérieur de boutique (rayons, éclairé la nuit), 5 lumineux (croix,
// carotte, ampoules), 6 verre opaque à intérieur simulé (Interior Mapping, v6.19) ; plus l'ambiance (ombre des nuages, pluie).
// « fusion » (#124 étape 2, shops.gd _fusionner) : tous les matériaux d'un modèle en une surface, chacun lu dans UV2.
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/env.gdshaderinc"

uniform int kind = 0;
uniform vec3 albedo : source_color = vec3(0.8);
uniform float rough = 0.5;
uniform float metal = 0.0;
uniform vec3 glow : source_color = vec3(0.0);
uniform float night = 0.0;
uniform float grid = 0.0;            // filets et grillages : maille (m), trous découpés
uniform bool fusion = false;         // matériau de chaque sommet dans UV2 (genre, couleur, rugosité, métal ou lueur)
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D atlas2 : source_color, filter_linear_mipmap_anisotropic, repeat_disable;   // 2e page (x + 10)
uniform sampler2D atlas3 : source_color, filter_linear_mipmap_anisotropic, repeat_disable;   // 3e page (x + 20)

varying vec4 v_c;
varying vec3 v_wp;
varying flat int v_kind;
varying vec3 v_alb;
varying vec3 v_glow;
varying vec2 v_rm;

vec3 octets(float a) {
	float r = floor(a / 65536.0);
	float g = floor((a - r * 65536.0) / 256.0);
	return vec3(r, g, a - r * 65536.0 - g * 256.0) / 255.0;
}

void vertex() {
	v_c = INSTANCE_CUSTOM;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_kind = kind;
	v_alb = albedo;
	v_glow = glow;
	v_rm = vec2(rough, metal);
	if (fusion) {
		v_alb = octets(UV2.x);
		if (UV2.y < 0.0) {
			v_kind = 5;
			v_glow = octets(-UV2.y - 1.0);
			v_rm = vec2(0.3, 0.0);
		} else {
			float k = floor(UV2.y / 16384.0);
			float r = floor((UV2.y - k * 16384.0) / 128.0);
			v_kind = int(k + 0.5);
			v_rm = vec2(r, UV2.y - k * 16384.0 - r * 128.0) / 127.0;
		}
	}
}

void fragment() {
	if (!env_fade_keep(v_wp, FRAGCOORD.xy)) {
		discard;
	}
	float sh = env_cloud(v_wp.xz);
	vec3 c = v_alb;
	float r = v_rm.x;
	int kd = v_kind;
	vec3 e = vec3(0.0);
	if (kd == 1) {
		vec2 cu = clamp(vec2(UV.x, 1.0 - UV.y), 0.004, 0.996) * v_c.zw;
		if (v_c.x >= 15.0) {
			c = texture(atlas3, vec2(v_c.x - 20.0, v_c.y) + cu).rgb;
		} else if (v_c.x >= 5.0) {
			c = texture(atlas2, vec2(v_c.x - 10.0, v_c.y) + cu).rgb;
		} else {
			c = texture(atlas, v_c.xy + cu).rgb;
		}
		e = c * night * 0.9;
		r = 0.3;
	} else if (kd == 2) {
		float st = step(0.5, fract(UV.x * 4.0));
		c = mix(v_c.rgb, vec3(0.93, 0.9, 0.82), st * 0.85);
	} else if (kd == 3) {
		c = v_c.a > 0.0 ? v_c.rgb : v_alb;
	} else if (kd == 4) {
		float shelf = step(0.75, fract(UV.y * 5.0)) * 0.35;
		float prod = step(0.5, fract(UV.x * 7.0 + floor(UV.y * 5.0) * 0.37)) * 0.25;
		c = v_alb * (0.75 + prod - shelf);
		e = vec3(1.0, 0.86, 0.62) * c * (0.25 + 0.9 * night);
	} else if (kd == 5) {
		e = v_glow * (0.35 + 2.2 * night);
	} else if (kd == 8) {
		// balise à chevrons bleus sur fond blanc
		float ch = step(0.5, fract(UV.x * 2.5 + abs(UV.y - 0.5) * 2.5));
		c = mix(vec3(0.95), vec3(0.08, 0.22, 0.58), ch);
	} else if (kd == 7) {
		vec2 g = fract(UV / grid);
		if (g.x > 0.18 && g.y > 0.18) {
			discard;
		}
	} else if (kd == 6) {
		// v6.19 : vitrine opaque à « Interior Mapping » : chaque vitre (case UV 0…1) cache une pièce de 1 de profondeur ;
		// le rayon de vue, ramené dans le repère de la vitre (TANGENT, BINORMAL, -NORMAL), touche le fond (rayons et
		// produits), les côtés, le sol ou le plafond (lampe). Aucun mélange : la vitre est un aplat opaque, le
		// reflet vient de ROUGHNESS/METALLIC.
		vec3 d = -VIEW;
		vec3 rd = vec3(dot(d, TANGENT), dot(d, BINORMAL), dot(d, -NORMAL));
		rd.z = abs(rd.z) + 0.001;
		vec3 ro = vec3(fract(UV), 0.0);
		rd = mix(rd, vec3(1e-5), step(abs(rd), vec3(1e-5)));   // pas de division par zéro
		vec3 k = (step(0.0, rd) - ro) / rd;                   // distance jusqu'à chaque paroi (toujours positive)
		float t = min(min(k.x, k.y), k.z);
		vec3 h = ro + rd * t;
		vec3 inside;
		if (k.z <= t + 1e-4) {
			float shelf = step(0.72, fract(h.y * 4.0));
			float prod = step(0.45, fract(h.x * 5.0 + floor(h.y * 4.0) * 0.31));
			inside = mix(vec3(0.32, 0.3, 0.27), vec3(0.62, 0.5, 0.36), prod) * (1.0 - shelf * 0.5);
		} else if (k.x <= t + 1e-4) {
			inside = vec3(0.55, 0.52, 0.46) * (0.8 + 0.2 * step(0.5, fract(h.z * 3.0)));
		} else if (rd.y > 0.0) {
			inside = vec3(0.36, 0.33, 0.3) * (0.85 + 0.15 * step(0.5, fract((h.x + h.z) * 4.0)));   // sol (UV.y vers le bas)
		} else {
			inside = vec3(0.8, 0.78, 0.72) + vec3(0.6, 0.5, 0.3) * step(length(h.xz - vec2(0.5)), 0.12);   // plafond, lampe
		}
		inside *= 1.0 - 0.45 * t;                      // le fond de la pièce est plus sombre
		float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		c = mix(inside * 0.6, vec3(0.45, 0.52, 0.6), fr * 0.6);
		e = inside * vec3(1.0, 0.88, 0.7) * (0.12 + 1.1 * night) * (1.0 - fr);
		r = 0.06;
	}
	ALBEDO = c * sh * (1.0 - 0.15 * wet);
	ROUGHNESS = mix(r, 0.08, wet * 0.6);
	METALLIC = kd == 6 ? 0.25 : v_rm.y;
	EMISSION = e;
}
