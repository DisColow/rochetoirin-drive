// Feux tricolores : cycle de 60 s (vert 27 s, orange 3 s, rouge 30 s), décalé selon le carrefour et l'axe
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform int bulb = 0;          // 0 rouge, 1 orange, 2 vert
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = fract(sin(dot(floor(w.xz / 60.0), vec2(12.9898, 78.233))) * 43758.5453) * 60.0;
	// axes perpendiculaires d'un même carrefour en opposition de phase (rouge pour l'un quand l'autre est vert)
	vec3 n = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float t = mod(TIME + phase + (abs(n.x) > abs(n.z) ? 30.0 : 0.0), 60.0);
	int on = t < 27.0 ? 2 : (t < 30.0 ? 1 : 0);
	vec3 col = bulb == 0 ? vec3(1.0, 0.08, 0.05) : (bulb == 1 ? vec3(1.0, 0.55, 0.05) : vec3(0.1, 1.0, 0.45));
	ALBEDO = on == bulb ? col * 2.5 : col * 0.08;
}
