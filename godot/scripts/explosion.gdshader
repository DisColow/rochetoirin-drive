// Explosions (#129) : boules de feu et fumée tirées de simulations (planches d'images de Unity Labs, CC0, voir
// pipeline/fetch_explosions.py). Une bouffée = une instance de MultiMesh (quad 1 × 1), panneau face à la caméra calculé
// ici comme fumee.gdshader (les modes « billboard » de Godot ignorent chaque instance en Compatibility).
// INSTANCE_CUSTOM : x = taille (m), y = rotation (rad), z = avancement de l'animation (0 … 1), w = opacité.
// COLOR : rgb = teinte de la fumée (poussière beige, fumée noire…), a = part de feu qui garde sa propre lumière.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;   // opaque tramé (Bayer + discard), sans mélange (v6.19)

uniform sampler2D planche : source_color, filter_linear_mipmap, repeat_disable;
uniform float grille = 5.0;          // images par côté de la planche
uniform float nb = 25.0;             // images de l'animation
uniform vec3 lumiere = vec3(1.0);    // lumière du moment sur la fumée (midi 1, nuit ~0,3, bleutée)
uniform float densite = 1.0;         // < 1 : bords des volutes plus pleins (moins de trous de tramage)

varying float v_age;
varying float v_alpha;
varying vec4 v_teinte;

void vertex() {
	float taille = INSTANCE_CUSTOM.x;
	float rot = INSTANCE_CUSTOM.y;
	v_age = INSTANCE_CUSTOM.z;
	v_alpha = INSTANCE_CUSTOM.w;
	v_teinte = COLOR;
	vec2 c = vec2(cos(rot), sin(rot));
	vec2 o = vec2(VERTEX.x * c.x - VERTEX.y * c.y, VERTEX.x * c.y + VERTEX.y * c.x) * taille;
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// panneau avancé vers la caméra d'un quart de sa taille : il ne se coupe pas dans le sol ni dans la voiture
	centre += normalize(-centre) * min(taille * 0.25, max(length(centre) - 1.0, 0.0));
	VERTEX = centre + vec3(o, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	// image de l'animation d'après l'avancement, fondu entre deux images voisines
	float f = clamp(v_age, 0.0, 1.0) * (nb - 1.0);
	float i0 = min(floor(f), nb - 1.0);
	float k = f - i0;
	float i1 = min(i0 + 1.0, nb - 1.0);
	vec2 uv0 = (vec2(mod(i0, grille), floor(i0 / grille)) + UV) / grille;
	vec2 uv1 = (vec2(mod(i1, grille), floor(i1 / grille)) + UV) / grille;
	vec4 t = mix(texture(planche, uv0), texture(planche, uv1), k);
	// feu : les pixels chauds (rouge bien plus fort que le bleu) gardent leur éclat, de jour comme de nuit ; la fumée
	// prend la teinte voulue et la lumière du moment
	float chaud = clamp((t.r - t.b) * 2.2 + (t.r - 0.75) * 2.0, 0.0, 1.0) * v_teinte.a;
	vec3 fumee = t.rgb * v_teinte.rgb * lumiere;
	ALBEDO = mix(fumee, t.rgb * 1.2, chaud);
	// pas de lecture de la profondeur (noircit tout le rendu en Compatibility) : fondu tout près de la caméra
	float doux = clamp((-VERTEX.z - 0.6) / 2.5, 0.0, 1.0);
	float couv = clamp(pow(t.a, densite) * v_alpha * doux, 0.0, 1.0);
	const float BAYER[16] = { 0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0 };
	if (couv <= (BAYER[int(mod(FRAGCOORD.x, 4.0)) + int(mod(FRAGCOORD.y, 4.0)) * 4] + 0.5) / 16.0) {
		discard;
	}
}
