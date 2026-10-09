// Voiture en sprite pixel art (build_car_sprite.py) : quad toujours face à la caméra, avancé vers elle (le bas du
// sprite ne s'enfonce pas dans la route), case de l'atlas choisie par car.gd (angle, hauteur, braquage ; la page de
// l'atlas est la texture passée dans « atlas »), inclinaison de la caisse (roulis vu de la caméra), feux allumés la
// nuit et au freinage ; teinte selon l'heure (night). Sous la pluie : gouttes en pixel art sur les vitres (et quelques
// reflets sur la carrosserie), essuie-glace de la lunette arrière qui les chasse (cadre de la lunette : « rear »).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
#include "res://scripts/env.gdshaderinc"

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D feux : filter_nearest, repeat_disable;     // R feux arrière, V phares, B vitres
uniform vec2 grid = vec2(16.0, 12.0);
uniform vec2 frame = vec2(256.0, 218.0);  // pixels d'une case
uniform vec2 cell = vec2(0.0);          // colonne, ligne
uniform float roll = 0.0;               // rad, sens horaire à l'écran
uniform float push = 3.2;               // avance vers la caméra (m)
uniform float head = 0.0;               // phares 0 … 1
uniform float tail = 0.0;               // feux arrière 0 … 1 (2 = frein)
uniform float night = 0.0;
uniform float rain = 0.0;               // pluie qui tombe 0 … 1 (gouttes, essuie-glace en marche)
// déformations « dessin animé » (car.gd) : penché vers l'extérieur des virages, écrasé / étiré par les bosses
uniform float shear = 0.0;              // décalage du haut par rapport au bas (fraction de la hauteur)
uniform float squash = 0.0;             // > 0 : écrasé (plus bas, plus large), < 0 : étiré
uniform float half_h = 2.4;             // demi-hauteur du quad (m)
uniform vec4 rear = vec4(0.0);          // cadre de la lunette arrière (pixels de la case : x0, y0, x1, y1) ; vide : z <= x

const float WIPE_T = 2.6;               // aller-retour de l'essuie-glace arrière (s)
const float WIPE_A = 1.35;              // demi-angle balayé (rad) ; au repos : couché à gauche, au pied de la vitre
const float DROP_RATE = 0.4;            // renouvellement des gouttes (par seconde)

varying vec3 v_wp;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 c = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	float d = length(c);
	float k = max(d - min(push, d * 0.6), 0.3) / max(d, 0.001);
	vec2 q = VERTEX.xy;
	// déformations ancrées au bas de l'image (les roues restent au sol)
	float hb = q.y + half_h;
	q.y = -half_h + hb * (1.0 - squash);
	q.x = q.x * (1.0 + squash * 0.6) + shear * hb;
	float cr = cos(roll), sr = sin(roll);
	q = vec2(q.x * cr + q.y * sr, -q.x * sr + q.y * cr);
	vec3 v = c * k + vec3(q * k, 0.0);
	POSITION = PROJECTION_MATRIX * vec4(v, 1.0);
	v_wp = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec2 px = floor(clamp(UV, vec2(0.0), vec2(0.9999)) * frame);     // pixel de la case (y vers le bas)
	vec2 uv = (cell + (px + 0.5) / frame) / grid;
	vec4 a = texture(atlas, uv);
	if (a.a < 0.5) {
		discard;
	}
	vec3 f = texture(feux, uv).rgb;
	// lumière : plein jour ; doré au couchant ; bleu nuit éclairé par la lune
	vec3 tint = mix(vec3(1.0), vec3(1.0, 0.82, 0.68), clamp(night * 2.5, 0.0, 1.0) * step(night, 0.6));
	tint = mix(tint, vec3(0.30, 0.34, 0.5), smoothstep(0.5, 1.0, night));
	vec3 col = a.rgb * env_cloud(v_wp.xz);
	col = mix(col, col * 0.85, wet);
	float glass = step(0.5, f.b);

	// essuie-glace arrière : angle -A … +A … -A (cosinus) tant qu'il pleut, couché au repos sinon
	bool has_rear = rear.z > rear.x;
	vec2 pv = vec2(0.5 * (rear.x + rear.z), rear.w);                  // pivot : pied de la lunette, au milieu
	vec2 half_ext = max(vec2(0.5 * (rear.z - rear.x), rear.w - rear.y), vec2(1.0));
	float on = step(0.01, rain);
	float ph = fract(TIME / WIPE_T);
	float ang = -WIPE_A * mix(1.0, cos(6.2831853 * ph), on);
	vec2 qn = (px + 0.5 - pv) / half_ext;                              // repère de la lunette (ellipse -> cercle)
	bool in_rear = has_rear && glass > 0.5 && qn.y < 0.3 && length(qn) < 1.15;

	// gouttes : une par bloc de 4 × 4 pixels au plus, qui apparaît, reste, puis laisse la place
	if (rain > 0.0) {
		float sz = glass > 0.5 ? 4.0 : 7.0;
		vec2 b = floor(px / sz);
		float seed = h21(b + sz);
		float t = TIME * DROP_RATE + seed * 7.0;
		float slot = floor(t);
		float age = fract(t) / DROP_RATE;                              // âge de la goutte (s)
		float dens = glass > 0.5 ? 0.15 : 0.03;
		float there = step(h21(b + slot * 13.17), dens * rain);
		vec2 o = floor(vec2(h21(b + slot + 3.3), h21(b + slot + 5.7)) * (sz - 1.0));
		vec2 d = px - (b * sz + o);
		// lunette arrière : la goutte n'existe que si l'essuie-glace n'est pas passé dessus depuis qu'elle est tombée
		if (in_rear) {
			float pa = clamp(atan(qn.x, -qn.y) / WIPE_A, -1.0, 1.0);       // angle du pixel, -1 … 1
			float pp = acos(clamp(-pa, -1.0, 1.0)) / 6.2831853;            // phases de passage : pp et 1 - pp
			float since = min(fract(ph - pp), fract(ph - (1.0 - pp))) * WIPE_T;
			there *= step(age, since);
		}
		if (d == vec2(0.0)) {
			col = mix(col, vec3(0.78, 0.85, 0.95), 0.6 * there);          // reflet de la goutte
		} else if (glass > 0.5 && d == vec2(0.0, 1.0)) {
			col = mix(col, col * 0.45, there);                              // son ombre, juste dessous
		}
	}
	// bras de l'essuie-glace : trait sombre d'un pixel depuis le pivot
	if (in_rear) {
		vec2 dir = vec2(sin(ang), -cos(ang)) * half_ext;                  // bout du bras (pixels)
		float len = length(dir) * 0.95;
		vec2 u = dir / max(length(dir), 0.001);
		vec2 q = px + 0.5 - pv;
		float along = dot(q, u);
		float perp = abs(q.x * u.y - q.y * u.x);
		if (along > 0.0 && along < len && perp < 0.75) {
			col = vec3(0.035, 0.035, 0.045);
		}
	}
	col *= tint;
	col += f.g * head * vec3(1.6, 1.5, 1.25) + f.r * tail * vec3(1.4, 0.12, 0.08);
	ALBEDO = col;
}
