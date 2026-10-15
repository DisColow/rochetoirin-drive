// Traînée de condensation de l'avion de ligne (ciel.gd) : ruban blanc qui s'élargit et s'efface vers l'arrière,
// transparence tramée (pas de transparence mélangée, docs/kb/performances.md).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

void vertex() {
	VERTEX.y *= mix(0.25, 1.6, UV.x);          // fine derrière l'avion, étalée au loin
}

void fragment() {
	float x = UV.x;
	float a = smoothstep(0.0, 0.015, x) * pow(1.0 - x, 1.6);
	float bord = 1.0 - abs(UV.y * 2.0 - 1.0);
	a *= smoothstep(0.0, 0.6, bord) * 0.85;
	// matrice de Bayer 4 × 4
	ivec2 p = ivec2(FRAGCOORD.xy) % 4;
	int i = p.x + p.y * 4;
	float seuil[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	if (a <= (seuil[i] + 0.5) / 16.0) {
		discard;
	}
	ALBEDO = vec3(0.96, 0.97, 1.0);
}
