// Étalonnage de l'image finale (calque 2D au-dessus de la scène, sous l'interface) : netteté légère, courbe en S douce,
// ombres un peu froides, hautes lumières un peu chaudes, vignette. Lit l'image déjà tonalisée : aucun assombrissement
// parasite.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float sharpen = 0.35;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c = texture(screen_tex, uv).rgb;
	vec3 blur = (texture(screen_tex, uv + vec2(px.x, 0)).rgb + texture(screen_tex, uv - vec2(px.x, 0)).rgb
		+ texture(screen_tex, uv + vec2(0, px.y)).rgb + texture(screen_tex, uv - vec2(0, px.y)).rgb) * 0.25;
	c += (c - blur) * sharpen;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, c * c * (3.0 - 2.0 * c), 0.15);
	c += vec3(-0.010, 0.0, 0.014) * (1.0 - smoothstep(0.0, 0.45, l));
	c += vec3(0.016, 0.007, -0.010) * smoothstep(0.55, 1.0, l);
	vec2 q = uv - 0.5;
	c *= 1.0 - 0.18 * smoothstep(0.35, 0.85, length(q * vec2(1.25, 1.0)));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
