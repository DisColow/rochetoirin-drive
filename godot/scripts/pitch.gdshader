// Terrains de sport : surface (herbe tondue en bandes, synthétique, terre battue, résine, stabilisé, tartan) et tracés
// blancs calculés selon le sport. UV = position en mètres (x largeur, y longueur, centrées), UV2 = (longueur, largeur),
// COLOR = (type / 10, surface / 10, éclairé, 0).
shader_type spatial;
#include "res://scripts/env.gdshaderinc"

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float rect_line(vec2 p, vec2 c, vec2 hs) {
	vec2 d = abs(p - c) - hs;
	return abs(max(d.x, d.y) > 0.0 ? length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) : max(d.x, d.y));
}
float seg_line(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}
float circ_line(vec2 p, vec2 c, float r) {
	return abs(length(p - c) - r);
}

void fragment() {
	vec2 p = UV;                 // x : largeur, y : longueur
	float L = UV2.x, W = UV2.y;
	int typ = int(round(COLOR.r * 10.0));
	int surf = int(round(COLOR.g * 10.0));
	vec3 c;
	float rough = 0.85;
	float n = fract(sin(dot(floor(p * 7.0), vec2(12.9898, 78.233))) * 43758.5453);
	if (surf == 0) {
		float band = step(0.5, fract(p.y / 10.0));
		c = mix(vec3(0.22, 0.42, 0.14), vec3(0.27, 0.5, 0.17), band) * (0.92 + 0.12 * n);
	} else if (surf == 1) {
		c = vec3(0.2, 0.52, 0.2) * (0.95 + 0.06 * n);
	} else if (surf == 2) {
		c = vec3(0.74, 0.37, 0.19) * (0.9 + 0.14 * n);
	} else if (surf == 3) {
		c = typ == 3 ? vec3(0.14, 0.3, 0.52) : vec3(0.2, 0.42, 0.28);
		if (typ == 3 && (abs(p.x) > 5.49 || abs(p.y) > 11.89)) {
			c = vec3(0.2, 0.42, 0.28);
		}
		c *= 0.95 + 0.05 * n;
		rough = 0.6;
	} else if (surf == 5) {
		c = vec3(0.62, 0.2, 0.14) * (0.93 + 0.08 * n);
	} else {
		c = vec3(0.68, 0.6, 0.47) * (0.85 + 0.2 * n);
	}
	// tracés
	float d = 100.0;
	float hw = W * 0.5 - 1.0, hl = L * 0.5 - 1.0;
	if (typ == 1 || typ == 2) {
		d = min(d, rect_line(p, vec2(0.0), vec2(hw, hl)));
		d = min(d, seg_line(p, vec2(-hw, 0.0), vec2(hw, 0.0)));
		if (typ == 1) {
			float k = clamp(hl / 52.5, 0.4, 1.0);
			d = min(d, circ_line(p, vec2(0.0), 9.15 * k));
			for (int s = -1; s <= 1; s += 2) {
				float e = float(s) * hl;
				d = min(d, rect_line(p, vec2(0.0, e - float(s) * 8.25 * k), vec2(min(20.15 * k, hw), 8.25 * k)));
				d = min(d, rect_line(p, vec2(0.0, e - float(s) * 2.75 * k), vec2(9.15 * k, 2.75 * k)));
				d = min(d, length(p - vec2(0.0, e - float(s) * 11.0 * k)) - 0.12);
			}
			d = min(d, length(p) - 0.12);
		} else {
			for (int s = -1; s <= 1; s += 2) {
				d = min(d, seg_line(p, vec2(-hw, float(s) * (hl - 5.0)), vec2(hw, float(s) * (hl - 5.0))));
				d = min(d, seg_line(p, vec2(-hw, float(s) * hl * 0.6), vec2(hw, float(s) * hl * 0.6)));
			}
		}
	} else if (typ == 3) {
		d = min(d, rect_line(p, vec2(0.0), vec2(5.485, 11.885)));
		d = min(d, rect_line(p, vec2(0.0), vec2(4.115, 11.885)));
		for (int s = -1; s <= 1; s += 2) {
			d = min(d, seg_line(p, vec2(-4.115, float(s) * 6.4), vec2(4.115, float(s) * 6.4)));
			d = min(d, seg_line(p, vec2(0.0, float(s) * 11.885), vec2(0.0, float(s) * 11.6)));
		}
		d = min(d, seg_line(p, vec2(0.0, -6.4), vec2(0.0, 6.4)));
	} else if (typ == 4 || typ == 5) {
		d = min(d, rect_line(p, vec2(0.0), vec2(hw, hl)));
		d = min(d, seg_line(p, vec2(-hw, 0.0), vec2(hw, 0.0)));
		d = min(d, circ_line(p, vec2(0.0), 1.8));
		for (int s = -1; s <= 1; s += 2) {
			float e = float(s) * hl;
			if (typ == 4) {
				d = min(d, rect_line(p, vec2(0.0, e - float(s) * 2.9), vec2(2.45, 2.9)));
				float r3 = min(6.75, hw - 0.5);
				vec2 q = p - vec2(0.0, e - float(s) * 1.575);
				if (q.y * float(s) < 0.0) { d = min(d, abs(length(q) - r3)); }
			} else {
				vec2 q = p - vec2(0.0, e);
				if (q.y * float(s) < 0.0) { d = min(d, abs(length(q) - min(6.0, hw))); }
			}
		}
	}
	float fw = max(fwidth(d), 0.01);
	float line = 1.0 - smoothstep(0.05, 0.05 + fw * 1.5, d);
	c = mix(c, vec3(0.93, 0.93, 0.9), line * (typ == 6 || typ == 7 ? 0.0 : 0.95));
	ALBEDO = c * env_cloud(v_wp.xz) * (1.0 - 0.3 * wet);
	ROUGHNESS = mix(rough, 0.25, wet * 0.7);
}
