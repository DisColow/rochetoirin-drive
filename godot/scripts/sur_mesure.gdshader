// Bâtiments sur mesure (sur_mesure.gd, ex. la boulangerie) : façades « en aplat » peintes dans un atlas.
// Atlas alpha : 0 = mur, 0,5 = vitre (lisse, reflète le ciel), 1 = vitre éclairée la nuit.
// Couleur de sommet : r = rugosité, g = toit (variations, mousse au nord), b = mur (salissures, coulures).
shader_type spatial;
render_mode cull_disabled;
#include "res://scripts/sur_mesure.gdshaderinc"
