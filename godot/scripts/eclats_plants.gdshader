// Morceaux de plants écrasés (issue #8 : « des morceaux de sprite qui volent ») : chaque éclat est un petit plan
// découpé dans l'atlas des plants (assets/veg/plants_albedo.png, même image que les plants du champ), qui tournoie.
// Données d'instance : CUSTOM = (u0, v0, du, dv) du morceau dans l'atlas ; COLOR.a = effacement en fin de vie.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D plants_atlas : source_color, filter_linear_mipmap, repeat_disable;

varying vec4 v_uv;
varying float v_a;

void vertex() {
	v_uv = INSTANCE_CUSTOM;
	v_a = COLOR.a;
}

void fragment() {
	vec4 c = texture(plants_atlas, v_uv.xy + UV * v_uv.zw);
	// bord du morceau un peu déchiré (pas de découpe rectangulaire nette) ; effacement tramé en fin de vie
	vec2 e = min(UV, 1.0 - UV);
	float dech = fract(sin(dot(floor(UV * 9.0), vec2(12.9898, 78.233))) * 43758.5453);
	if (c.a < 0.5 || min(e.x, e.y) < dech * 0.12 || v_a < fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453)) {
		discard;
	}
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(FRONT_FACING ? NORMAL : -NORMAL, up, 0.35));
	ALBEDO = c.rgb * 0.88;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
