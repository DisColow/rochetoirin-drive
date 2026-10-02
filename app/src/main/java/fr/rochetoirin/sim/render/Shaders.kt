package fr.rochetoirin.sim.render

/** Sources GLSL ES 3.00. */
object Shaders {
    private const val HEADER = "#version 300 es\nprecision highp float;\n"

    /** Ciel, brouillard et éclairage communs. */
    private const val COMMON = """
uniform vec3 uCamPos;
uniform vec3 uSunDir;
const vec3 SUN = vec3(1.12, 1.03, 0.90);
const vec3 HAZE = vec3(0.68, 0.78, 0.89);
vec3 skyColor(vec3 d) {
    float t = clamp(d.y, 0.0, 1.0);
    vec3 zen = vec3(0.12, 0.32, 0.74);
    vec3 c = mix(HAZE, zen, pow(t, 0.42));
    float s = max(dot(d, uSunDir), 0.0);
    c += vec3(1.0, 0.86, 0.62) * (pow(s, 8.0) * 0.20 + pow(s, 90.0) * 0.30);   // halo de Mie autour du soleil
    c = mix(c, vec3(0.82, 0.86, 0.90), (1.0 - smoothstep(0.0, 0.10, t)) * 0.30);  // horizon laiteux
    if (d.y < 0.0) c = mix(HAZE, vec3(0.52, 0.58, 0.54), clamp(-d.y * 6.0, 0.0, 1.0));
    return c;
}
// étalonnage final : exposition, courbe filmique (ACES), légère saturation
vec3 grade(vec3 c) {
    c *= 0.86;
    c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    return clamp(mix(vec3(l), c, 0.97), 0.0, 1.0);
}
vec3 fogged(vec3 col, vec3 wpos) {
    vec3 v = wpos - uCamPos;
    float d = length(v);
    // voile atmosphérique (portée ~30 km) + brume de vallée qui épargne les sommets
    float haze = 1.0 - exp(-d / 26000.0);
    float mist = smoothstep(1500.0, 8000.0, d) * 0.42 * clamp(exp(-(wpos.y - 450.0) / 550.0), 0.0, 1.0);
    float f = clamp(haze + mist, 0.0, 1.0);
    vec3 dir = v / max(d, 0.001);
    vec3 fc = HAZE;
    fc += vec3(1.0, 0.85, 0.6) * pow(max(dot(dir, uSunDir), 0.0), 6.0) * 0.18;
    return grade(mix(col, fc, f));
}
float hash12(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
// ombres portées du soleil (ShadowMaps) : deux cascades, PCF matériel
uniform highp sampler2DShadow uShadow0;
uniform highp sampler2DShadow uShadow1;
uniform mat4 uShadowM0;
uniform mat4 uShadowM1;
uniform vec3 uShadowP;            // taille de texel cascade 0 (m), cascade 1 (m), activé
float pcf(highp sampler2DShadow s, vec3 c, float t) {
    float r = texture(s, c + vec3(-0.6, -0.6, 0.0) * t);
    r += texture(s, c + vec3(0.6, -0.6, 0.0) * t);
    r += texture(s, c + vec3(-0.6, 0.6, 0.0) * t);
    r += texture(s, c + vec3(0.6, 0.6, 0.0) * t);
    return r * 0.25;
}
float sunShadow(vec3 p, vec3 n) {
    if (uShadowP.z < 0.5) return 1.0;
    float ndl = clamp(dot(n, uSunDir), 0.0, 1.0);
    float off = 1.5 + 2.5 * (1.0 - ndl);
    vec4 c0 = uShadowM0 * vec4(p + n * uShadowP.x * off, 1.0);
    vec2 e0 = abs(c0.xy - 0.5) * 2.0;
    float s1 = 1.0;
    vec4 c1 = uShadowM1 * vec4(p + n * uShadowP.y * off, 1.0);
    vec2 e1 = abs(c1.xy - 0.5) * 2.0;
    float m1 = max(e1.x, e1.y);
    if (m1 < 1.0 && c1.z < 1.0) s1 = mix(pcf(uShadow1, c1.xyz, 1.0 / 2048.0), 1.0, smoothstep(0.8, 1.0, m1));
    float m0 = max(e0.x, e0.y);
    if (m0 < 1.0 && c0.z < 1.0) return mix(pcf(uShadow0, c0.xyz, 1.0 / 2048.0), s1, smoothstep(0.85, 1.0, m0));
    return s1;
}
vec3 lit(vec3 albedo, vec3 n, float shadow) {
    float diff = max(dot(n, uSunDir), 0.0) * shadow;
    vec3 amb = mix(vec3(0.30, 0.30, 0.24), vec3(0.42, 0.50, 0.62), n.y * 0.5 + 0.5);
    return albedo * (SUN * diff + amb);
}
"""

