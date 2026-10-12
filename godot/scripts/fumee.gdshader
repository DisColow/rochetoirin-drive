// Fumée, poussière et embruns des roues (façon Call of Duty 2 : grosses volutes éclairées, qui gonflent et se dissipent).
// Une particule = une instance de MultiMesh (quad 1 × 1) ; le panneau face à la caméra est calculé ici (les modes
// « billboard » de Godot ignorent la position et la taille de chaque instance en Compatibility).
// INSTANCE_CUSTOM : x = taille (m), y = rotation (rad), z = âge (0 … 1, choisit l'image de l'animation), w = opacité.
// COLOR (couleur de l'instance) : teinte de la matière (poussière beige, fumée blanche, eau grise…).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;

uniform sampler2D fumee_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 soleil_dir = vec3(0.4, 0.8, 0.3);     // vers le soleil (monde)
uniform vec3 soleil_coul = vec3(1.0, 0.96, 0.88);
uniform vec3 ambiant = vec3(0.55, 0.6, 0.68);

varying float v_age;
varying float v_alpha;
varying vec3 v_teinte;
varying vec3 v_soleil_vue;
varying float v_rot;

void vertex() {
	float taille = INSTANCE_CUSTOM.x;
	float rot = INSTANCE_CUSTOM.y;
	v_age = INSTANCE_CUSTOM.z;
	v_alpha = INSTANCE_CUSTOM.w;
	v_teinte = COLOR.rgb;
	v_rot = rot;
	vec2 c = vec2(cos(rot), sin(rot));
	vec2 o = vec2(VERTEX.x * c.x - VERTEX.y * c.y, VERTEX.x * c.y + VERTEX.y * c.x) * taille;
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX = centre + vec3(o, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	v_soleil_vue = normalize((VIEW_MATRIX * vec4(soleil_dir, 0.0)).xyz);
}

void fragment() {
	// image de l'animation (planche 4 × 4) d'après l'âge, fondu entre deux images voisines
	float f = clamp(v_age, 0.0, 0.999) * 15.0;
	float i0 = floor(f);
	float k = f - i0;
	vec2 uv0 = (vec2(mod(i0, 4.0), floor(i0 / 4.0)) + UV) / 4.0;
	float i1 = min(i0 + 1.0, 15.0);
	vec2 uv1 = (vec2(mod(i1, 4.0), floor(i1 / 4.0)) + UV) / 4.0;
	vec4 t = mix(texture(fumee_tex, uv0), texture(fumee_tex, uv1), k);
	// normale de la volute (repère du panneau, tourné avec lui) -> éclairage par le soleil
	vec3 n = t.rgb * 2.0 - 1.0;
	vec2 c = vec2(cos(v_rot), sin(v_rot));
	n.xy = vec2(n.x * c.x - n.y * c.y, n.x * c.y + n.y * c.x);
	float dif = clamp(dot(normalize(n), v_soleil_vue) * 0.6 + 0.4, 0.0, 1.0);
	// lumière qui traverse les bords fins (diffusion) : contre-jour lumineux, comme la vraie fumée
	float trav = pow(clamp(-v_soleil_vue.z, 0.0, 1.0), 2.0) * (1.0 - t.a) * 0.6;
	vec3 lum = ambiant + soleil_coul * (dif + trav);
	ALBEDO = v_teinte * lum;
	// pas de lecture de la profondeur (hint_depth_texture noircit tout le rendu en Compatibility) : fondu près de la
	// caméra pour qu'un nuage ne bouche jamais l'écran
	float doux = clamp((-VERTEX.z - 0.6) / 2.5, 0.0, 1.0);
	ALPHA = clamp(t.a * v_alpha * doux, 0.0, 1.0);
}
