// Bord « cascade » façon Golden Sun 2 (#157, cascade.gd) : distance signée à la limite de la zone jouable
// (world/zone_sdf.bin, positive dehors, 1 m par unité autour de 128) ; quand l'option est choisie, le monde s'efface
// au-delà de la limite (if (env_hors_monde(position monde)) discard; env_fade_keep le fait déjà). Inclus par
// env.gdshaderinc, et seul par far.gdshader. Matériaux opaques sans discard (relief Terrain3D, routes, bâtiments,
// lointain) : test sous #ifdef BOUT_MONDE, variante chargée seulement avec l'option (env.gd, set_bout_monde) ; un
// discard, même jamais atteint, couperait l'early-Z des GPU de téléphone en mode Collines.
uniform float env_bout_monde = 0.0;
uniform sampler2D env_zone_sdf : filter_linear, repeat_disable;
uniform vec4 env_zone_rect = vec4(0.0);

bool env_hors_monde(vec3 wp) {
	if (env_bout_monde < 0.5) {
		return false;
	}
	vec2 uv = (wp.xz - env_zone_rect.xy) * env_zone_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return true;
	}
	return texture(env_zone_sdf, uv).r * 255.0 > 128.0;
}
