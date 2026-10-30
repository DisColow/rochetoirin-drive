// Bord « cascade » (#157, cascade.gd) : mer de nuages sous le monde, dans laquelle tombe la cascade. Grand plan qui
// suit la caméra ; nuages en relief (bruit fractal, ombré par le soleil) qui dérivent lentement.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { s += a * vnoise(p); p = p * 2.03 + 17.1; a *= 0.5; }
	return s;
}

void fragment() {
	vec2 p = v_wp.xz * 0.0045 + vec2(TIME * 0.004, TIME * 0.0025);
	float n = fbm(p);
	float e = 0.02;
	// relief des nuages : normale tirée du bruit (bourgeonnements)
	float nx = fbm(p + vec2(e, 0.0)) - n;
	float nz = fbm(p + vec2(0.0, e)) - n;
	NORMAL = normalize((VIEW_MATRIX * vec4(-nx * 40.0, 1.0, -nz * 40.0, 0.0)).xyz);
	// creux bleutés (ombre, profondeur) et sommets blancs
	float m = smoothstep(0.32, 0.72, n);
	ALBEDO = mix(vec3(0.42, 0.52, 0.66), vec3(0.96, 0.97, 0.99), m);
	ROUGHNESS = 1.0;
}
