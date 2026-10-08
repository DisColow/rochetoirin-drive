// Voiture en sprite pixel art (build_car_sprite.py) : quad toujours face à la caméra, avancé vers elle (le bas du
// sprite ne s'enfonce pas dans la route), case de l'atlas choisie par car.gd (angle, hauteur, braquage), inclinaison
// de la caisse (roulis vu de la caméra), feux allumés la nuit et au freinage ; teinte selon l'heure (night).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
#include "res://scripts/env.gdshaderinc"

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D feux : filter_nearest, repeat_disable;
uniform vec2 grid = vec2(24.0, 16.0);
uniform vec2 cell = vec2(0.0);          // colonne, ligne
uniform float roll = 0.0;               // rad, sens horaire à l'écran
uniform float push = 2.4;               // avance vers la caméra (m)
uniform float head = 0.0;               // phares 0 … 1
uniform float tail = 0.0;               // feux arrière 0 … 1 (2 = frein)
uniform float night = 0.0;

varying vec3 v_wp;

void vertex() {
	vec3 c = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	float d = length(c);
	float k = max(d - push, 0.3) / max(d, 0.001);
	vec2 q = VERTEX.xy;
	float cr = cos(roll), sr = sin(roll);
	q = vec2(q.x * cr + q.y * sr, -q.x * sr + q.y * cr);
	vec3 v = c * k + vec3(q * k, 0.0);
	POSITION = PROJECTION_MATRIX * vec4(v, 1.0);
	v_wp = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec2 uv = (cell + clamp(UV, vec2(0.0005), vec2(0.9995))) / grid;
	vec4 a = texture(atlas, uv);
	if (a.a < 0.5) {
		discard;
	}
	vec3 f = texture(feux, uv).rgb;
	// lumière : plein jour ; doré au couchant ; bleu nuit éclairé par la lune
	vec3 tint = mix(vec3(1.0), vec3(1.0, 0.82, 0.68), clamp(night * 2.5, 0.0, 1.0) * step(night, 0.6));
	tint = mix(tint, vec3(0.30, 0.34, 0.5), smoothstep(0.5, 1.0, night));
	vec3 col = a.rgb * tint * env_cloud(v_wp.xz);
	col = mix(col, col * 0.85, wet);
	col += f.g * head * vec3(1.6, 1.5, 1.25) + f.r * tail * vec3(1.4, 0.12, 0.08);
	ALBEDO = col;
}