    // --------------------------------------------------------------------------- terrain
    const val TERRAIN_VS = HEADER + """
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aN;
uniform mat4 uVP;
out vec3 vPos;
out vec3 vN;
void main() {
    vPos = aPos; vN = aN;
    gl_Position = uVP * vec4(aPos, 1.0);
}
"""
    const val TERRAIN_FS = HEADER + COMMON + """
in vec3 vPos;
in vec3 vN;
uniform sampler2D uGrass;
uniform sampler2D uNoise;
uniform sampler2D uLand;      // occupation du sol (classe, orientation, aléa) — 4 m/px
uniform sampler2D uLandFar;   // forêts / eau / bâti de l'anneau lointain — 25 m/px
uniform vec4 uLandRect;       // x0, z0, largeur, hauteur (m)
uniform vec4 uFarRect;
uniform int uMode;            // 0 zone jouable, 1 anneau lointain, 2 panorama
uniform sampler2D uAO;        // occlusion ambiante du sol (pied des murs, sous les arbres), 2 m/px
out vec4 o;

vec3 grassCol(vec2 p, float dist) {
    vec3 g1 = texture(uGrass, p * 0.21).rgb;
    vec3 g2 = texture(uGrass, p * 0.047 + vec2(0.31, 0.71)).rgb;
    vec3 g = mix(g1, g2, clamp(dist / 90.0, 0.35, 0.8));
    vec4 m1 = texture(uNoise, p / 900.0);
    vec4 m2 = texture(uNoise, p / 170.0);
    g *= mix(vec3(0.78, 0.90, 0.74), vec3(1.20, 1.08, 0.80), smoothstep(0.25, 0.75, m1.g));
    g *= 0.92 * (0.86 + 0.28 * m2.b);
    // herbe des photos de Rochetoirin : vert olive, un peu jaune en été (moins saturée)
    float lum = dot(g, vec3(0.3, 0.55, 0.15));
    g = mix(vec3(lum), g, 0.72) * vec3(1.02, 0.97, 0.80);
    return g;
}

// Cultures de début d'été (RPG 2025), classes définies dans tools/prepare_decor.py
vec3 landColor(int c, vec2 p, float ang, float rnd, float dist, vec3 grass) {
    vec2 dir = vec2(cos(ang), sin(ang));
    float across = dot(p, vec2(-dir.y, dir.x));
    float along = dot(p, dir);
    float n1 = texture(uNoise, p * 0.04 + rnd).g;
    float n2 = texture(uNoise, p * 0.6).a;
    float near = 1.0 - smoothstep(60.0, 260.0, dist);
    vec3 col = grass;
    if (c == 0) {                                   // pré naturel fleuri
        col = grass * vec3(1.03, 1.0, 0.9);
        float fl = step(0.80, texture(uNoise, p * 1.9).a) * near;
        col = mix(col, mix(vec3(0.95, 0.85, 0.35), vec3(0.95, 0.95, 0.92), step(0.5, n2)), fl * 0.55);
    } else if (c == 1) {                            // pâture
        col = grass * vec3(0.94, 1.06, 0.88) * (0.9 + 0.2 * n1);
    } else if (c == 2) {                            // prairie fauchée (bandes de fauche)
        float st = step(0.5, fract(across / 7.5));
        col = grass * vec3(1.12, 1.07, 0.80) * (0.90 + 0.14 * st);
    } else if (c == 3 || c == 4) {                  // blé / orge mûrs
        vec3 base = c == 3 ? vec3(0.76, 0.64, 0.34) : vec3(0.83, 0.74, 0.46);
        base *= 0.82 + 0.28 * n1;
        float tram = fract(across / 24.0) * 24.0;
        float t = (1.0 - smoothstep(0.12, 0.32, abs(tram - 1.0))) + (1.0 - smoothstep(0.12, 0.32, abs(tram - 2.9)));
        col = mix(base, base * vec3(0.72, 0.70, 0.62), clamp(t, 0.0, 1.0) * near);
    } else if (c == 5 || c == 6 || c == 17) {       // maïs, tournesol, soja : rangs
        vec3 leaf = c == 5 ? vec3(0.25, 0.41, 0.12) : (c == 6 ? vec3(0.30, 0.44, 0.15) : vec3(0.33, 0.48, 0.18));
        vec3 soil = mix(vec3(0.36, 0.30, 0.21), leaf, 0.35);
        float rc = across / 0.76;
        float w = fwidth(rc);
        float row = fract(rc);
        float r = smoothstep(0.2 - w, 0.2 + w, row) * (1.0 - smoothstep(0.8 - w, 0.8 + w, row));
        float cover = c == 5 ? 0.75 : 0.62;
        float m = mix(mix(r, cover, 0.4), cover, clamp(w * 2.0 - 0.3, 0.0, 1.0));
        col = mix(soil, leaf * (0.85 + 0.3 * n2), m);
    } else if (c == 7) {                            // colza en siliques
        col = vec3(0.47, 0.51, 0.24) * (0.85 + 0.3 * n1);
    } else if (c == 8) {                            // jachère
        col = mix(grass * vec3(1.1, 1.0, 0.75), vec3(0.60, 0.56, 0.36), smoothstep(0.4, 0.7, n1) * 0.6);
    } else if (c == 9) {                            // terre labourée
        float f = fract(across / 0.9);
        col = vec3(0.42, 0.33, 0.24) * (0.85 + 0.2 * smoothstep(0.3, 0.7, f) * near);
    } else if (c == 10) {                           // sous-bois
        col = vec3(0.17, 0.21, 0.10) * (0.8 + 0.4 * n2);
    } else if (c == 11) {                           // pelouse de jardin
        col = vec3(0.32, 0.45, 0.19) * (0.9 + 0.15 * n2);
    } else if (c == 12) {                           // cour, parking, zone d'activité
        col = vec3(0.40, 0.40, 0.38) * (0.8 + 0.3 * n2);
    } else if (c == 13) {                           // gravier (cimetière, terrain)
        col = vec3(0.66, 0.64, 0.58) * (0.85 + 0.25 * n2);
    } else if (c == 14) {                           // gazon de stade
        float st = step(0.5, fract(along / 6.0));
        col = vec3(0.24, 0.50, 0.16) * (0.92 + 0.1 * st);
    } else if (c == 15) {                           // fond d'étang
        col = vec3(0.22, 0.25, 0.18);
    } else if (c == 16) {                           // pied de haie
        col = grass * 0.72;
    }
    return col;
}

// mosaïque de parcelles procédurale pour l'horizon
vec3 patchwork(vec2 p, vec3 grass) {
    vec2 q = mat2(0.94, 0.34, -0.34, 0.94) * p;
    vec2 cs = vec2(190.0, 120.0);
    vec2 id = floor(q / cs + vec2(0.0, floor(q.x / cs.x) * 0.37));
    float h = hash12(id);
    vec3 c = grass;
    if (h < 0.30) c = grass * vec3(0.95, 1.05, 0.9);
    else if (h < 0.45) c = grass * vec3(1.12, 1.07, 0.8);
    else if (h < 0.60) c = vec3(0.74, 0.63, 0.35);
    else if (h < 0.75) c = vec3(0.28, 0.40, 0.15);
    else if (h < 0.85) c = vec3(0.80, 0.72, 0.46);
    else c = mix(grass, vec3(0.55, 0.52, 0.34), 0.5);
    vec2 f = abs(fract(q / cs + vec2(0.0, floor(q.x / cs.x) * 0.37)) - 0.5);
    float edge = smoothstep(0.47, 0.5, max(f.x, f.y));
    return mix(c, vec3(0.16, 0.24, 0.10), edge * 0.6);
}

void main() {
    vec3 n = normalize(vN);
    vec2 p = vPos.xz;
    float dist = length(vPos - uCamPos);
    vec3 grass = grassCol(p, dist);
    vec3 g = grass;
    vec2 wob = (texture(uNoise, p * 0.07).rg - 0.5) * 6.0;
    if (uMode == 0) {
        vec2 uv = (p + wob - uLandRect.xy) / uLandRect.zw;
        vec4 lc = texture(uLand, uv);
        g = landColor(int(lc.r * 255.0 + 0.5), p, lc.g * 3.14159, lc.b, dist, grass);
    } else if (uMode == 1) {
        vec2 uv = (p + wob * 4.0 - uFarRect.xy) / uFarRect.zw;
        int c = int(texture(uLandFar, uv).r * 255.0 / 60.0 + 0.5);
        g = patchwork(p, grass);
        if (c == 1) g = vec3(0.14, 0.21, 0.09) * (0.75 + 0.5 * texture(uNoise, p * 0.02).a);
        else if (c == 2) g = vec3(0.24, 0.33, 0.38);
        else if (c == 3) g = mix(vec3(0.58, 0.38, 0.30), vec3(0.62, 0.61, 0.58), step(0.5, hash12(floor(p / 14.0))));
    } else {
        // panorama : étagement alpin (altitude réelle = y + courbure)
        float alt = vPos.y + dot(p, p) / (2.0 * 7.32e6);
        float nn = texture(uNoise, p * 0.0004).g;
        g = patchwork(p * 0.5, grass * 0.9);
        g = mix(g, vec3(0.13, 0.20, 0.10), smoothstep(700.0, 1000.0, alt + nn * 300.0));
        g = mix(g, vec3(0.36, 0.40, 0.26), smoothstep(1650.0, 1850.0, alt + nn * 200.0));
        g = mix(g, vec3(0.50, 0.49, 0.47), smoothstep(1950.0, 2200.0, alt + nn * 200.0) * (0.6 + 0.4 * (1.0 - n.y)));
        float snow = smoothstep(2350.0, 2600.0, alt + nn * 300.0 + n.y * 250.0);
        g = mix(g, vec3(0.93, 0.95, 0.98), snow);
    }
    float slope = 1.0 - n.y;
    g = mix(g, g * vec3(1.08, 0.96, 0.78), clamp(slope * 2.5, 0.0, 0.5) * (uMode == 2 ? 0.0 : 1.0));
    float sh = uMode == 0 ? sunShadow(vPos, n) : 1.0;
    float ao = uMode == 0 ? texture(uAO, (p - uLandRect.xy) / uLandRect.zw).r : 1.0;
    o = vec4(fogged(lit(g, n, sh) * mix(1.0, ao, 0.9), vPos), 1.0);
}
"""

