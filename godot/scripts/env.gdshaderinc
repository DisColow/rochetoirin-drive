// Ambiance partagée par les matériaux du monde (paramètres de chaque matériau, tenus à jour par env.gd) :
//  wind   : x, y = direction du vent (plan xz), z = force (0 calme … 1 fort), w = inutilisé ;
//  clouds : x = assombrissement sous un nuage (0 = pas d'ombres de nuages), y = seuil de couverture, z, w inutilisés ;
//  wet    : 0 sec … 1 détrempé (pluie).
uniform vec4 wind = vec4(0.8, 0.6, 0.55, 0.0);
uniform vec4 clouds = vec4(0.0);
uniform float wet = 0.0;

// Rafales qui traversent le paysage dans le sens du vent (0 … 1).
float env_gust(vec2 p) {
	vec2 d = wind.xy;
	float a = dot(p, d) * 0.045 - TIME * (1.0 + wind.z * 1.2);
	float b = dot(p, vec2(-d.y, d.x)) * 0.019 + TIME * 0.21;
	float g = sin(a + sin(b) * 2.2) * (0.65 + 0.35 * sin(b * 1.7 + a * 0.31));
	return clamp(0.5 + 0.5 * g, 0.0, 1.0);
}

// Ombre des nuages qui défilent avec le vent : 1 au soleil, 1 - clouds.x sous un nuage.
float env_cloud(vec2 p) {
	if (clouds.x <= 0.0) {
		return 1.0;
	}
	vec2 q = p * 0.0032 - wind.xy * TIME * 0.016;
	float n = sin(q.x * 1.7 + sin(q.y * 1.3)) * sin(q.y * 1.9 + sin(q.x * 0.7 + 1.3));
	n += 0.5 * sin(q.x * 3.1 - q.y * 2.3 + 2.0) * sin(q.y * 3.7 + q.x * 1.1);
	n += 0.25 * sin(q.x * 7.3 + q.y * 5.1) * sin(q.y * 6.1 - q.x * 4.7);
	return 1.0 - clouds.x * smoothstep(clouds.y, clouds.y + 0.3, n);
}
