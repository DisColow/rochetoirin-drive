// Imposteurs d'arbres : quadrilatère tourné vers la caméra (autour de la verticale), vue choisie parmi 8 selon l'angle
// de la caméra autour de l'arbre, normales cuites pour un éclairage cohérent avec les vrais modèles.
// Données d'instance (custom) : x = essence / 8 (ligne de l'atlas), y = rotation / 2π, z = teinte.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled;

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_disable;
uniform float near_cut = 60.0;         // en deçà : le vrai modèle 3D est affiché
uniform float far_cut = 1200.0;

varying vec3 v_right;
varying vec3 v_up;
varying vec3 v_to;
varying float v_dist;
varying float v_tint;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float scale = length(MODEL_MATRIX[0].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to = cam - origin;
	to.y = 0.0;
	v_dist = length(to);
	to = to / max(v_dist, 0.001);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to));
	vec3 wp = origin + right * VERTEX.x * scale + vec3(0.0, 1.0, 0.0) * (VERTEX.y + 0.5) * scale;
	// angle de la caméra dans le repère de l'arbre -> vue cuite la plus proche
	float ang = atan(to.x, to.z) - INSTANCE_CUSTOM.y * TAU;
	float v = mod(round(ang / (TAU / 8.0)), 8.0);
	UV = vec2((v + UV.x) / 8.0, (INSTANCE_CUSTOM.x * 8.0 + UV.y) / 8.0);
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	v_right = (VIEW_MATRIX * vec4(right, 0.0)).xyz;
	v_up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	v_to = (VIEW_MATRIX * vec4(to, 0.0)).xyz;
	NORMAL = v_to;
	v_tint = INSTANCE_CUSTOM.z;
}

void fragment() {
	vec4 c = texture(albedo_atlas, UV);
	// relais avec les vrais modèles (fondu tramé sur 6 m) et au loin
	float hash = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	if (c.a < 0.5 || v_dist < near_cut + hash * 6.0 - 3.0 || v_dist > far_cut - hash * 40.0) {
		discard;
	}
	vec3 n = texture(normal_atlas, UV).rgb * 2.0 - 1.0;
	NORMAL = normalize(v_right * n.x + v_up * n.y + v_to * n.z);
	ALBEDO = c.rgb * v_tint;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
