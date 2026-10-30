// Chevrons de l'itinéraire (#154, fleches_route.gd) : « › » dessiné dans un carré posé à plat, pointe vers +Z (le
// sens de la marche) ; INSTANCE_CUSTOM.x = distance qui reste jusqu'à l'arrivée (m) : la vague de lumière la remonte.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 couleur : source_color = vec3(0.25, 0.65, 1.0);
uniform float longueur_vague = 42.0;  // m entre deux vagues
uniform float vitesse = 55.0;         // m/s

varying float v_reste;
varying float v_dist;

void vertex() {
	v_reste = INSTANCE_CUSTOM.x;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	// p.y vers l'avant (UV.y = 1 à l'avant du carré, côté +Z après rotation), p.x en travers
	vec2 p = vec2(UV.x * 2.0 - 1.0, UV.y * 2.0 - 1.0);
	float v = p.y + abs(p.x) * 1.1;                  // lignes de niveau en Λ, pointe vers l'avant (p.y = 1)
	float trait = 1.0 - smoothstep(0.2, 0.28, abs(v - 0.45));
	trait *= 1.0 - smoothstep(0.86, 0.98, abs(p.x));
	float vague = 0.5 + 0.5 * sin(6.2832 * (v_reste + TIME * vitesse) / longueur_vague);
	vague = pow(vague, 5.0);
	float fondu = smoothstep(3.0, 9.0, v_dist) * (1.0 - smoothstep(120.0, 165.0, v_dist));
	ALBEDO = mix(couleur * 1.35, vec3(1.0), 0.2 + 0.7 * vague);
	ALPHA = trait * fondu * (0.55 + 0.4 * vague);
}
