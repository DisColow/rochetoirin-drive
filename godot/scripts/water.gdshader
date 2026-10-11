// Eau : surface lisse qui reflète le ciel (rugosité faible, Fresnel), vaguelettes animées en normales procédurales ;
// cours d'eau : vaguelettes entraînées dans le sens du courant (UV2 = direction), plans d'eau : brise lente.
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/env.gdshaderinc"

uniform vec3 deep : source_color = vec3(0.035, 0.07, 0.065);
uniform vec3 shallow : source_color = vec3(0.10, 0.15, 0.11);

varying vec3 wpos;
varying vec2 flow;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = UV2;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float waves(vec2 p, vec2 drift) {
	return vnoise(p * 1.7 + drift) * 0.6 + vnoise(p * 4.3 - drift * 1.7) * 0.4;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	vec2 drift = length(flow) > 0.1 ? -flow * t * 1.2 : vec2(t * 0.15, t * 0.11);
	float e = 0.08;
	float h0 = waves(p, drift);
	float hx = waves(p + vec2(e, 0.0), drift);
	float hz = waves(p + vec2(0.0, e), drift);
	float dist = length(VERTEX);
	float amp = 0.35 * (1.0 - smoothstep(30.0, 250.0, dist));       // pas de scintillement au loin
	vec3 n_world = normalize(vec3(-(hx - h0) / e * amp, 1.0, -(hz - h0) / e * amp));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep, shallow, 0.4 + 0.3 * h0) * (1.0 - fres * 0.6) * env_cloud(wpos.xz);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