    // --------------------------------------------------------------------------- routes
    const val ROAD_VS = HEADER + """
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aN;
layout(location = 2) in vec4 aR;   // latéral, abscisse, demi-largeur, style
uniform mat4 uVP;
out vec3 vPos;
out vec3 vN;
out vec4 vR;
void main() {
    vPos = aPos; vN = aN; vR = aR;
    gl_Position = uVP * vec4(aPos, 1.0);
}
"""
    const val ROAD_FS = HEADER + COMMON + """
in vec3 vPos;
in vec3 vN;
in vec4 vR;
uniform sampler2D uGrass;
uniform sampler2D uNoise;
uniform sampler2D uAO;
uniform vec4 uAORect;
out vec4 o;

float line(float x, float center, float w, float aa) {
    return 1.0 - smoothstep(w * 0.5 - aa, w * 0.5 + aa, abs(x - center));
}
float dash(float s, float period, float on) {
    float f = fract(s / period);
    float aa = max(fwidth(s) / period, 0.001);
    return smoothstep(0.0, aa, f) * (1.0 - smoothstep(on - aa, on, f));
}
float markings(float style, vec4 r) {
    float lat = r.x, s = r.y, hw = r.z;
    float aa = max(fwidth(lat) * 0.8, 0.01);
    float m = 0.0;
    if (style < 0.5) {
        if (hw > 4.0) {
            float left = -hw + 0.5;
            m = max(m, line(lat, left, 0.20, aa));
            for (int k = 1; k < 4; k++) {
                float c = left + 3.5 * float(k);
                if (c < hw - 3.2) m = max(m, line(lat, c, 0.15, aa) * dash(s, 52.0, 0.75));
            }
            m = max(m, line(lat, hw - 3.0, 0.22, aa) * dash(s, 52.0, 0.75));
        } else {
            m = max(m, line(lat, -hw + 0.35, 0.15, aa));
            m = max(m, line(lat, hw - 0.35, 0.15, aa));
        }
    } else if (style < 2.5) {
        m = max(m, line(lat, 0.0, 0.13, aa) * dash(s, 13.0, 3.0 / 13.0));
        m = max(m, line(lat, -hw + 0.3, 0.13, aa) * dash(s, 6.5, 3.0 / 6.5));
        m = max(m, line(lat, hw - 0.3, 0.13, aa) * dash(s, 6.5, 3.0 / 6.5));
    } else if (style < 3.5) {
        m = max(m, line(lat, 0.0, 0.12, aa) * dash(s, 13.0, 3.0 / 13.0));
    }
    return m;
}

vec3 asphalt(float base, vec2 p) {
    float n1 = texture(uNoise, p * 0.45).a;
    float n2 = texture(uNoise, p * 0.06).b;
    float n3 = texture(uNoise, p / 50.0).g;
    vec3 c = vec3(base, base, base * 1.04) * (0.80 + 0.32 * n1) * (0.85 + 0.25 * n2) * (0.9 + 0.18 * n3);
    float near = 1.0 - smoothstep(10.0, 45.0, length(uCamPos.xz - p));
    // granulats : grains clairs et sombres visibles de près
    float g = hash12(floor(p / 0.025));
    float gfade = 1.0 - smoothstep(0.25, 0.7, length(fwidth(p)) / 0.025);    // pas de moiré : grains plus petits qu'un pixel effacés
    c *= 1.0 + gfade * ((g > 0.93 ? 0.30 : 0.0) - (g < 0.06 ? 0.22 : 0.0));
    // rapiéçages : plaques d'enrobé plus récent (plus sombre)
    vec2 cell = floor(p / 11.0);
    if (hash12(cell) > 0.80) {
        vec2 f = fract(p / 11.0) - 0.5;
        vec2 sz = vec2(0.18 + 0.45 * hash12(cell + 3.1), 0.15 + 0.45 * hash12(cell + 5.7)) * 0.5;
        float inside = (1.0 - step(sz.x, abs(f.x))) * (1.0 - step(sz.y, abs(f.y)));
        c *= 1.0 - 0.2 * inside;
    }
    // fissures : lignes sinueuses (isoligne du bruit) dans les zones fatiguées
    float cr = texture(uNoise, p * 0.09).r;
    float w = fwidth(cr) * 1.2 + 1e-4;
    float crack = (1.0 - smoothstep(w * 0.5, w * 1.6, abs(cr - 0.5))) * smoothstep(0.55, 0.7, texture(uNoise, p * 0.013).g);
    c *= 1.0 - 0.45 * crack * (0.4 + 0.6 * near);
    return c;
}
// voie ferrée : rails (écartement 1,435 m) espacés de 4 m entre voies
float railMask(float lat, float hw, out float onTrack) {
    float tracks = max(1.0, floor((2.0 * hw - 3.4) / 4.0 + 0.5) + 1.0);
    float m = 0.0; onTrack = 0.0;
    for (int k = 0; k < 4; k++) {
        if (float(k) >= tracks) break;
        float c = (float(k) - (tracks - 1.0) * 0.5) * 4.0;
        float aa = max(fwidth(lat), 0.005);
        m = max(m, 1.0 - smoothstep(0.035 - aa, 0.035 + aa, abs(abs(lat - c) - 0.7175)));
        onTrack = max(onTrack, 1.0 - step(1.3, abs(lat - c)));
    }
    return m;
}

void main() {
    float raw = floor(vR.w + 0.5);
    bool disc = raw > 9.5 && raw < 19.5;
    float style = disc ? raw - 10.0 : raw;
    vec2 p = vPos.xz;
    vec3 n = normalize(vN);
    float n1 = texture(uNoise, p * 0.45).a;
    float n2 = texture(uNoise, p * 0.06).b;
    vec3 col;
    float lat = vR.x, along = vR.y, hw = vR.z;
    if (style > 29.5) {
        // marquages ponctuels (décalcomanies)
        vec3 white = vec3(0.92, 0.92, 0.90) * (0.92 + 0.08 * n1);
        if (style < 30.5) {                          // passage piéton (zébra)
            float f = fract((lat + hw) / 1.0);
            if (f < 0.25 || f > 0.75 || abs(lat) > hw - 0.25) discard;
            col = white;
        } else if (style < 31.5) {                   // ligne d'arrêt (STOP)
            col = white;
        } else if (style < 32.5) {                   // ligne « cédez le passage »
            if (fract(lat / 1.0) > 0.5) discard;
            col = white;
        } else {                                     // plateau / dos d'âne : rampe avec dents de requin
            col = asphalt(0.32, p);
            if (style < 33.5) {
                float f = abs(fract(lat / 1.1) - 0.5) * 2.0;
                if (along < 1.0 - f && abs(lat) < hw - 0.3) col = white;
            }
        }
    } else if (style > 26.5) {                       // passage à niveau : rails dans l'enrobé
        col = asphalt(0.30, p);
        float on;
        float r = railMask(lat, hw, on);
        col = mix(col, vec3(0.55, 0.55, 0.56), r);
        col = mix(col, col * 0.75, on * 0.3);
    } else if (style > 7.5) {
        col = vec3(0.56, 0.55, 0.52) * (0.85 + 0.25 * n1);
    } else if (style > 6.5) {                        // ballast, traverses béton, rails
        col = vec3(0.47, 0.44, 0.40) * (0.70 + 0.5 * n1) * (0.9 + 0.2 * n2);
        float on;
        float r = railMask(lat, hw, on);
        float sl = fract(along / 0.6);
        float aa = max(fwidth(along) / 0.6, 0.01);
        float sleeper = on * smoothstep(0.0, aa, sl) * (1.0 - smoothstep(0.36 - aa, 0.36, sl));
        col = mix(col, vec3(0.60, 0.58, 0.54) * (0.9 + 0.15 * n1), sleeper);
        col = mix(col, vec3(0.30, 0.22, 0.17), r * 0.5);
        col = mix(col, vec3(0.70, 0.70, 0.72), r * 0.7);
        float edge = smoothstep(hw - 0.6, hw, abs(lat));
        col = mix(col, texture(uGrass, p * 0.21).rgb * 0.9, edge * 0.7);
    } else if (style > 5.5) {
        // chemin de terre : bande herbeuse au centre et sur les bords
        col = vec3(0.50, 0.43, 0.33) * (0.72 + 0.5 * n1) * (0.88 + 0.24 * n2);
        vec3 gr = texture(uGrass, p * 0.21).rgb * vec3(0.95, 1.0, 0.9);
        float la = abs(lat);
        float mid = 1.0 - smoothstep(0.22 + 0.15 * n2, 0.5 + 0.1 * n1, la);
        float edge = smoothstep(hw - 0.55 - 0.2 * n2, hw - 0.05, la);
        col = mix(col, gr, max(mid * 0.9, edge * 0.85));
    } else {
        float base = style < 0.5 ? 0.30 : (style > 4.5 ? 0.37 : (style > 3.5 ? 0.34 : 0.31));
        col = asphalt(base, p);
        if (!disc) {
            // traces de roulement plus sombres et bords usés
            float la = abs(lat);
            if (style > 0.5 && hw > 2.4) {
                float track = smoothstep(0.5, 0.1, abs(la - hw * 0.5));
                col *= 1.0 - 0.07 * track;
            }
            col = mix(col, vec3(0.40, 0.38, 0.33), smoothstep(hw - 0.25 - 0.15 * n1, hw, la) * 0.6);
            col = mix(col, vec3(0.90, 0.90, 0.88) * (0.9 + 0.1 * n1), markings(style, vR) * 0.92);
        }
    }
    float sh = sunShadow(vPos, n);
    vec3 V = normalize(uCamPos - vPos);
    // léger lustre de l'enrobé au soleil rasant
    float sheen = pow(max(dot(n, normalize(uSunDir + V)), 0.0), 30.0) * 0.07 * sh * (style < 7.5 ? 1.0 : 0.3);
    float ao = texture(uAO, (vPos.xz - uAORect.xy) / uAORect.zw).r;
    o = vec4(fogged((lit(col, n, sh) + SUN * sheen) * mix(1.0, ao, 0.8), vPos), 1.0);
}
"""

