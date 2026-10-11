"""Interface façon tableau de bord des années 80, en pixel art : gros boutons poussoirs de planche de bord (cadre de
plastique noir, touche bombée, témoin orange, pictogramme rétroéclairé ; bouton rouge des feux de détresse pour la
remise sur la route), cadres des panneaux et touches des menus, polices (Pixelify Sans pour les textes, DSEG7 pour
l'afficheur à cristaux liquides du compteur ; licence SIL OFL).
Les textures sont dessinées pixel par pixel puis agrandies sans lissage (× S) : affichées à leur taille, sans flou.
Sorties : ../godot/assets/ui/*.png, polices, theme.tres (thème du projet : gui/theme/custom), apercu.png (planche)."""
import os, shutil, urllib.request
import numpy as np
from PIL import Image

OUT = "../godot/assets/ui"
RAW = "data/ui"
FONTS = {
    "pixel.ttf": "https://raw.githubusercontent.com/google/fonts/main/ofl/pixelifysans/PixelifySans%5Bwght%5D.ttf",
    "lcd.ttf": "https://cdn.jsdelivr.net/npm/dseg@0.46.0/fonts/DSEG7-Classic/DSEG7Classic-Bold.ttf",
}
S = 4          # agrandissement des boutons de la planche
SP = 3         # agrandissement des cadres et touches des menus


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


# ---------------------------------------------------------------- pictogrammes (# = trait rétroéclairé)
ICONS = {
    "camera": [
        "...........",
        "..####.....",
        ".#######.##",
        ".#.....####",
        ".#.###.####",
        ".#.###.####",
        ".#.....####",
        ".#######.##",
        "...........",
    ],
    "replacer": [  # triangle des feux de détresse
        ".....#.....",
        "....#.#....",
        "....#.#....",
        "...#.#.#...",
        "...#.#.#...",
        "..#.###.#..",
        "..#.###.#..",
        ".#.#####.#.",
        ".#.......#.",
        "###########",
    ],
    "carte": [  # repère de position
        "....###....",
        "...#####...",
        "..###.###..",
        "..##...##..",
        "..###.###..",
        "...#####...",
        "...#####...",
        "....###....",
        ".##..#..##.",
        "...#####...",
    ],
    "reglages": [
        "....###....",
        ".##.#.#.##.",
        ".#########.",
        "..##...##..",
        "###.....###",
        "#.#.....#.#",
        "###.....###",
        "..##...##..",
        ".#########.",
        ".##.#.#.##.",
        "....###....",
    ],
    "activites": [  # drapeau à damier
        "#.........",
        "##########",
        "#.##..##.#",
        "#.##..##.#",
        "##..##..##",
        "##..##..##",
        "##########",
        "#.........",
        "#.........",
        "#.........",
    ],
    "parler": [  # bulle de conversation (taxi)
        ".#########.",
        "###########",
        "##.##.##.##",
        "###########",
        ".#########.",
        "..###......",
        "..##.......",
        "..#........",
    ],
    "radio": [
        ".....#####",
        "...###...#",
        "...#.....#",
        "...#.....#",
        "...#..####",
        ".###.#####",
        "####..###.",
        "####......",
        ".##.......",
    ],
}


def rrect(w, h, r):
    """Masque d'un rectangle aux coins arrondis en escalier (rayon r pixels)."""
    m = np.ones((h, w), bool)
    for k in range(r):
        cut = r - k - (1 if k else 0)
        cut = max(r - int(round(np.sqrt(max(r * r - (r - k - 0.5) ** 2, 0)))), 0)
        m[k, :cut] = m[k, w - cut:] = False
        m[h - 1 - k, :cut] = m[h - 1 - k, w - cut:] = False
    return m


def outline(m):
    e = np.zeros_like(m)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        e |= np.roll(m, (dy, dx), (0, 1)) & ~m
    return e


def up(img, k):
    return np.repeat(np.repeat(img, k, 0), k, 1)


