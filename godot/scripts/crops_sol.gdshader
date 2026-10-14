// Sol des champs sous les plants (#142, issue #25 : « le sol en dessous c'est de la terre ») : terre (dirt) avec les
// sillons des rangs, posée sur le relief et effacée en fondu au loin (au-delà : l'orthophoto, vue d'ensemble du champ).
// Données d'instance : x, y = sens des rangs (plan xz), z = écartement des rangs (m), w = inutilisé.
shader_type spatial;
#include "res://scripts/env.gdshaderinc"

uniform sampler2D dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D trample_tex : filter_linear, repeat_disable;
uniform vec4 trample_zone = vec4(0.0, 0.0, 96.0, 0.0);

varying vec3 v_wp;
varying flat vec3 v_row;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_row = INSTANCE_CUSTOM.xyz;
}

void fragment() {
	// fondu large (dernier tiers de la portée) : la terre se fond dans l'orthophoto
	float d = length(v_wp - env_cam);
	if (fade_far > 0.0 && !env_dither_keep(clamp((fade_far - d) / (fade_far * 0.35), 0.0, 1.0), FRAGCOORD.xy)) {
		discard;
	}
	vec3 c = texture(dirt, v_wp.xz / 2.5).rgb * vec3(0.95, 0.9, 0.86);
	// sillons : creux plus sombre entre deux rangs, butte claire sous le rang
	vec2 dir = normalize(v_row.xy + vec2(1e-4));
	float t = dot(v_wp.xz, vec2(-dir.y, dir.x)) / max(v_row.z, 0.1);
	float s = 0.5 + 0.5 * cos(fract(t) * 6.2832);
	// contraste atténué au loin (sinon rayures et moiré quand les sillons deviennent plus fins qu'un pixel)
	float net = 1.0 - smoothstep(0.15, 0.5, fwidth(t));
	c *= mix(1.0, mix(0.82, 1.04, s), net);
	// trace de la voiture : terre tassée, plus sombre
	if (trample_zone.w > 0.5) {
		vec2 tuv = (v_wp.xz - trample_zone.xy) / trample_zone.z;
		if (tuv.x > 0.0 && tuv.y > 0.0 && tuv.x < 1.0 && tuv.y < 1.0) {
			c *= 1.0 - 0.22 * smoothstep(0.05, 0.6, texture(trample_tex, tuv).b);
		}
	}
	ALBEDO = c * env_cloud(v_wp.xz) * (1.0 - 0.35 * wet);
	ROUGHNESS = mix(0.95, 0.4, wet);
	SPECULAR = 0.2;
}