    // --------------------------------------------------------------------------- ciel
    const val SKY_VS = HEADER + """
out vec2 vNdc;
void main() {
    vec2 p = vec2(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0);
    vNdc = p;
    gl_Position = vec4(p, 0.9999, 1.0);
}
"""
    const val SKY_FS = HEADER + COMMON + """
in vec2 vNdc;
uniform mat4 uInvVP;
uniform sampler2D uNoise;
uniform float uTime;
out vec4 o;
float cloudDensity(vec2 q) {
    float n = texture(uNoise, q * 0.16).r * 0.66 + texture(uNoise, q * 0.37 + 0.31).g * 0.26 + texture(uNoise, q * 0.9 + 0.7).b * 0.08;
    return (n - 0.5) * 2.8 + 0.5;      // le bruit fBm varie peu : on étire son contraste
}
void main() {
    vec4 w = uInvVP * vec4(vNdc, 1.0, 1.0);
    vec3 d = normalize(w.xyz / w.w - uCamPos);
    vec3 c = skyColor(d);
    float s = max(dot(d, uSunDir), 0.0);
    c += vec3(1.0, 0.95, 0.85) * smoothstep(0.9993, 0.9996, s) * 2.0;
    // cumulus de beau temps : couche plane projetée, éclairée côté soleil, base grise
    if (d.y > 0.0) {
        vec2 q = d.xz / (d.y + 0.06) + vec2(uTime * 0.004, uTime * 0.0016);
        float n = cloudDensity(q);
        float cov = smoothstep(0.52, 0.80, n);
        vec2 ts = normalize(uSunDir.xz + 1e-4) * 0.25;
        float n2 = cloudDensity(q + ts);
        float light = clamp(0.62 + (n - n2) * 5.0, 0.30, 1.0);
        vec3 cc = mix(vec3(0.60, 0.64, 0.72), vec3(1.02, 1.0, 0.96), light);
        cc += vec3(1.0, 0.9, 0.7) * pow(s, 10.0) * (1.0 - smoothstep(0.5, 0.9, n)) * 0.5;   // liseré argenté
        float fade = smoothstep(0.015, 0.20, d.y);
        cc = mix(cc, HAZE, 1.0 - smoothstep(0.0, 0.35, d.y));                                // perspective aérienne
        c = mix(c, cc, cov * fade * 0.92);
    }
    o = vec4(grade(c), 1.0);
}
"""

    // --------------------------------------------------------------------------- véhicule
    const val CAR_VS = HEADER + """
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aN;
layout(location = 2) in vec4 aCol;
layout(location = 3) in vec2 aUV;
uniform mat4 uVP;
uniform mat4 uModel;
out vec3 vPos;
out vec3 vN;
out vec4 vCol;
out vec2 vUV;
void main() {
    vec4 wp = uModel * vec4(aPos, 1.0);
    vPos = wp.xyz;
    vN = mat3(uModel) * aN;
    vCol = aCol; vUV = aUV;
    gl_Position = uVP * wp;
}
"""
    const val CAR_FS = HEADER + COMMON + """
in vec3 vPos;
in vec3 vN;
in vec4 vCol;
in vec2 vUV;
uniform sampler2D uPlates;
uniform float uBrake;
uniform float uSpeedo;
out vec4 o;
void main() {
    int m = int(vCol.a + 0.5);
    vec3 n = normalize(vN);
    bool inside = !gl_FrontFacing;
    if (inside) n = -n;
    vec3 V = normalize(uCamPos - vPos);
    vec3 base = vCol.rgb;
    float spec = 0.1, shin = 16.0, refl = 0.0, alpha = 1.0;
    vec3 emis = vec3(0.0);
    if (m == 0) {
        if (inside) { base = vec3(0.16, 0.16, 0.17); spec = 0.02; }
        else { spec = 0.7; shin = 90.0; refl = 0.10; }
    } else if (m == 1) {
        spec = 1.0; shin = 220.0;
        refl = inside ? 0.03 : 0.30;
        alpha = inside ? 0.12 : 0.86;
    } else if (m == 2) { spec = 0.2; shin = 30.0; refl = 0.03; }
    else if (m == 3) { spec = 1.0; shin = 70.0; refl = 0.55; }
    else if (m == 4) { spec = 0.05; shin = 8.0; }
    else if (m == 5) { spec = 1.0; shin = 120.0; refl = 0.35; emis = base * 0.12; }
    else if (m == 6) { spec = 0.8; shin = 90.0; refl = 0.15; emis = base * (0.15 + uBrake * 1.4); }
    else if (m == 7 || m == 8) { base = texture(uPlates, vUV).rgb; spec = 0.25; shin = 40.0; }
    else if (m == 9) { spec = 0.03; }
    else if (m == 10) { emis = vec3(0.05, 0.55, 0.45) * 0.6; spec = 0.6; shin = 100.0; }
    vec3 H = normalize(uSunDir + V);
    float sp = pow(max(dot(n, H), 0.0), shin) * spec * (max(dot(n, uSunDir), 0.0) > 0.0 ? 1.0 : 0.0);
    vec3 R = reflect(-V, n);
    vec3 env = skyColor(R);
    if (R.y < 0.0) env = mix(env, vec3(0.20, 0.26, 0.14), clamp(-R.y * 4.0, 0.0, 1.0));
    float fres = refl + (1.0 - refl) * pow(1.0 - max(dot(n, V), 0.0), 5.0) * (refl > 0.0 ? 0.6 : 0.0);
    float sh = sunShadow(vPos, n);
    vec3 c = lit(base, n, sh);
    c = mix(c, env, clamp(fres, 0.0, 1.0)) + SUN * sp * sh + emis;
    o = vec4(fogged(c, vPos), alpha);
}
"""

    // --------------------------------------------------------------------------- ombre portée
    const val SHADOW_VS = HEADER + """
uniform mat4 uVP;
uniform vec3 uCorners[4];
out vec2 vUV;
void main() {
    vec2 uv[4] = vec2[4](vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(1.0, 1.0), vec2(-1.0, 1.0));
    vUV = uv[gl_VertexID];
    gl_Position = uVP * vec4(uCorners[gl_VertexID], 1.0);
}
"""
    const val SHADOW_FS = HEADER + """
in vec2 vUV;
uniform float uAlpha;
out vec4 o;
void main() {
    vec2 q = abs(vUV);
    float d = length(max(q - vec2(0.55, 0.70), 0.0) / vec2(0.45, 0.30));
    float a = (1.0 - smoothstep(0.0, 1.0, d)) * uAlpha;
    o = vec4(0.0, 0.0, 0.0, a);
}
"""

    // --------------------------------------------------------------------------- balise
    const val MARKER_VS = HEADER + """
layout(location = 0) in vec3 aPos;
uniform mat4 uVP;
uniform vec4 uCenter;   // xyz + rayon
uniform float uHeight;
out float vH;
out vec3 vPos;
void main() {
    vH = aPos.y;
    vec3 p = uCenter.xyz + vec3(aPos.x * uCenter.w, aPos.y * uHeight, aPos.z * uCenter.w);
    vPos = p;
    gl_Position = uVP * vec4(p, 1.0);
}
"""
    const val MARKER_FS = HEADER + """
in float vH;
in vec3 vPos;
uniform vec4 uColor;
uniform float uTime;
out vec4 o;
void main() {
    float bands = 0.75 + 0.25 * sin(vPos.y * 1.2 - uTime * 4.0);
    float a = uColor.a * (1.0 - vH) * bands;
    o = vec4(uColor.rgb, a);
}
"""

