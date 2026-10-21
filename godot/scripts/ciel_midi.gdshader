// Ciel de midi (v6.70, #122) : panorama HDR en deux images (pipeline/build_ciel_midi.py) au lieu d'une image de
// 4096 × 2048 avec mipmaps (45 Mo de mémoire vidéo -> 18) : la moitié haute à pleine définition, la moitié basse,
// jamais vue directement (relief et horizon devant), réduite au quart pour la lumière ambiante.
// Même projection que PanoramaSkyMaterial (SKY_COORDS) ; filtrage sans mipmaps : le ciel est toujours agrandi.
shader_type sky;

uniform sampler2D haut : filter_linear, repeat_enable;
uniform sampler2D bas : filter_linear, repeat_enable;

void sky() {
	vec2 c = SKY_COORDS;
	if (c.y < 0.5) {
		// pas de bouclage vertical : le zénith ne doit pas prendre la couleur de l'horizon
		COLOR = texture(haut, vec2(c.x, clamp(c.y * 2.0, 0.5 / 1024.0, 1.0 - 0.5 / 1024.0))).rgb;
	} else {
		COLOR = texture(bas, vec2(c.x, clamp(c.y * 2.0 - 1.0, 0.5 / 256.0, 1.0 - 0.5 / 256.0))).rgb;
	}
}
