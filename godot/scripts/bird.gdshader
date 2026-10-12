// Oiseaux au loin : silhouette sombre dessinée par le calcul (ailes en V qui battent), quadrilatère face à la caméra.
// INSTANCE_CUSTOM : x = phase du battement, y = vitesse du battement, z = plané (0 bat, 1 plane).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform vec4 tint : source_color = vec4(0.07, 0.07, 0.08, 1.0);

varying float v_flap;

void vertex() {
	vec3 org = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 wp = org + (right * VERTEX.x + up * VERTEX.y) * s;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	float glide = INSTANCE_CUSTOM.z;
	v_flap = mix(sin(TIME * INSTANCE_CUSTOM.y + INSTANCE_CUSTOM.x * 6.283), 0.15, glide);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;
	float ax = abs(p.x);
	float wy = v_flap * 0.55 * ax - 0.12 * ax * ax;
	float th = 0.1 * (1.0 - ax) + 0.025;
	bool wing = ax < 0.98 && abs(p.y - wy) < th;
	bool body = (p.x / 0.2) * (p.x / 0.2) + ((p.y + 0.03) / 0.11) * ((p.y + 0.03) / 0.11) < 1.0;
	if (!(wing || body)) {
		discard;
	}
	ALBEDO = tint.rgb;
}