    // --------------------------------------------------------------------------- décor (bâtiments, eau, pylônes)
    const val PROPS_VS = HEADER + """
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aN;
layout(location = 2) in vec3 aCol;
layout(location = 3) in vec2 aUV;
layout(location = 4) in vec2 aMat;   // matériau + graine, paramètre
uniform mat4 uVP;
out vec3 vPos; out vec3 vN; out vec3 vCol; out vec2 vUV; flat out vec2 vMat;
void main() {
    vPos = aPos; vN = aN; vCol = aCol; vUV = aUV; vMat = aMat;
    gl_Position = uVP * vec4(aPos, 1.0);
}
"""
    const val PROPS_FS = HEADER + COMMON + """
in vec3 vPos; in vec3 vN; in vec3 vCol; in vec2 vUV; flat in vec2 vMat;
uniform sampler2D uNoise;
uniform sampler2D uSigns;
uniform sampler2D uHedge;
uniform float uTime;
out vec4 o;
const vec3 SHUT[6] = vec3[6](vec3(0.42, 0.28, 0.18), vec3(0.86, 0.86, 0.83), vec3(0.66, 0.68, 0.68),
                             vec3(0.42, 0.53, 0.60), vec3(0.35, 0.47, 0.37), vec3(0.47, 0.17, 0.15));
void main() {
    int m = int(floor(vMat.x));
    float seed = fract(vMat.x);
    vec3 n = normalize(vN);
    if (!gl_FrontFacing && m != 6 && m != 11) n = -n;
    vec3 V = normalize(uCamPos - vPos);
    float dist = length(uCamPos - vPos);
    vec3 c = vCol;
    float spec = 0.05, shin = 16.0, refl = 0.0;
    float fade = 1.0 - smoothstep(250.0, 700.0, dist);   // détails qui disparaissent au loin
    if (m == 1 || m == 2 || m == 7) {
        float u = vUV.x, v = vUV.y;
        c *= 0.9 + 0.16 * texture(uNoise, vec2(u * 0.35, v * 0.35) + seed * 7.0).a;
        if (m == 1) {
            if (v < 0.45) c *= 0.78;                       // soubassement
            float floors = floor(vMat.y / 1000.0);
            float halfZ = mod(vMat.y, 1000.0);
            if (halfZ > 0.0 && abs(u) < halfZ && v > 0.0) {
                float cu = fract((u + halfZ) / 3.3);
                float fl = floor(v / 2.9), fv = fract(v / 2.9);
                // pas de fenêtre à chaque travée : on en saute certaines selon la graine
                float skip = step(0.78, hash12(vec2(floor((u + halfZ) / 3.3), fl) + seed * 13.0));
                if (fl < floors && fv > 0.30 && fv < 0.80 && skip < 0.5) {
                    vec3 sh = SHUT[int(seed * 6.0)];
                    if (cu > 0.33 && cu < 0.67) {
                        float frame = step(cu, 0.355) + step(0.645, cu) + step(fv, 0.325) + step(0.775, fv);
                        vec3 glass = mix(vec3(0.07, 0.09, 0.11), skyColor(reflect(-V, n)) * 0.6, 0.35);
                        vec3 w = frame > 0.0 ? vec3(0.85, 0.85, 0.82) : glass;
                        c = mix(c, w, fade + (1.0 - fade) * 0.45);
                        spec = frame > 0.0 ? 0.1 : 0.8; shin = 120.0;
                    } else if ((cu > 0.17 && cu < 0.33) || (cu > 0.67 && cu < 0.83)) {
                        float slat = 0.9 + 0.1 * step(0.5, fract(v * 9.0));
                        c = mix(c, sh * mix(1.0, slat, fade), fade + (1.0 - fade) * 0.3);
                    }
                }
            }
        } else if (m == 2) {
            c *= 0.92 + 0.08 * step(0.5, fract(u / 0.9)) * fade;   // bardage nervuré
            if (v < 0.4) c *= 0.7;
        } else {
            // pierre de taille de l'église
            float row = floor(v / 0.38);
            vec2 bl = vec2(fract(u / 0.62 + row * 0.5), fract(v / 0.38));
            float mortar = (step(bl.x, 0.04) + step(bl.y, 0.08)) * fade;
            c *= (0.88 + 0.2 * hash12(vec2(floor(u / 0.62 + row * 0.5), row))) * (1.0 - 0.25 * min(mortar, 1.0));
            // grandes baies en plein cintre sur la nef
            if (vMat.y < 1.0) {
                float cu = fract(u / 4.5);
                vec2 q = vec2((cu - 0.5) * 4.5, v - 4.6);
                bool arch = abs(q.x) < 0.45 && (q.y < 0.0 ? q.y > -2.4 : length(q) < 0.45);
                if (arch) { c = vec3(0.10, 0.10, 0.14); spec = 0.6; shin = 80.0; }
            }
        }
    } else if (m == 3) {                                   // tuiles canal / mécaniques
        float rv = fract(vUV.y / 0.30);
        float col = vUV.x / 0.24 + floor(vUV.y / 0.30) * 0.5;
        float tile = hash12(vec2(floor(col), floor(vUV.y / 0.30)) + seed * 3.0);
        float shade = mix(1.0, (0.78 + 0.22 * smoothstep(0.0, 0.35, rv)) * (0.9 + 0.2 * tile), fade);
        float dirt = texture(uNoise, vPos.xz * 0.08 + seed).g;
        c *= shade * (0.85 + 0.25 * dirt);
        spec = 0.12; shin = 20.0;
    } else if (m == 4) {                                   // bac acier
        c *= 0.9 + 0.1 * step(0.5, fract(vUV.x / 0.33)) * fade;
        spec = 0.35; shin = 40.0;
    } else if (m == 5) {
        c *= 0.85 + 0.25 * texture(uNoise, vPos.xz * 0.4).a;
    } else if (m == 6 || m == 11) {                        // eau
        vec2 r = texture(uNoise, vPos.xz * 0.045 + vec2(uTime * 0.010, uTime * 0.006)).rg
               + texture(uNoise, vPos.xz * 0.11 - vec2(uTime * 0.013, -uTime * 0.008)).ba - 1.0;
        float k = m == 11 ? 0.35 : 0.18;
        n = normalize(vec3(r.x * k, 1.0, r.y * k));
        vec3 R = reflect(-V, n);
        vec3 env = skyColor(R);
        float fres = 0.04 + 0.96 * pow(1.0 - max(dot(n, V), 0.0), 5.0);
        vec3 deep = m == 11 ? vec3(0.13, 0.17, 0.12) : vec3(0.06, 0.12, 0.13);
        vec3 col = mix(deep, env, clamp(fres + 0.15, 0.0, 1.0));
        vec3 H = normalize(uSunDir + V);
        col += vec3(1.0, 0.95, 0.85) * pow(max(dot(n, H), 0.0), 300.0) * 1.5;
        if (m == 11) {   // berges du ruisseau : fondu vers le bord
            float e = abs(vUV.y) / max(vMat.y, 0.1);
            col = mix(col, vec3(0.22, 0.27, 0.14), smoothstep(0.55, 1.0, e));
        }
        o = vec4(fogged(col, vPos), 1.0);
        return;
    } else if (m == 12) {                                  // trottoir en enrobé clair
        c *= (0.85 + 0.25 * texture(uNoise, vPos.xz * 0.5).a) * (0.92 + 0.12 * texture(uNoise, vPos.xz * 0.05).b);
    } else if (m == 13) {                                  // bordure béton
        c *= 0.9 + 0.15 * texture(uNoise, vPos.xz * 0.9 + vPos.y).a;
        float j = fract((vPos.x + vPos.z) / 1.0);
        c *= 1.0 - 0.25 * (step(j, 0.02) * fade);
    } else if (m == 14) {                                  // gazon des terre-pleins
        c *= 0.75 + 0.45 * texture(uNoise, vPos.xz * 0.7).a;
    } else if (m == 15) {                                  // panneaux (atlas)
        vec4 t = texture(uSigns, vUV);
        if (t.a < 0.5) discard;
        if (vMat.y > 0.5) t.rgb = vec3(0.55, 0.56, 0.58);   // dos du panneau
        vec3 H = normalize(uSunDir + V);
        vec3 col = t.rgb * (SUN * (max(dot(n, uSunDir), 0.0) * 0.7 + 0.3) + vec3(0.35, 0.38, 0.42));
        o = vec4(fogged(col, vPos), 1.0);
        return;
    } else if (m == 16) {                                  // lampe / feu allumé
        o = vec4(fogged(vCol * 1.3, vPos), 1.0);
        return;
    } else if (m == 17) {                                  // moellons de l'église : pierres irrégulières brunes et dorées
        float u = vUV.x, v = vUV.y;
        float row = floor(v / 0.28);
        float rh = hash12(vec2(row, 3.1));
        float su = u / (0.38 + 0.3 * rh) + rh * 5.0;
        vec2 id = vec2(floor(su), row);
        float h = hash12(id + seed * 11.0);
        vec2 f = vec2(fract(su), fract(v / 0.28));
        float mortar = max(1.0 - smoothstep(0.0, 0.07, min(f.x, 1.0 - f.x)), 1.0 - smoothstep(0.0, 0.12, min(f.y, 1.0 - f.y)));
        vec3 st = mix(vec3(0.40, 0.32, 0.24), vec3(0.66, 0.53, 0.34), h);
        st = mix(st, vec3(0.50, 0.48, 0.44), step(0.85, hash12(id * 1.7 + 0.3)));
        st *= 0.88 + 0.24 * texture(uNoise, vec2(u, v) * 0.8).a;
        c = mix(vec3(0.50, 0.42, 0.31), mix(st, vec3(0.62, 0.58, 0.50), mortar * 0.85), fade) * (vCol / 0.5);
        spec = 0.03;
    } else if (m == 18) {                                  // crépi taloché
        float n1 = texture(uNoise, vUV * 1.7 + seed * 5.0).a;
        float n2 = texture(uNoise, vUV * 0.09 + seed).g;
        c *= (0.93 + 0.1 * n1 * fade) * (0.95 + 0.08 * n2);
        c *= 1.0 - 0.12 * (1.0 - smoothstep(0.0, 0.6, vUV.y));   // salissures en pied de mur
    } else if (m == 19) {                                  // haie taillée (thuyas, lauriers) : feuillage dense
        // feuillage photographié sur un modèle 3D d'arbuste (Poly Haven, CC0), raccord sans couture ; uv en mètres
        vec2 hu = vUV / vec2(2.28, 1.78) + seed * 3.7;
        vec3 lf = pow(texture(uHedge, hu).rgb, vec3(2.2)) * vec3(0.80, 1.05, 0.85);
        float n1 = texture(uNoise, vPos.xz * 0.11 + vPos.y * 0.05).a;
        c = lf * clamp(c / vec3(0.24, 0.34, 0.16), 0.75, 1.3) * (0.85 + 0.3 * n1);
        spec = 0.04;
    } else if (m == 20) {                                  // gravier / gravillons
        float g1 = hash12(floor(vPos.xz / 0.035));
        float g2 = texture(uNoise, vPos.xz * 0.35).a;
        c *= (0.80 + 0.30 * mix(0.5, g1, fade)) * (0.90 + 0.18 * g2);
        spec = 0.02;
    } else if (m == 21) {                                  // clôtures ajourées : grillage (0), barreaudage (1), lames (2)
        vec2 q = vUV;
        float k = vMat.y;
        float keep;
        if (k < 0.5) {
            vec2 f = abs(fract(q / vec2(0.2, 0.05 + 0.15 * step(0.15, fract(q.y / 0.6)))) - 0.5);
            keep = step(0.465, max(f.x, f.y)) + step(q.y, 0.03) + step(fract(q.x / 2.5), 0.015);
        } else if (k < 1.5) {
            keep = step(0.62, fract(q.x / 0.12)) + step(q.y, 0.08);
        } else {
            keep = step(fract(q.y / 0.25), 0.62);
        }
        float cov = k < 0.5 ? 0.16 : (k < 1.5 ? 0.45 : 0.62);
        float blur = clamp(max(fwidth(q.x), fwidth(q.y)) * 12.0 - 0.6, 0.0, 1.0);   // au loin : tramage
        float a = mix(min(keep, 1.0), cov, blur);
        if (a < hash12(gl_FragCoord.xy * 0.73) * 0.98 + 0.01) discard;
        spec = 0.3; shin = 40.0;
    } else if (m == 8) { spec = 0.5; shin = 50.0; refl = 0.15; }
    else if (m == 9) { c = vec3(0.12); }
    else if (m == 10) { refl = 0.5; spec = 0.9; shin = 150.0; }
    vec3 H = normalize(uSunDir + V);
    float sh = sunShadow(vPos, n);
    vec3 col = lit(c, n, sh);
    if (refl > 0.0) col = mix(col, skyColor(reflect(-V, n)), refl);
    col += SUN * pow(max(dot(n, H), 0.0), shin) * spec * step(0.0, dot(n, uSunDir)) * sh;
    o = vec4(fogged(col, vPos), 1.0);
}
"""