def dash_button(icon, pressed, led=None, red=False):
    """Bouton poussoir de planche de bord, 28 × 24 pixels. led : None (pas de témoin), False (éteint), True (allumé)."""
    W, H = 28, 24
    img = np.zeros((H, W, 4), np.uint8)
    frame = rrect(W - 2, H - 2, 3)
    fm = np.zeros((H, W), bool); fm[1:H - 1, 1:W - 1] = frame
    img[outline(fm)] = hexc("050507")
    # cadre : plastique noir grainé, éclairé d'en haut
    for y in range(H):
        t = y / H
        c = np.array(hexc("2a2a31")) * (1 - t) + np.array(hexc("141418")) * t
        row = fm[y]
        img[y, row] = c.astype(np.uint8)
    img[2, 4:W - 4][fm[2, 4:W - 4]] = hexc("3c3c45")
    # logement de la touche (creux sombre)
    x0, x1, y0, y1 = 4, W - 5, 4, H - 5
    img[y0:y1 + 1, x0:x1 + 1] = hexc("07070a")
    # touche : bombée, avec ombre portée ; enfoncée : descend d'un pixel, plus sombre
    dy = 1 if pressed else 0
    cy0, cy1 = y0 + dy, y1 - 1 + dy
    cx0, cx1 = x0 + 1, x1 - 1
    if red:
        top, mid, low, hi, sh = "d6403a", "b62a24", "8e1c18", "f07a64", "5a0e0c"
    else:
        top, mid, low, hi, sh = "4a4a54", "3c3c45", "30303a", "6a6a76", "1c1c22"
    k = 0.82 if pressed else 1.0
    def kc(h):
        c = hexc(h)
        return (int(c[0] * k), int(c[1] * k), int(c[2] * k), 255)
    for y in range(cy0, cy1 + 1):
        t = (y - cy0) / max(cy1 - cy0, 1)
        img[y, cx0:cx1 + 1] = kc(top if t < 0.3 else (mid if t < 0.75 else low))
    img[cy0, cx0 + 1:cx1] = kc(hi)                       # arête haute éclairée
    img[cy0:cy1, cx0] = kc(top)
    img[cy1, cx0:cx1 + 1] = kc(sh)                       # arête basse dans l'ombre
    img[cy0 + 1:cy1 + 1, cx1] = kc(sh)
    for (yy, xx) in ((cy0, cx0), (cy0, cx1), (cy1, cx0), (cy1, cx1)):
        img[yy, xx] = hexc("07070a")
    # témoin
    ic_top = cy0 + 2
    if led is not None:
        lx = (cx0 + cx1) // 2 - 2
        if led:
            img[cy0 + 2, lx:lx + 4] = hexc("ffb02e")
            img[cy0 + 2, lx + 1] = hexc("fff0b0")
            img[cy0 + 1, lx:lx + 4] = (np.array(img[cy0 + 1, lx:lx + 4], float) * 0.5 + np.array(hexc("ff9a20")) * 0.5).astype(np.uint8)
        else:
            img[cy0 + 2, lx:lx + 4] = hexc("3e2a10")
        ic_top = cy0 + 4
    # pictogramme
    pat = ICONS[icon]
    ih, iw = len(pat), len(pat[0])
    avail = cy1 - 1 - ic_top
    py = ic_top + max((avail - ih) // 2, 0)
    px = (cx0 + cx1 + 1) // 2 - iw // 2
    col = hexc("fff6e6") if red else hexc("e8dcc0")
    if pressed:
        col = tuple(int(c * 0.85) for c in col[:3]) + (255,)
    for j, line in enumerate(pat):
        for i, ch in enumerate(line):
            if ch == "#" and 0 <= py + j < cy1:
                img[py + j, px + i] = col
    return up(img, S)


def panel():
    """Cadre des panneaux (9 tranches) : plastique sombre, liseré clair en haut, coins en escalier. 16 × 16."""
    n = 16
    img = np.zeros((n, n, 4), np.uint8)
    m = np.zeros((n, n), bool); m[1:n - 1, 1:n - 1] = rrect(n - 2, n - 2, 3)
    img[m] = hexc("15161b", 236)
    img[outline(m)] = hexc("040405", 250)
    inner = m & ~outline(~m)
    edge_in = m & ~inner
    img[edge_in] = hexc("2c2d35", 245)
    img[2, 3:n - 3] = hexc("4a4b56", 250)                # liseré haut
    img[n - 3, 3:n - 3] = hexc("0a0a0d", 245)
    return up(img, SP)


def key(state):
    """Touche des menus (9 tranches), 16 × 14 : normal, survol, enfoncée, active (témoin orange), désactivée."""
    w, h = 16, 14
    img = np.zeros((h, w, 4), np.uint8)
    m = np.zeros((h, w), bool); m[0:h, 0:w] = rrect(w, h, 2)
    img[outline(~m) & m] = hexc("050507")
    cap = m.copy()
    cap[outline(~m) & m] = False
    pressed = state in ("pressed", "on")
    base = {"normal": "34343c", "hover": "40404a", "pressed": "26262c", "on": "2a2a30", "disabled": "202024"}[state]
    for y in range(h):
        t = y / h
        c = np.array(hexc(base), float) * (1.12 - 0.3 * t)
        img[y, cap[y]] = np.clip(c, 0, 255).astype(np.uint8)
    if not pressed:
        img[1, 2:w - 2] = hexc("5c5c68" if state != "disabled" else "2c2c32")
        img[h - 2, 2:w - 2] = hexc("16161a")
        img[h - 3, 2:w - 2] = hexc("1c1c22")
    else:
        img[1, 2:w - 2] = hexc("121216")
        img[h - 2, 2:w - 2] = hexc("3a3a42")
    if state == "on":                                    # témoin allumé sous le texte
        img[h - 3, 4:w - 4] = hexc("ffb02e")
        img[h - 4, 5:w - 5] = hexc("8a5a14")
    return up(img, SP)


def repere():
    """Repère de l'objet sélectionné par l'éditeur de monde : épingle orange, 12 × 16."""
    pat = ["...######...", "..########..", ".###....###.", ".##......##.", ".##......##.", ".###....###.",
           "..########..", "...######...", "....####....", ".....##.....", ".....##.....", ".....#......"]
    h, w = 16, 12
    img = np.zeros((h, w, 4), np.uint8)
    m = np.zeros((h, w), bool)
    for j, line in enumerate(pat):
        for i, ch in enumerate(line):
            m[j + 2, i] = ch == "#"
    img[outline(m)] = hexc("1a0f04")
    img[m] = hexc("ffb02e")
    img[3, 4:7][m[3, 4:7]] = hexc("fff0b0")
    return up(img, S)


def theme():
    t = '''[gd_resource type="Theme" load_steps=12 format=3]

[ext_resource type="FontFile" path="res://assets/ui/pixel.ttf" id="1"]
[ext_resource type="Texture2D" path="res://assets/ui/panneau.png" id="2"]
[ext_resource type="Texture2D" path="res://assets/ui/touche_normal.png" id="3"]
[ext_resource type="Texture2D" path="res://assets/ui/touche_hover.png" id="4"]
[ext_resource type="Texture2D" path="res://assets/ui/touche_pressed.png" id="5"]
[ext_resource type="Texture2D" path="res://assets/ui/touche_on.png" id="6"]
[ext_resource type="Texture2D" path="res://assets/ui/touche_disabled.png" id="7"]

'''
    m = 5 * SP
    def sbt(i, tex, cm, extra=""):
        return ('[sub_resource type="StyleBoxTexture" id="%s"]\ntexture = ExtResource("%s")\n'
                'texture_margin_left = %d\ntexture_margin_top = %d\ntexture_margin_right = %d\ntexture_margin_bottom = %d\n'
                'content_margin_left = %d\ncontent_margin_top = %d\ncontent_margin_right = %d\ncontent_margin_bottom = %d\n%s\n'
                % (i, tex, m, m, m, m, cm[0], cm[1], cm[0], cm[2], extra))
    t += sbt("panel", "2", (38, 24, 24))
    t += sbt("k_n", "3", (22, 10, 14))
    t += sbt("k_h", "4", (22, 10, 14))
    t += sbt("k_p", "5", (22, 12, 12))
    t += sbt("k_on", "6", (22, 10, 16))
    t += sbt("k_d", "7", (22, 10, 14))
    t += '''[resource]
default_font = ExtResource("1")
Button/colors/font_color = Color(0.91, 0.87, 0.78, 1)
Button/colors/font_hover_color = Color(1, 0.96, 0.86, 1)
Button/colors/font_pressed_color = Color(1, 0.75, 0.32, 1)
Button/colors/font_hover_pressed_color = Color(1, 0.8, 0.4, 1)
Button/colors/font_focus_color = Color(0.91, 0.87, 0.78, 1)
Button/colors/font_disabled_color = Color(0.5, 0.48, 0.44, 1)
Button/styles/normal = SubResource("k_n")
Button/styles/hover = SubResource("k_h")
Button/styles/pressed = SubResource("k_on")
Button/styles/hover_pressed = SubResource("k_on")
Button/styles/disabled = SubResource("k_d")
Button/styles/focus = SubResource("k_h")
Label/colors/font_color = Color(0.93, 0.9, 0.83, 1)
PanelContainer/styles/panel = SubResource("panel")
Panel/styles/panel = SubResource("panel")
'''
    open(OUT + "/theme.tres", "w").write(t)


def main():
    os.makedirs(OUT, exist_ok=True); os.makedirs(RAW, exist_ok=True)
    for fn, u in FONTS.items():
        raw = os.path.join(RAW, fn)
        if not os.path.exists(raw):
            open(raw, "wb").write(urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"}), timeout=120).read())
        shutil.copy(raw, os.path.join(OUT, fn))
    sheet = []
    for icon in ICONS:
        red = icon == "replacer"
        led = icon in ("radio", "activites")
        row = []
        for pressed in (False, True):
            for lit in ((False, True) if led else (None,)):
                im = dash_button(icon, pressed, lit, red)
                sfx = ("_p" if pressed else "") + ("_on" if lit else "")
                Image.fromarray(im, "RGBA").save("%s/btn_%s%s.png" % (OUT, icon, sfx))
                row.append(im)
        sheet.append(np.concatenate(row + [np.zeros_like(row[0])] * (4 - len(row)), 1))
    Image.fromarray(panel(), "RGBA").save(OUT + "/panneau.png")
    Image.fromarray(repere(), "RGBA").save(OUT + "/repere.png")
    for st in ("normal", "hover", "pressed", "on", "disabled"):
        Image.fromarray(key(st), "RGBA").save(OUT + "/touche_%s.png" % st)
    theme()
    sh = np.concatenate(sheet, 0)
    bg = np.zeros(sh.shape, np.uint8); bg[..., :3] = (96, 120, 90); bg[..., 3] = 255
    a = sh[..., 3:4] / 255.0
    Image.fromarray((sh[..., :3] * a + bg[..., :3] * (1 - a)).astype(np.uint8)).save(RAW + "/apercu.png")
    print("interface :", len(os.listdir(OUT)), "fichiers")


if __name__ == "__main__":
    main()
