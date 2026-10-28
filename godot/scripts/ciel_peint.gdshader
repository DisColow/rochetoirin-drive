// Ciel peint des heures sans photo (fin d'après-midi, coucher, nuit, temps gris : main.gd set_time / _apply_weather),
// avec des nuages (issue #57) : code dans ciel_nuages.gdshaderinc. Pas de TIME : un ciel qui change se recalcule
// entièrement (reflets) ; les nuages glissent par `vent`, mis à jour de loin en loin par main.gd.
shader_type sky;

#include "res://scripts/ciel_nuages.gdshaderinc"

void sky() {
	COLOR = ciel_peint(EYEDIR, LIGHT0_ENABLED, LIGHT0_DIRECTION, LIGHT0_COLOR * LIGHT0_ENERGY, AT_CUBEMAP_PASS);
}
