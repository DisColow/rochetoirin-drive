// Ciel de midi (v6.70, #122) : panorama HDR en deux images (pipeline/build_ciel_midi.py) au lieu d'une image de
// 4096 × 2048 avec mipmaps (45 Mo de mémoire vidéo -> 18) : la moitié haute à pleine définition, la moitié basse,
// jamais vue directement (relief et horizon devant), réduite au quart pour la lumière ambiante.
// Même projection que PanoramaSkyMaterial (SKY_COORDS) ; filtrage sans mipmaps : le ciel est toujours agrandi.
// v6.91 (météo variable) : `gris` mêle le ciel peint de ciel_nuages.gdshaderinc (mêmes réglages que le ciel gris
// qui suit) : à 1, l'image est celle de ciel_peint.gdshader, main.gd passe alors à ce ciel sans saut.
shader_type sky;

#include "res://scripts/ciel_nuages.gdshaderinc"

uniform sampler2D photo_haut : filter_linear, repeat_enable;
uniform sampler2D photo_bas : filter_linear, repeat_enable;
uniform float gris = 0.0;

void sky() {
	vec2 c = SKY_COORDS;
	if (c.y < 0.5) {
		// pas de bouclage vertical : le zénith ne doit pas prendre la couleur de l'horizon
		COLOR = texture(photo_haut, vec2(c.x, clamp(c.y * 2.0, 0.5 / 1024.0, 1.0 - 0.5 / 1024.0))).rgb;
	} else {
		COLOR = texture(photo_bas, vec2(c.x, clamp(c.y * 2.0 - 1.0, 0.5 / 256.0, 1.0 - 0.5 / 256.0))).rgb;
	}
	if (gris > 0.0) {
		COLOR = mix(COLOR, ciel_peint(EYEDIR, LIGHT0_ENABLED, LIGHT0_DIRECTION, LIGHT0_COLOR * LIGHT0_ENERGY, AT_CUBEMAP_PASS), gris);
	}
}