    // --------------------------------------------------------------------------- herbe 3D
    /** Touffes instanciées sur une grille qui suit la caméra (positions stables, aléa par cellule). */
    const val GRASS_VS = HEADER + """
layout(location = 0) in vec3 aPos;           // carte : x -0,5..0,5, y 0..1, z = n° de carte (0, 1)
uniform mat4 uVP;
uniform vec3 uCamPos;
uniform float uTime;
uniform vec4 uGrid;                          // origine x, z (alignée), pas, n
uniform highp sampler2D uHeight;             // relief de la zone jouable (R32F)
uniform vec3 uHRect;                         // x0, z0, pas
uniform sampler2D uLand;                     // classes d'occupation du sol
uniform sampler2D uMask;                     // routes, trottoirs, bâtiments (blanc = pas d'herbe)
uniform vec4 uLandRect;
uniform sampler2D uGrass;
uniform sampler2D uNoise;
uniform float uRadius;
uniform sampler2D uAO;
out vec3 vPos; out vec3 vCol; out vec2 vUV;
float hashg(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float terrainH(vec2 p) {
    vec2 g = (p - uHRect.xy) / uHRect.z;
    ivec2 i = ivec2(floor(g)); vec2 f = g - vec2(i);
    float h00 = texelFetch(uHeight, i, 0).r, h10 = texelFetch(uHeight, i + ivec2(1, 0), 0).r;
    float h01 = texelFetch(uHeight, i + ivec2(0, 1), 0).r, h11 = texelFetch(uHeight, i + ivec2(1, 1), 0).r;
    return f.y >= f.x ? h00 + (h11 - h01) * f.x + (h01 - h00) * f.y : h00 + (h10 - h00) * f.x + (h11 - h10) * f.y;
}
void main() {
    int n = int(uGrid.w);
    vec2 cell = vec2(float(gl_InstanceID % n), float(gl_InstanceID / n));
    vec2 wc = uGrid.xy + cell * uGrid.z;
    float r1 = hashg(wc), r2 = hashg(wc + 17.31), r3 = hashg(wc + 41.73);
    vec2 p = wc + vec2(r1, r2) * uGrid.z;
    float d = length(p - uCamPos.xz);
    vec2 luv = (p - uLandRect.xy) / uLandRect.zw;
    vec2 wob = (texture(uNoise, p * 0.07).rg - 0.5) * 6.0;           // mêmes limites ondulées que le terrain
    int cls = int(texture(uLand, (p + wob - uLandRect.xy) / uLandRect.zw).r * 255.0 + 0.5);
    float mask = texture(uMask, luv).r;
    // classes de prepare_decor.py : 0 pré, 1 pâture, 2 fauché, 3 blé, 4 orge, 8 jachère, 11 jardin, 14 gazon, 16 pied de haie
    float hgt = 0.0;
    bool crop = cls == 3 || cls == 4;
    if (cls == 0) hgt = 0.42; else if (cls == 1) hgt = 0.26; else if (cls == 2) hgt = 0.15; else if (crop) hgt = 0.85;
    else if (cls == 8) hgt = 0.55; else if (cls == 11) hgt = 0.11; else if (cls == 14) hgt = 0.07; else if (cls == 16) hgt = 0.45;
    float fade = 1.0 - smoothstep(uRadius * 0.55, uRadius, d);
    float s = hgt * fade * (0.65 + 0.7 * r3) * (1.0 - step(0.5, mask));
    if (s < 0.025 || luv.x < 0.0 || luv.y < 0.0 || luv.x > 1.0 || luv.y > 1.0) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); vPos = vec3(0.0); vCol = vec3(0.0); vUV = vec2(0.0); return; }
    float a = r3 * 6.2832 + aPos.z * 1.5708;
    float w = crop ? 0.5 : s * 1.4 + 0.15;
    vec3 base = vec3(p.x, terrainH(p) - 0.03, p.y);
    vec3 q = base + vec3(cos(a) * aPos.x * w, aPos.y * s, sin(a) * aPos.x * w);
    // vent : les pointes oscillent, par rafales
    float gust = 0.6 + 0.4 * sin(uTime * 0.35 + p.x * 0.02);
    q.xz += vec2(0.8, 0.5) * aPos.y * aPos.y * s * 0.22 * gust * sin(uTime * 1.9 + p.x * 0.45 + p.y * 0.31);
    // couleur : celle du sol sous la touffe (même texture que le terrain), un peu plus claire en pointe
    vec3 g = texture(uGrass, p * 0.21).rgb;
    vec4 m1 = texture(uNoise, p / 900.0);
    g *= mix(vec3(0.78, 0.90, 0.74), vec3(1.20, 1.08, 0.80), smoothstep(0.25, 0.75, m1.g));
    float lum = dot(g, vec3(0.3, 0.55, 0.15));
    g = mix(vec3(lum), g, 0.72) * vec3(1.02, 0.97, 0.80);
    if (cls == 2) g *= vec3(1.12, 1.07, 0.80);
    if (cls == 11) g = vec3(0.32, 0.45, 0.19) * 1.05;        // mêmes teintes que le sol (landColor)
    if (cls == 14) g = vec3(0.24, 0.50, 0.16);
    if (crop) g = (cls == 3 ? vec3(0.76, 0.64, 0.34) : vec3(0.83, 0.74, 0.46)) * (0.85 + 0.3 * r1);
    if (cls == 8) g = mix(g, vec3(0.62, 0.56, 0.36), 0.4);
    vCol = g * (0.9 + 0.2 * r2) * mix(1.0, texture(uAO, luv).r, 0.9);
    vUV = vec2((aPos.x + 0.5) * 0.5 + (crop ? 0.5 : 0.0), aPos.y);
    vPos = q;
    gl_Position = uVP * vec4(q, 1.0);
}
"""
    const val GRASS_FS = HEADER + COMMON + """
in vec3 vPos; in vec3 vCol; in vec2 vUV;
uniform sampler2D uTuft;
out vec4 o;
void main() {
    vec4 t = texture(uTuft, vUV);
    if (t.a < 0.5) discard;
    vec3 n = vec3(0.0, 1.0, 0.0);
    float sh = sunShadow(vPos, n);
    vec3 c = vCol * (t.rgb / max(t.a, 0.01)) * (0.62 + 0.55 * vUV.y);    // pied des brins plus sombre
    float diff = clamp(dot(n, uSunDir) * 0.8 + 0.2, 0.0, 1.0) * sh;
    vec3 amb = vec3(0.36, 0.42, 0.46);
    vec3 col = c * (SUN * diff + amb);
    vec3 V = normalize(uCamPos - vPos);
    col += c * SUN * pow(max(dot(-V, uSunDir), 0.0), 3.0) * 0.35 * sh * vUV.y;   // brins à contre-jour
    o = vec4(fogged(col, vPos), 1.0);
}
"""

