// Touffes de végétation basse : deux plans croisés par touffe, case de la planche (4 × 2) dans INSTANCE_CUSTOM.x,
// teinte en .y, phase du vent en .z ; balancement au vent (le haut seulement), base assombrie, fondu tramé au loin.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float fade_start = 35.0;
uniform float fade_end = 45.0;

varying float v_tint;
varying float v_dist;

void vertex() {
	float cell = floor(INSTANCE_CUSTOM.x * 8.0 + 0.5);
	float top = 1.0 - UV.y;
	float ph = INSTANCE_CUSTOM.z * 6.283 + TIME * 1.7;
	vec3 wind = vec3(sin(ph) * 0.06 + sin(ph * 2.3 + 1.0) * 0.025, 0.0, cos(ph * 0.8) * 0.04) * top * top;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * wind);
	UV = vec2((mod(cell, 4.0) + clamp(UV.x, 0.004, 0.996)) / 4.0, (floor(cell / 4.0) + clamp(UV.y, 0.004, 0.996)) / 2.0);
	v_tint = INSTANCE_CUSTOM.y;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	// éclairage doux : normale vers le haut (pas de plans noirs vus de côté)
	NORMAL = normalize(mix(NORMAL, (inverse(mat3(MODEL_MATRIX)) * vec3(0.0, 1.0, 0.0)), 0.75));
}

float bayer(vec2 p) {
	vec2 q = mod(floor(p), 4.0);
	return (q.x * 4.0 + q.y + mod(q.x + q.y, 2.0) * 8.0) / 16.0;
}

void fragment() {
	vec4 c = texture(atlas, UV);
	float f = clamp((v_dist - fade_start) / (fade_end - fade_start), 0.0, 1.0);
	if (c.a < 0.5 || f > bayer(FRAGCOORD.xy) * 0.999 + 0.0005 && f > 0.0) {
		discard;
	}
	ALBEDO = c.rgb * v_tint;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.25, 0.3, 0.12);
}