    // --------------------------------------------------------------------------- cartes d'ombre
    /** Occulteurs simples (arbres, voiture) : seule la profondeur compte. */
    const val DEPTH_FS = HEADER + """
out vec4 o;
void main() { o = vec4(1.0); }
"""
    /** Décor : pas d'ombre pour l'eau, les lampes et les clôtures ajourées (grillage). */
    const val PROPS_DEPTH_FS = HEADER + """
flat in vec2 vMat;
in vec2 vUV;
out vec4 o;
void main() {
    int m = int(floor(vMat.x));
    if (m == 6 || m == 11 || m == 16) discard;
    if (m == 21 && vMat.y < 0.5) discard;
    if (m == 21 && fract(vUV.x / 0.12) < 0.5 && vMat.y < 1.5) discard;
    o = vec4(1.0);
}
"""

    /** Arbres dans la carte d'ombre : les plaques de feuillage sont découpées (ombre ajourée). */
    const val TREE_DEPTH_FS = HEADER + """
in vec2 vUV; in float vCard;
uniform sampler2D uLeaf;
out vec4 o;
void main() {
    if (vCard > 0.5 && texture(uLeaf, vUV).a < 0.5) discard;
    o = vec4(1.0);
}
"""

    // --------------------------------------------------------------------------- arbres
    private const val TREE_PARAMS = """
// rayon du houppier / h, centre du houppier / h, étirement vertical, forme conique
const vec4 TP[6] = vec4[6](vec4(0.36, 0.58, 0.80, 0.0), vec4(0.52, 0.52, 0.78, 0.0), vec4(0.12, 0.60, 3.3, 0.0),
                           vec4(0.24, 0.56, 1.85, 1.0), vec4(0.44, 0.60, 0.80, 0.0), vec4(0.60, 0.45, 0.68, 0.0));
const vec3 TC[6] = vec3[6](vec3(0.19, 0.31, 0.10), vec3(0.21, 0.33, 0.11), vec3(0.27, 0.39, 0.13),
                           vec3(0.10, 0.20, 0.10), vec3(0.26, 0.39, 0.13), vec3(0.23, 0.34, 0.12));
"""
    const val TREE_VS = HEADER + TREE_PARAMS + """
layout(location = 0) in vec3 aPos;     // sphère unité (houppier) ou cylindre unité (tronc)
layout(location = 1) in vec3 aN;
layout(location = 2) in float aPart;   // 0 houppier, 1 tronc
layout(location = 3) in vec4 aI0;      // x, y, z, hauteur
layout(location = 4) in vec2 aI1;      // type, aléa
uniform mat4 uVP;
out vec3 vPos; out vec3 vN; out vec3 vCol; out float vAO; out float vTrunk; out vec2 vUV; out float vCard;
void main() {
    int t = int(aI1.x + 0.5);
    int corner = gl_VertexID & 3;
    vUV = vec2((corner == 1 || corner == 2) ? 1.0 : 0.0, corner >= 2 ? 1.0 : 0.0);
    vCard = (aPart > 0.45 && aPart < 0.75) ? 1.0 : 0.0;
    float rnd = aI1.y;
    float h = aI0.w;
    vec4 tp = TP[t];
    float R = tp.x * h, C = tp.y * h;
    float a = rnd * 6.2832;
    mat2 rot = mat2(cos(a), sin(a), -sin(a), cos(a));
    vec3 p;
    vec3 nn;
    if (aPart < 0.75) {
        vec3 q = aPos;
        float lump = 1.0 + 0.10 * sin(q.x * 5.1 + rnd * 31.0) * sin(q.y * 4.3 + rnd * 17.0) * sin(q.z * 4.9 + rnd * 7.0);
        float rs = 1.0;
        if (tp.w > 0.5) rs = (1.0 - (q.y + 1.0) * 0.5) * 1.35 + 0.04;   // cône (résineux)
        p = vec3(q.x * R * rs * lump, q.y * R * tp.z * lump + C, q.z * R * rs * lump);
        nn = normalize(vec3(aN.x / max(rs, 0.2), aN.y / tp.z, aN.z / max(rs, 0.2)));
        float lr = fract(aPart * 13.7 + rnd * 3.1);                 // nuance par touffe
        vCol = TC[t] * (0.78 + 0.44 * rnd) * vec3(0.94 + 0.12 * lr, 0.96 + 0.08 * lr, 0.92);
        vAO = clamp((q.y + 1.0) * 0.5 + 0.2, 0.0, 1.0) * clamp(0.45 + 0.6 * length(q), 0.0, 1.0);   // cœur du houppier plus sombre
        vTrunk = 0.0;
    } else {
        float tr = 0.03 * h + 0.06;
        p = vec3(aPos.x * tr, aPos.y * C * 1.02, aPos.z * tr);
        nn = aN;
        vCol = vec3(0.30, 0.26, 0.21);
        vAO = 0.7;
        vTrunk = 1.0;
    }
    p.xz = rot * p.xz;
    nn.xz = rot * nn.xz;
    vPos = aI0.xyz + p - vec3(0.0, 0.25, 0.0);
    vN = nn;
    gl_Position = uVP * vec4(vPos, 1.0);
}
"""
    const val TREE_FS = HEADER + COMMON + """
in vec3 vPos; in vec3 vN; in vec3 vCol; in float vAO; in float vTrunk; in vec2 vUV; in float vCard;
uniform sampler2D uNoise;
uniform sampler2D uLeaf;
out vec4 o;
void main() {
    vec3 n = normalize(vN);
    vec3 V = normalize(uCamPos - vPos);
    float leaf = texture(uNoise, vPos.xz * 1.9 + vPos.y * 1.3).a;
    float leaf2 = texture(uNoise, vPos.xy * 0.8 + vPos.z * 0.6).b;
    float dist = length(uCamPos - vPos);
    vec3 lt = vec3(1.0);
    if (vCard > 0.5) {
        vec4 lf = texture(uLeaf, vUV);
        if (lf.a < 0.5) discard;
        lt = lf.rgb / max(lf.a, 0.01) * 1.05;
        leaf = 0.55; leaf2 = 0.5;
    } else if (vTrunk < 0.5 && dist < 90.0) {
        // silhouette feuillue : les bords rasants des touffes sont découpés selon un motif de feuilles
        float rim = 1.0 - abs(dot(n, V));
        if (rim > 0.55 && leaf * leaf2 * 4.0 < (rim - 0.55) * 3.2) discard;
    }
    vec3 c = vTrunk > 0.5 ? vCol : vCol * lt * (0.55 + 0.75 * leaf) * (0.85 + 0.3 * leaf2);
    float sh = sunShadow(vPos, n);
    float ndl = dot(n, uSunDir);
    float diff = (vTrunk > 0.5 ? max(ndl, 0.0) : clamp((ndl + 0.35) / 1.35, 0.0, 1.0)) * sh;   // éclairage enveloppant du feuillage
    vec3 amb = mix(vec3(0.28, 0.29, 0.22), vec3(0.40, 0.48, 0.60), n.y * 0.5 + 0.5);
    vec3 col = c * (SUN * diff * 0.85 + amb) * (0.42 + 0.58 * vAO);
    // contre-jour : la lumière traverse les feuilles
    if (vTrunk < 0.5) col += c * SUN * pow(max(dot(-V, uSunDir), 0.0), 4.0) * 0.5 * (0.35 + 0.65 * sh);
    o = vec4(fogged(col, vPos), 1.0);
}
"""
    // --------------------------------------------------------------------------- arbres en imposteurs
    // Modèles 3D (Poly Haven, CC0) photographiés sous 8 angles : couleur + normale + profondeur par vue.
    const val IMP_VS = HEADER + """
layout(location = 0) in vec2 aCorner;  // x : -1..1, y : 0..1
layout(location = 3) in vec4 aI0;      // x, y, z, hauteur
layout(location = 4) in vec2 aI1;      // 6 + modèle (0-3 feuillus, 4-5 arbustes, 6-7 résineux) + (rayon / hauteur) / 2, aléa
uniform mat4 uVP;
uniform vec3 uCamPos;
uniform vec3 uFaceDir;                 // passe d'ombre : direction du soleil (sinon caméra)
uniform float uDirMode;
uniform vec4 uImp[8];                  // côté de cellule / H, rayon / H du modèle
out vec2 vUV0; out vec2 vUV1; out float vBlend; out vec3 vPos; out vec3 vTo; out vec2 vRot; out float vDepthScale; out float vRnd;
void main() {
    float t = floor(aI1.x);
    int mi = clamp(int(t) - 6, 0, 7);
    float wr = fract(aI1.x) * 2.0;     // rayon du houppier / hauteur (orthophoto)
    float h = aI0.w;
    vec4 P = uImp[mi];
    float sy = h;                                        // une unité « H du modèle » = h mètres
    float sx = clamp(wr * h / max(P.y, 0.05), 0.75 * h, 1.35 * h);
    vec3 to = uDirMode > 0.5 ? uFaceDir : uCamPos - aI0.xyz;
    to.y = 0.0;
    to = normalize(to + vec3(1e-4, 0.0, 0.0));
    float yaw = aI1.y * 6.2832;
    float c = cos(yaw), s = sin(yaw);
    vRot = vec2(c, s);
    // direction de vue dans le repère du modèle
    vec2 tl = vec2(c * to.x + s * to.z, -s * to.x + c * to.z);
    float th = atan(tl.x, tl.y);
    if (th < 0.0) th += 6.2832;
    float f = th / 6.2832 * 8.0;
    float i0 = floor(f);
    vBlend = f - i0;
    float i1 = mod(i0 + 1.0, 8.0); i0 = mod(i0, 8.0);
    vec2 cuv = vec2(aCorner.x * 0.5 + 0.5, 1.0 - aCorner.y);
    vUV0 = vec2((i0 + cuv.x) / 8.0, (float(mi) + cuv.y) / 8.0);
    vUV1 = vec2((i1 + cuv.x) / 8.0, (float(mi) + cuv.y) / 8.0);
    vec3 right = vec3(to.z, 0.0, -to.x);
    vPos = aI0.xyz + right * (aCorner.x * P.x * sx * 0.5) + vec3(0.0, aCorner.y * P.x * sy - 0.15, 0.0);
    vTo = to;
    vDepthScale = P.x * sx * 0.75;     // profondeur atlas (0..1) -> mètres le long de la vue
    vRnd = aI1.y;
    gl_Position = uVP * vec4(vPos, 1.0);
}
"""
    const val IMP_FS = HEADER + COMMON + """
in vec2 vUV0; in vec2 vUV1; in float vBlend; in vec3 vPos; in vec3 vTo; in vec2 vRot; in float vDepthScale; in float vRnd;
uniform sampler2D uImpCol;
uniform sampler2D uImpNrm;
out vec4 o;
void main() {
    vec4 c0 = texture(uImpCol, vUV0), c1 = texture(uImpCol, vUV1);
    float a = mix(c0.a, c1.a, vBlend);
    if (a < 0.5) discard;
    // une vue seule quand l'autre est transparente (pas de feuillage fantôme)
    vec4 cc = c0.a < 0.3 ? c1 : (c1.a < 0.3 ? c0 : mix(c0, c1, vBlend));
    vec4 n0 = texture(uImpNrm, vUV0), n1 = texture(uImpNrm, vUV1);
    vec4 nd = c0.a < 0.3 ? n1 : (c1.a < 0.3 ? n0 : mix(n0, n1, vBlend));
    vec3 nm = normalize(nd.rgb * 2.0 - 1.0);
    vec3 n = normalize(vec3(vRot.x * nm.x - vRot.y * nm.z, nm.y, vRot.y * nm.x + vRot.x * nm.z));
    float front = clamp((nd.a - 0.30) / 0.42, 0.0, 1.0);          // 1 = devant (exposé), 0 = cœur du houppier
    vec3 p = vPos + vTo * (nd.a - 0.5) * 2.0 * vDepthScale;
    vec3 alb = pow(cc.rgb, vec3(2.2)) * 2.8 * (0.9 + 0.2 * vRnd);
    bool wood = cc.r > cc.g * 1.02;
    float sh = sunShadow(p, n);
    float ndl = dot(n, uSunDir);
    float diff = (wood ? max(ndl, 0.0) : clamp((ndl + 0.35) / 1.35, 0.0, 1.0)) * sh;
    vec3 amb = mix(vec3(0.28, 0.29, 0.22), vec3(0.40, 0.48, 0.60), n.y * 0.5 + 0.5);
    float ao = 0.45 + 0.55 * front;
    vec3 col = alb * (SUN * diff * 0.85 + amb * ao);
    vec3 V = normalize(uCamPos - p);
    if (!wood) col += alb * SUN * pow(max(dot(-V, uSunDir), 0.0), 4.0) * 0.45 * (0.35 + 0.65 * sh);
    o = vec4(fogged(col, p), 1.0);
}
"""
    const val IMP_DEPTH_FS = HEADER + """
in vec2 vUV0; in vec2 vUV1; in float vBlend; in vec3 vPos; in vec3 vTo; in vec2 vRot; in float vDepthScale; in float vRnd;
uniform sampler2D uImpCol;
out vec4 o;
void main() {
    if (texture(uImpCol, vBlend < 0.5 ? vUV0 : vUV1).a < 0.5) discard;
    o = vec4(1.0);
}
"""
    const val BILLBOARD_VS = HEADER + TREE_PARAMS + """
layout(location = 0) in vec2 aCorner;  // x : -1..1, y : 0..1
layout(location = 3) in vec4 aI0;
layout(location = 4) in vec2 aI1;
uniform mat4 uVP;
uniform vec3 uCamPos;
out vec2 vQ; out vec4 vP; out vec3 vCol; out vec3 vPos; out vec3 vRight; out vec3 vTo; out float vRnd;
void main() {
    int t = int(aI1.x + 0.5);
    float h = aI0.w;
    vec4 tp = TP[t];
    float R = tp.x * h, C = tp.y * h;
    float halfW = R * (tp.w > 0.5 ? 1.4 : 1.12);
    float top = C + R * tp.z * 1.1;
    vec3 to = uCamPos - aI0.xyz; to.y = 0.0;
    to = normalize(to + vec3(1e-4));
    vec3 right = vec3(to.z, 0.0, -to.x);
    vQ = vec2(aCorner.x * halfW, aCorner.y * top);
    vP = vec4(R, C, tp.z, tp.w);
    vCol = TC[t] * (0.78 + 0.44 * aI1.y);
    vRnd = aI1.y;
    vRight = right; vTo = to;
    vPos = aI0.xyz + right * vQ.x + vec3(0.0, vQ.y - 0.25, 0.0);
    gl_Position = uVP * vec4(vPos, 1.0);
}
"""
    const val BILLBOARD_FS = HEADER + COMMON + """
in vec2 vQ; in vec4 vP; in vec3 vCol; in vec3 vPos; in vec3 vRight; in vec3 vTo; in float vRnd;
uniform sampler2D uNoise;
out vec4 o;
void main() {
    float R = vP.x, C = vP.y;
    vec2 d;
    float r;
    if (vP.w > 0.5) {
        float y01 = (vQ.y - (C - R * vP.z)) / (2.0 * R * vP.z);
        float w = max(1.0 - y01, 0.0) * 1.35 * R + 0.04 * R;
        d = vec2(vQ.x / max(w, 0.01), (y01 - 0.5) * 2.0);
        r = max(abs(d.x), abs(d.y));
    } else {
        d = vec2(vQ.x / R, (vQ.y - C) / (R * vP.z));
        r = length(d);
    }
    float edge = texture(uNoise, vQ * 0.25 + vRnd * 9.0).a;
    bool crown = r + (edge - 0.5) * 0.35 < 1.0;
    bool trunk = abs(vQ.x) < 0.05 * C + 0.06 && vQ.y < C && !crown;
    if (!crown && !trunk) discard;
    vec3 col;
    if (crown) {
        vec2 dd = clamp(d, -1.0, 1.0);
        float z = sqrt(max(0.0, 1.0 - dot(dd, dd)));
        vec3 n = normalize(vRight * dd.x + vec3(0.0, dd.y, 0.0) + vTo * z);
        float leaf = texture(uNoise, vQ * 0.6 + vRnd * 3.0).a;
        float diff = max(dot(n, uSunDir), 0.0) * 0.75 + 0.25;
        vec3 amb = mix(vec3(0.30, 0.30, 0.24), vec3(0.42, 0.50, 0.62), n.y * 0.5 + 0.5);
        float ao = clamp(0.5 + 0.5 * dd.y + 0.25, 0.0, 1.0);
        col = vCol * (0.72 + 0.5 * leaf) * (SUN * diff * 0.9 + amb) * (0.55 + 0.45 * ao);
    } else {
        col = vec3(0.30, 0.26, 0.21) * 0.8;
    }
    o = vec4(fogged(col, vPos), 1.0);
}
"""
}
